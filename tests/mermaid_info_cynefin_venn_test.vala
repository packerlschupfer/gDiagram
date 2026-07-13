/*
 * mermaid_info_cynefin_venn_test.vala — the three Mermaid 12.2.0 diagram types
 * added after the v0.1.0 release: `info`, `cynefin-beta` and `venn-beta`.
 *
 * Every grammar assertion is taken from mermaid's own sources (the langium
 * grammar for info/cynefin, the jison parser for venn), and every venn layout
 * assertion is a number read out of a real `mmdc` 12.2.0 render, not a value
 * this code computed for itself:
 *
 *   venn-beta / set A 20, set B 20, union A,B 6
 *     → circles (284.1427902696596, 213) r 198 and (515.8572097303404, 213) r 198
 *   venn-beta / 3 sets with all pairwise and the triple union
 *     → (324.6959487563375, 265.21122960751643) r 145.7887703924835
 *       (490.6953812546653, 265.21122960751643) r 130.39744038148072
 *       (407.8221825807239, 127.92749595882913) r 112.9274959588291
 *
 * Both were rendered with
 *   mmdc -p puppeteer.json -i x.mmd -o x.svg
 * at mermaid's default venn config (800 × 450 px, 48 px of title, padding 15),
 * i.e. a layout box of 800 × 426.
 */
namespace GDiagram.Tests {

    public class MermaidInfoCynefinVennTests {

        private static Gee.ArrayList<ElementRegion> regions() {
            return new Gee.ArrayList<ElementRegion>();
        }

        private static bool near(double a, double b, double tol = 0.01) {
            return Math.fabs(a - b) <= tol;
        }

        /** The DOT the engine produces for Mermaid source. */
        private static string dot_of(string source) {
            var engine = new DiagramEngine("dot");
            // The extension decides the format before the content does: a .puml
            // name here would silently route this through the PlantUML parser.
            string? dot = engine.generate_dot(source, "test.mmd", null);
            assert(dot != null);
            return dot;
        }

        private static string? line_with_id(string dot, string id) {
            foreach (string line in dot.split("\n")) {
                if (line.contains("id=\"%s\"".printf(id))) return line;
            }
            return null;
        }

        /** `name=value` or `name="value"` out of a DOT node line. */
        private static string attr(string line, string name) {
            var re = /([a-z_]+)=("[^"]*"|[^\s\]]+)/;
            MatchInfo m;
            if (!re.match(line, 0, out m)) return "";
            do {
                if (m.fetch(1) == name) {
                    string v = m.fetch(2);
                    return v.has_prefix("\"") ? v.substring(1, v.length - 2) : v;
                }
            } while (m.next());
            return "";
        }

        private static void node_pos(string dot, string id, out double x, out double y) {
            x = 0;
            y = 0;
            string? line = line_with_id(dot, id);
            assert(line != null);
            string pos = attr(line, "pos");
            string[] parts = pos.split(",");
            assert(parts.length == 2);
            x = double.parse(parts[0]);
            y = double.parse(parts[1]);
        }

        // ── detection ────────────────────────────────────────────

        /**
         * Mermaid's own detectors are /^\s*info/, /^\s*cynefin-beta(?:[\s:]|$)/
         * and /^\s*venn-beta/. `cynefin-beta:` is a separate keyword in the
         * grammar, so the colon form must land on the same type.
         */
        public static void test_detection() {
            assert(TypeDetector.detect_mermaid("info\n") == DiagramType.MERMAID_INFO);
            assert(TypeDetector.detect_mermaid("  info\n") == DiagramType.MERMAID_INFO);
            assert(TypeDetector.detect_mermaid("info\nshowInfo\n") == DiagramType.MERMAID_INFO);
            assert(TypeDetector.detect_mermaid("cynefin-beta\n") == DiagramType.MERMAID_CYNEFIN);
            assert(TypeDetector.detect_mermaid("cynefin-beta:\n") == DiagramType.MERMAID_CYNEFIN);
            assert(TypeDetector.detect_mermaid("    cynefin-beta\n    complex\n")
                   == DiagramType.MERMAID_CYNEFIN);
            assert(TypeDetector.detect_mermaid("venn-beta\n  set A\n") == DiagramType.MERMAID_VENN);

            // Mermaid's token builder forbids a non-space after the keyword.
            assert(TypeDetector.detect_mermaid("information about things\n")
                   != DiagramType.MERMAID_INFO);
            // A flowchart that merely mentions the words is still a flowchart.
            assert(TypeDetector.detect_mermaid("flowchart TD\n  A[info] --> B[venn-beta]\n")
                   == DiagramType.MERMAID_FLOWCHART);

            // TypeDetector.is_mermaid must agree, or detect_format sends these
            // to the PlantUML parser whenever the file has no .mmd extension.
            assert(TypeDetector.is_mermaid("info\n"));
            assert(TypeDetector.is_mermaid("cynefin-beta\n"));
            assert(TypeDetector.is_mermaid("venn-beta\n"));
        }

        /** The engine's parse() must reach the right AST class for each. */
        public static void test_engine_parse_dispatch() {
            var engine = new DiagramEngine("dot");

            var info = engine.parse("info\n", "test.mmd");
            assert(info.diagram_type == DiagramType.MERMAID_INFO);
            assert(info.ast is MermaidInfo);
            assert(info.errors.size == 0);

            var cyn = engine.parse("cynefin-beta\ncomplex\n  \"a\"\n", "test.mmd");
            assert(cyn.diagram_type == DiagramType.MERMAID_CYNEFIN);
            assert(cyn.ast is MermaidCynefin);
            assert(cyn.errors.size == 0);

            var venn = engine.parse("venn-beta\nset A [\"Alpha\"]: 20\n", "test.mmd");
            assert(venn.diagram_type == DiagramType.MERMAID_VENN);
            assert(venn.ast is MermaidVenn);
            assert(venn.errors.size == 0);
        }

        // ── info parser ──────────────────────────────────────────

        public static void test_info_parser() {
            var p = new MermaidInfoParser();

            var bare = p.parse("info\n");
            assert(bare.declared);
            assert(!bare.show_info);
            assert(!bare.has_errors());
            assert(!bare.is_empty());

            var legacy = p.parse("info\nshowInfo\n");
            assert(legacy.show_info);
            assert(!legacy.has_errors());

            var titled = p.parse("info\ntitle Renderer\naccTitle: Version card\naccDescr: What built this\n");
            assert(titled.title == "Renderer");
            assert(titled.acc_title == "Version card");
            assert(titled.acc_descr == "What built this");
            assert(!titled.has_errors());

            // A multi-line accDescr block.
            var block = p.parse("info\naccDescr {\n  line one\n  line two\n}\n");
            assert(block.acc_descr == "line one\nline two");
            assert(!block.has_errors());

            // Anything else is a parse error, as the grammar admits nothing else.
            var junk = p.parse("info\nnonsense here\n");
            assert(junk.has_errors());

            // Without the keyword there is no diagram.
            var missing = p.parse("title Only a title\n");
            assert(missing.is_empty());
            assert(missing.has_errors());
        }

        // ── cynefin parser ───────────────────────────────────────

        public static void test_cynefin_parser_domains_and_items() {
            var d = new MermaidCynefinParser().parse(
                "cynefin-beta\n" +
                "  title Decisions\n" +
                "  complex\n" +
                "    \"New market\"\n" +
                "    \"AI pricing\"\n" +
                "  clear\n" +
                "    \"Invoicing\"\n");
            assert(!d.has_errors());
            assert(d.declared);
            assert(d.title == "Decisions");
            assert(d.domains.size == 2);
            assert(d.domains.get(0).name == CynefinDomainName.COMPLEX);
            assert(d.domains.get(0).items.size == 2);
            assert(d.domains.get(0).items.get(0).label == "New market");
            // Line numbers must follow the item, not the block header.
            assert(d.domains.get(0).items.get(0).source_line == 4);
            assert(d.domains.get(0).items.get(1).source_line == 5);
            assert(d.domains.get(1).name == CynefinDomainName.CLEAR);
            assert(d.item_count() == 3);

            // The grammar's DomainBlock has NEWLINE* between parts, so items may
            // also sit on the domain's own line.
            var inline = new MermaidCynefinParser().parse(
                "cynefin-beta\nchaotic \"Outage\" \"Breach\"\n");
            assert(!inline.has_errors());
            assert(inline.domains.size == 1);
            assert(inline.domains.get(0).items.size == 2);
            assert(inline.domains.get(0).items.get(1).label == "Breach");

            // `cynefin-beta:` is the grammar's second header keyword.
            var colon = new MermaidCynefinParser().parse("cynefin-beta:\ncomplex\n  \"x\"\n");
            assert(!colon.has_errors());
            assert(colon.declared);
        }

        public static void test_cynefin_parser_transitions() {
            var d = new MermaidCynefinParser().parse(
                "cynefin-beta\n" +
                "complex --> complicated : \"learn\"\n" +
                "chaotic --> complex\n");
            assert(!d.has_errors());
            assert(d.transitions.size == 2);
            assert(d.transitions.get(0).from_domain == CynefinDomainName.COMPLEX);
            assert(d.transitions.get(0).to_domain == CynefinDomainName.COMPLICATED);
            assert(d.transitions.get(0).label == "learn");
            assert(d.transitions.get(0).source_line == 2);
            assert(d.transitions.get(1).label == null);

            // cynefinDb.setTransitions drops a self-loop; we report it.
            var loop = new MermaidCynefinParser().parse("cynefin-beta\ncomplex --> complex\n");
            assert(loop.transitions.size == 0);
            assert(loop.has_errors());

            // DOMAIN_NAME has exactly five alternatives.
            var bogus = new MermaidCynefinParser().parse("cynefin-beta\ncomplex --> simple\n");
            assert(bogus.transitions.size == 0);
            assert(bogus.has_errors());
        }

        public static void test_cynefin_parser_rejects_unquoted() {
            // DomainItem is `label=STRING`: there is no bare-word alternative.
            var item = new MermaidCynefinParser().parse("cynefin-beta\ncomplex\n  New market\n");
            assert(item.has_errors());
            assert(item.domains.get(0).items.size == 0);

            // Neither has the transition label.
            var label = new MermaidCynefinParser().parse(
                "cynefin-beta\ncomplex --> clear : learn\n");
            assert(label.has_errors());
            assert(label.transitions.size == 0);
        }

        // ── venn parser ──────────────────────────────────────────

        public static void test_venn_parser_sets_and_sizes() {
            var d = new MermaidVennParser().parse(
                "venn-beta\n" +
                "title Skills overlap\n" +
                "set A [\"Backend\"]: 20\n" +
                "set B [\"Frontend\"]\n" +
                "union A,B [\"Full stack\"]: 6\n");
            assert(!d.has_errors());
            assert(d.title == "Skills overlap");
            assert(d.subsets.size == 3);

            var a = d.find_subset("A");
            assert(a != null);
            assert(a.label == "Backend");
            assert(near(a.size, 20));
            assert(a.source_line == 3);

            // vennDB: size ?? 10 / identifiers²  →  10 for one, 2.5 for a pair.
            var b = d.find_subset("B");
            assert(b != null && near(b.size, 10));

            var ab = d.find_subset("A|B");
            assert(ab != null);
            assert(ab.label == "Full stack");
            assert(near(ab.size, 6));
            assert(!ab.is_set());

            var defaults = new MermaidVennParser().parse(
                "venn-beta\nset A\nset B\nset C\nunion A,B\nunion A,B,C\n");
            assert(!defaults.has_errors());
            assert(near(defaults.find_subset("A|B").size, 2.5));
            assert(near(defaults.find_subset("A|B|C").size, 10.0 / 9.0, 1e-9));
        }

        public static void test_venn_parser_validates_unions() {
            // validateUnionIdentifiers: every member must already be a `set`.
            var unknown = new MermaidVennParser().parse("venn-beta\nset A\nunion A,Zed\n");
            assert(unknown.has_errors());
            assert(unknown.find_subset("A|Zed") == null);

            // `union requires multiple identifiers`.
            var single = new MermaidVennParser().parse("venn-beta\nset A\nunion A\n");
            assert(single.has_errors());

            // The stored set list is sorted, so the key is stable.
            var sorted = new MermaidVennParser().parse("venn-beta\nset B\nset A\nunion B,A\n");
            assert(!sorted.has_errors());
            assert(sorted.find_subset("A|B") != null);
        }

        public static void test_venn_parser_text_and_style() {
            // An explicit set list, with and without a bracket label.
            var explicit_sets = new MermaidVennParser().parse(
                "venn-beta\nset A\nset B\nunion A,B\ntext A,B item1 [\"First item\"]\n");
            assert(!explicit_sets.has_errors());
            assert(explicit_sets.text_nodes.size == 1);
            assert(explicit_sets.text_nodes.get(0).id == "item1");
            assert(explicit_sets.text_nodes.get(0).label == "First item");
            assert(explicit_sets.text_nodes.get(0).key() == "A|B");

            // An indented `text` right after a set/union takes that statement's
            // sets (the jison lexer's INDENT_TEXT token).
            var indented = new MermaidVennParser().parse(
                "venn-beta\n" +
                "set A\n" +
                "    text alpha\n" +
                "union A,A2\n");
            // A2 was never declared, so the union errors — but the text node
            // must already have picked up the `set A` statement.
            assert(indented.text_nodes.size == 1);
            assert(indented.text_nodes.get(0).key() == "A");
            assert(indented.text_nodes.get(0).id == "alpha");

            var styled = new MermaidVennParser().parse(
                "venn-beta\nset A\nset B\nstyle A fill: #4C78A8, stroke-width: 4\nstyle B color: red\n");
            assert(!styled.has_errors());
            assert(styled.style_entries.size == 2);
            var a_styles = styled.styles_for("A");
            assert(a_styles.get("fill") == "#4C78A8");
            assert(a_styles.get("stroke-width") == "4");
            assert(styled.styles_for("B").get("color") == "red");
        }

        // ── venn layout fidelity (vs mmdc 12.2.0) ────────────────

        /**
         * circle_overlap and distance_from_intersect_area must invert each
         * other — the whole greedy layout is built on that bisection.
         */
        /**
         * A set with no `union` is its own disjoint cluster. venn.js packs
         * clusters side by side; we used to keep only the largest, which
         * dropped the other set from the drawing and left the renderer
         * dereferencing a circle that was not there.
         *
         * mmdc 12.2.0 on `set A: 20` + `set B: 10` with no union puts both
         * circles on one row at r = 210 and 148.49242404917499, centres
         * x = 247.30757595082497 and 614.2 — i.e. radius ratio √2 and a centre
         * gap of 1.7471 big radii. We keep mermaid's proportions on our own
         * canvas, so the test pins the ratios rather than the absolute numbers.
         */
        public static void test_venn_disjoint_sets_are_all_drawn() {
            var d = new MermaidVennParser().parse(
                "venn-beta\nset A [\"X\"]: 20\nset B [\"Y\"]: 10\n");
            assert(!d.has_errors());

            var solution = MermaidVennRenderer.layout(d, 800, 426, 15);
            var a = solution.get_circle("A");
            var b = solution.get_circle("B");
            // Both sets must survive the layout: this is the regression.
            assert(a != null);
            assert(b != null);

            // Packed on one row, larger first.
            assert(near(a.y, b.y, 0.01));
            assert(a.radius > b.radius);

            // mermaid's proportions: r_big / r_small = sqrt(20/10) = sqrt(2),
            // and the centres are 1.7471 big radii apart.
            assert(near(a.radius / b.radius, Math.sqrt(2.0), 0.001));
            assert(near((b.x - a.x) / a.radius, 1.7471, 0.001));

            // Three disjoint sets must all survive too.
            var d3 = new MermaidVennParser().parse(
                "venn-beta\nset A [\"X\"]: 20\nset B [\"Y\"]: 10\nset C [\"W\"]: 8\n");
            assert(!d3.has_errors());
            var s3 = MermaidVennRenderer.layout(d3, 800, 426, 15);
            assert(s3.get_circle("A") != null);
            assert(s3.get_circle("B") != null);
            assert(s3.get_circle("C") != null);
        }

        public static void test_venn_circle_math() {
            double r = Math.sqrt(20 / Math.PI);
            double d = VennLayout.distance_from_intersect_area(r, r, 6);
            assert(near(VennLayout.circle_overlap(r, r, d), 6, 1e-6));

            // Disjoint and fully contained are the closed-form cases.
            assert(near(VennLayout.circle_overlap(2, 3, 10), 0));
            assert(near(VennLayout.circle_overlap(2, 5, 1), Math.PI * 4, 1e-9));
        }

        /**
         * Two equal sets with a given overlap. mmdc puts the circles at
         * x = 284.1427902696596 and 515.8572097303404, y = 213, r = 198.
         */
        public static void test_venn_layout_matches_mermaid_two_sets() {
            var d = new MermaidVennParser().parse(
                "venn-beta\nset A [\"Backend\"]: 20\nset B [\"Frontend\"]: 20\nunion A,B [\"Full stack\"]: 6\n");
            assert(!d.has_errors());

            var solution = MermaidVennRenderer.layout(d, 800, 426, 15);
            var a = solution.get_circle("A");
            var b = solution.get_circle("B");
            assert(a != null && b != null);

            assert(near(a.x, 284.1427902696596, 0.01));
            assert(near(a.y, 213.0, 0.01));
            assert(near(a.radius, 198.0, 0.01));
            assert(near(b.x, 515.8572097303404, 0.01));
            assert(near(b.y, 213.0, 0.01));
            assert(near(b.radius, 198.0, 0.01));

            // mmdc's label anchors: A (202, 212), B (598, 213), A∩B (400, 212).
            assert(near(solution.text_x.get("A"), 202.0, 1.0));
            assert(near(solution.text_x.get("B"), 598.0, 1.0));
            assert(near(solution.text_x.get("A|B"), 400.0, 1.0));
            assert(near(solution.text_y.get("A|B"), 212.0, 1.0));
        }

        /**
         * Three sets with every pairwise overlap and the triple union. mmdc:
         *   A (324.6959487563375, 265.21122960751643) r 145.7887703924835
         *   B (490.6953812546653, 265.21122960751643) r 130.39744038148072
         *   C (407.8221825807239, 127.92749595882913) r 112.9274959588291
         */
        public static void test_venn_layout_matches_mermaid_three_sets() {
            var d = new MermaidVennParser().parse(
                "venn-beta\n" +
                "set A [\"Alpha\"]: 20\n" +
                "set B [\"Beta\"]: 16\n" +
                "set C [\"Gamma\"]: 12\n" +
                "union A,B [\"AB\"]: 5\n" +
                "union A,C [\"AC\"]: 4\n" +
                "union B,C [\"BC\"]: 3\n" +
                "union A,B,C [\"Core\"]: 2\n");
            assert(!d.has_errors());

            var s = MermaidVennRenderer.layout(d, 800, 426, 15);
            var a = s.get_circle("A");
            var b = s.get_circle("B");
            var c = s.get_circle("C");
            assert(a != null && b != null && c != null);

            // 0.05 pt of slack: our Nelder-Mead stops on the same tolerances but
            // not necessarily after the same number of reductions.
            assert(near(a.x, 324.6959487563375, 0.05));
            assert(near(a.y, 265.21122960751643, 0.05));
            assert(near(a.radius, 145.7887703924835, 0.05));
            assert(near(b.x, 490.6953812546653, 0.05));
            assert(near(b.y, 265.21122960751643, 0.05));
            assert(near(b.radius, 130.39744038148072, 0.05));
            assert(near(c.x, 407.8221825807239, 0.05));
            assert(near(c.y, 127.92749595882913, 0.05));
            assert(near(c.radius, 112.9274959588291, 0.05));

            // mmdc's label anchors, rounded to whole pixels in its SVG.
            assert(near(s.text_x.get("A"), 270.0, 1.0));
            assert(near(s.text_y.get("A"), 277.0, 1.0));
            assert(near(s.text_x.get("A|B|C"), 417.0, 1.0));
            assert(near(s.text_y.get("A|B|C"), 204.0, 1.0));
        }

        /**
         * ensurePairwiseSubsets: an N-set union with no pairwise entries still
         * has to overlap its circles, so the renderer synthesises the pairs.
         */
        public static void test_venn_synthesises_missing_pairs() {
            var d = new MermaidVennParser().parse(
                "venn-beta\nset A: 20\nset B: 20\nset C: 20\nunion A,B,C [\"Innovation\"]\n");
            assert(!d.has_errors());
            // The AST itself must not grow: only the layout input does.
            assert(d.subsets.size == 4);

            var areas = MermaidVennRenderer.layout_areas(d);
            assert(areas.size == 7);   // 3 sets + the triple + 3 synthetic pairs

            // The synthetic pair size is ¼ of the smaller of the two sets.
            bool found = false;
            foreach (var area in areas) {
                if (area.sets.length == 2 && area.key() == "A;B") {
                    assert(near(area.size, 5.0));
                    found = true;
                }
            }
            assert(found);

            // And the circles really do overlap.
            var s = MermaidVennRenderer.layout(d, 800, 426, 15);
            var a = s.get_circle("A");
            var b = s.get_circle("B");
            assert(VennLayout.distance(a.x, a.y, b.x, b.y) < a.radius + b.radius);
        }

        // ── renderer snapshots ───────────────────────────────────

        public static void test_info_dot() {
            string dot = dot_of("info\ntitle Renderer version\n");
            assert(dot.contains("graph info {"));
            assert(dot.contains("layout=nop2"));

            string? version = line_with_id(dot, "info_version");
            assert(version != null);
            assert(version.contains("label=\"v" + VERSION + "\""));
            assert(attr(version, "fontsize") == "32.00");

            string? title = line_with_id(dot, "info_title");
            assert(title != null);
            assert(title.contains("Renderer version"));

            // The version sits at the centre of the 400-wide card and the title
            // above it (DOT's y axis runs upwards).
            double vx, vy, tx, ty, px, py;
            node_pos(dot, "info_version", out vx, out vy);
            node_pos(dot, "info_title", out tx, out ty);
            node_pos(dot, "info_page", out px, out py);
            assert(near(vx, px, 0.5));
            assert(near(tx, px, 0.5));
            assert(ty > vy);
        }

        public static void test_cynefin_dot() {
            string dot = dot_of(
                "cynefin-beta\n" +
                "title Product decisions\n" +
                "complex\n" +
                "  \"New market entry\"\n" +
                "clear\n" +
                "  \"Invoice processing\"\n" +
                "complex --> clear : \"learn\"\n");
            assert(dot.contains("graph cynefin {"));

            // Four domain rectangles, each a quadrant of the 520 × 390 grid.
            foreach (string name in new string[] { "complex", "complicated", "chaotic", "clear" }) {
                string? line = line_with_id(dot, "cyn_domain_" + name);
                assert(line != null);
                assert(near(double.parse(attr(line, "width")) * 72.0, 260.0, 0.5));
                assert(near(double.parse(attr(line, "height")) * 72.0, 195.0, 0.5));
            }
            // Complex is top-left and Clear bottom-right, so in DOT coordinates
            // Complex is higher and further left than Clear.
            double cxx, cxy, clx, cly;
            node_pos(dot, "cyn_domain_complex", out cxx, out cxy);
            node_pos(dot, "cyn_domain_clear", out clx, out cly);
            assert(cxx < clx);
            assert(cxy > cly);

            // The confusion ellipse, radii 0.15 × the grid.
            string? ell = line_with_id(dot, "cyn_confusion");
            assert(ell != null);
            assert(ell.contains("shape=ellipse"));
            assert(near(double.parse(attr(ell, "width")) * 72.0, 2 * 520.0 * 0.15, 0.5));
            assert(near(double.parse(attr(ell, "height")) * 72.0, 2 * 390.0 * 0.15, 0.5));

            // Seven dashed segments per wavy boundary, plus the two-part cliff.
            for (int i = 0; i < 7; i++) {
                string? fold = line_with_id(dot, "cyn_fold_%d".printf(i));
                assert(fold != null);
                assert(fold.contains("style=dashed"));
                assert(line_with_id(dot, "cyn_hbound_%d".printf(i)) != null);
            }
            assert(line_with_id(dot, "cyn_fold_7") == null);
            assert(line_with_id(dot, "cyn_cliff_0") != null);
            assert(line_with_id(dot, "cyn_cliff_1") != null);

            // Labels, subtitles and the item badge.
            assert(dot.contains("Complex"));
            assert(dot.contains("Probe"));          // the Complex decision model
            assert(dot.contains("Emergent Practices"));
            assert(line_with_id(dot, "cyn_item_complex_0") != null);
            assert(dot.contains("New market entry"));

            // One arrow with a two-stroke chevron head and its label.
            assert(line_with_id(dot, "cyn_arrow_0") != null);
            assert(line_with_id(dot, "cyn_arrow_0_head_a") != null);
            assert(line_with_id(dot, "cyn_arrow_0_head_b") != null);
            assert(dot.contains("learn"));
            assert(line_with_id(dot, "cyn_arrow_1") == null);

            assert(line_with_id(dot, "cyn_title") != null);
            assert(dot.contains("Product decisions"));
        }

        /** mermaid's waviness PRNG is mulberry32; the seed is pinned so renders repeat. */
        public static void test_cynefin_boundary_prng() {
            // Values read out of mermaid's own seededRandom() in Node:
            //   seededRandom(0) = 0.26642920868471265
            //   seededRandom(1) = 0.6270739405881613
            //   seededRandom(101) = 0.1356478596571833
            assert(near(MermaidCynefinRenderer.seeded_random(0), 0.26642920868471265, 1e-15));
            assert(near(MermaidCynefinRenderer.seeded_random(1), 0.6270739405881613, 1e-15));
            assert(near(MermaidCynefinRenderer.seeded_random(101), 0.1356478596571833, 1e-15));
            // Deterministic: the same source renders the same DOT twice.
            string src = "cynefin-beta\ncomplex\n  \"x\"\n";
            assert(dot_of(src) == dot_of(src));
        }

        public static void test_venn_dot() {
            string dot = dot_of(
                "venn-beta\n" +
                "title Skills overlap\n" +
                "set A [\"Backend\"]: 20\n" +
                "set B [\"Frontend\"]: 20\n" +
                "union A,B [\"Full stack\"]: 6\n");
            assert(dot.contains("graph venn {"));

            // One circle per set, equal radii, on the same horizontal line.
            string? ca = line_with_id(dot, "venn_circle_A");
            string? cb = line_with_id(dot, "venn_circle_B");
            assert(ca != null && cb != null);
            assert(ca.contains("shape=circle"));
            double ra = double.parse(attr(ca, "width")) * 72.0 / 2.0;
            double rb = double.parse(attr(cb, "width")) * 72.0 / 2.0;
            assert(near(ra, rb, 0.1));
            assert(ra > 50);

            double ax, ay, bx, by;
            node_pos(dot, "venn_circle_A", out ax, out ay);
            node_pos(dot, "venn_circle_B", out bx, out by);
            assert(near(ay, by, 0.1));
            assert(ax < bx);
            // The centres are closer than 2r, so the circles really overlap.
            assert(bx - ax < 2 * ra);

            // Labels: the two sets and the intersection, the latter between them.
            assert(dot.contains("Backend"));
            assert(dot.contains("Frontend"));
            assert(dot.contains("Full stack"));
            double lx, ly;
            node_pos(dot, "venn_label_A_B", out lx, out ly);
            assert(lx > ax && lx < bx);

            assert(line_with_id(dot, "venn_title") != null);
        }

        /** `style` must reach the circle, with Graphviz's `#`-only-for-hex rule honoured. */
        public static void test_venn_style_reaches_the_circle() {
            string dot = dot_of(
                "venn-beta\nset A\nset B\nunion A,B\n" +
                "style A fill: #4C78A8, stroke: #2C4C6E, stroke-width: 4\n" +
                "style B fill: #red\n");
            string? ca = line_with_id(dot, "venn_circle_A");
            assert(ca != null);
            // Hex keeps its '#'; fill-opacity 0.1 is appended as an alpha byte.
            assert(attr(ca, "fillcolor") == "#4C78A81A");
            assert(attr(ca, "color") == "#2C4C6E");
            assert(attr(ca, "penwidth") == "4.00");

            // A named colour must lose the '#', or Graphviz rejects it.
            string? cb = line_with_id(dot, "venn_circle_B");
            assert(cb != null);
            assert(attr(cb, "fillcolor") == "red");
            assert(!attr(cb, "fillcolor").has_prefix("#"));
        }

        /** The text nodes of a `text` statement land inside their own area. */
        public static void test_venn_text_nodes_sit_inside_their_area() {
            var d = new MermaidVennParser().parse(
                "venn-beta\n" +
                "set A [\"Alpha\"]: 20\n" +
                "set B [\"Beta\"]: 20\n" +
                "union A,B [\"Both\"]: 6\n" +
                "text A,B shared [\"Shared work\"]\n");
            assert(!d.has_errors());
            assert(d.text_nodes.size == 1);

            string dot = dot_of(
                "venn-beta\n" +
                "set A [\"Alpha\"]: 20\n" +
                "set B [\"Beta\"]: 20\n" +
                "union A,B [\"Both\"]: 6\n" +
                "text A,B shared [\"Shared work\"]\n");
            string? node = line_with_id(dot, "venn_text_shared");
            assert(node != null);
            assert(node.contains("Shared work"));

            double ax, ay, bx, by, tx, ty;
            node_pos(dot, "venn_circle_A", out ax, out ay);
            node_pos(dot, "venn_circle_B", out bx, out by);
            node_pos(dot, "venn_text_shared", out tx, out ty);
            double ra = double.parse(attr(line_with_id(dot, "venn_circle_A"), "width")) * 72.0 / 2.0;
            double rb = double.parse(attr(line_with_id(dot, "venn_circle_B"), "width")) * 72.0 / 2.0;
            assert(VennLayout.distance(tx, ty, ax, ay) < ra);
            assert(VennLayout.distance(tx, ty, bx, by) < rb);
        }

        // ── regions and exports ──────────────────────────────────

        /**
         * All three must map click regions back to their source lines, and
         * DiagramEngine.render() must leave none of the previous diagram's
         * regions behind.
         */
        public static void test_click_regions() {
            var engine = new DiagramEngine("dot");

            var cyn = engine.render(DiagramType.MERMAID_CYNEFIN, DiagramFormat.MERMAID,
                "cynefin-beta\ncomplex\n  \"New market entry\"\nclear\n  \"Invoicing\"\n");
            assert(cyn.status == RenderStatus.OK);
            assert(engine.last_regions.size > 0);
            bool found_item = false;
            bool found_domain = false;
            foreach (var r in engine.last_regions) {
                if (r.name == "complex_item_0") {
                    found_item = true;
                    assert(r.source_line == 3);
                }
                if (r.name == "complex") found_domain = true;
            }
            assert(found_item);
            assert(found_domain);

            var venn = engine.render(DiagramType.MERMAID_VENN, DiagramFormat.MERMAID,
                "venn-beta\nset A [\"Alpha\"]: 20\nset B [\"Beta\"]: 20\nunion A,B [\"Both\"]: 6\n");
            assert(venn.status == RenderStatus.OK);
            bool found_set = false;
            foreach (var r in engine.last_regions) {
                if (r.name == "A") {
                    found_set = true;
                    assert(r.source_line == 2);
                }
                // The cynefin regions must be gone.
                assert(r.name != "complex_item_0");
            }
            assert(found_set);
        }

        /** PNG, SVG and PDF export must all produce a non-trivial file. */
        public static void test_exports() {
            string[] sources = {
                "info\ntitle Version\n",
                "cynefin-beta\ntitle D\ncomplex\n  \"x\"\nclear\n  \"y\"\ncomplex --> clear : \"learn\"\n",
                "venn-beta\ntitle V\nset A [\"Alpha\"]: 20\nset B [\"Beta\"]: 20\nunion A,B [\"Both\"]: 6\n"
            };
            string[] names = { "info", "cynefin", "venn" };
            var engine = new DiagramEngine("dot");

            for (int i = 0; i < sources.length; i++) {
                foreach (string fmt in new string[] { "png", "svg", "pdf" }) {
                    string path = Path.build_filename(Environment.get_tmp_dir(),
                        "gdiagram-%s-%d.%s".printf(names[i], (int) (GLib.get_real_time() & 0xFFFFFF), fmt));
                    bool ok = false;
                    if (fmt == "png") ok = engine.export_to_png(sources[i], "test.mmd", null, path);
                    else if (fmt == "svg") ok = engine.export_to_svg(sources[i], "test.mmd", null, path);
                    else ok = engine.export_to_pdf(sources[i], "test.mmd", null, path);
                    if (!ok) {
                        printerr("\nFAILED: %s export of %s\n", fmt, names[i]);
                        assert_not_reached();
                    }
                    var f = File.new_for_path(path);
                    assert(f.query_exists());
                    try {
                        var info = f.query_info("standard::size", FileQueryInfoFlags.NONE);
                        assert(info.get_size() > 500);
                    } catch (Error e) {
                        assert_not_reached();
                    }
                    FileUtils.unlink(path);
                }
            }
        }

        // ── locale ───────────────────────────────────────────────

        /**
         * `%f` follows LC_NUMERIC and a GUI process calls setlocale(): on a
         * German desktop a comma in a DOT coordinate makes Graphviz refuse the
         * whole graph. Every number these three renderers write must be
         * C-formatted.
         */
        public static void test_dot_is_locale_independent() {
            string? had = Intl.setlocale(LocaleCategory.NUMERIC, null);
            string[] comma_locales = {
                "de_AT.utf8", "de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "es_ES.UTF-8"
            };
            string? used = null;
            foreach (string loc in comma_locales) {
                if (Intl.setlocale(LocaleCategory.NUMERIC, loc) != null && "%.2f".printf(1.5) == "1,50") {
                    used = loc;
                    break;
                }
            }
            if (used == null) {
                Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");
                Test.skip("no comma-decimal locale installed; cannot prove the locale guard here");
                return;
            }

            string info = dot_of("info\ntitle T\n");
            string cyn = dot_of("cynefin-beta\ntitle T\ncomplex\n  \"x\"\ncomplex --> clear : \"go\"\n");
            string venn = dot_of(
                "venn-beta\ntitle T\nset A [\"Alpha\"]: 20\nset B [\"Beta\"]: 20\nunion A,B [\"Both\"]: 6\n");
            Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");

            // A comma is legal inside pos="x,y" and inside a label, so look at
            // the numeric attributes that must never carry one.
            foreach (string dot in new string[] { info, cyn, venn }) {
                var re = /(width|height|penwidth|fontsize)=([-0-9.,]+)/;
                MatchInfo m;
                if (re.match(dot, 0, out m)) {
                    do {
                        if (m.fetch(2).contains(",")) {
                            printerr("\nFAILED: locale-formatted %s=%s under %s\n",
                                m.fetch(1), m.fetch(2), used);
                            assert_not_reached();
                        }
                    } while (m.next());
                }
                // A coordinate pair is "x,y": exactly one comma, never two.
                foreach (string line in dot.split("\n")) {
                    int at = line.index_of("pos=\"");
                    if (at < 0) continue;
                    int end = line.index_of("\"", at + 5);
                    string pos = line.substring(at + 5, end - at - 5);
                    // Edge positions list several points separated by spaces.
                    foreach (string point in pos.split(" ")) {
                        if (point.length == 0) continue;
                        if (point.split(",").length != 2) {
                            printerr("\nFAILED: locale-formatted pos \"%s\" under %s\n", pos, used);
                            assert_not_reached();
                        }
                    }
                }
            }
        }
    }
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/icv/detection", GDiagram.Tests.MermaidInfoCynefinVennTests.test_detection);
    Test.add_func("/icv/engine-parse-dispatch", GDiagram.Tests.MermaidInfoCynefinVennTests.test_engine_parse_dispatch);
    Test.add_func("/icv/info-parser", GDiagram.Tests.MermaidInfoCynefinVennTests.test_info_parser);
    Test.add_func("/icv/cynefin-domains", GDiagram.Tests.MermaidInfoCynefinVennTests.test_cynefin_parser_domains_and_items);
    Test.add_func("/icv/cynefin-transitions", GDiagram.Tests.MermaidInfoCynefinVennTests.test_cynefin_parser_transitions);
    Test.add_func("/icv/cynefin-rejects-unquoted", GDiagram.Tests.MermaidInfoCynefinVennTests.test_cynefin_parser_rejects_unquoted);
    Test.add_func("/icv/venn-sets-and-sizes", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_parser_sets_and_sizes);
    Test.add_func("/icv/venn-validates-unions", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_parser_validates_unions);
    Test.add_func("/icv/venn-text-and-style", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_parser_text_and_style);
    Test.add_func("/icv/venn-disjoint-sets",
                  GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_disjoint_sets_are_all_drawn);
    Test.add_func("/icv/venn-circle-math", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_circle_math);
    Test.add_func("/icv/venn-layout-two-sets", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_layout_matches_mermaid_two_sets);
    Test.add_func("/icv/venn-layout-three-sets", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_layout_matches_mermaid_three_sets);
    Test.add_func("/icv/venn-synthesises-pairs", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_synthesises_missing_pairs);
    Test.add_func("/icv/info-dot", GDiagram.Tests.MermaidInfoCynefinVennTests.test_info_dot);
    Test.add_func("/icv/cynefin-dot", GDiagram.Tests.MermaidInfoCynefinVennTests.test_cynefin_dot);
    Test.add_func("/icv/cynefin-boundary-prng", GDiagram.Tests.MermaidInfoCynefinVennTests.test_cynefin_boundary_prng);
    Test.add_func("/icv/venn-dot", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_dot);
    Test.add_func("/icv/venn-style", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_style_reaches_the_circle);
    Test.add_func("/icv/venn-text-nodes", GDiagram.Tests.MermaidInfoCynefinVennTests.test_venn_text_nodes_sit_inside_their_area);
    Test.add_func("/icv/click-regions", GDiagram.Tests.MermaidInfoCynefinVennTests.test_click_regions);
    Test.add_func("/icv/exports", GDiagram.Tests.MermaidInfoCynefinVennTests.test_exports);
    Test.add_func("/icv/dot-locale-independent", GDiagram.Tests.MermaidInfoCynefinVennTests.test_dot_is_locale_independent);
    return Test.run();
}
