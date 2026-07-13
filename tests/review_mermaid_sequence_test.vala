namespace GDiagram.Tests {
    /**
     * Mermaid sequence diagrams and ZenUML, compared with the Mermaid CLI 11.17:
     *
     *  Q1/Q2 frames (loop, alt/else, opt, par/and, critical/option, break) are drawn around
     *        their rows, nested ones inside, "rect" blocks get their colour
     *  Q3    critical/option and "<<->>" render
     *  Q4    notes sit at their row, left of / right of / over their lifelines
     *  Q5    activation bars, boxes, actor figures, create/destroy, autonumber, links
     *  Q6    arrow types: heads, crosses, async chevrons, dotted lines
     *  Q7/Q8 label text is the source text; quoted aliases lose their quotes
     *  Z1-Z5 ZenUML calls without "A ->", returns, blocks, a sequence layout, label contrast
     *
     * Geometry is read from the exported SVG.
     */
    public class ReviewMermaidSequenceTests {

        private class Box : Object {
            public double x0 = double.MAX;
            public double y0 = double.MAX;
            public double x1 = -double.MAX;
            public double y1 = -double.MAX;

            public void add(double x, double y) {
                x0 = double.min(x0, x);
                x1 = double.max(x1, x);
                y0 = double.min(y0, y);
                y1 = double.max(y1, y);
            }

            public double cx() { return (x0 + x1) / 2; }
            public double cy() { return (y0 + y1) / 2; }
        }

        private class Edge : Object {
            public string title;
            public Box box = new Box();   // the line
            public Box tip = new Box();   // the line with its arrowheads
            public bool dashed;
            public int heads;
            public bool labelled;
        }

        private static string svg_of(string src, string name = "t.mmd") {
            string path = Path.build_filename(Environment.get_tmp_dir(),
                                              "gd_mmd_seq_%s.svg".printf(Uuid.string_random()));
            bool ok = new DiagramEngine("dot").export_to_svg(src, name, null, path);
            if (!ok) {
                printerr("\nexport failed for:\n%s\n", src);
                assert_not_reached();
            }
            string svg;
            try {
                FileUtils.get_contents(path, out svg);
            } catch (FileError e) {
                error("read svg: %s", e.message);
            }
            FileUtils.remove(path);
            return svg;
        }

        private static string dot_of(string src, string name = "t.mmd") {
            string? dot = new DiagramEngine("dot").generate_dot(src, name, null);
            assert(dot != null);
            return dot;
        }

        private static MermaidSequenceDiagram parse_seq(string src) {
            var r = new DiagramEngine("dot").parse(src, "t.mmd");
            assert(r.diagram_type == DiagramType.MERMAID_SEQUENCE);
            return (MermaidSequenceDiagram) r.ast;
        }

        private static MermaidZenUML parse_zen(string src) {
            var r = new DiagramEngine("dot").parse(src, "t.mmd");
            assert(r.diagram_type == DiagramType.MERMAID_ZENUML);
            return (MermaidZenUML) r.ast;
        }

        private static string unescape(string s) {
            return s.replace("&#45;", "-").replace("&gt;", ">").replace("&lt;", "<")
                    .replace("&quot;", "\"").replace("&#39;", "'").replace("&amp;", "&");
        }

        private static void add_numbers(Box box, string text) {
            try {
                var num = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                MatchInfo nm;
                num.match(text, 0, out nm);
                while (nm.matches()) {
                    box.add(double.parse(nm.fetch(1)), double.parse(nm.fetch(2)));
                    nm.next();
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
        }

        private static Gee.ArrayList<Edge> edges(string svg) {
            var list = new Gee.ArrayList<Edge>();
            try {
                var re = new Regex("<g id=\"edge[0-9]+\" class=\"edge\">\\s*<title>([^<]*)</title>(.*?)</g>",
                                   RegexCompileFlags.DOTALL);
                var path = new Regex("<path [^>]*d=\"([^\"]*)\"");
                MatchInfo mi;
                re.match(svg, 0, out mi);
                while (mi.matches()) {
                    var e = new Edge();
                    e.title = unescape(mi.fetch(1));
                    string body = mi.fetch(2);
                    MatchInfo pm;
                    if (path.match(body, 0, out pm)) {
                        string d = pm.fetch(1);
                        add_numbers(e.box, d);
                        add_numbers(e.tip, d);
                    }
                    MatchInfo hm;
                    var poly = new Regex("<polygon [^>]*points=\"([^\"]*)\"");
                    poly.match(body, 0, out hm);
                    while (hm.matches()) {
                        add_numbers(e.tip, hm.fetch(1));
                        hm.next();
                    }
                    e.dashed = body.contains("stroke-dasharray");
                    e.heads = body.split("<polygon").length - 1;
                    e.labelled = body.contains("<text");
                    list.add(e);
                    mi.next();
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            return list;
        }

        // Message arrows: the laid-out "_pNa->_pNb" edges (or labelled edges of a graph layout),
        // top to bottom
        private static Gee.ArrayList<Edge> message_edges(string svg) {
            var list = new Gee.ArrayList<Edge>();
            try {
                var re = new Regex("^_p([0-9]+)a->_p\\1b$");
                foreach (var e in edges(svg)) {
                    if (re.match(e.title) || e.labelled) {
                        list.add(e);
                    }
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            list.sort((a, b) => a.box.cy() < b.box.cy() ? -1 : (a.box.cy() > b.box.cy() ? 1 : 0));
            return list;
        }

        // Bounding box of a node's shapes, null if none
        private static Box? node_box(string svg, string id) {
            try {
                var re = new Regex("<g id=\"node[0-9]+\" class=\"node\">\\s*<title>%s</title>(.*?)</g>".printf(Regex.escape_string(id)),
                                   RegexCompileFlags.DOTALL);
                MatchInfo mi;
                if (!re.match(svg, 0, out mi)) {
                    return null;
                }
                var box = new Box();
                var pts = new Regex("points=\"([^\"]*)\"");
                string group = mi.fetch(1);
                MatchInfo pm;
                pts.match(group, 0, out pm);
                while (pm.matches()) {
                    add_numbers(box, pm.fetch(1));
                    pm.next();
                }
                // Graphviz's own shapes ("<path fill=..."), not drawn icons ("<path class=...")
                var paths = new Regex("<path fill=[^>]*d=\"([^\"]*)\"");
                paths.match(group, 0, out pm);
                while (pm.matches()) {
                    add_numbers(box, pm.fetch(1));
                    pm.next();
                }
                var ell = new Regex("<ellipse [^>]*cx=\"([-0-9.]+)\" cy=\"([-0-9.]+)\" rx=\"([-0-9.]+)\" ry=\"([-0-9.]+)\"");
                if (ell.match(group, 0, out pm)) {
                    double cx = double.parse(pm.fetch(1));
                    double cy = double.parse(pm.fetch(2));
                    box.add(cx - double.parse(pm.fetch(3)), cy - double.parse(pm.fetch(4)));
                    box.add(cx + double.parse(pm.fetch(3)), cy + double.parse(pm.fetch(4)));
                }
                return box.x0 <= box.x1 ? box : null;
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
        }

        // Boxes of nodes whose title starts with `prefix`, plus cluster outlines when `clusters`
        private static Gee.ArrayList<Box> boxes_with_prefix(string svg, string prefix, bool clusters) {
            var list = new Gee.ArrayList<Box>();
            try {
                var re = new Regex("<g id=\"(node|clust)[0-9]+\" class=\"(node|cluster)\">\\s*<title>([^<]*)</title>(.*?)</g>",
                                   RegexCompileFlags.DOTALL);
                var pts = new Regex("points=\"([^\"]*)\"");
                var paths = new Regex("<path fill=[^>]*d=\"([^\"]*)\"");
                MatchInfo mi;
                re.match(svg, 0, out mi);
                while (mi.matches()) {
                    bool is_cluster = mi.fetch(2) == "cluster";
                    if ((is_cluster && clusters) || (!is_cluster && mi.fetch(3).has_prefix(prefix))) {
                        var box = new Box();
                        string group = mi.fetch(4);
                        MatchInfo pm;
                        pts.match(group, 0, out pm);
                        while (pm.matches()) {
                            add_numbers(box, pm.fetch(1));
                            pm.next();
                        }
                        paths.match(group, 0, out pm);
                        while (pm.matches()) {
                            add_numbers(box, pm.fetch(1));
                            pm.next();
                        }
                        if (box.x0 <= box.x1) {
                            list.add(box);
                        }
                    }
                    mi.next();
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            return list;
        }

        // Position of the first <text> whose content is `content`
        private static bool text_at(string svg, string content, out double x, out double y) {
            x = 0;
            y = 0;
            try {
                var re = new Regex("<text [^>]*x=\"([-0-9.]+)\" y=\"([-0-9.]+)\"[^>]*>([^<]*)</text>");
                MatchInfo mi;
                re.match(svg, 0, out mi);
                while (mi.matches()) {
                    if (unescape(mi.fetch(3)) == content) {
                        x = double.parse(mi.fetch(1));
                        y = double.parse(mi.fetch(2));
                        return true;
                    }
                    mi.next();
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            return false;
        }

        private static bool has_text(string svg, string content) {
            double x, y;
            return text_at(svg, content, out x, out y);
        }

        private static void expect_text(string svg, string content) {
            if (!has_text(svg, content)) {
                printerr("\nno text '%s' in SVG\n", content);
                assert_not_reached();
            }
        }

        // The message arrow right below a label text
        private static Edge message_below(string svg, string label) {
            double x, y;
            if (!text_at(svg, label, out x, out y)) {
                printerr("\nno label '%s'\n", label);
                assert_not_reached();
            }
            Edge? best = null;
            foreach (var e in message_edges(svg)) {
                double d = e.box.cy() - y;
                if (d >= -2 && d < 25 && (best == null || d < best.box.cy() - y)) {
                    best = e;
                }
            }
            if (best == null) {
                printerr("\nno message arrow below '%s'\n", label);
                assert_not_reached();
            }
            return best;
        }

        private static double head_x(string svg, string id) {
            var box = node_box(svg, id);
            if (box == null) {
                printerr("\nno node %s\n", id);
                assert_not_reached();
            }
            return box.cx();
        }

        private static void assert_horizontal(Gee.ArrayList<Edge> msgs, int expected) {
            if (msgs.size != expected) {
                printerr("\n%d message arrows, expected %d\n", msgs.size, expected);
                assert_not_reached();
            }
            foreach (var e in msgs) {
                if (e.box.y1 - e.box.y0 > 0.5) {
                    printerr("\nmessage %s is not horizontal: y %f..%f\n", e.title, e.box.y0, e.box.y1);
                    assert_not_reached();
                }
            }
        }

        // ---------------------------------------------------------------- Q1 / Q2

        public static void test_frame_covers_rows() {
            string svg = svg_of("sequenceDiagram\n    A->>B: before\n    loop every minute\n        A->>B: inside1\n        B-->>A: inside2\n    end\n    A->>B: after\n");
            var msgs = message_edges(svg);
            assert_horizontal(msgs, 4);
            double before = msgs[0].box.cy();
            double in1 = msgs[1].box.cy();
            double in2 = msgs[2].box.cy();
            double after = msgs[3].box.cy();
            bool found = false;
            foreach (var b in boxes_with_prefix(svg, "_frame", true)) {
                if (b.y0 < in1 - 10 && b.y1 > in2 && b.y0 > before && b.y1 < after &&
                    b.x0 <= head_x(svg, "actor_A") && b.x1 >= head_x(svg, "actor_B")) {
                    found = true;
                }
            }
            assert(found);
            expect_text(svg, "loop");
            expect_text(svg, "[every minute]");
        }

        public static void test_else_sections() {
            string svg = svg_of("sequenceDiagram\n    A->>B: hi\n    alt ok\n        B->>A: yes\n    else bad\n        B->>A: no\n    end\n");
            var msgs = message_edges(svg);
            assert_horizontal(msgs, 3);
            expect_text(svg, "[ok]");
            expect_text(svg, "[bad]");
            double yes = msgs[1].box.cy();
            double no = msgs[2].box.cy();
            bool separator = false;
            foreach (var e in edges(svg)) {
                if (e.dashed && e.box.y1 - e.box.y0 < 0.5 && e.box.cy() > yes && e.box.cy() < no && !msgs.contains(e)) {
                    separator = true;
                }
            }
            assert(separator);
        }

        public static void test_nested_frames() {
            string svg = svg_of("sequenceDiagram\n    participant Client\n    participant Server\n    loop Retry\n        Client->>Server: GET\n        alt Success\n            Server-->>Client: 200\n        else Error\n            Server-->>Client: 500\n        end\n    end\n");
            var frames = boxes_with_prefix(svg, "_frame", true);
            assert(frames.size == 2);
            Box outer = frames[0].y0 < frames[1].y0 ? frames[0] : frames[1];
            Box inner = outer == frames[0] ? frames[1] : frames[0];
            assert(inner.x0 > outer.x0 && inner.x1 < outer.x1 && inner.y0 > outer.y0 && inner.y1 < outer.y1);
            var msgs = message_edges(svg);
            assert_horizontal(msgs, 3);
            assert(msgs[0].box.cy() < inner.y0 && msgs[1].box.cy() > inner.y0 && msgs[2].box.cy() < inner.y1);
        }

        public static void test_rect_colour() {
            string svg = svg_of("sequenceDiagram\n    A->>B: x\n    rect rgb(200, 220, 255)\n        A->>B: r\n    end\n    rect rgba(0, 0, 255, 0.1)\n        A->>B: s\n    end\n");
            assert(svg.contains("fill=\"#c8dcff\"") || svg.contains("fill=\"#C8DCFF\""));
            assert(svg.contains("fill=\"#0000ff\"") || svg.contains("fill=\"#0000FF\""));
            // the coloured block lies behind the message it covers
            int block = svg.index_of("#c8dcff") >= 0 ? svg.index_of("#c8dcff") : svg.index_of("#C8DCFF");
            assert(block < svg.index_of("class=\"edge\""));
        }

        // ---------------------------------------------------------------- Q3

        public static void test_critical_option_bidirectional() {
            string svg = svg_of("sequenceDiagram\n    critical crit\n        A->>B: c\n    option alt\n        A->>B: c2\n    end\n    A<<->>B: bidir\n    A<<-->>B: dotted bidir\n");
            expect_text(svg, "critical");
            expect_text(svg, "[alt]");
            var bidir = message_below(svg, "bidir");
            assert(bidir.heads == 2 && !bidir.dashed);
            var dotted = message_below(svg, "dotted bidir");
            assert(dotted.heads == 2 && dotted.dashed);
        }

        // ---------------------------------------------------------------- Q4

        public static void test_notes_at_rows() {
            string svg = svg_of("sequenceDiagram\n    A->>B: one\n    Note right of B: after one\n    B->>A: two\n    Note left of A: at left\n    Note over A,B: spanning\n    A->>B: three\n");
            var msgs = message_edges(svg);
            assert_horizontal(msgs, 3);
            double ax = head_x(svg, "actor_A");
            double bx = head_x(svg, "actor_B");
            double x, y;
            assert(text_at(svg, "after one", out x, out y));
            assert(y > msgs[0].box.cy() && y < msgs[1].box.cy() && x > bx);
            assert(text_at(svg, "at left", out x, out y));
            assert(y > msgs[1].box.cy() && y < msgs[2].box.cy() && x < ax);
            var over = node_box(svg, "note_2");
            assert(over != null);
            assert(over.x0 < ax && over.x1 > bx && over.cy() > msgs[1].box.cy() && over.cy() < msgs[2].box.cy());
            // no connector edges from notes
            foreach (var e in edges(svg)) {
                assert(!e.title.has_prefix("note_"));
            }
        }

        // ---------------------------------------------------------------- Q5

        public static void test_activation_bars() {
            string svg = svg_of("sequenceDiagram\n    A->>+B: req\n    B-->>-A: resp\n    A->>B: again\n    activate B\n    B->>A: work\n    deactivate B\n");
            double bx = head_x(svg, "actor_B");
            var req = message_below(svg, "req");
            var resp = message_below(svg, "resp");
            var again = message_below(svg, "again");
            var work = message_below(svg, "work");
            var bars = boxes_with_prefix(svg, "_act", false);
            assert(bars.size == 2);
            bars.sort((a, b) => a.y0 < b.y0 ? -1 : 1);
            assert((bars[0].cx() - bx).abs() < 6 && (bars[0].y0 - req.box.cy()).abs() < 1 && (bars[0].y1 - resp.box.cy()).abs() < 1);
            assert((bars[1].cx() - bx).abs() < 6 && (bars[1].y0 - again.box.cy()).abs() < 1 && (bars[1].y1 - work.box.cy()).abs() < 1);
            // the arrow ends on the bar's edge, not on the lifeline
            // (Graphviz stops a filled head about 2pt short of its point for the pen width)
            assert((req.tip.x1 - bars[0].x0).abs() < 2.5);
        }

        public static void test_box_group() {
            string svg = svg_of("sequenceDiagram\n    box Aqua Group\n    participant A\n    end\n    participant B\n    A->>B: x\n");
            expect_text(svg, "Group");
            double ax = head_x(svg, "actor_A");
            double bx = head_x(svg, "actor_B");
            var boxes = boxes_with_prefix(svg, "_bg_box", false);
            assert(boxes.size == 1);
            assert(boxes[0].x0 < ax && boxes[0].x1 > ax && boxes[0].x1 < bx);
            assert(svg.contains("fill=\"aqua\""));
        }

        public static void test_actor_figure() {
            string svg = svg_of("sequenceDiagram\n    actor U as User\n    U->>B: hi\n");
            assert(svg.contains("gdfigure"));
            expect_text(svg, "User");
        }

        public static void test_create_destroy() {
            string svg = svg_of("sequenceDiagram\n    A->>B: hi\n    create participant C\n    A->>C: new\n    destroy C\n    A-xC: kill\n");
            var created = node_box(svg, "actor_C");
            assert(created != null);
            var made = message_below(svg, "new");
            var kill = message_below(svg, "kill");
            assert((created.cy() - made.box.cy()).abs() < 1);
            assert(created.cy() > node_box(svg, "actor_A").cy() + 20);
            // the arrow ends at the created head's edge
            assert((made.tip.x1 - created.x0).abs() < 2.5);
            // the destroyed participant's box is drawn at the destroying message
            bool at_kill = false;
            foreach (var b in boxes_with_prefix(svg, "s_C_", false)) {
                at_kill = at_kill || (b.cy() - kill.box.cy()).abs() < 1;
            }
            assert(at_kill);
        }

        public static void test_autonumber_and_links() {
            string src = "sequenceDiagram\n    autonumber\n    link A: Dashboard @ https://example.com\n    links B: {\"Repo\": \"https://example.com\"}\n    A->>B: first\n    B-->>A: second\n";
            var d = parse_seq(src);
            assert(!d.has_errors());
            assert(d.actors.size == 2 && d.messages.size == 2);
            string svg = svg_of(src);
            expect_text(svg, "first");
            expect_text(svg, "second");
            double x, y;
            assert(text_at(svg, "1", out x, out y));
            assert((x - head_x(svg, "actor_A")).abs() < 2);
            assert(text_at(svg, "2", out x, out y));
            assert((x - head_x(svg, "actor_B")).abs() < 2);
        }

        // ---------------------------------------------------------------- Q6

        private static int marks_near(string svg, string prefix, Edge msg) {
            int count = 0;
            foreach (var e in edges(svg)) {
                if (e.title.has_prefix(prefix) && e.box.y0 <= msg.box.cy() + 0.5 && e.box.y1 >= msg.box.cy() - 0.5 &&
                    (e.box.x1 >= msg.box.x1 - 12 && e.box.x0 <= msg.box.x1 + 1)) {
                    count++;
                }
            }
            return count;
        }

        public static void test_arrow_types() {
            string svg = svg_of("sequenceDiagram\n    A->>B: solid arrow\n    A-->>B: dotted arrow\n    A-xB: solid cross\n    A--xB: dotted cross\n    A-)B: solid async\n    A--)B: dotted async\n    A->B: solid line\n    A-->B: dotted line\n");
            assert_horizontal(message_edges(svg), 8);
            string[] labels = { "solid arrow", "dotted arrow", "solid cross", "dotted cross",
                                "solid async", "dotted async", "solid line", "dotted line" };
            int[] heads = { 1, 1, 0, 0, 0, 0, 0, 0 };
            int[] crosses = { 0, 0, 2, 2, 0, 0, 0, 0 };
            int[] chevrons = { 0, 0, 0, 0, 2, 2, 0, 0 };
            for (int i = 0; i < labels.length; i++) {
                var m = message_below(svg, labels[i]);
                bool dotted = labels[i].has_prefix("dotted");
                int cross = marks_near(svg, "_x", m);
                int chevron = marks_near(svg, "_o", m);
                if (m.dashed != dotted || m.heads != heads[i] || cross != crosses[i] || chevron != chevrons[i]) {
                    printerr("\n%s: dashed %s heads %d crosses %d chevrons %d\n", labels[i], m.dashed.to_string(),
                             m.heads, cross, chevron);
                    assert_not_reached();
                }
            }
        }

        // ---------------------------------------------------------------- Q7 / Q8

        public static void test_label_text() {
            var d = parse_seq("sequenceDiagram\n    A->>B: GET /a/b (x: 1) \"q\" Wait...\n    Note right of B: Processing...\n    Note over A: line1<br/>line2\n    B->>A: say #quot;hi#quot; #35;1\n    A->>B: Hi 👋 there\n");
            assert(!d.has_errors());
            assert(d.messages[0].text == "GET /a/b (x: 1) \"q\" Wait...");
            assert(d.notes[0].text == "Processing...");
            assert(d.notes[1].text == "line1\nline2");
            assert(d.messages[1].text == "say \"hi\" #1");
            assert(d.messages[2].text == "Hi 👋 there");
            string svg = svg_of("sequenceDiagram\n    A->>B: GET /a/b (x: 1)\n    Note over A: line1<br/>line2\n");
            expect_text(svg, "GET /a/b (x: 1)");
            expect_text(svg, "line1");
            expect_text(svg, "line2");
        }

        // Mermaid's sequence grammar has no string token for an actor, so the quotes
        // of `participant A as "API Gateway"` and of `box "Front End"` are part of the
        // text it draws (checked against the Mermaid CLI 11.17).
        public static void test_quoted_alias() {
            var d = parse_seq("sequenceDiagram\n    participant A as \"API Gateway\"\n    A->>B: x\n");
            assert(d.find_actor("A").alias == "\"API Gateway\"");
            var b = parse_seq("sequenceDiagram\n    box \"Front End\"\n    participant A\n    end\n    A->>B: x\n");
            assert(b.boxes.size == 1);
            assert(b.boxes[0].label == "\"Front End\"");
        }

        public static void test_parse_errors_kept() {
            assert(parse_seq("sequenceDiagram\n    Alice->>: Missing destination\n").has_errors());
            assert(parse_seq("sequenceDiagram\n    loop forever\n        A->>B: x\n").has_errors());
            assert(!parse_seq("sequenceDiagram\n    alt cond\n    else\n    end\n").has_errors());
        }

        public static void test_click_regions() {
            var engine = new DiagramEngine("dot");
            string src = "sequenceDiagram\n    participant A as Alice\n    A->>B: hello\n    Note over B: n\n";
            var result = engine.render(DiagramType.MERMAID_SEQUENCE, DiagramFormat.MERMAID, src);
            assert(result.surface != null);
            bool head = false;
            bool msg = false;
            foreach (var r in engine.last_regions) {
                head = head || (r.name == "actor_A" && r.source_line == 2 && r.width > 5);
                msg = msg || (r.name == "s_A_0" && r.source_line == 3 && r.width > 5);
            }
            assert(head && msg);
        }

        // ---------------------------------------------------------------- ZenUML

        public static void test_zen_calls_without_arrow() {
            var d = parse_zen("zenuml\n    A.start() {\n        B.check()\n    }\n");
            assert(d.messages.size == 2);
            assert(d.messages[0].to_name == "A");
            assert(d.messages[1].from_name == "A" && d.messages[1].to_name == "B");
            // the one-line form
            d = parse_zen("zenuml\n    A -> B.m() { B -> C.n() { return x } }\n");
            assert(d.messages.size == 3);
            assert(d.messages[2].is_return && d.messages[2].from_name == "C" && d.messages[2].to_name == "B");
        }

        public static void test_zen_returns() {
            var d = parse_zen("zenuml\n    A.start() {\n        if (ok) {\n            B.check()\n        }\n        return done\n    }\n");
            ZenMessage? ret = null;
            foreach (var m in d.messages) {
                if (m.is_return) {
                    ret = m;
                }
            }
            assert(ret != null && ret.method == "done" && ret.from_name == "A" && ret.to_name == d.messages[0].from_name);

            string auth;
            try {
                FileUtils.get_contents(Path.build_filename(Environment.get_variable("GDIAGRAM_SOURCE_ROOT"),
                                                           "examples/mermaid/zenuml/auth.mmd"), out auth);
            } catch (FileError e) {
                error("read auth.mmd: %s", e.message);
            }
            d = parse_zen(auth);
            var got = new StringBuilder();
            foreach (var m in d.messages) {
                if (m.is_return) {
                    got.append("%s>%s:%s ".printf(m.from_name, m.to_name, m.method));
                }
            }
            string expected = "UserDB>AuthService:userData AuthService>AuthService:token AuthService>Frontend:token Frontend>User:token ";
            if (got.str != expected) {
                printerr("\nreturns: %s\n", got.str);
                assert_not_reached();
            }
        }

        public static void test_zen_sequence_layout() {
            string auth;
            try {
                FileUtils.get_contents(Path.build_filename(Environment.get_variable("GDIAGRAM_SOURCE_ROOT"),
                                                           "examples/mermaid/zenuml/auth.mmd"), out auth);
            } catch (FileError e) {
                error("read auth.mmd: %s", e.message);
            }
            string svg = svg_of(auth);
            var msgs = message_edges(svg);
            // 3 calls + the self call's loop are separate; 4 straight messages + returns
            foreach (var e in msgs) {
                assert(e.box.y1 - e.box.y0 < 0.5);
            }
            assert(msgs.size >= 5);
            // heads in one row, left to right in declaration order
            string[] names = { "User", "Frontend", "AuthService", "UserDB" };
            double prev_x = -double.MAX;
            double row_y = double.NAN;
            foreach (string n in names) {
                var b = node_box(svg, n);
                assert(b != null);
                assert(b.cx() > prev_x);
                if (!row_y.is_nan()) {
                    assert((b.y1 - row_y).abs() < 1);
                }
                row_y = b.y1;
                prev_x = b.cx();
            }
            expect_text(svg, "Alt");
            expect_text(svg, "[userData.valid]");
            var frames = boxes_with_prefix(svg, "_frame", false);
            assert(frames.size == 1);
            var gen = message_below(svg, "generateToken(userData)");
            assert(gen.box.cy() > frames[0].y0 && gen.box.cy() < frames[0].y1);
            assert(boxes_with_prefix(svg, "_act", false).size >= 4);
            // returns are dashed
            var ret = message_below(svg, "userData");
            assert(ret.dashed);
        }

        public static void test_zen_label_contrast() {
            string dot = dot_of("zenuml\n    @Actor User\n    @Database DB #F5F5F5\n    User -> DB.query()\n");
            int checked_heads = 0;
            try {
                var re = new Regex("fillcolor=\"([^\"]+)\"[^\\n]*fontcolor=\"([^\"]+)\"");
                foreach (string line in dot.split("\n")) {
                    if (!line.contains("User") && !line.contains("DB")) {
                        continue;
                    }
                    MatchInfo mi;
                    if (re.match(line, 0, out mi)) {
                        string fill = mi.fetch(1);
                        string font = mi.fetch(2);
                        if (RenderUtils.contrast_text(fill) != font) {
                            printerr("\n%s text on %s: %s\n", font, fill, line);
                            assert_not_reached();
                        }
                        checked_heads++;
                    }
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            assert(checked_heads >= 2);
        }

        public static void test_zen_basic_example_valid() {
            string basic;
            try {
                FileUtils.get_contents(Path.build_filename(Environment.get_variable("GDIAGRAM_SOURCE_ROOT"),
                                                           "examples/mermaid/zenuml/basic.mmd"), out basic);
            } catch (FileError e) {
                error("read basic.mmd: %s", e.message);
            }
            // Mermaid 11.17 rejects named colours such as "#whitesmoke" in ZenUML
            assert(!basic.contains("#whitesmoke"));
            var d = parse_zen(basic);
            assert(!d.has_errors() && d.participants.size == 4);
        }

        public static void test_zen_click_regions() {
            var engine = new DiagramEngine("dot");
            string src = "zenuml\n    @Actor User\n    User -> DB.query() {\n        return rows\n    }\n";
            var result = engine.render(DiagramType.MERMAID_ZENUML, DiagramFormat.MERMAID, src);
            assert(result.surface != null);
            bool head = false;
            bool msg = false;
            foreach (var r in engine.last_regions) {
                head = head || (r.name == "User" && r.source_line == 2 && r.width > 5);
                msg = msg || (r.name == "_zm0" && r.source_line == 3 && r.width > 5);
            }
            assert(head && msg);
        }

        // A rect/box block must render on a dark palette too: an author's own alpha already
        // carries a fill-opacity from Graphviz, and a second attribute is invalid XML that
        // librsvg rejects, which killed the whole preview and PNG/PDF export.
        public static void test_rect_dark_palette_renders() {
            var saved = ThemeManager.get_active_palette();
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-dark"));
            string src = "sequenceDiagram\n    participant A\n    participant B\n" +
                         "    box rgb(220,240,255) Team\n    participant C\n    end\n" +
                         "    rect\n        A->>B: plain\n    end\n" +
                         "    rect rgba(255,0,0,0.3)\n        A->>C: alpha\n    end\n";
            var engine = new DiagramEngine("dot");
            var result = engine.render(DiagramType.MERMAID_SEQUENCE, DiagramFormat.MERMAID, src);
            string svg = "";
            string path = "/tmp/gd_rect_dark_test.svg";
            engine.export_to_svg(src, "x.mmd", null, path);
            try { FileUtils.get_contents(path, out svg); } catch (Error e) { assert_not_reached(); }
            FileUtils.remove(path);
            ThemeManager.set_active_palette(saved);

            // no tag may carry fill-opacity twice
            foreach (string tag in svg.split("<")) {
                string t = tag.substring(0, tag.index_of(">") >= 0 ? tag.index_of(">") : tag.length);
                int n = 0;
                int at = 0;
                while ((at = t.index_of("fill-opacity=", at)) >= 0) { n++; at += 13; }
                if (n > 1) {
                    printerr("\nFAILED: fill-opacity written twice: <%s>\n", t);
                    assert_not_reached();
                }
            }
            // the tint still applies to an explicit light fill, and the author's alpha survives
            assert(svg.contains("fill-opacity=\"0.22\" fill=\"#dcf0ff\""));
            // and the whole thing actually rasterises
            assert(result.surface != null);
        }

        public static int main(string[] args) {
            Test.init(ref args);
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
            Test.add_func("/mermaid-sequence/q1/frame-covers-rows", test_frame_covers_rows);
            Test.add_func("/mermaid-sequence/q2/else-sections", test_else_sections);
            Test.add_func("/mermaid-sequence/q2/nested-frames", test_nested_frames);
            Test.add_func("/mermaid-sequence/q2/rect-colour", test_rect_colour);
            Test.add_func("/mermaid-sequence/q3/critical-option-bidirectional", test_critical_option_bidirectional);
            Test.add_func("/mermaid-sequence/q4/notes-at-rows", test_notes_at_rows);
            Test.add_func("/mermaid-sequence/q5/activation-bars", test_activation_bars);
            Test.add_func("/mermaid-sequence/q5/box-group", test_box_group);
            Test.add_func("/mermaid-sequence/q5/actor-figure", test_actor_figure);
            Test.add_func("/mermaid-sequence/q5/create-destroy", test_create_destroy);
            Test.add_func("/mermaid-sequence/q5/autonumber-links", test_autonumber_and_links);
            Test.add_func("/mermaid-sequence/q6/arrow-types", test_arrow_types);
            Test.add_func("/mermaid-sequence/q7/label-text", test_label_text);
            Test.add_func("/mermaid-sequence/q8/quoted-alias", test_quoted_alias);
            Test.add_func("/mermaid-sequence/parse-errors", test_parse_errors_kept);
            Test.add_func("/mermaid-sequence/click-regions", test_click_regions);
            Test.add_func("/review-mermaid-sequence/rect-dark-palette", test_rect_dark_palette_renders);
            Test.add_func("/zenuml/z1/calls-without-arrow", test_zen_calls_without_arrow);
            Test.add_func("/zenuml/z2/returns", test_zen_returns);
            Test.add_func("/zenuml/z3/sequence-layout", test_zen_sequence_layout);
            Test.add_func("/zenuml/z4/label-contrast", test_zen_label_contrast);
            Test.add_func("/zenuml/z5/basic-example-valid", test_zen_basic_example_valid);
            Test.add_func("/zenuml/click-regions", test_zen_click_regions);
            return Test.run();
        }
    }
}
