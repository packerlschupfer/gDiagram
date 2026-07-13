/* MermaidVennRenderer.vala — Mermaid `venn-beta` renderer on a pinned ChartCanvas
 *
 * The circle layout is VennLayout.vala, a port of @upsetjs/venn.js 2.0.0 (MIT,
 * attribution in that file) — the same library mermaid 12.2.0 drives. Drawing
 * follows mermaid's vennRenderer.ts:
 *
 *   - one translucent, thickly stroked circle per `set`, its label at the
 *     maximum-margin point inside it;
 *   - union labels at the maximum-margin point of their intersection, with no
 *     fill unless a `style` gives one (mermaid draws those paths with
 *     fill-opacity 0);
 *   - `text` nodes in a grid inside the area they belong to.
 *
 * Differences from mermaid, all deliberate:
 *   - Graphviz cannot fill an arbitrary circle-intersection lens, so a `style`
 *     that sets `fill` on a *union* tints that union's label instead of the
 *     lens. Set fills and strokes are honoured exactly.
 *   - mermaid's text nodes use a `foreignObject` with CSS word wrapping; we
 *     place one text line per node in the same grid cell (no soft wrapping).
 *   - the canvas is in points at 0.65 × mermaid's pixel size, and font sizes
 *     come from the house scale rather than 48 × (width/1600).
 */
namespace GDiagram {

public class MermaidVennRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // mermaid's venn config defaults (800 × 450 px, padding 15) at 0.65.
    private const double PAGE_W = 520.0;
    private const double PAGE_H = 292.0;
    private const double PADDING = 10.0;
    private const double SET_FONT = 15.0;
    private const double UNION_FONT = 12.0;
    private const double TEXT_FONT = 10.0;
    private const double TITLE_FONT = 16.0;
    private const double STROKE_WIDTH = 2.5;

    private Gee.HashMap<string, string> region_names = new Gee.HashMap<string, string>();
    private Gee.HashMap<string, int> element_lines = new Gee.HashMap<string, int>();

    public MermaidVennRenderer(Gvc.Context ctx,
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

    /** themeVariables.venn1..venn8, mapped onto palette roles. */
    private static string[] set_colors(Palette p) {
        return {
            p.container_fill, p.success, p.accent_secondary, p.warning,
            p.person_fill, p.system_fill, p.component_fill, p.database_fill
        };
    }

    /** The areas handed to the layout: the AST's subsets plus the synthetic pairs. */
    public static Gee.ArrayList<VennArea> layout_areas(MermaidVenn diagram) {
        var areas = new Gee.ArrayList<VennArea>();
        foreach (var s in diagram.subsets) {
            areas.add(new VennArea(venn_string_array(s.sets), s.size));
        }
        return VennLayout.ensure_pairwise(areas);
    }

    /** The laid-out solution for a given canvas, exposed for the fidelity tests. */
    public static VennSolution layout(MermaidVenn diagram, double width, double height,
                                      double padding) {
        return VennLayout.compute(layout_areas(diagram), width, height, padding);
    }

    public string generate_dot(MermaidVenn diagram) {
        var palette = ThemeManager.get_active_palette();
        var cv = new ChartCanvas();
        region_names = new Gee.HashMap<string, string>();
        element_lines = new Gee.HashMap<string, int>();
        string text_color = palette.node_text;

        bool has_title = diagram.title != null && diagram.title.length > 0;
        double title_h = has_title ? 28 : 0;

        // scaleSolution centres the circles inside the page, so the page has to
        // be the page: ChartCanvas otherwise sizes it from the drawn items
        // (always including the origin) and the whole diagram slides right.
        cv.rect(0, 0, PAGE_W, title_h + PAGE_H, palette.background, palette.background, 0,
            "venn_page");

        if (diagram.sets().size == 0) {
            if (has_title) {
                cv.text(PAGE_W / 2, 14, diagram.title, TITLE_FONT, text_color, 'c', true, "venn_title");
            }
            cv.text(PAGE_W / 2, title_h + 20, "(no sets defined)", 11, text_color, 'c');
            return cv.finish("venn", palette.background);
        }

        if (has_title) {
            string node = cv.text(PAGE_W / 2, 14, diagram.title, TITLE_FONT, text_color,
                'c', true, "venn_title");
            note_region(node, "_venn_title", 0);
        }

        var solution = layout(diagram, PAGE_W, PAGE_H - title_h, PADDING);
        string[] colors = set_colors(palette);

        // Set circles, in declaration order so the palette index matches mermaid's.
        var sets = diagram.sets();
        for (int i = 0; i < sets.size; i++) {
            var subset = sets.get(i);
            var circle = solution.get_circle(subset.sets.get(0));
            if (circle == null) continue;
            var style = diagram.styles_for(subset.key());

            // Plain if/else purely as a style choice — a single, non-nested
            // `cond ? a : b` mixing owned and unowned branches is perfectly
            // safe (valac gives the result an owned temporary and g_strdup's
            // the unowned branch). Don't "fix" this back to a conditional
            // expecting a bug; the real one is at the label block below.
            string base_color = colors[i % colors.length];
            if (style.has_key("fill")) base_color = normalize_color(style.get("fill"));
            string stroke = base_color;
            if (style.has_key("stroke")) stroke = normalize_color(style.get("stroke"));
            double pen = STROKE_WIDTH;
            if (style.has_key("stroke-width")) {
                double w = double.parse(style.get("stroke-width"));
                if (w > 0) pen = w;
            }
            string fill = base_color;
            if (base_color.has_prefix("#") && base_color.length == 7) {
                fill = base_color + "1A";   // fill-opacity 0.1
            }

            string node = cv.circle(circle.x, circle.y + title_h, circle.radius,
                fill, stroke, pen, "venn_circle_" + safe_id(subset.key()));
            note_region(node, subset.key(), subset.source_line);
        }

        // Labels: set labels first, then union labels, as mermaid's z-order has them.
        foreach (var subset in diagram.subsets) {
            string key = subset.key();
            if (!solution.text_x.has_key(key)) continue;
            double tx = solution.text_x.get(key);
            double ty = solution.text_y.get(key);
            if (tx <= -1e8) continue;   // computeTextCentre: area not on screen

            // Three statements, NOT the conditional this used to be:
            //
            //   subset.label != null && subset.label.length > 0
            //       ? subset.label
            //       : (subset.is_set() ? subset.sets.get(0) : key.replace("|", " ∩ "))
            //
            // That is a conditional nested inside another conditional. The
            // outer one has an unowned branch (the `label` property read), so
            // valac types its result `const gchar*`; the inner one has owned
            // branches (Gee's get(), string.replace()), so valac gives it its
            // own `gchar*`, aliases that into the unowned outer temporary and
            // frees it at the end of the branch. The result is read after free
            // — it put recycled heap bytes into the DOT labels, which Pango
            // then refused. It fires whichever inner branch actually runs.
            // Vala 0.56.18; see the Vala gotchas note on nested conditionals.
            string label = key.replace("|", " ∩ ");
            if (subset.is_set()) label = subset.sets.get(0);
            if (subset.label != null && subset.label.length > 0) label = subset.label;
            if (label.length == 0) continue;

            var style = diagram.styles_for(key);
            string color = text_color;
            if (style.has_key("color")) color = normalize_color(style.get("color"));
            double font = subset.is_set() ? SET_FONT : UNION_FONT;
            string node = cv.text(tx, ty + title_h, label, font, color, 'c',
                subset.is_set(), "venn_label_" + safe_id(key));
            if (!subset.is_set()) note_region(node, key, subset.source_line);
        }

        draw_text_nodes(cv, diagram, solution, title_h, text_color);

        return cv.finish("venn", palette.background);
    }

    /**
     * renderTextNodes: group the `text` nodes by area and lay each group out in
     * a ⌈√n⌉-column grid inside the area's inner radius, below its own label.
     */
    private void draw_text_nodes(ChartCanvas cv, MermaidVenn diagram, VennSolution solution,
                                 double title_h, string text_color) {
        if (diagram.text_nodes.size == 0) return;

        var keys = new Gee.ArrayList<string>();
        var by_area = new Gee.HashMap<string, Gee.ArrayList<VennTextNode>>();
        foreach (var node in diagram.text_nodes) {
            string key = node.key();
            if (!by_area.has_key(key)) {
                by_area.set(key, new Gee.ArrayList<VennTextNode>());
                keys.add(key);
            }
            by_area.get(key).add(node);
        }

        foreach (string key in keys) {
            if (!solution.text_x.has_key(key)) continue;
            double center_x = solution.text_x.get(key);
            double center_y = solution.text_y.get(key);
            if (center_x <= -1e8) continue;

            var members = new Gee.ArrayList<VennCircle>();
            foreach (string setid in key.split("|")) {
                var c = solution.get_circle(setid);
                if (c != null) members.add(c);
            }
            if (members.size == 0) continue;

            double min_radius = double.MAX;
            double inner_radius = double.MAX;
            foreach (var c in members) {
                min_radius = double.min(min_radius, c.radius);
                inner_radius = double.min(inner_radius,
                    c.radius - VennLayout.distance(center_x, center_y, c.x, c.y));
            }
            if (inner_radius < 0) inner_radius = 0;
            if (inner_radius == 0) inner_radius = min_radius * 0.6;

            var nodes = by_area.get(key);
            double inner_w = double.max(52, inner_radius * 2 * 0.95);
            double inner_h = double.max(39, inner_radius * 2 * 0.95);
            var subset = diagram.find_subset(key);
            bool has_label = subset != null && subset.label != null && subset.label.length > 0;
            double label_offset = (has_label ? double.min(21, inner_radius * 0.25) : 0)
                                + (nodes.size <= 2 ? 19 : 0);
            double start_x = center_x - inner_w / 2;
            double start_y = center_y - inner_h / 2 + label_offset;
            int cols = (int) double.max(1, Math.ceil(Math.sqrt(nodes.size)));
            int rows = (int) double.max(1, Math.ceil((double) nodes.size / cols));
            double cell_w = inner_w / cols;
            double cell_h = inner_h / rows;

            for (int i = 0; i < nodes.size; i++) {
                var node = nodes.get(i);
                int col = i % cols;
                int row = i / cols;
                double x = start_x + cell_w * (col + 0.5);
                double y = start_y + cell_h * (row + 0.5);
                var style = diagram.styles_for(node.id);
                string color = text_color;
                if (style.has_key("color")) color = normalize_color(style.get("color"));
                string drawn = cv.text(x, y + title_h, node.display_label(), TEXT_FONT,
                    color, 'c', false, "venn_text_" + safe_id(node.id));
                note_region(drawn, node.id, node.source_line);
            }
        }
    }

    /**
     * Graphviz takes `#` only for hex codes, never for a named colour, so a
     * `#red` from the parser must lose its `#` while `#FF0000` keeps it.
     */
    private static string normalize_color(string color) {
        string c = color.strip();
        if (!c.has_prefix("#")) return c;
        string body = c.substring(1);
        bool hex = body.length == 3 || body.length == 4 || body.length == 6 || body.length == 8;
        if (hex) {
            for (int i = 0; i < body.length; i++) {
                if (!body[i].isxdigit()) { hex = false; break; }
            }
        }
        return hex ? c : body;
    }

    /** A DOT-safe element id from a set key. */
    private static string safe_id(string key) {
        var sb = new StringBuilder();
        for (int i = 0; i < key.length; i++) {
            char c = key[i];
            sb.append_c(c.isalnum() || c == '_' ? c : '_');
        }
        return sb.str;
    }

    public uint8[]? render_to_svg(MermaidVenn diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse venn DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out venn graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render venn graph");
            return null;
        }
        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidVenn diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, PAGE_W, PAGE_H, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
            var cr = new Cairo.Context(surface);
            cr.set_source_rgb(1, 1, 1);
            cr.paint();

            var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
            handle.render_document(cr, viewport);

            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height, region_names);
            return surface;
        } catch (Error e) {
            warning("Failed to render venn SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidVenn diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidVenn diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidVenn diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
