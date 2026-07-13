namespace GDiagram {
    public class MermaidFlowchartParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidFlowchart diagram;
        private FlowchartSubgraph? current_subgraph = null;  // set when parsing inside a subgraph

        // parse_subgraph() recurses for nested subgraphs: without a cap a file of a few
        // thousand "subgraph" lines overflowed the stack. Mermaid never nests this deep.
        private const int MAX_SUBGRAPH_DEPTH = 200;
        private int subgraph_depth = 0;

        // Ids given a shape or label somewhere (A[..], A@{..}): such a node is a node even
        // when a subgraph has the same id
        private Gee.HashSet<string> shaped_ids;

        // Class, style, linkStyle and click statements are applied once the whole diagram
        // is read, as Mermaid does: "A:::hot" before "classDef hot", "style X" before X's
        // first use and "class S1 big" on a subgraph all work.
        private Gee.ArrayList<string> class_targets;
        private Gee.ArrayList<string> class_names;
        private Gee.ArrayList<string> style_targets;
        private Gee.ArrayList<string> style_props;
        private Gee.ArrayList<string> link_style_indexes;   // "0,1" or "default"
        private Gee.ArrayList<string> link_style_props;
        private Gee.ArrayList<string> click_targets;
        private Gee.ArrayList<string?> click_urls;
        private Gee.ArrayList<string?> click_tooltips;

        // One parsed link: "-->", "-- text -->", "<-.->|text|", "o--o" …
        private class LinkInfo : Object {
            public FlowchartEdgeType edge_type = FlowchartEdgeType.SOLID;
            public FlowchartArrowType arrow_type = FlowchartArrowType.NORMAL;
            public FlowchartArrowType tail_type = FlowchartArrowType.NONE;
            public int length = 1;
            public string? label = null;
            public bool label_markdown = false;
            public string? edge_id = null;   // "A e1@--> B"
        }

        public MermaidFlowchartParser() {
            this.current = 0;
        }

        public MermaidFlowchart parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidFlowchart();
            this.current_subgraph = null;
            shaped_ids = new Gee.HashSet<string>();
            class_targets = new Gee.ArrayList<string>();
            class_names = new Gee.ArrayList<string>();
            style_targets = new Gee.ArrayList<string>();
            style_props = new Gee.ArrayList<string>();
            link_style_indexes = new Gee.ArrayList<string>();
            link_style_props = new Gee.ArrayList<string>();
            click_targets = new Gee.ArrayList<string>();
            click_urls = new Gee.ArrayList<string?>();
            click_tooltips = new Gee.ArrayList<string?>();

            try {
                parse_flowchart();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
            }
            finish();

            return diagram;
        }

        private void parse_flowchart() throws GLib.Error {
            skip_newlines();
            skip_frontmatter();
            skip_newlines();

            // Expect flowchart keyword ("graph" is the older spelling, "flowchart-elk" a layout variant)
            if (check(MermaidTokenType.IDENTIFIER) &&
                (peek().lexeme == "graph" || peek().lexeme.has_prefix("flowchart"))) {
                advance();
            } else if (!match(MermaidTokenType.FLOWCHART)) {
                error_at_current("Expected 'flowchart'");
            }

            // Parse direction (optional, defaults to TD)
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
            } else if (check(MermaidTokenType.ASYMMETRIC_START) && peek().lexeme == ">") {
                advance();  // "graph >" = LR
                diagram.direction = FlowchartDirection.LEFT_RIGHT;
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

        // "---\ntitle: X\n---" before the header
        private void skip_frontmatter() {
            if (!check(MermaidTokenType.LINE_SOLID) || peek().lexeme != "---") {
                return;
            }
            advance();
            while (!is_at_end()) {
                if (check(MermaidTokenType.LINE_SOLID) && peek().lexeme == "---" &&
                    previous().token_type == MermaidTokenType.NEWLINE) {
                    advance();
                    return;
                }
                if (check(MermaidTokenType.TITLE) && previous().token_type == MermaidTokenType.NEWLINE) {
                    advance();
                    match(MermaidTokenType.COLON);
                    int start = current;
                    int end = line_end(current);
                    string title = MermaidLexer.label_text(tokens, start, end);
                    if (title.length > 0) diagram.title = title;
                    current = end;
                    continue;
                }
                advance();
            }
        }

        private void parse_statement() throws GLib.Error {
            skip_newlines();

            if (is_at_end()) {
                return;
            }

            // Skip comments and statement separators
            if (match(MermaidTokenType.COMMENT) || match(MermaidTokenType.SEMICOLON)) {
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

            // Class assignment: class nodeId className
            if (check(MermaidTokenType.CLASS_KW)) {
                parse_class_assignment();
                return;
            }

            // Click action: click nodeId "url"
            if (check(MermaidTokenType.CLICK)) {
                parse_click();
                return;
            }

            // linkStyle 0,1 stroke:… / linkStyle default …
            if (check(MermaidTokenType.LINK_STYLE)) {
                parse_link_style();
                return;
            }

            // "direction LR" outside a subgraph header position
            if (check(MermaidTokenType.DIRECTION)) {
                advance();
                if (current_subgraph != null) {
                    read_direction(current_subgraph);
                }
                skip_to_line_end();
                return;
            }

            // Skip accessibility annotations (accTitle: …, accDescr: … / accDescr { … })
            if (check(MermaidTokenType.IDENTIFIER)) {
                string kw = peek().lexeme.down();
                if (kw == "acctitle" || kw == "accdescr") {
                    advance();
                    if (check(MermaidTokenType.LBRACE)) {
                        while (!check(MermaidTokenType.RBRACE) && !is_at_end()) {
                            advance();
                        }
                        match(MermaidTokenType.RBRACE);
                    }
                    skip_to_line_end();
                    return;
                }
            }

            // Node or edge statement
            if (is_id_token(peek())) {
                parse_node_or_edge();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_subgraph() throws GLib.Error {
            if (subgraph_depth >= MAX_SUBGRAPH_DEPTH) {
                error_at_current("Subgraphs nested deeper than %d levels".printf(MAX_SUBGRAPH_DEPTH));
            }
            int header_line = peek().line;
            advance(); // consume 'subgraph'

            string id;
            string? title = null;
            bool title_md = false;

            if (check(MermaidTokenType.STRING)) {
                // subgraph "Title only": the title is the id too
                title = advance().lexeme;
                id = title;
                if (is_markdown(title)) {
                    title = strip_markdown_quotes(title);
                    title_md = true;
                }
            } else if (is_id_token(peek())) {
                int id_start = current;
                id = read_id();
                if (check(MermaidTokenType.LBRACKET)) {
                    int open = current;
                    int close = find_on_line(open + 1, MermaidTokenType.RBRACKET);
                    if (close < 0) {
                        error_at_current("Expected ']' after subgraph title");
                    }
                    title = label_of(open + 1, close, out title_md);
                    current = close + 1;
                } else {
                    // No [title]: Mermaid shows the id, or the whole line for "subgraph My Group"
                    int end = line_end(current);
                    title = MermaidLexer.text_range(tokens, id_start, end);
                    current = end;
                    // Mermaid gives "subgraph My Group" a generated id: "My" stays a node
                    if (title != id) {
                        id = title;
                    }
                }
            } else {
                error_at_current("Expected subgraph identifier");
                return;
            }

            var subgraph = new FlowchartSubgraph(id);
            subgraph.title = title;
            subgraph.title_markdown = title_md;
            subgraph.source_line = header_line;

            skip_newlines();

            // Parse subgraph direction (optional)
            if (check(MermaidTokenType.DIRECTION)) {
                advance();
                read_direction(subgraph);
            }

            skip_newlines();

            // Parse subgraph contents — register_with_subgraph() is called automatically
            // by parse_vertex() for all nodes created or referenced inside.
            var saved_subgraph = current_subgraph;
            current_subgraph = subgraph;
            subgraph_depth++;

            try {
                while (!check(MermaidTokenType.END) && !is_at_end()) {
                    parse_statement();
                    skip_newlines();
                }
            } finally {
                subgraph_depth--;
                current_subgraph = saved_subgraph;
            }

            if (!match(MermaidTokenType.END)) {
                error_at_current("Expected 'end' to close subgraph");
            }

            // If inside another subgraph, add as nested; otherwise add to top-level list
            if (saved_subgraph != null) {
                saved_subgraph.subgraphs.add(subgraph);
            } else {
                diagram.subgraphs.add(subgraph);
            }
        }

        private void read_direction(FlowchartSubgraph subgraph) {
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

        // style <nodeId|subgraphId> fill:#f9f,stroke:#333,stroke-width:4px,color:#fff
        private void parse_style() throws GLib.Error {
            advance(); // consume 'style'

            if (!is_id_token(peek())) {
                error_at_current("Expected identifier after 'style'");
            }
            string target = read_id();
            int end = line_end(current);
            style_targets.add(target);
            style_props.add(MermaidLexer.text_range(tokens, current, end));
            current = end;
        }

        // classDef name[,name2] fill:#f9f,stroke:#333
        private void parse_class_def() throws GLib.Error {
            advance(); // consume 'classDef'

            if (!is_id_token(peek())) {
                error_at_current("Expected class name");
            }
            var names = new Gee.ArrayList<string>();
            names.add(read_id());
            while (check(MermaidTokenType.COMMA) && is_id_token(peek_at(1))) {
                advance();
                names.add(read_id());
            }

            int end = line_end(current);
            var props = parse_props(MermaidLexer.text_range(tokens, current, end));
            current = end;

            foreach (var name in names) {
                var style = new FlowchartStyle(name);
                style.fill_color = props.get("fill");
                style.stroke_color = props.get("stroke");
                style.stroke_width = props.get("stroke-width");
                style.font_color = props.get("color");
                style.stroke_dasharray = props.get("stroke-dasharray");
                diagram.styles.add(style);
            }
        }

        // click id "url" ["tooltip"] [_blank] / click id href "url" / click id callback / call cb()
        private void parse_click() throws GLib.Error {
            advance(); // consume 'click'

            if (!is_id_token(peek())) {
                error_at_current("Expected node identifier after 'click'");
            }
            string node_id = read_id();

            string? url = null;
            if (check(MermaidTokenType.IDENTIFIER) && (peek().lexeme == "href" || peek().lexeme == "call")) {
                bool call = peek().lexeme == "call";
                advance();
                if (call && check(MermaidTokenType.IDENTIFIER)) {
                    url = advance().lexeme;
                }
            }
            if (url == null) {
                if (check(MermaidTokenType.STRING)) {
                    url = advance().lexeme;
                } else if (check(MermaidTokenType.IDENTIFIER)) {
                    // A callback function name or a URL without quotes
                    url = advance().lexeme;
                }
            }
            if (match(MermaidTokenType.LPAREN)) {
                while (!check(MermaidTokenType.RPAREN) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                match(MermaidTokenType.RPAREN);
            }

            // Optional tooltip after another string
            string? tooltip = null;
            if (check(MermaidTokenType.STRING)) {
                tooltip = advance().lexeme;
            }
            skip_to_line_end();

            click_targets.add(node_id);
            click_urls.add(url);
            click_tooltips.add(tooltip);
        }

        // class nodeId[,nodeId2] className
        private void parse_class_assignment() throws GLib.Error {
            advance(); // consume 'class'

            var node_ids = new Gee.ArrayList<string>();
            while (is_id_token(peek())) {
                node_ids.add(read_id());
                if (!match(MermaidTokenType.COMMA)) {
                    break;
                }
            }

            if (!is_id_token(peek())) {
                error_at_current("Expected class name");
            }
            string class_name = read_id();
            foreach (var id in node_ids) {
                class_targets.add(id);
                class_names.add(class_name);
            }
            skip_to_line_end();
        }

        // linkStyle 0,2 stroke:#f00,stroke-width:4px / linkStyle default … [interpolate basis]
        private void parse_link_style() throws GLib.Error {
            advance(); // consume 'linkStyle'
            var indexes = new StringBuilder();
            while (check(MermaidTokenType.NUMBER) || check(MermaidTokenType.COMMA) ||
                   (check(MermaidTokenType.IDENTIFIER) && peek().lexeme == "default")) {
                indexes.append(advance().lexeme);
            }
            if (check(MermaidTokenType.IDENTIFIER) && peek().lexeme == "interpolate") {
                advance();
                if (check(MermaidTokenType.IDENTIFIER)) advance();
            }
            int end = line_end(current);
            string props = MermaidLexer.text_range(tokens, current, end);
            current = end;
            if (indexes.len > 0 && props.length > 0) {
                link_style_indexes.add(indexes.str);
                link_style_props.add(props);
            }
        }

        // ---- nodes and edges ----

        // A statement of vertex groups joined by links: A & B --> C -- text --> D
        private void parse_node_or_edge() throws GLib.Error {
            var sources = parse_vertex_group();

            while (true) {
                var link = try_parse_link();
                if (link == null) {
                    break;
                }
                if (!is_id_token(peek())) {
                    error_at_current("Expected node identifier after arrow");
                }
                var targets = parse_vertex_group();
                foreach (var from in sources) {
                    foreach (var to in targets) {
                        var edge = new FlowchartEdge(from, to);
                        edge.edge_type = link.edge_type;
                        edge.arrow_type = link.arrow_type;
                        edge.tail_arrow_type = link.tail_type;
                        edge.label = link.label;
                        edge.label_markdown = link.label_markdown;
                        edge.min_length = link.length;
                        edge.edge_id = link.edge_id;
                        diagram.add_edge(edge);
                    }
                }
                sources = targets;
            }
        }

        private Gee.ArrayList<FlowchartNode> parse_vertex_group() throws GLib.Error {
            var group = new Gee.ArrayList<FlowchartNode>();
            var first = parse_vertex();
            if (first != null) group.add(first);
            while (check(MermaidTokenType.AMPERSAND)) {
                advance(); // consume '&'
                if (!is_id_token(peek())) break;
                var extra = parse_vertex();
                if (extra != null) group.add(extra);
            }
            return group;
        }

        // id [shape] [@{ … }] [:::class]
        private FlowchartNode? parse_vertex() throws GLib.Error {
            int line = peek().line;
            string id = read_id();

            FlowchartNodeShape shape;
            string text;
            bool markdown;
            bool has_shape = try_parse_shape(out shape, out text, out markdown);

            Gee.HashMap<string, string>? data = null;
            if (check(MermaidTokenType.AT) && !peek().space_before &&
                peek_at(1).token_type == MermaidTokenType.LBRACE && !peek_at(1).space_before) {
                data = parse_shape_data();
            }

            // Edge ids carry only animation settings: "e1@{ animate: true }" is not a node
            if (!has_shape && data != null && diagram.find_node(id) == null &&
                !data.has_key("shape") && !data.has_key("label") &&
                !data.has_key("icon") && !data.has_key("img") &&
                (data.has_key("animate") || data.has_key("animation") || data.has_key("curve"))) {
                return null;
            }

            var node = diagram.find_node(id);
            if (node == null) {
                node = new FlowchartNode(id, id, FlowchartNodeShape.RECTANGLE, line);
                diagram.add_node(node);
            } else if (node.source_line == 0) {
                node.source_line = line;
            }

            if (has_shape) {
                // A later definition updates the node, as in Mermaid ("A --> B" then "B[Label]")
                if (!shaped_ids.contains(id)) node.source_line = line;
                node.text = text;
                node.shape = shape;
                node.markdown = markdown;
                shaped_ids.add(id);
            }
            if (data != null) {
                apply_shape_data(node, data, line);
            }

            parse_class_suffix(id);
            register_with_subgraph(node);
            return node;
        }

        // ":::className" right after a vertex
        private void parse_class_suffix(string target) {
            while (check(MermaidTokenType.COLON) &&
                   peek_at(1).token_type == MermaidTokenType.COLON && !peek_at(1).space_before &&
                   peek_at(2).token_type == MermaidTokenType.COLON && !peek_at(2).space_before &&
                   is_id_token(peek_at(3)) && !peek_at(3).space_before) {
                advance();
                advance();
                advance();
                class_targets.add(target);
                class_names.add(read_id());
            }
        }

        // Node id; "1a" and "a.b" (lexed as separate tokens without space) stay one id
        private string read_id() {
            var sb = new StringBuilder(advance().lexeme);
            while ((check(MermaidTokenType.IDENTIFIER) || check(MermaidTokenType.NUMBER)) &&
                   !peek().space_before && only_dots(peek().leading)) {
                sb.append(peek().leading);
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        private static bool only_dots(string s) {
            for (int i = 0; i < s.length; i++) {
                if (s[i] != '.') return false;
            }
            return true;
        }

        // Node shape delimiters after an id. Label text is the exact source between them.
        private bool try_parse_shape(out FlowchartNodeShape shape, out string text, out bool markdown) throws GLib.Error {
            shape = FlowchartNodeShape.RECTANGLE;
            text = "";
            markdown = false;
            if (!is_node_shape_start()) {
                return false;
            }

            var open = peek();
            int open_idx = current;
            int text_start = open_idx + 1;
            int close = -1;       // index of the last closing token
            int text_end = -1;    // index of the first closing token
            string expected = "]";

            switch (open.token_type) {
                case MermaidTokenType.LBRACKET:
                    if (peek_at(1).token_type == MermaidTokenType.LPAREN && !peek_at(1).space_before) {
                        // [(text)] cylinder: ")" directly followed by "]"
                        shape = FlowchartNodeShape.CYLINDRICAL;
                        text_start = open_idx + 2;
                        expected = ")]";
                        for (int i = text_start; i < tokens.size && !ends_line(tokens[i]); i++) {
                            if (tokens[i].token_type == MermaidTokenType.RPAREN &&
                                tokens[i + 1].token_type == MermaidTokenType.RBRACKET &&
                                tokens[i + 1].leading.length == 0) {
                                text_end = i;
                                close = i + 1;
                                break;
                            }
                        }
                    } else {
                        shape = FlowchartNodeShape.RECTANGLE;
                        close = find_on_line(text_start, MermaidTokenType.RBRACKET);
                        text_end = close;
                    }
                    break;
                case MermaidTokenType.LBRACKET_SLASH:
                case MermaidTokenType.LBRACKET_BACKSLASH:
                    // [/t/] lean-r, [\t\] lean-l, [/t\] trapezoid, [\t/] inverted trapezoid:
                    // the closing "/]" or "\]" decides, so a "/" inside the text is fine
                    bool open_slash = open.token_type == MermaidTokenType.LBRACKET_SLASH;
                    expected = open_slash ? "/]" : "\\]";
                    for (int i = text_start; i < tokens.size && !ends_line(tokens[i]); i++) {
                        var t = tokens[i];
                        if ((t.token_type == MermaidTokenType.SLASH_RBRACKET ||
                             t.token_type == MermaidTokenType.BACKSLASH_RBRACKET) &&
                            tokens[i + 1].token_type == MermaidTokenType.RBRACKET &&
                            tokens[i + 1].leading.length == 0) {
                            bool close_slash = t.token_type == MermaidTokenType.SLASH_RBRACKET;
                            if (open_slash) {
                                shape = close_slash ? FlowchartNodeShape.PARALLELOGRAM : FlowchartNodeShape.TRAPEZOID;
                            } else {
                                shape = close_slash ? FlowchartNodeShape.TRAPEZOID_ALT : FlowchartNodeShape.PARALLELOGRAM_ALT;
                            }
                            text_end = i;
                            close = i + 1;
                            break;
                        }
                    }
                    if (close < 0) {
                        // Unterminated slash form: take up to "]" as before
                        shape = open_slash ? FlowchartNodeShape.PARALLELOGRAM : FlowchartNodeShape.TRAPEZOID;
                        close = find_on_line(text_start, MermaidTokenType.RBRACKET);
                        text_end = close;
                    }
                    break;
                case MermaidTokenType.LPAREN:
                    shape = FlowchartNodeShape.ROUNDED;
                    expected = ")";
                    close = find_on_line(text_start, MermaidTokenType.RPAREN);
                    text_end = close;
                    break;
                case MermaidTokenType.LBRACKET_LPAREN:
                    shape = FlowchartNodeShape.STADIUM;
                    expected = "])";
                    close = find_on_line(text_start, MermaidTokenType.RPAREN_RBRACKET);
                    text_end = close;
                    break;
                case MermaidTokenType.DOUBLE_LBRACKET:
                    shape = FlowchartNodeShape.SUBROUTINE;
                    expected = "]]";
                    close = find_on_line(text_start, MermaidTokenType.DOUBLE_RBRACKET);
                    text_end = close;
                    break;
                case MermaidTokenType.LBRACE:
                    shape = FlowchartNodeShape.RHOMBUS;
                    expected = "}";
                    close = find_on_line(text_start, MermaidTokenType.RBRACE);
                    text_end = close;
                    break;
                case MermaidTokenType.LBRACE_LBRACE:
                    shape = FlowchartNodeShape.HEXAGON;
                    expected = "}}";
                    close = find_on_line(text_start, MermaidTokenType.RBRACE_RBRACE);
                    text_end = close;
                    break;
                case MermaidTokenType.DOUBLE_LPAREN:
                    shape = FlowchartNodeShape.CIRCLE;
                    expected = "))";
                    close = find_on_line(text_start, MermaidTokenType.DOUBLE_RPAREN);
                    text_end = close;
                    break;
                case MermaidTokenType.TRIPLE_LPAREN:
                    shape = FlowchartNodeShape.DOUBLE_CIRCLE;
                    expected = ")))";
                    close = find_on_line(text_start, MermaidTokenType.TRIPLE_RPAREN);
                    text_end = close;
                    break;
                case MermaidTokenType.ASYMMETRIC_START:
                    shape = FlowchartNodeShape.ASYMMETRIC;
                    close = find_on_line(text_start, MermaidTokenType.RBRACKET);
                    text_end = close;
                    break;
                default:
                    return false;
            }

            if (close < 0) {
                current = open_idx + 1;
                error_at_current("Expected '%s'".printf(expected));
            }

            bool md;
            text = label_of(text_start, text_end, out md);
            if (md) markdown = true;
            current = close + 1;
            return true;
        }

        // A@{ shape: cyl, label: "New DB" } — Mermaid 11 shape data (may span lines)
        private Gee.HashMap<string, string> parse_shape_data() throws GLib.Error {
            var data = new Gee.HashMap<string, string>();
            advance(); // '@'
            advance(); // '{'
            while (!is_at_end() && !check(MermaidTokenType.RBRACE)) {
                if (check(MermaidTokenType.NEWLINE) || check(MermaidTokenType.COMMA) ||
                    check(MermaidTokenType.COMMENT)) {
                    advance();
                    continue;
                }
                if (!is_id_token(peek())) {
                    advance();
                    continue;
                }
                string key = advance().lexeme;
                if (!match(MermaidTokenType.COLON)) {
                    continue;
                }
                int start = current;
                while (!is_at_end() && !check(MermaidTokenType.COMMA) &&
                       !check(MermaidTokenType.RBRACE) && !check(MermaidTokenType.NEWLINE)) {
                    advance();
                }
                string value = MermaidLexer.label_text(tokens, start, current);
                data.set(key, value);
            }
            if (!match(MermaidTokenType.RBRACE)) {
                error_at_current("Expected '}' to close '@{'");
            }
            return data;
        }

        private void apply_shape_data(FlowchartNode node, Gee.HashMap<string, string> data, int line) {
            bool had_shape = shaped_ids.contains(node.id);
            if (data.has_key("shape")) {
                node.shape = shape_from_name(data.get("shape"));
            }
            if (data.has_key("icon") || data.has_key("img")) {
                node.icon = data.has_key("icon") ? data.get("icon") : data.get("img");
                node.icon_is_image = !data.has_key("icon");
                if (data.has_key("w")) node.img_w = int.parse(data.get("w"));
                if (data.has_key("h")) node.img_h = int.parse(data.get("h"));
                if (data.has_key("pos")) node.img_pos = data.get("pos");
                if (!data.has_key("shape")) {
                    string form = data.has_key("form") ? data.get("form") : "";
                    if (form == "circle") {
                        node.shape = FlowchartNodeShape.CIRCLE;
                    } else if (form == "rounded") {
                        node.shape = FlowchartNodeShape.ROUNDED;
                    } else {
                        node.shape = FlowchartNodeShape.RECTANGLE;
                    }
                }
            }
            if (data.has_key("label")) {
                string label = data.get("label");
                if (is_markdown(label)) {
                    label = strip_markdown_quotes(label);
                    node.markdown = true;
                } else {
                    node.markdown = false;
                }
                node.text = label;
            }
            if (!had_shape) node.source_line = line;
            shaped_ids.add(node.id);
        }

        // Mermaid 11.17 shape names and aliases → the nearest drawable shape
        public static FlowchartNodeShape shape_from_name(string raw_name) {
            string name = raw_name.strip().down();
            switch (name) {
                case "rect": case "rectangle": case "proc": case "process":
                case "div-rect": case "div-proc": case "divided-rectangle": case "divided-process":
                case "tag-rect": case "tag-proc": case "tagged-rectangle": case "tagged-process":
                    return FlowchartNodeShape.RECTANGLE;
                case "rounded": case "event":
                case "delay": case "half-rounded-rectangle":
                case "curv-trap": case "curved-trapezoid": case "display":
                case "bow-rect": case "stored-data": case "bow-tie-rectangle":
                    return FlowchartNodeShape.ROUNDED;
                case "stadium": case "pill": case "terminal":
                    return FlowchartNodeShape.STADIUM;
                case "fr-rect": case "subproc": case "subprocess": case "subroutine": case "framed-rectangle":
                case "lin-rect": case "lin-proc": case "lined-rectangle": case "lined-process": case "shaded-process":
                    return FlowchartNodeShape.SUBROUTINE;
                case "cyl": case "cylinder": case "database": case "db":
                case "h-cyl": case "das": case "horizontal-cylinder":
                case "lin-cyl": case "disk": case "lined-cylinder":
                    return FlowchartNodeShape.CYLINDRICAL;
                case "circle": case "circ":
                    return FlowchartNodeShape.CIRCLE;
                case "dbl-circ": case "double-circle":
                    return FlowchartNodeShape.DOUBLE_CIRCLE;
                case "diam": case "diamond": case "decision": case "question":
                    return FlowchartNodeShape.RHOMBUS;
                case "hex": case "hexagon": case "prepare":
                    return FlowchartNodeShape.HEXAGON;
                case "lean-r": case "lean-right": case "in-out":
                case "sl-rect": case "sloped-rectangle": case "manual-input":
                    return FlowchartNodeShape.PARALLELOGRAM;
                case "lean-l": case "lean-left": case "out-in":
                    return FlowchartNodeShape.PARALLELOGRAM_ALT;
                case "trap-b": case "trapezoid": case "trapezoid-bottom": case "priority":
                    return FlowchartNodeShape.TRAPEZOID;
                case "trap-t": case "inv-trapezoid": case "trapezoid-top": case "manual":
                    return FlowchartNodeShape.TRAPEZOID_ALT;
                case "doc": case "document":
                case "lin-doc": case "lined-document":
                case "tag-doc": case "tagged-document":
                    return FlowchartNodeShape.DOCUMENT;
                case "docs": case "documents": case "st-doc": case "stacked-document":
                case "st-rect": case "stacked-rectangle": case "processes": case "procs":
                    return FlowchartNodeShape.STACKED_RECT;
                case "notch-rect": case "card": case "notched-rectangle":
                    return FlowchartNodeShape.NOTCHED_RECT;
                case "tri": case "triangle": case "extract":
                    return FlowchartNodeShape.TRIANGLE;
                case "flip-tri": case "flipped-triangle": case "manual-file":
                    return FlowchartNodeShape.INV_TRIANGLE;
                case "hourglass": case "collate":
                    return FlowchartNodeShape.HOURGLASS;
                case "bolt": case "com-link": case "lightning-bolt":
                    return FlowchartNodeShape.BOLT;
                case "brace": case "brace-l": case "comment":
                    return FlowchartNodeShape.BRACE_LEFT;
                case "brace-r":
                    return FlowchartNodeShape.BRACE_RIGHT;
                case "braces":
                    return FlowchartNodeShape.BRACES;
                case "sm-circ": case "small-circle": case "start":
                    return FlowchartNodeShape.SMALL_CIRCLE;
                case "f-circ": case "filled-circle": case "junction":
                    return FlowchartNodeShape.FILLED_CIRCLE;
                case "fr-circ": case "framed-circle": case "stop":
                    return FlowchartNodeShape.FRAMED_CIRCLE;
                case "cross-circ": case "crossed-circle": case "summary":
                    return FlowchartNodeShape.CROSSED_CIRCLE;
                case "fork": case "join":
                    return FlowchartNodeShape.FORK_BAR;
                case "notch-pent": case "loop-limit": case "notched-pentagon":
                    return FlowchartNodeShape.NOTCHED_PENTAGON;
                case "win-pane": case "internal-storage": case "window-pane":
                    return FlowchartNodeShape.WINDOW_PANE;
                case "text":
                    return FlowchartNodeShape.TEXT_BLOCK;
                case "flag": case "paper-tape":
                    return FlowchartNodeShape.FLAG;
                case "odd":
                    return FlowchartNodeShape.ASYMMETRIC;
                case "bang":
                    return FlowchartNodeShape.BANG;
                case "cloud":
                    return FlowchartNodeShape.CLOUD;
                default:
                    return FlowchartNodeShape.RECTANGLE;
            }
        }

        // ---- links ----

        private static Regex? re_link = null;
        private static Regex? re_start = null;

        private static void init_link_regexes() {
            if (re_link != null) return;
            try {
                // Mermaid's flow.jison LINK / START_LINK tokens
                re_link = new Regex("^(?:([xo<]?)(-{2,})([-xo>])|([xo<]?)(={2,})([=xo>])|([xo<]?)-?(\\.+)-([xo>]?)|(~{3,}))$");
                re_start = new Regex("^([xo<]?)(--|==|-\\.)$");
            } catch (RegexError e) {
                warning("flowchart link regex: %s", e.message);
            }
        }

        private bool is_link_piece(MermaidToken t, bool first) {
            switch (t.token_type) {
                case MermaidTokenType.ARROW_SOLID:
                case MermaidTokenType.ARROW_DOTTED:
                case MermaidTokenType.ARROW_THICK:
                case MermaidTokenType.ARROW_INVISIBLE:
                case MermaidTokenType.LINE_SOLID:
                case MermaidTokenType.LINE_DOTTED:
                case MermaidTokenType.LINE_THICK:
                case MermaidTokenType.ARROW_OPEN_SOLID:
                case MermaidTokenType.ARROW_OPEN_DOTTED:
                case MermaidTokenType.ARROW_CROSS_SOLID:
                case MermaidTokenType.ARROW_CROSS_DOTTED:
                case MermaidTokenType.ARROW_BIDIRECTIONAL:
                case MermaidTokenType.SEQ_SOLID_ARROW:
                case MermaidTokenType.SEQ_SOLID_OPEN:
                case MermaidTokenType.SEQ_SOLID_CROSS:
                case MermaidTokenType.SEQ_SOLID_LINE:
                case MermaidTokenType.EQUALS:
                case MermaidTokenType.TILDE:
                    return true;
                case MermaidTokenType.ASYMMETRIC_START:
                    return first && t.lexeme == "<";
                case MermaidTokenType.IDENTIFIER:
                    return t.lexeme == "o" || t.lexeme == "x";
                default:
                    return false;
            }
        }

        // Longest run of adjacent link tokens starting at `pos` that forms a link of the
        // wanted kind (a complete link, or a "--"/"=="/"-." that opens a text link).
        // Returns the index after the run, or -1.
        // `matched` is the link text (a MatchInfo must not outlive the string it matched).
        private int match_link_at(int pos, bool want_start, out string matched) {
            init_link_regexes();
            matched = "";
            if (pos >= tokens.size || !is_link_piece(tokens[pos], true)) return -1;
            var pieces = new Gee.ArrayList<string>();
            string text = tokens[pos].raw;
            pieces.add(text);
            int i = pos + 1;
            while (i < tokens.size && only_dots(tokens[i].leading) && is_link_piece(tokens[i], false)) {
                text += tokens[i].leading + tokens[i].raw;
                pieces.add(text);
                i++;
            }
            for (int n = pieces.size; n >= 1; n--) {
                var re = want_start ? re_start : re_link;
                if (re.match(pieces[n - 1])) {
                    matched = pieces[n - 1];
                    return pos + n;
                }
            }
            return -1;
        }

        private LinkInfo? try_parse_link() throws GLib.Error {
            int pos = current;
            // Mermaid 11 edge ids: "A e1@--> B"
            if (pos + 2 < tokens.size && is_id_token(tokens[pos]) &&
                tokens[pos + 1].token_type == MermaidTokenType.AT && !tokens[pos + 1].space_before &&
                !tokens[pos + 2].space_before && is_link_piece(tokens[pos + 2], true)) {
                pos += 2;
            }

            string m;
            var link = new LinkInfo();
            if (pos > current) {
                link.edge_id = tokens[current].lexeme;
            }
            int after = match_link_at(pos, false, out m);
            if (after >= 0) {
                read_link(m, link);
                current = after;
            } else {
                after = match_link_at(pos, true, out m);
                if (after < 0) {
                    return null;
                }
                // "A -- text --> B": the text runs to the closing link on the same line
                MatchInfo sm;
                re_start.match(m, 0, out sm);
                string tail = sm.fetch(1);
                int text_start = after;
                int close = -1;
                int close_end = -1;
                string cm = "";
                for (int i = text_start; i < tokens.size && !ends_line(tokens[i]); i++) {
                    if (i > text_start || tokens[i].token_type != MermaidTokenType.STRING) {
                        int e = match_link_at(i, false, out cm);
                        if (e >= 0 && i > text_start) {
                            close = i;
                            close_end = e;
                            break;
                        }
                    }
                }
                if (close < 0) {
                    current = text_start;
                    error_at_current("Expected closing arrow after edge label");
                }
                read_link(cm, link);
                link.tail_type = arrow_for(tail);
                bool md;
                link.label = label_of(text_start, close, out md);
                link.label_markdown = md;
                current = close_end;
            }

            // -->|text|
            if (link.label == null && check(MermaidTokenType.PIPE)) {
                int close = find_on_line(current + 1, MermaidTokenType.PIPE);
                if (close < 0) {
                    advance();
                    error_at_current("Expected '|' after edge label");
                }
                bool md;
                link.label = label_of(current + 1, close, out md);
                link.label_markdown = md;
                current = close + 1;
            }

            return link;
        }

        private void read_link(string text, LinkInfo link) {
            MatchInfo m;
            if (!re_link.match(text, 0, out m)) return;
            string? solid = m.fetch(2);
            string? thick = m.fetch(5);
            string? dots = m.fetch(8);
            string? invis = m.fetch(10);
            if (solid != null && solid.length > 0) {
                string head = m.fetch(3);
                link.edge_type = FlowchartEdgeType.SOLID;
                link.tail_type = arrow_for(m.fetch(1));
                link.arrow_type = arrow_for(head);
                // Mermaid: the characters before the last one, minus one ("-->" and "---" 1, "--->" 2)
                link.length = solid.length - 1;
            } else if (thick != null && thick.length > 0) {
                string head = m.fetch(6);
                link.edge_type = FlowchartEdgeType.THICK;
                link.tail_type = arrow_for(m.fetch(4));
                link.arrow_type = arrow_for(head);
                link.length = thick.length - 1;
            } else if (dots != null && dots.length > 0) {
                link.edge_type = FlowchartEdgeType.DOTTED;
                link.tail_type = arrow_for(m.fetch(7));
                link.arrow_type = arrow_for(m.fetch(9));
                link.length = dots.length;
            } else if (invis != null && invis.length > 0) {
                link.edge_type = FlowchartEdgeType.INVISIBLE;
                link.arrow_type = FlowchartArrowType.NONE;
                link.length = invis.length - 2;
            }
            if (link.length < 1) link.length = 1;
        }

        private static FlowchartArrowType arrow_for(string? end) {
            if (end == null) return FlowchartArrowType.NONE;
            switch (end) {
                case ">": case "<": return FlowchartArrowType.NORMAL;
                case "o": return FlowchartArrowType.OPEN;
                case "x": return FlowchartArrowType.CROSS;
                default: return FlowchartArrowType.NONE;
            }
        }

        // ---- post-processing ----

        private void finish() {
            resolve_subgraph_ends();

            // Classes: "default" first, then assignments in source order
            FlowchartStyle? default_style = find_style("default");
            if (default_style != null) {
                var classed = new Gee.HashSet<string>();
                foreach (var t in class_targets) classed.add(t);
                foreach (var node in diagram.nodes) {
                    if (!classed.contains(node.id)) apply_class_to_node(node, default_style);
                }
            }
            for (int i = 0; i < class_targets.size; i++) {
                string target = class_targets[i];
                var node = diagram.find_node(target);
                if (node != null) {
                    node.style_class = node.style_class == null ? class_names[i] : node.style_class + " " + class_names[i];
                }
                var style = find_style(class_names[i]);
                if (style == null) continue;
                if (node != null) {
                    apply_class_to_node(node, style);
                } else {
                    var sg = diagram.find_subgraph(target);
                    if (sg != null) {
                        if (style.fill_color != null) sg.fill_color = style.fill_color;
                        if (style.stroke_color != null) sg.stroke_color = style.stroke_color;
                        if (style.stroke_width != null) sg.stroke_width = strip_px(style.stroke_width);
                        if (style.font_color != null) sg.font_color = style.font_color;
                        if (style.stroke_dasharray != null) sg.stroke_dasharray = style.stroke_dasharray;
                    } else {
                        // "class e1,e2 name": the target is an edge id, not a node
                        apply_class_to_edges(target, class_names[i], style);
                    }
                }
            }

            // style statements override classes
            for (int i = 0; i < style_targets.size; i++) {
                var props = parse_props(style_props[i]);
                var node = diagram.find_node(style_targets[i]);
                if (node != null) {
                    if (props.has_key("fill")) node.fill_color = props.get("fill");
                    if (props.has_key("stroke")) node.stroke_color = props.get("stroke");
                    if (props.has_key("stroke-width")) node.stroke_width = strip_px(props.get("stroke-width"));
                    if (props.has_key("color")) node.font_color = props.get("color");
                    if (props.has_key("stroke-dasharray")) node.stroke_dasharray = props.get("stroke-dasharray");
                    continue;
                }
                var sg = diagram.find_subgraph(style_targets[i]);
                if (sg != null) {
                    if (props.has_key("fill")) sg.fill_color = props.get("fill");
                    if (props.has_key("stroke")) sg.stroke_color = props.get("stroke");
                    if (props.has_key("stroke-width")) sg.stroke_width = strip_px(props.get("stroke-width"));
                    if (props.has_key("color")) sg.font_color = props.get("color");
                    if (props.has_key("stroke-dasharray")) sg.stroke_dasharray = props.get("stroke-dasharray");
                }
            }

            // linkStyle: by edge index in definition order; "default" applies to all first
            for (int pass = 0; pass < 2; pass++) {
                for (int i = 0; i < link_style_indexes.size; i++) {
                    bool is_default = link_style_indexes[i].contains("default");
                    if ((pass == 0) != is_default) continue;
                    var props = parse_props(link_style_props[i]);
                    var targets = new Gee.ArrayList<FlowchartEdge>();
                    if (is_default) {
                        targets.add_all(diagram.edges);
                    } else {
                        foreach (var part in link_style_indexes[i].split(",")) {
                            int idx;
                            if (int.try_parse(part.strip(), out idx) && idx >= 0 && idx < diagram.edges.size) {
                                targets.add(diagram.edges[idx]);
                            }
                        }
                    }
                    foreach (var edge in targets) {
                        if (props.has_key("stroke")) edge.edge_color = props.get("stroke");
                        if (props.has_key("stroke-width")) edge.edge_thickness = strip_px(props.get("stroke-width"));
                        if (props.has_key("color")) edge.label_color = props.get("color");
                        if (props.has_key("stroke-dasharray")) edge.stroke_dasharray = props.get("stroke-dasharray");
                    }
                }
            }

            for (int i = 0; i < click_targets.size; i++) {
                var node = diagram.find_node(click_targets[i]);
                if (node == null) continue;
                if (click_urls[i] != null) node.href_link = click_urls[i];
                if (click_tooltips[i] != null) node.tooltip = click_tooltips[i];
            }
        }

        // "X --> Y" where X / Y are subgraph ids: the edge attaches to the cluster, and the
        // placeholder node read for the id is not a node of the diagram
        private void resolve_subgraph_ends() {
            if (diagram.subgraphs.size == 0) return;
            var placeholders = new Gee.HashSet<FlowchartNode>();
            foreach (var edge in diagram.edges) {
                if (!shaped_ids.contains(edge.from.id)) {
                    var sg = diagram.find_subgraph(edge.from.id);
                    if (sg != null) {
                        edge.from_subgraph = sg;
                        placeholders.add(edge.from);
                    }
                }
                if (!shaped_ids.contains(edge.to.id)) {
                    var sg = diagram.find_subgraph(edge.to.id);
                    if (sg != null) {
                        edge.to_subgraph = sg;
                        placeholders.add(edge.to);
                    }
                }
            }
            foreach (var node in placeholders) {
                diagram.remove_node(node);
                remove_from_subgraphs(diagram.subgraphs, node);
            }
        }

        private static void remove_from_subgraphs(Gee.List<FlowchartSubgraph> list, FlowchartNode node) {
            foreach (var sg in list) {
                sg.nodes.remove(node);
                remove_from_subgraphs(sg.subgraphs, node);
            }
        }

        private FlowchartStyle? find_style(string name) {
            FlowchartStyle? found = null;
            foreach (var style in diagram.styles) {
                if (style.class_name == name) found = style;  // the last classDef wins
            }
            return found;
        }

        private static void apply_class_to_node(FlowchartNode node, FlowchartStyle style) {
            if (style.fill_color != null) node.fill_color = style.fill_color;
            if (style.stroke_color != null) node.stroke_color = style.stroke_color;
            if (style.stroke_width != null) node.stroke_width = strip_px(style.stroke_width);
            if (style.font_color != null) node.font_color = style.font_color;
            if (style.stroke_dasharray != null) node.stroke_dasharray = style.stroke_dasharray;
        }

        /*
         * A classDef applied to an edge id ("A e1@--> B" + "class e1 animate"):
         * Mermaid puts the class on the <path>, so stroke / stroke-width /
         * stroke-dasharray style the line and `color` its label. There is nothing to
         * fill, so `fill` is dropped.
         */
        private void apply_class_to_edges(string edge_id, string class_name, FlowchartStyle style) {
            foreach (var edge in diagram.edges) {
                if (edge.edge_id != edge_id) continue;
                edge.style_class = edge.style_class == null
                    ? class_name : edge.style_class + " " + class_name;
                if (style.stroke_color != null) edge.edge_color = style.stroke_color;
                if (style.stroke_width != null) edge.edge_thickness = strip_px(style.stroke_width);
                if (style.font_color != null) edge.label_color = style.font_color;
                if (style.stroke_dasharray != null) edge.stroke_dasharray = style.stroke_dasharray;
            }
        }

        private static string strip_px(string v) {
            string s = v.strip();
            if (s.has_suffix("px")) s = s.substring(0, s.length - 2).strip();
            return s;
        }

        // "fill:#f9f,stroke:#333, stroke-width:4px, color:rgb(1,2,3)" → map
        public static Gee.HashMap<string, string> parse_props(string text) {
            var map = new Gee.HashMap<string, string>();
            var parts = new Gee.ArrayList<string>();
            var sb = new StringBuilder();
            int depth = 0;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (c == '(') depth++;
                if (c == ')' && depth > 0) depth--;
                if ((c == ',' || c == ';') && depth == 0) {
                    parts.add(sb.str);
                    sb.truncate(0);
                } else {
                    sb.append_c(c);
                }
            }
            parts.add(sb.str);
            foreach (var part in parts) {
                int colon = part.index_of(":");
                if (colon <= 0) continue;
                string key = part.substring(0, colon).strip().down();
                string value = part.substring(colon + 1).replace("!important", "").strip();
                if (key.length > 0 && value.length > 0) {
                    map.set(key, value);
                }
            }
            return map;
        }

        private static bool is_markdown(string text) {
            return text.length >= 2 && text.has_prefix("`") && text.has_suffix("`");
        }

        /**
         * The label text of a token range, with Mermaid's markdown strings recognised
         * only inside a quoted label ("`text`"). Bare backticks — A[`text`] — are literal
         * text in Mermaid, and stripping them dropped the characters the author wrote.
         */
        private string label_of(int first, int end, out bool markdown) {
            string t = MermaidLexer.label_text(tokens, first, end);
            markdown = MermaidLexer.is_quoted_label(tokens, first, end) && is_markdown(t);
            if (markdown) t = strip_markdown_quotes(t);
            return t;
        }

        private static string strip_markdown_quotes(string text) {
            return text.substring(1, text.length - 2);
        }

        // ---- token helpers ----

        private bool is_node_shape_start() {
            return check(MermaidTokenType.LBRACKET) ||
                   check(MermaidTokenType.LPAREN) ||
                   check(MermaidTokenType.LBRACE) ||
                   check(MermaidTokenType.DOUBLE_LBRACKET) ||
                   check(MermaidTokenType.DOUBLE_LPAREN) ||
                   check(MermaidTokenType.TRIPLE_LPAREN) ||
                   check(MermaidTokenType.LBRACE_LBRACE) ||
                   check(MermaidTokenType.LBRACKET_LPAREN) ||
                   (check(MermaidTokenType.ASYMMETRIC_START) && peek().lexeme == ">") ||
                   check(MermaidTokenType.LBRACKET_SLASH) ||
                   check(MermaidTokenType.LBRACKET_BACKSLASH);
        }

        // Identifiers, numbers and words the lexer makes keywords of in other diagram
        // types ("state", "note", "loop") are node ids; flowchart statement keywords are not
        private static bool is_id_token(MermaidToken t) {
            switch (t.token_type) {
                case MermaidTokenType.IDENTIFIER:
                case MermaidTokenType.NUMBER:
                    return true;
                case MermaidTokenType.SUBGRAPH:
                case MermaidTokenType.END:
                case MermaidTokenType.STYLE:
                case MermaidTokenType.LINK_STYLE:
                case MermaidTokenType.CLASS_DEF:
                case MermaidTokenType.CLASS_KW:
                case MermaidTokenType.CLICK:
                case MermaidTokenType.DIRECTION:
                case MermaidTokenType.FLOWCHART:
                case MermaidTokenType.STRING:
                case MermaidTokenType.TEXT:
                case MermaidTokenType.COMMENT:
                case MermaidTokenType.NEWLINE:
                case MermaidTokenType.EOF:
                    return false;
                default:
                    return t.lexeme.length > 0 && t.lexeme[0].isalpha();
            }
        }

        private static bool ends_line(MermaidToken t) {
            return t.token_type == MermaidTokenType.NEWLINE || t.token_type == MermaidTokenType.EOF;
        }

        // Index of the first `type` token from `from` on the current line, or -1
        private int find_on_line(int from, MermaidTokenType type) {
            for (int i = from; i < tokens.size && !ends_line(tokens[i]); i++) {
                if (tokens[i].token_type == type) return i;
            }
            return -1;
        }

        // Index of the NEWLINE / COMMENT / EOF token that ends the line at `from`
        private int line_end(int from) {
            int i = from;
            while (i < tokens.size && !ends_line(tokens[i]) &&
                   tokens[i].token_type != MermaidTokenType.COMMENT) {
                i++;
            }
            return i < tokens.size ? i : tokens.size - 1;
        }

        private void skip_to_line_end() {
            current = line_end(current);
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        // Register a node with the current subgraph if we are inside one.
        // Uses a Set-like check to avoid duplicates (FlowchartSubgraph.nodes is an ArrayList).
        private void register_with_subgraph(FlowchartNode node) {
            if (current_subgraph != null && !current_subgraph.nodes.contains(node)) {
                current_subgraph.nodes.add(node);
            }
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

        private MermaidToken peek_at(int offset) {
            int i = current + offset;
            return tokens.get(i < tokens.size ? i : tokens.size - 1);
        }

        private MermaidToken previous() {
            return tokens.get(current > 0 ? current - 1 : 0);
        }

        private int error_line = 1;
        private int error_column = 1;

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            error_line = token.line;
            error_column = token.column;
            string context = "";
            if (token.lexeme.length > 0) {
                context = " (found: '%s')".printf(token.lexeme);
            }
            throw new GLib.IOError.FAILED("%s%s", message, context);
        }
    }
}
