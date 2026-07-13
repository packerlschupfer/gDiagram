namespace GDiagram {
    public class MermaidGitGraphRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // Branch colors cycle through palette role slots so each branch
        // is visually distinct within the active theme.
        private string[] branch_fill() {
            var p = ThemeManager.get_active_palette();
            return new string[] {
                p.success, p.container_fill, p.warning, p.accent_secondary,
                p.person_fill, p.component_fill, p.accent_primary, p.database_fill
            };
        }
        private string[] branch_border() {
            var p = ThemeManager.get_active_palette();
            return new string[] {
                p.success, p.container_border, p.warning, p.accent_secondary,
                p.person_border, p.component_border, p.accent_primary, p.database_border
            };
        }

        public MermaidGitGraphRenderer(
            Gvc.Context ctx,
            Gee.ArrayList<ElementRegion> regions,
            string engine
        ) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidGitGraph diagram) {
            var dot = new StringBuilder();

            // Map branch name -> index for color selection (int? to allow ?? 0 fallback)
            var branch_idx = new Gee.HashMap<string, int?>();
            for (int i = 0; i < diagram.branches.size; i++) {
                branch_idx.set(diagram.branches.get(i).name, (int?) i);
            }

            // Build a set of valid commit IDs for safe edge rendering
            var commit_ids = new Gee.HashSet<string>();
            foreach (var c in diagram.all_commits) {
                commit_ids.add(c.id);
            }

            var palette = ThemeManager.get_active_palette();
            var BRANCH_FILL = branch_fill();
            var BRANCH_BORDER = branch_border();
            dot.append("digraph gitgraph {\n");
            dot.append("  rankdir=LR;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Monospace\", fontsize=9, width=0.65, height=0.65];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=8, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("\n");

            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n",
                    RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n");
                dot.append("  fontname=\"Sans\";\n\n");
            }

            int n = diagram.all_commits.size;

            // Invisible timeline chain to enforce left-to-right ordering by commit.order
            if (n > 1) {
                for (int i = 0; i < n; i++) {
                    dot.append_printf("  _t%d [label=\"\", style=invis, fixedsize=true, width=0.01, height=0.01];\n", i);
                }
                dot.append("  ");
                for (int i = 0; i < n; i++) {
                    if (i > 0) dot.append(" -> ");
                    dot.append_printf("_t%d", i);
                }
                dot.append(" [style=invis, weight=10];\n\n");

                // Pin each commit to its timeline slot.
                // Use the loop index (0..n-1) rather than commit.order, because
                // commit.order is assigned from the full unfiltered log and may
                // have gaps when branches are filtered out — Graphviz would then
                // auto-create undeclared _t* nodes as visible artifacts.
                for (int i = 0; i < n; i++) {
                    dot.append_printf("  {rank=same; _t%d; %s;}\n",
                        i, node_id(diagram.all_commits.get(i).id));
                }
                dot.append("\n");
            }

            // Commit nodes
            foreach (var commit in diagram.all_commits) {
                int idx = branch_idx.get(commit.branch_name) ?? 0;
                string fill   = BRANCH_FILL[idx % BRANCH_FILL.length];
                string border = BRANCH_BORDER[idx % BRANCH_BORDER.length];

                string shape;
                switch (commit.commit_type) {
                    case GitGraphCommitType.REVERSE:
                        shape = "diamond";
                        break;
                    case GitGraphCommitType.HIGHLIGHT:
                        shape = "doublecircle";
                        break;
                    default:
                        shape = "circle";
                        break;
                }

                string label;
                if (commit.tag != null && commit.tag.length > 0) {
                    label = RenderUtils.escape_label(
                        "%s\\n[%s]".printf(commit.id, commit.tag));
                } else {
                    label = RenderUtils.escape_label(commit.id);
                }

                dot.append_printf(
                    "  %s [label=\"\", xlabel=\"%s\", shape=%s, style=\"filled\", " +
                    "fixedsize=true, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", penwidth=2];\n",
                    node_id(commit.id), label, shape, fill, border,
                    // the xlabel sits on the canvas beside the circle, not on its fill
                    palette.edge_text
                );
            }

            dot.append("\n");

            // Edges: sequential parent and merge-from
            foreach (var commit in diagram.all_commits) {
                int idx = branch_idx.get(commit.branch_name) ?? 0;
                string border = BRANCH_BORDER[idx % BRANCH_BORDER.length];

                if (commit.parent_id != null && commit.parent_id.length > 0 &&
                    commit_ids.contains(commit.parent_id)) {
                    dot.append_printf(
                        "  %s -> %s [color=\"%s\", penwidth=2];\n",
                        node_id(commit.parent_id), node_id(commit.id), border
                    );
                }

                if (commit.merge_from_id != null && commit.merge_from_id.length > 0 &&
                    commit_ids.contains(commit.merge_from_id)) {
                    dot.append_printf(
                        "  %s -> %s [style=dashed, color=\"" + palette.edge_color + "\", penwidth=1.5];\n",
                        node_id(commit.merge_from_id), node_id(commit.id)
                    );
                }
            }

            dot.append("\n");

            // Branch label nodes (rounded box at end of each branch chain)
            foreach (var branch in diagram.branches) {
                var head = branch.get_head();
                if (head == null) continue;

                int idx = branch_idx.get(branch.name) ?? 0;
                string fill   = BRANCH_FILL[idx % BRANCH_FILL.length];
                string border = BRANCH_BORDER[idx % BRANCH_BORDER.length];
                string lbl_nid = "branch_lbl_" + node_id(branch.name);

                dot.append_printf(
                    "  %s [label=\"%s\", shape=box, style=\"filled,rounded\", " +
                    "fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", fontsize=9, fontname=\"Sans Bold\", " +
                    "fixedsize=false, width=0, height=0];\n",
                    lbl_nid, RenderUtils.escape_label(branch.name), fill, border,
                    RenderUtils.contrast_text(fill)
                );
                dot.append_printf(
                    "  %s -> %s [style=dashed, color=\"%s\", arrowhead=none, penwidth=1];\n",
                    node_id(head.id), lbl_nid, border
                );
            }

            dot.append("}\n");
            return dot.str;
        }

        // Returns a valid Graphviz node identifier for a commit id string.
        private string node_id(string id) {
            var sb = new StringBuilder("n_");
            foreach (char c in id.to_utf8()) {
                if (c.isalnum() || c == '_') sb.append_c(c);
                else sb.append("_");
            }
            return sb.str;
        }

        // The picture is laid out like Mermaid's gitGraph renderer (branch
        // lanes, commit steps, arrow curves) and written as SVG directly;
        // generate_dot() above stays the graph form for "-f dot".
        public uint8[]? render_to_svg(MermaidGitGraph diagram) {
            var layout = new MermaidGitGraphLayout(diagram, ThemeManager.get_active_palette());
            string svg = layout.build();
            regions.clear();
            foreach (var r in layout.regions) regions.add(r);
            return svg.data;
        }

        public Cairo.ImageSurface? render_to_surface(MermaidGitGraph diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return null;
            return RenderUtils.svg_to_surface(svg_data);
        }

        public bool export_to_png(MermaidGitGraph diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) return false;
            return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidGitGraph diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidGitGraph diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }

    /**
     * Port of Mermaid 11.17's gitGraphRenderer.ts (default theme geometry):
     * branches are lanes 90 px apart (50 + 40 for rotated commit labels),
     * commits advance 50 px per sequence step (or from their closest parent
     * with parallelCommits), arrows are 8 px round-capped paths with 20 px
     * corners, rerouted onto a free lane when a commit of the curving branch
     * lies between the two ends.
     */
    public class MermaidGitGraphLayout : Object {
        private const double LAYOUT_OFFSET = 10;
        private const double COMMIT_STEP = 40;
        private const double PX = 4;
        private const double PY = 2;
        private const double DEFAULT_POS = 30;
        private const int COLOR_LIMIT = 8;

        private enum Symbol { NORMAL, REVERSE, HIGHLIGHT, MERGE, CHERRY_PICK }

        private class Point {
            public double x;
            public double y;
            public Point(double x, double y) { this.x = x; this.y = y; }
        }

        private class BranchPos {
            public double pos;
            public int index;
            public BranchPos(double pos, int index) { this.pos = pos; this.index = index; }
        }

        private MermaidGitGraph d;
        private Palette palette;
        public Gee.ArrayList<ElementRegion> regions { get; private set; }

        private string dir;
        private Gee.HashMap<string, BranchPos> branch_pos;
        private Gee.HashMap<string, Point> commit_pos;
        private Gee.HashMap<string, GitGraphCommit> by_id;
        private Gee.HashMap<GitGraphCommit, int> seq_of;
        private Gee.ArrayList<double?> lanes;
        private double max_pos;

        private StringBuilder sb_branches;
        private StringBuilder sb_arrows;
        private StringBuilder sb_bullets;
        private StringBuilder sb_labels;

        private double min_x = double.MAX;
        private double min_y = double.MAX;
        private double max_x = -double.MAX;
        private double max_y = -double.MAX;

        // Colours
        private bool dark;
        private string c_text;
        private string c_branch_line;
        private string c_inner;
        private string c_label_text;
        private string c_label_bkg;
        private double label_bkg_opacity;
        private string c_cherry;
        private string c_cherry_mark;

        // Mermaid default theme git0..git7, their label colours and inverses
        private const string[] GIT = {
            "#0000EC", "#DEDE00", "#9DEC00", "#0076EC", "#00ECEC", "#00EC76", "#EC00EC", "#EC0000"
        };
        private const string[] GIT_LABEL = {
            "#FFFFFF", "#000000", "#000000", "#FFFFFF", "#000000", "#000000", "#000000", "#000000"
        };
        private const string[] GIT_INV = {
            "#131300", "#0000A1", "#310093", "#934900", "#930000", "#930049", "#009300", "#009393"
        };

        public MermaidGitGraphLayout(MermaidGitGraph diagram, Palette palette) {
            this.d = diagram;
            this.palette = palette;
            this.regions = new Gee.ArrayList<ElementRegion>();
            this.dir = diagram.direction;
            branch_pos = new Gee.HashMap<string, BranchPos>();
            commit_pos = new Gee.HashMap<string, Point>();
            by_id = new Gee.HashMap<string, GitGraphCommit>();
            seq_of = new Gee.HashMap<GitGraphCommit, int>();
            lanes = new Gee.ArrayList<double?>();
            int s = 0;
            foreach (var c in d.all_commits) {
                by_id[c.id] = c;
                seq_of[c] = s++;
            }
            setup_colours();
        }

        private void setup_colours() {
            dark = MermaidGanttLayout.is_dark(palette.background);
            c_text = dark ? palette.node_text : "#333333";
            c_branch_line = dark ? palette.edge_color : "#333333";
            c_inner = dark ? palette.background : "#ECECFF";
            c_label_text = dark ? palette.node_text : "#000021";
            c_label_bkg = dark ? palette.background : "#FFFFDE";
            label_bkg_opacity = 0.5;
            c_cherry = dark ? "#A0A0A0" : "#333333";
            c_cherry_mark = dark ? "#000000" : "#FFFFFF";
        }

        // ---- helpers ----

        private static string f(double v) {
            string s = "%.3f".printf(v).replace(",", ".");
            while (s.contains(".") && (s.has_suffix("0") || s.has_suffix("."))) {
                s = s.substring(0, s.length - 1);
                if (!s.contains(".")) break;
            }
            return s;
        }

        private static string esc(string s) {
            return Markup.escape_text(s);
        }

        private static double text_w(string s, double size) {
            return GanttText.width(s, size);
        }

        // getBBox height of a text line
        private static double text_h(double size) {
            return Math.round(size * 1.1);
        }

        private void track(double x, double y) {
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }

        // Track a rectangle transformed by rotate(angle, cx, cy) then translate(tx, ty)
        private void track_rect(double x, double y, double w, double h,
                                double angle = 0, double cx = 0, double cy = 0,
                                double tx = 0, double ty = 0) {
            double a = angle * Math.PI / 180.0;
            double ca = Math.cos(a), sa = Math.sin(a);
            double[] xs = { x, x + w, x + w, x };
            double[] ys = { y, y, y + h, y + h };
            for (int i = 0; i < 4; i++) {
                double px = xs[i], py = ys[i];
                if (angle != 0) {
                    double dx = px - cx, dy = py - cy;
                    px = cx + dx * ca - dy * sa;
                    py = cy + dx * sa + dy * ca;
                }
                track(px + tx, py + ty);
            }
        }

        private int color_index(string branch) {
            var bp = branch_pos[branch];
            return (bp != null ? bp.index : 0) % COLOR_LIMIT;
        }

        // Mermaid picks the symbol with `commit.customType ?? commit.type`: an
        // explicit `type:` always wins, so `merge main type: NORMAL` draws a
        // plain commit circle, not the merge donut.
        private Symbol symbol_of(GitGraphCommit c) {
            if (c.has_custom_type) {
                switch (c.commit_type) {
                    case GitGraphCommitType.REVERSE: return Symbol.REVERSE;
                    case GitGraphCommitType.HIGHLIGHT: return Symbol.HIGHLIGHT;
                    default: return Symbol.NORMAL;
                }
            }
            if (c.is_cherry_pick) return Symbol.CHERRY_PICK;
            if (is_merge(c)) return Symbol.MERGE;
            switch (c.commit_type) {
                case GitGraphCommitType.REVERSE: return Symbol.REVERSE;
                case GitGraphCommitType.HIGHLIGHT: return Symbol.HIGHLIGHT;
                default: return Symbol.NORMAL;
            }
        }

        private static bool is_merge(GitGraphCommit c) {
            return c.is_merge || (!c.is_cherry_pick && c.merge_from_id != null && c.merge_from_id.length > 0);
        }

        private Gee.ArrayList<string> parents(GitGraphCommit c) {
            var list = new Gee.ArrayList<string>();
            if (c.parent_id != null && by_id.has_key(c.parent_id)) list.add(c.parent_id);
            if (c.merge_from_id != null && by_id.has_key(c.merge_from_id)) list.add(c.merge_from_id);
            return list;
        }

        private bool vertical() {
            return dir == "TB" || dir == "BT";
        }

        public static string region_name(GitGraphCommit c) {
            var sb = new StringBuilder("n_");
            foreach (char ch in c.id.to_utf8()) {
                if (ch.isalnum() || ch == '_') sb.append_c(ch);
                else sb.append("_");
            }
            return sb.str;
        }

        // ---- layout ----

        private Gee.ArrayList<GitGraphBranch> sorted_branches() {
            var list = new Gee.ArrayList<GitGraphBranch>();
            list.add_all(d.branches);
            // Stable sort by order (Array.prototype.sort is stable)
            for (int i = 1; i < list.size; i++) {
                var cur = list[i];
                int j = i - 1;
                while (j >= 0 && list[j].order > cur.order) {
                    list[j + 1] = list[j];
                    j--;
                }
                list[j + 1] = cur;
            }
            return list;
        }

        private void set_branch_positions(Gee.ArrayList<GitGraphBranch> branches) {
            double pos = 0;
            int index = 0;
            foreach (var b in branches) {
                branch_pos[b.name] = new BranchPos(pos, index++);
                pos += 50 + (d.rotate_commit_label ? 40 : 0) + (vertical() ? text_w(b.name, 16) / 2 : 0);
            }
        }

        private string? find_closest_parent(Gee.ArrayList<string> ps) {
            string? closest = null;
            double target = dir == "BT" ? double.MAX : 0;
            foreach (string p in ps) {
                var cp = commit_pos[p];
                if (cp == null) continue;
                double v = vertical() ? cp.y : cp.x;
                bool ok = dir == "BT" ? v <= target : v >= target;
                if (ok) {
                    closest = p;
                    target = v;
                }
            }
            return closest;
        }

        private double calculate_position(GitGraphCommit c) {
            var ps = parents(c);
            if (ps.size > 0) {
                string? closest = find_closest_parent(ps);
                if (closest != null) {
                    var pp = commit_pos[closest];
                    if (dir == "TB") return pp.y + COMMIT_STEP;
                    if (dir == "BT") {
                        var cur = commit_pos[c.id];
                        return (cur != null ? cur.y : 0) - COMMIT_STEP;
                    }
                    return pp.x + COMMIT_STEP;
                }
                return 0;
            }
            if (dir == "TB") return DEFAULT_POS;
            if (dir == "BT") {
                var cur = commit_pos[c.id];
                return (cur != null ? cur.y : 0) - COMMIT_STEP;
            }
            return 0;
        }

        // setParallelBTPos
        private void set_parallel_bt_positions(Gee.ArrayList<GitGraphCommit> sorted) {
            double cur = DEFAULT_POS;
            double max_position = DEFAULT_POS;
            var roots = new Gee.ArrayList<GitGraphCommit>();
            foreach (var c in sorted) {
                if (parents(c).size > 0) {
                    string? closest = find_closest_parent(parents(c));
                    if (closest != null && commit_pos[closest] != null) cur = commit_pos[closest].y + COMMIT_STEP;
                    max_position = double.max(cur, max_position);
                } else {
                    roots.add(c);
                }
                var bp = branch_pos[c.branch_name];
                commit_pos[c.id] = new Point(bp != null ? bp.pos : 0, cur + LAYOUT_OFFSET);
            }
            cur = max_position;
            foreach (var c in roots) {
                var bp = branch_pos[c.branch_name];
                commit_pos[c.id] = new Point(bp != null ? bp.pos : 0, cur + DEFAULT_POS);
            }
            foreach (var c in sorted) {
                var ps = parents(c);
                if (ps.size == 0) continue;
                string? closest = null;
                double maxp = double.MAX;
                foreach (string p in ps) {
                    var cp = commit_pos[p];
                    if (cp != null && cp.y <= maxp) { closest = p; maxp = cp.y; }
                }
                if (closest == null) continue;
                cur = commit_pos[closest].y - COMMIT_STEP;
                if (cur <= max_position) max_position = cur;
                var bp = branch_pos[c.branch_name];
                commit_pos[c.id] = new Point(bp != null ? bp.pos : 0, cur - LAYOUT_OFFSET);
            }
        }

        private void draw_commits(bool modify) {
            double pos = vertical() ? DEFAULT_POS : 0;
            bool parallel = d.parallel_commits;
            var sorted = new Gee.ArrayList<GitGraphCommit>();
            sorted.add_all(d.all_commits);
            if (dir == "BT") {
                if (parallel) set_parallel_bt_positions(sorted);
                var rev = new Gee.ArrayList<GitGraphCommit>();
                for (int i = sorted.size - 1; i >= 0; i--) rev.add(sorted[i]);
                sorted = rev;
            }
            foreach (var c in sorted) {
                if (parallel) pos = calculate_position(c);
                double with_offset = (dir == "BT" && parallel) ? pos : pos + LAYOUT_OFFSET;
                var bp = branch_pos[c.branch_name];
                double branch_coord = bp != null ? bp.pos : 0;
                double x = vertical() ? branch_coord : with_offset;
                double y = vertical() ? with_offset : branch_coord - 2;
                if (modify) {
                    int ci = color_index(c.branch_name);
                    draw_bullet(c, x, y, ci);
                    draw_label(c, x, y, with_offset, pos);
                    draw_tags(c, x, y, with_offset, pos);
                    regions.add(new ElementRegion(region_name(c), c.source_line, x - 10, y - 10, 20, 20));
                }
                if (vertical()) commit_pos[c.id] = new Point(x, with_offset);
                else commit_pos[c.id] = new Point(with_offset, y);
                pos = (dir == "BT" && parallel) ? pos + COMMIT_STEP : pos + COMMIT_STEP + LAYOUT_OFFSET;
                if (pos > max_pos) max_pos = pos;
            }
        }

        private void draw_bullet(GitGraphCommit c, double x, double y, int ci) {
            unowned StringBuilder sb = sb_bullets;
            switch (symbol_of(c)) {
                case Symbol.HIGHLIGHT:
                    sb.append("<rect x=\"%s\" y=\"%s\" width=\"20\" height=\"20\" fill=\"%s\" stroke=\"%s\"/>\n".printf(
                        f(x - 10), f(y - 10), dark ? GIT[ci] : GIT_INV[ci], dark ? GIT[ci] : GIT_INV[ci]));
                    sb.append("<rect x=\"%s\" y=\"%s\" width=\"12\" height=\"12\" fill=\"%s\" stroke=\"%s\"/>\n".printf(
                        f(x - 6), f(y - 6), c_inner, c_inner));
                    track_rect(x - 10, y - 10, 20, 20);
                    return;
                case Symbol.CHERRY_PICK:
                    sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"10\" fill=\"%s\"/>\n".printf(f(x), f(y), c_cherry));
                    sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"2.75\" fill=\"%s\"/>\n".printf(f(x - 3), f(y + 2), c_cherry_mark));
                    sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"2.75\" fill=\"%s\"/>\n".printf(f(x + 3), f(y + 2), c_cherry_mark));
                    sb.append("<path d=\"M %s %s L %s %s M %s %s L %s %s\" stroke=\"%s\" fill=\"none\"/>\n".printf(
                        f(x + 3), f(y + 1), f(x), f(y - 5), f(x - 3), f(y + 1), f(x), f(y - 5), c_cherry_mark));
                    track_rect(x - 10, y - 10, 20, 20);
                    return;
                default:
                    break;
            }
            sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"10\" fill=\"%s\" stroke=\"%s\"/>\n".printf(
                f(x), f(y), GIT[ci], GIT[ci]));
            track_rect(x - 10, y - 10, 20, 20);
            var sym = symbol_of(c);
            if (sym == Symbol.MERGE) {
                sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"6\" fill=\"%s\" stroke=\"%s\"/>\n".printf(
                    f(x), f(y), c_inner, c_inner));
            } else if (sym == Symbol.REVERSE) {
                sb.append("<path d=\"M %s,%s L%s,%s M%s,%s L%s,%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"3\"/>\n".printf(
                    f(x - 5), f(y - 5), f(x + 5), f(y + 5), f(x - 5), f(y + 5), f(x + 5), f(y - 5), c_inner));
            }
        }

        private void draw_label(GitGraphCommit c, double x, double y, double with_offset, double pos) {
            if (c.is_cherry_pick || !d.show_commit_label) return;
            if (is_merge(c) && !c.custom_id) return;
            unowned StringBuilder sb = sb_labels;
            double w = text_w(c.id, 10);
            double h = text_h(10);
            double bx = with_offset - w / 2 - PY, by = y + 13.5;
            double tx = with_offset - w / 2, ty = y + 25;
            string transform = "";
            double angle = 0, cx = 0, cy = 0, trx = 0, try_ = 0;
            if (vertical()) {
                bx = x - (w + 4 * PX + 5);
                by = y - 12;
                tx = x - (w + 4 * PX);
                ty = y + h - 12;
                if (d.rotate_commit_label) {
                    transform = " transform=\"rotate(-45, %s, %s)\"".printf(f(x), f(y));
                    angle = -45; cx = x; cy = y;
                }
            } else if (d.rotate_commit_label) {
                double r_x = -7.5 - ((w + 10) / 25) * 9.5;
                double r_y = 10 + (w / 25) * 8.5;
                transform = " transform=\"translate(%s, %s) rotate(-45, %s, %s)\"".printf(f(r_x), f(r_y), f(pos), f(y));
                angle = -45; cx = pos; cy = y; trx = r_x; try_ = r_y;
            }
            sb.append("<g%s>\n".printf(transform));
            sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" fill-opacity=\"%s\"/>\n".printf(
                f(bx), f(by), f(w + 2 * PY), f(h + 2 * PY), c_label_bkg, f(label_bkg_opacity)));
            sb.append("<text x=\"%s\" y=\"%s\" font-size=\"10\" fill=\"%s\">%s</text>\n".printf(
                f(tx), f(ty), c_label_text, esc(c.id)));
            sb.append("</g>\n");
            track_rect(bx, by, w + 2 * PY, h + 2 * PY, angle, cx, cy, trx, try_);
        }

        private void draw_tags(GitGraphCommit c, double x, double y, double with_offset, double pos) {
            var tag_list = new Gee.ArrayList<string>();
            if (c.tags.size > 0) tag_list.add_all(c.tags);
            else if (c.tag != null && c.tag.length > 0) tag_list.add(c.tag);
            if (tag_list.size == 0) return;
            unowned StringBuilder sb = sb_labels;
            double max_w = 0, max_h = text_h(10);
            for (int i = 0; i < tag_list.size; i++) max_w = double.max(max_w, text_w(tag_list[i], 10));
            double y_offset = 0;
            // Mermaid iterates the tags reversed
            for (int i = tag_list.size - 1; i >= 0; i--) {
                string tag = tag_list[i];
                double tw = text_w(tag, 10);
                double h2 = max_h / 2;
                if (vertical()) {
                    double yo = pos + y_offset;
                    string tr = "translate(12,12) rotate(45, %s,%s)".printf(f(x), f(pos));
                    string points = "%s,%s %s,%s %s,%s %s,%s %s,%s %s,%s".printf(
                        f(x), f(yo + 2), f(x), f(yo - 2), f(x + LAYOUT_OFFSET), f(yo - h2 - 2),
                        f(x + LAYOUT_OFFSET + max_w + 4), f(yo - h2 - 2),
                        f(x + LAYOUT_OFFSET + max_w + 4), f(yo + h2 + 2), f(x + LAYOUT_OFFSET), f(yo + h2 + 2));
                    sb.append("<polygon points=\"%s\" fill=\"#ECECFF\" stroke=\"#C7C7F1\" transform=\"%s\"/>\n".printf(points, tr));
                    sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"1.5\" fill=\"#333333\" transform=\"%s\"/>\n".printf(
                        f(x + PX / 2), f(yo), tr));
                    sb.append("<text x=\"%s\" y=\"%s\" font-size=\"10\" fill=\"#131300\" transform=\"translate(14,14) rotate(45, %s,%s)\">%s</text>\n".printf(
                        f(x + 5), f(yo + 3), f(x), f(pos), esc(tag)));
                    track_rect(x, yo - h2 - 2, LAYOUT_OFFSET + max_w + 4, max_h + 4, 45, x, pos, 12, 12);
                } else {
                    double ly = y - 19.2 - y_offset;
                    string points = "%s,%s %s,%s %s,%s %s,%s %s,%s %s,%s".printf(
                        f(pos - max_w / 2 - PX / 2), f(ly + PY), f(pos - max_w / 2 - PX / 2), f(ly - PY),
                        f(with_offset - max_w / 2 - PX), f(ly - h2 - PY),
                        f(with_offset + max_w / 2 + PX), f(ly - h2 - PY),
                        f(with_offset + max_w / 2 + PX), f(ly + h2 + PY),
                        f(with_offset - max_w / 2 - PX), f(ly + h2 + PY));
                    sb.append("<polygon points=\"%s\" fill=\"#ECECFF\" stroke=\"#C7C7F1\"/>\n".printf(points));
                    sb.append("<circle cx=\"%s\" cy=\"%s\" r=\"1.5\" fill=\"#333333\"/>\n".printf(
                        f(pos - max_w / 2 + PX / 2), f(ly)));
                    sb.append("<text x=\"%s\" y=\"%s\" font-size=\"10\" fill=\"#131300\">%s</text>\n".printf(
                        f(with_offset - tw / 2), f(y - 16 - y_offset), esc(tag)));
                    track_rect(double.min(pos - max_w / 2 - PX / 2, with_offset - max_w / 2 - PX),
                               ly - h2 - PY, max_w + 2 * PX + 10, max_h + 2 * PY);
                }
                y_offset += 20;
            }
        }

        private void draw_branches(Gee.ArrayList<GitGraphBranch> branches) {
            unowned StringBuilder sb = sb_branches;
            int index = 0;
            foreach (var b in branches) {
                int ci = index % COLOR_LIMIT;
                index++;
                double pos = branch_pos[b.name].pos;
                double spine = vertical() ? pos : pos - 2;
                double x1 = 0, y1 = spine, x2 = max_pos, y2 = spine;
                if (dir == "TB") { x1 = pos; y1 = DEFAULT_POS; x2 = pos; y2 = max_pos; }
                else if (dir == "BT") { x1 = pos; y1 = max_pos; x2 = pos; y2 = DEFAULT_POS; }
                sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"1\" stroke-dasharray=\"2\"/>\n".printf(
                    f(x1), f(y1), f(x2), f(y2), c_branch_line));
                track(x1, y1);
                track(x2, y2);
                lanes.add(spine);

                double w = text_w(b.name, 16);
                double h = text_h(16);
                double rx, ry, tx, ty;
                if (dir == "TB") {
                    rx = pos - w / 2 - 10; ry = 0;
                    tx = pos - w / 2 - 5; ty = 0;
                } else if (dir == "BT") {
                    rx = pos - w / 2 - 10; ry = max_pos;
                    tx = pos - w / 2 - 5; ty = max_pos;
                } else {
                    rx = -w - 4 - (d.rotate_commit_label ? 30 : 0) - 19;
                    ry = -h / 2 + 10 + spine - 12;
                    tx = -w - 14 - (d.rotate_commit_label ? 30 : 0);
                    ty = spine - h / 2 - 2;
                }
                sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"4\" ry=\"4\" fill=\"%s\"/>\n".printf(
                    f(rx), f(ry), f(w + 18), f(h + 4), GIT[ci]));
                // tspan dy=1em: centre the line in the 21 px box
                sb.append("<text x=\"%s\" y=\"%s\" font-size=\"16\" fill=\"%s\">%s</text>\n".printf(
                    f(tx), f(ry + (h + 4) / 2 + 16 * 0.35), GIT_LABEL[ci], esc(b.name)));
                track_rect(rx, ry, w + 18, h + 4);
                track_rect(tx, ty, w, h);
            }
        }

        private double find_lane(double y1, double y2, int depth = 0) {
            double candidate = y1 + Math.fabs(y1 - y2) / 2;
            if (depth > 5) return candidate;
            bool ok = true;
            foreach (var lane in lanes) {
                if (Math.fabs(lane - candidate) < 10) { ok = false; break; }
            }
            if (ok) {
                lanes.add(candidate);
                return candidate;
            }
            double diff = Math.fabs(y1 - y2);
            return find_lane(y1, y2 - diff / 5, depth + 1);
        }

        private bool should_reroute(GitGraphCommit a, GitGraphCommit b, Point p1, Point p2) {
            bool b_furthest = vertical() ? p1.x < p2.x : p1.y < p2.y;
            string branch = b_furthest ? b.branch_name : a.branch_name;
            int sa = seq_of[a], sb_ = seq_of[b];
            foreach (var x in d.all_commits) {
                int sx = seq_of[x];
                if (sx > sa && sx < sb_ && x.branch_name == branch) return true;
            }
            return false;
        }

        private void draw_arrow(GitGraphCommit a, GitGraphCommit b) {
            var p1 = commit_pos[a.id];
            var p2 = commit_pos[b.id];
            if (p1 == null || p2 == null) return;
            bool reroute = should_reroute(a, b, p1, p2);
            int color = color_index(b.branch_name);
            bool merge_second = is_merge(b) && a.id != b.parent_id;
            if (merge_second) color = color_index(a.branch_name);

            string? line = null;
            if (reroute) {
                string arc = "A 10 10, 0, 0, 0,";
                string arc2 = "A 10 10, 0, 0, 1,";
                double radius = 10, offset = 10;
                double line_y = p1.y < p2.y ? find_lane(p1.y, p2.y) : find_lane(p2.y, p1.y);
                double line_x = p1.x < p2.x ? find_lane(p1.x, p2.x) : find_lane(p2.x, p1.x);
                if (dir == "TB") {
                    if (p1.x < p2.x) {
                        line = "M %s %s L %s %s %s %s %s L %s %s %s %s %s L %s %s".printf(
                            f(p1.x), f(p1.y), f(line_x - radius), f(p1.y), arc2, f(line_x), f(p1.y + offset),
                            f(line_x), f(p2.y - radius), arc, f(line_x + offset), f(p2.y), f(p2.x), f(p2.y));
                    } else {
                        color = color_index(a.branch_name);
                        line = "M %s %s L %s %s %s %s %s L %s %s %s %s %s L %s %s".printf(
                            f(p1.x), f(p1.y), f(line_x + radius), f(p1.y), arc, f(line_x), f(p1.y + offset),
                            f(line_x), f(p2.y - radius), arc2, f(line_x - offset), f(p2.y), f(p2.x), f(p2.y));
                    }
                } else if (dir == "BT") {
                    if (p1.x < p2.x) {
                        line = "M %s %s L %s %s %s %s %s L %s %s %s %s %s L %s %s".printf(
                            f(p1.x), f(p1.y), f(line_x - radius), f(p1.y), arc, f(line_x), f(p1.y - offset),
                            f(line_x), f(p2.y + radius), arc2, f(line_x + offset), f(p2.y), f(p2.x), f(p2.y));
                    } else {
                        color = color_index(a.branch_name);
                        line = "M %s %s L %s %s %s %s %s L %s %s %s %s %s L %s %s".printf(
                            f(p1.x), f(p1.y), f(line_x + radius), f(p1.y), arc2, f(line_x), f(p1.y - offset),
                            f(line_x), f(p2.y + radius), arc, f(line_x - offset), f(p2.y), f(p2.x), f(p2.y));
                    }
                } else {
                    if (p1.y < p2.y) {
                        line = "M %s %s L %s %s %s %s %s L %s %s %s %s %s L %s %s".printf(
                            f(p1.x), f(p1.y), f(p1.x), f(line_y - radius), arc, f(p1.x + offset), f(line_y),
                            f(p2.x - radius), f(line_y), arc2, f(p2.x), f(line_y + offset), f(p2.x), f(p2.y));
                    } else {
                        color = color_index(a.branch_name);
                        line = "M %s %s L %s %s %s %s %s L %s %s %s %s %s L %s %s".printf(
                            f(p1.x), f(p1.y), f(p1.x), f(line_y + radius), arc2, f(p1.x + offset), f(line_y),
                            f(p2.x - radius), f(line_y), arc, f(p2.x), f(line_y - offset), f(p2.x), f(p2.y));
                    }
                }
            } else {
                string arc = "A 20 20, 0, 0, 0,";
                string arc2 = "A 20 20, 0, 0, 1,";
                double radius = 20, offset = 20;
                string straight = "M %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x), f(p2.y));
                if (dir == "TB") {
                    if (p1.x < p2.x) {
                        line = merge_second
                            ? "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p1.x), f(p2.y - radius), arc, f(p1.x + offset), f(p2.y), f(p2.x), f(p2.y))
                            : "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x - radius), f(p1.y), arc2, f(p2.x), f(p1.y + offset), f(p2.x), f(p2.y));
                    } else if (p1.x > p2.x) {
                        line = merge_second
                            ? "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p1.x), f(p2.y - radius), arc2, f(p1.x - offset), f(p2.y), f(p2.x), f(p2.y))
                            : "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x + radius), f(p1.y), arc, f(p2.x), f(p1.y + offset), f(p2.x), f(p2.y));
                    } else {
                        line = straight;
                    }
                } else if (dir == "BT") {
                    if (p1.x < p2.x) {
                        line = merge_second
                            ? "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p1.x), f(p2.y + radius), arc2, f(p1.x + offset), f(p2.y), f(p2.x), f(p2.y))
                            : "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x - radius), f(p1.y), arc, f(p2.x), f(p1.y - offset), f(p2.x), f(p2.y));
                    } else if (p1.x > p2.x) {
                        line = merge_second
                            ? "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p1.x), f(p2.y + radius), arc, f(p1.x - offset), f(p2.y), f(p2.x), f(p2.y))
                            : "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x + radius), f(p1.y), arc2, f(p2.x), f(p1.y - offset), f(p2.x), f(p2.y));
                    } else {
                        line = straight;
                    }
                } else {
                    if (p1.y < p2.y) {
                        line = merge_second
                            ? "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x - radius), f(p1.y), arc2, f(p2.x), f(p1.y + offset), f(p2.x), f(p2.y))
                            : "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p1.x), f(p2.y - radius), arc, f(p1.x + offset), f(p2.y), f(p2.x), f(p2.y));
                    } else if (p1.y > p2.y) {
                        line = merge_second
                            ? "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p2.x - radius), f(p1.y), arc, f(p2.x), f(p1.y - offset), f(p2.x), f(p2.y))
                            : "M %s %s L %s %s %s %s %s L %s %s".printf(f(p1.x), f(p1.y), f(p1.x), f(p2.y + radius), arc2, f(p1.x + offset), f(p2.y), f(p2.x), f(p2.y));
                    } else {
                        line = straight;
                    }
                }
            }
            sb_arrows.append("<path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"8\" stroke-linecap=\"round\"/>\n".printf(
                line, GIT[color]));
            track(p1.x, p1.y);
            track(p2.x, p2.y);
        }

        public string build() {
            sb_branches = new StringBuilder();
            sb_arrows = new StringBuilder();
            sb_bullets = new StringBuilder();
            sb_labels = new StringBuilder();
            regions.clear();

            var branches = sorted_branches();
            set_branch_positions(branches);
            draw_commits(false);
            if (d.show_branches) draw_branches(branches);
            foreach (var c in d.all_commits) {
                foreach (string p in parents(c)) draw_arrow(by_id[p], c);
            }
            // Second pass draws the commits over the arrows (as Mermaid does)
            draw_commits(true);

            if (min_x > max_x) {
                min_x = 0; min_y = 0; max_x = 100; max_y = 50;
            }
            // Title above the drawing, centred on it
            string title_svg = "";
            if (d.title != null && d.title.length > 0) {
                double cx = min_x + (max_x - min_x) / 2;
                double tw = text_w(d.title, 18);
                title_svg = "<text x=\"%s\" y=\"-25\" font-size=\"18\" text-anchor=\"middle\" fill=\"%s\">%s</text>\n".printf(
                    f(cx), c_text, esc(d.title));
                track_rect(cx - tw / 2, -25 - 18 * 0.9, tw, text_h(18));
            }

            const double PAD = 8;
            double vx = min_x - PAD, vy = min_y - PAD;
            double w = Math.ceil(max_x - min_x + 2 * PAD), h = Math.ceil(max_y - min_y + 2 * PAD);

            // Regions are in image pixels: shift by the view box origin
            foreach (var r in regions) {
                r.x -= vx;
                r.y -= vy;
            }

            var doc = new StringBuilder();
            doc.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            doc.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%spx\" height=\"%spx\" viewBox=\"%s %s %s %s\">\n".printf(
                f(w), f(h), f(vx), f(vy), f(w), f(h)));
            doc.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\"/>\n".printf(
                f(vx), f(vy), f(w), f(h), palette.background));
            doc.append("<g font-family=\"sans-serif\">\n");
            doc.append(sb_branches.str);
            doc.append(sb_arrows.str);
            doc.append(sb_bullets.str);
            doc.append(sb_labels.str);
            doc.append(title_svg);
            doc.append("</g>\n</svg>\n");
            return doc.str;
        }
    }
}
