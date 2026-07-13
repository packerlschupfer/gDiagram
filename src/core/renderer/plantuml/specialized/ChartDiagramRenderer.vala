/* ChartDiagramRenderer.vala — renderer for PlantUML's @startchart diagram type
 *
 * Fixed-position drawing through ChartCanvas (layout=nop2), the same base the
 * Mermaid xychart uses: Graphviz only paints, every coordinate is computed
 * here. PlantUML's own ChartRenderer works in pixels; Graphviz works in
 * points, so every PlantUML pixel size below is scaled by PX (0.75), which is
 * what makes the rendered SVG come out at PlantUML's pixel geometry.
 *
 * Measured against PlantUML 1.2026.8 the plot area is 400x300 px at 14px text,
 * grouped bars fill 80% of their category band, value labels are 10px bold
 * above the bar, and the legend sits 50px right of the plot with 12px swatches.
 *
 * Two deliberate differences, both forced by Graphviz: axis titles are not
 * rotated (the v-axis title sits above the axis instead of alongside it), and
 * an `area` series is filled with a run of narrow vertical rectangles, because
 * Graphviz cannot fill an arbitrary polygon. MermaidRadarRenderer solves the
 * same problem by injecting a <polygon> into the finished SVG, but this
 * renderer is reached through DiagramEngine's generic PlantUML path, which
 * renders generate_dot()'s output directly — so the DOT has to carry the whole
 * drawing or `-f dot` and the preview would disagree.
 *
 * Every number written into the DOT goes through ChartCanvas.num() or the
 * house "%.Nf".printf(v).replace(",", ".") idiom: a plain printf of a double
 * follows LC_NUMERIC, and a German desktop would emit "nodesep=0,8333", which
 * Graphviz rejects.
 */
namespace GDiagram {

    public class ChartDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // PlantUML pixel -> Graphviz point.
        private const double PX = 0.75;
        private const double PLOT_W = 400.0 * PX;
        private const double PLOT_H = 300.0 * PX;
        private const double FONT = 14.0 * PX;
        private const double VALUE_FONT = 10.0 * PX;
        private const double TICK = 5.0 * PX;
        private const double MARGIN = 10.0 * PX;
        private const double LEGEND_GAP = 50.0 * PX;
        private const double LEGEND_SWATCH = 12.0 * PX;
        private const double LEGEND_ROW = 34.0 * PX;
        private const double TITLE_FONT = 14.0 * PX;
        // PlantUML fills 60% of the category band with bars, measured off
        // 1.2026.9: a single series draws 60 px bars on a 100 px band, and a
        // stacked pair draws 40 px on a 66.7 px band. We used 0.8, which made
        // every bar a third too wide against the reference.
        private const double BAR_BAND_FILL = 0.6;
        private const double MARKER_R = 4.0 * PX;

        private const double AXIS_PEN = 0.5;

        // PlantUML draws axes, ticks and bar outlines in #181818 and has no
        // dark mode; gDiagram themes the drawing, so these come from the
        // active palette instead. Hard-coding PlantUML's near-black made the
        // whole axis system invisible on the dark palette.
        private string axis_color = "#181818";
        private string grid_color = "#181818";

        // The number of ticks a value axis gets when the document asks for no
        // particular spacing.
        private const int DEFAULT_TICKS = 5;

        public ChartDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        // Series take the next palette colour in declaration order unless the
        // document names one.
        private static string[] series_colors(Palette p) {
            return {
                p.system_fill, p.warning, p.success, p.accent_secondary,
                p.person_fill, p.container_fill
            };
        }

        /** A resolved value axis: the domain actually drawn, and its ticks. */
        private class Scale {
            public double lo;
            public double hi;
            public Gee.ArrayList<double?> values = new Gee.ArrayList<double?>();
            public Gee.ArrayList<string> labels = new Gee.ArrayList<string>();

            public double pos(double v, double origin, double length) {
                // Clamped: a value outside an explicit range must not be drawn
                // outside the plot area.
                double t = (double.max(lo, double.min(hi, v)) - lo) / (hi - lo);
                return origin + t * length;
            }
        }

        /**
         * The domain of a value axis: the document's explicit range, else the
         * data's own extent pulled to include zero so a bar has a baseline.
         */
        private static Scale build_scale(ChartAxisSpec ax, Gee.ArrayList<ChartSeries> members) {
            var sc = new Scale();
            bool first = true;
            double dmin = 0, dmax = 0;
            foreach (var s in members) {
                foreach (var v in s.values) {
                    if (v == null) continue;
                    if (first) { dmin = v; dmax = v; first = false; }
                    dmin = double.min(dmin, v);
                    dmax = double.max(dmax, v);
                }
            }
            if (ax.has_range) {
                sc.lo = ax.min;
                sc.hi = ax.max;
            } else if (first) {
                sc.lo = 0;
                sc.hi = 1;
            } else {
                sc.lo = double.min(0, dmin);
                sc.hi = double.max(0, dmax);
            }
            // A zero-width or inverted domain would divide by zero below.
            if (!(sc.hi > sc.lo)) {
                sc.hi = sc.lo + double.max(1.0, Math.fabs(sc.lo) * 1e-9);
            }
            if (!(sc.hi > sc.lo)) { sc.lo = 0; sc.hi = 1; }

            if (ax.has_custom_ticks()) {
                for (int i = 0; i < ax.tick_values.size; i++) {
                    sc.values.add(ax.tick_values.get(i));
                    sc.labels.add(i < ax.tick_labels.size ? ax.tick_labels.get(i) : "");
                }
            } else {
                double step = ax.has_tick_spacing && ax.tick_spacing > 0
                    ? ax.tick_spacing
                    : ChartCanvas.nice_step(sc.hi - sc.lo, DEFAULT_TICKS);
                var ts = ChartCanvas.ticks_of(sc.lo, sc.hi, step);
                foreach (var t in ts) {
                    sc.values.add(t);
                    sc.labels.add(ChartCanvas.format_value(t));
                }
            }
            return sc;
        }

        private static Gee.ArrayList<ChartSeries> axis_members(ChartDiagram d, bool secondary) {
            var list = new Gee.ArrayList<ChartSeries>();
            foreach (var s in d.series) {
                if (s.secondary_axis == secondary) list.add(s);
            }
            // A secondary axis declared with no series bound to it still needs a
            // domain; fall back to every series so its ticks are meaningful.
            if (list.size == 0 && secondary) list.add_all(d.series);
            return list;
        }

        public string generate_dot(ChartDiagram d) {
            var palette = ThemeManager.get_active_palette();
            var cv = new ChartCanvas();
            string text_color = palette.node_text;

            if (d.series.size == 0) {
                cv.text(0, MARGIN, "(no chart series defined)", FONT, text_color, 'l');
                return cv.finish("chart", palette.background);
            }

            bool horizontal = d.orientation == ChartOrientation.HORIZONTAL;
            string[] colors = series_colors(palette);
            axis_color = palette.node_border;
            grid_color = palette.grid;

            var primary = axis_members(d, false);
            var y_scale = build_scale(d.y_axis, primary);
            var y2_scale = d.has_y2 ? build_scale(d.y2_axis, axis_members(d, true)) : null;

            // How many slots the category axis has: the categories named on the
            // h-axis, else the longest series.
            int cats = d.x_axis.labels.size > 0 ? d.x_axis.labels.size : d.value_count();
            if (cats == 0) cats = 1;

            string[] cat_labels = new string[cats];
            for (int i = 0; i < cats; i++) {
                if (i < d.x_axis.labels.size) cat_labels[i] = d.x_axis.labels.get(i);
                else if (d.x_axis.has_range && cats > 1) {
                    cat_labels[i] = ChartCanvas.format_value(
                        d.x_axis.min + (d.x_axis.max - d.x_axis.min) * i / (cats - 1));
                } else cat_labels[i] = "%d".printf(i + 1);
            }

            // ---- page layout ----
            double y_label_w = 0;
            foreach (var s in y_scale.labels) {
                y_label_w = double.max(y_label_w, ChartCanvas.text_width(s, FONT));
            }
            double plot_left = MARGIN + y_label_w + TICK + 4;
            double top = MARGIN;
            if (d.title != null && d.title.length > 0) {
                top += TITLE_FONT * 1.6;
            }
            // Graphviz cannot rotate a text label, so the value-axis title goes
            // above the axis rather than alongside it.
            if (d.y_axis.title.length > 0) {
                top += FONT * 1.6;
            }
            if (d.legend == ChartLegendPosition.TOP) {
                top += LEGEND_ROW;
            }
            double plot_top = top + MARGIN;
            double plot_bottom = plot_top + PLOT_H;
            double plot_right = plot_left + PLOT_W;

            if (d.title != null && d.title.length > 0) {
                cv.text(plot_left + PLOT_W / 2, MARGIN + TITLE_FONT * 0.8, d.title,
                    TITLE_FONT, text_color, 'c', true, "chart_title");
            }
            if (d.y_axis.title.length > 0) {
                double ty = plot_top - FONT * 0.9;
                cv.text(d.y_axis.label_at_end ? plot_right : plot_left, ty, d.y_axis.title,
                    FONT, text_color, d.y_axis.label_at_end ? 'r' : 'l', false, "chart_vaxis_title");
            }

            // ---- grid, drawn first so the data sits on top ----
            if (d.y_axis.grid) {
                for (int i = 0; i < y_scale.values.size; i++) {
                    double gy = plot_bottom - (y_scale.pos(y_scale.values.get(i), 0, PLOT_H));
                    cv.line(plot_left, gy, plot_right, gy, grid_color, AXIS_PEN);
                }
            }
            double band = PLOT_W / cats;
            int cat_step = d.x_axis.has_tick_spacing && d.x_axis.tick_spacing >= 1
                ? (int) d.x_axis.tick_spacing : 1;
            if (d.x_axis.grid) {
                for (int i = 0; i < cats; i += cat_step) {
                    double gx = plot_left + band * (i + 0.5);
                    cv.line(gx, plot_top, gx, plot_bottom, grid_color, AXIS_PEN);
                }
            }

            // ---- axes ----
            cv.line(plot_left, plot_top, plot_left, plot_bottom, axis_color, AXIS_PEN, "chart_axis_v");
            cv.line(plot_left, plot_bottom, plot_right, plot_bottom, axis_color, AXIS_PEN, "chart_axis_h");

            for (int i = 0; i < y_scale.values.size; i++) {
                double ty = plot_bottom - y_scale.pos(y_scale.values.get(i), 0, PLOT_H);
                cv.line(plot_left - TICK, ty, plot_left, ty, axis_color, AXIS_PEN);
                cv.text(plot_left - TICK - 2, ty, y_scale.labels.get(i), FONT, text_color, 'r',
                    false, "chart_vtick_%d".printf(i));
            }
            for (int i = 0; i < cats; i += cat_step) {
                double cx = plot_left + band * (i + 0.5);
                cv.line(cx, plot_bottom, cx, plot_bottom + TICK, axis_color, AXIS_PEN);
                cv.text(cx, plot_bottom + TICK + FONT * 0.9, cat_labels[i], FONT, text_color, 'c',
                    false, "chart_cat_%d".printf(i));
            }

            double right_edge = plot_right;
            if (y2_scale != null) {
                cv.line(plot_right, plot_top, plot_right, plot_bottom, axis_color, AXIS_PEN,
                    "chart_axis_v2");
                double w2 = 0;
                for (int i = 0; i < y2_scale.values.size; i++) {
                    double ty = plot_bottom - y2_scale.pos(y2_scale.values.get(i), 0, PLOT_H);
                    cv.line(plot_right, ty, plot_right + TICK, ty, axis_color, AXIS_PEN);
                    cv.text(plot_right + TICK + 2, ty, y2_scale.labels.get(i), FONT, text_color, 'l',
                        false, "chart_v2tick_%d".printf(i));
                    w2 = double.max(w2, ChartCanvas.text_width(y2_scale.labels.get(i), FONT));
                }
                right_edge = plot_right + TICK + 2 + w2;
                if (d.y2_axis.title.length > 0) {
                    cv.text(right_edge, plot_top - FONT * 0.9, d.y2_axis.title, FONT, text_color,
                        'r', false, "chart_v2axis_title");
                }
            }

            // The h-axis title: centred under the axis, or past its right end
            // with `label-right`.
            if (d.x_axis.title.length > 0) {
                double bx = d.x_axis.label_at_end ? plot_right + TICK + 2 : plot_left + PLOT_W / 2;
                double by = d.x_axis.label_at_end
                    ? plot_bottom + TICK + FONT * 0.9
                    : plot_bottom + TICK + FONT * 2.4;
                cv.text(bx, by, d.x_axis.title, FONT, text_color,
                    d.x_axis.label_at_end ? 'l' : 'c', false, "chart_haxis_title");
            }

            // ---- series ----
            draw_series(cv, d, colors, text_color, plot_left, plot_top, plot_bottom, band,
                        y_scale, y2_scale, horizontal);

            // ---- annotations ----
            for (int i = 0; i < d.annotations.size; i++) {
                var a = d.annotations.get(i);
                double ax_x, ax_y;
                if (!annotation_point(d, a, cats, band, plot_left, plot_bottom, y_scale,
                                      out ax_x, out ax_y)) {
                    continue;
                }
                if (a.arrow) {
                    cv.shape(ax_x, ax_y + MARKER_R, MARKER_R * 2, MARKER_R * 2,
                        "shape=triangle style=filled fillcolor=\"%s\" color=\"%s\" penwidth=%s label=\"\"".printf(
                            axis_color, axis_color, ChartCanvas.num(AXIS_PEN)));
                }
                cv.text(ax_x, ax_y - FONT * 0.8, a.text, FONT, text_color, 'c', false,
                    "chart_annotation_%d".printf(i));
            }

            // ---- legend ----
            draw_legend(cv, d, colors, text_color, plot_left, plot_top, plot_bottom,
                        right_edge, PLOT_W);

            return cv.finish("chart", palette.background);
        }

        /**
         * Where an annotation sits. The y value is read on the primary value
         * axis. The x value is a category index (1-based) on a category axis
         * and a value on a value axis — PlantUML runs the x through an
         * autoscaled axis that stays degenerate on a category chart, pinning
         * every annotation to the left edge; the index reading is the useful one.
         */
        private static bool annotation_point(ChartDiagram d, ChartAnnotation a, int cats, double band,
                                             double plot_left, double plot_bottom, Scale y_scale,
                                             out double x, out double y) {
            x = 0;
            y = 0;
            double yv;
            if (!double.try_parse(a.y_pos, out yv)) return false;
            y = plot_bottom - y_scale.pos(yv, 0, PLOT_H);

            // A named category wins over a number, so `at ("Q3", 90)` works.
            for (int i = 0; i < d.x_axis.labels.size; i++) {
                if (d.x_axis.labels.get(i) == a.x_pos) {
                    x = plot_left + band * (i + 0.5);
                    return true;
                }
            }
            double xv;
            if (!double.try_parse(a.x_pos, out xv)) return false;
            if (d.x_axis.is_category_axis() || !d.x_axis.has_range) {
                int idx = (int) Math.round(xv) - 1;
                if (idx < 0) idx = 0;
                if (idx > cats - 1) idx = cats - 1;
                x = plot_left + band * (idx + 0.5);
            } else {
                double t = (double.max(d.x_axis.min, double.min(d.x_axis.max, xv)) - d.x_axis.min)
                    / (d.x_axis.max - d.x_axis.min);
                x = plot_left + t * PLOT_W;
            }
            return true;
        }

        private void draw_series(ChartCanvas cv, ChartDiagram d, string[] colors, string text_color,
                                 double plot_left, double plot_top, double plot_bottom, double band,
                                 Scale y_scale, Scale? y2_scale, bool horizontal) {
            int bar_count = 0;
            foreach (var s in d.series) {
                if (s.series_type == ChartSeriesType.BAR) bar_count++;
            }
            bool stacked = d.stack_mode == ChartStackMode.STACKED;
            int bar_slots = (stacked || bar_count == 0) ? 1 : bar_count;
            double group_w = band * BAR_BAND_FILL;
            double bar_w = group_w / bar_slots;

            // Running top of each category's stack, for `stackMode stacked`.
            var stack_pos = new double[d.value_count() + 1];
            var stack_neg = new double[d.value_count() + 1];

            // Paint order, as PlantUML's ChartRenderer uses it: the filled
            // areas go down first as a backdrop, then the bars, then the lines
            // and point markers on top. Drawing in declaration order instead
            // let an `area` declared after a `bar` cover the bar's foot.
            ChartSeriesType[] passes = {
                ChartSeriesType.AREA, ChartSeriesType.BAR,
                ChartSeriesType.LINE, ChartSeriesType.SCATTER
            };
            // A series keeps its declaration-order colour and bar slot whatever
            // pass draws it.
            var color_of = new string[d.series.size];
            var slot_of = new int[d.series.size];
            int next_slot = 0;
            for (int i = 0; i < d.series.size; i++) {
                var s = d.series.get(i);
                color_of[i] = s.color != null && s.color.length > 0
                    ? s.color : colors[i % colors.length];
                slot_of[i] = s.series_type == ChartSeriesType.BAR ? next_slot++ : 0;
            }

            foreach (var pass in passes) {
            for (int idx0 = 0; idx0 < d.series.size; idx0++) {
                var s = d.series.get(idx0);
                if (s.series_type != pass) continue;
                string color = color_of[idx0];
                int bar_idx = slot_of[idx0];
                int idx = idx0 + 1;
                var scale = (s.secondary_axis && y2_scale != null) ? y2_scale : y_scale;

                if (s.series_type == ChartSeriesType.BAR) {
                    for (int c = 0; c < s.values.size; c++) {
                        var v = s.values.get(c);
                        if (v == null) continue;
                        double from = 0, to = v;
                        if (stacked) {
                            if (v >= 0) {
                                from = stack_pos[c];
                                to = from + v;
                                stack_pos[c] = to;
                            } else {
                                from = stack_neg[c];
                                to = from + v;
                                stack_neg[c] = to;
                            }
                        }
                        double ya = plot_bottom - scale.pos(from, 0, PLOT_H);
                        double yb = plot_bottom - scale.pos(to, 0, PLOT_H);
                        double top_y = double.min(ya, yb);
                        double h = Math.fabs(ya - yb);
                        double bx = plot_left + band * c + (band - group_w) / 2
                            + (stacked ? 0 : bar_idx * bar_w);
                        cv.rect(bx, top_y, stacked ? group_w : bar_w, h, color, axis_color, AXIS_PEN,
                            "chart_bar_%d_%d".printf(bar_idx, c), "data_line=%d".printf(s.source_line));
                        if (s.show_labels) {
                            cv.text(bx + (stacked ? group_w : bar_w) / 2, top_y - VALUE_FONT * 0.8,
                                ChartCanvas.format_value(v), VALUE_FONT, text_color, 'c', true);
                        }
                    }
                    continue;
                }

                // line / area / scatter: one point per category centre.
                double prev_x = 0, prev_y = 0;
                bool have_prev = false;
                double base_y = plot_bottom - scale.pos(0, 0, PLOT_H);
                for (int c = 0; c < s.values.size; c++) {
                    var v = s.values.get(c);
                    if (v == null) { have_prev = false; continue; }
                    double lx = plot_left + band * (c + 0.5);
                    double ly = plot_bottom - scale.pos(v, 0, PLOT_H);

                    if (s.series_type == ChartSeriesType.SCATTER) {
                        draw_marker(cv, s.marker, lx, ly, color,
                            "chart_point_%d_%d".printf(idx - 1, c));
                    } else {
                        if (s.series_type == ChartSeriesType.AREA && have_prev) {
                            fill_area_segment(cv, prev_x, prev_y, lx, ly, base_y, color,
                                "chart_area_%d_%d".printf(idx - 1, c));
                        }
                        if (have_prev) {
                            cv.line(prev_x, prev_y, lx, ly, color, 1.5,
                                "chart_seg_%d_%d".printf(idx - 1, c));
                        }
                    }
                    if (s.show_labels) {
                        cv.text(lx, ly - VALUE_FONT * 1.2, ChartCanvas.format_value(v),
                            VALUE_FONT, text_color, 'c', true);
                    }
                    prev_x = lx;
                    prev_y = ly;
                    have_prev = true;
                }
            }
            }
        }

        private static void draw_marker(ChartCanvas cv, ChartMarkerShape shape, double x, double y,
                                        string color, string id) {
            switch (shape) {
                case ChartMarkerShape.SQUARE:
                    cv.rect(x - MARKER_R, y - MARKER_R, MARKER_R * 2, MARKER_R * 2,
                        color, color, 0, id);
                    break;
                case ChartMarkerShape.TRIANGLE:
                    cv.shape(x, y, MARKER_R * 2.4, MARKER_R * 2.4,
                        ("id=\"%s\" shape=triangle style=filled fillcolor=\"%s\" " +
                         "color=\"%s\" penwidth=0 label=\"\"").printf(id, color, color));
                    break;
                default:
                    cv.circle(x, y, MARKER_R, color, color, 0, id);
                    break;
            }
        }

        /**
         * One legend row per named series: a filled square for a bar or area, a
         * short line for a line series and the marker itself for a scatter.
         */
        private void draw_legend(ChartCanvas cv, ChartDiagram d, string[] colors, string text_color,
                                 double plot_left, double plot_top, double plot_bottom,
                                 double right_edge, double plot_w) {
            if (d.legend == ChartLegendPosition.NONE) return;
            int shown = 0;
            foreach (var s in d.series) {
                if (s.name.length > 0) shown++;
            }
            if (shown == 0) return;

            bool vertical = d.legend == ChartLegendPosition.LEFT
                || d.legend == ChartLegendPosition.RIGHT;

            double lx, ly;
            if (d.legend == ChartLegendPosition.RIGHT) {
                lx = right_edge + LEGEND_GAP;
                ly = plot_top + LEGEND_SWATCH / 2;
            } else if (d.legend == ChartLegendPosition.LEFT) {
                // Left of the whole axis block, so it cannot sit on the labels.
                lx = MARGIN;
                ly = plot_top + LEGEND_SWATCH / 2;
            } else if (d.legend == ChartLegendPosition.TOP) {
                lx = plot_left;
                ly = plot_top - PLOT_H * 0 - LEGEND_ROW;
            } else {
                lx = plot_left;
                ly = plot_bottom + TICK + FONT * 3.6;
            }

            int row = 0;
            int idx = 0;
            double x_cursor = lx;
            foreach (var s in d.series) {
                string color = s.color != null && s.color.length > 0
                    ? s.color : colors[idx % colors.length];
                idx++;
                if (s.name.length == 0) continue;

                double mx = vertical ? lx : x_cursor;
                double my = vertical ? ly + row * LEGEND_ROW : ly;

                switch (s.series_type) {
                    case ChartSeriesType.LINE:
                        cv.line(mx, my, mx + LEGEND_SWATCH, my, color, 1.5,
                            "chart_legend_marker_%d".printf(row));
                        break;
                    case ChartSeriesType.SCATTER:
                        draw_marker(cv, s.marker, mx + LEGEND_SWATCH / 2, my, color,
                            "chart_legend_marker_%d".printf(row));
                        break;
                    default:
                        cv.rect(mx, my - LEGEND_SWATCH / 2, LEGEND_SWATCH, LEGEND_SWATCH,
                            color, color, 0, "chart_legend_marker_%d".printf(row));
                        break;
                }
                cv.text(mx + LEGEND_SWATCH + 5, my, s.name, FONT, text_color, 'l', false,
                    "chart_legend_%d".printf(row));
                x_cursor = mx + LEGEND_SWATCH + 5 + ChartCanvas.text_width(s.name, FONT) + 14;
                row++;
            }
        }

        // How wide one fill strip of an `area` series is. Narrow enough that
        // the staircase is invisible at the plot's own scale, wide enough that
        // a full-width area costs a couple of hundred nodes, not thousands.
        private const double AREA_STRIP = 2.0;

        /**
         * Fills the band between one segment of an `area` series and the value
         * axis' zero line, as a run of narrow vertical rectangles: Graphviz
         * cannot fill an arbitrary polygon, and this renderer's DOT has to be
         * the whole drawing (see the file comment). Each strip is widened
         * slightly so neighbours overlap instead of leaving a hairline seam.
         */
        private static void fill_area_segment(ChartCanvas cv, double x1, double y1,
                                              double x2, double y2, double base_y,
                                              string color, string id) {
            double span = x2 - x1;
            if (span <= 0) return;
            int strips = (int) Math.ceil(span / AREA_STRIP);
            if (strips < 1) strips = 1;
            double w = span / strips;
            for (int i = 0; i < strips; i++) {
                double sx = x1 + i * w;
                // The segment's own height at the middle of this strip.
                double t = (i + 0.5) / strips;
                double sy = y1 + (y2 - y1) * t;
                double top = double.min(sy, base_y);
                double h = Math.fabs(base_y - sy);
                if (h < 0.01) continue;
                cv.rect(sx, top, w + 0.3, h, color, color, 0,
                    i == 0 ? id : null);
            }
        }

        public uint8[]? render_to_svg(ChartDiagram diagram) {
            string dot_source = generate_dot(diagram);

            var graph = RenderUtils.read_dot(dot_source);
            if (graph == null) {
                warning("Failed to parse chart DOT graph");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout chart with engine: %s", layout_engine);
                context.free_layout(graph);
                return null;
            }

            uint8[] svg_data;
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render chart graph");
                return null;
            }
            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(ChartDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null,
                    Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 500, 400, out width, out height);

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
                var cr = new Cairo.Context(surface);
                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
                handle.render_document(cr, viewport);

                RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render chart SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(ChartDiagram diagram, string filename) {
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(ChartDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(ChartDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
