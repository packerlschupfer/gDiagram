namespace GDiagram {
    public class MermaidUserJourneyParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidUserJourney diagram;
        private UserJourneySection? current_section;

        public MermaidUserJourneyParser() {
            this.current = 0;
        }

        public MermaidUserJourney parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidUserJourney();
            this.current_section = null;

            try {
                parse_journey();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
            }

            return diagram;
        }

        private void parse_journey() throws GLib.Error {
            skip_newlines();

            // Expect 'journey' keyword
            if (!match(MermaidTokenType.USER_JOURNEY)) {
                // Try accepting it as a generic identifier too
                if (check(MermaidTokenType.IDENTIFIER) && peek().lexeme == "journey") {
                    advance();
                } else {
                    error_at_current("Expected 'journey'");
                }
            }

            skip_newlines();

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

            // Section
            if (check(MermaidTokenType.IDENTIFIER) && peek().lexeme == "section") {
                parse_section();
                return;
            }

            // Skip accessibility annotations (accTitle, accDescr)
            if (check(MermaidTokenType.IDENTIFIER)) {
                string kw = peek().lexeme.down();
                if (kw == "acctitle" || kw == "accdescr") {
                    while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                        advance();
                    }
                    return;
                }
            }

            // Anything else on a non-empty line is a task
            if (!check(MermaidTokenType.NEWLINE)) {
                parse_task();
            }
        }

        private void parse_title() {
            advance(); // consume 'title'
            var parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (parts.len > 0) parts.append(" ");
                parts.append(advance().lexeme);
            }
            diagram.title = parts.str.strip();
        }

        private void parse_section() {
            advance(); // consume 'section'
            var parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (parts.len > 0) parts.append(" ");
                parts.append(advance().lexeme);
            }
            current_section = new UserJourneySection(parts.str.strip());
            diagram.sections.add(current_section);
        }

        // Task format: description: score
        //          or: description: score: actor1, actor2
        private void parse_task() {
            int line = peek().line;

            // Collect description up to first colon
            var desc_buf = new StringBuilder();
            while (!check(MermaidTokenType.COLON) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (desc_buf.len > 0) desc_buf.append(" ");
                desc_buf.append(advance().lexeme);
            }

            string description = desc_buf.str.strip();
            if (description.length == 0) {
                // Empty line — skip
                return;
            }

            // Score (after first colon)
            int score = 3; // default to neutral
            if (match(MermaidTokenType.COLON)) {
                // Skip whitespace-like tokens (spaces are usually subsumed by lexer)
                var score_buf = new StringBuilder();
                while (!check(MermaidTokenType.COLON) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    score_buf.append(advance().lexeme);
                }
                string score_str = score_buf.str.strip();
                if (score_str.length > 0 && int.try_parse(score_str, out score)) {
                    score = score.clamp(1, 5);
                } else {
                    score = 3;
                }
            }

            var task = new UserJourneyTask(description, score, line);

            // Actors (after second colon)
            if (match(MermaidTokenType.COLON)) {
                parse_actors(task);
            }

            // Consume rest of line
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                advance();
            }

            if (current_section != null) {
                current_section.add_task(task);
            }
            diagram.add_task(task);
        }

        private void parse_actors(UserJourneyTask task) {
            // Collect comma-separated actor names until newline
            var actor_buf = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                string lex = advance().lexeme;
                if (lex == ",") {
                    string actor = actor_buf.str.strip();
                    if (actor.length > 0) {
                        task.actors.add(actor);
                    }
                    actor_buf = new StringBuilder();
                } else {
                    if (actor_buf.len > 0) actor_buf.append(" ");
                    actor_buf.append(lex);
                }
            }
            string last_actor = actor_buf.str.strip();
            if (last_actor.length > 0) {
                task.actors.add(last_actor);
            }
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
            if (!is_at_end()) current++;
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

        private int error_line = 1;
        private int error_column = 1;

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            error_line = token.line;
            error_column = token.column;
            string context = token.lexeme.length > 0
                ? " (found: '%s')".printf(token.lexeme) : "";
            throw new GLib.IOError.FAILED("%s%s", message, context);
        }
    }
}
