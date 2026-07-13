namespace GDiagram.Tests {
    /**
     * !include line mapping for the parsers that split the preprocessed text into
     * lines themselves (the Lexer honours the include markers on its own), and the
     * type detection of sequence files with border messages ("[-> A", "A ->]").
     *
     * Every diagram below has a two-line include on main-file line 3 (4 in some),
     * so an element after the include is shifted by the included lines plus the
     * two marker lines when the mapping is missing.
     */
    public class ReviewIncludeTests {

        private static string? tmp_dir = null;

        private static string dir() {
            if (tmp_dir == null) {
                try {
                    tmp_dir = DirUtils.make_tmp("gdiagram-include-XXXXXX");
                } catch (FileError e) {
                    error("mkdtemp: %s", e.message);
                }
            }
            return tmp_dir;
        }

        private static void write(string name, string content) {
            try {
                FileUtils.set_contents(Path.build_filename(dir(), name), content);
            } catch (FileError e) {
                error("write %s: %s", name, e.message);
            }
        }

        /**
         * Parses `main_src` as the document dir()/main.puml whose include file
         * `inc_name` holds `inc_src`, through the engine like the GUI and the LSP.
         */
        private static ParseResult parse_doc(string main_src, string inc_name, string inc_src) {
            write(inc_name, inc_src);
            string main_path = Path.build_filename(dir(), "main.puml");
            write("main.puml", main_src);
            var r = new DiagramEngine("dot").parse(main_src, null, main_path);
            assert(r.ast != null);
            return r;
        }

        // ---- the shared line map ----

        public static void test_line_map_plain_text() {
            string[] lines = "a\nb\nc".split("\n");
            int[] map = Preprocessor.source_line_numbers(lines);
            assert(map.length == 3);
            assert(map[0] == 1 && map[1] == 2 && map[2] == 3);
        }

        public static void test_line_map_nested_includes() {
            write("inner.iuml", "inner1\ninner2\n");
            write("outer.iuml", "outer1\n!include inner.iuml\nouter2\n");
            string main = "@startuml\nmain2\n!include outer.iuml\nmain4\nmain5\n@enduml\n";
            var pre = new Preprocessor();
            string processed = pre.process(main, Path.build_filename(dir(), "main.puml"));
            assert(pre.errors.size == 0);
            string[] lines = processed.split("\n");
            int[] map = Preprocessor.source_line_numbers(lines);

            // Every word keeps the line of the main-file line it came from
            string[] words = { "main2", "outer1", "inner1", "inner2", "outer2", "main4", "main5" };
            int[] expected = { 2, 3, 3, 3, 3, 4, 5 };
            for (int w = 0; w < words.length; w++) {
                bool found = false;
                for (int i = 0; i < lines.length; i++) {
                    if (lines[i].strip() == words[w]) {
                        assert(map[i] == expected[w]);
                        found = true;
                    }
                }
                assert(found);
            }

            // Same numbers as the Lexer gives the tokens
            var tokens = new Lexer(processed).scan_all();
            int checked_tokens = 0;
            foreach (var t in tokens) {
                for (int w = 0; w < words.length; w++) {
                    if (t.lexeme == words[w]) {
                        assert(t.line == expected[w]);
                        checked_tokens++;
                    }
                }
            }
            assert(checked_tokens == words.length);
        }

        public static void test_strip_include_markers() {
            string text = "a\n' [begin include: x.iuml]\nb\n' [end include: x.iuml]\nc";
            assert(Preprocessor.strip_include_markers(text) == "a\nb\nc");
            assert(Preprocessor.strip_include_markers("a\n' comment\n") == "a\n' comment\n");
        }

        // ---- line-splitting parsers ----

        public static void test_gantt() {
            var r = parse_doc("@startgantt\n[Task A] requires 2 days\n!include tasks.iuml\n[Task B] requires 3 days\n@endgantt\n",
                              "tasks.iuml", "[Inc 1] requires 1 days\n[Inc 2] requires 1 days\n");
            assert(r.diagram_type == DiagramType.GANTT);
            var d = (PumlGanttDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var t in d.tasks) {
                lines[t.name] = t.source_line;
            }
            assert(lines["Task A"] == 2);
            assert(lines["Inc 1"] == 3);
            assert(lines["Inc 2"] == 3);
            assert(lines["Task B"] == 4);
        }

        public static void test_timing() {
            var r = parse_doc("@startuml\nconcise \"A\" as A\n!include sig.iuml\nrobust \"C\" as C\n@enduml\n",
                              "sig.iuml", "concise \"B1\" as B1\nconcise \"B2\" as B2\n");
            assert(r.diagram_type == DiagramType.TIMING);
            var d = (TimingDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var s in d.signals) {
                lines[s.alias_name] = s.source_line;
            }
            assert(lines["A"] == 2);
            assert(lines["B1"] == 3);
            assert(lines["B2"] == 3);
            assert(lines["C"] == 4);
        }

        public static void test_chronology() {
            var r = parse_doc("@startchronology\n[Start] happens on 2024-01-01\n!include ev.iuml\n[End] happens on 2024-03-01\n@endchronology\n",
                              "ev.iuml", "[Mid1] happens on 2024-02-01\n[Mid2] happens on 2024-02-02\n");
            assert(r.diagram_type == DiagramType.CHRONOLOGY);
            var d = (ChronologyDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var e in d.events) {
                lines[e.name] = e.source_line;
            }
            assert(lines["Start"] == 2);
            assert(lines["Mid1"] == 3);
            assert(lines["Mid2"] == 3);
            assert(lines["End"] == 4);
        }

        public static void test_nwdiag() {
            var r = parse_doc("@startnwdiag\nnwdiag {\n!include net.iuml\nnetwork lan {\nweb01\n}\n}\n@endnwdiag\n",
                              "net.iuml", "network dmz {\n  db01\n}\n");
            assert(r.diagram_type == DiagramType.NWDIAG);
            var d = (NwdiagDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var n in d.networks) {
                lines["net:" + n.name] = n.source_line;
                foreach (var node in n.nodes) {
                    lines[node.name] = node.source_line;
                }
            }
            assert(lines["net:dmz"] == 3);
            assert(lines["db01"] == 3);
            assert(lines["net:lan"] == 4);
            assert(lines["web01"] == 5);
        }

        public static void test_archimate() {
            var r = parse_doc("@startuml\narchimate #Business \"A\" as a <<business-actor>>\n!include arch.iuml\n" +
                              "archimate #Business \"C\" as c <<business-actor>>\n@enduml\n",
                              "arch.iuml", "archimate #Business \"B1\" as b1 <<business-actor>>\n" +
                              "archimate #Business \"B2\" as b2 <<business-actor>>\n");
            assert(r.diagram_type == DiagramType.ARCHIMATE);
            var d = (ArchimateDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var e in d.elements) {
                lines[e.id] = e.source_line;
            }
            assert(lines["a"] == 2);
            assert(lines["b1"] == 3);
            assert(lines["b2"] == 3);
            assert(lines["c"] == 4);
        }

        public static void test_chen() {
            var r = parse_doc("@startchen\nentity A {\n}\n!include chen.iuml\nentity C {\n}\n@endchen\n",
                              "chen.iuml", "entity B {\n  x\n}\n");
            assert(r.diagram_type == DiagramType.CHEN_ER);
            var d = (ChenDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var e in d.entities) {
                lines[e.name] = e.source_line;
            }
            assert(lines["A"] == 2);
            assert(lines["B"] == 4);
            assert(lines["C"] == 5);
        }

        public static void test_ebnf() {
            var r = parse_doc("@startebnf\na = \"x\" ;\n!include rules.iuml\nc = \"z\" ;\n@endebnf\n",
                              "rules.iuml", "b = \"y\" ;\nb2 = \"w\" ;\n");
            assert(r.diagram_type == DiagramType.EBNF);
            var d = (EbnfDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var rule in d.rules) {
                lines[rule.name] = rule.source_line;
            }
            assert(lines["a"] == 2);
            assert(lines["b"] == 3);
            assert(lines["b2"] == 3);
            assert(lines["c"] == 4);
        }

        private static void collect_salt(SaltPanel panel, Gee.HashMap<string, int> lines) {
            foreach (var row in panel.rows) {
                foreach (var cell in row.cells) {
                    if (cell.text.length > 0) {
                        lines[cell.text] = cell.source_line;
                    }
                    if (cell.nested_panel != null) {
                        collect_salt(cell.nested_panel, lines);
                    }
                }
            }
        }

        public static void test_salt() {
            var r = parse_doc("@startsalt\n{\nFirst\n!include rows.iuml\nLast\n}\n@endsalt\n",
                              "rows.iuml", "Inc1\nInc2\n");
            assert(r.diagram_type == DiagramType.SALT);
            var d = (SaltDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            collect_salt(d.root, lines);
            assert(lines["First"] == 3);
            assert(lines["Inc1"] == 4);
            assert(lines["Inc2"] == 4);
            assert(lines["Last"] == 5);
        }

        public static void test_tree() {
            var r = parse_doc("@starttree\n+ root\n!include kids.iuml\n++ after\n@endtree\n",
                              "kids.iuml", "++ inc1\n++ inc2\n");
            assert(r.diagram_type == DiagramType.TREE);
            var d = (TreeDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var n in d.get_all_nodes()) {
                lines[n.text] = n.source_line;
            }
            assert(lines["root"] == 2);
            assert(lines["inc1"] == 3);
            assert(lines["inc2"] == 3);
            assert(lines["after"] == 4);
        }

        public static void test_board() {
            var r = parse_doc("@startboard\n+ Col1\n!include cards.iuml\n++ after\n@endboard\n",
                              "cards.iuml", "++ c1\n++ c2\n");
            assert(r.diagram_type == DiagramType.BOARD);
            var d = (BoardDiagram) r.ast;
            assert(d.columns.size == 1);
            assert(d.columns[0].source_line == 2);
            var lines = new Gee.HashMap<string, int>();
            foreach (var c in d.columns[0].cards) {
                lines[c.text] = c.source_line;
            }
            assert(lines["c1"] == 3);
            assert(lines["c2"] == 3);
            assert(lines["after"] == 4);
        }

        public static void test_ancestry() {
            var r = parse_doc("@startancestry\nperson A [Alpha]\n!include people.iuml\nperson C [Gamma]\n@endancestry\n",
                              "people.iuml", "person B1\nperson B2\n");
            assert(r.diagram_type == DiagramType.ANCESTRY);
            var d = (AncestryDiagram) r.ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var p in d.persons) {
                lines[p.id] = p.source_line;
            }
            assert(lines["A"] == 2);
            assert(lines["B1"] == 3);
            assert(lines["B2"] == 3);
            assert(lines["C"] == 4);
        }

        // ---- data parsers: the markers are not part of the data ----

        public static void test_yaml_ignores_markers() {
            var r = parse_doc("@startyaml\nfruit: apple\n!include more.iuml\n@endyaml\n",
                              "more.iuml", "veg: carrot\n");
            assert(r.diagram_type == DiagramType.YAML_DIAGRAM);
            var d = (YamlDiagram) r.ast;
            assert(d.root != null);
            assert(d.root.children.size == 2);
            assert(d.root.children[0].key == "fruit");
            assert(d.root.children[1].key == "veg");
        }

        public static void test_dot_and_ditaa_ignore_markers() {
            var r = parse_doc("@startdot\ndigraph G {\n!include edges.iuml\n}\n@enddot\n",
                              "edges.iuml", "a -> b;\n");
            assert(r.diagram_type == DiagramType.DOT_DIAGRAM);
            string dot = ((DotDiagram) r.ast).dot_source;
            assert(dot.contains("a -> b;"));
            assert(!dot.contains("include"));

            var r2 = parse_doc("@startditaa\n+---+\n!include art.iuml\n+---+\n@endditaa\n",
                               "art.iuml", "| A |\n");
            assert(r2.diagram_type == DiagramType.DITAA);
            string art = ((DitaaDiagram) r2.ast).ascii_text;
            assert(art == "+---+\n| A |\n+---+");
        }

        // ---- detection: border messages are not components ----

        public static void test_border_messages_are_sequence() {
            string incoming = "@startuml\n[-> A: DoWork\nactivate A\nA -> A: Internal call\nactivate A\n" +
                              "A ->] : << createRequest >>\nA<--] : RequestCreated\ndeactivate A\n" +
                              "[<- A: Done\ndeactivate A\n@enduml\n";
            assert(TypeDetector.detect_plantuml(incoming) == DiagramType.SEQUENCE);
            string short_arrows = "@startuml\n?-> Alice    : \"\"?->\"\"\\\\n**short** to actor1\n" +
                                  "[-> Alice    : \"\"[->\"\"\\\\n**from start** to actor1\n" +
                                  "[-> Bob      : \"\"[->\"\"\\\\n**from start** to actor2\n" +
                                  "?-> Bob      : \"\"?->\"\"\\\\n**short** to actor2\n" +
                                  "Alice ->]    : \"\"->]\"\"\\\\nfrom actor1 **to end**\n" +
                                  "Alice ->?    : \"\"->?\"\"\\\\n**short** from actor1\n" +
                                  "Alice -> Bob : \"\"->\"\" \\\\nfrom actor1 to actor2\n@enduml\n";
            assert(TypeDetector.detect_plantuml(short_arrows) == DiagramType.SEQUENCE);
            // A bracketed component line still makes a component diagram
            assert(TypeDetector.detect_plantuml("@startuml\n[Web] --> [Db]\n@enduml\n") == DiagramType.COMPONENT);
        }

        // Types as PlantUML 1.2026.1 reports them (data-diagram-type of the SVG)
        public static void test_class_keyword_declarations() {
            foreach (string kw in new string[] { "exception", "protocol", "metaclass", "stereotype", "dataclass",
                                                 "record", "circle", "annotation", "struct" }) {
                assert(TypeDetector.detect_plantuml("@startuml\n%s Foo\n@enduml\n".printf(kw)) == DiagramType.CLASS);
                assert(TypeDetector.detect_plantuml("@startuml\n  %s Foo\nA -> B : hi\n@enduml\n".printf(kw)) ==
                       DiagramType.CLASS);
            }
            assert(TypeDetector.detect_plantuml("@startuml\nexception MyError\nrecord R\n@enduml\n") == DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\nprotocol Foo<T> extends Bar\n@enduml\n") == DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\nstereotype Foo <<meta>> #pink\n@enduml\n") == DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\nstruct S {\n  +x : int\n}\n@enduml\n") == DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\nobject o\nrecord R\n@enduml\n") == DiagramType.CLASS);
            // Not declarations / description elements
            assert(TypeDetector.detect_plantuml("@startuml\nrecord -> db : save\n@enduml\n") == DiagramType.SEQUENCE);
            assert(TypeDetector.detect_plantuml("@startuml\ncircle C\nactor A\nA --> C\n@enduml\n") != DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\ncircle C\nusecase U\n@enduml\n") != DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\ncircle C\nnode N\n@enduml\n") == DiagramType.COMPONENT);
            assert(TypeDetector.detect_plantuml("@startuml\nstart\n:circle foo;\nstop\n@enduml\n") == DiagramType.ACTIVITY);
        }

        // The diagram kind comes from the first "@start..." line (PlantUML 1.2026.1),
        // not from a tag mentioned in label text or a later diagram in the file
        public static void test_first_tag_line_decides() {
            string comp = "@startuml\n[Data\\nJson (@startjson)\\nYaml (@startyaml)] as p <<puml>>\n" +
                          "[Gantt (@startgantt)] as g\np --> g : @startmindmap\n@enduml\n";
            assert(TypeDetector.detect_plantuml(comp) == DiagramType.COMPONENT);
            var engine = new DiagramEngine("dot");
            assert(engine.detect_format(comp, null) == DiagramFormat.PLANTUML);
            assert(engine.parse(comp, "arch.puml").diagram_type == DiagramType.COMPONENT);
            assert(TypeDetector.detect_plantuml("@startuml\nnode n [\nUses @startwbs\n]\n@enduml\n") ==
                   DiagramType.COMPONENT);
            assert(TypeDetector.detect_plantuml("@startuml\nAlice -> Bob\nnote right\n@startmindmap\nend note\n@enduml\n") ==
                   DiagramType.SEQUENCE);
            // Tags inside a JSON document and later diagrams do not count; text before the tag is ignored
            assert(TypeDetector.detect_plantuml("@startjson\n{\"a\": \"@startuml\"}\n@endjson\n") ==
                   DiagramType.JSON_DIAGRAM);
            assert(TypeDetector.detect_plantuml("' intro\nnotes\n@startjson\n{}\n@endjson\n@startuml\nA -> B\n@enduml\n") ==
                   DiagramType.JSON_DIAGRAM);
            assert(TypeDetector.detect_plantuml("  @startyaml\na: 1\n@endyaml\n") == DiagramType.YAML_DIAGRAM);
            assert(TypeDetector.detect_plantuml("@startuml(id=x)\nA -> B\n@enduml\n") == DiagramType.SEQUENCE);
            assert(TypeDetector.detect_plantuml("x @startjson\n@startuml\nA -> B\n@enduml\n") == DiagramType.SEQUENCE);
            assert(TypeDetector.detect_plantuml("@startpacketdiag\npacketdiag {\n}\n@endpacketdiag\n") ==
                   DiagramType.MERMAID_PACKET);
            assert(TypeDetector.diagram_tag("A -> B\n") == null);
            // GEDCOM needs a file without a tag
            assert(TypeDetector.detect_plantuml("0 HEAD\n1 CHAR UTF-8\n0 TRLR\n") == DiagramType.ANCESTRY);
            assert(TypeDetector.detect_plantuml("@startuml\nA -> B : x\n0 HEAD\n@enduml\n") != DiagramType.ANCESTRY);
        }

        // Keywords in label text, quoted strings and action text do not choose the type
        public static void test_label_text_keywords() {
            string[] seq = {
                "Alice -> Bob : call component(x)", "Alice -> Bob : glob [*] files",
                "Alice -> Bob : endif reached", "Alice -> Bob : see (a)/b", "Alice -> Bob : x --option",
                "Alice -> Bob : partition table", "Alice -> Bob : <<person>> ok", "Alice -> Bob : fork again",
                "Alice -> Bob : \"(*)\"", "clock -> Bob : tick", "Alice -> Bob : a:/b"
            };
            foreach (string line in seq) {
                var t = TypeDetector.detect_plantuml("@startuml\n%s\n@enduml\n".printf(line));
                if (t != DiagramType.SEQUENCE) {
                    stderr.printf("%s: %s\n", line, t.to_string());
                    assert_not_reached();
                }
            }
            assert(TypeDetector.detect_plantuml("@startuml\nstart\n:run tool --output file;\n:next;\nstop\n@enduml\n") ==
                   DiagramType.ACTIVITY);
            assert(TypeDetector.detect_plantuml("@startuml\nstart\n:call person(x);\nstop\n@enduml\n") == DiagramType.ACTIVITY);
            assert(TypeDetector.detect_plantuml("@startuml\nstart\n:read a<|--b;\nstop\n@enduml\n") == DiagramType.ACTIVITY);
            // "initializeSystem(): Result" is a member, not a C4 System() call
            assert(TypeDetector.detect_plantuml("@startuml\nclass A {\n  + initializeSystem(): Result\n}\n@enduml\n") ==
                   DiagramType.CLASS);
            // Still detected: real C4 calls, timing signals, activity keywords, note-only activity
            assert(TypeDetector.detect_plantuml("@startuml\nPerson(user, \"User: x\")\n@enduml\n") == DiagramType.COMPONENT);
            assert(TypeDetector.detect_plantuml("@startuml\nclock clk with period 1\n@0\n@enduml\n") == DiagramType.TIMING);
            assert(TypeDetector.detect_plantuml("@startuml\nrobust \"Web: x\" as WB\n@enduml\n") == DiagramType.TIMING);
            assert(TypeDetector.detect_plantuml("@startuml\nif (a: b?) then (yes)\n:x;\nendif\n@enduml\n") ==
                   DiagramType.ACTIVITY);
            assert(TypeDetector.detect_plantuml("@startuml\nnote left: text\n@enduml\n") == DiagramType.ACTIVITY);
            assert(TypeDetector.detect_plantuml("@startuml\n(Use: case) as U\nactor A\nA --> U\n@enduml\n") ==
                   DiagramType.USECASE);
        }

        // Mermaid names the diagram on its first line; keywords in labels don't count
        public static void test_mermaid_header_line() {
            assert(TypeDetector.detect_mermaid("sequenceDiagram\n  A->>B: draw flowchart\n") ==
                   DiagramType.MERMAID_SEQUENCE);
            assert(TypeDetector.detect_mermaid("---\ntitle: gantt\n---\n%%{init: {}}%%\n%% pie\nclassDiagram\n  A <|-- B\n") ==
                   DiagramType.MERMAID_CLASS);
            assert(TypeDetector.detect_mermaid("%%{\n  init: {\"theme\": \"gantt\"}\n}%%\npie title Pets\n") ==
                   DiagramType.MERMAID_PIE);
            assert(TypeDetector.detect_mermaid("gitGraph:\n  commit\n") == DiagramType.MERMAID_GIT_GRAPH);
            assert(TypeDetector.is_mermaid("graph TD\n  A --> B : @startuml\n"));
            assert(!TypeDetector.is_mermaid("Alice -> Bob : show gantt chart\n"));
            assert(!TypeDetector.is_mermaid("@startuml\nA -> B : flowchart\n@enduml\n"));
        }

        // Indented "archimate" lines inside layer boxes are ArchiMate (they went to the
        // component renderer); an object diagram's "json" element, also next to a bare
        // "class" line, is an object diagram (the class line made it a class diagram)
        public static void test_archimate_and_object_json_detection() {
            assert(TypeDetector.detect_plantuml("@startuml\nrectangle \"Biz\" {\n  archimate #Business \"Sales Rep\" as sales <<Role>>\n}\n@enduml\n") == DiagramType.ARCHIMATE);
            assert(TypeDetector.detect_plantuml("@startuml\nclass Class\nobject Object\njson JSON {\n   \"fruit\":\"Apple\"\n}\n@enduml\n") == DiagramType.OBJECT);
            assert(TypeDetector.detect_plantuml("@startuml\njson J {\n  \"a\": 1\n}\n@enduml\n") == DiagramType.OBJECT);
            // ... but not beside actors and use cases ("allowmixing")
            assert(TypeDetector.detect_plantuml("@startuml\nallowmixing\nactor Actor\nusecase Usecase\njson J {\n  \"a\": 1\n}\n@enduml\n") == DiagramType.USECASE);
            // A class with a body or a class relation keeps the file a class diagram
            assert(TypeDetector.detect_plantuml("@startuml\nclass A {\n  +x : int\n}\nobject o\n@enduml\n") == DiagramType.CLASS);
            assert(TypeDetector.detect_plantuml("@startuml\nclass A\nclass B\nobject o\nA <|-- B\n@enduml\n") == DiagramType.CLASS);
        }

        // ---- C4-PlantUML standard library: the preprocessed text matches PlantUML's -preproc ----

        // `body` preprocessed as the document dir()/`name`, through the engine
        private static string c4_preprocess(string name, string body) {
            write(name, body);
            var engine = new DiagramEngine("dot");
            string text = engine.preprocess(body, Path.build_filename(dir(), name));
            assert(engine.preprocessor_errors.size == 0);
            return text;
        }

        private static bool has_line(string text, string expected) {
            foreach (string line in text.split("\n")) {
                if (line.strip() == expected) {
                    return true;
                }
            }
            return false;
        }

        private static void assert_line(string text, string expected) {
            if (!has_line(text, expected)) {
                error("missing line: %s", expected);
            }
        }

        private static ComponentDiagram c4_parse(string name, string body) {
            write(name, body);
            string path = Path.build_filename(dir(), name);
            var r = new DiagramEngine("dot").parse(body, path, path);
            assert(r.diagram_type == DiagramType.COMPONENT);
            var diagram = r.ast as ComponentDiagram;
            assert(diagram != null);
            assert(diagram.errors.size == 0);
            return diagram;
        }

        private static void collect_components(Gee.ArrayList<Component> list, Gee.ArrayList<Component> all) {
            foreach (var c in list) {
                all.add(c);
                collect_components(c.children, all);
            }
        }

        private const string C4_CONTAINER_DOC = """@startuml
!include <C4/C4_Container>

Person(customer, "Customer", "A user of the system")

System_Boundary(c1, "Online Store") {
    Container(web, "Web App",  "React",      "User interface")
    Container(api, "API",      "Go",         "Business logic")
    ContainerDb(db, "Database","PostgreSQL")
}

Rel(customer, web, "Uses",  "HTTPS")
Rel(web,      api, "Calls", "JSON")
Rel(api,      db,  "Reads/Writes", "SQL")

@enduml
""";

        // examples/plantuml/c4/02_full_stdlib.puml: elements with descriptions and the person
        // sprite, the boundary with its type line, relations with technology, well-formed
        // skinparams (a doubly expanded "FontColor =transparent=transparent" made ghost nodes)
        public static void test_c4_container_stdlib() {
            string text = c4_preprocess("c4_container.puml", C4_CONTAINER_DOC);
            assert_line(text, """rectangle "<$person>\n== Customer\n\nA user of the system" <<person>> as customer""");
            assert_line(text, """rectangle "== Online Store\n<size:12>[system]</size>" <<system_boundary>><<boundary>> as c1  {""");
            assert_line(text, """rectangle "== Web App\n//<size:12>[React]</size>//\n\nUser interface" <<container>> as web""");
            assert_line(text, """database "== Database\n//<size:12>[PostgreSQL]</size>//" <<container>> as db""");
            assert_line(text, """customer -->> web : **Uses**\n//<size:12>[HTTPS]</size>//""");
            assert_line(text, """api -->> db : **Reads/Writes**\n//<size:12>[SQL]</size>//""");
            assert_line(text, "sprite $person [48x48/16] {");
            assert(text.contains("skinparam rectangle<<system_boundary>> {\n    FontColor #444444\n" +
                                 "    BackgroundColor transparent\n    BorderColor #444444\n    RoundCorner 0\n" +
                                 "    DiagonalCorner 0\n    BorderStyle dashed\n}\n"));
            assert_line(text, "skinparam package<<system_boundary>>StereotypeFontColor transparent");
            foreach (string leak in new string[] { "=transparent", "$getLegendTable", "%set_variable_value",
                                                   "$tagSkin", "$bgColor", "$elementSkin" }) {
                if (text.contains(leak)) {
                    error("leaked into the output: %s", leak);
                }
            }
            // A comment mentioning LAYOUT_LANDSCAPE() is not expanded
            assert(!text.contains("left to right direction call"));

            var diagram = c4_parse("c4_container.puml", C4_CONTAINER_DOC);
            assert(diagram.components.size == 2);
            var all = new Gee.ArrayList<Component>();
            collect_components(diagram.components, all);
            assert(all.size == 5);
            foreach (var c in all) {
                assert(c.id != "FontColor" && c.id != "transparent" && c.alias != null);
            }
            assert(all[0].alias == "customer" && all[0].label.contains("A user of the system") &&
                   all[0].label.has_prefix("<$person>"));
            assert(all[1].alias == "c1" && all[1].children.size == 3 && all[1].label.contains("[system]") &&
                   all[1].has_stereotype("system_boundary"));
            assert(all[4].component_type == ComponentType.DATABASE && all[4].label.contains("[PostgreSQL]"));
            assert(diagram.relationships.size == 3);
            assert(diagram.relationships[0].from_id == "customer" && diagram.relationships[0].to_id == "web");
            assert(diagram.relationships[0].label == """**Uses**\n//<size:12>[HTTPS]</size>//""");
            assert(!diagram.left_to_right && diagram.legend == null);
        }

        private const string C4_COMPONENT_DOC = """@startuml
!include <C4/C4_Component>
AddElementTag("important", $bgColor="#d73027", $fontColor="#ffffff", $legendText="important component")
AddRelTag("async", $textColor="blue", $lineColor="blue", $lineStyle=DashedLine())
Container(spa, "SPA", "Angular", "The UI")
Container_Boundary(api, "API Application") {
  Component(sign, "Sign In Controller", "Spring MVC Rest Controller", "Allows users to sign in")
  Component(sec, "Security Component", "Spring Bean", "Provides functionality", $tags="important")
  ComponentDb(cdb, "Cache", "Redis")
  ComponentQueue(q, "Events", "Kafka")
}
ContainerDb(db, "Database", "Relational Database Schema", "Stores users")
Rel(spa, sign, "Uses", "JSON/HTTPS")
Rel_D(sign, sec, "Calls")
Rel(sec, db, "Read & write to", "JDBC", $tags="async")
Rel_R(sec, q, "Publishes")
LAYOUT_TOP_DOWN()
SHOW_LEGEND()
@enduml
""";

        // Tags, directed relations and SHOW_LEGEND(): the legend lists the used element
        // kinds and tags only (the "Legend" markup line leaked as "$getLegendTable(")
        public static void test_c4_component_tags_and_legend() {
            string text = c4_preprocess("c4_component.puml", C4_COMPONENT_DOC);
            assert_line(text, "skinparam arrow<<async>> {");
            assert_line(text, "Color blue;text:blue;line.dashed");
            assert_line(text, """rectangle "== Security Component\n//<size:12>[Spring Bean]</size>//\n\nProvides functionality" <<important>><<component>> as sec""");
            assert_line(text, """queue "== Events\n//<size:12>[Kafka]</size>//" <<component>> as q""");
            assert_line(text, """rectangle "== API Application\n<size:12>[container]</size>" <<container_boundary>><<boundary>> as api  {""");
            assert_line(text, "sign -DOWN->> sec : **Calls**");
            assert_line(text, """sec -->> db <<async>> : **Read & write to**\n//<size:12>[JDBC]</size>//""");
            assert_line(text, "sec -RIGHT->> q : **Publishes**");
            assert_line(text, "top to bottom direction");
            assert_line(text, "hide stereotype");
            assert_line(text, "legend right");
            assert_line(text, "<#transparent,#transparent>|<color:#000000>**Legend **</color> |");
            assert_line(text, "|<#438DD5><color:#3C7FC0> <U+25AF></color> <color:#FFFFFF> container <size:10></size></color> |");
            assert_line(text, "|<#85BBF0><color:#78A8D8> <U+25AF></color> <color:#000000> component <size:10></size></color> |");
            assert_line(text, "|<#transparent><color:#444444> <U+25AF></color> <color:#444444> container boundary <size:10></size></color> |");
            assert_line(text, "|<#d73027><color:#d73027> <U+25AF></color> <color:#ffffff> important component <size:10></size></color> |");
            assert_line(text, "|<color:blue> <U+2500></color> <color:blue> async <size:10>(dashed)</size></color> |");
            assert_line(text, "endlegend");
            // Unused kinds stay out of the legend
            assert(!text.contains("|<#08427B>"));

            var diagram = c4_parse("c4_component.puml", C4_COMPONENT_DOC);
            var all = new Gee.ArrayList<Component>();
            collect_components(diagram.components, all);
            assert(all.size == 7);
            assert(diagram.relationships.size == 4);
            assert(diagram.relationships[1].placement == "down" && diagram.relationships[3].placement == "right");
            assert(diagram.relationships[2].label.has_prefix("**Read & write to**"));
            assert(diagram.hide_stereotype && !diagram.left_to_right);
            assert(diagram.legend != null && diagram.legend.text.contains("important component"));
        }

        private const string C4_CONTEXT_DOC = """@startuml
!include <C4/C4_Context>
LAYOUT_LEFT_RIGHT()
Person(u, "User", "A person, using it")
Person_Ext(admin, "Admin")
Enterprise_Boundary(e, "Corp") {
  System(s, "Shop", "Sells things", $tags="important")
}
System_Ext(pay, "Payment Provider", "Handles payments")
Rel(u, s, "Uses", "HTTPS")
Rel_Back(pay, s, "Calls back")
BiRel(admin, s, "Manages")
Lay_R(u, admin)
SHOW_LEGEND()
@enduml
""";

        // LAYOUT_LEFT_RIGHT(), hidden layout links, back/bidirectional relations, a
        // description with a comma, person sprites in the legend
        public static void test_c4_context_layout() {
            string text = c4_preprocess("c4_context.puml", C4_CONTEXT_DOC);
            assert_line(text, "left to right direction");
            assert_line(text, """rectangle "<$person>\n== User\n\nA person, using it" <<person>> as u""");
            assert_line(text, """rectangle "<$person>\n== Admin" <<external_person>> as admin""");
            assert_line(text, """rectangle "== Corp\n<size:12>[enterprise]</size>" <<enterprise_boundary>><<boundary>> as e  {""");
            assert_line(text, """rectangle "== Shop\n\nSells things" <<important>><<system>> as s""");
            assert_line(text, "pay <<-- s : **Calls back**");
            assert_line(text, "admin <<-->> s : **Manages**");
            assert_line(text, "u -[hidden]RIGHT- admin");
            assert_line(text, "|<#08427B><color:#073B6F> <U+25AF></color> <color:#FFFFFF><$person,scale=.25>  person <size:10></size></color> |");

            var diagram = c4_parse("c4_context.puml", C4_CONTEXT_DOC);
            assert(diagram.left_to_right);
        }

        // C4_Dynamic numbers relations (overloaded Rel() with 8 and 9 parameters, Index());
        // C4_Deployment nests nodes
        public static void test_c4_dynamic_and_deployment() {
            string dyn = c4_preprocess("c4_dynamic.puml", """@startuml
!include <C4/C4_Dynamic>
Container(c1, "Single-Page Application", "JavaScript and Angular", "Provides functionality")
Container_Boundary(b, "API Application") {
  Component(c2, "Sign In Controller", "Spring MVC Rest Controller", "Allows users to sign in")
  Component(c3, "Security Component", "Spring Bean", "Provides functionality")
}
ContainerDb(c4, "Database", "Relational Database Schema", "Stores user info")
Rel_R(c1, c2, "Submits credentials to", "JSON/HTTPS")
Rel(c2, c3, "Calls isAuthenticated() on")
Rel(c3, c4, "select * from users where username = ?", "JDBC")
RelIndex(Index(), c3, c4, "again")
@enduml
""");
            assert_line(dyn, """c1 -RIGHT->> c2 : **1: Submits credentials to**\n//<size:12>[JSON/HTTPS]</size>//""");
            assert_line(dyn, "c2 -->> c3 : **2: Calls isAuthenticated() on**");
            assert_line(dyn, """c3 -->> c4 : **3: select * from users where username = ?**\n//<size:12>[JDBC]</size>//""");
            assert_line(dyn, "c3 -->> c4 : **4: again**");

            string depl = c4_preprocess("c4_deployment.puml", """@startuml
!include <C4/C4_Deployment>
Deployment_Node(plc, "Big Bank plc", "Data center") {
  Node(dbs, "bigbank-db01", "Ubuntu 16.04 LTS") {
    ContainerDb(db, "Database", "Oracle 12c", "Stores data")
  }
}
Container(api, "API Application", "Java and Spring MVC")
Rel_R(api, db, "Reads from and writes to", "JDBC")
SHOW_LEGEND()
@enduml
""");
            assert_line(depl, """rectangle "== Big Bank plc\n<size:12>[Data center]</size>" <<node>> as plc  {""");
            assert_line(depl, """rectangle "== bigbank-db01\n<size:12>[Ubuntu 16.04 LTS]</size>" <<node>> as dbs  {""");
            assert_line(depl, """database "== Database\n//<size:12>[Oracle 12c]</size>//\n\nStores data" <<container>> as db""");
            assert_line(depl, """api -RIGHT->> db : **Reads from and writes to**\n//<size:12>[JDBC]</size>//""");
            assert_line(depl, "|<#FFFFFF><color:#A2A2A2> <U+25AF></color> <color:#000000> node <size:10></size></color> |");
        }

        // ---- The preprocessor language features C4 relies on (each checked against PlantUML) ----

        private static string preprocess(string src) {
            var engine = new DiagramEngine("dot");
            return engine.preprocess(src, null);
        }

        // Strings and integers are different values: "0" + "1" concatenates (C4's legend masks)
        public static void test_preproc_typed_values() {
            string text = preprocess("@startuml\n!$m = \"0\" + \"1\"\n!$n = 1 + 2\n!$h = 12/2\n!$c = \"a\" + 3\n" +
                                     "!$e = \"5\" == 5\nV: $m $n $h $c $e\n@enduml\n");
            assert_line(text, "V: 01 3 6 a3 1");
        }

        // A call has its own scope: assigning an existing global updates it, a new name
        // stays local; %set_variable_value sets a global
        public static void test_preproc_call_scopes() {
            string text = preprocess("@startuml\n!$g = \"G\"\n!function $f($a)\n!$g = \"changed\"\n" +
                                     "!$loc = \"local\"\n%set_variable_value(\"$made\", \"global\")\n" +
                                     "!return $a + \"x\"\n!endfunction\nF: $f(\"q\") $g $loc $made\n@enduml\n");
            assert_line(text, "F: qx changed $loc global");
        }

        // !while and !foreach run their bodies (C4 breaks labels and lists legend entries in loops)
        public static void test_preproc_loops() {
            string text = preprocess("@startuml\n!$i = 0\n!while $i < 3\nW: $i\n!$i = $i + 1\n!endwhile\n" +
                                     "!foreach $it in %splitstr(\"a.b\", \".\")\nFE: $it\n!endfor\n" +
                                     "!function $count($s)\n!$n = 0\n!while %strpos($s, \"+\") >= 0\n!$n = $n + 1\n" +
                                     "!$s = %substr($s, %strpos($s, \"+\") + 1)\n!endwhile\n!return $n\n!endfunction\n" +
                                     "CNT: $count(\"a+b+c\")\n@enduml\n");
            assert(text.contains("W: 0\nW: 1\nW: 2\n"));
            assert(text.contains("FE: a\nFE: b\n"));
            assert_line(text, "CNT: 2");
        }

        // Overloads by argument count, named arguments, defaults that are expressions
        public static void test_preproc_overloads_named_defaults() {
            string text = preprocess("@startuml\n!function $ov($a)\n!return \"one\"\n!endfunction\n" +
                                     "!function $ov($a, $b)\n!return \"two\"\n!endfunction\n" +
                                     "!function Small()\n!return \"small\"\n!endfunction\n" +
                                     "!unquoted procedure P($a, $b=\"B\", $c=Small())\nP: $a $b $c\n!endprocedure\n" +
                                     "O: $ov(1) $ov(1, 2)\nP(x, $c=\"cc\")\nP(y)\n@enduml\n");
            assert_line(text, "O: one two");
            assert_line(text, "P: x B cc");
            assert_line(text, "P: y B small");
        }

        // An !unquoted call takes argument text: quotes removed, variables substituted
        // ($legendText="$PERSON_LEGEND_TEXT"); a parameter is only substituted as $name, so
        // "sprite $sprite" keeps its keyword (it became "person person")
        public static void test_preproc_unquoted_arguments() {
            string text = preprocess("@startuml\n!$TEXT = \"legend text\"\n!unquoted procedure U($x, $y=\"\")\n" +
                                     "U: [$x] [$y]\n!endprocedure\nU(\"quoted, comma\", $y=\"$TEXT\")\nU(bare words)\n" +
                                     "!unquoted procedure S($sprite)\nsprite $sprite\n!endprocedure\nS(person)\n@enduml\n");
            assert_line(text, "U: [quoted, comma] [legend text]");
            assert_line(text, "U: [bare words] []");
            assert_line(text, "sprite person");
        }

        // Calls inside quotes are expanded, string literals have no escapes, %breakline()
        // splits a procedure's output into lines, comment lines are left alone
        public static void test_preproc_text_lines() {
            string text = preprocess("@startuml\n!function $wrap($t)\n!return \"[\" + $t + \"]\"\n!endfunction\n" +
                                     "!procedure $lines()\n!$t = \"skinparam a b\" + %breakline() + \"skinparam c d\"\n" +
                                     "$t\n!endprocedure\n' comment $wrap(x)\nQ: \"$wrap(\"in quotes\")\" %strlen(\"a\\nb\")\n" +
                                     "$lines()\n@enduml\n");
            assert_line(text, "Q: \"[in quotes]\" 4");
            assert(text.contains("\nskinparam a b\nskinparam c d\n"));
            assert_line(text, "' comment $wrap(x)");
        }

        // An included file's text is expanded once: its "$w" output is not substituted again
        public static void test_preproc_include_expanded_once() {
            write("expanded_once.iuml", "!$w = \"WW\"\n!$v = \"$w\"\nX: $v\n");
            string main_src = "@startuml\n!include expanded_once.iuml\n@enduml\n";
            var engine = new DiagramEngine("dot");
            string text = engine.preprocess(main_src, Path.build_filename(dir(), "main_once.puml"));
            assert_line(text, "X: $w");
        }

        // Links with quoted multiplicities are class diagrams in PlantUML, with or without
        // a class line ('A "1" - "many" B' was unknown, 'A --> "*" B' a sequence diagram)
        public static void test_multiplicity_links_are_class() {
            foreach (string body in new string[] { "A \"1\" - \"many\" B", "A \"1\" --> \"*\" B : has", "A --> \"*\" B",
                                                   "A \"1\" -> B", "\"A\" \"1\" -- \"2\" \"B\"",
                                                   "A \"0..1\" .. \"1..*\" B : uses >", "foo \"1\" -left-> \"2\" bar" }) {
                if (TypeDetector.detect_plantuml("@startuml\n%s\n@enduml\n".printf(body)) != DiagramType.CLASS) {
                    error("not a class diagram: %s", body);
                }
            }
            // A quoted participant is not a multiplicity; skinparams and a message stay sequence
            assert(TypeDetector.detect_plantuml("@startuml\nAlice -> \"Bob\" : hi\n@enduml\n") == DiagramType.SEQUENCE);
            assert(TypeDetector.detect_plantuml("@startuml\nskinparam classArrowColor SeaGreen\n" +
                                                "skinparam ArrowColor Red\nA --> B\n@enduml\n") == DiagramType.SEQUENCE);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/include/line-map-plain", ReviewIncludeTests.test_line_map_plain_text);
        Test.add_func("/include/line-map-nested", ReviewIncludeTests.test_line_map_nested_includes);
        Test.add_func("/include/strip-markers", ReviewIncludeTests.test_strip_include_markers);
        Test.add_func("/include/gantt", ReviewIncludeTests.test_gantt);
        Test.add_func("/include/timing", ReviewIncludeTests.test_timing);
        Test.add_func("/include/chronology", ReviewIncludeTests.test_chronology);
        Test.add_func("/include/nwdiag", ReviewIncludeTests.test_nwdiag);
        Test.add_func("/include/archimate", ReviewIncludeTests.test_archimate);
        Test.add_func("/include/chen", ReviewIncludeTests.test_chen);
        Test.add_func("/include/ebnf", ReviewIncludeTests.test_ebnf);
        Test.add_func("/include/salt", ReviewIncludeTests.test_salt);
        Test.add_func("/include/tree", ReviewIncludeTests.test_tree);
        Test.add_func("/include/board", ReviewIncludeTests.test_board);
        Test.add_func("/include/ancestry", ReviewIncludeTests.test_ancestry);
        Test.add_func("/include/yaml-markers", ReviewIncludeTests.test_yaml_ignores_markers);
        Test.add_func("/include/dot-ditaa-markers", ReviewIncludeTests.test_dot_and_ditaa_ignore_markers);
        Test.add_func("/include/border-messages-sequence", ReviewIncludeTests.test_border_messages_are_sequence);
        Test.add_func("/include/class-keyword-declarations", ReviewIncludeTests.test_class_keyword_declarations);
        Test.add_func("/include/first-tag-line-decides", ReviewIncludeTests.test_first_tag_line_decides);
        Test.add_func("/include/label-text-keywords", ReviewIncludeTests.test_label_text_keywords);
        Test.add_func("/include/mermaid-header-line", ReviewIncludeTests.test_mermaid_header_line);
        Test.add_func("/include/archimate-object-json-detection", ReviewIncludeTests.test_archimate_and_object_json_detection);
        Test.add_func("/include/c4-container-stdlib", ReviewIncludeTests.test_c4_container_stdlib);
        Test.add_func("/include/c4-component-tags-legend", ReviewIncludeTests.test_c4_component_tags_and_legend);
        Test.add_func("/include/c4-context-layout", ReviewIncludeTests.test_c4_context_layout);
        Test.add_func("/include/c4-dynamic-deployment", ReviewIncludeTests.test_c4_dynamic_and_deployment);
        Test.add_func("/include/preproc-typed-values", ReviewIncludeTests.test_preproc_typed_values);
        Test.add_func("/include/preproc-call-scopes", ReviewIncludeTests.test_preproc_call_scopes);
        Test.add_func("/include/preproc-loops", ReviewIncludeTests.test_preproc_loops);
        Test.add_func("/include/preproc-overloads-named-defaults", ReviewIncludeTests.test_preproc_overloads_named_defaults);
        Test.add_func("/include/preproc-unquoted-arguments", ReviewIncludeTests.test_preproc_unquoted_arguments);
        Test.add_func("/include/preproc-text-lines", ReviewIncludeTests.test_preproc_text_lines);
        Test.add_func("/include/preproc-include-expanded-once", ReviewIncludeTests.test_preproc_include_expanded_once);
        Test.add_func("/include/multiplicity-links-class", ReviewIncludeTests.test_multiplicity_links_are_class);
        return Test.run();
    }
}
