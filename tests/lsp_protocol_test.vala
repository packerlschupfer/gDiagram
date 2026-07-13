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
            // Char 13 falls inside "Alice", which is not a keyword.
            var node = LspProtocol.build_hover(state, 1, 13);
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

        return Test.run();
    }
}
