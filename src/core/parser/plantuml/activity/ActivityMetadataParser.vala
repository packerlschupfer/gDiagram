namespace GDiagram {
    /**
     * Parser for metadata elements in activity diagrams.
     * Handles title, header, footer, caption, legend, notes, and skinparam directives.
     */
    public class ActivityMetadataParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ActivityDiagram diagram;
        private ActivityNode? last_node;

        // Reference to edge parser for pending edge note
        private ActivityEdgeParser? edge_parser;

        // Delegate for skipping newlines
        public delegate void SkipNewlinesDelegate();
        private unowned SkipNewlinesDelegate skip_newlines_callback;

        public ActivityMetadataParser(
            Gee.ArrayList<Token> tokens,
            ref int current,
            ActivityDiagram diagram
        ) {
            this.tokens = tokens;
            this.current = current;
            this.diagram = diagram;
        }

        public void set_callbacks(SkipNewlinesDelegate skip_nl) {
            this.skip_newlines_callback = skip_nl;
        }

        public void set_last_node(ActivityNode? node) {
            this.last_node = node;
        }

        public void set_edge_parser(ActivityEdgeParser parser) {
            this.edge_parser = parser;
        }

        /**
         * Parse title directive.
         */
        public void parse_title(ref int position) throws Error {
            current = position;

            var sb = new StringBuilder();

            // Collect title until newline
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            diagram.title = sb.str.strip();

            position = current;
        }

        /**
         * Parse header directive.
         */
        public void parse_header(ref int position) throws Error {
            current = position;

            var sb = new StringBuilder();

            // Collect header until newline
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            diagram.header = sb.str.strip();

            position = current;
        }

        /**
         * Parse footer directive.
         */
        public void parse_footer(ref int position) throws Error {
            current = position;

            var sb = new StringBuilder();

            // Collect footer until newline
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            diagram.footer = sb.str.strip();

            position = current;
        }

        /**
         * Parse caption directive.
         */
        public void parse_caption(ref int position) throws Error {
            current = position;

            var sb = new StringBuilder();

            // Collect caption until newline
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            diagram.caption = sb.str.strip();

            position = current;
        }

        /**
         * Parse legend: legend left / legend right / legend center
         */
        public void parse_legend(ref int position) throws Error {
            current = position;

            LegendPosition legend_position = LegendPosition.RIGHT;  // default

            if (match(TokenType.LEFT)) {
                legend_position = LegendPosition.LEFT;
            } else if (match(TokenType.RIGHT)) {
                legend_position = LegendPosition.RIGHT;
            } else if (match(TokenType.CENTER)) {
                legend_position = LegendPosition.CENTER;
            }

            skip_newlines_callback();

            var sb = new StringBuilder();

            // Collect text until "endlegend" or "end legend"
            // Handle Creole markers specially to avoid unwanted spaces
            while (!check_end_legend() && !is_at_end()) {
                if (check(TokenType.NEWLINE)) {
                    if (sb.len > 0) {
                        sb.append("\n");
                    }
                    advance();
                } else {
                    Token t = advance();
                    string lexeme = t.lexeme;

                    bool should_add_space = sb.len > 0 && !sb.str.has_suffix("\n");

                    if (should_add_space) {
                        should_add_space = ActivityTextFormatter.should_add_space_before(sb.str, lexeme);
                    }

                    if (should_add_space) {
                        sb.append(" ");
                    }
                    sb.append(lexeme);
                }
            }

            // Consume "endlegend" or "end legend"
            match_end_legend();

            diagram.legend = new ActivityLegend(sb.str.strip(), legend_position);

            position = current;
        }

        /**
         * Parse note: note left/right/top/bottom, with optional color and text
         */
        public void parse_note(ref int position, bool is_floating = false) throws Error {
            current = position;

            // Check for "note on link" pattern
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "on") {
                advance();  // consume "on"
                if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "link") {
                    advance();  // consume "link"
                    // Parse note text after colon
                    if (match(TokenType.COLON)) {
                        var sb = new StringBuilder();
                        while (!check(TokenType.NEWLINE) && !is_at_end()) {
                            if (sb.len > 0) sb.append(" ");
                            sb.append(advance().lexeme);
                        }
                        if (edge_parser != null) {
                            edge_parser.pending_edge_note = sb.str.strip();
                        }
                    }
                    position = current;
                    return;
                }
            }

            NotePosition note_position = NotePosition.RIGHT;  // default
            string? note_color = null;

            if (match(TokenType.LEFT)) {
                note_position = NotePosition.LEFT;
            } else if (match(TokenType.RIGHT)) {
                note_position = NotePosition.RIGHT;
            } else if (match(TokenType.TOP)) {
                note_position = NotePosition.TOP;
            } else if (match(TokenType.BOTTOM)) {
                note_position = NotePosition.BOTTOM;
            }

            // Check for optional color: #color
            if (check(TokenType.HASH)) {
                advance();  // consume #
                var color_sb = new StringBuilder();
                while (!check(TokenType.COLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    color_sb.append(advance().lexeme);
                }
                note_color = color_sb.str.strip();
            }

            var sb = new StringBuilder();

            // Check for inline note (with colon)
            if (match(TokenType.COLON)) {
                // Inline note - collect until newline
                // Handle Creole markers specially
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    string lexeme = t.lexeme;

                    bool should_add_space = sb.len > 0;
                    if (should_add_space) {
                        should_add_space = ActivityTextFormatter.should_add_space_before(sb.str, lexeme);
                    }

                    if (should_add_space) {
                        sb.append(" ");
                    }
                    sb.append(lexeme);
                }
            } else {
                // Multiline note - collect until "end note"
                skip_newlines_callback();

                // Handle Creole markers specially
                while (!check_end_note() && !is_at_end()) {
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) {
                            sb.append("\n");
                        }
                        advance();
                    } else {
                        Token t = advance();
                        string lexeme = t.lexeme;

                        bool should_add_space = sb.len > 0 && !sb.str.has_suffix("\n");
                        if (should_add_space) {
                            should_add_space = ActivityTextFormatter.should_add_space_before(sb.str, lexeme);
                        }

                        if (should_add_space) {
                            sb.append(" ");
                        }
                        sb.append(lexeme);
                    }
                }

                // Consume "end note"
                match_end_note();
            }

            // Attach note
            ActivityNode? attached_to = is_floating ? null : last_node;
            var note = new ActivityNote(sb.str.strip(), note_position, attached_to, note_color);
            diagram.notes.add(note);

            position = current;
        }

        /**
         * Parse skinparam directives.
         */
        public void parse_skinparam(ref int position) throws Error {
            current = position;

            // Get the first identifier (could be element name or property name)
            string first_name = "";
            if (check(TokenType.IDENTIFIER) || is_skinparam_element_keyword()) {
                first_name = advance().lexeme;
            } else {
                // No identifier after skinparam - skip line
                skip_to_end_of_line();
                position = current;
                return;
            }

            // Check if this is block syntax
            if (match(TokenType.LBRACE)) {
                // Block syntax: skinparam element { property value ... }
                string element = first_name;
                parse_skinparam_block(element);
            } else {
                // Single line syntax
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }

            position = current;
        }

        /**
         * Parse skinparam block syntax.
         */
        private void parse_skinparam_block(string element) throws Error {
            skip_newlines_callback();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines_callback();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                // Get property name
                if (!check(TokenType.IDENTIFIER)) {
                    advance();  // Skip unknown token
                    continue;
                }

                string property = advance().lexeme;

                // Get value (rest of line until newline)
                string value = collect_skinparam_value();

                if (value.length > 0) {
                    diagram.skin_params.set_element_property(element, property, value);
                }

                skip_newlines_callback();
            }

            match(TokenType.RBRACE);  // Consume closing brace
        }

        /**
         * Collect skinparam value tokens.
         */
        private string collect_skinparam_value() {
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                // Check if this is a hash starting a color
                if (t.lexeme == "#") {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    // Continue collecting color without spaces
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    // Regular token - add space separator
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            return sb.str.strip();
        }

        // Helper methods
        private void skip_to_end_of_line() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private bool is_skinparam_element_keyword() {
            switch (peek().token_type) {
                case TokenType.CLASS:
                case TokenType.INTERFACE:
                case TokenType.ABSTRACT:
                case TokenType.ENUM:
                case TokenType.NOTE:
                case TokenType.LEGEND:
                case TokenType.TITLE:
                case TokenType.HEADER:
                case TokenType.FOOTER:
                case TokenType.PARTICIPANT:
                case TokenType.ACTOR:
                case TokenType.BOUNDARY:
                case TokenType.CONTROL:
                case TokenType.ENTITY:
                case TokenType.DATABASE:
                    return true;
                default:
                    return false;
            }
        }

        private bool check_end_legend() {
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "endlegend") {
                return true;
            }
            if (check(TokenType.END)) {
                if (current + 1 < tokens.size) {
                    var next = tokens.get(current + 1);
                    if (next.token_type == TokenType.LEGEND) {
                        return true;
                    }
                }
            }
            return false;
        }

        private bool match_end_legend() {
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "endlegend") {
                advance();
                return true;
            }
            if (check(TokenType.END)) {
                if (current + 1 < tokens.size) {
                    var next = tokens.get(current + 1);
                    if (next.token_type == TokenType.LEGEND) {
                        advance();  // END
                        advance();  // LEGEND
                        return true;
                    }
                }
            }
            return false;
        }

        private bool check_end_note() {
            if (check(TokenType.END)) {
                if (current + 1 < tokens.size) {
                    var next = tokens.get(current + 1);
                    if (next.token_type == TokenType.NOTE) {
                        return true;
                    }
                }
            }
            return false;
        }

        private bool match_end_note() {
            if (check_end_note()) {
                advance();  // END
                advance();  // NOTE
                return true;
            }
            return false;
        }

        // Token navigation helpers
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
