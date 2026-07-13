namespace GDiagram {
    public class ClassDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ClassDiagram diagram;

        public ClassDiagramParser() {
            this.current = 0;
        }

        public ClassDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new ClassDiagram();

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
                // Skip diagram name if present (e.g., @startuml DiagramName)
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

            // Visibility-prefixed class declaration: -class, #class, ~class,
            // +class, or any of those before abstract/interface/enum.
            // Lexer emits each prefix as a distinct token: MINUS for `-`,
            // TILDE for `~`, PLUS for `+`, IDENTIFIER "#" for `#`.
            if (is_visibility_prefix_token()) {
                advance();  // skip the prefix marker
                if (check(TokenType.CLASS)) {
                    parse_class_declaration(ClassType.CLASS);
                    return;
                }
                if (check(TokenType.INTERFACE)) {
                    parse_class_declaration(ClassType.INTERFACE);
                    return;
                }
                if (check(TokenType.ABSTRACT)) {
                    advance();
                    if (check(TokenType.CLASS)) {
                        parse_class_declaration(ClassType.ABSTRACT);
                    }
                    return;
                }
                if (check(TokenType.ENUM)) {
                    parse_class_declaration(ClassType.ENUM);
                    return;
                }
                // Prefix wasn't followed by a class keyword — fall through
            }

            // Class declaration
            if (check(TokenType.CLASS)) {
                parse_class_declaration(ClassType.CLASS);
                return;
            }

            // Interface declaration
            if (check(TokenType.INTERFACE)) {
                parse_class_declaration(ClassType.INTERFACE);
                return;
            }

            // Abstract class
            if (check(TokenType.ABSTRACT)) {
                advance();
                if (check(TokenType.CLASS)) {
                    parse_class_declaration(ClassType.ABSTRACT);
                }
                return;
            }

            // Enum declaration
            if (check(TokenType.ENUM)) {
                parse_class_declaration(ClassType.ENUM);
                return;
            }

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Title, header, footer
            if (match(TokenType.TITLE)) {
                diagram.title = parse_text_content();
                return;
            }
            if (match(TokenType.HEADER)) {
                diagram.header = parse_text_content();
                return;
            }
            if (match(TokenType.FOOTER)) {
                diagram.footer = parse_text_content();
                return;
            }

            // Note handling
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Hide/show directives - skip entire line
            if (match(TokenType.HIDE) || match(TokenType.SHOW)) {
                skip_to_end_of_line();
                return;
            }

            // Relationship or identifier (class reference)
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_relationship_or_class();
                return;
            }

            // Unknown - skip to next line
            skip_to_end_of_line();
            if (!is_at_end()) {
                advance();  // consume the newline itself
            }
        }

        private void parse_skinparam() {
            // Parse skinparam directives and store in diagram.skin_params
            // Single line: skinparam PropertyName value
            // Block: skinparam element { PropertyName value ... }

            // Get the first identifier (could be element name or property name)
            // Note: element names like "class", "state", "component" are keywords, not identifiers
            string first_name = "";
            if (check(TokenType.IDENTIFIER) || is_skinparam_element_keyword()) {
                first_name = advance().lexeme;
            } else {
                // No identifier after skinparam - skip line
                skip_to_end_of_line();
                return;
            }

            // Check if this is block syntax
            if (match(TokenType.LBRACE)) {
                // Block syntax: skinparam element { property value ... }
                string element = first_name;
                parse_skinparam_block(element);
            } else {
                // Single line syntax
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }
        }

        private void parse_skinparam_block(string element) {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                // Get property name
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
            // Collect value tokens until newline or closing brace
            // Colors like #1e1e1e are tokenized as # + 1 + e1e1e, so we need to join without spaces
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                // Check if this is a hash starting a color
                if (t.lexeme == "#") {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    // Continue collecting color without spaces
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    // Regular token - add space separator
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

        private bool is_skinparam_element_keyword() {
            // Keywords that can be used as skinparam element names
            switch (peek().token_type) {
                case TokenType.CLASS:
                case TokenType.INTERFACE:
                case TokenType.ABSTRACT:
                case TokenType.ENUM:
                case TokenType.NOTE:
                case TokenType.LEGEND:
                case TokenType.TITLE:
                case TokenType.HEADER:
                case TokenType.FOOTER:
                case TokenType.PARTICIPANT:
                case TokenType.ACTOR:
                case TokenType.BOUNDARY:
                case TokenType.CONTROL:
                case TokenType.ENTITY:
                case TokenType.DATABASE:
                    return true;
                default:
                    return false;
            }
        }

        private void parse_class_declaration(ClassType type) throws Error {
            int line = peek().line;  // Capture line number before consuming keyword
            advance(); // consume class/interface/enum keyword

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected class name");
            }

            // Handle "as Alias" — alias becomes the lookup key; quoted name becomes display label
            string display_name = name;
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "as") {
                advance(); // consume "as"
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    string alias = advance().lexeme;
                    // Register under alias so relationships using the alias resolve correctly
                    var existing = diagram.get_or_create_class(alias, line);
                    existing.class_type = type;
                    existing.display_name = display_name;
                    // Continue with the alias as the working object
                    var uml_class = existing;
                    // Inline the rest of the declaration from here
                    if (match(TokenType.STEREOTYPE)) {
                        uml_class.stereotype = previous().lexeme;
                    }
                    if (match(TokenType.HASH)) {
                        uml_class.color = parse_color();
                    }
                    while (check(TokenType.EXTENDS) || check(TokenType.IMPLEMENTS)) {
                        var rel_type = check(TokenType.EXTENDS) ?
                            RelationshipType.INHERITANCE : RelationshipType.IMPLEMENTATION;
                        advance();
                        if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                            var parent_token = advance();
                            string parent_name = parent_token.lexeme;
                            var parent = diagram.get_or_create_class(parent_name, parent_token.line);
                            var relationship = new ClassRelationship(uml_class, parent, rel_type);
                            diagram.relationships.add(relationship);
                        }
                    }
                    if (match(TokenType.LBRACE)) {
                        parse_class_body(uml_class);
                    }
                    expect_end_of_statement();
                    return;
                }
            }

            var uml_class = diagram.get_or_create_class(name, line);
            uml_class.class_type = type;

            // Check for stereotype <<...>>
            if (match(TokenType.STEREOTYPE)) {
                uml_class.stereotype = previous().lexeme;
            }

            // Check for color specification (e.g., #LightBlue or #1e1e1e)
            if (match(TokenType.HASH)) {
                uml_class.color = parse_color();
            }

            // Check for extends/implements
            while (check(TokenType.EXTENDS) || check(TokenType.IMPLEMENTS)) {
                var rel_type = check(TokenType.EXTENDS) ?
                    RelationshipType.INHERITANCE : RelationshipType.IMPLEMENTATION;
                advance();

                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    var parent_token = advance();
                    string parent_name = parent_token.lexeme;
                    var parent = diagram.get_or_create_class(parent_name, parent_token.line);
                    var relationship = new ClassRelationship(uml_class, parent, rel_type);
                    diagram.relationships.add(relationship);
                }
            }

            // Check for class body
            if (match(TokenType.LBRACE)) {
                parse_class_body(uml_class);
            }

            expect_end_of_statement();
        }

        private string parse_color() {
            // Colors can be: named (LightBlue) or hex (1e1e1e, ABC123)
            // Hex colors starting with digits will be tokenized as IDENTIFIER since they include letters
            var sb = new StringBuilder();
            sb.append("#");

            // Collect color tokens until we hit a newline, brace, or other structural element
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check(TokenType.RBRACE) &&
                   !check(TokenType.EXTENDS) && !check(TokenType.IMPLEMENTS) && !is_at_end()) {
                Token t = peek();
                // Stop at keywords that shouldn't be part of color
                if (t.token_type == TokenType.CLASS || t.token_type == TokenType.INTERFACE ||
                    t.token_type == TokenType.ABSTRACT || t.token_type == TokenType.ENUM) {
                    break;
                }
                // Only collect identifiers as part of color
                if (t.token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }

            return sb.str;
        }

        private void parse_note() {
            int line = peek().line;
            advance(); // consume 'note' keyword

            string position = "right";
            string? attached_to = null;

            // Parse position: left, right, top, bottom
            // The lexer emits these as dedicated token types, not IDENTIFIER
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
            } else if (check(TokenType.IDENTIFIER)) {
                string pos = peek().lexeme.down();
                if (pos == "left" || pos == "right" || pos == "top" || pos == "bottom") {
                    position = pos;
                    advance();
                }
            }

            // Check for 'of' keyword
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "of") {
                advance(); // consume 'of'

                // Get the class name this note is attached to
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            // Check for colon and note text
            string note_text = "";
            if (match(TokenType.COLON)) {
                note_text = consume_rest_of_line();
            } else {
                // Multi-line note: note left of Class\n...text...\nend note
                skip_newlines();
                var sb = new StringBuilder();
                // Only "end note" ends the body — a bare "end" is prose.
                while (!is_at_end() && !(check(TokenType.END) && check_next(TokenType.NOTE))) {
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) {
                            sb.append("\n");
                        }
                        advance();
                    } else {
                        Token t = advance();
                        if (sb.len > 0 && sb.str[sb.len - 1] != '\n') {
                            sb.append(" ");
                        }
                        sb.append(t.lexeme);
                    }
                }
                note_text = sb.str.strip();

                // Consume 'end note' if present
                if (check(TokenType.END) && check_next(TokenType.NOTE)) {
                    advance();  // 'end'
                    advance();  // 'note'
                }
            }

            if (note_text.length > 0) {
                var note = new ClassNote(note_text, line);
                note.position = position;
                note.attached_to = attached_to;
                diagram.notes.add(note);
            }
        }

        private void parse_class_body(UmlClass uml_class) {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                int pos_before = current;

                // Parse member
                MemberVisibility visibility = MemberVisibility.PUBLIC;
                bool is_static = false;
                bool is_abstract = false;

                // Check visibility
                if (match(TokenType.PLUS)) {
                    visibility = MemberVisibility.PUBLIC;
                } else if (match(TokenType.MINUS)) {
                    visibility = MemberVisibility.PRIVATE;
                } else if (match(TokenType.HASH)) {
                    visibility = MemberVisibility.PROTECTED;
                } else if (match(TokenType.TILDE)) {
                    visibility = MemberVisibility.PACKAGE;
                }

                // Check for static/abstract markers: {static} or {abstract}
                if (match(TokenType.LBRACE)) {
                    if (check(TokenType.IDENTIFIER) || check(TokenType.ABSTRACT)) {
                        string modifier = advance().lexeme.down();
                        if (modifier == "static") {
                            is_static = true;
                        } else if (modifier == "abstract") {
                            is_abstract = true;
                        }
                    }
                    match(TokenType.RBRACE);
                }

                // Get member name and check if it's a method
                if (check(TokenType.IDENTIFIER) || check(TokenType.ABSTRACT) ||
                    check(TokenType.CLASS) || check(TokenType.INTERFACE) ||
                    check(TokenType.ENUM)) {
                    string member_text = consume_member_text();
                    bool is_method = member_text.contains("(");

                    var member = new ClassMember(member_text, is_method);
                    member.visibility = visibility;
                    member.is_static = is_static;
                    member.is_abstract = is_abstract;
                    uml_class.add_member(member);
                }

                // Safety: if no tokens consumed in this iteration, skip to next line
                if (current == pos_before) {
                    skip_to_end_of_line();
                    if (!check(TokenType.RBRACE) && !is_at_end()) {
                        advance();
                    }
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private string consume_member_text() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();
                string lex = t.lexeme;
                // Add a space between tokens unless attaching to opening paren, closing
                // paren/bracket/comma, or the first token on this line.
                if (sb.len > 0) {
                    string tail = sb.str[sb.str.length - 1 : sb.str.length];
                    bool glue = tail == "(" || lex == ")" || lex == "]" || lex == "," ||
                                tail == "[" || lex == "(" || lex == "[";
                    if (!glue) sb.append(" ");
                }
                sb.append(lex);
            }

            return sb.str.strip();
        }

        private void parse_relationship_or_class() {
            // Get first class name
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

            var from_class = diagram.get_or_create_class(from_name, from_line);

            // Check for relationship arrow
            RelationshipType? rel_type = null;
            bool reverse = false;
            bool undirected = false;

            if (match(TokenType.INHERITANCE)) {
                rel_type = RelationshipType.INHERITANCE;
                reverse = previous().lexeme.has_prefix("<");
            } else if (match(TokenType.IMPLEMENTATION)) {
                rel_type = RelationshipType.IMPLEMENTATION;
                reverse = previous().lexeme.has_prefix("<");
            } else if (match(TokenType.AGGREGATION)) {
                rel_type = RelationshipType.AGGREGATION;
                reverse = previous().lexeme.has_prefix("o");
            } else if (match(TokenType.COMPOSITION)) {
                rel_type = RelationshipType.COMPOSITION;
                reverse = previous().lexeme.has_prefix("*");
            } else if (match(TokenType.DEPENDENCY)) {
                rel_type = RelationshipType.DEPENDENCY;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                rel_type = RelationshipType.DEPENDENCY;
            } else if (match(TokenType.ARROW_RIGHT)) {
                rel_type = RelationshipType.ASSOCIATION;
            } else if (match(TokenType.ARROW_LEFT)) {
                rel_type = RelationshipType.ASSOCIATION;
                reverse = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                rel_type = RelationshipType.ASSOCIATION;
                undirected = true;
            } else if (match(TokenType.DOT_DOT)) {
                rel_type = RelationshipType.DEPENDENCY;
                undirected = true;
            }

            if (rel_type != null) {
                // Get second class name
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

                var to_class = diagram.get_or_create_class(to_name, to_line);

                ClassRelationship relationship;
                if (reverse) {
                    relationship = new ClassRelationship(to_class, from_class, rel_type);
                } else {
                    relationship = new ClassRelationship(from_class, to_class, rel_type);
                }

                relationship.undirected = undirected;

                // Optional label after colon
                if (match(TokenType.COLON)) {
                    relationship.label = consume_rest_of_line();
                }

                diagram.relationships.add(relationship);
            }

            expect_end_of_statement();
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

        private string parse_text_content() {
            // Handle title/header/footer content
            // Can be: "text", text until end of line, or multi-line
            var sb = new StringBuilder();

            if (check(TokenType.STRING)) {
                return advance().lexeme;
            }

            // Consume rest of line
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
                    case TokenType.CLASS:
                    case TokenType.INTERFACE:
                    case TokenType.ABSTRACT:
                    case TokenType.ENUM:
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

        // True if the current token is one of the visibility-prefix markers
        // (-, #, ~, +) and the NEXT token is a class-declaration keyword.
        // Used by the main dispatch to consume the prefix and then parse the
        // class declaration normally.
        private bool is_visibility_prefix_token() {
            if (is_at_end()) return false;
            var t = peek();
            bool is_prefix = t.token_type == TokenType.MINUS ||
                             t.token_type == TokenType.TILDE ||
                             t.token_type == TokenType.PLUS ||
                             (t.token_type == TokenType.IDENTIFIER && t.lexeme == "#");
            if (!is_prefix) return false;
            // Look at the next token
            if (current + 1 >= tokens.size) return false;
            var next = tokens[current + 1].token_type;
            return next == TokenType.CLASS ||
                   next == TokenType.INTERFACE ||
                   next == TokenType.ABSTRACT ||
                   next == TokenType.ENUM;
        }

        private bool match(TokenType type) {
            if (check(type)) {
                advance();
                return true;
            }
            return false;
        }

        /**
         * Type of the token after the current one. Needed to recognise the
         * two-token "end note" terminator without consuming a bare "end"
         * that is simply a word in the note body.
         */
        private bool check_next(TokenType type) {
            if (current + 1 >= tokens.size) {
                return false;
            }
            return tokens.get(current + 1).token_type == type;
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
