namespace GDiagram {
    public class UseCaseDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private UseCaseDiagram diagram;

        public UseCaseDiagramParser() {
            this.current = 0;
        }

        public UseCaseDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new UseCaseDiagram();

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

            // Parse statements until @enduml
            while (!check(TokenType.ENDUML) && !is_at_end()) {
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

            // Layout direction
            if (check(TokenType.LEFT)) {
                if (try_parse_direction()) {
                    return;
                }
            }
            if (check(TokenType.TOP)) {
                if (try_parse_top_to_bottom()) {
                    return;
                }
            }

            // Actor declaration
            if (check(TokenType.ACTOR)) {
                parse_actor_declaration();
                return;
            }

            // Use case declaration
            if (check(TokenType.USECASE)) {
                parse_usecase_declaration();
                return;
            }

            // Package or rectangle
            if (check(TokenType.PACKAGE) || check(TokenType.RECTANGLE)) {
                parse_package();
                return;
            }

            // Title
            if (match(TokenType.TITLE)) {
                diagram.title = consume_rest_of_line();
                return;
            }

            // Header
            if (match(TokenType.HEADER)) {
                diagram.header = consume_rest_of_line();
                return;
            }

            // Footer
            if (match(TokenType.FOOTER)) {
                diagram.footer = consume_rest_of_line();
                return;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Relationship or identifier reference
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || check(TokenType.COLON)) {
                parse_relationship_or_element();
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        private bool try_parse_direction() throws Error {
            // "left to right direction"
            if (!check(TokenType.LEFT)) return false;
            advance();  // consume "left"

            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "to") {
                current--;
                return false;
            }
            advance();  // consume "to"

            if (!check(TokenType.RIGHT)) {
                current -= 2;
                return false;
            }
            advance();  // consume "right"

            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "direction") {
                current -= 3;
                return false;
            }
            advance();  // consume "direction"

            diagram.left_to_right = true;
            return true;
        }

        private bool try_parse_top_to_bottom() throws Error {
            // "top to bottom direction"
            if (!check(TokenType.TOP)) return false;
            advance();  // consume "top"

            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "to") {
                current--;
                return false;
            }
            advance();  // consume "to"

            if (!check(TokenType.BOTTOM)) {
                current -= 2;
                return false;
            }
            advance();  // consume "bottom"

            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "direction") {
                current -= 3;
                return false;
            }
            advance();  // consume "direction"

            diagram.left_to_right = false;
            return true;
        }

        private void parse_actor_declaration() throws Error {
            int line = advance().line;  // consume "actor"

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected actor name");
            }

            var actor = new UseCaseActor(name, line);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    actor.alias = advance().lexeme;
                }
            }

            // Check for stereotype <<...>>
            string? stereotype = null;
            parse_stereotype(ref stereotype);
            actor.stereotype = stereotype;

            // Check for color
            actor.color = parse_color();

            diagram.actors.add(actor);
            expect_end_of_statement();
        }

        private void parse_usecase_declaration() throws Error {
            int line = advance().line;  // consume "usecase"

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                // Handle parenthesized use case: usecase (Name)
                if (match(TokenType.LPAREN)) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        sb.append(advance().lexeme);
                        if (!check(TokenType.RPAREN)) sb.append(" ");
                    }
                    match(TokenType.RPAREN);
                    name = sb.str.strip();
                } else {
                    throw new IOError.FAILED("Expected usecase name");
                }
            }

            var uc = new UseCase(name, line);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    uc.alias = advance().lexeme;
                }
            }

            // Check for stereotype <<...>>
            string? stereotype = null;
            parse_stereotype(ref stereotype);
            uc.stereotype = stereotype;

            // Check for color
            uc.color = parse_color();

            diagram.use_cases.add(uc);
            expect_end_of_statement();
        }

        private void parse_stereotype(ref string? stereotype) {
            // Stereotypes like <<Human>> are tokenized as < < identifier > >
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "<") {
                advance();  // consume first <
                if (check(TokenType.IDENTIFIER) && peek().lexeme == "<") {
                    advance();  // consume second <
                    if (check(TokenType.IDENTIFIER)) {
                        stereotype = advance().lexeme;
                        // consume closing >>
                        while (check(TokenType.IDENTIFIER) && peek().lexeme == ">") {
                            advance();
                        }
                    }
                }
            }
        }

        private string? parse_color() {
            if (!match(TokenType.HASH)) {
                return null;
            }

            var sb = new StringBuilder();
            sb.append("#");

            // Collect color tokens until we hit a structural element
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check(TokenType.RBRACE) &&
                   !check(TokenType.AS) && !is_at_end()) {
                Token t = peek();
                if (t.token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }

            return sb.str;
        }

        private void parse_package() throws Error {
            UseCaseContainerType container_type = UseCaseContainerType.PACKAGE;
            if (check(TokenType.RECTANGLE)) {
                container_type = UseCaseContainerType.RECTANGLE;
            }
            advance();  // consume "package" or "rectangle"

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected package name");
            }

            var package = new UseCasePackage(name, container_type);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    package.alias = advance().lexeme;
                }
            }

            // Package body
            if (match(TokenType.LBRACE)) {
                parse_package_body(package);
            }

            diagram.packages.add(package);
            expect_end_of_statement();
        }

        private void parse_note() throws Error {
            advance();  // consume "note"

            string position = "right";
            if (match(TokenType.LEFT)) {
                position = "left";
            } else if (match(TokenType.RIGHT)) {
                position = "right";
            } else if (match(TokenType.TOP)) {
                position = "top";
            } else if (match(TokenType.BOTTOM)) {
                position = "bottom";
            }

            string? attached_to = null;

            // "of Element" or "as alias"
            if (match(TokenType.OF)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            // Note text - can be single line or multi-line (end note)
            var sb = new StringBuilder();

            if (match(TokenType.COLON)) {
                // Single line note
                sb.append(consume_rest_of_line());
            } else {
                skip_newlines();
                // Multi-line note until "end note"
                while (!is_at_end()) {
                    if (check(TokenType.END)) {
                        advance();
                        // Check for "note" after "end"
                        if (check(TokenType.NOTE)) {
                            advance();
                            break;
                        }
                    }
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) sb.append("\n");
                        advance();
                    } else {
                        sb.append(advance().lexeme);
                        sb.append(" ");
                    }
                }
            }

            var note = new UseCaseNote(sb.str.strip());
            note.attached_to = attached_to;
            note.position = position;
            diagram.notes.add(note);
        }

        private void parse_package_body(UseCasePackage package) throws Error {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                // Actor in package
                if (check(TokenType.ACTOR)) {
                    int actor_line = advance().line;
                    string name = "";
                    if (check(TokenType.STRING)) {
                        name = advance().lexeme;
                    } else if (check(TokenType.IDENTIFIER)) {
                        name = advance().lexeme;
                    }
                    if (name.length > 0) {
                        var actor = new UseCaseActor(name, actor_line);
                        if (match(TokenType.AS)) {
                            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                                actor.alias = advance().lexeme;
                            }
                        }
                        package.actors.add(actor);
                    }
                }
                // Use case in package
                else if (check(TokenType.USECASE)) {
                    int uc_line = advance().line;
                    string name = "";
                    if (check(TokenType.STRING)) {
                        name = advance().lexeme;
                    } else if (check(TokenType.IDENTIFIER)) {
                        name = advance().lexeme;
                    } else if (match(TokenType.LPAREN)) {
                        var sb = new StringBuilder();
                        while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                            sb.append(advance().lexeme);
                            if (!check(TokenType.RPAREN)) sb.append(" ");
                        }
                        match(TokenType.RPAREN);
                        name = sb.str.strip();
                    }
                    if (name.length > 0) {
                        var uc = new UseCase(name, uc_line);
                        uc.container = package.name;
                        if (match(TokenType.AS)) {
                            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                                uc.alias = advance().lexeme;
                            }
                        }
                        package.use_cases.add(uc);
                    }
                }
                // Relationship inside package
                else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    parse_relationship_or_element();
                }
                else {
                    advance();
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private void parse_relationship_or_element() throws Error {
            // Get first name
            string from_name;
            if (check(TokenType.STRING)) {
                from_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                from_name = advance().lexeme;
            } else if (check(TokenType.COLON)) {
                // Shorthand use case like :(Use Case Name)
                advance();  // consume :
                if (match(TokenType.LPAREN)) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        sb.append(advance().lexeme);
                        if (!check(TokenType.RPAREN)) sb.append(" ");
                    }
                    match(TokenType.RPAREN);
                    from_name = sb.str.strip();
                    diagram.get_or_create_usecase(from_name);
                } else {
                    // Standalone : is a shorthand for actor
                    from_name = "User";
                    diagram.get_or_create_actor(from_name);
                }
                expect_end_of_statement();
                return;
            } else {
                return;
            }

            // Check for relationship arrow
            UseCaseRelationType? rel_type = null;
            bool reverse = false;
            bool is_dashed = false;

            if (match(TokenType.ARROW_RIGHT)) {
                rel_type = UseCaseRelationType.ASSOCIATION;
            } else if (match(TokenType.ARROW_RIGHT_DOTTED)) {
                rel_type = UseCaseRelationType.ASSOCIATION;
                is_dashed = true;
            } else if (match(TokenType.ARROW_LEFT)) {
                rel_type = UseCaseRelationType.ASSOCIATION;
                reverse = true;
            } else if (match(TokenType.ARROW_LEFT_DOTTED)) {
                rel_type = UseCaseRelationType.ASSOCIATION;
                reverse = true;
                is_dashed = true;
            } else if (match(TokenType.MINUS_MINUS)) {
                rel_type = UseCaseRelationType.ASSOCIATION;
            } else if (match(TokenType.INHERITANCE)) {
                rel_type = UseCaseRelationType.GENERALIZATION;
                reverse = previous().lexeme.has_prefix("<");
            } else if (match(TokenType.DEPENDENCY)) {
                rel_type = UseCaseRelationType.ASSOCIATION;
                is_dashed = true;
            }

            if (rel_type != null) {
                // Get second name
                string to_name;
                if (check(TokenType.STRING)) {
                    to_name = advance().lexeme;
                } else if (check(TokenType.IDENTIFIER)) {
                    to_name = advance().lexeme;
                } else if (check(TokenType.LPAREN)) {
                    advance();  // consume (
                    var sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        sb.append(advance().lexeme);
                        if (!check(TokenType.RPAREN)) sb.append(" ");
                    }
                    match(TokenType.RPAREN);
                    to_name = sb.str.strip();
                } else {
                    expect_end_of_statement();
                    return;
                }

                // Check for <<include>> or <<extend>> markers
                // These are often part of the label after ":"
                string? label = null;
                if (match(TokenType.COLON)) {
                    label = consume_rest_of_line();
                    if (label != null) {
                        string lower_label = label.down();
                        if (lower_label.contains("include")) {
                            rel_type = UseCaseRelationType.INCLUDE;
                        } else if (lower_label.contains("extend")) {
                            rel_type = UseCaseRelationType.EXTEND;
                        }
                    }
                }

                UseCaseRelationship relationship;
                if (reverse) {
                    relationship = new UseCaseRelationship(to_name, from_name, rel_type);
                } else {
                    relationship = new UseCaseRelationship(from_name, to_name, rel_type);
                }
                relationship.label = label;
                relationship.is_dashed = is_dashed;

                diagram.relationships.add(relationship);
            } else {
                // Just a reference - ensure the element exists
                // Try to determine if it's an actor or use case from context
                // For now, treat unknown identifiers as potential participants
            }

            expect_end_of_statement();
        }

        private void parse_skinparam() throws Error {
            string first_name = "";
            if (check(TokenType.IDENTIFIER) || is_skinparam_element_keyword()) {
                first_name = advance().lexeme;
            } else {
                skip_to_end_of_line();
                return;
            }

            if (match(TokenType.LBRACE)) {
                parse_skinparam_block(first_name);
            } else {
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }
        }

        private void parse_skinparam_block(string element) throws Error {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                if (!check(TokenType.IDENTIFIER)) {
                    advance();
                    continue;
                }

                string property = advance().lexeme;
                string value = collect_skinparam_value();

                if (value.length > 0) {
                    diagram.skin_params.set_element_property(element, property, value);
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private string collect_skinparam_value() {
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                if (t.lexeme == "#") {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    if (sb.len > 0) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                }
            }

            return sb.str.strip();
        }

        private void skip_to_end_of_line() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private bool is_skinparam_element_keyword() {
            switch (peek().token_type) {
                case TokenType.ACTOR:
                case TokenType.USECASE:
                case TokenType.PACKAGE:
                case TokenType.RECTANGLE:
                case TokenType.NOTE:
                    return true;
                default:
                    return false;
            }
        }

        private string consume_rest_of_line() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        private void expect_end_of_statement() {
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == TokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case TokenType.ACTOR:
                    case TokenType.USECASE:
                    case TokenType.PACKAGE:
                    case TokenType.RECTANGLE:
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
                // keep skipping
            }
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
