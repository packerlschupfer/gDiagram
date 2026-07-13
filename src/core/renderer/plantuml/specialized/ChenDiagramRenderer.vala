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

    // PlantUML's Chen look: grey (#F1F1F1) shapes with dark outlines —
    // entities as boxes (double for <<weak>>), relationships as diamonds
    // (double for <<identifying>>), attributes as ellipses (underlined
    // <<key>>, dashed <<derived>>, double <<multi>>). Attributes sit above
    // what they belong to, composite parts above their attribute; `A -N- B`
    // puts A above B with N on the line, `=` lines are heavy.
    private const string FILL = "#F1F1F1";
    private const string LINE = "#181818";
    private const string TEXT = "#000000";

    public string generate_dot(ChenDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    ranksep=0.8\n");
        sb.append_printf("    node [fontsize=10.5 fontname=\"Sans\" style=filled fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" penwidth=0.75]\n",
            FILL, LINE, TEXT);
        sb.append_printf("    edge [fontsize=8.5 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\" dir=none penwidth=0.75]\n\n",
            palette.node_text, palette.node_text);

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=<<B>%s</B>>\n    labelloc=t\n    fontsize=10.5\n    fontcolor=\"%s\"\n\n",
                Markup.escape_text(diagram.title), palette.node_text);
        }

        var declared = new Gee.HashSet<string>();
        foreach (var entity in diagram.entities) {
            string eid = sanitize_id(entity.name);
            declared.add(eid);
            sb.append_printf("    \"%s\" [id=\"chen_%d\" label=\"%s\" shape=box peripheries=%d margin=\"0.15,0.08\"]\n",
                eid, entity.source_line, RenderUtils.escape_label(entity.label()), entity.is_weak ? 2 : 1);
            append_attributes(sb, eid, entity.attributes);
        }

        foreach (var rel in diagram.relationships) {
            string rid = sanitize_id(rel.name);
            declared.add(rid);
            sb.append_printf("    \"%s\" [id=\"chen_%d\" label=\"%s\" shape=diamond peripheries=%d]\n",
                rid, rel.source_line, RenderUtils.escape_label(rel.label()), rel.is_identifying ? 2 : 1);
            append_attributes(sb, rid, rel.attributes);
        }
        sb.append("\n");

        foreach (var link in diagram.links) {
            string fid = declare(sb, declared, link.from_name);
            string tid = declare(sb, declared, link.to_name);
            var attrs = new StringBuilder();
            if (link.cardinality.length > 0) {
                attrs.append_printf("label=\"%s\"", RenderUtils.escape_label(link.cardinality));
            }
            if (link.total) attrs.append(" penwidth=2");
            attrs.append(" minlen=2");
            sb.append_printf("    \"%s\" -> \"%s\" [%s]\n", fid, tid, attrs.str);
        }

        // Subclasses: a ∪ (or ∩ for `-<-`) half way along the line; the multi
        // form joins the subclasses through a circle holding d, o or U.
        int sub_idx = 0;
        foreach (var sub in diagram.subclasses) {
            string sup = declare(sb, declared, sub.superclass);
            string total = sub.total ? " penwidth=2" : "";
            if (sub.symbol == null) {
                string child = declare(sb, declared, sub.subclasses[0]);
                string mark = "chen_sub_%d".printf(sub_idx);
                sb.append_printf("    \"%s\" [label=\"%s\" shape=plaintext style=\"\" fontsize=14 width=0.2 height=0.2 margin=0]\n",
                    mark, sub.downwards ? "∪" : "∩");
                sb.append_printf("    \"%s\" -> \"%s\" [%s]\n", sup, mark, total.strip());
                sb.append_printf("    \"%s\" -> \"%s\" [%s]\n", mark, child, total.strip());
            } else {
                string circle = "chen_sub_%d".printf(sub_idx);
                sb.append_printf("    \"%s\" [label=\"%s\" shape=circle width=0.25 height=0.25 fixedsize=true]\n",
                    circle, RenderUtils.escape_label(sub.symbol));
                sb.append_printf("    \"%s\" -> \"%s\" [%s]\n", sup, circle, total.strip());
                int k = 0;
                foreach (var name in sub.subclasses) {
                    string child = declare(sb, declared, name);
                    string mark = "chen_sub_%d_%d".printf(sub_idx, k++);
                    sb.append_printf("    \"%s\" [label=\"∪\" shape=plaintext style=\"\" fontsize=14 width=0.2 height=0.2 margin=0]\n", mark);
                    sb.append_printf("    \"%s\" -> \"%s\"\n", circle, mark);
                    sb.append_printf("    \"%s\" -> \"%s\"\n", mark, child);
                }
            }
            sub_idx++;
        }

        sb.append("}\n");
        return sb.str;
    }

    // A name used in a link but never declared still gets a box.
    private string declare(StringBuilder sb, Gee.HashSet<string> declared, string name) {
        string id = sanitize_id(name);
        if (!declared.contains(id)) {
            declared.add(id);
            sb.append_printf("    \"%s\" [label=\"%s\" shape=box]\n", id, RenderUtils.escape_label(name));
        }
        return id;
    }

    private void append_attributes(StringBuilder sb, string owner_id, Gee.ArrayList<ChenAttribute> attrs) {
        int idx = 0;
        foreach (var attr in attrs) {
            string aid = "%s__a%d".printf(owner_id, idx++);
            string text = Markup.escape_text(attr.label());
            if (attr.is_key) text = "<U>" + text + "</U>";
            var style = new StringBuilder("filled");
            if (attr.is_derived) style.append(",dashed");
            sb.append_printf("    \"%s\" [id=\"chen_%d\" label=<%s> shape=ellipse style=\"%s\" peripheries=%d height=0.3 margin=\"0.08,0.01\"]\n",
                aid, attr.source_line, text, style.str, attr.is_multivalued ? 2 : 1);
            // attribute above its owner
            sb.append_printf("    \"%s\" -> \"%s\"\n", aid, owner_id);
            append_attributes(sb, aid, attr.children);
        }
    }

    private string sanitize_id(string name) {
        var sb = new StringBuilder();
        foreach (char c in name.to_utf8()) {
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '_' || (uchar) c >= 0x80) {  // UTF-8 bytes are valid in DOT ids
                sb.append_c(c);
            } else {
                sb.append_c('_');
            }
        }
        return sb.str;
    }

    public uint8[]? render_to_svg(ChenDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
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
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

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
