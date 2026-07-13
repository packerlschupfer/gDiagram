/* MermaidSwimlaneRenderer.vala — Mermaid `swimlane-beta` diagrams.
 *
 * Mermaid calls swimlanes a "layout-variant diagram": swimlanesDiagram.ts is
 * three lines that hand flowchart's own `createFlowDiagram()` a different style
 * sheet, and flow.jison lexes `swimlane-beta` to the very same GRAPH token as
 * `flowchart` and `graph`.  Parser, AST, node shapes, labels, edges and styles
 * are the flowchart's; only the LAYOUT differs, and the lanes are the
 * top-level subgraphs.  Mermaid swaps in a dedicated lane-aware layout engine
 * for exactly that reason.
 *
 * This class is the same split: it owns one MermaidFlowchartRenderer, which
 * emits every node and edge, and supplies only the layout — in two passes.
 *
 *   Pass 1  Graphviz lays the plain flow out and we read its own `plain`
 *           output for each node's centre and size (the measurement trick the
 *           Mermaid mindmap and sequence renderers already use).
 *   Pass 2  Each node keeps its coordinate along the FLOW axis and is moved
 *           onto its lane's band along the other axis, bands in declaration
 *           order; the same DOT is re-emitted with `layout=nop2`, so Graphviz
 *           keeps those positions and only routes the edges.
 *
 * The two passes are not decoration.  Graphviz cannot be made to put the lanes
 * in declaration order: with `newrank=true` (needed to keep a cluster's rank
 * anchors inside it) dot's mincross ignores flat edges between nodes of
 * different clusters — reversing the ordering chain changes nothing — and
 * without it a top-level `rank=same` set deletes the anchors from their
 * clusters, which both loses the full-width band and segfaults dot 14 on a
 * four-lane graph.  Crossing minimisation then picks the lane order, which is
 * not the author's.
 */
namespace GDiagram {

public class MermaidSwimlaneRenderer : Object {
    private MermaidFlowchartRenderer inner;
    private unowned Gvc.Context context;

    // Band metrics, in Graphviz points
    private const double LANE_PAD = 22.0;     // band edge to content
    private const double LANE_TITLE = 22.0;   // extra room for the lane name
    private const double LANE_GAP = 10.0;     // between two bands
    private const double LANE_END_PAD = 24.0; // band ends beyond the first/last node

    public MermaidSwimlaneRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.inner = new MermaidFlowchartRenderer(ctx, regions, engine);
        this.inner.swimlane_mode = true;
    }

    // A node's laid-out box, in Graphviz points
    private class Box : Object {
        public double x;
        public double y;
        public double w;
        public double h;
    }

    public string generate_dot(MermaidFlowchart diagram) {
        inner.pinned_positions = null;
        inner.extra_dot = null;
        string pass1 = inner.generate_dot(diagram);

        // No lanes declared: this is just a flowchart, and pass 1 is the answer.
        if (diagram.subgraphs.size == 0 || diagram.nodes.size == 0) {
            return pass1;
        }

        var boxes = measure(pass1);
        if (boxes == null || boxes.size == 0) {
            warning("Swimlane measurement pass failed; falling back to the plain flow layout");
            return pass1;
        }

        string? pinned = build_pinned(diagram, boxes);
        if (pinned == null) {
            return pass1;
        }
        return pinned;
    }

    /**
     * Lays the flow out once and reads Graphviz's `plain` output, whose node
     * records are `node <name> <x> <y> <width> <height> ...` in inches.
     */
    private Gee.HashMap<string, Box>? measure(string dot_source) {
        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) return null;
        if (context.layout(graph, "dot") != 0) {
            context.free_layout(graph);
            return null;
        }
        uint8[] data;
        int ret = RenderUtils.render_data(context, graph, "plain", out data);
        context.free_layout(graph);
        if (ret != 0 || data.length == 0) return null;

        var text = new StringBuilder.sized(data.length + 1);
        text.append_len((string) data, data.length);

        var boxes = new Gee.HashMap<string, Box>();
        foreach (string line in text.str.split("\n")) {
            if (!line.has_prefix("node ")) continue;
            string[] f = line.split(" ");
            if (f.length < 6) continue;
            string name = f[1];
            if (name.length > 1 && name.has_prefix("\"") && name.has_suffix("\"")) {
                name = name.substring(1, name.length - 2);
            }
            var b = new Box();
            // double.parse is g_ascii_strtod, so a comma-decimal locale is safe here
            b.x = double.parse(f[2]) * 72.0;
            b.y = double.parse(f[3]) * 72.0;
            b.w = double.parse(f[4]) * 72.0;
            b.h = double.parse(f[5]) * 72.0;
            boxes.set(name, b);
        }
        return boxes;
    }

    private static bool lane_holds(FlowchartSubgraph lane, FlowchartNode node) {
        if (lane.nodes.contains(node)) return true;
        foreach (var inner_sg in lane.subgraphs) {
            if (lane_holds(inner_sg, node)) return true;
        }
        return false;
    }

    /**
     * Moves each node onto its lane's band and re-emits the graph pinned.
     *
     * The flow runs along the "rank" axis (x for LR/RL, y for TB/BT); the lanes
     * are stacked along the other one.  Mermaid puts the first lane at the top
     * for a left-to-right flow and at the left for a top-down one, which is
     * what the two branches below produce.
     */
    private string? build_pinned(MermaidFlowchart diagram, Gee.HashMap<string, Box> boxes) {
        bool flow_horizontal = diagram.direction == FlowchartDirection.LEFT_RIGHT ||
                               diagram.direction == FlowchartDirection.RIGHT_LEFT;

        int lane_count = diagram.subgraphs.size;
        // lane_of[i] is the lane index of diagram.nodes[i]; lane_count means "no lane"
        var lane_of = new Gee.HashMap<FlowchartNode, int>();
        foreach (var node in diagram.nodes) {
            int which = lane_count;
            for (int i = 0; i < lane_count; i++) {
                if (lane_holds(diagram.subgraphs[i], node)) { which = i; break; }
            }
            lane_of.set(node, which);
        }

        int bands = lane_count + 1;   // the last band collects un-laned nodes
        var lo = new double[bands];
        var hi = new double[bands];
        var used = new bool[bands];
        double rank_lo = 0, rank_hi = 0;
        bool any = false;

        foreach (var node in diagram.nodes) {
            var b = boxes.get(node.get_safe_id());
            if (b == null) continue;
            double o_c = flow_horizontal ? b.y : b.x;     // across the flow
            double o_half = (flow_horizontal ? b.h : b.w) / 2.0;
            double r_c = flow_horizontal ? b.x : b.y;     // along the flow
            double r_half = (flow_horizontal ? b.w : b.h) / 2.0;

            int k = lane_of.get(node);
            if (!used[k]) {
                lo[k] = o_c - o_half; hi[k] = o_c + o_half; used[k] = true;
            } else {
                lo[k] = double.min(lo[k], o_c - o_half);
                hi[k] = double.max(hi[k], o_c + o_half);
            }
            if (!any) {
                rank_lo = r_c - r_half; rank_hi = r_c + r_half; any = true;
            } else {
                rank_lo = double.min(rank_lo, r_c - r_half);
                rank_hi = double.max(rank_hi, r_c + r_half);
            }
        }
        if (!any) return null;

        // Stack the bands in declaration order along a cursor that grows away
        // from the first lane; `start`/`size` are in that cursor's units.
        var start = new double[bands];
        var size = new double[bands];
        double cursor = 0;
        for (int i = 0; i < bands; i++) {
            if (!used[i]) { start[i] = cursor; size[i] = 0; continue; }
            start[i] = cursor;
            size[i] = (hi[i] - lo[i]) + 2 * LANE_PAD + LANE_TITLE;
            cursor += size[i] + LANE_GAP;
        }
        double total = cursor > 0 ? cursor - LANE_GAP : 0;

        double band_rank_lo = rank_lo - LANE_END_PAD;
        double band_rank_hi = rank_hi + LANE_END_PAD;

        // Cursor -> Graphviz coordinate. Graphviz y grows upwards, so a
        // horizontal flow has to count the bands down from the top to put lane 0
        // there; a vertical flow stacks left to right, which x already does.
        var positions = new Gee.HashMap<string, string>();
        foreach (var node in diagram.nodes) {
            var b = boxes.get(node.get_safe_id());
            if (b == null) continue;
            int k = lane_of.get(node);
            double o_c = flow_horizontal ? b.y : b.x;
            double inside = (o_c - lo[k]) + LANE_PAD + LANE_TITLE;   // from the band's leading edge
            double o_new;
            if (flow_horizontal) {
                o_new = (total - start[k]) - inside;
            } else {
                o_new = start[k] + inside;
            }
            double r_c = flow_horizontal ? b.x : b.y;
            positions.set(node.get_safe_id(), flow_horizontal
                ? "%s,%s".printf(PinnedDotWriter.num(r_c), PinnedDotWriter.num(o_new))
                : "%s,%s".printf(PinnedDotWriter.num(o_new), PinnedDotWriter.num(r_c)));
        }

        var palette = ThemeManager.get_active_palette();
        var rects = new StringBuilder();
        rects.append("\n  // Swimlane bands, in declaration order\n");
        for (int i = 0; i < lane_count; i++) {
            if (!used[i]) continue;
            var lane = diagram.subgraphs[i];
            double b_lo, b_hi;   // the band's extent on the cross-flow axis
            if (flow_horizontal) {
                b_hi = total - start[i];
                b_lo = b_hi - size[i];
            } else {
                b_lo = start[i];
                b_hi = b_lo + size[i];
            }

            double cx, cy, w, h;
            if (flow_horizontal) {
                cx = (band_rank_lo + band_rank_hi) / 2.0;
                cy = (b_lo + b_hi) / 2.0;
                w = band_rank_hi - band_rank_lo;
                h = b_hi - b_lo;
            } else {
                cx = (b_lo + b_hi) / 2.0;
                cy = (band_rank_lo + band_rank_hi) / 2.0;
                w = b_hi - b_lo;
                h = band_rank_hi - band_rank_lo;
            }

            string border = lane.stroke_color != null
                ? MermaidFlowchartRenderer.css_color(lane.stroke_color) : palette.container_border;
            string fill = lane.fill_color != null
                ? MermaidFlowchartRenderer.css_color(lane.fill_color) : palette.grid;
            bool dashed = lane.stroke_dasharray != null && lane.stroke_dasharray.length > 0;

            rects.append_printf(
                "  lane_band_%d [shape=box, style=\"rounded,filled%s\", label=\"\", " +
                "fixedsize=true, width=%s, height=%s, pos=\"%s,%s\", " +
                "color=\"%s\", fillcolor=\"%s\", penwidth=%s];\n",
                i, dashed ? ",dashed" : "",
                PinnedDotWriter.num(w / 72.0), PinnedDotWriter.num(h / 72.0),
                PinnedDotWriter.num(cx), PinnedDotWriter.num(cy),
                border, fill, lane.stroke_width ?? "2");

            // Mermaid draws the lane name in a narrow strip on the band's
            // leading edge, rotated 90°. Graphviz cannot rotate text, so the
            // name goes in the band's leading corner instead.
            string title = lane.title != null && lane.title.length > 0 ? lane.title : lane.id;
            string title_color = lane.font_color != null
                ? MermaidFlowchartRenderer.css_color(lane.font_color)
                : (lane.fill_color != null
                    ? RenderUtils.contrast_text(MermaidFlowchartRenderer.css_color(lane.fill_color))
                    : palette.node_text);
            double tw = title.char_count() * 9.0 + 12.0;
            double tx, ty;
            if (flow_horizontal) {
                tx = band_rank_lo + tw / 2.0 + 8.0;
                ty = b_hi - LANE_TITLE / 2.0 - 4.0;
            } else {
                tx = b_lo + tw / 2.0 + 8.0;
                ty = band_rank_hi - LANE_TITLE / 2.0 - 4.0;
            }
            rects.append_printf(
                "  lane_name_%d [shape=plaintext, label=\"%s\", fontsize=14, " +
                "fontname=\"Sans Bold\", fontcolor=\"%s\", fixedsize=true, " +
                "width=%s, height=%s, pos=\"%s,%s\"];\n",
                i, RenderUtils.escape_label(title), title_color,
                PinnedDotWriter.num(tw / 72.0), PinnedDotWriter.num(LANE_TITLE / 72.0),
                PinnedDotWriter.num(tx), PinnedDotWriter.num(ty));
        }

        inner.pinned_positions = positions;
        inner.extra_dot = rects.str;
        string pinned_dot = inner.generate_dot(diagram);
        inner.pinned_positions = null;
        inner.extra_dot = null;
        return pinned_dot;
    }

    // ---- output ----

    public uint8[]? render_to_svg(MermaidFlowchart diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse swimlane DOT graph");
            return null;
        }
        // "dot" is still the engine name; the DOT's own layout=nop2 takes over
        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to lay out swimlane graph");
            context.free_layout(graph);
            return null;
        }
        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);
        if (ret != 0) {
            warning("Failed to render swimlane diagram to SVG");
            return null;
        }
        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidFlowchart diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(MermaidFlowchart diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidFlowchart diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidFlowchart diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
