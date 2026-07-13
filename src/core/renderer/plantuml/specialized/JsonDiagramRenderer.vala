/* JsonDiagramRenderer.vala — renders PlantUML JSON visualization */
namespace GDiagram {

public class JsonDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private int node_counter;

    public JsonDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(JsonDiagram diagram) {
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
            render_json_node(sb, diagram.root, null, diagram.highlights);
        }

        sb.append("}\n");
        return sb.str;
    }

    private string make_id() {
        node_counter++;
        return "j%d".printf(node_counter);
    }

    private string render_json_node(StringBuilder sb, JsonNode node, string? parent_id,
                                     Gee.ArrayList<string> highlights) {
        var palette = ThemeManager.get_active_palette();
        string nid = make_id();
        bool is_highlighted = is_node_highlighted(node, highlights);

        string bg_color = is_highlighted ? palette.accent_secondary : palette.node_fill;
        string border_color = is_highlighted ? palette.accent_primary : palette.node_border;

        if (node.node_type == JsonNodeType.OBJECT || node.node_type == JsonNodeType.ARRAY) {
            string type_label = (node.node_type == JsonNodeType.OBJECT) ? "{ }" : "[ ]";
            string key_display = (node.key != null && node.key.length > 0) ? Markup.escape_text(node.key) : "";

            if (key_display.length > 0) {
                sb.append_printf("    \"%s\" [shape=plaintext label=<\n", nid);
                sb.append_printf("        <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\">\n", bg_color, border_color);
                sb.append_printf("        <TR><TD ALIGN=\"LEFT\"><B>%s</B></TD><TD ALIGN=\"RIGHT\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>\n",
                    key_display, palette.edge_text, type_label);
                sb.append("        </TABLE>\n    >]\n");
            } else {
                sb.append_printf("    \"%s\" [shape=plaintext label=<\n", nid);
                sb.append_printf("        <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\">\n", bg_color, border_color);
                sb.append_printf("        <TR><TD><FONT COLOR=\"%s\">%s</FONT></TD></TR>\n", palette.edge_text, type_label);
                sb.append("        </TABLE>\n    >]\n");
            }

            if (parent_id != null) {
                sb.append_printf("    \"%s\" -> \"%s\"\n", parent_id, nid);
            }

            foreach (var child in node.children) {
                render_json_node(sb, child, nid, highlights);
            }
        } else {
            // Leaf node: key: value
            string key_part = (node.key != null && node.key.length > 0)
                ? "<B>%s</B>: ".printf(Markup.escape_text(node.key))
                : "";
            string val = Markup.escape_text(node.get_display_value());
            string val_color;
            switch (node.node_type) {
                case JsonNodeType.STRING:   val_color = palette.success; break;
                case JsonNodeType.NUMBER:   val_color = palette.accent_primary; break;
                case JsonNodeType.BOOLEAN:  val_color = palette.warning; break;
                case JsonNodeType.NULL_VALUE: val_color = palette.edge_text; break;
                default: val_color = palette.node_text; break;
            }

            sb.append_printf("    \"%s\" [shape=plaintext label=<\n", nid);
            sb.append_printf("        <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\">\n", bg_color, border_color);
            sb.append_printf("        <TR><TD ALIGN=\"LEFT\">%s<FONT COLOR=\"%s\">%s</FONT></TD></TR>\n",
                key_part, val_color, val);
            sb.append("        </TABLE>\n    >]\n");

            if (parent_id != null) {
                sb.append_printf("    \"%s\" -> \"%s\"\n", parent_id, nid);
            }
        }

        return nid;
    }

    private bool is_node_highlighted(JsonNode node, Gee.ArrayList<string> highlights) {
        if (node.key == null) return false;
        foreach (var h in highlights) {
            if (h == node.key || h.has_suffix("." + node.key)) return true;
        }
        return false;
    }

    public uint8[]? render_to_svg(JsonDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse JSON DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout JSON graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render JSON diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(JsonDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(JsonDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(JsonDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(JsonDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
