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
        if (diagram.plantuml_style) {
            return generate_packetdiag_dot(diagram);
        }
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

    // ==================== PlantUML packetdiag ====================

    // PlantUML draws packetdiag at 14px text, 3 text sizes per bit and 38px
    // rows; Graphviz works in points (1px = 0.75pt), so these are the
    // PlantUML pixel sizes scaled to points.
    private const double PX = 0.75;
    private const double PD_BIT = 42.0 * PX;
    private const double PD_ROW = 38.0 * PX;
    private const double PD_FONT = 14.0 * PX;
    private const double PD_TICK_FULL = 32.0 * PX;
    private const double PD_TICK_SHORT = 16.0 * PX;
    private const double PD_NUMBER_H = 20.0 * PX;
    private const double PD_MARGIN = 10.0 * PX;

    private class PdBlock {
        public PacketField field;
        public int bits;
        public PdBlock(PacketField f, int bits) { this.field = f; this.bits = bits; }
    }

    // Split the fields into rows of `colwidth` bits. A field that does not fit
    // continues on the next row, labelled again there.
    private static Gee.ArrayList<Gee.ArrayList<PdBlock>> packetdiag_rows(MermaidPacket d, int colwidth) {
        var rows = new Gee.ArrayList<Gee.ArrayList<PdBlock>>();
        var row = new Gee.ArrayList<PdBlock>();
        int free_bits = colwidth;
        foreach (var f in d.fields) {
            int left = f.bit_width();
            while (left > 0) {
                int take = int.min(left, free_bits);
                row.add(new PdBlock(f, take));
                left -= take;
                free_bits -= take;
                if (free_bits == 0) {
                    rows.add(row);
                    row = new Gee.ArrayList<PdBlock>();
                    free_bits = colwidth;
                }
            }
        }
        if (row.size > 0) rows.add(row);
        return rows;
    }

    // Text wider than its block is cut and ends in "...", as PlantUML does.
    // Width estimate: about 0.5em per character for the Sans text.
    internal static string packetdiag_fit_label(string text, double block_width, double font_size) {
        double avail = block_width - 2 * 5.0 * PX;
        double char_w = font_size * 0.5;
        if (text.char_count() * char_w <= avail) return text;
        int keep = (int) Math.floor(avail / char_w) - 3;
        if (keep < 0) keep = 0;
        return text.substring(0, text.index_of_nth_char(keep)).chomp() + "...";
    }

    private static string pd_num(double v) {
        return "%.2f".printf(v).replace(",", ".");
    }

    private static void pd_line(StringBuilder sb, ref int n, double x1, double y1, double x2, double y2,
                                string color) {
        string a = "pd_p%d".printf(n++);
        string b = "pd_p%d".printf(n++);
        sb.append_printf("    %s [pos=\"%s,%s\" shape=point style=invis width=0 height=0 label=\"\"]\n",
            a, pd_num(x1), pd_num(y1));
        sb.append_printf("    %s [pos=\"%s,%s\" shape=point style=invis width=0 height=0 label=\"\"]\n",
            b, pd_num(x2), pd_num(y2));
        sb.append_printf("    %s -- %s [pos=\"%s,%s %s,%s %s,%s %s,%s\" color=\"%s\" penwidth=0.75]\n",
            a, b, pd_num(x1), pd_num(y1), pd_num(x1), pd_num(y1), pd_num(x2), pd_num(y2),
            pd_num(x2), pd_num(y2), color);
    }

    private string generate_packetdiag_dot(MermaidPacket d) {
        var palette = ThemeManager.get_active_palette();
        const string BOX_FILL = "#F1F1F1";
        const string BOX_LINE = "#181818";
        const string BOX_TEXT = "#000000";

        int colwidth = d.colwidth > 0 ? d.colwidth : 16;
        var rows = packetdiag_rows(d, colwidth);
        // A packet narrower than one row shrinks the row to its bits.
        if (rows.size > 0) {
            int first = 0;
            foreach (var b in rows.get(0)) first += b.bits;
            if (rows.size == 1 && first < colwidth) colwidth = first;
        }
        if (colwidth <= 0) colwidth = 16;
        int scale = d.scale_interval > 0 ? int.min(d.scale_interval, colwidth) : int.max(1, colwidth / 2);
        int full = colwidth >= 4 ? colwidth / 4 : colwidth;

        double base_row = d.node_height > 0 ? d.node_height * PX : PD_ROW;
        var row_heights = new Gee.ArrayList<double?>();
        double tallest = base_row;
        foreach (var row in rows) {
            int span = 1;
            foreach (var b in row) span = int.max(span, b.field.row_span);
            row_heights.add(base_row * span);
            tallest = double.max(tallest, base_row * span);
        }
        if (d.same_height) {
            for (int i = 0; i < row_heights.size; i++) row_heights.set(i, tallest);
        }

        double title_h = (d.title != null && d.title.length > 0) ? 40.0 * PX : 0.0;
        double ruler_top = PD_MARGIN + title_h;
        double fields_top = ruler_top + PD_NUMBER_H + PD_TICK_FULL;
        double total_h = fields_top;
        foreach (var h in row_heights) total_h += h;
        double total_w = colwidth * PD_BIT;
        // Graphviz y grows upwards: flip the top-down layout.
        double height = total_h + PD_MARGIN;

        var sb = new StringBuilder();
        sb.append("graph packetdiag {\n");
        sb.append("    layout=nop2\n");
        sb.append_printf("    bgcolor=\"%s\"\n", palette.background);
        sb.append("    splines=line\n");
        sb.append_printf("    node [fontname=\"Sans\" fontsize=%s fixedsize=true]\n", pd_num(PD_FONT));
        // Corner anchors keep the margins inside the drawing.
        sb.append_printf("    pd_tl [pos=\"0,%s\" shape=point style=invis width=0 height=0 label=\"\"]\n", pd_num(height));
        sb.append_printf("    pd_br [pos=\"%s,0\" shape=point style=invis width=0 height=0 label=\"\"]\n",
            pd_num(total_w + 2 * PD_MARGIN));

        if (title_h > 0) {
            sb.append_printf("    pd_title [pos=\"%s,%s\" shape=plaintext width=%s height=0.3 label=<<B>%s</B>> fontcolor=\"%s\"]\n",
                pd_num(PD_MARGIN + total_w / 2), pd_num(height - PD_MARGIN - title_h / 2),
                pd_num((total_w + 2 * PD_MARGIN) / 72.0), Markup.escape_text(d.title), palette.node_text);
        }

        int n = 0;
        // Bit ruler: a number every `scale` bits, a full-height tick every
        // quarter row and a short tick at every other bit.
        for (int i = 0; i <= colwidth; i++) {
            double x = PD_MARGIN + i * PD_BIT;
            bool is_full = (i % full) == 0;
            bool numbered = (i % scale) == 0;
            double tick_bottom = height - fields_top;
            double tick_top = tick_bottom + (is_full ? PD_TICK_FULL : PD_TICK_SHORT);
            if (numbered) {
                int label = d.scale_rtl ? colwidth - i : i;
                double num_y = height - ruler_top - PD_NUMBER_H / 2 - (is_full ? 0 : PD_TICK_SHORT);
                sb.append_printf("    pd_n%d [pos=\"%s,%s\" shape=plaintext width=0.5 height=0.25 label=\"%d\" fontcolor=\"%s\"]\n",
                    i, pd_num(x), pd_num(num_y), label, palette.node_text);
            }
            pd_line(sb, ref n, x, tick_top, x, tick_bottom, palette.node_text);
        }

        double y = fields_top;
        for (int r = 0; r < rows.size; r++) {
            var row = rows.get(r);
            double rh = row_heights.get(r);
            var ordered = new Gee.ArrayList<PdBlock>();
            ordered.add_all(row);
            if (d.scale_rtl) {
                var rev = new Gee.ArrayList<PdBlock>();
                for (int i = ordered.size - 1; i >= 0; i--) rev.add(ordered.get(i));
                ordered = rev;
            }
            double x = PD_MARGIN;
            int bi = 0;
            foreach (var b in ordered) {
                double w = b.bits * PD_BIT;
                string text = packetdiag_fit_label(b.field.label, w, PD_FONT);
                sb.append_printf("    pd_f%d_%d [id=\"packet_field_%d\" pos=\"%s,%s\" shape=box width=%s height=%s style=filled fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" penwidth=0.75 label=\"%s\"]\n",
                    r, bi, b.field.source_line, pd_num(x + w / 2), pd_num(height - (y + rh / 2)),
                    pd_num(w / 72.0), pd_num(rh / 72.0), BOX_FILL, BOX_LINE, BOX_TEXT,
                    RenderUtils.escape_label(text));
                x += w;
                bi++;
            }
            y += rh;
        }

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidPacket diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
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
        ret = RenderUtils.render_data(ctx, graph, "svg", out svg_data);

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
