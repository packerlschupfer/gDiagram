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
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
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
                parse_statement();
                skip_newlines();
            }
        }

        private void parse_statement() {
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

            // Section or meta-keywords
            if (check(MermaidTokenType.IDENTIFIER)) {
                string first = peek().lexeme;
                if (first == "section") {
                    parse_section();
                    return;
                } else if (first == "dateFormat") {
                    parse_date_format();
                    return;
                } else if (first.down() == "acctitle" || first.down() == "accdescr" ||
                           first == "axisFormat" || first == "excludes" ||
                           first == "todayMarker" || first == "tickInterval" ||
                           first == "weekday" || first == "inclusiveEndDates") {
                    // Meta-directives: skip the entire line
                    while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                        advance();
                    }
                    return;
                }
            }

            // Task (starts with identifier or status keyword)
            parse_task();
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

        private void parse_section() {
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

        private void parse_date_format() {
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

        private void parse_task() {
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

        private void parse_task_details(GanttTask task) {
            // Collect all tokens on the line
            var sb = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (sb.len > 0) sb.append(" ");
                sb.append(advance().lexeme);
            }

            string detail_str = sb.str.strip();
            if (detail_str.length == 0) return;

            // Split by comma into individual fields
            string[] parts = detail_str.split(",");

            bool id_seen = false;
            for (int i = 0; i < parts.length; i++) {
                string part = parts[i].strip();
                if (part.length == 0) continue;

                string lower = part.down();

                // Status keywords
                if (lower == "done") {
                    task.status = GanttTaskStatus.DONE;
                    continue;
                }
                if (lower == "active") {
                    task.status = GanttTaskStatus.ACTIVE;
                    continue;
                }
                if (lower == "crit") {
                    task.status = GanttTaskStatus.CRITICAL;
                    continue;
                }
                if (lower == "milestone") {
                    task.status = GanttTaskStatus.MILESTONE;
                    continue;
                }

                // Dependency: "after task_id"
                if (lower.has_prefix("after ")) {
                    task.depends_on = part.substring(6).strip();
                    continue;
                }

                // Duration: ends with d/h/m/s (e.g. "3d", "12h", "30m")
                if (part.length >= 2) {
                    char last = part[part.length - 1];
                    if ((last == 'd' || last == 'h' || last == 'm' || last == 's') &&
                        part.substring(0, part.length - 1).strip().length > 0) {
                        bool all_digits = true;
                        string num_part = part.substring(0, part.length - 1).strip();
                        foreach (char c in num_part.to_utf8()) {
                            if (!c.isdigit()) { all_digits = false; break; }
                        }
                        if (all_digits) {
                            task.duration = part;
                            continue;
                        }
                    }
                }

                // Date pattern: looks like YYYY-MM-DD or similar
                if (part.contains("-") && part.length >= 8) {
                    task.start_date = part;
                    continue;
                }

                // Otherwise treat as task identifier (first unrecognized field)
                if (!id_seen) {
                    task.id = part;
                    id_seen = true;
                }
            }

            // If no explicit ID was found, keep description-derived ID
            // Store full detail string as duration fallback
            if (task.duration == null || task.duration.length == 0) {
                task.duration = detail_str;
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
