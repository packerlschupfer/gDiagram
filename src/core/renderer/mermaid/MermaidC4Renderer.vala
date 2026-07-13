/* MermaidC4Renderer.vala — Mermaid C4 diagram renderer */
namespace GDiagram {

public class MermaidC4Renderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Person heads: fill/stroke per placeholder index ("#0c4dNN"), see draw_person_heads
    private Gee.ArrayList<string> head_fills = new Gee.ArrayList<string>();
    private Gee.ArrayList<string> head_strokes = new Gee.ArrayList<string>();

    // Which grid row (container + row number) and column a shape landed in, so a
    // relationship inside one row can be drawn straight instead of arching over it
    private Gee.HashMap<string, string> row_key = new Gee.HashMap<string, string>();
    private Gee.HashMap<string, int> row_col = new Gee.HashMap<string, int>();
    // $offsetX / $offsetY per edge id, applied to its label in the SVG
    private Gee.ArrayList<string> rel_offsets = new Gee.ArrayList<string>();
    private int queue_index = 0;

    private MermaidC4 current;

    public MermaidC4Renderer(Gvc.Context ctx,
                              Gee.ArrayList<ElementRegion> regions,
                              string engine) {
        this.ctx = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    /*
     * Layout follows Mermaid's C4 grid: inside every boundary (and the diagram
     * itself) the shapes come first, c4ShapeInRow per row in declaration order,
     * then the nested boundaries below them, c4BoundaryInRow per row. Rows are
     * rank=same groups chained by invisible edges; relationships don't move shapes
     * (constraint=false), as in Mermaid.
     */
    public string generate_dot(MermaidC4 diagram) {
        var palette = ThemeManager.get_active_palette();
        current = diagram;
        head_fills.clear();
        head_strokes.clear();
        row_key.clear();
        row_col.clear();
        rel_offsets.clear();
        queue_index = 0;
        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=TB\n");
        sb.append("    compound=true\n");
        // Mermaid's C4 draws every relationship as a straight line between the two
        // shapes; with splined edges a link inside one row arched over the shapes
        // between its ends instead of running through them
        sb.append("    splines=line\n");
        sb.append("    nodesep=0.6\n    ranksep=0.7\n");
        sb.append("    node [fontsize=11 fontname=\"Sans\" fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    edge [fontsize=10 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\"]\n\n".printf(palette.edge_color, palette.edge_text));

        if (diagram.title != null && diagram.title.length > 0) {
            sb.append_printf("    label=\"%s\"\n", escape_dot(diagram.title));
            sb.append("    labelloc=t\n    fontsize=14\n");
            sb.append("    fontcolor=\"%s\"\n\n".printf(palette.node_text));
        }

        string top, bottom;
        emit_container(sb, null, "    ", out top, out bottom);

        // Render relationships
        int index = 0;
        foreach (var rel in diagram.relationships) {
            index++;
            render_relationship(sb, rel, diagram.c4_type == "Dynamic" ? index : 0);
        }

        sb.append("}\n");
        return sb.str;
    }

    private bool is_boundary_id(string? id) {
        if (id == null) return false;
        foreach (var b in current.boundaries) {
            if (b.id == id) return true;
        }
        return false;
    }

    // Elements and child boundaries of a container, the grid rows between them;
    // `top`/`bottom` are nodes of its first and last row for the parent's chain.
    private void emit_container(StringBuilder sb, string? parent_id, string indent, out string top, out string bottom) {
        var shapes = new Gee.ArrayList<C4Element>();
        foreach (var el in current.elements) {
            bool here = parent_id == null
                ? (el.parent_boundary == null || !is_boundary_id(el.parent_boundary))
                : el.parent_boundary == parent_id;
            if (here) shapes.add(el);
        }
        var children = new Gee.ArrayList<C4Boundary>();
        foreach (var b in current.boundaries) {
            bool here = parent_id == null
                ? (b.parent_boundary == null || !is_boundary_id(b.parent_boundary))
                : b.parent_boundary == parent_id;
            if (here && b.id != parent_id) children.add(b);
        }

        foreach (var el in shapes) {
            render_element(sb, el, indent);
        }

        top = "";
        bottom = "";
        int per_row = int.max(1, current.shape_in_row);
        string[]? prev_row = null;
        for (int start = 0; start < shapes.size; start += per_row) {
            int end = int.min(start + per_row, shapes.size);
            string[] row = new string[end - start];
            for (int k = start; k < end; k++) {
                row[k - start] = quote(shapes.get(k).id);
                row_key.set(shapes.get(k).id, "%s#%d".printf(parent_id ?? "", start));
                row_col.set(shapes.get(k).id, k - start);
            }
            if (row.length > 1) {
                sb.append_printf("%s{ rank=same; %s }\n", indent, string.joinv("; ", row));
                sb.append_printf("%s%s [style=invis]\n", indent, string.joinv(" -> ", row));
            }
            if (prev_row != null) {
                for (int j = 0; j < row.length && j < prev_row.length; j++) {
                    sb.append_printf("%s%s -> %s [style=invis]\n", indent, prev_row[j], row[j]);
                }
            } else {
                top = row[0];
            }
            bottom = row[0];
            prev_row = row;
        }

        var palette = ThemeManager.get_active_palette();
        int per_brow = int.max(1, current.boundary_in_row);
        var prev_bottoms = new Gee.ArrayList<string>();
        if (bottom.length > 0) prev_bottoms.add(bottom);
        for (int start = 0; start < children.size; start += per_brow) {
            int end = int.min(start + per_brow, children.size);
            var bottoms = new Gee.ArrayList<string>();
            for (int k = start; k < end; k++) {
                var b = children.get(k);
                string ctop, cbottom;
                sb.append_printf("%ssubgraph cluster_%s {\n", indent, sanitize_id(b.id));
                string inner = indent + "    ";
                var label = new StringBuilder("<B>%s</B>".printf(Markup.escape_text(b.label)));
                if (b.boundary_type != null && b.boundary_type.length > 0) {
                    label.append("<BR/><FONT POINT-SIZE=\"10\">[%s]</FONT>".printf(Markup.escape_text(b.boundary_type)));
                }
                if (b.description != null && b.description.length > 0) {
                    label.append("<BR/><FONT POINT-SIZE=\"10\">%s</FONT>".printf(wrap_html(b.description)));
                }
                sb.append_printf("%slabel=<%s>\n", inner, label.str);
                string stroke = b.border_color != null ? RenderUtils.sanitize_color(b.border_color) : palette.boundary_stroke;
                if (b.bg_color != null) {
                    sb.append_printf("%sstyle=\"%s,filled\"\n", inner, b.is_deployment_node ? "solid" : "dashed");
                    sb.append_printf("%sfillcolor=\"%s\"\n", inner, RenderUtils.sanitize_color(b.bg_color));
                } else {
                    sb.append_printf("%sstyle=%s\n", inner, b.is_deployment_node ? "solid" : "dashed");
                }
                sb.append_printf("%scolor=\"%s\"\n", inner, stroke);
                sb.append_printf("%sfontcolor=\"%s\"\n", inner,
                    b.font_color != null ? RenderUtils.sanitize_color(b.font_color) : palette.node_text);
                sb.append_printf("%smargin=16\n", inner);
                emit_container(sb, b.id, inner, out ctop, out cbottom);
                if (ctop.length == 0) {
                    // Graphviz drops an empty cluster: keep it with an invisible point
                    ctop = quote("__empty_" + b.id);
                    cbottom = ctop;
                    sb.append_printf("%s%s [shape=point style=invis width=0.8 height=0.5 label=\"\"]\n", inner, ctop);
                }
                sb.append_printf("%s}\n", indent);
                foreach (string pb in prev_bottoms) {
                    sb.append_printf("%s%s -> %s [style=invis]\n", indent, pb, ctop);
                }
                if (top.length == 0) top = ctop;
                bottoms.add(cbottom);
            }
            prev_bottoms = bottoms;
            bottom = bottoms.get(0);
        }
    }

    private static string quote(string id) {
        return "\"" + id.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    // "[Software System]", "[Container: React]"
    public static string stereotype_text(C4Element el) {
        string t = el.c4_shape_type;
        if (t.length == 0) {
            switch (el.element_type) {
                case C4ElementType.PERSON:    t = "person"; break;
                case C4ElementType.CONTAINER: t = "container"; break;
                case C4ElementType.COMPONENT: t = "component"; break;
                default:                      t = "system"; break;
            }
        }
        if (t.has_prefix("external_")) t = t.substring(9);
        if (t.has_suffix("_db")) t = t.substring(0, t.length - 3);
        else if (t.has_suffix("_queue")) t = t.substring(0, t.length - 6);
        string name;
        switch (t) {
            case "person":    name = "Person"; break;
            case "system":    name = "Software System"; break;
            case "container": name = "Container"; break;
            case "component": name = "Component"; break;
            default:          name = t.replace("_", " "); break;
        }
        if (el.technology != null && el.technology.length > 0) {
            return "[%s: %s]".printf(name, el.technology);
        }
        return "[%s]".printf(name);
    }

    // Escaped text broken into lines of about 32 characters at spaces
    private static string wrap_html(string text) {
        var out_sb = new StringBuilder();
        int line_len = 0;
        foreach (string word in text.split(" ")) {
            if (word.length == 0) continue;
            if (line_len > 0 && line_len + 1 + word.char_count() > 32) {
                out_sb.append("<BR/>");
                line_len = 0;
            } else if (line_len > 0) {
                out_sb.append(" ");
                line_len++;
            }
            out_sb.append(Markup.escape_text(word));
            line_len += word.char_count();
        }
        return out_sb.str;
    }

    private void render_element(StringBuilder sb, C4Element el, string indent) {
        var palette = ThemeManager.get_active_palette();
        string fill_color;
        string border;

        switch (el.element_type) {
            case C4ElementType.PERSON:
                fill_color = el.is_external ? palette.external_fill : palette.person_fill;
                border = el.is_external ? palette.external_border : palette.person_border;
                break;
            case C4ElementType.CONTAINER:
                fill_color = el.is_external ? palette.external_fill : palette.container_fill;
                border = el.is_external ? palette.external_border : palette.container_border;
                break;
            case C4ElementType.COMPONENT:
                fill_color = el.is_external ? palette.external_fill : palette.component_fill;
                border = el.is_external ? palette.external_border : palette.component_border;
                break;
            case C4ElementType.DEPLOYMENT_NODE:
                fill_color = palette.node_fill;
                border = palette.node_border;
                break;
            default: // SYSTEM
                fill_color = el.is_external ? palette.external_fill : palette.system_fill;
                border = el.is_external ? palette.external_border : palette.system_border;
                break;
        }
        if (el.bg_color != null) fill_color = RenderUtils.sanitize_color(el.bg_color);
        if (el.border_color != null) border = RenderUtils.sanitize_color(el.border_color);
        string font_color = el.font_color != null
            ? RenderUtils.sanitize_color(el.font_color)
            : RenderUtils.contrast_text(fill_color);

        // Name, "[type: technology]", description
        var text = new StringBuilder("<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">");
        text.append("<TR><TD><FONT POINT-SIZE=\"12\"><B>%s</B></FONT></TD></TR>".printf(Markup.escape_text(el.label)));
        text.append("<TR><TD><FONT POINT-SIZE=\"9\">%s</FONT></TD></TR>".printf(Markup.escape_text(stereotype_text(el))));
        if (el.description != null && el.description.length > 0) {
            text.append("<TR><TD><FONT POINT-SIZE=\"10\">%s</FONT></TD></TR>".printf(wrap_html(el.description)));
        }
        text.append("</TABLE>");

        if (el.element_type == C4ElementType.PERSON) {
            // Mermaid's person: a round head over a rounded body. The head cell is a
            // placeholder that draw_person_heads turns into a circle.
            if (head_fills.size < 250) {
                head_fills.add(fill_color);
                head_strokes.add(border);
                string sentinel = "#0c4d%02x".printf(head_fills.size);
                sb.append_printf("%s%s [shape=plain label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">" +
                    "<TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"52\" HEIGHT=\"44\" BGCOLOR=\"%s\"></TD></TR>" +
                    "<TR><TD><TABLE STYLE=\"rounded\" BORDER=\"1\" CELLBORDER=\"0\" CELLPADDING=\"10\" BGCOLOR=\"%s\" COLOR=\"%s\">" +
                    "<TR><TD><FONT COLOR=\"%s\">%s</FONT></TD></TR></TABLE></TD></TR></TABLE>>]\n",
                    indent, quote(el.id), sentinel, fill_color, border, font_color, text.str);
                return;
            }
        }

        if (el.is_queue) {
            // Mermaid's queue is the "h-cyl" shape: a cylinder lying on its side.
            // Graphviz has no such shape, so a plain box carries an id that
            // draw_queues turns into the cylinder outline.
            sb.append_printf("%s%s [label=<%s> shape=box style=filled id=\"gdc4q_%d\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" margin=\"0.32,0.12\"]\n",
                indent, quote(el.id), text.str, queue_index++, fill_color, border, font_color);
            return;
        }
        string shape = el.is_db ? "cylinder" : "box";
        string style = el.is_db ? "filled" : "rounded,filled";
        sb.append_printf("%s%s [label=<%s> shape=%s style=\"%s\" fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" margin=\"0.2,0.12\"]\n",
            indent, quote(el.id), text.str, shape, style, fill_color, border, font_color);
    }

    private void render_relationship(StringBuilder sb, C4Relationship rel, int index) {
        string label = index > 0 ? "%d: %s".printf(index, rel.label) : rel.label;
        var html = new StringBuilder(wrap_html(label));
        if (rel.technology != null && rel.technology.length > 0) {
            html.append("<BR/><I><FONT POINT-SIZE=\"9\">[%s]</FONT></I>".printf(Markup.escape_text(rel.technology)));
        }
        string edge_label = html.str;
        if (rel.text_color != null) {
            edge_label = "<FONT COLOR=\"%s\">%s</FONT>".printf(RenderUtils.sanitize_color(rel.text_color), edge_label);
        }

        string dir = rel.is_bidirectional ? "both" : "forward";
        if (rel.direction == "BACK") dir = "back";
        string color = rel.line_color != null
            ? " color=\"%s\"".printf(RenderUtils.sanitize_color(rel.line_color)) : "";

        // A normal label between two shapes of one row is placed above them and drags
        // the line up with it — the arch this used to draw. A tail label is placed
        // along the line instead, in the gap next to the shape it starts from.
        bool same_row = row_key.has_key(rel.from_id) && row_key.has_key(rel.to_id)
            && row_key.get(rel.from_id) == row_key.get(rel.to_id);
        bool adjacent = same_row
            && (row_col.get(rel.from_id) - row_col.get(rel.to_id)).abs() == 1;
        string label_attr = "label";
        string label_place = "";
        if (same_row && !adjacent) {
            label_attr = "taillabel";
            label_place = " labeldistance=3.0 labelangle=-22";
        }

        string id_attr = "";
        if (rel.offset_x != 0 || rel.offset_y != 0) {
            id_attr = " id=\"gdc4rel_%d\"".printf(rel_offsets.size);
            rel_offsets.add("%s;%s".printf(n(rel.offset_x), n(rel.offset_y)));
        }

        sb.append_printf("    %s -> %s [%s=<%s>%s dir=%s constraint=false%s%s]\n",
            quote(rel.from_id), quote(rel.to_id), label_attr, edge_label, label_place,
            dir, color, id_attr);
    }

    // Escape a string for use in a DOT quoted label
    private string escape_dot(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    // Sanitize an id for use as a DOT cluster identifier
    private string sanitize_id(string s) {
        var result = new StringBuilder();
        foreach (char c in s.to_utf8()) {
            if (c.isalnum() || c == '_') {
                result.append_c(c);
            } else {
                result.append_c('_');
            }
        }
        return result.str;
    }

    private static string n(double v) {
        char[] buf = new char[32];
        return v.format(buf, "%.2f");
    }

    // The person head placeholders become circles overlapping the body's top
    private uint8[] draw_person_heads(uint8[] svg_data) {
        var text = new StringBuilder.sized(svg_data.length + 1);
        text.append_len((string) svg_data, svg_data.length);
        string svg = text.str;
        if (!svg.contains("fill=\"#0c4d")) return svg_data;
        try {
            var re = new Regex("<polygon fill=\"#0c4d([0-9a-f]{2})\" stroke=\"[^\"]*\" points=\"([^\"]*)\"/>");
            svg = re.replace_eval(svg, -1, 0, 0, (m, result) => {
                string hex = m.fetch(1);
                int idx = hex[0].xdigit_value() * 16 + hex[1].xdigit_value() - 1;
                double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
                foreach (string pt in m.fetch(2).strip().split(" ")) {
                    string[] xy = pt.split(",");
                    if (xy.length != 2) continue;
                    double px = double.parse(xy[0]);
                    double py = double.parse(xy[1]);
                    minx = double.min(minx, px); maxx = double.max(maxx, px);
                    miny = double.min(miny, py); maxy = double.max(maxy, py);
                }
                if (minx > maxx || idx < 0 || idx >= head_fills.size) return false;
                // The cell spans the body's width: the head is sized by its height and
                // sinks a little into the body, which is drawn after it
                double r = double.min(maxx - minx, maxy - miny) / 2 + 2;
                double cx = (minx + maxx) / 2;
                double cy = maxy - r + 8;
                string fill = head_fills.get(idx);
                string stroke = head_strokes.get(idx);
                result.append("<circle class=\"gdc4head\" cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" stroke=\"%s\"/>".printf(
                    n(cx), n(cy), n(r), fill, stroke));
                return false;
            });
        } catch (RegexError e) {
            warning("Failed to draw C4 person heads: %s", e.message);
            return svg_data;
        }
        return svg.data;
    }

    /*
     * Mermaid's queue shapes (SystemQueue / ContainerQueue / ComponentQueue) are
     * drawn with the "h-cyl" shape: a cylinder on its side, an elliptical cap at
     * each end and the seam of the near cap inside the right one. The placeholder
     * box Graphviz drew is replaced by that outline here.
     */
    private uint8[] draw_queues(uint8[] svg_data) {
        var text = new StringBuilder.sized(svg_data.length + 1);
        text.append_len((string) svg_data, svg_data.length);
        string svg = text.str;
        if (!svg.contains("id=\"gdc4q_")) return svg_data;
        try {
            var re = new Regex(
                "(<g id=\"gdc4q_\\d+\" class=\"node\">\\s*<title>[^<]*</title>\\s*)<polygon fill=\"([^\"]*)\" stroke=\"([^\"]*)\" points=\"([^\"]*)\"/>",
                RegexCompileFlags.DOTALL);
            svg = re.replace_eval(svg, -1, 0, 0, (m, result) => {
                string fill = m.fetch(2);
                string stroke = m.fetch(3);
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
                    result.append("<polygon fill=\"%s\" stroke=\"%s\" points=\"%s\"/>".printf(fill, stroke, m.fetch(4)));
                    return false;
                }
                double h = maxy - miny;
                double ry = h / 2;
                double rx = ry / (2.5 + h / 50);   // Mermaid's tiltedCylinder ratio
                double lx = minx + rx;
                double rxx = double.max(lx + 1, maxx - rx);
                result.append("<path fill=\"%s\" stroke=\"%s\" d=\"M%s,%s A%s,%s 0 0 1 %s,%s L%s,%s A%s,%s 0 0 1 %s,%s Z\"/>".printf(
                    fill, stroke, n(lx), n(maxy), n(rx), n(ry), n(lx), n(miny),
                    n(rxx), n(miny), n(rx), n(ry), n(rxx), n(maxy)));
                result.append("<path fill=\"none\" stroke=\"%s\" d=\"M%s,%s A%s,%s 0 0 0 %s,%s\"/>".printf(
                    stroke, n(rxx), n(miny), n(rx), n(ry), n(rxx), n(maxy)));
                return false;
            });
        } catch (RegexError e) {
            warning("Failed to draw C4 queue shapes: %s", e.message);
            return svg_data;
        }
        return svg.data;
    }

    // UpdateRelStyle's $offsetX / $offsetY move a relationship's label
    private uint8[] apply_rel_offsets(uint8[] svg_data) {
        if (rel_offsets.size == 0) return svg_data;
        var text = new StringBuilder.sized(svg_data.length + 1);
        text.append_len((string) svg_data, svg_data.length);
        string svg = text.str;
        if (!svg.contains("id=\"gdc4rel_")) return svg_data;
        try {
            var re = new Regex("<g id=\"gdc4rel_(\\d+)\" class=\"edge\">(.*?)</g>", RegexCompileFlags.DOTALL);
            var shift = new Regex("<text ([^>]*?)x=\"([-0-9.]+)\" y=\"([-0-9.]+)\"");
            svg = re.replace_eval(svg, -1, 0, 0, (m, result) => {
                int idx = int.parse(m.fetch(1));
                if (idx < 0 || idx >= rel_offsets.size) {
                    result.append(m.fetch(0));
                    return false;
                }
                string[] off = rel_offsets[idx].split(";");
                double dx = double.parse(off[0]);
                double dy = off.length > 1 ? double.parse(off[1]) : 0;
                string body = m.fetch(2);
                try {
                    body = shift.replace_eval(body, -1, 0, 0, (t, res) => {
                        res.append("<text %sx=\"%s\" y=\"%s\"".printf(
                            t.fetch(1), n(double.parse(t.fetch(2)) + dx), n(double.parse(t.fetch(3)) + dy)));
                        return false;
                    });
                } catch (RegexError e) {
                    // keep the label where Graphviz put it
                }
                result.append("<g id=\"gdc4rel_%d\" class=\"edge\">%s</g>".printf(idx, body));
                return false;
            });
        } catch (RegexError e) {
            warning("Failed to apply C4 relationship offsets: %s", e.message);
            return svg_data;
        }
        return svg.data;
    }

    public uint8[]? render_to_svg(MermaidC4 diagram) {
        string dot_source = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot_source);
        if (graph == null) {
            warning("Failed to parse C4 DOT graph");
            return null;
        }

        int ret = ctx.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout C4 graph");
            ctx.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(ctx, graph, "svg", out svg_data);
        ctx.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render C4 graph");
            return null;
        }

        return apply_rel_offsets(draw_queues(draw_person_heads(svg_data)));
    }

    public Cairo.ImageSurface? render_to_surface(MermaidC4 diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

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

            var element_lines = new Gee.HashMap<string, int>();
            foreach (var el in diagram.elements) {
                if (el.source_line > 0)
                    element_lines.set(el.id, el.source_line);
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render C4 SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidC4 diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidC4 diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidC4 diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
