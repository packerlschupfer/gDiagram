/* TreeDiagramRenderer.vala — renders tree structure as Graphviz DOT */
namespace GDiagram {

public class TreeDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public TreeDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(TreeDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();

        sb.append("digraph tree {\n");
        sb.append("    rankdir=TB\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    fontname=\"Sans\"\n");
        sb.append("    node [style=\"filled\" fontname=\"Sans\" fontsize=11]\n");
        sb.append("    edge [fontname=\"Sans\" fontsize=10 color=\"%s\" arrowhead=none]\n".printf(palette.edge_color));
        sb.append("    nodesep=0.4\n");
        sb.append("    ranksep=0.5\n\n");

        if (diagram.title != null) {
            sb.append("    labelloc=t\n");
            sb.append("    label=\"%s\"\n".printf(RenderUtils.escape_label(diagram.title)));
            sb.append("    fontsize=14\n");
            sb.append("    fontcolor=\"%s\"\n\n".printf(palette.node_text));
        }

        if (diagram.root != null) {
            render_tree_node(sb, diagram.root, palette);
        }

        sb.append("}\n");
        return sb.str;
    }

    private void render_tree_node(StringBuilder sb, TreeNode node, Palette palette) {
        string[] level_colors = {
            palette.node_fill,
            palette.component_fill,
            palette.container_fill,
            palette.system_fill,
            palette.accent_secondary,
            palette.person_fill
        };
        string fill = level_colors[(node.depth - 1).clamp(0, level_colors.length - 1) % level_colors.length];
        string shape = (node.children.size > 0) ? "box" : "ellipse";

        sb.append_printf("    \"%s\" [label=\"%s\" shape=%s fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
            node.id, RenderUtils.escape_label(node.text), shape, fill,
            palette.node_border, palette.node_text);

        foreach (var child in node.children) {
            render_tree_node(sb, child, palette);
            sb.append_printf("    \"%s\" -> \"%s\"\n", node.id, child.id);
        }
    }

    public uint8[]? render_to_svg(TreeDiagram diagram) {
        string dot = generate_dot(diagram);
        return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "tree");
    }

    public Cairo.ImageSurface? render_to_surface(TreeDiagram diagram) {
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

            // Build element lines map for click-to-source
            var element_lines = new Gee.HashMap<string, int>();
            var all_nodes = diagram.get_all_nodes();
            foreach (var node in all_nodes) {
                if (node.source_line > 0) {
                    element_lines.set(node.id, node.source_line);
                }
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, (int)width, (int)height);

            return surface;
        } catch (Error e) {
            warning("Failed to create surface from SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(TreeDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(TreeDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(TreeDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
