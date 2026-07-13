/* ArchimateDiagramRenderer.vala — renders PlantUML Archimate diagrams via Graphviz */
namespace GDiagram {

public class ArchimateDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public ArchimateDiagramRenderer(Gvc.Context ctx,
                                     Gee.ArrayList<ElementRegion> regions,
                                     string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(ArchimateDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    compound=true\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" style=filled shape=box]\n");
        sb.append("    edge [fontsize=9 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n    labelloc=t\n    fontsize=14\n    fontcolor=\"%s\"\n\n",
                RenderUtils.escape_label(diagram.title), palette.node_text);
        }

        // Render groups as clusters
        var grouped_ids = new Gee.HashSet<string>();
        int grp_idx = 0;
        foreach (var grp in diagram.groups) {
            sb.append_printf("    subgraph cluster_grp_%d {\n", grp_idx++);
            sb.append_printf("        label=\"%s\"\n", RenderUtils.escape_label(grp.name));
            sb.append("        style=rounded\n");
            sb.append("        color=\"%s\"\n".printf(palette.boundary_stroke));
            sb.append("        bgcolor=\"%s\"\n".printf(palette.grid));
            sb.append("        fontsize=10\n");

            // Render elements inside group
            foreach (var eid in grp.element_ids) {
                var elem = diagram.find_element(eid);
                if (elem != null) {
                    render_element_dot(sb, elem, "        ");
                    grouped_ids.add(eid);
                }
            }

            sb.append("    }\n\n");
        }

        // Render ungrouped elements
        foreach (var elem in diagram.elements) {
            if (!grouped_ids.contains(elem.id)) {
                render_element_dot(sb, elem, "    ");
            }
        }

        sb.append("\n");

        // Render relations
        foreach (var rel in diagram.relations) {
            string from_id = sanitize_id(rel.from_id);
            string to_id = sanitize_id(rel.to_id);
            string style = rel.is_dotted ? "dashed" : "solid";
            string arrow = get_arrow_for_rel(rel.rel_type);

            sb.append_printf("    \"%s\" -> \"%s\" [", from_id, to_id);
            sb.append_printf("style=%s arrowhead=%s", style, arrow);
            if (rel.label != null && rel.label.length > 0) {
                sb.append_printf(" label=\"%s\"", RenderUtils.escape_label(rel.label));
            }
            sb.append("]\n");
        }

        sb.append("}\n");
        return sb.str;
    }

    private void render_element_dot(StringBuilder sb, ArchimateElement elem, string indent) {
        string fill = get_layer_color(elem.layer, elem.color);
        string border = get_layer_border(elem.layer);
        string node_id = sanitize_id(elem.id);

        // Build label: label text, optionally with stereotype
        string display_label = GLib.Markup.escape_text(elem.label);
        if (elem.stereotype != null && elem.stereotype.length > 0) {
            string stereo_text = GLib.Markup.escape_text("«" + elem.stereotype + "»");
            display_label = "<%s<BR/><FONT POINT-SIZE=\"8\">%s</FONT>>".printf(
                display_label, stereo_text);
        } else {
            display_label = "\"%s\"".printf(RenderUtils.escape_label(elem.label));
        }

        sb.append_printf("%s\"%s\" [label=%s fillcolor=\"%s\" color=\"%s\" shape=box style=filled]\n",
            indent, node_id, display_label, fill, border);
    }

    // ArchiMate's 7 layers are mapped to semantic palette slots. The
    // mapping picks colors that are visually distinct within a theme while
    // still flipping sensibly between light and dark.
    private string get_layer_color(ArchimateLayer layer, string? override_color) {
        if (override_color != null && override_color.length > 0) {
            return normalize_color(override_color);
        }
        var palette = ThemeManager.get_active_palette();
        switch (layer) {
            case ArchimateLayer.BUSINESS:       return palette.accent_secondary;
            case ArchimateLayer.APPLICATION:    return palette.container_fill;
            case ArchimateLayer.TECHNOLOGY:     return palette.success;
            case ArchimateLayer.MOTIVATION:     return palette.person_fill;
            case ArchimateLayer.PHYSICAL:       return palette.warning;
            case ArchimateLayer.IMPLEMENTATION: return palette.component_fill;
            case ArchimateLayer.STRATEGY:       return palette.accent_primary;
            default:                            return palette.node_fill;
        }
    }

    private string get_layer_border(ArchimateLayer layer) {
        var palette = ThemeManager.get_active_palette();
        switch (layer) {
            case ArchimateLayer.BUSINESS:       return palette.accent_secondary;
            case ArchimateLayer.APPLICATION:    return palette.container_border;
            case ArchimateLayer.TECHNOLOGY:     return palette.success;
            case ArchimateLayer.MOTIVATION:     return palette.person_border;
            case ArchimateLayer.PHYSICAL:       return palette.warning;
            case ArchimateLayer.IMPLEMENTATION: return palette.component_border;
            case ArchimateLayer.STRATEGY:       return palette.accent_primary;
            default:                            return palette.node_border;
        }
    }

    private string get_arrow_for_rel(string rel_type) {
        string lower = rel_type.down();
        if (lower.contains("composition"))  return "diamond";
        if (lower.contains("aggregation"))  return "odiamond";
        if (lower.contains("assignment"))   return "vee";
        if (lower.contains("triggering"))   return "normal";
        if (lower.contains("flow"))         return "open";
        if (lower.contains("serving"))      return "open";
        if (lower.contains("specialization")) return "empty";
        if (lower.contains("realization"))  return "empty";
        if (lower.contains("influence"))    return "open";
        return "open";  // Association default
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
        return (sb.len > 0) ? sb.str : "node";
    }

    private string normalize_color(string color) {
        string c = color.strip();
        if (c.has_prefix("#") && (c.length == 7 || c.length == 4)) return c;
        if (c.has_prefix("#")) return c.substring(1);
        return c;
    }

    public uint8[]? render_to_svg(ArchimateDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse Archimate DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout Archimate graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render Archimate diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(ArchimateDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(ArchimateDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(ArchimateDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(ArchimateDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
