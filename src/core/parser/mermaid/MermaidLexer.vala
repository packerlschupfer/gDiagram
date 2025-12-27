namespace GDiagram {
    public class MermaidLexer : Object {
        private string source;
        private int current;       // Byte position in source
        private int start;         // Byte position of current token start
        private int line;
        private int column;

        private static HashTable<string, MermaidTokenType?>? keywords = null;

        public MermaidLexer(string source) {
            this.source = source;
            this.current = 0;
            this.start = 0;
            this.line = 1;
            this.column = 1;

            init_keywords();
        }

        private static void init_keywords() {
            if (keywords != null) return;

            keywords = new HashTable<string, MermaidTokenType>(str_hash, str_equal);

            // Diagram types
            keywords.insert("flowchart", MermaidTokenType.FLOWCHART);
            keywords.insert("sequenceDiagram", MermaidTokenType.SEQUENCE_DIAGRAM);
            keywords.insert("stateDiagram-v2", MermaidTokenType.STATE_DIAGRAM);
            keywords.insert("classDiagram", MermaidTokenType.CLASS_DIAGRAM);
            keywords.insert("erDiagram", MermaidTokenType.ER_DIAGRAM);
            keywords.insert("gantt", MermaidTokenType.GANTT);
            keywords.insert("pie", MermaidTokenType.PIE);
            keywords.insert("gitGraph", MermaidTokenType.GIT_GRAPH);
            keywords.insert("journey", MermaidTokenType.USER_JOURNEY);

            // Direction keywords
            keywords.insert("TD", MermaidTokenType.TD);
            keywords.insert("TB", MermaidTokenType.TB);
            keywords.insert("BT", MermaidTokenType.BT);
            keywords.insert("LR", MermaidTokenType.LR);
            keywords.insert("RL", MermaidTokenType.RL);

            // Flowchart keywords
            keywords.insert("subgraph", MermaidTokenType.SUBGRAPH);
            keywords.insert("end", MermaidTokenType.END);
            keywords.insert("style", MermaidTokenType.STYLE);
            keywords.insert("classDef", MermaidTokenType.CLASS_DEF);
            keywords.insert("class", MermaidTokenType.CLASS_KW);
            keywords.insert("click", MermaidTokenType.CLICK);

            // Sequence diagram keywords
            keywords.insert("participant", MermaidTokenType.PARTICIPANT);
            keywords.insert("actor", MermaidTokenType.ACTOR);
            keywords.insert("activate", MermaidTokenType.ACTIVATE);
            keywords.insert("deactivate", MermaidTokenType.DEACTIVATE);
            keywords.insert("Note", MermaidTokenType.NOTE);
            keywords.insert("over", MermaidTokenType.OVER);
            keywords.insert("autonumber", MermaidTokenType.AUTONUMBER);
            keywords.insert("loop", MermaidTokenType.LOOP);
            keywords.insert("alt", MermaidTokenType.ALT);
            keywords.insert("else", MermaidTokenType.ELSE);
            keywords.insert("opt", MermaidTokenType.OPT);
            keywords.insert("par", MermaidTokenType.PAR);
            keywords.insert("and", MermaidTokenType.AND);
            keywords.insert("critical", MermaidTokenType.CRITICAL);
            keywords.insert("break", MermaidTokenType.BREAK);
            keywords.insert("rect", MermaidTokenType.RECT);

            // State diagram keywords
            keywords.insert("state", MermaidTokenType.STATE);

            // Common keywords
            keywords.insert("as", MermaidTokenType.AS);
            keywords.insert("title", MermaidTokenType.TITLE);
            keywords.insert("direction", MermaidTokenType.DIRECTION);
        }

        public Gee.ArrayList<MermaidToken> scan_all() {
            var tokens = new Gee.ArrayList<MermaidToken>();

            while (!is_at_end()) {
                var token = scan_token();
                if (token != null) {
                    tokens.add(token);
                }
            }

            tokens.add(new MermaidToken(MermaidTokenType.EOF, "", line, column));
            return tokens;
        }

        public MermaidToken? scan_token() {
            skip_whitespace();

            if (is_at_end()) {
                return null;
            }

            start = current;
            int start_column = column;

            unichar c = advance();

            // Comments (Mermaid uses %% for comments)
            if (c == '%' && peek() == '%') {
                return scan_comment(start_column);
            }

            // Newline
            if (c == '\n') {
                return new MermaidToken(MermaidTokenType.NEWLINE, "\\n", line - 1, start_column);
            }

            // Strings
            if (c == '"') {
                return scan_string('"', start_column);
            }
            if (c == '\'') {
                return scan_string('\'', start_column);
            }
            if (c == '`') {
                return scan_string('`', start_column);
            }

            // Arrows and lines - Complex matching for Mermaid
            if (c == '-') {
                // Check if it's a dotted arrow starting with -.
                if (peek() == '.') {
                    return scan_dotted_arrow_from_dash(start_column);
                }
                return scan_arrow_or_line(start_column);
            }
            if (c == '=') {
                if (peek() == '=') {
                    return scan_thick_arrow(start_column);
                }
                return new MermaidToken(MermaidTokenType.EQUALS, "=", line, start_column);
            }
            if (c == '~' && peek() == '~') {
                return scan_invisible_line(start_column);
            }
            if (c == '.' && peek() == '-') {
                return scan_dotted_arrow(start_column);
            }
            if (c == '<') {
                // Check for inheritance arrow <|--
                if (peek() == '|') {
                    return scan_inheritance_arrow_left(start_column);
                }
                // Check for regular left arrow <--
                if (peek() == '-') {
                    return scan_left_arrow(start_column);
                }
                return new MermaidToken(MermaidTokenType.ASYMMETRIC_START, "<", line, start_column);
            }

            // Symbols - complex delimiters for node shapes
            if (c == '(') {
                return scan_parenthesis(start_column);
            }
            if (c == ')') {
                return scan_close_parenthesis(start_column);
            }
            if (c == '[') {
                return scan_bracket(start_column);
            }
            if (c == ']') {
                return scan_close_bracket(start_column);
            }
            if (c == '{') {
                return scan_brace(start_column);
            }
            if (c == '}') {
                return scan_close_brace(start_column);
            }

            // Simple symbols
            if (c == '>') {
                return new MermaidToken(MermaidTokenType.ASYMMETRIC_START, ">", line, start_column);
            }
            if (c == '|') {
                return new MermaidToken(MermaidTokenType.PIPE, "|", line, start_column);
            }
            if (c == ':') {
                return new MermaidToken(MermaidTokenType.COLON, ":", line, start_column);
            }
            if (c == ';') {
                return new MermaidToken(MermaidTokenType.SEMICOLON, ";", line, start_column);
            }
            if (c == ',') {
                return new MermaidToken(MermaidTokenType.COMMA, ",", line, start_column);
            }
            if (c == '&') {
                return new MermaidToken(MermaidTokenType.AMPERSAND, "&", line, start_column);
            }
            if (c == '#') {
                return new MermaidToken(MermaidTokenType.HASH, "#", line, start_column);
            }
            if (c == '%') {
                return new MermaidToken(MermaidTokenType.PERCENT, "%", line, start_column);
            }
            if (c == '~') {
                // Check if it's invisible line or just tilde
                if (peek() == '~') {
                    return scan_invisible_line(start_column);
                }
                return new MermaidToken(MermaidTokenType.TILDE, "~", line, start_column);
            }
            if (c == '/') {
                return new MermaidToken(MermaidTokenType.SLASH_RBRACKET, "/", line, start_column);
            }
            if (c == '\\') {
                return new MermaidToken(MermaidTokenType.BACKSLASH_RBRACKET, "\\", line, start_column);
            }
            if (c == '?') {
                return new MermaidToken(MermaidTokenType.QUESTION, "?", line, start_column);
            }
            if (c == '!') {
                return new MermaidToken(MermaidTokenType.EXCLAMATION, "!", line, start_column);
            }
            if (c == '@') {
                return new MermaidToken(MermaidTokenType.AT, "@", line, start_column);
            }
            if (c == '$') {
                return new MermaidToken(MermaidTokenType.DOLLAR, "$", line, start_column);
            }
            if (c == '+') {
                return new MermaidToken(MermaidTokenType.PLUS, "+", line, start_column);
            }
            if (c == '*') {
                return new MermaidToken(MermaidTokenType.ASTERISK, "*", line, start_column);
            }

            // Numbers
            if (c.isdigit()) {
                return scan_number(start_column);
            }

            // Identifiers and keywords
            if (c.isalpha() || c == '_') {
                return scan_identifier(start_column);
            }

            // Unknown character - skip it
            return null;
        }

        private MermaidToken scan_comment(int start_column) {
            // Skip the second %
            advance();

            // Read until end of line
            while (peek() != '\n' && !is_at_end()) {
                advance();
            }

            string text = source.substring(start, current - start);
            return new MermaidToken(MermaidTokenType.COMMENT, text, line, start_column);
        }

        private MermaidToken scan_string(unichar quote, int start_column) {
            var sb = new StringBuilder();

            while (peek() != quote && !is_at_end()) {
                if (peek() == '\n') {
                    line++;
                    column = 0;
                }
                if (peek() == '\\') {
                    advance(); // Skip backslash
                    if (!is_at_end()) {
                        sb.append_unichar(advance());
                    }
                } else {
                    sb.append_unichar(advance());
                }
            }

            if (!is_at_end()) {
                advance(); // Closing quote
            }

            return new MermaidToken(MermaidTokenType.STRING, sb.str, line, start_column);
        }

        private MermaidToken scan_arrow_or_line(int start_column) {
            // We've seen '-', now check what follows
            // Patterns: ->, -->>, -->, --o, --x, --@, ----, -.->, etc.

            var sb = new StringBuilder();
            sb.append_c('-');

            // Count consecutive dashes
            int dash_count = 1;
            while (peek() == '-') {
                sb.append_c((char)advance());
                dash_count++;
            }

            // Check for arrow endings
            if (peek() == '>') {
                sb.append_c((char)advance());
                // Check for double >> (sequence diagram style)
                if (peek() == '>') {
                    sb.append_c((char)advance());
                }
                if (dash_count == 1) {
                    return new MermaidToken(MermaidTokenType.SEQ_SOLID_ARROW, sb.str, line, start_column);
                } else {
                    return new MermaidToken(MermaidTokenType.ARROW_SOLID, sb.str, line, start_column);
                }
            }
            if (peek() == 'o') {
                sb.append_c((char)advance());
                if (dash_count == 1) {
                    return new MermaidToken(MermaidTokenType.SEQ_SOLID_OPEN, sb.str, line, start_column);
                } else {
                    return new MermaidToken(MermaidTokenType.ARROW_OPEN_SOLID, sb.str, line, start_column);
                }
            }
            if (peek() == 'x') {
                sb.append_c((char)advance());
                if (dash_count == 1) {
                    return new MermaidToken(MermaidTokenType.SEQ_SOLID_CROSS, sb.str, line, start_column);
                } else {
                    return new MermaidToken(MermaidTokenType.ARROW_CROSS_SOLID, sb.str, line, start_column);
                }
            }
            if (peek() == '@') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_CIRCLE_SOLID, sb.str, line, start_column);
            }

            // Just a line
            if (dash_count == 1) {
                return new MermaidToken(MermaidTokenType.SEQ_SOLID_LINE, sb.str, line, start_column);
            } else {
                return new MermaidToken(MermaidTokenType.LINE_SOLID, sb.str, line, start_column);
            }
        }

        private MermaidToken scan_thick_arrow(int start_column) {
            var sb = new StringBuilder();
            sb.append_c('=');
            advance(); // Skip second '='

            // Count consecutive equals
            while (peek() == '=') {
                sb.append_c((char)advance());
            }

            // Check for arrow ending
            if (peek() == '>') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_THICK, sb.str, line, start_column);
            }

            return new MermaidToken(MermaidTokenType.LINE_THICK, sb.str, line, start_column);
        }

        private MermaidToken scan_invisible_line(int start_column) {
            var sb = new StringBuilder();

            // Consume all tildes
            while (peek() == '~') {
                sb.append_c((char)advance());
            }

            return new MermaidToken(MermaidTokenType.ARROW_INVISIBLE, sb.str, line, start_column);
        }

        private MermaidToken scan_dotted_arrow_from_dash(int start_column) {
            // We've already consumed '-', now we see '.'
            var sb = new StringBuilder();
            sb.append_c('-');

            // Pattern: -.-> or -.-
            while (peek() == '-' || peek() == '.') {
                sb.append_c((char)advance());
            }

            // Check for arrow endings
            if (peek() == '>') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_DOTTED, sb.str, line, start_column);
            }
            if (peek() == 'o') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_OPEN_DOTTED, sb.str, line, start_column);
            }
            if (peek() == 'x') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_CROSS_DOTTED, sb.str, line, start_column);
            }

            return new MermaidToken(MermaidTokenType.LINE_DOTTED, sb.str, line, start_column);
        }

        private MermaidToken scan_dotted_arrow(int start_column) {
            var sb = new StringBuilder();
            sb.append_c('.');

            // Pattern: .-> or -.-> or -.-
            while (peek() == '-' || peek() == '.') {
                sb.append_c((char)advance());
            }

            // Check for arrow endings
            if (peek() == '>') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_DOTTED, sb.str, line, start_column);
            }
            if (peek() == 'o') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_OPEN_DOTTED, sb.str, line, start_column);
            }
            if (peek() == 'x') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_CROSS_DOTTED, sb.str, line, start_column);
            }

            return new MermaidToken(MermaidTokenType.LINE_DOTTED, sb.str, line, start_column);
        }

        private MermaidToken scan_inheritance_arrow_left(int start_column) {
            // We've seen '<', now we see '|'
            var sb = new StringBuilder();
            sb.append_c('<');
            sb.append_c((char)advance()); // consume '|'

            // Consume dashes
            while (peek() == '-') {
                sb.append_c((char)advance());
            }

            return new MermaidToken(MermaidTokenType.INHERITANCE_LEFT, sb.str, line, start_column);
        }

        private MermaidToken scan_left_arrow(int start_column) {
            var sb = new StringBuilder();
            sb.append_c('<');

            // Consume all dashes
            while (peek() == '-') {
                sb.append_c((char)advance());
            }

            // Check for bidirectional
            if (peek() == '>') {
                sb.append_c((char)advance());
                return new MermaidToken(MermaidTokenType.ARROW_BIDIRECTIONAL, sb.str, line, start_column);
            }

            return new MermaidToken(MermaidTokenType.ARROW_SOLID, sb.str, line, start_column);
        }

        private MermaidToken scan_parenthesis(int start_column) {
            // Check for (( or (((
            if (peek() == '(') {
                advance();
                if (peek() == '(') {
                    advance();
                    return new MermaidToken(MermaidTokenType.TRIPLE_LPAREN, "(((", line, start_column);
                }
                return new MermaidToken(MermaidTokenType.DOUBLE_LPAREN, "((", line, start_column);
            }
            // Check for ([
            if (peek() == '[') {
                advance();
                return new MermaidToken(MermaidTokenType.LBRACKET_LPAREN, "([", line, start_column);
            }

            return new MermaidToken(MermaidTokenType.LPAREN, "(", line, start_column);
        }

        private MermaidToken scan_close_parenthesis(int start_column) {
            // Check for )) or )))
            if (peek() == ')') {
                advance();
                if (peek() == ')') {
                    advance();
                    return new MermaidToken(MermaidTokenType.TRIPLE_RPAREN, ")))", line, start_column);
                }
                return new MermaidToken(MermaidTokenType.DOUBLE_RPAREN, "))", line, start_column);
            }

            return new MermaidToken(MermaidTokenType.RPAREN, ")", line, start_column);
        }

        private MermaidToken scan_bracket(int start_column) {
            // Check for [[
            if (peek() == '[') {
                advance();
                return new MermaidToken(MermaidTokenType.DOUBLE_LBRACKET, "[[", line, start_column);
            }
            // Check for [/ or [\
            if (peek() == '/') {
                advance();
                return new MermaidToken(MermaidTokenType.LBRACKET_SLASH, "[/", line, start_column);
            }
            if (peek() == '\\') {
                advance();
                return new MermaidToken(MermaidTokenType.LBRACKET_BACKSLASH, "[\\", line, start_column);
            }
            // Check for [*] (initial/final state)
            if (peek() == '*') {
                int saved = current;
                advance();
                if (peek() == ']') {
                    advance();
                    return new MermaidToken(MermaidTokenType.INITIAL, "[*]", line, start_column);
                }
                // Backtrack
                current = saved;
                column = start_column;
            }

            return new MermaidToken(MermaidTokenType.LBRACKET, "[", line, start_column);
        }

        private MermaidToken scan_close_bracket(int start_column) {
            // Check for ]]
            if (peek() == ']') {
                advance();
                return new MermaidToken(MermaidTokenType.DOUBLE_RBRACKET, "]]", line, start_column);
            }
            // Check for ])
            if (peek() == ')') {
                advance();
                return new MermaidToken(MermaidTokenType.RPAREN_RBRACKET, "])", line, start_column);
            }

            return new MermaidToken(MermaidTokenType.RBRACKET, "]", line, start_column);
        }

        private MermaidToken scan_brace(int start_column) {
            // Check for {{
            if (peek() == '{') {
                advance();
                return new MermaidToken(MermaidTokenType.LBRACE_LBRACE, "{{", line, start_column);
            }

            return new MermaidToken(MermaidTokenType.LBRACE, "{", line, start_column);
        }

        private MermaidToken scan_close_brace(int start_column) {
            // Check for }}
            if (peek() == '}') {
                advance();
                return new MermaidToken(MermaidTokenType.RBRACE_RBRACE, "}}", line, start_column);
            }

            return new MermaidToken(MermaidTokenType.RBRACE, "}", line, start_column);
        }

        private MermaidToken scan_number(int start_column) {
            var sb = new StringBuilder();
            sb.append_unichar(source[current - 1]);

            while (peek().isdigit() || peek() == '.') {
                sb.append_unichar(advance());
            }

            return new MermaidToken(MermaidTokenType.NUMBER, sb.str, line, start_column);
        }

        private MermaidToken scan_identifier(int start_column) {
            var sb = new StringBuilder();
            sb.append_unichar(source[current - 1]);

            while (peek().isalnum() || peek() == '_') {
                sb.append_unichar(advance());
            }

            // Allow dashes in identifiers, but be careful not to consume arrow prefixes
            // Allow dash only if it's followed by alphanumeric (not >, -, etc.)
            while (peek() == '-') {
                // Save position in case we need to backtrack
                int saved_current = current;
                int saved_column = column;

                sb.append_unichar(advance()); // consume the dash

                // Check what follows the dash
                if (peek().isalnum() || peek() == '_') {
                    // It's part of the identifier, continue reading
                    while (peek().isalnum() || peek() == '_') {
                        sb.append_unichar(advance());
                    }
                    // Check for more dashes
                    continue;
                } else {
                    // It's not part of the identifier (probably an arrow), backtrack
                    current = saved_current;
                    column = saved_column;
                    // Remove the dash we just added
                    var temp = sb.str;
                    sb = new StringBuilder();
                    sb.append(temp.substring(0, temp.length - 1));
                    break;
                }
            }

            string text = sb.str;

            // Check if it's a keyword
            MermaidTokenType? keyword_type = keywords.lookup(text);
            if (keyword_type != null) {
                return new MermaidToken(keyword_type, text, line, start_column);
            }

            return new MermaidToken(MermaidTokenType.IDENTIFIER, text, line, start_column);
        }

        private void skip_whitespace() {
            while (!is_at_end()) {
                unichar c = peek();
                if (c == ' ' || c == '\t' || c == '\r') {
                    advance();
                } else {
                    break;
                }
            }
        }

        private unichar peek() {
            if (is_at_end()) return '\0';
            return source[current];
        }

        private unichar advance() {
            column++;
            if (is_at_end()) return '\0';

            unichar c = source[current];
            current++;

            if (c == '\n') {
                line++;
                column = 0;
            }

            return c;
        }

        private bool is_at_end() {
            return current >= source.length;
        }
    }
}
