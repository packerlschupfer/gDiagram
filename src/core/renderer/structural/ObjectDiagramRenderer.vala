namespace GDiagram {
    public class ObjectDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public ObjectDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ObjectDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values
            string bg_color = diagram.skin_params.background_color ?? "white";
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = diagram.skin_params.default_font_color ?? "black";

            sb.append("digraph object {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [fontname=\"%s\", fontsize=%s, fontcolor=\"%s\", shape=record];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9];\n".printf(font_name));

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
            }

            sb.append("\n");

            // Get object colors from theme
            string obj_color = diagram.skin_params.get_element_property("object", "BackgroundColor") ?? "#FEFECE";
            string obj_border = diagram.skin_params.get_element_property("object", "BorderColor") ?? "#A80036";

            // Render objects
            sb.append("  // Objects\n");
            foreach (var obj in diagram.objects) {
                string id = obj.get_id();
                string fill = obj.color ?? obj_color;

                // Build record label
                var label_parts = new StringBuilder();
                label_parts.append("{");
                label_parts.append(RenderUtils.escape_label(obj.get_display_label()));

                if (obj.fields.size > 0) {
                    label_parts.append("|");
                    bool first = true;
                    foreach (var field in obj.fields) {
                        if (!first) {
                            label_parts.append("\\l");
                        }
                        label_parts.append(RenderUtils.escape_label(field.name));
                        label_parts.append(" = ");
                        label_parts.append(RenderUtils.escape_label(field.value));
                        first = false;
                    }
                    label_parts.append("\\l");
                }

                label_parts.append("}");

                sb.append("  %s [label=\"%s\", style=filled, fillcolor=\"%s\", color=\"%s\"];\n".printf(
                    id, label_parts.str, fill, obj_border));
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";

                foreach (var note in diagram.notes) {
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"];\n".printf(
                        note.id, RenderUtils.escape_label(note.text), note_color));

                    if (note.attached_to != null) {
                        var target = diagram.find_object(note.attached_to);
                        if (target != null) {
                            sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                note.id, target.get_id()));
                        }
                    }
                }
            }

            // Render links
            sb.append("\n  // Links\n");
            foreach (var link in diagram.links) {
                var from = diagram.find_object(link.from_id);
                var to = diagram.find_object(link.to_id);

                if (from == null || to == null) continue;

                string from_id = from.get_id();
                string to_id = to.get_id();
                string style = link.is_dashed ? "dashed" : "solid";
                string arrowhead = "vee";
                string arrowtail = "none";

                switch (link.link_type) {
                    case ObjectLinkType.AGGREGATION:
                        arrowtail = "odiamond";
                        break;
                    case ObjectLinkType.COMPOSITION:
                        arrowtail = "diamond";
                        break;
                    case ObjectLinkType.DEPENDENCY:
                        style = "dashed";
                        break;
                    default:
                        break;
                }

                if (link.label != null && link.label.length > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s, arrowhead=%s, arrowtail=%s, dir=both];\n".printf(
                        from_id, to_id, RenderUtils.escape_label(link.label), style, arrowhead, arrowtail));
                } else {
                    sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=%s, dir=both];\n".printf(
                        from_id, to_id, style, arrowhead, arrowtail));
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        public uint8[]? render_to_svg(ObjectDiagram diagram) {
            string dot = generate_dot(diagram);

            try {
                string tmp_dot = "/tmp/gplantuml_object.dot";
                string tmp_svg = "/tmp/gplantuml_object.svg";

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
                warning("Failed to render object diagram: %s", e.message);
                return null;
            }
        }

        public Cairo.ImageSurface? render_to_surface(ObjectDiagram diagram) {
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
                foreach (var obj in diagram.objects) {
                    if (obj.source_line > 0) {
                        element_lines.set(obj.name, obj.source_line);
                        element_lines.set(obj.get_id(), obj.source_line);
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

        public bool export_to_png(ObjectDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(ObjectDiagram diagram, string filename) {
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

        public bool export_to_pdf(ObjectDiagram diagram, string filename) {
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
