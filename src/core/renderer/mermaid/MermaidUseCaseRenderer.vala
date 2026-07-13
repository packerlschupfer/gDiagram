/* MermaidUseCaseRenderer.vala — Mermaid `usecase-beta` renderer
 *
 * A Graphviz-laid-out diagram, following the same approach as the PlantUML
 * use case renderer (src/core/renderer/plantuml/behavioral/
 * UseCaseDiagramRenderer.vala) and reusing its building blocks rather than
 * inventing a second way to draw an actor:
 *
 *   - actors are RenderUtils.actor_figure_attrs() nodes, whose sentinel cell
 *     RenderUtils.draw_actor_figures() turns into a stick figure in the SVG,
 *     with the dark-theme contrast fallback of
 *     RenderUtils.default_actor_colors();
 *   - `business` elements get the shared "gdbusiness" class, which the same
 *     pass marks with a slash;
 *   - `--x` / `x--` arrowheads are Graphviz `obox` placeholders carrying
 *     MermaidFlowchartRenderer's "gdfcross" class, which its draw_crosses()
 *     redraws as an x — Graphviz has no cross arrowhead;
 *   - a systemBoundary is a Graphviz cluster, as a PlantUML package is.
 *
 * Accepted differences from mermaid's SVG:
 *   - a system boundary is a plain titled cluster; mermaid draws a folder tab
 *     on it (and a wider one for `type: package`);
 *   - `@{ icon: … }` actors fall back to the normal stick figure, since the
 *     icon packs are a browser-side font lookup;
 *   - `animate` / `animation` on an edge is parsed and kept on the AST but not
 *     drawn: a static SVG has no CSS animation;
 *   - dagre's and Graphviz's node placement differ, as for every other
 *     Graphviz-laid-out Mermaid type here.
 */
namespace GDiagram {

public class MermaidUseCaseRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Boundary id -> cluster name, filled by generate_dot() for the click regions.
    private Gee.HashMap<string, string> boundary_clusters;
    // classDef name -> its declarations, resolved while the DOT is built.
    private Gee.HashMap<string, Gee.ArrayList<string>> class_defs;

    public MermaidUseCaseRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
        this.boundary_clusters = new Gee.HashMap<string, string>();
        this.class_defs = new Gee.HashMap<string, Gee.ArrayList<string>>();
    }

    public string generate_dot(MermaidUseCase diagram) {
        var palette = ThemeManager.get_active_palette();
        boundary_clusters = new Gee.HashMap<string, string>();
        class_defs = new Gee.HashMap<string, Gee.ArrayList<string>>();
        foreach (var def in diagram.class_defs) {
            var list = new Gee.ArrayList<string>();
            list.add_all(def.styles);
            class_defs.set(def.id, list);
        }

        string bg = RenderUtils.fill_color(palette.background);
        string text_color = RenderUtils.sanitize_color(palette.node_text);
        string edge_color = RenderUtils.sanitize_color(palette.edge_color);
        string edge_text = RenderUtils.sanitize_color(palette.edge_text);

        var sb = new StringBuilder();
        sb.append("digraph usecase {\n");
        sb.append("  rankdir=%s;\n".printf(rankdir(diagram.direction)));
        sb.append("  bgcolor=\"%s\";\n".printf(bg));
        sb.append("  compound=true;\n");
        sb.append("  node [style=\"filled\", fontname=\"Sans\", fontsize=12, fontcolor=\"%s\"];\n".printf(text_color));
        sb.append("  edge [fontname=\"Sans\", fontsize=10, color=\"%s\", fontcolor=\"%s\"];\n".printf(
            edge_color, edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append("  labelloc=\"t\";\n");
            sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
            sb.append("  fontsize=14;\n");
            sb.append("  fontname=\"Sans\";\n");
            sb.append("  fontcolor=\"%s\";\n".printf(text_color));
        }
        sb.append("\n");

        // Top-level elements first, then one cluster per boundary.
        foreach (var actor in diagram.actors) {
            if (actor.parent_id == null) sb.append(actor_node(diagram, actor, "  "));
        }
        foreach (var uc in diagram.use_cases) {
            if (uc.parent_id == null) sb.append(use_case_node(diagram, uc, "  "));
        }
        foreach (var json in diagram.json_nodes) {
            if (json.parent_id == null) sb.append(json_node(diagram, json, "  "));
        }

        int ci = 0;
        foreach (var boundary in diagram.boundaries) {
            string cluster = "cluster_%d".printf(ci++);
            boundary_clusters.set(boundary.id, cluster);
            sb.append("  subgraph %s {\n".printf(cluster));
            sb.append("    label=\"%s\";\n".printf(RenderUtils.escape_label(plain_label(boundary))));
            sb.append("    labeljust=\"l\";\n");
            sb.append("    fontsize=12;\n");
            sb.append("    fontcolor=\"%s\";\n".printf(text_color));
            sb.append("    style=\"filled%s\";\n".printf(
                boundary.boundary_type == MermaidBoundaryType.PACKAGE ? ",rounded" : ""));
            sb.append("    fillcolor=\"%s\";\n".printf(RenderUtils.fill_color(palette.grid)));
            sb.append("    color=\"%s\";\n".printf(RenderUtils.sanitize_color(palette.boundary_stroke)));
            foreach (string member in boundary.members) {
                var actor = diagram.find_actor(member);
                if (actor != null) {
                    sb.append(actor_node(diagram, actor, "    "));
                    continue;
                }
                var uc = diagram.find_use_case(member);
                if (uc != null) {
                    sb.append(use_case_node(diagram, uc, "    "));
                    continue;
                }
                var json = diagram.find_json(member);
                if (json != null) sb.append(json_node(diagram, json, "    "));
            }
            // An empty cluster collapses to nothing; keep it a visible frame.
            if (boundary.members.size == 0) {
                sb.append("    %s_empty [shape=point, style=invis, width=0.4, height=0.4, label=\"\"];\n".printf(
                    RenderUtils.sanitize_id(boundary.id)));
            }
            sb.append("  }\n");
        }

        if (diagram.notes.size > 0) {
            sb.append("\n  // Notes\n");
            string note_fill = RenderUtils.fill_color(palette.accent_secondary);
            foreach (var note in diagram.notes) {
                string id = "_ucnote_%s".printf(RenderUtils.sanitize_id(note.id));
                sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", fontsize=10];\n".printf(
                    id, RenderUtils.escape_label(note.label), note_fill,
                    RenderUtils.contrast_text(note_fill)));
                if (diagram.find_element(note.target) != null) {
                    sb.append("  %s -> %s [style=dotted, arrowhead=none];\n".printf(
                        id, RenderUtils.sanitize_id(note.target)));
                }
            }
        }

        sb.append("\n  // Relationships\n");
        foreach (var rel in diagram.relations) {
            sb.append(relation_edge(diagram, rel));
        }

        sb.append("}\n");
        return sb.str;
    }

    // mermaid normalises TD to TB; everything else is a Graphviz rankdir too.
    private static string rankdir(string direction) {
        switch (direction) {
            case "TB":
            case "TD": return "TB";
            case "BT": return "BT";
            case "RL": return "RL";
            default:   return "LR";
        }
    }

    // ==================== nodes ====================

    private string actor_node(MermaidUseCase diagram, MermaidUseCaseActor actor, string indent) {
        string theme_fill, theme_stroke;
        RenderUtils.default_actor_colors(out theme_fill, out theme_stroke);
        string fill = css_fill(actor, theme_fill);
        string stroke = css_stroke(actor, theme_stroke);

        string extra = "";
        if (actor.actor_type == MermaidActorType.AWESOME) extra += " gdawesome";
        else if (actor.actor_type == MermaidActorType.HOLLOW) extra += " gdhollow";
        if (actor.business) extra += " gdbusiness";

        // An actor keeps its stereotype as a line of its own above the figure;
        // only use cases fold it into the label (mermaid's own split).
        string? above = actor.stereotype != null && actor.stereotype.length > 0
            ? "<I>«%s»</I>".printf(Markup.escape_text(actor.stereotype)) : null;
        string below = Markup.escape_text(plain_label(actor)).replace("\n", "<BR/>");

        return "%s%s [%s];\n".printf(indent, RenderUtils.sanitize_id(actor.id),
            RenderUtils.actor_figure_attrs(above, below, fill, stroke, extra, null));
    }

    private string use_case_node(MermaidUseCase diagram, MermaidUseCaseItem uc, string indent) {
        var palette = ThemeManager.get_active_palette();
        string fill_raw = css_fill(uc, palette.component_fill);
        string fill = RenderUtils.fill_color(fill_raw);
        string stroke = css_stroke(uc, palette.component_border);
        string text = RenderUtils.contrast_text(fill);

        // mermaid folds a use case's stereotype into its label as «s»<br/>label.
        string label = plain_label(uc);
        if (uc.stereotype != null && uc.stereotype.length > 0) {
            label = "«%s»\\n%s".printf(uc.stereotype, label);
        }

        string shape = uc.shape == MermaidUseCaseShape.RECT ? "box" : "ellipse";
        // mermaid's use-case padding: 20 for an ellipse, 10 for a rectangle.
        string margin = uc.shape == MermaidUseCaseShape.RECT ? "0.14,0.08" : "0.28,0.14";
        return "%s%s [label=\"%s\", shape=%s, margin=\"%s\", style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\"%s];\n".printf(
            indent, RenderUtils.sanitize_id(uc.id), RenderUtils.escape_label(label), shape, margin,
            fill, stroke, text, uc.business ? ", class=\"gdbusiness\"" : "");
    }

    // `json id @{ … }` as the key/value table mermaid draws.
    private string json_node(MermaidUseCase diagram, MermaidUseCaseJsonNode json, string indent) {
        var palette = ThemeManager.get_active_palette();
        string fill = RenderUtils.fill_color(css_fill(json, palette.node_fill));
        string stroke = css_stroke(json, palette.node_border);
        string text = RenderUtils.contrast_text(fill);

        var rows = new StringBuilder();
        rows.append("<TR><TD BGCOLOR=\"%s\" COLSPAN=\"2\"><FONT COLOR=\"%s\"><B>%s</B></FONT></TD></TR>".printf(
            fill, text, Markup.escape_text(json.id)));
        for (int i = 0; i < json.keys.size; i++) {
            string value = i < json.values.size ? json.values.get(i) : "";
            rows.append("<TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>".printf(
                text, Markup.escape_text(json.keys.get(i)), text, Markup.escape_text(value)));
        }
        if (json.keys.size == 0) {
            rows.append("<TR><TD COLSPAN=\"2\"><FONT COLOR=\"%s\">(empty)</FONT></TD></TR>".printf(text));
        }
        return "%s%s [shape=plain, style=\"\", label=<<TABLE BORDER=\"1\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" COLOR=\"%s\" BGCOLOR=\"%s\">%s</TABLE>>];\n".printf(
            indent, RenderUtils.sanitize_id(json.id), stroke, fill, rows.str);
    }

    // ==================== edges ====================

    private static string relation_edge(MermaidUseCase diagram, MermaidUseCaseRelation rel) {
        string from = RenderUtils.sanitize_id(rel.source);
        string to = RenderUtils.sanitize_id(rel.target);
        var attrs = new Gee.ArrayList<string>();

        switch (rel.kind) {
            case MermaidUseCaseRelationKind.INCLUDE:
            case MermaidUseCaseRelationKind.EXTEND:
                attrs.add("style=dashed");
                attrs.add("arrowhead=normal");
                break;
            case MermaidUseCaseRelationKind.GENERALIZATION:
                // A hollow triangle, as UML (and mermaid's `extension` marker).
                attrs.add("arrowhead=empty");
                break;
            default:
                attrs.add(association_markers(rel.arrow));
                break;
        }

        // Graphviz has no cross arrowhead: the obox placeholder above is
        // redrawn as an x by MermaidFlowchartRenderer.draw_crosses().
        if (rel.arrow == MermaidUseCaseArrow.CROSS_ARROW ||
            rel.arrow == MermaidUseCaseArrow.CROSS_ARROW_REVERSED) {
            attrs.add("class=\"gdfcross\"");
        }

        if (rel.label != null && rel.label.length > 0) {
            attrs.add("label=\"%s\"".printf(RenderUtils.escape_label(rel.label)));
        }
        if (rel.minlen > 1) {
            attrs.add("minlen=%d".printf(rel.minlen));
        }
        foreach (string s in rel.styles) {
            string? dot = css_to_dot_edge(s);
            if (dot != null) attrs.add(dot);
        }
        return "  %s -> %s [%s];\n".printf(from, to, string.joinv(", ", attrs.to_array()));
    }

    // The arrowheads of a plain association, per mermaid's numeric arrowType.
    private static string association_markers(MermaidUseCaseArrow arrow) {
        switch (arrow) {
            case MermaidUseCaseArrow.BACK_ARROW:
                return "dir=back, arrowtail=normal, arrowhead=none";
            case MermaidUseCaseArrow.LINE_SOLID:
                return "arrowhead=none";
            case MermaidUseCaseArrow.CIRCLE_ARROW:
                return "arrowhead=dot";
            case MermaidUseCaseArrow.CIRCLE_ARROW_REVERSED:
                return "dir=back, arrowtail=dot, arrowhead=none";
            case MermaidUseCaseArrow.CROSS_ARROW:
                return "arrowhead=obox";
            case MermaidUseCaseArrow.CROSS_ARROW_REVERSED:
                return "dir=back, arrowtail=obox, arrowhead=none";
            case MermaidUseCaseArrow.SOLID_ARROW:
            default:
                return "arrowhead=normal";
        }
    }

    // ==================== styling ====================

    // `classDef`/`style`/`:::` boil down to CSS declarations; the two that
    // Graphviz has an equivalent for are `fill` and `stroke`.
    private string? css_value(MermaidUseCaseElement el, string property) {
        for (int i = el.styles.size - 1; i >= 0; i--) {
            string? v = declaration_value(el.styles.get(i), property);
            if (v != null) return v;
        }
        var diagram_classes = el.classes;
        for (int i = diagram_classes.size - 1; i >= 0; i--) {
            // The classDef list is resolved by the caller through class_styles().
            string? v = class_styles_value(diagram_classes.get(i), property);
            if (v != null) return v;
        }
        return null;
    }

    private string? class_styles_value(string class_name, string property) {
        if (!class_defs.has_key(class_name)) return null;
        var list = class_defs.get(class_name);
        for (int i = list.size - 1; i >= 0; i--) {
            string? v = declaration_value(list.get(i), property);
            if (v != null) return v;
        }
        return null;
    }

    private static string? declaration_value(string declaration, string property) {
        int c = declaration.index_of_char(':');
        if (c < 0) return null;
        if (declaration.substring(0, c).strip().down() != property) return null;
        string v = declaration.substring(c + 1).strip();
        return v.length > 0 ? v : null;
    }

    private string css_fill(MermaidUseCaseElement el, string fallback) {
        string? v = css_value(el, "fill");
        return v != null ? RenderUtils.sanitize_color(v) : RenderUtils.sanitize_color(fallback);
    }

    private string css_stroke(MermaidUseCaseElement el, string fallback) {
        string? v = css_value(el, "stroke");
        return v != null ? RenderUtils.sanitize_color(v) : RenderUtils.sanitize_color(fallback);
    }

    private static string? css_to_dot_edge(string declaration) {
        int c = declaration.index_of_char(':');
        if (c < 0) return null;
        string key = declaration.substring(0, c).strip().down();
        string value = declaration.substring(c + 1).strip();
        if (key == "stroke") return "color=\"%s\"".printf(RenderUtils.sanitize_color(value));
        if (key == "stroke-width") return "penwidth=%s".printf(value.replace("px", "").strip());
        if (key == "stroke-dasharray") return "style=dashed";
        return null;
    }

    // The label as plain text: a markdown label keeps its text, with the
    // emphasis markers dropped (Graphviz draws no inline markdown).
    private static string plain_label(MermaidUseCaseElement el) {
        if (!el.label_markdown) return el.label;
        return el.label.replace("**", "").replace("__", "").replace("*", "")
                       .replace("<br/>", "\\n").replace("<br>", "\\n");
    }

    // ==================== output ====================

    public uint8[]? render_to_svg(MermaidUseCase diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse usecase DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out usecase graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // ABI-compatible wrapper (patched Graphviz uses size_t, the VAPI unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render usecase graph");
            return null;
        }
        // Stick figures, business slashes, then the x arrowheads.
        return MermaidFlowchartRenderer.draw_crosses(RenderUtils.draw_actor_figures(svg_data));
    }

    public Cairo.ImageSurface? render_to_surface(MermaidUseCase diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 400, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
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
            var node_ids = new Gee.HashSet<string>();
            foreach (var a in diagram.actors) {
                node_ids.add(RenderUtils.sanitize_id(a.id));
                if (a.source_line > 0) element_lines.set(RenderUtils.sanitize_id(a.id), a.source_line);
            }
            foreach (var u in diagram.use_cases) {
                node_ids.add(RenderUtils.sanitize_id(u.id));
                if (u.source_line > 0) element_lines.set(RenderUtils.sanitize_id(u.id), u.source_line);
            }
            foreach (var j in diagram.json_nodes) {
                node_ids.add(RenderUtils.sanitize_id(j.id));
                if (j.source_line > 0) element_lines.set(RenderUtils.sanitize_id(j.id), j.source_line);
            }
            // A boundary is a cluster, and parse_svg_regions only takes a cluster
            // whose title is mapped — unless a node already owns that name, where
            // merging the two would grow the node's region to the whole frame.
            var region_names = new Gee.HashMap<string, string>();
            foreach (var b in diagram.boundaries) {
                string? cluster = boundary_clusters.get(b.id);
                string safe = RenderUtils.sanitize_id(b.id);
                if (cluster == null || node_ids.contains(safe)) continue;
                region_names.set(cluster, safe);
                if (b.source_line > 0 && !element_lines.has_key(safe)) {
                    element_lines.set(safe, b.source_line);
                }
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height, region_names);
            return surface;
        } catch (Error e) {
            warning("Failed to render usecase SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidUseCase diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidUseCase diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidUseCase diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
