/* MermaidWardleyRenderer.vala — Mermaid `wardley-beta` maps on a pinned ChartCanvas
 *
 * A port of mermaid 12.2.0's wardleyRenderer.ts. Everything on a Wardley map
 * sits at an explicit coordinate, so there is no layout to compute: the drawing
 * goes onto ChartCanvas (shared with the xychart, pie, radar, treemap, packet,
 * sankey and timeline renderers), which pins every item with `layout=nop2` and
 * lets Graphviz do nothing but paint.
 *
 * Mermaid's own geometry is kept verbatim, in its px units read as points: the
 * map is 900 x 600 with a 48 padding, the same numbers as
 * wardleyRenderer.getConfigValues(), so the proportions of text, nodes and axes
 * match its SVG one-for-one.
 *
 * Accepted differences from mermaid's SVG, all of them Graphviz limits:
 *   - the y axis title is horizontal above the axis instead of rotated -90°
 *     (Graphviz cannot rotate text), as MermaidXYChartRenderer already does;
 *   - link labels are horizontal rather than rotated along the link;
 *   - dash patterns collapse to Graphviz's `dashed` / `dotted`;
 *   - flow arrowheads are two-segment chevrons rather than filled triangles;
 *   - the accelerator/deaccelerator arrows are drawn as an outline (ChartCanvas
 *     draws nodes and line segments, not filled polygons);
 *   - the annotations legend box is sized from a Pango measurement instead of
 *     mermaid's measured width plus its 105px safety buffer;
 *   - `showGrid` is a mermaid config key with no syntax to set it, so the
 *     optional background grid is not drawn.
 */
namespace GDiagram {

public class MermaidWardleyRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // DOT node name -> clickable element name, and element name -> source line.
    private Gee.HashMap<string, string> region_names;
    private Gee.HashMap<string, int> element_lines;

    public MermaidWardleyRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
        this.region_names = new Gee.HashMap<string, string>();
        this.element_lines = new Gee.HashMap<string, int>();
    }

    // wardleyRenderer.getConfigValues() defaults.
    private const double DEF_WIDTH = 900.0;
    private const double DEF_HEIGHT = 600.0;
    private const double PADDING = 48.0;
    private const double NODE_RADIUS = 6.0;
    private const double NODE_LABEL_OFFSET = 8.0;
    private const double AXIS_FONT = 12.0;
    private const double LABEL_FONT = 10.0;

    // `squareSize = nodeRadius * 1.6` — the pipeline parent's square.
    private const double SQUARE = NODE_RADIUS * 1.6;

    // theme.evolutionStroke: mermaid's fixed #dc3545, which reads on light and
    // dark canvases alike, so it is not taken from the palette.
    private const string EVOLUTION_COLOR = "#DC3545";

    private const string[] DEFAULT_STAGES = { "Genesis", "Custom Built", "Product", "Commodity" };

    // A node's position on the canvas, in points from the top-left.
    private class Pos {
        public double x;
        public double y;
        public WardleyMapNode node;
        public Pos(double x, double y, WardleyMapNode node) {
            this.x = x;
            this.y = y;
            this.node = node;
        }
    }

    public string generate_dot(MermaidWardley diagram) {
        var palette = ThemeManager.get_active_palette();
        region_names = new Gee.HashMap<string, string>();
        element_lines = new Gee.HashMap<string, int>();

        var cv = new ChartCanvas();
        cv.margin = 0;   // the background rect already spans the whole page

        string text_color = RenderUtils.sanitize_color(palette.node_text);
        string axis_color = RenderUtils.sanitize_color(palette.node_border);
        string link_color = RenderUtils.sanitize_color(palette.edge_color);
        string comp_fill = RenderUtils.sanitize_color(palette.node_fill);
        string comp_stroke = RenderUtils.sanitize_color(palette.node_border);
        string bg = RenderUtils.sanitize_color(palette.background);

        double width = diagram.has_size ? (double) diagram.size_width : DEF_WIDTH;
        double height = diagram.has_size ? (double) diagram.size_height : DEF_HEIGHT;
        double chart_w = width - PADDING * 2;
        double chart_h = height - PADDING * 2;
        if (chart_w < 1) chart_w = 1;
        if (chart_h < 1) chart_h = 1;

        cv.rect(0, 0, width, height, bg, bg, 0, "wardley_bg");

        if (diagram.title != null && diagram.title.length > 0) {
            cv.text(width / 2, PADDING / 2, diagram.title, AXIS_FONT * 1.05, text_color,
                    'c', true, "wardley_title");
        }

        // ---- axes ----
        cv.line(PADDING, height - PADDING, width - PADDING, height - PADDING,
                axis_color, 1.0, "wardley_axis_x");
        cv.line(PADDING, PADDING, PADDING, height - PADDING,
                axis_color, 1.0, "wardley_axis_y");
        cv.text(PADDING + chart_w / 2, height - PADDING / 4, "Evolution", AXIS_FONT, text_color,
                'c', true, "wardley_axis_label_x");
        // Horizontal, above the y axis: Graphviz cannot rotate text.
        cv.text(PADDING, PADDING - AXIS_FONT, "Visibility", AXIS_FONT, text_color,
                'l', true, "wardley_axis_label_y");

        // ---- evolution stages ----
        draw_stages(cv, diagram, axis_color, text_color, width, height, chart_w);

        // ---- node positions ----
        var positions = new Gee.HashMap<string, Pos>();
        foreach (var node in diagram.nodes) {
            positions.set(node.id, new Pos(project_x(node.x, chart_w),
                                           project_y(node.y, height, chart_h), node));
        }

        // ---- pipelines (they move their parent node, so they come first) ----
        draw_pipelines(cv, diagram, positions, axis_color, link_color);

        // ---- links ----
        draw_links(cv, diagram, positions, link_color, text_color);

        // ---- evolution trends ----
        draw_trends(cv, diagram, positions, chart_w, chart_h, height);

        // ---- nodes ----
        draw_nodes(cv, diagram, positions, comp_fill, comp_stroke, text_color);

        // ---- annotations, notes, accelerators ----
        draw_annotations(cv, diagram, axis_color, text_color, comp_fill,
                         width, height, chart_w, chart_h);
        foreach (var note in diagram.notes) {
            string n = cv.text(project_x(note.x, chart_w), project_y(note.y, height, chart_h),
                               note.text, 11, text_color, 'l', true,
                               "wardley_note_%d".printf(diagram.notes.index_of(note)));
            map_region(n, note.text, note.source_line);
        }
        draw_accelerators(cv, diagram, comp_stroke, text_color, chart_w, chart_h, height);

        return cv.finish("wardley", bg);
    }

    // ==================== projection ====================

    private static double project_x(double percent, double chart_w) {
        return PADDING + (percent / 100.0) * chart_w;
    }

    private static double project_y(double percent, double height, double chart_h) {
        return height - PADDING - (percent / 100.0) * chart_h;
    }

    // ==================== pieces ====================

    private void draw_stages(ChartCanvas cv, MermaidWardley diagram, string axis_color,
                             string text_color, double width, double height, double chart_w) {
        var stages = new Gee.ArrayList<string>();
        if (diagram.stages.size > 0) {
            stages.add_all(diagram.stages);
        } else {
            foreach (string s in DEFAULT_STAGES) stages.add(s);
        }
        if (stages.size == 0) return;

        // Custom `@boundary` values are only used when there is one per stage,
        // exactly as mermaid's renderer requires; otherwise the stages split the
        // axis evenly. Boundaries are fractions of the chart width, 0..1.
        var starts = new double[stages.size];
        var ends = new double[stages.size];
        bool custom = diagram.stage_boundaries.size == stages.size;
        if (custom) {
            double prev = 0;
            for (int i = 0; i < stages.size; i++) {
                starts[i] = prev;
                ends[i] = diagram.stage_boundaries.get(i);
                prev = ends[i];
            }
        } else {
            double w = 1.0 / stages.size;
            for (int i = 0; i < stages.size; i++) {
                starts[i] = i * w;
                ends[i] = (i + 1) * w;
            }
        }

        for (int i = 0; i < stages.size; i++) {
            double start_x = PADDING + starts[i] * chart_w;
            double end_x = PADDING + ends[i] * chart_w;
            if (i > 0) {
                cv.line(start_x, PADDING, start_x, height - PADDING, axis_color, 1.0,
                        "wardley_stage_divider_%d".printf(i), "style=dashed");
            }
            cv.text((start_x + end_x) / 2, height - PADDING / 1.5, stages.get(i),
                    AXIS_FONT - 2, text_color, 'c', false, "wardley_stage_%d".printf(i));
        }
    }

    /**
     * The pipeline band: dotted links between consecutive children and a box
     * around them. mermaid then moves the parent node to the top edge of that
     * box ("2/3 outside, 1/3 inside"), which is why this runs before the links.
     */
    private void draw_pipelines(ChartCanvas cv, MermaidWardley diagram,
                                Gee.HashMap<string, Pos> positions,
                                string axis_color, string link_color) {
        int pi = -1;
        foreach (var pipeline in diagram.pipelines) {
            pi++;
            if (pipeline.component_ids.size == 0) continue;

            // Children sorted by evolution, so the dotted chain runs left to right.
            var sorted = new Gee.ArrayList<Pos>();
            foreach (string id in pipeline.component_ids) {
                var p = positions.get(id);
                if (p != null) sorted.add(p);
            }
            if (sorted.size == 0) continue;
            sorted.sort((a, b) => {
                if (a.node.x < b.node.x) return -1;
                if (a.node.x > b.node.x) return 1;
                return 0;
            });

            for (int i = 0; i + 1 < sorted.size; i++) {
                cv.line(sorted.get(i).x, sorted.get(i).y,
                        sorted.get(i + 1).x, sorted.get(i + 1).y,
                        link_color, 1.0, "wardley_pipe_link_%d_%d".printf(pi, i), "style=dotted");
            }

            double min_x = double.MAX, max_x = -double.MAX, y = 0;
            foreach (var p in sorted) {
                min_x = double.min(min_x, p.x);
                max_x = double.max(max_x, p.x);
                y = p.y;
            }

            double box_pad = 15.0;
            double box_h = NODE_RADIUS * 4;
            double box_top = y - box_h / 2;

            var parent = positions.get(pipeline.node_id);
            if (parent != null) {
                parent.x = (min_x + max_x) / 2;
                parent.y = box_top - SQUARE / 6;
            }

            string name = cv.rect(min_x - box_pad, box_top, max_x - min_x + box_pad * 2, box_h,
                                  "none", axis_color, 1.5, "wardley_pipeline_%d".printf(pi));
            map_region(name, pipeline.node_id, pipeline.source_line);
        }
    }

    private void draw_links(ChartCanvas cv, MermaidWardley diagram,
                            Gee.HashMap<string, Pos> positions,
                            string link_color, string text_color) {
        // A child's link up to its own pipeline parent is implied by the box.
        int li = -1;
        foreach (var link in diagram.links) {
            li++;
            var src = positions.get(link.source);
            var dst = positions.get(link.target);
            if (src == null || dst == null) continue;
            var pipeline = diagram.find_pipeline(link.target);
            if (pipeline != null && pipeline.component_ids.contains(link.source)) continue;

            double dx = dst.x - src.x;
            double dy = dst.y - src.y;
            double dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < 1e-9) continue;

            double r_src = src.node.is_pipeline_parent ? SQUARE / Math.sqrt(2) : NODE_RADIUS;
            double r_dst = dst.node.is_pipeline_parent ? SQUARE / Math.sqrt(2) : NODE_RADIUS;
            double x1 = src.x + dx / dist * r_src;
            double y1 = src.y + dy / dist * r_src;
            double x2 = dst.x - dx / dist * r_dst;
            double y2 = dst.y - dy / dist * r_dst;

            cv.line(x1, y1, x2, y2, link_color, 1.0, "wardley_link_%d".printf(li),
                    link.dashed ? "style=dashed" : "");

            if (link.flow == WardleyFlow.FORWARD || link.flow == WardleyFlow.BIDIRECTIONAL) {
                chevron(cv, x2, y2, dx / dist, dy / dist, link_color, "wardley_link_%d_end".printf(li));
            }
            if (link.flow == WardleyFlow.BACKWARD || link.flow == WardleyFlow.BIDIRECTIONAL) {
                chevron(cv, x1, y1, -dx / dist, -dy / dist, link_color, "wardley_link_%d_start".printf(li));
            }

            if (link.label != null && link.label.length > 0) {
                // Mermaid offsets the label 8 along the link's perpendicular and
                // rotates it; we keep the offset and leave the text horizontal.
                double perp_x = dy / dist;
                double perp_y = -dx / dist;
                cv.text((src.x + dst.x) / 2 + perp_x * 8, (src.y + dst.y) / 2 + perp_y * 8,
                        link.label, LABEL_FONT, text_color, 'c', false,
                        "wardley_link_label_%d".printf(li));
            }
        }
    }

    /**
     * An arrowhead as two short segments meeting at (x, y), pointing along the
     * unit vector (ux, uy). Graphviz draws no arrowheads on the undirected
     * edges ChartCanvas emits, so the marker is drawn as geometry.
     */
    private static void chevron(ChartCanvas cv, double x, double y, double ux, double uy,
                                string color, string id) {
        const double LEN = 5.0;
        const double SPREAD = 0.45;   // radians off the shaft, ~26°
        double ang = Math.atan2(uy, ux);
        double ax = x - LEN * Math.cos(ang - SPREAD);
        double ay = y - LEN * Math.sin(ang - SPREAD);
        double bx = x - LEN * Math.cos(ang + SPREAD);
        double by = y - LEN * Math.sin(ang + SPREAD);
        cv.line(ax, ay, x, y, color, 1.2, id + "_a");
        cv.line(bx, by, x, y, color, 1.2, id + "_b");
    }

    private void draw_trends(ChartCanvas cv, MermaidWardley diagram,
                             Gee.HashMap<string, Pos> positions,
                             double chart_w, double chart_h, double height) {
        int ti = -1;
        foreach (var trend in diagram.trends) {
            ti++;
            var origin = positions.get(trend.node_id);
            if (origin == null) continue;
            double tx = project_x(trend.target_x, chart_w);
            double ty = project_y(trend.target_y, height, chart_h);
            double dx = tx - origin.x;
            double dy = ty - origin.y;
            double dist = Math.sqrt(dx * dx + dy * dy);
            // The line stops a node radius plus a 2pt gap short of the target.
            double shorten = NODE_RADIUS + 2;
            double x2 = dist > shorten ? tx - dx / dist * shorten : tx;
            double y2 = dist > shorten ? ty - dy / dist * shorten : ty;
            cv.line(origin.x, origin.y, x2, y2, EVOLUTION_COLOR, 1.0,
                    "wardley_trend_%d".printf(ti), "style=dashed");
            if (dist > 1e-9) {
                chevron(cv, x2, y2, dx / dist, dy / dist, EVOLUTION_COLOR,
                        "wardley_trend_%d_head".printf(ti));
            }
        }
    }

    private void draw_nodes(ChartCanvas cv, MermaidWardley diagram,
                            Gee.HashMap<string, Pos> positions,
                            string comp_fill, string comp_stroke, string text_color) {
        foreach (var node in diagram.nodes) {
            var pos = positions.get(node.id);
            if (pos == null) continue;
            string safe = RenderUtils.sanitize_id(node.id);

            // Sourcing decorator: a wider circle behind the component.
            switch (node.source_strategy) {
                case WardleySourceStrategy.OUTSOURCE:
                    cv.circle(pos.x, pos.y, NODE_RADIUS * 2, "#666666", comp_stroke, 1.0,
                              "wardley_overlay_" + safe);
                    break;
                case WardleySourceStrategy.BUY:
                    cv.circle(pos.x, pos.y, NODE_RADIUS * 2, "#CCCCCC", comp_stroke, 1.0,
                              "wardley_overlay_" + safe);
                    break;
                case WardleySourceStrategy.BUILD:
                    cv.circle(pos.x, pos.y, NODE_RADIUS * 2, "#EEEEEE", comp_stroke, 1.0,
                              "wardley_overlay_" + safe);
                    break;
                case WardleySourceStrategy.MARKET:
                    cv.circle(pos.x, pos.y, NODE_RADIUS * 2, comp_fill, comp_stroke, 1.0,
                              "wardley_overlay_" + safe);
                    break;
                default:
                    break;
            }

            // The component circle: anchors carry a bold label and no circle,
            // pipeline parents a square instead.
            if (node.kind != WardleyNodeKind.ANCHOR && !node.is_pipeline_parent &&
                node.source_strategy != WardleySourceStrategy.MARKET) {
                string name = cv.circle(pos.x, pos.y, NODE_RADIUS, comp_fill, comp_stroke, 1.0,
                                        "wardley_node_" + safe);
                map_region(name, node.id, node.source_line);
            }

            if (node.source_strategy == WardleySourceStrategy.MARKET) {
                draw_market(cv, pos, comp_fill, comp_stroke, safe);
            }

            if (node.is_pipeline_parent) {
                string name = cv.rect(pos.x - SQUARE / 2, pos.y - SQUARE / 2, SQUARE, SQUARE,
                                      comp_fill, comp_stroke, 1.0, "wardley_parent_" + safe);
                map_region(name, node.id, node.source_line);
            }

            if (node.inertia) {
                double offset = node.is_pipeline_parent ? SQUARE / 2 + 15 : NODE_RADIUS + 15;
                if (node.source_strategy != WardleySourceStrategy.NONE) offset += NODE_RADIUS + 10;
                double line_h = node.is_pipeline_parent ? SQUARE : NODE_RADIUS * 2;
                cv.line(pos.x + offset, pos.y - line_h / 2, pos.x + offset, pos.y + line_h / 2,
                        comp_stroke, 6.0, "wardley_inertia_" + safe);
            }

            // Label placement, straight from mermaid's text x/y accessors.
            double lx, ly;
            char align;
            bool bold;
            string color = text_color;
            // Each offset is unboxed in its own statement rather than read
            // inside a conditional: `label_offset_x/y` are boxed `double?`, and
            // valac frees that temporary before the read, which costs the
            // offset at -O2 while looking correct at -O0.
            if (node.kind == WardleyNodeKind.ANCHOR) {
                double off_x = 0, off_y = -3;
                if (node.label_offset_x != null) off_x = (double) node.label_offset_x;
                if (node.label_offset_y != null) off_y = (double) node.label_offset_y;
                lx = pos.x + off_x;
                ly = pos.y + off_y;
                align = 'c';
                bold = true;
            } else {
                double def_x = NODE_LABEL_OFFSET;
                double def_y = -NODE_LABEL_OFFSET;
                if (node.source_strategy != WardleySourceStrategy.NONE) {
                    if (node.label_offset_x == null) def_x += 10;
                    if (node.label_offset_y == null) def_y -= 10;
                }
                double off_x = def_x, off_y = def_y;
                if (node.label_offset_x != null) off_x = (double) node.label_offset_x;
                if (node.label_offset_y != null) off_y = (double) node.label_offset_y;
                lx = pos.x + off_x;
                ly = pos.y + off_y;
                align = 'l';
                bold = false;
            }
            string label_name = cv.text(lx, ly, node.label, LABEL_FONT, color, align, bold,
                                        "wardley_label_" + safe);
            if (node.kind == WardleyNodeKind.ANCHOR) {
                map_region(label_name, node.id, node.source_line);
            }
        }
    }

    // The market decorator: three circles in a triangle, joined by its sides.
    private static void draw_market(ChartCanvas cv, Pos pos, string fill, string stroke, string safe) {
        double small_r = NODE_RADIUS * 0.7;
        double tri_r = NODE_RADIUS * 1.2;
        double cos30 = Math.cos(Math.PI / 6);
        double sin30 = Math.sin(Math.PI / 6);
        double tx = pos.x, ty = pos.y - tri_r;
        double lx = pos.x - tri_r * cos30, lyy = pos.y + tri_r * sin30;
        double rx = pos.x + tri_r * cos30, ryy = pos.y + tri_r * sin30;
        cv.line(tx, ty, lx, lyy, stroke, 1.0, "wardley_market_a_" + safe);
        cv.line(lx, lyy, rx, ryy, stroke, 1.0, "wardley_market_b_" + safe);
        cv.line(rx, ryy, tx, ty, stroke, 1.0, "wardley_market_c_" + safe);
        cv.circle(tx, ty, small_r, fill, stroke, 2.0, "wardley_market_t_" + safe);
        cv.circle(lx, lyy, small_r, fill, stroke, 2.0, "wardley_market_l_" + safe);
        cv.circle(rx, ryy, small_r, fill, stroke, 2.0, "wardley_market_r_" + safe);
    }

    private void draw_annotations(ChartCanvas cv, MermaidWardley diagram, string axis_color,
                                  string text_color, string box_fill,
                                  double width, double height, double chart_w, double chart_h) {
        if (diagram.annotations.size == 0) return;

        int ai = -1;
        foreach (var ann in diagram.annotations) {
            ai++;
            var pts = new Gee.ArrayList<WardleyPoint>();
            foreach (var c in ann.coordinates) {
                pts.add(new WardleyPoint(project_x(c.x, chart_w), project_y(c.y, height, chart_h)));
            }
            for (int i = 0; i + 1 < pts.size; i++) {
                cv.line(pts.get(i).x, pts.get(i).y, pts.get(i + 1).x, pts.get(i + 1).y,
                        axis_color, 1.5, "wardley_ann_line_%d_%d".printf(ai, i), "style=dashed");
            }
            for (int i = 0; i < pts.size; i++) {
                string name = cv.circle(pts.get(i).x, pts.get(i).y, 10, box_fill, axis_color, 1.5,
                                        "wardley_ann_%d_%d".printf(ai, i));
                map_region(name, "annotation %d".printf(ann.number), ann.source_line);
                cv.text(pts.get(i).x, pts.get(i).y, "%d".printf(ann.number), 10, text_color,
                        'c', true, "wardley_ann_num_%d_%d".printf(ai, i));
            }
        }

        if (!diagram.has_annotations_box) return;

        // The legend box, sorted by annotation number, clamped inside the map.
        var texts = new Gee.ArrayList<string>();
        var sorted = new Gee.ArrayList<WardleyAnnotation>();
        sorted.add_all(diagram.annotations);
        sorted.sort((a, b) => a.number - b.number);
        foreach (var a in sorted) {
            if (a.text != null && a.text.length > 0) texts.add("%d. %s".printf(a.number, a.text));
        }
        if (texts.size == 0) return;

        const double BOX_PAD = 10.0;
        const double LINE_H = 16.0;
        const double FONT = 11.0;
        double max_w = 0;
        foreach (string t in texts) max_w = double.max(max_w, ChartCanvas.text_width(t, FONT));
        double box_w = max_w + BOX_PAD * 2;
        double box_h = texts.size * LINE_H + BOX_PAD * 2;

        double box_x = project_x(diagram.annotations_box_x, chart_w);
        double box_y = project_y(diagram.annotations_box_y, height, chart_h);
        box_x = double.max(PADDING, double.min(box_x, width - PADDING - box_w));
        box_y = double.max(PADDING, double.min(box_y, height - PADDING - box_h));

        cv.rect(box_x, box_y, box_w, box_h, box_fill, axis_color, 1.5, "wardley_ann_box");
        for (int i = 0; i < texts.size; i++) {
            cv.text(box_x + BOX_PAD, box_y + BOX_PAD + (i + 0.5) * LINE_H, texts.get(i),
                    FONT, text_color, 'l', false, "wardley_ann_box_line_%d".printf(i));
        }
    }

    /**
     * `accelerator` / `deaccelerator`: a 60 x 30 block arrow with a 20-wide
     * head, pointing right or left, with its name centred below it. ChartCanvas
     * has no filled-polygon primitive, so the seven edges are drawn as lines.
     */
    private void draw_accelerators(ChartCanvas cv, MermaidWardley diagram, string stroke,
                                   string text_color, double chart_w, double chart_h, double height) {
        const double W = 60.0, H = 30.0, HEAD = 20.0;
        int i = -1;
        foreach (var acc in diagram.accelerators) {
            i++;
            double x = project_x(acc.x, chart_w);
            double y = project_y(acc.y, height, chart_h);
            double[] px, py;
            if (!acc.decelerating) {
                px = { x,        x + W - HEAD, x + W - HEAD, x + W, x + W - HEAD, x + W - HEAD, x,       x };
                py = { y - H / 2, y - H / 2,    y - H / 2 - 8, y,     y + H / 2 + 8, y + H / 2,    y + H / 2, y - H / 2 };
            } else {
                px = { x + W,    x + HEAD,     x + HEAD,     x,     x + HEAD,     x + HEAD,     x + W,   x + W };
                py = { y - H / 2, y - H / 2,    y - H / 2 - 8, y,     y + H / 2 + 8, y + H / 2,    y + H / 2, y - H / 2 };
            }
            for (int k = 0; k + 1 < px.length; k++) {
                cv.line(px[k], py[k], px[k + 1], py[k + 1], stroke, 1.0,
                        "wardley_acc_%d_%d".printf(i, k));
            }
            string name = cv.text(x + W / 2, y + H / 2 + 15, acc.name, 10, text_color,
                                  'c', true, "wardley_acc_label_%d".printf(i));
            map_region(name, acc.name, acc.source_line);
        }
    }

    // A ChartCanvas item's DOT node name -> a clickable element, with its line.
    private void map_region(string dot_name, string element, int line) {
        if (dot_name.length == 0 || element.length == 0) return;
        if (region_names.has_key(dot_name)) return;
        region_names.set(dot_name, element);
        if (line > 0 && !element_lines.has_key(element)) element_lines.set(element, line);
    }

    // ==================== output ====================

    public uint8[]? render_to_svg(MermaidWardley diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse wardley DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out wardley graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // ABI-compatible wrapper (patched Graphviz uses size_t, the VAPI unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render wardley graph");
            return null;
        }
        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidWardley diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, DEF_WIDTH, DEF_HEIGHT, out width, out height);

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

            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height, region_names);
            return surface;
        } catch (Error e) {
            warning("Failed to render wardley SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidWardley diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidWardley diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidWardley diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
