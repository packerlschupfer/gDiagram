namespace GPlantUML {
    /**
     * Parser for control flow structures in activity diagrams.
     * Handles if/elseif/else, while, repeat, switch, fork, and split constructs.
     */
    public class ActivityControlFlowParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ActivityDiagram diagram;
        private ActivityNode? last_node;
        private Gee.ArrayList<ActivityNode> pending_breaks;

        // Delegate for parsing sub-statements
        public delegate void ParseStatementDelegate() throws Error;
        private unowned ParseStatementDelegate parse_statement_callback;

        // Delegate for adding nodes with connections
        public delegate void AddNodeDelegate(ActivityNode node);
        private unowned AddNodeDelegate add_node_callback;

        // Delegate for skipping newlines
        public delegate void SkipNewlinesDelegate();
        private unowned SkipNewlinesDelegate skip_newlines_callback;

        // Delegate for consuming until rparen
        public delegate string ConsumeUntilRparenDelegate();
        private unowned ConsumeUntilRparenDelegate consume_until_rparen_callback;

        public ActivityControlFlowParser(
            Gee.ArrayList<Token> tokens,
            ref int current,
            ActivityDiagram diagram,
            Gee.ArrayList<ActivityNode> pending_breaks
        ) {
            this.tokens = tokens;
            this.current = current;
            this.diagram = diagram;
            this.pending_breaks = pending_breaks;
        }

        public void set_callbacks(
            ParseStatementDelegate parse_stmt,
            AddNodeDelegate add_node,
            SkipNewlinesDelegate skip_nl,
            ConsumeUntilRparenDelegate consume_rparen
        ) {
            this.parse_statement_callback = parse_stmt;
            this.add_node_callback = add_node;
            this.skip_newlines_callback = skip_nl;
            this.consume_until_rparen_callback = consume_rparen;
        }

        public void set_last_node(ActivityNode? node) {
            this.last_node = node;
        }

        public ActivityNode? get_last_node() {
            return this.last_node;
        }

        /**
         * Parse if/elseif/else/endif statement.
         */
        public void parse_if(ref int position, int source_line) throws Error {
            current = position;

            // Track all branch ends for connecting to merge
            var branch_ends = new Gee.ArrayList<ActivityNode>();

            // Check for optional color: if (#color) (condition)
            string? if_color = null;
            if (match(TokenType.LPAREN)) {
                if (check(TokenType.HASH)) {
                    advance();  // consume #
                    var color_sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !is_at_end()) {
                        color_sb.append(advance().lexeme);
                    }
                    match(TokenType.RPAREN);
                    if_color = color_sb.str.strip();
                    // Now parse the actual condition
                    if (match(TokenType.LPAREN)) {
                        // condition follows
                    }
                }
            }

            // Parse first condition
            string condition = "";
            if (previous().token_type == TokenType.LPAREN || match(TokenType.LPAREN)) {
                condition = consume_until_rparen_callback();
            }

            var cond_node = new ActivityNode(ActivityNodeType.CONDITION, condition, source_line);
            cond_node.color = if_color;
            add_node_callback(cond_node);
            last_node = cond_node;

            // Parse 'then' branch label
            string yes_label = "yes";
            skip_newlines_callback();
            if (match(TokenType.THEN)) {
                if (match(TokenType.LPAREN)) {
                    yes_label = consume_until_rparen_callback();
                }
            }
            cond_node.condition_yes = yes_label;

            // Parse 'then' branch statements
            skip_newlines_callback();
            last_node = cond_node;

            while (!check(TokenType.ELSE) && !check(TokenType.ELSEIF) &&
                   !check(TokenType.ENDIF) && !is_at_end()) {
                parse_statement_callback();
                skip_newlines_callback();
            }

            // Mark the yes branch edge
            foreach (var edge in diagram.edges) {
                if (edge.from == cond_node) {
                    edge.label = yes_label;
                    edge.is_yes_branch = true;
                    break;
                }
            }

            if (last_node != null && last_node != cond_node) {
                branch_ends.add(last_node);
            }

            // Track last condition for chaining elseif/else
            ActivityNode last_cond = cond_node;

            // Parse 'elseif' branches
            while (match(TokenType.ELSEIF)) {
                int elseif_line = previous().line;
                string elseif_cond = "";
                if (match(TokenType.LPAREN)) {
                    elseif_cond = consume_until_rparen_callback();
                }

                var elseif_node = new ActivityNode(ActivityNodeType.CONDITION, elseif_cond, elseif_line);
                diagram.add_node(elseif_node);

                // Connect from previous condition's "no" branch
                var no_edge = new ActivityEdge(last_cond, elseif_node, last_cond.condition_no);
                no_edge.is_no_branch = true;
                diagram.add_edge(no_edge);

                // Parse 'then' label for elseif
                string elseif_yes = "yes";
                skip_newlines_callback();
                if (match(TokenType.THEN)) {
                    if (match(TokenType.LPAREN)) {
                        elseif_yes = consume_until_rparen_callback();
                    }
                }
                elseif_node.condition_yes = elseif_yes;

                // Parse elseif branch statements
                skip_newlines_callback();
                last_node = elseif_node;

                while (!check(TokenType.ELSE) && !check(TokenType.ELSEIF) &&
                       !check(TokenType.ENDIF) && !is_at_end()) {
                    parse_statement_callback();
                    skip_newlines_callback();
                }

                // Mark the yes branch edge
                foreach (var edge in diagram.edges) {
                    if (edge.from == elseif_node && edge.label == null) {
                        edge.label = elseif_yes;
                        edge.is_yes_branch = true;
                        break;
                    }
                }

                if (last_node != null && last_node != elseif_node) {
                    branch_ends.add(last_node);
                }

                last_cond = elseif_node;
            }

            // Parse 'else' branch
            if (match(TokenType.ELSE)) {
                string no_label = "no";
                if (match(TokenType.LPAREN)) {
                    no_label = consume_until_rparen_callback();
                }
                last_cond.condition_no = no_label;

                skip_newlines_callback();
                last_node = last_cond;

                while (!check(TokenType.ENDIF) && !is_at_end()) {
                    parse_statement_callback();
                    skip_newlines_callback();
                }

                // Mark the no branch edge
                foreach (var edge in diagram.edges) {
                    if (edge.from == last_cond && !edge.is_yes_branch) {
                        edge.label = no_label;
                        edge.is_no_branch = true;
                        break;
                    }
                }

                if (last_node != null && last_node != last_cond) {
                    branch_ends.add(last_node);
                }
            }

            match(TokenType.ENDIF);
            int endif_line = previous().line;

            // Create merge point
            var merge = new ActivityNode(ActivityNodeType.MERGE, null, endif_line);
            diagram.add_node(merge);

            // Connect all branch ends to merge
            foreach (var branch_end in branch_ends) {
                if (branch_end.node_type != ActivityNodeType.STOP &&
                    branch_end.node_type != ActivityNodeType.END) {
                    diagram.connect(branch_end, merge);
                }
            }

            // If no else branch, connect last condition's no to merge
            if (!check(TokenType.ELSE)) {
                bool has_else_connection = false;
                foreach (var edge in diagram.edges) {
                    if (edge.from == last_cond && edge.is_no_branch) {
                        has_else_connection = true;
                        break;
                    }
                }
                if (!has_else_connection) {
                    var no_edge = new ActivityEdge(last_cond, merge, last_cond.condition_no);
                    no_edge.is_no_branch = true;
                    diagram.add_edge(no_edge);
                }
            }

            last_node = merge;
            position = current;
        }

        /**
         * Parse fork/fork again/end fork statement.
         */
        public void parse_fork(ref int position, int source_line) throws Error {
            current = position;

            // Check for optional color: fork (#color) or fork (color)
            string? fork_color = null;
            if (match(TokenType.LPAREN)) {
                var color_sb = new StringBuilder();
                bool had_hash = false;
                if (check(TokenType.HASH)) {
                    had_hash = true;
                    advance();  // consume #
                }
                while (!check(TokenType.RPAREN) && !is_at_end()) {
                    color_sb.append(advance().lexeme);
                }
                string color_str = color_sb.str.strip();
                // Keep # only for hex colors (e.g., #FF0000), otherwise use name directly
                if (had_hash && color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                    fork_color = "#" + color_str;
                } else {
                    fork_color = color_str;
                }
                match(TokenType.RPAREN);
            }

            var fork_node = new ActivityNode(ActivityNodeType.FORK, null, source_line);
            fork_node.color = fork_color;
            add_node_callback(fork_node);

            var branch_ends = new Gee.ArrayList<ActivityNode>();
            skip_newlines_callback();

            // First branch
            last_node = fork_node;
            while (!check_fork_again() && !check_end_fork() && !is_at_end()) {
                parse_statement_callback();
                skip_newlines_callback();
            }
            if (last_node != null && last_node != fork_node) {
                branch_ends.add(last_node);
            }

            // Additional branches
            while (match_fork_again()) {
                skip_newlines_callback();
                last_node = fork_node;

                while (!check_fork_again() && !check_end_fork() && !is_at_end()) {
                    parse_statement_callback();
                    skip_newlines_callback();
                }
                if (last_node != null && last_node != fork_node) {
                    branch_ends.add(last_node);
                }
            }

            // Consume end fork
            match_end_fork();
            int end_fork_line = previous().line;

            // Join node (same color as fork)
            var join_node = new ActivityNode(ActivityNodeType.JOIN, null, end_fork_line);
            join_node.color = fork_color;
            diagram.add_node(join_node);

            foreach (var branch_end in branch_ends) {
                if (branch_end.node_type != ActivityNodeType.STOP &&
                    branch_end.node_type != ActivityNodeType.END) {
                    diagram.connect(branch_end, join_node);
                }
            }

            last_node = join_node;
            position = current;
        }

        /**
         * Parse split/split again/end split statement (non-synchronizing fork).
         */
        public void parse_split(ref int position, int source_line) throws Error {
            current = position;

            // Check for optional color: split (color)
            string? split_color = null;
            if (match(TokenType.LPAREN)) {
                var color_sb = new StringBuilder();
                if (check(TokenType.HASH)) {
                    advance();  // consume #
                }
                while (!check(TokenType.RPAREN) && !is_at_end()) {
                    color_sb.append(advance().lexeme);
                }
                string color_str = color_sb.str.strip();
                if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                    split_color = "#" + color_str;
                } else {
                    split_color = color_str;
                }
                match(TokenType.RPAREN);
            }

            // Split is like fork but branches don't synchronize
            var split_node = new ActivityNode(ActivityNodeType.FORK, null, source_line);
            split_node.color = split_color;
            add_node_callback(split_node);

            var branch_ends = new Gee.ArrayList<ActivityNode>();
            skip_newlines_callback();

            // First branch
            last_node = split_node;
            while (!check_split_again() && !check_end_split() && !is_at_end()) {
                parse_statement_callback();
                skip_newlines_callback();
            }
            if (last_node != null && last_node != split_node) {
                branch_ends.add(last_node);
            }

            // Additional branches
            while (match_split_again()) {
                skip_newlines_callback();
                last_node = split_node;

                while (!check_split_again() && !check_end_split() && !is_at_end()) {
                    parse_statement_callback();
                    skip_newlines_callback();
                }
                if (last_node != null && last_node != split_node) {
                    branch_ends.add(last_node);
                }
            }

            // Consume end split
            match_end_split();
            int end_split_line = previous().line;

            // Merge node (not join - paths don't synchronize)
            var merge_node = new ActivityNode(ActivityNodeType.MERGE, null, end_split_line);
            diagram.add_node(merge_node);

            foreach (var branch_end in branch_ends) {
                if (branch_end.node_type != ActivityNodeType.STOP &&
                    branch_end.node_type != ActivityNodeType.END) {
                    diagram.connect(branch_end, merge_node);
                }
            }

            last_node = merge_node;
            position = current;
        }

        /**
         * Parse while loop.
         */
        public void parse_while(ref int position, int source_line) throws Error {
            current = position;

            // Check for optional color: while (#color) (condition) or while (color) (condition)
            string? while_color = null;
            string condition = "";

            if (match(TokenType.LPAREN)) {
                // Check if this looks like a color (starts with # or is a color name followed by another paren)
                if (check(TokenType.HASH)) {
                    advance();  // consume #
                    var color_sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !is_at_end()) {
                        color_sb.append(advance().lexeme);
                    }
                    string color_str = color_sb.str.strip();
                    if (color_str.length == 6 && ActivityParserUtils.is_hex_color(color_str)) {
                        while_color = "#" + color_str;
                    } else {
                        while_color = color_str;
                    }
                    match(TokenType.RPAREN);
                    // Now parse the actual condition
                    if (match(TokenType.LPAREN)) {
                        condition = consume_until_rparen_callback();
                    }
                } else {
                    // Could be color without # or could be the condition
                    // Peek ahead: if there's another ( after ), it's a color
                    string first_content = consume_until_rparen_callback();
                    skip_whitespace_only();
                    if (check(TokenType.LPAREN)) {
                        // First was color, now parse condition
                        while_color = first_content;
                        match(TokenType.LPAREN);
                        condition = consume_until_rparen_callback();
                    } else {
                        // First was the condition
                        condition = first_content;
                    }
                }
            }

            var cond_node = new ActivityNode(ActivityNodeType.CONDITION, condition, source_line);
            cond_node.color = while_color;
            add_node_callback(cond_node);

            // Parse loop body
            skip_newlines_callback();
            last_node = cond_node;

            while (!check(TokenType.ENDWHILE) && !is_at_end()) {
                parse_statement_callback();
                skip_newlines_callback();
            }

            // Connect back to condition
            if (last_node != null && last_node != cond_node) {
                diagram.connect(last_node, cond_node);
            }

            match(TokenType.ENDWHILE);
            int endwhile_line = previous().line;

            // Parse exit condition label
            string exit_label = "";
            if (match(TokenType.LPAREN)) {
                exit_label = consume_until_rparen_callback();
            }

            // Create exit merge point
            var exit_node = new ActivityNode(ActivityNodeType.MERGE, null, endwhile_line);
            diagram.add_node(exit_node);

            var exit_edge = new ActivityEdge(cond_node, exit_node, exit_label);
            diagram.add_edge(exit_edge);

            // Connect any pending breaks to exit
            foreach (var break_node in pending_breaks) {
                diagram.connect(break_node, exit_node);
            }
            pending_breaks.clear();

            last_node = exit_node;
            position = current;
        }

        /**
         * Parse repeat/repeat while loop.
         */
        public void parse_repeat(ref int position, int source_line) throws Error {
            current = position;

            var repeat_start = new ActivityNode(ActivityNodeType.MERGE, null, source_line);
            add_node_callback(repeat_start);

            skip_newlines_callback();

            // Parse loop body until "repeat while" or "backward"
            string? backward_label = null;
            while (!check_repeat_while() && !check_backward() && !is_at_end()) {
                parse_statement_callback();
                skip_newlines_callback();
            }

            // Check for backward label
            if (match_backward()) {
                // Parse backward action text
                if (match(TokenType.COLON)) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        Token t = advance();
                        if (sb.len > 0) sb.append(" ");
                        sb.append(t.lexeme);
                    }
                    match(TokenType.SEMICOLON);
                    backward_label = sb.str.strip();
                }
                skip_newlines_callback();
            }

            // Consume "repeat while"
            match_repeat_while();

            string condition = "";
            if (match(TokenType.LPAREN)) {
                condition = consume_until_rparen_callback();
            }

            // Optional "is (yes)" label
            string yes_label = "yes";
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "is") {
                advance();  // consume "is"
                if (match(TokenType.LPAREN)) {
                    yes_label = consume_until_rparen_callback();
                }
            }

            // Optional "not (no)" label
            string no_label = "no";
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "not") {
                advance();  // consume "not"
                if (match(TokenType.LPAREN)) {
                    no_label = consume_until_rparen_callback();
                }
            }

            int repeat_while_line = previous().line;  // "repeat while" keyword line
            var cond_node = new ActivityNode(ActivityNodeType.CONDITION, condition, repeat_while_line);
            cond_node.condition_yes = yes_label;
            cond_node.condition_no = no_label;
            diagram.add_node(cond_node);
            if (last_node != null) {
                diagram.connect(last_node, cond_node);
            }

            // Loop back edge (when condition is true)
            string loop_label = backward_label != null ? backward_label : yes_label;
            var loop_edge = new ActivityEdge(cond_node, repeat_start, loop_label);
            loop_edge.is_yes_branch = true;
            diagram.add_edge(loop_edge);

            // Exit node (when condition is false)
            var exit_node = new ActivityNode(ActivityNodeType.MERGE, null, repeat_while_line);
            diagram.add_node(exit_node);
            var exit_edge = new ActivityEdge(cond_node, exit_node, no_label);
            exit_edge.is_no_branch = true;
            diagram.add_edge(exit_edge);

            // Connect any pending breaks to exit
            foreach (var break_node in pending_breaks) {
                diagram.connect(break_node, exit_node);
            }
            pending_breaks.clear();

            last_node = exit_node;
            position = current;
        }

        /**
         * Parse switch/case/endswitch statement.
         */
        public void parse_switch(ref int position, int source_line) throws Error {
            current = position;

            // Parse switch condition
            string condition = "";
            if (match(TokenType.LPAREN)) {
                condition = consume_until_rparen_callback();
            }

            var switch_node = new ActivityNode(ActivityNodeType.CONDITION, condition, source_line);
            add_node_callback(switch_node);

            var case_ends = new Gee.ArrayList<ActivityNode>();
            skip_newlines_callback();

            // Parse case branches
            while (match(TokenType.CASE)) {
                string case_label = "";
                if (match(TokenType.LPAREN)) {
                    case_label = consume_until_rparen_callback();
                }

                skip_newlines_callback();

                // Connect switch to this case branch
                last_node = switch_node;

                // Track if this is the first statement in the case
                bool first_in_case = true;

                // Parse case body
                while (!check(TokenType.CASE) && !check(TokenType.ENDSWITCH) && !is_at_end()) {
                    int before_count = diagram.nodes.size;
                    parse_statement_callback();

                    // Label the first edge from switch to this case
                    if (first_in_case && diagram.nodes.size > before_count) {
                        foreach (var edge in diagram.edges) {
                            if (edge.from == switch_node && edge.to == last_node) {
                                edge.label = case_label;
                                break;
                            }
                        }
                        first_in_case = false;
                    }

                    skip_newlines_callback();
                }

                // Save the end of this case branch
                if (last_node != null && last_node != switch_node) {
                    case_ends.add(last_node);
                }
            }

            match(TokenType.ENDSWITCH);
            int endswitch_line = previous().line;

            // Create merge point for all case branches
            var merge = new ActivityNode(ActivityNodeType.MERGE, null, endswitch_line);
            diagram.add_node(merge);

            foreach (var case_end in case_ends) {
                if (case_end.node_type != ActivityNodeType.STOP &&
                    case_end.node_type != ActivityNodeType.END) {
                    diagram.connect(case_end, merge);
                }
            }

            last_node = merge;
            position = current;
        }

        // Helper methods for checking compound keywords
        private bool check_split_again() {
            if (check(TokenType.SPLIT) && check_next(TokenType.IDENTIFIER)) {
                if (current + 1 < tokens.size && tokens.get(current + 1).lexeme.down() == "again") {
                    return true;
                }
            }
            return false;
        }

        private bool match_split_again() {
            if (check_split_again()) {
                advance();  // SPLIT
                advance();  // again
                return true;
            }
            return false;
        }

        private bool check_end_split() {
            if (check(TokenType.END)) {
                if (current + 1 < tokens.size) {
                    var next = tokens.get(current + 1);
                    if (next.token_type == TokenType.SPLIT) {
                        return true;
                    }
                }
            }
            return false;
        }

        private bool match_end_split() {
            if (check_end_split()) {
                advance();  // END
                advance();  // SPLIT
                return true;
            }
            return false;
        }

        private bool check_end_fork() {
            if (check(TokenType.END)) {
                if (check_next(TokenType.FORK) || check_next(TokenType.MERGE)) {
                    return true;
                }
            }
            return false;
        }

        private bool match_end_fork() {
            if (check(TokenType.END)) {
                if (check_next(TokenType.FORK) || check_next(TokenType.MERGE)) {
                    advance();
                    advance();
                    return true;
                }
            }
            return false;
        }

        private bool check_fork_again() {
            if (check(TokenType.FORK) && check_next(TokenType.IDENTIFIER)) {
                if (current + 1 < tokens.size && tokens.get(current + 1).lexeme.down() == "again") {
                    return true;
                }
            }
            return false;
        }

        private bool match_fork_again() {
            if (check_fork_again()) {
                advance();
                advance();
                return true;
            }
            return false;
        }

        private bool check_repeat_while() {
            if (check(TokenType.REPEAT) && check_next(TokenType.WHILE)) {
                return true;
            }
            return false;
        }

        private bool match_repeat_while() {
            if (check(TokenType.REPEAT) && check_next(TokenType.WHILE)) {
                advance();
                advance();
                return true;
            }
            return false;
        }

        private bool check_backward() {
            return check(TokenType.BACKWARD);
        }

        private bool match_backward() {
            if (check(TokenType.BACKWARD)) {
                advance();
                return true;
            }
            return false;
        }

        private void skip_whitespace_only() {
            // Skip whitespace tokens but not newlines
            while (!is_at_end() && check(TokenType.NEWLINE)) {
                // Don't skip newlines here
                break;
            }
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

        private bool check_next(TokenType type) {
            if (current + 1 >= tokens.size) return false;
            return tokens.get(current + 1).token_type == type;
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
