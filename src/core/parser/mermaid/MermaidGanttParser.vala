namespace GDiagram {
    public class MermaidGanttParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidGantt diagram;
        private GanttSection? current_section;

        public MermaidGanttParser() {
            this.current = 0;
        }

        public MermaidGantt parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidGantt();
            this.current_section = null;

            try {
                parse_gantt();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_gantt() throws GLib.Error {
            skip_newlines();

            // Expect gantt keyword
            if (!match(MermaidTokenType.GANTT)) {
                error_at_current("Expected 'gantt'");
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

            // Section
            if (check(MermaidTokenType.IDENTIFIER)) {
                string first = peek().lexeme;
                if (first == "section") {
                    parse_section();
                    return;
                } else if (first == "dateFormat") {
                    parse_date_format();
                    return;
                }
            }

            // Task (starts with identifier or status keyword)
            parse_task();
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

        private void parse_section() throws GLib.Error {
            advance(); // consume 'section'
            var section_name = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (section_name.len > 0) {
                    section_name.append(" ");
                }
                section_name.append(advance().lexeme);
            }
            current_section = new GanttSection(section_name.str.strip());
            diagram.sections.add(current_section);
        }

        private void parse_date_format() throws GLib.Error {
            advance(); // consume 'dateFormat'
            var format_parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (format_parts.len > 0) {
                    format_parts.append(" ");
                }
                format_parts.append(advance().lexeme);
            }
            diagram.date_format = format_parts.str.strip();
        }

        private void parse_task() throws GLib.Error {
            // Task format: TaskName : status, start, duration
            // Or simplified: TaskName : duration
            var task_desc = new StringBuilder();

            // Collect task description up to colon
            while (!check(MermaidTokenType.COLON) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (task_desc.len > 0) {
                    task_desc.append(" ");
                }
                task_desc.append(advance().lexeme);
            }

            if (task_desc.len == 0) {
                // Not a task line, skip
                return;
            }

            string description = task_desc.str.strip();
            var task = new GanttTask(description, description, previous().line);

            // Parse task details after colon
            if (match(MermaidTokenType.COLON)) {
                parse_task_details(task);
            }

            // Add task to current section or diagram
            if (current_section != null) {
                current_section.add_task(task);
            }
            diagram.add_task(task);
        }

        private void parse_task_details(GanttTask task) throws GLib.Error {
            // Parse: status, start, duration
            // Simplified: just collect the info
            var details = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (details.len > 0) {
                    details.append(" ");
                }
                details.append(advance().lexeme);
            }

            string detail_str = details.str.strip();

            // Parse status keywords
            if (detail_str.contains("done")) {
                task.status = GanttTaskStatus.DONE;
            } else if (detail_str.contains("active")) {
                task.status = GanttTaskStatus.ACTIVE;
            } else if (detail_str.contains("crit")) {
                task.status = GanttTaskStatus.CRITICAL;
            }

            // Store duration/dates (simplified)
            task.duration = detail_str;
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
