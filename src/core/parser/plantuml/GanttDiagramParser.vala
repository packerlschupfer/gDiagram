/* GanttDiagramParser.vala — line-based parser for PlantUML @startgantt */
namespace GDiagram {

public class GanttDiagramParser : Object {
    private PumlGanttDiagram diagram;

    public GanttDiagramParser() {}

    public PumlGanttDiagram parse(string source) {
        this.diagram = new PumlGanttDiagram();

        parse_gantt(source);

        return diagram;
    }

    private void parse_gantt(string source) {
        string? current_section = null;
        string[] lines = source.split("\n");

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("'") || trimmed.has_prefix("/'")) continue;  // comments

            string lower = trimmed.down();
            if (lower == "@startgantt" || lower == "@endgantt") continue;
            if (lower.has_prefix("scale ") || lower.has_prefix("skinparam ") ||
                lower.has_prefix("<style>") || lower == "</style>") continue;
            if (lower.has_prefix("saturday") || lower.has_prefix("sunday") ||
                lower.has_prefix("monday") || lower.has_prefix("closed ")) continue;

            // Title
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            // Project start date
            if (lower.has_prefix("project starts ")) {
                diagram.project_start = trimmed.substring(15).strip();
                continue;
            }

            // Section separator: -- Name --
            if (trimmed.has_prefix("--") && trimmed.has_suffix("--") && trimmed.length > 4) {
                current_section = trimmed.substring(2, trimmed.length - 4).strip();
                continue;
            }

            // Task lines start with [
            if (trimmed.has_prefix("[")) {
                parse_task_line(trimmed, current_section, i + 1);
                continue;
            }
        }
    }

    private void parse_task_line(string line, string? section, int lineno) {
        // Extract task name between [ and ]
        int close_bracket = line.index_of("]");
        if (close_bracket < 0) return;

        string task_name = line.substring(1, close_bracket - 1).strip();
        string rest = line.substring(close_bracket + 1).strip();
        string lower_rest = rest.down();

        // Find or create task
        var task = find_or_create_task(task_name, section, lineno);

        // Parse modifiers
        if (lower_rest.has_prefix("requires") || lower_rest.has_prefix("lasts")) {
            // [Task] requires N days/weeks
            string[] parts = rest.split(" ");
            if (parts.length >= 3) {
                int n = int.parse(parts[1]);
                string unit = (parts.length > 2) ? parts[2].down() : "days";
                if (unit.has_prefix("week")) n *= 7;
                task.duration_days = n;
            }
        } else if (lower_rest.has_prefix("starts at [")) {
            // [Task] starts at [OtherTask]'s end/start
            int ob = rest.index_of("[", 10);
            int cb = rest.index_of("]", ob > 0 ? ob : 0);
            if (ob >= 0 && cb > ob) {
                task.start_after_task = rest.substring(ob + 1, cb - ob - 1).strip();
                task.start_at_start = rest.down().contains("'s start");
            }
        } else if (lower_rest.has_prefix("starts ") || lower_rest.has_prefix("starts d+")) {
            // [Task] starts YYYY-MM-DD or D+N
            task.start_date = rest.substring(7).strip();
        } else if (lower_rest.has_prefix("happens at [")) {
            // [Milestone] happens at [Task]'s end
            task.is_milestone = true;
            int ob = rest.index_of("[", 11);
            int cb = rest.index_of("]", ob > 0 ? ob : 0);
            if (ob >= 0 && cb > ob) {
                task.start_after_task = rest.substring(ob + 1, cb - ob - 1).strip();
            }
        } else if (lower_rest.contains("% completed")) {
            // [Task] is N% completed
            int pct_pos = rest.index_of("%");
            if (pct_pos > 0) {
                string pct_str = rest.substring(0, pct_pos).replace("is ", "").strip();
                task.completion_pct = int.parse(pct_str);
            }
        } else if (lower_rest.has_prefix("is colored in ")) {
            // [Task] is colored in Color
            task.color = rest.substring(14).strip().split("/")[0].strip();
        } else if (lower_rest.has_prefix("->")) {
            // [Task] -> [NextTask]: dependency
            int ob = rest.index_of("[", 2);
            int cb = rest.index_of("]", ob > 0 ? ob : 0);
            if (ob >= 0 && cb > ob) {
                string next_name = rest.substring(ob + 1, cb - ob - 1).strip();
                var next_task = find_or_create_task(next_name, section, lineno);
                next_task.start_after_task = task_name;
            }
        }
    }

    private PumlGanttTask find_or_create_task(string name, string? section, int lineno) {
        foreach (var t in diagram.tasks) {
            if (t.name == name) return t;
        }
        var task = new PumlGanttTask(name, lineno);
        task.section = section;
        diagram.add_task(task);
        return task;
    }
}

}
