/* MermaidRadarParser.vala — Mermaid radar-beta diagram parser */
namespace GDiagram {

public class MermaidRadarParser : Object {
    private MermaidRadar diagram;

    public MermaidRadarParser() {}

    public MermaidRadar parse(string source) {
        this.diagram = new MermaidRadar();

        parse_radar(source);

        return diagram;
    }

    private void parse_radar(string source) {
        string[] lines = source.split("\n");
        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;

            string lower = trimmed.down();
            if (lower.has_prefix("radar-beta") || lower == "radar") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            if (lower.has_prefix("max ")) {
                diagram.max_value = double.parse(trimmed.substring(4).strip());
                continue;
            }
            if (lower.has_prefix("min ")) {
                diagram.min_value = double.parse(trimmed.substring(4).strip());
                continue;
            }

            // axis id["Label"] or axis id1, id2, id3
            if (lower.has_prefix("axis ")) {
                parse_axis(trimmed.substring(5).strip(), i + 1);
                continue;
            }

            // curve id["Label"]{...} or curve id{...}
            if (lower.has_prefix("curve ")) {
                parse_curve(trimmed.substring(6).strip(), i + 1);
                continue;
            }
        }
    }

    private void parse_axis(string spec, int lineno) {
        // Multiple axes on one line: "A, B, C"
        if (spec.contains(",") && !spec.contains("[")) {
            foreach (var part in spec.split(",")) {
                string s = part.strip();
                if (s.length > 0) {
                    diagram.axes.add(new RadarAxis(s, s, lineno));
                }
            }
            return;
        }

        // Single axis: id["Label"] or just id
        string id;
        string label;
        int bracket = spec.index_of("[");
        if (bracket >= 0) {
            id = spec.substring(0, bracket).strip();
            int bracket_close = spec.last_index_of("]");
            label = (bracket_close > bracket) ? spec.substring(bracket + 1, bracket_close - bracket - 1).replace("\"", "").strip() : id;
        } else {
            id = spec.strip();
            label = id;
        }
        diagram.axes.add(new RadarAxis(id, label, lineno));
    }

    private void parse_curve(string spec, int lineno) {
        // id["Label"]{v1,v2,...} or id{v1,v2,...} or id{key:v, key:v}
        string id;
        string label;
        string values_str = "";

        int brace_open = spec.index_of("{");
        int brace_close = spec.last_index_of("}");
        if (brace_open < 0) return;

        string before_brace = spec.substring(0, brace_open).strip();
        if (brace_close > brace_open) {
            values_str = spec.substring(brace_open + 1, brace_close - brace_open - 1).strip();
        }

        // Parse id["label"] from before_brace
        int bracket = before_brace.index_of("[");
        if (bracket >= 0) {
            id = before_brace.substring(0, bracket).strip();
            int bracket_close = before_brace.last_index_of("]");
            label = (bracket_close > bracket) ? before_brace.substring(bracket + 1, bracket_close - bracket - 1).replace("\"", "").strip() : id;
        } else {
            id = before_brace.strip();
            label = id;
        }

        var curve = new RadarCurve(id, label, lineno);

        // Parse values: either "1,2,3" (positional) or "axisA: 1, axisB: 2" (key-value)
        if (values_str.contains(":")) {
            // Key-value
            foreach (var kv in values_str.split(",")) {
                string[] parts = kv.strip().split(":");
                if (parts.length >= 2) {
                    string key = parts[0].strip();
                    double val = double.parse(parts[1].strip());
                    curve.key_values.set(key, val);
                }
            }
        } else {
            // Positional
            foreach (var v in values_str.split(",")) {
                string vs = v.strip();
                if (vs.length > 0) {
                    curve.values.add(double.parse(vs));
                }
            }
        }

        diagram.curves.add(curve);
    }
}

}
