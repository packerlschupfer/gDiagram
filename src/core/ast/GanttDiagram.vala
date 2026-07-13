/* GanttDiagram.vala — AST for PlantUML Gantt charts (@startgantt) */
namespace GDiagram {

// Which point of another task a constraint refers to
public enum PumlGanttAnchor {
    NONE,       // no relative constraint
    START,      // [X]'s start
    END         // [X]'s end
}

public enum PumlGanttScale {
    DAILY,
    WEEKLY,
    MONTHLY,
    QUARTERLY,
    YEARLY
}

// A relative or absolute date constraint ("starts 2026-09-03", "starts 2 days after [X]'s end")
public class PumlGanttConstraint : Object {
    public int date { get; set; default = int.MIN; }   // absolute day number (int.MIN = unset)
    public string? ref_task { get; set; }              // referenced task key (name or alias)
    public PumlGanttAnchor anchor { get; set; default = PumlGanttAnchor.NONE; }
    public int offset { get; set; default = 0; }       // signed day offset (negative = before)
    public bool working_days { get; set; default = false; }
    public bool project_relative { get; set; default = false; }  // "D+N": project start + offset
    public string? link_color { get; set; }                     // "with blue dotted link", "-[#F0F]->"
    public string? link_style { get; set; }                     // dotted | dashed | bold

    public bool is_set() {
        return date != int.MIN || anchor != PumlGanttAnchor.NONE || project_relative;
    }
}

public class PumlGanttResource : Object {
    public string name { get; set; }
    public int percent { get; set; }

    public PumlGanttResource(string name, int percent) {
        this.name = name;
        this.percent = percent;
    }
}

public class PumlGanttTask : Object {
    public string name { get; set; }
    public string? alias_name { get; set; }       // [Task] as [T]
    public int duration_days { get; set; }        // computed calendar span in days (outline)
    public string? start_date { get; set; }       // raw start date text, if absolute
    public string? start_after_task { get; set; } // referenced task of the start constraint
    public bool start_at_start { get; set; }      // starts at [X]'s start
    public bool is_milestone { get; set; }
    public int completion_pct { get; set; }       // 0-100, -1 = not given
    public string? color { get; set; }            // bar fill
    public string? line_color { get; set; }       // bar border (second colour of "A/B")
    public string? section { get; set; }
    public int source_line { get; set; }
    public string? note { get; set; }             // note bottom ... end note

    // Constraints as written
    public double requires_days { get; set; default = -1; }  // lasts/requires (working days)
    public PumlGanttConstraint start { get; set; }
    public PumlGanttConstraint end { get; set; }
    public Gee.ArrayList<PumlGanttResource> resources { get; private set; }

    // Schedule (filled by GanttScheduler) — day numbers count from 1970-01-01
    public int start_day { get; set; }
    public double end_instant { get; set; }       // exclusive end in (fractional) days
    public int last_day { get; set; }             // last calendar day the bar touches

    public PumlGanttTask(string name, int line = 0) {
        this.name = name;
        this.duration_days = 1;
        this.is_milestone = false;
        this.completion_pct = -1;
        this.start_at_start = false;
        this.source_line = line;
        this.start = new PumlGanttConstraint();
        this.end = new PumlGanttConstraint();
        this.resources = new Gee.ArrayList<PumlGanttResource>();
    }
}

// A dependency drawn as an arrow: from task's end (or start) to the dependent task
public class PumlGanttLink : Object {
    public PumlGanttTask from { get; set; }
    public PumlGanttTask to { get; set; }
    public PumlGanttAnchor from_anchor { get; set; }   // END or START of `from`
    public bool to_end { get; set; }                   // constraint on `to`'s end (ends at)
    public string? color { get; set; }
    public string? style { get; set; }                 // dotted | dashed | bold

    public PumlGanttLink(PumlGanttTask from, PumlGanttTask to, PumlGanttAnchor from_anchor, bool to_end) {
        this.from = from;
        this.to = to;
        this.from_anchor = from_anchor;
        this.to_end = to_end;
    }
}

// One chart row: a task/milestone, or a "-- separator --"
public class PumlGanttRow : Object {
    public PumlGanttTask? task { get; set; }
    public string? separator { get; set; }

    public PumlGanttRow.for_task(PumlGanttTask task) {
        this.task = task;
    }

    public PumlGanttRow.for_separator(string text) {
        this.separator = text;
    }
}

public class PumlGanttDayColor : Object {
    public int from_day { get; set; }
    public int to_day { get; set; }
    public string color { get; set; }

    public PumlGanttDayColor(int from_day, int to_day, string color) {
        this.from_day = from_day;
        this.to_day = to_day;
        this.color = color;
    }
}

public class PumlGanttDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public string? header { get; set; }
    public string? footer { get; set; }
    public string? caption { get; set; }
    public string? legend { get; set; }
    public string? project_start { get; set; }          // raw text
    public int project_start_day { get; set; default = int.MIN; }
    public Gee.ArrayList<PumlGanttTask> tasks { get; private set; }
    public Gee.ArrayList<PumlGanttRow> rows { get; private set; }
    public Gee.ArrayList<PumlGanttLink> links { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    // Calendar
    public bool[] closed_weekdays;                      // index 0 = Monday
    public Gee.HashSet<int> closed_days { get; private set; }
    public Gee.HashSet<int> open_days { get; private set; }
    public Gee.ArrayList<PumlGanttDayColor> day_colors { get; private set; }
    public int today_day { get; set; default = int.MIN; }
    public string? today_color { get; set; }
    public int print_from { get; set; default = int.MIN; }
    public int print_to { get; set; default = int.MIN; }

    // Presentation
    public PumlGanttScale scale { get; set; default = PumlGanttScale.DAILY; }
    public double zoom { get; set; default = 1.0; }
    public string language { get; set; default = "en"; }
    public bool hide_resource_names { get; set; }
    public bool hide_resource_footbox { get; set; }
    public bool hide_footbox { get; set; }

    public PumlGanttDiagram() {
        this.diagram_type = DiagramType.GANTT;
        this.tasks = new Gee.ArrayList<PumlGanttTask>();
        this.rows = new Gee.ArrayList<PumlGanttRow>();
        this.links = new Gee.ArrayList<PumlGanttLink>();
        this.errors = new Gee.ArrayList<ParseError>();
        this.closed_weekdays = new bool[7];
        this.closed_days = new Gee.HashSet<int>();
        this.open_days = new Gee.HashSet<int>();
        this.day_colors = new Gee.ArrayList<PumlGanttDayColor>();
    }

    public void add_task(PumlGanttTask task) {
        tasks.add(task);
        rows.add(new PumlGanttRow.for_task(task));
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return tasks.size == 0; }

    // True when the chart is laid on real dates ("Project starts ...")
    public bool is_dated() { return project_start_day != int.MIN; }

    // 1970-01-01 was a Thursday; 0 = Monday
    public static int weekday_of(int day) {
        int w = (day + 3) % 7;
        return w < 0 ? w + 7 : w;
    }

    public bool is_closed(int day) {
        if (open_days.contains(day)) return false;
        if (closed_days.contains(day)) return true;
        // Every weekday closed would leave no day to work on: ignore the weekday rules
        return closed_weekdays[weekday_of(day)] && !all_closed();
    }

    // True when every weekday is closed — scheduling would never terminate
    public bool all_closed() {
        foreach (bool c in closed_weekdays) {
            if (!c) return false;
        }
        return true;
    }
}

}
