namespace GDiagram {
    public class MermaidStateRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidStateRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        // Composite state IDs — populated in generate_dot(), used in render_transition()
        private Gee.HashSet<string> composite_ids = new Gee.HashSet<string>();

        public string generate_dot(MermaidStateDiagram diagram) {
            var dot = new StringBuilder();

            // Layout direction
            string rankdir;
            switch (diagram.direction) {
                case FlowchartDirection.LEFT_RIGHT:  rankdir = "LR"; break;
                case FlowchartDirection.RIGHT_LEFT:  rankdir = "RL"; break;
                case FlowchartDirection.BOTTOM_UP:   rankdir = "BT"; break;
                default:                             rankdir = "TB"; break;
            }
            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append_printf("  rankdir=%s;\n", rankdir);
            dot.append("  compound=true;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=11, style=\"rounded,filled\", fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n".printf(palette.accent_secondary, RenderUtils.contrast_text(palette.accent_secondary), palette.node_border));
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Collect composite state ids (states that have children)
            composite_ids = new Gee.HashSet<string>();
            foreach (var state in diagram.states) {
                if (state.parent_id != null) {
                    composite_ids.add(state.parent_id);
                }
            }

            // Render composite states as cluster subgraphs, then flat states outside
            var rendered_ids = new Gee.HashSet<string>();
            int cluster_idx = 0;
            foreach (var state in diagram.states) {
                if (composite_ids.contains(state.id)) {
                    // This state is a composite — render it as a subgraph cluster
                    render_composite_state(dot, state, diagram, "  ", ref cluster_idx);
                    rendered_ids.add(state.id);
                    // Mark children as rendered
                    foreach (var child in diagram.states) {
                        if (child.parent_id == state.id) {
                            rendered_ids.add(child.id);
                        }
                    }
                }
            }

            // Render remaining flat states
            dot.append("  // States\n");
            foreach (var state in diagram.states) {
                if (!rendered_ids.contains(state.id)) {
                    render_state(dot, state, "  ");
                }
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

        private void render_composite_state(StringBuilder dot, MermaidState state,
                                            MermaidStateDiagram diagram, string indent,
                                            ref int cluster_idx) {
            string safe_id = sanitize_state_id(state.id);
            string label = state.description ?? state.id;
            label = RenderUtils.escape_label(label);

            dot.append_printf("%ssubgraph cluster_%d {\n", indent, cluster_idx++);
            dot.append_printf("%s  label=\"%s\";\n", indent, label);
            dot.append_printf("%s  style=\"rounded,filled\";\n", indent);
            dot.append_printf("%s  fillcolor=\"%s\";\n", indent, ThemeManager.get_active_palette().success);
            dot.append_printf("%s  color=\"%s\";\n", indent, ThemeManager.get_active_palette().success);
            dot.append_printf("%s  fontcolor=\"%s\";\n", indent, RenderUtils.contrast_text(ThemeManager.get_active_palette().success));
            dot.append_printf("%s  fontname=\"Sans Bold\";\n", indent);
            dot.append_printf("%s  fontsize=11;\n", indent);
            dot.append("\n");

            // Render child states inside the cluster
            foreach (var child in diagram.states) {
                if (child.parent_id == state.id) {
                    render_state(dot, child, indent + "  ");
                }
            }

            dot.append_printf("%s}\n", indent);

            // Invisible anchor node so edges can reach the cluster boundary
            dot.append_printf("%s%s_anchor [label=\"\", shape=point, width=0, height=0, style=invis];\n",
                indent, safe_id);
        }

        private void render_state(StringBuilder dot, MermaidState state, string indent = "  ") {
            string safe_id = sanitize_state_id(state.id);
            string label = state.description ?? state.id;
            label = RenderUtils.escape_label(label);

            // Determine shape and style based on state type
            switch (state.state_type) {
                case MermaidStateType.START:
                case MermaidStateType.END:
                    dot.append_printf("%s%s [label=\"\", shape=circle, width=0.3, height=0.3, fixedsize=true, fillcolor=black];\n",
                        indent, safe_id);
                    break;

                case MermaidStateType.CHOICE:
                    dot.append_printf("%s%s [label=\"\", shape=diamond, width=0.5, height=0.5, fixedsize=true];\n",
                        indent, safe_id);
                    break;

                case MermaidStateType.FORK:
                case MermaidStateType.JOIN:
                    dot.append_printf("%s%s [label=\"\", shape=box, width=1.5, height=0.1, fixedsize=true, fillcolor=black];\n",
                        indent, safe_id);
                    break;

                case MermaidStateType.NORMAL:
                default:
                    dot.append_printf("%s%s [label=\"%s\", shape=box];\n",
                        indent, safe_id, label);
                    break;
            }

            // (Regions populated with real bounds in render_to_surface)

            // Render note if present
            if (state.note != null && state.note.length > 0) {
                string note_id = "%s_note".printf(safe_id);
                string note_label = RenderUtils.escape_label(state.note);
                string note_fill = ThemeManager.get_active_palette().accent_secondary;
                dot.append_printf("%s%s [label=\"%s\", shape=note, style=filled, fillcolor=\"" + note_fill + "\", fontcolor=\"" + RenderUtils.contrast_text(note_fill) + "\"];\n",
                    indent, note_id, note_label);
                dot.append_printf("%s%s -> %s [style=dashed, arrowhead=none, constraint=false];\n",
                    indent, note_id, safe_id);
            }
        }

        private void render_transition(StringBuilder dot, MermaidTransition transition) {
            string from_id = sanitize_state_id(transition.from.id);
            string to_id = sanitize_state_id(transition.to.id);

            // Composite states are rendered as clusters (not nodes). Use the anchor
            // node (emitted just after the cluster) as the edge endpoint so Graphviz
            // can connect the edge to something concrete.
            if (composite_ids.contains(transition.from.id)) {
                from_id = from_id + "_anchor";
            }
            if (composite_ids.contains(transition.to.id)) {
                to_id = to_id + "_anchor";
            }

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
            // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
            ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

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

                var element_lines = new Gee.HashMap<string, int>();
                foreach (var state in diagram.states) {
                    if (state.source_line > 0)
                        element_lines.set(sanitize_state_id(state.id), state.source_line);
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
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
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidStateDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
