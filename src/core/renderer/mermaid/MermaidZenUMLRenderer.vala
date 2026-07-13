/* MermaidZenUMLRenderer.vala — Mermaid ZenUML renderer */
namespace GDiagram {

public class MermaidZenUMLRenderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;

    public MermaidZenUMLRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.ctx = ctx;
        this.regions = regions;
    }

    public string generate_dot(MermaidZenUML diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    edge [fontsize=9 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // Participant nodes in a rank=same group
        sb.append("    { rank=same\n");
        if (diagram.participants.size > 0) {
            foreach (var p in diagram.participants) {
                string shape;
                string fill;
                switch (p.actor_type.down()) {
                    case "actor":       shape = "oval";      fill = palette.person_fill; break;
                    case "database":    shape = "cylinder";  fill = palette.database_fill; break;
                    case "boundary":    shape = "box";       fill = palette.accent_secondary; break;
                    case "control":     shape = "diamond";   fill = palette.warning; break;
                    case "entity":      shape = "ellipse";   fill = palette.component_fill; break;
                    default:            shape = "box";       fill = palette.node_fill; break;
                }
                // Use color override if specified
                if (p.color != null && p.color.length > 0) {
                    string c = p.color;
                    if (c.has_prefix("#") && c.length > 1) {
                        string cv = c.substring(1);
                        bool is_hex = true;
                        foreach (char ch in cv.to_utf8()) {
                            if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'))) {
                                is_hex = false;
                                break;
                            }
                        }
                        fill = is_hex ? c : cv;
                    }
                }
                string esc_name = RenderUtils.escape_label(p.name);
                sb.append_printf("        \"%s\" [label=\"%s\\n[%s]\" shape=%s style=filled fillcolor=\"%s\" fontcolor=\"%s\"]\n",
                    p.name, esc_name, p.actor_type, shape, fill, palette.node_text);
            }
        }
        sb.append("    }\n\n");

        // Message edges
        int msg_num = 1;
        foreach (var msg in diagram.messages) {
            string label = "%d: %s".printf(msg_num, RenderUtils.escape_label(msg.method));
            if (msg.is_return) {
                sb.append_printf("    \"%s\" -> \"%s\" [label=\"%s\" style=dashed arrowhead=open]\n",
                    msg.from_name, msg.to_name, label);
            } else {
                sb.append_printf("    \"%s\" -> \"%s\" [label=\"%s\"]\n",
                    msg.from_name, msg.to_name, label);
            }
            msg_num++;
        }

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidZenUML diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse ZenUML DOT graph");
            return null;
        }

        int ret = ctx.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout ZenUML graph");
            ctx.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(ctx, graph, "svg", out svg_data);
        ctx.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render ZenUML graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidZenUML diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            handle.get_intrinsic_size_in_pixels(out width, out height);

            if (width <= 0) width = 400;
            if (height <= 0) height = 300;

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
            foreach (var p in diagram.participants) {
                if (p.source_line > 0)
                    element_lines.set(p.name, p.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render ZenUML SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidZenUML diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidZenUML diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidZenUML diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
