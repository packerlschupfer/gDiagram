namespace GDiagram {

public class MermaidRequirementRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Palette slots cached per render (resolved in generate_dot).
    private string REQ_HEADER_BG;
    private string REQ_BODY_BG;
    private string ELEM_HEADER_BG;
    private string ELEM_BODY_BG;
    private string BODY_TEXT;

    public MermaidRequirementRenderer(Gvc.Context ctx,
                                      Gee.ArrayList<ElementRegion> regions,
                                      string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidRequirement diagram) {
        var palette = ThemeManager.get_active_palette();
        REQ_HEADER_BG   = palette.container_border;
        REQ_BODY_BG     = palette.container_fill;
        ELEM_HEADER_BG  = palette.success;
        ELEM_BODY_BG    = palette.success;
        BODY_TEXT       = palette.edge_text;
        var sb = new StringBuilder();
        sb.append("digraph requirement {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [fontname=\"Sans\" fontsize=10 shape=plaintext]\n");
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

        // Emit edges
        foreach (var rel in diagram.relationships) {
            string src_id = make_id(rel.source);
            string tgt_id = make_id(rel.target);
            string style = get_edge_style(rel.rel_type);
            string color = get_edge_color(rel.rel_type);
            sb.append_printf("    %s -> %s [label=\"%s\" %s color=\"%s\" fontcolor=\"%s\"]\n",
                src_id, tgt_id,
                RenderUtils.escape_label(rel.rel_type),
                style, color, BODY_TEXT);
        }

        sb.append("}\n");
        return sb.str;
    }

    private string build_requirement_label(ReqElement elem) {
        // Determine border color based on risk
        string border_color = get_risk_border_color(elem.risk);

        var sb = new StringBuilder();
        sb.append("<TABLE BORDER=\"2\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" COLOR=\"");
        sb.append(border_color);
        sb.append("\">");

        // Header row: requirement type
        sb.append_printf(
            "<TR><TD BGCOLOR=\"%s\"><FONT COLOR=\"white\"><B>%s</B></FONT></TD></TR>",
            REQ_HEADER_BG,
            xml_escape(elem.req_type)
        );

        // Name + ID row
        string name_id = xml_escape(elem.name);
        if (elem.id.length > 0 && elem.id != elem.name) {
            name_id += "  <FONT COLOR=\"" + BODY_TEXT + "\">id: " + xml_escape(elem.id) + "</FONT>";
        }
        sb.append_printf(
            "<TR><TD BGCOLOR=\"%s\"><B>%s</B></TD></TR>",
            REQ_BODY_BG, name_id
        );

        // Text row (if any)
        if (elem.text.length > 0) {
            sb.append_printf(
                "<TR><TD BGCOLOR=\"%s\">%s</TD></TR>",
                REQ_BODY_BG, xml_escape(elem.text)
            );
        }

        // Risk + verify row (if any)
        var meta = new StringBuilder();
        if (elem.risk.length > 0) {
            meta.append("risk: ");
            meta.append(xml_escape(elem.risk));
        }
        if (elem.verifymethod.length > 0) {
            if (meta.len > 0) meta.append(" | ");
            meta.append("verify: ");
            meta.append(xml_escape(elem.verifymethod));
        }
        if (meta.len > 0) {
            sb.append_printf(
                "<TR><TD BGCOLOR=\"%s\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>",
                REQ_BODY_BG, BODY_TEXT, meta.str
            );
        }

        sb.append("</TABLE>");
        return sb.str;
    }

    private string build_element_label(ReqElement elem) {
        var sb = new StringBuilder();
        sb.append("<TABLE BORDER=\"2\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" COLOR=\"");
        sb.append(ELEM_HEADER_BG);
        sb.append("\">");

        // Header row: "element"
        sb.append_printf(
            "<TR><TD BGCOLOR=\"%s\"><FONT COLOR=\"white\"><B>element</B></FONT></TD></TR>",
            ELEM_HEADER_BG
        );

        // Name row
        sb.append_printf(
            "<TR><TD BGCOLOR=\"%s\"><B>%s</B></TD></TR>",
            ELEM_BODY_BG, xml_escape(elem.name)
        );

        // type and docref
        if (elem.elem_type.length > 0) {
            sb.append_printf(
                "<TR><TD BGCOLOR=\"%s\">type: %s</TD></TR>",
                ELEM_BODY_BG, xml_escape(elem.elem_type)
            );
        }
        if (elem.docref.length > 0) {
            sb.append_printf(
                "<TR><TD BGCOLOR=\"%s\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>",
                ELEM_BODY_BG, BODY_TEXT, xml_escape(elem.docref)
            );
        }

        sb.append("</TABLE>");
        return sb.str;
    }

    private string get_risk_border_color(string risk) {
        var palette = ThemeManager.get_active_palette();
        switch (risk.down()) {
            case "high":   return palette.warning;
            case "medium": return palette.accent_secondary;
            case "low":    return palette.success;
            default:       return palette.container_border;
        }
    }

    private string get_edge_style(string rel_type) {
        switch (rel_type.down()) {
            case "traces":  return "style=dashed";
            case "derives": return "style=dotted";
            default:        return "style=solid";
        }
    }

    private string get_edge_color(string rel_type) {
        var palette = ThemeManager.get_active_palette();
        switch (rel_type.down()) {
            case "satisfies": return palette.accent_primary;
            case "traces":    return palette.boundary_stroke;
            case "contains":  return palette.success;
            case "copies":    return palette.accent_secondary;
            case "derives":   return palette.person_fill;
            case "refines":   return palette.warning;
            case "verifies":  return palette.component_border;
            default:          return palette.edge_color;
        }
    }

    private string make_id(string name) {
        var sb = new StringBuilder("r_");
        foreach (char c in name.to_utf8()) {
            if (c.isalnum() || c == '_') sb.append_c(c);
            else sb.append_c('_');
        }
        return sb.str;
    }

    private string xml_escape(string s) {
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;");
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidRequirement diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
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
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

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
            handle.get_intrinsic_size_in_pixels(out width, out height);

            if (width <= 0) width = 600;
            if (height <= 0) height = 400;

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
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
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
