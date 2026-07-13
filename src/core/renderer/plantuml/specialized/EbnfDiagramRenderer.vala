/* EbnfDiagramRenderer.vala — renders PlantUML @startebnf as railroad diagrams */
namespace GDiagram {

/**
 * Builds DOT for a drawing whose geometry is computed by the renderer
 * (`layout=nop2`): Graphviz keeps every node where it is put and draws each
 * edge along the given spline, so it only paints. Coordinates are PlantUML
 * pixels with y growing downwards; they are scaled to points (1px = 0.75pt)
 * and flipped when the DOT is written. Used by the EBNF, regex and ditaa
 * renderers, whose PlantUML look (railroad tracks, ASCII-art boxes) has no
 * Graphviz layout.
 */
public class PinnedDotWriter : Object {
    public const double PX = 0.75;
    private Gee.ArrayList<string> node_head = new Gee.ArrayList<string>();
    private Gee.ArrayList<double?> node_x = new Gee.ArrayList<double?>();
    private Gee.ArrayList<double?> node_y = new Gee.ArrayList<double?>();
    private Gee.ArrayList<string> edge_attrs = new Gee.ArrayList<string>();
    private Gee.ArrayList<Gee.ArrayList<double?>> edge_pts = new Gee.ArrayList<Gee.ArrayList<double?>>();
    private Gee.ArrayList<string> edge_prefix = new Gee.ArrayList<string>();
    private int n_nodes = 0;
    public double max_x = 0;
    public double max_y = 0;
    /** Extra graph attributes, e.g. outputorder */
    public string graph_attrs = "";

    public static string num(double v) {
        return "%.2f".printf(v).replace(",", ".");
    }

    private void extend(double x, double y) {
        if (x > max_x) max_x = x;
        if (y > max_y) max_y = y;
    }

    /** A node centred at (x, y); `attrs` must not set pos. */
    public void node(double x, double y, double w, double h, string attrs) {
        string id = "n%d".printf(n_nodes++);
        node_head.add("%s [%s width=%s height=%s ".printf(id, attrs, num(w * PX / 72.0), num(h * PX / 72.0)));
        node_x.add(x);
        node_y.add(y);
        extend(x + w / 2, y + h / 2);
    }

    /**
     * Text starting at `x` (left-aligned), vertically centred on `y`. The
     * node is wider than the estimated text so nothing is clipped.
     */
    public void left_text(double x, double y, string text, double font_px, bool bold, string color,
                         string extra = "") {
        double w = text.char_count() * font_px * 0.75 + 20;
        double h = font_px * 1.6;
        string body = Markup.escape_text(text);
        if (bold) body = "<B>" + body + "</B>";
        node(x + w / 2, y, w, h,
            "%s shape=plaintext fontsize=%s fontcolor=\"%s\" label=<<TABLE BORDER=\"0\" CELLPADDING=\"0\" CELLSPACING=\"0\"><TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"%d\" ALIGN=\"LEFT\">%s</TD></TR></TABLE>>".printf(
                extra, num(font_px * PX), color, (int) (w * PX), (int) (h * PX), body));
    }

    /** A cubic Bezier spline: 3n+1 points (x, y pairs). */
    public void spline(double[] pts, string attrs, string prefix = "") {
        var list = new Gee.ArrayList<double?>();
        for (int i = 0; i + 1 < pts.length; i += 2) {
            list.add(pts[i]);
            list.add(pts[i + 1]);
            extend(pts[i], pts[i + 1]);
        }
        edge_pts.add(list);
        edge_attrs.add(attrs);
        edge_prefix.add(prefix);
    }

    /** A straight polyline through (x, y) pairs. */
    public void polyline(double[] pts, string attrs, bool arrow_end = false, bool arrow_start = false,
                         double arrow_len = 8.0) {
        if (pts.length < 4) return;
        double[] p = pts;
        string prefix = "";
        int last = p.length - 2;
        if (arrow_end) {
            double dx = p[last] - p[last - 2], dy = p[last + 1] - p[last - 1];
            double len = Math.sqrt(dx * dx + dy * dy);
            if (len > 0) {
                double cut = double.min(arrow_len, len * 0.9);
                prefix += "e,%s ".printf(pt(p[last], p[last + 1]));
                p[last] = p[last] - dx / len * cut;
                p[last + 1] = p[last + 1] - dy / len * cut;
            }
        }
        if (arrow_start) {
            double dx = p[0] - p[2], dy = p[1] - p[3];
            double len = Math.sqrt(dx * dx + dy * dy);
            if (len > 0) {
                double cut = double.min(arrow_len, len * 0.9);
                prefix = "s,%s ".printf(pt(p[0], p[1])) + prefix;
                p[0] = p[0] - dx / len * cut;
                p[1] = p[1] - dy / len * cut;
            }
        }
        var b = new double[0];
        for (int i = 0; i + 1 < p.length; i += 2) {
            if (i == 0) {
                b += p[0]; b += p[1];
            } else {
                b += p[i - 2]; b += p[i - 1];
                b += p[i]; b += p[i + 1];
                b += p[i]; b += p[i + 1];
            }
        }
        string a = attrs;
        if (arrow_end && arrow_start) a += " dir=both arrowhead=normal arrowtail=normal";
        else if (arrow_end) a += " dir=forward arrowhead=normal";
        else if (arrow_start) a += " dir=back arrowtail=normal";
        spline(b, a, prefix);
        extend(pts[0], pts[1]);
    }

    private string pt(double x, double y) {
        // y is flipped in finish(); mark it for substitution
        return "%s,@Y%s@".printf(num(x * PX), num(y));
    }

    /** The DOT text; `margin` px of empty space is kept right and below. */
    public string finish(string background, double margin = 10.0) {
        double h = (max_y + margin) * PX;
        double w = (max_x + margin) * PX;
        var sb = new StringBuilder();
        sb.append("graph g {\n");
        sb.append("    layout=nop2\n");
        if (graph_attrs.length > 0) sb.append_printf("    %s\n", graph_attrs);
        sb.append_printf("    bgcolor=\"%s\"\n", background);
        sb.append("    node [fixedsize=shape fontname=\"Sans\" label=\"\"]\n");
        // Corner anchors: the drawing keeps its margins, and the edges
        // (whose splines are given) hang off them.
        sb.append_printf("    a0 [pos=\"0,%s\" shape=point style=invis width=0 height=0]\n", num(h));
        sb.append_printf("    a1 [pos=\"%s,0\" shape=point style=invis width=0 height=0]\n", num(w));
        for (int i = 0; i < node_y.size; i++) {
            sb.append_printf("    %spos=\"%s,%s\"]\n", node_head.get(i), num(node_x.get(i) * PX),
                num(h - node_y.get(i) * PX));
        }
        for (int i = 0; i < edge_pts.size; i++) {
            var pts = edge_pts.get(i);
            var ps = new StringBuilder();
            string prefix = edge_prefix.get(i);
            ps.append(flip_marks(prefix, h));
            for (int j = 0; j + 1 < pts.size; j += 2) {
                if (j > 0) ps.append(" ");
                ps.append_printf("%s,%s", num(pts.get(j) * PX), num(h - pts.get(j + 1) * PX));
            }
            sb.append_printf("    a0 -- a1 [pos=\"%s\" %s]\n", ps.str, edge_attrs.get(i));
        }
        sb.append("}\n");
        return sb.str;
    }

    private static string flip_marks(string s, double h) {
        var res = new StringBuilder();
        int i = 0;
        while (true) {
            int a = s.index_of("@Y", i);
            if (a < 0) { res.append(s.substring(i)); break; }
            int b = s.index_of("@", a + 2);
            res.append(s.substring(i, a - i));
            double y = double.parse(s.substring(a + 2, b - a - 2));
            res.append(num(h - y * PX));
            i = b + 1;
        }
        return res.str;
    }
}


// Railroad drawing shared by the EBNF and regex renderers (both follow
// PlantUML's railroad look).
// A railroad-diagram element laid out around its track: `w` wide, reaching
// `up` above and `down` below the line it sits on.
internal abstract class RailItem : Object {
    public double w;
    public double up;
    public double down;
    public abstract void draw(RailPainter p, double x, double y);
}

internal class RailPainter : Object {
    public PinnedDotWriter dot = new PinnedDotWriter();
    public string line_color;
    public string text_color;

    public void hline(double x1, double x2, double y) {
        if (x2 - x1 < 0.01) return;
        dot.polyline({ x1, y, x2, y }, "color=\"%s\"".printf(line_color));
    }

    // A horizontal line with an arrowhead halfway, pointing left or right.
    public void arrow_line(double x1, double x2, double y, bool leftwards) {
        double mid = (x1 + x2) / 2;
        string a = "color=\"%s\" arrowsize=0.5".printf(line_color);
        if (leftwards) {
            dot.polyline({ x2, y, mid - 3, y }, a, true);
            dot.polyline({ mid - 3, y, x1, y }, "color=\"%s\"".printf(line_color));
        } else {
            dot.polyline({ x1, y, mid + 3, y }, a, true);
            dot.polyline({ mid + 3, y, x2, y }, "color=\"%s\"".printf(line_color));
        }
    }

    // A quarter-turn curve from (x1, y1) to (x2, y2), leaving horizontally
    // when `h_first`, otherwise vertically.
    public void turn(double x1, double y1, double x2, double y2, bool h_first) {
        double[] pts;
        if (h_first) {
            pts = { x1, y1, x1 + (x2 - x1) * 0.55, y1, x2, y1 + (y2 - y1) * 0.45, x2, y2 };
        } else {
            pts = { x1, y1, x1, y1 + (y2 - y1) * 0.55, x1 + (x2 - x1) * 0.45, y2, x2, y2 };
        }
        dot.spline(pts, "color=\"%s\"".printf(line_color));
    }

    public void vline(double x, double y1, double y2) {
        if (Math.fabs(y2 - y1) < 0.01) return;
        dot.polyline({ x, y1, x, y2 }, "color=\"%s\"".printf(line_color));
    }

    public static double text_width(string s, double font_px) {
        // Sans averages a little over half an em per character
        return s.char_count() * font_px * 0.58;
    }
}

internal const double RAIL_R = 10.0;       // rail curve radius
internal const double RAIL_GAP = 12.0;     // line between items of a sequence
internal const double RAIL_TRACK_GAP = 9.0;
internal const double RAIL_FONT = 14.0;
internal const double RAIL_BOX_H = 28.0;

internal enum RailBoxStyle {
    PLAIN,      // white box, light border (literal text)
    ROUNDED,    // rounded grey box (rule reference, regex escape)
    DASHED      // dashed white box (regex character class)
}

internal class RailBox : RailItem {
    private string text;
    private RailBoxStyle style;
    private string id;
    private double font;
    private double box_h;

    public RailBox(string text, bool terminal, int line) {
        this.styled(text, terminal ? RailBoxStyle.PLAIN : RailBoxStyle.ROUNDED, "ebnf_%d".printf(line),
            RAIL_FONT, RAIL_BOX_H);
    }

    public RailBox.styled(string text, RailBoxStyle style, string id, double font, double box_h) {
        this.text = text;
        this.style = style;
        this.id = id;
        this.font = font;
        this.box_h = box_h;
        w = RailPainter.text_width(text, font) + (style == RailBoxStyle.ROUNDED ? 12.0 : 8.0);
        up = box_h / 2;
        down = box_h / 2;
    }

    public override void draw(RailPainter p, double x, double y) {
        // PlantUML: rule references are rounded grey boxes, literal
        // terminals plain white boxes with a light border.
        string attrs;
        switch (style) {
            case RailBoxStyle.PLAIN:
                attrs = "shape=box style=filled fillcolor=\"#FFFFFF\" color=\"#A0A0A0\" penwidth=0.75";
                break;
            case RailBoxStyle.DASHED:
                attrs = "shape=box style=\"filled,dashed\" fillcolor=\"#FFFFFF\" color=\"#181818\" penwidth=1";
                break;
            default:
                attrs = "shape=box style=\"rounded,filled\" fillcolor=\"#F1F1F1\" color=\"#181818\" penwidth=1";
                break;
        }
        p.dot.node(x + w / 2, y, w, box_h,
            "id=\"%s\" %s fontsize=%s fontcolor=\"#000000\" label=\"%s\"".printf(id,
                attrs, PinnedDotWriter.num(font * PinnedDotWriter.PX), RenderUtils.escape_label(text)));
    }
}

// A caption over `item` hung from a bracket, as PlantUML marks `{n,m}`.
internal class RailBracket : RailItem {
    private RailItem item;
    private string label;
    private const double LABEL_H = 18.0;
    private const double BRACKET_H = 8.0;

    public RailBracket(RailItem item, string label) {
        this.item = item;
        this.label = label;
        w = double.max(item.w, RailPainter.text_width(label, 12) + 8);
        up = item.up + BRACKET_H + LABEL_H;
        down = item.down;
    }

    public override void draw(RailPainter p, double x, double y) {
        double ix = x + (w - item.w) / 2;
        p.hline(x, ix, y);
        item.draw(p, ix, y);
        p.hline(ix + item.w, x + w, y);
        double by = y - item.up - 2;
        double top = by - BRACKET_H;
        double mid = ix + item.w / 2;
        string c = "color=\"#A0A0A0\"";
        p.dot.spline({ ix, by, ix, top + 2, ix + 2, top, ix + 6, top }, c);
        p.dot.polyline({ ix + 6, top, mid - 4, top }, c);
        p.dot.spline({ mid - 4, top, mid - 1, top, mid, top - 1, mid, top - 3 }, c);
        p.dot.spline({ mid, top - 3, mid, top - 1, mid + 1, top, mid + 4, top }, c);
        p.dot.polyline({ mid + 4, top, ix + item.w - 6, top }, c);
        p.dot.spline({ ix + item.w - 6, top, ix + item.w - 2, top, ix + item.w, top + 2, ix + item.w, by }, c);
        double tw = RailPainter.text_width(label, 12) + 8;
        p.dot.node(mid, top - 3 - LABEL_H / 2, tw, LABEL_H,
            "shape=plaintext fontsize=%s fontcolor=\"%s\" label=\"%s\"".printf(
                PinnedDotWriter.num(12 * PinnedDotWriter.PX), p.text_color, RenderUtils.escape_label(label)));
    }
}

internal class RailEmpty : RailItem {
    public RailEmpty() { w = 0; up = 0; down = 0; }
    public override void draw(RailPainter p, double x, double y) {}
}

internal class RailSequence : RailItem {
    private Gee.ArrayList<RailItem> items;

    public RailSequence(Gee.ArrayList<RailItem> items) {
        this.items = items;
        w = 0; up = 0; down = 0;
        foreach (var it in items) {
            w += it.w;
            up = double.max(up, it.up);
            down = double.max(down, it.down);
        }
        if (items.size > 1) w += RAIL_GAP * (items.size - 1);
    }

    public override void draw(RailPainter p, double x, double y) {
        double cx = x;
        for (int i = 0; i < items.size; i++) {
            if (i > 0) {
                p.hline(cx, cx + RAIL_GAP, y);
                cx += RAIL_GAP;
            }
            items.get(i).draw(p, cx, y);
            cx += items.get(i).w;
        }
    }
}

// Alternatives stacked downwards; the first one stays on the track. With
// `skip_arrow` the first (empty) track is a bypass carrying an arrowhead, as
// PlantUML draws optional and repeated parts.
internal class RailChoice : RailItem {
    private Gee.ArrayList<RailItem> items;
    private double[] offsets;
    private bool skip_arrow;
    private double inner_w;

    public RailChoice(Gee.ArrayList<RailItem> items, bool skip_arrow = false) {
        this.items = items;
        this.skip_arrow = skip_arrow;
        offsets = new double[items.size];
        inner_w = 0;
        foreach (var it in items) inner_w = double.max(inner_w, it.w);
        if (skip_arrow) inner_w = double.max(inner_w, 20.0);
        w = inner_w + 4 * RAIL_R;
        up = items.get(0).up;
        double yy = 0;
        for (int i = 0; i < items.size; i++) {
            if (i > 0) {
                double prev_down = double.max(items.get(i - 1).down, RAIL_BOX_H / 2);
                yy += prev_down + RAIL_TRACK_GAP + double.max(items.get(i).up, RAIL_BOX_H / 2);
            }
            offsets[i] = yy;
        }
        down = yy + items.get(items.size - 1).down;
    }

    public override void draw(RailPainter p, double x, double y) {
        double left = x + 2 * RAIL_R;
        double right = x + w - 2 * RAIL_R;
        for (int i = 0; i < items.size; i++) {
            var it = items.get(i);
            double ty = y + offsets[i];
            if (i == 0) {
                if (skip_arrow && it.w == 0) {
                    p.arrow_line(x, x + w, y, false);
                    continue;
                }
                p.hline(x, left, y);
                p.hline(right, x + w, y);
            } else {
                p.turn(x, y, x + RAIL_R, y + RAIL_R, true);
                p.vline(x + RAIL_R, y + RAIL_R, ty - RAIL_R);
                p.turn(x + RAIL_R, ty - RAIL_R, left, ty, false);
                p.turn(right, ty, right + RAIL_R, ty - RAIL_R, true);
                p.vline(right + RAIL_R, ty - RAIL_R, y + RAIL_R);
                p.turn(right + RAIL_R, y + RAIL_R, x + w, y, false);
            }
            it.draw(p, left, ty);
            p.hline(left + it.w, right, ty);
        }
    }
}

// One or more passes over `item`: a return track above it, arrow leftwards.
internal class RailLoop : RailItem {
    private RailItem item;

    public RailLoop(RailItem item) {
        this.item = item;
        w = item.w + 2 * RAIL_R;
        up = item.up + 6;
        down = item.down;
    }

    public override void draw(RailPainter p, double x, double y) {
        double xs = x + RAIL_R;
        double xe = xs + item.w;
        double top = y - (item.up + 4);
        p.hline(x, xs, y);
        item.draw(p, xs, y);
        p.hline(xe, x + w, y);
        p.dot.spline({ xe, y, xe + RAIL_R, y, xe + RAIL_R, top, xe, top }, "color=\"%s\"".printf(p.line_color));
        p.arrow_line(xs, xe, top, true);
        p.dot.spline({ xs, top, xs - RAIL_R, top, xs - RAIL_R, y, xs, y }, "color=\"%s\"".printf(p.line_color));
    }
}

public class EbnfDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public EbnfDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // Rules are drawn one below the other in source order, each as a
    // railroad track like PlantUML's: the rule name, an open start circle,
    // the expression and an arrow into a filled end dot.
    public string generate_dot(EbnfDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var p = new RailPainter();
        p.line_color = palette.node_text;
        p.text_color = palette.node_text;
        double font_pt = RAIL_FONT * PinnedDotWriter.PX;

        double y = 10.0;
        if (diagram.title != null && diagram.title.length > 0) {
            p.dot.left_text(10, y + 12, diagram.title, RAIL_FONT + 2, true, palette.node_text);
            y += 34;
        }

        foreach (var rule in diagram.rules) {
            p.dot.left_text(10, y + 10, rule.name, RAIL_FONT, true, palette.node_text,
                "id=\"ebnf_rule_%d\"".printf(rule.source_line));
            y += 24;

            var body = build(rule.body, rule.source_line);
            double track = y + body.up + 6;
            double x = 10;
            // start: open circle
            p.dot.node(x + 4, track, 8, 8,
                "shape=circle style=filled fillcolor=\"%s\" color=\"%s\" penwidth=1.5".printf(
                    palette.background, palette.node_text));
            p.hline(x + 8, x + 24, track);
            x += 24;
            body.draw(p, x, track);
            x += body.w;
            p.dot.polyline({ x, track, x + 18, track }, "color=\"%s\" arrowsize=0.5".printf(palette.node_text), true);
            p.dot.node(x + 22, track, 8, 8,
                "shape=circle style=filled fillcolor=\"%s\" color=\"%s\"".printf(palette.node_text, palette.node_text));
            y = track + body.down + 22;
        }
        if (diagram.rules.size == 0) {
            p.dot.node(60, y + 10, 100, 20,
                "shape=plaintext fontsize=%s fontcolor=\"%s\" label=\"(no rules)\"".printf(
                    PinnedDotWriter.num(font_pt), palette.node_text));
        }
        return p.dot.finish(palette.background);
    }

    private RailItem build(EbnfExpr expr, int line) {
        switch (expr.expr_type) {
            case EbnfExprType.TERMINAL:
                return new RailBox(expr.text, true, line);
            case EbnfExprType.NONTERMINAL:
                return new RailBox(expr.text, false, line);
            case EbnfExprType.SPECIAL:
                return new RailBox("? %s ?".printf(expr.text), true, line);
            case EbnfExprType.SEQUENCE: {
                var items = new Gee.ArrayList<RailItem>();
                foreach (var c in expr.children) items.add(build(c, line));
                if (items.size == 0) return new RailEmpty();
                return new RailSequence(items);
            }
            case EbnfExprType.ALTERNATION: {
                var items = new Gee.ArrayList<RailItem>();
                foreach (var c in expr.children) items.add(build(c, line));
                if (items.size == 0) return new RailEmpty();
                if (items.size == 1) return items.get(0);
                return new RailChoice(items);
            }
            case EbnfExprType.OPTIONAL: {
                if (expr.children.size == 0) return new RailEmpty();
                var items = new Gee.ArrayList<RailItem>();
                items.add(new RailEmpty());
                items.add(build(expr.children.get(0), line));
                return new RailChoice(items, true);
            }
            case EbnfExprType.REPETITION: {
                if (expr.children.size == 0) return new RailEmpty();
                var items = new Gee.ArrayList<RailItem>();
                items.add(new RailEmpty());
                items.add(new RailLoop(build(expr.children.get(0), line)));
                return new RailChoice(items, true);
            }
            case EbnfExprType.GROUP:
                if (expr.children.size > 0) return build(expr.children.get(0), line);
                return new RailEmpty();
            default:
                return new RailEmpty();
        }
    }

    public uint8[]? render_to_svg(EbnfDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse EBNF DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout EBNF graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render EBNF diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(EbnfDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(EbnfDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(EbnfDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(EbnfDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
