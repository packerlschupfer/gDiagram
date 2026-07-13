namespace GDiagram {
    public class StateDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public StateDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        // A composite with concurrent regions, for the separator lines drawn in render_to_svg()
        private class RegionLayout {
            public string cluster = "";
            public bool side_by_side = false;
            public Gee.ArrayList<string> regions = new Gee.ArrayList<string>();
        }

        // Per-render state filled by generate_dot() and used by render_to_svg()
        private Gee.ArrayList<PortBorderLayout> port_layouts = new Gee.ArrayList<PortBorderLayout>();
        private Gee.ArrayList<RegionLayout> region_layouts = new Gee.ArrayList<RegionLayout>();
        // Port-like state id (entry/exit point, pin, expansion node inside a composite) -> composite id
        private Gee.HashMap<string, string> port_parent = new Gee.HashMap<string, string>();
        // Composite id -> number of self transitions drawn around it
        private Gee.HashMap<string, int> composite_loops = new Gee.HashMap<string, int>();
        private Gee.HashSet<string> composite_ids = new Gee.HashSet<string>();
        private Gee.HashMap<string, Gee.HashSet<string>> enclosing = new Gee.HashMap<string, Gee.HashSet<string>>();

        private static bool is_top_port(StateType t) {
            return t == StateType.ENTRY_POINT || t == StateType.INPUT_PIN || t == StateType.EXPANSION_INPUT;
        }

        private static bool is_port_type(StateType t) {
            return is_top_port(t) || t == StateType.EXIT_POINT || t == StateType.OUTPUT_PIN ||
                   t == StateType.EXPANSION_OUTPUT;
        }

        public string generate_dot(StateDiagram diagram) {
            var sb = new StringBuilder();
            port_layouts = new Gee.ArrayList<PortBorderLayout>();
            region_layouts = new Gee.ArrayList<RegionLayout>();
            port_parent = new Gee.HashMap<string, string>();
            composite_loops = new Gee.HashMap<string, int>();
            attach_counts = new Gee.HashMap<string, int>();

            // Get theme values — active Palette as fallback when skin_params empty.
            var palette = ThemeManager.get_active_palette();
            string bg_raw = diagram.skin_params.background_color ?? palette.background;
            string bg_color = RenderUtils.fill_color(bg_raw);
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = RenderUtils.sanitize_color(diagram.skin_params.default_font_color ?? palette.node_text);
            string line_color = RenderUtils.edge_line_color(diagram.skin_params, palette);

            sb.append("digraph state {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            string bg_angle = RenderUtils.gradient_stmt(bg_raw);
            if (bg_angle != "") {
                sb.append("  %s\n".printf(bg_angle));
            }
            sb.append("  node [fontname=\"%s\", fontsize=%s, fontcolor=\"%s\", style=\"filled\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(
                font_name, line_color, RenderUtils.edge_label_color(diagram.skin_params, palette)));
            sb.append("  compound=true;\n");

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
                sb.append("  fontcolor=\"%s\";\n".printf(RenderUtils.title_color(diagram.skin_params, palette)));
            }

            sb.append("\n");

            // Get state colors from theme (fall back to palette accent).
            // As written: gradients are resolved where the fill is emitted
            string state_color = diagram.skin_params.get_element_property("state", "BackgroundColor") ?? palette.accent_secondary;
            string state_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("state", "BorderColor") ?? palette.accent_primary);
            // "skinparam state { StartColor X; EndColor Y }" (or the global forms). The circles
            // default to the link colour, readable on either theme; they were always black.
            start_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("state", "StartColor") ??
                                                     diagram.skin_params.get_global("StartColor") ?? line_color);
            end_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("state", "EndColor") ??
                                                   diagram.skin_params.get_global("EndColor") ?? line_color);
            port_fill = RenderUtils.fill_color(state_color);
            port_stroke = state_border;

            // Composite states render as clusters. Collected at every depth: a nested
            // composite needs the same anchor and border clipping as a top-level one.
            composite_ids = new Gee.HashSet<string>();
            enclosing = new Gee.HashMap<string, Gee.HashSet<string>>();
            collect_composites(diagram.states, new Gee.ArrayList<string>(), composite_ids, enclosing);
            cluster_names = new Gee.HashMap<string, string>();

            var all_transitions = new Gee.ArrayList<StateTransition>();
            collect_nested_transitions(diagram.states, all_transitions);
            all_transitions.add_all(diagram.transitions);
            foreach (var trans in all_transitions) {
                if (trans.from == trans.to && composite_ids.contains(trans.from.id)) {
                    composite_loops.set(trans.from.id, (composite_loops.has_key(trans.from.id) ? composite_loops.get(trans.from.id) : 0) + 1);
                }
            }

            // Render states
            sb.append("  // States\n");
            int cluster_idx = 0;
            foreach (var state in diagram.states) {
                append_state_node(sb, diagram, state, state_color, state_border, ref cluster_idx);
            }

            // Render transitions. Nested ones are written here too, outside every
            // cluster: an edge written inside a cluster pulls both endpoints into
            // it, so an edge to an outer state dragged that state into the box.
            sb.append("\n  // Transitions\n");
            var loops_done = new Gee.HashMap<string, int>();
            var link_ends = new Gee.HashMap<StateTransition, string>();
            foreach (var trans in all_transitions) {
                string from_raw = trans.from.id;
                string to_raw = trans.to.id;
                string clip = "";

                string style = trans.is_dashed ? "dashed" : "solid";
                string label = trans.get_full_label();
                if (trans.line_style == "dotted" || trans.line_style == "invis") {
                    style = trans.line_style;
                }
                string paint = "";
                if (trans.line_style == "bold") {
                    paint += ", penwidth=2";
                }
                if (trans.color != null) {
                    paint += ", color=\"%s\"".printf(RenderUtils.sanitize_color(trans.color));
                }
                string label_attr = label.length > 0
                    ? "label=\"%s\", ".printf(RenderUtils.escape_label(RenderUtils.strip_inline_creole(label)))
                    : "";

                // A composite's transition to itself: a loop around the cluster through a
                // point beside it. It was a tiny loop on the invisible anchor inside the box.
                if (from_raw == to_raw && composite_ids.contains(from_raw)) {
                    string cluster = cluster_names.get(from_raw);
                    int k = loops_done.has_key(from_raw) ? loops_done.get(from_raw) : 0;
                    loops_done.set(from_raw, k + 1);
                    string loop_id = "%s_loop%d".printf(RenderUtils.sanitize_id(from_raw), k);
                    string out_id = inner_endpoint(trans.from, false, false) ?? RenderUtils.sanitize_id(from_raw) + "_anchor";
                    string in_id = inner_endpoint(trans.from, true, false) ?? RenderUtils.sanitize_id(from_raw) + "_anchor";
                    // Out of the box below it, and back without ranking the point again
                    sb.append("  %s -> %s [style=%s, arrowhead=none, ltail=%s%s];\n".printf(
                        out_id, loop_id, style, cluster, paint));
                    sb.append("  %s -> %s [%sstyle=%s, lhead=%s, constraint=false%s];\n".printf(
                        loop_id, in_id, label_attr.replace("label=", "xlabel="), style, cluster, paint));
                    link_ends.set(trans, "%s %s".printf(loop_id, loop_id));
                    continue;
                }

                string from_id = endpoint_id(trans.from, trans.to, true);
                string to_id = endpoint_id(trans.to, trans.from, false);

                // A composite state is a cluster, not a node. The edge runs to a node inside
                // the cluster and ltail/lhead clip it at the border. Incoming links go to the
                // cluster's first node and outgoing ones leave from its last, so links in both
                // directions no longer share one anchor with overlapping heads. No clipping
                // when the other end lies inside that same cluster.
                if (composite_ids.contains(from_raw) && !is_enclosed_by(enclosing, to_raw, from_raw)) {
                    clip += ", ltail=%s".printf(cluster_names.get(from_raw));
                }
                if (composite_ids.contains(to_raw) && !is_enclosed_by(enclosing, from_raw, to_raw)) {
                    clip += ", lhead=%s".printf(cluster_names.get(to_raw));
                }

                // "->": side by side; "--->": a longer link
                bool sideways = trans.direction == "left" || trans.direction == "right" ||
                                (trans.direction == "" && trans.arrow_length == 1);
                bool flat_ok = !composite_ids.contains(from_raw) && !composite_ids.contains(to_raw) &&
                               !port_parent.has_key(from_raw) && !port_parent.has_key(to_raw);
                bool top_level = !is_nested(enclosing, from_raw) && !is_nested(enclosing, to_raw);
                string length = "";
                if (sideways && flat_ok && !top_level && same_scope(trans.from, trans.to)) {
                    length = ", minlen=0";
                } else if (trans.arrow_length > 2 && trans.direction != "left" && trans.direction != "right") {
                    length = ", minlen=%d".printf(trans.arrow_length - 1 + (clip != "" ? 1 : 0));
                } else if (clip != "" && !sideways) {
                    // One rank between nodes inside two clusters left no room for the link
                    // between their borders: it shrank to its arrowhead
                    length = ", minlen=2";
                }

                // "-up->" / "-left->": written from the target back to the source and drawn
                // with dir=back, so ranking and left-to-right order put the target above /
                // to the left
                string a = from_id;
                string b = to_id;
                string attrs = clip + paint + length;
                if (trans.direction == "up" || trans.direction == "left") {
                    a = to_id;
                    b = from_id;
                    attrs = attrs.replace("ltail=", "@TAIL@").replace("lhead=", "ltail=").replace("@TAIL@", "lhead=") +
                            ", dir=back";
                }

                // A clipped link's label goes beside the drawn part (xlabel): a plain label sits
                // in the middle of the whole spline, often inside the cluster
                if (clip != "") {
                    label_attr = label_attr.replace("label=", "xlabel=");
                }
                sb.append("  %s -> %s [%sstyle=%s%s];\n".printf(a, b, label_attr, style, attrs));
                link_ends.set(trans, "%s %s".printf(strip_port(a), strip_port(b)));
                // Side by side at the top level; a root-level rank=same would pull a node
                // out of its cluster, so nested ones use minlen=0 above
                if (sideways && flat_ok && top_level) {
                    sb.append("  { rank=same; %s; %s; }\n".printf(strip_port(a), strip_port(b)));
                }
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color_raw = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary;
                string note_color = RenderUtils.fill_color(note_color_raw);
                string note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_color));

                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"%s, fontcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(RenderUtils.strip_inline_creole(note.text)), note_color,
                        RenderUtils.gradient_attr(note_color_raw), note_font));

                    if (note.attached_to != null) {
                        string attached_id = RenderUtils.sanitize_id(note.attached_to);
                        // Composite states render as clusters, not nodes. Without the
                        // anchor redirect Graphviz invents an ellipse named after the
                        // state and the note points at that instead.
                        string note_clip = "";
                        if (composite_ids.contains(note.attached_to)) {
                            attached_id = attached_id + "_anchor";
                            note_clip = ", lhead=%s".printf(cluster_names.get(note.attached_to));
                        }
                        sb.append("  %s -> %s [style=dashed, arrowhead=none%s];\n".printf(note_id, attached_id, note_clip));
                    } else if (note.link != null && link_ends.has_key(note.link)) {
                        // "note on link": ranked between the transition's ends, so it sits
                        // beside the link, with no connector (as PlantUML draws it)
                        string[] ends = link_ends.get(note.link).split(" ");
                        if (ends[0] != ends[1]) {
                            sb.append("  %s -> %s [style=invis];\n".printf(ends[0], note_id));
                            sb.append("  %s -> %s [style=invis];\n".printf(note_id, ends[1]));
                        }
                    }
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        private string start_color = "black";
        private string end_color = "black";
        private string port_fill = "white";
        private string port_stroke = "black";

        private static string join_ids(Gee.ArrayList<string> ids) {
            var sb = new StringBuilder();
            foreach (string id in ids) {
                if (sb.len > 0) {
                    sb.append("; ");
                }
                sb.append(id);
            }
            return sb.str;
        }

        // "p1:sq" -> "p1"
        private static string strip_port(string endpoint) {
            int colon = endpoint.index_of(":");
            return colon > 0 ? endpoint.substring(0, colon) : endpoint;
        }

        // Both states drawn in the same cluster and concurrent region
        private bool same_scope(State a, State b) {
            var ea = enclosing.has_key(a.id) ? enclosing.get(a.id) : new Gee.HashSet<string>();
            var eb = enclosing.has_key(b.id) ? enclosing.get(b.id) : new Gee.HashSet<string>();
            return ea.size == eb.size && ea.contains_all(eb) && a.region == b.region;
        }

        // The DOT end of a transition at state `s` (`other` is the far end)
        private string endpoint_id(State s, State other, bool source) {
            string id = RenderUtils.sanitize_id(s.id);
            if (composite_ids.contains(s.id)) {
                if (is_enclosed_by(enclosing, other.id, s.id)) {
                    return id + "_anchor";
                }
                return inner_endpoint(s, !source) ?? id + "_anchor";
            }
            if (port_parent.has_key(s.id)) {
                // Entered from outside the composite on the border's outer side, from inside
                // on its inner side
                string parent = port_parent.get(s.id);
                string other_node = port_parent.has_key(other.id) ? port_parent.get(other.id) : other.id;
                bool inside = other_node == parent || is_enclosed_by(enclosing, other_node, parent);
                bool north = is_top_port(s.state_type) != inside;
                return "%s:sq:%s".printf(id, north ? "n" : "s");
            }
            return id;
        }

        // Nodes inside a composite that a clipped link can attach to, in order of preference:
        // for incoming links the start circle first, then the states in declaration order; for
        // outgoing ones the end circle first, then the states from the last declared. Nested
        // composites are looked into; border ports, history circles, and starts for outgoing
        // links are skipped.
        private void attach_candidates(State composite, bool incoming, Gee.ArrayList<string> into) {
            var ordered = new Gee.ArrayList<State>();
            foreach (var s in composite.nested_states) {
                if (s.state_type == (incoming ? StateType.INITIAL : StateType.FINAL)) {
                    ordered.add(s);
                }
            }
            int n = composite.nested_states.size;
            for (int i = 0; i < n; i++) {
                var s = composite.nested_states[incoming ? i : n - 1 - i];
                if (!ordered.contains(s) && (incoming || s.state_type != StateType.INITIAL) &&
                    s.state_type != StateType.HISTORY && s.state_type != StateType.DEEP_HISTORY) {
                    ordered.add(s);
                }
            }
            foreach (var s in ordered) {
                if (port_parent.has_key(s.id)) {
                    continue;
                }
                if (composite_ids.contains(s.id)) {
                    attach_candidates(s, incoming, into);
                } else {
                    into.add(RenderUtils.sanitize_id(s.id));
                }
            }
        }

        // Composite id + direction -> links attached so far, to spread the next one
        private Gee.HashMap<string, int> attach_counts = new Gee.HashMap<string, int>();

        // The node inside a composite a clipped link attaches to; successive links take
        // successive candidates, so their ends do not pile up on one point. Null when the
        // composite has no node of its own.
        private string? inner_endpoint(State composite, bool incoming, bool spread = true) {
            var candidates = new Gee.ArrayList<string>();
            attach_candidates(composite, incoming, candidates);
            if (candidates.size == 0) {
                return null;
            }
            if (!spread) {
                return candidates[0];
            }
            string key = composite.id + (incoming ? "\x01in" : "\x01out");
            int k = attach_counts.has_key(key) ? attach_counts.get(key) : 0;
            attach_counts.set(key, k + 1);
            return candidates[k % candidates.size];
        }

        // Every non-cluster node id drawn inside a composite (nested composites included)
        private void collect_inner_ids(State composite, Gee.ArrayList<string> into, bool with_ports) {
            foreach (var s in composite.nested_states) {
                if (composite_ids.contains(s.id)) {
                    collect_inner_ids(s, into, with_ports);
                    into.add(RenderUtils.sanitize_id(s.id) + "_anchor");
                } else if (with_ports || !port_parent.has_key(s.id)) {
                    into.add(RenderUtils.sanitize_id(s.id));
                }
            }
        }

        // State id -> Graphviz cluster name, filled while composites are emitted
        private Gee.HashMap<string, string> cluster_names = new Gee.HashMap<string, string>();

        private void collect_composites(Gee.List<State> states, Gee.ArrayList<string> stack,
                                        Gee.HashSet<string> composite_ids,
                                        Gee.HashMap<string, Gee.HashSet<string>> enclosing) {
            foreach (var state in states) {
                if (!enclosing.has_key(state.id)) {
                    var outer = new Gee.HashSet<string>();
                    outer.add_all(stack);
                    enclosing.set(state.id, outer);
                }
                if (stack.size > 0 && is_port_type(state.state_type)) {
                    port_parent.set(state.id, stack[stack.size - 1]);
                }
                if (state.state_type == StateType.COMPOSITE) {
                    composite_ids.add(state.id);
                    stack.add(state.id);
                    collect_composites(state.nested_states, stack, composite_ids, enclosing);
                    stack.remove_at(stack.size - 1);
                }
            }
        }

        private void collect_nested_transitions(Gee.List<State> states, Gee.ArrayList<StateTransition> into) {
            foreach (var state in states) {
                if (state.state_type == StateType.COMPOSITE) {
                    into.add_all(state.nested_transitions);
                    collect_nested_transitions(state.nested_states, into);
                }
            }
        }

        // True when state `id` is drawn inside the cluster of composite `composite_id`
        private bool is_enclosed_by(Gee.HashMap<string, Gee.HashSet<string>> enclosing,
                                    string id, string composite_id) {
            return enclosing.has_key(id) && enclosing.get(id).contains(composite_id);
        }

        private static bool is_nested(Gee.HashMap<string, Gee.HashSet<string>> enclosing, string id) {
            return enclosing.has_key(id) && enclosing.get(id).size > 0;
        }

        /**
         * Background for one state: an explicit inline color wins, then
         * skinparam state { BackgroundColor<<stereotype>> }, then the plain
         * BackgroundColor / palette default the caller resolved. Returned as written
         * (a gradient keeps both colours); the caller converts it for Graphviz.
         */
        private string resolve_state_fill(StateDiagram diagram, State state, string default_color) {
            if (state.color != null) {
                return state.color;
            }
            if (state.stereotype != null && state.stereotype.length > 0) {
                string? by_stereo = diagram.skin_params.get_stereotype_property(
                    "state", "BackgroundColor", state.stereotype);
                if (by_stereo != null) {
                    return by_stereo;
                }
            }
            return default_color;
        }

        // Cluster label of a composite state. Description lines ("Outer : text") and
        // entry/exit actions go into the header under the name, as in PlantUML. They
        // used to be written raw into a "// Description:" comment, and every line after
        // the first became bare DOT statements (ghost nodes, or a syntax error).
        private static string composite_label(State state) {
            var lines = new Gee.ArrayList<string>();
            if (state.description != null && state.description.length > 0) {
                foreach (string line in RenderUtils.strip_inline_creole(state.description).split("\n")) {
                    lines.add(line);
                }
            }
            if (state.entry_action != null && state.entry_action.length > 0) {
                lines.add("entry / " + state.entry_action);
            }
            if (state.exit_action != null && state.exit_action.length > 0) {
                lines.add("exit / " + state.exit_action);
            }
            if (lines.size == 0) {
                return "\"%s\"".printf(RenderUtils.escape_label(state.get_display_label()));
            }
            var body = new StringBuilder();
            foreach (string line in lines) {
                if (body.len > 0) {
                    body.append("<BR ALIGN=\"LEFT\"/>");
                }
                body.append(Markup.escape_text(line));
            }
            body.append("<BR ALIGN=\"LEFT\"/>");
            return "<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">" +
                   "<TR><TD>%s</TD></TR><HR/><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">%s</TD></TR></TABLE>>".printf(
                       Markup.escape_text(state.get_display_label()), body.str);
        }

        // An entry / exit point, pin or expansion node: its name beside a sentinel cell that
        // render_to_svg() replaces with the shape: #010204 a hollow circle, #010205 a crossed
        // circle, #010206 a square, #010207 a row of squares. Inside a composite it goes on
        // the border. (The node keeps the plain "node" class: the border step finds it by that.)
        private string port_node(State state, bool name_above) {
            string sentinel;
            int width = 12;
            switch (state.state_type) {
                case StateType.ENTRY_POINT: sentinel = "#010204"; break;
                case StateType.EXIT_POINT: sentinel = "#010205"; break;
                case StateType.EXPANSION_INPUT:
                case StateType.EXPANSION_OUTPUT: sentinel = "#010207"; width = 44; break;
                default: sentinel = "#010206"; break;
            }
            string id = RenderUtils.sanitize_id(state.id);
            string cell = "<TD FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"12\" PORT=\"sq\" BGCOLOR=\"%s\"></TD>".printf(width, sentinel);
            // The name diagonally outside the shape, clear of the links at its middle
            string name_row = "<TR><TD ALIGN=\"RIGHT\">%s</TD><TD></TD></TR>".printf(
                Markup.escape_text(state.get_display_label()));
            string shape_row = "<TR><TD></TD>%s</TR>".printf(cell);
            return "  %s [shape=plaintext, style=solid, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">%s%s</TABLE>>];\n".printf(
                id, name_above ? name_row : shape_row, name_above ? shape_row : name_row);
        }

        // base_color is the diagram-wide state background (skinparam or palette). Each state,
        // nested ones included, resolves its own fill from it: nested states used to get the
        // enclosing composite's resolved fill, so their own "#colour" was ignored.
        private void append_state_node(StringBuilder sb, StateDiagram diagram, State state, string base_color,
                                        string default_border, ref int cluster_idx) {
            string id = RenderUtils.sanitize_id(state.id);
            // As written (a gradient keeps both colours)
            string default_color = resolve_state_fill(diagram, state, base_color);
            string fill_color = RenderUtils.fill_color(default_color);
            // "#fill;line:red;line.dashed;text:blue"
            string border = state.line_color != null ? RenderUtils.sanitize_color(state.line_color) : default_border;
            string text_color = state.text_color != null ? RenderUtils.sanitize_color(state.text_color)
                                                         : RenderUtils.contrast_text(fill_color);
            string border_style = "";
            if (state.line_style == "dashed" || state.line_style == "dotted") {
                border_style = "," + state.line_style;
            }
            string penwidth = state.line_style == "bold" ? ", penwidth=2" : "";

            switch (state.state_type) {
                case StateType.INITIAL:
                    sb.append("  %s [label=\"\", shape=circle, style=filled, fillcolor=\"%s\", color=\"%s\", width=0.2, height=0.2];\n".printf(
                        id, state.color != null ? fill_color : start_color, state.color != null ? fill_color : start_color));
                    break;

                case StateType.FINAL:
                case StateType.END_STATE:
                    // A ring around a dot (Graphviz fills only the inner circle)
                    string ec = state.color != null ? fill_color : end_color;
                    sb.append("  %s [label=\"\", shape=doublecircle, style=filled, fillcolor=\"%s\", color=\"%s\", width=0.18, height=0.18];\n".printf(
                        id, ec, ec));
                    break;

                case StateType.COMPOSITE:
                    // Render as cluster subgraph
                    int my_idx = cluster_idx++;
                    string cluster = "cluster_%d".printf(my_idx);
                    cluster_names.set(state.id, cluster);
                    sb.append("\n  subgraph %s {\n".printf(cluster));
                    sb.append("    label=%s;\n".printf(composite_label(state)));
                    sb.append(border_style == "" ? "    style=rounded;\n" : "    style=\"rounded%s\";\n".printf(border_style));
                    sb.append("    color=\"%s\";\n".printf(border));
                    if (penwidth != "") {
                        sb.append("    penwidth=2;\n");
                    }
                    sb.append("    bgcolor=\"%s\";\n".printf(fill_color));
                    string angle = RenderUtils.gradient_stmt(default_color);
                    if (angle != "") {
                        sb.append("    %s\n".printf(angle));
                    }
                    // Readable on the fill; without it the label took the graph's title colour
                    sb.append("    fontcolor=\"%s\";\n".printf(text_color));

                    // Concurrent regions ("--" / "||" in the body): each region is an unframed
                    // sub-cluster; render_to_svg() draws the dashed separators between them
                    int region_count = 1;
                    foreach (var nested in state.nested_states) {
                        if (!port_parent.has_key(nested.id)) {
                            region_count = int.max(region_count, nested.region + 1);
                        }
                    }
                    var ports = new Gee.ArrayList<State>();
                    var region_nodes = new Gee.ArrayList<Gee.ArrayList<string>>();
                    RegionLayout? regions = null;
                    if (state.region_separator != null && region_count > 1) {
                        regions = new RegionLayout();
                        regions.cluster = cluster;
                        regions.side_by_side = state.region_separator == "||";
                    }
                    for (int r = 0; r < region_count; r++) {
                        string indent = "";
                        if (regions != null) {
                            string region_cluster = "%s_r%d".printf(cluster, r);
                            regions.regions.add(region_cluster);
                            sb.append("    subgraph %s {\n      label=\"\";\n      style=solid;\n      color=\"transparent\";\n      bgcolor=\"transparent\";\n".printf(region_cluster));
                            indent = "  ";
                        }
                        var ids = new Gee.ArrayList<string>();
                        foreach (var nested in state.nested_states) {
                            if (port_parent.has_key(nested.id)) {
                                if (r == 0) {
                                    ports.add(nested);
                                }
                                continue;
                            }
                            if (regions != null && int.min(nested.region, region_count - 1) != r) {
                                continue;
                            }
                            sb.append("  " + indent);
                            append_state_node(sb, diagram, nested, base_color, default_border, ref cluster_idx);
                            if (composite_ids.contains(nested.id)) {
                                collect_inner_ids(nested, ids, false);
                            } else {
                                ids.add(RenderUtils.sanitize_id(nested.id));
                            }
                        }
                        region_nodes.add(ids);
                        if (regions != null) {
                            sb.append("    }\n");
                        }
                    }
                    if (regions != null) {
                        region_layouts.add(regions);
                        // "--" stacks the regions: every node of a region above every node of
                        // the next
                        if (!regions.side_by_side) {
                            for (int r = 0; r + 1 < region_nodes.size; r++) {
                                foreach (string upper in region_nodes[r]) {
                                    foreach (string lower in region_nodes[r + 1]) {
                                        sb.append("    %s -> %s [style=invis];\n".printf(upper, lower));
                                    }
                                }
                            }
                        }
                    }

                    // Entry / exit points, pins and expansion nodes on the border: laid out in
                    // the cluster's first / last rank, then render_to_svg() moves the border
                    // onto them (as ComponentDiagramRenderer does with ports)
                    if (ports.size > 0) {
                        var layout = new PortBorderLayout(cluster);
                        foreach (var port in ports) {
                            bool top = is_top_port(port.state_type);
                            sb.append("  " + port_node(port, top));
                            (top ? layout.top_ports : layout.bottom_ports).add(RenderUtils.sanitize_id(port.id));
                        }
                        var inner = new Gee.ArrayList<string>();
                        collect_inner_ids(state, inner, false);
                        inner.add(id + "_anchor");
                        if (layout.top_ports.size > 0) {
                            sb.append("    { rank=min; %s; }\n".printf(join_ids(layout.top_ports)));
                        }
                        if (layout.bottom_ports.size > 0) {
                            sb.append("    { rank=max; %s; }\n".printf(join_ids(layout.bottom_ports)));
                        }
                        foreach (string node_id in inner) {
                            if (layout.top_ports.size > 0) {
                                sb.append("    %s -> %s [style=invis, weight=0];\n".printf(layout.top_ports[0], node_id));
                            }
                            if (layout.bottom_ports.size > 0) {
                                sb.append("    %s -> %s [style=invis, weight=0];\n".printf(node_id, layout.bottom_ports[0]));
                            }
                        }
                        port_layouts.add(layout);
                    }

                    // Anchor inside the cluster: lhead/ltail only clip an edge at a
                    // cluster border when the endpoint is a node of that cluster.
                    sb.append("    %s_anchor [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(id));

                    sb.append("  }\n");
                    // Points beside the cluster that its self transitions loop through
                    if (composite_loops.has_key(state.id)) {
                        for (int k = 0; k < composite_loops.get(state.id); k++) {
                            sb.append("  %s_loop%d [label=\"\", shape=point, width=0.01, height=0.01, style=invis];\n".printf(id, k));
                        }
                    }
                    break;

                case StateType.CHOICE:
                    // Diamond shape for choice/decision point
                    sb.append("  %s [label=\"\", shape=diamond, style=filled, fillcolor=\"%s\"%s, color=\"%s\", width=0.4, height=0.4];\n".printf(
                        id, fill_color, RenderUtils.gradient_attr(default_color), border));
                    break;

                case StateType.FORK:
                case StateType.JOIN:
                    // Horizontal bar for fork/join
                    sb.append("  %s [label=\"\", shape=box, style=filled, fillcolor=\"%s\", color=\"%s\", width=1.5, height=0.05];\n".printf(
                        id, start_color, start_color));
                    break;

                case StateType.HISTORY:
                case StateType.DEEP_HISTORY:
                    // A small circle with H / H*
                    sb.append("  %s [label=\"%s\", shape=circle, style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", width=0.3, height=0.3, fixedsize=true, fontsize=9];\n".printf(
                        id, state.state_type == StateType.DEEP_HISTORY ? "H*" : "H", fill_color, border, text_color));
                    break;

                case StateType.ENTRY_POINT:
                case StateType.EXIT_POINT:
                case StateType.INPUT_PIN:
                case StateType.OUTPUT_PIN:
                case StateType.EXPANSION_INPUT:
                case StateType.EXPANSION_OUTPUT:
                    // Not inside a composite (inside one, the composite draws it on its border)
                    sb.append(port_node(state, is_top_port(state.state_type)));
                    break;

                default:  // SIMPLE, SDL_RECEIVE
                    string label = state.get_display_label();
                    // Build label with description and entry/exit actions
                    var label_parts = new StringBuilder();
                    label_parts.append(label);

                    if (state.description != null && state.description.length > 0) {
                        label_parts.append("\\n");
                        label_parts.append(RenderUtils.strip_inline_creole(state.description));
                    }
                    if (state.entry_action != null && state.entry_action.length > 0) {
                        label_parts.append("\\nentry / ");
                        label_parts.append(state.entry_action);
                    }
                    if (state.exit_action != null && state.exit_action.length > 0) {
                        label_parts.append("\\nexit / ");
                        label_parts.append(state.exit_action);
                    }

                    // <<sdlreceive>>: a box whose top-left corner render_to_svg() folds
                    bool sdl = state.state_type == StateType.SDL_RECEIVE;
                    sb.append("  %s [label=\"%s\", shape=box, style=\"%sfilled%s\", fillcolor=\"%s\"%s, color=\"%s\", fontcolor=\"%s\"%s%s];\n".printf(
                        id, RenderUtils.escape_label(label_parts.str), sdl ? "" : "rounded,", border_style, fill_color,
                        RenderUtils.gradient_attr(default_color), border, text_color, penwidth,
                        sdl ? ", class=\"gdsdl\", margin=\"0.2,0.1\"" : ""));
                    break;
            }
        }

        public uint8[]? render_to_svg(StateDiagram diagram) {
            string dot = generate_dot(diagram);
            uint8[]? svg_data = RenderUtils.run_graphviz_subprocess(dot, layout_engine, "state");
            if (svg_data == null) {
                return null;
            }
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            if (port_layouts.size > 0) {
                svg = ComponentDiagramRenderer.place_ports_on_border(svg, port_layouts, false);
            }
            svg = draw_region_separators(svg, region_layouts);
            svg = draw_state_shapes(svg, port_fill, port_stroke);
            return svg.data;
        }

        private static string num(double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, "%.2f");
        }

        // Bounding box of the points / path coordinates of the <g class="cluster"> titled `title`
        private static bool cluster_bbox(string svg, string title, out double x0, out double y0,
                                         out double x1, out double y1, out int group_end) {
            x0 = double.MAX;
            y0 = double.MAX;
            x1 = -double.MAX;
            y1 = -double.MAX;
            group_end = -1;
            int t = svg.index_of("<title>%s</title>".printf(title));
            if (t < 0) {
                return false;
            }
            int end = svg.index_of("</g>", t);
            if (end < 0) {
                return false;
            }
            group_end = end;
            points_bbox(svg.substring(t, end - t), ref x0, ref y0, ref x1, ref y1);
            return x0 <= x1 && y0 <= y1;
        }

        private static void points_bbox(string fragment, ref double x0, ref double y0, ref double x1, ref double y1) {
            try {
                var shapes = new Regex("(?:points|d)=\"([^\"]*)\"");
                var pair = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                MatchInfo mi;
                shapes.match(fragment, 0, out mi);
                while (mi.matches()) {
                    string coords = mi.fetch(1);
                    MatchInfo pi;
                    pair.match(coords, 0, out pi);
                    while (pi.matches()) {
                        double x = double.parse(pi.fetch(1));
                        double y = double.parse(pi.fetch(2));
                        x0 = double.min(x0, x);
                        y0 = double.min(y0, y);
                        x1 = double.max(x1, x);
                        y1 = double.max(y1, y);
                        pi.next();
                    }
                    mi.next();
                }
            } catch (RegexError e) {
                warning("State SVG regex: %s", e.message);
            }
        }

        // Dashed lines between the concurrent regions of a composite: horizontal for "--"
        // (regions stacked), vertical for "||" (side by side), across the composite's body
        private static string draw_region_separators(string svg, Gee.ArrayList<RegionLayout> layouts) {
            string result = svg;
            foreach (var layout in layouts) {
                double px0, py0, px1, py1;
                int parent_end;
                if (!cluster_bbox(result, layout.cluster, out px0, out py0, out px1, out py1, out parent_end)) {
                    continue;
                }
                string stroke = "#888888";
                int st = result.substring(0, parent_end).last_index_of("stroke=\"");
                if (st >= 0) {
                    int se = result.index_of("\"", st + 8);
                    stroke = result.substring(st + 8, se - st - 8);
                }
                var boxes = new Gee.ArrayList<double?>();
                double top = double.MAX;
                foreach (string region in layout.regions) {
                    double x0, y0, x1, y1;
                    int e;
                    if (cluster_bbox(result, region, out x0, out y0, out x1, out y1, out e)) {
                        boxes.add(layout.side_by_side ? x0 : y0);
                        boxes.add(layout.side_by_side ? x1 : y1);
                        top = double.min(top, y0);
                    }
                }
                // Regions in drawing order along the separator axis
                var starts = new Gee.ArrayList<int>();
                for (int i = 0; i < boxes.size; i += 2) {
                    starts.add(i);
                }
                starts.sort((a, b) => boxes[a] < boxes[b] ? -1 : (boxes[a] > boxes[b] ? 1 : 0));
                var lines = new StringBuilder();
                for (int k = 0; k + 1 < starts.size; k++) {
                    double pos = (boxes[starts[k] + 1] + boxes[starts[k + 1]]) / 2;
                    if (layout.side_by_side) {
                        lines.append("\n<path class=\"gdregion\" fill=\"none\" stroke=\"%s\" stroke-dasharray=\"5,3\" d=\"M%s,%s L%s,%s\"/>".printf(
                            stroke, num(pos), num(top), num(pos), num(py1)));
                    } else {
                        lines.append("\n<path class=\"gdregion\" fill=\"none\" stroke=\"%s\" stroke-dasharray=\"5,3\" d=\"M%s,%s L%s,%s\"/>".printf(
                            stroke, num(px0), num(pos), num(px1), num(pos)));
                    }
                }
                int end;
                double a, b, c, d;
                cluster_bbox(result, layout.cluster, out a, out b, out c, out d, out end);
                result = result.substring(0, end) + lines.str + "\n" + result.substring(end);
            }
            return result;
        }

        // Shapes Graphviz has no node shape for: the folded
        // <<sdlreceive>> box, and the entry / exit points, pins and expansion nodes drawn over
        // their sentinel cells
        private static string draw_state_shapes(string svg, string port_fill, string port_stroke) {
            if (!svg.contains("gdsdl") && !svg.contains("fill=\"#01020")) {
                return svg;
            }
            string result = svg;
            try {
                var sdl = new Regex("(class=\"node gdsdl\">(?:(?!</g>).)*?<polygon [^>]*?points=\")([^\"]*)(\"/>)",
                                    RegexCompileFlags.DOTALL);
                result = sdl.replace_eval(result, -1, 0, 0, (m, sb) => {
                    double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
                    points_bbox("points=\"%s\"".printf(m.fetch(2)), ref x0, ref y0, ref x1, ref y1);
                    if (x0 > x1) {
                        sb.append(m.fetch(0));
                        return false;
                    }
                    double f = double.min(9, (y1 - y0) / 3);
                    sb.append(m.fetch(1));
                    sb.append("%s,%s %s,%s %s,%s %s,%s %s,%s %s,%s".printf(
                        num(x1), num(y0), num(x0 + f), num(y0), num(x0), num(y0 + f),
                        num(x0), num(y1), num(x1), num(y1), num(x1), num(y0)));
                    sb.append(m.fetch(3));
                    string stroke = "#000000";
                    string full = m.fetch(1);
                    int si = full.last_index_of("stroke=\"");
                    if (si >= 0) {
                        stroke = full.substring(si + 8, full.index_of("\"", si + 8) - si - 8);
                    }
                    sb.append("\n<path class=\"gdfold\" fill=\"none\" stroke=\"%s\" d=\"M%s,%s L%s,%s L%s,%s\"/>".printf(
                        stroke, num(x0 + f), num(y0), num(x0 + f), num(y0 + f), num(x0), num(y0 + f)));
                    return false;
                });

                var port = new Regex("<polygon fill=\"#01020([4-7])\" stroke=\"none\" points=\"([^\"]*)\"/>");
                string fill = paint_value(port_fill);
                string stroke = paint_value(port_stroke);
                result = port.replace_eval(result, -1, 0, 0, (m, sb) => {
                    double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
                    points_bbox("points=\"%s\"".printf(m.fetch(2)), ref x0, ref y0, ref x1, ref y1);
                    if (x0 > x1) {
                        return false;
                    }
                    string sentinel = m.fetch(1);
                    string kind = sentinel == "4" ? "gdentry" : sentinel == "5" ? "gdexit" : sentinel == "7" ? "gdexpansion" : "gdpin";
                    double cx = (x0 + x1) / 2;
                    double cy = (y0 + y1) / 2;
                    double h = y1 - y0;
                    if (kind == "gdentry" || kind == "gdexit") {
                        double r = h / 2 - 0.5;
                        sb.append("<circle class=\"gdportshape\" cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.2\"/>".printf(
                            num(cx), num(cy), num(r), fill, stroke));
                        if (kind == "gdexit") {
                            double k = r * 0.7;
                            sb.append("<path class=\"gdportshape\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.2\" d=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/>".printf(
                                stroke, num(cx - k), num(cy - k), num(cx + k), num(cy + k),
                                num(cx - k), num(cy + k), num(cx + k), num(cy - k)));
                        }
                    } else if (kind == "gdexpansion") {
                        sb.append("<rect class=\"gdportshape\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.2\"/>".printf(
                            num(x0 + 0.5), num(y0 + 0.5), num(x1 - x0 - 1), num(h - 1), fill, stroke));
                        var d = new StringBuilder();
                        double w = (x1 - x0 - 1) / 4;
                        for (int i = 1; i < 4; i++) {
                            d.append("M%s,%s L%s,%s ".printf(num(x0 + 0.5 + w * i), num(y0 + 0.5), num(x0 + 0.5 + w * i), num(y1 - 0.5)));
                        }
                        sb.append("<path class=\"gdportshape\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.2\" d=\"%s\"/>".printf(
                            stroke, d.str.strip()));
                    } else {
                        sb.append("<rect class=\"gdportshape\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.2\"/>".printf(
                            num(x0 + 0.5), num(y0 + 0.5), num(x1 - x0 - 1), num(h - 1), fill, stroke));
                    }
                    return false;
                });
            } catch (RegexError e) {
                warning("State SVG shapes: %s", e.message);
                return svg;
            }
            return result;
        }

        // A Graphviz colour as an SVG colour: "#0A4A89" stays, "Gold" stays, "#FF000080" -> "#FF0000"
        private static string paint_value(string color) {
            string token = color.has_prefix("#") ? color.substring(1) : color;
            bool hex = token.length == 6 || token.length == 3 || token.length == 8;
            for (int i = 0; hex && i < token.length; i++) {
                hex = token[i].isxdigit();
            }
            if (!hex) {
                return token.down() == "transparent" ? "none" : token;
            }
            return "#" + (token.length == 8 ? token.substring(0, 6) : token);
        }

        // Source lines of every state, nested ones included, by id and label
        private static void collect_element_lines(Gee.List<State> states, Gee.HashMap<string, int> into) {
            foreach (var state in states) {
                if (state.source_line > 0) {
                    into.set(state.id, state.source_line);
                    if (state.label != null && state.label.length > 0) {
                        into.set(state.label, state.source_line);
                    }
                }
                collect_element_lines(state.nested_states, into);
            }
        }

        public Cairo.ImageSurface? render_to_surface(StateDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            // Length-aware cast (avoid strlen overread past the array end).
            string svg_str;
            if (svg_data.length == 0) {
                svg_str = "";
            } else {
                unowned string raw = (string) svg_data;
                int safe_len = int.min(raw.length, (int) svg_data.length);
                svg_str = (raw.length == svg_data.length)
                    ? raw
                    : raw.substring(0, safe_len);
            }
            if (svg_str != null && svg_str.length > 0) {
                // Ensure xml:space="preserve" on all <text> elements without duplicating
                svg_str = svg_str.replace(" xml:space=\"preserve\"", "");
                svg_str = svg_str.replace("<text ", "<text xml:space=\"preserve\" ");
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_str.data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                // Element line numbers, nested states included (only top-level ones mapped)
                var element_lines = new Gee.HashMap<string, int>();
                collect_element_lines(diagram.states, element_lines);

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
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(StateDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
