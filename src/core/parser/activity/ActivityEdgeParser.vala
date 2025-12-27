namespace GDiagram {
    /**
     * Parser for arrow/edge styling and labels in activity diagrams.
     * Handles styled arrows, edge colors, directions, and labels.
     */
    public class ActivityEdgeParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ActivityDiagram diagram;

        // Edge state - modified by parsing methods
        public string? pending_edge_label { get; set; default = null; }
        public string? pending_edge_color { get; set; default = null; }
        public string? pending_edge_style { get; set; default = null; }
        public EdgeDirection pending_edge_direction { get; set; default = EdgeDirection.DEFAULT; }
        public string? pending_edge_note { get; set; default = null; }

        public ActivityEdgeParser(Gee.ArrayList<Token> tokens, ref int current, ActivityDiagram diagram) {
            this.tokens = tokens;
            this.current = current;
            this.diagram = diagram;
        }

        /**
         * Parse arrow label: -> label; or --> label;
         */
        public void parse_arrow_label(ref int position) throws Error {
            current = position;

            // Collect label until semicolon or newline
            var sb = new StringBuilder();

            while (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            match(TokenType.SEMICOLON);

            string label = sb.str.strip();
            if (label.length > 0) {
                pending_edge_label = label;
            }

            position = current;
        }

        /**
         * Parse styled arrow: -[#color]-> or -[dashed]-> or -[#color,dashed]-> or -up-> or -down->
         */
        public void parse_styled_arrow(ref int position) throws Error {
            current = position;

            advance();  // consume -

            string? color = null;
            string? style = null;
            EdgeDirection direction = EdgeDirection.DEFAULT;

            // Check if this is a direction arrow (-up->, -down->, etc.) or styled arrow (-[...]->)
            if (check(TokenType.LBRACKET)) {
                advance();  // consume [

                // Parse style content until ]
                var style_parts = new Gee.ArrayList<string>();
                var current_part = new StringBuilder();

                while (!check(TokenType.RBRACKET) && !is_at_end()) {
                    Token t = advance();
                    if (t.lexeme == ",") {
                        if (current_part.len > 0) {
                            style_parts.add(current_part.str.strip());
                            current_part = new StringBuilder();
                        }
                    } else {
                        current_part.append(t.lexeme);
                    }
                }
                if (current_part.len > 0) {
                    style_parts.add(current_part.str.strip());
                }

                match(TokenType.RBRACKET);

                // Process style parts - collect ALL colors for multi-line arrows
                var colors = new Gee.ArrayList<string>();
                foreach (var part in style_parts) {
                    // Handle semicolon-separated values (e.g., #red;#green;#orange;#blue)
                    // PlantUML renders these as multiple parallel arrows
                    string[] subparts = part.split(";");
                    foreach (var subpart in subparts) {
                        string trimmed = subpart.strip();
                        if (trimmed.length == 0) continue;

                        string lower = trimmed.down();
                        if (trimmed.has_prefix("#")) {
                            // Convert #colorname to colorname, keep #RRGGBB as is
                            string color_part = trimmed.substring(1);
                            string color_lower = color_part.down();
                            // Check if it's actually a style keyword with # prefix (user error)
                            if (color_lower == "dashed" || color_lower == "dotted" ||
                                color_lower == "bold" || color_lower == "hidden") {
                                if (style == null) {
                                    style = color_lower;
                                }
                            } else {
                                // Collect all colors for multi-arrow support
                                if (color_part.length == 6 && ActivityParserUtils.is_hex_color(color_part)) {
                                    colors.add(trimmed);  // Keep #RRGGBB
                                } else {
                                    colors.add(color_part);  // Use colorname without #
                                }
                            }
                        } else if (lower == "up" || lower == "u") {
                            direction = EdgeDirection.UP;
                        } else if (lower == "down" || lower == "d") {
                            direction = EdgeDirection.DOWN;
                        } else if (lower == "left" || lower == "l") {
                            direction = EdgeDirection.LEFT;
                        } else if (lower == "right" || lower == "r") {
                            direction = EdgeDirection.RIGHT;
                        } else if (lower == "dashed" || lower == "dotted" || lower == "bold" || lower == "hidden") {
                            if (style == null) {  // Take first style only
                                style = lower;
                            }
                        } else {
                            // Treat as color - Graphviz supports many color names
                            colors.add(lower);
                        }
                    }
                }
                // Join colors with semicolon for multi-arrow rendering
                if (colors.size > 0) {
                    color = string.joinv(";", colors.to_array());
                }
            } else {
                // Direction arrow: -up->, -down->, -left->, -right->
                if (check(TokenType.IDENTIFIER)) {
                    string dir = peek().lexeme.down();
                    if (dir == "up" || dir == "u") {
                        direction = EdgeDirection.UP;
                        advance();
                    } else if (dir == "down" || dir == "d") {
                        direction = EdgeDirection.DOWN;
                        advance();
                    } else if (dir == "left" || dir == "l") {
                        direction = EdgeDirection.LEFT;
                        advance();
                    } else if (dir == "right" || dir == "r") {
                        direction = EdgeDirection.RIGHT;
                        advance();
                    }
                }
            }

            // Parse the rest of the arrow (-> or -->)
            while (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) &&
                   !check(TokenType.COLON) && !is_at_end()) {
                Token t = peek();
                // Stop when we hit something that's not part of the arrow
                if (t.token_type == TokenType.IDENTIFIER && t.lexeme != ">") {
                    break;
                }
                advance();
            }

            pending_edge_color = color;
            pending_edge_style = style;
            pending_edge_direction = direction;

            // Check for optional label after arrow
            if (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                var sb = new StringBuilder();
                while (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
                string label = sb.str.strip();
                if (label.length > 0) {
                    pending_edge_label = label;
                }
            }

            match(TokenType.SEMICOLON);

            position = current;
        }

        /**
         * Reset all pending edge attributes.
         */
        public void reset_pending_edge_attributes() {
            pending_edge_label = null;
            pending_edge_color = null;
            pending_edge_style = null;
            pending_edge_direction = EdgeDirection.DEFAULT;
            pending_edge_note = null;
        }

        // Token navigation helpers
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
