/* MermaidRadarRenderer.vala — Mermaid radar-beta renderer on a pinned ChartCanvas */
namespace GDiagram {

public class MermaidRadarRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidRadarRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    private const double RADIUS = 180.0;

    // radar.curveTension in Mermaid's default config.
    private const double CURVE_TENSION = 0.17;

    /**
     * Mermaid's closedRoundCurve: the cubic control points of the segment from
     * vertex i to vertex i+1, taken from the neighbouring vertices. With a
     * circle graticule Mermaid draws this smooth closed curve; with a polygon
     * graticule it draws a straight <polygon> instead.
     */
    internal static void curve_controls(double[] xs, double[] ys, int i,
                                        out double c1x, out double c1y,
                                        out double c2x, out double c2y) {
        int n = xs.length;
        int i0 = (i - 1 + n) % n, i2 = (i + 1) % n, i3 = (i + 2) % n;
        c1x = xs[i] + (xs[i2] - xs[i0]) * CURVE_TENSION;
        c1y = ys[i] + (ys[i2] - ys[i0]) * CURVE_TENSION;
        c2x = xs[i2] - (xs[i3] - xs[i]) * CURVE_TENSION;
        c2y = ys[i2] - (ys[i3] - ys[i]) * CURVE_TENSION;
    }

    private static string[] curve_colors(Palette palette) {
        return {
            palette.system_fill, palette.warning, palette.success,
            palette.accent_secondary, palette.person_fill, palette.container_fill
        };
    }

    // Values aligned to the axes (positional, or by axis id), min_value when missing.
    internal static double[] curve_values(MermaidRadar diagram, RadarCurve curve) {
        int n = diagram.axes.size;
        double[] vals = new double[n];
        for (int i = 0; i < n; i++) {
            if (curve.key_values.size > 0) {
                string axis_id = diagram.axes.get(i).id;
                vals[i] = curve.key_values.has_key(axis_id) ? curve.key_values.get(axis_id) : diagram.min_value;
            } else {
                vals[i] = (i < curve.values.size && curve.values.get(i) != null) ? curve.values.get(i) : diagram.min_value;
            }
        }
        return vals;
    }

    public string generate_dot(MermaidRadar diagram) {
        var palette = ThemeManager.get_active_palette();
        var cv = new ChartCanvas();
        string text_color = palette.node_text;

        bool has_title = diagram.title != null && diagram.title.length > 0;
        double top = has_title ? 34 : 0;

        int n = diagram.axes.size;
        if (n == 0) {
            if (has_title) cv.text(0, 10, diagram.title, 16, text_color, 'l', false, "radar_title");
            cv.text(0, top + 10, "(no axes defined)", 11, text_color, 'l');
            return cv.finish("radar", palette.background);
        }

        // Axis labels need room around the circle.
        double label_room = 20;
        foreach (var axis in diagram.axes) {
            label_room = double.max(label_room, ChartCanvas.text_width(axis.label, 12) + 12);
        }
        double cx = label_room + RADIUS;
        double cy = top + 24 + RADIUS;
        if (has_title) cv.text(cx, 10, diagram.title, 16, text_color, 'c', false, "radar_title");
        double range = diagram.max_value - diagram.min_value;
        if (range <= 0.0) range = 1.0;
        int ticks = diagram.ticks > 0 ? diagram.ticks : 5;

        // Graticule: `ticks` rings, largest first so the translucent fills stack
        // towards the centre (circles), or polygons through the axes.
        string ring_fill = palette.grid.length == 7 ? palette.grid + "66" : palette.grid;
        for (int t = ticks; t >= 1; t--) {
            double r = RADIUS * t / ticks;
            if (!diagram.graticule_polygon) {
                cv.circle(cx, cy, r, ring_fill, palette.grid, 1.0, "radar_ring_%d".printf(t));
            } else {
                for (int i = 0; i < n; i++) {
                    double a1 = 2.0 * Math.PI * i / n, a2 = 2.0 * Math.PI * (i + 1) / n;
                    cv.line(cx + r * Math.sin(a1), cy - r * Math.cos(a1),
                            cx + r * Math.sin(a2), cy - r * Math.cos(a2),
                            palette.edge_color, 0.75, "radar_ring_%d_%d".printf(t, i));
                }
            }
        }

        // Axes clockwise from 12 o'clock, labels just outside the circle.
        for (int i = 0; i < n; i++) {
            double ang = 2.0 * Math.PI * i / n;
            double ex = cx + RADIUS * Math.sin(ang), ey = cy - RADIUS * Math.cos(ang);
            cv.line(cx, cy, ex, ey, palette.edge_color, 1.5, "radar_axis_%d".printf(i));
            double lx = cx + RADIUS * 1.06 * Math.sin(ang), ly = cy - RADIUS * 1.06 * Math.cos(ang);
            double sx = Math.sin(ang), sy = Math.cos(ang);
            char align = sx > 0.2 ? 'l' : (sx < -0.2 ? 'r' : 'c');
            if (align == 'c') ly -= 9 * (sy >= 0 ? 1 : -1);
            cv.text(lx, ly, diagram.axes.get(i).label, 12, text_color, align, false, "radar_axis_label_%d".printf(i));
        }

        // Curves: vertex markers first (render_to_svg adds the translucent
        // fills beneath them), then the outlines.
        string[] colors = curve_colors(palette);
        var points = new Gee.ArrayList<double?>();
        for (int c = 0; c < diagram.curves.size; c++) {
            double[] vals = curve_values(diagram, diagram.curves.get(c));
            string color = colors[c % colors.length];
            for (int i = 0; i < n; i++) {
                double norm = (vals[i] - diagram.min_value) / range;
                norm = double.max(0.0, double.min(1.0, norm));
                double ang = 2.0 * Math.PI * i / n;
                double px = cx + norm * RADIUS * Math.sin(ang), py = cy - norm * RADIUS * Math.cos(ang);
                points.add(px);
                points.add(py);
                cv.circle(px, py, 2.0, color, color, 0.5, "radar_curve_%d_pt_%d".printf(c, i));
            }
        }
        for (int c = 0; c < diagram.curves.size; c++) {
            string color = colors[c % colors.length];
            var xs = new double[n];
            var ys = new double[n];
            for (int i = 0; i < n; i++) {
                xs[i] = points.get(2 * (c * n + i));
                ys[i] = points.get(2 * (c * n + i) + 1);
            }
            for (int i = 0; i < n; i++) {
                int j = (i + 1) % n;
                if (diagram.graticule_polygon) {
                    cv.line(xs[i], ys[i], xs[j], ys[j], color, 2.0, "radar_curve_%d_%d".printf(c, i));
                } else {
                    double c1x, c1y, c2x, c2y;
                    curve_controls(xs, ys, i, out c1x, out c1y, out c2x, out c2y);
                    cv.bezier(xs[i], ys[i], c1x, c1y, c2x, c2y, xs[j], ys[j],
                        color, 2.0, "radar_curve_%d_%d".printf(c, i));
                }
            }
        }

        // Legend to the right of the chart.
        if (diagram.show_legend && diagram.curves.size > 0) {
            double lx = cx + RADIUS + label_room + 10;
            double ly = top + 30;
            for (int c = 0; c < diagram.curves.size; c++) {
                string color = colors[c % colors.length];
                double rowy = ly + c * 22;
                cv.rect(lx, rowy - 7, 14, 14, color, color, 1.0, "radar_legend_box_%d".printf(c));
                cv.text(lx + 20, rowy, diagram.curves.get(c).label, 12, text_color, 'l', false,
                    "radar_legend_%d".printf(c));
            }
        }

        return cv.finish("radar", palette.background);
    }

    // Graphviz cannot fill an arbitrary polygon: add one translucent <polygon>
    // per curve, through its vertex markers, below the first marker.
    internal static uint8[] add_curve_fills(uint8[] svg_data, MermaidRadar diagram) {
        if (diagram.curves.size == 0 || diagram.axes.size < 3) return svg_data;
        var text = new StringBuilder.sized(svg_data.length + 1);
        text.append_len((string) svg_data, svg_data.length);
        string svg = text.str;
        var palette = ThemeManager.get_active_palette();
        string[] colors = curve_colors(palette);
        var fills = new StringBuilder();
        try {
            int n = diagram.axes.size;
            for (int c = 0; c < diagram.curves.size; c++) {
                var xs = new double[n];
                var ys = new double[n];
                for (int i = 0; i < n; i++) {
                    var re = new Regex("<g id=\"radar_curve_%d_pt_%d\" class=\"node\">.*?<ellipse[^>]*cx=\"([-\\d.]+)\" cy=\"([-\\d.]+)\"".printf(c, i),
                        RegexCompileFlags.DOTALL);
                    MatchInfo m;
                    if (!re.match(svg, 0, out m)) return svg_data;
                    xs[i] = double.parse(m.fetch(1));
                    ys[i] = double.parse(m.fetch(2));
                }
                var shape = new StringBuilder();
                if (diagram.graticule_polygon) {
                    for (int i = 0; i < n; i++) {
                        shape.append_printf("%s%s,%s", i > 0 ? " " : "", fnum(xs[i]), fnum(ys[i]));
                    }
                    fills.append_printf("<polygon class=\"radar-fill\" fill=\"%s\" fill-opacity=\"0.3\" stroke=\"none\" points=\"%s\"/>\n",
                        colors[c % colors.length], shape.str);
                } else {
                    // Same closedRoundCurve as the stroked outline, in SVG space.
                    shape.append_printf("M%s,%s", fnum(xs[0]), fnum(ys[0]));
                    for (int i = 0; i < n; i++) {
                        double c1x, c1y, c2x, c2y;
                        curve_controls(xs, ys, i, out c1x, out c1y, out c2x, out c2y);
                        int j = (i + 1) % n;
                        shape.append_printf(" C%s,%s %s,%s %s,%s", fnum(c1x), fnum(c1y),
                            fnum(c2x), fnum(c2y), fnum(xs[j]), fnum(ys[j]));
                    }
                    shape.append(" Z");
                    fills.append_printf("<path class=\"radar-fill\" fill=\"%s\" fill-opacity=\"0.3\" stroke=\"none\" d=\"%s\"/>\n",
                        colors[c % colors.length], shape.str);
                }
            }
        } catch (RegexError e) {
            return svg_data;
        }
        int at = svg.index_of("<g id=\"radar_curve_0_pt_0\"");
        if (at < 0) return svg_data;
        string result = svg.substring(0, at) + fills.str + svg.substring(at);
        uint8[] out_data = result.data;
        return out_data;
    }

    private static string fnum(double v) {
        return "%.2f".printf(v).replace(",", ".");
    }

    public uint8[]? render_to_svg(MermaidRadar diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse radar DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out radar graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render radar graph");
            return null;
        }

        return add_curve_fills(svg_data, diagram);
    }

    public Cairo.ImageSurface? render_to_surface(MermaidRadar diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 600, out width, out height);

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
            warning("Failed to render radar SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidRadar diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidRadar diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidRadar diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
