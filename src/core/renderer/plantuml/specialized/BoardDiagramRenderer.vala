/* BoardDiagramRenderer.vala — renders board/kanban layout as Graphviz DOT */
namespace GDiagram {

public class BoardDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public BoardDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(BoardDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        string[] column_colors = {
            palette.grid,
            palette.component_fill,
            palette.success,
            palette.accent_secondary,
            palette.warning,
            palette.person_fill
        };

        var sb = new StringBuilder();
        sb.append("digraph board {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    compound=true\n");
        sb.append("    splines=false\n");
        sb.append("    nodesep=0.3\n");
        sb.append("    ranksep=1.0\n");
        sb.append("    node [fontname=\"Sans\" fontsize=10]\n\n");

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
            sb.append("    labelloc=t\n");
            sb.append("    fontsize=14\n");
            sb.append("    fontname=\"Sans Bold\"\n\n");
        }

        int col_idx = 0;
        foreach (var col in diagram.columns) {
            string col_color = column_colors[col_idx % column_colors.length];
            string col_id = "col_%d".printf(col_idx);

            sb.append_printf("    subgraph cluster_%s {\n", col_id);
            sb.append_printf("        label=<%s>\n", Markup.escape_text(col.title));
            sb.append("        style=filled\n");
            sb.append_printf("        fillcolor=\"%s\"\n", col_color);
            sb.append("        color=\"%s\"\n".printf(palette.edge_color));
            sb.append("        fontcolor=\"%s\"\n".printf(palette.node_text));
            sb.append("        fontname=\"Sans Bold\"\n");
            sb.append("        fontsize=11\n");
            sb.append("        margin=12\n\n");

            int card_idx = 0;
            foreach (var card in col.cards) {
                string node_id = "card_%d_%d".printf(col_idx, card_idx);
                sb.append_printf("        %s [\n", node_id);
                sb.append("            shape=plaintext\n");
                sb.append_printf("            label=<<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"6\" BGCOLOR=\"%s\" COLOR=\"%s\"><TR><TD ALIGN=\"LEFT\">%s</TD></TR></TABLE>>\n",
                    palette.node_fill, palette.node_border, Markup.escape_text(card.text));
                sb.append("        ]\n");
                card_idx++;
            }

            // Invisible placeholder if column is empty
            if (col.cards.size == 0) {
                sb.append_printf("        empty_%d [label=\"\" shape=point style=invis width=0.1]\n", col_idx);
            }

            sb.append("    }\n\n");
            col_idx++;
        }

        // Chain cards vertically within each column
        col_idx = 0;
        foreach (var col in diagram.columns) {
            for (int i = 0; i < col.cards.size - 1; i++) {
                sb.append_printf("    card_%d_%d -> card_%d_%d [style=invis]\n", col_idx, i, col_idx, i + 1);
            }
            col_idx++;
        }

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(BoardDiagram diagram) {
        string dot = generate_dot(diagram);
        return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "board");
    }

    public Cairo.ImageSurface? render_to_surface(BoardDiagram diagram) {
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

            var viewport = Rsvg.Rectangle() {
                x = 0,
                y = 0,
                width = width,
                height = height
            };
            handle.render_document(cr, viewport);

            return surface;
        } catch (Error e) {
            warning("Failed to create surface from SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(BoardDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(BoardDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(BoardDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
