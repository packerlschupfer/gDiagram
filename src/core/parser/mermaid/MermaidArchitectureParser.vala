/* MermaidArchitectureParser.vala — Mermaid architecture-beta parser */
namespace GDiagram {

public class MermaidArchitectureParser : Object {
    private MermaidArchitecture diagram;

    public MermaidArchitectureParser() {}

    public MermaidArchitecture parse(string source) {
        this.diagram = new MermaidArchitecture();

        parse_architecture(source);

        return diagram;
    }

    private void parse_architecture(string source) {
        string[] lines = source.split("\n");
        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;

            string lower = trimmed.down();
            if (lower.has_prefix("architecture-beta") || lower == "architecture") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            if (lower.has_prefix("group ")) {
                parse_group(trimmed, i + 1);
                continue;
            }
            if (lower.has_prefix("service ")) {
                parse_service(trimmed, false, i + 1);
                continue;
            }
            if (lower.has_prefix("junction ")) {
                parse_junction(trimmed, i + 1);
                continue;
            }
            // Edge: contains -- or -->
            if (trimmed.contains("--")) {
                parse_edge(trimmed, i + 1);
                continue;
            }
        }
    }

    // Parse: group id(icon)[label] OR group id(icon)[label] in parent_id
    private void parse_group(string line, int lineno) {
        // Remove "group " prefix
        string rest = line.substring(6).strip();

        string? parent_id = null;
        // Check for " in <id>" suffix
        int in_pos = rest.last_index_of(" in ");
        if (in_pos > 0) {
            parent_id = rest.substring(in_pos + 4).strip();
            rest = rest.substring(0, in_pos).strip();
        }

        string id;
        string icon = "server";
        string label;

        // Parse id(icon)[label] or id[label]
        int paren_open = rest.index_of("(");
        int bracket_open = rest.index_of("[");

        if (paren_open >= 0 && bracket_open > paren_open) {
            id = rest.substring(0, paren_open).strip();
            int paren_close = rest.index_of(")", paren_open);
            if (paren_close > paren_open) icon = rest.substring(paren_open + 1, paren_close - paren_open - 1).strip();
            int bracket_close = rest.last_index_of("]");
            label = (bracket_close > bracket_open) ? rest.substring(bracket_open + 1, bracket_close - bracket_open - 1).strip() : id;
        } else if (bracket_open >= 0) {
            id = rest.substring(0, bracket_open).strip();
            int bracket_close = rest.last_index_of("]");
            label = (bracket_close > bracket_open) ? rest.substring(bracket_open + 1, bracket_close - bracket_open - 1).strip() : id;
        } else {
            id = rest.strip();
            label = id;
        }

        var g = new ArchGroup(id, icon, label, lineno);
        g.parent_id = parent_id;
        diagram.groups.add(g);
    }

    // Parse: service id(icon)[label] OR service id(icon)[label] in group_id
    private void parse_service(string line, bool is_junction, int lineno) {
        string prefix = is_junction ? "junction " : "service ";
        string rest = line.substring(prefix.length).strip();

        string? group_id = null;
        int in_pos = rest.last_index_of(" in ");
        if (in_pos > 0) {
            group_id = rest.substring(in_pos + 4).strip();
            rest = rest.substring(0, in_pos).strip();
        }

        string id;
        string icon = "server";
        string label;

        int paren_open = rest.index_of("(");
        int bracket_open = rest.index_of("[");

        if (paren_open >= 0 && (bracket_open < 0 || bracket_open > paren_open)) {
            id = rest.substring(0, paren_open).strip();
            int paren_close = rest.index_of(")", paren_open);
            if (paren_close > paren_open) icon = rest.substring(paren_open + 1, paren_close - paren_open - 1).strip();
            if (bracket_open >= 0) {
                int bracket_close = rest.last_index_of("]");
                label = (bracket_close > bracket_open) ? rest.substring(bracket_open + 1, bracket_close - bracket_open - 1).strip() : id;
            } else {
                label = id;
            }
        } else if (bracket_open >= 0) {
            id = rest.substring(0, bracket_open).strip();
            int bracket_close = rest.last_index_of("]");
            label = (bracket_close > bracket_open) ? rest.substring(bracket_open + 1, bracket_close - bracket_open - 1).strip() : id;
        } else {
            id = rest.strip();
            label = id;
        }

        var svc = new ArchService(id, icon, label, lineno);
        svc.group_id = group_id;
        svc.is_junction = is_junction;
        diagram.services.add(svc);
    }

    private void parse_junction(string line, int lineno) {
        parse_service(line, true, lineno);
    }

    // Parse edge: from_id:SIDE -->|-- SIDE:to_id
    private void parse_edge(string line, int lineno) {
        bool directed;
        string connector;
        int conn_pos = -1;

        if (line.contains("-->")) {
            directed = true;
            conn_pos = line.index_of("-->");
            connector = "-->";
        } else if (line.contains("<--")) {
            // Reverse direction
            directed = true;
            conn_pos = line.index_of("<--");
            connector = "<--";
        } else {
            directed = false;
            conn_pos = line.index_of("--");
            connector = "--";
        }

        if (conn_pos < 0) return;

        string left_part = line.substring(0, conn_pos).strip();
        string right_part = line.substring(conn_pos + connector.length).strip();

        // Parse id:SIDE
        string from_id;
        string from_side = "";
        if (left_part.contains(":")) {
            string[] lparts = left_part.split(":");
            from_id = lparts[0].strip();
            from_side = (lparts.length > 1) ? lparts[1].strip().up() : "";
        } else {
            from_id = left_part;
        }

        string to_id;
        string to_side = "";
        if (right_part.contains(":")) {
            string[] rparts = right_part.split(":");
            to_side = rparts[0].strip().up();
            to_id = (rparts.length > 1) ? rparts[1].strip() : right_part;
        } else {
            to_id = right_part;
        }

        // Handle reverse direction
        if (connector == "<--") {
            diagram.edges.add(new ArchEdge(to_id, to_side, from_id, from_side, directed, lineno));
        } else {
            diagram.edges.add(new ArchEdge(from_id, from_side, to_id, to_side, directed, lineno));
        }
    }
}

}
