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

        // Render the root panel as an HTML TABLE node
        sb.append("    salt_root [shape=plaintext label=<\n");
        sb.append("      <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"6\" ");
        sb.append_printf("BGCOLOR=\"%s\" COLOR=\"%s\">\n", palette.node_fill, palette.node_border);

        render_panel_rows(diagram.root, sb, palette, 0);

        sb.append("      </TABLE>\n");
        sb.append("    >]\n");
        sb.append("}\n");
        return sb.str;
    }

    private void render_panel_rows(SaltPanel panel, StringBuilder sb, Palette palette, int depth) {
        foreach (var row in panel.rows) {
            sb.append("        <TR>\n");
            foreach (var cell in row.cells) {
                render_cell(cell, sb, palette, depth);
            }
            sb.append("        </TR>\n");
        }
    }

    private void render_cell(SaltElement elem, StringBuilder sb, Palette palette, int depth) {
        string text = Markup.escape_text(elem.text);

        switch (elem.element_type) {
            case SaltElementType.BUTTON:
                sb.append_printf("          <TD BGCOLOR=\"%s\" BORDER=\"1\" STYLE=\"ROUNDED\" CELLPADDING=\"4\">",
                    palette.component_fill);
                sb.append_printf("<FONT COLOR=\"%s\"> %s </FONT></TD>\n",
                    RenderUtils.contrast_text(palette.component_fill), text);
                break;

            case SaltElementType.TEXT_FIELD:
                sb.append_printf("          <TD BGCOLOR=\"%s\" BORDER=\"1\" CELLPADDING=\"4\" ALIGN=\"LEFT\">",
                    palette.background);
                sb.append_printf("<FONT COLOR=\"%s\">%s</FONT></TD>\n", palette.node_text, text);
                break;

            case SaltElementType.DROPDOWN:
                sb.append_printf("          <TD BGCOLOR=\"%s\" BORDER=\"1\" CELLPADDING=\"4\">",
                    palette.background);
                sb.append_printf("<FONT COLOR=\"%s\">%s &#9660;</FONT></TD>\n", palette.node_text, text);
                break;

            case SaltElementType.RADIO:
                string marker = elem.checked ? "&#9673;" : "&#9675;";
                sb.append_printf("          <TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s %s</FONT></TD>\n",
                    palette.node_text, marker, text);
                break;

            case SaltElementType.CHECKBOX:
                string marker_cb = elem.checked ? "&#9745;" : "&#9744;";
                sb.append_printf("          <TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s %s</FONT></TD>\n",
                    palette.node_text, marker_cb, text);
                break;

            case SaltElementType.SEPARATOR:
                sb.append_printf("          <TD COLSPAN=\"10\" HEIGHT=\"1\" BGCOLOR=\"%s\"></TD>\n",
                    palette.node_border);
                break;

            case SaltElementType.LABEL:
                sb.append_printf("          <TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD>\n",
                    palette.node_text, text);
                break;

            case SaltElementType.PANEL:
                // Nested panel — render as nested table with its rows
                sb.append_printf("          <TD><TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">\n",
                    palette.node_fill, palette.node_border);
                if (elem.nested_panel != null) {
                    render_panel_rows(elem.nested_panel, sb, palette, depth + 1);
                }
                sb.append("          </TABLE></TD>\n");
                break;

            default:
                sb.append_printf("          <TD><FONT COLOR=\"%s\">%s</FONT></TD>\n",
                    palette.node_text, text);
                break;
        }
    }

    public uint8[]? render_to_svg(SaltDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
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
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

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
