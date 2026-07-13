/*
 * Unit tests for the LSP server's pure logic: LspProtocol (JSON response
 * builders) and LspDocumentState (format/type detection + parse + diagnostics).
 *
 * These exercise the request-handler payloads directly, without spinning up
 * the stdio server. The full stdio round-trip is covered by
 * lsp_server_test.vala (integration).
 */
namespace GDiagram.Tests {
    public class LspProtocolTests {

        // ── LspProtocol.build_initialize_result ──────────────────────
        public static void test_initialize_capabilities() {
            var node = LspProtocol.build_initialize_result();
            assert(node != null);
            var obj = node.get_object();
            assert(obj.has_member("capabilities"));

            var caps = obj.get_object_member("capabilities");
            assert(caps.get_boolean_member("hoverProvider") == true);
            assert(caps.get_boolean_member("documentSymbolProvider") == true);
            assert(caps.has_member("completionProvider"));
            assert(caps.has_member("textDocumentSync"));

            // textDocumentSync must advertise Full sync (change == 1)
            var sync = caps.get_object_member("textDocumentSync");
            assert(sync.get_boolean_member("openClose") == true);
            assert(sync.get_int_member("change") == 1);

            var info = obj.get_object_member("serverInfo");
            assert(info.get_string_member("name") == "gdiagram-lsp");
        }

        // ── LspDocumentState.reparse ─────────────────────────────────
        public static void test_reparse_valid_sequence() {
            string src = "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob: Hi\n@enduml\n";
            var state = new LspDocumentState("file:///a.puml", src, "plantuml", 1);
            state.reparse();
            assert(state.format == DiagramFormat.PLANTUML);
            assert(state.diagram_type == DiagramType.SEQUENCE);
            assert(state.parsed_ast != null);
            // A clean diagram must not emit diagnostics.
            assert(state.diagnostics.size == 0);
        }

        public static void test_reparse_unknown_produces_diagnostic() {
            // Content that is neither recognisable PlantUML nor Mermaid:
            // reparse must not crash and must surface a diagnostic.
            string src = "@startuml\nxyzzy nonsense qwerty\n@enduml\n";
            var state = new LspDocumentState("file:///b.puml", src, "plantuml", 1);
            state.reparse();
            assert(state.diagnostics.size > 0);
        }

        public static void test_reparse_mermaid_flowchart() {
            string src = "flowchart TD\n  A[Start] --> B[End]\n";
            var state = new LspDocumentState("file:///c.mmd", src, "mermaid", 1);
            state.reparse();
            assert(state.format == DiagramFormat.MERMAID);
            assert(state.diagram_type == DiagramType.MERMAID_FLOWCHART);
        }

        public static void test_reparse_empty_no_crash() {
            var state = new LspDocumentState("file:///d.puml", "   \n\n", "plantuml", 1);
            state.reparse();
            assert(state.diagram_type == DiagramType.UNKNOWN);
            // Empty content is not an error, just unknown.
            assert(state.diagnostics.size == 0);
        }

        // ── LspProtocol.build_completion_items ───────────────────────
        public static void test_completion_plantuml_sequence() {
            var node = LspProtocol.build_completion_items(DiagramFormat.PLANTUML, DiagramType.SEQUENCE);
            var arr = node.get_array();
            assert(arr.get_length() > 0);
            assert(completion_has_label(arr, "@startuml"));
            assert(completion_has_label(arr, "->"));
            // Every item must carry a label and an integer kind.
            for (uint i = 0; i < arr.get_length(); i++) {
                var o = arr.get_object_element(i);
                assert(o.has_member("label"));
                assert(o.has_member("kind"));
            }
        }

        public static void test_completion_mermaid() {
            var node = LspProtocol.build_completion_items(DiagramFormat.MERMAID, DiagramType.MERMAID_FLOWCHART);
            var arr = node.get_array();
            assert(arr.get_length() > 0);
            assert(completion_has_label(arr, "flowchart"));
        }

        private static bool completion_has_label(Json.Array arr, string label) {
            for (uint i = 0; i < arr.get_length(); i++) {
                var o = arr.get_object_element(i);
                if (o.get_string_member("label") == label) return true;
            }
            return false;
        }

        // ── LspProtocol.build_document_symbols ───────────────────────
        public static void test_document_symbols_sequence() {
            string src = "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob: Hi\n@enduml\n";
            var state = new LspDocumentState("file:///e.puml", src, "plantuml", 1);
            state.reparse();
            assert(state.parsed_ast != null);

            var node = LspProtocol.build_document_symbols(state);
            var arr = node.get_array();
            // One top-level "diagram" symbol.
            assert(arr.get_length() == 1);

            var top = arr.get_object_element(0);
            assert(top.has_member("name"));
            assert(top.has_member("children"));
            // Participants + messages become children.
            var children = top.get_array_member("children");
            assert(children.get_length() > 0);
        }

        public static void test_document_symbols_empty_without_ast() {
            var state = new LspDocumentState("file:///f.puml", "   ", "plantuml", 1);
            state.reparse();
            var node = LspProtocol.build_document_symbols(state);
            assert(node.get_array().get_length() == 0);
        }

        // ── LspProtocol.build_hover ──────────────────────────────────
        public static void test_hover_keyword() {
            string src = "@startuml\nparticipant Alice\n@enduml\n";
            var state = new LspDocumentState("file:///g.puml", src, "plantuml", 1);
            state.reparse();
            // Line 1 = "participant Alice"; char 2 falls inside "participant".
            var node = LspProtocol.build_hover(state, 1, 2);
            assert(node != null);
            var contents = node.get_object().get_object_member("contents");
            assert(contents.get_string_member("kind") == "markdown");
            assert(contents.get_string_member("value").down().contains("participant"));
        }

        public static void test_hover_non_keyword_is_null() {
            string src = "@startuml\nparticipant Alice\n@enduml\n";
            var state = new LspDocumentState("file:///h.puml", src, "plantuml", 1);
            state.reparse();
            // "Alice" is an element now (element hover); a label word is neither keyword nor element
            assert(LspProtocol.build_hover(state, 1, 13) != null);
            var labelled = new LspDocumentState("file:///h2.puml",
                "@startuml\nparticipant Alice\nAlice -> Alice : wave\n@enduml\n", "plantuml", 1);
            labelled.reparse();
            var node = LspProtocol.build_hover(labelled, 2, 18);
            assert(node == null);
        }

        // ── LspProtocol.build_diagnostics_notification ───────────────
        public static void test_diagnostics_notification_shape() {
            var diags = new Gee.ArrayList<LspDiagnostic>();
            diags.add(new LspDiagnostic(1, 2, 3, 4, 1, "gdiagram", "boom"));

            string json = LspProtocol.build_diagnostics_notification("file:///x.puml", diags);
            var parser = new Json.Parser();
            try {
                parser.load_from_data(json);
            } catch (Error e) {
                assert_not_reached();
            }

            var obj = parser.get_root().get_object();
            assert(obj.get_string_member("jsonrpc") == "2.0");
            assert(obj.get_string_member("method") == "textDocument/publishDiagnostics");

            var p = obj.get_object_member("params");
            assert(p.get_string_member("uri") == "file:///x.puml");

            var da = p.get_array_member("diagnostics");
            assert(da.get_length() == 1);

            var d0 = da.get_object_element(0);
            assert(d0.get_string_member("message") == "boom");
            assert(d0.get_int_member("severity") == 1);
            assert(d0.get_string_member("source") == "gdiagram");

            var range = d0.get_object_member("range");
            assert(range.get_object_member("start").get_int_member("line") == 1);
            assert(range.get_object_member("start").get_int_member("character") == 2);
            assert(range.get_object_member("end").get_int_member("line") == 3);
            assert(range.get_object_member("end").get_int_member("character") == 4);
        }

        public static void test_diagnostics_notification_empty() {
            var diags = new Gee.ArrayList<LspDiagnostic>();
            string json = LspProtocol.build_diagnostics_notification("file:///y.puml", diags);
            var parser = new Json.Parser();
            try {
                parser.load_from_data(json);
            } catch (Error e) {
                assert_not_reached();
            }
            var p = parser.get_root().get_object().get_object_member("params");
            assert(p.get_array_member("diagnostics").get_length() == 0);
        }

        // ── LspProtocol.build_templates_list ─────────────────────────
        public static void test_templates_non_empty() {
            var node = LspProtocol.build_templates_list();
            var arr = node.get_array();
            assert(arr.get_length() > 0);
            // Each entry must expose name/format/type.
            var first = arr.get_object_element(0);
            assert(first.has_member("name"));
            assert(first.has_member("format"));
            assert(first.has_member("type"));
        }

        // ── LspProtocol.uri_to_path + include base path ──────────────
        public static void test_uri_to_path() {
            assert(LspProtocol.uri_to_path("file:///home/me/My%20Diagrams/a%23b.puml") ==
                   "/home/me/My Diagrams/a#b.puml");
            assert(LspProtocol.uri_to_path("untitled:Untitled-1") == null);
            assert(LspProtocol.uri_to_path("https://example.com/a.puml") == null);
        }

        // A relative !include resolves against the document's directory, not the
        // server's working directory (a directory name with a space needs decoding).
        public static void test_reparse_resolves_include_next_to_document() {
            string root;
            try {
                root = DirUtils.make_tmp("gdiagram-lsp-XXXXXX");
            } catch (FileError e) {
                error("mkdtemp: %s", e.message);
            }
            string doc_dir = Path.build_filename(root, "My Diagrams");
            DirUtils.create_with_parents(doc_dir, 0755);
            string doc_path = Path.build_filename(doc_dir, "plan.puml");
            string src = "@startgantt\n!include lsp_parts.iuml\n[MainTask] requires 1 days\n@endgantt\n";
            try {
                FileUtils.set_contents(Path.build_filename(doc_dir, "lsp_parts.iuml"),
                                       "[IncludedTask] requires 2 days\n[OtherTask] requires 2 days\n");
                FileUtils.set_contents(doc_path, src);
            } catch (FileError e) {
                error("write: %s", e.message);
            }
            assert(!FileUtils.test("lsp_parts.iuml", FileTest.EXISTS));

            string uri;
            try {
                uri = Filename.to_uri(doc_path, null);
            } catch (ConvertError e) {
                error("to_uri: %s", e.message);
            }
            assert(uri.contains("My%20Diagrams"));
            var state = new LspDocumentState(uri, src, "plantuml", 1);
            assert(state.file_path == doc_path);
            state.reparse();
            assert(state.diagram_type == DiagramType.GANTT);
            var d = (PumlGanttDiagram) state.parsed_ast;
            var lines = new Gee.HashMap<string, int>();
            foreach (var t in d.tasks) {
                lines[t.name] = t.source_line;
            }
            assert(lines.has_key("IncludedTask"));
            assert(lines["IncludedTask"] == 2);
            assert(lines["MainTask"] == 3);

            uint8[]? svg = state.render_svg();
            assert(svg != null);
            var svg_sb = new StringBuilder.sized(svg.length + 1);
            svg_sb.append_len((string) svg, svg.length);
            string svg_text = svg_sb.str;
            assert(svg_text.contains("IncludedTask"));
        }

        // ── Keyword tables for newly supported syntax ────────────────

        private static Json.Object? completion_item(Json.Array arr, string label) {
            for (uint i = 0; i < arr.get_length(); i++) {
                var o = arr.get_object_element(i);
                if (o.get_string_member("label") == label) return o;
            }
            return null;
        }

        private static LspDocumentState parsed(string uri, string src) {
            var state = new LspDocumentState(uri, src, "", 1);
            state.reparse();
            return state;
        }

        private static string? hover_at(LspDocumentState state, string needle) {
            string[] lines = state.content.split("\n");
            for (int l = 0; l < lines.length; l++) {
                int col = lines[l].index_of(needle);
                if (col < 0) continue;
                var node = LspProtocol.build_hover(state, l, col + 1);
                if (node == null) return null;
                return node.get_object().get_object_member("contents").get_string_member("value");
            }
            assert_not_reached();
        }

        public static void test_completion_timing_and_gantt() {
            var timing = parsed("file:///t.puml",
                "@startuml\nrobust \"Web\" as W\nconcise \"User\" as U\n@0\nU is Idle\n@enduml\n");
            assert(timing.diagram_type == DiagramType.TIMING);
            var arr = LspProtocol.build_completion_items(timing.format, timing.diagram_type, timing.content).get_array();
            foreach (string label in new string[] { "robust", "concise", "binary", "clock", "analog", "highlight",
                                                    "hide time-axis", "mode compact", "@0 as :anchor", "<->" }) {
                assert(completion_item(arr, label) != null);
            }
            // Other types' statements stay out
            assert(completion_item(arr, "autoactivate") == null);
            assert(completion_item(arr, "Project starts") == null);
            var clock = completion_item(arr, "clock");
            assert(clock.get_int_member("insertTextFormat") == 2);
            assert(clock.get_string_member("insertText").contains("with period"));

            var gantt = parsed("file:///g.puml",
                "@startgantt\nProject starts 2026-01-05\n[Design] lasts 5 days\n@endgantt\n");
            assert(gantt.diagram_type == DiagramType.GANTT);
            arr = LspProtocol.build_completion_items(gantt.format, gantt.diagram_type, gantt.content).get_array();
            foreach (string label in new string[] { "Project starts", "lasts", "requires", "then", "happens",
                                                    "is colored in", "-- Separator --", "printscale", "today is" }) {
                assert(completion_item(arr, label) != null);
            }
            assert(completion_item(arr, "robust") == null);
        }

        public static void test_completion_type_keywords() {
            var arr = LspProtocol.build_completion_items(DiagramFormat.PLANTUML, DiagramType.SEQUENCE).get_array();
            foreach (string label in new string[] { "autoactivate", "return", "newpage", "hnote", "[->", "->]", "order" }) {
                assert(completion_item(arr, label) != null);
            }
            arr = LspProtocol.build_completion_items(DiagramFormat.PLANTUML, DiagramType.STATE).get_array();
            foreach (string label in new string[] { "[H*]", "<<entryPoint>>", "<<sdlreceive>>", "note on link", "||" }) {
                assert(completion_item(arr, label) != null);
            }
            arr = LspProtocol.build_completion_items(DiagramFormat.PLANTUML, DiagramType.CLASS).get_array();
            foreach (string label in new string[] { "{field}", "dataclass", "hide empty members", "(A, B) .. C" }) {
                assert(completion_item(arr, label) != null);
            }
            arr = LspProtocol.build_completion_items(DiagramFormat.PLANTUML, DiagramType.COMPONENT).get_array();
            foreach (string label in new string[] { "portin", "actor/", "collections", "-[thickness=2]->" }) {
                assert(completion_item(arr, label) != null);
            }
            // Without a C4 include a component diagram gets no C4 macros
            assert(completion_item(arr, "Person") == null);

            arr = LspProtocol.build_completion_items(DiagramFormat.MERMAID, DiagramType.MERMAID_GANTT).get_array();
            assert(completion_item(arr, "dateFormat") != null);
            assert(completion_item(arr, "gantt") != null);
            assert(completion_item(arr, "service") == null);
            arr = LspProtocol.build_completion_items(DiagramFormat.MERMAID, DiagramType.MERMAID_ARCHITECTURE).get_array();
            assert(completion_item(arr, "service") != null);
            assert(completion_item(arr, "junction") != null);
            arr = LspProtocol.build_completion_items(DiagramFormat.MERMAID, DiagramType.MERMAID_RADAR).get_array();
            assert(completion_item(arr, "curve") != null);
            arr = LspProtocol.build_completion_items(DiagramFormat.MERMAID, DiagramType.MERMAID_KANBAN).get_array();
            assert(completion_item(arr, "priority") != null);
            arr = LspProtocol.build_completion_items(DiagramFormat.MERMAID, DiagramType.MERMAID_FLOWCHART).get_array();
            assert(completion_item(arr, "@{ shape: }") != null);
            assert(completion_item(arr, "dateFormat") == null);
        }

        public static void test_completion_and_hover_c4() {
            string src = "@startuml\n!include <C4/C4_Container>\nPerson(user, \"User\")\n" +
                "System(sys, \"System\")\nRel_U(user, sys, \"Uses\")\nSHOW_LEGEND()\n@enduml\n";
            var state = parsed("file:///c4.puml", src);
            assert(state.format == DiagramFormat.PLANTUML);
            var arr = LspProtocol.build_completion_items(state.format, state.diagram_type, state.content).get_array();
            var person = completion_item(arr, "Person");
            assert(person != null);
            assert(person.get_int_member("kind") == LspKeywords.KIND_FUNCTION);
            assert(person.get_string_member("insertText").has_prefix("Person(${1:alias}"));
            foreach (string label in new string[] { "System_Boundary", "ContainerDb", "Rel", "BiRel", "RelIndex",
                                                    "LAYOUT_LEFT_RIGHT", "AddElementTag", "UpdateRelStyle",
                                                    "Deployment_Node" }) {
                assert(completion_item(arr, label) != null);
            }

            string? rel = hover_at(state, "Rel_U");
            assert(rel != null);
            assert(rel.contains("Rel_U($from, $to, $label, $techn=\"\""));
            assert(rel.contains("upwards"));
            string? legend = hover_at(state, "SHOW_LEGEND");
            assert(legend != null && legend.contains("$hideStereotype"));
            // The element a macro call declares shows where to edit it
            string? user = hover_at(state, "user,");
            assert(user != null && user.contains("Person macro: edit the call on line 3"));
        }

        public static void test_hover_new_keywords() {
            var timing = parsed("file:///ht.puml", "@startuml\nrobust \"Web\" as W\n@0\nW is Idle\n@enduml\n");
            assert(hover_at(timing, "robust").contains("Robust signal"));
            var gantt = parsed("file:///hg.puml", "@startgantt\n[Design] lasts 5 days\n@endgantt\n");
            assert(hover_at(gantt, "lasts").contains("calendar days"));
            var seq = parsed("file:///hs.puml", "@startuml\nautoactivate on\nAlice -> Bob : hi\nhnote over Bob : x\n@enduml\n");
            assert(hover_at(seq, "autoactivate").contains("return"));
            assert(hover_at(seq, "hnote").contains("Hexagonal"));
            var mmd = parsed("file:///hm.mmd", "gantt\n    dateFormat YYYY-MM-DD\n    section A\n    T :a1, 2026-01-05, 3d\n");
            assert(mmd.format == DiagramFormat.MERMAID);
            assert(hover_at(mmd, "dateFormat").contains("dateFormat YYYY-MM-DD"));
            assert(hover_at(mmd, "gantt").contains("Gantt"));
        }

        private static Json.Array symbol_children(LspDocumentState state) {
            var arr = LspProtocol.build_document_symbols(state).get_array();
            assert(arr.get_length() == 1);
            return arr.get_object_element(0).get_array_member("children");
        }

        public static void test_document_symbols_timing_gantt() {
            var timing = parsed("file:///st.puml",
                "@startuml\nrobust \"Web\" as W\nconcise \"User\" as U\n@0\nW is Idle\nU is Busy\nU -> W@100 : ping\n@enduml\n");
            var children = symbol_children(timing);
            assert(children.get_length() == 3);
            var web = children.get_object_element(0);
            assert(web.get_string_member("name") == "Web");
            assert(web.get_string_member("detail") == "robust");
            assert(web.get_object_member("range").get_object_member("start").get_int_member("line") == 1);
            assert(children.get_object_element(2).get_string_member("name") == "U -> W: ping");

            var gantt = parsed("file:///sg.puml",
                "@startgantt\n[Design] lasts 5 days\n-- Build --\n[Code] lasts 3 days\n[Done] happens at [Code]'s end\n@endgantt\n");
            children = symbol_children(gantt);
            assert(children.get_length() == 2);
            assert(children.get_object_element(0).get_string_member("name") == "Design");
            var sep = children.get_object_element(1);
            assert(sep.get_string_member("name") == "Build");
            var tasks = sep.get_array_member("children");
            assert(tasks.get_length() == 2);
            assert(tasks.get_object_element(1).get_string_member("detail") == "milestone");
        }


        // ── Diagnostics from preprocessor and parse errors ───────────

        private static void dump_diagnostics(LspDocumentState state) {
            foreach (var d in state.diagnostics) {
                stderr.printf("  diag %d:%d-%d:%d sev %d: %s\n", d.start_line, d.start_char, d.end_line, d.end_char,
                              d.severity, d.message);
            }
        }

        public static void test_diagnostics_unresolved_include() {
            string src = "@startuml\n!include does_not_exist.iuml\nclass A\n@enduml\n";
            var state = parsed("file:///tmp/gdiagram-lsp-no-such-dir/inc.puml", src);
            dump_diagnostics(state);
            assert(state.include_error != null);
            assert(state.include_error.contains("does_not_exist.iuml"));
            bool found = false;
            foreach (var d in state.diagnostics) {
                if (d.message.contains("does_not_exist.iuml")) {
                    found = true;
                    assert(d.severity == 1);
                    assert(d.start_line == 1 && d.end_line == 1);
                    assert(d.start_char == 0 && d.end_char == "!include does_not_exist.iuml".length);
                }
            }
            assert(found);

            // Resolving it again clears the error
            state.content = "@startuml\nclass A\n@enduml\n";
            state.reparse();
            assert(state.include_error == null);
            assert(state.diagnostics.size == 0);
        }

        public static void test_diagnostics_parse_errors() {
            string seq = "@startuml\nparticipant Alice\nAlice -> Bob : hi\nelse\n@enduml\n";
            var s1 = parsed("file:///bs.puml", seq);
            dump_diagnostics(s1);
            assert(s1.diagram_type == DiagramType.SEQUENCE);
            assert(s1.diagnostics.size > 0);
            var d1 = s1.diagnostics[0];
            assert(d1.severity == 1);
            assert(d1.start_line == 3);  // the "else" line (0-based)
            assert(d1.end_char == 4);

            string flow = "flowchart TD\n    A[Start --> B\n    B --> C\n";
            var s2 = parsed("file:///bf.mmd", flow);
            dump_diagnostics(s2);
            assert(s2.format == DiagramFormat.MERMAID);
            assert(s2.diagnostics.size > 0);
            assert(s2.diagnostics[0].severity == 1);
            assert(s2.diagnostics[0].start_line >= 1 && s2.diagnostics[0].start_line <= 2);
        }

        public static void test_document_symbols_ranges_and_types() {
            // Sequence and class children sit on their source lines, not 0:0
            var seq = parsed("file:///ss.puml", "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob : hi\n@enduml\n");
            var children = symbol_children(seq);
            assert(children.get_length() == 3);
            assert(children.get_object_element(1).get_object_member("range").get_object_member("start")
                   .get_int_member("line") == 2);
            assert(children.get_object_element(2).get_object_member("range").get_object_member("start")
                   .get_int_member("line") == 3);

            var activity = parsed("file:///sa.puml", "@startuml\nstart\n:Say **hi**;\nstop\n@enduml\n");
            children = symbol_children(activity);
            bool has_action = false;
            for (uint i = 0; i < children.get_length(); i++) {
                var c = children.get_object_element(i);
                if (c.get_string_member("name") == "Say hi") {
                    has_action = true;
                    assert(c.get_object_member("range").get_object_member("start").get_int_member("line") == 2);
                }
            }
            assert(has_action);

            var flow = parsed("file:///sf.mmd", "flowchart TD\n    A[Start] --> B[End]\n");
            children = symbol_children(flow);
            assert(children.get_length() == 2);
            assert(children.get_object_element(0).get_string_member("name") == "Start");

            // C4: clean labels, not "<$person> / == Customer"
            var c4 = parsed("file:///sc4.puml", "@startuml\n!include <C4/C4_Container>\n" +
                "Person(customer, \"Customer\", \"A user\")\nSystem_Boundary(b, \"Shop\") {\n" +
                "  Container(web, \"Web App\", \"React\", \"UI\")\n}\n@enduml\n");
            children = symbol_children(c4);
            var names = new Gee.ArrayList<string>();
            for (uint i = 0; i < children.get_length(); i++) {
                names.add(children.get_object_element(i).get_string_member("name"));
            }
            assert(names.contains("Customer"));
            assert(names.contains("Shop"));

            var timing = parsed("file:///st2.puml", "@startuml\nrobust \"Web\" as W\n@0\nW is Idle\n@enduml\n");
            assert(LspProtocol.build_document_symbols(timing).get_array().get_object_element(0)
                   .get_string_member("name") == "Timing Diagram");
            assert(LspProtocol.diagram_type_name(DiagramType.MERMAID_BLOCK) == "Mermaid Block");
            assert(LspProtocol.diagram_type_id(DiagramType.MERMAID_FLOWCHART) == "mermaid_flowchart");
            assert(LspProtocol.format_id(DiagramFormat.PLANTUML) == "plantuml");
        }

        public static void test_hover_elements() {
            var state = parsed("file:///he.puml",
                "@startuml\nclass Foo <<entity>>\nnote right of Foo : persisted\nFoo --> Bar\n@enduml\n");
            string? foo = hover_at(state, "Foo <<");
            assert(foo != null);
            assert(foo.contains("`Foo`"));
            assert(foo.contains("Declared on line 2"));
            assert(foo.contains("<<entity>>"));
            assert(foo.contains("persisted"));
            // A word that is neither keyword nor element still has no hover
            assert(hover_at(state, "persisted") == null);
        }

        // ── UTF-16 positions (LSP counts code units, our strings are UTF-8 bytes) ──

        private static string? hover_value(LspDocumentState state, int line, int character) {
            var node = LspProtocol.build_hover(state, line, character);
            return node == null ? null
                : node.get_object().get_object_member("contents").get_string_member("value");
        }

        public static void test_utf16_offsets() {
            assert(LspProtocol.utf16_length("") == 0);
            assert(LspProtocol.utf16_length("abc") == 3);
            assert(LspProtocol.utf16_length("Ärger") == 5);          // 6 bytes, 5 units
            assert(LspProtocol.utf16_length("a😀b") == 4);           // the emoji is a pair

            assert(LspProtocol.utf16_to_byte_offset("Ärger", 0) == 0);
            assert(LspProtocol.utf16_to_byte_offset("Ärger", 1) == 2);
            assert(LspProtocol.utf16_to_byte_offset("Ärger", 2) == 3);
            assert(LspProtocol.utf16_to_byte_offset("Ärger", 5) == 6);   // past the last char
            assert(LspProtocol.utf16_to_byte_offset("Ärger", 99) == 6);
            assert(LspProtocol.utf16_to_byte_offset("a😀b", 3) == 5);    // after the pair
        }

        // A non-ASCII participant hovers at every column of its name, and a column past
        // the end of the line still has none. Byte offsets used to shift the word (or
        // reject it outright, since is_word_char turned down every byte >= 0x80).
        public static void test_hover_non_ascii_element() {
            var state = parsed("file:///umlaut.puml",
                "@startuml\nparticipant Ärger\nparticipant Bob\nÄrger -> Bob : Grüße\n@enduml\n");
            assert(state.diagram_type == DiagramType.SEQUENCE);

            // "participant " is 12 UTF-16 units; "Ärger" occupies 12..16
            string? on_umlaut = hover_value(state, 1, 12);      // on the "Ä" itself
            assert(on_umlaut != null);
            assert(on_umlaut.contains("`Ärger`"));

            string? inside = hover_value(state, 1, 14);         // inside the word
            assert(inside != null);
            assert(inside.contains("`Ärger`"));

            // 17 UTF-16 units is one past the line's last character: no word there
            assert(LspProtocol.utf16_length("participant Ärger") == 17);
            assert(hover_value(state, 1, 17) == null);
        }

        // Diagnostic ranges are UTF-16 too: char_count() counted code points, so a line
        // with a character outside the BMP ended before its last column.
        public static void test_diagnostic_range_utf16() {
            string src = "@startuml\n!include 😀.iuml\nclass A\n@enduml\n";
            var state = parsed("file:///tmp/gdiagram-lsp-no-such-dir/emoji.puml", src);
            bool found = false;
            foreach (var d in state.diagnostics) {
                if (d.message.contains(".iuml")) {
                    found = true;
                    assert(d.start_line == 1 && d.end_line == 1);
                    // "!include " (9) + the emoji (a surrogate pair: 2) + ".iuml" (5)
                    assert(d.end_char == 16);
                }
            }
            assert(found);
        }

        // A sequence message jumps to the line the parser recorded for it. Searching the
        // source for a line with "-" and both participant names let a note steal the jump.
        public static void test_document_symbols_message_lines() {
            var state = parsed("file:///msg.puml",
                "@startuml\n" +
                "participant Alice\n" +
                "participant Bob\n" +
                "note over Alice, Bob : Alice and Bob talk-about it\n" +
                "Alice -> Bob : real message\n" +
                "@enduml\n");
            assert(state.diagram_type == DiagramType.SEQUENCE);
            var children = symbol_children(state);
            assert(children.get_length() == 3);
            var msg = children.get_object_element(2);
            assert(msg.get_string_member("name").contains("real message"));
            // 0-based: the "Alice -> Bob" line, not the note above it
            assert(msg.get_object_member("range").get_object_member("start")
                      .get_int_member("line") == 4);
        }

        // The root range stops at the document's last line (it used to name one line past
        // EOF), and a child covers its declaration instead of being a zero-width caret.
        public static void test_document_symbols_ranges_are_selectable() {
            string src = "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob : hi\n@enduml\n";
            var state = parsed("file:///ranges.puml", src);
            var root = LspProtocol.build_document_symbols(state).get_array().get_object_element(0);
            var root_end = root.get_object_member("range").get_object_member("end");
            int line_count = src.split("\n").length;    // 6: the trailing "\n" leaves an empty last line
            assert(root_end.get_int_member("line") == line_count - 1);

            var children = root.get_array_member("children");
            assert(children.get_length() == 3);
            for (uint i = 0; i < children.get_length(); i++) {
                var range = children.get_object_element(i).get_object_member("range");
                var start = range.get_object_member("start");
                var end = range.get_object_member("end");
                assert(start.get_int_member("line") == end.get_int_member("line"));
                assert(end.get_int_member("character") > start.get_int_member("character"));
            }
            // Alice's declaration line, in full
            var alice = children.get_object_element(0).get_object_member("range");
            assert(alice.get_object_member("start").get_int_member("line") == 1);
            assert(alice.get_object_member("end").get_int_member("character") ==
                   "participant Alice".length);
        }

        // ── Every symbol must land on real source text ───────────────

        // start line, end line and the width of the range, for a readable failure
        private static string range_text(Json.Object symbol) {
            var range = symbol.get_object_member("range");
            return "%s:%s-%s:%s".printf(
                range.get_object_member("start").get_int_member("line").to_string(),
                range.get_object_member("start").get_int_member("character").to_string(),
                range.get_object_member("end").get_int_member("line").to_string(),
                range.get_object_member("end").get_int_member("character").to_string());
        }

        // A symbol whose range selects nothing sends go-to-symbol to a caret at 0:0
        private static void assert_selectable(Json.Object symbol, string what) {
            var range = symbol.get_object_member("range");
            int64 end_char = range.get_object_member("end").get_int_member("character");
            if (end_char > 0) return;
            printerr("\nFAILED: %s symbol '%s' has the empty range %s\n",
                     what, symbol.get_string_member("name"), range_text(symbol));
            assert_not_reached();
        }

        private static void assert_all_selectable(Json.Array symbols, string what) {
            for (uint i = 0; i < symbols.get_length(); i++) {
                var sym = symbols.get_object_element(i);
                assert_selectable(sym, what);
                if (sym.has_member("children")) {
                    assert_all_selectable(sym.get_array_member("children"), what);
                }
            }
        }

        /**
         * A gantt separator carried no source line at all (a hard-coded 0), so every
         * "-- Name --" got a zero-width range at 0:0: go-to-symbol jumped to line 1 and
         * selected nothing, whatever the separator was.
         */
        public static void test_document_symbols_gantt_separator_line() {
            string src = "@startgantt\n[Design] lasts 5 days\n-- Build --\n[Code] lasts 3 days\n" +
                         "-- Ship --\n[Release] lasts 1 day\n@endgantt\n";
            var children = symbol_children(parsed("file:///sep.puml", src));
            assert(children.get_length() == 3);   // Design, then the two separators

            var build = children.get_object_element(1);
            assert(build.get_string_member("name") == "Build");
            stderr.printf("Build separator range: %s\n", range_text(build));
            // "-- Build --" is the third line (0-based 2) and 11 characters wide
            var build_range = build.get_object_member("range");
            assert(build_range.get_object_member("start").get_int_member("line") == 2);
            assert(build_range.get_object_member("end").get_int_member("line") == 2);
            assert(build_range.get_object_member("end").get_int_member("character") ==
                   "-- Build --".length);
            assert(build.get_object_member("selectionRange")
                        .get_object_member("end").get_int_member("character") ==
                   "-- Build --".length);

            var ship = children.get_object_element(2);
            assert(ship.get_string_member("name") == "Ship");
            assert(ship.get_object_member("range").get_object_member("start")
                       .get_int_member("line") == 4);

            assert_all_selectable(children, "gantt");
        }

        /**
         * Mermaid documentSymbol only ever descended into flowcharts: a sequenceDiagram,
         * classDiagram or stateDiagram-v2 came back as one bare symbol with no children,
         * so the whole outline of those documents was a single unusable entry.
         */
        public static void test_document_symbols_mermaid_types() {
            // sequenceDiagram: the participants, then the messages
            string seq = "sequenceDiagram\n    participant Alice\n    participant Bob\n" +
                         "    Alice->>Bob: Hello\n    Bob-->>Alice: Hi there\n";
            var children = symbol_children(parsed("file:///m.mmd", seq));
            assert(children.get_length() == 4);
            assert(children.get_object_element(0).get_string_member("name") == "Alice");
            assert(children.get_object_element(0).get_object_member("range")
                           .get_object_member("start").get_int_member("line") == 1);
            assert(children.get_object_element(1).get_string_member("name") == "Bob");
            assert(children.get_object_element(2).get_string_member("name") == "Alice -> Bob: Hello");
            assert(children.get_object_element(2).get_object_member("range")
                           .get_object_member("start").get_int_member("line") == 3);
            assert_all_selectable(children, "mermaid sequence");

            // classDiagram: the classes, with their members as children
            string cls = "classDiagram\n    class Animal {\n        +String name\n" +
                         "        +eat()\n    }\n    class Dog\n    Animal <|-- Dog\n";
            children = symbol_children(parsed("file:///c.mmd", cls));
            assert(children.get_length() == 2);
            var animal = children.get_object_element(0);
            assert(animal.get_string_member("name") == "Animal");
            assert(animal.get_object_member("range").get_object_member("start")
                         .get_int_member("line") == 1);
            var members = animal.get_array_member("children");
            assert(members.get_length() == 2);
            // Each member sits on its own line, not lumped onto the class declaration
            assert(members.get_object_element(0).get_object_member("range")
                          .get_object_member("start").get_int_member("line") == 2);
            assert(members.get_object_element(1).get_object_member("range")
                          .get_object_member("start").get_int_member("line") == 3);
            assert(children.get_object_element(1).get_string_member("name") == "Dog");
            assert_all_selectable(children, "mermaid class");

            // stateDiagram-v2: nested states, then the transitions
            string st = "stateDiagram-v2\n    [*] --> Idle\n    Idle --> Running : start\n" +
                        "    state Running {\n        [*] --> Fast\n        Fast --> Slow\n    }\n" +
                        "    Running --> [*]\n";
            children = symbol_children(parsed("file:///s.mmd", st));
            assert(children.get_length() > 2);
            var idle = children.get_object_element(0);
            assert(idle.get_string_member("name") == "Idle");
            var running = children.get_object_element(1);
            assert(running.get_string_member("name") == "Running");
            // Fast and Slow are sub-states of Running, not siblings
            var sub = running.get_array_member("children");
            assert(sub.get_length() == 2);
            assert(sub.get_object_element(0).get_string_member("name") == "Fast");
            assert(sub.get_object_element(1).get_string_member("name") == "Slow");
            // The [*] markers are spelled as the source spells them, on their own lines
            bool saw_start = false;
            for (uint i = 0; i < children.get_length(); i++) {
                if (children.get_object_element(i).get_string_member("name") == "[*] --> Idle") {
                    saw_start = true;
                    assert(children.get_object_element(i).get_object_member("range")
                                   .get_object_member("start").get_int_member("line") == 1);
                }
            }
            assert(saw_start);
            assert_all_selectable(children, "mermaid state");
        }

        public static void test_quiet_json_access() {
            var parser = new Json.Parser();
            try {
                parser.load_from_data("{\"a\": 1, \"b\": \"x\", \"c\": [1], \"d\": {\"e\": true}}");
            } catch (Error e) {
                assert_not_reached();
            }
            var o = LspProtocol.as_object(parser.get_root());
            assert(o != null);
            assert(LspProtocol.string_member(o, "a") == null);
            assert(LspProtocol.string_member(o, "b") == "x");
            assert(LspProtocol.int_member(o, "b", -1) == -1);
            assert(LspProtocol.int_member(o, "a", -1) == 1);
            assert(LspProtocol.object_member(o, "c") == null);
            assert(LspProtocol.array_member(o, "c") != null);
            assert(LspProtocol.object_member(o, "d") != null);
            assert(LspProtocol.string_member(null, "b") == null);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/lsp/initialize_capabilities", LspProtocolTests.test_initialize_capabilities);
        Test.add_func("/lsp/reparse_valid_sequence", LspProtocolTests.test_reparse_valid_sequence);
        Test.add_func("/lsp/reparse_unknown_diagnostic", LspProtocolTests.test_reparse_unknown_produces_diagnostic);
        Test.add_func("/lsp/reparse_mermaid_flowchart", LspProtocolTests.test_reparse_mermaid_flowchart);
        Test.add_func("/lsp/reparse_empty", LspProtocolTests.test_reparse_empty_no_crash);
        Test.add_func("/lsp/completion_plantuml_sequence", LspProtocolTests.test_completion_plantuml_sequence);
        Test.add_func("/lsp/completion_mermaid", LspProtocolTests.test_completion_mermaid);
        Test.add_func("/lsp/document_symbols_sequence", LspProtocolTests.test_document_symbols_sequence);
        Test.add_func("/lsp/document_symbols_empty", LspProtocolTests.test_document_symbols_empty_without_ast);
        Test.add_func("/lsp/hover_keyword", LspProtocolTests.test_hover_keyword);
        Test.add_func("/lsp/hover_non_keyword", LspProtocolTests.test_hover_non_keyword_is_null);
        Test.add_func("/lsp/diagnostics_notification_shape", LspProtocolTests.test_diagnostics_notification_shape);
        Test.add_func("/lsp/diagnostics_notification_empty", LspProtocolTests.test_diagnostics_notification_empty);
        Test.add_func("/lsp/templates", LspProtocolTests.test_templates_non_empty);
        Test.add_func("/lsp/uri_to_path", LspProtocolTests.test_uri_to_path);
        Test.add_func("/lsp/reparse_include_next_to_document",
                      LspProtocolTests.test_reparse_resolves_include_next_to_document);
        Test.add_func("/lsp/completion_timing_gantt", LspProtocolTests.test_completion_timing_and_gantt);
        Test.add_func("/lsp/completion_type_keywords", LspProtocolTests.test_completion_type_keywords);
        Test.add_func("/lsp/completion_hover_c4", LspProtocolTests.test_completion_and_hover_c4);
        Test.add_func("/lsp/hover_new_keywords", LspProtocolTests.test_hover_new_keywords);
        Test.add_func("/lsp/document_symbols_timing_gantt", LspProtocolTests.test_document_symbols_timing_gantt);
        Test.add_func("/lsp/diagnostics_unresolved_include", LspProtocolTests.test_diagnostics_unresolved_include);
        Test.add_func("/lsp/diagnostics_parse_errors", LspProtocolTests.test_diagnostics_parse_errors);
        Test.add_func("/lsp/document_symbols_ranges_types", LspProtocolTests.test_document_symbols_ranges_and_types);
        Test.add_func("/lsp/hover_elements", LspProtocolTests.test_hover_elements);
        Test.add_func("/lsp/utf16_offsets", LspProtocolTests.test_utf16_offsets);
        Test.add_func("/lsp/hover_non_ascii_element", LspProtocolTests.test_hover_non_ascii_element);
        Test.add_func("/lsp/diagnostic_range_utf16", LspProtocolTests.test_diagnostic_range_utf16);
        Test.add_func("/lsp/document_symbols_message_lines",
                      LspProtocolTests.test_document_symbols_message_lines);
        Test.add_func("/lsp/document_symbols_ranges_selectable",
                      LspProtocolTests.test_document_symbols_ranges_are_selectable);
        Test.add_func("/lsp/document_symbols_gantt_separator_line",
                      LspProtocolTests.test_document_symbols_gantt_separator_line);
        Test.add_func("/lsp/document_symbols_mermaid_types",
                      LspProtocolTests.test_document_symbols_mermaid_types);
        Test.add_func("/lsp/quiet_json_access", LspProtocolTests.test_quiet_json_access);

        return Test.run();
    }
}
