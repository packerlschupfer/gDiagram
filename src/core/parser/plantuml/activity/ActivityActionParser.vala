namespace GDiagram {
    /**
     * Parser for action nodes in activity diagrams.
     * Handles colored actions, SDL shapes, stereotypes, and text formatting.
     */
    public class ActivityActionParser : Object {
        private TokenStream stream;
        private ActivityDiagram diagram;

        public ActivityActionParser(TokenStream stream, ActivityDiagram diagram) {
            this.stream = stream;
            this.diagram = diagram;
        }

        /**
         * Parse colored action: #color:action text; or #color1/color2:action text; (gradient)
         * Also: #color;line:border_color:action text;
         * Also: #color;text:font_color:action text;
         */
        public ActivityNode parse_colored_action(int source_line) {

            var color_sb = new StringBuilder();
            string? color = null;
            string? color2 = null;
            string? gradient_separator = null;
            string? line_color = null;
            string? text_color = null;

            // Collect tokens until we find the final colon before action
            // Handle line:color and text:color specifiers
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                if (check(TokenType.COLON)) {
                    // Check what comes before this colon
                    string current_str = color_sb.str.strip();

                    if (current_str.has_suffix("line")) {
                        // Consume colon and get line color
                        advance();
                        var val_sb = new StringBuilder();
                        while (!check(TokenType.COLON) && !check(TokenType.SEMICOLON) &&
                               !check(TokenType.NEWLINE) && !is_at_end()) {
                            val_sb.append(advance().lexeme);
                        }
                        line_color = val_sb.str.strip();
                        // Remove "line" from color_sb
                        string before = current_str.substring(0, current_str.length - 4).strip();
                        if (before.has_suffix(";")) {
                            before = before.substring(0, before.length - 1).strip();
                        }
                        color_sb = new StringBuilder();
                        color_sb.append(before);

                        // Skip semicolon if present
                        if (check(TokenType.SEMICOLON)) {
                            advance();
                        }
                    } else if (current_str.has_suffix("text")) {
                        // Consume colon and get text color
                        advance();
                        var val_sb = new StringBuilder();
                        while (!check(TokenType.COLON) && !check(TokenType.SEMICOLON) &&
                               !check(TokenType.NEWLINE) && !is_at_end()) {
                            val_sb.append(advance().lexeme);
                        }
                        text_color = val_sb.str.strip();
                        // Remove "text" from color_sb
                        string before = current_str.substring(0, current_str.length - 4).strip();
                        if (before.has_suffix(";")) {
                            before = before.substring(0, before.length - 1).strip();
                        }
                        color_sb = new StringBuilder();
                        color_sb.append(before);

                        // Skip semicolon if present
                        if (check(TokenType.SEMICOLON)) {
                            advance();
                        }
                    } else {
                        // This is the colon before action text
                        break;
                    }
                } else {
                    color_sb.append(advance().lexeme);
                }
            }

            string color_str = color_sb.str.strip();
            // The HASH fallback leaves the "#" behind; the colour token keeps it
            if (color_str.length > 0 && !color_str.has_prefix("#")) {
                color_str = "#" + color_str;
            }

            // Parse background color (may be a gradient: "red|green", "red-green",
            // "red/green", "red\green" - the separator gives the direction)
            if (color_str.length > 0) {
                int sep_idx = -1;
                for (int i = 1; i < color_str.length - 1; i++) {
                    char ch = color_str[i];
                    if (ch == '|' || ch == '-' || ch == '/' || ch == '\\') {
                        sep_idx = i;
                        break;
                    }
                }

                if (sep_idx > 0 && sep_idx < color_str.length - 1) {
                    color = color_str.substring(0, sep_idx).strip();
                    color2 = color_str.substring(sep_idx + 1).strip();
                    gradient_separator = color_str.substring(sep_idx, 1);
                } else {
                    color = color_str;
                }
            }

            // Expect colon before action text
            ActivityNode? node = null;
            if (match(TokenType.COLON)) {
                node = parse_action(color, color2, line_color, text_color, source_line);
                node.gradient_separator = gradient_separator;
            }

            return node;
        }

        /**
         * Parse action node with optional colors and styling.
         */
        public ActivityNode parse_action(string? color, string? color2,
                                         string? line_color, string? text_color, int source_line) {

            // Collect text until semicolon (can span multiple lines)
            var sb = new StringBuilder();
            Token? prev = null;

            while (!check(TokenType.SEMICOLON) && !is_at_end()) {
                Token t = advance();
                if (t.token_type == TokenType.NEWLINE) {
                    // Preserve newlines in multi-line actions
                    sb.append("\n");
                } else {
                    // Spaces only where the source has them. Guessing from the
                    // punctuation turned ">=" into "> =" and "°C" into "° C", and
                    // needed special cases for Creole markers, URLs and escapes.
                    // A "|" is literal text, as in PlantUML (it was a line break).
                    if (sb.len > 0 && !sb.str.has_suffix("\n") && t.space_before) {
                        sb.append(string.nfill(space_count(prev, t), ' '));
                    }
                    sb.append(t.lexeme);
                }
                prev = t;
            }

            match(TokenType.SEMICOLON);

            string text = sb.str.strip();
            string? stereotype = null;
            string? suffix_color = null;
            ActionShape shape = ActionShape.DEFAULT;

            // Check for stereotype AFTER semicolon: :action; <<stereotype>>
            if (!is_at_end() && peek().lexeme == "<" && check_next_lexeme("<")) {
                advance();  // consume first <
                advance();  // consume second <
                var st_sb = new StringBuilder();
                while (!is_at_end() && !(peek().lexeme == ">" && check_next_lexeme(">"))) {
                    st_sb.append(advance().lexeme);
                }
                if (!is_at_end() && peek().lexeme == ">") {
                    advance();  // consume first >
                    if (!is_at_end() && peek().lexeme == ">") {
                        advance();  // consume second >
                    }
                }
                stereotype = st_sb.str.strip();
            } else if (!is_at_end() && check(TokenType.STEREOTYPE)) {
                // The lexer reads "<<name>>" as one token
                stereotype = advance().lexeme.strip();
            }
            if (stereotype != null) {
                // ":error; <<#pink>>" colours the action (PlantUML 1.2026.8)
                if (stereotype.has_prefix("#") && stereotype.length > 1 && !stereotype.contains(" ")) {
                    suffix_color = stereotype;
                    stereotype = null;
                }

                // Check for SDL stereotypes and set shape
                shape = get_sdl_shape_from_stereotype(stereotype);
                if (shape != ActionShape.DEFAULT) {
                    stereotype = null;  // SDL shapes don't show stereotype text
                }
            }

            // Also check for stereotype at START of text: <<text>> action
            if (stereotype == null && (text.has_prefix("< <") || text.has_prefix("<<"))) {
                int start_idx = text.has_prefix("<<") ? 2 : 3;
                int end_idx = text.index_of("> >");
                if (end_idx == -1) {
                    end_idx = text.index_of(">>");
                }
                if (end_idx > start_idx) {
                    stereotype = text.substring(start_idx, end_idx - start_idx).strip();
                    // Remove stereotype from text
                    int text_start = end_idx + (text.substring(end_idx).has_prefix(">>") ? 2 : 3);
                    text = text.substring(text_start).strip();

                    // Check for SDL stereotypes and set shape
                    shape = get_sdl_shape_from_stereotype(stereotype);
                    if (shape != ActionShape.DEFAULT) {
                        stereotype = null;  // SDL shapes don't show stereotype text
                    }
                }
            }

            // Check for SDL shapes: |text|, <text>, >text>, /text/, ]text]
            if (text.has_prefix("|") && text.has_suffix("|") && text.length > 2) {
                shape = ActionShape.SDL_TASK;
                text = text.substring(1, text.length - 2).strip();
            } else if (text.has_prefix("<") && text.has_suffix(">") && text.length > 2) {
                shape = ActionShape.SDL_INPUT;
                text = text.substring(1, text.length - 2).strip();
            } else if (text.has_prefix(">") && text.has_suffix(">") && text.length > 2) {
                shape = ActionShape.SDL_OUTPUT;
                text = text.substring(1, text.length - 2).strip();
            } else if (text.has_prefix("/") && text.has_suffix("/") && text.length > 2
                       && !text.has_prefix("//")) {
                // SDL_SAVE: /text/ but NOT //text// (which is Creole italic)
                shape = ActionShape.SDL_SAVE;
                text = text.substring(1, text.length - 2).strip();
            } else if (text.has_prefix("]") && text.has_suffix("]") && text.length > 2) {
                shape = ActionShape.SDL_PROCEDURE;
                text = text.substring(1, text.length - 2).strip();
            }

            // Check for URL: [[url text]] or [[url]]
            string? url = null;
            if (text.contains("[[") && text.contains("]]")) {
                int url_start = text.index_of("[[");
                int url_end = text.index_of("]]");
                if (url_end > url_start + 2) {
                    string url_content = text.substring(url_start + 2, url_end - url_start - 2).strip();
                    // Check for "url text" format (space separates url from display text)
                    int space_idx = url_content.index_of(" ");
                    string display_text;
                    if (space_idx > 0) {
                        url = url_content.substring(0, space_idx).strip();
                        display_text = url_content.substring(space_idx + 1).strip();
                    } else {
                        url = url_content;
                        display_text = url_content;
                    }
                    // Replace [[...]] with display text
                    text = text.substring(0, url_start) + display_text + text.substring(url_end + 2);
                    text = text.strip();
                }
            }

            var node = new ActivityNode(ActivityNodeType.ACTION, text, source_line);
            node.color = color ?? suffix_color;
            node.color2 = color2;
            node.line_color = line_color;
            node.text_color = text_color;
            node.stereotype = stereotype;
            node.url = url;
            node.shape = shape;

            return node;
        }

        // Spaces between two tokens on one line, as written: PlantUML keeps repeated
        // spaces in an action ("only   this"). Measured from the columns; a string
        // token's lexeme lacks its two quotes. One space when that can't be measured.
        private static int space_count(Token? prev, Token t) {
            if (prev == null || prev.line != t.line || prev.token_type == TokenType.NEWLINE) {
                return 1;
            }
            int prev_len = prev.lexeme.char_count();
            if (prev.token_type == TokenType.STRING) {
                prev_len += 2;
            }
            int gap = t.column - (prev.column + prev_len);
            return (gap >= 1 && gap <= 64) ? gap : 1;
        }

        /**
         * Get SDL shape from stereotype string.
         */
        private ActionShape get_sdl_shape_from_stereotype(string? stereotype) {
            if (stereotype == null) return ActionShape.DEFAULT;

            string st_lower = stereotype.down();
            if (st_lower == "input") {
                return ActionShape.SDL_INPUT;
            } else if (st_lower == "output") {
                return ActionShape.SDL_OUTPUT;
            } else if (st_lower == "procedure" || st_lower == "subprocess") {
                return ActionShape.SDL_PROCEDURE;
            } else if (st_lower == "save") {
                return ActionShape.SDL_SAVE;
            } else if (st_lower == "load") {
                return ActionShape.SDL_LOAD;
            } else if (st_lower == "task") {
                return ActionShape.SDL_TASK;
            }

            return ActionShape.DEFAULT;
        }

        // Token navigation helpers
        private bool match(TokenType type) {
            return stream.match(type);
        }

        private bool check(TokenType type) {
            return stream.check(type);
        }

        private bool check_next_lexeme(string lexeme) {
            return stream.check_next_lexeme(lexeme);
        }

        private Token advance() {
            return stream.advance();
        }

        private bool is_at_end() {
            return stream.is_at_end();
        }

        private Token peek() {
            return stream.peek();
        }

    }
}
