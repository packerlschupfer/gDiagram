namespace GDiagram {
    public class ComponentDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ComponentDiagram diagram;

        public ComponentDiagramParser() {
            tokens = new Gee.ArrayList<Token>();
            current = 0;
        }

        public ComponentDiagram parse(Gee.ArrayList<Token> token_list) {
            // A copy: read_bracket_text() may split a comment token into the tokens it hid
            this.tokens = new Gee.ArrayList<Token>();
            this.tokens.add_all(token_list);
            this.current = 0;
            this.diagram = new ComponentDiagram();
            this.open_containers = new Gee.ArrayList<Component>();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(
                    "Unexpected error: " + e.message,
                    current < tokens.size ? tokens[current].line : 0,
                    current < tokens.size ? tokens[current].column : 0
                ));
            }
            drop_link_ends_declared_later();

            return diagram;
        }

        private void parse_diagram() throws Error {
            // Skip @startuml if present
            if (check(TokenType.STARTUML)) {
                advance();
            }

            while (!is_at_end() && !check(TokenType.ENDUML)) {
                skip_newlines();
                if (is_at_end() || check(TokenType.ENDUML)) break;

                int before = current;
                parse_statement();
                // Every statement must consume something, or this loop spins forever
                if (current == before) {
                    advance();
                }
            }
        }

        private void parse_statement() throws Error {
            skip_newlines();
            if (is_at_end() || check(TokenType.ENDUML)) return;

            // Check for direction
            if (check_sequence("left", "to", "right", "direction")) {
                diagram.left_to_right = true;
                advance(); advance(); advance(); advance();
                skip_to_newline();
                return;
            }

            if (check_sequence("top", "to", "bottom", "direction")) {
                diagram.left_to_right = false;
                advance(); advance(); advance(); advance();
                skip_to_newline();
                return;
            }

            // Check for title
            if (check(TokenType.TITLE)) {
                parse_title();
                return;
            }

            // Check for skinparam
            if (check(TokenType.SKINPARAM)) {
                parse_skinparam_block();
                return;
            }

            // Check for container types (package, node, folder, frame)
            if (check(TokenType.PACKAGE) || check(TokenType.NODE_KW) ||
                check(TokenType.FOLDER) || check(TokenType.FRAME)) {
                parse_container();
                return;
            }
            // database, storage and cloud can be either a container (`storage X { ... }`)
            // or a leaf element (`storage "..." as s`). Route to the element parser,
            // which handles both via its trailing `{` check. storage and cloud used to
            // go to parse_container unconditionally and render as empty clusters.
            if (check(TokenType.DATABASE) || check(TokenType.STORAGE) || check(TokenType.CLOUD)) {
                parse_element_declaration();
                return;
            }

            // Check for component keyword
            if (check(TokenType.COMPONENT)) {
                parse_component_declaration();
                return;
            }

            // Check for interface keyword or () syntax
            if (check(TokenType.INTERFACE)) {
                parse_interface_declaration();
                return;
            }

            // actor / usecase keywords and the "(Use case)" / ":Actor:" shorthands.
            // Description diagrams mix them with components; they were skipped.
            if (check(TokenType.ACTOR) || check(TokenType.USECASE)) {
                parse_element_declaration();
                return;
            }
            if (check(TokenType.LPAREN) && !peek_next_is(TokenType.RPAREN)) {
                parse_shorthand_element(ComponentType.USECASE);
                return;
            }
            if (check(TokenType.COLON)) {
                parse_shorthand_element(ComponentType.ACTOR);
                return;
            }

            // Check for [Component] bracket syntax
            if (check(TokenType.LBRACKET)) {
                parse_bracket_component();
                return;
            }

            // Check for () interface syntax
            if (check(TokenType.LPAREN) && peek_next_is(TokenType.RPAREN)) {
                parse_circle_interface();
                return;
            }

            // Check for artifact, card, agent, rectangle
            if (check(TokenType.ARTIFACT) || check(TokenType.CARD) ||
                check(TokenType.AGENT) || check(TokenType.RECTANGLE)) {
                parse_element_declaration();
                return;
            }

            // Check for note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Check for port declarations
            if (check(TokenType.PORTIN) || check(TokenType.PORTOUT) || check(TokenType.PORT)) {
                parse_port();
                return;
            }

            // Check for queue, boundary, control, entity
            if (check(TokenType.QUEUE) || check(TokenType.BOUNDARY) ||
                check(TokenType.CONTROL) || check(TokenType.ENTITY)) {
                parse_element_declaration();
                return;
            }

            // Check for hide ("hide stereotype" drops the «stereotype» lines)
            if (check(TokenType.HIDE)) {
                string what = peek_ahead(1).down();
                if (what == "stereotype" || what == "stereotypes") {
                    diagram.hide_stereotype = true;
                }
                skip_to_newline();
                return;
            }

            // "json J { ... }" (allowmixing): the body was dropped line by line
            if (is_json_declaration()) {
                parse_json_block(diagram.components);
                return;
            }

            // "sprite $name [48x48/16] { ... }": the rows were read as elements and links
            if (is_sprite_definition()) {
                parse_sprite();
                return;
            }

            // Check for together block
            if (check(TokenType.IDENTIFIER) && current_lexeme() == "together") {
                parse_together_block_top();
                return;
            }

            // 'device' (the retired deployment diagram keyword) is a node: box3d, a
            // container only with a body
            if (is_device_declaration()) {
                parse_container();
                return;
            }

            // Element keywords the lexer has no token for (file, stack, person, ...)
            ComponentType word_type = ComponentType.COMPONENT;
            if ((check(TokenType.IDENTIFIER) || check(TokenType.COLLECTIONS)) &&
                element_word_type(current_lexeme(), out word_type) && is_declaration_word()) {
                parse_identifier_element_declaration(word_type);
                return;
            }

            // Try to parse as relationship or identifier
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_identifier_or_relationship();
                return;
            }

            // "legend right ... endlegend": the lines were skipped as unknown statements
            if (check(TokenType.LEGEND) && !is_component_arrow_piece(current + 1, true)) {
                diagram.legend = read_legend_block(tokens, ref current);
                return;
            }

            // A name that lexes as a keyword ("left --> right" after "[Left Panel] as left"):
            // the line was skipped and the link lost
            if (is_name_word_at(current) && is_component_arrow_piece(current + 1, true)) {
                parse_identifier_or_relationship();
                return;
            }

            // Skip unknown tokens
            advance();
        }

        // "sprite $name [WxH/16] {", "sprite name {", "sprite $name [WxH/16z] data"
        private bool is_sprite_definition() {
            if (!check(TokenType.IDENTIFIER) || current_lexeme() != "sprite" || current + 2 >= tokens.size) {
                return false;
            }
            var next = tokens[current + 1];
            if (!next.space_before || next.token_type == TokenType.NEWLINE) {
                return false;
            }
            if (next.lexeme == "$") {
                return true;
            }
            var after = tokens[current + 2];
            return next.token_type == TokenType.IDENTIFIER &&
                   (after.token_type == TokenType.LBRACKET || after.token_type == TokenType.LBRACE);
        }

        // The sprite's rows are rebuilt from their tokens: a row has no spaces, so the tokens of
        // one line are glued back together
        private void parse_sprite() {
            advance();  // sprite
            if (current_lexeme() == "$") {
                advance();
            }
            var name = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.LBRACKET) &&
                   !check(TokenType.LBRACE) && (name.len == 0 || !tokens[current].space_before)) {
                name.append(current_lexeme());
                advance();
            }
            string? spec = null;
            if (check(TokenType.LBRACKET)) {
                advance();
                var sb = new StringBuilder();
                while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.RBRACKET)) {
                    sb.append(current_lexeme());
                    advance();
                }
                if (check(TokenType.RBRACKET)) {
                    advance();
                }
                spec = sb.str;
            }
            var rows = new Gee.ArrayList<string>();
            if (check(TokenType.LBRACE)) {
                advance();
                skip_to_newline();
                while (!is_at_end() && !check(TokenType.ENDUML)) {
                    skip_newlines();
                    if (is_at_end() || check(TokenType.ENDUML)) {
                        break;
                    }
                    if (check(TokenType.RBRACE)) {
                        advance();
                        break;
                    }
                    var row = new StringBuilder();
                    while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.RBRACE)) {
                        row.append(current_lexeme());
                        advance();
                    }
                    rows.add(row.str);
                }
            } else {
                var data = new StringBuilder();
                while (!is_at_end() && !check(TokenType.NEWLINE)) {
                    data.append(current_lexeme());
                    advance();
                }
                rows.add(data.str);
            }
            if (name.len > 0) {
                var sprite = PlantUmlSprite.decode(name.str, spec, rows);
                if (sprite != null) {
                    diagram.sprites.set(name.str, sprite);
                }
            }
            skip_to_newline();
        }

        // A word token that can be an element name or alias. "left", "right", "top", "bottom",
        // "end", "of", "over" ... lex as keywords, not IDENTIFIER.
        private bool is_name_word_at(int idx) {
            if (idx >= tokens.size) {
                return false;
            }
            var t = tokens[idx];
            if (t.token_type == TokenType.STRING || t.token_type == TokenType.NEWLINE ||
                t.token_type == TokenType.EOF || t.token_type == TokenType.COMMENT ||
                t.token_type == TokenType.ENDUML || t.token_type == TokenType.STEREOTYPE) {
                return false;
            }
            string lx = t.lexeme;
            return lx.length > 0 && (lx.get_char(0).isalnum() || lx.has_prefix("_"));
        }

        /**
         * "legend [top|bottom] [left|right|center]" at tokens[pos] through "endlegend" or
         * "end legend". The body lines are rebuilt from their tokens; pos ends after the
         * closing line. Shared with ClassDiagramParser.
         */
        public static DiagramLegend read_legend_block(Gee.ArrayList<Token> tokens, ref int pos) {
            var legend = new DiagramLegend("");
            pos++;  // legend
            while (pos < tokens.size && !legend_line_end(tokens[pos])) {
                string w = tokens[pos].lexeme.down();
                if (w == "left" || w == "right" || w == "center") {
                    legend.halign = w;
                } else if (w == "top" || w == "bottom") {
                    legend.valign = w;
                }
                pos++;
            }
            var text = new StringBuilder();
            var line = new StringBuilder();
            bool closed = false;
            while (pos < tokens.size) {
                var t = tokens[pos];
                if (t.token_type == TokenType.EOF || t.token_type == TokenType.ENDUML) {
                    break;
                }
                if (t.token_type == TokenType.NEWLINE) {
                    text.append(line.str);
                    text.append("\n");
                    line.truncate(0);
                    pos++;
                    continue;
                }
                if (line.len == 0) {
                    string low = t.lexeme.down();
                    if (low == "endlegend" ||
                        (low == "end" && pos + 1 < tokens.size && tokens[pos + 1].lexeme.down() == "legend")) {
                        closed = true;
                        pos += low == "end" ? 2 : 1;
                        while (pos < tokens.size && !legend_line_end(tokens[pos])) {
                            pos++;
                        }
                        break;
                    }
                } else if (t.space_before) {
                    line.append(" ");
                }
                line.append(t.token_type == TokenType.STRING ? "\"" + t.lexeme + "\"" : t.lexeme);
                pos++;
            }
            if (!closed) {
                text.append(line.str);
            }
            legend.text = text.str.strip();
            return legend;
        }

        private static bool legend_line_end(Token t) {
            return t.token_type == TokenType.NEWLINE || t.token_type == TokenType.EOF ||
                   t.token_type == TokenType.ENDUML;
        }

        /**
         * The text of the "[...]" at the cursor, through its "]". The lexer takes a "'" or
         * "<style>" anywhere as the start of a comment running to the end of the line (or
         * file), so "[crow's foot] as cf" and "[Preprocessor (<style> blocks)]" swallowed the
         * alias and the following lines. The comment's text up to its "]" belongs to the
         * label; the rest is lexed again in its place.
         */
        private string read_bracket_text() {
            advance();  // [
            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.RBRACKET)) {
                var t = tokens[current];
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                int close = t.token_type == TokenType.COMMENT ? t.lexeme.index_of("]") : -1;
                if (close >= 0) {
                    sb.append(t.lexeme.substring(0, close));
                    split_token_at(current, close);
                    continue;
                }
                sb.append(t.lexeme);
                advance();
            }
            if (check(TokenType.RBRACKET)) {
                advance();
            }
            return sb.str.strip();
        }

        // Replaces tokens[idx] by the tokens of its lexeme from byte `offset` on
        private void split_token_at(int idx, int offset) {
            var t = tokens[idx];
            int column_shift = t.column + t.lexeme.substring(0, offset).char_count() - 1;
            var relexed = new Lexer(t.lexeme.substring(offset)).scan_all();
            tokens.remove_at(idx);
            int at = idx;
            foreach (var r in relexed) {
                if (r.token_type == TokenType.EOF) {
                    continue;
                }
                if (r.line == 1) {
                    r.column += column_shift;
                }
                r.line += t.line - 1;
                tokens.insert(at++, r);
            }
        }

        // Top-level declaration, or a child of `parent` (a nested 'device')
        private void parse_container(Component? parent = null) throws Error {
            ComponentType container_type;

            if (check(TokenType.PACKAGE)) {
                container_type = ComponentType.PACKAGE;
            } else if (check(TokenType.NODE_KW) || is_device_declaration()) {
                container_type = ComponentType.NODE;
            } else if (check(TokenType.FOLDER)) {
                container_type = ComponentType.FOLDER;
            } else if (check(TokenType.FRAME)) {
                container_type = ComponentType.FRAME;
            } else if (check(TokenType.CLOUD)) {
                container_type = ComponentType.CLOUD;
            } else if (check(TokenType.STORAGE)) {
                container_type = ComponentType.STORAGE;
            } else if (check(TokenType.DATABASE)) {
                container_type = ComponentType.DATABASE;
            } else {
                container_type = ComponentType.PACKAGE;
            }
            advance();

            skip_whitespace();

            // Get name (can be string or identifier)
            string name = read_element_name();

            var container = new Component(name, container_type);
            // 'node "Web Server" as web': the quoted text is the label, not the alias
            if (last_name_quoted) {
                container.label = name;
            }
            // Only a body makes a container. 'node "Web Server" as web' is a node box in
            // PlantUML; it was drawn as an empty cluster titled with the alias. An empty
            // package is still drawn as a package.
            container.is_container = container_type == ComponentType.PACKAGE;

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                bool name_quoted = last_name_quoted;
                advance();
                skip_whitespace();
                read_alias_into(container, name, name_quoted);
            }

            skip_whitespace();

            // Stereotypes: "<<a>>" (one token) or a split "< <", possibly several
            read_stereotypes(container);

            skip_whitespace();

            // Check for color
            try_parse_color(container);

            skip_whitespace();

            // Check for { to start container body
            if (check(TokenType.LBRACE)) {
                container.is_container = true;
                advance();
                parse_container_body(container);
            }

            if (parent != null) {
                parent.children.add(container);
            } else {
                diagram.components.add(container);
            }
        }

        private bool is_device_declaration() {
            return check(TokenType.IDENTIFIER) && current_lexeme() == "device" && is_declaration_word();
        }

        private void parse_container_body(Component container) throws Error {
            ComponentType nested_word_type = ComponentType.COMPONENT;
            // Elements first mentioned in this body (link ends included) belong to it
            open_containers.add(container);
            // An unclosed body ends at @enduml; it used to swallow it
            while (!is_at_end() && !check(TokenType.RBRACE) && !check(TokenType.ENDUML)) {
                skip_newlines();
                if (is_at_end() || check(TokenType.RBRACE) || check(TokenType.ENDUML)) break;
                int before = current;

                // Parse nested components
                if (check(TokenType.COMPONENT)) {
                    advance(); // consume 'component' keyword
                    var comp = parse_component_inner();
                    if (comp != null) {
                        container.children.add(comp);
                    }
                } else if (check(TokenType.LBRACKET)) {
                    var comp = parse_bracket_component_inner();
                    if (comp != null) {
                        add_bracket_component(comp, container.children);
                    }
                } else if (check(TokenType.PACKAGE) || check(TokenType.NODE_KW) ||
                           check(TokenType.FOLDER) || check(TokenType.FRAME)) {
                    // Nested containers
                    parse_nested_container(container);
                } else if (is_device_declaration()) {
                    parse_container(container);
                } else if (check(TokenType.RECTANGLE) || check(TokenType.ARTIFACT) ||
                           check(TokenType.CARD) || check(TokenType.AGENT) ||
                           check(TokenType.QUEUE) || check(TokenType.BOUNDARY) ||
                           check(TokenType.CONTROL) || check(TokenType.ENTITY) ||
                           check(TokenType.DATABASE) || check(TokenType.STORAGE) ||
                           check(TokenType.CLOUD) || check(TokenType.ACTOR) ||
                           check(TokenType.USECASE)) {
                    // Nested element. DATABASE is here (not in nested-containers
                    // above) because parse_element_inner handles the C4-style
                    // `database "..." as db` leaf form correctly, while
                    // parse_nested_container would always make it a cluster.
                    var elem = parse_element_inner();
                    if (elem != null) {
                        container.children.add(elem);
                    }
                } else if (check(TokenType.INTERFACE) ||
                           (check(TokenType.LPAREN) && peek_next_is(TokenType.RPAREN))) {
                    // Interface in container - add as child AND register for relationships
                    if (check(TokenType.INTERFACE)) {
                        parse_interface_in_container(container);
                    } else {
                        parse_circle_interface();
                    }
                } else if (check(TokenType.NOTE)) {
                    parse_note();
                } else if (check(TokenType.IDENTIFIER) && current_lexeme() == "together") {
                    parse_together_block_nested(container);
                } else if (check(TokenType.LPAREN) || check(TokenType.COLON)) {
                    // "(Use case)" / ":Actor: as A" shorthands, as at top level
                    parse_shorthand_element(check(TokenType.LPAREN) ? ComponentType.USECASE : ComponentType.ACTOR,
                                            container.children);
                } else if ((check(TokenType.IDENTIFIER) || check(TokenType.COLLECTIONS)) &&
                           element_word_type(current_lexeme(), out nested_word_type) && is_declaration_word()) {
                    // file, stack, person, hexagon, ...: they became components named after the keyword
                    var elem = parse_identifier_element_inner(nested_word_type);
                    if (elem != null) {
                        container.children.add(elem);
                    }
                } else if (is_json_declaration()) {
                    parse_json_block(container.children);
                } else if (check(TokenType.PORTIN) || check(TokenType.PORTOUT) || check(TokenType.PORT)) {
                    // "node n { port p1 }": a port on the container's border. It became a
                    // component box named after the port.
                    parse_port(container);
                } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) ||
                           (is_name_word_at(current) && is_component_arrow_piece(current + 1, true))) {
                    // Could be nested element or relationship ("left --> right": keyword names)
                    parse_nested_element_or_relationship(container);
                } else {
                    advance();
                }

                if (current == before) {
                    advance();
                }
            }

            open_containers.remove_at(open_containers.size - 1);

            // Consume closing brace
            if (check(TokenType.RBRACE)) {
                advance();
            }
        }

        // Containers whose body is being parsed, innermost last. A container joins its
        // parent only after its body, so links inside it must look here as well.
        private Gee.ArrayList<Component> open_containers = new Gee.ArrayList<Component>();

        private static Component? find_in_tree(Component comp, string id) {
            if (comp.id == id || comp.alias == id) {
                return comp;
            }
            foreach (var child in comp.children) {
                var found = find_in_tree(child, id);
                if (found != null) {
                    return found;
                }
            }
            return null;
        }

        // An element declared so far, including those in the containers still open
        private Component? find_declared(string id) {
            var found = diagram.find_component(id);
            for (int i = 0; found == null && i < open_containers.size; i++) {
                found = find_in_tree(open_containers[i], id);
            }
            return found;
        }

        // Where a newly mentioned element goes: the innermost open body, or the top level
        private Gee.ArrayList<Component> declaration_scope() {
            return open_containers.size > 0 ? open_containers[open_containers.size - 1].children
                                            : diagram.components;
        }

        // A link end names an element. PlantUML declares it at its first mention, in the
        // body where that mention is; link ends inside a body were created at the top level
        // ([A]) or not at all (bare names), so they were drawn outside their container.
        // A bare name at the top level stays undeclared, as before.
        private void declare_link_end(string id, bool bracketed) {
            if (id.length == 0 || find_declared(id) != null || diagram.find_interface(id) != null) {
                return;
            }
            foreach (var port in diagram.ports) {
                if (port.id == id) {
                    return;
                }
            }
            foreach (var note in diagram.notes) {
                if (note.id == id) {
                    return;
                }
            }
            if (!bracketed && open_containers.size == 0) {
                return;
            }
            var comp = new Component(id, ComponentType.COMPONENT);
            comp.link_end = !bracketed;
            declaration_scope().add(comp);
        }

        // "node N { A --> db }" followed by "database db": PlantUML rejects the redeclaration.
        // The declaration wins, as it did before link ends in bodies were declared.
        private void drop_link_ends_declared_later() {
            var declared = new Gee.HashSet<string>();
            collect_declared_names(diagram.components, declared);
            foreach (var port in diagram.ports) {
                declared.add(port.id);
            }
            foreach (var iface in diagram.interfaces) {
                declared.add(iface.id);
                declared.add(iface.get_identifier());
            }
            foreach (var note in diagram.notes) {
                declared.add(note.id);
            }
            remove_link_ends(diagram.components, declared);
        }

        private static void collect_declared_names(Gee.ArrayList<Component> comps, Gee.HashSet<string> names) {
            foreach (var c in comps) {
                if (!c.link_end) {
                    names.add(c.id);
                    if (c.alias != null) {
                        names.add(c.alias);
                    }
                }
                collect_declared_names(c.children, names);
            }
        }

        private static void remove_link_ends(Gee.ArrayList<Component> comps, Gee.HashSet<string> declared) {
            for (int i = comps.size - 1; i >= 0; i--) {
                if (comps[i].link_end && declared.contains(comps[i].id)) {
                    comps.remove_at(i);
                } else {
                    remove_link_ends(comps[i].children, declared);
                }
            }
        }

        // "[App]" names the element declared earlier, which stays where it is; a first
        // mention is added to `into`. In a body a second App used to be created.
        private void add_bracket_component(Component comp, Gee.ArrayList<Component> into) {
            var existing = comp.alias == null ? find_declared(comp.id) : null;
            if (existing == null) {
                into.add(comp);
                return;
            }
            if (existing.link_end) {
                existing.link_end = false;
                existing.label = comp.label;
            }
            if (comp.stereotype != null) {
                existing.stereotype = comp.stereotype;
            }
            if (comp.color != null) {
                existing.color = comp.color;
            }
        }

        private void parse_nested_container(Component parent) throws Error {
            ComponentType container_type;

            if (check(TokenType.PACKAGE)) {
                container_type = ComponentType.PACKAGE;
            } else if (check(TokenType.NODE_KW)) {
                container_type = ComponentType.NODE;
            } else if (check(TokenType.FOLDER)) {
                container_type = ComponentType.FOLDER;
            } else if (check(TokenType.FRAME)) {
                container_type = ComponentType.FRAME;
            } else if (check(TokenType.CLOUD)) {
                container_type = ComponentType.CLOUD;
            } else if (check(TokenType.DATABASE)) {
                container_type = ComponentType.DATABASE;
            } else {
                container_type = ComponentType.STORAGE;
            }
            advance();

            skip_whitespace();

            string name = read_element_name();
            bool name_quoted = last_name_quoted;

            var nested = new Component(name, container_type);
            if (name_quoted) {
                nested.label = name;
            }
            // As at the top level: only a body makes a container, except an empty package.
            // A nested 'node X' was drawn as an empty cluster.
            nested.is_container = container_type == ComponentType.PACKAGE;

            skip_whitespace();

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                read_alias_into(nested, name, name_quoted);
            }

            skip_whitespace();

            read_stereotypes(nested);

            // Check for color
            try_parse_color(nested);

            skip_whitespace();

            if (check(TokenType.LBRACE)) {
                nested.is_container = true;
                advance();
                parse_container_body(nested);
            }

            parent.children.add(nested);
        }

        private void parse_nested_element_or_relationship(Component container) {
            string first_id;
            if (check(TokenType.STRING)) {
                first_id = get_string_value(current_lexeme());
            } else {
                first_id = current_lexeme();
            }
            advance();

            skip_whitespace();

            // Check for relationship arrow
            if (is_relationship_arrow()) {
                declare_link_end(first_id, false);
                parse_relationship_from(first_id);
            } else {
                // It's a simple element reference - create component if not exists
                var comp = new Component(first_id);
                container.children.add(comp);
                skip_to_newline();
            }
        }

        private void parse_component_declaration() throws Error {
            advance(); // consume 'component'
            var comp = parse_component_inner();
            if (comp != null) {
                diagram.components.add(comp);
            }
        }

        private Component? parse_element_inner() throws Error {
            ComponentType elem_type;
            if (check(TokenType.ARTIFACT)) {
                elem_type = ComponentType.ARTIFACT;
            } else if (check(TokenType.CARD)) {
                elem_type = ComponentType.CARD;
            } else if (check(TokenType.AGENT)) {
                elem_type = ComponentType.AGENT;
            } else if (check(TokenType.QUEUE)) {
                elem_type = ComponentType.QUEUE;
            } else if (check(TokenType.BOUNDARY)) {
                elem_type = ComponentType.BOUNDARY;
            } else if (check(TokenType.CONTROL)) {
                elem_type = ComponentType.CONTROL;
            } else if (check(TokenType.ENTITY)) {
                elem_type = ComponentType.ENTITY;
            } else if (check(TokenType.DATABASE)) {
                elem_type = ComponentType.DATABASE;
            } else if (check(TokenType.STORAGE)) {
                elem_type = ComponentType.STORAGE;
            } else if (check(TokenType.CLOUD)) {
                elem_type = ComponentType.CLOUD;
            } else if (check(TokenType.ACTOR)) {
                elem_type = ComponentType.ACTOR;
            } else if (check(TokenType.USECASE)) {
                elem_type = ComponentType.USECASE;
            } else {
                elem_type = ComponentType.RECTANGLE;
            }
            advance();

            skip_whitespace();

            string name = "";
            bool name_was_string = false;
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                name_was_string = true;
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            } else {
                return null;
            }

            var comp = new Component(name, elem_type);
            if (name_was_string) {
                comp.label = name;
            }

            skip_whitespace();

            // Optional <<stereotype>>s before "as alias" (C4-PlantUML form)
            read_stereotypes(comp);

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                read_alias_into(comp, name, name_was_string);
            }

            skip_whitespace();

            // Stereotypes may also appear AFTER the alias
            read_stereotypes(comp);

            // Check for color
            try_parse_color(comp);

            skip_whitespace();

            // Skip optional [[link]] hyperlink (possibly empty/unterminated)
            if (check(TokenType.LBRACKET) && peek_next_is(TokenType.LBRACKET)) {
                advance();
                advance();
                while (!is_at_end()) {
                    if (check(TokenType.RBRACKET) && peek_next_is(TokenType.RBRACKET)) {
                        advance();
                        advance();
                        break;
                    }
                    if (check(TokenType.LBRACE) || check(TokenType.NEWLINE) || check(TokenType.ENDUML)) {
                        break;
                    }
                    advance();
                }
                skip_whitespace();
            }

            // Check for { to make this a container
            if (check(TokenType.LBRACE)) {
                comp.is_container = true;
                advance();
                parse_container_body(comp);
            } else {
                skip_to_newline();
            }

            return comp;
        }

        private Component? parse_component_inner() throws Error {
            skip_whitespace();

            string name = read_element_name();
            if (name.length == 0) {
                return null;
            }

            var comp = new Component(name, ComponentType.COMPONENT);
            // 'component "Alert" as W': the quoted text is the label; without this the
            // alias was shown instead
            if (last_name_quoted) {
                comp.label = name;
            }

            skip_whitespace();

            // Stereotype may come before the alias ('component "X" <<s>> as Y')
            read_stereotypes(comp);

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                string? alias_word = read_alias();
                if (alias_word != null) {
                    comp.alias = alias_word;
                }
            }

            skip_whitespace();

            // Check for stereotype: one <<name>> token, or two "<" when the lexer split it.
            // Only the split form was handled, so '... as W <<warning>>' lost its stereotype.
            read_stereotypes(comp);

            skip_whitespace();

            // Check for color
            try_parse_color(comp);

            skip_whitespace();
            // "component component { }": a body. It was skipped with the line and the
            // "}" left over.
            if (check(TokenType.LBRACE)) {
                comp.is_container = true;
                advance();
                parse_container_body(comp);
            }

            skip_to_newline();
            return comp;
        }

        private void parse_interface_declaration() {
            advance(); // consume 'interface'
            skip_whitespace();

            string name = read_element_name();
            if (name.length == 0) {
                return;
            }

            var iface = new ComponentInterface(name);

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                string? alias_word = read_alias();
                if (alias_word != null) {
                    iface.alias = alias_word;
                }
            }

            diagram.interfaces.add(iface);
            // "() name )-0-(0 [target]": a link can follow on the same line
            skip_whitespace();
            if (is_relationship_arrow()) {
                parse_relationship_from(iface.get_identifier());
                return;
            }
            skip_to_newline();
        }

        private void parse_interface_in_container(Component container) {
            advance(); // consume 'interface'
            skip_whitespace();

            string name = read_element_name();
            if (name.length == 0) {
                return;
            }

            // A child component, drawn inside the container. It used to be added to
            // diagram.interfaces as well, so the interface was written twice in the DOT
            // (inside the cluster and again at the top level). Links find it as a
            // component, and the renderer attaches them to its circle.
            var comp = new Component(name, ComponentType.INTERFACE);
            bool name_quoted = last_name_quoted;
            container.children.add(comp);

            skip_whitespace();

            // 'interface "10/100 Mbps" as ETH': the quoted text is the caption. Only the
            // alias was kept, so "ETH" was drawn.
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                read_alias_into(comp, name, name_quoted);
            } else if (name_quoted) {
                comp.label = name;
            }
            skip_whitespace();
            read_stereotypes(comp);
            try_parse_color(comp);

            // "() name )-0-(0 [target]": a link can follow on the same line
            skip_whitespace();
            if (is_relationship_arrow()) {
                parse_relationship_from(comp.get_identifier());
                return;
            }
            skip_to_newline();
        }

        private void parse_bracket_component() {
            var comp = parse_bracket_component_inner();
            if (comp != null) {
                // "[App]" again names the element declared earlier, not a second one
                add_bracket_component(comp, diagram.components);
            }
        }

        private Component? parse_bracket_component_inner() {
            string name = read_bracket_text();
            if (name.length == 0) {
                return null;
            }

            var comp = new Component(name, ComponentType.COMPONENT);
            // The bracket text is the display label even when an alias follows
            // ("[Title\nDetails] as t"). Without it get_display_label() fell
            // through to the alias and the user's text was never shown.
            comp.label = name;

            skip_whitespace();

            // "[X] <<ui>> as a": a stereotype before the alias. The alias was lost, so every
            // link to "a" drew a separate ghost node.
            read_stereotypes(comp);

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                string? alias_word = read_alias();
                if (alias_word != null) {
                    comp.alias = alias_word;
                }
            }

            skip_whitespace();

            // "[Web Server] as WS <<frontend>> #pink": the stereotype and colour after the
            // alias were skipped with the rest of the line
            read_stereotypes(comp);
            try_parse_color(comp);
            skip_whitespace();

            // Check for relationship arrow
            if (is_relationship_arrow()) {
                // "[App] --> [DB]" after "node web { [App] <<svc>> #F00 }" names the declared
                // App. A second top-level App was created, and it replaced the declaration
                // (stereotype, colour and container lost).
                var existing = comp.alias == null ? find_declared(name) : null;
                if (existing != null) {
                    add_bracket_component(comp, declaration_scope());
                    parse_relationship_from(existing.get_identifier());
                    return null;
                }
                // Register component first, in the body the link is written in: it was
                // always added at the top level
                declaration_scope().add(comp);
                parse_relationship_from(comp.get_identifier());
                return null; // Already added
            }

            skip_to_newline();
            return comp;
        }

        private void parse_circle_interface() {
            advance(); // consume '('
            advance(); // consume ')'
            skip_whitespace();

            if (!check(TokenType.IDENTIFIER) && !check(TokenType.STRING)) {
                return;
            }

            string name;
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
            } else {
                name = current_lexeme();
            }
            advance();

            var iface = new ComponentInterface(name);

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                string? alias_word = read_alias();
                if (alias_word != null) {
                    iface.alias = alias_word;
                }
            }

            diagram.interfaces.add(iface);
            // "() name )-0-(0 [target]": a link can follow on the same line
            skip_whitespace();
            if (is_relationship_arrow()) {
                parse_relationship_from(iface.get_identifier());
                return;
            }
            skip_to_newline();
        }

        private void parse_identifier_element_declaration(ComponentType elem_type) throws Error {
            advance(); // consume keyword (e.g. 'file')
            skip_whitespace();

            if (check(TokenType.LBRACKET) && !peek_next_is(TokenType.LBRACKET)) {
                parse_bracket_component();  // "file [Logs]" is a component, as in PlantUML
                return;
            }

            string name = read_element_name();

            var comp = new Component(name, elem_type);

            skip_whitespace();

            if (check(TokenType.AS)) {
                bool name_quoted = last_name_quoted;
                advance();
                skip_whitespace();
                read_alias_into(comp, name, name_quoted);
            }

            skip_whitespace();

            try_parse_color(comp);

            skip_whitespace();

            // Check for { to make this a container
            if (check(TokenType.LBRACE)) {
                comp.is_container = true;
                advance();
                parse_container_body(comp);
            }

            diagram.components.add(comp);
            skip_to_newline();
        }

        private Component? parse_identifier_element_inner(ComponentType elem_type) throws Error {
            advance(); // consume keyword (e.g. 'file')
            skip_whitespace();

            string name = read_element_name();
            if (name.length == 0) {
                return null;
            }

            var comp = new Component(name, elem_type);

            skip_whitespace();

            if (check(TokenType.AS)) {
                bool name_quoted = last_name_quoted;
                advance();
                skip_whitespace();
                read_alias_into(comp, name, name_quoted);
            }

            skip_whitespace();

            try_parse_color(comp);

            skip_whitespace();

            if (check(TokenType.LBRACE)) {
                comp.is_container = true;
                advance();
                parse_container_body(comp);
            } else {
                skip_to_newline();
            }

            return comp;
        }

        private void parse_together_block_top() throws Error {
            advance(); // consume 'together'
            skip_whitespace();

            if (check(TokenType.LBRACE)) {
                advance();
                skip_newlines();

                // "together {" left open: parse_statement() returns at @enduml without
                // consuming it, and this loop spun forever (a hang on every keystroke)
                while (!is_at_end() && !check(TokenType.RBRACE) && !check(TokenType.ENDUML)) {
                    skip_newlines();
                    if (is_at_end() || check(TokenType.RBRACE) || check(TokenType.ENDUML)) break;
                    int before = current;
                    parse_statement();
                    if (current == before) {
                        advance();
                    }
                }

                if (check(TokenType.RBRACE)) {
                    advance();
                }
            } else {
                skip_to_newline();
            }
        }

        private void parse_together_block_nested(Component container) throws Error {
            advance(); // consume 'together'
            skip_whitespace();

            if (check(TokenType.LBRACE)) {
                advance();
                // Re-use container body parsing — children go into parent container
                while (!is_at_end() && !check(TokenType.RBRACE) && !check(TokenType.ENDUML)) {
                    skip_newlines();
                    if (is_at_end() || check(TokenType.RBRACE) || check(TokenType.ENDUML)) break;
                    int before = current;

                    // Parse nested components
                    if (check(TokenType.COMPONENT)) {
                        advance(); // consume 'component' keyword
                        var comp = parse_component_inner();
                        if (comp != null) {
                            container.children.add(comp);
                        }
                    } else if (check(TokenType.LBRACKET)) {
                        var comp = parse_bracket_component_inner();
                        if (comp != null) {
                            add_bracket_component(comp, container.children);
                        }
                    } else if (check(TokenType.PACKAGE) || check(TokenType.NODE_KW) ||
                               check(TokenType.FOLDER) || check(TokenType.FRAME) ||
                               check(TokenType.CLOUD) || check(TokenType.STORAGE) ||
                               check(TokenType.DATABASE)) {
                        parse_nested_container(container);
                    } else if (check(TokenType.RECTANGLE) || check(TokenType.ARTIFACT) ||
                               check(TokenType.CARD) || check(TokenType.AGENT) ||
                               check(TokenType.QUEUE) || check(TokenType.BOUNDARY) ||
                               check(TokenType.CONTROL) || check(TokenType.ENTITY)) {
                        var elem = parse_element_inner();
                        if (elem != null) {
                            container.children.add(elem);
                        }
                    } else if (check(TokenType.IDENTIFIER) && current_lexeme() == "file") {
                        var elem = parse_identifier_element_inner(ComponentType.FILE);
                        if (elem != null) {
                            container.children.add(elem);
                        }
                    } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) ||
                               (is_name_word_at(current) && is_component_arrow_piece(current + 1, true))) {
                        parse_nested_element_or_relationship(container);
                    } else {
                        advance();
                    }
                    if (current == before) {
                        advance();
                    }
                }

                if (check(TokenType.RBRACE)) {
                    advance();
                }
            } else {
                skip_to_newline();
            }
        }

        private void parse_element_declaration() throws Error {
            ComponentType elem_type;
            if (check(TokenType.ARTIFACT)) {
                elem_type = ComponentType.ARTIFACT;
            } else if (check(TokenType.CARD)) {
                elem_type = ComponentType.CARD;
            } else if (check(TokenType.AGENT)) {
                elem_type = ComponentType.AGENT;
            } else if (check(TokenType.QUEUE)) {
                elem_type = ComponentType.QUEUE;
            } else if (check(TokenType.BOUNDARY)) {
                elem_type = ComponentType.BOUNDARY;
            } else if (check(TokenType.CONTROL)) {
                elem_type = ComponentType.CONTROL;
            } else if (check(TokenType.ENTITY)) {
                elem_type = ComponentType.ENTITY;
            } else if (check(TokenType.DATABASE)) {
                elem_type = ComponentType.DATABASE;
            } else if (check(TokenType.STORAGE)) {
                elem_type = ComponentType.STORAGE;
            } else if (check(TokenType.CLOUD)) {
                elem_type = ComponentType.CLOUD;
            } else if (check(TokenType.ACTOR)) {
                elem_type = ComponentType.ACTOR;
            } else if (check(TokenType.USECASE)) {
                elem_type = ComponentType.USECASE;
            } else {
                elem_type = ComponentType.RECTANGLE;
            }
            advance();

            skip_whitespace();

            // "database [PostgreSQL] #LightBlue": PlantUML reads the bracket form as a
            // component; it used to leave an element with an empty name plus an
            // uncoloured second component
            if (check(TokenType.LBRACKET) && !peek_next_is(TokenType.LBRACKET)) {
                parse_bracket_component();
                return;
            }

            string name = read_element_name();
            bool name_was_string = last_name_quoted;

            var comp = new Component(name, elem_type);
            comp.business = last_name_business;
            // When the source had a quoted "label", store it as the display
            // label too. Otherwise get_display_label() falls through to the
            // alias when an alias exists, losing the user's text.
            if (name_was_string) {
                comp.label = name;
            }

            skip_whitespace();

            // Check for <<stereotype>> BEFORE "as alias". C4-PlantUML emits
            // declarations like: rectangle "label" <<person>> as customer.
            // The lexer recognises <<name>> as a single STEREOTYPE token, but
            // unrecognised inputs may fall back to two literal '<' identifiers.
            // "<<system_boundary>><<boundary>>": every stereotype is read. Only the first
            // was, so the alias and the "{" of the body were never reached and the
            // children were lost.
            read_stereotypes(comp);

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                read_alias_into(comp, name, name_was_string);
            }

            skip_whitespace();

            // Stereotypes may also appear AFTER the alias (rare but allowed)
            read_stereotypes(comp);

            // Check for color
            try_parse_color(comp);

            skip_whitespace();

            // Skip an optional [[link]] / [[link text]] hyperlink. C4-PlantUML
            // emits `as alias [[ ... ]]` even when the link is empty (i.e.
            // just `[[ {` with no closing ]]). Consume tokens until we hit
            // either the closing ]] OR a structurally significant token
            // (`{` for container body, NEWLINE for end of declaration).
            if (check(TokenType.LBRACKET) && peek_next_is(TokenType.LBRACKET)) {
                advance();  // first [
                advance();  // second [
                while (!is_at_end()) {
                    if (check(TokenType.RBRACKET) && peek_next_is(TokenType.RBRACKET)) {
                        advance();
                        advance();
                        break;
                    }
                    if (check(TokenType.LBRACE) || check(TokenType.NEWLINE) || check(TokenType.ENDUML)) {
                        // Unterminated [[ — leave the structural token for
                        // the caller to handle.
                        break;
                    }
                    advance();
                }
                skip_whitespace();
            }

            // Check for { to make this a container
            if (check(TokenType.LBRACE)) {
                comp.is_container = true;
                advance();
                parse_container_body(comp);
            }

            diagram.components.add(comp);
            skip_to_newline();
        }

        // A port; inside a container body `parent` is that container
        private void parse_port(Component? parent = null) {
            PortType port_type;
            if (check(TokenType.PORTIN)) {
                port_type = PortType.IN;
            } else if (check(TokenType.PORTOUT)) {
                port_type = PortType.OUT;
            } else {
                port_type = PortType.BIDIRECTIONAL;
            }
            advance();

            skip_whitespace();

            string? name = null;
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            }

            var port = new ComponentPort(name, port_type);

            skip_whitespace();

            // Check for "as Alias"
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    port.id = current_lexeme();
                    if (name != null) {
                        port.label = name;
                    }
                    advance();
                }
            }

            if (parent != null) {
                port.parent_component = parent.get_identifier();
            }
            diagram.ports.add(port);
            skip_to_newline();
        }

        private void parse_identifier_or_relationship() {
            string first_id;
            if (check(TokenType.STRING)) {
                first_id = get_string_value(current_lexeme());
            } else {
                first_id = current_lexeme();
            }
            advance();

            skip_whitespace();

            // Check for relationship arrow
            if (is_relationship_arrow()) {
                parse_relationship_from(first_id);
            } else {
                // Unknown statement
                skip_to_newline();
            }
        }

        // Multiplicity written before the arrow ("C "1" --> "many" D"), consumed by
        // is_relationship_arrow() and picked up by parse_relationship_from()
        private string? pending_tail_label = null;

        // True when a link arrow starts at the cursor. A quoted multiplicity in front of the
        // arrow is consumed into pending_tail_label; the link was dropped.
        private bool is_relationship_arrow() {
            pending_tail_label = null;
            if (check(TokenType.STRING)) {
                int save = current;
                string text = get_string_value(current_lexeme());
                advance();
                if (is_arrow_at_cursor()) {
                    pending_tail_label = text;
                    return true;
                }
                current = save;
                return false;
            }
            return is_arrow_at_cursor();
        }

        private bool is_arrow_at_cursor() {
            if (check(TokenType.STRING)) {
                return false;
            }
            // Check for various arrow types
            if (check(TokenType.ARROW_RIGHT) || check(TokenType.ARROW_RIGHT_DOTTED) ||
                check(TokenType.ARROW_LEFT) || check(TokenType.ARROW_LEFT_DOTTED) ||
                check(TokenType.DEPENDENCY) || check(TokenType.MINUS)) {
                return true;
            }

            if (is_component_arrow_piece(current, true)) {
                return true;
            }

            // Check for custom arrows with direction hints
            string lex = current_lexeme();
            if (lex.has_prefix("-") || lex.has_prefix(".") ||
                lex.has_prefix("<") || lex.has_suffix(">")) {
                return true;
            }

            return false;
        }

        private bool last_name_quoted = false;
        // "actor/" / "usecase/": the slash glued to the keyword
        private bool last_name_business = false;

        // Element name after a keyword: a quoted string, or any word including one
        // that is itself a keyword ("actor actor", "node node"). A slash glued to
        // the keyword ("actor/", "usecase/": business variants) is skipped. Keyword
        // names used to come back empty and all such elements merged into one.
        private string read_element_name() {
            last_name_quoted = false;
            last_name_business = false;
            if (current_lexeme() == "/" && !tokens[current].space_before) {
                last_name_business = true;
                advance();
                skip_whitespace();
            }
            if (check(TokenType.STRING)) {
                last_name_quoted = true;
                string quoted = get_string_value(current_lexeme());
                advance();
                return quoted;
            }
            if (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check(TokenType.AS) &&
                current_lexeme().length > 0 && (current_lexeme().get_char(0).isalnum() || current_lexeme().has_prefix("_"))) {
                // "_internal": an underscore start is a name too (read_alias already took it)
                string word = current_lexeme();
                advance();
                return word;
            }
            return "";
        }

        // "X as Y" for element keywords: a quoted side is the label and the other the id;
        // with neither quoted the name is the label and the alias the id, as PlantUML shows
        // 'node Node1 as n1' ("Node1") and 'file f1 as "File 1"' ("File 1", linked as f1).
        // Only the alias was kept, so the alias text was drawn instead of the name.
        private void read_alias_into(Component comp, string name, bool name_quoted) {
            if (check(TokenType.STRING)) {
                string quoted = get_string_value(current_lexeme());
                advance();
                if (name_quoted) {
                    comp.alias = quoted;
                } else {
                    comp.label = quoted;
                }
                return;
            }
            string? alias_word = read_alias();
            if (alias_word != null) {
                comp.alias = alias_word;
                if (comp.label == null) {
                    comp.label = name;
                }
            }
        }

        // An alias may be a keyword (`as node {`); accepting only IDENTIFIER left the
        // word and the following `{` unconsumed, so the container body was skipped
        private string? read_alias() {
            if (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check(TokenType.STRING) &&
                current_lexeme().length > 0 && (current_lexeme().get_char(0).isalnum() || current_lexeme().has_prefix("_"))) {
                string word = current_lexeme();
                advance();
                return word;
            }
            return null;
        }

        private static bool element_word_type(string word, out ComponentType type) {
            type = ComponentType.COMPONENT;
            switch (word) {
                case "file": type = ComponentType.FILE; return true;
                case "stack": type = ComponentType.STACK; return true;
                case "collections": type = ComponentType.COLLECTIONS; return true;
                case "person": type = ComponentType.PERSON; return true;
                case "action": type = ComponentType.ACTION; return true;
                case "process": type = ComponentType.PROCESS; return true;
                case "circle": type = ComponentType.CIRCLE; return true;
                case "hexagon": type = ComponentType.HEXAGON; return true;
                case "label": type = ComponentType.LABEL; return true;
                default: return false;
            }
        }

        // The keyword at the cursor starts a declaration: a name follows, not an arrow
        private bool is_declaration_word() {
            if (current + 1 >= tokens.size) {
                return false;
            }
            var next = tokens[current + 1];
            return next.token_type != TokenType.NEWLINE && next.token_type != TokenType.EOF &&
                   next.token_type != TokenType.COLON && !is_component_arrow_piece(current + 1, true);
        }

        // "(Use case)" or ":Actor:" name at the cursor; consumes the delimiters
        private string? read_shorthand_name() {
            TokenType close = check(TokenType.LPAREN) ? TokenType.RPAREN : TokenType.COLON;
            advance();
            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE) && !check(close)) {
                if (sb.len > 0 && tokens[current].space_before) {
                    sb.append(" ");
                }
                sb.append(current_lexeme());
                advance();
            }
            if (!check(close)) {
                return null;
            }
            advance();
            string name = sb.str.strip();
            return name.length > 0 ? name : null;
        }

        // Finds or creates the element; a new one goes into `into` (a container's children)
        // or the top level
        private Component shorthand_component(string name, ComponentType type,
                                              Gee.ArrayList<Component>? into = null) {
            var comp = find_declared(name);
            if (comp == null) {
                comp = new Component(name, type);
                comp.label = name;
                (into ?? declaration_scope()).add(comp);
            }
            return comp;
        }

        // "(Use case) [as alias] [link]" and ":Actor: [as alias] [link]"
        private void parse_shorthand_element(ComponentType type, Gee.ArrayList<Component>? into = null) {
            string? name = read_shorthand_name();
            if (name == null) {
                skip_to_newline();
                return;
            }
            var comp = shorthand_component(name, type, into);
            skip_whitespace();
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.LPAREN) || check(TokenType.COLON)) {
                    string? alias = read_shorthand_name();
                    if (alias != null) {
                        comp.alias = alias;
                    }
                } else {
                    string? alias_word = read_alias();
                    if (alias_word != null) {
                        comp.alias = alias_word;
                    }
                }
                skip_whitespace();
            }
            if (is_relationship_arrow()) {
                parse_relationship_from(comp.get_identifier());
                return;
            }
            skip_to_newline();
        }

        private const string COMPONENT_ARROW_CHARS = "-.~=<>|*o#x+^(){}0";

        private static bool has_arrow_line(string s) {
            for (int i = 0; i < s.length; i++) {
                if ("-.~=".index_of_char(s[i]) >= 0) {
                    return true;
                }
            }
            return false;
        }

        private static bool all_arrow_chars(string s) {
            if (s.length == 0) {
                return false;
            }
            for (int i = 0; i < s.length; i++) {
                if (COMPONENT_ARROW_CHARS.index_of_char(s[i]) < 0) {
                    return false;
                }
            }
            return true;
        }

        // A token that can be part of an arrow. The first piece must hold a line
        // character, or be an end marker ("0)", "#", "*") whose adjacent run does.
        private bool is_component_arrow_piece(int idx, bool first) {
            if (idx >= tokens.size) {
                return false;
            }
            var t = tokens[idx];
            if (t.token_type == TokenType.NEWLINE || t.token_type == TokenType.EOF ||
                t.token_type == TokenType.STRING || !all_arrow_chars(t.lexeme)) {
                return false;
            }
            if (!first || has_arrow_line(t.lexeme)) {
                return true;
            }
            for (int j = idx + 1; j < tokens.size && j < idx + 6; j++) {
                var n = tokens[j];
                if (n.space_before || n.token_type == TokenType.NEWLINE || !all_arrow_chars(n.lexeme)) {
                    return false;
                }
                if (has_arrow_line(n.lexeme)) {
                    return true;
                }
            }
            return false;
        }

        // "le" / "ri0" / "up": the direction, plus arrow characters glued to it ("0")
        private static string? split_direction(string lexeme, out string rest) {
            string low = lexeme.down();
            int end = low.length;
            while (end > 0 && "0()".index_of_char(low[end - 1]) >= 0) {
                end--;
            }
            rest = lexeme.substring(end);
            switch (low.substring(0, end)) {
                case "u": case "up":
                    return "up";
                case "d": case "do": case "dow": case "down":
                    return "down";
                case "l": case "le": case "lef": case "left":
                    return "left";
                case "r": case "ri": case "rig": case "righ": case "right":
                    return "right";
                default:
                    return null;
            }
        }

        // Link options from the last read_component_arrow(): "-[thickness=8]->",
        // "-[#blue;#green,dashed]->"
        private int opt_thickness = 0;
        private Gee.ArrayList<string> opt_colors = new Gee.ArrayList<string>();

        // "[#red]" in "-[#red]->" / "-[hidden]-": the arrow line goes on right after the "]".
        // In "[A]--[B]" the "[" opens the target instead; taking it as options dropped the link.
        private bool options_block_at(int idx) {
            for (int j = idx + 1; j < tokens.size; j++) {
                var t = tokens[j];
                if (t.token_type == TokenType.NEWLINE || t.token_type == TokenType.EOF) {
                    return false;
                }
                if (t.token_type == TokenType.RBRACKET) {
                    if (j + 1 >= tokens.size) {
                        return false;
                    }
                    var n = tokens[j + 1];
                    if (n.space_before || n.lexeme.length == 0) {
                        return false;
                    }
                    if ("-.~=>".index_of_char(n.lexeme[0]) >= 0) {
                        return true;
                    }
                    // "-[#FF0000]up->": a direction word between the options and the line.
                    // Only a line character was accepted, so the link was dropped.
                    string rest;
                    if (split_direction(n.lexeme, out rest) != null && j + 2 < tokens.size) {
                        var m = tokens[j + 2];
                        return !m.space_before && m.lexeme.length > 0 && "-.~=>".index_of_char(m.lexeme[0]) >= 0;
                    }
                    return false;
                }
            }
            return false;
        }

        // Reads a whole arrow from its adjacent tokens: "-le(0)->" becomes "-(0)->"
        // with placement "left"; "[#red,dashed]" options come back separately.
        // Returns null (cursor unchanged) when there is no arrow here.
        private string? read_component_arrow(out string placement, out string? opt_style, out string? opt_color) {
            placement = "";
            opt_style = null;
            opt_color = null;
            opt_thickness = 0;
            opt_colors = new Gee.ArrayList<string>();
            if (!is_component_arrow_piece(current, true)) {
                return null;
            }
            int start = current;
            var sb = new StringBuilder();
            bool first = true;
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                var t = tokens[current];
                if (!first && t.space_before) {
                    break;
                }
                string tail = sb.str;
                if (tail.has_suffix(">") && t.lexeme != ">") {
                    break;
                }
                bool after_line = tail.length > 0 && "-.~=".index_of_char(tail[tail.length - 1]) >= 0;
                string rest = "";
                string? dir = null;
                if (after_line) {
                    dir = split_direction(t.lexeme, out rest);
                }
                if (is_component_arrow_piece(current, first)) {
                    sb.append(t.lexeme);
                    advance();
                } else if (dir != null) {
                    placement = dir;
                    sb.append(rest);
                    advance();
                } else if (after_line && t.token_type == TokenType.LBRACKET && options_block_at(current)) {
                    advance();
                    // The options as written, split at "," and ";": "thickness=8" lexes as
                    // three tokens and was ignored, and of "#blue;#green" only the last
                    // colour was kept
                    var raw = new StringBuilder();
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        if (tokens[current].space_before) {
                            raw.append(" ");
                        }
                        raw.append(current_lexeme());
                        advance();
                    }
                    foreach (string part in raw.str.replace(";", ",").split(",")) {
                        string opt = part.strip();
                        string low = opt.down().replace(" ", "");
                        if (low == "hidden") {
                            opt_style = "invis";
                        } else if (low == "dashed" || low == "dotted" || low == "bold") {
                            opt_style = low;
                        } else if (low == "plain") {
                            opt_style = "solid";
                        } else if (low.has_prefix("thickness=")) {
                            opt_thickness = int.parse(low.substring("thickness=".length));
                        } else if (opt.has_prefix("#") && opt.length > 1) {
                            if (opt_color == null) {
                                opt_color = opt;
                            }
                            opt_colors.add(normalize_color(opt.substring(1)));
                        }
                    }
                    if (check(TokenType.RBRACKET)) {
                        advance();
                    }
                } else {
                    break;
                }
                first = false;
            }
            string text = sb.str;
            bool lone = text == "-" || text == ".";
            if (!has_arrow_line(text) ||
                (lone && !is_at_end() && !check(TokenType.NEWLINE) && !tokens[current].space_before)) {
                current = start;
                placement = "";
                opt_style = null;
                opt_color = null;
                return null;
            }
            return text;
        }

        // Records what the classic fields can't express: line style, direction,
        // end markers beyond < > o *, and a ball/socket in the middle of the line.
        private void apply_arrow_decorations(ComponentRelationship rel, string arrow, string placement,
                                             string? opt_style, string? opt_color) {
            int first_line = -1;
            int last_line = -1;
            for (int i = 0; i < arrow.length; i++) {
                if ("-.~=".index_of_char(arrow[i]) >= 0) {
                    if (first_line < 0) {
                        first_line = i;
                    }
                    last_line = i;
                }
            }
            if (first_line < 0) {
                return;
            }
            string left_end = arrow.substring(0, first_line);
            string right_end = arrow.substring(last_line + 1);
            var mid = new StringBuilder();
            for (int i = first_line; i <= last_line; i++) {
                if ("-.~=".index_of_char(arrow[i]) < 0) {
                    mid.append_c(arrow[i]);
                }
            }
            string middle = mid.str;

            rel.placement = placement;
            if (arrow.contains("~")) {
                rel.line_style = "dotted";
            } else if (arrow.contains("=")) {
                rel.line_style = "bold";
            }
            if (opt_style != null) {
                rel.line_style = opt_style;
            }
            if (opt_color != null) {
                rel.color = opt_color;
            }
            if (opt_thickness > 0) {
                rel.thickness = opt_thickness;
            }
            if (opt_colors.size > 1) {
                rel.colors.add_all(opt_colors);
            }
            // "A -> B", "A - B": one line character is a horizontal link in PlantUML; it
            // was laid out top to bottom like "-->"
            int line_chars = 0;
            for (int i = 0; i < arrow.length; i++) {
                if ("-.~=".index_of_char(arrow[i]) >= 0) {
                    line_chars++;
                }
            }
            if (placement == "" && line_chars == 1) {
                placement = "right";
                rel.placement = placement;
            }
            int ball = middle.index_of("0");
            rel.mid_ball = ball >= 0;
            rel.mid_left_socket = ball > 0 && middle.substring(0, ball).contains("(");
            rel.mid_right_socket = ball >= 0 && middle.substring(ball + 1).contains(")");
            bool classic_left = left_end == "" || left_end == "<" || left_end == "o" || left_end == "*";
            bool classic_right = right_end == "" || right_end == ">" || right_end == "o" || right_end == "*";
            if (!classic_left) {
                rel.tail_marker = end_marker_shapes(left_end, true);
            }
            if (!classic_right) {
                rel.head_marker = end_marker_shapes(right_end, false);
            }
            rel.plus_tail = left_end.contains("+");
            rel.plus_head = right_end.contains("+");
            rel.decorated = rel.mid_ball || !classic_left || !classic_right || rel.line_style != null ||
                            placement == "up" || placement == "left" || placement == "right";
        }

        // Graphviz arrow shapes for an arrow end, nearest the node first. A tail end
        // is written node first ("0)-"), a head end node last ("-(0").
        private static string end_marker_shapes(string end, bool tail) {
            string s = tail ? end : end.reverse();
            var shapes = new StringBuilder();
            int count = 0;
            int i = 0;
            while (i < s.length && count < 4) {
                string two = i + 1 < s.length ? s.substring(i, 2) : "";
                string shape = "";
                int used = 1;
                if (two == "<|" || two == "|>" || two == ">|" || two == "|<") {
                    shape = "onormal";
                    used = 2;
                } else if (two == ">>" || two == "<<") {
                    // "-->>" is a filled triangle in PlantUML; it was an open vee
                    shape = "normal";
                    used = 2;
                } else {
                    switch (s[i]) {
                        case '<':
                        case '>':
                            shape = "vee";
                            break;
                        case '*':
                            shape = "diamond";
                            break;
                        case 'o':
                            shape = "odiamond";
                            break;
                        case '#':
                            shape = "obox";  // hollow square, as PlantUML draws it
                            break;
                        case '+':
                        case '0':
                            shape = "odot";
                            break;
                        case '(':
                            shape = tail ? "curve" : "icurve";
                            break;
                        case ')':
                            shape = tail ? "icurve" : "curve";
                            break;
                        case 'x':
                        case '|':
                            shape = "tee";
                            break;
                        case '^':
                            shape = "onormal";
                            break;
                        default:
                            break;
                    }
                }
                i += used;
                if (shape.length > 0 && !(shape == "vee" && shapes.str.has_suffix("vee"))) {
                    shapes.append(shape);
                    count++;
                }
            }
            return shapes.len > 0 ? shapes.str : "none";
        }

        private void parse_relationship_from(string from_id) {
            // Parse the arrow
            ComponentRelationType rel_type = ComponentRelationType.DEPENDENCY;
            bool is_dashed = false;
            bool left_arrow = false;
            bool right_arrow = true;

            // Read the whole arrow ("-le(0)->", "#~~(", "*-0)-+") from its adjacent
            // tokens; direction words and [options] come back separately.
            string? tail_label = pending_tail_label;
            pending_tail_label = null;
            string placement;
            string? opt_style;
            string? opt_color;
            string? read_arrow = read_component_arrow(out placement, out opt_style, out opt_color);
            if (read_arrow == null) {
                skip_to_newline();
                return;
            }
            string arrow = read_arrow;


            // Detect arrow characteristics from the resolved arrow token
            // Dotted arrows ("..>", ".up.>") are dashed; "-->" is solid, as in stock
            // PlantUML. It used to be drawn dashed like a dependency.
            if (arrow.contains(".")) {
                is_dashed = true;
                rel_type = ComponentRelationType.REALIZATION;
            }

            if (arrow.has_prefix("<")) {
                left_arrow = true;
            }
            if (arrow.has_suffix(">")) {
                right_arrow = true;
            } else {
                right_arrow = false;
            }
            if (arrow.contains("o")) {
                rel_type = ComponentRelationType.AGGREGATION;
            }
            if (arrow.contains("*")) {
                rel_type = ComponentRelationType.COMPOSITION;
            }
            // "A --* B" puts the diamond at B; it was always drawn at A
            bool marker_at_head = (arrow.has_suffix("*") || arrow.has_suffix("o")) &&
                                  !arrow.has_prefix("*") && !arrow.has_prefix("o");

            skip_whitespace();

            // Multiplicity at the target end: a quoted text followed by the target
            string? head_label = null;
            if (check(TokenType.STRING) && current + 1 < tokens.size) {
                var after = tokens[current + 1].token_type;
                if (after == TokenType.IDENTIFIER || after == TokenType.STRING ||
                    after == TokenType.LBRACKET || after == TokenType.LPAREN) {
                    head_label = get_string_value(current_lexeme());
                    advance();
                    skip_whitespace();
                }
            }

            // Get target
            string to_id = "";
            if (check(TokenType.LBRACKET)) {
                to_id = read_bracket_text();
                // Ensure target component exists
                declare_link_end(to_id, true);
            } else if (check(TokenType.LPAREN) && peek_next_is(TokenType.RPAREN)) {
                // () Interface target
                advance(); // (
                advance(); // )
                skip_whitespace();
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    if (check(TokenType.STRING)) {
                        to_id = get_string_value(current_lexeme());
                    } else {
                        to_id = current_lexeme();
                    }
                    advance();
                }
            } else if (check(TokenType.LPAREN) || check(TokenType.COLON)) {
                // "(Use case)" or ":Actor:" target
                ComponentType short_type = check(TokenType.LPAREN) ? ComponentType.USECASE : ComponentType.ACTOR;
                string? short_name = read_shorthand_name();
                if (short_name != null) {
                    to_id = shorthand_component(short_name, short_type).get_identifier();
                }
            } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word_at(current)) {
                // is_name_word_at: "a --> left", a keyword used as an alias
                if (check(TokenType.STRING)) {
                    to_id = get_string_value(current_lexeme());
                } else {
                    to_id = current_lexeme();
                }
                advance();
                declare_link_end(to_id, false);
            }

            if (to_id.length == 0) {
                skip_to_newline();
                return;
            }

            var rel = new ComponentRelationship(from_id, to_id, rel_type);
            rel.is_dashed = is_dashed;
            rel.left_arrow = left_arrow;
            rel.right_arrow = right_arrow;
            rel.marker_at_head = marker_at_head;
            rel.tail_label = tail_label;
            rel.head_label = head_label;
            apply_arrow_decorations(rel, arrow, placement, opt_style, opt_color);

            skip_whitespace();

            // Inline style after the target: "foo --> bar #line:red;line.bold;text:red : x".
            // It was read as nothing and the label after it dropped.
            if (check(TokenType.IDENTIFIER) && current_lexeme().has_prefix("#") && current_lexeme().length > 1) {
                apply_link_style(rel, read_style_spec());
                skip_whitespace();
            }

            // Optional stereotype on the destination side (C4-PlantUML emits
            // "a -->> b << : label" — the empty <<>> stereotype comes from
            // an unset $tags variable). Skip past it so we still find the
            // colon label.
            // The stereotypes are kept: "skinparam arrow<<async>> { ... }" styles the link
            while (check(TokenType.STEREOTYPE)) {
                if (current_lexeme().strip().length > 0) {
                    rel.stereotypes.add(current_lexeme().strip());
                }
                advance();
                skip_whitespace();
            }
            if (current_lexeme() == "<" && peek_ahead(1) == "<") {
                // Empty <<>> or fallback two-< form — consume both
                advance();
                advance();
                skip_whitespace();
            }

            // Check for label
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace();
                var label_sb = new StringBuilder();
                while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.ENDUML)) {
                    // Spaces only where the source has them, so markup like
                    // "**bold**" or "<size:12>" and symbols like ">=" stay intact.
                    if (label_sb.len > 0 && tokens[current].space_before) {
                        label_sb.append(" ");
                    }
                    label_sb.append(current_lexeme());
                    advance();
                }
                rel.label = label_sb.str.strip();
            }

            diagram.relationships.add(rel);
        }

        private void parse_stereotype_inline(Component comp) {
            advance(); // consume first <
            advance(); // consume second <

            var sb = new StringBuilder();
            while (!is_at_end()) {
                if (current_lexeme() == ">" && peek_ahead(1) == ">") {
                    break;
                }
                sb.append(current_lexeme());
                advance();
            }

            // Consume closing >>
            if (current_lexeme() == ">") {
                advance();
                if (current_lexeme() == ">") {
                    advance();
                }
            }

            add_stereotype(comp, sb.str.strip());
        }

        private static void add_stereotype(Component comp, string name) {
            if (comp.stereotype == null) {
                comp.stereotype = name;
            }
            comp.stereotypes.add(name);
        }

        // Any number of "<<name>>" (a STEREOTYPE token, or "<" "<" ... ">" ">" when the
        // lexer split it), with the whitespace after them
        private void read_stereotypes(Component comp) {
            while (!is_at_end()) {
                if (check(TokenType.STEREOTYPE)) {
                    add_stereotype(comp, current_lexeme());
                    advance();
                } else if (current_lexeme() == "<" && peek_ahead(1) == "<") {
                    parse_stereotype_inline(comp);
                } else {
                    break;
                }
                skip_whitespace();
            }
        }

        private void parse_note() {
            advance(); // consume 'note'
            skip_whitespace();

            string position = "right";
            string? attached_to = null;

            // Check position
            if (current_lexeme() == "left" || current_lexeme() == "right" ||
                current_lexeme() == "top" || current_lexeme() == "bottom") {
                position = current_lexeme();
                advance();
                skip_whitespace();
            }

            // Check for "of" keyword
            if (current_lexeme() == "of") {
                advance();
                skip_whitespace();
                if (check(TokenType.LBRACKET)) {
                    // "note right of [First Component]": the "[" stopped the target, and the
                    // single-line note became a multi-line one that swallowed the file
                    attached_to = read_bracket_text();
                    skip_whitespace();
                } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    if (check(TokenType.STRING)) {
                        attached_to = get_string_value(current_lexeme());
                    } else {
                        attached_to = current_lexeme();
                    }
                    advance();
                }
            }

            skip_whitespace();

            // Inline colour: "note right of x #LightYellow". The lexer hands "#name"
            // over as one token; it was read as note text and the colour ignored.
            string? note_color = null;
            if (check(TokenType.IDENTIFIER) && current_lexeme().has_prefix("#") && current_lexeme().length > 1) {
                note_color = current_lexeme();
                advance();
                skip_whitespace();
            }

            // Floating note: note "text" as N1. Without a colon it took the multi-line
            // path, which skipped the quoted text and dropped the note.
            if (attached_to == null && check(TokenType.STRING) && peek_ahead(1).down() == "as") {
                var floating = new ComponentNote(get_string_value(current_lexeme()));
                advance();  // "text"
                skip_whitespace();
                advance();  // as
                skip_whitespace();
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    floating.id = get_string_value(current_lexeme());  // links name the note by its alias
                }
                skip_to_newline();
                floating.position = position;
                floating.color = note_color;
                diagram.notes.add(floating);
                return;
            }

            // Check for colon for single-line note
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace();
                var text_sb = new StringBuilder();
                while (!is_at_end() && !check(TokenType.NEWLINE)) {
                    if (text_sb.len > 0 && tokens[current].space_before) {
                        text_sb.append(" ");
                    }
                    text_sb.append(current_lexeme());
                    advance();
                }
                var note = new ComponentNote(text_sb.str.strip());
                note.position = position;
                note.attached_to = attached_to;
                note.color = note_color;
                diagram.notes.add(note);
                return;
            }

            // Multi-line note; "note as N1" names it for links
            string? alias = null;
            if (attached_to == null && current_lexeme() == "as") {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    alias = get_string_value(current_lexeme());
                }
            }
            skip_to_newline();
            var text_sb = new StringBuilder();
            while (!is_at_end()) {
                if (current_lexeme() == "end" && peek_ahead(1) == "note") {
                    advance();
                    advance();
                    break;
                }
                // A NEWLINE token's lexeme is the two characters "\\n". Appending it
                // as well as a real newline doubled every line break in the note.
                if (check(TokenType.NEWLINE)) {
                    text_sb.append("\n");
                } else {
                    if (text_sb.len > 0 && tokens[current].space_before && !text_sb.str.has_suffix("\n")) {
                        text_sb.append(" ");
                    }
                    text_sb.append(current_lexeme());
                }
                advance();
            }

            var note = new ComponentNote(text_sb.str.strip());
            if (alias != null) note.id = alias;
            note.position = position;
            note.attached_to = attached_to;
            note.color = note_color;
            diagram.notes.add(note);
        }

        private void parse_title() {
            advance(); // consume 'title'
            skip_whitespace();

            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                if (sb.len > 0 && tokens[current].space_before) {
                    sb.append(" ");
                }
                sb.append(current_lexeme());
                advance();
            }
            diagram.title = sb.str.strip();
        }

        private void parse_skinparam_block() {
            advance(); // consume 'skinparam'
            skip_whitespace();

            // Get param name — can be an IDENTIFIER or a keyword token (e.g., rectangle, database, node)
            if (is_at_end() || check(TokenType.NEWLINE) || check(TokenType.ENDUML)) {
                skip_to_newline();
                return;
            }

            string param_name = current_lexeme();
            advance();
            // "skinparam rectangle<<boundary>> { ... }" and
            // "skinparam package<<boundary>>StereotypeFontColor transparent": properties for
            // one stereotype. The block's lines were parsed as elements and links.
            string stereo_suffix = "";
            if (check(TokenType.STEREOTYPE)) {
                stereo_suffix = "<<%s>>".printf(current_lexeme().down());
                advance();
                if (check(TokenType.IDENTIFIER) && !tokens[current].space_before) {
                    string prop = current_lexeme() + stereo_suffix;
                    advance();
                    skip_whitespace();
                    var val = new StringBuilder();
                    while (!is_at_end() && !check(TokenType.NEWLINE)) {
                        if (val.len > 0 && tokens[current].space_before) {
                            val.append(" ");
                        }
                        val.append(current_lexeme());
                        advance();
                    }
                    diagram.skin_params.set_element_property(param_name, prop, val.str.strip());
                    return;
                }
            }
            skip_whitespace();

            // Check for block syntax
            if (check(TokenType.LBRACE)) {
                advance();
                while (!is_at_end() && !check(TokenType.RBRACE)) {
                    skip_newlines();
                    if (check(TokenType.RBRACE)) break;

                    if (check(TokenType.IDENTIFIER)) {
                        string sub_param = current_lexeme();
                        advance();
                        skip_whitespace();
                        // BackgroundColor<<stereotype>> gets its own entry
                        if (check(TokenType.STEREOTYPE)) {
                            sub_param = "%s<<%s>>".printf(sub_param, current_lexeme().down());
                            advance();
                            skip_whitespace();
                        } else if (stereo_suffix.length > 0) {
                            sub_param += stereo_suffix;
                        }

                        string value = "";
                        while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.RBRACE)) {
                            value += current_lexeme();
                            advance();
                            if (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE)) {
                                value += " ";
                            }
                        }
                        value = value.strip();
                        diagram.skin_params.set_element_property(param_name, sub_param, value);
                    } else {
                        advance();
                    }
                }
                if (check(TokenType.RBRACE)) {
                    advance();
                }
            } else {
                // Single value - store as a general property
                string value = "";
                while (!is_at_end() && !check(TokenType.NEWLINE)) {
                    value += current_lexeme();
                    advance();
                    if (!check(TokenType.NEWLINE)) {
                        value += " ";
                    }
                }
                value = value.strip();
                // Set as global skinparam value
                diagram.skin_params.set_global(param_name, value);
            }
        }

        // Color parsing helper: handles IDENTIFIER tokens starting with '#'
        // (Lexer's scan_color() returns '#Color' as a single IDENTIFIER token), with an
        // inline style glued to it: "#aliceblue;line:red;line.dotted;text:blue". Only the
        // fill was read; the rest of the style was ignored.
        private void try_parse_color(Component comp) {
            if (check(TokenType.IDENTIFIER) && current_lexeme().has_prefix("#")) {
                string spec = read_style_spec();
                foreach (string raw_part in spec.split(";")) {
                    string part = raw_part.strip();
                    if (part.has_prefix("#")) {
                        part = part.substring(1);
                    }
                    string low = part.down();
                    if (part.length == 0) {
                        continue;
                    } else if (low.has_prefix("line:")) {
                        comp.line_color = normalize_color(part.substring(5));
                    } else if (low.has_prefix("line.")) {
                        comp.line_style = low.substring(5);
                    } else if (low.has_prefix("text:")) {
                        comp.text_color = normalize_color(part.substring(5));
                    } else if (low.has_prefix("back:")) {
                        comp.color = normalize_color(part.substring(5));
                    } else if (comp.color == null || raw_part == spec.split(";")[0]) {
                        comp.color = normalize_color(part);
                    }
                }
            } else if (check(TokenType.HASH)) {
                // Fallback for standalone HASH token (shouldn't happen but be safe)
                advance();
                var color_sb = new StringBuilder();
                while (check(TokenType.IDENTIFIER)) {
                    color_sb.append(current_lexeme());
                    advance();
                }
                if (color_sb.len > 0) {
                    string color_value = color_sb.str;
                    if (is_hex_color(color_value)) {
                        comp.color = "#" + color_value;
                    } else {
                        comp.color = color_value;
                    }
                }
            }
        }

        // "#red" -> "#red"'s Graphviz-ready form: hex keeps its "#", a name loses it
        private string normalize_color(string c) {
            string v = c.strip();
            if (v.has_prefix("#")) {
                v = v.substring(1);
            }
            return is_hex_color(v) ? "#" + v : v;
        }

        // The "#..." token at the cursor and every token glued to it (no space between):
        // "#pink;line:red;line.bold;text:red" lexes as a dozen tokens
        private string read_style_spec() {
            var sb = new StringBuilder(current_lexeme());
            advance();
            while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.LBRACE) &&
                   !check(TokenType.LBRACKET) && !check(TokenType.STEREOTYPE) && !tokens[current].space_before) {
                sb.append(current_lexeme());
                advance();
            }
            return sb.str;
        }

        // A link's inline style: "#line:red;line.bold;text:red", "#green;line.dashed"
        private void apply_link_style(ComponentRelationship rel, string spec) {
            foreach (string raw_part in spec.split(";")) {
                string part = raw_part.strip();
                if (part.has_prefix("#")) {
                    part = part.substring(1);
                }
                string low = part.down();
                if (part.length == 0) {
                    continue;
                } else if (low.has_prefix("line:")) {
                    rel.color = normalize_color(part.substring(5));
                } else if (low.has_prefix("line.")) {
                    string style = low.substring(5);
                    if (style == "bold") {
                        rel.thickness = int.max(rel.thickness, 2);
                    } else if (style == "dashed" || style == "dotted") {
                        rel.is_dashed = style == "dashed";
                        rel.line_style = style;
                        rel.decorated = true;
                    }
                } else if (low.has_prefix("text:")) {
                    rel.text_color = normalize_color(part.substring(5));
                } else if (!low.contains(":") && !low.contains(".")) {
                    rel.color = normalize_color(part);
                }
            }
        }

        private bool is_json_declaration() {
            return check(TokenType.IDENTIFIER) && current_lexeme() == "json" && is_declaration_word();
        }

        // "json Name { ... }" / "json "Label" as J { ... }": the body is the JSON text,
        // rebuilt from its tokens (quotes restored) through the matching "}"
        private void parse_json_block(Gee.ArrayList<Component> into) {
            advance();  // json
            skip_whitespace();
            string name = read_element_name();
            bool quoted = last_name_quoted;
            if (name.length == 0) {
                skip_to_newline();
                return;
            }
            var comp = new Component(name, ComponentType.JSON);
            comp.source_line = tokens[current - 1].line;
            skip_whitespace();
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                read_alias_into(comp, name, quoted);
                skip_whitespace();
            } else if (quoted) {
                comp.label = name;
            }
            try_parse_color(comp);
            skip_whitespace();
            if (!check(TokenType.LBRACE)) {
                skip_to_newline();
                return;
            }
            var text = new StringBuilder();
            int depth = 0;
            while (!is_at_end() && !check(TokenType.ENDUML)) {
                var t = tokens[current];
                if (t.token_type == TokenType.LBRACE) {
                    depth++;
                } else if (t.token_type == TokenType.RBRACE) {
                    depth--;
                }
                if (t.token_type == TokenType.NEWLINE) {
                    text.append("\n");
                } else {
                    if (t.space_before) {
                        text.append(" ");
                    }
                    text.append(t.token_type == TokenType.STRING ? "\"" + t.lexeme.replace("\"", "\\\"") + "\"" : t.lexeme);
                }
                advance();
                if (depth == 0) {
                    break;
                }
            }
            comp.json_text = text.str;
            into.add(comp);
            skip_to_newline();
        }

        // Helper methods
        private bool check(TokenType type) {
            if (is_at_end()) return false;
            return tokens[current].token_type == type;
        }

        private bool is_at_end() {
            return current >= tokens.size || tokens[current].token_type == TokenType.EOF;
        }

        private Token advance() {
            if (!is_at_end()) current++;
            return tokens[current - 1];
        }

        private string current_lexeme() {
            if (is_at_end()) return "";
            return tokens[current].lexeme;
        }

        private void skip_whitespace() {
            // Skip any tokens that are considered whitespace (not NEWLINE)
            while (!is_at_end() && tokens[current].lexeme == " ") {
                advance();
            }
        }

        private void skip_newlines() {
            while (!is_at_end() && check(TokenType.NEWLINE)) {
                advance();
            }
        }

        private void skip_to_newline() {
            while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.ENDUML)) {
                advance();
            }
            if (check(TokenType.NEWLINE)) {
                advance();
            }
        }

        private bool peek_next_is(TokenType type) {
            if (current + 1 >= tokens.size) return false;
            return tokens[current + 1].token_type == type;
        }

        private string peek_ahead(int n) {
            if (current + n >= tokens.size) return "";
            return tokens[current + n].lexeme;
        }

        private bool check_sequence(string s1, string s2, string s3, string s4) {
            if (current + 3 >= tokens.size) return false;
            return tokens[current].lexeme.down() == s1 &&
                   tokens[current + 1].lexeme.down() == s2 &&
                   tokens[current + 2].lexeme.down() == s3 &&
                   tokens[current + 3].lexeme.down() == s4;
        }

        private string get_string_value(string str) {
            if (str.length >= 2 &&
                ((str.has_prefix("\"") && str.has_suffix("\"")) ||
                 (str.has_prefix("'") && str.has_suffix("'")))) {
                return str.substring(1, str.length - 2);
            }
            return str;
        }

        // "#F00", "#FF0000" and "#00FF0080" (with alpha). Only 6 digits kept the "#", so the
        // other forms reached Graphviz as unknown colour names.
        private bool is_hex_color(string str) {
            if (str.length != 3 && str.length != 6 && str.length != 8) return false;
            foreach (char c in str.to_utf8()) {
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                    return false;
                }
            }
            return true;
        }
    }
}
