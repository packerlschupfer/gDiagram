/* TreeDiagramParser.vala — parses indentation-based tree with +/- markers */
namespace GDiagram {

public class TreeDiagramParser : Object {

    public TreeDiagram parse(string source) {
        var diagram = new TreeDiagram();

        string[] lines = source.split("\n");
        // Stack: depth -> most recent node at that depth
        var stack = new Gee.ArrayList<TreeNode>();

        int line_num = 0;
        bool inside = false;

        foreach (string raw_line in lines) {
            line_num++;
            string line = raw_line.strip();

            // Handle @starttree / @endtree boundaries
            if (line.has_prefix("@starttree")) {
                inside = true;
                continue;
            }
            if (line.has_prefix("@endtree")) {
                break;
            }
            if (!inside) continue;

            // Skip blank lines and comments
            if (line.length == 0 || line.has_prefix("'")) continue;

            // Count leading + or - markers for depth
            int depth = 0;
            bool is_minus = false;
            string trimmed = raw_line;
            // Strip leading whitespace first
            while (trimmed.length > 0 && (trimmed[0] == ' ' || trimmed[0] == '\t')) {
                trimmed = trimmed.substring(1);
            }

            if (trimmed.length == 0) continue;

            if (trimmed[0] == '+' || trimmed[0] == '-') {
                is_minus = (trimmed[0] == '-');
                char marker = trimmed[0];
                while (depth < trimmed.length && trimmed[depth] == marker) {
                    depth++;
                }
                string text = trimmed.substring(depth).strip();
                if (text.length == 0) continue;

                var node = new TreeNode(text, depth, line_num);

                if (depth == 1 || stack.size == 0) {
                    // Root level
                    if (diagram.root == null) {
                        diagram.root = node;
                    }
                    stack.clear();
                    stack.add(node);
                } else {
                    // Find parent: walk back the stack to find depth - 1
                    while (stack.size > 0 && stack[stack.size - 1].depth >= depth) {
                        stack.remove_at(stack.size - 1);
                    }
                    if (stack.size > 0) {
                        stack[stack.size - 1].add_child(node);
                    } else if (diagram.root != null) {
                        diagram.root.add_child(node);
                    }
                    stack.add(node);
                }
            }
            // Lines not starting with +/- are ignored (title etc. could be added)
        }

        return diagram;
    }
}

}
