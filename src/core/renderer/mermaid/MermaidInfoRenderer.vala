/* MermaidInfoRenderer.vala — Mermaid `info` renderer on a pinned ChartCanvas
 *
 * mermaid's infoRenderer.ts draws a 400 × 100 canvas holding exactly one text
 * node, `v<version>`, at font-size 32. We keep that geometry and that single
 * line, but with two deliberate differences:
 *
 *   - the version is gDiagram's, not mermaid's — this diagram exists to answer
 *     "which renderer am I talking to", and gDiagram is the renderer;
 *   - mermaid pins the text at x=100 with text-anchor:middle on a 400-wide
 *     canvas, which leaves it crammed against the left quarter. We centre it.
 *
 * A `title` is drawn above the version line; mermaid's renderer accepts the
 * keyword in its grammar but never draws it.
 */
namespace GDiagram {

public class MermaidInfoRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // mermaid's configureSvgSize(svg, 100, 400, true).
    private const double PAGE_W = 400.0;
    private const double PAGE_H = 100.0;
    private const double VERSION_FONT = 32.0;

    private Gee.HashMap<string, string> region_names = new Gee.HashMap<string, string>();
    private Gee.HashMap<string, int> element_lines = new Gee.HashMap<string, int>();

    public MermaidInfoRenderer(Gvc.Context ctx,
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

    public string generate_dot(MermaidInfo diagram) {
        var palette = ThemeManager.get_active_palette();
        var cv = new ChartCanvas();
        region_names = new Gee.HashMap<string, string>();
        element_lines = new Gee.HashMap<string, int>();
        string text_color = palette.node_text;

        bool has_title = diagram.title != null && diagram.title.length > 0;
        double top = has_title ? 28 : 0;

        // ChartCanvas sizes the page from the drawn items (and always includes
        // the origin), so without a full-page spacer the card would hug the
        // text and the centred version string would sit off to the right.
        cv.rect(0, 0, PAGE_W, top + PAGE_H, palette.background, palette.background, 0, "info_page");

        if (has_title) {
            string node = cv.text(PAGE_W / 2, 14, diagram.title, 16, text_color, 'c', true, "info_title");
            note_region(node, "_info_title", diagram.source_line);
        }

        string version_node = cv.text(PAGE_W / 2, top + PAGE_H / 2,
            "v" + diagram.version, VERSION_FONT, text_color, 'c', false, "info_version");
        note_region(version_node, "_info_version", diagram.source_line);

        if (diagram.acc_descr != null && diagram.acc_descr.length > 0) {
            cv.text(PAGE_W / 2, top + PAGE_H - 12, diagram.acc_descr, 11, text_color, 'c',
                false, "info_descr");
        }

        return cv.finish("info", palette.background);
    }

    public uint8[]? render_to_svg(MermaidInfo diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse info DOT graph");
            return null;
        }

        int ret = context.layout(graph, layout_engine);
        if (ret != 0) {
            warning("Failed to lay out info graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render info graph");
            return null;
        }
        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidInfo diagram) {
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
            warning("Failed to render info SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidInfo diagram, string filename) {
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidInfo diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidInfo diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
