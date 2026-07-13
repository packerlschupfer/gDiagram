namespace GDiagram {

    /**
     * Helper functions for building LSP JSON responses and notifications.
     */
    public class LspProtocol : Object {

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
            b.set_member_name("version"); b.add_string_value("0.1.0");
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
         * Build completion items for the given diagram type.
         */
        public static Json.Node build_completion_items(DiagramFormat format, DiagramType dtype) {
            var b = new Json.Builder();
            b.begin_array();

            if (format == DiagramFormat.MERMAID) {
                add_completions_mermaid(b);
            } else {
                add_completions_plantuml_general(b);

                switch (dtype) {
                    case DiagramType.SEQUENCE:
                        add_completions_plantuml_sequence(b);
                        break;
                    case DiagramType.CLASS:
                        add_completions_plantuml_class(b);
                        break;
                    case DiagramType.ACTIVITY:
                        add_completions_plantuml_activity(b);
                        break;
                    default:
                        break;
                }
            }

            b.end_array();
            return b.get_root();
        }

        private static void add_completion_item(Json.Builder b, string label, int kind, string? detail = null) {
            b.begin_object();
            b.set_member_name("label"); b.add_string_value(label);
            b.set_member_name("kind"); b.add_int_value(kind); // 14 = Keyword
            if (detail != null) {
                b.set_member_name("detail"); b.add_string_value(detail);
            }
            b.end_object();
        }

        private static void add_completions_plantuml_general(Json.Builder b) {
            string[] keywords = {
                "@startuml", "@enduml", "participant", "actor", "class", "interface",
                "state", "component", "package", "node", "database", "entity",
                "usecase", "skinparam", "title", "note", "legend", "header", "footer"
            };
            foreach (var kw in keywords) {
                add_completion_item(b, kw, 14, "PlantUML keyword");
            }
        }

        private static void add_completions_plantuml_sequence(Json.Builder b) {
            string[] keywords = {
                "->", "-->", "<-", "<--", "->>",
                "activate", "deactivate", "return",
                "alt", "else", "loop", "opt", "par", "critical",
                "group", "ref", "delay", "|||", "==", "||"
            };
            foreach (var kw in keywords) {
                add_completion_item(b, kw, 14, "Sequence diagram");
            }
        }

        private static void add_completions_plantuml_class(Json.Builder b) {
            string[] keywords = {
                "extends", "implements", "abstract", "enum",
                "+", "-", "#", "~", "{field}", "{method}"
            };
            foreach (var kw in keywords) {
                add_completion_item(b, kw, 14, "Class diagram");
            }
        }

        private static void add_completions_plantuml_activity(Json.Builder b) {
            string[] keywords = {
                "start", "stop", ":action;",
                "if", "then", "else", "endif",
                "while", "endwhile",
                "fork", "end fork",
                "switch", "case", "endswitch", "partition"
            };
            foreach (var kw in keywords) {
                add_completion_item(b, kw, 14, "Activity diagram");
            }
        }

        private static void add_completions_mermaid(Json.Builder b) {
            string[] keywords = {
                "flowchart", "sequenceDiagram", "stateDiagram-v2", "classDiagram",
                "erDiagram", "gantt", "pie", "journey", "gitGraph", "mindmap",
                "timeline", "quadrantChart", "xychart-beta", "kanban",
                "sankey-beta", "requirementDiagram", "block-beta",
                "packet-beta", "C4Context", "architecture-beta",
                "zenuml", "radar-beta", "treemap-beta"
            };
            foreach (var kw in keywords) {
                add_completion_item(b, kw, 14, "Mermaid diagram type");
            }
        }

        /**
         * Build document symbols from parsed AST.
         * Returns a JSON array of DocumentSymbol objects.
         */
        public static Json.Node build_document_symbols(LspDocumentState state) {
            var b = new Json.Builder();
            b.begin_array();

            if (state.parsed_ast != null) {
                // Top-level symbol for the diagram type
                b.begin_object();
                b.set_member_name("name"); b.add_string_value(get_diagram_type_name(state.diagram_type));
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
            return b.get_root();
        }

        private static void add_type_specific_symbols(Json.Builder b, LspDocumentState state) {
            switch (state.diagram_type) {
                case DiagramType.SEQUENCE:
                    add_sequence_symbols(b, (SequenceDiagram) state.parsed_ast);
                    break;
                case DiagramType.CLASS:
                    add_class_symbols(b, (ClassDiagram) state.parsed_ast);
                    break;
                default:
                    // For other types, add a simple "content" symbol
                    break;
            }
        }

        private static void add_sequence_symbols(Json.Builder b, SequenceDiagram diagram) {
            // Add participants
            foreach (var p in diagram.participants) {
                b.begin_object();
                b.set_member_name("name"); b.add_string_value(p.display_label ?? p.name);
                b.set_member_name("kind"); b.add_int_value(5); // Class
                b.set_member_name("range"); build_zero_range(b);
                b.set_member_name("selectionRange"); build_zero_range(b);
                b.end_object();
            }
            // Add messages
            foreach (var m in diagram.messages) {
                b.begin_object();
                string msg_label = "%s -> %s: %s".printf(m.from.name, m.to.name, m.label ?? "");
                b.set_member_name("name"); b.add_string_value(msg_label);
                b.set_member_name("kind"); b.add_int_value(6); // Method
                b.set_member_name("range"); build_zero_range(b);
                b.set_member_name("selectionRange"); build_zero_range(b);
                b.end_object();
            }
        }

        private static void add_class_symbols(Json.Builder b, ClassDiagram diagram) {
            foreach (var cls in diagram.classes) {
                b.begin_object();
                b.set_member_name("name"); b.add_string_value(cls.name);
                b.set_member_name("kind"); b.add_int_value(5); // Class
                b.set_member_name("range"); build_zero_range(b);
                b.set_member_name("selectionRange"); build_zero_range(b);
                b.end_object();
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
            if (character >= current_line.length) return null;

            // Extract word at position
            string word = extract_word_at(current_line, character);
            if (word.length == 0) return null;

            // Build hover content
            string? hover_text = get_hover_for_word(word, state.format, state.diagram_type);
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
            return c.isalnum() || c == '_' || c == '@' || c == '-';
        }

        private static string? get_hover_for_word(string word, DiagramFormat format, DiagramType dtype) {
            string lower = word.down();

            // PlantUML keywords
            if (format == DiagramFormat.PLANTUML) {
                switch (lower) {
                    case "@startuml": return "**@startuml** - Begin a PlantUML diagram";
                    case "@enduml": return "**@enduml** - End a PlantUML diagram";
                    case "participant": return "**participant** - Declare a sequence diagram participant";
                    case "actor": return "**actor** - Declare an actor (stick figure)";
                    case "class": return "**class** - Declare a class in a class diagram";
                    case "interface": return "**interface** - Declare an interface";
                    case "abstract": return "**abstract** - Declare an abstract class";
                    case "enum": return "**enum** - Declare an enumeration";
                    case "state": return "**state** - Declare a state in a state diagram";
                    case "component": return "**component** - Declare a component";
                    case "package": return "**package** - Group elements in a package";
                    case "node": return "**node** - Declare a deployment node";
                    case "database": return "**database** - Declare a database element";
                    case "entity": return "**entity** - Declare an entity";
                    case "usecase": return "**usecase** - Declare a use case";
                    case "skinparam": return "**skinparam** - Set visual parameters";
                    case "title": return "**title** - Set diagram title";
                    case "note": return "**note** - Add a note";
                    case "start": return "**start** - Activity diagram start node";
                    case "stop": return "**stop** - Activity diagram stop node";
                    case "if": return "**if** - Begin conditional branch";
                    case "endif": return "**endif** - End conditional branch";
                    case "while": return "**while** - Begin while loop";
                    case "endwhile": return "**endwhile** - End while loop";
                    case "fork": return "**fork** - Begin parallel fork";
                    case "activate": return "**activate** - Activate a participant lifeline";
                    case "deactivate": return "**deactivate** - Deactivate a participant lifeline";
                    default: break;
                }
            }

            // Mermaid keywords
            if (format == DiagramFormat.MERMAID) {
                switch (lower) {
                    case "flowchart": return "**flowchart** - Mermaid flowchart/graph diagram";
                    case "sequencediagram": return "**sequenceDiagram** - Mermaid sequence diagram";
                    case "statediagram-v2": return "**stateDiagram-v2** - Mermaid state diagram";
                    case "classdiagram": return "**classDiagram** - Mermaid class diagram";
                    case "erdiagram": return "**erDiagram** - Mermaid ER diagram";
                    case "gantt": return "**gantt** - Mermaid Gantt chart";
                    case "pie": return "**pie** - Mermaid pie chart";
                    case "journey": return "**journey** - Mermaid user journey map";
                    case "gitgraph": return "**gitGraph** - Mermaid git graph";
                    case "mindmap": return "**mindmap** - Mermaid mind map";
                    case "timeline": return "**timeline** - Mermaid timeline";
                    default: break;
                }
            }

            return null;
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

        private static string get_diagram_type_name(DiagramType dtype) {
            switch (dtype) {
                case DiagramType.SEQUENCE: return "Sequence Diagram";
                case DiagramType.CLASS: return "Class Diagram";
                case DiagramType.ACTIVITY: return "Activity Diagram";
                case DiagramType.USECASE: return "Use Case Diagram";
                case DiagramType.STATE: return "State Diagram";
                case DiagramType.COMPONENT: return "Component Diagram";
                case DiagramType.OBJECT: return "Object Diagram";
                case DiagramType.DEPLOYMENT: return "Deployment Diagram";
                case DiagramType.ER_DIAGRAM: return "ER Diagram";
                case DiagramType.MINDMAP: return "Mind Map";
                case DiagramType.GANTT: return "Gantt Chart";
                case DiagramType.MERMAID_FLOWCHART: return "Mermaid Flowchart";
                case DiagramType.MERMAID_SEQUENCE: return "Mermaid Sequence";
                case DiagramType.MERMAID_STATE: return "Mermaid State";
                case DiagramType.MERMAID_CLASS: return "Mermaid Class";
                case DiagramType.MERMAID_ER: return "Mermaid ER";
                case DiagramType.MERMAID_GANTT: return "Mermaid Gantt";
                case DiagramType.MERMAID_PIE: return "Mermaid Pie";
                default: return dtype.to_string();
            }
        }

        private static void build_full_range(Json.Builder b, string content) {
            int line_count = content.split("\n").length;
            b.begin_object();
            b.set_member_name("start");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(0);
            b.set_member_name("character"); b.add_int_value(0);
            b.end_object();
            b.set_member_name("end");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(line_count);
            b.set_member_name("character"); b.add_int_value(0);
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
