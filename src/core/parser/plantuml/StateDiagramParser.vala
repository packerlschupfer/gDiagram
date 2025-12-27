namespace GDiagram {
    public class StateDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private StateDiagram diagram;

        public StateDiagramParser() {
            this.current = 0;
        }

        public StateDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new StateDiagram();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_diagram() throws Error {
            skip_newlines();

            // Skip @startuml and any diagram name after it
            if (match(TokenType.STARTUML)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                skip_newlines();
            }

            // Parse statements until @enduml
            while (!check(TokenType.ENDUML) && !is_at_end()) {
                try {
                    parse_statement();
                } catch (Error e) {
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

        private void parse_statement() throws Error {
            skip_newlines();

            if (is_at_end() || check(TokenType.ENDUML)) {
                return;
            }

            // Skip comments
            if (match(TokenType.COMMENT)) {
                return;
            }

            // Hide directive
            if (match(TokenType.HIDE)) {
                // hide empty description
                string rest = consume_rest_of_line().down();
                if (rest.contains("empty") && rest.contains("description")) {
                    diagram.hide_empty_description = true;
                }
                return;
            }

            // State declaration
            if (check(TokenType.STATE)) {
                parse_state_declaration();
                return;
            }

            // [*] - Initial or final state
            if (check(TokenType.INITIAL_FINAL)) {
                parse_initial_final_transition();
                return;
            }

            // [H] or [H*] - History states
            if (check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) {
                parse_history_transition();
                return;
            }

            // Title
            if (match(TokenType.TITLE)) {
                diagram.title = consume_rest_of_line();
                return;
            }

            // Header
            if (match(TokenType.HEADER)) {
                diagram.header = consume_rest_of_line();
                return;
            }

            // Footer
            if (match(TokenType.FOOTER)) {
                diagram.footer = consume_rest_of_line();
                return;
            }

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Transition: State1 --> State2 : label
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_transition_or_state();
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        private void parse_state_declaration() throws Error {
            int line = advance().line;  // consume "state"

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected state name");
            }

            var state = diagram.get_or_create_state(name, line);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    string alias = advance().lexeme;
                    state.label = name;
                    state.id = alias;
                }
            }

            // Check for stereotype <<choice>>, <<fork>>, <<join>>, <<end>>
            if (match(TokenType.STEREOTYPE)) {
                string stereo = previous().lexeme.down();
                state.stereotype = stereo;
                switch (stereo) {
                    case "choice":
                        state.state_type = StateType.CHOICE;
                        break;
                    case "fork":
                        state.state_type = StateType.FORK;
                        break;
                    case "join":
                        state.state_type = StateType.JOIN;
                        break;
                    case "end":
                        state.state_type = StateType.END_STATE;
                        break;
                    case "entrypoint":
                        state.state_type = StateType.ENTRY_POINT;
                        break;
                    case "exitpoint":
                        state.state_type = StateType.EXIT_POINT;
                        break;
                    default:
                        // Unknown stereotype - keep as annotation
                        break;
                }
            }

            // Check for color
            if (match(TokenType.HASH)) {
                state.color = "#" + collect_color();
            }

            // Check for state body with nested states
            if (match(TokenType.LBRACE)) {
                parse_state_body(state);
            }

            // Check for description after colon
            if (match(TokenType.COLON)) {
                string desc = consume_rest_of_line();
                parse_state_description(state, desc);
            }

            expect_end_of_statement();
        }

        // Parse state description which may include entry/exit actions
        private void parse_state_description(State state, string desc) {
            string lower = desc.down();
            if (lower.has_prefix("entry /") || lower.has_prefix("entry/")) {
                int slash_pos = desc.index_of("/");
                if (slash_pos >= 0) {
                    state.entry_action = desc.substring(slash_pos + 1).strip();
                }
            } else if (lower.has_prefix("exit /") || lower.has_prefix("exit/")) {
                int slash_pos = desc.index_of("/");
                if (slash_pos >= 0) {
                    state.exit_action = desc.substring(slash_pos + 1).strip();
                }
            } else {
                state.description = desc;
            }
        }

        private void parse_state_body(State parent) throws Error {
            parent.state_type = StateType.COMPOSITE;
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                // Nested state
                if (check(TokenType.STATE)) {
                    advance();
                    string name;
                    if (check(TokenType.STRING)) {
                        name = advance().lexeme;
                    } else if (check(TokenType.IDENTIFIER)) {
                        name = advance().lexeme;
                    } else {
                        advance();
                        continue;
                    }

                    var nested = new State(name);

                    // Check for alias
                    if (match(TokenType.AS)) {
                        if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                            string alias = advance().lexeme;
                            nested.label = name;
                            nested.id = alias;
                        }
                    }

                    // Nested state body
                    if (match(TokenType.LBRACE)) {
                        parse_state_body(nested);
                    }

                    // Description
                    if (match(TokenType.COLON)) {
                        nested.description = consume_rest_of_line();
                    }

                    parent.nested_states.add(nested);
                }
                // [*] inside composite state
                else if (check(TokenType.INITIAL_FINAL)) {
                    parse_nested_initial_final(parent);
                }
                // Transition inside composite state
                else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    parse_nested_transition(parent);
                }
                else {
                    advance();
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private void parse_initial_final_transition() throws Error {
            advance();  // consume [*]

            // Check for arrow
            bool is_dashed = false;
            bool has_arrow = false;

            if (match(TokenType.ARROW_RIGHT)) {
                has_arrow = true;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                has_arrow = true;
                is_dashed = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                // -- could be followed by >
                if (match(TokenType.IDENTIFIER) && previous().lexeme == ">") {
                    has_arrow = true;
                }
            }

            if (!has_arrow) {
                expect_end_of_statement();
                return;
            }

            // Get target state
            string to_name;
            if (check(TokenType.INITIAL_FINAL)) {
                // [*] --> [*] (shouldn't happen but handle it)
                advance();
                to_name = "_final_0";
            } else if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                expect_end_of_statement();
                return;
            }

            // Create initial state and transition
            var initial = State.create_initial();
            diagram.states.add(initial);

            var target = diagram.get_or_create_state(to_name);

            var transition = new StateTransition(initial, target);
            transition.is_dashed = is_dashed;

            // Check for label with guard and action parsing
            if (match(TokenType.COLON)) {
                string label_text = consume_rest_of_line();
                parse_transition_label(transition, label_text);
            }

            diagram.transitions.add(transition);
            expect_end_of_statement();
        }

        private void parse_history_transition() throws Error {
            bool deep = check(TokenType.DEEP_HISTORY);
            advance();  // consume [H] or [H*]

            // Check for arrow
            bool is_dashed = false;
            bool has_arrow = false;

            if (match(TokenType.ARROW_RIGHT)) {
                has_arrow = true;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                has_arrow = true;
                is_dashed = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                has_arrow = true;
                is_dashed = true;
            }

            if (!has_arrow) {
                // Just a history state declaration
                var history = State.create_history(deep);
                diagram.states.add(history);
                expect_end_of_statement();
                return;
            }

            // Get target state
            string to_name;
            if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                expect_end_of_statement();
                return;
            }

            // Create history state and transition
            var history = State.create_history(deep);
            diagram.states.add(history);

            var target = diagram.get_or_create_state(to_name);

            var transition = new StateTransition(history, target);
            transition.is_dashed = is_dashed;

            // Check for label with guard and action parsing
            if (match(TokenType.COLON)) {
                string label_text = consume_rest_of_line();
                parse_transition_label(transition, label_text);
            }

            diagram.transitions.add(transition);
            expect_end_of_statement();
        }

        private void parse_transition_or_state() throws Error {
            string from_name;
            if (check(TokenType.STRING)) {
                from_name = advance().lexeme;
            } else {
                from_name = advance().lexeme;
            }

            // Check for description (State : description)
            if (match(TokenType.COLON)) {
                var state = diagram.get_or_create_state(from_name);
                state.description = consume_rest_of_line();
                return;
            }

            // Check for arrow
            bool is_dashed = false;
            bool has_arrow = false;
            bool to_final = false;

            if (match(TokenType.ARROW_RIGHT)) {
                has_arrow = true;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                has_arrow = true;
                is_dashed = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                has_arrow = true;
                is_dashed = true;
                // Check for > after --
                if (check(TokenType.IDENTIFIER) && peek().lexeme == ">") {
                    advance();
                    is_dashed = false;
                }
            }

            if (!has_arrow) {
                // Just a state reference
                diagram.get_or_create_state(from_name);
                expect_end_of_statement();
                return;
            }

            // Get target state
            string to_name;
            if (check(TokenType.INITIAL_FINAL)) {
                // Transition to final state
                advance();
                to_final = true;
                var final_state = State.create_final();
                diagram.states.add(final_state);
                to_name = final_state.id;
            } else if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                expect_end_of_statement();
                return;
            }

            var from_state = diagram.get_or_create_state(from_name);
            State to_state;
            if (to_final) {
                to_state = diagram.find_state(to_name);
            } else {
                to_state = diagram.get_or_create_state(to_name);
            }

            var transition = new StateTransition(from_state, to_state);
            transition.is_dashed = is_dashed;

            // Check for label with guard and action parsing
            if (match(TokenType.COLON)) {
                string label_text = consume_rest_of_line();
                parse_transition_label(transition, label_text);
            }

            diagram.transitions.add(transition);
            expect_end_of_statement();
        }

        private void parse_nested_initial_final(State parent) throws Error {
            advance();  // consume [*]

            // Check for arrow
            bool has_arrow = false;
            bool is_dashed = false;

            if (match(TokenType.ARROW_RIGHT)) {
                has_arrow = true;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                has_arrow = true;
                is_dashed = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                has_arrow = true;
                is_dashed = true;
            }

            if (!has_arrow) {
                return;
            }

            // Get target
            string to_name;
            if (check(TokenType.INITIAL_FINAL)) {
                advance();
                var final_state = State.create_final();
                parent.nested_states.add(final_state);
                to_name = final_state.id;
            } else if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                return;
            }

            // Create initial state for this composite
            var initial = State.create_initial();
            parent.nested_states.add(initial);

            // Find or create target in nested states
            State? target = null;
            foreach (var ns in parent.nested_states) {
                if (ns.id == to_name) {
                    target = ns;
                    break;
                }
            }
            if (target == null) {
                target = new State(to_name);
                parent.nested_states.add(target);
            }

            var transition = new StateTransition(initial, target);
            transition.is_dashed = is_dashed;

            if (match(TokenType.COLON)) {
                string label_text = consume_rest_of_line();
                parse_transition_label(transition, label_text);
            }

            parent.nested_transitions.add(transition);
        }

        private void parse_nested_transition(State parent) throws Error {
            string from_name;
            if (check(TokenType.STRING)) {
                from_name = advance().lexeme;
            } else {
                from_name = advance().lexeme;
            }

            // Check for arrow
            bool has_arrow = false;
            bool is_dashed = false;

            if (match(TokenType.ARROW_RIGHT)) {
                has_arrow = true;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                has_arrow = true;
                is_dashed = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                has_arrow = true;
                is_dashed = true;
            }

            if (!has_arrow) {
                return;
            }

            // Get target
            string to_name;
            if (check(TokenType.INITIAL_FINAL)) {
                advance();
                var final_state = State.create_final();
                parent.nested_states.add(final_state);
                to_name = final_state.id;
            } else if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                return;
            }

            // Find or create states in parent's nested states
            State? from_state = null;
            State? to_state = null;

            foreach (var ns in parent.nested_states) {
                if (ns.id == from_name) from_state = ns;
                if (ns.id == to_name) to_state = ns;
            }

            if (from_state == null) {
                from_state = new State(from_name);
                parent.nested_states.add(from_state);
            }
            if (to_state == null) {
                to_state = new State(to_name);
                parent.nested_states.add(to_state);
            }

            var transition = new StateTransition(from_state, to_state);
            transition.is_dashed = is_dashed;

            if (match(TokenType.COLON)) {
                string label_text = consume_rest_of_line();
                parse_transition_label(transition, label_text);
            }

            parent.nested_transitions.add(transition);
        }

        private void parse_note() throws Error {
            advance();  // consume "note"

            string position = "right";
            if (match(TokenType.LEFT)) {
                position = "left";
            } else if (match(TokenType.RIGHT)) {
                position = "right";
            } else if (match(TokenType.TOP)) {
                position = "top";
            } else if (match(TokenType.BOTTOM)) {
                position = "bottom";
            }

            string? attached_to = null;

            // "of State" or just continue
            if (match(TokenType.OF)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            // Note text - can be single line or multi-line (end note)
            var sb = new StringBuilder();

            if (match(TokenType.COLON)) {
                // Single line note
                sb.append(consume_rest_of_line());
            } else {
                skip_newlines();
                // Multi-line note until "end note"
                while (!is_at_end()) {
                    if (check(TokenType.END)) {
                        advance();
                        // Check for "note" after "end"
                        if (check(TokenType.NOTE)) {
                            advance();
                            break;
                        }
                    }
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) sb.append("\n");
                        advance();
                    } else {
                        sb.append(advance().lexeme);
                        sb.append(" ");
                    }
                }
            }

            var note = new StateNote(sb.str.strip());
            note.attached_to = attached_to;
            note.position = position;
            diagram.notes.add(note);
        }

        private string collect_color() {
            var sb = new StringBuilder();
            while (check(TokenType.IDENTIFIER) || check(TokenType.HASH)) {
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        private void parse_skinparam() throws Error {
            string first_name = "";
            if (check(TokenType.IDENTIFIER) || check(TokenType.STATE)) {
                first_name = advance().lexeme;
            } else {
                skip_to_end_of_line();
                return;
            }

            if (match(TokenType.LBRACE)) {
                parse_skinparam_block(first_name);
            } else {
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }
        }

        private void parse_skinparam_block(string element) throws Error {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                if (!check(TokenType.IDENTIFIER)) {
                    advance();
                    continue;
                }

                string property = advance().lexeme;
                string value = collect_skinparam_value();

                if (value.length > 0) {
                    diagram.skin_params.set_element_property(element, property, value);
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private string collect_skinparam_value() {
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                if (t.lexeme == "#") {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            return sb.str.strip();
        }

        private void skip_to_end_of_line() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private string consume_rest_of_line() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        // Parse transition label to extract event, guard, and action
        // Format: event [guard] / action
        private void parse_transition_label(StateTransition transition, string label) {
            string text = label.strip();
            if (text.length == 0) {
                return;
            }

            // Extract guard: text between [ and ]
            int guard_start = text.index_of("[");
            int guard_end = text.index_of("]");
            if (guard_start >= 0 && guard_end > guard_start) {
                transition.guard = text.substring(guard_start + 1, guard_end - guard_start - 1).strip();
                // Remove guard from text
                text = text.substring(0, guard_start) + text.substring(guard_end + 1);
                text = text.strip();
            }

            // Extract action: text after /
            int action_pos = text.index_of("/");
            if (action_pos >= 0) {
                transition.action = text.substring(action_pos + 1).strip();
                text = text.substring(0, action_pos).strip();
            }

            // Remaining text is the event/trigger
            if (text.length > 0) {
                transition.label = text;
            }
        }

        private void expect_end_of_statement() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == TokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case TokenType.STATE:
                    case TokenType.INITIAL_FINAL:
                    case TokenType.NOTE:
                    case TokenType.ENDUML:
                        return;
                    default:
                        advance();
                        break;
                }
            }
        }

        private void skip_newlines() {
            while (match(TokenType.NEWLINE) || match(TokenType.COMMENT)) {
                // keep skipping
            }
        }

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
