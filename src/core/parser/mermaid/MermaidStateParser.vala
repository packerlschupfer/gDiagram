namespace GDiagram {
    public class MermaidStateParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidStateDiagram diagram;

        public MermaidStateParser() {
            this.current = 0;
        }

        public MermaidStateDiagram parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidStateDiagram();

            try {
                parse_state_diagram();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_state_diagram() throws GLib.Error {
            skip_newlines();

            // Expect stateDiagram-v2 keyword
            if (!match(MermaidTokenType.STATE_DIAGRAM)) {
                error_at_current("Expected 'stateDiagram-v2'");
            }

            skip_newlines();

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

            // State declaration
            if (check(MermaidTokenType.STATE)) {
                parse_state_declaration();
                return;
            }

            // Initial state marker [*]
            if (check(MermaidTokenType.INITIAL)) {
                parse_transition();
                return;
            }

            // Regular state or transition
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_state_or_transition();
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

        private void parse_state_declaration() throws GLib.Error {
            advance(); // consume 'state'

            if (!check(MermaidTokenType.IDENTIFIER) && !check(MermaidTokenType.STRING)) {
                error_at_current("Expected state identifier");
            }

            string id = advance().lexeme;
            var state = diagram.get_or_create_state(id);

            // Check for 'as Description'
            if (match(MermaidTokenType.AS)) {
                var desc_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (desc_parts.len > 0) {
                        desc_parts.append(" ");
                    }
                    desc_parts.append(advance().lexeme);
                }
                state.description = desc_parts.str.strip();
            }

            // Check for stereotypes like <<choice>>, <<fork>>, <<join>>
            if (check(MermaidTokenType.CHOICE)) {
                state.state_type = MermaidStateType.CHOICE;
                advance();
            } else if (check(MermaidTokenType.FORK_KW)) {
                state.state_type = MermaidStateType.FORK;
                advance();
            } else if (check(MermaidTokenType.JOIN)) {
                state.state_type = MermaidStateType.JOIN;
                advance();
            }
        }

        private void parse_state_or_transition() throws GLib.Error {
            string first_id = advance().lexeme;
            skip_whitespace_same_line();

            // Check for transition arrow
            if (is_transition_arrow()) {
                // It's a transition
                parse_transition_from(first_id);
            } else if (match(MermaidTokenType.COLON)) {
                // It's a state with description: StateId: Description
                var state = diagram.get_or_create_state(first_id);
                var desc_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (desc_parts.len > 0) {
                        desc_parts.append(" ");
                    }
                    desc_parts.append(advance().lexeme);
                }
                state.description = desc_parts.str.strip();
            } else {
                // Just a state reference
                diagram.get_or_create_state(first_id);
            }
        }

        private void parse_transition() throws GLib.Error {
            // Handle [*] --> State transitions
            string from_id = "[*]";

            if (check(MermaidTokenType.INITIAL)) {
                advance(); // consume [*]
            } else {
                error_at_current("Expected [*] or state identifier");
            }

            skip_whitespace_same_line();

            if (!is_transition_arrow()) {
                error_at_current("Expected transition arrow");
            }

            parse_transition_from(from_id);
        }

        private void parse_transition_from(string from_id) throws GLib.Error {
            // Create or get 'from' state
            MermaidState from_state;
            if (from_id == "[*]") {
                from_state = new MermaidState("[*]_start", MermaidStateType.START);
                if (diagram.start_state == null) {
                    diagram.start_state = from_state;
                    diagram.add_state(from_state);
                } else {
                    from_state = diagram.start_state;
                }
            } else {
                from_state = diagram.get_or_create_state(from_id);
            }

            // Consume arrow (should be --> or similar)
            advance_arrow();

            skip_whitespace_same_line();

            // Get 'to' state
            MermaidState to_state;
            if (check(MermaidTokenType.INITIAL)) {
                advance(); // consume [*]
                to_state = new MermaidState("[*]_end", MermaidStateType.END);
                if (diagram.end_state == null) {
                    diagram.end_state = to_state;
                    diagram.add_state(to_state);
                } else {
                    to_state = diagram.end_state;
                }
            } else if (check(MermaidTokenType.IDENTIFIER)) {
                string to_id = advance().lexeme;
                to_state = diagram.get_or_create_state(to_id);
            } else {
                error_at_current("Expected state identifier or [*]");
                return;
            }

            var transition = new MermaidTransition(from_state, to_state);

            // Check for transition label after colon
            if (match(MermaidTokenType.COLON)) {
                var label_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (label_parts.len > 0) {
                        label_parts.append(" ");
                    }
                    label_parts.append(advance().lexeme);
                }
                transition.label = label_parts.str.strip();
            }

            diagram.transitions.add(transition);
        }

        private bool is_transition_arrow() {
            return check(MermaidTokenType.ARROW_SOLID) ||
                   check(MermaidTokenType.LINE_SOLID) ||
                   check(MermaidTokenType.SEQ_SOLID_ARROW);
        }

        private void advance_arrow() {
            if (is_transition_arrow()) {
                advance();
            }
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        private void skip_whitespace_same_line() {
            // No-op since lexer handles whitespace
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case MermaidTokenType.STATE:
                    case MermaidTokenType.INITIAL:
                        return;
                    default:
                        advance();
                        break;
                }
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
            throw new GLib.IOError.FAILED("Line %d: %s", token.line, message);
        }
    }
}
