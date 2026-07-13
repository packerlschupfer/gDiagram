namespace GDiagram {
    /**
     * Utility methods for parsing activity diagrams.
     * Provides helper functions for token consumption and validation.
     */
    public class ActivityParserUtils : Object {
        private TokenStream stream;

        public ActivityParserUtils(TokenStream stream) {
            this.stream = stream;
        }

        /**
         * Consume tokens until matching closing parenthesis, respecting nesting.
         * Returns the collected text as a string.
         */
        public string consume_until_rparen() {
            var sb = new StringBuilder();
            int depth = 1;

            while (depth > 0 && !stream.is_at_end()) {
                if (stream.check(TokenType.LPAREN)) {
                    depth++;
                } else if (stream.check(TokenType.RPAREN)) {
                    depth--;
                    if (depth == 0) {
                        stream.advance();
                        break;
                    }
                }
                Token t = stream.advance();

                // Skip spaces around UTF-8 bytes (lexer tokenizes them separately)
                bool is_utf8_byte = false;
                if (t.lexeme.length == 1) {
                    uint8 b = (uint8)t.lexeme[0];
                    is_utf8_byte = b >= 0x80;
                }
                bool prev_ends_with_utf8 = false;
                if (sb.len > 0) {
                    uint8 last_b = (uint8)sb.str[sb.len - 1];
                    prev_ends_with_utf8 = last_b >= 0x80;
                }

                if (sb.len > 0 && !is_utf8_byte && !prev_ends_with_utf8) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        /**
         * Check if a string is a valid 6-character hex color code.
         */
        public static bool is_hex_color(string str) {
            if (str.length != 6) return false;
            foreach (char c in str.to_utf8()) {
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                    return false;
                }
            }
            return true;
        }

        /**
         * Check if next token (current+1) matches type.
         */
        public bool check_next(TokenType type) {
            int next_pos = stream.current + 1;
            if (next_pos >= stream.size()) return false;
            stream.advance();
            bool result = stream.peek().token_type == type;
            stream.current--;
            return result;
        }

        /**
         * Check if next token matches a specific lexeme.
         */
        public bool check_next_lexeme(string lexeme) {
            int next_pos = stream.current + 1;
            if (next_pos >= stream.size()) return false;
            stream.advance();
            bool result = stream.peek().lexeme == lexeme;
            stream.current--;
            return result;
        }
    }
}
