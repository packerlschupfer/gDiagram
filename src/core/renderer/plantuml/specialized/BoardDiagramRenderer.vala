/* BoardDiagramRenderer.vala — renders board/kanban layout as Graphviz DOT */
namespace GDiagram {

public class BoardDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public BoardDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // PlantUML's board geometry, in pixels: 150x70 cards on a 170x90 grid.
    private const double CARD_W = 150.0;
    private const double CARD_H = 70.0;
    private const double PITCH_X = 170.0;
    private const double PITCH_Y = 90.0;
    private const double MARGIN = 10.0;

    // Columns and cards laid out as PlantUML does: the columns side by side in
    // source order along the top row, each card one row below its parent,
    // and every card as wide as the leaves under it — so a card sits above its
    // first sub-card and the next card starts after the last one. Dashed lines
    // separate the levels.
    public string generate_dot(BoardDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var w = new PinnedDotWriter();
        double top = MARGIN;
        if (diagram.title != null && diagram.title.length > 0) {
            w.left_text(MARGIN, top + 10, diagram.title, 16, true, palette.node_text);
            top += 30;
        }

        int max_depth = 0;
        int slot = 0;
        foreach (var col in diagram.columns) {
            int used = place(w, col.title, col.source_line, col.cards, slot, 0, top, ref max_depth);
            slot += used;
        }
        double right = MARGIN + slot * PITCH_X - (PITCH_X - CARD_W) + 20;
        for (int level = 1; level <= max_depth; level++) {
            double y = top + level * PITCH_Y - (PITCH_Y - CARD_H) / 2;
            w.polyline({ MARGIN, y, right, y },
                "color=\"%s\" style=dashed penwidth=0.75".printf(palette.edge_color));
        }
        return w.finish(palette.background);
    }

    // Draws one card (or column title) and its sub-cards; returns the number
    // of grid slots the subtree takes.
    private int place(PinnedDotWriter w, string text, int line, Gee.ArrayList<BoardCard> children,
                      int slot, int depth, double top, ref int max_depth) {
        if (depth > max_depth) max_depth = depth;
        double x = MARGIN + slot * PITCH_X;
        double y = top + depth * PITCH_Y;
        // Drop shadow, then the card with its text in the top-left corner
        w.node(x + CARD_W / 2 + 3, y + CARD_H / 2 + 3, CARD_W, CARD_H,
            "shape=box style=filled fillcolor=\"#00000033\" color=\"#00000000\"");
        w.node(x + CARD_W / 2, y + CARD_H / 2, CARD_W, CARD_H,
            ("id=\"board_%d\" shape=box style=filled fillcolor=\"#C1C1C1\" color=\"#000000\" penwidth=0.75 " +
             "fontsize=%s fontcolor=\"#000000\" label=<<TABLE BORDER=\"0\" CELLPADDING=\"2\" CELLSPACING=\"0\">" +
             "<TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"%d\" ALIGN=\"LEFT\" VALIGN=\"TOP\">%s</TD></TR></TABLE>>").printf(
                line, PinnedDotWriter.num(14 * PinnedDotWriter.PX),
                (int) ((CARD_W - 4) * PinnedDotWriter.PX), (int) ((CARD_H - 4) * PinnedDotWriter.PX),
                Markup.escape_text(text)));
        int used = 0;
        foreach (var child in children) {
            used += place(w, child.text, child.source_line, child.children, slot + used, depth + 1, top, ref max_depth);
        }
        return int.max(1, used);
    }

    public uint8[]? render_to_svg(BoardDiagram diagram) {
        string dot = generate_dot(diagram);
        return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "board");
    }

    public Cairo.ImageSurface? render_to_surface(BoardDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            handle.get_intrinsic_size_in_pixels(out width, out height);

            if (width <= 0) width = 400;
            if (height <= 0) height = 300;

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

            return surface;
        } catch (Error e) {
            warning("Failed to create surface from SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(BoardDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(BoardDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(BoardDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
