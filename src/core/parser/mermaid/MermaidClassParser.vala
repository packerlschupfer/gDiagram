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
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
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

            // Skip lines starting with meta-keywords that look like identifiers:
            // note for ClassName "text", namespace Name, accTitle, accDescr
            // Also handle: abstract class Foo, interface class Foo
            if (check(MermaidTokenType.IDENTIFIER)) {
                string kw = peek().lexeme.down();
                if ((kw == "abstract" || kw == "interface") &&
                    peek_at(1).token_type == MermaidTokenType.CLASS_KW) {
                    MermaidClassType pre_type = (kw == "interface")
                        ? MermaidClassType.INTERFACE
                        : MermaidClassType.ABSTRACT;
                    advance(); // consume 'abstract' or 'interface'
                    parse_class(pre_type);
                    return;
                }
                if (kw == "note" || kw == "namespace" || kw == "acctitle" || kw == "accdescr") {
                    while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                        advance();
                    }
                    return;
                }
            }

            // Relationship or class reference
            if (check(MermaidTokenType.IDENTIFIER)) {
                parse_relationship_or_class_reference();
                return;
            }

            // Unknown - skip token
            advance();
        }

        private void parse_title() {
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

        private void parse_class(MermaidClassType pre_type = MermaidClassType.CLASS) throws GLib.Error {
            advance(); // consume 'class'

            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected class name");
            }

            string class_name = advance().lexeme;
            int line = previous().line;

            var cls = diagram.get_or_create_class(class_name);
            cls.source_line = line;
            if (pre_type != MermaidClassType.CLASS) {
                cls.class_type = pre_type;
            }

            // Check for inline stereotype: class Foo <<interface>>
            if (check(MermaidTokenType.ASYMMETRIC_START) &&
                peek_at(1).token_type == MermaidTokenType.ASYMMETRIC_START) {
                advance(); advance(); // consume <<
                if (check(MermaidTokenType.IDENTIFIER)) {
                    cls.stereotype = advance().lexeme;
                    string st = cls.stereotype.down();
                    if (st == "interface") cls.class_type = MermaidClassType.INTERFACE;
                    else if (st == "abstract") cls.class_type = MermaidClassType.ABSTRACT;
                    else if (st == "enum") cls.class_type = MermaidClassType.ENUM;
                }
                if (check(MermaidTokenType.ASYMMETRIC_START)) advance();
                if (check(MermaidTokenType.ASYMMETRIC_START)) advance();
            }

            skip_newlines();

            // Check for class body
            if (match(MermaidTokenType.LBRACE)) {
                parse_class_body(cls);
                if (!match(MermaidTokenType.RBRACE)) {
                    error_at_current("Expected '}'");
                }
            }
        }

        private void parse_class_body(MermaidClass cls) {
            skip_newlines();

            while (!check(MermaidTokenType.RBRACE) && !is_at_end()) {
                // Check for stereotype annotation: <<interface>>, <<abstract>>, etc.
                // Lexer emits ASYMMETRIC_START for both < and >
                if (check(MermaidTokenType.ASYMMETRIC_START) &&
                    peek_at(1).token_type == MermaidTokenType.ASYMMETRIC_START) {
                    advance(); advance(); // consume <<
                    if (check(MermaidTokenType.IDENTIFIER)) {
                        cls.stereotype = advance().lexeme;
                        string st = cls.stereotype.down();
                        if (st == "interface") {
                            cls.class_type = MermaidClassType.INTERFACE;
                        } else if (st == "abstract") {
                            cls.class_type = MermaidClassType.ABSTRACT;
                        } else if (st == "enum") {
                            cls.class_type = MermaidClassType.ENUM;
                        }
                    }
                    // Consume >>
                    if (check(MermaidTokenType.ASYMMETRIC_START)) advance();
                    if (check(MermaidTokenType.ASYMMETRIC_START)) advance();
                    // Consume rest of line
                    while (!check(MermaidTokenType.NEWLINE) && !check(MermaidTokenType.RBRACE) && !is_at_end()) {
                        advance();
                    }
                } else {
                    // Parse member
                    parse_class_member(cls);
                }
                skip_newlines();
            }
        }

        private void parse_class_member(MermaidClass cls) {
            // Parse visibility modifier (+, -, #, ~)
            MermaidVisibility visibility = MermaidVisibility.PUBLIC;

            if (check(MermaidTokenType.PLUS)) {
                advance();
                visibility = MermaidVisibility.PUBLIC;
            } else if (check(MermaidTokenType.SEQ_SOLID_LINE)) {
                // '-' is lexed as SEQ_SOLID_LINE (single dash)
                advance();
                visibility = MermaidVisibility.PRIVATE;
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
                // Could be type or name, need to check what follows
                int saved = current;
                string first = advance().lexeme;

                // Check for generic type: List~Animal~ or Map~String,Integer~
                if (check(MermaidTokenType.TILDE)) {
                    // It's a generic type — consume ~...~
                    var type_sb = new StringBuilder(first);
                    type_sb.append("<");
                    advance(); // consume opening ~
                    while (!check(MermaidTokenType.TILDE) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                        type_sb.append(advance().lexeme);
                    }
                    if (check(MermaidTokenType.TILDE)) {
                        advance(); // consume closing ~
                    }
                    type_sb.append(">");
                    type_name = type_sb.str;
                } else if (check(MermaidTokenType.IDENTIFIER)) {
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
                    // Handle tilde generic syntax: List~Animal~ → List<Animal>
                    if (check(MermaidTokenType.IDENTIFIER)) {
                        string ident = advance().lexeme;
                        if (check(MermaidTokenType.TILDE)) {
                            advance(); // opening ~
                            var generic_sb = new StringBuilder(ident);
                            generic_sb.append("<");
                            while (!check(MermaidTokenType.TILDE) && !check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                                generic_sb.append(advance().lexeme);
                            }
                            if (check(MermaidTokenType.TILDE)) advance(); // closing ~
                            generic_sb.append(">");
                            if (type_parts.len > 0) type_parts.append(" ");
                            type_parts.append(generic_sb.str);
                        } else {
                            if (type_parts.len > 0) type_parts.append(" ");
                            type_parts.append(ident);
                        }
                        continue;
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

            // Optional cardinality before the arrow: ClassA "1" --> ...
            string? from_card = null;
            if (check(MermaidTokenType.STRING)) {
                from_card = advance().lexeme;
                skip_whitespace_same_line();
            }

            // Check for relationship arrow
            if (is_relationship_arrow()) {
                parse_relationship_from(from_name, from_card);
            } else {
                // Just a class reference (discard any cardinality)
                diagram.get_or_create_class(from_name);
            }
        }

        private void parse_relationship_from(string from_name, string? from_card = null) throws GLib.Error {
            var from_class = diagram.get_or_create_class(from_name);

            // Parse relationship arrow
            MermaidRelationType rel_type = parse_relationship_arrow();

            skip_whitespace_same_line();

            // Optional cardinality after the arrow: --> "0..*" ClassB
            string? to_card = null;
            if (check(MermaidTokenType.STRING)) {
                to_card = advance().lexeme;
                skip_whitespace_same_line();
            }

            // Get target class
            if (!check(MermaidTokenType.IDENTIFIER)) {
                error_at_current("Expected target class name");
            }

            string to_name = advance().lexeme;
            var to_class = diagram.get_or_create_class(to_name);

            var relation = new MermaidRelation(from_class, to_class, rel_type);
            relation.from_cardinality = from_card;
            relation.to_cardinality = to_card;

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
            return check(MermaidTokenType.INHERITANCE_LEFT) ||
                   check(MermaidTokenType.INHERITANCE_RIGHT) ||
                   check(MermaidTokenType.COMPOSITION_LEFT) ||
                   check(MermaidTokenType.COMPOSITION_RIGHT) ||
                   check(MermaidTokenType.AGGREGATION_LEFT) ||
                   check(MermaidTokenType.AGGREGATION_RIGHT) ||
                   check(MermaidTokenType.REALIZATION_LEFT) ||
                   check(MermaidTokenType.REALIZATION_RIGHT) ||
                   check(MermaidTokenType.ARROW_SOLID) ||
                   check(MermaidTokenType.ARROW_DOTTED);
        }

        private MermaidRelationType parse_relationship_arrow() throws GLib.Error {
            var token = advance();

            // Map token types directly
            switch (token.token_type) {
                case MermaidTokenType.INHERITANCE_LEFT:
                case MermaidTokenType.INHERITANCE_RIGHT:
                    return MermaidRelationType.INHERITANCE;

                case MermaidTokenType.COMPOSITION_LEFT:
                case MermaidTokenType.COMPOSITION_RIGHT:
                    return MermaidRelationType.COMPOSITION;

                case MermaidTokenType.AGGREGATION_LEFT:
                case MermaidTokenType.AGGREGATION_RIGHT:
                    return MermaidRelationType.AGGREGATION;

                case MermaidTokenType.REALIZATION_LEFT:
                case MermaidTokenType.REALIZATION_RIGHT:
                    return MermaidRelationType.REALIZATION;

                case MermaidTokenType.ARROW_DOTTED:
                    return MermaidRelationType.DEPENDENCY;

                case MermaidTokenType.ARROW_SOLID:
                default:
                    return MermaidRelationType.ASSOCIATION;
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

        private MermaidToken peek_at(int offset) {
            int idx = current + offset;
            if (idx >= tokens.size) return tokens.get(tokens.size - 1); // EOF
            return tokens.get(idx);
        }

        private MermaidToken previous() {
            return tokens.get(current - 1);
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
