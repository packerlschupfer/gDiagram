/* ChronologyDiagramRenderer.vala — renders PlantUML Chronology as vertical timeline */
namespace GDiagram {

public class ChronologyDiagramRenderer : Object {
    private unowned Gvc.Context context;

    public ChronologyDiagramRenderer(Gvc.Context ctx,
                                      Gee.ArrayList<ElementRegion> regions,
                                      string engine) {
        this.context = ctx;
    }

    public string generate_dot(ChronologyDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [fontname=\"Sans\" fontsize=11]\n");
        sb.append("    edge [dir=none]\n\n");

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n\n",
                RenderUtils.escape_label(diagram.title));
        }

        if (diagram.events.size == 0) {
            sb.append("    empty [label=\"(no events)\" shape=note]\n}\n");
            return sb.str;
        }

        // Timeline spine nodes (invisible, just for layout)
        int n = diagram.events.size;
        for (int i = 0; i < n; i++) {
            sb.append_printf("    spine_%d [shape=point width=0.1 style=filled fillcolor=\"%s\"]\n", i, palette.boundary_stroke);
        }

        // Connect spine nodes vertically
        for (int i = 0; i < n - 1; i++) {
            sb.append_printf("    spine_%d -> spine_%d [color=\"%s\" penwidth=2 style=solid]\n", i, i + 1, palette.boundary_stroke);
        }
        sb.append("\n");

        // Event nodes alternating left/right — cycle through palette roles.
        string[] fill_colors = {
            palette.container_fill, palette.success, palette.accent_secondary,
            palette.person_fill, palette.warning, palette.component_fill,
            palette.database_fill, palette.external_fill
        };

        for (int i = 0; i < n; i++) {
            var ev = diagram.events.get(i);
            string esc_name = RenderUtils.escape_label(ev.name);
            string esc_date = RenderUtils.escape_label(ev.date_str);
            string fill = fill_colors[i % fill_colors.length];

            sb.append_printf("    event_%d [label=\"%s\\n%s\" shape=box style=filled fillcolor=\"%s\" fontsize=10]\n",
                i, esc_name, esc_date, fill);

            // Connect to spine with constraint=false so events float to sides
            sb.append_printf("    spine_%d -> event_%d [color=\"%s\" style=dashed constraint=false]\n", i, i, palette.edge_color);
        }
        sb.append("\n");

        // Invisible edges to push events to alternating sides
        sb.append("    { edge [style=invis]\n");
        for (int i = 0; i < n; i++) {
            // Alternate: even events left, odd events right
            if (i % 2 == 0) {
                sb.append_printf("    event_%d -> spine_%d\n", i, i);
            } else {
                sb.append_printf("    spine_%d -> event_%d\n", i, i);
            }
        }
        sb.append("    }\n");

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(ChronologyDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse Chronology DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout Chronology graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render Chronology diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(ChronologyDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(ChronologyDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(ChronologyDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(ChronologyDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
