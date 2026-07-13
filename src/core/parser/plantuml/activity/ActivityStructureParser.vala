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

                // Check for color inside brackets. A colour token "#pink" is skipped:
                // PlantUML 1.2026.1 draws "|[#pink]alias| Title" uncoloured.
                if (ActivityParserUtils.is_color_token(peek())) {
                    advance();
                } else if (check(TokenType.HASH)) {
                    advance();  // consume #
                    var color_sb = new StringBuilder();
                    while (!check(TokenType.RBRACKET) && !check(TokenType.PIPE) && !is_at_end()) {
                        color_sb.append(advance().lexeme);
                    }
                    color = "#" + color_sb.str.strip();
                }

                match(TokenType.RBRACKET);  // consume ]

                // Get alias (text after ] but before |)
                var alias_sb = new StringBuilder();
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (alias_sb.len > 0 && t.space_before) {
                        alias_sb.append(" ");
                    }
                    alias_sb.append(t.lexeme);
                }
                alias = alias_sb.str.strip();

                match(TokenType.PIPE);  // consume middle |

                // Get title (display name)
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0 && t.space_before) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            } else if (ActivityParserUtils.is_color_token(peek()) || check(TokenType.HASH)) {
                // Old syntax: |#color|Name|
                if (ActivityParserUtils.is_color_token(peek())) {
                    // The Lexer reads "#pink|Name" as a gradient token: the name
                    // starts after the "|"
                    string lexeme = advance().lexeme;
                    int bar = lexeme.index_of("|");
                    if (bar > 0) {
                        color = lexeme.substring(0, bar);
                        sb.append(lexeme.substring(bar + 1));
                    } else {
                        color = lexeme;
                        match(TokenType.PIPE);  // consume middle |
                    }
                } else {
                    advance();  // consume #
                    var color_sb = new StringBuilder();
                    while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        color_sb.append(advance().lexeme);
                    }
                    color = "#" + color_sb.str.strip();

                    match(TokenType.PIPE);  // consume middle |
                }

                // Collect name until closing pipe
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0 && t.space_before) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            } else {
                // Simple syntax: |Name|
                while (!check(TokenType.PIPE) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0 && t.space_before) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            // "|a1| First Lane": text after the closing pipe is the lane title and
            // the name between the pipes becomes its alias. The bracket form has
            // already read its title.
            if (match(TokenType.PIPE) && alias == null) {
                var title_sb = new StringBuilder();
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (title_sb.len > 0 && t.space_before) {
                        title_sb.append(" ");
                    }
                    title_sb.append(t.lexeme);
                }
                string title = title_sb.str.strip();
                if (title.length > 0) {
                    alias = sb.str.strip();
                    sb.assign(title);
                }
            }

            string name = sb.str.strip();
            if (name.length > 0 || (alias != null && alias.length > 0)) {
                // Use alias as lookup key if provided, otherwise use name
                string lookup_key = (alias != null && alias.length > 0) ? alias : name;
                string display_name = name.length > 0 ? name : (alias != null ? alias : "");

                // Add partition to diagram if not already present
                ActivityPartition? lane = null;
                foreach (var p in diagram.partitions) {
                    // By the id between the pipes only: after "|A| Alpha", "|Alpha|" is
                    // a new lane (PlantUML 1.2026.1), not lane A under its title
                    string lane_id = (p.alias != null && p.alias.length > 0) ? p.alias : p.name;
                    if (p.is_swimlane && lane_id == lookup_key) {
                        lane = p;
                        // Update color if provided
                        if (color != null) {
                            p.color = color;
                        }
                        // A title given later still names the lane
                        if (alias != null && name.length > 0 && p.name == lookup_key) {
                            p.name = name;
                            p.alias = alias;
                        }
                        break;
                    }
                }
                if (lane == null) {
                    lane = new ActivityPartition(display_name, color, alias);
                    lane.key = diagram.unique_partition_key(lookup_key);
                    lane.is_swimlane = true;
                    diagram.partitions.add(lane);
                }

                // Groups and partitions still open continue in the new lane, as their
                // own boxes there (PlantUML stays in the lane when the block closes)
                if (open_blocks.size > 0 && diagram.lane_of(current_partition) != lane.key) {
                    string parent = lane.key;
                    foreach (var block in open_blocks) {
                        var copy = new ActivityPartition(block.name, block.color);
                        copy.key = diagram.unique_partition_key(block.name);
                        copy.parent = parent;
                        diagram.partitions.add(copy);
                        block.key = copy.key;
                        parent = copy.key;
                    }
                    current_partition = parent;
                } else if (open_blocks.size == 0) {
                    current_partition = lane.key;
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

            // Check for optional color: partition #color or partition (color).
            // "#color" is one colour token ("#red/white" for a gradient), or HASH + name.
            if (ActivityParserUtils.is_valid_color_token(peek())) {
                partition_color = advance().lexeme;
            } else if (check_hash_color()) {
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

            // Colour after the name: partition Name #color {
            if (ActivityParserUtils.is_valid_color_token(peek())) {
                partition_color = advance().lexeme;
            }

            // Every block is its own box: a key per occurrence
            var block = open_block(name, partition_color);

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

            close_block(block);

            if (debug) print("[DEBUG]       parse_partition() EXIT\n");
        }

        /**
         * Parse group: group #color Name or group Name #color ... end group
         */
        public void parse_group() throws Error {

            string? group_color = null;
            var name_sb = new StringBuilder();

            // Check for color at start: one colour token, or HASH + name. Only a real
            // colour: "#7" in "group Issue #7" is part of the name.
            if (ActivityParserUtils.is_valid_color_token(peek())) {
                group_color = advance().lexeme;
            } else if (check_hash_color()) {
                group_color = consume_hash_color();
            }

            // Collect group name until newline, colour or {
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check_hash_color() &&
                   !ActivityParserUtils.is_valid_color_token(peek()) && !is_at_end()) {
                Token t = advance();
                if (name_sb.len > 0 && t.space_before) {
                    name_sb.append(" ");
                }
                name_sb.append(t.lexeme);
            }

            // Check for color at end
            if (ActivityParserUtils.is_valid_color_token(peek())) {
                group_color = advance().lexeme;
            } else if (check_hash_color()) {
                group_color = consume_hash_color();
            }

            string name = name_sb.str.strip();
            // "group Name {" ... "}" is the current syntax, "end group" the old one
            bool braced = match(TokenType.LBRACE);

            // A named group is a box of its own (a key per occurrence)
            OpenBlock? block = name.length > 0 ? open_block(name, group_color) : null;

            skip_newlines_callback();

            // Parse group body until "end group" or "}"
            while (!(braced ? check(TokenType.RBRACE) : check_end_group()) && !is_at_end()) {
                int pos_before = stream.position();
                parse_statement_callback();
                skip_newlines_callback();
                // A token no statement consumes (a stray "}") looped forever
                if (stream.position() == pos_before && !is_at_end()) {
                    advance();
                }
            }

            if (braced) {
                match(TokenType.RBRACE);
            } else {
                match_end_group();
            }

            if (block != null) {
                close_block(block);
            }
        }

        // An open partition/group: its key moves when a lane switch re-opens it in
        // another lane
        private class OpenBlock {
            public string name;
            public string? color;
            public string key;
        }

        private Gee.ArrayList<OpenBlock> open_blocks = new Gee.ArrayList<OpenBlock>();

        private OpenBlock open_block(string name, string? color) {
            var partition = new ActivityPartition(name, color);
            partition.key = diagram.unique_partition_key(name);
            partition.parent = current_partition;
            diagram.partitions.add(partition);

            var block = new OpenBlock();
            block.name = name;
            block.color = color;
            block.key = partition.key;
            open_blocks.add(block);

            // The main parser assigns nodes from its own copy, so it must hear about it
            current_partition = partition.key;
            if (update_partition_callback != null) {
                update_partition_callback(current_partition);
            }
            return block;
        }

        // Back to the block's enclosing partition: the lane it ended in when a lane
        // switch happened inside it
        private void close_block(OpenBlock block) {
            open_blocks.remove(block);
            var partition = diagram.find_partition(block.key);
            current_partition = partition != null ? partition.parent : null;
            if (update_partition_callback != null) {
                update_partition_callback(current_partition);
            }
        }

        // A split colour: HASH followed by a colour name or hex code
        private bool check_hash_color() {
            if (!check(TokenType.HASH) || stream.position() + 1 >= stream.size()) {
                return false;
            }
            var next = stream.peek_at(stream.position() + 1);
            return next.token_type == TokenType.IDENTIFIER && !next.space_before &&
                ActivityParserUtils.is_color_value(next.lexeme);
        }

        private string consume_hash_color() {
            advance();  // consume #
            string color_str = advance().lexeme;
            if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                return "#" + color_str;
            }
            return color_str;
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
