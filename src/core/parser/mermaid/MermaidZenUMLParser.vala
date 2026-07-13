/* MermaidZenUMLParser.vala — Mermaid ZenUML parser */
namespace GDiagram {

/**
 * ZenUML: statements are split at newlines, ";", "{" and "}" (outside parentheses and
 * quotes), so "A.m() { B.n() }" on one line works. A stack of open call bodies and
 * control blocks gives every call its caller (the enclosing callee, or an implicit
 * starter at the top level) and every "return" its receiver; control blocks (if / else,
 * loop, opt, par, try / catch / finally, critical, section) become events for frames.
 * Only lines with "->" used to be read, the caller of a nested call without "A ->" was a
 * hard-coded "Client", and the "}" of an "if" popped the call stack.
 */
public class MermaidZenUMLParser : Object {
    private MermaidZenUML diagram;
    private Gee.HashSet<string> seen_participants;

    public const string STARTER = "_STARTER_";

    private class Stmt : Object {
        public string text;
        public bool opens;    // followed by "{"
        public bool closes;   // a "}"
        public int line;
        public string? comment;   // the "// ..." seen just before it

        public Stmt(string text, bool opens, bool closes, int line) {
            this.text = text;
            this.opens = opens;
            this.closes = closes;
            this.line = line;
        }
    }

    private class Frame : Object {
        public bool braceless;   // "if (x)" with no "{": runs to the end of its block
        public bool is_call;
        public string callee = "";
        public string caller = "";
        public string keyword = "";
        public string? assignee = null;
        public bool returned = false;
        public string prefix = "";
        public int counter = 0;
    }

    private Gee.ArrayList<Frame> stack;
    private Frame root;

    public MermaidZenUMLParser() {}

    public MermaidZenUML parse(string source) {
        this.diagram = new MermaidZenUML();
        this.seen_participants = new Gee.HashSet<string>();
        this.stack = new Gee.ArrayList<Frame>();
        this.root = new Frame();

        var stmts = scan(source);
        for (int i = 0; i < stmts.size; i++) {
            var st = stmts[i];
            if (st.closes) {
                close_frame(stmts, ref i);
                continue;
            }
            handle(st);
        }
        while (stack.size > 0) {
            var fr = stack.remove_at(stack.size - 1);
            end_frame(fr, 0);
        }
        return diagram;
    }

    // ------------------------------------------------------------ scanning

    private static Gee.ArrayList<Stmt> scan(string source) {
        var list = new Gee.ArrayList<Stmt>();
        string? pending_comment = null;
        var sb = new StringBuilder();
        int line = 1;
        int start_line = 1;
        int paren = 0;
        char quote = 0;
        bool header_done = false;
        int n = source.length;
        for (int k = 0; k < n; k++) {
            char c = source[k];
            if (quote != 0) {
                if (c == quote) {
                    quote = 0;
                }
                if (c == '\n') {
                    line++;
                }
                sb.append_c(c);
                continue;
            }
            if (c == '"' ) {
                quote = c;
                sb.append_c(c);
                continue;
            }
            if (c == '/' && k + 1 < n && source[k + 1] == '/' && paren == 0) {
                // ZenUML shows a comment beside the statement it precedes
                int from = k + 2;
                while (k < n && source[k] != '\n') {
                    k++;
                }
                string text = source.substring(from, k - from).strip();
                if (text.length > 0) {
                    pending_comment = pending_comment == null ? text : pending_comment + "\n" + text;
                }
                k--;
                continue;
            }
            if (c == '(') {
                paren++;
            } else if (c == ')' && paren > 0) {
                paren--;
            }
            if (paren > 0 && c != '\n') {
                sb.append_c(c);
                continue;
            }
            if (c == '\n' || c == ';' || c == '{' || c == '}') {
                string t = sb.str.strip();
                if (!header_done && t.length > 0) {
                    header_done = true;
                    if (t.down() == "zenuml") {
                        t = "";
                    }
                }
                if (t.length > 0 || c == '{') {
                    var st = new Stmt(t, c == '{', false, start_line);
                    st.comment = pending_comment;
                    pending_comment = null;
                    list.add(st);
                }
                if (c == '}') {
                    list.add(new Stmt("", false, true, line));
                }
                sb.truncate();
                if (c == '\n') {
                    line++;
                    paren = 0;
                }
                start_line = line;
                continue;
            }
            if (sb.len == 0 && c.isspace()) {
                continue;
            }
            if (sb.len == 0) {
                start_line = line;
            }
            sb.append_c(c);
        }
        string rest = sb.str.strip();
        if (rest.length > 0 && !(!header_done && rest.down() == "zenuml")) {
            var last = new Stmt(rest, false, false, start_line);
            last.comment = pending_comment;
            list.add(last);
        }
        // "A.m()" or "if (x)" with its "{" on the next line
        var merged = new Gee.ArrayList<Stmt>();
        foreach (var st in list) {
            if (st.opens && st.text.length == 0 && merged.size > 0) {
                var prev = merged[merged.size - 1];
                if (!prev.opens && !prev.closes) {
                    prev.opens = true;
                    if (prev.comment == null) prev.comment = st.comment;
                    continue;
                }
            }
            merged.add(st);
        }
        return merged;
    }

    // ------------------------------------------------------------ statements

    private Frame top() {
        return stack.size > 0 ? stack[stack.size - 1] : root;
    }

    private Frame? innermost_call() {
        for (int k = stack.size - 1; k >= 0; k--) {
            if (stack[k].is_call) {
                return stack[k];
            }
        }
        return null;
    }

    private int call_depth() {
        int d = 0;
        foreach (var fr in stack) {
            if (fr.is_call) {
                d++;
            }
        }
        return d;
    }

    private string next_number() {
        var fr = top();
        fr.counter++;
        return fr.prefix.length > 0 ? "%s.%d".printf(fr.prefix, fr.counter) : fr.counter.to_string();
    }

    private string current_caller() {
        var call = innermost_call();
        return call != null ? call.callee : STARTER;
    }

    private void declare(string name, string type, int line, string? color = null,
                         string? stereotype = null) {
        if (seen_participants.contains(name)) {
            foreach (var p in diagram.participants) {
                if (p.name != name) continue;
                if (color != null) p.color = color;
                if (stereotype != null) p.stereotype = stereotype;
            }
            return;
        }
        seen_participants.add(name);
        var p = new ZenParticipant(name, type, line);
        p.color = color;
        p.stereotype = stereotype;
        if (name == STARTER) {
            p.is_starter = true;
            diagram.participants.insert(0, p);
        } else {
            diagram.participants.add(p);
        }
    }

    private static bool is_identifier(string s) {
        if (s.length == 0 || !(s[0].isalpha() || s[0] == '_')) {
            return false;
        }
        for (int k = 0; k < s.length; k++) {
            if (!(s[k].isalnum() || s[k] == '_')) {
                return false;
            }
        }
        return true;
    }

    private static string unquote(string s) {
        if (s.length >= 2 && s.has_prefix("\"") && s.has_suffix("\"")) {
            return s.substring(1, s.length - 2);
        }
        return s;
    }

    private void handle(Stmt st) {
        string t = st.text;
        string lower = t.down();
        if (t.length == 0) {
            if (st.opens) {
                // a bare "{": keep the braces balanced
                var fr = new Frame();
                fr.is_call = false;
                fr.keyword = "";
                fr.prefix = top().prefix;
                stack.add(fr);
            }
            return;
        }
        if (lower.has_prefix("title ") || lower == "title") {
            diagram.title = t.substring(5).strip();
            return;
        }
        if (t.has_prefix("@") && !lower.has_prefix("@return") && !lower.has_prefix("@reply")) {
            parse_participant(t, st.line);
            return;
        }
        if (lower.has_prefix("return") && (t.length == 6 || t[6].isspace()) ||
            lower.has_prefix("@return") || lower.has_prefix("@reply")) {
            parse_return(t, st.line);
            return;
        }
        if (try_block(t, st)) {
            return;
        }
        // a participant on its own: "A", "\"Long name\"", "<<stereo>> A", "A as B"
        string decl = t;
        string? stereo = take_stereotype(ref decl);
        int as_pos = decl.index_of(" as ");
        if (as_pos > 0) {
            decl = decl.substring(0, as_pos).strip();
        }
        if (!st.opens && (is_identifier(decl) || (decl.has_prefix("\"") && decl.has_suffix("\"") && decl.length > 2))) {
            declare(unquote(decl), "Participant", st.line, null, stereo);
            return;
        }
        parse_message(t, st);
    }

    // @Type [<<Stereotype>>] Name [#color], @Starter(Name)
    private void parse_participant(string line, int lineno) {
        string rest = line.substring(1).strip();
        if (rest.down().has_prefix("starter(")) {
            int close = rest.index_of(")");
            if (close > 8) {
                string name = rest.substring(8, close - 8).strip();
                declare(name, "Actor", lineno);
            }
            return;
        }
        // "@<<service>> Ext": a stereotype without a type
        string? stereotype = take_stereotype(ref rest);
        string[] tokens = rest.split(" ");
        var parts = new Gee.ArrayList<string>();
        foreach (string tk in tokens) {
            if (tk.strip().length > 0) {
                parts.add(tk.strip());
            }
        }
        if (parts.size == 0) {
            return;
        }
        if (parts.size < 2 && stereotype == null) {
            return;
        }
        string actor_type = parts.size > 1 ? parts[0] : "Participant";
        string? color = null;
        int name_idx = parts.size - 1;
        if (parts[name_idx].has_prefix("#")) {
            color = parts[name_idx];
            name_idx--;
        }
        int lowest = parts.size > 1 ? 1 : 0;
        while (name_idx >= lowest && (parts[name_idx].has_prefix("<<") || parts[name_idx].has_suffix(">>"))) {
            name_idx--;
        }
        if (name_idx < lowest) {
            return;
        }
        declare(unquote(parts[name_idx]), actor_type, lineno, color, stereotype);
    }

    // "<<service>> Name" / "@Type <<service>> Name": returns "service", removing it
    private static string? take_stereotype(ref string rest) {
        int open = rest.index_of("<<");
        if (open < 0) {
            return null;
        }
        int close = rest.index_of(">>", open + 2);
        if (close < 0) {
            return null;
        }
        string text = rest.substring(open + 2, close - open - 2).strip();
        rest = (rest.substring(0, open) + " " + rest.substring(close + 2)).strip();
        return text.length > 0 ? text : null;
    }

    private bool try_block(string t, Stmt st) {
        string lower = t.down();
        string[] keywords = { "else if", "if", "else", "while", "foreach", "for", "loop", "opt", "par",
                              "try", "catch", "finally", "critical", "section", "group" };
        foreach (string kw in keywords) {
            if (!lower.has_prefix(kw)) {
                continue;
            }
            string after = t.substring(kw.length);
            if (after.length > 0 && (after[0].isalnum() || after[0] == '_' || after[0] == '.')) {
                continue;
            }
            after = after.strip();
            bool parenthesised = after.has_prefix("(") && after.has_suffix(")") && after.length >= 2;
            if (!st.opens && !parenthesised) {
                // "loop x" without braces is not a block; only "if (x)" is
                return false;
            }
            string? cond = null;
            if (parenthesised) {
                cond = after.substring(1, after.length - 2).strip();
            } else if (after.length > 0) {
                cond = after;
            }
            string norm = kw == "foreach" ? "forEach" : kw;
            var ev = new ZenEvent(ZenEventKind.BLOCK_START, st.line);
            ev.keyword = norm;
            ev.condition = cond;
            ev.number = next_number();
            diagram.events.add(ev);
            var fr = new Frame();
            fr.is_call = false;
            fr.keyword = norm;
            fr.prefix = ev.number;
            // ZenUML's grammar lets "if (x)" without braces take the rest of the
            // enclosing block as its body (checked against the Mermaid CLI 11.17)
            fr.braceless = !st.opens;
            stack.add(fr);
            if (kw == "else if" || kw == "else" || kw == "catch" || kw == "finally") {
                // a section without its "if" / "try": treated as a block of its own
                ev.keyword = kw == "catch" || kw == "finally" ? "try" : "if";
                ev.condition = kw == "else" || kw == "finally" ? kw : cond;
            }
            return true;
        }
        return false;
    }

    private void close_frame(Gee.ArrayList<Stmt> stmts, ref int i) {
        // a braceless "if (x)" ends with the block that holds it
        while (stack.size > 0 && stack[stack.size - 1].braceless) {
            end_frame(stack.remove_at(stack.size - 1), stmts[i].line);
        }
        if (stack.size == 0) {
            return;
        }
        var fr = stack.remove_at(stack.size - 1);
        int line = stmts[i].line;
        if (!fr.is_call && fr.keyword.length > 0 && i + 1 < stmts.size) {
            var next = stmts[i + 1];
            string nl = next.text.down();
            bool if_family = fr.keyword == "if";
            bool try_family = fr.keyword == "try";
            string? section = null;
            string? cond = null;
            if (if_family && next.opens && nl.has_prefix("else")) {
                string rest = next.text.substring(4).strip();
                if (rest.down().has_prefix("if")) {
                    rest = rest.substring(2).strip();
                    if (rest.has_prefix("(") && rest.has_suffix(")")) {
                        rest = rest.substring(1, rest.length - 2).strip();
                    }
                    section = "else if";
                    cond = rest;
                } else {
                    section = "else";
                    cond = "else";
                }
            } else if (try_family && next.opens && (nl.has_prefix("catch") || nl.has_prefix("finally"))) {
                bool is_catch = nl.has_prefix("catch");
                section = is_catch ? "catch" : "finally";
                string rest = next.text.substring(is_catch ? 5 : 7).strip();
                cond = is_catch ? ("catch" + (rest.length > 0 ? " " + rest : "")) : "finally";
            }
            if (section != null) {
                var ev = new ZenEvent(ZenEventKind.BLOCK_SECTION, next.line);
                ev.keyword = section;
                ev.condition = cond;
                diagram.events.add(ev);
                stack.add(fr);
                i++;
                return;
            }
        }
        end_frame(fr, line);
    }

    private void end_frame(Frame fr, int line) {
        if (fr.is_call) {
            if (fr.assignee != null && !fr.returned) {
                add_return(fr.callee, fr.caller, fr.assignee, line);
            }
            var ev = new ZenEvent(ZenEventKind.BODY_END, line);
            ev.participant = fr.callee;
            diagram.events.add(ev);
        } else if (fr.keyword.length > 0) {
            diagram.events.add(new ZenEvent(ZenEventKind.BLOCK_END, line));
        }
    }

    private void add_return(string from, string to, string label, int line) {
        var msg = new ZenMessage(from, to, label, line);
        msg.is_return = true;
        msg.depth = call_depth();
        msg.number = next_number();
        diagram.messages.add(msg);
        var ev = new ZenEvent(ZenEventKind.MESSAGE, line);
        ev.message = msg;
        ev.number = msg.number;
        diagram.events.add(ev);
    }

    private void parse_return(string t, int line) {
        string rest;
        string lower = t.down();
        if (lower.has_prefix("@return")) {
            rest = t.substring(7).strip();
        } else if (lower.has_prefix("@reply")) {
            rest = t.substring(6).strip();
        } else {
            rest = t.substring(6).strip();
        }
        // "@return A->B: value"
        int arrow = rest.index_of("->");
        int colon = rest.index_of(":");
        if (arrow > 0 && colon > arrow) {
            string from = rest.substring(0, arrow).strip();
            string to = rest.substring(arrow + 2, colon - arrow - 2).strip();
            declare(from, "Participant", line);
            declare(to, "Participant", line);
            add_return(from, to, rest.substring(colon + 1).strip(), line);
            var c = innermost_call();
            if (c != null) {
                c.returned = true;
            }
            return;
        }
        var call = innermost_call();
        if (call == null) {
            return;
        }
        call.returned = true;
        add_return(call.callee, call.caller, rest.length > 0 ? rest : "return", line);
    }

    private void parse_message(string t, Stmt st) {
        string rest = t;
        string? from = null;

        // async "A->B: text"
        int arrow = index_outside_parens(rest, "->");
        if (arrow >= 0) {
            string lhs = rest.substring(0, arrow).strip();
            string rhs = rest.substring(arrow + 2).strip();
            int colon = rhs.index_of(":");
            int dot = rhs.index_of(".");
            if (colon >= 0 && (dot < 0 || dot > colon)) {
                string to = unquote(rhs.substring(0, colon).strip());
                if (lhs.length == 0 || to.length == 0) {
                    return;
                }
                lhs = unquote(lhs);
                declare(lhs, "Participant", st.line);
                declare(to, "Participant", st.line);
                var msg = new ZenMessage(lhs, to, rhs.substring(colon + 1).strip(), st.line);
                msg.comment = st.comment;
                msg.is_async = true;
                msg.depth = call_depth();
                msg.number = next_number();
                diagram.messages.add(msg);
                var ev = new ZenEvent(ZenEventKind.MESSAGE, st.line);
                ev.message = msg;
                ev.number = msg.number;
                diagram.events.add(ev);
                return;
            }
            if (lhs.length > 0) {
                from = unquote(lhs);
            }
            rest = rhs;
        }

        // assignment: "x = B.m()", "Type x = B.m()"
        string? assignee = null;
        int eq = index_outside_parens(rest, "=");
        int first_paren = rest.index_of("(");
        if (eq > 0 && (first_paren < 0 || eq < first_paren) && (eq + 1 >= rest.length || rest[eq + 1] != '=')) {
            string lhs = rest.substring(0, eq).strip();
            string[] words = lhs.split(" ");
            assignee = words[words.length - 1];
            rest = rest.substring(eq + 1).strip();
        }

        bool is_create = false;
        string to_name;
        string method_name;
        string? params_str = null;
        if (rest.has_prefix("new ")) {
            is_create = true;
            rest = rest.substring(4).strip();
        }
        int paren = rest.index_of("(");
        int dot = rest.index_of(".");
        if (!is_create && dot > 0 && (paren < 0 || dot < paren)) {
            to_name = unquote(rest.substring(0, dot).strip());
            string after = rest.substring(dot + 1);
            int po = after.index_of("(");
            int pc = after.last_index_of(")");
            if (po >= 0) {
                method_name = after.substring(0, po).strip();
                params_str = pc > po ? after.substring(po + 1, pc - po - 1).strip() : "";
            } else {
                method_name = after.strip();
            }
        } else if (paren >= 0) {
            string name = rest.substring(0, paren).strip();
            int pc = rest.last_index_of(")");
            params_str = pc > paren ? rest.substring(paren + 1, pc - paren - 1).strip() : "";
            if (is_create) {
                to_name = name;
                method_name = "«create»";
            } else {
                // "m()": a call on the current participant itself
                to_name = from ?? current_caller();
                method_name = name;
            }
        } else if (is_create) {
            to_name = rest.strip();
            method_name = "«create»";
        } else {
            to_name = unquote(rest.strip());
            method_name = to_name;
        }
        if (to_name.length == 0 || method_name.length == 0 || to_name.contains(" ")) {
            return;
        }

        string actual_from = from ?? current_caller();
        declare(actual_from, actual_from == STARTER ? "Actor" : "Participant", st.line);
        declare(to_name, "Participant", st.line);

        string label = method_name;
        if (params_str != null && params_str.length > 0 && !is_create) {
            label = "%s(%s)".printf(method_name, params_str);
        } else if (params_str != null && !is_create) {
            label = "%s()".printf(method_name);
        }
        var msg = new ZenMessage(actual_from, to_name, label, st.line);
        msg.comment = st.comment;
        msg.params_str = params_str;
        msg.depth = call_depth();
        msg.is_create = is_create;
        msg.has_body = st.opens;
        msg.number = next_number();
        diagram.messages.add(msg);
        var ev = new ZenEvent(ZenEventKind.MESSAGE, st.line);
        ev.message = msg;
        ev.number = msg.number;
        diagram.events.add(ev);

        if (st.opens) {
            var fr = new Frame();
            fr.is_call = true;
            fr.callee = to_name;
            fr.caller = actual_from;
            fr.assignee = assignee;
            fr.prefix = msg.number;
            stack.add(fr);
        } else {
            if (!is_create) {
                if (assignee != null) {
                    add_return(to_name, actual_from, assignee, st.line);
                }
                // a call without a body: a short activation
                var end = new ZenEvent(ZenEventKind.BODY_END, st.line);
                end.participant = to_name;
                diagram.events.add(end);
            }
        }
    }

    private static int index_outside_parens(string s, string needle) {
        int depth = 0;
        bool quoted = false;
        for (int k = 0; k + needle.length <= s.length; k++) {
            char c = s[k];
            if (c == '"') {
                quoted = !quoted;
            } else if (!quoted && c == '(') {
                depth++;
            } else if (!quoted && c == ')' && depth > 0) {
                depth--;
            } else if (!quoted && depth == 0 && s.substring(k, needle.length) == needle) {
                return k;
            }
        }
        return -1;
    }
}

}
