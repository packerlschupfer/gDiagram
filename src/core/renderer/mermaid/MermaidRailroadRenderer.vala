/* MermaidRailroadRenderer.vala — Mermaid railroad diagrams (railroad-beta and
 * its EBNF / ABNF / PEG front ends) drawn on gDiagram's existing railroad
 * machinery.
 *
 * Reused from EbnfDiagramRenderer.vala (the PlantUML @startebnf railroad):
 *   PinnedDotWriter  fixed-position DOT (layout=nop2) so Graphviz only paints
 *   RailPainter      hline / vline / turn / spline primitives
 *   RailItem         the w / up / down + draw(painter, x, y) protocol
 *   RailBox          the symbol boxes (with three Mermaid styles added)
 *   RailSequence     items in a row
 *
 * Written here, because Mermaid's railroadRenderer.ts lays these three out
 * differently from PlantUML's:
 *   MermaidRailChoice       alternatives centred on the track (PlantUML keeps
 *                           the first alternative on it and stacks downwards)
 *   MermaidRailOptional     element on the track, bypass arcing ABOVE it
 *                           (PlantUML puts the bypass on the track instead)
 *   MermaidRailRepetition   loop returning BELOW the element (PlantUML returns
 *                           above), plus a bypass above when min is 0
 *
 * Every constant below is from mermaid's DEFAULT_RAILROAD_CONFIG.
 */
namespace GDiagram {

// mermaid DEFAULT_RAILROAD_CONFIG
internal const double MMRR_R = 10.0;        // arcRadius
internal const double MMRR_VSEP = 8.0;      // verticalSeparation
internal const double MMRR_PAD = 10.0;      // padding
internal const double MMRR_FONT = 14.0;     // fontSize
internal const double MMRR_BOX_H = 37.0;    // measured text height (17) + padding * 2
internal const double MMRR_MARKER = 5.0;    // markerRadius

/**
 * Alternatives stacked top to bottom with the track entering and leaving at the
 * vertical centre of the whole stack (mermaid's renderChoice).  Each alternative
 * is centred horizontally in the widest one's column.
 */
internal class MermaidRailChoice : RailItem {
    private Gee.ArrayList<RailItem> items;
    private double[] centres;   // y of each alternative's track, from the stack top
    private double inner_w;
    private double total_h;

    public MermaidRailChoice(Gee.ArrayList<RailItem> items) {
        this.items = items;
        centres = new double[items.size];
        inner_w = 0;
        total_h = 0;
        foreach (var it in items) inner_w = double.max(inner_w, it.w);

        double y = 0;
        for (int i = 0; i < items.size; i++) {
            var it = items.get(i);
            centres[i] = y + it.up;
            y += it.up + it.down;
            if (i < items.size - 1) y += MMRR_VSEP;
        }
        total_h = y;
        w = inner_w + 4 * MMRR_R;
        up = total_h / 2;
        down = total_h - up;
    }

    public override void draw(RailPainter p, double x, double y) {
        double top = y - up;            // stack top in absolute coordinates
        double centre = y;              // the incoming/outgoing track
        double right_lane = x + w - 2 * MMRR_R;

        for (int i = 0; i < items.size; i++) {
            var it = items.get(i);
            double ty = top + centres[i];
            double ix = x + 2 * MMRR_R + (inner_w - it.w) / 2;

            if (Math.fabs(ty - centre) < 0.01) {
                p.hline(x, ix, centre);
                p.hline(ix + it.w, x + w, centre);
            } else {
                bool below = ty > centre;
                double s = below ? 1.0 : -1.0;
                // left: out horizontally, down/up the lane, back in horizontally
                p.turn(x, centre, x + MMRR_R, centre + s * MMRR_R, true);
                p.vline(x + MMRR_R, centre + s * MMRR_R, ty - s * MMRR_R);
                p.turn(x + MMRR_R, ty - s * MMRR_R, x + 2 * MMRR_R, ty, false);
                p.hline(x + 2 * MMRR_R, ix, ty);
                // right: mirror image back to the centre line
                p.hline(ix + it.w, right_lane, ty);
                p.turn(right_lane, ty, right_lane + MMRR_R, ty - s * MMRR_R, true);
                p.vline(right_lane + MMRR_R, ty - s * MMRR_R, centre + s * MMRR_R);
                p.turn(right_lane + MMRR_R, centre + s * MMRR_R, x + w, centre, false);
            }
            it.draw(p, ix, ty);
        }
    }
}

/** The element on the track with a bypass arcing above it (mermaid's renderOptional). */
internal class MermaidRailOptional : RailItem {
    private RailItem item;

    public MermaidRailOptional(RailItem item) {
        this.item = item;
        w = item.w + 4 * MMRR_R;
        up = 2 * MMRR_R + item.up;
        down = item.down;
    }

    public override void draw(RailPainter p, double x, double y) {
        p.hline(x, x + 2 * MMRR_R, y);
        item.draw(p, x + 2 * MMRR_R, y);
        p.hline(x + 2 * MMRR_R + item.w, x + w, y);
        draw_bypass(p, x, y, w, up);
    }

    // The bypass shared with a zero-or-more repetition: up out of the track,
    // across the top of the item, back down into the track.
    internal static void draw_bypass(RailPainter p, double x, double y, double w, double up) {
        double top = y - up;
        p.turn(x, y, x + MMRR_R, y - MMRR_R, true);
        p.vline(x + MMRR_R, y - MMRR_R, top + MMRR_R);
        p.turn(x + MMRR_R, top + MMRR_R, x + 2 * MMRR_R, top, false);
        p.hline(x + 2 * MMRR_R, x + w - 2 * MMRR_R, top);
        p.turn(x + w - 2 * MMRR_R, top, x + w - MMRR_R, top + MMRR_R, true);
        p.vline(x + w - MMRR_R, top + MMRR_R, y - MMRR_R);
        p.turn(x + w - MMRR_R, y - MMRR_R, x + w, y, false);
    }
}

/**
 * The element on the track with the loop returning below it (mermaid's
 * renderRepetition); `min == 0` adds the same bypass above that an optional has,
 * which is how `*` differs from `+`.  Mermaid's renderer ignores `max`.
 */
internal class MermaidRailRepetition : RailItem {
    private RailItem item;
    private bool bypass;
    private double loop_offset;   // loop track below the item's own track

    public MermaidRailRepetition(RailItem item, int min) {
        this.item = item;
        this.bypass = min == 0;
        w = item.w + 4 * MMRR_R;
        up = (bypass ? 2 * MMRR_R : 0) + item.up;
        // mermaid: loopY = elemY + inner.height + arcRadius, and the lower edge
        // of the returning track sits one more radius below that.
        loop_offset = item.down + MMRR_R;
        double total_h = item.up + item.down + 2 * MMRR_R + (bypass ? 2 * MMRR_R : 0);
        down = total_h - up;
    }

    public override void draw(RailPainter p, double x, double y) {
        double ix = x + 2 * MMRR_R;
        double ex = ix + item.w;
        p.hline(x, ix, y);
        item.draw(p, ix, y);
        p.hline(ex, x + w, y);

        double loop_y = y + loop_offset;
        p.turn(ex, y, ex + MMRR_R, y + MMRR_R, true);
        p.vline(ex + MMRR_R, y + MMRR_R, loop_y);
        p.turn(ex + MMRR_R, loop_y, ex, loop_y + MMRR_R, false);
        p.hline(ix, ex, loop_y + MMRR_R);
        p.turn(ix, loop_y + MMRR_R, x + MMRR_R, loop_y, true);
        p.vline(x + MMRR_R, loop_y, y + MMRR_R);
        p.turn(x + MMRR_R, y + MMRR_R, ix, y, false);

        if (bypass) {
            MermaidRailOptional.draw_bypass(p, x, y, w, up);
        }
    }
}

public class MermaidRailroadRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    // Kept for signature parity with the other renderers; the geometry is
    // already fixed, so this one always lays out with "dot" + nop2.
    private string layout_engine;
    private Gee.HashMap<string, int> element_lines;

    public MermaidRailroadRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
        this.element_lines = new Gee.HashMap<string, int>();
    }

    /**
     * One railroad track per rule, in source order: the rule name as "name =",
     * a start dot, the expression, and an end dot (mermaid's renderRule).
     */
    public string generate_dot(MermaidRailroad diagram) {
        element_lines = new Gee.HashMap<string, int>();
        // Reset per render, or a second call on the same renderer would hand the
        // same boxes different ids and the DOT would not be reproducible.
        box_seq = 0;
        var palette = ThemeManager.get_active_palette();
        var p = new RailPainter();
        p.line_color = palette.node_text;
        p.text_color = palette.node_text;

        double y = MMRR_PAD;
        if (diagram.title != null && diagram.title.length > 0) {
            p.dot.left_text(MMRR_PAD, y + MMRR_FONT, diagram.title, MMRR_FONT + 2, true,
                palette.node_text);
            y += 2 * MMRR_FONT + 6;
        }

        int index = 0;
        foreach (var rule in diagram.rules) {
            var body = build(rule.definition, rule.source_line, index);
            // mermaid: baselineY = max(20, up); the rule box is at least 40 tall
            double baseline = double.max(20.0, body.up);
            double track = y + baseline;

            string rule_name = rule.name + " =";
            double name_w = RailPainter.text_width(rule_name, MMRR_FONT) + 20.0;
            string rule_id = "mmrr_rule_%d".printf(index);
            p.dot.left_text(MMRR_PAD, track, rule_name, MMRR_FONT, true, palette.node_text,
                "id=\"%s\"".printf(rule_id));
            if (rule.source_line > 0) element_lines.set(rule_id, rule.source_line);

            double marker_x = MMRR_PAD + name_w;
            double def_x = marker_x + 20.0;
            // Start and end markers are filled dots of markerRadius
            p.dot.node(marker_x, track, 2 * MMRR_MARKER, 2 * MMRR_MARKER,
                "shape=circle style=filled fillcolor=\"%s\" color=\"%s\"".printf(
                    palette.node_text, palette.node_text));
            p.hline(marker_x + MMRR_MARKER, def_x, track);

            body.draw(p, def_x, track);

            double end_x = def_x + body.w + 10.0;
            p.hline(def_x + body.w, end_x - MMRR_MARKER, track);
            p.dot.node(end_x, track, 2 * MMRR_MARKER, 2 * MMRR_MARKER,
                "shape=circle style=filled fillcolor=\"%s\" color=\"%s\"".printf(
                    palette.node_text, palette.node_text));

            double height = double.max(40.0,
                (baseline - body.up) + body.up + body.down + 2 * MMRR_PAD);
            y += height + MMRR_VSEP;
            index++;
        }

        if (diagram.rules.size == 0) {
            p.dot.left_text(MMRR_PAD, y + MMRR_FONT, "(no rules)", MMRR_FONT, false,
                palette.node_text);
        }
        return p.dot.finish(palette.background, MMRR_PAD);
    }

    // ---- AST -> RailItem ----

    private RailItem build(MermaidRailroadNode node, int line, int rule_index) {
        switch (node.node_type) {
            case MermaidRailroadNodeType.TERMINAL:
                return box(node.text, RailBoxStyle.MM_TERMINAL, line, rule_index);
            case MermaidRailroadNodeType.NONTERMINAL:
                return box(node.text, RailBoxStyle.MM_NONTERMINAL, line, rule_index);
            case MermaidRailroadNodeType.SPECIAL:
                // mermaid's renderSpecial labels the box "? text ?"
                return box("? %s ?".printf(node.text), RailBoxStyle.MM_SPECIAL, line, rule_index);
            case MermaidRailroadNodeType.SEQUENCE: {
                var items = new Gee.ArrayList<RailItem>();
                foreach (var c in node.children) items.add(build(c, line, rule_index));
                if (items.size == 0) return new RailEmpty();
                if (items.size == 1) return items.get(0);
                return new RailSequence(items);
            }
            case MermaidRailroadNodeType.CHOICE: {
                var items = new Gee.ArrayList<RailItem>();
                foreach (var c in node.children) items.add(build(c, line, rule_index));
                if (items.size == 0) return new RailEmpty();
                if (items.size == 1) return items.get(0);
                return new MermaidRailChoice(items);
            }
            case MermaidRailroadNodeType.OPTIONAL:
                if (node.children.size == 0) return new RailEmpty();
                return new MermaidRailOptional(build(node.children.get(0), line, rule_index));
            case MermaidRailroadNodeType.REPETITION:
                if (node.children.size == 0) return new RailEmpty();
                return new MermaidRailRepetition(build(node.children.get(0), line, rule_index),
                                                 node.min);
            default:
                return new RailEmpty();
        }
    }

    private int box_seq = 0;

    private RailItem box(string text, RailBoxStyle style, int line, int rule_index) {
        string id = "mmrr_%d_%d".printf(rule_index, box_seq++);
        if (line > 0) element_lines.set(id, line);
        return new RailBox.styled(text, style, id, MMRR_FONT, MMRR_BOX_H);
    }

    // ---- output ----

    public uint8[]? render_to_svg(MermaidRailroad diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse Mermaid railroad DOT graph");
            return null;
        }

        // The geometry is already fixed (layout=nop2 in the DOT), so Graphviz
        // only paints; the engine name must still be "dot" for nop2 to apply.
        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to lay out Mermaid railroad graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render Mermaid railroad diagram to SVG");
            return null;
        }
        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidRailroad diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null,
                Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 400, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
            var cr = new Cairo.Context(surface);
            var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
            handle.render_document(cr, viewport);

            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render Mermaid railroad SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidRailroad diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidRailroad diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidRailroad diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
