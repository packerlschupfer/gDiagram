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

    // Locale-safe decimal formatting: "%f" writes a comma in a de_AT locale
    // and Graphviz then reads the coordinate as two attributes.
    private static string num(double v) { return "%.4f".printf(v).replace(",", "."); }
    private static string num2(double v) { return "%.2f".printf(v).replace(",", "."); }

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
            // Mermaid rejects a point outside 0..1; keeping it unclamped pushed
            // the pinned neato canvas far past the quadrant box.
            double qx = double.max(0.0, double.min(1.0, pt.x));
            double qy = double.max(0.0, double.min(1.0, pt.y));
            double dx = 0.5 + qx * 4.0;
            double dy = 0.5 + qy * 4.0;
            // Style precedence as in Mermaid: the point's own styles, then its
            // :::class, then the theme.
            var style = new QuadrantPoint(pt.label, pt.x, pt.y);
            if (pt.css_class != null && diagram.class_defs.has_key(pt.css_class)) {
                MermaidQuadrantParser.apply_styles(style, diagram.class_defs.get(pt.css_class));
            }
            string fill = pt.color ?? style.color ?? PT_FILL;
            string stroke = pt.stroke_color ?? style.stroke_color ?? (pt.color ?? style.color ?? PT_STROKE);
            double radius_px = pt.radius > 0 ? pt.radius : style.radius;
            double stroke_w = pt.stroke_width > 0 ? pt.stroke_width : (style.stroke_width > 0 ? style.stroke_width : 1.0);
            // Mermaid radii are pixels (1px = 0.75pt); the default dot stays 0.12in.
            string size = radius_px > 0 ? "%.4f".printf(2 * radius_px * 0.75 / 72.0).replace(",", ".") : "0.12";
            sb.append_printf(
                "    pt%d [label=\"\" xlabel=\"%s\" pos=\"%s,%s!\" shape=circle style=filled " +
                "fillcolor=\"%s\" color=\"%s\" penwidth=%s fontcolor=\"%s\" width=%s height=%s fixedsize=true fontsize=8]\n",
                i,
                RenderUtils.escape_label(pt.label),
                num(dx), num(dy),
                RenderUtils.sanitize_color(fill), RenderUtils.sanitize_color(stroke),
                num2(stroke_w), palette.node_text, size, size);
        }

        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidQuadrant diagram) {
        string dot_source = generate_dot(diagram);

        // Use the neato binary directly because the Graphviz library API
        // does not reliably respect pinned positions (pos="x,y!").
        //
        // The files go in a private temporary directory, not under fixed
        // /tmp names: two renders at once (a GUI tab and the LSP's render
        // worker are separate processes, so no in-process lock helps) read
        // each other's output, and a world-writable fixed name is a symlink
        // target anyone can plant.
        string? dir = null;
        try {
            dir = DirUtils.make_tmp("gdiagram-quadrant-XXXXXX");
            string tmp_dot = Path.build_filename(dir, "quadrant.dot");
            string tmp_svg = Path.build_filename(dir, "quadrant.svg");

            FileUtils.set_contents(tmp_dot, dot_source);

            string[] argv = {"neato", "-Gfontname=Sans", "-Tsvg", tmp_dot, "-o", tmp_svg};
            int exit_status;
            Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

            if (exit_status != 0) {
                warning("neato command failed with exit status %d", exit_status);
                return null;
            }

            uint8[] svg_data;
            FileUtils.get_data(tmp_svg, out svg_data);
            return RenderUtils.fill_svg_background(svg_data);
        } catch (Error e) {
            warning("Failed to render quadrant diagram: %s", e.message);
            return null;
        } finally {
            if (dir != null) {
                FileUtils.unlink(Path.build_filename(dir, "quadrant.dot"));
                FileUtils.unlink(Path.build_filename(dir, "quadrant.svg"));
                DirUtils.remove(dir);
            }
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
            RenderUtils.svg_page_size(handle, 600, 600, out width, out height);

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
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
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
