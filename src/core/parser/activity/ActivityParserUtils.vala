namespace GPlantUML {
    /**
     * Utility methods for parsing activity diagrams.
     * Provides helper functions for token consumption and validation.
     */
    public class ActivityParserUtils : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;

        public ActivityParserUtils(Gee.ArrayList<Token> tokens, ref int current) {
            this.tokens = tokens;
            this.current = current;
        }

        /**
         * Consume tokens until matching closing parenthesis, respecting nesting.
         * Returns the collected text as a string.
         */
        public string consume_until_rparen(ref int position) {
            current = position;
            var sb = new StringBuilder();
            int depth = 1;

            while (depth > 0 && !is_at_end()) {
                if (check(TokenType.LPAREN)) {
                    depth++;
                } else if (check(TokenType.RPAREN)) {
                    depth--;
                    if (depth == 0) {
                        advance();
                        position = current;
                        break;
                    }
                }
                Token t = advance();

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

            position = current;
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
         * Check if current token matches type without consuming it.
         */
        private bool check(TokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        /**
         * Check if next token (current+1) matches type.
         */
        public bool check_next(TokenType type) {
            if (current + 1 >= tokens.size) return false;
            return tokens.get(current + 1).token_type == type;
        }

        /**
         * Check if next token matches a specific lexeme.
         */
        public bool check_next_lexeme(string lexeme) {
            if (current + 1 >= tokens.size) return false;
            return tokens.get(current + 1).lexeme == lexeme;
        }

        /**
         * Advance to next token.
         */
        private Token advance() {
            if (!is_at_end()) {
                current++;
            }
            return previous();
        }

        /**
         * Check if at end of token stream.
         */
        private bool is_at_end() {
            return peek().token_type == TokenType.EOF;
        }

        /**
         * Get current token without advancing.
         */
        private Token peek() {
            return tokens.get(current);
        }

        /**
         * Get previous token.
         */
        private Token previous() {
            return tokens.get(current - 1);
        }
    }
}
