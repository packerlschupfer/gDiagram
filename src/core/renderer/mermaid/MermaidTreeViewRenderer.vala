/* MermaidTreeViewRenderer.vala — Mermaid `treeView-beta` renderer
 *
 * Port of mermaid 12.2.0's treeView renderer.ts. The drawing is a pinned
 * layout — one row per node in pre-order, an elbow of two straight lines per
 * parent — so it goes through ChartCanvas (layout=nop2) like the other
 * fixed-geometry Mermaid renderers rather than through a Graphviz rank layout.
 *
 * Geometry (mermaid's treeView config defaults: rowIndent 10, paddingX 5,
 * paddingY 5, lineThickness 1, showIcons false):
 *   indent   = depth * (rowIndent + paddingX)
 *   row      = labelHeight + 2 * paddingY, rows stacked from y = 0
 *   stub     = a horizontal line from indent - rowIndent to indent, at mid-row
 *   trunk    = a vertical line at indent + paddingX from the bottom of a
 *              parent's row down to the middle of its last child's row
 *   descriptions are right of the widest label, in one column
 *
 * Everything is laid out before anything is drawn: the highlight band of a
 * `:::highlight` row spans the whole tree width, which is only known once the
 * last description has been measured, and it has to be painted *under* the
 * label (ChartCanvas draws in insertion order).
 */
namespace GDiagram {

public class MermaidTreeViewRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;
    private Gee.HashMap<string, int> _element_lines = new Gee.HashMap<string, int>();

    public MermaidTreeViewRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // mermaid's treeView config defaults, in points.
    private const double ROW_INDENT = 10.0;
    private const double PAD_X = 5.0;
    private const double PAD_Y = 5.0;
    private const double LINE_THICKNESS = 1.0;
    private const double FONT = 16.0;
    private const double ICON_SIZE = 14.0;
    private const double ICON_GAP = 4.0;
    private const double DESC_GAP = 16.0;
    // getBBox().height of one label line as a multiple of the font size,
    // measured from Mermaid's own output (17.015625 at 16px). A measured Sans
    // height would be ~1.44 em and stretch every row pitch past Mermaid's.
    private const double LABEL_HEIGHT_RATIO = 1.0635;

    /** One laid-out row. */
    private class Row : Object {
        public TreeViewNode node;
        public int depth;
        public double x;            // row indent
        public double y;            // row top
        public double w;
        public double h;
        public double label_x;
        public double center_y;
        public double label_right;
        public string? icon;        // resolved icon name, null = none
        public Row(TreeViewNode node, int depth) {
            this.node = node;
            this.depth = depth;
        }
    }

    private class Trunk : Object {
        public double x;
        public double y1;
        public double y2;
        public Trunk(double x, double y1, double y2) { this.x = x; this.y1 = y1; this.y2 = y2; }
    }

    private Gee.ArrayList<Row> rows;
    private Gee.ArrayList<Trunk> trunks;
    private double total_height;
    private double total_width;

    public string generate_dot(MermaidTreeView diagram) {
        this._element_lines = new Gee.HashMap<string, int>();
        var palette = ThemeManager.get_active_palette();
        var canvas = new ChartCanvas();

        layout_tree(diagram);

        // The description column sits right of the widest label.
        double max_label_right = 0;
        bool any_desc = false;
        foreach (var r in rows) {
            max_label_right = double.max(max_label_right, r.label_right);
            if (r.node.description != null) any_desc = true;
        }
        double desc_x = max_label_right + DESC_GAP;
        if (any_desc) {
            foreach (var r in rows) {
                if (r.node.description == null) continue;
                total_width = double.max(total_width,
                    desc_x + ChartCanvas.text_width(r.node.description, FONT) + PAD_X);
            }
        }

        // Highlight bands, widened to the whole tree. mermaid grows totalWidth
        // inside this same loop, so a second highlighted row is wider again.
        var band_width = new Gee.HashMap<Row, double?>();
        foreach (var r in rows) {
            if (!r.node.has_class("highlight")) continue;
            double width = total_width - r.x + 8;
            band_width.set(r, width);
            total_width = double.max(total_width, r.x + width + 2);
        }

        string line_color = palette.edge_color;
        string label_color = palette.node_text;
        string desc_color = palette.success;
        // The highlight band keeps Mermaid's amber literally: every gDiagram
        // palette's `warning` is a red, which reads as an error rather than as
        // the emphasis a `:::highlight` class asks for, and amber carries on
        // both a light and a dark canvas.
        string band_stroke = "#ffc107";
        string band_fill = "#ffc10726";                    // rgba(255,193,7,0.15)

        // Bands first: ChartCanvas draws in insertion order and they go under
        // the labels.
        foreach (var r in rows) {
            if (!band_width.has_key(r)) continue;
            canvas.rect(r.x, r.y + 1, band_width.get(r), r.h - 2, band_fill, band_stroke,
                LINE_THICKNESS, "treeview_highlight_%d".printf(r.node.source_line));
        }

        foreach (var r in rows) {
            canvas.line(r.x - ROW_INDENT, r.center_y, r.x, r.center_y, line_color, LINE_THICKNESS);
        }
        foreach (var t in trunks) {
            canvas.line(t.x, t.y1, t.x, t.y2, line_color, LINE_THICKNESS);
        }

        foreach (var r in rows) {
            if (r.icon != null) {
                canvas.shape(r.x + PAD_X + ICON_SIZE / 2, r.y + PAD_Y + ICON_SIZE / 2,
                    ICON_SIZE, ICON_SIZE,
                    "shape=%s style=solid color=\"%s\" penwidth=%s label=\"\"".printf(
                        icon_shape(r.icon), line_color, ChartCanvas.num(LINE_THICKNESS)));
            }
            string name = canvas.text(r.label_x, r.center_y, r.node.name, FONT, label_color,
                'l', r.node.is_directory(), "treeview_node_%d".printf(r.node.source_line));
            if (name.length > 0 && r.node.source_line > 0) {
                _element_lines.set(name, r.node.source_line);
            }
            if (r.node.description != null) {
                canvas.text(desc_x, r.center_y, r.node.description, FONT, desc_color,
                    'l', false, null, true);
            }
        }

        return canvas.finish("treeView", palette.background);
    }

    /**
     * Rows and trunks in pre-order from the synthetic root, which mermaid draws
     * as a "/" directory row of its own.
     */
    private void layout_tree(MermaidTreeView diagram) {
        rows = new Gee.ArrayList<Row>();
        trunks = new Gee.ArrayList<Trunk>();
        total_height = 0;
        total_width = 0;
        walk(diagram.root, 0);
    }

    private Row walk(TreeViewNode node, int depth) {
        var row = place(node, depth);
        rows.add(row);
        Row? last = null;
        foreach (var child in node.children) last = walk(child, depth + 1);
        if (last != null) {
            trunks.add(new Trunk(row.x + PAD_X, row.y + row.h,
                last.y + last.h / 2 + LINE_THICKNESS / 2));
        }
        return row;
    }

    private Row place(TreeViewNode node, int depth) {
        var row = new Row(node, depth);
        row.icon = resolve_icon(node);
        bool bold = node.is_directory();
        double label_w = ChartCanvas.text_width(node.name, FONT, bold);
        double label_h = FONT * LABEL_HEIGHT_RATIO;
        double icon_offset = row.icon != null ? ICON_SIZE + ICON_GAP : 0;

        row.x = depth * (ROW_INDENT + PAD_X);
        row.y = total_height;
        row.h = label_h + PAD_Y * 2;
        row.w = label_w + PAD_X * 2 + icon_offset;
        row.label_x = row.x + PAD_X + icon_offset;
        row.center_y = row.y + row.h / 2;
        row.label_right = row.label_x + label_w;

        total_width = double.max(total_width, row.x + row.w);
        total_height += row.h;
        return row;
    }

    /**
     * icons.ts getNodeIcon(): an explicit `icon()` annotation wins and `none`
     * hides the icon; without one nothing is drawn, because mermaid's
     * `showIcons` defaults to false and gDiagram has no iconify packs to
     * resolve a name against.
     */
    private static string? resolve_icon(TreeViewNode node) {
        if (node.icon == null || node.icon == "none") return null;
        return node.icon;
    }

    /**
     * The two built-in icons as Graphviz shapes: a folder outline and a
     * dog-eared page. Any other name comes from an iconify pack that is not
     * bundled, so it gets a plain box placeholder of the same size — the row
     * geometry stays identical either way.
     */
    private static string icon_shape(string icon) {
        string name = icon;
        int colon = name.last_index_of(":");
        if (colon >= 0) name = name.substring(colon + 1);
        switch (name) {
            case "folder": return "folder";
            case "file":   return "note";
            default:       return "box";
        }
    }

    public uint8[]? render_to_svg(MermaidTreeView diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse treeView DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out treeView graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render treeView graph");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidTreeView diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 600, 400, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
            var cr = new Cairo.Context(surface);
            cr.set_source_rgb(1, 1, 1);
            cr.paint();

            var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
            handle.render_document(cr, viewport);

            RenderUtils.parse_svg_regions(svg_data, regions, _element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render treeView SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidTreeView diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidTreeView diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidTreeView diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
