/* MermaidMindmapRenderer.vala — renders Mermaid mindmaps via Graphviz */
namespace GDiagram {

public class MermaidMindmapRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Colors by depth level — sourced from the active palette at render time.
    private string[] depth_fills() {
        var p = ThemeManager.get_active_palette();
        return new string[] {
            p.container_fill, p.success, p.accent_secondary,
            p.warning, p.person_fill, p.container_fill
        };
    }
    private string[] depth_strokes() {
        var p = ThemeManager.get_active_palette();
        return new string[] {
            p.container_border, p.success, p.accent_secondary,
            p.warning, p.person_border, p.container_border
        };
    }

    public MermaidMindmapRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidMindmap diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("graph mindmap {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    overlap=false\n");
        sb.append("    splines=true\n");
        sb.append("    node [fontname=\"Sans\" fontsize=10 style=filled margin=\"0.1,0.05\"]\n");
        sb.append("    edge [color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.root != null) {
            emit_node(sb, diagram.root);
            emit_edges(sb, diagram.root);
        }

        sb.append("}\n");
        return sb.str;
    }

    // Generate a unique stable node ID using source line and depth
    private string node_id(MindmapNode node) {
        return "n_%d_%d".printf(node.source_line, node.depth);
    }

    private void emit_node(StringBuilder sb, MindmapNode node) {
        var fills = depth_fills();
        var strokes = depth_strokes();
        int ci = node.depth % fills.length;
        string fill = fills[ci];
        string stroke = strokes[ci];
        string label = RenderUtils.escape_label(node.label);
        string nid = node_id(node);

        string shape_attr;
        switch (node.shape) {
            case "circle":
                shape_attr = "shape=circle fixedsize=true width=1.2";
                break;
            case "rounded":
                shape_attr = "shape=ellipse";
                break;
            case "hexagon":
                shape_attr = "shape=hexagon";
                break;
            case "cloud":
                shape_attr = "shape=ellipse style=\"filled,dashed\"";
                break;
            case "bang":
                shape_attr = "shape=note";
                break;
            case "rectangle":
                shape_attr = "shape=box";
                break;
            default:
                shape_attr = "shape=box style=\"filled,rounded\"";
                break;
        }

        if (node.depth == 0) {
            // Root gets larger font and heavier border
            sb.append_printf("    %s [label=\"%s\" %s fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" fontsize=12 penwidth=2]\n",
                nid, label, shape_attr, fill, stroke, RenderUtils.contrast_text(fill));
        } else {
            sb.append_printf("    %s [label=\"%s\" %s fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
                nid, label, shape_attr, fill, stroke, RenderUtils.contrast_text(fill));
        }

        foreach (var child in node.children) {
            emit_node(sb, child);
        }
    }

    private void collect_mindmap_lines(MindmapNode node, Gee.HashMap<string, int> element_lines) {
        if (node.source_line > 0)
            element_lines.set(node_id(node), node.source_line);
        foreach (var child in node.children)
            collect_mindmap_lines(child, element_lines);
    }

    private void emit_edges(StringBuilder sb, MindmapNode parent) {
        foreach (var child in parent.children) {
            sb.append_printf("    %s -- %s\n", node_id(parent), node_id(child));
            emit_edges(sb, child);
        }
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidMindmap diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse mindmap DOT graph");
            return null;
        }

        // Use twopi for radial mindmap layout
        int ret = context.layout(graph, "twopi");
        if (ret != 0) {
            warning("Failed to layout mindmap graph with twopi, trying dot");
            ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout mindmap graph");
                return null;
            }
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render mindmap graph");
            return null;
        }

        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidMindmap diagram) {
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
            if (height <= 0) height = 400;

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
            if (diagram.root != null)
                collect_mindmap_lines(diagram.root, element_lines);
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render mindmap SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidMindmap diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }

        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidMindmap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidMindmap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
