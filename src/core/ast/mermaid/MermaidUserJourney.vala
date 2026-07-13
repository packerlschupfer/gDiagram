namespace GDiagram {

    // ==================== MERMAID USER JOURNEY ====================

    public class UserJourneyTask : Object {
        public string description { get; set; }
        public int score { get; set; }  // 1–5
        public Gee.ArrayList<string> actors { get; private set; }
        public int source_line { get; set; }

        public UserJourneyTask(string description, int score, int line = 0) {
            this.description = description;
            this.score = score.clamp(1, 5);
            this.actors = new Gee.ArrayList<string>();
            this.source_line = line;
        }
    }

    public class UserJourneySection : Object {
        public string name { get; set; }
        public Gee.ArrayList<UserJourneyTask> tasks { get; private set; }

        public UserJourneySection(string name) {
            this.name = name;
            this.tasks = new Gee.ArrayList<UserJourneyTask>();
        }

        public void add_task(UserJourneyTask task) {
            tasks.add(task);
        }
    }

    public class MermaidUserJourney : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<UserJourneySection> sections { get; private set; }
        public Gee.ArrayList<UserJourneyTask> all_tasks { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidUserJourney() {
            this.diagram_type = MermaidDiagramType.USER_JOURNEY;
            this.title = null;
            this.sections = new Gee.ArrayList<UserJourneySection>();
            this.all_tasks = new Gee.ArrayList<UserJourneyTask>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_task(UserJourneyTask task) {
            all_tasks.add(task);
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
