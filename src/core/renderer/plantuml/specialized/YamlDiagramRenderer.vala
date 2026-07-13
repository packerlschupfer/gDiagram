/* YamlDiagramRenderer.vala — renders PlantUML YAML visualization */
namespace GDiagram {

public class YamlDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private int node_counter;

    public YamlDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(YamlDiagram diagram) {
        this.node_counter = 0;
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [fontname=\"monospace\" fontsize=10]\n");
        sb.append("    edge [color=\"%s\"]\n\n".printf(palette.edge_color));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=13\n\n",
                RenderUtils.escape_label(diagram.title));
        }

        if (diagram.root != null) {
            render_yaml_node(sb, diagram.root, null, diagram.highlights);
        }

        sb.append("}\n");
        return sb.str;
    }

    private string make_id() {
        node_counter++;
        return "y%d".printf(node_counter);
    }

    private string render_yaml_node(StringBuilder sb, YamlNode node, string? parent_id,
                                     Gee.ArrayList<string> highlights) {
        var palette = ThemeManager.get_active_palette();
        string nid = make_id();
        bool is_highlighted = is_node_highlighted(node, highlights);
        string bg_color = is_highlighted ? palette.accent_secondary : palette.node_fill;
        string border_color = is_highlighted ? palette.accent_primary : palette.node_border;

        if (node.node_type == YamlNodeType.MAPPING || node.node_type == YamlNodeType.SEQUENCE) {
            string type_label = (node.node_type == YamlNodeType.SEQUENCE) ? "[ ]" : "{ }";
            string key_display = (node.key != null && node.key.length > 0)
                ? Markup.escape_text(node.key) : "";

            if (key_display.length > 0) {
                sb.append_printf("    \"%s\" [shape=plaintext label=<\n", nid);
                sb.append_printf("        <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\">\n",
                    bg_color, border_color);
                sb.append_printf("        <TR><TD ALIGN=\"LEFT\"><B>%s</B></TD><TD ALIGN=\"RIGHT\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>\n",
                    key_display, palette.edge_text, type_label);
                sb.append("        </TABLE>\n    >]\n");
            } else {
                sb.append_printf("    \"%s\" [shape=plaintext label=<\n", nid);
                sb.append_printf("        <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\">\n",
                    bg_color, border_color);
                sb.append_printf("        <TR><TD><FONT COLOR=\"%s\">%s</FONT></TD></TR>\n", palette.edge_text, type_label);
                sb.append("        </TABLE>\n    >]\n");
            }

            if (parent_id != null) {
                sb.append_printf("    \"%s\" -> \"%s\"\n", parent_id, nid);
            }

            foreach (var child in node.children) {
                render_yaml_node(sb, child, nid, highlights);
            }
        } else {
            // Scalar node
            string key_part = (node.key != null && node.key.length > 0)
                ? "<B>%s</B>: ".printf(Markup.escape_text(node.key))
                : "- ";
            string val = Markup.escape_text(node.value ?? "");

            // Color-code values by type
            string val_color = determine_value_color(node.value ?? "");

            sb.append_printf("    \"%s\" [shape=plaintext label=<\n", nid);
            sb.append_printf("        <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\">\n",
                bg_color, border_color);
            sb.append_printf("        <TR><TD ALIGN=\"LEFT\">%s<FONT COLOR=\"%s\">%s</FONT></TD></TR>\n",
                key_part, val_color, val);
            sb.append("        </TABLE>\n    >]\n");

            if (parent_id != null) {
                sb.append_printf("    \"%s\" -> \"%s\"\n", parent_id, nid);
            }
        }

        return nid;
    }

    private string determine_value_color(string val) {
        var palette = ThemeManager.get_active_palette();
        string v = val.down();
        if (v == "true" || v == "false" || v == "yes" || v == "no") {
            return palette.warning;
        }
        if (v == "null" || v == "~") {
            return palette.edge_text;
        }
        // Check if numeric
        bool is_num = (val.length > 0);
        bool has_digit = false;
        foreach (char ch in val.to_utf8()) {
            if (ch >= '0' && ch <= '9') {
                has_digit = true;
            } else if (ch == '.' || ch == '-' || ch == 'e' || ch == 'E' || ch == '+') {
                // allowed in numbers
            } else {
                is_num = false;
                break;
            }
        }
        if (is_num && has_digit) {
            return palette.accent_primary;
        }
        return palette.success;
    }

    private bool is_node_highlighted(YamlNode node, Gee.ArrayList<string> highlights) {
        if (node.key == null) return false;
        foreach (var h in highlights) {
            if (h == node.key || h.has_suffix("." + node.key)) return true;
        }
        return false;
    }

    public uint8[]? render_to_svg(YamlDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse YAML DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout YAML graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render YAML diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(YamlDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(YamlDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(YamlDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(YamlDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
