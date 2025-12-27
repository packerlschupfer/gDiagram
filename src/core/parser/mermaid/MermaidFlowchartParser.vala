namespace GDiagram {
    public class MermaidFlowchartParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidFlowchart diagram;

        public MermaidFlowchartParser() {
            this.current = 0;
        }

        public MermaidFlowchart parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidFlowchart();

            try {
                parse_flowchart();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_flowchart() throws GLib.Error {
            skip_newlines();

            // Expect flowchart keyword
            if (!match(MermaidTokenType.FLOWCHART)) {
                error_at_current("Expected 'flowchart'");
            }

            // Parse direction (optional, defaults to TD)
            skip_newlines();
            if (check(MermaidTokenType.TD) || check(MermaidTokenType.TB)) {
                advance();
                diagram.direction = FlowchartDirection.TOP_DOWN;
            } else if (check(MermaidTokenType.BT)) {
                advance();
                diagram.direction = FlowchartDirection.BOTTOM_UP;
            } else if (check(MermaidTokenType.LR)) {
                advance();
                diagram.direction = FlowchartDirection.LEFT_RIGHT;
            } else if (check(MermaidTokenType.RL)) {
                advance();
                diagram.direction = FlowchartDirection.RIGHT_LEFT;
            }

            skip_newlines();

            // Parse statements until EOF
            while (!is_at_end()) {
                try {
                    parse_statement();
                } catch (GLib.Error e) {
                    diagram.errors.add(new ParseError(
                        e.message,
                        previous().line,
                        previous().column
                    ));
                    synchronize();
                }
                skip_newlines();
            }
        }

        private void parse_statement() throws GLib.Error {
            skip_newlines();

            if (is_at_end()) {
                return;
            }

            // Skip comments
            if (match(MermaidTokenType.COMMENT)) {
                return;
            }

            // Subgraph
            if (check(MermaidTokenType.SUBGRAPH)) {
                parse_subgraph();
                return;
            }

            // Style definition
            if (check(MermaidTokenType.STYLE)) {
                parse_style();
                return;
            }

            // Class definition
            if (check(MermaidTokenType.CLASS_DEF)) {
                parse_class_def();
                return;
            }

            // Node or edge statement
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_node_or_edge();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_subgraph() throws GLib.Error {
            advance(); // consume 'subgraph'

            // Get subgraph ID
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected subgraph identifier");
            }
            string id = advance().lexeme;

            var subgraph = new FlowchartSubgraph(id);

            // Optional title in brackets or quotes
            if (check(MermaidTokenType.LBRACKET)) {
                advance();
                var title_parts = new StringBuilder();
                while (!check(MermaidTokenType.RBRACKET) && !is_at_end()) {
                    title_parts.append(advance().lexeme);
                    title_parts.append(" ");
                }
                if (match(MermaidTokenType.RBRACKET)) {
                    subgraph.title = title_parts.str.strip();
                }
            } else if (check(MermaidTokenType.STRING)) {
                subgraph.title = advance().lexeme;
            }

            skip_newlines();

            // Parse subgraph direction (optional)
            if (check(MermaidTokenType.DIRECTION)) {
                advance();
                skip_newlines();
                if (check(MermaidTokenType.TD) || check(MermaidTokenType.TB)) {
                    advance();
                    subgraph.direction = FlowchartDirection.TOP_DOWN;
                    subgraph.has_custom_direction = true;
                } else if (check(MermaidTokenType.LR)) {
                    advance();
                    subgraph.direction = FlowchartDirection.LEFT_RIGHT;
                    subgraph.has_custom_direction = true;
                } else if (check(MermaidTokenType.RL)) {
                    advance();
                    subgraph.direction = FlowchartDirection.RIGHT_LEFT;
                    subgraph.has_custom_direction = true;
                } else if (check(MermaidTokenType.BT)) {
                    advance();
                    subgraph.direction = FlowchartDirection.BOTTOM_UP;
                    subgraph.has_custom_direction = true;
                }
            }

            skip_newlines();

            // Parse subgraph contents until 'end'
            while (!check(MermaidTokenType.END) && !is_at_end()) {
                // For now, we'll track nodes defined in subgraph
                // A more complete implementation would parse full statements here
                if (check(MermaidTokenType.IDENTIFIER)) {
                    string node_id = peek().lexeme;
                    var node = diagram.find_node(node_id);
                    if (node != null) {
                        subgraph.nodes.add(node);
                    }
                }
                parse_statement();
                skip_newlines();
            }

            if (!match(MermaidTokenType.END)) {
                error_at_current("Expected 'end' to close subgraph");
            }

            diagram.subgraphs.add(subgraph);
        }

        private void parse_style() throws GLib.Error {
            advance(); // consume 'style'

            // Get node ID or class name
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected identifier after 'style'");
            }
            string target = advance().lexeme;

            // Parse style properties (simplified - just consume rest of line)
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                advance();
            }

            // Note: Full implementation would parse fill, stroke, color, etc.
        }

        private void parse_class_def() throws GLib.Error {
            advance(); // consume 'classDef'

            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected class name");
            }
            string class_name = advance().lexeme;

            var style = new FlowchartStyle(class_name);

            // Parse style properties (simplified)
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                var token = advance();
                // In a full implementation, we'd parse fill:color, stroke:color, etc.
            }

            diagram.styles.add(style);
        }

        private void parse_node_or_edge() throws GLib.Error {
            // Start with a node ID
            string from_id = advance().lexeme;
            FlowchartNode? from_node = null;

            skip_whitespace_same_line();

            // Check for node shape definition
            if (is_node_shape_start()) {
                from_node = parse_node_definition(from_id);
                diagram.add_node(from_node);
            } else {
                // Just a reference to existing node
                from_node = diagram.get_or_create_node(from_id);
            }

            skip_whitespace_same_line();

            // Check for edge/arrow
            if (is_arrow_token()) {
                parse_edges_from_node(from_node);
            }
        }

        private FlowchartNode parse_node_definition(string id) throws GLib.Error {
            int line = previous().line;
            FlowchartNodeShape shape = FlowchartNodeShape.RECTANGLE;
            string text = id; // Default text is the ID

            // Determine shape and parse text based on delimiters
            if (check(MermaidTokenType.LBRACKET)) {
                advance();
                shape = FlowchartNodeShape.RECTANGLE;
                text = parse_node_text_until(MermaidTokenType.RBRACKET);
                if (!match(MermaidTokenType.RBRACKET)) {
                    error_at_current("Expected ']'");
                }
            } else if (check(MermaidTokenType.LPAREN)) {
                advance();
                shape = FlowchartNodeShape.ROUNDED;
                text = parse_node_text_until(MermaidTokenType.RPAREN);
                if (!match(MermaidTokenType.RPAREN)) {
                    error_at_current("Expected ')'");
                }
            } else if (check(MermaidTokenType.LBRACKET_LPAREN)) {
                advance();
                shape = FlowchartNodeShape.STADIUM;
                text = parse_node_text_until(MermaidTokenType.RPAREN_RBRACKET);
                if (!match(MermaidTokenType.RPAREN_RBRACKET)) {
                    error_at_current("Expected '])'");
                }
            } else if (check(MermaidTokenType.DOUBLE_LBRACKET)) {
                advance();
                shape = FlowchartNodeShape.SUBROUTINE;
                text = parse_node_text_until(MermaidTokenType.DOUBLE_RBRACKET);
                if (!match(MermaidTokenType.DOUBLE_RBRACKET)) {
                    error_at_current("Expected ']]'");
                }
            } else if (check(MermaidTokenType.LBRACE)) {
                advance();
                shape = FlowchartNodeShape.RHOMBUS;
                text = parse_node_text_until(MermaidTokenType.RBRACE);
                if (!match(MermaidTokenType.RBRACE)) {
                    error_at_current("Expected '}'");
                }
            } else if (check(MermaidTokenType.LBRACE_LBRACE)) {
                advance();
                shape = FlowchartNodeShape.HEXAGON;
                text = parse_node_text_until(MermaidTokenType.RBRACE_RBRACE);
                if (!match(MermaidTokenType.RBRACE_RBRACE)) {
                    error_at_current("Expected '}}'");
                }
            } else if (check(MermaidTokenType.DOUBLE_LPAREN)) {
                advance();
                shape = FlowchartNodeShape.CIRCLE;
                text = parse_node_text_until(MermaidTokenType.DOUBLE_RPAREN);
                if (!match(MermaidTokenType.DOUBLE_RPAREN)) {
                    error_at_current("Expected '))'");
                }
            } else if (check(MermaidTokenType.TRIPLE_LPAREN)) {
                advance();
                shape = FlowchartNodeShape.DOUBLE_CIRCLE;
                text = parse_node_text_until(MermaidTokenType.TRIPLE_RPAREN);
                if (!match(MermaidTokenType.TRIPLE_RPAREN)) {
                    error_at_current("Expected ')))'");
                }
            } else if (check(MermaidTokenType.ASYMMETRIC_START)) {
                advance();
                shape = FlowchartNodeShape.ASYMMETRIC;
                text = parse_node_text_until(MermaidTokenType.RBRACKET);
                if (!match(MermaidTokenType.RBRACKET)) {
                    error_at_current("Expected ']'");
                }
            } else if (check(MermaidTokenType.LBRACKET_SLASH)) {
                advance();
                shape = FlowchartNodeShape.PARALLELOGRAM;
                text = parse_node_text_until(MermaidTokenType.SLASH_RBRACKET);
                // Consume /]
                while (!check(MermaidTokenType.RBRACKET) && !is_at_end()) {
                    advance();
                }
                if (match(MermaidTokenType.RBRACKET)) {
                    // ok
                }
            } else if (check(MermaidTokenType.LBRACKET_BACKSLASH)) {
                advance();
                shape = FlowchartNodeShape.TRAPEZOID;
                text = parse_node_text_until(MermaidTokenType.BACKSLASH_RBRACKET);
                // Consume \]
                while (!check(MermaidTokenType.RBRACKET) && !is_at_end()) {
                    advance();
                }
                if (match(MermaidTokenType.RBRACKET)) {
                    // ok
                }
            }

            return new FlowchartNode(id, text, shape, line);
        }

        private string parse_node_text_until(MermaidTokenType end_type) {
            var sb = new StringBuilder();
            MermaidTokenType? last_type = null;

            while (!check(end_type) && !is_at_end() && !check(MermaidTokenType.NEWLINE)) {
                var token = advance();

                // Skip pipes
                if (token.token_type == MermaidTokenType.PIPE) {
                    continue;
                }

                // Add space before this token if needed
                if (sb.len > 0 && needs_space_before(token.token_type, last_type)) {
                    sb.append(" ");
                }

                sb.append(token.lexeme);
                last_type = token.token_type;
            }

            return sb.str.strip();
        }

        private bool needs_space_before(MermaidTokenType current, MermaidTokenType? previous) {
            // Don't add space before punctuation
            if (current == MermaidTokenType.QUESTION ||
                current == MermaidTokenType.EXCLAMATION ||
                current == MermaidTokenType.COMMA ||
                current == MermaidTokenType.COLON ||
                current == MermaidTokenType.SEMICOLON ||
                current == MermaidTokenType.PERCENT) {
                return false;
            }

            // Don't add space after opening brackets/parens
            if (previous == MermaidTokenType.LPAREN ||
                previous == MermaidTokenType.LBRACKET ||
                previous == MermaidTokenType.LBRACE) {
                return false;
            }

            return true;
        }

        private void parse_edges_from_node(FlowchartNode from_node) throws GLib.Error {
            while (is_arrow_token() && !is_at_end()) {
                var edge = new FlowchartEdge(from_node, from_node); // temp, will update 'to'

                // Determine edge type and arrow type
                var arrow_token = advance();
                parse_arrow_type(arrow_token, edge);

                skip_whitespace_same_line();

                // Parse edge label (optional, between pipes)
                string? label = null;
                if (check(MermaidTokenType.PIPE)) {
                    advance();
                    label = parse_edge_label();
                    if (!match(MermaidTokenType.PIPE)) {
                        error_at_current("Expected '|' after edge label");
                    }
                    skip_whitespace_same_line();
                }

                edge.label = label;

                // Parse destination node
                if (!check(MermaidTokenType.IDENTIFIER)) {
                    error_at_current("Expected node identifier after arrow");
                }

                string to_id = advance().lexeme;
                skip_whitespace_same_line();

                FlowchartNode? to_node = null;

                // Check if destination node has a shape definition
                if (is_node_shape_start()) {
                    to_node = parse_node_definition(to_id);
                    diagram.add_node(to_node);
                } else {
                    to_node = diagram.get_or_create_node(to_id);
                }

                edge.to = to_node;
                diagram.add_edge(edge);

                skip_whitespace_same_line();

                // Check for chained edges (A --> B --> C)
                // The 'to_node' becomes the new 'from_node' for chaining
                if (is_arrow_token()) {
                    from_node = to_node;
                } else {
                    break;
                }
            }
        }

        private void parse_arrow_type(MermaidToken arrow_token, FlowchartEdge edge) {
            switch (arrow_token.token_type) {
                case MermaidTokenType.ARROW_SOLID:
                    edge.edge_type = FlowchartEdgeType.SOLID;
                    edge.arrow_type = FlowchartArrowType.NORMAL;
                    break;
                case MermaidTokenType.ARROW_DOTTED:
                    edge.edge_type = FlowchartEdgeType.DOTTED;
                    edge.arrow_type = FlowchartArrowType.NORMAL;
                    break;
                case MermaidTokenType.ARROW_THICK:
                    edge.edge_type = FlowchartEdgeType.THICK;
                    edge.arrow_type = FlowchartArrowType.NORMAL;
                    break;
                case MermaidTokenType.ARROW_INVISIBLE:
                    edge.edge_type = FlowchartEdgeType.INVISIBLE;
                    edge.arrow_type = FlowchartArrowType.NONE;
                    break;
                case MermaidTokenType.ARROW_OPEN_SOLID:
                    edge.edge_type = FlowchartEdgeType.SOLID;
                    edge.arrow_type = FlowchartArrowType.OPEN;
                    break;
                case MermaidTokenType.ARROW_OPEN_DOTTED:
                    edge.edge_type = FlowchartEdgeType.DOTTED;
                    edge.arrow_type = FlowchartArrowType.OPEN;
                    break;
                case MermaidTokenType.ARROW_CROSS_SOLID:
                    edge.edge_type = FlowchartEdgeType.SOLID;
                    edge.arrow_type = FlowchartArrowType.CROSS;
                    break;
                case MermaidTokenType.ARROW_CROSS_DOTTED:
                    edge.edge_type = FlowchartEdgeType.DOTTED;
                    edge.arrow_type = FlowchartArrowType.CROSS;
                    break;
                case MermaidTokenType.ARROW_CIRCLE_SOLID:
                    edge.edge_type = FlowchartEdgeType.SOLID;
                    edge.arrow_type = FlowchartArrowType.CIRCLE;
                    break;
                case MermaidTokenType.LINE_SOLID:
                    edge.edge_type = FlowchartEdgeType.SOLID;
                    edge.arrow_type = FlowchartArrowType.NONE;
                    break;
                case MermaidTokenType.LINE_DOTTED:
                    edge.edge_type = FlowchartEdgeType.DOTTED;
                    edge.arrow_type = FlowchartArrowType.NONE;
                    break;
                case MermaidTokenType.LINE_THICK:
                    edge.edge_type = FlowchartEdgeType.THICK;
                    edge.arrow_type = FlowchartArrowType.NONE;
                    break;
                default:
                    edge.edge_type = FlowchartEdgeType.SOLID;
                    edge.arrow_type = FlowchartArrowType.NORMAL;
                    break;
            }
        }

        private string parse_edge_label() {
            var sb = new StringBuilder();

            while (!check(MermaidTokenType.PIPE) && !is_at_end() && !check(MermaidTokenType.NEWLINE)) {
                var token = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(token.lexeme);
            }

            return sb.str.strip();
        }

        private bool is_node_shape_start() {
            return check(MermaidTokenType.LBRACKET) ||
                   check(MermaidTokenType.LPAREN) ||
                   check(MermaidTokenType.LBRACE) ||
                   check(MermaidTokenType.DOUBLE_LBRACKET) ||
                   check(MermaidTokenType.DOUBLE_LPAREN) ||
                   check(MermaidTokenType.TRIPLE_LPAREN) ||
                   check(MermaidTokenType.LBRACE_LBRACE) ||
                   check(MermaidTokenType.LBRACKET_LPAREN) ||
                   check(MermaidTokenType.ASYMMETRIC_START) ||
                   check(MermaidTokenType.LBRACKET_SLASH) ||
                   check(MermaidTokenType.LBRACKET_BACKSLASH);
        }

        private bool is_arrow_token() {
            return check(MermaidTokenType.ARROW_SOLID) ||
                   check(MermaidTokenType.ARROW_DOTTED) ||
                   check(MermaidTokenType.ARROW_THICK) ||
                   check(MermaidTokenType.ARROW_INVISIBLE) ||
                   check(MermaidTokenType.ARROW_OPEN_SOLID) ||
                   check(MermaidTokenType.ARROW_OPEN_DOTTED) ||
                   check(MermaidTokenType.ARROW_CROSS_SOLID) ||
                   check(MermaidTokenType.ARROW_CROSS_DOTTED) ||
                   check(MermaidTokenType.ARROW_CIRCLE_SOLID) ||
                   check(MermaidTokenType.LINE_SOLID) ||
                   check(MermaidTokenType.LINE_DOTTED) ||
                   check(MermaidTokenType.LINE_THICK);
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        private void skip_whitespace_same_line() {
            // In Mermaid, whitespace within a line doesn't create tokens
            // This is a no-op since our lexer already skips whitespace
        }

        private void synchronize() {
            // Skip to next line or known statement start
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case MermaidTokenType.SUBGRAPH:
                    case MermaidTokenType.END:
                    case MermaidTokenType.STYLE:
                    case MermaidTokenType.CLASS_DEF:
                        return;
                    default:
                        advance();
                        break;
                }
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

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            throw new GLib.IOError.FAILED("Line %d: %s", token.line, message);
        }
    }
}
