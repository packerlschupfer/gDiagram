namespace GDiagram {

/*
 * Mermaid block-beta. Statements follow Mermaid's grammar rather than one per line:
 * a row holds any number of blocks ("a["A"]:2 space b(("B"))"), links chain blocks
 * ("a --> b -- "x" --> c"), "block:id ... end" groups nest with their own
 * "columns N", and "style" / "classDef" / "class" lines style blocks. A block that
 * is mentioned again (in a link, say) keeps its first position, as in Mermaid.
 */
public class MermaidBlockParser : Object {
    private MermaidBlock diagram;
    private Gee.ArrayList<BlockNode> groups;
    private int anon_groups;
    private int space_count;
    private int line_num;
    private string text;
    private int pos;

    // Shape openers, longest first, with their closers
    private const string[] OPENERS = { "(((", "((", "([", "(", "[[", "[(", "[/", "[\\", "[", "{{", "{", ">", "<[" };

    // Compiled once: match_link() built both of these on every statement-scan step
    private static Regex? labelled_link = null;
    private static Regex? plain_link = null;

    private static void init_regex() {
        if (labelled_link != null) return;
        try {
            labelled_link = new Regex(
                "[xo<]?(?:--|==|-\\.)\\s*\"([^\"]*)\"\\s*[xo<]?(--+[-xo>]|==+[=xo>]|-?\\.+-[xo>]?)");
            plain_link = new Regex("[xo<]?(--+[-xo>]|==+[=xo>]|-?\\.+-[xo>]?|~~~+)");
        } catch (RegexError e) {
            warning("MermaidBlockParser regex: %s", e.message);
        }
    }

    public MermaidBlockParser() {}

    public MermaidBlock parse(string source) {
        init_regex();
        diagram = new MermaidBlock();
        groups = new Gee.ArrayList<BlockNode>();
        anon_groups = 0;
        space_count = 0;

        // Front matter and "%%{init}%%" directives — including ones spanning several
        // lines, whose body used to leak in as blocks and hide the block-beta header.
        string? fm_title;
        bool header_ok;
        var lines = MermaidSourceLine.split(source, { "block-beta", "block" },
                                            out fm_title, out header_ok);
        if (fm_title != null) diagram.title = fm_title;

        foreach (var l in lines) {
            line_num = l.line;
            string t = l.text;
            if (t.length == 0) continue;

            string low = t.down();
            if (low.has_prefix("accTitle") || low.has_prefix("acctitle") || low.has_prefix("accdescr")) continue;
            if (low.has_prefix("style ")) {
                parse_style(t.substring(6).strip());
                continue;
            }
            if (low.has_prefix("classdef ")) {
                parse_class_def(t.substring(9).strip());
                continue;
            }
            if (low.has_prefix("class ")) {
                parse_class(t.substring(6).strip());
                continue;
            }

            scan_statements(t);
        }

        return diagram;
    }

    private string? current_group_id() {
        return groups.size > 0 ? groups.get(groups.size - 1).id : null;
    }

    private static bool is_id_char(unichar c) {
        // Mermaid's block id: anything but ( [ \n - ) { } whitespace < > : =
        return !(c == '(' || c == '[' || c == '-' || c == ')' || c == '{' || c == '}' ||
                 c == '<' || c == '>' || c == ':' || c == '=' || c == '"' || c == ',' ||
                 c == '|' || c == ']' || c.isspace());
    }

    private void skip_ws() {
        while (pos < text.length && text[pos].isspace()) pos++;
    }

    // `word` at pos as a whole word
    private bool at_word(string word) {
        if (!text.substring(pos).has_prefix(word)) return false;
        int after = pos + word.length;
        return after >= text.length || !is_id_char(text[after]);
    }

    private int read_int_suffix(int fallback) {
        // ":N"
        if (pos < text.length && text[pos] == ':' && pos + 1 < text.length && text[pos + 1].isdigit()) {
            pos++;
            int start = pos;
            while (pos < text.length && text[pos].isdigit()) pos++;
            return int.parse(text.substring(start, pos - start));
        }
        return fallback;
    }

    private void scan_statements(string line) {
        text = line;
        pos = 0;
        string? prev = null;
        while (true) {
            skip_ws();
            if (pos >= text.length) break;

            if (text.substring(pos).has_prefix("%%")) break;

            if (at_word("end")) {
                pos += 3;
                if (groups.size > 0) groups.remove_at(groups.size - 1);
                prev = null;
                continue;
            }
            if (text.substring(pos).has_prefix("block:")) {
                pos += 6;
                open_group(false);
                prev = null;
                continue;
            }
            if (at_word("block")) {
                pos += 5;
                open_group(true);
                prev = null;
                continue;
            }
            if (at_word("space") || text.substring(pos).has_prefix("space:")) {
                pos += 5;
                int n = read_int_suffix(1);
                for (int k = 0; k < n; k++) {
                    space_count++;
                    var sp = new BlockNode("space_%d".printf(space_count), "space", line_num);
                    sp.is_space = true;
                    sp.shape = "space";
                    sp.group_id = current_group_id();
                    diagram.add_node(sp);
                }
                prev = null;
                continue;
            }
            if (at_word("columns")) {
                pos += 7;
                skip_ws();
                int start = pos;
                while (pos < text.length && !text[pos].isspace()) pos++;
                string v = text.substring(start, pos - start);
                int cols = v == "auto" ? -1 : int.parse(v);
                if (cols == 0) cols = -1;
                if (groups.size > 0) {
                    groups.get(groups.size - 1).columns = cols;
                } else {
                    diagram.columns = cols > 0 ? cols : 0;
                }
                continue;
            }

            if (prev != null) {
                string? label;
                string arrow_end;
                bool thick, dotted, invisible;
                if (match_link(out label, out arrow_end, out thick, out dotted, out invisible)) {
                    skip_ws();
                    var target = parse_node();
                    if (target == null) {
                        prev = null;
                        continue;
                    }
                    var edge = new BlockEdge(prev, target.id, label, line_num);
                    edge.arrow_end = arrow_end;
                    edge.thick = thick;
                    edge.dotted = dotted;
                    edge.invisible = invisible;
                    diagram.add_edge(edge);
                    prev = target.id;
                    continue;
                }
            }

            var node = parse_node();
            if (node == null) {
                // Not a statement we know: skip one character
                pos++;
                prev = null;
                continue;
            }
            prev = node.id;
        }
    }

    private void open_group(bool anonymous) {
        string id;
        string? label = null;
        string? shape = null;
        string dir = "right";
        if (anonymous) {
            anon_groups++;
            id = "block_%d".printf(anon_groups);
        } else {
            id = read_id();
            if (id.length == 0) {
                anon_groups++;
                id = "block_%d".printf(anon_groups);
            }
            if (!read_shape(out shape, out label, out dir)) {
                unclosed_shape();
                return;
            }
        }
        int span = read_int_suffix(1);
        var grp = new BlockNode(id, label ?? "", line_num);
        grp.is_group = true;
        grp.col_span = span;
        grp.group_id = current_group_id();
        diagram.add_node(grp);
        groups.add(grp);
    }

    private string read_id() {
        int start = pos;
        while (pos < text.length) {
            unichar c = text.get_char(pos);
            if (!is_id_char(c)) break;
            pos += c.to_string().length;
        }
        return text.substring(start, pos - start);
    }

    // A block: id, optional shape with label, optional ":N" width
    private BlockNode? parse_node() {
        string id = read_id();
        if (id.length == 0) return null;
        string? shape;
        string? label;
        string dir;
        if (!read_shape(out shape, out label, out dir)) {
            unclosed_shape();
            return null;
        }
        int span = read_int_suffix(0);

        var existing = diagram.find_node(id);
        if (existing != null) {
            if (shape != null) existing.shape = shape;
            if (label != null) existing.label = label;
            if (shape == "block_arrow") existing.arrow_direction = dir;
            if (span > 0) existing.col_span = span;
            return existing;
        }
        var node = new BlockNode(id, label ?? id, line_num);
        node.shape = shape ?? "square";
        node.arrow_direction = dir;
        node.col_span = span > 0 ? span : 1;
        node.group_id = current_group_id();
        diagram.add_node(node);
        return node;
    }

    /**
     * Reads an optional shape and its label at `pos`. Returns false when a shape is
     * opened but never closed ("a[\"unclosed"): Mermaid rejects the diagram, so the
     * caller reports the error instead of inventing a block from the leftover text.
     */
    private bool read_shape(out string? shape, out string? label, out string dir) {
        shape = null;
        label = null;
        dir = "right";
        string rest = text.substring(pos);
        string? opener = null;
        foreach (string o in OPENERS) {
            if (rest.has_prefix(o)) {
                opener = o;
                break;
            }
        }
        if (opener == null) return true;

        string[] closers;
        switch (opener) {
            case "(((": closers = { ")))" }; break;
            case "((":  closers = { "))" }; break;
            case "([":  closers = { "])" }; break;
            case "(":   closers = { ")" }; break;
            case "[[":  closers = { "]]" }; break;
            case "[(":  closers = { ")]" }; break;
            case "[/":  closers = { "/]", "\\]" }; break;
            case "[\\": closers = { "\\]", "/]" }; break;
            case "{{":  closers = { "}}" }; break;
            case "{":   closers = { "}" }; break;
            case "<[":  closers = { "]>" }; break;
            default:    closers = { "]" }; break;   // "[" and ">"
        }

        int p = pos + opener.length;
        string body;
        int close_at = -1;
        string closer = closers[0];
        // A quoted label may hold any closer characters
        int q = p;
        while (q < text.length && text[q] == ' ') q++;
        if (q < text.length && text[q] == '"') {
            int endq = text.index_of("\"", q + 1);
            if (endq < 0) return false;
            body = text.substring(q + 1, endq - q - 1);
            int after = endq + 1;
            while (after < text.length && text[after] == ' ') after++;
            foreach (string c in closers) {
                if (text.substring(after).has_prefix(c)) {
                    close_at = after;
                    closer = c;
                    break;
                }
            }
            if (close_at < 0) return false;
        } else {
            int best = -1;
            foreach (string c in closers) {
                int at = text.index_of(c, p);
                if (at >= 0 && (best < 0 || at < best)) {
                    best = at;
                    closer = c;
                }
            }
            if (best < 0) return false;
            close_at = best;
            body = text.substring(p, best - p).strip();
        }

        switch (opener) {
            case "(((": shape = "doublecircle"; break;
            case "((":  shape = "circle"; break;
            case "([":  shape = "stadium"; break;
            case "(":   shape = "round"; break;
            case "[[":  shape = "subroutine"; break;
            case "[(":  shape = "cylinder"; break;
            case "[/":  shape = closer == "/]" ? "lean_right" : "trapezoid"; break;
            case "[\\": shape = closer == "\\]" ? "lean_left" : "inv_trapezoid"; break;
            case "{{":  shape = "hexagon"; break;
            case "{":   shape = "diamond"; break;
            case ">":   shape = "rect_left_inv_arrow"; break;
            case "<[":  shape = "block_arrow"; break;
            default:    shape = "square"; break;
        }
        label = body;
        pos = close_at + closer.length;

        if (shape == "block_arrow") {
            // "(right)", "(up, down)"...: the first direction decides the drawing
            int save = pos;
            while (pos < text.length && text[pos] == ' ') pos++;
            if (pos < text.length && text[pos] == '(') {
                int end = text.index_of(")", pos);
                if (end > pos) {
                    string[] dirs = text.substring(pos + 1, end - pos - 1).split(",");
                    if (dirs.length > 0 && dirs[0].strip().length > 0) dir = dirs[0].strip().down();
                    pos = end + 1;
                    return true;
                }
            }
            pos = save;
        }
        return true;
    }

    // An unclosed shape ends the line: Mermaid rejects the whole diagram here
    private void unclosed_shape() {
        diagram.errors.add(new ParseError("Unclosed block label", line_num, pos + 1));
        pos = text.length;
    }

    private bool match_link(out string? label, out string arrow_end, out bool thick,
                            out bool dotted, out bool invisible) {
        label = null;
        arrow_end = "";
        thick = false;
        dotted = false;
        invisible = false;
        MatchInfo m;
        string token;
        if (labelled_link == null || plain_link == null) return false;
        try {
            if (labelled_link.match_full(text, -1, pos, RegexMatchFlags.ANCHORED, out m)) {
                label = m.fetch(1);
                token = m.fetch(2);
            } else if (plain_link.match_full(text, -1, pos, RegexMatchFlags.ANCHORED, out m)) {
                token = m.fetch(1);
            } else {
                return false;
            }
            int start, end;
            m.fetch_pos(0, out start, out end);
            pos = end;
        } catch (RegexError e) {
            return false;
        }
        // "-->|label|"
        skip_ws();
        if (pos < text.length && text[pos] == '|') {
            int close = text.index_of("|", pos + 1);
            if (close > pos) {
                label = text.substring(pos + 1, close - pos - 1).strip();
                pos = close + 1;
            }
        }
        if (token.has_prefix("~~~")) {
            invisible = true;
        } else {
            thick = token.contains("==");
            dotted = token.contains(".");
            switch (token[token.length - 1]) {
                case '>': arrow_end = "arrow_point"; break;
                case 'x': arrow_end = "arrow_cross"; break;
                case 'o': arrow_end = "arrow_circle"; break;
                default:  arrow_end = ""; break;
            }
        }
        if (label != null && label.length == 0) label = null;
        return true;
    }

    // "style a,b fill:#f96,stroke:#333"
    private void parse_style(string rest) {
        int sp = rest.index_of_char(' ');
        if (sp <= 0) return;
        string css = rest.substring(sp + 1).strip();
        foreach (string id in rest.substring(0, sp).split(",")) {
            var node = diagram.find_node(id.strip());
            if (node != null) node.styles = css;
        }
    }

    // "classDef name fill:#f96,stroke:#333"
    private void parse_class_def(string rest) {
        int sp = rest.index_of_char(' ');
        if (sp <= 0) return;
        diagram.class_defs.set(rest.substring(0, sp), rest.substring(sp + 1).strip());
    }

    // "class a,b name"
    private void parse_class(string rest) {
        int sp = rest.last_index_of_char(' ');
        if (sp <= 0) return;
        string cls = rest.substring(sp + 1).strip();
        foreach (string id in rest.substring(0, sp).split(",")) {
            var node = diagram.find_node(id.strip());
            if (node == null) continue;
            node.css_classes = node.css_classes == null ? cls : node.css_classes + " " + cls;
        }
    }

}

}
