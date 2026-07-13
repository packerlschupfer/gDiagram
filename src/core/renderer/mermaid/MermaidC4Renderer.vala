/* MermaidC4Renderer.vala — Mermaid C4 diagram renderer */
namespace GDiagram {

public class MermaidC4Renderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidC4Renderer(Gvc.Context ctx,
                              Gee.ArrayList<ElementRegion> regions,
                              string engine) {
        this.ctx = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidC4 diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    compound=true\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    edge [fontsize=10 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", escape_dot(diagram.title));
            sb.append("    labelloc=t\n    fontsize=14\n");
            sb.append("    fontcolor=\"%s\"\n\n".printf(palette.node_text));
        }

        // Render boundaries as subgraph clusters
        render_boundaries(sb, diagram, null, 0);

        // Render elements NOT in any boundary
        foreach (var el in diagram.elements) {
            if (el.parent_boundary == null) {
                render_element(sb, el, "    ");
            }
        }

        // Render relationships
        foreach (var rel in diagram.relationships) {
            render_relationship(sb, rel);
        }

        sb.append("}\n");
        return sb.str;
    }

    private void render_boundaries(StringBuilder sb, MermaidC4 diagram, string? parent_id, int depth) {
        var palette = ThemeManager.get_active_palette();
        foreach (var boundary in diagram.boundaries) {
            if (boundary.parent_boundary != parent_id) continue;

            string cluster_id = "cluster_" + sanitize_id(boundary.id);
            sb.append_printf("    subgraph %s {\n", cluster_id);
            sb.append_printf("        label=\"%s\"\n", escape_dot(boundary.label));
            sb.append("        style=dashed\n");
            sb.append("        color=\"%s\"\n".printf(palette.boundary_stroke));
            sb.append("        fontcolor=\"%s\"\n".printf(palette.node_text));
            sb.append("        bgcolor=\"%s\"\n".printf(palette.grid));

            // Nested boundaries
            render_boundaries(sb, diagram, boundary.id, depth + 1);

            // Elements in this boundary
            foreach (var el in diagram.elements) {
                if (el.parent_boundary == boundary.id) {
                    render_element(sb, el, "        ");
                }
            }

            sb.append("    }\n\n");
        }
    }

    private void render_element(StringBuilder sb, C4Element el, string indent) {
        var palette = ThemeManager.get_active_palette();
        string shape;
        string fill_color;
        string font_color;
        string style = "filled";

        switch (el.element_type) {
            case C4ElementType.PERSON:
                shape = "oval";
                fill_color = el.is_external ? palette.external_fill : palette.person_fill;
                font_color = RenderUtils.contrast_text(fill_color);
                break;
            case C4ElementType.DEPLOYMENT_NODE:
                shape = "box";
                fill_color = palette.node_fill;
                font_color = palette.node_text;
                style = "dashed";
                break;
            case C4ElementType.CONTAINER:
                shape = el.is_db ? "cylinder" : "box";
                fill_color = el.is_external ? palette.external_fill : palette.container_fill;
                font_color = RenderUtils.contrast_text(fill_color);
                break;
            case C4ElementType.COMPONENT:
                shape = "component";
                fill_color = el.is_external ? palette.external_fill : palette.component_fill;
                font_color = palette.node_text;
                break;
            default: // SYSTEM
                shape = el.is_db ? "cylinder" : "box3d";
                fill_color = el.is_external ? palette.external_fill : palette.system_fill;
                font_color = RenderUtils.contrast_text(fill_color);
                break;
        }

        string escaped_label = escape_dot(el.label);
        string node_label;
        if (el.description != null && el.description.length > 0) {
            string descr = escape_dot(el.description ?? "");
            node_label = "%s\\n[%s]".printf(escaped_label, descr);
        } else if (el.technology != null && el.technology.length > 0) {
            string tech = escape_dot(el.technology ?? "");
            node_label = "%s\\n[%s]".printf(escaped_label, tech);
        } else {
            node_label = escaped_label;
        }

        sb.append_printf("%s\"%s\" [label=\"%s\" shape=%s style=\"%s\" fillcolor=\"%s\" fontcolor=\"%s\"]\n",
            indent, el.id, node_label, shape, style, fill_color, font_color);
    }

    private void render_relationship(StringBuilder sb, C4Relationship rel) {
        string escaped_label = escape_dot(rel.label);
        string edge_label;
        if (rel.technology != null && rel.technology.length > 0) {
            string tech = escape_dot(rel.technology ?? "");
            edge_label = "%s\\n[%s]".printf(escaped_label, tech);
        } else {
            edge_label = escaped_label;
        }

        string dir = rel.is_bidirectional ? "both" : "forward";
        if (rel.direction == "BACK") dir = "back";

        sb.append_printf("    \"%s\" -> \"%s\" [label=\"%s\" dir=%s fontsize=10]\n",
            rel.from_id, rel.to_id, edge_label, dir);
    }

    // Escape a string for use in a DOT quoted label
    private string escape_dot(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    // Sanitize an id for use as a DOT cluster identifier
    private string sanitize_id(string s) {
        var result = new StringBuilder();
        foreach (char c in s.to_utf8()) {
            if (c.isalnum() || c == '_') {
                result.append_c(c);
            } else {
                result.append_c('_');
            }
        }
        return result.str;
    }

    public uint8[]? render_to_svg(MermaidC4 diagram) {
        string dot_source = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot_source);
        if (graph == null) {
            warning("Failed to parse C4 DOT graph");
            return null;
        }

        int ret = ctx.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout C4 graph");
            ctx.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(ctx, graph, "svg", out svg_data);
        ctx.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render C4 graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidC4 diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

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
            foreach (var el in diagram.elements) {
                if (el.source_line > 0)
                    element_lines.set(el.id, el.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render C4 SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidC4 diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidC4 diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidC4 diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
