/* DitaaDiagramRenderer.vala — renders DITAA ASCII art as monospace DOT node */
namespace GDiagram {

public class DitaaDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public DitaaDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(DitaaDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();

        sb.append("digraph ditaa {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    node [fontname=\"monospace\" fontsize=10]\n\n");

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
            sb.append("    labelloc=t\n");
            sb.append("    fontsize=14\n");
            sb.append("    fontname=\"Sans Bold\"\n\n");
        }

        // Render ASCII art as a single plaintext node with HTML TABLE
        sb.append("    ascii_art [\n");
        sb.append("        shape=plaintext\n");
        sb.append("        label=<\n");
        sb.append_printf("            <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">\n",
            palette.node_fill, palette.node_border);

        string[] lines = diagram.ascii_text.split("\n");
        foreach (string line in lines) {
            string escaped = Markup.escape_text(line);
            // Preserve spaces by replacing them with non-breaking spaces
            escaped = escaped.replace(" ", "&#160;");
            sb.append_printf("            <TR><TD ALIGN=\"LEFT\"><FONT FACE=\"monospace\" POINT-SIZE=\"10\" COLOR=\"%s\">%s</FONT></TD></TR>\n",
                palette.node_text, escaped);
        }

        sb.append("            </TABLE>\n");
        sb.append("        >\n");
        sb.append("    ]\n");
        sb.append("}\n");

        return sb.str;
    }

    public uint8[]? render_to_svg(DitaaDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse DITAA DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout DITAA graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render DITAA diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(DitaaDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(DitaaDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(DitaaDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(DitaaDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
