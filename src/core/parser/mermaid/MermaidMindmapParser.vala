/* MermaidMindmapParser.vala — Mermaid mindmap parser for gDiagram */
namespace GDiagram {

public class MermaidMindmapParser : Object {
    private Gee.ArrayList<string> lines;
    private MermaidMindmap diagram;

    public MermaidMindmapParser() {}

    public MermaidMindmap parse(string source) {
        this.diagram = new MermaidMindmap();
        this.lines = new Gee.ArrayList<string>();

        foreach (var line in source.split("\n")) {
            lines.add(line);
        }

        parse_mindmap();

        return diagram;
    }

    private void parse_mindmap() {
        // Stack of nodes to track parent chain
        var stack = new Gee.ArrayList<MindmapNode>();

        for (int i = 0; i < lines.size; i++) {
            string raw = lines.get(i);
            string trimmed = raw.strip();

            // Skip blank lines
            if (trimmed.length == 0) continue;
            // Skip the "mindmap" keyword line
            if (trimmed.down() == "mindmap") continue;
            // Skip comment lines
            if (trimmed.has_prefix("%%")) continue;

            int depth = count_indent(raw);
            string shape;
            string text = parse_node_text(trimmed, out shape);
            text = text.replace("<br/>", "\n").replace("<br>", "\n");

            var node = new MindmapNode(text, shape, depth, i + 1);

            if (diagram.root == null) {
                diagram.root = node;
                stack.clear();
                stack.add(node);
                continue;
            }

            // Pop stack until we find parent at shallower depth
            while (stack.size > 1 && stack.get(stack.size - 1).depth >= depth) {
                stack.remove_at(stack.size - 1);
            }

            var parent = stack.get(stack.size - 1);
            parent.add_child(node);
            stack.add(node);
        }
    }

    // Count leading spaces / 2 (mermaid uses 2-space indent per level)
    private int count_indent(string line) {
        int count = 0;
        foreach (char c in line.to_utf8()) {
            if (c == ' ') count++;
            else if (c == '\t') count += 2;
            else break;
        }
        return count / 2;
    }

    // Parse node label and shape from text like "(text)", "((text))", "[text]", etc.
    private string parse_node_text(string text, out string shape) {
        string t = text.strip();

        // Remove icon annotations ::icon(...)
        int icon_pos = t.index_of("::");
        if (icon_pos >= 0) t = t.substring(0, icon_pos).strip();

        // Find first shape character to detect optional id prefix
        int bracket_pos = t.index_of("[");
        int paren_pos = t.index_of("(");
        int brace_pos = t.index_of("{");
        int gt_pos = t.index_of(">");
        // Cloud shape starts with ))
        if (t.has_prefix("))") && t.has_suffix("((")) {
            shape = "cloud";
            return t.substring(2, t.length - 4).strip();
        }

        // Find first shape delimiter position
        int first = -1;
        if (bracket_pos >= 0) first = bracket_pos;
        if (paren_pos >= 0 && (first < 0 || paren_pos < first)) first = paren_pos;
        if (brace_pos >= 0 && (first < 0 || brace_pos < first)) first = brace_pos;
        if (gt_pos >= 0 && (first < 0 || gt_pos < first)) first = gt_pos;

        // Strip optional id prefix (e.g. "myId[text]" -> "[text]")
        if (first > 0) t = t.substring(first);

        // Detect shape and strip delimiters
        if (t.has_prefix("((") && t.has_suffix("))")) {
            shape = "circle";
            return t.substring(2, t.length - 4).strip();
        }
        if (t.has_prefix("(") && t.has_suffix(")")) {
            shape = "rounded";
            return t.substring(1, t.length - 2).strip();
        }
        if (t.has_prefix("[[") && t.has_suffix("]]")) {
            shape = "rectangle";
            return t.substring(2, t.length - 4).strip();
        }
        if (t.has_prefix("[") && t.has_suffix("]")) {
            shape = "rectangle";
            return t.substring(1, t.length - 2).strip();
        }
        if (t.has_prefix("{{") && t.has_suffix("}}")) {
            shape = "hexagon";
            return t.substring(2, t.length - 4).strip();
        }
        if (t.has_prefix("{") && t.has_suffix("}")) {
            shape = "hexagon";
            return t.substring(1, t.length - 2).strip();
        }
        if (t.has_prefix(">") && t.has_suffix("]")) {
            shape = "bang";
            return t.substring(1, t.length - 2).strip();
        }

        shape = "default";
        return t.strip();
    }
}

}
