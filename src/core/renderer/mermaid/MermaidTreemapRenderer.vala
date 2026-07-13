/* MermaidTreemapRenderer.vala — Mermaid treemap-beta renderer */
namespace GDiagram {

public class MermaidTreemapRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private int node_counter;
    private Gee.HashMap<string, int> _element_lines = new Gee.HashMap<string, int>();

    public MermaidTreemapRenderer(Gvc.Context ctx,
                                    Gee.ArrayList<ElementRegion> regions,
                                    string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidTreemap diagram) {
        this.node_counter = 0;
        this._element_lines = new Gee.HashMap<string, int>();
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" style=filled]\n");
        sb.append("    edge [color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n\n",
                RenderUtils.escape_label(diagram.title));
        }

        // Get max value for font size scaling
        double max_val = 1.0;
        foreach (var root in diagram.roots) {
            double tv = root.total_value();
            if (tv > max_val) max_val = tv;
        }

        // Render all root nodes and their subtrees
        foreach (var root in diagram.roots) {
            render_node(sb, root, null, max_val);
        }

        sb.append("}\n");
        return sb.str;
    }

    private string make_node_id() {
        node_counter++;
        return "n%d".printf(node_counter);
    }

    private string render_node(StringBuilder sb, TreemapNode node, string? parent_id, double max_val) {
        string nid = make_node_id();
        if (node.source_line > 0)
            _element_lines.set(nid, node.source_line);

        // Depth-based colors from the active palette.
        var palette = ThemeManager.get_active_palette();
        string[] depth_colors = {
            palette.system_fill,
            palette.container_fill,
            palette.component_fill,
            palette.success,
            palette.accent_secondary
        };
        int color_idx = int.min(node.depth, depth_colors.length - 1);
        string fill = depth_colors[color_idx];
        string font_color = (node.depth <= 1) ? RenderUtils.contrast_text(fill) : palette.node_text;

        string style = node.is_leaf ? "filled,rounded" : "filled";

        // Font size proportional to value (for leaves)
        int font_size = 11;
        if (node.is_leaf && max_val > 0) {
            double ratio = node.value / max_val;
            font_size = (int)(10.0 + ratio * 8.0);  // range 10..18
            if (font_size < 10) font_size = 10;
            if (font_size > 18) font_size = 18;
        }

        string esc_label = RenderUtils.escape_label(node.label);
        string display_label;
        if (node.is_leaf && node.value > 0.0) {
            display_label = "%s\\n%.0f".printf(esc_label, node.value);
        } else {
            display_label = esc_label;
        }

        sb.append_printf("    \"%s\" [label=\"%s\" shape=box style=\"%s\" fillcolor=\"%s\" fontcolor=\"%s\" fontsize=%d]\n",
            nid, display_label, style, fill, font_color, font_size);

        if (parent_id != null) {
            sb.append_printf("    \"%s\" -> \"%s\"\n", parent_id, nid);
        }

        foreach (var child in node.children) {
            render_node(sb, child, nid, max_val);
        }

        return nid;
    }

    public uint8[]? render_to_svg(MermaidTreemap diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse treemap DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout treemap graph with dot");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render treemap graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidTreemap diagram) {
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

            RenderUtils.parse_svg_regions(svg_data, regions, _element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render treemap SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidTreemap diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidTreemap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidTreemap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
