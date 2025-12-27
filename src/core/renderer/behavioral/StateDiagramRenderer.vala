namespace GDiagram {
    public class StateDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public StateDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(StateDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values with defaults
            string bg_color = diagram.skin_params.background_color ?? "white";
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = diagram.skin_params.default_font_color ?? "black";

            sb.append("digraph state {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
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

            // Get state colors from theme
            string state_color = diagram.skin_params.get_element_property("state", "BackgroundColor") ?? "#FEFECE";
            string state_border = diagram.skin_params.get_element_property("state", "BorderColor") ?? "#A80036";

            // Render states
            sb.append("  // States\n");
            int cluster_idx = 0;
            foreach (var state in diagram.states) {
                append_state_node(sb, state, state_color, state_border, ref cluster_idx);
            }

            // Render transitions
            sb.append("\n  // Transitions\n");
            foreach (var trans in diagram.transitions) {
                string from_id = RenderUtils.sanitize_id(trans.from.id);
                string to_id = RenderUtils.sanitize_id(trans.to.id);

                string style = trans.is_dashed ? "dashed" : "solid";
                string label = trans.get_full_label();

                if (label.length > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s];\n".printf(
                        from_id, to_id, RenderUtils.escape_label(label), style));
                } else {
                    sb.append("  %s -> %s [style=%s];\n".printf(from_id, to_id, style));
                }
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";

                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(note.text), note_color));

                    if (note.attached_to != null) {
                        string attached_id = RenderUtils.sanitize_id(note.attached_to);
                        sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(note_id, attached_id));
                    }
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        private void append_state_node(StringBuilder sb, State state, string default_color,
                                        string default_border, ref int cluster_idx) {
            string id = RenderUtils.sanitize_id(state.id);
            string fill_color = state.color ?? default_color;

            switch (state.state_type) {
                case StateType.INITIAL:
                    sb.append("  %s [label=\"\", shape=circle, style=filled, fillcolor=\"black\", width=0.2, height=0.2];\n".printf(id));
                    break;

                case StateType.FINAL:
                    sb.append("  %s [label=\"\", shape=doublecircle, style=filled, fillcolor=\"black\", width=0.2, height=0.2];\n".printf(id));
                    break;

                case StateType.COMPOSITE:
                    // Render as cluster subgraph
                    sb.append("\n  subgraph cluster_%d {\n".printf(cluster_idx++));
                    sb.append("    label=\"%s\";\n".printf(RenderUtils.escape_label(state.get_display_label())));
                    sb.append("    style=rounded;\n");
                    sb.append("    color=\"%s\";\n".printf(default_border));
                    sb.append("    bgcolor=\"%s\";\n".printf(fill_color));

                    if (state.description != null && state.description.length > 0) {
                        sb.append("    // Description: %s\n".printf(state.description));
                    }

                    // Render nested states
                    foreach (var nested in state.nested_states) {
                        sb.append("  ");
                        append_state_node(sb, nested, default_color, default_border, ref cluster_idx);
                    }

                    // Render nested transitions
                    foreach (var trans in state.nested_transitions) {
                        string from_id = RenderUtils.sanitize_id(trans.from.id);
                        string to_id = RenderUtils.sanitize_id(trans.to.id);
                        string style = trans.is_dashed ? "dashed" : "solid";
                        string label = trans.get_full_label();

                        if (label.length > 0) {
                            sb.append("    %s -> %s [label=\"%s\", style=%s];\n".printf(
                                from_id, to_id, RenderUtils.escape_label(label), style));
                        } else {
                            sb.append("    %s -> %s [style=%s];\n".printf(from_id, to_id, style));
                        }
                    }

                    sb.append("  }\n");
                    break;

                case StateType.CHOICE:
                    // Diamond shape for choice/decision point
                    sb.append("  %s [label=\"\", shape=diamond, style=filled, fillcolor=\"%s\", width=0.4, height=0.4];\n".printf(
                        id, fill_color));
                    break;

                case StateType.FORK:
                case StateType.JOIN:
                    // Horizontal bar for fork/join
                    sb.append("  %s [label=\"\", shape=box, style=filled, fillcolor=\"black\", width=1.5, height=0.05];\n".printf(id));
                    break;

                case StateType.END_STATE:
                    // Circle with X or bulls-eye for termination
                    sb.append("  %s [label=\"\", shape=doublecircle, style=filled, fillcolor=\"black\", width=0.25, height=0.25];\n".printf(id));
                    break;

                case StateType.HISTORY:
                    // Circle with H
                    sb.append("  %s [label=\"H\", shape=circle, style=filled, fillcolor=\"white\", width=0.3, height=0.3, fontsize=10];\n".printf(id));
                    break;

                case StateType.DEEP_HISTORY:
                    // Circle with H*
                    sb.append("  %s [label=\"H*\", shape=circle, style=filled, fillcolor=\"white\", width=0.3, height=0.3, fontsize=10];\n".printf(id));
                    break;

                case StateType.ENTRY_POINT:
                    // Small filled circle (entry point)
                    sb.append("  %s [label=\"\", shape=circle, style=filled, fillcolor=\"black\", width=0.15, height=0.15];\n".printf(id));
                    break;

                case StateType.EXIT_POINT:
                    // Circle with X
                    sb.append("  %s [label=\"X\", shape=circle, style=\"filled\", fillcolor=\"white\", fontcolor=\"black\", width=0.2, height=0.2, fontsize=8];\n".printf(id));
                    break;

                default:  // SIMPLE
                    string label = state.get_display_label();
                    // Build label with description and entry/exit actions
                    var label_parts = new StringBuilder();
                    label_parts.append(label);

                    if (state.description != null && state.description.length > 0) {
                        label_parts.append("\\n");
                        label_parts.append(state.description);
                    }
                    if (state.entry_action != null && state.entry_action.length > 0) {
                        label_parts.append("\\nentry / ");
                        label_parts.append(state.entry_action);
                    }
                    if (state.exit_action != null && state.exit_action.length > 0) {
                        label_parts.append("\\nexit / ");
                        label_parts.append(state.exit_action);
                    }

                    sb.append("  %s [label=\"%s\", shape=box, style=\"rounded,filled\", fillcolor=\"%s\", color=\"%s\"];\n".printf(
                        id, RenderUtils.escape_label(label_parts.str), fill_color, default_border));
                    break;
            }
        }

        public uint8[]? render_to_svg(StateDiagram diagram) {
            string dot = generate_dot(diagram);

            try {
                string tmp_dot = "/tmp/gplantuml_state.dot";
                string tmp_svg = "/tmp/gplantuml_state.svg";

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
                warning("Failed to render state diagram: %s", e.message);
                return null;
            }
        }

        public Cairo.ImageSurface? render_to_surface(StateDiagram diagram) {
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

                // Build element line number map from states
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var state in diagram.states) {
                    if (state.source_line > 0) {
                        element_lines.set(state.id, state.source_line);
                        if (state.label != null && state.label.length > 0) {
                            element_lines.set(state.label, state.source_line);
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

        public bool export_to_png(StateDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(StateDiagram diagram, string filename) {
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

        public bool export_to_pdf(StateDiagram diagram, string filename) {
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
