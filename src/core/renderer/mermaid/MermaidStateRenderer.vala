namespace GDiagram {
    public class MermaidStateRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidStateRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidStateDiagram diagram) {
            var dot = new StringBuilder();

            // Use top-down layout for state machines
            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  node [fontname=\"Sans\", fontsize=11, style=\"rounded,filled\", fillcolor=white];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=9];\n");
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Render states
            dot.append("  // States\n");
            foreach (var state in diagram.states) {
                render_state(dot, state);
            }

            dot.append("\n");

            // Render transitions
            if (diagram.transitions.size > 0) {
                dot.append("  // Transitions\n");
                foreach (var transition in diagram.transitions) {
                    render_transition(dot, transition);
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_state(StringBuilder dot, MermaidState state) {
            string safe_id = sanitize_state_id(state.id);
            string label = state.description ?? state.id;
            label = RenderUtils.escape_label(label);

            // Determine shape and style based on state type
            switch (state.state_type) {
                case MermaidStateType.START:
                case MermaidStateType.END:
                    // Start/end states are small circles
                    dot.append_printf("  %s [label=\"\", shape=circle, width=0.3, height=0.3, fixedsize=true, fillcolor=black];\n",
                        safe_id);
                    break;

                case MermaidStateType.CHOICE:
                    // Choice is a diamond
                    dot.append_printf("  %s [label=\"\", shape=diamond, width=0.5, height=0.5, fixedsize=true];\n",
                        safe_id);
                    break;

                case MermaidStateType.FORK:
                case MermaidStateType.JOIN:
                    // Fork/join are horizontal bars (represented as box)
                    dot.append_printf("  %s [label=\"\", shape=box, width=1.5, height=0.1, fixedsize=true, fillcolor=black];\n",
                        safe_id);
                    break;

                case MermaidStateType.NORMAL:
                default:
                    // Normal states are rounded rectangles
                    dot.append_printf("  %s [label=\"%s\", shape=box];\n",
                        safe_id, label);
                    break;
            }

            // Store region for click navigation
            regions.add(new ElementRegion(state.id, state.source_line, 0, 0, 0, 0));

            // Render note if present
            if (state.note != null && state.note.length > 0) {
                string note_id = "%s_note".printf(safe_id);
                string note_label = RenderUtils.escape_label(state.note);
                dot.append_printf("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"#FFFFCC\"];\n",
                    note_id, note_label);
                dot.append_printf("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n",
                    note_id, safe_id);
            }
        }

        private void render_transition(StringBuilder dot, MermaidTransition transition) {
            string from_id = sanitize_state_id(transition.from.id);
            string to_id = sanitize_state_id(transition.to.id);

            var attrs = new Gee.ArrayList<string>();

            // Add label if present
            if (transition.label != null && transition.label.length > 0) {
                string label = RenderUtils.escape_label(transition.label);
                attrs.add("label=\"%s\"".printf(label));
            }

            string attr_str = "";
            if (attrs.size > 0) {
                attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            }

            dot.append_printf("  %s -> %s%s;\n", from_id, to_id, attr_str);
        }

        private string sanitize_state_id(string id) {
            return RenderUtils.sanitize_id(id);
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidStateDiagram diagram) {
            string dot_source = generate_dot(diagram);

            // Parse DOT into graph
            var graph = Gvc.Graph.read_string(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph");
                return null;
            }

            // Layout
            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout graph with engine: %s", layout_engine);
                return null;
            }

            // Render to SVG
            uint8[] svg_data;
            ret = context.render_data(graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return svg_data;
        }

        // Render to Cairo surface
        public Cairo.ImageSurface? render_to_surface(MermaidStateDiagram diagram) {
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

                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidStateDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidStateDiagram diagram, string filename) {
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

        public bool export_to_pdf(MermaidStateDiagram diagram, string filename) {
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
