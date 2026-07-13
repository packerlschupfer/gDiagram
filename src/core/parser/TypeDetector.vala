namespace GDiagram {
    /**
     * Single source of truth for diagram-type detection.
     *
     * Both the GUI render path (DocumentView) and the headless export path
     * (Application) used to have their own copies of this logic. They drifted
     * out of sync, causing real bugs (e.g. WBS files detected as ACTIVITY in
     * one path but not the other). All detection now lives here.
     *
     * Returns DiagramType.UNKNOWN when no syntax is recognized so callers can
     * surface a clear error instead of silently rendering an empty default.
     */
    public class TypeDetector : Object {

        // True if the source contains a "business actor" :Name:/ pattern
        // (a letter followed by `:/` followed by whitespace/end). Excludes
        // URL `://` which has `/` immediately after the second `:`.
        // True if the source contains an activity action line: a line that
        // (after leading whitespace) STARTS with ':'. The previous heuristic —
        // any ':' plus any ';' anywhere in the source — misdetected component
        // diagrams whose edge labels contain colons and whose node labels
        // contain a semicolon. A terminating ';' is still required somewhere,
        // but it may sit on a later line (multi-line actions).
        private static bool contains_action_line(string lower) {
            if (!lower.contains(";")) return false;
            foreach (string raw_line in lower.split("\n")) {
                string line = raw_line.strip();
                if (line.length > 1 && line[0] == ':') return true;
            }
            return false;
        }

        private static bool contains_business_actor(string lower) {
            int n = lower.length;
            for (int i = 1; i < n - 1; i++) {
                if (lower[i] != ':') continue;
                // Must have a letter or digit before
                char prev = lower[i - 1];
                if (!(prev >= 'a' && prev <= 'z') && !(prev >= '0' && prev <= '9')) continue;
                // Must have `/` immediately after
                if (lower[i + 1] != '/') continue;
                // Reject URL form (`://`): check that the char after `/` is
                // not another `/`.
                if (i + 2 < n && lower[i + 2] == '/') continue;
                return true;
            }
            return false;
        }

        public static bool is_mermaid(string source) {
            // PlantUML files start with @startuml, @startgantt, @startwbs,
            // @startpacketdiag etc. Mermaid never uses @start..., so a tag line
            // means PlantUML (without this guard, @startpacketdiag was "packet").
            // Only a line that starts with the tag counts: "@start" in label text
            // made Mermaid documents PlantUML.
            if (diagram_tag(source) != null) {
                return false;
            }
            // Mermaid reads the diagram kind from the first line (after front matter,
            // comments and directives). Keywords elsewhere are label text: a PlantUML
            // "Alice -> Bob : show gantt" was a Mermaid document.
            return mermaid_header_type(source) != DiagramType.UNKNOWN;
        }

        /**
         * The kind of the first diagram in the source: "uml" for "@startuml" or
         * "@startuml(id=x)", "json" for "@startjson", null without a tag line.
         * PlantUML starts a diagram at a line beginning with "@start"; text before it,
         * "@start..." inside a label and the tags of later diagrams in the same file
         * do not choose the kind.
         */
        public static string? diagram_tag(string source) {
            foreach (string raw in source.split("\n")) {
                string line = raw.strip().down();
                if (!line.has_prefix("@start")) {
                    continue;
                }
                int end = 6;
                while (end < line.length && line[end].isalpha()) {
                    end++;
                }
                return line.substring(6, end - 6);
            }
            return null;
        }

        public static DiagramType detect_plantuml(string source) {
            // The @start... tag of the first diagram is definitive
            string? tag = diagram_tag(source);
            if (tag != null) {
                switch (tag) {
                    case "json": return DiagramType.JSON_DIAGRAM;
                    case "nwdiag": return DiagramType.NWDIAG;
                    case "packetdiag": return DiagramType.MERMAID_PACKET;
                    case "yaml": return DiagramType.YAML_DIAGRAM;
                    case "chronology": return DiagramType.CHRONOLOGY;
                    case "gantt": return DiagramType.GANTT;
                    case "wbs": return DiagramType.WBS;
                    case "mindmap": return DiagramType.MINDMAP;
                    case "dot": return DiagramType.DOT_DIAGRAM;
                    case "salt": return DiagramType.SALT;
                    case "chen": return DiagramType.CHEN_ER;
                    case "ebnf": return DiagramType.EBNF;
                    case "regex": return DiagramType.REGEX_DIAGRAM;
                    case "tree": return DiagramType.TREE;
                    case "ditaa": return DiagramType.DITAA;
                    case "board": return DiagramType.BOARD;
                    case "ancestry": return DiagramType.ANCESTRY;
                    default: break;
                }
            }

            // GEDCOM files start with "0 HEAD" and have no @start tag
            string raw_lower = source.down();
            if (tag == null && (raw_lower.has_prefix("0 head") || raw_lower.contains("\n0 head"))) {
                return DiagramType.ANCESTRY;
            }

            // Keyword rules below look at the diagram code only: text after a label
            // colon, quoted strings, activity action text and multi-line "[...]" bodies
            // are removed ("A -> B : glob [*] files" was a state diagram,
            // ":run tool --output;" a class diagram). `full_lower` keeps the notes.
            string full_lower = strip_labels(source).down();
            string code_as_written = strip_labels(strip_notes(source));
            string code = code_as_written.down();
            string lower = code;

            // Archimate: archimate keyword or macro-style layer prefixes
            // Also indented, inside a "rectangle ... {" layer box (those went to the
            // component renderer)
            if (has_line_starting(lower, "archimate ") ||
                lower.contains("\nbusiness_") || lower.contains("\napplication_") ||
                lower.contains("\ntechnology_") || lower.contains("\nmotivation_")) {
                return DiagramType.ARCHIMATE;
            }

            // Timing diagram: @startuml with concise/robust/clock/binary/analog signals
            // Must check BEFORE sequence/state/activity since timing uses @startuml too.
            // A message from a participant named "clock" ("clock -> Bob") is not a signal.
            if (tag == null || tag == "uml") {
                foreach (string kw in new string[] { "concise ", "robust ", "clock ", "binary ", "analog " }) {
                    if (has_line_starting_without(lower, kw, "->", "<-")) {
                        return DiagramType.TIMING;
                    }
                }
            }

            // Raw C4-PlantUML macros: files using the stdlib directly (before
            // preprocessor expansion) call Person(...), Container(...), etc.
            // We route these to COMPONENT so the C4-aware render path kicks in
            // once the preprocessor has expanded the stdlib macros. The calls are
            // statements: "render_component(x)" in a label is not one.
            if (has_c4_macro_line(lower)) {
                return DiagramType.COMPONENT;
            }

            // C4-PlantUML expansion: any of the C4 element stereotypes appears.
            // After preprocessor expansion, C4 calls produce rectangle/database
            // declarations with these stereotypes. Routes to COMPONENT (which
            // already understands rectangle/database/<<stereo>> syntax). Must
            // come before the activity heuristic because the C4 output also
            // contains skinparam blocks with ':' and ';' that would otherwise
            // trigger the activity check.
            if (lower.contains("<<person>>") ||
                lower.contains("<<system>>") ||
                lower.contains("<<container>>") ||
                lower.contains("<<container_db>>") ||
                lower.contains("<<container_queue>>") ||
                lower.contains("<<external_person>>") ||
                lower.contains("<<external_system>>") ||
                lower.contains("<<external_container>>") ||
                lower.contains("<<system_boundary>>") ||
                lower.contains("<<container_boundary>>") ||
                lower.contains("<<enterprise_boundary>>") ||
                (lower.contains("<<boundary>>") && lower.contains("rectangle "))) {
                return DiagramType.COMPONENT;
            }

            // Sequence diagram: participant keyword is unique to sequence
            bool has_sequence_syntax =
                lower.contains("\nparticipant ") ||
                lower.has_prefix("participant ") ||
                (lower.contains("\nactor ") && lower.contains("\nparticipant "));
            if (has_sequence_syntax) return DiagramType.SEQUENCE;

            // State diagram: [*], state keyword
            if (lower.contains("[*]") ||
                lower.contains("\nstate ") || lower.has_prefix("state ")) {
                return DiagramType.STATE;
            }

            // Object diagrams: "object" / "map" declarations with no class or component
            // declarations. Their class-style arrows ("<|--", "*--") and packages made
            // them class or component diagrams.
            // Checked on the source as written: keywords are lowercase, and a class
            // named "Object" ("Object <|-- ArrayList") is not an object declaration.
            // Note bodies and multi-line action text are not declarations: "map entries
            // are cached" in a note, or ":Load\nobject pool;", made activity, component
            // and sequence files object diagrams.
            // An embedded "json Name {" is an object-diagram element too, and bare "class X"
            // lines beside objects stay drawable there (PlantUML's example: a class, an
            // object and a json block; the class line made it a class diagram, losing both).
            // (Not beside actors and use cases: an "allowmixing" use case file keeps its
            // renderer, which draws those.)
            bool object_decl = has_line_starting(code_as_written, "object ") || has_line_starting(code_as_written, "map ") ||
                (has_json_element_line(code_as_written) && !has_line_starting(code, "actor ") &&
                 !has_line_starting(code, "usecase "));
            if (object_decl &&
                (!has_line_starting(code, "class ") || only_bare_class_lines(code)) && !has_line_starting(code, "abstract ") &&
                !has_line_starting(code, "interface ") && !has_line_starting(code, "enum ") &&
                !has_class_keyword_declaration(code) &&
                !has_line_starting(code, "component ") && !has_line_starting(code, "[")) {
                return DiagramType.OBJECT;
            }

            // Description diagrams (components, interfaces, boundaries, actors) can carry
            // class-looking arrows ("#-->>", "*-0)-+") and "interface" lines. Without a
            // class declaration they are component diagrams, not class diagrams.
            // Deployment elements count too: a file of "artifact"/"node"/... lines with arrows
            // like "--*" and "--+" was a class diagram, where "--0 artifact8" drew a class "0".
            // Only those need "no entity line" (IE/crow's-foot files stay class diagrams); a
            // file with component lines is a component diagram even when it lists "entity".
            // Declarations are looked for outside notes: note text such as "node version
            // must be >= 18" or "[optional] retry" made activity diagrams component diagrams.
            // Activity files (start/stop, ":action;") are never claimed; use case files keep
            // their frames and nodes; a file of queue/collections/database participants and
            // sequence messages is a sequence diagram, as in PlantUML.
            bool component_lines = has_line_starting(code, "component ") || has_bracket_component_line(code) ||
                                   has_line_starting(code, "() ");
            if (!has_line_starting(code, "class ") && !has_line_starting(code, "abstract ") &&
                !has_line_starting(code, "enum ") &&
                !has_activity_line(code) &&
                (component_lines || has_line_starting(code, "boundary ") ||
                 has_line_starting(code, "control ") ||
                 (!has_line_starting(code, "entity ") && !has_usecase_declaration(code) &&
                  has_deployment_element_line(code)))) {
                if (!component_lines && is_sequence_only(code)) {
                    return DiagramType.SEQUENCE;
                }
                return DiagramType.COMPONENT;
            }
            // Use case diagrams may use class-style arrows ("(Start) <|-- (Use)").
            // Their "(name)" and ":Actor: as X" lines are not class syntax, so check
            // them before the class arrows claim the file. Links to or from a use case
            // or a colon actor (":user: -left-> (dummyLeft)", "User -> (Start)") count:
            // those files were sequence diagrams, and their export failed.
            if (!has_class_declaration(lower) && contains_usecase_shorthand(lower)) {
                return DiagramType.USECASE;
            }

            // Class diagram BEFORE activity — class files can legitimately
            // contain both ':' and ';' (e.g. in note text), which would
            // otherwise trigger the activity heuristic.
            if ((lower.contains("\nclass ") || lower.has_prefix("class ")) ||
                // "exception E", "record R", "struct S", ... declarations
                has_class_keyword_declaration(code) ||
                lower.contains("\ninterface ") ||
                lower.contains("\nabstract class") ||
                lower.contains("\nenum ") ||
                // Declarations indented inside package/namespace blocks
                has_line_starting(lower, "class ") || has_line_starting(lower, "abstract class ") ||
                has_line_starting(lower, "enum ") ||
                // Class declarations with visibility prefix: -class, #class,
                // ~class, +class (private/protected/package/public)
                lower.contains("\n-class ") || lower.contains("\n#class ") ||
                lower.contains("\n~class ") || lower.contains("\n+class ") ||
                // Standard class relation arrows
                lower.contains("--|>") || lower.contains("<|--") ||
                lower.contains("..|>") || lower.contains("<|..") ||
                lower.contains("o--")  || lower.contains("--o")  ||
                lower.contains("*--")  || lower.contains("--*") ||
                // Alternative class relation arrows: #-- x-- }-- +-- ^--
                lower.contains("#--") || lower.contains("--#") ||
                lower.contains("x--") || lower.contains("--x") ||
                lower.contains("}--") || lower.contains("--{") ||
                lower.contains("+--") || contains_class_plus_arrow(lower) ||
                lower.contains("^--") || lower.contains("--^")) {
                return DiagramType.CLASS;
            }

            // Activity diagram: start/stop, control flow keywords, action lines
            bool has_start_stop = lower.contains("\nstart") || lower.contains("\nstop") ||
                                  lower.has_prefix("@startuml\nstart") ||
                                  lower.has_prefix("@startuml\r\nstart");
            // "(*) --> "First"": legacy activity syntax (was a use case diagram)
            bool has_activity_syntax = lower.contains("(*)") ||
                                       lower.contains("endif") ||
                                       lower.contains("endwhile") ||
                                       lower.contains("end fork") ||
                                       lower.contains("endswitch") ||
                                       lower.contains("fork again") ||
                                       lower.contains("partition ") ||
                                       contains_action_line(lower) ||
                                       // "|Swimlane|" / "|#color|Swimlane|"
                                       has_swimlane_line(code) ||
                                       lower.contains("\n* ") || lower.has_prefix("* ") ||
                                       lower.contains("\n- ") || lower.has_prefix("- ");
            if (has_start_stop || has_activity_syntax) {
                return DiagramType.ACTIVITY;
            }

            // Actor-only files with messages ("actor Alice" / "Alice -> Bob : hello") are sequence
            // diagrams, as in PlantUML; the actor rule below made them use case diagrams. A use
            // case, "(Name)", ":Name:" actor, business "/" or container line fails is_sequence_only.
            if (has_line_starting(code, "actor ") && is_sequence_only(code)) {
                return DiagramType.SEQUENCE;
            }

            // Use case diagram
            if (lower.contains("\nusecase ") ||
                lower.contains("\nusecase(") ||
                lower.contains("\nusecase/") || lower.has_prefix("usecase/") ||
                lower.contains("\nactor/") || lower.has_prefix("actor/") ||
                // Business usecase notation: (First usecase)/ — closing paren
                // immediately followed by '/'. Excludes URLs (which have '/'
                // after a host segment, never after a paren).
                lower.contains(")/") ||
                // Business actor notation: :Actor Name:/
                // Match :word:/ but NOT URL :// — the colon must be preceded
                // by a letter (the end of an actor name), and not preceded
                // by another colon or slash.
                contains_business_actor(lower) ||
                (lower.contains("\nactor ") && !lower.contains("\nparticipant "))) {
                return DiagramType.USECASE;
            }

            // ER diagram
            if (lower.contains("\nentity ") || lower.has_prefix("entity ") ||
                lower.contains("||--") || lower.contains("}o--") ||
                lower.contains("|o--") || lower.contains("--||") ||
                lower.contains("--o{") || lower.contains("--o|")) {
                return DiagramType.ER_DIAGRAM;
            }

            // Component diagram
            if (lower.contains("\npackage ") || lower.has_prefix("package ") ||
                lower.contains("\ncomponent ") || has_unindented_bracket_line(lower) ||
                lower.contains("\ncloud ") || lower.contains("\nnode ") ||
                lower.contains("\nfolder ") || lower.contains("\nframe ") ||
                lower.contains("\nrectangle ") || lower.contains("\nartifact ") ||
                lower.contains("\nstorage ") || lower.contains("\ndatabase ") ||
                // "device" was a separate deployment diagram type; PlantUML rejects the
                // keyword, and gDiagram draws it as a node
                lower.contains("\ndevice ") || lower.has_prefix("device ")) {
                return DiagramType.COMPONENT;
            }

            // Object diagram
            if (lower.contains("\nobject ") || lower.has_prefix("object ") ||
                lower.contains("\nmap ")) {
                return DiagramType.OBJECT;
            }

            // Messages and participant declarations only ("Bob -[#red]> Alice", a lone
            // "note over Alice : text"): PlantUML's sequence diagram. "-[#red]>" has no "->".
            if (is_sequence_only(code) || has_line_starting(full_lower, "note over ")) {
                return DiagramType.SEQUENCE;
            }

            // A link a sequence diagram cannot take ("ClassA -- ClassB : label",
            // "Client ..> Supplier", "foo -left-> dummyLeft") between plain names: PlantUML
            // falls back to a class diagram. These were unknown or, with "-left->", sequence
            // diagrams whose export failed. So is a lone floating 'note "text" as N1'.
            if (has_class_link_line(code) || has_floating_note_line(full_lower)) {
                return DiagramType.CLASS;
            }

            // Sequence diagram (last resort — needs only an arrow)
            if (lower.contains("->") || lower.contains("-->") ||
                lower.contains("<-") || lower.contains("<--")) {
                return DiagramType.SEQUENCE;
            }

            // A lone "note left: text" / "note right: text" is an activity note in PlantUML
            if (has_line_starting(full_lower, "note left:") || has_line_starting(full_lower, "note right:") ||
                has_line_starting(full_lower, "note left :") || has_line_starting(full_lower, "note right :")) {
                return DiagramType.ACTIVITY;
            }

            // No syntax recognized
            return DiagramType.UNKNOWN;
        }

        // "|Lane|" or "|#color|Lane|" on a line of its own ("|||" is sequence spacing)
        private static bool has_swimlane_line(string code) {
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (line.length > 2 && line.has_prefix("|") && line.has_suffix("|") &&
                    !line.has_prefix("||") && line.substring(1, line.length - 2).strip().length > 0) {
                    return true;
                }
            }
            return false;
        }

        // 'note "text" as N1'
        private static bool has_floating_note_line(string lower) {
            foreach (string raw in lower.split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("note \"") && line.contains("\" as ")) {
                    return true;
                }
            }
            return false;
        }

        private static Regex? class_link_regex = null;
        private static Regex? usecase_link_regex = null;

        // Link endpoints, arrow body with an optional "[style]" and direction word, ends
        private const string LINK_ARROW =
            "\\s*(<\\|?|\\*|o|\\+|#|x|\\}|\\^|<)?(-+|\\.+)(\\[[^\\]]*\\])?" +
            "((left|right|up|down|le|ri|do|l|r|u|d)(-+|\\.+))?(\\|?>|\\*|o|\\+|#|x|\\{|\\^|>)?\\s*";

        // A link between plain names that is not a sequence message. Either end may
        // carry a quoted multiplicity ('A "1" - "many" B', 'A --> "*" B'), which no
        // sequence message takes: PlantUML draws those as class diagrams, they were
        // unknown or sequence diagrams.
        private static bool has_class_link_line(string code) {
            if (class_link_regex == null) {
                try {
                    class_link_regex = new Regex("^([\\w.]+|\"[^\"]+\")(\\s*\"[^\"]*\")?" + LINK_ARROW +
                                                 "(\"[^\"]*\"\\s*)?([\\w.]+|\"[^\"]+\")\\s*(:.*)?$");
                } catch (RegexError e) {
                    return false;
                }
            }
            is_sequence_only("");  // compiles sequence_message_regex
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (class_link_regex.match(line) && !sequence_message_regex.match(line)) {
                    return true;
                }
            }
            return false;
        }

        // A link with a use case "(Name)" or a colon actor ":Name:" at one end
        private static bool has_usecase_link_line(string code) {
            if (usecase_link_regex == null) {
                try {
                    string end = "(:[^:;]+:|\\([^()*]+\\)|\"[^\"]*\"|[\\w.]+)/?";
                    usecase_link_regex = new Regex("^" + end + LINK_ARROW + end + "\\s*(:.*)?$");
                } catch (RegexError e) {
                    return false;
                }
            }
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                MatchInfo info;
                if (!usecase_link_regex.match(line, 0, out info)) {
                    continue;
                }
                // group 1: first end, 9: second end (groups 2-8 are the arrow)
                string from = info.fetch(1) ?? "";
                string to = info.fetch(9) ?? "";
                foreach (string end in new string[] { from, to }) {
                    if ((end.has_prefix("(") && end.strip().length > 2) || end.has_prefix(":")) {
                        return true;
                    }
                }
            }
            return false;
        }

        // "--+" is a class arrow, but "--++" is sequence activation shorthand
        // ("bob -> charlie --++ : x"), which made sequence files class diagrams.
        private static bool contains_class_plus_arrow(string lower) {
            int i = 0;
            while ((i = lower.index_of("--+", i)) >= 0) {
                if (i + 3 >= lower.length || lower[i + 3] != '+') {
                    return true;
                }
                i += 4;
            }
            return false;
        }

        // Some line, ignoring its indentation, starts with `prefix`
        // A line declaring a deployment/description element ("artifact x", "node y", ...)
        private static bool has_deployment_element_line(string lower) {
            foreach (string kw in new string[] { "artifact ", "node ", "device ", "folder ", "frame ", "cloud ",
                                                 "database ", "storage ", "card ", "agent ", "queue ",
                                                 "stack ", "collections ", "hexagon " }) {
                if (has_line_starting(lower, kw)) {
                    return true;
                }
            }
            return false;
        }

        private static bool has_line_starting(string lower, string prefix) {
            foreach (string raw in lower.split("\n")) {
                if (raw.strip().has_prefix(prefix)) {
                    return true;
                }
            }
            return false;
        }

        // "json Name {" (an object diagram's JSON element)
        private static bool has_json_element_line(string code) {
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("json ") && line.has_suffix("{") && line.length > 6) {
                    return true;
                }
            }
            return false;
        }

        // Every "class" line is a bare "class Name" without a body, generics or
        // stereotype, and no class-relation arrow links anything
        private static bool only_bare_class_lines(string code) {
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("class ")) {
                    string rest = line.substring(6).strip();
                    if (rest.length == 0 || rest.contains("{") || rest.contains("<") || rest.contains(" ")) {
                        return false;
                    }
                }
                if (line.contains("<|") || line.contains("|>")) {
                    return false;
                }
            }
            return true;
        }

        // Some line starts with `prefix` and contains neither `not_a` nor `not_b`
        private static bool has_line_starting_without(string lower, string prefix, string not_a, string not_b) {
            foreach (string raw in lower.split("\n")) {
                string line = raw.strip();
                if (line.has_prefix(prefix) && !line.contains(not_a) && !line.contains(not_b)) {
                    return true;
                }
            }
            return false;
        }

        private const string[] C4_MACROS = {
            "person", "system", "system_ext", "container", "containerdb", "containerqueue",
            "component", "componentdb", "system_boundary", "container_boundary",
            "enterprise_boundary", "deployment_node"
        };

        // A line calling a C4-PlantUML macro: "Person(user, ...)", "System_Boundary (b, ...) {"
        private static bool has_c4_macro_line(string lower) {
            foreach (string raw in lower.split("\n")) {
                string line = raw.strip();
                int end = 0;
                while (end < line.length && (line[end].isalnum() || line[end] == '_')) {
                    end++;
                }
                if (end == 0 || !line.substring(end).chug().has_prefix("(")) {
                    continue;
                }
                string name = line.substring(0, end);
                foreach (string macro in C4_MACROS) {
                    if (name == macro) {
                        return true;
                    }
                }
            }
            return false;
        }

        /**
         * The source without label text, line by line (indentation and case kept):
         *  - quoted strings keep their quotes and become "x";
         *  - comment lines ("' text") become blank;
         *  - an activity action ":any text;" becomes ":a;" (other terminators kept);
         *  - text after a label colon outside "(...)" and "[...]" is dropped, the colon
         *    kept ("A -> B : text", ":Actor: -> (Use) : text", "State : text");
         *  - the lines of a multi-line "[" ... "]" description body are dropped.
         * Swimlane lines ("|Lane|") are kept as they are.
         */
        private static string strip_labels(string text) {
            string[] lines = text.split("\n");
            var sb = new StringBuilder();
            for (int i = 0; i < lines.length; i++) {
                string raw = lines[i];
                string t = raw.strip();
                int indent = raw.index_of(t.length > 0 ? t.substring(0, 1) : "");
                string lead = indent > 0 ? raw.substring(0, indent) : "";
                if (t.has_prefix("'")) {
                    sb.append_c('\n');
                    continue;
                }
                if (t.length == 0 || t.has_prefix("|") || t.has_prefix("@")) {
                    sb.append(raw);
                    sb.append_c('\n');
                    continue;
                }
                string line = blank_quoted(t);
                if (line.has_prefix(":")) {
                    if (line.has_suffix(";")) {
                        line = ":a;";
                    } else if (line.index_of(":", 1) < 0) {
                        // an action; one whose text goes on over the next lines
                        // (dropped by strip_notes) counts as ":a;"
                        line = ends_action_text(line) ? ":a" + line.substring(line.length - 1) : ":a;";
                    } else {
                        line = cut_label(line, line.index_of(":", 1) + 1);
                    }
                } else {
                    line = cut_label(line, 0);
                }
                sb.append(lead);
                sb.append(line);
                sb.append_c('\n');
                // "node n [" ... "]": the body lines are the element's label
                if (line.has_suffix("[") && !line.has_prefix(":")) {
                    for (int j = i + 1; j < lines.length; j++) {
                        string next = lines[j].strip();
                        if (next.has_prefix("@end")) {
                            break;
                        }
                        if (next.has_prefix("]")) {
                            i = j - 1;
                            break;
                        }
                    }
                }
            }
            return sb.str;
        }

        // Every quoted string's text replaced by "x"; an unclosed quote is left alone
        private static string blank_quoted(string line) {
            if (!line.contains("\"")) {
                return line;
            }
            var sb = new StringBuilder();
            int i = 0;
            while (i < line.length) {
                int close = line[i] == '"' ? line.index_of("\"", i + 1) : -1;
                if (close > 0) {
                    sb.append(close > i + 1 ? "\"x\"" : "\"\"");
                    i = close + 1;
                } else {
                    sb.append_c(line[i]);
                    i++;
                }
            }
            return sb.str;
        }

        // `line` up to and including the first colon at or after `from` that sits
        // outside parentheses and brackets
        private static string cut_label(string line, int from) {
            int depth = 0;
            for (int i = from; i < line.length; i++) {
                char c = line[i];
                if (c == '(' || c == '[') {
                    depth++;
                } else if ((c == ')' || c == ']') && depth > 0) {
                    depth--;
                } else if (c == ':' && depth == 0) {
                    return line.substring(0, i + 1);
                }
            }
            return line;
        }

        // Indented declarations count: "package p {\n  class Student" was missed and an
        // association class "(Student, Course) .. Enrollment" became a use case.
        private static bool has_class_declaration(string lower) {
            return has_line_starting(lower, "class ") || has_line_starting(lower, "interface ") ||
                   has_line_starting(lower, "abstract ") || has_line_starting(lower, "enum ");
        }

        private static Regex? class_keyword_regex = null;

        // A declaration with one of the other class-diagram keywords: "exception MyError",
        // "record R", "protocol Foo<T> extends Bar", "stereotype S <<meta>> #pink", "circle C".
        // A file of those was a sequence diagram; PlantUML draws a class diagram. Messages
        // like "record -> db : save" are not declarations. "circle" is also a description
        // element: next to an actor or a use case it stays a use case diagram, as in PlantUML
        // (components and deployment elements have claimed their files before this check).
        private static bool has_class_keyword_declaration(string code) {
            if (class_keyword_regex == null) {
                try {
                    class_keyword_regex = new Regex(
                        "^(exception|protocol|metaclass|stereotype|dataclass|record|circle|annotation|struct)" +
                        "\\s+(\"[^\"]+\"|[\\w.$:]+)" +
                        "(\\s*<[^>]*>)?(\\s+as\\s+(\"[^\"]+\"|[\\w.$]+))?" +
                        "(\\s+(extends|implements)\\s+[\\w.$:,<> ]+)?" +
                        "(\\s*<<[^>]*>>)*(\\s*#\\S+)?\\s*(\\{.*)?$");
                } catch (RegexError e) {
                    return false;
                }
            }
            bool description = has_line_starting(code, "actor ") || has_usecase_declaration(code);
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                MatchInfo info;
                if (class_keyword_regex.match(line, 0, out info)) {
                    if (info.fetch(1) != "circle" || !description) {
                        return true;
                    }
                }
            }
            return false;
        }

        private static bool is_note_start(string line) {
            return line.has_prefix("note ") || line.has_prefix("hnote ") || line.has_prefix("rnote ") ||
                   line.has_prefix("floating note");
        }

        private static bool is_note_end(string line) {
            return line.has_prefix("end note") || line.has_prefix("endnote") ||
                   line.has_prefix("end hnote") || line.has_prefix("endhnote") ||
                   line.has_prefix("end rnote") || line.has_prefix("endrnote");
        }

        // The source without note text: "note ... : text" lines, floating 'note "text" as N'
        // lines, and the bodies of notes closed by "end note". A note line without either
        // form only starts a body when an "end note" follows (a floating note used to switch
        // note-skipping on for the rest of the file).
        // Also without the continuation lines of a multi-line activity action (":Load" /
        // "object pool;"). Works on source in any case; the text keeps its case.
        private static string strip_notes(string text) {
            string[] lines = text.split("\n");
            var sb = new StringBuilder();
            bool in_note = false;
            bool in_action = false;
            for (int i = 0; i < lines.length; i++) {
                string line = lines[i].strip().down();
                if (in_note) {
                    if (is_note_end(line)) {
                        in_note = false;
                    }
                    continue;
                }
                if (in_action) {
                    if (ends_action_text(line)) {
                        in_action = false;
                    }
                    continue;
                }
                if (is_note_start(line)) {
                    string after = line.substring(line.index_of("note") + 4).strip();
                    if (!line.contains(":") && !after.has_prefix("\"")) {
                        for (int j = i + 1; j < lines.length; j++) {
                            if (is_note_end(lines[j].strip().down())) {
                                in_note = true;
                                break;
                            }
                        }
                    }
                    continue;
                }
                // ":text" without its terminator; ":Actor:" has a second colon. Only when a
                // later line ends the text before the diagram does.
                if (line.has_prefix(":") && line.index_of(":", 1) < 0 && !ends_action_text(line)) {
                    for (int j = i + 1; j < lines.length; j++) {
                        string next = lines[j].strip();
                        if (next.has_prefix("@end")) {
                            break;
                        }
                        if (ends_action_text(next)) {
                            in_action = true;
                            break;
                        }
                    }
                }
                sb.append(lines[i]);
                sb.append_c('\n');
            }
            return sb.str;
        }

        private static bool ends_action_text(string line) {
            if (line.length < 1) {
                return false;
            }
            char last = line[line.length - 1];
            return last == ';' || last == '|' || last == '<' || last == '>' ||
                   last == '/' || last == '\\' || last == ']' || last == '}';
        }

        // "[Component]" at a line start; "[-> A" / "[<- A" are sequence messages from outside
        private static bool has_bracket_component_line(string code) {
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("[") && !is_border_message_start(line)) {
                    return true;
                }
            }
            return false;
        }

        // An unindented "[Component]" line after the first line. "[-> A" / "[<- A" are sequence
        // messages from outside the diagram, not components: a file of those and "A ->] : x"
        // lines was a component diagram.
        private static bool has_unindented_bracket_line(string lower) {
            string[] lines = lower.split("\n");
            for (int i = 1; i < lines.length; i++) {
                string line = lines[i];
                if (line.has_prefix("[") && !is_border_message_start(line)) {
                    return true;
                }
            }
            return false;
        }

        private static bool is_border_message_start(string line) {
            return line.has_prefix("[-") || line.has_prefix("[<") ||
                   line.has_prefix("[o-") || line.has_prefix("[x-");
        }

        // "start" / "stop" or a one-line ":action;"
        private static bool has_activity_line(string code) {
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (line == "start" || line == "stop" ||
                    (line.length > 2 && line[0] == ':' && line.has_suffix(";"))) {
                    return true;
                }
            }
            return false;
        }

        // "usecase X" or a "(Use case)" line (not "()" interfaces or legacy "(*)")
        private static bool has_usecase_declaration(string code) {
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("usecase ") || line.has_prefix("usecase/") || line.has_prefix("usecase(")) {
                    return true;
                }
                if (line.has_prefix("(") && !line.has_prefix("()") && !line.has_prefix("(*)") &&
                    line.index_of(")") > 1) {
                    return true;
                }
            }
            // "User --> (Login)": a use case used in a link. An actor file with a cloud or
            // node and such links was a component diagram.
            return has_usecase_link_line(code);
        }

        private static Regex? sequence_message_regex = null;

        // Every line is something a sequence diagram accepts — participant declarations
        // (queue, collections, database, ...), messages with sequence arrows, sequence
        // keywords — and there is at least one message. PlantUML tries the sequence
        // diagram first, so such a file is a sequence diagram.
        private static bool is_sequence_only(string code) {
            if (sequence_message_regex == null) {
                try {
                    sequence_message_regex = new Regex(
                        "^(\\[|\\?|\"[^\"]+\"|[\\w.$]+)\\s*[ox]?" +
                        "(<{1,2}[\\\\/]?-{1,2}(\\[[^\\]]*\\])?-?(>{1,2}|[\\\\/]{1,2})?|" +
                        "-{1,2}(\\[[^\\]]*\\])?-?(>{1,2}|[\\\\/]{1,2}))" +
                        "[ox]?\\s*(\\]|\\?|\"[^\"]+\"|[\\w.$]+)\\s*(\\+\\+|--|\\*\\*|!!)?\\s*(:.*)?$");
                } catch (RegexError e) {
                    return false;
                }
            }
            bool message = false;
            bool declaration = false;
            int skin_depth = 0;
            foreach (string raw in code.split("\n")) {
                string line = raw.strip();
                if (skin_depth > 0) {
                    if (line.has_suffix("{")) {
                        skin_depth++;
                    } else if (line.has_prefix("}")) {
                        skin_depth--;
                    }
                    continue;
                }
                if (line.length == 0 || line[0] == '\'' || line[0] == '@' || line[0] == '!') {
                    continue;
                }
                if (line.has_prefix("skinparam")) {
                    if (line.has_suffix("{")) {
                        skin_depth = 1;
                    }
                    continue;
                }
                bool known = false;
                foreach (string kw in new string[] { "participant ", "actor ", "boundary ", "control ", "entity ",
                                                     "database ", "collections ", "queue " }) {
                    if (line.has_prefix(kw) && !line.contains("{")) {
                        known = true;
                        declaration = true;
                        break;
                    }
                }
                foreach (string kw in new string[] { "title", "hide ", "show ", "autonumber", "activate ",
                                                     "deactivate ", "destroy ", "create ", "return", "...",
                                                     "|||", "==", "alt", "else", "end", "loop", "opt", "par",
                                                     "break", "critical", "group", "ref over", "box", "delay",
                                                     "newpage", "header", "footer", "caption", "scale " }) {
                    if (known || line.has_prefix(kw)) {
                        known = true;
                        break;
                    }
                }
                if (known) {
                    continue;
                }
                if (sequence_message_regex.match(line)) {
                    message = true;
                    continue;
                }
                return false;
            }
            // A file of declarations only ("actor Actor", "database Database") is a
            // sequence diagram in PlantUML too; it was a use case / component diagram
            return message || declaration;
        }

        // A line that is a use case "(Name) as/arrow/<<stereo>>" or a colon actor
        // ":Name: as X". Note text is skipped: prose lines like "(default 5 min)"
        // made component diagrams look like use cases. "(*)" is legacy activity syntax.
        private static bool contains_usecase_shorthand(string lower) {
            if (has_usecase_link_line(strip_notes(lower))) {
                return true;
            }
            foreach (string raw in strip_notes(lower).split("\n")) {
                string line = raw.strip();
                if (line.has_prefix("(")) {
                    int close = line.index_of(")");
                    if (close > 1 && line.substring(1, close - 1).strip().length > 0 &&
                        line.substring(1, close - 1).strip() != "*") {
                        string rest = line.substring(close + 1).strip();
                        if (rest.has_prefix("as ") || rest.has_prefix("-") ||
                            rest.has_prefix(".") || rest.has_prefix("<")) {
                            return true;
                        }
                    }
                } else if (line.has_prefix(":") && !line.contains(";")) {
                    int close = line.index_of(":", 1);
                    if (close > 1 && line.substring(close + 1).strip().has_prefix("as ")) {
                        return true;
                    }
                }
            }
            return false;
        }

        /**
         * The diagram type named by a Mermaid document's first line: front matter
         * ("---" ... "---"), "%%" comments and "%%{...}%%" directives (also over
         * several lines) are skipped. UNKNOWN when that line names no known type.
         */
        public static DiagramType mermaid_header_type(string source) {
            bool front_matter = false;
            bool directive = false;
            bool seen = false;
            foreach (string raw in source.split("\n")) {
                string line = raw.strip();
                if (front_matter) {
                    if (line == "---") {
                        front_matter = false;
                    }
                    continue;
                }
                if (directive) {
                    if (line.contains("}%%")) {
                        directive = false;
                    }
                    continue;
                }
                if (line.length == 0) {
                    continue;
                }
                if (!seen && line == "---") {
                    seen = true;
                    front_matter = true;
                    continue;
                }
                seen = true;
                if (line.has_prefix("%%{") && !line.contains("}%%")) {
                    directive = true;
                    continue;
                }
                if (line.has_prefix("%%")) {
                    continue;
                }
                string lower = line.down();
                int end = 0;
                while (end < lower.length && !lower[end].isspace() && lower[end] != ':' &&
                       lower[end] != ';' && lower[end] != '{') {
                    end++;
                }
                return mermaid_keyword_type(lower.substring(0, end));
            }
            return DiagramType.UNKNOWN;
        }

        private static DiagramType mermaid_keyword_type(string word) {
            switch (word) {
                case "flowchart": case "flowchart-elk": case "graph":
                    return DiagramType.MERMAID_FLOWCHART;
                case "sequencediagram": return DiagramType.MERMAID_SEQUENCE;
                case "statediagram": case "statediagram-v2": return DiagramType.MERMAID_STATE;
                case "classdiagram": case "classdiagram-v2": return DiagramType.MERMAID_CLASS;
                case "erdiagram": return DiagramType.MERMAID_ER;
                case "gantt": return DiagramType.MERMAID_GANTT;
                case "pie": return DiagramType.MERMAID_PIE;
                case "journey": return DiagramType.MERMAID_USER_JOURNEY;
                case "gitgraph": return DiagramType.MERMAID_GIT_GRAPH;
                case "mindmap": return DiagramType.MERMAID_MINDMAP;
                case "timeline": return DiagramType.MERMAID_TIMELINE;
                case "quadrantchart": return DiagramType.MERMAID_QUADRANT;
                case "xychart": case "xychart-beta": return DiagramType.MERMAID_XYCHART;
                case "kanban": return DiagramType.MERMAID_KANBAN;
                case "sankey": case "sankey-beta": return DiagramType.MERMAID_SANKEY;
                case "requirementdiagram": return DiagramType.MERMAID_REQUIREMENT;
                case "block-beta": return DiagramType.MERMAID_BLOCK;
                case "packet": case "packet-beta": return DiagramType.MERMAID_PACKET;
                case "c4context": case "c4container": case "c4component": case "c4dynamic":
                case "c4deployment":
                    return DiagramType.MERMAID_C4;
                case "architecture-beta": return DiagramType.MERMAID_ARCHITECTURE;
                case "zenuml": return DiagramType.MERMAID_ZENUML;
                case "radar": case "radar-beta": return DiagramType.MERMAID_RADAR;
                case "treemap": case "treemap-beta": return DiagramType.MERMAID_TREEMAP;
                default: return DiagramType.UNKNOWN;
            }
        }

        public static DiagramType detect_mermaid(string source) {
            // The first line names the diagram: "sequenceDiagram" with a message
            // "A->>B: draw flowchart" was a flowchart.
            DiagramType header = mermaid_header_type(source);
            if (header != DiagramType.UNKNOWN) {
                return header;
            }
            string lower = source.down();

            if (lower.contains("flowchart") || lower.has_prefix("flowchart") ||
                lower.has_prefix("graph ")) {
                return DiagramType.MERMAID_FLOWCHART;
            }
            if (lower.contains("sequencediagram") || lower.has_prefix("sequencediagram")) {
                return DiagramType.MERMAID_SEQUENCE;
            }
            if (lower.contains("statediagram-v2") || lower.contains("statediagram")) {
                return DiagramType.MERMAID_STATE;
            }
            if (lower.contains("classdiagram") || lower.has_prefix("classdiagram")) {
                return DiagramType.MERMAID_CLASS;
            }
            if (lower.contains("erdiagram") || lower.has_prefix("erdiagram")) {
                return DiagramType.MERMAID_ER;
            }
            if (lower.contains("gantt") || lower.has_prefix("gantt")) {
                return DiagramType.MERMAID_GANTT;
            }
            if (lower.has_prefix("pie") || lower.contains("\npie")) {
                return DiagramType.MERMAID_PIE;
            }
            if (lower.has_prefix("journey") || lower.contains("\njourney")) {
                return DiagramType.MERMAID_USER_JOURNEY;
            }
            if (lower.has_prefix("gitgraph") || lower.contains("\ngitgraph")) {
                return DiagramType.MERMAID_GIT_GRAPH;
            }
            if (lower.has_prefix("mindmap") || lower.contains("\nmindmap")) {
                return DiagramType.MERMAID_MINDMAP;
            }
            if (lower.has_prefix("timeline") || lower.contains("\ntimeline")) {
                return DiagramType.MERMAID_TIMELINE;
            }
            if (lower.has_prefix("quadrantchart") || lower.contains("\nquadrantchart")) {
                return DiagramType.MERMAID_QUADRANT;
            }
            if (lower.has_prefix("xychart-beta") || lower.has_prefix("xychart") ||
                lower.contains("\nxychart-beta") || lower.contains("\nxychart")) {
                return DiagramType.MERMAID_XYCHART;
            }
            if (lower.has_prefix("kanban") || lower.contains("\nkanban")) {
                return DiagramType.MERMAID_KANBAN;
            }
            if (lower.has_prefix("sankey") || lower.contains("\nsankey")) {
                return DiagramType.MERMAID_SANKEY;
            }
            if (lower.has_prefix("requirementdiagram") || lower.contains("\nrequirementdiagram")) {
                return DiagramType.MERMAID_REQUIREMENT;
            }
            if (lower.has_prefix("block-beta") || lower.contains("\nblock-beta")) {
                return DiagramType.MERMAID_BLOCK;
            }
            if (lower.has_prefix("packet-beta") || lower.contains("\npacket-beta") ||
                lower.has_prefix("packet\n") || lower.contains("\npacket\n")) {
                return DiagramType.MERMAID_PACKET;
            }
            if (lower.has_prefix("c4context") || lower.has_prefix("c4container") ||
                lower.has_prefix("c4component") || lower.has_prefix("c4dynamic") ||
                lower.has_prefix("c4deployment") ||
                lower.contains("\nc4context") || lower.contains("\nc4container")) {
                return DiagramType.MERMAID_C4;
            }
            if (lower.has_prefix("architecture-beta") || lower.contains("\narchitecture-beta")) {
                return DiagramType.MERMAID_ARCHITECTURE;
            }
            if (lower.has_prefix("zenuml") || lower.contains("\nzenuml")) {
                return DiagramType.MERMAID_ZENUML;
            }
            if (lower.has_prefix("radar-beta") || lower.contains("\nradar-beta") ||
                lower.has_prefix("radar\n") || lower.contains("\nradar\n")) {
                return DiagramType.MERMAID_RADAR;
            }
            if (lower.has_prefix("treemap-beta") || lower.contains("\ntreemap-beta") ||
                lower.has_prefix("treemap\n") || lower.contains("\ntreemap\n")) {
                return DiagramType.MERMAID_TREEMAP;
            }
            return DiagramType.UNKNOWN;
        }
    }
}
