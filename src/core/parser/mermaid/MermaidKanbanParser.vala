namespace GDiagram {

public class MermaidKanbanParser : Object {

    public MermaidKanbanParser() {}

    public MermaidKanban parse(string source) {
        var diagram = new MermaidKanban();
        KanbanColumn? current_col = null;
        int line_num = 0;
        bool in_front_matter = false;
        // Column header indent is detected from the first content line that
        // appears after the `kanban` keyword. Some files write column headers
        // at indent 0 (DiagramTemplates flat style) while the official
        // mermaid.js.org syntax indents columns under `kanban` (indent 2).
        // Both are valid; -1 means "not yet detected".
        int column_indent = -1;

        foreach (var raw in source.split("\n")) {
            line_num++;
            string line_stripped = raw.strip();

            // Skip empty lines and comments
            if (line_stripped.length == 0 || line_stripped.has_prefix("%%")) continue;

            // Handle YAML front matter block (---)
            if (line_stripped == "---") {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) continue;

            // Skip the "kanban" keyword line itself
            if (line_stripped.down().has_prefix("kanban")) continue;

            // Handle title directive
            if (line_stripped.down().has_prefix("title ")) {
                diagram.title = line_stripped.substring(6).strip();
                continue;
            }

            int indent = count_indent(raw);
            string text = strip_metadata(line_stripped);  // remove @{...} annotations

            // Lazily learn the column-header indent from the first non-kanban
            // content line we see.
            if (column_indent < 0) column_indent = indent;

            if (indent == column_indent) {
                // Column header
                string col_id;
                string col_label = parse_id_label(text, out col_id);
                if (col_label.length == 0) continue;
                current_col = new KanbanColumn(col_label, col_id, line_num);
                diagram.add_column(current_col);
            } else if (indent > column_indent && current_col != null) {
                // Card under current column
                string card_id;
                string card_label = parse_id_label(text, out card_id);
                if (card_label.length == 0) continue;
                var card = new KanbanCard(card_label, card_id, line_num);
                // Parse metadata from the raw (stripped) line
                string meta = extract_metadata(line_stripped);
                if (meta.length > 0) {
                    parse_card_metadata(card, meta);
                }
                current_col.add_card(card);
            }
        }

        return diagram;
    }

    private int count_indent(string line) {
        int n = 0;
        foreach (char c in line.to_utf8()) {
            if (c == ' ') n++;
            else if (c == '\t') n += 2;
            else break;
        }
        return n;
    }

    // Extract text inside @{...}
    private string extract_metadata(string line) {
        int start = line.index_of("@{");
        if (start < 0) return "";
        int end = line.index_of("}", start);
        if (end < 0) return "";
        return line.substring(start + 2, end - start - 2);
    }

    // Remove @{...} from text
    private string strip_metadata(string text) {
        int start = text.index_of("@{");
        if (start < 0) return text;
        return text.substring(0, start).strip();
    }

    // Parse "id[label]" -> label, id; or "[label]" -> label, ""; or "plain text" -> text, ""
    private string parse_id_label(string text, out string id) {
        int open = text.index_of("[");
        int close = text.index_of("]");
        if (open >= 0 && close > open) {
            id = text.substring(0, open).strip();
            return text.substring(open + 1, close - open - 1).strip();
        }
        id = "";
        return text.strip();
    }

    // Parse key: 'value' pairs from metadata string
    private void parse_card_metadata(KanbanCard card, string meta) {
        foreach (var pair in meta.split(",")) {
            string[] kv = pair.split(":");
            if (kv.length < 2) continue;
            string key = kv[0].strip().down();
            // Rejoin remaining parts in case value contained ':'
            string val = string.joinv(":", kv[1:kv.length]).strip().replace("'", "").replace("\"", "");
            switch (key) {
                case "assigned": card.assigned = val; break;
                case "ticket":   card.ticket = val; break;
                case "priority": card.priority = val; break;
            }
        }
    }
}

}
