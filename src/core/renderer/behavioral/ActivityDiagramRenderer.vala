namespace GPlantUML {
    public class ActivityDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;
        private SkinParams? current_skin_params;

        public ActivityDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
            this.current_skin_params = null;
        }

        public string generate_dot(ActivityDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values with defaults
            string bg_color = diagram.skin_params.background_color ?? "white";
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = diagram.skin_params.default_font_color ?? "black";
            string arrow_color = diagram.skin_params.get_element_property("arrow", "Color") ?? "black";
            string arrow_font_color = diagram.skin_params.get_element_property("arrow", "FontColor") ?? font_color;

            // Store skin_params in a local variable for use in helper methods
            this.current_skin_params = diagram.skin_params;

            sb.append("digraph activity {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(font_name, arrow_color, arrow_font_color));
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
                string fill_color = "#E8E8E8";
                string border_color = "#888888";
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
                    if (edge.color != null && edge.color.length > 0) {
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

                    if (attrs.size > 0) {
                        sb.append("  %s -> %s [%s];\n".printf(
                            edge.from.id, edge.to.id, string.joinv(", ", attrs.to_array())
                        ));
                    } else {
                        sb.append("  %s -> %s;\n".printf(edge.from.id, edge.to.id));
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
                    string note_default = "#FFFFCC";
                    if (current_skin_params != null) {
                        note_default = current_skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";
                    }
                    string note_color = note.color != null ? note.color : note_default;

                    if (use_html) {
                        sb.append("  %s [shape=note, style=filled, fillcolor=\"%s\", label=<%s>];\n".printf(
                            note.id, note_color, note_label
                        ));
                    } else {
                        sb.append("  %s [shape=note, style=filled, fillcolor=\"%s\", label=\"%s\"];\n".printf(
                            note.id, note_color, note_label
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

                if (legend_use_html) {
                    legend_label = RenderUtils.convert_creole_to_html(diagram.legend.text);
                    sb.append("  legend_node [shape=box, style=\"filled\", fillcolor=\"#FFFFCC\", ");
                    sb.append("label=<%s>, fontsize=9, fontname=\"Sans\"];\n".printf(legend_label));
                } else {
                    legend_label = RenderUtils.escape_label(diagram.legend.text);
                    // Replace \n with \l for left-aligned lines in Graphviz
                    string? temp_legend = legend_label.replace("\n", "\\l");
                    if (temp_legend != null) legend_label = temp_legend;
                    sb.append("  legend_node [shape=box, style=\"filled\", fillcolor=\"#FFFFCC\", ");
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

                    if (use_html_label) {
                        label = RenderUtils.convert_creole_to_html(raw_label);
                        // Add stereotype above label if present
                        if (node.stereotype != null && node.stereotype.length > 0) {
                            label = "«" + node.stereotype + "»<br/>" + label;
                        }
                    } else {
                        label = RenderUtils.escape_label(raw_label);
                        // Add stereotype above label if present
                        if (node.stereotype != null && node.stereotype.length > 0) {
                            label = "«" + RenderUtils.escape_label(node.stereotype) + "»\\n" + label;
                        }
                    }

                    // Build fill color (support gradient with color2)
                    string fill_color;
                    string gradient_attr = "";
                    // Get default action color from theme
                    string default_action_color = "#FEFECE";
                    if (current_skin_params != null) {
                        default_action_color = current_skin_params.get_element_property("activity", "BackgroundColor") ?? "#FEFECE";
                    }
                    if (node.color2 != null && node.color2.length > 0) {
                        // Gradient: color1:color2
                        string c1 = node.color != null ? node.color : default_action_color;
                        fill_color = c1 + ":" + node.color2;
                        gradient_attr = ", gradientangle=270";
                    } else {
                        fill_color = node.color != null ? node.color : default_action_color;
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
                            string proc_border = node.line_color != null ? ", color=\"%s\"".printf(node.line_color) : "";
                            string proc_font = node.text_color != null ? ", fontcolor=\"%s\"".printf(node.text_color) : "";
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
                        string border_attr = node.line_color != null ? ", color=\"%s\"".printf(node.line_color) : "";
                        string font_attr = node.text_color != null ? ", fontcolor=\"%s\"".printf(node.text_color) : "";
                        string url_attr = node.url != null ? ", URL=\"%s\"".printf(node.url) : "";
                        // Polygon attributes for parallelograms
                        string skew_attr = "";
                        if (node.shape == ActionShape.SDL_SAVE) {
                            skew_attr = ", sides=4, skew=0.4";  // Leaning right
                        } else if (node.shape == ActionShape.SDL_LOAD) {
                            skew_attr = ", sides=4, skew=-0.4";  // Leaning left (mirrored)
                        }
                        if (use_html_label) {
                            sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=<%s>%s%s%s%s%s];\n".printf(
                                node.id, shape, style, fill_color, label, gradient_attr, border_attr, font_attr, url_attr, skew_attr
                            ));
                        } else {
                            sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"%s\"%s%s%s%s%s];\n".printf(
                                node.id, shape, style, fill_color, label, gradient_attr, border_attr, font_attr, url_attr, skew_attr
                            ));
                        }
                    }
                    break;

                case ActivityNodeType.CONDITION:
                    shape = "diamond";
                    style = "filled";
                    label = node.label != null ? RenderUtils.escape_label(node.label) : "";
                    // Get condition color from theme or node
                    string cond_default = "#FEFECE";
                    if (current_skin_params != null) {
                        cond_default = current_skin_params.get_element_property("activity", "BackgroundColor") ?? "#FEFECE";
                    }
                    string cond_color = node.color != null ? node.color : cond_default;
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"%s\", label=\"%s\"];\n".printf(
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
                    shape = "point";
                    width = "0.1";
                    height = "0.1";
                    sb.append("  %s [shape=%s, width=%s, height=%s];\n".printf(
                        node.id, shape, width, height
                    ));
                    break;

                case ActivityNodeType.CONNECTOR:
                    shape = "circle";
                    style = "filled";
                    label = node.label != null ? RenderUtils.escape_label(node.label) : "";
                    sb.append("  %s [shape=%s, style=\"%s\", fillcolor=\"#FFFFCC\", label=\"%s\", width=\"0.4\", height=\"0.4\"];\n".printf(
                        node.id, shape, style, label
                    ));
                    break;

                case ActivityNodeType.SEPARATOR:
                    // Horizontal line separator with optional label
                    if (node.label != null && node.label.length > 0) {
                        // Separator with text - use box with label
                        string sep_label = RenderUtils.escape_label(node.label);
                        sb.append("  %s [shape=box, style=\"filled,rounded\", fillcolor=\"#E8E8E8\", color=\"#888888\", fontcolor=\"#555555\", label=\"%s\", width=\"2.0\"];\n".printf(
                            node.id, sep_label
                        ));
                    } else {
                        sb.append("  %s [shape=box, style=\"filled\", fillcolor=\"#888888\", label=\"\", width=\"2.0\", height=\"0.02\"];\n".printf(
                            node.id
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
            string dot = generate_dot(diagram);

            // Use command line dot instead of libgvc to fix HTML label rendering issues
            try {
                string tmp_dot = "/tmp/gplantuml_activity.dot";
                string tmp_svg = "/tmp/gplantuml_activity.svg";

                FileUtils.set_contents(tmp_dot, dot);

                string[] argv = {layout_engine, "-Tsvg", tmp_dot, "-o", tmp_svg};
                int exit_status;
                Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

                if (exit_status != 0) {
                    warning("dot command failed with exit status %d", exit_status);
                    return null;
                }

                uint8[] svg_data;
                FileUtils.get_data(tmp_svg, out svg_data);
                return svg_data;
            } catch (Error e) {
                warning("Failed to render with dot command: %s", e.message);
                return null;
            }
        }

        public Cairo.ImageSurface? render_to_surface(ActivityDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            // Post-process SVG to fix RSVG whitespace handling
            // Add xml:space="preserve" to text elements
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

                // Build element line number map from activity nodes
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var node in diagram.nodes) {
                    if (node.source_line > 0) {
                        element_lines.set(node.id, node.source_line);
                        // Also map by label for action nodes
                        if (node.label != null && node.label.length > 0) {
                            element_lines.set(node.label, node.source_line);
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

        public bool export_to_png(ActivityDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(ActivityDiagram diagram, string filename) {
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

        public bool export_to_pdf(ActivityDiagram diagram, string filename) {
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
