namespace GDiagram {
    /**
     * Mermaid classDiagram parser. The grammar is line oriented, so statements are read
     * from the source lines (see MermaidSourceLine) rather than from MermaidLexer tokens:
     * member signatures, generics (`~T~`), labels and note text keep their exact text.
     */
    public class MermaidClassParser : Object {
        private MermaidClassDiagram diagram;
        private MermaidClass? body_class = null;         // inside "class X {"
        private Gee.ArrayList<string> namespaces = new Gee.ArrayList<string>();
        private bool in_acc_descr = false;

        public MermaidClassParser() {
        }

        public MermaidClassDiagram parse(string source) {
            this.diagram = new MermaidClassDiagram();
            body_class = null;
            namespaces = new Gee.ArrayList<string>();
            in_acc_descr = false;

            string? fm_title;
            bool header_ok;
            var lines = MermaidSourceLine.split(source, { "classDiagram", "classDiagram-v2" },
                                                out fm_title, out header_ok);
            if (!header_ok) {
                int line = lines.size > 0 ? lines[0].line : 1;
                diagram.errors.add(new ParseError("Expected 'classDiagram'", line, 1));
                return diagram;
            }
            if (fm_title != null) diagram.title = fm_title;

            int last_line = 1;
            foreach (var l in lines) {
                last_line = l.line;
                parse_line(l.text, l.line);
            }
            if (body_class != null) {
                diagram.errors.add(new ParseError(
                    "Expected '}' to close class '%s'".printf(body_class.name), last_line, 1));
            }
            return diagram;
        }

        private void parse_line(string text, int line) {
            if (in_acc_descr) {
                if (text.contains("}")) in_acc_descr = false;
                return;
            }

            if (body_class != null) {
                int close = MermaidSourceLine.index_unquoted(text, "}");
                string part = close >= 0 ? text.substring(0, close).strip() : text;
                if (part.length > 0) parse_body_line(body_class, part);
                if (close >= 0) body_class = null;
                return;
            }

            if (text == "}") {
                if (namespaces.size > 0) namespaces.remove_at(namespaces.size - 1);
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
                if (MermaidSourceLine.parse_direction(text.substring(9), out dir)) {
                    diagram.direction = dir;
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "namespace")) {
                string rest = text.substring(9).strip();
                int brace = rest.index_of("{");
                string name = (brace >= 0 ? rest.substring(0, brace) : rest).strip();
                name = strip_backticks(name);
                namespaces.add(name);
                // "namespace X { }" on one line, or a namespace without a block
                if (brace < 0 || rest.substring(brace).contains("}")) {
                    namespaces.remove_at(namespaces.size - 1);
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "classDef")) {
                string rest = text.substring(8).strip();
                int sp = MermaidSourceLine.first_space(rest);
                if (sp > 0) {
                    string spec = rest.substring(sp).strip();
                    foreach (string name in rest.substring(0, sp).split(",")) {
                        if (name.strip().length > 0) diagram.class_defs.set(name.strip(), spec);
                    }
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "cssClass")) {
                // cssClass "A,B" hot
                string rest = text.substring(8).strip();
                string names = rest;
                string css = "";
                if (rest.has_prefix("\"")) {
                    int q = rest.index_of("\"", 1);
                    if (q > 0) {
                        names = rest.substring(1, q - 1);
                        css = rest.substring(q + 1).strip();
                    }
                } else {
                    int sp = MermaidSourceLine.first_space(rest);
                    if (sp > 0) {
                        names = rest.substring(0, sp);
                        css = rest.substring(sp).strip();
                    }
                }
                if (css.length > 0) {
                    foreach (string n in names.split(",")) {
                        if (n.strip().length > 0) use_class(n.strip(), line).css_classes.add(css);
                    }
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "style")) {
                string rest = text.substring(5).strip();
                int sp = MermaidSourceLine.first_space(rest);
                if (sp > 0) {
                    use_class(rest.substring(0, sp), line).inline_style = rest.substring(sp).strip();
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "click") ||
                MermaidSourceLine.starts_with_word(text, "link") ||
                MermaidSourceLine.starts_with_word(text, "callback")) {
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "note")) {
                parse_note(text.substring(4).strip(), line);
                return;
            }

            // abstract class Foo / interface class Foo (gDiagram extension)
            if (text.has_prefix("abstract class ") || text.has_prefix("interface class ")) {
                bool iface = text.has_prefix("interface");
                var cls = parse_class_statement(text.substring(iface ? 10 : 9).strip(), line);
                if (cls != null) {
                    cls.class_type = iface ? MermaidClassType.INTERFACE : MermaidClassType.ABSTRACT;
                }
                return;
            }

            if (MermaidSourceLine.starts_with_word(text, "class")) {
                parse_class_statement(text, line);
                return;
            }

            // <<interface>> ClassName
            if (text.has_prefix("<<")) {
                int end = text.index_of(">>");
                if (end > 2) {
                    string stereotype = text.substring(2, end - 2).strip();
                    string target = text.substring(end + 2).strip();
                    if (target.length > 0) {
                        int pos = 0;
                        string? generic;
                        string name = read_name(target, ref pos, out generic);
                        if (name.length > 0) {
                            var cls = use_class(name, line);
                            apply_stereotype(cls, stereotype);
                        }
                    }
                }
                return;
            }

            if (try_relation(text, line)) return;

            // ClassName : +member
            int p = 0;
            string? gen;
            string first = read_name(text, ref p, out gen);
            if (first.length == 0) return;
            var cls = use_class(first, line);
            if (gen != null) cls.generic_type = gen;
            string after = text.substring(p).strip();
            if (after.has_prefix(":::")) {
                read_css_shorthand(cls, after);
                return;
            }
            if (after.has_prefix(":")) {
                string member = after.substring(1).strip();
                if (member.length > 0) parse_body_line(cls, member);
            }
        }

        // class Name~T~["Label"]:::css <<annotation>> { members }
        private MermaidClass? parse_class_statement(string text, int line) {
            string rest = text.has_prefix("class") ? text.substring(5).strip() : text;
            int pos = 0;
            string? generic;
            string name = read_name(rest, ref pos, out generic);
            if (name.length == 0) {
                diagram.errors.add(new ParseError("Expected class name", line, 1));
                return null;
            }
            var cls = use_class(name, line, true);
            if (generic != null) cls.generic_type = generic;
            if (namespaces.size > 0) cls.namespace_name = namespaces[namespaces.size - 1];

            string after = rest.substring(pos).strip();
            // ["Label"]
            if (after.has_prefix("[")) {
                int close = after.index_of("]");
                if (close > 0) {
                    string lbl = MermaidSourceLine.unquote(after.substring(1, close - 1));
                    cls.label = lbl;
                    after = after.substring(close + 1).strip();
                }
            }
            if (after.has_prefix(":::")) {
                int end = 3;
                while (end < after.length && after[end] != ' ' && after[end] != '{' && after[end] != '<') end++;
                cls.css_classes.add(after.substring(3, end - 3));
                after = after.substring(end).strip();
            }
            if (after.has_prefix("<<")) {
                int end = after.index_of(">>");
                if (end > 2) {
                    apply_stereotype(cls, after.substring(2, end - 2).strip());
                    after = after.substring(end + 2).strip();
                }
            }
            if (after.has_prefix("{")) {
                string body = after.substring(1).strip();
                int close = MermaidSourceLine.index_unquoted(body, "}");
                if (close >= 0) {
                    string inner = body.substring(0, close).strip();
                    if (inner.length > 0) parse_body_line(cls, inner);
                } else {
                    body_class = cls;
                    if (body.length > 0) parse_body_line(cls, body);
                }
            }
            return cls;
        }

        private void read_css_shorthand(MermaidClass cls, string after) {
            string css = after.substring(3).strip();
            int sp = MermaidSourceLine.first_space(css);
            if (sp > 0) css = css.substring(0, sp);
            if (css.length > 0) cls.css_classes.add(css);
        }

        private void apply_stereotype(MermaidClass cls, string stereotype) {
            cls.stereotype = stereotype;
            string st = stereotype.down();
            if (st == "interface") cls.class_type = MermaidClassType.INTERFACE;
            else if (st == "abstract") cls.class_type = MermaidClassType.ABSTRACT;
            else if (st == "enum" || st == "enumeration") cls.class_type = MermaidClassType.ENUM;
        }

        private MermaidClass use_class(string name, int line, bool declaration = false) {
            var existing = diagram.find_class(name);
            if (existing != null) {
                if (declaration && existing.source_line <= 0) existing.source_line = line;
                return existing;
            }
            var cls = diagram.get_or_create_class(name);
            cls.source_line = line;
            if (namespaces.size > 0) cls.namespace_name = namespaces[namespaces.size - 1];
            return cls;
        }

        // note for A "text" | note "text"
        private void parse_note(string note_src, int line) {
            string rest = note_src;
            MermaidClass? target = null;
            if (MermaidSourceLine.starts_with_word(rest, "for")) {
                rest = rest.substring(3).strip();
                int pos = 0;
                string? generic;
                string name = read_name(rest, ref pos, out generic);
                if (name.length == 0) return;
                target = use_class(name, line);
                rest = rest.substring(pos).strip();
            }
            string text = MermaidSourceLine.unquote(rest).replace("\\n", "\n").replace("<br>", "\n")
                .replace("<br/>", "\n").replace("<br />", "\n");
            diagram.notes.add(new MermaidClassNote(text, target, line));
        }

        // One member line inside a class body or after "ClassName :"
        private void parse_body_line(MermaidClass cls, string raw) {
            string text = raw.strip();
            if (text.length == 0) return;
            if (text.has_prefix("<<")) {
                int end = text.index_of(">>");
                if (end > 2) apply_stereotype(cls, text.substring(2, end - 2).strip());
                return;
            }

            var member = new MermaidClassMember(text);
            string body = text;
            char first = body[0];
            if (first == '+' || first == '-' || first == '#' || first == '~') {
                member.has_visibility = true;
                switch (first) {
                    case '-': member.visibility = MermaidVisibility.PRIVATE; break;
                    case '#': member.visibility = MermaidVisibility.PROTECTED; break;
                    case '~': member.visibility = MermaidVisibility.PACKAGE; break;
                    default: member.visibility = MermaidVisibility.PUBLIC; break;
                }
                body = body.substring(1).strip();
            }

            int open = body.index_of("(");
            int close = body.last_index_of(")");
            if (open > 0 && close > open) {
                member.is_method = true;
                member.name = MermaidSourceLine.generics(body.substring(0, open).strip());
                member.parameters = MermaidSourceLine.generics(body.substring(open + 1, close - open - 1).strip());
                string tail = body.substring(close + 1).strip();
                // classifier right after ")" or at the very end
                if (tail.has_prefix("$") || tail.has_prefix("*")) {
                    mark_classifier(member, tail[0]);
                    tail = tail.substring(1).strip();
                }
                if (tail.has_suffix("$") || tail.has_suffix("*")) {
                    mark_classifier(member, tail[tail.length - 1]);
                    tail = tail.substring(0, tail.length - 1).strip();
                }
                if (tail.has_prefix(":")) tail = tail.substring(1).strip();
                if (tail.length > 0) member.type_name = MermaidSourceLine.generics(tail);
                var sb = new StringBuilder();
                if (member.has_visibility) sb.append_c(first);
                sb.append(member.name).append("(").append(member.parameters).append(")");
                if (member.type_name != null) sb.append(" : ").append(member.type_name);
                member.display_text = sb.str;
            } else {
                if (body.has_suffix("$") || body.has_suffix("*")) {
                    mark_classifier(member, body[body.length - 1]);
                    body = body.substring(0, body.length - 1).strip();
                }
                string shown = MermaidSourceLine.generics(body);
                int colon = shown.index_of(":");
                if (colon > 0) {
                    // name : Type
                    member.name = shown.substring(0, colon).strip();
                    string t = shown.substring(colon + 1).strip();
                    if (t.length > 0) member.type_name = t;
                } else {
                    // Type name (the last word is the name, as in "List<T> items")
                    int sp = last_top_level_space(shown);
                    if (sp > 0) {
                        member.type_name = shown.substring(0, sp).strip();
                        member.name = shown.substring(sp + 1).strip();
                    } else {
                        member.name = shown;
                    }
                }
                member.display_text = (member.has_visibility ? first.to_string() : "") + shown;
            }
            cls.add_member(member);
        }

        private static void mark_classifier(MermaidClassMember member, char c) {
            if (c == '$') member.is_static = true;
            else if (c == '*') member.is_abstract = true;
        }

        // Last space not inside <...>
        private static int last_top_level_space(string s) {
            int depth = 0;
            int found = -1;
            for (int k = 0; k < s.length; k++) {
                if (s[k] == '<') depth++;
                else if (s[k] == '>' && depth > 0) depth--;
                else if (s[k] == ' ' && depth == 0) found = k;
            }
            return found;
        }

        /**
         * A [cardinality] marker line marker [cardinality] B [: label]
         * with markers <| * o < () on the left, |> * o > () on the right and line -- or ..
         */
        private bool try_relation(string text, int line) {
            int pos = 0;
            string? gen_a;
            string a = read_name(text, ref pos, out gen_a);
            if (a.length == 0) return false;
            skip_ws(text, ref pos);

            string? card_a = null;
            if (pos < text.length && text[pos] == '"') {
                int q = text.index_of("\"", pos + 1);
                if (q < 0) return false;
                card_a = text.substring(pos + 1, q - pos - 1);
                pos = q + 1;
                skip_ws(text, ref pos);
            }

            MermaidRelationEnd left = MermaidRelationEnd.NONE;
            string r = text.substring(pos);
            if (r.has_prefix("<|")) { left = MermaidRelationEnd.INHERITANCE; pos += 2; }
            else if (r.has_prefix("()")) { left = MermaidRelationEnd.LOLLIPOP; pos += 2; }
            else if (r.has_prefix("*")) { left = MermaidRelationEnd.COMPOSITION; pos += 1; }
            else if (r.has_prefix("o--") || r.has_prefix("o..")) { left = MermaidRelationEnd.AGGREGATION; pos += 1; }
            else if (r.has_prefix("<")) { left = MermaidRelationEnd.ARROW; pos += 1; }

            r = text.substring(pos);
            bool dashed;
            if (r.has_prefix("--")) dashed = false;
            else if (r.has_prefix("..")) dashed = true;
            else return false;
            pos += 2;

            // Mermaid's class relations are exactly "--" or ".." plus end markers:
            // "A ---> B" is a parse error there, while gDiagram used to read the extra
            // "-" as the target class name.
            if (pos < text.length && (text[pos] == '-' || text[pos] == '.')) {
                diagram.errors.add(new ParseError(
                    "Invalid relationship: expected '--' or '..'", line, pos + 1));
                return true;
            }

            MermaidRelationEnd right = MermaidRelationEnd.NONE;
            r = text.substring(pos);
            if (r.has_prefix("|>")) { right = MermaidRelationEnd.INHERITANCE; pos += 2; }
            else if (r.has_prefix("()")) { right = MermaidRelationEnd.LOLLIPOP; pos += 2; }
            else if (r.has_prefix("*")) { right = MermaidRelationEnd.COMPOSITION; pos += 1; }
            else if (r.has_prefix(">")) { right = MermaidRelationEnd.ARROW; pos += 1; }
            else if (r.has_prefix("o") && (r.length == 1 || r[1] == ' ' || r[1] == '\t' || r[1] == '"')) {
                right = MermaidRelationEnd.AGGREGATION; pos += 1;
            }
            skip_ws(text, ref pos);

            string? card_b = null;
            if (pos < text.length && text[pos] == '"') {
                int q = text.index_of("\"", pos + 1);
                if (q < 0) return false;
                card_b = text.substring(pos + 1, q - pos - 1);
                pos = q + 1;
                skip_ws(text, ref pos);
            }

            string? gen_b;
            string b = read_name(text, ref pos, out gen_b);
            if (b.length == 0) {
                diagram.errors.add(new ParseError("Expected target class name", line, pos + 1));
                return true;
            }
            skip_ws(text, ref pos);
            string? label = null;
            string rest = text.substring(pos);
            if (rest.has_prefix(":::")) {
                rest = "";
            } else if (rest.has_prefix(":")) {
                label = MermaidSourceLine.unquote(rest.substring(1).strip());
            }

            var from = use_class(a, line);
            if (gen_a != null && from.generic_type == null) from.generic_type = gen_a;
            var to = use_class(b, line);
            if (gen_b != null && to.generic_type == null) to.generic_type = gen_b;

            // Mermaid turns the lollipop end of "I ()-- J" into an interface node (a bare
            // circle with its name) — but only when the other end carries no marker
            if (left == MermaidRelationEnd.LOLLIPOP && right == MermaidRelationEnd.NONE) {
                from.lollipop_interface = true;
            } else if (right == MermaidRelationEnd.LOLLIPOP && left == MermaidRelationEnd.NONE) {
                to.lollipop_interface = true;
            }

            var rel = new MermaidRelation(from, to, relation_type_for(left, right, dashed));
            rel.from_end = left;
            rel.to_end = right;
            rel.dashed = dashed;
            rel.from_cardinality = card_a;
            rel.to_cardinality = card_b;
            if (label != null && label.length > 0) rel.label = label;
            diagram.relations.add(rel);
            return true;
        }

        private static MermaidRelationType relation_type_for(MermaidRelationEnd left, MermaidRelationEnd right,
                                                             bool dashed) {
            if (left == MermaidRelationEnd.INHERITANCE || right == MermaidRelationEnd.INHERITANCE) {
                return dashed ? MermaidRelationType.REALIZATION : MermaidRelationType.INHERITANCE;
            }
            if (left == MermaidRelationEnd.COMPOSITION || right == MermaidRelationEnd.COMPOSITION) {
                return MermaidRelationType.COMPOSITION;
            }
            if (left == MermaidRelationEnd.AGGREGATION || right == MermaidRelationEnd.AGGREGATION) {
                return MermaidRelationType.AGGREGATION;
            }
            if (left == MermaidRelationEnd.NONE && right == MermaidRelationEnd.NONE) {
                return dashed ? MermaidRelationType.DASHED_LINK : MermaidRelationType.LINK;
            }
            return dashed ? MermaidRelationType.DEPENDENCY : MermaidRelationType.ASSOCIATION;
        }

        private static void skip_ws(string s, ref int pos) {
            while (pos < s.length && (s[pos] == ' ' || s[pos] == '\t')) pos++;
        }

        private static string strip_backticks(string s) {
            if (s.length >= 2 && s[0] == '`' && s[s.length - 1] == '`') return s.substring(1, s.length - 2);
            return s;
        }

        /**
         * A class name at `pos`: `backticked name` or a run of name characters, then an
         * optional ~generic~ (returned without the tildes, nested generics as <...>).
         */
        private static string read_name(string s, ref int pos, out string? generic) {
            generic = null;
            skip_ws(s, ref pos);
            if (pos >= s.length) return "";
            string name;
            if (s[pos] == '`') {
                int end = s.index_of("`", pos + 1);
                if (end < 0) return "";
                name = s.substring(pos + 1, end - pos - 1);
                pos = end + 1;
            } else {
                int start = pos;
                while (pos < s.length) {
                    char c = s[pos];
                    if (c == ' ' || c == '\t' || c == '~' || c == '"' || c == ':' || c == '[' ||
                        c == '{' || c == '}' || c == '<' || c == '>' || c == '*' || c == '|' ||
                        c == '(' || c == ')' || c == ',' || c == ';') break;
                    if ((c == '-' || c == '.') && pos + 1 < s.length && (s[pos + 1] == '-' || s[pos + 1] == '.')) break;
                    // "o--" right after a name is an aggregation marker only after a space
                    pos++;
                }
                name = s.substring(start, pos - start);
            }
            if (pos < s.length && s[pos] == '~') {
                // matching closing tilde: the last one before whitespace or a delimiter
                int end = pos + 1;
                int last = -1;
                while (end < s.length && s[end] != ' ' && s[end] != '\t' && s[end] != '[' &&
                       s[end] != '{' && s[end] != ':' && s[end] != '"') {
                    if (s[end] == '~') last = end;
                    end++;
                }
                if (last > pos + 1) {
                    generic = MermaidSourceLine.generics(s.substring(pos + 1, last - pos - 1));
                    pos = last + 1;
                }
            }
            return name;
        }
    }
}
