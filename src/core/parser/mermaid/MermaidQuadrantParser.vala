namespace GDiagram {

public class MermaidQuadrantParser : Object {

    public MermaidQuadrantParser() {}

    public MermaidQuadrant parse(string source) {
        var diagram = new MermaidQuadrant();
        int line_num = 0;

        foreach (var raw in source.split("\n")) {
            line_num++;
            string line = raw.strip();
            if (line.length == 0 || line.has_prefix("%%")) continue;

            string low = line.down();

            if (low.has_prefix("quadrantchart")) continue;

            if (low.has_prefix("title ")) {
                diagram.title = line.substring(6).strip();
                continue;
            }

            // x-axis Low --> High  or  x-axis Low Reach --> High Reach
            if (low.has_prefix("x-axis ")) {
                string rest = line.substring(7).strip();
                int arrow = rest.index_of("-->");
                if (arrow >= 0) {
                    diagram.x_axis_left = rest.substring(0, arrow).strip();
                    diagram.x_axis_right = rest.substring(arrow + 3).strip();
                } else {
                    diagram.x_axis_left = rest;
                }
                continue;
            }

            if (low.has_prefix("y-axis ")) {
                string rest = line.substring(7).strip();
                int arrow = rest.index_of("-->");
                if (arrow >= 0) {
                    diagram.y_axis_bottom = rest.substring(0, arrow).strip();
                    diagram.y_axis_top = rest.substring(arrow + 3).strip();
                } else {
                    diagram.y_axis_bottom = rest;
                }
                continue;
            }

            if (low.has_prefix("quadrant-1 ")) { diagram.quadrant_1 = line.substring(11).strip(); continue; }
            if (low.has_prefix("quadrant-2 ")) { diagram.quadrant_2 = line.substring(11).strip(); continue; }
            if (low.has_prefix("quadrant-3 ")) { diagram.quadrant_3 = line.substring(11).strip(); continue; }
            if (low.has_prefix("quadrant-4 ")) { diagram.quadrant_4 = line.substring(11).strip(); continue; }

            // Point: "Label: [x, y]" or "Label: [x, y] radius: 10 ..."
            int colon = line.index_of(": [");
            if (colon >= 0) {
                string label = line.substring(0, colon).strip();
                string rest = line.substring(colon + 3);
                int close = rest.index_of("]");
                if (close >= 0) {
                    string coords = rest.substring(0, close);
                    string[] parts = coords.split(",");
                    if (parts.length == 2) {
                        double x = double.parse(parts[0].strip());
                        double y = double.parse(parts[1].strip());
                        diagram.add_point(new QuadrantPoint(label, x, y, line_num));
                    }
                }
                continue;
            }
        }

        return diagram;
    }
}

}
