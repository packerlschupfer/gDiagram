namespace GDiagram {

    /**
     * What the properties panel shows for one diagram element.
     *
     * Values come from the element's declaration line when it has one (so the
     * panel shows what is written, including colours a parser normalised) and
     * from the AST otherwise.
     */
    public class ElementInfo : Object {
        public DiagramType diagram_type = DiagramType.UNKNOWN;
        public string kind = "Element";       // "Class", "Actor", "Use case", ...
        public string id = "";                // lookup key: the alias, else the name
        public string? label = null;          // display label
        public string? alias = null;          // the "as X" code, when written
        public string? stereotype = null;     // inner text of <<x>>
        public string? color = null;          // inline colour as written, with '#'
        public string? note = null;           // text of notes attached to the element
        public int line = 0;                  // 1-based declaration (or first use) line
        public bool declared = false;         // has a declaration line of its own
        public bool editable = false;         // false: read-only info for an uncovered type
        public string keyword = "";           // declaration keyword ("class", "participant")
        // Which edits the element's declaration form can carry; only meaningful when
        // editable. The properties panel hides the rows for edits that would always fail.
        public bool can_label = false;
        public bool can_stereotype = false;
        public bool can_color = false;
        public bool can_rename = false;
        // Why some edits are unavailable (e.g. the declaration lives in an !include'd
        // file), null when nothing is restricted
        public string? read_only_reason = null;
    }

    /**
     * Reads a clicked diagram element from the parsed AST and rewrites the source
     * text for property edits. GTK-free; the properties panel is a thin view on it.
     *
     * The source text stays the single source of truth: every apply function takes
     * the current text and returns the NEW text, or null when the edit does not apply
     * (invalid value, or a declaration form that cannot carry it). A no-op edit
     * returns the text unchanged.
     *
     * Edits act on the element's declaration line, found by id, and replace only the
     * part they change (label, stereotype or colour), leaving the rest as written.
     * An element that is only used in relationships gets a declaration line of its own
     * for label/stereotype/colour edits. It is inserted directly above the first line
     * that uses the element, with that line's indentation, so an element used inside a
     * package or container body stays in that scope. In sequence diagrams this can
     * move the participant before the other participant of that first message.
     *
     * Covered for inspect and edit: PlantUML class (incl. IE "entity"), component,
     * use case (actor + usecase), state, sequence participant, object, component/deployment element
     * and ER entity. Other diagram types get read-only info (kind + name + line).
     */
    public class ElementInspector : Object {

        private enum NameStyle {
            BARE,      // class Foo
            QUOTED,    // class "My Class"
            BRACKET,   // [Component]
            PAREN,     // (Use case)
            COLON      // :Actor:
        }

        // One declaration line, split into byte spans so an edit replaces exactly one part
        private class Decl : Object {
            public int line_index;
            public string keyword = "";
            public NameStyle style;
            public int name_start;
            public int name_end;          // after the closing delimiter
            public string name = "";      // inner text (a generic class: without "<T>")
            public int tail_end;          // after a business "/" marker
            public int alias_ws = -1;     // start of the whitespace before "as"
            public int alias_start = -1;
            public int alias_end = -1;    // after the alias, including generics ("Foo<T>")
            public string? alias = null;
            public bool alias_quoted = false;
            public int stereo_ws = -1;
            public int stereo_start = -1;
            public int stereo_first_end = -1;   // after the first "<<x>>"
            public int stereo_end = -1;         // after the last adjacent "<<y>>"
            public string? stereotype = null;   // the first stereotype
            public int color_ws = -1;
            public int color_start = -1;
            public int color_end = -1;
            public string? color = null;
            public int border_ws = -1;    // "##[dashed]red": a border-only colour
            public int order_end = -1;    // sequence "order 10"

            // "class C as \"Label\"": the quoted side is the label, the bare name the id
            public bool label_in_alias() {
                return alias != null && alias_quoted && style != NameStyle.QUOTED;
            }

            public string get_id() {
                if (alias == null || label_in_alias()) return name;
                return alias;
            }

            public string get_label() {
                if (label_in_alias()) return alias;
                return name;
            }

            // Where a new " <<x>>" or " #color" goes: after the name, alias and stereotype.
            // A colour also goes after "order N" (PlantUML rejects "#red order 10") but
            // before a border-only "##colour".
            public int insert_pos(bool after_stereotype) {
                int pos = int.max(tail_end, alias_end);
                if (after_stereotype) {
                    pos = int.max(pos, stereo_end);
                    pos = int.max(pos, order_end);
                    if (border_ws >= 0 && border_ws >= int.max(tail_end, alias_end) && border_ws < pos) {
                        pos = border_ws;
                    }
                }
                return pos;
            }
        }

        // An element found in the AST
        private class Found : Object {
            public string kind = "Element";
            public string id = "";
            public string? name = null;   // name as parsed, when it differs from the id
            public string? label = null;
            public string? alias = null;
            public string? stereotype = null;
            public string? color = null;
            public int line = 0;
            public string keyword = "";
        }

        // ==================== Inspect ====================

        public static bool is_covered(DiagramType type) {
            if (MermaidElementInspector.covers(type)) return true;
            switch (type) {
                case DiagramType.CLASS:
                case DiagramType.COMPONENT:
                case DiagramType.USECASE:
                case DiagramType.STATE:
                case DiagramType.SEQUENCE:
                case DiagramType.OBJECT:
                case DiagramType.ER_DIAGRAM:
                    return true;
                default:
                    return false;
            }
        }

        /**
         * Strips the suffixes renderers add to synthesized DOT node ids: sequence
         * lifelines "Foo_top"/"Foo_bottom" and message anchors "Foo_m0".
         */
        public static string strip_synthetic_suffix(string element_name) {
            if (element_name.has_suffix("_top")) {
                return element_name.substring(0, element_name.length - 4);
            }
            if (element_name.has_suffix("_bottom")) {
                return element_name.substring(0, element_name.length - 7);
            }
            int m = element_name.last_index_of("_m");
            if (m > 0 && is_all_digits(element_name.substring(m + 2))) {
                return element_name.substring(0, m);
            }
            return element_name;
        }

        /**
         * Describes the element a click region named `element_name` belongs to.
         * Returns null when a covered diagram type has no such element (e.g. after it
         * was renamed or deleted, or for a note/pseudo-state node).
         */
        public static ElementInfo? inspect(DiagramType type, Object? ast, string element_name,
                                           int source_line, string source) {
            if (element_name.length == 0) return null;
            if (MermaidElementInspector.covers(type)) {
                return MermaidElementInspector.inspect(type, ast, element_name, source_line, source);
            }

            if (!is_covered(type)) {
                var ro = new ElementInfo();
                ro.diagram_type = type;
                ro.id = strip_synthetic_suffix(element_name);
                ro.label = ro.id;
                ro.line = source_line;
                return ro;
            }
            if (ast == null) return null;

            Found? found = find_in_ast(type, ast, element_name);
            if (found == null) {
                string base_name = strip_synthetic_suffix(element_name);
                if (base_name != element_name) found = find_in_ast(type, ast, base_name);
            }
            if (found == null) return null;

            var info = new ElementInfo();
            info.diagram_type = type;
            info.editable = true;
            info.can_label = info.can_stereotype = info.can_color = info.can_rename = true;
            info.kind = found.kind;
            info.id = found.id;
            info.keyword = found.keyword;
            info.label = found.label ?? found.id;
            info.alias = found.alias;
            info.stereotype = found.stereotype;
            info.color = found.color;
            info.line = found.line;

            string[] lines = source.split("\n");
            bool[] code = code_mask(type, lines);
            var decl = find_declaration(type, lines, code, found.id, found.line);
            if (decl != null) {
                info.declared = true;
                info.line = decl.line_index + 1;
                info.label = decl.get_label();
                info.alias = decl.alias != null ? decl.get_id() : null;
                if (decl.stereotype != null) info.stereotype = decl.stereotype;
                if (decl.color != null || decl.border_ws >= 0) info.color = decl.color;
                if (decl.keyword.length > 0) info.keyword = decl.keyword.ascii_down();
            } else {
                int use = first_use_line(type, lines, code, found.id);
                if (info.line <= 0 || info.line > lines.length) info.line = use + 1;
                if (has_include(lines, code)) {
                    // The AST comes from the preprocessed text: an element this file never
                    // declares may be declared in an included file. A rename here would
                    // orphan that declaration; a label/stereotype/colour it already carries
                    // came from there, and a second declaration here would fight it.
                    bool styled = found.color != null || found.stereotype != null ||
                                  (found.label != null && found.label != found.id);
                    info.can_rename = false;
                    if (use < 0 || styled) {
                        info.can_label = info.can_stereotype = info.can_color = false;
                        info.read_only_reason = "Declared in an included file: edit it there";
                    } else {
                        info.read_only_reason = "May be declared in an included file: rename it there";
                    }
                }
            }
            info.note = find_note(ast, found);
            return info;
        }

        // ==================== Edits ====================

        /**
         * Sets the display label. With no alias written, the bare name moves into the
         * alias so references keep working: `class Foo` -> `class "New" as Foo`.
         * An empty label removes an explicit label again.
         * A shorthand or quoted name without an alias moves into the alias the same way:
         * `[Database]` -> `[Main DB] as Database`. Not applicable (null) when that name is
         * not a plain identifier (`usecase "Log in"`, `[Web Server]`): rename it first.
         */
        public static string? set_label(ElementInfo info, string source, string new_label) {
            if (!info.editable || !info.can_label) return null;
            if (MermaidElementInspector.covers(info.diagram_type)) {
                return MermaidElementInspector.set_label(info, source, new_label);
            }
            string label = new_label.strip();
            if (label.contains("\n") || label.contains("\"")) return null;

            string[] lines = source.split("\n");
            bool[] code = code_mask(info.diagram_type, lines);
            var decl = find_declaration(info.diagram_type, lines, code, info.id, info.line);
            if (decl == null) {
                if (label.length == 0 || label == info.id) return source;
                if (!is_identifier(info.id)) return null;
                return insert_declaration(info, lines, code,
                    "%s \"%s\" as %s".printf(info.keyword, label, info.id));
            }

            string line = lines[decl.line_index];
            string result;
            if (decl.label_in_alias()) {
                if (label.length == 0) {
                    result = splice(line, decl.alias_ws, decl.alias_end, "");
                } else {
                    result = splice(line, decl.alias_start, decl.alias_end, "\"%s\"".printf(label));
                }
            } else if (decl.alias != null) {
                if (label.length == 0) {
                    // Collapse `"Label" as C` to `C` (shorthand: `[C]`)
                    if (decl.alias_quoted) return null;
                    // The alias as written, generics included ("Foo<T>")
                    string alias_text = line.substring(decl.alias_start, decl.alias_end - decl.alias_start);
                    string id_text = decl.style == NameStyle.QUOTED || decl.style == NameStyle.BARE
                        ? (is_identifier(decl.alias) ? alias_text : "\"%s\"".printf(decl.alias))
                        : wrap(decl.style, decl.alias);
                    result = splice(line, decl.name_start, decl.alias_end, id_text);
                } else {
                    string? token = label_token(decl.style, label);
                    if (token == null) return null;
                    result = splice(line, decl.name_start, decl.name_end, token);
                }
            } else {
                if (label.length == 0 || label == decl.name) return source;
                if (!is_identifier(decl.name)) return null;
                // The label goes in the declaration's own delimiters (quotes for a bare
                // name), a business "/" marker stays with it, and the name becomes the alias
                string? token = decl.style == NameStyle.BARE
                    ? "\"%s\"".printf(label) : label_token(decl.style, label);
                if (token == null) return null;
                string marker = line.substring(decl.name_end, decl.tail_end - decl.name_end);
                string name_text = decl.style == NameStyle.BARE
                    ? line.substring(decl.name_start, decl.name_end - decl.name_start) : decl.name;
                result = splice(line, decl.name_start, decl.tail_end,
                    "%s%s as %s".printf(token, marker, name_text));
            }
            lines[decl.line_index] = result;
            return string.joinv("\n", lines);
        }

        /**
         * Adds, changes or (with an empty value) removes the `<<stereotype>>`.
         * Accepts "name" or "<<name>>". With several stereotypes (`<<A>> <<B>>`) the
         * first one is the element's stereotype: it is the one changed or removed, the
         * others stay as written.
         */
        public static string? set_stereotype(ElementInfo info, string source, string new_stereotype) {
            if (!info.editable || !info.can_stereotype) return null;
            if (MermaidElementInspector.covers(info.diagram_type)) {
                return MermaidElementInspector.set_stereotype(info, source, new_stereotype);
            }
            string s = new_stereotype.strip();
            if (s.has_prefix("<<")) s = s.substring(2);
            if (s.has_suffix(">>")) s = s.substring(0, s.length - 2);
            s = s.strip();
            if (s.contains("\n") || s.contains("<<") || s.contains(">>")) return null;

            string[] lines = source.split("\n");
            bool[] code = code_mask(info.diagram_type, lines);
            var decl = find_declaration(info.diagram_type, lines, code, info.id, info.line);
            if (decl == null) {
                if (s.length == 0) return source;
                if (!is_identifier(info.id)) return null;
                return insert_declaration(info, lines, code,
                    "%s %s <<%s>>".printf(info.keyword, info.id, s));
            }

            string line = lines[decl.line_index];
            if (decl.stereo_start >= 0) {
                // Only the first stereotype is edited; "<<A>> <<B>>" keeps its "<<B>>"
                if (s.length == 0) {
                    line = splice(line, decl.stereo_ws, decl.stereo_first_end, "");
                } else {
                    line = splice(line, decl.stereo_start, decl.stereo_first_end, "<<%s>>".printf(s));
                }
            } else {
                if (s.length == 0) return source;
                line = splice(line, decl.insert_pos(false), decl.insert_pos(false), " <<%s>>".printf(s));
            }
            lines[decl.line_index] = line;
            return string.joinv("\n", lines);
        }

        /**
         * Adds, changes or (with an empty value) removes the inline `#color`.
         * Accepts "red", "#red", "#FF0000" or "FF0000"-style hex written with '#'.
         */
        public static string? set_color(ElementInfo info, string source, string new_color) {
            if (!info.editable || !info.can_color) return null;
            if (MermaidElementInspector.covers(info.diagram_type)) {
                return MermaidElementInspector.set_color(info, source, new_color);
            }
            string c = new_color.strip();
            if (c.length > 0 && !c.has_prefix("#")) c = "#" + c;
            if (c.length == 1 || !is_color_text(c)) return null;

            string[] lines = source.split("\n");
            bool[] code = code_mask(info.diagram_type, lines);
            var decl = find_declaration(info.diagram_type, lines, code, info.id, info.line);
            if (decl == null) {
                if (c.length == 0) return source;
                if (!is_identifier(info.id)) return null;
                return insert_declaration(info, lines, code,
                    "%s %s %s".printf(info.keyword, info.id, c));
            }

            string line = lines[decl.line_index];
            if (decl.color_start >= 0) {
                // "#pink;line:red": only the fill part changes, the line/text styling stays
                string written = decl.color.substring(1);
                int semi = written.index_of_char(';');
                string first = semi >= 0 ? written.substring(0, semi) : written;
                string rest = semi >= 0 ? written.substring(semi + 1) : "";
                string first_lower = first.ascii_down();
                bool has_fill = !(first_lower.has_prefix("line") || first_lower.has_prefix("text"));
                string replacement;
                if (!has_fill) {
                    if (c.length == 0) return source;
                    replacement = c + ";" + written;
                } else if (c.length == 0) {
                    replacement = rest.length > 0 ? "#" + rest : "";
                } else {
                    replacement = rest.length > 0 ? c + ";" + rest : c;
                }
                if (replacement.length == 0) {
                    line = splice(line, decl.color_ws, decl.color_end, "");
                } else {
                    line = splice(line, decl.color_start, decl.color_end, replacement);
                }
            } else {
                if (c.length == 0) return source;
                line = splice(line, decl.insert_pos(true), decl.insert_pos(true), " " + c);
            }
            lines[decl.line_index] = line;
            return string.joinv("\n", lines);
        }

        /**
         * Changes the element id, updating every reference in the file: whole words, and
         * whole "quoted" / [bracket] / (paren) / :colon: tokens whose text is exactly the
         * id (`participant "Bob"` -> `participant "Rob"`). Skipped: labels (`[Web Server]
         * as WS`, `X as "Label"`), words inside delimited names, `'` line comments,
         * `/' '/` block comments, note / legend / ref bodies, title/header/footer/caption
         * text, sequence group labels, dividers, delays and return values, multi-line
         * `[ ... ]` descriptions, `<<stereotypes>>`, `#colours` and label text after a
         * `:` separator. An id that is not a single word ("Log in", [Web Server]) is
         * renamed in its delimiters. Returns null when the new id is invalid or already
         * written in any form.
         */
        public static string? rename(ElementInfo info, string source, string new_id) {
            if (!info.editable || !info.can_rename) return null;
            if (MermaidElementInspector.covers(info.diagram_type)) {
                return MermaidElementInspector.rename(info, source, new_id);
            }
            string to = new_id.strip();
            if (to == info.id) return source;
            if (!is_word_id(info.id)) return rename_delimited(info.diagram_type, info.id, source, to);
            if (!is_word_id(to)) return null;

            string[] lines = source.split("\n");
            bool[] code = code_mask(info.diagram_type, lines);
            int hits = 0;
            int clashes = 0;
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                lines[i] = rename_in_line(info.diagram_type, lines[i], info.id, to, ref hits, ref clashes);
            }
            if (hits == 0 || clashes > 0) return null;
            return string.joinv("\n", lines);
        }

        // ==================== AST lookup ====================

        private static bool name_matches(string wanted, string? candidate) {
            if (candidate == null || candidate.length == 0) return false;
            return wanted == candidate || wanted == RenderUtils.sanitize_id(candidate);
        }

        // "GDIAGRAM_COMPONENT_TYPE_COMPONENT" -> "component"
        private static string enum_word(string enum_name) {
            int idx = enum_name.last_index_of("_TYPE_");
            string word = idx >= 0 ? enum_name.substring(idx + 6) : enum_name;
            return word.ascii_down();
        }

        // "end_state" -> "End state"
        private static string kind_label(string word) {
            string s = word.replace("_", " ");
            if (s.length == 0) return s;
            return s.substring(0, 1).ascii_up() + s.substring(1);
        }

        private static Found? find_in_ast(DiagramType type, Object ast, string name) {
            // The AST class is checked too: a type/AST mismatch must not become a bad cast
            if (type == DiagramType.CLASS && ast is ClassDiagram) {
                return find_class((ClassDiagram) ast, name);
            }
            if (type == DiagramType.SEQUENCE && ast is SequenceDiagram) {
                return find_participant((SequenceDiagram) ast, name);
            }
            if (type == DiagramType.USECASE && ast is UseCaseDiagram) {
                return find_usecase_element((UseCaseDiagram) ast, name);
            }
            if (type == DiagramType.STATE && ast is StateDiagram) {
                return find_state_in(((StateDiagram) ast).states, name);
            }
            if (type == DiagramType.COMPONENT && ast is ComponentDiagram) {
                return find_component_element((ComponentDiagram) ast, name);
            }
            if (type == DiagramType.OBJECT && ast is ObjectDiagram) {
                return find_object_element((ObjectDiagram) ast, name);
            }
            if (type == DiagramType.ER_DIAGRAM && ast is ERDiagram) {
                return find_entity((ERDiagram) ast, name);
            }
            return null;
        }

        private static Found? find_class(ClassDiagram d, string name) {
            foreach (var c in d.classes) {
                if (c.is_diamond || c.removed) continue;
                if (!name_matches(name, c.name) && name != c.get_id()) continue;
                var f = new Found();
                f.id = c.name;
                f.label = c.display_name ?? c.name;
                f.stereotype = c.stereotype;
                f.color = c.color;
                f.line = c.source_line;
                switch (c.class_type) {
                    case ClassType.INTERFACE: f.kind = "Interface"; f.keyword = "interface"; break;
                    case ClassType.ABSTRACT: f.kind = "Abstract class"; f.keyword = "abstract class"; break;
                    case ClassType.ENUM: f.kind = "Enum"; f.keyword = "enum"; break;
                    case ClassType.ANNOTATION: f.kind = "Annotation"; f.keyword = "annotation"; break;
                    case ClassType.ENTITY: f.kind = "Entity"; f.keyword = "entity"; break;
                    case ClassType.STRUCT: f.kind = "Struct"; f.keyword = "struct"; break;
                    case ClassType.EXCEPTION: f.kind = "Exception"; f.keyword = "exception"; break;
                    case ClassType.PROTOCOL: f.kind = "Protocol"; f.keyword = "protocol"; break;
                    case ClassType.METACLASS: f.kind = "Metaclass"; f.keyword = "metaclass"; break;
                    case ClassType.STEREOTYPE: f.kind = "Stereotype"; f.keyword = "stereotype"; break;
                    case ClassType.DATACLASS: f.kind = "Dataclass"; f.keyword = "dataclass"; break;
                    case ClassType.RECORD: f.kind = "Record"; f.keyword = "record"; break;
                    case ClassType.CIRCLE: f.kind = "Circle"; f.keyword = "circle"; break;
                    default: f.kind = "Class"; f.keyword = "class"; break;
                }
                return f;
            }
            return null;
        }

        private static Found? find_participant(SequenceDiagram d, string name) {
            foreach (var p in d.participants) {
                if (!name_matches(name, p.get_id()) && !name_matches(name, p.name)) continue;
                var f = new Found();
                f.id = p.get_id();
                f.name = p.name;
                f.alias = p.alias;
                f.label = p.alias != null ? p.name : (p.display_label ?? p.name);
                f.stereotype = p.stereotype;
                f.color = p.color;
                f.line = p.source_line;
                f.keyword = enum_word(p.participant_type.to_string());
                f.kind = kind_label(f.keyword);
                return f;
            }
            return null;
        }

        private static Found? find_usecase_element(UseCaseDiagram d, string name) {
            var actors = new Gee.ArrayList<UseCaseActor>();
            var use_cases = new Gee.ArrayList<UseCase>();
            actors.add_all(d.actors);
            use_cases.add_all(d.use_cases);
            foreach (var pkg in d.packages) {
                actors.add_all(pkg.actors);
                use_cases.add_all(pkg.use_cases);
            }
            foreach (var a in actors) {
                if (!name_matches(name, a.get_id()) && !name_matches(name, a.name)) continue;
                var f = new Found();
                f.kind = "Actor";
                f.keyword = "actor";
                f.id = a.get_id();
                f.name = a.name;
                f.alias = a.alias;
                f.label = a.name;
                f.stereotype = a.stereotype;
                f.color = a.color;
                f.line = a.source_line;
                return f;
            }
            foreach (var u in use_cases) {
                if (!name_matches(name, u.get_id()) && !name_matches(name, u.name)) continue;
                var f = new Found();
                f.kind = "Use case";
                f.keyword = "usecase";
                f.id = u.get_id();
                f.name = u.name;
                f.alias = u.alias;
                f.label = u.name;
                f.stereotype = u.stereotype;
                f.color = u.color;
                f.line = u.source_line;
                return f;
            }
            return null;
        }

        private static Found? find_state_in(Gee.ArrayList<State> states, string name) {
            foreach (var s in states) {
                if (!s.id.has_prefix("_") && name_matches(name, s.id)) {
                    var f = new Found();
                    f.id = s.id;
                    f.label = s.label ?? s.id;
                    f.stereotype = s.stereotype;
                    f.color = s.color;
                    f.line = s.source_line;
                    f.keyword = "state";
                    switch (s.state_type) {
                        case StateType.CHOICE: f.kind = "Choice"; break;
                        case StateType.FORK: f.kind = "Fork"; break;
                        case StateType.JOIN: f.kind = "Join"; break;
                        case StateType.END_STATE: f.kind = "End state"; break;
                        case StateType.ENTRY_POINT: f.kind = "Entry point"; break;
                        case StateType.EXIT_POINT: f.kind = "Exit point"; break;
                        case StateType.COMPOSITE: f.kind = "Composite state"; break;
                        default: f.kind = "State"; break;
                    }
                    return f;
                }
                var nested = find_state_in(s.nested_states, name);
                if (nested != null) return nested;
            }
            return null;
        }

        private static Found? find_component_in(Gee.ArrayList<Component> comps, string name) {
            foreach (var c in comps) {
                if (name_matches(name, c.alias) || name_matches(name, c.id)) {
                    var f = new Found();
                    f.id = c.alias ?? c.id;
                    f.name = c.id;
                    f.alias = c.alias;
                    f.label = c.label ?? c.id;
                    f.stereotype = c.stereotype;
                    f.color = c.color;
                    f.line = c.source_line;
                    f.keyword = enum_word(c.component_type.to_string());
                    f.kind = kind_label(f.keyword);
                    return f;
                }
                var child = find_component_in(c.children, name);
                if (child != null) return child;
            }
            return null;
        }

        private static Found? find_component_element(ComponentDiagram d, string name) {
            var f = find_component_in(d.components, name);
            if (f != null) return f;
            foreach (var iface in d.interfaces) {
                if (!name_matches(name, iface.alias) && !name_matches(name, iface.id)) continue;
                f = new Found();
                f.kind = "Interface";
                f.keyword = "interface";
                f.id = iface.alias ?? iface.id;
                f.name = iface.id;
                f.alias = iface.alias;
                f.label = iface.label ?? iface.id;
                f.stereotype = iface.stereotype;
                return f;
            }
            return null;
        }

        private static void collect_objects(Gee.ArrayList<ObjectPackage> packages, Gee.ArrayList<ObjectInstance> into) {
            foreach (var pkg in packages) {
                into.add_all(pkg.objects);
                collect_objects(pkg.children, into);
            }
        }

        private static Found? find_object_element(ObjectDiagram d, string name) {
            var objects = new Gee.ArrayList<ObjectInstance>();
            objects.add_all(d.objects);
            collect_objects(d.packages, objects);
            foreach (var o in objects) {
                if (!name_matches(name, o.alias) && !name_matches(name, o.name) && name != o.get_id()) continue;
                var f = new Found();
                f.kind = o.is_map ? "Map" : "Object";
                f.keyword = o.is_map ? "map" : "object";
                f.id = o.alias ?? o.name;
                f.name = o.name;
                f.alias = o.alias;
                f.label = o.name;
                f.stereotype = o.stereotype;
                f.color = o.color;
                f.line = o.source_line;
                return f;
            }
            return null;
        }

        private static Found? find_entity(ERDiagram d, string name) {
            foreach (var e in d.entities) {
                if (e.name.has_prefix("#")) continue;
                if (!name_matches(name, e.alias) && !name_matches(name, e.name)) continue;
                var f = new Found();
                f.kind = "Entity";
                f.keyword = "entity";
                f.id = e.alias ?? e.name;
                f.name = e.name;
                f.alias = e.alias;
                f.label = e.name;
                f.color = e.color;
                f.line = e.source_line;
                return f;
            }
            return null;
        }

        private static bool note_targets(string? attached_to, Found f) {
            if (attached_to == null) return false;
            return attached_to == f.id || (f.name != null && attached_to == f.name);
        }

        private static string? find_note(Object ast, Found f) {
            var texts = new Gee.ArrayList<string>();
            if (ast is ClassDiagram) {
                foreach (var n in ((ClassDiagram) ast).notes) {
                    bool hit = note_targets(n.attached_to, f);
                    foreach (var link in n.links) {
                        if (link.target == f.id) hit = true;
                    }
                    if (hit) texts.add(n.text);
                }
            } else if (ast is SequenceDiagram) {
                foreach (var n in ((SequenceDiagram) ast).notes) {
                    if ((n.participant != null && n.participant.get_id() == f.id) ||
                        (n.participant2 != null && n.participant2.get_id() == f.id)) {
                        texts.add(n.text);
                    }
                }
            } else if (ast is UseCaseDiagram) {
                foreach (var n in ((UseCaseDiagram) ast).notes) {
                    if (note_targets(n.attached_to, f)) texts.add(n.text);
                }
            } else if (ast is StateDiagram) {
                foreach (var n in ((StateDiagram) ast).notes) {
                    if (note_targets(n.attached_to, f)) texts.add(n.text);
                }
            } else if (ast is ComponentDiagram) {
                foreach (var n in ((ComponentDiagram) ast).notes) {
                    if (note_targets(n.attached_to, f)) texts.add(n.text);
                }
            } else if (ast is ObjectDiagram) {
                foreach (var n in ((ObjectDiagram) ast).notes) {
                    if (note_targets(n.attached_to, f)) texts.add(n.text);
                }
            } else if (ast is ERDiagram) {
                foreach (var n in ((ERDiagram) ast).notes) {
                    if (note_targets(n.attached_to, f)) texts.add(n.text);
                }
            }
            if (texts.size == 0) return null;
            return string.joinv("\n\n", texts.to_array());
        }

        // ==================== Declaration lines ====================

        private static string[] keywords_for(DiagramType type) {
            switch (type) {
                case DiagramType.CLASS:
                    return { "abstract class", "abstract", "class", "interface", "enum",
                             "annotation", "entity", "struct", "exception", "protocol", "metaclass",
                             "stereotype", "dataclass", "record", "circle" };
                case DiagramType.SEQUENCE:
                    return { "participant", "actor", "boundary", "control", "entity",
                             "database", "collections", "queue" };
                case DiagramType.USECASE:
                    return { "actor/", "actor", "usecase/", "usecase" };
                case DiagramType.STATE:
                    return { "state" };
                case DiagramType.COMPONENT:
                    return { "component", "interface", "database", "cloud", "package", "folder",
                             "frame", "node", "device", "artifact", "storage", "card", "agent", "rectangle",
                             "queue", "stack", "file", "boundary", "control", "entity", "actor/",
                             "actor", "usecase/", "usecase", "person", "action", "process",
                             "circle", "hexagon", "label", "collections", "()" };
                case DiagramType.OBJECT:
                    return { "object", "map" };
                case DiagramType.ER_DIAGRAM:
                    return { "entity" };
                default:
                    return {};
            }
        }

        private static bool allows_shorthand(DiagramType type, NameStyle style) {
            switch (style) {
                case NameStyle.BRACKET:
                    return type == DiagramType.COMPONENT;
                case NameStyle.PAREN:
                case NameStyle.COLON:
                    return type == DiagramType.USECASE || type == DiagramType.COMPONENT;
                default:
                    return true;
            }
        }

        // Splits a declaration line; null when the line declares nothing of this type
        private static Decl? parse_decl(DiagramType type, string line, int index) {
            int len = line.length;
            int p = skip_ws(line, 0);
            if (p >= len) return null;
            string lower = line.ascii_down();

            var d = new Decl();
            d.line_index = index;
            // "create participant Foo" declares Foo where it is created
            if (type == DiagramType.SEQUENCE && starts_at(lower, p, "create") &&
                p + 6 < len && is_space(line[p + 6])) {
                p = skip_ws(line, p + 6);
            }
            bool has_keyword = false;
            foreach (unowned string kw in keywords_for(type)) {
                if (!starts_at(lower, p, kw)) continue;
                int after = p + kw.length;
                if (after < len && is_space(line[after])) {
                    d.keyword = line.substring(p, kw.length);
                    p = skip_ws(line, after);
                    has_keyword = true;
                    break;
                }
            }
            if (p >= len) return null;

            char open = line[p];
            char close = 0;
            if (open == '"') {
                d.style = NameStyle.QUOTED;
                close = '"';
            } else if (open == '[') {
                d.style = NameStyle.BRACKET;
                close = ']';
            } else if (open == '(') {
                d.style = NameStyle.PAREN;
                close = ')';
            } else if (open == ':') {
                d.style = NameStyle.COLON;
                close = ':';
            } else {
                d.style = NameStyle.BARE;
            }
            if (!has_keyword && (d.style == NameStyle.BARE || d.style == NameStyle.QUOTED)) return null;
            if (!allows_shorthand(type, d.style)) return null;

            d.name_start = p;
            if (d.style == NameStyle.BARE) {
                int q = p;
                while (q < len) {
                    char ch = line[q];
                    if (is_space(ch) || ch == '{' || ch == '#' || ch == ';' || ch == '[' || ch == '<') {
                        break;
                    }
                    if (ch == ':') {
                        if (starts_at(line, q, "::")) {
                            q += 2;
                            continue;
                        }
                        break;
                    }
                    q++;
                }
                if (q == p) return null;
                d.name = line.substring(p, q - p);
                // "class Foo<T>": the id is Foo, the generics stay with it
                d.name_end = skip_generics(line, q);
            } else {
                int q = index_of_byte(line, close, p + 1);
                if (q < 0) return null;
                d.name = line.substring(p + 1, q - p - 1);
                d.name_end = q + 1;
            }
            if (d.name.strip().length == 0) return null;
            d.tail_end = d.name_end;
            if (d.tail_end < len && line[d.tail_end] == '/') d.tail_end++;

            // "as Alias", "<<stereotype>>", "#color", "##border" and "order N", in any order
            int pos = d.tail_end;
            while (pos < len) {
                int ws = pos;
                int t = skip_ws(line, pos);
                if (t >= len) break;
                if (d.alias == null && t > ws && starts_at(lower, t, "as") &&
                    t + 2 < len && is_space(line[t + 2])) {
                    int a = skip_ws(line, t + 2);
                    if (a >= len) break;
                    int a_end;
                    if (line[a] == '"') {
                        int q = index_of_byte(line, '"', a + 1);
                        if (q < 0) break;
                        d.alias = line.substring(a + 1, q - a - 1);
                        d.alias_quoted = true;
                        a_end = q + 1;
                    } else {
                        a_end = a;
                        while (a_end < len && !is_space(line[a_end]) && line[a_end] != '{' &&
                               line[a_end] != '#' && line[a_end] != ';' && line[a_end] != '<') {
                            a_end++;
                        }
                        if (a_end == a) break;
                        d.alias = line.substring(a, a_end - a);
                        a_end = skip_generics(line, a_end);
                    }
                    d.alias_ws = ws;
                    d.alias_start = a;
                    d.alias_end = a_end;
                    pos = a_end;
                    continue;
                }
                if (starts_at(line, t, "<<")) {
                    int q = line.index_of(">>", t + 2);
                    if (q < 0) break;
                    if (d.stereo_start < 0) {
                        d.stereo_ws = ws;
                        d.stereo_start = t;
                        d.stereo_first_end = q + 2;
                        d.stereotype = line.substring(t + 2, q - t - 2).strip();
                        d.stereo_end = q + 2;
                    } else if (d.stereo_end == ws) {
                        d.stereo_end = q + 2;
                    }
                    pos = q + 2;
                    continue;
                }
                if (type == DiagramType.SEQUENCE && starts_at(lower, t, "order") &&
                    t + 5 < len && is_space(line[t + 5])) {
                    int q = skip_ws(line, t + 5);
                    if (q < len && line[q] == '-') q++;
                    int digits = q;
                    while (q < len && line[q] >= '0' && line[q] <= '9') q++;
                    if (q == digits) break;
                    d.order_end = q;
                    pos = q;
                    continue;
                }
                if (starts_at(line, t, "##")) {
                    int q = t + 2;
                    while (q < len && !is_space(line[q]) && line[q] != '{') q++;
                    if (d.border_ws < 0) d.border_ws = ws;
                    pos = q;
                    continue;
                }
                if (line[t] == '#' && d.color == null) {
                    int q = t + 1;
                    while (q < len && !is_space(line[q]) && line[q] != '{') q++;
                    d.color_ws = ws;
                    d.color_start = t;
                    d.color_end = q;
                    d.color = line.substring(t, q - t);
                    pos = q;
                    continue;
                }
                break;
            }

            // Whatever follows must still be declaration syntax, not a relationship arrow
            int r = skip_ws(line, pos);
            if (r < len) {
                char ch = line[r];
                bool ok = ch == '{' || ch == ':' || ch == '$' || ch == '[' || ch == '\'' || ch == ';';
                if (!ok) {
                    ok = starts_at(lower, r, "extends") || starts_at(lower, r, "implements") ||
                         starts_at(lower, r, "order");
                }
                if (!ok) return null;
            }
            return d;
        }

        // After "<T>" / "<K, List<V>>" directly at `pos`; `pos` when there are none
        private static int skip_generics(string line, int pos) {
            if (pos >= line.length || line[pos] != '<' || starts_at(line, pos, "<<")) return pos;
            int depth = 0;
            for (int q = pos; q < line.length; q++) {
                if (line[q] == '<') {
                    depth++;
                } else if (line[q] == '>') {
                    depth--;
                    if (depth == 0) return q + 1;
                }
            }
            return pos;
        }

        private static Decl? find_declaration(DiagramType type, string[] lines, bool[] code,
                                              string id, int hint_line) {
            Decl? first = null;
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                var d = parse_decl(type, lines[i], i);
                if (d == null || d.get_id() != id) continue;
                if (i + 1 == hint_line) return d;
                if (first == null) first = d;
            }
            return first;
        }

        private static int first_use_line(DiagramType type, string[] lines, bool[] code, string id) {
            for (int i = 0; i < lines.length; i++) {
                if (code[i] && line_has_word(type, lines[i], id)) return i;
            }
            return -1;
        }

        private static bool line_has_word(DiagramType type, string line, string word) {
            int hits = 0;
            int clashes = 0;
            rename_in_line(type, line, word, word, ref hits, ref clashes);
            return hits > 0;
        }

        // "!include" / "!import" lines: the preprocessed AST can hold elements declared elsewhere
        private static bool has_include(string[] lines, bool[] code) {
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                string l = lines[i].strip().ascii_down();
                if (l.has_prefix("!include") || l.has_prefix("!import")) return true;
            }
            return false;
        }

        // New declaration line directly above the first use (keeps package/container scope),
        // or after @startuml when the element is not used on any code line
        private static string insert_declaration(ElementInfo info, string[] lines, bool[] code, string text) {
            int at = -1;
            if (info.line > 0 && info.line <= lines.length && code[info.line - 1] &&
                line_has_word(info.diagram_type, lines[info.line - 1], info.id)) {
                at = info.line - 1;
            }
            if (at < 0) at = first_use_line(info.diagram_type, lines, code, info.id);

            string indent = "";
            if (at >= 0) {
                string l = lines[at];
                indent = l.substring(0, skip_ws(l, 0));
            } else {
                at = 0;
                for (int i = 0; i < lines.length; i++) {
                    if (lines[i].strip().ascii_down().has_prefix("@start")) {
                        at = i + 1;
                        break;
                    }
                }
            }

            string[] result = {};
            for (int i = 0; i < lines.length; i++) {
                if (i == at) result += indent + text;
                result += lines[i];
            }
            if (at >= lines.length) result += indent + text;
            return string.joinv("\n", result);
        }

        // ==================== Text scanning ====================

        // Which lines hold diagram code: false for comments and free-text lines and blocks
        // (note/legend/ref bodies, title/header/footer/caption text, multi-line "[ ... ]"
        // descriptions, and in sequence diagrams group labels, dividers and delays)
        private static bool[] code_mask(DiagramType type, string[] lines) {
            var mask = new bool[lines.length];
            bool in_comment = false;
            string? block = null;   // "note", "legend", "ref", "title", "]", ... until its end line
            for (int i = 0; i < lines.length; i++) {
                string s = lines[i].strip();
                string l = s.ascii_down();
                mask[i] = false;
                if (in_comment) {
                    if (s.contains("'/")) in_comment = false;
                    continue;
                }
                if (s.has_prefix("/'")) {
                    if (!s.substring(2).contains("'/")) in_comment = true;
                    continue;
                }
                if (s.has_prefix("'")) continue;
                if (block != null) {
                    if (block == "]") {
                        if (s.has_prefix("]")) block = null;
                        continue;
                    }
                    string e = l.replace(" ", "").replace("\t", "");
                    if (e.has_prefix("end" + block) ||
                        (block == "note" && (e.has_prefix("endhnote") || e.has_prefix("endrnote")))) {
                        block = null;
                    }
                    continue;
                }
                bool is_note = false;
                foreach (unowned string kw in new string[] { "note", "hnote", "rnote" }) {
                    if (starts_word(l, kw)) {
                        mask[i] = true;
                        // A body follows unless the text is on this line: after a ':' label
                        // separator ("::" is a member reference) or quoted right after the
                        // keyword (floating `note "text" as N`)
                        int t = skip_ws(s, kw.length);
                        if (!has_label_colon(s) && !(t < s.length && s[t] == '"')) block = "note";
                        is_note = true;
                        break;
                    }
                }
                if (is_note) continue;
                if (starts_word(l, "legend")) {
                    block = "legend";
                    continue;
                }
                if (l.has_prefix("ref over") || l.has_prefix("ref#")) {
                    mask[i] = true;
                    if (!has_label_colon(s)) block = "ref";
                    continue;
                }
                // "title", "header", "center footer", ...: one line of text, or a block
                string text_line = l;
                foreach (unowned string side in new string[] { "left", "right", "center" }) {
                    if (starts_word(l, side)) {
                        text_line = l.substring(side.length).strip();
                        break;
                    }
                }
                bool text_block = false;
                foreach (unowned string kw in new string[] { "title", "header", "footer", "caption" }) {
                    if (text_line == kw) {
                        block = kw;
                        text_block = true;
                        break;
                    }
                    if (starts_word(text_line, kw)) {
                        text_block = true;
                        break;
                    }
                }
                if (text_block) continue;
                if (type == DiagramType.SEQUENCE && is_sequence_text_line(l)) continue;
                mask[i] = true;
                // `component C [` / `participant P [`: the description lines up to "]"
                if (s.has_suffix("[") && !s.has_suffix("[[") && !s.has_prefix("[")) block = "]";
            }
            return mask;
        }

        // Sequence lines whose text is prose: group labels (alt, else, loop, group, ...),
        // box titles, return values, "== divider ==", "... delay ...", "||| spacing"
        private static bool is_sequence_text_line(string l) {
            if (l.has_prefix("==") || l.has_prefix("...") || l.has_prefix("||")) return true;
            foreach (unowned string kw in new string[] { "alt", "else", "opt", "loop", "par", "par2",
                                                         "critical", "break", "group", "return", "box",
                                                         "newpage", "divider" }) {
                if (!starts_word(l, kw)) continue;
                // "loop -> Bob": an element that happens to be called like a keyword
                string rest = l.substring(kw.length).strip();
                return rest.length == 0 || "-<>.=:[/\\".index_of_char(rest[0]) < 0;
            }
            return false;
        }

        // A ':' outside quotes that is not part of a "::" member reference
        private static bool has_label_colon(string s) {
            bool in_string = false;
            for (int i = 0; i < s.length; i++) {
                if (s[i] == '"') {
                    in_string = !in_string;
                } else if (s[i] == ':' && !in_string) {
                    if (i + 1 < s.length && s[i + 1] == ':') {
                        i++;
                        continue;
                    }
                    return true;
                }
            }
            return false;
        }

        // Start of a delimited token: line start, whitespace, or an arrow/list character
        private static bool token_start(string line, int i) {
            return i == 0 || " \t>-.(|,=<".index_of_char(line[i - 1]) >= 0;
        }

        // The delimited token start..end is a label: `"Label" as X`, `[Label] as X`, `X as "Label"`
        private static bool is_label_token(string lower, int start, int end) {
            int a = skip_ws(lower, end);
            if (a > end && starts_at(lower, a, "as") && (a + 2 == lower.length || is_space(lower[a + 2]))) {
                return true;
            }
            int b = start;
            while (b > 0 && is_space(lower[b - 1])) b--;
            return b < start && b >= 2 && starts_at(lower, b - 2, "as") && (b == 2 || !is_word(lower[b - 3]));
        }

        // Replaces `from` references with `to` in the code part of one line, counting
        // replacements in `hits` and existing references to `to` in `clashes`. A reference
        // is a whole word, or a whole "quoted", [bracket], (paren) or :colon: token whose
        // text is exactly the id. Words inside delimited names ([Web Server]) are not
        // references, nor are labels (`[Label] as X`, `X as "Label"`, floating note text).
        private static string rename_in_line(DiagramType type, string line, string from, string to,
                                             ref int hits, ref int clashes) {
            int len = line.length;
            int first = skip_ws(line, 0);
            if (first < len && line[first] == '\'') return line;
            string lower = line.ascii_down();
            int note_text = -1;
            foreach (unowned string kw in new string[] { "note", "hnote", "rnote" }) {
                if (starts_word(lower.substring(first), kw)) {
                    note_text = skip_ws(line, first + kw.length);
                    break;
                }
            }
            bool paren_names = type == DiagramType.USECASE || type == DiagramType.COMPONENT;

            var sb = new StringBuilder();
            int copied = 0;
            int i = 0;
            while (i < len) {
                char c = line[i];
                if (c == '"') {
                    int q = index_of_byte(line, '"', i + 1);
                    if (q < 0) break;
                    if (i != note_text && !is_label_token(lower, i, q + 1)) {
                        visit_token(line, i + 1, q, from, to, sb, ref copied, ref hits, ref clashes);
                    }
                    i = q + 1;
                    continue;
                }
                if (c == '/' && i + 1 < len && line[i + 1] == '\'') {
                    int q = line.index_of("'/", i + 2);
                    i = q < 0 ? len : q + 2;
                    continue;
                }
                // "<<stereotype>>", but not a "<<-" / "<<--" arrow head
                if (starts_at(line, i, "<<") && !(i + 2 < len && "-.=<".index_of_char(line[i + 2]) >= 0)) {
                    int q = line.index_of(">>", i + 2);
                    i = q < 0 ? len : q + 2;
                    continue;
                }
                if (c == '#') {
                    i++;
                    while (i < len && is_word(line[i])) i++;
                    continue;
                }
                if (c == '[' && token_start(line, i)) {
                    if (starts_at(line, i, "[[")) {
                        int q = line.index_of("]]", i + 2);
                        i = q < 0 ? len : q + 2;
                        continue;
                    }
                    int q = index_of_byte(line, ']', i + 1);
                    if (q > i + 1) {
                        string inner = line.substring(i + 1, q - i - 1);
                        // "-[#red]->", "-[hidden]-": arrow style, not a name
                        if (i > 0 && "-.".index_of_char(line[i - 1]) >= 0 &&
                            q + 1 < len && "-.>".index_of_char(line[q + 1]) >= 0) {
                            i = q + 1;
                            continue;
                        }
                        if (inner.index_of_char('<') < 0 && inner.index_of_char('>') < 0 &&
                            inner.index_of_char('[') < 0 && !inner.has_prefix("-") && !inner.has_prefix("#")) {
                            if (!is_label_token(lower, i, q + 1)) {
                                visit_token(line, i + 1, q, from, to, sb, ref copied, ref hits, ref clashes);
                            }
                            i = q + 1;
                            continue;
                        }
                    }
                    i++;
                    continue;
                }
                if (c == '(' && paren_names && token_start(line, i)) {
                    int q = index_of_byte(line, ')', i + 1);
                    if (q > i + 1 && line.substring(i + 1, q - i - 1).index_of_char(',') < 0) {
                        if (!is_label_token(lower, i, q + 1)) {
                            visit_token(line, i + 1, q, from, to, sb, ref copied, ref hits, ref clashes);
                        }
                        i = q + 1;
                        continue;
                    }
                    i++;
                    continue;
                }
                if (c == ':') {
                    if (i + 1 < len && line[i + 1] == ':') {
                        i += 2;
                        continue;
                    }
                    // ":Actor:" shorthand: a name token; any other ':' starts label text
                    bool opener = (i == 0 || is_space(line[i - 1]) || "-<>.(|".index_of_char(line[i - 1]) >= 0) &&
                                  i + 1 < len && !is_space(line[i + 1]);
                    int close = opener ? index_of_byte(line, ':', i + 1) : -1;
                    if (close < 0) break;
                    if (!is_label_token(lower, i, close + 1)) {
                        visit_token(line, i + 1, close, from, to, sb, ref copied, ref hits, ref clashes);
                    }
                    i = close + 1;
                    continue;
                }
                if (is_word(c) && (i == 0 || !is_word(line[i - 1]))) {
                    int q = i;
                    while (q < len && is_word(line[q])) q++;
                    visit_token(line, i, q, from, to, sb, ref copied, ref hits, ref clashes);
                    i = q;
                    continue;
                }
                i++;
            }
            if (copied == 0) return line;
            sb.append(line.substring(copied));
            return sb.str;
        }

        // The text start..end is one whole reference candidate
        private static void visit_token(string line, int start, int end, string from, string to,
                                        StringBuilder sb, ref int copied, ref int hits, ref int clashes) {
            string w = line.substring(start, end - start);
            if (w == from) {
                sb.append(line.substring(copied, start - copied));
                sb.append(to);
                copied = end;
                hits++;
            } else if (w == to) {
                clashes++;
            }
        }

        // Renames an id that is only ever written inside delimiters: every "from", [from],
        // (from) and :from: on a code line gets the new text in the same delimiters. Text
        // after a " : " label separator is prose and stays. Null when the new text would
        // close a delimiter early, nothing was found, or the new name is already used in
        // any form (delimited or as a bare id).
        private static string? rename_delimited(DiagramType type, string from, string source, string to) {
            if (to.length == 0 || to.contains("\"") || to.contains("]") || to.contains(")") ||
                to.contains(":") || to.contains("\n")) {
                return null;
            }
            string[] opens = { "\"", "[", "(", ":" };
            string[] closes = { "\"", "]", ")", ":" };
            string[] lines = source.split("\n");
            bool[] code = code_mask(type, lines);
            bool word_id = is_word_id(to);
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                for (int k = 0; k < opens.length; k++) {
                    if (lines[i].contains(opens[k] + to + closes[k])) return null;
                }
                if (word_id && line_has_word(type, lines[i], to)) return null;
            }

            int hits = 0;
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                string line = lines[i];
                int label_at = line.index_of(" : ");
                string head = label_at >= 0 ? line.substring(0, label_at) : line;
                string tail = label_at >= 0 ? line.substring(label_at) : "";
                for (int k = 0; k < opens.length; k++) {
                    string needle = opens[k] + from + closes[k];
                    int found = head.index_of(needle);
                    while (found >= 0) {
                        head = splice(head, found, found + needle.length, opens[k] + to + closes[k]);
                        hits++;
                        found = head.index_of(needle, found + to.length + 2);
                    }
                }
                lines[i] = head + tail;
            }
            return hits > 0 ? string.joinv("\n", lines) : null;
        }

        // ==================== Small helpers ====================

        private static string splice(string s, int start, int end, string replacement) {
            return s.substring(0, start) + replacement + s.substring(end);
        }

        private static string wrap(NameStyle style, string text) {
            switch (style) {
                case NameStyle.BRACKET: return "[%s]".printf(text);
                case NameStyle.PAREN: return "(%s)".printf(text);
                case NameStyle.COLON: return ":%s:".printf(text);
                default: return "\"%s\"".printf(text);
            }
        }

        // The label in the declaration's own delimiters; null if it would close them early
        private static string? label_token(NameStyle style, string label) {
            if (style == NameStyle.BRACKET && label.contains("]")) return null;
            if (style == NameStyle.PAREN && label.contains(")")) return null;
            if (style == NameStyle.COLON && label.contains(":")) return null;
            return wrap(style, label);
        }

        public static bool is_identifier(string s) {
            if (s.length == 0) return false;
            char c0 = s[0];
            if (!((c0 >= 'a' && c0 <= 'z') || (c0 >= 'A' && c0 <= 'Z') || c0 == '_')) return false;
            for (int i = 1; i < s.length; i++) {
                char c = s[i];
                if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) {
                    return false;
                }
            }
            return true;
        }

        // An identifier that may also hold non-ASCII letters ("Größe"): word bytes only,
        // not starting with a digit
        private static bool is_word_id(string s) {
            if (s.length == 0 || (s[0] >= '0' && s[0] <= '9')) return false;
            for (int i = 0; i < s.length; i++) {
                if (!is_word(s[i])) return false;
            }
            return s.validate();
        }

        private static bool is_color_text(string c) {
            if (c.length == 0) return true;
            for (int i = 0; i < c.length; i++) {
                char ch = c[i];
                bool ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
                          ch == '#' || ch == ';' || ch == ':' || ch == '/' || ch == '\\' || ch == '|' ||
                          ch == '.' || ch == '-';
                if (!ok) return false;
            }
            return true;
        }

        private static bool is_all_digits(string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                if (s[i] < '0' || s[i] > '9') return false;
            }
            return true;
        }

        private static bool is_space(char c) {
            return c == ' ' || c == '\t' || c == '\r';
        }

        // Identifier bytes; UTF-8 continuation bytes count so "Foö" never matches "Fo"
        private static bool is_word(char c) {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                   c == '_' || (uchar) c >= 0x80;
        }

        private static int skip_ws(string s, int pos) {
            while (pos < s.length && is_space(s[pos])) pos++;
            return pos;
        }

        private static bool starts_at(string s, int pos, string prefix) {
            if (pos < 0 || pos + prefix.length > s.length) return false;
            for (int i = 0; i < prefix.length; i++) {
                if (s[pos + i] != prefix[i]) return false;
            }
            return true;
        }

        // `prefix` at the start of `l`, followed by the end or a non-identifier byte
        private static bool starts_word(string l, string prefix) {
            if (!l.has_prefix(prefix)) return false;
            return l.length == prefix.length || !is_word(l[prefix.length]);
        }

        private static int index_of_byte(string s, char c, int from) {
            for (int i = from; i < s.length; i++) {
                if (s[i] == c) return i;
            }
            return -1;
        }
    }
}
