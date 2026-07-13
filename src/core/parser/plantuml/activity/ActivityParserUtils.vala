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

                // Spaces only where the source has them (multi-byte characters and
                // symbols like ">=" used to be split or padded)
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        /**
         * True for an inline colour token. The Lexer scans "#pink", "#FF0000" and
         * gradients "#red/white" as ONE IDENTIFIER that keeps the "#"; a separate
         * HASH token only comes from split forms, which callers handle as a fallback.
         */
        public static bool is_color_token(Token t) {
            return t.token_type == TokenType.IDENTIFIER && t.lexeme.length > 1 && t.lexeme.has_prefix("#");
        }

        // Colour names PlantUML accepts after "#": the CSS/SVG names plus "transparent"
        // and the ArchiMate names
        private const string COLOR_NAMES =
            "aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue " +
            "blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue " +
            "cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgrey darkgreen " +
            "darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon " +
            "darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet " +
            "deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen " +
            "fuchsia gainsboro ghostwhite gold goldenrod gray grey green greenyellow honeydew " +
            "hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon " +
            "lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgrey lightgreen " +
            "lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey " +
            "lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine " +
            "mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen " +
            "mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite " +
            "navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen " +
            "paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple " +
            "rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell " +
            "sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan " +
            "teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen " +
            "transparent application business implementation motivation physical strategy " +
            "technology";

        private static Gee.HashSet<string>? color_names = null;

        /**
         * True when `value` (without the leading "#") is a colour PlantUML reads: a hex
         * code of 3, 6 or 8 digits, a colour name, or a gradient of two of them joined by
         * "|", "-", "/" or "\\". "#7" in "group Issue #7" is none of these: it is text.
         */
        public static bool is_color_value(string value) {
            string v = value.strip();
            if (v.has_prefix("#")) {
                v = v.substring(1);
            }
            int semi = v.index_of(";");  // "#pink;line:red": the fill comes first
            if (semi >= 0) {
                v = v.substring(0, semi);
            }
            for (int i = 1; i < v.length - 1; i++) {
                char ch = v[i];
                if (ch == '|' || ch == '-' || ch == '/' || ch == '\\') {
                    string second = v.substring(i + 1);
                    if (second.has_prefix("#")) {
                        second = second.substring(1);
                    }
                    return is_single_color(v.substring(0, i)) && is_single_color(second);
                }
            }
            return is_single_color(v);
        }

        private static bool is_single_color(string s) {
            if ((s.length == 3 || s.length == 6 || s.length == 8) && is_hex_digits(s)) {
                return true;
            }
            if (color_names == null) {
                color_names = new Gee.HashSet<string>();
                foreach (string n in COLOR_NAMES.split(" ")) {
                    if (n.length > 0) {
                        color_names.add(n);
                    }
                }
            }
            return color_names.contains(s.down());
        }

        private static bool is_hex_digits(string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                if (!s[i].isxdigit()) return false;
            }
            return true;
        }

        /** An inline colour token (see is_color_token) whose value is a real colour. */
        public static bool is_valid_color_token(Token t) {
            return is_color_token(t) && is_color_value(t.lexeme);
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
