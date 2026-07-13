namespace GDiagram {

public class MermaidBlockRenderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    private string[] block_colors() {
        var p = ThemeManager.get_active_palette();
        return new string[] { p.container_fill, p.success, p.accent_secondary, p.warning, p.person_fill };
    }
    private string[] block_strokes() {
        var p = ThemeManager.get_active_palette();
        return new string[] { p.container_border, p.success, p.accent_secondary, p.warning, p.person_border };
    }

    public MermaidBlockRenderer(Gvc.Context context,
                                 Gee.ArrayList<ElementRegion> regions,
                                 string engine) {
        this.ctx = context;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidBlock diagram) {
        var palette = ThemeManager.get_active_palette();
        var BLOCK_COLORS = block_colors();
        var BLOCK_STROKES = block_strokes();
        var sb = new StringBuilder();
        sb.append("digraph block {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    compound=true\n");
        sb.append("    node [fontname=\"Sans\" fontsize=10 style=\"filled,rounded\" shape=box]\n");
        sb.append("    edge [fontname=\"Sans\" fontsize=9 color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        // Find group nodes and their children
        var groups = new Gee.HashMap<string, Gee.ArrayList<BlockNode>>();

        foreach (var node in diagram.nodes) {
            if (node.is_group) {
                groups.set(node.id, new Gee.ArrayList<BlockNode>());
            } else if (node.group_id != null && groups.has_key(node.group_id)) {
                groups.get(node.group_id).add(node);
            }
        }

        // Emit groups as clusters
        int cluster_idx = 0;
        foreach (var node in diagram.nodes) {
            if (!node.is_group) continue;
            var children = groups.get(node.id);
            if (children == null) continue;

            sb.append_printf("    subgraph cluster_%d {\n", cluster_idx++);
            sb.append_printf("        label=\"%s\"\n", RenderUtils.escape_label(node.label));
            sb.append("        style=dashed\n");
            sb.append("        color=\"%s\"\n".printf(palette.boundary_stroke));
            sb.append("        fontname=\"Sans\"\n");
            sb.append("        fontsize=10\n");

            int ci = 0;
            foreach (var child in children) {
                string fill = BLOCK_COLORS[ci % BLOCK_COLORS.length];
                string stroke = BLOCK_STROKES[ci % BLOCK_STROKES.length];
                sb.append_printf("        %s [label=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
                    child.id, RenderUtils.escape_label(child.label), fill, stroke, palette.node_text);
                ci++;
            }
            sb.append("    }\n\n");
        }

        // Emit top-level nodes (non-group, no group_id)
        int ci = 0;
        foreach (var node in diagram.nodes) {
            if (node.is_group || node.group_id != null) continue;
            string fill = BLOCK_COLORS[ci % BLOCK_COLORS.length];
            string stroke = BLOCK_STROKES[ci % BLOCK_STROKES.length];
            sb.append_printf("    %s [label=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
                node.id, RenderUtils.escape_label(node.label), fill, stroke, palette.node_text);
            ci++;
        }
        sb.append("\n");

        // Emit edges
        foreach (var edge in diagram.edges) {
            if (edge.label != null && edge.label.length > 0) {
                sb.append_printf("    %s -> %s [label=\"%s\"]\n",
                    edge.source, edge.target, RenderUtils.escape_label(edge.label));
            } else {
                sb.append_printf("    %s -> %s\n", edge.source, edge.target);
            }
        }

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("\n    labelloc=t label=\"%s\" fontsize=12 fontname=\"Sans Bold\"\n",
                RenderUtils.escape_label(diagram.title));
        }

        sb.append("}\n");
        return sb.str;
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidBlock diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse DOT graph");
            return null;
        }

        int ret = ctx.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to layout graph with engine: %s", layout_engine);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = GraphvizCompat.render_data(ctx, graph, "svg", out svg_data);

        ctx.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render graph");
            return null;
        }

        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidBlock diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

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
            foreach (var node in diagram.nodes) {
                if (!node.is_group && node.source_line > 0)
                    element_lines.set(node.id, node.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidBlock diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidBlock diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidBlock diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
