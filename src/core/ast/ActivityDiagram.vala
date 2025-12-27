namespace GDiagram {
    public enum ActivityNodeType {
        START,
        STOP,
        END,
        KILL,
        DETACH,
        ACTION,
        CONDITION,
        FORK,
        JOIN,
        MERGE,
        NOTE,
        CONNECTOR,
        SEPARATOR,
        VSPACE
    }

    public enum ActionShape {
        DEFAULT,       // rounded box
        SDL_TASK,      // |text| - box
        SDL_INPUT,     // <text> - rectangle with < cut on right
        SDL_OUTPUT,    // >text> - rectangle with > cut on right
        SDL_SAVE,      // /text/ - parallelogram leaning right
        SDL_LOAD,      // \text\ - parallelogram leaning left
        SDL_PROCEDURE  // ]text] - procedure
    }

    public class ActivityNode : Object {
        public string id { get; set; }
        public ActivityNodeType node_type { get; set; }
        public string? label { get; set; }
        public string? condition_yes { get; set; }
        public string? condition_no { get; set; }
        public string? partition { get; set; }
        public string? color { get; set; }
        public string? color2 { get; set; }  // For gradient: color to color2
        public string? line_color { get; set; }  // Border color
        public string? text_color { get; set; }  // Font color
        public string? stereotype { get; set; }
        public string? url { get; set; }  // Hyperlink URL
        public ActionShape shape { get; set; }
        public int source_line { get; set; }

        private static int id_counter = 0;

        public ActivityNode(ActivityNodeType type, string? label = null, int line = 0) {
            this.id = "node%d".printf(id_counter++);
            this.node_type = type;
            this.label = label;
            this.condition_yes = "yes";
            this.condition_no = "no";
            this.partition = null;
            this.color = null;
            this.color2 = null;
            this.line_color = null;
            this.text_color = null;
            this.url = null;
            this.shape = ActionShape.DEFAULT;
            this.source_line = line;
        }

        public static void reset_counter() {
            id_counter = 0;
        }
    }

    public enum NotePosition {
        LEFT,
        RIGHT,
        TOP,
        BOTTOM
    }

    public class ActivityNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public NotePosition position { get; set; }
        public ActivityNode? attached_to { get; set; }
        public string? color { get; set; }

        private static int note_counter = 0;

        public ActivityNote(string text, NotePosition position, ActivityNode? attached_to = null, string? color = null) {
            this.id = "note%d".printf(note_counter++);
            this.text = text;
            this.position = position;
            this.attached_to = attached_to;
            this.color = color;
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public enum EdgeDirection {
        DEFAULT,
        UP,
        DOWN,
        LEFT,
        RIGHT
    }

    public enum LegendPosition {
        LEFT,
        RIGHT,
        CENTER
    }

    public class ActivityLegend : Object {
        public string text { get; set; }
        public LegendPosition position { get; set; }

        public ActivityLegend(string text, LegendPosition position = LegendPosition.RIGHT) {
            this.text = text;
            this.position = position;
        }
    }

    public class ActivityEdge : Object {
        public ActivityNode from { get; set; }
        public ActivityNode to { get; set; }
        public string? label { get; set; }
        public bool is_yes_branch { get; set; }
        public bool is_no_branch { get; set; }
        public string? color { get; set; }
        public string? style { get; set; }  // "dashed", "dotted", "bold", etc.
        public EdgeDirection direction { get; set; }
        public string? note { get; set; }  // Note on link

        public ActivityEdge(ActivityNode from, ActivityNode to, string? label = null) {
            this.from = from;
            this.to = to;
            this.label = label;
            this.is_yes_branch = false;
            this.is_no_branch = false;
            this.color = null;
            this.style = null;
            this.direction = EdgeDirection.DEFAULT;
            this.note = null;
        }
    }

    public class ActivityPartition : Object {
        public string name { get; set; }
        public string? alias { get; set; }  // Short alias for referencing
        public string? color { get; set; }
        public Gee.ArrayList<ActivityNode> nodes { get; private set; }

        public ActivityPartition(string name, string? color = null, string? alias = null) {
            this.name = name;
            this.alias = alias;
            this.color = color;
            this.nodes = new Gee.ArrayList<ActivityNode>();
        }
    }

    public class ActivityDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }
        public string? caption { get; set; }
        public Gee.ArrayList<ActivityNode> nodes { get; private set; }
        public Gee.ArrayList<ActivityEdge> edges { get; private set; }
        public Gee.ArrayList<ActivityPartition> partitions { get; private set; }
        public Gee.ArrayList<ActivityNote> notes { get; private set; }
        public ActivityLegend? legend { get; set; }
        public SkinParams skin_params { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public ActivityDiagram() {
            this.diagram_type = DiagramType.ACTIVITY;
            this.title = null;
            this.header = null;
            this.footer = null;
            this.caption = null;
            this.nodes = new Gee.ArrayList<ActivityNode>();
            this.edges = new Gee.ArrayList<ActivityEdge>();
            this.partitions = new Gee.ArrayList<ActivityPartition>();
            this.notes = new Gee.ArrayList<ActivityNote>();
            this.legend = null;
            this.skin_params = new SkinParams();
            this.errors = new Gee.ArrayList<ParseError>();
            ActivityNode.reset_counter();
            ActivityNote.reset_counter();
        }

        public void add_node(ActivityNode node) {
            nodes.add(node);
        }

        public void add_edge(ActivityEdge edge) {
            edges.add(edge);
        }

        public new void connect(ActivityNode from, ActivityNode to, string? label = null) {
            var edge = new ActivityEdge(from, to, label);
            edges.add(edge);
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }
}
