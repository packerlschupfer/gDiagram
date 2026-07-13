/* DitaaDiagramRenderer.vala — renders DITAA ASCII art as boxes, lines and text */
namespace GDiagram {

public class DitaaDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public DitaaDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // ==================== ASCII-art recognition ====================
    //
    // The drawing is read the way ditaa reads it. Line characters
    // (- = | : + / \ and the arrowheads > < ^ v) join neighbouring cells when
    // both sides point at each other. Cells that join nothing are text. Areas
    // the joined lines close off become shapes, each drawn with its own
    // outline, fill and drop shadow (and pulled in a little so neighbouring
    // boxes stay apart); the joined lines that bound no area are connectors.
    // `cRED`/`cBLU`/... or `cXYZ` colour a shape, `{d}` `{s}` `{io}` `{c}` `{o}`
    // `{mo}` `{tr}` change its kind. Geometry follows PlantUML's ditaa: 10x14px
    // cells, a 20px/28px margin, bold 12px text.

    private const int P_L = 1;
    private const int P_R = 2;
    private const int P_U = 4;
    private const int P_D = 8;

    private int rows;
    private int cols;
    private unichar[,] grid;
    private bool[,] conn_h;     // (r,c) joined to (r,c+1)
    private bool[,] conn_v;     // (r,c) joined to (r+1,c)
    private double k = 1.0;     // scale

    private double CW { get { return 10.0 * k; } }
    private double CH { get { return 14.0 * k; } }
    private double MX { get { return 20.0 * k; } }
    private double MY { get { return 28.0 * k; } }

    private double px(double lattice_x) { return MX + lattice_x * CW + CW / 2; }
    private double py(double lattice_y) { return MY + lattice_y * CH + CH / 2; }

    private static int ports(unichar ch) {
        switch (ch) {
            case '-': case '=': return P_L | P_R;
            case '|': case ':': return P_U | P_D;
            case '+': case '/': case '\\': return P_L | P_R | P_U | P_D;
            case '>': return P_L;
            case '<': return P_R;
            case '^': return P_D;
            case 'v': case 'V': return P_U;
            default: return 0;
        }
    }

    private unichar at(int r, int c) {
        if (r < 0 || c < 0 || r >= rows || c >= cols) return ' ';
        return grid[r, c];
    }

    private bool is_wall(int r, int c) {
        if (r < 0 || c < 0 || r >= rows || c >= cols) return false;
        return (c < cols - 1 && conn_h[r, c]) || (c > 0 && conn_h[r, c - 1]) ||
               (r < rows - 1 && conn_v[r, c]) || (r > 0 && conn_v[r - 1, c]);
    }

    private class Shape {
        public Gee.ArrayList<int> cells = new Gee.ArrayList<int>();   // r * cols + c
        public string? color = null;
        public string? kind = null;
        public int min_x; public int max_x; public int min_y; public int max_y;  // lattice bbox
        public bool rect;
        public bool dashed;
        public bool rounded;
        public bool[,] sub;
    }

    private static string? tag_color(string code) {
        switch (code) {
            case "RED": return "#EE3322";
            case "BLU": return "#5555BB";
            case "GRE": return "#99DD99";
            case "PNK": return "#FFAAAA";
            case "BLK": return "#000000";
            case "YEL": return "#FFFF33";
        }
        bool hex = code.length == 3;
        for (int i = 0; i < code.length && hex; i++) hex = code[i].isxdigit();
        if (!hex) return null;
        return "#%c%c%c%c%c%c".printf(code[0], code[0], code[1], code[1], code[2], code[2]).up();
    }

    public string generate_dot(DitaaDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        k = diagram.scale;

        // ---- grid ----
        string[] lines = diagram.ascii_text.replace("\t", "        ").split("\n");
        rows = lines.length;
        cols = 1;
        foreach (string l in lines) cols = int.max(cols, l.char_count());
        grid = new unichar[rows, cols];
        for (int r = 0; r < rows; r++) {
            int c = 0;
            int idx = 0;
            unichar ch;
            while (lines[r].get_next_char(ref idx, out ch)) {
                grid[r, c++] = ch;
            }
            for (; c < cols; c++) grid[r, c] = ' ';
        }

        // ---- tags: remembered by cell, then blanked ----
        var color_at = new Gee.HashMap<int, string>();
        var kind_at = new Gee.HashMap<int, string>();
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                if (grid[r, c] == '{') {
                    foreach (string kind in new string[] { "d", "s", "io", "c", "o", "mo", "tr" }) {
                        int n = kind.length;
                        if (c + n + 1 < cols && grid[r, c + n + 1] == '}' && cells_equal(r, c + 1, kind)) {
                            kind_at[r * cols + c + 1] = kind;
                            for (int i = 0; i < n + 2; i++) grid[r, c + i] = ' ';
                            break;
                        }
                    }
                } else if (grid[r, c] == 'c' && c + 3 < cols && !at(r, c - 1).isalnum() && !at(r, c + 4).isalnum()) {
                    string code = "%s%s%s".printf(grid[r, c + 1].to_string(), grid[r, c + 2].to_string(),
                        grid[r, c + 3].to_string());
                    string? color = tag_color(code);
                    if (color != null) {
                        color_at[r * cols + c] = color;
                        for (int i = 0; i < 4; i++) grid[r, c + i] = ' ';
                    }
                }
            }
        }

        // ---- joins ----
        conn_h = new bool[rows, cols];
        conn_v = new bool[rows, cols];
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                int p = ports(grid[r, c]);
                if (p == 0) continue;
                if (c + 1 < cols && (p & P_R) != 0 && (ports(grid[r, c + 1]) & P_L) != 0) {
                    conn_h[r, c] = !(is_arrow(grid[r, c]) && is_arrow(grid[r, c + 1]));
                }
                if (r + 1 < rows && (p & P_D) != 0 && (ports(grid[r + 1, c]) & P_U) != 0) {
                    conn_v[r, c] = !(is_arrow(grid[r, c]) && is_arrow(grid[r + 1, c]));
                }
            }
        }

        // ---- enclosed areas ----
        // Flood the outside on a doubled grid where the joins between cells
        // are cells of their own: two line cells side by side only block the
        // flood when they are joined (an arrowhead pointing away from a box
        // leaves a gap). Cells the flood cannot reach, and that are not
        // lines, are inside a shape.
        int fr = 2 * rows + 1, fc = 2 * cols + 1;
        var blocked = new bool[fr, fc];
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                if (is_wall(r, c)) blocked[2 * r + 1, 2 * c + 1] = true;
                if (c + 1 < cols && conn_h[r, c]) blocked[2 * r + 1, 2 * c + 2] = true;
                if (r + 1 < rows && conn_v[r, c]) blocked[2 * r + 2, 2 * c + 1] = true;
            }
        }
        var outside = new bool[fr, fc];
        var queue = new Gee.ArrayQueue<int>();
        int[] dr = { -1, 1, 0, 0 };
        int[] dc = { 0, 0, -1, 1 };
        outside[0, 0] = true;
        queue.offer(0);
        while (!queue.is_empty) {
            int v = queue.poll();
            int r = v / fc, c = v % fc;
            for (int d = 0; d < 4; d++) {
                int nr = r + dr[d], nc = c + dc[d];
                if (nr < 0 || nc < 0 || nr >= fr || nc >= fc || outside[nr, nc] || blocked[nr, nc]) continue;
                outside[nr, nc] = true;
                queue.offer(nr * fc + nc);
            }
        }
        // Inside areas: connected unblocked, non-outside fine cells
        var area_of = new int[fr, fc];
        for (int r = 0; r < fr; r++) {
            for (int c = 0; c < fc; c++) area_of[r, c] = -1;
        }
        var shape_of = new int[rows, cols];
        var shapes = new Gee.ArrayList<Shape>();
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) shape_of[r, c] = -1;
        }
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                int f_r = 2 * r + 1, f_c = 2 * c + 1;
                if (outside[f_r, f_c] || blocked[f_r, f_c] || area_of[f_r, f_c] >= 0) continue;
                var s = new Shape();
                int id = shapes.size;
                shapes.add(s);
                area_of[f_r, f_c] = id;
                queue.offer(f_r * fc + f_c);
                while (!queue.is_empty) {
                    int v = queue.poll();
                    int vr = v / fc, vc = v % fc;
                    if (vr % 2 == 1 && vc % 2 == 1) {
                        int cr = vr / 2, cc = vc / 2;
                        s.cells.add(cr * cols + cc);
                        shape_of[cr, cc] = id;
                    }
                    for (int d = 0; d < 4; d++) {
                        int nr = vr + dr[d], nc = vc + dc[d];
                        if (nr < 0 || nc < 0 || nr >= fr || nc >= fc) continue;
                        if (area_of[nr, nc] >= 0 || blocked[nr, nc] || outside[nr, nc]) continue;
                        area_of[nr, nc] = id;
                        queue.offer(nr * fc + nc);
                    }
                }
            }
        }

        // Each shape covers the 2x2-cell squares around its inside cells (from
        // line centre to line centre). sub[i, j] is the unit square with its
        // top-left corner at lattice point (x = j - 1, y = i - 1).
        var boundary = new Gee.HashSet<string>();
        for (int si = 0; si < shapes.size; si++) {
            var s = shapes[si];
            var sub = new bool[rows + 2, cols + 2];
            s.min_x = int.MAX; s.min_y = int.MAX; s.max_x = int.MIN; s.max_y = int.MIN;
            foreach (int v in s.cells) {
                int r = v / cols, c = v % cols;
                for (int i = r - 1; i <= r; i++) {
                    for (int j = c - 1; j <= c; j++) sub[i + 1, j + 1] = true;
                }
                s.min_x = int.min(s.min_x, c - 1); s.max_x = int.max(s.max_x, c + 1);
                s.min_y = int.min(s.min_y, r - 1); s.max_y = int.max(s.max_y, r + 1);
                if (color_at.has_key(v)) s.color = color_at[v];
                if (kind_at.has_key(v)) s.kind = kind_at[v];
            }
            int area = 0;
            for (int i = 0; i < rows + 2; i++) {
                for (int j = 0; j < cols + 2; j++) {
                    if (!sub[i, j]) continue;
                    area++;
                    int y = i - 1, x = j - 1;
                    if (i == 0 || !sub[i - 1, j]) add_edge(boundary, s, "h", y, x);
                    if (i == rows + 1 || !sub[i + 1, j]) add_edge(boundary, s, "h", y + 1, x);
                    if (j == 0 || !sub[i, j - 1]) add_edge(boundary, s, "v", y, x);
                    if (j == cols + 1 || !sub[i, j + 1]) add_edge(boundary, s, "v", y, x + 1);
                }
            }
            s.rect = area == (s.max_x - s.min_x) * (s.max_y - s.min_y);
            unichar[] corners = { at(s.min_y, s.min_x), at(s.min_y, s.max_x), at(s.max_y, s.min_x), at(s.max_y, s.max_x) };
            foreach (unichar ch in corners) {
                if (ch == '/' || ch == '\\') s.rounded = true;
            }
            if (diagram.round_corners) s.rounded = true;
            s.sub = (owned) sub;
        }

        var w = new PinnedDotWriter();
        w.graph_attrs = "outputorder=nodesfirst";
        double inset = diagram.separation ? 2.0 * k : 0.0;
        string line_color = "#000000";

        // ---- shadows, then shapes ----
        if (diagram.shadows) {
            for (int si = 0; si < shapes.size; si++) {
                var s = shapes[si];
                if (s.kind != null && s.kind != "d") continue;
                draw_fill(w, s, shapes[si].sub, 4 * k, "#00000040", inset, s.kind == "d" ? double.min(6 * k, (py(s.max_y) - py(s.min_y)) / 4) : 0);
            }
        }
        for (int si = 0; si < shapes.size; si++) {
            draw_shape(w, shapes[si], shapes[si].sub, inset, line_color, boundary);
        }

        // ---- connectors: joins that bound no shape ----
        var comp = new UnionFind(rows * cols);
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                if (c + 1 < cols && conn_h[r, c] && !boundary.contains("h:%d:%d".printf(r, c))) comp.union(r * cols + c, r * cols + c + 1);
                if (r + 1 < rows && conn_v[r, c] && !boundary.contains("v:%d:%d".printf(r, c))) comp.union(r * cols + c, (r + 1) * cols + c);
            }
        }
        var dashed_root = new Gee.HashSet<int>();
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                if ((grid[r, c] == '=' || grid[r, c] == ':') && is_wall(r, c)) dashed_root.add(comp.find(r * cols + c));
            }
        }
        // horizontal runs
        for (int r = 0; r < rows; r++) {
            int c = 0;
            while (c < cols - 1) {
                if (!connector_h(boundary, r, c)) { c++; continue; }
                int start = c;
                while (c < cols - 1 && connector_h(boundary, r, c)) c++;
                emit_run(w, true, r, start, c, dashed_root.contains(comp.find(r * cols + start)), palette.node_text);
            }
        }
        for (int c = 0; c < cols; c++) {
            int r = 0;
            while (r < rows - 1) {
                if (!connector_v(boundary, r, c)) { r++; continue; }
                int start = r;
                while (r < rows - 1 && connector_v(boundary, r, c)) r++;
                emit_run(w, false, c, start, r, dashed_root.contains(comp.find(start * cols + c)), palette.node_text);
            }
        }

        // ---- text: runs of non-line characters, split at double spaces ----
        for (int r = 0; r < rows; r++) {
            int c = 0;
            while (c < cols) {
                if (grid[r, c] == ' ' || is_wall(r, c)) { c++; continue; }
                int start = c;
                int last = c;
                while (c < cols) {
                    if (grid[r, c] != ' ' && !is_wall(r, c)) { last = c; c++; continue; }
                    if (grid[r, c] == ' ' && c + 1 < cols && grid[r, c + 1] != ' ' && !is_wall(r, c + 1) && c == last + 1) { c++; continue; }
                    break;
                }
                var text = new StringBuilder();
                for (int i = start; i <= last; i++) text.append_unichar(grid[r, i]);
                // Text on the canvas follows the theme; inside a shape it
                // contrasts with the shape's fill.
                string fg = palette.node_text;
                int sid = shape_of[r, start];
                if (sid >= 0) fg = RenderUtils.contrast_text(shapes[sid].color ?? "#FFFFFF");
                double cx = (px(start) + px(last)) / 2;
                double tw = (last - start + 1) * CW * 1.3 + 10;
                w.node(cx, py(r), tw, CH * 1.2,
                    "shape=plaintext fontsize=%s fontcolor=\"%s\" label=<<B>%s</B>>".printf(
                        PinnedDotWriter.num(12 * k * PinnedDotWriter.PX), fg, Markup.escape_text(text.str)));
                c = last + 1;
            }
        }

        w.max_x = double.max(w.max_x, 2 * MX + cols * CW);
        w.max_y = double.max(w.max_y, 2 * MY + rows * CH);
        return w.finish(palette.background, 0);
    }

    private bool cells_equal(int r, int c, string s) {
        for (int i = 0; i < s.length; i++) {
            if (at(r, c + i) != s[i]) return false;
        }
        return true;
    }

    private static bool is_arrow(unichar ch) {
        return ch == '>' || ch == '<' || ch == '^' || ch == 'v' || ch == 'V';
    }

    private void add_edge(Gee.HashSet<string> boundary, Shape s, string dir, int y, int x) {
        boundary.add("%s:%d:%d".printf(dir, y, x));
        // A shape drawn with = or : is dashed
        unichar a = at(y, x);
        unichar b = dir == "h" ? at(y, x + 1) : at(y + 1, x);
        if (a == '=' || a == ':' || b == '=' || b == ':') s.dashed = true;
    }

    private bool connector_h(Gee.HashSet<string> boundary, int r, int c) {
        return conn_h[r, c] && !boundary.contains("h:%d:%d".printf(r, c));
    }

    private bool connector_v(Gee.HashSet<string> boundary, int r, int c) {
        return conn_v[r, c] && !boundary.contains("v:%d:%d".printf(r, c));
    }

    // A straight connector from lattice `a` to `b` along row/column `line`;
    // arrowhead characters at either end put a head there, reaching into the
    // next cell's line when one is there.
    private void emit_run(PinnedDotWriter w, bool horizontal, int line, int a, int b, bool dashed, string color) {
        unichar ca = horizontal ? at(line, a) : at(a, line);
        unichar cb = horizontal ? at(line, b) : at(b, line);
        bool head_a = horizontal ? ca == '<' : ca == '^';
        bool head_b = horizontal ? cb == '>' : (cb == 'v' || cb == 'V');
        double pa = a, pb = b;
        if (head_a) pa = a - ((horizontal ? is_wall(line, a - 1) : is_wall(a - 1, line)) ? 1.0 : 0.5);
        if (head_b) pb = b + ((horizontal ? is_wall(line, b + 1) : is_wall(b + 1, line)) ? 1.0 : 0.5);
        double[] pts = horizontal
            ? new double[] { px(pa), py(line), px(pb), py(line) }
            : new double[] { px(line), py(pa), px(line), py(pb) };
        string attrs = "color=\"%s\" penwidth=0.75 arrowsize=0.8%s".printf(color, dashed ? " style=dashed" : "");
        w.polyline(pts, attrs, head_b, head_a, 10 * k);
    }

    private void draw_fill(PinnedDotWriter w, Shape s, bool[,] sub, double offset, string fill, double inset,
                           double cut_bottom = 0) {
        if (s.rect || s.kind != null) {
            double x0 = px(s.min_x) + inset + offset, x1 = px(s.max_x) - inset + offset;
            double y0 = py(s.min_y) + inset + offset, y1 = py(s.max_y) - inset + offset - cut_bottom;
            string style = s.rounded ? "\"rounded,filled\"" : "filled";
            w.node((x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0,
                "shape=box style=%s fillcolor=\"%s\" color=\"%s\" penwidth=0".printf(style, fill, fill));
            return;
        }
        // Irregular shape: one filled strip per row of unit squares
        for (int i = 0; i < rows + 2; i++) {
            int j = 0;
            while (j < cols + 2) {
                if (!sub[i, j]) { j++; continue; }
                int start = j;
                while (j < cols + 2 && sub[i, j]) j++;
                double x0 = px(start - 1) + offset, x1 = px(j - 1) + offset;
                double y0 = py(i - 1) + offset, y1 = py(i) + offset;
                w.node((x0 + x1) / 2, (y0 + y1) / 2, x1 - x0 + 0.5, y1 - y0 + 0.5,
                    "shape=box style=filled fillcolor=\"%s\" color=\"%s\" penwidth=0".printf(fill, fill));
            }
        }
    }

    private void draw_shape(PinnedDotWriter w, Shape s, bool[,] sub, double inset, string line_color,
                            Gee.HashSet<string> boundary) {
        string fill = s.color ?? "#FFFFFF";
        double x0 = px(s.min_x) + inset, x1 = px(s.max_x) - inset;
        double y0 = py(s.min_y) + inset, y1 = py(s.max_y) - inset;
        double cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
        string dash = s.dashed ? "dashed," : "";
        string common = "fillcolor=\"%s\" color=\"%s\" penwidth=0.75".printf(fill, line_color);

        if (s.kind != null && s.kind != "d") {
            string shape;
            switch (s.kind) {
                case "s": shape = "cylinder"; break;
                case "io": shape = "parallelogram"; break;
                case "c": shape = "diamond"; break;
                case "o": shape = "ellipse"; break;
                case "mo": shape = "invtrapezium"; break;
                default: shape = "trapezium"; break;
            }
            w.node(cx, cy, x1 - x0, y1 - y0, "shape=%s style=\"%sfilled\" %s".printf(shape, dash, common));
            return;
        }
        if (s.kind == "d") {
            // Document: a wavy bottom edge
            double wave = double.min(6 * k, (y1 - y0) / 4);
            double yb = y1 - wave;
            w.node(cx, (y0 + yb) / 2, x1 - x0, yb - y0, "shape=box style=filled fillcolor=\"%s\" color=\"%s\" penwidth=0".printf(fill, fill));
            string la = "color=\"%s\" penwidth=0.75%s".printf(line_color, s.dashed ? " style=dashed" : "");
            w.polyline({ x0, yb, x0, y0, x1, y0, x1, yb }, la);
            double q = (x1 - x0) / 4;
            w.spline({ x0, yb, x0 + q, yb + 2 * wave, x0 + q, yb + 2 * wave, cx, yb,
                       cx + q, yb - 2 * wave, cx + q, yb - 2 * wave, x1, yb }, la);
            return;
        }
        if (s.rect) {
            string style = s.rounded ? "rounded,filled" : "filled";
            w.node(cx, cy, x1 - x0, y1 - y0, "shape=box style=\"%s%s\" %s".printf(dash, style, common));
            return;
        }
        // Irregular: filled strips, then the outline along the lines
        draw_fill(w, s, sub, 0, fill, 0);
        string la = "color=\"%s\" penwidth=0.75%s".printf(line_color, s.dashed ? " style=dashed" : "");
        for (int i = 0; i <= rows + 1; i++) {
            for (int j = 0; j <= cols + 1; j++) {
                if (!sub[i, j]) continue;
                double lx0 = px(j - 1), lx1 = px(j), ly0 = py(i - 1), ly1 = py(i);
                if (i == 0 || !sub[i - 1, j]) w.polyline({ lx0, ly0, lx1, ly0 }, la);
                if (i == rows + 1 || !sub[i + 1, j]) w.polyline({ lx0, ly1, lx1, ly1 }, la);
                if (j == 0 || !sub[i, j - 1]) w.polyline({ lx0, ly0, lx0, ly1 }, la);
                if (j == cols + 1 || !sub[i, j + 1]) w.polyline({ lx1, ly0, lx1, ly1 }, la);
            }
        }
    }

    private class UnionFind {
        private int[] parent;
        public UnionFind(int n) {
            parent = new int[n];
            for (int i = 0; i < n; i++) parent[i] = i;
        }
        public int find(int x) {
            while (parent[x] != x) {
                parent[x] = parent[parent[x]];
                x = parent[x];
            }
            return x;
        }
        public void union(int a, int b) {
            int ra = find(a), rb = find(b);
            if (ra != rb) parent[ra] = rb;
        }
    }

    public uint8[]? render_to_svg(DitaaDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse DITAA DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout DITAA graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render DITAA diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(DitaaDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(DitaaDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(DitaaDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(DitaaDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
