namespace GDiagram {
    /**
     * Parser for action nodes in activity diagrams.
     * Handles colored actions, SDL shapes, stereotypes, and text formatting.
     */
    public class ActivityActionParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ActivityDiagram diagram;
        private ActivityNode? last_node;

        public ActivityActionParser(Gee.ArrayList<Token> tokens, ref int current, ActivityDiagram diagram) {
            this.tokens = tokens;
            this.current = current;
            this.diagram = diagram;
        }

        /**
         * Parse colored action: #color:action text; or #color1/color2:action text; (gradient)
         * Also: #color;line:border_color:action text;
         * Also: #color;text:font_color:action text;
         */
        public ActivityNode parse_colored_action(ref int position, int source_line) throws Error {
            current = position;

            var color_sb = new StringBuilder();
            string? color = null;
            string? color2 = null;
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

            // Parse background color (may be gradient)
            if (color_str.length > 0) {
                int sep_idx = color_str.index_of("/");
                if (sep_idx == -1) {
                    sep_idx = color_str.index_of("\\");
                }

                if (sep_idx > 0 && sep_idx < color_str.length - 1) {
                    color = color_str.substring(0, sep_idx).strip();
                    color2 = color_str.substring(sep_idx + 1).strip();
                } else {
                    color = color_str;
                }
            }

            // Expect colon before action text
            ActivityNode? node = null;
            if (match(TokenType.COLON)) {
                node = parse_action(ref current, color, color2, line_color, text_color, source_line);
            }

            position = current;
            return node;
        }

        /**
         * Parse action node with optional colors and styling.
         */
        public ActivityNode parse_action(ref int position, string? color, string? color2,
                                         string? line_color, string? text_color, int source_line) throws Error {
            current = position;

            // Collect text until semicolon (can span multiple lines)
            // Pipe character | is used as line separator: :line1|line2|line3;
            var sb = new StringBuilder();
            int url_bracket_depth = 0;  // Track if we're inside [[...]]

            while (!check(TokenType.SEMICOLON) && !is_at_end()) {
                Token t = advance();
                if (t.token_type == TokenType.NEWLINE) {
                    // Preserve newlines in multi-line actions
                    sb.append("\n");
                } else if (t.token_type == TokenType.PIPE) {
                    // Pipe is line separator in actions: :line1|line2;
                    sb.append("\n");
                } else {
                    // Track URL bracket depth: [[ opens, ]] closes
                    if (t.lexeme == "[" && sb.str.has_suffix("[")) {
                        url_bracket_depth++;
                    } else if (t.lexeme == "]" && sb.str.has_suffix("]") && url_bracket_depth > 0) {
                        url_bracket_depth--;
                    }

                    // Check if this is an escape sequence (like \n, \t)
                    bool is_escape_seq = t.lexeme.has_prefix("\\") && t.lexeme.length == 2;
                    // Check if previous content ends with escape sequence start
                    bool prev_ends_with_escape = sb.str.has_suffix("\\");

                    // Check for Creole formatting markers - don't add spaces around them
                    bool is_creole_marker = t.lexeme == "*" || t.lexeme == "/" ||
                                            t.lexeme == "_" || t.lexeme == "-" || t.lexeme == "~";
                    bool prev_ends_with_creole = sb.str.has_suffix("*") || sb.str.has_suffix("/") ||
                                                  sb.str.has_suffix("_") || sb.str.has_suffix("-") ||
                                                  sb.str.has_suffix("~");

                    // Check for URL brackets - only skip space when forming [[ or ]]
                    bool is_double_open = t.lexeme == "[" && sb.str.has_suffix("[");
                    bool is_double_close = t.lexeme == "]" && sb.str.has_suffix("]");

                    // Inside URL brackets, don't add spaces around URL-forming characters
                    bool is_url_char = t.lexeme == ":" || t.lexeme == "/" || t.lexeme == "." ||
                                       t.lexeme == "-" || t.lexeme == "_" || t.lexeme == "?" ||
                                       t.lexeme == "=" || t.lexeme == "&" || t.lexeme == "#";
                    bool prev_ends_with_url_char = sb.str.has_suffix(":") || sb.str.has_suffix("/") ||
                                                    sb.str.has_suffix(".") || sb.str.has_suffix("-") ||
                                                    sb.str.has_suffix("?") || sb.str.has_suffix("=") ||
                                                    sb.str.has_suffix("&") || sb.str.has_suffix("#") ||
                                                    sb.str.has_suffix("[");

                    // Determine if we should skip adding a space
                    bool skip_space = is_escape_seq || prev_ends_with_escape
                                      || is_creole_marker || prev_ends_with_creole
                                      || is_double_open || is_double_close;

                    // Inside URL brackets, also skip spaces around URL characters and before ]
                    if (url_bracket_depth > 0 && (is_url_char || prev_ends_with_url_char || t.lexeme == "]")) {
                        skip_space = true;
                    }

                    // Skip spaces around UTF-8 continuation bytes (lexer may tokenize them separately)
                    // UTF-8 lead bytes are >= 0xC0, continuation bytes are 0x80-0xBF
                    bool is_utf8_byte = false;
                    if (t.lexeme.length == 1) {
                        uint8 b = (uint8)t.lexeme[0];
                        is_utf8_byte = b >= 0x80;  // Any high byte
                    }
                    bool prev_ends_with_utf8 = false;
                    if (sb.len > 0) {
                        uint8 last_b = (uint8)sb.str[sb.len - 1];
                        prev_ends_with_utf8 = last_b >= 0x80;
                    }
                    if (is_utf8_byte || prev_ends_with_utf8) {
                        skip_space = true;
                    }

                    if (sb.len > 0 && !sb.str.has_suffix("\n") && t.token_type != TokenType.COLON
                        && !skip_space) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            match(TokenType.SEMICOLON);

            string text = sb.str.strip();
            string? stereotype = null;
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
            node.color = color;
            node.color2 = color2;
            node.line_color = line_color;
            node.text_color = text_color;
            node.stereotype = stereotype;
            node.url = url;
            node.shape = shape;

            position = current;
            return node;
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

        private bool check_next_lexeme(string lexeme) {
            if (current + 1 >= tokens.size) return false;
            return tokens.get(current + 1).lexeme == lexeme;
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
