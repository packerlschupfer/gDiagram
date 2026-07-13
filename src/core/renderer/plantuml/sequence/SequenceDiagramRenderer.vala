namespace GDiagram {
    /**
     * PlantUML sequence diagrams. The layout is computed here, not by Graphviz' rank
     * layout: that one only placed lifeline points for the participants of each message,
     * so arrows sloped and lifelines bent wherever a label was wider than the gap between
     * two participants. Now:
     *
     *  1. Every text-bearing node (heads, labels, notes, frame tabs, titles) is measured
     *     with a throwaway Graphviz layout, so sizes match the final rendering.
     *  2. Columns: one x per participant (plus the left/right border columns of "[->" /
     *     "->]"), placed left to right so that every gap is at least as wide as the widest
     *     label, note or head between the two columns.
     *  3. Rows: the events are walked in source order; each message is a row with its
     *     label above a horizontal arrow, notes / dividers / delays / frame headers take
     *     their own rows.
     *  4. The DOT gives every node a fixed position (layout=nop2), and lifelines are
     *     straight edges from head to foot.
     */
    public class SequenceDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public SequenceDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        // An open grouping frame while the rows are walked
        private class FrameState : Object {
            public SequenceFrame frame;
            public int index;
            public double top;
            public double min_x = double.MAX;
            public double max_x = -double.MAX;
            public Gee.ArrayList<SequenceFrame> else_frames = new Gee.ArrayList<SequenceFrame>();
            public Gee.ArrayList<double?> else_y = new Gee.ArrayList<double?>();
        }

        // Measured node sizes in points, by node id
        private Gee.HashMap<string, double?> size_w = new Gee.HashMap<string, double?>();
        private Gee.HashMap<string, double?> size_h = new Gee.HashMap<string, double?>();
        private Gee.ArrayList<string> measure_ids = new Gee.ArrayList<string>();
        private Gee.ArrayList<string> measure_attrs = new Gee.ArrayList<string>();

        // Column constraints: gaps[a * ncols + b] is the least x[b] - x[a]
        private double[] gaps = {};
        private bool[] col_valid = {};
        private int ncols = 0;

        // Layout state of one generate_dot() run
        private double ext_min;
        private double ext_max;
        private Gee.ArrayList<FrameState> open_frames = new Gee.ArrayList<FrameState>();

        private const double BAR_HALF = 5.0;
        private const double SELF_LOOP = 30.0;

        public string generate_dot(SequenceDiagram diagram) {
            var palette = ThemeManager.get_active_palette();
            // skinparam colours with palette fallbacks. The renderer used to read the
            // palette only, so a theme had no effect and message text was hard-coded black.
            var skin = diagram.skin_params;
            string seq_bg = RenderUtils.sanitize_color(skin.background_color ?? palette.background);
            string seq_participant_fill = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "ParticipantBackgroundColor") ??
                skin.get_element_property("participant", "BackgroundColor") ?? palette.container_fill);
            string seq_participant_border = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "ParticipantBorderColor") ??
                skin.get_element_property("participant", "BorderColor") ?? palette.container_border);
            string? seq_participant_font = skin.get_element_property("sequence", "ParticipantFontColor") ??
                skin.get_element_property("participant", "FontColor");
            string seq_lifeline = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "LifeLineBorderColor") ?? palette.grid);
            string seq_bar_fill = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "LifeLineBackgroundColor") ?? seq_bg);
            string seq_arrow = RenderUtils.sanitize_color(skin.get_element_property("arrow", "Color") ?? palette.edge_color);
            // Arrow FontColor / DefaultFontColor, else a colour contrasting with a canvas set in
            // the file: "skinparam backgroundColor #FFFFFF" on the dark theme left the
            // palette's light label text on white
            string seq_arrow_font = RenderUtils.edge_label_color(skin, palette);
            string seq_note_fill = RenderUtils.sanitize_color(
                skin.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary);
            string seq_note_font = RenderUtils.sanitize_color(
                skin.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(seq_note_fill));
            string frame_color = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "GroupBorderColor") ?? seq_arrow);
            string title_font = RenderUtils.title_color(skin, palette);
            label_bg = seq_bg;

            int n = diagram.participants.size;
            var events = diagram.events;
            measure_ids = new Gee.ArrayList<string>();
            measure_attrs = new Gee.ArrayList<string>();

            image_paths = new Gee.ArrayList<string>();
            spot_marks = new Gee.ArrayList<string>();
            icon_marks = new Gee.ArrayList<string>();
            box_kinds = new Gee.HashMap<string, string>();

            // ---- 1. What to measure ----
            var head_attrs = new string[n];
            var foot_attrs = new string[n];
            for (int i = 0; i < n; i++) {
                var p = diagram.participants[i];
                head_attrs[i] = participant_attrs(p, false, skin, seq_participant_fill, seq_participant_border,
                                                  seq_participant_font);
                foot_attrs[i] = participant_attrs(p, true, skin, seq_participant_fill, seq_participant_border,
                                                  seq_participant_font);
                want("_h%d".printf(i), head_attrs[i]);
                if (p.body_lines == null && (p.participant_type == ParticipantType.COLLECTIONS ||
                                             p.participant_type == ParticipantType.QUEUE)) {
                    string kind = p.participant_type == ParticipantType.QUEUE ? "queue" : "collections";
                    string bid = RenderUtils.escape_id(p.get_id());
                    if (bid.has_prefix("\"") && bid.has_suffix("\"") && bid.length >= 2) {
                        bid = bid.substring(1, bid.length - 2);
                    }
                    box_kinds.set(bid + "_top", kind);
                    box_kinds.set(bid + "_bottom", kind);
                }
            }
            var label_attrs = new string?[diagram.messages.size];
            for (int mi = 0; mi < diagram.messages.size; mi++) {
                label_attrs[mi] = message_label_attrs(diagram.messages[mi], skin, seq_arrow_font);
                if (label_attrs[mi] != null) {
                    want("_seq_lbl_m%d".printf(mi), label_attrs[mi]);
                }
            }
            for (int di = 0; di < diagram.durations.size; di++) {
                string? dl = diagram.durations[di].label;
                if (dl != null) {
                    want("_seq_durl%d".printf(di), html_text_attrs(text_block(creole_html(dl)), 11, seq_arrow_font));
                }
            }
            // "newpage": the footer of the page that ends, the header and title of the next one
            int pages = diagram.page_count;
            {
                int page = 1;
                foreach (var ev in events) {
                    var pb = ev as PageBreakEvent;
                    if (pb == null) {
                        continue;
                    }
                    if (diagram.footer != null) {
                        want("_seq_footer_p%d".printf(page), html_text_attrs(
                            block_html(page_vars(diagram.footer, page, pages)), 10, "#888888"));
                    }
                    page++;
                    if (diagram.header != null) {
                        want("_seq_header_p%d".printf(page), html_text_attrs(
                            block_html(page_vars(diagram.header, page, pages)), 10, "#888888"));
                    }
                    if (pb.title != null) {
                        want("_seq_ptitle%d".printf(page), html_text_attrs(
                            "<B>%s</B>".printf(block_html(pb.title)), 14, title_font));
                    }
                }
            }
            var note_attrs = new string[diagram.notes.size];
            for (int ni = 0; ni < diagram.notes.size; ni++) {
                var note = diagram.notes[ni];
                // "hnote" is a hexagon, "rnote" a rectangle; "note over A #color" its own fill
                string note_shape = note.kind == "hnote" ? "hexagon" : (note.kind == "rnote" ? "box" : "note");
                string note_fill = seq_note_fill;
                string note_font = seq_note_font;
                string? inline_note_color = normalize_color(note.color);
                if (inline_note_color != null) {
                    note_fill = RenderUtils.sanitize_color(inline_note_color);
                    note_font = RenderUtils.sanitize_color(
                        skin.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_fill));
                }
                // Creole text; the lines left-aligned with each other, the block centred in the
                // note as PlantUML draws it (the markers used to be stripped and "" kept)
                string note_text = text_block(creole_html(note.text, true));
                note_attrs[ni] = "shape=%s, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", label=<%s>, color=\"%s\", fontsize=11, margin=\"0.1,0.04\"".printf(
                    note_shape, note_fill, note_font, note_text, seq_arrow);
                want("note%d".printf(ni), note_attrs[ni]);
            }
            string div_fill = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "DividerBackgroundColor") ?? seq_participant_fill);
            string div_font = RenderUtils.sanitize_color(
                skin.get_element_property("sequence", "DividerFontColor") ?? RenderUtils.contrast_text(div_fill));
            for (int d = 0; d < diagram.dividers.size; d++) {
                want("_seq_div%d".printf(d), "shape=plaintext, fontsize=12, margin=0, width=0, height=0, label=<<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\"><TR><TD><FONT COLOR=\"%s\">%s</FONT></TD></TR></TABLE>>".printf(
                    div_fill, seq_participant_border, div_font, creole_html(diagram.dividers[d].title)));
            }
            for (int fi = 0; fi < diagram.frames.size; fi++) {
                var frame = diagram.frames[fi];
                if (frame.frame_type == SequenceFrameType.ELSE) {
                    continue;
                }
                string tab;
                string? secondary;
                frame_texts(frame, out tab, out secondary);
                want("_seq_ftab%d".printf(fi), "shape=box, style=filled, fillcolor=\"%s\", color=\"%s\", penwidth=1.5, fontsize=11, fontcolor=\"%s\", margin=\"0.08,0.02\", width=0, height=0, label=<<B>%s</B>>".printf(
                    seq_bg, frame_color, seq_arrow_font, Markup.escape_text(tab)));
                if (secondary != null) {
                    string sec_attrs = frame.frame_type == SequenceFrameType.REF
                        ? text_attrs(secondary, 11, seq_arrow_font, false)
                        : html_text_attrs("<B>%s</B>".printf(Markup.escape_text(secondary)), 10, seq_arrow_font);
                    want("_seq_fsec%d".printf(fi), sec_attrs);
                }
                for (int si = 0; si < frame.sections.size; si++) {
                    string? cond = frame.sections[si].condition;
                    if (cond != null && cond.strip().length > 0) {
                        string c = cond.strip();
                        if (!c.has_prefix("[")) {
                            c = "[%s]".printf(c);
                        }
                        want("_seq_felse%d_%d".printf(fi, si),
                             html_text_attrs("<B>%s</B>".printf(Markup.escape_text(c)), 10, seq_arrow_font));
                    }
                }
            }
            int space_index = 0;
            foreach (var ev in events) {
                var sp = ev as SpaceEvent;
                if (sp != null) {
                    if (sp.space.delay && sp.space.text != null) {
                        want("_seq_delay%d".printf(space_index), text_attrs(sp.space.text, 10, seq_arrow_font, false));
                    }
                    space_index++;
                }
            }
            if (diagram.title != null) {
                want("_seq_title", html_text_attrs("<B>%s</B>".printf(block_html(diagram.title)), 14, title_font));
            }
            if (diagram.header != null) {
                want("_seq_header", html_text_attrs(block_html(page_vars(diagram.header, 1, pages)), 10, "#888888"));
            }
            if (diagram.caption != null) {
                want("_seq_caption", html_text_attrs(block_html(diagram.caption), 12, title_font));
            }
            if (diagram.footer != null) {
                want("_seq_footer", html_text_attrs(block_html(page_vars(diagram.footer, pages, pages)), 10, "#888888"));
            }
            measure_all();

            // Notes written right after a message without a participant ("note left: x")
            // sit beside that message's arrow
            var attached = new Gee.HashMap<Note, Message>();
            var notes_of = new Gee.HashMap<Message, Gee.ArrayList<Note>>();
            {
                Message? chain = null;
                foreach (var ev in events) {
                    var me = ev as MessageEvent;
                    var ne = ev as NoteEvent;
                    if (me != null) {
                        chain = me.message;
                    } else if (ne != null && chain != null && ne.note.participant == null &&
                               ne.note.position != "across") {
                        attached.set(ne.note, chain);
                        if (!notes_of.has_key(chain)) {
                            notes_of.set(chain, new Gee.ArrayList<Note>());
                        }
                        notes_of.get(chain).add(ne.note);
                    } else if (!(ev is ActivationEvent)) {
                        chain = null;
                    }
                }
            }

            // "create X": the head sits at the first message to X
            var create_msg = new Gee.HashMap<Participant, Message>();
            foreach (var msg in diagram.messages) {
                if (msg.to.created && msg.border == MessageBorder.NONE && msg.from != msg.to &&
                    !create_msg.has_key(msg.to)) {
                    create_msg.set(msg.to, msg);
                }
            }

            // ---- 2. Columns ----
            bool left_border = false;
            bool right_border = false;
            foreach (var msg in diagram.messages) {
                if (msg.border == MessageBorder.LEFT && !msg.border_short) {
                    left_border = true;
                } else if (msg.border == MessageBorder.RIGHT && !msg.border_short) {
                    right_border = true;
                }
            }
            left_border = left_border && n > 0;
            right_border = right_border && n > 0;
            ncols = n + 2;
            gaps = new double[ncols * ncols];
            col_valid = new bool[ncols];
            for (int c = 1; c <= n; c++) {
                col_valid[c] = true;
            }
            col_valid[0] = left_border;
            col_valid[n + 1] = right_border;
            var head_w = new double[ncols];
            for (int i = 0; i < n; i++) {
                head_w[i + 1] = w_of("_h%d".printf(i));
            }
            for (int c = 1; c < n; c++) {
                need(c, c + 1, head_w[c] / 2 + head_w[c + 1] / 2 + 16);
            }
            need(0, 1, head_w[1] / 2 + 16);
            need(n, n + 1, head_w[n] / 2 + 16);

            for (int mi = 0; mi < diagram.messages.size; mi++) {
                var msg = diagram.messages[mi];
                double lw = w_of("_seq_lbl_m%d".printf(mi));
                int cf = col_of(diagram, msg.from);
                int ct = col_of(diagram, msg.to);
                if (msg.border == MessageBorder.NONE) {
                    if (msg.from == msg.to) {
                        // "A <- A" loops on the left
                        int side = msg.direction == ArrowDirection.LEFT ? cf - 1 : cf + 1;
                        need(cf, side, double.max(lw + 16, SELF_LOOP + 15) + BAR_HALF * 2);
                    } else {
                        double extra = create_msg.has_key(msg.to) && create_msg.get(msg.to) == msg
                            ? head_w[ct] / 2 : 0;
                        need(cf, ct, lw + 36 + extra);
                    }
                } else if (msg.border_short) {
                    double s = short_length(lw);
                    if (msg.border == MessageBorder.LEFT) {
                        need(cf - 1, cf, s + 16);
                    } else {
                        need(cf, cf + 1, s + 16);
                    }
                } else if (msg.border == MessageBorder.LEFT) {
                    need(0, cf, lw + 30);
                } else {
                    need(cf, n + 1, lw + 30);
                }
            }
            for (int ni = 0; ni < diagram.notes.size; ni++) {
                var note = diagram.notes[ni];
                double nw = w_of("note%d".printf(ni));
                if (attached.has_key(note)) {
                    var msg = attached.get(note);
                    int ca = col_of(diagram, msg.from);
                    int cb = msg.border == MessageBorder.NONE ? col_of(diagram, msg.to)
                        : (msg.border_short ? ca : (msg.border == MessageBorder.LEFT ? 0 : n + 1));
                    int lo = int.min(ca, cb);
                    int hi = int.max(ca, cb);
                    double self_w = 0;
                    if (msg.from == msg.to && msg.border == MessageBorder.NONE) {
                        self_w = double.max(w_of("_seq_lbl_m%d".printf(diagram.messages.index_of(msg))), SELF_LOOP) + 10;
                    }
                    if (create_msg.has_key(msg.to) && create_msg.get(msg.to) == msg) {
                        self_w = head_w[col_of(diagram, msg.to)] / 2;
                    }
                    if (note.position == "left") {
                        need(lo - 1, lo, nw + 24);
                    } else if (note.position == "right") {
                        need(hi, hi + 1, nw + 24 + self_w);
                    } else if (lo != hi) {
                        need(lo, hi, nw - 20);
                    } else {
                        need(lo - 1, lo, nw / 2 + 16);
                        need(lo, lo + 1, nw / 2 + 16);
                    }
                    continue;
                }
                if (note.participant == null) {
                    continue;
                }
                int c1 = col_of(diagram, note.participant);
                if (note.aligned && ni > 0 && diagram.notes[ni - 1].participant != null) {
                    // "/ note" shares the row of the note before it: keep them apart
                    int c0 = col_of(diagram, diagram.notes[ni - 1].participant);
                    need(c0, c1, (w_of("note%d".printf(ni - 1)) + nw) / 2 + 12);
                }
                if (note.position == "across" || (note.position == "over" && note.participant2 != null)) {
                    int c2 = note.participant2 != null ? col_of(diagram, note.participant2) : c1;
                    if (c1 != c2) {
                        need(int.min(c1, c2), int.max(c1, c2), nw - 30);
                        continue;
                    }
                }
                if (note.position == "left") {
                    need(c1 - 1, c1, nw + 24);
                } else if (note.position == "right") {
                    need(c1, c1 + 1, nw + 24);
                } else {
                    need(c1 - 1, c1, nw / 2 + 16);
                    need(c1, c1 + 1, nw / 2 + 16);
                }
            }
            for (int fi = 0; fi < diagram.frames.size; fi++) {
                var frame = diagram.frames[fi];
                if (frame.frame_type != SequenceFrameType.REF || frame.participants.size == 0) {
                    continue;
                }
                double rw = double.max(w_of("_seq_ftab%d".printf(fi)) + 20, w_of("_seq_fsec%d".printf(fi)) + 30);
                int lo = int.MAX;
                int hi = -1;
                foreach (var p in frame.participants) {
                    lo = int.min(lo, col_of(diagram, p));
                    hi = int.max(hi, col_of(diagram, p));
                }
                if (lo == hi) {
                    need(lo - 1, lo, rw / 2 + 16);
                    need(lo, lo + 1, rw / 2 + 16);
                } else {
                    need(lo, hi, rw - 50);
                }
            }

            var xs = new double[ncols];
            int prev_col = -1;
            for (int c = 0; c < ncols; c++) {
                if (!col_valid[c]) {
                    continue;
                }
                double x = prev_col >= 0 ? xs[prev_col] : 0;
                for (int a = 0; a < c; a++) {
                    if (col_valid[a]) {
                        x = double.max(x, xs[a] + gaps[a * ncols + c]);
                    }
                }
                xs[c] = x;
                prev_col = c;
            }

            // ---- 3. Rows ----
            var back = new StringBuilder();    // frame outlines
            var mid = new StringBuilder();     // points, activation bars, message labels
            var front = new StringBuilder();   // heads, notes, tabs, titles
            var edges = new StringBuilder();   // lifelines, separators
            var msg_edges = new StringBuilder();
            ext_min = double.MAX;
            ext_max = -double.MAX;
            open_frames = new Gee.ArrayList<FrameState>();

            double cur = 0;
            double header_y = 0;
            double title_y = 0;
            if (diagram.header != null) {
                header_y = cur;
                cur += h_of("_seq_header") + 4;
            }
            if (diagram.title != null) {
                title_y = cur;
                cur += h_of("_seq_title") + 10;
            }
            double head_top = cur;
            double head_row = 0;
            for (int i = 0; i < n; i++) {
                if (!create_msg.has_key(diagram.participants[i])) {
                    head_row = double.max(head_row, h_of("_h%d".printf(i)));
                }
            }
            cur += head_row;
            double life_start = cur;
            cur += 10;

            var open_bars = new Gee.HashMap<Participant, Gee.ArrayList<double?>>();
            // the fill of each open bar ("activate A #red", "A -> B ++ #gold")
            var bar_fills = new Gee.HashMap<Participant, Gee.ArrayList<string>>();
            var anchor_y = new Gee.HashMap<string, double?>();
            var anchor_x = new Gee.HashMap<string, double?>();
            string? align_param = skin.get_global("sequencemessagealign");
            string message_align = align_param != null ? align_param.strip().down() : "left";
            string? below_param = skin.get_global("responsemessagebelowarrow");
            bool response_below = below_param != null && below_param.strip().down() == "true";
            // page breaks: the separator rows and the footer / header / title of each page
            var page_sep_y = new Gee.ArrayList<double?>();
            var page_items = new Gee.ArrayList<string>();
            var page_item_y = new Gee.ArrayList<double?>();
            int page_no = 1;
            var destroyed = new Gee.HashMap<Participant, double?>();
            var created_y = new Gee.HashMap<Participant, double?>();
            var delays = new Gee.ArrayList<double?>();
            var divider_y = new Gee.ArrayList<double?>();
            var delay_texts = new Gee.ArrayList<string>();
            var delay_text_y = new Gee.ArrayList<double?>();
            int bar_count = 0;
            int x_count = 0;
            Message? last_msg = null;
            double last_arrow_y = 0;
            bool last_row_msg = false;
            double note_row_top = -1;
            space_index = 0;
            int divider_index = 0;

            for (int ei = 0; ei < events.size; ei++) {
                var ev = events[ei];
                if (!(ev is NoteEvent) && !(ev is ActivationEvent)) {
                    note_row_top = -1;
                }

                var me = ev as MessageEvent;
                if (me != null) {
                    var msg = me.message;
                    int mi = diagram.messages.index_of(msg);
                    string lbl_id = "_seq_lbl_m%d".printf(mi);
                    bool has_label = size_w.has_key(lbl_id);
                    double lw = w_of(lbl_id);
                    double lh = h_of(lbl_id);
                    var here = notes_of.has_key(msg) ? notes_of.get(msg) : new Gee.ArrayList<Note>();
                    double nh = 0;
                    foreach (var note in here) {
                        nh = double.max(nh, h_of("note%d".printf(diagram.notes.index_of(note))));
                    }

                    // Activation levels at this row, including "activate" lines that follow
                    int lf = bar_level(open_bars, msg.from);
                    int lt = bar_level(open_bars, msg.to);
                    int sf = lf;
                    int st = lt;
                    for (int k = ei + 1; k < events.size; k++) {
                        if (events[k] is NoteEvent && attached.has_key(((NoteEvent) events[k]).note)) {
                            continue;
                        }
                        var ae = events[k] as ActivationEvent;
                        if (ae == null) {
                            break;
                        }
                        int delta = ae.activation.activation_type == ActivationType.ACTIVATE ? 1
                            : (ae.activation.activation_type == ActivationType.DEACTIVATE ? -1 : 0);
                        if (ae.activation.participant == msg.from) {
                            sf += delta;
                            lf = int.max(lf, sf);
                        }
                        if (ae.activation.participant == msg.to && msg.to != msg.from) {
                            st += delta;
                            lt = int.max(lt, st);
                        }
                    }
                    bool create_here = create_msg.has_key(msg.to) && create_msg.get(msg.to) == msg;
                    double created_h = create_here ? h_of("_h%d".printf(diagram.participants.index_of(msg.to))) : 0;

                    // "skinparam responseMessageBelowArrow true": the label of a "<-" message
                    // goes under its arrow
                    bool below = has_label && response_below && msg.direction == ArrowDirection.LEFT &&
                                 !(msg.border == MessageBorder.NONE && msg.from == msg.to);
                    double arrow_y = cur + (has_label && !below ? lh + 3 : 6);
                    if (here.size > 0) {
                        arrow_y = double.max(arrow_y, cur + 2 + nh / 2 + (below ? 0 : lh / 2));
                    }
                    if (create_here) {
                        arrow_y = double.max(arrow_y, cur + created_h / 2 + 2);
                    }
                    double bottom = arrow_y + 9 + (below ? lh : 0);
                    string style = get_arrow_style(msg.style);
                    string line_color = msg.color != null ? RenderUtils.sanitize_color(msg.color) : seq_arrow;
                    string color_attr = msg.color != null ? ", color=\"%s\"".printf(line_color) : "";
                    // the written ends: the head end is the one the arrow points at ("bob <- alice"
                    // is alice's message to bob: the head is at bob, the from end)
                    bool head_is_from = msg.direction == ArrowDirection.LEFT;
                    string head_written = head_is_from ? msg.head_left : msg.head_right;
                    string head_deco = head_is_from ? msg.deco_left : msg.deco_right;
                    string tail_written = head_is_from ? msg.head_right : msg.head_left;
                    string tail_deco = head_is_from ? msg.deco_right : msg.deco_left;
                    double lo_x;
                    double hi_x;
                    double label_left;
                    bool head_on_left = false;
                    bool head_on_right = false;

                    if (msg.border == MessageBorder.NONE && msg.from == msg.to) {
                        // Self message: out to the right (left for "A <- A"), down, and back
                        bool loop_left = msg.direction == ArrowDirection.LEFT;
                        double px = column_x(diagram, xs, msg.from);
                        double x0 = bar_edge(px, lf, !loop_left);
                        double lx = loop_left ? x0 - SELF_LOOP : x0 + SELF_LOOP;
                        double y2 = arrow_y + 14;
                        string base_id = RenderUtils.escape_id(msg.from.get_id()) + "_m%d".printf(mi);
                        string s1 = "_seq_self1_m%d".printf(mi);
                        string s2 = "_seq_self2_m%d".printf(mi);
                        string s3 = "_seq_self3_m%d".printf(mi);
                        point(mid, base_id, x0, arrow_y);
                        point(mid, s1, lx, arrow_y);
                        point(mid, s2, lx, y2);
                        point(mid, s3, x0, y2);
                        string plain = "style=%s, arrowhead=none%s".printf(style, color_attr);
                        {
                            string tail_arrow = end_arrow(tail_written, tail_deco,
                                                          msg.direction == ArrowDirection.BIDIRECTIONAL, loop_left,
                                                          head_is_from);
                            string tail = tail_arrow != "none"
                                ? ", dir=both, arrowtail=%s, arrowsize=0.8".printf(tail_arrow) : "";
                            msg_edges.append("  %s -> %s [%s%s];\n".printf(base_id, s1, plain, tail));
                            msg_edges.append("  %s -> %s [%s];\n".printf(s1, s2, plain));
                            msg_edges.append("  %s -> %s [style=%s, arrowhead=%s, arrowsize=0.8%s];\n".printf(
                                s2, s3, style, end_arrow(head_written, head_deco, true, loop_left, !head_is_from),
                                color_attr));
                        }
                        bottom = y2 + 9;
                        if (loop_left) {
                            lo_x = lx;
                            hi_x = px + (lf > 0 ? BAR_HALF : 0);
                            label_left = x0 - 2 - lw;
                        } else {
                            lo_x = px - (lf > 0 ? BAR_HALF : 0);
                            hi_x = lx;
                            label_left = x0 + 2;
                        }
                    } else {
                        double px_from = column_x(diagram, xs, msg.from);
                        double px_to = column_x(diagram, xs, msg.to);
                        string from_id = RenderUtils.escape_id(msg.from.get_id()) + "_m%d".printf(mi);
                        string to_id = RenderUtils.escape_id(msg.to.get_id()) + "_m%d".printf(mi);
                        double from_x;
                        double to_x;
                        if (msg.border == MessageBorder.NONE) {
                            bool to_right = px_to > px_from;
                            from_x = bar_edge(px_from, lf, to_right);
                            if (create_here) {
                                double hw = w_of("_h%d".printf(diagram.participants.index_of(msg.to)));
                                to_x = px_to + (to_right ? -hw / 2 : hw / 2);
                                created_y.set(msg.to, arrow_y);
                            } else {
                                to_x = bar_edge(px_to, lt, !to_right);
                            }
                        } else {
                            // "[-> A" starts at the left border, "A ->]" ends at the right
                            // one; "?-> A" / "A ->?" are short arrows beside the lifeline
                            string end_id = border_end_id(msg, mi);
                            double end_x;
                            if (msg.border_short) {
                                double s = short_length(lw);
                                end_x = msg.border == MessageBorder.LEFT ? px_from - BAR_HALF - s : px_from + BAR_HALF + s;
                            } else {
                                end_x = msg.border == MessageBorder.LEFT ? xs[0] : xs[n + 1];
                            }
                            double p_x = bar_edge(px_from, lf, msg.border == MessageBorder.RIGHT);
                            if (msg.border == MessageBorder.LEFT) {
                                from_id = end_id;
                                from_x = end_x;
                                to_x = p_x;
                            } else {
                                to_id = end_id;
                                from_x = p_x;
                                to_x = end_x;
                            }
                        }
                        lo_x = double.min(from_x, to_x);
                        hi_x = double.max(from_x, to_x);
                        double head_x = head_is_from ? from_x : to_x;
                        double tail_x = head_is_from ? to_x : from_x;
                        bool points_right = head_x > tail_x;
                        // "->x": the line stops at a cross short of the end
                        if (head_deco == "x" || tail_deco == "x") {
                            double hx = head_x;
                            double tx = tail_x;
                            if (head_deco == "x") {
                                hx = head_x + (points_right ? -8 : 8);
                                draw_cross(mid, edges, "_seq_cx%d".printf(x_count++), hx, arrow_y, line_color);
                            }
                            if (tail_deco == "x") {
                                tx = tail_x + (points_right ? 8 : -8);
                                draw_cross(mid, edges, "_seq_cx%d".printf(x_count++), tx, arrow_y, line_color);
                            }
                            if (head_is_from) {
                                from_x = hx;
                                to_x = tx;
                            } else {
                                to_x = hx;
                                from_x = tx;
                            }
                        }
                        point(mid, from_id, from_x, arrow_y);
                        point(mid, to_id, to_x, arrow_y);
                        string extra = color_attr;
                        string tail_arrow = end_arrow(tail_written, tail_deco,
                                                      msg.direction == ArrowDirection.BIDIRECTIONAL, !points_right,
                                                      head_is_from);
                        if (tail_arrow != "none") {
                            // "<->": a head at both ends; "o->": a circle at the tail
                            extra += ", dir=both, arrowtail=%s".printf(tail_arrow);
                        }
                        string head_arrow = end_arrow(head_written, head_deco, true, points_right, !head_is_from);
                        if (head_is_from) {
                            msg_edges.append("  %s -> %s [style=%s, arrowhead=%s, arrowsize=0.8%s];\n".printf(
                                to_id, from_id, style, head_arrow, extra));
                        } else {
                            msg_edges.append("  %s -> %s [style=%s, arrowhead=%s, arrowsize=0.8%s];\n".printf(
                                from_id, to_id, style, head_arrow, extra));
                        }
                        head_on_left = (head_arrow != "none" && !points_right) || (tail_arrow != "none" && points_right);
                        head_on_right = (head_arrow != "none" && points_right) || (tail_arrow != "none" && !points_right);
                        switch (message_align) {
                            case "right":
                                label_left = hi_x - lw - (head_on_right ? 8 : 0);
                                break;
                            case "center":
                                label_left = (lo_x + hi_x - lw) / 2;
                                break;
                            case "direction":
                                // at the tail: left-aligned when the arrow points right
                                label_left = points_right ? lo_x : hi_x - lw;
                                break;
                            case "reversedirection":
                                label_left = points_right ? hi_x - lw - (head_on_right ? 8 : 0)
                                                          : lo_x + (head_on_left ? 8 : 0);
                                break;
                            default:
                                label_left = lo_x + (head_on_left ? 8 : 0);
                                break;
                        }
                    }
                    if (has_label) {
                        double label_cy = below ? arrow_y + 2 + lh / 2 : arrow_y - 1 - lh / 2;
                        mid.append("  %s [%s, %s];\n".printf(lbl_id, label_attrs[mi], pos(label_left + lw / 2, label_cy)));
                        extend(label_left, label_left + lw);
                    }
                    if (create_here) {
                        // the created head stands at the end of the arrow
                        double hw = w_of("_h%d".printf(diagram.participants.index_of(msg.to)));
                        double px_to = column_x(diagram, xs, msg.to);
                        lo_x = double.min(lo_x, px_to - hw / 2);
                        hi_x = double.max(hi_x, px_to + hw / 2);
                    }
                    extend(lo_x, hi_x);
                    if (msg.anchor != null) {
                        anchor_y.set(msg.anchor, arrow_y);
                        anchor_x.set(msg.anchor, (lo_x + hi_x) / 2);
                    }

                    foreach (var note in here) {
                        int ni = diagram.notes.index_of(note);
                        string nid = "note%d".printf(ni);
                        double nw = w_of(nid);
                        double nhh = h_of(nid);
                        double cy = double.max(arrow_y - lh / 2 - 1, cur + 2 + nhh / 2);
                        double cx;
                        if (note.position == "left") {
                            cx = lo_x - 10 - nw / 2;
                        } else if (note.position == "right") {
                            cx = hi_x + 10 + nw / 2;
                        } else {
                            cx = (lo_x + hi_x) / 2;
                        }
                        front.append("  %s [%s, %s];\n".printf(nid, note_attrs[ni], pos(cx, cy)));
                        extend(cx - nw / 2, cx + nw / 2);
                        bottom = double.max(bottom, cy + nhh / 2 + 5);
                    }
                    if (create_here) {
                        bottom = double.max(bottom, arrow_y + created_h / 2 + 6);
                    }
                    cur = bottom;
                    last_msg = msg;
                    last_arrow_y = arrow_y;
                    last_row_msg = true;
                    continue;
                }

                var ne = ev as NoteEvent;
                if (ne != null) {
                    var note = ne.note;
                    if (attached.has_key(note)) {
                        continue;
                    }
                    int ni = diagram.notes.index_of(note);
                    string nid = "note%d".printf(ni);
                    double nw = w_of(nid);
                    double nhh = h_of(nid);
                    double row_top = cur;
                    if (note.aligned && note_row_top >= 0) {
                        // "/ note": on the row of the note before it
                        row_top = note_row_top;
                    }
                    double cy = row_top + 4 + nhh / 2;
                    double cx = 0;
                    string width_attr = "";
                    if (n > 0 && note.participant != null &&
                        (note.position == "across" || (note.position == "over" && note.participant2 != null))) {
                        double xa = column_x(diagram, xs, note.participant);
                        double xb = note.participant2 != null ? column_x(diagram, xs, note.participant2) : xa;
                        if (note.position == "across") {
                            xa = xs[1];
                            xb = xs[n];
                        }
                        double span = (xb - xa).abs() + 30;
                        cx = (xa + xb) / 2;
                        if (span > nw) {
                            nw = span;
                            width_attr = ", width=%s".printf(inch(nw));
                        }
                    } else if (n > 0) {
                        Participant anchor = note.participant ?? (last_msg != null ? last_msg.from : diagram.participants[0]);
                        double ax = column_x(diagram, xs, anchor);
                        int level = bar_level(open_bars, anchor);
                        if (note.position == "left") {
                            cx = ax - (level > 0 ? BAR_HALF : 0) - 8 - nw / 2;
                        } else if (note.position == "right") {
                            cx = bar_edge(ax, level, true) + 8 + nw / 2;
                        } else {
                            cx = ax;
                        }
                    }
                    front.append("  %s [%s%s, %s];\n".printf(nid, note_attrs[ni], width_attr, pos(cx, cy)));
                    extend(cx - nw / 2, cx + nw / 2);
                    cur = double.max(cur, cy + nhh / 2 + 6);
                    note_row_top = row_top;
                    last_row_msg = false;
                    continue;
                }

                // "newpage": the pages follow each other in one image (see page_break_rows)
                var pb = ev as PageBreakEvent;
                if (pb != null) {
                    cur += 10;
                    if (diagram.footer != null) {
                        string fid = "_seq_footer_p%d".printf(page_no);
                        page_items.add(fid);
                        page_item_y.add(cur + h_of(fid) / 2);
                        cur += h_of(fid) + 6;
                    }
                    page_sep_y.add(cur);
                    cur += 10;
                    page_no++;
                    if (diagram.header != null) {
                        string hid = "_seq_header_p%d".printf(page_no);
                        page_items.add(hid);
                        page_item_y.add(cur + h_of(hid) / 2);
                        cur += h_of(hid) + 4;
                    }
                    if (pb.title != null) {
                        string tid = "_seq_ptitle%d".printf(page_no);
                        page_items.add(tid);
                        page_item_y.add(cur + h_of(tid) / 2);
                        cur += h_of(tid) + 10;
                    }
                    last_row_msg = false;
                    continue;
                }

                var de = ev as DividerEvent;
                if (de != null) {
                    string did = "_seq_div%d".printf(divider_index);
                    cur += 8;
                    divider_y.add(cur + h_of(did) / 2);
                    cur += h_of(did) + 8;
                    divider_index++;
                    last_row_msg = false;
                    continue;
                }

                var se = ev as SpaceEvent;
                if (se != null) {
                    string sid = "_seq_delay%d".printf(space_index);
                    space_index++;
                    if (se.space.delay) {
                        double y0 = cur;
                        double th = size_h.has_key(sid) ? h_of(sid) : 0;
                        cur += double.max(26, th + 16);
                        delays.add(y0);
                        delays.add(cur);
                        if (th > 0) {
                            delay_texts.add(sid);
                            delay_text_y.add((y0 + cur) / 2);
                        }
                    } else {
                        cur += se.space.height;
                    }
                    last_row_msg = false;
                    continue;
                }

                var fe = ev as FrameEvent;
                if (fe != null) {
                    var frame = fe.frame;
                    int fi = diagram.frames.index_of(frame);
                    last_row_msg = false;
                    if (frame.frame_type == SequenceFrameType.REF && frame.participants.size > 0) {
                        // "ref over A, B": a box with the text, over the participants
                        string tab_id = "_seq_ftab%d".printf(fi);
                        string text_id = "_seq_fsec%d".printf(fi);
                        double lo = double.MAX;
                        double hi = -double.MAX;
                        foreach (var p in frame.participants) {
                            lo = double.min(lo, column_x(diagram, xs, p));
                            hi = double.max(hi, column_x(diagram, xs, p));
                        }
                        double width = double.max(hi - lo + 50, double.max(w_of(tab_id) + 20, w_of(text_id) + 30));
                        double cx = (lo + hi) / 2;
                        double left = cx - width / 2;
                        cur += 6;
                        double top = cur;
                        double height = h_of(tab_id) + h_of(text_id) + 10;
                        front.append("  _seq_frame%d [shape=rect, style=filled, fillcolor=\"%s\", color=\"%s\", penwidth=1.5, fixedsize=true, label=\"\", width=%s, height=%s, %s];\n".printf(
                            fi, seq_bg, frame_color, inch(width), inch(height), pos(cx, top + height / 2)));
                        front.append("  %s [%s, %s];\n".printf(tab_id, measure_attr(tab_id),
                            pos(left + w_of(tab_id) / 2, top + h_of(tab_id) / 2)));
                        if (size_w.has_key(text_id)) {
                            front.append("  %s [%s, %s];\n".printf(text_id, measure_attr(text_id),
                                pos(cx, top + h_of(tab_id) + 4 + h_of(text_id) / 2)));
                        }
                        extend(left, left + width);
                        cur = top + height + 6;
                        continue;
                    }
                    if (frame.frame_type == SequenceFrameType.ELSE) {
                        FrameState? parent = null;
                        foreach (var st_open in open_frames) {
                            if (st_open.frame == frame.parent) {
                                parent = st_open;
                            }
                        }
                        if (parent == null) {
                            continue;
                        }
                        cur += 6;
                        parent.else_frames.add(frame);
                        parent.else_y.add(cur);
                        string cid = "_seq_felse%d_%d".printf(parent.index, frame.parent.sections.index_of(frame));
                        cur += (size_h.has_key(cid) ? h_of(cid) + 2 : 0) + 6;
                        continue;
                    }
                    if (fe.is_start) {
                        cur += 8;
                        var state = new FrameState();
                        state.frame = frame;
                        state.index = fi;
                        state.top = cur;
                        open_frames.add(state);
                        cur += h_of("_seq_ftab%d".printf(fi)) + 6;
                        continue;
                    }
                    int at = -1;
                    for (int k = 0; k < open_frames.size; k++) {
                        if (open_frames[k].frame == frame) {
                            at = k;
                        }
                    }
                    if (at < 0) {
                        continue;
                    }
                    while (open_frames.size > at) {
                        cur += 6;
                        close_frame(back, front, edges, open_frames[open_frames.size - 1], cur, xs, head_w, n,
                                    frame_color);
                    }
                    cur += 4;
                    continue;
                }

                var ae = ev as ActivationEvent;
                if (ae != null) {
                    var p = ae.activation.participant;
                    bool at_msg = last_row_msg && last_msg != null && (last_msg.from == p || last_msg.to == p);
                    double y = at_msg ? last_arrow_y : cur;
                    if (!open_bars.has_key(p)) {
                        open_bars.set(p, new Gee.ArrayList<double?>());
                        bar_fills.set(p, new Gee.ArrayList<string>());
                    }
                    var stack = open_bars.get(p);
                    var fills = bar_fills.get(p);
                    switch (ae.activation.activation_type) {
                        case ActivationType.ACTIVATE:
                            stack.add(y);
                            // "activate A #red": the colours were ignored
                            string? act_color = normalize_color(ae.activation.color);
                            fills.add(act_color != null ? RenderUtils.sanitize_color(act_color) : seq_bar_fill);
                            break;
                        case ActivationType.DEACTIVATE:
                            if (stack.size > 0) {
                                cur = double.max(cur, emit_bar(mid, bar_count++, column_x(diagram, xs, p), stack.size,
                                                               (double) stack.remove_at(stack.size - 1), y,
                                                               fills.remove_at(fills.size - 1), seq_arrow) + 4);
                            }
                            break;
                        case ActivationType.DESTROY:
                            while (stack.size > 0) {
                                emit_bar(mid, bar_count++, column_x(diagram, xs, p), stack.size,
                                         (double) stack.remove_at(stack.size - 1), y, fills.remove_at(fills.size - 1),
                                         seq_arrow);
                            }
                            destroyed.set(p, y);
                            double px = column_x(diagram, xs, p);
                            for (int k = 0; k < 2; k++) {
                                string a = "_seq_x%d_%da".printf(x_count, k);
                                string b = "_seq_x%d_%db".printf(x_count, k);
                                point(mid, a, px - 9, y + (k == 0 ? -9 : 9));
                                point(mid, b, px + 9, y + (k == 0 ? 9 : -9));
                                edges.append("  %s -> %s [arrowhead=none, color=\"#A80036\", penwidth=2];\n".printf(a, b));
                            }
                            x_count++;
                            if (!at_msg) {
                                cur += 12;
                            }
                            break;
                    }
                    continue;
                }
            }

            while (open_frames.size > 0) {
                cur += 6;
                close_frame(back, front, edges, open_frames[open_frames.size - 1], cur, xs, head_w, n, frame_color);
            }
            cur += 6;
            foreach (var entry in open_bars.entries) {
                var stack = entry.value;
                var fills = bar_fills.get(entry.key);
                while (stack.size > 0) {
                    emit_bar(mid, bar_count++, column_x(diagram, xs, entry.key), stack.size,
                             (double) stack.remove_at(stack.size - 1), cur, fills.remove_at(fills.size - 1), seq_arrow);
                }
            }
            cur += 4;
            double foot_top = cur;

            // Heads and feet
            double foot_row = 0;
            for (int i = 0; i < n; i++) {
                var p = diagram.participants[i];
                string base_id = RenderUtils.escape_id(p.get_id());
                double x = xs[i + 1];
                double w = w_of("_h%d".printf(i));
                double h = h_of("_h%d".printf(i));
                double head_cy = created_y.has_key(p) ? (double) created_y.get(p) : head_top + head_row - h / 2;
                front.append("  %s_top [%s, %s];\n".printf(base_id, head_attrs[i], pos(x, head_cy)));
                if (diagram.hide_footbox) {
                    // "hide footbox": the lifeline ends at an invisible point instead of a box
                    front.append("  %s_bottom [label=\"\", shape=point, width=0, height=0, style=invis, %s];\n".printf(
                        base_id, pos(x, foot_top)));
                } else {
                    front.append("  %s_bottom [%s, %s];\n".printf(base_id, foot_attrs[i], pos(x, foot_top + h / 2)));
                    foot_row = double.max(foot_row, h);
                }
                extend(x - w / 2, x + w / 2);

                // The lifeline: straight from below the head to the foot (or the "destroy"
                // cross), dotted through delays
                double ys = created_y.has_key(p) ? (double) created_y.get(p) + h / 2 : life_start;
                double ye = destroyed.has_key(p) ? (double) destroyed.get(p) : foot_top;
                var cuts = new Gee.ArrayList<double?>();
                cuts.add(ys);
                for (int k = 0; k + 1 < delays.size; k += 2) {
                    if ((double) delays[k] > ys && (double) delays[k + 1] < ye) {
                        cuts.add(delays[k]);
                        cuts.add(delays[k + 1]);
                    }
                }
                cuts.add(ye);
                for (int k = 0; k < cuts.size; k++) {
                    point(mid, "%s_l%d".printf(base_id, k), x, (double) cuts[k]);
                }
                for (int k = 0; k + 1 < cuts.size; k++) {
                    bool in_delay = k % 2 == 1;
                    // A delay's dots take the arrow colour: in the faint lifeline colour they
                    // could not be told from the dashes (render_to_svg also packs them closer)
                    edges.append("  %s_l%d -> %s_l%d [style=%s, arrowhead=none, color=\"%s\", penwidth=%s];\n".printf(
                        base_id, k, base_id, k + 1, in_delay ? "dotted" : "dashed", in_delay ? seq_arrow : seq_lifeline,
                        in_delay ? "1.5" : "1"));
                }
            }
            if (left_border) {
                extend(xs[0], xs[0]);
            }
            if (right_border) {
                extend(xs[n + 1], xs[n + 1]);
            }
            cur = foot_top + foot_row;
            if (ext_min > ext_max) {
                ext_min = 0;
                ext_max = 0;
            }

            // Dividers ("== Title =="): a double line across the diagram, the title boxed
            // in the middle
            double mid_x = (ext_min + ext_max) / 2;
            for (int d = 0; d < divider_y.size; d++) {
                double y = (double) divider_y[d];
                for (int k = 0; k < 2; k++) {
                    double ly = y + (k == 0 ? -1.5 : 1.5);
                    string a = "_seq_dl%d_%da".printf(d, k);
                    string b = "_seq_dl%d_%db".printf(d, k);
                    point(mid, a, ext_min - 6, ly);
                    point(mid, b, ext_max + 6, ly);
                    edges.append("  %s -> %s [arrowhead=none, color=\"%s\", penwidth=1];\n".printf(a, b, seq_participant_border));
                }
                front.append("  _seq_div%d [%s, %s];\n".printf(d, measure_attr("_seq_div%d".printf(d)), pos(mid_x, y)));
            }
            // Page breaks: a dashed rule across the diagram; the footer of the page above it,
            // the header and "newpage" title of the page below it. PlantUML's PNG export shows
            // page 1 only; one image of all pages keeps every message visible in the preview
            // (and clickable) instead of silently dropping the later pages.
            for (int k = 0; k < page_sep_y.size; k++) {
                double y = (double) page_sep_y[k];
                string a = "_seq_page%d_a".printf(k);
                string b = "_seq_page%d_b".printf(k);
                point(mid, a, ext_min - 6, y);
                point(mid, b, ext_max + 6, y);
                edges.append("  %s -> %s [arrowhead=none, style=dashed, color=\"%s\", penwidth=1.2];\n".printf(
                    a, b, seq_participant_border));
            }
            for (int k = 0; k < page_items.size; k++) {
                string id = page_items[k];
                double w = w_of(id);
                double x = id.has_prefix("_seq_footer") ? mid_x
                    : (id.has_prefix("_seq_header") ? double.max(ext_max, ext_min + w) - w / 2 : mid_x);
                front.append("  %s [%s, %s];\n".printf(id, measure_attr(id), pos(x, (double) page_item_y[k])));
            }
            // "{start} <-> {end} : text": a vertical double arrow from the middle of the first
            // anchored message to the row of the second, the text beside it
            for (int di = 0; di < diagram.durations.size; di++) {
                var dur = diagram.durations[di];
                if (!anchor_y.has_key(dur.from_anchor) || !anchor_y.has_key(dur.to_anchor)) {
                    continue;
                }
                double x = (double) anchor_x.get(dur.from_anchor);
                double y1 = (double) anchor_y.get(dur.from_anchor);
                double y2 = (double) anchor_y.get(dur.to_anchor);
                string a = "_seq_dur%d_a".printf(di);
                string b = "_seq_dur%d_b".printf(di);
                point(mid, a, x, y1);
                point(mid, b, x, y2);
                msg_edges.append("  %s -> %s [style=solid, dir=both, arrowhead=normal, arrowtail=normal, arrowsize=0.8];\n".printf(a, b));
                string lid = "_seq_durl%d".printf(di);
                if (size_w.has_key(lid)) {
                    double w = w_of(lid);
                    front.append("  %s [%s, %s];\n".printf(lid, measure_attr(lid), pos(x + 4 + w / 2, (y1 + y2) / 2)));
                    extend(x, x + 4 + w);
                }
            }
            for (int k = 0; k < delay_texts.size; k++) {
                front.append("  %s [%s, %s];\n".printf(delay_texts[k], measure_attr(delay_texts[k]),
                                                     pos(mid_x, (double) delay_text_y[k])));
            }
            if (diagram.title != null) {
                front.append("  _seq_title [%s, %s];\n".printf(measure_attr("_seq_title"),
                                                              pos(mid_x, title_y + h_of("_seq_title") / 2)));
            }
            if (diagram.header != null) {
                front.append("  _seq_header [%s, %s];\n".printf(measure_attr("_seq_header"),
                    pos(double.max(ext_max, ext_min + w_of("_seq_header")) - w_of("_seq_header") / 2,
                        header_y + h_of("_seq_header") / 2)));
            }
            if (diagram.caption != null) {
                cur += 8;
                front.append("  _seq_caption [%s, %s];\n".printf(measure_attr("_seq_caption"),
                                                                pos(mid_x, cur + h_of("_seq_caption") / 2)));
                cur += h_of("_seq_caption");
            }
            if (diagram.footer != null) {
                cur += 6;
                front.append("  _seq_footer [%s, %s];\n".printf(measure_attr("_seq_footer"),
                                                               pos(mid_x, cur + h_of("_seq_footer") / 2)));
            }

            var sb = new StringBuilder();
            sb.append("digraph sequence {\n");
            sb.append("  // Positions are fixed here (layout=nop2): Graphviz draws, it does not place\n");
            sb.append("  layout=nop2;\n");
            sb.append("  splines=line;\n");
            sb.append("  outputorder=edgesfirst;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(seq_bg));
            sb.append("  node [fontname=\"Sans\", style=\"filled\"];\n");
            sb.append("  edge [fontsize=10, fontname=\"Sans\", color=\"%s\"];\n".printf(palette.edge_color));
            sb.append("\n  // Frames\n");
            sb.append(back.str);
            sb.append("\n  // Points, activations, message labels\n");
            sb.append(mid.str);
            sb.append("\n  // Participants, notes, titles\n");
            sb.append(front.str);
            sb.append("\n  // Lifelines and separators\n");
            sb.append(edges.str);
            sb.append("\n  // Messages\n");
            sb.append("  edge [fontsize=11, color=\"%s\", fontcolor=\"%s\"];\n".printf(seq_arrow, seq_arrow_font));
            sb.append(msg_edges.str);
            sb.append("}\n");
            return sb.str;
        }

        // Closes the innermost open frame at `bottom`: its outline, tab, "else" separators
        private void close_frame(StringBuilder back, StringBuilder front, StringBuilder edges, FrameState state,
                                 double bottom, double[] xs, double[] head_w, int n, string frame_color) {
            open_frames.remove(state);
            int fi = state.index;
            double left;
            double right;
            if (state.min_x > state.max_x) {
                left = n > 0 ? xs[1] - head_w[1] / 2 : 0;
                right = n > 0 ? xs[n] + head_w[n] / 2 : 60;
            } else {
                left = state.min_x - 12;
                right = state.max_x + 12;
            }
            string tab_id = "_seq_ftab%d".printf(fi);
            string sec_id = "_seq_fsec%d".printf(fi);
            double tab_w = w_of(tab_id);
            double tab_h = h_of(tab_id);
            double need_w = tab_w + (size_w.has_key(sec_id) ? w_of(sec_id) + 12 : 0) + 10;
            for (int si = 0; si < state.frame.sections.size; si++) {
                need_w = double.max(need_w, w_of("_seq_felse%d_%d".printf(fi, si)) + 16);
            }
            if (right - left < need_w) {
                right = left + need_w;
            }
            double width = right - left;
            double height = bottom - state.top;
            back.append("  _seq_frame%d [shape=rect, style=solid, fixedsize=true, label=\"\", color=\"%s\", penwidth=1.5, width=%s, height=%s, %s];\n".printf(
                fi, frame_color, inch(width), inch(height), pos(left + width / 2, state.top + height / 2)));
            front.append("  %s [%s, %s];\n".printf(tab_id, measure_attr(tab_id),
                                                 pos(left + tab_w / 2, state.top + tab_h / 2)));
            if (size_w.has_key(sec_id)) {
                front.append("  %s [%s, %s];\n".printf(sec_id, measure_attr(sec_id),
                    pos(left + tab_w + 8 + w_of(sec_id) / 2, state.top + tab_h / 2)));
            }
            for (int k = 0; k < state.else_frames.size; k++) {
                int si = state.frame.sections.index_of(state.else_frames[k]);
                double y = (double) state.else_y[k];
                string a = "_seq_fe%d_%da".printf(fi, si);
                string b = "_seq_fe%d_%db".printf(fi, si);
                point(back, a, left, y);
                point(back, b, right, y);
                edges.append("  %s -> %s [style=dashed, arrowhead=none, color=\"%s\", penwidth=1];\n".printf(a, b, frame_color));
                string cid = "_seq_felse%d_%d".printf(fi, si);
                if (size_w.has_key(cid)) {
                    front.append("  %s [%s, %s];\n".printf(cid, measure_attr(cid),
                        pos(left + 6 + w_of(cid) / 2, y + 2 + h_of(cid) / 2)));
                }
            }
            extend(left, right);
        }

        // The "x" end of a message ("->x"): two crossing strokes centred on (x, y)
        private static void draw_cross(StringBuilder points, StringBuilder edges, string id, double x, double y,
                                       string color) {
            for (int k = 0; k < 2; k++) {
                string a = "%s_%da".printf(id, k);
                string b = "%s_%db".printf(id, k);
                point(points, a, x - 5, y + (k == 0 ? -5 : 5));
                point(points, b, x + 5, y + (k == 0 ? 5 : -5));
                edges.append("  %s -> %s [arrowhead=none, color=\"%s\", penwidth=2];\n".printf(a, b, color));
            }
        }

        // An activation bar; returns its bottom
        private double emit_bar(StringBuilder sb, int index, double x, int level, double ys, double ye,
                                string fill, string border) {
            double bottom = double.max(ye, ys + 8);
            sb.append("  _seq_act%d [shape=rect, style=filled, fixedsize=true, label=\"\", fillcolor=\"%s\", color=\"%s\", width=%s, height=%s, %s];\n".printf(
                index, fill, border, inch(BAR_HALF * 2), inch(bottom - ys),
                pos(x + (level - 1) * BAR_HALF, (ys + bottom) / 2)));
            return bottom;
        }

        private static int bar_level(Gee.HashMap<Participant, Gee.ArrayList<double?>> bars, Participant p) {
            return bars.has_key(p) ? bars.get(p).size : 0;
        }

        // Where an arrow meets a lifeline with `level` open activation bars
        private static double bar_edge(double x, int level, bool toward_right) {
            if (level <= 0) {
                return x;
            }
            return toward_right ? x + BAR_HALF + (level - 1) * BAR_HALF : x - BAR_HALF;
        }

        // Length of a short "?->" arrow
        private static double short_length(double label_w) {
            return double.max(label_w + 16, 30);
        }

        // Grows the diagram's and every open frame's horizontal extent
        private void extend(double a, double b) {
            ext_min = double.min(ext_min, a);
            ext_max = double.max(ext_max, b);
            foreach (var state in open_frames) {
                state.min_x = double.min(state.min_x, a);
                state.max_x = double.max(state.max_x, b);
            }
        }

        private static int col_of(SequenceDiagram diagram, Participant p) {
            return diagram.participants.index_of(p) + 1;
        }

        private static double column_x(SequenceDiagram diagram, double[] xs, Participant p) {
            int c = col_of(diagram, p);
            return c >= 1 && c < xs.length ? xs[c] : 0;
        }

        // x[b] - x[a] must be at least d
        private void need(int a, int b, double d) {
            if (a > b) {
                int t = a;
                a = b;
                b = t;
            }
            if (a == b || a < 0 || b >= ncols || !col_valid[a] || !col_valid[b]) {
                return;
            }
            gaps[a * ncols + b] = double.max(gaps[a * ncols + b], d);
        }

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

        /**
         * Sizes every wanted node with one throwaway Graphviz layout ("plain" output), so
         * the columns and rows fit the text as Graphviz will draw it. Nodes the layout
         * could not size get a rough estimate.
         */
        private void measure_all() {
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

        // Locale-independent number for DOT
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

        // A message label with two spaces around each line
        private static string pad_label(string text) {
            var sb = new StringBuilder();
            foreach (string line in text.replace("\n", "\\n").split("\\n")) {
                if (sb.len > 0) {
                    sb.append("\\n");
                }
                sb.append("  %s  ".printf(line));
            }
            return sb.str;
        }

        // "\n" line breaks as left-justified "\l" lines
        private static string left_lines(string escaped) {
            if (!escaped.contains("\\n")) {
                return escaped;
            }
            return escaped.replace("\\n", "\\l") + "\\l";
        }

        // A plain text node
        private static string text_attrs(string text, int fontsize, string color, bool left) {
            string esc = RenderUtils.escape_label(text);
            if (left) {
                esc = left_lines(esc);
            }
            return "shape=plaintext, style=solid, fontsize=%d, fontcolor=\"%s\", margin=\"0.02,0.01\", width=0, height=0, label=\"%s\"".printf(
                fontsize, color, esc);
        }

        // A text node with an HTML label body
        private static string html_text_attrs(string html, int fontsize, string color) {
            return "shape=plaintext, style=solid, fontsize=%d, fontcolor=\"%s\", margin=\"0.02,0.01\", width=0, height=0, label=<%s>".printf(
                fontsize, color, html);
        }

        // Title / caption text as HTML: Creole styles, line breaks
        private string block_html(string text) {
            return creole_html(text);
        }

        // Header/footer page variables
        private static string page_vars(string text, int page, int last_page) {
            return text.replace("%page%", page.to_string()).replace("%lastpage%", last_page.to_string());
        }

        // The tab text and the secondary text of a frame: "alt" + "[condition]",
        // "group" label + "[secondary]", "ref" + text
        private static void frame_texts(SequenceFrame frame, out string tab, out string? secondary) {
            string text = (frame.condition ?? frame.label ?? "").strip();
            secondary = null;
            if (frame.frame_type == SequenceFrameType.GROUP) {
                int b = text.index_of("[");
                if (b >= 0 && text.has_suffix("]")) {
                    tab = text.substring(0, b).strip();
                    secondary = text.substring(b);
                } else {
                    tab = text;
                }
                if (tab.length == 0) {
                    tab = "group";
                }
            } else if (frame.frame_type == SequenceFrameType.REF) {
                tab = "ref";
                if (text.length > 0) {
                    secondary = text;
                }
            } else {
                tab = frame.get_type_label();
                if (text.length > 0) {
                    secondary = text.has_prefix("[") ? text : "[%s]".printf(text);
                }
            }
        }

        private static void point(StringBuilder sb, string id, double x, double y) {
            sb.append("  %s [label=\"\", shape=point, width=0.01, height=0.01, style=invis, %s];\n".printf(id, pos(x, y)));
        }

        // DOT id of a border message's free end
        private static string border_end_id(Message msg, int msg_idx) {
            string side = msg.border == MessageBorder.LEFT ? "l" : "r";
            if (msg.border_short) {
                return "_seq_s%s_m%d".printf(side, msg_idx);
            }
            return "_seq_b%s_m%d".printf(side, msg_idx);
        }

        // The Graphviz shape of a boxed participant head. Actors, boundaries, controls and
        // entities are icons (participant_attrs); collections and queues are boxes that
        // render_to_svg turns into stacked boxes and horizontal cylinders.
        private static string get_participant_shape(ParticipantType ptype) {
            return ptype == ParticipantType.DATABASE ? "cylinder" : "box";
        }

        private string get_arrow_style(ArrowStyle style) {
            switch (style) {
                case ArrowStyle.DOTTED:
                case ArrowStyle.DOTTED_OPEN:
                    return "dashed";
                default:
                    return "solid";
            }
        }

        private string? normalize_color(string? color) {
            if (color == null) return null;

            // If color starts with #, check if it's hex or named
            if (color.has_prefix("#")) {
                string value = color.substring(1);
                // Check if it's a hex color (3 or 6 hex digits)
                if (value.length == 3 || value.length == 6) {
                    bool is_hex = true;
                    foreach (char c in value.to_utf8()) {
                        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                            is_hex = false;
                            break;
                        }
                    }
                    if (is_hex) {
                        return color;  // Keep #FF0000 or #F00
                    }
                }
                // Named color with #, strip the #
                return value;  // Return 'red' not '#red'
            }
            return color;
        }

        // skinparam element that styles a participant of this kind
        private static string participant_element(ParticipantType ptype) {
            switch (ptype) {
                case ParticipantType.ACTOR: return "actor";
                case ParticipantType.BOUNDARY: return "boundary";
                case ParticipantType.CONTROL: return "control";
                case ParticipantType.ENTITY: return "entity";
                case ParticipantType.DATABASE: return "database";
                case ParticipantType.COLLECTIONS: return "collections";
                case ParticipantType.QUEUE: return "queue";
                default: return "participant";
            }
        }

        // Diagram background, for actor text that sits outside any box
        private string label_bg = "#FFFFFF";

        // The stereotype as HTML-label text: «foo», or <<foo>> under "skinparam guillemet false"
        private static string? participant_stereotype_html(Participant p, SkinParams skin) {
            if (p.stereotype == null) {
                return null;
            }
            string text = Markup.escape_text(p.stereotype);
            string? guillemet = skin.get_global("guillemet");
            if (guillemet != null && guillemet.strip().down() == "false") {
                return "&lt;&lt;<I>%s</I>&gt;&gt;".printf(text);
            }
            return "<I>«%s»</I>".printf(text);
        }

        // ---- Creole / PlantUML HTML text ----

        // An open text style while creole_html() walks its text
        private class Span : Object {
            public string kind;
            public string open_tag;
            public string close_tag;
            // "**" / "//" / ... pairs end at the line end; <tags> may span lines
            public bool line_scoped;
            public int start;
            public int mark;
        }

        // Local image files met by creole_html(allow_images): "\x01<index>\x01" in its output
        private Gee.ArrayList<string> image_paths = new Gee.ArrayList<string>();

        private static Regex? tag_regex = null;
        private static Regex? font_attr_regex = null;

        // The two-character Creole marker at `i`, or null
        private static string? marker_at(string text, int i) {
            if (i + 1 >= text.length || text[i] != text[i + 1]) {
                return null;
            }
            switch (text[i]) {
                case '*':
                case '"':
                case '-':
                case '_':
                case '~':
                    return text.substring(i, 2);
                case '/':
                    // "https://" is no italic
                    return i > 0 && text[i - 1] == ':' ? null : "//";
                default:
                    return null;
            }
        }

        // Is there a closing `marker` after `from`, before the end of the line?
        private static bool closes_on_line(string text, int from, string marker) {
            for (int j = from + 1; j + 1 < text.length; j++) {
                if (text[j] == '\n' || (text[j] == '\\' && text[j + 1] == 'n' && text[j - 1] != '\\')) {
                    return false;
                }
                if (text[j] == marker[0] && text[j + 1] == marker[1] && marker_at(text, j) != null) {
                    return true;
                }
            }
            return false;
        }

        private static void push_span(StringBuilder sb, Gee.ArrayList<Span> stack, Span span) {
            span.start = (int) sb.len;
            sb.append(span.open_tag);
            span.mark = (int) sb.len;
            stack.add(span);
        }

        private const int CLOSE_ONE = 0;        // stack[at]; the spans opened after it reopen
        private const int CLOSE_LINE_END = 1;   // stack[at] and later; later tag spans reopen
        private const int CLOSE_ALL = 2;        // stack[at] and later, nothing reopens

        // Closes stack[at] and the spans opened after it (reopened as `mode` says). An empty
        // span is dropped instead of closed: Graphviz rejects "<b></b>".
        private static void close_spans(StringBuilder sb, Gee.ArrayList<Span> stack, int at, int mode) {
            var reopen = new Gee.ArrayList<Span>();
            for (int k = stack.size - 1; k >= at; k--) {
                var s = stack.remove_at(k);
                if (s.open_tag.length > 0) {
                    if ((int) sb.len == s.mark) {
                        sb.truncate(s.start);
                    } else {
                        sb.append(s.close_tag);
                    }
                }
                bool again = k > at && (mode == CLOSE_ONE || (mode == CLOSE_LINE_END && !s.line_scoped));
                if (again) {
                    reopen.insert(0, s);
                }
            }
            foreach (var s in reopen) {
                push_span(sb, stack, s);
            }
        }

        private static int find_span(Gee.ArrayList<Span> stack, string kind) {
            for (int k = stack.size - 1; k >= 0; k--) {
                if (stack[k].kind == kind) {
                    return k;
                }
            }
            return -1;
        }

        private static void append_escaped_char(StringBuilder sb, char c) {
            switch (c) {
                case '&': sb.append("&amp;"); break;
                case '<': sb.append("&lt;"); break;
                case '>': sb.append("&gt;"); break;
                case '"': sb.append("&quot;"); break;
                default: sb.append_c(c); break;
            }
        }

        private static string xml_escape(string text) {
            var sb = new StringBuilder();
            for (int i = 0; i < text.length; i++) {
                append_escaped_char(sb, text[i]);
            }
            return sb.str;
        }

        // A Creole/HTML colour as a Graphviz colour, null when it is none
        private static string? html_color(string? value) {
            if (value == null) {
                return null;
            }
            string v = value.strip();
            if (v.has_prefix("#")) {
                v = v.substring(1);
            }
            if (v.length == 0) {
                return null;
            }
            bool hex = v.length == 3 || v.length == 6 || v.length == 8;
            bool alpha = true;
            for (int i = 0; i < v.length; i++) {
                hex = hex && v[i].isxdigit();
                alpha = alpha && v[i].isalpha();
            }
            if (hex) {
                if (v.length == 3) {
                    v = "%c%c%c%c%c%c".printf(v[0], v[0], v[1], v[1], v[2], v[2]);
                }
                return "#" + v.up();
            }
            return alpha ? v.down() : null;
        }

        /**
         * Creole and PlantUML's HTML subset as Graphviz HTML-label text: **bold**, //italic//,
         * ""mono"", --strike--, __underline__, ~~wave~~ (underlined), ~ escapes, <b> <i> <u>
         * <s> <strike> <del> <w> <sub> <sup>, <color:X> / <color X>, <size:N>, <font ...>,
         * <back:X> (read, not drawn), [[links]], "\n" breaks and "\\n" as a literal "\n".
         * Tags stay balanced: an unclosed tag ends with the text, a closing tag with nothing
         * open stays literal text. With `allow_images` a local <img:file> becomes an image
         * marker for html_cells(); otherwise images are dropped.
         */
        private string creole_html(string? text, bool allow_images = false) {
            if (text == null || text.length == 0) {
                return "";
            }
            try {
                if (tag_regex == null) {
                    tag_regex = new Regex("^<(/?)([A-Za-z]+)(?:[:= ]\\s*([^<>]*?))?\\s*/?>");
                    font_attr_regex = new Regex("([A-Za-z-]+)\\s*=\\s*\"?([^\"\\s>]+)\"?");
                }
            } catch (RegexError e) {
                return xml_escape(text);
            }
            var sb = new StringBuilder();
            var stack = new Gee.ArrayList<Span>();
            int n = text.length;
            int i = 0;
            while (i < n) {
                char c = text[i];
                if (c == '\r') {
                    i++;
                    continue;
                }
                if (c == '\\' && i + 1 < n && text[i + 1] == '\\') {
                    sb.append("\\");
                    i += 2;
                    continue;
                }
                if (c == '\n' || (c == '\\' && i + 1 < n && text[i + 1] == 'n')) {
                    int first_line_scoped = -1;
                    for (int k = 0; k < stack.size; k++) {
                        if (stack[k].line_scoped) {
                            first_line_scoped = k;
                            break;
                        }
                    }
                    if (first_line_scoped >= 0) {
                        close_spans(sb, stack, first_line_scoped, CLOSE_LINE_END);
                    }
                    sb.append("<BR/>");
                    i += c == '\n' ? 1 : 2;
                    continue;
                }
                string? marker = marker_at(text, i);
                if (marker != null) {
                    string kind = "m" + marker;
                    int open_at = find_span(stack, kind);
                    if (open_at >= 0) {
                        close_spans(sb, stack, open_at, CLOSE_ONE);
                        i += 2;
                        continue;
                    }
                    if (closes_on_line(text, i + 2, marker)) {
                        var span = new Span();
                        span.kind = kind;
                        span.line_scoped = true;
                        switch (marker) {
                            case "**": span.open_tag = "<b>"; span.close_tag = "</b>"; break;
                            case "//": span.open_tag = "<i>"; span.close_tag = "</i>"; break;
                            case "--": span.open_tag = "<s>"; span.close_tag = "</s>"; break;
                            case "\"\"":
                                span.open_tag = "<font face=\"monospace\">";
                                span.close_tag = "</font>";
                                break;
                            default: span.open_tag = "<u>"; span.close_tag = "</u>"; break;
                        }
                        push_span(sb, stack, span);
                        i += 2;
                        continue;
                    }
                }
                if (c == '~' && i + 1 < n && "*/\"-_~<[\\=".index_of_char(text[i + 1]) >= 0) {
                    append_escaped_char(sb, text[i + 1]);
                    i += 2;
                    continue;
                }
                if (c == '<') {
                    int used = html_tag(text, i, sb, stack, allow_images);
                    if (used > 0) {
                        i += used;
                        continue;
                    }
                }
                if (c == '[' && i + 1 < n && text[i + 1] == '[') {
                    int close = text.index_of("]]", i + 2);
                    if (close > i + 2) {
                        string inner = text.substring(i + 2, close - i - 2).strip();
                        int space = inner.index_of_char(' ');
                        int brace = inner.index_of_char('{');
                        string shown = space > 0 ? inner.substring(space + 1).strip() : inner;
                        if (brace >= 0 && space < 0) {
                            shown = inner.substring(0, brace);
                        }
                        sb.append(xml_escape(shown));
                        i = close + 2;
                        continue;
                    }
                }
                append_escaped_char(sb, c);
                i++;
            }
            if (stack.size > 0) {
                close_spans(sb, stack, 0, CLOSE_ALL);
            }
            return sb.str;
        }

        // An HTML tag at `i`: applied and its length returned, or 0 when it is text
        private int html_tag(string text, int i, StringBuilder sb, Gee.ArrayList<Span> stack, bool allow_images) {
            MatchInfo mi;
            string rest = text.substring(i);
            if (!tag_regex.match(rest, 0, out mi)) {
                return 0;
            }
            int used = mi.fetch(0).length;
            bool closing = mi.fetch(1) == "/";
            string name = mi.fetch(2).down();
            string? value = mi.fetch(3);
            string kind;
            switch (name) {
                case "b": case "i": case "u": case "s": case "sub": case "sup":
                    kind = name;
                    break;
                case "strike": case "del":
                    kind = "s";
                    break;
                case "w":
                    kind = "u";
                    break;
                case "color": case "size": case "font": case "back":
                    kind = name;
                    break;
                case "br":
                    sb.append("<BR/>");
                    return used;
                case "img":
                    if (closing) {
                        return used;
                    }
                    string src = value ?? "";
                    try {
                        MatchInfo sm;
                        if (new Regex("src\\s*=\\s*\"?([^\"\\s>]+)").match(src, 0, out sm)) {
                            src = sm.fetch(1);
                        }
                    } catch (RegexError e) {
                        return used;
                    }
                    src = src.strip();
                    if (allow_images && !src.contains("://") && src.length > 0 &&
                        FileUtils.test(src, FileTest.IS_REGULAR)) {
                        var open_spans = new Gee.ArrayList<Span>();
                        open_spans.add_all(stack);
                        if (stack.size > 0) {
                            close_spans(sb, stack, 0, CLOSE_ALL);
                        }
                        sb.append("\x01%d\x01".printf(image_paths.size));
                        image_paths.add(src);
                        foreach (var s in open_spans) {
                            push_span(sb, stack, s);
                        }
                    }
                    return used;
                default:
                    return 0;
            }
            if (closing) {
                int at = find_span(stack, kind);
                if (at < 0) {
                    return 0;
                }
                close_spans(sb, stack, at, CLOSE_ONE);
                return used;
            }
            var span = new Span();
            span.kind = kind;
            span.line_scoped = false;
            span.open_tag = "";
            span.close_tag = "";
            switch (kind) {
                case "b": case "i": case "u": case "s": case "sub": case "sup":
                    if (find_span(stack, kind) >= 0 && kind != "sub" && kind != "sup") {
                        // already open: PlantUML does not nest it
                        return used;
                    }
                    span.open_tag = "<%s>".printf(kind);
                    span.close_tag = "</%s>".printf(kind);
                    break;
                case "color":
                    string? col = html_color(value);
                    if (col != null) {
                        span.open_tag = "<font color=\"%s\">".printf(col);
                        span.close_tag = "</font>";
                    }
                    break;
                case "size":
                    int64 size = 0;
                    if (value != null && int64.try_parse(value.strip(), out size) && size > 0 && size < 200) {
                        span.open_tag = "<font point-size=\"%d\">".printf((int) size);
                        span.close_tag = "</font>";
                    }
                    break;
                case "font":
                    var attrs = new StringBuilder();
                    MatchInfo? am = null;
                    if (value != null && font_attr_regex.match(value, 0, out am)) {
                        while (am.matches()) {
                            string an = am.fetch(1).down();
                            string av = am.fetch(2);
                            if (an == "color") {
                                string? col = html_color(av);
                                if (col != null) {
                                    attrs.append(" color=\"%s\"".printf(col));
                                }
                            } else if (an == "size") {
                                int64 size = 0;
                                if (int64.try_parse(av, out size) && size > 0 && size < 200) {
                                    attrs.append(" point-size=\"%d\"".printf((int) size));
                                }
                            } else if (an == "face" || an == "name") {
                                attrs.append(" face=\"%s\"".printf(xml_escape(av)));
                            }
                            try {
                                am.next();
                            } catch (RegexError e) {
                                break;
                            }
                        }
                    }
                    if (attrs.len > 0) {
                        span.open_tag = "<font%s>".printf(attrs.str);
                        span.close_tag = "</font>";
                    }
                    break;
                default:
                    // <back:X>: Graphviz has no text background
                    break;
            }
            push_span(sb, stack, span);
            return used;
        }

        // A creole_html() result as table cells: text runs (lines left-aligned together) and
        // image cells
        private string html_cells(string html, string balign = "LEFT") {
            if (!html.contains("\x01")) {
                return "<TD BALIGN=\"%s\">%s</TD>".printf(balign, html);
            }
            var sb = new StringBuilder();
            string[] parts = html.split("\x01");
            for (int k = 0; k < parts.length; k++) {
                if (k % 2 == 1) {
                    int idx = int.parse(parts[k]);
                    if (idx >= 0 && idx < image_paths.size) {
                        sb.append("<TD><IMG SRC=\"%s\"/></TD>".printf(xml_escape(image_paths[idx])));
                    }
                } else if (parts[k].length > 0) {
                    sb.append("<TD BALIGN=\"%s\">%s</TD>".printf(balign, parts[k]));
                }
            }
            return sb.len > 0 ? sb.str : "<TD></TD>";
        }

        // Text lines left-aligned with each other, the block centred in its node
        private string text_block(string html) {
            return "<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR>%s</TR></TABLE>".printf(
                html_cells(html));
        }

        // Text that needs no HTML label: no markup, no escapes, one line
        private bool is_plain_text(string text) {
            if (text.contains("\\") || text.contains("\n")) {
                return false;
            }
            return creole_html(text) == xml_escape(text);
        }

        // "<< text >>" in a message is «text»
        private static string guillemets(string text) {
            try {
                return new Regex("<<\\s*(.*?)\\s*>>").replace(text, -1, 0, "«\\1»");
            } catch (RegexError e) {
                return text;
            }
        }

        // Cairo "toy" text width in points of plain text at `size`
        private static double text_width(string text, double size) {
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
            var cr = new Cairo.Context(surface);
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size(size);
            Cairo.TextExtents ext;
            cr.text_extents(text, out ext);
            return ext.x_advance;
        }

        // "skinparam maxMessageSize N": words wrapped onto lines of at most N points
        private string wrap_message(string text, int max_width) {
            var out_lines = new StringBuilder();
            string normalized = text.replace("\\\\", "\x02").replace("\\n", "\n").replace("\x02", "\\\\");
            foreach (string line in normalized.split("\n")) {
                if (out_lines.len > 0) {
                    out_lines.append("\n");
                }
                var cur_line = new StringBuilder();
                foreach (string word in line.split(" ")) {
                    if (word.length == 0) {
                        continue;
                    }
                    if (cur_line.len > 0) {
                        string candidate = cur_line.str + " " + word;
                        if (text_width(RenderUtils.strip_inline_creole(candidate), 11) > max_width) {
                            out_lines.append(cur_line.str);
                            out_lines.append("\n");
                            cur_line.truncate(0);
                        } else {
                            cur_line.append(" ");
                        }
                    }
                    cur_line.append(word);
                }
                out_lines.append(cur_line.str);
            }
            return out_lines.str;
        }

        /**
         * A message label node's attributes, null when there is no text. Plain text keeps a
         * simple label; Creole, several lines or an autonumber make an HTML label: the number
         * (formatted, bold by default) in its own cell, the lines left-aligned beside it.
         */
        private string? message_label_attrs(Message msg, SkinParams skin, string font_color) {
            string text = guillemets(msg.label ?? "");
            string? max_size = skin.get_global("maxmessagesize");
            int64 max_w = 0;
            if (max_size != null && int64.try_parse(max_size.strip(), out max_w) && max_w > 0) {
                text = wrap_message(text, (int) max_w);
            }
            bool numbered = msg.number_text != null;
            if (!numbered && text.strip().length == 0) {
                return null;
            }
            if (!numbered && is_plain_text(text)) {
                return text_attrs(pad_label(text), 11, font_color, true);
            }
            var cells = new StringBuilder("<TD WIDTH=\"6\"></TD>");
            if (numbered) {
                cells.append("<TD>%s</TD>".printf(creole_html(msg.number_text)));
                if (text.strip().length > 0) {
                    cells.append("<TD WIDTH=\"4\"></TD>");
                }
            }
            if (text.strip().length > 0) {
                // "skinparam sequenceMessageAlign right|center": the lines align that way too
                string? align = skin.get_global("sequencemessagealign");
                string balign = "LEFT";
                if (align != null && align.strip().down() == "right") {
                    balign = "RIGHT";
                } else if (align != null && align.strip().down() == "center") {
                    balign = "CENTER";
                }
                cells.append(html_cells(creole_html(text, true), balign));
            }
            cells.append("<TD WIDTH=\"6\"></TD>");
            return html_text_attrs("<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR>%s</TR></TABLE>".printf(cells.str),
                                   11, font_color);
        }

        // ---- Arrow ends ----

        /**
         * The Graphviz arrow at one end of a message. `written` is the end as written ("<",
         * ">>", "\\", "//", ...), `deco` "o" / "x" / "". Half heads keep the side PlantUML
         * draws: a right-hand "\\" or left-hand "/" is the upper half, the others the lower
         * one, whichever way the arrow points on the page. "x" is drawn separately (cross).
         */
        private static string end_arrow(string written, string deco, bool head_end, bool points_right,
                                         bool right_hand) {
            string shape;
            switch (written) {
                case ">": case "<":
                    shape = "normal";
                    break;
                case ">>": case "<<":
                    shape = "open";
                    break;
                case "\\": case "/": case "\\\\": case "//":
                    bool upper = right_hand ? written[0] == '\\' : written[0] == '/';
                    // "l" keeps the half left of the edge's direction: above it when it points right
                    bool left_half = upper == points_right;
                    shape = (left_half ? "l" : "r") + (written.length == 2 ? "vee" : "normal");
                    break;
                default:
                    shape = head_end && deco.length == 0 ? "normal" : "none";
                    break;
            }
            if (deco == "x") {
                return "none";
            }
            if (deco == "o") {
                return shape == "none" ? "dot" : "dot" + shape;
            }
            return shape;
        }

        // ---- Participants ----

        // Sentinel fills in HTML labels that render_to_svg replaces: spots (#01F2kk) and
        // participant icons (#01F3kk)
        private Gee.ArrayList<string> spot_marks = new Gee.ArrayList<string>();    // "C|#ADD1B2"
        private Gee.ArrayList<string> icon_marks = new Gee.ArrayList<string>();    // "kind|fill|stroke"
        // Node ids drawn as stacked boxes / horizontal cylinders
        private Gee.HashMap<string, string> box_kinds = new Gee.HashMap<string, string>();

        // The "(C,#ADD1B2)" spot cell of a participant, "" without one
        private string spot_cell(Participant p) {
            if (p.spot_char == null) {
                return "";
            }
            string color = html_color(p.spot_color) ?? "#ADD1B2";
            int idx = spot_marks.size;
            spot_marks.add("%s|%s".printf(p.spot_char, color));
            return "<TD FIXEDSIZE=\"TRUE\" WIDTH=\"20\" HEIGHT=\"20\" BGCOLOR=\"#01F2%02X\"> </TD><TD WIDTH=\"4\"></TD>".printf(idx % 256);
        }

        // The body of "participant P [ ... ]" as table rows: "=" headings, "----" rules
        private string body_rows(Gee.ArrayList<string> lines, string? stereotype_html, bool stereotype_bottom) {
            var groups = new Gee.ArrayList<string>();
            var cur_group = new StringBuilder();
            foreach (string raw in lines) {
                string t = raw.strip();
                bool rule = t.length >= 2 && (t.replace("-", "").length == 0 || t.replace("=", "").length == 0 ||
                                              t.replace(".", "").length == 0 || t.replace("_", "").length == 0);
                if (rule) {
                    if (cur_group.len > 0) {
                        groups.add(cur_group.str);
                        cur_group.truncate(0);
                    }
                    continue;
                }
                int level = 0;
                while (level < t.length && t[level] == '=') {
                    level++;
                }
                string line_html;
                if (level > 0) {
                    int size = 14 + int.max(1, 5 - level);
                    line_html = "<b><font point-size=\"%d\">%s</font></b>".printf(size, creole_html(t.substring(level).strip()));
                } else {
                    line_html = creole_html(t);
                }
                if (cur_group.len > 0) {
                    cur_group.append("<BR/>");
                }
                cur_group.append(line_html);
            }
            if (cur_group.len > 0) {
                groups.add(cur_group.str);
            }
            if (groups.size == 0) {
                groups.add(" ");
            }
            var sb = new StringBuilder();
            for (int k = 0; k < groups.size; k++) {
                if (k > 0) {
                    sb.append("<HR/>");
                }
                string cell = groups[k];
                if (k == 0 && stereotype_html != null && !stereotype_bottom) {
                    cell = stereotype_html + "<BR/>" + cell;
                }
                if (k == groups.size - 1 && stereotype_html != null && stereotype_bottom) {
                    cell = cell + "<BR/>" + stereotype_html;
                }
                sb.append("<TR><TD>%s</TD></TR>".printf(cell));
            }
            return sb.str;
        }

        // Icon size (points) of the kinds drawn above their name
        private static bool icon_kind(ParticipantType t, out string kind, out int w, out int h) {
            switch (t) {
                case ParticipantType.BOUNDARY: kind = "boundary"; w = 40; h = 28; return true;
                case ParticipantType.CONTROL: kind = "control"; w = 28; h = 30; return true;
                case ParticipantType.ENTITY: kind = "entity"; w = 28; h = 30; return true;
                default: kind = ""; w = 0; h = 0; return false;
            }
        }

        // A participant head (`foot` false) or foot box. "participant Bob <<foo>>" draws «foo»
        // above the name and takes "skinparam participant { BackgroundColor<<foo>> red }"
        // colours (per participant kind; an inline #colour still wins), as PlantUML does.
        // Names, stereotypes and bodies are Creole text.
        private string participant_attrs(Participant p, bool foot, SkinParams skin, string default_fill,
                                         string default_border, string? default_font) {
            string element = participant_element(p.participant_type);
            string? stereo_fill = skin.get_stereotype_property(element, "BackgroundColor", p.stereotype);
            string? stereo_border = skin.get_stereotype_property(element, "BorderColor", p.stereotype);
            string? stereo_font = skin.get_stereotype_property(element, "FontColor", p.stereotype);

            string color = default_fill;
            string? inline_color = normalize_color(p.color);
            if (inline_color != null) {
                color = inline_color;
            } else if (stereo_fill != null) {
                color = RenderUtils.sanitize_color(stereo_fill);
            }

            string? stereo_html = participant_stereotype_html(p, skin);
            // "skinparam stereotypePosition bottom" puts the stereotype under the name
            bool stereo_bottom = false;
            string? stereo_position = skin.get_global("stereotypeposition");
            if (stereo_position != null && stereo_position.strip().down() == "bottom") {
                stereo_bottom = true;
            }

            string border = default_border;
            if (stereo_border != null) {
                border = RenderUtils.sanitize_color(stereo_border);
            }
            string part_font;
            if (stereo_font != null) {
                part_font = RenderUtils.sanitize_color(stereo_font);
            } else if (default_font != null) {
                part_font = RenderUtils.sanitize_color(default_font);
            } else {
                part_font = RenderUtils.contrast_text(color);
            }

            // "participant P [ =Title ---- ""Sub"" ]": a box of rows with rules between them
            if (p.body_lines != null) {
                string spot = spot_cell(p);
                string table = "<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">%s</TABLE>".printf(
                    color, border, body_rows(p.body_lines, stereo_html, stereo_bottom));
                if (spot.length > 0) {
                    table = "<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR>%s<TD>%s</TD></TR></TABLE>".printf(spot, table);
                }
                return "label=<%s>, shape=plaintext, style=solid, fontcolor=\"%s\"".printf(table, part_font);
            }

            string name_text = p.display_label ?? p.name;
            string name_html = creole_html(name_text);

            // Actors are stick figures in PlantUML ("skinparam actorStyle awesome" / "hollow"
            // draw other figures); they were octagons. The figure is drawn in the SVG step
            // (RenderUtils.draw_actor_figures); the text sits on the diagram background.
            if (p.participant_type == ParticipantType.ACTOR) {
                string style_class = "";
                string? actor_style = skin.get_global("actorstyle");
                if (actor_style != null) {
                    string st = actor_style.strip().down();
                    if (st == "awesome") {
                        style_class = " gdawesome";
                    } else if (st == "hollow") {
                        style_class = " gdhollow";
                    }
                }
                string? above = null;
                string below = name_html;
                if (stereo_html != null) {
                    if (stereo_bottom) {
                        below = below + "<BR/>" + stereo_html;
                    } else {
                        above = stereo_html;
                    }
                }
                string actor_text;
                if (stereo_font != null) {
                    actor_text = RenderUtils.sanitize_color(stereo_font);
                } else {
                    actor_text = RenderUtils.contrast_text(label_bg);
                }
                return RenderUtils.actor_figure_attrs(above, below, color, border, style_class, actor_text);
            }

            var text = new StringBuilder();
            if (stereo_html != null && !stereo_bottom) {
                text.append(stereo_html);
                text.append("<BR/>");
            }
            text.append(name_html);
            if (stereo_html != null && stereo_bottom) {
                text.append("<BR/>");
                text.append(stereo_html);
            }
            string spot = spot_cell(p);

            // Boundary, control and entity: an icon, the name below it (above it at the foot)
            string kind;
            int iw, ih;
            if (icon_kind(p.participant_type, out kind, out iw, out ih)) {
                int idx = icon_marks.size;
                icon_marks.add("%s|%s|%s".printf(kind, color, border));
                string icon_row = "<TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"%d\" BGCOLOR=\"#01F3%02X\"> </TD></TR>".printf(
                    iw, ih, idx % 256);
                string icon_text = stereo_font != null ? RenderUtils.sanitize_color(stereo_font)
                                                       : RenderUtils.contrast_text(label_bg);
                string name_row = spot.length > 0
                    ? "<TR><TD><TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR>%s<TD><FONT COLOR=\"%s\">%s</FONT></TD></TR></TABLE></TD></TR>".printf(spot, icon_text, text.str)
                    : "<TR><TD><FONT COLOR=\"%s\">%s</FONT></TD></TR>".printf(icon_text, text.str);
                return "shape=none, style=solid, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"1\">%s%s</TABLE>>".printf(
                    foot ? name_row : icon_row, foot ? icon_row : name_row);
            }

            string shape = get_participant_shape(p.participant_type);
            string label;
            if (spot.length > 0) {
                label = "<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR>%s<TD>%s</TD></TR></TABLE>>".printf(
                    spot, text.str);
            } else if (stereo_html == null && !name_text.replace("\\n", "").contains("\\") &&
                       name_html == xml_escape(name_text).replace("\\n", "<BR/>")) {
                // plain text lines keep a plain label
                label = "\"%s\"".printf(RenderUtils.escape_label(name_text));
            } else {
                label = "<%s>".printf(text.str);
            }
            string extra = "";
            if (p.participant_type == ParticipantType.COLLECTIONS || p.participant_type == ParticipantType.QUEUE) {
                // room for the second box / the cylinder ends drawn in render_to_svg
                extra = ", margin=\"0.16,0.06\"";
            }
            return "label=%s, shape=%s, style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\"%s".printf(
                label, shape, color, border, part_font, extra);
        }

        // ---- SVG post-processing ----

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

        private static string f(double v) {
            return num(v, "%.2f");
        }

        private static string svg_color(string c) {
            return xml_escape(c);
        }

        /**
         * Draws what Graphviz has no shape for, over the placeholders generate_dot() left:
         * stereotype spots (a coloured circle with its letter), boundary / control / entity
         * icons, the second box of collections and the cylinder of queues. Delay segments of
         * lifelines get denser dots than Graphviz' "dotted".
         */
        private uint8[] draw_sequence_shapes(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            try {
                var sentinel = new Regex("<polygon fill=\"#01[Ff]([23])([0-9A-Fa-f]{2})\" stroke=\"none\" points=\"([^\"]*)\"/>");
                svg = sentinel.replace_eval(svg, -1, 0, 0, (m, result) => {
                    bool spot = m.fetch(1) == "2";
                    int idx = (int) int64.parse("0x" + m.fetch(2));
                    double[]? b = points_box(m.fetch(3));
                    var marks = spot ? spot_marks : icon_marks;
                    if (b == null || idx >= marks.size) {
                        return false;
                    }
                    string[] parts = marks[idx].split("|");
                    double cx = (b[0] + b[2]) / 2;
                    double cy = (b[1] + b[3]) / 2;
                    if (spot) {
                        double r = double.min(b[2] - b[0], b[3] - b[1]) / 2 - 1;
                        string letter_color = RenderUtils.contrast_text(parts[1]);
                        result.append("<circle class=\"gdspot\" cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" stroke=\"#181818\" stroke-width=\"1\"/>".printf(
                            f(cx), f(cy), f(r), svg_color(parts[1])));
                        result.append("<text class=\"gdspot\" text-anchor=\"middle\" x=\"%s\" y=\"%s\" font-family=\"Sans\" font-weight=\"bold\" font-size=\"%s\" fill=\"%s\">%s</text>".printf(
                            f(cx), f(cy + r * 0.45), f(r * 1.3), svg_color(letter_color), xml_escape(parts[0])));
                        return false;
                    }
                    string fill = svg_color(parts[1]);
                    string stroke = svg_color(parts[2]);
                    double h = b[3] - b[1];
                    double r = h * 0.38;
                    string paint = "fill=\"%s\" stroke=\"%s\" stroke-width=\"1.3\"".printf(fill, stroke);
                    switch (parts[0]) {
                        case "boundary":
                            // a vertical bar joined to a circle
                            double ccx = b[2] - r - 1;
                            double bar_x = b[0] + 2;
                            result.append("<path class=\"gdicon\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.3\" d=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/>".printf(
                                stroke, f(bar_x), f(cy - r), f(bar_x), f(cy + r), f(bar_x), f(cy), f(ccx - r), f(cy)));
                            result.append("<circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/>".printf(f(ccx), f(cy), f(r), paint));
                            break;
                        case "control":
                            // a circle with an arrowhead on top, pointing counter-clockwise
                            double ccy = cy + 2;
                            result.append("<circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/>".printf(f(cx), f(ccy), f(r), paint));
                            double ty = ccy - r;
                            result.append("<path class=\"gdicon\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.6\" d=\"M%s,%s L%s,%s L%s,%s\"/>".printf(
                                stroke, f(cx + 4), f(ty - 5), f(cx - 1), f(ty), f(cx + 4), f(ty + 5)));
                            break;
                        default:
                            // entity: a circle on a line
                            double ecy = cy - 2;
                            result.append("<circle class=\"gdicon\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s/>".printf(f(cx), f(ecy), f(r), paint));
                            result.append("<path class=\"gdicon\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.3\" d=\"M%s,%s L%s,%s\"/>".printf(
                                stroke, f(cx - r), f(ecy + r + 3), f(cx + r), f(ecy + r + 3)));
                            break;
                    }
                    return false;
                });

                foreach (var entry in box_kinds.entries) {
                    string title = Markup.escape_text(entry.key).replace("-", "&#45;");
                    var node = new Regex("(<title>%s</title>\\s*)<polygon fill=\"([^\"]*)\" stroke=\"([^\"]*)\" points=\"([^\"]*)\"/>".printf(
                        Regex.escape_string(title)));
                    string kind = entry.value;
                    svg = node.replace_eval(svg, -1, 0, 0, (m, result) => {
                        double[]? b = points_box(m.fetch(4));
                        result.append(m.fetch(1));
                        if (b == null) {
                            result.append(m.fetch(0).substring(m.fetch(1).length));
                            return false;
                        }
                        string paint = "fill=\"%s\" stroke=\"%s\"".printf(m.fetch(2), m.fetch(3));
                        if (kind == "collections") {
                            // a second box behind, offset up and to the right
                            double d = 4;
                            result.append("<polygon class=\"gdicon\" %s points=\"%s,%s %s,%s %s,%s %s,%s %s,%s\"/>".printf(
                                paint, f(b[0] + d), f(b[1] - d), f(b[2] + d), f(b[1] - d), f(b[2] + d), f(b[3] - d),
                                f(b[0] + d), f(b[3] - d), f(b[0] + d), f(b[1] - d)));
                            result.append("<polygon %s points=\"%s,%s %s,%s %s,%s %s,%s %s,%s\"/>".printf(
                                paint, f(b[0]), f(b[1]), f(b[2]), f(b[1]), f(b[2]), f(b[3]), f(b[0]), f(b[3]), f(b[0]), f(b[1])));
                        } else {
                            // a horizontal cylinder: round ends, the right one's front edge drawn
                            double ry = (b[3] - b[1]) / 2;
                            double rx = double.min(6, (b[2] - b[0]) / 4);
                            result.append("<path class=\"gdicon\" %s d=\"M%s,%s L%s,%s A%s,%s 0 0 1 %s,%s L%s,%s A%s,%s 0 0 1 %s,%s Z\"/>".printf(
                                paint, f(b[0] + rx), f(b[1]), f(b[2] - rx), f(b[1]), f(rx), f(ry), f(b[2] - rx), f(b[3]),
                                f(b[0] + rx), f(b[3]), f(rx), f(ry), f(b[0] + rx), f(b[1])));
                            result.append("<path class=\"gdicon\" fill=\"none\" stroke=\"%s\" d=\"M%s,%s A%s,%s 0 0 0 %s,%s\"/>".printf(
                                m.fetch(3), f(b[2] - rx), f(b[1]), f(rx), f(ry), f(b[2] - rx), f(b[3])));
                        }
                        return false;
                    });
                }
                // Delay segments: dots close enough to read as a dotted lifeline
                svg = svg.replace("stroke-dasharray=\"1,5\"", "stroke-dasharray=\"1,3\"");
            } catch (RegexError e) {
                warning("Failed to draw sequence shapes: %s", e.message);
                return svg_data;
            }
            return svg.data;
        }
        public uint8[]? render_to_svg(SequenceDiagram diagram) {
            string dot = generate_dot(diagram);

            // Parse DOT into graph
            var graph = RenderUtils.read_dot(dot);
            if (graph == null) {
                warning("Failed to parse DOT graph");
                return null;
            }

            // Layout
            // The positions are fixed in the DOT: "nop2" keeps them and only routes the edges
            int ret = context.layout(graph, "nop2");
            if (ret != 0) {
                warning("Failed to layout graph with engine: %s", layout_engine);
                return null;
            }

            // Render to SVG using ABI-compatible wrapper
            // (patched Graphviz uses size_t for length, VAPI declares unsigned int)
            uint8[] svg_data;
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return draw_sequence_shapes(RenderUtils.draw_actor_figures(svg_data));
        }

        public Cairo.ImageSurface? render_to_surface(SequenceDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                // Load SVG with librsvg
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                // Build element line number map from participants. The DOT
                // node ids for lifelines are synthesized as "<id>_top" and
                // "<id>_bottom" — register those too so their click regions
                // resolve to the participant's source line.
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var participant in diagram.participants) {
                    if (participant.source_line > 0) {
                        element_lines.set(participant.name, participant.source_line);
                        element_lines.set(participant.name + "_top", participant.source_line);
                        element_lines.set(participant.name + "_bottom", participant.source_line);
                        if (participant.alias != null) {
                            element_lines.set(participant.alias, participant.source_line);
                            element_lines.set(participant.alias + "_top", participant.source_line);
                            element_lines.set(participant.alias + "_bottom", participant.source_line);
                        }
                    }
                }

                // Parse SVG regions for click-to-source navigation (with pixel scaling)
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, width, height);

                // Create Cairo surface
                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                // White background
                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                // Render SVG
                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(SequenceDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(SequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(SequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
