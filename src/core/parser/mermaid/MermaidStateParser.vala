namespace GDiagram {
    public class MermaidStateParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidStateDiagram diagram;
        private string? current_parent_id = null;  // set when parsing composite state block

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
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
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

            // direction directive: direction LR, direction TB, etc.
            if (check(MermaidTokenType.DIRECTION)) {
                advance(); // consume 'direction'
                if (check(MermaidTokenType.LR)) {
                    diagram.direction = FlowchartDirection.LEFT_RIGHT;
                    advance();
                } else if (check(MermaidTokenType.RL)) {
                    diagram.direction = FlowchartDirection.RIGHT_LEFT;
                    advance();
                } else if (check(MermaidTokenType.BT)) {
                    diagram.direction = FlowchartDirection.BOTTOM_UP;
                    advance();
                } else if (check(MermaidTokenType.TD) || check(MermaidTokenType.TB)) {
                    diagram.direction = FlowchartDirection.TOP_DOWN;
                    advance();
                }
                return;
            }

            // Skip note blocks and accessibility annotations
            if (check(MermaidTokenType.IDENTIFIER)) {
                string kw = peek().lexeme.down();
                if (kw == "acctitle" || kw == "accdescr") {
                    while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                        advance();
                    }
                    return;
                }
                // note right/left of State : text  (also handles multi-line 'note ... end note')
                if (kw == "note") {
                    advance(); // consume 'note'
                    // Consume until 'end note' or just the line for single-line notes
                    bool in_note_block = false;
                    while (!is_at_end()) {
                        if (check(MermaidTokenType.NEWLINE)) {
                            skip_newlines();
                            // Check for 'end note' (multi-line)
                            if (check(MermaidTokenType.IDENTIFIER) && peek().lexeme.down() == "end") {
                                advance(); // consume 'end'
                                if (check(MermaidTokenType.IDENTIFIER) && peek().lexeme.down() == "note") {
                                    advance(); // consume 'note'
                                }
                                break;
                            }
                            // If we were on the first line and it was a single-line note
                            // (had ':' on it), we already advanced past the colon content
                            if (!in_note_block) break;
                        } else if (check(MermaidTokenType.COLON)) {
                            // Single-line note: consume rest of line
                            in_note_block = false;
                            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                                advance();
                            }
                            break;
                        } else {
                            in_note_block = true;
                            advance();
                        }
                    }
                    return;
                }
            }

            // Regular state or transition
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_state_or_transition();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_title() {
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
            // The lexer emits two ASYMMETRIC_START tokens for << and >> respectively.
            if (check(MermaidTokenType.ASYMMETRIC_START) &&
                peek_at(1).token_type == MermaidTokenType.ASYMMETRIC_START) {
                advance(); advance(); // consume <<
                if (check(MermaidTokenType.IDENTIFIER)) {
                    string stereotype = advance().lexeme.down();
                    switch (stereotype) {
                        case "choice": state.state_type = MermaidStateType.CHOICE; break;
                        case "fork":   state.state_type = MermaidStateType.FORK;   break;
                        case "join":   state.state_type = MermaidStateType.JOIN;   break;
                        default: break;
                    }
                }
                // Consume >>
                if (check(MermaidTokenType.ASYMMETRIC_START)) advance();
                if (check(MermaidTokenType.ASYMMETRIC_START)) advance();
            }

            // Composite state: state "Name" as Id { ... }
            // Sub-states are added to the diagram with parent_id set to this state's id.
            if (check(MermaidTokenType.LBRACE)) {
                advance(); // consume '{'
                string? saved_parent = current_parent_id;
                current_parent_id = id;
                skip_newlines();
                while (!check(MermaidTokenType.RBRACE) && !is_at_end()) {
                    try {
                        parse_statement();
                    } catch (GLib.Error e) {
                        synchronize();
                    }
                    skip_newlines();
                }
                current_parent_id = saved_parent;
                if (check(MermaidTokenType.RBRACE)) {
                    advance(); // consume '}'
                }
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
                assign_parent_if_new(state);
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
                var state = diagram.get_or_create_state(first_id);
                assign_parent_if_new(state);
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
                assign_parent_if_new(from_state);
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
                assign_parent_if_new(to_state);
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

        // Set parent_id on a newly created state if we are inside a composite block
        // and the state has no parent yet (so already-defined states don't get re-parented).
        private void assign_parent_if_new(MermaidState state) {
            if (current_parent_id != null && state.parent_id == null && state.id != current_parent_id) {
                state.parent_id = current_parent_id;
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

        private MermaidToken peek_at(int offset) {
            int idx = current + offset;
            if (idx >= tokens.size) return tokens.get(tokens.size - 1); // EOF
            return tokens.get(idx);
        }

        private int error_line = 1;
        private int error_column = 1;

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            error_line = token.line;
            error_column = token.column;
            string context = "";
            if (token.lexeme.length > 0) {
                context = " (found: '%s')".printf(token.lexeme);
            }
            throw new GLib.IOError.FAILED("%s%s", message, context);
        }
    }
}
