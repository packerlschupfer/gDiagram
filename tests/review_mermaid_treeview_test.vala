namespace GDiagram.Tests {
    /**
     * Mermaid treeView-beta and ishikawa fidelity against Mermaid CLI 12.2.0.
     *
     * treeView covers both input forms — indentation and `tree`-command box
     * drawing — plus the four node annotations, and pins the drawn row pitch
     * and indent against mermaid's own SVG. ishikawa pins the fishbone
     * geometry: the spine length split by descendant count, the 82-degree
     * bones, and the horizontal/diagonal alternation of the sub-bones.
     *
     * Every geometry number in here was read out of an `mmdc` render of the
     * same source (mermaid 12.2.0, default theme).
     */
    public class ReviewMermaidTreeViewTests {

        // ──────────────────────────────── helpers

        private static MermaidTreeView tree(string src) {
            var d = new MermaidTreeViewParser().parse(src);
            foreach (var e in d.errors) printerr("treeView error: %s (line %d)\n", e.message, e.line);
            assert(!d.has_errors());
            return d;
        }

        private static MermaidIshikawa fish(string src) {
            var d = new MermaidIshikawaParser().parse(src);
            foreach (var e in d.errors) printerr("ishikawa error: %s (line %d)\n", e.message, e.line);
            assert(!d.has_errors());
            return d;
        }

        /** "a/b/c" paths of every node below the synthetic root, in pre-order. */
        private static Gee.ArrayList<string> paths(MermaidTreeView d) {
            var list = new Gee.ArrayList<string>();
            collect_paths(d.root, "", list);
            return list;
        }

        private static void collect_paths(TreeViewNode node, string prefix,
                                          Gee.ArrayList<string> list) {
            foreach (var child in node.children) {
                string p = prefix + child.name + (child.is_directory() ? "/" : "");
                list.add(p);
                collect_paths(child, p, list);
            }
        }

        private static string joined(MermaidTreeView d) {
            var sb = new StringBuilder();
            foreach (string p in paths(d)) {
                if (sb.len > 0) sb.append(" | ");
                sb.append(p);
            }
            return sb.str;
        }

        private static TreeViewNode node_at(MermaidTreeView d, string path) {
            foreach (var child in d.root.children) {
                var hit = find_path(child, "", path);
                if (hit != null) return hit;
            }
            error("no treeView node at %s", path);
        }

        private static TreeViewNode? find_path(TreeViewNode node, string prefix, string want) {
            string p = prefix + node.name + (node.is_directory() ? "/" : "");
            if (p == want) return node;
            foreach (var child in node.children) {
                var hit = find_path(child, p, want);
                if (hit != null) return hit;
            }
            return null;
        }

        private static string tree_dot(string src) {
            var engine = new DiagramEngine("dot");
            string? dot = engine.generate_dot(src, "test.mmd", null);
            assert(dot != null);
            return dot;
        }

        private static string fish_svg(MermaidIshikawa d) {
            var regions = new Gee.ArrayList<ElementRegion>();
            var r = new MermaidIshikawaRenderer(new Gvc.Context(), regions, "dot");
            uint8[]? data = r.render_to_svg(d);
            assert(data != null);
            var sb = new StringBuilder();
            sb.append_len((string) data, data.length);
            return sb.str;
        }

        /**
         * Where the ChartCanvas node with this id attribute was pinned. x is
         * the *left* edge of the node box, not its centre: a left-aligned
         * label's box is centred on `anchor + (text width + 8) / 2`, so the
         * centre alone would carry the text width into every comparison.
         */
        private static bool dot_pos(string dot, string id, out double x, out double y) {
            x = 0; y = 0;
            try {
                var re = new Regex("id=\"" + Regex.escape_string(id) +
                    "\"[^\\n]*pos=\"([-0-9.]+),([-0-9.]+)\" width=([0-9.]+)");
                MatchInfo m;
                if (!re.match(dot, 0, out m)) return false;
                x = double.parse(m.fetch(1)) - double.parse(m.fetch(3)) * 36.0;
                y = double.parse(m.fetch(2));
                return true;
            } catch (RegexError e) {
                return false;
            }
        }

        private static void near(double got, double want, double tol, string what) {
            if (Math.fabs(got - want) > tol) {
                error("%s: got %f, expected %f (±%f)", what, got, want, tol);
            }
        }

        // ──────────────────────────────── treeView parsing

        private const string INDENTED = """treeView-beta
src/
    main.c
    util/
        helper.c
        helper.h
    README.md
""";

        // The same tree as INDENTED, written the way `tree` prints it.
        private const string BOXED = """treeView-beta
src/
├── main.c
├── util/
│   ├── helper.c
│   └── helper.h
└── README.md
""";

        public static void test_indentation_tree() {
            var d = tree(INDENTED);
            // mermaid always keeps a synthetic "/" root and draws it.
            assert(d.root.name == "/");
            assert(d.root.is_directory());
            assert(d.root.level == -1);
            assert(d.node_count() == 6);
            assert(joined(d) ==
                "src/ | src/main.c | src/util/ | src/util/helper.c | src/util/helper.h | src/README.md");
            // A trailing "/" marks a directory and is stripped from the name.
            assert(node_at(d, "src/").name == "src");
            assert(node_at(d, "src/main.c").node_type == TreeViewNodeType.FILE);
            // The level is the raw indentation character count, not a depth.
            assert(node_at(d, "src/").level == 0);
            assert(node_at(d, "src/util/").level == 4);
            assert(node_at(d, "src/util/helper.c").level == 8);
            // Source lines for click-to-source.
            assert(node_at(d, "src/util/helper.h").source_line == 6);
        }

        public static void test_box_drawing_matches_indentation() {
            // mmdc renders both forms to the identical 135.125 x 189.109375
            // view box, i.e. the preprocessor produces the same tree.
            assert(joined(tree(BOXED)) == joined(tree(INDENTED)));
            var d = tree(BOXED);
            assert(node_at(d, "src/util/helper.c").source_line == 5);
        }

        public static void test_box_drawing_heavy_and_segment_width() {
            // Heavy variants ┣━━ ┗━━ ┃ are the same characters class.
            string heavy = """treeView-beta
src/
┣━━ main.c
┣━━ util/
┃   ┣━━ helper.c
┃   ┗━━ helper.h
┗━━ README.md
""";
            assert(joined(tree(heavy)) == joined(tree(INDENTED)));

            // The indent unit comes from the column of the first branch
            // character that is not at column 0 — here 2, not 4. Box drawing
            // characters are three bytes in UTF-8, so a byte offset would
            // infer 6 and flatten every level below the first.
            string narrow = """treeView-beta
src/
├─ main.c
├─ util/
│ ├─ helper.c
│ └─ helper.h
└─ README.md
""";
            assert(joined(tree(narrow)) == joined(tree(INDENTED)));
        }

        public static void test_box_drawing_decoration_and_errors() {
            // A line that is nothing but trunk decoration is dropped.
            string decorated = """treeView-beta
src/
├── a.c
│
└── b.c
""";
            assert(joined(tree(decorated)) == "src/ | src/a.c | src/b.c");

            // mermaid throws on a branch prefix with no name after it ...
            var empty_node = new MermaidTreeViewParser().parse("""treeView-beta
src/
├──
└── b.c
""");
            assert(empty_node.has_errors());
            assert(empty_node.errors.get(0).line == 3);
            assert(empty_node.errors.get(0).message.contains("Empty node"));

            // ... and on indentation without a box prefix once in box mode.
            var mixed = new MermaidTreeViewParser().parse("""treeView-beta
src/
├── a.c
    b.c
""");
            assert(mixed.has_errors());
            assert(mixed.errors.get(0).line == 4);
            assert(mixed.errors.get(0).message.contains("without box-drawing"));
        }

        public static void test_annotations() {
            string src = """treeView-beta
title My Tree
accTitle: short title
accDescr: a longer description
app/
    "my file.txt" ## the entry point
    config.json :::highlight
    assets/ icon(folder)
    plain.txt icon()
    both.txt :::warn icon(mdi:file) ## two of them
    not:::an:::annotation.txt
""";
            var d = tree(src);
            assert(d.title == "My Tree");
            assert(d.acc_title == "short title");
            assert(d.acc_descr == "a longer description");

            // A quoted name keeps its internal spaces and loses the quotes.
            var quoted = node_at(d, "app/my file.txt");
            assert(quoted.description == "the entry point");
            assert(quoted.css_class == null);

            assert(node_at(d, "app/config.json").css_class == "highlight");
            assert(node_at(d, "app/config.json").has_class("highlight"));

            var assets = node_at(d, "app/assets/");
            assert(assets.icon == "folder");
            assert(assets.is_directory());

            // A bare icon() means "no icon", which the renderer reads as none.
            assert(node_at(d, "app/plain.txt").icon == "none");

            var both = node_at(d, "app/both.txt");
            assert(both.css_class == "warn");
            assert(both.icon == "mdi:file");
            assert(both.description == "two of them");

            // CLASS_ANNOTATION needs whitespace before ":::", so this is a name.
            assert(node_at(d, "app/not:::an:::annotation.txt").css_class == null);
        }

        public static void test_detection() {
            assert(TypeDetector.is_mermaid("treeView-beta\nsrc/\n"));
            assert(TypeDetector.detect_mermaid("treeView-beta\nsrc/\n")
                == DiagramType.MERMAID_TREE_VIEW);
            // mermaid's own detector keeps the -beta spelling for treeView.
            assert(TypeDetector.detect_mermaid("ishikawa\nEffect\n")
                == DiagramType.MERMAID_ISHIKAWA);
            assert(TypeDetector.detect_mermaid("ishikawa-beta\nEffect\n")
                == DiagramType.MERMAID_ISHIKAWA);
            // /^\s*ishikawa(-beta)?\b/i — case-insensitive, leading space ok.
            assert(TypeDetector.detect_mermaid("  Ishikawa\nEffect\n")
                == DiagramType.MERMAID_ISHIKAWA);
            assert(TypeDetector.is_mermaid("ishikawa\nEffect\n"));

            // Both go through the engine's own dispatch, AST included.
            var engine = new DiagramEngine("dot");
            var r = engine.parse(INDENTED, "test.mmd");
            assert(r.diagram_type == DiagramType.MERMAID_TREE_VIEW);
            assert(r.ast is MermaidTreeView);
            var r2 = engine.parse("ishikawa\nEffect\n    Cause\n", "test.mmd");
            assert(r2.diagram_type == DiagramType.MERMAID_ISHIKAWA);
            assert(r2.ast is MermaidIshikawa);
        }

        // ──────────────────────────────── treeView geometry

        public static void test_tree_view_row_geometry() {
            string dot = tree_dot(INDENTED);
            // The node ids carry the source line: 0 = the synthetic root,
            // 2 = "src/", 3 = "main.c", 4 = "util/", 5 = "helper.c".
            double root_x, root_y, src_x, src_y, util_x, util_y;
            double main_x, main_y, helper_x, helper_y;
            assert(dot_pos(dot, "treeview_node_0", out root_x, out root_y));
            assert(dot_pos(dot, "treeview_node_2", out src_x, out src_y));
            assert(dot_pos(dot, "treeview_node_3", out main_x, out main_y));
            assert(dot_pos(dot, "treeview_node_4", out util_x, out util_y));
            assert(dot_pos(dot, "treeview_node_5", out helper_x, out helper_y));

            // mermaid: rows are labelHeight + 2 * paddingY = 27.015625 apart.
            near(root_y - src_y, 27.0156, 0.05, "row pitch root->src");
            near(src_y - main_y, 27.0156, 0.05, "row pitch src->main.c");
            near(main_y - util_y, 27.0156, 0.05, "row pitch main.c->util");

            // indent = depth * (rowIndent 10 + paddingX 5). A directory label
            // is bold, which ChartCanvas writes as an HTML cell whose box is
            // inset by 2 pt, so compare rows of the same weight.
            near(src_x - root_x, 15.0, 0.02, "indent per level, directories");
            near(util_x - src_x, 15.0, 0.02, "indent per level, directories");
            near(helper_x - main_x, 15.0, 0.02, "indent per level, files");
        }

        public static void test_tree_view_icon_offset_and_highlight() {
            string src = """treeView-beta
app/
    plain.txt
    marked.txt :::highlight
    with-icon.txt icon(file)
    assets/ icon(folder)
    hidden.txt icon()
""";
            string dot = tree_dot(src);
            double plain_x, plain_y, icon_x, icon_y, hidden_x, hidden_y;
            assert(dot_pos(dot, "treeview_node_3", out plain_x, out plain_y));
            assert(dot_pos(dot, "treeview_node_5", out icon_x, out icon_y));
            assert(dot_pos(dot, "treeview_node_7", out hidden_x, out hidden_y));
            // An icon shifts the label by ICON_SIZE + ICON_GAP = 18 at the same
            // depth: mmdc puts an icon'd depth-2 label at x=53, a plain one at 35.
            near(icon_x - plain_x, 18.0, 0.02, "icon offset");
            // A bare icon() suppresses the icon, and with it the offset.
            near(hidden_x - plain_x, 0.0, 0.02, "icon() suppresses the offset");

            // The two built-in icons become Graphviz folder / note outlines.
            assert(dot.contains("shape=folder"));
            assert(dot.contains("shape=note"));
            // The highlight band is Mermaid's amber at 15% over the full width.
            assert(dot.contains("id=\"treeview_highlight_4\""));
            assert(dot.contains("fillcolor=\"#ffc10726\""));
        }

        public static void test_tree_view_description_column() {
            string src = """treeView-beta
a/
    short.txt ## first
    a-much-longer-file-name.txt
    other.txt ## second
""";
            string dot = tree_dot(src);
            // Both descriptions share one column, right of the widest label,
            // and are drawn in italics (Mermaid's .treeView-node-description).
            int first = dot.index_of("first");
            int second = dot.index_of("second");
            assert(first > 0 && second > 0);
            try {
                var re = new Regex("label=<<TABLE[^>]*><TR><TD[^>]*><I>first</I>");
                assert(re.match(dot));
            } catch (RegexError e) {
                assert_not_reached();
            }
            // The two description nodes sit at the same x.
            double x1 = 0, x2 = 0;
            assert(desc_x(dot, "first", out x1));
            assert(desc_x(dot, "second", out x2));
            near(x1, x2, 0.01, "shared description column");
        }

        private static bool desc_x(string dot, string text, out double x) {
            x = 0;
            try {
                var re = new Regex("<I>" + Regex.escape_string(text) +
                    "</I>[^\\n]*pos=\"([-0-9.]+),([-0-9.]+)\" width=([0-9.]+)");
                MatchInfo m;
                if (!re.match(dot, 0, out m)) return false;
                x = double.parse(m.fetch(1)) - double.parse(m.fetch(3)) * 36.0;
                return true;
            } catch (RegexError e) {
                return false;
            }
        }

        // ──────────────────────────────── ishikawa parsing

        private const string FISHBONE = """ishikawa-beta
Late delivery
    Machine
        Old printer
        No spare parts
    Method
        Unclear process
    Material
        Low quality paper
    Manpower
        Untrained staff
""";

        public static void test_ishikawa_structure() {
            var d = fish(FISHBONE);
            assert(d.root != null);
            assert(d.root.text == "Late delivery");
            // mermaid's db sets the diagram title to the effect text.
            assert(d.title == "Late delivery");
            assert(d.causes().size == 4);
            assert(d.causes().get(0).text == "Machine");
            assert(d.causes().get(0).children.size == 2);
            assert(d.causes().get(0).children.get(1).text == "No spare parts");
            assert(d.node_count() == 10);        // the effect plus 4 causes and 5 sub-causes
            assert(d.causes().get(0).descendant_count() == 2);
            assert(d.causes().get(1).descendant_count() == 1);
            assert(d.root.source_line == 2);
            assert(d.causes().get(3).source_line == 10);
        }

        public static void test_ishikawa_base_level_and_noise() {
            // baseLevel comes from the first *cause*, so an effect line that is
            // indented deeper than its causes still nests correctly.
            var d = fish("""ishikawa
        Deeply indented effect
  Machine
    Old printer
  Method
""");
            assert(d.root.text == "Deeply indented effect");
            assert(d.causes().size == 2);
            assert(d.causes().get(0).children.size == 1);

            // Blank lines and whole-line %% comments are SPACELINE: no-ops
            // that must not shift the level of the line after them.
            var e = fish("""ishikawa
Effect

    Machine
%% a comment
        Old printer

    Method
""");
            assert(e.causes().size == 2);
            assert(e.causes().get(0).children.size == 1);
            assert(e.causes().get(0).children.get(0).text == "Old printer");

            // A tab counts as one indentation character, as [\s]+ length does.
            var t = fish("ishikawa\nEffect\n\tMachine\n\t\tOld printer\n\tMethod\n");
            assert(t.causes().size == 2);
            assert(t.causes().get(0).children.size == 1);
        }

        public static void test_ishikawa_keyword_forms() {
            // Both spellings, any case, and the first statement may share the
            // keyword's line (the jison lexer simply carries on).
            assert(fish("ISHIKAWA\nEffect\n").root.text == "Effect");
            assert(fish("ishikawa-beta\nEffect\n").root.text == "Effect");
            var same_line = fish("ishikawa Effect\n    Machine\n");
            assert(same_line.root.text == "Effect");
            assert(same_line.causes().size == 1);

            // A bare keyword draws nothing at all in mermaid.
            var bare = fish("ishikawa\n");
            assert(bare.is_empty());
            assert(bare.root == null);
            assert(bare.node_count() == 0);
        }

        // ──────────────────────────────── ishikawa geometry

        private static bool svg_line(string svg, int index, out double x1, out double y1,
                                     out double x2, out double y2) {
            x1 = 0; y1 = 0; x2 = 0; y2 = 0;
            try {
                var re = new Regex(
                    "<line class=\"[^\"]*\" x1=\"([-0-9.]+)\" y1=\"([-0-9.]+)\" x2=\"([-0-9.]+)\" y2=\"([-0-9.]+)\"");
                MatchInfo m;
                if (!re.match(svg, 0, out m)) return false;
                int seen = 0;
                do {
                    if (seen == index) {
                        x1 = double.parse(m.fetch(1));
                        y1 = double.parse(m.fetch(2));
                        x2 = double.parse(m.fetch(3));
                        y2 = double.parse(m.fetch(4));
                        return true;
                    }
                    seen++;
                } while (m.next());
                return false;
            } catch (RegexError e) {
                return false;
            }
        }

        public static void test_ishikawa_spine_and_bones() {
            string svg = fish_svg(fish(FISHBONE));

            // mmdc: the upper side holds 3 descendants and the lower 2, so the
            // 500 pt pool splits 300/200 and the spine sits at y = 300.
            assert(svg.contains("class=\"ishikawa-spine\""));
            try {
                var re = new Regex("class=\"ishikawa-spine\" x1=\"([-0-9.]+)\" y1=\"([-0-9.]+)\"");
                MatchInfo m;
                assert(re.match(svg, 0, out m));
                near(double.parse(m.fetch(2)), 300.0, 0.01, "spine y");
            } catch (RegexError e) {
                assert_not_reached();
            }

            // First (upper) bone: 82 degrees, full 300 pt, from x = -20.
            double x1, y1, x2, y2;
            assert(svg_line(svg, 0, out x1, out y1, out x2, out y2));
            near(x1, -20.0, 0.01, "bone 1 start x");
            near(y1, 300.0, 0.01, "bone 1 start y");
            near(x2, -61.752, 0.01, "bone 1 end x");
            near(y2, 2.9196, 0.01, "bone 1 end y");

            // Its two sub-bones are horizontal, evenly spread along it, each
            // a 30 pt stub because they have no children of their own.
            assert(svg_line(svg, 1, out x1, out y1, out x2, out y2));
            near(x1, -33.917, 0.01, "sub-bone 1 x0");
            near(y1, 200.973, 0.01, "sub-bone 1 y");
            near(x2 - x1, -30.0, 0.01, "sub-bone 1 stub length");
            assert(svg_line(svg, 2, out x1, out y1, out x2, out y2));
            near(x1, -47.835, 0.01, "sub-bone 2 x0");
            near(y1, 101.946, 0.01, "sub-bone 2 y");

            // Lower bone: mirrored, and only 200 pt because its side carries
            // two of the five descendants.
            assert(svg_line(svg, 3, out x1, out y1, out x2, out y2));
            near(x2, -47.835, 0.01, "bone 2 end x");
            near(y2, 498.054, 0.01, "bone 2 end y");

            // Cause labels keep Mermaid's box: text height + 4.
            try {
                var re = new Regex("class=\"ishikawa-label-box\"[^/]*height=\"([-0-9.]+)\"");
                MatchInfo m;
                assert(re.match(svg, 0, out m));
                near(double.parse(m.fetch(1)), 21.0156, 0.01, "cause label box height");
            } catch (RegexError e) {
                assert_not_reached();
            }

            // The head is a wedge whose quadratic control point is at w * 2.4,
            // and every bone carries an arrowhead pointing into the spine.
            assert(svg.contains("class=\"ishikawa-head\""));
            try {
                var re = new Regex("class=\"ishikawa-head\" d=\"M 0 ([-0-9.]+) L 0 ([-0-9.]+) Q ([-0-9.]+) 300");
                MatchInfo m;
                assert(re.match(svg, 0, out m));
                near(double.parse(m.fetch(2)) - double.parse(m.fetch(1)), 103.378, 0.5, "head height");
                assert(double.parse(m.fetch(3)) >= 144.0);
            } catch (RegexError e) {
                assert_not_reached();
            }
            assert(svg.contains("class=\"ishikawa-arrow\""));
        }

        public static void test_ishikawa_nested_sub_bones() {
            // Depth 3 sub-causes get diagonal bones inside the parent's wedge,
            // laid out post-order so they stay there. Numbers from mmdc.
            string svg = fish_svg(fish("""ishikawa-beta
Defects in paint finish
    Machine
        Spray gun worn
            Nozzle clogged
            Seal leaking
        Oven temperature drifts
    Method
        No primer step
        Cure time too short
    Material
        Paint batch varies
    Measurement
        Gauge not calibrated
    Manpower
        New operators
    Environment
        Humidity
"""));
            double x1, y1, x2, y2;
            // bone, stub for "Oven temperature drifts", the 70 pt base bone
            // for "Spray gun worn", then its two diagonals.
            assert(svg_line(svg, 2, out x1, out y1, out x2, out y2));
            near(x1, -36.70, 0.02, "parent bone x0");
            near(x2, -106.70, 0.02, "parent bone x1");
            near(x2 - x1, -70.0, 0.01, "base 60 + 2 children * 5");
            assert(svg_line(svg, 3, out x1, out y1, out x2, out y2));
            near(x1, -83.37, 0.02, "diagonal 1 x0");
            near(y1, 181.17, 0.02, "diagonal 1 y0");
            near(x2, -91.72, 0.02, "diagonal 1 x1");
            near(y2, 121.75, 0.02, "diagonal 1 y1");
            assert(svg_line(svg, 4, out x1, out y1, out x2, out y2));
            near(x1, -60.03, 0.02, "diagonal 2 x0");
            near(x2, -76.73, 0.02, "diagonal 2 x1");
            near(y2, 62.34, 0.02, "diagonal 2 y1");

            // Post-order on the odd depth: "Seal leaking" is written first.
            int seal = svg.index_of("Seal leaking");
            int nozzle = svg.index_of("Nozzle clogged");
            assert(seal > 0 && nozzle > 0 && seal < nozzle);
        }

        public static void test_ishikawa_effect_only_and_empty() {
            // An effect with no causes: a zero-length spine and just the head
            // (mmdc's view box is 133.34 x 112 for "Effect only").
            string svg = fish_svg(fish("ishikawa\nEffect only\n"));
            try {
                var re = new Regex(
                    "class=\"ishikawa-spine\" x1=\"([-0-9.]+)\" y1=\"([-0-9.]+)\" x2=\"([-0-9.]+)\" y2=\"([-0-9.]+)\"");
                MatchInfo m;
                assert(re.match(svg, 0, out m));
                near(double.parse(m.fetch(1)), 0.0, 0.01, "degenerate spine x1");
                near(double.parse(m.fetch(1)), double.parse(m.fetch(3)), 0.01, "degenerate spine");
                near(double.parse(m.fetch(2)), 250.0, 0.01, "effect-only spine y");
            } catch (RegexError e) {
                assert_not_reached();
            }
            assert(!svg.contains("ishikawa-branch"));

            // A bare keyword: nothing drawn, but still a real page rather than
            // the 1x1 image a zero-sized view box would export to.
            string blank = fish_svg(fish("ishikawa\n"));
            assert(!blank.contains("<line"));
            assert(!blank.contains("ishikawa-head"));
            assert(blank.contains("viewBox=\"-20 -20 140 90\""));
        }

        // ──────────────────────────────── exports

        public static void test_exports() {
            var engine = new DiagramEngine("dot");
            string dir = DirUtils.make_tmp("gdiagram-treeview-XXXXXX");
            foreach (string src in new string[] { INDENTED, BOXED, FISHBONE }) {
                foreach (string fmt in new string[] { "png", "svg", "pdf" }) {
                    string path = Path.build_filename(dir, "out." + fmt);
                    bool ok = false;
                    if (fmt == "png") ok = engine.export_to_png(src, "test.mmd", null, path);
                    else if (fmt == "svg") ok = engine.export_to_svg(src, "test.mmd", null, path);
                    else ok = engine.export_to_pdf(src, "test.mmd", null, path);
                    if (!ok) error("export to %s failed", fmt);
                    if (!FileUtils.test(path, FileTest.EXISTS)) error("%s not written", path);
                    int64 size = 0;
                    try {
                        var info = File.new_for_path(path).query_info("standard::size", 0);
                        size = info.get_size();
                    } catch (Error e) {
                        error("stat %s: %s", path, e.message);
                    }
                    if (size < 512) error("%s is only %lld bytes", path, size);
                    FileUtils.unlink(path);
                }
            }
            DirUtils.remove(dir);
        }

        // ──────────────────────────────── stats / lint / outline inputs

        public static void test_stats_and_lint() {
            var stats = new DiagramStats();
            stats.analyze_mermaid_tree_view(tree(INDENTED), INDENTED);
            assert(stats.node_count == 6);
            assert(stats.edge_count == 2);              // src/ and util/
            assert(stats.diagram_type == "Mermaid TreeView");

            var fstats = new DiagramStats();
            fstats.analyze_mermaid_ishikawa(fish(FISHBONE), FISHBONE);
            assert(fstats.node_count == 10);
            assert(fstats.edge_count == 4);             // the four main bones
            assert(fstats.diagram_type == "Mermaid Ishikawa");

            // A main cause with no sub-causes is drawn at a fifth of the
            // length, which the linter calls out.
            var linter = new DiagramLinter();
            linter.lint_ishikawa(fish("ishikawa\nEffect\n    Alone\n    Other\n        Detail\n"));
            bool mentioned = false;
            foreach (var m in linter.messages) {
                if (m.message.contains("Alone")) mentioned = true;
            }
            assert(mentioned);

            var validator = new DiagramValidator();
            validator.validate_tree_view(tree(INDENTED));
            assert(!validator.has_issues());
            validator.validate_ishikawa(fish(FISHBONE));
            assert(!validator.has_issues());
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/mermaid-treeview/parse/indentation",
            ReviewMermaidTreeViewTests.test_indentation_tree);
        Test.add_func("/mermaid-treeview/parse/box-drawing",
            ReviewMermaidTreeViewTests.test_box_drawing_matches_indentation);
        Test.add_func("/mermaid-treeview/parse/box-drawing-widths",
            ReviewMermaidTreeViewTests.test_box_drawing_heavy_and_segment_width);
        Test.add_func("/mermaid-treeview/parse/box-drawing-errors",
            ReviewMermaidTreeViewTests.test_box_drawing_decoration_and_errors);
        Test.add_func("/mermaid-treeview/parse/annotations",
            ReviewMermaidTreeViewTests.test_annotations);
        Test.add_func("/mermaid-treeview/detection",
            ReviewMermaidTreeViewTests.test_detection);
        Test.add_func("/mermaid-treeview/render/rows",
            ReviewMermaidTreeViewTests.test_tree_view_row_geometry);
        Test.add_func("/mermaid-treeview/render/icons-highlight",
            ReviewMermaidTreeViewTests.test_tree_view_icon_offset_and_highlight);
        Test.add_func("/mermaid-treeview/render/descriptions",
            ReviewMermaidTreeViewTests.test_tree_view_description_column);
        Test.add_func("/mermaid-ishikawa/parse/structure",
            ReviewMermaidTreeViewTests.test_ishikawa_structure);
        Test.add_func("/mermaid-ishikawa/parse/base-level",
            ReviewMermaidTreeViewTests.test_ishikawa_base_level_and_noise);
        Test.add_func("/mermaid-ishikawa/parse/keywords",
            ReviewMermaidTreeViewTests.test_ishikawa_keyword_forms);
        Test.add_func("/mermaid-ishikawa/render/spine-bones",
            ReviewMermaidTreeViewTests.test_ishikawa_spine_and_bones);
        Test.add_func("/mermaid-ishikawa/render/nested-bones",
            ReviewMermaidTreeViewTests.test_ishikawa_nested_sub_bones);
        Test.add_func("/mermaid-ishikawa/render/degenerate",
            ReviewMermaidTreeViewTests.test_ishikawa_effect_only_and_empty);
        Test.add_func("/mermaid-treeview/exports", ReviewMermaidTreeViewTests.test_exports);
        Test.add_func("/mermaid-treeview/stats-lint",
            ReviewMermaidTreeViewTests.test_stats_and_lint);
        return Test.run();
    }
}
