/* GanttDiagram.vala — AST for PlantUML Gantt charts */
namespace GDiagram {

public class PumlGanttTask : Object {
    public string name { get; set; }
    public string? alias_name { get; set; }       // [Task] as [T]
    public int duration_days { get; set; }        // requires N days
    public string? start_date { get; set; }       // YYYY-MM-DD or D+N
    public string? start_after_task { get; set; } // starts at [X]'s end
    public bool start_at_start { get; set; }      // starts at [X]'s start
    public bool is_milestone { get; set; }
    public int completion_pct { get; set; }       // 0-100
    public string? color { get; set; }
    public string? section { get; set; }
    public int source_line { get; set; }

    public PumlGanttTask(string name, int line = 0) {
        this.name = name;
        this.duration_days = 1;
        this.is_milestone = false;
        this.completion_pct = 0;
        this.start_at_start = false;
        this.source_line = line;
    }
}

public class PumlGanttDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public string? project_start { get; set; }
    public Gee.ArrayList<PumlGanttTask> tasks { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public PumlGanttDiagram() {
        this.diagram_type = DiagramType.GANTT;
        this.tasks = new Gee.ArrayList<PumlGanttTask>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public void add_task(PumlGanttTask task) { tasks.add(task); }
    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return tasks.size == 0; }
}

}
