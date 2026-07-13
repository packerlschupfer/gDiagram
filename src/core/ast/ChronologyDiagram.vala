/* ChronologyDiagram.vala — AST for PlantUML Chronology diagrams */
namespace GDiagram {

public class ChronologyEvent : Object {
    public string name { get; set; }
    public string date_str { get; set; }     // YYYY-MM-DD or YYYY-MM-DD HH:MM:SS
    public int source_line { get; set; }

    public ChronologyEvent(string name, string date_str, int line = 0) {
        this.name = name;
        this.date_str = date_str;
        this.source_line = line;
    }
}

public class ChronologyDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<ChronologyEvent> events { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public ChronologyDiagram() {
        this.diagram_type = DiagramType.CHRONOLOGY;
        this.events = new Gee.ArrayList<ChronologyEvent>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public void add_event(ChronologyEvent event) { events.add(event); }
    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return events.size == 0; }
}

}
