/* GanttDiagramParser.vala — line-based parser for PlantUML @startgantt.
 *
 * Syntax follows https://plantuml.com/gantt-diagram (checked against 1.2026.8):
 * tasks with lasts/requires/starts/ends, relative constraints, "->" and "then"
 * dependencies, aliases, completion, colours, resources, milestones, separators,
 * notes, closed/open/coloured days, today, printscale/zoom, language, hide options
 * and title/header/footer/caption/legend. Scheduling is done by GanttScheduler.
 */
namespace GDiagram {

public class GanttDiagramParser : Object {
    private PumlGanttDiagram diagram;
    private string? current_section;
    private PumlGanttTask? last_task;
    private int current_line;

    private Regex re_task_head;
    private Regex re_arrow_chain;
    private Regex re_ref_point;
    private Regex re_offset_point;
    private Regex re_duration_part;
    private Regex re_resource;
    private Regex re_date_line;
    private Regex re_weekday_line;
    private Regex re_today;
    private Regex re_scale;
    private Regex re_complete;
    private Regex re_with_link;

    private const string DATE = "(\\d{4}[-/]\\d{1,2}[-/]\\d{1,2})";
    private const string[] WEEKDAYS = {
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    };

    public GanttDiagramParser() {
        try {
            var ci = RegexCompileFlags.CASELESS;
            re_task_head = new Regex("^\\[([^\\]]+)\\](?:\\s+as\\s+\\[([^\\]]+)\\])?\\s*(.*)$", ci);
            re_arrow_chain = new Regex("^\\[[^\\]]+\\](\\s*-(?:\\[[^\\]]*\\]-)?>\\s*\\[[^\\]]+\\])+\\s*$", ci);
            re_ref_point = new Regex("^at\\s+\\[([^\\]]+)\\]'s\\s+(start|end)$", ci);
            re_offset_point = new Regex(
                "^(\\d+)\\s+(working\\s+)?days?\\s+(after|before)\\s+\\[([^\\]]+)\\]'s\\s+(start|end)$", ci);
            re_duration_part = new Regex("(\\d+(?:\\.\\d+)?)\\s*(days?|weeks?|months?)", ci);
            re_resource = new Regex("\\{([^}:]+)(?::\\s*(\\d+)%)?\\}", ci);
            re_date_line = new Regex("^" + DATE + "(?:\\s+to\\s+" + DATE + ")?\\s+(?:is|are)\\s+(.+)$", ci);
            re_weekday_line = new Regex(
                "^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\\s+(?:is|are)\\s+(closed|open)$", ci);
            re_today = new Regex("^today\\s+is\\s+(.+?)(?:\\s+and\\s+is\\s+colou?red\\s+in\\s+(\\S+))?$", ci);
            re_scale = new Regex(
                "^(?:printscale|projectscale|ganttscale)\\s+(daily|weekly|monthly|quarterly|yearly)" +
                "(?:\\s+zoom\\s+(\\d+(?:\\.\\d+)?))?\\s*$", ci);
            re_complete = new Regex("^is\\s+(?:(\\d+)\\s*%\\s+)?complete(?:d)?$", ci);
            re_with_link = new Regex("\\s+with\\s+([^\\[\\]]*)\\blink$", ci);
        } catch (RegexError e) {
            error("gantt parser regex: %s", e.message);
        }
    }

    public PumlGanttDiagram parse(string source) {
        this.diagram = new PumlGanttDiagram();
        current_section = null;
        last_task = null;

        parse_gantt(source);
        finish();

        return diagram;
    }

    private void parse_gantt(string source) {
        string[] lines = source.split("\n");
        // Main-file line numbers: included text reports its !include line
        int[] line_nos = Preprocessor.source_line_numbers(lines);

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            current_line = line_nos[i];
            if (trimmed.length == 0) continue;
            string lower = trimmed.ascii_down();

            // Comments
            if (trimmed.has_prefix("/'")) {
                while (i < lines.length && !lines[i].strip().has_suffix("'/")) i++;
                continue;
            }
            if (trimmed.has_prefix("'")) continue;

            if (lower.has_prefix("@startgantt") || lower.has_prefix("@endgantt") ||
                lower.has_prefix("@startuml") || lower.has_prefix("@enduml")) continue;

            // Blocks
            if (lower.has_prefix("<style>")) {
                while (i < lines.length && !lines[i].ascii_down().contains("</style>")) i++;
                continue;
            }
            if (lower == "legend" || lower.has_prefix("legend ")) {
                var sb = new StringBuilder();
                i++;
                while (i < lines.length) {
                    string l = lines[i].strip();
                    string ll = l.ascii_down();
                    if (ll == "endlegend" || ll == "end legend") break;
                    if (sb.len > 0) sb.append_c('\n');
                    sb.append(l);
                    i++;
                }
                diagram.legend = sb.str;
                continue;
            }
            if (lower == "note bottom" || lower == "note top" || lower == "note") {
                var sb = new StringBuilder();
                i++;
                while (i < lines.length) {
                    string l = lines[i].strip();
                    string ll = l.ascii_down();
                    if (ll == "endnote" || ll == "end note") break;
                    if (sb.len > 0) sb.append_c('\n');
                    sb.append(l);
                    i++;
                }
                if (last_task != null) last_task.note = sb.str;
                continue;
            }

            if (lower.has_prefix("scale ") || lower.has_prefix("skinparam ") || lower.has_prefix("!")) continue;

            if (parse_document_line(trimmed, lower)) continue;

            // Separator: -- Name --
            if (trimmed.has_prefix("--") && trimmed.has_suffix("--") && trimmed.length >= 4) {
                string text = trimmed.substring(2, trimmed.length - 4).strip();
                current_section = text;
                diagram.rows.add(new PumlGanttRow.for_separator(text));
                continue;
            }

            if (parse_calendar_line(trimmed, lower)) continue;

            // then [Next] lasts ...
            if (lower.has_prefix("then ")) {
                var prev = last_task;
                string rest = trimmed.substring(5).strip();
                var t = parse_task_statement(rest);
                if (t != null && prev != null && t != prev) {
                    t.start.ref_task = key_of(prev);
                    t.start.anchor = PumlGanttAnchor.END;
                    t.start_after_task = prev.name;
                }
                continue;
            }

            if (trimmed.has_prefix("[")) {
                MatchInfo m;
                if (re_arrow_chain.match(trimmed, 0, out m)) {
                    parse_arrow_chain(trimmed);
                } else {
                    parse_task_statement(trimmed);
                }
                continue;
            }
        }
    }

    // title / header / footer / caption / language / hide / printscale
    private bool parse_document_line(string line, string lower) {
        string[] prefixes = { "title ", "header ", "footer ", "caption ",
                              "center header ", "left header ", "right header ",
                              "center footer ", "left footer ", "right footer " };
        foreach (string p in prefixes) {
            if (lower.has_prefix(p)) {
                string value = line.substring(p.length).strip();
                if (p.has_suffix("title ")) diagram.title = value;
                else if (p.has_suffix("header ")) diagram.header = value;
                else if (p.has_suffix("footer ")) diagram.footer = value;
                else diagram.caption = value;
                return true;
            }
        }
        if (lower.has_prefix("language ")) {
            diagram.language = lower.substring(9).strip();
            return true;
        }
        if (lower.has_prefix("hide ")) {
            string what = lower.substring(5).strip();
            if (what.has_suffix("names")) diagram.hide_resource_names = true;
            else if (what.has_prefix("ressources footbox") || what.has_prefix("resources footbox"))
                diagram.hide_resource_footbox = true;
            else if (what == "footbox") diagram.hide_footbox = true;
            return true;
        }
        MatchInfo m;
        if (re_scale.match(line, 0, out m)) {
            switch (m.fetch(1).ascii_down()) {
                case "weekly":    diagram.scale = PumlGanttScale.WEEKLY; break;
                case "monthly":   diagram.scale = PumlGanttScale.MONTHLY; break;
                case "quarterly": diagram.scale = PumlGanttScale.QUARTERLY; break;
                case "yearly":    diagram.scale = PumlGanttScale.YEARLY; break;
                default:          diagram.scale = PumlGanttScale.DAILY; break;
            }
            string? z = m.fetch(2);
            if (z != null && z.length > 0) {
                double zoom = double.parse(z);
                if (zoom > 0) diagram.zoom = zoom;
            }
            return true;
        }
        return false;
    }

    // Project start, closed/open/coloured days, today, print range
    private bool parse_calendar_line(string line, string lower) {
        MatchInfo m;
        if (lower.has_prefix("project starts ")) {
            diagram.project_start = line.substring(15).strip();
            int day = GanttScheduler.parse_date(diagram.project_start);
            if (day != int.MIN) diagram.project_start_day = day;
            return true;
        }
        if (re_weekday_line.match(line, 0, out m)) {
            string wd = m.fetch(1).ascii_down();
            for (int i = 0; i < 7; i++) {
                if (WEEKDAYS[i] == wd) diagram.closed_weekdays[i] = m.fetch(2).ascii_down() == "closed";
            }
            return true;
        }
        if (re_date_line.match(line, 0, out m)) {
            int from = GanttScheduler.parse_date(m.fetch(1));
            string? to_text = m.fetch(2);
            int to = (to_text != null && to_text.length > 0) ? GanttScheduler.parse_date(to_text) : from;
            string what = m.fetch(3).strip();
            string what_lower = what.ascii_down();
            if (from == int.MIN || to == int.MIN || to < from || to - from > 36600) return true;
            if (what_lower == "closed" || what_lower == "open") {
                bool closed = what_lower == "closed";
                for (int d = from; d <= to; d++) {
                    if (closed) {
                        diagram.closed_days.add(d);
                        diagram.open_days.remove(d);
                    } else {
                        diagram.open_days.add(d);
                        diagram.closed_days.remove(d);
                    }
                }
            } else if (what_lower.has_prefix("colored in ") || what_lower.has_prefix("coloured in ")) {
                string color = what.substring(what.index_of(" in ") + 4).strip();
                diagram.day_colors.add(new PumlGanttDayColor(from, to, color));
            } else if (what_lower.has_prefix("named ")) {
                // "2026-09-01 to 2026-09-05 are named [Sprint]" — accepted, not drawn
            }
            return true;
        }
        if (lower.has_prefix("today is colored in ") || lower.has_prefix("today is coloured in ")) {
            diagram.today_color = line.substring(20).strip();
            return true;
        }
        if (re_today.match(line, 0, out m)) {
            string spec = m.fetch(1).strip();
            string? color = m.fetch(2);
            int day = GanttScheduler.parse_date(spec);
            if (day == int.MIN) {
                try {
                    var after = new Regex("^(\\d+)\\s+days?\\s+after\\s+start$", RegexCompileFlags.CASELESS);
                    MatchInfo am;
                    if (after.match(spec, 0, out am)) {
                        day = (diagram.is_dated() ? diagram.project_start_day : 0) + int.parse(am.fetch(1));
                    }
                } catch (RegexError e) {}
            }
            if (day != int.MIN) diagram.today_day = day;
            if (color != null && color.length > 0) diagram.today_color = color;
            return true;
        }
        if (lower.has_prefix("print between ")) {
            try {
                var re = new Regex("^print\\s+between\\s+" + DATE + "\\s+and\\s+" + DATE + "$",
                                   RegexCompileFlags.CASELESS);
                if (re.match(line, 0, out m)) {
                    diagram.print_from = GanttScheduler.parse_date(m.fetch(1));
                    diagram.print_to = GanttScheduler.parse_date(m.fetch(2));
                }
            } catch (RegexError e) {}
            return true;
        }
        // Accepted, not drawn
        if (lower.has_prefix("separator just") || lower.has_prefix("label on ") ||
            lower.has_prefix("weeks starts") || lower.has_prefix("with week numbering") ||
            lower.has_prefix("with calendar date") || lower.has_prefix("{")) {
            return true;
        }
        return false;
    }

    // [A] -> [B] -> [C]
    private void parse_arrow_chain(string line) {
        PumlGanttTask? prev = null;
        string? spec = null;
        int pos = 0;
        while (true) {
            int ob = line.index_of("[", pos);
            if (ob < 0) break;
            // "-[#color,dotted]->" styles the next arrow
            if (ob > 0 && line[ob - 1] == '-') {
                int skip = line.index_of("]", ob);
                if (skip < 0) break;
                spec = line.substring(ob + 1, skip - ob - 1);
                pos = skip + 1;
                continue;
            }
            int cb = line.index_of("]", ob);
            if (cb < 0) break;
            string name = line.substring(ob + 1, cb - ob - 1).strip();
            var t = find_or_create_task(name);
            if (prev != null && t != prev) {
                t.start.date = int.MIN;
                t.start.project_relative = false;
                t.start.ref_task = key_of(prev);
                t.start.anchor = PumlGanttAnchor.END;
                t.start.offset = 0;
                t.start.working_days = false;
                t.start_after_task = prev.name;
                t.start_at_start = false;
                t.start.link_color = null;
                t.start.link_style = null;
                if (spec != null) apply_link_spec(t.start, spec);
            }
            spec = null;
            prev = t;
            pos = cb + 1;
        }
        if (prev != null) last_task = prev;
    }

    // [Task] (as [Alias])? (on {res})? clause (and clause)*
    private PumlGanttTask? parse_task_statement(string line) {
        MatchInfo m;
        if (!re_task_head.match(line, 0, out m)) return null;
        string name = m.fetch(1).strip();
        string? alias = m.fetch(2);
        string rest = m.fetch(3).strip();

        var task = find_or_create_task(name);
        if (alias != null && alias.length > 0) {
            // "[Same name] as [T2]" declares a second task when the alias is new
            if (task.alias_name != null && task.alias_name != alias.strip()) {
                task = new PumlGanttTask(name, current_line);
                task.section = current_section;
                diagram.add_task(task);
            }
            task.alias_name = alias.strip();
        }
        last_task = task;

        foreach (string clause in split_clauses(rest)) {
            parse_clause(task, clause);
        }
        return task;
    }

    // Split on " and " outside brackets; "1 week and 4 days" stays one duration clause
    private Gee.ArrayList<string> split_clauses(string text) {
        var parts = new Gee.ArrayList<string>();
        var sb = new StringBuilder();
        int depth = 0;
        string lower = text.ascii_down();
        int i = 0;
        while (i < text.length) {
            char c = text[i];
            if (c == '[' || c == '{') depth++;
            else if ((c == ']' || c == '}') && depth > 0) depth--;
            if (depth == 0 && lower.substring(i).has_prefix(" and ")) {
                parts.add(sb.str.strip());
                sb.truncate();
                i += 5;
                continue;
            }
            sb.append_c(c);
            i++;
        }
        if (sb.str.strip().length > 0) parts.add(sb.str.strip());

        var merged = new Gee.ArrayList<string>();
        try {
            var dur_only = new Regex("^\\d+(?:\\.\\d+)?\\s*(days?|weeks?|months?)$", RegexCompileFlags.CASELESS);
            foreach (string p in parts) {
                if (merged.size > 0 && dur_only.match(p)) {
                    merged[merged.size - 1] = merged[merged.size - 1] + " and " + p;
                } else if (p.length > 0) {
                    merged.add(p);
                }
            }
        } catch (RegexError e) {
            return parts;
        }
        return merged;
    }

    private void parse_clause(PumlGanttTask task, string raw_clause) {
        string clause = raw_clause.strip();
        MatchInfo m;
        // "... with blue dotted link" styles the dependency arrow only
        string? link_spec = null;
        if (re_with_link.match(clause, 0, out m)) {
            link_spec = m.fetch(1);
            clause = clause.substring(0, clause.length - m.fetch(0).length).strip();
        }
        string lower = clause.ascii_down();
        if (clause.length == 0) return;

        // on {Alice:50%} {Bob} (optionally followed by another clause)
        if (lower.has_prefix("on ") && clause.index_of("{") >= 0) {
            int last_close = clause.last_index_of("}");
            string res = clause.substring(0, last_close + 1);
            if (re_resource.match(res, 0, out m)) {
                do {
                    string rname = m.fetch(1).strip();
                    string? pct = m.fetch(2);
                    int p = (pct != null && pct.length > 0) ? int.parse(pct) : 100;
                    task.resources.add(new PumlGanttResource(rname, p));
                } while (next_match(m));
            }
            string remainder = clause.substring(last_close + 1).strip();
            if (remainder.length > 0) parse_clause(task, remainder);
            return;
        }

        if (lower.has_prefix("lasts ") || lower.has_prefix("requires ")) {
            double total = 0;
            bool any = false;
            if (re_duration_part.match(clause, 0, out m)) {
                do {
                    double n = double.parse(m.fetch(1));
                    string unit = m.fetch(2).ascii_down();
                    if (unit.has_prefix("week")) n *= 7;
                    else if (unit.has_prefix("month")) n *= 30;
                    total += n;
                    any = true;
                } while (next_match(m));
            }
            if (any) task.requires_days = total;
            return;
        }

        if (lower.has_prefix("starts ")) {
            string spec = clause.substring(7).strip();
            parse_point(spec, task.start);
            if (link_spec != null) apply_link_spec(task.start, link_spec.replace(" ", ","));
            if (task.start.anchor != PumlGanttAnchor.NONE) {
                var other = find_task(task.start.ref_task);
                task.start_after_task = other != null ? other.name : task.start.ref_task;
                task.start_at_start = task.start.anchor == PumlGanttAnchor.START;
            } else {
                task.start_date = spec;
            }
            return;
        }
        if (lower.has_prefix("ends ")) {
            parse_point(clause.substring(5).strip(), task.end);
            if (link_spec != null) apply_link_spec(task.end, link_spec.replace(" ", ","));
            return;
        }
        if (lower.has_prefix("happens ")) {
            task.is_milestone = true;
            parse_point(clause.substring(8).strip(), task.start);
            return;
        }
        if (lower.has_prefix("occurs from ")) {
            try {
                var re = new Regex("^occurs\\s+from\\s+\\[([^\\]]+)\\]\\s+to\\s+\\[([^\\]]+)\\]$",
                                   RegexCompileFlags.CASELESS);
                if (re.match(clause, 0, out m)) {
                    task.start.ref_task = m.fetch(1).strip();
                    task.start.anchor = PumlGanttAnchor.START;
                    task.end.ref_task = m.fetch(2).strip();
                    task.end.anchor = PumlGanttAnchor.END;
                }
            } catch (RegexError e) {}
            return;
        }

        if (re_complete.match(clause, 0, out m)) {
            string? pct = m.fetch(1);
            task.completion_pct = (pct != null && pct.length > 0) ? int.parse(pct).clamp(0, 100) : 100;
            return;
        }
        if (lower.has_prefix("is colored in ") || lower.has_prefix("is coloured in ")) {
            string colors = clause.substring(14).strip();
            string[] parts = colors.split("/");
            task.color = parts[0].strip();
            if (parts.length > 1 && parts[1].strip().length > 0) task.line_color = parts[1].strip();
            return;
        }
        // is deleted (PlantUML 1.2026.8 still draws the task) / displays on same row as /
        // pauses on / links to — accepted, not drawn
    }

    // "2026-09-03", "D+3", "at [X]'s end", "2 working days after [X]'s end"
    private void parse_point(string spec, PumlGanttConstraint c) {
        MatchInfo m;
        string s = spec.strip();
        if (re_ref_point.match(s, 0, out m)) {
            c.date = int.MIN;
            c.project_relative = false;
            c.ref_task = m.fetch(1).strip();
            c.anchor = m.fetch(2).ascii_down() == "start" ? PumlGanttAnchor.START : PumlGanttAnchor.END;
            c.offset = 0;
            c.working_days = false;
            find_or_create_task(c.ref_task);
            return;
        }
        if (re_offset_point.match(s, 0, out m)) {
            int n = int.parse(m.fetch(1));
            c.date = int.MIN;
            c.project_relative = false;
            c.working_days = m.fetch(2) != null && m.fetch(2).length > 0;
            c.offset = m.fetch(3).ascii_down() == "before" ? -n : n;
            c.ref_task = m.fetch(4).strip();
            c.anchor = m.fetch(5).ascii_down() == "start" ? PumlGanttAnchor.START : PumlGanttAnchor.END;
            find_or_create_task(c.ref_task);
            return;
        }
        string lower = s.ascii_down();
        if (lower.has_prefix("d+")) {
            c.anchor = PumlGanttAnchor.NONE;
            c.date = int.MIN;
            c.project_relative = true;
            c.offset = int.parse(s.substring(2).strip());
            return;
        }
        int day = GanttScheduler.parse_date(s);
        if (day != int.MIN) {
            c.anchor = PumlGanttAnchor.NONE;
            c.project_relative = false;
            c.date = day;
            c.offset = 0;
        }
    }

    // "#FF00FF,dotted", "blue,dotted", "green,bold"
    private static void apply_link_spec(PumlGanttConstraint c, string spec) {
        foreach (string raw in spec.split(",")) {
            string part = raw.strip();
            string lower = part.ascii_down();
            if (part.length == 0) continue;
            if (lower == "dotted" || lower == "dashed" || lower == "bold") {
                c.link_style = lower;
            } else if (lower != "plain" && lower != "link") {
                c.link_color = part;
            }
        }
    }

    private static bool next_match(MatchInfo m) {
        try {
            return m.next();
        } catch (RegexError e) {
            return false;
        }
    }

    // Name or alias of a task as other statements refer to it
    private string key_of(PumlGanttTask t) {
        return t.alias_name ?? t.name;
    }

    private PumlGanttTask? find_task(string? key) {
        if (key == null) return null;
        foreach (var t in diagram.tasks) {
            if (t.alias_name == key) return t;
        }
        foreach (var t in diagram.tasks) {
            if (t.name == key) return t;
        }
        return null;
    }

    private PumlGanttTask find_or_create_task(string name) {
        var existing = find_task(name);
        if (existing != null) return existing;
        var task = new PumlGanttTask(name, current_line);
        task.section = current_section;
        diagram.add_task(task);
        return task;
    }

    private void finish() {
        // Absolute dates without "Project starts": PlantUML refuses the diagram;
        // start the calendar at the earliest date instead.
        if (!diagram.is_dated()) {
            int earliest = int.MAX;
            foreach (var t in diagram.tasks) {
                if (t.start.date != int.MIN && t.start.date < earliest) earliest = t.start.date;
                if (t.end.date != int.MIN && t.end.date < earliest) earliest = t.end.date;
            }
            if (earliest != int.MAX) diagram.project_start_day = earliest;
        }
        new GanttScheduler().schedule(diagram);
    }
}

}
