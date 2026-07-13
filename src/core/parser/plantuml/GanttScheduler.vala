/* GanttScheduler.vala — calendar arithmetic and task scheduling for PlantUML gantt charts.
 *
 * Days are integers counting from 1970-01-01 (a Thursday). An undated chart
 * ("Day 1", "Day 2", ...) starts at day 0, which is why PlantUML's
 * "saturday are closed" closes Day 3 and Day 4 of an undated chart.
 *
 * Rules follow PlantUML 1.2026.8 renders:
 *  - a task lasts N working days: closed days inside it do not count
 *  - a task starting on a closed day moves to the next open day
 *  - "starts at [X]'s end" = the day after X's last day;
 *    "starts N days after [X]'s end" adds N calendar days to that,
 *    "N working days after" steps over N open days
 *  - a milestone "happens at [X]'s end" on X's last day (N days after: last day + N)
 *  - resources load a task: "on {A:50%} {B}" makes 2 days last 2 / 1.5 days
 */
namespace GDiagram {

public class GanttScheduler : Object {
    private const int MAX_STEPS = 36600;

    private PumlGanttDiagram diagram;
    private Gee.HashMap<PumlGanttTask, int> state;
    private int base_day;

    // ---- date helpers ----

    public static int day_from_ymd(int year, int month, int day) {
        if (month < 1 || month > 12 || day < 1 || year < 1) return int.MIN;
        var date = Date();
        date.clear();
        date.set_dmy((DateDay) day, month, (DateYear) year);
        if (!date.valid()) return int.MIN;
        var epoch = Date();
        epoch.clear();
        epoch.set_dmy(1, 1, 1970);
        return (int) date.get_julian() - (int) epoch.get_julian();
    }

    public static void ymd_from_day(int day, out int year, out int month, out int dom) {
        var epoch = Date();
        epoch.clear();
        epoch.set_dmy(1, 1, 1970);
        var date = Date();
        date.clear();
        date.set_julian(epoch.get_julian() + day);
        year = date.get_year();
        month = (int) date.get_month();
        dom = date.get_day();
    }

    public static int iso_week(int day) {
        var epoch = Date();
        epoch.clear();
        epoch.set_dmy(1, 1, 1970);
        var date = Date();
        date.clear();
        date.set_julian(epoch.get_julian() + day);
        return (int) date.get_iso8601_week_of_year();
    }

    private const string[] MONTHS = {
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december"
    };

    /**
     * Parse "2026-09-03", "2026/09/03" or "the 20th of september 2017".
     * Returns int.MIN when the text is not a date.
     */
    public static int parse_date(string text) {
        string t = text.strip().down();
        try {
            var iso = new Regex("^(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})$");
            MatchInfo m;
            if (iso.match(t, 0, out m)) {
                return day_from_ymd(int.parse(m.fetch(1)), int.parse(m.fetch(2)), int.parse(m.fetch(3)));
            }
            var words = new Regex("^(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?([a-z]+)\\s+(\\d{4})$");
            if (words.match(t, 0, out m)) {
                string month = m.fetch(2);
                for (int i = 0; i < 12; i++) {
                    if (MONTHS[i] == month || (month.length >= 3 && MONTHS[i].has_prefix(month))) {
                        return day_from_ymd(int.parse(m.fetch(3)), i + 1, int.parse(m.fetch(1)));
                    }
                }
            }
        } catch (RegexError e) {
            warning("gantt date regex: %s", e.message);
        }
        return int.MIN;
    }

    // ---- calendar arithmetic (public for tests) ----

    // First open day at or after `day`
    public static int snap_open(PumlGanttDiagram d, int day) {
        int n = 0;
        while (d.is_closed(day) && n++ < MAX_STEPS) day++;
        return day;
    }

    /**
     * Exclusive end of a task starting on open day `start` that needs `days`
     * working days (fractional for loaded resources).
     */
    public static double end_after_working_days(PumlGanttDiagram d, int start, double days) {
        double remaining = days;
        int day = start;
        int n = 0;
        while (remaining > 1e-9 && n++ < MAX_STEPS) {
            if (d.is_closed(day)) {
                day++;
                continue;
            }
            if (remaining >= 1.0 - 1e-9) {
                remaining -= 1.0;
                day++;
            } else {
                return day + remaining;
            }
        }
        return day;
    }

    // First day of a task that ends on `last` and needs `days` working days
    public static int start_before_working_days(PumlGanttDiagram d, int last, double days) {
        int count = (int) Math.ceil(days - 1e-9);
        int day = last;
        int n = 0;
        while (n++ < MAX_STEPS) {
            if (!d.is_closed(day)) {
                count--;
                if (count <= 0) break;
            }
            day--;
        }
        return day;
    }

    // Move `steps` open days forward (or backward when negative) from `day`
    public static int step_working_days(PumlGanttDiagram d, int day, int steps) {
        int dir = steps < 0 ? -1 : 1;
        int left = steps.abs();
        int n = 0;
        while (left > 0 && n++ < MAX_STEPS) {
            day += dir;
            if (!d.is_closed(day)) left--;
        }
        return day;
    }

    // ---- scheduling ----

    public void schedule(PumlGanttDiagram d) {
        diagram = d;
        state = new Gee.HashMap<PumlGanttTask, int>();
        base_day = d.is_dated() ? d.project_start_day : 0;
        foreach (var t in d.tasks) {
            resolve(t);
        }
        d.links.clear();
        foreach (var t in d.tasks) {
            if (t.is_milestone) continue;
            if (t.start.anchor != PumlGanttAnchor.NONE) {
                var from = find(t.start.ref_task);
                if (from != null && from != t) {
                    var link = new PumlGanttLink(from, t, t.start.anchor, false);
                    link.color = t.start.link_color;
                    link.style = t.start.link_style;
                    d.links.add(link);
                }
            }
            if (t.end.anchor != PumlGanttAnchor.NONE) {
                var from = find(t.end.ref_task);
                if (from != null && from != t) {
                    var link = new PumlGanttLink(from, t, t.end.anchor, true);
                    link.color = t.end.link_color;
                    link.style = t.end.link_style;
                    d.links.add(link);
                }
            }
        }
    }

    public PumlGanttTask? find(string? key) {
        if (key == null) return null;
        foreach (var t in diagram.tasks) {
            if (t.alias_name == key) return t;
        }
        foreach (var t in diagram.tasks) {
            if (t.name == key) return t;
        }
        return null;
    }

    private void resolve(PumlGanttTask t) {
        int s = state.has_key(t) ? state[t] : 0;
        if (s != 0) return;   // done, or a cycle (keeps whatever is set)
        state[t] = 1;
        t.start_day = base_day;
        t.end_instant = base_day + 1;
        t.last_day = base_day;

        if (t.is_milestone) {
            int day = t.start.is_set() ? milestone_day(t.start) : base_day;
            t.start_day = day;
            t.last_day = day;
            t.end_instant = day + 1;
            t.duration_days = 1;
            state[t] = 2;
            return;
        }

        double work = t.requires_days;
        double load = 0;
        foreach (var r in t.resources) load += r.percent / 100.0;
        double effective = work >= 0 ? (load > 0 ? work / load : work) : -1;

        if (t.start.is_set()) {
            int start = snap_open(diagram, start_point(t.start));
            t.start_day = start;
            if (effective >= 0) {
                t.end_instant = end_after_working_days(diagram, start, effective);
            } else if (t.end.is_set()) {
                t.end_instant = end_point(t.end) + 1;
            } else {
                t.end_instant = end_after_working_days(diagram, start, 1);
            }
        } else if (t.end.is_set()) {
            int last = end_point(t.end);
            if (effective >= 0) {
                t.start_day = start_before_working_days(diagram, last, effective);
            } else {
                t.start_day = snap_open(diagram, base_day);
            }
            t.end_instant = last + 1;
        } else {
            int start = snap_open(diagram, base_day);
            t.start_day = start;
            t.end_instant = end_after_working_days(diagram, start, effective >= 0 ? effective : 1);
        }
        if (t.end_instant < t.start_day + 1e-9) t.end_instant = t.start_day + 1;
        t.last_day = (int) Math.ceil(t.end_instant - 1e-9) - 1;
        if (t.last_day < t.start_day) t.last_day = t.start_day;
        t.duration_days = t.last_day - t.start_day + 1;
        state[t] = 2;
    }

    // The referenced task, scheduled; null when unknown or part of a cycle
    private PumlGanttTask? ref_task(PumlGanttConstraint c) {
        var other = find(c.ref_task);
        if (other == null) return null;
        resolve(other);
        if (state[other] != 2) return null;
        return other;
    }

    private int start_point(PumlGanttConstraint c) {
        if (c.project_relative) return base_day + c.offset;
        if (c.date != int.MIN) return c.date + c.offset;
        var other = ref_task(c);
        if (other == null) return base_day;
        int t;
        if (c.anchor == PumlGanttAnchor.START) {
            t = other.start_day;
        } else if (other.is_milestone) {
            t = other.start_day;
        } else {
            t = (int) Math.ceil(other.end_instant - 1e-9);
        }
        if (c.working_days) return step_working_days(diagram, t, c.offset);
        return t + c.offset;
    }

    private int end_point(PumlGanttConstraint c) {
        if (c.project_relative) return base_day + c.offset;
        if (c.date != int.MIN) return c.date + c.offset;
        var other = ref_task(c);
        if (other == null) return base_day;
        int t = c.anchor == PumlGanttAnchor.START ? other.start_day : other.last_day;
        if (c.working_days) return step_working_days(diagram, t, c.offset);
        return t + c.offset;
    }

    private int milestone_day(PumlGanttConstraint c) {
        if (c.project_relative) return base_day + c.offset;
        if (c.date != int.MIN) return c.date + c.offset;
        var other = ref_task(c);
        if (other == null) return base_day;
        int t = c.anchor == PumlGanttAnchor.START ? other.start_day : other.last_day;
        if (c.working_days) return step_working_days(diagram, t, c.offset);
        return t + c.offset;
    }
}

}
