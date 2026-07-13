namespace GDiagram {

/**
 * Mermaid 12.2.0 `eventmodeling`.
 *
 * The geometry is fully determined — mermaid's own renderer appends absolutely
 * positioned rects and paths with no layout engine involved — so this renderer
 * writes the SVG directly, as the Mermaid gantt and gitgraph renderers already do
 * here. `generate_dot()` still returns a small valid summary graph so `-f dot`
 * works.
 *
 * `EmLayout` below is a port of `diagrams/eventmodeling/db.ts` (the swimlane and
 * box placement, which mermaid models as a decide/evolve fold) plus
 * `renderer.ts` (the drawing). Every constant and formula is mermaid's.
 */
public class MermaidEventModelingRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidEventModelingRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(MermaidEventModeling diagram) {
        var palette = ThemeManager.get_active_palette();
        var dot = new StringBuilder();
        dot.append("digraph G {\n");
        dot.append("  rankdir=LR;\n");
        dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
        dot.append("  node [fontname=\"Sans\", fontsize=10, shape=box, style=\"rounded,filled\", color=\"%s\", fontcolor=\"%s\"];\n".printf(
            palette.node_border, palette.node_text));
        dot.append("  edge [fontname=\"Sans\", color=\"%s\"];\n".printf(palette.edge_color));
        if (diagram.title != null && diagram.title.length > 0) {
            dot.append_printf("  label=\"%s\";\n  labelloc=t;\n", RenderUtils.escape_label(diagram.title));
        }

        var ids = new Gee.HashMap<string, string>();
        foreach (var f in diagram.frames) {
            string id = "f%s".printf(f.name);
            ids.set(f.name, id);
            dot.append_printf("  %s [label=\"%s\\n(%s)\", fillcolor=\"%s\"];\n",
                id, RenderUtils.escape_label(f.entity_name),
                RenderUtils.escape_label(f.kind.keyword()),
                normalize_color(f.kind.fill_color()));
        }
        var layout = new EmLayout(diagram);
        foreach (var rel in layout.relations) {
            dot.append_printf("  %s -> %s;\n",
                ids.get(rel.source.frame.name), ids.get(rel.target.frame.name));
        }
        dot.append("}\n");
        return dot.str;
    }

    /**
     * Graphviz takes a `#` prefix only for hex codes, never for named colours.
     * These are all hex, but route them through the house check anyway so a theme
     * override that supplies a name still produces valid DOT.
     */
    private static string normalize_color(string c) {
        string s = c.strip();
        if (!s.has_prefix("#")) return s;
        string body = s.substring(1);
        bool hex = body.length == 3 || body.length == 6 || body.length == 8;
        if (hex) {
            for (int i = 0; i < body.length; i++) {
                if (!body[i].isxdigit()) { hex = false; break; }
            }
        }
        return hex ? s : body;
    }

    public uint8[]? render_to_svg(MermaidEventModeling diagram) {
        var layout = new EmLayout(diagram);
        string svg = layout.build(ThemeManager.get_active_palette());
        regions.clear();
        foreach (var r in layout.regions) regions.add(r);
        return svg.data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidEventModeling diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(MermaidEventModeling diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidEventModeling diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidEventModeling diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

/** One swimlane. Boxes hold a reference, because its `y` is re-flowed as lanes appear. */
public class EmSwimlane : Object {
    public int index;
    public string label;
    /** The right edge of the last box placed in this lane. */
    public double r = 0;
    public double y = 0;
    public double height;
    public double max_height;

    public EmSwimlane(int index, string label, double min_height, double gap) {
        this.index = index;
        this.label = label;
        this.y = index * min_height + gap;
        this.height = min_height;
        this.max_height = min_height;
    }
}

/** One frame box. */
public class EmBox : Object {
    public EmFrame frame;
    public EmSwimlane swimlane;
    public double x;
    public double r;
    public double width;
    public double height;
    /** The rendered label lines, already escaped-safe plain text. */
    public Gee.ArrayList<string> name_lines;
    public Gee.ArrayList<string> data_lines;

    public EmBox(EmFrame frame, EmSwimlane swimlane) {
        this.frame = frame;
        this.swimlane = swimlane;
        this.name_lines = new Gee.ArrayList<string>();
        this.data_lines = new Gee.ArrayList<string>();
    }

    /** `renderer.ts`: the box's top is its lane's `y` plus the lane padding. */
    public double top(double swimlane_padding) {
        return swimlane.y + swimlane_padding;
    }
}

public class EmRelation : Object {
    public EmBox source;
    public EmBox target;

    public EmRelation(EmBox source, EmBox target) {
        this.source = source;
        this.target = target;
    }
}

/**
 * Geometry and SVG output. Every constant is `db.ts`'s `diagramProps`.
 */
public class EmLayout : Object {
    public const double SWIMLANE_MIN_HEIGHT = 70;
    public const double SWIMLANE_PADDING = 15;
    public const double SWIMLANE_GAP = 10;
    public const double BOX_PADDING = 10;
    public const double BOX_OVERLAP = 90;
    public const double BOX_MIN_WIDTH = 80;
    public const double BOX_MAX_WIDTH = 450;
    public const double BOX_MIN_HEIGHT = 80;
    public const double BOX_MAX_HEIGHT = 750;
    public const double CONTENT_START_X = 250;
    public const double TEXT_MAX_WIDTH = 450 - 2 * 10;
    public const double BOX_TEXT_PADDING = 10;
    public const double FONT_SIZE = 16;
    /** `renderer.ts` draws the label 10px below the box top, then centres it. */
    public const double TEXT_TOP_OFFSET = 10;
    /** Attached data is drawn as mermaid's `<code>` block: smaller and monospaced. */
    public const double DATA_FONT_SIZE = 13;
    public const double DIAGRAM_PADDING = 30;

    private MermaidEventModeling d;
    public Gee.ArrayList<EmBox> boxes { get; private set; }
    public Gee.ArrayList<EmRelation> relations { get; private set; }
    public Gee.ArrayList<EmSwimlane> lanes { get; private set; }
    public Gee.ArrayList<ElementRegion> regions { get; private set; }
    public double max_r { get; private set; }

    private Gee.HashMap<int, EmSwimlane> lane_by_index;
    private int? previous_lane_index = null;

    public EmLayout(MermaidEventModeling diagram) {
        this.d = diagram;
        this.boxes = new Gee.ArrayList<EmBox>();
        this.relations = new Gee.ArrayList<EmRelation>();
        this.lanes = new Gee.ArrayList<EmSwimlane>();
        this.regions = new Gee.ArrayList<ElementRegion>();
        this.lane_by_index = new Gee.HashMap<int, EmSwimlane>();
        this.max_r = 0;
        build_layout();
    }

    // ---- layout ----

    private void build_layout() {
        foreach (var frame in d.frames) {
            place_frame(frame);
            place_relations(frame);
        }
        sort_lanes();
    }

    /**
     * `evolveFramePositioned`. The order matters: `maxR` is taken over the lane
     * right-edges as they stand *before* this box updates its own lane.
     */
    private void place_frame(EmFrame frame) {
        var lane = lane_for(frame);
        var last_box = boxes.size > 0 ? boxes[boxes.size - 1] : null;
        EmSwimlane? previous_lane = previous_lane_index != null
            ? lane_by_index.get(previous_lane_index) : null;

        var box = new EmBox(frame, lane);
        measure(frame, box, out box.width, out box.height);

        box.x = calculate_x(lane, previous_lane, last_box);
        box.r = box.x + box.width + BOX_PADDING;

        double maxr = box.r;
        foreach (var l in lanes) {
            if (l.r > maxr) maxr = l.r;
        }
        max_r = maxr;

        lane.r = box.x + box.width;
        lane.max_height = double.max(lane.max_height, box.height);
        lane.height = double.max(SWIMLANE_MIN_HEIGHT, lane.max_height) + 2 * SWIMLANE_PADDING;

        boxes.add(box);
        previous_lane_index = lane.index;

        reflow_lanes();
    }

    /** `calculateX`. */
    private double calculate_x(EmSwimlane lane, EmSwimlane? previous_lane, EmBox? last_box) {
        if (previous_lane == null) return CONTENT_START_X;
        // `swimlane.r` is falsy (0) for a lane that has no box yet, so a brand new
        // lane falls through to the overlap rule even when it is "the same" lane.
        if (previous_lane.index == lane.index && lane.r != 0) {
            return lane.r + BOX_PADDING;
        }
        if (last_box == null) return CONTENT_START_X;
        return last_box.r - BOX_OVERLAP + BOX_PADDING;
    }

    /**
     * `calculateSwimlaneProps`, ported as-is — including the behaviour that makes a
     * *namespaced* frame take a brand-new lane every time.
     *
     * mermaid computes the lane's label from the namespace but never writes the
     * namespace onto the Swimlane record it then creates, so its own
     * `findSwimlaneByNamespace` can never match and every namespaced frame
     * allocates the next free index inside its band. Verified against mermaid
     * 12.2.0: seven `Shop.*` frames render as seven lanes labelled "UI/A: Shop",
     * "C/RM: Shop", "Stream: Shop" — grouped by band but one lane per frame.
     *
     * This is ported rather than "fixed" because the intended behaviour is not
     * recoverable from the source: the lookup is not restricted to the frame's own
     * band, so making it match would collapse UI, command and event frames of one
     * namespace into a single lane, which is no more plausible than the current
     * result. Frames with no namespace — the common case — land on the band base
     * index and group correctly.
     */
    private EmSwimlane lane_for(EmFrame frame) {
        int base_index = frame.kind.band_base();
        int index;
        string label;

        if (frame.ns != null && frame.ns.length > 0) {
            index = next_free_index(base_index, frame.kind.band_limit());
            label = frame.kind.band_prefix() + frame.ns;
        } else {
            index = base_index;
            label = frame.kind.band_label();
        }

        var existing = lane_by_index.get(index);
        if (existing != null) return existing;

        var lane = new EmSwimlane(index, label, SWIMLANE_MIN_HEIGHT, SWIMLANE_GAP);
        lane_by_index.set(index, lane);
        lanes.add(lane);
        return lane;
    }

    /** `findNextAvailableIndex`: max of the taken indices strictly inside the band, + 1. */
    private int next_free_index(int boundary_min, int boundary_max) {
        int best = boundary_min;
        foreach (var l in lanes) {
            if (l.index > boundary_min && l.index < boundary_max && l.index > best) {
                best = l.index;
            }
        }
        return best + 1;
    }

    /**
     * The lane `y` re-flow mermaid runs after every box: the first lane sits at 0 and
     * each next one below the previous, in index order.
     */
    private void reflow_lanes() {
        var sorted = sorted_lanes();
        if (sorted.size == 0) return;
        sorted[0].y = 0;
        for (int i = 1; i < sorted.size; i++) {
            sorted[i].y = sorted[i - 1].y + sorted[i - 1].height + SWIMLANE_GAP;
        }
    }

    private Gee.ArrayList<EmSwimlane> sorted_lanes() {
        var sorted = new Gee.ArrayList<EmSwimlane>();
        sorted.add_all(lanes);
        sorted.sort((a, b) => {
            return a.index < b.index ? -1 : (a.index > b.index ? 1 : 0);
        });
        return sorted;
    }

    private void sort_lanes() {
        var sorted = sorted_lanes();
        lanes.clear();
        lanes.add_all(sorted);
    }

    /**
     * `decidePositionRelation`: an explicit `->>` source, else the nearest earlier
     * frame in a *different* lane. The first frame gets none, and a reset frame
     * gets none unless it names its sources.
     */
    private void place_relations(EmFrame frame) {
        var target = find_box(frame.name);
        if (target == null) return;

        if (frame.index == 0 && frame.source_frames.size == 0) return;

        if (frame.source_frames.size > 0) {
            foreach (string src in frame.source_frames) {
                var source = find_box(src);
                if (source != null) relations.add(new EmRelation(source, target));
            }
            return;
        }

        if (frame.is_reset) return;

        var source = find_box_by_line_index(target.swimlane.index, frame.index - 1);
        if (source != null) relations.add(new EmRelation(source, target));
    }

    private EmBox? find_box(string frame_name) {
        foreach (var b in boxes) {
            if (b.frame.name == frame_name) return b;
        }
        return null;
    }

    /** `findBoxByLineIndex`: walk back from `line_index` for a box in another lane. */
    private EmBox? find_box_by_line_index(int target_lane, int line_index) {
        if (line_index < 0) return null;
        for (int i = int.min(line_index, boxes.size - 1); i >= 0; i--) {
            if (boxes[i].swimlane.index != target_lane) return boxes[i];
        }
        return null;
    }

    // ---- text ----

    /**
     * `calculateTextProps` + the clamping in `evolveFramePositioned`.
     *
     * mermaid builds an HTML string (`<b>name</b>`, plus a `<code>` block when the
     * frame carries data) and hands that *whole string, markup included*, to its
     * text measurer — so the `<b>` and `</b>` characters are measured as if they
     * were visible. That is not an accident we can drop: it is what makes a box
     * ~60px wider than its visible label, and reproducing it is what keeps the box
     * widths in step with mermaid's. Confirmed by solving mermaid's own output:
     * every box width in a reference render is consistent with the tagged string
     * and none with the bare name.
     */
    private void measure(EmFrame frame, EmBox box, out double width, out double height) {
        string name = frame.entity_name;
        foreach (string piece in wrap_label(name, TEXT_MAX_WIDTH)) {
            box.name_lines.add(piece);
        }

        string? data = data_text(frame);
        if (data != null) {
            foreach (string piece in data.split("\n")) {
                string trimmed = piece.chomp();
                if (trimmed.strip().length == 0) continue;
                box.data_lines.add(trimmed);
            }
        }

        // The measured string, exactly as mermaid composes it.
        double text_w = 0;
        double text_h = 0;
        var measured = new Gee.ArrayList<string>();
        if (box.name_lines.size > 0) {
            var first = new StringBuilder();
            first.append("<b>").append(box.name_lines[0]);
            if (box.name_lines.size == 1) first.append("</b>");
            measured.add(first.str);
            for (int i = 1; i < box.name_lines.size; i++) {
                measured.add(i == box.name_lines.size - 1
                    ? box.name_lines[i] + "</b>" : box.name_lines[i]);
            }
        }
        foreach (string l in measured) {
            double w = EmText.width(l, FONT_SIZE, true);
            if (w > text_w) text_w = w;
            text_h += EmText.line_height(FONT_SIZE);
        }
        if (measured.size == 0) text_h = EmText.line_height(FONT_SIZE);

        /*
         * The data block is measured at the size and family it is actually drawn in,
         * and mermaid's `calculatedWidthFix` — "a temporal workaround until a more
         * complex dimension calculation is in place", which divides the measured
         * width by three whenever data is rendered — is deliberately not ported.
         *
         * That divisor only makes sense alongside the thing it compensates for:
         * mermaid measures the literal string `<code style="text-align: left;
         * display: block;max-width:430px">…</code>`, markup included, so a third of
         * that is roughly the visible text. Keeping the divisor without the markup
         * made every data box a third of the width its own text needs, and the text
         * spilled out of the box. Measuring what is drawn is both simpler and right;
         * the cost is that a data box here is narrower than mermaid's (which is
         * wider than its content needs).
         */
        foreach (string l in box.data_lines) {
            double w = EmText.width(l, DATA_FONT_SIZE, false, "monospace");
            if (w > text_w) text_w = w;
            text_h += EmText.line_height(DATA_FONT_SIZE);
        }

        double w0 = text_w + 2 * BOX_TEXT_PADDING;
        double h0 = text_h + 2 * BOX_TEXT_PADDING;

        width = clamp(w0, BOX_MIN_WIDTH, BOX_MAX_WIDTH) + 2 * BOX_PADDING;
        height = clamp(h0, BOX_MIN_HEIGHT, BOX_MAX_HEIGHT) + 2 * BOX_PADDING;
    }

    private static double clamp(double v, double lo, double hi) {
        return double.max(lo, double.min(hi, v));
    }

    /**
     * The data mermaid renders inside a box: an inline `{ … }` value with its outer
     * braces trimmed, or the body of the `data` entity a `[[ref]]` names.
     */
    private string? data_text(EmFrame frame) {
        if (frame.data_inline != null) {
            string s = frame.data_inline;
            int open = s.index_of("{");
            if (open >= 0) s = s.substring(open + 1);
            int close = s.last_index_of("}");
            if (close >= 0) s = s.substring(0, close);
            return s.strip().length > 0 ? s : null;
        }
        if (frame.data_reference != null) {
            var entity = d.find_data(frame.data_reference);
            if (entity != null && entity.body.strip().length > 0) return entity.body;
        }
        return null;
    }

    /** `wrapLabel`: greedy word wrap at a pixel width. */
    private static Gee.ArrayList<string> wrap_label(string text, double max_width) {
        var out_lines = new Gee.ArrayList<string>();
        if (text.length == 0) {
            out_lines.add("");
            return out_lines;
        }
        var line = new StringBuilder();
        foreach (string word in text.split(" ")) {
            string candidate = line.len == 0 ? word : line.str + " " + word;
            if (EmText.width(candidate, FONT_SIZE, true) > max_width && line.len > 0) {
                out_lines.add(line.str);
                line = new StringBuilder();
                line.append(word);
            } else {
                line.erase();
                line.append(candidate);
            }
        }
        if (line.len > 0) out_lines.add(line.str);
        if (out_lines.size == 0) out_lines.add("");
        return out_lines;
    }

    // ---- SVG ----

    /**
     * Writes the drawing. Numbers go through `f()`, never `printf("%f")`:
     * a GUI process has called setlocale(), so "%f" on a German desktop emits
     * "0,8333" and the SVG parser rejects it.
     */
    public string build(Palette palette) {
        double content_w = max_r + SWIMLANE_PADDING;
        double content_h = 0;
        foreach (var l in lanes) {
            double bottom = l.y + l.height;
            if (bottom > content_h) content_h = bottom;
        }
        if (content_w < 1) content_w = 1;
        if (content_h < 1) content_h = 1;

        double title_h = (d.title != null && d.title.length > 0) ? 36 : 0;
        double width = content_w + 2 * DIAGRAM_PADDING;
        double height = content_h + 2 * DIAGRAM_PADDING + title_h;

        // Keep the page inside what the preview can paint; RenderUtils clamps too,
        // but the regions below must match whatever is actually drawn.
        var sb = new StringBuilder();
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        sb.append_printf(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%s\" height=\"%s\" viewBox=\"0 0 %s %s\">\n",
            f(width), f(height), f(width), f(height));
        sb.append_printf("<rect width=\"%s\" height=\"%s\" fill=\"%s\"/>\n",
            f(width), f(height), palette.background);
        sb.append("<defs>\n");
        sb.append_printf("<marker id=\"em-arrowhead\" markerWidth=\"10\" markerHeight=\"7\" refX=\"10\" refY=\"3.5\" orient=\"auto\"><polygon points=\"0 0, 10 3.5, 0 7\" fill=\"%s\"/></marker>\n",
            palette.edge_color);
        sb.append("</defs>\n");

        if (title_h > 0) {
            text_to(sb, width / 2, DIAGRAM_PADDING - 6, d.title, 18, palette.node_text,
                    "middle", true);
        }

        sb.append_printf("<g transform=\"translate(%s,%s)\">\n",
            f(DIAGRAM_PADDING), f(DIAGRAM_PADDING + title_h));

        bool dark = is_dark(palette.background);
        string lane_fill = dark ? "#1f1f1f" : "rgb(250,250,250)";
        string lane_stroke = dark ? "#2e2e2e" : "rgb(240,240,240)";

        foreach (var l in lanes) {
            sb.append("<g class=\"em-swimlane\">\n");
            sb.append_printf(
                "<rect x=\"0\" y=\"%s\" rx=\"3\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\"/>\n",
                f(l.y), f(max_r + SWIMLANE_PADDING), f(l.height), lane_fill, lane_stroke);
            text_to(sb, 30, l.y + 30, l.label, FONT_SIZE, palette.node_text, "start", true);
            sb.append("</g>\n");
        }

        foreach (var b in boxes) {
            double y = b.top(SWIMLANE_PADDING);
            sb.append("<g class=\"em-box\">\n");
            sb.append_printf(
                "<rect x=\"%s\" y=\"%s\" rx=\"3\" width=\"%s\" height=\"%s\" stroke=\"%s\" fill=\"%s\"/>\n",
                f(b.x), f(y), f(b.width), f(b.height),
                b.frame.kind.stroke_color(), b.frame.kind.fill_color());

            // The label block is vertically centred in the box, as the foreignObject
            // table cell is in mermaid.
            double name_h = EmText.line_height(FONT_SIZE);
            double data_h = EmText.line_height(DATA_FONT_SIZE);
            double block_h = b.name_lines.size * name_h + b.data_lines.size * data_h;
            double cursor = y + double.max(TEXT_TOP_OFFSET, (b.height - block_h) / 2);
            // Box text is always dark: the fills are mermaid's own pastels.
            foreach (string l in b.name_lines) {
                cursor += name_h;
                text_to(sb, b.x + b.width / 2, cursor - name_h * 0.28, l,
                        FONT_SIZE, "#333333", "middle", true);
            }
            foreach (string l in b.data_lines) {
                cursor += data_h;
                text_to(sb, b.x + BOX_PADDING + BOX_TEXT_PADDING, cursor - data_h * 0.28, l,
                        DATA_FONT_SIZE, "#333333", "start", false, true);
            }
            sb.append("</g>\n");

            regions.add(new ElementRegion(b.frame.name, b.frame.source_line,
                b.x + DIAGRAM_PADDING, y + DIAGRAM_PADDING + title_h, b.width, b.height));
        }

        foreach (var rel in relations) {
            double sy_top = rel.source.top(SWIMLANE_PADDING);
            double ty_top = rel.target.top(SWIMLANE_PADDING);
            bool upwards = sy_top > ty_top;

            double sx = rel.source.x + rel.source.width * 2.0 / 3.0;
            double tx = rel.target.x + rel.target.width / 3.0;
            double sy = upwards ? sy_top : sy_top + rel.source.height;
            double ty = upwards ? ty_top + rel.target.height : ty_top;

            sb.append_printf(
                "<path class=\"em-relation\" fill=\"none\" stroke=\"%s\" stroke-width=\"1\" marker-end=\"url(#em-arrowhead)\" d=\"M%s %s L%s %s\"/>\n",
                palette.edge_color, f(sx), f(sy), f(tx), f(ty));
        }

        sb.append("</g>\n</svg>\n");
        return sb.str;
    }

    private static bool is_dark(string color) {
        string c = color.strip();
        if (!c.has_prefix("#") || c.length < 7) return false;
        int r = (int) int64.parse("0x" + c.substring(1, 2));
        int g = (int) int64.parse("0x" + c.substring(3, 2));
        int b = (int) int64.parse("0x" + c.substring(5, 2));
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128;
    }

    private static void text_to(StringBuilder target, double x, double y, string content,
                                double size, string fill, string anchor = "start",
                                bool bold = false, bool mono = false) {
        if (content.length == 0) return;
        target.append_printf(
            "<text x=\"%s\" y=\"%s\" fill=\"%s\" font-size=\"%s\" font-family=\"%s\"%s%s>%s</text>\n",
            f(x), f(y), fill, f(size), mono ? "monospace" : "sans-serif",
            anchor != "start" ? " text-anchor=\"%s\"".printf(anchor) : "",
            bold ? " font-weight=\"bold\"" : "",
            Markup.escape_text(content));
    }

    /**
     * C-locale number for SVG. `"%.3f".printf` follows LC_NUMERIC and a GUI process
     * has called setlocale(), so the comma has to go.
     */
    private static string f(double v) {
        string s = "%.3f".printf(v).replace(",", ".");
        while (s.contains(".") && (s.has_suffix("0") || s.has_suffix("."))) {
            s = s.substring(0, s.length - 1);
            if (!s.contains(".")) break;
        }
        return s;
    }
}

/** Pango text measurement for the event-modeling boxes. */
internal class EmText : Object {
    private static Pango.Layout? layout = null;
    private static Cairo.ImageSurface? surface = null;

    public static double width(string text, double size, bool bold = false,
                               string family = "sans-serif") {
        if (text.length == 0) return 0;
        if (layout == null) {
            surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
            var cr = new Cairo.Context(surface);
            layout = Pango.cairo_create_layout(cr);
        }
        var desc = new Pango.FontDescription();
        desc.set_family(family);
        desc.set_absolute_size(size * Pango.SCALE);
        desc.set_weight(bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
        layout.set_font_description(desc);
        layout.set_text(text, -1);
        Pango.Rectangle ink, logical;
        layout.get_extents(out ink, out logical);
        return (double) logical.width / Pango.SCALE;
    }

    /** Mermaid's wrapped lines sit on a 1.5 line box at this font size. */
    public static double line_height(double size) {
        return size * 1.5;
    }
}

}
