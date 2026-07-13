namespace GDiagram {

    // ==================== Timeline ====================

    public class TimelineEvent : Object {
        public string text { get; set; }
        public int source_line { get; set; }

        public TimelineEvent(string text, int line = 0) {
            this.text = text;
            this.source_line = line;
        }
    }

    public class TimelinePeriod : Object {
        public string label { get; set; }
        public string? section_name { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<TimelineEvent> events { get; private set; }

        public TimelinePeriod(string label, string? section = null, int line = 0) {
            this.label = label;
            this.section_name = section;
            this.source_line = line;
            this.events = new Gee.ArrayList<TimelineEvent>();
        }

        public void add_event(TimelineEvent e) { events.add(e); }
    }

    public class MermaidTimeline : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<TimelinePeriod> periods { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidTimeline() {
            this.diagram_type = MermaidDiagramType.TIMELINE;
            this.title = null;
            this.periods = new Gee.ArrayList<TimelinePeriod>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_period(TimelinePeriod p) { periods.add(p); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return periods.size == 0; }
    }

}
