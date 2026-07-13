/* MermaidArchitectureRenderer.vala — Mermaid architecture-beta diagram renderer */
namespace GDiagram {

// One placed service / junction: grid cell (col, row — row grows downwards) and pixels
internal class ArchCell : Object {
    public ArchService svc;
    public int col;
    public int row;
    public double cx;      // centre of the icon tile
    public double cy;
    public double icon_w;
    public double icon_h;
    public double w;       // cell size, label included
    public double h;

    public ArchCell(ArchService svc) {
        this.svc = svc;
    }
}

// A group's grid extent and, once placed, its rectangle
internal class ArchBox : Object {
    public ArchGroup group;
    public int c0 = int.MAX;
    public int c1 = int.MIN;
    public int r0 = int.MAX;
    public int r1 = int.MIN;
    public double x0;
    public double y0;
    public double x1;
    public double y1;
    public double title_w;
    public double title_h;
    public int depth;

    public ArchBox(ArchGroup g) {
        this.group = g;
    }

    public bool empty { get { return c0 > c1; } }

    public void cover(int col, int row) {
        c0 = int.min(c0, col);
        c1 = int.max(c1, col);
        r0 = int.min(r0, row);
        r1 = int.max(r1, row);
    }
}

public class MermaidArchitectureRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    // Mermaid draws every service icon on a square tile of this colour
    public const string ICON_TILE = "#087ebf";
    // Placeholder cell colours, one per icon, swapped for the tile and its glyph
    // in the SVG (draw_icons): Graphviz has no way to draw the icons itself.
    private const string[] ICON_NAMES = { "cloud", "database", "disk", "internet", "server" };

    public MermaidArchitectureRenderer(Gvc.Context ctx,
                                        Gee.ArrayList<ElementRegion> regions,
                                        string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    private string escape_dot(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    // "#0a0b01".."#0a0b05" for the built-in icons, "#0a0b06" for any other name
    public static string icon_sentinel(string icon) {
        int idx = 0;
        foreach (unowned string name in ICON_NAMES) {
            idx++;
            if (name == icon) return "#0a0b%02d".printf(idx);
        }
        return "#0a0b06";
    }

    // ---- layout ------------------------------------------------------------
    //
    // Mermaid places architecture services from the L/R/T/B sides of its edges
    // (architectureDb.getDataStructures: a BFS over the direction pairs builds a
    // spatial map, which cytoscape-fcose then turns into coordinates). Letting
    // Graphviz rank the nodes instead could not honour "below" or "above" across a
    // group boundary, so the same grid is computed here and every node is pinned
    // (layout=nop2); Graphviz only draws.

    private const double ICON = 60.0;        // the blue icon tile
    private const double GROUP_ICON = 18.0;
    private const double FONT = 12.0;
    private const double GAP = 44.0;         // between two neighbouring cells
    private const double GROUP_PAD = 16.0;   // inside a group outline
    private const double MARGIN = 12.0;
    private const double LABEL_GAP = 4.0;

    private Gee.ArrayList<ArchCell> cells;
    private Gee.HashMap<string, ArchCell> cell_by_id;
    private Gee.ArrayList<ArchBox> boxes;
    private Gee.HashMap<string, ArchBox> box_by_id;
    private double total_w;
    private double total_h;

    private static bool is_x(char c) { return c == 'L' || c == 'R'; }

    // Mermaid's shiftPositionByArchitectureDirectionPair, y still growing upwards
    private static void shift_by(string pair, ref int x, ref int y) {
        if (pair.length < 2) return;
        char lhs = pair[0];
        char rhs = pair[1];
        if (is_x(lhs)) {
            x += lhs == 'L' ? -1 : 1;
            if (!is_x(rhs)) y += rhs == 'T' ? 1 : -1;
        } else {
            y += lhs == 'T' ? 1 : -1;
            if (is_x(rhs)) x += rhs == 'L' ? 1 : -1;
        }
    }

    private static string? dir_pair(string a, string b) {
        string sa = a.length > 0 ? a : "R";
        string sb = b.length > 0 ? b : "L";
        if (sa == sb) return null;   // LL / RR / TT / BB is not a placement
        return sa + sb;
    }

    private static string cell_key(int col, int row) {
        return "%d;%d".printf(col, row);
    }

    private double label_width(string text) {
        double w = 0;
        foreach (string line in text.split("\n")) {
            w = double.max(w, GanttText.width(line, FONT, false, "Sans"));
        }
        return w;
    }

    private static int line_count(string text) {
        return int.max(1, text.split("\n").length);
    }

    /*
     * Builds the grid: a BFS per connected component over the direction pairs, a
     * free neighbouring cell when two edges want the same one (Mermaid leaves that
     * to fcose's repulsion), and the components side by side.
     */
    private void build_grid(MermaidArchitecture diagram) {
        cells = new Gee.ArrayList<ArchCell>();
        cell_by_id = new Gee.HashMap<string, ArchCell>();
        foreach (var svc in diagram.services) {
            if (cell_by_id.has_key(svc.id)) continue;
            var c = new ArchCell(svc);
            cells.add(c);
            cell_by_id.set(svc.id, c);
        }

        // adjacency: every edge seen from both of its ends
        var adj = new Gee.HashMap<string, Gee.ArrayList<string>>();
        foreach (var c in cells) adj.set(c.svc.id, new Gee.ArrayList<string>());
        foreach (var edge in diagram.edges) {
            if (!cell_by_id.has_key(edge.from_id) || !cell_by_id.has_key(edge.to_id)) continue;
            if (edge.from_id == edge.to_id) continue;
            string? fwd = dir_pair(edge.from_side, edge.to_side);
            string? back = dir_pair(edge.to_side, edge.from_side);
            if (fwd != null) adj.get(edge.from_id).add(fwd + "\t" + edge.to_id);
            if (back != null) adj.get(edge.to_id).add(back + "\t" + edge.from_id);
        }

        var taken = new Gee.HashSet<string>();
        var placed = new Gee.HashSet<string>();
        int next_col = 0;
        for (int start = 0; start < cells.size; start++) {
            if (placed.contains(cells[start].svc.id)) continue;
            var comp = new Gee.ArrayList<ArchCell>();
            var queue = new Gee.ArrayList<ArchCell>();
            var local = new Gee.HashSet<string>();
            var first = cells[start];
            first.col = 0;
            first.row = 0;
            local.add(cell_key(0, 0));
            placed.add(first.svc.id);
            queue.add(first);
            comp.add(first);
            for (int qi = 0; qi < queue.size; qi++) {
                var cur = queue[qi];
                foreach (string entry in adj.get(cur.svc.id)) {
                    string[] parts = entry.split("\t");
                    if (parts.length != 2) continue;
                    var other = cell_by_id.get(parts[1]);
                    if (other == null || placed.contains(other.svc.id)) continue;
                    int gx = cur.col;
                    int gy = -cur.row;
                    shift_by(parts[0], ref gx, ref gy);
                    int col = gx;
                    int row = -gy;
                    // occupied: step aside along the axis the edge does not fix
                    bool vertical_free = is_x(parts[0][0]);
                    for (int step = 1; local.contains(cell_key(col, row)) && step < 64; step++) {
                        int d = (step % 2 == 1) ? (step + 1) / 2 : -(step / 2);
                        if (vertical_free) {
                            row = -gy + d;
                        } else {
                            col = gx + d;
                        }
                    }
                    other.col = col;
                    other.row = row;
                    local.add(cell_key(col, row));
                    placed.add(other.svc.id);
                    queue.add(other);
                    comp.add(other);
                }
            }
            int min_col = int.MAX;
            int min_row = int.MAX;
            foreach (var c in comp) {
                min_col = int.min(min_col, c.col);
                min_row = int.min(min_row, c.row);
            }
            foreach (var c in comp) {
                c.col += next_col - min_col;
                c.row -= min_row;
                taken.add(cell_key(c.col, c.row));
            }
            foreach (var c in comp) next_col = int.max(next_col, c.col + 2);
        }
    }

    // Grid extent of every group, its own members and its nested groups
    private void build_boxes(MermaidArchitecture diagram) {
        boxes = new Gee.ArrayList<ArchBox>();
        box_by_id = new Gee.HashMap<string, ArchBox>();
        foreach (var g in diagram.groups) {
            if (box_by_id.has_key(g.id)) continue;
            var b = new ArchBox(g);
            b.title_w = GROUP_ICON + 4 + label_width(g.label);
            b.title_h = double.max(GROUP_ICON, FONT * 1.35);
            boxes.add(b);
            box_by_id.set(g.id, b);
        }
        foreach (var b in boxes) {
            int depth = 0;
            var walk = b.group;
            while (walk != null && walk.parent_id != null && box_by_id.has_key(walk.parent_id) && depth < 32) {
                depth++;
                walk = box_by_id.get(walk.parent_id).group;
            }
            b.depth = depth;
        }
        foreach (var c in cells) {
            string? gid = c.svc.group_id;
            int guard = 0;
            while (gid != null && box_by_id.has_key(gid) && guard++ < 32) {
                var b = box_by_id.get(gid);
                b.cover(c.col, c.row);
                gid = b.group.parent_id;
            }
        }
    }

    // Cell sizes, column / row extents, then the pixel position of everything
    private void place(MermaidArchitecture diagram) {
        int max_col = 0;
        int max_row = 0;
        foreach (var c in cells) {
            c.icon_w = c.svc.is_junction ? 0 : ICON;
            c.icon_h = c.svc.is_junction ? 0 : ICON;
            double lw = c.svc.is_junction ? 0 : label_width(c.svc.label);
            double lh = c.svc.is_junction || c.svc.label.length == 0
                ? 0 : line_count(c.svc.label) * FONT * 1.35 + LABEL_GAP;
            // a junction is invisible but keeps a tile's worth of room, so every
            // icon in a row lines up with it
            c.w = double.max(c.icon_w, lw);
            c.h = ICON + lh;
            max_col = int.max(max_col, c.col);
            max_row = int.max(max_row, c.row);
        }

        var col_w = new double[max_col + 1];
        var row_h = new double[max_row + 1];
        foreach (var c in cells) {
            col_w[c.col] = double.max(col_w[c.col], c.w);
            row_h[c.row] = double.max(row_h[c.row], c.h);
        }

        // gaps: the plain cell distance plus the outline of every group that starts
        // or ends there (its title needs room above its first row)
        var gap_x = new double[int.max(max_col, 1)];
        var gap_y = new double[int.max(max_row, 1)];
        for (int i = 0; i < max_col; i++) gap_x[i] = GAP;
        for (int i = 0; i < max_row; i++) gap_y[i] = GAP;
        double pad_left = MARGIN;
        double pad_right = MARGIN;
        double pad_top = MARGIN;
        double pad_bottom = MARGIN;
        foreach (var b in boxes) {
            if (b.empty) continue;
            if (b.c0 == 0) pad_left += GROUP_PAD;
            else gap_x[b.c0 - 1] += GROUP_PAD;
            if (b.c1 == max_col) pad_right += GROUP_PAD;
            else gap_x[b.c1] += GROUP_PAD;
            if (b.r0 == 0) pad_top += GROUP_PAD + b.title_h;
            else gap_y[b.r0 - 1] += GROUP_PAD + b.title_h;
            if (b.r1 == max_row) pad_bottom += GROUP_PAD;
            else gap_y[b.r1] += GROUP_PAD;
        }

        var col_x = new double[max_col + 1];
        var row_y = new double[max_row + 1];
        double run = pad_left;
        for (int i = 0; i <= max_col; i++) {
            col_x[i] = run;
            run += col_w[i] + (i < max_col ? gap_x[i] : 0);
        }
        total_w = run + pad_right;
        run = pad_top;
        for (int i = 0; i <= max_row; i++) {
            row_y[i] = run;
            run += row_h[i] + (i < max_row ? gap_y[i] : 0);
        }
        total_h = run + pad_bottom;

        // every tile sits at the top of its row, so icons across a row line up
        foreach (var c in cells) {
            c.cx = col_x[c.col] + col_w[c.col] / 2;
            c.cy = row_y[c.row] + ICON / 2;
        }

        // group rectangles, innermost first, around their members and child groups
        boxes.sort((a, b) => b.depth - a.depth);
        foreach (var b in boxes) {
            double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
            foreach (var c in cells) {
                if (c.svc.group_id != b.group.id) continue;
                x0 = double.min(x0, c.cx - c.w / 2);
                x1 = double.max(x1, c.cx + c.w / 2);
                y0 = double.min(y0, c.cy - ICON / 2);
                y1 = double.max(y1, c.cy - ICON / 2 + c.h);
            }
            foreach (var child in boxes) {
                if (child.group.parent_id != b.group.id || child.empty) continue;
                x0 = double.min(x0, child.x0);
                x1 = double.max(x1, child.x1);
                y0 = double.min(y0, child.y0);
                y1 = double.max(y1, child.y1);
            }
            if (x0 > x1) continue;
            b.x0 = x0 - GROUP_PAD;
            b.x1 = x1 + GROUP_PAD;
            b.y0 = y0 - GROUP_PAD - b.title_h;
            b.y1 = y1 + GROUP_PAD;
            b.x1 = double.max(b.x1, b.x0 + b.title_w + 8);
        }
    }

    // ---- DOT ----------------------------------------------------------------

    private static string num(double v) {
        char[] buf = new char[32];
        return v.format(buf, "%.2f");
    }

    private static string inch(double points) {
        char[] buf = new char[32];
        return (points / 72.0).format(buf, "%.4f");
    }

    // y grows downwards in the layout, upwards in Graphviz
    private string pos(double x, double y) {
        return "pos=\"%s,%s!\"".printf(num(x), num(total_h - y));
    }

    public string generate_dot(MermaidArchitecture diagram) {
        var palette = ThemeManager.get_active_palette();
        build_grid(diagram);
        build_boxes(diagram);
        place(diagram);

        var back = new StringBuilder();    // group outlines
        var mid = new StringBuilder();     // icon tiles, junction points, edge waypoints
        var front = new StringBuilder();   // labels, group titles
        var lines = new StringBuilder();   // edges

        double title_h = 0;
        if (diagram.title != null && diagram.title.length > 0) {
            title_h = FONT * 1.6 + 10;
        }
        double shift = title_h;
        total_h += title_h;

        // corner anchors so the margins stay inside the drawing
        mid.append_printf("    __arch_tl [%s shape=point style=invis width=0 height=0 label=\"\"]\n",
            pos(0, 0));
        mid.append_printf("    __arch_br [%s shape=point style=invis width=0 height=0 label=\"\"]\n",
            pos(total_w, total_h));

        if (title_h > 0) {
            front.append_printf("    __arch_title [shape=plaintext style=solid fontsize=14 fontcolor=\"%s\" margin=0 label=\"%s\" %s]\n",
                palette.node_text, escape_dot(diagram.title), pos(total_w / 2, title_h / 2));
        }

        foreach (var b in boxes) {
            if (b.empty) continue;
            double w = b.x1 - b.x0;
            double h = b.y1 - b.y0;
            back.append_printf("    %s [shape=box style=dashed penwidth=1.5 color=\"%s\" fixedsize=true label=\"\" width=%s height=%s %s]\n",
                quote("_ag_" + b.group.id), palette.container_border, inch(w), inch(h),
                pos(b.x0 + w / 2, b.y0 + h / 2 + shift));
            front.append_printf("    %s [shape=box style=filled fixedsize=true label=\"\" fillcolor=\"%s\" color=\"%s\" width=%s height=%s %s]\n",
                quote("_agi_" + b.group.id), icon_sentinel(b.group.icon), icon_sentinel(b.group.icon),
                inch(GROUP_ICON), inch(GROUP_ICON),
                pos(b.x0 + 2 + GROUP_ICON / 2, b.y0 + 2 + b.title_h / 2 + shift));
            front.append_printf("    %s [shape=plaintext style=solid fontname=\"Sans\" fontsize=%d fontcolor=\"%s\" margin=0 label=\"%s\" %s]\n",
                quote("_agt_" + b.group.id), (int) FONT, palette.node_text, escape_dot(b.group.label),
                pos(b.x0 + 2 + GROUP_ICON + 4 + (b.title_w - GROUP_ICON - 4) / 2,
                    b.y0 + 2 + b.title_h / 2 + shift));
        }

        foreach (var c in cells) {
            if (c.svc.is_junction) {
                // Mermaid draws no junction: it is only a corner for its edges
                mid.append_printf("    %s [shape=point style=invis width=0.01 height=0.01 label=\"\" %s]\n",
                    quote(c.svc.id), pos(c.cx, c.cy + shift));
                continue;
            }
            mid.append_printf("    %s [shape=box style=filled fixedsize=true label=\"\" fillcolor=\"%s\" color=\"%s\" width=%s height=%s %s]\n",
                quote(c.svc.id), icon_sentinel(c.svc.icon), icon_sentinel(c.svc.icon),
                inch(c.icon_w), inch(c.icon_h), pos(c.cx, c.cy + shift));
            if (c.svc.label.length > 0) {
                front.append_printf("    %s [shape=plaintext style=solid fontname=\"Sans\" fontsize=%d fontcolor=\"%s\" margin=0 label=\"%s\" %s]\n",
                    quote("_al_" + c.svc.id), (int) FONT, palette.node_text, escape_dot(c.svc.label),
                    pos(c.cx, c.cy + c.icon_h / 2 + LABEL_GAP + (c.h - c.icon_h - LABEL_GAP) / 2 + shift));
            }
        }

        int seq = 0;
        foreach (var edge in diagram.edges) {
            render_edge(mid, front, lines, diagram, edge, shift, ref seq, palette);
        }

        var sb = new StringBuilder();
        sb.append("digraph {\n");
        sb.append("    // Positions are fixed here (layout=nop2): Graphviz draws, it does not place\n");
        sb.append("    layout=nop2\n");
        sb.append("    splines=line\n");
        sb.append("    outputorder=nodesfirst\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    pad=0.1\n");
        sb.append("    node [fontsize=12 fontname=\"Sans\" fontcolor=\"%s\"]\n".printf(palette.node_text));
        sb.append("    edge [fontsize=10 fontname=\"Sans\" color=\"%s\" fontcolor=\"%s\" penwidth=2 arrowsize=0.8 headclip=false tailclip=false]\n\n".printf(
            palette.edge_color, palette.edge_text));
        sb.append(back.str);
        sb.append(mid.str);
        sb.append(front.str);
        sb.append(lines.str);
        sb.append("}\n");
        return sb.str;
    }

    private static string quote(string id) {
        return "\"" + id.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    private ArchBox? group_of(MermaidArchitecture diagram, string service_id) {
        var c = cell_by_id.get(service_id);
        if (c == null || c.svc.group_id == null) return null;
        return box_by_id.get(c.svc.group_id);
    }

    // The point on `side` of a service tile, or of its group when "a{group}" was used
    private bool endpoint(MermaidArchitecture diagram, string id, string side, bool use_group,
                          out double px, out double py) {
        px = 0;
        py = 0;
        var c = cell_by_id.get(id);
        if (c == null) return false;
        double cx = c.cx;
        double cy = c.cy;
        double hw = c.icon_w / 2;
        double hh = c.icon_h / 2;
        if (use_group) {
            var b = group_of(diagram, id);
            if (b != null && !b.empty) {
                switch (side) {
                    case "L": px = b.x0; py = cy; return true;
                    case "R": px = b.x1; py = cy; return true;
                    case "T": px = cx; py = b.y0; return true;
                    default:  px = cx; py = b.y1; return true;
                }
            }
        }
        switch (side) {
            case "L": px = cx - hw; py = cy; break;
            case "R": px = cx + hw; py = cy; break;
            case "T": px = cx; py = cy - hh; break;
            case "B": px = cx; py = cy + hh; break;
            default:  px = cx; py = cy; break;
        }
        return true;
    }

    /*
     * Sides decide the route, as in Mermaid: two sides on the same axis are a
     * straight line ("straight"), an X side against a Y side an orthogonal corner
     * ("segments"). Both ends and the corner are pinned points.
     */
    private void render_edge(StringBuilder mid, StringBuilder front, StringBuilder lines,
                             MermaidArchitecture diagram, ArchEdge edge, double shift,
                             ref int seq, Palette palette) {
        string from_side = edge.from_side.length > 0 ? edge.from_side : "R";
        string to_side = edge.to_side.length > 0 ? edge.to_side : "L";
        double x1, y1, x2, y2;
        if (!endpoint(diagram, edge.from_id, from_side, edge.from_group, out x1, out y1)) return;
        if (!endpoint(diagram, edge.to_id, to_side, edge.to_group, out x2, out y2)) return;

        bool arrow_from = edge.arrow_from;
        bool arrow_to = edge.arrow_to;
        if (!arrow_from && !arrow_to && edge.directed) arrow_to = true;

        int e = seq++;
        string a = "_ae%da".printf(e);
        string b = "_ae%db".printf(e);
        mid.append_printf("    %s [shape=point style=invis width=0.01 height=0.01 label=\"\" %s]\n", a, pos(x1, y1 + shift));
        mid.append_printf("    %s [shape=point style=invis width=0.01 height=0.01 label=\"\" %s]\n", b, pos(x2, y2 + shift));

        bool bend = is_x(from_side[0]) != is_x(to_side[0]);
        string tail = arrow_from ? "normal" : "none";
        string head = arrow_to ? "normal" : "none";
        if (bend) {
            double kx = is_x(from_side[0]) ? x2 : x1;
            double ky = is_x(from_side[0]) ? y1 : y2;
            string k = "_ae%dk".printf(e);
            mid.append_printf("    %s [shape=point style=invis width=0.01 height=0.01 label=\"\" %s]\n", k, pos(kx, ky + shift));
            lines.append_printf("    %s -> %s [dir=both arrowtail=%s arrowhead=none]\n", a, k, tail);
            lines.append_printf("    %s -> %s [arrowhead=%s]\n", k, b, head);
        } else {
            lines.append_printf("    %s -> %s [dir=both arrowtail=%s arrowhead=%s]\n", a, b, tail, head);
        }

        if (edge.label != null && edge.label.length > 0) {
            front.append_printf("    %s [shape=plaintext style=solid fontname=\"Sans\" fontsize=10 fontcolor=\"%s\" margin=0 label=\"%s\" %s]\n",
                "_ael%d".printf(e), palette.edge_text, escape_dot(edge.label),
                pos((x1 + x2) / 2, (y1 + y2) / 2 - 8 + shift));
        }
    }

    private delegate string UnitFmt(double u);

    private static string n(double v) {
        char[] buf = new char[32];
        return v.format(buf, "%.2f");
    }

    // The white line-art glyph of an icon inside the box (x, y, w, h)
    public static string icon_glyph(string sentinel, double x, double y, double w, double h) {
        double s = double.min(w, h);
        double ox = x + (w - s) / 2;
        double oy = y + (h - s) / 2;
        var d = new StringBuilder();
        // Unit-square helpers
        UnitFmt X = (u) => { return n(ox + u * s); };
        UnitFmt Y = (u) => { return n(oy + u * s); };
        UnitFmt L = (u) => { return n(u * s); };
        string open = "<g class=\"gdarchicon\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"%s\" stroke-linecap=\"round\" stroke-linejoin=\"round\">".printf(n(s * 0.045));
        d.append(open);
        switch (sentinel) {
            case "#0a0b01": // cloud
                d.append("<path d=\"M%s,%s H%s A%s,%s 0 0 0 %s,%s A%s,%s 0 0 0 %s,%s A%s,%s 0 0 0 %s,%s Z\"/>".printf(
                    X(0.30), Y(0.66), X(0.72),
                    L(0.13), L(0.13), X(0.69), Y(0.41),
                    L(0.19), L(0.19), X(0.34), Y(0.40),
                    L(0.13), L(0.13), X(0.30), Y(0.66)));
                break;
            case "#0a0b02": // database
                d.append("<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\"/>".printf(X(0.5), Y(0.27), L(0.28), L(0.09)));
                d.append("<path d=\"M%s,%s V%s A%s,%s 0 0 0 %s,%s V%s\"/>".printf(
                    X(0.22), Y(0.27), Y(0.73), L(0.28), L(0.09), X(0.78), Y(0.73), Y(0.27)));
                foreach (double yy in new double[] { 0.42, 0.575 }) {
                    d.append("<path d=\"M%s,%s A%s,%s 0 0 0 %s,%s\"/>".printf(
                        X(0.22), Y(yy), L(0.28), L(0.09), X(0.78), Y(yy)));
                }
                break;
            case "#0a0b03": // disk
                d.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\"/>".printf(
                    X(0.22), Y(0.18), L(0.56), L(0.64), L(0.05)));
                d.append("<circle cx=\"%s\" cy=\"%s\" r=\"%s\"/>".printf(X(0.5), Y(0.45), L(0.15)));
                d.append("<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#ffffff\"/>".printf(X(0.5), Y(0.45), L(0.035)));
                d.append("<path d=\"M%s,%s L%s,%s\"/>".printf(X(0.47), Y(0.53), X(0.37), Y(0.71)));
                break;
            case "#0a0b04": // internet
                d.append("<circle cx=\"%s\" cy=\"%s\" r=\"%s\"/>".printf(X(0.5), Y(0.5), L(0.3)));
                d.append("<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\"/>".printf(X(0.5), Y(0.5), L(0.13), L(0.3)));
                d.append("<path d=\"M%s,%s H%s M%s,%s H%s M%s,%s H%s\"/>".printf(
                    X(0.2), Y(0.5), X(0.8), X(0.25), Y(0.36), X(0.75), X(0.25), Y(0.64), X(0.75)));
                break;
            case "#0a0b05": // server
                for (int i = 0; i < 3; i++) {
                    double top = 0.2 + i * 0.21;
                    d.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\"/>".printf(
                        X(0.18), Y(top), L(0.64), L(0.18), L(0.03)));
                    double cy = top + 0.09;
                    d.append("<path d=\"M%s,%s H%s M%s,%s H%s M%s,%s H%s M%s,%s H%s\"/>".printf(
                        X(0.26), Y(cy), X(0.265), X(0.32), Y(cy), X(0.325), X(0.38), Y(cy), X(0.385),
                        X(0.55), Y(cy), X(0.74)));
                }
                break;
            default: // unknown icon name
                return "<text x=\"%s\" y=\"%s\" text-anchor=\"middle\" font-family=\"Sans\" font-weight=\"bold\" font-size=\"%s\" fill=\"#ffffff\">?</text>".printf(
                    X(0.5), Y(0.68), L(0.5));
        }
        d.append("</g>");
        return d.str;
    }

    // Replaces each icon placeholder cell with the tile colour and draws its glyph
    public static uint8[] draw_icons(uint8[] svg_data) {
        var text = new StringBuilder.sized(svg_data.length + 1);
        text.append_len((string) svg_data, svg_data.length);
        string svg = text.str;
        if (!svg.contains("fill=\"#0a0b0")) return svg_data;
        try {
            var re = new Regex("<polygon fill=\"(#0a0b0[1-6])\" stroke=\"[^\"]*\" points=\"([^\"]*)\"/>");
            svg = re.replace_eval(svg, -1, 0, 0, (m, result) => {
                double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
                foreach (string pt in m.fetch(2).strip().split(" ")) {
                    string[] xy = pt.split(",");
                    if (xy.length != 2) continue;
                    double px = double.parse(xy[0]);
                    double py = double.parse(xy[1]);
                    minx = double.min(minx, px); maxx = double.max(maxx, px);
                    miny = double.min(miny, py); maxy = double.max(maxy, py);
                }
                if (minx > maxx) {
                    result.append(m.fetch(0));
                    return false;
                }
                result.append("<polygon fill=\"%s\" stroke=\"none\" points=\"%s\"/>".printf(ICON_TILE, m.fetch(2)));
                result.append(icon_glyph(m.fetch(1), minx, miny, maxx - minx, maxy - miny));
                return false;
            });
        } catch (RegexError e) {
            warning("Failed to draw architecture icons: %s", e.message);
            return svg_data;
        }
        return svg.data;
    }

    public uint8[]? render_to_svg(MermaidArchitecture diagram) {
        string dot = generate_dot(diagram);
        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse architecture DOT graph");
            return null;
        }

        int ret = context.layout(graph, "nop2");
        if (ret != 0) {
            warning("Failed to layout architecture graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render architecture graph");
            return null;
        }

        return draw_icons(svg_data);
    }

    public Cairo.ImageSurface? render_to_surface(MermaidArchitecture diagram) {
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
            foreach (var svc in diagram.services) {
                if (svc.source_line > 0) {
                    element_lines.set(svc.id, svc.source_line);
                    element_lines.set("_al_" + svc.id, svc.source_line);
                }
            }
            foreach (var g in diagram.groups) {
                if (g.source_line > 0) {
                    element_lines.set("_ag_" + g.id, g.source_line);
                    element_lines.set("_agt_" + g.id, g.source_line);
                }
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render architecture SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidArchitecture diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidArchitecture diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidArchitecture diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
