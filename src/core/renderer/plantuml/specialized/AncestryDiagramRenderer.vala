/* AncestryDiagramRenderer.vala — renders ancestry/family tree as Graphviz DOT */
namespace GDiagram {

public class AncestryDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Gender-based fill colors
    private const string MALE_FILL = "#4A90D9";
    private const string FEMALE_FILL = "#D94A7A";
    private const string MALE_FILL_DECEASED = "#7AABD4";
    private const string FEMALE_FILL_DECEASED = "#D47A9A";

    public AncestryDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    public string generate_dot(AncestryDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph ancestry {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    splines=ortho\n");
        sb.append("    nodesep=0.25\n");
        sb.append("    ranksep=0.45\n");
        sb.append("    node [fontname=\"Sans\" fontsize=11 margin=\"0.15,0.08\"]\n");
        sb.append("    edge [color=\"%s\" arrowhead=none penwidth=1.2 fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
            sb.append("    labelloc=t\n");
            sb.append("    fontsize=16\n");
            sb.append("    fontname=\"Sans Bold\"\n");
            sb.append("    fontcolor=\"%s\"\n\n".printf(palette.node_text));
        }

        // Render person nodes
        foreach (var person in diagram.persons) {
            string fill = get_person_fill(person, palette);
            string text_color = RenderUtils.contrast_text(fill);
            string date_str = person.get_date_string();

            // Convert newlines in display name to <BR/> for HTML labels
            string name_html = Markup.escape_text(person.display_name).replace("\n", "<BR/>");

            sb.append_printf("    %s [\n", person.id);
            sb.append("        shape=plaintext\n");
            sb.append("        label=<\n");
            sb.append_printf("            <TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"6\" BGCOLOR=\"%s\" COLOR=\"%s\" STYLE=\"ROUNDED\">\n",
                fill, palette.node_border);
            sb.append_printf("                <TR><TD><FONT COLOR=\"%s\" POINT-SIZE=\"11\"><B>%s</B></FONT></TD></TR>\n",
                text_color, name_html);
            // Always emit a date row for consistent node height.
            // Use non-breaking space placeholder when no date is known.
            string date_html = date_str.length > 0
                ? Markup.escape_text(date_str)
                : "&#160;";
            sb.append_printf("                <TR><TD><FONT COLOR=\"%s\" POINT-SIZE=\"9\">%s</FONT></TD></TR>\n",
                text_color, date_html);
            sb.append("            </TABLE>\n");
            sb.append("        >\n");
            sb.append("    ]\n\n");
        }

        // Build a set of children per marriage for parent-child edges
        // marriage_key -> list of child IDs
        var marriage_children = new Gee.HashMap<string, Gee.ArrayList<string>>();

        // Create marriage connector nodes and edges
        int marriage_idx = 0;
        foreach (var marriage in diagram.marriages) {
            string m_id = "m_%d".printf(marriage_idx);

            // Marriage diamond — carries the year as its label when known.
            // group="m_N" binds the diamond to its bus-bar tap in the same
            // vertical column, eliminating Z-shaped ortho-routing kinks.
            bool has_year = marriage.year != null && marriage.year.length > 0;
            sb.append_printf("    %s [\n", m_id);
            sb.append("        shape=diamond\n");
            sb.append("        style=filled\n");
            sb.append_printf("        fillcolor=\"%s\"\n", palette.accent_secondary);
            sb.append_printf("        group=\"%s\"\n", m_id);
            if (has_year) {
                sb.append_printf("        label=\"%s\"\n",
                    RenderUtils.escape_label(marriage.year));
                sb.append("        fontsize=9\n");
                sb.append_printf("        fontcolor=\"%s\"\n",
                    RenderUtils.contrast_text(palette.accent_secondary));
                sb.append("        width=0.55\n");
                sb.append("        height=0.35\n");
                sb.append("        fixedsize=true\n");
            } else {
                sb.append("        width=0.15\n");
                sb.append("        height=0.15\n");
                sb.append("        label=\"\"\n");
            }
            sb.append("    ]\n\n");

            // Keep spouses on same rank
            sb.append_printf("    {rank=same; %s; %s; %s}\n", marriage.person1_id, m_id, marriage.person2_id);

            // Spouse edges (no arrows)
            sb.append_printf("    %s -> %s [dir=none]\n", marriage.person1_id, m_id);
            sb.append_printf("    %s -> %s [dir=none]\n", m_id, marriage.person2_id);
            sb.append("\n");

            // Track this marriage for child edges
            string marriage_key = marriage.person1_id + "+" + marriage.person2_id;
            marriage_children[marriage_key] = new Gee.ArrayList<string>();

            marriage_idx++;
        }

        // Group child links by unique child to find which marriage they belong to
        // For each child, collect the set of parents
        var child_parents = new Gee.HashMap<string, Gee.ArrayList<string>>();
        foreach (var link in diagram.children) {
            if (!child_parents.has_key(link.child_id)) {
                child_parents[link.child_id] = new Gee.ArrayList<string>();
            }
            if (!child_parents[link.child_id].contains(link.parent_id)) {
                child_parents[link.child_id].add(link.parent_id);
            }
        }

        // Group children by their marriage (both parents known).
        // marriage_idx -> ordered list of child IDs
        var marriage_to_children = new Gee.HashMap<int, Gee.ArrayList<string>>();
        // Children with a single known parent go into a separate bucket
        var orphan_child_edges = new Gee.ArrayList<string>();  // "parent_id->child_id"

        foreach (var child_id in child_parents.keys) {
            var parents = child_parents[child_id];
            int matched_marriage = -1;

            if (parents.size >= 2) {
                for (int i = 0; i < parents.size && matched_marriage < 0; i++) {
                    for (int j = i + 1; j < parents.size && matched_marriage < 0; j++) {
                        int m_idx = find_marriage_index(diagram, parents[i], parents[j]);
                        if (m_idx >= 0) matched_marriage = m_idx;
                    }
                }
            }

            if (matched_marriage >= 0) {
                if (!marriage_to_children.has_key(matched_marriage)) {
                    marriage_to_children[matched_marriage] = new Gee.ArrayList<string>();
                }
                marriage_to_children[matched_marriage].add(child_id);
            } else {
                foreach (var parent_id in parents) {
                    orphan_child_edges.add("%s->%s".printf(parent_id, child_id));
                }
            }
        }

        // Emit a bus-bar topology for each marriage's children.
        // For a couple with N children:
        //   - N invisible point nodes on one rank (the "bus")
        //   - Invisible edges chain them left-to-right
        //   - A "tap" point in the middle receives the drop from the marriage junction
        //   - Each bus point drops straight down to its child
        // This prevents ortho splines from detouring around the marriage
        // junction when a child column is far from the couple's X center.
        foreach (var m_idx in marriage_to_children.keys) {
            var kids = marriage_to_children[m_idx];
            int n = kids.size;

            if (n == 1) {
                // Single child — direct edge with no detour to worry about
                sb.append_printf("    m_%d -> %s\n", m_idx, kids[0]);
                continue;
            }

            // Single-tap topology: one invisible point below the marriage
            // junction. All children connect to this tap. splines=ortho
            // creates a natural horizontal bus from the tap's rank, with
            // vertical drops to each child. No dangling stubs.
            sb.append_printf("    // Tap for marriage m_%d\n", m_idx);
            sb.append_printf("    b_%d_tap [shape=point, width=0.001, style=invis, group=\"m_%d\"]\n",
                m_idx, m_idx);

            // Force the tap on its own rank by connecting all children
            // to it. Graphviz will place the tap above the children rank.
            sb.append_printf("    m_%d -> b_%d_tap [weight=100]\n", m_idx, m_idx);
            for (int k = 0; k < n; k++) {
                sb.append_printf("    b_%d_tap -> %s\n", m_idx, kids[k]);
            }
            sb.append("\n");
        }

        // Draw orphan child edges (single known parent)
        foreach (var edge in orphan_child_edges) {
            string[] parts = edge.split("->");
            if (parts.length == 2) {
                sb.append_printf("    %s -> %s\n", parts[0], parts[1]);
            }
        }

        sb.append("}\n");
        return sb.str;
    }

    private int find_marriage_index(AncestryDiagram diagram, string p1, string p2) {
        for (int i = 0; i < diagram.marriages.size; i++) {
            var m = diagram.marriages[i];
            if ((m.person1_id == p1 && m.person2_id == p2) ||
                (m.person1_id == p2 && m.person2_id == p1)) {
                return i;
            }
        }
        return -1;
    }

    private string get_person_fill(AncestryPerson person, Palette palette) {
        bool deceased = person.is_deceased();
        switch (person.gender) {
            case AncestryGender.MALE:
                return deceased ? MALE_FILL_DECEASED : MALE_FILL;
            case AncestryGender.FEMALE:
                return deceased ? FEMALE_FILL_DECEASED : FEMALE_FILL;
            default:
                return palette.node_fill;
        }
    }

    public uint8[]? render_to_svg(AncestryDiagram diagram) {
        string dot = generate_dot(diagram);
        return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "ancestry");
    }

    public Cairo.ImageSurface? render_to_surface(AncestryDiagram diagram) {
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

            // Build element lines map for click-to-source
            var element_lines = new Gee.HashMap<string, int>();
            foreach (var person in diagram.persons) {
                if (person.source_line > 0) {
                    element_lines.set(person.id, person.source_line);
                }
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, (int)width, (int)height);

            return surface;
        } catch (Error e) {
            warning("Failed to create surface from SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(AncestryDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(AncestryDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(AncestryDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
