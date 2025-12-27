namespace GPlantUML {
    /**
     * Orchestrator for parsing activity diagrams.
     * Delegates specialized parsing to dedicated parser classes.
     */
    public class ActivityDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ActivityDiagram diagram;
        private ActivityNode? last_node;
        private Gee.ArrayList<ActivityNode> pending_connections;
        private string? current_partition;
        private Gee.HashMap<string, ActivityNode> connectors;
        private Gee.ArrayList<ActivityNode> pending_breaks;

        // Specialized parsers
        private ActivityParserUtils utils;
        private ActivityEdgeParser edge_parser;
        private ActivityActionParser action_parser;
        private ActivityControlFlowParser control_flow_parser;
        private ActivityStructureParser structure_parser;
        private ActivityMetadataParser metadata_parser;

        public ActivityDiagramParser() {
            this.current = 0;
            this.pending_connections = new Gee.ArrayList<ActivityNode>();
            this.current_partition = null;
            this.connectors = new Gee.HashMap<string, ActivityNode>();
            this.pending_breaks = new Gee.ArrayList<ActivityNode>();
        }

        public ActivityDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new ActivityDiagram();
            this.last_node = null;
            this.pending_connections.clear();
            this.current_partition = null;
            this.connectors.clear();
            this.pending_breaks.clear();

            // Initialize specialized parsers
            utils = new ActivityParserUtils(tokens, ref current);
            edge_parser = new ActivityEdgeParser(tokens, ref current, diagram);
            action_parser = new ActivityActionParser(tokens, ref current, diagram);
            control_flow_parser = new ActivityControlFlowParser(tokens, ref current, diagram, pending_breaks);
            structure_parser = new ActivityStructureParser(tokens, ref current, diagram);
            metadata_parser = new ActivityMetadataParser(tokens, ref current, diagram);

            // Set up callbacks for parsers that need them
            control_flow_parser.set_callbacks(
                () => { parse_statement(); },
                (node) => { add_node_with_connection(node); },
                () => { skip_newlines(); },
                () => { return consume_until_rparen(); }
            );

            structure_parser.set_callbacks(
                () => { parse_statement(); },
                () => { skip_newlines(); }
            );

            metadata_parser.set_callbacks(
                () => { skip_newlines(); }
            );

            metadata_parser.set_edge_parser(edge_parser);

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
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
            int max_iterations = tokens.size * 2;
            int iterations = 0;

            while (!check(TokenType.ENDUML) && !is_at_end() && iterations < max_iterations) {
                int pos_before = current;
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
                iterations++;

                // Safety: if we didn't advance, force advance to prevent infinite loop
                if (current == pos_before && !is_at_end()) {
                    advance();
                }
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

            int source_line = peek().line;

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
                edge_parser.parse_arrow_label(ref current);
                return;
            }

            if (check(TokenType.MINUS)) {
                if (check_next(TokenType.LBRACKET)) {
                    edge_parser.parse_styled_arrow(ref current);
                    return;
                }
                if (check_next(TokenType.IDENTIFIER)) {
                    string next_lexeme = tokens.get(current + 1).lexeme.down();
                    if (next_lexeme == "up" || next_lexeme == "u" ||
                        next_lexeme == "down" || next_lexeme == "d" ||
                        next_lexeme == "left" || next_lexeme == "l" ||
                        next_lexeme == "right" || next_lexeme == "r") {
                        edge_parser.parse_styled_arrow(ref current);
                        return;
                    }
                }
            }

            // Delegate to ActionParser
            if (match(TokenType.HASH)) {
                var node = action_parser.parse_colored_action(ref current, source_line);
                add_node_with_connection(node);
                return;
            }

            if (match(TokenType.COLON)) {
                var node = action_parser.parse_action(ref current, null, null, null, null, previous().line);
                add_node_with_connection(node);
                return;
            }

            // Delegate to ControlFlowParser
            if (match(TokenType.IF)) {
                control_flow_parser.parse_if(ref current, previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (check(TokenType.FORK) && !check_fork_again()) {
                int fork_line = advance().line;
                control_flow_parser.parse_fork(ref current, fork_line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.WHILE)) {
                control_flow_parser.parse_while(ref current, previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.REPEAT)) {
                control_flow_parser.parse_repeat(ref current, previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.SWITCH)) {
                control_flow_parser.parse_switch(ref current, previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            if (match(TokenType.SPLIT)) {
                control_flow_parser.parse_split(ref current, previous().line);
                last_node = control_flow_parser.get_last_node();
                return;
            }

            // Delegate to StructureParser
            if (match(TokenType.PIPE)) {
                structure_parser.set_current_partition(current_partition);
                structure_parser.parse_swimlane(ref current);
                current_partition = structure_parser.get_current_partition();
                return;
            }

            if (match(TokenType.PARTITION)) {
                structure_parser.set_current_partition(current_partition);
                structure_parser.parse_partition(ref current);
                current_partition = structure_parser.get_current_partition();
                return;
            }

            if (match(TokenType.GROUP)) {
                structure_parser.set_current_partition(current_partition);
                structure_parser.parse_group(ref current);
                current_partition = structure_parser.get_current_partition();
                return;
            }

            // Delegate to MetadataParser
            if (match(TokenType.FLOATING)) {
                if (match(TokenType.NOTE)) {
                    metadata_parser.set_last_node(last_node);
                    metadata_parser.parse_note(ref current, true);
                }
                return;
            }

            if (match(TokenType.NOTE)) {
                metadata_parser.set_last_node(last_node);
                metadata_parser.parse_note(ref current, false);
                return;
            }

            if (match(TokenType.TITLE)) {
                metadata_parser.parse_title(ref current);
                return;
            }

            if (match(TokenType.HEADER)) {
                metadata_parser.parse_header(ref current);
                return;
            }

            if (match(TokenType.FOOTER)) {
                metadata_parser.parse_footer(ref current);
                return;
            }

            if (match(TokenType.CAPTION)) {
                metadata_parser.parse_caption(ref current);
                return;
            }

            if (match(TokenType.LEGEND)) {
                metadata_parser.parse_legend(ref current);
                return;
            }

            if (match(TokenType.SKINPARAM)) {
                metadata_parser.parse_skinparam(ref current);
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
                if (current + 1 < tokens.size && tokens.get(current + 1).lexeme == "=") {
                    int eq_line = advance().line;
                    advance();
                    var sb = new StringBuilder();
                    while (!is_at_end() && !check(TokenType.NEWLINE)) {
                        Token t = peek();
                        if (t.lexeme == "=" && current + 1 < tokens.size &&
                            tokens.get(current + 1).lexeme == "=") {
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

            // Skip directives
            if (match(TokenType.SCALE) || match(TokenType.HIDE) || match(TokenType.SHOW)) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                return;
            }

            // Unknown - skip
            advance();
        }

        private void parse_connector(int source_line) throws Error {
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
            return utils.consume_until_rparen(ref current);
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
            while (match(TokenType.NEWLINE) || match(TokenType.COMMENT)) {
            }
        }

        private bool check_fork_again() {
            if (check(TokenType.FORK) && check_next(TokenType.IDENTIFIER)) {
                if (current + 1 < tokens.size && tokens.get(current + 1).lexeme.down() == "again") {
                    return true;
                }
            }
            return false;
        }

        private bool check_next(TokenType type) {
            if (current + 1 >= tokens.size) return false;
            return tokens.get(current + 1).token_type == type;
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
    }
}
