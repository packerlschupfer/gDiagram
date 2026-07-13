namespace GDiagram {
    /**
     * A small recursive-descent evaluator for PlantUML preprocessor
     * expressions. Used by !if/!elseif/!return contexts. Everything is a
     * string in PlantUML's preprocessor; booleans are "true"/"false",
     * numbers are decimal strings.
     *
     * Supported grammar (lowest to highest precedence):
     *
     *   expr     := or_expr
     *   or_expr  := and_expr ('||' and_expr)*
     *   and_expr := eq_expr  ('&&' eq_expr)*
     *   eq_expr  := rel_expr (('==' | '!=') rel_expr)?
     *   rel_expr := add_expr (('<' | '>' | '<=' | '>=') add_expr)?
     *   add_expr := mul_expr (('+' | '-') mul_expr)*
     *   mul_expr := unary  (('*' | '/') unary)*
     *   unary    := ('!' | '-')? primary
     *   primary  := NUMBER
     *             | STRING
     *             | '$' IDENT       (variable lookup)
     *             | IDENT '(' args ')'   (macro/function call)
     *             | '%' IDENT '(' args ')' (built-in function call)
     *             | IDENT           (bare name -> macro lookup or string itself)
     *             | '(' expr ')'
     *
     * The evaluator is intentionally permissive: unknown identifiers
     * resolve to their literal string form rather than erroring, which
     * matches PlantUML's behaviour for many corner cases.
     */
    public class PreprocessorExpression : Object {
        private string source;
        private int pos;
        private Gee.HashMap<string, Macro> macros;
        public Gee.ArrayList<string> errors { get; private set; }

        public PreprocessorExpression(string expr, Gee.HashMap<string, Macro> macros) {
            this.source = expr;
            this.pos = 0;
            this.macros = macros;
            this.errors = new Gee.ArrayList<string>();
        }

        public string evaluate() {
            string result = parse_or();
            return result;
        }

        public bool evaluate_bool() {
            string v = evaluate();
            return is_truthy(v);
        }

        public static bool is_truthy(string v) {
            string t = v.strip().down();
            if (t == "" || t == "false" || t == "0" || t == "no") return false;
            return true;
        }

        // ── Parser ────────────────────────────────────────────────

        private string parse_or() {
            string left = parse_and();
            while (match_op("||")) {
                string right = parse_and();
                left = (is_truthy(left) || is_truthy(right)) ? "true" : "false";
            }
            return left;
        }

        private string parse_and() {
            string left = parse_eq();
            while (match_op("&&")) {
                string right = parse_eq();
                left = (is_truthy(left) && is_truthy(right)) ? "true" : "false";
            }
            return left;
        }

        private string parse_eq() {
            string left = parse_rel();
            if (match_op("==")) {
                string right = parse_rel();
                return (left == right) ? "true" : "false";
            }
            if (match_op("!=")) {
                string right = parse_rel();
                return (left != right) ? "true" : "false";
            }
            return left;
        }

        private string parse_rel() {
            string left = parse_add();
            // Two-char operators must be checked before single-char.
            if (match_op("<=")) return cmp_num(left, parse_add(), -1, true);
            if (match_op(">=")) return cmp_num(left, parse_add(), 1, true);
            if (match_op("<"))  return cmp_num(left, parse_add(), -1, false);
            if (match_op(">"))  return cmp_num(left, parse_add(), 1, false);
            return left;
        }

        private string parse_add() {
            string left = parse_mul();
            while (true) {
                if (match_op("+")) {
                    string right = parse_mul();
                    // PlantUML's '+' is overloaded: numeric add for numbers,
                    // string concat otherwise.
                    if (is_numeric(left) && is_numeric(right)) {
                        left = num_to_string(parse_num(left) + parse_num(right));
                    } else {
                        left = left + right;
                    }
                } else if (match_op("-")) {
                    string right = parse_mul();
                    if (is_numeric(left) && is_numeric(right)) {
                        left = num_to_string(parse_num(left) - parse_num(right));
                    } else {
                        left = left;  // can't subtract non-numbers; keep left
                    }
                } else {
                    break;
                }
            }
            return left;
        }

        private string parse_mul() {
            string left = parse_unary();
            while (true) {
                if (match_op("*")) {
                    string right = parse_unary();
                    if (is_numeric(left) && is_numeric(right)) {
                        left = num_to_string(parse_num(left) * parse_num(right));
                    }
                } else if (match_op("/")) {
                    string right = parse_unary();
                    if (is_numeric(left) && is_numeric(right) && parse_num(right) != 0) {
                        left = num_to_string(parse_num(left) / parse_num(right));
                    }
                } else {
                    break;
                }
            }
            return left;
        }

        private string parse_unary() {
            skip_ws();
            if (peek() == '!') {
                pos++;
                string v = parse_unary();
                return is_truthy(v) ? "false" : "true";
            }
            if (peek() == '-') {
                pos++;
                string v = parse_unary();
                if (is_numeric(v)) {
                    return num_to_string(-parse_num(v));
                }
                return "-" + v;
            }
            return parse_primary();
        }

        private string parse_primary() {
            skip_ws();
            unichar c = peek();

            // Parenthesized expression
            if (c == '(') {
                pos++;
                string v = parse_or();
                skip_ws();
                if (peek() == ')') pos++;
                return v;
            }

            // String literal
            if (c == '"' || c == '\'') {
                return read_string_literal();
            }

            // Number
            if (c.isdigit() || c == '.') {
                return read_number();
            }

            // Variable reference: $name  OR  function call: $name(args)
            if (c == '$') {
                pos++;
                string name = read_identifier();
                skip_ws();
                if (peek() == '(') {
                    var args = read_call_args();
                    return call_user_macro(name, args);
                }
                return lookup_macro_value(name);
            }

            // Built-in function: %name(...)
            if (c == '%') {
                pos++;
                string name = read_identifier();
                skip_ws();
                if (peek() == '(') {
                    var args = read_call_args();
                    return call_builtin(name, args);
                }
                return name;  // bare % usage — return the name
            }

            // Identifier — could be a macro/function call or a bare name
            if (c.isalpha() || c == '_') {
                string name = read_identifier();
                skip_ws();
                if (peek() == '(') {
                    var args = read_call_args();
                    return call_user_macro(name, args);
                }
                // Bare identifier — try macro lookup, else return as literal
                if (macros.has_key(name)) {
                    return lookup_macro_value(name);
                }
                return name;
            }

            // Unknown — consume one char to avoid infinite loop
            if (pos < source.length) pos++;
            return "";
        }

        // ── Lexing helpers ────────────────────────────────────────

        private void skip_ws() {
            while (pos < source.length) {
                unichar c = source[pos];
                if (c == ' ' || c == '\t') pos++;
                else break;
            }
        }

        private unichar peek() {
            if (pos >= source.length) return '\0';
            return (unichar) source[pos];
        }

        private bool match_op(string op) {
            skip_ws();
            if (pos + op.length > source.length) return false;
            for (int i = 0; i < op.length; i++) {
                if (source[pos + i] != op[i]) return false;
            }
            // Reject prefix matches: don't accept "<" when source has "<=".
            // This is handled by ordering — callers check longer ops first.
            // But also: don't accept "==" as a prefix of "===".
            if (op == "<" || op == ">") {
                // Make sure the next char isn't '=' (which would form <= / >=)
                if (pos + 1 < source.length && source[pos + 1] == '=') return false;
            }
            if (op == "!") {
                // Don't consume the '!' of "!=".
                if (pos + 1 < source.length && source[pos + 1] == '=') return false;
            }
            pos += op.length;
            return true;
        }

        private string read_string_literal() {
            unichar quote = (unichar) source[pos];
            pos++;
            var sb = new StringBuilder();
            while (pos < source.length && source[pos] != quote) {
                if (source[pos] == '\\' && pos + 1 < source.length) {
                    char c = source[pos + 1];
                    // Preserve PlantUML/graphviz format escapes as two
                    // characters: \n in a label is "render as newline"
                    // (graphviz handles it). Only unescape \" and \\ which
                    // are needed to embed literal quote/backslash characters
                    // in the source.
                    if (c == '"' || c == '\'') {
                        pos++;
                        sb.append_c(c);
                    } else if (c == '\\') {
                        pos++;
                        sb.append_c('\\');
                    } else {
                        // Keep the backslash + char as-is so format escapes
                        // (\n, \t, \l, \r) survive into label output for the
                        // downstream renderer to handle.
                        sb.append_c('\\');
                        pos++;
                        sb.append_c(c);
                    }
                } else {
                    sb.append_unichar((unichar) source[pos]);
                }
                pos++;
            }
            if (pos < source.length) pos++;  // closing quote
            return sb.str;
        }

        private string read_number() {
            int start = pos;
            while (pos < source.length) {
                char c = source[pos];
                if ((c >= '0' && c <= '9') || c == '.') pos++;
                else break;
            }
            return source.substring(start, pos - start);
        }

        private string read_identifier() {
            int start = pos;
            while (pos < source.length) {
                char c = source[pos];
                bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                          (c == '_') || (pos > start && c >= '0' && c <= '9');
                if (!ok) break;
                pos++;
            }
            return source.substring(start, pos - start);
        }

        /**
         * Read a parenthesized argument list, evaluating each argument as
         * its own sub-expression. Caller has positioned `pos` at the '('.
         */
        private Gee.ArrayList<string> read_call_args() {
            var list = new Gee.ArrayList<string>();
            if (peek() != '(') return list;
            pos++;  // consume '('
            skip_ws();
            if (peek() == ')') { pos++; return list; }
            while (pos < source.length) {
                string arg = parse_or();
                list.add(arg);
                skip_ws();
                if (peek() == ',') { pos++; skip_ws(); continue; }
                if (peek() == ')') { pos++; break; }
                break;
            }
            return list;
        }

        // ── Value lookups ─────────────────────────────────────────

        private string lookup_macro_value(string name) {
            if (!macros.has_key(name)) return "";
            var m = macros.get(name);
            if (m.is_parameterized) return name;  // can't expand without args here
            if (m.body.size == 0) return "";
            string raw = m.body[0];
            // Strip surrounding quotes — in expression context the value of
            // !define MODE "prod" should compare equal to the literal "prod".
            if (raw.length >= 2) {
                char first = raw[0];
                char last = raw[raw.length - 1];
                if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
                    return raw.substring(1, raw.length - 2);
                }
            }
            return raw;
        }

        private string call_user_macro(string name, Gee.ArrayList<string> args) {
            if (!macros.has_key(name)) {
                // Unknown — return the call form as a literal so the surrounding
                // text isn't broken
                return name + "(" + join_args(args) + ")";
            }
            var m = macros.get(name);
            var subs = new Gee.HashMap<string, string>();
            for (int p = 0; p < m.parameters.size; p++) {
                var param = m.parameters[p];
                string val;
                if (p < args.size) val = args[p];
                else if (param.default_value != null) val = param.default_value;
                else val = "";
                subs.set(param.name, val);
            }

            if (m.is_function) {
                return execute_function_body(m, subs);
            }

            // Procedure: substitute params into the body lines and join.
            var sb = new StringBuilder();
            for (int i = 0; i < m.body.size; i++) {
                if (i > 0) sb.append("\n");
                sb.append(substitute_in_text(m.body[i], subs));
            }
            return sb.str;
        }

        /**
         * Execute a !function body and return its !return value.
         * Walks body lines top to bottom, applying parameter substitution
         * to each, then:
         *   - !return EXPR  → evaluate EXPR and return its value
         *   - !if EXPR / !elseif / !else / !endif → track an if-stack so
         *                    only the active branch's lines run
         *   - any other line → ignored (functions emit only via !return)
         *
         * Conditional !return inside an if block works because the
         * if-stack gates it.
         */
        private string execute_function_body(Macro func, Gee.HashMap<string, string> subs) {
            var local_if_stack = new Gee.ArrayList<bool>();
            // While loops are not (yet) properly iterated. To avoid running
            // a loop body once when it should run zero times, we track a
            // depth counter for !while ... !endwhile and skip everything
            // inside. This is degraded but better than the alternative for
            // common cases like "label fits in one line so loop runs 0 times".
            int while_depth = 0;

            for (int i = 0; i < func.body.size; i++) {
                string raw = func.body[i];
                // Check directives BEFORE substitution so the LHS of !$var=
                // keeps its name even if it collides with a parameter name.
                string trimmed_raw = raw.strip();

                if (trimmed_raw.has_prefix("!while ") || trimmed_raw.has_prefix("!while\t")) {
                    while_depth++;
                    continue;
                }
                if (trimmed_raw == "!endwhile" || trimmed_raw.has_prefix("!endwhile ")) {
                    if (while_depth > 0) while_depth--;
                    continue;
                }
                if (while_depth > 0) continue;

                // Conditional handling within the function body
                if (trimmed_raw.has_prefix("!if ") || trimmed_raw.has_prefix("!if\t")) {
                    if (local_all_active(local_if_stack)) {
                        string expr = substitute_in_text(trimmed_raw.substring(3).strip(), subs);
                        var sub_ev = new PreprocessorExpression(expr, macros);
                        local_if_stack.add(sub_ev.evaluate_bool());
                    } else {
                        local_if_stack.add(false);
                    }
                    continue;
                }
                if (trimmed_raw == "!else" || trimmed_raw.has_prefix("!else ")) {
                    if (local_if_stack.size > 0) {
                        int top = local_if_stack.size - 1;
                        local_if_stack[top] = !local_if_stack[top];
                    }
                    continue;
                }
                if (trimmed_raw == "!endif" || trimmed_raw.has_prefix("!endif ")) {
                    if (local_if_stack.size > 0) {
                        local_if_stack.remove_at(local_if_stack.size - 1);
                    }
                    continue;
                }

                if (!local_all_active(local_if_stack)) continue;

                // Variable assignment !$var = expr (or ?=). Without this,
                // string-building functions like C4-PlantUML's $getElementBase
                // silently produce empty output because their incremental
                // !$element = $element + ... is dropped.
                if (trimmed_raw.has_prefix("!$")) {
                    handle_var_assign_in_fn(trimmed_raw, subs);
                    continue;
                }

                if (trimmed_raw.has_prefix("!return") &&
                    (trimmed_raw.length == 7 || trimmed_raw[7] == ' ' || trimmed_raw[7] == '\t')) {
                    string ret_expr = trimmed_raw.length > 7
                        ? substitute_in_text(trimmed_raw.substring(7).strip(), subs)
                        : "";
                    if (ret_expr.length == 0) return "";
                    var inner = new PreprocessorExpression(ret_expr, macros);
                    return inner.evaluate();
                }
            }
            return "";
        }

        /**
         * !$var = expr / !$var ?= expr inside a function body.
         * Stores the evaluated value as a Macro entry so subsequent
         * references via $var pick it up.
         */
        private void handle_var_assign_in_fn(string line, Gee.HashMap<string, string> subs) {
            string body = line.substring(2);  // strip "!$"
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
            string rhs = substitute_in_text(body.substring(i).strip(), subs);
            if (conditional && macros.has_key(name)) return;
            var inner = new PreprocessorExpression(rhs, macros);
            string value = inner.evaluate();
            var m = new Macro(name);
            m.body.add(value);
            macros.set(name, m);
        }

        private bool local_all_active(Gee.ArrayList<bool> stack) {
            foreach (bool a in stack) {
                if (!a) return false;
            }
            return true;
        }

        private string substitute_in_text(string line, Gee.HashMap<string, string> subs) {
            string r = line;
            foreach (var entry in subs.entries) {
                try {
                    // If the value contains spaces or other expression-meaningful
                    // characters, wrap it in quotes so the expression parser
                    // treats it as a single string literal rather than splitting
                    // on whitespace. ("Web App" → quoted; React → unquoted.)
                    string quoted = needs_quoting(entry.value)
                        ? "\"" + entry.value.replace("\"", "\\\"") + "\""
                        : entry.value;
                    var re_dollar = new Regex("\\$" + Regex.escape_string(entry.key) + "\\b");
                    r = re_dollar.replace_literal(r, -1, 0, quoted);
                    var re_bare = new Regex("\\b" + Regex.escape_string(entry.key) + "\\b");
                    r = re_bare.replace_literal(r, -1, 0, quoted);
                } catch (RegexError e) {}
            }
            return r;
        }

        private bool needs_quoting(string value) {
            if (value.length == 0) return false;
            // Already quoted? leave as-is
            if (value.length >= 2 &&
                ((value[0] == '"' && value[value.length - 1] == '"') ||
                 (value[0] == '\'' && value[value.length - 1] == '\''))) {
                return false;
            }
            // Numeric? leave as-is
            if (is_numeric(value)) return false;
            // Contains a character that would break expression parsing if
            // emitted bare (whitespace, comma, parens, operators)
            for (int i = 0; i < value.length; i++) {
                char c = value[i];
                if (c == ' ' || c == '\t' || c == ',' || c == '(' || c == ')' ||
                    c == '+' || c == '-' || c == '*' || c == '/' ||
                    c == '<' || c == '>' || c == '=' || c == '!' ||
                    c == '&' || c == '|') {
                    return true;
                }
            }
            return false;
        }

        private string call_builtin(string name, Gee.ArrayList<string> args) {
            // Implementations of PlantUML preprocessor built-ins. The set
            // covers everything that C4-PlantUML's core file uses.
            switch (name) {
                case "upper":
                case "strupper":
                    return args.size > 0 ? args[0].up() : "";
                case "lower":
                case "strlower":
                    return args.size > 0 ? args[0].down() : "";
                case "strlen":
                case "strLen":
                    return args.size > 0 ? args[0].length.to_string() : "0";
                case "string":
                    return args.size > 0 ? args[0] : "";
                case "intval":
                case "number":
                    return args.size > 0 && is_numeric(args[0])
                        ? ((long) parse_num(args[0])).to_string() : "0";
                case "not":
                    return args.size > 0 && is_truthy(args[0]) ? "false" : "true";
                case "true":
                    return "true";
                case "false":
                    return "false";
                case "function_exists":
                case "variable_exists":
                    if (args.size > 0 && macros.has_key(args[0])) return "true";
                    return "false";
                case "get_variable_value":
                    if (args.size > 0) return lookup_macro_value(args[0]);
                    return "";
                case "set_variable_value":
                    // !$set_variable_value("name", value)
                    if (args.size >= 2) {
                        var m = new Macro(args[0]);
                        m.body.add(args[1]);
                        macros.set(args[0], m);
                    }
                    return args.size >= 2 ? args[1] : "";
                case "newline":
                    return "\n";
                case "breakline":
                    return "\\n";
                case "chr":
                    if (args.size > 0 && is_numeric(args[0])) {
                        unichar c = (unichar) parse_num(args[0]);
                        var sb = new StringBuilder();
                        sb.append_unichar(c);
                        return sb.str;
                    }
                    return "";
                case "substr":
                    // %substr(string, start) or %substr(string, start, length)
                    if (args.size < 2) return "";
                    string s = args[0];
                    int start = is_numeric(args[1]) ? (int) parse_num(args[1]) : 0;
                    if (start < 0) start = int.max(0, s.length + start);
                    if (start >= s.length) return "";
                    if (args.size >= 3 && is_numeric(args[2])) {
                        int len = (int) parse_num(args[2]);
                        if (len < 0) return "";
                        if (start + len > s.length) len = s.length - start;
                        return s.substring(start, len);
                    }
                    return s.substring(start);
                case "strpos":
                    // %strpos(string, search) — returns 0-based index, or -1
                    if (args.size < 2) return "-1";
                    int idx = args[0].index_of(args[1]);
                    return idx.to_string();
                case "splitstr":
                case "splitstr_regex":
                    // %splitstr(string, sep) — returns the first piece (we
                    // don't have list values, so this is a degraded impl)
                    if (args.size < 2) return args.size > 0 ? args[0] : "";
                    string[] pieces = args[0].split(args[1]);
                    return pieces.length > 0 ? pieces[0] : "";
                case "is_dark":
                    // %is_dark("#RRGGBB") — true if luminance < 0.5
                    if (args.size == 0) return "false";
                    return is_dark_hex(args[0]) ? "true" : "false";
                case "darken":
                case "lighten":
                    // %darken("#RRGGBB", percent) — return adjusted hex.
                    // Stub: return the original color unchanged so the layout
                    // doesn't break. Real implementation would shift HSL.
                    return args.size > 0 ? args[0] : "#000000";
                case "version":
                    return "0";
                default:
                    // Unknown built-in — return the literal call form so it
                    // shows up in output for diagnosis instead of disappearing.
                    return "%" + name + "(" + join_args(args) + ")";
            }
        }

        private bool is_dark_hex(string color) {
            string c = color.strip();
            if (c.has_prefix("#")) c = c.substring(1);
            if (c.length != 6) return false;
            // Parse hex: rr gg bb
            int r = parse_hex_byte(c.substring(0, 2));
            int g = parse_hex_byte(c.substring(2, 2));
            int b = parse_hex_byte(c.substring(4, 2));
            // Standard luminance formula
            double lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
            return lum < 0.5;
        }

        private int parse_hex_byte(string s) {
            int v = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                int d;
                if (c >= '0' && c <= '9') d = c - '0';
                else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
                else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
                else return 0;
                v = v * 16 + d;
            }
            return v;
        }

        // ── Numeric helpers ───────────────────────────────────────

        private bool is_numeric(string s) {
            if (s.length == 0) return false;
            int i = 0;
            if (s[0] == '-' || s[0] == '+') i++;
            bool seen_digit = false;
            bool seen_dot = false;
            while (i < s.length) {
                char c = s[i];
                if (c >= '0' && c <= '9') seen_digit = true;
                else if (c == '.' && !seen_dot) seen_dot = true;
                else return false;
                i++;
            }
            return seen_digit;
        }

        private double parse_num(string s) {
            return double.parse(s);
        }

        private string num_to_string(double v) {
            // Drop trailing .0 for nicer output
            if (v == (long) v) {
                return ((long) v).to_string();
            }
            return "%g".printf(v);
        }

        private string cmp_num(string a, string b, int direction, bool inclusive) {
            if (is_numeric(a) && is_numeric(b)) {
                double na = parse_num(a);
                double nb = parse_num(b);
                bool result;
                if (direction < 0) result = inclusive ? na <= nb : na < nb;
                else result = inclusive ? na >= nb : na > nb;
                return result ? "true" : "false";
            }
            // String comparison
            int cmp = strcmp(a, b);
            bool result_s;
            if (direction < 0) result_s = inclusive ? cmp <= 0 : cmp < 0;
            else result_s = inclusive ? cmp >= 0 : cmp > 0;
            return result_s ? "true" : "false";
        }

        private string join_args(Gee.ArrayList<string> args) {
            var sb = new StringBuilder();
            for (int i = 0; i < args.size; i++) {
                if (i > 0) sb.append(", ");
                sb.append(args[i]);
            }
            return sb.str;
        }
    }
}
