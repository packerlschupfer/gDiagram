namespace GDiagram.Tests {
    /**
     * PlantUML sequence layout, checked on the geometry of the exported SVG:
     *
     *  1. every message is a horizontal arrow and every lifeline a straight vertical
     *     line; the gap between two participants grows with the label between them
     *  2. title (also multi-line), header, footer and caption are drawn
     *  3. alt/else/loop/group/ref draw frames around their rows, nested ones inside
     *  4. notes sit beside / over their lifeline without connector edges
     *  5. a message label is everything after the colon ("use -- carefully")
     */
    public class ReviewSequenceLayoutTests {

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
        }

        private static string svg_of(string body) {
            string src = "@startuml\n%s\n@enduml\n".printf(body);
            string path = Path.build_filename(Environment.get_tmp_dir(),
                                              "gd_seq_layout_%s.svg".printf(Uuid.string_random()));
            assert(new DiagramEngine("dot").export_to_svg(src, "test.puml", null, path));
            string svg;
            try {
                FileUtils.get_contents(path, out svg);
            } catch (FileError e) {
                error("read svg: %s", e.message);
            }
            FileUtils.remove(path);
            return svg;
        }

        private static string dot_of(string body) {
            string? dot = new DiagramEngine("dot").generate_dot("@startuml\n%s\n@enduml\n".printf(body), "test.puml", null);
            assert(dot != null);
            return dot;
        }

        private static SequenceDiagram parse_seq(string body) {
            var r = new DiagramEngine("dot").parse("@startuml\n%s\n@enduml\n".printf(body), null);
            assert(r.diagram_type == DiagramType.SEQUENCE);
            return (SequenceDiagram) r.ast;
        }

        // Edge title (unescaped "a->b") -> the points of its path
        private static Gee.HashMap<string, Box> edge_paths(string svg) {
            var map = new Gee.HashMap<string, Box>();
            try {
                var re = new Regex("<g id=\"edge[0-9]+\" class=\"edge\">\\s*<title>([^<]*)</title>\\s*<path [^>]*d=\"([^\"]*)\"",
                                   RegexCompileFlags.DOTALL);
                var num = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                MatchInfo mi;
                re.match(svg, 0, out mi);
                while (mi.matches()) {
                    string title = mi.fetch(1).replace("&#45;", "-").replace("&gt;", ">");
                    var box = new Box();
                    // the matched text must outlive the MatchInfo
                    string d = mi.fetch(2);
                    MatchInfo nm;
                    num.match(d, 0, out nm);
                    while (nm.matches()) {
                        box.add(double.parse(nm.fetch(1)), double.parse(nm.fetch(2)));
                        nm.next();
                    }
                    map.set(title, box);
                    mi.next();
                }
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            return map;
        }

        // Bounding box of a node's polygon / path shapes, null if none
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
                var num = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                string group = mi.fetch(1);
                MatchInfo pm;
                pts.match(group, 0, out pm);
                while (pm.matches()) {
                    string points = pm.fetch(1);
                    MatchInfo nm;
                    num.match(points, 0, out nm);
                    while (nm.matches()) {
                        box.add(double.parse(nm.fetch(1)), double.parse(nm.fetch(2)));
                        nm.next();
                    }
                    pm.next();
                }
                return box.x0 <= box.x1 ? box : null;
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
        }

        private static double centre_x(string svg, string id) {
            var box = node_box(svg, id);
            assert(box != null);
            return (box.x0 + box.x1) / 2;
        }

        // x of a participant's lifeline; asserts all its segments are vertical and aligned
        private static double lifeline_x(Gee.HashMap<string, Box> edges, string id) {
            double x = double.NAN;
            int segments = 0;
            foreach (var entry in edges.entries) {
                if (!entry.key.has_prefix(id + "_l") || !entry.key.contains("->" + id + "_l")) {
                    continue;
                }
                var b = entry.value;
                if (b.x1 - b.x0 > 0.5) {
                    printerr("lifeline segment %s is not vertical: x %f..%f\n", entry.key, b.x0, b.x1);
                    assert_not_reached();
                }
                if (segments > 0 && (b.x0 - x).abs() > 0.5) {
                    printerr("lifeline segment %s at x %f, others at %f\n", entry.key, b.x0, x);
                    assert_not_reached();
                }
                x = b.x0;
                segments++;
            }
            assert(segments > 0);
            return x;
        }

        private static Regex message_re;

        // Every message edge is horizontal; returns how many were checked
        private static int assert_messages_horizontal(Gee.HashMap<string, Box> edges) {
            int n = 0;
            foreach (var entry in edges.entries) {
                string t = entry.key;
                // "A_m3->B_m3": both ends on the row of message 3 (self-message loops excluded)
                MatchInfo mi;
                bool message = message_re.match(t, 0, out mi) && mi.fetch(2) == mi.fetch(4) &&
                               !t.contains("_seq_self");
                if (!message) {
                    continue;
                }
                if (entry.value.y1 - entry.value.y0 > 0.5) {
                    printerr("message %s is not horizontal: y %f..%f\n", t, entry.value.y0, entry.value.y1);
                    assert_not_reached();
                }
                n++;
            }
            return n;
        }

        private const string TYPES = "participant Participant as Foo\nactor Actor as Foo1\nboundary Boundary as Foo2\n" +
            "control Control as Foo3\nentity Entity as Foo4\ndatabase Database as Foo5\n" +
            "collections Collections as Foo6\nqueue Queue as Foo7\n" +
            "Foo -> Foo1 : To actor\nFoo -> Foo2 : To boundary\nFoo -> Foo3 : To control\n" +
            "Foo -> Foo4 : To entity\nFoo -> Foo5 : To database\nFoo -> Foo6 : To collections\n" +
            "Foo -> Foo7 : To queue";

        // ---- 1 ----

        public static void test_messages_horizontal_lifelines_straight() {
            string body = TYPES + "\nFoo7 --> Foo : a reply with a label much wider than any gap between two heads\n" +
                          "Foo2 -> Foo2 : self\nactivate Foo2\nFoo2 -> Foo5 : inside\ndeactivate Foo2\n" +
                          "note right of Foo3 : a note\n[-> Foo : in\nFoo7 ->] : out\n...\nFoo1 <- Foo4 : back";
            string svg = svg_of(body);
            var edges = edge_paths(svg);
            assert(assert_messages_horizontal(edges) >= 11);
            string[] ids = { "Foo", "Foo1", "Foo2", "Foo3", "Foo4", "Foo5", "Foo6", "Foo7" };
            double prev = -double.MAX;
            foreach (string id in ids) {
                double x = lifeline_x(edges, id);
                assert(x > prev);  // columns left to right in declaration order
                prev = x;
            }
            // the self message leaves and returns horizontally
            assert(edges.get("Foo2_m8->_seq_self1_m8").y1 - edges.get("Foo2_m8->_seq_self1_m8").y0 <= 0.5);
            assert(edges.get("_seq_self2_m8->_seq_self3_m8").y1 - edges.get("_seq_self2_m8->_seq_self3_m8").y0 <= 0.5);
        }

        // Every arrow starts on its sender's lifeline: the x below the centre of the head box,
        // the same on every row, and the foot box straight below the head
        public static void test_arrows_start_on_lifelines() {
            string svg = svg_of(TYPES + "\nFoo7 --> Foo : a reply with a label much wider than any gap between two heads\n" +
                                "Foo5 -> Foo2 : back\nFoo3 -> Foo6 : across");
            var edges = edge_paths(svg);
            var head_x = new Gee.HashMap<string, double?>();
            foreach (string id in new string[] { "Foo", "Foo1", "Foo2", "Foo3", "Foo4", "Foo5", "Foo6", "Foo7" }) {
                var top = node_box(svg, id + "_top");
                var bottom = node_box(svg, id + "_bottom");
                if (top != null && bottom != null) {
                    // actors have no polygon; the other heads do
                    assert(((top.x0 + top.x1) / 2 - (bottom.x0 + bottom.x1) / 2).abs() <= 0.5);
                    head_x.set(id, (top.x0 + top.x1) / 2);
                }
            }
            int checked = 0;
            foreach (var entry in edges.entries) {
                MatchInfo mi;
                if (!message_re.match(entry.key, 0, out mi) || mi.fetch(2) != mi.fetch(4)) {
                    continue;
                }
                string from = mi.fetch(1);
                if (!head_x.has_key(from)) {
                    continue;
                }
                double hx = (double) head_x.get(from);
                // the tail end (no arrowhead) is on the lifeline; Graphviz clips the edge at the
                // edge of its (0.01in) point node, which leaves up to about a point
                double tail = (entry.value.x0 - hx).abs() < (entry.value.x1 - hx).abs() ? entry.value.x0 : entry.value.x1;
                if ((tail - hx).abs() > 1.5) {
                    printerr("message %s starts at x %f, its lifeline is at %f\n", entry.key, tail, hx);
                    assert_not_reached();
                }
                checked++;
            }
            assert(checked >= 7);
        }

        // The gap between neighbours grows to fit the label between them
        public static void test_gap_fits_label() {
            string label = "this label is far wider than the two participant heads together";
            string svg = svg_of("participant A\nparticipant B\nparticipant C\nA -> B : %s\nB -> C : x".printf(label));
            // head box centres, independent of how the lifelines are built
            double gap_ab = centre_x(svg, "B_top") - centre_x(svg, "A_top");
            double gap_bc = centre_x(svg, "C_top") - centre_x(svg, "B_top");
            var edges = edge_paths(svg);
            assert((lifeline_x(edges, "B") - centre_x(svg, "B_top")).abs() <= 0.5);
            // 11pt Sans is well over 4.5pt per character
            assert(gap_ab > label.length * 4.5);
            assert(gap_bc < gap_ab / 2);
        }

        // docs/architecture/05_ui_interaction.puml: long labels between distant participants
        public static void test_architecture_doc_layout() {
            string path = Path.build_filename(Environment.get_variable("GDIAGRAM_SOURCE_ROOT") ?? "..",
                                              "docs", "architecture", "05_ui_interaction.puml");
            string src;
            try {
                FileUtils.get_contents(path, out src);
            } catch (FileError e) {
                Test.skip("05_ui_interaction.puml not found");
                return;
            }
            string out_path = Path.build_filename(Environment.get_tmp_dir(),
                                                  "gd_seq_layout_%s.svg".printf(Uuid.string_random()));
            assert(new DiagramEngine("dot").export_to_svg(src, path, Path.get_dirname(path), out_path));
            string svg;
            try {
                FileUtils.get_contents(out_path, out svg);
            } catch (FileError e) {
                error("read svg: %s", e.message);
            }
            FileUtils.remove(out_path);
            var edges = edge_paths(svg);
            assert(assert_messages_horizontal(edges) > 40);
            double prev = -double.MAX;
            foreach (string id in new string[] { "User", "MW", "DV", "Left", "PP", "Props", "Insp", "SE", "Git", "Eng", "LSP", "VSC" }) {
                double x = lifeline_x(edges, id);
                assert(x > prev);
                prev = x;
            }
        }

        // ---- 2 ----

        public static void test_title_header_footer_caption() {
            string svg = svg_of("header Page Header\nfooter Page Footer\ncaption The Caption\ntitle Example Title\n" +
                                "Alice -> Bob : message 1");
            foreach (string text in new string[] { "Example Title", "Page Header", "Page Footer", "The Caption" }) {
                if (!svg.contains(">%s</text>".printf(text))) {
                    printerr("missing text '%s'\n", text);
                    assert_not_reached();
                }
            }
            // the title is above the heads
            var title_y = text_y(svg, "Example Title");
            var head = node_box(svg, "Alice_top");
            assert(head != null && title_y < head.y0);
            assert(text_y(svg, "The Caption") > node_box(svg, "Alice_bottom").y1);

            var d = parse_seq("title\n  Line one\n  **Line** two\nend title\nAlice -> Bob : hi");
            assert(d.title == "Line one\n**Line** two");
            assert(d.messages.size == 1);
            svg = svg_of("title\n  Line one\n  **Line** two\nend title\nAlice -> Bob : hi");
            assert(svg.contains(">Line one</text>"));
            assert(svg.contains("two</text>"));
        }

        private static double text_y(string svg, string text) {
            try {
                var re = new Regex("<text [^>]*y=\"(-?[0-9.]+)\"[^>]*>%s</text>".printf(Regex.escape_string(text)));
                MatchInfo mi;
                assert(re.match(svg, 0, out mi));
                return double.parse(mi.fetch(1));
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
        }

        // ---- 3 ----

        public static void test_group_frames() {
            string body = "participant Alice\nparticipant Bob\nparticipant Log\n" +
                          "Alice -> Bob: Authentication Request\n" +
                          "alt successful case\n  Bob -> Alice: Authentication Accepted\n" +
                          "else some kind of failure\n  Bob -> Alice: Authentication Failure\n" +
                          "  group My own label [secondary]\n    Alice -> Log : Log attack start\n" +
                          "    loop 1000 times\n      Alice -> Bob: DNS Attack\n    end\n" +
                          "    Alice -> Log : Log attack end\n  end\n" +
                          "else Another type of failure\n  Bob -> Alice: Please repeat\nend\n" +
                          "ref over Alice, Bob : init";
            string svg = svg_of(body);
            var edges = edge_paths(svg);
            var alt = node_box(svg, "_seq_frame0");
            var group = node_box(svg, "_seq_frame1");
            var loop = node_box(svg, "_seq_frame2");
            var reference = node_box(svg, "_seq_frame3");
            assert(alt != null && group != null && loop != null && reference != null);
            // nested frames lie inside their parents
            assert(group.x0 > alt.x0 && group.x1 < alt.x1 && group.y0 > alt.y0 && group.y1 < alt.y1);
            assert(loop.x0 > group.x0 && loop.x1 < group.x1 && loop.y0 > group.y0 && loop.y1 < group.y1);
            // the frame spans the rows between alt and end, not the message before it
            double before = edges.get("Alice_m0->Bob_m0").y0;
            double inside = edges.get("Bob_m1->Alice_m1").y0;
            double last = edges.get("Bob_m6->Alice_m6").y0;
            assert(before < alt.y0);
            assert(inside > alt.y0 && last < alt.y1);
            double dns = edges.get("Alice_m4->Bob_m4").y0;
            assert(dns > loop.y0 && dns < loop.y1);
            // the frame spans the columns of its messages
            assert(alt.x0 < lifeline_x(edges, "Alice") && alt.x1 > lifeline_x(edges, "Log"));
            assert(loop.x1 < lifeline_x(edges, "Log"));
            // "else": two dashed separators across the alt frame
            int separators = 0;
            foreach (var entry in edges.entries) {
                if (entry.key.has_prefix("_seq_fe0_")) {
                    assert(entry.value.y1 - entry.value.y0 <= 0.5);
                    assert((entry.value.x0 - alt.x0).abs() < 1 && (entry.value.x1 - alt.x1).abs() < 1);
                    separators++;
                }
            }
            assert(separators == 2);
            foreach (string text in new string[] { ">alt</text>", ">[successful case]</text>", ">[some kind of failure]</text>",
                                                  ">My own label</text>", ">[secondary]</text>", ">loop</text>",
                                                  ">[1000 times]</text>", ">ref</text>", ">init</text>" }) {
                if (!svg.contains(text)) {
                    printerr("missing %s\n", text);
                    assert_not_reached();
                }
            }
            // the reference box covers both lifelines, below the frame
            assert(reference.y0 > alt.y1);
            assert(reference.x0 < lifeline_x(edges, "Alice") && reference.x1 > lifeline_x(edges, "Bob"));
            var d = parse_seq(body);
            assert(d.errors.size == 0);
            assert(d.frames[d.frames.size - 1].participants.size == 2);
        }

        // ---- 4 ----

        public static void test_notes_beside_lifelines() {
            string body = "participant A\nparticipant B\nparticipant C\nA -> B : hello\n" +
                          "note left of A : left note\nnote right of A : right note\n" +
                          "note over B, C : spanning\nhnote over C : hex\nB -> C : after\n" +
                          "note right : attached to after\nC -> A : back";
            string dot = dot_of(body);
            for (int i = 0; i < 5; i++) {
                if (dot.contains("note%d ->".printf(i)) || dot.contains("-> note%d".printf(i))) {
                    printerr("note%d has a connector:\n%s\n", i, dot);
                    assert_not_reached();
                }
            }
            string svg = svg_of(body);
            var edges = edge_paths(svg);
            assert(assert_messages_horizontal(edges) == 3);
            double ax = lifeline_x(edges, "A");
            double bx = lifeline_x(edges, "B");
            double cx = lifeline_x(edges, "C");
            var left = node_box(svg, "note0");
            var right = node_box(svg, "note1");
            var span = node_box(svg, "note2");
            var hex = node_box(svg, "note3");
            var attached = node_box(svg, "note4");
            assert(left.x1 < ax);
            assert(right.x0 > ax && right.x1 < bx);
            assert(span.x0 < bx && span.x1 > cx);
            assert(hex.x0 < cx && hex.x1 > cx);
            // own rows in source order, below "hello"
            double hello = edges.get("A_m0->B_m0").y0;
            assert(left.y0 > hello && right.y0 > left.y1 - 0.5 && span.y0 > right.y1 - 0.5);
            // "note right" without a participant sits beside the arrow it follows
            double after = edges.get("B_m1->C_m1").y0;
            assert(attached.x0 > cx);
            assert(attached.y0 < after && attached.y1 > after - 12);
        }

        // ---- 5 ----

        public static void test_label_after_colon() {
            var d = parse_seq("A -> B : use -- carefully\nA -> B : a--b\nB --> A : don't stop\nA -> B ++ : x ++ y\n" +
                              "A -> B : colon: inside");
            assert(d.messages.size == 4 + 1);
            assert(d.messages[0].label == "use -- carefully");
            assert(d.messages[1].label == "a--b");
            assert(d.messages[2].label == "don't stop");
            assert(d.messages[3].label == "x ++ y");
            assert(d.messages[3].activate_target);
            assert(d.messages[4].label == "colon: inside");
            string svg = svg_of("A -> B : use -- carefully");
            assert(svg.contains("use &#45;&#45; carefully"));
        }

        // Labels come from the source lines; text from an !include must not shift them
        public static void test_label_after_include() {
            string dir;
            try {
                dir = DirUtils.make_tmp("gd-seq-layout-XXXXXX");
                FileUtils.set_contents(Path.build_filename(dir, "inc.iuml"),
                                       "skinparam backgroundColor #FFFFFF\nskinparam note {\n  FontColor #000000\n}\n");
            } catch (Error e) {
                error("tmp: %s", e.message);
            }
            string src = "@startuml\n!include inc.iuml\nparticipant A\nparticipant B\nA -> B : first -- label\n" +
                         "note over A\n  line one\n\n  line two\nend note\n@enduml\n";
            var engine = new DiagramEngine("dot");
            string pre = engine.preprocess(src, dir);
            var d = (SequenceDiagram) engine.parse(pre, null).ast;
            assert(d.messages.size == 1);
            assert(d.messages[0].label == "first -- label");
            assert(d.notes.size == 1);
            assert(d.notes[0].text == "line one\n\nline two");
            FileUtils.remove(Path.build_filename(dir, "inc.iuml"));
            DirUtils.remove(dir);
        }

        // Delays, spacing, "return" and the activation shorthand
        public static void test_delay_return_shorthand() {
            var d = parse_seq("participant A\nparticipant B\nA -> B ++ #gold : call\n...5 minutes later...\n|||\n" +
                              "||45||\nreturn done\nA -> B --++ : again\nB -> C ** : make\nB -> C !! : drop");
            assert(d.errors.size == 0);
            assert(d.messages.size == 5);
            assert(d.messages[0].label == "call");
            assert(d.messages[1].label == "done");
            assert(d.messages[1].from.name == "B" && d.messages[1].to.name == "A");
            assert(d.messages[1].style == ArrowStyle.DOTTED);
            assert(d.messages[2].label == "again");
            assert(d.find_participant("C").created);
            int spaces = 0;
            foreach (var ev in d.events) {
                var sp = ev as SpaceEvent;
                if (sp != null) {
                    spaces++;
                    if (spaces == 1) {
                        assert(sp.space.delay && sp.space.text == "5 minutes later");
                    }
                    if (spaces == 3) {
                        assert(!sp.space.delay && sp.space.height == 45);
                    }
                }
            }
            assert(spaces == 3);
            string svg = svg_of("participant A\nparticipant B\nA -> B : one\n...\nB -> A : two");
            var edges = edge_paths(svg);
            assert(edges.has_key("A_l1->A_l2"));
            assert(svg.contains("stroke-dasharray=\"1,3\""));  // the dotted delay segment (packed dots)
        }


        // ---- PlantUML fidelity (September 2026) ----

        private static string line_of(string dot, string start) {
            foreach (string l in dot.split("\n")) {
                if (l.has_prefix("  " + start)) {
                    return l;
                }
            }
            return "";
        }

        // 1. Creole / HTML in messages, participant names and notes
        public static void test_creole_labels() {
            string dot = dot_of("participant \"The **Famous** Bob\" as Bob\n" +
                                "Alice -> Bob : A //well// **bold** \"\"mono\"\" --strike-- __under__ ~~wave~~\n" +
                                "note right of Alice\n  **bold** //ital// \"\"mono\"\"\n  <color red>red</color> <b>html</b>\nend note");
            string lbl = line_of(dot, "_seq_lbl_m0 [");
            foreach (string part in new string[] { "<i>well</i>", "<b>bold</b>", "<font face=\"monospace\">mono</font>",
                                                   "<s>strike</s>", "<u>under</u>", "<u>wave</u>" }) {
                if (!lbl.contains(part)) {
                    printerr("message label lacks %s: %s\n", part, lbl);
                    assert_not_reached();
                }
            }
            assert(!lbl.contains("**") && !lbl.contains("//"));
            assert(line_of(dot, "Bob_top [").contains("label=<The <b>Famous</b> Bob>"));
            string note = line_of(dot, "note0 [");
            assert(note.contains("<b>bold</b>") && note.contains("<i>ital</i>") &&
                   note.contains("<font face=\"monospace\">mono</font>") && note.contains("<font color=\"red\">red</font>") &&
                   note.contains("<b>html</b>"));
            assert(!note.contains("&quot;"));
            // unbalanced / literal markup stays valid: the export still works
            string svg = svg_of("A -> B : a ** b </i> <b>open\nA -> B : x <- y < z > w");
            assert(svg.contains("<b>") == false);
            assert(svg.contains("font-weight=\"bold\""));
        }

        // 2. Arrow heads: x, o, half heads, on border messages too
        public static void test_arrow_heads() {
            string dot = dot_of("Bob ->x Alice : x\nBob ->o Alice : o\nBob -\\ Alice : half\nBob //-- Alice : hd\n" +
                                "[x-> Bob : xin\nBob ->o] : oout\nBob <->o Alice");
            assert(dot.contains("Bob_m0 -> Alice_m0 [style=solid, arrowhead=none"));
            assert(dot.contains("_seq_cx0_0a -> _seq_cx0_0b"));
            assert(dot.contains("Bob_m1 -> Alice_m1 [style=solid, arrowhead=dotnormal"));
            // "-\": the upper half; pointing right that is the half left of the edge
            assert(dot.contains("Bob_m2 -> Alice_m2 [style=solid, arrowhead=lnormal"));
            // "//--": thin upper half at Bob, the arrow pointing left
            assert(dot.contains("Alice_m3 -> Bob_m3 [style=dashed, arrowhead=rvee"));
            assert(dot.contains("_seq_bl_m4 -> Bob_m4 [style=solid, arrowhead=normal"));
            assert(dot.contains("_seq_cx1_0a -> _seq_cx1_0b"));
            assert(dot.contains("Bob_m5 -> _seq_br_m5 [style=solid, arrowhead=dotnormal"));
            assert(dot.contains("Bob_m6 -> Alice_m6 [style=solid, arrowhead=dotnormal, arrowsize=0.8, dir=both, arrowtail=normal"));
            var d = parse_seq("Bob ->x Alice\n[x-> Bob");
            assert(d.messages[0].deco_right == "x" && d.messages[0].head_right == ">");
            assert(d.messages[1].deco_left == "x");
        }

        // 3. "autoactivate on": calls activate, "return" answers them
        public static void test_autoactivate() {
            string body = "autoactivate on\nalice -> bob : hello\nbob -> carl : call\nreturn done\nreturn rc";
            var d = parse_seq(body);
            assert(d.messages.size == 4);
            assert(d.messages[2].label == "done" && d.messages[2].from.name == "carl" && d.messages[2].to.name == "bob");
            assert(d.messages[3].label == "rc" && d.messages[3].from.name == "bob" && d.messages[3].to.name == "alice");
            assert(d.messages[2].style == ArrowStyle.DOTTED);
            string dot = dot_of(body);
            assert(dot.contains("_seq_act0 [") && dot.contains("_seq_act1 ["));
            assert(!dot.contains("_seq_act2 ["));
            // a dotted message deactivates its sender
            d = parse_seq("autoactivate on\nA -> B : call\nB --> A : back");
            int deact = 0;
            foreach (var a in d.activations) {
                deact += a.activation_type == ActivationType.DEACTIVATE && a.participant.name == "B" ? 1 : 0;
            }
            assert(deact == 1);
        }

        // 4. autonumber formats, hierarchical numbers, %autonumber%
        public static void test_autonumber_formats() {
            var d = parse_seq("autonumber 5 \"<b>[000]\"\nA -> B : fmt\nautonumber 1.1.1\nA -> B : hier\nB --> A : r\n" +
                              "autonumber inc A\nA -> B : hier2\nnote right: n=%autonumber%\nautonumber inc B\n" +
                              "A -> B : self %autonumber%\nautonumber 40 10 \"<font color=red><b>Message 0  \"\nA -> B : m\n" +
                              "A -> B : m2\nautonumber \"<b>(<u>##</u>)\"\nA -> B : u");
            assert(d.messages[0].number_text == "<b>[005]");
            assert(d.messages[1].number_text == "<b>1.1.1</b>");
            assert(d.messages[2].number_text == "<b>1.1.2</b>");
            assert(d.messages[3].number_text == "<b>2.1.1</b>");
            assert(d.notes[0].text == "n=2.1.1");
            assert(d.messages[4].number_text == "<b>2.2.1</b>");
            assert(d.messages[4].label == "self 2.2.1");
            assert(d.messages[5].number_text == "<font color=red><b>Message 40  ");
            assert(d.messages[6].number_text == "<font color=red><b>Message 50  ");
            assert(d.messages[7].number_text == "<b>(<u>1</u>)");
            string dot = dot_of("autonumber 5 \"<b>[000]\"\nA -> B : fmt");
            assert(line_of(dot, "_seq_lbl_m0 [").contains("<TD><b>[005]</b></TD>"));
        }

        // 5. 'A -> "Long\nname" as L' declares L once
        public static void test_message_alias() {
            var d = parse_seq("A -> \"Long\\nname\" as L : first\nL --> A : back");
            assert(d.participants.size == 2);
            var l = d.find_participant("L");
            assert(l != null && l.name == "Long\\nname");
            assert(d.messages[1].from == l);
        }

        // 6. "participant X order N"
        public static void test_participant_order() {
            var d = parse_seq("participant X\nparticipant Last order 30\nparticipant Mid\nparticipant First order 10\n" +
                              "participant Neg order -5\nLast -> First : m");
            string[] names = { "Neg", "X", "Mid", "First", "Last" };
            assert(d.participants.size == names.length);
            for (int i = 0; i < names.length; i++) {
                assert(d.participants[i].name == names[i]);
            }
            string svg = svg_of("participant Last order 30\nparticipant First order 10\nLast -> First : m");
            assert(centre_x(svg, "First_top") < centre_x(svg, "Last_top"));
        }

        // 7. newpage / ignore newpage
        public static void test_newpage() {
            var d = parse_seq("footer Page %page% of %lastpage%\nA -> B : m1\nnewpage A title for the page\nA -> B : m2");
            assert(d.title == null);
            assert(d.page_count == 2);
            assert(d.messages.size == 2);
            string dot = dot_of("footer Page %page% of %lastpage%\nA -> B : m1\nnewpage A title for the page\nA -> B : m2");
            assert(dot.contains("<Page 1 of 2>") && dot.contains("<Page 2 of 2>"));
            assert(dot.contains("_seq_page0_a -> _seq_page0_b"));
            assert(dot.contains("A title for the page"));
            // the separator lies between the two messages
            assert(seq_y(dot, "_seq_page0_a") > seq_y(dot, "A_m0") && seq_y(dot, "_seq_page0_a") < seq_y(dot, "A_m1"));
            d = parse_seq("ignore newpage\nA -> B : m1\nnewpage A title for the page\nA -> B : m2");
            assert(d.title == null && d.page_count == 1);
            dot = dot_of("ignore newpage\nfooter Page %page% of %lastpage%\nA -> B : m1\nnewpage A title for the page\nA -> B : m2");
            assert(!dot.contains("_seq_page0") && !dot.contains("title for the page") && dot.contains("<Page 1 of 1>"));
        }

        private static double seq_x(string dot, string id) {
            string l = line_of(dot, id + " [");
            int at = l.index_of("pos=\"");
            assert(at >= 0);
            return double.parse(l.substring(at + 5).split(",")[0]);
        }

        private static double seq_y(string dot, string id) {
            string l = line_of(dot, id + " [");
            int at = l.index_of("pos=\"");
            assert(at >= 0);
            return -double.parse(l.substring(at + 5).split("!")[0].split(",")[1]);
        }

        // 8. teoz anchors and a duration arrow
        public static void test_anchor_duration() {
            string body = "!pragma teoz true\n{s} A -> B : start\nB -> A : mid\n{e} B -> A : end\n{s} <-> {e} : duration";
            var d = parse_seq(body);
            assert(d.messages.size == 3);
            assert(d.messages[0].anchor == "s" && d.messages[2].anchor == "e");
            assert(d.durations.size == 1 && d.durations[0].label == "duration");
            string svg = svg_of(body);
            var edges = edge_paths(svg);
            var dur = edges.get("_seq_dur0_a->_seq_dur0_b");
            assert(dur != null);
            assert(dur.x1 - dur.x0 <= 0.5);  // vertical
            assert((dur.y0 - edges.get("A_m0->B_m0").y0).abs() < 12);
            assert((dur.y1 - edges.get("B_m2->A_m2").y0).abs() < 12);
            assert(svg.contains(">duration</text>"));
        }

        // 9. boundary / control / entity icons, collections and queue shapes
        public static void test_participant_icons() {
            string svg = svg_of("participant P\nboundary Bd\ncontrol Ct\nentity En\nqueue Qu\ncollections Co\nP -> Qu : m");
            assert(!svg.down().contains("#01f3"));
            // boundary: bar + circle, control: circle + arrow, entity: circle + line, at head and foot
            assert(count(svg, "<circle class=\"gdicon\"") == 6);
            assert(count(svg, "<path class=\"gdicon\"") >= 6 + 4);  // + queue body and front edge x2
            assert(count(svg, "<polygon class=\"gdicon\"") == 2);   // the collections back boxes
            string dot = dot_of("boundary Bd\nqueue Qu\nBd -> Qu");
            assert(!dot.contains("hexagon") && !dot.contains("trapezium"));
        }

        private static int count(string hay, string needle) {
            int n = 0;
            int at = 0;
            while ((at = hay.index_of(needle, at)) >= 0) {
                n++;
                at += needle.length;
            }
            return n;
        }

        // 10. "participant P [ =Title ---- ""Sub"" ]"
        public static void test_multiline_participant_body() {
            var d = parse_seq("participant P [\n  =Title\n  ----\n  \"\"Sub\"\"\n]\nP -> B : m");
            assert(d.errors.size == 0 && d.messages.size == 1 && d.participants.size == 2);
            assert(d.participants[0].body_lines.size == 3);
            string top = line_of(dot_of("participant P [\n  =Title\n  ----\n  \"\"Sub\"\"\n]\nP -> B : m"), "P_top [");
            assert(top.contains("<b><font point-size=\"18\">Title</font></b>"));
            assert(top.contains("<HR/>"));
            assert(top.contains("<font face=\"monospace\">Sub</font>"));
            assert(top.contains("style=solid"));
        }

        // 11. stereotype spot
        public static void test_stereotype_spot() {
            var d = parse_seq("participant Alice << (C,#ADD1B2) Testable >>\nparticipant Bob << (C,#ADD1B2) >>\nAlice -> Bob : m");
            assert(d.participants[0].spot_char == "C" && d.participants[0].spot_color == "#ADD1B2");
            assert(d.participants[0].stereotype == "Testable" && d.participants[1].stereotype == null);
            string svg = svg_of("participant Alice << (C,#ADD1B2) Testable >>\nparticipant Bob << (C,#ADD1B2) >>\nAlice -> Bob : m");
            assert(!svg.down().contains("#01f2"));
            assert(count(svg, "<circle class=\"gdspot\"") == 4);
            assert(count(svg, "font-weight=\"bold\" font-size=") >= 4 && svg.contains("fill=\"#ADD1B2\""));
        }

        // 12. activation colours
        public static void test_activation_colors() {
            string dot = dot_of("A -> B ++ #gold : hello\nactivate A #red\nB --> A -- : ok\ndeactivate A");
            bool gold = false;
            bool red = false;
            foreach (string l in dot.split("\n")) {
                if (l.contains("_seq_act")) {
                    gold = gold || l.contains("fillcolor=\"gold\"");
                    red = red || l.contains("fillcolor=\"red\"");
                }
            }
            assert(gold && red);
        }

        // 13. skinparams and text conversions
        public static void test_skinparams_and_escapes() {
            string dot = dot_of("skinparam maxMessageSize 40\nA -> B : this is a long message with words");
            assert(count(line_of(dot, "_seq_lbl_m0 ["), "<BR/>") >= 3);
            // "<< text >>" is «text»; "\\n" a literal \n
            dot = dot_of("B -> A : << guillemet >>\nA -> B : one\\\\ntwo");
            assert(line_of(dot, "_seq_lbl_m0 [").contains("«guillemet»"));
            string esc = line_of(dot, "_seq_lbl_m1 [");
            assert(esc.contains("one\\ntwo") && !esc.contains("<BR/>"));
            // sequenceMessageAlign right: the label ends at the arrow's right end
            dot = dot_of("skinparam sequenceMessageAlign right\nparticipant Bob\nparticipant Alice\nBob -> Alice : Request");
            string ldot = dot_of("participant Bob\nparticipant Alice\nBob -> Alice : Request");
            double mid_arrow = (seq_x(dot, "Bob_m0") + seq_x(dot, "Alice_m0")) / 2;
            assert(seq_x(dot, "_seq_lbl_m0") > mid_arrow);
            assert(seq_x(ldot, "_seq_lbl_m0") < mid_arrow);
            // responseMessageBelowArrow: the label of a "<-" message is under its arrow
            dot = dot_of("skinparam responseMessageBelowArrow true\nBob -> Alice : hello\nBob <- Alice : ok");
            assert(seq_y(dot, "_seq_lbl_m0") < seq_y(dot, "Bob_m0"));
            assert(seq_y(dot, "_seq_lbl_m1") > seq_y(dot, "Bob_m1"));
        }

        // 14. footer page variables of a one-page diagram
        public static void test_footer_single_page() {
            assert(dot_of("footer Page %page% of %lastpage%\nA -> B : m").contains("<Page 1 of 1>"));
        }

        // 15. note text: lines left-aligned with each other, the block centred in the note
        public static void test_note_text_centred() {
            string svg = svg_of("participant A\nparticipant B\nparticipant C\nA -> C : m\nnote over A, C\n  a much longer first line\n  short\nend note");
            var note = node_box(svg, "note0");
            assert(note != null);
            double x_long = text_x(svg, "a much longer first line");
            double x_short = text_x(svg, "short");
            assert((x_long - x_short).abs() < 0.5);
            // the block is not at the left edge of the wide note
            assert(x_long - note.x0 > 20);
        }

        private static double text_x(string svg, string text) {
            try {
                var re = new Regex("<text [^>]*x=\"(-?[0-9.]+)\"[^>]*>%s</text>".printf(Regex.escape_string(text)));
                MatchInfo mi;
                assert(re.match(svg, 0, out mi));
                return double.parse(mi.fetch(1));
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
        }

        // Click regions still resolve participants and messages
        public static void test_click_regions() {
            var engine = new DiagramEngine("dot");
            string src = "@startuml\nparticipant \"The **Famous** Bob\" as Bob <<(C,#ADD1B2) T>>\nboundary Bd\nBob -> Bd : **hi**\n@enduml\n";
            var result = engine.render(DiagramType.SEQUENCE, DiagramFormat.PLANTUML, src);
            assert(result.surface != null);
            bool bob = false;
            bool bd = false;
            bool msg = false;
            foreach (var r in engine.last_regions) {
                bob = bob || (r.name == "Bob_top" && r.source_line == 2);
                bd = bd || (r.name == "Bd_top" && r.source_line == 3);
                // the (HTML) message label keeps a clickable region with a size
                msg = msg || (r.name == "_seq_lbl_m0" && r.width > 5 && r.height > 5);
            }
            assert(bob && bd && msg);
        }

        public static int main(string[] args) {
            Test.init(ref args);
            try {
                message_re = new Regex("^(.+)_m([0-9]+)->(.+)_m([0-9]+)$");
            } catch (RegexError e) {
                error("regex: %s", e.message);
            }
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
            Test.add_func("/sequence-layout/1/horizontal-messages-straight-lifelines",
                          test_messages_horizontal_lifelines_straight);
            Test.add_func("/sequence-layout/1/gap-fits-label", test_gap_fits_label);
            Test.add_func("/sequence-layout/1/arrows-start-on-lifelines", test_arrows_start_on_lifelines);
            Test.add_func("/sequence-layout/1/architecture-doc", test_architecture_doc_layout);
            Test.add_func("/sequence-layout/2/title-header-footer-caption", test_title_header_footer_caption);
            Test.add_func("/sequence-layout/3/group-frames", test_group_frames);
            Test.add_func("/sequence-layout/4/notes", test_notes_beside_lifelines);
            Test.add_func("/sequence-layout/5/label-after-colon", test_label_after_colon);
            Test.add_func("/sequence-layout/5/label-after-include", test_label_after_include);
            Test.add_func("/sequence-layout/delay-return-shorthand", test_delay_return_shorthand);
            Test.add_func("/sequence-layout/fidelity/1-creole", test_creole_labels);
            Test.add_func("/sequence-layout/fidelity/2-arrow-heads", test_arrow_heads);
            Test.add_func("/sequence-layout/fidelity/3-autoactivate", test_autoactivate);
            Test.add_func("/sequence-layout/fidelity/4-autonumber-formats", test_autonumber_formats);
            Test.add_func("/sequence-layout/fidelity/5-message-alias", test_message_alias);
            Test.add_func("/sequence-layout/fidelity/6-participant-order", test_participant_order);
            Test.add_func("/sequence-layout/fidelity/7-newpage", test_newpage);
            Test.add_func("/sequence-layout/fidelity/8-anchor-duration", test_anchor_duration);
            Test.add_func("/sequence-layout/fidelity/9-participant-icons", test_participant_icons);
            Test.add_func("/sequence-layout/fidelity/10-multiline-body", test_multiline_participant_body);
            Test.add_func("/sequence-layout/fidelity/11-stereotype-spot", test_stereotype_spot);
            Test.add_func("/sequence-layout/fidelity/12-activation-colors", test_activation_colors);
            Test.add_func("/sequence-layout/fidelity/13-skinparams-escapes", test_skinparams_and_escapes);
            Test.add_func("/sequence-layout/fidelity/14-footer-single-page", test_footer_single_page);
            Test.add_func("/sequence-layout/fidelity/15-note-text-centred", test_note_text_centred);
            Test.add_func("/sequence-layout/fidelity/click-regions", test_click_regions);
            return Test.run();
        }
    }
}
