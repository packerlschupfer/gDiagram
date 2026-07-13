/* MermaidArchitectureRenderer.vala — Mermaid architecture-beta diagram renderer */
namespace GDiagram {

public class MermaidArchitectureRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidArchitectureRenderer(Gvc.Context ctx,
                                        Gee.ArrayList<ElementRegion> regions,
                                        string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    private string escape_dot(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    public string generate_dot(MermaidArchitecture diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    compound=true\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" style=filled fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    edge [fontsize=9 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                escape_dot(diagram.title), palette.node_text);
        }

        // Render top-level groups (no parent)
        render_groups(sb, diagram, null);

        // Render services not in any group
        foreach (var svc in diagram.services) {
            if (svc.group_id == null) {
                render_service(sb, svc, "    ");
            }
        }

        // Render edges
        foreach (var edge in diagram.edges) {
            string dir = edge.directed ? "forward" : "none";
            sb.append_printf("    \"%s\" -> \"%s\" [dir=%s]\n",
                escape_dot(edge.from_id), escape_dot(edge.to_id), dir);
        }

        sb.append("}\n");
        return sb.str;
    }

    private void render_groups(StringBuilder sb, MermaidArchitecture diagram, string? parent_id) {
        var palette = ThemeManager.get_active_palette();
        foreach (var group in diagram.groups) {
            if (group.parent_id != parent_id) continue;

            sb.append_printf("    subgraph cluster_%s {\n", RenderUtils.sanitize_id(group.id));
            sb.append_printf("        label=\"%s\"\n", escape_dot(group.label));
            sb.append("        style=filled\n");
            sb.append("        bgcolor=\"%s\"\n".printf(palette.grid));
            sb.append("        color=\"%s\"\n".printf(palette.container_border));
            sb.append("        fontcolor=\"%s\"\n".printf(palette.node_text));

            // Nested groups
            render_groups(sb, diagram, group.id);

            // Services in this group
            foreach (var svc in diagram.services) {
                if (svc.group_id == group.id) {
                    render_service(sb, svc, "        ");
                }
            }

            sb.append("    }\n\n");
        }
    }

    private void render_service(StringBuilder sb, ArchService svc, string indent) {
        var palette = ThemeManager.get_active_palette();
        string fill;
        string shape = "box";
        switch (svc.icon) {
            case "database": fill = palette.database_fill; shape = "cylinder"; break;
            case "disk":     fill = palette.success; break;
            case "cloud":    fill = palette.person_fill; shape = "oval"; break;
            case "internet": fill = palette.accent_secondary; shape = "oval"; break;
            case "server":   fill = palette.warning; break;
            default:         fill = palette.node_fill; break;
        }

        if (svc.is_junction) {
            sb.append_printf("%s\"%s\" [label=\"\" shape=point width=0.15 style=filled fillcolor=\"%s\"]\n",
                indent, escape_dot(svc.id), palette.boundary_stroke);
        } else {
            string label = escape_dot(svc.label);
            sb.append_printf("%s\"%s\" [label=\"%s\\n[%s]\" shape=%s fillcolor=\"%s\" fontcolor=\"%s\"]\n",
                indent, escape_dot(svc.id), label, svc.icon, shape, fill, palette.node_text);
        }
    }

    public uint8[]? render_to_svg(MermaidArchitecture diagram) {
        string dot = generate_dot(diagram);
        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse architecture DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout architecture graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render architecture graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidArchitecture diagram) {
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
            foreach (var svc in diagram.services) {
                if (svc.source_line > 0)
                    element_lines.set(escape_dot(svc.id), svc.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render architecture SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidArchitecture diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidArchitecture diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidArchitecture diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
