namespace GDiagram {

public class MermaidRequirementRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Palette slots cached per render (resolved in generate_dot).
    private string BOX_FILL;
    private string BOX_BORDER;
    private string BOX_TEXT;
    // Diagram of the current generate_dot() pass — read for classDef / style lookups
    private MermaidRequirement? current = null;

    public MermaidRequirementRenderer(Gvc.Context ctx,
                                      Gee.ArrayList<ElementRegion> regions,
                                      string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidRequirement diagram) {
        var palette = ThemeManager.get_active_palette();
        BOX_FILL   = palette.node_fill;
        BOX_BORDER = palette.node_border;
        BOX_TEXT   = RenderUtils.contrast_text_themed(palette.node_fill, palette.node_text);
        current = diagram;
        var sb = new StringBuilder();
        sb.append("digraph requirement {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        // Mermaid honours "direction" in requirement diagrams (default top-down)
        sb.append("    rankdir=%s\n".printf(MermaidSourceLine.rankdir(diagram.direction)));
        sb.append("    node [fontname=\"Sans\" fontsize=10 shape=plaintext fontcolor=\"%s\"]\n".printf(BOX_TEXT));
        sb.append("    edge [fontname=\"Sans\" fontsize=9 color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
            sb.append("    labelloc=t\n");
            sb.append("    fontsize=14\n");
            sb.append("    fontname=\"Sans Bold\"\n\n");
        }

        // Emit nodes
        foreach (var elem in diagram.elements) {
            string safe_id = make_id(elem.name);
            bool is_element = elem.req_type.down() == "element";

            if (is_element) {
                sb.append_printf("    %s [label=<%s>]\n",
                    safe_id, build_element_label(elem));
            } else {
                sb.append_printf("    %s [label=<%s>]\n",
                    safe_id, build_requirement_label(elem));
            }

        }

        sb.append("\n");

        // Emit edges. Mermaid draws every relationship dashed with an open arrow at
        // the target, except "contains", which is solid with the marker at the source.
        foreach (var rel in diagram.relationships) {
            string src_id = make_id(rel.source);
            string tgt_id = make_id(rel.target);
            bool contains = rel.rel_type.down() == "contains";
            string ends = contains
                ? "dir=both arrowtail=odot arrowhead=none"
                : "style=dashed arrowhead=vee";
            sb.append_printf("    %s -> %s [label=\"%s\" %s]\n",
                src_id, tgt_id,
                RenderUtils.escape_label("<<%s>>".printf(rel.rel_type)),
                ends);
        }

        sb.append("}\n");
        return sb.str;
    }

    // Two compartments: "<<Type>>" over the bold name, then the body rows
    private string box_label(ReqElement elem, string type_text, string name, string body) {
        string fill = BOX_FILL;
        string border = BOX_BORDER;
        string text_color = BOX_TEXT;
        element_colors(elem, ref fill, ref border, ref text_color);
        var sb = new StringBuilder();
        sb.append_printf(
            "<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"6\" BGCOLOR=\"%s\" COLOR=\"%s\">",
            fill, border);
        sb.append_printf("<TR><TD><FONT COLOR=\"%s\">&lt;&lt;%s&gt;&gt;<BR/><B>%s</B></FONT></TD></TR>",
                         text_color, xml_escape(type_text), xml_escape(name));
        if (body.length > 0) {
            sb.append("<HR/>");
            sb.append_printf("<TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>",
                             text_color, body);
        }
        sb.append("</TABLE>");
        return sb.str;
    }

    // "classDef"/"class" and "style" specs, later ones winning, as Mermaid applies them
    private void element_colors(ReqElement elem, ref string fill, ref string border, ref string text_color) {
        if (current == null) return;
        var specs = new Gee.ArrayList<string>();
        foreach (string name in elem.css_classes) {
            if (current.class_defs.has_key(name)) specs.add(current.class_defs.get(name));
        }
        if (elem.inline_style != null) specs.add(elem.inline_style);
        if (specs.size == 0) return;
        string? css_fill, css_stroke, css_text;
        MermaidSourceLine.style_colors(specs, out css_fill, out css_stroke, out css_text);
        if (css_fill != null) {
            fill = RenderUtils.sanitize_color(css_fill);
            if (css_text == null) text_color = RenderUtils.contrast_text(fill);
        }
        if (css_stroke != null) border = RenderUtils.sanitize_color(css_stroke);
        if (css_text != null) text_color = RenderUtils.sanitize_color(css_text);
    }

    private static void add_row(StringBuilder rows, string label, string value) {
        if (value.length == 0) return;
        if (rows.len > 0) rows.append("<BR ALIGN=\"LEFT\"/>");
        rows.append(xml_escape(label + value));
    }

    private string build_requirement_label(ReqElement elem) {
        var rows = new StringBuilder();
        add_row(rows, "ID: ", elem.id);
        add_row(rows, "Text: ", elem.text);
        add_row(rows, "Risk: ", title_case(elem.risk));
        add_row(rows, "Verification: ", title_case(elem.verifymethod));
        return box_label(elem, type_label(elem.req_type), elem.name, rows.str);
    }

    private string build_element_label(ReqElement elem) {
        var rows = new StringBuilder();
        add_row(rows, "Type: ", elem.elem_type);
        add_row(rows, "Doc Ref: ", elem.docref);
        return box_label(elem, "Element", elem.name, rows.str);
    }

    // "functionalRequirement" -> "Functional Requirement", as Mermaid labels the header
    private static string type_label(string req_type) {
        var sb = new StringBuilder();
        for (int i = 0; i < req_type.length; i++) {
            char c = req_type[i];
            if (c.isupper() && sb.len > 0) sb.append_c(' ');
            sb.append_c(i == 0 ? c.toupper() : c);
        }
        return sb.str;
    }

    // "high" -> "High" (Mermaid's RiskLevel / VerifyType labels)
    private static string title_case(string s) {
        if (s.length == 0) return s;
        return s.substring(0, 1).up() + s.substring(1);
    }

    // UTF-8 aware: replacing every non-alnum *byte* mapped "Grüße" and "Größe" to the
    // same DOT id, so one requirement vanished and its relationship became a self-loop.
    private static string make_id(string name) {
        return "r_" + RenderUtils.sanitize_id(name);
    }

    private static string xml_escape(string s) {
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;");
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidRequirement diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to layout graph with engine: %s", layout_engine);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render graph");
            return null;
        }

        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidRequirement diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 400, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
            var cr = new Cairo.Context(surface);

            cr.set_source_rgb(1, 1, 1);
            cr.paint();

            var viewport = Rsvg.Rectangle() {
                x = 0,
                y = 0,
                width = width,
                height = height
            };
            handle.render_document(cr, viewport);

            var element_lines = new Gee.HashMap<string, int>();
            foreach (var elem in diagram.elements) {
                if (elem.source_line > 0)
                    element_lines.set(make_id(elem.name), elem.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidRequirement diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidRequirement diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidRequirement diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
