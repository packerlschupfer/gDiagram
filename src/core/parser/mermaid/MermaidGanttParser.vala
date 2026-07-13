/* MermaidGanttParser.vala — Mermaid gantt parser and scheduler.
 *
 * Follows Mermaid 11.17's gantt.jison lexer and ganttDb.js: statements are
 * recognised per line, task data is "tags, [id,] [start,] end" split on
 * commas, and dates are resolved with the same multi-pass compile (after /
 * until references, excludes that push end dates out, inclusiveEndDates).
 * Times are milliseconds since the epoch using calendar arithmetic in UTC, so
 * a chart lays out identically in every time zone.
 */
namespace GDiagram {

public class MermaidGanttParser : Object {
    private MermaidGantt diagram;
    private GanttSection? current_section;
    private string current_section_name;
    private int task_counter;
    private string? last_task_id;

    public MermaidGanttParser() {
    }

    public MermaidGantt parse(string source) {
        this.diagram = new MermaidGantt();
        this.current_section = null;
        this.current_section_name = "";
        this.task_counter = 0;
        this.last_task_id = null;

        string[] lines = source.replace("\r\n", "\n").split("\n");
        int i = 0;
        bool seen_gantt = false;

        // YAML front matter: title and displayMode
        while (i < lines.length && lines[i].strip().length == 0) i++;
        if (i < lines.length && lines[i].strip() == "---") {
            int j = i + 1;
            while (j < lines.length && lines[j].strip() != "---") {
                string fl = lines[j].strip();
                if (fl.has_prefix("title:")) {
                    diagram.title = unquote(fl.substring(6).strip());
                } else if (fl.has_prefix("displayMode:")) {
                    diagram.compact = unquote(fl.substring(12).strip()) == "compact";
                }
                j++;
            }
            i = j < lines.length ? j + 1 : j;
        }

        for (; i < lines.length; i++) {
            string raw = lines[i];
            string line = raw.chug();
            int line_no = i + 1;
            if (line.strip().length == 0) continue;

            // %%{init: ...}%% directives, possibly spanning lines
            if (line.has_prefix("%%{")) {
                var dir = new StringBuilder(line);
                while (!dir.str.contains("}%%") && i + 1 < lines.length) {
                    i++;
                    dir.append("\n").append(lines[i]);
                }
                apply_directive(dir.str);
                continue;
            }
            if (line.has_prefix("%%")) continue;

            if (!seen_gantt) {
                if (line.down().has_prefix("gantt") &&
                    (line.length == 5 || !is_word_char(line[5]))) {
                    seen_gantt = true;
                    string rest = line.substring(5).strip();
                    if (rest.length == 0) continue;
                    line = rest;
                } else {
                    diagram.errors.add(new ParseError("Expected 'gantt' (found: '%s')".printf(
                        line.strip()), line_no, 1));
                    return diagram;
                }
            }

            // accDescr { ... } spans lines
            if (match_keyword(line, "accDescr") && line.substring(8).strip().has_prefix("{")) {
                while (!lines[i].contains("}") && i + 1 < lines.length) i++;
                continue;
            }

            parse_line(line, line_no);
        }

        if (!seen_gantt) {
            diagram.errors.add(new ParseError("Expected 'gantt'", 1, 1));
            return diagram;
        }

        MermaidGanttScheduler.schedule(diagram);
        return diagram;
    }

    private void apply_directive(string text) {
        try {
            var re = new Regex("[\"']?displayMode[\"']?\\s*:\\s*[\"']?compact");
            if (re.match(text)) diagram.compact = true;
        } catch (RegexError e) {
            warning("gantt directive regex: %s", e.message);
        }
    }

    private static string unquote(string s) {
        if (s.length >= 2 && ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                              (s.has_prefix("'") && s.has_suffix("'")))) {
            return s.substring(1, s.length - 2);
        }
        return s;
    }

    private static bool is_word_char(char c) {
        return c.isalnum() || c == '_';
    }

    // Case-insensitive keyword at the start of the line followed by a
    // non-word character (or the end)
    private static bool match_keyword(string line, string keyword) {
        if (line.length < keyword.length) return false;
        if (line.substring(0, keyword.length).down() != keyword.down()) return false;
        return line.length == keyword.length || !is_word_char(line[keyword.length]);
    }

    // Keyword followed by whitespace and a value; the value stops at # or ;
    private static string? keyword_value(string line, string keyword, bool stop_at_hash = true) {
        if (line.length <= keyword.length) return null;
        if (line.substring(0, keyword.length).down() != keyword.down()) return null;
        if (!line[keyword.length].isspace()) return null;
        string v = line.substring(keyword.length + 1);
        int cut = -1;
        for (int k = 0; k < v.length; k++) {
            if ((stop_at_hash && v[k] == '#') || v[k] == ';') { cut = k; break; }
        }
        if (cut >= 0) v = v.substring(0, cut);
        return v.strip().length > 0 ? v : null;
    }

    private void parse_line(string line, int line_no) {
        string? v;
        if ((v = keyword_value(line, "dateFormat")) != null) {
            diagram.date_format = v.strip();
            return;
        }
        if (match_keyword(line, "inclusiveEndDates")) {
            diagram.inclusive_end_dates = true;
            return;
        }
        if (match_keyword(line, "topAxis")) {
            diagram.top_axis = true;
            return;
        }
        if ((v = keyword_value(line, "axisFormat")) != null) {
            diagram.axis_format = v.strip();
            return;
        }
        if ((v = keyword_value(line, "tickInterval")) != null) {
            diagram.tick_interval = v.strip();
            return;
        }
        if ((v = keyword_value(line, "includes")) != null) {
            merge_tokens(diagram.includes, v);
            return;
        }
        if ((v = keyword_value(line, "excludes")) != null) {
            merge_tokens(diagram.excludes, v);
            return;
        }
        if ((v = keyword_value(line, "todayMarker", false)) != null) {
            diagram.today_marker = v.strip();
            return;
        }
        if (match_keyword(line, "weekday")) {
            string day = line.substring(7).strip().down();
            switch (day) {
                case "monday": case "tuesday": case "wednesday": case "thursday":
                case "friday": case "saturday": case "sunday":
                    diagram.weekday = day;
                    return;
            }
        }
        if (match_keyword(line, "weekend")) {
            string day = line.substring(7).strip().down();
            if (day == "friday" || day == "saturday") {
                diagram.weekend = day;
                return;
            }
        }
        if (line.length > 6 && line.substring(0, 5).down() == "title" && line[5].isspace()) {
            diagram.title = line.substring(6).strip();
            return;
        }
        if (match_keyword(line, "accTitle") || match_keyword(line, "accDescr") ||
            match_keyword(line, "accDescription")) {
            return;
        }
        if (line.length > 8 && line.substring(0, 7).down() == "section" && line[7].isspace()) {
            current_section_name = line.substring(8).strip();
            current_section = new GanttSection(current_section_name);
            diagram.sections.add(current_section);
            return;
        }
        if (line.length > 6 && line.substring(0, 5).down() == "click" && line[5].isspace()) {
            parse_click(line.substring(6).strip());
            return;
        }

        int colon = line.index_of(":");
        if (colon <= 0) {
            diagram.errors.add(new ParseError(
                "Expected ':' and task data after '%s'".printf(line.strip()), line_no, 1));
            return;
        }
        string description = line.substring(0, colon).strip();
        string data = line.substring(colon + 1);
        for (int k = 0; k < data.length; k++) {
            if (data[k] == '#' || data[k] == ';') { data = data.substring(0, k); break; }
        }
        add_task(description, data, line_no);
    }

    private static void merge_tokens(Gee.ArrayList<string> list, string text) {
        foreach (string tok in text.down().replace(",", " ").replace("\t", " ").split(" ")) {
            if (tok.length > 0 && !list.contains(tok)) list.add(tok);
        }
    }

    // click taskId[,taskId] href "url"  |  click taskId call fn(args)
    private void parse_click(string rest) {
        int sp = 0;
        while (sp < rest.length && !rest[sp].isspace()) sp++;
        string ids = rest.substring(0, sp);
        string tail = rest.substring(sp).strip();
        string? url = null;
        if (tail.down().has_prefix("href")) {
            int q1 = tail.index_of("\"");
            int q2 = q1 >= 0 ? tail.index_of("\"", q1 + 1) : -1;
            if (q1 >= 0 && q2 > q1) url = tail.substring(q1 + 1, q2 - q1 - 1);
        }
        foreach (string id in ids.split(",")) {
            var t = find_last(id.strip());
            if (t == null) continue;
            t.clickable = true;
            if (url != null) t.link = url;
        }
    }

    private GanttTask? find_last(string id) {
        for (int k = diagram.tasks.size - 1; k >= 0; k--) {
            if (diagram.tasks[k].id == id) return diagram.tasks[k];
        }
        return null;
    }

    private void add_task(string description, string data, int line_no) {
        var parts = new Gee.ArrayList<string>();
        foreach (string p in data.split(",")) parts.add(p);

        var task = new GanttTask("", description, line_no);
        task.section_name = current_section_name;

        // Leading tags (exact words, case-sensitive like Mermaid)
        bool found = true;
        while (found && parts.size > 0) {
            found = false;
            string head = parts[0].strip();
            switch (head) {
                case "active":    task.is_active = true; found = true; break;
                case "done":      task.is_done = true; found = true; break;
                case "crit":      task.is_crit = true; found = true; break;
                case "milestone": task.is_milestone = true; found = true; break;
                case "vert":      task.is_vert = true; found = true; break;
            }
            if (found) parts.remove_at(0);
        }
        for (int k = 0; k < parts.size; k++) parts[k] = parts[k].strip();

        string id;
        if (parts.size >= 3) {
            id = parts[0];
            task.raw_start = parts[1];
            task.raw_end = parts[2];
        } else if (parts.size == 2) {
            id = "task%d".printf(++task_counter);
            task.raw_start = parts[0];
            task.raw_end = parts[1];
        } else {
            id = "task%d".printf(++task_counter);
            task.raw_start = "";
            task.raw_end = parts.size == 1 ? parts[0] : "";
        }
        task.id = id;
        task.prev_task_id = last_task_id;

        // Status for linters / outline: the most significant tag
        if (task.is_milestone) task.status = GanttTaskStatus.MILESTONE;
        else if (task.is_crit) task.status = GanttTaskStatus.CRITICAL;
        else if (task.is_active) task.status = GanttTaskStatus.ACTIVE;
        else if (task.is_done) task.status = GanttTaskStatus.DONE;
        else task.status = GanttTaskStatus.NONE;

        // Reference lists and the legacy string fields
        string? after = MermaidGanttScheduler.reference_ids(task.raw_start, "after", task.after_ids);
        if (after != null) task.depends_on = task.after_ids.size > 0 ? task.after_ids[0] : null;
        MermaidGanttScheduler.reference_ids(task.raw_end, "until", task.until_ids);
        if (after == null && task.raw_start.length > 0) task.start_date = task.raw_start;
        if (task.until_ids.size == 0 && task.raw_end.length > 0) {
            double val;
            string unit;
            if (MermaidGanttTime.parse_duration(task.raw_end, out val, out unit)) {
                task.duration = task.raw_end;
            } else {
                task.end_date = task.raw_end;
            }
        } else if (task.until_ids.size > 0) {
            task.end_date = task.raw_end;
        }

        if (task.is_vert) {
            task.order = -1;
        } else {
            int count = 0;
            foreach (var t in diagram.tasks) if (!t.is_vert) count++;
            task.order = count;
        }

        if (current_section != null) current_section.add_task(task);
        diagram.add_task(task);
        last_task_id = id;
    }
}

// ==================== Scheduling ====================

public class MermaidGanttScheduler : Object {
    private const int64 DAY = 86400000;

    // "after a b" → ids; returns the id text or null when not that form
    public static string? reference_ids(string text, string keyword, Gee.ArrayList<string> ids) {
        string t = text.strip();
        if (!t.has_prefix(keyword)) return null;
        string rest = t.substring(keyword.length);
        if (rest.length == 0 || !rest[0].isspace()) return null;
        rest = rest.strip();
        // Mermaid's id pattern is [\d\w- ]+
        int end = 0;
        while (end < rest.length && (rest[end].isalnum() || rest[end] == '_' ||
                                     rest[end] == '-' || rest[end] == ' ')) end++;
        if (end == 0) return null;
        foreach (string id in rest.substring(0, end).split(" ")) {
            if (id.length > 0) ids.add(id);
        }
        return rest.substring(0, end);
    }

    public static int64 today(MermaidGantt d) {
        if (d.today_ms >= 0) return d.today_ms;
        var now = new DateTime.now_local();
        var midnight = new DateTime.utc(now.get_year(), now.get_month(), now.get_day_of_month(), 0, 0, 0);
        return midnight.to_unix() * 1000;
    }

    public static void schedule(MermaidGantt d) {
        var by_id = new Gee.HashMap<string, GanttTask>();
        foreach (var t in d.tasks) by_id[t.id] = t;   // later duplicates win, as in Mermaid

        foreach (var t in d.tasks) t.scheduled = false;
        bool all = compile_pass(d, by_id);
        for (int pass = 0; pass < 10 && !all; pass++) {
            all = compile_pass(d, by_id);
        }

        // Anything still unresolved (a cycle, a first task without a start)
        // starts where the chart starts so it stays visible
        if (!all) {
            int64 origin = int64.MAX;
            foreach (var t in d.tasks) if (t.scheduled && t.start_ms < origin) origin = t.start_ms;
            if (origin == int64.MAX) origin = today(d);
            foreach (var t in d.tasks) {
                if (t.scheduled) continue;
                t.start_ms = origin;
                int64 end;
                if (!end_from_expression(d, by_id, t, origin, out end)) end = origin;
                t.end_ms = end;
                t.render_end_ms = -1;
                t.scheduled = true;
            }
        }
    }

    private static bool compile_pass(MermaidGantt d, Gee.HashMap<string, GanttTask> by_id) {
        bool all = true;
        foreach (var t in d.tasks) {
            bool have_start = t.scheduled;
            int64 start = t.start_ms;

            if (t.raw_start.length == 0) {
                var prev = t.prev_task_id != null ? by_id[t.prev_task_id] : null;
                if (prev != null && prev.scheduled) {
                    start = prev.end_ms;
                    have_start = true;
                }
            } else if (t.after_ids.size > 0) {
                GanttTask? latest = null;
                bool any = false;
                foreach (string id in t.after_ids) {
                    var other = by_id[id];
                    if (other == null) continue;
                    if (!any) { latest = other; any = true; continue; }
                    // An unresolved end never compares greater (undefined in JS)
                    if (latest.scheduled && other.scheduled && other.end_ms > latest.end_ms) latest = other;
                }
                if (!any) {
                    start = today(d);
                    have_start = true;
                } else if (latest.scheduled) {
                    start = latest.end_ms;
                    have_start = true;
                }
            } else {
                int64 parsed;
                if (MermaidGanttTime.parse_start(t.raw_start, d.date_format ?? "", out parsed)) {
                    start = parsed;
                    have_start = true;
                } else if (!t.scheduled) {
                    d.errors.add(new ParseError("Invalid date:%s".printf(t.raw_start), t.source_line, 1));
                    start = today(d);
                    have_start = true;
                }
            }

            if (have_start) {
                int64 end;
                if (end_from_expression(d, by_id, t, start, out end)) {
                    t.start_ms = start;
                    t.end_ms = end;
                    t.render_end_ms = -1;
                    t.scheduled = true;
                    int64 ignored;
                    t.manual_end = MermaidGanttTime.parse_format(t.raw_end.strip(), "YYYY-MM-DD", out ignored);
                    check_task_dates(d, t);
                }
            }
            all = all && t.scheduled;
        }
        return all;
    }

    // getEndDate: until ids, a date in dateFormat, or a duration
    private static bool end_from_expression(MermaidGantt d, Gee.HashMap<string, GanttTask> by_id,
                                            GanttTask t, int64 start, out int64 end) {
        end = start;
        if (t.until_ids.size > 0) {
            GanttTask? earliest = null;
            foreach (string id in t.until_ids) {
                var other = by_id[id];
                if (other == null) continue;
                if (earliest == null) { earliest = other; continue; }
                if (earliest.scheduled && other.scheduled && other.start_ms < earliest.start_ms) earliest = other;
            }
            if (earliest == null) {
                end = today(d);
                return true;
            }
            if (!earliest.scheduled) return false;
            end = earliest.start_ms;
            return true;
        }
        string fmt = d.date_format ?? "";
        int64 parsed = 0;
        if (fmt.strip().length > 0 && MermaidGanttTime.parse_format(t.raw_end.strip(), fmt.strip(), out parsed)) {
            end = d.inclusive_end_dates ? MermaidGanttTime.add(parsed, 1, "d") : parsed;
            return true;
        }
        double val;
        string unit;
        if (MermaidGanttTime.parse_duration(t.raw_end, out val, out unit)) {
            end = MermaidGanttTime.add(start, val, unit);
        }
        return true;
    }

    // checkTaskDates / fixTaskDates: excluded days push the end out; the
    // bar is drawn to the last end reached from a valid day
    private static void check_task_dates(MermaidGantt d, GanttTask t) {
        if (d.excludes.size == 0 || t.manual_end) return;
        int64 cur = MermaidGanttTime.add(t.start_ms, 1, "d");
        int64 end = t.end_ms;
        int64 max_end = MermaidGanttTime.add(end, 10000, "d");
        bool invalid = false;
        int64 render_end = -1;
        while (cur <= end) {
            if (!invalid) render_end = end;
            invalid = is_invalid_date(d, cur);
            if (invalid) {
                end = MermaidGanttTime.add(end, 1, "d");
                if (end > max_end) break;
            }
            cur = MermaidGanttTime.add(cur, 1, "d");
        }
        t.end_ms = end;
        t.render_end_ms = render_end;
    }

    public static bool is_invalid_date(MermaidGantt d, int64 ms) {
        string fmt = (d.date_format ?? "").strip();
        string formatted = MermaidGanttTime.format_dayjs(ms, fmt.length > 0 ? fmt : "YYYY-MM-DDTHH:mm:ssZ");
        string date_only = MermaidGanttTime.format_dayjs(ms, "YYYY-MM-DD");
        if (d.includes.contains(formatted) || d.includes.contains(date_only)) return false;
        int wd = MermaidGanttTime.iso_weekday(ms);
        if (d.excludes.contains("weekends")) {
            int first = d.weekend == "friday" ? 5 : 6;
            if (wd == first || wd == first + 1) return true;
        }
        if (d.excludes.contains(MermaidGanttTime.format_dayjs(ms, "dddd").down())) return true;
        return d.excludes.contains(formatted) || d.excludes.contains(date_only);
    }
}

// ==================== Date helpers ====================

public class MermaidGanttTime : Object {
    private const string[] MONTHS = {
        "January", "February", "March", "April", "May", "June", "July",
        "August", "September", "October", "November", "December"
    };
    private const string[] DAYS = {
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    };

    public static int64 make(int year, int month, int day, int hour = 0, int minute = 0,
                             int second = 0, int ms = 0) {
        var dt = new DateTime.utc(year, month, day, hour, minute, second);
        if (dt == null) return int64.MIN;
        return dt.to_unix() * 1000 + ms;
    }

    // GLib's DateTime only covers years 1..9999 and returns NULL outside it —
    // without logging, but every getter then asserts. A millisecond timestamp
    // fed to `dateFormat X` (seconds), or a `999999999d` duration, lands there.
    public const int64 MIN_MS = -62135596800000;    // 0001-01-01T00:00:00Z
    public const int64 MAX_MS = 253402300799999;    // 9999-12-31T23:59:59.999Z

    public static bool is_representable(int64 ms) {
        return ms >= MIN_MS && ms <= MAX_MS;
    }

    private static int64 clamp_ms(int64 ms) {
        return ms < MIN_MS ? MIN_MS : (ms > MAX_MS ? MAX_MS : ms);
    }

    // Never null: an out-of-range instant is pinned to the nearest end of the
    // representable range, so the chart still gets an axis instead of a run of
    // g_date_time_* criticals and a zeroed, inverted scale.
    private static DateTime to_dt(int64 ms) {
        int64 c = clamp_ms(ms);
        int64 sec = c >= 0 ? c / 1000 : -((-c + 999) / 1000);
        var dt = new DateTime.from_unix_utc(sec);
        if (dt == null) dt = new DateTime.utc(1, 1, 1, 0, 0, 0);
        return dt;
    }

    private static int millis(int64 ms) {
        int64 r = ms % 1000;
        if (r < 0) r += 1000;
        return (int) r;
    }

    public static void parts(int64 ms, out int year, out int month, out int day,
                             out int hour, out int minute, out int second, out int milli) {
        var dt = to_dt(ms);
        year = dt.get_year();
        month = dt.get_month();
        day = dt.get_day_of_month();
        hour = dt.get_hour();
        minute = dt.get_minute();
        second = dt.get_second();
        milli = millis(ms);
    }

    // 1 = Monday … 7 = Sunday
    public static int iso_weekday(int64 ms) {
        return to_dt(ms).get_day_of_week();
    }

    public static int64 start_of_day(int64 ms) {
        int y, mo, d, h, mi, s, l;
        parts(ms, out y, out mo, out d, out h, out mi, out s, out l);
        return make(y, mo, d);
    }

    // dayjs .add(value, unit): calendar units for d/w/M/y
    public static int64 add(int64 ms, double value, string unit) {
        switch (unit) {
            case "ms": return ms + (int64) Math.round(value);
            case "s":  return ms + (int64) Math.round(value * 1000);
            case "m":  return ms + (int64) Math.round(value * 60000);
            case "h":  return ms + (int64) Math.round(value * 3600000);
            case "d":
            case "w": {
                double days = unit == "w" ? value * 7 : value;
                if (days > int.MAX || days < int.MIN) return ms;
                int64 whole = (int64) Math.floor(days);
                // add_days/add_months/add_years all return null when the result
                // leaves year 1..9999; dayjs answers an Invalid Date there and
                // Mermaid drops the task, so keep the instant unchanged.
                var dt = to_dt(ms).add_days((int) whole);
                if (dt == null) return ms;
                int64 r = dt.to_unix() * 1000 + millis(ms);
                return r + (int64) Math.round((days - whole) * 86400000.0);
            }
            case "M": {
                if (value > int.MAX || value < int.MIN) return ms;
                var dt = to_dt(ms).add_months((int) Math.round(value));
                if (dt == null) return ms;
                return dt.to_unix() * 1000 + millis(ms);
            }
            case "y": {
                if (value > int.MAX || value < int.MIN) return ms;
                var dt = to_dt(ms).add_years((int) Math.round(value));
                if (dt == null) return ms;
                return dt.to_unix() * 1000 + millis(ms);
            }
        }
        return ms;
    }

    // /^(\d+(?:\.\d+)?)([Mdhmswy]|ms)$/
    public static bool parse_duration(string text, out double value, out string unit) {
        value = 0;
        unit = "ms";
        string t = text.strip();
        int i = 0;
        while (i < t.length && t[i].isdigit()) i++;
        if (i == 0) return false;
        if (i < t.length && t[i] == '.') {
            int j = i + 1;
            while (j < t.length && t[j].isdigit()) j++;
            if (j == i + 1) return false;
            i = j;
        }
        string u = t.substring(i);
        if (u != "ms" && (u.length != 1 || !"Mdhmswy".contains(u))) return false;
        value = double.parse(t.substring(0, i));
        unit = u;
        return true;
    }

    // getStartDate's date part: strict dateFormat, then the JS Date fallbacks
    public static bool parse_start(string text, string format, out int64 ms) {
        string s = text.strip();
        string fmt = format.strip();
        ms = 0;
        if ((fmt == "x" || fmt == "X") && s.length > 0) {
            bool digits = true;
            for (int i = 0; i < s.length; i++) if (!s[i].isdigit()) { digits = false; break; }
            if (digits) {
                // Clamped: a JS millisecond timestamp handed to `dateFormat X`
                // (seconds) lands past year 9999, where GLib has no DateTime.
                ms = clamp_ms(int64.parse(s) * (fmt == "X" ? 1000 : 1));
                return true;
            }
        }
        if (fmt.length > 0 && parse_format(s, fmt, out ms)) return true;
        return parse_js_date(s, out ms);
    }

    /**
     * The local UTC offset in milliseconds at the given instant.
     *
     * Every other timestamp here is a wall-clock time stored as if it were
     * UTC, which is what dayjs's local parsing and local formatting add up to.
     * `new Date(str)` is the one branch that is genuinely UTC, so its result
     * has to be shifted into that wall-clock frame.
     */
    private static int64 local_offset_ms(int64 utc_ms) {
        int64 c = utc_ms;
        if (c < MermaidGanttTime.MIN_MS) c = MermaidGanttTime.MIN_MS;
        if (c > MermaidGanttTime.MAX_MS) c = MermaidGanttTime.MAX_MS;
        var instant = new DateTime.from_unix_utc(c >= 0 ? c / 1000 : -((-c + 999) / 1000));
        if (instant == null) return 0;
        return instant.to_local().get_utc_offset() / 1000;
    }

    // The common shapes new Date(string) accepts
    public static bool parse_js_date(string s, out int64 ms) {
        ms = 0;
        try {
            var re = new Regex("^(\\d{4})([-/])(\\d{1,2})[-/](\\d{1,2})(?:([T ])(\\d{1,2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d{1,3}))?)?)?(Z?)$");
            MatchInfo m;
            if (re.match(s, 0, out m)) {
                string sep = m.fetch(2);
                string mos = m.fetch(3), ds = m.fetch(4);
                int y = int.parse(m.fetch(1)), mo = int.parse(mos), d = int.parse(ds);
                string? tsep = m.fetch(5);
                string? hs = m.fetch(6);
                int h = hs != null && hs.length > 0 ? int.parse(hs) : 0;
                string? mis = m.fetch(7);
                int mi = mis != null && mis.length > 0 ? int.parse(mis) : 0;
                string? ss = m.fetch(8);
                int sec = ss != null && ss.length > 0 ? int.parse(ss) : 0;
                // `new Date(string)` only checks the ranges the ISO grammar spells
                // out — it does not check the day against the month. A day past the
                // end of its month, or hour 24, rolls forward ("2024-02-30" is
                // 2024-03-01, "2024-01-01T24:00" is the 2nd), while a month past 12
                // or a day past 31 has no ISO reading at all and stays invalid.
                if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 24 || mi > 59 || sec > 59) return false;
                if (y < 1) {
                    // JS has year 0 (mermaid only rejects |year| > 10000), GLib's
                    // DateTime starts at year 1. Pin it to the earliest instant the
                    // renderer can draw, the same clamp to_dt() already applies —
                    // a chart from year 0 beats refusing the file.
                    ms = MIN_MS;
                    return true;
                }
                // Built from the first of the month so the surplus days roll over.
                int64 base_ms = make(y, mo, 1);
                if (base_ms == int64.MIN) return false;
                ms = clamp_ms(base_ms + ((int64) (d - 1)) * 86400000 + ((int64) h) * 3600000
                              + ((int64) mi) * 60000 + ((int64) sec) * 1000);
                // ECMAScript: a date-only ISO string ("2024-01-01") is UTC, and
                // so is any form with a trailing Z; a date-time without an
                // offset, and anything the legacy parser handles ("2024/01/01",
                // "2024-1-1", a space separator), is local. Mermaid only takes
                // this branch when there is no usable dateFormat.
                bool has_time = tsep != null && tsep.length > 0;
                bool iso_date = sep == "-" && mos.length == 2 && ds.length == 2;
                bool is_utc = m.fetch(10) == "Z" || (iso_date && !has_time);
                if (is_utc) ms += local_offset_ms(ms);
                return true;
            }
        } catch (RegexError e) {
            warning("gantt date regex: %s", e.message);
        }
        return false;
    }

    // Strict validity, as dayjs's customParseFormat checks it: no rollover, the day
    // has to exist in its month. `Date.get_days_in_month()` asserts outside GDate's
    // year range, so year 0 (which strict dayjs rejects anyway) is caught first —
    // "0000-01-01" used to reach it and log a GLib critical.
    private static bool valid_parts(int y, int mo, int d, int h, int mi, int s) {
        if (y < 1 || y > 9999) return false;
        if (mo < 1 || mo > 12 || d < 1 || h > 24 || mi > 59 || s > 59) return false;
        if (d > (int) Date.get_days_in_month((DateMonth) mo, (DateYear) y)) return false;
        return true;
    }

    private static string[] tokenize(string format) {
        // dayjs customParseFormat tokens, longest first
        string[] toks = {};
        int i = 0;
        string[] names = { "YYYY", "MMMM", "dddd", "MMM", "SSS", "ddd", "YY", "MM", "DD", "Do",
                           "HH", "hh", "mm", "ss", "SS", "ZZ", "dd", "M", "D", "H", "h", "m",
                           "s", "S", "A", "a", "Z", "X", "x", "d", "Q" };
        while (i < format.length) {
            if (format[i] == '[') {
                int close = format.index_of("]", i);
                if (close > i) {
                    toks += "\x01" + format.substring(i + 1, close - i - 1);
                    i = close + 1;
                    continue;
                }
            }
            bool matched = false;
            foreach (string n in names) {
                if (format.length - i >= n.length && format.substring(i, n.length) == n) {
                    toks += n;
                    i += n.length;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                toks += "\x01" + format.substring(i, 1);
                i++;
            }
        }
        return toks;
    }

    // Strict dayjs(text, format, true)
    public static bool parse_format(string text, string format, out int64 ms) {
        ms = 0;
        if (format.length == 0) return false;
        var re_src = new StringBuilder("^");
        string[] toks = tokenize(format);
        foreach (string t in toks) {
            if (t.has_prefix("\x01")) {
                re_src.append(Regex.escape_string(t.substring(1)));
                continue;
            }
            switch (t) {
                case "YYYY": re_src.append("(\\d{4})"); break;
                case "YY": case "MM": case "DD": case "HH": case "hh": case "mm": case "ss": case "SS":
                    re_src.append("(\\d\\d)"); break;
                case "M": case "D": case "H": case "h": case "m": case "s":
                    re_src.append("(\\d\\d?)"); break;
                case "S": re_src.append("(\\d)"); break;
                case "SSS": re_src.append("(\\d{3})"); break;
                case "Do": re_src.append("(\\d\\d?)(?:st|nd|rd|th)"); break;
                case "MMMM": case "MMM": re_src.append("([A-Za-z]+)"); break;
                case "dddd": case "ddd": case "dd": re_src.append("[A-Za-z]+"); break;
                case "d": re_src.append("\\d"); break;
                case "A": case "a": re_src.append("([AaPp][Mm])"); break;
                case "Z": case "ZZ": re_src.append("([+-]\\d\\d:?\\d\\d|Z)"); break;
                case "X": re_src.append("(\\d+(?:\\.\\d+)?)"); break;
                case "x": re_src.append("(\\d+)"); break;
                case "Q": re_src.append("\\d"); break;
            }
        }
        re_src.append("$");
        MatchInfo m;
        try {
            var re = new Regex(re_src.str);
            if (!re.match(text, 0, out m)) return false;
        } catch (RegexError e) {
            return false;
        }

        var now = new DateTime.now_local();
        int year = -1, month = -1, day = -1, hour = 0, minute = 0, second = 0, milli = 0;
        int pm = -1;
        int64 unix_ms = int64.MIN;
        int group = 1;
        foreach (string t in toks) {
            if (t.has_prefix("\x01")) continue;
            switch (t) {
                case "dddd": case "ddd": case "dd": case "d": case "Q":
                    continue;
            }
            string v = m.fetch(group++);
            switch (t) {
                case "YYYY": year = int.parse(v); break;
                case "YY": { int yy = int.parse(v); year = yy + (yy > 68 ? 1900 : 2000); break; }
                case "MM": case "M": month = int.parse(v); break;
                case "MMMM": case "MMM": {
                    month = -1;
                    for (int k = 0; k < 12; k++) {
                        string full = MONTHS[k];
                        if ((t == "MMMM" && full.down() == v.down()) ||
                            (t == "MMM" && full.substring(0, 3).down() == v.down())) month = k + 1;
                    }
                    if (month < 0) return false;
                    break;
                }
                case "DD": case "D": case "Do": day = int.parse(v); break;
                case "HH": case "H": case "hh": case "h": hour = int.parse(v); break;
                case "mm": case "m": minute = int.parse(v); break;
                case "ss": case "s": second = int.parse(v); break;
                case "S": milli = int.parse(v) * 100; break;
                case "SS": milli = int.parse(v) * 10; break;
                case "SSS": milli = int.parse(v); break;
                case "A": case "a": pm = v.down() == "pm" ? 1 : 0; break;
                case "X": unix_ms = (int64) (double.parse(v) * 1000); break;
                case "x": unix_ms = int64.parse(v); break;
                case "Z": case "ZZ": break;
            }
        }
        if (unix_ms != int64.MIN) {
            ms = unix_ms;
            return true;
        }
        if (pm == 1 && hour < 12) hour += 12;
        if (pm == 0 && hour == 12) hour = 0;
        if (year < 0) year = now.get_year();
        if (month < 0) month = (year >= 0 && day < 0) ? now.get_month() : 1;
        if (day < 0) day = 1;
        if (!valid_parts(year, month, day, hour, minute, second) || hour > 23) return false;
        ms = make(year, month, day, hour, minute, second, milli);
        return ms != int64.MIN;
    }

    private static string pad(int v, int width) {
        string s = v.abs().to_string();
        while (s.length < width) s = "0" + s;
        return v < 0 ? "-" + s : s;
    }

    // dayjs .format()
    public static string format_dayjs(int64 ms, string format) {
        int y, mo, d, h, mi, s, l;
        parts(ms, out y, out mo, out d, out h, out mi, out s, out l);
        int wd = iso_weekday(ms) % 7;   // 0 = Sunday
        var sb = new StringBuilder();
        foreach (string t in tokenize(format)) {
            if (t.has_prefix("\x01")) { sb.append(t.substring(1)); continue; }
            switch (t) {
                case "YYYY": sb.append(pad(y, 4)); break;
                case "YY": sb.append(pad(y % 100, 2)); break;
                case "MMMM": sb.append(MONTHS[mo - 1]); break;
                case "MMM": sb.append(MONTHS[mo - 1].substring(0, 3)); break;
                case "MM": sb.append(pad(mo, 2)); break;
                case "M": sb.append(mo.to_string()); break;
                case "DD": sb.append(pad(d, 2)); break;
                case "D": sb.append(d.to_string()); break;
                case "Do": {
                    string suf = "th";
                    int r100 = d % 100;
                    if (r100 < 11 || r100 > 13) {
                        if (d % 10 == 1) suf = "st";
                        else if (d % 10 == 2) suf = "nd";
                        else if (d % 10 == 3) suf = "rd";
                    }
                    sb.append(d.to_string() + suf);
                    break;
                }
                case "dddd": sb.append(DAYS[wd]); break;
                case "ddd": sb.append(DAYS[wd].substring(0, 3)); break;
                case "dd": sb.append(DAYS[wd].substring(0, 2)); break;
                case "d": sb.append(wd.to_string()); break;
                case "HH": sb.append(pad(h, 2)); break;
                case "H": sb.append(h.to_string()); break;
                case "hh": sb.append(pad(h % 12 == 0 ? 12 : h % 12, 2)); break;
                case "h": sb.append((h % 12 == 0 ? 12 : h % 12).to_string()); break;
                case "mm": sb.append(pad(mi, 2)); break;
                case "m": sb.append(mi.to_string()); break;
                case "ss": sb.append(pad(s, 2)); break;
                case "s": sb.append(s.to_string()); break;
                case "SSS": sb.append(pad(l, 3)); break;
                case "SS": sb.append(pad(l / 10, 2)); break;
                case "S": sb.append((l / 100).to_string()); break;
                case "A": sb.append(h < 12 ? "AM" : "PM"); break;
                case "a": sb.append(h < 12 ? "am" : "pm"); break;
                case "Z": sb.append("+00:00"); break;
                case "ZZ": sb.append("+0000"); break;
                case "X": sb.append((ms / 1000).to_string()); break;
                case "x": sb.append(ms.to_string()); break;
                case "Q": sb.append(((mo - 1) / 3 + 1).to_string()); break;
            }
        }
        return sb.str;
    }

    // d3 timeFormat (strftime-like)
    public static string format_d3(int64 ms, string format) {
        int y, mo, d, h, mi, s, l;
        parts(ms, out y, out mo, out d, out h, out mi, out s, out l);
        var dt = to_dt(ms);
        int wd = dt.get_day_of_week() % 7;
        int doy = dt.get_day_of_year();
        var sb = new StringBuilder();
        for (int i = 0; i < format.length; i++) {
            char c = format[i];
            if (c != '%' || i + 1 >= format.length) { sb.append_c(c); continue; }
            char code = format[++i];
            char padc = '\0';
            if ((code == '-' || code == '_' || code == '0') && i + 1 < format.length) {
                padc = code;
                code = format[++i];
            }
            string val;
            char defpad = '0';
            switch (code) {
                case 'a': val = DAYS[wd].substring(0, 3); defpad = '\0'; break;
                case 'A': val = DAYS[wd]; defpad = '\0'; break;
                case 'b': val = MONTHS[mo - 1].substring(0, 3); defpad = '\0'; break;
                case 'B': val = MONTHS[mo - 1]; defpad = '\0'; break;
                case 'c': val = "%d/%d/%d, %d:%s:%s %s".printf(mo, d, y, h % 12 == 0 ? 12 : h % 12,
                                   pad(mi, 2), pad(s, 2), h < 12 ? "AM" : "PM"); defpad = '\0'; break;
                case 'd': val = pad(d, 2); break;
                case 'e': val = pad(d, 2); defpad = ' '; break;
                case 'f': val = pad(l * 1000, 6); break;
                case 'H': val = pad(h, 2); break;
                case 'I': val = pad(h % 12 == 0 ? 12 : h % 12, 2); break;
                case 'j': val = pad(doy, 3); break;
                case 'L': val = pad(l, 3); break;
                case 'm': val = pad(mo, 2); break;
                case 'M': val = pad(mi, 2); break;
                case 'p': val = h < 12 ? "AM" : "PM"; defpad = '\0'; break;
                case 'q': val = ((mo - 1) / 3 + 1).to_string(); defpad = '\0'; break;
                case 'Q': val = ms.to_string(); defpad = '\0'; break;
                case 's': val = (ms / 1000).to_string(); defpad = '\0'; break;
                case 'S': val = pad(s, 2); break;
                case 'u': val = (wd == 0 ? 7 : wd).to_string(); defpad = '\0'; break;
                case 'U': {
                    // Sunday-based week of year
                    int jan1_wd = (wd - (doy - 1) % 7 + 7) % 7;
                    val = pad((doy - 1 + jan1_wd) / 7, 2);
                    break;
                }
                case 'W': {
                    int mon_wd = (wd + 6) % 7;
                    int jan1 = (mon_wd - (doy - 1) % 7 + 7) % 7;
                    val = pad((doy - 1 + jan1) / 7, 2);
                    break;
                }
                case 'V': val = pad(dt.get_week_of_year(), 2); break;
                case 'G': val = pad(dt.get_week_numbering_year(), 4); break;
                case 'g': val = pad(dt.get_week_numbering_year() % 100, 2); break;
                case 'w': val = wd.to_string(); defpad = '\0'; break;
                case 'x': val = "%d/%d/%d".printf(mo, d, y); defpad = '\0'; break;
                case 'X': val = "%d:%s:%s %s".printf(h % 12 == 0 ? 12 : h % 12, pad(mi, 2), pad(s, 2),
                                  h < 12 ? "AM" : "PM"); defpad = '\0'; break;
                case 'y': val = pad(y % 100, 2); break;
                case 'Y': val = pad(y, 4); break;
                case 'Z': val = "+0000"; defpad = '\0'; break;
                case '%': val = "%"; defpad = '\0'; break;
                default:
                    sb.append_c('%');
                    sb.append_c(code);
                    continue;
            }
            // d3's pad modifiers: `-` none, `_` space, `0` zero. `_` was read
            // literally and never matched the ' ' test below, so `%_d` dropped
            // the padding entirely instead of space-padding.
            char use = padc == '_' ? ' ' : (padc != '\0' ? padc : defpad);
            if (defpad != '\0' && use != '0') {
                // Re-pad: strip leading zeros, then pad with the requested char
                int k = 0;
                while (k < val.length - 1 && val[k] == '0') k++;
                string core = val.substring(k);
                if (use == ' ') {
                    while (core.length < val.length) core = " " + core;
                }
                val = core;
            }
            sb.append(val);
        }
        return sb.str;
    }
}

}
