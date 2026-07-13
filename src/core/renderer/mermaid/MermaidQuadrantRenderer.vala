/* MermaidQuadrantRenderer.vala — renders Mermaid quadrant charts via Graphviz neato */
namespace GDiagram {

public class MermaidQuadrantRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Quadrant and point colors are resolved from the active palette.

    public MermaidQuadrantRenderer(Gvc.Context ctx,
                                    Gee.ArrayList<ElementRegion> regions,
                                    string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidQuadrant diagram) {
        var palette = ThemeManager.get_active_palette();
        string Q1_FILL = palette.success;
        string Q2_FILL = palette.container_fill;
        string Q3_FILL = palette.warning;
        string Q4_FILL = palette.accent_secondary;
        string PT_FILL = palette.node_fill;
        string PT_STROKE = palette.node_border;
        string QBOX_STROKE = palette.boundary_stroke;
        var sb = new StringBuilder();

        // Canvas: 5×5 inches.  Quadrant area: [0.5,4.5] × [0.5,4.5].
        // Each quadrant occupies a 2×2 inch area.
        // neato with pinned positions.
        sb.append("graph quadrant {\n");
        sb.append("    graph [bgcolor=\"%s\" layout=neato overlap=true outputorder=nodesfirst]\n".printf(palette.background));
        sb.append("    node  [fontname=\"Sans\" fontsize=9 fontcolor=\"%s\"]\n\n".printf(palette.node_text));

        // Title
        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
            sb.append("    labelloc=t\n");
            sb.append("    fontsize=14\n");
            sb.append("    fontname=\"Sans Bold\"\n");
            sb.append("    fontcolor=\"%s\"\n\n".printf(palette.node_text));
        }

        // ---- Quadrant background rectangles (large filled boxes) ----
        // These are 2×2 inch boxes centered in each quadrant.
        // Q2=top-left, Q1=top-right, Q3=bottom-left, Q4=bottom-right
        sb.append("    // quadrant backgrounds\n");
        if (diagram.quadrant_2.length > 0) {
            sb.append_printf(
                "    qbg2 [label=\"%s\" pos=\"1.5,3.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" fontcolor=\"%s\" width=2 height=2 fixedsize=true fontsize=10 labelloc=t]\n",
                RenderUtils.escape_label(diagram.quadrant_2), Q2_FILL, QBOX_STROKE, RenderUtils.contrast_text(Q2_FILL));
        } else {
            sb.append_printf(
                "    qbg2 [label=\"\" pos=\"1.5,3.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" width=2 height=2 fixedsize=true]\n", Q2_FILL, QBOX_STROKE);
        }
        if (diagram.quadrant_1.length > 0) {
            sb.append_printf(
                "    qbg1 [label=\"%s\" pos=\"3.5,3.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" fontcolor=\"%s\" width=2 height=2 fixedsize=true fontsize=10 labelloc=t]\n",
                RenderUtils.escape_label(diagram.quadrant_1), Q1_FILL, QBOX_STROKE, RenderUtils.contrast_text(Q1_FILL));
        } else {
            sb.append_printf(
                "    qbg1 [label=\"\" pos=\"3.5,3.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" width=2 height=2 fixedsize=true]\n", Q1_FILL, QBOX_STROKE);
        }
        if (diagram.quadrant_3.length > 0) {
            sb.append_printf(
                "    qbg3 [label=\"%s\" pos=\"1.5,1.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" fontcolor=\"%s\" width=2 height=2 fixedsize=true fontsize=10 labelloc=t]\n",
                RenderUtils.escape_label(diagram.quadrant_3), Q3_FILL, QBOX_STROKE, RenderUtils.contrast_text(Q3_FILL));
        } else {
            sb.append_printf(
                "    qbg3 [label=\"\" pos=\"1.5,1.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" width=2 height=2 fixedsize=true]\n", Q3_FILL, QBOX_STROKE);
        }
        if (diagram.quadrant_4.length > 0) {
            sb.append_printf(
                "    qbg4 [label=\"%s\" pos=\"3.5,1.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" fontcolor=\"%s\" width=2 height=2 fixedsize=true fontsize=10 labelloc=t]\n",
                RenderUtils.escape_label(diagram.quadrant_4), Q4_FILL, QBOX_STROKE, RenderUtils.contrast_text(Q4_FILL));
        } else {
            sb.append_printf(
                "    qbg4 [label=\"\" pos=\"3.5,1.5!\" shape=box style=filled fillcolor=\"%s\" " +
                "color=\"%s\" width=2 height=2 fixedsize=true]\n", Q4_FILL, QBOX_STROKE);
        }
        sb.append("\n");

        // ---- Axis labels (plaintext, pinned at edges) ----
        sb.append("    // axis labels\n");
        if (diagram.x_axis_left.length > 0) {
            sb.append_printf(
                "    ax_left [label=\"%s\" pos=\"0.0,2.5!\" shape=plaintext fontsize=10 fontname=\"Sans\"]\n",
                RenderUtils.escape_label(diagram.x_axis_left));
        }
        if (diagram.x_axis_right.length > 0) {
            sb.append_printf(
                "    ax_right [label=\"%s\" pos=\"5.0,2.5!\" shape=plaintext fontsize=10 fontname=\"Sans\"]\n",
                RenderUtils.escape_label(diagram.x_axis_right));
        }
        if (diagram.y_axis_bottom.length > 0) {
            sb.append_printf(
                "    ay_bot [label=\"%s\" pos=\"2.5,0.2!\" shape=plaintext fontsize=10 fontname=\"Sans\"]\n",
                RenderUtils.escape_label(diagram.y_axis_bottom));
        }
        if (diagram.y_axis_top.length > 0) {
            sb.append_printf(
                "    ay_top [label=\"%s\" pos=\"2.5,4.8!\" shape=plaintext fontsize=10 fontname=\"Sans\"]\n",
                RenderUtils.escape_label(diagram.y_axis_top));
        }
        sb.append("\n");

        // ---- Data points (small dots with label) ----
        // Scale: dot_x = 0.5 + x * 4.0,  dot_y = 0.5 + y * 4.0
        sb.append("    // data points\n");
        for (int i = 0; i < diagram.points.size; i++) {
            var pt = diagram.points.get(i);
            double dx = 0.5 + pt.x * 4.0;
            double dy = 0.5 + pt.y * 4.0;
            sb.append_printf(
                "    pt%d [label=\"\" xlabel=\"%s\" pos=\"%.4f,%.4f!\" shape=circle style=filled " +
                "fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" width=0.12 height=0.12 fixedsize=true fontsize=8]\n",
                i,
                RenderUtils.escape_label(pt.label),
                dx, dy,
                PT_FILL, PT_STROKE, palette.node_text);
        }

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidQuadrant diagram) {
        string dot_source = generate_dot(diagram);

        // Use the neato binary directly because the Graphviz library API
        // does not reliably respect pinned positions (pos="x,y!").
        try {
            string tmp_dot = "/tmp/gdiagram_quadrant.dot";
            string tmp_svg = "/tmp/gdiagram_quadrant.svg";

            FileUtils.set_contents(tmp_dot, dot_source);

            string[] argv = {"neato", "-Tsvg", tmp_dot, "-o", tmp_svg};
            int exit_status;
            Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

            if (exit_status != 0) {
                warning("neato command failed with exit status %d", exit_status);
                return null;
            }

            uint8[] svg_data;
            FileUtils.get_data(tmp_svg, out svg_data);
            return svg_data;
        } catch (Error e) {
            warning("Failed to render quadrant diagram: %s", e.message);
            return null;
        }
    }

    public Cairo.ImageSurface? render_to_surface(MermaidQuadrant diagram) {
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
            if (height <= 0) height = 600;

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
            var cr = new Cairo.Context(surface);

            cr.set_source_rgb(1, 1, 1);
            cr.paint();

            var viewport = Rsvg.Rectangle() {
                x = 0, y = 0, width = width, height = height
            };
            handle.render_document(cr, viewport);

            var element_lines = new Gee.HashMap<string, int>();
            for (int i = 0; i < diagram.points.size; i++) {
                var pt = diagram.points.get(i);
                if (pt.source_line > 0)
                    element_lines.set("pt%d".printf(i), pt.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render quadrant SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidQuadrant diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidQuadrant diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidQuadrant diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
