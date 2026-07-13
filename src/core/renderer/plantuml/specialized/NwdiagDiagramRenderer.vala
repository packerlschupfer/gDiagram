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

    public string generate_dot(NwdiagDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    compound=true\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" style=filled]\n");
        sb.append("    edge [fontsize=9 color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // Track all unique node names across networks (last occurrence wins for peer links)
        var all_nodes = new Gee.HashMap<string, string>();  // node_name -> node_id

        // Render networks as clusters
        int net_idx = 0;
        foreach (var net in diagram.networks) {
            string net_color = (net.color != null && net.color.length > 0)
                ? normalize_color(net.color) : palette.component_fill;

            string net_label = net.name;
            if (net.address != null && net.address.length > 0) {
                net_label = "%s\\n%s".printf(net.name, net.address);
            }

            sb.append_printf("    subgraph cluster_net_%d {\n", net_idx);
            sb.append_printf("        label=\"%s\"\n", RenderUtils.escape_label(net_label));
            sb.append("        style=filled\n");
            sb.append_printf("        bgcolor=\"%s\"\n", net_color);
            sb.append("        color=\"%s\"\n".printf(palette.container_border));

            // Render nodes inside this network
            foreach (var node in net.nodes) {
                string node_shape = get_node_shape(node.shape);
                string node_fill = get_node_fill(node.shape, node.color);
                string node_label = node.name;
                if (node.address != null && node.address.length > 0) {
                    node_label = "%s\\n%s".printf(node.name, node.address);
                }
                string esc_label = RenderUtils.escape_label(node_label);

                // Use unique node ID per network to allow node in multiple networks
                string node_id = "%s_net%d".printf(sanitize_id(node.name), net_idx);
                sb.append_printf("        \"%s\" [label=\"%s\" shape=%s fillcolor=\"%s\"]\n",
                    node_id, esc_label, node_shape, node_fill);

                all_nodes.set(node.name, node_id);
            }

            sb.append("    }\n\n");
            net_idx++;
        }

        // Peer links between nodes
        foreach (var link in diagram.peer_links) {
            string id_a = all_nodes.has_key(link.node_a)
                ? all_nodes.get(link.node_a)
                : sanitize_id(link.node_a);
            string id_b = all_nodes.has_key(link.node_b)
                ? all_nodes.get(link.node_b)
                : sanitize_id(link.node_b);
            sb.append_printf("    \"%s\" -> \"%s\" [dir=none style=bold]\n", id_a, id_b);
        }

        sb.append("}\n");
        return sb.str;
    }

    private string sanitize_id(string name) {
        var sb = new StringBuilder();
        foreach (char c in name.to_utf8()) {
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '_') {
                sb.append_c(c);
            } else {
                sb.append_c('_');
            }
        }
        return sb.str;
    }

    private string get_node_shape(string? shape) {
        if (shape == null) return "box";
        switch (shape.down()) {
            case "database":  return "cylinder";
            case "cloud":     return "oval";
            case "server":    return "box";
            case "router":    return "diamond";
            case "internet":  return "oval";
            case "node":      return "box";
            default:          return "box";
        }
    }

    private string get_node_fill(string? shape, string? color) {
        if (color != null && color.length > 0) return normalize_color(color);
        var palette = ThemeManager.get_active_palette();
        if (shape == null) return palette.container_fill;
        switch (shape.down()) {
            case "database":  return palette.database_fill;
            case "cloud":     return palette.person_fill;
            case "server":    return palette.system_fill;
            case "router":    return palette.accent_secondary;
            case "internet":  return palette.external_fill;
            default:          return palette.container_fill;
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

        var graph = Gvc.Graph.read_string(dot);
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
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

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
