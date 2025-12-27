namespace GPlantUML {
    public class ComponentDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ComponentDiagram diagram;

        public ComponentDiagramParser() {
            tokens = new Gee.ArrayList<Token>();
            current = 0;
        }

        public ComponentDiagram parse(Gee.ArrayList<Token> token_list) {
            this.tokens = token_list;
            this.current = 0;
            this.diagram = new ComponentDiagram();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(
                    "Unexpected error: " + e.message,
                    current < tokens.size ? tokens[current].line : 0,
                    current < tokens.size ? tokens[current].column : 0
                ));
            }

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

                parse_statement();
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

            // Check for container types (package, node, folder, frame, cloud, database)
            if (check(TokenType.PACKAGE) || check(TokenType.NODE_KW) ||
                check(TokenType.FOLDER) || check(TokenType.FRAME) ||
                check(TokenType.CLOUD) || check(TokenType.STORAGE)) {
                parse_container();
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

            // Check for database keyword
            if (check(TokenType.IDENTIFIER) && current_lexeme() == "database") {
                parse_database();
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

            // Check for hide
            if (check(TokenType.HIDE)) {
                skip_to_newline();
                return;
            }

            // Try to parse as relationship or identifier
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_identifier_or_relationship();
                return;
            }

            // Skip unknown tokens
            advance();
        }

        private void parse_container() throws Error {
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
            } else if (check(TokenType.STORAGE)) {
                container_type = ComponentType.STORAGE;
            } else {
                container_type = ComponentType.PACKAGE;
            }
            advance();

            skip_whitespace();

            // Get name (can be string or identifier)
            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            }

            var container = new Component(name, container_type);
            container.is_container = true;

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    container.alias = current_lexeme();
                    advance();
                }
            }

            skip_whitespace();

            // Check for stereotype
            // Check for stereotype (using << >> syntax)
            if (current_lexeme() == "<" && peek_ahead(1) == "<") {
                parse_stereotype_inline(container);
            }

            skip_whitespace();

            // Check for color
            if (check(TokenType.HASH)) {
                advance();
                var color_sb = new StringBuilder();
                while (check(TokenType.IDENTIFIER)) {
                    color_sb.append(current_lexeme());
                    advance();
                }
                if (color_sb.len > 0) {
                    string color_value = color_sb.str;
                    // Only add # prefix for hex colors (6 chars), not for named colors
                    if (is_hex_color(color_value)) {
                        container.color = "#" + color_value;
                    } else {
                        container.color = color_value;
                    }
                }
            }

            skip_whitespace();

            // Check for { to start container body
            if (check(TokenType.LBRACE)) {
                advance();
                parse_container_body(container);
            }

            diagram.components.add(container);
        }

        private void parse_container_body(Component container) throws Error {
            while (!is_at_end() && !check(TokenType.RBRACE)) {
                skip_newlines();
                if (is_at_end() || check(TokenType.RBRACE)) break;

                // Parse nested components
                if (check(TokenType.COMPONENT)) {
                    var comp = parse_component_inner();
                    if (comp != null) {
                        container.children.add(comp);
                    }
                } else if (check(TokenType.LBRACKET)) {
                    var comp = parse_bracket_component_inner();
                    if (comp != null) {
                        container.children.add(comp);
                    }
                } else if (check(TokenType.PACKAGE) || check(TokenType.NODE_KW) ||
                           check(TokenType.FOLDER) || check(TokenType.FRAME) ||
                           check(TokenType.CLOUD) || check(TokenType.STORAGE)) {
                    // Nested containers
                    parse_nested_container(container);
                } else if (check(TokenType.RECTANGLE) || check(TokenType.ARTIFACT) ||
                           check(TokenType.CARD) || check(TokenType.AGENT) ||
                           check(TokenType.QUEUE) || check(TokenType.BOUNDARY) ||
                           check(TokenType.CONTROL) || check(TokenType.ENTITY)) {
                    // Nested element (rectangle, artifact, etc.)
                    var elem = parse_element_inner();
                    if (elem != null) {
                        container.children.add(elem);
                    }
                } else if (check(TokenType.INTERFACE) ||
                           (check(TokenType.LPAREN) && peek_next_is(TokenType.RPAREN))) {
                    // Interface in container - add to diagram directly
                    if (check(TokenType.INTERFACE)) {
                        parse_interface_declaration();
                    } else {
                        parse_circle_interface();
                    }
                } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    // Could be nested element or relationship
                    parse_nested_element_or_relationship(container);
                } else {
                    advance();
                }
            }

            // Consume closing brace
            if (check(TokenType.RBRACE)) {
                advance();
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
            } else {
                container_type = ComponentType.STORAGE;
            }
            advance();

            skip_whitespace();

            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            }

            var nested = new Component(name, container_type);
            nested.is_container = true;

            skip_whitespace();

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    nested.alias = current_lexeme();
                    advance();
                }
            }

            skip_whitespace();

            if (check(TokenType.LBRACE)) {
                advance();
                parse_container_body(nested);
            }

            parent.children.add(nested);
        }

        private void parse_nested_element_or_relationship(Component container) throws Error {
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
            } else {
                elem_type = ComponentType.RECTANGLE;
            }
            advance();

            skip_whitespace();

            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            } else {
                return null;
            }

            var comp = new Component(name, elem_type);

            skip_whitespace();

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    comp.alias = current_lexeme();
                    advance();
                }
            }

            skip_whitespace();

            // Check for color
            if (check(TokenType.HASH)) {
                advance();
                var color_sb = new StringBuilder();
                while (check(TokenType.IDENTIFIER)) {
                    color_sb.append(current_lexeme());
                    advance();
                }
                if (color_sb.len > 0) {
                    string color_value = color_sb.str;
                    // Only add # prefix for hex colors (6 chars), not for named colors
                    if (is_hex_color(color_value)) {
                        comp.color = "#" + color_value;
                    } else {
                        comp.color = color_value;
                    }
                }
            }

            skip_to_newline();
            return comp;
        }

        private Component? parse_component_inner() throws Error {
            skip_whitespace();

            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            } else {
                return null;
            }

            var comp = new Component(name, ComponentType.COMPONENT);

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    comp.alias = current_lexeme();
                    advance();
                }
            }

            skip_whitespace();

            // Check for stereotype (using << >> syntax)
            if (current_lexeme() == "<" && peek_ahead(1) == "<") {
                parse_stereotype_inline(comp);
            }

            skip_whitespace();

            // Check for color
            if (check(TokenType.HASH)) {
                advance();
                var color_sb = new StringBuilder();
                while (check(TokenType.IDENTIFIER)) {
                    color_sb.append(current_lexeme());
                    advance();
                }
                if (color_sb.len > 0) {
                    string color_value = color_sb.str;
                    // Only add # prefix for hex colors (6 chars), not for named colors
                    if (is_hex_color(color_value)) {
                        comp.color = "#" + color_value;
                    } else {
                        comp.color = color_value;
                    }
                }
            }

            skip_to_newline();
            return comp;
        }

        private void parse_interface_declaration() throws Error {
            advance(); // consume 'interface'
            skip_whitespace();

            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            } else {
                return;
            }

            var iface = new ComponentInterface(name);

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    iface.alias = current_lexeme();
                    advance();
                }
            }

            diagram.interfaces.add(iface);
            skip_to_newline();
        }

        private void parse_bracket_component() throws Error {
            var comp = parse_bracket_component_inner();
            if (comp != null) {
                diagram.components.add(comp);
            }
        }

        private Component? parse_bracket_component_inner() throws Error {
            advance(); // consume '['

            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.RBRACKET)) {
                sb.append(current_lexeme());
                advance();
                // Add space if next token is not ]
                if (!check(TokenType.RBRACKET)) {
                    sb.append(" ");
                }
            }

            if (check(TokenType.RBRACKET)) {
                advance();
            }

            string name = sb.str.strip();
            if (name.length == 0) {
                return null;
            }

            var comp = new Component(name, ComponentType.COMPONENT);

            skip_whitespace();

            // Check for alias
            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    comp.alias = current_lexeme();
                    advance();
                }
            }

            skip_whitespace();

            // Check for relationship arrow
            if (is_relationship_arrow()) {
                // Register component first
                diagram.components.add(comp);
                parse_relationship_from(comp.get_identifier());
                return null; // Already added
            }

            skip_to_newline();
            return comp;
        }

        private void parse_circle_interface() throws Error {
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
                if (check(TokenType.IDENTIFIER)) {
                    iface.alias = current_lexeme();
                    advance();
                }
            }

            diagram.interfaces.add(iface);
            skip_to_newline();
        }

        private void parse_database() throws Error {
            advance(); // consume 'database'
            skip_whitespace();

            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            }

            var comp = new Component(name, ComponentType.DATABASE);

            skip_whitespace();

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    comp.alias = current_lexeme();
                    advance();
                }
            }

            diagram.components.add(comp);
            skip_to_newline();
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
            } else {
                elem_type = ComponentType.RECTANGLE;
            }
            advance();

            skip_whitespace();

            string name = "";
            if (check(TokenType.STRING)) {
                name = get_string_value(current_lexeme());
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                name = current_lexeme();
                advance();
            }

            var comp = new Component(name, elem_type);

            skip_whitespace();

            if (check(TokenType.AS)) {
                advance();
                skip_whitespace();
                if (check(TokenType.IDENTIFIER)) {
                    comp.alias = current_lexeme();
                    advance();
                }
            }

            skip_whitespace();

            // Check for color: rectangle "Name" #LightGreen
            if (check(TokenType.HASH)) {
                advance();
                var color_sb = new StringBuilder();
                while (check(TokenType.IDENTIFIER)) {
                    color_sb.append(current_lexeme());
                    advance();
                }
                if (color_sb.len > 0) {
                    string color_value = color_sb.str;
                    // Only add # prefix for hex colors (6 chars), not for named colors
                    if (is_hex_color(color_value)) {
                        comp.color = "#" + color_value;
                    } else {
                        comp.color = color_value;
                    }
                }
            }

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

        private void parse_port() throws Error {
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

            diagram.ports.add(port);
            skip_to_newline();
        }

        private void parse_identifier_or_relationship() throws Error {
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

        private bool is_relationship_arrow() {
            // Check for various arrow types
            if (check(TokenType.ARROW_RIGHT) || check(TokenType.ARROW_RIGHT_DOTTED) ||
                check(TokenType.ARROW_LEFT) || check(TokenType.ARROW_LEFT_DOTTED) ||
                check(TokenType.DEPENDENCY) || check(TokenType.MINUS)) {
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

        private void parse_relationship_from(string from_id) throws Error {
            // Parse the arrow
            ComponentRelationType rel_type = ComponentRelationType.DEPENDENCY;
            bool is_dashed = false;
            bool left_arrow = false;
            bool right_arrow = true;

            string arrow = current_lexeme();

            // Detect arrow characteristics
            if (arrow.contains("..") || check(TokenType.ARROW_RIGHT_DOTTED) || check(TokenType.ARROW_LEFT_DOTTED)) {
                is_dashed = true;
                rel_type = ComponentRelationType.REALIZATION;
            }

            if (arrow.has_prefix("<")) {
                left_arrow = true;
            }
            if (!arrow.has_suffix(">")) {
                right_arrow = false;
            }
            if (arrow.contains("o")) {
                rel_type = ComponentRelationType.AGGREGATION;
            }
            if (arrow.contains("*")) {
                rel_type = ComponentRelationType.COMPOSITION;
            }

            advance(); // consume arrow

            skip_whitespace();

            // Get target
            string to_id = "";
            if (check(TokenType.LBRACKET)) {
                advance();
                var sb = new StringBuilder();
                while (!is_at_end() && !check(TokenType.RBRACKET)) {
                    sb.append(current_lexeme());
                    advance();
                    if (!check(TokenType.RBRACKET)) {
                        sb.append(" ");
                    }
                }
                if (check(TokenType.RBRACKET)) {
                    advance();
                }
                to_id = sb.str.strip();
                // Ensure target component exists
                diagram.get_or_create_component(to_id);
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
            } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                if (check(TokenType.STRING)) {
                    to_id = get_string_value(current_lexeme());
                } else {
                    to_id = current_lexeme();
                }
                advance();
            }

            if (to_id.length == 0) {
                skip_to_newline();
                return;
            }

            var rel = new ComponentRelationship(from_id, to_id, rel_type);
            rel.is_dashed = is_dashed;
            rel.left_arrow = left_arrow;
            rel.right_arrow = right_arrow;

            skip_whitespace();

            // Check for label
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace();
                var label_sb = new StringBuilder();
                while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.ENDUML)) {
                    label_sb.append(current_lexeme());
                    advance();
                    if (!check(TokenType.NEWLINE) && !check(TokenType.ENDUML)) {
                        label_sb.append(" ");
                    }
                }
                rel.label = label_sb.str.strip();
            }

            diagram.relationships.add(rel);
        }

        private void parse_stereotype_inline(Component comp) throws Error {
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

            comp.stereotype = sb.str.strip();
        }

        private void parse_note() throws Error {
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
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    if (check(TokenType.STRING)) {
                        attached_to = get_string_value(current_lexeme());
                    } else {
                        attached_to = current_lexeme();
                    }
                    advance();
                }
            }

            skip_whitespace();

            // Check for colon for single-line note
            if (check(TokenType.COLON)) {
                advance();
                skip_whitespace();
                var text_sb = new StringBuilder();
                while (!is_at_end() && !check(TokenType.NEWLINE)) {
                    text_sb.append(current_lexeme());
                    advance();
                    if (!check(TokenType.NEWLINE)) {
                        text_sb.append(" ");
                    }
                }
                var note = new ComponentNote(text_sb.str.strip());
                note.position = position;
                note.attached_to = attached_to;
                diagram.notes.add(note);
                return;
            }

            // Multi-line note
            skip_to_newline();
            var text_sb = new StringBuilder();
            while (!is_at_end()) {
                if (current_lexeme() == "end" && peek_ahead(1) == "note") {
                    advance();
                    advance();
                    break;
                }
                text_sb.append(current_lexeme());
                if (check(TokenType.NEWLINE)) {
                    text_sb.append("\n");
                } else {
                    text_sb.append(" ");
                }
                advance();
            }

            var note = new ComponentNote(text_sb.str.strip());
            note.position = position;
            note.attached_to = attached_to;
            diagram.notes.add(note);
        }

        private void parse_title() throws Error {
            advance(); // consume 'title'
            skip_whitespace();

            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                sb.append(current_lexeme());
                advance();
                if (!check(TokenType.NEWLINE)) {
                    sb.append(" ");
                }
            }
            diagram.title = sb.str.strip();
        }

        private void parse_skinparam_block() throws Error {
            advance(); // consume 'skinparam'
            skip_whitespace();

            // Get param name
            if (!check(TokenType.IDENTIFIER)) {
                skip_to_newline();
                return;
            }

            string param_name = current_lexeme();
            advance();
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

        private bool is_hex_color(string str) {
            if (str.length != 6) return false;
            foreach (char c in str.to_utf8()) {
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                    return false;
                }
            }
            return true;
        }
    }
}
