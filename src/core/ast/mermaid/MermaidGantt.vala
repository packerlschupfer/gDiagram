namespace GDiagram {

    // ==================== MERMAID GANTT CHART ====================

    public enum GanttTaskStatus {
        ACTIVE,
        DONE,
        CRITICAL,
        MILESTONE
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

        public GanttTask(string id, string description, int line = 0) {
            this.id = id;
            this.description = description;
            this.status = GanttTaskStatus.ACTIVE;
            this.start_date = null;
            this.end_date = null;
            this.duration = null;
            this.depends_on = null;
            this.source_line = line;
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

        public MermaidGantt() {
            this.diagram_type = MermaidDiagramType.GANTT;
            this.title = null;
            this.date_format = null;
            this.sections = new Gee.ArrayList<GanttSection>();
            this.tasks = new Gee.ArrayList<GanttTask>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_task(GanttTask task) {
            tasks.add(task);
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
