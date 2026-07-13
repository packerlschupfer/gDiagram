namespace GDiagram {
    /**
     * Parser for structural elements in activity diagrams.
     * Handles swimlanes, partitions, and groups.
     */
    public class ActivityStructureParser : Object {
        private TokenStream stream;
        private ActivityDiagram diagram;
        private string? current_partition;

        // Delegate for parsing sub-statements
        public delegate void ParseStatementDelegate() throws Error;
        private unowned ParseStatementDelegate parse_statement_callback;

        // Delegate for skipping newlines
        public delegate void SkipNewlinesDelegate();
        private unowned SkipNewlinesDelegate skip_newlines_callback;

        // Delegate for updating partition in main parser
        public delegate void UpdatePartitionDelegate(string? partition);
        private unowned UpdatePartitionDelegate? update_partition_callback;

        public ActivityStructureParser(
            TokenStream stream,
            ActivityDiagram diagram
        ) {
            this.stream = stream;
            this.diagram = diagram;
        }

        public void set_callbacks(
            ParseStatementDelegate parse_stmt,
            SkipNewlinesDelegate skip_nl,
            UpdatePartitionDelegate? update_partition = null
        ) {
            this.parse_statement_callback = parse_stmt;
            this.skip_newlines_callback = skip_nl;
            this.update_partition_callback = update_partition;
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
        public void parse_swimlane() {

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
        }

        /**
         * Parse partition: partition #color "Name" { ... } or partition "Name" { ... }
         */
        public void parse_partition() throws Error {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG]       parse_partition() ENTER token='%s'\n", peek().lexeme);

            string name = "";
            string? partition_color = null;

            // Check for optional color: partition #color or partition (color)
            if (check(TokenType.HASH)) {
                if (debug) print("[DEBUG]         Found # color\n");
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
            if (debug) print("[DEBUG]         Looking for partition name, current token='%s' (type=%d)\n", peek().lexeme, peek().token_type);

            if (match(TokenType.STRING)) {
                name = previous().lexeme;
                if (debug) print("[DEBUG]         Got STRING name: '%s'\n", name);
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
                if (debug) print("[DEBUG]         Got IDENTIFIER name: '%s'\n", name);
            } else {
                if (debug) printerr("[ERROR]       No partition name found! token='%s' (type=%d)\n", peek().lexeme, peek().token_type);
            }

            // Save previous partition for nesting
            string? prev_partition = current_partition;
            current_partition = name;
            if (debug) print("[DEBUG]         Set current_partition='%s', prev='%s'\n", current_partition, prev_partition);

            // Notify main parser of partition change
            if (update_partition_callback != null) {
                update_partition_callback(current_partition);
            }

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

            if (debug) print("[DEBUG]         After skip_newlines, token='%s'\n", peek().lexeme);

            // Parse partition body in braces
            if (match(TokenType.LBRACE)) {
                if (debug) print("[DEBUG]         Found LBRACE, parsing partition body...\n");
                skip_newlines_callback();

                // Safety: prevent infinite loop AND track nesting depth
                int max_iterations = 10000;
                int iterations = 0;
                int nesting_depth = 0;

                while (!is_at_end() && iterations < max_iterations) {
                    // Check for RBRACE only at depth 0
                    if (nesting_depth == 0 && check(TokenType.RBRACE)) {
                        if (debug) print("[DEBUG]           Loop break: depth=0, found RBRACE\n");
                        break;
                    }

                    if (debug) {
                        print("[DEBUG]           Iter %d: token='%s' (type=%d), depth=%d\n",
                            iterations, peek().lexeme, peek().token_type, nesting_depth);
                    }

                    // Handle braces directly (don't delegate to parse_statement)
                    if (check(TokenType.LBRACE)) {
                        nesting_depth++;
                        if (debug) print("[DEBUG]             -> LBRACE, depth now %d\n", nesting_depth);
                        advance();  // Consume it here
                        skip_newlines_callback();
                        iterations++;
                        continue;  // Skip to next iteration
                    } else if (check(TokenType.RBRACE)) {
                        nesting_depth--;
                        if (debug) print("[DEBUG]             -> RBRACE, depth now %d\n", nesting_depth);
                        advance();  // Consume it here
                        skip_newlines_callback();
                        iterations++;
                        continue;  // Skip to next iteration
                    }

                    if (debug) print("[DEBUG]             -> Calling parse_statement_callback\n");
                    parse_statement_callback();
                    if (debug) print("[DEBUG]             <- Returned from parse_statement_callback, token='%s'\n", peek().lexeme);

                    skip_newlines_callback();
                    iterations++;
                }

                match(TokenType.RBRACE);
                if (debug) print("[DEBUG]         Partition body complete after %d iterations, depth=%d\n", iterations, nesting_depth);
            } else {
                if (debug) printerr("[ERROR]       No LBRACE found after partition name! token='%s'\n", peek().lexeme);
            }

            // Restore previous partition
            current_partition = prev_partition;

            // Notify main parser of partition change
            if (update_partition_callback != null) {
                update_partition_callback(current_partition);
            }

            if (debug) print("[DEBUG]       parse_partition() EXIT\n");
        }

        /**
         * Parse group: group #color Name or group Name #color ... end group
         */
        public void parse_group() throws Error {

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
        }

        // Helper methods
        private bool check_end_group() {
            if (check(TokenType.END)) {
                return stream.check_next(TokenType.GROUP);
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
            return stream.match(type);
        }

        private bool check(TokenType type) {
            return stream.check(type);
        }

        private Token advance() {
            return stream.advance();
        }

        private bool is_at_end() {
            return stream.is_at_end();
        }

        private Token peek() {
            return stream.peek();
        }

        private Token previous() {
            return stream.previous();
        }
    }
}
