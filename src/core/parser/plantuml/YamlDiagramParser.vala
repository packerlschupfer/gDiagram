/* YamlDiagramParser.vala — parser for PlantUML @startyaml */
namespace GDiagram {

public class YamlDiagramParser : Object {
    private YamlDiagram diagram;

    public YamlDiagramParser() {}

    public YamlDiagram parse(string source) {
        this.diagram = new YamlDiagram();

        parse_yaml_diagram(source);

        return diagram;
    }

    private void parse_yaml_diagram(string source) {
        string[] lines = source.split("\n");
        var yaml_lines = new Gee.ArrayList<string>();

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            string lower = trimmed.down();

            if (lower == "@startyaml" || lower == "@endyaml") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }
            if (trimmed.has_prefix("#highlight ")) {
                string path = trimmed.substring(11).strip()
                    .replace("\"", "").replace(" / ", ".").replace("/", ".");
                diagram.highlights.add(path.strip());
                continue;
            }
            if (trimmed == "---" || trimmed == "...") continue;
            // Skip comment lines (# but not ##highlight — already handled above)
            if (trimmed.has_prefix("#")) continue;
            if (trimmed.has_prefix("skinparam") || trimmed.has_prefix("<style>") || trimmed == "</style>") continue;

            yaml_lines.add(lines[i]);
        }

        if (yaml_lines.size == 0) return;

        // Create a root MAPPING node to hold all top-level entries
        var root = new YamlNode(YamlNodeType.MAPPING, 0);
        diagram.root = root;

        // Stack of (node, indent_level) pairs for tracking nesting
        var stack = new Gee.ArrayList<YamlNode>();
        var indent_stack = new Gee.ArrayList<int>();
        stack.add(root);
        indent_stack.add(-1);

        for (int i = 0; i < yaml_lines.size; i++) {
            string raw = yaml_lines.get(i);
            if (raw.strip().length == 0) continue;

            int indent = count_indent(raw);
            string trimmed = raw.strip();

            // Pop stack entries whose indent is >= current indent
            while (indent_stack.size > 1 &&
                   indent_stack.get(indent_stack.size - 1) >= indent) {
                stack.remove_at(stack.size - 1);
                indent_stack.remove_at(indent_stack.size - 1);
            }

            var parent = stack.get(stack.size - 1);

            if (trimmed.has_prefix("- ")) {
                // Sequence item
                string item_value = trimmed.substring(2).strip();
                if (parent.node_type != YamlNodeType.SEQUENCE) {
                    parent.node_type = YamlNodeType.SEQUENCE;
                }
                var item = new YamlNode(YamlNodeType.SCALAR, indent);
                item.value = item_value;
                parent.children.add(item);
            } else if (trimmed.contains(": ")) {
                // Key: value pair
                int colon = trimmed.index_of(": ");
                string key = trimmed.substring(0, colon).strip();
                string val = trimmed.substring(colon + 2).strip();
                if (val.length > 0) {
                    // Inline scalar
                    var node = new YamlNode(YamlNodeType.SCALAR, indent);
                    node.key = key;
                    node.value = val;
                    parent.children.add(node);
                } else {
                    // Mapping container
                    var node = new YamlNode(YamlNodeType.MAPPING, indent);
                    node.key = key;
                    parent.children.add(node);
                    stack.add(node);
                    indent_stack.add(indent);
                }
            } else if (trimmed.has_suffix(":")) {
                // Mapping container without trailing space: key:
                string key = trimmed.substring(0, trimmed.length - 1).strip();
                var node = new YamlNode(YamlNodeType.MAPPING, indent);
                node.key = key;
                parent.children.add(node);
                stack.add(node);
                indent_stack.add(indent);
            } else if (trimmed.length > 0 && !trimmed.has_prefix("#")) {
                // Plain scalar (bare value without key)
                var node = new YamlNode(YamlNodeType.SCALAR, indent);
                node.value = trimmed;
                parent.children.add(node);
            }
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

}
