/* TimingDiagramRenderer.vala — renders PlantUML timing diagrams as waveforms
 *
 * Graphviz cannot lay out a timeline, so this renderer writes SVG directly and
 * reuses the shared SVG → surface/PNG/PDF path. The geometry is a port of
 * PlantUML's own timing layout (TimingRuler, Panels*, TimeArrow,
 * TimeConstraint, Highlight, TimingNote): a shared time ruler whose tick unit is
 * the highest common factor of all times (or `scale N as M pixels`), one lane per
 * participant with its framed title, and per-type waveforms.
 */
namespace GDiagram {

/** Text metrics shared by the timing renderer (Cairo, unhinted metrics, px). */
public class TimingTextMetrics : Object {
    private static Cairo.Context? cr = null;

    private static unowned Cairo.Context context(double size, bool bold, bool serif) {
        if (cr == null) {
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
            cr = new Cairo.Context(surface);
            var opts = new Cairo.FontOptions();
            opts.set_hint_metrics(Cairo.HintMetrics.OFF);
            opts.set_hint_style(Cairo.HintStyle.NONE);
            cr.set_font_options(opts);
        }
        cr.select_font_face(serif ? "serif" : "sans-serif", Cairo.FontSlant.NORMAL,
                            bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
        cr.set_font_size(size);
        return cr;
    }

    public static double line_width(string text, double size, bool bold, bool serif = false) {
        if (text.length == 0) return 0;
        Cairo.TextExtents te;
        context(size, bold, serif).text_extents(text, out te);
        return te.x_advance;
    }

    public static double ascent(double size, bool bold, bool serif = false) {
        Cairo.FontExtents fe;
        context(size, bold, serif).font_extents(out fe);
        return fe.ascent;
    }

    public static double line_height(double size, bool bold, bool serif = false) {
        Cairo.FontExtents fe;
        context(size, bold, serif).font_extents(out fe);
        return fe.ascent + fe.descent;
    }

    public static double width(string text, double size, bool bold, bool serif = false) {
        double w = 0;
        foreach (var l in text.split("\n")) w = double.max(w, line_width(l, size, bold, serif));
        return w;
    }

    public static double height(string text, double size, bool bold, bool serif = false) {
        return text.split("\n").length * line_height(size, bold, serif);
    }
}

public class TimingDiagramRenderer : Object {
    private Gee.ArrayList<ElementRegion> regions;

    // PlantUML layout constants (Panels, TimingDiagram)
    private const double MARGIN = 20;        // document margin
    private const double MARGIN_X1 = 5;      // TimingDiagram.marginX1
    private const double MARGIN_Y = 8;       // Panels.MARGIN_Y
    private const double PANEL_MARGIN_X = 12;
    private const double BOTTOM_MARGIN = 10;
    private const double LEFT_MIN = 5;
    private const double HIST_INITIAL = 40;  // PanelsRobust.HISTOGRAM_INITIAL_WIDTH

    // Font sizes (plantuml.skin timingDiagram section)
    private const double TITLE_FONT = 14;    // player title, bold
    private const double STATE_FONT = 12;    // concise/robust/binary
    private const double RECT_FONT = 14;     // rectangle/analog (inherit 14 bold)
    private const double AXIS_FONT = 11;
    private const double ARROW_FONT = 14;    // serif
    private const double CONSTRAINT_FONT = 12;
    private const double NOTE_FONT = 13;
    private const double CAPTION_FONT = 12;

    // Theme colours resolved per render
    private string c_bg;
    private string c_line;
    private string c_text;
    private string c_wave;
    private string c_concise_fill;
    private string c_rect_fill;
    private string c_arrow;
    private string c_constraint;
    private string c_highlight;
    private string c_note_fill;
    private string c_title;

    // Current layout
    private TimingDiagram diagram;
    private StringBuilder sb;
    private Gee.ArrayList<Lane> lanes;
    private double part1;
    private double x0;             // x of time min
    private double top;            // y of the first frame
    private double inner_height;   // sum of lanes
    private double width_total;    // part1 + ruler + margins

    // Ruler
    private double r_min;
    private double r_max;
    private double tick_unit;
    private double tick_px;
    private bool forced_scale;

    /** Per-participant layout. */
    private class Lane : Object {
        public TimingSignal sig;
        public double frame_y;
        public double frame_h;
        public double panel_y;
        public double panel_h;
        // State/robust changes (sorted; first wins at equal time)
        public Gee.ArrayList<SignalStateChange> changes;
        // Robust
        public Gee.ArrayList<string> all_states;
        public string? initial;
        public int ribbon;
        public int height;
    }

    public TimingDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.regions = regions;
    }

    // ── Public API (kept compatible with the Graphviz renderers) ──────────

    /**
     * Timing diagrams are drawn directly as SVG; the DOT output is a plain
     * summary graph (one node per participant) for the `-f dot` export path.
     */
    public string generate_dot(TimingDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var d = new StringBuilder();
        d.append("digraph timing {\n");
        d.append("    // Timing diagrams render as SVG waveforms; this graph lists the participants.\n");
        d.append("    bgcolor=\"%s\"\n".printf(palette.background));
        d.append("    rankdir=TB\n");
        d.append("    node [shape=plaintext fontname=\"Sans\" fontsize=11 fontcolor=\"%s\"]\n".printf(palette.node_text));
        if (diagram.signals.size == 0) {
            d.append("    empty [label=\"(no signals defined)\"]\n}\n");
            return d.str;
        }
        int i = 0;
        string? prev = null;
        foreach (var sig in diagram.signals) {
            string id = "s%d".printf(i++);
            string kind = sig.signal_type.to_string().replace("GDIAGRAM_SIGNAL_TYPE_", "").down();
            d.append("    %s [label=\"%s (%s, %d changes)\"]\n".printf(id,
                RenderUtils.escape_label(sig.display_name()), kind, sig.state_changes.size));
            if (prev != null) d.append("    %s -> %s [style=invis]\n".printf(prev, id));
            prev = id;
        }
        d.append("}\n");
        return d.str;
    }

    public uint8[]? render_to_svg(TimingDiagram diagram) {
        string svg = build_svg(diagram);
        uint8[] data = svg.data;
        return data;
    }

    public Cairo.ImageSurface? render_to_surface(TimingDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(TimingDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(TimingDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(TimingDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }

    // ── Geometry accessors (valid after render_to_svg; used by tests) ─────

    /** Absolute SVG x of a time. */
    public double time_to_x(double t) { return x0 + pos(t); }
    /** Pixels per tick and time units per tick of the last layout. */
    public double get_tick_unit() { return tick_unit; }
    public double get_tick_pixels() { return tick_px; }
    /** Absolute y of a lane's panel top / frame top, by participant code. */
    public double lane_panel_y(string code) {
        foreach (var l in lanes) if (l.sig.alias_name == code) return l.panel_y;
        return -1;
    }
    public double lane_frame_y(string code) {
        foreach (var l in lanes) if (l.sig.alias_name == code) return l.frame_y;
        return -1;
    }

    // ── Layout ─────────────────────────────────────────────────────────────

    private string build_svg(TimingDiagram d) {
        this.diagram = d;
        resolve_colors();
        setup_ruler();

        lanes = new Gee.ArrayList<Lane>();
        foreach (var sig in d.signals) lanes.add(build_lane(sig));

        part1 = 0;
        foreach (var l in lanes) part1 = double.max(part1, left_panel_width(l));

        double title_h = 0, title_w = 0;
        string? title = (d.title != null && d.title.strip().length > 0) ? clean_text(d.title) : null;
        if (title != null) {
            title_h = TimingTextMetrics.height(title, TITLE_FONT, true);
            title_w = TimingTextMetrics.width(title, TITLE_FONT, true);
        }
        top = MARGIN + (title != null ? title_h + 21 : 0);

        double y = top;
        foreach (var l in lanes) {
            l.frame_y = y;
            l.frame_h = frame_height(l);
            l.panel_y = y + l.frame_h;
            l.panel_h = panel_height(l);
            y = l.panel_y + l.panel_h;
        }
        inner_height = y - top;
        x0 = MARGIN + MARGIN_X1 + part1;
        width_total = part1 + ruler_width() + MARGIN_X1 * 2;

        double axis_h = TimingTextMetrics.line_height(AXIS_FONT, false);
        double content_w = double.max(width_total, title_w);
        int svg_w = (int) (MARGIN + content_w + MARGIN) + 1;
        int svg_h = (int) (top + inner_height + axis_h + MARGIN) + 1;

        sb = new StringBuilder();
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"%dpx\" height=\"%dpx\" viewBox=\"0 0 %d %d\">\n"
            .printf(svg_w, svg_h, svg_w, svg_h));
        sb.append("<rect x=\"0\" y=\"0\" width=\"%d\" height=\"%d\" fill=\"%s\"/>\n".printf(svg_w, svg_h, c_bg));
        sb.append("<g font-family=\"sans-serif\">\n");

        if (title != null) {
            draw_text(title, MARGIN + (content_w - title_w) / 2 - 0.5, MARGIN, TITLE_FONT, true, c_title);
        }

        regions.clear();
        foreach (var l in lanes) {
            regions.add(new ElementRegion(l.sig.alias_name, l.sig.source_line, MARGIN, l.frame_y,
                                          width_total, l.frame_h + l.panel_h));
        }

        // Lane background colours
        foreach (var l in lanes) {
            if (l.sig.back_color != null) {
                string c = color(l.sig.back_color);
                rect(MARGIN, l.frame_y, width_total, l.frame_h + l.panel_h, c, c, 0.5);
            }
        }
        if (!d.compact_mode) {
            line(MARGIN, top, MARGIN, top + inner_height, c_line, 0.5);
            line(MARGIN + width_total, top, MARGIN + width_total, top + inner_height, c_line, 0.5);
        }
        foreach (var h in d.highlights) {
            double a = pos(h.from_time), b = pos(h.to_time);
            string fill = h.back_color != null ? color(h.back_color) : c_highlight;
            sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"none\"/>\n".printf(
                f(x0 + a), f(top), f(b - a), f(inner_height), fill));
        }
        draw_grid();

        foreach (var l in lanes) {
            if (!l.sig.compact) line(MARGIN, l.frame_y, MARGIN + width_total, l.frame_y, c_line, 0.5);
            draw_frame_title(l);
            draw_left_panel(l);
            draw_right_panel(l);
        }

        draw_time_axis();
        foreach (var msg in d.messages) draw_message(msg);
        foreach (var h in d.highlights) {
            double a = x0 + pos(h.from_time), b = x0 + pos(h.to_time);
            string lc = h.line_color != null ? color(h.line_color) : c_line;
            dashed_line(a, top, a, top + inner_height, lc, 2, "4,4");
            dashed_line(b, top, b, top + inner_height, lc, 2, "4,4");
            if (h.caption != null) draw_text(clean_text(h.caption), a + 3, top + 2, CAPTION_FONT, false, text_on(h.back_color));
        }

        sb.append("</g>\n</svg>\n");
        return sb.str;
    }

    private void resolve_colors() {
        var p = ThemeManager.get_active_palette();
        c_bg = p.background;
        c_line = p.node_border;
        c_text = p.node_text;
        c_title = p.node_text;
        // PlantUML: darkgreen on light, lightgreen on dark — pull the theme green toward the text colour
        c_wave = mix(p.success, p.node_text, 0.35);
        c_concise_fill = mix(p.background, p.accent_primary, 0.12);
        c_rect_fill = mix(p.background, p.node_text, 0.06);
        c_arrow = p.accent_primary;
        c_constraint = p.warning;
        c_highlight = p.grid;
        c_note_fill = mix(p.background, p.accent_secondary, 0.14);
    }

    // ── Ruler (TimingRuler) ────────────────────────────────────────────────

    private Gee.ArrayList<double?> ruler_times() {
        var list = new Gee.ArrayList<double?>();
        foreach (var t in diagram.times) list.add(t);
        if (list.size == 0) list.add(0);
        if (list[list.size - 1] > 0 && list[0] < 0) {
            list.add(0);
            list.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
        }
        return list;
    }

    private void setup_ruler() {
        var times = ruler_times();
        r_min = times[0];
        r_max = times[times.size - 1];
        tick_px = diagram.scale_pixels > 0 ? (double) diagram.scale_pixels : 50;
        forced_scale = diagram.scale_ticks > 0;
        if (forced_scale) {
            tick_unit = (double) diagram.scale_ticks;
            return;
        }
        int64 hcf = -1;
        foreach (var t in times) {
            int64 v = (int64) t;
            if (v < 0) v = -v;
            if (v <= 0) continue;
            hcf = hcf == -1 ? v : gcd(hcf, v);
        }
        if (hcf <= 0) hcf = 1;
        double range = r_max - r_min;
        if (hcf == 1 && (range + 1) * tick_px > 4000) {
            tick_unit = Math.round(1 + tick_px * range / 4000.0);
        } else {
            tick_unit = (double) hcf;
        }
        // Guard against absurd surfaces (e.g. dates without `scale`): PlantUML
        // itself only applies the 4000 px fallback when the HCF is 1.
        if ((range / tick_unit + 1) * tick_px > 30000) {
            tick_unit = Math.ceil(tick_px * range / 30000.0);
        }
    }

    private static int64 gcd(int64 a, int64 b) {
        int64 r = a;
        while (r != 0) {
            r = a % b;
            a = b;
            b = r;
        }
        return a < 0 ? -a : a;
    }

    private double ruler_width() {
        return ((r_max - r_min) / tick_unit + 1) * tick_px;
    }

    private double pos(double t) {
        return (t - r_min) / tick_unit * tick_px;
    }

    private int nb_ticks() {
        int64 delta = (int64) r_max - (int64) r_min;
        int64 n = 1 + (int64) (delta / tick_unit);
        return (int) int64.min(1000, n);
    }

    private void draw_grid() {
        int nb = nb_ticks();
        for (int i = 0; i <= nb; i++) {
            double x = x0 + tick_px * i;
            dashed_line(x, top, x, top + inner_height, c_line, 0.5, "3,5");
        }
    }

    private void draw_time_axis() {
        if (diagram.hide_time_axis) return;
        double y = top + inner_height;
        double w = ruler_width();
        double first = 0;
        foreach (var t in ruler_times()) {
            if (t >= 0) { first = pos(t); break; }
        }
        int nb = 0;
        if (diagram.manual_time_axis) {
            while (first + nb * tick_px <= w) nb++;
            if (nb > 0) line(x0 + first, y, x0 + first + (nb - 1) * tick_px, y, c_line, 2);
            foreach (var t in ruler_times()) {
                double x = x0 + pos(t);
                line(x, y, x, y + 5, c_line, 2);
                string label = manual_label(t);
                if (label.length == 0) continue;
                double lw = TimingTextMetrics.width(label, AXIS_FONT, false);
                draw_text(label, x - lw / 2, y + 6, AXIS_FONT, false, c_text);
            }
            return;
        }
        while (first + nb * tick_px <= w && nb < 100000) {
            double x = x0 + first + nb * tick_px;
            line(x, y, x, y + 5, c_line, 2);
            nb++;
        }
        if (nb > 0) line(x0 + first, y, x0 + first + (nb - 1) * tick_px, y, c_line, 2);

        var rounds = new Gee.TreeSet<int64?>((a, b) => {
            int64 x = a, z = b;
            return x < z ? -1 : (x > z ? 1 : 0);
        });
        if (!forced_scale) {
            foreach (var t in ruler_times()) rounds.add((int64) t);
        } else {
            int n = nb_ticks();
            for (int i = 0; i <= n; i++) rounds.add((int64) (tick_unit * i) + (int64) r_min);
        }
        if (rounds.first() < 0 && rounds.last() > 0) rounds.add(0);
        foreach (var r in rounds) {
            string label = format_time((double) r);
            double lw = TimingTextMetrics.width(label, AXIS_FONT, false);
            draw_text(label, x0 + pos((double) r) - lw / 2, y + 6, AXIS_FONT, false, c_text);
        }
    }

    private string manual_label(double t) {
        foreach (var e in diagram.anchors.entries) {
            if (e.value == t) return e.key;
        }
        return format_time(t);
    }

    /** Formats a ruler time per TimingFormat (decimal, h:mm:ss, mm/dd or `use date format`). */
    public string format_time(double t) {
        if (diagram.time_format == TimingTimeFormat.DECIMAL && diagram.date_format == null) {
            if (t == Math.floor(t) && Math.fabs(t) < 1e15) return ((int64) t).to_string();
            return plain_number(t);
        }
        int64 secs = (int64) t;
        if (diagram.date_format != null) return format_date(secs, diagram.date_format);
        if (diagram.time_format == TimingTimeFormat.HOUR) {
            int64 s = secs % 60;
            int64 m = (secs / 60) % 60;
            int64 h = secs / 3600;
            return "%s:%02d:%02d".printf(h.to_string(), (int) m, (int) s);
        }
        var dt = new DateTime.from_unix_utc(secs);
        if (dt == null) return secs.to_string();
        return "%02d/%02d".printf(dt.get_month(), dt.get_day_of_month());
    }

    /** Subset of java.text.SimpleDateFormat (y, M, d, H, h, m, s, E, a, quoted text). */
    private static string format_date(int64 secs, string pattern) {
        var dt = new DateTime.from_unix_utc(secs);
        if (dt == null) return secs.to_string();
        string[] months = { "January", "February", "March", "April", "May", "June", "July",
                            "August", "September", "October", "November", "December" };
        string[] days = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
        var out_sb = new StringBuilder();
        int i = 0;
        while (i < pattern.length) {
            char ch = pattern[i];
            if (ch == '\'') {
                int j = pattern.index_of_char('\'', i + 1);
                if (j < 0) j = pattern.length;
                if (j == i + 1) out_sb.append_c('\'');
                else out_sb.append(pattern.substring(i + 1, j - i - 1));
                i = j + 1;
                continue;
            }
            if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'))) {
                out_sb.append_c(ch);
                i++;
                continue;
            }
            int n = 1;
            while (i + n < pattern.length && pattern[i + n] == ch) n++;
            switch (ch) {
                case 'y':
                case 'Y':
                    if (n == 2) out_sb.append("%02d".printf(dt.get_year() % 100));
                    else out_sb.append("%0*d".printf(n, dt.get_year()));
                    break;
                case 'M':
                    if (n >= 4) out_sb.append(months[dt.get_month() - 1]);
                    else if (n == 3) out_sb.append(months[dt.get_month() - 1].substring(0, 3));
                    else out_sb.append("%0*d".printf(n, dt.get_month()));
                    break;
                case 'd': out_sb.append("%0*d".printf(n, dt.get_day_of_month())); break;
                case 'H': out_sb.append("%0*d".printf(n, dt.get_hour())); break;
                case 'h': {
                    int h12 = dt.get_hour() % 12;
                    out_sb.append("%0*d".printf(n, h12 == 0 ? 12 : h12));
                    break;
                }
                case 'm': out_sb.append("%0*d".printf(n, dt.get_minute())); break;
                case 's': out_sb.append("%0*d".printf(n, dt.get_second())); break;
                case 'E': {
                    string day = days[dt.get_day_of_week() - 1];
                    out_sb.append(n >= 4 ? day : day.substring(0, 3));
                    break;
                }
                case 'a': out_sb.append(dt.get_hour() < 12 ? "AM" : "PM"); break;
                default: out_sb.append(pattern.substring(i, n)); break;
            }
            i += n;
        }
        return out_sb.str;
    }

    // ── Lanes ──────────────────────────────────────────────────────────────

    private Lane build_lane(TimingSignal sig) {
        var l = new Lane();
        l.sig = sig;
        l.changes = sig.sorted_changes();
        l.initial = sig.initial_state != null ? sig.initial_state.state : null;
        l.ribbon = sig.suggested_height == 0 ? 24 : sig.suggested_height;
        switch (sig.signal_type) {
            case SignalType.BINARY:
            case SignalType.CLOCK:
                l.height = sig.suggested_height == 0 ? 30 : sig.suggested_height;
                break;
            case SignalType.ANALOG:
                l.height = sig.suggested_height == 0 ? 100 : sig.suggested_height;
                break;
            default:
                l.height = sig.suggested_height;
                break;
        }
        if (sig.signal_type == SignalType.ROBUST) {
            l.all_states = new Gee.ArrayList<string>();
            foreach (var code in sig.state_codes) l.all_states.add(sig.state_labels[code]);
            // PanelsRobust reverses the declared states
            var rev = new Gee.ArrayList<string>();
            for (int i = l.all_states.size - 1; i >= 0; i--) rev.add(l.all_states[i]);
            l.all_states = rev;
            if (l.initial != null && !l.all_states.contains(l.initial)) l.all_states.add(l.initial);
            foreach (var c in l.changes) {
                if (c.is_hidden()) continue;
                foreach (var s in c.states) {
                    if (!l.all_states.contains(s)) l.all_states.add(s);
                }
            }
        }
        return l;
    }

    private string frame_title(Lane l) {
        return clean_text(l.sig.label);
    }

    private double frame_height(Lane l) {
        string t = frame_title(l);
        double h = t.strip().length == 0 ? 0 : TimingTextMetrics.height(t, TITLE_FONT, true);
        return l.sig.compact ? h - 1 : h + 1;
    }

    private void draw_frame_title(Lane l) {
        string t = frame_title(l);
        if (t.strip().length == 0) return;
        double x = MARGIN + MARGIN_X1;
        draw_text(t, x, l.frame_y, TITLE_FONT, true, text_on(l.sig.back_color));
        if (l.sig.compact) return;
        double w = TimingTextMetrics.width(t, TITLE_FONT, true) + 1;
        double h = TimingTextMetrics.height(t, TITLE_FONT, true) + 1;
        line(MARGIN, l.frame_y + h, x + w, l.frame_y + h, c_line, 0.5);
        line(x + w, l.frame_y + h, x + w + 10, l.frame_y, c_line, 0.5);
    }

    private double state_font(Lane l) {
        return l.sig.signal_type == SignalType.RECTANGLE ? RECT_FONT : STATE_FONT;
    }

    private double left_panel_width(Lane l) {
        switch (l.sig.signal_type) {
            case SignalType.ROBUST: {
                double w = robust_states_width(l);
                return l.initial != null ? w + HIST_INITIAL : w;
            }
            case SignalType.CONCISE:
            case SignalType.RECTANGLE:
                return initial_width(l);
            case SignalType.ANALOG: {
                current_analog = l;
                double w;
                if (l.sig.ticks_every <= 0) {
                    w = double.max(analog_label_width(analog_min(l)), analog_label_width(analog_max(l)));
                } else {
                    w = 0;
                    int first = (int) Math.ceil(analog_min(l));
                    int last = (int) Math.floor(analog_max(l));
                    for (int i = first; i <= last && i - first < 10000; i++) {
                        if (i % l.sig.ticks_every == 0) w = double.max(w, analog_label_width(i));
                    }
                }
                current_analog = null;
                return LEFT_MIN + w;
            }
            default:
                return LEFT_MIN;
        }
    }

    private double panel_height(Lane l) {
        switch (l.sig.signal_type) {
            case SignalType.ROBUST: {
                double h = robust_constraints_height(l);
                if (l.all_states.size > 0) h += robust_step(l) * (l.all_states.size - 1);
                return h + 12 + 6;
            }
            case SignalType.CONCISE:
            case SignalType.RECTANGLE:
                return state_constraints_height(l) + top_comment_height(l) + notes_height(l, TimingNotePosition.TOP)
                    + l.ribbon + notes_height(l, TimingNotePosition.BOTTOM) + BOTTOM_MARGIN;
            case SignalType.BINARY:
                return constraints_height(l) + notes_height(l, TimingNotePosition.TOP) + l.height
                    + notes_height(l, TimingNotePosition.BOTTOM);
            case SignalType.CLOCK:
                return l.height;
            case SignalType.ANALOG:
                return constraints_height(l) + l.height;
            default:
                return 0;
        }
    }

    private void draw_left_panel(Lane l) {
        double base_x = MARGIN + MARGIN_X1;
        if (l.sig.signal_type == SignalType.ROBUST) {
            double width = robust_states_width(l);
            if (l.initial != null) width += HIST_INITIAL;
            double dx = part1 > width + 5 ? part1 - width - 5 : part1 - width;
            double y0 = l.panel_y + robust_constraints_height(l);
            foreach (var s in l.all_states) {
                string label = clean_text(s);
                draw_text(label, base_x + dx, y0 + robust_y(l, s) - TimingTextMetrics.height(label, STATE_FONT, false) / 2 + 1,
                          STATE_FONT, false, text_on(l.sig.back_color));
            }
        } else if (l.sig.signal_type == SignalType.ANALOG) {
            if (l.sig.ticks_every <= 0) {
                draw_analog_label(l, analog_min(l));
                draw_analog_label(l, analog_max(l));
            } else {
                int first = (int) Math.ceil(analog_min(l));
                int last = (int) Math.floor(analog_max(l));
                for (int i = first; i <= last && i - first < 10000; i++) {
                    if (i % l.sig.ticks_every == 0) draw_analog_label(l, i);
                }
            }
        }
    }

    private void draw_right_panel(Lane l) {
        switch (l.sig.signal_type) {
            case SignalType.ROBUST: draw_robust(l); break;
            case SignalType.CONCISE:
            case SignalType.RECTANGLE: draw_state(l); break;
            case SignalType.BINARY: draw_binary(l); break;
            case SignalType.CLOCK: draw_clock(l); break;
            case SignalType.ANALOG: draw_analog(l); break;
        }
    }

    // ── Constraints / notes (Panels) ───────────────────────────────────────

    private double constraint_height(TimingConstraint c) {
        string label = clean_text(c.label ?? "");
        return TimingTextMetrics.height(label, CONSTRAINT_FONT, false) + 5;
    }

    private double constraints_height(Lane l) {
        double result = 0;
        foreach (var c in l.sig.constraints) {
            double dy = l.sig.signal_type == SignalType.ROBUST ? robust_constraint_dy(l, c) : 0;
            result = double.max(result, constraint_height(c) - dy);
        }
        return result;
    }

    private double state_constraints_height(Lane l) {
        return double.max(5, constraints_height(l));
    }

    private double robust_constraints_height(Lane l) {
        return double.max(10, constraints_height(l));
    }

    private double constraint_margin(Lane l) {
        switch (l.sig.signal_type) {
            case SignalType.ROBUST:
            case SignalType.BINARY:
                return 2.5;
            default:
                return 1;
        }
    }

    /** TimeConstraint.drawU with the constraint line at absolute y. */
    private void draw_constraint(Lane l, TimingConstraint c, double y) {
        string col = c.color != null ? color(c.color) : c_constraint;
        double m = constraint_margin(l);
        double x1 = x0 + pos(c.time1) + m;
        double x2 = x0 + pos(c.time2) - m;
        if (x2 - x1 > 20) {
            line(x1 + 3, y, x2 - 3, y, col, 1.5);
            arrow_head(x1, y, false, col);
            arrow_head(x2, y, true, col);
        } else {
            line(x1 - 1, y, x2 + 1, y, col, 1.5);
            arrow_head(x1, y, true, col);
            arrow_head(x2, y, false, col);
        }
        string label = clean_text(c.label ?? "");
        if (label.length > 0) {
            double w = TimingTextMetrics.width(label, CONSTRAINT_FONT, false);
            // The label keeps the style font colour; only the arrow takes [#color]
            draw_text(label, x1 + (x2 - x1 - w) / 2, y - constraint_height(c), CONSTRAINT_FONT, false, c_constraint);
        }
    }

    private void arrow_head(double x, double y, bool right, string col) {
        double dx = right ? -8 : 8;
        sb.append("<polygon points=\"%s,%s %s,%s %s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1\"/>\n".printf(
            f(x + dx), f(y + 4), f(x + dx), f(y - 4), f(x), f(y), col, col));
    }

    private double note_box_width(TimingNote n) {
        return TimingTextMetrics.width(clean_text(n.text), NOTE_FONT, true) + 21;
    }

    private double note_box_height(TimingNote n) {
        return TimingTextMetrics.height(clean_text(n.text), NOTE_FONT, true) + 10;
    }

    private double notes_height(Lane l, TimingNotePosition p) {
        double h = 0;
        foreach (var n in l.sig.notes) {
            if (n.position == p) h = double.max(h, note_box_height(n) + 10);
        }
        return h;
    }

    private void draw_notes(Lane l, TimingNotePosition p, double y) {
        foreach (var n in l.sig.notes) {
            if (n.position != p) continue;
            double x = x0 + (n.has_time ? pos(n.time) : 0);
            double ny = p == TimingNotePosition.BOTTOM ? y + 5 : y;
            double w = note_box_width(n), h = note_box_height(n);
            sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"0.5\"/>\n".printf(
                f(x), f(ny), f(x), f(ny + h), f(x + w), f(ny + h), f(x + w), f(ny + 10), f(x + w - 10), f(ny), f(x), f(ny),
                c_note_fill, c_line));
            sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"0.5\"/>\n".printf(
                f(x + w - 10), f(ny), f(x + w - 10), f(ny + 10), f(x + w), f(ny + 10), f(x + w - 10), f(ny),
                c_note_fill, c_line));
            draw_text(clean_text(n.text), x + 6, ny + 5, NOTE_FONT, true, c_text);
        }
    }

    // ── Robust (PanelsRobust) ──────────────────────────────────────────────

    private double robust_states_width(Lane l) {
        double w = 0;
        foreach (var s in l.all_states) w = double.max(w, TimingTextMetrics.width(clean_text(s), STATE_FONT, false));
        return w;
    }

    private double robust_step(Lane l) {
        if (l.height == 0 || l.all_states.size <= 1) return 20;
        return (double) (l.height / (l.all_states.size - 1));
    }

    private double robust_y(Lane l, string state) {
        int nb = l.all_states.size - 1 - l.all_states.index_of(state);
        return robust_step(l) * nb;
    }

    /** PanelsRobust.getStatesAt */
    private string[] robust_states_at(Lane l, double t) {
        if (l.changes.size == 0) return {};
        for (int i = 0; i < l.changes.size; i++) {
            double w = l.changes[i].time;
            if (w == t) {
                if (i == 0 && l.initial == null) return { l.changes[i].state };
                if (i == 0) return { l.initial, l.changes[i].state };
                return { l.changes[i - 1].state, l.changes[i].state };
            }
            if (w > t) return { l.changes[i == 0 ? 0 : i - 1].state };
        }
        return { l.changes[l.changes.size - 1].state };
    }

    private double robust_y_at(Lane l, double t) {
        var st = robust_states_at(l, t);
        if (st.length == 0) return 0;
        return robust_y(l, st[st.length - 1]);
    }

    private double robust_constraint_dy(Lane l, TimingConstraint c) {
        double y = robust_y_at(l, c.time1);
        foreach (var ch in l.changes) {
            if (c.time1 < ch.time && c.time2 > ch.time) y = double.min(y, robust_y_at(l, ch.time));
        }
        return y;
    }

    private double[] robust_points_y(Lane l, int n) {
        var st = l.changes[n].states;
        if (st.length == 2) return { robust_y(l, st[0]), robust_y(l, st[1]) };
        return { robust_y(l, st[0]) };
    }

    private void draw_robust(Lane l) {
        if (l.changes.size == 0) return;
        double oy = l.panel_y + robust_constraints_height(l);
        double w = ruler_width();
        var ch = l.changes;
        int n = ch.size;

        // Horizontal lines
        if (l.initial != null) {
            int npts = robust_points_y(l, 0).length;
            for (int k = 0; k < npts; k++) {
                line(x0 - HIST_INITIAL, oy + robust_y(l, l.initial), x0 + pos(ch[0].time), oy + robust_y(l, l.initial),
                     c_wave, 2);
            }
        }
        for (int i = 0; i < n; i++) {
            if (ch[i].is_hidden()) continue;
            double xa = pos(ch[i].time);
            double x2 = i < n - 1 ? pos(ch[i + 1].time) : w;
            double len = x2 - xa;
            var ys = robust_points_y(l, i);
            if (ys.length == 2) {
                double min_y = double.min(ys[0], ys[1]), max_y = double.max(ys[0], ys[1]);
                string fill = ch[i].back_color != null ? color(ch[i].back_color) : c_concise_fill;
                string stroke = ch[i].line_color != null ? color(ch[i].line_color) : c_wave;
                sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"2\"/>\n".printf(
                    f(x0 + xa), f(oy + min_y), f(len), f(max_y - min_y), fill, stroke));
                for (double dx = 0; dx < len; dx += 5) {
                    line(x0 + xa + dx, oy + min_y, x0 + xa + dx, oy + max_y, stroke, 2);
                }
            }
            if (i < n - 1) {
                foreach (var py in ys) line(x0 + xa, oy + py, x0 + xa + len, oy + py, c_wave, 2);
            }
        }
        if (!ch[n - 1].is_hidden()) {
            double xa = pos(ch[n - 1].time);
            foreach (var py in robust_points_y(l, n - 1)) line(x0 + xa, oy + py, x0 + w, oy + py, c_wave, 2);
        }

        // Vertical transitions
        if (l.initial != null) {
            double cx = x0 + pos(ch[0].time);
            line(cx, oy + robust_points_y(l, 0)[0], cx, oy + robust_y(l, l.initial), c_wave, 2);
        }
        for (int i = 1; i < n; i++) {
            if (ch[i - 1].is_hidden() || ch[i].is_hidden()) continue;
            var a = robust_points_y(l, i);
            var b = robust_points_y(l, i - 1);
            double min_y = double.min(min_of(a), min_of(b));
            double max_y = double.max(max_of(a), max_of(b));
            double cx = x0 + pos(ch[i].time);
            line(cx, oy + min_y, cx, oy + max_y, c_wave, 2);
        }

        // Comments
        foreach (var c in ch) {
            if (c.comment == null) continue;
            string text = clean_text(c.comment);
            double py = robust_y(l, c.states[0]);
            draw_text(text, x0 + pos(c.time) + 2, oy + py - TimingTextMetrics.height(text, STATE_FONT, false),
                      STATE_FONT, false, text_on(l.sig.back_color));
        }

        foreach (var c in l.sig.constraints) {
            draw_constraint(l, c, oy - 5 + robust_constraint_dy(l, c));
        }
    }

    private static double min_of(double[] v) {
        double r = v[0];
        foreach (var x in v) r = double.min(r, x);
        return r;
    }

    private static double max_of(double[] v) {
        double r = v[0];
        foreach (var x in v) r = double.max(r, x);
        return r;
    }

    // ── Concise / rectangle (PanelsState) ──────────────────────────────────

    private double initial_width(Lane l) {
        if (l.initial == null) return 0;
        return TimingTextMetrics.width(clean_text(l.initial), state_font(l), true) + 2 * PANEL_MARGIN_X;
    }

    private double top_comment_height(Lane l) {
        double h = 0;
        foreach (var c in l.changes) {
            if (c.comment != null) h = double.max(h, TimingTextMetrics.height(clean_text(c.comment), state_font(l), true));
        }
        return h;
    }

    private void state_colors(Lane l, SignalStateChange c, out string fill, out string stroke) {
        bool rect_type = l.sig.signal_type == SignalType.RECTANGLE;
        fill = c.back_color != null ? color(c.back_color) : (rect_type ? c_rect_fill : c_concise_fill);
        stroke = c.line_color != null ? color(c.line_color) : (rect_type ? c_line : c_wave);
    }

    private double state_stroke(Lane l) {
        return l.sig.signal_type == SignalType.RECTANGLE ? 0.5 : 1.5;
    }

    private void draw_state(Lane l) {
        double hc = state_constraints_height(l);
        double ry = l.panel_y + hc + top_comment_height(l) + notes_height(l, TimingNotePosition.TOP);
        double rh = l.ribbon;
        double w = ruler_width();
        double sw = state_stroke(l);
        bool rect_type = l.sig.signal_type == SignalType.RECTANGLE;
        var ch = l.changes;
        double fs = state_font(l);
        double text_h = TimingTextMetrics.line_height(fs, true);

        // Before-zero (initial) state
        if (l.initial != null) {
            double iw = initial_width(l);
            string fill, stroke;
            if (ch.size == 0) {
                var init = l.sig.initial_state;
                state_colors(l, init, out fill, out stroke);
                double xs = x0 - iw, len = iw + w;
                if (init.is_flat()) {
                    line(xs, ry + rh / 2, xs + len, ry + rh / 2, stroke, sw);
                } else {
                    sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                        f(xs), f(ry), f(len), f(rh), fill, fill, f(sw)));
                    line(xs, ry, xs + len, ry, stroke, sw);
                    line(xs, ry + rh, xs + len, ry + rh, stroke, sw);
                }
            } else {
                // Context of the first change, overridden by the initial colours
                state_colors(l, ch[0], out fill, out stroke);
                if (l.sig.initial_state.back_color != null) fill = color(l.sig.initial_state.back_color);
                if (l.sig.initial_state.line_color != null) stroke = color(l.sig.initial_state.line_color);
                double xs = x0 - iw, len = iw + pos(ch[0].time);
                if (l.sig.initial_state.is_flat()) {
                    line(xs, ry + rh / 2, xs + len, ry + rh / 2, stroke, sw);
                } else if (rect_type) {
                    penta_rect(xs, ry, len, rh, fill, stroke, sw, true);
                } else {
                    penta(xs, ry, len, rh, fill, stroke, sw, true);
                }
            }
            if (!l.sig.initial_state.is_flat()) {
                string label = clean_text(l.initial);
                double lw = TimingTextMetrics.width(label, fs, true);
                string? init_fill = l.sig.initial_state.back_color ?? (ch.size > 0 ? ch[0].back_color : null);
                draw_text(label, x0 - PANEL_MARGIN_X - lw, ry + rh / 2 - text_h / 2, fs, true, text_on(init_fill));
            }
        }

        // States
        for (int i = 0; i < ch.size; i++) {
            double a = pos(ch[i].time);
            bool last = i == ch.size - 1;
            double b = last ? w : pos(ch[i + 1].time);
            string fill, stroke;
            state_colors(l, ch[i], out fill, out stroke);
            if (ch[i].is_flat()) {
                line(x0 + a, ry + rh / 2, x0 + b, ry + rh / 2, stroke, sw);
            } else if (!ch[i].is_hidden()) {
                if (!last) {
                    if (rect_type) {
                        sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                            f(x0 + a), f(ry), f(b - a), f(rh), fill, stroke, f(sw)));
                    } else {
                        hexa(x0 + a, ry, b - a, rh, fill, stroke, sw);
                    }
                } else if (rect_type) {
                    penta_rect(x0 + a, ry, b - a, rh, fill, stroke, sw, false);
                } else {
                    penta(x0 + a, ry, b - a, rh, fill, stroke, sw, false);
                }
            }
        }

        // Labels and comments
        for (int i = 0; i < ch.size; i++) {
            var c = ch[i];
            double x = x0 + pos(c.time);
            if (!c.is_blank() && !c.is_hidden() && !c.is_flat()) {
                string label = clean_text(c.state);
                double lw = TimingTextMetrics.width(label, fs, true);
                double lh = TimingTextMetrics.height(label, fs, true);
                double xt = i == ch.size - 1 ? x + PANEL_MARGIN_X : (x + x0 + pos(ch[i + 1].time)) / 2 - lw / 2;
                draw_text(label, xt, ry + rh / 2 - lh / 2, fs, true, text_on(c.back_color));
            }
            if (c.comment != null) {
                string text = clean_text(c.comment);
                draw_text(text, x + PANEL_MARGIN_X, ry - TimingTextMetrics.height(text, fs, true), fs, true, text_on(l.sig.back_color));
            }
        }

        foreach (var c in l.sig.constraints) draw_constraint(l, c, l.panel_y + hc / 2);
        draw_notes(l, TimingNotePosition.TOP, l.panel_y);
        draw_notes(l, TimingNotePosition.BOTTOM, l.panel_y + hc + rh + notes_height(l, TimingNotePosition.TOP));
    }

    private void hexa(double x, double y, double w, double h, string fill, string stroke, double sw) {
        sb.append("<polygon points=\"%s,%s %s,%s %s,%s %s,%s %s,%s %s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"miter\"/>\n".printf(
            f(x + 12), f(y), f(x + w - 12), f(y), f(x + w), f(y + h / 2), f(x + w - 12), f(y + h),
            f(x + 12), f(y + h), f(x), f(y + h / 2), fill, stroke, f(sw)));
    }

    /** PentaAShape (initial, open on the left) / PentaBShape (last, open on the right). */
    private void penta(double x, double y, double w, double h, string fill, string stroke, double sw, bool a_shape) {
        if (a_shape) {
            sb.append("<polygon points=\"%s,%s %s,%s %s,%s %s,%s %s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                f(x), f(y), f(x + w - 12), f(y), f(x + w), f(y + h / 2), f(x + w - 12), f(y + h), f(x), f(y + h),
                fill, fill, f(sw)));
            sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                f(x), f(y), f(x + w - 12), f(y), f(x + w), f(y + h / 2), f(x + w - 12), f(y + h), f(x), f(y + h),
                stroke, f(sw)));
        } else {
            sb.append("<polygon points=\"%s,%s %s,%s %s,%s %s,%s %s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                f(x + 12), f(y), f(x + w), f(y), f(x + w), f(y + h), f(x + 12), f(y + h), f(x), f(y + h / 2),
                fill, fill, f(sw)));
            sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                f(x + w), f(y), f(x + 12), f(y), f(x), f(y + h / 2), f(x + 12), f(y + h), f(x + w), f(y + h),
                stroke, f(sw)));
        }
    }

    private void penta_rect(double x, double y, double w, double h, string fill, string stroke, double sw, bool a_shape) {
        sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
            f(x), f(y), f(w), f(h), fill, fill, f(sw)));
        if (a_shape) {
            sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                f(x), f(y), f(x + w), f(y), f(x + w), f(y + h), f(x), f(y + h), stroke, f(sw)));
        } else {
            sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
                f(x + w), f(y), f(x), f(y), f(x), f(y + h), f(x + w), f(y + h), stroke, f(sw)));
        }
    }

    // ── Binary (PanelsBinary) ──────────────────────────────────────────────

    private static bool binary_high(string s) {
        return s == "1" || s.down() == "high";
    }

    /** Sorted binary values; a later change at the same time replaces an earlier one. */
    private Gee.ArrayList<SignalStateChange> last_wins(Gee.ArrayList<SignalStateChange> changes) {
        var result = new Gee.ArrayList<SignalStateChange>();
        foreach (var c in changes) {
            int idx = -1;
            for (int i = 0; i < result.size; i++) if (result[i].time == c.time) { idx = i; break; }
            if (idx >= 0) {
                result[idx] = c;
                continue;
            }
            int p = result.size;
            while (p > 0 && result[p - 1].time > c.time) p--;
            result.insert(p, c);
        }
        return result;
    }

    private double binary_yhigh(Lane l) {
        return l.panel_y + MARGIN_Y + constraints_height(l) + notes_height(l, TimingNotePosition.TOP);
    }

    private double binary_ylow(Lane l) {
        return l.panel_y + constraints_height(l) + notes_height(l, TimingNotePosition.TOP) + l.height - MARGIN_Y;
    }

    private static string binary_key(string[] states) {
        var k = new StringBuilder();
        foreach (var s in states) k.append(binary_high(s) ? "1" : "0");
        return k.str;
    }

    private void draw_binary(Lane l) {
        double yh = binary_yhigh(l), yl = binary_ylow(l);
        double lastx = 0;
        string[] last_values = l.sig.initial_state != null ? l.sig.initial_state.states : new string[] { "0" };
        foreach (var v in last_wins(l.sig.state_changes)) {
            double x = pos(v.time);
            if (last_values.length == 1) {
                double y = binary_high(last_values[0]) ? yh : yl;
                line(x0 + lastx, y, x0 + x, y, c_wave, 2);
            } else {
                for (double tx = lastx; tx < x; tx += 5) line(x0 + tx, yh, x0 + tx, yl, c_wave, 2);
            }
            if (binary_key(last_values) != binary_key(v.states)) line(x0 + x, yh, x0 + x, yl, c_wave, 2);
            if (v.comment != null) draw_text(clean_text(v.comment), x0 + x + 2, yh, STATE_FONT, false, text_on(l.sig.back_color));
            lastx = x;
            last_values = v.states;
        }
        double ly = binary_high(last_values[0]) ? yh : yl;
        line(x0 + lastx, ly, x0 + ruler_width(), ly, c_wave, 2);
        foreach (var c in l.sig.constraints) draw_constraint(l, c, l.panel_y + constraints_height(l));
        draw_notes(l, TimingNotePosition.TOP, l.panel_y + MARGIN_Y);
        draw_notes(l, TimingNotePosition.BOTTOM, l.panel_y + constraints_height(l)
                   + notes_height(l, TimingNotePosition.TOP) + l.height - MARGIN_Y / 2);
    }

    // ── Clock (PanelsClock) ────────────────────────────────────────────────

    private double clock_pulse(TimingSignal s) {
        return s.clock_pulse == 0 ? s.clock_period / 2.0 : s.clock_pulse;
    }

    private bool clock_high_at(TimingSignal s, double t) {
        if (s.clock_period <= 0) return false;
        if (t < s.clock_offset) return false;
        double phase = Math.fmod(t - s.clock_offset, s.clock_period);
        if (phase < 0) phase += s.clock_period;
        return phase < clock_pulse(s);
    }

    private void clock_hline(double y, double t1, double t2) {
        double a = pos(t1);
        double b = double.min(ruler_width(), pos(t2));
        line(x0 + a, y, x0 + b, y, c_wave, 1.5);
    }

    private void draw_clock(Lane l) {
        var s = l.sig;
        double yh = l.panel_y + MARGIN_Y;
        double yl = yh + (l.height - 2 * MARGIN_Y);
        double w = ruler_width();
        if (s.clock_period <= 0) return;
        double value = 0;
        if (s.clock_offset != 0) {
            clock_hline(yl, value, s.clock_offset);
            value += s.clock_offset;
        }
        if (pos(value) > w) return;
        line(x0 + pos(value), yh, x0 + pos(value), yl, c_wave, 1.5);
        double vpulse = clock_pulse(s);
        double remain = s.clock_period - vpulse;
        for (int i = 0; i < 1000; i++) {
            clock_hline(yh, value, value + vpulse);
            value += vpulse;
            if (pos(value) > w) return;
            line(x0 + pos(value), yh, x0 + pos(value), yl, c_wave, 1.5);
            clock_hline(yl, value, value + remain);
            value += remain;
            if (pos(value) > w) return;
            line(x0 + pos(value), yh, x0 + pos(value), yl, c_wave, 1.5);
        }
    }

    // ── Analog (PanelsAnalog) ──────────────────────────────────────────────

    private Gee.ArrayList<SignalStateChange> analog_series(Lane l) {
        return last_wins(l.sig.state_changes);
    }

    private double analog_min(Lane l) {
        if (l.sig.analog_min != null) return double.parse(l.sig.analog_min);
        double m = 0;
        foreach (var c in l.sig.state_changes) m = double.min(m, double.parse(c.state));
        return m;
    }

    private double analog_max(Lane l) {
        if (l.sig.analog_max != null) return double.parse(l.sig.analog_max);
        double m = 0;
        foreach (var c in l.sig.state_changes) m = double.max(m, double.parse(c.state));
        return m == 0 ? 10 : m;
    }

    private double analog_y(Lane l, double v) {
        double min = analog_min(l), max = analog_max(l);
        double span = max - min;
        double y = span == 0 ? 0 : (v - min) * (l.height - 2 * MARGIN_Y) / span;
        return l.panel_y + constraints_height(l) + l.height - MARGIN_Y - y;
    }

    private double analog_label_width(double v) {
        return TimingTextMetrics.width(analog_display(v), RECT_FONT, true);
    }

    private Lane? current_analog = null;

    private string analog_display(double v) {
        var l = current_analog;
        if (l != null && l.sig.analog_min != null && l.sig.analog_max != null) {
            return deduce_format(l.sig.analog_min, l.sig.analog_max, v);
        }
        return java_double(v);
    }

    private void draw_analog_label(Lane l, double v) {
        current_analog = l;
        string text = analog_display(v);
        double w = TimingTextMetrics.width(text, RECT_FONT, true);
        double h = TimingTextMetrics.height(text, RECT_FONT, true);
        draw_text(text, MARGIN + MARGIN_X1 + part1 - w - 2, analog_y(l, v) - h / 2, RECT_FONT, true, text_on(l.sig.back_color));
        current_analog = null;
    }

    private void draw_analog(Lane l) {
        double w = ruler_width();
        if (l.sig.ticks_every > 0) {
            int first = (int) Math.ceil(analog_min(l));
            int last = (int) Math.floor(analog_max(l));
            for (int i = first; i <= last && i - first < 10000; i++) {
                if (i % l.sig.ticks_every == 0) {
                    double y = analog_y(l, i);
                    dashed_line(x0, y, x0 + w, y, c_line, 0.5, "3,5");
                }
            }
        }
        double lastx = 0;
        double last_value = 0;
        if (l.sig.initial_state != null) {
            last_value = double.parse(l.sig.initial_state.state);
        } else if (l.sig.state_changes.size > 0) {
            last_value = double.parse(l.sig.state_changes[0].state);
        }
        foreach (var c in analog_series(l)) {
            double v = double.parse(c.state);
            double x = pos(c.time);
            line(x0 + lastx, analog_y(l, last_value), x0 + x, analog_y(l, v), c_line, 0.5);
            lastx = x;
            last_value = v;
        }
        line(x0 + lastx, analog_y(l, last_value), x0 + w, analog_y(l, last_value), c_line, 0.5);
        foreach (var c in l.sig.constraints) draw_constraint(l, c, l.panel_y + constraints_height(l));
    }

    private double analog_value_at(Lane l, double t) {
        var series = analog_series(l);
        SignalStateChange? last = null;
        foreach (var c in series) {
            if (c.time == t) return double.parse(c.state);
        }
        foreach (var c in series) {
            if (c.time > t) {
                double v2 = double.parse(c.state);
                if (last == null) return v2;
                double p = (t - last.time) / (c.time - last.time);
                double v1 = double.parse(last.state);
                return v1 + (v2 - v1) * p;
            }
            last = c;
        }
        return last != null ? double.parse(last.state) : 0;
    }

    /** Java Double.toString for typical values. */
    private static string java_double(double v) {
        if (v == Math.floor(v) && Math.fabs(v) < 1e7) {
            return "%s.0".printf(((int64) v).to_string());
        }
        return plain_number(v);
    }

    /** PlantUML DeduceFormat: fraction digits taken from the `between` bounds. */
    private static string deduce_format(string a, string b, double v) {
        int fa = fraction_digits(a), fb = fraction_digits(b);
        int min_frac = int.min(fa, fb), max_frac = int.max(fa, fb);
        char[] buf = new char[64];
        string s = v.format(buf, "%." + max_frac.to_string() + "f");
        if (s.contains(".")) {
            int keep = s.index_of_char('.') + 1 + min_frac;
            while (s.length > keep && s.has_suffix("0")) s = s.substring(0, s.length - 1);
            if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
        }
        return s;
    }

    private static int fraction_digits(string n) {
        int dot = n.index_of_char('.');
        if (dot < 0) dot = n.index_of_char(',');
        return dot < 0 ? 0 : n.length - dot - 1;
    }

    // ── Messages (TimeArrow) ───────────────────────────────────────────────

    /** Time projection of a lane: two candidate points (x, y). */
    private bool projection(Lane l, double t, out double x, out double ya, out double yb) {
        x = x0 + pos(t);
        ya = yb = 0;
        switch (l.sig.signal_type) {
            case SignalType.ROBUST: {
                var st = robust_states_at(l, t);
                if (st.length == 0) return false;
                double base_y = l.panel_y + robust_constraints_height(l);
                ya = base_y + robust_y(l, st[0]);
                yb = base_y + robust_y(l, st[st.length - 1]);
                return true;
            }
            case SignalType.CONCISE:
            case SignalType.RECTANGLE: {
                double y = l.panel_y + state_constraints_height(l) + notes_height(l, TimingNotePosition.TOP)
                    + top_comment_height(l) + l.ribbon / 2.0;
                ya = yb = y;
                foreach (var c in l.changes) {
                    if (c.time == t) return true;
                }
                ya = y - l.ribbon / 2.0;
                yb = y + l.ribbon / 2.0;
                return true;
            }
            case SignalType.BINARY:
                ya = yb = binary_yhigh(l);
                return true;
            case SignalType.CLOCK:
                ya = yb = clock_high_at(l.sig, t) ? l.panel_y + MARGIN_Y : l.panel_y + l.height - MARGIN_Y;
                return true;
            case SignalType.ANALOG:
                ya = yb = analog_y(l, analog_value_at(l, t));
                return true;
        }
        return false;
    }

    private Lane? lane_of(string code) {
        foreach (var l in lanes) if (l.sig.alias_name == code) return l;
        return null;
    }

    private void draw_message(TimingMessage msg) {
        if (msg.from_time.is_nan() || msg.to_time.is_nan()) return;
        var l1 = lane_of(msg.from_signal);
        var l2 = lane_of(msg.to_signal);
        if (l1 == null || l2 == null) return;
        double x1, a1, b1, x2, a2, b2;
        if (!projection(l1, msg.from_time, out x1, out a1, out b1)) return;
        if (!projection(l2, msg.to_time, out x2, out a2, out b2)) return;
        // Shortest of the four combinations (TimeArrow.create)
        double[] s = { a1, a1, b1, b1 };
        double[] e = { a2, b2, a2, b2 };
        int best;
        double[] lens = new double[4];
        for (int i = 0; i < 4; i++) lens[i] = Math.hypot(x2 - x1, e[i] - s[i]);
        // shorter(shorter(1,2), shorter(3,4)) with strict '<' keeping the second on ties
        int p = lens[0] < lens[1] ? 0 : 1;
        int q = lens[2] < lens[3] ? 2 : 3;
        best = lens[p] < lens[q] ? p : q;
        double sy = s[best], ey = e[best];
        string col = msg.color != null ? color(msg.color) : c_arrow;
        line(x1, sy, x2, ey, col, 1.5);
        double angle = Math.atan2(x2 - x1, ey - sy);
        double delta = 20.0 * Math.PI / 180.0;
        double p1x = x2 - Math.sin(angle + delta) * 8, p1y = ey - Math.cos(angle + delta) * 8;
        double p2x = x2 - Math.sin(angle - delta) * 8, p2y = ey - Math.cos(angle - delta) * 8;
        sb.append("<polygon points=\"%s,%s %s,%s %s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.5\"/>\n".printf(
            f(p1x), f(p1y), f(p2x), f(p2y), f(x2), f(ey), col, col));
        if (msg.label != null && msg.label.length > 0) {
            string text = clean_text(msg.label.replace("\\n", "\n"));
            double tx = (p1x + p2x) / 2, ty = (p1y + p2y) / 2;
            if (sy < ey) ty -= TimingTextMetrics.height(text, ARROW_FONT, false, true);
            draw_text(text, tx, ty, ARROW_FONT, false, c_arrow, true);
        }
    }

    // ── SVG primitives ─────────────────────────────────────────────────────

    /** Locale-independent number for SVG attributes. */
    private static string f(double v) {
        if (v.is_nan() || v.is_infinity() != 0) v = 0;
        char[] buf = new char[64];
        string s = v.format(buf, "%.3f");
        if (s.contains(".")) {
            while (s.has_suffix("0")) s = s.substring(0, s.length - 1);
            if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
        }
        if (s == "-0") s = "0";
        return s;
    }

    private static string plain_number(double v) {
        char[] buf = new char[64];
        string s = v.format(buf, "%.10f");
        if (s.contains(".")) {
            while (s.has_suffix("0")) s = s.substring(0, s.length - 1);
            if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
        }
        return s;
    }

    private void line(double x1, double y1, double x2, double y2, string col, double width) {
        sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
            f(x1), f(y1), f(x2), f(y2), col, f(width)));
    }

    private void dashed_line(double x1, double y1, double x2, double y2, string col, double width, string dash) {
        sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-dasharray=\"%s\"/>\n".printf(
            f(x1), f(y1), f(x2), f(y2), col, f(width), dash));
    }

    private void rect(double x, double y, double w, double h, string fill, string stroke, double sw) {
        sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n".printf(
            f(x), f(y), f(w), f(h), fill, stroke, f(sw)));
    }

    /** Draws (multi-line) text with its top-left corner at (x, y). */
    private void draw_text(string text, double x, double y, double size, bool bold, string col, bool serif = false) {
        double asc = TimingTextMetrics.ascent(size, bold, serif);
        double lh = TimingTextMetrics.line_height(size, bold, serif);
        int i = 0;
        foreach (var ln in text.split("\n")) {
            if (ln.length > 0) {
                sb.append("<text x=\"%s\" y=\"%s\" fill=\"%s\" font-size=\"%s\"%s%s xml:space=\"preserve\">%s</text>\n".printf(
                    f(x), f(y + asc + lh * i), col, f(size),
                    bold ? " font-weight=\"700\"" : "",
                    serif ? " font-family=\"serif\"" : "",
                    Markup.escape_text(ln)));
            }
            i++;
        }
    }

    /**
     * Text colour over a fill: the theme text colour on theme fills, a contrasting one
     * on a colour from the source (a light #Gold band stays readable in the dark theme).
     */
    private string text_on(string? user_fill) {
        if (user_fill == null) return c_text;
        string contrast = RenderUtils.contrast_text(color(user_fill));
        bool theme_text_dark = RenderUtils.contrast_text(c_text) == "#FFFFFF";
        bool want_dark = contrast == "#000000";
        return want_dark == theme_text_dark ? c_text : contrast;
    }

    private static string clean_text(string s) {
        return RenderUtils.strip_inline_creole(s.replace("\\n", "\n"));
    }

    /** User colour → SVG colour ("#FF0000" kept, "#LightCyan" → "lightcyan"). */
    private static string color(string c) {
        string s = RenderUtils.sanitize_color(c);
        if (!s.has_prefix("#")) s = s.down();
        return s;
    }

    private static bool parse_hex(string c, out double r, out double g, out double b) {
        r = g = b = 0;
        string h = c.strip();
        if (h.has_prefix("#")) h = h.substring(1);
        if (h.length == 3) h = "%c%c%c%c%c%c".printf(h[0], h[0], h[1], h[1], h[2], h[2]);
        if (h.length < 6) return false;
        int64 v = 0;
        for (int i = 0; i < 6; i++) {
            int d = h[i].xdigit_value();
            if (d < 0) return false;
            v = v * 16 + d;
        }
        r = ((v >> 16) & 0xff) / 255.0;
        g = ((v >> 8) & 0xff) / 255.0;
        b = (v & 0xff) / 255.0;
        return true;
    }

    /** Blend `b` over `a` with weight `t` (both "#RRGGBB"). */
    private static string mix(string a, string b, double t) {
        double ar, ag, ab, br, bg, bb;
        bool ok_a = parse_hex(a, out ar, out ag, out ab);
        bool ok_b = parse_hex(b, out br, out bg, out bb);
        if (!ok_a || !ok_b) return a;
        int r = (int) Math.round((ar + (br - ar) * t) * 255);
        int g = (int) Math.round((ag + (bg - ag) * t) * 255);
        int bl = (int) Math.round((ab + (bb - ab) * t) * 255);
        return "#%02X%02X%02X".printf(r, g, bl);
    }
}

}
