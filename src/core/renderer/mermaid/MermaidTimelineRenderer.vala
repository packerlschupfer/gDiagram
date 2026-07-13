/* MermaidTimelineRenderer.vala — renders Mermaid timeline diagrams via Graphviz */
namespace GDiagram {

public class MermaidTimelineRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    private string[] section_colors(Palette p) {
        return { p.container_fill, p.success, p.accent_secondary, p.warning, p.person_fill };
    }
    private string[] section_strokes(Palette p) {
        return { p.container_border, p.success, p.accent_secondary, p.warning, p.person_border };
    }

    public MermaidTimelineRenderer(Gvc.Context ctx,
                                    Gee.ArrayList<ElementRegion> regions,
                                    string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidTimeline diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph timeline {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [fontname=\"Sans\" fontsize=10 style=filled shape=plaintext]\n");
        sb.append("    edge [color=\"%s\" fontcolor=\"%s\" arrowhead=open]\n\n".printf(palette.edge_color, palette.edge_text));

        string? prev_section = null;
        int section_idx = -1;
        bool in_cluster = false;

        for (int i = 0; i < diagram.periods.size; i++) {
            var period = diagram.periods.get(i);
            string? sec = period.section_name;

            // Close previous cluster if section changed
            if (in_cluster && sec != prev_section) {
                sb.append("    }\n\n");
                in_cluster = false;
            }

            string[] sec_colors = section_colors(palette);
            string[] sec_strokes = section_strokes(palette);
            // Open new cluster for a new section
            if (sec != null && sec != prev_section) {
                section_idx++;
                int ci = section_idx % sec_colors.length;
                sb.append_printf("    subgraph cluster_%d {\n", section_idx);
                sb.append_printf("        label=\"%s\"\n", RenderUtils.escape_label(sec));
                sb.append_printf("        color=\"%s\"\n", sec_strokes[ci]);
                sb.append("        style=dashed\n");
                sb.append("        fontname=\"Sans\" fontsize=10\n");
                in_cluster = true;
                prev_section = sec;
            }

            // Determine colors — cycle through palette by section index or period index
            int color_idx;
            if (sec != null) {
                color_idx = section_idx % sec_colors.length;
            } else {
                // No section: alternate colors by period index
                color_idx = i % sec_colors.length;
            }
            string fill = sec_colors[color_idx];
            string stroke = sec_strokes[color_idx];

            // Build HTML TABLE label: header row (period label) + one row per event
            string period_label = Markup.escape_text(period.label);
            var label_sb = new StringBuilder();
            label_sb.append("<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\">");
            label_sb.append_printf("<TR><TD BGCOLOR=\"%s\"><FONT FACE=\"Sans Bold\" POINT-SIZE=\"10\"><B>%s</B></FONT></TD></TR>",
                stroke, period_label);
            foreach (var evt in period.events) {
                string evt_text = Markup.escape_text(evt.text);
                label_sb.append_printf("<TR><TD BGCOLOR=\"%s\">%s</TD></TR>", fill, evt_text);
            }
            label_sb.append("</TABLE>>");

            string indent = in_cluster ? "        " : "    ";
            sb.append_printf("%sp%d [label=%s color=\"%s\"]\n",
                indent, i, label_sb.str, stroke);
        }

        if (in_cluster) {
            sb.append("    }\n\n");
        }

        // Chain edges between consecutive periods
        for (int i = 0; i + 1 < diagram.periods.size; i++) {
            sb.append_printf("    p%d -> p%d\n", i, i + 1);
        }

        // Graph-level title
        if (diagram.title != null) {
            sb.append_printf("\n    labelloc=t\n    label=\"%s\"\n    fontsize=12\n    fontname=\"Sans Bold\"\n",
                RenderUtils.escape_label(diagram.title));
        }

        sb.append("}\n");
        return sb.str;
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidTimeline diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse timeline DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to layout timeline graph with engine: %s", layout_engine);
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render timeline graph");
            return null;
        }

        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidTimeline diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            handle.get_intrinsic_size_in_pixels(out width, out height);

            if (width <= 0) width = 800;
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

            RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render timeline SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidTimeline diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidTimeline diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidTimeline diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
