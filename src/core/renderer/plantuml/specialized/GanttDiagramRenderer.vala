/* GanttDiagramRenderer.vala — renders PlantUML Gantt chart using Graphviz */
namespace GDiagram {

public class GanttDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> last_regions;
    private string layout_engine;

    public GanttDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.last_regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(PumlGanttDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [shape=plaintext fontname=\"Sans\" fontsize=11]\n");
        sb.append("    edge [color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.tasks.size == 0) {
            sb.append("    empty [label=\"(no tasks defined)\" shape=note]\n");
            sb.append("}\n");
            return sb.str;
        }

        // Find max duration for scaling bars
        int max_dur = 1;
        foreach (var t in diagram.tasks) {
            if (t.duration_days > max_dur) max_dur = t.duration_days;
        }
        int max_bar_width = 200;

        sb.append("    gantt [label=<\n");
        sb.append("        <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"2\" CELLPADDING=\"4\">\n");

        // Title row
        string title_text = (diagram.title != null && diagram.title.length > 0)
            ? RenderUtils.escape_label(diagram.title)
            : "Gantt Chart";
        sb.append_printf("        <TR><TD COLSPAN=\"3\" ALIGN=\"CENTER\"><B><FONT POINT-SIZE=\"14\" COLOR=\"%s\">%s</FONT></B></TD></TR>\n", palette.node_text, title_text);

        // Header row
        sb.append("        <TR>\n");
        sb.append_printf("          <TD BGCOLOR=\"%s\"><FONT COLOR=\"%s\"><B>Task</B></FONT></TD>\n", palette.node_border, RenderUtils.contrast_text(palette.node_border));
        sb.append_printf("          <TD BGCOLOR=\"%s\"><FONT COLOR=\"%s\"><B>Duration</B></FONT></TD>\n", palette.node_border, RenderUtils.contrast_text(palette.node_border));
        sb.append_printf("          <TD BGCOLOR=\"%s\" WIDTH=\"220\"><FONT COLOR=\"%s\"><B>Timeline</B></FONT></TD>\n", palette.node_border, RenderUtils.contrast_text(palette.node_border));
        sb.append("        </TR>\n");

        string? current_section = null;
        foreach (var task in diagram.tasks) {
            // Section header row
            if (task.section != null && task.section != current_section) {
                current_section = task.section;
                string esc_sec = RenderUtils.escape_label(task.section);
                sb.append_printf("        <TR><TD COLSPAN=\"3\" BGCOLOR=\"%s\"><B>%s</B></TD></TR>\n", palette.grid, esc_sec);
            }

            string esc_name = RenderUtils.escape_label(task.name);
            string dur_str;
            string bg_color;
            if (task.is_milestone) {
                dur_str = "milestone";
                bg_color = palette.accent_secondary;
            } else {
                dur_str = "%d days".printf(task.duration_days);
                bg_color = palette.system_fill;
            }
            if (task.color != null && task.color.length > 0) {
                bg_color = normalize_color(task.color);
            }

            // Bar width proportional to duration
            int bar_w = (int)((double)task.duration_days / (double)max_dur * (double)max_bar_width);
            if (bar_w < 10) bar_w = 10;

            string completion_bar = "";
            if (task.completion_pct > 0 && !task.is_milestone) {
                completion_bar = " (%d%%)".printf(task.completion_pct);
            }

            sb.append("        <TR>\n");
            sb.append_printf("          <TD ALIGN=\"LEFT\">%s</TD>\n", esc_name);
            sb.append_printf("          <TD ALIGN=\"RIGHT\">%s%s</TD>\n", dur_str, completion_bar);
            if (task.is_milestone) {
                sb.append_printf("          <TD><TABLE BORDER=\"0\"><TR><TD WIDTH=\"20\" BGCOLOR=\"%s\">&#9670;</TD></TR></TABLE></TD>\n",
                    bg_color);
            } else {
                sb.append_printf("          <TD><TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\"><TR><TD WIDTH=\"%d\" BGCOLOR=\"%s\"> </TD><TD> </TD></TR></TABLE></TD>\n",
                    bar_w, bg_color);
            }
            sb.append("        </TR>\n");
        }

        sb.append("        </TABLE>\n");
        sb.append("    >]\n");
        sb.append("}\n");
        return sb.str;
    }

    private string normalize_color(string color) {
        string c = color.strip();
        // Hex color with proper format — keep as-is
        if (c.has_prefix("#") && (c.length == 7 || c.length == 4)) return c;
        // Named color with # prefix — strip the #
        if (c.has_prefix("#")) {
            return c.substring(1);
        }
        return c;
    }

    public uint8[]? render_to_svg(PumlGanttDiagram diagram) {
        string dot = generate_dot(diagram);

        try {
            string tmp_dot = "/tmp/gdiagram_gantt.dot";
            string tmp_svg = "/tmp/gdiagram_gantt.svg";

            FileUtils.set_contents(tmp_dot, dot);

            string[] argv = {layout_engine, "-Tsvg", "-o", tmp_svg, tmp_dot};
            int exit_status;
            Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

            if (exit_status != 0) {
                warning("Graphviz returned error %d for Gantt diagram", exit_status);
                return null;
            }

            string svg_content;
            FileUtils.get_contents(tmp_svg, out svg_content);

            return svg_content.data;
        } catch (Error e) {
            warning("Failed to render Gantt diagram: %s", e.message);
            return null;
        }
    }

    public Cairo.ImageSurface? render_to_surface(PumlGanttDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(PumlGanttDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(PumlGanttDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(PumlGanttDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
