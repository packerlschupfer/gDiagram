namespace GDiagram.Tests {
    /**
     * Mermaid `wardley-beta` and `usecase-beta`: detection, parsing and drawn
     * geometry, asserted against mermaid 12.2.0's own output.
     *
     * The wardley expectations are the exact coordinates mermaid's SVG carries
     * for the two files in examples/mermaid/wardley, read out of a mmdc run
     * (mermaid 12.2.0, @mermaid-js/parser's wardley.langium). Mermaid's map is
     * 900 x 600 px with a 48 padding, and MermaidWardleyRenderer keeps those
     * numbers as points, so the two drawings are directly comparable rather
     * than merely proportional. Nothing here is a self-recorded snapshot.
     *
     * The usecase expectations are mermaid's model, not its layout: Graphviz
     * and dagre place nodes differently, so what is pinned is the inventory
     * mermaid builds (which id is an actor, which a use case, what shape, what
     * marker on which end of which edge, which boundary a member belongs to)
     * plus the parser's handling of the grammar's sharp edges.
     */
    public class MermaidWardleyUseCaseTests {

        private static Gee.ArrayList<ElementRegion> regions() {
            return new Gee.ArrayList<ElementRegion>();
        }

        private static bool near(double a, double b, double tol = 0.05) {
            return Math.fabs(a - b) <= tol;
        }

        // ==================== DOT readers ====================

        private static string? line_with_id(string dot, string id) {
            foreach (string line in dot.split("\n")) {
                if (line.contains("id=\"%s\"".printf(id))) return line;
            }
            return null;
        }

        private static string attr(string line, string name) {
            var re = /(?:^|\s|\[|,)([a-z_]+)=("[^"]*"|[^\s\],]+)/;
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

        // A pinned item's centre, converted back to top-left coordinates.
        // ChartCanvas emits Graphviz's bottom-up y, so y_top = page_h - y_dot.
        private class Geo {
            public double x;
            public double y;
            public double w;
            public double h;
        }

        private static Geo node(string dot, string id, double page_h) {
            string? line = line_with_id(dot, id);
            if (line == null) error("no pinned element id=\"%s\"", id);
            var g = new Geo();
            string[] xy = attr(line, "pos").split(",");
            g.x = double.parse(xy[0]);
            g.y = page_h - double.parse(xy[1]);
            g.w = double.parse(attr(line, "width")) * 72.0;
            g.h = double.parse(attr(line, "height")) * 72.0;
            return g;
        }

        // The first and last point of a pinned line's `pos` spline.
        private class Seg {
            public double x1;
            public double y1;
            public double x2;
            public double y2;
            public string line;
        }

        private static Seg? segment(string dot, string id, double page_h) {
            string? line = line_with_id(dot, id);
            if (line == null) return null;
            var s = new Seg();
            s.line = line;
            string[] pts = attr(line, "pos").split(" ");
            if (pts.length < 2) error("element id=\"%s\" is not a line", id);
            string[] a = pts[0].split(",");
            string[] b = pts[pts.length - 1].split(",");
            s.x1 = double.parse(a[0]);
            s.y1 = page_h - double.parse(a[1]);
            s.x2 = double.parse(b[0]);
            s.y2 = page_h - double.parse(b[1]);
            return s;
        }

        private static Seg need_segment(string dot, string id, double page_h) {
            var s = segment(dot, id, page_h);
            if (s == null) error("no pinned line id=\"%s\"", id);
            return s;
        }

        // The anchor a left-aligned ChartCanvas label was asked for: the node
        // is centred, and a plain label carries `\l` while a bold one is an
        // HTML cell 4pt wider than the measured box.
        private static double label_anchor(string dot, string id, double page_h) {
            string? line = line_with_id(dot, id);
            if (line == null) error("no label id=\"%s\"", id);
            var g = node(dot, id, page_h);
            bool bold = line.contains("<B>");
            double w = bold ? g.w - 4 : g.w;
            return g.x - w / 2;
        }

        // ==================== wardley sources ====================

        // examples/mermaid/wardley/tea-shop.mmd, trimmed to what is asserted.
        private const string TEA = """wardley-beta
title Tea Shop
evolution Genesis -> Custom Built -> Product / Rental -> Commodity
anchor Business [0.95, 0.63]
component Cup of Tea [0.79, 0.61] label [19, -4]
component Water [0.38, 0.82] (buy)
component Kettle [0.43, 0.35] label [-57, 4] (build)
component Power [0.10, 0.70] label [-27, 20] (outsource) inertia
Business->Cup of Tea
Cup of Tea->Water
Kettle->Power
evolve Kettle 0.62
note "Standardising power" [0.33, 0.73]
annotation 1, [0.43, 0.49] "Standardising power enables lower cost supply"
accelerator Electricity [0.60, 0.20]
deaccelerator Regulation [0.25, 0.15]
""";

        // examples/mermaid/wardley/pipeline-sourcing.mmd
        private const string PIPE = """wardley-beta
title Pipelines and sourcing
size [1000, 700]
evolution Novel @0.2 -> Emerging @0.45 -> Good @0.7 -> Best @1.0
anchor User [0.90, 0.20]
component Platform [0.70, 0.55]
component Compute [0.45, 0.85] (market)
component Billing [0.35, 0.40] label [8, 16]
pipeline Platform {
  component Runtime [0.40]
  component Scheduler [0.62]
  component Registry [0.80]
}
User->Platform
Platform +> Compute
Platform +<> Billing
Billing +'bills'< Compute
Compute -.-> Billing
evolve Billing 0.75
""";

        private static string wardley_dot(string src) {
            var engine = new DiagramEngine("dot");
            // ".mmd" matters: the extension decides the format before the
            // content does, and a ".puml" name would route this to PlantUML.
            string? dot = engine.generate_dot(src, "test.mmd", null);
            if (dot == null) error("wardley generate_dot returned null");
            return dot;
        }

        // ==================== wardley tests ====================

        public static void test_wardley_is_detected() {
            var engine = new DiagramEngine("dot");
            assert(engine.detect_mermaid_type(TEA) == DiagramType.MERMAID_WARDLEY);
            assert(engine.detect_mermaid_type("  wardley-beta\n") == DiagramType.MERMAID_WARDLEY);
            // Mermaid's detector is case-insensitive for wardley.
            assert(engine.detect_mermaid_type("WARDLEY-BETA\n") == DiagramType.MERMAID_WARDLEY);
            var r = engine.parse(TEA, "test.mmd");
            assert(r.diagram_type == DiagramType.MERMAID_WARDLEY);
            assert(r.ast is MermaidWardley);
            assert(r.errors.size == 0);
        }

        public static void test_wardley_coordinates_are_visibility_then_evolution() {
            var d = new MermaidWardleyParser().parse(TEA);
            assert(d.errors.size == 0);
            var kettle = d.find_node("Kettle");
            assert(kettle != null);
            // `[0.43, 0.35]` is [visibility, evolution]: y is the first number.
            assert(near(kettle.y, 43.0));
            assert(near(kettle.x, 35.0));
            // `label [-57, 4]`: the minus binds to the number that follows it.
            assert(kettle.label_offset_x != null && near(kettle.label_offset_x, -57.0));
            assert(kettle.label_offset_y != null && near(kettle.label_offset_y, 4.0));
            // `label [19, -4]` the other way round.
            var cup = d.find_node("Cup of Tea");
            assert(cup.label_offset_x != null && near(cup.label_offset_x, 19.0));
            assert(cup.label_offset_y != null && near(cup.label_offset_y, -4.0));
        }

        /**
         * The grammar names the annotation / accelerator fields `x` and `y`,
         * but wardleyParser.ts hands them to toCoordinates(visibility,
         * evolution), so they are ordered like every other coordinate.
         * Mermaid's SVG puts `annotation 1, [0.43, 0.49]` at (441.96, 335.28),
         * i.e. evolution 49% across and visibility 43% up — reading them as
         * (x, y) would place it at (393.72, 305.04).
         */
        public static void test_wardley_annotation_and_accelerator_axes_are_not_swapped() {
            string dot = wardley_dot(TEA);
            var ann = node(dot, "wardley_ann_0_0", 600);
            assert(near(ann.x, 441.96, 0.02));
            assert(near(ann.y, 335.28, 0.02));

            // `accelerator Electricity [0.60, 0.20]` -> evolution 20%,
            // visibility 60%; mermaid's block arrow starts at (208.8, 234.6).
            var first = need_segment(dot, "wardley_acc_0_0", 600);
            assert(near(first.x1, 208.8, 0.02));
            assert(near(first.y1, 234.6, 0.02));
            // The 60 x 30 body with a 20-wide head: seven closed segments.
            assert(near(first.x2, 248.8, 0.02));
            assert(segment(dot, "wardley_acc_0_6", 600) != null);
            assert(segment(dot, "wardley_acc_0_7", 600) == null);

            // `deaccelerator Regulation [0.25, 0.15]` points the other way:
            // the shaft starts at the right edge and the head is on the left.
            var dec = need_segment(dot, "wardley_acc_1_0", 600);
            assert(dec.x1 > dec.x2);
        }

        public static void test_wardley_axes_and_default_stages_match_mermaid() {
            // A bare keyword still draws the frame and mermaid's four default
            // stages, which is what mermaid renders for an empty map.
            string dot = wardley_dot("wardley-beta\n");
            var x_axis = need_segment(dot, "wardley_axis_x", 600);
            assert(near(x_axis.x1, 48.0) && near(x_axis.y1, 552.0));
            assert(near(x_axis.x2, 852.0) && near(x_axis.y2, 552.0));
            var y_axis = need_segment(dot, "wardley_axis_y", 600);
            assert(near(y_axis.x1, 48.0) && near(y_axis.y1, 48.0));
            assert(near(y_axis.y2, 552.0));

            // Genesis / Custom Built / Product / Commodity, quartered.
            for (int i = 0; i < 4; i++) {
                var lab = node(dot, "wardley_stage_%d".printf(i), 600);
                assert(near(lab.x, 48.0 + 804.0 * (i + 0.5) / 4.0, 0.02));
                assert(near(lab.y, 568.0, 0.02));
            }
            assert(line_with_id(dot, "wardley_stage_4") == null);
            // Dividers only between stages, dashed, full chart height.
            assert(line_with_id(dot, "wardley_stage_divider_0") == null);
            var div = need_segment(dot, "wardley_stage_divider_1", 600);
            assert(near(div.x1, 249.0, 0.02));
            assert(near(div.y1, 48.0) && near(div.y2, 552.0));
            assert(div.line.contains("style=dashed"));
        }

        public static void test_wardley_nodes_and_labels_match_mermaid() {
            string dot = wardley_dot(TEA);
            // Component circles, r = 6, at mermaid's own coordinates.
            var kettle = node(dot, "wardley_node_Kettle", 600);
            assert(near(kettle.x, 329.40, 0.02) && near(kettle.y, 335.28, 0.02));
            assert(near(kettle.w, 12.0, 0.02));
            var water = node(dot, "wardley_node_Water", 600);
            assert(near(water.x, 707.28, 0.02) && near(water.y, 360.48, 0.02));

            // An anchor has no circle, only a bold centred label at its point.
            assert(line_with_id(dot, "wardley_node_Business") == null);
            var business = node(dot, "wardley_label_Business", 600);
            assert(near(business.x, 554.52, 0.02));
            assert(near(business.y, 70.20, 0.02));   // pos.y - 3

            // A component's label is offset, left-aligned; the explicit
            // `label [-57, 4]` wins over the default (+8, -8), and a sourcing
            // decorator adds 10 only when no explicit offset was given.
            assert(near(label_anchor(dot, "wardley_label_Kettle", 600), 272.40, 0.02));
            assert(near(node(dot, "wardley_label_Kettle", 600).y, 339.28, 0.02));
            assert(near(label_anchor(dot, "wardley_label_Water", 600), 725.28, 0.02));
            assert(near(node(dot, "wardley_label_Water", 600).y, 342.48, 0.02));
        }

        public static void test_wardley_sourcing_overlays_and_inertia() {
            string dot = wardley_dot(TEA);
            // Each decorator is a circle of twice the node radius behind it.
            foreach (string name in new string[] { "Water", "Kettle", "Power" }) {
                var ov = node(dot, "wardley_overlay_" + name, 600);
                assert(near(ov.w, 24.0, 0.02));
            }
            // build -> #EEEEEE, buy -> #CCCCCC, outsource -> #666666
            assert(line_with_id(dot, "wardley_overlay_Kettle").contains("#EEEEEE"));
            assert(line_with_id(dot, "wardley_overlay_Water").contains("#CCCCCC"));
            assert(line_with_id(dot, "wardley_overlay_Power").contains("#666666"));

            // `inertia` is a 6pt bar to the right, pushed out a further
            // radius + 10 because Power also carries a decorator.
            var bar = need_segment(dot, "wardley_inertia_Power", 600);
            assert(near(bar.x1, 647.8, 0.02) && near(bar.x2, 647.8, 0.02));
            assert(near(bar.y1, 495.6, 0.02) && near(bar.y2, 507.6, 0.02));
            assert(bar.line.contains("penwidth=6"));
        }

        public static void test_wardley_links_are_clipped_at_the_node_edge() {
            string dot = wardley_dot(TEA);
            // Business -> Cup of Tea: mermaid shortens both ends by the node
            // radius along the link direction.
            var link = need_segment(dot, "wardley_link_0", 600);
            assert(near(link.x1, 553.35, 0.02) && near(link.y1, 79.08, 0.02));
            assert(near(link.x2, 539.61, 0.02) && near(link.y2, 147.96, 0.02));
            // A plain `->` carries no arrowhead at all.
            assert(line_with_id(dot, "wardley_link_0_end_a") == null);
            assert(line_with_id(dot, "wardley_link_0_start_a") == null);
            assert(!link.line.contains("style=dashed"));
        }

        public static void test_wardley_trend_is_a_dashed_arrow_at_the_same_visibility() {
            string dot = wardley_dot(TEA);
            // `evolve Kettle 0.62` keeps Kettle's visibility and stops a
            // radius + 2 short of the target.
            var trend = need_segment(dot, "wardley_trend_0", 600);
            assert(near(trend.x1, 329.40, 0.02) && near(trend.y1, 335.28, 0.02));
            assert(near(trend.x2, 538.48, 0.02) && near(trend.y2, 335.28, 0.02));
            assert(trend.line.contains("style=dashed"));
            assert(trend.line.contains("#DC3545"));
            // The arrowhead is drawn as two segments (Graphviz draws none on
            // the undirected edges ChartCanvas emits).
            assert(segment(dot, "wardley_trend_0_head_a", 600) != null);
            assert(segment(dot, "wardley_trend_0_head_b", 600) != null);
        }

        public static void test_wardley_pipeline_band_and_parent_square() {
            string dot = wardley_dot(PIPE);
            // `size [1000, 700]`
            var x_axis = need_segment(dot, "wardley_axis_x", 700);
            assert(near(x_axis.x2, 952.0, 0.02));
            assert(near(x_axis.y1, 652.0, 0.02));

            // The box spans the children with a 15 padding and is 4 radii tall.
            var box = node(dot, "wardley_pipeline_0", 700);
            assert(near(box.x - box.w / 2, 394.60, 0.02));
            assert(near(box.y - box.h / 2, 217.20, 0.02));
            assert(near(box.w, 391.60, 0.02));
            assert(near(box.h, 24.0, 0.02));

            // Children are chained left to right with a dotted line.
            var chain = need_segment(dot, "wardley_pipe_link_0_0", 700);
            assert(near(chain.x1, 409.60, 0.02) && near(chain.x2, 608.48, 0.02));
            assert(near(chain.y1, 229.20, 0.02) && near(chain.y2, 229.20, 0.02));
            assert(chain.line.contains("style=dotted"));
            assert(segment(dot, "wardley_pipe_link_0_1", 700) != null);
            assert(segment(dot, "wardley_pipe_link_0_2", 700) == null);

            // The parent becomes a 9.6 square recentred on the band's top edge
            // (two thirds above it), not a circle at its own coordinate.
            assert(line_with_id(dot, "wardley_node_Platform") == null);
            var square = node(dot, "wardley_parent_Platform", 700);
            assert(near(square.x - square.w / 2, 585.60, 0.02));
            assert(near(square.y - square.h / 2, 210.80, 0.02));
            assert(near(square.w, 9.6, 0.02) && near(square.h, 9.6, 0.02));
        }

        public static void test_wardley_custom_stage_boundaries_are_honoured() {
            string dot = wardley_dot(PIPE);
            // `@0.2 / @0.45 / @0.7 / @1.0` are fractions of the chart width
            // (1000 - 96 = 904), so the dividers are not evenly spaced.
            assert(near(need_segment(dot, "wardley_stage_divider_1", 700).x1, 228.80, 0.02));
            assert(near(need_segment(dot, "wardley_stage_divider_2", 700).x1, 454.80, 0.02));
            assert(near(need_segment(dot, "wardley_stage_divider_3", 700).x1, 680.80, 0.02));
            // The boundary number is stripped off the stage name, and a
            // `A / B` stage keeps both halves.
            var d = new MermaidWardleyParser().parse(PIPE);
            assert(d.stages.size == 4);
            assert(d.stages.get(0) == "Novel");
            assert(d.stages.get(3) == "Best");
            assert(d.stage_boundaries.size == 4);
            assert(near(d.stage_boundaries.get(1), 0.45));
            var tea = new MermaidWardleyParser().parse(TEA);
            assert(tea.stages.get(2) == "Product / Rental");
            assert(tea.stage_boundaries.size == 0);
        }

        public static void test_wardley_flow_ports_and_dashed_links() {
            string dot = wardley_dot(PIPE);
            var d = new MermaidWardleyParser().parse(PIPE);
            assert(d.errors.size == 0);
            assert(d.links.size == 5);
            // `User->Platform` plain, `+>` forward, `+<>` both,
            // `+'bills'<` backward with a label, `-.->` dashed and unmarked.
            assert(d.links.get(0).flow == WardleyFlow.NONE);
            assert(d.links.get(1).flow == WardleyFlow.FORWARD);
            assert(d.links.get(2).flow == WardleyFlow.BIDIRECTIONAL);
            assert(d.links.get(3).flow == WardleyFlow.BACKWARD);
            assert(d.links.get(3).label == "bills");
            assert(d.links.get(4).flow == WardleyFlow.NONE);
            assert(d.links.get(4).dashed);

            // One chevron per marked end, two for the bidirectional link.
            assert(line_with_id(dot, "wardley_link_1_end_a") != null);
            assert(line_with_id(dot, "wardley_link_1_start_a") == null);
            assert(line_with_id(dot, "wardley_link_2_end_a") != null);
            assert(line_with_id(dot, "wardley_link_2_start_a") != null);
            assert(line_with_id(dot, "wardley_link_3_start_a") != null);
            assert(line_with_id(dot, "wardley_link_3_end_a") == null);
            assert(need_segment(dot, "wardley_link_4", 700).line.contains("style=dashed"));
            // The label sits 8 off the link's perpendicular at its midpoint.
            var lab = node(dot, "wardley_link_label_3", 700);
            assert(near(lab.x, 611.83, 0.05) && near(lab.y, 402.49, 0.05));
        }

        public static void test_wardley_market_decorator_draws_three_dots() {
            string dot = wardley_dot(PIPE);
            // The three dots sit on a circle of 1.2 radii, r = 0.7 radii.
            var top = node(dot, "wardley_market_t_Compute", 700);
            assert(near(top.w, 8.4, 0.02));
            assert(near(top.x, 816.40, 0.02) && near(top.y, 373.00, 0.02));
            var left = node(dot, "wardley_market_l_Compute", 700);
            assert(near(left.x, 810.16, 0.02) && near(left.y, 383.80, 0.02));
            var right = node(dot, "wardley_market_r_Compute", 700);
            assert(near(right.x, 822.64, 0.02) && near(right.y, 383.80, 0.02));
            // A market component gets the wide outer ring, not the plain circle.
            assert(line_with_id(dot, "wardley_node_Compute") == null);
            assert(near(node(dot, "wardley_overlay_Compute", 700).w, 24.0, 0.02));
        }

        public static void test_wardley_numbers_are_written_c_style() {
            // A comma-decimal locale must not leak into the DOT: Graphviz
            // rejects `pos="329,40,264"`.
            string saved = Intl.setlocale(LocaleCategory.NUMERIC, null);
            string? got = Intl.setlocale(LocaleCategory.NUMERIC, "de_DE.UTF-8");
            if (got == null) {
                got = Intl.setlocale(LocaleCategory.NUMERIC, "de_DE");
            }
            if (got == null) {
                Intl.setlocale(LocaleCategory.NUMERIC, saved);
                Test.skip("no comma-decimal locale on this system");
                return;
            }
            string dot = wardley_dot(TEA);
            Intl.setlocale(LocaleCategory.NUMERIC, saved);

            // Every pos/width/height must use a dot, and no coordinate pair may
            // have grown a third component from a decimal comma.
            foreach (string line in dot.split("\n")) {
                int p = line.index_of("pos=\"");
                if (p < 0) continue;
                int e = line.index_of_char('"', p + 5);
                string pos = line.substring(p + 5, e - p - 5);
                foreach (string point in pos.split(" ")) {
                    assert(point.split(",").length == 2);
                }
            }
            // And the parse of a decimal coordinate is locale-independent.
            assert(dot.contains("wardley_node_Kettle"));
            var k = node(dot, "wardley_node_Kettle", 600);
            assert(near(k.x, 329.40, 0.02));
        }

        public static void test_wardley_click_regions_follow_the_source() {
            var ctx = new Gvc.Context();
            var r = regions();
            var d = new MermaidWardleyParser().parse(TEA);
            assert(new MermaidWardleyRenderer(ctx, r, "dot").render_to_surface(d) != null);

            var kettle = find_region(r, "Kettle");
            assert(kettle != null);
            assert(kettle.width > 0 && kettle.height > 0);
            // `component Kettle …` is line 7 of TEA.
            assert(kettle.source_line == 7);
            var business = find_region(r, "Business");
            assert(business != null && business.source_line == 4);
            // Water is to the right of Kettle on the map, as its evolution says.
            var water = find_region(r, "Water");
            assert(water != null && water.x > kettle.x);
        }

        private static ElementRegion? find_region(Gee.ArrayList<ElementRegion> list, string name) {
            foreach (var reg in list) {
                if (reg.name == name) return reg;
            }
            return null;
        }

        public static void test_wardley_bad_coordinates_are_reported() {
            // mermaid's toPercent rejects anything outside 0-1 or 0-100.
            var d = new MermaidWardleyParser().parse(
                "wardley-beta\ncomponent Bad [120, 0.5]\n");
            assert(d.errors.size == 1);
            assert(d.errors.get(0).line == 2);
            assert(d.errors.get(0).message.contains("between 0-1"));
            assert(d.find_node("Bad") == null);

            // An unknown statement is an error, not a silent drop.
            var e = new MermaidWardleyParser().parse("wardley-beta\nnonsense here\n");
            assert(e.errors.size == 1);
            assert(e.errors.get(0).message.contains("Unrecognised"));

            // An `evolve` for a component that does not exist cannot be placed.
            var f = new MermaidWardleyParser().parse("wardley-beta\nevolve Ghost 0.5\n");
            assert(f.trends.size == 0);
            assert(f.errors.size == 1);
            assert(f.errors.get(0).message.contains("unknown component"));
        }

        // Every format writes a non-empty file through the engine's own
        // export dispatch, which is where a missing case would show up.
        private static void check_exports(string src, string stem) {
            var engine = new DiagramEngine("dot");
            string dir;
            try {
                dir = DirUtils.make_tmp(stem + "XXXXXX");
            } catch (FileError e) {
                error("%s", e.message);
            }
            string png = Path.build_filename(dir, "d.png");
            string svg = Path.build_filename(dir, "d.svg");
            string pdf = Path.build_filename(dir, "d.pdf");
            assert(engine.export_to_png(src, "test.mmd", null, png));
            assert(engine.export_to_svg(src, "test.mmd", null, svg));
            assert(engine.export_to_pdf(src, "test.mmd", null, pdf));
            foreach (string p in new string[] { png, svg, pdf }) {
                assert(FileUtils.test(p, FileTest.EXISTS));
                int64 size = 0;
                try {
                    size = File.new_for_path(p).query_info("*", 0).get_size();
                } catch (Error e) {
                    error("%s", e.message);
                }
                assert(size > 0);
                FileUtils.unlink(p);
            }
            DirUtils.remove(dir);
        }

        public static void test_wardley_exports_every_format() {
            check_exports(TEA, "gdwardley");
        }

        // ==================== usecase sources ====================

        // examples/mermaid/usecase/library-system.mmd
        private const string LIB = """usecase-beta
accTitle: Library lending
direction LR
actor Member
actor Librarian@{ type: hollow }
systemBoundary Library[Library system]
  Borrow(Borrow a book)
  Return(Return a book)
  Fine[Pay a fine]
end
Member -- requests --> Borrow
Member --> Return
Librarian --o Fine
Return ..>: include Fine
Borrow --|> Return
note for Borrow "Max 5 books per member"
classDef critical fill:#f96,stroke:#333
class Fine critical
""";

        // examples/mermaid/usecase/account-admin.mmd
        private const string ADMIN = """usecase-beta
direction TB
actor Admin, Guest
actor Robot@{ icon: "fa:fa-robot" }
actor "Main Admin"
Maintain(Maintain system)@{ business: true }
Delete(Delete account)<<danger>>:::critical
Archive[Archive account]
json config @{ "retries": 3, "mode": "safe" }
Admin e1@--> Maintain
e1@{ animation: slow }
Guest x-- Delete
Robot o-- Archive
Archive <-- restores -- Delete
Main_Admin --- Maintain
Delete --x Archive
Admin --> config
classDef critical fill:#f96,stroke:#333
class Archive critical
""";

        private static string usecase_dot(string src) {
            var engine = new DiagramEngine("dot");
            string? dot = engine.generate_dot(src, "test.mmd", null);
            if (dot == null) error("usecase generate_dot returned null");
            return dot;
        }

        // The DOT statement that declares node `id`.
        private static string node_line(string dot, string id) {
            foreach (string line in dot.split("\n")) {
                string t = line.strip();
                if (t.has_prefix(id + " [")) return t;
            }
            error("no node %s in the usecase DOT", id);
        }

        private static string edge_line(string dot, string from, string to) {
            foreach (string line in dot.split("\n")) {
                string t = line.strip();
                if (t.has_prefix("%s -> %s [".printf(from, to))) return t;
            }
            error("no edge %s -> %s in the usecase DOT", from, to);
        }

        // ==================== usecase tests ====================

        public static void test_usecase_is_detected() {
            var engine = new DiagramEngine("dot");
            assert(engine.detect_mermaid_type(LIB) == DiagramType.MERMAID_USECASE);
            assert(engine.detect_mermaid_type("  usecase-beta\nactor A\n") == DiagramType.MERMAID_USECASE);
            var r = engine.parse(LIB, "test.mmd");
            assert(r.diagram_type == DiagramType.MERMAID_USECASE);
            assert(r.ast is MermaidUseCase);
            assert(r.errors.size == 0);
        }

        /**
         * The model mermaid builds for library-system.mmd, read from the
         * `data-usecase-id` / `data-usecase-kind` attributes of its SVG:
         * actors Member and Librarian, boundary Library holding Borrow, Return
         * and Fine, and five relationships edge-0..edge-4.
         */
        public static void test_usecase_model_matches_mermaid() {
            var d = new MermaidUseCaseParser().parse(LIB);
            assert(d.errors.size == 0);
            assert(d.direction == "LR");
            assert(d.acc_title == "Library lending");

            assert(d.actors.size == 2);
            assert(d.find_actor("Member") != null);
            assert(d.find_actor("Librarian").actor_type == MermaidActorType.HOLLOW);
            assert(d.find_actor("Member").actor_type == MermaidActorType.NORMAL);

            assert(d.use_cases.size == 3);
            // `(Label)` is an ellipse, `[Label]` a rectangle.
            assert(d.find_use_case("Borrow").shape == MermaidUseCaseShape.ELLIPSE);
            assert(d.find_use_case("Borrow").label == "Borrow a book");
            assert(d.find_use_case("Fine").shape == MermaidUseCaseShape.RECT);

            assert(d.boundaries.size == 1);
            var b = d.find_boundary("Library");
            assert(b.label == "Library system");
            assert(b.boundary_type == MermaidBoundaryType.RECT);
            assert(b.members.size == 3);
            assert(b.members.contains("Borrow") && b.members.contains("Fine"));
            assert(d.find_use_case("Fine").parent_id == "Library");

            assert(d.relations.size == 5);
            assert(d.relations.get(0).id == "edge-0");
            assert(d.relations.get(4).id == "edge-4");
            assert(d.notes.size == 1);
            assert(d.notes.get(0).id == "note-0");
            assert(d.notes.get(0).target == "Borrow");
            assert(d.notes.get(0).label == "Max 5 books per member");
            assert(d.find_use_case("Fine").classes.contains("critical"));
        }

        /**
         * Edge labels have exactly one form in mermaid's grammar, the sandwich
         * `A -- label --> B`. There is no `A --> B : label`.
         */
        public static void test_usecase_edge_label_is_the_sandwich_form() {
            var d = new MermaidUseCaseParser().parse(LIB);
            var rel = d.relations.get(0);
            assert(rel.source == "Member" && rel.target == "Borrow");
            assert(rel.label == "requests");
            assert(rel.arrow == MermaidUseCaseArrow.SOLID_ARROW);

            // `A --> B : uses` is not a label; the colon is unexpected text.
            var bad = new MermaidUseCaseParser().parse("usecase-beta\nA --> B : uses\n");
            assert(bad.errors.size > 0);
            bool complained = false;
            foreach (var e in bad.errors) {
                if (e.message.contains("unexpected text")) complained = true;
            }
            assert(complained);
            foreach (var r in bad.relations) {
                assert(r.label == null);
            }
        }

        /**
         * mermaid's own ambiguity: `A -- B --> C` is A to C labelled "B", not a
         * chain through a node B, because the lookahead finds the closing
         * operator past the label.
         */
        public static void test_usecase_bare_label_between_operators_is_a_label() {
            var d = new MermaidUseCaseParser().parse("usecase-beta\nactor A\nA -- B --> C\n");
            assert(d.errors.size == 0);
            assert(d.relations.size == 1);
            assert(d.relations.get(0).source == "A");
            assert(d.relations.get(0).target == "C");
            assert(d.relations.get(0).label == "B");
            assert(d.find_use_case("B") == null);
            assert(d.find_use_case("C") != null);
            // A bare `A -- B` with nothing after it really is an edge to B.
            var e = new MermaidUseCaseParser().parse("usecase-beta\nactor A\nA -- B\n");
            assert(e.relations.size == 1);
            assert(e.relations.get(0).target == "B");
            assert(e.relations.get(0).label == null);
            assert(e.relations.get(0).arrow == MermaidUseCaseArrow.LINE_SOLID);
        }

        /**
         * Every arrow form, with the marker end mermaid draws it on. Taken from
         * the `marker-start` / `marker-end` of each `usecase-my-svg-edge-N`
         * path in mermaid's SVG for account-admin.mmd: crossStart, circleStart,
         * pointStart, no marker, crossEnd, pointEnd.
         */
        public static void test_usecase_every_arrow_form() {
            var d = new MermaidUseCaseParser().parse(ADMIN);
            assert(d.errors.size == 0);
            assert(d.relations.size == 7);

            var e1 = d.relations.get(0);
            assert(e1.id == "e1" && e1.explicit_id);
            assert(e1.arrow == MermaidUseCaseArrow.SOLID_ARROW);
            // `e1@{ animation: slow }` reaches the edge it names.
            assert(e1.animation == "slow" && e1.animate);

            assert(d.relations.get(1).arrow == MermaidUseCaseArrow.CROSS_ARROW_REVERSED);
            assert(d.relations.get(2).arrow == MermaidUseCaseArrow.CIRCLE_ARROW_REVERSED);
            var back = d.relations.get(3);
            assert(back.arrow == MermaidUseCaseArrow.BACK_ARROW);
            assert(back.label == "restores");
            var plain = d.relations.get(4);
            assert(plain.arrow == MermaidUseCaseArrow.LINE_SOLID);
            // `---` is minlen 2 (dashes - 1); `--` would be 1.
            assert(plain.minlen == 2);
            assert(d.relations.get(5).arrow == MermaidUseCaseArrow.CROSS_ARROW);
            assert(d.relations.get(6).arrow == MermaidUseCaseArrow.SOLID_ARROW);

            string dot = usecase_dot(ADMIN);
            assert(edge_line(dot, "Admin", "Maintain").contains("arrowhead=normal"));
            // A reversed marker is dir=back with the marker on the tail.
            string g = edge_line(dot, "Guest", "Delete");
            assert(g.contains("dir=back") && g.contains("arrowtail=obox"));
            // Graphviz has no cross arrowhead: an obox placeholder marked
            // gdfcross, which MermaidFlowchartRenderer.draw_crosses redraws.
            assert(g.contains("gdfcross"));
            assert(edge_line(dot, "Robot", "Archive").contains("arrowtail=dot"));
            assert(edge_line(dot, "Archive", "Delete").contains("arrowtail=normal"));
            assert(edge_line(dot, "Main_Admin", "Maintain").contains("arrowhead=none"));
            assert(edge_line(dot, "Main_Admin", "Maintain").contains("minlen=2"));
            assert(edge_line(dot, "Delete", "Archive").contains("arrowhead=obox"));
        }

        /**
         * `A ..>: include B` / `..>: extend B`, the only include/extend form.
         * `<<include>>` is a node stereotype in this grammar, never an arrow.
         */
        public static void test_usecase_include_and_extend() {
            var d = new MermaidUseCaseParser().parse(LIB);
            var inc = d.relations.get(3);
            assert(inc.kind == MermaidUseCaseRelationKind.INCLUDE);
            assert(inc.source == "Return" && inc.target == "Fine");
            // mermaid labels the edge with the keyword itself.
            assert(inc.label == "include");
            var gen = d.relations.get(4);
            assert(gen.kind == MermaidUseCaseRelationKind.GENERALIZATION);

            string dot = usecase_dot(LIB);
            string line = edge_line(dot, "Return", "Fine");
            assert(line.contains("style=dashed"));
            assert(line.contains("label=\"include\""));
            // A generalization is the hollow UML triangle.
            assert(edge_line(dot, "Borrow", "Return").contains("arrowhead=empty"));

            var ext = new MermaidUseCaseParser().parse(
                "usecase-beta\nA(a)\nB(b)\nA ..>: EXTEND B\n");
            assert(ext.errors.size == 0);
            assert(ext.relations.get(0).kind == MermaidUseCaseRelationKind.EXTEND);
            // The keyword is case-insensitive but stored lower case.
            assert(ext.relations.get(0).label == "extend");

            // include/extend need a use case on both ends.
            var bad = new MermaidUseCaseParser().parse(
                "usecase-beta\nactor A\nB(b)\nA ..>: include B\n");
            bool complained = false;
            foreach (var e in bad.errors) {
                if (e.message.contains("include/extend require")) complained = true;
            }
            assert(complained);
        }

        public static void test_usecase_quoted_names_generate_ids() {
            var d = new MermaidUseCaseParser().parse(ADMIN);
            // `actor "Main Admin"` -> id Main_Admin, label "Main Admin".
            var a = d.find_actor("Main_Admin");
            assert(a != null);
            assert(a.label == "Main Admin");
            // The generated id is what a later relation refers to.
            assert(d.relations.get(4).source == "Main_Admin");

            // `actor Admin, Guest` declares both.
            assert(d.find_actor("Admin") != null && d.find_actor("Guest") != null);
            // An `icon:` property implies the icon actor type.
            assert(d.find_actor("Robot").actor_type == MermaidActorType.ICON);
            assert(d.find_actor("Robot").icon == "fa:fa-robot");
            // `@{ business: true }` and `<<stereotype>>` / `:::class`.
            assert(d.find_use_case("Maintain").business);
            assert(d.find_use_case("Delete").stereotype == "danger");
            assert(d.find_use_case("Delete").classes.contains("critical"));
            // A json node is its own kind, with its top-level keys kept in order.
            var j = d.find_json("config");
            assert(j != null);
            assert(j.keys.size == 2);
            assert(j.keys.get(0) == "retries" && j.values.get(0) == "3");
            assert(j.keys.get(1) == "mode");
        }

        public static void test_usecase_dot_shapes_and_boundary_cluster() {
            string dot = usecase_dot(LIB);
            assert(dot.contains("rankdir=LR"));
            // An actor is the shared stick-figure node: an HTML label whose
            // sentinel cell RenderUtils.draw_actor_figures replaces.
            string member = node_line(dot, "Member");
            assert(member.contains("gdactor"));
            assert(member.contains("#010203"));
            assert(node_line(dot, "Librarian").contains("gdhollow"));

            assert(node_line(dot, "Borrow").contains("shape=ellipse"));
            assert(node_line(dot, "Fine").contains("shape=box"));
            // `classDef critical fill:#f96,stroke:#333` reaches the node.
            assert(node_line(dot, "Fine").contains("fillcolor=\"#f96\""));
            assert(node_line(dot, "Fine").contains("color=\"#333\""));

            // The boundary is a cluster holding its three members.
            assert(dot.contains("subgraph cluster_0 {"));
            int cluster = dot.index_of("subgraph cluster_0 {");
            int close = dot.index_of("\n  }", cluster);
            string body = dot.substring(cluster, close - cluster);
            assert(body.contains("label=\"Library system\""));
            assert(body.contains("Borrow [") && body.contains("Return [") && body.contains("Fine ["));
            assert(!body.contains("Member ["));

            // A note is a dotted, markerless edge to its target.
            assert(dot.contains("shape=note"));
            assert(edge_line(dot, "_ucnote_note_0", "Borrow").contains("arrowhead=none"));
        }

        public static void test_usecase_direction_tb_and_rl() {
            assert(usecase_dot(ADMIN).contains("rankdir=TB"));
            // mermaid normalises TD to TB.
            var d = new MermaidUseCaseParser().parse("usecase-beta\ndirection TD\nA(a)\n");
            assert(d.direction == "TB");
            assert(usecase_dot("usecase-beta\ndirection RL\nA(a)\n").contains("rankdir=RL"));
            // No `direction` at all is LR, not TB.
            assert(new MermaidUseCaseParser().parse("usecase-beta\nA(a)\n").direction == "LR");
            var bad = new MermaidUseCaseParser().parse("usecase-beta\ndirection sideways\nA(a)\n");
            assert(bad.errors.size == 1);
            assert(bad.direction == "LR");
        }

        public static void test_usecase_rejects_plantuml_and_bad_metadata() {
            // A pasted PlantUML statement must fail loudly, not become a node.
            var d = new MermaidUseCaseParser().parse("usecase-beta\nrectangle Sys {\n");
            assert(d.errors.size > 0);
            assert(d.find_use_case("rectangle") == null);

            // Only type / icon / business / animate / animation exist.
            var e = new MermaidUseCaseParser().parse("usecase-beta\nA(a)@{ shape: hexagon }\n");
            assert(e.errors.size == 1);
            assert(e.errors.get(0).message.contains("is invalid for usecase"));

            // A boundary that is never closed is reported.
            var f = new MermaidUseCaseParser().parse("usecase-beta\nsystemBoundary S\n  A(a)\n");
            bool complained = false;
            foreach (var err in f.errors) {
                if (err.message.contains("never closed")) complained = true;
            }
            assert(complained);

            // A boundary id is not a relation endpoint.
            var g = new MermaidUseCaseParser().parse(
                "usecase-beta\nsystemBoundary S\n  A(a)\nend\nactor B\nB --> S\n");
            complained = false;
            foreach (var err in g.errors) {
                if (err.message.contains("cannot be a relation endpoint")) complained = true;
            }
            assert(complained);
        }

        public static void test_usecase_click_regions_follow_the_source() {
            var ctx = new Gvc.Context();
            var r = regions();
            var d = new MermaidUseCaseParser().parse(LIB);
            assert(new MermaidUseCaseRenderer(ctx, r, "dot").render_to_surface(d) != null);

            var borrow = find_region(r, "Borrow");
            assert(borrow != null);
            assert(borrow.width > 0 && borrow.height > 0);
            assert(borrow.source_line == 7);
            var member = find_region(r, "Member");
            assert(member != null && member.source_line == 4);
            // The boundary cluster is clickable under its own name, and its
            // frame is bigger than the member inside it.
            var library = find_region(r, "Library");
            assert(library != null && library.source_line == 6);
            assert(library.width > borrow.width);
        }

        public static void test_usecase_exports_every_format() {
            check_exports(LIB, "gdusecase");
        }

        /**
         * The stats / lint / validate wiring DocumentView drives after every
         * render. All three are display-free, so they are asserted here rather
         * than left to the GUI suites: a missing case would silently fall
         * through to a generic "N elements" footer and an empty lint list.
         */
        public static void test_stats_lint_and_validate_are_wired() {
            var wardley = new MermaidWardleyParser().parse(TEA);
            var ws = new DiagramStats();
            ws.analyze_mermaid_wardley(wardley, TEA);
            assert(ws.diagram_type == "Mermaid Wardley Map");
            assert(ws.node_count == wardley.nodes.size);
            assert(ws.edge_count == wardley.links.size + wardley.trends.size);
            // The footer must name components and links, not fall through to
            // the generic "%d elements" default.
            assert(ws.get_quick_stats() == "%d components, %d links".printf(
                wardley.nodes.size, wardley.links.size + wardley.trends.size));

            var usecase = new MermaidUseCaseParser().parse(LIB);
            var us = new DiagramStats();
            us.analyze_mermaid_usecase(usecase, LIB);
            assert(us.diagram_type == "Mermaid Use Case");
            assert(us.node_count == usecase.actors.size + usecase.use_cases.size);
            assert(us.edge_count == usecase.relations.size);
            assert(us.get_quick_stats() == "%d elements, %d relations".printf(
                us.node_count, us.edge_count));

            // A map with no anchor and no links is worth two lint remarks.
            var linter = new DiagramLinter();
            linter.lint_wardley(new MermaidWardleyParser().parse(
                "wardley-beta\ncomponent A [0.5, 0.5]\ncomponent B [0.2, 0.2]\n"));
            bool no_anchor = false, no_links = false;
            foreach (var m in linter.messages) {
                if (m.message.contains("no anchor")) no_anchor = true;
                if (m.message.contains("no links")) no_links = true;
            }
            assert(no_anchor && no_links);
            // The shipped example has an anchor and links, so neither fires.
            linter.lint_wardley(wardley);
            foreach (var m in linter.messages) {
                assert(!m.message.contains("no anchor"));
                assert(!m.message.contains("no links"));
            }

            var ul = new DiagramLinter();
            ul.lint_usecase_mermaid(new MermaidUseCaseParser().parse(
                "usecase-beta\nLonely(On its own)\n"));
            bool actorless = false, unconnected = false;
            foreach (var m in ul.messages) {
                if (m.message.contains("no actors")) actorless = true;
                if (m.message.contains("not connected")) unconnected = true;
            }
            assert(actorless && unconnected);

            // The validator surfaces the parser's errors, and a link naming an
            // undeclared component.
            var wv = new DiagramValidator();
            wv.validate_wardley(new MermaidWardleyParser().parse(
                "wardley-beta\ncomponent A [0.5, 0.5]\nA->Ghost\n"));
            bool ghost = false;
            foreach (var m in wv.messages) {
                if (m.message.contains("Ghost")) ghost = true;
            }
            assert(ghost);
            wv.validate_wardley(wardley);
            foreach (var m in wv.messages) {
                assert(m.severity != ValidationMessage.Severity.ERROR);
            }

            var uv = new DiagramValidator();
            uv.validate_usecase_mermaid(new MermaidUseCaseParser().parse(
                "usecase-beta\nA(a)\nnote for Nobody \"hi\"\n"));
            bool nobody = false;
            foreach (var m in uv.messages) {
                if (m.message.contains("Nobody")) nobody = true;
            }
            assert(nobody);
            uv.validate_usecase_mermaid(usecase);
            foreach (var m in uv.messages) {
                assert(m.severity != ValidationMessage.Severity.ERROR);
            }
        }

        // The SVG really carries the stick figures and the redrawn crosses,
        // not just the placeholders the DOT asks for.
        public static void test_usecase_svg_has_figures_and_crosses() {
            var ctx = new Gvc.Context();
            var d = new MermaidUseCaseParser().parse(ADMIN);
            uint8[]? svg = new MermaidUseCaseRenderer(ctx, regions(), "dot").render_to_svg(d);
            assert(svg != null);
            var sb = new StringBuilder.sized(svg.length + 1);
            sb.append_len((string) svg, svg.length);
            string text = sb.str;
            // Four actors, each figure drawn from its sentinel cell.
            assert(text.contains("gdfigure"));
            assert(!text.contains("#010203"));
            // Two cross ends (`x--` and `--x`) became gdmark x paths.
            int marks = 0;
            int at = 0;
            while (true) {
                at = text.index_of("class=\"gdmark\"", at);
                if (at < 0) break;
                marks++;
                at += 5;
            }
            assert(marks == 2);
        }
    }
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/wardley/detect", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_is_detected);
    Test.add_func("/wardley/coordinate-order", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_coordinates_are_visibility_then_evolution);
    Test.add_func("/wardley/annotation-axes", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_annotation_and_accelerator_axes_are_not_swapped);
    Test.add_func("/wardley/axes-and-stages", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_axes_and_default_stages_match_mermaid);
    Test.add_func("/wardley/nodes-and-labels", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_nodes_and_labels_match_mermaid);
    Test.add_func("/wardley/sourcing-and-inertia", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_sourcing_overlays_and_inertia);
    Test.add_func("/wardley/link-clipping", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_links_are_clipped_at_the_node_edge);
    Test.add_func("/wardley/trend", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_trend_is_a_dashed_arrow_at_the_same_visibility);
    Test.add_func("/wardley/pipeline", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_pipeline_band_and_parent_square);
    Test.add_func("/wardley/stage-boundaries", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_custom_stage_boundaries_are_honoured);
    Test.add_func("/wardley/flow-ports", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_flow_ports_and_dashed_links);
    Test.add_func("/wardley/market", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_market_decorator_draws_three_dots);
    Test.add_func("/wardley/locale", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_numbers_are_written_c_style);
    Test.add_func("/wardley/click-regions", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_click_regions_follow_the_source);
    Test.add_func("/wardley/errors", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_bad_coordinates_are_reported);
    Test.add_func("/wardley/exports", GDiagram.Tests.MermaidWardleyUseCaseTests.test_wardley_exports_every_format);
    Test.add_func("/usecase/detect", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_is_detected);
    Test.add_func("/usecase/model", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_model_matches_mermaid);
    Test.add_func("/usecase/edge-label", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_edge_label_is_the_sandwich_form);
    Test.add_func("/usecase/label-ambiguity", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_bare_label_between_operators_is_a_label);
    Test.add_func("/usecase/arrow-forms", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_every_arrow_form);
    Test.add_func("/usecase/include-extend", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_include_and_extend);
    Test.add_func("/usecase/generated-ids", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_quoted_names_generate_ids);
    Test.add_func("/usecase/dot-shapes", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_dot_shapes_and_boundary_cluster);
    Test.add_func("/usecase/direction", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_direction_tb_and_rl);
    Test.add_func("/usecase/errors", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_rejects_plantuml_and_bad_metadata);
    Test.add_func("/usecase/click-regions", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_click_regions_follow_the_source);
    Test.add_func("/usecase/exports", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_exports_every_format);
    Test.add_func("/usecase/svg-figures", GDiagram.Tests.MermaidWardleyUseCaseTests.test_usecase_svg_has_figures_and_crosses);
    Test.add_func("/wardley-usecase/stats-lint-validate", GDiagram.Tests.MermaidWardleyUseCaseTests.test_stats_lint_and_validate_are_wired);
    return Test.run();
}
