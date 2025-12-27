namespace GDiagram {
    public class UseCaseDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public UseCaseDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(UseCaseDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values with defaults
            string bg_color = diagram.skin_params.background_color ?? "#FAFAFA";
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = diagram.skin_params.default_font_color ?? "#424242";

            sb.append("digraph usecase {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [style=\"filled\", fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9];\n".printf(font_name));
            sb.append("  compound=true;\n");

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
            }

            sb.append("\n");

            // Render actors (stick figures or simple shapes)
            string actor_color = diagram.skin_params.get_element_property("actor", "BackgroundColor") ?? "#FEFECE";
            string actor_border = diagram.skin_params.get_element_property("actor", "BorderColor") ?? "#A80036";

            sb.append("  // Actors\n");
            foreach (var actor in diagram.actors) {
                string id = RenderUtils.sanitize_id(actor.get_id());
                string label = actor.name;
                string fill = actor.color ?? actor_color;
                // Use a simple shape for actors - stick figure would require custom SVG
                sb.append("  %s [label=\"%s\", shape=ellipse, style=filled, fillcolor=\"%s\", color=\"%s\"];\n".printf(
                    id, RenderUtils.escape_label(label), fill, actor_border));
            }

            // Render use cases
            string uc_color = diagram.skin_params.get_element_property("usecase", "BackgroundColor") ?? "#FEFECE";
            string uc_border = diagram.skin_params.get_element_property("usecase", "BorderColor") ?? "#A80036";

            sb.append("\n  // Use Cases\n");
            foreach (var uc in diagram.use_cases) {
                string id = RenderUtils.sanitize_id(uc.get_id());
                string label = uc.name;
                string fill = uc.color ?? uc_color;
                sb.append("  %s [label=\"%s\", shape=ellipse, style=filled, fillcolor=\"%s\", color=\"%s\"];\n".printf(
                    id, RenderUtils.escape_label(label), fill, uc_border));
            }

            // Render packages/rectangles as clusters
            string pkg_color = diagram.skin_params.get_element_property("package", "BackgroundColor") ?? "#FEFECE";
            string pkg_border = diagram.skin_params.get_element_property("package", "BorderColor") ?? "#000000";
            string rect_color = diagram.skin_params.get_element_property("rectangle", "BackgroundColor") ?? "#FFFFFF";
            string rect_border = diagram.skin_params.get_element_property("rectangle", "BorderColor") ?? "#000000";

            int cluster_idx = 0;
            foreach (var pkg in diagram.packages) {
                string container_name = pkg.container_type == UseCaseContainerType.RECTANGLE ? "Rectangle" : "Package";
                string fill_color = pkg.container_type == UseCaseContainerType.RECTANGLE ? rect_color : pkg_color;
                string border_color = pkg.container_type == UseCaseContainerType.RECTANGLE ? rect_border : pkg_border;

                sb.append("\n  // %s: %s\n".printf(container_name, pkg.name));
                sb.append("  subgraph cluster_%d {\n".printf(cluster_idx));
                sb.append("    label=\"%s\";\n".printf(RenderUtils.escape_label(pkg.name)));

                if (pkg.container_type == UseCaseContainerType.RECTANGLE) {
                    // Rectangle: system boundary style
                    sb.append("    style=\"filled\";\n");
                    sb.append("    fillcolor=\"%s\";\n".printf(fill_color));
                    sb.append("    color=\"%s\";\n".printf(border_color));
                    sb.append("    penwidth=2;\n");
                } else {
                    // Package: tab style (simulated with filled)
                    sb.append("    style=filled;\n");
                    sb.append("    fillcolor=\"%s\";\n".printf(fill_color));
                    sb.append("    color=\"%s\";\n".printf(border_color));
                }
                sb.append("\n");

                // Actors in container
                foreach (var actor in pkg.actors) {
                    string id = RenderUtils.sanitize_id(actor.get_id());
                    string label = actor.name;
                    string fill = actor.color ?? actor_color;
                    sb.append("    %s [label=\"%s\", shape=ellipse, style=filled, fillcolor=\"%s\", color=\"%s\"];\n".printf(
                        id, RenderUtils.escape_label(label), fill, actor_border));
                }

                // Use cases in container
                foreach (var uc in pkg.use_cases) {
                    string id = RenderUtils.sanitize_id(uc.get_id());
                    string label = uc.name;
                    string fill = uc.color ?? uc_color;
                    sb.append("    %s [label=\"%s\", shape=ellipse, style=filled, fillcolor=\"%s\", color=\"%s\"];\n".printf(
                        id, RenderUtils.escape_label(label), fill, uc_border));
                }

                sb.append("  }\n");
                cluster_idx++;
            }

            // Render notes
            string note_color = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(note.text), note_color));

                    if (note.attached_to != null) {
                        string target_id = RenderUtils.sanitize_id(note.attached_to);
                        sb.append("  %s -> %s [style=dotted, arrowhead=none];\n".printf(note_id, target_id));
                    }
                }
            }

            // Render relationships
            sb.append("\n  // Relationships\n");
            foreach (var rel in diagram.relationships) {
                string from_id = RenderUtils.sanitize_id(rel.from_id);
                string to_id = RenderUtils.sanitize_id(rel.to_id);

                string style = rel.is_dashed ? "dashed" : "solid";
                string arrowhead = "vee";

                // Handle different relationship types
                switch (rel.relation_type) {
                    case UseCaseRelationType.INCLUDE:
                        style = "dashed";
                        break;
                    case UseCaseRelationType.EXTEND:
                        style = "dashed";
                        break;
                    case UseCaseRelationType.GENERALIZATION:
                        arrowhead = "empty";
                        break;
                    default:
                        break;
                }

                if (rel.label != null && rel.label.length > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s, arrowhead=%s];\n".printf(
                        from_id, to_id, RenderUtils.escape_label(rel.label), style, arrowhead));
                } else {
                    sb.append("  %s -> %s [style=%s, arrowhead=%s];\n".printf(
                        from_id, to_id, style, arrowhead));
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        public uint8[]? render_to_svg(UseCaseDiagram diagram) {
            string dot = generate_dot(diagram);

            try {
                string tmp_dot = "/tmp/gplantuml_usecase.dot";
                string tmp_svg = "/tmp/gplantuml_usecase.svg";

                FileUtils.set_contents(tmp_dot, dot);

                string[] argv = {layout_engine, "-Tsvg", "-o", tmp_svg, tmp_dot};
                int exit_status;
                Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

                if (exit_status != 0) {
                    warning("dot command failed with status %d", exit_status);
                    return null;
                }

                uint8[] svg_data;
                FileUtils.get_data(tmp_svg, out svg_data);
                return svg_data;
            } catch (Error e) {
                warning("Failed to render use case diagram: %s", e.message);
                return null;
            }
        }

        public Cairo.ImageSurface? render_to_surface(UseCaseDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            string svg_str = (string) svg_data;
            if (svg_str != null && svg_str.length > 0) {
                svg_str = svg_str.replace("<text ", "<text xml:space=\"preserve\" ");
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_str.data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                // Build element line number map from actors and use cases
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var actor in diagram.actors) {
                    if (actor.source_line > 0) {
                        element_lines.set(actor.name, actor.source_line);
                        if (actor.alias != null) {
                            element_lines.set(actor.alias, actor.source_line);
                        }
                    }
                }
                foreach (var uc in diagram.use_cases) {
                    if (uc.source_line > 0) {
                        element_lines.set(uc.name, uc.source_line);
                        if (uc.alias != null) {
                            element_lines.set(uc.alias, uc.source_line);
                        }
                    }
                }
                // Also check actors/use cases in packages
                foreach (var pkg in diagram.packages) {
                    foreach (var actor in pkg.actors) {
                        if (actor.source_line > 0) {
                            element_lines.set(actor.name, actor.source_line);
                            if (actor.alias != null) {
                                element_lines.set(actor.alias, actor.source_line);
                            }
                        }
                    }
                    foreach (var uc in pkg.use_cases) {
                        if (uc.source_line > 0) {
                            element_lines.set(uc.name, uc.source_line);
                            if (uc.alias != null) {
                                element_lines.set(uc.alias, uc.source_line);
                            }
                        }
                    }
                }

                // Parse SVG regions for click-to-source navigation (with pixel scaling)
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, width, height);

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

                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(UseCaseDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(UseCaseDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                var file = File.new_for_path(filename);
                var stream = file.replace(null, false, FileCreateFlags.NONE);
                stream.write_all(svg_data, null);
                stream.close();
                return true;
            } catch (Error e) {
                warning("Failed to write SVG: %s", e.message);
                return false;
            }
        }

        public bool export_to_pdf(UseCaseDiagram diagram, string filename) {
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
