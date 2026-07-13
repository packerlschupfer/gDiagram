namespace GDiagram {

// ==================== ZenUML ====================

public class ZenParticipant : Object {
    public string name { get; set; }
    public string actor_type { get; set; }  // Actor, Boundary, Control, Entity, Database, etc.
    public string? color { get; set; }
    public int source_line { get; set; }

    public ZenParticipant(string name, string actor_type, int line = 0) {
        this.name = name;
        this.actor_type = actor_type;
        this.source_line = line;
    }
}

public class ZenMessage : Object {
    public string from_name { get; set; }
    public string to_name { get; set; }
    public string method { get; set; }
    public string? params_str { get; set; }
    public bool is_return { get; set; }
    public int depth { get; set; }  // nesting depth
    public int source_line { get; set; }

    public ZenMessage(string from_name, string to_name, string method, int line = 0) {
        this.from_name = from_name;
        this.to_name = to_name;
        this.method = method;
        this.is_return = false;
        this.depth = 0;
        this.source_line = line;
    }
}

public class MermaidZenUML : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<ZenParticipant> participants { get; private set; }
    public Gee.ArrayList<ZenMessage> messages { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidZenUML() {
        this.diagram_type = MermaidDiagramType.ZENUML;
        this.title = null;
        this.participants = new Gee.ArrayList<ZenParticipant>();
        this.messages = new Gee.ArrayList<ZenMessage>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return messages.size == 0 && participants.size == 0; }
}

}
