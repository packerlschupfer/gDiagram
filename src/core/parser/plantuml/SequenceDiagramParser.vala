namespace GDiagram {
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

        // autonumber state, reset per parse (the engine reuses one parser). The number is
        // hierarchical ("autonumber 1.1.1"): the last level counts up by the step,
        // "autonumber inc A" steps the first level and resets the ones below it.
        private bool autonumber_on = false;
        private int[] autonumber_levels = { 1 };
        private int autonumber_step = 1;
        // PlantUML's DecimalFormat-like pattern: "0" a padded digit, "#" an optional one;
        // the rest is Creole/HTML text around the number. The default is a bold number.
        private string autonumber_format = DEFAULT_AUTONUMBER_FORMAT;
        private const string DEFAULT_AUTONUMBER_FORMAT = "<b>0</b>";
        // The last number given, for "%autonumber%" in notes
        private string? last_number = null;
        // "autoactivate on": a message activates its target, a dotted one deactivates its source
        private bool autoactivate = false;
        // "ignore newpage" anywhere in the file
        private bool ignore_newpage = false;
        // "{start} A -> B": the anchor for the message being parsed
        private string? pending_anchor = null;

        // The source split into lines: labels and titles are read from the line text after
        // their token, so text the lexer splits or drops ("a--b", "don't") stays whole
        private string[] source_lines = {};
        // Line of `source_lines` (0-based) each token starts on. Token.line cannot be used:
        // it stays at the !include line inside included text.
        private int[] token_rows = {};

        public SequenceDiagram parse(string source) {
            this.source_lines = source.split("\n");
            var lexer = new Lexer(source);
            this.tokens = lexer.scan_all();
            this.token_rows = new int[tokens.size];
            int row = 0;
            for (int i = 0; i < tokens.size; i++) {
                token_rows[i] = row;
                var tok = tokens.get(i);
                if (tok.token_type == TokenType.NEWLINE) {
                    row++;
                } else {
                    // block comments and style blocks span lines
                    unowned string lx = tok.lexeme;
                    for (int k = 0; k < lx.length; k++) {
                        if (lx[k] == '\n') {
                            row++;
                        }
                    }
                }
            }
            this.current = 0;
            this.diagram = new SequenceDiagram();
            this.autonumber_on = false;
            this.autonumber_levels = { 1 };
            this.autonumber_step = 1;
            this.autonumber_format = DEFAULT_AUTONUMBER_FORMAT;
            this.last_number = null;
            this.autoactivate = false;
            this.pending_anchor = null;
            this.ignore_newpage = false;
            foreach (string l in source_lines) {
                string t = l.strip().down();
                if (t.has_prefix("ignore") && t.substring(6).strip() == "newpage") {
                    this.ignore_newpage = true;
                }
            }
            this.active_parts = new Gee.ArrayList<Participant>();
            this.active_callers = new Gee.ArrayList<Participant>();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }
            sort_participants_by_order();

            return diagram;
        }

        // "participant X order 10": a stable sort by the order value (0 when not given)
        private void sort_participants_by_order() {
            var parts = diagram.participants;
            bool ordered = false;
            foreach (var p in parts) {
                ordered = ordered || p.order != 0;
            }
            if (!ordered) {
                return;
            }
            var sorted = new Gee.ArrayList<Participant>();
            foreach (var p in parts) {
                int at = sorted.size;
                while (at > 0 && sorted[at - 1].order > p.order) {
                    at--;
                }
                sorted.insert(at, p);
            }
            parts.clear();
            parts.add_all(sorted);
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
            if (check(TokenType.CAPTION)) {
                Token caption_token = advance();
                string caption = rest_of_line_after(caption_token);
                if (caption.length > 0) {
                    diagram.caption = caption;
                }
                return;
            }
            // "legend ... endlegend": the body lines were parsed as statements
            if (check(TokenType.LEGEND)) {
                advance();
                consume_block({ "endlegend", "end legend" });
                return;
            }

            // "..." / "...text..." (delay) and "|||" / "||45||" (space) were skipped
            if (at_line_start() && parse_space()) {
                return;
            }

            // "create Bob" / "create control Bob": Bob's head box sits at his first message
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "create" && current + 1 < tokens.size &&
                tokens[current + 1].token_type != TokenType.NEWLINE && tokens[current + 1].space_before) {
                advance();
                string? created_name = null;
                if (current + 1 < tokens.size &&
                    (check(TokenType.PARTICIPANT) || check(TokenType.ACTOR) || check(TokenType.BOUNDARY) ||
                     check(TokenType.CONTROL) || check(TokenType.ENTITY) || check(TokenType.DATABASE) ||
                     check(TokenType.COLLECTIONS) || check(TokenType.QUEUE))) {
                    created_name = tokens[current + 1].lexeme;
                    parse_participant_declaration();
                } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    created_name = advance().lexeme;
                    diagram.get_or_create_participant(created_name);
                    expect_end_of_statement();
                }
                var created = created_name != null ? diagram.find_participant(created_name) : null;
                if (created != null) {
                    created.created = true;
                }
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

            // "{start} A -> B" (teoz anchor) names the message's row; "{start} <-> {end} :
            // text" draws a vertical duration arrow between two anchored rows. Both were
            // dropped (the "{" had failed the whole export).
            if (check(TokenType.LBRACE) && current + 2 < tokens.size &&
                tokens[current + 1].token_type != TokenType.NEWLINE &&
                tokens[current + 2].token_type == TokenType.RBRACE) {
                string anchor = tokens[current + 1].lexeme;
                current += 3;
                if (!check(TokenType.IDENTIFIER) && !check(TokenType.STRING)) {
                    parse_duration(anchor);
                    return;
                }
                if (check(TokenType.IDENTIFIER) && peek().lexeme.length > 0 &&
                    ARROW_CHARS.index_of_char(peek().lexeme[0]) >= 0) {
                    parse_duration(anchor);
                    return;
                }
                pending_anchor = anchor;
                parse_message();
                pending_anchor = null;
                return;
            }

            // "newpage [title]" / "ignore newpage" / "autoactivate on|off"
            if (check(TokenType.IDENTIFIER) && at_line_start()) {
                string word = peek().lexeme.down();
                if (word == "newpage") {
                    Token np = advance();
                    string page_title = rest_of_line_after(np);
                    if (!ignore_newpage) {
                        diagram.add_page_break(page_title.length > 0 ? page_title : null);
                    }
                    return;
                }
                if (word == "ignore" && current + 1 < tokens.size &&
                    tokens[current + 1].lexeme.down() == "newpage") {
                    consume_rest_of_line();
                    return;
                }
                if (word == "autoactivate") {
                    advance();
                    autoactivate = consume_rest_of_line().strip().down() == "on";
                    return;
                }
            }

            // "/ note over B": a note on the same row as the note before it
            if (!is_at_end() && peek().lexeme == "/" && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.NOTE ||
                 tokens[current + 1].lexeme == "hnote" || tokens[current + 1].lexeme == "rnote")) {
                advance();
                parse_note();
                diagram.notes[diagram.notes.size - 1].aligned = true;
                return;
            }

            // Note, hexagonal "hnote" and rectangular "rnote". hnote/rnote were not
            // recognised: the note vanished and its text lines were parsed as statements.
            if (check(TokenType.NOTE) || is_shaped_note_start()) {
                parse_note();
                return;
            }

            // Border messages "[-> A", "[<- A", "?-> A", "[-[#red]> A", "[o-> A". The "["
            // used to be skipped as unknown, so the message was dropped.
            if (check(TokenType.LBRACKET) || (check(TokenType.IDENTIFIER) && peek().lexeme == "?")) {
                if (parse_border_incoming()) {
                    return;
                }
                if (check(TokenType.LBRACKET)) {
                    advance();
                    return;
                }
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
                check(TokenType.GROUP) || check(TokenType.REF) || check(TokenType.PARTITION)) {
                parse_frame_start();
                return;
            }

            // Else section within alt
            if (check(TokenType.ELSE)) {
                parse_else_section();
                return;
            }

            // End frame (but not "end note")
            if (check(TokenType.END)) {
                // A stray "end note" / "end hnote" / "end rnote": skip both tokens
                int end_len = note_end_length();
                if (end_len > 0) {
                    current += end_len;
                    return;
                }
                parse_frame_end();
                return;
            }

            // Skinparam: stored for the renderer (it used to be discarded, so
            // themes had no effect on sequence diagrams)
            if (check(TokenType.SKINPARAM)) {
                advance();
                parse_skinparam();
                return;
            }

            // Divider "== Title ==". The lexer returns "==" as two "=" tokens and
            // three or more as one SEPARATOR token. The title used to be thrown away.
            if (is_divider_start()) {
                parse_divider();
                return;
            }

            // autonumber [start [step]] | autonumber stop | autonumber resume [step]
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "autonumber") {
                parse_autonumber();
                return;
            }

            // Scale, Hide, Show (consume keyword + rest of line). "hide footbox" drops
            // the participant boxes at the bottom; it was ignored.
            if (check(TokenType.SCALE) ||
                check(TokenType.HIDE) || check(TokenType.SHOW)) {
                bool is_hide = check(TokenType.HIDE);
                bool is_show = check(TokenType.SHOW);
                advance();
                string rest = consume_rest_of_line().strip().down();
                if (rest == "footbox") {
                    if (is_hide) {
                        diagram.hide_footbox = true;
                    } else if (is_show) {
                        diagram.hide_footbox = false;
                    }
                }
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

        private bool is_equals_token(int offset) {
            if (current + offset >= tokens.size) {
                return false;
            }
            var t = tokens.get(current + offset);
            return t.token_type == TokenType.SEPARATOR ||
                   (t.token_type == TokenType.IDENTIFIER && t.lexeme == "=");
        }

        private bool is_divider_start() {
            if (check(TokenType.SEPARATOR)) {
                return true;
            }
            return check(TokenType.IDENTIFIER) && peek().lexeme == "=" && is_equals_token(1);
        }

        private void parse_divider() {
            int line = peek().line;
            while (is_equals_token(0)) {
                advance();
            }
            var sb = new StringBuilder();
            // The title runs up to the closing "==" (a lone "=" is part of it)
            while (!check(TokenType.NEWLINE) && !is_at_end() &&
                   !(is_equals_token(0) && (check(TokenType.SEPARATOR) || is_equals_token(1)))) {
                Token t = advance();
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                // The lexer strips a STRING's quotes; PlantUML shows them in the title
                if (t.token_type == TokenType.STRING) {
                    sb.append("\"%s\"".printf(t.lexeme));
                } else {
                    sb.append(t.lexeme);
                }
            }
            consume_rest_of_line();
            diagram.add_divider(new SequenceDivider(sb.str.strip(), line));
        }

        // "{start} <-> {end} : text", the first anchor already read
        private void parse_duration(string from_anchor) {
            ArrowStyle style;
            ArrowDirection direction;
            string? color;
            if (!parse_arrow(out style, out direction, out color) || !check(TokenType.LBRACE) ||
                current + 2 >= tokens.size || tokens[current + 2].token_type != TokenType.RBRACE) {
                consume_rest_of_line();
                return;
            }
            string to_anchor = tokens[current + 1].lexeme;
            current += 3;
            string? label = null;
            if (match(TokenType.COLON)) {
                label = rest_of_line_after(previous());
            } else {
                consume_rest_of_line();
            }
            diagram.durations.add(new SequenceDuration(from_anchor, to_anchor,
                                                       label != null && label.length > 0 ? label : null));
        }

        /**
         * autonumber [start] [step] ["format"] | autonumber stop |
         * autonumber resume [step] ["format"] | autonumber inc A
         * "start" may be hierarchical ("1.1.1"). Formats were accepted and ignored, so the
         * numbers were never bold, padded or coloured.
         */
        private void parse_autonumber() {
            Token kw = advance();  // autonumber
            string rest = rest_of_line_after(kw);
            try {
                MatchInfo mi;
                if (rest == "stop") {
                    autonumber_on = false;
                    return;
                }
                if (new Regex("^resume(?:\\s+(\\d+))?(?:\\s*\"(.*)\")?\\s*$").match(rest, 0, out mi)) {
                    autonumber_on = true;
                    string? step = mi.fetch(1);
                    if (step != null && step.length > 0) {
                        autonumber_step = int.parse(step);
                    }
                    string? fmt = mi.fetch(2);
                    if (fmt != null && fmt.length > 0) {
                        autonumber_format = fmt;
                    }
                    return;
                }
                if (new Regex("^inc\\s+([A-Za-z])\\s*$").match(rest, 0, out mi)) {
                    int level = mi.fetch(1).up()[0] - 'A';
                    if (level >= 0 && level < autonumber_levels.length) {
                        autonumber_levels[level]++;
                        for (int k = level + 1; k < autonumber_levels.length; k++) {
                            autonumber_levels[k] = 1;
                        }
                    }
                    return;
                }
                if (new Regex("^(\\d+(?:\\.\\d+)*)?(?:\\s+(\\d+))?(?:\\s*\"(.*)\")?\\s*$").match(rest, 0, out mi)) {
                    autonumber_on = true;
                    autonumber_levels = { 1 };
                    autonumber_step = 1;
                    autonumber_format = DEFAULT_AUTONUMBER_FORMAT;
                    string? start = mi.fetch(1);
                    if (start != null && start.length > 0) {
                        string[] parts = start.split(".");
                        autonumber_levels = new int[parts.length];
                        for (int k = 0; k < parts.length; k++) {
                            autonumber_levels[k] = int.parse(parts[k]);
                        }
                    }
                    string? step = mi.fetch(2);
                    if (step != null && step.length > 0) {
                        autonumber_step = int.parse(step);
                    }
                    string? fmt = mi.fetch(3);
                    if (fmt != null && fmt.length > 0) {
                        autonumber_format = fmt;
                    }
                    return;
                }
            } catch (RegexError e) {
                warning("parse_autonumber: %s", e.message);
            }
            autonumber_on = true;
        }

        // The number in `format`: the first run of "0" / "#" outside a <tag> becomes the value,
        // zero-padded to the count of "0"s. A hierarchical value ("1.2.1") replaces the run
        // as it is. No run: the format is a prefix to the number.
        internal static string format_autonumber(string format, int[] levels) {
            var plain = new StringBuilder();
            for (int k = 0; k < levels.length; k++) {
                if (k > 0) {
                    plain.append(".");
                }
                plain.append(levels[k].to_string());
            }
            int depth = 0;
            int start = -1;
            int end = -1;
            for (int i = 0; i < format.length; i++) {
                char c = format[i];
                if (c == '<') {
                    depth++;
                } else if (c == '>' && depth > 0) {
                    depth--;
                } else if (depth == 0 && (c == '0' || c == '#')) {
                    if (start < 0) {
                        start = i;
                    }
                    end = i + 1;
                } else if (start >= 0) {
                    break;
                }
            }
            if (start < 0) {
                return format + plain.str;
            }
            string number = plain.str;
            if (levels.length == 1) {
                int zeros = 0;
                for (int i = start; i < end; i++) {
                    if (format[i] == '0') {
                        zeros++;
                    }
                }
                bool negative = levels[0] < 0;
                string digits = negative ? (-levels[0]).to_string() : number;
                while (digits.length < zeros) {
                    digits = "0" + digits;
                }
                number = negative ? "-" + digits : digits;
            }
            return format.substring(0, start) + number + format.substring(end);
        }

        // "title text", or "title" alone followed by lines up to "end title"
        private void parse_title() {
            Token title_token = advance();
            string title_text = rest_of_line_after(title_token);
            if (title_text.length == 0) {
                title_text = consume_block({ "end title", "endtitle" });
            }
            if (title_text.length > 0) {
                diagram.title = title_text;
            }
        }

        private void parse_header() {
            Token header_token = advance();
            string header_text = rest_of_line_after(header_token);
            if (header_text.length == 0) {
                header_text = consume_block({ "end header", "endheader" });
            }
            if (header_text.length > 0) {
                diagram.header = header_text;
            }
        }

        private void parse_footer() {
            Token footer_token = advance();
            string footer_text = rest_of_line_after(footer_token);
            if (footer_text.length == 0) {
                footer_text = consume_block({ "end footer", "endfooter" });
            }
            if (footer_text.length > 0) {
                diagram.footer = footer_text;
            }
        }

        // The source line the token at `index` is on, "" when out of range
        private string line_text(int index) {
            if (index < 0 || index >= token_rows.length) {
                return "";
            }
            int row = token_rows[index];
            if (row < 0 || row >= source_lines.length) {
                return "";
            }
            return source_lines[row].replace("\r", "");
        }

        // Is the current token the first on its line?
        private bool at_line_start() {
            return current == 0 || previous().token_type == TokenType.NEWLINE ||
                   previous().token_type == TokenType.COMMENT || previous().line != peek().line;
        }

        /**
         * The source text after `t` up to the end of its line, stripped, with the tokens
         * of the rest of the line consumed. Rejoining tokens lost text the lexer splits
         * or drops: a label "a--b" stopped at the "--", "don't" at the comment quote.
         * Falls back to the rejoined tokens when the token is not found on its line.
         */
        private string rest_of_line_after(Token t) {
            int index = current > 0 && tokens.get(current - 1) == t ? current - 1 : tokens.index_of(t);
            string line = line_text(index);
            int col = t.column - 1;
            if (col >= 0 && col < line.char_count()) {
                int off = line.index_of_nth_char(col);
                string from_token = line.substring(off);
                if (t.lexeme.length > 0 && from_token.down().has_prefix(t.lexeme.down())) {
                    consume_rest_of_line();
                    return from_token.substring(t.lexeme.length).strip();
                }
            }
            return consume_rest_of_line();
        }

        /**
         * Lines up to one of `ends` (compared lower-case, spaces collapsed) or @enduml,
         * joined with newlines; the terminator line is consumed. Called on the opening
         * line, whose rest is skipped.
         */
        private string consume_block(string[] ends) {
            consume_rest_of_line();
            var lines = new StringBuilder();
            int breaks = 0;
            while (!is_at_end() && !check(TokenType.ENDUML)) {
                if (match(TokenType.NEWLINE)) {
                    breaks++;
                    continue;
                }
                // a blank line inside the block stays
                for (int k = 1; k < breaks && lines.len > 0; k++) {
                    lines.append("\n");
                }
                breaks = 0;
                string raw = line_text(current).strip();
                string norm = raw.down();
                try {
                    norm = new Regex("\\s+").replace(norm, -1, 0, " ");
                } catch (RegexError e) {
                    warning("consume_block: %s", e.message);
                }
                consume_rest_of_line();
                bool is_end = false;
                foreach (string e in ends) {
                    if (norm == e) {
                        is_end = true;
                    }
                }
                if (is_end) {
                    break;
                }
                if (lines.len > 0) {
                    lines.append("\n");
                }
                lines.append(raw);
            }
            return lines.str.strip();
        }

        // "..." / "...text..." and "|||" / "||45||" on their own line
        private bool parse_space() {
            string raw = line_text(current).strip();
            if (raw.has_prefix("...")) {
                string text = raw;
                while (text.has_prefix(".")) {
                    text = text.substring(1);
                }
                while (text.has_suffix(".")) {
                    text = text.substring(0, text.length - 1);
                }
                text = text.strip();
                consume_rest_of_line();
                diagram.add_space(new SequenceSpace(true, text.length > 0 ? text : null, 0));
                return true;
            }
            if (raw == "|||") {
                consume_rest_of_line();
                diagram.add_space(new SequenceSpace(false, null, 20));
                return true;
            }
            try {
                MatchInfo mi;
                if (new Regex("^\\|\\|\\s*(\\d+)\\s*\\|\\|$").match(raw, 0, out mi)) {
                    consume_rest_of_line();
                    diagram.add_space(new SequenceSpace(false, null, int.parse(mi.fetch(1))));
                    return true;
                }
            } catch (RegexError e) {
                warning("parse_space: %s", e.message);
            }
            return false;
        }

        // Open activations, innermost last, with the participant whose message started
        // each one: "return" answers the innermost
        private Gee.ArrayList<Participant> active_parts = new Gee.ArrayList<Participant>();
        private Gee.ArrayList<Participant> active_callers = new Gee.ArrayList<Participant>();

        private void push_activation(Participant p, string? color = null) {
            Participant caller = p;
            if (diagram.messages.size > 0) {
                var last = diagram.messages[diagram.messages.size - 1];
                // the sender of the message that reached p ("A <- B": B reached A)
                if (last.direction == ArrowDirection.LEFT) {
                    if (last.from == p) {
                        caller = last.to;
                    }
                } else if (last.to == p) {
                    caller = last.from;
                }
            }
            active_parts.add(p);
            active_callers.add(caller);
            var act = new Activation(p, ActivationType.ACTIVATE);
            act.color = color;
            diagram.add_activation(act);
        }

        private void pop_activation(Participant p) {
            for (int i = active_parts.size - 1; i >= 0; i--) {
                if (active_parts[i] == p) {
                    active_parts.remove_at(i);
                    active_callers.remove_at(i);
                    break;
                }
            }
            diagram.add_activation(new Activation(p, ActivationType.DEACTIVATE));
        }

        private void parse_activate() {
            advance(); // consume 'activate'
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                string name = advance().lexeme;
                // "activate A #red": the bar's colour
                string? color = null;
                if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                    color = advance().lexeme;
                }
                push_activation(diagram.get_or_create_participant(name), color);
            }
            expect_end_of_statement();
        }

        private void parse_deactivate() {
            advance(); // consume 'deactivate'
            if (check(TokenType.IDENTIFIER)) {
                string name = advance().lexeme;
                var participant = diagram.find_participant(name);
                if (participant != null) {
                    pop_activation(participant);
                }
            }
            expect_end_of_statement();
        }

        private void parse_destroy() {
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

        // "return label": a dotted message from the innermost active participant back to
        // the one that activated it, ending the activation. It was ignored.
        private void parse_return() {
            Token return_token = advance();
            string label = rest_of_line_after(return_token);
            if (active_parts.size == 0) {
                return;
            }
            var p = active_parts[active_parts.size - 1];
            var caller = active_callers[active_callers.size - 1];
            var message = new Message(p, caller);
            message.style = ArrowStyle.DOTTED;
            if (label.length > 0) {
                message.label = label;
            }
            number_message(message);
            diagram.add_message(message);
            pop_activation(p);
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

        private void parse_frame_start() {
            Token frame_token = advance();  // consume frame keyword
            int line_num = frame_token.line;
            SequenceFrameType frame_type = token_to_frame_type(frame_token.token_type);

            var frame = new SequenceFrame(frame_type, line_num);
            frame.start_order = event_counter++;

            // Parse optional label/condition
            string label_text = rest_of_line_after(frame_token);
            // "partition p1" is drawn as a group "partition [p1]"
            if (frame_token.token_type == TokenType.PARTITION) {
                label_text = label_text.length > 0 ? "partition [%s]".printf(label_text) : "partition";
            }

            // "ref over A, B : text" or "ref over A" + lines + "end ref": a box over the
            // participants, complete in itself. It used to open a frame that never closed.
            if (frame_type == SequenceFrameType.REF && label_text.down().has_prefix("over")) {
                string over = label_text.substring(4).strip();
                string? text = null;
                int colon = over.index_of(":");
                if (colon >= 0) {
                    text = over.substring(colon + 1).strip();
                    over = over.substring(0, colon);
                }
                foreach (string part in over.split(",")) {
                    string name = part.strip();
                    if (name.length >= 2 && name.has_prefix("\"") && name.has_suffix("\"")) {
                        name = name.substring(1, name.length - 2);
                    }
                    if (name.length > 0) {
                        frame.participants.add(diagram.get_or_create_participant(name));
                    }
                }
                if (text == null) {
                    text = consume_block({ "end ref", "endref", "end" });
                }
                frame.label = text;
                frame.end_order = event_counter++;
                if (frame_stack.size > 0) {
                    frame.parent = frame_stack.get(frame_stack.size - 1);
                }
                diagram.frames.add(frame);
                diagram.events.add(new FrameEvent(frame, true, frame.start_order));
                return;
            }
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

        private void parse_else_section() {
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
            string condition = rest_of_line_after(else_token);
            if (condition.length > 0) {
                else_frame.condition = condition;
            }

            // Add to parent's sections
            parent_frame.sections.add(else_frame);

            // Add FrameEvent for else section
            diagram.events.add(new FrameEvent(else_frame, true, else_frame.start_order));
        }

        private void parse_frame_end() {
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

            // "participant P [ =Title / ---- / ""Sub"" ]": the body lines are read from the
            // source as written (Creole kept, "----" a separator). Rejoining tokens lost the
            // heading, the monospace and the separator.
            if (check(TokenType.LBRACKET)) {
                int open_index = current;
                advance();
                int open_row = token_rows[open_index];
                var body = new Gee.ArrayList<string>();
                int close_row = -1;
                // text after "[" on the same line
                string first_line = line_text(open_index);
                int bracket = first_line.index_of("[");
                if (bracket >= 0) {
                    string after = first_line.substring(bracket + 1);
                    int close = after.last_index_of("]");
                    if (close >= 0) {
                        after = after.substring(0, close);
                        close_row = open_row;
                    }
                    if (after.strip().length > 0) {
                        body.add(after.strip());
                    }
                }
                for (int row = open_row + 1; close_row < 0 && row < source_lines.length; row++) {
                    string raw = source_lines[row].replace("\r", "").strip();
                    if (raw.has_prefix("]")) {
                        close_row = row;
                        break;
                    }
                    if (raw.has_suffix("]")) {
                        raw = raw.substring(0, raw.length - 1).strip();
                        close_row = row;
                    }
                    if (raw.length > 0) {
                        body.add(raw);
                    }
                }
                if (close_row >= 0) {
                    while (!is_at_end() && token_rows[current] < close_row) {
                        advance();
                    }
                    while (!is_at_end() && token_rows[current] == close_row && !check(TokenType.RBRACKET)) {
                        advance();
                    }
                    match(TokenType.RBRACKET);
                    participant.body_lines = body;
                    // A plain-text form for the outline / LSP: no separators or heading marks
                    var plain = new StringBuilder();
                    foreach (string l in body) {
                        string t = l;
                        while (t.has_prefix("=")) {
                            t = t.substring(1);
                        }
                        t = t.strip();
                        bool separator = t.length >= 2 && t.replace("-", "").length == 0;
                        if (separator || t.length == 0) {
                            continue;
                        }
                        if (plain.len > 0) {
                            plain.append("\\n");
                        }
                        plain.append(t);
                    }
                    participant.display_label = plain.str;
                }
            }

            // Stereotype, "as Alias", "#colour" and "order N" in any order
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                int before = current;
                parse_participant_stereotype(participant);
                if (match(TokenType.AS)) {
                    if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                        participant.alias = advance().lexeme;
                    }
                } else if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                    string color_with_hash = advance().lexeme;
                    string color_value = color_with_hash.substring(1);
                    // Only hex colours keep the #, named ones lose it
                    if (is_hex_color(color_value) || color_value.length == 3) {
                        participant.color = color_with_hash;
                    } else {
                        participant.color = color_value;
                    }
                } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "order") {
                    // "participant X order 10": the column order (the lexer may split "-5")
                    advance();
                    var num = new StringBuilder();
                    while (!check(TokenType.NEWLINE) && !is_at_end() &&
                           (num.len == 0 || !peek().space_before) &&
                           (peek().lexeme == "-" || int64.try_parse(peek().lexeme))) {
                        num.append(advance().lexeme);
                    }
                    int64 order_value;
                    if (int64.try_parse(num.str, out order_value)) {
                        participant.order = (int) order_value;
                    }
                }
                if (current == before) {
                    advance();
                }
            }

            // Add if not already exists
            var existing = diagram.find_participant(name);
            if (existing == null) {
                diagram.participants.add(participant);
            } else if (participant.order != 0) {
                existing.order = participant.order;
            }

            expect_end_of_statement();
        }

        // "participant Bob <<foo>>": usually one STEREOTYPE token, but a stereotype
        // the lexer cannot take whole arrives as "<", "<", words, ">", ">". Only the
        // text of a spot stereotype "<<(C,#ADD1B2) Testable>>" is kept.
        private void parse_participant_stereotype(Participant participant) {
            string? text = null;
            if (check(TokenType.STEREOTYPE)) {
                text = advance().lexeme;
            } else if (current + 1 < tokens.size && tokens.get(current).lexeme == "<" &&
                       tokens.get(current + 1).lexeme == "<") {
                var sb = new StringBuilder();
                int k = current + 2;
                while (k < tokens.size && tokens.get(k).token_type != TokenType.NEWLINE) {
                    Token t = tokens.get(k);
                    if (t.lexeme == ">>") {
                        text = sb.str;
                        current = k + 1;
                        break;
                    }
                    if (t.lexeme == ">" && k + 1 < tokens.size && tokens.get(k + 1).lexeme == ">") {
                        text = sb.str;
                        current = k + 2;
                        break;
                    }
                    if (sb.len > 0 && t.space_before) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    k++;
                }
            }
            if (text == null) {
                return;
            }
            string stereo = text.strip();
            if (stereo.has_prefix("(")) {
                int close = stereo.index_of(")");
                if (close > 0) {
                    // "(C,#ADD1B2)": the spot's letter and circle colour
                    string[] spot = stereo.substring(1, close - 1).split(",", 2);
                    string letter = spot[0].strip();
                    if (letter.length > 0) {
                        participant.spot_char = letter.substring(0, letter.index_of_nth_char(1));
                        participant.spot_color = spot.length > 1 && spot[1].strip().length > 0 ? spot[1].strip() : null;
                    }
                    stereo = stereo.substring(close + 1).strip();
                }
            }
            if (stereo.length > 0) {
                participant.stereotype = stereo;
            }
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
            string from_name = advance().lexeme;
            string? from_alias = null;
            // '"Long name" as L -> B'
            if (check(TokenType.AS) && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING)) {
                int save = current;
                advance();
                from_alias = advance().lexeme;
                if (!peek_is_arrow()) {
                    current = save;
                    from_alias = null;
                }
            }

            // Don't create participant yet — confirm arrow first
            ArrowStyle style;
            ArrowDirection direction;
            string? arrow_color;

            if (!parse_arrow(out style, out direction, out arrow_color)) {
                // Not a message — no arrow found, no phantom participant created
                return;
            }

            var from = participant_with_alias(from_name, from_alias);

            // "A ->]" (to the right border) / "A ->?" (short arrow). The "]" failed with
            // "Expected target participant", which failed the whole export.
            if (check(TokenType.RBRACKET) || (check(TokenType.IDENTIFIER) && peek().lexeme == "?")) {
                var border_message = new Message(from, from);
                border_message.border = MessageBorder.RIGHT;
                border_message.border_short = advance().lexeme == "?";
                border_message.style = style;
                border_message.direction = direction;
                border_message.color = arrow_color;
                finish_message(border_message);
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
            // 'A -> "Long\nname" as L : text' declares L; it made a second participant
            // named "Long\nname" and a third one "L" at the next message
            string? to_alias = null;
            if (check(TokenType.AS) && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING)) {
                advance();
                to_alias = advance().lexeme;
            }

            var to = participant_with_alias(to_name, to_alias);

            var message = new Message(from, to);
            message.style = style;
            message.direction = direction;
            message.color = arrow_color;
            finish_message(message);
        }

        // Does an arrow start at the current token?
        private bool peek_is_arrow() {
            int save = current;
            ArrowStyle s;
            ArrowDirection d;
            string? c;
            bool is_arrow = parse_arrow(out s, out d, out c);
            current = save;
            return is_arrow;
        }

        // The participant for a message end; with an alias it is declared as "name as alias"
        private Participant participant_with_alias(string name, string? alias) {
            if (alias == null) {
                return diagram.get_or_create_participant(name);
            }
            var existing = diagram.find_participant(alias);
            if (existing != null) {
                return existing;
            }
            existing = diagram.find_participant(name);
            if (existing != null && existing.alias == null) {
                existing.alias = alias;
                return existing;
            }
            var p = new Participant(name);
            p.alias = alias;
            p.source_line = current > 0 ? previous().line : 0;
            diagram.participants.add(p);
            return p;
        }

        // "[-> A" / "?-> A": a message from the left border (or a short one). The tokens
        // stay unread when the line is not such a message.
        private bool parse_border_incoming() {
            int start = current;
            bool is_short = advance().lexeme == "?";
            if (check(TokenType.NEWLINE) || is_at_end() || peek().space_before) {
                current = start;
                return false;
            }
            ArrowStyle style;
            ArrowDirection direction;
            string? arrow_color;
            if (!parse_arrow(out style, out direction, out arrow_color) ||
                !(check(TokenType.IDENTIFIER) || check(TokenType.STRING))) {
                current = start;
                return false;
            }
            var p = diagram.get_or_create_participant(advance().lexeme);
            var message = new Message(p, p);
            message.border = MessageBorder.LEFT;
            message.border_short = is_short;
            message.style = style;
            message.direction = direction;
            message.color = arrow_color;
            finish_message(message);
            return true;
        }

        // Activation shorthand, label and autonumber after the message ends are read
        private void finish_message(Message message) {
            message.head_left = arrow_head_left;
            message.head_right = arrow_head_right;
            message.deco_left = arrow_deco_left;
            message.deco_right = arrow_deco_right;
            message.anchor = pending_anchor;
            // The participant the arrow points at ("A <- B" points at A) and the sender
            bool reversed = message.direction == ArrowDirection.LEFT;
            var target = reversed ? message.from : message.to;
            var source = reversed ? message.to : message.from;

            // Shorthand between the target and the label: "++" activates the target, "--"
            // deactivates the source ("--++" both), "**" creates the target, "!!" destroys
            // it; "#color" is the activation's colour. Only "++" / "--" alone were read, so
            // "bob -> bib ++ #005500 : hello" and "--++" lost their labels.
            var mods = new StringBuilder();
            while (!check(TokenType.COLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                mods.append(advance().lexeme);
            }
            string m = mods.str;
            bool deactivate = m.has_prefix("--");
            bool activate = m.contains("++");
            bool create = m.contains("**");
            bool destroy = m.contains("!!");
            int hash = m.index_of("#");
            if (hash >= 0) {
                int end = hash + 1;
                while (end < m.length && (m[end].isalnum() || m[end] == '_')) {
                    end++;
                }
                if (end > hash + 1) {
                    message.activation_color = m.substring(hash, end - hash);
                }
            }

            // Optional label after colon
            if (match(TokenType.COLON)) {
                message.label = consume_message_label();
            }
            if (create) {
                bool used = false;
                foreach (var earlier in diagram.messages) {
                    used = used || earlier.from == target || earlier.to == target;
                }
                target.created = !used;
            }

            number_message(message);
            diagram.add_message(message);
            // "autoactivate on": a solid message with a normal or thin head activates its
            // target, a dotted one deactivates its source (create/destroy messages and
            // explicit shorthand excepted). "return" then had nothing to answer.
            if (autoactivate && !activate && !deactivate && !create && !destroy &&
                message.border == MessageBorder.NONE) {
                string head = reversed ? message.head_left : message.head_right;
                if (head == ">" || head == "<" || head == ">>" || head == "<<") {
                    if (message.style == ArrowStyle.DOTTED || message.style == ArrowStyle.DOTTED_OPEN) {
                        pop_activation(source);
                    } else {
                        activate = true;
                    }
                }
            }
            // The activations follow the message, so their bars start at its arrow
            if (deactivate) {
                message.deactivate_source = true;
                pop_activation(source);
            }
            if (activate) {
                message.activate_target = true;
                push_activation(target, message.activation_color);
            }
            if (destroy) {
                diagram.add_activation(new Activation(target, ActivationType.DESTROY));
            }
        }

        private void number_message(Message message) {
            if (autonumber_on) {
                int last = autonumber_levels.length - 1;
                message.number = autonumber_levels[last];
                message.number_text = format_autonumber(autonumber_format, autonumber_levels);
                last_number = format_autonumber("0", autonumber_levels);
                autonumber_levels[last] += autonumber_step;
            }
            // "%autonumber%" is the message's own number
            if (message.label != null && message.label.contains("%autonumber%")) {
                message.label = message.label.replace("%autonumber%", last_number ?? "");
            }
        }

        private const string ARROW_CHARS = "-<>/\\";

        /**
         * A sequence arrow read from its adjacent tokens: "->", "-->>", "<<--", "-\\",
         * "->x", "-[#red]>", "<-[#blue,dashed]-". The lexer splits these in many ways
         * ("-[#red]>" is five tokens, "<<--" is "<<-" and "-"); only the few whole-token
         * arrows were accepted, so "Bob -[#red]> Alice" was no message at all and "<<-"
         * failed with "Expected target participant". The tokens stay unread when the text
         * is not an arrow.
         */
        private bool parse_arrow(out ArrowStyle style, out ArrowDirection direction, out string? color) {
            style = ArrowStyle.SOLID;
            direction = ArrowDirection.RIGHT;
            color = null;

            int start = current;
            var text = new StringBuilder();
            bool first = true;
            string deco_left = "";
            string deco_right = "";
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                Token t = peek();
                if (!first && t.space_before) {
                    break;
                }
                // "[#red]" / "[#red,dashed]" / "[bold]" inside the line
                if (t.token_type == TokenType.LBRACKET && text.len > 0 && !text.str.has_suffix(">")) {
                    int k = current + 1;
                    var inner = new StringBuilder();
                    while (k < tokens.size && tokens[k].token_type != TokenType.RBRACKET &&
                           tokens[k].token_type != TokenType.NEWLINE && tokens[k].token_type != TokenType.EOF) {
                        inner.append(tokens[k].lexeme);
                        k++;
                    }
                    if (k >= tokens.size || tokens[k].token_type != TokenType.RBRACKET) {
                        break;
                    }
                    foreach (string part in inner.str.split(",")) {
                        string p = part.strip();
                        if (p.has_prefix("#") && p.length > 1) {
                            color = p;
                        } else if (p == "dashed" || p == "dotted") {
                            text.append("-");  // counts as a dotted line
                        }
                    }
                    current = k + 1;
                    first = false;
                    continue;
                }
                string lx = t.lexeme;
                // "o" / "x" start ("Bob o\\-- Alice"): it made a participant "o"
                if (first && (lx == "x" || lx == "o") && current + 1 < tokens.size &&
                    !tokens[current + 1].space_before && tokens[current + 1].lexeme.length > 0 &&
                    ARROW_CHARS.index_of_char(tokens[current + 1].lexeme[0]) >= 0) {
                    deco_left = advance().lexeme;
                    first = false;
                    continue;
                }
                bool arrow_token = lx.length > 0;
                for (int i = 0; i < lx.length; i++) {
                    if (ARROW_CHARS.index_of_char(lx[i]) < 0) {
                        arrow_token = false;
                        break;
                    }
                }
                // "x" / "o" end ("->x Bob", "->o Bob") when a separate target follows, or
                // the border "]" / "?" of "A ->x]"
                if (!arrow_token && !first && (lx == "x" || lx == "o") &&
                    current + 1 < tokens.size &&
                    (tokens[current + 1].space_before || tokens[current + 1].token_type == TokenType.RBRACKET ||
                     tokens[current + 1].lexeme == "?") &&
                    (text.str.has_suffix(">") || text.str.has_suffix("\\") || text.str.has_suffix("/"))) {
                    deco_right = advance().lexeme;
                    break;
                }
                if (!arrow_token) {
                    break;
                }
                text.append(lx);
                advance();
                first = false;
            }

            string arrow = text.str;
            // "A -x B" / "A o- B": a decoration alone still needs a head on some end
            if (!arrow.contains("-") || !classify_arrow(arrow, deco_left.length > 0 || deco_right.length > 0,
                                                        out style, out direction)) {
                current = start;
                color = null;
                return false;
            }
            int dash_start = arrow.index_of_char('-');
            int dash_end = arrow.last_index_of_char('-');
            arrow_head_left = arrow.substring(0, dash_start);
            arrow_head_right = arrow.substring(dash_end + 1);
            arrow_deco_left = deco_left;
            arrow_deco_right = deco_right;
            return true;
        }

        // The ends of the arrow parse_arrow() read last
        private string arrow_head_left = "";
        private string arrow_head_right = "";
        private string arrow_deco_left = "";
        private string arrow_deco_right = "";

        private static bool classify_arrow(string arrow, bool decorated, out ArrowStyle style,
                                           out ArrowDirection direction) {
            style = ArrowStyle.SOLID;
            direction = ArrowDirection.RIGHT;
            int dash_start = arrow.index_of_char('-');
            int dash_end = arrow.last_index_of_char('-');
            string head_left = arrow.substring(0, dash_start);
            string head_right = arrow.substring(dash_end + 1);
            string line = arrow.substring(dash_start, dash_end - dash_start + 1);
            if (line.replace("-", "").length > 0) {
                return false;
            }
            foreach (string head in new string[] { head_left, head_right }) {
                if (head.length > 2) {
                    return false;
                }
            }
            bool left = head_left.length > 0;
            bool right = head_right.length > 0;
            if (left && (head_left.contains(">"))) return false;
            if (right && (head_right.contains("<"))) return false;
            if (!left && !right && !decorated) {
                return false;
            }
            direction = left && right ? ArrowDirection.BIDIRECTIONAL
                : (left ? ArrowDirection.LEFT : ArrowDirection.RIGHT);
            bool dotted = line.length >= 2;
            string head = right ? head_right : head_left;
            bool open = head.length == 2 || head == "\\" || head == "/";
            if (dotted) {
                style = open ? ArrowStyle.DOTTED_OPEN : ArrowStyle.DOTTED;
            } else {
                style = open ? ArrowStyle.SOLID_OPEN : ArrowStyle.SOLID;
            }
            return true;
        }

        // "hnote over A" / "rnote left of A" / "hnote across": an identifier the lexer
        // does not know, followed by a note position
        private bool is_shaped_note_start() {
            if (!check(TokenType.IDENTIFIER) || (peek().lexeme != "hnote" && peek().lexeme != "rnote") ||
                current + 1 >= tokens.size) {
                return false;
            }
            var next = tokens.get(current + 1);
            return next.token_type == TokenType.OVER || next.token_type == TokenType.LEFT ||
                   next.token_type == TokenType.RIGHT ||
                   (next.token_type == TokenType.IDENTIFIER && next.lexeme == "across");
        }

        // Tokens of a note terminator at the current position: "end note" / "end hnote" /
        // "end rnote" (2) or "endnote" / "endhnote" / "endrnote" (1); 0 otherwise
        private int note_end_length() {
            if (is_at_end()) {
                return 0;
            }
            Token t = peek();
            if (t.token_type == TokenType.END && current + 1 < tokens.size) {
                Token next = tokens.get(current + 1);
                if (next.token_type == TokenType.NOTE ||
                    (next.token_type == TokenType.IDENTIFIER && (next.lexeme == "hnote" || next.lexeme == "rnote"))) {
                    return 2;
                }
            }
            if (t.token_type == TokenType.IDENTIFIER &&
                (t.lexeme == "endnote" || t.lexeme == "endhnote" || t.lexeme == "endrnote")) {
                return 1;
            }
            return 0;
        }

        private void parse_note() {
            Token keyword = advance(); // consume 'note' / 'hnote' / 'rnote'
            string kind = keyword.token_type == TokenType.NOTE ? "note" : keyword.lexeme;

            string position = "right";
            Participant? over_participant = null;
            Participant? over_participant2 = null;

            if (match(TokenType.LEFT)) {
                position = "left";
                if (match(TokenType.OF)) {
                    if (check(TokenType.IDENTIFIER)) {
                        string name = advance().lexeme;
                        over_participant = diagram.get_or_create_participant(name);
                    }
                }
            } else if (match(TokenType.RIGHT)) {
                position = "right";
                if (match(TokenType.OF)) {
                    if (check(TokenType.IDENTIFIER)) {
                        string name = advance().lexeme;
                        over_participant = diagram.get_or_create_participant(name);
                    }
                }
            } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "across") {
                // "note across: text" spans every lifeline. "across" was not recognised,
                // so the colon was missed and the note took the rest of the file as its
                // text, looking for "end note".
                advance();
                position = "across";
                if (diagram.participants.size > 0) {
                    over_participant = diagram.participants[0];
                    if (diagram.participants.size > 1) {
                        over_participant2 = diagram.participants[diagram.participants.size - 1];
                    }
                }
            } else if (match(TokenType.OVER)) {
                position = "over";
                if (check(TokenType.IDENTIFIER)) {
                    string name = advance().lexeme;
                    over_participant = diagram.get_or_create_participant(name);
                }
                // "note over A, B": without consuming ", B" it became note text
                if (check(TokenType.IDENTIFIER) && peek().lexeme == ",") {
                    advance();
                    if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                        over_participant2 = diagram.get_or_create_participant(advance().lexeme);
                    }
                }
            }

            // "note over A #lightblue": a colour before the text. It was not consumed, so
            // the colon was missed and the note swallowed the file looking for "end note".
            string? color = null;
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                color = advance().lexeme;
            }

            // Get note text
            string text = "";
            if (match(TokenType.COLON)) {
                // Single-line note: note right: text
                text = rest_of_line_after(previous());
            } else {
                // Multi-line note: note right \n text \n end note (or "endnote",
                // "end hnote", "endrnote", ...)
                text = consume_block({ "end note", "endnote", "end hnote", "endhnote",
                                       "end rnote", "endrnote" });
            }

            // "%autonumber%": the number of the message before the note
            if (text.contains("%autonumber%")) {
                text = text.replace("%autonumber%", last_number ?? "");
            }
            var note = new Note(text, position);
            note.participant = over_participant;
            note.participant2 = over_participant2;
            note.kind = kind;
            note.color = color;
            diagram.add_note(note);
        }

        // skinparam name value | skinparam element { Property value ... }
        // Any token can name the element ("note", "sequence", "state" ...).
        private void parse_skinparam() {
            if (check(TokenType.NEWLINE) || is_at_end()) {
                return;
            }
            string first_name = advance().lexeme;
            if (match(TokenType.LBRACE)) {
                int brace_line = previous().line;
                // A value ends at the newline OR the closing brace: reading to the end
                // of the line swallowed the "}" of a one-line block ("skinparam
                // participant { BackgroundColor red }", what <style> translates to),
                // and every later line of the diagram became a skinparam property.
                while (!is_at_end() && !check(TokenType.RBRACE) && !check(TokenType.ENDUML)) {
                    if (match(TokenType.NEWLINE) || match(TokenType.COMMENT)) {
                        continue;
                    }
                    Token property_token = advance();
                    string property = property_token.lexeme;
                    // BackgroundColor<<stereotype>> gets its own entry
                    bool stereotype_key = false;
                    if (check(TokenType.STEREOTYPE)) {
                        property = "%s<<%s>>".printf(property, advance().lexeme.down());
                        stereotype_key = true;
                    }
                    var value_sb = new StringBuilder();
                    while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                        Token t = advance();
                        if (value_sb.len > 0 && t.space_before) {
                            value_sb.append(" ");
                        }
                        value_sb.append(t.lexeme);
                    }
                    string value = value_sb.str.strip();
                    // PlantUML rejects "skinparam participant { BackgroundColor<<foo>> red }"
                    // written on one line; only the <style> translation of "participant.foo"
                    // produces it, and PlantUML does not colour participants from that style.
                    // A bare ".foo" selector (translated to "element { ...<<foo>> }") does apply.
                    bool style_selector = stereotype_key && property_token.line == brace_line &&
                                          first_name.down() != "element";
                    if (value.length > 0 && !style_selector) {
                        diagram.skin_params.set_element_property(first_name, property, value);
                    }
                }
                match(TokenType.RBRACE);
            } else if (check(TokenType.STEREOTYPE)) {
                // "skinparam participantBackgroundColor<<foo>> red" is the block form's
                // "participant { BackgroundColor<<foo>> red }"
                string stereo = advance().lexeme.down();
                string value = consume_rest_of_line().strip();
                if (value.length == 0) {
                    return;
                }
                string lower = first_name.down();
                string[] elements = { "participant", "actor", "boundary", "control", "entity",
                                      "database", "collections", "queue" };
                foreach (string elem in elements) {
                    if (lower.has_prefix(elem) && lower.length > elem.length) {
                        diagram.skin_params.set_element_property(
                            elem, "%s<<%s>>".printf(first_name.substring(elem.length), stereo), value);
                        return;
                    }
                }
                diagram.skin_params.set_global("%s<<%s>>".printf(first_name, stereo), value);
            } else {
                string value = consume_rest_of_line().strip();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }
        }

        private string consume_rest_of_line() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        // The label is everything after the colon. It used to stop at a "--" or "++"
        // token, so "use -- carefully" became "use".
        private string consume_message_label() {
            return rest_of_line_after(previous());
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
            string context = "";
            if (token.lexeme.length > 0) {
                context = " (found: '%s')".printf(token.lexeme);
            }
            throw new IOError.FAILED("Line %d: %s%s", token.line, message, context);
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
