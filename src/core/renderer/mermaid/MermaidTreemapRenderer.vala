/* MermaidTreemapRenderer.vala — Mermaid treemap-beta renderer */
namespace GDiagram {

public class MermaidTreemapRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private Gee.HashMap<string, int> _element_lines = new Gee.HashMap<string, int>();

    public MermaidTreemapRenderer(Gvc.Context ctx,
                                    Gee.ArrayList<ElementRegion> regions,
                                    string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // Canvas and section geometry in points.
    private const double WIDTH = 720.0;
    private const double HEIGHT = 400.0;
    private const double HEADER = 20.0;
    private const double PAD = 6.0;

    private ChartCanvas canvas;
    private MermaidTreemap current;
    private string[] section_colors;

    public string generate_dot(MermaidTreemap diagram) {
        this._element_lines = new Gee.HashMap<string, int>();
        var palette = ThemeManager.get_active_palette();
        this.canvas = new ChartCanvas();
        this.current = diagram;
        this.section_colors = {
            palette.system_fill, palette.warning, palette.success, palette.accent_secondary,
            palette.person_fill, palette.container_fill, palette.component_fill, palette.database_fill
        };

        double top = 0;
        if (diagram.title != null && diagram.title.length > 0) {
            canvas.text(WIDTH / 2, 10, diagram.title, 16, palette.node_text, 'c', false, "treemap_title");
            top = 30;
        }

        if (diagram.roots.size == 0) {
            canvas.text(WIDTH / 2, top + 20, "(no data)", 12, palette.node_text, 'c');
            return canvas.finish("treemap", palette.background);
        }

        var roots = sorted_by_value(diagram.roots);
        var rects = squarify(weights_of(roots), 0, top, WIDTH, HEIGHT);
        for (int i = 0; i < roots.size; i++) {
            var r = rects.get(i);
            string color = section_colors[i % section_colors.length];
            draw_node(roots.get(i), r.x, r.y, r.w, r.h, color, 0);
        }

        return canvas.finish("treemap", palette.background);
    }

    private class Box {
        public double x;
        public double y;
        public double w;
        public double h;
        public Box(double x, double y, double w, double h) { this.x = x; this.y = y; this.w = w; this.h = h; }
    }

    // Largest first, as d3's treemap lays them out. Zero-valued nodes are kept:
    // Mermaid draws them, and dropping them turned a treemap written without
    // any numbers into a blank 29x29 pt square.
    private static Gee.ArrayList<TreemapNode> sorted_by_value(Gee.ArrayList<TreemapNode> nodes) {
        var list = new Gee.ArrayList<TreemapNode>();
        list.add_all(nodes);
        list.sort((a, b) => {
            double va = a.total_value(), vb = b.total_value();
            return va > vb ? -1 : (va < vb ? 1 : 0);
        });
        return list;
    }

    /**
     * The area weight of each node. A level whose values are all zero — or
     * absent — splits its space equally instead of vanishing.
     */
    private static Gee.ArrayList<double?> weights_of(Gee.ArrayList<TreemapNode> nodes) {
        var w = new Gee.ArrayList<double?>();
        double total = 0;
        foreach (var n in nodes) {
            double v = n.total_value();
            if (!(v > 0)) v = 0;
            w.add(v);
            total += v;
        }
        if (w.size == 0) return w;
        if (total <= 0) {
            for (int i = 0; i < w.size; i++) w.set(i, 1.0);
            return w;
        }
        // A zero beside real values keeps a small share rather than a
        // zero-area box. Two reasons: squarify's row height is
        // `area / row_width`, so a row of zeroes divides 0 by 0 and every
        // later coordinate comes out NaN; and a box with no area cannot carry
        // the label Mermaid still writes for such a node.
        double sliver = total / (w.size * 20.0);
        for (int i = 0; i < w.size; i++) {
            if (w.get(i) <= 0) w.set(i, sliver);
        }
        return w;
    }

    private static double worst_ratio(Gee.ArrayList<double?> row, double side) {
        double sum = 0, mx = 0, mn = double.MAX;
        foreach (var a in row) {
            sum += a;
            mx = double.max(mx, a);
            mn = double.min(mn, a);
        }
        if (sum <= 0 || mn <= 0) return double.MAX;
        double s2 = side * side, sum2 = sum * sum;
        return double.max(s2 * mx / sum2, sum2 / (s2 * mn));
    }

    /**
     * Squarified treemap (Bruls, Huizing, van Wijk): each node gets a box
     * whose area is proportional to its value. `nodes` must be sorted
     * largest first; boxes come back in the same order.
     */
    private static Gee.ArrayList<Box> squarify(Gee.ArrayList<double?> values,
                                               double x, double y, double w, double h) {
        var boxes = new Gee.ArrayList<Box>();
        double total = 0;
        foreach (var v in values) total += v;
        if (values.size == 0 || total <= 0 || w <= 0 || h <= 0) return boxes;

        double scale = w * h / total;
        int i = 0;
        while (i < values.size) {
            double side = double.min(w, h);
            var row = new Gee.ArrayList<double?>();
            row.add(values.get(i) * scale);
            int j = i + 1;
            while (j < values.size) {
                var trial = new Gee.ArrayList<double?>();
                trial.add_all(row);
                trial.add(values.get(j) * scale);
                if (worst_ratio(trial, side) > worst_ratio(row, side)) break;
                row = trial;
                j++;
            }
            double row_area = 0;
            foreach (var a in row) row_area += a;
            if (w >= h) {
                // Column along the left edge.
                double col_w = row_area / h;
                double yy = y;
                foreach (var a in row) {
                    double bh = a / col_w;
                    boxes.add(new Box(x, yy, col_w, bh));
                    yy += bh;
                }
                x += col_w;
                w -= col_w;
            } else {
                // Row along the top edge.
                double row_h = row_area / w;
                double xx = x;
                foreach (var a in row) {
                    double bw = a / row_h;
                    boxes.add(new Box(xx, y, bw, row_h));
                    xx += bw;
                }
                y += row_h;
                h -= row_h;
            }
            i = j;
        }
        return boxes;
    }

    // classDef styling for `:::name`: fill, stroke, stroke-width, color.
    private string? class_prop(TreemapNode node, string prop) {
        if (node.css_class == null || !current.class_defs.has_key(node.css_class)) return null;
        var props = current.class_defs.get(node.css_class);
        if (!props.has_key(prop)) return null;
        string v = props.get(prop);
        if (v.has_suffix("px")) v = v.substring(0, v.length - 2);
        return v;
    }

    private static string with_alpha(string color, string alpha) {
        return (color.has_prefix("#") && color.length == 7) ? color + alpha : color;
    }

    private void draw_node(TreemapNode node, double x, double y, double w, double h, string color, int depth) {
        var palette = ThemeManager.get_active_palette();
        string? fill_override = class_prop(node, "fill");
        string? stroke_override = class_prop(node, "stroke");
        string? width_override = class_prop(node, "stroke-width");
        string? text_override = class_prop(node, "color");
        string stroke = stroke_override != null ? RenderUtils.sanitize_color(stroke_override) : color;
        double pen = width_override != null ? double.parse(width_override) : 1.5;
        // A node written without a number still gets a box, but no total to show.
        bool has_value = node.total_value() > 0;
        string value_text = has_value ? ChartCanvas.format_value(node.total_value()) : "";

        if (!node.is_leaf && node.children.size > 0) {
            string fill = fill_override != null ? RenderUtils.sanitize_color(fill_override) : with_alpha(color, "40");
            string text_color = text_override != null ? RenderUtils.sanitize_color(text_override) : palette.node_text;
            string name = canvas.rect(x, y, w, h, fill, stroke, pen, "treemap_section_%d".printf(node.source_line));
            if (node.source_line > 0) _element_lines.set(name, node.source_line);
            if (w > 30 && h > HEADER) {
                // Name left, total right, in the header band.
                // The total gives way first when the band is narrow, then the name is cut.
                double value_w = ChartCanvas.text_width(value_text, 11);
                double label_w = ChartCanvas.text_width(node.label, 12, true);
                bool show_total = has_value && label_w + value_w + 3 * PAD <= w;
                string label = node.label;
                double room = w - 2 * PAD;
                if (!show_total && label_w > room) {
                    // Cut by measured width, not by an assumed advance: a CJK
                    // label kept far too many characters and ran off the box.
                    int keep = label.char_count();
                    while (keep > 0 &&
                           ChartCanvas.text_width(label.substring(0, label.index_of_nth_char(keep)) + "…", 12, true) > room) {
                        keep--;
                    }
                    label = keep > 0 ? label.substring(0, label.index_of_nth_char(keep)) + "…" : "";
                }
                canvas.text(x + PAD, y + HEADER / 2 + 1, label, 12, text_color, 'l', true);
                if (show_total) {
                    canvas.text(x + w - PAD, y + HEADER / 2 + 1, value_text, 11, text_color, 'r', false, null, true);
                }
            }
            var kids = sorted_by_value(node.children);
            double ix = x + PAD, iy = y + HEADER, iw = w - 2 * PAD, ih = h - HEADER - PAD;
            if (iw <= 2 || ih <= 2) return;
            var boxes = squarify(weights_of(kids), ix, iy, iw, ih);
            for (int i = 0; i < kids.size; i++) {
                var b = boxes.get(i);
                draw_node(kids.get(i), b.x, b.y, b.w, b.h, color, depth + 1);
            }
            return;
        }

        // Leaf: inset a little so neighbours stay apart; name and value centred,
        // the name scaled with the box as Mermaid does.
        double inset = 2.0;
        double lx = x + inset, ly = y + inset, lw = w - 2 * inset, lh = h - 2 * inset;
        if (lw <= 0 || lh <= 0) return;
        string fill = fill_override != null ? RenderUtils.sanitize_color(fill_override) : with_alpha(color, "8C");
        string text_color = text_override != null ? RenderUtils.sanitize_color(text_override) : palette.node_text;
        string name = canvas.rect(lx, ly, lw, lh, fill, stroke, pen, "treemap_leaf_%d".printf(node.source_line));
        if (node.source_line > 0) _element_lines.set(name, node.source_line);

        double size = double.min(28.0, double.min(lh / 3.0, lw / double.max(1, node.label.char_count() * 0.62)));
        if (size < 7.0) return;
        double value_size = double.max(8.0, double.min(size * 0.7, 16.0));
        bool show_value = has_value && lh >= size * 1.4 + value_size * 1.6;
        double label_y = show_value ? ly + lh / 2 - value_size * 0.7 : ly + lh / 2;
        canvas.text(lx + lw / 2, label_y, node.label, size, text_color, 'c');
        if (show_value) {
            canvas.text(lx + lw / 2, label_y + size * 0.7 + value_size * 0.8, value_text, value_size, text_color, 'c');
        }
    }

    public uint8[]? render_to_svg(MermaidTreemap diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse treemap DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out treemap graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render treemap graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidTreemap diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 600, out width, out height);

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

            RenderUtils.parse_svg_regions(svg_data, regions, _element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render treemap SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidTreemap diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidTreemap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidTreemap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
