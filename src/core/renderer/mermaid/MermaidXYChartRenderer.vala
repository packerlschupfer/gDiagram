namespace GDiagram {

    /**
     * Fixed-geometry drawing for the Mermaid chart renderers (xychart, pie,
     * radar, treemap, packet): shapes are placed at exact coordinates and the
     * DOT is laid out with `layout=nop2`, so Graphviz only draws them.
     *
     * Coordinates are in points with the origin top-left (y grows down);
     * finish() shifts everything inside a margin and flips it to Graphviz's
     * y-up space. Items are emitted in the order they were added, which is
     * also their drawing (z) order. Shape methods return the DOT node name,
     * which is the <title> that click-to-source region parsing keys on.
     */
    public class ChartCanvas : Object {
        private class Item {
            public bool is_line;
            public string name;
            public double x1;
            public double y1;
            public double x2;
            public double y2;
            public double w;
            public double h;
            public string attrs;
            // Cubic Bézier control points; equal to the endpoints for a straight line.
            public double cx1;
            public double cy1;
            public double cx2;
            public double cy2;
        }

        private Gee.ArrayList<Item> items = new Gee.ArrayList<Item>();
        private int counter = 0;
        public double margin { get; set; default = 10; }

        public static string num(double v) {
            return "%.2f".printf(v).replace(",", ".");
        }

        // Chart value text: integers without decimals, otherwise at most two
        // decimals with trailing zeros dropped (10.5, 7.25, 124.73).
        public static string format_value(double v) {
            double r = Math.round(v * 100.0) / 100.0;
            if (Math.fabs(r - Math.round(r)) < 1e-9) return "%.0f".printf(r);
            string s = "%.2f".printf(r).replace(",", ".");
            while (s.has_suffix("0")) s = s.substring(0, s.length - 1);
            if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
            return s;
        }

        // Advance width of Sans text, measured with Pango (the shaper librsvg
        // uses): a per-character estimate cut CJK and other wide glyphs off at
        // the canvas edge.
        public static double text_width(string text, double font_size, bool bold = false) {
            return GanttText.width(text, font_size, bold, "Sans");
        }

        // The most tick values a value axis may carry; d3 caps its tick list
        // the same way, so a degenerate domain cannot blow the drawing up.
        public const int MAX_TICKS = 10000;

        /**
         * The tick values of a linear axis, as d3's `ticks()` computes them:
         * the integer multiples of `step` inside [lo, hi].
         *
         * Walking the axis with `for (t = first; t <= hi; t += step)` stops
         * advancing as soon as `t / step` exceeds 2^52 — `t + step == t` in
         * double — and the caller then filled memory until it was killed.
         * Indexing by an integer tick number cannot stall, and the count is
         * bounded before the loop runs.
         */
        public static Gee.ArrayList<double?> ticks_of(double lo, double hi, double step) {
            var ticks = new Gee.ArrayList<double?>();
            double i0 = Math.ceil(lo / step - 1e-9);
            double i1 = Math.floor(hi / step + 1e-9);
            bool usable = step > 0 && i1 >= i0 && (i1 - i0) <= MAX_TICKS
                && Math.fabs(i0) <= 9e15 && Math.fabs(i1) <= 9e15;
            if (!usable) {
                // Degenerate domain (d3 answers [lo] when lo == hi): just the ends.
                ticks.add(lo);
                if (hi > lo) ticks.add(hi);
                return ticks;
            }
            for (int64 k = (int64) i0; k <= (int64) i1; k++) {
                double t = k * step;
                ticks.add(Math.fabs(t) < step * 1e-9 ? 0.0 : t);
            }
            return ticks;
        }

        // A "nice" tick step (1, 2 or 5 times a power of ten) giving about
        // `count` ticks over `range`.
        public static double nice_step(double range, int count) {
            if (range <= 0 || count <= 0) return 1.0;
            double raw = range / count;
            double mag = Math.pow(10, Math.floor(Math.log10(raw)));
            double norm = raw / mag;
            double nice = norm <= 1.0 ? 1.0 : norm <= 2.0 ? 2.0 : norm <= 5.0 ? 5.0 : 10.0;
            return nice * mag;
        }

        private static string id_attr(string? id) {
            return (id != null && id.length > 0) ? "id=\"%s\" ".printf(id) : "";
        }

        private static string suffix(string extra) {
            return extra.length > 0 ? " " + extra : "";
        }

        private string add_node(double cx, double cy, double w, double h, string attrs) {
            var it = new Item();
            it.is_line = false;
            it.name = "c%d".printf(counter++);
            it.x1 = cx;
            it.y1 = cy;
            it.w = w;
            it.h = h;
            it.attrs = attrs;
            items.add(it);
            return it.name;
        }

        /** Filled rectangle with its top-left corner at (x, y). penwidth 0 = no border. */
        public string rect(double x, double y, double w, double h, string fill, string stroke,
                         double penwidth = 1.0, string? id = null, string extra = "") {
            if (w < 0.01) w = 0.01;
            if (h < 0.01) h = 0.01;
            string pen = penwidth > 0
                ? "color=\"%s\" penwidth=%s".printf(stroke, num(penwidth))
                : "color=\"%s\" penwidth=0".printf(fill);
            return add_node(x + w / 2, y + h / 2, w, h,
                "%sshape=box style=filled fillcolor=\"%s\" %s label=\"\"%s".printf(
                    id_attr(id), fill, pen, suffix(extra)));
        }

        /** Circle centred at (cx, cy); fill "none" draws the outline only. */
        public string circle(double cx, double cy, double r, string fill, string stroke,
                           double penwidth = 1.0, string? id = null, string extra = "") {
            string style = fill == "none" ? "style=solid" : "style=filled fillcolor=\"%s\"".printf(fill);
            return add_node(cx, cy, 2 * r, 2 * r,
                "%sshape=circle %s color=\"%s\" penwidth=%s label=\"\"%s".printf(
                    id_attr(id), style, stroke, num(penwidth), suffix(extra)));
        }

        /** A node of any shape centred at (cx, cy); `attrs` gives shape, style and label. */
        public string shape(double cx, double cy, double w, double h, string attrs) {
            return add_node(cx, cy, w, h, attrs);
        }

        /**
         * Text anchored at (x, y): `align` 'l' starts at x, 'r' ends at x,
         * anything else centres on x. y is the vertical centre of the line.
         */
        public string text(double x, double y, string text, double size, string color,
                         char align = 'c', bool bold = false, string? id = null, bool italic = false) {
            if (text.length == 0) return "";
            // The box is the measured text plus a little slack; the label is
            // justified inside it, so the anchor stays exact.
            double w = text_width(text, size, bold) + 8;
            double h = size * 1.6;
            double cx = x;
            string just = "";
            if (align == 'l') {
                cx = x + w / 2;
                just = "\\l";
            } else if (align == 'r') {
                cx = x - w / 2;
                just = "\\r";
            }
            if (bold || italic) {
                // librsvg ignores a "Sans Bold" font family: use HTML markup,
                // aligned inside a fixed-size cell.
                string body = Markup.escape_text(text);
                if (italic) body = "<I>" + body + "</I>";
                if (bold) body = "<B>" + body + "</B>";
                string cell_align = align == 'l' ? "LEFT" : (align == 'r' ? "RIGHT" : "CENTER");
                return add_node(cx, y, w + 4, h + 4,
                    "%sshape=plaintext fontsize=%s fontcolor=\"%s\" label=<<TABLE BORDER=\"0\" CELLPADDING=\"0\" CELLSPACING=\"0\"><TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"%d\" ALIGN=\"%s\">%s</TD></TR></TABLE>>".printf(
                        id_attr(id), num(size), color, (int) w, (int) h, cell_align, body));
            }
            return add_node(cx, y, w, h,
                "%sshape=plaintext fontsize=%s fontcolor=\"%s\" label=\"%s%s\"".printf(
                    id_attr(id), num(size), color, RenderUtils.escape_label(text), just));
        }

        /** Straight line segment from (x1, y1) to (x2, y2). */
        public void line(double x1, double y1, double x2, double y2, string color,
                         double penwidth = 1.0, string? id = null, string extra = "") {
            bezier(x1, y1, x1, y1, x2, y2, x2, y2, color, penwidth, id, extra);
        }

        /**
         * Cubic Bézier from (x1, y1) to (x2, y2) with control points
         * (cx1, cy1) and (cx2, cy2). Graphviz honours the explicit edge `pos`
         * under layout=nop2, so the stroke follows the curve exactly.
         */
        public void bezier(double x1, double y1, double cx1, double cy1,
                           double cx2, double cy2, double x2, double y2,
                           string color, double penwidth = 1.0, string? id = null, string extra = "") {
            var it = new Item();
            it.is_line = true;
            it.name = "c%d".printf(counter++);
            it.x1 = x1;
            it.y1 = y1;
            it.x2 = x2;
            it.y2 = y2;
            it.cx1 = cx1;
            it.cy1 = cy1;
            it.cx2 = cx2;
            it.cy2 = cy2;
            it.attrs = "%scolor=\"%s\" penwidth=%s%s".printf(id_attr(id), color, num(penwidth), suffix(extra));
            items.add(it);
        }

        /** The DOT graph for everything drawn so far. */
        public string finish(string graph_name, string background) {
            double min_x = 0, min_y = 0, max_x = 0, max_y = 0;
            foreach (var it in items) {
                if (it.is_line) {
                    // The hull of the control polygon bounds the curve.
                    min_x = double.min(min_x, double.min(double.min(it.x1, it.x2), double.min(it.cx1, it.cx2)));
                    max_x = double.max(max_x, double.max(double.max(it.x1, it.x2), double.max(it.cx1, it.cx2)));
                    min_y = double.min(min_y, double.min(double.min(it.y1, it.y2), double.min(it.cy1, it.cy2)));
                    max_y = double.max(max_y, double.max(double.max(it.y1, it.y2), double.max(it.cy1, it.cy2)));
                } else {
                    min_x = double.min(min_x, it.x1 - it.w / 2);
                    max_x = double.max(max_x, it.x1 + it.w / 2);
                    min_y = double.min(min_y, it.y1 - it.h / 2);
                    max_y = double.max(max_y, it.y1 + it.h / 2);
                }
            }
            double ox = margin - min_x;
            double oy = margin - min_y;
            double width = max_x + ox + margin;
            double height = max_y + oy + margin;

            var sb = new StringBuilder();
            sb.append_printf("graph %s {\n", graph_name);
            sb.append("    layout=nop2\n");
            sb.append_printf("    bgcolor=\"%s\"\n", background);
            sb.append("    splines=line\n");
            sb.append("    node [fontname=\"Sans\" fixedsize=true margin=0]\n");
            // Corner anchors keep the margins inside the drawing.
            sb.append_printf("    a_tl [pos=\"0,%s\" shape=point style=invis width=0 height=0 label=\"\"]\n", num(height));
            sb.append_printf("    a_br [pos=\"%s,0\" shape=point style=invis width=0 height=0 label=\"\"]\n", num(width));
            foreach (var it in items) {
                if (it.is_line) {
                    string x1 = num(it.x1 + ox), y1 = num(height - (it.y1 + oy));
                    string x2 = num(it.x2 + ox), y2 = num(height - (it.y2 + oy));
                    string k1x = num(it.cx1 + ox), k1y = num(height - (it.cy1 + oy));
                    string k2x = num(it.cx2 + ox), k2y = num(height - (it.cy2 + oy));
                    sb.append_printf("    %sa [pos=\"%s,%s\" shape=point style=invis width=0 height=0 label=\"\"]\n",
                        it.name, x1, y1);
                    sb.append_printf("    %sb [pos=\"%s,%s\" shape=point style=invis width=0 height=0 label=\"\"]\n",
                        it.name, x2, y2);
                    sb.append_printf("    %sa -- %sb [%s pos=\"%s,%s %s,%s %s,%s %s,%s\"]\n",
                        it.name, it.name, it.attrs, x1, y1, k1x, k1y, k2x, k2y, x2, y2);
                } else {
                    sb.append_printf("    %s [%s pos=\"%s,%s\" width=%s height=%s]\n",
                        it.name, it.attrs, num(it.x1 + ox), num(height - (it.y1 + oy)),
                        "%.4f".printf(it.w / 72.0).replace(",", "."),
                        "%.4f".printf(it.h / 72.0).replace(",", "."));
                }
            }
            sb.append("}\n");
            return sb.str;
        }
    }

    public class MermaidXYChartRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // Plot area in points (Mermaid's default chart is 700 x 500 px).
        private const double PLOT_W = 460.0;
        private const double PLOT_H = 300.0;
        private const double TICK = 5.0;
        private const double FONT = 11.0;
        // Legend geometry, as ratios of the legend font size (Mermaid's
        // getLegendLayout) plus its padding from the plot.
        private const double LEGEND_MARKER_RATIO = 0.75;
        private const double LEGEND_ITEM_SPACING_RATIO = 0.5;
        private const double LEGEND_MARKER_SPACING_RATIO = 0.35;
        private const double LEGEND_PAD = 10.0;

        // Plots take the next colour in declaration order, bars and lines alike.
        private string[] plot_colors(Palette p) {
            return {
                p.system_fill, p.warning, p.success, p.accent_secondary, p.person_fill, p.container_fill
            };
        }

        public MermaidXYChartRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidXYChart diagram) {
            var palette = ThemeManager.get_active_palette();
            var cv = new ChartCanvas();
            string text_color = palette.node_text;
            string axis_color = palette.node_text;

            bool has_title = diagram.title != null && diagram.title.length > 0;
            double y = has_title ? 30 : 0;

            if (diagram.series.size == 0) {
                cv.text(PLOT_W / 2, y + 20, "(no data)", FONT, text_color);
                return cv.finish("xychart", palette.background);
            }

            // Value range: explicit `y-axis min --> max`, otherwise exactly the
            // data's min and max — Mermaid's setYAxisRangeFromPlotData() does
            // not pull the range towards 0, and doing so flattened a series
            // that only varies in its last digits.
            double v_min = 0.0, v_max = 0.0;
            bool first = true;
            foreach (var s in diagram.series) {
                foreach (var v in s.values) {
                    if (v == null) continue;
                    if (first) { v_min = v; v_max = v; first = false; }
                    v_min = double.min(v_min, v);
                    v_max = double.max(v_max, v);
                }
            }
            if (diagram.has_y_range) {
                v_min = diagram.y_min;
                v_max = diagram.y_max;
            }
            // A zero-width value range would divide by zero below, and at 1e17
            // even `v_min + 1` is still v_min in a double — widen it relative
            // to its own magnitude and show the single tick d3 gives a
            // degenerate domain.
            bool flat = !(v_max > v_min);
            if (flat) v_max = v_min + double.max(1.0, Math.fabs(v_min) * 1e-9);
            if (!(v_max > v_min)) { v_min = 0.0; v_max = 1.0; }   // non-finite input
            double step = ChartCanvas.nice_step(v_max - v_min, 10);

            // A band x axis fixes the categories: Mermaid slices the extra
            // values away (`data.slice(0, categories.length)`) instead of
            // inventing categories for them.
            int cat_count = 0;
            foreach (var s in diagram.series) cat_count = int.max(cat_count, s.values.size);
            if (diagram.x_labels.size > 0) cat_count = diagram.x_labels.size;
            if (cat_count == 0) cat_count = 1;

            string[] colors = plot_colors(palette);
            bool horizontal = diagram.horizontal;

            // Tick label texts along the value axis.
            var ticks = new Gee.ArrayList<double?>();
            if (flat) ticks.add(v_min);
            else ticks = ChartCanvas.ticks_of(v_min, v_max, step);

            // Category label texts along the category axis.
            string[] cats = new string[cat_count];
            for (int c = 0; c < cat_count; c++) {
                if (c < diagram.x_labels.size) cats[c] = diagram.x_labels.get(c);
                else if (diagram.has_x_range && cat_count > 1)
                    cats[c] = ChartCanvas.format_value(diagram.x_min + (diagram.x_max - diagram.x_min) * c / (cat_count - 1));
                else cats[c] = diagram.x_labels.size == 0 && !diagram.has_x_range ? "" : "%d".printf(c + 1);
            }

            double tick_label_w = 0;
            if (!horizontal) {
                foreach (var t in ticks) tick_label_w = double.max(tick_label_w, ChartCanvas.text_width(ChartCanvas.format_value(t), FONT));
            } else {
                foreach (var c in cats) tick_label_w = double.max(tick_label_w, ChartCanvas.text_width(c, FONT));
            }

            // Axis title of the left axis sits above it (Graphviz cannot rotate text).
            string left_title = horizontal ? diagram.x_axis_label : diagram.y_axis_label;
            string bottom_title = horizontal ? diagram.y_axis_label : diagram.x_axis_label;
            if (left_title.length > 0) {
                cv.text(0, y + 8, left_title, FONT, text_color, 'l', false, "xy_left_title");
                y += 22;
            }

            double px = tick_label_w + TICK + 8;   // plot left
            if (has_title) {
                cv.text(px + PLOT_W / 2, 10, diagram.title, 16, text_color, 'c', false, "xy_title");
            }
            double py = y + 8;                     // plot top
            if (horizontal) py += FONT + TICK + 6; // value axis labels on top

            // Value -> coordinate along the value axis.
            double value_len = horizontal ? PLOT_W : PLOT_H;
            double band = (horizontal ? PLOT_H : PLOT_W) / cat_count;

            // Axis lines and ticks.
            if (!horizontal) {
                cv.line(px, py, px, py + PLOT_H, axis_color, 1.5, "xy_axis_y");
                cv.line(px, py + PLOT_H, px + PLOT_W, py + PLOT_H, axis_color, 1.5, "xy_axis_x");
                for (int i = 0; i < ticks.size; i++) {
                    double t = ticks.get(i);
                    double ty = py + PLOT_H - (t - v_min) / (v_max - v_min) * value_len;
                    cv.line(px - TICK, ty, px, ty, axis_color, 1.0, "xy_ytick_%d".printf(i));
                    cv.text(px - TICK - 3, ty, ChartCanvas.format_value(t), FONT, text_color, 'r', false,
                        "xy_ytick_label_%d".printf(i));
                }
                for (int c = 0; c < cat_count; c++) {
                    double cx = px + band * (c + 0.5);
                    cv.line(cx, py + PLOT_H, cx, py + PLOT_H + TICK, axis_color, 1.0);
                    cv.text(cx, py + PLOT_H + TICK + 9, cats[c], FONT, text_color, 'c', false,
                        "xy_cat_label_%d".printf(c));
                }
            } else {
                cv.line(px, py, px, py + PLOT_H, axis_color, 1.5, "xy_axis_y");
                cv.line(px, py, px + PLOT_W, py, axis_color, 1.5, "xy_axis_x");
                for (int i = 0; i < ticks.size; i++) {
                    double t = ticks.get(i);
                    double tx = px + (t - v_min) / (v_max - v_min) * value_len;
                    cv.line(tx, py - TICK, tx, py, axis_color, 1.0, "xy_ytick_%d".printf(i));
                    cv.text(tx, py - TICK - 9, ChartCanvas.format_value(t), FONT, text_color, 'c', false,
                        "xy_ytick_label_%d".printf(i));
                }
                for (int c = 0; c < cat_count; c++) {
                    double cy = py + band * (c + 0.5);
                    cv.line(px - TICK, cy, px, cy, axis_color, 1.0);
                    cv.text(px - TICK - 3, cy, cats[c], FONT, text_color, 'r', false,
                        "xy_cat_label_%d".printf(c));
                }
            }

            // Plots, in declaration order: bars fill most of their band (several
            // bar plots overlap, as in Mermaid), lines join the band centres.
            int plot_idx = 0;
            int bar_idx = 0;
            int line_idx = 0;
            foreach (var s in diagram.series) {
                string color = colors[plot_idx % colors.length];
                if (s.series_type == XYSeriesType.BAR) {
                    for (int c = 0; c < s.values.size && c < cat_count; c++) {
                        var v = s.values.get(c);
                        if (v == null) continue;
                        double base_v = double.max(v_min, double.min(v_max, 0.0));
                        double a = (double.max(v_min, double.min(v_max, (double) v)) - v_min) / (v_max - v_min) * value_len;
                        double b = (base_v - v_min) / (v_max - v_min) * value_len;
                        double lo = double.min(a, b), len = Math.fabs(a - b);
                        double thick = band * 0.8;
                        string id = "xy_bar_%d_%d".printf(bar_idx, c);
                        if (!horizontal) {
                            cv.rect(px + band * c + (band - thick) / 2, py + PLOT_H - lo - len, thick, len,
                                color, color, 0, id);
                        } else {
                            cv.rect(px + lo, py + band * c + (band - thick) / 2, len, thick,
                                color, color, 0, id);
                        }
                    }
                    bar_idx++;
                } else {
                    double prev_x = 0, prev_y = 0;
                    bool have_prev = false;
                    for (int c = 0; c < s.values.size && c < cat_count; c++) {
                        var v = s.values.get(c);
                        if (v == null) { have_prev = false; continue; }
                        double a = (double.max(v_min, double.min(v_max, (double) v)) - v_min) / (v_max - v_min) * value_len;
                        double lx, ly;
                        if (!horizontal) {
                            lx = px + band * (c + 0.5);
                            ly = py + PLOT_H - a;
                        } else {
                            lx = px + a;
                            ly = py + band * (c + 0.5);
                        }
                        if (have_prev) {
                            cv.line(prev_x, prev_y, lx, ly, color, 2.0, "xy_line_%d_%d".printf(line_idx, c));
                        }
                        prev_x = lx;
                        prev_y = ly;
                        have_prev = true;
                    }
                    line_idx++;
                }
                plot_idx++;
            }

            if (bottom_title.length > 0) {
                double by = horizontal ? py + PLOT_H + 16 : py + PLOT_H + TICK + 30;
                cv.text(px + PLOT_W / 2, by, bottom_title, 12, text_color, 'c', false, "xy_bottom_title");
            }

            draw_legend(cv, diagram, colors, text_color, px + PLOT_W + LEGEND_PAD, py);

            return cv.finish("xychart", palette.background);
        }

        /**
         * The plot legend, to the right of the plot area and centred on it, as
         * Mermaid's ChartLegend draws it (`showLegend` is on by default): one
         * row per plot that was given a title, a bar plot marked by a filled
         * square and a line plot by a line in the plot's own colour.
         */
        private void draw_legend(ChartCanvas cv, MermaidXYChart diagram, string[] colors,
                                 string text_color, double lx, double plot_top) {
            int shown = 0;
            foreach (var s in diagram.series) {
                if (s.title != null && s.title.length > 0) shown++;
            }
            if (shown == 0) return;

            double marker = FONT * LEGEND_MARKER_RATIO;
            double marker_gap = FONT * LEGEND_MARKER_SPACING_RATIO;
            double item_gap = FONT * LEGEND_ITEM_SPACING_RATIO;
            double row_h = FONT + item_gap;
            double total_h = shown * FONT + (shown - 1) * item_gap;
            double ly = plot_top + double.max((PLOT_H - total_h) / 2, 0);

            int row = 0;
            int idx = 0;
            foreach (var s in diagram.series) {
                string color = colors[idx % colors.length];
                idx++;
                if (s.title == null || s.title.length == 0) continue;
                double my = ly + row * row_h + marker / 2;
                if (s.series_type == XYSeriesType.BAR) {
                    cv.rect(lx, my - marker / 2, marker, marker, color, color, 0,
                        "xy_legend_marker_%d".printf(row));
                } else {
                    cv.line(lx, my, lx + marker, my, color, 2.0, "xy_legend_marker_%d".printf(row));
                }
                cv.text(lx + marker + marker_gap, my, s.title, FONT, text_color, 'l', false,
                    "xy_legend_label_%d".printf(row));
                row++;
            }
        }

        public uint8[]? render_to_svg(MermaidXYChart diagram) {
            string dot_source = generate_dot(diagram);

            var graph = RenderUtils.read_dot(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout graph with engine: %s", layout_engine);
                context.free_layout(graph);
                return null;
            }

            uint8[] svg_data;
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(MermaidXYChart diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 500, 400, out width, out height);

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0, y = 0, width = width, height = height
                };
                handle.render_document(cr, viewport);

                RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(MermaidXYChart diagram, string filename) {
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(MermaidXYChart diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidXYChart diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
