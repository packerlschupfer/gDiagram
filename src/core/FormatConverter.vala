namespace GDiagram {
    public class FormatConverter : Object {

        // =====================================================================
        // Arrow conversion helpers (sequence diagrams)
        // =====================================================================

        // PlantUML sequence arrow → Mermaid (protect already-Mermaid arrows first)
        private static string arrow_puml_to_mermaid(string line) {
            string s = line;
            s = s.replace("-->>", "___DDASYNC___");
            s = s.replace("->>",  "___DASYNC___");
            s = s.replace("-->",  "___DDASYNC___");
            s = s.replace("->x",  "___DLOST___");
            s = s.replace("->",   "___DASYNC___");
            s = s.replace("___DDASYNC___", "-->>");
            s = s.replace("___DASYNC___",  "->>");
            s = s.replace("___DLOST___",   "-x");
            return s;
        }

        // Mermaid sequence arrow → PlantUML
        private static string arrow_mermaid_to_puml(string line) {
            string s = line;
            s = s.replace("->>",  "___DASYNC___");
            s = s.replace("-->>", "___DDASYNC___");
            s = s.replace("-x",   "___DLOST___");
            s = s.replace("-)",   "___DEXEC___");
            s = s.replace("___DDASYNC___", "-->");
            s = s.replace("___DASYNC___",  "->");
            s = s.replace("___DLOST___",   "->x");
            s = s.replace("___DEXEC___",   "->o");
            return s;
        }

        private static bool is_seq_message(string line) {
            return line.contains("->") || line.contains("<-") ||
                   line.contains("->>") || line.contains("<<-") ||
                   line.contains("-->>") || line.contains("-x") || line.contains("-)");
        }

        // =====================================================================
        // Sequence diagram: PlantUML → Mermaid
        // =====================================================================

        public static string? sequence_plantuml_to_mermaid(string plantuml_source) {
            var output = new StringBuilder();
            output.append("sequenceDiagram\n");

            string[] lines = plantuml_source.split("\n");
            bool in_diagram = false;
            bool in_note = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed.has_prefix("@startuml")) { in_diagram = true; continue; }
                if (trimmed.has_prefix("@enduml"))   { break; }
                if (!in_diagram && trimmed.length > 0) in_diagram = true;
                if (!in_diagram) continue;

                if (trimmed.length == 0) { output.append("\n"); continue; }
                // Skip comments and style directives
                if (trimmed.has_prefix("'") || trimmed.has_prefix("/'") ||
                    trimmed.has_prefix("skinparam") || trimmed.has_prefix("hide") ||
                    trimmed.has_prefix("autonumber")) continue;

                // Multi-line note body
                if (in_note) {
                    if (trimmed == "end note") {
                        output.append("    end note\n");
                        in_note = false;
                    } else {
                        output.append("    ").append(trimmed).append("\n");
                    }
                    continue;
                }

                // Note lines
                if (trimmed.has_prefix("note ") || trimmed.has_prefix("hnote ") ||
                    trimmed.has_prefix("rnote ")) {
                    string note_line = trimmed.has_prefix("note ") ? trimmed :
                                       "note " + trimmed.substring(trimmed.index_of(" ") + 1);
                    // Single-line note has colon; multi-line does not
                    if (note_line.contains(" : ")) {
                        string mermaid_note = note_line.substring(0, 1).up() + note_line.substring(1);
                        output.append("    ").append(mermaid_note).append("\n");
                    } else {
                        string mermaid_note = note_line.substring(0, 1).up() + note_line.substring(1);
                        output.append("    ").append(mermaid_note).append("\n");
                        in_note = true;
                    }
                    continue;
                }

                // Block keywords — pass through
                if (trimmed.has_prefix("loop") || trimmed.has_prefix("alt") ||
                    trimmed.has_prefix("opt") || trimmed.has_prefix("else") ||
                    trimmed.has_prefix("par") || trimmed.has_prefix("break") ||
                    trimmed.has_prefix("critical") || trimmed == "end") {
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }

                // activate / deactivate
                if (trimmed.has_prefix("activate ") || trimmed.has_prefix("deactivate ")) {
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }

                // participant / actor
                if (trimmed.has_prefix("participant ") || trimmed.has_prefix("actor ")) {
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }

                // title
                if (trimmed.has_prefix("title")) {
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }

                // Divider ==text== → skip (no Mermaid equivalent)
                if (trimmed.has_prefix("==") && trimmed.has_suffix("==")) continue;

                // box/group → comment
                if (trimmed.has_prefix("box") || trimmed == "end box" ||
                    trimmed.has_prefix("group") || trimmed == "end group") {
                    output.append_printf("    %% %s\n", trimmed);
                    continue;
                }

                // Message arrows
                if (is_seq_message(trimmed)) {
                    output.append("    ").append(arrow_puml_to_mermaid(trimmed)).append("\n");
                    continue;
                }
            }

            return output.str;
        }

        // =====================================================================
        // Sequence diagram: Mermaid → PlantUML
        // =====================================================================

        public static string? sequence_mermaid_to_plantuml(string mermaid_source) {
            var output = new StringBuilder();
            output.append("@startuml\n");

            string[] lines = mermaid_source.split("\n");
            bool in_diagram = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed == "sequenceDiagram") { in_diagram = true; continue; }
                if (!in_diagram && trimmed.length > 0) in_diagram = true;
                if (!in_diagram) continue;

                if (trimmed.length == 0) { output.append("\n"); continue; }
                if (trimmed.has_prefix("%%")) continue;

                // Note: Mermaid capitalises "Note", PlantUML uses "note"
                if (trimmed.has_prefix("Note ") || trimmed.has_prefix("note ")) {
                    output.append("note ").append(trimmed.substring(trimmed.index_of(" ") + 1)).append("\n");
                    continue;
                }

                // Pass-through keywords
                if (trimmed.has_prefix("participant ") || trimmed.has_prefix("actor ") ||
                    trimmed.has_prefix("activate ") || trimmed.has_prefix("deactivate ") ||
                    trimmed.has_prefix("loop") || trimmed.has_prefix("alt") ||
                    trimmed.has_prefix("opt") || trimmed.has_prefix("else") ||
                    trimmed.has_prefix("par") || trimmed.has_prefix("break") ||
                    trimmed.has_prefix("critical") || trimmed == "end" ||
                    trimmed == "end note" || trimmed.has_prefix("title")) {
                    output.append(trimmed).append("\n");
                    continue;
                }

                // Message arrows
                if (is_seq_message(trimmed)) {
                    output.append(arrow_mermaid_to_puml(trimmed)).append("\n");
                    continue;
                }

                output.append(trimmed).append("\n");
            }

            output.append("@enduml\n");
            return output.str;
        }

        // =====================================================================
        // Class diagram: PlantUML → Mermaid
        // =====================================================================

        public static string? class_plantuml_to_mermaid(string plantuml_source) {
            var output = new StringBuilder();
            output.append("classDiagram\n");

            string[] lines = plantuml_source.split("\n");
            bool in_class = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed.has_prefix("@startuml") || trimmed.has_prefix("@enduml")) continue;
                if (trimmed.length == 0) { output.append("\n"); continue; }
                if (trimmed.has_prefix("'") || trimmed.has_prefix("skinparam") ||
                    trimmed.has_prefix("hide") || trimmed.has_prefix("!")) continue;

                // Class / interface / abstract declaration
                if (trimmed.has_prefix("class ") || trimmed.has_prefix("interface ") ||
                    trimmed.has_prefix("abstract ") || trimmed.has_prefix("enum ")) {
                    in_class = trimmed.contains("{") && !trimmed.contains("}");
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }

                // Class body
                if (in_class) {
                    if (trimmed == "}") {
                        output.append("    ").append(trimmed).append("\n");
                        in_class = false;
                    } else {
                        output.append("        ").append(trimmed).append("\n");
                    }
                    continue;
                }

                // Closing brace outside tracked class
                if (trimmed == "}") {
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }

                // Relationships
                if (trimmed.contains("<|--") || trimmed.contains("--|>") ||
                    trimmed.contains("-->") || trimmed.contains("<-->") ||
                    trimmed.contains("*--") || trimmed.contains("--*") ||
                    trimmed.contains("o--") || trimmed.contains("--o") ||
                    trimmed.contains("..|>") || trimmed.contains("<|..") ||
                    trimmed.contains("..>") || trimmed.contains("..")) {
                    output.append("    ").append(trimmed).append("\n");
                    continue;
                }
            }

            return output.str;
        }

        // =====================================================================
        // Class diagram: Mermaid → PlantUML
        // =====================================================================

        public static string? class_mermaid_to_plantuml(string mermaid_source) {
            var output = new StringBuilder();
            output.append("@startuml\n");

            string[] lines = mermaid_source.split("\n");
            bool in_diagram = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed == "classDiagram" || trimmed.has_prefix("classDiagram ")) {
                    in_diagram = true;
                    continue;
                }
                if (!in_diagram) continue;
                if (trimmed.length == 0) { output.append("\n"); continue; }
                if (trimmed.has_prefix("%%")) continue;

                // Class declaration
                if (trimmed.has_prefix("class ")) {
                    output.append(trimmed).append("\n");
                    continue;
                }

                // Relationship arrows — syntax is compatible between PlantUML and Mermaid
                if (trimmed.contains("--|>") || trimmed.contains("<|--") ||
                    trimmed.contains("*--") || trimmed.contains("--*") ||
                    trimmed.contains("o--") || trimmed.contains("--o") ||
                    trimmed.contains("-->") || trimmed.contains("<-->") ||
                    trimmed.contains("..|>") || trimmed.contains("<|..") ||
                    trimmed.contains("..>") || trimmed.contains("..")) {
                    output.append(trimmed).append("\n");
                    continue;
                }

                // Class body members
                if (trimmed.has_prefix("+") || trimmed.has_prefix("-") ||
                    trimmed.has_prefix("#") || trimmed.has_prefix("~") ||
                    trimmed == "{" || trimmed == "}") {
                    output.append(trimmed).append("\n");
                    continue;
                }

                // namespace/note/link — emit as comments
                if (trimmed.has_prefix("namespace") || trimmed.has_prefix("note") ||
                    trimmed.has_prefix("link") || trimmed.has_prefix("callback")) {
                    output.append_printf("' %s\n", trimmed);
                    continue;
                }

                output.append(trimmed).append("\n");
            }

            output.append("@enduml\n");
            return output.str;
        }

        // =====================================================================
        // State diagram: PlantUML → Mermaid
        // PlantUML and Mermaid state syntax is nearly identical; main differences:
        //   header, comment style, and a few keywords.
        // =====================================================================

        public static string? state_plantuml_to_mermaid(string plantuml_source) {
            var output = new StringBuilder();
            output.append("stateDiagram-v2\n");

            string[] lines = plantuml_source.split("\n");
            bool in_diagram = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed.has_prefix("@startuml")) { in_diagram = true; continue; }
                if (trimmed.has_prefix("@enduml"))   { break; }
                if (!in_diagram && trimmed.length > 0) in_diagram = true;
                if (!in_diagram) continue;

                if (trimmed.length == 0) { output.append("\n"); continue; }

                // Skip style/skin directives
                if (trimmed.has_prefix("skinparam") || trimmed.has_prefix("hide") ||
                    trimmed.has_prefix("!") || trimmed.has_prefix("scale")) continue;

                // Comments: ' → %%
                if (trimmed.has_prefix("'")) {
                    output.append("  %% ").append(trimmed.substring(1).strip()).append("\n");
                    continue;
                }

                // PlantUML state syntax is near-identical to Mermaid — pass through
                output.append("  ").append(trimmed).append("\n");
            }

            return output.str;
        }

        // =====================================================================
        // State diagram: Mermaid → PlantUML
        // =====================================================================

        public static string? state_mermaid_to_plantuml(string mermaid_source) {
            var output = new StringBuilder();
            output.append("@startuml\n");

            string[] lines = mermaid_source.split("\n");
            bool in_diagram = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed == "stateDiagram-v2" || trimmed == "stateDiagram" ||
                    trimmed.has_prefix("stateDiagram")) {
                    in_diagram = true;
                    continue;
                }
                if (!in_diagram && trimmed.length > 0) in_diagram = true;
                if (!in_diagram) continue;

                if (trimmed.length == 0) { output.append("\n"); continue; }

                // Comments: %% → '
                if (trimmed.has_prefix("%%")) {
                    output.append("' ").append(trimmed.substring(2).strip()).append("\n");
                    continue;
                }

                // direction keyword not used in PlantUML state
                if (trimmed.has_prefix("direction ")) continue;

                output.append(trimmed).append("\n");
            }

            output.append("@enduml\n");
            return output.str;
        }

        // =====================================================================
        // ER diagram: PlantUML → Mermaid
        // PlantUML: entity Name { * field : type }
        // Mermaid:  NAME { type field PK }
        // Relationship syntax is compatible (||--o{ etc.)
        // =====================================================================

        public static string? er_plantuml_to_mermaid(string plantuml_source) {
            var output = new StringBuilder();
            output.append("erDiagram\n");

            string[] lines = plantuml_source.split("\n");
            bool in_diagram = false;
            bool in_entity = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed.has_prefix("@startuml")) { in_diagram = true; continue; }
                if (trimmed.has_prefix("@enduml"))   { break; }
                if (!in_diagram && trimmed.length > 0) in_diagram = true;
                if (!in_diagram) continue;

                if (trimmed.length == 0) { output.append("\n"); continue; }
                if (trimmed.has_prefix("skinparam") || trimmed.has_prefix("'") ||
                    trimmed.has_prefix("hide") || trimmed.has_prefix("!")) continue;

                // Entity declaration: entity Name { or entity Name as Alias {
                if (trimmed.has_prefix("entity ") && !in_entity) {
                    string rest = trimmed.substring(7).replace("{", "").strip();
                    string ename;
                    int as_pos = rest.index_of(" as ");
                    if (as_pos >= 0) {
                        ename = rest.substring(as_pos + 4).strip();
                    } else {
                        ename = rest;
                    }
                    ename = ename.up();
                    in_entity = trimmed.contains("{");
                    output.append_printf("  %s {\n", ename);
                    if (!in_entity) {
                        // Entity without braces body
                        output.append("  }\n");
                    }
                    continue;
                }

                if (in_entity && trimmed == "}") {
                    output.append("  }\n");
                    in_entity = false;
                    continue;
                }

                // Entity field inside braces
                if (in_entity) {
                    if (trimmed == "--" || trimmed.length == 0) continue;  // separator line

                    bool is_pk = trimmed.has_prefix("* ");
                    bool is_fk = trimmed.has_prefix("+ ");
                    string field_text = (is_pk || is_fk) ? trimmed.substring(2).strip() : trimmed;

                    if (field_text.contains(":")) {
                        int ci = field_text.index_of(":");
                        string fname = field_text.substring(0, ci).strip();
                        string ftype_rest = field_text.substring(ci + 1).strip();
                        string ftype = ftype_rest;
                        string fcomment = "";
                        // Inline comment after type
                        int qi = ftype_rest.index_of("\"");
                        if (qi >= 0) {
                            ftype = ftype_rest.substring(0, qi).strip();
                            fcomment = " " + ftype_rest.substring(qi);
                        }
                        string suffix = is_pk ? " PK" : (is_fk ? " FK" : "");
                        output.append_printf("    %s %s%s%s\n", ftype, fname, suffix, fcomment);
                    } else {
                        string suffix = is_pk ? " PK" : (is_fk ? " FK" : "");
                        output.append_printf("    string %s%s\n", field_text, suffix);
                    }
                    continue;
                }

                // Relationships: A ||--o{ B : label → A ||--o{ B : "label"
                if (trimmed.contains("||") || trimmed.contains("|{") ||
                    trimmed.contains("}|") || trimmed.contains("o{") ||
                    trimmed.contains("}o") || trimmed.contains("|o") ||
                    trimmed.contains("o|")) {
                    int colon = trimmed.last_index_of(" : ");
                    if (colon >= 0) {
                        string rel_part = trimmed.substring(0, colon);
                        string label = trimmed.substring(colon + 3).strip();
                        if (!label.has_prefix("\"")) label = "\"" + label + "\"";
                        output.append_printf("  %s : %s\n", rel_part, label);
                    } else {
                        output.append("  ").append(trimmed).append("\n");
                    }
                    continue;
                }
            }

            return output.str;
        }

        // =====================================================================
        // ER diagram: Mermaid → PlantUML
        // =====================================================================

        public static string? er_mermaid_to_plantuml(string mermaid_source) {
            var output = new StringBuilder();
            output.append("@startuml\n");

            string[] lines = mermaid_source.split("\n");
            bool in_diagram = false;
            bool in_entity = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed == "erDiagram" || trimmed.has_prefix("erDiagram ")) {
                    in_diagram = true;
                    continue;
                }
                if (!in_diagram && trimmed.length > 0) in_diagram = true;
                if (!in_diagram) continue;

                if (trimmed.length == 0) { output.append("\n"); continue; }
                if (trimmed.has_prefix("%%")) continue;

                // Entity: NAME {
                if (!in_entity && trimmed.has_suffix("{") &&
                    !trimmed.contains("-->") && !trimmed.contains("||") &&
                    !trimmed.contains("|{") && !trimmed.contains("}|")) {
                    string ename = trimmed.replace("{", "").strip();
                    // Title-case the name for PlantUML style
                    string puml_name = ename.length > 0 ?
                        ename.substring(0, 1).up() + ename.substring(1).down() : ename;
                    in_entity = true;
                    output.append_printf("entity %s {\n", puml_name);
                    continue;
                }

                if (in_entity && trimmed == "}") {
                    output.append("}\n");
                    in_entity = false;
                    continue;
                }

                // Entity field: type name [PK|FK|UK] ["comment"]
                if (in_entity && trimmed.length > 0) {
                    string[] fparts = trimmed.split(" ");
                    if (fparts.length >= 2) {
                        string ftype = fparts[0];
                        string fname = fparts[1];
                        bool is_pk = trimmed.contains(" PK");
                        bool is_fk = trimmed.contains(" FK");
                        string prefix = is_pk ? "* " : (is_fk ? "+ " : "");
                        // Collect comment if any
                        var cmt = new StringBuilder();
                        for (int i = 2; i < fparts.length; i++) {
                            if (fparts[i].has_prefix("\"") || cmt.len > 0) {
                                if (cmt.len > 0) cmt.append(" ");
                                cmt.append(fparts[i]);
                            }
                        }
                        string fcomment = cmt.len > 0 ? (" " + cmt.str) : "";
                        output.append_printf("  %s%s : %s%s\n", prefix, fname, ftype, fcomment);
                    } else {
                        output.append("  ").append(trimmed).append("\n");
                    }
                    continue;
                }

                // Relationships: strip quotes from label
                if (!in_entity && (trimmed.contains("||") || trimmed.contains("|{") ||
                    trimmed.contains("}|") || trimmed.contains("o{") ||
                    trimmed.contains("}o"))) {
                    int colon = trimmed.last_index_of(" : ");
                    if (colon >= 0) {
                        string rel_part = trimmed.substring(0, colon);
                        string label = trimmed.substring(colon + 3).strip().replace("\"", "");
                        output.append_printf("%s : %s\n", rel_part, label);
                    } else {
                        output.append(trimmed).append("\n");
                    }
                    continue;
                }

                output.append(trimmed).append("\n");
            }

            output.append("@enduml\n");
            return output.str;
        }

        // =====================================================================
        // Detection and dispatch
        // =====================================================================

        public static bool can_convert(string source, string from_format, string to_format) {
            string lower = source.down();
            if (from_format == "plantuml" && to_format == "mermaid") {
                return lower.contains("participant ") || lower.contains("actor ") ||
                       lower.contains("class ") || lower.contains("interface ") ||
                       lower.contains("entity ") || lower.contains("[*]") ||
                       lower.contains("state ");
            }
            if (from_format == "mermaid" && to_format == "plantuml") {
                return lower.contains("sequencediagram") || lower.contains("classdiagram") ||
                       lower.contains("erdiagram") || lower.contains("statediagram");
            }
            return false;
        }

        public static string? auto_convert(string source, string target_format) {
            string lower = source.down();

            bool is_plantuml = lower.contains("@startuml") || lower.contains("@startgantt") ||
                               lower.contains("@startmindmap") || lower.contains("@startwbs");

            if (is_plantuml) {
                if (target_format != "mermaid") return null;
                // Sequence: participant/actor keywords, or arrows without entity/class context
                if (lower.contains("participant ") || lower.contains("actor ")) {
                    return sequence_plantuml_to_mermaid(source);
                }
                // ER must be checked before class (entity keyword)
                if (lower.contains("entity ")) {
                    return er_plantuml_to_mermaid(source);
                }
                // Class
                if (lower.contains("class ") || lower.contains("interface ") ||
                    lower.contains("abstract ")) {
                    return class_plantuml_to_mermaid(source);
                }
                // State
                if (lower.contains("[*]") || lower.contains("state ")) {
                    return state_plantuml_to_mermaid(source);
                }
                // Fallback: try sequence if arrows present
                if (lower.contains("->")) {
                    return sequence_plantuml_to_mermaid(source);
                }
                return null;
            } else {
                // Mermaid source → PlantUML
                if (target_format != "plantuml") return null;
                if (lower.contains("sequencediagram")) {
                    return sequence_mermaid_to_plantuml(source);
                }
                if (lower.contains("classdiagram")) {
                    return class_mermaid_to_plantuml(source);
                }
                if (lower.contains("erdiagram")) {
                    return er_mermaid_to_plantuml(source);
                }
                if (lower.contains("statediagram")) {
                    return state_mermaid_to_plantuml(source);
                }
                return null;
            }
        }
    }
}
