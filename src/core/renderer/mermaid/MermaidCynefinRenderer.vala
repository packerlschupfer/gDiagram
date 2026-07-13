/* MermaidCynefinRenderer.vala — Mermaid `cynefin-beta` renderer on a pinned ChartCanvas
 *
 * A port of mermaid 12.2.0's cynefinRenderer.ts + cynefinBoundaries.ts: four
 * domain rectangles, two wavy dashed boundaries through the centre, the thicker
 * "cliff" between Clear and Chaotic, the dashed Confusion ellipse, the domain
 * labels with their decision model and practice subtitles, one rounded badge
 * per item, and quadratic transition arrows between domain centres.
 *
 * The geometry is mermaid's, expressed in points at 0.65 × its pixel scale
 * (the ratio the other pinned Mermaid renderers use), with two differences:
 *
 *   - domain fills come from the active gDiagram palette instead of mermaid's
 *     fixed pastels, so the diagram follows the light/dark theme;
 *   - mermaid seeds the boundary waviness from the SVG element id when no seed
 *     is configured, which makes every render different. We pin the seed so a
 *     render is reproducible (and so the snapshot tests mean something).
 *
 * Graphviz cannot put an arrowhead on an undirected edge, so transitions end in
 * a two-stroke chevron, the same stand-in MermaidTimelineRenderer uses.
 */
namespace GDiagram {

public class MermaidCynefinRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // mermaid's cynefin config defaults (800 × 600 px, 40 px padding) at 0.65.
    private const double W = 520.0;
    private const double H = 390.0;
    private const double PAD = 26.0;

    // Badge metrics in points (mermaid: 26 px high, 10 px side padding).
    private const double ITEM_H = 20.0;
    private const double ITEM_GAP = 4.0;
    private const double ITEM_PAD_X = 7.0;
    private const double ITEM_FONT = 10.0;
    private const double LABEL_FONT = 14.0;
    private const double SUBTITLE_FONT = 9.0;

    // mermaid's MAX_CONFUSION_ITEMS.
    private const int MAX_CONFUSION_ITEMS = 3;

    // A fixed, non-zero boundary seed: reproducible renders (mermaid's
    // `cynefin.seed` config, which takes precedence over the id hash).
    private const int BOUNDARY_SEED = 1;

    private Gee.HashMap<string, string> region_names = new Gee.HashMap<string, string>();
    private Gee.HashMap<string, int> element_lines = new Gee.HashMap<string, int>();

    public MermaidCynefinRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    private void note_region(string node, string region, int line) {
        if (node.length == 0) return;
        region_names.set(node, region);
        if (line > 0) element_lines.set(region, line);
    }

    // ── cynefinBoundaries.ts ─────────────────────────────────────

    /** mulberry32, exactly as cynefinBoundaries.ts computes it (32-bit wrapping). */
    public static double seeded_random(int seed) {
        uint32 t = (uint32) seed + 0x6d2b79f5u;
        t = (t ^ (t >> 15)) * (t | 1u);
        t ^= t + (t ^ (t >> 7)) * (t | 61u);
        return (double) (t ^ (t >> 14)) / 4294967296.0;
    }

    /** Domain centres and boxes: getDomainLayouts(width, height). */
    internal static void domain_box(CynefinDomainName name, out double x, out double y,
                                    out double w, out double h,
                                    out double cx, out double cy) {
        double hw = W / 2, hh = H / 2;
        switch (name) {
            case CynefinDomainName.COMPLEX:
                x = 0;  y = 0;  w = hw; h = hh; break;
            case CynefinDomainName.COMPLICATED:
                x = hw; y = 0;  w = hw; h = hh; break;
            case CynefinDomainName.CHAOTIC:
                x = 0;  y = hh; w = hw; h = hh; break;
            case CynefinDomainName.CLEAR:
                x = hw; y = hh; w = hw; h = hh; break;
            default:
                x = hw * 0.7; y = hh * 0.7; w = hw * 0.6; h = hh * 0.6; break;
        }
        if (name == CynefinDomainName.CONFUSION) {
            cx = hw;
            cy = hh;
        } else {
            cx = x + w / 2;
            cy = y + h / 2;
        }
    }

    /** The domain fill, from the active palette (mermaid uses fixed pastels). */
    private static string domain_fill(CynefinDomainName name, Palette p) {
        switch (name) {
            case CynefinDomainName.COMPLEX:     return p.success;
            case CynefinDomainName.COMPLICATED: return p.container_fill;
            case CynefinDomainName.CHAOTIC:     return p.warning;
            case CynefinDomainName.CLEAR:       return p.accent_secondary;
            default:                            return p.accent_primary;
        }
    }

    // #RRGGBB + an alpha byte; Graphviz understands #RRGGBBAA.
    private static string translucent(string color, string alpha) {
        // `cond ? color + alpha : color` would be fine here — a single,
        // non-nested conditional mixing an owned and an unowned branch is
        // safe. This is just spelled out for symmetry with the sites that
        // genuinely cannot use one (a conditional nested inside another).
        if (color.length == 7 && color.has_prefix("#")) return color + alpha;
        return color;
    }

    /**
     * generateFoldPath: a vertical wavy line through the centre, as 7 cubic
     * segments whose control points alternate sides.
     */
    private static void fold_path(ChartCanvas cv, string color, int seed) {
        double cx = W / 2;
        double amplitude = W * 0.015;
        const int SEGMENTS = 7;
        double seg = H / SEGMENTS;
        double[] px = new double[SEGMENTS + 1];
        double[] py = new double[SEGMENTS + 1];
        for (int i = 0; i <= SEGMENTS; i++) {
            double jitter = seeded_random(seed + i * 17) * amplitude * 2 - amplitude;
            px[i] = cx + jitter;
            py[i] = i * seg;
        }
        for (int i = 0; i < SEGMENTS; i++) {
            double mid_y = (py[i] + py[i + 1]) / 2;
            double dir = i % 2 == 0 ? 1 : -1;
            double offset = amplitude * 1.5 * dir * seeded_random(seed + i * 31 + 7);
            cv.bezier(px[i], py[i], px[i] + offset, mid_y,
                      px[i + 1] - offset, mid_y, px[i + 1], py[i + 1],
                      color, 1.0, "cyn_fold_%d".printf(i), "style=dashed");
        }
    }

    /** generateHorizontalBoundary: the same, horizontally. */
    private static void horizontal_boundary(ChartCanvas cv, string color, int seed) {
        double cy = H / 2;
        double amplitude = H * 0.015;
        const int SEGMENTS = 7;
        double seg = W / SEGMENTS;
        double[] px = new double[SEGMENTS + 1];
        double[] py = new double[SEGMENTS + 1];
        for (int i = 0; i <= SEGMENTS; i++) {
            double jitter = seeded_random(seed + i * 23) * amplitude * 2 - amplitude;
            px[i] = i * seg;
            py[i] = cy + jitter;
        }
        for (int i = 0; i < SEGMENTS; i++) {
            double mid_x = (px[i] + px[i + 1]) / 2;
            double dir = i % 2 == 0 ? 1 : -1;
            double offset = amplitude * 1.5 * dir * seeded_random(seed + i * 37 + 11);
            cv.bezier(px[i], py[i], mid_x, py[i] + offset,
                      mid_x, py[i + 1] - offset, px[i + 1], py[i + 1],
                      color, 1.0, "cyn_hbound_%d".printf(i), "style=dashed");
        }
    }

    /** generateCliffPath: the abrupt boundary between Clear and Chaotic. */
    private static void cliff_path(ChartCanvas cv, string color) {
        double cx = W / 2;
        double top_y = H * 0.5;
        double bottom_y = H;
        double span = bottom_y - top_y;
        double a = W * 0.03;
        cv.bezier(cx, top_y,
                  cx + a, top_y + span * 0.2,
                  cx - a * 1.5, top_y + span * 0.55,
                  cx + a * 0.5, top_y + span * 0.75,
                  color, 2.5, "cyn_cliff_0");
        cv.bezier(cx + a * 0.5, top_y + span * 0.75,
                  cx - a, top_y + span * 0.85,
                  cx + a * 0.3, top_y + span * 0.95,
                  cx, bottom_y,
                  color, 2.5, "cyn_cliff_1");
    }

    // A ">" chevron at (x, y) pointing along (dx, dy).
    private static void arrow_head(ChartCanvas cv, double x, double y,
                                   double dx, double dy, string color, string id) {
        double len = Math.sqrt(dx * dx + dy * dy);
        if (len < 1e-9) return;
        double ux = dx / len, uy = dy / len;
        double size = 7.0;
        double spread = 0.45;   // ~26°
        double c = Math.cos(spread), s = Math.sin(spread);
        // Back along the direction, rotated ± spread.
        double b1x = x - size * (ux * c - uy * s);
        double b1y = y - size * (uy * c + ux * s);
        double b2x = x - size * (ux * c + uy * s);
        double b2y = y - size * (uy * c - ux * s);
        cv.line(b1x, b1y, x, y, color, 1.8, id + "_a");
        cv.line(b2x, b2y, x, y, color, 1.8, id + "_b");
    }

    // ── cynefinRenderer.ts ───────────────────────────────────────

    public string generate_dot(MermaidCynefin diagram) {
        var palette = ThemeManager.get_active_palette();
        var cv = new ChartCanvas();
        cv.margin = PAD;
        region_names = new Gee.HashMap<string, string>();
        element_lines = new Gee.HashMap<string, int>();

        string text_color = palette.node_text;
        string boundary_color = palette.edge_color;

        CynefinDomainName[] quadrants = {
            CynefinDomainName.COMPLEX, CynefinDomainName.COMPLICATED,
            CynefinDomainName.CHAOTIC, CynefinDomainName.CLEAR
        };

        // 1. Domain background rectangles (fill-opacity 0.4).
        foreach (var name in quadrants) {
            double x, y, w, h, cx, cy;
            domain_box(name, out x, out y, out w, out h, out cx, out cy);
            string fill = translucent(domain_fill(name, palette), "66");
            string node = cv.rect(x, y, w, h, fill, fill, 0,
                "cyn_domain_" + name.id());
            var declared = diagram.find_domain(name);
            note_region(node, name.id(), declared != null ? declared.source_line : 0);
        }

        // 2. Wavy boundaries and 3. the cliff.
        fold_path(cv, boundary_color, BOUNDARY_SEED);
        horizontal_boundary(cv, boundary_color, BOUNDARY_SEED + 100);
        cliff_path(cv, palette.accent_primary);

        // 4. Confusion ellipse (width*0.15 × height*0.15 radii).
        double rx = W * 0.15, ry = H * 0.15;
        string confusion_fill = translucent(domain_fill(CynefinDomainName.CONFUSION, palette), "80");
        string confusion_node = cv.shape(W / 2, H / 2, rx * 2, ry * 2,
            "id=\"cyn_confusion\" shape=ellipse style=\"filled,dashed\" fillcolor=\"%s\" color=\"%s\" penwidth=1.5 label=\"\""
                .printf(confusion_fill, boundary_color));
        var confusion_domain = diagram.find_domain(CynefinDomainName.CONFUSION);
        note_region(confusion_node, "confusion",
            confusion_domain != null ? confusion_domain.source_line : 0);

        // 5./6. Domain labels with the decision model and practice subtitles.
        // The three lines need their own height: a 14 pt label box is 22 pt
        // tall and a 9 pt subtitle 14 pt, so mermaid's -30/-10/+5 pixel offsets
        // would overlap at these sizes.
        foreach (var name in quadrants) {
            double x, y, w, h, cx, cy;
            domain_box(name, out x, out y, out w, out h, out cx, out cy);
            cv.text(cx, cy - 26, name.label(), LABEL_FONT, text_color, 'c', true,
                "cyn_label_" + name.id());
            cv.text(cx, cy - 9, name.decision_model(), SUBTITLE_FONT, text_color, 'c', false,
                "cyn_model_" + name.id(), true);
            cv.text(cx, cy + 5, name.practice(), SUBTITLE_FONT, text_color, 'c', false,
                "cyn_practice_" + name.id(), true);
        }
        cv.text(W / 2, H / 2 - 16, CynefinDomainName.CONFUSION.label(), LABEL_FONT,
            text_color, 'c', true, "cyn_label_confusion");
        cv.text(W / 2, H / 2 + 1, CynefinDomainName.CONFUSION.practice(), SUBTITLE_FONT,
            text_color, 'c', false, "cyn_practice_confusion", true);

        // 7. Item badges.
        foreach (var domain in diagram.domains) {
            if (domain.items.size == 0) continue;
            double x, y, w, h, cx, cy;
            domain_box(domain.name, out x, out y, out w, out h, out cx, out cy);
            bool is_confusion = domain.name == CynefinDomainName.CONFUSION;

            int shown = domain.items.size;
            int overflow = 0;
            if (is_confusion && shown > MAX_CONFUSION_ITEMS) {
                overflow = shown - MAX_CONFUSION_ITEMS;
                shown = MAX_CONFUSION_ITEMS;
            }
            double start_y = cy + (is_confusion ? 14 : 18);
            string solid = domain_fill(domain.name, palette);
            string fill = translucent(solid, "F2");
            // The badge is nearly opaque, so its text takes the fill's contrast
            // colour — the palette's node text is unreadable on a light domain.
            string badge_text = RenderUtils.contrast_text(solid);

            for (int idx = 0; idx < shown; idx++) {
                var item = domain.items.get(idx);
                double item_y = start_y + idx * (ITEM_H + ITEM_GAP);
                double badge_w = ChartCanvas.text_width(item.label, ITEM_FONT) + ITEM_PAD_X * 2;
                string node = cv.rect(cx - badge_w / 2, item_y, badge_w, ITEM_H,
                    fill, boundary_color, 1.0,
                    "cyn_item_%s_%d".printf(domain.name.id(), idx));
                note_region(node, "%s_item_%d".printf(domain.name.id(), idx), item.source_line);
                cv.text(cx, item_y + ITEM_H / 2, item.label, ITEM_FONT, badge_text, 'c', false,
                    "cyn_item_text_%s_%d".printf(domain.name.id(), idx));
            }
            if (overflow > 0) {
                string label = "+%d more".printf(overflow);
                double item_y = start_y + shown * (ITEM_H + ITEM_GAP);
                double badge_w = ChartCanvas.text_width(label, ITEM_FONT) + ITEM_PAD_X * 2;
                cv.rect(cx - badge_w / 2, item_y, badge_w, ITEM_H,
                    translucent(solid, "99"), boundary_color, 1.0,
                    "cyn_item_overflow", "style=\"filled,dashed\"");
                cv.text(cx, item_y + ITEM_H / 2, label, ITEM_FONT, badge_text, 'c', false,
                    "cyn_item_overflow_text");
            }
        }

        // 8. Transition arrows: a quadratic Bézier offset perpendicular to the chord.
        for (int t = 0; t < diagram.transitions.size; t++) {
            var tr = diagram.transitions.get(t);
            double fx, fy, fw, fh, x1, y1;
            double tx, ty, tw, th, x2, y2;
            domain_box(tr.from_domain, out fx, out fy, out fw, out fh, out x1, out y1);
            domain_box(tr.to_domain, out tx, out ty, out tw, out th, out x2, out y2);

            double mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
            double dx = x2 - x1, dy = y2 - y1;
            double len = Math.sqrt(dx * dx + dy * dy);
            if (len < 1e-9) continue;
            double offset = len * 0.15;
            double cpx = mx + (-dy / len) * offset;
            double cpy = my + (dx / len) * offset;

            // Quadratic (p0, q, p1) as a cubic: c1 = p0 + 2/3·(q - p0), c2 = p1 + 2/3·(q - p1).
            double c1x = x1 + 2.0 / 3.0 * (cpx - x1);
            double c1y = y1 + 2.0 / 3.0 * (cpy - y1);
            double c2x = x2 + 2.0 / 3.0 * (cpx - x2);
            double c2y = y2 + 2.0 / 3.0 * (cpy - y2);
            string arrow_id = "cyn_arrow_%d".printf(t);
            cv.bezier(x1, y1, c1x, c1y, c2x, c2y, x2, y2,
                palette.edge_text, 1.5, arrow_id);
            arrow_head(cv, x2, y2, x2 - cpx, y2 - cpy, palette.edge_text, arrow_id + "_head");

            if (tr.label != null && tr.label.length > 0) {
                cv.text(cpx, cpy - 6, tr.label, ITEM_FONT, palette.edge_text, 'c', false,
                    "cyn_arrow_label_%d".printf(t));
            }
        }

        // Title, at -padding/2 above the grid.
        if (diagram.title != null && diagram.title.length > 0) {
            cv.text(W / 2, -PAD / 2, diagram.title, 16, text_color, 'c', true, "cyn_title");
        }

        return cv.finish("cynefin", palette.background);
    }

    public uint8[]? render_to_svg(MermaidCynefin diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse cynefin DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out cynefin graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render cynefin graph");
            return null;
        }
        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidCynefin diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, W + 2 * PAD, H + 2 * PAD, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
            var cr = new Cairo.Context(surface);
            cr.set_source_rgb(1, 1, 1);
            cr.paint();

            var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
            handle.render_document(cr, viewport);

            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height, region_names);
            return surface;
        } catch (Error e) {
            warning("Failed to render cynefin SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidCynefin diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidCynefin diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidCynefin diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
