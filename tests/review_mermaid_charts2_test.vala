namespace GDiagram.Tests {
    /**
     * Second round of Mermaid chart fidelity checks against Mermaid CLI 11.17,
     * for the layouts that were still Graphviz-shaped after the first round:
     * the sankey band layout (a port of d3-sankey 0.12.3), the radar's smooth
     * closed curve, Mermaid's handling of a pie slice that rounds to 0%, the
     * timeline's per-event boxes, the mindmap's root-centred tree and its
     * ::icon() decoration, and the UTC date fallback of a gantt with no
     * dateFormat.
     *
     * Everything is asserted on the drawn geometry — positions, widths and
     * control points — not on the presence of a string.
     */
    public class ReviewMermaidCharts2Tests {

        private static Gee.ArrayList<ElementRegion> regions() {
            return new Gee.ArrayList<ElementRegion>();
        }

        private static bool near(double a, double b, double tol = 0.6) {
            return Math.fabs(a - b) <= tol;
        }

        private class Geo {
            public double x;
            public double y;
            public double w;   // points
            public double h;   // points
        }

        private static string? line_with_id(string dot, string id) {
            foreach (string line in dot.split("\n")) {
                if (line.contains("id=\"%s\"".printf(id))) return line;
            }
            return null;
        }

        private static string attr(string line, string name) {
            var re = /(?:^|\s|\[)([a-z]+)=("[^"]*"|[^\s\]]+)/;
            MatchInfo m;
            int start = 0;
            try {
                while (re.match_full(line, -1, start, 0, out m)) {
                    if (m.fetch(1) == name) {
                        string v = m.fetch(2);
                        if (v.has_prefix("\"")) v = v.substring(1, v.length - 2);
                        return v;
                    }
                    int s, e;
                    m.fetch_pos(0, out s, out e);
                    start = e;
                }
            } catch (RegexError err) {
                error("%s", err.message);
            }
            return "";
        }

        // Centre and size of the element drawn with id="<id>", in points.
        private static Geo node(string dot, string id) {
            string? line = line_with_id(dot, id);
            if (line == null) error("no element %s", id);
            var g = new Geo();
            string[] xy = attr(line, "pos").split(",");
            g.x = double.parse(xy[0]);
            g.y = double.parse(xy[1]);
            g.w = double.parse(attr(line, "width")) * 72.0;
            g.h = double.parse(attr(line, "height")) * 72.0;
            return g;
        }

        // The four control points of the edge drawn with id="<id>".
        private static double[] edge_points(string dot, string id) {
            string? line = line_with_id(dot, id);
            if (line == null) error("no edge %s", id);
            string pos = attr(line, "pos");
            var vals = new double[8];
            string[] pts = pos.split(" ");
            if (pts.length != 4) error("edge %s has %d points", id, pts.length);
            for (int i = 0; i < 4; i++) {
                string[] xy = pts[i].split(",");
                vals[2 * i] = double.parse(xy[0]);
                vals[2 * i + 1] = double.parse(xy[1]);
            }
            return vals;
        }

        private static string svg_of(uint8[]? data) {
            assert(data != null);
            var sb = new StringBuilder.sized(data.length + 1);
            sb.append_len((string) data, data.length);
            return sb.str;
        }

        // ==================== Sankey ====================

        private const string FLOW = """sankey-beta
Electricity,Residential,120.5
Electricity,Commercial,45.2
Residential,Heating,80
Residential,Cooling,20.5
Residential,Other,20
Commercial,Operations,45.2
""";

        private static string sankey_dot(string src) {
            var d = new MermaidSankeyParser().parse(src);
            return new MermaidSankeyRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        /**
         * S1: nodes are thin vertical bars, one column per depth, sized by
         * value — not a Graphviz node layout. d3-sankey puts the columns
         * (600 - nodeWidth) / (columns - 1) = 295 pt apart and every bar is
         * nodeWidth = 10 pt wide.
         */
        public static void test_sankey_bars_in_depth_columns() {
            string dot = sankey_dot(FLOW);
            // get_nodes() order: Electricity, Residential, Commercial,
            // Heating, Cooling, Other, Operations.
            var electricity = node(dot, "sankey_node_0");
            var residential = node(dot, "sankey_node_1");
            var commercial = node(dot, "sankey_node_2");
            var heating = node(dot, "sankey_node_3");

            assert(near(electricity.w, 10, 0.05));
            assert(near(residential.w, 10, 0.05));
            // Three depth columns, evenly spaced.
            assert(near(residential.x - electricity.x, 295, 0.5));
            assert(near(heating.x - residential.x, 295, 0.5));
            // Nodes of the same depth share a column.
            assert(near(commercial.x, residential.x, 0.05));

            // Bar heights follow the node totals (165.7, 120.5, 45.2, 80).
            assert(near(electricity.h / residential.h, 165.7 / 120.5, 0.02));
            assert(near(residential.h / commercial.h, 120.5 / 45.2, 0.02));
            assert(near(residential.h / heating.h, 120.5 / 80.0, 0.02));
        }

        /**
         * S2: link thickness is proportional to the link value, and the same
         * scale applies across the whole diagram (both columns).
         */
        public static void test_sankey_ribbon_widths_follow_values() {
            string dot = sankey_dot(FLOW);
            double[] w = new double[6];
            for (int i = 0; i < 6; i++) {
                string? line = line_with_id(dot, "sankey_link_%d".printf(i));
                assert(line != null);
                w[i] = double.parse(attr(line, "penwidth"));
                assert(w[i] > 1);
            }
            // 120.5 / 45.2, 80 / 20.5, and across columns 120.5 / 80.
            assert(near(w[0] / w[1], 120.5 / 45.2, 0.01));
            assert(near(w[2] / w[3], 80.0 / 20.5, 0.01));
            assert(near(w[0] / w[2], 120.5 / 80.0, 0.01));
        }

        /**
         * S3: ribbons are d3's horizontal bump curve — a cubic with both
         * control points on the vertical midline between the two bars — and
         * they are stroked with a source-to-target gradient at half opacity.
         */
        public static void test_sankey_ribbons_are_curved_gradients() {
            var d = new MermaidSankeyParser().parse(FLOW);
            // The renderer keeps the context unowned: hold it here.
            var ctx = new Gvc.Context();
            var r = new MermaidSankeyRenderer(ctx, regions(), "dot");
            string dot = r.generate_dot(d);
            double[] p = edge_points(dot, "sankey_link_0");
            double mid = (p[0] + p[6]) / 2;
            assert(near(p[2], mid, 0.05) && near(p[4], mid, 0.05));
            assert(near(p[3], p[1], 0.05) && near(p[5], p[7], 0.05));
            // A real curve: the ends sit at different heights.
            assert(Math.fabs(p[1] - p[7]) > 1);

            string svg = svg_of(r.render_to_svg(d));
            assert(svg.contains("<linearGradient id=\"sankeyGrad0\""));
            assert(svg.contains("stroke=\"url(#sankeyGrad0)\""));
            assert(svg.contains("stroke-opacity=\"0.5\""));
            // The stroke width in the SVG is the link width, not a hairline.
            MatchInfo m;
            try {
                var re = new Regex("stroke=\"url\\(#sankeyGrad0\\)\" stroke-width=\"([0-9.]+)\"");
                assert(re.match(svg, 0, out m));
                assert(double.parse(m.fetch(1)) > 20);
            } catch (RegexError e) {
                error("%s", e.message);
            }
        }

        // ==================== Radar ====================

        private static string radar_dot(string src) {
            var d = new MermaidRadarParser().parse(src);
            return new MermaidRadarRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        private const string RADAR = "radar-beta\n axis A, B, C, D\n curve a{1, 4, 2, 3}\n";

        /**
         * R1: with the default circle graticule Mermaid draws the curve with
         * closedRoundCurve(points, curveTension = 0.17): each segment's control
         * points are offset from its endpoints by 0.17 times the vector between
         * the neighbouring vertices.
         */
        public static void test_radar_curve_is_smooth() {
            string dot = radar_dot(RADAR);
            int n = 4;
            var xs = new double[n];
            var ys = new double[n];
            for (int i = 0; i < n; i++) {
                var pt = node(dot, "radar_curve_0_pt_%d".printf(i));
                xs[i] = pt.x;
                ys[i] = pt.y;
            }
            for (int i = 0; i < n; i++) {
                double[] p = edge_points(dot, "radar_curve_0_%d".printf(i));
                int i0 = (i - 1 + n) % n, i2 = (i + 1) % n, i3 = (i + 2) % n;
                double c1x = xs[i] + (xs[i2] - xs[i0]) * 0.17;
                double c1y = ys[i] + (ys[i2] - ys[i0]) * 0.17;
                double c2x = xs[i2] - (xs[i3] - xs[i]) * 0.17;
                double c2y = ys[i2] - (ys[i3] - ys[i]) * 0.17;
                assert(near(p[0], xs[i], 0.05) && near(p[6], xs[i2], 0.05));
                assert(near(p[2], c1x, 0.05) && near(p[3], c1y, 0.05));
                assert(near(p[4], c2x, 0.05) && near(p[5], c2y, 0.05));
                // Not the straight segment it used to be.
                assert(Math.fabs(p[2] - p[0]) + Math.fabs(p[3] - p[1]) > 1);
            }
        }

        /**
         * R2: with `graticule polygon` Mermaid draws a plain <polygon>, so the
         * segments stay straight and the translucent fill stays a polygon.
         */
        public static void test_radar_polygon_graticule_stays_straight() {
            string src = "radar-beta\n graticule polygon\n axis A, B, C, D\n curve a{1, 4, 2, 3}\n";
            string dot = radar_dot(src);
            for (int i = 0; i < 4; i++) {
                double[] p = edge_points(dot, "radar_curve_0_%d".printf(i));
                assert(near(p[2], p[0], 0.01) && near(p[3], p[1], 0.01));
                assert(near(p[4], p[6], 0.01) && near(p[5], p[7], 0.01));
            }
            var d = new MermaidRadarParser().parse(src);
            string svg = svg_of(new MermaidRadarRenderer(new Gvc.Context(), regions(), "dot").render_to_svg(d));
            assert(svg.contains("<polygon class=\"radar-fill\""));
            assert(!svg.contains("<path class=\"radar-fill\""));

            var circle = new MermaidRadarParser().parse(RADAR);
            string csvg = svg_of(new MermaidRadarRenderer(new Gvc.Context(), regions(), "dot").render_to_svg(circle));
            assert(csvg.contains("<path class=\"radar-fill\""));
            assert(csvg.contains("Z\"/>"));
        }

        // ==================== Pie ====================

        private static string pie_dot(string src) {
            var d = new MermaidPieParser().parse(src);
            return new MermaidPieRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        /**
         * P1: Mermaid filters out arcs whose share rounds to "0%" — neither the
         * wedge nor the label is drawn — but the slice keeps its angular space
         * and stays in the legend.
         */
        public static void test_pie_zero_percent_slice_is_dropped() {
            string dot = pie_dot("pie title T\n  \"Big\" : 500\n  \"Medium\" : 300\n  \"Sliver\" : 1\n  \"Rest\" : 200\n");
            // No label for the 0.1% slice, labels for the other three.
            assert(line_with_id(dot, "pie_pct_0") != null);
            assert(line_with_id(dot, "pie_pct_1") != null);
            assert(line_with_id(dot, "pie_pct_2") == null);
            assert(line_with_id(dot, "pie_pct_3") != null);
            // All four still have a legend entry.
            for (int i = 0; i < 4; i++) assert(line_with_id(dot, "pie_legend_box_%d".printf(i)) != null);

            // Its wedge is painted in the background colour, so the pie shows a
            // gap there rather than a coloured sliver.
            string? wedge = line_with_id(dot, "pie");
            assert(wedge != null);
            string fill = attr(wedge, "fillcolor");
            string bg = ThemeManager.get_active_palette().background;
            assert(fill.contains(bg + ";"));

            // The remaining slices keep the angles they would have had: "Rest"
            // starts after 0.4995 + 0.2997 + 0.000999 turns, so its label sits
            // at 0.9001 turns clockwise from 12 o'clock.
            var centre = node(dot, "pie");
            var rest = node(dot, "pie_pct_3");
            double ang = 2 * Math.PI * 0.90010;
            // Canvas y grows down, Graphviz y grows up, so the y offset flips.
            assert(near(rest.x - centre.x, 0.75 * 150.0 * Math.sin(ang), 1.0));
            assert(near(rest.y - centre.y, 0.75 * 150.0 * Math.cos(ang), 1.0));
        }

        // ==================== Timeline ====================

        private const string MULTI = """timeline
    title System Development History
    Early 2023 : Research phase
               : Team formation
    Late 2023  : Prototype V1 : Feedback session
    2024       : Production MVP
               : First 100 users
""";

        private static string timeline_dot(string src) {
            var d = new MermaidTimelineParser().parse(src);
            return new MermaidTimelineRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        /**
         * T1: every period gets its own box and every event a separate box
         * below it, laid out identically in each column — Mermaid's timeline.
         * The HTML-table version drew the inner boxes only for the periods
         * whose section fill and stroke colours happened to differ.
         */
        public static void test_timeline_every_period_has_event_boxes() {
            string dot = timeline_dot(MULTI);
            var p0 = node(dot, "period_0");
            var p1 = node(dot, "period_1");
            var p2 = node(dot, "period_2");
            // One 200 pt column per period, all period boxes the same size.
            assert(near(p1.x - p0.x, 200, 0.5) && near(p2.x - p1.x, 200, 0.5));
            assert(near(p0.y, p1.y, 0.05) && near(p1.y, p2.y, 0.05));
            assert(near(p0.w, 190, 0.5) && near(p0.h, p2.h, 0.05));

            for (int i = 0; i < 3; i++) {
                var e0 = node(dot, "event_%d_0".printf(i));
                var e1 = node(dot, "event_%d_1".printf(i));
                var p = node(dot, "period_%d".printf(i));
                // Same column, stacked below the period (Graphviz y grows up).
                assert(near(e0.x, p.x, 0.05) && near(e1.x, p.x, 0.05));
                assert(e0.y < p.y && e1.y < e0.y);
                // Separate boxes: a 10 pt gap, not one merged block.
                assert(near((e0.y - e0.h / 2) - (e1.y + e1.h / 2), 10, 0.5));
                assert(near(e0.w, 190, 0.5));
            }
            // Identical geometry in every column: that is what was uneven.
            var a = node(dot, "event_0_0");
            var b = node(dot, "event_1_0");
            var c = node(dot, "event_2_0");
            assert(near(a.y, b.y, 0.05) && near(b.y, c.y, 0.05));
            assert(near(a.h, b.h, 0.05) && near(b.h, c.h, 0.05));
        }

        /**
         * T2: a section band spans 200 * periods - 50 over the columns it
         * covers, and sits above the period row.
         */
        public static void test_timeline_section_bands() {
            string dot = timeline_dot("timeline\n  section First\n    1990 : A\n    1993 : B\n  section Second\n    2001 : C\n");
            var s0 = node(dot, "section_0");
            var s1 = node(dot, "section_1");
            assert(near(s0.w, 350, 0.5));
            assert(near(s1.w, 150, 0.5));
            assert(near(s1.x - s0.x, 300, 0.5));   // 2 columns on, centres differ
            var p0 = node(dot, "period_0");
            assert(s0.y > p0.y);                   // above the periods
        }

        // ==================== Mindmap ====================

        private static string mindmap_dot(string src) {
            var d = new MermaidMindmapParser().parse(src);
            return new MermaidMindmapRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        // Mindmap nodes are named n_<source line>_<depth>, not id="".
        private static Geo mm_node(string dot, string name) {
            foreach (string line in dot.split("\n")) {
                if (!line.strip().has_prefix(name + " [")) continue;
                var g = new Geo();
                string[] xy = attr(line, "pos").split(",");
                g.x = double.parse(xy[0]);
                g.y = double.parse(xy[1]);
                return g;
            }
            error("no mindmap node %s", name);
        }

        /**
         * M1: the root is centred with its top-level branches alternating to
         * the right and to the left, each subtree growing outwards — the shape
         * cose-bilkent settles into, instead of Graphviz's radial twopi.
         */
        public static void test_mindmap_root_centred_branches_both_sides() {
            string dot = mindmap_dot("""mindmap
  root((Central Topic))
    Branch One
      Leaf A
      Leaf B
    Branch Two
      Leaf C
      Leaf D
    Branch Three
      Leaf E
""");
            assert(dot.contains("layout=nop2"));
            var root = mm_node(dot, "n_2_0");
            var b1 = mm_node(dot, "n_3_1");
            var b2 = mm_node(dot, "n_6_1");
            var b3 = mm_node(dot, "n_9_1");
            // Alternating sides.
            assert(b1.x > root.x && b3.x > root.x);
            assert(b2.x < root.x);
            // Children grow away from the root on their branch's side.
            assert(mm_node(dot, "n_4_2").x > b1.x);
            assert(mm_node(dot, "n_5_2").x > b1.x);
            assert(mm_node(dot, "n_7_2").x < b2.x);
            assert(mm_node(dot, "n_8_2").x < b2.x);
            // Siblings are stacked, not on top of each other.
            assert(Math.fabs(mm_node(dot, "n_4_2").y - mm_node(dot, "n_5_2").y) > 10);
            // The root sits at the vertical centre of the drawing.
            double min_y = double.MAX, max_y = -double.MAX;
            string[] all = { "n_2_0", "n_3_1", "n_4_2", "n_5_2", "n_6_1", "n_7_2", "n_8_2", "n_9_1", "n_10_2" };
            foreach (string name in all) {
                var g = mm_node(dot, name);
                min_y = double.min(min_y, g.y);
                max_y = double.max(max_y, g.y);
            }
            assert(near(root.y, (min_y + max_y) / 2, 6));
            // Compact: the two sides span three levels, not a wide radial fan.
            assert(max_y - min_y < 400);
        }

        /**
         * M2: `::icon(fa fa-book)` names a glyph from an icon font we do not
         * bundle, so the icon's own short name is drawn instead — small,
         * italic and on its own line above the label.
         */
        public static void test_mindmap_icon_is_drawn() {
            string dot = mindmap_dot("mindmap\n  root((Docs))\n    Reading\n    ::icon(fa fa-book)\n    Writing\n    ::icon(mdi mdi-pencil-outline)\n");
            assert(dot.contains("<FONT POINT-SIZE=\"8\"><I>book</I></FONT><BR/>"));
            assert(dot.contains("<FONT POINT-SIZE=\"8\"><I>pencil-outline</I></FONT><BR/>"));
            // A node without an icon keeps a plain label.
            string plain = mindmap_dot("mindmap\n  root((Docs))\n    Reading\n");
            assert(!plain.contains("POINT-SIZE=\"8\""));
        }

        /**
         * An unmatched markdown marker stays literal text.
         *
         * `["`Rating 5*`"]` used to close out as `<I></I>`, which Graphviz's
         * HTML-label parser rejects — it printed "syntax error in line 1" and
         * dropped the whole label, leaving an empty box.
         */
        public static void test_mindmap_unmatched_markdown_marker_stays_literal() {
            string dot = mindmap_dot("mindmap\n  root((Root))\n    A[\"`Rating 5*`\"]\n");
            assert(!dot.contains("<I></I>") && !dot.contains("<B></B>"));
            assert(dot.contains("Rating 5*"));

            // A matched pair still becomes a tag, and the markers themselves
            // are not shown.
            string paired = mindmap_dot("mindmap\n  root((Root))\n    B[\"`a *b* **c**`\"]\n");
            assert(paired.contains("<I>b</I>") && paired.contains("<B>c</B>"));
            assert(!paired.contains("*b*") && !paired.contains("**c**"));

            // `_` behaves the same way.
            string under = mindmap_dot("mindmap\n  root((Root))\n    C[\"`snake_case`\"]\n");
            assert(!under.contains("<I></I>"));
            assert(under.contains("snake_case"));
        }

        // ==================== Gantt overflow / vert ====================

        /**
         * A timestamp past year 9999 is clamped instead of producing a NULL
         * DateTime: `DateTime.from_unix_utc` and add_days/add_months/add_years
         * all answer null out there, and the unchecked getters then logged six
         * GLib criticals per call and returned 0, inverting the time scale.
         */
        public static void test_gantt_date_overflow_is_clamped() {
            // A JS millisecond timestamp handed to `dateFormat X` (seconds).
            int64 ms;
            assert(MermaidGanttTime.parse_start("1735689600000", "X", out ms));
            assert(MermaidGanttTime.is_representable(ms));
            int y, mo, d, h, mi, s, l;
            MermaidGanttTime.parts(ms, out y, out mo, out d, out h, out mi, out s, out l);
            assert(y == 9999);                       // not 1970 from a null DateTime

            // Overflowing durations keep the instant instead of collapsing it.
            int64 base_ms = MermaidGanttTime.make(2024, 1, 1);
            assert(MermaidGanttTime.add(base_ms, 999999999, "d") == base_ms);
            assert(MermaidGanttTime.add(base_ms, 999999999, "M") == base_ms);
            assert(MermaidGanttTime.add(base_ms, 999999999, "y") == base_ms);
            // A duration that does fit still applies.
            assert(MermaidGanttTime.add(base_ms, 3, "d") == MermaidGanttTime.make(2024, 1, 4));

            // The chart still gets an axis: the domain is ordered and the tick
            // list is non-empty.
            var diagram = new MermaidGanttParser().parse(
                "gantt\n    dateFormat X\n    section S\n    A :a, 1735689600000, 3600\n");
            var layout = new MermaidGanttLayout(diagram, ThemeManager.get_active_palette());
            string svg = layout.build();
            assert(layout.ticks().size > 0);
            assert(svg.contains("<text"));
        }

        /**
         * The `vert` marker spans every ordinary task, as Mermaid's
         * `tasksWithoutVert.length` does — `compact` collapses the row count,
         * which used to leave the marker a fraction of the chart's height.
         */
        public static void test_gantt_vert_marker_spans_all_tasks() {
            string src = """---
displayMode: compact
---
gantt
    dateFormat YYYY-MM-DD
    axisFormat %%d
    section S
    A : a1, 2024-01-01, 1d
    B : a2, 2024-01-03, 1d
    C : a3, 2024-01-05, 1d
    Marker : vert, m1, 2024-01-02, 0d
""";
            var diagram = new MermaidGanttParser().parse(src);
            assert(diagram.compact);
            var layout = new MermaidGanttLayout(diagram, ThemeManager.get_active_palette());
            string svg = layout.build();
            double h = vert_rect_height(svg);
            // Three non-vert tasks share one compact row, so a row-count-based
            // height would be 1 * (barHeight + barGap) + 2 * barHeight.
            assert(h > 3 * 20.0);
            assert(near(h, 3 * (20.0 + 4.0) + 2 * 20.0, 1.0));
        }

        // Height of the thin `vert` rect (width 0.08 * barHeight = 1.6).
        private static double vert_rect_height(string svg) {
            foreach (string line in svg.split("\n")) {
                if (!line.has_prefix("<rect") || !line.contains("width=\"1.6\"")) continue;
                int i = line.index_of("height=\"");
                assert(i > 0);
                string rest = line.substring(i + 8);
                return double.parse(rest.substring(0, rest.index_of("\"")));
            }
            error("no vert marker rect in %s", svg);
        }

        // d3's `_` pad modifier means "pad with spaces"; it was compared to a
        // literal ' ' and so silently degraded to no padding at all.
        public static void test_gantt_d3_space_pad_modifier() {
            int64 ms = MermaidGanttTime.make(2024, 1, 5, 9, 7, 3);
            assert(MermaidGanttTime.format_d3(ms, "%_d") == " 5");
            assert(MermaidGanttTime.format_d3(ms, "%_m") == " 1");
            assert(MermaidGanttTime.format_d3(ms, "%_H") == " 9");
            // The other two modifiers are unchanged.
            assert(MermaidGanttTime.format_d3(ms, "%-d") == "5");
            assert(MermaidGanttTime.format_d3(ms, "%0d") == "05");
            assert(MermaidGanttTime.format_d3(ms, "%d") == "05");
        }

        // ==================== Gitgraph ====================

        /**
         * Mermaid resolves a commit's symbol with `customType ?? type`, so an
         * explicit `type:` on a merge wins: `merge x type: NORMAL` draws a
         * plain filled circle, not the merge donut (a second, background-
         * coloured circle punched into the first).
         */
        public static void test_gitgraph_merge_type_normal_draws_plain_commit() {
            string src = "gitGraph\n   commit\n   branch develop\n   commit\n   checkout main\n   merge develop";
            string donut = gitgraph_svg(src);
            string normal = gitgraph_svg(src + " type: NORMAL");
            // A plain merge keeps its donut: an inner, background-coloured
            // circle on top of the commit circle. NORMAL has none, so the SVG
            // holds exactly one circle fewer.
            assert(count_circles(donut) == count_circles(normal) + 1);
            assert(count_circles(normal) == 3);   // one per commit, nothing else
            // A REVERSE merge still overrides with its own cross marks.
            string reverse = gitgraph_svg(src + " type: REVERSE");
            assert(count_circles(reverse) == 3 && reverse.index_of("<line") >= 0);
        }

        private static string gitgraph_svg(string src) {
            var d = new MermaidGitGraphParser().parse(src);
            var renderer = new MermaidGitGraphRenderer(new Gvc.Context(), regions(), "dot");
            uint8[]? data = renderer.render_to_svg(d);
            assert(data != null);
            return (string) data;
        }

        private static int count_circles(string svg) {
            int n = 0, i = 0;
            while ((i = svg.index_of("<circle", i)) >= 0) { n++; i += 7; }
            return n;
        }

        // ==================== Click regions ====================

        private static ElementRegion? find_region(Gee.ArrayList<ElementRegion> rs, string name) {
            foreach (var r in rs) if (r.name == name) return r;
            return null;
        }

        /**
         * C1: the GUI path (render_to_surface) still maps the pinned sankey and
         * timeline boxes back to named, non-empty click regions carrying their
         * source line — the layouts moved to ChartCanvas node names, so the
         * regions are now supplied through region_names.
         */
        public static void test_pinned_layouts_keep_click_regions() {
            var sctx = new Gvc.Context();
            var sr = regions();
            var sd = new MermaidSankeyParser().parse(FLOW);
            assert(new MermaidSankeyRenderer(sctx, sr, "dot").render_to_surface(sd) != null);
            var electricity = find_region(sr, "Electricity");
            var heating = find_region(sr, "Heating");
            assert(electricity != null && heating != null);
            assert(electricity.width > 0 && electricity.height > 0);
            assert(electricity.source_line == 2 && heating.source_line == 4);
            assert(heating.x > electricity.x);

            var tctx = new Gvc.Context();
            var tr = regions();
            var td = new MermaidTimelineParser().parse(MULTI);
            assert(new MermaidTimelineRenderer(tctx, tr, "dot").render_to_surface(td) != null);
            for (int i = 0; i < 3; i++) {
                var p = find_region(tr, "period_%d".printf(i));
                var e = find_region(tr, "event_%d_0".printf(i));
                assert(p != null && e != null);
                assert(p.width > 0 && p.height > 0 && e.width > 0 && e.height > 0);
                assert(p.source_line > 0 && e.source_line > 0);
                assert(e.y > p.y);   // surface coordinates grow downwards
            }
        }

        // ==================== Gantt dates ====================

        // tests/meson.build pins TZ=Europe/Vienna for this suite: +01:00 in
        // January. Spelling the offset out keeps the assertions below from
        // collapsing into `x == x` the way they did under CI's UTC.
        private const int64 VIENNA_JAN_OFFSET = 3600000;

        private static int64 local_offset_ms(int64 utc_ms) {
            var instant = new DateTime.from_unix_utc(utc_ms / 1000);
            return instant.to_local().get_utc_offset() / 1000;
        }

        // Guards the pin itself: without it every offset below is zero.
        private static void assert_tz_pinned() {
            int64 jan = MermaidGanttTime.make(2024, 1, 1);
            if (local_offset_ms(jan) != VIENNA_JAN_OFFSET) {
                error("this suite needs TZ=Europe/Vienna (offset was %" + int64.FORMAT + " ms)",
                      local_offset_ms(jan));
            }
        }

        /**
         * G1: with no usable dateFormat Mermaid falls back to `new Date(str)`,
         * where an ISO date-only string is UTC while everything the legacy
         * parser handles is local. Every other date here is a wall-clock time,
         * so the UTC forms have to be shifted by the local offset.
         */
        public static void test_gantt_no_date_format_parses_as_utc() {
            assert_tz_pinned();
            int64 wall = MermaidGanttTime.make(2024, 1, 1);
            int64 off = VIENNA_JAN_OFFSET;

            int64 strict;
            assert(MermaidGanttTime.parse_start("2024-01-01", "YYYY-MM-DD", out strict));
            assert(strict == wall);

            int64 fallback;
            assert(MermaidGanttTime.parse_start("2024-01-01", "", out fallback));
            assert(fallback == wall + off);
            assert(fallback != strict);          // the shift is real, not 0

            // Not ISO: the legacy Date parser reads these as local time.
            int64 slashes;
            assert(MermaidGanttTime.parse_start("2024/01/01", "", out slashes));
            assert(slashes == wall);
            int64 loose;
            assert(MermaidGanttTime.parse_start("2024-1-1", "", out loose));
            assert(loose == wall);

            // An ISO date-time without an offset is local; with Z it is UTC.
            int64 local_dt;
            assert(MermaidGanttTime.parse_start("2024-01-01T06:00", "", out local_dt));
            assert(local_dt == MermaidGanttTime.make(2024, 1, 1, 6));
            int64 zulu;
            assert(MermaidGanttTime.parse_start("2024-01-01T06:00:00Z", "", out zulu));
            assert(zulu == MermaidGanttTime.make(2024, 1, 1, 6) + off);
            assert(zulu != local_dt);

            // Summer is +02:00 there, so the shift tracks DST rather than
            // being one fixed number.
            int64 jul_wall = MermaidGanttTime.make(2024, 7, 1);
            int64 jul;
            assert(MermaidGanttTime.parse_start("2024-07-01", "", out jul));
            assert(jul == jul_wall + 2 * VIENNA_JAN_OFFSET);
        }

        /**
         * G2: the shift reaches the scheduled chart — a task dated 2024-01-01
         * with no dateFormat starts one local-offset later than the same task
         * with `dateFormat YYYY-MM-DD`, exactly as Mermaid renders it.
         */
        public static void test_gantt_no_date_format_shifts_the_chart() {
            assert_tz_pinned();
            var plain = new MermaidGanttParser().parse(
                "gantt\n  section S\n  A : a1, 2024-01-01, 3d\n  B : a2, after a1, 2d\n");
            var fmt = new MermaidGanttParser().parse(
                "gantt\n  dateFormat YYYY-MM-DD\n  section S\n  A : a1, 2024-01-01, 3d\n  B : a2, after a1, 2d\n");
            var pa = plain.find_task("a1");
            var fa = fmt.find_task("a1");
            assert(pa != null && fa != null);
            // Absolute, not relative to a value computed the same way the code
            // under test computes it: 2024-01-01 00:00 UTC is 01:00 in Vienna.
            assert(fa.start_ms == MermaidGanttTime.make(2024, 1, 1));
            assert(pa.start_ms == MermaidGanttTime.make(2024, 1, 1, 1));
            assert(pa.start_ms - fa.start_ms == VIENNA_JAN_OFFSET);
            // The dependent task moves with it, and keeps its 2-day length.
            var pb = plain.find_task("a2");
            var fb = fmt.find_task("a2");
            assert(pb != null && fb != null);
            assert(fb.start_ms == MermaidGanttTime.make(2024, 1, 4));
            assert(pb.start_ms == MermaidGanttTime.make(2024, 1, 4, 1));
            assert(pb.end_ms == MermaidGanttTime.make(2024, 1, 6, 1));
            assert(fb.end_ms - fb.start_ms == 2 * 86400000);
        }
    }
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/charts2/sankey-bars-in-depth-columns", GDiagram.Tests.ReviewMermaidCharts2Tests.test_sankey_bars_in_depth_columns);
    Test.add_func("/charts2/sankey-ribbon-widths", GDiagram.Tests.ReviewMermaidCharts2Tests.test_sankey_ribbon_widths_follow_values);
    Test.add_func("/charts2/sankey-ribbon-curves", GDiagram.Tests.ReviewMermaidCharts2Tests.test_sankey_ribbons_are_curved_gradients);
    Test.add_func("/charts2/radar-curve-smooth", GDiagram.Tests.ReviewMermaidCharts2Tests.test_radar_curve_is_smooth);
    Test.add_func("/charts2/radar-polygon-graticule", GDiagram.Tests.ReviewMermaidCharts2Tests.test_radar_polygon_graticule_stays_straight);
    Test.add_func("/charts2/pie-zero-percent-slice", GDiagram.Tests.ReviewMermaidCharts2Tests.test_pie_zero_percent_slice_is_dropped);
    Test.add_func("/charts2/timeline-event-boxes", GDiagram.Tests.ReviewMermaidCharts2Tests.test_timeline_every_period_has_event_boxes);
    Test.add_func("/charts2/timeline-section-bands", GDiagram.Tests.ReviewMermaidCharts2Tests.test_timeline_section_bands);
    Test.add_func("/charts2/mindmap-root-centred", GDiagram.Tests.ReviewMermaidCharts2Tests.test_mindmap_root_centred_branches_both_sides);
    Test.add_func("/charts2/mindmap-icon", GDiagram.Tests.ReviewMermaidCharts2Tests.test_mindmap_icon_is_drawn);
    Test.add_func("/charts2/pinned-click-regions", GDiagram.Tests.ReviewMermaidCharts2Tests.test_pinned_layouts_keep_click_regions);
    Test.add_func("/charts2/gantt-no-date-format-utc", GDiagram.Tests.ReviewMermaidCharts2Tests.test_gantt_no_date_format_parses_as_utc);
    Test.add_func("/charts2/gantt-no-date-format-chart", GDiagram.Tests.ReviewMermaidCharts2Tests.test_gantt_no_date_format_shifts_the_chart);
    Test.add_func("/charts2/mindmap-unmatched-markdown", GDiagram.Tests.ReviewMermaidCharts2Tests.test_mindmap_unmatched_markdown_marker_stays_literal);
    Test.add_func("/charts2/gantt-date-overflow", GDiagram.Tests.ReviewMermaidCharts2Tests.test_gantt_date_overflow_is_clamped);
    Test.add_func("/charts2/gantt-vert-span", GDiagram.Tests.ReviewMermaidCharts2Tests.test_gantt_vert_marker_spans_all_tasks);
    Test.add_func("/charts2/gantt-d3-space-pad", GDiagram.Tests.ReviewMermaidCharts2Tests.test_gantt_d3_space_pad_modifier);
    Test.add_func("/charts2/gitgraph-merge-type-normal", GDiagram.Tests.ReviewMermaidCharts2Tests.test_gitgraph_merge_type_normal_draws_plain_commit);
    return Test.run();
}
