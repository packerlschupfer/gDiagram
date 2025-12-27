namespace GDiagram {
    public class ERDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ERDiagram diagram;

        public ERDiagramParser() {
            this.current = 0;
        }

        public ERDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new ERDiagram();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, peek().line, peek().column));
            }

            return diagram;
        }

        private void parse_diagram() throws Error {
            // Skip @startuml if present
            if (check(TokenType.STARTUML)) {
                advance();
                skip_newlines();
            }

            while (!is_at_end() && !check(TokenType.ENDUML)) {
                skip_newlines();

                if (is_at_end() || check(TokenType.ENDUML)) {
                    break;
                }

                if (!parse_statement()) {
                    // Skip unrecognized token
                    advance();
                }

                skip_newlines();
            }
        }

        private bool parse_statement() throws Error {
            skip_newlines();

            if (check(TokenType.COMMENT)) {
                advance();
                return true;
            }

            // Title
            if (check(TokenType.TITLE)) {
                parse_title();
                return true;
            }

            // Header/Footer
            if (check(TokenType.HEADER)) {
                parse_header();
                return true;
            }

            if (check(TokenType.FOOTER)) {
                parse_footer();
                return true;
            }

            // Direction
            if (try_parse_direction()) {
                return true;
            }

            // Skinparam
            if (check(TokenType.SKINPARAM)) {
                parse_skinparam();
                return true;
            }

            // Entity
            if (check(TokenType.ENTITY)) {
                parse_entity();
                return true;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return true;
            }

            // Relationship (identifier with cardinality markers)
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                return parse_relationship_or_entity();
            }

            return false;
        }

        private void parse_title() throws Error {
            advance(); // consume 'title'
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) sb.append(" ");
                if (t.token_type == TokenType.STRING) {
                    sb.append(t.lexeme);
                } else {
                    sb.append(t.lexeme);
                }
            }

            diagram.title = sb.str.strip();
        }

        private void parse_header() throws Error {
            advance(); // consume 'header'
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) sb.append(" ");
                sb.append(t.lexeme);
            }

            diagram.header = sb.str.strip();
        }

        private void parse_footer() throws Error {
            advance(); // consume 'footer'
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) sb.append(" ");
                sb.append(t.lexeme);
            }

            diagram.footer = sb.str.strip();
        }

        private bool try_parse_direction() throws Error {
            if (check(TokenType.LEFT) || match_sequence("left", "to", "right", "direction")) {
                int pos = current;
                if (check_identifier("left") && check_identifier_at(1, "to") &&
                    check_identifier_at(2, "right") && check_identifier_at(3, "direction")) {
                    advance(); advance(); advance(); advance();
                    diagram.left_to_right = true;
                    return true;
                }
                current = pos;
            }

            if (check(TokenType.TOP) || match_sequence("top", "to", "bottom", "direction")) {
                int pos = current;
                if (check_identifier("top") && check_identifier_at(1, "to") &&
                    check_identifier_at(2, "bottom") && check_identifier_at(3, "direction")) {
                    advance(); advance(); advance(); advance();
                    diagram.left_to_right = false;
                    return true;
                }
                current = pos;
            }

            return false;
        }

        private bool check_identifier(string name) {
            return check(TokenType.IDENTIFIER) && peek().lexeme.down() == name;
        }

        private bool check_identifier_at(int offset, string name) {
            if (current + offset >= tokens.size) return false;
            Token t = tokens.get(current + offset);
            return t.token_type == TokenType.IDENTIFIER && t.lexeme.down() == name;
        }

        private bool match_sequence(string s1, string s2, string s3, string s4) {
            return check_identifier(s1);
        }

        private void parse_skinparam() throws Error {
            advance(); // consume 'skinparam'
            skip_whitespace_tokens();

            if (check(TokenType.LBRACE)) {
                // Block skinparam
                advance();
                parse_skinparam_block();
            } else {
                // Single line skinparam
                parse_skinparam_single();
            }
        }

        private void parse_skinparam_block() throws Error {
            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) break;

                // Read element and property
                if (check(TokenType.IDENTIFIER)) {
                    string element = advance().lexeme;
                    skip_whitespace_tokens();

                    if (check(TokenType.IDENTIFIER)) {
                        string property = advance().lexeme;
                        skip_whitespace_tokens();

                        // Read value
                        string value = read_until_newline();
                        diagram.skin_params.set_element_property(element.down(), property, value);
                    }
                }

                skip_newlines();
            }

            if (check(TokenType.RBRACE)) {
                advance();
            }
        }

        private void parse_skinparam_single() throws Error {
            if (!check(TokenType.IDENTIFIER)) return;

            string element = advance().lexeme;
            skip_whitespace_tokens();

            // Check if there's a property name or just a value
            if (check(TokenType.IDENTIFIER)) {
                string second = peek().lexeme;

                // Common properties that might be specified
                if (second == "BackgroundColor" || second == "BorderColor" ||
                    second == "FontColor" || second == "FontSize" || second == "FontName") {
                    advance();
                    skip_whitespace_tokens();
                    string value = read_until_newline();
                    diagram.skin_params.set_element_property(element.down(), second, value);
                } else {
                    // Single element with value
                    string value = read_until_newline();
                    diagram.skin_params.set_property(element, value);
                }
            }
        }

        private void parse_entity() throws Error {
            advance(); // consume 'entity'
            skip_whitespace_tokens();

            int line = peek().line;
            string name;

            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                diagram.errors.add(new ParseError("Expected entity name", line, peek().column));
                return;
            }

            var entity = diagram.get_or_create_entity(name, line);

            // Check for alias
            skip_whitespace_tokens();
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace_tokens();
                if (check(TokenType.IDENTIFIER)) {
                    entity.alias = advance().lexeme;
                }
            }

            // Check for color
            skip_whitespace_tokens();
            if (check(TokenType.HASH)) {
                entity.color = parse_color();
            }

            // Check for body
            skip_whitespace_tokens();
            if (check(TokenType.LBRACE)) {
                parse_entity_body(entity);
            }
        }

        private void parse_entity_body(EREntity entity) throws Error {
            advance(); // consume '{'
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) break;

                // Check for separator line (---)
                if (check(TokenType.MINUS_MINUS) || check(TokenType.MINUS)) {
                    // Skip separator
                    while (check(TokenType.MINUS_MINUS) || check(TokenType.MINUS)) {
                        advance();
                    }
                    entity.has_separator = true;
                    skip_newlines();
                    continue;
                }

                // Parse attribute
                parse_entity_attribute(entity);
                skip_newlines();
            }

            if (check(TokenType.RBRACE)) {
                advance();
            }
        }

        private void parse_entity_attribute(EREntity entity) throws Error {
            // Check for key marker
            ERAttributeType attr_type = ERAttributeType.NORMAL;
            int line = peek().line;

            // Check for * (primary key marker)
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "*") {
                advance();
                attr_type = ERAttributeType.PRIMARY_KEY;
                skip_whitespace_tokens();
            }

            // Alternative: check for <<PK>> or <<FK>> stereotypes later

            if (!check(TokenType.IDENTIFIER) && !check(TokenType.STRING)) {
                return;
            }

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else {
                name = advance().lexeme;
            }

            var attr = new ERAttribute(name, null, line);
            attr.attr_type = attr_type;

            skip_whitespace_tokens();

            // Check for : type
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace_tokens();

                var type_sb = new StringBuilder();
                while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) &&
                       !check(TokenType.STEREOTYPE) && !is_at_end()) {
                    Token t = peek();

                    // Check for <<PK>> or <<FK>>
                    if (t.token_type == TokenType.IDENTIFIER && t.lexeme.has_prefix("<<")) {
                        break;
                    }

                    if (type_sb.len > 0) type_sb.append(" ");
                    type_sb.append(advance().lexeme);
                }
                attr.data_type = type_sb.str.strip();
            }

            // Check for stereotype <<PK>> or <<FK>>
            if (check(TokenType.STEREOTYPE)) {
                string stereo = advance().lexeme.up();
                if (stereo == "PK" || stereo == "PRIMARY KEY") {
                    attr.attr_type = ERAttributeType.PRIMARY_KEY;
                } else if (stereo == "FK" || stereo == "FOREIGN KEY") {
                    attr.attr_type = ERAttributeType.FOREIGN_KEY;
                }
            }

            entity.attributes.add(attr);
        }

        private bool parse_relationship_or_entity() throws Error {
            int line = peek().line;

            // Get first entity name
            string from_name;
            if (check(TokenType.STRING)) {
                from_name = advance().lexeme;
            } else {
                from_name = advance().lexeme;
            }

            skip_whitespace_tokens();

            // Check for relationship markers: ||, |o, }o, }|, o{, etc.
            // Or simple arrows: --, .., -->, ..>

            // Check for cardinality markers
            ERCardinality from_card = ERCardinality.ONE_MANDATORY;
            ERCardinality to_card = ERCardinality.MANY_MANDATORY;
            bool is_identifying = false;
            bool is_dashed = false;

            // Parse from cardinality
            if (check(TokenType.PIPE)) {
                advance();
                if (check(TokenType.PIPE)) {
                    advance();
                    from_card = ERCardinality.ONE_MANDATORY;
                } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "o") {
                    advance();
                    from_card = ERCardinality.ZERO_OR_ONE;
                }
            } else if (check(TokenType.RBRACE)) {
                advance();
                if (check(TokenType.PIPE)) {
                    advance();
                    from_card = ERCardinality.MANY_MANDATORY;
                } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "o") {
                    advance();
                    from_card = ERCardinality.ZERO_OR_MANY;
                }
            }

            // Parse line (-- or ..)
            if (check(TokenType.MINUS_MINUS)) {
                advance();
                is_dashed = false;
            } else if (check(TokenType.DEPENDENCY)) {
                advance();
                is_dashed = true;
            } else if (check(TokenType.ARROW_RIGHT_DOTTED)) {
                advance();
                is_dashed = true;
            } else if (check(TokenType.ARROW_RIGHT)) {
                advance();
                is_dashed = false;
            } else {
                // This might be an entity declaration without body
                var entity = diagram.get_or_create_entity(from_name, line);

                // Check for alias
                if (check(TokenType.AS)) {
                    advance();
                    skip_whitespace_tokens();
                    if (check(TokenType.IDENTIFIER)) {
                        entity.alias = advance().lexeme;
                    }
                }

                // Check for color
                if (check(TokenType.HASH)) {
                    entity.color = parse_color();
                }

                return true;
            }

            // Parse to cardinality
            if (check(TokenType.PIPE)) {
                advance();
                if (check(TokenType.PIPE)) {
                    advance();
                    to_card = ERCardinality.ONE_MANDATORY;
                } else if (check(TokenType.LBRACE)) {
                    advance();
                    to_card = ERCardinality.ONE_TO_MANY;
                }
            } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "o") {
                advance();
                if (check(TokenType.PIPE)) {
                    advance();
                    to_card = ERCardinality.ZERO_OR_ONE;
                } else if (check(TokenType.LBRACE)) {
                    advance();
                    to_card = ERCardinality.ZERO_OR_MANY;
                }
            }

            skip_whitespace_tokens();

            // Get to entity name
            string to_name;
            if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                diagram.errors.add(new ParseError("Expected entity name in relationship", line, peek().column));
                return false;
            }

            // Create relationship
            var rel = new ERRelationship(from_name, to_name, line);
            rel.from_cardinality = from_card;
            rel.to_cardinality = to_card;
            rel.is_identifying = is_identifying;
            rel.is_dashed = is_dashed;

            // Check for label
            skip_whitespace_tokens();
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace_tokens();

                var label_sb = new StringBuilder();
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    if (label_sb.len > 0) label_sb.append(" ");
                    label_sb.append(advance().lexeme);
                }
                rel.label = label_sb.str.strip();
            }

            diagram.relationships.add(rel);

            // Ensure entities exist
            diagram.get_or_create_entity(from_name, line);
            diagram.get_or_create_entity(to_name, line);

            return true;
        }

        private void parse_note() throws Error {
            advance(); // consume 'note'
            skip_whitespace_tokens();

            int line = peek().line;
            string position = "right";
            string? attached_to = null;

            // Check position: left, right, top, bottom
            if (check(TokenType.LEFT)) {
                position = "left";
                advance();
            } else if (check(TokenType.RIGHT)) {
                position = "right";
                advance();
            } else if (check(TokenType.TOP)) {
                position = "top";
                advance();
            } else if (check(TokenType.BOTTOM)) {
                position = "bottom";
                advance();
            }

            skip_whitespace_tokens();

            // Check for 'of' entity
            if (check(TokenType.OF)) {
                advance();
                skip_whitespace_tokens();

                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            skip_whitespace_tokens();

            // Check for note content
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace_tokens();

                var text_sb = new StringBuilder();
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    if (text_sb.len > 0) text_sb.append(" ");
                    text_sb.append(advance().lexeme);
                }

                var note = new ERNote(text_sb.str.strip(), line);
                note.attached_to = attached_to;
                note.position = position;
                diagram.notes.add(note);
            } else {
                // Multi-line note
                skip_newlines();
                var text_sb = new StringBuilder();

                while (!is_at_end()) {
                    if (check(TokenType.END) && check_identifier_at(1, "note")) {
                        advance(); advance(); // consume 'end note'
                        break;
                    }

                    if (check(TokenType.NEWLINE)) {
                        if (text_sb.len > 0) text_sb.append("\n");
                        advance();
                    } else {
                        if (text_sb.len > 0 && !text_sb.str.has_suffix("\n")) {
                            text_sb.append(" ");
                        }
                        text_sb.append(advance().lexeme);
                    }
                }

                var note = new ERNote(text_sb.str.strip(), line);
                note.attached_to = attached_to;
                note.position = position;
                diagram.notes.add(note);
            }
        }

        private string parse_color() {
            var sb = new StringBuilder();
            sb.append("#");

            if (check(TokenType.HASH)) {
                advance();
            }

            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check(TokenType.RBRACE) &&
                   !check(TokenType.AS) && !is_at_end()) {
                Token t = peek();
                if (t.token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }

            return sb.str;
        }

        private string read_until_newline() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                if (sb.len > 0) sb.append(" ");
                sb.append(advance().lexeme);
            }

            return sb.str.strip();
        }

        private void skip_newlines() {
            while (check(TokenType.NEWLINE) || check(TokenType.COMMENT)) {
                advance();
            }
        }

        private void skip_whitespace_tokens() {
            // In our lexer, whitespace is consumed, so this is mostly for comments
            while (check(TokenType.COMMENT)) {
                advance();
            }
        }

        private bool check(TokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        private Token peek() {
            return tokens.get(current);
        }

        private Token advance() {
            if (!is_at_end()) current++;
            return tokens.get(current - 1);
        }

        private bool is_at_end() {
            return current >= tokens.size || peek().token_type == TokenType.EOF;
        }
    }
}
