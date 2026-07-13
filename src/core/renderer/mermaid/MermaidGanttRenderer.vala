/* MermaidGanttRenderer.vala — renders Mermaid gantt charts on a time axis.
 *
 * Graphviz cannot place bars by date, so the chart is written as SVG
 * directly (like the PlantUML gantt renderer) and goes through the shared
 * SVG → surface/PNG/PDF path. Geometry follows Mermaid 11.17's
 * ganttRenderer.js with its default configuration: a 784 px wide chart
 * (Mermaid CLI's default), 20 px bars on 24 px rows, 75 px side padding, a
 * d3 time scale with d3's automatic ticks (or tickInterval), section bands,
 * excluded-day shading, milestones as diamonds, vert markers and the today
 * line. Colours are Mermaid's default theme on light backgrounds; neutral
 * colours (text, grid, bands) follow the active palette on dark ones.
 */
namespace GDiagram {

public class MermaidGanttRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public MermaidGanttRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    /**
     * The chart itself is drawn without Graphviz; the DOT form lists the
     * tasks per section and their dependencies for tools that want a graph.
     */
    public string generate_dot(MermaidGantt diagram) {
        var palette = ThemeManager.get_active_palette();
        var dot = new StringBuilder();
        dot.append("digraph G {\n");
        dot.append("  rankdir=LR;\n");
        dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
        dot.append("  node [fontname=\"Sans\", fontsize=10, shape=box, style=\"rounded\", color=\"%s\", fontcolor=\"%s\"];\n".printf(
            palette.node_border, palette.node_text));
        dot.append("  edge [color=\"%s\"];\n".printf(palette.edge_color));
        if (diagram.title != null && diagram.title.length > 0) {
            dot.append_printf("  label=\"%s\";\n  labelloc=t;\n", RenderUtils.escape_label(diagram.title));
        }
        var ids = new Gee.HashMap<GanttTask, string>();
        int n = 0;
        foreach (var t in diagram.tasks) ids[t] = "t%d".printf(n++);
        string section = null;
        int cluster = 0;
        foreach (var t in diagram.tasks) {
            if (t.section_name != section) {
                if (section != null && section.length > 0) dot.append("  }\n");
                section = t.section_name;
                if (section.length > 0) {
                    dot.append_printf("  subgraph cluster_%d {\n    label=\"%s\";\n", cluster++,
                        RenderUtils.escape_label(section));
                }
            }
            dot.append_printf("  %s [label=\"%s\"%s];\n", ids[t], RenderUtils.escape_label(t.description),
                t.is_milestone ? ", shape=diamond, style=solid" : "");
        }
        if (section != null && section.length > 0) dot.append("  }\n");
        var by_id = new Gee.HashMap<string, GanttTask>();
        foreach (var t in diagram.tasks) by_id[t.id] = t;
        foreach (var t in diagram.tasks) {
            foreach (string id in t.after_ids) {
                var from = by_id[id];
                if (from != null) dot.append_printf("  %s -> %s;\n", ids[from], ids[t]);
            }
        }
        dot.append("}\n");
        return dot.str;
    }

    public uint8[]? render_to_svg(MermaidGantt diagram) {
        var layout = new MermaidGanttLayout(diagram, ThemeManager.get_active_palette());
        string svg = layout.build();
        regions.clear();
        foreach (var r in layout.regions) regions.add(r);
        return svg.data;
    }

    public Cairo.ImageSurface? render_to_surface(MermaidGantt diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(MermaidGantt diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) return false;
        return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(MermaidGantt diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidGantt diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

// Geometry and SVG output
public class MermaidGanttLayout : Object {
    // Mermaid gantt defaults
    public const double WIDTH = 784;
    public const double BAR_HEIGHT = 20;
    public const double BAR_GAP = 4;
    public const double TOP_PADDING = 50;
    public const double SIDE_PADDING = 75;
    public const double RIGHT_PADDING = 75;
    public const double GRID_START = 35;
    public const double TITLE_TOP = 25;
    public const double FONT_SIZE = 11;
    private const int64 DAY = 86400000;

    private MermaidGantt d;
    private Palette palette;
    private StringBuilder sb;
    public Gee.ArrayList<ElementRegion> regions { get; private set; }

    private int64 dom0;
    private int64 dom1;
    public double height { get; private set; }
    private Gee.ArrayList<string> categories;
    private Gee.HashMap<GanttTask, int> rows;
    private int row_count;

    // Colours
    private bool dark;
    private string c_bg;
    private string c_text;
    private string c_title;
    private string c_grid;
    private string c_exclude;
    private string c_vert;
    private string c_click;

    public MermaidGanttLayout(MermaidGantt diagram, Palette palette) {
        this.d = diagram;
        this.palette = palette;
        this.regions = new Gee.ArrayList<ElementRegion>();
        this.rows = new Gee.HashMap<GanttTask, int>();
        this.categories = new Gee.ArrayList<string>();
        setup_colours();
        compute_rows();
        compute_domain();
    }

    // ---- colours ----

    private static bool parse_hex(string c, out int r, out int g, out int b) {
        r = g = b = 0;
        string s = c.strip();
        if (s.has_prefix("#")) s = s.substring(1);
        if (s.length == 3) s = "%c%c%c%c%c%c".printf(s[0], s[0], s[1], s[1], s[2], s[2]);
        if (s.length != 6 && s.length != 8) return false;
        for (int i = 0; i < 6; i++) if (!s[i].isxdigit()) return false;
        r = (s[0].xdigit_value() << 4) | s[1].xdigit_value();
        g = (s[2].xdigit_value() << 4) | s[3].xdigit_value();
        b = (s[4].xdigit_value() << 4) | s[5].xdigit_value();
        return true;
    }

    private static string mix(string a, string b, double t) {
        int ar, ag, ab, br, bg, bb;
        if (!parse_hex(a, out ar, out ag, out ab)) return b;
        if (!parse_hex(b, out br, out bg, out bb)) return a;
        return "#%02X%02X%02X".printf(
            ((int) Math.round(ar + (br - ar) * t)).clamp(0, 255),
            ((int) Math.round(ag + (bg - ag) * t)).clamp(0, 255),
            ((int) Math.round(ab + (bb - ab) * t)).clamp(0, 255));
    }

    public static bool is_dark(string c) {
        int r, g, b;
        if (!parse_hex(c, out r, out g, out b)) return false;
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128;
    }

    private void setup_colours() {
        c_bg = palette.background;
        dark = is_dark(c_bg);
        c_text = dark ? palette.node_text : "#000000";
        c_title = dark ? palette.node_text : "#333333";
        c_grid = dark ? mix(c_bg, palette.node_text, 0.55) : "#000000";
        c_exclude = dark ? mix(c_bg, palette.node_text, 0.12) : "#EEEEEE";
        c_vert = dark ? "#8C8CFF" : "#000080";
        c_click = dark ? "#9CC8FF" : "#003163";
    }

    // ---- scale ----

    private void compute_rows() {
        foreach (var t in d.tasks) {
            if (t.is_vert) continue;
            if (!categories.contains(t.section_name)) categories.add(t.section_name);
        }
        if (d.compact) {
            // getMaxIntersections per section, in section order
            int offset = 0;
            foreach (string cat in categories) {
                var list = new Gee.ArrayList<GanttTask>();
                foreach (var t in d.tasks) if (!t.is_vert && t.section_name == cat) list.add(t);
                var sorted = new Gee.ArrayList<GanttTask>();
                sorted.add_all(list);
                sorted.sort((a, b) => {
                    if (a.start_ms != b.start_ms) return a.start_ms < b.start_ms ? -1 : 1;
                    return a.order - b.order;
                });
                var timeline = new int64[list.size];
                for (int k = 0; k < timeline.length; k++) timeline[k] = int64.MIN;
                int max_j = 0;
                foreach (var t in sorted) {
                    for (int j = 0; j < timeline.length; j++) {
                        if (t.start_ms >= timeline[j]) {
                            timeline[j] = t.end_ms;
                            rows[t] = j + offset;
                            if (j > max_j) max_j = j;
                            break;
                        }
                    }
                }
                offset += max_j + 1;
            }
            row_count = offset;
        } else {
            int n = 0;
            foreach (var t in d.tasks) {
                if (t.is_vert) continue;
                rows[t] = t.order;
                n++;
            }
            row_count = n;
        }
        height = 2 * TOP_PADDING + row_count * (BAR_HEIGHT + BAR_GAP);
    }

    private void compute_domain() {
        bool first = true;
        foreach (var t in d.tasks) {
            if (first || t.start_ms < dom0) dom0 = t.start_ms;
            if (first || t.end_ms > dom1) dom1 = t.end_ms;
            first = false;
        }
        // A task whose end precedes its start (an unparseable duration read as
        // a date, a timestamp clamped to the end of the calendar) inverted the
        // domain, and every tick range then came out empty — an axis-less chart.
        if (dom1 < dom0) {
            int64 swap = dom0;
            dom0 = dom1;
            dom1 = swap;
        }
    }

    // d3 scaleTime().rangeRound([0, WIDTH - 150])
    public double x_of(int64 ms) {
        double range = WIDTH - SIDE_PADDING - RIGHT_PADDING;
        if (dom1 == dom0) return Math.round(range * 0.5);
        return Math.round((double) (ms - dom0) / (double) (dom1 - dom0) * range);
    }

    // ---- ticks (d3-time) ----

    private enum Unit { MILLI, SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, YEAR }

    private static int64 floor_unit(int64 ms, Unit u, int week_start) {
        int y, mo, dd, h, mi, s, l;
        MermaidGanttTime.parts(ms, out y, out mo, out dd, out h, out mi, out s, out l);
        switch (u) {
            case Unit.MILLI:  return ms;
            case Unit.SECOND: return MermaidGanttTime.make(y, mo, dd, h, mi, s);
            case Unit.MINUTE: return MermaidGanttTime.make(y, mo, dd, h, mi);
            case Unit.HOUR:   return MermaidGanttTime.make(y, mo, dd, h);
            case Unit.DAY:    return MermaidGanttTime.make(y, mo, dd);
            case Unit.WEEK: {
                int64 day = MermaidGanttTime.make(y, mo, dd);
                int wd = MermaidGanttTime.iso_weekday(ms) % 7;    // 0 = Sunday
                int back = (wd - week_start + 7) % 7;
                return MermaidGanttTime.add(day, -back, "d");
            }
            case Unit.MONTH:  return MermaidGanttTime.make(y, mo, 1);
            default:          return MermaidGanttTime.make(y, 1, 1);
        }
    }

    private static int64 offset_unit(int64 ms, Unit u, int64 n) {
        switch (u) {
            case Unit.MILLI:  return ms + n;
            case Unit.SECOND: return ms + n * 1000;
            case Unit.MINUTE: return ms + n * 60000;
            case Unit.HOUR:   return ms + n * 3600000;
            case Unit.DAY:    return MermaidGanttTime.add(ms, n, "d");
            case Unit.WEEK:   return MermaidGanttTime.add(ms, n * 7, "d");
            case Unit.MONTH:  return MermaidGanttTime.add(ms, n, "M");
            default:          return MermaidGanttTime.add(ms, n, "y");
        }
    }

    // interval.every(step) filter
    private static bool field_ok(int64 ms, Unit u, int step, int week_start) {
        if (step <= 1) return true;
        int y, mo, dd, h, mi, s, l;
        MermaidGanttTime.parts(ms, out y, out mo, out dd, out h, out mi, out s, out l);
        switch (u) {
            case Unit.MILLI:  return ms % step == 0;
            case Unit.SECOND: return s % step == 0;
            case Unit.MINUTE: return mi % step == 0;
            case Unit.HOUR:   return h % step == 0;
            case Unit.DAY:    return (dd - 1) % step == 0;
            case Unit.WEEK: {
                int64 epoch_week = floor_unit(0, Unit.WEEK, week_start);
                int64 weeks = (floor_unit(ms, Unit.WEEK, week_start) - epoch_week) / (7 * DAY);
                return weeks % step == 0;
            }
            case Unit.MONTH:  return (mo - 1) % step == 0;
            default:          return y % step == 0;
        }
    }

    // interval.every(step).range(start, stop)
    private static Gee.ArrayList<int64?> range(int64 start, int64 stop, Unit u, int step, int week_start) {
        var out_list = new Gee.ArrayList<int64?>();
        if (u == Unit.MILLI && step > 1) {
            int64 t = (start + step - 1) / step * step;
            for (; t < stop && out_list.size < 10000; t += step) out_list.add(t);
            return out_list;
        }
        int64 t0 = floor_unit(start, u, week_start);
        if (t0 < start) t0 = offset_unit(t0, u, 1);
        int64 t = t0;
        int guard = 0;
        while (t < stop && guard++ < 200000 && out_list.size < 10000) {
            if (field_ok(t, u, step, week_start)) out_list.add(t);
            t = offset_unit(t, u, 1);
        }
        return out_list;
    }

    private static double tick_step(double start, double stop, int count) {
        double step = (stop - start) / count;
        double power = Math.floor(Math.log10(step));
        double error = step / Math.pow(10, power);
        double factor = error >= Math.sqrt(50) ? 10 : error >= Math.sqrt(10) ? 5 : error >= Math.sqrt(2) ? 2 : 1;
        return factor * Math.pow(10, power);
    }

    private static int weekday_index(string name) {
        switch (name) {
            case "monday": return 1;
            case "tuesday": return 2;
            case "wednesday": return 3;
            case "thursday": return 4;
            case "friday": return 5;
            case "saturday": return 6;
            default: return 0;
        }
    }

    public Gee.ArrayList<int64?> ticks() {
        // tickInterval: /^([1-9]\d*)(millisecond|second|minute|hour|day|week|month)$/
        if (d.tick_interval != null) {
            try {
                var re = new Regex("^([1-9]\\d*)(millisecond|second|minute|hour|day|week|month)$");
                MatchInfo m;
                if (re.match(d.tick_interval, 0, out m)) {
                    int every = int.parse(m.fetch(1));
                    string unit = m.fetch(2);
                    Unit u;
                    int64 unit_ms;
                    switch (unit) {
                        case "millisecond": u = Unit.MILLI; unit_ms = 1; break;
                        case "second": u = Unit.SECOND; unit_ms = 1000; break;
                        case "minute": u = Unit.MINUTE; unit_ms = 60000; break;
                        case "hour": u = Unit.HOUR; unit_ms = 3600000; break;
                        case "day": u = Unit.DAY; unit_ms = DAY; break;
                        case "week": u = Unit.WEEK; unit_ms = 7 * DAY; break;
                        default: u = Unit.MONTH; unit_ms = 30 * DAY; break;
                    }
                    double estimated = Math.ceil((double) (dom1 - dom0) / (double) (unit_ms * every));
                    if (estimated <= 10000) {
                        return range(dom0, dom1 + 1, u, every, weekday_index(d.weekday));
                    }
                }
            } catch (RegexError e) {
                warning("tickInterval regex: %s", e.message);
            }
        }

        // d3 scaleTime ticks(10)
        const int COUNT = 10;
        int64 SEC = 1000, MIN = 60000, HOUR = 3600000, WEEK = 7 * DAY, MONTH = 30 * DAY, YEAR = 365 * DAY;
        Unit[] units = { Unit.SECOND, Unit.SECOND, Unit.SECOND, Unit.SECOND, Unit.MINUTE, Unit.MINUTE,
                         Unit.MINUTE, Unit.MINUTE, Unit.HOUR, Unit.HOUR, Unit.HOUR, Unit.HOUR,
                         Unit.DAY, Unit.DAY, Unit.WEEK, Unit.MONTH, Unit.MONTH, Unit.YEAR };
        int[] steps = { 1, 5, 15, 30, 1, 5, 15, 30, 1, 3, 6, 12, 1, 2, 1, 1, 3, 1 };
        int64[] durs = { SEC, 5 * SEC, 15 * SEC, 30 * SEC, MIN, 5 * MIN, 15 * MIN, 30 * MIN,
                         HOUR, 3 * HOUR, 6 * HOUR, 12 * HOUR, DAY, 2 * DAY, WEEK, MONTH, 3 * MONTH, YEAR };
        if (dom1 <= dom0) {
            return range(dom0, dom1 + 1, Unit.MILLI, 1, 0);
        }
        double target = (double) (dom1 - dom0) / COUNT;
        int i = 0;
        while (i < durs.length && durs[i] <= target) i++;   // bisector.right
        if (i == durs.length) {
            int step = (int) tick_step((double) dom0 / YEAR, (double) dom1 / YEAR, COUNT);
            return range(dom0, dom1 + 1, Unit.YEAR, int.max(step, 1), 0);
        }
        if (i == 0) {
            int step = int.max((int) tick_step(dom0, dom1, COUNT), 1);
            return range(dom0, dom1 + 1, Unit.MILLI, step, 0);
        }
        int pick = (target / durs[i - 1] < durs[i] / target) ? i - 1 : i;
        return range(dom0, dom1 + 1, units[pick], steps[pick], 0);
    }

    // ---- SVG primitives ----

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

    private void text(double x, double y, string content, double size, string fill,
                      string anchor = "start", bool bold = false, bool italic = false) {
        text_to(sb, x, y, content, size, fill, anchor, bold, italic);
    }

    private static void text_to(StringBuilder target, double x, double y, string content, double size,
                                string fill, string anchor = "start", bool bold = false, bool italic = false) {
        if (content.length == 0) return;
        target.append("<text x=\"%s\" y=\"%s\" fill=\"%s\" font-size=\"%s\"%s%s%s>%s</text>\n".printf(
            f(x), f(y), fill, f(size),
            anchor != "start" ? " text-anchor=\"%s\"".printf(anchor) : "",
            bold ? " font-weight=\"bold\"" : "",
            italic ? " font-style=\"italic\"" : "", esc(content)));
    }

    public static double text_width(string s, double size, bool bold = false) {
        return GanttText.width(s, size, bold);
    }

    // ---- drawing ----

    private string section_fill(int idx, out double opacity) {
        switch (idx % 4) {
            case 0:
                opacity = 0.49 * 0.2;
                return "#6666FF";
            case 2:
                opacity = dark ? 0.1 : 0.2;
                return "#FFF400";
            default:
                opacity = dark ? 0.0 : 0.2;
                return "#FFFFFF";
        }
    }

    private int section_index(string name) {
        int i = categories.index_of(name);
        return i < 0 ? 0 : i;
    }

    private void draw_exclude_days() {
        if (d.excludes.size == 0 && d.includes.size == 0) return;
        if (d.tasks.size == 0) return;
        int64 min_t = int64.MAX, max_t = int64.MIN;
        foreach (var t in d.tasks) {
            if (t.start_ms < min_t) min_t = t.start_ms;
            if (t.end_ms > max_t) max_t = t.end_ms;
        }
        if (max_t - min_t >= 6 * 365 * DAY) return;
        int64 cur = min_t;
        int64 range_start = -1, range_end = -1;
        bool open = false;
        int guard = 0;
        var ranges = new Gee.ArrayList<int64?>();
        while (cur <= max_t && guard++ < 4000) {
            if (MermaidGanttScheduler.is_invalid_date(d, cur)) {
                if (!open) { range_start = cur; open = true; }
                range_end = cur;
            } else if (open) {
                ranges.add(range_start);
                ranges.add(range_end);
                open = false;
            }
            cur = MermaidGanttTime.add(cur, 1, "d");
        }
        for (int i = 0; i + 1 < ranges.size; i += 2) {
            int64 s0 = MermaidGanttTime.start_of_day(ranges[i]);
            int64 e0 = MermaidGanttTime.start_of_day(ranges[i + 1]) + DAY - 1;
            double x = x_of(s0) + SIDE_PADDING;
            double w = x_of(e0) - x_of(s0);
            if (w <= 0) continue;
            sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\"/>\n".printf(
                f(x), f(GRID_START), f(w), f(height - TOP_PADDING - GRID_START), c_exclude));
        }
    }

    private string axis_format() {
        if (d.axis_format != null && d.axis_format.length > 0) return d.axis_format;
        if (d.date_format == "D") return "%d";
        return "%Y-%m-%d";
    }

    private void draw_grid() {
        var tick_list = ticks();
        string fmt = axis_format();
        double base_y = height - 50;
        sb.append("<g opacity=\"0.8\">\n");
        foreach (var t in tick_list) {
            double x = x_of(t) + SIDE_PADDING + 0.5;
            sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"1\" shape-rendering=\"crispEdges\"/>\n".printf(
                f(x), f(base_y), f(x), f(GRID_START), c_grid));
            text(x, base_y + 3 + 10, MermaidGanttTime.format_d3(t, fmt), 10, c_title, "middle");
            if (d.top_axis) {
                double top = TOP_PADDING;
                sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"1\" shape-rendering=\"crispEdges\"/>\n".printf(
                    f(x), f(top), f(x), f(top + height - TOP_PADDING - GRID_START), c_grid));
                text(x, top - 3, MermaidGanttTime.format_d3(t, fmt), 10, c_title, "middle");
            }
        }
        sb.append("</g>\n");
    }

    private void draw_bands() {
        var drawn = new Gee.HashSet<int>();
        double w = WIDTH - RIGHT_PADDING / 2;
        foreach (var t in d.tasks) {
            if (t.is_vert) continue;
            int row = rows[t];
            if (drawn.contains(row)) continue;
            drawn.add(row);
            double opacity;
            string fill = section_fill(section_index(t.section_name), out opacity);
            if (opacity <= 0) continue;
            sb.append("<rect x=\"0\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" fill-opacity=\"%s\"/>\n".printf(
                f(row * (BAR_HEIGHT + BAR_GAP) + TOP_PADDING - 2), f(w), f(BAR_HEIGHT + BAR_GAP),
                fill, f(opacity)));
        }
    }

    private void bar_colours(GanttTask t, out string fill, out string stroke) {
        if (t.is_active) {
            fill = "#BFC7FF";
            stroke = t.is_crit ? "#FF8888" : "#534FBC";
        } else if (t.is_done) {
            fill = "#D3D3D3";
            stroke = t.is_crit ? "#FF8888" : "#808080";
        } else if (t.is_crit) {
            fill = "#FF0000";
            stroke = "#FF8888";
        } else {
            fill = "#8A90DD";
            stroke = "#534FBC";
        }
        if (t.is_vert) stroke = c_vert;
    }

    public static string region_name(GanttTask t) {
        return "task_%s".printf(RenderUtils.sanitize_id(t.id));
    }

    private void draw_tasks() {
        // Vert markers are drawn last, as in Mermaid
        var ordered = new Gee.ArrayList<GanttTask>();
        foreach (var t in d.tasks) if (!t.is_vert) ordered.add(t);
        // Mermaid sizes the vert marker from `tasksWithoutVert.length`, the
        // number of ordinary tasks — not from the row count, which `compact`
        // collapses, leaving the marker far too short.
        int vert_span = ordered.size;
        ordered.sort((a, b) => a.start_ms < b.start_ms ? -1 : (a.start_ms > b.start_ms ? 1 : 0));
        foreach (var t in d.tasks) if (t.is_vert) ordered.add(t);

        var labels = new StringBuilder();
        foreach (var t in ordered) {
            int row = t.is_vert ? 0 : rows[t];
            double gap = BAR_HEIGHT + BAR_GAP;
            double top = row * gap + TOP_PADDING;
            double x0 = x_of(t.start_ms);
            double x_end = x_of(t.end_ms);
            double x_render_end = x_of(t.visible_end_ms());
            string fill, stroke;
            bar_colours(t, out fill, out stroke);

            double rx = 0, ry = 0, rw = 0, rh = 0;
            if (t.is_milestone && !t.is_vert) {
                double cx = x0 + SIDE_PADDING + 0.5 * (x_end - x0);
                double cy = top + 0.5 * BAR_HEIGHT;
                double r = BAR_HEIGHT * 0.8 / Math.SQRT2;   // rotate(45) scale(0.8) of a 20 px square
                sb.append("<polygon points=\"%s,%s %s,%s %s,%s %s,%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.6\" stroke-linejoin=\"round\"/>\n".printf(
                    f(cx), f(cy - r), f(cx + r), f(cy), f(cx), f(cy + r), f(cx - r), f(cy), fill, stroke));
                rx = cx - r; ry = cy - r; rw = 2 * r; rh = 2 * r;
            } else if (t.is_vert) {
                double x = x0 + SIDE_PADDING;
                double h = vert_span * gap + BAR_HEIGHT * 2;
                sb.append("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"3\" ry=\"3\" fill=\"%s\" stroke=\"%s\" stroke-width=\"2\"/>\n".printf(
                    f(x), f(GRID_START), f(0.08 * BAR_HEIGHT), f(h), fill, stroke));
                rx = x - 2; ry = GRID_START; rw = 4; rh = h;
            } else {
                double x = x0 + SIDE_PADDING;
                double w = x_render_end - x0;
                if (w > 0) {
                    sb.append("<rect id=\"%s\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"3\" ry=\"3\" fill=\"%s\" stroke=\"%s\" stroke-width=\"2\"/>\n".printf(
                        esc(region_name(t)), f(x), f(top), f(w), f(BAR_HEIGHT), fill, stroke));
                }
                rx = x; ry = top; rw = double.max(w, 1); rh = BAR_HEIGHT;
            }

            // Label position (x from the render end, class from the end)
            double sx = x0, ex = x_render_end;
            if (t.is_milestone) {
                sx += 0.5 * (x_end - x0) - 0.5 * BAR_HEIGHT;
                ex = sx + BAR_HEIGHT;
            }
            double tw = text_width(t.description, FONT_SIZE, t.clickable);
            double tx;
            if (t.is_vert) {
                tx = x0 + SIDE_PADDING;
            } else if (tw > ex - sx) {
                tx = (ex + tw + 1.5 * SIDE_PADDING > WIDTH) ? sx + SIDE_PADDING - 5 : ex + SIDE_PADDING + 5;
            } else {
                tx = (ex - sx) / 2 + sx + SIDE_PADDING;
            }
            double cls_ex = t.is_milestone ? x0 + BAR_HEIGHT : x_end;
            string anchor;
            bool outside = tw > cls_ex - x0;
            if (outside) {
                anchor = (cls_ex + tw + 1.5 * SIDE_PADDING > WIDTH) ? "end" : "start";
            } else {
                anchor = "middle";
            }
            string colour;
            if (t.clickable) {
                colour = outside ? c_click : "#003163";
            } else if (outside) {
                colour = c_text;
            } else if (t.is_active || t.is_done) {
                colour = "#000000";
            } else {
                colour = "#FFFFFF";
            }
            double size = FONT_SIZE;
            double ty = top + BAR_HEIGHT / 2 + (FONT_SIZE / 2 - 2);
            if (t.is_vert) {
                anchor = "middle";
                colour = c_vert;
                size = 15;
                ty = GRID_START + vert_span * gap + 60;
            }
            text_to(labels, tx, ty, t.description, size, colour, anchor, t.clickable, t.is_milestone);

            double lx = anchor == "middle" ? tx - tw / 2 : (anchor == "end" ? tx - tw : tx);
            double left = double.min(rx, lx), right = double.max(rx + rw, lx + tw);
            if (!t.is_vert) {
                regions.add(new ElementRegion(region_name(t), t.source_line, left, ry,
                                              right - left, rh));
            }
        }
        sb.append(labels.str);
    }

    private void draw_section_titles() {
        var counts = new Gee.ArrayList<int>();
        foreach (string cat in categories) {
            int c = 0;
            if (d.compact) {
                int lo = int.MAX, hi = -1;
                foreach (var t in d.tasks) {
                    if (t.is_vert || t.section_name != cat) continue;
                    lo = int.min(lo, rows[t]);
                    hi = int.max(hi, rows[t]);
                }
                c = hi >= lo ? hi - lo + 1 : 0;
            } else {
                foreach (var t in d.tasks) if (!t.is_vert && t.section_name == cat) c++;
            }
            counts.add(c);
        }
        double gap = BAR_HEIGHT + BAR_GAP;
        int prev = 0;
        for (int i = 0; i < categories.size; i++) {
            string[] lines = Regex.split_simple("<br\\s*/?>", categories[i], RegexCompileFlags.CASELESS);
            double y = counts[i] * gap / 2 + prev * gap + TOP_PADDING;
            prev += counts[i];
            // alignment-baseline central: centre each row on its line
            double first = y - (lines.length - 1) / 2.0 * FONT_SIZE;
            for (int k = 0; k < lines.length; k++) {
                text(10, first + k * FONT_SIZE + FONT_SIZE * 0.35, lines[k].strip(), FONT_SIZE, c_title);
            }
        }
    }

    private void draw_today() {
        if (d.today_marker == "off") return;
        int64 today = MermaidGanttScheduler.today(d);
        double x = x_of(today) + SIDE_PADDING;
        if (x < -10 || x > WIDTH + 10) return;
        string stroke = "#FF0000";
        string width = "2";
        string extra = "";
        foreach (string decl in d.today_marker.split(",")) {
            int c = decl.index_of(":");
            if (c <= 0) continue;
            string key = decl.substring(0, c).strip();
            string val = decl.substring(c + 1).strip();
            if (key == "stroke") stroke = val;
            else if (key == "stroke-width") width = val.replace("px", "");
            else if (key == "opacity" || key == "stroke-opacity") extra += " %s=\"%s\"".printf(key, esc(val));
            else if (key == "stroke-dasharray") extra += " stroke-dasharray=\"%s\"".printf(esc(val));
        }
        sb.append("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"%s\"%s/>\n".printf(
            f(x), f(TITLE_TOP), f(x), f(height - TITLE_TOP), esc(stroke), esc(width), extra));
    }

    public string build() {
        sb = new StringBuilder();
        regions.clear();
        if (d.tasks.size > 0) {
            draw_exclude_days();
            draw_grid();
            draw_bands();
            draw_tasks();
            draw_section_titles();
            draw_today();
        }
        if (d.title != null && d.title.length > 0) {
            text(WIDTH / 2, TITLE_TOP, d.title, 18, c_title, "middle");
        }
        var doc = new StringBuilder();
        doc.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        doc.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%spx\" height=\"%spx\" viewBox=\"0 0 %s %s\">\n".printf(
            f(WIDTH), f(height), f(WIDTH), f(height)));
        doc.append("<rect x=\"0\" y=\"0\" width=\"100%%\" height=\"100%%\" fill=\"%s\"/>\n".printf(c_bg));
        doc.append("<g font-family=\"sans-serif\">\n");
        doc.append(sb.str);
        doc.append("</g>\n</svg>\n");
        return doc.str;
    }
}

}
