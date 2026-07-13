namespace GDiagram {
    public class ActivityDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;
        private SkinParams? current_skin_params;
        private ActivityDiagram? current_diagram;
        private bool is_multilevel_list;
        private string dot_binary;

        public ActivityDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
            this.current_skin_params = null;
            // Prefer patched binary at /usr/local for HTML-TABLE text centering;
            // fall back to system dot when patched build is not installed.
            if (FileUtils.test("/usr/local/bin/dot", FileTest.IS_EXECUTABLE)) {
                this.dot_binary = "/usr/local/bin/dot";
            } else {
                this.dot_binary = "dot";
            }
        }

        public string generate_dot(ActivityDiagram diagram) {
            var sb = new StringBuilder();

            // Check if diagram has multi-level lists (for formatting decisions)
            this.is_multilevel_list = false;
            foreach (var node in diagram.nodes) {
                if (node.indent_level >= 2) {
                    this.is_multilevel_list = true;
                    break;
                }
            }

            // Get theme values — palette slots fall in where skin_params
            // doesn't override. "black" fallbacks are kept for the arrow
            // label so that existing diagrams with explicit arrow coloring
            // still work identically.
            var palette = ThemeManager.get_active_palette();
            string bg_color = RenderUtils.sanitize_color(diagram.skin_params.background_color ?? palette.background);
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "13";
            string font_color = RenderUtils.sanitize_color(diagram.skin_params.default_font_color ?? palette.node_text);
            string arrow_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("arrow", "Color") ?? palette.edge_color);
            string arrow_font_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("arrow", "FontColor") ?? font_color);

            // Store skin_params in a local variable for use in helper methods
            this.current_skin_params = diagram.skin_params;
            this.current_diagram = diagram;

            sb.append("digraph activity {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  newrank=true;\n");
            sb.append("  splines=polyline;\n");
            sb.append("  pad=\"0.15,0.19\";\n");
            sb.append("  labeljust=l;\n");
            sb.append("  ranksep=0.28;\n");
            sb.append("  nodesep=0.15;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\", arrowhead=vee];\n".printf(font_name, arrow_color, arrow_font_color));
            sb.append("  compound=true;\n");

            // Add title/header at top
            if ((diagram.title != null && diagram.title.length > 0) ||
                (diagram.header != null && diagram.header.length > 0)) {
                sb.append("  labelloc=\"t\";\n");
                var label_parts = new Gee.ArrayList<string>();
                if (diagram.header != null && diagram.header.length > 0) {
                    label_parts.add(RenderUtils.escape_label(diagram.header));
                }
                if (diagram.title != null && diagram.title.length > 0) {
                    label_parts.add(RenderUtils.escape_label(diagram.title));
                }
                sb.append("  label=\"%s\";\n".printf(string.joinv("\\n", label_parts.to_array())));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
                sb.append("  fontcolor=\"%s\";\n".printf(RenderUtils.title_color(diagram.skin_params, palette)));
            }

            // Add footer at bottom using xlabel on a dummy node
            if (diagram.footer != null && diagram.footer.length > 0) {
                // We'll add a footer node at the end
            }

            sb.append("\n");

            // Group nodes by partition
            var partition_nodes = new Gee.HashMap<string, Gee.ArrayList<ActivityNode>>();
            var no_partition_nodes = new Gee.ArrayList<ActivityNode>();

            foreach (var node in diagram.nodes) {
                if (node.partition != null && node.partition.length > 0) {
                    if (!partition_nodes.has_key(node.partition)) {
                        partition_nodes.set(node.partition, new Gee.ArrayList<ActivityNode>());
                    }
                    partition_nodes.get(node.partition).add(node);
                } else {
                    no_partition_nodes.add(node);
                }
            }

            // Render partitions as subgraphs (clusters), nested groups and
            // partitions inside their parent, in source order
            var drawn_keys = new Gee.ArrayList<string>();
            // A declared lane is drawn even when empty, as PlantUML draws the column
            foreach (var p in diagram.partitions) {
                if (p.is_swimlane && p.parent == null && !drawn_keys.contains(p.key)) {
                    drawn_keys.add(p.key);
                }
            }
            foreach (var key in partition_nodes.keys) {
                string? k = key;
                while (k != null && !drawn_keys.contains(k)) {
                    drawn_keys.add(k);
                    var p = find_partition(diagram, k);
                    k = p != null ? p.parent : null;
                }
            }
            var ordered_keys = new Gee.ArrayList<string>();
            foreach (var p in diagram.partitions) {
                if (drawn_keys.contains(p.key) && !ordered_keys.contains(p.key)) {
                    ordered_keys.add(p.key);
                }
            }
            foreach (var key in drawn_keys) {
                if (!ordered_keys.contains(key)) {
                    ordered_keys.add(key);
                }
            }
            // Top-level swimlanes, left to right in declaration order
            var lane_keys = new Gee.ArrayList<string>();
            foreach (var key in ordered_keys) {
                var p = find_partition(diagram, key);
                if (p != null && p.is_swimlane && (p.parent == null || !ordered_keys.contains(p.parent))) {
                    lane_keys.add(key);
                }
            }
            int cluster_idx = 0;
            foreach (var key in ordered_keys) {
                var p = find_partition(diagram, key);
                if (p == null || p.parent == null || !ordered_keys.contains(p.parent)) {
                    append_partition_cluster(sb, diagram, key, ordered_keys, partition_nodes, ref cluster_idx, "  ",
                                             lane_keys.index_of(key));
                }
            }
            append_swimlane_columns(sb, diagram, lane_keys);

            // Render nodes without partitions
            sb.append("  // Nodes without partition\n");
            foreach (var node in no_partition_nodes) {
                append_activity_node(sb, node);
            }
            sb.append("\n");

            // Track if/else branch edges for port-based routing
            var condition_yes_edges = new Gee.HashMap<string, ActivityEdge>();
            var condition_no_edges = new Gee.HashMap<string, ActivityEdge>();

            foreach (var edge in diagram.edges) {
                if (edge.from.node_type == ActivityNodeType.CONDITION) {
                    if (edge.is_yes_branch) {
                        condition_yes_edges.set(edge.from.id, edge);
                    } else if (edge.is_no_branch) {
                        condition_no_edges.set(edge.from.id, edge);
                    }
                }
            }

            // Create edges
            sb.append("  // Edges\n");
            foreach (var edge in diagram.edges) {
                string label = edge.label != null ? RenderUtils.escape_label(edge.label) : "";
                // A multi-line or Creole label ("-> line one\nand **three**;") is an HTML
                // label, lines left-aligned as PlantUML draws them
                string label_attr = "label=\"%s\"".printf(label);
                if (label != "" && RenderUtils.has_creole_formatting(edge.label)) {
                    label_attr = "label=<%s>".printf(edge_label_html(edge.label));
                }

                // Check for multi-colored arrows (semicolon-separated colors)
                string[]? multi_colors = null;
                if (edge.color != null && edge.color.contains(";")) {
                    multi_colors = edge.color.split(";");
                }

                if (multi_colors != null && multi_colors.length > 1) {
                    // Create multiple parallel edges for multi-colored arrows
                    int color_count = multi_colors.length;
                    for (int i = 0; i < color_count; i++) {
                        var attrs = new Gee.ArrayList<string>();
                        string c = multi_colors[i].strip();

                        // Only first edge gets the label
                        if (i == 0 && label != "") {
                            attrs.add(label_attr);
                        }

                        if (c.length > 0) {
                            attrs.add("color=\"%s\"".printf(c));
                            if (i == 0) {
                                attrs.add("fontcolor=\"%s\"".printf(c));
                            }
                        }

                        if (edge.style != null && edge.style.length > 0) {
                            string gv_style = edge.style == "hidden" ? "invis" : edge.style;
                            attrs.add("style=\"%s\"".printf(gv_style));
                        }

                        // Note only on first edge
                        if (i == 0 && edge.note != null && edge.note.length > 0) {
                            attrs.add("xlabel=\"%s\"".printf(RenderUtils.escape_label(edge.note)));
                        }

                        // Direction hints
                        switch (edge.direction) {
                            case EdgeDirection.UP:
                                attrs.add("dir=back");
                                break;
                            case EdgeDirection.LEFT:
                            case EdgeDirection.RIGHT:
                                attrs.add("constraint=false");
                                break;
                            default:
                                break;
                        }

                        // Use constraint=false for non-first edges to allow parallel placement
                        if (i > 0) {
                            attrs.add("constraint=false");
                        }

                        sb.append("  %s -> %s [%s];\n".printf(
                            edge.from.id, edge.to.id, string.joinv(", ", attrs.to_array())
                        ));
                    }
                } else {
                    // Single color edge (original behavior)
                    var attrs = new Gee.ArrayList<string>();

                    if (label != "") {
                        attrs.add(label_attr);
                    }

                    // Handle edge coloring
                    if (edge.label_color != null && edge.label_color.length > 0) {
                        // Label-only color: explicitly keep arrow at default, color only label
                        attrs.add("color=\"%s\"".printf(arrow_color));
                        attrs.add("fontcolor=\"%s\"".printf(edge.label_color));
                    } else if (edge.color != null && edge.color.length > 0) {
                        // Full edge color: both arrow and label
                        attrs.add("color=\"%s\"".printf(edge.color));
                        attrs.add("fontcolor=\"%s\"".printf(edge.color));
                    } else if (label != "") {
                        // The theme's label colour can vanish on a coloured lane or partition
                        // (light text on beige in the dark theme): contrast with that fill.
                        // The label sits mid-edge, over either end's background: when the
                        // two need different text, it gets a patch of the source's background.
                        string? from_bg = node_background(diagram, edge.from);
                        string? to_bg = node_background(diagram, edge.to);
                        string from_text = from_bg != null ? RenderUtils.contrast_text(from_bg) : arrow_font_color;
                        string to_text = to_bg != null ? RenderUtils.contrast_text(to_bg) : arrow_font_color;
                        if (is_light_color(from_text) != is_light_color(to_text)) {
                            string patch = bg_color;
                            if (from_bg != null) {
                                int colon = from_bg.index_of(":");  // a gradient's first colour
                                patch = colon > 0 ? from_bg.substring(0, colon) : from_bg;
                            }
                            attrs.remove(label_attr);
                            attrs.insert(0, ("label=<<table border=\"0\" cellborder=\"0\" cellspacing=\"0\" " +
                                "cellpadding=\"1\" bgcolor=\"%s\"><tr><td>%s</td></tr></table>>").printf(
                                patch, RenderUtils.convert_creole_to_html(edge.label)));
                            attrs.add("fontcolor=\"%s\"".printf(from_text));
                        } else if (from_bg != null) {
                            attrs.add("fontcolor=\"%s\"".printf(from_text));
                        }
                    }
                    if (edge.to.node_type == ActivityNodeType.KILL ||
                        edge.to.node_type == ActivityNodeType.DETACH) {
                        // The flow just stops: PlantUML draws no arrow into kill/detach
                        attrs.add("style=\"invis\"");
                    } else if (edge.style != null && edge.style.length > 0) {
                        // Convert PlantUML "hidden" to Graphviz "invis"
                        string gv_style = edge.style == "hidden" ? "invis" : edge.style;
                        attrs.add("style=\"%s\"".printf(gv_style));
                    }

                    // Note on link - displayed as xlabel (external label)
                    if (edge.note != null && edge.note.length > 0) {
                        attrs.add("xlabel=\"%s\"".printf(RenderUtils.escape_label(edge.note)));
                    }

                    // Handle direction hints
                    switch (edge.direction) {
                        case EdgeDirection.UP:
                            attrs.add("dir=back");
                            break;
                        case EdgeDirection.LEFT:
                        case EdgeDirection.RIGHT:
                            attrs.add("constraint=false");
                            break;
                        default:
                            break;
                    }

                    // Force vertical spacing after merge points in same partition
                    if (edge.from.node_type == ActivityNodeType.MERGE &&
                        edge.from.partition == edge.to.partition &&
                        edge.from.partition != null) {
                        attrs.add("minlen=2");
                    }

                    // Build edge string with optional port positions for symmetric branches
                    string from_port = "";
                    string to_port = "";

                    // A repeat's loop-back edge (condition back to an earlier node) must not
                    // rank the condition above the loop start: route it up the right side
                    bool repeat_loop_back = is_loop_back(diagram, edge);

                    // For condition (diamond) nodes, use ports for branch exits
                    if (repeat_loop_back) {
                        attrs.add("constraint=false");
                        from_port = ":e";
                        to_port = ":e";
                    } else if (edge.is_no_branch && is_repeat_condition(diagram, edge.from)) {
                        // The loop exit continues straight down, as in PlantUML
                        from_port = ":s";
                    }
                    if (is_passthrough_merge(diagram, edge.to)) {
                        // The pass-through point is invisible: the arrowhead goes on its outgoing edge
                        attrs.add("arrowhead=none");
                        if (!has_outgoing(diagram, edge.to)) {
                            // Nothing follows (a repeat at the very end): PlantUML draws
                            // only the exit label, no line
                            attrs.add("color=\"transparent\"");
                        }
                    }
                    if (repeat_loop_back || (edge.is_no_branch && is_repeat_condition(diagram, edge.from))) {
                        // ports set above
                    } else if (edge.from.node_type == ActivityNodeType.CONDITION) {
                        if (diagram.use_vertical_if) {
                            // Vertical mode: yes exits right, no exits down
                            if (edge.is_yes_branch) {
                                from_port = ":e";   // East exit for yes (horizontal right)
                            } else if (edge.is_no_branch) {
                                from_port = ":s";   // South exit for no (straight down)
                            }
                        } else {
                            // Default mode: symmetric diagonal exits
                            if (edge.is_yes_branch) {
                                from_port = ":sw";  // Southwest exit for yes/left branch
                            } else if (edge.is_no_branch) {
                                from_port = ":se";  // Southeast exit for no/right branch
                            }
                        }
                    }

                    // A split's lines: one port per branch, so each branch leaves and
                    // rejoins straight down
                    int split_out = split_port_index(diagram, edge, true);
                    if (split_out >= 0) {
                        from_port = ":b%d:s".printf(split_out);
                    }
                    int split_in = split_port_index(diagram, edge, false);
                    if (split_in >= 0) {
                        to_port = ":b%d:n".printf(split_in);
                    }

                    string from_node = edge.from.id + from_port;
                    string to_node = edge.to.id + to_port;

                    if (attrs.size > 0) {
                        sb.append("  %s -> %s [%s];\n".printf(
                            from_node, to_node, string.joinv(", ", attrs.to_array())
                        ));
                    } else {
                        sb.append("  %s -> %s;\n".printf(from_node, to_node));
                    }
                }
            }

            // Create notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                foreach (var note in diagram.notes) {
                    // A note on a node in a lane or partition is defined in that cluster
                    if (note.attached_to == null || note.attached_to.partition == null ||
                        note.attached_to.partition.length == 0) {
                        sb.append("  " + note_definition(note));
                    }

                    // Connect note to attached node
                    if (note.attached_to != null) {
                        switch (note.position) {
                            case NotePosition.LEFT:
                                // Note on left: note -> node (note comes first)
                                sb.append("  %s -> %s [style=invis];\n".printf(
                                    note.id, note.attached_to.id
                                ));
                                // Dashed connector line (none for a floating note)
                                if (!note.floating) {
                                    sb.append("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n".printf(
                                        note.attached_to.id, note.id
                                    ));
                                }
                                // Same rank to keep horizontal
                                sb.append("  { rank=same; %s; %s; }\n".printf(
                                    note.attached_to.id, note.id
                                ));
                                break;

                            case NotePosition.RIGHT:
                                // Note on right: node -> note (node comes first)
                                sb.append("  %s -> %s [style=invis];\n".printf(
                                    note.attached_to.id, note.id
                                ));
                                // Dashed connector line (none for a floating note)
                                if (!note.floating) {
                                    sb.append("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n".printf(
                                        note.attached_to.id, note.id
                                    ));
                                }
                                // Same rank to keep horizontal
                                sb.append("  { rank=same; %s; %s; }\n".printf(
                                    note.attached_to.id, note.id
                                ));
                                break;

                            case NotePosition.TOP:
                                // Note above: note -> node (vertical ordering)
                                sb.append("  %s -> %s [style=%s, arrowhead=none];\n".printf(
                                    note.id, note.attached_to.id, note.floating ? "invis" : "dashed"
                                ));
                                break;

                            case NotePosition.BOTTOM:
                                // Note below: node -> note (vertical ordering)
                                sb.append("  %s -> %s [style=%s, arrowhead=none];\n".printf(
                                    note.attached_to.id, note.id, note.floating ? "invis" : "dashed"
                                ));
                                break;
                        }
                    }
                }
            }

            // Add footer as a label node at the bottom
            string? connect_from = null;
            if (diagram.nodes.size > 0) {
                connect_from = diagram.nodes.get(diagram.nodes.size - 1).id;
            }

            if (diagram.footer != null && diagram.footer.length > 0) {
                sb.append("\n  // Footer\n");
                sb.append("  footer [shape=plaintext, label=\"%s\", fontsize=10, fontname=\"Sans\"];\n".printf(
                    RenderUtils.escape_label(diagram.footer)
                ));
                if (connect_from != null) {
                    sb.append("  %s -> footer [style=invis];\n".printf(connect_from));
                }
                connect_from = "footer";
            }

            // Add caption below footer (italic style)
            if (diagram.caption != null && diagram.caption.length > 0) {
                sb.append("\n  // Caption\n");
                sb.append("  caption [shape=plaintext, label=\"%s\", fontsize=9, fontname=\"Sans Italic\"];\n".printf(
                    RenderUtils.escape_label(diagram.caption)
                ));
                if (connect_from != null) {
                    sb.append("  %s -> caption [style=invis];\n".printf(connect_from));
                }
            }

            // Add legend
            if (diagram.legend != null && diagram.legend.text.length > 0) {
                sb.append("\n  // Legend\n");
                bool legend_use_html = RenderUtils.has_creole_formatting(diagram.legend.text);
                string legend_label;

                string legend_bg = ThemeManager.get_active_palette().accent_secondary;
                if (legend_use_html) {
                    legend_label = RenderUtils.convert_creole_to_html(diagram.legend.text);
                    sb.append("  legend_node [shape=box, style=\"filled\", fillcolor=\"%s\", ".printf(legend_bg));
                    sb.append("label=<%s>, fontsize=9, fontname=\"Sans\"];\n".printf(legend_label));
                } else {
                    legend_label = RenderUtils.escape_label(diagram.legend.text);
                    // Replace \n with \l for left-aligned lines in Graphviz
                    string? temp_legend = legend_label.replace("\n", "\\l");
                    if (temp_legend != null) legend_label = temp_legend;
                    sb.append("  legend_node [shape=box, style=\"filled\", fillcolor=\"%s\", ".printf(legend_bg));
                    sb.append("label=\"%s\\l\", fontsize=9, fontname=\"Sans\"];\n".printf(legend_label));
                }

                // Position based on legend position setting
                switch (diagram.legend.position) {
                    case LegendPosition.LEFT:
                        // Put legend on left side by constraining with first node
                        if (diagram.nodes.size > 0) {
                            sb.append("  { rank=same; legend_node; %s; }\n".printf(diagram.nodes.get(0).id));
                            sb.append("  legend_node -> %s [style=invis];\n".printf(diagram.nodes.get(0).id));
                        }
                        break;
                    case LegendPosition.RIGHT:
                        // Put legend on right side
                        if (diagram.nodes.size > 0) {
                            sb.append("  { rank=same; %s; legend_node; }\n".printf(diagram.nodes.get(0).id));
                            sb.append("  %s -> legend_node [style=invis];\n".printf(diagram.nodes.get(0).id));
                        }
                        break;
                    case LegendPosition.CENTER:
                        // Center: place at bottom
                        if (connect_from != null) {
                            sb.append("  %s -> legend_node [style=invis];\n".printf(connect_from));
                        }
                        break;
                }
            }

            // Add rank constraints and invisible edges for proper centering
            sb.append("\n  // Layout constraints for if/else structures\n");

            // Find elseif chains (connected condition nodes) for horizontal alignment
            var elseif_chains = new Gee.ArrayList<Gee.ArrayList<string>>();
            var visited_conditions = new Gee.HashSet<string>();

            foreach (var node in diagram.nodes) {
                if (node.node_type == ActivityNodeType.CONDITION && !visited_conditions.contains(node.id)) {
                    var chain = new Gee.ArrayList<string>();
                    chain.add(node.id);
                    visited_conditions.add(node.id);

                    // Follow elseif edges to find chained conditions. Any no-branch edge
                    // also chained an if whose "no" leads to the next if or repeat
                    // condition, ranking them side by side.
                    var current_cond = node;
                    foreach (var edge in diagram.edges) {
                        if (edge.from == current_cond && edge.is_no_branch && edge.is_elseif) {
                            if (edge.to.node_type == ActivityNodeType.CONDITION) {
                                chain.add(edge.to.id);
                                visited_conditions.add(edge.to.id);
                                current_cond = edge.to;
                            }
                        }
                    }

                    // If chain has 2+ conditions, it's an elseif chain
                    if (chain.size >= 2) {
                        elseif_chains.add(chain);
                    }
                }
            }

            // Layout elseif chains based on vertical mode
            if (!diagram.use_vertical_if) {
                // Horizontal mode: align conditions in a row
                foreach (var chain in elseif_chains) {
                    if (chain.size >= 2) {
                        sb.append("  { rank=same; %s; }\n".printf(string.joinv("; ", chain.to_array())));
                    }
                }
            } else {
                // Vertical mode: create vertical spines for both conditions and text boxes
                foreach (var chain in elseif_chains) {
                    if (chain.size >= 2) {
                        // Add invisible edges to create vertical spine through conditions
                        for (int i = 0; i < chain.size - 1; i++) {
                            sb.append("  %s -> %s [style=invis, weight=100];\n".printf(chain[i], chain[i+1]));
                        }

                        // Find yes-branch text nodes for vertical alignment on right
                        var text_nodes = new Gee.ArrayList<string>();
                        foreach (var cond_id in chain) {
                            foreach (var edge in diagram.edges) {
                                if (edge.from.id == cond_id && edge.is_yes_branch &&
                                    edge.to.node_type == ActivityNodeType.ACTION) {
                                    text_nodes.add(edge.to.id);
                                    break;
                                }
                            }
                        }

                        // Create vertical spine through text boxes on right
                        if (text_nodes.size >= 2) {
                            for (int i = 0; i < text_nodes.size - 1; i++) {
                                sb.append("  %s -> %s [style=invis, weight=50];\n".printf(text_nodes[i], text_nodes[i+1]));
                            }
                        }
                    }
                }
            }

            // Find all merge nodes and their incoming branches
            var merge_nodes = new Gee.HashSet<string>();
            var branch_pairs = new Gee.HashMap<string, Gee.ArrayList<string>>();
            var condition_for_merge = new Gee.HashMap<string, string>();

            foreach (var node in diagram.nodes) {
                if (node.node_type == ActivityNodeType.MERGE) {
                    merge_nodes.add(node.id);
                    branch_pairs.set(node.id, new Gee.ArrayList<string>());
                }
            }

            // Find branches and their parent condition for each merge
            foreach (var edge in diagram.edges) {
                // A repeat's loop-back into its start diamond is not a branch to centre
                bool loop_back = is_loop_back(diagram, edge);
                // Nor is a branch without statements (an if without else): ranking its
                // condition beside the other branch put the branch next to the diamond
                bool direct_branch = edge.from.node_type == ActivityNodeType.CONDITION &&
                    (edge.is_yes_branch || edge.is_no_branch);
                if (merge_nodes.contains(edge.to.id) && !loop_back && !direct_branch) {
                    branch_pairs.get(edge.to.id).add(edge.from.id);
                }

                // Track condition -> branch connections
                if (edge.from.node_type == ActivityNodeType.CONDITION &&
                    (edge.is_yes_branch || edge.is_no_branch)) {
                    // This branch came from a condition
                    string branch_id = edge.to.id;
                    string cond_id = edge.from.id;

                    // Find which merge this branch leads to
                    foreach (var e2 in diagram.edges) {
                        if (e2.from.id == branch_id && merge_nodes.contains(e2.to.id)) {
                            condition_for_merge.set(e2.to.id, cond_id);
                            break;
                        }
                    }
                }
            }

            // For each merge with 2+ branches, add centering constraints
            foreach (var entry in branch_pairs.entries) {
                string merge_id = entry.key;
                var branches = entry.value;

                if (branches.size == 2) {
                    // Make branches same rank (horizontally aligned)
                    sb.append("  { rank=same; %s; %s; }\n".printf(branches[0], branches[1]));

                    // Add invisible edge from condition to merge for vertical spine
                    if (condition_for_merge.has_key(merge_id)) {
                        string cond_id = condition_for_merge.get(merge_id);
                        sb.append("  %s -> %s [style=invis, weight=100];\n".printf(cond_id, merge_id));
                    }
                } else if (branches.size > 2) {
                    // Multiple branches (like split): align ONLY single-action branches
                    // (branches where one node goes: split → node → merge)

                    // First, find the split bar node
                    string? split_node_id = null;
                    foreach (var branch_id in branches) {
                        foreach (var edge in diagram.edges) {
                            if (edge.to.id == branch_id && edge.from.node_type == ActivityNodeType.FORK) {
                                split_node_id = edge.from.id;
                                break;
                            }
                        }
                        if (split_node_id != null) break;
                    }

                    // Find single-action branches: split → node → merge (nothing in between)
                    var single_action_branches = new Gee.ArrayList<string>();
                    if (split_node_id != null) {
                        foreach (var branch_id in branches) {
                            bool from_split = false;
                            bool to_merge = false;

                            // Check if branch comes from split
                            foreach (var edge in diagram.edges) {
                                if (edge.from.id == split_node_id && edge.to.id == branch_id) {
                                    from_split = true;
                                    break;
                                }
                            }

                            // Check if branch goes directly to merge
                            foreach (var edge in diagram.edges) {
                                if (edge.from.id == branch_id && edge.to.id == merge_id) {
                                    to_merge = true;
                                    break;
                                }
                            }

                            // Single-action branch: comes from split AND goes to merge directly
                            if (from_split && to_merge) {
                                single_action_branches.add(branch_id);
                            }
                        }
                    }

                    // Align all single-action branches horizontally (e.g., A, B, C)
                    if (single_action_branches.size >= 2) {
                        sb.append("  { rank=same; %s; }\n".printf(string.joinv("; ", single_action_branches.to_array())));
                    }
                }
            }

            // Add invisible spine edges for repeat loops to enforce vertical alignment
            sb.append("\n  // Vertical spine for repeat loops\n");

            // Find repeat loops (condition with loop-back to entry node)
            var repeat_conditions = new Gee.ArrayList<ActivityNode>();
            var repeat_entries = new Gee.HashMap<string, string>(); // condition -> entry

            foreach (var edge in diagram.edges) {
                // Find loop-back edges (condition pointing backward)
                if (edge.from.node_type == ActivityNodeType.CONDITION) {
                    // Check if there's an edge from this condition that points to an earlier node
                    foreach (var e2 in diagram.edges) {
                        if (e2.from == edge.from && e2.to != edge.to) {
                            // Found condition with multiple outgoing edges
                            // If one edge is a loop-back (to an earlier node), it's a repeat/while
                            int from_idx = diagram.nodes.index_of(edge.from);
                            int to_idx = diagram.nodes.index_of(edge.to);
                            if (to_idx < from_idx) {
                                // Loop-back detected
                                repeat_conditions.add(edge.from);
                                repeat_entries.set(edge.from.id, edge.to.id);
                                break;
                            }
                        }
                    }
                }
            }

            // For each repeat condition, create vertical spine from entry to condition
            foreach (var cond in repeat_conditions) {
                if (repeat_entries.has_key(cond.id)) {
                    string entry_id = repeat_entries.get(cond.id);
                    // Add invisible edge from entry to condition for vertical spine
                    sb.append("  %s -> %s [style=invis, weight=100];\n".printf(entry_id, cond.id));
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        // The fill behind a node: its innermost coloured lane or partition, null for the
        // theme background (an uncoloured partition box has the theme's grid fill)
        private string? node_background(ActivityDiagram diagram, ActivityNode node) {
            string? key = node.partition;
            int depth = 0;
            while (key != null && depth < 64) {
                var partition = find_partition(diagram, key);
                if (partition == null) {
                    return null;
                }
                if (partition.color != null) {
                    return RenderUtils.fill_color(partition.color);
                }
                if (!partition.is_swimlane) {
                    return null;
                }
                key = partition.parent;
                depth++;
            }
            return null;
        }

        // Whether a colour is light (it needs dark text)
        private static bool is_light_color(string color) {
            return RenderUtils.contrast_text(color) == "#000000";
        }

        // HTML for a multi-line / Creole edge label, lines left-aligned
        private static string edge_label_html(string text) {
            string html = RenderUtils.convert_creole_to_html(text)
                .replace("<BR/>", "<br align=\"left\"/>").replace("<br/>", "<br align=\"left\"/>");
            return html + "<br align=\"left\"/>";
        }

        // The port of an edge leaving (outgoing) or entering a split line: the edge's
        // position among that node's visible edges. -1 when the node isn't a split line.
        private int split_port_index(ActivityDiagram diagram, ActivityEdge edge, bool outgoing) {
            ActivityNode node = outgoing ? edge.from : edge.to;
            // Branches leave the top line (the FORK) and rejoin the bottom one (the MERGE)
            ActivityNodeType branch_side = outgoing ? ActivityNodeType.FORK : ActivityNodeType.MERGE;
            if (!node.is_split || node.node_type != branch_side) {
                return -1;
            }
            int index = 0;
            foreach (var e in diagram.edges) {
                if ((outgoing ? e.from : e.to) != node || e.style == "hidden") {
                    continue;
                }
                if (e == edge) {
                    return index;
                }
                index++;
            }
            return -1;
        }

        // A split's horizontal line: a row of cells, one per branch, each with the
        // branch's port. The cell width follows the branch's first (or last) node; the
        // line runs from the first branch's centre to the last one's, as in PlantUML.
        private void append_split_line(StringBuilder sb, ActivityNode node) {
            var widths = new Gee.ArrayList<int>();
            string color = node.color != null ? RenderUtils.sanitize_color(node.color) : split_line_color();
            if (current_diagram != null) {
                bool outgoing = node.node_type == ActivityNodeType.FORK;
                foreach (var e in current_diagram.edges) {
                    if ((outgoing ? e.from : e.to) != node || e.style == "hidden") {
                        continue;
                    }
                    ActivityNode other = outgoing ? e.to : e.from;
                    int width = 66;
                    if (other.node_type == ActivityNodeType.ACTION && other.label != null) {
                        int longest = 0;
                        foreach (string line in other.label.split("\n")) {
                            longest = int.max(longest, line.char_count());
                        }
                        width = int.max(width, longest * 8 + 28);
                    }
                    widths.add(width);
                }
            }
            if (widths.size == 0) {
                widths.add(66);
            }
            var cells = new StringBuilder();
            int n = widths.size;
            for (int i = 0; i < n; i++) {
                int half = widths[i] / 2;
                string left = (i > 0) ? color : "transparent";
                string right = (i < n - 1) ? color : "transparent";
                if (n == 1) {
                    left = color;
                    right = color;
                }
                cells.append(("<td port=\"b%d\" cellpadding=\"0\"><table border=\"0\" cellborder=\"0\" cellspacing=\"0\" cellpadding=\"0\"><tr>" +
                    "<td width=\"%d\" height=\"1\" fixedsize=\"true\" bgcolor=\"%s\"></td>" +
                    "<td width=\"%d\" height=\"1\" fixedsize=\"true\" bgcolor=\"%s\"></td></tr></table></td>").printf(
                    i, half, left, widths[i] - half, right));
            }
            sb.append("  %s [shape=plaintext, margin=0, width=0, height=0, label=<<table border=\"0\" cellborder=\"0\" cellspacing=\"0\" cellpadding=\"0\"><tr>%s</tr></table>>];\n".printf(
                node.id, cells.str));
        }

        private string split_line_color() {
            string? arrow = current_skin_params != null ? current_skin_params.get_element_property("arrow", "Color") : null;
            return RenderUtils.sanitize_color(arrow ?? ThemeManager.get_active_palette().edge_color);
        }

        // Diamonds (conditions and merges) take the activity's diamond colours, as in
        // PlantUML: DiamondBackgroundColor, else the action background
        private string diamond_fill() {
            string? skin = null;
            if (current_skin_params != null) {
                skin = current_skin_params.get_element_property("activity", "DiamondBackgroundColor") ??
                    current_skin_params.get_element_property("activity", "BackgroundColor");
            }
            return RenderUtils.sanitize_color(skin ?? ThemeManager.get_active_palette().node_fill);
        }

        // Border and font attributes from activity DiamondBorderColor / DiamondFontColor
        private string diamond_attrs(bool with_font) {
            var attrs = new StringBuilder();
            if (current_skin_params != null) {
                string? border = current_skin_params.get_element_property("activity", "DiamondBorderColor");
                if (border != null) {
                    attrs.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(border)));
                }
                string? font = current_skin_params.get_element_property("activity", "DiamondFontColor");
                if (with_font && font != null) {
                    attrs.append(", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(font)));
                }
            }
            return attrs.str;
        }

        // DOT statement defining a note node (no indent)
        private string note_definition(ActivityNote note) {
            bool use_html = RenderUtils.has_creole_formatting(note.text);
            string note_label;

            if (use_html) {
                note_label = RenderUtils.convert_creole_to_html(note.text);
            } else {
                note_label = RenderUtils.escape_label(note.text);
                // Replace \n with \\n for Graphviz label
                string? temp_label = note_label.replace("\n", "\\n");
                if (temp_label != null) note_label = temp_label;
            }

            // Use custom color or theme color or default yellow
            string note_default = ThemeManager.get_active_palette().accent_secondary;
            if (current_skin_params != null) {
                note_default = RenderUtils.sanitize_color(current_skin_params.get_element_property("note", "BackgroundColor") ?? ThemeManager.get_active_palette().accent_secondary);
            }
            // "#red/white" is a gradient: a colour list plus its angle
            string note_color = note.color != null ? RenderUtils.fill_color(note.color) : note_default;
            string note_gradient = note.color != null ? RenderUtils.gradient_attr(note.color) : "";
            // Notes carry a light fill even on dark themes, so their text needs a
            // fill-derived foreground rather than the global (light) node font color.
            string? note_font_skin = current_skin_params != null
                ? current_skin_params.get_element_property("note", "FontColor") : null;
            string note_font = note_font_skin != null
                ? RenderUtils.sanitize_color(note_font_skin)
                : RenderUtils.contrast_text(note_color);

            if (use_html) {
                return "%s [shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", label=<%s>%s];\n".printf(
                    note.id, note_color, note_font, note_label, note_gradient
                );
            }
            return "%s [shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", label=\"%s\"%s];\n".printf(
                note.id, note_color, note_font, note_label, note_gradient
            );
        }

        // A repeat's loop-back: a condition's yes edge to a node added before it
        private bool is_loop_back(ActivityDiagram diagram, ActivityEdge edge) {
            return edge.from.node_type == ActivityNodeType.CONDITION && edge.is_yes_branch &&
                diagram.nodes.index_of(edge.to) < diagram.nodes.index_of(edge.from);
        }

        private bool is_repeat_condition(ActivityDiagram diagram, ActivityNode node) {
            if (node.node_type != ActivityNodeType.CONDITION) {
                return false;
            }
            foreach (var e in diagram.edges) {
                if (e.from == node && is_loop_back(diagram, e)) {
                    return true;
                }
            }
            return false;
        }

        // A merge the parser marks as pass-through (a repeat exit, a break, the end of a
        // branch with a pending exit) reached by exactly one visible edge. Inferring it
        // from the edge count alone also hid the real merges of a switch or an
        // "end merge" where only one branch continues.
        private bool is_passthrough_merge(ActivityDiagram diagram, ActivityNode node) {
            if (node.node_type != ActivityNodeType.MERGE || !node.passthrough) {
                return false;
            }
            int incoming = 0;
            foreach (var e in diagram.edges) {
                if (e.to == node && e.style != "hidden") {
                    if (is_loop_back(diagram, e)) {
                        return false;
                    }
                    incoming++;
                }
            }
            return incoming == 1;
        }

        private bool has_outgoing(ActivityDiagram diagram, ActivityNode node) {
            foreach (var e in diagram.edges) {
                if (e.from == node && e.style != "hidden") {
                    return true;
                }
            }
            return false;
        }

        private ActivityPartition? find_partition(ActivityDiagram diagram, string key) {
            // By key only: a partition named like a lane title, or two blocks with the
            // same name, are separate boxes
            return diagram.find_partition(key);
        }

        private void append_partition_cluster(StringBuilder sb, ActivityDiagram diagram, string key,
                                              Gee.ArrayList<string> keys,
                                              Gee.HashMap<string, Gee.ArrayList<ActivityNode>> partition_nodes,
                                              ref int cluster_idx, string indent, int lane_index = -1) {
            var palette = ThemeManager.get_active_palette();
            string fill_color = palette.grid;
            string border_color = palette.boundary_stroke;
            string gradient_stmt = "";
            string display_name = key;
            var partition = find_partition(diagram, key);
            if (partition != null) {
                display_name = partition.name;
                if (partition.color != null) {
                    // "#red" is a name for Graphviz, "#red/white" a gradient
                    fill_color = RenderUtils.fill_color(partition.color);
                    border_color = RenderUtils.sanitize_color(partition.color);
                    gradient_stmt = RenderUtils.gradient_stmt(partition.color);
                }
            }

            sb.append("%ssubgraph cluster_%d {\n".printf(indent, cluster_idx));
            cluster_idx++;
            sb.append("%s  label=\"%s\";\n".printf(indent, RenderUtils.escape_label(display_name)));
            if (lane_index >= 0) {
                // A swimlane is a column: centred title, lane lines in the edge
                // colour, filled only when the lane has a colour
                sb.append("%s  labeljust=c;\n".printf(indent));
                sb.append("%s  fontsize=16;\n".printf(indent));
                if (partition.color != null) {
                    sb.append("%s  style=filled;\n".printf(indent));
                    sb.append("%s  fillcolor=\"%s\";\n".printf(indent, fill_color));
                    if (gradient_stmt.length > 0) {
                        sb.append("%s  %s\n".printf(indent, gradient_stmt));
                    }
                } else {
                    sb.append("%s  style=solid;\n".printf(indent));
                }
                sb.append("%s  color=\"%s\";\n".printf(indent, RenderUtils.sanitize_color(palette.edge_color)));
                sb.append("%s  lane_top_%d [shape=point, style=invis, width=0, height=0, label=\"\"];\n".printf(indent, lane_index));
                sb.append("%s  lane_bottom_%d [shape=point, style=invis, width=0, height=0, label=\"\"];\n".printf(indent, lane_index));
            } else {
                sb.append("%s  style=filled;\n".printf(indent));
                sb.append("%s  fillcolor=\"%s\";\n".printf(indent, fill_color));
                if (gradient_stmt.length > 0) {
                    sb.append("%s  %s\n".printf(indent, gradient_stmt));
                }
                sb.append("%s  color=\"%s\";\n".printf(indent, border_color));
            }
            // Cluster titles otherwise fall back to Graphviz's black serif default:
            // Sans, in the theme's text colour or contrasting with the lane fill
            string title_color = (partition != null && partition.color != null)
                ? RenderUtils.contrast_text(RenderUtils.fill_color(partition.color))
                : RenderUtils.sanitize_color(palette.node_text);
            sb.append("%s  fontname=\"Sans\";\n".printf(indent));
            sb.append("%s  fontcolor=\"%s\";\n".printf(indent, title_color));
            sb.append("\n");

            if (partition_nodes.has_key(key)) {
                foreach (var node in partition_nodes.get(key)) {
                    sb.append(indent);
                    append_activity_node(sb, node);
                }
            }
            // Notes sit beside their node inside its lane or partition; defined at the
            // top level they were pushed outside every lane
            foreach (var note in diagram.notes) {
                if (note.attached_to != null && note.attached_to.partition == key) {
                    sb.append(indent + "  " + note_definition(note));
                }
            }

            foreach (var child_key in keys) {
                var child = find_partition(diagram, child_key);
                if (child != null && child.parent == key && child_key != key) {
                    append_partition_cluster(sb, diagram, child_key, keys, partition_nodes, ref cluster_idx, indent + "  ");
                }
            }

            sb.append("%s}\n\n".printf(indent));
        }

        // Swimlanes as full-height columns: every lane's top anchor shares the
        // first rank and its bottom anchor the last, each lane's nodes sit
        // between them, and invisible edges between the tops keep the
        // declaration order left to right.
        private void append_swimlane_columns(StringBuilder sb, ActivityDiagram diagram, Gee.ArrayList<string> lane_keys) {
            if (lane_keys.size == 0) {
                return;
            }
            sb.append("  // Swimlane columns\n");
            var tops = new StringBuilder();
            var bottoms = new StringBuilder();
            for (int i = 0; i < lane_keys.size; i++) {
                tops.append(" lane_top_%d;".printf(i));
                bottoms.append(" lane_bottom_%d;".printf(i));
                foreach (var node in diagram.nodes) {
                    if (in_partition(diagram, node.partition, lane_keys[i])) {
                        sb.append("  lane_top_%d -> %s [style=invis, weight=0];\n".printf(i, node.id));
                        sb.append("  %s -> lane_bottom_%d [style=invis, weight=0];\n".printf(node.id, i));
                    }
                }
                foreach (var note in diagram.notes) {
                    // A left/right note shares its node's rank; anchoring it too swapped
                    // its side. A top/bottom note gets a rank of its own to keep inside.
                    if (note.attached_to != null &&
                        (note.position == NotePosition.TOP || note.position == NotePosition.BOTTOM) &&
                        in_partition(diagram, note.attached_to.partition, lane_keys[i])) {
                        sb.append("  lane_top_%d -> %s [style=invis, weight=0];\n".printf(i, note.id));
                        sb.append("  %s -> lane_bottom_%d [style=invis, weight=0];\n".printf(note.id, i));
                    }
                }
                if (i > 0) {
                    sb.append("  lane_top_%d -> lane_top_%d [style=invis];\n".printf(i - 1, i));
                }
            }
            sb.append("  { rank=same;%s }\n".printf(tops.str));
            sb.append("  { rank=same;%s }\n".printf(bottoms.str));
            // Flat edges between nodes of different clusters don't hold their order
            // (crossing minimisation moved the lane a flow starts in to the left). A row
            // of anchors outside the clusters does: their order is kept, and each one
            // pulls its lane below it.
            var headers = new StringBuilder();
            for (int i = 0; i < lane_keys.size; i++) {
                sb.append("  lane_hdr_%d [shape=point, style=invis, width=0, height=0, label=\"\"];\n".printf(i));
                sb.append("  lane_hdr_%d -> lane_top_%d [style=invis, weight=100];\n".printf(i, i));
                if (i > 0) {
                    sb.append("  lane_hdr_%d -> lane_hdr_%d [style=invis];\n".printf(i - 1, i));
                }
                headers.append(" lane_hdr_%d;".printf(i));
            }
            sb.append("  { rank=same;%s }\n\n".printf(headers.str));
        }

        // Whether a node's partition key is the given partition or nested in it
        private bool in_partition(ActivityDiagram diagram, string? node_key, string key) {
            string? k = node_key;
            int depth = 0;
            while (k != null && depth < 32) {
                if (k == key) {
                    return true;
                }
                var p = find_partition(diagram, k);
                k = p != null ? p.parent : null;
                depth++;
            }
            return false;
        }

        private void append_activity_node(StringBuilder sb, ActivityNode node) {
            string shape = "";
            string label = "";
            string style = "";
            string width = "";
            string height = "";

            switch (node.node_type) {
                case ActivityNodeType.START:
                    shape = "circle";
                    style = "filled";
                    label = "";
                    width = "0.3";
                    height = "0.3";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"black\", label=\"\", width=%s, height=%s];\n".printf(
                        node.id, shape, style, width, height
                    ));
                    break;

                case ActivityNodeType.STOP:
                    shape = "doublecircle";
                    style = "filled";
                    label = "";
                    width = "0.3";
                    height = "0.3";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"black\", label=\"\", width=%s, height=%s];\n".printf(
                        node.id, shape, style, width, height
                    ));
                    break;

                case ActivityNodeType.END:
                    // End = flow final: a circle with an X (stop is the bullseye)
                    sb.append("  %s [shape=circle, style=\"filled\", fillcolor=\"white\", color=\"black\", penwidth=1.5, fixedsize=shape, width=0.28, height=0.28, label=<<font point-size=\"20\" color=\"black\">×</font>>];\n".printf(
                        node.id
                    ));
                    break;

                case ActivityNodeType.KILL:
                case ActivityNodeType.DETACH:
                    // Kill and detach are invisible - the flow just ends
                    // (PlantUML 1.2026.1 draws no symbol for either)
                    sb.append("  %s [shape=point, style=\"invis\", width=\"0\", height=\"0\"];\n".printf(
                        node.id
                    ));
                    break;

                case ActivityNodeType.ACTION:
                    string raw_label = node.label != null ? node.label : "";
                    bool use_html_label = RenderUtils.has_creole_formatting(raw_label);

                    // Add bullet and indentation for sub-level list items
                    // Position bullets at vertical middle using SUP for slight elevation
                    string bullet = "";
                    if (node.indent_level == 2) {
                        // Sub-Actions (**): bullet operator (centered dot)
                        bullet = "∙ ";  // U+2219 Bullet Operator (full font size)
                    } else if (node.indent_level >= 3) {
                        // SubSub-Actions (***): indented + small square
                        bullet = "  ▪ ";  // U+25AA Black Small Square (full font size)
                    }

                    if (use_html_label) {
                        label = RenderUtils.convert_creole_to_html(raw_label);
                        // Add bullet for sub-items
                        if (bullet.length > 0) {
                            label = bullet + label;
                        }
                        // Add stereotype above label if present
                        if (node.stereotype != null && node.stereotype.length > 0) {
                            label = "«" + node.stereotype + "»<br/>" + label;
                        }
                    } else {
                        label = RenderUtils.escape_label(raw_label);
                        // Add bullet for sub-items
                        if (bullet.length > 0) {
                            label = bullet + label;
                        }
                        // Add stereotype above label if present
                        if (node.stereotype != null && node.stereotype.length > 0) {
                            label = "«" + RenderUtils.escape_label(node.stereotype) + "»\\n" + label;
                        }
                    }

                    // Build fill color (support gradient with color2)
                    string fill_color;
                    string gradient_attr = "";
                    // Get default action color from theme
                    string default_action_color = ThemeManager.get_active_palette().node_fill;
                    if (current_skin_params != null) {
                        default_action_color = RenderUtils.sanitize_color(current_skin_params.get_element_property("activity", "BackgroundColor") ?? ThemeManager.get_active_palette().node_fill);
                    }
                    if (node.color2 != null && node.color2.length > 0) {
                        // Gradient: color1:color2, rejoined so RenderUtils reads both sides
                        // ("#blue\9932CC" gets its "#") and the direction from the separator
                        string c1 = node.color != null ? node.color : default_action_color;
                        string gradient = c1 + (node.gradient_separator ?? "-") + node.color2;
                        if (RenderUtils.gradient_angle(gradient) >= 0) {
                            fill_color = RenderUtils.fill_color(gradient);
                            gradient_attr = RenderUtils.gradient_attr(gradient);
                        } else {
                            fill_color = RenderUtils.sanitize_color(c1) + ":" + RenderUtils.sanitize_color(node.color2);
                            gradient_attr = ", gradientangle=%d".printf(
                                RenderUtils.gradient_angle_for_separator(node.gradient_separator));
                        }
                    } else {
                        fill_color = node.color != null ? RenderUtils.sanitize_color(node.color) : default_action_color;
                    }

                    // An inline fill gets a readable text colour (the theme's node font is
                    // light on dark themes); "text:" overrides it
                    string? inline_font = node.color != null ? RenderUtils.contrast_text(fill_color) : null;
                    if (node.text_color != null) {
                        inline_font = RenderUtils.sanitize_color(node.text_color);
                    }

                    // Determine shape based on SDL shape type
                    switch (node.shape) {
                        case ActionShape.SDL_TASK:
                            shape = "box";
                            style = "filled";
                            break;
                        case ActionShape.SDL_INPUT:
                            // Box shape for input
                            shape = "box";
                            style = "filled";
                            break;
                        case ActionShape.SDL_OUTPUT:
                            // Box shape for output
                            shape = "box";
                            style = "filled";
                            break;
                        case ActionShape.SDL_SAVE:
                            // Parallelogram leaning right
                            shape = "polygon";
                            style = "filled";
                            break;
                        case ActionShape.SDL_LOAD:
                            // Parallelogram leaning left (mirrored save)
                            shape = "polygon";
                            style = "filled";
                            break;
                        case ActionShape.SDL_PROCEDURE:
                            shape = "box";
                            style = "filled";
                            // Add double lines for procedure
                            string proc_border = node.line_color != null ? ", color=\"%s\"".printf(RenderUtils.sanitize_color(node.line_color)) : "";
                            string proc_font = inline_font != null ? ", fontcolor=\"%s\"".printf(inline_font) : "";
                            string proc_url = node.url != null ? ", URL=\"%s\"".printf(node.url) : "";
                            if (use_html_label) {
                                sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=<%s>, peripheries=2%s%s%s%s];\n".printf(
                                    node.id, shape, style, fill_color, label, gradient_attr, proc_border, proc_font, proc_url
                                ));
                            } else {
                                sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"%s\", peripheries=2%s%s%s%s];\n".printf(
                                    node.id, shape, style, fill_color, label, gradient_attr, proc_border, proc_font, proc_url
                                ));
                            }
                            break;
                        default:
                            shape = "box";
                            style = "filled,rounded";
                            break;
                    }

                    if (node.shape != ActionShape.SDL_PROCEDURE) {
                        string border_attr = node.line_color != null ? ", color=\"%s\"".printf(RenderUtils.sanitize_color(node.line_color)) : "";
                        string font_attr = inline_font != null ? ", fontcolor=\"%s\"".printf(inline_font) : "";
                        string url_attr = node.url != null ? ", URL=\"%s\"".printf(node.url) : "";
                        // Polygon attributes for parallelograms
                        string skew_attr = "";
                        if (node.shape == ActionShape.SDL_SAVE) {
                            skew_attr = ", sides=4, skew=0.4";  // Leaning right
                        } else if (node.shape == ActionShape.SDL_LOAD) {
                            skew_attr = ", sides=4, skew=-0.4";  // Leaning left (mirrored)
                        }
                        // Text inside an HTML table cell needs HTML escaping. escape_label
                        // only escapes for a quoted DOT string, so an action like
                        // ":a < b;" made the whole graph a syntax error.
                        string cell_label = label;
                        if (!use_html_label) {
                            cell_label = RenderUtils.convert_creole_to_html(raw_label);
                            if (bullet.length > 0) {
                                cell_label = bullet + cell_label;
                            }
                            if (node.stereotype != null && node.stereotype.length > 0) {
                                cell_label = "«" + Markup.escape_text(node.stereotype) + "»<br/>" + cell_label;
                            }
                        }
                        if (this.is_multilevel_list && node.indent_level >= 1) {
                            // Multi-level lists: HTML TABLE for uniform width and left-align
                            string table_label = "<table border=\"0\" cellborder=\"0\" cellpadding=\"4\" cellspacing=\"0\"><tr><td align=\"text\" width=\"150\">" + cell_label + "<br align=\"left\"/></td></tr></table>";
                            sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=<%s>, margin=\"0\"%s%s%s%s%s];\n".printf(
                                node.id, shape, style, fill_color, table_label, gradient_attr, border_attr, font_attr, url_attr, skew_attr
                            ));
                        } else if (use_html_label) {
                            // Nodes with creole formatting (bold, italic): HTML TABLE needed
                            string table_label = "<table border=\"0\" cellborder=\"0\" cellpadding=\"4\" cellspacing=\"0\"><tr><td>" + label + "</td></tr></table>";
                            sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=<%s>, margin=\"0\"%s%s%s%s%s];\n".printf(
                                node.id, shape, style, fill_color, table_label, gradient_attr, border_attr, font_attr, url_attr, skew_attr
                            ));
                        } else {
                            // Plain text nodes: HTML TABLE so patched GraphViz centering applies consistently
                            string table_label = "<table border=\"0\" cellborder=\"0\" cellpadding=\"4\" cellspacing=\"0\"><tr><td>" + RenderUtils.convert_creole_to_html(node.label ?? "") + "</td></tr></table>";
                            sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=<%s>, margin=\"0\"%s%s%s%s%s];\n".printf(
                                node.id, shape, style, fill_color, table_label, gradient_attr, border_attr, font_attr, url_attr, skew_attr
                            ));
                        }
                    }
                    break;

                case ActivityNodeType.CONDITION:
                    shape = "hexagon";
                    style = "filled";
                    label = node.label != null ? RenderUtils.escape_label(node.label) : "";
                    // Get condition color from theme or node
                    string cond_default = diamond_fill();
                    string cond_color = node.color != null ? RenderUtils.sanitize_color(node.color) : cond_default;
                    string cond_font = node.color != null ? ", fontcolor=\"%s\"".printf(RenderUtils.contrast_text(cond_color)) : "";
                    cond_font += diamond_attrs(node.color == null);
                    // Hexagon with ~90° apex on left/right points
                    // Testing ratio for correct angle
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"%s\", width=2, height=1%s];\n".printf(
                        node.id, shape, style, cond_color, label, cond_font
                    ));
                    break;

                case ActivityNodeType.FORK:
                case ActivityNodeType.JOIN:
                    if (node.is_split) {
                        append_split_line(sb, node);
                        break;
                    }
                    shape = "box";
                    style = "filled";
                    width = "1.5";
                    height = "0.05";
                    string bar_color = node.color != null ? RenderUtils.sanitize_color(node.color) : "black";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"\", width=%s, height=%s];\n".printf(
                        node.id, shape, style, bar_color, width, height
                    ));
                    break;

                case ActivityNodeType.MERGE:
                    if (node.is_split) {
                        append_split_line(sb, node);
                        break;
                    }
                    if (current_diagram != null && is_passthrough_merge(current_diagram, node)) {
                        // A merge with one way in (a repeat exit without breaks): PlantUML
                        // draws no diamond, the flow just continues
                        sb.append("  %s [shape=point, style=invis, width=0, height=0, label=\"\"];\n".printf(node.id));
                        break;
                    }
                    shape = "diamond";
                    style = "filled";
                    width = "0.4";
                    height = "0.4";
                    // Same fill as action nodes, or the colour of its "#yellow:if"
                    // (the theme's diamond colour: a fixed palette fill was white on dark themes)
                    string merge_color = node.color != null
                        ? RenderUtils.fill_color(node.color) : diamond_fill();
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"\", width=%s, height=%s%s%s];\n".printf(
                        node.id, shape, style, merge_color, width, height,
                        node.color != null ? RenderUtils.gradient_attr(node.color) : "",
                        diamond_attrs(false)
                    ));
                    break;

                case ActivityNodeType.CONNECTOR:
                    shape = "circle";
                    style = "filled";
                    label = node.label != null ? RenderUtils.escape_label(node.label) : "";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"%s\", width=\"0.4\", height=\"0.4\"];\n".printf(
                        node.id, shape, style, ThemeManager.get_active_palette().accent_secondary, label
                    ));
                    break;

                case ActivityNodeType.SEPARATOR:
                    // Horizontal line separator with optional label
                    var sep_palette = ThemeManager.get_active_palette();
                    if (node.label != null && node.label.length > 0) {
                        // Separator with text - use box with label
                        string sep_label = RenderUtils.escape_label(node.label);
                        sb.append("  %s [shape=box, style=\"filled,rounded\", fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", label=\"%s\", width=\"2.0\"];\n".printf(
                            node.id, sep_palette.grid, sep_palette.boundary_stroke, sep_palette.edge_text, sep_label
                        ));
                    } else {
                        sb.append("  %s [shape=box, style=\"filled\", fillcolor=\"%s\", label=\"\", width=\"2.0\", height=\"0.02\"];\n".printf(
                            node.id, sep_palette.boundary_stroke
                        ));
                    }
                    break;

                case ActivityNodeType.VSPACE:
                    // Invisible node for vertical spacing
                    sb.append("  %s [shape=point, width=\"0\", height=\"0.5\", style=\"invis\"];\n".printf(
                        node.id
                    ));
                    break;

                default:
                    shape = "box";
                    label = node.label != null ? RenderUtils.escape_label(node.label) : "";
                    sb.append("  %s [shape=%s, label=\"%s\"];\n".printf(
                        node.id, shape, label
                    ));
                    break;
            }
        }

        public uint8[]? render_to_svg(ActivityDiagram diagram) {
            // Uses the patched dot_binary (not layout_engine) for correct
            // HTML-TABLE text centering. RenderUtils.run_graphviz_subprocess
            // doesn't hard-code an engine, so we can reuse it.
            string dot = generate_dot(diagram);
            return RenderUtils.run_graphviz_subprocess(dot, dot_binary, "activity");
        }

        public Cairo.ImageSurface? render_to_surface(ActivityDiagram diagram) {
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

                var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
                handle.render_document(cr, viewport);

                // Build element_lines: map DOT node ID → source line.
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var node in diagram.nodes) {
                    if (node.source_line > 0) {
                        element_lines.set(node.id, node.source_line);
                    }
                }

                last_regions.clear();
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, width, height);

                return surface;
            } catch (Error e) {
                warning("Failed to render activity SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(ActivityDiagram diagram, string filename) {
            // Use GraphViz PNG directly (no reprocessing - preserves patches!)
            // Uses secure unique temp paths via mkstemp.
            string dot = generate_dot(diagram);
            string tmp_dot = "";
            string graphviz_png = "";

            try {
                int fd_dot = FileUtils.open_tmp("gdiagram_activity_XXXXXX.dot", out tmp_dot);
                if (fd_dot < 0) return false;
                FileStream.fdopen(fd_dot, "w");

                int fd_png = FileUtils.open_tmp("gdiagram_activity_XXXXXX.png", out graphviz_png);
                if (fd_png < 0) { FileUtils.unlink(tmp_dot); return false; }
                FileStream.fdopen(fd_png, "w");

                FileUtils.set_contents(tmp_dot, dot);

                // Generate PNG directly with patched GraphViz
                string[] argv = {dot_binary, "-Gfontname=Sans", "-Tpng", tmp_dot, "-o", graphviz_png};
                int exit_status;
                Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

                if (exit_status != 0) {
                    FileUtils.unlink(tmp_dot);
                    FileUtils.unlink(graphviz_png);
                    return false;
                }

                uint8[] png_data;
                FileUtils.get_data(graphviz_png, out png_data);
                var file = File.new_for_path(filename);
                var stream = file.replace(null, false, FileCreateFlags.NONE);
                stream.write_all(png_data, null);
                stream.close();

                FileUtils.unlink(tmp_dot);
                FileUtils.unlink(graphviz_png);
                return true;
            } catch (Error e) {
                warning("Failed to export PNG: %s", e.message);
                if (tmp_dot.length > 0) FileUtils.unlink(tmp_dot);
                if (graphviz_png.length > 0) FileUtils.unlink(graphviz_png);
                return false;
            }
        }

        public bool export_to_svg(ActivityDiagram diagram, string filename) {
            string dot = generate_dot(diagram);
            var svg_data = RenderUtils.run_graphviz_subprocess(dot, dot_binary, "activity");
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(ActivityDiagram diagram, string filename) {
            string dot = generate_dot(diagram);
            var svg_data = RenderUtils.run_graphviz_subprocess(dot, dot_binary, "activity");
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
