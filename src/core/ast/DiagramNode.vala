namespace GDiagram {
    public enum DiagramFormat {
        PLANTUML,
        MERMAID,
        UNKNOWN
    }

    public enum DiagramType {
        SEQUENCE,
        CLASS,
        USECASE,
        ACTIVITY,
        STATE,
        COMPONENT,
        OBJECT,
        DEPLOYMENT,
        ER_DIAGRAM,
        MINDMAP,
        WBS,
        // Mermaid-specific types
        MERMAID_FLOWCHART,
        MERMAID_SEQUENCE,
        MERMAID_STATE,
        MERMAID_CLASS,
        MERMAID_ER,
        MERMAID_GANTT,
        MERMAID_PIE,
        UNKNOWN
    }

    public enum ParticipantType {
        PARTICIPANT,
        ACTOR,
        BOUNDARY,
        CONTROL,
        ENTITY,
        DATABASE,
        COLLECTIONS,
        QUEUE
    }

    public enum ArrowStyle {
        SOLID,          // ->
        DOTTED,         // -->
        SOLID_OPEN,     // ->>
        DOTTED_OPEN     // -->>
    }

    public enum ArrowDirection {
        RIGHT,
        LEFT,
        BIDIRECTIONAL
    }

    public class Participant : Object {
        public string name { get; set; }
        public string? alias { get; set; }
        public string? display_label { get; set; }  // Multi-line label for rendering
        public ParticipantType participant_type { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }

        public Participant(string name, ParticipantType type = ParticipantType.PARTICIPANT, int line = 0) {
            this.name = name;
            this.participant_type = type;
            this.alias = null;
            this.color = null;
            this.source_line = line;
        }

        public string get_id() {
            return alias ?? name;
        }
    }

    public class Message : Object {
        public Participant from { get; set; }
        public Participant to { get; set; }
        public string? label { get; set; }
        public ArrowStyle style { get; set; }
        public ArrowDirection direction { get; set; }
        public bool activate_target { get; set; }      // ++ at end
        public bool deactivate_source { get; set; }    // -- at end

        public Message(Participant from, Participant to) {
            this.from = from;
            this.to = to;
            this.label = null;
            this.style = ArrowStyle.SOLID;
            this.direction = ArrowDirection.RIGHT;
            this.activate_target = false;
            this.deactivate_source = false;
        }
    }

    public enum ActivationType {
        ACTIVATE,
        DEACTIVATE,
        DESTROY
    }

    public class Activation : Object {
        public Participant participant { get; set; }
        public ActivationType activation_type { get; set; }

        public Activation(Participant participant, ActivationType type) {
            this.participant = participant;
            this.activation_type = type;
        }
    }

    public class Note : Object {
        public string text { get; set; }
        public string position { get; set; }  // "left", "right", "over"
        public Participant? participant { get; set; }

        public Note(string text, string position) {
            this.text = text;
            this.position = position;
            this.participant = null;
        }
    }

    public class ParseError : Object {
        public string message { get; set; }
        public int line { get; set; }
        public int column { get; set; }

        public ParseError(string message, int line, int column) {
            this.message = message;
            this.line = line;
            this.column = column;
        }

        public string to_string() {
            return "Line %d:%d: %s".printf(line, column, message);
        }
    }

    // Base class for sequence events (for ordering)
    public abstract class SequenceEvent : Object {
        public int order { get; set; }
    }

    public class MessageEvent : SequenceEvent {
        public Message message { get; set; }
        public MessageEvent(Message msg, int order) {
            this.message = msg;
            this.order = order;
        }
    }

    public class NoteEvent : SequenceEvent {
        public Note note { get; set; }
        public NoteEvent(Note note, int order) {
            this.note = note;
            this.order = order;
        }
    }

    public class ActivationEvent : SequenceEvent {
        public Activation activation { get; set; }
        public ActivationEvent(Activation act, int order) {
            this.activation = act;
            this.order = order;
        }
    }

    // Grouping frames (alt/opt/loop/par/break/critical/group)
    public enum SequenceFrameType {
        ALT,        // alt/else/end
        OPT,        // opt/end (optional)
        LOOP,       // loop/end
        PAR,        // par/end (parallel)
        BREAK,      // break/end
        CRITICAL,   // critical/end
        GROUP,      // group/end (generic)
        REF,        // ref (reference to another diagram)
        ELSE        // else section within alt
    }

    public class SequenceFrame : Object {
        public string id { get; set; }
        public SequenceFrameType frame_type { get; set; }
        public string? label { get; set; }
        public string? condition { get; set; }
        public int start_order { get; set; }
        public int end_order { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<SequenceFrame> sections { get; private set; }  // For else sections in alt
        public SequenceFrame? parent { get; set; }

        private static int frame_counter = 0;

        public SequenceFrame(SequenceFrameType type, int line = 0) {
            this.id = "_frame_%d".printf(frame_counter++);
            this.frame_type = type;
            this.label = null;
            this.condition = null;
            this.start_order = 0;
            this.end_order = 0;
            this.source_line = line;
            this.sections = new Gee.ArrayList<SequenceFrame>();
            this.parent = null;
        }

        public static void reset_counter() {
            frame_counter = 0;
        }

        public string get_type_label() {
            switch (frame_type) {
                case SequenceFrameType.ALT:
                    return "alt";
                case SequenceFrameType.OPT:
                    return "opt";
                case SequenceFrameType.LOOP:
                    return "loop";
                case SequenceFrameType.PAR:
                    return "par";
                case SequenceFrameType.BREAK:
                    return "break";
                case SequenceFrameType.CRITICAL:
                    return "critical";
                case SequenceFrameType.GROUP:
                    return "group";
                case SequenceFrameType.REF:
                    return "ref";
                case SequenceFrameType.ELSE:
                    return "else";
                default:
                    return "group";
            }
        }
    }

    public class FrameEvent : SequenceEvent {
        public SequenceFrame frame { get; set; }
        public bool is_start { get; set; }
        public FrameEvent(SequenceFrame frame, bool is_start, int order) {
            this.frame = frame;
            this.is_start = is_start;
            this.order = order;
        }
    }

    public class SequenceDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<Participant> participants { get; private set; }
        public Gee.ArrayList<Message> messages { get; private set; }
        public Gee.ArrayList<Note> notes { get; private set; }
        public Gee.ArrayList<Activation> activations { get; private set; }
        public Gee.ArrayList<SequenceFrame> frames { get; private set; }
        public Gee.ArrayList<SequenceEvent> events { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }
        private int event_counter = 0;

        public SequenceDiagram() {
            this.diagram_type = DiagramType.SEQUENCE;
            this.participants = new Gee.ArrayList<Participant>();
            this.messages = new Gee.ArrayList<Message>();
            this.notes = new Gee.ArrayList<Note>();
            this.activations = new Gee.ArrayList<Activation>();
            this.frames = new Gee.ArrayList<SequenceFrame>();
            this.events = new Gee.ArrayList<SequenceEvent>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counters
            SequenceFrame.reset_counter();
        }

        public void add_message(Message msg) {
            messages.add(msg);
            events.add(new MessageEvent(msg, event_counter++));
        }

        public void add_note(Note note) {
            notes.add(note);
            events.add(new NoteEvent(note, event_counter++));
        }

        public void add_activation(Activation act) {
            activations.add(act);
            events.add(new ActivationEvent(act, event_counter++));
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public Participant? find_participant(string name) {
            foreach (var p in participants) {
                if (p.name == name || p.alias == name) {
                    return p;
                }
            }
            return null;
        }

        public Participant get_or_create_participant(string name) {
            var existing = find_participant(name);
            if (existing != null) {
                return existing;
            }

            var participant = new Participant(name);
            participants.add(participant);
            return participant;
        }
    }
}
