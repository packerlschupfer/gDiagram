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

            // Skip style/layout update lines
            if (lower.has_prefix("updatelayoutconfig") ||
                lower.has_prefix("updateelementstyle") ||
                lower.has_prefix("updaterelstyle")) continue;

            // Boundary declarations
            if (lower.has_prefix("enterprise_boundary") ||
                lower.has_prefix("system_boundary") ||
                lower.has_prefix("container_boundary") ||
                lower.has_prefix("boundary(")) {
                parse_boundary(trimmed, i + 1);
                continue;
            }

            // Relationships
            if (lower.has_prefix("rel(") || lower.has_prefix("birel(") ||
                lower.has_prefix("rel_u(") || lower.has_prefix("rel_d(") ||
                lower.has_prefix("rel_l(") || lower.has_prefix("rel_r(") ||
                lower.has_prefix("rel_back(")) {
                parse_relationship(trimmed, i + 1);
                continue;
            }

            // Elements
            if (lower.has_prefix("person") || lower.has_prefix("system") ||
                lower.has_prefix("container") || lower.has_prefix("component") ||
                lower.has_prefix("deployment_node") || lower.has_prefix("node")) {
                parse_element(trimmed, i + 1);
                continue;
            }
        }
    }

    private void parse_boundary(string line, int lineno) {
        int popen = line.index_of("(");
        int pclose = line.last_index_of(")");
        if (popen < 0 || pclose < 0) return;

        string args_str = line.substring(popen + 1, pclose - popen - 1);
        string[] args = split_c4_args(args_str);
        if (args.length < 1) return;

        string bid = args[0].strip().replace("\"", "");
        string blabel = (args.length > 1) ? args[1].strip().replace("\"", "") : bid;
        string? btype = (args.length > 2) ? args[2].strip().replace("\"", "") : null;

        var boundary = new C4Boundary(bid, blabel, lineno);
        boundary.boundary_type = btype;
        if (boundary_stack.size > 0) {
            boundary.parent_boundary = boundary_stack.get(boundary_stack.size - 1);
        }
        diagram.boundaries.add(boundary);

        // Push if line ends with {
        if (line.contains("{")) {
            boundary_stack.add(bid);
        }
    }

    private void parse_element(string line, int lineno) {
        int popen = line.index_of("(");
        int pclose = line.last_index_of(")");
        if (popen < 0 || pclose < 0) return;

        string func_name = line.substring(0, popen).strip().down();
        // Remove trailing { if present
        if (func_name.has_suffix("{")) func_name = func_name.substring(0, func_name.length - 1).strip();

        string args_str = line.substring(popen + 1, pclose - popen - 1);
        string[] args = split_c4_args(args_str);
        if (args.length < 1) return;

        string eid = args[0].strip().replace("\"", "");
        string elabel = (args.length > 1) ? args[1].strip().replace("\"", "") : eid;
        string? tech = null;
        string? descr = null;
        // For Container/Component/Node: (id, label, tech, descr)
        // For Person/System: (id, label, descr)
        if (func_name.has_prefix("container") || func_name.has_prefix("component") ||
            func_name.has_prefix("deployment_node") || func_name.has_prefix("node")) {
            tech = (args.length > 2) ? args[2].strip().replace("\"", "") : null;
            descr = (args.length > 3) ? args[3].strip().replace("\"", "") : null;
        } else {
            descr = (args.length > 2) ? args[2].strip().replace("\"", "") : null;
        }

        C4ElementType etype;
        if (func_name.has_prefix("person")) etype = C4ElementType.PERSON;
        else if (func_name.has_prefix("deployment_node") || func_name.has_prefix("node")) etype = C4ElementType.DEPLOYMENT_NODE;
        else if (func_name.has_prefix("container")) etype = C4ElementType.CONTAINER;
        else if (func_name.has_prefix("component")) etype = C4ElementType.COMPONENT;
        else etype = C4ElementType.SYSTEM;

        var el = new C4Element(eid, elabel, etype, lineno);
        el.description = descr;
        el.technology = tech;
        el.is_external = func_name.contains("_ext");
        el.is_db = func_name.contains("db");
        el.is_queue = func_name.contains("queue");
        if (boundary_stack.size > 0) {
            el.parent_boundary = boundary_stack.get(boundary_stack.size - 1);
        }

        diagram.elements.add(el);

        // If followed by { push to boundary stack
        if (line.contains("{")) {
            boundary_stack.add(eid);
        }
    }

    private void parse_relationship(string line, int lineno) {
        int popen = line.index_of("(");
        int pclose = line.last_index_of(")");
        if (popen < 0 || pclose < 0) return;

        string func_name = line.substring(0, popen).strip().down();
        string args_str = line.substring(popen + 1, pclose - popen - 1);
        string[] args = split_c4_args(args_str);
        if (args.length < 3) return;

        string from_id = args[0].strip().replace("\"", "");
        string to_id = args[1].strip().replace("\"", "");
        string rel_label = args[2].strip().replace("\"", "");
        string? tech = (args.length > 3) ? args[3].strip().replace("\"", "") : null;

        var rel = new C4Relationship(from_id, to_id, rel_label, lineno);
        rel.technology = tech;
        rel.is_bidirectional = func_name.has_prefix("birel");
        if (func_name.has_suffix("_u")) rel.direction = "U";
        else if (func_name.has_suffix("_d")) rel.direction = "D";
        else if (func_name.has_suffix("_l")) rel.direction = "L";
        else if (func_name.has_suffix("_r")) rel.direction = "R";
        else if (func_name.has_suffix("_back")) rel.direction = "BACK";
        diagram.relationships.add(rel);
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
