namespace GDiagram {
    /**
     * Pure static utility class for text formatting and spacing logic.
     * Handles Creole markup, UTF-8 characters, and spacing rules.
     */
    public class ActivityTextFormatter : Object {
        /**
         * Determine if we should add a space before a token during text collection
         * for Creole formatting support. Returns true if space should be added.
         */
        public static bool should_add_space_before(string prev_text, string next_lexeme) {
            // Skip spaces around UTF-8 bytes (lexer tokenizes multi-byte chars separately)
            // UTF-8 high bytes are >= 0x80
            if (next_lexeme.length == 1) {
                uint8 b = (uint8)next_lexeme[0];
                if (b >= 0x80) return false;  // Don't add space before UTF-8 byte
            }
            if (prev_text.length > 0) {
                uint8 last_b = (uint8)prev_text[prev_text.length - 1];
                if (last_b >= 0x80) return false;  // Don't add space after UTF-8 byte
            }

            // Creole marker characters
            bool next_is_marker = next_lexeme == "*" || next_lexeme == "/" ||
                                  next_lexeme == "_" || next_lexeme == "~";
            // Note: "-" is tricky because it's also used in regular text

            // Check what the previous text ends with
            bool prev_ends_single_star = prev_text.has_suffix("*") && !prev_text.has_suffix("**");
            bool prev_ends_single_slash = prev_text.has_suffix("/") && !prev_text.has_suffix("//");
            bool prev_ends_single_underscore = prev_text.has_suffix("_") && !prev_text.has_suffix("__");
            bool prev_ends_single_tilde = prev_text.has_suffix("~") && !prev_text.has_suffix("~~");

            bool prev_ends_double_star = prev_text.has_suffix("**");
            bool prev_ends_double_slash = prev_text.has_suffix("//");
            bool prev_ends_double_underscore = prev_text.has_suffix("__");
            bool prev_ends_double_tilde = prev_text.has_suffix("~~");

            // Count markers to determine if we're inside formatting
            int star_count = count_occurrences(prev_text, "**");
            int slash_count = count_occurrences(prev_text, "//");
            int underscore_count = count_occurrences(prev_text, "__");
            int tilde_count = count_occurrences(prev_text, "~~");

            // Rule 1: Don't add space between two consecutive markers of same type
            // e.g., "*" followed by "*" should produce "**"
            if (prev_ends_single_star && next_lexeme == "*") return false;
            if (prev_ends_single_slash && next_lexeme == "/") return false;
            if (prev_ends_single_underscore && next_lexeme == "_") return false;
            if (prev_ends_single_tilde && next_lexeme == "~") return false;

            // Rule 2: Don't add space after OPENING double markers (odd count = inside)
            // e.g., "**" followed by "Bold" should produce "**Bold"
            // But "**Bold**" followed by "and" should produce "**Bold** and"
            if (prev_ends_double_star && !next_is_marker && star_count % 2 == 1) return false;
            if (prev_ends_double_slash && !next_is_marker && slash_count % 2 == 1) return false;
            if (prev_ends_double_underscore && !next_is_marker && underscore_count % 2 == 1) return false;
            if (prev_ends_double_tilde && !next_is_marker && tilde_count % 2 == 1) return false;

            // Rule 3: Don't add space before closing markers (first marker of pair)
            // e.g., "Bold" followed by "*" should produce "Bold*"
            // If the text contains an odd number of double markers, we're inside
            if (next_is_marker) {
                // If we're inside bold (odd count of **) and next is *, don't add space
                if (next_lexeme == "*" && star_count % 2 == 1) return false;
                if (next_lexeme == "/" && slash_count % 2 == 1) return false;
                if (next_lexeme == "_" && underscore_count % 2 == 1) return false;
                if (next_lexeme == "~" && tilde_count % 2 == 1) return false;
            }

            // Default: add space
            return true;
        }

        /**
         * Count non-overlapping occurrences of a substring.
         */
        public static int count_occurrences(string text, string sub) {
            int count = 0;
            int pos = 0;
            while ((pos = text.index_of(sub, pos)) >= 0) {
                count++;
                pos += sub.length;
            }
            return count;
        }

        /**
         * Check if a token is a Creole marker character.
         */
        public static bool is_creole_marker(string lexeme) {
            return lexeme == "*" || lexeme == "/" || lexeme == "_" ||
                   lexeme == "-" || lexeme == "~";
        }

        /**
         * Check if a character is a UTF-8 high byte.
         */
        public static bool is_utf8_byte(string lexeme) {
            if (lexeme.length != 1) return false;
            uint8 b = (uint8)lexeme[0];
            return b >= 0x80;
        }

        /**
         * Check if string ends with a UTF-8 high byte.
         */
        public static bool ends_with_utf8_byte(string text) {
            if (text.length == 0) return false;
            uint8 last_b = (uint8)text[text.length - 1];
            return last_b >= 0x80;
        }
    }
}
