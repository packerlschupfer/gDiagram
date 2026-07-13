/* JsonDiagramRenderer.vala — renders PlantUML JSON visualization */
namespace GDiagram {

/**
 * Colours and font of a JSON/YAML data table, from the theme and the diagram's
 * skinparams (a "<style> jsonDiagram { node {...} highlight {...} arrow {...} }"
 * block arrives as "skinparam nodeBackgroundColor ..." lines).
 */
public class DataTableStyle : Object {
    public string background;
    public string fill;
    public string border;
    public string font;
    public string font_name = "Sans";
    public string font_size = "12";
    public string highlight_fill = "#CCFF02";
    public string highlight_font = "#000000";
    public string arrow;

    public static DataTableStyle from_skin(Gee.HashMap<string, string>? skin) {
        var palette = ThemeManager.get_active_palette();
        var s = new DataTableStyle();
        s.background = RenderUtils.sanitize_color(lookup(skin, {"backgroundcolor"}) ?? palette.background);
        s.fill = RenderUtils.sanitize_color(lookup(skin, {"nodebackgroundcolor", "elementbackgroundcolor"}) ?? palette.node_fill);
        s.border = RenderUtils.sanitize_color(lookup(skin, {"nodebordercolor", "elementbordercolor"}) ?? palette.node_border);
        string? font = lookup(skin, {"nodefontcolor", "defaultfontcolor"});
        s.font = font != null ? RenderUtils.sanitize_color(font) : RenderUtils.contrast_text(s.fill);
        s.font_name = lookup(skin, {"nodefontname", "defaultfontname"}) ?? "Sans";
        s.font_size = lookup(skin, {"nodefontsize", "defaultfontsize"}) ?? "12";
        string? hl = lookup(skin, {"highlightbackgroundcolor"});
        if (hl != null) {
            s.highlight_fill = RenderUtils.sanitize_color(hl);
        }
        string? hl_font = lookup(skin, {"highlightfontcolor"});
        s.highlight_font = hl_font != null ? RenderUtils.sanitize_color(hl_font) : RenderUtils.contrast_text(s.highlight_fill);
        s.arrow = RenderUtils.sanitize_color(lookup(skin, {"arrowcolor", "elementbordercolor"}) ?? palette.edge_color);
        return s;
    }

    private static string? lookup(Gee.HashMap<string, string>? skin, string[] keys) {
        if (skin == null) {
            return null;
        }
        foreach (string k in keys) {
            if (skin.has_key(k)) {
                return skin.get(k);
            }
        }
        return null;
    }

    // "skinparam name value" lines of a data diagram, keys lowercased. Returns false
    // for any other line.
    public static bool read_skinparam_line(string trimmed, Gee.HashMap<string, string> skin) {
        if (!trimmed.down().has_prefix("skinparam ")) {
            return false;
        }
        string rest = trimmed.substring(10).strip();
        int sp = rest.index_of_char(' ');
        if (sp > 0) {
            string value = rest.substring(sp + 1).strip();
            if (value.length > 0 && !value.contains("{")) {
                skin.set(rest.substring(0, sp).down(), value);
            }
        }
        return true;
    }
}

/**
 * JSON / YAML data as PlantUML draws it: every object or array is a table ("key |
 * value" rows, or one column of items); a nested object or array is a dot in its row
 * with a dashed arrow to its own table. Highlighted paths ("#highlight "a" / "b"")
 * get the highlight colours. The inline form nests the tables in their cells
 * instead, as an object diagram's "json" element does.
 */
public class DataTableBuilder : Object {
    private DataTableStyle style;
    private Gee.ArrayList<string> highlights;
    private string prefix;
    private int counter = 0;
    public StringBuilder nodes = new StringBuilder();
    public StringBuilder edges = new StringBuilder();

    public DataTableBuilder(DataTableStyle style, Gee.ArrayList<string>? highlights, string prefix) {
        this.style = style;
        this.highlights = highlights ?? new Gee.ArrayList<string>();
        this.prefix = prefix;
    }

    private bool is_highlighted(string path) {
        foreach (var h in highlights) {
            if (h == path) {
                return true;
            }
        }
        return false;
    }

    private static string child_path(string path, string key) {
        return path.length > 0 ? path + "." + key : key;
    }

    private string table_open(bool rounded) {
        return "<table border=\"1\" cellborder=\"0\" cellspacing=\"0\" cellpadding=\"3\"%s bgcolor=\"%s\" color=\"%s\" columns=\"*\" rows=\"*\">".printf(
            rounded ? " style=\"rounded\"" : "", style.fill, style.border);
    }

    // Text of a scalar as PlantUML shows it
    public static string scalar_html(JsonNode node) {
        switch (node.node_type) {
            case JsonNodeType.BOOLEAN:
                return node.bool_value ? "☑ true" : "☐ false";
            case JsonNodeType.NULL_VALUE:
                return "␀";
            case JsonNodeType.NUMBER:
                return Markup.escape_text(node.string_value ?? "%.10g".printf(node.number_value));
            default:
                string text = Markup.escape_text(node.string_value ?? "");
                return text.replace("\n", "<br align=\"left\"/>");
        }
    }

    private string cell(string content, string? bg, string align = "left", string? port = null, bool bold = false) {
        string fc = bg != null ? style.highlight_font : style.font;
        // An empty <font></font> is a Graphviz syntax error ("empty:" in YAML)
        string inner = content;
        if (content.length == 0) {
            inner = " ";
        } else if (bold) {
            inner = "<b>%s</b>".printf(content);
        }
        return "<td align=\"%s\"%s%s><font color=\"%s\">%s</font></td>".printf(
            align, bg != null ? " bgcolor=\"%s\"".printf(bg) : "",
            port != null ? " port=\"%s\"".printf(port) : "", fc, inner);
    }

    private const string DOT = "<font point-size=\"7\">●</font>";

    // A table node for `node` (and, recursively, its nested containers). Returns its id.
    public string add_box(JsonNode node, string path) {
        string id = "%s%d".printf(prefix, counter++);
        var t = new StringBuilder(table_open(true));
        var children = new Gee.ArrayList<string>();  // "port|child id" pairs, drawn after
        int port_no = 0;
        if (node.node_type == JsonNodeType.OBJECT) {
            foreach (var child in node.children) {
                string key = child.key ?? "";
                string cpath = child_path(path, key);
                string? bg = is_highlighted(cpath) ? style.highlight_fill : null;
                t.append("<tr>");
                t.append(cell(Markup.escape_text(key), bg, "left", null, true));
                if (child.is_leaf()) {
                    t.append(cell(scalar_html(child), bg));
                } else {
                    string port = "p%d".printf(port_no++);
                    t.append(cell(DOT, bg, "right", port));
                    children.add(port + "|" + add_box(child, cpath));
                }
                t.append("</tr>");
            }
        } else if (node.node_type == JsonNodeType.ARRAY) {
            int index = 0;
            foreach (var child in node.children) {
                string cpath = child_path(path, (index++).to_string());
                string? bg = is_highlighted(cpath) ? style.highlight_fill : null;
                t.append("<tr>");
                if (child.is_leaf()) {
                    t.append(cell(scalar_html(child), bg));
                } else {
                    string port = "p%d".printf(port_no++);
                    t.append(cell(DOT, bg, "center", port));
                    children.add(port + "|" + add_box(child, cpath));
                }
                t.append("</tr>");
            }
        } else {
            t.append("<tr>%s</tr>".printf(cell(scalar_html(node), null)));
        }
        if (node.children.size == 0 && !node.is_leaf()) {
            t.append("<tr><td> </td></tr>");
        }
        t.append("</table>");
        nodes.append("    %s [label=<%s>];\n".printf(id, t.str));
        foreach (string pair in children) {
            string[] parts = pair.split("|", 2);
            edges.append("    %s:%s:e -> %s;\n".printf(id, parts[0], parts[1]));
        }
        return id;
    }

    // The data as one HTML table with nested tables in its cells, under an optional
    // title row (an object diagram's "json Name { ... }")
    public string inline_table(JsonNode node, string? title, string path = "") {
        var t = new StringBuilder(title != null ? table_open(false) :
            "<table border=\"0\" cellborder=\"0\" cellspacing=\"0\" cellpadding=\"3\" columns=\"*\" rows=\"*\">");
        if (title != null) {
            t.append("<tr><td colspan=\"2\"><font color=\"%s\">%s</font></td></tr>".printf(
                style.font, Markup.escape_text(title)));
        }
        if (node.node_type == JsonNodeType.OBJECT) {
            foreach (var child in node.children) {
                string key = child.key ?? "";
                string cpath = child_path(path, key);
                string? bg = is_highlighted(cpath) ? style.highlight_fill : null;
                t.append("<tr>");
                t.append(cell(Markup.escape_text(key), bg));
                if (child.is_leaf()) {
                    t.append(cell(scalar_html(child), bg));
                } else {
                    t.append("<td cellpadding=\"0\">%s</td>".printf(inline_table(child, null, cpath)));
                }
                t.append("</tr>");
            }
        } else if (node.node_type == JsonNodeType.ARRAY) {
            int index = 0;
            foreach (var child in node.children) {
                string cpath = child_path(path, (index++).to_string());
                string? bg = is_highlighted(cpath) ? style.highlight_fill : null;
                if (child.is_leaf()) {
                    t.append("<tr>%s</tr>".printf(cell(scalar_html(child), bg)));
                } else {
                    t.append("<tr><td cellpadding=\"0\">%s</td></tr>".printf(inline_table(child, null, cpath)));
                }
            }
        } else {
            t.append("<tr>%s</tr>".printf(cell(scalar_html(node), null)));
        }
        if (node.children.size == 0 && !node.is_leaf()) {
            t.append("<tr><td> </td></tr>");
        }
        t.append("</table>");
        return t.str;
    }

    // A whole data diagram: graph attributes, tables and arrows
    public static string diagram_dot(JsonNode? root, string? title, DataTableStyle style,
                                     Gee.ArrayList<string>? highlights) {
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(style.background));
        sb.append("    rankdir=LR\n");
        sb.append("    nodesep=0.15\n");
        sb.append("    ranksep=0.4\n");
        sb.append("    node [shape=plain fontname=\"%s\" fontsize=%s fontcolor=\"%s\"]\n".printf(
            style.font_name, style.font_size, style.font));
        sb.append("    edge [style=dashed arrowhead=vee arrowsize=0.6 color=\"%s\"]\n\n".printf(style.arrow));
        if (title != null && title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(title), RenderUtils.contrast_text(style.background));
        }
        if (root != null) {
            var builder = new DataTableBuilder(style, highlights, "t");
            builder.add_box(root, "");
            sb.append(builder.nodes.str);
            sb.append(builder.edges.str);
        }
        sb.append("}\n");
        return sb.str;
    }
}

public class JsonDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public JsonDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(JsonDiagram diagram) {
        return DataTableBuilder.diagram_dot(diagram.root, diagram.title,
            DataTableStyle.from_skin(diagram.skin), diagram.highlights);
    }

    public uint8[]? render_to_svg(JsonDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
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
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

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
