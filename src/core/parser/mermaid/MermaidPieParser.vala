namespace GDiagram {
    public class MermaidPieParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidPie diagram;

        public MermaidPieParser() {
            this.current = 0;
        }

        public MermaidPie parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidPie();

            try {
                parse_pie();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_pie() throws GLib.Error {
            skip_newlines();

            // Expect pie keyword
            if (!match(MermaidTokenType.PIE)) {
                error_at_current("Expected 'pie'");
            }

            skip_newlines();

            // Check for showData keyword
            if (check(MermaidTokenType.IDENTIFIER) && peek().lexeme == "showData") {
                advance();
                diagram.show_data = true;
                skip_newlines();
            }

            // Parse statements until EOF
            while (!is_at_end()) {
                try {
                    parse_statement();
                } catch (GLib.Error e) {
                    diagram.errors.add(new ParseError(
                        e.message,
                        previous().line,
                        previous().column
                    ));
                    synchronize();
                }
                skip_newlines();
            }
        }

        private void parse_statement() throws GLib.Error {
            skip_newlines();

            if (is_at_end()) {
                return;
            }

            // Skip comments
            if (match(MermaidTokenType.COMMENT)) {
                return;
            }

            // Title
            if (check(MermaidTokenType.TITLE)) {
                parse_title();
                return;
            }

            // Data entry: "Label" : value
            if (check(MermaidTokenType.STRING) || check(MermaidTokenType.IDENTIFIER)) {
                parse_slice();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_title() throws GLib.Error {
            advance(); // consume 'title'
            var title_parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (title_parts.len > 0) {
                    title_parts.append(" ");
                }
                title_parts.append(advance().lexeme);
            }
            diagram.title = title_parts.str.strip();
        }

        private void parse_slice() throws GLib.Error {
            // Get label (can be quoted or unquoted)
            string label;
            if (check(MermaidTokenType.STRING)) {
                label = advance().lexeme;
            } else {
                var label_parts = new StringBuilder();
                while (!check(MermaidTokenType.COLON) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (label_parts.len > 0) {
                        label_parts.append(" ");
                    }
                    label_parts.append(advance().lexeme);
                }
                label = label_parts.str.strip();
            }

            if (label.length == 0) {
                return;
            }

            // Expect colon
            if (!match(MermaidTokenType.COLON)) {
                error_at_current("Expected ':' after pie slice label");
            }

            // Get value (number)
            if (!check(MermaidTokenType.NUMBER)) {
                error_at_current("Expected number value for pie slice");
            }

            string value_str = advance().lexeme;
            double value = double.parse(value_str);

            var slice = new PieSlice(label, value, previous().line);
            diagram.add_slice(slice);
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) {
                    return;
                }
                advance();
            }
        }

        private bool match(MermaidTokenType type) {
            if (check(type)) {
                advance();
                return true;
            }
            return false;
        }

        private bool check(MermaidTokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        private MermaidToken advance() {
            if (!is_at_end()) {
                current++;
            }
            return previous();
        }

        private bool is_at_end() {
            return peek().token_type == MermaidTokenType.EOF;
        }

        private MermaidToken peek() {
            return tokens.get(current);
        }

        private MermaidToken previous() {
            return tokens.get(current - 1);
        }

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            string context = "";
            if (token.lexeme.length > 0) {
                context = " (found: '%s')".printf(token.lexeme);
            }
            throw new GLib.IOError.FAILED("Line %d: %s%s", token.line, message, context);
        }
    }
}
