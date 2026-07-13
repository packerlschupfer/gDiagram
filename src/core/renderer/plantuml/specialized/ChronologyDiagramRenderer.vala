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

        // Events in chronological order down a spine, each label on the same row to the
        // right of its point. Alternating sides let the layout reorder the labels
        // (Email/TCP, Sprint 1/2 read out of order).
        var events = sorted_events(diagram);
        int n = events.size;
        string spine = RenderUtils.sanitize_color(palette.boundary_stroke);
        string fill = RenderUtils.sanitize_color(palette.node_fill);
        string border = RenderUtils.sanitize_color(palette.node_border);
        string text = RenderUtils.contrast_text(fill);
        for (int i = 0; i < n; i++) {
            var ev = events.get(i);
            sb.append_printf("    spine_%d [shape=point width=0.12 style=filled fillcolor=\"%s\" color=\"%s\"]\n", i, spine, spine);
            sb.append_printf("    event_%d [label=<<b>%s</b><br/><font point-size=\"9\">%s</font>> shape=box style=\"rounded,filled\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" fontsize=10]\n",
                i, Markup.escape_text(ev.name), Markup.escape_text(ev.date_str), fill, border, text);
            sb.append_printf("    { rank=same; spine_%d; event_%d }\n", i, i);
            sb.append_printf("    spine_%d -> event_%d [color=\"%s\" style=dashed minlen=1]\n", i, i, RenderUtils.sanitize_color(palette.edge_color));
            if (i > 0) {
                sb.append_printf("    spine_%d -> spine_%d [color=\"%s\" penwidth=2 weight=100]\n", i - 1, i, spine);
            }
        }
        sb.append("\n");

        sb.append("}\n");
        return sb.str;
    }

    // A date as a sortable key: "2024-3-1 9:05" -> "2024-03-01 09:05:00"
    public static string date_key(string date_str) {
        string[] parts = date_str.strip().split(" ", 2);
        var sb = new StringBuilder();
        string[] ymd = parts[0].split("-");
        for (int i = 0; i < ymd.length; i++) {
            if (i > 0) sb.append("-");
            sb.append(ymd[i].length == 1 ? "0" + ymd[i] : ymd[i]);
        }
        sb.append(" ");
        string[] hms = parts.length > 1 ? parts[1].strip().split(":") : new string[0];
        for (int i = 0; i < 3; i++) {
            if (i > 0) sb.append(":");
            string v = i < hms.length ? hms[i].strip() : "00";
            sb.append(v.length == 1 ? "0" + v : v);
        }
        return sb.str;
    }

    // The events by date; events on the same date keep their written order
    public static Gee.ArrayList<ChronologyEvent> sorted_events(ChronologyDiagram diagram) {
        var sorted = new Gee.ArrayList<ChronologyEvent>();
        foreach (var ev in diagram.events) {
            int pos = sorted.size;
            string key = date_key(ev.date_str);
            while (pos > 0 && date_key(sorted[pos - 1].date_str) > key) {
                pos--;
            }
            sorted.insert(pos, ev);
        }
        return sorted;
    }

    public uint8[]? render_to_svg(ChronologyDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
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
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

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
