namespace GDiagram {
    public class ClassDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ClassDiagram diagram;
        private Gee.ArrayList<ClassPackage> package_stack = new Gee.ArrayList<ClassPackage>();
        // Namespace separator; "" when "set namespaceSeparator none" makes dots literal
        private string ns_separator = ".";
        // "set separator ::": "::" joins name segments instead of "."
        private bool colon_separator = false;
        // "-class Foo": the marker read before the declaration keyword
        private string? pending_class_visibility = null;
        // Target of a note written without "of" ("class Foo" / "note left: text")
        private UmlClass? last_declared_class = null;
        // "hide/show ... members|fields|methods|circle|stereotype" in written order
        private Gee.ArrayList<MemberCommand> member_commands = new Gee.ArrayList<MemberCommand>();

        private class MemberCommand {
            public bool show;
            public string? target;           // class name, "<<stereo>>", "$tag", "@unlinked" or null (all)
            public bool fields;
            public bool methods;
            public bool circle;
            public bool stereotype;
            public bool empty;               // "hide empty members": only empty compartments
            public Gee.ArrayList<MemberVisibility> visibilities = new Gee.ArrayList<MemberVisibility>();
        }

        public ClassDiagramParser() {
            this.current = 0;
        }

        public ClassDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new ClassDiagram();
            this.package_stack = new Gee.ArrayList<ClassPackage>();
            this.ns_separator = ".";
            this.colon_separator = false;
            this.pending_class_visibility = null;
            this.last_declared_class = null;
            this.member_commands = new Gee.ArrayList<MemberCommand>();
            this.visibility_commands = new Gee.ArrayList<string>();
            this.together_open = new Gee.ArrayList<int>();
            this.together_groups_open = new Gee.ArrayList<Gee.ArrayList<UmlClass>>();
            this.note_aliases = new Gee.HashMap<string, ClassNote>();
            this.collision_short_names = new Gee.HashMap<UmlClass, string>();

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }
            apply_visibility_commands();
            apply_member_commands();
            diagram.assign_ids();

            return diagram;
        }

        private void parse_diagram() throws Error {
            skip_newlines();

            // Skip @startuml and any diagram name after it
            if (match(TokenType.STARTUML)) {
                // Skip diagram name if present (e.g., @startuml DiagramName)
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

            pending_class_visibility = null;

            // Visibility-prefixed class declaration: -class, #class, ~class,
            // +class, or any of those before abstract/interface/enum.
            // Lexer emits each prefix as a distinct token: MINUS for `-`,
            // TILDE for `~`, PLUS for `+`, IDENTIFIER "#" for `#`.
            if (is_visibility_prefix_token()) {
                // Kept for the header: PlantUML draws the class's visibility before its name
                pending_class_visibility = advance().lexeme;
                if (check(TokenType.CLASS)) {
                    parse_class_declaration(ClassType.CLASS);
                    return;
                }
                if (check(TokenType.INTERFACE)) {
                    parse_class_declaration(ClassType.INTERFACE);
                    return;
                }
                if (check(TokenType.ABSTRACT)) {
                    advance();
                    if (check(TokenType.CLASS)) {
                        parse_class_declaration(ClassType.ABSTRACT);
                    }
                    return;
                }
                if (check(TokenType.ENUM)) {
                    parse_class_declaration(ClassType.ENUM);
                    return;
                }
                // Prefix wasn't followed by a class keyword — fall through
                pending_class_visibility = null;
            }

            // Class declaration
            if (check(TokenType.CLASS)) {
                parse_class_declaration(ClassType.CLASS);
                return;
            }

            // Interface declaration
            if (check(TokenType.INTERFACE)) {
                parse_class_declaration(ClassType.INTERFACE);
                return;
            }

            // Abstract class: "abstract class D", or "abstract D" (became a plain class)
            if (check(TokenType.ABSTRACT)) {
                if (starts_short_declaration()) {
                    parse_class_declaration(ClassType.ABSTRACT);
                    return;
                }
                advance();
                if (check(TokenType.CLASS)) {
                    parse_class_declaration(ClassType.ABSTRACT);
                }
                return;
            }

            // "annotation Ann" / "struct S" / "exception E" / "record R" ...: these words lex as
            // identifiers, so the line became a class named after the keyword
            ClassType keyword_type = ClassType.CLASS;
            if (check(TokenType.IDENTIFIER) && declaration_keyword_type(peek().lexeme, out keyword_type) &&
                starts_short_declaration()) {
                parse_class_declaration(keyword_type);
                return;
            }
            // "diamond d1": an association diamond, like "<> d1". The keyword became a class.
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "diamond" && starts_short_declaration()) {
                advance();
                var name_tok = advance();
                string dname = name_tok.token_type == TokenType.STRING
                    ? name_tok.lexeme : read_qualified_name(name_tok.lexeme);
                var diamond = class_in_scope(dname, name_tok.line, false);
                diamond.is_diamond = true;
                expect_end_of_statement();
                return;
            }
            // "() c1": short form of "circle c1". The line was dropped.
            if (check(TokenType.LPAREN) && current + 2 < tokens.size &&
                tokens[current + 1].token_type == TokenType.RPAREN && !tokens[current + 1].space_before &&
                !is_arrow_piece_at(current + 2, true) &&
                (tokens[current + 2].token_type == TokenType.STRING || is_word_token(tokens[current + 2]))) {
                advance();
                advance();
                var name_tok = advance();
                string cname = name_tok.token_type == TokenType.STRING
                    ? name_tok.lexeme : read_qualified_name(name_tok.lexeme);
                UmlClass circle;
                if (check(TokenType.AS) && current + 1 < tokens.size) {
                    advance();
                    circle = class_in_scope(advance().lexeme, name_tok.line, false);
                    circle.display_name = cname;
                } else {
                    circle = class_in_scope(cname, name_tok.line, false);
                }
                circle.class_type = ClassType.CIRCLE;
                last_declared_class = circle;
                expect_end_of_statement();
                return;
            }
            // "(A, B) .. C": association class on the link between A and B. It was dropped.
            if (check(TokenType.LPAREN) && try_parse_association_class()) {
                return;
            }
            // "page 2x2" / "scale 750 width": output settings with nothing to draw. "page"
            // became a class.
            if (check(TokenType.IDENTIFIER) && (peek().lexeme == "page" || peek().lexeme == "scale") &&
                current + 1 < tokens.size && tokens[current + 1].space_before &&
                tokens[current + 1].token_type != TokenType.NEWLINE && !is_arrow_piece_at(current + 1, true) &&
                tokens[current + 1].lexeme.length > 0 && tokens[current + 1].lexeme.get_char(0).isdigit()) {
                skip_to_end_of_line();
                return;
            }

            // Enum declaration
            if (check(TokenType.ENUM)) {
                parse_class_declaration(ClassType.ENUM);
                return;
            }

            // Entity declaration (IE/crow's-foot diagrams). "entity" lines were skipped,
            // so their boxes, attributes and links vanished.
            if (check(TokenType.ENTITY)) {
                parse_class_declaration(ClassType.ENTITY);
                return;
            }

            // set namespaceSeparator <sep|none> / set separator <sep|none>
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "set" && current + 1 < tokens.size) {
                string setting = tokens[current + 1].lexeme.down();
                if (setting == "namespaceseparator" || setting == "separator") {
                    advance();
                    advance();
                    var value = new StringBuilder();
                    while (!check(TokenType.NEWLINE) && !is_at_end()) {
                        value.append(advance().lexeme);
                    }
                    // "." and "::" are understood ("::" names are read as dotted ones, so
                    // "X1::X2::foo" is foo in package X2 in X1); none keeps names literal
                    string sep = value.str.strip();
                    ns_separator = sep == "." || sep == "::" ? "." : "";
                    colon_separator = sep == "::";
                    return;
                }
            }

            // left to right direction / top to bottom direction. Skipped as an
            // unknown line before, so class diagrams always laid out top to bottom.
            if (is_direction_statement("left", "right")) {
                diagram.left_to_right = true;
                skip_to_end_of_line();
                return;
            }
            if (is_direction_statement("top", "bottom")) {
                diagram.left_to_right = false;
                skip_to_end_of_line();
                return;
            }

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Title, header, footer
            if (match(TokenType.TITLE)) {
                diagram.title = parse_text_content();
                return;
            }
            if (match(TokenType.HEADER)) {
                diagram.header = parse_text_content();
                return;
            }
            if (match(TokenType.FOOTER)) {
                diagram.footer = parse_text_content();
                return;
            }

            // "legend right ... endlegend". Its lines became classes, "endlegend" among them.
            if (check(TokenType.LEGEND) && !is_arrow_piece_at(current + 1, true)) {
                diagram.legend = ComponentDiagramParser.read_legend_block(tokens, ref current);
                return;
            }

            // Note handling
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // "hide X" / "hide $tag" / "hide @unlinked" / "hide <<s>>" hide classes. Member forms
            // ("hide empty members", "hide Foo methods") and "show" are still skipped.
            if (check(TokenType.HIDE) || check(TokenType.SHOW)) {
                bool show = advance().token_type == TokenType.SHOW;
                int start = current;
                if (!read_member_command(show)) {
                    current = start;
                    string? target = read_visibility_target();
                    if (target != null) {
                        visibility_commands.add((show ? "show " : "hide ") + target);
                    }
                }
                skip_to_end_of_line();
                return;
            }
            // "remove X" / "restore X" (same targets, plus "*"). Both lines used to become a
            // class named "remove"/"restore" or were ignored.
            if (check(TokenType.IDENTIFIER) && (peek().lexeme == "remove" || peek().lexeme == "restore") &&
                !is_arrow_piece_at(current + 1, true)) {
                string action = advance().lexeme;
                string? target = read_visibility_target();
                if (target != null) {
                    visibility_commands.add(action + " " + target);
                }
                skip_to_end_of_line();
                return;
            }

            // "<> name": association diamond. The "<" and ">" came through as a class
            // named "<".
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "<" && current + 2 < tokens.size &&
                tokens[current + 1].lexeme == ">" && !tokens[current + 1].space_before &&
                (tokens[current + 2].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 2].token_type == TokenType.STRING)) {
                advance();
                advance();
                var name_tok = advance();
                string dname = name_tok.token_type == TokenType.STRING
                    ? name_tok.lexeme : read_qualified_name(name_tok.lexeme);
                var diamond = class_in_scope(dname, name_tok.line, false);
                diamond.is_diamond = true;
                expect_end_of_statement();
                return;
            }

            // package / namespace blocks. They used to be skipped line by line, so
            // their classes were drawn loose with no box around them.
            if (check(TokenType.PACKAGE) || (check(TokenType.IDENTIFIER) && peek().lexeme == "namespace")) {
                parse_package();
                return;
            }
            // "together { ... }": its classes are grouped. The word used to become a
            // ghost class named "together".
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "together" && current + 1 < tokens.size &&
                tokens[current + 1].token_type == TokenType.LBRACE) {
                advance();
                advance();
                together_open.add(package_stack.size);
                var group = new Gee.ArrayList<UmlClass>();
                together_groups_open.add(group);
                diagram.together_groups.add(group);
                return;
            }
            if (check(TokenType.RBRACE) && together_open.size > 0 &&
                together_open[together_open.size - 1] == package_stack.size) {
                advance();
                together_open.remove_at(together_open.size - 1);
                together_groups_open.remove_at(together_groups_open.size - 1);
                return;
            }
            if (check(TokenType.RBRACE) && package_stack.size > 0) {
                advance();
                package_stack.remove_at(package_stack.size - 1);
                return;
            }

            // Relationship or identifier (class reference)
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                parse_relationship_or_class();
                return;
            }

            // A keyword used as a name or alias ("node }o--|| Customer") also starts a
            // relationship when an arrow follows it
            if (is_word_token(peek()) && is_arrow_piece_at(current + 1, true)) {
                parse_relationship_or_class();
                return;
            }

            // Unknown - skip to next line
            skip_to_end_of_line();
            if (!is_at_end()) {
                advance();  // consume the newline itself
            }
        }

        // Class-like declaration keywords that lex as plain identifiers
        private static bool declaration_keyword_type(string word, out ClassType type) {
            switch (word) {
                case "annotation": type = ClassType.ANNOTATION; return true;
                case "struct": type = ClassType.STRUCT; return true;
                case "exception": type = ClassType.EXCEPTION; return true;
                case "protocol": type = ClassType.PROTOCOL; return true;
                case "metaclass": type = ClassType.METACLASS; return true;
                case "stereotype": type = ClassType.STEREOTYPE; return true;
                case "dataclass": type = ClassType.DATACLASS; return true;
                case "record": type = ClassType.RECORD; return true;
                case "circle": type = ClassType.CIRCLE; return true;
                default: type = ClassType.CLASS; return false;
            }
        }

        // A declaration keyword followed by the class name on the same line ("abstract D",
        // "struct S"), not by an arrow ("struct --> X" names a class "struct")
        private bool starts_short_declaration() {
            if (current + 1 >= tokens.size) {
                return false;
            }
            var next = tokens[current + 1];
            if (!next.space_before || next.token_type == TokenType.CLASS || is_arrow_piece_at(current + 1, true)) {
                return false;
            }
            return next.token_type == TokenType.STRING || is_word_token(next);
        }

        // "hide"/"remove"/"restore" commands in written order, applied after parsing
        private Gee.ArrayList<string> visibility_commands = new Gee.ArrayList<string>();
        // Open "together" blocks: the package depth each opened at, and its class group
        private Gee.ArrayList<int> together_open = new Gee.ArrayList<int>();
        private Gee.ArrayList<Gee.ArrayList<UmlClass>> together_groups_open = new Gee.ArrayList<Gee.ArrayList<UmlClass>>();
        // Floating notes by alias ("note "text" as N1")
        private Gee.HashMap<string, ClassNote> note_aliases = new Gee.HashMap<string, ClassNote>();
        // Short names of classes keyed by their package because the bare name was taken
        private Gee.HashMap<UmlClass, string> collision_short_names = new Gee.HashMap<UmlClass, string>();

        // Single target of hide/remove/restore: a name, "*", "$tag", "@unlinked" or "<<stereo>>".
        // Null for member forms ("hide empty members", "hide Foo methods", "hide circle").
        private string? read_visibility_target() {
            var sb = new StringBuilder();
            bool first = true;
            bool several_words = false;
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = peek();
                if (t.token_type == TokenType.COMMENT) {
                    break;
                }
                if (!first && t.space_before) {
                    several_words = true;
                }
                if (t.token_type == TokenType.STEREOTYPE) {
                    sb.append("<<" + t.lexeme + ">>");
                } else {
                    sb.append(t.lexeme);
                }
                advance();
                first = false;
            }
            string target = sb.str.strip();
            if (several_words || target.length == 0) {
                return null;
            }
            switch (target.down()) {
                case "members":
                case "member":
                case "fields":
                case "field":
                case "attributes":
                case "attribute":
                case "methods":
                case "method":
                case "circle":
                case "circles":
                case "stereotype":
                case "stereotypes":
                case "footbox":
                case "empty":
                    return null;
                default:
                    return target;
            }
        }

        // "hide members", "show A methods", "hide <<S>> circle", "hide private members",
        // "hide empty fields", "hide stereotype": a member-portion command. False (cursor
        // anywhere) when the line is not one.
        private bool read_member_command(bool show) {
            var words = new Gee.ArrayList<string>();
            var sb = new StringBuilder();
            bool first = true;
            while (!check(TokenType.NEWLINE) && !is_at_end() && !check(TokenType.COMMENT)) {
                Token t = advance();
                if (!first && t.space_before && sb.len > 0) {
                    words.add(sb.str);
                    sb.truncate(0);
                }
                sb.append(t.token_type == TokenType.STEREOTYPE ? "<<" + t.lexeme + ">>" : t.lexeme);
                first = false;
            }
            if (sb.len > 0) {
                words.add(sb.str);
            }
            if (words.size == 0) {
                return false;
            }
            var cmd = new MemberCommand();
            cmd.show = show;
            switch (words[words.size - 1].down()) {
                case "members":
                case "member":
                    cmd.fields = true;
                    cmd.methods = true;
                    break;
                case "fields":
                case "field":
                case "attributes":
                case "attribute":
                    cmd.fields = true;
                    break;
                case "methods":
                case "method":
                    cmd.methods = true;
                    break;
                case "circle":
                case "circles":
                case "circled":
                    cmd.circle = true;
                    break;
                case "stereotype":
                case "stereotypes":
                    cmd.stereotype = true;
                    break;
                default:
                    return false;
            }
            for (int i = 0; i < words.size - 1; i++) {
                string w = words[i];
                switch (w.down()) {
                    case "empty": cmd.empty = true; break;
                    case "public": cmd.visibilities.add(MemberVisibility.PUBLIC); break;
                    case "private": cmd.visibilities.add(MemberVisibility.PRIVATE); break;
                    case "protected": cmd.visibilities.add(MemberVisibility.PROTECTED); break;
                    case "package": cmd.visibilities.add(MemberVisibility.PACKAGE); break;
                    default:
                        if (cmd.target != null) {
                            return false;
                        }
                        cmd.target = w;
                        break;
                }
            }
            member_commands.add(cmd);
            return true;
        }

        private Gee.HashSet<UmlClass> linked_classes() {
            var linked = new Gee.HashSet<UmlClass>();
            foreach (var rel in diagram.relationships) {
                if (rel.from != rel.to) {
                    linked.add(rel.from);
                    linked.add(rel.to);
                }
            }
            foreach (var link in diagram.package_links) {
                if (link.from_class != null) {
                    linked.add(link.from_class);
                }
                if (link.to_class != null) {
                    linked.add(link.to_class);
                }
            }
            return linked;
        }

        // Member-portion commands apply to every matching class wherever it is declared, in
        // written order (PlantUML: "hide members" then "show A methods")
        private void apply_member_commands() {
            if (member_commands.size == 0) {
                return;
            }
            var linked = linked_classes();
            foreach (var cmd in member_commands) {
                foreach (var c in diagram.classes) {
                    if (cmd.target != null && !visibility_target_matches(c, cmd.target, linked)) {
                        continue;
                    }
                    bool hide = !cmd.show;
                    if (cmd.visibilities.size > 0) {
                        foreach (var m in c.members) {
                            if (m.separator != null || !m.visibility_explicit ||
                                !cmd.visibilities.contains(m.visibility)) {
                                continue;
                            }
                            if ((m.is_method && cmd.methods) || (!m.is_method && cmd.fields)) {
                                m.hidden_member = hide;
                            }
                        }
                        continue;
                    }
                    if (cmd.empty) {
                        if (cmd.fields) c.empty_fields_hidden = hide;
                        if (cmd.methods) c.empty_methods_hidden = hide;
                        continue;
                    }
                    if (cmd.fields) c.fields_hidden = hide;
                    if (cmd.methods) c.methods_hidden = hide;
                    if (cmd.circle) c.circle_hidden = hide;
                    if (cmd.stereotype) c.stereotype_hidden = hide;
                }
            }
        }

        // In written order, so "remove *" then "restore $tag1" works; "@unlinked" sees every
        // relationship of the finished diagram
        private void apply_visibility_commands() {
            if (visibility_commands.size == 0) {
                return;
            }
            var linked = new Gee.HashSet<UmlClass>();
            foreach (var rel in diagram.relationships) {
                if (rel.from != rel.to) {
                    linked.add(rel.from);
                    linked.add(rel.to);
                }
            }
            foreach (var link in diagram.package_links) {
                if (link.from_class != null) {
                    linked.add(link.from_class);
                }
                if (link.to_class != null) {
                    linked.add(link.to_class);
                }
            }
            foreach (string cmd in visibility_commands) {
                int sp = cmd.index_of(" ");
                string action = cmd.substring(0, sp);
                string target = cmd.substring(sp + 1);
                foreach (var c in diagram.classes) {
                    if (!visibility_target_matches(c, target, linked)) {
                        continue;
                    }
                    if (action == "remove") {
                        c.removed = true;
                        c.hidden = false;
                    } else if (action == "hide") {
                        if (!c.removed) {
                            c.hidden = true;
                        }
                    } else if (action == "show") {
                        c.hidden = false;
                    } else {
                        c.removed = false;
                        c.hidden = false;
                    }
                }
            }
        }

        // "$x" is always a tag, as in PlantUML: "remove $C1" leaves a class named "$C1" alone
        private static bool visibility_target_matches(UmlClass c, string target, Gee.HashSet<UmlClass> linked) {
            if (target == "*") {
                return true;
            }
            if (target == "@unlinked") {
                return !linked.contains(c);
            }
            if (target.has_prefix("$")) {
                return c.tags.contains(target);
            }
            if (target.has_prefix("<<") && target.has_suffix(">>") && target.length > 4) {
                return c.stereotype != null && c.stereotype == target.substring(2, target.length - 4);
            }
            return c.name == target;
        }

        // "$tag13 $tag1" after a declaration; "$" lexes as a token of its own
        private void read_class_tags(UmlClass c) {
            while (check(TokenType.IDENTIFIER) && peek().lexeme == "$" && current + 1 < tokens.size &&
                   !tokens[current + 1].space_before && is_word_token(tokens[current + 1])) {
                advance();
                c.tags.add("$" + advance().lexeme);
            }
        }

        private void parse_skinparam() {
            // Parse skinparam directives and store in diagram.skin_params
            // Single line: skinparam PropertyName value
            // Block: skinparam element { PropertyName value ... }

            // Get the first identifier (could be element name or property name)
            // Note: element names like "class", "state", "component" are keywords, not identifiers
            string first_name = "";
            // Any token can name the element. A keyword whitelist missed "state",
            // "component", "package", ... and the block body was then parsed as
            // classes named after its properties (StartColor, EndColor, ...).
            if (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                first_name = advance().lexeme;
            } else {
                // No identifier after skinparam - skip line
                skip_to_end_of_line();
                return;
            }

            // Check if this is block syntax
            if (match(TokenType.LBRACE)) {
                // Block syntax: skinparam element { property value ... }
                string element = first_name;
                parse_skinparam_block(element);
            } else {
                // Single line syntax. "stereotypeCBackgroundColor<<Foo>> DimGray" keeps the
                // stereotype in the key: it was read as the value "Foo DimGray" and replaced the
                // colour of every class.
                if (check(TokenType.STEREOTYPE) && !peek().space_before) {
                    first_name = "%s<<%s>>".printf(first_name, advance().lexeme.strip().down());
                }
                string value = collect_skinparam_value();
                if (value.length > 0) {
                    diagram.skin_params.set_global(first_name, value);
                }
            }
        }

        private void parse_skinparam_block(string element) {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE)) {
                    break;
                }

                // Get property name
                if (!check(TokenType.IDENTIFIER)) {
                    advance();
                    continue;
                }

                string property = advance().lexeme;
                if (check(TokenType.STEREOTYPE)) {
                    property = "%s<<%s>>".printf(property, advance().lexeme.down());
                }
                string value = collect_skinparam_value();

                if (value.length > 0) {
                    diagram.skin_params.set_element_property(element, property, value);
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        private string collect_skinparam_value() {
            // Collect value tokens until newline or closing brace
            // Colors like #1e1e1e are tokenized as # + 1 + e1e1e, so we need to join without spaces
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                // Check if this is a hash starting a color
                if (t.lexeme == "#") {
                    if (sb.len > 0 && t.space_before) {
                        sb.append(" ");
                    }
                    sb.append(t.lexeme);
                    in_color = true;
                } else if (in_color) {
                    // Continue collecting color without spaces
                    sb.append(t.lexeme);
                    if (!check(TokenType.IDENTIFIER) && !check(TokenType.HASH)) {
                        in_color = false;
                    }
                } else {
                    // Regular token - add space separator
                    if (sb.len > 0 && t.space_before) {
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

private bool is_direction_statement(string first, string second) {
            return current + 3 < tokens.size &&
                   tokens[current].lexeme == first && tokens[current + 1].lexeme == "to" &&
                   tokens[current + 2].lexeme == second && tokens[current + 3].lexeme == "direction";
        }

        // True when tokens[idx] starts a relationship arrow
        private bool is_link_token_at(int idx) {
            return is_arrow_piece_at(idx, true);
        }

        private const string ARROW_CHARS = "-.<>|*o#x+{}^";

        // A token that can be part of an arrow's text. The first piece must hold a
        // line character itself ("--", "<|-") or be a marker directly followed by one.
        private bool is_arrow_piece_at(int idx, bool first) {
            if (idx >= tokens.size) {
                return false;
            }
            var t = tokens[idx];
            if (t.token_type == TokenType.NEWLINE || t.token_type == TokenType.EOF ||
                t.token_type == TokenType.STRING || t.lexeme.length == 0) {
                return false;
            }
            for (int i = 0; i < t.lexeme.length; i++) {
                if (ARROW_CHARS.index_of_char(t.lexeme[i]) < 0) {
                    return false;
                }
            }
            if (!first || t.lexeme.contains("-") || t.lexeme.contains(".")) {
                return true;
            }
            if (idx + 1 >= tokens.size || tokens[idx + 1].space_before) {
                return false;
            }
            string next = tokens[idx + 1].lexeme;
            if (next.has_prefix("-") || next.has_prefix(".")) {
                return true;
            }
            // Crow's-foot ends put two markers before the line: "}o--" (the lexer makes
            // "o--" one token) and "||--". Both were not taken as arrows at all.
            if (!is_arrow_chars(next)) {
                return false;
            }
            if (next.contains("-") || next.contains(".")) {
                return true;
            }
            return idx + 2 < tokens.size && !tokens[idx + 2].space_before &&
                   (tokens[idx + 2].lexeme.has_prefix("-") || tokens[idx + 2].lexeme.has_prefix("."));
        }

        private static bool is_arrow_chars(string s) {
            if (s.length == 0) {
                return false;
            }
            for (int i = 0; i < s.length; i++) {
                if (ARROW_CHARS.index_of_char(s[i]) < 0) {
                    return false;
                }
            }
            return true;
        }

        // Names and aliases may be keywords ("as node"); IDENTIFIER-only checks dropped them
        private static bool is_word_token(Token t) {
            return t.token_type != TokenType.STRING && t.token_type != TokenType.NEWLINE &&
                   t.token_type != TokenType.EOF && t.lexeme.length > 0 &&
                   (t.lexeme.get_char(0).isalnum() || t.lexeme[0] == '_');
        }

        private static bool is_direction_word(string w) {
            switch (w.down()) {
                case "u": case "up":
                case "d": case "do": case "dow": case "down":
                case "l": case "le": case "lef": case "left":
                case "r": case "ri": case "rig": case "righ": case "right":
                    return true;
                default:
                    return false;
            }
        }

        private static string flip_placement(string p) {
            switch (p) {
                case "up": return "down";
                case "down": return "up";
                case "left": return "right";
                case "right": return "left";
                default: return p;
            }
        }

        // Reads an arrow such as "-up->" or "-[#red,dashed]->" from the adjacent
        // tokens at the cursor. Returns its line-and-marker text ("->") with the
        // direction and bracket options split out, or null (cursor unchanged).
        private string? read_arrow_text(out string placement, out string? line_style, out string? line_color) {
            placement = "";
            line_style = null;
            line_color = null;
            if (!is_arrow_piece_at(current, true)) {
                return null;
            }
            int start = current;
            var sb = new StringBuilder();
            bool first = true;
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                Token t = peek();
                if (!first && t.space_before) {
                    break;
                }
                string tail = sb.str;
                bool in_body = tail.has_suffix("-") || tail.has_suffix(".");
                bool open_end = first || in_body || tail.has_suffix("|") || tail.has_suffix("<") || tail.length == 1 ||
                                // crow's-foot right ends "--o{" and "--o|"
                                (tail.has_suffix("o") && (t.lexeme == "{" || t.lexeme == "|")) ||
                                // dotted crow's-foot left ends "|o.." and "}o..": the lexer
                                // splits them into "|" "o" "..", and the arrow stopped at "o"
                                (tail.has_suffix("o") && t.lexeme.has_prefix("."));
                if (open_end && is_arrow_piece_at(current, first)) {
                    advance();
                    sb.append(t.lexeme);
                } else if (in_body && is_direction_word(t.lexeme)) {
                    advance();
                    switch (t.lexeme.down().substring(0, 1)) {
                        case "u": placement = "up"; break;
                        case "d": placement = "down"; break;
                        case "l": placement = "left"; break;
                        default: placement = "right"; break;
                    }
                } else if (in_body && t.token_type == TokenType.LBRACKET) {
                    advance();
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        string opt = advance().lexeme;
                        string low = opt.down();
                        if (low == "thickness" && check(TokenType.IDENTIFIER) && peek().lexeme == "=" &&
                            current + 1 < tokens.size) {
                            // "-[thickness=8]->": the line width. It was ignored.
                            advance();
                            last_arrow_thickness = int.parse(advance().lexeme);
                        } else if (low == "hidden") {
                            line_style = "invis";
                        } else if (low == "dashed" || low == "dotted" || low == "bold") {
                            line_style = low;
                        } else if (opt.has_prefix("#") && opt.length > 1) {
                            line_color = opt;
                        }
                    }
                    match(TokenType.RBRACKET);
                } else {
                    break;
                }
                first = false;
            }
            string text = sb.str;
            bool has_line = text.contains("-") || text.contains(".");
            // A lone "-" or "." is a link only with whitespace after it; "-ri(0)->"
            // and similar non-class arrows must not turn their next word into a class.
            bool lone = text == "-" || text == ".";
            if (!has_line || (lone && !is_at_end() && !check(TokenType.NEWLINE) && !peek().space_before)) {
                current = start;
                placement = "";
                line_style = null;
                line_color = null;
                return null;
            }
            return text;
        }

        // Relationship type and direction from arrow text. Returns true when the
        // line is a single "-" or "." (drawn side by side, as in PlantUML).
        // Marker of the last aggregation-style arrow classified ("+", "#", "x", "}", "^", "o")
        private string? last_arrow_marker = null;
        // "[thickness=N]" of the last arrow read, 0 when not given
        private int last_arrow_thickness = 0;
        // Graphviz shapes of the crow's-foot ends of the last arrow classified
        private string? last_ie_tail = null;
        private string? last_ie_head = null;

        // "||" exactly one, "|o"/"o|" zero or one, "}|"/"|{" one or more, "}o"/"o{" zero or
        // more. Graphviz draws the first shape at the node: the maximum sits there.
        private static string ie_end_shape(string m) {
            switch (m) {
                case "||": return "teetee";
                case "|o":
                case "o|": return "teeodot";
                case "}|":
                case "|{": return "crowtee";
                default: return "crowodot";
            }
        }

        private bool classify_arrow(string arrow, out RelationshipType? type, out bool reverse, out bool undirected) {
            last_arrow_marker = null;
            last_ie_tail = null;
            last_ie_head = null;
            // Crow's-foot (IE) ends, checked before the one-character markers they contain
            string ie_body = arrow;
            foreach (string m in new string[] { "||", "|o", "}|", "}o" }) {
                if (ie_body.has_prefix(m) && ie_body.length > m.length) {
                    last_ie_tail = ie_end_shape(m);
                    ie_body = ie_body.substring(m.length);
                    break;
                }
            }
            foreach (string m in new string[] { "||", "o|", "|{", "o{" }) {
                if (ie_body.has_suffix(m) && ie_body.length > m.length) {
                    last_ie_head = ie_end_shape(m);
                    ie_body = ie_body.substring(0, ie_body.length - m.length);
                    break;
                }
            }
            if (last_ie_tail != null || last_ie_head != null) {
                type = ie_body.contains(".") ? RelationshipType.DEPENDENCY : RelationshipType.ASSOCIATION;
                reverse = false;
                undirected = false;
                return ie_body.length == 1;
            }
            string body = arrow;
            string left = "";
            string right = "";
            foreach (string m in new string[] { "<|", "<<", "<", "*", "o", "#", "x", "}", "+", "^" }) {
                if (body.has_prefix(m) && body.length > m.length) {
                    left = m;
                    body = body.substring(m.length);
                    break;
                }
            }
            foreach (string m in new string[] { "|>", ">>", ">", "*", "o", "#", "x", "{", "}", "+", "^" }) {
                if (body.has_suffix(m) && body.length > m.length) {
                    right = m;
                    body = body.substring(0, body.length - m.length);
                    break;
                }
            }
            bool dotted = body.contains(".");
            reverse = false;
            undirected = false;
            if (left == "<|" || right == "|>") {
                type = dotted ? RelationshipType.IMPLEMENTATION : RelationshipType.INHERITANCE;
                reverse = left == "<|";
            } else if (left == "*" || right == "*") {
                type = RelationshipType.COMPOSITION;
                reverse = left != "*";
            } else if (left.length > 0 && left != "<" && left != "<<") {
                type = RelationshipType.AGGREGATION;
                last_arrow_marker = left;
            } else if (right.length > 0 && right != ">" && right != ">>") {
                type = RelationshipType.AGGREGATION;
                last_arrow_marker = right;
                reverse = true;
            } else if (right == ">" || right == ">>") {
                type = dotted ? RelationshipType.DEPENDENCY : RelationshipType.ASSOCIATION;
            } else if (left == "<" || left == "<<") {
                type = dotted ? RelationshipType.DEPENDENCY : RelationshipType.ASSOCIATION;
                reverse = true;
            } else {
                type = dotted ? RelationshipType.DEPENDENCY : RelationshipType.ASSOCIATION;
                undirected = true;
            }
            // Markers at both ends ("<-->", "*-->", "<|--*"): draw both. Only one branch above
            // wins, so the other end was lost. "x" is left out: its SVG redraw expects a
            // single polygon on the edge.
            if (left.length > 0 && right.length > 0 && left != "x" && right != "x") {
                string left_shape = end_marker_shape(left);
                string right_shape = end_marker_shape(right);
                // ie_tail sits at the relationship's `from`, which is the right-hand name
                // when the arrow is reversed
                last_ie_tail = reverse ? right_shape : left_shape;
                last_ie_head = reverse ? left_shape : right_shape;
            }
            return body.length == 1;
        }

        // Graphviz arrow shape of one end marker of a class arrow
        private static string end_marker_shape(string m) {
            switch (m) {
                case "<|":
                case "|>": return "empty";
                case "*": return "diamond";
                case "o": return "odiamond";
                case "+": return "odot";
                case "#": return "obox";
                case "{":
                case "}": return "crow";
                case "^": return "onormal";
                default: return "open";  // "<", ">", "<<", ">>"
            }
        }

        // "foo1.foo2" lexes as foo1 "." foo2; join the pieces back into one name
        private string read_qualified_name(string head) {
            var sb = new StringBuilder(head);
            // ".Name" is the global Name (used inside a namespace)
            if (head == "." && check(TokenType.IDENTIFIER) && !peek().space_before &&
                peek().lexeme.length > 0 && peek().lexeme.get_char(0).isalnum()) {
                sb.append(advance().lexeme);
            }
            // "set separator ::": "X1::X2::foo" is read as "X1.X2.foo"
            while (colon_separator && check(TokenType.COLON) && !peek().space_before &&
                   current + 2 < tokens.size && tokens[current + 1].token_type == TokenType.COLON &&
                   !tokens[current + 1].space_before && !tokens[current + 2].space_before &&
                   is_word_token(tokens[current + 2])) {
                advance();
                advance();
                sb.append(".");
                sb.append(advance().lexeme);
            }
            while (check(TokenType.IDENTIFIER) && peek().lexeme == "." && !peek().space_before &&
                   current + 1 < tokens.size && !tokens[current + 1].space_before &&
                   tokens[current + 1].lexeme.length > 0 && tokens[current + 1].lexeme.get_char(0).isalnum()) {
                advance();
                sb.append(".");
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        // "::member" right after a class name ("C::x --> A"): a link to a member is drawn to
        // its class, as in PlantUML. The link was dropped.
        private void skip_member_suffix() {
            if (!check(TokenType.COLON) || peek().space_before || current + 2 >= tokens.size ||
                tokens[current + 1].token_type != TokenType.COLON || tokens[current + 1].space_before ||
                tokens[current + 2].space_before ||
                (!is_word_token(tokens[current + 2]) && tokens[current + 2].token_type != TokenType.STRING)) {
                return;
            }
            advance();
            advance();
            advance();
            // "C::run()": the parentheses belong to the member name
            if (check(TokenType.LPAREN) && !peek().space_before) {
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    if (advance().token_type == TokenType.RPAREN) {
                        break;
                    }
                }
            }
        }

        // A relationship end names a package when no class has that name
        private ClassPackage? package_endpoint(string name) {
            return diagram.find_class(qualify(name)) == null ? diagram.find_package(name) : null;
        }

        // "a.b.c" as nested top-level packages a > b > c, each labelled with its last
        // segment and keyed by its full path. Returns the innermost package.
        private ClassPackage ensure_package_path(string full, int line) {
            ClassPackage? parent = null;
            string path = "";
            foreach (string part in full.split(".")) {
                if (part.length == 0) {
                    continue;
                }
                path = path.length > 0 ? path + "." + part : part;
                var pkg = diagram.find_package(path);
                if (pkg == null) {
                    pkg = new ClassPackage(path, line);
                    pkg.label = part;
                    if (parent != null) {
                        pkg.parent = parent;
                        parent.children.add(pkg);
                    } else {
                        diagram.packages.add(pkg);
                    }
                }
                parent = pkg;
            }
            return parent;
        }

        // Nearest enclosing "namespace" block, if any
        private ClassPackage? current_namespace() {
            for (int i = package_stack.size - 1; i >= 0; i--) {
                if (package_stack[i].is_namespace) {
                    return package_stack[i];
                }
            }
            return null;
        }

        // Full class key for a name as written, following PlantUML: "a.b.X" is
        // already qualified, ".X" is global, and a bare name inside a namespace
        // belongs to it. Dotted names used to be taken literally, so
        // "net.dummy.Person" and "Person" inside net.dummy were two classes.
        private string qualify(string name) {
            if (ns_separator != ".") {
                return name;
            }
            if (name.has_prefix(".") && name.length > 1) {
                return name.substring(1);
            }
            if (name.contains(".")) {
                return name;
            }
            var ns = current_namespace();
            return ns != null ? ns.name + "." + name : name;
        }

        // Put a class into its box: the namespace named by its qualifier (created
        // if needed, as PlantUML does), otherwise the open package block. A ".X"
        // global reference goes nowhere.
        private void place_class(UmlClass c, string written, string full) {
            if (c.owner_package != null) {
                return;
            }
            int dot = ns_separator == "." ? full.last_index_of(".") : -1;
            if (dot > 0 && dot < full.length - 1) {
                string prefix = full.substring(0, dot);
                var pkg = diagram.find_package(prefix);
                if (pkg == null) {
                    pkg = ensure_package_path(prefix, c.source_line);
                    pkg.is_namespace = true;
                }
                c.owner_package = pkg;
                pkg.classes.add(c);
                if (c.display_name == null) {
                    c.display_name = full.substring(dot + 1);
                }
                return;
            }
            if (!written.has_prefix(".")) {
                add_to_open_package(c);
            }
        }

        // package "Name" [<<Stereotype>>] [#color] [{]
        private void parse_package() {
            int line = peek().line;
            bool is_namespace = advance().lexeme == "namespace";

            var name_sb = new StringBuilder();
            string? color = null;
            string? alias = null;
            string? pkg_style = null;
            bool quoted = false;
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                Token t = advance();
                if (t.token_type == TokenType.STRING) {
                    quoted = true;
                }
                if (t.token_type == TokenType.STEREOTYPE) {
                    // Shape stereotypes (<<Folder>>, <<Node>>, ...) pick the box's look
                    pkg_style = t.lexeme.strip().down();
                    continue;
                } else if (t.token_type == TokenType.IDENTIFIER && t.lexeme.has_prefix("#") && t.lexeme.length > 1) {
                    color = t.lexeme;
                } else if (t.token_type == TokenType.AS || t.lexeme == "as") {
                    // "package Name as Alias": the alias names the package in references. It
                    // was dropped, so "X --> Alias" drew a stray class box.
                    if (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                        alias = advance().lexeme;
                    }
                } else {
                    if (name_sb.len > 0 && t.space_before) {
                        name_sb.append(" ");
                    }
                    name_sb.append(t.lexeme);
                }
            }

            // A block for a package that already exists (declared earlier, or created
            // for a qualified class name) reopens it instead of drawing a second box
            // Looked up in the enclosing package only: searching the whole tree merged
            // Alpha's "Common" with Beta's "Common" (PlantUML keeps them apart).
            string pkg_name = name_sb.str.strip();
            ClassPackage? pkg = null;
            var siblings = package_stack.size > 0 ? package_stack[package_stack.size - 1].children : diagram.packages;
            string parent_prefix = package_stack.size > 0 ? package_stack[package_stack.size - 1].name + "." : "";
            foreach (var p in siblings) {
                if (p.name == pkg_name || (parent_prefix != "" && p.name == parent_prefix + pkg_name)) {
                    pkg = p;
                    break;
                }
            }
            if (pkg == null && !quoted && ns_separator == "." && pkg_name.contains(".") && package_stack.size == 0) {
                // "package a.b" draws as package b inside package a (PlantUML 1.2026)
                pkg = ensure_package_path(pkg_name, line);
            }
            if (pkg == null) {
                pkg = new ClassPackage(pkg_name, line);
                if (package_stack.size > 0) {
                    var enclosing_pkg = package_stack[package_stack.size - 1];
                    pkg.parent = enclosing_pkg;
                    enclosing_pkg.children.add(pkg);
                } else {
                    diagram.packages.add(pkg);
                }
            }
            if (color != null) {
                pkg.color = color;
            }
            if (alias != null) {
                pkg.alias = alias;
            }
            if (pkg_style != null) {
                pkg.style = pkg_style;
            }
            pkg.is_namespace = pkg.is_namespace || is_namespace;
            if (match(TokenType.LBRACE)) {
                package_stack.add(pkg);
            }
        }

        // A class declared inside an open package belongs to it (first declaration wins)
        private void add_to_open_package(UmlClass c) {
            if (package_stack.size > 0 && c.owner_package == null) {
                var pkg = package_stack[package_stack.size - 1];
                c.owner_package = pkg;
                pkg.classes.add(c);
            }
        }

        // A class first mentioned by a relationship inside a package belongs to it,
        // as in PlantUML ("package P { Object <|-- ArrayList }").
        // `reuse` is true for references: as in PlantUML, a bare name that does not exist in
        // the current namespace finds an existing class of that name elsewhere ("Foo" inside
        // namespace n links to the global Foo instead of creating n.Foo). Declarations
        // ("class Foo" inside n) always make their own class.
        private UmlClass class_in_scope(string name, int line, bool reuse = true) {
            UmlClass? found = lookup_class(name, reuse);
            if (found != null) {
                if (found.source_line == 0 && line > 0) {
                    found.source_line = line;
                }
                return found;
            }
            string full = qualify(name);
            string key = full;
            if (diagram.find_class(key) != null) {
                // The name is taken by a class of another package ("package P { class Person }
                // package Q { class Person }"): this one is keyed by its package. Both used
                // to be the same class, drawn in P only.
                string prefix = package_stack.size > 0 ? package_stack[package_stack.size - 1].name + "." : ".";
                key = prefix + full;
                int n = 2;
                while (diagram.find_class(key) != null) {
                    key = "%s%s#%d".printf(prefix, full, n++);
                }
                int dot = ns_separator == "." ? full.last_index_of(".") : -1;
                string short_name = dot >= 0 && dot < full.length - 1 ? full.substring(dot + 1) : full;
                var c = diagram.get_or_create_class(key, line);
                c.display_name = short_name;
                collision_short_names.set(c, short_name);
                place_class(c, name, full);
                add_to_open_together(c);
                return c;
            }
            var c = diagram.get_or_create_class(full, line);
            place_class(c, name, full);
            add_to_open_together(c);
            return c;
        }

        // Name of a class inside its package: "Person" for the key "P.Person" or "net.Person"
        private string short_class_name(UmlClass c) {
            if (collision_short_names.has_key(c)) {
                return collision_short_names.get(c);
            }
            if (c.owner_package != null) {
                string prefix = c.owner_package.name + ".";
                if (c.name.has_prefix(prefix) && c.name.length > prefix.length) {
                    return c.name.substring(prefix.length);
                }
            }
            return c.name;
        }

        // The existing class a name refers to, following PlantUML: a qualified name
        // ("a.b.X", ".X") names one class; a bare name is the class of that name in the
        // current package, else (for references, `reuse`) the only class of that name
        // anywhere. With several candidates a reference makes a new class in the current
        // package, as PlantUML does.
        private UmlClass? lookup_class(string name, bool reuse) {
            string full = qualify(name);
            if (ns_separator == "." && name.has_prefix(".") && !full.contains(".")) {
                // ".Name": the top-level class, even when a package class holds the bare key
                foreach (var c in diagram.classes) {
                    if (c.owner_package == null && short_class_name(c) == full) {
                        return c;
                    }
                }
            }
            if (ns_separator != "." || name.has_prefix(".") || name.contains(".")) {
                UmlClass? exact = diagram.find_class(full);
                return exact != null ? exact : resolve_existing_class(name);
            }
            if (full != name) {
                // Bare name inside a namespace: its own "ns.Name" first
                UmlClass? in_ns = diagram.find_class(full);
                if (in_ns != null) {
                    return in_ns;
                }
            } else {
                ClassPackage? scope = package_stack.size > 0 ? package_stack[package_stack.size - 1] : null;
                foreach (var c in diagram.classes) {
                    if (c.owner_package == scope && short_class_name(c) == name) {
                        return c;
                    }
                }
            }
            if (!reuse) {
                return null;
            }
            UmlClass? only = null;
            foreach (var c in diagram.classes) {
                if (short_class_name(c) == name) {
                    if (only != null) {
                        return null;
                    }
                    only = c;
                }
            }
            return only;
        }

        // A class declared or first mentioned inside an open "together" block joins its group
        private void add_to_open_together(UmlClass c) {
            if (together_groups_open.size > 0) {
                var group = together_groups_open[together_groups_open.size - 1];
                if (!group.contains(c)) {
                    group.add(c);
                }
            }
        }

        // An existing class for a dotted name whose own key does not exist: "P.A" is the A
        // declared in package P (packages don't prefix their class keys unless two share a name)
        private UmlClass? resolve_existing_class(string name) {
            if (ns_separator != "." || name.has_prefix(".")) {
                return null;
            }
            int dot = name.last_index_of(".");
            if (dot <= 0 || dot == name.length - 1) {
                return null;
            }
            var pkg = find_package_path(name.substring(0, dot));
            if (pkg == null) {
                return null;
            }
            string last = name.substring(dot + 1);
            foreach (var c in pkg.classes) {
                if (c.name == last || c.name == pkg.name + "." + last) {
                    return c;
                }
            }
            return null;
        }

        // Package for a dotted path walked from the top level ("P.Q" is Q inside P), by
        // name, alias or full dotted key
        private ClassPackage? find_package_path(string path) {
            Gee.ArrayList<ClassPackage> level = diagram.packages;
            ClassPackage? cur = null;
            foreach (string seg in path.split(".")) {
                ClassPackage? next = null;
                foreach (var p in level) {
                    if (p.name == seg || p.alias == seg || (cur != null && p.name == cur.name + "." + seg)) {
                        next = p;
                        break;
                    }
                }
                if (next == null) {
                    return null;
                }
                cur = next;
                level = next.children;
            }
            return cur;
        }

        private void parse_class_declaration(ClassType type) throws Error {
            int line = peek().line;  // Capture line number before consuming keyword
            advance(); // consume class/interface/enum keyword

            string name;
            bool name_quoted = check(TokenType.STRING);
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "$" && current + 1 < tokens.size &&
                       !tokens[current + 1].space_before && is_word_token(tokens[current + 1])) {
                // "class $C1": the "$" lexes on its own and the class vanished
                advance();
                name = "$" + advance().lexeme;
            } else if (!is_at_end() && is_word_token(peek())) {
                name = read_qualified_name(advance().lexeme);
            } else {
                throw new IOError.FAILED("Expected class name");
            }
            // "class E<T>": the class is E. The "<" stopped the declaration, so the body
            // was not read and its members were lost.
            string? generic = read_generic();

            // Handle "as Alias" — alias becomes the lookup key; quoted name becomes display label.
            // The lexer emits "as" as an AS token, so checking only for an IDENTIFIER "as"
            // never read an alias.
            UmlClass uml_class;
            if ((check(TokenType.AS) || (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "as")) &&
                current + 1 < tokens.size &&
                (is_word_token(tokens[current + 1]) || tokens[current + 1].token_type == TokenType.STRING)) {
                advance(); // consume "as"
                var alias_token = advance();
                string alias = alias_token.lexeme;
                string display_name = name;
                // "class class2 as \"Label\"": the quoted side is the label and the bare
                // name stays the key, whichever side of "as" it is on
                if (alias_token.token_type == TokenType.STRING && !name_quoted) {
                    display_name = alias;
                    alias = name;
                }
                // Registered under the alias so relationships using it resolve
                uml_class = class_in_scope(alias, line, false);
                add_to_open_together(uml_class);
                place_class(uml_class, alias, qualify(alias));
                uml_class.display_name = display_name;
                if (generic == null) {
                    generic = read_generic();
                }
            } else {
                if (check(TokenType.AS) || (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "as")) {
                    advance();  // "as" with no alias after it
                }
                uml_class = class_in_scope(name, line, false);
                add_to_open_together(uml_class);
                place_class(uml_class, name, qualify(name));
            }
            uml_class.class_type = type;
            if (generic != null) {
                uml_class.generic = generic;
            }

            if (pending_class_visibility != null) {
                uml_class.visibility_marker = pending_class_visibility;
                pending_class_visibility = null;
            }
            last_declared_class = uml_class;

            // Check for stereotype <<...>>
            if (match(TokenType.STEREOTYPE)) {
                uml_class.stereotype = previous().lexeme;
                read_custom_spot(uml_class);
            }

            parse_class_colors(uml_class);

            // "$tag" markers, used by "remove $tag" / "restore $tag"
            read_class_tags(uml_class);

            // Check for extends/implements: "extends B, C" names several parents (only
            // the first was kept)
            while (check(TokenType.EXTENDS) || check(TokenType.IMPLEMENTS)) {
                var rel_type = check(TokenType.EXTENDS) ?
                    RelationshipType.INHERITANCE : RelationshipType.IMPLEMENTATION;
                advance();

                while (check(TokenType.STRING) || (!is_at_end() && is_word_token(peek()) &&
                       !check(TokenType.EXTENDS) && !check(TokenType.IMPLEMENTS))) {
                    var parent_token = advance();
                    string parent_name = parent_token.token_type == TokenType.STRING
                        ? parent_token.lexeme : read_qualified_name(parent_token.lexeme);
                    read_generic();
                    var parent = class_in_scope(parent_name, parent_token.line);
                    var relationship = new ClassRelationship(uml_class, parent, rel_type);
                    diagram.relationships.add(relationship);
                    if (check(TokenType.IDENTIFIER) && peek().lexeme == ",") {
                        advance();
                    } else {
                        break;
                    }
                }
            }
            // A stereotype written after the parents
            if (uml_class.stereotype == null && match(TokenType.STEREOTYPE)) {
                uml_class.stereotype = previous().lexeme;
                read_custom_spot(uml_class);
            }

            // Check for class body
            if (match(TokenType.LBRACE)) {
                parse_class_body(uml_class);
            }

            expect_end_of_statement();
        }

        // "<< (S,#FF7700) Singleton >>": a custom spot letter and colour before the text
        private static void read_custom_spot(UmlClass c) {
            string s = c.stereotype.strip();
            if (!s.has_prefix("(")) {
                return;
            }
            int close = s.index_of(")");
            if (close < 0) {
                return;
            }
            string[] parts = s.substring(1, close - 1).split(",", 2);
            string letter = parts[0].strip();
            if (letter.length == 0) {
                return;
            }
            c.spot_letter = letter;
            if (parts.length > 1 && parts[1].strip().length > 0) {
                string color = parts[1].strip();
                c.spot_color = color.has_prefix("#") ? color : "#" + color;
            }
        }

        // "<T>" / "<K, V>" written right after a class name; null when there is none
        private string? read_generic() {
            if (!check(TokenType.IDENTIFIER) || peek().lexeme != "<" || peek().space_before) {
                return null;
            }
            int start = current;
            advance();
            var sb = new StringBuilder();
            int depth = 1;
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (t.lexeme == "<") {
                    depth++;
                } else if (t.lexeme == ">") {
                    depth--;
                    if (depth == 0) {
                        return sb.str.strip();
                    }
                }
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }
            current = start;  // no closing ">"
            return null;
        }

        // Colour spec after a class declaration: "#pink", "#back:pink;line:red;line.dashed;text:blue",
        // "#pink;line:red", and the border form "##[dashed]blue". Only the first "#..." token was
        // taken, so "#back:pink" gave the fill "back" (black) and the rest of the line, with the
        // body's "{", was skipped.
        private void parse_class_colors(UmlClass c) {
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                string first = advance().lexeme;
                string key = first.substring(1).down();
                if ((key == "back" || key == "line" || key == "text") && check(TokenType.COLON) &&
                    !peek().space_before) {
                    apply_color_item(c, key);
                } else if (key == "line" && check(TokenType.IDENTIFIER) && peek().lexeme == "." &&
                           !peek().space_before) {
                    apply_color_item(c, key);
                } else {
                    c.color = first;
                }
                while (check(TokenType.SEMICOLON) && !peek().space_before && current + 1 < tokens.size &&
                       is_word_token(tokens[current + 1]) && !tokens[current + 1].space_before) {
                    advance();
                    apply_color_item(c, advance().lexeme.down());
                }
            } else if (match(TokenType.HASH)) {
                c.color = parse_color();
            }
            // "##blue" / "##[dashed]blue" / "##[bold]": border colour and style
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "#" && current + 1 < tokens.size &&
                !tokens[current + 1].space_before && tokens[current + 1].lexeme.has_prefix("#")) {
                advance();
                Token second = advance();
                if (second.lexeme.length > 1) {
                    c.line_color = second.lexeme;
                } else {
                    if (check(TokenType.LBRACKET) && !peek().space_before) {
                        advance();
                        while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                            string style = advance().lexeme.down();
                            if (style == "dashed" || style == "dotted" || style == "bold") {
                                c.line_style = style;
                            }
                        }
                        match(TokenType.RBRACKET);
                    }
                    if (check(TokenType.IDENTIFIER) && !peek().space_before && is_word_token(peek())) {
                        c.line_color = "#" + advance().lexeme;
                    } else if (check(TokenType.IDENTIFIER) && !peek().space_before &&
                               peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                        c.line_color = advance().lexeme;
                    }
                }
            }
        }

        // One "key:value" item of a colour spec, the key already read: back / line / text,
        // or "line.dashed" / "line.dotted" / "line.bold"
        private void apply_color_item(UmlClass c, string key) {
            if (key == "line" && check(TokenType.IDENTIFIER) && peek().lexeme == "." && !peek().space_before &&
                current + 1 < tokens.size && !tokens[current + 1].space_before) {
                advance();
                string style = advance().lexeme.down();
                if (style == "dashed" || style == "dotted" || style == "bold") {
                    c.line_style = style;
                }
                return;
            }
            if (!check(TokenType.COLON) || peek().space_before || current + 1 >= tokens.size ||
                tokens[current + 1].space_before || tokens[current + 1].token_type != TokenType.IDENTIFIER) {
                return;
            }
            advance();  // ':'
            string value = advance().lexeme;
            if (!value.has_prefix("#")) {
                value = "#" + value;
            }
            switch (key) {
                case "back": c.color = value; break;
                case "line": c.line_color = value; break;
                case "text": c.text_color = value; break;
                default: break;
            }
        }

        private string parse_color() {
            // Colors can be: named (LightBlue) or hex (1e1e1e, ABC123)
            // Hex colors starting with digits will be tokenized as IDENTIFIER since they include letters
            var sb = new StringBuilder();
            sb.append("#");

            // Collect color tokens until we hit a newline, brace, or other structural element
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !check(TokenType.RBRACE) &&
                   !check(TokenType.EXTENDS) && !check(TokenType.IMPLEMENTS) && !is_at_end()) {
                Token t = peek();
                // Stop at keywords that shouldn't be part of color
                if (t.token_type == TokenType.CLASS || t.token_type == TokenType.INTERFACE ||
                    t.token_type == TokenType.ABSTRACT || t.token_type == TokenType.ENUM) {
                    break;
                }
                // Only collect identifiers as part of color
                if (t.token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }

            return sb.str;
        }

        private void parse_note() {
            int line = peek().line;
            advance(); // consume 'note' keyword

            string position = "right";
            string? attached_to = null;
            int before_position = current;

            // Parse position: left, right, top, bottom
            // The lexer emits these as dedicated token types, not IDENTIFIER
            if (check(TokenType.LEFT)) {
                position = "left";
                advance();
            } else if (check(TokenType.RIGHT)) {
                position = "right";
                advance();
            } else if (check(TokenType.TOP)) {
                position = "top";
                advance();
            } else if (check(TokenType.BOTTOM)) {
                position = "bottom";
                advance();
            } else if (check(TokenType.IDENTIFIER)) {
                string pos = peek().lexeme.down();
                if (pos == "left" || pos == "right" || pos == "top" || pos == "bottom") {
                    position = pos;
                    advance();
                }
            }
            bool position_given = current != before_position;

            // Check for 'of' keyword
            // "of" lexes as the OF keyword; checking only IDENTIFIER left "of X" in the
            // note text and the note unattached.
            ClassRelationship? on_link = null;
            bool link_note = false;
            if (check(TokenType.OF) || (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "of")) {
                advance(); // consume 'of'

                // The class this note is attached to: "Foo", "\"Foo\"", "net.dummy.Person" or
                // "Foo::member". Only one token was read, so a dotted target left ". dummy ..."
                // on the line and the note body ran on to "end note", past @enduml.
                if (check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                } else if (!is_at_end() && (is_word_token(peek()) || (peek().lexeme == "." && !check(TokenType.NEWLINE)))) {
                    attached_to = read_qualified_name(advance().lexeme);
                }
                skip_member_suffix();
                if (attached_to != null) {
                    // Keyed as the class is: inside "namespace net.dummy" the note on
                    // "Person" belongs to net.dummy.Person
                    var target = lookup_class(attached_to, true);
                    if (target != null) {
                        attached_to = target.name;
                    }
                }
            } else if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "on" && current + 1 < tokens.size &&
                       tokens[current + 1].lexeme.down() == "link") {
                // "note on link": a note by the relationship written just before it
                advance();
                advance();
                link_note = true;
                if (diagram.relationships.size > 0) {
                    on_link = diagram.relationships[diagram.relationships.size - 1];
                }
            } else if (position_given && last_declared_class != null &&
                       (check(TokenType.COLON) || check(TokenType.NEWLINE) ||
                        (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#")))) {
                // "class Foo" / "note left: text": PlantUML attaches it to the last class
                // declared. It was drawn as an unattached note.
                attached_to = last_declared_class.name;
            }

            // note "text" as N1 / note as N1 ... end note: a floating note that links refer to
            // by alias. Without a colon the one-line form took the multi-line path and
            // swallowed the rest of the file as note text.
            string? alias = null;
            string note_text = "";
            bool single_line = false;
            if (attached_to == null && !link_note && check(TokenType.STRING) && current + 1 < tokens.size &&
                tokens[current + 1].token_type == TokenType.AS) {
                note_text = advance().lexeme;
                advance();  // as
                if (!is_at_end() && is_word_token(peek())) {
                    alias = advance().lexeme;
                }
                single_line = true;
            } else if (attached_to == null && !link_note && check(TokenType.AS)) {
                advance();
                if (!is_at_end() && is_word_token(peek())) {
                    alias = advance().lexeme;
                }
            }

            // "note left of Foo #pink" / "#blue\9932CC": the note's fill. It was kept as
            // the first line of the note text.
            string? note_color = null;
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                note_color = advance().lexeme;
            }

            // Check for colon and note text
            if (single_line) {
                expect_end_of_statement();
            } else if (match(TokenType.COLON)) {
                note_text = consume_rest_of_line();
            } else {
                // Multi-line note: note left of Class\n...text...\nend note
                skip_newlines();
                var sb = new StringBuilder();
                // Only "end note" ends the body — a bare "end" is prose. An unclosed note
                // stops at @enduml instead of taking the rest of the file.
                while (!is_at_end() && !check(TokenType.ENDUML) && !(check(TokenType.END) && check_next(TokenType.NOTE))) {
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) {
                            sb.append("\n");
                        }
                        advance();
                    } else {
                        Token t = advance();
                        if (sb.len > 0 && t.space_before && sb.str[sb.len - 1] != '\n') {
                            sb.append(" ");
                        }
                        sb.append(t.lexeme);
                    }
                }
                note_text = sb.str.strip();

                // Consume 'end note' if present
                if (check(TokenType.END) && check_next(TokenType.NOTE)) {
                    advance();  // 'end'
                    advance();  // 'note'
                }
            }

            if (note_text.length > 0) {
                var note = new ClassNote(note_text, line);
                note.position = position;
                note.attached_to = attached_to;
                note.alias = alias;
                note.color = note_color;
                note.on_link = on_link;
                if (alias != null) {
                    note_aliases.set(alias, note);
                }
                diagram.notes.add(note);
            }
        }

        private void parse_class_body(UmlClass uml_class) {
            skip_newlines();

            while (!check(TokenType.RBRACE) && !check(TokenType.ENDUML) && !is_at_end()) {
                int pos_before = current;

                // "-- title --", "..", "==", "__": a separator line. These lines were dropped.
                string? separator = separator_at_line_start();
                if (separator != null) {
                    string title = consume_member_text();
                    var sep = new ClassMember(trim_separator(title, separator[0]), false);
                    sep.separator = separator;
                    uml_class.add_member(sep);
                    skip_newlines();
                    continue;
                }

                parse_member(uml_class);

                // Safety: if no tokens consumed in this iteration, skip to next line
                if (current == pos_before) {
                    skip_to_end_of_line();
                    if (!check(TokenType.RBRACE) && !check(TokenType.ENDUML) && !is_at_end()) {
                        advance();
                    }
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        // One member line, in a class body or after "ClassName :". Stops at the end of the
        // line (or a body's closing brace).
        private void parse_member(UmlClass uml_class) {
            MemberVisibility visibility = MemberVisibility.PUBLIC;
            bool visibility_explicit = false;
            bool is_static = false;
            bool is_abstract = false;
            // "{field}" / "{method}": the compartment, whatever the text looks like
            bool force_field = false;
            bool force_method = false;
            string? lead_name = null;

            // Modifiers and the visibility marker, in either order ("{static} + get()")
            bool progress = true;
            while (progress && lead_name == null) {
                progress = false;
                if (!visibility_explicit) {
                    // "-o : Point" / "-* : int": the lexer reads "-o" and "-*" as arrows and the
                    // member was dropped. The "-" is the visibility, the rest starts the name.
                    if ((check(TokenType.AGGREGATION) && peek().lexeme == "-o") ||
                        (check(TokenType.COMPOSITION) && peek().lexeme == "-*")) {
                        lead_name = advance().lexeme.substring(1);
                        visibility = MemberVisibility.PRIVATE;
                        visibility_explicit = true;
                        break;
                    } else if (match(TokenType.PLUS)) {
                        visibility = MemberVisibility.PUBLIC;
                        visibility_explicit = true;
                    } else if (match(TokenType.MINUS)) {
                        visibility = MemberVisibility.PRIVATE;
                        visibility_explicit = true;
                    } else if (match(TokenType.HASH)) {
                        visibility = MemberVisibility.PROTECTED;
                        visibility_explicit = true;
                    } else if (check(TokenType.IDENTIFIER) && peek().lexeme == "#") {
                        advance();
                        visibility = MemberVisibility.PROTECTED;
                        visibility_explicit = true;
                    } else if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                        // "#x : int" lexes as one colour-like token "#x"
                        lead_name = advance().lexeme.substring(1);
                        visibility = MemberVisibility.PROTECTED;
                        visibility_explicit = true;
                        break;
                    } else if (match(TokenType.TILDE)) {
                        visibility = MemberVisibility.PACKAGE;
                        visibility_explicit = true;
                    }
                    if (visibility_explicit) {
                        progress = true;
                        continue;
                    }
                }
                // Check for modifiers: {static}, {classifier}, {abstract}, {field}, {method}
                if (check(TokenType.LBRACE) && current + 2 < tokens.size &&
                    tokens[current + 2].token_type == TokenType.RBRACE) {
                    string modifier = tokens[current + 1].lexeme.down();
                    switch (modifier) {
                        case "static":
                        case "classifier": is_static = true; break;
                        case "abstract": is_abstract = true; break;
                        case "field": force_field = true; break;
                        case "method": force_method = true; break;
                        default: break;  // other "{x}" modifiers are dropped, as before
                    }
                    advance();
                    advance();
                    advance();
                    progress = true;
                }
            }
            // "* id : int": mandatory entity attribute. The line was dropped.
            bool mandatory = lead_name == null && match(TokenType.MULT);
            // "+* : int": a member named "*", not a mandatory attribute
            if (mandatory && !check(TokenType.IDENTIFIER) && !check(TokenType.LBRACE) &&
                !check(TokenType.ABSTRACT) && !check(TokenType.CLASS) && !check(TokenType.INTERFACE) &&
                !check(TokenType.ENUM) && !check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                lead_name = "*";
                mandatory = false;
            }

            // Get member name and check if it's a method. Any word starts one: members
            // named like a keyword ("note : String", "+end()", "object : Obj") or quoted
            // ("\"quoted\" : int") were dropped.
            if (lead_name != null || (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) &&
                                      !check(TokenType.ENDUML) && !is_at_end())) {
                string member_text;
                if (lead_name != null) {
                    bool spaced = !check(TokenType.NEWLINE) && !check(TokenType.RBRACE) &&
                                  !is_at_end() && peek().space_before;
                    string rest = consume_member_text();
                    member_text = rest.length == 0 ? lead_name : lead_name + (spaced ? " " : "") + rest;
                } else {
                    member_text = consume_member_text();
                }
                if (member_text.length == 0 && !is_static && !is_abstract) {
                    return;
                }
                bool is_method = force_method || (!force_field && member_text.contains("("));
                if (trailing_field) {
                    is_method = false;
                } else if (trailing_method) {
                    is_method = true;
                }

                var member = new ClassMember(member_text, is_method);
                member.visibility = visibility;
                member.visibility_explicit = visibility_explicit;
                member.mandatory = mandatory;
                member.is_static = is_static || trailing_static;
                member.is_abstract = is_abstract || trailing_abstract;
                uml_class.add_member(member);
            }
        }

        // Separator kind ("--", "..", "==", "__") when the body line at the cursor is one
        private string? separator_at_line_start() {
            if (is_at_end() || check(TokenType.NEWLINE)) {
                return null;
            }
            string lex = peek().lexeme;
            foreach (string ch in new string[] { "-", ".", "=", "_" }) {
                if (lex.length == 0 || lex.replace(ch, "").length != 0) {
                    continue;
                }
                // "=" lexes one character at a time: "==" is two adjacent tokens
                if (lex.length >= 2) {
                    return ch + ch;
                }
                if (current + 1 < tokens.size && tokens[current + 1].lexeme.has_prefix(ch) &&
                    tokens[current + 1].lexeme.replace(ch, "").length == 0 && !tokens[current + 1].space_before) {
                    return ch + ch;
                }
            }
            return null;
        }

        // "-- title --" -> "title"
        private static string trim_separator(string text, char ch) {
            int start = 0;
            int end = text.length;
            while (start < end && (text[start] == ch || text[start] == ' ')) {
                start++;
            }
            while (end > start && (text[end - 1] == ch || text[end - 1] == ' ')) {
                end--;
            }
            return text.substring(start, end - start);
        }

        // Set by consume_member_text() when a member line carries a trailing
        // modifier ("+ one() {static}").
        private bool trailing_static = false;
        private bool trailing_abstract = false;
        private bool trailing_field = false;
        private bool trailing_method = false;

        private string consume_member_text() {
            var sb = new StringBuilder();
            trailing_static = false;
            trailing_abstract = false;
            trailing_field = false;
            trailing_method = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                // A trailing {static}/{abstract}: consume it as a modifier. Its "}" used
                // to stop this loop and was then taken as the end of the class body,
                // silently dropping every member after it.
                if (check(TokenType.LBRACE) && current + 2 < tokens.size &&
                    tokens[current + 2].token_type == TokenType.RBRACE) {
                    string modifier = tokens[current + 1].lexeme.down();
                    if (modifier == "static" || modifier == "classifier" || modifier == "abstract" ||
                        modifier == "field" || modifier == "method") {
                        if (modifier == "abstract") {
                            trailing_abstract = true;
                        } else if (modifier == "field") {
                            trailing_field = true;
                        } else if (modifier == "method") {
                            trailing_method = true;
                        } else {
                            trailing_static = true;
                        }
                        advance();
                        advance();
                        advance();
                        continue;
                    }
                }
                // "\~Dummy()": a backslash escapes the next character and is not shown
                if (check(TokenType.IDENTIFIER) && peek().lexeme == "\\" && current + 1 < tokens.size &&
                    !tokens[current + 1].space_before && tokens[current + 1].token_type != TokenType.NEWLINE &&
                    tokens[current + 1].token_type != TokenType.EOF) {
                    bool spaced = peek().space_before;
                    advance();
                    Token escaped = advance();
                    if (sb.len > 0 && spaced) {
                        sb.append(" ");
                    }
                    sb.append(escaped.lexeme);
                    continue;
                }
                Token t = advance();
                // A quoted part keeps its quotes, as PlantUML shows it ("\"quoted\" : int")
                string lex = t.token_type == TokenType.STRING ? "\"" + t.lexeme + "\"" : t.lexeme;
                // Keep the source's own spacing: guessing from the punctuation
                // turned "Result<void>" into "Result < void >".
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(lex);
            }

            return sb.str.strip();
        }

        private void parse_relationship_or_class() {
            // Get first class (or package) name
            string from_name;
            int from_line;
            if (check(TokenType.STRING)) {
                var token = advance();
                from_name = token.lexeme;
                from_line = token.line;
            } else {
                var token = advance();
                from_name = read_qualified_name(token.lexeme);
                from_line = token.line;
            }
            skip_member_suffix();

            // A floating note's alias ("N1 .. A") links the note instead of making a class box
            ClassNote? from_note = null;
            if (note_aliases.has_key(from_name)) {
                from_note = note_aliases.get(from_name);
            }
            ClassPackage? from_pkg = null;
            UmlClass? from_class = null;
            if (from_note == null) {
                from_pkg = package_endpoint(from_name);
                if (from_pkg == null) {
                    from_class = class_in_scope(from_name, from_line);
                }
            }

            // "Object : equals()": a member added to the class. The line was dropped.
            if (from_class != null && check(TokenType.COLON) &&
                (current + 1 >= tokens.size || tokens[current + 1].token_type != TokenType.COLON)) {
                advance();
                if (from_class.source_line == 0) {
                    from_class.source_line = from_line;
                }
                parse_member(from_class);
                expect_end_of_statement();
                return;
            }

            // "bar ()- foo": bar is a lollipop interface (a small circle), not a class box
            if (from_class != null && is_lollipop_at(current)) {
                advance();
                advance();
                make_lollipop(from_class);
            }

            // Optional cardinality before the arrow: A "1" *-- "many" B
            string? from_card = null;
            if (check(TokenType.STRING) && is_link_token_at(current + 1)) {
                from_card = advance().lexeme;
            }

            // Relationship arrow, read as the text of its adjacent tokens, so every
            // PlantUML form works: -- .. --> ..> <|-- *- o-- -up-> -[hidden]- ...
            // Matching single tokens dropped direction arrows and made "-->" dashed.
            RelationshipType? rel_type = null;
            bool reverse = false;
            bool undirected = false;
            bool horizontal = false;
            string placement;
            string? link_style;
            string? link_color;
            last_arrow_thickness = 0;
            // "foo -() bar": a line ending in a lollipop. The "-" directly before "(" is not
            // taken as an arrow by read_arrow_text().
            bool lollipop_to = false;
            string? arrow = read_lollipop_arrow();
            if (arrow != null) {
                placement = "";
                link_style = null;
                link_color = null;
                lollipop_to = true;
            } else {
                arrow = read_arrow_text(out placement, out link_style, out link_color);
            }
            if (arrow != null) {
                horizontal = classify_arrow(arrow, out rel_type, out reverse, out undirected) && placement == "";
                if (reverse) {
                    placement = flip_placement(placement);
                }
            }

            if (rel_type != null) {
                // Optional cardinality after the arrow: ... "many" B. Without this the
                // quoted string was taken as the target and became a ghost class.
                string? to_card = null;
                if (check(TokenType.STRING) && current + 1 < tokens.size &&
                    (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                     tokens[current + 1].token_type == TokenType.STRING)) {
                    to_card = advance().lexeme;
                }

                // Get second class name
                string to_name;
                int to_line;
                if (check(TokenType.STRING)) {
                    var token = advance();
                    to_name = token.lexeme;
                    to_line = token.line;
                } else if (!is_at_end() && is_word_token(peek())) {
                    var token = advance();
                    to_name = read_qualified_name(token.lexeme);
                    to_line = token.line;
                } else {
                    expect_end_of_statement();
                    return;
                }
                skip_member_suffix();

                // "foo --> bar #red", "#line:red;line.bold;text:red": colour and style of the
                // link, written after its target. The label after them was lost.
                string? inline_line_color = null;
                string? inline_text_color = null;
                string? inline_style = null;
                read_link_colors(out inline_line_color, out inline_text_color, out inline_style);

                ClassNote? to_note = null;
                if (note_aliases.has_key(to_name)) {
                    to_note = note_aliases.get(to_name);
                }
                if (from_note != null || to_note != null) {
                    ClassNote? note = null;
                    UmlClass? other = null;
                    if (from_note != null && to_note == null) {
                        note = from_note;
                        if (package_endpoint(to_name) == null) {
                            other = class_in_scope(to_name, to_line);
                        }
                    } else if (from_note == null) {
                        note = to_note;
                        other = from_class;
                    }
                    if (note != null && other != null) {
                        note.links.add(new ClassNoteLink(other.name, arrow != null && arrow.contains("."),
                                                         from_note != null));
                    }
                    expect_end_of_statement();
                    return;
                }

                var to_pkg = package_endpoint(to_name);
                if (from_pkg != null || to_pkg != null) {
                    var link = new ClassPackageLink(rel_type);
                    link.end_marker = last_arrow_marker;
                    UmlClass? to_end_class = to_pkg == null ? class_in_scope(to_name, to_line) : null;
                    if (reverse) {
                        link.from_class = to_end_class;
                        link.from_package = to_pkg;
                        link.to_class = from_class;
                        link.to_package = from_pkg;
                    } else {
                        link.from_class = from_class;
                        link.from_package = from_pkg;
                        link.to_class = to_end_class;
                        link.to_package = to_pkg;
                    }
                    link.undirected = undirected;
                    if (match(TokenType.COLON)) {
                        link.label = consume_rest_of_line();
                    }
                    diagram.package_links.add(link);
                    expect_end_of_statement();
                    return;
                }

                var to_class = class_in_scope(to_name, to_line);

                ClassRelationship relationship;
                if (reverse) {
                    relationship = new ClassRelationship(to_class, from_class, rel_type);
                } else {
                    relationship = new ClassRelationship(from_class, to_class, rel_type);
                }

                relationship.undirected = undirected;
                relationship.horizontal = horizontal;
                relationship.text_reversed = reverse;
                relationship.end_marker = last_arrow_marker;
                relationship.ie_tail = last_ie_tail;
                relationship.ie_head = last_ie_head;
                relationship.placement = placement;
                relationship.line_style = inline_style ?? link_style;
                relationship.line_color = inline_line_color ?? link_color;
                relationship.text_color = inline_text_color;
                relationship.thickness = last_arrow_thickness;
                if (lollipop_to) {
                    make_lollipop(to_class);
                }
                relationship.from_cardinality = reverse ? to_card : from_card;
                relationship.to_cardinality = reverse ? from_card : to_card;

                // Optional label after colon
                if (match(TokenType.COLON)) {
                    relationship.label = consume_rest_of_line();
                }

                diagram.relationships.add(relationship);
            }

            expect_end_of_statement();
        }

        // "()" directly at idx: a lollipop marker
        private bool is_lollipop_at(int idx) {
            return idx + 1 < tokens.size && tokens[idx].token_type == TokenType.LPAREN &&
                   tokens[idx + 1].token_type == TokenType.RPAREN && !tokens[idx + 1].space_before;
        }

        private static void make_lollipop(UmlClass c) {
            if (c.class_type == ClassType.CLASS && c.members.size == 0 && c.stereotype == null) {
                c.class_type = ClassType.CIRCLE;
            }
        }

        // "-()" / "--()" / "..()": the line characters and the lollipop; null (cursor unchanged)
        // when the arrow at the cursor is not one
        private string? read_lollipop_arrow() {
            int i = current;
            var sb = new StringBuilder();
            while (i < tokens.size) {
                var t = tokens[i];
                if (i > current && t.space_before) {
                    break;
                }
                string lex = t.lexeme;
                if (lex.length == 0 || lex.replace("-", "").replace(".", "").length != 0 ||
                    t.token_type == TokenType.STRING) {
                    break;
                }
                sb.append(lex);
                i++;
            }
            if (sb.len == 0 || !is_lollipop_at(i) || tokens[i].space_before) {
                return null;
            }
            current = i + 2;
            return sb.str;
        }

        // Colour and style written after a link's target: "#red", "#line:red;line.bold;text:red",
        // "#green;line.dashed;text:green"
        private void read_link_colors(out string? line_color, out string? text_color, out string? style) {
            line_color = null;
            text_color = null;
            style = null;
            if (!check(TokenType.IDENTIFIER) || !peek().lexeme.has_prefix("#") || peek().lexeme.length < 2) {
                return;
            }
            bool first = true;
            while (true) {
                string key;
                if (first) {
                    key = advance().lexeme.substring(1);
                } else {
                    key = advance().lexeme;
                }
                first = false;
                string low = key.down();
                if ((low == "line" || low == "text" || low == "back") && check(TokenType.COLON) &&
                    !peek().space_before) {
                    advance();
                    string value = read_adjacent_value();
                    if (value.length > 0) {
                        if (low == "line") {
                            line_color = value.has_prefix("#") ? value : "#" + value;
                        } else if (low == "text") {
                            text_color = value.has_prefix("#") ? value : "#" + value;
                        }
                    }
                } else if (low == "line" && check(TokenType.IDENTIFIER) && peek().lexeme == "." &&
                           !peek().space_before && current + 1 < tokens.size) {
                    advance();
                    string st = advance().lexeme.down();
                    if (st == "bold" || st == "dashed" || st == "dotted") {
                        style = st;
                    } else if (st == "hidden") {
                        style = "invis";
                    }
                } else {
                    string rest = read_adjacent_value();
                    line_color = "#" + key + rest;
                }
                if (check(TokenType.SEMICOLON) && !peek().space_before && current + 1 < tokens.size &&
                    !tokens[current + 1].space_before && is_word_token(tokens[current + 1])) {
                    advance();
                    continue;
                }
                break;
            }
        }

        // Tokens directly adjacent to the cursor up to ";" / ":" (a colour value like "FF0000")
        private string read_adjacent_value() {
            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE) && !check(TokenType.SEMICOLON) &&
                   !check(TokenType.COLON) && (sb.len == 0 || !peek().space_before)) {
                if (sb.len == 0 && peek().space_before) {
                    break;
                }
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        // "(A, B) .. C" / "(A, B) . C": C is an association class on the A-B link
        private bool try_parse_association_class() {
            int start = current;
            int line = peek().line;
            advance();  // (
            string[] names = {};
            while (names.length < 2) {
                if (check(TokenType.STRING)) {
                    names += advance().lexeme;
                } else if (!is_at_end() && is_word_token(peek())) {
                    names += read_qualified_name(advance().lexeme);
                } else {
                    break;
                }
                if (names.length == 1) {
                    if (check(TokenType.IDENTIFIER) && peek().lexeme == ",") {
                        advance();
                    } else {
                        break;
                    }
                }
            }
            if (names.length != 2 || !check(TokenType.RPAREN)) {
                current = start;
                return false;
            }
            advance();  // )
            string placement;
            string? style;
            string? color;
            string? arrow = read_arrow_text(out placement, out style, out color);
            if (arrow == null || !(check(TokenType.STRING) || (!is_at_end() && is_word_token(peek())))) {
                current = start;
                return false;
            }
            var name_tok = advance();
            string cname = name_tok.token_type == TokenType.STRING
                ? name_tok.lexeme : read_qualified_name(name_tok.lexeme);
            var a = class_in_scope(names[0], line);
            var b = class_in_scope(names[1], line);
            var c = class_in_scope(cname, name_tok.line);
            ClassRelationship? rel = null;
            foreach (var r in diagram.relationships) {
                if ((r.from == a && r.to == b) || (r.from == b && r.to == a)) {
                    rel = r;
                }
            }
            if (rel == null) {
                rel = new ClassRelationship(a, b, RelationshipType.ASSOCIATION);
                rel.undirected = true;
                diagram.relationships.add(rel);
            }
            string body = arrow.replace("<", "").replace(">", "").replace("|", "");
            rel.association_classes.add(c);
            rel.association_side.add(body.length == 1);
            rel.association_dashed.add(arrow.contains("."));
            expect_end_of_statement();
            return true;
        }

        private string consume_rest_of_line() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(t.lexeme);
            }

            return sb.str.strip();
        }

        private string parse_text_content() {
            // Handle title/header/footer content
            // Can be: "text", text until end of line, or multi-line
            var sb = new StringBuilder();

            if (check(TokenType.STRING)) {
                return advance().lexeme;
            }

            // Consume rest of line
            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0 && t.space_before) {
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
                    case TokenType.CLASS:
                    case TokenType.INTERFACE:
                    case TokenType.ABSTRACT:
                    case TokenType.ENUM:
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

        // True if the current token is one of the visibility-prefix markers
        // (-, #, ~, +) and the NEXT token is a class-declaration keyword.
        // Used by the main dispatch to consume the prefix and then parse the
        // class declaration normally.
        private bool is_visibility_prefix_token() {
            if (is_at_end()) return false;
            var t = peek();
            bool is_prefix = t.token_type == TokenType.MINUS ||
                             t.token_type == TokenType.TILDE ||
                             t.token_type == TokenType.PLUS ||
                             (t.token_type == TokenType.IDENTIFIER && t.lexeme == "#");
            if (!is_prefix) return false;
            // Look at the next token
            if (current + 1 >= tokens.size) return false;
            var next = tokens[current + 1].token_type;
            return next == TokenType.CLASS ||
                   next == TokenType.INTERFACE ||
                   next == TokenType.ABSTRACT ||
                   next == TokenType.ENUM;
        }

        private bool match(TokenType type) {
            if (check(type)) {
                advance();
                return true;
            }
            return false;
        }

        /**
         * Type of the token after the current one. Needed to recognise the
         * two-token "end note" terminator without consuming a bare "end"
         * that is simply a word in the note body.
         */
        private bool check_next(TokenType type) {
            if (current + 1 >= tokens.size) {
                return false;
            }
            return tokens.get(current + 1).token_type == type;
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
