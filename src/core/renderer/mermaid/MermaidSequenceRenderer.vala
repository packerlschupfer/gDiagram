namespace GDiagram {

    // ==================== Sequence layout model (Mermaid sequence + ZenUML) ====================

    public class SeqLayParticipant : Object {
        public string label { get; set; }
        // participant, actor, boundary, control, entity, database, collections, queue,
        // starter (ZenUML's nameless caller); ZenUML heads use zen_icon for the icon beside the name
        public string kind { get; set; default = "participant"; }
        public string? fill { get; set; default = null; }
        public string? stereotype { get; set; default = null; }  // ZenUML "«service»"
        public int line { get; set; default = 0; }
        public string node_id { get; set; }
        public string foot_id { get; set; }
        public int box { get; set; default = -1; }

        public SeqLayParticipant(string label, string node_id) {
            this.label = label;
            this.node_id = node_id;
            this.foot_id = node_id + "_foot";
        }
    }

    public class SeqLayBox : Object {
        public string? label { get; set; default = null; }
        public string? fill { get; set; default = null; }
    }

    public enum SeqLayKind {
        MESSAGE,
        NOTE,
        FRAME_START,
        FRAME_SECTION,
        FRAME_END,
        ACTIVATE,
        DEACTIVATE,
        CREATE,
        DESTROY
    }

    public enum SeqLayHead {
        NONE,
        ARROW,
        CROSS,
        OPEN,
        BOTH
    }

    public class SeqLayEvent : Object {
        public SeqLayKind kind { get; set; }
        public int a { get; set; default = -1; }
        public int b { get; set; default = -1; }
        public string? text { get; set; default = null; }
        public string? comment { get; set; default = null; }   // ZenUML "// ..." above a message
        public bool dotted { get; set; default = false; }
        public SeqLayHead head { get; set; default = SeqLayHead.ARROW; }
        public bool activate_target { get; set; default = false; }
        public bool deactivate_source { get; set; default = false; }
        public string? number { get; set; default = null; }
        public int line { get; set; default = 0; }
        public string? node_id { get; set; default = null; }
        public int note_side { get; set; default = 0; }        // -1 left of, 1 right of, 0 over
        public string? frame_label { get; set; default = null; } // "loop", "alt", ...
        public string? fill { get; set; default = null; }        // "rect" background

        public SeqLayEvent(SeqLayKind kind) {
            this.kind = kind;
        }
    }

    /**
     * Lays out a sequence diagram with fixed positions (layout=nop2), as the PlantUML
     * sequence renderer does: the Graphviz rank layout put Mermaid messages on rows of
     * shared invisible nodes, so frames ("loop", "alt", ...) could never be drawn as
     * clusters and notes floated in the header row.
     *
     *  1. every text node is measured with a throwaway Graphviz layout
     *  2. one column per participant, gaps wide enough for the labels and notes between them
     *  3. the events are walked in order: each message is a row with its label above a
     *     horizontal arrow, notes and frame headers / dividers take their own rows,
     *     activation bars stack on the lifeline
     *  4. frames are drawn around the rows they cover, coloured "rect" blocks and
     *     participant boxes behind everything
     */
    public class MermaidSeqLayout : Object {
        public Gee.ArrayList<SeqLayParticipant> participants { get; private set; }
        public Gee.ArrayList<SeqLayBox> boxes { get; private set; }
        public Gee.ArrayList<SeqLayEvent> events { get; private set; }
        public string? title { get; set; default = null; }
        // ZenUML look: dashed lifelines, no foot boxes, frame header bands, "1.1" numbers
        public bool zen { get; set; default = false; }

        private const double BAR_HALF = 5.0;
        private const double SELF_W = 30.0;
        private const double SELF_H = 16.0;

        private Gee.HashMap<string, double?> size_w = new Gee.HashMap<string, double?>();
        private Gee.HashMap<string, double?> size_h = new Gee.HashMap<string, double?>();
        private Gee.ArrayList<string> measure_ids = new Gee.ArrayList<string>();
        private Gee.ArrayList<string> measure_attrs = new Gee.ArrayList<string>();
        private Gee.ArrayList<string> icon_marks = new Gee.ArrayList<string>();

        private class FrameState : Object {
            public SeqLayEvent ev;
            public int index;
            public double top;
            public double min_x = double.MAX;
            public double max_x = -double.MAX;
            public Gee.ArrayList<double?> section_y = new Gee.ArrayList<double?>();
            public Gee.ArrayList<int> section_ev = new Gee.ArrayList<int>();
        }

        private Gee.ArrayList<FrameState> open_frames;
        private double ext_min;
        private double ext_max;

        public MermaidSeqLayout() {
            participants = new Gee.ArrayList<SeqLayParticipant>();
            boxes = new Gee.ArrayList<SeqLayBox>();
            events = new Gee.ArrayList<SeqLayEvent>();
        }

        // ---------------------------------------------------------------- DOT

        public string generate_dot(Gvc.Context context) {
            var palette = ThemeManager.get_active_palette();
            string bg = palette.background;
            string line_color = palette.edge_color;
            string text_color = palette.edge_text;
            string head_fill = palette.container_fill;
            string head_border = palette.container_border;
            string note_fill = palette.accent_secondary;
            string frame_color = palette.edge_color;
            string title_color = palette.node_text;
            string bar_fill = zen ? palette.grid : palette.background;

            int n = participants.size;
            measure_ids = new Gee.ArrayList<string>();
            measure_attrs = new Gee.ArrayList<string>();
            icon_marks = new Gee.ArrayList<string>();

            // ---- 1. what to measure ----
            var head_attrs = new string[n];
            for (int i = 0; i < n; i++) {
                var p = participants[i];
                string fill = p.fill != null ? color_value(p.fill) : head_fill;
                head_attrs[i] = participant_attrs(p, fill, head_border);
                want("_h%d".printf(i), head_attrs[i]);
            }
            for (int e = 0; e < events.size; e++) {
                var ev = events[e];
                switch (ev.kind) {
                    case SeqLayKind.MESSAGE:
                        if (ev.text != null && ev.text.length > 0) {
                            want("_l%d".printf(e), text_attrs(ev.text, 11, text_color));
                        }
                        if (ev.comment != null && ev.comment.length > 0) {
                            want("_cm%d".printf(e), text_attrs(ev.comment, 11, muted(text_color)));
                        }
                        if (ev.number != null && zen) {
                            want("_num%d".printf(e), text_attrs(ev.number, 9, palette.edge_color));
                        }
                        break;
                    case SeqLayKind.NOTE:
                        want("_n%d".printf(e), "shape=box, style=filled, fontsize=11, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", margin=\"0.1,0.06\", width=0.6, height=0.3, label=\"%s\"".printf(
                            note_fill, palette.node_border, RenderUtils.contrast_text(note_fill),
                            RenderUtils.escape_label(ev.text ?? "")));
                        break;
                    case SeqLayKind.FRAME_START:
                        if (ev.fill == null) {
                            string tab = ev.frame_label ?? "loop";
                            if (zen) {
                                want("_ft%d".printf(e), "shape=plaintext, style=solid, fontsize=11, fontname=\"Sans Bold\", fontcolor=\"%s\", margin=\"0.06,0.03\", width=0, height=0, label=\"%s\"".printf(
                                    title_color, RenderUtils.escape_label(tab)));
                            } else {
                                string tfill = head_fill;
                                want("_ft%d".printf(e), "shape=box, style=filled, fontsize=10, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", margin=\"0.06,0.02\", width=0, height=0, label=\"%s\"".printf(
                                    tfill, frame_color, RenderUtils.contrast_text(tfill), RenderUtils.escape_label(tab)));
                            }
                            if (ev.text != null && ev.text.length > 0) {
                                want("_fc%d".printf(e), text_attrs("[%s]".printf(ev.text), 11, text_color));
                            }
                        }
                        break;
                    case SeqLayKind.FRAME_SECTION:
                        if (ev.text != null && ev.text.length > 0) {
                            want("_fc%d".printf(e), text_attrs("[%s]".printf(ev.text), 11, text_color));
                        }
                        break;
                    default:
                        break;
                }
            }
            if (title != null && title.length > 0) {
                want("_title", "shape=plaintext, style=solid, fontsize=14, fontname=\"Sans Bold\", fontcolor=\"%s\", margin=0, width=0, height=0, label=\"%s\"".printf(
                    title_color, RenderUtils.escape_label(title)));
            }
            for (int k = 0; k < boxes.size; k++) {
                if (boxes[k].label != null && boxes[k].label.length > 0) {
                    string? bfill = boxes[k].fill != null ? color_value(boxes[k].fill) : null;
                    string bcol = bfill != null && !dark_canvas() ? RenderUtils.contrast_text_themed(bfill, title_color) : title_color;
                    want("_bl%d".printf(k), text_attrs(boxes[k].label, 11, bcol));
                }
            }
            measure_all(context);

            var head_w = new double[int.max(n, 1)];
            var head_h = new double[int.max(n, 1)];
            double head_row = 0;
            for (int i = 0; i < n; i++) {
                head_w[i] = w_of("_h%d".printf(i));
                head_h[i] = h_of("_h%d".printf(i));
                head_row = double.max(head_row, head_h[i]);
            }

            // ---- 2. columns ----
            var gap = new double[int.max(n * n, 1)];
            for (int i = 0; i + 1 < n; i++) {
                need(gap, n, i, i + 1, head_w[i] / 2 + head_w[i + 1] / 2 + (zen ? 40 : 50));
            }
            for (int e = 0; e < events.size; e++) {
                var ev = events[e];
                if (ev.kind == SeqLayKind.MESSAGE && ev.a >= 0 && ev.b >= 0) {
                    double lw = w_of("_l%d".printf(e));
                    double extra = ev.number != null ? (zen ? 0 : 20) : 0;
                    if (ev.a == ev.b) {
                        if (ev.a + 1 < n) {
                            need(gap, n, ev.a, ev.a + 1, double.max(SELF_W, lw + 4) + 30 + head_w[ev.a + 1] / 2 * 0);
                        }
                    } else {
                        need(gap, n, ev.a, ev.b, lw + 30 + extra);
                    }
                } else if (ev.kind == SeqLayKind.NOTE && ev.a >= 0) {
                    double nw = w_of("_n%d".printf(e));
                    if (ev.note_side > 0 && ev.a + 1 < n) {
                        need(gap, n, ev.a, ev.a + 1, nw + 30);
                    } else if (ev.note_side < 0 && ev.a > 0) {
                        need(gap, n, ev.a - 1, ev.a, nw + 30);
                    } else if (ev.note_side == 0 && (ev.b < 0 || ev.b == ev.a)) {
                        if (ev.a + 1 < n) need(gap, n, ev.a, ev.a + 1, nw / 2 + 20);
                        if (ev.a > 0) need(gap, n, ev.a - 1, ev.a, nw / 2 + 20);
                    }
                }
            }
            for (int k = 0; k < boxes.size; k++) {
                int first = -1;
                int last = -1;
                for (int i = 0; i < n; i++) {
                    if (participants[i].box == k) {
                        if (first < 0) first = i;
                        last = i;
                    }
                }
                if (first >= 0 && last > first) {
                    need(gap, n, first, last, w_of("_bl%d".printf(k)) - head_w[first] / 2 - head_w[last] / 2);
                }
            }
            var xs = new double[int.max(n, 1)];
            for (int j = 0; j < n; j++) {
                xs[j] = j == 0 ? head_w[0] / 2 + 10 : 0;
                for (int i = 0; i < j; i++) {
                    xs[j] = double.max(xs[j], xs[i] + gap[i * n + j]);
                }
            }

            var back = new StringBuilder();    // frame outlines, coloured blocks, boxes
            var mid = new StringBuilder();     // points, bars, labels
            var front = new StringBuilder();   // heads, notes, tabs, titles
            var edges = new StringBuilder();   // lifelines, messages, separators
            open_frames = new Gee.ArrayList<FrameState>();
            ext_min = n > 0 ? xs[0] - head_w[0] / 2 : 0;
            ext_max = n > 0 ? xs[n - 1] + head_w[n - 1] / 2 : 100;

            // ---- 3. rows ----
            double cur = 8;
            double title_y = cur;
            if (size_w.has_key("_title")) {
                cur += h_of("_title") + 12;
            }
            double box_label_h = 0;
            for (int k = 0; k < boxes.size; k++) {
                box_label_h = double.max(box_label_h, h_of("_bl%d".printf(k)));
            }
            double boxes_top = cur;
            if (boxes.size > 0) {
                cur += box_label_h + 10;
            }
            double head_top = cur;
            double head_bottom = head_top + head_row;
            cur = head_bottom + 12;

            var created_pending = new Gee.HashSet<int>();
            var destroyed_pending = new Gee.HashSet<int>();
            var created = new bool[int.max(n, 1)];
            var destroyed = new bool[int.max(n, 1)];
            var life_start = new double[int.max(n, 1)];
            var life_end = new double[int.max(n, 1)];
            for (int i = 0; i < n; i++) {
                life_start[i] = head_bottom;
            }
            var bars = new Gee.ArrayList<Gee.ArrayList<double?>>();
            for (int i = 0; i < n; i++) {
                bars.add(new Gee.ArrayList<double?>());
            }
            int bar_count = 0;
            double last_msg_y = -1;

            for (int e = 0; e < events.size; e++) {
                var ev = events[e];
                switch (ev.kind) {
                    case SeqLayKind.CREATE:
                        if (ev.a >= 0) {
                            created_pending.add(ev.a);
                            created[ev.a] = true;
                        }
                        break;
                    case SeqLayKind.DESTROY:
                        if (ev.a >= 0) {
                            destroyed_pending.add(ev.a);
                        }
                        break;
                    case SeqLayKind.ACTIVATE:
                        if (ev.a >= 0) {
                            bars[ev.a].add(last_msg_y >= 0 ? last_msg_y : cur);
                        }
                        break;
                    case SeqLayKind.DEACTIVATE:
                        if (ev.a >= 0 && bars[ev.a].size > 0) {
                            double ys = (double) bars[ev.a].remove_at(bars[ev.a].size - 1);
                            double ye = double.max(last_msg_y, ys + 12);
                            if (zen) {
                                ye = double.max(ye, cur - 4);
                                cur = double.max(cur, ye + 6);
                            }
                            emit_bar(mid, bar_count++, xs[ev.a], bars[ev.a].size + 1, ys, ye, bar_fill, line_color);
                            extend(xs[ev.a] - BAR_HALF, xs[ev.a] + bars[ev.a].size * BAR_HALF + BAR_HALF);
                        }
                        break;
                    case SeqLayKind.MESSAGE: {
                        if (ev.a < 0 || ev.b < 0) {
                            break;
                        }
                        string lid = "_l%d".printf(e);
                        double lw = w_of(lid);
                        double lh = h_of(lid);
                        // ZenUML draws a "// ..." comment in grey above its message
                        string cmid = "_cm%d".printf(e);
                        double cmw = w_of(cmid);
                        double cmh = h_of(cmid);
                        double cm_y = 0;
                        if (cmh > 0) {
                            cur += 2;
                            cm_y = cur + cmh / 2;
                            cur += cmh;
                        }
                        bool make_a = created_pending.contains(ev.a) && ev.a != ev.b;
                        bool make_b = created_pending.contains(ev.b) && ev.a != ev.b;
                        bool kill_a = destroyed_pending.contains(ev.a) && ev.a != ev.b;
                        bool kill_b = destroyed_pending.contains(ev.b) && ev.a != ev.b;
                        cur += lh > 0 ? lh + 2 : 8;
                        if (make_a || make_b || kill_a || kill_b) {
                            cur += head_row / 2 - 6;
                        }
                        double y = cur;
                        string style = ev.dotted ? "dashed" : "solid";

                        if (ev.a == ev.b) {
                            if (ev.activate_target) {
                                bars[ev.a].add(y + SELF_H);
                            }
                            double px = xs[ev.a];
                            int lvl = bars[ev.a].size - (ev.activate_target ? 1 : 0);
                            double x0 = bar_edge(px, lvl, true);
                            double x1 = x0 + SELF_W;
                            double x2 = bar_edge(px, bars[ev.a].size, true);
                            string p0 = "_p%da".printf(e);
                            string p1 = "_p%db".printf(e);
                            string p2 = "_p%dc".printf(e);
                            string p3 = "_p%dd".printf(e);
                            point(mid, p0, x0, y);
                            point(mid, p1, x1, y);
                            point(mid, p2, x1, y + SELF_H);
                            point(mid, p3, x2, y + SELF_H);
                            edges.append("  %s -> %s [style=%s, arrowhead=none, color=\"%s\"];\n".printf(p0, p1, style, line_color));
                            edges.append("  %s -> %s [style=%s, arrowhead=none, color=\"%s\"];\n".printf(p1, p2, style, line_color));
                            message_edge(edges, mid, p2, p3, e, ev, x3_dir(x1, x2), x2, y + SELF_H, style, line_color);
                            if (lh > 0) {
                                front.append("  %s [%s, %s];\n".printf(label_node_id(ev, lid), measure_attr(lid),
                                                                       pos(x0 + 4 + lw / 2, y - lh / 2 - 1)));
                            }
                            number_mark(front, e, ev, x0, y, palette);
                            if (cmh > 0) {
                                front.append("  %s [%s, %s];\n".printf(cmid, measure_attr(cmid), pos(x0 + cmw / 2, cm_y)));
                                extend(x0, x0 + cmw);
                            }
                            extend(px - BAR_HALF, double.max(x1, x0 + 4 + lw) + 4);
                            if (ev.deactivate_source && bars[ev.a].size > 0) {
                                double ys = (double) bars[ev.a].remove_at(bars[ev.a].size - 1);
                                emit_bar(mid, bar_count++, px, bars[ev.a].size + 1, ys, y + SELF_H, bar_fill, line_color);
                            }
                            last_msg_y = y + SELF_H;
                            cur = y + SELF_H + 10;
                            break;
                        }

                        double xa = xs[ev.a];
                        double xb = xs[ev.b];
                        bool right = xb > xa;
                        if (ev.activate_target) {
                            bars[ev.b].add(y);
                        }
                        double sx = bar_edge(xa, bars[ev.a].size, right);
                        double tx = bar_edge(xb, bars[ev.b].size, !right);
                        if (make_a || kill_a) {
                            sx = xa + (right ? head_w[ev.a] / 2 : -head_w[ev.a] / 2);
                        }
                        if (make_b || kill_b) {
                            tx = xb + (right ? -head_w[ev.b] / 2 : head_w[ev.b] / 2);
                        }
                        string pa = "_p%da".printf(e);
                        string pb = "_p%db".printf(e);
                        point(mid, pa, sx, y);
                        point(mid, pb, tx, y);
                        message_edge(edges, mid, pa, pb, e, ev, right ? 1 : -1, tx, y, style, line_color);
                        if (lh > 0) {
                            front.append("  %s [%s, %s];\n".printf(label_node_id(ev, lid), measure_attr(lid),
                                                                   pos((sx + tx) / 2, y - lh / 2 - 1)));
                        }
                        number_mark(front, e, ev, sx, y, palette);
                        if (cmh > 0) {
                            double cm_left = double.min(sx, tx);
                            front.append("  %s [%s, %s];\n".printf(cmid, measure_attr(cmid), pos(cm_left + cmw / 2, cm_y)));
                            extend(cm_left, cm_left + cmw);
                        }
                        double lo = double.min(sx, tx);
                        double hi = double.max(sx, tx);
                        extend(double.min(lo - BAR_HALF, (sx + tx) / 2 - lw / 2), double.max(hi + BAR_HALF, (sx + tx) / 2 + lw / 2));
                        if (ev.deactivate_source && bars[ev.a].size > 0) {
                            double ys = (double) bars[ev.a].remove_at(bars[ev.a].size - 1);
                            emit_bar(mid, bar_count++, xa, bars[ev.a].size + 1, ys, y, bar_fill, line_color);
                        }
                        int[] ends = { ev.a, ev.b };
                        foreach (int idx in ends) {
                            bool mk = idx == ev.a ? make_a : make_b;
                            bool kl = idx == ev.a ? kill_a : kill_b;
                            if (mk) {
                                created_pending.remove(idx);
                                emit_head(front, idx, participants[idx].node_id, xs[idx], y, head_attrs[idx]);
                                life_start[idx] = y + head_h[idx] / 2;
                            }
                            if (kl) {
                                destroyed_pending.remove(idx);
                                destroyed[idx] = true;
                                emit_head(front, idx, participants[idx].foot_id, xs[idx], y, head_attrs[idx]);
                                life_end[idx] = y - head_h[idx] / 2;
                            }
                        }
                        last_msg_y = y;
                        cur = y + 12;
                        if (make_a || make_b || kill_a || kill_b) {
                            cur = y + head_row / 2 + 10;
                        }
                        break;
                    }
                    case SeqLayKind.NOTE: {
                        if (ev.a < 0) {
                            break;
                        }
                        string nid = "_n%d".printf(e);
                        double w = w_of(nid);
                        double h = h_of(nid);
                        cur += 6;
                        double top = cur;
                        double left;
                        bool fixed = false;
                        double xa = xs[ev.a];
                        if (ev.note_side > 0) {
                            left = bar_edge(xa, bars[ev.a].size, true) + 6;
                        } else if (ev.note_side < 0) {
                            left = bar_edge(xa, bars[ev.a].size, false) - 6 - w;
                        } else if (ev.b >= 0 && ev.b != ev.a) {
                            double lo = double.min(xa, xs[ev.b]) - 20;
                            double hi = double.max(xa, xs[ev.b]) + 20;
                            if (w < hi - lo) {
                                w = hi - lo;
                                fixed = true;
                                left = lo;
                            } else {
                                left = (lo + hi) / 2 - w / 2;
                            }
                        } else {
                            left = xa - w / 2;
                        }
                        string attrs = measure_attr(nid);
                        if (fixed) {
                            attrs += ", fixedsize=true, width=%s, height=%s".printf(inch(w), inch(h));
                        }
                        string note_id = ev.node_id ?? "note_%d".printf(e);
                        front.append("  %s [%s, %s];\n".printf(note_id, attrs, pos(left + w / 2, top + h / 2)));
                        extend(left, left + w);
                        cur = top + h + 6;
                        break;
                    }
                    case SeqLayKind.FRAME_START: {
                        cur += 8;
                        var st = new FrameState();
                        st.ev = ev;
                        st.index = e;
                        st.top = cur;
                        open_frames.add(st);
                        if (ev.fill != null) {
                            cur += 6;
                        } else {
                            double tab_h = h_of("_ft%d".printf(e));
                            double cond_h = h_of("_fc%d".printf(e));
                            if (zen) {
                                cur += tab_h + 4 + (cond_h > 0 ? cond_h + 4 : 0);
                            } else {
                                cur += double.max(tab_h, cond_h) + 6;
                            }
                        }
                        break;
                    }
                    case SeqLayKind.FRAME_SECTION: {
                        if (open_frames.size == 0) {
                            break;
                        }
                        var st = open_frames[open_frames.size - 1];
                        cur += 6;
                        st.section_y.add(cur);
                        st.section_ev.add(e);
                        cur += h_of("_fc%d".printf(e)) + 6;
                        break;
                    }
                    case SeqLayKind.FRAME_END: {
                        if (open_frames.size == 0) {
                            break;
                        }
                        cur += 6;
                        var st = open_frames[open_frames.size - 1];
                        close_frame(back, front, edges, st, cur, xs, head_w, n, frame_color, text_color, palette);
                        cur += 4;
                        break;
                    }
                }
            }
            // unclosed frames (a parse error elsewhere): close them at the bottom
            while (open_frames.size > 0) {
                cur += 6;
                close_frame(back, front, edges, open_frames[open_frames.size - 1], cur, xs, head_w, n,
                            frame_color, text_color, palette);
            }
            // participants created but never messaged appear here
            foreach (int idx in created_pending) {
                cur += head_h[idx] / 2 + 4;
                emit_head(front, idx, participants[idx].node_id, xs[idx], cur, head_attrs[idx]);
                life_start[idx] = cur + head_h[idx] / 2;
                cur += head_h[idx] / 2 + 8;
            }
            cur += 10;
            // Mermaid draws no bar for an activation that is never closed; ZenUML closes its own
            for (int i = 0; zen && i < n; i++) {
                while (bars[i].size > 0) {
                    double ys = (double) bars[i].remove_at(bars[i].size - 1);
                    emit_bar(mid, bar_count++, xs[i], bars[i].size + 1, ys, double.max(ys + 12, cur - 6), bar_fill, line_color);
                }
            }
            double foot_top = cur;
            double foot_bottom = foot_top;
            for (int i = 0; i < n; i++) {
                var p = participants[i];
                if (!created[i]) {
                    emit_head(front, i, p.node_id, xs[i], head_bottom - head_h[i] / 2, head_attrs[i]);
                }
                double end_y;
                if (destroyed[i]) {
                    end_y = life_end[i];
                } else if (zen) {
                    end_y = foot_top;
                } else {
                    emit_head(front, i, p.foot_id, xs[i], foot_top + head_h[i] / 2, head_attrs[i]);
                    end_y = foot_top;
                    foot_bottom = double.max(foot_bottom, foot_top + head_h[i]);
                }
                if (end_y > life_start[i]) {
                    string la = "_life%da".printf(i);
                    string lb = "_life%db".printf(i);
                    point(mid, la, xs[i], life_start[i]);
                    point(mid, lb, xs[i], end_y);
                    edges.append("  %s -> %s [arrowhead=none, style=%s, color=\"%s\", penwidth=%s];\n".printf(
                        la, lb, zen ? "dashed" : "solid", zen ? palette.grid : line_color, zen ? "1" : "1.2"));
                }
            }

            // participant boxes: behind the heads, from the box label to the feet
            for (int k = 0; k < boxes.size; k++) {
                double lo = double.MAX;
                double hi = -double.MAX;
                for (int i = 0; i < n; i++) {
                    if (participants[i].box == k) {
                        lo = double.min(lo, xs[i] - head_w[i] / 2);
                        hi = double.max(hi, xs[i] + head_w[i] / 2);
                    }
                }
                if (lo > hi) {
                    continue;
                }
                lo -= 10;
                hi += 10;
                double lw = w_of("_bl%d".printf(k));
                if (hi - lo < lw + 16) {
                    double c = (lo + hi) / 2;
                    lo = c - lw / 2 - 8;
                    hi = c + lw / 2 + 8;
                }
                double top = boxes_top;
                double bottom = foot_bottom + 8;
                string? bfill = boxes[k].fill != null ? color_value(boxes[k].fill) : null;
                back.append("  _bg_box%d [shape=rect, fixedsize=true, label=\"\", style=\"%s\", fillcolor=\"%s\", color=\"%s\", penwidth=1, width=%s, height=%s, %s];\n".printf(
                    k, bfill != null ? "filled" : "solid", bfill ?? "none", head_border, inch(hi - lo), inch(bottom - top),
                    pos((lo + hi) / 2, (top + bottom) / 2)));
                if (size_w.has_key("_bl%d".printf(k))) {
                    front.append("  _bl%d [%s, %s];\n".printf(k, measure_attr("_bl%d".printf(k)),
                                                             pos((lo + hi) / 2, top + 4 + h_of("_bl%d".printf(k)) / 2)));
                }
                extend(lo, hi);
            }
            if (size_w.has_key("_title")) {
                double tw = w_of("_title");
                double tx = zen ? ext_min + tw / 2 : (ext_min + ext_max) / 2;
                front.append("  _title [%s, %s];\n".printf(measure_attr("_title"), pos(tx, title_y + h_of("_title") / 2)));
            }

            var sb = new StringBuilder();
            sb.append("digraph G {\n");
            sb.append("  // Positions are fixed here (layout=nop2): Graphviz draws, it does not place\n");
            sb.append("  layout=nop2;\n");
            sb.append("  splines=line;\n");
            sb.append("  outputorder=edgesfirst;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg));
            sb.append("  pad=0.15;\n");
            sb.append("  node [fontname=\"Sans\", style=\"filled\"];\n");
            // unclipped: lines and arrow tips end exactly on their points (lifelines, bar edges)
            sb.append("  edge [fontsize=10, fontname=\"Sans\", color=\"%s\", headclip=false, tailclip=false];\n".printf(line_color));
            sb.append("\n  // Boxes, coloured blocks and frames\n");
            sb.append(back.str);
            sb.append("\n  // Points, activations\n");
            sb.append(mid.str);
            sb.append("\n  // Participants, labels, notes, frame tabs, title\n");
            sb.append(front.str);
            sb.append("\n  // Lifelines, messages, separators\n");
            sb.append(edges.str);
            sb.append("}\n");
            return sb.str;
        }

        private static int x3_dir(double from_x, double to_x) {
            return to_x > from_x ? 1 : -1;
        }

        private static string label_node_id(SeqLayEvent ev, string fallback) {
            return ev.node_id ?? fallback;
        }

        private void message_edge(StringBuilder edges, StringBuilder mid, string from, string to, int e,
                                  SeqLayEvent ev, int dir, double end_x, double y, string style, string color) {
            string head;
            string extra = "";
            switch (ev.head) {
                case SeqLayHead.NONE:
                case SeqLayHead.CROSS:
                case SeqLayHead.OPEN:
                    head = "none";
                    break;
                case SeqLayHead.BOTH:
                    head = "normal";
                    extra = ", dir=both, arrowtail=normal, arrowsize=0.8";
                    break;
                default:
                    head = zen && ev.dotted ? "vee" : "normal";
                    extra = ", arrowsize=0.8";
                    break;
            }
            edges.append("  %s -> %s [style=%s, arrowhead=%s, color=\"%s\", penwidth=1.2%s];\n".printf(
                from, to, style, head, color, extra));
            if (ev.head == SeqLayHead.CROSS) {
                double cx = end_x - dir * 5;
                for (int k = 0; k < 2; k++) {
                    string a = "_x%d_%da".printf(e, k);
                    string b = "_x%d_%db".printf(e, k);
                    point(mid, a, cx - 4, y + (k == 0 ? -4 : 4));
                    point(mid, b, cx + 4, y + (k == 0 ? 4 : -4));
                    edges.append("  %s -> %s [arrowhead=none, color=\"%s\", penwidth=1.8];\n".printf(a, b, color));
                }
            } else if (ev.head == SeqLayHead.OPEN) {
                // async: an open chevron of two strokes, not a filled head
                for (int k = 0; k < 2; k++) {
                    string a = "_o%d_%da".printf(e, k);
                    string b = "_o%d_%db".printf(e, k);
                    point(mid, a, end_x - dir * 9, y + (k == 0 ? -6 : 6));
                    point(mid, b, end_x, y);
                    edges.append("  %s -> %s [arrowhead=none, color=\"%s\", penwidth=1.6];\n".printf(a, b, color));
                }
            }
        }

        private static bool dark_canvas() {
            return RenderUtils.contrast_text(ThemeManager.get_active_palette().background) == "#FFFFFF";
        }

        // Autonumber: a filled circle on the arrow's start (Mermaid) or "1.1" before it (ZenUML)
        private void number_mark(StringBuilder front, int e, SeqLayEvent ev, double x, double y, Palette palette) {
            if (ev.number == null) {
                return;
            }
            if (zen) {
                string id = "_num%d".printf(e);
                double w = w_of(id);
                front.append("  %s [%s, %s];\n".printf(id, measure_attr(id), pos(x - 4 - w / 2, y - h_of(id) / 2 - 1)));
                extend(x - 4 - w, x);
                return;
            }
            string fill = palette.edge_color;
            front.append("  _num%d [shape=circle, fixedsize=true, width=0.22, height=0.22, style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", fontsize=8, label=\"%s\", %s];\n".printf(
                e, fill, fill, RenderUtils.contrast_text(fill), RenderUtils.escape_label(ev.number), pos(x, y)));
            extend(x - 8, x + 8);
        }

        private void emit_head(StringBuilder front, int i, string id, double x, double cy, string attrs) {
            front.append("  %s [%s, %s];\n".printf(id, attrs, pos(x, cy)));
            extend(x - w_of("_h%d".printf(i)) / 2, x + w_of("_h%d".printf(i)) / 2);
        }

        private void close_frame(StringBuilder back, StringBuilder front, StringBuilder edges, FrameState st,
                                 double bottom, double[] xs, double[] head_w, int n, string frame_color,
                                 string text_color, Palette palette) {
            open_frames.remove(st);
            int e = st.index;
            double left;
            double right;
            if (st.min_x > st.max_x) {
                left = n > 0 ? xs[0] - head_w[0] / 2 : 0;
                right = n > 0 ? xs[n - 1] + head_w[n - 1] / 2 : 80;
            } else {
                left = st.min_x - 10;
                right = st.max_x + 10;
            }
            string tab_id = "_ft%d".printf(e);
            string cond_id = "_fc%d".printf(e);
            double tab_w = w_of(tab_id);
            double tab_h = h_of(tab_id);
            double need_w = zen ? double.max(tab_w, w_of(cond_id)) + 16 : tab_w + w_of(cond_id) * 2 / 2 + 30;
            foreach (int se in st.section_ev) {
                need_w = double.max(need_w, w_of("_fc%d".printf(se)) + 20);
            }
            if (right - left < need_w) {
                double c = (left + right) / 2;
                left = double.min(left, c - need_w / 2);
                right = left + double.max(need_w, right - left);
            }
            double width = right - left;
            double height = bottom - st.top;
            if (st.ev.fill != null) {
                string fill = color_value(st.ev.fill);
                back.append("  _bg_rect%d [shape=rect, fixedsize=true, label=\"\", style=filled, penwidth=0, fillcolor=\"%s\", color=\"%s\", width=%s, height=%s, %s];\n".printf(
                    e, fill, fill, inch(width), inch(height), pos(left + width / 2, st.top + height / 2)));
                extend(left, right);
                return;
            }
            back.append("  _frame%d [shape=rect, fixedsize=true, label=\"\", style=\"%s\", color=\"%s\", penwidth=1.2, width=%s, height=%s, %s];\n".printf(
                e, zen ? "solid" : "dashed", frame_color, inch(width), inch(height), pos(left + width / 2, st.top + height / 2)));
            if (zen) {
                double band_h = tab_h + 4;
                back.append("  _bg_band%d [shape=rect, fixedsize=true, label=\"\", style=filled, penwidth=0, fillcolor=\"%s\", width=%s, height=%s, %s];\n".printf(
                    e, palette.grid, inch(width - 2), inch(band_h), pos(left + width / 2, st.top + 1 + band_h / 2)));
                front.append("  %s [%s, %s];\n".printf(tab_id, measure_attr(tab_id),
                    pos(left + 8 + tab_w / 2, st.top + 2 + tab_h / 2)));
                if (size_w.has_key(cond_id)) {
                    front.append("  %s [%s, %s];\n".printf(cond_id, measure_attr(cond_id),
                        pos(left + 10 + w_of(cond_id) / 2, st.top + band_h + 2 + h_of(cond_id) / 2)));
                }
            } else {
                front.append("  %s [%s, %s];\n".printf(tab_id, measure_attr(tab_id), pos(left + tab_w / 2, st.top + tab_h / 2)));
                if (size_w.has_key(cond_id)) {
                    double cx = double.max((left + right) / 2, left + tab_w + 8 + w_of(cond_id) / 2);
                    front.append("  %s [%s, %s];\n".printf(cond_id, measure_attr(cond_id),
                        pos(cx, st.top + double.max(tab_h, h_of(cond_id)) / 2 + 1)));
                }
            }
            for (int k = 0; k < st.section_y.size; k++) {
                double y = (double) st.section_y[k];
                int se = st.section_ev[k];
                string a = "_sep%da".printf(se);
                string b = "_sep%db".printf(se);
                point(back, a, left, y);
                point(back, b, right, y);
                edges.append("  %s -> %s [style=dashed, arrowhead=none, color=\"%s\", penwidth=1];\n".printf(a, b, frame_color));
                string cid = "_fc%d".printf(se);
                if (size_w.has_key(cid)) {
                    double cx = zen ? left + 6 + w_of(cid) / 2 : (left + right) / 2;
                    front.append("  %s [%s, %s];\n".printf(cid, measure_attr(cid), pos(cx, y + 3 + h_of(cid) / 2)));
                }
            }
            extend(left, right);
        }

        private void emit_bar(StringBuilder sb, int index, double x, int level, double ys, double ye,
                              string fill, string border) {
            double bottom = double.max(ye, ys + 8);
            sb.append("  _act%d [shape=rect, style=filled, fixedsize=true, label=\"\", fillcolor=\"%s\", color=\"%s\", width=%s, height=%s, %s];\n".printf(
                index, fill, border, inch(BAR_HALF * 2), inch(bottom - ys),
                pos(x + (level - 1) * BAR_HALF, (ys + bottom) / 2)));
        }

        // Where an arrow meets a lifeline with `level` open activation bars
        private static double bar_edge(double x, int level, bool toward_right) {
            if (level <= 0) {
                return x;
            }
            return toward_right ? x + level * BAR_HALF : x + (level - 2) * BAR_HALF;
        }

        private void extend(double a, double b) {
            ext_min = double.min(ext_min, a);
            ext_max = double.max(ext_max, b);
            foreach (var st in open_frames) {
                st.min_x = double.min(st.min_x, a);
                st.max_x = double.max(st.max_x, b);
            }
        }

        private static void need(double[] gap, int n, int a, int b, double d) {
            if (a > b) {
                int t = a;
                a = b;
                b = t;
            }
            if (a == b || a < 0 || b >= n) {
                return;
            }
            gap[a * n + b] = double.max(gap[a * n + b], d);
        }

        // ---------------------------------------------------------------- nodes

        private string participant_attrs(SeqLayParticipant p, string fill, string border) {
            string font = RenderUtils.contrast_text(fill);
            string esc_html = Markup.escape_text(p.label).replace("\n", "<BR/>");
            switch (p.kind) {
                case "actor":
                    if (!zen) {
                        return RenderUtils.actor_figure_attrs(null, esc_html, fill, border, "",
                                                              ThemeManager.get_active_palette().node_text) + ", fontsize=12";
                    }
                    break;
                case "database":
                    if (!zen) {
                        return "shape=cylinder, style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", fontsize=12, margin=\"0.15,0.1\", height=0.6, label=\"%s\"".printf(
                            fill, border, font, RenderUtils.escape_label(p.label));
                    }
                    break;
                default:
                    break;
            }
            string? icon = icon_for(p.kind);
            if (zen) {
                string icon_cell = "";
                if (icon != null) {
                    icon_cell = "<TD FIXEDSIZE=\"TRUE\" WIDTH=\"22\" HEIGHT=\"24\" BGCOLOR=\"#01F3%02X\"> </TD>".printf(icon_marks.size);
                    icon_marks.add("%s|%s".printf(icon, font));
                }
                string name_cell = p.label.length > 0 ? "<TD>%s</TD>".printf(esc_html) : "";
                if (icon_cell.length == 0 && name_cell.length == 0) {
                    name_cell = "<TD> </TD>";
                }
                // "@<<service>> Ext": ZenUML draws «service» over the name
                string stereo_row = "";
                if (p.stereotype != null && p.stereotype.length > 0) {
                    stereo_row = "<TR><TD COLSPAN=\"2\"><FONT POINT-SIZE=\"11\">«%s»</FONT></TD></TR>".printf(
                        Markup.escape_text(p.stereotype));
                }
                // ZenUML draws @Collections / @Queue as a plain box, like every other head
                string zperiph = "";
                return "shape=box, style=\"rounded,filled\", fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", penwidth=1.5, fontsize=13, margin=\"0.12,0.06\", height=0.45%s, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"2\" CELLPADDING=\"1\">%s<TR>%s%s</TR></TABLE>>".printf(
                    fill, border, font, zperiph, stereo_row, icon_cell, name_cell);
            }
            if (icon != null) {
                // Mermaid boundary / control / entity: the icon over the name
                string cell = "<TD FIXEDSIZE=\"TRUE\" WIDTH=\"34\" HEIGHT=\"30\" BGCOLOR=\"#01F3%02X\"> </TD>".printf(icon_marks.size);
                icon_marks.add("%s|%s".printf(icon, border));
                return "shape=plaintext, style=solid, fontcolor=\"%s\", fontsize=12, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"1\"><TR><TD>%s</TD></TR><TR><TD>%s</TD></TR></TABLE>>".printf(
                    ThemeManager.get_active_palette().node_text, cell, esc_html);
            }
            string periph = p.kind == "collections" ? ", peripheries=2" : "";
            return "shape=box, style=\"rounded,filled\", fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", penwidth=1.2, fontsize=12, margin=\"0.15,0.08\", width=1.0, height=0.5, label=\"%s\"%s".printf(
                fill, border, font, RenderUtils.escape_label(p.label), periph);
        }

        private string? icon_for(string kind) {
            switch (kind) {
                case "boundary":
                case "control":
                case "entity":
                    return kind;
                case "actor":
                case "starter":
                    return zen ? "actor" : null;
                case "database":
                    return zen ? "database" : null;
                default:
                    return null;
            }
        }

        // The same colour at 60% opacity: Graphviz takes "#RRGGBBAA"
        private static string muted(string color) {
            return color.length == 7 && color.has_prefix("#") ? color + "99" : color;
        }

        private static string text_attrs(string text, int fontsize, string color) {
            return "shape=plaintext, style=solid, fontsize=%d, fontcolor=\"%s\", margin=\"0.02,0.01\", width=0, height=0, label=\"%s\"".printf(
                fontsize, color, RenderUtils.escape_label(text));
        }

        /**
         * A Mermaid colour as Graphviz takes it: "rgb(200, 220, 255)" -> "#C8DCFF",
         * "rgba(0,0,255,0.1)" -> "#0000FF1A", "#abc" -> "#AABBCC", "Aqua" -> "aqua".
         */
        public static string color_value(string color) {
            string c = color.strip();
            string low = c.down();
            if (low.has_prefix("rgb")) {
                int open = c.index_of("(");
                int close = c.last_index_of(")");
                if (open > 0 && close > open) {
                    string[] parts = c.substring(open + 1, close - open - 1).replace("/", ",").split(",");
                    if (parts.length >= 3) {
                        int r = channel(parts[0]);
                        int g = channel(parts[1]);
                        int b = channel(parts[2]);
                        if (parts.length >= 4) {
                            double a = double.parse(parts[3].strip().replace("%", ""));
                            if (parts[3].contains("%")) {
                                a /= 100.0;
                            }
                            int ai = (int) Math.round(double.min(1.0, double.max(0.0, a)) * 255);
                            return "#%02X%02X%02X%02X".printf(r, g, b, ai);
                        }
                        return "#%02X%02X%02X".printf(r, g, b);
                    }
                }
                return "none";
            }
            if (c.has_prefix("#")) {
                string h = c.substring(1);
                bool hex = h.length > 0;
                for (int k = 0; k < h.length; k++) {
                    if (!h[k].isxdigit()) {
                        hex = false;
                        break;
                    }
                }
                if (hex && (h.length == 3 || h.length == 4)) {
                    var sb = new StringBuilder("#");
                    for (int k = 0; k < h.length; k++) {
                        sb.append_c(h[k]);
                        sb.append_c(h[k]);
                    }
                    return sb.str.up();
                }
                return hex ? c : RenderUtils.sanitize_color(c);
            }
            if (low == "transparent") {
                return "none";
            }
            return low;
        }

        private static int channel(string s) {
            string t = s.strip();
            double v = double.parse(t.replace("%", ""));
            if (t.has_suffix("%")) {
                v = v * 255.0 / 100.0;
            }
            return (int) Math.round(double.min(255, double.max(0, v)));
        }

        // ---------------------------------------------------------------- measuring

        private void want(string id, string attrs) {
            measure_ids.add(id);
            measure_attrs.add(attrs);
        }

        private string measure_attr(string id) {
            int i = measure_ids.index_of(id);
            return i >= 0 ? measure_attrs[i] : "label=\"\", shape=point, style=invis";
        }

        private double w_of(string id) {
            return size_w.has_key(id) ? (double) size_w.get(id) : 0;
        }

        private double h_of(string id) {
            return size_h.has_key(id) ? (double) size_h.get(id) : 0;
        }

        // Sizes every wanted node with one throwaway Graphviz layout ("plain" output)
        private void measure_all(Gvc.Context context) {
            size_w.clear();
            size_h.clear();
            if (measure_ids.size == 0) {
                return;
            }
            var sb = new StringBuilder("digraph measure {\n  node [fontname=\"Sans\", style=\"filled\"];\n");
            for (int i = 0; i < measure_ids.size; i++) {
                sb.append("  _q%d [%s];\n".printf(i, measure_attrs[i]));
            }
            sb.append("}\n");
            var graph = RenderUtils.read_dot(sb.str);
            if (graph != null && context.layout(graph, "dot") == 0) {
                uint8[] data;
                if (RenderUtils.render_data(context, graph, "plain", out data) == 0) {
                    var text = new StringBuilder.sized(data.length + 1);
                    text.append_len((string) data, data.length);
                    foreach (string line in text.str.split("\n")) {
                        string[] f = line.split(" ");
                        if (f.length >= 6 && f[0] == "node" && f[1].has_prefix("_q")) {
                            int idx = int.parse(f[1].substring(2));
                            if (idx >= 0 && idx < measure_ids.size) {
                                size_w.set(measure_ids[idx], double.parse(f[4]) * 72.0);
                                size_h.set(measure_ids[idx], double.parse(f[5]) * 72.0);
                            }
                        }
                    }
                }
                context.free_layout(graph);
            }
            for (int i = 0; i < measure_ids.size; i++) {
                if (!size_w.has_key(measure_ids[i])) {
                    size_w.set(measure_ids[i], 80.0);
                    size_h.set(measure_ids[i], 24.0);
                }
            }
        }

        private static string num(double v, string fmt = "%.2f") {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, fmt);
        }

        // Fixed position; y grows downwards in the layout, upwards in Graphviz
        private static string pos(double x, double y) {
            return "pos=\"%s,%s!\"".printf(num(x), num(-y));
        }

        private static string inch(double points) {
            return num(points / 72.0, "%.4f");
        }

        private static void point(StringBuilder sb, string id, double x, double y) {
            sb.append("  %s [label=\"\", shape=point, width=0.01, height=0.01, style=invis, %s];\n".printf(id, pos(x, y)));
        }

        // ---------------------------------------------------------------- SVG

        public uint8[]? render_svg(Gvc.Context context) {
            string dot = generate_dot(context);
            var graph = RenderUtils.read_dot(dot);
            if (graph == null) {
                warning("Failed to parse sequence DOT");
                return null;
            }
            if (context.layout(graph, "nop2") != 0) {
                warning("Failed to lay out sequence graph");
                return null;
            }
            uint8[] svg_data;
            int ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
            context.free_layout(graph);
            if (ret != 0) {
                warning("Failed to render sequence graph");
                return null;
            }
            return postprocess(RenderUtils.draw_actor_figures(svg_data));
        }

        private static string f(double v) {
            return num(v, "%.2f");
        }

        /**
         * Coloured "rect" blocks and participant boxes are moved behind everything (they are
         * nodes, which Graphviz draws after the edges), and the icon placeholders become
         * boundary / control / entity / actor / database icons.
         */
        private uint8[] postprocess(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            try {
                var bg_nodes = new Regex("<g id=\"node[0-9]+\" class=\"node\">\\s*<title>_bg_[^<]*</title>(?:(?!</g>).)*</g>\\s*",
                                         RegexCompileFlags.DOTALL);
                var moved = new StringBuilder();
                svg = bg_nodes.replace_eval(svg, -1, 0, 0, (m, result) => {
                    moved.append(m.fetch(0));
                    return false;
                });
                if (moved.len > 0) {
                    if (dark_canvas()) {
                        // explicit light fills ("box #e1f5fe", "rect rgb(...)") are tinted on a dark
                        // canvas, or the theme's light text over them would be unreadable.
                        // A fill with an alpha channel already carries its own fill-opacity from
                        // Graphviz: multiply into it instead of writing a second attribute, which
                        // would be invalid XML and make librsvg reject the whole document.
                        // A fill that already carries an alpha channel keeps the author's own
                        // opacity: Graphviz then writes fill-opacity itself, and adding a second
                        // attribute would be invalid XML that librsvg rejects outright.
                        var poly_fill = new Regex("<polygon fill=\"([^\"]*)\"(\\s+fill-opacity=)?");
                        string tinted = poly_fill.replace_eval(moved.str, -1, 0, 0, (m, result) => {
                            string? had = m.fetch(2);
                            if (had != null && had != "") {
                                result.append(m.fetch(0));
                            } else {
                                result.append("<polygon fill-opacity=\"0.22\" fill=\"%s\"".printf(m.fetch(1)));
                            }
                            return false;
                        });
                        moved.truncate();
                        moved.append(tinted);
                    }
                    var canvas = new Regex("(<g id=\"graph0\" class=\"graph\"[^>]*>\\s*<title>[^<]*</title>\\s*<polygon[^>]*/>\\s*)");
                    string block = moved.str;
                    svg = canvas.replace_eval(svg, -1, 0, 0, (m, result) => {
                        result.append(m.fetch(1));
                        result.append(block);
                        return false;
                    });
                }

                // Graphviz asks Pango for "Sans Bold" and writes that name straight
                // into the SVG; librsvg (and browsers) look for a family of that name,
                // find none and fall back to a regular face. The weight has to be its
                // own attribute for the text to come out bold.
                var bold_font = new Regex("font-family=\"([^\"]*?) Bold\"");
                svg = bold_font.replace(svg, -1, 0, "font-family=\"\\1\" font-weight=\"bold\"");

                var sentinel = new Regex("<polygon fill=\"#01[Ff]3([0-9A-Fa-f]{2})\" stroke=\"[^\"]*\" points=\"([^\"]*)\"/>");
                svg = sentinel.replace_eval(svg, -1, 0, 0, (m, result) => {
                    int idx = (int) int64.parse("0x" + m.fetch(1));
                    double[]? b = points_box(m.fetch(2));
                    if (b == null || idx >= icon_marks.size) {
                        return false;
                    }
                    string[] parts = icon_marks[idx].split("|");
                    result.append(icon_svg(parts[0], parts.length > 1 ? parts[1] : "#333333", b));
                    return false;
                });
            } catch (RegexError e) {
                warning("Sequence SVG post-processing: %s", e.message);
                return svg_data;
            }
            return svg.data;
        }

        private static double[]? points_box(string points) {
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            foreach (string pt in points.strip().split(" ")) {
                string[] xy = pt.split(",");
                if (xy.length != 2) {
                    continue;
                }
                double x = double.parse(xy[0]);
                double y = double.parse(xy[1]);
                minx = double.min(minx, x);
                maxx = double.max(maxx, x);
                miny = double.min(miny, y);
                maxy = double.max(maxy, y);
            }
            if (minx > maxx) {
                return null;
            }
            return { minx, miny, maxx, maxy };
        }

        private static string icon_svg(string kind, string stroke_color, double[] b) {
            string stroke = Markup.escape_text(stroke_color);
            double cx = (b[0] + b[2]) / 2;
            double cy = (b[1] + b[3]) / 2;
            double h = b[3] - b[1];
            double r = h * 0.28;
            string paint = "fill=\"none\" stroke=\"%s\" stroke-width=\"1.4\"".printf(stroke);
            switch (kind) {
                case "actor": {
                    double hr = h * 0.14;
                    double hy = b[1] + hr + 1;
                    double neck = hy + hr;
                    double hip = b[1] + h * 0.64;
                    double arm = neck + h * 0.12;
                    return "<circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/><path class=\"gdicon\" %s d=\"M%s,%s L%s,%s M%s,%s L%s,%s M%s,%s L%s,%s L%s,%s\"/>".printf(
                        f(cx), f(hy), f(hr), paint, paint,
                        f(cx), f(neck), f(cx), f(hip),
                        f(cx - h * 0.25), f(arm), f(cx + h * 0.25), f(arm),
                        f(cx - h * 0.22), f(b[3] - 1), f(cx), f(hip), f(cx + h * 0.22), f(b[3] - 1));
                }
                case "boundary": {
                    double ccx = cx + r * 0.5;
                    double bx = ccx - r - r * 0.9;
                    return "<path class=\"gdicon\" %s d=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/><circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/>".printf(
                        paint, f(bx), f(cy - r), f(bx), f(cy + r), f(bx), f(cy), f(ccx - r), f(cy),
                        f(ccx), f(cy), f(r), paint);
                }
                case "control": {
                    double ccy = cy + 1.5;
                    double ty = ccy - r;
                    return "<circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/><path class=\"gdicon\" %s d=\"M%s,%s L%s,%s L%s,%s\"/>".printf(
                        f(cx), f(ccy), f(r), paint, paint,
                        f(cx + 4), f(ty - 4), f(cx), f(ty), f(cx + 4), f(ty + 4));
                }
                case "entity": {
                    double ecy = cy - 2;
                    return "<circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/><path class=\"gdicon\" %s d=\"M%s,%s L%s,%s\"/>".printf(
                        f(cx), f(ecy), f(r), paint, paint, f(cx - r), f(ecy + r + 3), f(cx + r), f(ecy + r + 3));
                }
                default: {
                    // database: a cylinder
                    double w = h * 0.34;
                    double ry = h * 0.1;
                    double top = b[1] + ry + 2;
                    double bottom = b[3] - ry - 2;
                    return "<ellipse class=\"gdicon\" cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\" %s/><path class=\"gdicon\" %s d=\"M%s,%s L%s,%s A%s,%s 0 0 0 %s,%s L%s,%s M%s,%s A%s,%s 0 0 0 %s,%s M%s,%s A%s,%s 0 0 0 %s,%s\"/>".printf(
                        f(cx), f(top), f(w), f(ry), paint, paint,
                        f(cx - w), f(top), f(cx - w), f(bottom), f(w), f(ry), f(cx + w), f(bottom), f(cx + w), f(top),
                        f(cx - w), f(top + (bottom - top) / 3), f(w), f(ry), f(cx + w), f(top + (bottom - top) / 3),
                        f(cx - w), f(top + (bottom - top) * 2 / 3), f(w), f(ry), f(cx + w), f(top + (bottom - top) * 2 / 3));
                }
            }
        }
    }

    // ==================== Mermaid sequence renderer ====================

    public class MermaidSequenceRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidSequenceRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        // Click-region ids: "actor_X" heads, "s_X_N" message labels / foot boxes, which
        // MermaidElementInspector maps back to participant X
        private static string actor_node(MermaidActor a) {
            return "actor_" + RenderUtils.sanitize_id(a.id);
        }

        private MermaidSeqLayout build_layout(MermaidSequenceDiagram diagram) {
            var lay = new MermaidSeqLayout();
            lay.title = diagram.title;
            var index = new Gee.HashMap<MermaidActor, int>();
            int n_msgs = diagram.messages.size;
            foreach (var a in diagram.actors) {
                var p = new SeqLayParticipant(a.get_display_name(), actor_node(a));
                p.foot_id = "s_%s_%d".printf(RenderUtils.sanitize_id(a.id), n_msgs);
                p.kind = a.shape ?? (a.is_participant ? "participant" : "actor");
                p.line = a.source_line;
                p.box = a.box_index;
                index.set(a, lay.participants.size);
                lay.participants.add(p);
            }
            foreach (var box in diagram.boxes) {
                var b = new SeqLayBox();
                b.label = box.label;
                b.fill = box.color;
                lay.boxes.add(b);
            }
            int note_num = 0;
            foreach (var ev in diagram.events) {
                switch (ev.kind) {
                    case MermaidSeqEventKind.MESSAGE: {
                        var msg = ev.message;
                        var le = new SeqLayEvent(SeqLayKind.MESSAGE);
                        le.a = index.get(msg.from);
                        le.b = index.get(msg.to);
                        le.text = msg.text;
                        le.line = msg.source_line;
                        le.activate_target = msg.is_activation;
                        le.deactivate_source = msg.is_deactivation;
                        if (msg.number >= 0) {
                            le.number = msg.number.to_string();
                        }
                        le.node_id = "s_%s_%d".printf(RenderUtils.sanitize_id(msg.from.id), msg.sequence_index);
                        switch (msg.arrow_type) {
                            case MermaidArrowType.DOTTED_ARROW:
                                le.dotted = true;
                                break;
                            case MermaidArrowType.SOLID_LINE:
                                le.head = SeqLayHead.NONE;
                                break;
                            case MermaidArrowType.DOTTED_LINE:
                                le.head = SeqLayHead.NONE;
                                le.dotted = true;
                                break;
                            case MermaidArrowType.SOLID_CROSS:
                                le.head = SeqLayHead.CROSS;
                                break;
                            case MermaidArrowType.DOTTED_CROSS:
                                le.head = SeqLayHead.CROSS;
                                le.dotted = true;
                                break;
                            case MermaidArrowType.SOLID_OPEN:
                                le.head = SeqLayHead.OPEN;
                                break;
                            case MermaidArrowType.DOTTED_OPEN:
                                le.head = SeqLayHead.OPEN;
                                le.dotted = true;
                                break;
                            case MermaidArrowType.SOLID_BIDIRECTIONAL:
                                le.head = SeqLayHead.BOTH;
                                break;
                            case MermaidArrowType.DOTTED_BIDIRECTIONAL:
                                le.head = SeqLayHead.BOTH;
                                le.dotted = true;
                                break;
                            default:
                                break;
                        }
                        lay.events.add(le);
                        break;
                    }
                    case MermaidSeqEventKind.NOTE: {
                        var note = ev.note;
                        if (note.from_actor == null) {
                            break;
                        }
                        var le = new SeqLayEvent(SeqLayKind.NOTE);
                        le.a = index.get(note.from_actor);
                        le.b = note.to_actor != null ? index.get(note.to_actor) : -1;
                        le.note_side = note.is_over ? 0 : (note.is_right ? 1 : -1);
                        le.text = note.text;
                        le.line = note.source_line;
                        le.node_id = "note_%d".printf(note_num++);
                        lay.events.add(le);
                        break;
                    }
                    case MermaidSeqEventKind.BLOCK_START: {
                        var le = new SeqLayEvent(SeqLayKind.FRAME_START);
                        le.frame_label = loop_keyword(ev.loop.loop_type);
                        le.line = ev.source_line;
                        if (ev.loop.loop_type == MermaidLoopType.RECT) {
                            le.fill = ev.loop.color ?? "rgba(128,128,128,0.15)";
                        } else {
                            le.text = ev.loop.condition;
                        }
                        lay.events.add(le);
                        break;
                    }
                    case MermaidSeqEventKind.BLOCK_SECTION: {
                        var le = new SeqLayEvent(SeqLayKind.FRAME_SECTION);
                        le.text = ev.section.condition;
                        le.line = ev.source_line;
                        lay.events.add(le);
                        break;
                    }
                    case MermaidSeqEventKind.BLOCK_END:
                        lay.events.add(new SeqLayEvent(SeqLayKind.FRAME_END));
                        break;
                    case MermaidSeqEventKind.ACTIVATE:
                    case MermaidSeqEventKind.DEACTIVATE:
                    case MermaidSeqEventKind.CREATE:
                    case MermaidSeqEventKind.DESTROY: {
                        SeqLayKind k;
                        switch (ev.kind) {
                            case MermaidSeqEventKind.ACTIVATE: k = SeqLayKind.ACTIVATE; break;
                            case MermaidSeqEventKind.DEACTIVATE: k = SeqLayKind.DEACTIVATE; break;
                            case MermaidSeqEventKind.CREATE: k = SeqLayKind.CREATE; break;
                            default: k = SeqLayKind.DESTROY; break;
                        }
                        var le = new SeqLayEvent(k);
                        le.a = index.get(ev.actor);
                        lay.events.add(le);
                        break;
                    }
                }
            }
            return lay;
        }

        private static string loop_keyword(MermaidLoopType type) {
            switch (type) {
                case MermaidLoopType.ALT:      return "alt";
                case MermaidLoopType.OPT:      return "opt";
                case MermaidLoopType.PAR:      return "par";
                case MermaidLoopType.CRITICAL: return "critical";
                case MermaidLoopType.BREAK:    return "break";
                case MermaidLoopType.RECT:     return "rect";
                default:                       return "loop";
            }
        }

        public string generate_dot(MermaidSequenceDiagram diagram) {
            return build_layout(diagram).generate_dot(context);
        }

        public uint8[]? render_to_svg(MermaidSequenceDiagram diagram) {
            return build_layout(diagram).render_svg(context);
        }

        public Cairo.ImageSurface? render_to_surface(MermaidSequenceDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return null;

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(
                    stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

                var surface = new Cairo.ImageSurface(
                    Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0, y = 0, width = width, height = height
                };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                int n_msgs = diagram.messages.size;
                foreach (var actor in diagram.actors) {
                    if (actor.source_line > 0) {
                        element_lines.set(actor_node(actor), actor.source_line);
                        element_lines.set("s_%s_%d".printf(RenderUtils.sanitize_id(actor.id), n_msgs), actor.source_line);
                    }
                }
                foreach (var msg in diagram.messages) {
                    if (msg.source_line > 0) {
                        element_lines.set("s_%s_%d".printf(RenderUtils.sanitize_id(msg.from.id), msg.sequence_index),
                                          msg.source_line);
                    }
                }
                for (int i = 0; i < diagram.notes.size; i++) {
                    if (diagram.notes[i].source_line > 0) {
                        element_lines.set("note_%d".printf(i), diagram.notes[i].source_line);
                    }
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render Mermaid sequence SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidSequenceDiagram diagram, string filename) {
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(MermaidSequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidSequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
