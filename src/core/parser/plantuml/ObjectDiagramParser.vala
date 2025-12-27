namespace GDiagram {
    public class ObjectDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ObjectDiagram diagram;

        public ObjectDiagramParser() {
            this.current = 0;
        }

        public ObjectDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new ObjectDiagram();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_diagram() throws Error {
            skip_newlines();

            // Skip @startuml and any diagram name after it
            if (match(TokenType.STARTUML)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                skip_newlines();
            }

            // Parse statements until @enduml
            while (!check(TokenType.ENDUML) && !is_at_end()) {
                try {
                    parse_statement();
                } catch (Error e) {
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

        private void parse_statement() throws Error {
            skip_newlines();

            if (is_at_end() || check(TokenType.ENDUML)) {
                return;
            }

            // Skip comments
            if (match(TokenType.COMMENT)) {
                return;
            }

            // Object declaration
            if (check(TokenType.OBJECT)) {
                parse_object_declaration();
                return;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Title, header, footer
            if (match(TokenType.TITLE)) {
                diagram.title = consume_rest_of_line();
                return;
            }
            if (match(TokenType.HEADER)) {
                diagram.header = consume_rest_of_line();
                return;
            }
            if (match(TokenType.FOOTER)) {
                diagram.footer = consume_rest_of_line();
                return;
            }

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Link or identifier reference (object Name or Name --> Name2)
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_link_or_object();
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        private void parse_object_declaration() throws Error {
            int line = advance().line;  // consume "object"

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected object name");
            }

            var obj = diagram.get_or_create_object(name, line);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    obj.alias = advance().lexeme;
                }
            }

            // Check for stereotype <<...>>
            if (match(TokenType.STEREOTYPE)) {
                obj.stereotype = previous().lexeme;
            }

            // Check for color
            if (match(TokenType.HASH)) {
                obj.color = parse_color();
            }

            // Check for object body with fields
            if (match(TokenType.LBRACE)) {
                parse_object_body(obj);
            }

            expect_end_of_statement();
        }

        private void parse_object_body(ObjectInstance obj) throws Error {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                // Parse field: name = value
                if (check(TokenType.IDENTIFIER)) {
                    string field_name = advance().lexeme;

                    // Skip optional colon or equals
                    match(TokenType.COLON);
                    match(TokenType.EQUALS);

                    // Get field value
                    string value = consume_rest_of_line();
                    if (value.length > 0) {
                        obj.fields.add(new ObjectField(field_name, value));
                    }
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private void parse_link_or_object() throws Error {
            // Get first object name
            string from_name;
            int from_line;
            if (check(TokenType.STRING)) {
                var token = advance();
                from_name = token.lexeme;
                from_line = token.line;
            } else {
                var token = advance();
                from_name = token.lexeme;
                from_line = token.line;
            }

            // Check for object field assignment: ObjectName : field = value
            if (match(TokenType.COLON)) {
                var obj = diagram.get_or_create_object(from_name, from_line);
                string rest = consume_rest_of_line();

                // Parse field = value
                int eq_pos = rest.index_of("=");
                if (eq_pos > 0) {
                    string field_name = rest.substring(0, eq_pos).strip();
                    string field_value = rest.substring(eq_pos + 1).strip();
                    obj.fields.add(new ObjectField(field_name, field_value));
                }
                return;
            }

            // Check for link arrow
            ObjectLinkType? link_type = null;
            bool is_dashed = false;
            bool reverse = false;

            if (match(TokenType.ARROW_RIGHT)) {
                link_type = ObjectLinkType.ASSOCIATION;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                link_type = ObjectLinkType.DEPENDENCY;
                is_dashed = true;
            } else if (match(TokenType.ARROW_LEFT)) {
                link_type = ObjectLinkType.ASSOCIATION;
                reverse = true;
            } else if (match(TokenType.ARROW_LEFT_DOTTED)) {
                link_type = ObjectLinkType.DEPENDENCY;
                is_dashed = true;
                reverse = true;
            } else if (match(TokenType.AGGREGATION)) {
                link_type = ObjectLinkType.AGGREGATION;
                reverse = previous().lexeme.has_prefix("o");
            } else if (match(TokenType.COMPOSITION)) {
                link_type = ObjectLinkType.COMPOSITION;
                reverse = previous().lexeme.has_prefix("*");
            } else if (match(TokenType.MINUS_MINUS)) {
                link_type = ObjectLinkType.ASSOCIATION;
            }

            if (link_type != null) {
                // Get second object name
                string to_name;
                int to_line;
                if (check(TokenType.STRING)) {
                    var token = advance();
                    to_name = token.lexeme;
                    to_line = token.line;
                } else if (check(TokenType.IDENTIFIER)) {
                    var token = advance();
                    to_name = token.lexeme;
                    to_line = token.line;
                } else {
                    expect_end_of_statement();
                    return;
                }

                // Create objects if they don't exist
                diagram.get_or_create_object(from_name, from_line);
                diagram.get_or_create_object(to_name, to_line);

                ObjectLink link;
                if (reverse) {
                    link = new ObjectLink(to_name, from_name, link_type);
                } else {
                    link = new ObjectLink(from_name, to_name, link_type);
                }
                link.is_dashed = is_dashed;

                // Optional label after colon
                if (match(TokenType.COLON)) {
                    link.label = consume_rest_of_line();
                }

                diagram.links.add(link);
            } else {
                // Just an object reference - ensure it exists
                diagram.get_or_create_object(from_name, from_line);
            }

            expect_end_of_statement();
        }

        private void parse_note() throws Error {
            int line = advance().line;  // consume "note"

            string position = "right";
            if (match(TokenType.LEFT)) {
                position = "left";
            } else if (match(TokenType.RIGHT)) {
                position = "right";
            } else if (match(TokenType.TOP)) {
                position = "top";
            } else if (match(TokenType.BOTTOM)) {
                position = "bottom";
            }

            string? attached_to = null;

            // "of ObjectName"
            if (match(TokenType.OF)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            // Note text
            var sb = new StringBuilder();

            if (match(TokenType.COLON)) {
                sb.append(consume_rest_of_line());
            } else {
                skip_newlines();
                // Multi-line note until "end note"
                while (!is_at_end()) {
                    if (check(TokenType.END)) {
                        advance();
                        if (check(TokenType.NOTE)) {
                            advance();
                            break;
                        }
                    }
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) sb.append("\n");
                        advance();
                    } else {
                        sb.append(advance().lexeme);
                        sb.append(" ");
                    }
                }
            }

            var note = new ObjectNote(sb.str.strip(), line);
            note.attached_to = attached_to;
            note.position = position;
            diagram.notes.add(note);
        }

        private string parse_color() {
            var sb = new StringBuilder();
            sb.append("#");

            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                Token t = peek();
                if (t.token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }

            return sb.str;
        }

        private void parse_skinparam() throws Error {
            string first_name = "";
            if (check(TokenType.IDENTIFIER) || check(TokenType.OBJECT)) {
                first_name = advance().lexeme;
            } else {
                skip_to_end_of_line();
                return;
            }

            if (match(TokenType.LBRACE)) {
                parse_skinparam_block(first_name);
            } else {
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }
        }

        private void parse_skinparam_block(string element) throws Error {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                if (!check(TokenType.IDENTIFIER)) {
                    advance();
                    continue;
                }

                string property = advance().lexeme;
                string value = collect_skinparam_value();

                if (value.length > 0) {
                    diagram.skin_params.set_element_property(element, property, value);
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private string collect_skinparam_value() {
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                if (t.lexeme == "#") {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            return sb.str.strip();
        }

        private void skip_to_end_of_line() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private string consume_rest_of_line() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        private void expect_end_of_statement() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == TokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case TokenType.OBJECT:
                    case TokenType.NOTE:
                    case TokenType.ENDUML:
                        return;
                    default:
                        advance();
                        break;
                }
            }
        }

        private void skip_newlines() {
            while (match(TokenType.NEWLINE) || match(TokenType.COMMENT)) {
                // keep skipping
            }
        }

        private bool match(TokenType type) {
            if (check(type)) {
                advance();
                return true;
            }
            return false;
        }

        private bool check(TokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        private Token advance() {
            if (!is_at_end()) {
                current++;
            }
            return previous();
        }

        private bool is_at_end() {
            return peek().token_type == TokenType.EOF;
        }

        private Token peek() {
            return tokens.get(current);
        }

        private Token previous() {
            return tokens.get(current - 1);
        }
    }
}
