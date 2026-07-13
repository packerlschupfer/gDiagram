/* MermaidMindmapParser.vala — Mermaid mindmap parser for gDiagram
 *
 * Follows Mermaid 11.17's mindmap.jison: a node is an optional id (any text
 * up to "(", "[", ")", "{" or "}") followed by a shape — [rect], (rounded),
 * ((circle)), )cloud(, ))bang((, {{hexagon}} — whose text may be a "string"
 * or a "`markdown string`". Anything else (">Better recall]") is the plain
 * text of a default node, as Mermaid shows it. The level is the indentation
 * in characters; a node's parent is the last node with a smaller level.
 */
namespace GDiagram {

public class MermaidMindmapParser : Object {
    private MermaidMindmap diagram;

    public MermaidMindmapParser() {}

    public MermaidMindmap parse(string source) {
        this.diagram = new MermaidMindmap();
        string[] lines = source.replace("\r\n", "\n").split("\n");

        var nodes = new Gee.ArrayList<MindmapNode>();
        int base_level = 0;
        bool seen_keyword = false;
        int i = 0;

        // YAML front matter
        while (i < lines.length && lines[i].strip().length == 0) i++;
        if (i < lines.length && lines[i].strip() == "---") {
            i++;
            while (i < lines.length && lines[i].strip() != "---") {
                string fl = lines[i].strip();
                if (fl.has_prefix("title:")) diagram.title = fl.substring(6).strip();
                i++;
            }
            i++;
        }

        for (; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%{")) {
                while (!lines[i].contains("}%%") && i + 1 < lines.length) i++;
                continue;
            }
            if (trimmed.has_prefix("%%")) continue;

            if (!seen_keyword) {
                if (trimmed.down() == "mindmap") {
                    seen_keyword = true;
                    continue;
                }
                if (trimmed.down().has_prefix("mindmap")) {
                    // "mindmap" followed by more text on the same line
                    seen_keyword = true;
                    trimmed = trimmed.substring(7).strip();
                    if (trimmed.length == 0) continue;
                    raw = trimmed;
                } else {
                    // Tolerate a missing keyword, as before
                    seen_keyword = true;
                }
            }

            // Decorations apply to the last node
            if (trimmed.has_prefix("::icon(")) {
                if (nodes.size > 0) {
                    int close = trimmed.last_index_of(")");
                    nodes[nodes.size - 1].icon = close > 7 ? trimmed.substring(7, close - 7).strip() : trimmed.substring(7);
                }
                continue;
            }
            if (trimmed.has_prefix(":::")) {
                if (nodes.size > 0) nodes[nodes.size - 1].css_class = trimmed.substring(3).strip();
                continue;
            }

            int indent = 0;
            while (indent < raw.length && (raw[indent] == ' ' || raw[indent] == '\t')) indent++;

            string shape;
            string id;
            bool markdown;
            string text = parse_node_text(trimmed, out shape, out id, out markdown);
            text = text.replace("<br/>", "\n").replace("<br>", "\n").replace("<br />", "\n");

            MindmapNode node;
            if (nodes.size == 0) {
                base_level = indent;
                node = new MindmapNode(text, shape, 0, i + 1);
                node.level = 0;
                node.node_id = id;
                node.markdown = markdown;
                diagram.root = node;
                nodes.add(node);
                continue;
            }

            int level = indent - base_level;
            MindmapNode? parent = null;
            for (int k = nodes.size - 1; k >= 0; k--) {
                if (nodes[k].level < level) { parent = nodes[k]; break; }
            }
            if (parent == null) {
                diagram.errors.add(new ParseError(
                    "There can be only one root. No parent could be found for (\"%s\")".printf(text),
                    i + 1, indent + 1));
                continue;
            }
            node = new MindmapNode(text, shape, parent.depth + 1, i + 1);
            node.level = level;
            node.node_id = id;
            node.markdown = markdown;
            parent.add_child(node);
            nodes.add(node);
        }

        if (diagram.root != null) assign_sections(diagram.root, -1);
        return diagram;
    }

    // Root children get sections 0..10 in order; descendants inherit
    private void assign_sections(MindmapNode node, int section) {
        node.section = node.depth == 0 ? -1 : section;
        for (int k = 0; k < node.children.size; k++) {
            assign_sections(node.children[k], node.depth == 0 ? k % 11 : section);
        }
    }

    private static bool is_id_char(char c) {
        return c != '(' && c != '[' && c != ')' && c != '{' && c != '}';
    }

    // Parse "id[text]", "((text))", "text" … into label, shape and id.
    // Text that doesn't form a valid node is kept literally.
    private string parse_node_text(string t, out string shape, out string id, out bool markdown) {
        shape = "default";
        markdown = false;
        id = t;

        int p = 0;
        while (p < t.length && is_id_char(t[p])) p++;
        string node_id = t.substring(0, p).strip();
        if (p >= t.length) {
            // NODE_ID only: a default node showing its text
            return t;
        }

        string rest = t.substring(p);
        string start;
        if (rest.has_prefix("-)")) start = "-)";
        else if (rest.has_prefix("(-")) start = "(-";
        else if (rest.has_prefix("))")) start = "))";
        else if (rest.has_prefix(")")) start = ")";
        else if (rest.has_prefix("((")) start = "((";
        else if (rest.has_prefix("{{")) start = "{{";
        else if (rest.has_prefix("(")) start = "(";
        else if (rest.has_prefix("[")) start = "[";
        else return t;   // "{text}" and other stray delimiters: literal text

        string inner = rest.substring(start.length);
        string descr;
        int q = 0;
        if (inner.has_prefix("\"`")) {
            int close = inner.index_of("`\"", 2);
            if (close < 0) return t;
            descr = inner.substring(2, close - 2);
            q = close + 2;
            markdown = true;
        } else if (inner.has_prefix("\"")) {
            int close = inner.index_of("\"", 1);
            if (close < 0) return t;
            descr = inner.substring(1, close - 1);
            q = close + 1;
        } else {
            while (q < inner.length && inner[q] != ')' && inner[q] != ']' && inner[q] != '(' &&
                   inner[q] != '}') q++;
            descr = inner.substring(0, q);
        }

        string after = inner.substring(q);
        string end;
        if (after.has_prefix("))")) end = "))";
        else if (after.has_prefix(")")) end = ")";
        else if (after.has_prefix("]")) end = "]";
        else if (after.has_prefix("}}")) end = "}}";
        else if (after.has_prefix("(-")) end = "(-";
        else if (after.has_prefix("-)")) end = "-)";
        else if (after.has_prefix("((")) end = "((";
        else if (after.has_prefix("(")) end = "(";
        else return t;   // unterminated: literal text

        switch (start) {
            case "[":  shape = "rectangle"; break;
            case "(":  shape = end == ")" ? "rounded" : "cloud"; break;
            case "((": shape = "circle"; break;
            case ")":  shape = "cloud"; break;
            case "))": shape = "bang"; break;
            case "{{": shape = "hexagon"; break;
            default:   shape = "default"; break;
        }
        id = node_id.length > 0 ? node_id : descr;
        return markdown ? descr : descr.strip();
    }
}

}
