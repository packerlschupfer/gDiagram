namespace GDiagram {
    public class StateDiagramParser : Object {
        private Gee.ArrayList<Token> tokens;
        private int current;
        private StateDiagram diagram;

        public StateDiagramParser() {
            this.current = 0;
        }

        public StateDiagram parse(Gee.ArrayList<Token> tokens) {
            this.tokens = tokens;
            this.current = 0;
            this.diagram = new StateDiagram();
            this.declared = new Gee.HashSet<State>();
            this.open_regions = new Gee.HashMap<State, int>();
            this.last_transition = null;

            try {
                parse_diagram();
            } catch (Error e) {
                diagram.errors.add(new ParseError(e.message, 1, 1));
            }

            // "Idle --> N1" where N1 is a floating note's alias runs to the note (its id);
            // the transition end made a state box of the same name. It is removed from
            // wherever it sits: a ghost made inside "state Outer { A --> N1 }" stayed there
            // and pulled the note into Outer's cluster.
            foreach (var note in diagram.notes) {
                var ghost = diagram.find_state(note.id);
                if (ghost != null && ghost.nested_states.size == 0) {
                    detach_state(ghost);
                }
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

            // Hide directive
            if (match(TokenType.HIDE)) {
                // hide empty description
                string rest = consume_rest_of_line().down();
                if (rest.contains("empty") && rest.contains("description")) {
                    diagram.hide_empty_description = true;
                }
                return;
            }

            // State declaration ("State S1" too: the capitalised keyword made a state "State")
            if (check(TokenType.STATE) || is_state_keyword()) {
                parse_state_declaration(null);
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

            // Skinparam directive
            if (match(TokenType.SKINPARAM)) {
                parse_skinparam();
                return;
            }

            // Output scaling (scale 2, scale max 800 width) - not a state
            if (match(TokenType.SCALE)) {
                skip_to_end_of_line();
                return;
            }

            // Note
            if (check(TokenType.NOTE)) {
                parse_note();
                return;
            }

            // Transition: State1 --> State2 : label, [*] --> A, [H] --> A, A --> S[H*]
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || check(TokenType.INITIAL_FINAL) ||
                check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) {
                parse_transition_or_state(null);
                return;
            }

            // Unknown - skip to next line
            advance();
        }

        // "State S1": the keyword written with a capital letter lexes as an identifier
        private bool is_state_keyword() {
            if (!check(TokenType.IDENTIFIER) || peek().lexeme.down() != "state" || current + 1 >= tokens.size) {
                return false;
            }
            var next = tokens[current + 1];
            return next.space_before &&
                   (next.token_type == TokenType.IDENTIFIER || next.token_type == TokenType.STRING);
        }

        // ── Scopes ─────────────────────────────────────────────────────────
        // A scope is the top level (parent null) or the body of a composite state.

        // States named in a "state" declaration, not only referenced by a transition
        private Gee.HashSet<State> declared = new Gee.HashSet<State>();
        // Region being filled in each composite body that is open right now
        private Gee.HashMap<State, int> open_regions = new Gee.HashMap<State, int>();
        private StateTransition? last_transition = null;

        private Gee.ArrayList<State> scope_states(State? parent) {
            return parent == null ? diagram.states : parent.nested_states;
        }

        private int region_of(State? parent) {
            return parent != null && open_regions.has_key(parent) ? open_regions.get(parent) : 0;
        }

        private void add_to_scope(State? parent, State state) {
            state.region = region_of(parent);
            scope_states(parent).add(state);
        }

        // The [*] start / end circle or [H] / [H*] history of a scope. PlantUML draws one start
        // and one end per scope (per concurrent region), however many transitions use them;
        // each "X --> [*]" drew its own end circle. "Outer --> [H]" inside a composite and
        // "X --> S[H*]" name the history inside that composite; both were dropped.
        private State pseudo_state(State? parent, StateType type) {
            bool per_region = type == StateType.INITIAL || type == StateType.FINAL;
            int region = region_of(parent);
            foreach (var s in scope_states(parent)) {
                if (s.state_type == type && s.id.has_prefix("_") && (!per_region || s.region == region)) {
                    return s;
                }
            }
            State created;
            switch (type) {
                case StateType.INITIAL: created = State.create_initial(); break;
                case StateType.FINAL: created = State.create_final(); break;
                case StateType.DEEP_HISTORY: created = State.create_history(true); break;
                default: created = State.create_history(false); break;
            }
            add_to_scope(parent, created);
            return created;
        }

        // A state named by a transition. State names are global: an existing state is that
        // state wherever it is drawn. A new one goes into the scope where it is first named.
        private State resolve_named(State? parent, string name) {
            if (parent == null) {
                return diagram.get_or_create_state(name);
            }
            foreach (var ns in parent.nested_states) {
                if (ns.id == name) {
                    return ns;
                }
            }
            var found = diagram.find_state(name);
            if (found != null) {
                return found;
            }
            var created = new State(name);
            add_to_scope(parent, created);
            return created;
        }

        // A state named by a "state" declaration in this scope. An existing state declared
        // inside a composite moves there. A state only referenced so far moves here from
        // wherever that reference put it: "A1 --> B" inside A, then a top-level "state B { }",
        // is a top-level B, as in PlantUML; it stayed nested inside A.
        private State declare_state(State? parent, string id, int line) {
            State? existing = null;
            foreach (var s in scope_states(parent)) {
                if (s.id == id) {
                    existing = s;
                    break;
                }
            }
            if (existing == null) {
                var found = diagram.find_state(id);
                if (found != null && found != parent && (parent == null || !state_contains(found, parent))) {
                    if (parent != null || !declared.contains(found)) {
                        detach_state(found);
                        add_to_scope(parent, found);
                    }
                    existing = found;
                }
            }
            if (existing == null) {
                existing = new State(id, StateType.SIMPLE, line);
                add_to_scope(parent, existing);
            }
            if (line > 0 && existing.source_line == 0) {
                existing.source_line = line;
            }
            declared.add(existing);
            return existing;
        }

        // "state Name", "state \"Long name\" as Id", "state Id as \"Long name\"", "state A.X",
        // with stereotype, colours, a body and a description, at the top level or in a body.
        // Also the keyword-less "\"Long name\" as Id".
        private void parse_state_declaration(State? parent, bool keyword = true) throws Error {
            int line = keyword ? advance().line : peek().line;  // consume "state"

            string name;
            bool quoted = check(TokenType.STRING);
            if (check(TokenType.STRING) || check(TokenType.IDENTIFIER)) {
                name = advance().lexeme;
            } else if (parent == null) {
                throw new IOError.FAILED("Expected state name");
            } else {
                expect_end_of_statement();
                return;
            }

            // "state A.X": X inside composite A. The dots were left in the line and A, B and X
            // were drawn as unrelated top-level states.
            var path = new Gee.ArrayList<string>();
            while (!quoted && check(TokenType.IDENTIFIER) && peek().lexeme == "." && !peek().space_before &&
                   current + 1 < tokens.size && tokens[current + 1].token_type == TokenType.IDENTIFIER &&
                   !tokens[current + 1].space_before && is_word_token(tokens[current + 1])) {
                advance();  // "."
                path.add(name);
                name = advance().lexeme;
            }

            string id = name;
            string? label = null;
            if (match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    Token alias = advance();
                    if (alias.token_type == TokenType.STRING && !quoted) {
                        // "state p as \"Plain desc\"": p is the id, the quoted text is shown.
                        // The id was shown and "Plain desc" became the id.
                        label = alias.lexeme;
                    } else {
                        label = name;
                        id = alias.lexeme;
                    }
                }
            }

            State? scope = parent;
            foreach (string outer in path) {
                var composite = declare_state(scope, outer, line);
                if (composite.state_type == StateType.SIMPLE) {
                    composite.state_type = StateType.COMPOSITE;
                }
                scope = composite;
            }
            // The id is known before the state is looked up: "[*] --> NS" then
            // "state \"Not Shooting\" as NS { }" made a state "Not Shooting" renamed to NS,
            // beside the NS the transition had created (a ghost box next to the cluster)
            var state = declare_state(scope, id, line);
            if (label != null) {
                state.label = label;
            }

            // Stereotype and inline colour before the body ("state HardwareSetup #lightblue {")
            parse_state_stereotype(state);
            parse_state_colors(state);
            parse_state_stereotype(state);

            if (match(TokenType.LBRACE)) {
                parse_state_body(state);
            }

            if (match(TokenType.COLON)) {
                parse_state_description(state, consume_text_line());
            }

            expect_end_of_statement();
        }

        // Stereotype after a state name: <<choice>>, <<fork>>, <<join>>, <<start>>, <<end>>,
        // <<history>>, <<history*>>, <<sdlreceive>>, <<entryPoint>>, <<exitPoint>>, pins and
        // expansion nodes, or any other kept as an annotation
        private void parse_state_stereotype(State state) {
            if (!match(TokenType.STEREOTYPE)) {
                return;
            }
            string stereo = previous().lexeme.strip().down();
            state.stereotype = stereo;
            switch (stereo) {
                case "choice":
                    state.state_type = StateType.CHOICE;
                    break;
                case "fork":
                    state.state_type = StateType.FORK;
                    break;
                case "join":
                    state.state_type = StateType.JOIN;
                    break;
                case "start":
                    state.state_type = StateType.INITIAL;
                    break;
                case "end":
                    state.state_type = StateType.END_STATE;
                    break;
                case "history":
                    state.state_type = StateType.HISTORY;
                    break;
                case "history*":
                    state.state_type = StateType.DEEP_HISTORY;
                    break;
                case "sdlreceive":
                    state.state_type = StateType.SDL_RECEIVE;
                    break;
                case "entrypoint":
                    state.state_type = StateType.ENTRY_POINT;
                    break;
                case "exitpoint":
                    state.state_type = StateType.EXIT_POINT;
                    break;
                case "inputpin":
                    state.state_type = StateType.INPUT_PIN;
                    break;
                case "outputpin":
                    state.state_type = StateType.OUTPUT_PIN;
                    break;
                case "expansioninput":
                    state.state_type = StateType.EXPANSION_INPUT;
                    break;
                case "expansionoutput":
                    state.state_type = StateType.EXPANSION_OUTPUT;
                    break;
                default:
                    break;
            }
        }

        private static bool is_word_token(Token t) {
            return t.token_type != TokenType.STRING && t.token_type != TokenType.NEWLINE &&
                   t.token_type != TokenType.EOF && t.lexeme.length > 0 &&
                   (t.lexeme.get_char(0).isalnum() || t.lexeme[0] == '_');
        }

        // Colour spec after a state name: "#pink", "#pink;line:red;line.dashed;text:blue",
        // "#back:pink;text:white", "##[dashed]red". The lexer's scan_color() returns "#RRGGBB"
        // or "#name" as a single IDENTIFIER. Only that first token was read; inside a
        // composite the rest ("line:red") then became a description line of a state "line".
        private void parse_state_colors(State state) {
            if (check(TokenType.IDENTIFIER) && peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                string first = advance().lexeme;
                string key = first.substring(1).down();
                if ((key == "back" || key == "line" || key == "text") && check(TokenType.COLON) &&
                    !peek().space_before) {
                    apply_state_color_item(state, key);
                } else if (key == "line" && peek().lexeme == "." && !peek().space_before) {
                    apply_state_color_item(state, key);
                } else {
                    state.color = first;
                }
                while (check(TokenType.SEMICOLON) && !peek().space_before && current + 1 < tokens.size &&
                       is_word_token(tokens[current + 1]) && !tokens[current + 1].space_before) {
                    advance();
                    apply_state_color_item(state, advance().lexeme.down());
                }
            } else if (match(TokenType.HASH)) {
                state.color = "#" + collect_color();
            }
            // "##red" / "##[dashed]red" / "##[bold]": border colour and style
            if (check(TokenType.IDENTIFIER) && peek().lexeme == "#" && current + 1 < tokens.size &&
                !tokens[current + 1].space_before && tokens[current + 1].lexeme.has_prefix("#")) {
                advance();
                Token second = advance();
                if (second.lexeme.length > 1) {
                    state.line_color = second.lexeme;
                } else {
                    if (check(TokenType.LBRACKET) && !peek().space_before) {
                        advance();
                        while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                            set_state_line_style(state, advance().lexeme.down());
                        }
                        match(TokenType.RBRACKET);
                    }
                    if (check(TokenType.IDENTIFIER) && !peek().space_before && is_word_token(peek())) {
                        state.line_color = "#" + advance().lexeme;
                    } else if (check(TokenType.IDENTIFIER) && !peek().space_before &&
                               peek().lexeme.has_prefix("#") && peek().lexeme.length > 1) {
                        state.line_color = advance().lexeme;
                    }
                }
            }
        }

        private static void set_state_line_style(State state, string style) {
            if (style == "dashed" || style == "dotted" || style == "bold") {
                state.line_style = style;
            }
        }

        // One item of a colour spec, the key already read: "back:X", "line:X", "text:X",
        // or "line.dashed" / "line.dotted" / "line.bold"
        private void apply_state_color_item(State state, string key) {
            if (key == "line" && peek().lexeme == "." && !peek().space_before &&
                current + 1 < tokens.size && !tokens[current + 1].space_before) {
                advance();
                set_state_line_style(state, advance().lexeme.down());
                return;
            }
            if (!check(TokenType.COLON) || peek().space_before || current + 1 >= tokens.size ||
                tokens[current + 1].space_before || !is_word_token(tokens[current + 1])) {
                return;
            }
            advance();  // ':'
            string value = advance().lexeme;
            if (!value.has_prefix("#")) {
                value = "#" + value;
            }
            switch (key) {
                case "back": state.color = value; break;
                case "line": state.line_color = value; break;
                case "text": state.text_color = value; break;
                default: break;
            }
        }

        // Parse state description which may include entry/exit actions
        private void parse_state_description(State state, string desc) {
            string lower = desc.down();
            if (lower.has_prefix("entry /") || lower.has_prefix("entry/")) {
                int slash_pos = desc.index_of("/");
                if (slash_pos >= 0) {
                    state.entry_action = desc.substring(slash_pos + 1).strip();
                }
            } else if (lower.has_prefix("exit /") || lower.has_prefix("exit/")) {
                int slash_pos = desc.index_of("/");
                if (slash_pos >= 0) {
                    state.exit_action = desc.substring(slash_pos + 1).strip();
                }
            } else {
                append_description(state, desc);
            }
        }

        // PlantUML accumulates repeated "State : text" lines into one
        // multi-line description; plain assignment kept only the last line.
        private void append_description(State state, string text) {
            if (state.description == null || state.description.length == 0) {
                state.description = text;
            } else {
                state.description = state.description + "\n" + text;
            }
        }

        // True when `inner` is `outer` or drawn somewhere inside it
        private static bool state_contains(State outer, State inner) {
            if (outer == inner) {
                return true;
            }
            foreach (var child in outer.nested_states) {
                if (state_contains(child, inner)) {
                    return true;
                }
            }
            return false;
        }

        // Removes a state from whichever list currently holds it (top level or a composite)
        private void detach_state(State s) {
            if (diagram.states.remove(s)) {
                return;
            }
            foreach (var top in diagram.states) {
                if (detach_from(top, s)) {
                    return;
                }
            }
        }

        private static bool detach_from(State container, State s) {
            if (container.nested_states.remove(s)) {
                return true;
            }
            foreach (var child in container.nested_states) {
                if (detach_from(child, s)) {
                    return true;
                }
            }
            return false;
        }

        private void parse_state_body(State parent) {
            parent.state_type = StateType.COMPOSITE;
            open_regions.set(parent, 0);
            skip_newlines();

            // An unclosed body ends at @enduml; it used to swallow it
            while (!check(TokenType.RBRACE) && !check(TokenType.ENDUML) && !is_at_end()) {
                skip_newlines();

                if (check(TokenType.RBRACE) || check(TokenType.ENDUML)) {
                    break;
                }
                int before = current;

                if (check(TokenType.STATE) || is_state_keyword()) {
                    try {
                        parse_state_declaration(parent);
                    } catch (Error e) {
                        expect_end_of_statement();
                    }
                }
                // "--" / "||" alone on a line: the next concurrent region. The line was
                // skipped and all regions were drawn as one.
                else if (is_region_separator()) {
                    string sep = check(TokenType.MINUS_MINUS) ? "--" : "||";
                    if (parent.region_separator == null) {
                        parent.region_separator = sep;
                    }
                    open_regions.set(parent, open_regions.get(parent) + 1);
                    expect_end_of_statement();
                }
                else if (check(TokenType.NOTE)) {
                    parse_note();
                }
                // "Name : text" — a description line. PlantUML lets a state describe
                // itself inside its own braces (state IDLE { IDLE : Entry: ... }).
                else if ((check(TokenType.IDENTIFIER) || check(TokenType.STRING)) && check_next(TokenType.COLON)) {
                    string name = advance().lexeme;
                    advance();  // ':'
                    string text = consume_text_line();
                    State? target = null;
                    if (name == parent.id || name == parent.label) {
                        target = parent;
                    } else {
                        foreach (var child in parent.nested_states) {
                            if (child.id == name || child.label == name) {
                                target = child;
                                break;
                            }
                        }
                        if (target == null) {
                            target = new State(name);
                            add_to_scope(parent, target);
                        }
                    }
                    parse_state_description(target, text);
                }
                // Transition inside composite state
                else if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || check(TokenType.INITIAL_FINAL) ||
                         check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) {
                    parse_transition_or_state(parent);
                }
                else {
                    advance();
                }

                if (current == before) {
                    advance();
                }
                skip_newlines();
            }

            match(TokenType.RBRACE);
            open_regions.unset(parent);

            // Braces holding only the state's own description lines are not a
            // composite. Left COMPOSITE it rendered as an empty cluster and the
            // state disappeared from the diagram.
            if (parent.nested_states.size == 0 && parent.nested_transitions.size == 0) {
                parent.state_type = StateType.SIMPLE;
                parent.region_separator = null;
            }
        }

        private bool is_region_separator() {
            if (check(TokenType.MINUS_MINUS)) {
                return current + 1 < tokens.size && (tokens[current + 1].token_type == TokenType.NEWLINE ||
                                                     tokens[current + 1].token_type == TokenType.EOF);
            }
            if (check(TokenType.PIPE) && current + 2 < tokens.size &&
                tokens[current + 1].token_type == TokenType.PIPE && !tokens[current + 1].space_before) {
                var after = tokens[current + 2];
                return after.token_type == TokenType.NEWLINE || after.token_type == TokenType.EOF;
            }
            return false;
        }

        // Skips one transition end ("[*]", "[H]", "Name", "Name[H*]") and reports whether an
        // arrow follows. The cursor is left where it was.
        private bool arrow_after_endpoint() {
            int start = current;
            if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                advance();
                if ((check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) && !peek().space_before) {
                    advance();
                }
            } else {
                advance();
            }
            bool arrow = read_state_arrow(true);
            current = start;
            return arrow;
        }

        // One transition end: "[*]" (the scope's start as a source, its end as a target),
        // "[H]" / "[H*]" (the scope's history), "Name", "\"Name\"", "Name[H]" / "Name[H*]"
        // (the history inside composite Name). Null with nothing consumed when there is none.
        private State? read_endpoint(State? parent, bool source) {
            if (match(TokenType.INITIAL_FINAL)) {
                return pseudo_state(parent, source ? StateType.INITIAL : StateType.FINAL);
            }
            if (check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) {
                bool deep = advance().token_type == TokenType.DEEP_HISTORY;
                return pseudo_state(parent, deep ? StateType.DEEP_HISTORY : StateType.HISTORY);
            }
            if (!check(TokenType.IDENTIFIER) && !check(TokenType.STRING)) {
                return null;
            }
            var named = resolve_named(parent, advance().lexeme);
            if ((check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) && !peek().space_before) {
                bool deep = advance().token_type == TokenType.DEEP_HISTORY;
                if (named.state_type == StateType.SIMPLE) {
                    named.state_type = StateType.COMPOSITE;
                }
                return pseudo_state(named, deep ? StateType.DEEP_HISTORY : StateType.HISTORY);
            }
            return named;
        }

        // A transition, a bare state reference or "\"Long name\" as Id", at the top level
        // (parent null) or inside a composite body
        private void parse_transition_or_state(State? parent) {
            // "\"Main state\" as M": a declaration without the keyword
            if (check(TokenType.STRING) && check_next(TokenType.AS)) {
                try {
                    parse_state_declaration(parent, false);
                } catch (Error e) {
                    expect_end_of_statement();
                }
                return;
            }

            // "State : description" (top level; a body handles its own description lines)
            if (parent == null && (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) &&
                check_next(TokenType.COLON)) {
                var described = diagram.get_or_create_state(advance().lexeme);
                advance();  // ':'
                parse_state_description(described, consume_text_line());
                return;
            }

            if (!arrow_after_endpoint()) {
                // A bare reference: "Name" declares a state; "[H]" a history state
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    var bare = resolve_named(parent, advance().lexeme);
                    parse_state_stereotype(bare);
                } else if (check(TokenType.HISTORY) || check(TokenType.DEEP_HISTORY)) {
                    read_endpoint(parent, true);
                } else {
                    advance();
                }
                expect_end_of_statement();
                return;
            }

            State? from_state = read_endpoint(parent, true);
            if (from_state == null || !read_state_arrow(true)) {
                expect_end_of_statement();
                return;
            }
            string arrow_text = last_arrow;
            string direction = arrow_direction;
            string? color = arrow_color;
            string? style = arrow_style;

            State? to_state = read_endpoint(parent, false);
            if (to_state == null) {
                expect_end_of_statement();
                return;
            }
            // "sin2 --> exitA <<exitPoint>>": the stereotype belongs to the target
            // (as PlantUML 1.2026.1 draws it)
            parse_state_stereotype(to_state);

            arrow_direction = direction;
            arrow_color = color;
            arrow_style = style;
            var transition = new StateTransition(from_state, to_state);
            apply_arrow(transition);
            int line_chars = 0;
            for (int i = 0; i < arrow_text.length; i++) {
                if (arrow_text[i] == '-' || arrow_text[i] == '.') {
                    line_chars++;
                }
            }
            transition.arrow_length = line_chars;

            if (match(TokenType.COLON)) {
                parse_transition_label(transition, consume_text_line());
            }

            if (parent == null) {
                diagram.transitions.add(transition);
            } else {
                parent.nested_transitions.add(transition);
            }
            last_transition = transition;
            expect_end_of_statement();
        }

        // Details of the arrow read last by read_state_arrow()
        private string arrow_direction = "";
        private string? arrow_color = null;
        private string? arrow_style = null;
        private string last_arrow = "";

        private static bool is_state_arrow_piece(Token t) {
            switch (t.token_type) {
                case TokenType.ARROW_RIGHT:
                case TokenType.ARROW_RIGHT_DOTTED:
                case TokenType.MINUS_MINUS:
                case TokenType.MINUS:
                    return true;
                case TokenType.IDENTIFIER:
                    return t.lexeme == ">";
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

        // Reads a transition arrow from adjacent tokens: "->", "-->", "-up->", "-[#red]->",
        // "-[dashed,#blue]left->". Direction and options go to arrow_direction / arrow_color /
        // arrow_style. A plain "--" counts only when allow_plain is set. Returns false with
        // the cursor unchanged when there is no arrow here.
        private bool read_state_arrow(bool allow_plain) {
            arrow_direction = "";
            arrow_color = null;
            arrow_style = null;
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
                    break;
                }
                bool after_line = text.has_suffix("-") || text.has_suffix(".");
                string? dir = after_line && arrow_direction == "" ? direction_word(t.lexeme) : null;
                if (is_state_arrow_piece(t) && (!first || t.lexeme != ">")) {
                    sb.append(t.lexeme);
                    advance();
                } else if (dir != null && check_next_piece()) {
                    arrow_direction = dir;
                    advance();
                } else if (after_line && t.token_type == TokenType.LBRACKET) {
                    advance();  // [
                    while (!check(TokenType.RBRACKET) && !check(TokenType.NEWLINE) && !is_at_end()) {
                        string opt = advance().lexeme.strip();
                        string low = opt.down();
                        if (low == "dashed") {
                            arrow_style = "dashed";
                        } else if (low == "dotted" || low == "bold") {
                            arrow_style = low;
                        } else if (low == "hidden") {
                            arrow_style = "invis";
                        } else if (opt.has_prefix("#") && opt.length > 1) {
                            arrow_color = opt;
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
            if (arrow.contains("-") && (arrow.has_suffix(">") || (allow_plain && arrow == "--"))) {
                last_arrow = arrow;
                return true;
            }
            current = start;
            arrow_direction = "";
            arrow_color = null;
            arrow_style = null;
            return false;
        }

        // The token after the cursor continues an arrow, written without a space
        private bool check_next_piece() {
            if (current + 1 >= tokens.size) {
                return false;
            }
            var n = tokens.get(current + 1);
            return !n.space_before && (is_state_arrow_piece(n) || n.token_type == TokenType.LBRACKET);
        }

        private void apply_arrow(StateTransition transition) {
            transition.direction = arrow_direction;
            if (arrow_color != null) {
                transition.color = arrow_color;
            }
            if (arrow_style == "dashed") {
                transition.is_dashed = true;
            } else if (arrow_style != null) {
                transition.line_style = arrow_style;
            }
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

            // "note on link": a note beside the transition written just before it. It became
            // a floating note whose text started with "on link".
            StateTransition? link = null;
            if (check(TokenType.IDENTIFIER) && peek().lexeme.down() == "on" && current + 1 < tokens.size &&
                tokens[current + 1].lexeme.down() == "link") {
                advance();
                advance();
                link = last_transition;
                if (link == null) {
                    // nothing to attach to: read and drop the note body as PlantUML does
                    attached_to = "";
                }
            }

            // "of State" or just continue
            if (match(TokenType.OF)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    attached_to = advance().lexeme;
                }
            }

            // Floating note: note "text" as N1. PlantUML shows the text without its
            // quotes; it used to read on to "end note" and swallow the rest of the file.
            if (attached_to == null && link == null && check(TokenType.STRING) && check_next(TokenType.AS)) {
                var floating = new StateNote(advance().lexeme);
                advance();  // 'as'
                if (check(TokenType.IDENTIFIER)) {
                    floating.id = advance().lexeme;  // links name the note by its alias
                }
                floating.position = position;
                diagram.notes.add(floating);
                expect_end_of_statement();
                return;
            }

            // Floating block note: "note as N1" then a body up to "end note". The
            // alias names the note; it used to be shown as body text ("as N1").
            string? alias = null;
            if (attached_to == null && link == null && match(TokenType.AS)) {
                if (check(TokenType.IDENTIFIER) || check(TokenType.STRING)) {
                    alias = advance().lexeme;
                }
            }

            // Note text - can be single line or multi-line (end note)
            var sb = new StringBuilder();

            if (match(TokenType.COLON)) {
                // Single line note
                sb.append(consume_text_line());
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
                        sb.append(text_lexeme(body_tok));
                    }
                }
            }

            if (attached_to == "") {
                return;
            }
            var note = new StateNote(sb.str.strip());
            if (alias != null) note.id = alias;
            note.attached_to = attached_to;
            note.link = link;
            note.position = position;
            diagram.notes.add(note);
        }

        private string collect_color() {
            var sb = new StringBuilder();
            while (check(TokenType.IDENTIFIER) || check(TokenType.HASH)) {
                sb.append(advance().lexeme);
            }
            return sb.str;
        }

        private void parse_skinparam() {
            string first_name = "";
            // Any token can name the element: "note", "class", "component" and
            // "package" lex as keywords. Rejecting them skipped only the first
            // line, and the block body was then parsed as STATES named after
            // its properties (BackgroundColor, FontColor, ...).
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

                // BackgroundColor<<stereotype>> — fold the stereotype into the
                // key so each declaration gets its own entry instead of the
                // last one overwriting every other.
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

        // Rest of the line as displayed text. The lexer strips the quotes off a
        // STRING token, but PlantUML shows them in state descriptions, transition
        // labels and notes ("Outer : then \"retries\"" keeps its quotes).
        private string consume_text_line() {
            var sb = new StringBuilder();

            while (!check(TokenType.NEWLINE) && !is_at_end()) {
                Token t = advance();
                if (sb.len > 0 && t.space_before) {
                    sb.append(" ");
                }
                sb.append(text_lexeme(t));
            }

            return sb.str.strip();
        }

        private static string text_lexeme(Token t) {
            if (t.token_type == TokenType.STRING) {
                return "\"" + t.lexeme + "\"";
            }
            return t.lexeme;
        }

        // Parse transition label to extract event, guard, and action
        // Format: event [guard] / action
        private void parse_transition_label(StateTransition transition, string label) {
            string text = label.strip();
            if (text.length == 0) {
                return;
            }

            // Extract guard: text between [ and ]
            int guard_start = text.index_of("[");
            int guard_end = text.index_of("]");
            if (guard_start >= 0 && guard_end > guard_start) {
                transition.guard = text.substring(guard_start + 1, guard_end - guard_start - 1).strip();
                // Remove guard from text
                text = text.substring(0, guard_start) + text.substring(guard_end + 1);
                text = text.strip();
            }

            // Extract action: text after /
            int action_pos = text.index_of("/");
            if (action_pos >= 0) {
                transition.action = text.substring(action_pos + 1).strip();
                text = text.substring(0, action_pos).strip();
            }

            // Remaining text is the event/trigger
            if (text.length > 0) {
                transition.label = text;
            }
        }

        private void expect_end_of_statement() {
            // Not past @enduml: after an unclosed "state X {" body it was consumed here
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
                    case TokenType.STATE:
                    case TokenType.INITIAL_FINAL:
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
