namespace GDiagram {
    public class MermaidClassParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidClassDiagram diagram;

        public MermaidClassParser() {
            this.current = 0;
        }

        public MermaidClassDiagram parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidClassDiagram();

            try {
                parse_class_diagram();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            return diagram;
        }

        private void parse_class_diagram() throws GLib.Error {
            skip_newlines();

            // Expect classDiagram keyword
            if (!match(MermaidTokenType.CLASS_DIAGRAM)) {
                error_at_current("Expected 'classDiagram'");
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

            // Title
            if (check(MermaidTokenType.TITLE)) {
                parse_title();
                return;
            }

            // Class declaration
            if (check(MermaidTokenType.CLASS_KW)) {
                parse_class();
                return;
            }

            // Relationship or class reference
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_relationship_or_class_reference();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_title() throws GLib.Error {
            advance(); // consume 'title'
            var title_parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (title_parts.len > 0) {
                    title_parts.append(" ");
                }
                title_parts.append(advance().lexeme);
            }
            diagram.title = title_parts.str.strip();
        }

        private void parse_class() throws GLib.Error {
            advance(); // consume 'class'

            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected class name");
            }

            string class_name = advance().lexeme;
            int line = previous().line;

            var cls = diagram.get_or_create_class(class_name);
            cls.source_line = line;

            skip_newlines();

            // Check for class body
            if (match(MermaidTokenType.LBRACE)) {
                parse_class_body(cls);
                if (!match(MermaidTokenType.RBRACE)) {
                    error_at_current("Expected '}'");
                }
            }
        }

        private void parse_class_body(MermaidClass cls) throws GLib.Error {
            skip_newlines();

            while (!check(MermaidTokenType.RBRACE) && !is_at_end()) {
                // Parse member
                parse_class_member(cls);
                skip_newlines();
            }
        }

        private void parse_class_member(MermaidClass cls) throws GLib.Error {
            // Parse visibility modifier (+, -, #, ~)
            MermaidVisibility visibility = MermaidVisibility.PUBLIC;

            if (check(MermaidTokenType.PLUS)) {
                advance();
                visibility = MermaidVisibility.PUBLIC;
            } else if (check(MermaidTokenType.MINUS)) {
                // Need to disambiguate from arrows
                int saved = current;
                advance();
                if (check(MermaidTokenType.IDENTIFIER)) {
                    visibility = MermaidVisibility.PRIVATE;
                } else {
                    // Backtrack - it's probably an arrow
                    current = saved;
                    return;
                }
            } else if (check(MermaidTokenType.HASH)) {
                advance();
                visibility = MermaidVisibility.PROTECTED;
            } else if (check(MermaidTokenType.TILDE)) {
                advance();
                visibility = MermaidVisibility.PACKAGE;
            }

            // Parse member type (optional in Mermaid)
            string? type_name = null;
            if (check(MermaidTokenType.IDENTIFIER)) {
                // Could be type or name, need to check if there's another identifier
                int saved = current;
                string first = advance().lexeme;

                if (check(MermaidTokenType.IDENTIFIER)) {
                    // First was type, second is name
                    type_name = first;
                } else {
                    // Only one identifier - backtrack, it's the name
                    current = saved;
                }
            }

            // Parse member name
            if (!check(MermaidTokenType.IDENTIFIER)) {
                // Skip this member
                return;
            }

            string member_name = advance().lexeme;
            bool is_method = false;

            // Check for method parentheses
            if (match(MermaidTokenType.LPAREN)) {
                is_method = true;
                // Skip parameters for now
                while (!check(MermaidTokenType.RPAREN) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                match(MermaidTokenType.RPAREN);
            }

            // Check for type annotation with colon (Mermaid style: name: Type)
            if (match(MermaidTokenType.COLON)) {
                var type_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end() && !check(MermaidTokenType.RBRACE)) {
                    if (check(MermaidTokenType.LPAREN)) {
                        // It's a method return type
                        is_method = true;
                        break;
                    }
                    if (type_parts.len > 0) {
                        type_parts.append(" ");
                    }
                    type_parts.append(advance().lexeme);
                }
                if (type_parts.len > 0) {
                    type_name = type_parts.str.strip();
                }
            }

            var member = new MermaidClassMember(member_name, is_method);
            member.visibility = visibility;
            member.type_name = type_name;

            cls.add_member(member);

            // Consume rest of line
            while (!check(MermaidTokenType.NEWLINE) && !check(MermaidTokenType.RBRACE) && !is_at_end()) {
                advance();
            }
        }

        private void parse_relationship_or_class_reference() throws GLib.Error {
            string from_name = advance().lexeme;
            skip_whitespace_same_line();

            // Check for relationship arrow
            if (is_relationship_arrow()) {
                parse_relationship_from(from_name);
            } else {
                // Just a class reference
                diagram.get_or_create_class(from_name);
            }
        }

        private void parse_relationship_from(string from_name) throws GLib.Error {
            var from_class = diagram.get_or_create_class(from_name);

            // Parse relationship arrow
            MermaidRelationType rel_type = parse_relationship_arrow();

            skip_whitespace_same_line();

            // Get target class
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected target class name");
            }

            string to_name = advance().lexeme;
            var to_class = diagram.get_or_create_class(to_name);

            var relation = new MermaidRelation(from_class, to_class, rel_type);

            // Check for label after colon
            if (match(MermaidTokenType.COLON)) {
                var label_parts = new StringBuilder();
                while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                    if (label_parts.len > 0) {
                        label_parts.append(" ");
                    }
                    label_parts.append(advance().lexeme);
                }
                relation.label = label_parts.str.strip();
            }

            diagram.relations.add(relation);
        }

        private bool is_relationship_arrow() {
            // Check for various relationship arrows
            // Inheritance: <|--
            // Composition: *--
            // Aggregation: o--
            // Association: -->
            // Dependency: ..>
            // Realization: ..|>

            // Look ahead for arrow patterns
            if (check(MermaidTokenType.ARROW_SOLID) ||
                check(MermaidTokenType.ARROW_DOTTED) ||
                check(MermaidTokenType.AGGREGATION) ||
                check(MermaidTokenType.COMPOSITION)) {
                return true;
            }

            // Check for special patterns like <|--
            if (check(MermaidTokenType.ASYMMETRIC_START)) {
                return true; // Could be part of <|--
            }

            return false;
        }

        private MermaidRelationType parse_relationship_arrow() throws GLib.Error {
            // This is simplified - a full implementation would parse
            // the complete arrow syntax with cardinality

            var token = advance();

            // Map based on lexeme patterns
            string arrow = token.lexeme;

            if (arrow.contains("<|--") || (check(MermaidTokenType.PIPE) && peek_ahead_for("--"))) {
                consume_until_arrow_end();
                return MermaidRelationType.INHERITANCE;
            }

            if (arrow.contains("*--") || arrow.starts_with("*")) {
                consume_until_arrow_end();
                return MermaidRelationType.COMPOSITION;
            }

            if (arrow.contains("o--") || arrow.starts_with("o")) {
                consume_until_arrow_end();
                return MermaidRelationType.AGGREGATION;
            }

            if (arrow.contains("..|>")) {
                return MermaidRelationType.REALIZATION;
            }

            if (arrow.contains("..>") || arrow.contains("-.")) {
                return MermaidRelationType.DEPENDENCY;
            }

            // Default to association
            return MermaidRelationType.ASSOCIATION;
        }

        private bool peek_ahead_for(string pattern) {
            // Simple lookahead for pattern
            if (current + 1 < tokens.size) {
                return tokens.get(current + 1).lexeme.contains(pattern);
            }
            return false;
        }

        private void consume_until_arrow_end() {
            // Consume tokens until we get past the arrow
            while (!check(MermaidTokenType.IDENTIFIER) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (check(MermaidTokenType.ASYMMETRIC_START) ||
                    check(MermaidTokenType.PIPE) ||
                    check(MermaidTokenType.LINE_SOLID) ||
                    check(MermaidTokenType.ASTERISK) ||
                    check(MermaidTokenType.ARROW_SOLID)) {
                    advance();
                } else {
                    break;
                }
            }
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {
                // keep skipping
            }
        }

        private void skip_whitespace_same_line() {
            // No-op since lexer handles whitespace
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) {
                    return;
                }

                switch (peek().token_type) {
                    case MermaidTokenType.CLASS_KW:
                    case MermaidTokenType.TITLE:
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
