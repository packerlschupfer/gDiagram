/*
 * review_mermaid_structural2_test.vala — second round of Mermaid class / ER / state /
 * requirement / block fidelity findings, compared with Mermaid CLI 11.17:
 *
 *   R1  ER relationships draw crow's-foot markers instead of text cardinalities
 *   R2  "I ()-- J" draws I as a bare lollipop circle, not a class box
 *   R3  "--" inside a composite state splits it into concurrent regions
 *   R4  requirement boxes match Mermaid's header/rows and relationship line styles
 *   R5  block "x--x" ends draw an X, not a tee
 *   R6  empty block grid cells ("space") stay out of the outline
 *
 * The outline case needs a display: meson runs the suite under xvfb-run and the case
 * skips itself where Gtk cannot be initialised.
 */
using GDiagram;

namespace GDiagram.Tests {

    public class ReviewMermaidStructural2Tests {

        private static void check(bool ok, string what, string context = "") {
            if (!ok) {
                printerr("\nFAILED: %s\n%s\n", what, context);
                assert_not_reached();
            }
        }

        private static string dot_of(string source) {
            string? dot = new DiagramEngine("dot").generate_dot(source, "x.mmd", null);
            check(dot != null, "dot generated", source);
            return dot;
        }

        private static Object ast_of(string source, DiagramType expected) {
            var r = new DiagramEngine("dot").parse(source, "x.mmd");
            check(r.diagram_type == expected, "detected " + r.diagram_type.to_string(), source);
            return r.ast;
        }

        private static string svg_of(string source) {
            string path = Path.build_filename(Environment.get_tmp_dir(),
                                              "gd_str2_%u.svg".printf(Random.next_int()));
            check(new DiagramEngine("dot").export_to_svg(source, "x.mmd", null, path),
                  "svg exported", source);
            string text;
            try {
                FileUtils.get_contents(path, out text);
            } catch (FileError e) {
                check(false, "svg read: " + e.message);
                return "";
            }
            FileUtils.unlink(path);
            return text;
        }

        // The DOT line declaring or connecting `prefix` ("A -> B " / "A [")
        private static string line_starting(string dot, string prefix) {
            foreach (string line in dot.split("\n")) {
                if (line.strip().has_prefix(prefix)) return line.strip();
            }
            return "";
        }

        // ==================== R1: ER crow's feet ====================

        // Every cardinality gets Mermaid's marker pair; the text cardinalities are gone
        public static void test_r1_er_crows_foot_markers() {
            string src = "erDiagram\n" +
                         "    A ||--o{ B : places\n" +
                         "    C |o--|{ D : uses\n" +
                         "    E }o..o| F : maybe\n";
            string dot = dot_of(src);

            string ab = line_starting(dot, "A -> B");
            check(ab.contains("dir=both"), "A->B is two-ended", ab);
            check(ab.contains("arrowtail=teetee"), "|| tail is a double bar", ab);
            check(ab.contains("arrowhead=crowodot"), "o{ head is crow + circle", ab);
            check(ab.contains("label=\"places\""), "relationship label kept", ab);

            string cd = line_starting(dot, "C -> D");
            check(cd.contains("arrowtail=teeodot"), "|o tail is bar + circle", cd);
            check(cd.contains("arrowhead=crowtee"), "|{ head is crow + bar", cd);

            string ef = line_starting(dot, "E -> F");
            check(ef.contains("arrowtail=crowodot"), "}o tail is crow + circle", ef);
            check(ef.contains("arrowhead=teeodot"), "o| head is bar + circle", ef);
            check(ef.contains("style=dashed"), "'..' stays non-identifying", ef);

            check(!dot.contains("taillabel="), "no text cardinality at the tail", dot);
            check(!dot.contains("headlabel="), "no text cardinality at the head", dot);
            check(!dot.contains("dir=none"), "edges are no longer undirected", dot);
            check(!dot.contains("\"0..*\"") && !dot.contains("\"1..*\""),
                  "no 0..*/1..* text left", dot);
        }

        // The markers survive to the render: an ER diagram has no round shapes of its
        // own, so an <ellipse> can only be the zero-or-more circle
        public static void test_r1_er_markers_rendered() {
            string svg = svg_of("erDiagram\n    A ||--o{ B : places\n");
            check(svg.contains("class=\"edge\""), "edge group present", svg);
            check(svg.contains("<ellipse"), "the zero circle is drawn", svg);
            check(!svg.contains(">0..*<"), "no cardinality text drawn", svg);
        }

        // ==================== R2: class lollipop interfaces ====================

        public static void test_r2_lollipop_interface_has_no_box() {
            string src = "classDiagram\n" +
                         "    class J {\n        +doWork()\n    }\n" +
                         "    I ()-- J\n" +
                         "    class K {\n        +run()\n    }\n" +
                         "    K --() L\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.find_class("I") != null && d.find_class("I").lollipop_interface,
                  "I is marked as a lollipop interface");
            check(d.find_class("L") != null && d.find_class("L").lollipop_interface,
                  "L is marked as a lollipop interface");
            check(!d.find_class("J").lollipop_interface, "J stays a class");

            string dot = dot_of(src);
            string i_line = line_starting(dot, "I [");
            check(i_line.contains("shape=plaintext"), "I is drawn as bare text", i_line);
            check(!i_line.contains("<TABLE"), "I has no class box", i_line);
            check(i_line.contains("label=\"I\""), "I keeps its name", i_line);
            string l_line = line_starting(dot, "L [");
            check(l_line.contains("shape=plaintext") && !l_line.contains("<TABLE"),
                  "L is drawn as bare text", l_line);
            check(line_starting(dot, "J [").contains("<TABLE"), "J keeps its box",
                  line_starting(dot, "J ["));

            string edge = line_starting(dot, "I -> J");
            check(edge.contains("arrowtail=odot"), "the lollipop circle is the edge marker", edge);
            check(line_starting(dot, "K -> L").contains("arrowhead=odot"),
                  "the circle sits at the end it was written on", line_starting(dot, "K -> L"));
        }

        // Mermaid only converts the end when the other end carries no marker
        public static void test_r2_lollipop_with_other_marker_stays_a_class() {
            string src = "classDiagram\n    I ()--|> J\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(!d.find_class("I").lollipop_interface, "I stays a class next to an arrow end");
            check(line_starting(dot_of(src), "I [").contains("<TABLE"), "I keeps its box");
        }

        // ==================== R3: concurrent state regions ====================

        public static void test_r3_concurrent_regions() {
            string src = "stateDiagram-v2\n" +
                         "    [*] --> Active\n" +
                         "    state Active {\n" +
                         "        [*] --> NumLockOff\n" +
                         "        NumLockOff --> NumLockOn : press\n" +
                         "        --\n" +
                         "        [*] --> CapsLockOff\n" +
                         "        CapsLockOff --> CapsLockOn : press\n" +
                         "    }\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            check(d.find_state("NumLockOff").region == 0, "NumLockOff is in region 0");
            check(d.find_state("CapsLockOff").region == 1, "CapsLockOff is in region 1");
            check(d.find_state("CapsLockOn").region == 1, "CapsLockOn is in region 1");

            // Each region keeps its own [*] start marker
            int starts = 0;
            foreach (var s in d.states) {
                if (s.state_type == MermaidStateType.START && s.parent_id == "Active") starts++;
            }
            check(starts == 2, "one start marker per region, got %d".printf(starts));

            string dot = dot_of(src);
            check(dot.contains("subgraph cluster_Active {"), "the composite is a cluster", dot);
            check(dot.contains("subgraph cluster_Active_r0 {"), "region 0 is a sub-cluster", dot);
            check(dot.contains("subgraph cluster_Active_r1 {"), "region 1 is a sub-cluster", dot);

            // Both region clusters are nested inside the composite's cluster and dashed
            int composite_at = dot.index_of("subgraph cluster_Active {");
            int r0 = dot.index_of("subgraph cluster_Active_r0 {");
            int r1 = dot.index_of("subgraph cluster_Active_r1 {");
            check(composite_at < r0 && r0 < r1, "regions come after the composite opens", dot);
            string region_block = dot.substring(r0, r1 - r0);
            check(region_block.contains("style=\"dashed,filled\";"),
                  "the region separator is a dashed border", region_block);
            check(region_block.contains("NumLockOff") && region_block.contains("NumLockOn"),
                  "region 0 holds its own states", region_block);
            check(!region_block.contains("CapsLock"), "region 0 holds no region 1 state", region_block);
        }

        // A composite without "--" keeps exactly one region and no extra cluster
        public static void test_r3_single_region_unchanged() {
            string dot = dot_of("stateDiagram-v2\n    state Active {\n        A --> B\n    }\n");
            check(dot.contains("subgraph cluster_Active {"), "composite cluster present", dot);
            check(!dot.contains("cluster_Active_r0"), "no region sub-cluster without '--'", dot);
        }

        // ==================== R4: requirement diagram look ====================

        public static void test_r4_requirement_boxes() {
            string src = "requirementDiagram\n" +
                         "    functionalRequirement login_req {\n" +
                         "        id: 1.1\n" +
                         "        text: Users shall log in.\n" +
                         "        risk: medium\n" +
                         "        verifymethod: inspection\n" +
                         "    }\n" +
                         "    element auth_module {\n" +
                         "        type: software component\n" +
                         "        docref: SDD/auth\n" +
                         "    }\n" +
                         "    auth_module - satisfies -> login_req\n" +
                         "    auth_module - contains -> login_req\n";
            string dot = dot_of(src);
            check(dot.contains("rankdir=TB"), "Mermaid lays requirements out top-down", dot);

            // The type header, then the bold name, then the body rows
            check(dot.contains("&lt;&lt;Functional Requirement&gt;&gt;"),
                  "the type header is the spelled-out type", dot);
            check(dot.contains("<B>login_req</B>"), "the name is bold", dot);
            check(dot.contains("ID: 1.1"), "the id row", dot);
            check(dot.contains("Text: Users shall log in."), "the text row", dot);
            check(dot.contains("Risk: Medium"), "the risk row is title-cased", dot);
            check(dot.contains("Verification: Inspection"), "the verifymethod row", dot);
            check(!dot.contains("risk: medium"), "no lower-case risk row left", dot);

            check(dot.contains("&lt;&lt;Element&gt;&gt;"), "the element header", dot);
            check(dot.contains("Type: software component"), "the element type row", dot);
            check(dot.contains("Doc Ref: SDD/auth"), "the element docref row", dot);

            // One fill for every box, no risk-coloured borders
            var palette = ThemeManager.get_active_palette();
            check(dot.contains("BGCOLOR=\"%s\"".printf(palette.node_fill)),
                  "boxes use the node fill", dot);
            check(!dot.contains(palette.warning), "no risk-coloured border", dot);
        }

        public static void test_r4_requirement_edges() {
            string src = "requirementDiagram\n" +
                         "    requirement a {\n        id: 1\n    }\n" +
                         "    requirement b {\n        id: 2\n    }\n" +
                         "    a - satisfies -> b\n" +
                         "    a - contains -> b\n";
            string dot = dot_of(src);
            string satisfies = "";
            string contains = "";
            foreach (string line in dot.split("\n")) {
                if (line.contains("satisfies")) satisfies = line.strip();
                if (line.contains("contains")) contains = line.strip();
            }
            check(satisfies.contains("label=\"<<satisfies>>\""),
                  "Mermaid labels the line <<satisfies>>", satisfies);
            check(satisfies.contains("style=dashed"), "non-containment lines are dashed", satisfies);
            check(satisfies.contains("arrowhead=vee"), "open arrow at the target", satisfies);
            check(contains.contains("arrowtail=odot"), "contains is marked at the source", contains);
            check(!contains.contains("style=dashed"), "contains is a solid line", contains);
            check(!dot.contains("style=dotted"), "no dotted relationship lines left", dot);
        }

        // ==================== R5: block cross link ends ====================

        public static void test_r5_block_cross_end() {
            string src = "block-beta\n  columns 2\n  A[\"A\"] B[\"B\"]\n  A x--x B\n";
            string dot = dot_of(src);
            string edge = line_starting(dot, "\"A\" -> \"B\"");
            check(edge.contains("id=\"gdblkx_0\""), "the cross edge is tagged for the SVG pass", edge);
            check(edge.contains("arrowhead=none"), "no Graphviz arrowhead on a cross end", edge);
            check(!edge.contains("arrowhead=tee"), "the tee is gone", edge);

            string svg = svg_of(src);
            int at = svg.index_of("id=\"gdblkx_0\"");
            check(at >= 0, "the tagged edge survives into the SVG", svg);
            string group = svg.substring(at, int.min(600, svg.length - at));
            int close = group.index_of("</g>");
            if (close > 0) group = group.substring(0, close);
            check(group.contains("stroke-width=\"1.6\""), "the X is drawn on the edge", group);
            // Two crossing strokes in one path: "M..L.. M..L.."
            int moves = 0;
            int pos = 0;
            string d = group.substring(group.index_of("stroke-width=\"1.6\""));
            while ((pos = d.index_of("M", pos)) >= 0) { moves++; pos++; }
            check(moves == 2, "the X is two crossing strokes, got %d".printf(moves), group);
        }

        // A plain arrow end is untouched
        public static void test_r5_block_arrow_end_unchanged() {
            string dot = dot_of("block-beta\n  columns 2\n  A[\"A\"] B[\"B\"]\n  A --> B\n");
            string edge = line_starting(dot, "\"A\" -> \"B\"");
            check(edge.contains("arrowhead=normal"), "a normal arrow stays normal", edge);
            check(!edge.contains("gdblkx_"), "no cross tag on a normal arrow", edge);
        }

        // ==================== R6: outline entries ====================

        // Needs a display (Gtk.ListBox): skipped where Gtk cannot start
        public static void test_r6_outline_skips_spaces() {
            if (!Gtk.init_check()) {
                Test.skip("no display for Gtk");
                return;
            }
            string src = "block-beta\n  columns 3\n  A[\"Alpha\"] space B[\"Beta\"]\n  A --> B\n";
            var engine = new DiagramEngine("dot");
            var result = engine.parse(src, "x.mmd");
            var list = new Gtk.ListBox();
            var controller = new OutlineController(list);
            controller.update(result.diagram_type, result.ast);

            var rows = new StringBuilder();
            for (var child = list.get_first_child(); child != null; child = child.get_next_sibling()) {
                var row = child as OutlineRow;
                if (row == null) continue;
                rows.append(row.node.text).append("\n");
            }
            string got = rows.str;
            check(got.contains("Alpha"), "the named blocks are listed", got);
            check(got.contains("Beta"), "the named blocks are listed", got);
            check(!got.contains("space"), "empty grid cells stay out of the outline", got);
        }

        // The stats footer counts real blocks, not the `space` layout cells
        public static void test_r6_stats_skips_spaces() {
            string src = "block-beta\n    columns 3\n    Alpha\n    space\n    Beta\n    space:2\n    Gamma\n";
            var result = new DiagramEngine("dot").parse(src, "x.mmd");
            var d = result.ast as MermaidBlock;
            check(d != null, "block diagram parsed", src);
            var stats = new DiagramStats();
            stats.analyze_mermaid_block(d, src);
            check(stats.node_count == 3, "3 blocks, got %d".printf(stats.node_count), src);
        }

        public static int main(string[] args) {
            Test.init(ref args);
            Test.add_func("/review-mermaid-structural2/r1/er-crows-foot", test_r1_er_crows_foot_markers);
            Test.add_func("/review-mermaid-structural2/r1/er-markers-rendered", test_r1_er_markers_rendered);
            Test.add_func("/review-mermaid-structural2/r2/lollipop-no-box", test_r2_lollipop_interface_has_no_box);
            Test.add_func("/review-mermaid-structural2/r2/lollipop-with-marker",
                          test_r2_lollipop_with_other_marker_stays_a_class);
            Test.add_func("/review-mermaid-structural2/r3/concurrent-regions", test_r3_concurrent_regions);
            Test.add_func("/review-mermaid-structural2/r3/single-region", test_r3_single_region_unchanged);
            Test.add_func("/review-mermaid-structural2/r4/requirement-boxes", test_r4_requirement_boxes);
            Test.add_func("/review-mermaid-structural2/r4/requirement-edges", test_r4_requirement_edges);
            Test.add_func("/review-mermaid-structural2/r5/block-cross-end", test_r5_block_cross_end);
            Test.add_func("/review-mermaid-structural2/r5/block-arrow-end", test_r5_block_arrow_end_unchanged);
            Test.add_func("/review-mermaid-structural2/r6/outline-skips-spaces", test_r6_outline_skips_spaces);
            Test.add_func("/review-mermaid-structural2/r6/stats-skips-spaces", test_r6_stats_skips_spaces);
            return Test.run();
        }
    }
}
