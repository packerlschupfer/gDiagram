/* EbnfDiagramParser.vala — parser for PlantUML @startebnf grammar rules */
namespace GDiagram {

public class EbnfDiagramParser : Object {
    private EbnfDiagram diagram;
    private string expr_text;
    private int pos;

    public EbnfDiagramParser() {}

    public EbnfDiagram parse(string source) {
        this.diagram = new EbnfDiagram();
        parse_ebnf(source);
        return diagram;
    }

    private void parse_ebnf(string source) {
        string[] lines = source.split("\n");
        var rule_buffer = new StringBuilder();
        int rule_start_line = 0;

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'") || trimmed.has_prefix("(*")) continue;

            string lower = trimmed.down();
            if (lower == "@startebnf" || lower == "@endebnf") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            // Accumulate rule text until we see a ;
            if (rule_buffer.len == 0) {
                rule_start_line = i + 1;
            }
            if (rule_buffer.len > 0) rule_buffer.append(" ");
            rule_buffer.append(trimmed);

            if (trimmed.has_suffix(";")) {
                parse_rule(rule_buffer.str, rule_start_line);
                rule_buffer.truncate(0);
            }
        }

        // Handle rule without trailing semicolon
        if (rule_buffer.len > 0) {
            parse_rule(rule_buffer.str, rule_start_line);
        }
    }

    private void parse_rule(string text, int lineno) {
        // Format: name = expr ;
        string rule_text = text.strip();
        if (rule_text.has_suffix(";")) {
            rule_text = rule_text.substring(0, rule_text.length - 1).strip();
        }

        int eq_pos = rule_text.index_of("=");
        if (eq_pos < 0) {
            // Could be a bare expression or comment, skip
            return;
        }

        // Make sure it's not == (which could be in an expression)
        if (eq_pos + 1 < rule_text.length && rule_text[eq_pos + 1] == '=') {
            return;
        }

        string name = rule_text.substring(0, eq_pos).strip();
        string body_text = rule_text.substring(eq_pos + 1).strip();

        if (name.length == 0) return;

        EbnfExpr? body = parse_expression(body_text);
        if (body == null) {
            body = new EbnfExpr(EbnfExprType.TERMINAL, body_text);
        }

        diagram.rules.add(new EbnfRule(name, body, lineno));
    }

    private EbnfExpr? parse_expression(string text) {
        this.expr_text = text.strip();
        this.pos = 0;
        return parse_alternation();
    }

    private EbnfExpr? parse_alternation() {
        var first = parse_sequence();
        if (first == null) return null;

        var alternatives = new Gee.ArrayList<EbnfExpr>();
        alternatives.add(first);

        while (pos < expr_text.length) {
            skip_whitespace();
            if (pos >= expr_text.length || expr_text[pos] != '|') break;
            pos++;  // consume |
            var next = parse_sequence();
            if (next == null) break;
            alternatives.add(next);
        }

        if (alternatives.size == 1) return first;
        var alt = new EbnfExpr(EbnfExprType.ALTERNATION);
        alt.children.add_all(alternatives);
        return alt;
    }

    private EbnfExpr? parse_sequence() {
        var items = new Gee.ArrayList<EbnfExpr>();

        while (pos < expr_text.length) {
            skip_whitespace();
            if (pos >= expr_text.length) break;

            char c = expr_text[pos];
            // Stop at | (alternation), ) ] } end-of-group
            if (c == '|' || c == ')' || c == ']' || c == '}') break;

            // Skip comma separators
            if (c == ',') {
                pos++;
                continue;
            }

            var item = parse_atom();
            if (item == null) break;
            items.add(item);
        }

        if (items.size == 0) return null;
        if (items.size == 1) return items.get(0);

        var seq = new EbnfExpr(EbnfExprType.SEQUENCE);
        seq.children.add_all(items);
        return seq;
    }

    private EbnfExpr? parse_atom() {
        skip_whitespace();
        if (pos >= expr_text.length) return null;

        char c = expr_text[pos];

        // Quoted terminal: "..." or '...'
        if (c == '"' || c == '\'') {
            return parse_terminal(c);
        }

        // Grouping: ( expr )
        if (c == '(') {
            pos++;
            var inner = parse_alternation();
            skip_whitespace();
            if (pos < expr_text.length && expr_text[pos] == ')') pos++;
            if (inner == null) return new EbnfExpr(EbnfExprType.GROUP);
            var grp = new EbnfExpr(EbnfExprType.GROUP);
            grp.children.add(inner);
            return grp;
        }

        // Repetition: { expr }
        if (c == '{') {
            pos++;
            var inner = parse_alternation();
            skip_whitespace();
            if (pos < expr_text.length && expr_text[pos] == '}') pos++;
            var rep = new EbnfExpr(EbnfExprType.REPETITION);
            if (inner != null) rep.children.add(inner);
            return rep;
        }

        // Optional: [ expr ]
        if (c == '[') {
            pos++;
            var inner = parse_alternation();
            skip_whitespace();
            if (pos < expr_text.length && expr_text[pos] == ']') pos++;
            var opt = new EbnfExpr(EbnfExprType.OPTIONAL);
            if (inner != null) opt.children.add(inner);
            return opt;
        }

        // Special sequence: ? ... ?
        if (c == '?') {
            pos++;
            var sb = new StringBuilder();
            while (pos < expr_text.length && expr_text[pos] != '?') {
                sb.append_c((char) expr_text[pos]);
                pos++;
            }
            if (pos < expr_text.length) pos++;  // consume closing ?
            return new EbnfExpr(EbnfExprType.SPECIAL, sb.str.strip());
        }

        // Identifier (nonterminal)
        if (c.isalpha() || c == '_') {
            return parse_nonterminal();
        }

        // Unknown character, skip
        pos++;
        return null;
    }

    private EbnfExpr? parse_terminal(char quote) {
        pos++;  // consume opening quote
        var sb = new StringBuilder();
        while (pos < expr_text.length && expr_text[pos] != quote) {
            if (expr_text[pos] == '\\' && pos + 1 < expr_text.length) {
                pos++;
                sb.append_c((char) expr_text[pos]);
            } else {
                sb.append_c((char) expr_text[pos]);
            }
            pos++;
        }
        if (pos < expr_text.length) pos++;  // consume closing quote
        return new EbnfExpr.terminal(sb.str);
    }

    private EbnfExpr? parse_nonterminal() {
        var sb = new StringBuilder();
        while (pos < expr_text.length) {
            char c = expr_text[pos];
            if (c.isalpha() || c.isdigit() || c == '_' || c == ' ') {
                sb.append_c(c);
                pos++;
            } else {
                break;
            }
        }
        string name = sb.str.strip();
        if (name.length == 0) return null;
        return new EbnfExpr.nonterminal(name);
    }

    private void skip_whitespace() {
        while (pos < expr_text.length && expr_text[pos].isspace()) {
            pos++;
        }
    }
}

}
