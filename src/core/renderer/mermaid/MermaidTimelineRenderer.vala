/* MermaidTimelineRenderer.vala — renders Mermaid timeline diagrams
 *
 * The layout is computed here and pinned through ChartCanvas (layout=nop2),
 * following Mermaid 11.17's timeline renderer: one column per period, the
 * period box on top, a horizontal time arrow below it, and the period's events
 * as separate boxes stacked underneath, joined to the period by a dashed
 * connector. Sections become a wide band above the columns they cover.
 *
 * Graphviz's own layout gave every period a single HTML table, in which the
 * inner cell borders vanished whenever the section's fill and stroke colours
 * happened to be the same — so only some periods appeared to have event boxes.
 */
namespace GDiagram {

public class MermaidTimelineRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Mermaid's node metrics (px): 150 text width plus 20 padding each side,
    // laid out on a 200 px grid, so neighbouring boxes keep a 10 px gap.
    private const double TEXT_W = 150;
    private const double NODE_W = 190;
    private const double COL_STEP = 200;
    private const double FONT = 12;
    private const double LINE_H = 16;
    private const double PAD_V = 13;
    private const double MIN_BOX_H = 44;
    private const double EVENT_GAP = 10;
    private const double SECTION_GAP = 28;
    private const double AXIS_GAP = 26;
    private const double EVENT_TOP_GAP = 34;

    // Region name and source line per canvas node, filled by generate_dot().
    private Gee.HashMap<string, string> region_names = new Gee.HashMap<string, string>();
    private Gee.HashMap<string, int> element_lines = new Gee.HashMap<string, int>();

    private string[] section_colors(Palette p) {
        return { p.container_fill, p.success, p.accent_secondary, p.warning, p.person_fill };
    }

    public MermaidTimelineRenderer(Gvc.Context ctx,
                                    Gee.ArrayList<ElementRegion> regions,
                                    string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // Contiguous run of periods sharing one section name.
    private class Band {
        public string? name;
        public int first;
        public int count;
    }

    // Greedy word wrap to Mermaid's 150 px text width.
    private static Gee.ArrayList<string> wrap(string text, double max_w) {
        var lines = new Gee.ArrayList<string>();
        foreach (string para in text.split("\n")) {
            var cur = new StringBuilder();
            foreach (string w in para.split(" ")) {
                if (w.length == 0) continue;
                string cand = cur.len == 0 ? w : cur.str + " " + w;
                if (cur.len > 0 && GanttText.width(cand, FONT) > max_w) {
                    lines.add(cur.str);
                    cur.assign(w);
                } else {
                    cur.assign(cand);
                }
            }
            lines.add(cur.str);
        }
        if (lines.size == 0) lines.add("");
        return lines;
    }

    private static double box_height(Gee.ArrayList<string> lines) {
        return double.max(MIN_BOX_H, lines.size * LINE_H + 2 * PAD_V);
    }

    // Mix a hex colour towards black; used for the strip under each box, which
    // Mermaid draws in a contrasting shade of the section colour.
    private static int hex_byte(string s, int at) {
        int v = 0;
        for (int i = at; i < at + 2; i++) {
            char c = s[i];
            int d = (c >= '0' && c <= '9') ? c - '0'
                  : (c >= 'a' && c <= 'f') ? c - 'a' + 10
                  : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : 0;
            v = v * 16 + d;
        }
        return v;
    }

    private static string shade(string color, double factor) {
        if (color.length != 7 || color[0] != '#') return color;
        int r = (int) (hex_byte(color, 1) * factor);
        int g = (int) (hex_byte(color, 3) * factor);
        int b = (int) (hex_byte(color, 5) * factor);
        return "#%02X%02X%02X".printf(int.min(255, r), int.min(255, g), int.min(255, b));
    }

    // Draws a filled box with the section's underline strip and its centred,
    // wrapped label; every canvas node it creates maps to `region`.
    private void draw_box(ChartCanvas cv, double x, double y, double w, double h,
                          Gee.ArrayList<string> lines, string fill, string region, int line) {
        string strip = shade(fill, 0.72);
        string text_color = RenderUtils.contrast_text(fill);
        note_region(cv.rect(x, y, w, h, fill, strip, 0, region), region, line);
        note_region(cv.rect(x, y + h - 3, w, 3, strip, strip, 0, region + "_strip"), region, line);
        double first = y + h / 2 - (lines.size - 1) * LINE_H / 2;
        for (int i = 0; i < lines.size; i++) {
            note_region(cv.text(x + w / 2, first + i * LINE_H, lines.get(i), FONT, text_color,
                'c', false, "%s_t%d".printf(region, i)), region, line);
        }
    }

    private void note_region(string node, string region, int line) {
        if (node.length == 0) return;
        region_names.set(node, region);
        if (line > 0) element_lines.set(region, line);
    }

    // A ">" chevron at (x, y) pointing right, standing in for an arrowhead.
    private static void arrow_head(ChartCanvas cv, double x, double y, string color, bool down) {
        double s = 6;
        if (down) {
            cv.line(x - s, y - s, x, y, color, 1.5);
            cv.line(x + s, y - s, x, y, color, 1.5);
        } else {
            cv.line(x - s, y - s, x, y, color, 2.0);
            cv.line(x - s, y + s, x, y, color, 2.0);
        }
    }

    public string generate_dot(MermaidTimeline diagram) {
        var palette = ThemeManager.get_active_palette();
        var cv = new ChartCanvas();
        region_names = new Gee.HashMap<string, string>();
        element_lines = new Gee.HashMap<string, int>();
        string text_color = palette.node_text;

        bool has_title = diagram.title != null && diagram.title.length > 0;

        int n = diagram.periods.size;
        if (n == 0) {
            if (has_title) cv.text(0, 10, diagram.title, 16, text_color, 'l', true, "timeline_title");
            cv.text(0, has_title ? 40 : 10, "(no periods)", FONT, text_color, 'l');
            return cv.finish("timeline", palette.background);
        }

        // Sections become bands over the columns they cover.
        var bands = new Gee.ArrayList<Band>();
        for (int i = 0; i < n; i++) {
            string? sec = diagram.periods.get(i).section_name;
            if (bands.size > 0 && bands.last().name == sec) {
                bands.last().count++;
            } else {
                var b = new Band();
                b.name = sec;
                b.first = i;
                b.count = 1;
                bands.add(b);
            }
        }
        bool has_sections = false;
        foreach (var b in bands) if (b.name != null) has_sections = true;

        // Measure everything first: all period boxes share one height, as do
        // the event boxes of a given row position.
        var period_lines = new Gee.ArrayList<Gee.ArrayList<string>>();
        double period_h = MIN_BOX_H;
        foreach (var p in diagram.periods) {
            var l = wrap(p.label, TEXT_W);
            period_lines.add(l);
            period_h = double.max(period_h, box_height(l));
        }
        double section_h = 0;
        var band_lines = new Gee.ArrayList<Gee.ArrayList<string>>();
        foreach (var b in bands) {
            var l = wrap(b.name ?? "", TEXT_W);
            band_lines.add(l);
            if (b.name != null) section_h = double.max(section_h, box_height(l));
        }

        double y = 0;
        if (has_title) {
            cv.text(0, 14, diagram.title, 18, text_color, 'l', true, "timeline_title");
            y = 44;
        }
        double band_y = y;
        if (has_sections) y += section_h + SECTION_GAP;
        double period_y = y;
        double axis_y = period_y + period_h + AXIS_GAP;
        double event_y = axis_y + EVENT_TOP_GAP;

        string[] colors = section_colors(palette);

        // Section bands, spanning 200 * count - 50 as Mermaid does.
        for (int bi = 0; bi < bands.size; bi++) {
            var b = bands.get(bi);
            if (b.name == null) continue;
            double bx = b.first * COL_STEP;
            double bw = COL_STEP * b.count - 50;
            draw_box(cv, bx, band_y, bw, section_h, band_lines.get(bi),
                colors[bi % colors.length], "section_%d".printf(bi),
                diagram.periods.get(b.first).source_line);
        }

        // The colour of column i: without sections Mermaid gives every period
        // its own, with sections a whole band shares the section's.
        var col_fill = new string[n];
        for (int bi = 0; bi < bands.size; bi++) {
            var b = bands.get(bi);
            for (int k = 0; k < b.count; k++) {
                col_fill[b.first + k] = has_sections ? colors[bi % colors.length]
                                                     : colors[(b.first + k) % colors.length];
            }
        }

        // Wrap every event and measure the stack, so the dashed connectors can
        // be drawn first — Mermaid paints them under the boxes they pass.
        var event_lines = new Gee.ArrayList<Gee.ArrayList<string>>();
        for (int i = 0; i < n; i++) {
            var period = diagram.periods.get(i);
            double ey = event_y;
            for (int j = 0; j < period.events.size; j++) {
                var el = wrap(period.events.get(j).text, TEXT_W);
                event_lines.add(el);
                ey += box_height(el) + EVENT_GAP;
            }
            if (period.events.size > 0) ey -= EVENT_GAP;
            double cx = i * COL_STEP + NODE_W / 2;
            double tip = ey + 26;
            cv.line(cx, period_y + period_h, cx, tip, palette.edge_color, 1.5, null, "style=dashed");
            arrow_head(cv, cx, tip, palette.edge_color, true);
        }

        // One column per period: the period box on top, its events below.
        int flat = 0;
        for (int i = 0; i < n; i++) {
            var period = diagram.periods.get(i);
            string fill = col_fill[i];
            double x = i * COL_STEP;
            draw_box(cv, x, period_y, NODE_W, period_h, period_lines.get(i), fill,
                "period_%d".printf(i), period.source_line);

            double ey = event_y;
            for (int j = 0; j < period.events.size; j++) {
                var el = event_lines.get(flat++);
                double eh = box_height(el);
                draw_box(cv, x, ey, NODE_W, eh, el, fill,
                    "event_%d_%d".printf(i, j), period.events.get(j).source_line);
                ey += eh + EVENT_GAP;
            }
        }

        // The time arrow, between the period row and the events.
        double axis_end = (n - 1) * COL_STEP + NODE_W + 40;
        cv.line(0, axis_y, axis_end, axis_y, palette.node_text, 2.5, "timeline_axis");
        arrow_head(cv, axis_end, axis_y, palette.node_text, false);

        return cv.finish("timeline", palette.background);
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidTimeline diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse timeline DOT graph");
            return null;
        }

        int ret = context.layout(graph, "nop2");
        if (ret != 0) {
            warning("Failed to layout timeline graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render timeline graph");
            return null;
        }

        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidTimeline diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 800, 300, out width, out height);

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

            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height, region_names);
            return surface;
        } catch (Error e) {
            warning("Failed to render timeline SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidTimeline diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidTimeline diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidTimeline diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
