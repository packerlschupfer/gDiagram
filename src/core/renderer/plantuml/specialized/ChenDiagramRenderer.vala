/* ChenDiagramRenderer.vala — renders PlantUML @startchen Chen ER notation */
namespace GDiagram {

public class ChenDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public ChenDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(ChenDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" style=filled]\n");
        sb.append("    edge [fontsize=9 color=\"%s\" fontcolor=\"%s\" dir=none]\n\n".printf(
            palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // Render entities as boxes
        foreach (var entity in diagram.entities) {
            string eid = sanitize_id(entity.name);
            string border_style = entity.is_weak ? "bold" : "solid";
            string peripheries = entity.is_weak ? "2" : "1";

            sb.append_printf("    \"%s\" [label=\"%s\" shape=box fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" style=\"filled\" peripheries=%s]\n",
                eid, RenderUtils.escape_label(entity.name),
                palette.system_fill, palette.system_border,
                RenderUtils.contrast_text(palette.system_fill), peripheries);

            // Render attributes as ellipses connected to entity
            int attr_idx = 0;
            foreach (var attr in entity.attributes) {
                string aid = "%s_attr_%d".printf(eid, attr_idx);
                string label;
                if (attr.is_key) {
                    label = "<%s>".printf(
                        "<U>%s</U>".printf(Markup.escape_text(attr.name)));
                } else if (attr.is_derived) {
                    label = "<%s>".printf(
                        "<I>%s</I>".printf(Markup.escape_text(attr.name)));
                } else {
                    label = "\"%s\"".printf(RenderUtils.escape_label(attr.name));
                }

                string attr_shape = attr.is_multivalued ? "doubleoctagon" : "ellipse";
                string attr_style = attr.is_derived ? "dashed,filled" : "filled";

                sb.append_printf("    \"%s\" [label=%s shape=%s style=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
                    aid, label, attr_shape, attr_style,
                    palette.node_fill, palette.node_border, palette.node_text);
                sb.append_printf("    \"%s\" -> \"%s\"\n", eid, aid);
                attr_idx++;
            }
        }

        sb.append("\n");

        // Render relationships as diamonds
        foreach (var rel in diagram.relationships) {
            string rid = sanitize_id(rel.name);
            sb.append_printf("    \"%s\" [label=\"%s\" shape=diamond fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" style=filled]\n",
                rid, RenderUtils.escape_label(rel.name),
                palette.accent_primary, palette.container_border,
                RenderUtils.contrast_text(palette.accent_primary));

            // Render relationship attributes
            int attr_idx = 0;
            foreach (var attr in rel.attributes) {
                string aid = "%s_rattr_%d".printf(rid, attr_idx);
                string label;
                if (attr.is_key) {
                    label = "<%s>".printf("<U>%s</U>".printf(Markup.escape_text(attr.name)));
                } else {
                    label = "\"%s\"".printf(RenderUtils.escape_label(attr.name));
                }
                sb.append_printf("    \"%s\" [label=%s shape=ellipse style=filled fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
                    aid, label, palette.node_fill, palette.node_border, palette.node_text);
                sb.append_printf("    \"%s\" -> \"%s\"\n", rid, aid);
                attr_idx++;
            }
        }

        sb.append("\n");

        // Render links with cardinality labels
        foreach (var link in diagram.links) {
            string fid = sanitize_id(link.from_name);
            string tid = sanitize_id(link.to_name);
            if (link.cardinality.length > 0) {
                sb.append_printf("    \"%s\" -> \"%s\" [label=\"%s\"]\n",
                    fid, tid, RenderUtils.escape_label(link.cardinality));
            } else {
                sb.append_printf("    \"%s\" -> \"%s\"\n", fid, tid);
            }
        }

        sb.append("}\n");
        return sb.str;
    }

    private string sanitize_id(string name) {
        var sb = new StringBuilder();
        foreach (char c in name.to_utf8()) {
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '_') {
                sb.append_c(c);
            } else {
                sb.append_c('_');
            }
        }
        return sb.str;
    }

    public uint8[]? render_to_svg(ChenDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse Chen ER DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout Chen ER graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render Chen ER diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(ChenDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(ChenDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(ChenDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(ChenDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
