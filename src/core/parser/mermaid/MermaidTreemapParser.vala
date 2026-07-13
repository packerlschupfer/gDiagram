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

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;

            string lower = trimmed.down();
            if (lower.has_prefix("treemap-beta") || lower == "treemap") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            int depth = count_indent(raw);
            // Parse: "Label": value  OR  "Label"
            string label;
            double value = 0.0;
            bool is_leaf = false;

            int colon_pos = -1;
            // Find colon after closing quote
            int last_quote = trimmed.last_index_of("\"");
            if (last_quote >= 0 && last_quote + 1 < trimmed.length) {
                string after_quote = trimmed.substring(last_quote + 1).strip();
                if (after_quote.has_prefix(":")) {
                    colon_pos = last_quote;
                    is_leaf = true;
                    value = double.parse(after_quote.substring(1).strip());
                }
            }

            // Extract label (remove quotes)
            if (is_leaf) {
                label = trimmed.substring(0, colon_pos + 1).strip();
            } else {
                label = trimmed.strip();
            }
            // Remove surrounding quotes
            if (label.has_prefix("\"") && label.has_suffix("\"") && label.length >= 2) {
                label = label.substring(1, label.length - 2);
            }

            var entry = new TreemapEntryData(depth, label, value, is_leaf, i + 1);
            entries.add(entry);
        }

        // Build tree from flat list using stack
        var stack = new Gee.ArrayList<TreemapNode>();

        foreach (var entry in entries) {
            var node = new TreemapNode(entry.label, entry.value, entry.is_leaf, entry.depth_val, entry.line);

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

    public TreemapEntryData(int depth, string label, double value, bool is_leaf, int line) {
        this.depth_val = depth;
        this.label = label;
        this.value = value;
        this.is_leaf = is_leaf;
        this.line = line;
    }
}

}
