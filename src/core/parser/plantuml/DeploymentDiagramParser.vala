namespace GDiagram {
    public class DeploymentDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private DeploymentDiagram diagram;

        public DeploymentDiagramParser() {
            this.current = 0;
        }

        public DeploymentDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new DeploymentDiagram();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_diagram() throws Error {
            skip_newlines();

            // Skip @startuml
            if (match(TokenType.STARTUML)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                skip_newlines();
            }

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

            if (match(TokenType.COMMENT)) {
                return;
            }

            // Direction
            if (check(TokenType.LEFT)) {
                if (try_parse_direction()) return;
            }

            // Node types
            if (check(TokenType.NODE_KW)) {
                parse_node_declaration(DeploymentNodeType.NODE);
                return;
            }
            if (check(TokenType.CLOUD)) {
                parse_node_declaration(DeploymentNodeType.CLOUD);
                return;
            }
            if (check(TokenType.DATABASE)) {
                parse_node_declaration(DeploymentNodeType.DATABASE);
                return;
            }
            if (check(TokenType.FOLDER)) {
                parse_node_declaration(DeploymentNodeType.FOLDER);
                return;
            }
            if (check(TokenType.FRAME)) {
                parse_node_declaration(DeploymentNodeType.FRAME);
                return;
            }
            if (check(TokenType.STORAGE)) {
                parse_node_declaration(DeploymentNodeType.STORAGE);
                return;
            }
            if (check(TokenType.ARTIFACT)) {
                parse_node_declaration(DeploymentNodeType.ARTIFACT);
                return;
            }
            if (check(TokenType.COMPONENT)) {
                parse_node_declaration(DeploymentNodeType.COMPONENT);
                return;
            }
            if (check(TokenType.CARD)) {
                parse_node_declaration(DeploymentNodeType.CARD);
                return;
            }
            if (check(TokenType.AGENT)) {
                parse_node_declaration(DeploymentNodeType.AGENT);
                return;
            }
            if (check(TokenType.RECTANGLE)) {
                parse_node_declaration(DeploymentNodeType.RECTANGLE);
                return;
            }
            if (check(TokenType.QUEUE)) {
                parse_node_declaration(DeploymentNodeType.QUEUE);
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

            // Skinparam
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Connection or element reference
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || check(TokenType.LBRACKET)) {
                parse_connection_or_element();
                return;
            }

            advance();
        }

        private bool try_parse_direction() throws Error {
            if (!check(TokenType.LEFT)) return false;
            advance();

            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "to") {
                current--;
                return false;
            }
            advance();

            if (!check(TokenType.RIGHT)) {
                current -= 2;
                return false;
            }
            advance();

            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "direction") {
                current -= 3;
                return false;
            }
            advance();

            diagram.left_to_right = true;
            return true;
        }

        private void parse_node_declaration(DeploymentNodeType type) throws Error {
            int line = advance().line;  // consume keyword

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected node name");
            }

            var node = diagram.get_or_create_node(name, type, line);
            node.node_type = type;

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    node.alias = advance().lexeme;
                }
            }

            // Stereotype
            if (match(TokenType.STEREOTYPE)) {
                node.stereotype = previous().lexeme;
            }

            // Color
            if (match(TokenType.HASH)) {
                node.color = parse_color();
            }

            // Container body
            if (match(TokenType.LBRACE)) {
                node.is_container = true;
                parse_container_body(node);
            }

            expect_end_of_statement();
        }

        private void parse_container_body(DeploymentNode container) throws Error {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) break;

                // Nested nodes
                DeploymentNodeType? nested_type = null;
                if (check(TokenType.NODE_KW)) nested_type = DeploymentNodeType.NODE;
                else if (check(TokenType.CLOUD)) nested_type = DeploymentNodeType.CLOUD;
                else if (check(TokenType.DATABASE)) nested_type = DeploymentNodeType.DATABASE;
                else if (check(TokenType.FOLDER)) nested_type = DeploymentNodeType.FOLDER;
                else if (check(TokenType.FRAME)) nested_type = DeploymentNodeType.FRAME;
                else if (check(TokenType.STORAGE)) nested_type = DeploymentNodeType.STORAGE;
                else if (check(TokenType.ARTIFACT)) nested_type = DeploymentNodeType.ARTIFACT;
                else if (check(TokenType.COMPONENT)) nested_type = DeploymentNodeType.COMPONENT;
                else if (check(TokenType.CARD)) nested_type = DeploymentNodeType.CARD;
                else if (check(TokenType.AGENT)) nested_type = DeploymentNodeType.AGENT;
                else if (check(TokenType.RECTANGLE)) nested_type = DeploymentNodeType.RECTANGLE;
                else if (check(TokenType.QUEUE)) nested_type = DeploymentNodeType.QUEUE;

                if (nested_type != null) {
                    int line = advance().line;
                    string name = "";
                    if (check(TokenType.STRING)) {
                        name = advance().lexeme;
                    } else if (check(TokenType.IDENTIFIER)) {
                        name = advance().lexeme;
                    }

                    if (name.length > 0) {
                        var child = new DeploymentNode(name, nested_type, line);

                        if (match(TokenType.AS)) {
                            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                                child.alias = advance().lexeme;
                            }
                        }
                        if (match(TokenType.STEREOTYPE)) {
                            child.stereotype = previous().lexeme;
                        }
                        if (match(TokenType.HASH)) {
                            child.color = parse_color();
                        }

                        if (match(TokenType.LBRACE)) {
                            child.is_container = true;
                            parse_container_body(child);
                        }

                        container.children.add(child);
                    }
                }
                // Bracketed component shorthand [Name]
                else if (check(TokenType.LBRACKET)) {
                    advance();
                    var sb = new StringBuilder();
                    int comp_line = previous().line;
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        sb.append(advance().lexeme);
                        if (!check(TokenType.RBRACKET)) sb.append(" ");
                    }
                    match(TokenType.RBRACKET);
                    string comp_name = sb.str.strip();
                    if (comp_name.length > 0) {
                        var child = new DeploymentNode(comp_name, DeploymentNodeType.COMPONENT, comp_line);
                        container.children.add(child);
                    }
                }
                else {
                    advance();
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private void parse_connection_or_element() throws Error {
            string from_name;
            int from_line;

            // Handle [Component] shorthand
            if (check(TokenType.LBRACKET)) {
                advance();
                var sb = new StringBuilder();
                from_line = previous().line;
                while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    sb.append(advance().lexeme);
                    if (!check(TokenType.RBRACKET)) sb.append(" ");
                }
                match(TokenType.RBRACKET);
                from_name = sb.str.strip();
                diagram.get_or_create_node(from_name, DeploymentNodeType.COMPONENT, from_line);
            } else if (check(TokenType.STRING)) {
                var token = advance();
                from_name = token.lexeme;
                from_line = token.line;
            } else {
                var token = advance();
                from_name = token.lexeme;
                from_line = token.line;
            }

            // Check for connection arrow
            DeploymentConnectionType? conn_type = null;
            bool is_dashed = false;
            bool reverse = false;

            if (match(TokenType.ARROW_RIGHT)) {
                conn_type = DeploymentConnectionType.DIRECTED;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                conn_type = DeploymentConnectionType.DEPENDENCY;
                is_dashed = true;
            } else if (match(TokenType.ARROW_LEFT)) {
                conn_type = DeploymentConnectionType.DIRECTED;
                reverse = true;
            } else if (match(TokenType.ARROW_LEFT_DOTTED)) {
                conn_type = DeploymentConnectionType.DEPENDENCY;
                is_dashed = true;
                reverse = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                conn_type = DeploymentConnectionType.ASSOCIATION;
            } else if (match(TokenType.ARROW_BIDIRECTIONAL)) {
                conn_type = DeploymentConnectionType.BIDIRECTIONAL;
            }

            if (conn_type != null) {
                string to_name;
                int to_line;

                if (check(TokenType.LBRACKET)) {
                    advance();
                    var sb = new StringBuilder();
                    to_line = previous().line;
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        sb.append(advance().lexeme);
                        if (!check(TokenType.RBRACKET)) sb.append(" ");
                    }
                    match(TokenType.RBRACKET);
                    to_name = sb.str.strip();
                } else if (check(TokenType.STRING)) {
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

                diagram.get_or_create_node(from_name, DeploymentNodeType.NODE, from_line);
                diagram.get_or_create_node(to_name, DeploymentNodeType.NODE, to_line);

                DeploymentConnection conn;
                if (reverse) {
                    conn = new DeploymentConnection(to_name, from_name, conn_type);
                } else {
                    conn = new DeploymentConnection(from_name, to_name, conn_type);
                }
                conn.is_dashed = is_dashed;

                if (match(TokenType.COLON)) {
                    conn.label = consume_rest_of_line();
                }

                diagram.connections.add(conn);
            } else {
                diagram.get_or_create_node(from_name, DeploymentNodeType.NODE, from_line);
            }

            expect_end_of_statement();
        }

        private void parse_note() throws Error {
            int line = advance().line;

            string position = "right";
            if (match(TokenType.LEFT)) position = "left";
            else if (match(TokenType.RIGHT)) position = "right";
            else if (match(TokenType.TOP)) position = "top";
            else if (match(TokenType.BOTTOM)) position = "bottom";

            string? attached_to = null;
            if (match(TokenType.OF)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            var sb = new StringBuilder();
            if (match(TokenType.COLON)) {
                sb.append(consume_rest_of_line());
            } else {
                skip_newlines();
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

            var note = new DeploymentNote(sb.str.strip(), line);
            note.attached_to = attached_to;
            note.position = position;
            diagram.notes.add(note);
        }

        private string parse_color() {
            var sb = new StringBuilder();
            sb.append("#");
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                if (peek().token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }
            return sb.str;
        }

        private void parse_skinparam() throws Error {
            string name = "";
            if (check(TokenType.IDENTIFIER) || is_skinparam_element()) {
                name = advance().lexeme;
            } else {
                skip_to_end_of_line();
                return;
            }

            if (match(TokenType.LBRACE)) {
                parse_skinparam_block(name);
            } else {
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(name, value);
                }
            }
        }

        private bool is_skinparam_element() {
            switch (peek().token_type) {
                case TokenType.NODE_KW:
                case TokenType.CLOUD:
                case TokenType.DATABASE:
                case TokenType.FOLDER:
                case TokenType.FRAME:
                case TokenType.STORAGE:
                case TokenType.ARTIFACT:
                case TokenType.COMPONENT:
                case TokenType.NOTE:
                    return true;
                default:
                    return false;
            }
        }

        private void parse_skinparam_block(string element) throws Error {
            skip_newlines();
            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();
                if (check(TokenType.RBRACE)) break;
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
                    if (sb.len > 0) sb.append(" ");
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    if (sb.len > 0) sb.append(" ");
                    sb.append(t.lexeme);
                }
            }
            return sb.str.strip();
        }

        private void skip_to_end_of_line() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) advance();
        }

        private string consume_rest_of_line() {
            var sb = new StringBuilder();
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) sb.append(" ");
                sb.append(t.lexeme);
            }
            return sb.str.strip();
        }

        private void expect_end_of_statement() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) advance();
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == TokenType.NEWLINE) return;
                switch (peek().token_type) {
                    case TokenType.NODE_KW:
                    case TokenType.CLOUD:
                    case TokenType.DATABASE:
                    case TokenType.ARTIFACT:
                    case TokenType.COMPONENT:
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
            while (match(TokenType.NEWLINE) || match(TokenType.COMMENT)) {}
        }

        private bool match(TokenType type) {
            if (check(type)) { advance(); return true; }
            return false;
        }

        private bool check(TokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        private Token advance() {
            if (!is_at_end()) current++;
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
