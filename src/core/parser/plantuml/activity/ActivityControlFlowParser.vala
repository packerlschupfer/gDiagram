namespace GDiagram {
    /**
     * Parser for control flow structures in activity diagrams.
     * Handles if/elseif/else, while, repeat, switch, fork, and split constructs.
     */
    public class ActivityControlFlowParser : Object {
        private TokenStream stream;
        private ActivityDiagram diagram;
        private ActivityNode? last_node;
        private Gee.ArrayList<ActivityNode> pending_breaks;

        // Colour of a "#pink:if (...)" prefix, consumed by the next parse_if()
        public string? prefix_color = null;

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

        // Delegate for updating last_node in main parser
        public delegate void SetLastNodeDelegate(ActivityNode? node);
        private unowned SetLastNodeDelegate? set_last_node_callback;

        // Delegate for adding to pending_connections
        public delegate void AddToPendingDelegate(ActivityNode node, string? label, bool no_branch);
        private unowned AddToPendingDelegate? add_to_pending_callback;

        // Delegate for getting last_node from main parser
        public delegate ActivityNode? GetLastNodeDelegate();
        private unowned GetLastNodeDelegate? get_last_node_callback;

        // Delegate for dropping a node from pending_connections
        public delegate void RemovePendingDelegate(ActivityNode node);
        private unowned RemovePendingDelegate? remove_pending_callback;

        // Delegate turning pending connections into a point node (see flush_pending)
        public delegate void FlushPendingDelegate();
        private unowned FlushPendingDelegate? flush_pending_callback;

        // Terminated branch ends (kill/detach/end/stop) of an if without else:
        // the next node is ranked below them, as PlantUML continues the flow
        // under the whole if rather than beside the terminated branch
        public Gee.ArrayList<ActivityNode>? rank_after_terminals = null;

        public ActivityControlFlowParser(
            TokenStream stream,
            ActivityDiagram diagram,
            Gee.ArrayList<ActivityNode> pending_breaks
        ) {
            this.stream = stream;
            this.diagram = diagram;
            this.pending_breaks = pending_breaks;
        }

        public void set_callbacks(
            ParseStatementDelegate parse_stmt,
            AddNodeDelegate add_node,
            SkipNewlinesDelegate skip_nl,
            ConsumeUntilRparenDelegate consume_rparen,
            SetLastNodeDelegate? set_last_node = null,
            AddToPendingDelegate? add_to_pending = null,
            GetLastNodeDelegate? get_last_node = null,
            RemovePendingDelegate? remove_pending = null,
            FlushPendingDelegate? flush_pending = null
        ) {
            this.parse_statement_callback = parse_stmt;
            this.add_node_callback = add_node;
            this.skip_newlines_callback = skip_nl;
            this.consume_until_rparen_callback = consume_rparen;
            this.set_last_node_callback = set_last_node;
            this.add_to_pending_callback = add_to_pending;
            this.get_last_node_callback = get_last_node;
            this.remove_pending_callback = remove_pending;
            this.flush_pending_callback = flush_pending;
        }

        // Pending connections left by the end of a branch or loop body (the exit of a
        // while, an if without else) become an invisible point that is the body's last
        // node. Left pending, they connected to whatever statement came next: the
        // start of an else branch, or nothing at a repeat condition.
        private void flush_pending() {
            if (flush_pending_callback != null) {
                flush_pending_callback();
            }
        }

        public void set_last_node(ActivityNode? node) {
            this.last_node = node;
        }

        // An else branch starts: a note before its first element belongs to the condition
        // (the branch has no last node, the condition connects through pending)
        public signal void branch_started(ActivityNode condition);

        public ActivityNode? get_last_node() {
            return this.last_node;
        }

        /**
         * Parse if/elseif/else/endif statement.
         */
        public void parse_if(int source_line) throws Error {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] parse_if() ENTERED at line %d\n", source_line);

            // Track all branch ends for connecting to merge
            var branch_ends = new Gee.ArrayList<ActivityNode>();

            // Check for optional color: if (#color) (condition)
            string? if_color = prefix_color;
            prefix_color = null;
            if (match(TokenType.LPAREN)) {
                // "(#color)" is one colour token followed by ")(", or HASH + name
                bool color_token = ActivityParserUtils.is_color_token(peek()) &&
                    stream.peek_at(stream.current + 1).token_type == TokenType.RPAREN &&
                    stream.peek_at(stream.current + 2).token_type == TokenType.LPAREN;
                if (color_token || check(TokenType.HASH)) {
                    match(TokenType.HASH);
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

            // Check for "is (label)" after condition (alternative to "then (label)")
            string yes_label = "";  // PlantUML draws no branch label unless one is written
            string? yes_label_color = null;
            skip_whitespace_only();
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "is") {
                advance();  // consume "is"
                skip_whitespace_only();
                if (match(TokenType.LPAREN)) {
                    yes_label = consume_until_rparen_callback();

                    // Extract and strip inline color syntax: <color:X>text
                    string compact = yes_label.replace(" ", "");
                    if (compact.has_prefix("<color:")) {
                        int color_end = compact.index_of(">");
                        if (color_end > 7) {
                            // Extract color (between <color: and >)
                            yes_label_color = compact.substring(7, color_end - 7);

                            // Extract text after >
                            int orig_start = yes_label.index_of(">") + 1;
                            if (orig_start < yes_label.length) {
                                yes_label = yes_label.substring(orig_start).strip();
                            }
                        }
                    }
                }
            }

            var cond_node = new ActivityNode(ActivityNodeType.CONDITION, condition, source_line);
            cond_node.color = if_color;
            add_node_callback(cond_node);
            last_node = cond_node;
            int branch_nodes_start = diagram.nodes.size;

            // Parse 'then' branch label (if not already parsed via "is")
            skip_newlines_callback();
            if (match(TokenType.THEN)) {
                if (match(TokenType.LPAREN)) {
                    string then_label = consume_until_rparen_callback();

                    // Extract and strip inline color syntax
                    string compact = then_label.replace(" ", "");
                    if (compact.has_prefix("<color:")) {
                        int color_end = compact.index_of(">");
                        if (color_end > 7) {
                            // Extract color
                            yes_label_color = compact.substring(7, color_end - 7);

                            // Extract text
                            int end_idx = then_label.index_of(">");
                            if (end_idx > 0 && end_idx < then_label.length) {
                                yes_label = then_label.substring(end_idx + 1).strip();
                            }
                        }
                    } else {
                        yes_label = then_label;
                    }
                }
            }
            cond_node.condition_yes = yes_label;

            // Parse 'then' branch statements
            skip_newlines_callback();
            last_node = cond_node;

            // Sync with main parser's last_node
            if (set_last_node_callback != null) {
                set_last_node_callback(cond_node);
            }

            if (debug) print("[DEBUG]   Parsing THEN branch (last_node set to condition node: %s)...\n", cond_node.id);

            // Safety: prevent infinite loop. A nested if/while/fork is parsed whole by
            // the statement callback, so every else/elseif/endif met here is this if's.
            // (Counting nesting depth here never saw the nested endif, which the nested
            // parse consumed, so the outer else/endif were swallowed.)
            int max_iterations = stream.size() * 2;
            int iterations = 0;
            int pos_before;

            while (!is_at_end() && iterations < max_iterations) {
                if (check(TokenType.ELSE) || check(TokenType.ELSEIF) || check(TokenType.ENDIF)) {
                    break;
                }

                pos_before = stream.position();
                if (debug && iterations > 0 && iterations % 20 == 0) {
                    print("[DEBUG]     THEN loop iteration %d, token='%s'\n", iterations, peek().lexeme);
                }

                parse_statement_callback();
                skip_newlines_callback();
                iterations++;

                // Force advance if stuck
                if (stream.position() == pos_before && !is_at_end()) {
                    stream.advance();
                }
            }

            if (debug) print("[DEBUG]   THEN branch complete after %d iterations\n", iterations);

            // A branch ending in a construct whose exit is still pending (a while, an if
            // without else) gets a point to continue from, so the exit joins this if's
            // merge instead of whatever statement comes next
            flush_pending();

            // Sync last_node from main parser after THEN branch
            if (get_last_node_callback != null) {
                last_node = get_last_node_callback();
                if (debug) print("[DEBUG]   Synced last_node from main parser: %s\n", last_node != null ? last_node.id : "null");
            }

            // Mark the yes branch edge with label and label color
            foreach (var edge in diagram.edges) {
                if (edge.from == cond_node) {
                    // An arrow label at the start of the branch stays when "then" has none
                    if (yes_label.length > 0 || edge.label == null) {
                        edge.label = yes_label;
                    }
                    edge.is_yes_branch = true;
                    if (yes_label_color != null) {
                        edge.label_color = yes_label_color;  // Only color the label, not arrow
                    }
                    break;
                }
            }

            // Branches with no statements go straight from their condition to the merge
            var direct_from = new Gee.ArrayList<ActivityNode>();
            var direct_labels = new Gee.ArrayList<string>();
            var direct_yes = new Gee.ArrayList<bool>();

            if (last_node != null && last_node == cond_node) {
                direct_from.add(cond_node);
                direct_labels.add(yes_label);
                direct_yes.add(true);
            } else if (last_node != null) {
                if (debug) print("[DEBUG]   Adding THEN branch end to merge list: %s\n", last_node.id);
                branch_ends.add(last_node);
            } else {
                if (debug) print("[DEBUG]   THEN branch: last_node is %s, not adding to branch_ends\n", last_node != null ? last_node.id : "null");
            }

            // Track last condition for chaining elseif/else
            ActivityNode last_cond = cond_node;

            // Parse 'elseif' branches
            if (debug) print("[DEBUG]   Checking for ELSEIF branches...\n");
            while (match(TokenType.ELSEIF)) {
                int elseif_line = previous().line;
                if (debug) print("[DEBUG]   Found ELSEIF at line %d\n", elseif_line);

                string elseif_cond = "";
                if (match(TokenType.LPAREN)) {
                    elseif_cond = consume_until_rparen_callback();
                }

                var elseif_node = new ActivityNode(ActivityNodeType.CONDITION, elseif_cond, elseif_line);
                // Added directly, so it takes its lane/partition from the if
                elseif_node.partition = last_cond.partition;
                diagram.add_node(elseif_node);

                // Connect from previous condition's "no" branch
                var no_edge = new ActivityEdge(last_cond, elseif_node, last_cond.condition_no);
                no_edge.is_no_branch = true;
                no_edge.is_elseif = true;
                diagram.add_edge(no_edge);

                // Parse 'then' label for elseif
                string elseif_yes = "";
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

                // Sync with main parser's last_node
                if (set_last_node_callback != null) {
                    set_last_node_callback(elseif_node);
                }

                iterations = 0;
                while (!is_at_end() && iterations < max_iterations) {
                    if (check(TokenType.ELSE) || check(TokenType.ELSEIF) || check(TokenType.ENDIF)) {
                        break;
                    }

                    pos_before = stream.position();

                    parse_statement_callback();
                    skip_newlines_callback();
                    iterations++;

                    // Force advance if stuck
                    if (stream.position() == pos_before && !is_at_end()) {
                        stream.advance();
                    }
                }

                flush_pending();

                // Sync last_node from main parser after elseif branch
                if (get_last_node_callback != null) {
                    last_node = get_last_node_callback();
                    if (debug) print("[DEBUG]   Synced last_node from main parser after elseif: %s\n", last_node != null ? last_node.id : "null");
                }

                // Mark the yes branch edge
                foreach (var edge in diagram.edges) {
                    if (edge.from == elseif_node && edge.label == null) {
                        edge.label = elseif_yes;
                        edge.is_yes_branch = true;
                        break;
                    }
                }

                if (last_node != null && last_node == elseif_node) {
                    direct_from.add(elseif_node);
                    direct_labels.add(elseif_yes);
                    direct_yes.add(true);
                } else if (last_node != null) {
                    if (debug) print("[DEBUG]   Adding elseif branch end to merge list: %s\n", last_node.id);
                    branch_ends.add(last_node);
                } else {
                    if (debug) print("[DEBUG]   Elseif branch: last_node is %s, not adding to branch_ends\n", last_node != null ? last_node.id : "null");
                }

                last_cond = elseif_node;
            }

            // Parse 'else' branch
            if (debug) print("[DEBUG]   Checking for ELSE branch...\n");
            bool has_else = false;
            bool else_empty = false;
            if (match(TokenType.ELSE)) {
                has_else = true;
                if (debug) print("[DEBUG]   Found ELSE, parsing branch...\n");

                string no_label = "";
                if (match(TokenType.LPAREN)) {
                    no_label = consume_until_rparen_callback();
                }
                last_cond.condition_no = no_label;

                skip_newlines_callback();

                // For ELSE branch: Add condition to pending_connections and clear last_node
                // This ensures Option 2 connects FROM condition, not from Option 1
                if (add_to_pending_callback != null) {
                    add_to_pending_callback(last_cond, no_label, true);
                }
                if (set_last_node_callback != null) {
                    set_last_node_callback(null);
                }
                last_node = null;
                branch_started(last_cond);
                int else_nodes_start = diagram.nodes.size;

                if (debug) print("[DEBUG]   ELSE branch: added condition to pending, last_node=null\n");

                iterations = 0;
                while (!is_at_end() && iterations < max_iterations) {
                    if (check(TokenType.ENDIF)) {
                        break;
                    }

                    pos_before = stream.position();
                    if (debug && iterations > 0 && iterations % 20 == 0) {
                        print("[DEBUG]     ELSE loop iteration %d, token='%s'\n", iterations, peek().lexeme);
                    }

                    parse_statement_callback();
                    skip_newlines_callback();
                    iterations++;

                    // Force advance if stuck
                    if (stream.position() == pos_before && !is_at_end()) {
                        stream.advance();
                    }
                }

                if (debug) print("[DEBUG]   ELSE branch complete after %d iterations\n", iterations);

                else_empty = diagram.nodes.size == else_nodes_start;
                if (else_empty) {
                    // Still pending from the condition: handled with the other direct paths
                    if (remove_pending_callback != null) {
                        remove_pending_callback(last_cond);
                    }
                    direct_from.add(last_cond);
                    direct_labels.add(no_label);
                    direct_yes.add(false);
                } else {
                    flush_pending();
                }

                // Sync last_node from main parser after ELSE branch
                if (get_last_node_callback != null) {
                    last_node = get_last_node_callback();
                    if (debug) print("[DEBUG]   Synced last_node from main parser after ELSE: %s\n", last_node != null ? last_node.id : "null");
                }

                // Mark the no branch edge
                foreach (var edge in diagram.edges) {
                    if (edge.from == last_cond && !edge.is_yes_branch) {
                        // An arrow label after a bare "else" ("else\n-> why;") stays
                        if (no_label.length > 0 || edge.label == null) {
                            edge.label = no_label;
                        }
                        edge.is_no_branch = true;
                        break;
                    }
                }

                if (!else_empty && last_node != null && last_node != last_cond) {
                    if (debug) print("[DEBUG]   Adding ELSE branch end to merge list: %s\n", last_node.id);
                    branch_ends.add(last_node);
                } else {
                    if (debug) print("[DEBUG]   ELSE branch: last_node is %s, not adding to branch_ends\n", last_node != null ? last_node.id : "null");
                }
            }

            if (debug) print("[DEBUG]   Looking for ENDIF...\n");
            match(TokenType.ENDIF);
            int endif_line = previous().line;
            if (debug) print("[DEBUG]   Found ENDIF at line %d\n", endif_line);

            // Filter out terminal nodes from branch_ends
            var continuing_branches = new Gee.ArrayList<ActivityNode>();
            foreach (var branch_end in branch_ends) {
                if (branch_end.node_type != ActivityNodeType.STOP &&
                    branch_end.node_type != ActivityNodeType.END &&
                    branch_end.node_type != ActivityNodeType.KILL &&
                    branch_end.node_type != ActivityNodeType.DETACH) {
                    continuing_branches.add(branch_end);
                }
            }

            // Without else, the last condition's "no" continues past endif
            if (!has_else) {
                direct_from.add(last_cond);
                direct_labels.add(last_cond.condition_no ?? "");
                direct_yes.add(false);
            }

            int paths = continuing_branches.size + direct_from.size;
            if (paths >= 2) {
                // Merge point, as PlantUML draws it for every if whose paths rejoin
                // (also an if without else: its "no" path is one of them)
                var merge = new ActivityNode(ActivityNodeType.MERGE, null, endif_line);
                merge.partition = cond_node.partition;
                merge.color = cond_node.color;  // "#yellow:if" colours its merge too
                diagram.add_node(merge);

                if (debug) print("[DEBUG]   Created merge node: %s (partition='%s'), paths: %d\n",
                    merge.id, merge.partition ?? "(none)", paths);

                foreach (var branch_end in continuing_branches) {
                    diagram.connect(branch_end, merge);
                }
                for (int i = 0; i < direct_from.size; i++) {
                    var edge = new ActivityEdge(direct_from[i], merge, direct_labels[i]);
                    edge.is_yes_branch = direct_yes[i];
                    edge.is_no_branch = !direct_yes[i];
                    diagram.add_edge(edge);
                }

                last_node = merge;
                if (set_last_node_callback != null) {
                    set_last_node_callback(merge);
                }
            } else if (continuing_branches.size == 1) {
                // Only one branch continues - no merge needed
                last_node = continuing_branches.get(0);
                if (set_last_node_callback != null) {
                    set_last_node_callback(last_node);
                }
                if (debug) print("[DEBUG]   Single continuing branch: %s, no merge created\n", last_node.id);
            } else if (direct_from.size == 1) {
                // Every other branch terminates: the flow goes on from the condition,
                // connected to the next statement
                if (add_to_pending_callback != null) {
                    add_to_pending_callback(direct_from[0], direct_labels[0], !direct_yes[0]);
                }
                if (rank_after_terminals != null) {
                    // Terminal statements clear last_node, so they never reach
                    // branch_ends: collect the branch nodes without an outgoing edge
                    for (int i = branch_nodes_start; i < diagram.nodes.size; i++) {
                        var n = diagram.nodes[i];
                        bool has_out = false;
                        foreach (var e in diagram.edges) {
                            if (e.from == n) {
                                has_out = true;
                                break;
                            }
                        }
                        if (!has_out) {
                            rank_after_terminals.add(n);
                        }
                    }
                }
                last_node = null;
                if (set_last_node_callback != null) {
                    set_last_node_callback(null);
                }
            } else {
                // All branches explicitly terminate
                last_node = null;
                if (set_last_node_callback != null) {
                    set_last_node_callback(null);
                }
                if (debug) print("[DEBUG]   All branches terminate, no merge, last_node=null\n");
            }

            if (debug) print("[DEBUG] parse_if() EXITING normally\n");
        }

        /**
         * Parse fork/fork again/end fork statement.
         */
        public void parse_fork(int source_line) throws Error {
            // Safety: variables for loop protection
            int max_iterations = stream.size() * 2;
            int iterations = 0;
            int pos_before;

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

            // Sync with main parser
            if (set_last_node_callback != null) {
                set_last_node_callback(fork_node);
            }

            // Safety: prevent infinite loop
            iterations = 0;
            while (!check_fork_again() && !check_end_fork() && !is_at_end() && iterations < max_iterations) {
                pos_before = stream.position();
                parse_statement_callback();
                skip_newlines_callback();
                iterations++;
                if (stream.position() == pos_before && !is_at_end()) {
                    stream.advance();
                }
            }

            flush_pending();

            // Sync back from main parser
            if (get_last_node_callback != null) {
                last_node = get_last_node_callback();
            }

            if (last_node != null && last_node != fork_node) {
                branch_ends.add(last_node);
            }

            // Additional branches
            while (match_fork_again()) {
                skip_newlines_callback();
                last_node = fork_node;

                // Sync with main parser for each fork again branch
                if (set_last_node_callback != null) {
                    set_last_node_callback(fork_node);
                }

                iterations = 0;
                while (!check_fork_again() && !check_end_fork() && !is_at_end() && iterations < max_iterations) {
                    pos_before = stream.position();
                    parse_statement_callback();
                    skip_newlines_callback();
                    iterations++;
                    if (stream.position() == pos_before && !is_at_end()) {
                        stream.advance();
                    }
                }

                flush_pending();

                // Sync back from main parser
                if (get_last_node_callback != null) {
                    last_node = get_last_node_callback();
                }

                if (last_node != null && last_node != fork_node) {
                    branch_ends.add(last_node);
                }
            }

            // Consume end fork/merge and check which type
            bool is_merge = false;
            if (check(TokenType.END)) {
                advance(); // consume END
                if (check(TokenType.MERGE)) {
                    is_merge = true;
                    advance(); // consume MERGE
                } else if (check(TokenType.FORK)) {
                    advance(); // consume FORK
                }
            }
            int end_fork_line = previous().line;

            ActivityNode join_or_merge;
            if (is_merge) {
                // end merge → use MERGE diamond
                join_or_merge = new ActivityNode(ActivityNodeType.MERGE, null, end_fork_line);
                join_or_merge.partition = fork_node.partition;
            } else {
                // end fork → use JOIN bar
                join_or_merge = new ActivityNode(ActivityNodeType.JOIN, null, end_fork_line);
                join_or_merge.color = fork_color;
                join_or_merge.partition = fork_node.partition;
            }
            diagram.add_node(join_or_merge);

            foreach (var branch_end in branch_ends) {
                if (branch_end.node_type != ActivityNodeType.STOP &&
                    branch_end.node_type != ActivityNodeType.END) {
                    diagram.connect(branch_end, join_or_merge);
                }
            }

            last_node = join_or_merge;
        }

        /**
         * Parse split/split again/end split statement (non-synchronizing fork).
         */
        public void parse_split(int source_line) throws Error {
            // Safety: variables for loop protection
            int max_iterations = stream.size() * 2;
            int iterations = 0;
            int pos_before;

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
            split_node.is_split = true;
            add_node_callback(split_node);

            var branch_ends = new Gee.ArrayList<ActivityNode>();
            skip_newlines_callback();

            // First branch
            last_node = split_node;

            // Sync with main parser
            if (set_last_node_callback != null) {
                set_last_node_callback(split_node);
            }

            // Safety: prevent infinite loop
            iterations = 0;
            while (!check_split_again() && !check_end_split() && !is_at_end() && iterations < max_iterations) {
                pos_before = stream.position();
                parse_statement_callback();
                skip_newlines_callback();
                iterations++;
                if (stream.position() == pos_before && !is_at_end()) {
                    stream.advance();
                }
            }

            flush_pending();

            // Sync back from main parser
            if (get_last_node_callback != null) {
                last_node = get_last_node_callback();
            }

            if (last_node != null && last_node != split_node) {
                branch_ends.add(last_node);
            }

            // Additional branches
            while (match_split_again()) {
                skip_newlines_callback();
                last_node = split_node;

                // Sync with main parser for each split again branch
                if (set_last_node_callback != null) {
                    set_last_node_callback(split_node);
                }

                iterations = 0;
                while (!check_split_again() && !check_end_split() && !is_at_end() && iterations < max_iterations) {
                    pos_before = stream.position();
                    parse_statement_callback();
                    skip_newlines_callback();
                    iterations++;
                    if (stream.position() == pos_before && !is_at_end()) {
                        stream.advance();
                    }
                }

                flush_pending();

                // Sync back from main parser
                if (get_last_node_callback != null) {
                    last_node = get_last_node_callback();
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
            merge_node.partition = split_node.partition;
            merge_node.is_split = true;
            merge_node.color = split_color;
            diagram.add_node(merge_node);

            foreach (var branch_end in branch_ends) {
                if (branch_end.node_type != ActivityNodeType.STOP &&
                    branch_end.node_type != ActivityNodeType.END) {
                    diagram.connect(branch_end, merge_node);
                }
            }

            last_node = merge_node;
        }

        /**
         * Parse while loop.
         */
        public void parse_while(int source_line) throws Error {
            // Safety: variables for loop protection
            int max_iterations = stream.size() * 2;
            int iterations = 0;
            int pos_before;

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

            // Check for "is (label)" after condition
            string loop_label = "";
            skip_whitespace_only();
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "is") {
                advance();  // consume "is"
                skip_whitespace_only();
                if (match(TokenType.LPAREN)) {
                    loop_label = consume_until_rparen_callback();
                }
            }
            cond_node.condition_yes = loop_label;

            // Parse loop body
            skip_newlines_callback();
            last_node = cond_node;

            // Safety: prevent infinite loop
            iterations = 0;
            ActivityNode? first_body_node = null;
            while (!check(TokenType.ENDWHILE) && !is_at_end() && iterations < max_iterations) {
                pos_before = stream.position();
                int node_count_before = diagram.nodes.size;

                parse_statement_callback();

                // Track first node in loop body
                if (first_body_node == null && diagram.nodes.size > node_count_before) {
                    first_body_node = diagram.nodes.get(diagram.nodes.size - 1);
                }

                skip_newlines_callback();
                iterations++;
                if (stream.position() == pos_before && !is_at_end()) {
                    stream.advance();
                }
            }

            // Mark the entry edge to loop body (condition -> first node)
            if (first_body_node != null) {
                foreach (var edge in diagram.edges) {
                    if (edge.from == cond_node && edge.to == first_body_node) {
                        if (loop_label.length > 0 || edge.label == null) {
                            edge.label = loop_label;
                        }
                        edge.is_yes_branch = true;
                        break;
                    }
                }
            }

            flush_pending();

            // Sync last_node from main parser after loop body
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (get_last_node_callback != null) {
                last_node = get_last_node_callback();
                if (debug) print("[DEBUG]   While: synced last_node from main parser: %s\n", last_node != null ? last_node.id : "null");
            }

            // Connect back to condition with loop-back edge
            if (last_node != null && last_node != cond_node) {
                if (debug) print("[DEBUG]   While: creating loop-back edge %s -> %s\n", last_node.id, cond_node.id);
                var loop_edge = new ActivityEdge(last_node, cond_node, null);
                diagram.add_edge(loop_edge);
            } else {
                if (debug) print("[DEBUG]   While: NOT creating loop-back (last_node=%s)\n", last_node != null ? last_node.id : "null");
            }

            match(TokenType.ENDWHILE);
            int endwhile_line = previous().line;

            // Parse exit condition label
            string exit_label = "";
            if (match(TokenType.LPAREN)) {
                exit_label = consume_until_rparen_callback();
            }

            cond_node.condition_no = exit_label;

            // No merge diamond for while exit - condition's no-branch continues directly
            // Only create merge if there are break statements
            if (pending_breaks.size > 0) {
                // Create exit merge for breaks
                var exit_node = new ActivityNode(ActivityNodeType.MERGE, null, endwhile_line);
                exit_node.partition = cond_node.partition;
                diagram.add_node(exit_node);

                var exit_edge = new ActivityEdge(cond_node, exit_node, exit_label);
                exit_edge.is_no_branch = true;
                diagram.add_edge(exit_edge);

                foreach (var break_node in pending_breaks) {
                    diagram.connect(break_node, exit_node);
                }
                pending_breaks.clear();

                last_node = exit_node;

                if (set_last_node_callback != null) {
                    set_last_node_callback(exit_node);
                }
            } else {
                // No breaks - condition's no-branch continues via pending
                if (add_to_pending_callback != null) {
                    add_to_pending_callback(cond_node, exit_label, false);
                }

                last_node = null;

                if (set_last_node_callback != null) {
                    set_last_node_callback(null);
                }
            }
        }

        /**
         * Parse repeat/repeat while loop.
         */
        public void parse_repeat(int source_line) throws Error {
            // Safety: variables for loop protection
            int max_iterations = stream.size() * 2;
            int iterations = 0;
            int pos_before;

            // Check for starting label: repeat :label; — on the same line only.
            // Skipping newlines first took the body's first action as the label,
            // which dropped the start diamond.
            ActivityNode repeat_start;
            if (match(TokenType.COLON)) {
                // Parse starting label action
                var sb = new StringBuilder();
                while (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    if (sb.len > 0 && t.space_before) sb.append(" ");
                    sb.append(t.lexeme);
                }
                match(TokenType.SEMICOLON);

                string label = sb.str.strip();
                repeat_start = new ActivityNode(ActivityNodeType.ACTION, label, source_line);
                add_node_callback(repeat_start);
            } else {
                // No starting label - use merge diamond as entry
                repeat_start = new ActivityNode(ActivityNodeType.MERGE, null, source_line);
                add_node_callback(repeat_start);
            }

            skip_newlines_callback();

            // Parse loop body until "repeat while" or "backward"
            string? backward_label = null;

            // Safety: prevent infinite loop
            iterations = 0;
            while (!check_repeat_while() && !check_backward() && !is_at_end() && iterations < max_iterations) {
                pos_before = stream.position();
                parse_statement_callback();
                skip_newlines_callback();
                iterations++;
                if (stream.position() == pos_before && !is_at_end()) {
                    stream.advance();
                }
            }

            // Check for backward label
            if (match_backward()) {
                // Parse backward action text
                if (match(TokenType.COLON)) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.SEMICOLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        Token t = advance();
                        if (sb.len > 0 && t.space_before) sb.append(" ");
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
            string yes_label = "";  // PlantUML draws no branch label unless one is written
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "is") {
                advance();  // consume "is"
                if (match(TokenType.LPAREN)) {
                    yes_label = consume_until_rparen_callback();
                }
            }

            // Optional "not (no)" label
            string no_label = "";
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "not") {
                advance();  // consume "not"
                if (match(TokenType.LPAREN)) {
                    no_label = consume_until_rparen_callback();
                }
            }

            int repeat_while_line = previous().line;  // "repeat while" keyword line
            // Sync last_node from main parser after repeat body
            if (get_last_node_callback != null) {
                last_node = get_last_node_callback();
            }

            var cond_node = new ActivityNode(ActivityNodeType.CONDITION, condition, repeat_while_line);
            cond_node.condition_yes = yes_label;
            cond_node.condition_no = no_label;
            // Connected like any statement: from the body end, and from what is still
            // pending when the body ends in a while or in an if without else whose branch
            // stops (only the body end was connected, so the condition had no way in)
            ActivityNode? body_end = last_node;
            add_node_callback(cond_node);
            // The condition belongs to the lane/partition of the loop body end
            if (body_end != null) {
                cond_node.partition = body_end.partition;
            }

            // Loop back edge (when condition is true)
            string loop_label = backward_label != null ? backward_label : yes_label;
            var loop_edge = new ActivityEdge(cond_node, repeat_start, loop_label);
            loop_edge.is_yes_branch = true;
            diagram.add_edge(loop_edge);

            // Exit node (when condition is false)
            var exit_node = new ActivityNode(ActivityNodeType.MERGE, null, repeat_while_line);
            exit_node.partition = cond_node.partition;
            // PlantUML draws no diamond at a repeat exit without breaks
            exit_node.passthrough = true;
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
        }

        /**
         * Parse switch/case/endswitch statement.
         */
        public void parse_switch(int source_line) throws Error {
            // Safety: variables for loop protection
            int max_iterations = stream.size() * 2;
            int iterations = 0;
            int pos_before;

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

                // Sync with main parser for each case
                if (set_last_node_callback != null) {
                    set_last_node_callback(switch_node);
                }

                // Track first node in case for labeling
                ActivityNode? first_case_node = null;

                // Parse case body
                // Safety: prevent infinite loop
                iterations = 0;
                while (!check(TokenType.CASE) && !check(TokenType.ENDSWITCH) && !is_at_end() && iterations < max_iterations) {
                    int before_count = diagram.nodes.size;
                    pos_before = stream.position();
                    parse_statement_callback();

                    // Track first node in case
                    if (first_case_node == null && diagram.nodes.size > before_count) {
                        first_case_node = diagram.nodes.get(diagram.nodes.size - 1);
                    }

                    skip_newlines_callback();
                    iterations++;
                    if (stream.position() == pos_before && !is_at_end()) {
                        stream.advance();
                    }
                }

                // Label the edge from switch to first node in case
                if (first_case_node != null) {
                    foreach (var edge in diagram.edges) {
                        if (edge.from == switch_node && edge.to == first_case_node) {
                            edge.label = case_label;
                            break;
                        }
                    }
                }

                flush_pending();

                // Sync back from main parser
                if (get_last_node_callback != null) {
                    last_node = get_last_node_callback();
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
            merge.partition = switch_node.partition;
            diagram.add_node(merge);

            foreach (var case_end in case_ends) {
                if (case_end.node_type != ActivityNodeType.STOP &&
                    case_end.node_type != ActivityNodeType.END) {
                    diagram.connect(case_end, merge);
                }
            }

            last_node = merge;
        }

        // Helper methods for checking compound keywords
        private bool check_split_again() {
            if (check(TokenType.SPLIT) && check_next(TokenType.IDENTIFIER)) {
                if (stream.position() + 1 < stream.size() && stream.peek_at(stream.position() + 1).lexeme.down() == "again") {
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
                if (stream.position() + 1 < stream.size()) {
                    var next = stream.peek_at(stream.position() + 1);
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

        private bool check_fork_again() {
            if (check(TokenType.FORK) && check_next(TokenType.IDENTIFIER)) {
                if (stream.position() + 1 < stream.size() && stream.peek_at(stream.position() + 1).lexeme.down() == "again") {
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
            return stream.match(type);
        }

        private bool check(TokenType type) {
            return stream.check(type);
        }

        private bool check_next(TokenType type) {
            if (stream.position() + 1 >= stream.size()) return false;
            return stream.peek_at(stream.position() + 1).token_type == type;
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
