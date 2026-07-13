/* BoardDiagramParser.vala — parses column-based board layout */
namespace GDiagram {

public class BoardDiagramParser : Object {

    /*
     * PlantUML's syntax: a line without `+` starts a column, `+` adds a card
     * to it and `++`, `+++` ... add sub-cards under the card one level up.
     *
     * The older gDiagram form, where every line is prefixed (`+ column`,
     * `++ card`), is still read: when no line of the board is unprefixed,
     * one `+` is taken off every level.
     */
    public BoardDiagram parse(string source) {
        var diagram = new BoardDiagram();

        string[] lines = source.split("\n");
        // Main-file line numbers: included text reports its !include line
        int[] line_nos = Preprocessor.source_line_numbers(lines);

        var texts = new Gee.ArrayList<string>();
        var depths = new Gee.ArrayList<int>();
        var line_list = new Gee.ArrayList<int>();
        bool inside = false;
        bool any_unprefixed = false;

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i].strip();

            if (line.has_prefix("@startboard")) {
                inside = true;
                continue;
            }
            if (line.has_prefix("@endboard")) {
                break;
            }
            if (!inside) continue;
            if (line.length == 0 || line.has_prefix("'")) continue;

            int depth = 0;
            while (depth < line.length && line[depth] == '+') {
                depth++;
            }
            string text = line.substring(depth).strip();
            if (text.length == 0) continue;
            if (depth == 0) any_unprefixed = true;
            texts.add(text);
            depths.add(depth);
            line_list.add(line_nos[i]);
        }

        int shift = any_unprefixed ? 0 : 1;
        BoardColumn? column = null;
        // stack[k] = the latest card at card level k + 1
        var stack = new Gee.ArrayList<BoardCard>();

        for (int i = 0; i < texts.size; i++) {
            int level = depths[i] - shift;   // 0 = column, 1 = card, 2 = sub-card ...
            if (level <= 0) {
                column = new BoardColumn(texts[i], line_list[i]);
                diagram.columns.add(column);
                stack.clear();
                continue;
            }
            if (column == null) {
                // A card before any column gets an untitled column
                column = new BoardColumn("", line_list[i]);
                diagram.columns.add(column);
            }
            var card = new BoardCard(texts[i], line_list[i]);
            // A level deeper than the stack allows hangs under the deepest card
            if (level - 1 > stack.size) level = stack.size + 1;
            while (stack.size > level - 1) {
                stack.remove_at(stack.size - 1);
            }
            if (level == 1) {
                column.cards.add(card);
            } else {
                stack[stack.size - 1].children.add(card);
            }
            stack.add(card);
        }

        return diagram;
    }
}

}
