/* RegexDiagramParser.vala — recursive descent parser for PlantUML @startregex */
namespace GDiagram {

public class RegexDiagramParser : Object {
    private RegexDiagram diagram;
    private string pattern;
    private int pos;

    public RegexDiagramParser() {}

    public RegexDiagram parse(string source) {
        this.diagram = new RegexDiagram();

        // Extract the regex pattern from source
        string extracted = extract_pattern(source);
        if (extracted.length == 0) {
            return diagram;
        }

        diagram.pattern = extracted;
        this.pattern = extracted;
        this.pos = 0;

        diagram.root = parse_alternation();

        return diagram;
    }

    private string extract_pattern(string source) {
        string[] lines = source.split("\n");
        var sb = new StringBuilder();

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower == "@startregex" || lower == "@endregex") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            if (sb.len > 0) sb.append("\n");
            sb.append(trimmed);
        }

        return sb.str.strip();
    }

    private RegexNode parse_alternation() {
        var first = parse_sequence_node();

        var alternatives = new Gee.ArrayList<RegexNode>();
        alternatives.add(first);

        while (pos < pattern.length && pattern[pos] == '|') {
            pos++;  // consume |
            alternatives.add(parse_sequence_node());
        }

        if (alternatives.size == 1) return first;

        var alt = new RegexNode(RegexNodeType.ALTERNATION);
        alt.children.add_all(alternatives);
        return alt;
    }

    private RegexNode parse_sequence_node() {
        var items = new Gee.ArrayList<RegexNode>();

        while (pos < pattern.length) {
            char c = (char) pattern[pos];
            if (c == '|' || c == ')') break;

            var atom = parse_quantified();
            if (atom != null) {
                items.add(atom);
            } else {
                break;
            }
        }

        if (items.size == 0) return new RegexNode(RegexNodeType.SEQUENCE);
        if (items.size == 1) return items.get(0);

        var seq = new RegexNode(RegexNodeType.SEQUENCE);
        seq.children.add_all(items);
        return seq;
    }

    private RegexNode? parse_quantified() {
        var atom = parse_atom();
        if (atom == null) return null;

        // Check for quantifier
        if (pos < pattern.length) {
            char c = (char) pattern[pos];
            int min_c = 0;
            int max_c = -1;
            bool has_quantifier = false;

            if (c == '*') {
                min_c = 0; max_c = -1; has_quantifier = true; pos++;
            } else if (c == '+') {
                min_c = 1; max_c = -1; has_quantifier = true; pos++;
            } else if (c == '?') {
                min_c = 0; max_c = 1; has_quantifier = true; pos++;
            } else if (c == '{') {
                has_quantifier = parse_brace_quantifier(out min_c, out max_c);
            }

            if (has_quantifier) {
                bool greedy = true;
                if (pos < pattern.length && pattern[pos] == '?') {
                    greedy = false;
                    pos++;
                }

                var quant = new RegexNode(RegexNodeType.QUANTIFIER);
                quant.min_count = min_c;
                quant.max_count = max_c;
                quant.greedy = greedy;
                quant.children.add(atom);
                return quant;
            }
        }

        return atom;
    }

    private bool parse_brace_quantifier(out int min_c, out int max_c) {
        min_c = 0;
        max_c = -1;
        int save_pos = pos;
        pos++;  // consume {

        var num = new StringBuilder();
        while (pos < pattern.length && pattern[pos].isdigit()) {
            num.append_c((char) pattern[pos]);
            pos++;
        }

        if (num.len == 0) {
            pos = save_pos;
            return false;
        }

        min_c = int.parse(num.str);
        max_c = min_c;

        if (pos < pattern.length && pattern[pos] == ',') {
            pos++;
            var num2 = new StringBuilder();
            while (pos < pattern.length && pattern[pos].isdigit()) {
                num2.append_c((char) pattern[pos]);
                pos++;
            }
            if (num2.len > 0) {
                max_c = int.parse(num2.str);
            } else {
                max_c = -1;  // unlimited
            }
        }

        if (pos < pattern.length && pattern[pos] == '}') {
            pos++;
            return true;
        }

        pos = save_pos;
        return false;
    }

    private RegexNode? parse_atom() {
        if (pos >= pattern.length) return null;
        char c = (char) pattern[pos];

        // Group: ( ... )
        if (c == '(') {
            pos++;
            // Check for (?:...) non-capturing group
            if (pos + 1 < pattern.length && pattern[pos] == '?' && pattern[pos + 1] == ':') {
                pos += 2;
            }
            var inner = parse_alternation();
            if (pos < pattern.length && pattern[pos] == ')') pos++;
            var grp = new RegexNode(RegexNodeType.GROUP);
            grp.children.add(inner);
            return grp;
        }

        // Character class: [ ... ]
        if (c == '[') {
            return parse_char_class();
        }

        // Anchors
        if (c == '^') {
            pos++;
            return new RegexNode.anchor("^");
        }
        if (c == '$') {
            pos++;
            return new RegexNode.anchor("$");
        }

        // Dot (any character)
        if (c == '.') {
            pos++;
            return new RegexNode.dot();
        }

        // Escape sequence
        if (c == '\\' && pos + 1 < pattern.length) {
            pos++;
            char ec = (char) pattern[pos];
            pos++;
            // Common shorthand classes
            switch (ec) {
                case 'd': return new RegexNode.char_class("\\d");
                case 'D': return new RegexNode.char_class("\\D");
                case 'w': return new RegexNode.char_class("\\w");
                case 'W': return new RegexNode.char_class("\\W");
                case 's': return new RegexNode.char_class("\\s");
                case 'S': return new RegexNode.char_class("\\S");
                case 'b': return new RegexNode.anchor("\\b");
                case 'B': return new RegexNode.anchor("\\B");
                default:
                    return new RegexNode.literal(ec.to_string());
            }
        }

        // Literal character
        if (c != '|' && c != ')' && c != '*' && c != '+' && c != '?' && c != '{') {
            pos++;
            return new RegexNode.literal(c.to_string());
        }

        return null;
    }

    private RegexNode parse_char_class() {
        pos++;  // consume [
        var sb = new StringBuilder();
        sb.append("[");

        if (pos < pattern.length && pattern[pos] == '^') {
            sb.append("^");
            pos++;
        }

        // First ] doesn't close the class
        bool first = true;
        while (pos < pattern.length) {
            char c = (char) pattern[pos];
            if (c == ']' && !first) {
                pos++;
                break;
            }
            first = false;
            if (c == '\\' && pos + 1 < pattern.length) {
                sb.append_c(c);
                pos++;
                sb.append_c((char) pattern[pos]);
                pos++;
            } else {
                sb.append_c(c);
                pos++;
            }
        }
        sb.append("]");

        return new RegexNode.char_class(sb.str);
    }
}

}
