namespace GDiagram {

// One block of the grid with its computed geometry (points, y down)
internal class BlockBox : Object {
    public BlockNode? node;
    public Gee.ArrayList<BlockBox> children = new Gee.ArrayList<BlockBox>();
    public int columns = -1;
    public double w;
    public double h;
    public double x;
    public double y;

    public BlockBox(BlockNode? node) {
        this.node = node;
        if (node != null) columns = node.columns;
    }

    public int span { get { return node != null ? int.max(1, node.col_span) : 1; } }
    public bool is_space { get { return node != null && node.is_space; } }
    public bool is_group { get { return node == null || node.is_group; } }
}

/*
 * Mermaid block-beta is a grid, not a graph: the renderer computes every block's
 * position the way Mermaid's block layout does and pins it (layout=nop2), so
 * Graphviz only draws the shapes and routes the links as straight lines.
 *  - A group's children share one cell size: the widest child (per column it
 *    spans) and the tallest, and cells fill `columns` per row ("columns N"; one
 *    row without it). "id:N" spans N cells, "space"/"space:N" leaves cells empty.
 *  - A group is as large as its grid; a larger parent cell stretches the grid.
 */
public class MermaidBlockRenderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    private const double PAD = 6.0;        // Mermaid block padding, 8px
    private const double FONT = 12.0;
    private const double MARGIN = 8.0;
    // Room for a group's own title above its children (Mermaid draws it inside the rect)
    private const double GROUP_LABEL_H = 20.0;
    // measure(), place() and emit_children() walk the group tree once per nesting level:
    // without a cap a few thousand nested "block:" groups overflowed the stack.
    private const int MAX_GROUP_DEPTH = 200;
    /*
     * Largest canvas we hand to Graphviz, per direction.
     *
     * A block grid's cells are all the size of its widest/tallest child (Mermaid's own
     * model), so a group nested inside a group multiplies the canvas by the number of
     * cells per level. That growth is Mermaid's, not ours — mermaid-cli renders the same
     * ladder at the same 6x per level (depth 3: 17340pt there, 16433pt here; depth 8:
     * 44791530pt there) — so measure() must keep it to stay faithful.
     *
     * What is ours is what happened past it: Graphviz prints the SVG's width as an int,
     * so a canvas over 2^31 points came out as width="-2147483648pt", librsvg then
     * reported no size and the PNG fell back to a blank 400x300 image at exit 0. Past
     * this limit no renderer or viewer can show the diagram anyway (the PNG downscale
     * has already collapsed it to a few pixels), so say so instead of drawing nothing.
     */
    private const double MAX_CANVAS = 1000000.0;

    public MermaidBlockRenderer(Gvc.Context context,
                                 Gee.ArrayList<ElementRegion> regions,
                                 string engine) {
        this.ctx = context;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // ---- layout ---------------------------------------------------------

    private BlockBox build_tree(MermaidBlock diagram) {
        var root = new BlockBox(null);
        root.columns = diagram.columns > 0 ? diagram.columns : -1;
        var boxes = new Gee.HashMap<string, BlockBox>();
        foreach (var n in diagram.nodes) {
            boxes.set(n.id, new BlockBox(n));
        }
        foreach (var n in diagram.nodes) {
            BlockBox parent = root;
            if (n.group_id != null && boxes.has_key(n.group_id) && n.group_id != n.id) {
                parent = boxes.get(n.group_id);
            }
            parent.children.add(boxes.get(n.id));
        }
        return root;
    }

    private static int grid_columns(BlockBox box) {
        int items = 0;
        foreach (var c in box.children) items += c.span;
        if (items == 0) return 1;
        return box.columns > 0 ? int.min(box.columns, items) : items;
    }

    // Cells used by each child (clipped at the row end) and the number of rows
    private static int grid_rows(BlockBox box) {
        int col_pos = 0;
        foreach (var c in box.children) {
            col_pos += filled_cells(box, col_pos, c.span);
        }
        if (box.columns <= 0) return 1;
        return int.max(1, (col_pos + box.columns - 1) / box.columns);
    }

    private static int filled_cells(BlockBox box, int col_pos, int span) {
        if (box.columns > 0) return int.min(span, box.columns - col_pos % box.columns);
        return span;
    }

    public static double text_width(string text) {
        return GanttText.width(text, FONT, false, "Sans");
    }

    // Size a block needs for its label
    private void natural_size(BlockBox box) {
        var n = box.node;
        string label = n.label;
        double tw = label.length > 0 ? text_width(label) : 0;
        double th = FONT * 1.3;
        double w = tw + 24;
        double h = th + 16;
        switch (n.shape) {
            case "circle":
                w = double.max(w, h);
                h = w;
                break;
            case "doublecircle":
                w = double.max(w, h) + 8;
                h = w;
                break;
            case "diamond":
                w = tw + th + 24;
                h = w;
                break;
            case "hexagon":
            case "stadium":
                w += h / 2;
                break;
            case "lean_right":
            case "lean_left":
            case "trapezoid":
            case "inv_trapezoid":
            case "rect_left_inv_arrow":
                w += h * 0.6;
                break;
            case "block_arrow":
                if (n.arrow_direction == "up" || n.arrow_direction == "down" || n.arrow_direction == "y") {
                    h *= 2;
                    w += 12;
                } else {
                    w += h;
                    h *= 1.5;
                }
                break;
            default:
                break;
        }
        box.w = w;
        box.h = h;
    }

    // A drawn group with a title reserves a strip at the top of its rect for it
    private static string? group_label(BlockBox box) {
        if (box.node == null || !box.node.is_group || box.children.size == 0) return null;
        string label = box.node.label;
        if (label.has_prefix("\"") && label.has_suffix("\"") && label.length >= 2) {
            label = label.substring(1, label.length - 2);
        }
        return label.length > 0 ? label : null;
    }

    private static double group_label_h(BlockBox box) {
        return group_label(box) != null ? GROUP_LABEL_H : 0;
    }

    private void measure(BlockBox box, int depth = 0) {
        if (!box.is_group || (box.node != null && box.children.size == 0) ||
            depth >= MAX_GROUP_DEPTH) {
            if (box.is_space) {
                box.w = 0;
                box.h = 0;
            } else if (box.node != null) {
                natural_size(box);
            } else {
                box.w = 20;
                box.h = 20;
            }
            return;
        }
        double max_w = 0;
        double max_h = 0;
        foreach (var c in box.children) {
            measure(c, depth + 1);
            if (c.is_space) continue;
            max_w = double.max(max_w, c.w / c.span);
            max_h = double.max(max_h, c.h);
        }
        if (max_w <= 0) max_w = 20;
        if (max_h <= 0) max_h = 20;
        int cols = grid_columns(box);
        int rows = grid_rows(box);
        box.w = cols * (max_w + PAD) + PAD;
        box.h = rows * (max_h + PAD) + PAD + group_label_h(box);
        string? title = group_label(box);
        if (title != null) box.w = double.max(box.w, text_width(title) + 2 * PAD + 12);
    }

    // Final geometry: a group spreads its (possibly stretched) size over its cells
    private void place(BlockBox box, double x, double y, double w, double h, int depth = 0) {
        box.x = x;
        box.y = y;
        box.w = w;
        box.h = h;
        if (box.children.size == 0 || depth >= MAX_GROUP_DEPTH) return;
        int cols = grid_columns(box);
        int rows = grid_rows(box);
        double lh = group_label_h(box);
        double cw = (w - PAD * (cols + 1)) / cols;
        double ch = (h - lh - PAD * (rows + 1)) / rows;
        int col_pos = 0;
        foreach (var c in box.children) {
            int px = box.columns > 0 ? col_pos % box.columns : col_pos;
            int py = box.columns > 0 ? col_pos / box.columns : 0;
            int filled = filled_cells(box, col_pos, c.span);
            place(c, x + PAD + px * (cw + PAD), y + lh + PAD + py * (ch + PAD),
                  cw * filled + PAD * (filled - 1), ch, depth + 1);
            col_pos += filled;
        }
    }

    // Deepest group nesting in the tree, counted without recursion
    private static int tree_depth(BlockBox root) {
        var stack = new Gee.ArrayList<BlockBox>();
        var depths = new Gee.ArrayList<int>();
        stack.add(root);
        depths.add(0);
        int max = 0;
        while (stack.size > 0) {
            var box = stack.remove_at(stack.size - 1);
            int d = depths.remove_at(depths.size - 1);
            if (d > max) max = d;
            foreach (var c in box.children) {
                stack.add(c);
                depths.add(d + 1);
            }
        }
        return max;
    }

    // ---- styling ----------------------------------------------------------

    private void apply_css(string? css, ref string fill, ref string stroke, ref string text, ref double pen) {
        if (css == null) return;
        foreach (string decl in css.split(",")) {
            string d = decl.strip();
            if (d.has_suffix(";")) d = d.substring(0, d.length - 1);
            int colon = d.index_of_char(':');
            if (colon <= 0) continue;
            string key = d.substring(0, colon).strip();
            string val = d.substring(colon + 1).strip();
            if (val.length == 0) continue;
            switch (key) {
                case "fill":   fill = RenderUtils.sanitize_color(val); break;
                case "stroke": stroke = RenderUtils.sanitize_color(val); break;
                case "color":  text = RenderUtils.sanitize_color(val); break;
                case "stroke-width":
                    double px = double.parse(val.replace("px", ""));
                    if (px > 0) pen = px * 0.75;
                    break;
                default: break;
            }
        }
    }

    private static string num(double v) {
        char[] buf = new char[32];
        return v.format(buf, "%.2f");
    }

    private static string quote(string id) {
        return "\"" + RenderUtils.escape_label(id) + "\"";
    }

    // ---- DOT --------------------------------------------------------------

    /*
     * The grid does not fit a canvas Graphviz can describe (see MAX_CANVAS): draw a single
     * block that says so, instead of pinning coordinates Graphviz prints as a negative SVG
     * width — which left the PNG export a blank 400x300 image at exit 0. The same message
     * goes to diagram.errors, so the editor and the LSP report it as a diagnostic.
     */
    private string oversize_dot(MermaidBlock diagram, Palette palette,
                                double total_w, double total_h) {
        string note = "Block layout is %.0f x %.0f points, too large to render; reduce the nesting of \"block:\" groups"
            .printf(total_w, total_h);
        diagram.errors.add(new ParseError(note, 1, 1));

        var sb = new StringBuilder();
        sb.append("digraph block {\n");
        sb.append("    layout=nop2\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append_printf("    __block_oversize [pos=\"0,0!\" shape=box style=filled fontname=\"Sans\" fontsize=%s fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" label=\"%s\"]\n",
            num(FONT), palette.node_fill, palette.node_border, palette.node_text,
            RenderUtils.escape_label(note));
        sb.append("}\n");
        return sb.str;
    }

    public string generate_dot(MermaidBlock diagram) {
        var palette = ThemeManager.get_active_palette();
        var root = build_tree(diagram);
        if (tree_depth(root) > MAX_GROUP_DEPTH) {
            diagram.errors.add(new ParseError(
                "Blocks nested deeper than %d levels".printf(MAX_GROUP_DEPTH), 1, 1));
        }
        measure(root);
        place(root, 0, 0, root.w, root.h);
        double total_h = root.h + 2 * MARGIN;
        double total_w = root.w + 2 * MARGIN;
        if (total_w > MAX_CANVAS || total_h > MAX_CANVAS) {
            return oversize_dot(diagram, palette, total_w, total_h);
        }

        var sb = new StringBuilder();
        sb.append("digraph block {\n");
        sb.append("    layout=nop2\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    splines=line\n");
        sb.append("    outputorder=nodesfirst\n");
        sb.append_printf("    node [fontname=\"Sans\" fontsize=%s fixedsize=true style=filled fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\"]\n",
            num(FONT), palette.node_fill, palette.node_border, palette.node_text);
        sb.append("    edge [fontname=\"Sans\" fontsize=10 color=\"%s\" fontcolor=\"%s\" arrowsize=0.8]\n\n".printf(palette.edge_color, palette.edge_text));
        // Corner anchors keep the margins inside the drawing
        sb.append_printf("    __block_tl [pos=\"0,%s!\" shape=point style=invis width=0 height=0 label=\"\"]\n", num(total_h));
        sb.append_printf("    __block_br [pos=\"%s,0!\" shape=point style=invis width=0 height=0 label=\"\"]\n", num(total_w));

        int shape_idx = 0;
        emit_children(sb, diagram, root, total_h, ref shape_idx);

        sb.append("\n");
        int cross_idx = 0;
        foreach (var edge in diagram.edges) {
            if (diagram.find_node(edge.source) == null || diagram.find_node(edge.target) == null) continue;
            var attrs = new StringBuilder();
            string head;
            switch (edge.arrow_end) {
                case "arrow_point":  head = "normal"; break;
                // Graphviz has no cross arrowhead: the X is drawn onto the SVG afterwards
                case "arrow_cross":  head = "none"; break;
                case "arrow_circle": head = "dot"; break;
                default:             head = "none"; break;
            }
            attrs.append("arrowhead=" + head);
            if (edge.arrow_end == "arrow_cross") {
                attrs.append(" id=\"gdblkx_%d\"".printf(cross_idx++));
            }
            if (edge.invisible) attrs.append(" style=invis");
            else if (edge.dotted) attrs.append(" style=dashed");
            if (edge.thick) attrs.append(" penwidth=2.5");
            if (edge.label != null && edge.label.length > 0) {
                attrs.append(" label=\"%s\"".printf(RenderUtils.escape_label(edge.label)));
            }
            sb.append_printf("    %s -> %s [%s]\n", quote(edge.source), quote(edge.target), attrs.str);
        }

        sb.append("}\n");
        return sb.str;
    }

    private void emit_children(StringBuilder sb, MermaidBlock diagram, BlockBox parent, double total_h,
                               ref int shape_idx, int depth = 0) {
        if (depth >= MAX_GROUP_DEPTH) return;
        var palette = ThemeManager.get_active_palette();
        foreach (var box in parent.children) {
            var n = box.node;
            if (n.is_space) continue;
            double cx = MARGIN + box.x + box.w / 2;
            double cy = total_h - (MARGIN + box.y + box.h / 2);

            string fill = n.is_group ? palette.grid : palette.node_fill;
            string stroke = n.is_group ? palette.container_border : palette.node_border;
            string text = palette.node_text;
            double pen = 1.0;
            if (n.css_classes != null) {
                foreach (string cls in n.css_classes.split(" ")) {
                    if (diagram.class_defs.has_key(cls)) {
                        apply_css(diagram.class_defs.get(cls), ref fill, ref stroke, ref text, ref pen);
                    }
                }
            }
            apply_css(n.styles, ref fill, ref stroke, ref text, ref pen);
            // A styled fill without a text colour: keep the text readable on it
            string default_fill = n.is_group ? palette.grid : palette.node_fill;
            if (fill != default_fill && text == palette.node_text) {
                text = RenderUtils.contrast_text(fill);
            }

            if (n.is_group && box.children.size > 0) {
                // Mermaid draws a group as a rectangle behind its blocks, with the group's
                // own label inside it, above them
                string? title = group_label(box);
                sb.append_printf("    %s [pos=\"%s,%s!\" width=%s height=%s shape=box label=\"%s\" labelloc=t fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" penwidth=%s]\n",
                    quote(n.id), num(cx), num(cy), num(box.w / 72.0), num(box.h / 72.0),
                    title != null ? RenderUtils.escape_label(title) : "", fill, stroke, text, num(pen));
                emit_children(sb, diagram, box, total_h, ref shape_idx, depth + 1);
                continue;
            }

            double w = box.w;
            double h = box.h;
            string shape = "box";
            string extra = "";
            switch (n.shape) {
                case "round":        extra = " style=\"rounded,filled\""; break;
                case "cylinder":     shape = "cylinder"; break;
                case "circle":       shape = "circle"; break;
                case "doublecircle": shape = "doublecircle"; break;
                case "diamond":      shape = "diamond"; break;
                case "hexagon":      shape = "hexagon"; break;
                case "lean_right":   shape = "parallelogram"; break;
                case "lean_left":    shape = "polygon"; extra = " sides=4 skew=-0.4"; break;
                case "trapezoid":    shape = "trapezium"; break;
                case "inv_trapezoid": shape = "invtrapezium"; break;
                case "rect_left_inv_arrow": shape = "cds"; extra = " orientation=180"; break;
                case "stadium":
                case "subroutine":
                    extra = " id=\"gdblk_%s_%d\"".printf(n.shape, shape_idx++);
                    break;
                case "block_arrow":
                    string dir = n.arrow_direction;
                    if (dir != "left" && dir != "up" && dir != "down" && dir != "x" && dir != "y") dir = "right";
                    extra = " id=\"gdblk_arrow%s_%d\"".printf(dir, shape_idx++);
                    break;
                default: break;
            }
            // Circles and diamonds keep their own size, centred in the cell
            if (n.shape == "circle" || n.shape == "doublecircle" || n.shape == "diamond") {
                var own = new BlockBox(n);
                natural_size(own);
                w = double.min(own.w, double.min(box.w, box.h));
                h = w;
            }
            string label = n.label;
            if (label.has_prefix("\"") && label.has_suffix("\"") && label.length >= 2) {
                label = label.substring(1, label.length - 2);
            }
            sb.append_printf("    %s [pos=\"%s,%s!\" width=%s height=%s shape=%s%s label=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" penwidth=%s]\n",
                quote(n.id), num(cx), num(cy), num(w / 72.0), num(h / 72.0), shape, extra,
                RenderUtils.escape_label(label), fill, stroke, text, num(pen));
        }
    }

    // ---- SVG shapes Graphviz lacks ------------------------------------------

    // Stadiums, subroutines and block arrows are drawn as boxes with an id naming
    // the shape; the box outline is replaced here by the real shape.
    public static uint8[] draw_shapes(uint8[] svg_data) {
        var sbuf = new StringBuilder.sized(svg_data.length + 1);
        sbuf.append_len((string) svg_data, svg_data.length);
        string svg = sbuf.str;
        if (!svg.contains("id=\"gdblk_")) return svg_data;
        try {
            var re = new Regex(
                "(<g id=\"gdblk_([a-z]+)_\\d+\" class=\"node\">\\s*<title>[^<]*</title>\\s*)<polygon ([^>]*?)points=\"([^\"]*)\"/>",
                RegexCompileFlags.DOTALL);
            svg = re.replace_eval(svg, -1, 0, 0, (m, result) => {
                string kind = m.fetch(2);
                string attrs = m.fetch(3);
                double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
                foreach (string pt in m.fetch(4).strip().split(" ")) {
                    string[] xy = pt.split(",");
                    if (xy.length != 2) continue;
                    double px = double.parse(xy[0]);
                    double py = double.parse(xy[1]);
                    minx = double.min(minx, px); maxx = double.max(maxx, px);
                    miny = double.min(miny, py); maxy = double.max(maxy, py);
                }
                result.append(m.fetch(1));
                if (minx > maxx) {
                    result.append("<polygon %spoints=\"%s\"/>".printf(attrs, m.fetch(4)));
                    return false;
                }
                double w = maxx - minx;
                double h = maxy - miny;
                double cx = (minx + maxx) / 2;
                double cy = (miny + maxy) / 2;
                switch (kind) {
                    case "stadium":
                        result.append("<rect %sx=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\"/>".printf(
                            attrs, num(minx), num(miny), num(w), num(h), num(double.min(h, w) / 2)));
                        break;
                    case "subroutine":
                        result.append("<polygon %spoints=\"%s\"/>".printf(attrs, m.fetch(4)));
                        string stroke_attrs = attrs;
                        try {
                            stroke_attrs = new Regex("fill=\"[^\"]*\"").replace(attrs, -1, 0, "fill=\"none\"");
                        } catch (RegexError e) {}
                        result.append("<path %sd=\"M%s,%s V%s M%s,%s V%s\"/>".printf(stroke_attrs,
                            num(minx + 8), num(miny), num(maxy), num(maxx - 8), num(miny), num(maxy)));
                        break;
                    default:
                        string dir = kind.has_prefix("arrow") ? kind.substring(5) : "right";
                        result.append("<polygon %spoints=\"%s\"/>".printf(attrs, arrow_points(dir, minx, miny, w, h, cx, cy)));
                        break;
                }
                return false;
            });
        } catch (RegexError e) {
            warning("Failed to draw block shapes: %s", e.message);
            return svg_data;
        }
        return svg.data;
    }

    /**
     * "A x--x B" ends in a cross. Graphviz has no cross arrowhead, so those edges are
     * drawn without one and tagged with an id; the X is added here at the line's end,
     * turned to the line's direction like Mermaid's cross marker.
     */
    public static uint8[] draw_cross_ends(uint8[] svg_data) {
        var sbuf = new StringBuilder.sized(svg_data.length + 1);
        sbuf.append_len((string) svg_data, svg_data.length);
        string svg = sbuf.str;
        if (!svg.contains("id=\"gdblkx_")) return svg_data;
        try {
            var re = new Regex(
                "(<g id=\"gdblkx_\\d+\" class=\"edge\">\\s*<title>[^<]*</title>\\s*" +
                "<path [^>]*?stroke=\"([^\"]*)\"[^>]*?d=\"([^\"]*)\"/>)",
                RegexCompileFlags.DOTALL);
            svg = re.replace_eval(svg, -1, 0, 0, (m, result) => {
                result.append(m.fetch(1));
                double px, py, ex, ey;
                if (path_end(m.fetch(3), out px, out py, out ex, out ey)) {
                    result.append(cross_path(m.fetch(2), px, py, ex, ey));
                }
                return false;
            });
        } catch (RegexError e) {
            warning("Failed to draw block cross ends: %s", e.message);
            return svg_data;
        }
        return svg.data;
    }

    // Last and second-to-last point of an SVG path's "d"
    private static bool path_end(string d, out double px, out double py,
                                 out double ex, out double ey) {
        px = 0; py = 0; ex = 0; ey = 0;
        var xs = new Gee.ArrayList<double?>();
        var ys = new Gee.ArrayList<double?>();
        try {
            var num = new Regex("(-?[0-9]+(?:\\.[0-9]+)?),(-?[0-9]+(?:\\.[0-9]+)?)");
            MatchInfo m;
            if (!num.match(d, 0, out m)) return false;
            do {
                xs.add(double.parse(m.fetch(1)));
                ys.add(double.parse(m.fetch(2)));
            } while (m.next());
        } catch (RegexError e) {
            return false;
        }
        int n = xs.size;
        if (n < 2) return false;
        px = xs[n - 2]; py = ys[n - 2];
        ex = xs[n - 1]; ey = ys[n - 1];
        return true;
    }

    private static string cross_path(string stroke, double px, double py, double ex, double ey) {
        double dx = ex - px, dy = ey - py;
        double len = Math.sqrt(dx * dx + dy * dy);
        if (len < 0.001) { dx = 1; dy = 0; len = 1; }
        dx /= len; dy /= len;
        // The two arms, at 45° to the line
        double k = 1 / Math.sqrt(2.0);
        double ax = (dx - dy) * k, ay = (dy + dx) * k;
        double bx = (dx + dy) * k, by = (dy - dx) * k;
        double r = 5.0;
        return "<path fill=\"none\" stroke=\"%s\" stroke-width=\"1.6\" d=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/>".printf(
            stroke,
            num(ex - r * ax), num(ey - r * ay), num(ex + r * ax), num(ey + r * ay),
            num(ex - r * bx), num(ey - r * by), num(ex + r * bx), num(ey + r * by));
    }

    // Outline of a block arrow filling the box
    private static string arrow_points(string dir, double x, double y, double w, double h, double cx, double cy) {
        double[] pts;
        bool vertical = dir == "up" || dir == "down" || dir == "y";
        double len = vertical ? h : w;
        double thick = vertical ? w : h;
        double head = double.min(thick / 2, len * 0.35);
        double body = thick * 0.3;       // half the shaft thickness
        double half = thick / 2;
        // Along the arrow axis a: from -len/2 to len/2; across it b
        double a0 = -len / 2, a1 = len / 2;
        switch (dir) {
            case "x":
            case "y":
                pts = { a0, 0, a0 + head, -half, a0 + head, -body, a1 - head, -body, a1 - head, -half,
                        a1, 0, a1 - head, half, a1 - head, body, a0 + head, body, a0 + head, half };
                break;
            default:
                pts = { a0, -body, a1 - head, -body, a1 - head, -half, a1, 0,
                        a1 - head, half, a1 - head, body, a0, body };
                break;
        }
        var sb = new StringBuilder();
        for (int i = 0; i + 1 < pts.length; i += 2) {
            double a = pts[i];
            double b = pts[i + 1];
            double px, py;
            switch (dir) {
                case "left":  px = cx - a; py = cy + b; break;
                case "up":    px = cx + b; py = cy - a; break;
                case "down":
                case "y":     px = cx + b; py = cy + a; break;
                default:      px = cx + a; py = cy + b; break;
            }
            if (sb.len > 0) sb.append(" ");
            sb.append("%s,%s".printf(num(px), num(py)));
        }
        // Close the outline like Graphviz does
        sb.append(" " + sb.str.split(" ")[0]);
        return sb.str;
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidBlock diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse DOT graph");
            return null;
        }

        // Positions are fixed in the DOT: nop2 keeps them and only routes the links
        int ret = ctx.layout(graph, "nop2");
        if (ret != 0) {
            warning("Failed to layout block diagram");
            return null;
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = RenderUtils.render_data(ctx, graph, "svg", out svg_data);

        ctx.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render graph");
            return null;
        }

        return draw_cross_ends(draw_shapes(svg_data));
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidBlock diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            handle.get_intrinsic_size_in_pixels(out width, out height);

            // A size librsvg cannot read means Graphviz wrote a broken canvas (an SVG width
            // past the int range came out negative). Painting a blank 400x300 instead made
            // that look like a successful render; fail so the caller reports it.
            if (width <= 0 || height <= 0) {
                warning("Block diagram SVG has no usable size (%g x %g)", width, height);
                return null;
            }
            // Scaled down to what Cairo can hold; the click regions below follow the size
            RenderUtils.fit_surface_size(ref width, ref height);

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

            var element_lines = new Gee.HashMap<string, int>();
            foreach (var node in diagram.nodes) {
                if (!node.is_group && !node.is_space && node.source_line > 0)
                    element_lines.set(node.id, node.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidBlock diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidBlock diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidBlock diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
