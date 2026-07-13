namespace GDiagram.Tests {
    /**
     * Front-end review findings: the shared lexer/preprocessor/type detection and the
     * sequence, ER and mind map parsers and renderers.
     */
    public class ReviewFrontendTests {

        // 1-based line of the first line containing `needle`, -1 when absent
        private static int line_of(string text, string needle) {
            string[] lines = text.split("\n");
            for (int i = 0; i < lines.length; i++) {
                if (lines[i].contains(needle)) {
                    return i + 1;
                }
            }
            return -1;
        }

        private static string dot_of(string source) {
            var engine = new DiagramEngine("dot");
            string? dot = engine.generate_dot(source, null, null);
            assert(dot != null);
            return dot;
        }

        private static DiagramType detect(string source) {
            return TypeDetector.detect_plantuml(source);
        }

        // ---- 1: <style> stereotype selectors and one-line skinparam blocks ----

        public static void test_mindmap_style_stereotype() {
            string src = "@startmindmap\n<style>\n.rose {\n  BackgroundColor pink\n}\n</style>\n" +
                         "* root\n** a <<rose>>\n** b\n@endmindmap\n";
            var engine = new DiagramEngine("dot");
            var r = engine.parse(src, null);
            assert(r.diagram_type == DiagramType.MINDMAP);
            var d = (MindMapDiagram) r.ast;
            assert(d.root != null);
            assert(d.get_node_count() == 3);
            var a = d.root.children[0];
            assert(a.text == "a");
            assert(a.stereotype == "rose");
            string dot = dot_of(src);
            // "a" is pink, "b" is not
            bool a_pink = false;
            bool b_pink = false;
            foreach (string l in dot.split("\n")) {
                if (l.contains("label=\"a\"") && l.contains("fillcolor=\"pink\"")) a_pink = true;
                if (l.contains("label=\"b\"") && l.contains("fillcolor=\"pink\"")) b_pink = true;
            }
            assert(a_pink);
            assert(!b_pink);
        }

        public static void test_mindmap_one_line_skinparam_block() {
            string src = "@startmindmap\nskinparam node { BackgroundColor pink }\n* root\n** a\n** b\n@endmindmap\n";
            var r = new DiagramEngine("dot").parse(src, null);
            var d = (MindMapDiagram) r.ast;
            assert(d.root != null);
            assert(d.get_node_count() == 3);
        }

        public static void test_er_style_stereotype() {
            string src = "@startuml\n<style>\n.foo {\n  BackgroundColor pink\n}\n</style>\n" +
                         "entity A <<foo>> {\n  id : int\n}\nentity B {\n  id : int\n}\nA }|..|| B\n@enduml\n";
            var r = new DiagramEngine("dot").parse(src, null);
            assert(r.diagram_type == DiagramType.ER_DIAGRAM);
            var d = (ERDiagram) r.ast;
            assert(d.entities.size == 2);
            var a = d.find_entity("A");
            assert(a != null);
            assert(a.stereotype == "foo");
            assert(a.attributes.size == 1);
            assert(d.relationships.size == 1);
            string dot = dot_of(src);
            assert(line_of(dot, "fillcolor=\"pink\"") == line_of(dot, "  A ["));
            assert(!dot.contains("\"}\""));
        }

        // ---- 5: a stray quote does not hold back placeholder lines ----

        public static void test_stray_quote_keeps_line_numbers() {
            string src = "@startuml\nA -> B : 3.5\" floppy\n!if 1 == 0\nX -> Y\n!endif\nA -> B : line6\n@enduml\n";
            string res = new Preprocessor().process(src, null);
            assert(line_of(res, "line6") == 6);
        }

        public static void test_multiline_quote_still_holds_placeholders() {
            string src = "@startuml\nusecase U1 as \"first\n!define X 1\nsecond\"\nactor Marker\n@enduml\n";
            string res = new Preprocessor().process(src, null);
            assert(res.contains("\"first\nsecond\"\n"));
            assert(line_of(res, "actor Marker") == 5);
        }

        // ---- 6: nested <style> element selectors ----

        public static void test_nested_style_selector_not_page_skinparam() {
            string src = "@startuml\n<style>\nclassDiagram {\n  class {\n    header {\n      FontColor red\n    }\n  }\n}\n</style>\nclass A\n@enduml\n";
            string res = new Preprocessor().process(src, null);
            assert(!res.down().contains("headerfontcolor"));
            // a single element still maps
            string src2 = "@startuml\n<style>\nclassDiagram {\n  class {\n    FontColor red\n  }\n}\n</style>\nclass A\n@enduml\n";
            assert(new Preprocessor().process(src2, null).contains("skinparam classFontColor red"));
        }

        // ---- 10: ER direction words ----

        public static void test_er_arrow_direction_no_ghost_entity() {
            string src = "@startuml\nentity A {\n  id : int\n}\nentity C {\n  id : int\n}\nA -up-> C\nA }o-left-|| C\n@enduml\n";
            var r = new DiagramEngine("dot").parse(src, null);
            var d = (ERDiagram) r.ast;
            assert(d.entities.size == 2);
            assert(d.find_entity("up") == null);
            assert(d.relationships.size == 2);
            assert(d.relationships[1].from_cardinality == ERCardinality.ZERO_OR_MANY);
            assert(d.relationships[1].to_cardinality == ERCardinality.ONE_MANDATORY);
        }

        // ---- 11: line numbers after !include ----

        public static void test_include_keeps_line_numbers() {
            string dir = "";
            try {
                dir = DirUtils.make_tmp("gd_review_inc_XXXXXX");
            } catch (Error e) {
                assert_not_reached();
            }
            string inc = Path.build_filename(dir, "common.iuml");
            try {
                FileUtils.set_contents(inc, "@startuml\nskinparam backgroundColor white\nparticipant Included\nparticipant Other\n@enduml\n");
            } catch (Error e) {
                assert_not_reached();
            }
            string src = "@startuml\n!include %s\nparticipant Alice\nAlice -> Included : hi\n@enduml\n".printf(inc);
            var r = new DiagramEngine("dot").parse(src, null);
            assert(r.diagram_type == DiagramType.SEQUENCE);
            var d = (SequenceDiagram) r.ast;
            Participant? alice = null;
            Participant? included = null;
            foreach (var p in d.participants) {
                if (p.name == "Alice") alice = p;
                if (p.name == "Included") included = p;
            }
            assert(alice != null && included != null);
            assert(alice.source_line == 3);
            // included content reports the !include line
            assert(included.source_line == 2);
            // a parse error after the include has its document line
            string bad = "@startuml\n!include %s\nparticipant Alice\nend\n@enduml\n".printf(inc);
            var rb = new DiagramEngine("dot").parse(bad, null);
            bool found = false;
            foreach (var err in rb.errors) {
                if (err.message.contains("'end'")) {
                    assert(err.line == 4);
                    found = true;
                }
            }
            assert(found);
            FileUtils.remove(inc);
            DirUtils.remove(dir);
        }

        public static void test_multiline_comment_and_string_line_numbers() {
            var tokens = new Lexer("/' one\ntwo\nthree '/\nparticipant \"a\nb\"\nparticipant X\n").scan_all();
            foreach (var t in tokens) {
                if (t.lexeme == "X") {
                    assert(t.line == 6);
                }
            }
        }

        // ---- 12: non-ASCII identifiers ----

        public static void test_lexer_non_ascii_identifier() {
            var tokens = new Lexer("class Äpfel\nÖl --> Birne").scan_all();
            assert(tokens[1].token_type == TokenType.IDENTIFIER);
            assert(tokens[1].lexeme == "Äpfel");
            assert(tokens[3].lexeme == "Öl");
            var r = new DiagramEngine("dot").parse("@startuml\nclass Äpfel\n@enduml\n", null);
            var d = (ClassDiagram) r.ast;
            assert(d.classes.size == 1);
            assert(d.classes[0].name == "Äpfel");
        }

        // Mermaid state classDef/class/:::/style lines: no ghost states, colours applied
        public static void test_mermaid_state_class_styles() {
            string src = "stateDiagram-v2\nclassDef hot fill:#f00,color:white\nclassDef cool fill:#aaddff,stroke:#003366\n" +
                         "[*] --> S\nS:::hot\nS --> T:::cool\nT --> U\nclass U cool\nstyle U stroke:#ff8800\n";
            var engine = new DiagramEngine("dot");
            var d = (MermaidStateDiagram) engine.parse(src, "x.mmd").ast;
            foreach (var st in d.states) {
                assert(st.id != "hot" && st.id != "fill" && st.id != "cool");
                assert(st.description == null || !st.description.contains(":"));
            }
            string? dot = engine.generate_dot(src, "x.mmd", null);
            assert(dot != null);
            assert(dot.contains("S [label=\"S\", shape=box, fillcolor=\"#f00\", fontcolor=\"white\"]"));
            assert(dot.contains("T [label=\"T\", shape=box, fillcolor=\"#aaddff\", fontcolor=\"#000000\", color=\"#003366\"]"));
            assert(dot.contains("U [label=\"U\", shape=box, fillcolor=\"#aaddff\", fontcolor=\"#000000\", color=\"#ff8800\"]"));
        }

        // Gitgraph commit names are xlabels on the canvas: they take the canvas label colour
        // (the edge text colour), not the contrast colour of the commit circle's fill
        public static void test_gitgraph_commit_label_colour() {
            string? dot = new DiagramEngine("dot").generate_dot(
                "gitGraph\n  commit id: \"Initial commit\"\n  commit id: \"Add README\"\n", "g.mmd", null);
            assert(dot != null);
            string edge_text = "";
            string commit_line = "";
            foreach (string line in dot.split("\n")) {
                if (line.strip().has_prefix("edge [")) {
                    int at = line.index_of("fontcolor=\"") + 11;
                    edge_text = line.substring(at, line.index_of("\"", at) - at);
                }
                if (line.contains("xlabel=\"Initial commit\"")) commit_line = line;
            }
            assert(edge_text != "");
            assert(commit_line.contains("fontcolor=\"%s\"".printf(edge_text)));
        }

        // A subgraph without [title] is labelled with its id / the rest of its line, as in Mermaid
        public static void test_mermaid_subgraph_default_title() {
            string? dot = new DiagramEngine("dot").generate_dot(
                "flowchart TD\n  subgraph Processing\n    A --> B\n  end\n  subgraph My Group\n    C\n  end\n  subgraph two [Second one]\n    D\n  end\n",
                "s.mmd", null);
            assert(dot != null);
            assert(dot.contains("label=\"Processing\";"));
            assert(dot.contains("label=\"My Group\";"));
            assert(dot.contains("label=\"Second one\";"));
        }

        // "'" and "<style>" only start a comment / style block at the start of a line;
        // mid-line they are text ("crow's foot", "(<style> blocks)")
        public static void test_lexer_line_start_comment_and_style() {
            var tokens = new Lexer("usecase (crow's foot) as cf\n' a real comment\n[Pre (<style> blocks)] as p\n").scan_all();
            int comments = 0;
            bool saw_cf = false;
            bool saw_p = false;
            foreach (var t in tokens) {
                if (t.token_type == TokenType.COMMENT) comments++;
                if (t.lexeme == "cf") saw_cf = true;
                if (t.lexeme == "p") saw_p = true;
            }
            assert(comments == 1);
            assert(saw_cf);
            assert(saw_p);
            var r = new DiagramEngine("dot").parse("@startuml\nactor User\nusecase (crow's foot) as cf\nUser --> cf\n@enduml\n", "u.puml");
            var d = (UseCaseDiagram) r.ast;
            bool labelled = false;
            foreach (var u in d.use_cases) {
                if (u.name == "crow's foot" && u.alias == "cf") labelled = true;
            }
            assert(labelled);
        }

        public static void test_mermaid_lexer_non_ascii() {
            var tokens = new MermaidLexer("Ä[Grüße] --> B").scan_all();
            assert(tokens[0].token_type == MermaidTokenType.IDENTIFIER);
            assert(tokens[0].lexeme == "Ä");
            assert(tokens[2].lexeme == "Grüße");
            var r = new DiagramEngine("dot").parse("flowchart LR\n  Ä[Grüße] --> B\n", "x.mmd");
            var d = (MermaidFlowchart) r.ast;
            assert(d.nodes.size == 2);
            bool found = false;
            foreach (var n in d.nodes) {
                if (n.id == "Ä") {
                    assert(n.text == "Grüße");
                    found = true;
                }
            }
            assert(found);
        }

        // ---- 2: "object" / "map" lines inside notes and action text ----

        public static void test_object_keyword_in_note_or_action_text() {
            assert(detect("@startuml\nstart\n:Load data;\nnote right\nmap entries are cached\nend note\nstop\n@enduml\n")
                   == DiagramType.ACTIVITY);
            assert(detect("@startuml\nnode Server\nnote right of Server\nobject storage backend\nend note\nnode Client\nClient --> Server\n@enduml\n")
                   == DiagramType.COMPONENT);
            assert(detect("@startuml\nactor User\nUser -> Bob : hi\nnote right\nmap is rebuilt\nend note\n@enduml\n")
                   == DiagramType.SEQUENCE);
            assert(detect("@startuml\nstart\n:Load\nobject pool;\nstop\n@enduml\n") == DiagramType.ACTIVITY);
            // real object diagrams stay
            assert(detect("@startuml\nobject user\nmap config {\n  a => b\n}\nuser --> config\n@enduml\n")
                   == DiagramType.OBJECT);
        }

        // ---- 3: use case files with deployment elements ----

        public static void test_usecase_with_cloud_is_usecase() {
            assert(detect("@startuml\nactor User\ncloud Internet\nUser --> (Login)\nUser --> Internet\n@enduml\n")
                   == DiagramType.USECASE);
            // a deployment file without use cases stays a component diagram
            assert(detect("@startuml\nactor User\ncloud Internet\nnode Web\nUser --> Web\nWeb --> Internet\n@enduml\n")
                   == DiagramType.COMPONENT);
        }

        // ---- 4: use case links and directional links ----

        public static void test_usecase_links_and_directional_class_links() {
            assert(detect("@startuml\n:user: -left-> (dummyLeft)\n:user: -up-> (dummyUp)\n@enduml\n") == DiagramType.USECASE);
            assert(detect("@startuml\nuser1 --> (Usecase 1)\nuser2 --> (Usecase 2)\n@enduml\n") == DiagramType.USECASE);
            assert(detect("@startuml\n:User: --> (Use)\n\"Main Admin\" as Admin\nAdmin --> (Admin the application)\n@enduml\n")
                   == DiagramType.USECASE);
            assert(detect("@startuml\nfoo -left-> dummyLeft\nfoo -up-> dummyUp\n@enduml\n") == DiagramType.CLASS);
            // IE ends stay class diagrams, as in PlantUML
            assert(detect("@startuml\nEntityA ||--o{ EntityB\n@enduml\n") == DiagramType.CLASS);
            // plain sequence messages stay sequence diagrams
            assert(detect("@startuml\nAlice -> Bob : hi\nBob --> Alice : ok\n@enduml\n") == DiagramType.SEQUENCE);
        }

        // ---- 7: message label colour on a canvas set in the file ----

        public static void test_sequence_label_colour_on_skin_background() {
            var dark = ThemeManager.get_preset("default-dark");
            ThemeManager.set_active_palette(dark);
            string dot = dot_of("@startuml\nskinparam backgroundColor #FFFFFF\nAlice -> Bob : hello\n@enduml\n");
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
            // the dark palette's label text is light: it must not be used on white
            assert(RenderUtils.contrast_text("#FFFFFF") != dark.edge_text);
            int messages = line_of(dot, "// Messages");
            assert(messages > 0);
            string edge_defaults = dot.split("\n")[messages];
            assert(edge_defaults.contains("fontcolor=\"%s\"".printf(RenderUtils.contrast_text("#FFFFFF"))));
            assert(!edge_defaults.contains("\"%s\"".printf(dark.edge_text)));
        }

        // ---- 8: palette snippets on their own ----

        public static void test_lone_snippet_detection() {
            string[] sources = {
                "note over Alice : Note text", "ClassA -- ClassB : label", "Client ..> Supplier : uses",
                "ComponentName - InterfaceName", "note \"Note text\" as N1", "ActorName -- (Use case)",
                "|Swimlane|", "note right: Note text", "actor Actor", "database Database",
                "Bob -[#red]> Alice"
            };
            DiagramType[] expected = {
                DiagramType.SEQUENCE, DiagramType.CLASS, DiagramType.CLASS,
                DiagramType.CLASS, DiagramType.CLASS, DiagramType.USECASE,
                DiagramType.ACTIVITY, DiagramType.ACTIVITY, DiagramType.SEQUENCE, DiagramType.SEQUENCE,
                DiagramType.SEQUENCE
            };
            for (int i = 0; i < sources.length; i++) {
                DiagramType got = detect("@startuml\n%s\n@enduml\n".printf(sources[i]));
                if (got != expected[i]) {
                    printerr("%s: %s\n", sources[i], got.to_string());
                }
                assert(got == expected[i]);
            }
        }

        // ---- 9: sequence messages ----

        private static SequenceDiagram parse_seq(string body) {
            var r = new DiagramEngine("dot").parse("@startuml\n%s\n@enduml\n".printf(body), null);
            assert(r.diagram_type == DiagramType.SEQUENCE);
            return (SequenceDiagram) r.ast;
        }

        public static void test_sequence_activation_before_label() {
            var d = parse_seq("participant alice\nparticipant bob\nalice -> bob ++ : hello");
            assert(d.messages.size == 1);
            assert(d.messages[0].label == "hello");
            assert(d.messages[0].activate_target);
        }

        public static void test_sequence_coloured_arrow() {
            var d = parse_seq("Bob -[#red]> Alice : hi\nAlice -[#blue]-> Bob");
            assert(d.participants.size == 2);
            assert(d.messages.size == 2);
            assert(d.messages[0].color == "#red");
            assert(d.messages[0].style == ArrowStyle.SOLID);
            assert(d.messages[0].label == "hi");
            assert(d.messages[1].style == ArrowStyle.DOTTED);
            var engine = new DiagramEngine("dot");
            string dot = dot_of("@startuml\nBob -[#red]> Alice\n@enduml\n");
            assert(dot.contains("color=\"red\""));
            string png = Path.build_filename(Environment.get_tmp_dir(), "gd_review_seq_%s.png".printf(Uuid.string_random()));
            assert(engine.export_to_png("@startuml\nBob -[#red]> Alice\n@enduml\n", null, null, png));
            FileUtils.remove(png);
        }

        public static void test_sequence_note_across() {
            var d = parse_seq("participant A\nparticipant B\nnote across: x\nA -> B : after\nB -> A : back");
            assert(d.notes.size == 1);
            assert(d.notes[0].text == "x");
            assert(d.messages.size == 2);
        }

        public static void test_sequence_open_left_arrows() {
            var d = parse_seq("participant A\nparticipant B\nB <<- A : one\nB <<-- A : two");
            assert(d.errors.size == 0);
            assert(d.messages.size == 2);
            assert(d.messages[0].direction == ArrowDirection.LEFT);
            assert(d.messages[0].style == ArrowStyle.SOLID_OPEN);
            assert(d.messages[1].style == ArrowStyle.DOTTED_OPEN);
            // a left arrow's head is at its first participant: "B <- A" points at B
            string dot = dot_of("@startuml\nparticipant A\nparticipant B\nB <- A : m\n@enduml\n");
            assert(dot.contains("A_m0 -> B_m0 [style=solid, arrowhead=normal"));
            assert(dot.contains("_seq_lbl_m0 [") && dot.contains("label=\"  m  \""));
            assert(!dot.contains("dir=back"));
        }

        // "hnote" / "rnote": hexagonal and rectangular notes, single- and multi-line, with a
        // colour. They were not recognised; their body lines were parsed as statements.
        public static void test_sequence_hnote_rnote() {
            string body = "participant A\nparticipant B\nA -> B : x\n" +
                          "hnote over A #lightblue : idle\n" +
                          "rnote over A, B\nA -> B : inside\nendrnote\n" +
                          "hnote across : all\n" +
                          "hnote over B\nmulti\nend hnote\n" +
                          "note over A #FFAAAA\nplain\nendnote\n" +
                          "B -> A : after";
            var d = parse_seq(body);
            assert(d.errors.size == 0);
            assert(d.notes.size == 5);
            assert(d.messages.size == 2);
            assert(d.messages[1].label == "after");
            assert(d.notes[0].kind == "hnote");
            assert(d.notes[0].text == "idle");
            assert(d.notes[0].color == "#lightblue");
            assert(d.notes[0].participant.name == "A");
            assert(d.notes[1].kind == "rnote");
            assert(d.notes[1].text == "A -> B : inside");
            assert(d.notes[1].participant2 != null && d.notes[1].participant2.name == "B");
            assert(d.notes[2].kind == "hnote");
            assert(d.notes[2].position == "across");
            assert(d.notes[2].text == "all");
            assert(d.notes[3].text == "multi");
            assert(d.notes[4].kind == "note");
            assert(d.notes[4].text == "plain");
            assert(d.notes[4].color == "#FFAAAA");
            string dot = dot_of("@startuml\n%s\n@enduml\n".printf(body));
            assert(dot.contains("note0 [shape=hexagon, style=filled, fillcolor=\"lightblue\""));
            assert(dot.contains("note1 [shape=box,"));
            assert(dot.contains("note4 [shape=note, style=filled, fillcolor=\"#FFAAAA\""));
        }

        // "[-> A", "A ->]", "?-> A", "A ->?" and their styles: messages to and from the
        // diagram border. "[" was skipped (message lost) and "]" failed the export.
        public static void test_sequence_border_arrows() {
            string body = "participant A\nparticipant B\n" +
                          "[-> A : in\nA ->] : out\n[<- A\nA <-]\n?-> A : short\nA ->?\n" +
                          "[-[#red]> B\n[o-> A\nA ->x]\nA<--] : dashed";
            var d = parse_seq(body);
            assert(d.errors.size == 0);
            assert(d.participants.size == 2);
            assert(d.messages.size == 10);
            MessageBorder[] borders = {
                MessageBorder.LEFT, MessageBorder.RIGHT, MessageBorder.LEFT, MessageBorder.RIGHT,
                MessageBorder.LEFT, MessageBorder.RIGHT, MessageBorder.LEFT, MessageBorder.LEFT,
                MessageBorder.RIGHT, MessageBorder.RIGHT
            };
            for (int i = 0; i < borders.length; i++) {
                assert(d.messages[i].border == borders[i]);
                assert(d.messages[i].border_short == (i == 4 || i == 5));
                assert(d.messages[i].from == d.messages[i].to);
            }
            assert(d.messages[0].label == "in");
            assert(d.messages[0].direction == ArrowDirection.RIGHT);
            assert(d.messages[2].direction == ArrowDirection.LEFT);
            assert(d.messages[3].direction == ArrowDirection.LEFT);
            assert(d.messages[6].color == "#red");
            assert(d.messages[6].from.name == "B");
            assert(d.messages[9].style == ArrowStyle.DOTTED);
            assert(d.messages[9].label == "dashed");

            string src = "@startuml\n%s\n@enduml\n".printf(body);
            string dot = dot_of(src);
            assert(dot.contains("_seq_bl_m0 -> A_m0 ["));
            assert(dot.contains("label=\"  in  \""));
            assert(dot.contains("A_m1 -> _seq_br_m1 ["));
            assert(dot.contains("label=\"  out  \""));
            // "[<- A": the head is at the border
            assert(dot.contains("A_m2 -> _seq_bl_m2 ["));
            // "A <-]": the head is at A
            assert(dot.contains("_seq_br_m3 -> A_m3 ["));
            assert(dot.contains("_seq_sl_m4 -> A_m4 ["));
            assert(dot.contains("label=\"  short  \""));
            assert(dot.contains("A_m5 -> _seq_sr_m5 ["));
            string png = Path.build_filename(Environment.get_tmp_dir(), "gd_review_seq_%s.png".printf(Uuid.string_random()));
            assert(new DiagramEngine("dot").export_to_png(src, null, null, png));
            FileUtils.remove(png);
        }

        // examples/plantuml/sequence/53: its PNG export failed on "Bob ->]"
        public static void test_sequence_border_example_export() {
            string src = "@startuml\nparticipant Alice\nparticipant Bob #lightblue\nAlice -> Bob\nBob -> Carol\n" +
                         "...\n[-> Bob\n[o-> Bob\n[o->o Bob\n[x-> Bob\n...\n[<- Bob\n[x<- Bob\n...\n" +
                         "Bob ->]\nBob ->o]\nBob o->o]\nBob ->x]\n...\nBob <-]\nBob x<-]\n@enduml\n";
            var r = new DiagramEngine("dot").parse(src, null);
            var d = (SequenceDiagram) r.ast;
            assert(d.errors.size == 0);
            assert(d.participants.size == 3);
            assert(d.messages.size == 14);
            string png = Path.build_filename(Environment.get_tmp_dir(), "gd_review_seq_%s.png".printf(Uuid.string_random()));
            assert(new DiagramEngine("dot").export_to_png(src, null, null, png));
            FileUtils.remove(png);
        }

        public static int main(string[] args) {
            Test.init(ref args);
            Test.add_func("/review-frontend/1/mindmap-style-stereotype", test_mindmap_style_stereotype);
            Test.add_func("/review-frontend/1/mindmap-one-line-skinparam-block", test_mindmap_one_line_skinparam_block);
            Test.add_func("/review-frontend/1/er-style-stereotype", test_er_style_stereotype);
            Test.add_func("/review-frontend/5/stray-quote-line-numbers", test_stray_quote_keeps_line_numbers);
            Test.add_func("/review-frontend/5/multiline-quote-placeholders", test_multiline_quote_still_holds_placeholders);
            Test.add_func("/review-frontend/6/nested-style-selector", test_nested_style_selector_not_page_skinparam);
            Test.add_func("/review-frontend/10/er-arrow-direction", test_er_arrow_direction_no_ghost_entity);
            Test.add_func("/review-frontend/11/include-line-numbers", test_include_keeps_line_numbers);
            Test.add_func("/review-frontend/11/multiline-comment-string-lines", test_multiline_comment_and_string_line_numbers);
            Test.add_func("/review-frontend/12/lexer-non-ascii", test_lexer_non_ascii_identifier);
            Test.add_func("/review-frontend/12/mermaid-lexer-non-ascii", test_mermaid_lexer_non_ascii);
            Test.add_func("/review-frontend/mermaid-state-class-styles", test_mermaid_state_class_styles);
            Test.add_func("/review-frontend/gitgraph-commit-label-colour", test_gitgraph_commit_label_colour);
            Test.add_func("/review-frontend/mermaid-subgraph-default-title", test_mermaid_subgraph_default_title);
            Test.add_func("/review-frontend/lexer-line-start-comment-style", test_lexer_line_start_comment_and_style);
            Test.add_func("/review-frontend/2/object-keyword-in-text", test_object_keyword_in_note_or_action_text);
            Test.add_func("/review-frontend/3/usecase-with-cloud", test_usecase_with_cloud_is_usecase);
            Test.add_func("/review-frontend/4/usecase-and-directional-links", test_usecase_links_and_directional_class_links);
            Test.add_func("/review-frontend/7/sequence-label-colour", test_sequence_label_colour_on_skin_background);
            Test.add_func("/review-frontend/8/lone-snippets", test_lone_snippet_detection);
            Test.add_func("/review-frontend/9/activation-before-label", test_sequence_activation_before_label);
            Test.add_func("/review-frontend/9/coloured-arrow", test_sequence_coloured_arrow);
            Test.add_func("/review-frontend/9/note-across", test_sequence_note_across);
            Test.add_func("/review-frontend/9/open-left-arrows", test_sequence_open_left_arrows);
            Test.add_func("/review-frontend/9/hnote-rnote", test_sequence_hnote_rnote);
            Test.add_func("/review-frontend/9/border-arrows", test_sequence_border_arrows);
            Test.add_func("/review-frontend/9/border-example-export", test_sequence_border_example_export);
            return Test.run();
        }
    }
}
