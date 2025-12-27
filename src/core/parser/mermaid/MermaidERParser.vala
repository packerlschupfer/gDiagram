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
                diagram.errors.add(new ParseError(e.message, 1, 1));
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

            // Entity or relationship
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_entity_or_relationship();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_title() throws GLib.Error {
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

        private void parse_attribute(MermaidEREntity entity) throws GLib.Error {
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

            entity.add_attribute(attr);

            // Consume rest of line
            while (!check(MermaidTokenType.NEWLINE) && !check(MermaidTokenType.RBRACE) && !is_at_end()) {
                advance();
            }
        }

        private void parse_relationship_from(string from_name) throws GLib.Error {
            var from_entity = diagram.get_or_create_entity(from_name);

            // Parse from cardinality
            MermaidERCardinality from_card = parse_cardinality();

            skip_whitespace_same_line();

            // Expect dashes
            consume_dashes();

            skip_whitespace_same_line();

            // Parse to cardinality
            MermaidERCardinality to_card = parse_cardinality();

            skip_whitespace_same_line();

            // Get target entity
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected target entity name");
            }

            string to_name = advance().lexeme;
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

        private MermaidERCardinality parse_cardinality() throws GLib.Error {
            // Parse cardinality notation: ||, o|, |{, o{
            bool has_o = false;
            bool has_pipe = false;
            bool has_brace = false;

            // Check for 'o'
            if (peek().lexeme == "o") {
                has_o = true;
                advance();
            }

            // Check for '|'
            if (check(MermaidTokenType.PIPE)) {
                has_pipe = true;
                advance();
            }

            // Check for '{' or another '|'
            if (check(MermaidTokenType.LBRACE)) {
                has_brace = true;
                advance();
            } else if (check(MermaidTokenType.PIPE)) {
                has_pipe = true;
                advance();
            }

            // Determine cardinality
            if (has_pipe && !has_brace && !has_o) {
                return MermaidERCardinality.EXACTLY_ONE;  // ||
            }
            if (has_o && has_pipe) {
                return MermaidERCardinality.ZERO_OR_ONE;  // o|
            }
            if (has_o && has_brace) {
                return MermaidERCardinality.ZERO_OR_MORE; // o{
            }
            if (has_pipe && has_brace) {
                return MermaidERCardinality.ONE_OR_MORE;  // |{
            }

            return MermaidERCardinality.ZERO_OR_MORE; // Default
        }

        private bool is_cardinality_marker() {
            // Check if next tokens look like cardinality (||, o|, |{, o{)
            return check(MermaidTokenType.PIPE) ||
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

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            string context = "";
            if (token.lexeme.length > 0) {
                context = " (found: '%s')".printf(token.lexeme);
            }
            throw new GLib.IOError.FAILED("Line %d: %s%s", token.line, message, context);
        }
    }
}
