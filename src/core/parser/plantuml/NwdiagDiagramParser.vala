/* NwdiagDiagramParser.vala — line-based parser for PlantUML @startnwdiag */
namespace GDiagram {

public class NwdiagDiagramParser : Object {
    private NwdiagDiagram diagram;

    public NwdiagDiagramParser() {}

    public NwdiagDiagram parse(string source) {
        this.diagram = new NwdiagDiagram();

        parse_nwdiag(source);

        return diagram;
    }

    private void parse_nwdiag(string source) {
        string[] lines = source.split("\n");

        // Context stack: "root", "nwdiag", "network:NAME", "group:NAME"
        var context_stack = new Gee.ArrayList<string>();
        NwNetwork? current_network = null;
        NwGroup? current_group = null;

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower == "@startnwdiag" || lower == "@endnwdiag") continue;
            if (lower.has_prefix("skinparam") || lower.has_prefix("<style>") || lower == "</style>") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            // Closing brace — pop context
            if (trimmed == "}") {
                if (context_stack.size > 0) {
                    string ctx = context_stack.get(context_stack.size - 1);
                    context_stack.remove_at(context_stack.size - 1);
                    if (ctx.has_prefix("network:")) current_network = null;
                    if (ctx.has_prefix("group:")) current_group = null;
                }
                continue;
            }

            // nwdiag { opening
            if (lower.has_prefix("nwdiag") && trimmed.contains("{")) {
                context_stack.add("nwdiag");
                continue;
            }

            // Network block: network NAME {
            if (lower.has_prefix("network ")) {
                string net_rest = trimmed.substring(8).strip();
                // Remove trailing {
                if (net_rest.has_suffix("{")) net_rest = net_rest.substring(0, net_rest.length - 1).strip();
                string net_name = net_rest.strip();
                current_network = new NwNetwork(net_name, i + 1);
                diagram.networks.add(current_network);
                context_stack.add("network:" + net_name);
                continue;
            }

            // Group block: group NAME {  or  group {
            if (lower.has_prefix("group")) {
                string grp_rest = trimmed.length > 5 ? trimmed.substring(5).strip() : "";
                if (grp_rest.has_suffix("{")) grp_rest = grp_rest.substring(0, grp_rest.length - 1).strip();
                string grp_name = (grp_rest.length > 0) ? grp_rest : "group_%d".printf(diagram.groups.size);
                current_group = new NwGroup(grp_name, i + 1);
                diagram.groups.add(current_group);
                context_stack.add("group:" + grp_name);
                continue;
            }

            // Property assignment: key = "value"  (inside network or group)
            // Must be a BARE property — lines like `node_name [address = ...]`
            // contain ` = ` inside brackets and are node declarations, not
            // properties. Require that `=` comes before any `[`.
            {
                int eq_pos = trimmed.index_of(" = ");
                int bracket_pos = trimmed.index_of("[");
                bool is_bare_property = eq_pos >= 0
                    && !trimmed.has_prefix("[")
                    && (bracket_pos < 0 || bracket_pos > eq_pos);
                if (is_bare_property) {
                    string key = trimmed.substring(0, eq_pos).strip().down();
                    string val = trimmed.substring(eq_pos + 3).strip().replace("\"", "").replace(";", "");

                    if (current_network != null) {
                        if (key == "address") current_network.address = val;
                        else if (key == "color") current_network.color = val;
                    } else if (current_group != null) {
                        if (key == "color") current_group.color = val;
                    }
                    continue;
                }
            }

            // Peer link inside nwdiag: node_a -- node_b
            if (trimmed.contains(" -- ") && current_network == null && current_group == null) {
                string[] parts = trimmed.split(" -- ");
                if (parts.length == 2) {
                    diagram.peer_links.add(new NwPeerLink(
                        parts[0].strip(), parts[1].strip().replace(";", ""), i + 1
                    ));
                }
                continue;
            }

            // Inside group — node name list
            if (current_group != null && current_network == null) {
                string node_name = trimmed.replace(";", "");
                if (node_name.length > 0 && !node_name.contains("=")) {
                    current_group.node_names.add(node_name);
                }
                continue;
            }

            // Node declaration inside network: NODE_NAME [attrs]  or  NODE_NAME;
            if (current_network != null) {
                parse_network_node(trimmed, current_network, i + 1);
            }
        }
    }

    // Parse: node_name [address = "x.x.x", shape = "database"]
    private void parse_network_node(string line, NwNetwork network, int lineno) {
        string trimmed = line.replace(";", "");

        // Skip lines that look like property assignments
        if (trimmed.contains(" = ") && !trimmed.contains("[")) {
            int eq_pos = trimmed.index_of(" = ");
            string key = trimmed.substring(0, eq_pos).strip().down();
            string val = trimmed.substring(eq_pos + 3).strip().replace("\"", "");
            if (key == "address") network.address = val;
            else if (key == "color") network.color = val;
            return;
        }

        string node_name;
        string? address = null;
        string? shape = null;
        string? color = null;

        int bracket_open = trimmed.index_of("[");
        int bracket_close = trimmed.last_index_of("]");

        if (bracket_open >= 0 && bracket_close > bracket_open) {
            node_name = trimmed.substring(0, bracket_open).strip();
            string attrs_str = trimmed.substring(bracket_open + 1, bracket_close - bracket_open - 1);

            // Parse key=value attributes
            foreach (var attr in attrs_str.split(",")) {
                string a = attr.strip();
                int eq = a.index_of("=");
                if (eq < 0) continue;
                string k = a.substring(0, eq).strip().down();
                string v = a.substring(eq + 1).strip().replace("\"", "");
                if (k == "address") address = v;
                else if (k == "shape") shape = v;
                else if (k == "color") color = v;
            }
        } else {
            node_name = trimmed;
        }

        if (node_name.length == 0) return;

        // Find or create node (nodes can appear in multiple networks)
        var node = new NwNode(node_name, lineno);
        node.address = address;
        node.shape = shape;
        node.color = color;
        network.nodes.add(node);
    }
}

}
