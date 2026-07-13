namespace GDiagram {

    /**
     * Helper functions for building LSP JSON responses and notifications.
     */
    public class LspProtocol : Object {

        /**
         * Local file path of a "file://" document URI, percent-decoded
         * ("file:///home/me/My%20Diagrams/a.puml" -> "/home/me/My Diagrams/a.puml").
         * Null for other schemes ("untitled:Untitled-1") and malformed URIs.
         */
        public static string? uri_to_path(string? uri) {
            if (uri == null || !uri.has_prefix("file://")) {
                return null;
            }
            try {
                return Filename.from_uri(uri, null);
            } catch (ConvertError e) {
                return null;
            }
        }

        // ---- Quiet JSON access: null (or the fallback) for a missing member or a wrong type,
        // without the Json-CRITICAL that get_*_member logs ----

        public static Json.Object? as_object(Json.Node? node) {
            return (node != null && node.get_node_type() == Json.NodeType.OBJECT) ? node.get_object() : null;
        }

        public static Json.Object? object_member(Json.Object? obj, string name) {
            return (obj != null && obj.has_member(name)) ? as_object(obj.get_member(name)) : null;
        }

        public static Json.Array? array_member(Json.Object? obj, string name) {
            if (obj == null || !obj.has_member(name)) return null;
            var node = obj.get_member(name);
            return node.get_node_type() == Json.NodeType.ARRAY ? node.get_array() : null;
        }

        public static string? string_member(Json.Object? obj, string name) {
            if (obj == null || !obj.has_member(name)) return null;
            var node = obj.get_member(name);
            if (node.get_node_type() != Json.NodeType.VALUE || node.get_value_type() != typeof(string)) return null;
            return node.get_string();
        }

        public static int64 int_member(Json.Object? obj, string name, int64 fallback) {
            if (obj == null || !obj.has_member(name)) return fallback;
            var node = obj.get_member(name);
            if (node.get_node_type() != Json.NodeType.VALUE || node.get_value_type() != typeof(int64)) return fallback;
            return node.get_int();
        }

        // ---- UTF-16 positions ----
        // LSP positions count UTF-16 code units by default ("positionEncoding" is not
        // negotiated here), while every string in this codebase is UTF-8 bytes. One
        // `character` is one byte only for ASCII; "participant Ärger" already differs.

        /** Length of `text` in UTF-16 code units (an LSP `character` past its last one). */
        public static int utf16_length(string text) {
            int units = 0;
            int index = 0;
            unichar c = 0;
            while (text.get_next_char(ref index, out c)) {
                units += c >= 0x10000 ? 2 : 1;   // outside the BMP: a surrogate pair
            }
            return units;
        }

        /**
         * Byte offset in `line` of the LSP `character` (UTF-16 code units).
         * Past the end of the line: the line's length in bytes.
         */
        public static int utf16_to_byte_offset(string line, int character) {
            if (character <= 0) return 0;
            int units = 0;
            int byte_offset = 0;
            int index = 0;
            unichar c = 0;
            while (units < character && line.get_next_char(ref index, out c)) {
                byte_offset = index;
                units += c >= 0x10000 ? 2 : 1;
            }
            return byte_offset;
        }

        /** "plantuml", "mermaid" or "unknown" */
        public static string format_id(DiagramFormat format) {
            switch (format) {
                case DiagramFormat.PLANTUML: return "plantuml";
                case DiagramFormat.MERMAID:  return "mermaid";
                default:                     return "unknown";
            }
        }

        /** The type as a lower-case id: "sequence", "mermaid_flowchart", "unknown" */
        public static string diagram_type_id(DiagramType dtype) {
            string nick = dtype.to_string();
            if (nick.has_prefix("GDIAGRAM_DIAGRAM_TYPE_")) nick = nick.substring("GDIAGRAM_DIAGRAM_TYPE_".length);
            return nick.down();
        }

        /**
         * Build the response to the initialize request.
         */
        public static Json.Node build_initialize_result() {
            var b = new Json.Builder();
            b.begin_object();

            // capabilities
            b.set_member_name("capabilities");
            b.begin_object();

            // textDocumentSync = Full (1)
            b.set_member_name("textDocumentSync");
            b.begin_object();
            b.set_member_name("openClose"); b.add_boolean_value(true);
            b.set_member_name("change"); b.add_int_value(1); // Full
            b.end_object();

            // completionProvider
            b.set_member_name("completionProvider");
            b.begin_object();
            b.set_member_name("triggerCharacters");
            b.begin_array();
            b.add_string_value("@");
            b.add_string_value("-");
            b.add_string_value(":");
            b.end_array();
            b.end_object();

            // hoverProvider
            b.set_member_name("hoverProvider"); b.add_boolean_value(true);

            // documentSymbolProvider
            b.set_member_name("documentSymbolProvider"); b.add_boolean_value(true);

            b.end_object(); // capabilities

            // serverInfo
            b.set_member_name("serverInfo");
            b.begin_object();
            b.set_member_name("name"); b.add_string_value("gdiagram-lsp");
            // Same reasoning as `gdiagram --version`: the hard-coded release version cannot
            // tell two builds apart, so the editor sees the commit too.
            b.set_member_name("version");
            b.add_string_value("%s (%s, %s)".printf(VERSION, BUILD_ID, BUILD_DATE));
            b.end_object();

            b.end_object();
            return b.get_root();
        }

        /**
         * Build a publishDiagnostics notification.
         */
        public static string build_diagnostics_notification(string uri,
                                                            Gee.ArrayList<LspDiagnostic> diagnostics) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("method"); b.add_string_value("textDocument/publishDiagnostics");
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.set_member_name("diagnostics");
            b.begin_array();
            foreach (var diag in diagnostics) {
                b.begin_object();
                b.set_member_name("range");
                b.begin_object();
                b.set_member_name("start");
                b.begin_object();
                b.set_member_name("line"); b.add_int_value(diag.start_line);
                b.set_member_name("character"); b.add_int_value(diag.start_char);
                b.end_object();
                b.set_member_name("end");
                b.begin_object();
                b.set_member_name("line"); b.add_int_value(diag.end_line);
                b.set_member_name("character"); b.add_int_value(diag.end_char);
                b.end_object();
                b.end_object();
                b.set_member_name("severity"); b.add_int_value(diag.severity);
                b.set_member_name("source"); b.add_string_value(diag.source);
                b.set_member_name("message"); b.add_string_value(diag.message);
                b.end_object();
            }
            b.end_array();
            b.end_object();
            b.end_object();

            var gen = new Json.Generator();
            gen.root = b.get_root();
            return gen.to_data(null);
        }

        /**
         * Build completion items for the given diagram type: the format's general
         * keywords, the detected type's statements and, in PlantUML documents that
         * use the C4 stdlib, the C4 macros (LspKeywords). Items with an LSP snippet
         * carry insertText; every item documents itself in markdown.
         */
        public static Json.Node build_completion_items(DiagramFormat format, DiagramType dtype,
                                                       string? content = null) {
            var b = new Json.Builder();
            b.begin_array();
            var seen = new Gee.HashSet<string>();
            foreach (var kw in LspKeywords.for_document(format, dtype, content)) {
                // A type may repeat a general keyword ("note"): the first one wins
                if (!seen.add(kw.label)) continue;
                b.begin_object();
                b.set_member_name("label"); b.add_string_value(kw.label);
                b.set_member_name("kind"); b.add_int_value(kw.kind);
                b.set_member_name("detail"); b.add_string_value(kw.detail);
                b.set_member_name("documentation");
                b.begin_object();
                b.set_member_name("kind"); b.add_string_value("markdown");
                b.set_member_name("value"); b.add_string_value(kw.hover_markdown());
                b.end_object();
                if (kw.insert_text != null) {
                    b.set_member_name("insertText"); b.add_string_value(kw.insert_text);
                    b.set_member_name("insertTextFormat"); b.add_int_value(2); // Snippet
                }
                b.end_object();
            }
            b.end_array();
            return b.get_root();
        }

        /**
         * Build document symbols from parsed AST.
         * Returns a JSON array of DocumentSymbol objects.
         */
        public static Json.Node build_document_symbols(LspDocumentState state) {
            var b = new Json.Builder();
            b.begin_array();

            // build_line_range needs each declaration line's width to give a symbol a
            // range go-to-symbol can actually select. Held for this call only (the
            // server handles every request on its single main loop).
            symbol_lines = state.content.split("\n");

            if (state.parsed_ast != null) {
                // Top-level symbol for the diagram type
                b.begin_object();
                b.set_member_name("name"); b.add_string_value(diagram_type_name(state.diagram_type));
                b.set_member_name("kind"); b.add_int_value(2); // Module
                b.set_member_name("range");
                build_full_range(b, state.content);
                b.set_member_name("selectionRange");
                build_zero_range(b);

                // Add children based on diagram type
                b.set_member_name("children");
                b.begin_array();
                add_type_specific_symbols(b, state);
                b.end_array();

                b.end_object();
            }

            b.end_array();
            symbol_lines = {};
            return b.get_root();
        }

        // Source lines of the document build_document_symbols is working on (see there)
        private static string[] symbol_lines = {};

        private static void add_type_specific_symbols(Json.Builder b, LspDocumentState state) {
            switch (state.diagram_type) {
                case DiagramType.SEQUENCE:
                    add_sequence_symbols(b, (SequenceDiagram) state.parsed_ast);
                    break;
                case DiagramType.CLASS:
                    add_class_symbols(b, (ClassDiagram) state.parsed_ast);
                    break;
                case DiagramType.TIMING:
                    add_timing_symbols(b, (TimingDiagram) state.parsed_ast);
                    break;
                case DiagramType.GANTT:
                    add_gantt_symbols(b, (PumlGanttDiagram) state.parsed_ast);
                    break;
                case DiagramType.STATE:
                    foreach (var s in ((StateDiagram) state.parsed_ast).states) {
                        add_state_symbol(b, s);
                    }
                    break;
                case DiagramType.COMPONENT:
                    add_component_symbols(b, (ComponentDiagram) state.parsed_ast);
                    break;
                case DiagramType.ACTIVITY:
                    add_activity_symbols(b, (ActivityDiagram) state.parsed_ast);
                    break;
                case DiagramType.MERMAID_FLOWCHART:
                    foreach (var node in ((MermaidFlowchart) state.parsed_ast).nodes) {
                        string text = ElementInspector.display_label(node.text);
                        add_symbol(b, text.length > 0 ? text : node.id, 12, node.source_line, node.id); // Function
                    }
                    break;
                case DiagramType.MERMAID_SEQUENCE:
                    add_mermaid_sequence_symbols(b, (MermaidSequenceDiagram) state.parsed_ast);
                    break;
                case DiagramType.MERMAID_CLASS:
                    add_mermaid_class_symbols(b, (MermaidClassDiagram) state.parsed_ast);
                    break;
                case DiagramType.MERMAID_STATE:
                    add_mermaid_state_symbols(b, (MermaidStateDiagram) state.parsed_ast);
                    break;
                default:
                    // For other types, add a simple "content" symbol
                    break;
            }
        }

        // ---- Mermaid document symbols ----
        // sequenceDiagram, classDiagram and stateDiagram-v2 used to return the bare
        // top-level symbol with no children at all, so the outline of every Mermaid
        // document but a flowchart was a single unusable entry.

        private static void add_mermaid_sequence_symbols(Json.Builder b, MermaidSequenceDiagram diagram) {
            foreach (var actor in diagram.actors) {
                add_symbol(b, actor.get_display_name(), 5, actor.source_line,      // Class
                           actor.is_participant ? "participant" : "actor");
            }
            foreach (var m in diagram.messages) {
                string label = "%s -> %s".printf(m.from.get_display_name(), m.to.get_display_name());
                if (m.text != null && m.text.length > 0) label += ": " + m.text;
                add_symbol(b, label, 6, m.source_line);                            // Method
            }
        }

        private static void add_mermaid_class_symbols(Json.Builder b, MermaidClassDiagram diagram) {
            foreach (var cls in diagram.classes) {
                begin_symbol(b, cls.label ?? cls.name, 5, cls.source_line, cls.stereotype); // Class
                if (cls.members.size > 0) {
                    b.set_member_name("children");
                    b.begin_array();
                    foreach (var member in cls.members) {
                        // MermaidClassMember carries no line of its own: find the line the
                        // member was written on, from the class declaration downwards.
                        int line = find_source_line(cls.source_line, { member.name });
                        add_symbol(b, member.display_text ?? member.name,
                                   member.is_method ? 6 : 8,                       // Method / Field
                                   line > 0 ? line : cls.source_line);
                    }
                    b.end_array();
                }
                b.end_object();
            }
        }

        private static void add_mermaid_state_symbols(Json.Builder b, MermaidStateDiagram diagram) {
            foreach (var s in diagram.children_of(null)) {
                add_mermaid_state_symbol(b, diagram, s);
            }
            // MermaidTransition carries no line of its own; locate the arrow that wrote it
            foreach (var t in diagram.transitions) {
                string from = mermaid_state_token(t.from);
                string to = mermaid_state_token(t.to);
                string label = "%s --> %s".printf(from, to);
                if (t.label != null && t.label.length > 0) label += ": " + t.label;
                add_symbol(b, label, 6, find_source_line(1, { from, "-->", to }));  // Method
            }
        }

        // A state as the source spells it. The parser gives the [*] markers synthesized
        // ids ("[*]_start", "[*]_end@Running") that appear nowhere in the document, so
        // both the symbol name and the line search have to use "[*]" itself.
        private static string mermaid_state_token(MermaidState s) {
            return s.id.has_prefix("[*]") ? "[*]" : s.id;
        }

        private static void add_mermaid_state_symbol(Json.Builder b, MermaidStateDiagram diagram,
                                                     MermaidState s) {
            if (s.state_type != MermaidStateType.NORMAL) return;   // [*] markers, history, forks
            string name = (s.description != null && s.description.length > 0) ? s.description : s.id;
            begin_symbol(b, name, 5, s.source_line, s.id != name ? s.id : null);   // Class
            var children = diagram.children_of(s.id);
            if (children.size > 0) {
                b.set_member_name("children");
                b.begin_array();
                foreach (var child in children) {
                    add_mermaid_state_symbol(b, diagram, child);
                }
                b.end_array();
            }
            b.end_object();
        }

        // 1-based line of the first source line at or after `from_line` (1-based, clamped
        // to 1) holding every one of `needles` in order, or 0 when there is none. For AST
        // nodes that record no line of their own — a zero range at 0:0 would send
        // go-to-symbol to line 1 with nothing selected.
        private static int find_source_line(int from_line, string[] needles) {
            if (needles.length == 0) return 0;
            for (int i = int.max(0, from_line - 1); i < symbol_lines.length; i++) {
                string line = symbol_lines[i];
                int at = 0;
                bool all = true;
                foreach (string needle in needles) {
                    int found = line.index_of(needle, at);
                    if (found < 0) { all = false; break; }
                    at = found + needle.length;
                }
                if (all) return i + 1;
            }
            return 0;
        }

        private static void add_sequence_symbols(Json.Builder b, SequenceDiagram diagram) {
            foreach (var p in diagram.participants) {
                string name = ElementInspector.display_label(p.display_label ?? p.name);
                add_symbol(b, name.length > 0 ? name : p.name, 5, p.source_line); // Class
            }
            // The parser records each message's statement line. Searching the source for
            // a line holding "-" and both participant names instead matched anything that
            // mentioned them ("note over A, B : A and B talk-about it"), which stole the
            // jump from the real message.
            foreach (var m in diagram.messages) {
                string msg_label = "%s -> %s: %s".printf(m.from.name, m.to.name, m.label ?? "");
                add_symbol(b, msg_label, 6, m.source_line); // Method
            }
        }

        // A symbol on its 1-based source line (0 = unknown: a zero range); `children`
        // is left open for the caller when true
        private static void begin_symbol(Json.Builder b, string name, int kind, int source_line,
                                         string? detail = null) {
            b.begin_object();
            b.set_member_name("name"); b.add_string_value(name.length > 0 ? name : "(unnamed)");
            if (detail != null) {
                b.set_member_name("detail"); b.add_string_value(detail);
            }
            b.set_member_name("kind"); b.add_int_value(kind);
            b.set_member_name("range"); build_line_range(b, source_line);
            b.set_member_name("selectionRange"); build_line_range(b, source_line);
        }

        private static void add_symbol(Json.Builder b, string name, int kind, int source_line, string? detail = null) {
            begin_symbol(b, name, kind, source_line, detail);
            b.end_object();
        }

        // The whole declaration line, so go-to-symbol selects something instead of
        // collapsing to a caret. An unknown line (0) still gets a zero range at 0:0.
        private static void build_line_range(Json.Builder b, int source_line) {
            int line = int.max(0, source_line - 1);
            int end_char = 0;
            if (source_line > 0 && line < symbol_lines.length) {
                end_char = utf16_length(symbol_lines[line].replace("\r", ""));
            }
            b.begin_object();
            b.set_member_name("start");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(line);
            b.set_member_name("character"); b.add_int_value(0);
            b.end_object();
            b.set_member_name("end");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(line);
            b.set_member_name("character"); b.add_int_value(end_char);
            b.end_object();
            b.end_object();
        }

        // Timing: one symbol per participant (lane), then the messages
        private static void add_timing_symbols(Json.Builder b, TimingDiagram diagram) {
            foreach (var sig in diagram.signals) {
                string kind_name = sig.signal_type.to_string().down();
                int cut = kind_name.last_index_of("_");
                if (cut >= 0) kind_name = kind_name.substring(cut + 1);
                add_symbol(b, ElementInspector.display_label(sig.label), 13, sig.source_line, kind_name); // Variable
            }
            foreach (var msg in diagram.messages) {
                string name = "%s -> %s".printf(msg.from_signal, msg.to_signal);
                if (msg.label != null && msg.label.length > 0) name += ": " + msg.label;
                add_symbol(b, name, 24, msg.source_line, "@%g".printf(msg.from_time)); // Event
            }
        }

        // Gantt: separators hold the tasks and milestones below them
        private static void add_gantt_symbols(Json.Builder b, PumlGanttDiagram diagram) {
            bool open_separator = false;
            int separator_scan = 1;   // PumlGanttRow records no line; see separator_line()
            foreach (var row in diagram.rows) {
                if (row.separator != null) {
                    if (open_separator) {
                        b.end_array();
                        b.end_object();
                    }
                    begin_symbol(b, row.separator, 3,
                                 separator_line(row.separator, ref separator_scan),
                                 "separator"); // Namespace
                    b.set_member_name("children");
                    b.begin_array();
                    open_separator = true;
                    continue;
                }
                var task = row.task;
                if (task == null) continue;
                if (task.is_milestone) {
                    add_symbol(b, task.name, 24, task.source_line, "milestone"); // Event
                } else {
                    add_symbol(b, task.name, 12, task.source_line,
                               task.duration_days == 1 ? "1 day" : "%d days".printf(task.duration_days)); // Function
                }
            }
            if (open_separator) {
                b.end_array();
                b.end_object();
            }
        }

        /**
         * 1-based line of the "-- text --" a gantt separator came from, or 0.
         *
         * PumlGanttRow keeps only the separator's text, so every separator used to get a
         * zero range at 0:0: go-to-symbol jumped to line 1 and selected nothing. `scan`
         * carries the search forward across calls, so repeated separator names keep the
         * order the parser saw them in.
         */
        private static int separator_line(string text, ref int scan) {
            for (int i = int.max(0, scan - 1); i < symbol_lines.length; i++) {
                string trimmed = symbol_lines[i].strip();
                if (trimmed.length < 4 || !trimmed.has_prefix("--") || !trimmed.has_suffix("--")) continue;
                if (trimmed.substring(2, trimmed.length - 4).strip() != text) continue;
                scan = i + 2;
                return i + 1;
            }
            return 0;
        }

        private static void add_state_symbol(Json.Builder b, State state) {
            if (state.state_type == StateType.INITIAL || state.state_type == StateType.FINAL) return;
            begin_symbol(b, state.label ?? state.id, 5, state.source_line, state.stereotype); // Class
            if (state.nested_states.size > 0) {
                b.set_member_name("children");
                b.begin_array();
                foreach (var nested in state.nested_states) {
                    add_state_symbol(b, nested);
                }
                b.end_array();
            }
            b.end_object();
        }

        private static void add_component_symbols(Json.Builder b, ComponentDiagram diagram) {
            var nested = new Gee.HashSet<Component>();
            foreach (var comp in diagram.components) {
                foreach (var child in comp.children) nested.add(child);
            }
            foreach (var comp in diagram.components) {
                if (!nested.contains(comp)) add_component_symbol(b, comp);
            }
        }

        private static void add_component_symbol(Json.Builder b, Component comp) {
            // C4 labels carry sprites and creole ("<$person>\\n== Customer"): the first plain line
            string name = ElementInspector.display_label(comp.label ?? comp.id);
            begin_symbol(b, name.length > 0 ? name : comp.id, comp.is_container ? 3 : 2, comp.source_line,
                         comp.id); // Namespace / Module
            if (comp.children.size > 0) {
                b.set_member_name("children");
                b.begin_array();
                foreach (var child in comp.children) {
                    add_component_symbol(b, child);
                }
                b.end_array();
            }
            b.end_object();
        }

        private static void add_class_symbols(Json.Builder b, ClassDiagram diagram) {
            foreach (var cls in diagram.classes) {
                add_symbol(b, cls.name, 5, cls.source_line); // Class
            }
        }

        // Activity: actions (by their text) and the start/stop points
        private static void add_activity_symbols(Json.Builder b, ActivityDiagram diagram) {
            foreach (var node in diagram.nodes) {
                switch (node.node_type) {
                    case ActivityNodeType.ACTION: {
                        string text = ElementInspector.display_label(node.label ?? "");
                        if (text.length > 0) add_symbol(b, text, 12, node.source_line); // Function
                        break;
                    }
                    case ActivityNodeType.START:
                        add_symbol(b, "start", 24, node.source_line); // Event
                        break;
                    case ActivityNodeType.STOP:
                    case ActivityNodeType.END:
                        add_symbol(b, node.node_type == ActivityNodeType.STOP ? "stop" : "end", 24, node.source_line);
                        break;
                    default:
                        break;
                }
            }
        }

        /**
         * Build hover information for a position.
         */
        public static Json.Node? build_hover(LspDocumentState state, int line, int character) {
            // Find the word at the given position
            string[] lines = state.content.split("\n");
            if (line >= lines.length) return null;

            string current_line = lines[line];
            // `character` is a UTF-16 code unit index; extract_word_at works in bytes
            int offset = utf16_to_byte_offset(current_line, character);
            if (offset >= current_line.length) return null;

            // Extract word at position
            string word = extract_word_at(current_line, offset);
            if (word.length == 0) return null;

            // Build hover content
            string? hover_text = get_hover_for_word(word, state);
            if (hover_text == null) return null;

            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("contents");
            b.begin_object();
            b.set_member_name("kind"); b.add_string_value("markdown");
            b.set_member_name("value"); b.add_string_value(hover_text);
            b.end_object();
            b.end_object();
            return b.get_root();
        }

        private static string extract_word_at(string line, int pos) {
            if (pos >= line.length) return "";

            int start = pos;
            int end = pos;

            while (start > 0 && is_word_char(line[start - 1])) {
                start--;
            }
            while (end < line.length && is_word_char(line[end])) {
                end++;
            }

            if (start == end) return "";
            return line.substring(start, end - start);
        }

        private static bool is_word_char(char c) {
            // Every byte of a multi-byte UTF-8 character belongs to the word: rejecting
            // them cut "Ärger" down to "rger", so no element under it ever hovered.
            // Walking back over them always lands on the lead byte, a valid boundary.
            if (((uint8) c) >= 0x80) return true;
            return c.isalnum() || c == '_' || c == '@' || c == '-';
        }

        private static string? get_hover_for_word(string word, LspDocumentState state) {
            var kw = LspKeywords.lookup(word, state.format, state.diagram_type, state.content);
            if (kw != null) return kw.hover_markdown();
            return element_hover(word, state);
        }

        // An element of the diagram (class, participant, state, component, ...): its kind,
        // label, declaration line, stereotype and notes, as the properties panel reads them
        private static string? element_hover(string word, LspDocumentState state) {
            if (state.parsed_ast == null || !ElementInspector.is_covered(state.diagram_type)) return null;
            var info = ElementInspector.inspect(state.diagram_type, state.parsed_ast, word, 0, state.content);
            if (info == null || info.synthetic_id) return null;
            var sb = new StringBuilder();
            sb.append("**%s** `%s`".printf(info.kind, info.id));
            string label = info.label != null ? ElementInspector.display_label(info.label) : "";
            if (label.length > 0 && label != info.id) sb.append(" — %s".printf(label));
            if (info.stereotype != null) sb.append("\n\nStereotype: `<<%s>>`".printf(info.stereotype));
            if (info.line > 0) {
                sb.append("\n\n%s line %d".printf(info.declared ? "Declared on" : "First used on", info.line));
            }
            if (info.read_only_reason != null) sb.append("\n\n_%s_".printf(info.read_only_reason));
            if (info.note != null) sb.append("\n\nNote: %s".printf(info.note.strip()));
            return sb.str;
        }

        /**
         * Build a list of available diagram templates.
         */
        public static Json.Node build_templates_list() {
            var b = new Json.Builder();
            b.begin_array();

            // Mermaid templates
            string[] mermaid_types = {
                "flowchart", "sequence", "state", "class", "er",
                "gantt", "pie", "journey", "gitGraph", "mindmap",
                "timeline", "quadrant", "xychart", "kanban"
            };
            foreach (var t in mermaid_types) {
                b.begin_object();
                b.set_member_name("name"); b.add_string_value("mermaid-%s".printf(t));
                b.set_member_name("format"); b.add_string_value("mermaid");
                b.set_member_name("type"); b.add_string_value(t);
                b.end_object();
            }

            // PlantUML templates
            string[] plantuml_types = {
                "sequence", "class", "activity", "usecase", "state",
                "component", "object", "deployment", "er", "mindmap",
                "gantt", "json", "yaml", "timing"
            };
            foreach (var t in plantuml_types) {
                b.begin_object();
                b.set_member_name("name"); b.add_string_value("plantuml-%s".printf(t));
                b.set_member_name("format"); b.add_string_value("plantuml");
                b.set_member_name("type"); b.add_string_value(t);
                b.end_object();
            }

            b.end_array();
            return b.get_root();
        }

        // --- Utility helpers ---

        public static string diagram_type_name(DiagramType dtype) {
            switch (dtype) {
                case DiagramType.SEQUENCE: return "Sequence Diagram";
                case DiagramType.CLASS: return "Class Diagram";
                case DiagramType.ACTIVITY: return "Activity Diagram";
                case DiagramType.USECASE: return "Use Case Diagram";
                case DiagramType.STATE: return "State Diagram";
                case DiagramType.COMPONENT: return "Component Diagram";
                case DiagramType.OBJECT: return "Object Diagram";
                case DiagramType.ER_DIAGRAM: return "ER Diagram";
                case DiagramType.MINDMAP: return "Mind Map";
                case DiagramType.GANTT: return "Gantt Chart";
                case DiagramType.TIMING: return "Timing Diagram";
                case DiagramType.MERMAID_FLOWCHART: return "Mermaid Flowchart";
                case DiagramType.MERMAID_SEQUENCE: return "Mermaid Sequence";
                case DiagramType.MERMAID_STATE: return "Mermaid State";
                case DiagramType.MERMAID_CLASS: return "Mermaid Class";
                case DiagramType.MERMAID_ER: return "Mermaid ER";
                case DiagramType.MERMAID_GANTT: return "Mermaid Gantt";
                case DiagramType.MERMAID_PIE: return "Mermaid Pie";
                default: {
                    // "mermaid_block" -> "Mermaid Block"
                    var sb = new StringBuilder();
                    foreach (string word in diagram_type_id(dtype).split("_")) {
                        if (word.length == 0) continue;
                        if (sb.len > 0) sb.append_c(' ');
                        sb.append(word.substring(0, 1).up() + word.substring(1));
                    }
                    return sb.str;
                }
            }
        }

        // The document, from 0:0 to the end of its last line. `line_count` as the end
        // line pointed one line past EOF, a range no client can resolve.
        private static void build_full_range(Json.Builder b, string content) {
            string[] lines = content.split("\n");
            int last_line = int.max(0, lines.length - 1);
            int end_char = utf16_length(lines[last_line].replace("\r", ""));
            b.begin_object();
            b.set_member_name("start");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(0);
            b.set_member_name("character"); b.add_int_value(0);
            b.end_object();
            b.set_member_name("end");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(last_line);
            b.set_member_name("character"); b.add_int_value(end_char);
            b.end_object();
            b.end_object();
        }

        private static void build_zero_range(Json.Builder b) {
            b.begin_object();
            b.set_member_name("start");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(0);
            b.set_member_name("character"); b.add_int_value(0);
            b.end_object();
            b.set_member_name("end");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(0);
            b.set_member_name("character"); b.add_int_value(0);
            b.end_object();
            b.end_object();
        }
    }
}
