namespace GDiagram {

public class MermaidBlockParser : Object {

    public MermaidBlockParser() {}

    public MermaidBlock parse(string source) {
        var diagram = new MermaidBlock();
        string? current_group = null;
        int line_num = 0;

        foreach (var raw in source.split("\n")) {
            line_num++;
            string line = raw.strip();
            if (line.length == 0 || line.has_prefix("%%")) continue;

            string low = line.down();

            if (low.has_prefix("block-beta") || low == "block") continue;
            if (low.has_prefix("title ")) { diagram.title = line.substring(6).strip(); continue; }

            // columns N
            if (low.has_prefix("columns ")) {
                int cols = int.parse(line.substring(8).strip());
                if (cols > 0) diagram.columns = cols;
                continue;
            }

            // end of group
            if (low == "end") { current_group = null; continue; }

            // group: "block:id["label"]" or "block:id"
            if (low.has_prefix("block:")) {
                string rest = line.substring(6);
                string group_id;
                string group_label = parse_block_token(rest, out group_id);
                var grp = new BlockNode(group_id, group_label, line_num);
                grp.is_group = true;
                diagram.add_node(grp);
                current_group = group_id;
                continue;
            }

            // Edge: "A --> B" or "A -- label --> B"  (contains "-->")
            if (line.contains("-->")) {
                parse_edge(line, diagram, line_num);
                continue;
            }

            // blockArrow — skip (visual arrow block, not structural)
            if (low.has_prefix("blockarrow")) continue;

            // Block row: space-separated tokens like: A["Block A"] B C:2
            // Only parse as blocks if line doesn't look like an edge
            parse_block_row(line, diagram, current_group, line_num);
        }

        return diagram;
    }

    private void parse_edge(string line, MermaidBlock diagram, int line_num) {
        // Formats: "A --> B", "A -- "label" --> B", "A -->|label| B"
        int arrow = line.index_of("-->");
        if (arrow < 0) return;

        string left = line.substring(0, arrow).strip();
        string right = line.substring(arrow + 3).strip();
        string? label = null;

        // "A -- label -->"
        int dash2 = left.index_of("--");
        if (dash2 >= 0) {
            string src = left.substring(0, dash2).strip();
            label = left.substring(dash2 + 2).strip().replace("\"", "");
            left = src;
        }
        // "A -->|label| B"
        if (right.has_prefix("|")) {
            int end_pipe = right.index_of("|", 1);
            if (end_pipe > 0) {
                label = right.substring(1, end_pipe - 1);
                right = right.substring(end_pipe + 1).strip();
            }
        }

        if (left.length > 0 && right.length > 0) {
            diagram.add_edge(new BlockEdge(left, right, label, line_num));
        }
    }

    private void parse_block_row(string line, MermaidBlock diagram, string? group_id, int line_num) {
        // Tokenize: handles A["label"] and plain A and A:2
        int i = 0;
        while (i < line.length) {
            // Skip spaces
            while (i < line.length && line[i] == ' ') i++;
            if (i >= line.length) break;

            // Read until next space (unless inside quotes/brackets)
            var token = new StringBuilder();
            bool in_bracket = false;
            bool in_quote = false;
            while (i < line.length) {
                char c = line[i];
                if (c == '[') in_bracket = true;
                if (c == ']') in_bracket = false;
                if (c == '"') in_quote = !in_quote;
                if (c == ' ' && !in_bracket && !in_quote) break;
                token.append_c(c);
                i++;
            }

            string tok = token.str.strip();
            if (tok.length == 0) continue;

            // Parse span suffix ":N"
            int col_span = 1;
            int colon = tok.last_index_of(":");
            if (colon > 0) {
                string after = tok.substring(colon + 1);
                if (after.length > 0 && after[0].isdigit()) {
                    col_span = int.parse(after);
                    tok = tok.substring(0, colon);
                }
            }

            string block_id;
            string block_label = parse_block_token(tok, out block_id);
            if (block_id.length == 0) continue;

            // Skip if this looks like an existing group id
            var node = new BlockNode(block_id, block_label, line_num);
            node.group_id = group_id;
            node.col_span = col_span;
            diagram.add_node(node);
        }
    }

    // Parse "id[\"label\"]" or "id" → returns label, sets id
    private string parse_block_token(string tok, out string id) {
        int open = tok.index_of("[");
        int close = tok.last_index_of("]");
        if (open >= 0 && close > open) {
            id = tok.substring(0, open).strip();
            if (id.length == 0) id = tok.substring(open + 1, close - open - 1).strip().replace("\"", "");
            return tok.substring(open + 1, close - open - 1).strip().replace("\"", "");
        }
        id = tok.strip();
        return tok.strip();
    }
}

}
