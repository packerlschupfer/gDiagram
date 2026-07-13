/* BoardDiagramParser.vala — parses column-based board layout */
namespace GDiagram {

public class BoardDiagramParser : Object {

    public BoardDiagram parse(string source) {
        var diagram = new BoardDiagram();

        string[] lines = source.split("\n");
        int line_num = 0;
        bool inside = false;
        BoardColumn? current_column = null;

        foreach (string raw_line in lines) {
            line_num++;
            string line = raw_line.strip();

            if (line.has_prefix("@startboard")) {
                inside = true;
                continue;
            }
            if (line.has_prefix("@endboard")) {
                break;
            }
            if (!inside) continue;

            if (line.length == 0 || line.has_prefix("'")) continue;

            // Count leading + markers
            string trimmed = raw_line;
            while (trimmed.length > 0 && (trimmed[0] == ' ' || trimmed[0] == '\t')) {
                trimmed = trimmed.substring(1);
            }
            if (trimmed.length == 0) continue;

            if (trimmed[0] == '+') {
                int depth = 0;
                while (depth < trimmed.length && trimmed[depth] == '+') {
                    depth++;
                }
                string text = trimmed.substring(depth).strip();
                if (text.length == 0) continue;

                if (depth == 1) {
                    // Column header
                    current_column = new BoardColumn(text, line_num);
                    diagram.columns.add(current_column);
                } else if (depth >= 2 && current_column != null) {
                    // Card within current column
                    current_column.cards.add(new BoardCard(text, line_num));
                }
            }
        }

        return diagram;
    }
}

}
