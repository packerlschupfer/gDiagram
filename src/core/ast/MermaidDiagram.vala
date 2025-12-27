namespace GDiagram {
    // Mermaid-specific diagram types
    public enum MermaidDiagramType {
        FLOWCHART,
        SEQUENCE,
        CLASS,
        STATE,
        ER_DIAGRAM,
        GANTT,
        PIE,
        GIT_GRAPH,
        USER_JOURNEY,
        UNKNOWN
    }

    // ==================== FLOWCHART ====================

    public enum FlowchartDirection {
        TOP_DOWN,       // TD or TB
        BOTTOM_UP,      // BT
        LEFT_RIGHT,     // LR
        RIGHT_LEFT      // RL
    }

    public enum FlowchartNodeShape {
        RECTANGLE,      // [text]
        ROUNDED,        // (text)
        STADIUM,        // ([text])
        SUBROUTINE,     // [[text]]
        CYLINDRICAL,    // [(text)]
        CIRCLE,         // ((text))
        ASYMMETRIC,     // >text]
        RHOMBUS,        // {text}
        HEXAGON,        // {{text}}
        PARALLELOGRAM,  // [/text/]
        TRAPEZOID,      // [\\text/]
        DOUBLE_CIRCLE   // (((text)))
    }

    public enum FlowchartEdgeType {
        SOLID,          // -->
        DOTTED,         // -.->
        THICK,          // ==>
        INVISIBLE       // ~~~
    }

    public enum FlowchartArrowType {
        NORMAL,         // -->
        OPEN,           // --o
        CROSS,          // --x
        CIRCLE,         // --o
        NONE            // ---
    }

    public class FlowchartNode : Object {
        public string id { get; set; }
        public string text { get; set; }
        public FlowchartNodeShape shape { get; set; }
        public string? style_class { get; set; }
        public string? click_action { get; set; }
        public int source_line { get; set; }

        // Direct style properties
        public string? fill_color { get; set; }
        public string? stroke_color { get; set; }
        public string? stroke_width { get; set; }
        public string? tooltip { get; set; }
        public string? href_link { get; set; }

        public FlowchartNode(string id, string text, FlowchartNodeShape shape = FlowchartNodeShape.RECTANGLE, int line = 0) {
            this.id = id;
            this.text = text;
            this.shape = shape;
            this.style_class = null;
            this.click_action = null;
            this.source_line = line;
        }

        public string get_safe_id() {
            // Ensure ID is valid for Graphviz
            var sb = new StringBuilder();
            foreach (char c in id.to_utf8()) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_') {
                    sb.append_c(c);
                } else {
                    sb.append_c('_');
                }
            }
            string result = sb.str;
            if (result.length == 0 || (result[0] >= '0' && result[0] <= '9')) {
                return "n_" + result;
            }
            return result;
        }
    }

    public class FlowchartEdge : Object {
        public FlowchartNode from { get; set; }
        public FlowchartNode to { get; set; }
        public string? label { get; set; }
        public FlowchartEdgeType edge_type { get; set; }
        public FlowchartArrowType arrow_type { get; set; }
        public int min_length { get; set; default = 1; }  // For controlling spacing

        // Edge styling
        public string? edge_color { get; set; }
        public string? edge_thickness { get; set; }
        public string? label_color { get; set; }

        public FlowchartEdge(FlowchartNode from, FlowchartNode to) {
            this.from = from;
            this.to = to;
            this.label = null;
            this.edge_type = FlowchartEdgeType.SOLID;
            this.arrow_type = FlowchartArrowType.NORMAL;
            this.min_length = 1;
        }
    }

    public class FlowchartSubgraph : Object {
        public string id { get; set; }
        public string? title { get; set; }
        public FlowchartDirection direction { get; set; default = FlowchartDirection.TOP_DOWN; }
        public bool has_custom_direction { get; set; default = false; }
        public Gee.ArrayList<FlowchartNode> nodes { get; private set; }
        public Gee.ArrayList<FlowchartSubgraph> subgraphs { get; private set; }

        public FlowchartSubgraph(string id) {
            this.id = id;
            this.title = null;
            this.has_custom_direction = false;
            this.nodes = new Gee.ArrayList<FlowchartNode>();
            this.subgraphs = new Gee.ArrayList<FlowchartSubgraph>();
        }
    }

    public class FlowchartStyle : Object {
        public string class_name { get; set; }
        public string? fill_color { get; set; }
        public string? stroke_color { get; set; }
        public string? stroke_width { get; set; }
        public string? font_color { get; set; }

        public FlowchartStyle(string class_name) {
            this.class_name = class_name;
            this.fill_color = null;
            this.stroke_color = null;
            this.stroke_width = null;
            this.font_color = null;
        }
    }

    public class MermaidFlowchart : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public FlowchartDirection direction { get; set; }
        public Gee.ArrayList<FlowchartNode> nodes { get; private set; }
        public Gee.ArrayList<FlowchartEdge> edges { get; private set; }
        public Gee.ArrayList<FlowchartSubgraph> subgraphs { get; private set; }
        public Gee.ArrayList<FlowchartStyle> styles { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }

        private Gee.HashMap<string, FlowchartNode> node_map;

        public MermaidFlowchart() {
            this.diagram_type = MermaidDiagramType.FLOWCHART;
            this.direction = FlowchartDirection.TOP_DOWN;
            this.nodes = new Gee.ArrayList<FlowchartNode>();
            this.edges = new Gee.ArrayList<FlowchartEdge>();
            this.subgraphs = new Gee.ArrayList<FlowchartSubgraph>();
            this.styles = new Gee.ArrayList<FlowchartStyle>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.node_map = new Gee.HashMap<string, FlowchartNode>();
            this.title = null;
        }

        public void add_node(FlowchartNode node) {
            if (!node_map.has_key(node.id)) {
                nodes.add(node);
                node_map.set(node.id, node);
            }
        }

        public FlowchartNode? find_node(string id) {
            return node_map.get(id);
        }

        public FlowchartNode get_or_create_node(string id, string? text = null) {
            var existing = find_node(id);
            if (existing != null) {
                return existing;
            }

            var node = new FlowchartNode(id, text ?? id);
            add_node(node);
            return node;
        }

        public void add_edge(FlowchartEdge edge) {
            edges.add(edge);
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

    // ==================== MERMAID SEQUENCE DIAGRAM ====================

    public enum MermaidArrowType {
        SOLID_ARROW,        // ->
        DOTTED_ARROW,       // -->
        SOLID_LINE,         // -
        DOTTED_LINE,        // --
        SOLID_CROSS,        // -x
        DOTTED_CROSS,       // --x
        SOLID_OPEN,         // -)
        DOTTED_OPEN         // --)
    }

    public class MermaidActor : Object {
        public string id { get; set; }
        public string? alias { get; set; }
        public bool is_participant { get; set; }  // false = actor
        public int source_line { get; set; }

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

    public class MermaidLoop : Object {
        public MermaidLoopType loop_type { get; set; }
        public string? condition { get; set; }
        public Gee.ArrayList<MermaidMessage> messages { get; private set; }
        public Gee.ArrayList<MermaidNote> notes { get; private set; }

        public MermaidLoop(MermaidLoopType type) {
            this.loop_type = type;
            this.condition = null;
            this.messages = new Gee.ArrayList<MermaidMessage>();
            this.notes = new Gee.ArrayList<MermaidNote>();
        }
    }

    public class MermaidSequenceDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidActor> actors { get; private set; }
        public Gee.ArrayList<MermaidMessage> messages { get; private set; }
        public Gee.ArrayList<MermaidNote> notes { get; private set; }
        public Gee.ArrayList<MermaidLoop> loops { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
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

    // ==================== MERMAID CLASS DIAGRAM ====================

    public enum MermaidClassType {
        CLASS,
        INTERFACE,
        ABSTRACT,
        ENUM
    }

    public enum MermaidVisibility {
        PUBLIC,      // +
        PRIVATE,     // -
        PROTECTED,   // #
        PACKAGE      // ~
    }

    public enum MermaidRelationType {
        INHERITANCE,      // <|--
        COMPOSITION,      // *--
        AGGREGATION,      // o--
        ASSOCIATION,      // -->
        DEPENDENCY,       // ..>
        REALIZATION       // ..|>
    }

    public class MermaidClassMember : Object {
        public string name { get; set; }
        public string? type_name { get; set; }
        public MermaidVisibility visibility { get; set; }
        public bool is_static { get; set; }
        public bool is_abstract { get; set; }
        public bool is_method { get; set; }

        public MermaidClassMember(string name, bool is_method = false) {
            this.name = name;
            this.is_method = is_method;
            this.visibility = MermaidVisibility.PUBLIC;
            this.is_static = false;
            this.is_abstract = false;
            this.type_name = null;
        }
    }

    public class MermaidClass : Object {
        public string name { get; set; }
        public MermaidClassType class_type { get; set; }
        public string? stereotype { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<MermaidClassMember> members { get; private set; }

        public MermaidClass(string name, MermaidClassType type = MermaidClassType.CLASS, int line = 0) {
            this.name = name;
            this.class_type = type;
            this.stereotype = null;
            this.source_line = line;
            this.members = new Gee.ArrayList<MermaidClassMember>();
        }

        public void add_member(MermaidClassMember member) {
            members.add(member);
        }
    }

    public class MermaidRelation : Object {
        public MermaidClass from { get; set; }
        public MermaidClass to { get; set; }
        public MermaidRelationType relation_type { get; set; }
        public string? label { get; set; }
        public string? from_cardinality { get; set; }
        public string? to_cardinality { get; set; }

        public MermaidRelation(MermaidClass from, MermaidClass to, MermaidRelationType type) {
            this.from = from;
            this.to = to;
            this.relation_type = type;
            this.label = null;
            this.from_cardinality = null;
            this.to_cardinality = null;
        }
    }

    public class MermaidClassDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidClass> classes { get; private set; }
        public Gee.ArrayList<MermaidRelation> relations { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }

        private Gee.HashMap<string, MermaidClass> class_map;

        public MermaidClassDiagram() {
            this.diagram_type = MermaidDiagramType.CLASS;
            this.classes = new Gee.ArrayList<MermaidClass>();
            this.relations = new Gee.ArrayList<MermaidRelation>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.class_map = new Gee.HashMap<string, MermaidClass>();
            this.title = null;
        }

        public void add_class(MermaidClass cls) {
            if (!class_map.has_key(cls.name)) {
                classes.add(cls);
                class_map.set(cls.name, cls);
            }
        }

        public MermaidClass? find_class(string name) {
            return class_map.get(name);
        }

        public MermaidClass get_or_create_class(string name) {
            var existing = find_class(name);
            if (existing != null) {
                return existing;
            }

            var cls = new MermaidClass(name);
            add_class(cls);
            return cls;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

    // ==================== MERMAID GANTT CHART ====================

    public enum GanttTaskStatus {
        ACTIVE,
        DONE,
        CRITICAL,
        MILESTONE
    }

    public class GanttTask : Object {
        public string id { get; set; }
        public string description { get; set; }
        public GanttTaskStatus status { get; set; }
        public string? start_date { get; set; }
        public string? end_date { get; set; }
        public string? duration { get; set; }
        public string? depends_on { get; set; }
        public int source_line { get; set; }

        public GanttTask(string id, string description, int line = 0) {
            this.id = id;
            this.description = description;
            this.status = GanttTaskStatus.ACTIVE;
            this.start_date = null;
            this.end_date = null;
            this.duration = null;
            this.depends_on = null;
            this.source_line = line;
        }
    }

    public class GanttSection : Object {
        public string name { get; set; }
        public Gee.ArrayList<GanttTask> tasks { get; private set; }

        public GanttSection(string name) {
            this.name = name;
            this.tasks = new Gee.ArrayList<GanttTask>();
        }

        public void add_task(GanttTask task) {
            tasks.add(task);
        }
    }

    public class MermaidGantt : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public string? date_format { get; set; }
        public Gee.ArrayList<GanttSection> sections { get; private set; }
        public Gee.ArrayList<GanttTask> tasks { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidGantt() {
            this.diagram_type = MermaidDiagramType.GANTT;
            this.title = null;
            this.date_format = null;
            this.sections = new Gee.ArrayList<GanttSection>();
            this.tasks = new Gee.ArrayList<GanttTask>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_task(GanttTask task) {
            tasks.add(task);
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

    // ==================== MERMAID PIE CHART ====================

    public class PieSlice : Object {
        public string label { get; set; }
        public double value { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }

        public PieSlice(string label, double value, int line = 0) {
            this.label = label;
            this.value = value;
            this.color = null;
            this.source_line = line;
        }

        public double get_percentage(double total) {
            if (total == 0) return 0;
            return (value / total) * 100.0;
        }
    }

    public class MermaidPie : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public bool show_data { get; set; }
        public Gee.ArrayList<PieSlice> slices { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidPie() {
            this.diagram_type = MermaidDiagramType.PIE;
            this.title = null;
            this.show_data = false;
            this.slices = new Gee.ArrayList<PieSlice>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_slice(PieSlice slice) {
            slices.add(slice);
        }

        public double get_total() {
            double total = 0;
            foreach (var slice in slices) {
                total += slice.value;
            }
            return total;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

    // ==================== MERMAID ER DIAGRAM ====================

    public enum MermaidERCardinality {
        ZERO_OR_ONE,     // o|
        EXACTLY_ONE,     // ||
        ZERO_OR_MORE,    // o{
        ONE_OR_MORE      // |{
    }

    public class MermaidEREntity : Object {
        public string name { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<MermaidERAttribute> attributes { get; private set; }

        public MermaidEREntity(string name, int line = 0) {
            this.name = name;
            this.source_line = line;
            this.attributes = new Gee.ArrayList<MermaidERAttribute>();
        }

        public void add_attribute(MermaidERAttribute attr) {
            attributes.add(attr);
        }
    }

    public class MermaidERAttribute : Object {
        public string name { get; set; }
        public string? type_name { get; set; }
        public bool is_primary_key { get; set; }
        public bool is_foreign_key { get; set; }

        public MermaidERAttribute(string name) {
            this.name = name;
            this.type_name = null;
            this.is_primary_key = false;
            this.is_foreign_key = false;
        }
    }

    public class MermaidERRelationship : Object {
        public MermaidEREntity from { get; set; }
        public MermaidEREntity to { get; set; }
        public MermaidERCardinality from_cardinality { get; set; }
        public MermaidERCardinality to_cardinality { get; set; }
        public string? label { get; set; }

        public MermaidERRelationship(MermaidEREntity from, MermaidEREntity to) {
            this.from = from;
            this.to = to;
            this.from_cardinality = MermaidERCardinality.ZERO_OR_MORE;
            this.to_cardinality = MermaidERCardinality.ZERO_OR_MORE;
            this.label = null;
        }
    }

    public class MermaidERDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidEREntity> entities { get; private set; }
        public Gee.ArrayList<MermaidERRelationship> relationships { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }

        private Gee.HashMap<string, MermaidEREntity> entity_map;

        public MermaidERDiagram() {
            this.diagram_type = MermaidDiagramType.ER_DIAGRAM;
            this.entities = new Gee.ArrayList<MermaidEREntity>();
            this.relationships = new Gee.ArrayList<MermaidERRelationship>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.entity_map = new Gee.HashMap<string, MermaidEREntity>();
            this.title = null;
        }

        public void add_entity(MermaidEREntity entity) {
            if (!entity_map.has_key(entity.name)) {
                entities.add(entity);
                entity_map.set(entity.name, entity);
            }
        }

        public MermaidEREntity? find_entity(string name) {
            return entity_map.get(name);
        }

        public MermaidEREntity get_or_create_entity(string name) {
            var existing = find_entity(name);
            if (existing != null) {
                return existing;
            }

            var entity = new MermaidEREntity(name);
            add_entity(entity);
            return entity;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

    // ==================== MERMAID STATE DIAGRAM ====================

    public enum MermaidStateType {
        NORMAL,
        START,          // [*]
        END,            // [*]
        CHOICE,         // <<choice>>
        FORK,           // <<fork>>
        JOIN            // <<join>>
    }

    public class MermaidState : Object {
        public string id { get; set; }
        public string? description { get; set; }
        public MermaidStateType state_type { get; set; }
        public string? note { get; set; }
        public int source_line { get; set; }

        public MermaidState(string id, MermaidStateType type = MermaidStateType.NORMAL, int line = 0) {
            this.id = id;
            this.description = null;
            this.state_type = type;
            this.note = null;
            this.source_line = line;
        }
    }

    public class MermaidTransition : Object {
        public MermaidState from { get; set; }
        public MermaidState to { get; set; }
        public string? label { get; set; }

        public MermaidTransition(MermaidState from, MermaidState to) {
            this.from = from;
            this.to = to;
            this.label = null;
        }
    }

    public class MermaidStateDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidState> states { get; private set; }
        public Gee.ArrayList<MermaidTransition> transitions { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }
        public MermaidState? start_state { get; set; }
        public MermaidState? end_state { get; set; }

        private Gee.HashMap<string, MermaidState> state_map;

        public MermaidStateDiagram() {
            this.diagram_type = MermaidDiagramType.STATE;
            this.states = new Gee.ArrayList<MermaidState>();
            this.transitions = new Gee.ArrayList<MermaidTransition>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.state_map = new Gee.HashMap<string, MermaidState>();
            this.title = null;
            this.start_state = null;
            this.end_state = null;
        }

        public void add_state(MermaidState state) {
            if (!state_map.has_key(state.id)) {
                states.add(state);
                state_map.set(state.id, state);

                if (state.state_type == MermaidStateType.START) {
                    start_state = state;
                } else if (state.state_type == MermaidStateType.END) {
                    end_state = state;
                }
            }
        }

        public MermaidState? find_state(string id) {
            return state_map.get(id);
        }

        public MermaidState get_or_create_state(string id) {
            var existing = find_state(id);
            if (existing != null) {
                return existing;
            }

            var state = new MermaidState(id);
            add_state(state);
            return state;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }
}
