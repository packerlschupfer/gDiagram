/* GanttDiagramRenderer.vala — renders PlantUML gantt charts as a calendar.
 *
 * Graphviz cannot place bars on a time axis, so the chart is written as SVG
 * directly (then the shared SVG → surface/PNG/PDF path). The layout follows
 * PlantUML 1.2026.8: a Start/End/Duration table on the left, a calendar header
 * (month + weekday + day for daily; month + week numbers for weekly; year +
 * month/quarter for monthly/quarterly; years for yearly), closed-day shading,
 * one row per task with the bar from its start to its end day, dependency
 * arrows, milestone diamonds, separators, notes, resource load rows and the
 * calendar repeated below the chart. Colours come from the theme palette.
 */
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

    // ==================== DOT (CLI "-f dot") ====================

    /**
     * The chart itself is drawn without Graphviz; the DOT form lists the
     * scheduled tasks and their dependencies for tools that want a graph.
     */
    public string generate_dot(PumlGanttDiagram diagram) {
        var palette = ThemeManager.get_active_palette();
        var sb = new StringBuilder();
        sb.append("digraph gantt {\n");
        sb.append("    bgcolor=\"%s\"\n".printf(palette.background));
        sb.append("    rankdir=LR\n");
        sb.append("    node [shape=box fontname=\"Sans\" fontsize=11 color=\"%s\" fontcolor=\"%s\"]\n".printf(
            palette.node_border, palette.node_text));
        sb.append("    edge [color=\"%s\"]\n".printf(palette.edge_color));
        if (diagram.title != null && diagram.title.length > 0) {
            sb.append("    label=\"%s\" labelloc=t fontname=\"Sans\" fontcolor=\"%s\"\n".printf(
                RenderUtils.escape_label(diagram.title), palette.node_text));
        }
        var lang = GanttLanguage.for_code(diagram.language);
        int i = 0;
        var ids = new Gee.HashMap<PumlGanttTask, string>();
        foreach (var t in diagram.tasks) {
            string id = "task%d".printf(i++);
            ids[t] = id;
            string when = t.is_milestone
                ? format_date(diagram, lang, t.start_day)
                : "%s - %s".printf(format_date(diagram, lang, t.start_day), format_date(diagram, lang, t.last_day));
            sb.append("    %s [label=\"%s\\n%s\"%s]\n".printf(id, RenderUtils.escape_label(t.name),
                RenderUtils.escape_label(when), t.is_milestone ? " shape=diamond" : ""));
        }
        foreach (var link in diagram.links) {
            if (ids.has_key(link.from) && ids.has_key(link.to)) {
                sb.append("    %s -> %s\n".printf(ids[link.from], ids[link.to]));
            }
        }
        sb.append("}\n");
        return sb.str;
    }

    // ==================== SVG ====================

    public uint8[]? render_to_svg(PumlGanttDiagram diagram) {
        var layout = new GanttLayout(diagram, ThemeManager.get_active_palette());
        string svg = layout.build();
        last_regions.clear();
        foreach (var r in layout.regions) last_regions.add(r);
        return svg.data;
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

    internal static string format_date(PumlGanttDiagram d, GanttLanguage lang, int day) {
        if (!d.is_dated()) return "%s %d".printf(lang.day_word, day - GanttLayout.undated_origin() + 1);
        int y, m, dom;
        GanttScheduler.ymd_from_day(day, out y, out m, out dom);
        return lang.short_date(m, dom);
    }
}

// Month/weekday names and table words for the "language" command
public class GanttLanguage : Object {
    public string start_word;
    public string end_word;
    public string duration_word;
    public string day_word;       // "Day 3"
    public string day_unit;       // "1 day"
    public string days_unit;      // "3 days"
    public string hour_unit;
    public string hours_unit;
    public string[] months;
    public string[] short_months;
    public string[] weekdays;     // two letters, Monday first
    public bool day_first;        // "7. Sep" instead of "Sep 7"

    public static GanttLanguage for_code(string code) {
        var l = new GanttLanguage();
        switch (code.ascii_down()) {
            case "de":
                l.start_word = "Start"; l.end_word = "Ende"; l.duration_word = "Dauer";
                l.day_word = "Tag"; l.day_unit = "Tag"; l.days_unit = "Tage";
                l.hour_unit = "Stunde"; l.hours_unit = "Stunden";
                l.months = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                             "August", "September", "Oktober", "November", "Dezember" };
                l.short_months = { "Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul",
                                   "Aug", "Sep", "Okt", "Nov", "Dez" };
                l.weekdays = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" };
                l.day_first = true;
                break;
            default:
                l.start_word = "Start"; l.end_word = "End"; l.duration_word = "Duration";
                l.day_word = "Day"; l.day_unit = "day"; l.days_unit = "days";
                l.hour_unit = "hour"; l.hours_unit = "hours";
                l.months = { "January", "February", "March", "April", "May", "June", "July",
                             "August", "September", "October", "November", "December" };
                l.short_months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
                                   "Aug", "Sep", "Oct", "Nov", "Dec" };
                l.weekdays = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" };
                l.day_first = false;
                break;
        }
        return l;
    }

    public string short_date(int month, int dom) {
        return day_first ? "%d. %s".printf(dom, short_months[month - 1])
                         : "%s %d".printf(short_months[month - 1], dom);
    }

    // "3 days", "1 day, 8 hours"
    public string duration(double days) {
        int total_hours = (int) Math.round(days * 24.0);
        int d = total_hours / 24;
        int h = total_hours % 24;
        var sb = new StringBuilder();
        if (d > 0 || h == 0) sb.append("%d %s".printf(d, d == 1 ? day_unit : days_unit));
        if (h > 0) {
            if (sb.len > 0) sb.append(", ");
            sb.append("%d %s".printf(h, h == 1 ? hour_unit : hours_unit));
        }
        return sb.str;
    }
}

// Text widths via Pango, the same shaper librsvg uses for the SVG text
internal class GanttText : Object {
    private static Pango.Layout? layout = null;
    private static Cairo.ImageSurface? surface = null;

    public static double width(string text, double size, bool bold = false, string family = "sans-serif") {
        if (text.length == 0) return 0;
        if (layout == null) {
            surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
            var cr = new Cairo.Context(surface);
            layout = Pango.cairo_create_layout(cr);
        }
        var desc = new Pango.FontDescription();
        desc.set_family(family);
        desc.set_absolute_size(size * Pango.SCALE);
        desc.set_weight(bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
        layout.set_font_description(desc);
        layout.set_text(text, -1);
        Pango.Rectangle ink, logical;
        layout.get_extents(out ink, out logical);
        return (double) logical.width / Pango.SCALE;
    }
}

// Computes the chart geometry and writes the SVG
public class GanttLayout : Object {
    // Geometry measured from PlantUML 1.2026.8 SVG output
    public const double ROW_HEIGHT = 18.982;
    public const double BAR_HEIGHT = 14.982;
    public const double SEPARATOR_HEIGHT = 34.982;
    public const double RESOURCE_HEIGHT = 32.0;
    private const double NOTE_LINE = 12.258;

    private PumlGanttDiagram d;
    private Palette palette;
    private GanttLanguage lang;
    private StringBuilder sb;
    public Gee.ArrayList<ElementRegion> regions { get; private set; }

    // Colours
    private string c_bg;
    private string c_text;
    private string c_muted;
    private string c_grid;
    private string c_bar;
    private string c_bar_line;
    private string c_closed;
    private string c_note;
    private string c_legend;

    // Geometry
    public double day_width { get; private set; }
    public int range_start { get; private set; }
    public int range_end { get; private set; }      // inclusive
    public double chart_x { get; private set; }
    public double chart_top { get; private set; }   // top of the calendar header
    public double header_height { get; private set; }
    public double rows_top { get; private set; }
    public double rows_end { get; private set; }
    private double[] col_widths;
    private double max_x;
    private Gee.HashMap<PumlGanttTask, double?> row_tops;

    public static int undated_origin() { return 0; }

    public GanttLayout(PumlGanttDiagram diagram, Palette palette) {
        this.d = diagram;
        this.palette = palette;
        this.lang = GanttLanguage.for_code(diagram.language);
        this.regions = new Gee.ArrayList<ElementRegion>();
        this.row_tops = new Gee.HashMap<PumlGanttTask, double?>();
        setup_colours();
        compute_range();
    }

    // ---- colours ----

    private static bool parse_hex(string c, out int r, out int g, out int b) {
        r = g = b = 0;
        string s = c.strip();
        if (s.has_prefix("#")) s = s.substring(1);
        if (s.length == 3) s = "%c%c%c%c%c%c".printf(s[0], s[0], s[1], s[1], s[2], s[2]);
        if (s.length != 6 && s.length != 8) return false;
        for (int i = 0; i < 6; i++) {
            if (!s[i].isxdigit()) return false;
        }
        r = (s[0].xdigit_value() << 4) | s[1].xdigit_value();
        g = (s[2].xdigit_value() << 4) | s[3].xdigit_value();
        b = (s[4].xdigit_value() << 4) | s[5].xdigit_value();
        return true;
    }

    // Blend `a` toward `b` by t (0 = a, 1 = b)
    private static string mix(string a, string b, double t) {
        int ar, ag, ab, br, bg, bb;
        if (!parse_hex(a, out ar, out ag, out ab)) return b;
        if (!parse_hex(b, out br, out bg, out bb)) return a;
        int r = (int) Math.round(ar + (br - ar) * t);
        int g = (int) Math.round(ag + (bg - ag) * t);
        int bl = (int) Math.round(ab + (bb - ab) * t);
        return "#%02X%02X%02X".printf(r.clamp(0, 255), g.clamp(0, 255), bl.clamp(0, 255));
    }

    private static bool is_dark(string c) {
        int r, g, b;
        if (!parse_hex(c, out r, out g, out b)) return false;
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128;
    }

    // PlantUML colour → SVG colour: hex keeps "#", named colours lose it
    public static string svg_color(string color) {
        string c = color.strip();
        if (c.has_prefix("#")) {
            string rest = c.substring(1);
            bool hex = rest.length > 0;
            for (int i = 0; i < rest.length; i++) {
                if (!rest[i].isxdigit()) { hex = false; break; }
            }
            if (hex && (rest.length == 3 || rest.length == 6 || rest.length == 8)) return c;
            return rest.ascii_down();
        }
        bool hex = c.length == 6 || c.length == 3;
        for (int i = 0; i < c.length && hex; i++) {
            if (!c[i].isxdigit()) hex = false;
        }
        // A bare "AAF"/"FFD700" is a hex code only if it isn't a word like "bad"/"add"
        if (hex && c.length == 6) return "#" + c;
        return c.ascii_down();
    }

    private void setup_colours() {
        c_bg = palette.background;
        c_text = palette.node_text;
        bool dark = is_dark(c_bg);
        c_muted = mix(c_bg, c_text, 0.45);
        c_grid = mix(c_bg, c_text, 0.28);
        c_bar = dark ? mix(c_bg, "#8C8CE0", 0.35) : mix(c_bg, "#6A6AB0", 0.2);
        c_bar_line = c_text;
        c_closed = dark ? mix(c_bg, "#D07070", 0.2) : mix(c_bg, "#B06060", 0.12);
        c_note = dark ? mix(c_bg, "#FEFFDD", 0.22) : "#FEFFDD";
        c_legend = mix(c_bg, c_text, 0.15);
    }

    // ---- range / scale ----

    private void compute_range() {
        int start = d.is_dated() ? d.project_start_day : undated_origin();
        int end = start;
        bool first = true;
        foreach (var t in d.tasks) {
            if (t.start_day < start) start = t.start_day;
            int last = t.last_day;
            if (first || last > end) end = last;
            first = false;
        }
        if (end < start) end = start;
        if (d.print_from != int.MIN) start = d.print_from;
        if (d.print_to != int.MIN && d.print_to >= start) end = d.print_to;
        range_start = start;
        range_end = end;

        double base_width;
        switch (d.scale) {
            case PumlGanttScale.WEEKLY:    base_width = 4.0; break;
            case PumlGanttScale.MONTHLY:   base_width = 16.0 / 15.0; break;
            case PumlGanttScale.QUARTERLY: base_width = 0.4; break;
            case PumlGanttScale.YEARLY:    base_width = 4.0 / 15.0; break;
            default:                       base_width = 16.0; break;
        }
        day_width = base_width * d.zoom;
    }

    public double x_of(double day) {
        return chart_x + (day - range_start) * day_width;
    }

    public double chart_right() {
        return x_of(range_end + 1);
    }

    private bool daily_dated() {
        return d.scale == PumlGanttScale.DAILY && d.is_dated();
    }

    private double calendar_height() {
        switch (d.scale) {
            case PumlGanttScale.WEEKLY:    return 27;
            case PumlGanttScale.MONTHLY:
            case PumlGanttScale.QUARTERLY: return 30;
            case PumlGanttScale.YEARLY:    return 17;
            default:                       return d.is_dated() ? 39 : 16;
        }
    }

    private double footer_height() {
        switch (d.scale) {
            case PumlGanttScale.WEEKLY:    return 16;
            case PumlGanttScale.MONTHLY:
            case PumlGanttScale.QUARTERLY: return 30;
            case PumlGanttScale.YEARLY:    return 17;
            default:                       return d.is_dated() ? 39.83 : 16;
        }
    }

    // ---- SVG primitives ----

    private static string f(double v) {
        // Locale-independent, short
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

    private void text(double x, double y, string content, double size, string fill,
                      bool bold = false, string? family = null) {
        if (content.length == 0) return;
        track(x + GanttText.width(content, size, bold, family ?? "sans-serif"));
        sb.append("<text x=\"%s\" y=\"%s\" fill=\"%s\" font-size=\"%s\"%s%s>%s</text>\n".printf(
            f(x), f(y), fill, f(size), bold ? " font-weight=\"700\"" : "",
            family != null ? " font-family=\"%s\"".printf(family) : "", esc(content)));
    }

    private void line(double x1, double y1, double x2, double y2, string stroke,
                      double width = 1, string? dash = null) {
        sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"%s\"%s/>\n".printf(
            f(x1), f(y1), f(x2), f(y2), stroke, f(width),
            dash != null ? " stroke-dasharray=\"%s\"".printf(dash) : ""));
    }

    private void rect(double x, double y, double w, double h, string fill, string? stroke = null,
                      double rx = 0) {
        if (w <= 0 || h <= 0) return;
        track(x + w);
        sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\"%s%s/>\n".printf(
            f(x), f(y), f(w), f(h), fill,
            stroke != null ? " stroke=\"%s\" stroke-width=\"1\"".printf(stroke) : "",
            rx > 0 ? " rx=\"%s\" ry=\"%s\"".printf(f(rx), f(rx)) : ""));
    }

    private void path(string data, string fill, string stroke, double width, string? dash = null) {
        sb.append("<path d=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"%s/>\n".printf(
            data, fill, stroke, f(width), dash != null ? " stroke-dasharray=\"%s\"".printf(dash) : ""));
    }

    private void polygon(string points, string fill, string stroke) {
        sb.append("<polygon points=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1\"/>\n".printf(
            points, fill, stroke));
    }

    private void track(double right) {
        if (right > max_x) max_x = right;
    }

    // ---- table ----

    private string start_cell(PumlGanttTask t) {
        return GanttDiagramRenderer.format_date(d, lang, t.start_day);
    }

    private string end_cell(PumlGanttTask t) {
        if (t.is_milestone) {
            return GanttDiagramRenderer.format_date(d, lang, GanttScheduler.snap_open(d, t.start_day));
        }
        double frac = t.end_instant - Math.floor(t.end_instant);
        if (frac > 1e-6 && d.is_dated()) {
            int hours = (int) Math.round(frac * 24);
            return "%s %02d:00".printf(GanttDiagramRenderer.format_date(d, lang, (int) Math.floor(t.end_instant)), hours);
        }
        return GanttDiagramRenderer.format_date(d, lang, t.last_day);
    }

    private string duration_cell(PumlGanttTask t) {
        if (t.is_milestone) {
            int end = GanttScheduler.snap_open(d, t.start_day);
            return lang.duration(end - t.start_day + 1);
        }
        return lang.duration(t.end_instant - t.start_day);
    }

    private void measure_table() {
        col_widths = new double[3];
        string[] heads = { lang.start_word, lang.end_word, lang.duration_word };
        for (int i = 0; i < 3; i++) col_widths[i] = GanttText.width(heads[i], 10) + 10;
        foreach (var t in d.tasks) {
            col_widths[0] = double.max(col_widths[0], GanttText.width(start_cell(t), 10) + 10);
            col_widths[1] = double.max(col_widths[1], GanttText.width(end_cell(t), 10) + 10);
            col_widths[2] = double.max(col_widths[2], GanttText.width(duration_cell(t), 10) + 10);
        }
        chart_x = col_widths[0] + col_widths[1] + col_widths[2];
    }

    private void draw_table() {
        string[] heads = { lang.start_word, lang.end_word, lang.duration_word };
        double top = chart_top;
        double bottom = rows_end;
        line(0, top, chart_x, top, c_grid);
        line(0, top + header_height, chart_x, top + header_height, c_grid);
        line(0, bottom, chart_x, bottom, c_grid);
        double x = 0;
        line(0, top, 0, bottom, c_grid);
        for (int i = 0; i < 3; i++) {
            x += col_widths[i];
            line(x, top, x, bottom, c_grid);
        }
        double hx = 0;
        for (int i = 0; i < 3; i++) {
            text(hx + 5, top + header_height / 2 + 3.88, heads[i], 10, c_text);
            hx += col_widths[i];
        }
        foreach (var t in d.tasks) {
            double rt = row_tops[t];
            text(5, rt + 13.371, start_cell(t), 10, c_text);
            text(col_widths[0] + 5, rt + 13.371, end_cell(t), 10, c_text);
            text(col_widths[0] + col_widths[1] + 5, rt + 13.371, duration_cell(t), 10, c_text);
        }
    }

    // ---- calendar header / footer ----

    private int span_key_month(int day) {
        int y, m, dom;
        GanttScheduler.ymd_from_day(day, out y, out m, out dom);
        return y * 12 + (m - 1);
    }

    private int span_key_year(int day) {
        int y, m, dom;
        GanttScheduler.ymd_from_day(day, out y, out m, out dom);
        return y;
    }

    private int span_key_quarter(int day) {
        int y, m, dom;
        GanttScheduler.ymd_from_day(day, out y, out m, out dom);
        return y * 4 + (m - 1) / 3;
    }

    private enum SpanKind { MONTH, QUARTER, YEAR }

    private int span_key(SpanKind kind, int day) {
        switch (kind) {
            case SpanKind.MONTH:   return span_key_month(day);
            case SpanKind.QUARTER: return span_key_quarter(day);
            default:               return span_key_year(day);
        }
    }

    // Visible [first, last] day ranges of each month/quarter/year
    private Gee.ArrayList<int> spans(SpanKind kind) {
        var list = new Gee.ArrayList<int>();   // pairs: first, last
        int first = range_start;
        int key = span_key(kind, first);
        for (int day = range_start + 1; day <= range_end + 1; day++) {
            int k = day <= range_end ? span_key(kind, day) : int.MIN;
            if (k != key) {
                list.add(first);
                list.add(day - 1);
                first = day;
                key = k;
            }
        }
        return list;
    }

    private string span_label(SpanKind kind, int day, double span_width, bool daily_row, double size, bool bold) {
        int y, m, dom;
        GanttScheduler.ymd_from_day(day, out y, out m, out dom);
        string[] candidates;
        switch (kind) {
            case SpanKind.YEAR:
                candidates = { "%d".printf(y) };
                break;
            case SpanKind.QUARTER:
                candidates = { "Q%d".printf((m - 1) / 3 + 1) };
                break;
            default:
                if (daily_row) {
                    candidates = { "%s %d".printf(lang.months[m - 1], y), lang.months[m - 1] };
                } else if (d.scale == PumlGanttScale.WEEKLY) {
                    candidates = { "%s %d".printf(lang.short_months[m - 1], y), lang.short_months[m - 1] };
                } else {
                    candidates = { lang.months[m - 1], lang.short_months[m - 1] };
                }
                break;
        }
        foreach (string c in candidates) {
            double w = GanttText.width(c, size, bold);
            if (w <= span_width) return c;
        }
        return (kind == SpanKind.MONTH) ? "" : candidates[candidates.length - 1];
    }

    // One row of month/quarter/year labels centred on their visible spans
    private void draw_span_row(SpanKind kind, double top, double height, double baseline,
                               double size, bool bold, bool boundary_lines, bool daily_row) {
        var list = spans(kind);
        double right = chart_right();
        for (int i = 0; i < list.size; i += 2) {
            double x1 = x_of(list[i]);
            double x2 = x_of(list[i + 1] + 1);
            string label = span_label(kind, list[i], x2 - x1, daily_row, size, bold);
            if (label.length > 0) {
                double w = GanttText.width(label, size, bold);
                text((x1 + x2) / 2 - w / 2, top + baseline, label, size, c_text, bold);
            }
            if (boundary_lines) line(x1, top, x1, top + height, c_grid);
        }
        if (boundary_lines) line(right, top, right, top + height, c_grid);
    }

    private void draw_day_rows(double weekday_baseline, double day_baseline) {
        for (int day = range_start; day <= range_end; day++) {
            double cx = x_of(day) + day_width / 2;
            string color = d.is_closed(day) ? c_muted : c_text;
            if (weekday_baseline >= 0) {
                string wd = lang.weekdays[PumlGanttDiagram.weekday_of(day)];
                text(cx - GanttText.width(wd, 10) / 2, weekday_baseline, wd, 10, color);
            }
            string num;
            if (d.is_dated()) {
                int y, m, dom;
                GanttScheduler.ymd_from_day(day, out y, out m, out dom);
                num = "%d".printf(dom);
            } else {
                num = "%d".printf(day - undated_origin() + 1);
                color = c_text;
            }
            text(cx - GanttText.width(num, 10) / 2, day_baseline, num, 10, color);
        }
    }

    private void draw_week_numbers(double baseline) {
        for (int day = range_start; day <= range_end; day++) {
            if (PumlGanttDiagram.weekday_of(day) != 0) continue;
            string week = "%d".printf(GanttScheduler.iso_week(day));
            // PlantUML leaves out a number that would run past the chart's end
            if (x_of(day) + GanttText.width(week, 10) > chart_right()) continue;
            text(x_of(day) + 5, baseline, week, 10, c_text);
        }
    }

    private void draw_calendar(double top, bool footer) {
        double right = chart_right();
        switch (d.scale) {
            case PumlGanttScale.WEEKLY:
                if (footer) {
                    draw_span_row(SpanKind.MONTH, top, 16, 12.828, 12, true, true, false);
                    line(chart_x, top + 16, right, top + 16, c_grid);
                } else {
                    draw_span_row(SpanKind.MONTH, top, 16, 12.828, 12, true, true, false);
                    draw_week_numbers(top + 26.69);
                    line(chart_x, top, right, top, c_grid);
                    line(chart_x, top + 16, right, top + 16, c_grid);
                    line(chart_x, top + 27, right, top + 27, c_grid);
                }
                break;
            case PumlGanttScale.MONTHLY:
            case PumlGanttScale.QUARTERLY:
                SpanKind sub = d.scale == PumlGanttScale.MONTHLY ? SpanKind.MONTH : SpanKind.QUARTER;
                if (footer) {
                    draw_span_row(sub, top, 14, 10.69, 10, false, true, false);
                    draw_span_row(SpanKind.YEAR, top + 14, 16, 12.828, 12, true, true, false);
                    line(chart_x, top + 14, right, top + 14, c_grid);
                    line(chart_x, top + 30, right, top + 30, c_grid);
                } else {
                    draw_span_row(SpanKind.YEAR, top, 16, 12.828, 12, true, true, false);
                    draw_span_row(sub, top + 16, 14, 10.69, 10, false, true, false);
                    line(chart_x, top, right, top, c_grid);
                    line(chart_x, top + 16, right, top + 16, c_grid);
                    line(chart_x, top + 30, right, top + 30, c_grid);
                }
                break;
            case PumlGanttScale.YEARLY:
                draw_span_row(SpanKind.YEAR, top, 16, 14.966, 14, true, true, false);
                line(chart_x, top + 17, right, top + 17, c_grid);
                break;
            default:
                if (!d.is_dated()) {
                    draw_day_rows(-1, top + (footer ? 13.69 : 10.69));
                } else if (footer) {
                    draw_day_rows(top + 10.69, top + 24.69);
                    draw_span_row(SpanKind.MONTH, top + 24.69, 16, 15.138, 12, true, false, true);
                } else {
                    draw_span_row(SpanKind.MONTH, top, 16, 12.828, 12, true, false, true);
                    draw_day_rows(top + 24.69, top + 36.69);
                }
                break;
        }
    }

    // Shading, grid lines inside the chart body
    private void draw_body_background() {
        double right = chart_right();
        if (daily_dated()) {
            // Closed days, then coloured days and today on top
            int run_start = int.MIN;
            for (int day = range_start; day <= range_end + 1; day++) {
                bool closed = day <= range_end && d.is_closed(day);
                if (closed && run_start == int.MIN) run_start = day;
                if (!closed && run_start != int.MIN) {
                    rect(x_of(run_start), rows_top, (day - run_start) * day_width, rows_end - rows_top, c_closed);
                    run_start = int.MIN;
                }
            }
            foreach (var dc in d.day_colors) {
                int from = int.max(dc.from_day, range_start);
                int to = int.min(dc.to_day, range_end);
                if (to < from) continue;
                rect(x_of(from), rows_top, (to - from + 1) * day_width, rows_end - rows_top,
                     svg_color(dc.color));
            }
        }
        if (d.today_day != int.MIN && d.today_color != null &&
            d.today_day >= range_start && d.today_day <= range_end && d.scale == PumlGanttScale.DAILY) {
            rect(x_of(d.today_day), rows_top, day_width, rows_end - rows_top, svg_color(d.today_color));
        }

        switch (d.scale) {
            case PumlGanttScale.DAILY:
                double y1 = d.is_dated() ? rows_top : chart_top + 6;
                double y2 = d.is_dated() ? rows_end : rows_end + 8;
                for (int day = range_start; day <= range_end + 1; day++) {
                    line(x_of(day), y1, x_of(day), y2, c_grid);
                }
                if (d.is_dated()) {
                    line(chart_x, rows_top, right, rows_top, c_grid);
                    line(chart_x, rows_end, right, rows_end, c_grid);
                }
                break;
            case PumlGanttScale.WEEKLY:
                for (int day = range_start; day <= range_end; day++) {
                    if (PumlGanttDiagram.weekday_of(day) == 0) {
                        line(x_of(day), chart_top + 16, x_of(day), rows_end, c_grid);
                    }
                }
                line(right, chart_top + 16, right, rows_end, c_grid);
                line(chart_x, rows_end, right, rows_end, c_grid);
                break;
            default:
                line(chart_x, rows_end, right, rows_end, c_grid);
                break;
        }
    }

    // ---- rows ----

    private string label_of(PumlGanttTask t) {
        if (t.resources.size == 0 || d.hide_resource_names) return t.name;
        var sb2 = new StringBuilder(t.name);
        foreach (var r in t.resources) {
            sb2.append(r.percent == 100 ? " {%s}".printf(r.name) : " {%s:%d%%}".printf(r.name, r.percent));
        }
        return sb2.str;
    }

    // Open-day runs of a task as [first, end) day pairs; the last end may be fractional
    private Gee.ArrayList<double?> open_runs(PumlGanttTask t) {
        var runs = new Gee.ArrayList<double?>();
        int run_start = int.MIN;
        for (int day = t.start_day; day <= t.last_day + 1; day++) {
            bool open = day <= t.last_day && !d.is_closed(day);
            if (open && run_start == int.MIN) run_start = day;
            if (!open && run_start != int.MIN) {
                runs.add((double) run_start);
                runs.add((double) day);
                run_start = int.MIN;
            }
        }
        if (runs.size == 0) {
            runs.add((double) t.start_day);
            runs.add((double) t.last_day + 1);
        }
        // A fractional end cuts the last run short
        if (t.end_instant < runs[runs.size - 1] - 1e-9 && t.end_instant > runs[runs.size - 2]) {
            runs[runs.size - 1] = t.end_instant;
        }
        return runs;
    }

    public double bar_left(PumlGanttTask t) {
        return x_of(t.start_day) + 2;
    }

    public double bar_right(PumlGanttTask t) {
        var runs = open_runs(t);
        return x_of(runs[runs.size - 1]) - 2;
    }

    private void draw_bar(PumlGanttTask t, double top) {
        string fill = t.color != null ? svg_color(t.color) : c_bar;
        string stroke = t.line_color != null ? svg_color(t.line_color) : (t.color != null ? fill : c_bar_line);
        var runs = open_runs(t);
        int n = runs.size / 2;
        double y = top + 2;
        double h = BAR_HEIGHT;

        // Segment extents
        double[] lefts = new double[n];
        double[] rights = new double[n];
        double total = 0;
        for (int i = 0; i < n; i++) {
            lefts[i] = x_of(runs[2 * i]) + (i == 0 ? 2 : 0);
            rights[i] = x_of(runs[2 * i + 1]) - (i == n - 1 ? 2 : 0);
            total += rights[i] - lefts[i];
        }

        bool partial = t.completion_pct >= 0 && t.completion_pct < 100;
        double done = partial ? total * t.completion_pct / 100.0 : total;
        for (int i = 0; i < n; i++) {
            double w = rights[i] - lefts[i] + (i < n - 1 ? 1 : 0);
            double filled = double.min(w, double.max(0, done));
            if (filled > 0) rect(lefts[i], y, filled, h, fill);
            if (partial && w - filled > 0) rect(lefts[i] + filled, y, w - filled, h, c_bg);
            done -= rights[i] - lefts[i];
        }

        double bottom = y + h;
        if (n == 1) {
            rect(lefts[0], y, rights[0] - lefts[0], h, "none", stroke);
        } else {
            for (int i = 0; i < n; i++) {
                string l = f(lefts[i]), r = f(rights[i]), yt = f(y), yb = f(bottom);
                if (i == 0) {
                    path("M%s,%s L%s,%s L%s,%s L%s,%s".printf(r, yb, l, yb, l, yt, r, yt), "none", stroke, 1);
                } else if (i == n - 1) {
                    path("M%s,%s L%s,%s L%s,%s L%s,%s".printf(l, yt, r, yt, r, yb, l, yb), "none", stroke, 1);
                } else {
                    line(lefts[i], y, rights[i], y, stroke);
                    line(lefts[i], bottom, rights[i], bottom, stroke);
                }
            }
            for (int i = 0; i < n - 1; i++) {
                double g1 = rights[i] + 3, g2 = lefts[i + 1] - 3;
                if (g2 - g1 > 1) {
                    line(g1, y, g2, y, stroke, 1, "2,3");
                    line(g1, bottom, g2, bottom, stroke, 1, "2,3");
                }
            }
        }

        double left = lefts[0], right = rights[n - 1];
        regions.add(new ElementRegion(t.name, t.source_line, left, y, right - left, h));

        string label = label_of(t);
        double lw = GanttText.width(label, 11);
        double lx = (lw + 8 <= right - left) ? left + 4 : right + 4;
        // An "ends at [X]'s end" arrow enters from the right: the label moves past its bend
        if (lx > right) {
            foreach (var link in d.links) {
                if (link.to == t && link.to_end) {
                    lx = right + 14;
                    break;
                }
            }
        }
        text(lx, top + 13.759, label, 11, c_text);
        if (lx > right) regions.add(new ElementRegion(t.name, t.source_line, lx, y, lw, h));
    }

    private void draw_milestone(PumlGanttTask t, double top) {
        double cx = x_of(t.start_day) + day_width / 2;
        double cy = top + 2 + BAR_HEIGHT / 2;
        string fill = t.color != null ? svg_color(t.color) : c_text;
        polygon("%s,%s %s,%s %s,%s %s,%s".printf(f(cx), f(cy - 5), f(cx + 5), f(cy), f(cx), f(cy + 5), f(cx - 5), f(cy)),
                fill, fill);
        track(cx + 5);
        double lx = cx + 8;
        text(lx, top + 13.759, t.name, 11, c_text);
        regions.add(new ElementRegion(t.name, t.source_line, cx - 5, cy - 5,
                                      lx - cx + 5 + GanttText.width(t.name, 11), 10));
    }

    private double note_height(PumlGanttTask t) {
        if (t.note == null) return 0;
        return 10 + NOTE_LINE * t.note.split("\n").length;
    }

    private void draw_note(PumlGanttTask t, double y0) {
        string[] lines = t.note.split("\n");
        double maxw = 0;
        foreach (string l in lines) maxw = double.max(maxw, GanttText.width(l, 9));
        double x0 = x_of(t.start_day);
        double w = maxw + 26;
        double h = note_height(t);
        string x1 = f(x0), x2 = f(x0 + w), xf = f(x0 + w - 10), y1 = f(y0), y2 = f(y0 + h), yf = f(y0 + 10);
        sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"0.5\"/>\n".printf(
            x1, y1, x1, y2, x2, y2, x2, yf, xf, y1, x1, y1, c_note, c_text));
        sb.append("<path d=\"M%s,%s L%s,%s L%s,%s L%s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"0.5\"/>\n".printf(
            xf, y1, xf, yf, x2, yf, xf, y1, c_note, c_text));
        track(x0 + w);
        string note_text = is_dark(c_note) ? c_text : "#000000";
        for (int i = 0; i < lines.length; i++) {
            text(x0 + 6, y0 + 14.621 + i * NOTE_LINE, lines[i], 9, note_text);
        }
    }

    private void draw_separator(string label, double top) {
        double y = top + SEPARATOR_HEIGHT / 2;
        double right = chart_right();
        if (label.length == 0) {
            line(chart_x, y, right, y, c_bar_line);
            return;
        }
        line(chart_x, y, chart_x + 5, y, c_bar_line);
        double tx = chart_x + 10;
        double tw = GanttText.width(label, 11);
        text(tx, y + 4.268, label, 11, c_text);
        if (tx + tw + 5 < right) line(tx + tw + 5, y, right, y, c_bar_line);
    }

    private void draw_link(PumlGanttLink link) {
        if (!row_tops.has_key(link.from) || !row_tops.has_key(link.to)) return;
        double ft = row_tops[link.from];
        double tt = row_tops[link.to];
        double to_mid = tt + 2 + BAR_HEIGHT / 2;
        double from_mid = ft + 2 + BAR_HEIGHT / 2;
        string stroke = link.color != null ? svg_color(link.color) : c_bar_line;
        double width = link.style == "bold" ? 2 : 1.5;
        string? dash = link.style == "dotted" ? "1,3" : (link.style == "dashed" ? "7,7" : null);
        var p = new StringBuilder();
        if (link.to_end) {
            // ends at [X]'s end: out of X's right side, into the task's right end
            double sx = link.from.is_milestone ? x_of(link.from.start_day) + day_width / 2 + 3 : bar_right(link.from);
            double tip = bar_right(link.to) + 2;
            double bend = sx + (link.from.is_milestone ? 13 : 10);
            p.append("M%s,%s L%s,%s L%s,%s L%s,%s".printf(f(sx), f(from_mid), f(bend), f(from_mid),
                                                        f(bend), f(to_mid), f(tip + 3), f(to_mid)));
            path(p.str, "none", stroke, width, dash);
            polygon("%s,%s %s,%s %s,%s %s,%s".printf(f(tip + 4), f(to_mid - 4), f(tip), f(to_mid),
                                                     f(tip + 4), f(to_mid + 4), f(tip + 4), f(to_mid - 4)),
                    stroke, stroke);
            return;
        }
        double tip = bar_left(link.to) - 2;
        if (link.from_anchor == PumlGanttAnchor.START) {
            double sx = link.from.is_milestone ? x_of(link.from.start_day) + day_width / 2 - 3 : bar_left(link.from);
            double bend = sx - (link.from.is_milestone ? 13 : 10);
            p.append("M%s,%s L%s,%s L%s,%s L%s,%s".printf(f(sx), f(from_mid), f(bend), f(from_mid),
                                                        f(bend), f(to_mid), f(tip - 3), f(to_mid)));
        } else {
            double sx = link.from.is_milestone ? x_of(link.from.start_day) + day_width / 2 : bar_right(link.from) - 6;
            double sy = tt >= ft ? ft + 2 + BAR_HEIGHT : ft + 2;
            if (link.from.is_milestone) sy = tt >= ft ? from_mid + 5 : from_mid - 5;
            p.append("M%s,%s L%s,%s L%s,%s".printf(f(sx), f(sy), f(sx), f(to_mid), f(tip - 3), f(to_mid)));
        }
        path(p.str, "none", stroke, width, dash);
        polygon("%s,%s %s,%s %s,%s %s,%s".printf(f(tip - 4), f(to_mid - 4), f(tip), f(to_mid),
                                                 f(tip - 4), f(to_mid + 4), f(tip - 4), f(to_mid - 4)),
                stroke, stroke);
    }

    // ---- resources ----

    private void draw_resources(double top) {
        var names = new Gee.ArrayList<string>();
        foreach (var t in d.tasks) {
            foreach (var r in t.resources) {
                if (!names.contains(r.name)) names.add(r.name);
            }
        }
        double right = chart_right();
        double y = top;
        foreach (string name in names) {
            text(chart_x, y + 13.897, name, 13, c_text, false, "serif");
            line(chart_x, y + 17.706, right, y + 17.706, c_text);
            if (d.scale == PumlGanttScale.DAILY) {
                var loads = new Gee.HashMap<int, int>();
                foreach (var t in d.tasks) {
                    foreach (var r in t.resources) {
                        if (r.name != name) continue;
                        for (int day = t.start_day; day <= t.last_day; day++) {
                            if (d.is_closed(day) || day + 1 > t.end_instant + 1e-9) continue;
                            loads[day] = (loads.has_key(day) ? loads[day] : 0) + r.percent;
                        }
                    }
                }
                foreach (var e in loads.entries) {
                    string s = "%d".printf(e.value);
                    double w = GanttText.width(s, 9, false, "serif");
                    text(x_of(e.key) + day_width / 2 - w / 2, y + 25.62, s, 9, c_text, false, "serif");
                }
            }
            y += RESOURCE_HEIGHT;
        }
    }

    private int resource_count() {
        var names = new Gee.HashSet<string>();
        foreach (var t in d.tasks) {
            foreach (var r in t.resources) names.add(r.name);
        }
        return names.size;
    }

    // ---- whole chart ----

    public string build() {
        sb = new StringBuilder();
        max_x = 0;
        measure_table();

        double y = 0;
        double header_block = 0;
        if (d.header != null && d.header.length > 0) header_block = 14.62;
        double title_block = (d.title != null && d.title.length > 0) ? 40.068 : 0;
        chart_top = header_block + title_block;
        header_height = calendar_height();
        rows_top = chart_top + header_height;

        // Row positions
        y = rows_top;
        foreach (var row in d.rows) {
            if (row.task != null) {
                row_tops[row.task] = y;
                y += ROW_HEIGHT + note_height(row.task);
            } else {
                y += SEPARATOR_HEIGHT;
            }
        }
        int nres = d.hide_resource_footbox ? 0 : resource_count();
        rows_end = y + nres * RESOURCE_HEIGHT;

        draw_table();
        draw_body_background();
        draw_calendar(chart_top, false);
        foreach (var link in d.links) draw_link(link);
        foreach (var row in d.rows) {
            if (row.task != null) {
                double top = row_tops[row.task];
                if (row.task.is_milestone) {
                    draw_milestone(row.task, top);
                } else {
                    draw_bar(row.task, top);
                }
            }
        }
        y = rows_top;
        foreach (var row in d.rows) {
            if (row.task != null) {
                if (row.task.note != null) draw_note(row.task, y + ROW_HEIGHT);
                y += ROW_HEIGHT + note_height(row.task);
            } else {
                draw_separator(row.separator, y);
                y += SEPARATOR_HEIGHT;
            }
        }
        if (nres > 0) draw_resources(y);

        double bottom = rows_end;
        if (!d.hide_footbox) {
            draw_calendar(rows_end, true);
            bottom = rows_end + footer_height();
        }
        track(chart_right());

        // Width known: centred and right-aligned document texts
        double width = Math.ceil(max_x + 20);
        double title_w = title_block > 0 ? GanttText.width(d.title, 14, true) : 0;
        width = double.max(width, Math.ceil(title_w + 20));

        // Chart content first; the frame (width) is known afterwards
        string body = sb.str;
        sb = new StringBuilder();
        if (header_block > 0) {
            double hw = GanttText.width(d.header, 10);
            text(width - 5 - hw, 10.69, d.header, 10, mix(c_bg, c_text, 0.5));
        }
        if (title_block > 0) {
            text(width / 2 - title_w / 2, header_block + 24.966, d.title, 14, c_text, true);
        }
        double cursor = bottom;
        if (d.legend != null && d.legend.length > 0) {
            string[] lines = d.legend.split("\n");
            double lw = 0;
            foreach (string l in lines) lw = double.max(lw, GanttText.width(l, 14));
            double lh = 10 + lines.length * 19.068;
            double ly = cursor + 12;
            double lx = width / 2 - (lw + 10) / 2;
            rect(lx, ly, lw + 10, lh, c_legend, c_text, 7.5);
            for (int i = 0; i < lines.length; i++) {
                text(lx + 5, ly + 19.966 + i * 19.068, lines[i], 14, c_text);
            }
            cursor = ly + lh;
        }
        if (d.caption != null && d.caption.length > 0) {
            double cw = GanttText.width(d.caption, 14);
            cursor += 28.965;
            text(width / 2 - cw / 2, cursor, d.caption, 14, c_text);
            cursor += 4;
        }
        if (d.footer != null && d.footer.length > 0) {
            double fw = GanttText.width(d.footer, 10);
            cursor += (d.caption != null && d.caption.length > 0) ? 12.79 : 16.79;
            text(width / 2 - fw / 2, cursor, d.footer, 10, mix(c_bg, c_text, 0.5));
            cursor += 4;
        }
        double height = Math.ceil(double.max(cursor, bottom) + 1);

        var doc = new StringBuilder();
        doc.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        doc.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%spx\" height=\"%spx\" viewBox=\"0 0 %s %s\">\n".printf(
            f(width), f(height), f(width), f(height)));
        doc.append("<rect x=\"0\" y=\"0\" width=\"100%%\" height=\"100%%\" fill=\"%s\"/>\n".printf(c_bg));
        doc.append("<g font-family=\"sans-serif\">\n");
        doc.append(body);
        doc.append(sb.str);
        doc.append("</g>\n</svg>\n");
        return doc.str;
    }
}

}
