namespace GDiagram {
    public class ERDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public ERDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ERDiagram diagram) {
            var sb = new StringBuilder();
            sb.append("digraph G {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  fontname=\"Sans\";\n");
            sb.append("  node [style=\"filled\", fontname=\"Sans\", fontsize=11, shape=record];\n");
            sb.append("  edge [fontname=\"Sans\", fontsize=10];\n");

            // Title
            if (diagram.title != null) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=16;\n");
            }

            // Render entities
            sb.append("\n  // Entities\n");
            string entity_fill = diagram.skin_params.get_element_property("entity", "BackgroundColor") ?? "#FEFECE";
            string entity_border = diagram.skin_params.get_element_property("entity", "BorderColor") ?? "#A80036";

            foreach (var entity in diagram.entities) {
                string id = entity.get_dot_id();
                string fill = entity.color ?? entity_fill;

                // Build record label
                var label_parts = new StringBuilder();
                label_parts.append("{");
                label_parts.append(RenderUtils.escape_label(entity.get_display_name()));

                if (entity.attributes.size > 0) {
                    label_parts.append("|");

                    bool first = true;
                    bool in_separator = false;

                    foreach (var attr in entity.attributes) {
                        if (!first && !in_separator) {
                            label_parts.append("\\l");
                        }
                        first = false;
                        in_separator = false;

                        label_parts.append(RenderUtils.escape_label(attr.get_display_text()));
                    }

                    if (!first) {
                        label_parts.append("\\l");
                    }
                }

                label_parts.append("}");

                sb.append("  %s [label=\"%s\", style=filled, fillcolor=\"%s\", color=\"%s\"];\n".printf(
                    id, label_parts.str, fill, entity_border));
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";

                foreach (var note in diagram.notes) {
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"];\n".printf(
                        note.id, RenderUtils.escape_label(note.text), note_color));

                    if (note.attached_to != null) {
                        var target = diagram.find_entity(note.attached_to);
                        if (target != null) {
                            sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                note.id, target.get_dot_id()));
                        }
                    }
                }
            }

            // Render relationships
            sb.append("\n  // Relationships\n");
            foreach (var rel in diagram.relationships) {
                var from = diagram.find_entity(rel.from_entity);
                var to = diagram.find_entity(rel.to_entity);

                if (from == null || to == null) continue;

                string from_id = from.get_dot_id();
                string to_id = to.get_dot_id();
                string style = rel.is_dashed ? "dashed" : "solid";

                // Cardinality decorations
                string arrowtail = get_er_cardinality_arrow(rel.from_cardinality);
                string arrowhead = get_er_cardinality_arrow(rel.to_cardinality);

                if (rel.label != null && rel.label.length > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s, arrowhead=%s, arrowtail=%s, dir=both];\n".printf(
                        from_id, to_id, RenderUtils.escape_label(rel.label), style, arrowhead, arrowtail));
                } else {
                    sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=%s, dir=both];\n".printf(
                        from_id, to_id, style, arrowhead, arrowtail));
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        private string get_er_cardinality_arrow(ERCardinality card) {
            switch (card) {
                case ERCardinality.ONE_TO_ONE:
                    return "tee";
                case ERCardinality.ONE_TO_MANY:
                    return "crowodot";
                case ERCardinality.MANY_TO_ONE:
                    return "crowodot";
                case ERCardinality.MANY_TO_MANY:
                    return "crowodot";
                case ERCardinality.ZERO_OR_ONE:
                    return "teeodot";
                case ERCardinality.ZERO_OR_MANY:
                    return "crowodot";
                case ERCardinality.ONE_MANDATORY:
                    return "tee";
                case ERCardinality.MANY_MANDATORY:
                    return "crow";
                default:
                    return "none";
            }
        }

        public uint8[]? render_to_svg(ERDiagram diagram) {
            string dot = generate_dot(diagram);

            try {
                string tmp_dot = "/tmp/gplantuml_er.dot";
                string tmp_svg = "/tmp/gplantuml_er.svg";

                FileUtils.set_contents(tmp_dot, dot);

                string[] argv = {layout_engine, "-Tsvg", "-o", tmp_svg, tmp_dot};
                int exit_status;
                Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

                if (exit_status != 0) {
                    warning("Graphviz returned error %d", exit_status);
                    return null;
                }

                string svg_content;
                FileUtils.get_contents(tmp_svg, out svg_content);

                return svg_content.data;
            } catch (Error e) {
                warning("Failed to render ER diagram: %s", e.message);
                return null;
            }
        }

        public Cairo.ImageSurface? render_to_surface(ERDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                // Build element lines map for click-to-source
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var entity in diagram.entities) {
                    if (entity.source_line > 0) {
                        element_lines.set(entity.name, entity.source_line);
                        element_lines.set(entity.get_dot_id(), entity.source_line);
                        if (entity.alias != null) {
                            element_lines.set(entity.alias, entity.source_line);
                        }
                    }
                }
                foreach (var note in diagram.notes) {
                    if (note.source_line > 0) {
                        element_lines.set(note.id, note.source_line);
                    }
                }
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, (int)width, (int)height);

                return surface;
            } catch (Error e) {
                warning("Failed to create surface from SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(ERDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(ERDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                FileUtils.set_contents(filename, (string)svg_data);
                return true;
            } catch (Error e) {
                warning("Failed to write SVG: %s", e.message);
                return false;
            }
        }

        public bool export_to_pdf(ERDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.PdfSurface(filename, width, height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                surface.finish();

                return surface.status() == Cairo.Status.SUCCESS;
            } catch (Error e) {
                warning("Failed to export PDF: %s", e.message);
                return false;
            }
        }
    }
}
