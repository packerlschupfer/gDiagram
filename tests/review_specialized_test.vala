namespace GDiagram.Tests {
    /**
     * The lightweight PlantUML types (ancestry, board, chen, ditaa, dot, ebnf,
     * regex, salt, tree) and @startpacketdiag, checked against PlantUML
     * 1.2026.8: file export, source order, Chen notation, the ditaa drawing,
     * and the packetdiag bit ruler.
     */
    public class ReviewSpecializedTests {

        private static DiagramEngine? shared_engine = null;
        private static string? tmp_dir = null;

        private static DiagramEngine engine() {
            if (shared_engine == null) shared_engine = new DiagramEngine("dot");
            return shared_engine;
        }

        private static string tmp(string name) {
            if (tmp_dir == null) {
                try {
                    tmp_dir = DirUtils.make_tmp("gdiagram-special-XXXXXX");
                } catch (FileError e) {
                    error("mkdtemp: %s", e.message);
                }
            }
            return Path.build_filename(tmp_dir, name);
        }

        private static string dot_of(string src) {
            string? dot = engine().generate_dot(src, "x.puml", null);
            assert(dot != null);
            return dot;
        }

        // pos="x,y" of the first DOT line containing `marker`
        private static void pos_of(string dot, string marker, out double x, out double y) {
            x = 0; y = 0;
            foreach (string line in dot.split("\n")) {
                if (!line.contains(marker)) continue;
                int p = line.index_of("pos=\"");
                assert(p >= 0);
                string rest = line.substring(p + 5);
                string[] xy = rest.substring(0, rest.index_of("\"")).split(",");
                x = double.parse(xy[0]);
                y = double.parse(xy[1]);
                return;
            }
            error("no DOT line with %s", marker);
        }

        private static int count(string haystack, string needle) {
            int n = 0, i = 0;
            while ((i = haystack.index_of(needle, i)) >= 0) { n++; i += needle.length; }
            return n;
        }

        private const string BOARD = "@startboard\nBacklog\n+Design login page\n+Set up CI/CD\nIn Progress\n+Implement auth\n++Subtask A\nDone\n+Project setup\n@endboard\n";
        private const string CHEN = "@startchen\nentity PERSON {\n  Name {\n    First : STRING\n    Last : STRING\n  }\n  SSN : INTEGER <<key>>\n  Birthday : DATE\n  Age : INTEGER <<derived>>\n  Phone <<multi>>\n}\nentity LOCATION {\n  Address : STRING <<key>>\n}\nrelationship RENTED_TO {\n  Date : DATE\n}\nRENTED_TO -1- PERSON\nRENTED_TO =N= LOCATION\n@endchen\n";
        private const string EBNF = "@startebnf\nexpr = term, { (\"+\" | \"-\"), term };\nterm = factor;\ndigit = \"0\" | \"1\" | \"9\";\n@endebnf\n";
        private const string DITAA = "@startditaa\n+--------+   +-------+    +-------+\n|        +---+ ditaa |    |       |\n|  Text  |   +-------+    |Diagram|\n|Document|   |!magic!|    |       |\n|     {d}+---+-------+--->+       |\n+---+----+   |       |    |       |\n    :        | ASCII |    +-------+\n    |        +-------+\n    v\n+-----------+\n| Beautiful |\n|  Diagram  |\n+-----------+\n@endditaa\n";
        private const string REGEX = "@startregex\n[a-z]+@[a-z]+\\.[a-z]{2,4}\n@endregex\n";
        private const string SALT = "@startsalt\n{\n  Login Form\n  ---\n  Username | \"admin\"\n  [X] Remember me\n  [Cancel] | [  OK  ]\n}\n@endsalt\n";
        private const string PACKET = "@startpacketdiag\npacketdiag {\n   0-15: Source Port\n   16-31: Destination Port\n   32-63: Sequence Number\n   96-99: Data Offset\n}\n@endpacketdiag\n";

        // ---- 1. export for every lightweight type ----

        public static void test_export_all_formats() {
            string[] sources = {
                BOARD, CHEN, EBNF, DITAA, REGEX, SALT, PACKET,
                "@startdot\ndigraph G { a -> b }\n@enddot\n",
                "@starttree\n+ root\n++ child\n@endtree\n",
                "@startancestry\nperson A [Alpha]\nperson B [Beta]\nA -> B\n@endancestry\n"
            };
            uint8[] png_magic = { 0x89, 'P', 'N', 'G' };
            for (int i = 0; i < sources.length; i++) {
                string png = tmp("e%d.png".printf(i));
                string svg = tmp("e%d.svg".printf(i));
                string pdf = tmp("e%d.pdf".printf(i));
                if (!engine().export_to_png(sources[i], "x.puml", null, png)) {
                    error("PNG export failed for source %d", i);
                }
                assert(engine().export_to_svg(sources[i], "x.puml", null, svg));
                assert(engine().export_to_pdf(sources[i], "x.puml", null, pdf));
                uint8[] data;
                try {
                    FileUtils.get_data(png, out data);
                    assert(data.length > 100);
                    for (int j = 0; j < 4; j++) assert(data[j] == png_magic[j]);
                    string text;
                    FileUtils.get_contents(svg, out text);
                    assert(text.contains("<svg"));
                    FileUtils.get_data(pdf, out data);
                    assert(((string) data).has_prefix("%PDF"));
                } catch (FileError e) {
                    error("%s", e.message);
                }
            }
        }

        // ---- 2. board ----

        public static void test_board_plantuml_syntax() {
            var d = new BoardDiagramParser().parse(BOARD);
            assert(d.columns.size == 3);
            assert(d.columns[0].title == "Backlog");
            assert(d.columns[1].title == "In Progress");
            assert(d.columns[2].title == "Done");
            assert(d.columns[0].cards.size == 2);
            assert(d.columns[1].cards[0].text == "Implement auth");
            assert(d.columns[1].cards[0].children.size == 1);
            assert(d.columns[1].cards[0].children[0].text == "Subtask A");
        }

        public static void test_board_legacy_syntax() {
            var d = new BoardDiagramParser().parse("@startboard\n+ Backlog\n++ Card A\n++ Card B\n+ Done\n++ Card C\n@endboard\n");
            assert(d.columns.size == 2);
            assert(d.columns[0].title == "Backlog");
            assert(d.columns[0].cards.size == 2);
            assert(d.columns[1].cards[0].text == "Card C");
        }

        // x/y of the SVG <text> element showing `text` (y grows downwards)
        private static void svg_text_pos(string svg, string text, out double x, out double y) {
            int end = svg.index_of(">" + Markup.escape_text(text) + "</text>");
            if (end < 0) error("no SVG text %s", text);
            int start = svg.substring(0, end).last_index_of("<text");
            string tag = svg.substring(start, end - start);
            x = double.parse(tag.substring(tag.index_of(" x=\"") + 4));
            y = double.parse(tag.substring(tag.index_of(" y=\"") + 4));
        }

        public static void test_board_columns_left_to_right() {
            // Rendered text positions, whatever the DOT looks like
            uint8[]? data = engine().generate_svg(BOARD, "x.puml", null);
            assert(data != null);
            string svg = (string) data;
            double x1, y1, x2, y2, x3, y3, xs, ys, xc1, yc1, xc2, yc2;
            svg_text_pos(svg, "Backlog", out x1, out y1);
            svg_text_pos(svg, "In Progress", out x2, out y2);
            svg_text_pos(svg, "Done", out x3, out y3);
            // columns side by side in source order along one row
            assert(x1 < x2 && x2 < x3);
            assert(Math.fabs(y1 - y2) < 1 && Math.fabs(y2 - y3) < 1);
            svg_text_pos(svg, "Subtask A", out xs, out ys);
            svg_text_pos(svg, "Design login page", out xc1, out yc1);
            svg_text_pos(svg, "Set up CI/CD", out xc2, out yc2);
            // cards one level below their column; a sub-card below its card
            assert(yc1 > y1 && Math.fabs(yc1 - yc2) < 1 && ys > yc1);
            // Backlog's two cards take two slots, so In Progress starts after them
            assert(Math.fabs(xc1 - x1) < 1 && xc2 > xc1 && x2 > xc2);
        }

        // ---- 3. chen ----

        public static void test_chen_parse() {
            var d = new ChenDiagramParser().parse(CHEN);
            assert(d.entities.size == 2);
            var person = d.entities[0];
            assert(person.attributes.size == 5);
            assert(person.attributes[0].name == "Name");
            assert(person.attributes[0].children.size == 2);
            assert(person.attributes[0].children[1].name == "Last : STRING");
            assert(person.attributes[1].name == "SSN : INTEGER" && person.attributes[1].is_key);
            assert(person.attributes[3].is_derived);
            assert(person.attributes[4].is_multivalued);
            assert(d.relationships.size == 1);
            assert(d.links.size == 2);
            assert(d.links[0].cardinality == "1" && !d.links[0].total);
            assert(d.links[1].cardinality == "N" && d.links[1].total);
        }

        public static void test_chen_dot() {
            string dot = dot_of(CHEN);
            assert(!dot.contains("&lt;&lt;key"));
            assert(!dot.contains("<<key>>"));
            assert(dot.contains("<U>SSN : INTEGER</U>"));
            assert(dot.contains("\"RENTED_TO\" -> \"PERSON\" [label=\"1\""));
            assert(dot.contains("\"RENTED_TO\" -> \"LOCATION\" [label=\"N\" penwidth=2"));
            // composite parts hang off their attribute, not off the entity
            assert(dot.contains("\"PERSON__a0__a0\" -> \"PERSON__a0\""));
            foreach (string line in dot.split("\n")) {
                if (line.contains("Age : INTEGER")) assert(line.contains("dashed"));
                if (line.contains("label=<Phone>")) assert(line.contains("peripheries=2"));
                if (line.contains("label=<Name")) assert(!line.contains("{"));
            }
        }

        // ---- 4. ebnf ----

        public static void test_ebnf_source_order() {
            uint8[]? data = engine().generate_svg(EBNF, "x.puml", null);
            assert(data != null);
            string svg = (string) data;
            double x, y_expr, y_digit, y0, y1, y9;
            svg_text_pos(svg, "expr", out x, out y_expr);
            svg_text_pos(svg, "digit", out x, out y_digit);
            assert(y_expr < y_digit);                      // rules top to bottom
            svg_text_pos(svg, "0", out x, out y0);
            svg_text_pos(svg, "1", out x, out y1);
            svg_text_pos(svg, "9", out x, out y9);
            assert(y0 < y1 && y1 < y9);                    // alternatives in source order
        }

        // ---- 5. ditaa ----

        public static void test_ditaa_shapes() {
            string dot = dot_of(DITAA);
            assert(!dot.contains("+--------+"));
            assert(dot.contains("layout=nop2"));
            // 6 plain boxes (the document is drawn apart): the small box, ditaa,
            // !magic!, ASCII, Diagram, Beautiful Diagram
            assert(count(dot, "shape=box style=\"filled\" fillcolor=\"#FFFFFF\"") == 6);
            assert(dot.contains("<B>Beautiful</B>"));
            assert(dot.contains("<B>ditaa</B>"));
            assert(!dot.contains("{d}"));
            assert(count(dot, "dir=forward arrowhead=normal") == 2);   // ---> and v
            assert(count(dot, "style=dashed") == 1);                   // the : line
            string colored = dot_of("@startditaa\n+----+\n|cRED|\n| hi |\n+----+\n@endditaa\n");
            assert(colored.contains("fillcolor=\"#EE3322\""));
            assert(!colored.contains("cRED"));
        }

        // ---- 6. regex ----

        public static void test_regex_railroad() {
            string dot = dot_of(REGEX);
            assert(!dot.contains("[a-z]+@"));          // no raw pattern caption
            assert(!dot.contains("shape=point width=0.12"));
            assert(dot.contains("label=\"{2,4}\""));
            assert(count(dot, "label=\"a-z\"") == 3);
            assert(count(dot, "arrowhead=normal") >= 3);   // three loops
        }

        // ---- 7. salt ----

        public static void test_salt_look() {
            string dot = dot_of(SALT);
            assert(!dot.contains("HEIGHT=\"1\" BGCOLOR"));   // separator was a filled bar
            assert(dot.contains("SIDES=\"B\" COLOR=\"#A0A0A0\""));
            assert(dot.contains("SIDES=\"LB\""));             // text field underline
            assert(!dot.contains("CELLPADDING=\"6\" BGCOLOR"));
        }

        // ---- 9. packetdiag ----

        public static void test_packetdiag_parse() {
            var p = new MermaidPacketParser().parse_packetdiag(PACKET);
            assert(p.plantuml_style);
            assert(p.colwidth == 16);
            assert(p.fields.size == 4);
            // placed one after another: 96-99 follows 32-63
            assert(p.fields[3].bit_start == 64 && p.fields[3].bit_end == 67);
            var q = new MermaidPacketParser().parse_packetdiag(
                "@startpacketdiag\npacketdiag {\n colwidth = 32\n same_height = true\n node_height = 60\n * Flags [len = 3, height = 2]\n}\n@endpacketdiag\n");
            assert(q.colwidth == 32 && q.same_height && q.node_height == 60);
            assert(q.fields[0].bit_width() == 3 && q.fields[0].row_span == 2);
            assert(q.errors.size == 0);
        }

        public static void test_packetdiag_dot() {
            string dot = dot_of(PACKET);
            assert(dot.contains("layout=nop2"));
            assert(!dot.contains("Packet Structure"));
            assert(!dot.contains("0-15"));
            assert(dot.contains("label=\"8\"") && dot.contains("label=\"16\""));
            assert(!dot.contains("label=\"32\""));
            // 16-bit field spans the whole row: 16 bits * 31.5pt
            double x_src, y_src, x_seq, y_seq;
            pos_of(dot, "label=\"Source Port\"", out x_src, out y_src);
            pos_of(dot, "label=\"Destination Port\"", out x_seq, out y_seq);
            assert(x_src == x_seq && y_src > y_seq);
            foreach (string line in dot.split("\n")) {
                if (line.contains("label=\"Source Port\"")) assert(line.contains("width=7.00"));
                if (line.contains("label=\"Data Offset\"")) assert(line.contains("width=1.75"));
            }
            string wide = dot_of("@startpacketdiag\npacketdiag {\n colwidth = 32\n 0-15: A\n 16-31: B\n}\n@endpacketdiag\n");
            assert(wide.contains("label=\"32\""));
            // Mermaid packet-beta keeps its own look
            string? mermaid = engine().generate_dot("packet-beta\n0-15: \"Source Port\"\n", "x.mmd", null);
            assert(mermaid != null && mermaid.contains("Packet Structure"));
        }

        // ---- 10. docs ----

        public static void test_docs_pipeline_no_start_lines() {
            string? root = Environment.get_variable("GDIAGRAM_SOURCE_ROOT");
            assert(root != null);
            string text;
            try {
                FileUtils.get_contents(Path.build_filename(root, "docs", "architecture", "02_rendering_pipeline.puml"), out text);
            } catch (FileError e) {
                error("%s", e.message);
            }
            int starts = 0;
            foreach (string line in text.split("\n")) {
                if (line.strip().has_prefix("@start")) starts++;
            }
            assert(starts == 1);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/special/export-all-formats", ReviewSpecializedTests.test_export_all_formats);
        Test.add_func("/special/board-plantuml-syntax", ReviewSpecializedTests.test_board_plantuml_syntax);
        Test.add_func("/special/board-legacy-syntax", ReviewSpecializedTests.test_board_legacy_syntax);
        Test.add_func("/special/board-columns-left-to-right", ReviewSpecializedTests.test_board_columns_left_to_right);
        Test.add_func("/special/chen-parse", ReviewSpecializedTests.test_chen_parse);
        Test.add_func("/special/chen-dot", ReviewSpecializedTests.test_chen_dot);
        Test.add_func("/special/ebnf-source-order", ReviewSpecializedTests.test_ebnf_source_order);
        Test.add_func("/special/ditaa-shapes", ReviewSpecializedTests.test_ditaa_shapes);
        Test.add_func("/special/regex-railroad", ReviewSpecializedTests.test_regex_railroad);
        Test.add_func("/special/salt-look", ReviewSpecializedTests.test_salt_look);
        Test.add_func("/special/packetdiag-parse", ReviewSpecializedTests.test_packetdiag_parse);
        Test.add_func("/special/packetdiag-dot", ReviewSpecializedTests.test_packetdiag_dot);
        Test.add_func("/special/docs-pipeline-no-start-lines", ReviewSpecializedTests.test_docs_pipeline_no_start_lines);
        return Test.run();
    }
}
