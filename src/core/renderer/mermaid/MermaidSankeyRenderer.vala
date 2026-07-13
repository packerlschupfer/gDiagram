/* MermaidSankeyRenderer.vala — renders Mermaid sankey-beta diagrams
 *
 * A port of d3-sankey 0.12.3 (the layout Mermaid 11.17 uses) rather than a
 * Graphviz layout: nodes become thin vertical bars placed in depth columns and
 * sized by their value, and links become curved ribbons whose thickness is
 * proportional to their value. The geometry is computed here and pinned
 * through ChartCanvas (layout=nop2); Graphviz only draws it.
 */
namespace GDiagram {

public class MermaidSankeyRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Mermaid's sankey config defaults (px).
    private const double EXTENT_W = 600;
    private const double EXTENT_H = 400;
    private const double NODE_WIDTH = 10;
    private const double NODE_PADDING = 12;
    private const double VALUE_PADDING = 15;   // extra gap when showValues
    private const int ITERATIONS = 6;
    private const double FONT = 12;

    // Per-node fill rotates through these palette role slots.
    private string[] node_colors_from_palette(Palette p) {
        return { p.container_fill, p.success, p.accent_secondary, p.warning, p.person_fill,
                 p.system_fill, p.component_fill, p.database_fill, p.external_fill, p.accent_primary };
    }

    private class SNode : Object {
        public int index;
        public string name;
        public double value;
        public int depth;
        public int height;
        public int layer;
        public double x0;
        public double x1;
        public double y0;
        public double y1;
        public Gee.ArrayList<SLink> source_links = new Gee.ArrayList<SLink>();
        public Gee.ArrayList<SLink> target_links = new Gee.ArrayList<SLink>();
    }

    private class SLink : Object {
        public int index;
        public SNode source;
        public SNode target;
        public double value;
        public double width;
        public double y0;
        public double y1;
        public int source_line;
    }

    // Layout state, kept between generate_dot() and the SVG post-pass.
    private Gee.ArrayList<SLink> laid_links = new Gee.ArrayList<SLink>();
    private Gee.HashMap<string, string> region_names = new Gee.HashMap<string, string>();
    private Gee.HashMap<string, int> element_lines = new Gee.HashMap<string, int>();
    private string[] link_colors = {};

    public MermaidSankeyRenderer(Gvc.Context ctx,
                                  Gee.ArrayList<ElementRegion> regions,
                                  string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // ==================== d3-sankey ====================

    private static double sum_value(Gee.ArrayList<SLink> links) {
        double s = 0;
        foreach (var l in links) s += l.value;
        return s;
    }

    // depth: rounds of "every node, then everything downstream of it".
    private static void compute_depths(Gee.ArrayList<SNode> nodes, bool forward) {
        var current = new Gee.HashSet<SNode>();
        foreach (var n in nodes) current.add(n);
        int x = 0;
        while (current.size > 0) {
            var next = new Gee.HashSet<SNode>();
            foreach (var node in current) {
                if (forward) node.depth = x;
                else node.height = x;
                foreach (var l in forward ? node.source_links : node.target_links) {
                    next.add(forward ? l.target : l.source);
                }
            }
            if (++x > nodes.size) break;   // circular link
            current = next;
        }
    }

    private static void reorder_links(Gee.ArrayList<SNode> nodes) {
        foreach (var node in nodes) {
            node.source_links.sort((a, b) => cmp_breadth(a.target, b.target, a.index, b.index));
            node.target_links.sort((a, b) => cmp_breadth(a.source, b.source, a.index, b.index));
        }
    }

    private static void reorder_node_links(SNode node) {
        foreach (var l in node.target_links) {
            l.source.source_links.sort((a, b) => cmp_breadth(a.target, b.target, a.index, b.index));
        }
        foreach (var l in node.source_links) {
            l.target.target_links.sort((a, b) => cmp_breadth(a.source, b.source, a.index, b.index));
        }
    }

    private static int cmp_breadth(SNode a, SNode b, int ia, int ib) {
        if (a.y0 < b.y0) return -1;
        if (a.y0 > b.y0) return 1;
        return ia - ib;
    }

    private static double target_top(SNode source, SNode target, double py) {
        double y = source.y0 - (source.source_links.size - 1) * py / 2;
        foreach (var l in source.source_links) {
            if (l.target == target) break;
            y += l.width + py;
        }
        foreach (var l in target.target_links) {
            if (l.source == source) break;
            y -= l.width;
        }
        return y;
    }

    private static double source_top(SNode source, SNode target, double py) {
        double y = target.y0 - (target.target_links.size - 1) * py / 2;
        foreach (var l in target.target_links) {
            if (l.source == source) break;
            y += l.width + py;
        }
        foreach (var l in source.source_links) {
            if (l.target == target) break;
            y -= l.width;
        }
        return y;
    }

    private static void collisions_down(Gee.ArrayList<SNode> col, double y, int i, double alpha, double py) {
        for (; i < col.size; i++) {
            var node = col.get(i);
            double dy = (y - node.y0) * alpha;
            if (dy > 1e-6) { node.y0 += dy; node.y1 += dy; }
            y = node.y1 + py;
        }
    }

    private static void collisions_up(Gee.ArrayList<SNode> col, double y, int i, double alpha, double py) {
        for (; i >= 0; i--) {
            var node = col.get(i);
            double dy = (node.y1 - y) * alpha;
            if (dy > 1e-6) { node.y0 -= dy; node.y1 -= dy; }
            y = node.y0 - py;
        }
    }

    private static void resolve_collisions(Gee.ArrayList<SNode> col, double alpha, double py, double y0, double y1) {
        if (col.size == 0) return;
        int i = col.size >> 1;
        var subject = col.get(i);
        collisions_up(col, subject.y0 - py, i - 1, alpha, py);
        collisions_down(col, subject.y1 + py, i + 1, alpha, py);
        collisions_up(col, y1, col.size - 1, alpha, py);
        collisions_down(col, y0, 0, alpha, py);
    }

    private static void sort_by_breadth(Gee.ArrayList<SNode> col) {
        col.sort((a, b) => a.y0 < b.y0 ? -1 : (a.y0 > b.y0 ? 1 : 0));
    }

    /** The full d3-sankey pipeline; fills in x0/x1/y0/y1 and the link breadths. */
    private static void layout_sankey(Gee.ArrayList<SNode> nodes, Gee.ArrayList<SLink> links,
                                      double dx, double dy, double ex_w, double ex_h) {
        if (nodes.size == 0) return;
        for (int i = 0; i < nodes.size; i++) nodes.get(i).index = i;
        for (int i = 0; i < links.size; i++) {
            var l = links.get(i);
            l.index = i;
            l.source.source_links.add(l);
            l.target.target_links.add(l);
        }
        foreach (var n in nodes) {
            n.value = double.max(sum_value(n.source_links), sum_value(n.target_links));
        }
        compute_depths(nodes, true);
        compute_depths(nodes, false);

        // computeNodeLayers, with the "justify" alignment Mermaid defaults to.
        int max_depth = 0;
        foreach (var n in nodes) max_depth = int.max(max_depth, n.depth);
        int cols = max_depth + 1;
        double kx = cols > 1 ? (ex_w - dx) / (cols - 1) : 0;
        var columns = new Gee.ArrayList<Gee.ArrayList<SNode>>();
        for (int i = 0; i < cols; i++) columns.add(new Gee.ArrayList<SNode>());
        foreach (var n in nodes) {
            int i = n.source_links.size > 0 ? n.depth : cols - 1;
            i = int.max(0, int.min(cols - 1, i));
            n.layer = i;
            n.x0 = i * kx;
            n.x1 = n.x0 + dx;
            columns.get(i).add(n);
        }

        int max_len = 1;
        foreach (var c in columns) max_len = int.max(max_len, c.size);
        double py = max_len > 1 ? double.min(dy, ex_h / (max_len - 1)) : dy;

        // initializeNodeBreadths
        double ky = double.MAX;
        foreach (var c in columns) {
            double s = 0;
            foreach (var n in c) s += n.value;
            if (s <= 0) continue;
            ky = double.min(ky, (ex_h - (c.size - 1) * py) / s);
        }
        // ky is 0 when the widest column already fills the extent with padding
        // alone; d3 lets that collapse every bar, and Mermaid renders it that
        // way, so don't "fix" it here.
        if (ky == double.MAX) ky = 0;
        foreach (var c in columns) {
            double y = 0;
            foreach (var node in c) {
                node.y0 = y;
                node.y1 = y + node.value * ky;
                y = node.y1 + py;
                foreach (var l in node.source_links) l.width = l.value * ky;
            }
            y = (ex_h - y + py) / (c.size + 1);
            for (int i = 0; i < c.size; i++) {
                c.get(i).y0 += y * (i + 1);
                c.get(i).y1 += y * (i + 1);
            }
            reorder_links(c);
        }

        for (int it = 0; it < ITERATIONS; it++) {
            double alpha = Math.pow(0.99, it);
            double beta = double.max(1 - alpha, (it + 1.0) / ITERATIONS);
            // relaxRightToLeft
            for (int i = columns.size - 2; i >= 0; i--) {
                var col = columns.get(i);
                foreach (var source in col) {
                    double y = 0, w = 0;
                    foreach (var l in source.source_links) {
                        double v = l.value * (l.target.layer - source.layer);
                        y += source_top(source, l.target, py) * v;
                        w += v;
                    }
                    if (!(w > 0)) continue;
                    double d = (y / w - source.y0) * alpha;
                    source.y0 += d;
                    source.y1 += d;
                    reorder_node_links(source);
                }
                sort_by_breadth(col);
                resolve_collisions(col, beta, py, 0, ex_h);
            }
            // relaxLeftToRight
            for (int i = 1; i < columns.size; i++) {
                var col = columns.get(i);
                foreach (var target in col) {
                    double y = 0, w = 0;
                    foreach (var l in target.target_links) {
                        double v = l.value * (target.layer - l.source.layer);
                        y += target_top(l.source, target, py) * v;
                        w += v;
                    }
                    if (!(w > 0)) continue;
                    double d = (y / w - target.y0) * alpha;
                    target.y0 += d;
                    target.y1 += d;
                    reorder_node_links(target);
                }
                sort_by_breadth(col);
                resolve_collisions(col, beta, py, 0, ex_h);
            }
        }

        // computeLinkBreadths
        foreach (var node in nodes) {
            double y0 = node.y0, y1 = node.y0;
            foreach (var l in node.source_links) {
                l.y0 = y0 + l.width / 2;
                y0 += l.width;
            }
            foreach (var l in node.target_links) {
                l.y1 = y1 + l.width / 2;
                y1 += l.width;
            }
        }
    }

    // ==================== drawing ====================

    public string generate_dot(MermaidSankey diagram) {
        var palette = ThemeManager.get_active_palette();
        var cv = new ChartCanvas();
        laid_links = new Gee.ArrayList<SLink>();
        region_names = new Gee.HashMap<string, string>();
        element_lines = new Gee.HashMap<string, int>();
        string text_color = palette.node_text;

        bool has_title = diagram.title != null && diagram.title.length > 0;

        var names = diagram.get_nodes();
        if (names.size == 0) {
            if (has_title) cv.text(0, 10, diagram.title, 16, text_color, 'l', true, "sankey_title");
            cv.text(0, has_title ? 40 : 10, "(no links)", FONT, text_color, 'l');
            return cv.finish("sankey", palette.background);
        }

        var nodes = new Gee.ArrayList<SNode>();
        var by_name = new Gee.HashMap<string, SNode>();
        foreach (var name in names) {
            var n = new SNode();
            n.name = name;
            nodes.add(n);
            by_name.set(name, n);
        }
        var links = new Gee.ArrayList<SLink>();
        foreach (var link in diagram.links) {
            var l = new SLink();
            l.source = by_name.get(link.source);
            l.target = by_name.get(link.target);
            l.value = link.value;
            l.source_line = link.source_line;
            links.add(l);
        }

        double dy = NODE_PADDING + (diagram.show_values ? VALUE_PADDING : 0);
        layout_sankey(nodes, links, NODE_WIDTH, dy, EXTENT_W, EXTENT_H);

        // Room for the labels that sit outside the left and right columns.
        double left_room = 0, right_room = 0;
        foreach (var n in nodes) {
            double w = GanttText.width(label_of(diagram, n), FONT) + 10;
            if (n.x0 < EXTENT_W / 2) right_room = double.max(right_room, n.x1 + 6 + w - EXTENT_W);
            else left_room = double.max(left_room, w + 6 - n.x0);
        }
        double ox = double.max(0, left_room);
        double oy = has_title ? 40 : 0;
        if (has_title) cv.text(ox, 14, diagram.title, 18, text_color, 'l', true, "sankey_title");
        // Keep the right-hand labels inside the drawing.
        if (right_room > 0) cv.rect(ox + EXTENT_W + right_room, oy, 0.01, 0.01, palette.background, palette.background, 0);

        string[] colors = node_colors_from_palette(palette);
        var node_color = new Gee.HashMap<string, string>();
        for (int i = 0; i < nodes.size; i++) {
            node_color.set(nodes.get(i).name, colors[i % colors.length]);
        }

        // Ribbons first, so the bars and labels stay on top of them.
        link_colors = new string[links.size];
        for (int i = 0; i < links.size; i++) {
            var l = links.get(i);
            double x1 = ox + l.source.x1, x2 = ox + l.target.x0;
            double mid = (x1 + x2) / 2;
            double y1 = oy + l.y0, y2 = oy + l.y1;
            string color = node_color.get(l.source.name);
            link_colors[i] = color;
            cv.bezier(x1, y1, mid, y1, mid, y2, x2, y2, color,
                double.max(1, l.width), "sankey_link_%d".printf(i));
            laid_links.add(l);
        }

        // Node bars, then their labels outside the bar.
        for (int i = 0; i < nodes.size; i++) {
            var n = nodes.get(i);
            string fill = node_color.get(n.name);
            string region = n.name;
            int line = first_line(diagram, n.name);
            note(cv.rect(ox + n.x0, oy + n.y0, NODE_WIDTH, n.y1 - n.y0, fill, fill, 0,
                "sankey_node_%d".printf(i)), region, line);
            string label = label_of(diagram, n);
            bool right = n.x0 < EXTENT_W / 2;
            note(cv.text(ox + (right ? n.x1 + 6 : n.x0 - 6), oy + (n.y0 + n.y1) / 2, label,
                FONT, text_color, right ? 'l' : 'r', false, "sankey_label_%d".printf(i)), region, line);
        }

        return cv.finish("sankey", palette.background);
    }

    private void note(string node, string region, int line) {
        if (node.length == 0) return;
        region_names.set(node, region);
        if (line > 0) element_lines.set(region, line);
    }

    // Mermaid labels a node with its name and, when showValues, its total.
    private static string label_of(MermaidSankey diagram, SNode n) {
        return diagram.show_values
            ? "%s %s".printf(n.name, ChartCanvas.format_value(n.value))
            : n.name;
    }

    private static int first_line(MermaidSankey diagram, string name) {
        foreach (var l in diagram.links) {
            if (l.source == name || l.target == name) return l.source_line;
        }
        return 0;
    }

    /**
     * Mermaid strokes each ribbon with a gradient from its source colour to its
     * target colour at half opacity; Graphviz can only give it one flat colour,
     * so the gradients are injected afterwards. The endpoint x coordinates come
     * out of the rendered path, which is already in the SVG's own space.
     */
    private uint8[] add_link_gradients(uint8[] svg_data, Gee.HashMap<string, string> node_color) {
        if (laid_links.size == 0) return svg_data;
        var buf = new StringBuilder.sized(svg_data.length + 1);
        buf.append_len((string) svg_data, svg_data.length);
        string svg = buf.str;
        var defs = new StringBuilder();
        try {
            var re = new Regex("(<g id=\"sankey_link_(\\d+)\" class=\"edge\">.*?<path fill=\"none\" stroke=\")([^\"]*)(\"[^>]*d=\"M([-\\d.]+),[-\\d.]+C[^\"]*?([-\\d.]+),[-\\d.]+\")",
                RegexCompileFlags.DOTALL);
            string result = re.replace_eval(svg, -1, 0, 0, (m, res) => {
                int idx = int.parse(m.fetch(2));
                if (idx < 0 || idx >= laid_links.size) {
                    res.append(m.fetch(0));
                    return false;
                }
                var l = laid_links.get(idx);
                string c0 = node_color.get(l.source.name) ?? m.fetch(3);
                string c1 = node_color.get(l.target.name) ?? m.fetch(3);
                defs.append_printf("<linearGradient id=\"sankeyGrad%d\" gradientUnits=\"userSpaceOnUse\" x1=\"%s\" x2=\"%s\">"
                    + "<stop offset=\"0%%\" stop-color=\"%s\"/><stop offset=\"100%%\" stop-color=\"%s\"/></linearGradient>",
                    idx, m.fetch(5), m.fetch(6), c0, c1);
                res.append(m.fetch(1));
                res.append("url(#sankeyGrad%d)".printf(idx));
                res.append(m.fetch(4));
                res.append(" stroke-opacity=\"0.5\"");
                return false;
            });
            if (defs.len == 0) return svg_data;
            int at = result.index_of("<g id=\"graph0\"");
            if (at < 0) return svg_data;
            result = result.substring(0, at) + "<defs>" + defs.str + "</defs>\n" + result.substring(at);
            return result.data;
        } catch (RegexError e) {
            warning("sankey gradient regex: %s", e.message);
            return svg_data;
        }
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidSankey diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse DOT graph");
            return null;
        }

        int ret = context.layout(graph, "nop2");
        if (ret != 0) {
            warning("Failed to layout sankey graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render graph");
            return null;
        }

        var palette = ThemeManager.get_active_palette();
        string[] colors = node_colors_from_palette(palette);
        var node_color = new Gee.HashMap<string, string>();
        var names = diagram.get_nodes();
        for (int i = 0; i < names.size; i++) node_color.set(names.get(i), colors[i % colors.length]);
        return add_link_gradients(svg_data, node_color);
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidSankey diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
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
            warning("Failed to render SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidSankey diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidSankey diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidSankey diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
