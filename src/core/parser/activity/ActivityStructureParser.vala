namespace GDiagram {
    /**
     * Parser for structural elements in activity diagrams.
     * Handles swimlanes, partitions, and groups.
     */
    public class ActivityStructureParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ActivityDiagram diagram;
        private string? current_partition;

        // Delegate for parsing sub-statements
        public delegate void ParseStatementDelegate() throws Error;
        private unowned ParseStatementDelegate parse_statement_callback;

        // Delegate for skipping newlines
        public delegate void SkipNewlinesDelegate();
        private unowned SkipNewlinesDelegate skip_newlines_callback;

        public ActivityStructureParser(
            Gee.ArrayList<Token> tokens,
            ref int current,
            ActivityDiagram diagram
        ) {
            this.tokens = tokens;
            this.current = current;
            this.diagram = diagram;
        }

        public void set_callbacks(
            ParseStatementDelegate parse_stmt,
            SkipNewlinesDelegate skip_nl
        ) {
            this.parse_statement_callback = parse_stmt;
            this.skip_newlines_callback = skip_nl;
        }

        public void set_current_partition(string? partition) {
            this.current_partition = partition;
        }

        public string? get_current_partition() {
            return this.current_partition;
        }

        /**
         * Parse swimlane: |Name|, |#color|Name|, or |[#color]alias| Title
         */
        public void parse_swimlane(ref int position) throws Error {
            current = position;

            string? color = null;
            string? alias = null;
            var sb = new StringBuilder();

            // Check for alias syntax: |[#color]alias| or |[alias]|
            if (check(TokenType.LBRACKET)) {
                advance();  // consume [

                // Check for color inside brackets
                if (check(TokenType.HASH)) {
                    advance();  // consume #
                    var color_sb = new StringBuilder();
                    while (!check(TokenType.RBRACKET) && !check(TokenType.PIPE) && !is_at_end()) {
                        color_sb.append(advance().lexeme);
                    }
                    color = color_sb.str.strip();
                }

                match(TokenType.RBRACKET);  // consume ]

                // Get alias (text after ] but before |)
                var alias_sb = new StringBuilder();
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (alias_sb.len > 0) {
                        alias_sb.append(" ");
                    }
                    alias_sb.append(t.lexeme);
                }
                alias = alias_sb.str.strip();

                match(TokenType.PIPE);  // consume middle |

                // Get title (display name)
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            } else if (check(TokenType.HASH)) {
                // Old syntax: |#color|Name|
                advance();  // consume #
                var color_sb = new StringBuilder();
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    color_sb.append(advance().lexeme);
                }
                color = color_sb.str.strip();

                match(TokenType.PIPE);  // consume middle |

                // Collect name until closing pipe
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            } else {
                // Simple syntax: |Name|
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            match(TokenType.PIPE);  // consume closing |

            string name = sb.str.strip();
            if (name.length > 0 || (alias != null && alias.length > 0)) {
                // Use alias as lookup key if provided, otherwise use name
                string lookup_key = (alias != null && alias.length > 0) ? alias : name;
                string display_name = name.length > 0 ? name : (alias != null ? alias : "");

                current_partition = lookup_key;

                // Add partition to diagram if not already present
                bool found = false;
                foreach (var p in diagram.partitions) {
                    if (p.name == lookup_key || (p.alias != null && p.alias == lookup_key)) {
                        found = true;
                        // Update color if provided
                        if (color != null) {
                            p.color = color;
                        }
                        break;
                    }
                }
                if (!found) {
                    var partition = new ActivityPartition(display_name, color, alias);
                    diagram.partitions.add(partition);
                }
            }

            position = current;
        }

        /**
         * Parse partition: partition #color "Name" { ... } or partition "Name" { ... }
         */
        public void parse_partition(ref int position) throws Error {
            current = position;

            string name = "";
            string? partition_color = null;

            // Check for optional color: partition #color or partition (color)
            if (check(TokenType.HASH)) {
                advance();  // consume #
                if (check(TokenType.IDENTIFIER)) {
                    string color_str = advance().lexeme;
                    if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                        partition_color = "#" + color_str;
                    } else {
                        partition_color = color_str;
                    }
                }
            } else if (match(TokenType.LPAREN)) {
                var color_sb = new StringBuilder();
                if (check(TokenType.HASH)) {
                    advance();
                }
                while (!check(TokenType.RPAREN) && !is_at_end()) {
                    color_sb.append(advance().lexeme);
                }
                string color_str = color_sb.str.strip();
                if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                    partition_color = "#" + color_str;
                } else {
                    partition_color = color_str;
                }
                match(TokenType.RPAREN);
            }

            // Get partition name (string or identifier)
            if (match(TokenType.STRING)) {
                name = previous().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            }

            // Save previous partition for nesting
            string? prev_partition = current_partition;
            current_partition = name;

            // Add partition to diagram
            bool found = false;
            foreach (var p in diagram.partitions) {
                if (p.name == name) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                diagram.partitions.add(new ActivityPartition(name, partition_color));
            }

            skip_newlines_callback();

            // Parse partition body in braces
            if (match(TokenType.LBRACE)) {
                skip_newlines_callback();

                while (!check(TokenType.RBRACE) && !is_at_end()) {
                    parse_statement_callback();
                    skip_newlines_callback();
                }

                match(TokenType.RBRACE);
            }

            // Restore previous partition
            current_partition = prev_partition;

            position = current;
        }

        /**
         * Parse group: group #color Name or group Name #color ... end group
         */
        public void parse_group(ref int position) throws Error {
            current = position;

            string? group_color = null;
            var name_sb = new StringBuilder();

            // Check for color at start
            if (check(TokenType.HASH)) {
                advance();  // consume #
                if (check(TokenType.IDENTIFIER)) {
                    string color_str = advance().lexeme;
                    if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                        group_color = "#" + color_str;
                    } else {
                        group_color = color_str;
                    }
                }
            }

            // Collect group name until newline or #
            while (!check(TokenType.NEWLINE) && !check(TokenType.HASH) && !is_at_end()) {
                Token t = advance();
                if (name_sb.len > 0) {
                    name_sb.append(" ");
                }
                name_sb.append(t.lexeme);
            }

            // Check for color at end
            if (check(TokenType.HASH)) {
                advance();  // consume #
                if (check(TokenType.IDENTIFIER)) {
                    string color_str = advance().lexeme;
                    if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                        group_color = "#" + color_str;
                    } else {
                        group_color = color_str;
                    }
                }
            }

            string name = name_sb.str.strip();

            // Save previous partition for nesting
            string? prev_partition = current_partition;
            current_partition = name;

            // Add as partition with color
            if (name.length > 0) {
                bool found = false;
                foreach (var p in diagram.partitions) {
                    if (p.name == name) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    diagram.partitions.add(new ActivityPartition(name, group_color));
                }
            }

            skip_newlines_callback();

            // Parse group body until "end group"
            while (!check_end_group() && !is_at_end()) {
                parse_statement_callback();
                skip_newlines_callback();
            }

            // Consume "end group"
            match_end_group();

            // Restore previous partition
            current_partition = prev_partition;

            position = current;
        }

        // Helper methods
        private bool check_end_group() {
            if (check(TokenType.END)) {
                if (current + 1 < tokens.size) {
                    var next = tokens.get(current + 1);
                    if (next.token_type == TokenType.GROUP) {
                        return true;
                    }
                }
            }
            return false;
        }

        private bool match_end_group() {
            if (check_end_group()) {
                advance();  // END
                advance();  // GROUP
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
