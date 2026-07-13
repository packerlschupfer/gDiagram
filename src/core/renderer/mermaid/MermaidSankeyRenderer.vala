namespace GDiagram {

public class MermaidSankeyRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Per-node fill + stroke rotate through these palette role slots.
    private string[] node_colors_from_palette(Palette p) {
        return { p.container_fill, p.success, p.accent_secondary, p.warning, p.person_fill };
    }
    private string[] node_strokes_from_palette(Palette p) {
        return { p.container_border, p.success, p.accent_secondary, p.warning, p.person_border };
    }

    public MermaidSankeyRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidSankey diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph sankey {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [fontname=\"Sans\" fontsize=10 style=filled shape=box]\n");
        sb.append("    edge [fontname=\"Sans\" fontsize=8 color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        var nodes = diagram.get_nodes();

        // Find source-only and target-only nodes
        var has_incoming = new Gee.HashSet<string>();
        var has_outgoing = new Gee.HashSet<string>();
        foreach (var link in diagram.links) {
            has_outgoing.add(link.source);
            has_incoming.add(link.target);
        }

        // Find max value for edge width scaling
        double max_val = 0.001;
        foreach (var link in diagram.links) {
            if (link.value > max_val) max_val = link.value;
        }

        // Emit nodes with colors
        int ci = 0;
        foreach (var node in nodes) {
            string safe_id = make_id(node);
            string[] node_colors = node_colors_from_palette(palette);
            string[] node_strokes = node_strokes_from_palette(palette);
            string fill = node_colors[ci % node_colors.length];
            string stroke = node_strokes[ci % node_strokes.length];
            string label = RenderUtils.escape_label(node);
            sb.append_printf("    %s [label=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
                safe_id, label, fill, stroke, RenderUtils.contrast_text(fill));
            regions.add(new ElementRegion(node, 0, 0, 0, 0, 0));
            ci++;
        }
        sb.append("\n");

        // Rank groupings
        var sources_only = new Gee.ArrayList<string>();
        var targets_only = new Gee.ArrayList<string>();
        foreach (var node in nodes) {
            bool is_src = has_outgoing.contains(node);
            bool is_tgt = has_incoming.contains(node);
            if (is_src && !is_tgt) sources_only.add(node);
            if (is_tgt && !is_src) targets_only.add(node);
        }

        if (sources_only.size > 0) {
            sb.append("    { rank=min");
            foreach (var n in sources_only) sb.append_printf(" %s", make_id(n));
            sb.append(" }\n");
        }
        if (targets_only.size > 0) {
            sb.append("    { rank=max");
            foreach (var n in targets_only) sb.append_printf(" %s", make_id(n));
            sb.append(" }\n");
        }
        sb.append("\n");

        // Emit edges
        bool show_labels = diagram.links.size <= 20;
        foreach (var link in diagram.links) {
            double width = 1.0 + (link.value / max_val) * 7.0;
            string src_id = make_id(link.source);
            string tgt_id = make_id(link.target);
            if (show_labels) {
                sb.append_printf("    %s -> %s [penwidth=%.1f label=\"%.0f\"]\n",
                    src_id, tgt_id, width, link.value);
            } else {
                sb.append_printf("    %s -> %s [penwidth=%.1f]\n",
                    src_id, tgt_id, width);
            }
        }

        if (diagram.title != null) {
            sb.append_printf("\n    labelloc=t label=\"%s\" fontsize=12 fontname=\"Sans Bold\" fontcolor=\"%s\"\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        sb.append("}\n");
        return sb.str;
    }

    private string make_id(string name) {
        // Create a safe Graphviz node ID from a name
        var sb = new StringBuilder("n_");
        foreach (char c in name.to_utf8()) {
            if (c.isalnum() || c == '_') sb.append_c(c);
            else sb.append_c('_');
        }
        return sb.str;
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidSankey diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to layout graph with engine: %s", layout_engine);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render graph");
            return null;
        }

        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidSankey diagram) {
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

            RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidSankey diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidSankey diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidSankey diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
