namespace GDiagram {

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
        // "left" or "right" for `note left of` / `note right of`
        public string? note_position { get; set; }
        public int source_line { get; set; }
        public string? parent_id { get; set; }  // set when this state is a sub-state of a composite state
        // Concurrent region of the parent composite: 0 before the first "--", 1 after it, ...
        public int region { get; set; default = 0; }
        // classDef names applied with "class A name" / "A:::name", and a "style A ..." line
        public Gee.ArrayList<string> css_classes { get; private set; default = new Gee.ArrayList<string>(); }
        public string? inline_style { get; set; }

        public MermaidState(string id, MermaidStateType type = MermaidStateType.NORMAL, int line = 0) {
            this.id = id;
            this.description = null;
            this.state_type = type;
            this.note = null;
            this.source_line = line;
            this.parent_id = null;
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
        // The top-level [*] markers; a composite state has its own (parent_id set)
        public MermaidState? start_state { get; set; }
        public MermaidState? end_state { get; set; }
        public FlowchartDirection direction { get; set; default = FlowchartDirection.TOP_DOWN; }

        // classDef name -> "fill:#f00,stroke:#333,color:white"
        public Gee.HashMap<string, string> class_defs { get; private set; default = new Gee.HashMap<string, string>(); }

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

                if (state.parent_id == null) {
                    if (state.state_type == MermaidStateType.START) {
                        start_state = state;
                    } else if (state.state_type == MermaidStateType.END) {
                        end_state = state;
                    }
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

        // The id of the [*] start (or end) marker of a scope (null = top level)
        public static string marker_id(string? scope, bool start) {
            string base_id = start ? "[*]_start" : "[*]_end";
            return scope == null ? base_id : base_id + "@" + scope;
        }

        // Sub-states of `scope` (null = top level)
        public Gee.ArrayList<MermaidState> children_of(string? scope) {
            var list = new Gee.ArrayList<MermaidState>();
            foreach (var s in states) {
                if (s.parent_id == scope) list.add(s);
            }
            return list;
        }

        public bool is_composite(string id) {
            foreach (var s in states) {
                if (s.parent_id == id) return true;
            }
            return false;
        }

        // True when `state` sits (at any depth) inside the composite `ancestor_id`
        public bool is_inside(MermaidState state, string ancestor_id) {
            string? p = state.parent_id;
            int guard = 0;
            while (p != null && guard++ < 1000) {
                if (p == ancestor_id) return true;
                var parent = find_state(p);
                if (parent == null) return false;
                p = parent.parent_id;
            }
            return false;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
