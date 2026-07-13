namespace GDiagram {
    /**
     * Mermaid erDiagram parser. Statements are read from the source lines (see
     * MermaidSourceLine) instead of MermaidLexer tokens, so attribute names that are
     * keywords elsewhere ("title", "direction", "style") stay attribute names, and
     * comments, keys and aliases keep their text.
     */
    public class MermaidERParser : Object {
        private MermaidERDiagram diagram;
        private MermaidEREntity? body_entity = null;

        private static Regex? symbol_rel = null;
        private static Regex? word_rel = null;
        private static Regex? entity_head = null;

        public MermaidERParser() {
        }

        private static void init_regex() {
            if (symbol_rel != null) return;
            try {
                string name = "(\"[^\"]*\"|[^\\s\"\\[:]+?)(?:\\[[^\\]]*\\])?";
                symbol_rel = new Regex(
                    "^" + name + "\\s*(\\|o|\\|\\||\\}o|\\}\\||o\\||o\\{|\\|\\{)(--|\\.\\.)" +
                    "(o\\||\\|\\||o\\{|\\|\\{|\\|o|\\}o|\\}\\|)\\s*(\"[^\"]*\"|[^\\s\"\\[:]+)(?:\\[[^\\]]*\\])?" +
                    "\\s*(?::\\s*(.*))?$");
                string card = "(one or zero|zero or one|one or more|one or many|many\\(1\\)|1\\+|" +
                              "zero or more|zero or many|many\\(0\\)|0\\+|only one|1)";
                word_rel = new Regex(
                    "^" + name + "\\s+" + card + "\\s+(to|optionally to)\\s+" + card +
                    "\\s+(\"[^\"]*\"|[^\\s\"\\[:]+)(?:\\[[^\\]]*\\])?\\s*(?::\\s*(.*))?$");
                // NAME, NAME["Alias"], NAME[Alias], optional "{" body start
                entity_head = new Regex("^(\"[^\"]*\"|[^\\s\"\\[{:]+)\\s*(?:\\[\\s*(\"[^\"]*\"|[^\\]]*)\\s*\\])?\\s*(:::[^\\s{]+)?\\s*(\\{.*)?$");
            } catch (RegexError e) {
                warning("MermaidERParser regex: %s", e.message);
            }
        }

        public MermaidERDiagram parse(string source) {
            init_regex();
            this.diagram = new MermaidERDiagram();
            body_entity = null;

            string? fm_title;
            bool header_ok;
            var lines = MermaidSourceLine.split(source, { "erDiagram" }, out fm_title, out header_ok);
            if (!header_ok) {
                int line = lines.size > 0 ? lines[0].line : 1;
                diagram.errors.add(new ParseError("Expected 'erDiagram'", line, 1));
                return diagram;
            }
            if (fm_title != null) diagram.title = fm_title;

            int last_line = 1;
            bool in_acc_descr = false;
            foreach (var l in lines) {
                last_line = l.line;
                string text = l.text;
                if (in_acc_descr) {
                    if (text.contains("}")) in_acc_descr = false;
                    continue;
                }
                if (body_entity != null) {
                    int close = MermaidSourceLine.index_unquoted(text, "}");
                    string part = close >= 0 ? text.substring(0, close).strip() : text;
                    if (part.length > 0) parse_attribute(body_entity, part);
                    if (close >= 0) body_entity = null;
                    continue;
                }
                if (text.has_prefix("accTitle") || text.has_prefix("accDescr")) {
                    if (text.has_prefix("accDescr") && !text.contains(":") && text.contains("{") &&
                        !text.contains("}")) {
                        in_acc_descr = true;
                    }
                    continue;
                }
                parse_statement(text, l.line);
            }
            if (body_entity != null) {
                diagram.errors.add(new ParseError(
                    "Expected '}' to close entity '%s'".printf(body_entity.name), last_line, 1));
            }
            return diagram;
        }

        private void parse_statement(string text, int line) {
            if (MermaidSourceLine.starts_with_word(text, "title")) {
                diagram.title = text.substring(5).strip();
                return;
            }
            if (MermaidSourceLine.starts_with_word(text, "direction")) {
                FlowchartDirection dir;
                if (MermaidSourceLine.parse_direction(text.substring(9), out dir)) diagram.direction = dir;
                return;
            }
            if (MermaidSourceLine.starts_with_word(text, "style") ||
                MermaidSourceLine.starts_with_word(text, "classDef") ||
                MermaidSourceLine.starts_with_word(text, "class")) {
                return;
            }

            MatchInfo m;
            if (symbol_rel.match(text, 0, out m)) {
                string left = m.fetch(2);
                string right = m.fetch(4);
                add_relationship(m.fetch(1), m.fetch(5), cardinality_of_symbol(left),
                                 cardinality_of_symbol(right), m.fetch(3) == "--", fetch_opt(m, 6), line);
                return;
            }
            if (word_rel.match(text, 0, out m)) {
                add_relationship(m.fetch(1), m.fetch(5), cardinality_of_word(m.fetch(2)),
                                 cardinality_of_word(m.fetch(4)), m.fetch(3) == "to", fetch_opt(m, 6), line);
                return;
            }
            if (entity_head.match(text, 0, out m)) {
                var entity = use_entity(m.fetch(1), line);
                string alias = fetch_opt(m, 2) ?? "";
                if (alias.strip().length > 0) entity.alias = MermaidSourceLine.unquote(alias.strip());
                string body = fetch_opt(m, 4) ?? "";
                if (body.has_prefix("{")) {
                    // A body line counts as the entity's declaration
                    entity.source_line = line;
                    string rest = body.substring(1).strip();
                    int close = MermaidSourceLine.index_unquoted(rest, "}");
                    if (close >= 0) {
                        string inner = rest.substring(0, close).strip();
                        if (inner.length > 0) parse_attribute(entity, inner);
                    } else {
                        body_entity = entity;
                        if (rest.length > 0) parse_attribute(entity, rest);
                    }
                }
                return;
            }
            diagram.errors.add(new ParseError("Unrecognized ER statement: %s".printf(text), line, 1));
        }

        private static string? fetch_opt(MatchInfo m, int group) {
            int start, end;
            if (!m.fetch_pos(group, out start, out end) || start < 0) return null;
            return m.fetch(group);
        }

        private MermaidEREntity use_entity(string raw_name, int line) {
            string name = MermaidSourceLine.unquote(raw_name);
            var existing = diagram.find_entity(name);
            if (existing != null) return existing;
            var entity = diagram.get_or_create_entity(name);
            entity.source_line = line;
            return entity;
        }

        private void add_relationship(string a, string b, MermaidERCardinality from_card,
                                      MermaidERCardinality to_card, bool identifying, string? label, int line) {
            var from = use_entity(a, line);
            var to = use_entity(b, line);
            var rel = new MermaidERRelationship(from, to);
            rel.from_cardinality = from_card;
            rel.to_cardinality = to_card;
            rel.identifying = identifying;
            if (label != null) {
                string l = MermaidSourceLine.unquote(label.strip());
                if (l.length > 0) rel.label = l;
            }
            diagram.relationships.add(rel);
        }

        private static MermaidERCardinality cardinality_of_symbol(string s) {
            bool o = s.contains("o");
            bool many = s.contains("{") || s.contains("}");
            if (many) return o ? MermaidERCardinality.ZERO_OR_MORE : MermaidERCardinality.ONE_OR_MORE;
            return o ? MermaidERCardinality.ZERO_OR_ONE : MermaidERCardinality.EXACTLY_ONE;
        }

        private static MermaidERCardinality cardinality_of_word(string w) {
            switch (w) {
                case "one or zero": case "zero or one": return MermaidERCardinality.ZERO_OR_ONE;
                case "one or more": case "one or many": case "many(1)": case "1+":
                    return MermaidERCardinality.ONE_OR_MORE;
                case "zero or more": case "zero or many": case "many(0)": case "0+":
                    return MermaidERCardinality.ZERO_OR_MORE;
                default: return MermaidERCardinality.EXACTLY_ONE;
            }
        }

        // type name [PK, FK, UK] ["comment"]
        private void parse_attribute(MermaidEREntity entity, string text) {
            var words = new Gee.ArrayList<string>();
            int i = 0;
            while (i < text.length) {
                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                if (i >= text.length) break;
                int start = i;
                if (text[i] == '"') {
                    int q = text.index_of("\"", i + 1);
                    i = q < 0 ? text.length : q + 1;
                } else {
                    while (i < text.length && text[i] != ' ' && text[i] != '\t' && text[i] != '"') i++;
                }
                words.add(text.substring(start, i - start));
            }
            if (words.size == 0) return;

            MermaidERAttribute attr;
            int next;
            if (words.size >= 2 && !words[1].has_prefix("\"")) {
                attr = new MermaidERAttribute(words[1]);
                attr.type_name = words[0];
                next = 2;
            } else {
                attr = new MermaidERAttribute(words[0]);
                next = 1;
            }
            for (int k = next; k < words.size; k++) {
                string w = words[k];
                if (w.has_prefix("\"")) {
                    attr.comment = MermaidSourceLine.unquote(w);
                    continue;
                }
                foreach (string key in w.split(",")) {
                    switch (key.strip().up()) {
                        case "PK": attr.is_primary_key = true; break;
                        case "FK": attr.is_foreign_key = true; break;
                        case "UK": attr.is_unique_key = true; break;
                        default: break;
                    }
                }
            }
            entity.add_attribute(attr);
        }
    }
}
