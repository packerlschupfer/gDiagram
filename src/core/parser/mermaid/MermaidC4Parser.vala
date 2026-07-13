/* MermaidC4Parser.vala — Mermaid C4 diagram parser */
namespace GDiagram {

public class MermaidC4Parser : Object {
    private MermaidC4 diagram;
    private Gee.ArrayList<string> boundary_stack;

    public MermaidC4Parser() {}

    public MermaidC4 parse(string source) {
        this.diagram = new MermaidC4();
        this.boundary_stack = new Gee.ArrayList<string>();

        parse_c4(source);

        return diagram;
    }

    private void parse_c4(string source) {
        string[] lines = source.split("\n");
        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;

            // Closing brace — pop boundary stack
            if (trimmed == "}") {
                if (boundary_stack.size > 0) {
                    boundary_stack.remove_at(boundary_stack.size - 1);
                }
                continue;
            }

            // Opening keyword
            string lower = trimmed.down();
            if (lower.has_prefix("c4context") || lower.has_prefix("c4container") ||
                lower.has_prefix("c4component") || lower.has_prefix("c4dynamic") ||
                lower.has_prefix("c4deployment")) {
                // Set c4_type
                if (lower.has_prefix("c4context")) diagram.c4_type = "Context";
                else if (lower.has_prefix("c4container")) diagram.c4_type = "Container";
                else if (lower.has_prefix("c4component")) diagram.c4_type = "Component";
                else if (lower.has_prefix("c4dynamic")) diagram.c4_type = "Dynamic";
                else diagram.c4_type = "Deployment";
                continue;
            }

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            int popen = trimmed.index_of("(");
            if (popen <= 0) continue;
            string func = trimmed.substring(0, popen).strip().down();

            switch (func) {
                case "updatelayoutconfig":
                    parse_layout_config(trimmed);
                    continue;
                case "updateelementstyle":
                    parse_element_style(trimmed);
                    continue;
                case "updaterelstyle":
                    parse_rel_style(trimmed);
                    continue;
                case "enterprise_boundary":
                case "system_boundary":
                case "container_boundary":
                case "boundary":
                case "deployment_node":
                case "node":
                case "node_l":
                case "node_r":
                    parse_boundary(func, trimmed, i + 1);
                    continue;
                case "rel":
                case "birel":
                case "rel_u":
                case "rel_up":
                case "rel_d":
                case "rel_down":
                case "rel_l":
                case "rel_left":
                case "rel_r":
                case "rel_right":
                case "rel_back":
                case "relindex":
                    parse_relationship(func, trimmed, i + 1);
                    continue;
                default:
                    break;
            }

            // Elements
            if (func.has_prefix("person") || func.has_prefix("system") ||
                func.has_prefix("container") || func.has_prefix("component")) {
                parse_element(func, trimmed, i + 1);
                continue;
            }
        }
    }

    // Arguments inside the outer parentheses: positional values in order, and
    // `$name="value"` ones by name (without the "$")
    private string[] call_args(string line, Gee.HashMap<string, string> named) {
        int popen = line.index_of("(");
        int pclose = line.last_index_of(")");
        if (popen < 0 || pclose <= popen) return new string[0];
        string[] all = split_c4_args(line.substring(popen + 1, pclose - popen - 1));
        string[] positional = {};
        foreach (string a in all) {
            string t = a.strip();
            if (t.has_prefix("$")) {
                int eq = t.index_of("=");
                if (eq > 1) {
                    named.set(t.substring(1, eq - 1).strip(), t.substring(eq + 1).strip());
                }
                continue;
            }
            positional += t;
        }
        return positional;
    }

    private static string? arg(string[] args, int idx) {
        if (idx >= args.length) return null;
        string v = args[idx].strip();
        return v.length > 0 ? v : null;
    }

    private void parse_boundary(string func, string line, int lineno) {
        var named = new Gee.HashMap<string, string>();
        string[] args = call_args(line, named);
        if (args.length < 1 || args[0].length == 0) return;

        string bid = args[0];
        string blabel = arg(args, 1) ?? bid;
        string? btype = arg(args, 2) ?? named.get("type");
        bool deployment = func == "deployment_node" || func.has_prefix("node");
        // Mermaid's default types, shown as "[SYSTEM]", "[node]", ...
        if (btype == null) {
            switch (func) {
                case "enterprise_boundary": btype = "ENTERPRISE"; break;
                case "system_boundary":     btype = "SYSTEM"; break;
                case "container_boundary":  btype = "CONTAINER"; break;
                case "boundary":            btype = "system"; break;
                default:                    btype = "node"; break;
            }
        }

        var boundary = new C4Boundary(bid, blabel, lineno);
        boundary.boundary_type = btype;
        boundary.is_deployment_node = deployment;
        if (deployment) boundary.description = arg(args, 3) ?? named.get("descr");
        if (boundary_stack.size > 0) {
            boundary.parent_boundary = boundary_stack.get(boundary_stack.size - 1);
        }
        diagram.boundaries.add(boundary);

        // Push if line opens a scope
        if (line.contains("{")) {
            boundary_stack.add(bid);
        }
    }

    private void parse_element(string func_name, string line, int lineno) {
        var named = new Gee.HashMap<string, string>();
        string[] args = call_args(line, named);
        if (args.length < 1 || args[0].length == 0) return;

        string eid = args[0];
        string elabel = arg(args, 1) ?? eid;
        string? tech = null;
        string? descr = null;
        // For Container/Component: (id, label, techn, descr)
        // For Person/System: (id, label, descr)
        bool has_techn = func_name.has_prefix("container") || func_name.has_prefix("component");
        if (has_techn) {
            tech = arg(args, 2) ?? named.get("techn");
            descr = arg(args, 3) ?? named.get("descr");
        } else {
            descr = arg(args, 2) ?? named.get("descr");
        }

        C4ElementType etype;
        string base_type;
        if (func_name.has_prefix("person")) { etype = C4ElementType.PERSON; base_type = "person"; }
        else if (func_name.has_prefix("container")) { etype = C4ElementType.CONTAINER; base_type = "container"; }
        else if (func_name.has_prefix("component")) { etype = C4ElementType.COMPONENT; base_type = "component"; }
        else { etype = C4ElementType.SYSTEM; base_type = "system"; }

        var el = new C4Element(eid, elabel, etype, lineno);
        el.description = descr;
        el.technology = tech;
        el.is_external = func_name.contains("_ext");
        el.is_db = func_name.contains("db");
        el.is_queue = func_name.contains("queue");
        el.c4_shape_type = (el.is_external ? "external_" : "") + base_type +
            (el.is_db ? "_db" : (el.is_queue ? "_queue" : ""));
        if (boundary_stack.size > 0) {
            el.parent_boundary = boundary_stack.get(boundary_stack.size - 1);
        }

        diagram.elements.add(el);
    }

    private void parse_relationship(string func_name, string line, int lineno) {
        var named = new Gee.HashMap<string, string>();
        string[] args = call_args(line, named);
        // RelIndex(index, from, to, label, ...): Mermaid drops the index
        if (func_name == "relindex") {
            if (args.length < 1) return;
            args = args[1:args.length];
        }
        if (args.length < 3) return;

        string from_id = args[0];
        string to_id = args[1];
        string rel_label = args[2];

        var rel = new C4Relationship(from_id, to_id, rel_label, lineno);
        rel.technology = arg(args, 3) ?? named.get("techn");
        rel.description = arg(args, 4) ?? named.get("descr");
        rel.is_bidirectional = func_name.has_prefix("birel");
        if (func_name == "rel_u" || func_name == "rel_up") rel.direction = "U";
        else if (func_name == "rel_d" || func_name == "rel_down") rel.direction = "D";
        else if (func_name == "rel_l" || func_name == "rel_left") rel.direction = "L";
        else if (func_name == "rel_r" || func_name == "rel_right") rel.direction = "R";
        else if (func_name == "rel_back") rel.direction = "BACK";
        diagram.relationships.add(rel);
    }

    // UpdateElementStyle(name, $bgColor, $fontColor, $borderColor, ...)
    private void parse_element_style(string line) {
        var named = new Gee.HashMap<string, string>();
        string[] args = call_args(line, named);
        if (args.length < 1) return;
        string? bg = arg(args, 1) ?? named.get("bgColor");
        string? fg = arg(args, 2) ?? named.get("fontColor");
        string? border = arg(args, 3) ?? named.get("borderColor");
        foreach (var el in diagram.elements) {
            if (el.id != args[0]) continue;
            if (bg != null) el.bg_color = bg;
            if (fg != null) el.font_color = fg;
            if (border != null) el.border_color = border;
            return;
        }
        foreach (var b in diagram.boundaries) {
            if (b.id != args[0]) continue;
            if (bg != null) b.bg_color = bg;
            if (fg != null) b.font_color = fg;
            if (border != null) b.border_color = border;
            return;
        }
    }

    // UpdateRelStyle(from, to, $textColor, $lineColor, $offsetX, $offsetY)
    private void parse_rel_style(string line) {
        var named = new Gee.HashMap<string, string>();
        string[] args = call_args(line, named);
        if (args.length < 2) return;
        string? text = arg(args, 2) ?? named.get("textColor");
        string? stroke = arg(args, 3) ?? named.get("lineColor");
        string? off_x = arg(args, 4) ?? named.get("offsetX");
        string? off_y = arg(args, 5) ?? named.get("offsetY");
        foreach (var rel in diagram.relationships) {
            if (rel.from_id != args[0] || rel.to_id != args[1]) continue;
            if (text != null) rel.text_color = text;
            if (stroke != null) rel.line_color = stroke;
            // Mermaid coerces the offsets with parseInt: "-40px" and "-40" both work
            if (off_x != null) rel.offset_x = (double) int.parse(off_x);
            if (off_y != null) rel.offset_y = (double) int.parse(off_y);
            return;
        }
    }

    // UpdateLayoutConfig($c4ShapeInRow, $c4BoundaryInRow)
    private void parse_layout_config(string line) {
        var named = new Gee.HashMap<string, string>();
        string[] args = call_args(line, named);
        string? shapes = arg(args, 0) ?? named.get("c4ShapeInRow");
        string? bounds = arg(args, 1) ?? named.get("c4BoundaryInRow");
        if (shapes != null && int.parse(shapes) > 0) diagram.shape_in_row = int.parse(shapes);
        if (bounds != null && int.parse(bounds) > 0) diagram.boundary_in_row = int.parse(bounds);
    }

    // Split comma-separated args respecting quoted strings
    private string[] split_c4_args(string s) {
        var parts = new Gee.ArrayList<string>();
        var current = new StringBuilder();
        bool in_quotes = false;
        char quote_char = '"';
        int paren_depth = 0;

        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (in_quotes) {
                if (c == quote_char) in_quotes = false;
                else current.append_c(c);
            } else if (c == '"' || c == '\'') {
                in_quotes = true;
                quote_char = c;
            } else if (c == '(') {
                paren_depth++;
                current.append_c(c);
            } else if (c == ')') {
                paren_depth--;
                current.append_c(c);
            } else if (c == ',' && paren_depth == 0) {
                parts.add(current.str.strip());
                current.erase();
            } else {
                current.append_c(c);
            }
        }
        if (current.str.strip().length > 0) parts.add(current.str.strip());
        return parts.to_array();
    }
}

}
