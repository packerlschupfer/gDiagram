namespace GDiagram {

    // ==================== MERMAID SEQUENCE DIAGRAM ====================

    public enum MermaidArrowType {
        SOLID_ARROW,        // ->>
        DOTTED_ARROW,       // -->>
        SOLID_LINE,         // ->   (no head)
        DOTTED_LINE,        // -->  (no head)
        SOLID_CROSS,        // -x
        DOTTED_CROSS,       // --x
        SOLID_OPEN,         // -)
        DOTTED_OPEN,        // --)
        SOLID_BIDIRECTIONAL,  // <<->>
        DOTTED_BIDIRECTIONAL  // <<-->>
    }

    public class MermaidActor : Object {
        public string id { get; set; }
        public string? alias { get; set; }
        public bool is_participant { get; set; }  // false = actor
        public int source_line { get; set; }
        // "participant A@{ "type": "database" }": boundary, control, entity, database,
        // collections or queue; null for a plain participant / actor
        public string? shape { get; set; default = null; }
        // Index into MermaidSequenceDiagram.boxes, -1 outside any "box"
        public int box_index { get; set; default = -1; }

        public MermaidActor(string id, bool is_participant = true, int line = 0) {
            this.id = id;
            this.alias = null;
            this.is_participant = is_participant;
            this.source_line = line;
        }

        public string get_display_name() {
            return alias ?? id;
        }
    }

    public class MermaidMessage : Object {
        public MermaidActor from { get; set; }
        public MermaidActor to { get; set; }
        public string? text { get; set; }
        public MermaidArrowType arrow_type { get; set; }
        public bool is_activation { get; set; }
        public bool is_deactivation { get; set; }
        public int sequence_index { get; set; default = -1; }  // position in messages list
        public int source_line { get; set; default = 0; }
        public int number { get; set; default = -1; }           // autonumber value, -1 when off

        public MermaidMessage(MermaidActor from, MermaidActor to) {
            this.from = from;
            this.to = to;
            this.text = null;
            this.arrow_type = MermaidArrowType.SOLID_ARROW;
            this.is_activation = false;
            this.is_deactivation = false;
        }
    }

    public class MermaidNote : Object {
        public string text { get; set; }
        public MermaidActor? over_actor { get; set; }
        public MermaidActor? from_actor { get; set; }
        public MermaidActor? to_actor { get; set; }
        public bool is_right { get; set; }  // right of / left of
        public bool is_over { get; set; default = false; }
        public int source_line { get; set; default = 0; }

        public MermaidNote(string text) {
            this.text = text;
            this.over_actor = null;
            this.from_actor = null;
            this.to_actor = null;
            this.is_right = true;
        }
    }

    public enum MermaidLoopType {
        LOOP,
        ALT,
        OPT,
        PAR,
        CRITICAL,
        BREAK,
        RECT
    }

    // An "else" / "and" / "option" divider inside a block
    public class MermaidLoopSection : Object {
        public string? condition { get; set; }
        public int msg_start { get; set; default = -1; }
        public int source_line { get; set; default = 0; }

        public MermaidLoopSection(string? condition) {
            this.condition = condition;
        }
    }

    public class MermaidLoop : Object {
        public MermaidLoopType loop_type { get; set; }
        public string? condition { get; set; }
        public int msg_start { get; set; default = -1; }  // index into diagram.messages (inclusive)
        public int msg_end { get; set; default = -1; }    // index into diagram.messages (inclusive)
        public Gee.ArrayList<MermaidMessage> messages { get; private set; }
        public Gee.ArrayList<MermaidNote> notes { get; private set; }
        public Gee.ArrayList<MermaidLoopSection> sections { get; private set; }
        public string? color { get; set; default = null; }  // "rect" background
        public int depth { get; set; default = 0; }          // nesting level, 0 = outermost
        public int source_line { get; set; default = 0; }

        public MermaidLoop(MermaidLoopType type) {
            this.loop_type = type;
            this.condition = null;
            this.messages = new Gee.ArrayList<MermaidMessage>();
            this.notes = new Gee.ArrayList<MermaidNote>();
            this.sections = new Gee.ArrayList<MermaidLoopSection>();
        }
    }

    // "box [colour] [title] ... end" around participants
    public class MermaidBox : Object {
        public string? label { get; set; default = null; }
        public string? color { get; set; default = null; }
        public Gee.ArrayList<MermaidActor> actors { get; private set; }
        public int source_line { get; set; default = 0; }

        public MermaidBox() {
            this.actors = new Gee.ArrayList<MermaidActor>();
        }
    }

    public enum MermaidSeqEventKind {
        MESSAGE,
        NOTE,
        BLOCK_START,
        BLOCK_SECTION,
        BLOCK_END,
        ACTIVATE,
        DEACTIVATE,
        CREATE,
        DESTROY
    }

    // The statements in source order: what the renderer lays out row by row
    public class MermaidSeqEvent : Object {
        public MermaidSeqEventKind kind { get; set; }
        public MermaidMessage? message { get; set; default = null; }
        public MermaidNote? note { get; set; default = null; }
        public MermaidLoop? loop { get; set; default = null; }
        public MermaidLoopSection? section { get; set; default = null; }
        public MermaidActor? actor { get; set; default = null; }
        public int source_line { get; set; default = 0; }

        public MermaidSeqEvent(MermaidSeqEventKind kind, int line) {
            this.kind = kind;
            this.source_line = line;
        }
    }

    public class MermaidSequenceDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidActor> actors { get; private set; }
        public Gee.ArrayList<MermaidMessage> messages { get; private set; }
        public Gee.ArrayList<MermaidNote> notes { get; private set; }
        public Gee.ArrayList<MermaidLoop> loops { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public Gee.ArrayList<MermaidSeqEvent> events { get; private set; }
        public Gee.ArrayList<MermaidBox> boxes { get; private set; }
        public string? title { get; set; }
        public bool autonumber { get; set; }

        private Gee.HashMap<string, MermaidActor> actor_map;

        public MermaidSequenceDiagram() {
            this.diagram_type = MermaidDiagramType.SEQUENCE;
            this.actors = new Gee.ArrayList<MermaidActor>();
            this.messages = new Gee.ArrayList<MermaidMessage>();
            this.notes = new Gee.ArrayList<MermaidNote>();
            this.loops = new Gee.ArrayList<MermaidLoop>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.events = new Gee.ArrayList<MermaidSeqEvent>();
            this.boxes = new Gee.ArrayList<MermaidBox>();
            this.actor_map = new Gee.HashMap<string, MermaidActor>();
            this.title = null;
            this.autonumber = false;
        }

        public void add_actor(MermaidActor actor) {
            if (!actor_map.has_key(actor.id)) {
                actors.add(actor);
                actor_map.set(actor.id, actor);
            }
        }

        public MermaidActor? find_actor(string id) {
            return actor_map.get(id);
        }

        public MermaidActor get_or_create_actor(string id) {
            var existing = find_actor(id);
            if (existing != null) {
                return existing;
            }

            var actor = new MermaidActor(id);
            add_actor(actor);
            return actor;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
