namespace GDiagram {
    public class MermaidSequenceParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidSequenceDiagram diagram;

        public MermaidSequenceParser() {
            this.current = 0;
        }

        public MermaidSequenceDiagram parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidSequenceDiagram();

            try {
                parse_sequence_diagram();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_sequence_diagram() throws GLib.Error {
            skip_newlines();

            // Expect sequenceDiagram keyword
            if (!match(MermaidTokenType.SEQUENCE_DIAGRAM)) {
                error_at_current("Expected 'sequenceDiagram'");
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

            // Autonumber
            if (check(MermaidTokenType.AUTONUMBER)) {
                advance();
                diagram.autonumber = true;
                return;
            }

            // Participant/Actor declarations
            if (check(MermaidTokenType.PARTICIPANT) || check(MermaidTokenType.ACTOR)) {
                parse_participant();
                return;
            }

            // Activation
            if (check(MermaidTokenType.ACTIVATE)) {
                parse_activate();
                return;
            }

            // Deactivation
            if (check(MermaidTokenType.DEACTIVATE)) {
                parse_deactivate();
                return;
            }

            // Note
            if (check(MermaidTokenType.NOTE)) {
                parse_note();
                return;
            }

            // Loop blocks
            if (check(MermaidTokenType.LOOP) || check(MermaidTokenType.ALT) ||
                check(MermaidTokenType.OPT) || check(MermaidTokenType.PAR) ||
                check(MermaidTokenType.CRITICAL) || check(MermaidTokenType.BREAK) ||
                check(MermaidTokenType.RECT)) {
                parse_loop();
                return;
            }

            // End (closes loop blocks)
            if (check(MermaidTokenType.END)) {
                // Handled by loop parsing
                advance();
                return;
            }

            // Message (identifier followed by arrow)
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_message();
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

        private void parse_participant() throws GLib.Error {
            bool is_actor = check(MermaidTokenType.ACTOR);
            advance(); // consume 'participant' or 'actor'

            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected participant identifier");
            }

            string id = advance().lexeme;
            var actor = new MermaidActor(id, !is_actor);

            // Check for 'as Alias'
            if (match(MermaidTokenType.AS)) {
                var alias_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (alias_parts.len > 0) {
                        alias_parts.append(" ");
                    }
                    alias_parts.append(advance().lexeme);
                }
                actor.alias = alias_parts.str.strip();
            }

            diagram.add_actor(actor);
        }

        private void parse_activate() throws GLib.Error {
            advance(); // consume 'activate'

            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected actor identifier");
            }

            string id = advance().lexeme;
            var actor = diagram.get_or_create_actor(id);
            // Note: Activation is typically handled on messages with +/-
            // but explicit activate/deactivate is also supported
        }

        private void parse_deactivate() throws GLib.Error {
            advance(); // consume 'deactivate'

            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected actor identifier");
            }

            string id = advance().lexeme;
            var actor = diagram.get_or_create_actor(id);
            // Deactivation tracking
        }

        private void parse_note() throws GLib.Error {
            advance(); // consume 'Note'

            // Parse position: "over", "left of", "right of"
            MermaidActor? from_actor = null;
            MermaidActor? to_actor = null;
            bool is_right = true;

            if (match(MermaidTokenType.OVER)) {
                // Note over A or Note over A,B
                if (!check(MermaidTokenType.IDENTIFIER)) {
                    error_at_current("Expected actor identifier");
                }
                from_actor = diagram.get_or_create_actor(advance().lexeme);

                // Check for second actor
                if (match(MermaidTokenType.COMMA)) {
                    if (!check(MermaidTokenType.IDENTIFIER)) {
                        error_at_current("Expected second actor identifier");
                    }
                    to_actor = diagram.get_or_create_actor(advance().lexeme);
                }
            } else if (check(MermaidTokenType.LEFT_OF)) {
                advance(); // consume "left of"
                is_right = false;
                if (!check(MermaidTokenType.IDENTIFIER)) {
                    error_at_current("Expected actor identifier");
                }
                from_actor = diagram.get_or_create_actor(advance().lexeme);
            } else if (check(MermaidTokenType.RIGHT_OF)) {
                advance(); // consume "right of"
                is_right = true;
                if (!check(MermaidTokenType.IDENTIFIER)) {
                    error_at_current("Expected actor identifier");
                }
                from_actor = diagram.get_or_create_actor(advance().lexeme);
            }

            // Parse note text after colon
            string text = "";
            if (match(MermaidTokenType.COLON)) {
                var text_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (text_parts.len > 0) {
                        text_parts.append(" ");
                    }
                    text_parts.append(advance().lexeme);
                }
                text = text_parts.str.strip();
            }

            var note = new MermaidNote(text);
            note.over_actor = from_actor;
            note.from_actor = from_actor;
            note.to_actor = to_actor;
            note.is_right = is_right;

            diagram.notes.add(note);
        }

        private void parse_loop() throws GLib.Error {
            var loop_token = advance();
            MermaidLoopType loop_type = token_to_loop_type(loop_token.token_type);

            var loop = new MermaidLoop(loop_type);

            // Parse optional condition/label
            if (match(MermaidTokenType.COLON)) {
                var cond_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (cond_parts.len > 0) {
                        cond_parts.append(" ");
                    }
                    cond_parts.append(advance().lexeme);
                }
                loop.condition = cond_parts.str.strip();
            } else {
                // Consume rest of line as condition
                var cond_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (cond_parts.len > 0) {
                        cond_parts.append(" ");
                    }
                    cond_parts.append(advance().lexeme);
                }
                string cond = cond_parts.str.strip();
                if (cond.length > 0) {
                    loop.condition = cond;
                }
            }

            skip_newlines();

            // Parse loop contents until 'end'
            while (!check(MermaidTokenType.END) && !is_at_end()) {
                // For now, just consume statements
                // A full implementation would track messages/notes within the loop
                parse_statement();
                skip_newlines();
            }

            if (!match(MermaidTokenType.END)) {
                error_at_current("Expected 'end' to close loop");
            }

            diagram.loops.add(loop);
        }

        private MermaidLoopType token_to_loop_type(MermaidTokenType type) {
            switch (type) {
                case MermaidTokenType.LOOP:
                    return MermaidLoopType.LOOP;
                case MermaidTokenType.ALT:
                    return MermaidLoopType.ALT;
                case MermaidTokenType.OPT:
                    return MermaidLoopType.OPT;
                case MermaidTokenType.PAR:
                    return MermaidLoopType.PAR;
                case MermaidTokenType.CRITICAL:
                    return MermaidLoopType.CRITICAL;
                case MermaidTokenType.BREAK:
                    return MermaidLoopType.BREAK;
                case MermaidTokenType.RECT:
                    return MermaidLoopType.RECT;
                default:
                    return MermaidLoopType.LOOP;
            }
        }

        private void parse_message() throws GLib.Error {
            // Get source actor
            string from_id = advance().lexeme;
            var from_actor = diagram.get_or_create_actor(from_id);

            skip_whitespace_same_line();

            // Parse arrow
            if (!is_arrow_token()) {
                error_at_current("Expected arrow after actor");
            }

            var arrow_token = advance();
            MermaidArrowType arrow_type = parse_arrow_type(arrow_token);

            skip_whitespace_same_line();

            // Get destination actor
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected destination actor");
            }

            string to_id = advance().lexeme;
            var to_actor = diagram.get_or_create_actor(to_id);

            var message = new MermaidMessage(from_actor, to_actor);
            message.arrow_type = arrow_type;

            // Parse message text after colon
            if (match(MermaidTokenType.COLON)) {
                var text_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (text_parts.len > 0) {
                        text_parts.append(" ");
                    }
                    text_parts.append(advance().lexeme);
                }
                message.text = text_parts.str.strip();
            }

            diagram.messages.add(message);
        }

        private MermaidArrowType parse_arrow_type(MermaidToken token) {
            // Map token types to arrow types based on lexeme
            string arrow = token.lexeme;

            if (arrow == "->" || arrow == "->>" ) {
                return MermaidArrowType.SOLID_ARROW;
            }
            if (arrow.contains("-->>") || arrow.contains("-->")) {
                return MermaidArrowType.DOTTED_ARROW;
            }
            if (arrow == "-" || arrow == "--") {
                return MermaidArrowType.SOLID_LINE;
            }
            if (arrow.contains("-.") || arrow.contains("..")) {
                return MermaidArrowType.DOTTED_LINE;
            }
            if (arrow.contains("-x")) {
                return MermaidArrowType.SOLID_CROSS;
            }
            if (arrow.contains("--x")) {
                return MermaidArrowType.DOTTED_CROSS;
            }
            if (arrow.contains("-)")) {
                return MermaidArrowType.SOLID_OPEN;
            }
            if (arrow.contains("--)")) {
                return MermaidArrowType.DOTTED_OPEN;
            }

            return MermaidArrowType.SOLID_ARROW;
        }

        private bool is_arrow_token() {
            return check(MermaidTokenType.ARROW_SOLID) ||
                   check(MermaidTokenType.ARROW_DOTTED) ||
                   check(MermaidTokenType.SEQ_SOLID_ARROW) ||
                   check(MermaidTokenType.SEQ_DOTTED_ARROW) ||
                   check(MermaidTokenType.SEQ_SOLID_LINE) ||
                   check(MermaidTokenType.SEQ_DOTTED_LINE) ||
                   check(MermaidTokenType.SEQ_SOLID_OPEN) ||
                   check(MermaidTokenType.SEQ_DOTTED_OPEN) ||
                   check(MermaidTokenType.SEQ_SOLID_CROSS) ||
                   check(MermaidTokenType.SEQ_DOTTED_CROSS) ||
                   check(MermaidTokenType.LINE_SOLID) ||
                   check(MermaidTokenType.LINE_DOTTED);
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        private void skip_whitespace_same_line() {
            // No-op since lexer already handles whitespace
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case MermaidTokenType.PARTICIPANT:
                    case MermaidTokenType.ACTOR:
                    case MermaidTokenType.NOTE:
                    case MermaidTokenType.LOOP:
                    case MermaidTokenType.ALT:
                    case MermaidTokenType.END:
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
