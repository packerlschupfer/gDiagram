namespace GDiagram {
    public class ActivityDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;
        private SkinParams? current_skin_params;
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

            // Render partitions as subgraphs (clusters)
            int cluster_idx = 0;
            foreach (var entry in partition_nodes.entries) {
                // Find partition and its display name/color
                string fill_color = palette.grid;
                string border_color = palette.boundary_stroke;
                string display_name = entry.key;
                foreach (var p in diagram.partitions) {
                    // Match by name or alias
                    if (p.name == entry.key || (p.alias != null && p.alias == entry.key)) {
                        display_name = p.name;  // Use display name
                        if (p.color != null) {
                            fill_color = p.color;
                            border_color = p.color;
                        }
                        break;
                    }
                }

                sb.append("  subgraph cluster_%d {\n".printf(cluster_idx));
                sb.append("    label=\"%s\";\n".printf(RenderUtils.escape_label(display_name)));
                sb.append("    style=filled;\n");
                sb.append("    fillcolor=\"%s\";\n".printf(fill_color));
                sb.append("    color=\"%s\";\n".printf(border_color));
                sb.append("\n");

                foreach (var node in entry.value) {
                    sb.append("  ");
                    append_activity_node(sb, node);
                }

                sb.append("  }\n\n");
                cluster_idx++;
            }

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
                            attrs.add("label=\"%s\"".printf(label));
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
                        attrs.add("label=\"%s\"".printf(label));
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
                    }
                    if (edge.style != null && edge.style.length > 0) {
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

                    // For condition (diamond) nodes, use ports for branch exits
                    if (edge.from.node_type == ActivityNodeType.CONDITION) {
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
                    string note_color = note.color != null ? RenderUtils.sanitize_color(note.color) : note_default;
                    // Notes carry a light fill even on dark themes, so their text needs a
                    // fill-derived foreground rather than the global (light) node font color.
                    string? note_font_skin = current_skin_params != null
                        ? current_skin_params.get_element_property("note", "FontColor") : null;
                    string note_font = note_font_skin != null
                        ? RenderUtils.sanitize_color(note_font_skin)
                        : RenderUtils.contrast_text(note_color);

                    if (use_html) {
                        sb.append("  %s [shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", label=<%s>];\n".printf(
                            note.id, note_color, note_font, note_label
                        ));
                    } else {
                        sb.append("  %s [shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", label=\"%s\"];\n".printf(
                            note.id, note_color, note_font, note_label
                        ));
                    }

                    // Connect note to attached node
                    if (note.attached_to != null) {
                        switch (note.position) {
                            case NotePosition.LEFT:
                                // Note on left: note -> node (note comes first)
                                sb.append("  %s -> %s [style=invis];\n".printf(
                                    note.id, note.attached_to.id
                                ));
                                // Dashed connector line
                                sb.append("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n".printf(
                                    note.attached_to.id, note.id
                                ));
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
                                // Dashed connector line
                                sb.append("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n".printf(
                                    note.attached_to.id, note.id
                                ));
                                // Same rank to keep horizontal
                                sb.append("  { rank=same; %s; %s; }\n".printf(
                                    note.attached_to.id, note.id
                                ));
                                break;

                            case NotePosition.TOP:
                                // Note above: note -> node (vertical ordering)
                                sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                    note.id, note.attached_to.id
                                ));
                                break;

                            case NotePosition.BOTTOM:
                                // Note below: node -> note (vertical ordering)
                                sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                    note.attached_to.id, note.id
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

                    // Follow no-branch edges to find chained conditions (elseif)
                    var current_cond = node;
                    foreach (var edge in diagram.edges) {
                        if (edge.from == current_cond && edge.is_no_branch) {
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
                if (merge_nodes.contains(edge.to.id)) {
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
                    // End = flow final (bullseye - circle with filled circle inside)
                    sb.append("  %s [shape=doublecircle, style=\"filled\", fillcolor=\"black\", color=\"black\", label=\"\", width=0.2];\n".printf(
                        node.id
                    ));
                    break;

                case ActivityNodeType.KILL:
                    // Kill shows X symbol
                    shape = "circle";
                    style = "filled";
                    width = "0.25";
                    height = "0.25";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"black\", label=\"X\", fontcolor=\"white\", width=%s, height=%s];\n".printf(
                        node.id, shape, style, width, height
                    ));
                    break;

                case ActivityNodeType.DETACH:
                    // Detach is invisible - flow just ends
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
                        // Gradient: color1:color2
                        string c1 = node.color != null ? RenderUtils.sanitize_color(node.color) : default_action_color;
                        fill_color = c1 + ":" + RenderUtils.sanitize_color(node.color2);
                        gradient_attr = ", gradientangle=270";
                    } else {
                        fill_color = node.color != null ? RenderUtils.sanitize_color(node.color) : default_action_color;
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
                            string proc_font = node.text_color != null ? ", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(node.text_color)) : "";
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
                        string font_attr = node.text_color != null ? ", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(node.text_color)) : "";
                        string url_attr = node.url != null ? ", URL=\"%s\"".printf(node.url) : "";
                        // Polygon attributes for parallelograms
                        string skew_attr = "";
                        if (node.shape == ActionShape.SDL_SAVE) {
                            skew_attr = ", sides=4, skew=0.4";  // Leaning right
                        } else if (node.shape == ActionShape.SDL_LOAD) {
                            skew_attr = ", sides=4, skew=-0.4";  // Leaning left (mirrored)
                        }
                        if (this.is_multilevel_list && node.indent_level >= 1) {
                            // Multi-level lists: HTML TABLE for uniform width and left-align
                            string table_label = "<table border=\"0\" cellborder=\"0\" cellpadding=\"4\" cellspacing=\"0\"><tr><td align=\"text\" width=\"150\">" + label + "<br align=\"left\"/></td></tr></table>";
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
                            string table_label = "<table border=\"0\" cellborder=\"0\" cellpadding=\"4\" cellspacing=\"0\"><tr><td>" + RenderUtils.escape_label(node.label ?? "") + "</td></tr></table>";
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
                    string cond_default = ThemeManager.get_active_palette().node_fill;
                    if (current_skin_params != null) {
                        cond_default = RenderUtils.sanitize_color(current_skin_params.get_element_property("activity", "BackgroundColor") ?? ThemeManager.get_active_palette().node_fill);
                    }
                    string cond_color = node.color != null ? RenderUtils.sanitize_color(node.color) : cond_default;
                    // Hexagon with ~90° apex on left/right points
                    // Testing ratio for correct angle
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"%s\", width=2, height=1];\n".printf(
                        node.id, shape, style, cond_color, label
                    ));
                    break;

                case ActivityNodeType.FORK:
                case ActivityNodeType.JOIN:
                    shape = "box";
                    style = "filled";
                    width = "1.5";
                    height = "0.05";
                    string bar_color = node.color != null ? node.color : "black";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"\", width=%s, height=%s];\n".printf(
                        node.id, shape, style, bar_color, width, height
                    ));
                    break;

                case ActivityNodeType.MERGE:
                    shape = "diamond";
                    style = "filled";
                    width = "0.4";
                    height = "0.4";
                    // Use same fill color as action nodes
                    string merge_color = ThemeManager.get_active_palette().node_fill;
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"\", width=%s, height=%s];\n".printf(
                        node.id, shape, style, merge_color, width, height
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
                string[] argv = {dot_binary, "-Tpng", tmp_dot, "-o", graphviz_png};
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
            try {
                return RenderUtils.export_svg_to_pdf(svg_data, filename);
            } catch (Error e) {
                warning("Failed to export activity PDF: %s", e.message);
                return false;
            }
        }
    }
}
