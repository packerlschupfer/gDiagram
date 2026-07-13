namespace GDiagram {
    /**
     * Preprocessor handles PlantUML preprocessing directives before lexing.
     *
     * Supported directives:
     * - !include <filename>  - Include another file (relative or absolute path)
     * - !include <filename>  - Include from standard library (future)
     *
     * Future support:
     * - !define NAME VALUE   - Define a macro
     * - !ifdef/!endif        - Conditional compilation
     * - !theme               - Theme directive
     *
     * Usage:
     *   var preprocessor = new Preprocessor();
     *   string processed = preprocessor.process(source, base_path);
     *   var lexer = new Lexer(processed);
     */
    public class Preprocessor : Object {
        // Track included files to prevent circular includes
        private Gee.HashSet<string> included_files;

        // Macro table: name -> Macro. Covers !define, !procedure, !unquoted
        // procedure, and !function. Simple !define NAME VALUE is stored as a
        // Macro with no parameters and a one-line body.
        // Persists across includes within a single process() call.
        private Gee.HashMap<string, Macro> macros;

        // Maximum macro expansion recursion depth, to break infinite loops.
        private const int MAX_MACRO_DEPTH = 32;

        // Per-call cycle detection: the set of macro names currently being
        // expanded. Re-entering an in-progress macro is treated as a recursive
        // call and the inner call is NOT expanded (left as literal). This
        // breaks both direct (Foo calls Foo) and indirect (Foo→Bar→Foo)
        // cycles without penalising sibling calls or top-level user code.
        // Cleared at the start of every top-level expand_macros() call so
        // that two unrelated user calls don't see each other's state.
        private Gee.HashSet<string> expanding_macros;

        // Stack of conditional frames for !if/!ifdef/!ifndef/!else/!endif.
        // Each frame tracks whether the current branch should emit lines and
        // whether any branch in the chain has already been taken (for !elseif).
        private Gee.ArrayList<IfFrame> if_stack;

        // Maximum include depth to prevent infinite recursion
        private const int MAX_INCLUDE_DEPTH = 10;

        // Errors encountered during preprocessing
        public Gee.ArrayList<PreprocessorError> errors { get; private set; }

        public Preprocessor() {
            this.included_files = new Gee.HashSet<string>();
            this.macros = new Gee.HashMap<string, Macro>();
            this.if_stack = new Gee.ArrayList<IfFrame>();
            this.expanding_macros = new Gee.HashSet<string>();
            this.errors = new Gee.ArrayList<PreprocessorError>();
        }

        /**
         * Process source content, expanding all preprocessor directives.
         *
         * @param source The PlantUML source content
         * @param base_path The directory path for resolving relative includes (can be null)
         * @return The preprocessed source with all includes expanded
         */
        public string process(string source, string? base_path) {
            included_files.clear();
            macros.clear();
            if_stack.clear();
            expanding_macros.clear();
            errors.clear();
            return process_internal(source, base_path, 0);
        }

        /**
         * True iff every frame in the if-stack is currently active. When
         * false, the line loop suppresses both directive execution (except
         * for the conditional directives themselves) and text output.
         */
        private bool is_emitting() {
            foreach (var frame in if_stack) {
                if (!frame.active) return false;
            }
            return true;
        }

        private string process_internal(string source, string? base_path, int depth) {
            if (depth > MAX_INCLUDE_DEPTH) {
                errors.add(new PreprocessorError(
                    "Maximum include depth (%d) exceeded - possible circular include".printf(MAX_INCLUDE_DEPTH),
                    0
                ));
                return source;
            }

            var result = new StringBuilder();
            var lines = source.split("\n");
            int line_num = 0;
            int idx = 0;
            int while_depth = 0;

            while (idx < lines.length) {
                string line = lines[idx];
                line_num = idx + 1;
                string trimmed = line.strip();

                // !while ... !endwhile is treated as "skip body" (degraded
                // — we don't iterate). Handled before everything else so the
                // body can't trigger procedure detection or other directives.
                if (trimmed.has_prefix("!while ") || trimmed.has_prefix("!while\t")) {
                    while_depth++;
                    result.append("\n");
                    idx++;
                    continue;
                }
                if (trimmed == "!endwhile" || trimmed.has_prefix("!endwhile ")) {
                    if (while_depth > 0) while_depth--;
                    result.append("\n");
                    idx++;
                    continue;
                }
                if (while_depth > 0) {
                    result.append("\n");
                    idx++;
                    continue;
                }

                // Conditional directives are processed in every state because
                // they're how we escape an inactive branch. Emit a blank
                // placeholder line so error line numbers remain stable.
                if (is_conditional_directive(trimmed)) {
                    process_conditional_directive(trimmed, line_num);
                    result.append("\n");
                    idx++;
                    continue;
                }

                // Everything else is suppressed when we're inside an inactive branch.
                if (!is_emitting()) {
                    idx++;
                    continue;
                }

                if (trimmed.has_prefix("!include ") || trimmed.has_prefix("!include\t")) {
                    string include_content = process_include_directive(trimmed, base_path, depth, line_num);
                    result.append(expand_macros(include_content, 0));
                    idx++;
                } else if (is_procedure_start(trimmed)) {
                    // Collect lines until matching !endprocedure / !enddefinelong
                    int proc_end = find_matching_proc_end(lines, idx);
                    if (proc_end < 0) {
                        errors.add(new PreprocessorError(
                            "Unterminated !procedure (no matching !endprocedure)",
                            line_num));
                        // Treat the whole rest of the file as the body to avoid
                        // dropping content silently
                        proc_end = lines.length - 1;
                    }
                    process_procedure_directive(lines, idx, proc_end, line_num);
                    // Emit blank lines to keep error line numbers stable
                    for (int k = idx; k <= proc_end && k < lines.length; k++) {
                        result.append("\n");
                    }
                    idx = proc_end + 1;
                } else if (trimmed.has_prefix("!define ") || trimmed.has_prefix("!define\t")) {
                    process_define_directive(trimmed, line_num);
                    result.append("\n");
                    idx++;
                } else if (trimmed.has_prefix("!$")) {
                    process_var_assign_directive(trimmed, line_num);
                    result.append("\n");
                    idx++;
                } else if (trimmed.has_prefix("!undef ") || trimmed.has_prefix("!undef\t")) {
                    process_undef_directive(trimmed);
                    result.append("\n");
                    idx++;
                } else if (trimmed.has_prefix("!")) {
                    // Other (unsupported) preprocessor directives — drop silently
                    result.append("\n");
                    idx++;
                } else {
                    result.append(expand_macros(line, 0));
                    result.append("\n");
                    idx++;
                }
            }

            return result.str;
        }

        /**
         * True for any !if/!ifdef/!ifndef/!else/!elseif/!endif directive.
         */
        private bool is_conditional_directive(string trimmed) {
            return trimmed.has_prefix("!if ") || trimmed.has_prefix("!if\t") ||
                   trimmed.has_prefix("!ifdef ") || trimmed.has_prefix("!ifdef\t") ||
                   trimmed.has_prefix("!ifndef ") || trimmed.has_prefix("!ifndef\t") ||
                   trimmed.has_prefix("!elseif ") || trimmed.has_prefix("!elseif\t") ||
                   trimmed == "!else" || trimmed.has_prefix("!else ") ||
                   trimmed == "!endif" || trimmed.has_prefix("!endif ");
        }

        /**
         * Update the if-stack in response to a conditional directive.
         *
         *   !ifdef NAME    push frame, active = NAME is defined
         *   !ifndef NAME   push frame, active = NAME is NOT defined
         *   !if EXPR       push frame, active = (eval of EXPR) — until task #13
         *                  lands, EXPR is evaluated as "always true" with a
         *                  warning so we don't silently drop the body.
         *   !elseif EXPR   reuse top frame, active = !taken && (eval EXPR)
         *   !else          reuse top frame, active = !taken
         *   !endif         pop frame
         *
         * "taken" tracks whether any branch of the current chain has yet
         * emitted lines, so subsequent branches stay inactive.
         */
        private void process_conditional_directive(string trimmed, int line_num) {
            if (trimmed.has_prefix("!ifdef")) {
                string name = trimmed.substring(6).strip();
                bool defined = macros.has_key(name);
                push_if_frame(defined);
            } else if (trimmed.has_prefix("!ifndef")) {
                string name = trimmed.substring(7).strip();
                bool defined = macros.has_key(name);
                push_if_frame(!defined);
            } else if (trimmed.has_prefix("!if ") || trimmed.has_prefix("!if\t")) {
                string expr = trimmed.substring(3).strip();
                bool truth = evaluate_expression(expr);
                push_if_frame(truth);
            } else if (trimmed.has_prefix("!elseif")) {
                if (if_stack.size == 0) {
                    errors.add(new PreprocessorError(
                        "!elseif without matching !if/!ifdef", line_num));
                    return;
                }
                var frame = if_stack[if_stack.size - 1];
                if (frame.taken) {
                    frame.active = false;
                } else {
                    string expr = trimmed.substring(7).strip();
                    bool truth = evaluate_expression(expr);
                    frame.active = truth;
                    if (truth) frame.taken = true;
                }
            } else if (trimmed == "!else" || trimmed.has_prefix("!else ")) {
                if (if_stack.size == 0) {
                    errors.add(new PreprocessorError(
                        "!else without matching !if/!ifdef", line_num));
                    return;
                }
                var frame = if_stack[if_stack.size - 1];
                if (frame.taken) {
                    frame.active = false;
                } else {
                    frame.active = true;
                    frame.taken = true;
                }
            } else if (trimmed == "!endif" || trimmed.has_prefix("!endif ")) {
                if (if_stack.size == 0) {
                    errors.add(new PreprocessorError(
                        "!endif without matching !if/!ifdef", line_num));
                    return;
                }
                if_stack.remove_at(if_stack.size - 1);
            }
        }

        private void push_if_frame(bool initially_active) {
            var frame = new IfFrame();
            frame.active = initially_active;
            frame.taken = initially_active;
            if_stack.add(frame);
        }

        /**
         * Evaluate a preprocessor expression in boolean context. Used for
         * !if and !elseif. Returns true on parse error so we don't silently
         * skip the body.
         */
        private bool evaluate_expression(string expr) {
            var ev = new PreprocessorExpression(expr, macros);
            return ev.evaluate_bool();
        }

        /**
         * True if `trimmed` opens a multi-line procedure or function block.
         * Recognizes:
         *   !procedure NAME(...)
         *   !unquoted procedure NAME(...)
         *   !function NAME(...)
         * Function support is added by Task 12; we recognize the keyword here
         * so the body collection works for both.
         */
        private bool is_procedure_start(string trimmed) {
            return trimmed.has_prefix("!procedure ") ||
                   trimmed.has_prefix("!procedure\t") ||
                   trimmed.has_prefix("!unquoted procedure ") ||
                   trimmed.has_prefix("!unquoted procedure\t") ||
                   trimmed.has_prefix("!function ") ||
                   trimmed.has_prefix("!function\t") ||
                   trimmed.has_prefix("!unquoted function ") ||
                   trimmed.has_prefix("!unquoted function\t") ||
                   trimmed.has_prefix("!definelong ") ||
                   trimmed.has_prefix("!definelong\t");
        }

        /**
         * Given the line index of a procedure-start directive, scan forward
         * for the matching !endprocedure / !endfunction / !enddefinelong.
         * Returns the line index of the end directive, or -1 if not found.
         * Handles nested procedures by tracking depth.
         */
        private int find_matching_proc_end(string[] lines, int start) {
            int depth = 1;
            for (int k = start + 1; k < lines.length; k++) {
                string t = lines[k].strip();
                if (is_procedure_start(t)) {
                    depth++;
                } else if (is_procedure_end(t)) {
                    depth--;
                    if (depth == 0) return k;
                }
            }
            return -1;
        }

        /**
         * True for any !endprocedure / !endfunction / !enddefinelong terminator.
         * Accepts both "!endfunction" and "!end function" forms (PlantUML
         * tolerates a space between !end and function — used in some C4
         * stdlib files).
         */
        private bool is_procedure_end(string trimmed) {
            return trimmed == "!endprocedure" || trimmed.has_prefix("!endprocedure ") ||
                   trimmed == "!endfunction" || trimmed.has_prefix("!endfunction ") ||
                   trimmed == "!end procedure" || trimmed.has_prefix("!end procedure ") ||
                   trimmed == "!end function" || trimmed.has_prefix("!end function ") ||
                   trimmed == "!enddefinelong" || trimmed.has_prefix("!enddefinelong ");
        }

        /**
         * Parse a multi-line procedure or function definition spanning
         * lines[start..end]. The first line is the directive itself, all
         * lines in between are the body, the last line is !endprocedure /
         * !endfunction / !enddefinelong (or the EOF if we recovered from
         * a missing terminator).
         */
        private void process_procedure_directive(string[] lines, int start, int end, int line_num) {
            string head = lines[start].strip();

            bool is_unquoted = false;
            bool is_function = false;
            string after_kw;

            if (head.has_prefix("!unquoted procedure")) {
                is_unquoted = true;
                after_kw = head.substring("!unquoted procedure".length).strip();
            } else if (head.has_prefix("!unquoted function")) {
                is_unquoted = true;
                is_function = true;
                after_kw = head.substring("!unquoted function".length).strip();
            } else if (head.has_prefix("!procedure")) {
                after_kw = head.substring("!procedure".length).strip();
            } else if (head.has_prefix("!function")) {
                is_function = true;
                after_kw = head.substring("!function".length).strip();
            } else if (head.has_prefix("!definelong")) {
                // Treated as a procedure for body-collection purposes
                after_kw = head.substring("!definelong".length).strip();
            } else {
                return;
            }

            // Parse name (allow optional $ prefix on the name itself, which
            // PlantUML uses for "private" procedures like $defineSkinparams)
            int i = 0;
            if (i < after_kw.length && after_kw[i] == '$') i++;
            int name_start = i;
            while (i < after_kw.length) {
                char c = after_kw[i];
                bool is_name_char = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                    (c == '_') || (i > name_start && c >= '0' && c <= '9');
                if (!is_name_char) break;
                i++;
            }
            if (i == name_start) {
                errors.add(new PreprocessorError(
                    "Expected procedure name after directive", line_num));
                return;
            }
            string name = after_kw.substring(name_start, i - name_start);

            var macro = new Macro(name);
            macro.is_unquoted = is_unquoted;
            macro.is_function = is_function;
            macro.is_parameterized = true;  // procedures always use call syntax
            macro.is_procedure = true;      // suppresses bare-name substitution

            // Optional parameter list
            if (i < after_kw.length && after_kw[i] == '(') {
                int paren_end;
                var param_list = parse_parameter_list(after_kw, i, out paren_end, line_num);
                if (param_list == null) return;
                macro.parameters = param_list;
            }

            // Collect body lines (lines[start+1 .. end-1])
            for (int k = start + 1; k < end && k < lines.length; k++) {
                macro.body.add(lines[k]);
            }

            macros.set(name, macro);
        }

        /**
         * Parse "!define NAME VALUE", "!define NAME(p1, p2) BODY",
         * or "!define NAME" (empty value).
         */
        private void process_define_directive(string line, int line_num) {
            // Strip "!define" + leading whitespace
            string body_text = line.substring(7).strip();
            if (body_text.length == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !define directive: missing name", line_num));
                return;
            }

            // Parse the name (identifier characters until '(' or whitespace)
            int i = 0;
            while (i < body_text.length) {
                char c = body_text[i];
                bool is_name_char = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                    (c == '_') || (i > 0 && c >= '0' && c <= '9');
                if (!is_name_char) break;
                i++;
            }

            if (i == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !define directive: missing name", line_num));
                return;
            }

            string name = body_text.substring(0, i);
            if (!is_valid_define_name(name)) {
                errors.add(new PreprocessorError(
                    "Invalid !define name '%s'".printf(name), line_num));
                return;
            }

            var macro = new Macro(name);

            // Check for parameterized form: NAME(p1, p2) BODY
            if (i < body_text.length && body_text[i] == '(') {
                int paren_end;
                var param_list = parse_parameter_list(body_text, i, out paren_end, line_num);
                if (param_list == null) return;  // error already logged
                macro.parameters = param_list;
                macro.is_parameterized = true;
                i = paren_end + 1;  // skip past closing ')'
            }

            // Skip whitespace before the body
            while (i < body_text.length && (body_text[i] == ' ' || body_text[i] == '\t')) {
                i++;
            }

            // Everything after the name (and optional param list and whitespace) is the body.
            string value = (i < body_text.length) ? body_text.substring(i) : "";
            macro.body.add(value);

            macros.set(name, macro);
        }

        /**
         * Parse a "(p1, p2, p3=default)" parameter list starting at `start`
         * (which must point at the open paren). Returns the list of parameters
         * and sets `end` to the index of the closing paren. Returns null on
         * error (and logs to errors).
         *
         * Parameter names are accepted with or without a leading '$' (PlantUML
         * canonically uses '$' inside procedure bodies but the param list can
         * use either form). The leading '$' is stripped before storing.
         */
        private Gee.ArrayList<MacroParameter>? parse_parameter_list(string text, int start, out int end, int line_num) {
            end = start;
            var list = new Gee.ArrayList<MacroParameter>();
            if (start >= text.length || text[start] != '(') {
                errors.add(new PreprocessorError(
                    "Expected '(' in parameter list", line_num));
                return null;
            }

            int i = start + 1;
            while (i < text.length) {
                // Skip whitespace
                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;

                if (i >= text.length) break;
                if (text[i] == ')') {
                    end = i;
                    return list;
                }

                // Parse parameter name
                int name_start = i;
                if (text[i] == '$') i++;  // skip optional $ prefix
                int name_real_start = i;
                while (i < text.length) {
                    char c = text[i];
                    bool is_name_char = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                        (c == '_') || (i > name_real_start && c >= '0' && c <= '9');
                    if (!is_name_char) break;
                    i++;
                }
                if (i == name_real_start) {
                    errors.add(new PreprocessorError(
                        "Expected parameter name in parameter list", line_num));
                    return null;
                }
                string param_name = text.substring(name_real_start, i - name_real_start);

                // Optional default value: =VALUE or ="VALUE"
                string? default_value = null;
                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                if (i < text.length && text[i] == '=') {
                    i++;
                    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                    int v_start = i;
                    if (i < text.length && (text[i] == '"' || text[i] == '\'')) {
                        // Quoted default — read until matching close quote
                        char quote = text[i];
                        i++;
                        v_start = i;
                        while (i < text.length && text[i] != quote) i++;
                        default_value = text.substring(v_start, i - v_start);
                        if (i < text.length) i++;  // skip closing quote
                    } else {
                        // Bare default — read until ',' or ')'
                        while (i < text.length && text[i] != ',' && text[i] != ')') i++;
                        default_value = text.substring(v_start, i - v_start).strip();
                    }
                }

                list.add(new MacroParameter(param_name, default_value));

                // Skip trailing whitespace and consume optional comma
                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                if (i < text.length && text[i] == ',') {
                    i++;
                    continue;
                }
                if (i < text.length && text[i] == ')') {
                    end = i;
                    return list;
                }
            }

            errors.add(new PreprocessorError(
                "Unterminated parameter list (missing ')')", line_num));
            return null;
        }

        /**
         * Handle "!$NAME = EXPR" (unconditional) and "!$NAME ?= EXPR"
         * (conditional — assigns only if NAME is not already defined).
         * The RHS is evaluated through the expression evaluator.
         */
        private void process_var_assign_directive(string line, int line_num) {
            // Strip leading !$
            string body = line.substring(2);
            // Read name
            int i = 0;
            while (i < body.length) {
                char c = body[i];
                bool is_name_char = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                    (c == '_') || (i > 0 && c >= '0' && c <= '9');
                if (!is_name_char) break;
                i++;
            }
            if (i == 0) {
                errors.add(new PreprocessorError("Invalid !$var assignment: missing name", line_num));
                return;
            }
            string name = body.substring(0, i);
            // Skip whitespace
            while (i < body.length && (body[i] == ' ' || body[i] == '\t')) i++;
            bool conditional = false;
            if (i + 1 < body.length && body[i] == '?' && body[i + 1] == '=') {
                conditional = true;
                i += 2;
            } else if (i < body.length && body[i] == '=') {
                i += 1;
            } else {
                errors.add(new PreprocessorError("Invalid !$var assignment: missing '='", line_num));
                return;
            }
            string rhs = body.substring(i).strip();

            // Conditional ?= only assigns if not already defined
            if (conditional && macros.has_key(name)) return;

            // Evaluate the RHS as an expression
            var ev = new PreprocessorExpression(rhs, macros);
            string value = ev.evaluate();

            var macro = new Macro(name);
            macro.body.add(value);
            macros.set(name, macro);
        }

        private void process_undef_directive(string line) {
            string name = line.substring(6).strip();
            if (macros.has_key(name)) {
                macros.unset(name);
            }
        }

        private bool is_valid_define_name(string name) {
            if (name.length == 0) return false;
            for (int i = 0; i < name.length; i++) {
                char c = name[i];
                bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                          (c == '_') ||
                          (i > 0 && c >= '0' && c <= '9');
                if (!ok) return false;
            }
            return true;
        }

        /**
         * Expand all macro references in `line`. Handles both forms:
         *   - Simple substitution:    NAME           → macro.body[0]
         *   - Parameterized call:     NAME(a, b, c)  → expanded body with
         *                                              params replaced by args
         *
         * `depth` guards against infinite recursion (a macro that expands to
         * something containing its own name).
         */
        private string expand_macros(string line, int depth) {
            if (macros.size == 0) return line;
            if (depth > MAX_MACRO_DEPTH) return line;

            var sb = new StringBuilder();
            int i = 0;
            int n = line.length;

            while (i < n) {
                char c = line[i];

                // $NAME — look up a simple-define value or stringify a parameterized
                // macro by calling it through the expression evaluator.
                if (c == '$' && i + 1 < n) {
                    char nc = line[i + 1];
                    bool starts_ident = (nc >= 'A' && nc <= 'Z') || (nc >= 'a' && nc <= 'z') || nc == '_';
                    if (starts_ident) {
                        i++;  // consume the $
                        int name_start = i;
                        while (i < n) {
                            char xc = line[i];
                            bool is_name_char = (xc >= 'A' && xc <= 'Z') || (xc >= 'a' && xc <= 'z') ||
                                                (xc == '_') || (i > name_start && xc >= '0' && xc <= '9');
                            if (!is_name_char) break;
                            i++;
                        }
                        string ident = line.substring(name_start, i - name_start);
                        Macro? macro = macros.get(ident);
                        if (macro == null) {
                            // Unknown — preserve the literal $name so it shows up
                            // in output for diagnosis instead of disappearing.
                            sb.append("$").append(ident);
                            continue;
                        }
                        if (macro.is_parameterized) {
                            // Parameterized macro: only expand if followed by '('.
                            // Otherwise leave the $NAME literal so the body
                            // doesn't get dumped without its arguments.
                            if (i < n && line[i] == '(') {
                                int call_end;
                                var args = parse_argument_list(line, i, out call_end);
                                if (args != null) {
                                    if (expanding_macros.contains(macro.name)) {
                                        sb.append("$").append(ident).append("(");
                                        for (int a = 0; a < args.size; a++) {
                                            if (a > 0) sb.append(", ");
                                            sb.append(args[a]);
                                        }
                                        sb.append(")");
                                        i = call_end + 1;
                                        continue;
                                    }
                                    expanding_macros.add(macro.name);
                                    sb.append(expand_macro_call(macro, args, depth + 1));
                                    expanding_macros.remove(macro.name);
                                    i = call_end + 1;
                                    continue;
                                }
                            }
                            // Bare $NAME referencing a parameterized macro:
                            // leave literal so the body isn't emitted unkeyed.
                            sb.append("$").append(ident);
                            continue;
                        }
                        // Simple value substitution (recursively expand the value)
                        string value = macro.body.size > 0 ? macro.body[0] : "";
                        sb.append(expand_macros(value, depth + 1));
                        continue;
                    }
                }

                // Identifier-start: letter or underscore
                bool is_name_start = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
                if (!is_name_start) {
                    sb.append_c(c);
                    i++;
                    continue;
                }

                // Read the identifier
                int name_start2 = i;
                while (i < n) {
                    char nc2 = line[i];
                    bool is_name_char = (nc2 >= 'A' && nc2 <= 'Z') || (nc2 >= 'a' && nc2 <= 'z') ||
                                        (nc2 == '_') || (i > name_start2 && nc2 >= '0' && nc2 <= '9');
                    if (!is_name_char) break;
                    i++;
                }
                string ident2 = line.substring(name_start2, i - name_start2);

                Macro? macro2 = macros.get(ident2);
                if (macro2 == null) {
                    sb.append(ident2);
                    continue;
                }

                if (macro2.is_parameterized) {
                    if (i >= n || line[i] != '(') {
                        sb.append(ident2);
                        continue;
                    }
                    int call_end2;
                    var args2 = parse_argument_list(line, i, out call_end2);
                    if (args2 == null) {
                        sb.append(ident2);
                        continue;
                    }
                    // Cycle check: don't recursively expand a macro that's
                    // already on the in-progress stack. Leaving the call
                    // literal is better than infinite recursion.
                    if (expanding_macros.contains(macro2.name)) {
                        sb.append(ident2);
                        sb.append("(");
                        for (int a = 0; a < args2.size; a++) {
                            if (a > 0) sb.append(", ");
                            sb.append(args2[a]);
                        }
                        sb.append(")");
                        i = call_end2 + 1;
                        continue;
                    }
                    expanding_macros.add(macro2.name);
                    string expanded = expand_macro_call(macro2, args2, depth + 1);
                    expanding_macros.remove(macro2.name);
                    sb.append(expanded);
                    i = call_end2 + 1;
                } else {
                    string value = macro2.body.size > 0 ? macro2.body[0] : "";
                    sb.append(expand_macros(value, depth + 1));
                }
            }

            return sb.str;
        }

        /**
         * Parse a "(arg1, arg2, ...)" argument list starting at `start`
         * (which must point at the open paren). Respects nested parens and
         * quoted strings (so "Foo(Bar(x), \"a, b\")" parses as two args).
         * Sets `end` to the index of the closing paren.
         */
        private Gee.ArrayList<string>? parse_argument_list(string text, int start, out int end) {
            end = start;
            var list = new Gee.ArrayList<string>();
            if (start >= text.length || text[start] != '(') return null;

            int i = start + 1;
            int paren_depth = 1;
            var current = new StringBuilder();
            char in_quote = 0;

            while (i < text.length) {
                char c = text[i];

                if (in_quote != 0) {
                    current.append_c(c);
                    if (c == in_quote) in_quote = 0;
                    i++;
                    continue;
                }

                if (c == '"' || c == '\'') {
                    in_quote = c;
                    current.append_c(c);
                    i++;
                    continue;
                }

                if (c == '(') {
                    paren_depth++;
                    current.append_c(c);
                    i++;
                    continue;
                }

                if (c == ')') {
                    paren_depth--;
                    if (paren_depth == 0) {
                        // End of argument list
                        string arg = current.str.strip();
                        // Don't add an empty trailing arg from "Foo()"
                        if (list.size > 0 || arg.length > 0) {
                            list.add(arg);
                        }
                        end = i;
                        return list;
                    }
                    current.append_c(c);
                    i++;
                    continue;
                }

                if (c == ',' && paren_depth == 1) {
                    list.add(current.str.strip());
                    current = new StringBuilder();
                    i++;
                    continue;
                }

                current.append_c(c);
                i++;
            }

            return null;  // unterminated
        }

        /**
         * Expand a parameterized macro call. `args` are the call-site argument
         * strings (already trimmed); they may contain quotes which are kept
         * verbatim. Missing trailing arguments fall back to parameter defaults
         * (or empty string if neither given).
         */
        private string expand_macro_call(Macro macro, Gee.ArrayList<string> args, int depth) {
            // Build a per-call substitution map: param.name -> arg value
            var subs = new Gee.HashMap<string, string>();
            for (int p = 0; p < macro.parameters.size; p++) {
                var param = macro.parameters[p];
                string val;
                if (p < args.size) {
                    val = args[p];
                } else if (param.default_value != null) {
                    val = param.default_value;
                } else {
                    val = "";
                }
                // For !unquoted procedures, strip surrounding quotes from arg values
                // so they substitute as bare text.
                if (macro.is_unquoted && val.length >= 2) {
                    if ((val[0] == '"' && val[val.length - 1] == '"') ||
                        (val[0] == '\'' && val[val.length - 1] == '\'')) {
                        val = val.substring(1, val.length - 2);
                    }
                }
                subs.set(param.name, val);
            }

            // Functions: walk the body looking for !return.
            if (macro.is_function) {
                return run_function_body(macro, subs, depth);
            }

            // Procedure bodies are real preprocessor programs — they may
            // contain !if/!else/!endif, !$var = expr, and embedded macro
            // calls. Interpret them line-by-line with a local if-stack so
            // outer conditional state isn't disturbed.
            return execute_procedure_body(macro, subs, depth);
        }

        /**
         * Run a !function body with parameter values from `subs`. Returns
         * the value of the first executed !return EXPR statement (with the
         * function's local if-stack determining which !return is reached).
         * Falls back to empty string if the function ends without returning.
         */
        private string run_function_body(Macro func, Gee.HashMap<string, string> subs, int depth) {
            var local_if = new Gee.ArrayList<bool>();
            int while_depth = 0;

            for (int li = 0; li < func.body.size; li++) {
                string raw = func.body[li];
                string trimmed_raw = raw.strip();

                // !while ... !endwhile body is skipped (degraded — not
                // iterated). Better than running the body exactly once.
                if (trimmed_raw.has_prefix("!while ") || trimmed_raw.has_prefix("!while\t")) {
                    while_depth++;
                    continue;
                }
                if (trimmed_raw == "!endwhile" || trimmed_raw.has_prefix("!endwhile ")) {
                    if (while_depth > 0) while_depth--;
                    continue;
                }
                if (while_depth > 0) continue;

                // Check directive form BEFORE substituting params, so LHS of
                // !$var = expr keeps its variable name even if it collides
                // with a parameter name.
                if (trimmed_raw.has_prefix("!if ") || trimmed_raw.has_prefix("!if\t")) {
                    if (local_all_active(local_if)) {
                        string expr = substitute_in_expr(trimmed_raw.substring(3).strip(), subs);
                        var ev = new PreprocessorExpression(expr, macros);
                        local_if.add(ev.evaluate_bool());
                    } else {
                        local_if.add(false);
                    }
                    continue;
                }
                if (trimmed_raw == "!else" || trimmed_raw.has_prefix("!else ")) {
                    if (local_if.size > 0) {
                        int top = local_if.size - 1;
                        local_if[top] = !local_if[top];
                    }
                    continue;
                }
                if (trimmed_raw == "!endif" || trimmed_raw.has_prefix("!endif ")) {
                    if (local_if.size > 0) local_if.remove_at(local_if.size - 1);
                    continue;
                }

                if (!local_all_active(local_if)) continue;

                if (trimmed_raw.has_prefix("!$")) {
                    process_var_assign_in_proc(trimmed_raw, subs);
                    continue;
                }

                if (trimmed_raw.has_prefix("!return") &&
                    (trimmed_raw.length == 7 || trimmed_raw[7] == ' ' || trimmed_raw[7] == '\t')) {
                    string ret_expr = trimmed_raw.length > 7
                        ? substitute_in_expr(trimmed_raw.substring(7).strip(), subs)
                        : "";
                    if (ret_expr.length == 0) return "";
                    var inner = new PreprocessorExpression(ret_expr, macros);
                    return inner.evaluate();
                }
            }
            return "";
        }

        /**
         * Substitute parameter values into an expression string. Replaces
         * $name forms with the corresponding arg value, auto-quoting if the
         * value contains expression-meaningful characters (whitespace,
         * commas, parens, operators) so that "Web App" stays a single
         * string literal instead of being parsed as two tokens "Web" + "App".
         * Numeric values stay bare so numeric comparisons still work.
         */
        private string substitute_in_expr(string expr, Gee.HashMap<string, string> subs) {
            string result = expr;
            foreach (var entry in subs.entries) {
                try {
                    var re = new Regex("\\$" + Regex.escape_string(entry.key) + "\\b");
                    string quoted = expr_value_needs_quoting(entry.value)
                        ? "\"" + entry.value.replace("\"", "\\\"") + "\""
                        : entry.value;
                    result = re.replace_literal(result, -1, 0, quoted);
                } catch (RegexError e) {}
            }
            return result;
        }

        private bool expr_value_needs_quoting(string value) {
            if (value.length == 0) return false;
            if (value.length >= 2 &&
                ((value[0] == '"' && value[value.length - 1] == '"') ||
                 (value[0] == '\'' && value[value.length - 1] == '\''))) {
                return false;
            }
            // Numeric values (integer or decimal, with optional sign) stay bare
            int i = 0;
            if (value[0] == '-' || value[0] == '+') i++;
            bool seen_digit = false;
            bool seen_dot = false;
            bool all_numeric = true;
            for (int j = i; j < value.length; j++) {
                char c = value[j];
                if (c >= '0' && c <= '9') seen_digit = true;
                else if (c == '.' && !seen_dot) seen_dot = true;
                else { all_numeric = false; break; }
            }
            if (all_numeric && seen_digit) return false;
            // Anything containing whitespace, comma, parens, or operators
            // would parse as multiple tokens — quote it.
            for (int j = 0; j < value.length; j++) {
                char c = value[j];
                if (c == ' ' || c == '\t' || c == ',' || c == '(' || c == ')' ||
                    c == '+' || c == '-' || c == '*' || c == '/' ||
                    c == '<' || c == '>' || c == '=' || c == '!' ||
                    c == '&' || c == '|') {
                    return true;
                }
            }
            return false;
        }

        /**
         * Handle !$var = expr or !$var ?= expr inside a procedure/function
         * body. The LHS name is preserved (params don't shadow it during
         * lookup of the LHS), but the RHS expression sees param values.
         */
        private void process_var_assign_in_proc(string line, Gee.HashMap<string, string> subs) {
            // Strip leading !$
            string body = line.substring(2);
            int i = 0;
            while (i < body.length) {
                char c = body[i];
                bool is_name_char = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                    (c == '_') || (i > 0 && c >= '0' && c <= '9');
                if (!is_name_char) break;
                i++;
            }
            if (i == 0) return;
            string name = body.substring(0, i);
            while (i < body.length && (body[i] == ' ' || body[i] == '\t')) i++;
            bool conditional = false;
            if (i + 1 < body.length && body[i] == '?' && body[i + 1] == '=') {
                conditional = true;
                i += 2;
            } else if (i < body.length && body[i] == '=') {
                i += 1;
            } else {
                return;
            }
            string rhs = substitute_in_expr(body.substring(i).strip(), subs);
            if (conditional && macros.has_key(name)) return;
            var ev = new PreprocessorExpression(rhs, macros);
            string value = ev.evaluate();
            var m = new Macro(name);
            m.body.add(value);
            macros.set(name, m);
        }

        /**
         * Walk a procedure body line by line, interpreting embedded directives
         * and emitting expanded text.
         *
         * Supported directives inside procedure bodies:
         *   !if EXPR / !elseif EXPR / !else / !endif   (with local if-stack)
         *   !$NAME = EXPR  /  !$NAME ?= EXPR
         *
         * Other lines (when the local if-stack is active) are parameter-
         * substituted and then run through expand_macros, then emitted.
         */
        private string execute_procedure_body(Macro macro, Gee.HashMap<string, string> subs, int depth) {
            var sb = new StringBuilder();
            var local_if = new Gee.ArrayList<bool>();
            int while_depth = 0;

            for (int li = 0; li < macro.body.size; li++) {
                string raw = macro.body[li];
                // Examine directive form on the RAW line first, so the LHS of
                // !$var = expr keeps its variable name even if it collides
                // with a parameter name.
                string trimmed_raw = raw.strip();

                // !while ... !endwhile: skip body (degraded — not iterated)
                if (trimmed_raw.has_prefix("!while ") || trimmed_raw.has_prefix("!while\t")) {
                    while_depth++;
                    continue;
                }
                if (trimmed_raw == "!endwhile" || trimmed_raw.has_prefix("!endwhile ")) {
                    if (while_depth > 0) while_depth--;
                    continue;
                }
                if (while_depth > 0) continue;

                // Conditional directives — RHS expression gets parameter
                // substitution but the directive form itself is recognized
                // on the raw line.
                if (trimmed_raw.has_prefix("!if ") || trimmed_raw.has_prefix("!if\t")) {
                    if (local_all_active(local_if)) {
                        string expr = substitute_in_expr(trimmed_raw.substring(3).strip(), subs);
                        var ev = new PreprocessorExpression(expr, macros);
                        local_if.add(ev.evaluate_bool());
                    } else {
                        local_if.add(false);
                    }
                    continue;
                }
                if (trimmed_raw.has_prefix("!ifdef ") || trimmed_raw.has_prefix("!ifdef\t")) {
                    if (local_all_active(local_if)) {
                        local_if.add(macros.has_key(trimmed_raw.substring(7).strip()));
                    } else {
                        local_if.add(false);
                    }
                    continue;
                }
                if (trimmed_raw.has_prefix("!ifndef ") || trimmed_raw.has_prefix("!ifndef\t")) {
                    if (local_all_active(local_if)) {
                        local_if.add(!macros.has_key(trimmed_raw.substring(8).strip()));
                    } else {
                        local_if.add(false);
                    }
                    continue;
                }
                if (trimmed_raw == "!else" || trimmed_raw.has_prefix("!else ")) {
                    if (local_if.size > 0) {
                        int top = local_if.size - 1;
                        local_if[top] = !local_if[top];
                    }
                    continue;
                }
                if (trimmed_raw.has_prefix("!elseif")) {
                    if (local_if.size > 0) {
                        int top = local_if.size - 1;
                        if (local_if[top]) {
                            local_if[top] = false;
                        } else {
                            string expr = substitute_in_expr(trimmed_raw.substring(7).strip(), subs);
                            var ev = new PreprocessorExpression(expr, macros);
                            local_if[top] = ev.evaluate_bool();
                        }
                    }
                    continue;
                }
                if (trimmed_raw == "!endif" || trimmed_raw.has_prefix("!endif ")) {
                    if (local_if.size > 0) local_if.remove_at(local_if.size - 1);
                    continue;
                }

                if (!local_all_active(local_if)) continue;

                // Variable assignment inside a procedure body — handle on raw
                // form so LHS variable name is preserved.
                if (trimmed_raw.has_prefix("!$")) {
                    process_var_assign_in_proc(trimmed_raw, subs);
                    continue;
                }

                // Comment lines and blanks pass through unchanged
                if (trimmed_raw.has_prefix("'") || trimmed_raw.length == 0) {
                    sb.append(raw);
                    if (li < macro.body.size - 1) sb.append("\n");
                    continue;
                }

                // Active body line — substitute params, then expand macros, emit.
                string substituted = substitute_params(raw, subs, macro.is_procedure);
                string expanded = expand_macros(substituted, depth);
                sb.append(expanded);
                if (li < macro.body.size - 1) sb.append("\n");
            }
            return sb.str;
        }

        private bool local_all_active(Gee.ArrayList<bool> stack) {
            foreach (bool a in stack) {
                if (!a) return false;
            }
            return true;
        }

        /**
         * Substitute parameter references in `line` with values from `subs`.
         * - Always recognizes $name form (PlantUML canonical).
         * - Also recognizes bare `name` only when allow_bare is true. Bare-name
         *   substitution is suppressed for procedures because their bodies may
         *   contain literal text matching a parameter name.
         */
        private string substitute_params(string line, Gee.HashMap<string, string> subs, bool is_procedure_body) {
            if (subs.size == 0) return line;
            string result = line;
            foreach (var entry in subs.entries) {
                try {
                    // Replace $name (with the dollar prefix) — always.
                    var re_dollar = new Regex("\\$" + Regex.escape_string(entry.key) + "\\b");
                    result = re_dollar.replace_literal(result, -1, 0, entry.value);
                    // Bare name only outside procedures (where literal text
                    // collisions are common).
                    if (!is_procedure_body) {
                        var re_bare = new Regex("\\b" + Regex.escape_string(entry.key) + "\\b");
                        result = re_bare.replace_literal(result, -1, 0, entry.value);
                    }
                } catch (RegexError e) {
                    // skip
                }
            }
            return result;
        }

        private string process_include_directive(string line, string? base_path, int depth, int line_num) {
            // Parse: !include <path> or !include path
            string path = extract_include_path(line);

            if (path == null || path.length == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !include directive: missing path",
                    line_num
                ));
                return "' [preprocessor error] Invalid !include: %s\n".printf(line);
            }

            // Check for standard library includes (future feature)
            if (path.has_prefix("<") && path.has_suffix(">")) {
                // Standard library include - not supported yet
                errors.add(new PreprocessorError(
                    "Standard library includes not yet supported: %s".printf(path),
                    line_num
                ));
                return "' [preprocessor] Unsupported standard library include: %s\n".printf(path);
            }

            // Resolve the file path
            string resolved_path = resolve_path(path, base_path);

            if (resolved_path == null) {
                errors.add(new PreprocessorError(
                    "Cannot resolve include path: %s".printf(path),
                    line_num
                ));
                return "' [preprocessor error] Cannot resolve: %s\n".printf(path);
            }

            // Check for circular includes
            string canonical_path = get_canonical_path(resolved_path);
            if (canonical_path != null && included_files.contains(canonical_path)) {
                // Already included - skip silently (this is valid PlantUML behavior)
                return "' [preprocessor] Already included: %s\n".printf(path);
            }

            if (canonical_path != null) {
                included_files.add(canonical_path);
            }

            // Read the file
            string? content = read_file(resolved_path);
            if (content == null) {
                errors.add(new PreprocessorError(
                    "Cannot read include file: %s".printf(resolved_path),
                    line_num
                ));
                return "' [preprocessor error] Cannot read: %s\n".printf(resolved_path);
            }

            // Get the directory of the included file for nested includes
            string? include_base_path = get_directory(resolved_path);

            // Strip @startuml and @enduml from included content
            string stripped = strip_uml_tags(content);

            // Recursively process the included content
            string processed = process_internal(stripped, include_base_path, depth + 1);

            // Wrap with markers for debugging
            var result = new StringBuilder();
            result.append("' [begin include: %s]\n".printf(path));
            result.append(processed);
            if (!processed.has_suffix("\n")) {
                result.append("\n");
            }
            result.append("' [end include: %s]\n".printf(path));

            return result.str;
        }

        private string? extract_include_path(string line) {
            // !include <path> or !include path or !include "path"
            string after_include = line.substring(8).strip();  // Skip "!include"

            if (after_include.length == 0) {
                return null;
            }

            // Handle quoted paths
            if (after_include.has_prefix("\"") && after_include.has_suffix("\"") && after_include.length > 2) {
                return after_include.substring(1, after_include.length - 2);
            }

            // Handle angle-bracket paths (standard library)
            if (after_include.has_prefix("<") && after_include.has_suffix(">")) {
                return after_include;  // Return with brackets for identification
            }

            // Plain path - take until whitespace or end
            int space_idx = after_include.index_of(" ");
            if (space_idx > 0) {
                return after_include.substring(0, space_idx);
            }

            return after_include;
        }

        private string? resolve_path(string path, string? base_path) {
            // Absolute path
            if (Path.is_absolute(path)) {
                if (FileUtils.test(path, FileTest.EXISTS)) {
                    return path;
                }
                return null;
            }

            // Relative path - resolve against base_path
            if (base_path != null) {
                string full_path = Path.build_filename(base_path, path);
                if (FileUtils.test(full_path, FileTest.EXISTS)) {
                    return full_path;
                }
            }

            // Try current working directory as fallback
            if (FileUtils.test(path, FileTest.EXISTS)) {
                return path;
            }

            return null;
        }

        private string? get_canonical_path(string path) {
            // Normalise `..`, `.`, and redundant slashes so includes
            // reached via different path strings (e.g. `foo.puml`,
            // `./foo.puml`, `a/../foo.puml`) produce the same key in
            // the circular-include set. Without this, a creative
            // !include chain could reload the same file repeatedly
            // until MAX_INCLUDE_DEPTH triggers.
            //
            // Note: this is path normalisation only — it does not
            // resolve symlinks. For include-loop prevention that's
            // enough; symlink resolution would be overkill.
            return GLib.Filename.canonicalize(path);
        }

        private string? get_directory(string path) {
            return Path.get_dirname(path);
        }

        private string? read_file(string path) {
            try {
                string content;
                FileUtils.get_contents(path, out content);
                return content;
            } catch (Error e) {
                return null;
            }
        }

        /**
         * Strip @startuml and @enduml tags from included file content.
         * These tags should only appear in the main file, not in includes.
         */
        private string strip_uml_tags(string content) {
            var result = new StringBuilder();
            var lines = content.split("\n");

            foreach (var line in lines) {
                string trimmed = line.strip().down();
                // Skip @startuml (with or without diagram name) and @enduml
                if (trimmed.has_prefix("@startuml") || trimmed == "@enduml") {
                    continue;
                }
                result.append(line);
                result.append("\n");
            }

            return result.str;
        }

        /**
         * Check if preprocessing produced any errors.
         */
        public bool has_errors() {
            return errors.size > 0;
        }
    }

    /**
     * Represents an error encountered during preprocessing.
     */
    public class PreprocessorError : Object {
        public string message { get; private set; }
        public int line { get; private set; }

        public PreprocessorError(string message, int line) {
            this.message = message;
            this.line = line;
        }
    }

    /**
     * One frame on the conditional-compilation stack.
     *
     * `active` controls whether the line loop currently emits output for the
     * lines inside this if-branch. `taken` records whether any branch in
     * the if/elseif/else chain has been entered yet — once true, all
     * subsequent branches stay inactive.
     */
    public class IfFrame : Object {
        public bool active;
        public bool taken;
    }

    /**
     * A formal parameter of a macro/procedure/function.
     * The name is stored without the $ prefix; default_value is null when no
     * default was given. Default values are stored as raw text — they are
     * substituted verbatim into the body when the corresponding argument is
     * missing.
     */
    public class MacroParameter : Object {
        public string name { get; set; }
        public string? default_value { get; set; }

        public MacroParameter(string name, string? default_value = null) {
            this.name = name;
            this.default_value = default_value;
        }
    }

    /**
     * A preprocessor macro: !define, !procedure, !unquoted procedure, or
     * !function. The body is stored as a list of lines so the same class
     * works for both single-line !define and multi-line !procedure.
     *
     * Simple `!define NAME VALUE` is represented as a Macro with empty
     * parameters and a one-line body containing VALUE.
     */
    public class Macro : Object {
        public string name { get; set; }
        public Gee.ArrayList<MacroParameter> parameters { get; set; }
        public Gee.ArrayList<string> body { get; set; }
        public bool is_parameterized { get; set; }
        public bool is_unquoted { get; set; }
        public bool is_function { get; set; }
        // True for multi-line procedures (collected via !procedure / !unquoted
        // procedure / !function). Bare-name parameter substitution is suppressed
        // for procedures because their bodies may contain literal text matching
        // a parameter name (e.g. "bg=...$bg..." would otherwise replace the
        // literal "bg" too). Only $name form substitutes inside procedure bodies.
        public bool is_procedure { get; set; }

        public Macro(string name) {
            this.name = name;
            this.parameters = new Gee.ArrayList<MacroParameter>();
            this.body = new Gee.ArrayList<string>();
            this.is_parameterized = false;
            this.is_unquoted = false;
            this.is_function = false;
            this.is_procedure = false;
        }
    }
}
