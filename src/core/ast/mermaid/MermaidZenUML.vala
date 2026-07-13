namespace GDiagram {

// ==================== ZenUML ====================

public class ZenParticipant : Object {
    public string name { get; set; }
    public string actor_type { get; set; }  // Actor, Boundary, Control, Entity, Database, etc.
    public string? color { get; set; }
    public string? stereotype { get; set; default = null; }  // "@<<service>> Ext"
    public int source_line { get; set; }
    // The implicit caller of top-level calls without "A ->" (drawn as a nameless actor)
    public bool is_starter { get; set; default = false; }

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
    public bool is_async { get; set; default = false; }    // "A->B: text"
    public bool is_create { get; set; default = false; }   // "new B()"
    public bool has_body { get; set; default = false; }    // "A.m() { ... }"
    public string? number { get; set; default = null; }    // "1.2.1" as ZenUML numbers it
    public string? comment { get; set; default = null; }   // the "// ..." line above it

    public ZenMessage(string from_name, string to_name, string method, int line = 0) {
        this.from_name = from_name;
        this.to_name = to_name;
        this.method = method;
        this.is_return = false;
        this.depth = 0;
        this.source_line = line;
    }
}

public enum ZenEventKind {
    MESSAGE,        // a call, async message or return
    BODY_END,       // the "}" of a call body: the callee's activation ends
    BLOCK_START,    // if / loop / opt / par / try / critical / section
    BLOCK_SECTION,  // else / else if / catch / finally
    BLOCK_END
}

// The statements in source order, for the sequence layout
public class ZenEvent : Object {
    public ZenEventKind kind { get; set; }
    public ZenMessage? message { get; set; default = null; }
    public string? participant { get; set; default = null; }  // BODY_END: whose activation ends
    public string? keyword { get; set; default = null; }      // "if", "else", "loop", ...
    public string? condition { get; set; default = null; }
    public string? number { get; set; default = null; }
    public int source_line { get; set; default = 0; }

    public ZenEvent(ZenEventKind kind, int line) {
        this.kind = kind;
        this.source_line = line;
    }
}

public class MermaidZenUML : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<ZenParticipant> participants { get; private set; }
    public Gee.ArrayList<ZenMessage> messages { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }
    public Gee.ArrayList<ZenEvent> events { get; private set; }

    public MermaidZenUML() {
        this.diagram_type = MermaidDiagramType.ZENUML;
        this.title = null;
        this.participants = new Gee.ArrayList<ZenParticipant>();
        this.messages = new Gee.ArrayList<ZenMessage>();
        this.errors = new Gee.ArrayList<ParseError>();
        this.events = new Gee.ArrayList<ZenEvent>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return messages.size == 0 && participants.size == 0; }
}

}
