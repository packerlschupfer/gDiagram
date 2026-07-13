/* MermaidRadarRenderer.vala — Mermaid radar-beta renderer using neato */
namespace GDiagram {

public class MermaidRadarRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidRadarRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidRadar diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("graph radar {\n");
        sb.append("    graph [bgcolor=\"%s\" layout=neato overlap=false]\n".printf(palette.background));
        sb.append("    node [shape=plaintext fontsize=11 fontname=\"Sans\" fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    edge [fontsize=9 color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontname=\"Sans Bold\"\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        int n = diagram.axes.size;
        if (n == 0) {
            sb.append("    empty [label=\"(no axes defined)\" pos=\"0,0!\"]\n");
            sb.append("}\n");
            return sb.str;
        }

        double axis_radius = 3.5;
        double range = diagram.max_value - diagram.min_value;
        if (range <= 0.0) range = 100.0;

        // Center node (invisible)
        sb.append("    center [label=\"\" shape=point width=0.01 pos=\"0,0!\"]\n\n");

        // Axis label nodes (placed further out than the axis edge nodes)
        for (int i = 0; i < n; i++) {
            var axis = diagram.axes.get(i);
            double angle = Math.PI / 2.0 - (2.0 * Math.PI * i / n);
            double ax = axis_radius * 1.25 * Math.cos(angle);
            double ay = axis_radius * 1.25 * Math.sin(angle);
            string esc_label = RenderUtils.escape_label(axis.label);
            sb.append_printf("    axis_%d [label=\"%s\" pos=\"%.3f,%.3f!\" fontsize=10]\n",
                i, esc_label, ax, ay);
        }
        sb.append("\n");

        // Axis edge nodes (at the polygon boundary)
        for (int i = 0; i < n; i++) {
            double angle = Math.PI / 2.0 - (2.0 * Math.PI * i / n);
            double ax = axis_radius * Math.cos(angle);
            double ay = axis_radius * Math.sin(angle);
            sb.append_printf("    axis_edge_%d [label=\"\" shape=point width=0.01 pos=\"%.3f,%.3f!\"]\n",
                i, ax, ay);
        }
        // Draw axis lines from center to edge
        for (int i = 0; i < n; i++) {
            sb.append_printf("    center -- axis_edge_%d [color=\"%s\" style=dashed penwidth=0.5]\n", i, palette.boundary_stroke);
        }
        // Draw outer polygon
        for (int i = 0; i < n; i++) {
            int next = (i + 1) % n;
            sb.append_printf("    axis_edge_%d -- axis_edge_%d [color=\"%s\" penwidth=0.5]\n", i, next, palette.grid);
        }
        sb.append("\n");

        // Curve data points — palette roles for visual distinction.
        string[] curve_colors = {
            palette.system_fill, palette.accent_secondary, palette.success,
            palette.warning, palette.person_fill
        };
        int curve_idx = 0;
        foreach (var curve in diagram.curves) {
            string color = curve_colors[curve_idx % curve_colors.length];

            // Build value array aligned to axes
            double[] vals = new double[n];
            if (curve.key_values.size > 0) {
                for (int i = 0; i < n; i++) {
                    string axis_id = diagram.axes.get(i).id;
                    if (curve.key_values.has_key(axis_id)) {
                        vals[i] = curve.key_values.get(axis_id);
                    } else {
                        vals[i] = diagram.min_value;
                    }
                }
            } else {
                for (int i = 0; i < n; i++) {
                    vals[i] = (i < curve.values.size) ? curve.values.get(i) : diagram.min_value;
                }
            }

            // Place data point nodes
            for (int i = 0; i < n; i++) {
                double v = vals[i];
                double normalized = (v - diagram.min_value) / range;
                if (normalized < 0.0) normalized = 0.0;
                if (normalized > 1.0) normalized = 1.0;
                double r = normalized * axis_radius;
                double angle = Math.PI / 2.0 - (2.0 * Math.PI * i / n);
                double px = r * Math.cos(angle);
                double py = r * Math.sin(angle);
                sb.append_printf("    curve%d_%d [label=\"\" shape=point width=0.08 pos=\"%.3f,%.3f!\" color=\"%s\"]\n",
                    curve_idx, i, px, py, color);
            }

            // Connect data points as polygon
            for (int i = 0; i < n; i++) {
                int next_i = (i + 1) % n;
                sb.append_printf("    curve%d_%d -- curve%d_%d [color=\"%s\" penwidth=2]\n",
                    curve_idx, i, curve_idx, next_i, color);
            }

            curve_idx++;
        }

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidRadar diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse radar DOT graph");
            return null;
        }

        // neato is specified inside the DOT via layout=neato attribute
        int ret = context.layout(graph, "neato");
        if (ret != 0) {
            warning("Failed to layout radar graph with neato");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render radar graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidRadar diagram) {
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
                x = 0,
                y = 0,
                width = width,
                height = height
            };
            handle.render_document(cr, viewport);

            RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render radar SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidRadar diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidRadar diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidRadar diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
