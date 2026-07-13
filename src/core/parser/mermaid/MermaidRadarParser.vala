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
        bool max_given = false;
        bool in_front_matter = false;
        bool seen_content = false;
        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) {
                if (trimmed.has_prefix("title:") && diagram.title == null) {
                    diagram.title = strip_quotes(trimmed.substring(6).strip());
                }
                continue;
            }
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;
            seen_content = true;

            string lower = trimmed.down();
            if (lower.has_prefix("radar-beta") || lower == "radar") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = strip_quotes(trimmed.substring(6).strip());
                continue;
            }

            if (lower.has_prefix("max ")) {
                diagram.max_value = double.parse(trimmed.substring(4).strip());
                max_given = true;
                continue;
            }
            if (lower.has_prefix("min ")) {
                diagram.min_value = double.parse(trimmed.substring(4).strip());
                continue;
            }
            if (lower.has_prefix("ticks ")) {
                int t = int.parse(trimmed.substring(6).strip());
                if (t > 0) diagram.ticks = t;
                continue;
            }
            if (lower.has_prefix("graticule ")) {
                diagram.graticule_polygon = trimmed.substring(10).strip().down() == "polygon";
                continue;
            }
            if (lower.has_prefix("showlegend")) {
                diagram.show_legend = trimmed.substring(10).strip().down() != "false";
                continue;
            }

            // axis id["Label"], id2, id3["Label 3"]
            if (lower.has_prefix("axis ")) {
                foreach (var item in split_items(trimmed.substring(5))) {
                    parse_axis(item, i + 1);
                }
                continue;
            }

            // curve id["Label"]{...}, id2{...}
            if (lower.has_prefix("curve ")) {
                foreach (var item in split_items(trimmed.substring(6))) {
                    parse_curve(item, i + 1);
                }
                continue;
            }
        }

        // Without `max` Mermaid scales to the largest value.
        if (!max_given) {
            bool any = false;
            double mx = 0;
            foreach (var c in diagram.curves) {
                foreach (var v in c.values) {
                    if (v == null) continue;
                    mx = any ? double.max(mx, v) : v;
                    any = true;
                }
                foreach (var v in c.key_values.values) {
                    if (v == null) continue;
                    mx = any ? double.max(mx, v) : v;
                    any = true;
                }
            }
            if (any && mx > diagram.min_value) diagram.max_value = mx;
        }
    }

    private static string strip_quotes(string s) {
        if (s.length >= 2 && s.has_prefix("\"") && s.has_suffix("\"")) return s.substring(1, s.length - 2);
        return s;
    }

    // Splits on commas outside quotes, [..] and {..}.
    private static Gee.ArrayList<string> split_items(string spec) {
        var items = new Gee.ArrayList<string>();
        var cur = new StringBuilder();
        int depth = 0;
        bool quoted = false;
        for (int i = 0; i < spec.length; i++) {
            char c = spec[i];
            if (c == '"') quoted = !quoted;
            else if (!quoted && (c == '[' || c == '{')) depth++;
            else if (!quoted && (c == ']' || c == '}')) depth--;
            if (c == ',' && depth == 0 && !quoted) {
                if (cur.str.strip().length > 0) items.add(cur.str.strip());
                cur.truncate(0);
                continue;
            }
            cur.append_c(c);
        }
        if (cur.str.strip().length > 0) items.add(cur.str.strip());
        return items;
    }

    // id["Label"] or id
    private static void id_and_label(string spec, out string id, out string label) {
        int bracket = spec.index_of("[");
        if (bracket >= 0) {
            id = spec.substring(0, bracket).strip();
            int bracket_close = spec.last_index_of("]");
            label = (bracket_close > bracket)
                ? strip_quotes(spec.substring(bracket + 1, bracket_close - bracket - 1).strip())
                : id;
        } else {
            id = spec.strip();
            label = id;
        }
    }

    private void parse_axis(string spec, int lineno) {
        string id, label;
        id_and_label(spec, out id, out label);
        if (id.length > 0) diagram.axes.add(new RadarAxis(id, label, lineno));
    }

    private void parse_curve(string spec, int lineno) {
        // id["Label"]{v1,v2,...} or id{v1,v2,...} or id{key:v, key:v}
        int brace_open = spec.index_of("{");
        int brace_close = spec.last_index_of("}");
        if (brace_open < 0) return;

        string values_str = "";
        if (brace_close > brace_open) {
            values_str = spec.substring(brace_open + 1, brace_close - brace_open - 1).strip();
        }

        string id, label;
        id_and_label(spec.substring(0, brace_open).strip(), out id, out label);

        var curve = new RadarCurve(id, label, lineno);

        if (values_str.contains(":")) {
            foreach (var kv in values_str.split(",")) {
                string[] parts = kv.strip().split(":");
                if (parts.length >= 2) {
                    curve.key_values.set(parts[0].strip(), double.parse(parts[1].strip()));
                }
            }
        } else {
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
