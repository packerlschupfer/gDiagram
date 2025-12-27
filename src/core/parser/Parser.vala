namespace GPlantUML {
    public class Parser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private SequenceDiagram diagram;
        private Gee.ArrayList<SequenceFrame> frame_stack;  // Stack for nested frames
        private int event_counter;  // Track event ordering

        public Parser() {
            this.current = 0;
            this.frame_stack = new Gee.ArrayList<SequenceFrame>();
            this.event_counter = 0;
        }

        public SequenceDiagram parse(string source) {
            var lexer = new Lexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new SequenceDiagram();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_diagram() throws Error {
            skip_newlines();

            // Expect @startuml
            if (!match(TokenType.STARTUML)) {
                error_at_current("Expected @startuml");
            }

            skip_newlines();

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

            // Expect @enduml
            if (!match(TokenType.ENDUML)) {
                error_at_current("Expected @enduml");
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

            // Title, header, footer
            if (check(TokenType.TITLE)) {
                parse_title();
                return;
            }
            if (check(TokenType.HEADER)) {
                parse_header();
                return;
            }
            if (check(TokenType.FOOTER)) {
                parse_footer();
                return;
            }

            // Participant declarations
            if (check(TokenType.PARTICIPANT) ||
                check(TokenType.ACTOR) ||
                check(TokenType.BOUNDARY) ||
                check(TokenType.CONTROL) ||
                check(TokenType.ENTITY) ||
                check(TokenType.DATABASE) ||
                check(TokenType.COLLECTIONS) ||
                check(TokenType.QUEUE)) {
                parse_participant_declaration();
                return;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Activation commands
            if (check(TokenType.ACTIVATE)) {
                parse_activate();
                return;
            }
            if (check(TokenType.DEACTIVATE)) {
                parse_deactivate();
                return;
            }
            if (check(TokenType.DESTROY)) {
                parse_destroy();
                return;
            }

            // Return statement
            if (check(TokenType.RETURN)) {
                parse_return();
                return;
            }

            // Grouping frame keywords
            if (check(TokenType.ALT) || check(TokenType.OPT) ||
                check(TokenType.LOOP) || check(TokenType.PAR) ||
                check(TokenType.BREAK) || check(TokenType.CRITICAL) ||
                check(TokenType.GROUP) || check(TokenType.REF)) {
                parse_frame_start();
                return;
            }

            // Else section within alt
            if (check(TokenType.ELSE)) {
                parse_else_section();
                return;
            }

            // End frame
            if (check(TokenType.END)) {
                parse_frame_end();
                return;
            }

            // Message (identifier followed by arrow)
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_message();
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        private void parse_title() throws Error {
            advance(); // consume 'title'
            string title_text = consume_rest_of_line().strip();
            if (title_text.length > 0) {
                diagram.title = title_text;
            }
        }

        private void parse_header() throws Error {
            advance(); // consume 'header'
            string header_text = consume_rest_of_line().strip();
            if (header_text.length > 0) {
                diagram.header = header_text;
            }
        }

        private void parse_footer() throws Error {
            advance(); // consume 'footer'
            string footer_text = consume_rest_of_line().strip();
            if (footer_text.length > 0) {
                diagram.footer = footer_text;
            }
        }

        private void parse_activate() throws Error {
            advance(); // consume 'activate'
            if (check(TokenType.IDENTIFIER)) {
                string name = advance().lexeme;
                var participant = diagram.get_or_create_participant(name);
                var activation = new Activation(participant, ActivationType.ACTIVATE);
                diagram.add_activation(activation);
            }
            expect_end_of_statement();
        }

        private void parse_deactivate() throws Error {
            advance(); // consume 'deactivate'
            if (check(TokenType.IDENTIFIER)) {
                string name = advance().lexeme;
                var participant = diagram.find_participant(name);
                if (participant != null) {
                    var activation = new Activation(participant, ActivationType.DEACTIVATE);
                    diagram.add_activation(activation);
                }
            }
            expect_end_of_statement();
        }

        private void parse_destroy() throws Error {
            advance(); // consume 'destroy'
            if (check(TokenType.IDENTIFIER)) {
                string name = advance().lexeme;
                var participant = diagram.find_participant(name);
                if (participant != null) {
                    var activation = new Activation(participant, ActivationType.DESTROY);
                    diagram.add_activation(activation);
                }
            }
            expect_end_of_statement();
        }

        private void parse_return() throws Error {
            advance(); // consume 'return'
            // Just consume the rest of the line for now
            consume_rest_of_line();
        }

        private SequenceFrameType token_to_frame_type(TokenType tt) {
            switch (tt) {
                case TokenType.ALT: return SequenceFrameType.ALT;
                case TokenType.OPT: return SequenceFrameType.OPT;
                case TokenType.LOOP: return SequenceFrameType.LOOP;
                case TokenType.PAR: return SequenceFrameType.PAR;
                case TokenType.BREAK: return SequenceFrameType.BREAK;
                case TokenType.CRITICAL: return SequenceFrameType.CRITICAL;
                case TokenType.REF: return SequenceFrameType.REF;
                default: return SequenceFrameType.GROUP;
            }
        }

        private void parse_frame_start() throws Error {
            Token frame_token = advance();  // consume frame keyword
            int line_num = frame_token.line;
            SequenceFrameType frame_type = token_to_frame_type(frame_token.token_type);

            var frame = new SequenceFrame(frame_type, line_num);
            frame.start_order = event_counter++;

            // Parse optional label/condition
            string label_text = consume_rest_of_line().strip();
            if (label_text.length > 0) {
                // For alt, the text is typically a condition like [x > 0]
                if (frame_type == SequenceFrameType.ALT) {
                    frame.condition = label_text;
                } else {
                    frame.label = label_text;
                }
            }

            // Set parent if nested
            if (frame_stack.size > 0) {
                frame.parent = frame_stack.get(frame_stack.size - 1);
            }

            // Push onto stack
            frame_stack.add(frame);

            // Add frame to diagram
            diagram.frames.add(frame);

            // Add FrameEvent for start
            diagram.events.add(new FrameEvent(frame, true, frame.start_order));
        }

        private void parse_else_section() throws Error {
            Token else_token = advance();  // consume 'else'
            int line_num = else_token.line;

            // Else must be within an alt frame
            if (frame_stack.size == 0) {
                diagram.errors.add(new ParseError("'else' without matching 'alt'", line_num, 1));
                consume_rest_of_line();
                return;
            }

            var parent_frame = frame_stack.get(frame_stack.size - 1);
            if (parent_frame.frame_type != SequenceFrameType.ALT) {
                diagram.errors.add(new ParseError("'else' can only appear within 'alt' frame", line_num, 1));
                consume_rest_of_line();
                return;
            }

            // Create else section
            var else_frame = new SequenceFrame(SequenceFrameType.ELSE, line_num);
            else_frame.start_order = event_counter++;
            else_frame.parent = parent_frame;

            // Parse optional condition (for elseif-like behavior)
            string condition = consume_rest_of_line().strip();
            if (condition.length > 0) {
                else_frame.condition = condition;
            }

            // Add to parent's sections
            parent_frame.sections.add(else_frame);

            // Add FrameEvent for else section
            diagram.events.add(new FrameEvent(else_frame, true, else_frame.start_order));
        }

        private void parse_frame_end() throws Error {
            Token end_token = advance();  // consume 'end'
            int line_num = end_token.line;

            if (frame_stack.size == 0) {
                diagram.errors.add(new ParseError("'end' without matching frame", line_num, 1));
                return;
            }

            // Pop the current frame
            var frame = frame_stack.remove_at(frame_stack.size - 1);
            frame.end_order = event_counter++;

            // Add FrameEvent for end
            diagram.events.add(new FrameEvent(frame, false, frame.end_order));

            // Close any else sections
            foreach (var section in frame.sections) {
                section.end_order = frame.end_order;
            }
        }

        private void parse_participant_declaration() throws Error {
            Token type_token = advance();
            int line = type_token.line;  // Capture line number
            ParticipantType ptype = token_to_participant_type(type_token.token_type);

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected participant name");
            }

            var participant = new Participant(name, ptype, line);

            // Check for multi-line label with [ ... ]
            if (match(TokenType.LBRACKET)) {
                var lines = new Gee.ArrayList<string>();
                var current_line = new StringBuilder();

                while (!check(TokenType.RBRACKET) && !is_at_end()) {
                    if (check(TokenType.NEWLINE)) {
                        if (current_line.len > 0) {
                            lines.add(current_line.str.strip());
                            current_line = new StringBuilder();
                        }
                        advance();
                        continue;
                    }

                    Token t = advance();

                    // Handle =Title syntax (skip the =)
                    if (t.lexeme == "=") {
                        continue;
                    }

                    // Handle ---- separator (any number of dashes >= 2)
                    if (t.token_type == TokenType.MINUS || t.lexeme == "-" ||
                        t.lexeme.has_prefix("-")) {
                        int dash_count = t.lexeme.length;  // Count dashes in current token

                        // Consume all consecutive dash tokens
                        while (check(TokenType.MINUS) ||
                               (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("-"))) {
                            Token next = advance();
                            dash_count += next.lexeme.length;
                        }

                        // If we have 2+ dashes, it's a separator
                        if (dash_count >= 2) {
                            if (current_line.len > 0) {
                                lines.add(current_line.str.strip());
                                current_line = new StringBuilder();
                            }
                            lines.add("SEPARATOR");  // Add separator marker
                            continue;
                        }

                        // Otherwise treat as regular text (single dash)
                        if (current_line.len > 0) {
                            current_line.append(" ");
                        }
                        current_line.append("-");
                        continue;
                    }

                    // Regular text - strip quotes from ""SubTitle""
                    string text = t.lexeme;
                    if (text.has_prefix("\"\"") && text.has_suffix("\"\"") && text.length > 4) {
                        text = text.substring(2, text.length - 4);
                    } else if (text.has_prefix("\"") && text.has_suffix("\"") && text.length > 2) {
                        text = text.substring(1, text.length - 2);
                    }

                    if (current_line.len > 0) {
                        current_line.append(" ");
                    }
                    current_line.append(text);
                }

                if (current_line.len > 0) {
                    lines.add(current_line.str.strip());
                }

                match(TokenType.RBRACKET);

                // Build multi-line label - DON'T include original name, just the bracket content
                var multi_sb = new StringBuilder();
                bool first = true;
                foreach (var label_line in lines) {
                    if (label_line == "SEPARATOR") {
                        // Use separator marker for HTML table row separation
                        multi_sb.append("║SEPARATOR║");
                    } else if (label_line.length > 0) {
                        if (!first) {
                            multi_sb.append("\\n");
                        }
                        multi_sb.append(label_line);
                        first = false;
                    }
                }
                // Store multi-line label for rendering, keep original name for lookup
                participant.display_label = multi_sb.str;
            }

            // Check for alias: "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER)) {
                    participant.alias = advance().lexeme;
                }
            }

            // Check for color at end of line: #color (comes as IDENTIFIER like "#red" or "#99FF99")
            if (!is_at_end() && check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#")) {
                string color_with_hash = advance().lexeme;
                string color_value = color_with_hash.substring(1);  // Remove the #

                // Only add # back for hex colors (6 or 3 chars), not for named colors
                if (is_hex_color(color_value) || color_value.length == 3) {
                    participant.color = color_with_hash;  // Keep #FF0000 or #99FF99
                } else {
                    participant.color = color_value;  // Use 'red' without #
                }
            }

            // Add if not already exists
            if (diagram.find_participant(name) == null) {
                diagram.participants.add(participant);
            }

            expect_end_of_statement();
        }

        private ParticipantType token_to_participant_type(TokenType tt) {
            switch (tt) {
                case TokenType.ACTOR: return ParticipantType.ACTOR;
                case TokenType.BOUNDARY: return ParticipantType.BOUNDARY;
                case TokenType.CONTROL: return ParticipantType.CONTROL;
                case TokenType.ENTITY: return ParticipantType.ENTITY;
                case TokenType.DATABASE: return ParticipantType.DATABASE;
                case TokenType.COLLECTIONS: return ParticipantType.COLLECTIONS;
                case TokenType.QUEUE: return ParticipantType.QUEUE;
                default: return ParticipantType.PARTICIPANT;
            }
        }

        private void parse_message() throws Error {
            // Get "from" participant
            string from_name;
            if (check(TokenType.STRING)) {
                from_name = advance().lexeme;
            } else {
                from_name = advance().lexeme;
            }

            var from = diagram.get_or_create_participant(from_name);

            // Get arrow
            ArrowStyle style;
            ArrowDirection direction;

            if (!parse_arrow(out style, out direction)) {
                // Not a message, might be something else
                return;
            }

            // Get "to" participant
            string to_name;
            if (check(TokenType.STRING)) {
                to_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                to_name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected target participant");
            }

            var to = diagram.get_or_create_participant(to_name);

            var message = new Message(from, to);
            message.style = style;
            message.direction = direction;

            // Optional label after colon
            if (match(TokenType.COLON)) {
                message.label = consume_message_label();
            }

            // Check for activation modifiers after the message
            if (match(TokenType.PLUS_PLUS)) {
                message.activate_target = true;
                // Also add an activation event for the target
                var activation = new Activation(to, ActivationType.ACTIVATE);
                diagram.add_activation(activation);
            } else if (match(TokenType.MINUS_MINUS)) {
                message.deactivate_source = true;
                // Also add a deactivation event for the source
                var deactivation = new Activation(from, ActivationType.DEACTIVATE);
                diagram.add_activation(deactivation);
            }

            diagram.add_message(message);
        }

        private bool parse_arrow(out ArrowStyle style, out ArrowDirection direction) {
            style = ArrowStyle.SOLID;
            direction = ArrowDirection.RIGHT;

            if (match(TokenType.ARROW_RIGHT)) {
                style = ArrowStyle.SOLID;
                direction = ArrowDirection.RIGHT;
                return true;
            }
            if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                style = ArrowStyle.DOTTED;
                direction = ArrowDirection.RIGHT;
                return true;
            }
            if (match(TokenType.ARROW_RIGHT_OPEN)) {
                style = ArrowStyle.SOLID_OPEN;
                direction = ArrowDirection.RIGHT;
                return true;
            }
            if (match(TokenType.ARROW_LEFT)) {
                style = ArrowStyle.SOLID;
                direction = ArrowDirection.LEFT;
                return true;
            }
            if (match(TokenType.ARROW_LEFT_DOTTED)) {
                style = ArrowStyle.DOTTED;
                direction = ArrowDirection.LEFT;
                return true;
            }
            if (match(TokenType.ARROW_LEFT_OPEN)) {
                style = ArrowStyle.SOLID_OPEN;
                direction = ArrowDirection.LEFT;
                return true;
            }
            if (match(TokenType.ARROW_BIDIRECTIONAL)) {
                style = ArrowStyle.SOLID;
                direction = ArrowDirection.BIDIRECTIONAL;
                return true;
            }

            return false;
        }

        private void parse_note() throws Error {
            advance(); // consume 'note'

            string position = "right";
            Participant? over_participant = null;

            if (match(TokenType.LEFT)) {
                position = "left";
                if (match(TokenType.OF)) {
                    if (check(TokenType.IDENTIFIER)) {
                        string name = advance().lexeme;
                        over_participant = diagram.find_participant(name);
                    }
                }
            } else if (match(TokenType.RIGHT)) {
                position = "right";
                if (match(TokenType.OF)) {
                    if (check(TokenType.IDENTIFIER)) {
                        string name = advance().lexeme;
                        over_participant = diagram.find_participant(name);
                    }
                }
            } else if (match(TokenType.OVER)) {
                position = "over";
                if (check(TokenType.IDENTIFIER)) {
                    string name = advance().lexeme;
                    over_participant = diagram.find_participant(name);
                }
            }

            // Get note text after colon
            string text = "";
            if (match(TokenType.COLON)) {
                text = consume_rest_of_line();
            }

            var note = new Note(text, position);
            note.participant = over_participant;
            diagram.add_note(note);
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

        private string consume_message_label() {
            var sb = new StringBuilder();

            // Consume until newline, ++, or --
            while (!check(TokenType.NEWLINE) &&
                   !check(TokenType.PLUS_PLUS) &&
                   !check(TokenType.MINUS_MINUS) &&
                   !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        private void expect_end_of_statement() {
            // Just skip to end of line
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private void synchronize() {
            // Skip to next line or known statement start
            while (!is_at_end()) {
                if (previous().token_type == TokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case TokenType.PARTICIPANT:
                    case TokenType.ACTOR:
                    case TokenType.BOUNDARY:
                    case TokenType.CONTROL:
                    case TokenType.ENTITY:
                    case TokenType.DATABASE:
                    case TokenType.COLLECTIONS:
                    case TokenType.QUEUE:
                    case TokenType.NOTE:
                    case TokenType.ACTIVATE:
                    case TokenType.DEACTIVATE:
                    case TokenType.DESTROY:
                    case TokenType.RETURN:
                    case TokenType.ALT:
                    case TokenType.OPT:
                    case TokenType.LOOP:
                    case TokenType.PAR:
                    case TokenType.BREAK:
                    case TokenType.CRITICAL:
                    case TokenType.GROUP:
                    case TokenType.REF:
                    case TokenType.ELSE:
                    case TokenType.END:
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

        private void error_at_current(string message) throws Error {
            var token = peek();
            throw new IOError.FAILED("Line %d: %s", token.line, message);
        }

        private bool is_hex_color(string str) {
            if (str.length != 6) return false;
            foreach (char c in str.to_utf8()) {
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                    return false;
                }
            }
            return true;
        }
    }
}
