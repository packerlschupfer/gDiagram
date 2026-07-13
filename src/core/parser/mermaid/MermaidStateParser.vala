namespace GDiagram {
    /**
     * Mermaid stateDiagram(-v2) parser. Statements are read from the source lines (see
     * MermaidSourceLine) instead of MermaidLexer tokens, which keeps note and label text
     * exact and makes the composite-state scopes explicit:
     *  - `[*]` inside `state X { }` is X's own start/end marker (parent_id = X)
     *  - a composite declared inside another one is a child of it, never a top-level state
     */
    public class MermaidStateParser : Object {
        private MermaidStateDiagram diagram;
        private Gee.ArrayList<string> scopes = new Gee.ArrayList<string>();
        // One counter per open scope, bumped by every "--" concurrency separator
        private Gee.ArrayList<int> scope_regions = new Gee.ArrayList<int>();
        // note block being read ("note left of X" ... "end note")
        private MermaidState? note_target = null;
        private StringBuilder? note_text = null;
        private bool in_acc_descr = false;

        public MermaidStateParser() {
        }

        private string? current_parent_id {
            owned get { return scopes.size > 0 ? scopes[scopes.size - 1] : null; }
        }

        private int current_region {
            get { return scope_regions.size > 0 ? scope_regions[scope_regions.size - 1] : 0; }
        }

        public MermaidStateDiagram parse(string source) {
            this.diagram = new MermaidStateDiagram();
            scopes = new Gee.ArrayList<string>();
            scope_regions = new Gee.ArrayList<int>();
            note_target = null;
            note_text = null;
            in_acc_descr = false;

            string? fm_title;
            bool header_ok;
            var lines = MermaidSourceLine.split(source, { "stateDiagram-v2", "stateDiagram" },
                                                out fm_title, out header_ok);
            if (!header_ok) {
                int line = lines.size > 0 ? lines[0].line : 1;
                diagram.errors.add(new ParseError("Expected 'stateDiagram-v2'", line, 1));
                return diagram;
            }
            if (fm_title != null) diagram.title = fm_title;

            foreach (var l in lines) {
                parse_line(l.text, l.line);
            }
            if (note_target != null) finish_note(note_target, note_text.str);
            return diagram;
        }

        private void parse_line(string text, int line) {
            if (note_target != null) {
                if (text == "end note") {
                    finish_note(note_target, note_text.str);
                    note_target = null;
                    note_text = null;
                } else {
                    if (note_text.len > 0) note_text.append_c('\n');
                    note_text.append(text);
                }
                return;
            }
            if (in_acc_descr) {
                if (text.contains("}")) in_acc_descr = false;
                return;
            }

            if (text == "}") {
                if (scopes.size > 0) scopes.remove_at(scopes.size - 1);
                if (scope_regions.size > 0) scope_regions.remove_at(scope_regions.size - 1);
                return;
            }
            // concurrency separator: everything after it belongs to the next region
            if (text == "--") {
                if (scope_regions.size > 0) {
                    scope_regions[scope_regions.size - 1] = scope_regions[scope_regions.size - 1] + 1;
                }
                return;
            }

            if (text.has_prefix("accTitle") || text.has_prefix("accDescr")) {
                if (text.has_prefix("accDescr") && !text.contains(":") && text.contains("{") &&
                    !text.contains("}")) {
                    in_acc_descr = true;
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "title")) {
                diagram.title = text.substring(5).strip();
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "direction")) {
                FlowchartDirection dir;
                if (MermaidSourceLine.parse_direction(text.substring(9), out dir)) diagram.direction = dir;
                return;
            }

            // classDef name fill:#f00,stroke:#333
            if (MermaidSourceLine.starts_with_word(text, "classDef")) {
                string rest = text.substring(8).strip();
                int sp = MermaidSourceLine.first_space(rest);
                if (sp > 0) {
                    string spec = rest.substring(sp).strip().replace(" ", "");
                    foreach (string name in rest.substring(0, sp).split(",")) {
                        if (name.strip().length > 0) diagram.class_defs.set(name.strip(), spec);
                    }
                }
                return;
            }

            // class A,B name
            if (MermaidSourceLine.starts_with_word(text, "class")) {
                string rest = text.substring(5).strip();
                int sp = rest.last_index_of(" ");
                if (sp > 0) {
                    string name = rest.substring(sp + 1).strip();
                    foreach (string id in rest.substring(0, sp).split(",")) {
                        if (id.strip().length == 0) continue;
                        use_state(id.strip(), line).css_classes.add(name);
                    }
                }
                return;
            }

            // style A fill:#f00
            if (MermaidSourceLine.starts_with_word(text, "style")) {
                string rest = text.substring(5).strip();
                int sp = MermaidSourceLine.first_space(rest);
                if (sp > 0) {
                    use_state(rest.substring(0, sp), line).inline_style = rest.substring(sp).strip().replace(" ", "");
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "note")) {
                parse_note(text.substring(4).strip(), line);
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "state")) {
                parse_state_declaration(text.substring(5).strip(), line);
                return;
            }

            int arrow = MermaidSourceLine.index_unquoted(text, "-->");
            int arrow_len = 3;
            if (arrow < 0) {
                arrow = MermaidSourceLine.index_unquoted(text, "->");
                arrow_len = 2;
            }
            // "Idle : waits -> ready" is a description, not a transition: a bare id
            // followed by ":" wins over an arrow later in the line (Mermaid draws the
            // arrow as description text).
            int desc_colon = arrow >= 0 ? description_colon(text) : -1;
            if (desc_colon >= 0 && desc_colon < arrow) arrow = -1;
            if (arrow >= 0) {
                parse_transition(text.substring(0, arrow).strip(), text.substring(arrow + arrow_len).strip(), line);
                return;
            }

            // Id, Id:::cls, Id : description
            int pos = 0;
            string id = read_id(text, ref pos);
            if (id.length == 0 || id == "[*]") return;
            var state = use_state(id, line);
            string rest = text.substring(pos).strip();
            rest = read_class_shorthand(state, rest);
            if (rest.has_prefix(":")) {
                state.description = rest.substring(1).strip();
                state.source_line = line;
            }
        }

        // `state "Desc" as Id`, `state Id as Desc`, `state Id <<fork>>`, `state Id {`
        private void parse_state_declaration(string rest_src, int line) {
            string rest = rest_src;
            string id;
            string? description = null;
            if (rest.has_prefix("\"")) {
                int q = rest.index_of("\"", 1);
                if (q < 0) {
                    diagram.errors.add(new ParseError("Unterminated state description", line, 1));
                    return;
                }
                description = rest.substring(1, q - 1);
                rest = rest.substring(q + 1).strip();
                if (MermaidSourceLine.starts_with_word(rest, "as")) {
                    rest = rest.substring(2).strip();
                    int pos = 0;
                    id = read_id(rest, ref pos);
                    rest = rest.substring(pos).strip();
                } else {
                    id = description;
                    description = null;
                }
            } else {
                int pos = 0;
                id = read_id(rest, ref pos);
                rest = rest.substring(pos).strip();
            }
            if (id.length == 0 || id == "[*]") {
                diagram.errors.add(new ParseError("Expected state identifier", line, 1));
                return;
            }

            bool opens = false;
            string body = rest;
            if (body.has_suffix("{")) {
                opens = true;
                body = body.substring(0, body.length - 1).strip();
            }

            var state = use_state(id, line);
            state.source_line = line;
            if (description != null) state.description = description;

            body = read_class_shorthand(state, body);
            if (body.has_prefix("<<")) {
                int end = body.index_of(">>");
                if (end > 2) {
                    switch (body.substring(2, end - 2).strip().down()) {
                        // S6: Mermaid 11.17 draws a fork/join declared after its first use as a
                        // plain box; gDiagram keeps the bar the author asked for
                        case "choice": state.state_type = MermaidStateType.CHOICE; break;
                        case "fork":   state.state_type = MermaidStateType.FORK;   break;
                        case "join":   state.state_type = MermaidStateType.JOIN;   break;
                        default: break;
                    }
                    body = body.substring(end + 2).strip();
                }
            } else if (MermaidSourceLine.starts_with_word(body, "as")) {
                string desc = body.substring(2).strip();
                if (desc.length > 0) state.description = MermaidSourceLine.unquote(desc);
            } else if (body.has_prefix(":")) {
                string desc = body.substring(1).strip();
                if (desc.length > 0) state.description = desc;
            }

            if (opens) {
                // A composite declared inside another one belongs to it
                string? scope = current_parent_id;
                if (scope != null && scope != id) {
                    var scope_state = diagram.find_state(scope);
                    if (scope_state != null && !diagram.is_inside(scope_state, id)) {
                        state.parent_id = scope;
                    }
                }
                scopes.add(id);
                scope_regions.add(0);
            }
        }

        private void parse_transition(string left, string right, int line) {
            int pos = 0;
            string from_id = read_id(left, ref pos);
            if (from_id.length == 0) {
                diagram.errors.add(new ParseError("Expected state identifier or [*]", line, 1));
                return;
            }
            MermaidState from_state = from_id == "[*]" ? marker(true, line) : use_state(from_id, line);
            if (from_id != "[*]") read_class_shorthand(from_state, left.substring(pos).strip());

            pos = 0;
            string to_id = read_id(right, ref pos);
            if (to_id.length == 0) {
                diagram.errors.add(new ParseError("Expected state identifier or [*]", line, 1));
                return;
            }
            MermaidState to_state = to_id == "[*]" ? marker(false, line) : use_state(to_id, line);
            string rest = right.substring(pos).strip();
            if (to_id != "[*]") rest = read_class_shorthand(to_state, rest);

            var transition = new MermaidTransition(from_state, to_state);
            if (rest.has_prefix(":")) {
                string label = rest.substring(1).strip();
                if (label.length > 0) transition.label = label;
            }
            diagram.transitions.add(transition);
        }

        // The [*] start/end marker of the current scope
        private MermaidState marker(bool start, int line) {
            string? scope = current_parent_id;
            int region = current_region;
            // Each concurrent region has its own [*] markers
            string id = MermaidStateDiagram.marker_id(scope, start);
            if (region > 0) id += "#%d".printf(region);
            var existing = diagram.find_state(id);
            if (existing != null) return existing;
            var state = new MermaidState(id, start ? MermaidStateType.START : MermaidStateType.END, line);
            state.parent_id = scope;
            state.region = region;
            diagram.add_state(state);
            return state;
        }

        // note left of X : text | note right of X (block until "end note")
        private void parse_note(string note_src, int line) {
            string rest = note_src;
            string position;
            if (rest.has_prefix("left of ")) {
                position = "left";
                rest = rest.substring(8).strip();
            } else if (rest.has_prefix("right of ")) {
                position = "right";
                rest = rest.substring(9).strip();
            } else {
                // floating `note "text" as N`: not attached to a state
                return;
            }
            int pos = 0;
            string id = read_id(rest, ref pos);
            if (id.length == 0) return;
            var state = use_state(id, line);
            state.note_position = position;
            string after = rest.substring(pos).strip();
            if (after.has_prefix(":")) {
                finish_note(state, after.substring(1).strip());
            } else {
                note_target = state;
                note_text = new StringBuilder();
            }
        }

        private void finish_note(MermaidState state, string text) {
            string t = text.replace("\\n", "\n").replace("<br>", "\n").replace("<br/>", "\n").strip();
            if (t.length == 0) return;
            state.note = state.note == null ? t : state.note + "\n" + t;
        }

        // ":::name" right after a state id; returns the text after it
        private string read_class_shorthand(MermaidState state, string rest) {
            if (!rest.has_prefix(":::")) return rest;
            int end = 3;
            while (end < rest.length && rest[end] != ' ' && rest[end] != '\t' && rest[end] != ':' &&
                   rest[end] != '{' && rest[end] != '<') {
                end++;
            }
            string name = rest.substring(3, end - 3);
            if (name.length > 0) state.css_classes.add(name);
            return rest.substring(end).strip();
        }

        // A state is created in the scope it is first mentioned in
        private MermaidState use_state(string id, int line) {
            var existing = diagram.find_state(id);
            if (existing != null) return existing;
            var state = new MermaidState(id, MermaidStateType.NORMAL, line);
            string? scope = current_parent_id;
            if (scope != null && scope != id) {
                state.parent_id = scope;
                state.region = current_region;
            }
            diagram.add_state(state);
            return state;
        }

        /**
         * Offset of the ":" that opens an `Id : description`, or -1. The ":" must sit
         * outside quotes, must not be the ":::" class shorthand, and everything before it
         * must be one bare identifier — so "A --> B : label" and "A:::cls --> B" are not
         * descriptions, while "Idle : waits -> ready" is.
         */
        private static int description_colon(string text) {
            bool quoted = false;
            int len = text.length;   // hoisted: Vala re-reads this as strlen() per test
            for (int k = 0; k < len; k++) {
                char c = text[k];
                if (c == '"') {
                    quoted = !quoted;
                    continue;
                }
                if (quoted || c != ':') continue;
                if (text.substring(k).has_prefix(":::")) {
                    k += 2;
                    continue;
                }
                string head = text.substring(0, k).strip();
                if (head.length == 0) return -1;
                int pos = 0;
                string id = read_id(head, ref pos);
                if (id.length == 0 || id == "[*]") return -1;
                string rest = head.substring(pos);
                return (rest.length == 0 || rest.has_prefix(":::")) ? k : -1;
            }
            return -1;
        }

        private static string read_id(string s, ref int pos) {
            while (pos < s.length && (s[pos] == ' ' || s[pos] == '\t')) pos++;
            if (s.substring(pos).has_prefix("[*]")) {
                pos += 3;
                return "[*]";
            }
            int start = pos;
            while (pos < s.length) {
                char c = s[pos];
                if (c == ' ' || c == '\t' || c == ':' || c == '{' || c == '<' || c == '"') break;
                pos++;
            }
            return s.substring(start, pos - start);
        }
    }
}
