namespace GDiagram {
    public class ObjectDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private ObjectDiagram diagram;
        private Gee.ArrayList<ObjectPackage> package_stack = new Gee.ArrayList<ObjectPackage>();

        public ObjectDiagramParser() {
            this.current = 0;
        }

        public ObjectDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new ObjectDiagram();
            this.package_stack = new Gee.ArrayList<ObjectPackage>();

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

            // "legend ... endlegend": its lines became ghost objects "Key" and "endlegend"
            if (check(TokenType.LEGEND) && current + 1 < tokens.size &&
                !tokens[current + 1].lexeme.has_prefix("-") && !tokens[current + 1].lexeme.has_prefix(".")) {
                diagram.legend = ComponentDiagramParser.read_legend_block(tokens, ref current);
                return;
            }

            // left to right direction / top to bottom direction
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

            // package / namespace blocks
            if (check(TokenType.PACKAGE) || (check(TokenType.IDENTIFIER) && peek().lexeme == "namespace")) {
                parse_package();
                return;
            }
            if (check(TokenType.RBRACE) && package_stack.size > 0) {
                advance();
                package_stack.remove_at(package_stack.size - 1);
                return;
            }

            // map Name { key => value | key *-> Target }. Maps were not understood:
            // "map" and every key became separate boxes.
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "map" && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING)) {
                parse_map();
                return;
            }

            // "diamond dia": a junction point. "diamond" and "dia" became two boxes.
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "diamond" && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING) &&
                (current + 2 >= tokens.size || tokens[current + 2].token_type == TokenType.NEWLINE ||
                 tokens[current + 2].token_type == TokenType.EOF || tokens[current + 2].token_type == TokenType.ENDUML)) {
                int line = advance().line;
                string? name = read_name();
                if (name != null) {
                    touch_object(name, line, last_name_quoted).is_diamond = true;
                }
                expect_end_of_statement();
                return;
            }

            // "json Name { ... }": the JSON drawn as a table. Its keys became boxes.
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "json" && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING)) {
                parse_json_element();
                return;
            }

            // "class Name" among objects (PlantUML draws the class beside them)
            if (check(TokenType.CLASS) && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING)) {
                int line = advance().line;
                string? name = read_name();
                if (name != null) {
                    var cls = touch_object(name, line, last_name_quoted);
                    cls.is_class = true;
                    if (match(TokenType.AS) && (check(TokenType.STRING) || is_word_token(peek()))) {
                        cls.alias = advance().lexeme;
                    }
                    while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                        advance();
                    }
                    if (match(TokenType.LBRACE)) {
                        parse_object_body(cls);
                    }
                }
                expect_end_of_statement();
                return;
            }

            // Object declaration
            if (check(TokenType.OBJECT)) {
                parse_object_declaration();
                return;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Title, header, footer
            if (match(TokenType.TITLE)) {
                diagram.title = consume_rest_of_line();
                return;
            }
            if (match(TokenType.HEADER)) {
                diagram.header = consume_rest_of_line();
                return;
            }
            if (match(TokenType.FOOTER)) {
                diagram.footer = consume_rest_of_line();
                return;
            }

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Output scaling (scale 2, scale max 800 width) - not an object
            if (match(TokenType.SCALE)) {
                skip_to_end_of_line();
                return;
            }

            // Link or identifier reference (object Name or Name --> Name2). A keyword
            // word ("node", "edge") that names a known object starts a link too.
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) ||
                (is_word_token(peek()) && diagram.find_object(peek().lexeme) != null)) {
                parse_link_or_object();
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        private void parse_object_declaration() throws Error {
            int line = advance().line;  // consume "object"

            string? name = read_name();
            if (name == null) {
                throw new IOError.FAILED("Expected object name");
            }

            var obj = touch_object(name, line, last_name_quoted);

            // Check for "as Alias". Keyword words are aliases too: "as node" used to
            // be dropped because "node" lexes as a keyword token.
            if (match(TokenType.AS)) {
                if (check(TokenType.STRING) || is_word_token(peek())) {
                    obj.alias = advance().lexeme;
                }
            }

            // Check for stereotype <<...>>
            if (match(TokenType.STEREOTYPE)) {
                obj.stereotype = previous().lexeme;
            }

            // Check for color ("#pink" lexes as one IDENTIFIER token)
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#")) {
                obj.color = advance().lexeme;
            } else if (match(TokenType.HASH)) {
                obj.color = parse_color();
            }

            // Check for object body with fields
            if (match(TokenType.LBRACE)) {
                parse_object_body(obj);
            }

            expect_end_of_statement();
        }

        // json Name [as Alias] { json text }
        private void parse_json_element() {
            int line = advance().line;  // "json"
            string? name = read_name();
            if (name == null) {
                expect_end_of_statement();
                return;
            }
            var obj = touch_object(name, line, last_name_quoted);
            if (match(TokenType.AS)) {
                string? alias = read_name();
                if (alias != null) {
                    obj.alias = alias;
                }
            }
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                advance();
            }
            if (!check(TokenType.LBRACE)) {
                expect_end_of_statement();
                return;
            }
            // The JSON text back from its tokens, up to the matching "}"
            var text = new StringBuilder();
            int depth = 0;
            while (!is_at_end() && !check(TokenType.ENDUML)) {
                Token t = advance();
                if (t.token_type == TokenType.LBRACE) {
                    depth++;
                } else if (t.token_type == TokenType.RBRACE) {
                    depth--;
                }
                if (t.token_type == TokenType.NEWLINE) {
                    text.append("\n");
                } else if (t.token_type == TokenType.STRING) {
                    text.append(" \"%s\"".printf(t.lexeme));
                } else {
                    if (t.space_before) {
                        text.append(" ");
                    }
                    text.append(t.lexeme);
                }
                if (depth == 0) {
                    break;
                }
            }
            obj.json_root = JsonDiagramParser.parse_text(text.str);
            if (obj.json_root == null) {
                obj.json_root = new JsonNode(JsonNodeType.OBJECT);
            }
        }

        private void parse_object_body(ObjectInstance obj) {
            skip_newlines();

            // Also stop on ENDUML so an unclosed `{` at the top level
            // doesn't spin forever parsing past the diagram end.
            while (!check(TokenType.RBRACE)
                   && !check(TokenType.ENDUML)
                   && !is_at_end()) {
                int start_pos = current;

                // Field line, kept as written ("name = \"Dummy\"", "label : text", "just text").
                // "=" lexes as an identifier, so matching an EQUALS token never fired and the
                // renderer's own " = " doubled it; quotes were lost and "\"q\" = 1" dropped.
                if (!check(TokenType.NEWLINE)) {
                    add_field_line(obj, consume_line_as_written());
                }

                skip_newlines();

                // Safety net: if nothing in this iteration advanced the
                // cursor, bail out rather than spin forever on an
                // unrecognized token.
                if (current == start_pos) {
                    break;
                }
            }

            match(TokenType.RBRACE);
        }

        // One field row: split at its first "=" or ":" into name and value, shown as written
        private static void add_field_line(ObjectInstance obj, string line) {
            if (line.length == 0) {
                return;
            }
            int eq = line.index_of("=");
            int colon = line.index_of(":");
            int pos = eq > 0 && (colon <= 0 || eq < colon) ? eq : colon;
            ObjectField field;
            if (pos > 0) {
                field = new ObjectField(line.substring(0, pos).strip(), line.substring(pos + 1).strip());
            } else {
                field = new ObjectField(line, "");
            }
            field.text = line;
            obj.fields.add(field);
        }

        // Rest of the line in the source's spacing, quoted strings with their quotes. Stops
        // at a "}" closing an object body.
        private string consume_line_as_written() {
            var sb = new StringBuilder();
            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !check(TokenType.ENDUML) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(t.token_type == TokenType.STRING ? "\"" + t.lexeme + "\"" : t.lexeme);
            }
            return sb.str.strip();
        }

        private void parse_link_or_object() {
            int from_line = peek().line;
            string? from_row;
            string? from_name = read_endpoint(out from_row);
            if (from_name == null) {
                advance();
                return;
            }
            bool from_quoted = last_name_quoted;

            // Object field assignment: ObjectName : field = value
            if (from_row == null && match(TokenType.COLON)) {
                var obj = touch_object(from_name, from_line, from_quoted);
                string rest = consume_line_as_written();
                skip_to_end_of_line();
                if (rest.index_of("=") > 0) {
                    add_field_line(obj, rest);
                }
                return;
            }

            // Optional cardinality before the arrow: A "1" *-- "many" B
            string? from_card = null;
            if (check(TokenType.STRING) && arrow_piece_at(current + 1, true)) {
                from_card = advance().lexeme;
            }

            string? arrow = read_arrow();
            if (arrow == null) {
                // Just a reference - make sure the object exists
                if (from_row == null && diagram.find_package(from_name) == null) {
                    resolve_endpoint(from_name, from_line, from_quoted);
                }
                expect_end_of_statement();
                return;
            }

            string? to_card = null;
            if (check(TokenType.STRING) && current + 1 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER ||
                 tokens[current + 1].token_type == TokenType.STRING)) {
                to_card = advance().lexeme;
            }

            int to_line = peek().line;
            string? to_row;
            string? to_name = read_endpoint(out to_row);
            if (to_name == null) {
                expect_end_of_statement();
                return;
            }
            add_link(from_name, from_row, from_line, from_quoted, to_name, to_row, to_line, last_name_quoted,
                     arrow, from_card, to_card);
            expect_end_of_statement();
        }

        // Whether the name read last by read_name() was a quoted string
        private bool last_name_quoted = false;

        // A word: identifier or keyword token ("node", "edge" lex as keywords)
        private static bool is_word_token(Token t) {
            return t.token_type != TokenType.STRING && t.token_type != TokenType.NEWLINE &&
                   t.token_type != TokenType.EOF && t.lexeme.length > 0 &&
                   (t.lexeme.get_char(0).isalnum() || t.lexeme[0] == '_');
        }

        // An object or map name: a quoted string, or a word with dots joined ("task.1")
        private string? read_name() {
            last_name_quoted = false;
            if (check(TokenType.STRING)) {
                last_name_quoted = true;
                return advance().lexeme;
            }
            if (!check(TokenType.IDENTIFIER) && !(!is_at_end() && is_word_token(peek()))) {
                return null;
            }
            var sb = new StringBuilder(advance().lexeme);
            while (check(TokenType.IDENTIFIER) && peek().lexeme == "." && !peek().space_before &&
                   current + 1 < tokens.size && !tokens[current + 1].space_before &&
                   tokens[current + 1].lexeme.length > 0 && tokens[current + 1].lexeme.get_char(0).isalnum()) {
                advance();
                sb.append(".");
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        // "Name", "pkg.Name" or "Map::key" (the key comes back in `row`)
        private string? read_endpoint(out string? row) {
            row = null;
            string? name = read_name();
            if (name == null) {
                return null;
            }
            if (check(TokenType.COLON) && !peek().space_before && current + 2 < tokens.size &&
                tokens[current + 1].token_type == TokenType.COLON && !tokens[current + 1].space_before &&
                !tokens[current + 2].space_before && tokens[current + 2].token_type != TokenType.NEWLINE) {
                advance();
                advance();
                row = advance().lexeme;
            }
            return name;
        }

        private ObjectInstance touch_object(string name, int line, bool quoted = false) {
            bool is_new = diagram.find_object(name) == null;
            var obj = diagram.get_or_create_object(name, line);
            if (is_new) {
                int dot = name.last_index_of(".");
                // Only an unquoted dotted name nests: "a.b" in quotes is a plain
                // top-level object (it used to land in a package "a")
                if (!quoted && package_stack.size == 0 && dot > 0 && dot < name.length - 1 && !name.contains(" ")) {
                    // "task.1" is object "task.1" inside package "task" (PlantUML 1.2026)
                    var pkg = ensure_package_path(name.substring(0, dot));
                    obj.owner_package = pkg;
                    pkg.objects.add(obj);
                } else {
                    add_to_open_package(obj);
                }
            }
            return obj;
        }

        // "a.b" as nested top-level packages a > b, labelled with their last segment
        private ObjectPackage ensure_package_path(string full) {
            ObjectPackage? parent = null;
            string path = "";
            foreach (string part in full.split(".")) {
                if (part.length == 0) {
                    continue;
                }
                path = path.length > 0 ? path + "." + part : part;
                var pkg = diagram.find_package(path);
                if (pkg == null) {
                    pkg = new ObjectPackage(path);
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

        // A floating note's alias ("note "text" as N1"), so "Foo .. N1" links the note
        private bool is_note_alias(string name) {
            foreach (var note in diagram.notes) {
                if (note.alias == name) return true;
            }
            return false;
        }

        private void add_to_open_package(ObjectInstance obj) {
            if (package_stack.size > 0 && obj.owner_package == null) {
                var pkg = package_stack[package_stack.size - 1];
                obj.owner_package = pkg;
                pkg.objects.add(obj);
            }
        }

        // The name a link end refers to: an object, a package, or "pkg.Name" for
        // object Name inside package pkg. Anything else is created as an object.
        private string resolve_endpoint(string name, int line, bool quoted = false) {
            if (diagram.find_object(name) != null || diagram.find_package(name) != null || is_note_alias(name)) {
                return name;
            }
            int dot = name.last_index_of(".");
            if (dot > 0) {
                var pkg = diagram.find_package(name.substring(0, dot));
                string short_name = name.substring(dot + 1);
                if (pkg != null) {
                    foreach (var o in pkg.objects) {
                        if (o.name == short_name || o.alias == short_name) {
                            return o.alias ?? o.name;
                        }
                    }
                }
            }
            touch_object(name, line, quoted);
            return name;
        }

        private void add_link(string from_name, string? from_row, int from_line, bool from_quoted,
                              string to_name, string? to_row, int to_line, bool to_quoted,
                              string arrow, string? from_card, string? to_card) {
            ObjectLinkType type;
            bool reverse;
            bool undirected;
            bool dashed;
            bool head;
            classify_arrow(arrow, out type, out reverse, out undirected, out dashed, out head);
            string from_ref = resolve_endpoint(from_name, from_line, from_quoted);
            string to_ref = resolve_endpoint(to_name, to_line, to_quoted);
            var link = reverse ? new ObjectLink(to_ref, from_ref, type) : new ObjectLink(from_ref, to_ref, type);
            link.from_row = reverse ? to_row : from_row;
            link.to_row = reverse ? from_row : to_row;
            link.from_cardinality = reverse ? to_card : from_card;
            link.to_cardinality = reverse ? from_card : to_card;
            link.is_dashed = dashed;
            link.undirected = undirected;
            link.has_head = head;
            link.text_reversed = reverse;
            link.end_marker = last_marker;
            link.has_tail_head = last_both_heads;
            link.line_color = last_arrow_color;
            link.line_style = last_arrow_style;
            if (match(TokenType.COLON)) {
                link.label = consume_rest_of_line();
            }
            diagram.links.add(link);
        }

        private const string ARROW_CHARS = "-.<>|*o#x+^";
        private string? last_marker = null;  // aggregation marker of the last classified arrow
        private bool last_both_heads = false;  // last classified arrow was "<-->" / "<..>"
        private string? last_arrow_color = null;  // "-[#red]->" options of the last arrow read
        private string? last_arrow_style = null;

        // A token that can be part of an arrow. The first piece must hold a line
        // character itself, or be a marker ("*", "o") directly followed by one.
        private bool arrow_piece_at(int idx, bool first) {
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
            return idx + 1 < tokens.size && !tokens[idx + 1].space_before &&
                   (tokens[idx + 1].lexeme.has_prefix("-") || tokens[idx + 1].lexeme.has_prefix("."));
        }

        private static bool is_direction_word(string w) {
            switch (w.down()) {
                case "u": case "up": case "d": case "do": case "down":
                case "l": case "le": case "left": case "r": case "ri": case "right":
                    return true;
                default:
                    return false;
            }
        }

        // Reads an arrow ("-->", "*->", "<|--", "-up->") from its adjacent tokens.
        // Only fixed tokens were recognised before, so "..>", "<|--" and map row
        // arrows were dropped. Returns null (cursor unchanged) when there is none.
        private string? read_arrow() {
            last_arrow_color = null;
            last_arrow_style = null;
            if (!arrow_piece_at(current, true)) {
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
                if (tail.has_suffix(">") && t.lexeme != ">") {
                    break;
                }
                bool in_body = tail.has_suffix("-") || tail.has_suffix(".");
                if (arrow_piece_at(current, first)) {
                    advance();
                    sb.append(t.lexeme);
                } else if (in_body && is_direction_word(t.lexeme)) {
                    advance();
                } else if (in_body && t.token_type == TokenType.LBRACKET) {
                    // "-[#red]->", "-[dashed]->", "-[hidden]-": the whole link used
                    // to be dropped at the "["
                    advance();
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        string opt = advance().lexeme;
                        string low = opt.down();
                        if (low == "hidden") {
                            last_arrow_style = "invis";
                        } else if (low == "dashed" || low == "dotted" || low == "bold") {
                            last_arrow_style = low;
                        } else if (opt.has_prefix("#") && opt.length > 1) {
                            last_arrow_color = opt;
                        }
                    }
                    match(TokenType.RBRACKET);
                } else {
                    break;
                }
                first = false;
            }
            string text = sb.str;
            bool lone = text == "-" || text == ".";
            if (!(text.contains("-") || text.contains(".")) ||
                (lone && !is_at_end() && !check(TokenType.NEWLINE) && !peek().space_before)) {
                current = start;
                last_arrow_color = null;
                last_arrow_style = null;
                return null;
            }
            return text;
        }

        // Link type from arrow text. Markers at the start belong to the source end:
        // "*--" keeps the order (diamond at the whole), "--*" and "<|--" reverse it.
        private void classify_arrow(string arrow, out ObjectLinkType type, out bool reverse, out bool undirected,
                                    out bool dashed, out bool head) {
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
            last_marker = null;
            dashed = body.contains(".");
            reverse = false;
            undirected = false;
            head = right == ">" || right == ">>" || left == "<" || left == "<<";
            // "<-->" has a head at both ends; it used to lose the one at the source
            last_both_heads = (left == "<" || left == "<<") && (right == ">" || right == ">>");
            if (left == "<|" || right == "|>") {
                type = ObjectLinkType.INHERITANCE;
                reverse = left == "<|";
                head = true;
            } else if (left == "*" || right == "*") {
                type = ObjectLinkType.COMPOSITION;
                reverse = left != "*";
            } else if (left.length > 0 && left != "<" && left != "<<") {
                type = ObjectLinkType.AGGREGATION;
                last_marker = left;
            } else if (right.length > 0 && right != ">" && right != ">>") {
                type = ObjectLinkType.AGGREGATION;
                last_marker = right;
                reverse = true;
            } else if (right == ">" || right == ">>") {
                type = dashed ? ObjectLinkType.DEPENDENCY : ObjectLinkType.ASSOCIATION;
            } else if (left == "<" || left == "<<") {
                type = dashed ? ObjectLinkType.DEPENDENCY : ObjectLinkType.ASSOCIATION;
                reverse = true;
            } else {
                type = ObjectLinkType.ASSOCIATION;
                undirected = true;
            }
        }

        private bool is_direction_statement(string first, string second) {
            return current + 3 < tokens.size &&
                   tokens[current].lexeme == first && tokens[current + 1].lexeme == "to" &&
                   tokens[current + 2].lexeme == second && tokens[current + 3].lexeme == "direction";
        }

        // package "Name" [#color] [{]
        private void parse_package() {
            advance();  // package / namespace
            var name_sb = new StringBuilder();
            string? color = null;
            bool quoted = false;
            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                Token t = advance();
                if (t.token_type == TokenType.STRING) {
                    quoted = true;
                }
                if (t.token_type == TokenType.STEREOTYPE) {
                    continue;
                } else if (t.token_type == TokenType.IDENTIFIER && t.lexeme.has_prefix("#") && t.lexeme.length > 1) {
                    color = t.lexeme;
                } else {
                    if (name_sb.len > 0 && t.space_before) {
                        name_sb.append(" ");
                    }
                    name_sb.append(t.lexeme);
                }
            }
            string pkg_name = name_sb.str.strip();
            var pkg = diagram.find_package(pkg_name);
            if (pkg == null && !quoted && pkg_name.contains(".") && package_stack.size == 0) {
                pkg = ensure_package_path(pkg_name);
            }
            if (pkg == null) {
                pkg = new ObjectPackage(pkg_name);
                if (package_stack.size > 0) {
                    var enclosing = package_stack[package_stack.size - 1];
                    pkg.parent = enclosing;
                    enclosing.children.add(pkg);
                } else {
                    diagram.packages.add(pkg);
                }
            }
            if (color != null) {
                pkg.color = color;
            }
            if (match(TokenType.LBRACE)) {
                package_stack.add(pkg);
            }
        }

        private bool is_map_arrow_start() {
            return check(TokenType.IDENTIFIER) && peek().lexeme == "=" && current + 1 < tokens.size &&
                   tokens[current + 1].lexeme == ">" && !tokens[current + 1].space_before;
        }

        // map "Title" [as Alias] [#color] { key => value | key <arrow> Target }
        private void parse_map() {
            int line = advance().line;  // "map"
            string? name = read_name();
            if (name == null) {
                expect_end_of_statement();
                return;
            }
            var map = touch_object(name, line, last_name_quoted);
            if (match(TokenType.AS)) {
                string? alias = read_name();
                if (alias != null) {
                    map.alias = alias;
                }
            }
            map.is_map = true;
            if (match(TokenType.STEREOTYPE)) {
                map.stereotype = previous().lexeme;
            }
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                map.color = advance().lexeme;
            }
            if (!match(TokenType.LBRACE)) {
                expect_end_of_statement();
                return;
            }
            string map_ref = map.alias ?? map.name;
            skip_newlines();
            while (!check(TokenType.RBRACE) && !check(TokenType.ENDUML) && !is_at_end()) {
                int start = current;
                int row_line = peek().line;
                var key = new StringBuilder();
                while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end() &&
                       !is_map_arrow_start() && !(arrow_piece_at(current, true) && peek().space_before)) {
                    Token t = advance();
                    if (key.len > 0 && t.space_before) {
                        key.append(" ");
                    }
                    key.append(t.lexeme);
                }
                string k = key.str.strip();
                if (is_map_arrow_start()) {
                    advance();
                    advance();
                    var val = new StringBuilder();
                    while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                        Token t = advance();
                        if (val.len > 0 && t.space_before) {
                            val.append(" ");
                        }
                        val.append(t.lexeme);
                    }
                    if (k.length > 0) {
                        map.entries.add(new MapEntry(k, val.str.strip()));
                    }
                } else if (k.length > 0) {
                    var entry = new MapEntry(k, "");
                    map.entries.add(entry);
                    string? row_arrow = read_arrow();
                    if (row_arrow != null) {
                        entry.link_row = true;
                        int to_line = peek().line;
                        string? to_row;
                        string? target = read_endpoint(out to_row);
                        if (target != null) {
                            // In a map row the "*" of "*->" only marks the row link; it is
                            // a plain arrow, not a composition
                            string link_arrow = row_arrow.has_prefix("*") ? row_arrow.substring(1) : row_arrow;
                            add_link(map_ref, k, row_line, false, target, to_row, to_line, last_name_quoted,
                                     link_arrow, null, null);
                        }
                    }
                    skip_to_end_of_line();
                }
                skip_newlines();
                if (current == start) {
                    advance();
                }
            }
            match(TokenType.RBRACE);
        }

        private void parse_note() {
            int line = advance().line;  // consume "note"

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

            // "of ObjectName"
            if (match(TokenType.OF)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            // Floating note: note "text" as N1 is one line; note as N1 names a block
            // note. The first read on to "end note" past @enduml, the second showed "as N1".
            if (attached_to == null && check(TokenType.STRING) && check_next(TokenType.AS)) {
                var floating = new ObjectNote(advance().lexeme, line);
                advance();  // as
                floating.alias = read_note_alias();  // links name the note by its alias
                skip_to_end_of_line();
                floating.position = position;
                diagram.notes.add(floating);
                return;
            }
            string? alias = null;
            if (attached_to == null && match(TokenType.AS)) {
                alias = read_note_alias();
            }

            // Note text
            var sb = new StringBuilder();

            if (match(TokenType.COLON)) {
                sb.append(consume_rest_of_line());
            } else {
                skip_newlines();
                // Multi-line note until "end note"
                // An unclosed note stops at @enduml
                while (!is_at_end() && !check(TokenType.ENDUML)) {
                    // Only "end note" terminates the body. Testing for NOTE
                    // *before* consuming keeps a bare "end" in the prose.
                    if (check(TokenType.END) && check_next(TokenType.NOTE)) {
                        advance();  // 'end'
                        advance();  // 'note'
                        break;
                    }
                    if (check(TokenType.NEWLINE)) {
                        if (sb.len > 0) sb.append("\n");
                        advance();
                    } else {
                        Token body_tok = advance();
                        if (sb.len > 0 && body_tok.space_before && !sb.str.has_suffix("\n")) {
                            sb.append(" ");
                        }
                        sb.append(body_tok.lexeme);
                    }
                }
            }

            var note = new ObjectNote(sb.str.strip(), line);
            note.alias = alias;
            note.attached_to = attached_to;
            note.position = position;
            diagram.notes.add(note);
        }

        // The alias after "note ... as": a word, "pkg.Name" or a quoted name on the same line
        private string? read_note_alias() {
            if (check(TokenType.STRING)) {
                return advance().lexeme;
            }
            if (!is_at_end() && is_word_token(peek())) {
                return read_name();
            }
            return null;
        }

        private string parse_color() {
            var sb = new StringBuilder();
            sb.append("#");

            while (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
                Token t = peek();
                if (t.token_type == TokenType.IDENTIFIER) {
                    sb.append(advance().lexeme);
                } else {
                    break;
                }
            }

            return sb.str;
        }

        private void parse_skinparam() {
            string first_name = "";
            // Any token can name the skinparam element ("note", "state", "class" ... lex
            // as keywords); a whitelist let theme blocks become diagram elements.
            if (!check(TokenType.NEWLINE) && !check(TokenType.LBRACE) && !is_at_end()) {
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

        private void parse_skinparam_block(string element) {
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
            var sb = new StringBuilder();
            bool in_color = false;

            while (!check(TokenType.NEWLINE) && !check(TokenType.RBRACE) && !is_at_end()) {
                Token t = advance();

                if (t.lexeme == "#") {
                    if (sb.len > 0 && t.space_before) {
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
                    case TokenType.OBJECT:
                    case TokenType.NOTE:
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
