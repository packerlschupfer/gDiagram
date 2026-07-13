namespace GDiagram {
    public class MermaidERParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidERDiagram diagram;

        public MermaidERParser() {
            this.current = 0;
        }

        public MermaidERDiagram parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidERDiagram();

            try {
                parse_er_diagram();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
            }

            return diagram;
        }

        private void parse_er_diagram() throws GLib.Error {
            skip_newlines();

            // Expect erDiagram keyword
            if (!match(MermaidTokenType.ER_DIAGRAM)) {
                error_at_current("Expected 'erDiagram'");
            }

            skip_newlines();

            // Parse statements until EOF
            while (!is_at_end()) {
                try {
                    parse_statement();
                } catch (GLib.Error e) {
                    diagram.errors.add(new ParseError(
                        e.message,
                        previous().line,
                        previous().column
                    ));
                    synchronize();
                }
                skip_newlines();
            }
        }

        private void parse_statement() throws GLib.Error {
            skip_newlines();

            if (is_at_end()) {
                return;
            }

            // Skip comments
            if (match(MermaidTokenType.COMMENT)) {
                return;
            }

            // Title
            if (check(MermaidTokenType.TITLE)) {
                parse_title();
                return;
            }

            // Skip accessibility annotations (accTitle, accDescr)
            if (check(MermaidTokenType.IDENTIFIER)) {
                string kw = peek().lexeme.down();
                if (kw == "acctitle" || kw == "accdescr") {
                    while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                        advance();
                    }
                    return;
                }
            }

            // Entity or relationship
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_entity_or_relationship();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_title() {
            advance(); // consume 'title'
            var title_parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (title_parts.len > 0) {
                    title_parts.append(" ");
                }
                title_parts.append(advance().lexeme);
            }
            diagram.title = title_parts.str.strip();
        }

        private void parse_entity_or_relationship() throws GLib.Error {
            string first_name = advance().lexeme;

            // Reassemble hyphenated names (e.g. LINE-ITEM tokenised as IDENTIFIER "-" IDENTIFIER)
            while (check(MermaidTokenType.SEQ_SOLID_LINE) &&
                   current + 1 < tokens.size &&
                   tokens.get(current + 1).token_type == MermaidTokenType.IDENTIFIER) {
                advance(); // consume '-'
                first_name = first_name + "-" + advance().lexeme;
            }

            skip_whitespace_same_line();

            // Check if it's a relationship (has cardinality markers)
            if (is_cardinality_marker()) {
                parse_relationship_from(first_name);
            } else if (match(MermaidTokenType.LBRACE)) {
                // Entity with attributes
                parse_entity_attributes(first_name);
            } else {
                // Just an entity reference
                diagram.get_or_create_entity(first_name);
            }
        }

        private void parse_entity_attributes(string entity_name) throws GLib.Error {
            var entity = diagram.get_or_create_entity(entity_name);
            skip_newlines();

            while (!check(MermaidTokenType.RBRACE) && !is_at_end()) {
                parse_attribute(entity);
                skip_newlines();
            }

            if (!match(MermaidTokenType.RBRACE)) {
                error_at_current("Expected '}'");
            }
        }

        private void parse_attribute(MermaidEREntity entity) {
            // Parse: type name or just name
            if (!check(MermaidTokenType.IDENTIFIER)) {
                return;
            }

            string first = advance().lexeme;
            string? type_name = null;
            string attr_name;

            // Check if there's a second identifier (first is type, second is name)
            if (check(MermaidTokenType.IDENTIFIER)) {
                type_name = first;
                attr_name = advance().lexeme;
            } else {
                // Just one identifier - it's the name
                attr_name = first;
            }

            var attr = new MermaidERAttribute(attr_name);
            attr.type_name = type_name;

            // Check for PK / FK constraint keywords
            while (!check(MermaidTokenType.NEWLINE) && !check(MermaidTokenType.RBRACE) && !is_at_end()) {
                if (check(MermaidTokenType.IDENTIFIER)) {
                    string kw = peek().lexeme.up();
                    if (kw == "PK") {
                        attr.is_primary_key = true;
                        advance();
                    } else if (kw == "FK") {
                        attr.is_foreign_key = true;
                        advance();
                    } else {
                        advance();
                    }
                } else {
                    advance();
                }
            }

            entity.add_attribute(attr);
        }

        private void parse_relationship_from(string from_name) throws GLib.Error {
            var from_entity = diagram.get_or_create_entity(from_name);

            // Parse from cardinality
            MermaidERCardinality from_card = parse_cardinality();

            skip_whitespace_same_line();

            // Consume dashes. --o{ is lexed as ARROW_OPEN_SOLID("--o") + LBRACE,
            // and --x{ as ARROW_CROSS_SOLID("--x") + LBRACE, so the 'o'/'x' is
            // already consumed as part of the dash token.
            bool right_starts_with_o = false;
            if (check(MermaidTokenType.ARROW_OPEN_SOLID)) {
                right_starts_with_o = true;
                advance(); // consume "--o"
            } else if (check(MermaidTokenType.ARROW_CROSS_SOLID)) {
                advance(); // consume "--x" (treat same as many)
                right_starts_with_o = true;
            } else {
                consume_dashes();
            }

            skip_whitespace_same_line();

            // Parse to cardinality (right side)
            MermaidERCardinality to_card;
            if (right_starts_with_o) {
                // The 'o' is already consumed; now just check for { or |
                if (match(MermaidTokenType.LBRACE)) {
                    to_card = MermaidERCardinality.ZERO_OR_MORE; // o{
                } else {
                    match(MermaidTokenType.PIPE);
                    to_card = MermaidERCardinality.ZERO_OR_ONE;  // o| or bare o
                }
            } else {
                to_card = parse_cardinality();
            }

            skip_whitespace_same_line();

            // Get target entity
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected target entity name");
            }

            string to_name = advance().lexeme;
            // Reassemble hyphenated names (e.g. LINE-ITEM)
            while (check(MermaidTokenType.SEQ_SOLID_LINE) &&
                   current + 1 < tokens.size &&
                   tokens.get(current + 1).token_type == MermaidTokenType.IDENTIFIER) {
                advance();
                to_name = to_name + "-" + advance().lexeme;
            }
            var to_entity = diagram.get_or_create_entity(to_name);

            var relationship = new MermaidERRelationship(from_entity, to_entity);
            relationship.from_cardinality = from_card;
            relationship.to_cardinality = to_card;

            // Parse label after colon
            if (match(MermaidTokenType.COLON)) {
                var label_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (label_parts.len > 0) {
                        label_parts.append(" ");
                    }
                    label_parts.append(advance().lexeme);
                }
                relationship.label = label_parts.str.strip();
            }

            diagram.relationships.add(relationship);
        }

        private MermaidERCardinality parse_cardinality() {
            // Parse 2-character cardinality notation.
            // Left-to-right variants:  || o| o{ |{
            // Reversed (right-to-left): }| }o |o
            // Consume up to 2 cardinality tokens in any valid order.
            bool has_o = false;
            bool has_pipe = false;
            bool has_brace = false;

            for (int i = 0; i < 2; i++) {
                if (check(MermaidTokenType.LBRACE) || check(MermaidTokenType.RBRACE)) {
                    has_brace = true;
                    advance();
                } else if (peek().lexeme == "o") {
                    has_o = true;
                    advance();
                } else if (check(MermaidTokenType.PIPE)) {
                    has_pipe = true;
                    advance();
                } else {
                    break;
                }
            }

            // Determine cardinality from collected flags
            if (has_pipe && !has_brace && !has_o) {
                return MermaidERCardinality.EXACTLY_ONE;  // ||
            }
            if (has_o && has_pipe) {
                return MermaidERCardinality.ZERO_OR_ONE;  // o| or |o
            }
            if (has_o && has_brace) {
                return MermaidERCardinality.ZERO_OR_MORE; // o{ or }o
            }
            if (has_pipe && has_brace) {
                return MermaidERCardinality.ONE_OR_MORE;  // |{ or }|
            }

            return MermaidERCardinality.ZERO_OR_MORE; // Default
        }

        private bool is_cardinality_marker() {
            // Check if next tokens look like a cardinality marker.
            // Handles both left-to-right (||, o|, |{, o{) and
            // reversed (}|, }o) notation.
            return check(MermaidTokenType.PIPE) ||
                   check(MermaidTokenType.RBRACE) ||
                   (peek().lexeme == "o");
        }

        private void consume_dashes() {
            // Consume -- or ---
            while (check(MermaidTokenType.LINE_SOLID) || check(MermaidTokenType.ARROW_SOLID)) {
                advance();
            }
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        private void skip_whitespace_same_line() {
            // No-op since lexer handles whitespace
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) {
                    return;
                }

                if (check(MermaidTokenType.IDENTIFIER)) {
                    return;
                }

                advance();
            }
        }

        private bool match(MermaidTokenType type) {
            if (check(type)) {
                advance();
                return true;
            }
            return false;
        }

        private bool check(MermaidTokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        private MermaidToken advance() {
            if (!is_at_end()) {
                current++;
            }
            return previous();
        }

        private bool is_at_end() {
            return peek().token_type == MermaidTokenType.EOF;
        }

        private MermaidToken peek() {
            return tokens.get(current);
        }

        private MermaidToken previous() {
            return tokens.get(current - 1);
        }

        private int error_line = 1;
        private int error_column = 1;

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            error_line = token.line;
            error_column = token.column;
            string context = "";
            if (token.lexeme.length > 0) {
                context = " (found: '%s')".printf(token.lexeme);
            }
            throw new GLib.IOError.FAILED("%s%s", message, context);
        }
    }
}
