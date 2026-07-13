/* MermaidTreemapParser.vala — Mermaid treemap-beta parser */
namespace GDiagram {

public class MermaidTreemapParser : Object {
    private MermaidTreemap diagram;

    public MermaidTreemapParser() {}

    public MermaidTreemap parse(string source) {
        this.diagram = new MermaidTreemap();

        parse_treemap(source);

        return diagram;
    }

    private void parse_treemap(string source) {
        string[] lines = source.split("\n");

        // Build flat list of (depth, label, value, is_leaf) entries
        var entries = new Gee.ArrayList<TreemapEntryData>();

        bool in_front_matter = false;
        bool seen_content = false;
        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();
            if (trimmed == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) {
                if (trimmed.has_prefix("title:") && diagram.title == null) {
                    diagram.title = unquote(trimmed.substring(6).strip());
                }
                continue;
            }
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;
            seen_content = true;

            string lower = trimmed.down();
            if (lower.has_prefix("treemap-beta") || lower == "treemap") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = unquote(trimmed.substring(6).strip());
                continue;
            }
            if (lower.has_prefix("classdef ")) {
                parse_class_def(trimmed.substring(9).strip());
                continue;
            }

            int depth = count_indent(raw);
            string body = trimmed;

            // Trailing `:::className`
            string? css_class = null;
            int cls = body.last_index_of(":::");
            if (cls >= 0) {
                string name = body.substring(cls + 3).strip();
                if (name.length > 0 && !name.contains("\"") && !name.contains("'")) {
                    css_class = name;
                    body = body.substring(0, cls).strip();
                }
            }

            // "Label": value, 'Label': value, or a section "Label"
            string label;
            string after;
            char q = body.length > 0 ? body[0] : '\0';
            if ((q == '"' || q == '\'') && body.index_of_char(q, 1) > 0) {
                int close = body.index_of_char(q, 1);
                label = body.substring(1, close - 1);
                after = body.substring(close + 1).strip();
            } else {
                int colon = body.last_index_of(":");
                label = colon >= 0 ? body.substring(0, colon).strip() : body;
                after = colon >= 0 ? body.substring(colon).strip() : "";
            }

            double value = 0.0;
            bool is_leaf = false;
            if (after.has_prefix(":") || after.has_prefix(",")) {
                string num = after.substring(1).strip();
                if (num.length > 0) {
                    is_leaf = true;
                    value = double.parse(num);
                }
            }

            var entry = new TreemapEntryData(depth, label, value, is_leaf, i + 1);
            entry.css_class = css_class;
            entries.add(entry);
        }

        // Build tree from flat list using stack
        var stack = new Gee.ArrayList<TreemapNode>();

        foreach (var entry in entries) {
            var node = new TreemapNode(entry.label, entry.value, entry.is_leaf, entry.depth_val, entry.line);
            node.css_class = entry.css_class;

            // Pop stack until we find parent at shallower depth
            while (stack.size > 0 && stack.get(stack.size - 1).depth >= entry.depth_val) {
                stack.remove_at(stack.size - 1);
            }

            if (stack.size == 0) {
                diagram.roots.add(node);
            } else {
                stack.get(stack.size - 1).add_child(node);
            }

            stack.add(node);
        }
    }

    private static string unquote(string s) {
        if (s.length >= 2 && ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                              (s.has_prefix("'") && s.has_suffix("'")))) {
            return s.substring(1, s.length - 2);
        }
        return s;
    }

    // classDef name fill:#f96,stroke:#333,stroke-width:2px,color:#000;
    private void parse_class_def(string spec) {
        string body = spec.strip();
        if (body.has_suffix(";")) body = body.substring(0, body.length - 1);
        int sp = body.index_of_char(' ');
        if (sp <= 0) return;
        string name = body.substring(0, sp);
        var props = new Gee.HashMap<string, string>();
        foreach (var part in body.substring(sp + 1).split(",")) {
            int c = part.index_of_char(':');
            if (c <= 0) continue;
            props.set(part.substring(0, c).strip().down(), part.substring(c + 1).strip());
        }
        foreach (var name_part in name.split(",")) {
            diagram.class_defs.set(name_part.strip(), props);
        }
    }

    private int count_indent(string line) {
        int count = 0;
        foreach (char c in line.to_utf8()) {
            if (c == ' ') count++;
            else if (c == '\t') count += 2;
            else break;
        }
        return count;
    }
}

// Helper class for building the tree (class instead of struct for Vala compatibility)
private class TreemapEntryData : Object {
    public int depth_val;
    public string label;
    public double value;
    public bool is_leaf;
    public int line;
    public string? css_class = null;

    public TreemapEntryData(int depth, string label, double value, bool is_leaf, int line) {
        this.depth_val = depth;
        this.label = label;
        this.value = value;
        this.is_leaf = is_leaf;
        this.line = line;
    }
}

}
