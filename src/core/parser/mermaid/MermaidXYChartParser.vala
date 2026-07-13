namespace GDiagram {

public class MermaidXYChartParser : Object {

    public MermaidXYChartParser() {}

    public MermaidXYChart parse(string source) {
        var diagram = new MermaidXYChart();

        foreach (var raw in source.split("\n")) {
            string line = raw.strip();
            if (line.length == 0 || line.has_prefix("%%")) continue;

            string low = line.down();

            // Skip the keyword line (xychart-beta or xychart)
            if (low.has_prefix("xychart")) continue;

            if (low.has_prefix("title ") || low.has_prefix("title\"")) {
                string rest = line.substring(5).strip().replace("\"", "");
                diagram.title = rest;
                continue;
            }

            if (low.has_prefix("x-axis ")) {
                string rest = line.substring(7).strip();
                parse_x_axis(diagram, rest);
                continue;
            }

            if (low.has_prefix("y-axis ")) {
                string rest = line.substring(7).strip();
                parse_y_axis(diagram, rest);
                continue;
            }

            if (low.has_prefix("bar ") || low == "bar") {
                string rest = line.substring(4).strip();
                var s = new XYSeries(XYSeriesType.BAR);
                parse_values(rest, s);
                diagram.add_series(s);
                continue;
            }

            if (low.has_prefix("line ") || low == "line") {
                string rest = line.substring(5).strip();
                var s = new XYSeries(XYSeriesType.LINE);
                parse_values(rest, s);
                diagram.add_series(s);
                continue;
            }
        }

        return diagram;
    }

    private void parse_x_axis(MermaidXYChart diagram, string rest) {
        // x-axis [jan, feb, mar] or x-axis "Label" min --> max
        if (rest.has_prefix("[")) {
            int close = rest.index_of("]");
            string inner = (close >= 0) ? rest.substring(1, close - 1) : rest.substring(1);
            foreach (var tok in inner.split(",")) {
                string label = tok.strip().replace("\"", "");
                if (label.length > 0) {
                    diagram.x_labels.add(label);
                }
            }
        } else {
            // numeric or labeled form: "Label" 0 --> 100
            string r = rest.replace("\"", "");
            int arrow = r.index_of("-->");
            if (arrow >= 0) {
                diagram.x_axis_label = r.substring(0, arrow).strip();
            } else {
                diagram.x_axis_label = r.strip();
            }
        }
    }

    private void parse_y_axis(MermaidXYChart diagram, string rest) {
        // y-axis "Revenue" 4000 --> 11000
        string r = rest.replace("\"", "");
        int arrow = r.index_of("-->");
        if (arrow >= 0) {
            // Left side might be "Revenue (in $) 4000" — take last token as min if numeric
            string left = r.substring(0, arrow).strip();
            string right = r.substring(arrow + 3).strip();
            string[] parts = left.split(" ");
            if (parts.length >= 2 && is_number(parts[parts.length - 1])) {
                diagram.y_min = double.parse(parts[parts.length - 1]);
                // Rebuild label from all parts except the trailing number
                var label_parts = new string[parts.length - 1];
                for (int i = 0; i < parts.length - 1; i++) {
                    label_parts[i] = parts[i];
                }
                diagram.y_axis_label = string.joinv(" ", label_parts).strip();
            } else {
                diagram.y_axis_label = left.strip();
            }
            string[] right_parts = right.split(" ");
            diagram.y_max = double.parse(right_parts[0]);
            diagram.has_y_range = true;
        } else {
            diagram.y_axis_label = r.strip();
        }
    }

    private void parse_values(string text, XYSeries series) {
        string inner = text;
        if (inner.has_prefix("[")) {
            int close = inner.index_of("]");
            inner = (close >= 0) ? inner.substring(1, close - 1) : inner.substring(1);
        }
        foreach (var tok in inner.split(",")) {
            string t = tok.strip();
            if (t.length > 0 && is_number(t)) {
                series.add_value(double.parse(t));
            }
        }
    }

    private bool is_number(string s) {
        if (s.length == 0) return false;
        bool has_digit = false;
        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (c.isdigit()) { has_digit = true; continue; }
            if ((c == '-' || c == '+') && i == 0) continue;
            if (c == '.') continue;
            return false;
        }
        return has_digit;
    }
}

}
