/* MermaidMindmapRenderer.vala — renders Mermaid mindmaps via Graphviz
 *
 * The layout is computed here and pinned (layout=nop2): the root is centred
 * with its branches alternating right and left, the shape Mermaid's
 * cose-bilkent run settles into. Shapes, colours and
 * edge widths follow Mermaid 11.17's default theme: each top-level branch
 * has its own section colour that its subtree inherits, the root is blue,
 * default nodes are borderless boxes with a coloured underline, and edges
 * get thinner with depth. Cloud and bang outlines are drawn into the SVG in
 * place of the ellipse Graphviz laid out for them.
 */
namespace GDiagram {

public class MermaidMindmapRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    // Set by generate_dot(): the emitted graph carries explicit positions.
    private bool pinned = false;

    // Mermaid default theme: cScale0..10, their underline colours (cScaleInv)
    private const string[] SECTION_FILL = {
        "#FFFF78", "#D7FF86", "#C286FF", "#FF86FF", "#FF86C2", "#FF8686",
        "#FFC286", "#C2FF86", "#86FFC2", "#86FFFF", "#86C2FF"
    };
    private const string[] SECTION_LINE = {
        "#ABABFF", "#D0B9FF", "#DCFFB9", "#B9FFB9", "#B9FFDC", "#B9FFFF",
        "#B9DCFF", "#DCB9FF", "#FFB9DC", "#FFB9B9", "#FFDCB9"
    };
    private const string ROOT_FILL = "#0000EC";
    private const string ROOT_LINE = "#FFFFB9";

    // Mermaid's maxNodeWidth (px) at its 16 px font
    private const double MAX_NODE_WIDTH = 200;
    private const double FONT_PX = 16;

    public MermaidMindmapRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public static string section_fill(MindmapNode node) {
        return node.section < 0 ? ROOT_FILL : SECTION_FILL[node.section % SECTION_FILL.length];
    }

    public static string section_text(MindmapNode node) {
        return (node.section < 0 || node.section % SECTION_FILL.length == 2) ? "#FFFFFF" : "#000000";
    }

    private static string section_line(MindmapNode node) {
        return node.section < 0 ? ROOT_LINE : SECTION_LINE[node.section % SECTION_LINE.length];
    }

    public string generate_dot(MermaidMindmap diagram) {
        var palette = ThemeManager.get_active_palette();
        var placed = layout_tree(diagram);
        pinned = placed != null;

        var sb = new StringBuilder();
        sb.append("graph mindmap {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        if (placed != null) {
            sb.append("    layout=nop2\n");
        } else {
            sb.append("    overlap=false\n");
            sb.append("    splines=true\n");
            sb.append("    ranksep=0.6\n");
        }
        sb.append("    node [fontname=\"Sans\" fontsize=%s style=filled penwidth=0]\n".printf(num(FONT_PT)));
        sb.append("    edge [color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.root != null) {
            emit_node(sb, diagram.root, placed);
            emit_edges(sb, diagram.root);
        }

        sb.append("}\n");
        return sb.str;
    }

    // ==================== layout ====================

    private const double FONT_PT = 12;
    private const double H_GAP = 45;       // between a node and its children
    private const double V_GAP = 14;       // between siblings
    private const double LAYOUT_MARGIN = 20;

    private class MmBox : Object {
        public double w;
        public double h;
        public double x;      // centre, points
        public double y;
        public double sub_h;  // height of the whole subtree
    }

    /**
     * Measures every node by laying the bare graph out once and reading
     * Graphviz's own `plain` output (sizes in inches), so the pinned layout
     * uses exactly the boxes Graphviz will draw.
     */
    private Gee.HashMap<string, MmBox>? measure(MermaidMindmap diagram) {
        var sb = new StringBuilder();
        sb.append("graph mm {\n");
        sb.append("    node [fontname=\"Sans\" fontsize=%s style=filled penwidth=0]\n".printf(num(FONT_PT)));
        if (diagram.root != null) emit_node(sb, diagram.root, null);
        sb.append("}\n");

        var graph = RenderUtils.read_dot(sb.str);
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
        var boxes = new Gee.HashMap<string, MmBox>();
        foreach (string line in text.str.split("\n")) {
            if (!line.has_prefix("node ")) continue;
            string[] f = line.split(" ");
            if (f.length < 6) continue;
            var b = new MmBox();
            b.w = double.parse(f[4]) * 72.0;
            b.h = double.parse(f[5]) * 72.0;
            if (b.w <= 0 || b.h <= 0) continue;
            boxes.set(f[1], b);
        }
        return boxes.size > 0 ? boxes : null;
    }

    private double subtree_height(MindmapNode node, Gee.HashMap<string, MmBox> boxes) {
        var b = boxes.get(node_id(node));
        if (b == null) return 0;
        double own = b.h;
        double stacked = 0;
        int k = 0;
        foreach (var child in node.children) {
            double ch = subtree_height(child, boxes);
            if (ch <= 0) continue;
            stacked += ch;
            k++;
        }
        if (k > 1) stacked += (k - 1) * V_GAP;
        b.sub_h = double.max(own, stacked);
        return b.sub_h;
    }

    // Places a subtree growing away from the root: dir +1 to the right, -1 left.
    private void place(MindmapNode node, Gee.HashMap<string, MmBox> boxes,
                       double edge_x, double centre_y, int dir) {
        var b = boxes.get(node_id(node));
        if (b == null) return;
        b.x = edge_x + dir * b.w / 2;
        b.y = centre_y;
        if (node.children.size == 0) return;
        double next_edge = edge_x + dir * (b.w + H_GAP);
        double total = 0;
        int k = 0;
        foreach (var child in node.children) {
            var cb = boxes.get(node_id(child));
            if (cb == null) continue;
            total += cb.sub_h;
            k++;
        }
        if (k > 1) total += (k - 1) * V_GAP;
        double y = centre_y - total / 2;
        foreach (var child in node.children) {
            var cb = boxes.get(node_id(child));
            if (cb == null) continue;
            place(child, boxes, next_edge, y + cb.sub_h / 2, dir);
            y += cb.sub_h + V_GAP;
        }
    }

    /**
     * Mermaid lays mindmaps out with cose-bilkent, which settles into a root in
     * the middle with its branches fanning out on both sides. This reproduces
     * that shape deterministically: the root is centred and its top-level
     * branches alternate right and left, each drawn as a compact horizontal
     * tree. Returns null (Graphviz keeps its own layout) if measuring fails.
     */
    private Gee.HashMap<string, MmBox>? layout_tree(MermaidMindmap diagram) {
        if (diagram.root == null) return null;
        var boxes = measure(diagram);
        if (boxes == null) return null;
        var root_box = boxes.get(node_id(diagram.root));
        if (root_box == null) return null;

        var right = new Gee.ArrayList<MindmapNode>();
        var left = new Gee.ArrayList<MindmapNode>();
        for (int i = 0; i < diagram.root.children.size; i++) {
            (i % 2 == 0 ? right : left).add(diagram.root.children.get(i));
        }
        foreach (var c in diagram.root.children) subtree_height(c, boxes);

        root_box.x = 0;
        root_box.y = 0;
        place_side(right, boxes, root_box.w / 2 + H_GAP, 1);
        place_side(left, boxes, -root_box.w / 2 - H_GAP, -1);

        // Shift into positive space and flip to Graphviz's y-up coordinates.
        double min_x = double.MAX, min_y = double.MAX, max_y = -double.MAX;
        foreach (var b in boxes.values) {
            min_x = double.min(min_x, b.x - b.w / 2);
            min_y = double.min(min_y, b.y - b.h / 2);
            max_y = double.max(max_y, b.y + b.h / 2);
        }
        double ox = LAYOUT_MARGIN - min_x;
        double height = (max_y - min_y) + 2 * LAYOUT_MARGIN;
        foreach (var b in boxes.values) {
            b.x += ox;
            b.y = height - (b.y - min_y + LAYOUT_MARGIN);
        }
        return boxes;
    }

    private void place_side(Gee.ArrayList<MindmapNode> branches, Gee.HashMap<string, MmBox> boxes,
                            double edge_x, int dir) {
        double total = 0;
        int k = 0;
        foreach (var n in branches) {
            var b = boxes.get(node_id(n));
            if (b == null) continue;
            total += b.sub_h;
            k++;
        }
        if (k > 1) total += (k - 1) * V_GAP;
        double y = -total / 2;
        foreach (var n in branches) {
            var b = boxes.get(node_id(n));
            if (b == null) continue;
            place(n, boxes, edge_x, y + b.sub_h / 2, dir);
            y += b.sub_h + V_GAP;
        }
    }

    // Generate a unique stable node ID using source line and depth
    private string node_id(MindmapNode node) {
        return "n_%d_%d".printf(node.source_line, node.depth);
    }

    // Word-wrap to Mermaid's node width; returns HTML-label lines
    private static string html_label(MindmapNode node) {
        var out_lines = new Gee.ArrayList<string>();
        foreach (string para in node.label.split("\n")) {
            string[] words = para.split(" ");
            var line = new StringBuilder();
            foreach (string w in words) {
                if (w.length == 0) continue;
                string candidate = line.len == 0 ? w : line.str + " " + w;
                string measured = node.markdown ? markdown_plain(candidate) : candidate;
                if (line.len > 0 && GanttText.width(measured, FONT_PX, false, "Sans") > MAX_NODE_WIDTH) {
                    out_lines.add(line.str);
                    line.assign(w);
                } else {
                    line.assign(candidate);
                }
            }
            out_lines.add(line.str);
        }
        var sb = new StringBuilder();
        for (int i = 0; i < out_lines.size; i++) {
            if (i > 0) sb.append("<BR/>");
            sb.append(node.markdown ? markdown_html(out_lines[i]) : Markup.escape_text(out_lines[i]));
        }
        return sb.str;
    }


    // Marker kinds in the tokenized label.
    private const int MD_TEXT = 0;
    private const int MD_BOLD = 1;
    private const int MD_ITALIC = 2;

    /**
     * **bold** and *italic* / _italic_ to Graphviz HTML.
     *
     * A marker only becomes a tag when a later marker of the same kind closes
     * it with at least one character in between; every other marker stays
     * literal text. Graphviz's HTML-label parser rejects an empty `<B></B>` or
     * `<I></I>` and then drops the *whole* label, so `Rating 5*` used to come
     * out as an empty box plus a "syntax error in line 1" on stderr.
     *
     * Tokenizing first also keeps this linear: the old loop took `s.substring(i)`
     * on every byte just to test a two-character prefix.
     */
    private static string markdown_html(string s) {
        return md_convert(s, true);
    }

    // The text markdown_html() will actually show, for width measurement.
    private static string markdown_plain(string s) {
        return md_convert(s, false);
    }

    private static string md_convert(string s, bool html) {
        var kinds = new Gee.ArrayList<int>();
        var texts = new Gee.ArrayList<string>();
        var run = new StringBuilder();
        int i = 0;
        while (i < s.length) {
            char c = s[i];
            bool marker = (c == '*' || c == '_');
            if (marker) {
                bool doubled = (i + 1 < s.length && s[i + 1] == c);
                if (run.len > 0) { kinds.add(MD_TEXT); texts.add(run.str); run.truncate(); }
                kinds.add(doubled ? MD_BOLD : MD_ITALIC);
                texts.add(doubled ? "%c%c".printf(c, c) : "%c".printf(c));
                i += doubled ? 2 : 1;
                continue;
            }
            run.append_c(c);
            i++;
        }
        if (run.len > 0) { kinds.add(MD_TEXT); texts.add(run.str); }

        var opens = new bool[kinds.size];
        var closes = new bool[kinds.size];
        for (int kind = MD_BOLD; kind <= MD_ITALIC; kind++) {
            int open = -1;
            bool saw_text = false;
            for (int j = 0; j < kinds.size; j++) {
                if (kinds[j] == MD_TEXT) {
                    if (texts[j].length > 0) saw_text = true;
                    continue;
                }
                if (kinds[j] != kind) continue;
                if (open < 0) { open = j; saw_text = false; continue; }
                if (!saw_text) continue;   // the tag pair would be empty
                opens[open] = true;
                closes[j] = true;
                open = -1;
                saw_text = false;
            }
        }

        var sb = new StringBuilder();
        for (int j = 0; j < kinds.size; j++) {
            if (kinds[j] == MD_TEXT) {
                sb.append(html ? Markup.escape_text(texts[j]) : texts[j]);
                continue;
            }
            if (opens[j] || closes[j]) {
                // A paired marker becomes a tag, and shows no text either way.
                if (html) sb.append(opens[j] ? "<%s>".printf(kinds[j] == MD_BOLD ? "B" : "I")
                                             : "</%s>".printf(kinds[j] == MD_BOLD ? "B" : "I"));
                continue;
            }
            sb.append(html ? Markup.escape_text(texts[j]) : texts[j]);
        }
        return sb.str;
    }

    /**
     * `::icon(fa fa-book)` names a glyph from an icon font we do not bundle, so
     * rather than drawing a wrong glyph or silently dropping the decoration we
     * print the icon's own name — small, italic and on its own line above the
     * label, where it stays out of the way.
     */
    private static string icon_html(MindmapNode node) {
        if (node.icon == null) return "";
        string s = node.icon.strip();
        if (s.length == 0) return "";
        string[] parts = s.split(" ");
        string last = parts[parts.length - 1];
        int dash = last.index_of("-");
        if (dash > 0 && dash + 1 < last.length) last = last.substring(dash + 1);
        return "<FONT POINT-SIZE=\"8\"><I>%s</I></FONT><BR/>".printf(Markup.escape_text(last));
    }

    // The node's DOT attribute list, without any position.
    private string node_attrs(MindmapNode node) {
        string fill = section_fill(node);
        string text = section_text(node);
        string label = "<FONT COLOR=\"%s\">%s%s</FONT>".printf(text, icon_html(node), html_label(node));

        switch (node.shape) {
            case "circle":
                return "label=<%s> shape=circle margin=\"0.06,0.06\" fillcolor=\"%s\" color=\"%s\"".printf(
                    label, fill, fill);
            case "rounded":
                return "label=<%s> shape=box style=\"filled,rounded\" margin=\"0.21,0.14\" fillcolor=\"%s\" color=\"%s\"".printf(
                    label, fill, fill);
            case "rectangle":
                return "label=<%s> shape=box margin=\"0.14,0.1\" fillcolor=\"%s\" color=\"%s\"".printf(
                    label, fill, fill);
            case "hexagon":
                return "label=<%s> shape=hexagon margin=\"0.1,0.08\" fillcolor=\"%s\" color=\"%s\"".printf(
                    label, fill, fill);
            case "cloud":
            case "bang":
                // Laid out as an ellipse; the outline is replaced in the SVG
                return "label=<%s> shape=ellipse margin=\"0.12,0.1\" fillcolor=\"%s\" color=\"%s\"".printf(
                    label, fill, fill);
            default:
                // Borderless box with a 3 px underline in the section's line colour
                return ("shape=plain style=solid label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">" +
                    "<TR><TD BGCOLOR=\"%s\" CELLPADDING=\"7\">&#160;%s&#160;</TD></TR>" +
                    "<TR><TD BGCOLOR=\"%s\" HEIGHT=\"3\"></TD></TR></TABLE>>").printf(
                    fill, label, section_line(node));
        }
    }

    private void emit_node(StringBuilder sb, MindmapNode node, Gee.Map<string, MmBox>? placed) {
        string nid = node_id(node);
        var box = placed != null ? placed.get(nid) : null;
        if (box != null) {
            sb.append_printf("    %s [%s pos=\"%s,%s\"]\n", nid, node_attrs(node), num(box.x), num(box.y));
        } else {
            sb.append_printf("    %s [%s]\n", nid, node_attrs(node));
        }
        foreach (var child in node.children) {
            emit_node(sb, child, placed);
        }
    }

    private void collect_mindmap_lines(MindmapNode node, Gee.HashMap<string, int> element_lines) {
        if (node.source_line > 0)
            element_lines.set(node_id(node), node.source_line);
        foreach (var child in node.children)
            collect_mindmap_lines(child, element_lines);
    }

    private void collect_outlines(MindmapNode node, Gee.HashMap<string, string> outlines) {
        if (node.shape == "cloud" || node.shape == "bang") outlines[node_id(node)] = node.shape;
        foreach (var child in node.children) collect_outlines(child, outlines);
    }

    private void emit_edges(StringBuilder sb, MindmapNode parent) {
        foreach (var child in parent.children) {
            // Mermaid: edge-depth-(parent level + 1) has stroke-width 17 - 3 * (depth + 1),
            // falling back to 3 when that is not positive
            int depth = parent.level + 1;
            double width = 17 - 3 * (depth + 1);
            if (width <= 0) width = 3;
            sb.append_printf("    %s -- %s [color=\"%s\" penwidth=%s]\n", node_id(parent), node_id(child),
                section_fill(child), num(width * 0.75));
            emit_edges(sb, child);
        }
    }

    // Replace the ellipse of cloud / bang nodes with a scalloped outline
    private static string replace_outlines(string svg, Gee.HashMap<string, string> outlines) {
        if (outlines.size == 0) return svg;
        string result = svg;
        foreach (var e in outlines.entries) {
            try {
                var re = new Regex("(<title>" + Regex.escape_string(e.key) + "</title>\\s*)<ellipse fill=\"([^\"]*)\" stroke=\"([^\"]*)\"(?: stroke-width=\"[^\"]*\")? cx=\"([^\"]*)\" cy=\"([^\"]*)\" rx=\"([^\"]*)\" ry=\"([^\"]*)\"/>");
                MatchInfo m;
                if (!re.match(result, 0, out m)) continue;
                double cx = double.parse(m.fetch(4)), cy = double.parse(m.fetch(5));
                double rx = double.parse(m.fetch(6)), ry = double.parse(m.fetch(7));
                string path = scallop_path(cx, cy, rx, ry, e.value == "cloud");
                string repl = "%s<path fill=\"%s\" stroke=\"%s\" d=\"%s\"/>".printf(
                    m.fetch(1), m.fetch(2), m.fetch(3), path);
                int start, end;
                m.fetch_pos(0, out start, out end);
                result = result.substring(0, start) + repl + result.substring(end);
            } catch (RegexError err) {
                warning("mindmap outline regex: %s", err.message);
            }
        }
        return result;
    }

    // Arcs between points on the ellipse: bulging out (cloud) or in (bang)
    public static string scallop_path(double cx, double cy, double rx, double ry, bool outward) {
        double perimeter = Math.PI * (3 * (rx + ry) - Math.sqrt((3 * rx + ry) * (rx + 3 * ry)));
        int n = int.max(8, (int) Math.round(perimeter / (outward ? 38 : 22)));
        var sb = new StringBuilder();
        double px = 0, py = 0;
        for (int i = 0; i <= n; i++) {
            double a = 2 * Math.PI * i / n;
            double x = cx + rx * Math.cos(a);
            double y = cy + ry * Math.sin(a);
            if (i == 0) {
                sb.append("M%s,%s".printf(num(x), num(y)));
            } else {
                double chord = Math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
                double r = chord * (outward ? 0.62 : 0.8);
                sb.append(" A%s,%s 0 0,%d %s,%s".printf(num(r), num(r), outward ? 1 : 0, num(x), num(y)));
            }
            px = x;
            py = y;
        }
        sb.append(" Z");
        return sb.str;
    }

    private static string num(double v) {
        return "%.2f".printf(v).replace(",", ".");
    }

    // Render to SVG using Graphviz
    public uint8[]? render_to_svg(MermaidMindmap diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse mindmap DOT graph");
            return null;
        }

        // Positions are pinned by layout_tree(); twopi is only the fallback
        // for the (measurement failed) case where generate_dot emitted none.
        int ret = context.layout(graph, pinned ? "nop2" : "twopi");
        if (ret != 0) {
            warning("Failed to layout mindmap graph, trying %s", layout_engine);
            ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout mindmap graph");
                return null;
            }
        }

        uint8[] svg_data;
        // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render mindmap graph");
            return null;
        }

        var outlines = new Gee.HashMap<string, string>();
        if (diagram.root != null) collect_outlines(diagram.root, outlines);
        if (outlines.size > 0) {
            var buf = new StringBuilder.sized(svg_data.length + 1);
            buf.append_len((string) svg_data, svg_data.length);
            string text = replace_outlines(buf.str, outlines);
            return text.data;
        }
        return svg_data;
    }

    // Render to Cairo surface
    public Cairo.ImageSurface? render_to_surface(MermaidMindmap diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 400, out width, out height);

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
            if (diagram.root != null)
                collect_mindmap_lines(diagram.root, element_lines);
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render mindmap SVG: %s", e.message);
            return null;
        }
    }

    // Export methods
    public bool export_to_png(MermaidMindmap diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidMindmap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidMindmap diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
