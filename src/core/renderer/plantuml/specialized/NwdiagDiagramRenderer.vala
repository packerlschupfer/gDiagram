/* NwdiagDiagramRenderer.vala — renders PlantUML nwdiag network diagrams */
namespace GDiagram {

public class NwdiagDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public NwdiagDiagramRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // As PlantUML draws it: every network a horizontal bar (name and address on its
    // left), every node once, between the bars of the networks it is on, with a line
    // to each bar labelled with its address there. Each network used to be a box with
    // its own copy of every node, so a node on two networks was drawn twice and
    // nothing showed the networks were connected through it.
    public string generate_dot(NwdiagDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        string node_fill = RenderUtils.sanitize_color(palette.node_fill);
        string node_border = RenderUtils.sanitize_color(palette.node_border);
        string text = RenderUtils.sanitize_color(palette.node_text);
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    nodesep=0.3\n");
        sb.append("    ranksep=0.35\n");
        sb.append("    splines=line\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" fontcolor=\"%s\"]\n".printf(text));
        sb.append("    edge [fontsize=9 fontname=\"Sans\" dir=none color=\"%s\" fontcolor=\"%s\"]\n\n".printf(
            RenderUtils.sanitize_color(palette.edge_color), RenderUtils.sanitize_color(palette.edge_text)));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), text);
        }

        // One DOT node per node name, with the attributes of its first declaration
        var ids = new Gee.HashMap<string, string>();
        var first = new Gee.HashMap<string, NwNode>();
        var order = new Gee.ArrayList<string>();
        var first_network = new Gee.HashMap<string, int>();
        for (int n = 0; n < diagram.networks.size; n++) {
            foreach (var node in diagram.networks[n].nodes) {
                if (!ids.has_key(node.name)) {
                    ids.set(node.name, "node_%d".printf(ids.size));
                    first.set(node.name, node);
                    order.add(node.name);
                    first_network.set(node.name, n);
                } else if (first.get(node.name).shape == null && node.shape != null) {
                    first.get(node.name).shape = node.shape;
                }
            }
        }
        foreach (var group in diagram.groups) {
            foreach (string name in group.node_names) {
                if (!ids.has_key(name)) {
                    ids.set(name, "node_%d".printf(ids.size));
                    first.set(name, new NwNode(name, group.source_line));
                    order.add(name);
                }
            }
        }
        foreach (var link in diagram.peer_links) {
            foreach (string name in new string[] { link.node_a, link.node_b }) {
                if (!ids.has_key(name)) {
                    ids.set(name, "node_%d".printf(ids.size));
                    first.set(name, new NwNode(name, link.source_line));
                    order.add(name);
                }
            }
        }

        // Networks: a label, then one tap point per member on the same rank, joined into
        // a bar by thick flat edges (border, fill, border). Each tap sits straight above
        // or below its node, which a bar node with fixed port positions couldn't do for
        // a node on two networks.
        for (int n = 0; n < diagram.networks.size; n++) {
            var net = diagram.networks[n];
            string bar = net.color != null && net.color.length > 0 ? normalize_color(net.color) : "#E6E6FA";
            string label = Markup.escape_text(net.name);
            if (net.address != null && net.address.length > 0) {
                label += "<br align=\"right\"/>" + Markup.escape_text(net.address) + "<br align=\"right\"/>";
            }
            sb.append_printf("    net_%d_label [shape=plaintext margin=0 label=<%s>]\n", n, label);
            int taps = int.max(1, net.nodes.size);
            var rank = new StringBuilder("net_%d_label;".printf(n));
            for (int m = 0; m < taps; m++) {
                sb.append_printf("    net_%d_m%d [shape=box label=\"\" width=0.35 height=0.07 fixedsize=true style=filled fillcolor=\"%s\" color=\"%s\" penwidth=0.8]\n",
                    n, m, bar, node_border);
                rank.append(" net_%d_m%d;".printf(n, m));
            }
            sb.append_printf("    { rank=same; %s }\n", rank.str);
            sb.append_printf("    net_%d_label -> net_%d_m0 [style=invis]\n", n, n);
            for (int m = 1; m < taps; m++) {
                sb.append_printf("    net_%d_m%d -> net_%d_m%d [color=\"%s:%s:%s\" penwidth=1.6]\n",
                    n, m - 1, n, m, node_border, bar, node_border);
            }
            if (n > 0) {
                sb.append_printf("    net_%d_m0 -> net_%d_m0 [style=invis minlen=2 weight=1]\n", n - 1, n);
            }
        }
        sb.append("\n");

        // Groups: a coloured box around their nodes
        var grouped = new Gee.HashSet<string>();
        int g = 0;
        foreach (var group in diagram.groups) {
            string fill = group.color != null && group.color.length > 0 ? normalize_color(group.color) : palette.grid;
            sb.append_printf("    subgraph cluster_group_%d {\n        label=\"\"\n        style=filled\n        fillcolor=\"%s\"\n        color=\"%s\"\n",
                g++, fill, fill);
            foreach (string name in group.node_names) {
                if (grouped.add(name)) {
                    append_node(sb, ids.get(name), first.get(name), node_fill, node_border, "        ");
                }
            }
            sb.append("    }\n");
        }
        foreach (string name in order) {
            if (!grouped.contains(name)) {
                append_node(sb, ids.get(name), first.get(name), node_fill, node_border, "    ");
            }
        }
        sb.append("\n");

        // Member lines: from the node's first network down to it, from it down to the others
        for (int n = 0; n < diagram.networks.size; n++) {
            var net = diagram.networks[n];
            for (int m = 0; m < net.nodes.size; m++) {
                var node = net.nodes[m];
                string label = node.address != null && node.address.length > 0
                    ? " label=\"%s\"".printf(RenderUtils.escape_label(node.address)) : "";
                if (first_network.get(node.name) == n) {
                    sb.append_printf("    net_%d_m%d -> %s [weight=10%s]\n", n, m, ids.get(node.name), label);
                } else {
                    sb.append_printf("    %s -> net_%d_m%d [weight=10%s]\n", ids.get(node.name), n, m, label);
                }
            }
        }

        foreach (var link in diagram.peer_links) {
            sb.append_printf("    %s -> %s\n", ids.get(link.node_a), ids.get(link.node_b));
        }

        sb.append("}\n");
        return sb.str;
    }

    private void append_node(StringBuilder sb, string id, NwNode node, string fill, string border, string indent) {
        string label = node.description != null && node.description.length > 0 ? node.description : node.name;
        string node_fill = node.color != null && node.color.length > 0 ? normalize_color(node.color) : fill;
        sb.append_printf("%s%s [label=\"%s\" shape=%s style=\"%s\" fillcolor=\"%s\" color=\"%s\"%s]\n",
            indent, id, RenderUtils.escape_label(label), get_node_shape(node.shape),
            node.shape != null && node.shape.down() == "cloud" ? "filled,rounded" : "filled",
            node_fill, border,
            node.color != null ? " fontcolor=\"%s\"".printf(RenderUtils.contrast_text(node_fill)) : "");
    }

    // PlantUML's nwdiag shapes: a box by default, a cylinder for a database; the
    // others come as close as Graphviz shapes allow
    private string get_node_shape(string? shape) {
        if (shape == null) return "box";
        switch (shape.down()) {
            case "database":  return "cylinder";
            case "cloud":     return "ellipse";
            case "storage":   return "cylinder";
            case "actor":     return "egg";
            case "folder":    return "folder";
            case "file":      return "note";
            case "card":      return "box";
            case "queue":     return "cds";
            case "stack":     return "box3d";
            case "collections": return "box3d";
            case "hexagon":   return "hexagon";
            case "boundary":  return "circle";
            case "control":   return "circle";
            case "entity":    return "circle";
            case "interface": return "circle";
            case "usecase":   return "ellipse";
            default:          return "box";
        }
    }

    private string normalize_color(string color) {
        string c = color.strip();
        if (c.has_prefix("#") && (c.length == 7 || c.length == 4)) return c;
        if (c.has_prefix("#")) return c.substring(1);
        return c;
    }

    public uint8[]? render_to_svg(NwdiagDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse nwdiag DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout nwdiag graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render nwdiag diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(NwdiagDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(NwdiagDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(NwdiagDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(NwdiagDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
