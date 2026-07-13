namespace GDiagram.Tests {
    /**
     * Mermaid chart diagrams (xychart, sankey, radar, treemap, pie, packet,
     * quadrant, timeline, kanban, user journey) checked against Mermaid CLI
     * 11.17: parsing of the documented syntax and the drawn geometry (bar and
     * line positions, treemap areas, packet field widths).
     */
    public class ReviewMermaidChartsTests {

        private static Gee.ArrayList<ElementRegion> regions() {
            return new Gee.ArrayList<ElementRegion>();
        }

        private class Geo {
            public double x;
            public double y;
            public double w;   // points
            public double h;   // points
        }

        // The DOT line of the element drawn with id="<id>", or null.
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

        // Centre and size of a node, in points (Graphviz y-up).
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

        // End points of a straight line element: {x1, y1, x2, y2}.
        private static double[] segment(string dot, string id) {
            string? line = line_with_id(dot, id);
            if (line == null) error("no line %s", id);
            string[] pts = attr(line, "pos").split(" ");
            string[] a = pts[0].split(",");
            string[] b = pts[pts.length - 1].split(",");
            return { double.parse(a[0]), double.parse(a[1]), double.parse(b[0]), double.parse(b[1]) };
        }

        private static bool near(double a, double b, double tol = 0.6) {
            return Math.fabs(a - b) <= tol;
        }

        // A DOT label with its \l / \r justification suffix removed.
        private static string label_text(string dot, string id) {
            string? line = line_with_id(dot, id);
            if (line == null) error("no element %s", id);
            string v = attr(line, "label");
            if (v.has_suffix("\\l") || v.has_suffix("\\r")) v = v.substring(0, v.length - 2);
            return v;
        }

        private static int count(string haystack, string needle) {
            int n = 0, i = 0;
            while ((i = haystack.index_of(needle, i)) >= 0) { n++; i += needle.length; }
            return n;
        }

        private static string example(string rel) {
            string? root = Environment.get_variable("GDIAGRAM_SOURCE_ROOT");
            assert(root != null);
            string text;
            try {
                FileUtils.get_contents(Path.build_filename(root, "examples", "mermaid", rel), out text);
            } catch (FileError e) {
                error("%s", e.message);
            }
            return text;
        }

        // ==================== XYChart ====================

        private const string XY1 = "xychart-beta\n    title \"X\"\n    x-axis \"Month\" [jan, feb, mar]\n    y-axis \"Units\" 0 --> 100\n    bar [20, 50, 80]\n    line [30, 60, 90]\n";

        private static string xy_dot(string src) {
            var d = new MermaidXYChartParser().parse(src);
            return new MermaidXYChartRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        // X1: the line series is drawn through the band centres at its values.
        public static void test_xy_line_series() {
            string dot = xy_dot(XY1);
            var bar0 = node(dot, "xy_bar_0_0");
            var bar1 = node(dot, "xy_bar_0_1");
            double baseline = bar0.y - bar0.h / 2;          // value 0
            double per_unit = bar0.h / 20.0;                // bar 0 is 20 high
            assert(near(bar1.h, 50 * per_unit));
            double[] s0 = segment(dot, "xy_line_0_1");      // jan -> feb
            double[] s1 = segment(dot, "xy_line_0_2");      // feb -> mar
            assert(near(s0[0], bar0.x) && near(s0[2], bar1.x));
            assert(near(s0[1] - baseline, 30 * per_unit));
            assert(near(s0[3] - baseline, 60 * per_unit));
            assert(near(s1[3] - baseline, 90 * per_unit));
        }

        // X2: `x-axis "title" [categories]` keeps both.
        public static void test_xy_axis_title_and_categories() {
            var d = new MermaidXYChartParser().parse(XY1);
            assert(d.x_axis_label == "Month");
            assert(d.x_labels.size == 3 && d.x_labels.get(0) == "jan" && d.x_labels.get(2) == "mar");
            string dot = xy_dot(XY1);
            assert(attr(line_with_id(dot, "xy_cat_label_1"), "label") == "feb");
            var q = new MermaidXYChartParser().parse("xychart-beta\n x-axis Region [\"North, East\", South]\n bar [1, 2]\n");
            assert(q.x_axis_label == "Region" && q.x_labels.size == 2 && q.x_labels.get(0) == "North, East");
        }

        // X3: `xychart-beta horizontal` lays bars along x, categories down y.
        public static void test_xy_horizontal() {
            string src = "xychart-beta horizontal\n    x-axis [a, b, c]\n    bar [20, 50, 80]\n";
            assert(new MermaidXYChartParser().parse(src).horizontal);
            string dot = xy_dot(src);
            var a = node(dot, "xy_bar_0_0");
            var b = node(dot, "xy_bar_0_1");
            var c = node(dot, "xy_bar_0_2");
            assert(near(a.x - a.w / 2, c.x - c.w / 2));     // same left edge
            // Mermaid anchors a bar at the plot edge, and with no explicit
            // y-axis the domain is the data's own min..max — so the smallest
            // value has no bar and the others scale from it.
            assert(a.w < 0.5);
            assert(near((b.w - a.w) / (c.w - a.w), 0.5, 0.01));   // (50-20)/(80-20)
            assert(a.y > c.y);                              // a above c
            assert(near(a.h, c.h));
        }

        // X4: tick labels are centred on their tick.
        public static void test_xy_tick_labels_on_ticks() {
            string dot = xy_dot(XY1);
            for (int i = 0; i < 11; i++) {
                double[] tick = segment(dot, "xy_ytick_%d".printf(i));
                var label = node(dot, "xy_ytick_label_%d".printf(i));
                assert(near(label.y, tick[1], 0.05));
            }
            assert(attr(line_with_id(dot, "xy_ytick_label_10"), "label").has_prefix("100"));
        }

        // `y-axis "T" min --> max` and several bar/line plots.
        public static void test_xy_range_and_multiple_series() {
            string src = "xychart-beta\n y-axis \"Revenue (in $)\" 4000 --> 11000\n x-axis [a, b]\n bar [5000, 11000]\n bar [4500, 6000]\n line [5000, 9000]\n line [4000, 8000]\n";
            var d = new MermaidXYChartParser().parse(src);
            assert(d.y_axis_label == "Revenue (in $)" && d.has_y_range && d.y_min == 4000 && d.y_max == 11000);
            assert(d.series.size == 4);
            string dot = xy_dot(src);
            var top_bar = node(dot, "xy_bar_0_1");         // 11000 = full height
            var low_bar = node(dot, "xy_bar_1_0");         // 4500
            double bottom = top_bar.y - top_bar.h / 2;
            assert(near(low_bar.y - low_bar.h / 2, bottom));
            assert(near(low_bar.h / top_bar.h, 500.0 / 7000.0, 0.01));
            assert(line_with_id(dot, "xy_line_0_1") != null && line_with_id(dot, "xy_line_1_1") != null);
        }

        // ==================== Sankey ====================

        private static string sankey_dot(MermaidSankey d) {
            return new MermaidSankeyRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        // K1 + K2: RFC 4180 double quotes; single quotes are part of the name.
        public static void test_sankey_csv_quotes() {
            var d = new MermaidSankeyParser().parse("sankey-beta\n\"Heat, gas\",Homes,10.5\nHomes,Kitchen 'main',4.5\n\"Say \"\"hi\"\"\",Homes,1\n");
            assert(d.links.size == 3);
            assert(d.links.get(0).source == "Heat, gas" && d.links.get(0).target == "Homes");
            assert(d.links.get(1).target == "Kitchen 'main'");
            assert(d.links.get(2).source == "Say \"hi\"");
        }

        // K3: names differing only in punctuation stay separate nodes, each
        // with its own bar and its own ribbon (labels are right-justified
        // because both sit in the right-hand half of the chart).
        public static void test_sankey_distinct_node_ids() {
            string dot = sankey_dot(new MermaidSankeyParser().parse("sankey-beta\nGrid,Heat-pump,10\nGrid,Heat pump,5\n"));
            assert(dot.contains("label=\"Heat-pump 10\\r\""));
            assert(dot.contains("label=\"Heat pump 5\\r\""));
            double w0 = 0, w1 = 0;
            foreach (string line in dot.split("\n")) {
                if (line.contains("id=\"sankey_link_0\"")) w0 = double.parse(attr(line, "penwidth"));
                if (line.contains("id=\"sankey_link_1\"")) w1 = double.parse(attr(line, "penwidth"));
            }
            assert(w0 > 0 && w1 > 0 && near(w0 / w1, 2.0, 0.01));
        }

        // K4 + K5: values keep their decimals and every node carries its total,
        // on large diagrams too. Mermaid labels nodes only — a ribbon has no
        // label of its own.
        public static void test_sankey_values() {
            string dot = sankey_dot(new MermaidSankeyParser().parse("sankey-beta\nA,B,1.5\nA,C,2.25\n"));
            assert(dot.contains("label=\"A 3.75\\l\""));
            assert(dot.contains("label=\"B 1.5\\r\""));
            assert(dot.contains("label=\"C 2.25\\r\""));
            var big = new StringBuilder("sankey-beta\n");
            for (int i = 0; i < 25; i++) big.append_printf("Src,T%d,%d.5\n", i, i + 1);
            string big_dot = sankey_dot(new MermaidSankeyParser().parse(big.str));
            assert(big_dot.contains("T24 25.5"));
            var off = new MermaidSankeyParser().parse("---\nconfig:\n  sankey:\n    showValues: false\n---\nsankey-beta\nA,B,1.5\n");
            assert(!off.show_values && sankey_dot(off).contains("label=\"A\\l\""));
        }

        // K6: the title comes from front matter; the examples use valid syntax.
        public static void test_sankey_front_matter_title() {
            var d = new MermaidSankeyParser().parse("---\ntitle: Flows\n---\nsankey-beta\nA,B,1.5\n");
            assert(d.title == "Flows" && d.links.size == 1);
            foreach (string name in new string[] { "sankey/budget.mmd", "sankey/energy.mmd" }) {
                string text = example(name);
                assert(text.has_prefix("---\ntitle: "));
                foreach (string line in text.split("\n")) assert(!line.strip().has_prefix("title "));
                var e = new MermaidSankeyParser().parse(text);
                assert(e.title != null && e.title.length > 0 && e.links.size > 10);
            }
        }

        // ==================== Radar ====================

        private static string radar_dot(MermaidRadar d) {
            return new MermaidRadarRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        // R1: several labelled axes (and curves) on one line.
        public static void test_radar_axes_on_one_line() {
            var d = new MermaidRadarParser().parse("radar-beta\n  axis m[\"Math\"], s[\"Science\"], e[\"English\"]\n  curve a[\"Alice\"]{3, 4, 5}, b[\"Bob\"]{5, 2, 4}\n");
            assert(d.axes.size == 3);
            assert(d.axes.get(0).id == "m" && d.axes.get(0).label == "Math");
            assert(d.axes.get(2).id == "e" && d.axes.get(2).label == "English");
            assert(d.curves.size == 2 && d.curves.get(1).label == "Bob" && d.curves.get(1).values.size == 3);
        }

        // R2: without `max` the scale ends at the largest value.
        public static void test_radar_default_max() {
            var d = new MermaidRadarParser().parse("radar-beta\n  axis A, B, C, D\n  curve x[\"Team X\"]{1, 2, 3, 4}\n");
            assert(d.max_value == 4.0 && d.min_value == 0.0);
            string dot = radar_dot(d);
            // The value 4 on axis D sits on the outer ring.
            var ring = node(dot, "radar_ring_5");
            var p = node(dot, "radar_curve_0_pt_3");
            assert(near(Math.fabs(p.x - ring.x), ring.w / 2, 0.1));
            var e = new MermaidRadarParser().parse("radar-beta\n axis A, B, C\n curve x{A: 5, C: 3, B: 4}\n max 10\n");
            assert(e.max_value == 10.0);
        }

        // R3: a legend with the curve labels.
        public static void test_radar_legend() {
            var d = new MermaidRadarParser().parse("radar-beta\n axis A, B, C\n curve a[\"Alice\"]{1, 2, 3}\n curve b[\"Bob\"]{3, 2, 1}\n");
            string dot = radar_dot(d);
            assert(attr(line_with_id(dot, "radar_legend_0"), "label").has_prefix("Alice"));
            assert(attr(line_with_id(dot, "radar_legend_1"), "label").has_prefix("Bob"));
            var hidden = new MermaidRadarParser().parse("radar-beta\n showLegend false\n axis A, B, C\n curve a[\"Alice\"]{1, 2, 3}\n");
            assert(line_with_id(radar_dot(hidden), "radar_legend_0") == null);
        }

        // R4: graticule rings (circle by default, `ticks`, `graticule polygon`).
        public static void test_radar_graticule() {
            string dot = radar_dot(new MermaidRadarParser().parse("radar-beta\n axis A, B, C\n curve a{1, 2, 3}\n"));
            assert(count(dot, "id=\"radar_ring_") == 5);
            var outer = node(dot, "radar_ring_5");
            var inner = node(dot, "radar_ring_1");
            assert(near(inner.w * 5, outer.w, 0.5));
            string poly = radar_dot(new MermaidRadarParser().parse("radar-beta\n axis A, B, C, D\n ticks 3\n graticule polygon\n curve a{1, 2, 3, 4}\n"));
            assert(line_with_id(poly, "radar_ring_3_3") != null && line_with_id(poly, "radar_ring_4_0") == null);
            assert(line_with_id(poly, "radar_ring_1") == null);   // no circles
        }

        // Curves are filled (translucent polygons added to the SVG).
        public static void test_radar_curve_fills() {
            var d = new MermaidRadarParser().parse("radar-beta\n axis A, B, C\n curve a{1, 2, 3}\n curve b{3, 2, 1}\n");
            uint8[]? svg = new MermaidRadarRenderer(new Gvc.Context(), regions(), "dot").render_to_svg(d);
            assert(svg != null);
            var text = new StringBuilder();
            text.append_len((string) svg, svg.length);
            assert(count(text.str, "class=\"radar-fill\"") == 2);
        }

        // ==================== Treemap ====================

        private static string treemap_dot(MermaidTreemap d) {
            return new MermaidTreemapRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        // T1: a squarified treemap, leaf areas proportional to their values,
        // nested inside their sections.
        public static void test_treemap_areas() {
            string src = "treemap-beta\n\"Engineering\"\n    \"Salaries\": 450\n    \"Infrastructure\"\n        \"Cloud\": 80\n        \"Hardware\": 20\n    \"Tools\": 30\n\"Marketing\"\n    \"Advertising\": 120\n    \"Events\": 40\n";
            string dot = treemap_dot(new MermaidTreemapParser().parse(src));
            // Leaves are inset by 2pt on each side.
            var salaries = node(dot, "treemap_leaf_3");
            var tools = node(dot, "treemap_leaf_7");
            var cloud = node(dot, "treemap_leaf_5");
            var hardware = node(dot, "treemap_leaf_6");
            double a_sal = (salaries.w + 4) * (salaries.h + 4);
            double a_tools = (tools.w + 4) * (tools.h + 4);
            double a_cloud = (cloud.w + 4) * (cloud.h + 4);
            double a_hw = (hardware.w + 4) * (hardware.h + 4);
            assert(Math.fabs(a_sal / a_tools - 15.0) < 0.15);
            assert(Math.fabs(a_cloud / a_hw - 4.0) < 0.05);
            // Hardware lies inside the Infrastructure section.
            var infra = node(dot, "treemap_section_4");
            assert(hardware.x - hardware.w / 2 >= infra.x - infra.w / 2);
            assert(hardware.x + hardware.w / 2 <= infra.x + infra.w / 2);
            assert(hardware.y - hardware.h / 2 >= infra.y - infra.h / 2);
            // Section totals in the header.
            assert(dot.contains("580") && dot.contains("160"));
        }

        // T2 + T3: decimal values and single-quoted names.
        public static void test_treemap_values_and_quotes() {
            var d = new MermaidTreemapParser().parse("treemap-beta\n\"Root\"\n    \"A\": 10.5\n    'B': 20\n");
            assert(d.roots.size == 1 && d.roots.get(0).children.size == 2);
            var b = d.roots.get(0).children.get(1);
            assert(b.label == "B" && b.is_leaf && b.value == 20);
            string dot = treemap_dot(d);
            assert(dot.contains("label=\"10.5\""));
            assert(dot.contains("30.5"));
        }

        // `:::class` with classDef styling.
        public static void test_treemap_class_def() {
            var d = new MermaidTreemapParser().parse("treemap-beta\n\"Root\"\n    \"Hot\": 10:::hot\n    \"Cold\": 5\nclassDef hot fill:#ff0000,stroke:#00ff00,color:#0000ff;\n");
            var hot = d.roots.get(0).children.get(0);
            assert(hot.label == "Hot" && hot.value == 10 && hot.css_class == "hot");
            string line = line_with_id(treemap_dot(d), "treemap_leaf_3");
            assert(attr(line, "fillcolor") == "#ff0000" && attr(line, "color") == "#00ff00");
        }

        // ==================== Pie ====================

        private static string pie_dot(string src) {
            var d = new MermaidPieParser().parse(src);
            return new MermaidPieRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        // P1: showData values keep their decimals.
        public static void test_pie_show_data_values() {
            string dot = pie_dot("pie showData\n    \"A\" : 12.5\n    \"B\" : 7.25\n");
            assert(attr(line_with_id(dot, "pie_legend_0"), "label").has_prefix("A [12.5]"));
            assert(attr(line_with_id(dot, "pie_legend_1"), "label").has_prefix("B [7.25]"));
        }

        // P2: percentages on the slices (clockwise from 12 o'clock), not in the legend.
        public static void test_pie_percentages_on_slices() {
            string dot = pie_dot("pie\n    \"A\" : 75\n    \"B\" : 25\n");
            var pie = node(dot, "pie");
            var a = node(dot, "pie_pct_0");
            var b = node(dot, "pie_pct_1");
            assert(attr(line_with_id(dot, "pie_pct_0"), "label") == "75%");
            assert(attr(line_with_id(dot, "pie_pct_1"), "label") == "25%");
            // A covers 12 -> 9 o'clock clockwise, its middle is at 4:30 (lower right);
            // B covers 9 -> 12, its middle at 10:30 (upper left).
            assert(a.x > pie.x && a.y < pie.y);
            assert(b.x < pie.x && b.y > pie.y);
            assert(!attr(line_with_id(dot, "pie_legend_0"), "label").contains("%"));
        }

        // ==================== Packet ====================

        private static string packet_dot(string src) {
            var d = new MermaidPacketParser().parse(src);
            return new MermaidPacketRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
        }

        private const string PK1 = "packet-beta\n0-1: \"Ver\"\n2-31: \"Very long field name for payload\"\n32-47: \"Source Port Number Field\"\n48-63: \"Dst\"\n";

        // W1: field width follows the bit count, 32 bits per row.
        public static void test_packet_widths_follow_bits() {
            string dot = packet_dot(PK1);
            var ver = node(dot, "packet_field_0_0");        // 2 bits
            var payload = node(dot, "packet_field_1_0");    // 30 bits
            var src = node(dot, "packet_field_2_0");        // 16 bits
            var dst = node(dot, "packet_field_3_0");        // 16 bits
            // width + gap = bits * bit width
            double bit = (ver.w + 4) / 2;
            assert(near((payload.w + 4) / 30, bit, 0.01));
            assert(near(src.w, dst.w, 0.01));
            assert(near(ver.x - ver.w / 2, src.x - src.w / 2));      // both rows start at x=0
            assert(near(payload.x + payload.w / 2, dst.x + dst.w / 2)); // and end at bit 31
            assert(ver.y > src.y);                                    // row 2 below row 1
        }

        // W2: no invented title.
        public static void test_packet_no_default_title() {
            string dot = packet_dot(PK1);
            assert(!dot.contains("Packet Structure") && line_with_id(dot, "packet_title") == null);
            assert(line_with_id(packet_dot("packet-beta\ntitle UDP\n+16: \"Port\"\n"), "packet_title") != null);
        }

        // W3: a single bit shows one number; `+N` keeps working.
        public static void test_packet_single_bit_and_increment() {
            string dot = packet_dot("packet-beta\n0-105: \"Head\"\n106: \"URG\"\n107-127: \"Rest\"\n");
            // The one number is centred over its box, not left-justified the
            // way a range's start number is. (`!dot.contains("106-106")` used
            // to stand here, and no code path could ever have written that.)
            assert(attr(line_with_id(dot, "packet_bit_start_1_0"), "label") == "106");
            assert(attr(line_with_id(dot, "packet_bit_start_2_0"), "label") == "107\\l");
            assert(line_with_id(dot, "packet_bit_end_1_0") == null);
            assert(line_with_id(dot, "packet_bit_end_2_0") != null);
            // ... and it sits over the middle of the field it numbers.
            var field = node(dot, "packet_field_1_0");
            var number = node(dot, "packet_bit_start_1_0");
            assert(near(number.x, field.x, 0.01));
            var d = new MermaidPacketParser().parse("packet-beta\n+16: \"A\"\n+1: \"B\"\n+15: \"C\"\n");
            assert(d.fields.get(1).bit_start == 16 && d.fields.get(1).bit_end == 16);
            assert(d.fields.get(2).bit_start == 17 && d.fields.get(2).bit_end == 31);
        }

        // ==================== Quadrant ====================

        private const string QD1 = "quadrantChart\n    x-axis Low --> High\n    y-axis Low --> High\n    Point A:::red: [0.3, 0.6]\n    Point B: [0.7, 0.2] radius: 12, color: #ff0000, stroke-color: #00ff00, stroke-width: 3px\n    classDef red color: #ff3300, radius: 10\n";

        // Q1: `:::class` is not part of the label.
        public static void test_quadrant_class_not_in_label() {
            var d = new MermaidQuadrantParser().parse(QD1);
            assert(d.points.get(0).label == "Point A" && d.points.get(0).css_class == "red");
        }

        // Q2: per-point styles and classDef.
        public static void test_quadrant_point_styles() {
            var d = new MermaidQuadrantParser().parse(QD1);
            var b = d.points.get(1);
            assert(b.radius == 12 && b.color == "#ff0000" && b.stroke_color == "#00ff00" && b.stroke_width == 3);
            string dot = new MermaidQuadrantRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
            string? a_line = null, b_line = null;
            foreach (string line in dot.split("\n")) {
                if (line.has_prefix("    pt0 ")) a_line = line;
                if (line.has_prefix("    pt1 ")) b_line = line;
            }
            assert(a_line != null && b_line != null);
            assert(attr(a_line, "fillcolor") == "#ff3300");
            assert(near(double.parse(attr(a_line, "width")) * 72.0, 2 * 10 * 0.75, 0.05));
            assert(attr(b_line, "fillcolor") == "#ff0000" && attr(b_line, "color") == "#00ff00");
            assert(attr(b_line, "penwidth") == "3.00");
            assert(near(double.parse(attr(b_line, "width")) * 72.0, 2 * 12 * 0.75, 0.05));
        }

        // ==================== Timeline ====================

        // L1: every ` : ` on a line starts another event.
        public static void test_timeline_events_on_one_line() {
            var d = new MermaidTimelineParser().parse("timeline\n    Late 2023 : Prototype V1 : Feedback session\n              : Demo : Retro\n    2024 : Delta\n");
            assert(d.periods.size == 2);
            var late = d.periods.get(0);
            assert(late.label == "Late 2023" && late.events.size == 4);
            assert(late.events.get(0).text == "Prototype V1" && late.events.get(1).text == "Feedback session");
            assert(late.events.get(3).text == "Retro");
            assert(d.periods.get(1).events.size == 1);
        }

        // ==================== Kanban ====================

        private class TextPos {
            public double x;
            public double y;
        }

        private static TextPos svg_text(string svg, string text) {
            MatchInfo m;
            try {
                var re = new Regex("<text[^>]* x=\"([-\\d.]+)\" y=\"([-\\d.]+)\"[^>]*>%s</text>".printf(Regex.escape_string(text)));
                if (!re.match(svg, 0, out m)) error("no text %s", text);
            } catch (RegexError err) {
                error("%s", err.message);
            }
            var p = new TextPos();
            p.x = double.parse(m.fetch(1));
            p.y = double.parse(m.fetch(2));
            return p;
        }

        // N1: columns left to right, cards stacked within each column, metadata kept.
        public static void test_kanban_layout() {
            var d = new MermaidKanbanParser().parse("kanban\n  todo[Todo]\n    a[Card A]@{ ticket: T42, assigned: 'alice' }\n    b[Card B]\n    c[Card C]\n  done[Done]\n    d[Card D]@{ priority: 'Low' }\n");
            uint8[]? data = new MermaidKanbanRenderer(new Gvc.Context(), regions(), "dot").render_to_svg(d);
            assert(data != null);
            var sb = new StringBuilder();
            sb.append_len((string) data, data.length);
            string svg = sb.str;
            var a = svg_text(svg, "Card A");
            var b = svg_text(svg, "Card B");
            var c = svg_text(svg, "Card C");
            var dd = svg_text(svg, "Card D");
            var todo = svg_text(svg, "Todo");
            var done = svg_text(svg, "Done");
            assert(near(a.x, b.x) && near(b.x, c.x));          // one column
            assert(a.y < b.y && b.y < c.y);                    // stacked downwards
            assert(dd.x > a.x + 50 && near(dd.y, a.y, 1.0));   // next column, top aligned
            assert(near(todo.y, done.y) && done.x > todo.x);
            assert(svg.contains(">T42</text>") && svg.contains(">alice</text>"));
        }

        // ==================== User journey ====================

        // Tasks are grouped under their section header.
        public static void test_userjourney_sections_group_tasks() {
            var d = new MermaidUserJourneyParser().parse("journey\n  title Day\n  section Morning\n    Wake up: 3: Me\n    Coffee: 5: Me\n  section Work\n    Code: 5: Me\n");
            string dot = new MermaidUserJourneyRenderer(new Gvc.Context(), regions(), "dot").generate_dot(d);
            int morning = dot.index_of("subgraph cluster_section_0");
            int work = dot.index_of("subgraph cluster_section_1");
            assert(morning >= 0 && work > morning);
            string morning_block = dot.substring(morning, work - morning);
            assert(morning_block.contains("label=\"Morning\"") && morning_block.contains("Wake up") && morning_block.contains("Coffee"));
            assert(!morning_block.contains(">Code<"));
            assert(dot.substring(work).contains(">Code<"));
        }

        // ==================== Round 3 regressions ====================

        /**
         * A value axis whose ends are equal — or so large that `t += step`
         * cannot advance the double — must still terminate.
         *
         * `y-axis 1e17 --> 1e17` used to spin in `for (t = ...; t <= max; t +=
         * step)` forever, appending a tick each turn: 2.9 GB resident after
         * 9 s, on every keystroke in the editor.
         */
        public static void test_xy_degenerate_range_terminates() {
            string dot = xy_dot("xychart-beta\n    y-axis 100000000000000000 --> 100000000000000000\n" +
                                "    x-axis [a, b]\n    bar [1, 2]\n");
            // d3 answers a single tick for a zero-width domain.
            assert(line_with_id(dot, "xy_ytick_label_0") != null);
            assert(line_with_id(dot, "xy_ytick_label_1") == null);
            assert(label_text(dot, "xy_ytick_label_0") == "100000000000000000");
            // Both categories are still drawn, so the chart is not empty.
            assert(line_with_id(dot, "xy_cat_label_0") != null);
            assert(line_with_id(dot, "xy_cat_label_1") != null);

            // The tick helper itself is bounded whatever it is handed.
            assert(ChartCanvas.ticks_of(0, 100, 10).size == 11);
            assert(ChartCanvas.ticks_of(1e17, 1e17, 1).size <= 2);
            assert(ChartCanvas.ticks_of(0, 1e9, 1e-9).size <= ChartCanvas.MAX_TICKS + 2);
            assert(ChartCanvas.ticks_of(5, 5, 0).size <= 2);
        }

        /**
         * With no `y-axis` line the range is the data's own min and max, as
         * Mermaid's setYAxisRangeFromPlotData computes it. Pulling it to 0
         * turned `line [20.5, 21.0, 20.8, 21.4]` into a flat line under ticks
         * 0..25.
         */
        public static void test_xy_default_range_follows_the_data() {
            string dot = xy_dot("xychart-beta\n    line [20.5, 21.0, 20.8, 21.4]\n");
            assert(label_text(dot, "xy_ytick_label_0") == "20.5");
            int last = 0;
            while (line_with_id(dot, "xy_ytick_label_%d".printf(last + 1)) != null) last++;
            assert(label_text(dot, "xy_ytick_label_%d".printf(last)) == "21.4");
            // The line uses the full plot height instead of its bottom 4%.
            double[] lo = segment(dot, "xy_line_0_1");   // 20.5 -> 21.0
            double[] hi = segment(dot, "xy_line_0_3");   // 20.8 -> 21.4
            double span = Math.fabs(hi[3] - lo[1]);      // 21.4 vs 20.5
            assert(span > 250);                          // PLOT_H is 300
        }

        /**
         * A band x axis fixes the category count: Mermaid slices the extra
         * values away (`data.slice(0, categories.length)`) rather than
         * inventing "3" and "4" categories for them.
         */
        public static void test_xy_extra_values_are_sliced_to_categories() {
            string dot = xy_dot("xychart-beta\n    x-axis [a, b]\n    bar [1, 2, 3, 4]\n");
            assert(label_text(dot, "xy_cat_label_0") == "a");
            assert(label_text(dot, "xy_cat_label_1") == "b");
            assert(line_with_id(dot, "xy_cat_label_2") == null);
            assert(line_with_id(dot, "xy_bar_0_2") == null);
            // Without categories the data length still sets the count.
            string free = xy_dot("xychart-beta\n    bar [1, 2, 3, 4]\n");
            assert(line_with_id(free, "xy_bar_0_3") != null);
        }

        /**
         * A titled plot gets a legend row — Mermaid's `showLegend` defaults to
         * true and the titles were parsed and then thrown away.
         */
        public static void test_xy_legend_lists_titled_plots() {
            string dot = xy_dot("xychart-beta\n    x-axis [jan, feb]\n    y-axis 0 --> 100\n" +
                                "    bar \"Bar series\" [10, 20]\n    line \"Line series\" [30, 40]\n");
            assert(label_text(dot, "xy_legend_label_0") == "Bar series");
            assert(label_text(dot, "xy_legend_label_1") == "Line series");
            // Right of the plot, one row under the other, marker then label.
            var plot_edge = node(dot, "xy_bar_0_1");
            var row0 = node(dot, "xy_legend_label_0");
            var row1 = node(dot, "xy_legend_label_1");
            assert(row0.x - row0.w / 2 > plot_edge.x);
            assert(row0.y > row1.y);                       // Graphviz y grows up
            var marker0 = node(dot, "xy_legend_marker_0");
            assert(marker0.x < row0.x - row0.w / 2 + 1);
            // No title, no legend.
            string bare = xy_dot("xychart-beta\n    x-axis [jan, feb]\n    bar [10, 20]\n");
            assert(line_with_id(bare, "xy_legend_label_0") == null);
        }

        /**
         * Text is measured with Pango, not at a flat 0.56 em per character: a
         * CJK label is about twice as wide as a Latin one of the same length
         * and used to run past the edge of the canvas and be cut mid-glyph.
         */
        public static void test_chart_text_width_measures_wide_glyphs() {
            double latin = ChartCanvas.text_width("abcdefgh", 12);
            double cjk = ChartCanvas.text_width("日本語テキスト日本", 12);
            assert(cjk > latin * 1.6);
            assert(ChartCanvas.text_width("", 12) == 0);

            // The radar axis label makes room for itself, so the canvas grows.
            string wide = radar_dot(new MermaidRadarParser().parse(
                "radar-beta\n  axis 日本語のとても長い軸ラベルです日本語, b, c\n  curve x{5, 3, 4}\n"));
            string narrow = radar_dot(new MermaidRadarParser().parse(
                "radar-beta\n  axis a, b, c\n  curve x{5, 3, 4}\n"));
            assert(right_edge(wide) > right_edge(narrow) + 100);
        }

        // x of the canvas's bottom-right anchor, i.e. the drawing's width.
        private static double right_edge(string dot) {
            foreach (string line in dot.split("\n")) {
                if (!line.contains("a_br [")) continue;
                return double.parse(attr(line, "pos").split(",")[0]);
            }
            error("no a_br anchor");
        }

        /**
         * A treemap written without numbers still draws its nodes. Dropping
         * every node whose total is 0 left a blank 29x29 pt square with no
         * text and no error at all.
         */
        public static void test_treemap_keeps_zero_valued_nodes() {
            string dot = treemap_dot(new MermaidTreemapParser().parse(
                "treemap-beta\n\"Root\"\n    \"Frontend\"\n    \"Backend\"\n"));
            assert(dot.contains(">Root<") || dot.contains("label=\"Root\""));
            assert(count(dot, "shape=plaintext") >= 3);
            // Equal shares when nothing has a value.
            var fe = node(dot, "treemap_leaf_3");
            var be = node(dot, "treemap_leaf_4");
            assert(near(fe.w * fe.h, be.w * be.h, 1.0));
            // No "0" printed where there is no number.
            assert(!dot.contains("label=\"0\""));

            // A single zero-valued leaf next to real ones is still drawn.
            string mixed = treemap_dot(new MermaidTreemapParser().parse(
                "treemap-beta\n\"Root\"\n    \"A\": 10\n    \"B\": 0\n"));
            assert(mixed.contains("label=\"B\"") || mixed.contains(">B<"));

            // An empty treemap says so instead of rendering nothing.
            assert(treemap_dot(new MermaidTreemapParser().parse("treemap-beta\n")).contains("(no data)"));
        }

        /**
         * Packet ranges are validated and the drawing is capped.
         *
         * `10-3` silently became a 1-bit field; `0-2000000` drew 62 501 rows
         * into a 56 MB SVG in 7 s. Mermaid reports the first and stops at
         * maxPacketSize (1e4) blocks.
         */
        public static void test_packet_rejects_invalid_and_oversized_ranges() {
            var bad = new MermaidPacketParser().parse("packet-beta\n0-3: \"A\"\n10-3: \"Bad\"\n");
            assert(bad.has_errors());
            assert(bad.errors.get(0).message.contains("10 - 3"));
            assert(bad.errors.get(0).line == 3);
            assert(bad.fields.size == 1);           // the good field survives

            // Over the cap Mermaid draws the prefix instead of refusing the diagram, and
            // so do we: no ParseError (which fails the whole render — a mistyped range
            // would blank the preview mid-keystroke), the field kept and cut to the
            // block budget, and `truncated` set so the renderer can say so.
            var big = new MermaidPacketParser().parse("packet-beta\n0-2000000: \"Payload\"\n");
            assert(!big.has_errors());
            assert(big.truncated);
            assert(big.fields.size == 1);
            assert(big.fields.get(0).bit_end
                   == MermaidPacketParser.MAX_BLOCKS * MermaidPacketParser.BITS_PER_ROW - 1);
            string big_dot = new MermaidPacketRenderer(new Gvc.Context(), regions(), "dot").generate_dot(big);
            assert(count(big_dot, "id=\"packet_field_") == MermaidPacketParser.MAX_BLOCKS);
            assert(big_dot.contains("truncated"));

            // The renderer never emits more than the cap, whatever it is given.
            var forced = new MermaidPacket();
            forced.add_field(new PacketField(0, 2000000, "Payload", 2));
            string dot = new MermaidPacketRenderer(new Gvc.Context(), regions(), "dot").generate_dot(forced);
            assert(count(dot, "id=\"packet_field_") == MermaidPacketParser.MAX_BLOCKS);
            // 2 000 001 bits are 62 501 rows; the cap stops at 10 000.
            assert(!dot.contains("packet_field_0_10000"));

            // A legal packet is untouched.
            var ok = new MermaidPacketParser().parse("packet-beta\n0-15: \"A\"\n16-31: \"B\"\n");
            assert(!ok.has_errors() && ok.fields.size == 2);
        }

        /**
         * Packet fields have to tile the packet, as Mermaid's populate() requires:
         * "Packet block 8 - 23 is not contiguous. It should start from 16."
         *
         * Overlapping and gapped ranges were taken exactly as written and the renderer
         * drew the boxes on top of each other, so `0-15` / `8-23` looked like a packet
         * with a 24-bit field over a 16-bit one.
         */
        /**
         * `y-axis "Y" 50 --> -50` is a range written backwards. Mermaid hands the
         * descending domain to d3, which flips the axis and still plots every point;
         * kept as written it was a range of negative width, the renderer widened it
         * to [50, 51] and all three bars fell outside the plot — an empty chart, exit 0.
         */
        public static void test_xy_inverted_range_is_normalised() {
            string src = "xychart-beta\n    title \"T\"\n    x-axis [a, b, c]\n" +
                         "    y-axis \"Y\" %s\n    bar [10, 20, 30]\n";
            string dot = xy_dot(src.printf("50 --> -50"));
            string upright = xy_dot(src.printf("-50 --> 50"));
            assert(dot == upright);

            // Every bar is drawn, and their heights grow with the values.
            var b0 = node(dot, "xy_bar_0_0");
            var b1 = node(dot, "xy_bar_0_1");
            var b2 = node(dot, "xy_bar_0_2");
            assert(b0.h > 0 && b1.h > b0.h && b2.h > b1.h);
            // The axis spans the whole range, lowest tick first.
            assert(label_text(dot, "xy_ytick_label_0") == "-50");
            int last = 0;
            while (line_with_id(dot, "xy_ytick_label_%d".printf(last + 1)) != null) last++;
            assert(label_text(dot, "xy_ytick_label_%d".printf(last)) == "50");

            // An inverted x range is normalised the same way.
            string xrange = xy_dot("xychart-beta\n    x-axis \"X\" 10 --> 1\n    line [1, 2, 3]\n");
            assert(xrange == xy_dot("xychart-beta\n    x-axis \"X\" 1 --> 10\n    line [1, 2, 3]\n"));
        }

        /**
         * d3.pie() over a dataset that sums to zero produces no arcs, so Mermaid draws
         * an empty circle with the legend beside it. Sharing the circle out evenly
         * instead invented a 50/50 split out of two values that both say zero.
         */
        public static void test_pie_all_zero_draws_no_slices() {
            string dot = pie_dot("pie title Z\n    \"A\" : 0\n    \"B\" : 0\n");
            // No wedge, no percentage labels and no dividing lines...
            assert(line_with_id(dot, "pie_pct_0") == null);
            assert(line_with_id(dot, "pie_pct_1") == null);
            assert(!dot.contains("style=wedged"));
            assert(line_with_id(dot, "pie_border_0") == null);
            // ...but the circle and both legend entries are still there.
            assert(line_with_id(dot, "pie_rim") != null);
            assert(label_text(dot, "pie_legend_0") == "A");
            assert(label_text(dot, "pie_legend_1") == "B");

            // A single zero slice behaves the same, and real data still draws wedges.
            string one = pie_dot("pie\n    \"Only\" : 0\n");
            assert(!one.contains("style=wedged") && line_with_id(one, "pie_pct_0") == null);
            assert(pie_dot("pie\n    \"A\" : 1\n    \"B\" : 1\n").contains("style=wedged"));
        }

        /**
         * A bit range is "+N", "N" or "N-M" with unsigned numbers. `int.parse()` reads
         * 0 out of anything else, so `-5-10: "x"` split into ["", "5", "10"] and was
         * drawn as bits 0-5 under the right label — the range the file asked for was
         * gone without a word. Mermaid answers a syntax error.
         */
        public static void test_packet_rejects_a_malformed_range() {
            var neg = new MermaidPacketParser().parse("packet-beta\n-5-10: \"x\"\n");
            assert(neg.has_errors());
            assert(neg.errors.get(0).message.contains("'-5-10' is invalid"));
            assert(neg.errors.get(0).line == 2);
            assert(neg.fields.size == 0);

            // Same for a range that is not a number at all.
            var word = new MermaidPacketParser().parse("packet-beta\nabc: \"x\"\n");
            assert(word.has_errors() && word.fields.size == 0);
            var half = new MermaidPacketParser().parse("packet-beta\n0-: \"x\"\n");
            assert(half.has_errors() && half.fields.size == 0);

            // The shapes Mermaid does accept are untouched.
            var ok = new MermaidPacketParser().parse(
                "packet-beta\n0-15: \"A\"\n16: \"B\"\n+8: \"C\"\n 25 - 31 : \"D\"\n");
            assert(!ok.has_errors());
            assert(ok.fields.size == 4);
            assert(ok.fields.get(3).bit_start == 25 && ok.fields.get(3).bit_end == 31);
        }

        public static void test_packet_ranges_must_be_contiguous() {
            var overlap = new MermaidPacketParser().parse("packet-beta\n0-15: \"A\"\n8-23: \"B\"\n");
            assert(overlap.has_errors());
            assert(overlap.errors.get(0).message == "Packet block 8 - 23 is not contiguous. It should start from 16.");
            assert(overlap.errors.get(0).line == 3);
            assert(overlap.fields.size == 1);        // the overlapping field is not drawn

            var gap = new MermaidPacketParser().parse("packet-beta\n0-15: \"A\"\n32-47: \"B\"\n");
            assert(gap.has_errors());
            assert(gap.errors.get(0).message.contains("should start from 16"));

            // One mistyped range reports once: parsing resumes after it, so the fields
            // that follow it correctly are not each reported as non-contiguous too.
            var once = new MermaidPacketParser().parse(
                "packet-beta\n0-15: \"A\"\n8-23: \"B\"\n24-31: \"C\"\n32-39: \"D\"\n");
            assert(once.errors.size == 1);
            assert(once.fields.size == 3);           // A, C and D

            // "+N" continues where the last field ended, so it is contiguous by
            // construction — and a zero-bit field is Mermaid's own error.
            var inc = new MermaidPacketParser().parse("packet-beta\n0-15: \"A\"\n+16: \"B\"\n+8: \"C\"\n");
            assert(!inc.has_errors() && inc.fields.size == 3);
            assert(inc.fields.get(1).bit_start == 16 && inc.fields.get(1).bit_end == 31);
            assert(inc.fields.get(2).bit_start == 32 && inc.fields.get(2).bit_end == 39);
            var zero = new MermaidPacketParser().parse("packet-beta\n0-7: \"A\"\n+0: \"B\"\n");
            assert(zero.has_errors());
            assert(zero.errors.get(0).message.contains("Cannot have a zero bit field"));

            // A packet that starts anywhere but bit 0 is non-contiguous as well.
            var late = new MermaidPacketParser().parse("packet-beta\n8-15: \"A\"\n");
            assert(late.has_errors());
            assert(late.errors.get(0).message.contains("should start from 0"));

            // The inverted-range error still comes first and still skips only its field.
            var inverted = new MermaidPacketParser().parse("packet-beta\n0-3: \"A\"\n10-3: \"B\"\n4-7: \"C\"\n");
            assert(inverted.errors.size == 1);
            assert(inverted.errors.get(0).message.contains("End must be greater than start"));
            assert(inverted.fields.size == 2);       // A and C, C still contiguous after 0-3
        }

        /**
         * Mermaid's addSection ignores a repeated label, and its values go
         * through parseFloat, so `1e3` is 1000.
         */
        public static void test_pie_duplicate_labels_and_exponents() {
            var dup = new MermaidPieParser().parse("pie\n    \"A\" : 10\n    \"B\" : 20\n    \"A\" : 30\n");
            assert(dup.slices.size == 2);
            assert(dup.slices.get(0).label == "A" && dup.slices.get(0).value == 10);
            assert(dup.get_total() == 30);

            var sci = new MermaidPieParser().parse("pie\n    \"A\" : 1e3\n    \"B\" : 20\n");
            assert(!sci.has_errors());
            assert(sci.slices.size == 2 && sci.slices.get(0).value == 1000);
            var signed = new MermaidPieParser().parse("pie\n    \"A\" : 2.5e+2\n    \"B\" : 1\n");
            assert(!signed.has_errors() && signed.slices.get(0).value == 250);
            // An identifier that only looks like an exponent is left alone.
            var plain = new MermaidPieParser().parse("pie\n    \"A\" : 5\n    \"B\" : 6\n");
            assert(plain.slices.get(0).value == 5);
        }

        /**
         * A negative exponent is part of the number, not an arrow.
         *
         * `"A" : 1e-3` lexed as NUMBER "1", IDENTIFIER "e" and then the `-` opened an
         * arrow-family token, so the leftovers failed the next statement and the whole
         * render with it (`1e3` and `2.5e+2` happened to survive). The lexer now takes
         * the exponent itself, and only when `e`/`E` is followed by digits or a sign and
         * digits — a date, an id before an arrow and a bare `1e` must lex as before,
         * since every Mermaid diagram shares this lexer.
         */
        public static void test_pie_negative_exponent_is_not_an_arrow() {
            foreach (string v in new string[] { "1e-3", "1E-10", "2.5e+2", "1e3", "42" }) {
                var d = new MermaidPieParser().parse("pie\n    \"A\" : %s\n    \"B\" : 1\n".printf(v));
                if (d.has_errors() || d.slices.size != 2) {
                    error("pie value %s: %d slices, %d errors (%s)", v, d.slices.size, d.errors.size,
                          d.errors.size > 0 ? d.errors.get(0).message : "");
                }
                assert(d.slices.get(0).value == double.parse(v));
            }

            // The shared lexer still splits an arrow after a number-looking id, and a
            // dash that is not an exponent sign is still its own token.
            var lexer = new MermaidLexer("flowchart LR\n  1e-->B\n  2024-01-01\n");
            var kinds = new StringBuilder();
            foreach (var t in lexer.scan_all()) {
                if (t.token_type == MermaidTokenType.NUMBER) kinds.append("[%s]".printf(t.lexeme));
            }
            // "1e" is not an exponent, so the number stops at 1 and the arrow survives
            assert(kinds.str.contains("[1]"));
            assert(!kinds.str.contains("[1e"));
            // A date is three numbers, not one with an exponent
            assert(kinds.str.contains("[2024]") && kinds.str.contains("[01]"));
            var fc = new MermaidFlowchartParser().parse("flowchart LR\n  1e-->B\n");
            assert(fc.edges.size == 1);
        }

        /**
         * Quadrant renders must not go through fixed /tmp names: two at once
         * (the GUI and the LSP's render worker are separate processes) read
         * each other's output, and the name is a symlink target in a
         * world-writable directory.
         */
        public static void test_quadrant_render_does_not_touch_fixed_tmp_names() {
            var d = new MermaidQuadrantParser().parse(QD1);
            string sentinel = "gdiagram-round3-sentinel";
            try {
                FileUtils.set_contents("/tmp/gdiagram_quadrant.dot", sentinel);
                FileUtils.set_contents("/tmp/gdiagram_quadrant.svg", sentinel);
            } catch (FileError e) {
                // Someone else already owns the legacy name on this machine,
                // which is the hazard itself — nothing left to prove here.
                Test.skip("cannot write /tmp/gdiagram_quadrant.dot: " + e.message);
                return;
            }
            uint8[]? svg = new MermaidQuadrantRenderer(new Gvc.Context(), regions(), "neato")
                .render_to_svg(d);
            assert(svg != null && ((string) svg).contains("<svg"));
            string dot_after, svg_after;
            try {
                FileUtils.get_contents("/tmp/gdiagram_quadrant.dot", out dot_after);
                FileUtils.get_contents("/tmp/gdiagram_quadrant.svg", out svg_after);
            } catch (FileError e) {
                error("%s", e.message);
            }
            assert(dot_after == sentinel && svg_after == sentinel);
            FileUtils.unlink("/tmp/gdiagram_quadrant.dot");
            FileUtils.unlink("/tmp/gdiagram_quadrant.svg");
        }

        /**
         * A point outside 0..1 is clamped into the quadrant box (Mermaid
         * rejects the file outright); leaving it inflated the neato canvas.
         */
        public static void test_quadrant_clamps_points_and_writes_dots() {
            string dot = new MermaidQuadrantRenderer(new Gvc.Context(), regions(), "neato").generate_dot(
                new MermaidQuadrantParser().parse(
                    "quadrantChart\n    x-axis Low --> High\n    y-axis Low --> High\n" +
                    "    Far: [5, -3]\n    In: [0.25, 0.75]\n"));
            assert(attr(line_with_id_free(dot, "pt0"), "pos") == "4.5000,0.5000!");
            assert(attr(line_with_id_free(dot, "pt1"), "pos") == "1.5000,3.5000!");

            // Locale-safe: a comma decimal separator would split the position
            // into two Graphviz attributes.
            string? previous = Intl.setlocale(LocaleCategory.NUMERIC, null);
            if (Intl.setlocale(LocaleCategory.NUMERIC, "de_AT.UTF-8") != null ||
                Intl.setlocale(LocaleCategory.NUMERIC, "de_DE.UTF-8") != null) {
                string local = new MermaidQuadrantRenderer(new Gvc.Context(), regions(), "neato").generate_dot(
                    new MermaidQuadrantParser().parse(
                        "quadrantChart\n    A: [0.25, 0.75] stroke-width: 2.5px\n"));
                assert(attr(line_with_id_free(local, "pt0"), "pos") == "1.5000,3.5000!");
                assert(attr(line_with_id_free(local, "pt0"), "penwidth") == "2.50");
                Intl.setlocale(LocaleCategory.NUMERIC, previous ?? "C");
            }
        }

        // The DOT line declaring node <name> (quadrant nodes carry no id=).
        private static string line_with_id_free(string dot, string name) {
            foreach (string line in dot.split("\n")) {
                if (line.strip().has_prefix(name + " [")) return line;
            }
            error("no node %s", name);
        }

        /**
         * A word longer than the column is hard-broken. Left whole it made its
         * card, and with it the whole column, as wide as the word.
         */
        public static void test_kanban_breaks_an_overlong_word() {
            string src = "kanban\n  todo[To Do]\n    t1[%s]\n    t2[short]\n";
            string wide = kanban_svg(src.printf("Averyveryverylongunbreakablewordthatneverwraps"));
            string narrow = kanban_svg(src.printf("short words only here"));
            assert(svg_width(wide) < svg_width(narrow) + 60);
            // The word is split, not dropped.
            assert(wide.contains("Averyveryveryl") && wide.contains("wraps"));
            // A multi-byte word is cut on character boundaries.
            string cjk = kanban_svg(src.printf("日本語日本語日本語日本語日本語日本語日本語日本語"));
            assert(cjk.contains("日本語"));
        }

        private static string kanban_svg(string src) {
            var d = new MermaidKanbanParser().parse(src);
            uint8[]? data = new MermaidKanbanRenderer(new Gvc.Context(), regions(), "dot").render_to_svg(d);
            assert(data != null);
            return (string) data;
        }

        private static double svg_width(string svg) {
            int i = svg.index_of("<svg width=\"");
            assert(i >= 0);
            return double.parse(svg.substring(i + 12));
        }

        /**
         * A `sankey`-prefixed *label* is data, not the diagram keyword, and a
         * short record is a parse error rather than a silent drop.
         */
        public static void test_sankey_keyword_only_on_the_header() {
            var d = new MermaidSankeyParser().parse("sankey-beta\nSankey Ltd,Revenue,100\nOther,Revenue,50\n");
            assert(!d.has_errors());
            assert(d.links.size == 2);
            assert(d.links.get(0).source == "Sankey Ltd" && d.links.get(0).value == 100);
            double revenue = 0;
            foreach (var l in d.links) if (l.target == "Revenue") revenue += l.value;
            assert(revenue == 150);

            var bad = new MermaidSankeyParser().parse("sankey-beta\nA,B\n");
            assert(bad.has_errors() && bad.errors.get(0).line == 2);
            assert(bad.links.size == 0);
            var empty_value = new MermaidSankeyParser().parse("sankey-beta\nA,B,\n");
            assert(empty_value.has_errors());
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/charts/xy-line-series", ReviewMermaidChartsTests.test_xy_line_series);
        Test.add_func("/charts/xy-axis-title-and-categories", ReviewMermaidChartsTests.test_xy_axis_title_and_categories);
        Test.add_func("/charts/xy-horizontal", ReviewMermaidChartsTests.test_xy_horizontal);
        Test.add_func("/charts/xy-tick-labels-on-ticks", ReviewMermaidChartsTests.test_xy_tick_labels_on_ticks);
        Test.add_func("/charts/xy-range-and-multiple-series", ReviewMermaidChartsTests.test_xy_range_and_multiple_series);
        Test.add_func("/charts/sankey-csv-quotes", ReviewMermaidChartsTests.test_sankey_csv_quotes);
        Test.add_func("/charts/sankey-distinct-node-ids", ReviewMermaidChartsTests.test_sankey_distinct_node_ids);
        Test.add_func("/charts/sankey-values", ReviewMermaidChartsTests.test_sankey_values);
        Test.add_func("/charts/sankey-front-matter-title", ReviewMermaidChartsTests.test_sankey_front_matter_title);
        Test.add_func("/charts/radar-axes-on-one-line", ReviewMermaidChartsTests.test_radar_axes_on_one_line);
        Test.add_func("/charts/radar-default-max", ReviewMermaidChartsTests.test_radar_default_max);
        Test.add_func("/charts/radar-legend", ReviewMermaidChartsTests.test_radar_legend);
        Test.add_func("/charts/radar-graticule", ReviewMermaidChartsTests.test_radar_graticule);
        Test.add_func("/charts/radar-curve-fills", ReviewMermaidChartsTests.test_radar_curve_fills);
        Test.add_func("/charts/treemap-areas", ReviewMermaidChartsTests.test_treemap_areas);
        Test.add_func("/charts/treemap-values-and-quotes", ReviewMermaidChartsTests.test_treemap_values_and_quotes);
        Test.add_func("/charts/treemap-class-def", ReviewMermaidChartsTests.test_treemap_class_def);
        Test.add_func("/charts/pie-show-data-values", ReviewMermaidChartsTests.test_pie_show_data_values);
        Test.add_func("/charts/pie-percentages-on-slices", ReviewMermaidChartsTests.test_pie_percentages_on_slices);
        Test.add_func("/charts/packet-widths-follow-bits", ReviewMermaidChartsTests.test_packet_widths_follow_bits);
        Test.add_func("/charts/packet-no-default-title", ReviewMermaidChartsTests.test_packet_no_default_title);
        Test.add_func("/charts/packet-single-bit-and-increment", ReviewMermaidChartsTests.test_packet_single_bit_and_increment);
        Test.add_func("/charts/quadrant-class-not-in-label", ReviewMermaidChartsTests.test_quadrant_class_not_in_label);
        Test.add_func("/charts/quadrant-point-styles", ReviewMermaidChartsTests.test_quadrant_point_styles);
        Test.add_func("/charts/timeline-events-on-one-line", ReviewMermaidChartsTests.test_timeline_events_on_one_line);
        Test.add_func("/charts/kanban-layout", ReviewMermaidChartsTests.test_kanban_layout);
        Test.add_func("/charts/userjourney-sections-group-tasks", ReviewMermaidChartsTests.test_userjourney_sections_group_tasks);
        Test.add_func("/charts/xy-degenerate-range-terminates", ReviewMermaidChartsTests.test_xy_degenerate_range_terminates);
        Test.add_func("/charts/xy-default-range-follows-data", ReviewMermaidChartsTests.test_xy_default_range_follows_the_data);
        Test.add_func("/charts/xy-extra-values-sliced", ReviewMermaidChartsTests.test_xy_extra_values_are_sliced_to_categories);
        Test.add_func("/charts/xy-legend", ReviewMermaidChartsTests.test_xy_legend_lists_titled_plots);
        Test.add_func("/charts/text-width-wide-glyphs", ReviewMermaidChartsTests.test_chart_text_width_measures_wide_glyphs);
        Test.add_func("/charts/treemap-zero-valued-nodes", ReviewMermaidChartsTests.test_treemap_keeps_zero_valued_nodes);
        Test.add_func("/charts/packet-invalid-and-oversized", ReviewMermaidChartsTests.test_packet_rejects_invalid_and_oversized_ranges);
        Test.add_func("/charts/pie-duplicates-and-exponents", ReviewMermaidChartsTests.test_pie_duplicate_labels_and_exponents);
        Test.add_func("/charts/pie-negative-exponent", ReviewMermaidChartsTests.test_pie_negative_exponent_is_not_an_arrow);
        Test.add_func("/charts/packet-contiguous-ranges", ReviewMermaidChartsTests.test_packet_ranges_must_be_contiguous);
        Test.add_func("/charts/quadrant-no-fixed-tmp", ReviewMermaidChartsTests.test_quadrant_render_does_not_touch_fixed_tmp_names);
        Test.add_func("/charts/quadrant-clamp-and-dots", ReviewMermaidChartsTests.test_quadrant_clamps_points_and_writes_dots);
        Test.add_func("/charts/kanban-overlong-word", ReviewMermaidChartsTests.test_kanban_breaks_an_overlong_word);
        Test.add_func("/charts/sankey-keyword-only-header", ReviewMermaidChartsTests.test_sankey_keyword_only_on_the_header);
        Test.add_func("/charts/xy-inverted-range", ReviewMermaidChartsTests.test_xy_inverted_range_is_normalised);
        Test.add_func("/charts/pie-all-zero", ReviewMermaidChartsTests.test_pie_all_zero_draws_no_slices);
        Test.add_func("/charts/packet-malformed-range", ReviewMermaidChartsTests.test_packet_rejects_a_malformed_range);
        return Test.run();
    }
}
