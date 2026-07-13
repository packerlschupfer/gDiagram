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
        private MermaidStateDiagram? current_diagram = null;

        // render_scope() and render_composite_state() call each other once per nesting
        // level: without a cap a few thousand nested "state X {" blocks overflowed the
        // stack. Deeper composites are drawn as plain states and reported once.
        private const int MAX_COMPOSITE_DEPTH = 200;
        private bool depth_limit_reported = false;

        public string generate_dot(MermaidStateDiagram diagram) {
            current_diagram = diagram;
            depth_limit_reported = false;
            var dot = new StringBuilder();

            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append_printf("  rankdir=%s;\n", MermaidSourceLine.rankdir(diagram.direction));
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

            // Composite states: states that have children
            composite_ids = new Gee.HashSet<string>();
            foreach (var state in diagram.states) {
                if (state.parent_id != null && diagram.find_state(state.parent_id) != null) {
                    composite_ids.add(state.parent_id);
                }
            }

            // States, each composite as a cluster holding its own sub-states (nested
            // composites are clusters inside their parent's cluster)
            dot.append("  // States\n");
            var rendered = new Gee.HashSet<string>();
            render_scope(dot, diagram, null, "  ", 0, rendered);
            // Anything not reached from the top level (a parent cycle) is drawn flat
            foreach (var state in diagram.states) {
                if (!rendered.contains(state.id)) {
                    rendered.add(state.id);
                    render_state(dot, state, "  ");
                }
            }

            dot.append("\n");

            // Render transitions
            if (diagram.transitions.size > 0) {
                back_edges = find_back_edges(diagram);
                dot.append("  // Transitions\n");
                foreach (var transition in diagram.transitions) {
                    render_transition(dot, transition);
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_scope(StringBuilder dot, MermaidStateDiagram diagram, string? scope,
                                  string indent, int depth, Gee.HashSet<string> rendered,
                                  int region = -1) {
            foreach (var state in diagram.states) {
                string? parent = state.parent_id;
                if (parent != null && diagram.find_state(parent) == null) parent = null;
                if (parent != scope || rendered.contains(state.id)) continue;
                if (region >= 0 && state.region != region) continue;
                rendered.add(state.id);
                if (composite_ids.contains(state.id) && depth < MAX_COMPOSITE_DEPTH) {
                    render_composite_state(dot, state, diagram, indent, depth, rendered);
                } else {
                    if (composite_ids.contains(state.id) && !depth_limit_reported) {
                        depth_limit_reported = true;
                        diagram.errors.add(new ParseError(
                            "Composite states nested deeper than %d levels".printf(MAX_COMPOSITE_DEPTH),
                            state.source_line > 0 ? state.source_line : 1, 1));
                    }
                    render_state(dot, state, indent);
                }
            }
        }

        private static string cluster_name(string id) {
            return "cluster_" + RenderUtils.sanitize_id(id);
        }

        /**
         * The fill of a composite state's box. Mermaid tints it (#ECECFF over white) so
         * the sub-states and the transition labels between them stay readable; a full
         * saturated palette colour drowned both. Nested levels take a stronger tint so
         * each level is still told apart.
         */
        private static string composite_fill(Palette palette, int depth) {
            return mix(palette.container_border, palette.background, depth % 2 == 0 ? 0.14 : 0.30);
        }

        // `t` of colour `a` over colour `b`; non-hex colours are returned unchanged
        private static string mix(string a, string b, double t) {
            int ar, ag, ab;
            int br = 0, bg = 0, bb = 0;
            if (!parse_hex(a, out ar, out ag, out ab)) return a;
            if (!parse_hex(b, out br, out bg, out bb)) return a;
            return "#%02X%02X%02X".printf(
                (int) (ar * t + br * (1 - t) + 0.5),
                (int) (ag * t + bg * (1 - t) + 0.5),
                (int) (ab * t + bb * (1 - t) + 0.5));
        }

        private static bool parse_hex(string c, out int r, out int g, out int b) {
            r = 0; g = 0; b = 0;
            if (!c.has_prefix("#")) return false;
            string h = c.substring(1);
            if (h.length == 3) {
                h = "%c%c%c%c%c%c".printf(h[0], h[0], h[1], h[1], h[2], h[2]);
            }
            if (h.length != 6) return false;
            r = (int) uint64.parse(h.substring(0, 2), 16);
            g = (int) uint64.parse(h.substring(2, 2), 16);
            b = (int) uint64.parse(h.substring(4, 2), 16);
            return true;
        }

        // Concurrent regions of a composite: 1 unless it holds a "--" separator
        private static int region_count(MermaidStateDiagram diagram, string composite_id) {
            int max_region = 0;
            foreach (var child in diagram.children_of(composite_id)) {
                if (child.region > max_region) max_region = child.region;
            }
            return max_region + 1;
        }

        private void render_composite_state(StringBuilder dot, MermaidState state,
                                            MermaidStateDiagram diagram, string indent, int depth,
                                            Gee.HashSet<string> rendered) {
            var palette = ThemeManager.get_active_palette();
            string label = RenderUtils.escape_label(state.description ?? state.id);
            // Nested composites alternate tints so each level stays visible
            string fill = composite_fill(palette, depth);

            dot.append_printf("%ssubgraph %s {\n", indent, cluster_name(state.id));
            dot.append_printf("%s  label=\"%s\";\n", indent, label);
            dot.append_printf("%s  style=\"rounded,filled\";\n", indent);
            dot.append_printf("%s  fillcolor=\"%s\";\n", indent, fill);
            dot.append_printf("%s  color=\"%s\";\n", indent, palette.node_border);
            dot.append_printf("%s  fontcolor=\"%s\";\n", indent, RenderUtils.contrast_text(fill));
            dot.append_printf("%s  fontname=\"Sans Bold\";\n", indent);
            dot.append_printf("%s  fontsize=11;\n", indent);
            dot.append("\n");

            // "--" splits a composite into concurrent regions: Mermaid draws each of
            // them in its own dashed box inside the composite
            int max_region = region_count(diagram, state.id) - 1;
            if (max_region > 0) {
                for (int r = 0; r <= max_region; r++) {
                    dot.append_printf("%s  subgraph %s_r%d {\n", indent, cluster_name(state.id), r);
                    dot.append_printf("%s    label=\"\";\n", indent);
                    dot.append_printf("%s    style=\"dashed,filled\";\n", indent);
                    dot.append_printf("%s    fillcolor=\"%s\";\n", indent, palette.grid);
                    dot.append_printf("%s    color=\"%s\";\n", indent, palette.node_border);
                    render_scope(dot, diagram, state.id, indent + "    ", depth + 1, rendered, r);
                    dot.append_printf("%s  }\n", indent);
                }
                // Anything left (a region index with no cluster of its own)
                render_scope(dot, diagram, state.id, indent + "  ", depth + 1, rendered);
            } else {
                render_scope(dot, diagram, state.id, indent + "  ", depth + 1, rendered);
            }

            dot.append_printf("%s}\n", indent);

            // A note on a composite joins the cluster border
            if (state.note != null && state.note.length > 0) {
                string note_id = "%s_note".printf(sanitize_state_id(state.id));
                string note_fill = palette.accent_secondary;
                dot.append_printf("%s%s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n",
                    indent, note_id, RenderUtils.escape_label(state.note), note_fill,
                    RenderUtils.contrast_text(note_fill), palette.node_border);
                if (state.note_position == "left") {
                    dot.append_printf("%s%s -> %s [style=dashed, arrowhead=none, lhead=%s];\n", indent, note_id,
                        sanitize_state_id(entry_node(diagram, state.id)), cluster_name(state.id));
                } else {
                    dot.append_printf("%s%s -> %s [style=dashed, arrowhead=none, ltail=%s];\n", indent,
                        sanitize_state_id(exit_node(diagram, state.id)), note_id, cluster_name(state.id));
                }
            }
        }

        private string style_attrs(MermaidState state) {
            var specs = new Gee.ArrayList<string>();
            if (current_diagram != null) {
                foreach (string name in state.css_classes) {
                    if (current_diagram.class_defs.has_key(name)) specs.add(current_diagram.class_defs.get(name));
                }
            }
            if (state.inline_style != null) specs.add(state.inline_style);
            string? fill, stroke, text;
            MermaidSourceLine.style_colors(specs, out fill, out stroke, out text);
            var sb = new StringBuilder();
            if (fill != null) {
                sb.append(", fillcolor=\"%s\"".printf(RenderUtils.sanitize_color(fill)));
                if (text == null) sb.append(", fontcolor=\"%s\"".printf(RenderUtils.contrast_text(RenderUtils.sanitize_color(fill))));
            }
            if (stroke != null) sb.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(stroke)));
            if (text != null) sb.append(", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(text)));
            return sb.str;
        }

        private void render_state(StringBuilder dot, MermaidState state, string indent = "  ") {
            var palette = ThemeManager.get_active_palette();
            string safe_id = sanitize_state_id(state.id);
            string label = state.description ?? state.id;
            label = RenderUtils.escape_label(label);
            // Pseudo-states use the line colour, which contrasts with the canvas in every theme
            string mark = palette.edge_color;

            switch (state.state_type) {
                case MermaidStateType.START:
                    dot.append_printf("%s%s [label=\"\", shape=circle, width=0.25, height=0.25, fixedsize=true, style=filled, fillcolor=\"%s\", color=\"%s\"];\n",
                        indent, safe_id, mark, mark);
                    break;

                case MermaidStateType.END:
                    // Bullseye, as Mermaid draws the final state
                    dot.append_printf("%s%s [label=\"\", shape=doublecircle, width=0.18, height=0.18, fixedsize=true, style=filled, fillcolor=\"%s\", color=\"%s\"];\n",
                        indent, safe_id, mark, mark);
                    break;

                case MermaidStateType.CHOICE:
                    dot.append_printf("%s%s [label=\"\", shape=diamond, width=0.5, height=0.5, fixedsize=true];\n",
                        indent, safe_id);
                    break;

                case MermaidStateType.FORK:
                case MermaidStateType.JOIN:
                    // A bar, also when declared after its first use (Mermaid 11.17 draws a box then)
                    dot.append_printf("%s%s [label=\"\", shape=box, width=1.5, height=0.1, fixedsize=true, style=filled, fillcolor=\"%s\", color=\"%s\"];\n",
                        indent, safe_id, mark, mark);
                    break;

                case MermaidStateType.NORMAL:
                default:
                    dot.append_printf("%s%s [label=\"%s\", shape=box%s];\n",
                        indent, safe_id, label, style_attrs(state));
                    break;
            }

            // (Regions populated with real bounds in render_to_surface)

            // Note beside its state, on the side it was written for
            if (state.note != null && state.note.length > 0) {
                string note_id = "%s_note".printf(safe_id);
                string note_label = RenderUtils.escape_label(state.note);
                string note_fill = palette.accent_secondary;
                dot.append_printf("%s%s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n",
                    indent, note_id, note_label, note_fill, RenderUtils.contrast_text(note_fill), palette.node_border);
                if (state.note_position == "left") {
                    dot.append_printf("%s%s -> %s [style=dashed, arrowhead=none];\n", indent, note_id, safe_id);
                } else {
                    dot.append_printf("%s%s -> %s [style=dashed, arrowhead=none];\n", indent, safe_id, note_id);
                }
                dot.append_printf("%s{ rank=same; %s; %s; }\n", indent, safe_id, note_id);
            }
        }

        // First node inside a composite (its [*] start, else its first sub-state)
        private string entry_node(MermaidStateDiagram diagram, string composite_id, int depth = 0) {
            var start = diagram.find_state(MermaidStateDiagram.marker_id(composite_id, true));
            if (start != null) return start.id;
            var children = diagram.children_of(composite_id);
            var first = children[0];
            if (depth < 64 && composite_ids.contains(first.id)) return entry_node(diagram, first.id, depth + 1);
            return first.id;
        }

        // Last node inside a composite (its [*] end, else its last sub-state)
        private string exit_node(MermaidStateDiagram diagram, string composite_id, int depth = 0) {
            var end = diagram.find_state(MermaidStateDiagram.marker_id(composite_id, false));
            if (end != null) return end.id;
            var children = diagram.children_of(composite_id);
            var last = children[children.size - 1];
            if (depth < 64 && composite_ids.contains(last.id)) return exit_node(diagram, last.id, depth + 1);
            return last.id;
        }

        private Gee.HashSet<MermaidTransition> back_edges = new Gee.HashSet<MermaidTransition>();

        /**
         * Transitions that close a cycle, found by a depth-first walk in source order from
         * the start marker (a composite leads to its sub-states). They are emitted reversed
         * with dir=back: with clusters Graphviz otherwise may break a cycle at the wrong
         * edge and put "Idle" below the composite it enters first, where Mermaid keeps the
         * source order.
         */
        private Gee.HashSet<MermaidTransition> find_back_edges(MermaidStateDiagram diagram) {
            var result = new Gee.HashSet<MermaidTransition>();
            var out_edges = new Gee.HashMap<string, Gee.ArrayList<MermaidTransition>>();
            foreach (var t in diagram.transitions) {
                if (!out_edges.has_key(t.from.id)) out_edges.set(t.from.id, new Gee.ArrayList<MermaidTransition>());
                out_edges.get(t.from.id).add(t);
            }
            var done = new Gee.HashSet<string>();
            var on_stack = new Gee.HashSet<string>();
            var roots = new Gee.ArrayList<string>();
            if (diagram.start_state != null) roots.add(diagram.start_state.id);
            foreach (var s in diagram.states) roots.add(s.id);
            foreach (string root in roots) {
                if (!done.contains(root)) dfs(diagram, root, out_edges, done, on_stack, result, 0);
            }
            return result;
        }

        private void dfs(MermaidStateDiagram diagram, string id,
                         Gee.HashMap<string, Gee.ArrayList<MermaidTransition>> out_edges,
                         Gee.HashSet<string> done, Gee.HashSet<string> on_stack,
                         Gee.HashSet<MermaidTransition> result, int depth) {
            if (depth > 2000) return;
            done.add(id);
            on_stack.add(id);
            // Entering a composite reaches its sub-states first
            if (composite_ids.contains(id)) {
                foreach (var child in diagram.children_of(id)) {
                    if (!done.contains(child.id)) dfs(diagram, child.id, out_edges, done, on_stack, result, depth + 1);
                }
            }
            if (out_edges.has_key(id)) {
                foreach (var t in out_edges.get(id)) {
                    string target = t.to.id;
                    if (target == id) continue;
                    if (on_stack.contains(target)) {
                        result.add(t);
                    } else if (!done.contains(target)) {
                        dfs(diagram, target, out_edges, done, on_stack, result, depth + 1);
                    }
                }
            }
            on_stack.remove(id);
        }

        private void render_transition(StringBuilder dot, MermaidTransition transition) {
            var diagram = current_diagram;
            string from = transition.from.id;
            string to = transition.to.id;
            string? ltail = null;
            string? lhead = null;

            // A composite is a cluster, not a node: the edge runs to a node inside it and
            // is clipped at the cluster border (compound=true)
            if (composite_ids.contains(from) && !diagram.is_inside(transition.to, from)) {
                ltail = cluster_name(from);
                from = exit_node(diagram, from);
            } else if (composite_ids.contains(from)) {
                from = entry_node(diagram, from);
            }
            if (composite_ids.contains(to) && !diagram.is_inside(transition.from, to)) {
                lhead = cluster_name(to);
                to = entry_node(diagram, to);
            } else if (composite_ids.contains(to)) {
                to = exit_node(diagram, to);
            }

            var attrs = new Gee.ArrayList<string>();
            if (transition.label != null && transition.label.length > 0) {
                attrs.add("label=\"%s\"".printf(RenderUtils.escape_label(transition.label)));
                // A label between two sub-states sits on the composite's fill, not the canvas
                string? scope = transition.from.parent_id;
                if (scope != null && scope == transition.to.parent_id) {
                    int depth = 0;
                    var parent = diagram.find_state(scope);
                    while (parent != null && parent.parent_id != null) {
                        depth++;
                        parent = diagram.find_state(parent.parent_id);
                    }
                    var palette = ThemeManager.get_active_palette();
                    // Inside concurrent regions the label sits on the region's own fill
                    string fill = region_count(diagram, scope) > 1
                        ? palette.grid
                        : composite_fill(palette, depth);
                    attrs.add("fontcolor=\"%s\"".printf(RenderUtils.contrast_text(fill)));
                }
            }
            bool reversed = back_edges.contains(transition) && from != to;
            if (from != to) {
                // lhead/ltail name the DOT head/tail, which swap when the edge is reversed
                if (ltail != null) attrs.add("%s=%s".printf(reversed ? "lhead" : "ltail", ltail));
                if (lhead != null) attrs.add("%s=%s".printf(reversed ? "ltail" : "lhead", lhead));
            }
            if (reversed) attrs.add("dir=back");

            string attr_str = "";
            if (attrs.size > 0) {
                attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            }

            if (reversed) {
                dot.append_printf("  %s -> %s%s;\n", sanitize_state_id(to), sanitize_state_id(from), attr_str);
            } else {
                dot.append_printf("  %s -> %s%s;\n", sanitize_state_id(from), sanitize_state_id(to), attr_str);
            }
        }

        private string sanitize_state_id(string id) {
            return RenderUtils.sanitize_id(id);
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidStateDiagram diagram) {
            string dot_source = generate_dot(diagram);

            // Parse DOT into graph
            var graph = RenderUtils.read_dot(dot_source);
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
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

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
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

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
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
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
