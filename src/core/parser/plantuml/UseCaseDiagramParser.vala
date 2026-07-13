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
            declare_undeclared_ends();

            return diagram;
        }

        // A plain name used only in relationships ("User <|-- Admin") is an actor, as in
        // PlantUML. Checked after parsing, so a use case declared further down is not turned
        // into an actor. Such names were drawn as grey default nodes with unreadable labels.
        private void declare_undeclared_ends() {
            foreach (var rel in diagram.relationships) {
                foreach (string end in new string[] { rel.from_id, rel.to_id }) {
                    if (end.length == 0 || diagram.find_actor(end) != null || diagram.find_usecase(end) != null ||
                        diagram.find_package(end) != null || is_note_alias(end)) {
                        continue;
                    }
                    diagram.actors.add(new UseCaseActor(end));
                }
            }
        }

        // A floating note keeps its alias as id ("note "text" as N2"), so "(Start) .. N2" links the note
        private bool is_note_alias(string name) {
            foreach (var note in diagram.notes) {
                if (note.id == name) return true;
            }
            return false;
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
                int before = current;
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
                // Every statement must consume something, or this loop spins forever
                if (current == before && !check(TokenType.ENDUML)) {
                    advance();
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

            // Package, rectangle, frame, node, cloud or folder. Only package and rectangle
            // were containers; use cases inside a frame lost the frame.
            if (check(TokenType.PACKAGE) || check(TokenType.RECTANGLE) || check(TokenType.FRAME) ||
                check(TokenType.NODE_KW) || check(TokenType.CLOUD) || check(TokenType.FOLDER)) {
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
            // "legend ... endlegend": the lines were read as elements (object diagrams got
            // ghost "Key"/"endlegend" objects) or skipped
            if (check(TokenType.LEGEND) && current + 1 < tokens.size && !is_arrow_piece(tokens[current + 1])) {
                diagram.legend = ComponentDiagramParser.read_legend_block(tokens, ref current);
                return;
            }

            // "json Name { ... }" (with allowmixing): it was read as an actor "json" and lines of
            // the body, and nothing was drawn
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "json" && current + 2 < tokens.size &&
                (tokens[current + 1].token_type == TokenType.IDENTIFIER || tokens[current + 1].token_type == TokenType.STRING) &&
                tokens[current + 2].token_type == TokenType.LBRACE) {
                parse_json_block();
                return;
            }

            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || check(TokenType.COLON)) {
                parse_relationship_or_element();
                return;
            }

            // "(Use case)" declaration or a relationship starting with one. The line was
            // skipped, so top-level "(A) --> (B)" was dropped.
            if (check(TokenType.LPAREN)) {
                parse_paren_statement();
                return;
            }

            // "left --> right" after "... as left": aliases that lex as keywords
            if (is_name_word() && current + 1 < tokens.size && is_arrow_piece(tokens[current + 1])) {
                parse_relationship_or_element();
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        // A word token usable as a name or alias: "left", "right", "top", "bottom", "end" ...
        // lex as keywords, not IDENTIFIER
        private bool is_name_word() {
            if (is_at_end()) return false;
            var t = peek();
            if (t.token_type == TokenType.STRING || t.token_type == TokenType.NEWLINE ||
                t.token_type == TokenType.EOF || t.token_type == TokenType.COMMENT ||
                t.token_type == TokenType.ENDUML || t.token_type == TokenType.STEREOTYPE) {
                return false;
            }
            string lx = t.lexeme;
            return lx.length > 0 && (lx.get_char(0).isalnum() || lx.has_prefix("_"));
        }

        private bool try_parse_direction() {
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

        private bool try_parse_top_to_bottom() {
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

        // "actor [/] Name [as Alias] [<<stereotype>>] [#colour]", added to `into` (a
        // container's actors) or the top level
        private void parse_actor_declaration(Gee.ArrayList<UseCaseActor>? into = null) throws Error {
            int line = advance().line;  // consume "actor"
            bool business = skip_business_marker();  // "actor/ Woman3": the "/" became an actor named "/"

            string name;
            bool name_is_text = check(TokenType.STRING);
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.COLON)) {
                name_is_text = true;
                // "actor :Last actor: as Person1" was lost
                advance();  // consume :
                string? colon_name = read_colon_name();
                if (colon_name == null) {
                    throw new IOError.FAILED("Expected actor name");
                }
                name = colon_name;
                if (skip_business_marker()) {
                    business = true;
                }
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected actor name");
            }

            var actor = new UseCaseActor(name, line);
            actor.business = business;

            // Stereotype before or after "as Alias": "actor User <<human>> as u" lost the
            // alias and left a second, undeclared "u"
            string? stereotype = null;
            parse_stereotype(ref stereotype);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word()) {
                    Token alias = advance();
                    if (alias_is_description(alias, name_is_text)) {
                        actor.alias = actor.name;
                        actor.name = alias.lexeme;
                    } else {
                        actor.alias = alias.lexeme;
                    }
                }
            }

            // Check for stereotype <<...>>
            parse_stereotype(ref stereotype);
            actor.stereotype = stereotype;

            // Colour and inline style
            string? color = null, line_color = null, line_style = null, text_color = null;
            parse_element_style(ref color, ref line_color, ref line_style, ref text_color);
            actor.color = color;
            actor.line_color = line_color;
            actor.line_style = line_style;
            actor.text_color = text_color;

            (into ?? diagram.actors).add(actor);
            expect_end_of_statement();
        }

        // "usecase [/] Name|\"Name\"|(Name) [as Alias|\"Description\"] [<<stereotype>>] [#colour;style]",
        // added to `into` (a container) or the top level
        private void parse_usecase_declaration(UseCasePackage? into = null) throws Error {
            int line = advance().line;  // consume "usecase"
            // "usecase/ UC3": the "/" became a use case named "/"
            bool business = skip_business_marker();

            string name;
            bool name_is_text = !check(TokenType.IDENTIFIER);
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                // Handle parenthesized use case: usecase (Name)
                if (match(TokenType.LPAREN)) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        Token part = advance();
                        if (sb.len > 0 && part.space_before) sb.append(" ");
                        sb.append(part.lexeme);
                    }
                    match(TokenType.RPAREN);
                    name = sb.str.strip();
                } else {
                    throw new IOError.FAILED("Expected usecase name");
                }
            }
            if (skip_business_marker()) {
                business = true;
            }

            var uc = new UseCase(name, line);
            uc.business = business;

            // Stereotype before or after "as Alias": "actor User <<human>> as u" lost the
            // alias and left a second, undeclared "u"
            string? stereotype = null;
            parse_stereotype(ref stereotype);

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word()) {
                    Token alias = advance();
                    if (alias_is_description(alias, name_is_text)) {
                        uc.alias = uc.name;
                        uc.name = alias.lexeme;
                    } else {
                        uc.alias = alias.lexeme;
                    }
                }
            }

            // Check for stereotype <<...>>
            parse_stereotype(ref stereotype);
            uc.stereotype = stereotype;

            // Colour and inline style
            string? color = null, line_color = null, line_style = null, text_color = null;
            parse_element_style(ref color, ref line_color, ref line_style, ref text_color);
            uc.color = color;
            uc.line_color = line_color;
            uc.line_style = line_style;
            uc.text_color = text_color;

            if (into != null) {
                uc.container = into.name;
                into.use_cases.add(uc);
            } else {
                diagram.use_cases.add(uc);
            }
            expect_end_of_statement();
        }

        // "usecase UC1 as \"Long description\"", "actor A1 as \"Actor desc\"": the quoted text
        // is shown and the word before "as" is the id. Both were swapped: the id was shown.
        // "usecase \"Eat Food\" as UC1" / "usecase description1 as alias1" keep the name shown.
        private static bool alias_is_description(Token alias, bool name_is_text) {
            return alias.token_type == TokenType.STRING && !name_is_text;
        }

        // "#pink", "#pink;line:red;line.bold;text:red", "#back:pink;line.dashed", "#line:green":
        // colours as "#name" / "#RRGGBB". Only the first colour was read; the rest was ignored.
        private void parse_element_style(ref string? color, ref string? line_color, ref string? line_style,
                                         ref string? text_color) {
            string? first = parse_color();
            if (first == null || first.length < 2) {
                return;
            }
            string key = first.substring(1).down();
            if ((key == "back" || key == "line" || key == "text") && !check(TokenType.NEWLINE) && !is_at_end() &&
                !peek().space_before && (check(TokenType.COLON) || peek().lexeme == ".")) {
                style_item(key, ref color, ref line_color, ref line_style, ref text_color);
            } else {
                color = first;
            }
            while (check(TokenType.SEMICOLON) && !peek().space_before && current + 1 < tokens.size &&
                   !tokens[current + 1].space_before && tokens[current + 1].token_type != TokenType.NEWLINE) {
                advance();  // ;
                string item = advance().lexeme.down();
                style_item(item, ref color, ref line_color, ref line_style, ref text_color);
            }
        }

        // One item of an inline style, its key already read: "back:X", "line:X", "text:X",
        // "line.dashed" / "line.dotted" / "line.bold"
        private void style_item(string key, ref string? color, ref string? line_color, ref string? line_style,
                                ref string? text_color) {
            if (key == "line" && !is_at_end() && peek().lexeme == "." && !peek().space_before &&
                current + 1 < tokens.size && !tokens[current + 1].space_before) {
                advance();  // .
                string st = advance().lexeme.down();
                if (st == "dashed" || st == "dotted" || st == "bold") {
                    line_style = st;
                }
                return;
            }
            if (!check(TokenType.COLON) || peek().space_before || current + 1 >= tokens.size ||
                tokens[current + 1].space_before || tokens[current + 1].token_type == TokenType.NEWLINE) {
                return;
            }
            advance();  // :
            string value = advance().lexeme;
            if (!value.has_prefix("#")) {
                value = "#" + value;
            }
            switch (key) {
                case "back": color = value; break;
                case "line": line_color = value; break;
                case "text": text_color = value; break;
                default: break;
            }
        }

        private void parse_stereotype(ref string? stereotype) {
            string? text = read_stereotype_text();
            if (text != null) {
                stereotype = text;
            }
        }

        // "<<Human>>" (one STEREOTYPE token) or "<< One Shot >>" (tokenized as < < words > >).
        // Only a single-word "< < name > >" was read, so "<< One Shot >>" was lost.
        private string? read_stereotype_text() {
            if (check(TokenType.STEREOTYPE)) {
                return advance().lexeme.strip();
            }
            if (!(check(TokenType.IDENTIFIER) && peek().lexeme == "<" && current + 1 < tokens.size &&
                  tokens[current + 1].lexeme == "<")) {
                return null;
            }
            advance();  // consume first <
            advance();  // consume second <
            var sb = new StringBuilder();
            while (!is_at_end() && !check(TokenType.NEWLINE) && !peek().lexeme.has_prefix(">")) {
                Token part = advance();
                if (sb.len > 0 && part.space_before) sb.append(" ");
                sb.append(part.lexeme);
            }
            while (!is_at_end() && !check(TokenType.NEWLINE) && peek().lexeme.has_prefix(">")) {
                advance();  // consume closing >>
            }
            string text = sb.str.strip();
            return text.length > 0 ? text : null;
        }

        // Business actor / use case marker written right after the name: ":Name:/", "(Name)/",
        // "actor/". The "/" became an actor named "/" or blocked a following "as Alias".
        private bool skip_business_marker() {
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "/" && !peek().space_before) {
                advance();
                return true;
            }
            return false;
        }

        // A colour from an inline style, "#" already removed: hex digits get it back
        // ("FF0000" -> "#FF0000"), a name stays a name
        private static string color_value(string raw) {
            string v = raw.strip();
            if (v.has_prefix("#")) {
                v = v.substring(1);
            }
            if (v.length == 3 || v.length == 6 || v.length == 8) {
                bool hex = true;
                for (int i = 0; i < v.length; i++) {
                    if (!v[i].isxdigit()) {
                        hex = false;
                        break;
                    }
                }
                if (hex) {
                    return "#" + v;
                }
            }
            return v;
        }

        // A token that is (part of) an arrow line: "-->", "<..", "<|--", or "." / ">" / "<"
        // left over as single-character identifiers
        private static bool is_arrow_piece(Token t) {
            switch (t.token_type) {
                case TokenType.ARROW_RIGHT:
                case TokenType.ARROW_RIGHT_DOTTED:
                case TokenType.ARROW_LEFT:
                case TokenType.ARROW_LEFT_DOTTED:
                case TokenType.MINUS_MINUS:
                case TokenType.MINUS:
                case TokenType.DOT_DOT:
                case TokenType.INHERITANCE:
                case TokenType.DEPENDENCY:
                    return true;
                case TokenType.IDENTIFIER:
                    if (t.lexeme.length == 0) {
                        return false;
                    }
                    for (int i = 0; i < t.lexeme.length; i++) {
                        if ("-.<>|".index_of_char(t.lexeme[i]) < 0) {
                            return false;
                        }
                    }
                    return true;
                default:
                    return false;
            }
        }

        private static string? direction_word(string word) {
            switch (word.down()) {
                case "u": case "up":
                    return "up";
                case "d": case "do": case "down":
                    return "down";
                case "l": case "le": case "left":
                    return "left";
                case "r": case "ri": case "right":
                    return "right";
                default:
                    return null;
            }
        }

        // Reads an arrow from adjacent tokens: "-->", "-up->", ".left.>", "-[#blue,dashed]->".
        // Returns the arrow without direction and options (e.g. "-->", "..>"), or null with
        // the cursor unchanged when there is no arrow here.
        private string? read_arrow(out string placement, out string? opt_color, out string? opt_style) {
            placement = "";
            opt_color = null;
            opt_style = null;
            int start = current;
            var sb = new StringBuilder();
            bool first = true;
            while (!is_at_end() && !check(TokenType.NEWLINE)) {
                Token t = peek();
                if (!first && t.space_before) {
                    break;
                }
                string text = sb.str;
                if (text.has_suffix(">")) {
                    break;  // the head ends the arrow
                }
                bool after_line = text.has_suffix("-") || text.has_suffix(".");
                string? dir = after_line && placement == "" ? direction_word(t.lexeme) : null;
                if (is_arrow_piece(t)) {
                    sb.append(t.lexeme);
                    advance();
                } else if (dir != null && current + 1 < tokens.size && is_arrow_piece(tokens[current + 1]) &&
                           !tokens[current + 1].space_before) {
                    placement = dir;
                    advance();
                } else if (after_line && t.token_type == TokenType.LBRACKET) {
                    advance();  // [
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        string opt = advance().lexeme.strip();
                        string low = opt.down();
                        if (low == "dashed" || low == "dotted" || low == "bold") {
                            opt_style = low;
                        } else if (low == "hidden") {
                            opt_style = "invis";
                        } else if (opt.has_prefix("#") && opt.length > 1) {
                            opt_color = color_value(opt);
                        }
                    }
                    if (!match(TokenType.RBRACKET)) {
                        break;
                    }
                } else {
                    break;
                }
                first = false;
            }
            string arrow = sb.str;
            if (!arrow.contains("-") && !arrow.contains(".")) {
                current = start;
                placement = "";
                opt_color = null;
                opt_style = null;
                return null;
            }
            return arrow;
        }

        private string? parse_color() {
            // The lexer gives "#pink" / "#FF0000" as one IDENTIFIER token
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#")) {
                return advance().lexeme;
            }
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
            } else if (check(TokenType.FRAME)) {
                container_type = UseCaseContainerType.FRAME;
            } else if (check(TokenType.NODE_KW)) {
                container_type = UseCaseContainerType.NODE;
            } else if (check(TokenType.CLOUD)) {
                container_type = UseCaseContainerType.CLOUD;
            } else if (check(TokenType.FOLDER)) {
                container_type = UseCaseContainerType.FOLDER;
            }
            advance();  // consume the container keyword

            string name;
            if (check(TokenType.STRING)) {
                name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else {
                throw new IOError.FAILED("Expected package name");
            }

            var package = new UseCasePackage(name, container_type);
            package.parent = current_package;  // set while parsing an enclosing body

            // Check for "as Alias"
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word()) {
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

        private void parse_note() {
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
                } else if (match(TokenType.LPAREN)) {
                    // "note right of (Use)": the name was left in the note text, unattached
                    var name = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        Token part = advance();
                        if (name.len > 0 && part.space_before) name.append(" ");
                        name.append(part.lexeme);
                    }
                    match(TokenType.RPAREN);
                    attached_to = name.str;
                }
            }

            // Floating note: note "text" as N1 is one line; note as N1 names a block
            // note. The first read on to "end note" past @enduml, the second showed "as N1".
            if (attached_to == null && check(TokenType.STRING) && check_next(TokenType.AS)) {
                var floating = new UseCaseNote(advance().lexeme);
                advance();  // as
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    floating.id = advance().lexeme;  // links name the note by its alias
                }
                while (!check(TokenType.NEWLINE) && !is_at_end()) {
                    advance();
                }
                floating.position = position;
                diagram.notes.add(floating);
                return;
            }
            string? alias = null;
            if (attached_to == null && match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    alias = advance().lexeme;
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

            var note = new UseCaseNote(sb.str.strip());
            if (alias != null) note.id = alias;
            note.attached_to = attached_to;
            note.position = position;
            diagram.notes.add(note);
        }

        // Container whose body is being parsed: use cases first named there belong to it
        private UseCasePackage? current_package = null;

        // "(Name) [as Alias]" declares a use case (in the current container, if any); a line
        // that continues after "(Name)" is a relationship starting with that use case
        private void parse_paren_statement() {
            int start = current;
            int uc_line = advance().line;  // consume (
            var sb = new StringBuilder();
            while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                Token part = advance();
                if (sb.len > 0 && part.space_before) sb.append(" ");
                sb.append(part.lexeme);
            }
            bool closed = match(TokenType.RPAREN);
            bool business = closed && skip_business_marker();  // "(First usecase)/"
            string name = sb.str.strip();
            // A declaration ends after the name, or continues with "as Alias" or a stereotype
            // ("(Start) << One Shot >>", which was parsed as a relationship and dropped)
            bool stereotype_next = check(TokenType.STEREOTYPE) ||
                (check(TokenType.IDENTIFIER) && peek().lexeme == "<" && current + 1 < tokens.size &&
                 tokens[current + 1].lexeme == "<");
            if (closed && name.length > 0 &&
                (check(TokenType.NEWLINE) || check(TokenType.RBRACE) || check(TokenType.AS) || stereotype_next ||
                 is_at_end())) {
                var uc = find_usecase_in_scope(name);
                if (uc == null && is_container_name(name)) {
                    // "(Sys)" alone inside "rectangle Sys" names the container, not a new use case
                    expect_end_of_statement();
                    return;
                }
                if (uc == null) {
                    uc = new UseCase(name, uc_line);
                    if (current_package != null) {
                        uc.container = current_package.name;
                        current_package.use_cases.add(uc);
                    } else {
                        diagram.use_cases.add(uc);
                    }
                }
                if (business) {
                    uc.business = true;
                }
                if (match(TokenType.AS)) {
                    if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word()) {
                        uc.alias = advance().lexeme;
                    } else if (check(TokenType.LPAREN)) {
                        // "(Use the application) as (Use)": the parenthesised alias was ignored,
                        // so a later "(Use)" made a second, separate use case
                        advance();  // consume (
                        var alias_sb = new StringBuilder();
                        while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                            Token part = advance();
                            if (alias_sb.len > 0 && part.space_before) alias_sb.append(" ");
                            alias_sb.append(part.lexeme);
                        }
                        match(TokenType.RPAREN);
                        string alias_name = alias_sb.str.strip();
                        if (alias_name.length > 0) {
                            uc.alias = alias_name;
                        }
                    }
                }
                string? paren_stereo = read_stereotype_text();
                if (paren_stereo != null) {
                    uc.stereotype = paren_stereo;
                }
                expect_end_of_statement();
            } else {
                current = start;
                parse_relationship_or_element();
            }
        }

        // A "(Name)" relationship end is a use case: declare it where it is first named. A name
        // that is a container ("(checkout)" inside "rectangle checkout") stays the container.
        // Undeclared ends were drawn as grey default nodes with unreadable labels.
        private void touch_usecase(string name) {
            if (name.length == 0 || find_usecase_in_scope(name) != null || diagram.find_actor(name) != null) {
                return;
            }
            if (is_container_name(name)) {
                return;
            }
            var uc = new UseCase(name);
            if (current_package != null) {
                uc.container = current_package.name;
                current_package.use_cases.add(uc);
            } else {
                diagram.use_cases.add(uc);
            }
        }

        // An actor named between colons (":user:"), declared where it is first named
        private UseCaseActor touch_actor(string name) {
            var existing = diagram.find_actor(name);
            if (existing != null) {
                return existing;
            }
            for (var pkg = current_package; pkg != null; pkg = pkg.parent) {
                foreach (var candidate in pkg.actors) {
                    if (candidate.name == name || candidate.alias == name) {
                        return candidate;
                    }
                }
            }
            var actor = new UseCaseActor(name);
            if (current_package != null) {
                current_package.actors.add(actor);
            } else {
                diagram.actors.add(actor);
            }
            return actor;
        }

        // Reads "Name:" after an opening ':' (already consumed); null when there is no
        // closing ':' on the line or the name is empty
        private string? read_colon_name() {
            int start = current;
            var sb = new StringBuilder();
            while (!check(TokenType.COLON) && !check(TokenType.NEWLINE) && !is_at_end()) {
                Token part = advance();
                if (sb.len > 0 && part.space_before) sb.append(" ");
                sb.append(part.lexeme);
            }
            if (!match(TokenType.COLON) || sb.str.strip().length == 0) {
                current = start;
                return null;
            }
            return sb.str.strip();
        }

        // The container being parsed is only added to diagram.packages after its body, so
        // lookups during the body must also check it: without this, every "(checkout)" inside
        // "rectangle checkout" created another use case named like the container
        private UseCase? find_usecase_in_scope(string name) {
            var uc = diagram.find_usecase(name);
            if (uc != null) {
                return uc;
            }
            // The enclosing containers are not in diagram.packages yet either
            for (var pkg = current_package; pkg != null; pkg = pkg.parent) {
                foreach (var candidate in pkg.use_cases) {
                    if (candidate.name == name || candidate.alias == name) {
                        return candidate;
                    }
                }
            }
            return null;
        }

        private bool is_container_name(string name) {
            for (var pkg = current_package; pkg != null; pkg = pkg.parent) {
                if (pkg.name == name || pkg.alias == name) {
                    return true;
                }
            }
            return diagram.find_package(name) != null;
        }

        private void parse_package_body(UseCasePackage package) {
            var outer_package = current_package;
            current_package = package;
            parse_package_body_statements(package);
            current_package = outer_package;
        }

        private void parse_package_body_statements(UseCasePackage package) {
            skip_newlines();

            // An unclosed body ends at @enduml; it used to swallow it
            while (!check(TokenType.RBRACE) && !check(TokenType.ENDUML) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE) || check(TokenType.ENDUML)) {
                    break;
                }
                int pos_before = current;

                // Actor in package: the same declaration as at the top level. A reduced copy
                // made "actor/ Woman" an actor named "/" and ignored stereotype and colour.
                if (check(TokenType.ACTOR)) {
                    try {
                        parse_actor_declaration(package.actors);
                    } catch (Error e) {
                        expect_end_of_statement();
                    }
                }
                // Nested container ("rectangle Sys { package Sub { (Deep) } }"). The keyword
                // was skipped, so its "}" closed the outer body and "Sub" was lost.
                else if (check(TokenType.PACKAGE) || check(TokenType.RECTANGLE) || check(TokenType.FRAME) ||
                         check(TokenType.NODE_KW) || check(TokenType.CLOUD) || check(TokenType.FOLDER)) {
                    try {
                        parse_package();
                    } catch (Error e) {
                        expect_end_of_statement();
                    }
                }
                // "note right of (Inner) : text" inside the body was dropped
                else if (check(TokenType.NOTE)) {
                    parse_note();
                }
                // Use case in package: the same declaration as at the top level (a reduced copy
                // ignored stereotype, colour and "usecase/")
                else if (check(TokenType.USECASE)) {
                    try {
                        parse_usecase_declaration(package);
                    } catch (Error e) {
                        expect_end_of_statement();
                    }
                }
                // "(Name)" shorthand: a use case in this container when the line ends after it
                // (optionally "as Alias"); otherwise the start of a relationship. It was skipped,
                // so the use case was only created, outside the container, by a later link.
                else if (check(TokenType.LPAREN)) {
                    parse_paren_statement();
                }
                // Relationship inside package
                else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    parse_relationship_or_element();
                }
                else {
                    advance();
                }

                // Every statement must consume something; a branch that returns without
                // advancing would otherwise spin this loop forever
                if (current == pos_before) {
                    advance();
                }

                skip_newlines();
            }

            match(TokenType.RBRACE);
        }

        // "json Name {" ... "}": the body is kept as JSON text (strings re-quoted)
        private void parse_json_block() {
            int line = advance().line;  // json
            string name = advance().lexeme;
            advance();  // {
            var sb = new StringBuilder("{");
            int depth = 1;
            while (!is_at_end() && !check(TokenType.ENDUML)) {
                Token t = advance();
                if (t.token_type == TokenType.LBRACE) {
                    depth++;
                } else if (t.token_type == TokenType.RBRACE) {
                    depth--;
                }
                if (t.token_type == TokenType.NEWLINE) {
                    sb.append("\n");
                } else if (t.token_type == TokenType.STRING) {
                    if (t.space_before) sb.append(" ");
                    sb.append("\"%s\"".printf(t.lexeme.replace("\\", "\\\\").replace("\"", "\\\"")));
                } else {
                    if (t.space_before) sb.append(" ");
                    sb.append(t.lexeme);
                }
                if (depth == 0) {
                    break;
                }
            }
            diagram.json_blocks.add(new UseCaseJson(name, sb.str, line));
            expect_end_of_statement();
        }

        // "\"Main Admin\" as Admin" (an actor) and "\"Use the application\" as (Use)" (a use case):
        // the quoted text is shown, the alias is the id. The alias was shown instead, or the
        // line was dropped.
        private void parse_described_alias() {
            string text = advance().lexeme;
            advance();  // as
            if (check(TokenType.LPAREN)) {
                advance();
                var sb = new StringBuilder();
                while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token part = advance();
                    if (sb.len > 0 && part.space_before) sb.append(" ");
                    sb.append(part.lexeme);
                }
                match(TokenType.RPAREN);
                string id = sb.str.strip();
                if (id.length == 0) {
                    expect_end_of_statement();
                    return;
                }
                touch_usecase(id);
                var uc = find_usecase_in_scope(id);
                if (uc != null) {
                    if (uc.alias == null && uc.name == id) {
                        uc.alias = id;
                    }
                    uc.name = text;
                    string? stereo = read_stereotype_text();
                    if (stereo != null) {
                        uc.stereotype = stereo;
                    }
                }
            } else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word()) {
                string id = advance().lexeme;
                var uc = find_usecase_in_scope(id);
                if (uc != null) {
                    if (uc.alias == null && uc.name == id) {
                        uc.alias = id;
                    }
                    uc.name = text;
                } else if (!is_container_name(id)) {
                    var actor = touch_actor(id);
                    if (actor.alias == null && actor.name == id) {
                        actor.alias = id;
                    }
                    actor.name = text;
                    string? stereo = read_stereotype_text();
                    if (stereo != null) {
                        actor.stereotype = stereo;
                    }
                }
            }
            expect_end_of_statement();
        }

        private void parse_relationship_or_element() {
            if (check(TokenType.STRING) && check_next(TokenType.AS)) {
                parse_described_alias();
                return;
            }
            // Get first name
            string from_name;
            if (check(TokenType.STRING)) {
                from_name = advance().lexeme;
            } else if (check(TokenType.IDENTIFIER) || is_name_word()) {
                from_name = advance().lexeme;
            } else if (check(TokenType.COLON)) {
                // Shorthand use case like :(Use Case Name)
                advance();  // consume :
                if (match(TokenType.LPAREN)) {
                    var sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        Token part = advance();
                        if (sb.len > 0 && part.space_before) sb.append(" ");
                        sb.append(part.lexeme);
                    }
                    match(TokenType.RPAREN);
                    from_name = sb.str.strip();
                    diagram.get_or_create_usecase(from_name);
                    expect_end_of_statement();
                    return;
                }
                // ":Main Admin: as Admin" / ":user: --> (X)": an actor between colons. The name
                // was dropped and an actor "User" created instead, so links to it were lost.
                string? actor_name = read_colon_name();
                if (actor_name == null) {
                    // Standalone : is a shorthand for actor
                    from_name = "User";
                    diagram.get_or_create_actor(from_name);
                    expect_end_of_statement();
                    return;
                }
                var colon_actor = touch_actor(actor_name);
                if (skip_business_marker()) {
                    colon_actor.business = true;
                }
                if (match(TokenType.AS)) {
                    if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || is_name_word()) {
                        colon_actor.alias = advance().lexeme;
                    }
                }
                // A stereotype after it (":Main Database: as MySql << Application >>") is read by
                // the no-arrow branch below, which sets it on this actor
                from_name = colon_actor.get_id();
            } else if (check(TokenType.LPAREN)) {
                // "(Use case) --> ...": this returned without consuming anything, so the
                // container body loop calling it spun forever
                advance();  // consume (
                var sb = new StringBuilder();
                while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                    Token part = advance();
                    if (sb.len > 0 && part.space_before) sb.append(" ");
                    sb.append(part.lexeme);
                }
                match(TokenType.RPAREN);
                from_name = sb.str.strip();
                touch_usecase(from_name);
            } else {
                return;
            }

            // Check for relationship arrow
            UseCaseRelationType? rel_type = null;
            bool reverse = false;
            bool is_dashed = false;
            // "--", "-", ".." are plain lines; they used to get an arrowhead like "-->"
            bool directed = true;

            // The whole arrow is read from its adjacent tokens, so a direction word or an
            // options block inside it ("-up->", ".left.>", "-[#blue]->") is part of the arrow.
            // Only single arrow tokens were matched: "-up->" took "-" as a plain line, made an
            // actor named "up" and dropped the target.
            string placement;
            string? opt_color;
            string? opt_style;
            string? arrow = read_arrow(out placement, out opt_color, out opt_style);
            if (arrow != null) {
                rel_type = UseCaseRelationType.ASSOCIATION;
                // "-->" is solid in stock PlantUML; "-.->", "..>", ".." are dashed
                is_dashed = arrow.contains(".");
                if (arrow.contains("|>") || arrow.contains("<|")) {
                    rel_type = UseCaseRelationType.GENERALIZATION;
                    is_dashed = false;
                    reverse = arrow.has_prefix("<");
                } else {
                    // "--", "-", ".." are plain lines; "Auth <.. Login" points at Auth
                    bool left = arrow.has_prefix("<");
                    bool right = arrow.has_suffix(">");
                    directed = left || right;
                    reverse = left && !right;
                }
            }

            if (rel_type != null) {
                // Get second name
                string to_name;
                if (check(TokenType.STRING)) {
                    to_name = advance().lexeme;
                } else if (check(TokenType.IDENTIFIER) || is_name_word()) {
                    to_name = advance().lexeme;
                } else if (check(TokenType.LPAREN)) {
                    advance();  // consume (
                    var sb = new StringBuilder();
                    while (!check(TokenType.RPAREN) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        Token part = advance();
                        if (sb.len > 0 && part.space_before) sb.append(" ");
                        sb.append(part.lexeme);
                    }
                    match(TokenType.RPAREN);
                    to_name = sb.str.strip();
                    touch_usecase(to_name);
                } else if (check(TokenType.COLON)) {
                    // "(Use case 1) <.. :user:": an actor end; the relationship was dropped
                    advance();  // consume :
                    string? target_actor = read_colon_name();
                    if (target_actor == null) {
                        expect_end_of_statement();
                        return;
                    }
                    to_name = touch_actor(target_actor).get_id();
                } else {
                    expect_end_of_statement();
                    return;
                }

                // Inline link style right after the target, written without spaces:
                // "#line:red;line.bold;text:red", "#green;line.dashed". It was ignored and
                // broke the ": label" that follows it.
                string? style_color = null;
                string? style_line = null;
                string? style_text = null;
                bool style_bold = false;
                if (!check(TokenType.NEWLINE) && !is_at_end() &&
                    (check(TokenType.HASH) || peek().lexeme.has_prefix("#"))) {
                    var style_sb = new StringBuilder();
                    bool first = true;
                    while (!check(TokenType.NEWLINE) && !is_at_end() && (first || !peek().space_before)) {
                        style_sb.append(advance().lexeme);
                        first = false;
                    }
                    foreach (string raw_part in style_sb.str.substring(style_sb.str.has_prefix("#") ? 1 : 0).split(";")) {
                        string part = raw_part.strip();
                        string lower = part.down();
                        if (lower.has_prefix("line:")) {
                            style_color = color_value(part.substring(5));
                        } else if (lower.has_prefix("text:")) {
                            style_text = color_value(part.substring(5));
                        } else if (lower == "line.bold" || lower == "bold") {
                            style_bold = true;
                        } else if (lower == "line.dashed" || lower == "dashed") {
                            style_line = "dashed";
                        } else if (lower == "line.dotted" || lower == "dotted") {
                            style_line = "dotted";
                        } else if (part.length > 0 && style_color == null) {
                            // "#FF0000;line.bold": the "#" was stripped with the prefix, and
                            // "FF0000" reached Graphviz as an unknown colour name
                            style_color = color_value(part);
                        }
                    }
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
                relationship.directed = directed;
                relationship.line_color = style_color ?? opt_color;
                relationship.line_style = style_line;
                if (style_line == null && opt_style != null && opt_style != "bold") {
                    relationship.line_style = opt_style;
                }
                relationship.line_bold = style_bold || opt_style == "bold";
                relationship.text_color = style_text;
                relationship.placement = placement;
                int line_chars = 0;
                for (int i = 0; i < arrow.length; i++) {
                    if (arrow[i] == '-' || arrow[i] == '.') {
                        line_chars++;
                    }
                }
                relationship.horizontal = line_chars == 1 && placement == "";

                diagram.relationships.add(relationship);
            } else {
                // "User << Human >>": a stereotype on a name; the name is an actor (as in PlantUML)
                // unless it is a declared use case. The stereotype was ignored.
                string? bare_stereo = read_stereotype_text();
                if (bare_stereo != null && from_name.length > 0) {
                    var stereo_uc = find_usecase_in_scope(from_name);
                    if (stereo_uc != null) {
                        stereo_uc.stereotype = bare_stereo;
                    } else if (!is_container_name(from_name)) {
                        touch_actor(from_name).stereotype = bare_stereo;
                    }
                }
            }

            expect_end_of_statement();
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
                // "BackgroundColor<< Main >> YellowGreen": a per-stereotype value. The stereotype
                // was read as part of the value, overwriting the plain BackgroundColor.
                string? prop_stereo = read_stereotype_text();
                if (prop_stereo != null) {
                    property = "%s<<%s>>".printf(property, prop_stereo);
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
            // Not past @enduml: after an unclosed container body it was consumed here
            while (!check(TokenType.NEWLINE) && !check(TokenType.ENDUML) && !is_at_end()) {
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
                    case TokenType.FRAME:
                    case TokenType.NODE_KW:
                    case TokenType.CLOUD:
                    case TokenType.FOLDER:
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
