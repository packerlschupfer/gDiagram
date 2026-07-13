/* MermaidPacketRenderer.vala — Mermaid packet-beta diagram renderer */
namespace GDiagram {

public class MermaidPacketRenderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidPacketRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.ctx = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidPacket diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    node [shape=plaintext fontname=\"monospace\" fontsize=11 fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    rankdir=TB\n\n");

        if (diagram.fields.size == 0) {
            sb.append("    empty [label=\"(no fields defined)\" shape=note]\n");
            sb.append("}\n");
            return sb.str;
        }

        // Build title
        string title = (diagram.title != null && diagram.title.length > 0)
            ? Markup.escape_text(diagram.title)
            : "Packet Structure";

        // Determine total bits and group into rows of 32
        int bits_per_row = 32;
        int total_width = 0;
        foreach (var f in diagram.fields) {
            if (f.bit_end + 1 > total_width) total_width = f.bit_end + 1;
        }
        if (total_width == 0) total_width = 32;

        // Render as single HTML TABLE node
        sb.append("    packet [label=<\n");
        sb.append("        <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"4\" CELLPADDING=\"4\">\n");

        // Title row
        sb.append("        <TR><TD COLSPAN=\"64\" ALIGN=\"CENTER\"><FONT COLOR=\"%s\"><B>".printf(palette.node_text));
        sb.append(title);
        sb.append("</B></FONT></TD></TR>\n");

        // Process fields in rows of bits_per_row
        int row_start = 0;
        int row_num = 0;
        while (row_start < total_width) {
            int row_end = row_start + bits_per_row - 1;

            // Collect fields that overlap this row
            var row_fields = new Gee.ArrayList<PacketField>();
            foreach (var f in diagram.fields) {
                if (f.bit_end >= row_start && f.bit_start <= row_end) {
                    row_fields.add(f);
                }
            }

            if (row_fields.size == 0) {
                row_start += bits_per_row;
                row_num++;
                continue;
            }

            // Bit range header row
            sb.append("        <TR>\n");
            int pos = row_start;
            foreach (var f in row_fields) {
                int fstart = int.max(f.bit_start, row_start);
                int fend = int.min(f.bit_end, row_end);
                int colspan = fend - fstart + 1;
                if (colspan < 1) colspan = 1;
                sb.append_printf("          <TD COLSPAN=\"%d\" BORDER=\"1\" BGCOLOR=\"%s\" ALIGN=\"CENTER\"><FONT POINT-SIZE=\"8\" COLOR=\"%s\">%d-%d</FONT></TD>\n",
                    colspan, palette.grid, palette.node_text, fstart, fend);
                pos = fend + 1;
            }
            // Fill remaining bits in row
            if (pos <= row_end) {
                int remaining = row_end - pos + 1;
                sb.append_printf("          <TD COLSPAN=\"%d\" BORDER=\"1\" BGCOLOR=\"%s\" ALIGN=\"CENTER\"><FONT POINT-SIZE=\"8\" COLOR=\"%s\">%d-%d</FONT></TD>\n",
                    remaining, palette.grid, palette.node_text, pos, row_end);
            }
            sb.append("        </TR>\n");

            // Field label row
            string[] colors = {
                palette.container_fill, palette.success, palette.accent_secondary,
                palette.person_fill, palette.warning
            };
            sb.append("        <TR>\n");
            foreach (var f in row_fields) {
                int fstart = int.max(f.bit_start, row_start);
                int fend = int.min(f.bit_end, row_end);
                int colspan = fend - fstart + 1;
                if (colspan < 1) colspan = 1;
                int color_idx = (row_fields.index_of(f)) % colors.length;
                string bg = colors[color_idx];
                string escaped = Markup.escape_text(f.label);
                sb.append_printf("          <TD COLSPAN=\"%d\" BORDER=\"1\" BGCOLOR=\"%s\" ALIGN=\"CENTER\"><FONT COLOR=\"%s\"><B>%s</B></FONT></TD>\n",
                    colspan, bg, RenderUtils.contrast_text(bg), escaped);
            }
            // Fill remaining
            int cur = row_start;
            foreach (var f in row_fields) {
                cur = int.min(f.bit_end, row_end) + 1;
            }
            if (cur <= row_end) {
                int remaining = row_end - cur + 1;
                sb.append_printf("          <TD COLSPAN=\"%d\" BORDER=\"1\" BGCOLOR=\"%s\" ALIGN=\"CENTER\"><FONT COLOR=\"%s\">&#x2014;</FONT></TD>\n", remaining, palette.node_fill, palette.node_text);
            }
            sb.append("        </TR>\n");

            row_start += bits_per_row;
            row_num++;
        }

        sb.append("        </TABLE>\n");
        sb.append("    >]\n");
        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidPacket diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse DOT graph");
            return null;
        }

        int ret = ctx.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to layout graph with engine: %s", layout_engine);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(ctx, graph, "svg", out svg_data);

        ctx.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidPacket diagram) {
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

            RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidPacket diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidPacket diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidPacket diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
