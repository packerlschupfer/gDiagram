namespace GDiagram {
    public class MindMapDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private MindMapDiagram diagram;
        private Gee.ArrayList<MindMapNode> level_stack;
        private MindMapSide current_side;

        public MindMapDiagramParser() {
            this.current = 0;
            this.level_stack = new Gee.ArrayList<MindMapNode>();
            this.current_side = MindMapSide.RIGHT;
        }

        public MindMapDiagram parse(Gee.ArrayList<Token> tokens, DiagramType type = DiagramType.MINDMAP) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new MindMapDiagram(type);
            this.level_stack.clear();
            this.current_side = MindMapSide.RIGHT;

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, peek().line, peek().column));
            }

            return diagram;
        }

        private void parse_diagram() throws Error {
            // Skip @startmindmap / @startwbs if present
            if (check(TokenType.STARTMINDMAP)) {
                advance();
                skip_newlines();
            } else if (check(TokenType.STARTWBS)) {
                advance();
                skip_newlines();
            } else if (check(TokenType.STARTUML)) {
                advance();
                skip_newlines();
            }

            while (!is_at_end() && !check(TokenType.ENDMINDMAP) &&
                   !check(TokenType.ENDWBS) && !check(TokenType.ENDUML)) {
                skip_newlines();

                if (is_at_end() || check(TokenType.ENDMINDMAP) ||
                    check(TokenType.ENDWBS) || check(TokenType.ENDUML)) {
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

            // Skinparam
            if (check(TokenType.SKINPARAM)) {
                parse_skinparam();
                return true;
            }

            // Left side directive
            if (check_identifier("left") && check_identifier_at(1, "side")) {
                advance(); advance();
                current_side = MindMapSide.LEFT;
                return true;
            }

            // Right side directive
            if (check_identifier("right") && check_identifier_at(1, "side")) {
                advance(); advance();
                current_side = MindMapSide.RIGHT;
                return true;
            }

            // Node lines (start with * or + or -)
            if (check(TokenType.MULT) || check(TokenType.PLUS) || check(TokenType.MINUS)) {
                return parse_node_line();
            }

            return false;
        }

        private bool parse_node_line() throws Error {
            int line = peek().line;

            // Count level markers (* or + or -)
            int level = 0;
            TokenType marker = peek().token_type;

            while (check(marker)) {
                level++;
                advance();
            }

            skip_whitespace_tokens();

            // Parse node content
            string text = "";
            MindMapNodeStyle style = MindMapNodeStyle.DEFAULT;
            string? color = null;

            // Check for style markers
            if (check(TokenType.LBRACKET)) {
                // [text] - box style
                advance();
                text = read_until_token(TokenType.RBRACKET);
                if (check(TokenType.RBRACKET)) advance();
                style = MindMapNodeStyle.BOX;
            } else if (check(TokenType.LPAREN)) {
                advance();
                if (check(TokenType.LPAREN)) {
                    // ((text)) - pill style
                    advance();
                    text = read_until_double_paren();
                    style = MindMapNodeStyle.PILL;
                } else {
                    // (text) - rounded style
                    text = read_until_token(TokenType.RPAREN);
                    if (check(TokenType.RPAREN)) advance();
                    style = MindMapNodeStyle.ROUNDED;
                }
            } else if (check(TokenType.LBRACE)) {
                // Check for {{text}} - cloud style
                advance();
                if (check(TokenType.LBRACE)) {
                    advance();
                    text = read_until_double_brace();
                    style = MindMapNodeStyle.CLOUD;
                } else {
                    // Single brace - read as text
                    text = "{" + read_until_newline();
                }
            } else {
                // Plain text
                text = read_until_newline();
            }

            text = text.strip();
            if (text.length == 0) {
                return false;
            }

            // Check for color at end
            if (text.contains("#")) {
                int hash_pos = text.last_index_of("#");
                string potential_color = text.substring(hash_pos);
                if (potential_color.length > 1 && potential_color.length <= 8) {
                    color = potential_color;
                    text = text.substring(0, hash_pos).strip();
                }
            }

            // Create node
            var node = new MindMapNode(text, level, line);
            node.style = style;
            node.color = color;
            node.side = current_side;

            // Add to tree
            if (level == 1) {
                // Root node
                if (diagram.root == null) {
                    diagram.root = node;
                    level_stack.clear();
                    level_stack.add(node);
                } else {
                    // Multiple root level nodes - add to root as children
                    diagram.root.add_child(node);
                    level_stack.clear();
                    level_stack.add(diagram.root);
                    level_stack.add(node);
                }
            } else {
                // Find parent at appropriate level
                while (level_stack.size >= level) {
                    level_stack.remove_at(level_stack.size - 1);
                }

                if (level_stack.size > 0) {
                    var parent = level_stack.get(level_stack.size - 1);
                    parent.add_child(node);
                } else if (diagram.root != null) {
                    diagram.root.add_child(node);
                }

                level_stack.add(node);
            }

            return true;
        }

        private string read_until_token(TokenType type) {
            var sb = new StringBuilder();
            while (!check(type) && !check(TokenType.NEWLINE) && !is_at_end()) {
                if (sb.len > 0) sb.append(" ");
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        private string read_until_double_paren() {
            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                if (check(TokenType.RPAREN)) {
                    advance();
                    if (check(TokenType.RPAREN)) {
                        advance();
                        break;
                    } else {
                        sb.append(")");
                    }
                } else {
                    if (sb.len > 0) sb.append(" ");
                    sb.append(advance().lexeme);
                }
            }
            return sb.str;
        }

        private string read_until_double_brace() {
            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                if (check(TokenType.RBRACE)) {
                    advance();
                    if (check(TokenType.RBRACE)) {
                        advance();
                        break;
                    } else {
                        sb.append("}");
                    }
                } else {
                    if (sb.len > 0) sb.append(" ");
                    sb.append(advance().lexeme);
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
            return sb.str;
        }

        private void parse_title() throws Error {
            advance(); // consume 'title'
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) sb.append(" ");
                sb.append(t.lexeme);
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

                if (check(TokenType.IDENTIFIER)) {
                    string element = advance().lexeme;
                    skip_whitespace_tokens();

                    if (check(TokenType.IDENTIFIER)) {
                        string property = advance().lexeme;
                        skip_whitespace_tokens();

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

            if (check(TokenType.IDENTIFIER)) {
                string second = peek().lexeme;

                if (second == "BackgroundColor" || second == "BorderColor" ||
                    second == "FontColor" || second == "FontSize") {
                    advance();
                    skip_whitespace_tokens();
                    string value = read_until_newline();
                    diagram.skin_params.set_element_property(element.down(), second, value);
                } else {
                    string value = read_until_newline();
                    diagram.skin_params.set_property(element, value);
                }
            }
        }

        private bool check_identifier(string name) {
            return check(TokenType.IDENTIFIER) && peek().lexeme.down() == name;
        }

        private bool check_identifier_at(int offset, string name) {
            if (current + offset >= tokens.size) return false;
            Token t = tokens.get(current + offset);
            return t.token_type == TokenType.IDENTIFIER && t.lexeme.down() == name;
        }

        private void skip_newlines() {
            while (check(TokenType.NEWLINE) || check(TokenType.COMMENT)) {
                advance();
            }
        }

        private void skip_whitespace_tokens() {
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
