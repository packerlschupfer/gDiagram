/* RegexDiagramRenderer.vala — renders PlantUML @startregex as railroad/NFA diagram */
namespace GDiagram {

public class RegexDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private int state_counter;

    public RegexDiagramRenderer(Gvc.Context ctx,
                                 Gee.ArrayList<ElementRegion> regions,
                                 string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(RegexDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        state_counter = 0;
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\"]\n");
        sb.append("    edge [fontsize=9 color=\"%s\" fontcolor=\"%s\"]\n\n".printf(
            palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // Show the pattern as a subtitle
        if (diagram.pattern.length > 0) {
            sb.append_printf("    pattern_label [shape=plaintext label=\"%s\" fontsize=10 fontcolor=\"%s\"]\n\n",
                RenderUtils.escape_label(diagram.pattern), palette.edge_text);
        }

        // Start and end states
        string start_id = "start";
        string end_id = "end";
        sb.append_printf("    \"%s\" [shape=circle width=0.25 fixedsize=true label=\"\" style=filled fillcolor=\"%s\"]\n",
            start_id, palette.success);
        sb.append_printf("    \"%s\" [shape=doublecircle width=0.25 fixedsize=true label=\"\" style=filled fillcolor=\"%s\"]\n",
            end_id, palette.success);

        // Render the regex tree
        string[] endpoints = render_node(diagram.root, sb, palette);
        if (endpoints.length == 2) {
            sb.append_printf("    \"%s\" -> \"%s\"\n", start_id, endpoints[0]);
            sb.append_printf("    \"%s\" -> \"%s\"\n", endpoints[1], end_id);
        }

        sb.append("}\n");
        return sb.str;
    }

    // Returns [entry_id, exit_id]
    private string[] render_node(RegexNode node, StringBuilder sb, Palette palette) {
        switch (node.node_type) {
            case RegexNodeType.LITERAL:
                return render_labeled_transition(node.text, sb, palette, false);

            case RegexNodeType.CHAR_CLASS:
                return render_labeled_transition(node.text, sb, palette, true);

            case RegexNodeType.DOT:
                return render_labeled_transition(".", sb, palette, true);

            case RegexNodeType.ANCHOR:
                return render_anchor(node.text, sb, palette);

            case RegexNodeType.SEQUENCE:
                return render_sequence(node, sb, palette);

            case RegexNodeType.ALTERNATION:
                return render_alternation(node, sb, palette);

            case RegexNodeType.GROUP:
                if (node.children.size > 0) {
                    return render_node(node.children.get(0), sb, palette);
                }
                return render_epsilon(sb);

            case RegexNodeType.QUANTIFIER:
                return render_quantifier(node, sb, palette);

            default:
                return render_epsilon(sb);
        }
    }

    private string[] render_labeled_transition(string label, StringBuilder sb, Palette palette, bool is_class) {
        string nid = next_state();
        string fill = is_class ? palette.accent_secondary : palette.accent_primary;
        string shape = is_class ? "box" : "box";
        string style = is_class ? "rounded,filled" : "rounded,filled";

        sb.append_printf("    \"%s\" [label=\"%s\" shape=%s style=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
            nid, RenderUtils.escape_label(label), shape, style,
            fill, palette.container_border,
            RenderUtils.contrast_text(fill));
        return { nid, nid };
    }

    private string[] render_anchor(string text, StringBuilder sb, Palette palette) {
        string nid = next_state();
        sb.append_printf("    \"%s\" [label=\"%s\" shape=diamond width=0.4 style=filled fillcolor=\"%s\" fontcolor=\"%s\" fontsize=9]\n",
            nid, RenderUtils.escape_label(text),
            palette.warning, RenderUtils.contrast_text(palette.warning));
        return { nid, nid };
    }

    private string[] render_sequence(RegexNode node, StringBuilder sb, Palette palette) {
        if (node.children.size == 0) return render_epsilon(sb);

        string first_entry = "";
        string prev_exit = "";

        for (int i = 0; i < node.children.size; i++) {
            string[] ep = render_node(node.children.get(i), sb, palette);
            if (i == 0) {
                first_entry = ep[0];
            } else {
                sb.append_printf("    \"%s\" -> \"%s\"\n", prev_exit, ep[0]);
            }
            prev_exit = ep[1];
        }

        return { first_entry, prev_exit };
    }

    private string[] render_alternation(RegexNode node, StringBuilder sb, Palette palette) {
        if (node.children.size == 0) return render_epsilon(sb);

        string fork_id = next_state();
        string join_id = next_state();

        sb.append_printf("    \"%s\" [shape=point width=0.12]\n", fork_id);
        sb.append_printf("    \"%s\" [shape=point width=0.12]\n", join_id);

        foreach (var child in node.children) {
            string[] ep = render_node(child, sb, palette);
            sb.append_printf("    \"%s\" -> \"%s\"\n", fork_id, ep[0]);
            sb.append_printf("    \"%s\" -> \"%s\"\n", ep[1], join_id);
        }

        return { fork_id, join_id };
    }

    private string[] render_quantifier(RegexNode node, StringBuilder sb, Palette palette) {
        if (node.children.size == 0) return render_epsilon(sb);

        string fork_id = next_state();
        string join_id = next_state();

        sb.append_printf("    \"%s\" [shape=point width=0.12]\n", fork_id);
        sb.append_printf("    \"%s\" [shape=point width=0.12]\n", join_id);

        string[] ep = render_node(node.children.get(0), sb, palette);

        // Forward path through the expression
        sb.append_printf("    \"%s\" -> \"%s\"\n", fork_id, ep[0]);
        sb.append_printf("    \"%s\" -> \"%s\"\n", ep[1], join_id);

        // Quantifier-specific edges
        if (node.min_count == 0) {
            // Can skip entirely (?, *, {0,...})
            sb.append_printf("    \"%s\" -> \"%s\" [style=dashed]\n", fork_id, join_id);
        }
        if (node.max_count == -1 || node.max_count > 1) {
            // Loop back for repetition (+, *, {n,m>1})
            string quant_label = get_quantifier_label(node);
            sb.append_printf("    \"%s\" -> \"%s\" [style=dashed label=\"%s\"]\n",
                ep[1], ep[0], RenderUtils.escape_label(quant_label));
        }

        return { fork_id, join_id };
    }

    private string get_quantifier_label(RegexNode node) {
        if (node.min_count == 0 && node.max_count == -1) return "*";
        if (node.min_count == 1 && node.max_count == -1) return "+";
        if (node.min_count == 0 && node.max_count == 1) return "?";
        if (node.min_count == node.max_count) return "{%d}".printf(node.min_count);
        if (node.max_count == -1) return "{%d,}".printf(node.min_count);
        return "{%d,%d}".printf(node.min_count, node.max_count);
    }

    private string[] render_epsilon(StringBuilder sb) {
        string nid = next_state();
        sb.append_printf("    \"%s\" [shape=point width=0.1]\n", nid);
        return { nid, nid };
    }

    private string next_state() {
        state_counter++;
        return "s_%d".printf(state_counter);
    }

    public uint8[]? render_to_svg(RegexDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse regex DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout regex graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render regex diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(RegexDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(RegexDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(RegexDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(RegexDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
