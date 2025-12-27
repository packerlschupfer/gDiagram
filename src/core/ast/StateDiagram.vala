namespace GPlantUML {
    public enum StateType {
        INITIAL,      // [*] as source
        FINAL,        // [*] as target
        SIMPLE,       // Regular state
        COMPOSITE,    // State with nested states
        CHOICE,       // <<choice>> - diamond decision point
        FORK,         // <<fork>> - horizontal bar for parallel split
        JOIN,         // <<join>> - horizontal bar for parallel join
        END_STATE,    // <<end>> - termination point
        HISTORY,      // [H] - shallow history
        DEEP_HISTORY, // [H*] - deep history
        ENTRY_POINT,  // <<entryPoint>>
        EXIT_POINT    // <<exitPoint>>
    }

    public class State : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public StateType state_type { get; set; }
        public string? description { get; set; }
        public string? stereotype { get; set; }        // <<choice>>, <<fork>>, etc.
        public string? entry_action { get; set; }      // entry / action
        public string? exit_action { get; set; }       // exit / action
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<State> nested_states { get; private set; }
        public Gee.ArrayList<StateTransition> nested_transitions { get; private set; }

        private static int initial_counter = 0;
        private static int final_counter = 0;
        private static int choice_counter = 0;
        private static int fork_counter = 0;
        private static int join_counter = 0;
        private static int history_counter = 0;

        public State(string id, StateType type = StateType.SIMPLE, int line = 0) {
            this.id = id;
            this.state_type = type;
            this.label = null;
            this.description = null;
            this.stereotype = null;
            this.entry_action = null;
            this.exit_action = null;
            this.color = null;
            this.source_line = line;
            this.nested_states = new Gee.ArrayList<State>();
            this.nested_transitions = new Gee.ArrayList<StateTransition>();
        }

        public static State create_initial(int line = 0) {
            var state = new State("_initial_%d".printf(initial_counter++), StateType.INITIAL, line);
            return state;
        }

        public static State create_final(int line = 0) {
            var state = new State("_final_%d".printf(final_counter++), StateType.FINAL, line);
            return state;
        }

        public static State create_choice(string? name = null, int line = 0) {
            string id = name ?? "_choice_%d".printf(choice_counter++);
            var state = new State(id, StateType.CHOICE, line);
            state.stereotype = "choice";
            return state;
        }

        public static State create_fork(string? name = null, int line = 0) {
            string id = name ?? "_fork_%d".printf(fork_counter++);
            var state = new State(id, StateType.FORK, line);
            state.stereotype = "fork";
            return state;
        }

        public static State create_join(string? name = null, int line = 0) {
            string id = name ?? "_join_%d".printf(join_counter++);
            var state = new State(id, StateType.JOIN, line);
            state.stereotype = "join";
            return state;
        }

        public static State create_history(bool deep = false, int line = 0) {
            var state = new State("_history_%d".printf(history_counter++),
                                  deep ? StateType.DEEP_HISTORY : StateType.HISTORY, line);
            return state;
        }

        public static void reset_counters() {
            initial_counter = 0;
            final_counter = 0;
            choice_counter = 0;
            fork_counter = 0;
            join_counter = 0;
            history_counter = 0;
        }

        public string get_display_label() {
            if (label != null && label.length > 0) {
                return label;
            }
            return id;
        }

        public bool is_composite() {
            return nested_states.size > 0;
        }
    }

    public class StateTransition : Object {
        public State from { get; set; }
        public State to { get; set; }
        public string? label { get; set; }     // event/trigger
        public string? guard { get; set; }      // [condition]
        public string? action { get; set; }     // / action
        public string? color { get; set; }
        public bool is_dashed { get; set; }

        public StateTransition(State from, State to) {
            this.from = from;
            this.to = to;
            this.label = null;
            this.guard = null;
            this.action = null;
            this.color = null;
            this.is_dashed = false;
        }

        public string get_full_label() {
            var sb = new StringBuilder();

            if (label != null && label.length > 0) {
                sb.append(label);
            }

            if (guard != null && guard.length > 0) {
                sb.append(" [");
                sb.append(guard);
                sb.append("]");
            }

            if (action != null && action.length > 0) {
                sb.append(" / ");
                sb.append(action);
            }

            return sb.str;
        }
    }

    public class StateNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }  // State ID this note is attached to
        public string position { get; set; }       // left, right, top, bottom

        private static int note_counter = 0;

        public StateNote(string text) {
            this.id = "_state_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public class StateDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<State> states { get; private set; }
        public Gee.ArrayList<StateTransition> transitions { get; private set; }
        public Gee.ArrayList<StateNote> notes { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        // Hide empty description
        public bool hide_empty_description { get; set; default = false; }

        public StateDiagram() {
            this.diagram_type = DiagramType.STATE;
            this.states = new Gee.ArrayList<State>();
            this.transitions = new Gee.ArrayList<StateTransition>();
            this.notes = new Gee.ArrayList<StateNote>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();

            // Reset counters for new diagram
            State.reset_counters();
            StateNote.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public State? find_state(string id) {
            foreach (var state in states) {
                if (state.id == id) {
                    return state;
                }
                // Check nested states
                var nested = find_nested_state(state, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        private State? find_nested_state(State parent, string id) {
            foreach (var state in parent.nested_states) {
                if (state.id == id) {
                    return state;
                }
                var nested = find_nested_state(state, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        public State get_or_create_state(string id, int line = 0) {
            var existing = find_state(id);
            if (existing != null) {
                // Update line if this is a better definition
                if (line > 0 && existing.source_line == 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var state = new State(id, StateType.SIMPLE, line);
            states.add(state);
            return state;
        }

        public void add_transition(State from, State to, string? label = null) {
            var transition = new StateTransition(from, to);
            transition.label = label;
            transitions.add(transition);
        }
    }
}
