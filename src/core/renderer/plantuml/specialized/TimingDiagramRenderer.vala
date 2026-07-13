/* TimingDiagramRenderer.vala — renders PlantUML timing diagrams as Graphviz HTML TABLE */
namespace GDiagram {

public class TimingDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public TimingDiagramRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(TimingDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    node [shape=plaintext fontname=\"Sans\" fontsize=11]\n");
        sb.append("    edge [color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.signals.size == 0) {
            sb.append("    empty [label=\"(no signals defined)\" shape=note]\n}\n");
            return sb.str;
        }

        string title = (diagram.title != null && diagram.title.length > 0)
            ? Markup.escape_text(diagram.title)
            : "Timing Diagram";

        // Collect all unique time points across all signals
        var time_set = new Gee.TreeSet<int>();
        time_set.add(0);
        foreach (var sig in diagram.signals) {
            foreach (var sc in sig.state_changes) {
                time_set.add(sc.time_value);
            }
        }
        if (time_set.size == 0) time_set.add(0);

        var time_points = new Gee.ArrayList<int>();
        foreach (var t in time_set) time_points.add(t);
        int num_cols = time_points.size;

        sb.append("    timing [label=<\n");
        sb.append("        <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\">\n");

        // Title row
        sb.append_printf("        <TR><TD COLSPAN=\"%d\" ALIGN=\"CENTER\" BGCOLOR=\"%s\"><FONT COLOR=\"%s\"><B>%s</B></FONT></TD></TR>\n",
            num_cols + 1, palette.boundary_stroke, RenderUtils.contrast_text(palette.boundary_stroke), title);

        // Time header row
        sb.append("        <TR>\n");
        sb.append("          <TD BGCOLOR=\"%s\"><FONT COLOR=\"%s\"><B>Signal</B></FONT></TD>\n".printf(palette.node_border, RenderUtils.contrast_text(palette.node_border)));
        foreach (var t in time_points) {
            sb.append_printf("          <TD BGCOLOR=\"%s\" ALIGN=\"CENTER\"><FONT COLOR=\"%s\"><B>@%d</B></FONT></TD>\n", palette.node_border, RenderUtils.contrast_text(palette.node_border), t);
        }
        sb.append("        </TR>\n");

        // Signal state rows — cycle through palette roles for variety.
        string[] state_colors = {
            palette.system_fill,
            palette.container_fill,
            palette.component_fill,
            palette.person_fill,
            palette.accent_secondary,
            palette.accent_primary,
            palette.success,
            palette.warning
        };
        int color_seed = 0;

        foreach (var sig in diagram.signals) {
            string esc_label = Markup.escape_text(sig.label);
            sb.append("        <TR>\n");

            // Signal type icon prefix
            string type_prefix;
            switch (sig.signal_type) {
                case SignalType.BINARY: type_prefix = "[B] "; break;
                case SignalType.CLOCK:  type_prefix = "[C] "; break;
                case SignalType.ANALOG: type_prefix = "[~] "; break;
                case SignalType.ROBUST: type_prefix = "[R] "; break;
                default:                type_prefix = ""; break;
            }

            sb.append_printf("          <TD BGCOLOR=\"%s\" ALIGN=\"LEFT\"><B>%s%s</B></TD>\n",
                palette.grid, type_prefix, esc_label);

            // Build state map: time -> state
            var state_at = new Gee.HashMap<int, string>();
            string last_state = "";
            foreach (var sc in sig.state_changes) {
                state_at.set(sc.time_value, sc.state);
            }

            // Fill each time slot
            foreach (var t in time_points) {
                if (state_at.has_key(t)) last_state = state_at.get(t);
                string display_state = (last_state.length > 0) ? last_state : "-";
                string esc_state = Markup.escape_text(display_state);

                // Choose color based on state
                string bg;
                string lower_state = display_state.down();
                if (lower_state == "0" || lower_state == "low" || lower_state == "idle") {
                    bg = palette.grid;
                    esc_state = display_state;
                } else if (lower_state == "1" || lower_state == "high" || lower_state == "active") {
                    bg = state_colors[color_seed % state_colors.length];
                } else if (lower_state == "{hidden}" || lower_state == "-") {
                    bg = palette.node_fill;
                    esc_state = "";
                } else {
                    bg = state_colors[(color_seed + 2) % state_colors.length];
                }

                sb.append_printf("          <TD BGCOLOR=\"%s\" ALIGN=\"CENTER\">%s</TD>\n", bg, esc_state);
            }

            sb.append("        </TR>\n");
            color_seed++;
        }

        sb.append("        </TABLE>\n");
        sb.append("    >]\n");
        sb.append("}\n");
        return sb.str;
    }

    public uint8[]? render_to_svg(TimingDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = Gvc.Graph.read_string(dot);
        if (graph == null) {
            warning("Failed to parse Timing DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout Timing graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render Timing diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(TimingDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(TimingDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(TimingDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(TimingDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
