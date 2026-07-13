namespace GDiagram {
    /**
     * Orchestrator for parsing activity diagrams.
     * Delegates specialized parsing to dedicated parser classes.
     */
    public class ActivityDiagramParser : Object {
        private TokenStream stream;
        private ActivityDiagram diagram;
        private ActivityNode? last_node;
        private Gee.ArrayList<ActivityNode> pending_connections;
        private string? current_partition;
        private Gee.HashMap<string, ActivityNode> connectors;
        private Gee.ArrayList<ActivityNode> pending_breaks;

        // Recursion depth tracking to prevent stack overflow
        private int recursion_depth = 0;
        private const int MAX_RECURSION_DEPTH = 100;

        // Specialized parsers
        private ActivityParserUtils utils;
        private ActivityEdgeParser edge_parser;
        private ActivityActionParser action_parser;
        private ActivityControlFlowParser control_flow_parser;
        private ActivityStructureParser structure_parser;
        private ActivityMetadataParser metadata_parser;

        public ActivityDiagramParser() {
            this.pending_connections = new Gee.ArrayList<ActivityNode>();
            this.current_partition = null;
            this.connectors = new Gee.HashMap<string, ActivityNode>();
            this.pending_breaks = new Gee.ArrayList<ActivityNode>();
        }

        public ActivityDiagram parse(Gee.ArrayList<Token> tokens) {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] ActivityDiagramParser.parse() - Resetting state...\n");

            this.stream = new TokenStream(tokens);
            this.diagram = new ActivityDiagram();
            this.last_node = null;
            this.pending_connections.clear();
            this.current_partition = null;
            this.connectors.clear();
            this.pending_breaks.clear();
            this.recursion_depth = 0;

            // Scan tokens for pragma directives
            for (int i = 0; i < tokens.size; i++) {
                var token = tokens[i];
                string lower_lexeme = token.lexeme.down();
                // Pragma might be in single token like '!pragma useVerticalIf on'
                if (lower_lexeme.contains("!pragma") && lower_lexeme.contains("useverticalif")) {
                    diagram.use_vertical_if = true;
                    if (debug) print("[DEBUG] Detected pragma useVerticalIf in token: '%s'\n", token.lexeme);
                }
            }

            if (debug) print("[DEBUG] State reset, initializing parsers...\n");

            // Initialize specialized parsers
            utils = new ActivityParserUtils(stream);
            edge_parser = new ActivityEdgeParser(stream, diagram);
            action_parser = new ActivityActionParser(stream, diagram);
            control_flow_parser = new ActivityControlFlowParser(stream, diagram, pending_breaks);
            structure_parser = new ActivityStructureParser(stream, diagram);
            metadata_parser = new ActivityMetadataParser(stream, diagram);

            // Set up callbacks for parsers that need them
            control_flow_parser.set_callbacks(
                () => { parse_statement(); },
                (node) => { add_node_with_connection(node); },
                () => { skip_newlines(); },
                () => { return consume_until_rparen(); },
                (node) => { last_node = node; },
                (node) => { pending_connections.add(node); },
                () => { return last_node; }
            );

            structure_parser.set_callbacks(
                () => { parse_statement(); },
                () => { skip_newlines(); },
                (partition) => { current_partition = partition; }
            );

            metadata_parser.set_callbacks(
                () => { skip_newlines(); }
            );

            metadata_parser.set_edge_parser(edge_parser);

            if (debug) print("[DEBUG] Starting parse_diagram()...\n");

            try {
                parse_diagram();
                if (debug) print("[DEBUG] parse_diagram() completed successfully\n");
            } catch (Error e) {
                if (debug) printerr("[ERROR] parse_diagram() threw exception: %s\n", e.message);
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            if (debug) {
                print("[DEBUG] ActivityDiagramParser.parse() returning diagram with %d nodes\n", diagram.nodes.size);
                print("[DEBUG] === NODE SUMMARY ===\n");
                foreach (var node in diagram.nodes) {
                    string label = node.label ?? "(null)";
                    if (label.length > 80) {
                        label = label[0:77] + "...";
                    }
                    print("[DEBUG]   %s: partition='%s', label='%s'\n",
                        node.node_type.to_string(), node.partition ?? "(none)", label);
                }
            }
            return diagram;
        }

        private void parse_diagram() throws Error {
            skip_newlines();

            // Skip @startuml and any diagram name after it
            if (match(TokenType.STARTUML)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                skip_newlines();
            }

            // Parse statements until @enduml with iteration limit
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            int max_iterations = stream.size() * 2;
            int iterations = 0;

            if (debug) print("[DEBUG] parse_diagram() main loop starting (max %d iterations)...\n", max_iterations);

            while (!check(TokenType.ENDUML) && !is_at_end() && iterations < max_iterations) {
                int pos_before = stream.current;

                if (debug && iterations >= 15) {
                    print("[DEBUG]   Main loop iteration %d, token='%s' (type=%d) at line %d, pos=%d\n",
                        iterations, peek().lexeme, peek().token_type, peek().line, stream.current);
                }

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

                if (debug && iterations >= 15 && iterations < 25) {
                    print("[DEBUG]   Before skip_newlines: pos=%d, iterations=%d\n", stream.current, iterations);
                }

                skip_newlines();

                if (debug && iterations >= 15 && iterations < 25) {
                    print("[DEBUG]   After skip_newlines: pos=%d, about to increment iterations\n", stream.current);
                }

                iterations++;

                if (debug && iterations >= 15 && iterations < 25) {
                    print("[DEBUG]   Incremented to %d, checking loop condition...\n", iterations);
                }

                // Safety: if we didn't advance, force advance to prevent infinite loop
                if (stream.current == pos_before && !is_at_end()) {
                    if (debug) print("[DEBUG]   Position stuck, forcing advance\n");
                    advance();
                }
            }

            if (debug) print("[DEBUG] parse_diagram() main loop complete after %d iterations\n", iterations);
        }

        private void parse_statement() throws Error {
            // Recursion depth protection
            recursion_depth++;
            if (recursion_depth > MAX_RECURSION_DEPTH) {
                bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
                if (debug) {
                    printerr("[ERROR] Maximum recursion depth exceeded (%d) - likely infinite recursion\n", MAX_RECURSION_DEPTH);
                }
                diagram.errors.add(new ParseError(
                    "Maximum recursion depth exceeded (too many nested constructs)",
                    stream.current < stream.size() ? peek().line : 1,
                    1
                ));
                recursion_depth--;
                return;
            }

            try {
                parse_statement_impl();
            } finally {
                bool debug_fin = Environment.get_variable("G_MESSAGES_DEBUG") != null;
                if (debug_fin && recursion_depth == 1) {
                    print("[DEBUG]     parse_statement finally block: depth before decrement=%d\n", recursion_depth);
                }
                recursion_depth--;
                if (debug_fin && recursion_depth == 0) {
                    print("[DEBUG]     parse_statement RETURNING to caller, depth now=%d\n", recursion_depth);
                }
            }
        }

        private void parse_statement_impl() throws Error {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;

            if (debug && recursion_depth == 1) {
                print("[DEBUG]       >>> parse_statement(depth=%d): token='%s' at pos=%d\n",
                    recursion_depth, peek().lexeme, stream.current);
            }

            skip_newlines();

            if (is_at_end() || check(TokenType.ENDUML)) {
                return;
            }

            // Skip @startuml if it appears (defense in depth)
            if (match(TokenType.STARTUML)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                return;
            }

            // Skip comments
            if (match(TokenType.COMMENT)) {
                return;
            }

            int source_line = peek().line;

            if (debug && recursion_depth > 5) {
                print("[DEBUG] parse_statement depth=%d, line=%d, token='%s'\n",
                    recursion_depth, source_line, peek().lexeme);
            }

            // Simple node types - handle directly
            if (match(TokenType.START)) {
                var node = new ActivityNode(ActivityNodeType.START, null, previous().line);
                add_node_with_connection(node);
                return;
            }

            if (match(TokenType.STOP)) {
                var node = new ActivityNode(ActivityNodeType.STOP, null, previous().line);
                add_node_with_connection(node);
                last_node = null;
                return;
            }

            if (match(TokenType.KILL)) {
                var node = new ActivityNode(ActivityNodeType.KILL, null, previous().line);
                add_node_with_connection(node);
                last_node = null;
                return;
            }

            if (check(TokenType.END) && !check_next(TokenType.FORK) && !check_next(TokenType.MERGE) &&
                !check_next(TokenType.SPLIT) && !check_next(TokenType.NOTE)) {
                advance();
                var node = new ActivityNode(ActivityNodeType.END, null, previous().line);
                add_node_with_connection(node);
                last_node = null;
                return;
            }

            if (match(TokenType.DETACH)) {
                var node = new ActivityNode(ActivityNodeType.DETACH, null, previous().line);
                add_node_with_connection(node);
                last_node = null;
                return;
            }

            if (match(TokenType.BREAK)) {
                var break_node = new ActivityNode(ActivityNodeType.ACTION, "break", previous().line);
                add_node_with_connection(break_node);
                pending_breaks.add(break_node);
                last_node = null;
                return;
            }

            // Delegate to EdgeParser
            if (match(TokenType.ARROW_RIGHT) || match(TokenType.ARROW_RIGHT_DOTTED) ||
                match(TokenType.ARROW_LEFT) || match(TokenType.ARROW_LEFT_DOTTED)) {
                edge_parser.parse_arrow_label();
                return;
            }

            if (check(TokenType.MINUS)) {
                if (check_next(TokenType.LBRACKET)) {
                    edge_parser.parse_styled_arrow();
                    return;
                }
                if (check_next(TokenType.IDENTIFIER)) {
                    Token next_token = stream.peek_at(stream.current + 1);
                    string next_lexeme = next_token.lexeme.down();
                    if (next_lexeme == "up" || next_lexeme == "u" ||
                        next_lexeme == "down" || next_lexeme == "d" ||
                        next_lexeme == "left" || next_lexeme == "l" ||
                        next_lexeme == "right" || next_lexeme == "r") {
                        edge_parser.parse_styled_arrow();
                        return;
                    }
                }
            }

            // Delegate to ActionParser
            if (match(TokenType.HASH)) {
                var node = action_parser.parse_colored_action(source_line);
                add_node_with_connection(node);
                return;
            }

            if (match(TokenType.COLON)) {
                var node = action_parser.parse_action(null, null, null, null, previous().line);
                add_node_with_connection(node);
                return;
            }

            // Delegate to ControlFlowParser
            if (match(TokenType.IF)) {
                if (debug) print("[DEBUG]     Statement: IF\n");
                control_flow_parser.parse_if(previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (check(TokenType.FORK) && !check_fork_again()) {
                int fork_line = advance().line;
                control_flow_parser.parse_fork(fork_line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.WHILE)) {
                if (debug) print("[DEBUG]     Statement: WHILE at line %d\n", previous().line);
                control_flow_parser.parse_while(previous().line);
                last_node = control_flow_parser.get_last_node();
                if (debug) print("[DEBUG]     WHILE parsing complete\n");
                return;
            }

            if (match(TokenType.REPEAT)) {
                control_flow_parser.parse_repeat(previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.SWITCH)) {
                control_flow_parser.parse_switch(previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.SPLIT)) {
                control_flow_parser.parse_split(previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            // Delegate to StructureParser
            if (match(TokenType.PIPE)) {
                structure_parser.set_current_partition(current_partition);
                structure_parser.parse_swimlane();
                current_partition = structure_parser.get_current_partition();
                return;
            }

            if (match(TokenType.PARTITION)) {
                if (debug) print("[DEBUG]     Statement: PARTITION at line %d, pos=%d\n", previous().line, stream.current);
                structure_parser.set_current_partition(current_partition);
                int pos_before_partition = stream.current;
                structure_parser.parse_partition();
                current_partition = structure_parser.get_current_partition();
                if (debug) print("[DEBUG]     PARTITION complete, pos advanced from %d to %d\n", pos_before_partition, stream.current);
                return;
            }

            if (match(TokenType.GROUP)) {
                if (debug) print("[DEBUG]     Statement: GROUP at line %d\n", previous().line);
                structure_parser.set_current_partition(current_partition);
                structure_parser.parse_group();
                current_partition = structure_parser.get_current_partition();
                if (debug) print("[DEBUG]     GROUP complete\n");
                return;
            }

            // Delegate to MetadataParser
            if (match(TokenType.FLOATING)) {
                if (match(TokenType.NOTE)) {
                    metadata_parser.set_last_node(last_node);
                    metadata_parser.parse_note(true);
                }
                return;
            }

            if (match(TokenType.NOTE)) {
                if (debug) print("[DEBUG]     Statement: NOTE at line %d, pos=%d\n", previous().line, stream.current);
                metadata_parser.set_last_node(last_node);
                int pos_before_note = stream.current;
                metadata_parser.parse_note(false);
                if (debug) print("[DEBUG]     NOTE parsing complete, pos advanced from %d to %d\n", pos_before_note, stream.current);
                if (debug && recursion_depth == 1) {
                    print("[DEBUG]     About to return from NOTE handler at depth=%d\n", recursion_depth);
                }
                return;
            }

            if (match(TokenType.TITLE)) {
                metadata_parser.parse_title();
                return;
            }

            if (match(TokenType.HEADER)) {
                metadata_parser.parse_header();
                return;
            }

            if (match(TokenType.FOOTER)) {
                metadata_parser.parse_footer();
                return;
            }

            if (match(TokenType.CAPTION)) {
                metadata_parser.parse_caption();
                return;
            }

            if (match(TokenType.LEGEND)) {
                metadata_parser.parse_legend();
                return;
            }

            if (match(TokenType.SKINPARAM)) {
                metadata_parser.parse_skinparam();
                return;
            }

            // Connector/goto labels
            if (match(TokenType.LPAREN)) {
                parse_connector(previous().line);
                return;
            }

            // Separators
            if (match(TokenType.SEPARATOR)) {
                int sep_line = previous().line;
                var node = new ActivityNode(ActivityNodeType.SEPARATOR, null, sep_line);
                if (!check(TokenType.NEWLINE) && !check(TokenType.SEPARATOR) && !is_at_end()) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.SEPARATOR) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        if (sb.len > 0) sb.append(" ");
                        sb.append(advance().lexeme);
                    }
                    match(TokenType.SEPARATOR);
                    node.label = sb.str.strip();
                }
                add_node_with_connection(node);
                return;
            }

            if (check(TokenType.IDENTIFIER) && peek().lexeme == "=") {
                if (stream.check_next_lexeme("=")) {
                    int eq_line = advance().line;
                    advance();
                    var sb = new StringBuilder();
                    while (!is_at_end() && !check(TokenType.NEWLINE)) {
                        Token t = peek();
                        if (t.lexeme == "=" && stream.check_next_lexeme("=")) {
                            advance();
                            advance();
                            break;
                        }
                        if (sb.len > 0) sb.append(" ");
                        sb.append(advance().lexeme);
                    }
                    var node = new ActivityNode(ActivityNodeType.SEPARATOR, sb.str.strip(), eq_line);
                    add_node_with_connection(node);
                    return;
                }
            }

            if (match(TokenType.VSPACE)) {
                var node = new ActivityNode(ActivityNodeType.VSPACE, null, previous().line);
                add_node_with_connection(node);
                return;
            }

            // Handle pragma directives (might be tokenized as ! followed by pragma)
            if (peek().lexeme == "!" || peek().lexeme == "!pragma") {
                advance(); // consume ! or !pragma

                // If we consumed just !, next should be pragma
                if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "pragma") {
                    advance();
                }

                // Check for useVerticalIf
                if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "useverticalif") {
                    advance();
                    if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "on") {
                        advance();
                        diagram.use_vertical_if = true;
                    }
                }

                // Consume rest of line
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                return;
            }

            // Skip directives
            if (match(TokenType.SCALE) || match(TokenType.HIDE) || match(TokenType.SHOW)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                return;
            }

            // List syntax: - Action or * Action
            if (check(TokenType.MINUS) || peek().lexeme == "*") {
                // Count nesting level (*, **, ***)
                int level = 0;
                while (peek().lexeme == "*" && !is_at_end()) {
                    level++;
                    advance(); // consume *
                }

                // If we consumed asterisks, this is list syntax
                bool is_list = (level > 0) || check(TokenType.MINUS);

                if (!is_list && peek().lexeme != "*") {
                    // Was just a MINUS for something else, not list
                    return;
                }

                if (level == 0 && check(TokenType.MINUS)) {
                    advance(); // consume -
                    level = 1;
                }

                // Collect action text until newline
                var sb = new StringBuilder();
                Token? prev_token = null;
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    Token t = advance();
                    // Don't add space before/after hyphen for compound words
                    bool need_space = (sb.len > 0);
                    if (prev_token != null && (prev_token.token_type == TokenType.MINUS || t.token_type == TokenType.MINUS)) {
                        need_space = false;  // No space around hyphens
                    }
                    if (need_space) sb.append(" ");
                    sb.append(t.lexeme);
                    prev_token = t;
                }

                string label = sb.str.strip();
                if (label.length > 0) {
                    var node = new ActivityNode(ActivityNodeType.ACTION, label, source_line);
                    node.indent_level = level;  // Store list nesting level (1=*, 2=**, 3=***)
                    add_node_with_connection(node);
                }
                return;
            }

            // Unknown - skip
            if (debug) {
                print("[DEBUG]     Statement: UNKNOWN token='%s' (type=%d) at line %d, pos=%d - skipping\n",
                    peek().lexeme, peek().token_type, peek().line, stream.current);
            }
            advance();
        }

        private void parse_connector(int source_line) {
            var name_sb = new StringBuilder();

            while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                name_sb.append(t.lexeme);
            }

            match(TokenType.RPAREN);

            string name = name_sb.str.strip();
            if (name.length == 0) {
                return;
            }

            if (connectors.has_key(name)) {
                var target = connectors.get(name);
                if (last_node != null) {
                    diagram.connect(last_node, target, edge_parser.pending_edge_label);
                    edge_parser.pending_edge_label = null;
                }
                last_node = null;
            } else {
                var node = new ActivityNode(ActivityNodeType.CONNECTOR, name, source_line);
                add_node_with_connection(node);
                connectors.set(name, node);
            }
        }

        private string consume_until_rparen() {
            return utils.consume_until_rparen();
        }

        private void add_node_with_connection(ActivityNode node) {
            node.partition = current_partition;
            diagram.add_node(node);

            if (last_node != null) {
                var edge = new ActivityEdge(last_node, node, edge_parser.pending_edge_label);
                edge.color = edge_parser.pending_edge_color;
                edge.style = edge_parser.pending_edge_style;
                edge.direction = edge_parser.pending_edge_direction;
                edge.note = edge_parser.pending_edge_note;
                diagram.add_edge(edge);
                edge_parser.reset_pending_edge_attributes();
            }

            foreach (var pending in pending_connections) {
                diagram.connect(pending, node);
            }
            pending_connections.clear();

            last_node = node;
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == TokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case TokenType.START:
                    case TokenType.STOP:
                    case TokenType.IF:
                    case TokenType.FORK:
                    case TokenType.WHILE:
                    case TokenType.REPEAT:
                    case TokenType.ENDUML:
                        return;
                    default:
                        advance();
                        break;
                }
            }
        }

        private void skip_newlines() {
            // Safety: Don't process if already at/past end
            if (stream.current >= stream.size() - 1) {
                return;
            }

            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            int safety_count = 0;
            int last_pos = stream.current;

            while (match(TokenType.NEWLINE) || match(TokenType.COMMENT)) {
                safety_count++;

                // Check if position is stuck
                if (stream.current == last_pos) {
                    if (debug) {
                        printerr("[ERROR] skip_newlines() stuck at position %d, token='%s'\n", stream.current, peek().lexeme);
                    }
                    // Force advance
                    advance();
                }
                last_pos = stream.current;

                // Safety: stop if we reach near EOF
                if (stream.current >= stream.size() - 1) {
                    break;
                }

                if (safety_count > 1000) {
                    if (debug) {
                        printerr("[ERROR] skip_newlines() exceeded 1000 iterations! Breaking.\n");
                    }
                    break;
                }
            }
        }

        private bool check_fork_again() {
            if (check(TokenType.FORK) && check_next(TokenType.IDENTIFIER)) {
                Token next_token = stream.peek_at(stream.current + 1);
                return next_token.lexeme.down() == "again";
            }
            return false;
        }

        private bool check_next(TokenType type) {
            return stream.check_next(type);
        }

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
