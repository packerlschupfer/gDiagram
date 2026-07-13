/* RegexDiagramRenderer.vala — renders PlantUML @startregex as railroad/NFA diagram */
namespace GDiagram {

public class RegexDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private int state_counter;

    public RegexDiagramRenderer(Gvc.Context ctx,
                                 Gee.ArrayList<ElementRegion> regions,
                                 string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    private const double FONT = 13.0;
    private const double BOX_H = 24.0;

    // The pattern as PlantUML draws it: one railroad track, left to right —
    // literal runs in plain boxes, character classes dashed, escapes, `.`
    // and anchors in rounded grey boxes; `?` and `*` get a bypass above,
    // `+` and `*` a return loop, other counts a `{n,m}` bracket.
    public string generate_dot(RegexDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        state_counter = 0;
        var p = new RailPainter();
        p.line_color = palette.node_text;
        p.text_color = palette.node_text;

        double y = 10.0;
        if (diagram.title != null && diagram.title.length > 0) {
            p.dot.left_text(10, y + 12, diagram.title, 16, true, palette.node_text);
            y += 34;
        }
        var body = build(diagram.root);
        double track = y + body.up + 4;
        p.hline(10, 26, track);
        body.draw(p, 26, track);
        p.hline(26 + body.w, 42 + body.w, track);
        return p.dot.finish(palette.background);
    }

    private RailItem box(string text, RailBoxStyle style) {
        state_counter++;
        return new RailBox.styled(text, style, "regex_%d".printf(state_counter), FONT, BOX_H);
    }

    private RailItem build(RegexNode node) {
        switch (node.node_type) {
            case RegexNodeType.LITERAL:
                return box(node.text, RailBoxStyle.PLAIN);
            case RegexNodeType.CHAR_CLASS: {
                string t = node.text;
                if (t.has_prefix("[") && t.has_suffix("]") && t.length >= 2) {
                    string inner = t.substring(1, t.length - 2);
                    if (inner.has_prefix("^")) inner = "^ " + inner.substring(1);
                    return box(inner, RailBoxStyle.DASHED);
                }
                return box(t, RailBoxStyle.ROUNDED);
            }
            case RegexNodeType.DOT:
            case RegexNodeType.ANCHOR:
                return box(node.text, RailBoxStyle.ROUNDED);
            case RegexNodeType.SEQUENCE: {
                var items = new Gee.ArrayList<RailItem>();
                var run = new StringBuilder();
                foreach (var c in node.children) {
                    // Consecutive literal characters form one box ("ab")
                    if (c.node_type == RegexNodeType.LITERAL) {
                        run.append(c.text);
                        continue;
                    }
                    if (run.len > 0) {
                        items.add(box(run.str, RailBoxStyle.PLAIN));
                        run.truncate(0);
                    }
                    items.add(build(c));
                }
                if (run.len > 0) items.add(box(run.str, RailBoxStyle.PLAIN));
                if (items.size == 0) return new RailEmpty();
                if (items.size == 1) return items[0];
                return new RailSequence(items);
            }
            case RegexNodeType.ALTERNATION: {
                var items = new Gee.ArrayList<RailItem>();
                foreach (var c in node.children) items.add(build(c));
                if (items.size == 0) return new RailEmpty();
                if (items.size == 1) return items[0];
                return new RailChoice(items);
            }
            case RegexNodeType.GROUP:
                if (node.children.size > 0) return build(node.children[0]);
                return new RailEmpty();
            case RegexNodeType.QUANTIFIER: {
                if (node.children.size == 0) return new RailEmpty();
                RailItem item = build(node.children[0]);
                if (node.max_count == -1 || node.max_count > 1) {
                    item = new RailLoop(item);
                }
                string label = get_quantifier_label(node);
                if (label != "*" && label != "+" && label != "?") {
                    item = new RailBracket(item, label);
                }
                if (node.min_count == 0) {
                    var items = new Gee.ArrayList<RailItem>();
                    items.add(new RailEmpty());
                    items.add(item);
                    item = new RailChoice(items, true);
                }
                return item;
            }
            default:
                return new RailEmpty();
        }
    }

    private string get_quantifier_label(RegexNode node) {
        if (node.min_count == 0 && node.max_count == -1) return "*";
        if (node.min_count == 1 && node.max_count == -1) return "+";
        if (node.min_count == 0 && node.max_count == 1) return "?";
        if (node.min_count == node.max_count) return "{%d}".printf(node.min_count);
        if (node.max_count == -1) return "{%d,}".printf(node.min_count);
        return "{%d,%d}".printf(node.min_count, node.max_count);
    }

    public uint8[]? render_to_svg(RegexDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse regex DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout regex graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render regex diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(RegexDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(RegexDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(RegexDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(RegexDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
