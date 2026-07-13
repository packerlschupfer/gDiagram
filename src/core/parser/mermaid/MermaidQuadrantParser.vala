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

            // classDef name color: #ff3300, radius: 10, stroke-color: #000, stroke-width: 2px
            if (low.has_prefix("classdef ")) {
                string spec = line.substring(9).strip();
                int sp = spec.index_of_char(' ');
                if (sp > 0) {
                    diagram.class_defs.set(spec.substring(0, sp), parse_styles(spec.substring(sp + 1)));
                }
                continue;
            }

            // Point: "Label: [x, y]", "Label:::class: [x, y]", "Label: [x, y] radius: 10, color: #f00"
            int colon = line.index_of(": [");
            if (colon < 0) colon = line.index_of(":[");
            if (colon >= 0) {
                string label = line.substring(0, colon).strip();
                string? css_class = null;
                int cls = label.index_of(":::");
                if (cls >= 0) {
                    css_class = label.substring(cls + 3).strip();
                    label = label.substring(0, cls).strip();
                }
                if (label.length >= 2 && label.has_prefix("\"") && label.has_suffix("\"")) {
                    label = label.substring(1, label.length - 2);
                }
                int open = line.index_of("[", colon);
                string rest = line.substring(open + 1);
                int close = rest.index_of("]");
                if (close >= 0) {
                    string coords = rest.substring(0, close);
                    string[] parts = coords.split(",");
                    if (parts.length == 2) {
                        double x = double.parse(parts[0].strip());
                        double y = double.parse(parts[1].strip());
                        var point = new QuadrantPoint(label, x, y, line_num);
                        point.css_class = css_class;
                        apply_styles(point, parse_styles(rest.substring(close + 1)));
                        diagram.add_point(point);
                    }
                }
                continue;
            }
        }

        return diagram;
    }

    // "radius: 10, color: #ff0000" -> {radius: 10, color: #ff0000}
    internal static Gee.HashMap<string, string> parse_styles(string text) {
        var styles = new Gee.HashMap<string, string>();
        foreach (var part in text.split(",")) {
            int c = part.index_of_char(':');
            if (c <= 0) continue;
            string key = part.substring(0, c).strip().down();
            string val = part.substring(c + 1).strip();
            if (val.has_suffix(";")) val = val.substring(0, val.length - 1).strip();
            if (key.length > 0 && val.length > 0) styles.set(key, val);
        }
        return styles;
    }

    internal static void apply_styles(QuadrantPoint point, Gee.HashMap<string, string> styles) {
        if (styles.has_key("color")) point.color = styles.get("color");
        if (styles.has_key("radius")) point.radius = double.parse(styles.get("radius").replace("px", ""));
        if (styles.has_key("stroke-color")) point.stroke_color = styles.get("stroke-color");
        if (styles.has_key("stroke-width")) point.stroke_width = double.parse(styles.get("stroke-width").replace("px", ""));
    }
}

}
