namespace GDiagram {

    // ==================== MERMAID GANTT CHART ====================

    // The most significant tag of a task (kept for linters/outline); the
    // individual flags on GanttTask carry combinations such as "crit, active".
    public enum GanttTaskStatus {
        ACTIVE,
        DONE,
        CRITICAL,
        MILESTONE,
        NONE
    }

    public class GanttTask : Object {
        public string id { get; set; }
        public string description { get; set; }
        public GanttTaskStatus status { get; set; }
        public string? start_date { get; set; }
        public string? end_date { get; set; }
        public string? duration { get; set; }
        public string? depends_on { get; set; }
        public int source_line { get; set; }

        // Tags as Mermaid keeps them (any combination)
        public bool is_active { get; set; default = false; }
        public bool is_done { get; set; default = false; }
        public bool is_crit { get; set; default = false; }
        public bool is_milestone { get; set; default = false; }
        public bool is_vert { get; set; default = false; }

        // Section name ("" before the first section) and row order
        public string section_name { get; set; default = ""; }
        public int order { get; set; default = 0; }

        // Raw task data after the tags: start expression ("2025-01-01",
        // "after a b", "" = previous task end) and end expression
        public string raw_start { get; set; default = ""; }
        public string raw_end { get; set; default = ""; }
        public string? prev_task_id { get; set; default = null; }
        public Gee.ArrayList<string> after_ids { get; private set; }
        public Gee.ArrayList<string> until_ids { get; private set; }

        // Link from a "click id href" line
        public string? link { get; set; default = null; }
        public bool clickable { get; set; default = false; }

        // Schedule (milliseconds since the epoch, calendar arithmetic in UTC).
        // render_end_ms is where the bar is drawn to when excluded days
        // pushed end_ms further out; -1 when equal to end_ms.
        public bool scheduled { get; set; default = false; }
        public int64 start_ms { get; set; default = 0; }
        public int64 end_ms { get; set; default = 0; }
        public int64 render_end_ms { get; set; default = -1; }
        public bool manual_end { get; set; default = false; }

        public GanttTask(string id, string description, int line = 0) {
            this.id = id;
            this.description = description;
            this.status = GanttTaskStatus.NONE;
            this.start_date = null;
            this.end_date = null;
            this.duration = null;
            this.depends_on = null;
            this.source_line = line;
            this.after_ids = new Gee.ArrayList<string>();
            this.until_ids = new Gee.ArrayList<string>();
        }

        public int64 visible_end_ms() {
            return render_end_ms >= 0 ? render_end_ms : end_ms;
        }
    }

    public class GanttSection : Object {
        public string name { get; set; }
        public Gee.ArrayList<GanttTask> tasks { get; private set; }

        public GanttSection(string name) {
            this.name = name;
            this.tasks = new Gee.ArrayList<GanttTask>();
        }

        public void add_task(GanttTask task) {
            tasks.add(task);
        }
    }

    public class MermaidGantt : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public string? date_format { get; set; }
        public Gee.ArrayList<GanttSection> sections { get; private set; }
        public Gee.ArrayList<GanttTask> tasks { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        // Directives
        public string? axis_format { get; set; default = null; }
        public string? tick_interval { get; set; default = null; }
        public string today_marker { get; set; default = ""; }
        public Gee.ArrayList<string> excludes { get; private set; }
        public Gee.ArrayList<string> includes { get; private set; }
        public bool inclusive_end_dates { get; set; default = false; }
        public bool top_axis { get; set; default = false; }
        public string weekday { get; set; default = "sunday"; }
        public string weekend { get; set; default = "saturday"; }
        public bool compact { get; set; default = false; }

        // "Today" for todayMarker and unresolved references; tests pin it
        public int64 today_ms { get; set; default = -1; }

        public MermaidGantt() {
            this.diagram_type = MermaidDiagramType.GANTT;
            this.title = null;
            this.date_format = null;
            this.sections = new Gee.ArrayList<GanttSection>();
            this.tasks = new Gee.ArrayList<GanttTask>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.excludes = new Gee.ArrayList<string>();
            this.includes = new Gee.ArrayList<string>();
        }

        public void add_task(GanttTask task) {
            tasks.add(task);
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public GanttTask? find_task(string id) {
            foreach (var t in tasks) {
                if (t.id == id) return t;
            }
            return null;
        }
    }

}
