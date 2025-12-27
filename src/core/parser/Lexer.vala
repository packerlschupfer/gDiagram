namespace GDiagram {
    public class Lexer : Object {
        private string source;
        private int current;       // Byte position in source
        private int start;         // Byte position of current token start
        private int line;
        private int column;
        private int line_start;    // Byte position of current line start

        private static HashTable<string, TokenType>? keywords = null;

        public Lexer(string source) {
            this.source = source;
            this.current = 0;
            this.start = 0;
            this.line = 1;
            this.column = 1;
            this.line_start = 0;

            init_keywords();
        }

        private static void init_keywords() {
            if (keywords != null) return;

            keywords = new HashTable<string, TokenType>(str_hash, str_equal);
            keywords.insert("participant", TokenType.PARTICIPANT);
            keywords.insert("actor", TokenType.ACTOR);
            keywords.insert("boundary", TokenType.BOUNDARY);
            keywords.insert("control", TokenType.CONTROL);
            keywords.insert("entity", TokenType.ENTITY);
            keywords.insert("database", TokenType.DATABASE);
            keywords.insert("collections", TokenType.COLLECTIONS);
            keywords.insert("queue", TokenType.QUEUE);
            keywords.insert("as", TokenType.AS);
            keywords.insert("note", TokenType.NOTE);
            keywords.insert("end", TokenType.END);
            keywords.insert("left", TokenType.LEFT);
            keywords.insert("right", TokenType.RIGHT);
            keywords.insert("top", TokenType.TOP);
            keywords.insert("bottom", TokenType.BOTTOM);
            keywords.insert("over", TokenType.OVER);
            keywords.insert("of", TokenType.OF);
            keywords.insert("activate", TokenType.ACTIVATE);
            keywords.insert("deactivate", TokenType.DEACTIVATE);
            keywords.insert("destroy", TokenType.DESTROY);
            keywords.insert("return", TokenType.RETURN);

            // Class diagram keywords
            keywords.insert("class", TokenType.CLASS);
            keywords.insert("interface", TokenType.INTERFACE);
            keywords.insert("abstract", TokenType.ABSTRACT);
            keywords.insert("enum", TokenType.ENUM);
            keywords.insert("extends", TokenType.EXTENDS);
            keywords.insert("implements", TokenType.IMPLEMENTS);

            // Object diagram keywords
            keywords.insert("object", TokenType.OBJECT);

            // Activity diagram keywords
            keywords.insert("start", TokenType.START);
            keywords.insert("stop", TokenType.STOP);
            keywords.insert("kill", TokenType.KILL);
            keywords.insert("detach", TokenType.DETACH);
            keywords.insert("if", TokenType.IF);
            keywords.insert("then", TokenType.THEN);
            keywords.insert("else", TokenType.ELSE);
            keywords.insert("elseif", TokenType.ELSEIF);
            keywords.insert("endif", TokenType.ENDIF);
            keywords.insert("fork", TokenType.FORK);
            keywords.insert("merge", TokenType.MERGE);
            keywords.insert("while", TokenType.WHILE);
            keywords.insert("endwhile", TokenType.ENDWHILE);
            keywords.insert("repeat", TokenType.REPEAT);
            keywords.insert("partition", TokenType.PARTITION);
            keywords.insert("switch", TokenType.SWITCH);
            keywords.insert("case", TokenType.CASE);
            keywords.insert("endswitch", TokenType.ENDSWITCH);
            keywords.insert("group", TokenType.GROUP);
            keywords.insert("split", TokenType.SPLIT);
            keywords.insert("backward", TokenType.BACKWARD);
            keywords.insert("break", TokenType.BREAK);
            keywords.insert("floating", TokenType.FLOATING);
            keywords.insert("title", TokenType.TITLE);
            keywords.insert("header", TokenType.HEADER);
            keywords.insert("footer", TokenType.FOOTER);
            keywords.insert("caption", TokenType.CAPTION);
            keywords.insert("skinparam", TokenType.SKINPARAM);
            keywords.insert("scale", TokenType.SCALE);
            keywords.insert("hide", TokenType.HIDE);
            keywords.insert("show", TokenType.SHOW);
            keywords.insert("legend", TokenType.LEGEND);
            keywords.insert("center", TokenType.CENTER);

            // Use Case diagram keywords
            keywords.insert("usecase", TokenType.USECASE);
            keywords.insert("package", TokenType.PACKAGE);
            keywords.insert("rectangle", TokenType.RECTANGLE);

            // State diagram keywords
            keywords.insert("state", TokenType.STATE);

            // Component diagram keywords
            keywords.insert("component", TokenType.COMPONENT);
            keywords.insert("cloud", TokenType.CLOUD);
            keywords.insert("folder", TokenType.FOLDER);
            keywords.insert("frame", TokenType.FRAME);
            keywords.insert("node", TokenType.NODE_KW);
            keywords.insert("artifact", TokenType.ARTIFACT);
            keywords.insert("storage", TokenType.STORAGE);
            keywords.insert("portin", TokenType.PORTIN);
            keywords.insert("portout", TokenType.PORTOUT);
            keywords.insert("port", TokenType.PORT);
            keywords.insert("card", TokenType.CARD);
            keywords.insert("agent", TokenType.AGENT);

            // Sequence diagram grouping frame keywords
            keywords.insert("alt", TokenType.ALT);
            keywords.insert("opt", TokenType.OPT);
            keywords.insert("loop", TokenType.LOOP);
            keywords.insert("par", TokenType.PAR);
            keywords.insert("critical", TokenType.CRITICAL);
            keywords.insert("ref", TokenType.REF);
        }

        public Gee.ArrayList<Token> scan_all() {
            var tokens = new Gee.ArrayList<Token>();

            while (!is_at_end()) {
                var token = scan_token();
                if (token != null) {
                    tokens.add(token);
                }
            }

            tokens.add(new Token(TokenType.EOF, "", line, column));
            return tokens;
        }

        public Token? scan_token() {
            skip_whitespace();

            if (is_at_end()) {
                return null;
            }

            start = current;
            int start_column = column;

            unichar c = advance();

            // Comments
            if (c == '\'') {
                return scan_line_comment(start_column);
            }
            if (c == '/' && peek() == '\'') {
                return scan_block_comment(start_column);
            }

            // Newline
            if (c == '\n') {
                return new Token(TokenType.NEWLINE, "\\n", line - 1, start_column);
            }

            // Directives
            if (c == '@') {
                return scan_directive(start_column);
            }

            // Preprocessor directives (!pragma, !define, !include, etc.) - skip line
            if (c == '!') {
                while (peek() != '\n' && !is_at_end()) {
                    advance();
                }
                string text = source.substring(start, current - start);
                return new Token(TokenType.COMMENT, text, line, start_column);
            }

            // Strings
            if (c == '"') {
                return scan_string(start_column);
            }

            // Colon
            if (c == ':') {
                return new Token(TokenType.COLON, ":", line, start_column);
            }

            // Braces, parentheses, and brackets
            if (c == '{') {
                return new Token(TokenType.LBRACE, "{", line, start_column);
            }
            if (c == '}') {
                return new Token(TokenType.RBRACE, "}", line, start_column);
            }
            if (c == '(') {
                return new Token(TokenType.LPAREN, "(", line, start_column);
            }
            if (c == ')') {
                return new Token(TokenType.RPAREN, ")", line, start_column);
            }
            if (c == '[') {
                // Check for [*] (initial/final state in state diagrams)
                if (peek() == '*') {
                    advance();  // consume *
                    if (peek() == ']') {
                        advance();  // consume ]
                        return new Token(TokenType.INITIAL_FINAL, "[*]", line, start_column);
                    }
                    // Put back * if not followed by ]
                    go_back_one_char();
                }
                // Check for [H] or [H*] (history states)
                if (peek() == 'H') {
                    advance();  // consume H
                    if (peek() == '*') {
                        advance();  // consume *
                        if (peek() == ']') {
                            advance();  // consume ]
                            return new Token(TokenType.DEEP_HISTORY, "[H*]", line, start_column);
                        }
                        go_back_one_char();  // put back *
                    }
                    if (peek() == ']') {
                        advance();  // consume ]
                        return new Token(TokenType.HISTORY, "[H]", line, start_column);
                    }
                    go_back_one_char();  // put back H
                }
                return new Token(TokenType.LBRACKET, "[", line, start_column);
            }
            if (c == ']') {
                return new Token(TokenType.RBRACKET, "]", line, start_column);
            }

            // Semicolon (activity diagram action end)
            if (c == ';') {
                return new Token(TokenType.SEMICOLON, ";", line, start_column);
            }

            // Pipe (activity diagram partition) or vertical space |||
            if (c == '|') {
                if (peek() == '|' && peek_next() == '|') {
                    advance();  // consume second |
                    advance();  // consume third |
                    return new Token(TokenType.VSPACE, "|||", line, start_column);
                }
                return new Token(TokenType.PIPE, "|", line, start_column);
            }

            // Horizontal separator ====
            if (c == '=') {
                if (peek() == '=' && peek_next() == '=') {
                    // Consume at least 3 more = for ====
                    advance();  // second =
                    advance();  // third =
                    while (peek() == '=') {
                        advance();
                    }
                    return new Token(TokenType.SEPARATOR, "====", line, start_column);
                }
                return new Token(TokenType.IDENTIFIER, "=", line, start_column);
            }

            // Visibility modifiers and other symbols
            if (c == '#') {
                // Scan color code: #RRGGBB, #RGB, or #colorname
                return scan_color(start_column);
            }
            if (c == '~') {
                return new Token(TokenType.TILDE, "~", line, start_column);
            }

            // Plus operators
            if (c == '+') {
                if (peek() == '+') {
                    advance();
                    return new Token(TokenType.PLUS_PLUS, "++", line, start_column);
                }
                return new Token(TokenType.PLUS, "+", line, start_column);
            }

            // Arrows, minus, and class relationships
            if (c == '-' || c == '<' || c == '.' || c == '*' || c == 'o') {
                return scan_arrow_or_relationship(c, start_column);
            }

            // Identifiers and keywords (ASCII letters and underscore)
            if (is_alpha(c)) {
                return scan_identifier(start_column);
            }

            // Numbers
            if (is_digit(c)) {
                return scan_number(start_column);
            }

            // Escape sequences (for newlines in labels, etc.)
            if (c == '\\') {
                unichar next = peek();
                if (next == 'n') {
                    advance();  // consume 'n'
                    return new Token(TokenType.IDENTIFIER, "\\n", line, start_column);
                } else if (next == 't') {
                    advance();  // consume 't'
                    return new Token(TokenType.IDENTIFIER, "\\t", line, start_column);
                } else if (next == '\\') {
                    advance();  // consume second '\'
                    return new Token(TokenType.IDENTIFIER, "\\\\", line, start_column);
                }
                // Fall through to unknown character if not an escape
            }

            // Unknown/Unicode character - return as identifier (includes UTF-8 chars like ≥, °, etc.)
            string char_str = c.to_string();
            return new Token(TokenType.IDENTIFIER, char_str, line, start_column);
        }

        private Token scan_number(int start_column) {
            while (is_digit(peek()) || peek() == '.') {
                advance();
            }
            string text = source.substring(start, current - start);
            return new Token(TokenType.IDENTIFIER, text, line, start_column);
        }

        private Token scan_line_comment(int start_column) {
            while (peek() != '\n' && !is_at_end()) {
                advance();
            }
            string text = source.substring(start, current - start);
            return new Token(TokenType.COMMENT, text, line, start_column);
        }

        private Token scan_block_comment(int start_column) {
            advance(); // consume '
            int start_line = line;

            while (!is_at_end()) {
                if (peek() == '\'' && peek_next() == '/') {
                    advance();
                    advance();
                    break;
                }
                if (peek() == '\n') {
                    line++;
                    line_start = current + 1;
                }
                advance();
            }

            string text = source.substring(start, current - start);
            return new Token(TokenType.COMMENT, text, start_line, start_column);
        }

        private Token scan_directive(int start_column) {
            while (is_alpha(peek())) {
                advance();
            }

            string text = source.substring(start, current - start).down();

            if (text == "@startuml") {
                return new Token(TokenType.STARTUML, text, line, start_column);
            } else if (text == "@enduml") {
                return new Token(TokenType.ENDUML, text, line, start_column);
            } else if (text == "@startmindmap") {
                return new Token(TokenType.STARTMINDMAP, text, line, start_column);
            } else if (text == "@endmindmap") {
                return new Token(TokenType.ENDMINDMAP, text, line, start_column);
            } else if (text == "@startwbs") {
                return new Token(TokenType.STARTWBS, text, line, start_column);
            } else if (text == "@endwbs") {
                return new Token(TokenType.ENDWBS, text, line, start_column);
            }

            return new Token(TokenType.IDENTIFIER, text, line, start_column);
        }

        private Token scan_string(int start_column) {
            int start_line = line;

            while (peek() != '"' && !is_at_end()) {
                if (peek() == '\n') {
                    line++;
                    line_start = current + 1;
                }
                if (peek() == '\\' && peek_next() == '"') {
                    advance();
                }
                advance();
            }

            if (!is_at_end()) {
                advance(); // closing "
            }

            // Extract string content without quotes
            string text = source.substring(start + 1, current - start - 2);
            return new Token(TokenType.STRING, text, start_line, start_column);
        }

        private Token scan_arrow_or_relationship(unichar first, int start_column) {
            // Handle arrow patterns and class relationships:
            // Sequence: -> --> ->> <- <-- <<- <->
            // Class: --|> <|-- ..|> <|.. o-- --o *-- --* ..>

            if (first == '<') {
                if (peek() == '|') {
                    advance();
                    if (peek() == '-') {
                        advance();
                        if (peek() == '-') {
                            advance();
                            return new Token(TokenType.INHERITANCE, "<|--", line, start_column);
                        }
                    }
                    if (peek() == '.') {
                        advance();
                        if (peek() == '.') {
                            advance();
                            return new Token(TokenType.IMPLEMENTATION, "<|..", line, start_column);
                        }
                    }
                }
                if (peek() == '-') {
                    advance();
                    if (peek() == '-') {
                        advance();
                        if (peek() == '>') {
                            advance();
                            return new Token(TokenType.ARROW_BIDIRECTIONAL, "<-->", line, start_column);
                        }
                        return new Token(TokenType.ARROW_LEFT_DOTTED, "<--", line, start_column);
                    }
                    if (peek() == '>') {
                        advance();
                        return new Token(TokenType.ARROW_BIDIRECTIONAL, "<->", line, start_column);
                    }
                    return new Token(TokenType.ARROW_LEFT, "<-", line, start_column);
                }
                if (peek() == '<') {
                    advance();
                    if (peek() == '-') {
                        advance();
                        return new Token(TokenType.ARROW_LEFT_OPEN, "<<-", line, start_column);
                    }
                    // Check for stereotype <<name>>
                    var stereo = scan_stereotype();
                    if (stereo != null) {
                        return stereo;
                    }
                    // Two << characters - return first one, the second will be returned next call
                    go_back_one_char();
                    return new Token(TokenType.IDENTIFIER, "<", line, start_column);
                }
                return new Token(TokenType.IDENTIFIER, "<", line, start_column);
            }

            if (first == '-') {
                if (peek() == '-') {
                    advance();
                    if (peek() == '|') {
                        advance();
                        if (peek() == '>') {
                            advance();
                            return new Token(TokenType.INHERITANCE, "--|>", line, start_column);
                        }
                    }
                    if (peek() == 'o') {
                        advance();
                        return new Token(TokenType.AGGREGATION, "--o", line, start_column);
                    }
                    if (peek() == '*') {
                        advance();
                        return new Token(TokenType.COMPOSITION, "--*", line, start_column);
                    }
                    if (peek() == '>') {
                        advance();
                        return new Token(TokenType.ARROW_RIGHT_DOTTED, "-->", line, start_column);
                    }
                    return new Token(TokenType.MINUS_MINUS, "--", line, start_column);
                }
                if (peek() == '>') {
                    advance();
                    if (peek() == '>') {
                        advance();
                        return new Token(TokenType.ARROW_RIGHT_OPEN, "->>", line, start_column);
                    }
                    return new Token(TokenType.ARROW_RIGHT, "->", line, start_column);
                }
                return new Token(TokenType.MINUS, "-", line, start_column);
            }

            if (first == '.') {
                if (peek() == '.') {
                    advance();
                    if (peek() == '|') {
                        advance();
                        if (peek() == '>') {
                            advance();
                            return new Token(TokenType.IMPLEMENTATION, "..|>", line, start_column);
                        }
                    }
                    if (peek() == '>') {
                        advance();
                        return new Token(TokenType.DEPENDENCY, "..>", line, start_column);
                    }
                }
                return new Token(TokenType.IDENTIFIER, ".", line, start_column);
            }

            if (first == '*') {
                if (peek() == '-') {
                    advance();
                    if (peek() == '-') {
                        advance();
                        return new Token(TokenType.COMPOSITION, "*--", line, start_column);
                    }
                }
                return new Token(TokenType.MULT, "*", line, start_column);
            }

            if (first == 'o') {
                if (peek() == '-') {
                    advance();
                    if (peek() == '-') {
                        advance();
                        return new Token(TokenType.AGGREGATION, "o--", line, start_column);
                    }
                    // Put back the character
                    go_back_one_char();
                }
                // This is actually an identifier starting with 'o'
                go_back_one_char();
                return scan_identifier(start_column);
            }

            // Handle standalone > (for stereotypes >>)
            if (first == '>') {
                return new Token(TokenType.IDENTIFIER, ">", line, start_column);
            }

            // Handle color codes: #RRGGBB or #RGB or #colorname
            if (first == '#') {
                return scan_color(start_column);
            }

            return new Token(TokenType.ERROR, first.to_string(), line, start_column);
        }

        private Token scan_color(int start_column) {
            // Scan #RRGGBB, #RGB, or #colorname
            var sb = new StringBuilder();
            sb.append_c('#');

            while (!is_at_end()) {
                unichar c = peek();
                if (c.isalnum()) {
                    sb.append_unichar(c);
                    advance();
                } else {
                    break;
                }
            }

            return new Token(TokenType.IDENTIFIER, sb.str, line, start_column);
        }

        // Scan a stereotype like <<choice>>, <<fork>>, etc.
        // Called after << has been consumed
        private Token? scan_stereotype() {
            int stereo_start = current;
            int col = column;
            var sb = new StringBuilder();

            // Collect the stereotype name
            while (!is_at_end()) {
                unichar c = peek();
                if (c == '>') {
                    // Check for >>
                    advance();
                    if (peek() == '>') {
                        advance();
                        string name = sb.str.strip();
                        if (name.length > 0) {
                            return new Token(TokenType.STEREOTYPE, name, line, col);
                        }
                    }
                    // Not >> - restore and fail
                    go_back_one_char();
                    break;
                } else if (c == '\n' || c == '<') {
                    // Invalid - newline or nested << in stereotype
                    break;
                } else {
                    sb.append_unichar(c);
                    advance();
                }
            }

            // Failed to parse stereotype - restore position
            while (current > stereo_start) {
                go_back_one_char();
            }
            return null;
        }

        private Token scan_identifier(int start_column) {
            // Identifiers: ASCII letters, digits, underscore, and Unicode letters
            while (!is_at_end()) {
                unichar c = peek();
                if (is_alphanumeric(c) || c == '_' || c.isalpha()) {
                    advance();
                } else {
                    break;
                }
            }

            string text = source.substring(start, current - start);
            string lower = text.down();

            // Only treat as keyword if it's all lowercase (case-sensitive keywords)
            // This allows "Participant" to be used as a name while "participant" is a keyword
            if (text == lower && keywords.contains(lower)) {
                return new Token(keywords.get(lower), text, line, start_column);
            }

            return new Token(TokenType.IDENTIFIER, text, line, start_column);
        }

        private void skip_whitespace() {
            while (!is_at_end()) {
                unichar c = peek();
                switch (c) {
                    case ' ':
                    case '\r':
                    case '\t':
                        advance();
                        break;
                    case '\n':
                        // Don't skip newlines - they're significant
                        return;
                    default:
                        return;
                }
            }
        }

        private bool is_at_end() {
            return current >= source.length;
        }

        // Advance to the next UTF-8 character and return it
        private unichar advance() {
            if (is_at_end()) return '\0';

            unichar c;
            int next_pos = current;
            if (!source.get_next_char(ref next_pos, out c)) {
                // Invalid UTF-8, advance by one byte
                c = (unichar) source[current];
                current++;
            } else {
                current = next_pos;
            }

            column++;

            if (c == '\n') {
                line++;
                line_start = current;
                column = 1;
            }

            return c;
        }

        // Peek at the current character without advancing
        private unichar peek() {
            if (is_at_end()) return '\0';

            unichar c;
            int pos = current;
            if (!source.get_next_char(ref pos, out c)) {
                // Invalid UTF-8, return byte as char
                return (unichar) source[current];
            }
            return c;
        }

        // Peek at the next character (one after current)
        private unichar peek_next() {
            if (is_at_end()) return '\0';

            // First, get past current character
            unichar c;
            int pos = current;
            if (!source.get_next_char(ref pos, out c)) {
                pos = current + 1;
            }

            // Now peek at the next one
            if (pos >= source.length) return '\0';

            if (!source.get_next_char(ref pos, out c)) {
                return (unichar) source[pos];
            }
            return c;
        }

        // Go back one character (for lookahead failures)
        private void go_back_one_char() {
            if (current <= 0) return;

            // Move back byte by byte until we find a valid UTF-8 start
            current--;
            column--;

            // In UTF-8, continuation bytes start with 10xxxxxx (0x80-0xBF)
            // Keep going back if we're on a continuation byte
            while (current > 0 && (source[current] & 0xC0) == 0x80) {
                current--;
            }
        }

        private bool is_alpha(unichar c) {
            return (c >= 'a' && c <= 'z') ||
                   (c >= 'A' && c <= 'Z') ||
                   c == '_';
        }

        private bool is_digit(unichar c) {
            return c >= '0' && c <= '9';
        }

        private bool is_alphanumeric(unichar c) {
            return is_alpha(c) || is_digit(c);
        }
    }
}
