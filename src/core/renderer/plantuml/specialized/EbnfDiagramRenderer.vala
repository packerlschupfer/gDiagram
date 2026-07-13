/* EbnfDiagramRenderer.vala — renders PlantUML @startebnf as railroad diagrams */
namespace GDiagram {

public class EbnfDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private int node_counter;

    public EbnfDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(EbnfDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        node_counter = 0;
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\"]\n");
        sb.append("    edge [color=\"%s\" arrowsize=0.7]\n\n".printf(palette.edge_color));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // Each rule gets its own subgraph with start/end points
        int rule_idx = 0;
        foreach (var rule in diagram.rules) {
            sb.append_printf("    subgraph cluster_rule_%d {\n", rule_idx);
            sb.append_printf("        label=\"%s\"\n", RenderUtils.escape_label(rule.name));
            sb.append_printf("        fontcolor=\"%s\"\n", palette.node_text);
            sb.append("        style=dashed\n");
            sb.append_printf("        color=\"%s\"\n", palette.container_border);
            sb.append("        labeljust=l\n\n");

            string start_id = next_id("start");
            string end_id = next_id("end");

            // Start and end points (small circles)
            sb.append_printf("        \"%s\" [shape=circle width=0.2 fixedsize=true label=\"\" style=filled fillcolor=\"%s\"]\n",
                start_id, palette.node_border);
            sb.append_printf("        \"%s\" [shape=doublecircle width=0.2 fixedsize=true label=\"\" style=filled fillcolor=\"%s\"]\n",
                end_id, palette.node_border);

            // Render the expression body
            string[] endpoints = render_expr(rule.body, sb, palette);
            if (endpoints.length == 2) {
                sb.append_printf("        \"%s\" -> \"%s\"\n", start_id, endpoints[0]);
                sb.append_printf("        \"%s\" -> \"%s\"\n", endpoints[1], end_id);
            }

            sb.append("    }\n\n");
            rule_idx++;
        }

        sb.append("}\n");
        return sb.str;
    }

    // Returns [entry_id, exit_id] for the rendered expression
    private string[] render_expr(EbnfExpr expr, StringBuilder sb, Palette palette) {
        switch (expr.expr_type) {
            case EbnfExprType.TERMINAL:
                return render_terminal(expr.text, sb, palette);

            case EbnfExprType.NONTERMINAL:
                return render_nonterminal(expr.text, sb, palette);

            case EbnfExprType.SEQUENCE:
                return render_sequence(expr, sb, palette);

            case EbnfExprType.ALTERNATION:
                return render_alternation(expr, sb, palette);

            case EbnfExprType.REPETITION:
                return render_repetition(expr, sb, palette);

            case EbnfExprType.OPTIONAL:
                return render_optional(expr, sb, palette);

            case EbnfExprType.GROUP:
                if (expr.children.size > 0) {
                    return render_expr(expr.children.get(0), sb, palette);
                }
                return render_empty_node(sb, palette);

            case EbnfExprType.SPECIAL:
                return render_special(expr.text, sb, palette);

            default:
                return render_empty_node(sb, palette);
        }
    }

    private string[] render_terminal(string text, StringBuilder sb, Palette palette) {
        string nid = next_id("term");
        sb.append_printf("        \"%s\" [label=\"%s\" shape=box style=\"rounded,filled\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
            nid, RenderUtils.escape_label(text),
            palette.accent_primary, palette.container_border,
            RenderUtils.contrast_text(palette.accent_primary));
        return { nid, nid };
    }

    private string[] render_nonterminal(string name, StringBuilder sb, Palette palette) {
        string nid = next_id("nonterm");
        sb.append_printf("        \"%s\" [label=\"%s\" shape=box style=filled fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
            nid, RenderUtils.escape_label(name),
            palette.node_fill, palette.node_border, palette.node_text);
        return { nid, nid };
    }

    private string[] render_sequence(EbnfExpr expr, StringBuilder sb, Palette palette) {
        if (expr.children.size == 0) return render_empty_node(sb, palette);

        string first_entry = "";
        string prev_exit = "";

        for (int i = 0; i < expr.children.size; i++) {
            string[] ep = render_expr(expr.children.get(i), sb, palette);
            if (i == 0) {
                first_entry = ep[0];
            } else {
                sb.append_printf("        \"%s\" -> \"%s\"\n", prev_exit, ep[0]);
            }
            prev_exit = ep[1];
        }

        return { first_entry, prev_exit };
    }

    private string[] render_alternation(EbnfExpr expr, StringBuilder sb, Palette palette) {
        if (expr.children.size == 0) return render_empty_node(sb, palette);

        string fork_id = next_id("fork");
        string join_id = next_id("join");

        sb.append_printf("        \"%s\" [shape=point width=0.15]\n", fork_id);
        sb.append_printf("        \"%s\" [shape=point width=0.15]\n", join_id);

        foreach (var child in expr.children) {
            string[] ep = render_expr(child, sb, palette);
            sb.append_printf("        \"%s\" -> \"%s\"\n", fork_id, ep[0]);
            sb.append_printf("        \"%s\" -> \"%s\"\n", ep[1], join_id);
        }

        return { fork_id, join_id };
    }

    private string[] render_repetition(EbnfExpr expr, StringBuilder sb, Palette palette) {
        // { expr } = zero or more
        string fork_id = next_id("repfork");
        string join_id = next_id("repjoin");

        sb.append_printf("        \"%s\" [shape=point width=0.15]\n", fork_id);
        sb.append_printf("        \"%s\" [shape=point width=0.15]\n", join_id);

        // Skip path (zero occurrences)
        sb.append_printf("        \"%s\" -> \"%s\"\n", fork_id, join_id);

        if (expr.children.size > 0) {
            string[] ep = render_expr(expr.children.get(0), sb, palette);
            sb.append_printf("        \"%s\" -> \"%s\"\n", fork_id, ep[0]);
            sb.append_printf("        \"%s\" -> \"%s\"\n", ep[1], join_id);
            // Loop back edge
            sb.append_printf("        \"%s\" -> \"%s\" [style=dashed]\n", ep[1], ep[0]);
        }

        return { fork_id, join_id };
    }

    private string[] render_optional(EbnfExpr expr, StringBuilder sb, Palette palette) {
        // [ expr ] = zero or one
        string fork_id = next_id("optfork");
        string join_id = next_id("optjoin");

        sb.append_printf("        \"%s\" [shape=point width=0.15]\n", fork_id);
        sb.append_printf("        \"%s\" [shape=point width=0.15]\n", join_id);

        // Skip path
        sb.append_printf("        \"%s\" -> \"%s\"\n", fork_id, join_id);

        if (expr.children.size > 0) {
            string[] ep = render_expr(expr.children.get(0), sb, palette);
            sb.append_printf("        \"%s\" -> \"%s\"\n", fork_id, ep[0]);
            sb.append_printf("        \"%s\" -> \"%s\"\n", ep[1], join_id);
        }

        return { fork_id, join_id };
    }

    private string[] render_special(string text, StringBuilder sb, Palette palette) {
        string nid = next_id("special");
        sb.append_printf("        \"%s\" [label=\"? %s ?\" shape=hexagon style=filled fillcolor=\"%s\" fontcolor=\"%s\"]\n",
            nid, RenderUtils.escape_label(text), palette.warning, RenderUtils.contrast_text(palette.warning));
        return { nid, nid };
    }

    private string[] render_empty_node(StringBuilder sb, Palette palette) {
        string nid = next_id("empty");
        sb.append_printf("        \"%s\" [shape=point width=0.1]\n", nid);
        return { nid, nid };
    }

    private string next_id(string prefix) {
        node_counter++;
        return "%s_%d".printf(prefix, node_counter);
    }

    public uint8[]? render_to_svg(EbnfDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse EBNF DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout EBNF graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render EBNF diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(EbnfDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(EbnfDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(EbnfDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(EbnfDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
