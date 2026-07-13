/* SaltDiagramRenderer.vala — renders PlantUML @startsalt UI wireframes */
namespace GDiagram {

public class SaltDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public SaltDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(SaltDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\"]\n");
        sb.append("    edge [style=invis]\n\n");

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // The root panel as one HTML TABLE node. Like PlantUML, a plain `{`
        // panel has no frame; `{+` gets one and `{#` a grid.
        sb.append("    salt_root [shape=plaintext fontsize=10.5 label=<\n");
        sb.append("      <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n");

        render_panel_rows(diagram.root, sb, palette, 0);

        sb.append("      </TABLE>\n");
        sb.append("    >]\n");
        sb.append("}\n");
        return sb.str;
    }

    private static int column_count(SaltPanel panel) {
        int cols = 1;
        foreach (var row in panel.rows) {
            bool separator_only = row.cells.size == 1 && row.cells[0].element_type == SaltElementType.SEPARATOR;
            if (!separator_only) cols = int.max(cols, row.cells.size);
        }
        return cols;
    }

    private void render_panel_rows(SaltPanel panel, StringBuilder sb, Palette palette, int depth) {
        int cols = column_count(panel);
        foreach (var row in panel.rows) {
            sb.append("        <TR>\n");
            if (row.cells.size == 1 && row.cells[0].element_type == SaltElementType.SEPARATOR) {
                render_separator(row.cells[0], sb, palette, cols);
            } else {
                for (int i = 0; i < row.cells.size; i++) {
                    // The last cell of a short row takes the remaining columns
                    int span = (i == row.cells.size - 1) ? cols - row.cells.size + 1 : 1;
                    render_cell(row.cells[i], sb, palette, depth, span, panel.panel_type);
                }
            }
            sb.append("        </TR>\n");
        }
    }

    // A thin line across the panel (PlantUML draws `--`, `==`, `..`, `~~`
    // as a light rule, not a filled bar).
    private void render_separator(SaltElement elem, StringBuilder sb, Palette palette, int cols) {
        string style = (elem.text == ".." || elem.text == "~~") ? " STYLE=\"DASHED\"" : "";
        sb.append_printf("          <TD COLSPAN=\"%d\" CELLPADDING=\"3\"><TABLE BORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR><TD BORDER=\"1\" SIDES=\"B\" COLOR=\"#A0A0A0\" HEIGHT=\"1\"%s></TD></TR></TABLE></TD>\n",
            cols, style);
    }

    private void render_cell(SaltElement elem, StringBuilder sb, Palette palette, int depth, int span,
                             string panel_type) {
        string text = Markup.escape_text(elem.text);
        string colspan = span > 1 ? " COLSPAN=\"%d\"".printf(span) : "";
        string grid = panel_type == "#" ? " BORDER=\"1\" COLOR=\"%s\"".printf(palette.node_text) : "";

        switch (elem.element_type) {
            case SaltElementType.BUTTON:
                // White, rounded, heavy outline
                sb.append_printf("          <TD%s%s CELLPADDING=\"3\"><TABLE BORDER=\"2\" STYLE=\"ROUNDED\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\" COLOR=\"%s\"><TR><TD><FONT COLOR=\"%s\">%s</FONT></TD></TR></TABLE></TD>\n",
                    colspan, grid, palette.node_text, palette.node_text, text.length > 0 ? text.strip() : " ");
                break;

            case SaltElementType.TEXT_FIELD:
                // Text on an underline with short end ticks
                sb.append_printf("          <TD%s%s ALIGN=\"LEFT\"><TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\" COLOR=\"%s\">" +
                    "<TR><TD COLSPAN=\"3\" CELLPADDING=\"1\" ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>" +
                    "<TR><TD BORDER=\"1\" SIDES=\"LB\" WIDTH=\"2\" HEIGHT=\"3\"></TD><TD BORDER=\"1\" SIDES=\"B\" HEIGHT=\"3\"></TD><TD BORDER=\"1\" SIDES=\"RB\" WIDTH=\"2\" HEIGHT=\"3\"></TD></TR>" +
                    "</TABLE></TD>\n",
                    colspan, grid, palette.node_text, palette.node_text, text.length > 0 ? text : " ");
                break;

            case SaltElementType.DROPDOWN:
                sb.append_printf("          <TD%s BORDER=\"1\" COLOR=\"%s\" CELLPADDING=\"2\" ALIGN=\"LEFT\">",
                    colspan, palette.node_text);
                sb.append_printf("<FONT COLOR=\"%s\">%s &#9660;</FONT></TD>\n", palette.node_text, text);
                break;

            case SaltElementType.RADIO:
                string marker = elem.checked ? "&#9673;" : "&#9675;";
                sb.append_printf("          <TD%s%s ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s %s</FONT></TD>\n",
                    colspan, grid, palette.node_text, marker, text);
                break;

            case SaltElementType.CHECKBOX:
                string marker_cb = elem.checked ? "&#9745;" : "&#9744;";
                sb.append_printf("          <TD%s%s ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s %s</FONT></TD>\n",
                    colspan, grid, palette.node_text, marker_cb, text);
                break;

            case SaltElementType.SEPARATOR:
                render_separator(elem, sb, palette, span);
                break;

            case SaltElementType.LABEL:
                sb.append_printf("          <TD%s%s ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD>\n",
                    colspan, grid, palette.node_text, text.length > 0 ? text : " ");
                break;

            case SaltElementType.PANEL: {
                string type = elem.nested_panel != null ? elem.nested_panel.panel_type : "";
                string frame = (type == "+" || type == "#") ? "BORDER=\"1\" COLOR=\"%s\"".printf(palette.node_text) : "BORDER=\"0\"";
                sb.append_printf("          <TD%s%s><TABLE %s CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n",
                    colspan, grid, frame);
                if (elem.nested_panel != null) {
                    render_panel_rows(elem.nested_panel, sb, palette, depth + 1);
                }
                sb.append("          </TABLE></TD>\n");
                break;
            }

            default:
                sb.append_printf("          <TD%s><FONT COLOR=\"%s\">%s</FONT></TD>\n",
                    colspan, palette.node_text, text);
                break;
        }
    }

    public uint8[]? render_to_svg(SaltDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse salt DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout salt graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render salt diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(SaltDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(SaltDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(SaltDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(SaltDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
