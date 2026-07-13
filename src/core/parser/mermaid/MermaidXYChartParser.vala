namespace GDiagram {

public class MermaidXYChartParser : Object {

    public MermaidXYChartParser() {}

    public MermaidXYChart parse(string source) {
        var diagram = new MermaidXYChart();
        bool in_front_matter = false;
        bool seen_content = false;

        foreach (var raw in source.split("\n")) {
            string line = raw.strip();
            if (line == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) {
                if (line.has_prefix("title:") && diagram.title == null) {
                    diagram.title = unquote(line.substring(6).strip());
                }
                continue;
            }
            if (line.length == 0 || line.has_prefix("%%")) continue;
            seen_content = true;

            string low = line.down();

            // Keyword line: xychart-beta [horizontal|vertical]
            if (low.has_prefix("xychart")) {
                if (low.contains("horizontal")) diagram.horizontal = true;
                continue;
            }

            if (low.has_prefix("title ") || low.has_prefix("title\"")) {
                diagram.title = unquote(line.substring(5).strip());
                continue;
            }

            if (low.has_prefix("x-axis")) {
                parse_x_axis(diagram, line.substring(6).strip());
                continue;
            }

            if (low.has_prefix("y-axis")) {
                parse_y_axis(diagram, line.substring(6).strip());
                continue;
            }

            if (low.has_prefix("bar ") || low.has_prefix("bar[") || low.has_prefix("bar\"")) {
                var s = new XYSeries(XYSeriesType.BAR);
                parse_values(line.substring(3).strip(), s);
                diagram.add_series(s);
                continue;
            }

            if (low.has_prefix("line ") || low.has_prefix("line[") || low.has_prefix("line\"")) {
                var s = new XYSeries(XYSeriesType.LINE);
                parse_values(line.substring(4).strip(), s);
                diagram.add_series(s);
                continue;
            }
        }

        return diagram;
    }

    private static string unquote(string s) {
        string t = s.strip();
        if (t.length >= 2 && t.has_prefix("\"") && t.has_suffix("\"")) {
            return t.substring(1, t.length - 2);
        }
        return t;
    }

    // Reads an optional axis/plot title at the start of `rest`: a quoted string
    // or a bare word that is not the start of a list or a number range.
    private static string take_title(ref string rest) {
        rest = rest.strip();
        if (rest.has_prefix("\"")) {
            int close = rest.index_of("\"", 1);
            if (close > 0) {
                string t = rest.substring(1, close - 1);
                rest = rest.substring(close + 1).strip();
                return t;
            }
        }
        if (rest.length == 0 || rest.has_prefix("[")) return "";
        int end = 0;
        while (end < rest.length && rest[end] != ' ' && rest[end] != '[' && rest[end] != '\t') end++;
        string word = rest.substring(0, end);
        if (is_number(word)) return "";
        rest = rest.substring(end).strip();
        return word;
    }

    private static bool parse_range(string rest, out double min, out double max) {
        min = 0;
        max = 0;
        int arrow = rest.index_of("-->");
        if (arrow < 0) return false;
        string a = rest.substring(0, arrow).strip();
        string b = rest.substring(arrow + 3).strip();
        if (!is_number(a) || !is_number(b)) return false;
        min = double.parse(a);
        max = double.parse(b);
        // `y-axis "Y" 50 --> -50` is a range written backwards, and Mermaid still
        // plots every point in it (d3 takes a descending domain and flips the axis).
        // Kept as written it was a zero-or-negative-width range, which the renderer
        // widened to [50, 51] — the axis was drawn and every bar fell outside it.
        if (min > max) {
            double swap = min;
            min = max;
            max = swap;
        }
        return true;
    }

    // Splits "[a, "b, c", d]" into its items, honouring double quotes.
    private static Gee.ArrayList<string> list_items(string text) {
        var items = new Gee.ArrayList<string>();
        string inner = text.strip();
        if (inner.has_prefix("[")) {
            int close = inner.last_index_of("]");
            inner = close > 0 ? inner.substring(1, close - 1) : inner.substring(1);
        }
        var cur = new StringBuilder();
        bool quoted = false;
        for (int i = 0; i < inner.length; i++) {
            char c = inner[i];
            if (c == '"') { quoted = !quoted; continue; }
            if (c == ',' && !quoted) {
                items.add(cur.str.strip());
                cur.truncate(0);
                continue;
            }
            cur.append_c(c);
        }
        if (cur.str.strip().length > 0 || items.size > 0) items.add(cur.str.strip());
        return items;
    }

    private void parse_x_axis(MermaidXYChart diagram, string text) {
        // x-axis [jan, feb], x-axis "Month" [jan, feb], x-axis "T" 1 --> 10
        string rest = text;
        diagram.x_axis_label = take_title(ref rest);
        if (rest.has_prefix("[")) {
            foreach (var label in list_items(rest)) {
                if (label.length > 0) diagram.x_labels.add(label);
            }
            return;
        }
        double min, max;
        if (parse_range(rest, out min, out max)) {
            diagram.x_min = min;
            diagram.x_max = max;
            diagram.has_x_range = true;
        }
    }

    private void parse_y_axis(MermaidXYChart diagram, string text) {
        // y-axis "Revenue" 4000 --> 11000, y-axis Units, y-axis 0 --> 10
        string rest = text;
        diagram.y_axis_label = take_title(ref rest);
        double min, max;
        if (parse_range(rest, out min, out max)) {
            diagram.y_min = min;
            diagram.y_max = max;
            diagram.has_y_range = true;
        }
    }

    private void parse_values(string text, XYSeries series) {
        string rest = text;
        series.title = take_title(ref rest);
        foreach (var t in list_items(rest)) {
            if (is_number(t)) series.add_value(double.parse(t));
        }
    }

    private static bool is_number(string s) {
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
