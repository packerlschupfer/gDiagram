namespace GDiagram {
    /**
     * A value of PlantUML's preprocessor: a string, an integer or a JSON array
     * (from %splitstr). The kind matters: "0" + "1" concatenates to "01" while
     * 0 + 1 adds, and booleans are the integers 1 and 0.
     */
    public class PValue : Object {
        public const int STR = 0;
        public const int INT = 1;
        public const int ARR = 2;

        public int kind;
        public string str = "";
        public int64 num = 0;
        public Gee.ArrayList<PValue>? items = null;

        public PValue.of_string(string s) {
            kind = STR;
            str = s;
        }

        public PValue.of_int(int64 n) {
            kind = INT;
            num = n;
        }

        public PValue.of_bool(bool b) {
            kind = INT;
            num = b ? 1 : 0;
        }

        public PValue.of_array(Gee.ArrayList<PValue> list) {
            kind = ARR;
            items = list;
        }

        public string to_text() {
            switch (kind) {
                case INT:
                    return num.to_string();
                case ARR:
                    var sb = new StringBuilder("[");
                    for (int i = 0; i < items.size; i++) {
                        if (i > 0) {
                            sb.append_c(',');
                        }
                        var item = items[i];
                        if (item.kind == STR) {
                            sb.append_c('"').append(item.str.replace("\\", "\\\\").replace("\"", "\\\"")).append_c('"');
                        } else {
                            sb.append(item.to_text());
                        }
                    }
                    sb.append_c(']');
                    return sb.str;
                default:
                    return str;
            }
        }

        /** PlantUML truth: a non-zero integer, a non-empty string or array. */
        public bool truthy() {
            switch (kind) {
                case INT:
                    return num != 0;
                case ARR:
                    return items.size > 0;
                default:
                    return str.length > 0;
            }
        }

        /** The integer value; a string counts when it is an integer literal. */
        public bool to_int(out int64 v) {
            v = 0;
            if (kind == INT) {
                v = num;
                return true;
            }
            if (kind == STR) {
                return parse_int(str.strip(), out v);
            }
            return false;
        }

        public static bool parse_int(string s, out int64 v) {
            v = 0;
            if (s.length == 0) {
                return false;
            }
            int i = (s[0] == '-' || s[0] == '+') ? 1 : 0;
            if (i >= s.length) {
                return false;
            }
            for (int k = i; k < s.length; k++) {
                if (s[k] < '0' || s[k] > '9') {
                    return false;
                }
            }
            return int64.try_parse(s, out v);
        }
    }

    /**
     * Recursive-descent evaluator for PlantUML preprocessor expressions
     * (!if, !while, !$var = ..., !return, function arguments).
     *
     *   expr     := or_expr
     *   or_expr  := and_expr ('||' and_expr)*
     *   and_expr := eq_expr  ('&&' eq_expr)*
     *   eq_expr  := rel_expr (('==' | '!=') rel_expr)*
     *   rel_expr := add_expr (('<' | '>' | '<=' | '>=') add_expr)*
     *   add_expr := mul_expr (('+' | '-') mul_expr)*
     *   mul_expr := unary  (('*' | '/') unary)*
     *   unary    := ('!' | '-' | '+') unary | primary
     *   primary  := INTEGER | STRING | '(' expr ')'
     *             | '$' IDENT ['(' args ')']     variable / user function
     *             | '%' IDENT '(' args ')'       built-in function
     *             | IDENT ['(' args ')']         bare variable / function / literal
     *             | other text                   literal string
     *
     * Like PlantUML, string literals have no escapes ("\n" stays two
     * characters), an unknown name is its own text, and of two juxtaposed
     * values ("0.5" reads as 0 then .5) the last one wins.
     */
    public class PreprocessorExpression : Object {
        private string source;
        private int pos;
        private unowned Preprocessor pp;

        public PreprocessorExpression(string expr, Preprocessor pp) {
            this.source = expr;
            this.pos = 0;
            this.pp = pp;
        }

        public PValue evaluate() {
            var v = new PValue.of_string("");
            skip_ws();
            while (pos < source.length) {
                int before = pos;
                v = parse_or();
                skip_ws();
                if (pos == before) {
                    pos++;
                }
            }
            return v;
        }

        public bool evaluate_bool() {
            return evaluate().truthy();
        }

        // ── Parser ────────────────────────────────────────────────

        private PValue parse_or() {
            var left = parse_and();
            while (match_op("||")) {
                var right = parse_and();
                left = new PValue.of_bool(left.truthy() || right.truthy());
            }
            return left;
        }

        private PValue parse_and() {
            var left = parse_eq();
            while (match_op("&&")) {
                var right = parse_eq();
                left = new PValue.of_bool(left.truthy() && right.truthy());
            }
            return left;
        }

        private PValue parse_eq() {
            var left = parse_rel();
            while (true) {
                if (match_op("==")) {
                    left = new PValue.of_bool(compare(left, parse_rel()) == 0);
                } else if (match_op("!=")) {
                    left = new PValue.of_bool(compare(left, parse_rel()) != 0);
                } else {
                    return left;
                }
            }
        }

        private PValue parse_rel() {
            var left = parse_add();
            while (true) {
                if (match_op("<=")) {
                    left = new PValue.of_bool(compare(left, parse_add()) <= 0);
                } else if (match_op(">=")) {
                    left = new PValue.of_bool(compare(left, parse_add()) >= 0);
                } else if (match_op("<")) {
                    left = new PValue.of_bool(compare(left, parse_add()) < 0);
                } else if (match_op(">")) {
                    left = new PValue.of_bool(compare(left, parse_add()) > 0);
                } else {
                    return left;
                }
            }
        }

        private PValue parse_add() {
            var left = parse_mul();
            while (true) {
                if (match_op("+")) {
                    var right = parse_mul();
                    if (left.kind == PValue.INT && right.kind == PValue.INT) {
                        left = new PValue.of_int(left.num + right.num);
                    } else {
                        left = new PValue.of_string(left.to_text() + right.to_text());
                    }
                } else if (match_op("-")) {
                    var right = parse_mul();
                    int64 a = 0, b = 0;
                    if (left.to_int(out a) && right.to_int(out b)) {
                        left = new PValue.of_int(a - b);
                    }
                } else {
                    return left;
                }
            }
        }

        private PValue parse_mul() {
            var left = parse_unary();
            while (true) {
                if (match_op("*")) {
                    var right = parse_unary();
                    int64 a = 0, b = 0;
                    if (left.to_int(out a) && right.to_int(out b)) {
                        left = new PValue.of_int(a * b);
                    }
                } else if (match_op("/")) {
                    var right = parse_unary();
                    int64 a = 0, b = 0;
                    if (left.to_int(out a) && right.to_int(out b)) {
                        left = new PValue.of_int(b != 0 ? a / b : 0);
                    }
                } else {
                    return left;
                }
            }
        }

        private PValue parse_unary() {
            skip_ws();
            if (peek() == '!' && peek_at(1) != '=') {
                pos++;
                return new PValue.of_bool(!parse_unary().truthy());
            }
            if (peek() == '-') {
                pos++;
                var v = parse_unary();
                int64 n;
                if (v.to_int(out n)) {
                    return new PValue.of_int(-n);
                }
                return new PValue.of_string("-" + v.to_text());
            }
            if (peek() == '+') {
                pos++;
                return parse_unary();
            }
            return parse_primary();
        }

        private PValue parse_primary() {
            skip_ws();
            char c = peek();

            if (c == '(') {
                pos++;
                var v = parse_until_close();
                if (peek() == ')') {
                    pos++;
                }
                return v;
            }
            if (c == '"' || c == '\'') {
                return new PValue.of_string(read_string_literal());
            }
            if (c >= '0' && c <= '9') {
                int start = pos;
                while (pos < source.length && source[pos] >= '0' && source[pos] <= '9') {
                    pos++;
                }
                int64 n;
                if (int64.try_parse(source.substring(start, pos - start), out n)) {
                    return new PValue.of_int(n);
                }
                return new PValue.of_string(source.substring(start, pos - start));
            }
            if ((c == '$' || c == '%') && Preprocessor.is_ident_start(peek_at(1))) {
                pos++;
                string name = c.to_string() + read_identifier();
                if (peek_after_ws() == '(') {
                    skip_ws();
                    var named = new Gee.HashMap<string, PValue>();
                    var args = read_call_args(named);
                    PValue? r = c == '%'
                        ? pp.call_builtin(name.substring(1), args)
                        : pp.call_function_values(name, args, named);
                    return r ?? new PValue.of_string(name + "(" + join_args(args) + ")");
                }
                if (c == '%') {
                    return new PValue.of_string(name);
                }
                return pp.lookup_expression_variable(name) ?? new PValue.of_string(name);
            }
            if (Preprocessor.is_ident_start(c)) {
                string name = read_identifier();
                if (peek_after_ws() == '(') {
                    skip_ws();
                    var named = new Gee.HashMap<string, PValue>();
                    var args = read_call_args(named);
                    return pp.call_function_values(name, args, named) ??
                           new PValue.of_string(name + "(" + join_args(args) + ")");
                }
                return pp.lookup_expression_variable(name) ?? new PValue.of_string(name);
            }
            if (pos >= source.length || is_operator_char(c)) {
                // A stray operator or ')' — consume it so parsing always advances
                if (pos < source.length && c != ')' && c != ',') {
                    pos++;
                }
                return new PValue.of_string("");
            }
            // Other text (#FFFFFF, .5, ...) is a literal up to whitespace or an operator
            int start = pos;
            while (pos < source.length && source[pos] != ' ' && source[pos] != '\t' &&
                   !is_operator_char(source[pos]) && source[pos] != '"' && source[pos] != '\'') {
                pos++;
            }
            return new PValue.of_string(source.substring(start, pos - start));
        }

        // Juxtaposed values up to ')' , ',' or the end; the last one wins
        private PValue parse_until_close() {
            var v = new PValue.of_string("");
            skip_ws();
            while (pos < source.length && peek() != ')' && peek() != ',') {
                int before = pos;
                v = parse_or();
                skip_ws();
                if (pos == before) {
                    pos++;
                }
            }
            return v;
        }

        /**
         * "(a, $name = b, ...)" with `pos` at '('. Each argument is evaluated;
         * "$name = value" arguments go to `named`.
         */
        private Gee.ArrayList<PValue> read_call_args(Gee.HashMap<string, PValue> named) {
            var list = new Gee.ArrayList<PValue>();
            if (peek() != '(') {
                return list;
            }
            pos++;
            skip_ws();
            if (peek() == ')') {
                pos++;
                return list;
            }
            while (pos < source.length) {
                skip_ws();
                string? arg_name = read_named_arg_prefix();
                var v = parse_until_close();
                if (arg_name != null) {
                    named.set(arg_name, v);
                } else {
                    list.add(v);
                }
                if (peek() == ',') {
                    pos++;
                    continue;
                }
                if (peek() == ')') {
                    pos++;
                }
                break;
            }
            return list;
        }

        // "$name =" (not "==") at pos: consumes it and returns "$name"
        private string? read_named_arg_prefix() {
            if (peek() != '$' || !Preprocessor.is_ident_start(peek_at(1))) {
                return null;
            }
            int save = pos;
            pos++;
            string name = "$" + read_identifier();
            skip_ws();
            if (peek() == '=' && peek_at(1) != '=') {
                pos++;
                return name;
            }
            pos = save;
            return null;
        }

        // ── Lexing helpers ────────────────────────────────────────

        private static bool is_operator_char(char c) {
            return c == '+' || c == '-' || c == '*' || c == '/' || c == '<' || c == '>' ||
                   c == '=' || c == '!' || c == '&' || c == '|' || c == '(' || c == ')' || c == ',';
        }

        private void skip_ws() {
            while (pos < source.length && (source[pos] == ' ' || source[pos] == '\t')) {
                pos++;
            }
        }

        private char peek() {
            return pos < source.length ? source[pos] : '\0';
        }

        private char peek_at(int offset) {
            return pos + offset < source.length ? source[pos + offset] : '\0';
        }

        private char peek_after_ws() {
            int p = pos;
            while (p < source.length && (source[p] == ' ' || source[p] == '\t')) {
                p++;
            }
            return p < source.length ? source[p] : '\0';
        }

        private bool match_op(string op) {
            skip_ws();
            if (pos + op.length > source.length) {
                return false;
            }
            for (int i = 0; i < op.length; i++) {
                if (source[pos + i] != op[i]) {
                    return false;
                }
            }
            // "<" / ">" must not take the first half of "<=" / ">="
            if ((op == "<" || op == ">") && peek_at(1) == '=') {
                return false;
            }
            pos += op.length;
            return true;
        }

        // No escapes: PlantUML keeps "\n" as two characters and "\" is a backslash
        private string read_string_literal() {
            char quote = source[pos];
            pos++;
            int start = pos;
            while (pos < source.length && source[pos] != quote) {
                pos++;
            }
            string s = source.substring(start, pos - start);
            if (pos < source.length) {
                pos++;
            }
            return s;
        }

        private string read_identifier() {
            int start = pos;
            while (pos < source.length && Preprocessor.is_ident_char(source[pos])) {
                pos++;
            }
            return source.substring(start, pos - start);
        }

        // Numbers compare numerically, anything else as text
        public static int compare(PValue a, PValue b) {
            if (a.kind == PValue.INT && b.kind == PValue.INT) {
                return a.num < b.num ? -1 : (a.num > b.num ? 1 : 0);
            }
            return strcmp(a.to_text(), b.to_text());
        }

        private static string join_args(Gee.ArrayList<PValue> args) {
            var sb = new StringBuilder();
            for (int i = 0; i < args.size; i++) {
                if (i > 0) {
                    sb.append(", ");
                }
                sb.append(args[i].to_text());
            }
            return sb.str;
        }
    }
}
