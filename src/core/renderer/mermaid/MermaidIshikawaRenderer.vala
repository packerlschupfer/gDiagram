/* MermaidIshikawaRenderer.vala — Mermaid `ishikawa` / `ishikawa-beta` renderer
 *
 * Port of mermaid 12.2.0's ishikawaRenderer.ts. A fishbone is a pinned layout
 * with no graph structure for Graphviz to lay out, and two of its parts cannot
 * be expressed as Graphviz nodes at all — the head is a filled quadratic wedge
 * and every bone carries an arrowhead at an arbitrary angle — so the SVG is
 * written directly, the way the Mermaid gantt and gitGraph renderers are.
 * generate_dot() still answers with the equivalent cause tree so `-f dot`
 * keeps working.
 *
 * Geometry, all of it mermaid's:
 *   - the spine runs left from the head at x = 0, y = spineY
 *   - causes alternate above (even index) and below (odd index) the spine, as
 *     82-degree bones whose length is the side's share of the descendant count
 *   - a bone's sub-causes alternate horizontal (even depth) and diagonal (odd
 *     depth), spread evenly along their parent bone
 *   - after each pair of bones the spine start moves left of the leftmost text
 *     drawn so far, so the next pair cannot overlap it
 */
namespace GDiagram {

public class MermaidIshikawaRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidIshikawaRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    /**
     * The cause tree as a DOT graph. The drawing is written as SVG below; this
     * is what the headless `-f dot` output shows.
     */
    public string generate_dot(MermaidIshikawa diagram) {
        var palette = ThemeManager.get_active_palette();
        var dot = new StringBuilder();
        dot.append("digraph ishikawa {\n");
        dot.append("  rankdir=LR\n");
        dot.append_printf("  bgcolor=\"%s\"\n", palette.background);
        dot.append_printf("  node [fontname=\"Sans\" shape=box style=rounded color=\"%s\" fontcolor=\"%s\"]\n",
            palette.node_border, palette.node_text);
        dot.append_printf("  edge [color=\"%s\" dir=back]\n", palette.edge_color);
        if (diagram.root == null) {
            dot.append("}\n");
            return dot.str;
        }
        int counter = 0;
        emit_dot_node(dot, diagram.root, "n0", ref counter, true);
        dot.append("}\n");
        return dot.str;
    }

    private void emit_dot_node(StringBuilder dot, IshikawaNode node, string id,
                               ref int counter, bool is_effect) {
        dot.append_printf("  %s [label=\"%s\"%s]\n", id,
            RenderUtils.escape_label(node.text),
            is_effect ? " shape=box style=\"rounded,bold\"" : "");
        foreach (var child in node.children) {
            counter++;
            string child_id = "n%d".printf(counter);
            emit_dot_node(dot, child, child_id, ref counter, false);
            dot.append_printf("  %s -> %s\n", id, child_id);
        }
    }

    public uint8[]? render_to_svg(MermaidIshikawa diagram) {
        var layout = new MermaidIshikawaLayout(diagram, ThemeManager.get_active_palette());
        string svg = layout.build();
        regions.clear();
        foreach (var r in layout.regions) regions.add(r);
        return svg.data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidIshikawa diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(MermaidIshikawa diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidIshikawa diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidIshikawa diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

/** Where a text block sits vertically relative to its anchor y. */
private enum IshikawaBaseline {
    MIDDLE,     // .ishikawa-label.cause / .align — centred on y
    ABOVE,      // .ishikawa-label.up — baselines on y, so the text is above it
    BELOW       // .ishikawa-label.down — hanging, so the text is below y
}

/** Computes the fishbone geometry and writes the SVG. */
public class MermaidIshikawaLayout : Object {
    // mermaid's ishikawaRenderer constants.
    private const double SPINE_BASE_LENGTH = 250.0;
    private const double BONE_STUB = 30.0;
    private const double BONE_BASE = 60.0;
    private const double BONE_PER_CHILD = 5.0;
    private const double ANGLE_DEG = 82.0;
    private const double PADDING = 20.0;
    // themeVariables.fontSize is 16px; .ishikawa-head-label overrides to 14px,
    // while the head's line spacing still comes from the 16px base.
    private const double FONT = 16.0;
    private const double HEAD_FONT = 14.0;
    private const double LINE_RATIO = 1.05;
    // getBBox().height of one text line as a multiple of the font size,
    // measured from Mermaid's own output: a cause label's box is 21.015625
    // high at 16px, and 21.015625 - 4 (the box padding) = 1.0635 em.
    private const double TEXT_HEIGHT_RATIO = 1.0635;
    private const double STROKE_SPINE = 2.0;
    private const double STROKE_SUB = 1.0;
    private const int CAUSE_WRAP = 15;

    private MermaidIshikawa d;
    private Palette palette;
    private double cos_a;
    private double sin_a;

    private StringBuilder sb_lines;
    private StringBuilder sb_boxes;
    private StringBuilder sb_labels;

    private double min_x;
    private double min_y;
    private double max_x;
    private double max_y;
    private bool any_bounds;

    // The leftmost text drawn in the pair currently being laid out.
    private double pair_text_left;

    public Gee.ArrayList<ElementRegion> regions { get; private set; }

    public MermaidIshikawaLayout(MermaidIshikawa diagram, Palette palette) {
        this.d = diagram;
        this.palette = palette;
        double a = ANGLE_DEG * Math.PI / 180.0;
        this.cos_a = Math.cos(a);
        this.sin_a = Math.sin(a);
        this.regions = new Gee.ArrayList<ElementRegion>();
    }

    // ==================== number / text helpers ====================

    /** C-locale number for an SVG attribute (never LC_NUMERIC's comma). */
    private static string f(double v) {
        string s = "%.3f".printf(v).replace(",", ".");
        while (s.contains(".") && (s.has_suffix("0") || s.has_suffix("."))) {
            s = s.substring(0, s.length - 1);
            if (!s.contains(".")) break;
        }
        return s;
    }

    private static string esc(string s) { return Markup.escape_text(s); }

    private static double text_w(string s, double size, bool bold = false) {
        return GanttText.width(s, size, bold, "Sans");
    }

    /** `<br>` and newlines split a label, as mermaid's splitLines does. */
    private static string[] split_lines(string text) {
        return Regex.split_simple("<br\\s*/?>|\n", text, RegexCompileFlags.CASELESS);
    }

    /** mermaid's wrapText: greedy word wrap, a single long word kept whole. */
    private static string wrap_text(string text, int max_chars) {
        if (text.char_count() <= max_chars) return text;
        var lines = new Gee.ArrayList<string>();
        foreach (string word in Regex.split_simple("\\s+", text)) {
            if (word.length == 0) continue;
            if (lines.size > 0 &&
                lines.get(lines.size - 1).char_count() + 1 + word.char_count() <= max_chars) {
                lines.set(lines.size - 1, lines.get(lines.size - 1) + " " + word);
            } else {
                lines.add(word);
            }
        }
        var sb = new StringBuilder();
        for (int i = 0; i < lines.size; i++) {
            if (i > 0) sb.append_c('\n');
            sb.append(lines.get(i));
        }
        return sb.str;
    }

    private double block_width(string[] lines, double size, bool bold) {
        double w = 0;
        foreach (string line in lines) w = double.max(w, text_w(line, size, bold));
        return w;
    }

    private double block_height(int line_count, double size) {
        return (line_count - 1) * FONT * LINE_RATIO + size * TEXT_HEIGHT_RATIO;
    }

    // ==================== bounds ====================

    private void track(double x, double y) {
        if (!any_bounds) {
            min_x = x; max_x = x; min_y = y; max_y = y;
            any_bounds = true;
            return;
        }
        if (x < min_x) min_x = x;
        if (x > max_x) max_x = x;
        if (y < min_y) min_y = y;
        if (y > max_y) max_y = y;
    }

    private void track_rect(double x, double y, double w, double h) {
        track(x, y);
        track(x + w, y + h);
    }

    // ==================== primitives ====================

    private void line(double x1, double y1, double x2, double y2, double stroke, string cls) {
        sb_lines.append_printf(
            "<line class=\"%s\" x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"%s\" fill=\"none\"/>\n",
            cls, f(x1), f(y1), f(x2), f(y2), palette.edge_color, f(stroke));
        track(x1, y1);
        track(x2, y2);
    }

    /**
     * The arrowhead mermaid gets from `marker-start`: the tip sits on the
     * line's start point and the triangle points away from the line, into the
     * spine. markerUnits is strokeWidth, so a 6x6 marker over a 10x10 viewBox
     * is 6 * stroke long and 6 * stroke wide.
     */
    private void arrow_head(double x, double y, double dx, double dy, double stroke) {
        double len = Math.sqrt(dx * dx + dy * dy);
        if (len <= 0) return;
        double ux = dx / len, uy = dy / len;
        double back = 6.0 * stroke, half = 3.0 * stroke;
        double bx = x - ux * back, by = y - uy * back;
        double px = -uy * half, py = ux * half;
        sb_lines.append_printf(
            "<path class=\"ishikawa-arrow\" d=\"M %s %s L %s %s L %s %s Z\" fill=\"%s\"/>\n",
            f(x), f(y), f(bx + px), f(by + py), f(bx - px), f(by - py), palette.edge_color);
    }

    /**
     * A text block anchored at (x, y). `anchor` is 's' (start), 'm' (middle) or
     * 'e' (end). Returns the block's bounding box through the out parameters.
     */
    // Bounding box of the text block written last, for the callers that need it.
    private double last_x;
    private double last_y;
    private double last_w;
    private double last_h;

    private void text_block(string text, double x, double y, char anchor,
                            IshikawaBaseline baseline, double size, string cls,
                            bool bold) {
        double bx, by, bw, bh;
        string[] lines = split_lines(text);
        double lh = FONT * LINE_RATIO;
        bw = block_width(lines, size, bold);
        bh = block_height(lines.length, size);
        bx = anchor == 'm' ? x - bw / 2 : (anchor == 'e' ? x - bw : x);
        double shift = baseline == IshikawaBaseline.MIDDLE ? size * 0.35
                     : (baseline == IshikawaBaseline.BELOW ? size * 0.8 : 0.0);
        double first = y - (lines.length - 1) * lh / 2 + shift;
        by = y - bh / 2;
        if (baseline == IshikawaBaseline.ABOVE) by = y - bh + size * 0.25;
        else if (baseline == IshikawaBaseline.BELOW) by = y - size * 0.25;

        string align = anchor == 'm' ? "middle" : (anchor == 'e' ? "end" : "start");
        sb_labels.append_printf(
            "<text class=\"%s\" x=\"%s\" y=\"%s\" text-anchor=\"%s\" font-size=\"%s\" fill=\"%s\"%s>",
            cls, f(x), f(first), align, f(size), palette.node_text,
            bold ? " font-weight=\"600\"" : "");
        for (int i = 0; i < lines.length; i++) {
            sb_labels.append_printf("<tspan x=\"%s\" y=\"%s\">%s</tspan>",
                f(x), f(first + i * lh), esc(lines[i]));
        }
        sb_labels.append("</text>\n");
        track_rect(bx, by, bw, bh);
        if (bx < pair_text_left) pair_text_left = bx;
        last_x = bx; last_y = by; last_w = bw; last_h = bh;
    }

    // ==================== the drawing ====================

    public string build() {
        sb_lines = new StringBuilder();
        sb_boxes = new StringBuilder();
        sb_labels = new StringBuilder();
        regions.clear();
        any_bounds = false;
        pair_text_left = double.MAX;

        if (d.root == null) {
            // mermaid draws nothing at all for a bare `ishikawa` keyword; a
            // blank page of the fallback size beats the 1x1 image a zero-sized
            // view box would export to.
            return finish();
        }

        var causes = d.root.children;
        double spine_x = 0;
        double spine_y = SPINE_BASE_LENGTH;

        double upper_len = SPINE_BASE_LENGTH;
        double lower_len = SPINE_BASE_LENGTH;

        if (causes.size > 0) {
            int upper_total = 0, upper_max = 0, lower_total = 0, lower_max = 0;
            for (int i = 0; i < causes.size; i++) {
                int n = causes.get(i).descendant_count();
                if (i % 2 == 0) {
                    upper_total += n;
                    upper_max = int.max(upper_max, n);
                } else {
                    lower_total += n;
                    lower_max = int.max(lower_max, n);
                }
            }
            int descendant_total = upper_total + lower_total;
            if (descendant_total > 0) {
                double pool = SPINE_BASE_LENGTH * 2;
                double min_len = SPINE_BASE_LENGTH * 0.3;
                upper_len = double.max(min_len, pool * ((double) upper_total / descendant_total));
                lower_len = double.max(min_len, pool * ((double) lower_total / descendant_total));
            }
            double min_spacing = FONT * 2;
            upper_len = double.max(upper_len, upper_max * min_spacing);
            lower_len = double.max(lower_len, lower_max * min_spacing);
            spine_y = double.max(upper_len, SPINE_BASE_LENGTH);
        }

        draw_head(0, spine_y, d.root.text);

        if (causes.size == 0) {
            line(spine_x, spine_y, spine_x, spine_y, STROKE_SPINE, "ishikawa-spine");
            return finish();
        }

        spine_x -= 20;

        int pair_count = (causes.size + 1) / 2;
        for (int p = 0; p < pair_count; p++) {
            pair_text_left = double.MAX;
            if (p * 2 < causes.size) {
                draw_branch(causes.get(p * 2), spine_x, spine_y, -1, upper_len);
            }
            if (p * 2 + 1 < causes.size) {
                draw_branch(causes.get(p * 2 + 1), spine_x, spine_y, 1, lower_len);
            }
            // The next pair starts left of everything this pair wrote.
            if (pair_text_left < double.MAX) spine_x = pair_text_left;
        }

        line(spine_x, spine_y, 0, spine_y, STROKE_SPINE, "ishikawa-spine");
        return finish();
    }

    /** The fish head: a wedge with a straight left edge and a bulging right one. */
    private void draw_head(double x, double y, string label) {
        int max_chars = int.max(6, (int) Math.floor(110.0 / (FONT * 0.6)));
        string wrapped = wrap_text(label, max_chars);
        string[] lines = split_lines(wrapped);
        double tw = block_width(lines, HEAD_FONT, true);
        double th = block_height(lines.length, HEAD_FONT);

        double w = double.max(60.0, tw + 6.0);
        double h = double.max(40.0, th * 2 + 40.0);

        sb_boxes.append_printf(
            "<path class=\"ishikawa-head\" d=\"M %s %s L %s %s Q %s %s %s %s Z\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n",
            f(x), f(y - h / 2), f(x), f(y + h / 2), f(x + w * 2.4), f(y), f(x), f(y - h / 2),
            palette.node_fill, palette.edge_color, f(STROKE_SPINE));
        // A quadratic from (x, y+h/2) to (x, y-h/2) peaks at x + w * 1.2.
        track_rect(x, y - h / 2, w * 1.2, h);

        text_block(wrapped, x + (w - tw) / 2 + 3, y, 's', IshikawaBaseline.MIDDLE,
            HEAD_FONT, "ishikawa-head-label", true);
        add_region("ishikawa_effect", d.root.source_line, x, y - h / 2, w * 1.2, h);
    }

    /** One main bone plus every sub-bone hanging off it. */
    private void draw_branch(IshikawaNode node, double start_x, double start_y,
                             int direction, double length) {
        var children = node.children;
        double line_len = length * (children.size > 0 ? 1.0 : 0.2);
        double dx = -cos_a * line_len;
        double dy = sin_a * line_len * direction;
        double end_x = start_x + dx;
        double end_y = start_y + dy;

        line(start_x, start_y, end_x, end_y, STROKE_SPINE, "ishikawa-branch");
        arrow_head(start_x, start_y, start_x - end_x, start_y - end_y, STROKE_SPINE);
        draw_cause_label(node, end_x, end_y, direction);

        if (children.size == 0) return;

        var entries = new Gee.ArrayList<Entry>();
        var y_order = new Gee.ArrayList<int>();
        flatten(children, -1, 2, direction, entries, y_order);

        int count = entries.size;
        var ys = new double[count];
        for (int slot = 0; slot < y_order.size; slot++) {
            ys[y_order.get(slot)] = start_y + dy * ((double) (slot + 1) / (count + 1));
        }

        var bones = new Gee.HashMap<int, Bone>();
        bones.set(-1, new Bone(start_x, start_y, end_x, end_y, children.size));

        double diagonal_x = -cos_a;
        double diagonal_y = sin_a * direction;
        var odd_baseline = direction < 0 ? IshikawaBaseline.ABOVE : IshikawaBaseline.BELOW;
        string odd_class = direction < 0 ? "ishikawa-label up" : "ishikawa-label down";

        for (int i = 0; i < count; i++) {
            var e = entries.get(i);
            double y = ys[i];
            var par = bones.get(e.parent_index);
            double bx0, by0, bx1;

            if (e.depth % 2 == 0) {
                // Horizontal bone: meets the parent's diagonal at this y and
                // runs left.
                double dy_p = par.y1 - par.y0;
                double t = dy_p != 0 ? (y - par.y0) / dy_p : 0.5;
                bx0 = lerp(par.x0, par.x1, t);
                by0 = y;
                bx1 = bx0 - (e.child_count > 0
                    ? BONE_BASE + e.child_count * BONE_PER_CHILD
                    : BONE_STUB);
                line(bx0, y, bx1, y, STROKE_SUB, "ishikawa-sub-branch");
                arrow_head(bx0, y, 1, 0, STROKE_SUB);
                emit_sub_label(e, bx1, y, IshikawaBaseline.MIDDLE, "ishikawa-label align");
            } else {
                // Diagonal bone: starts at an even share of the parent's
                // horizontal bone and runs out to this y at the bone angle.
                int k = par.children_drawn++;
                bx0 = lerp(par.x0, par.x1,
                    (double) (par.child_count - k) / (par.child_count + 1));
                by0 = par.y0;
                bx1 = bx0 + diagonal_x * ((y - by0) / diagonal_y);
                line(bx0, by0, bx1, y, STROKE_SUB, "ishikawa-sub-branch");
                arrow_head(bx0, by0, bx0 - bx1, by0 - y, STROKE_SUB);
                emit_sub_label(e, bx1, y, odd_baseline, odd_class);
            }

            if (e.child_count > 0) {
                bones.set(i, new Bone(bx0, by0, bx1, y, e.child_count));
            }
        }
    }

    private void emit_sub_label(Entry e, double x, double y,
                                IshikawaBaseline baseline, string cls) {
        text_block(e.text, x, y, 'e', baseline, FONT, cls, false);
        add_region("ishikawa_cause_%d".printf(e.source_line), e.source_line,
            last_x, last_y, last_w, last_h);
    }

    /** The boxed label at the outer end of a main bone. */
    private void draw_cause_label(IshikawaNode node, double x, double y, int direction) {
        string[] lines = split_lines(node.text);
        double tw = block_width(lines, FONT, false);
        double th = block_height(lines.length, FONT);
        double cy = y + 11.0 * direction;
        double rx = x - tw / 2 - 20;
        double ry = cy - th / 2 - 2;
        double rw = tw + 40;
        double rh = th + 4;

        sb_boxes.append_printf(
            "<rect class=\"ishikawa-label-box\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n",
            f(rx), f(ry), f(rw), f(rh), palette.node_fill, palette.edge_color, f(STROKE_SPINE));
        track_rect(rx, ry, rw, rh);

        text_block(node.text, x, cy, 'm', IshikawaBaseline.MIDDLE, FONT,
            "ishikawa-label cause", false);
        add_region("ishikawa_cause_%d".printf(node.source_line), node.source_line,
            rx, ry, rw, rh);
    }

    private static double lerp(double a, double b, double t) { return a + (b - a) * t; }

    private class Entry : Object {
        public int depth;
        public string text;
        public int parent_index;
        public int child_count;
        public int source_line;
    }

    private class Bone : Object {
        public double x0;
        public double y0;
        public double x1;
        public double y1;
        public int child_count;
        public int children_drawn;
        public Bone(double x0, double y0, double x1, double y1, int child_count) {
            this.x0 = x0; this.y0 = y0; this.x1 = x1; this.y1 = y1;
            this.child_count = child_count;
            this.children_drawn = 0;
        }
    }

    /**
     * Flattens the sub-causes into draw order plus a separate y order: even
     * depths are laid out pre-order (nearest the spine first), odd depths
     * post-order, which keeps a diagonal bone inside its parent's wedge.
     */
    private void flatten(Gee.ArrayList<IshikawaNode> nodes, int parent_index, int depth,
                         int direction, Gee.ArrayList<Entry> entries,
                         Gee.ArrayList<int> y_order) {
        var ordered = new Gee.ArrayList<IshikawaNode>();
        ordered.add_all(nodes);
        if (direction == -1) {
            var reversed = new Gee.ArrayList<IshikawaNode>();
            for (int i = ordered.size - 1; i >= 0; i--) reversed.add(ordered.get(i));
            ordered = reversed;
        }
        foreach (var child in ordered) {
            int idx = entries.size;
            var e = new Entry();
            e.depth = depth;
            e.text = wrap_text(child.text, CAUSE_WRAP);
            e.parent_index = parent_index;
            e.child_count = child.children.size;
            e.source_line = child.source_line;
            entries.add(e);
            if (depth % 2 == 0) {
                y_order.add(idx);
                if (child.children.size > 0) {
                    flatten(child.children, idx, depth + 1, direction, entries, y_order);
                }
            } else {
                if (child.children.size > 0) {
                    flatten(child.children, idx, depth + 1, direction, entries, y_order);
                }
                y_order.add(idx);
            }
        }
    }

    private void add_region(string name, int source_line, double x, double y,
                            double w, double h) {
        regions.add(new ElementRegion(name, source_line, x, y, w, h));
    }

    // ==================== document ====================

    private string finish() {
        if (!any_bounds) {
            min_x = 0; min_y = 0; max_x = 100; max_y = 50;
        }
        double vx = min_x - PADDING;
        double vy = min_y - PADDING;
        double w = Math.ceil(max_x - min_x + 2 * PADDING);
        double h = Math.ceil(max_y - min_y + 2 * PADDING);
        // Regions are in image pixels: shift them by the view box origin.
        foreach (var r in regions) {
            r.x -= vx;
            r.y -= vy;
        }
        return document(vx, vy, w, h);
    }

    private string document(double vx, double vy, double w, double h) {
        var doc = new StringBuilder();
        doc.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        doc.append_printf(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%spx\" height=\"%spx\" viewBox=\"%s %s %s %s\">\n",
            f(w), f(h), f(vx), f(vy), f(w), f(h));
        doc.append_printf("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\"/>\n",
            f(vx), f(vy), f(w), f(h), palette.background);
        doc.append("<g class=\"ishikawa\" font-family=\"Sans\">\n");
        if (sb_lines != null) doc.append(sb_lines.str);
        if (sb_boxes != null) doc.append(sb_boxes.str);
        if (sb_labels != null) doc.append(sb_labels.str);
        doc.append("</g>\n</svg>\n");
        return doc.str;
    }
}

}
