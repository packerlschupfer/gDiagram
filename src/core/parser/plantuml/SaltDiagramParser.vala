/* SaltDiagramParser.vala — line-based parser for PlantUML @startsalt */
namespace GDiagram {

public class SaltDiagramParser : Object {
    private SaltDiagram diagram;

    public SaltDiagramParser() {}

    public SaltDiagram parse(string source) {
        this.diagram = new SaltDiagram();
        parse_salt(source);
        return diagram;
    }

    private void parse_salt(string source) {
        string[] lines = source.split("\n");

        // Stack of panels for nested { } blocks
        var panel_stack = new Gee.ArrayList<SaltPanel>();
        panel_stack.add(diagram.root);

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower == "@startsalt" || lower == "@endsalt") continue;
            if (lower.has_prefix("skinparam") || lower.has_prefix("<style>") || lower == "</style>") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            // Process characters looking for { and }
            // Opening brace — possibly with type modifier {T, {#, {+, {!, {-, etc.
            if (trimmed.has_prefix("{")) {
                string type_str = "";
                string rest = trimmed.substring(1).strip();
                if (rest.length > 0 && !rest.has_prefix("|") && !rest.has_prefix("[")) {
                    // Check for type modifier like T, #, +, etc.
                    if (rest[0] == 'T' || rest[0] == '#' || rest[0] == '+' ||
                        rest[0] == '!' || rest[0] == '-' || rest[0] == '^') {
                        type_str = rest.substring(0, 1);
                        rest = rest.substring(1).strip();
                    }
                }
                var panel = new SaltPanel(type_str, i + 1);
                // Add as a cell in the current panel's current row
                var current_panel = panel_stack.get(panel_stack.size - 1);
                var elem = new SaltElement(SaltElementType.PANEL, "", i + 1);
                elem.nested_panel = panel;
                if (current_panel.rows.size == 0) {
                    current_panel.rows.add(new SaltRow(i + 1));
                }
                var current_row = current_panel.rows.get(current_panel.rows.size - 1);
                current_row.cells.add(elem);
                panel_stack.add(panel);

                // If there's remaining content on this line, parse it
                if (rest.length > 0 && rest != "}") {
                    parse_row(rest, panel, i + 1);
                }
                continue;
            }

            if (trimmed == "}") {
                if (panel_stack.size > 1) {
                    var closed_panel = panel_stack.get(panel_stack.size - 1);
                    panel_stack.remove_at(panel_stack.size - 1);
                    // Merge closed panel rows into parent as a nested structure
                    // Actually, the closed panel already has its rows; the parent
                    // references it through the PANEL element
                }
                continue;
            }

            // Regular content line — parse as a row in the current panel
            var current_panel = panel_stack.get(panel_stack.size - 1);
            parse_row(trimmed, current_panel, i + 1);
        }
    }

    private void parse_row(string line, SaltPanel panel, int lineno) {
        var row = new SaltRow(lineno);

        // Check for separators
        if (line == "--" || line == "---" || line == ".." || line == "==" || line == "~~") {
            row.cells.add(new SaltElement(SaltElementType.SEPARATOR, line, lineno));
            panel.rows.add(row);
            return;
        }

        // Split by | for columns
        string[] cells = line.split("|");
        foreach (var cell_text in cells) {
            string cell = cell_text.strip();
            if (cell.length == 0) {
                row.cells.add(new SaltElement(SaltElementType.LABEL, "", lineno));
                continue;
            }
            row.cells.add(parse_widget(cell, lineno));
        }

        panel.rows.add(row);
    }

    private SaltElement parse_widget(string text, int lineno) {
        string t = text.strip();

        // Button: [text]
        if (t.has_prefix("[") && t.has_suffix("]") && !t.has_prefix("[X]") && !t.has_prefix("[ ]")) {
            string label = t.substring(1, t.length - 2).strip();
            return new SaltElement(SaltElementType.BUTTON, label, lineno);
        }

        // Text field: "text"
        if (t.has_prefix("\"") && t.has_suffix("\"")) {
            string label = t.substring(1, t.length - 2);
            return new SaltElement(SaltElementType.TEXT_FIELD, label, lineno);
        }

        // Dropdown: ^text^ or ^text1^text2^
        if (t.has_prefix("^") && t.has_suffix("^")) {
            string label = t.substring(1, t.length - 2);
            return new SaltElement(SaltElementType.DROPDOWN, label, lineno);
        }

        // Radio button: () text or (X) text
        if (t.has_prefix("()") || t.has_prefix("(X)")) {
            bool selected = t.has_prefix("(X)");
            string label = selected ? t.substring(3).strip() : t.substring(2).strip();
            var elem = new SaltElement(SaltElementType.RADIO, label, lineno);
            elem.checked = selected;
            return elem;
        }

        // Checkbox: [X] text or [ ] text
        if (t.has_prefix("[X]") || t.has_prefix("[ ]")) {
            bool chk = t.has_prefix("[X]");
            string label = t.substring(3).strip();
            var elem = new SaltElement(SaltElementType.CHECKBOX, label, lineno);
            elem.checked = chk;
            return elem;
        }

        // Separator
        if (t == "--" || t == "---" || t == ".." || t == "==" || t == "~~") {
            return new SaltElement(SaltElementType.SEPARATOR, t, lineno);
        }

        // Default: label
        return new SaltElement(SaltElementType.LABEL, t, lineno);
    }
}

}
