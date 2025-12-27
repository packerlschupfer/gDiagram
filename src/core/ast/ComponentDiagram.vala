namespace GPlantUML {
    public enum ComponentType {
        COMPONENT,    // [Name] or component keyword
        INTERFACE,    // () Name or interface keyword
        DATABASE,     // database keyword
        CLOUD,        // cloud keyword
        PACKAGE,      // package keyword
        FOLDER,       // folder keyword
        FRAME,        // frame keyword
        NODE,         // node keyword
        ARTIFACT,     // artifact keyword
        STORAGE,      // storage keyword
        CARD,         // card keyword
        AGENT,        // agent keyword
        RECTANGLE,    // rectangle keyword
        QUEUE,        // queue keyword
        STACK,        // stack keyword
        FILE,         // file keyword
        BOUNDARY,     // boundary keyword
        CONTROL,      // control keyword
        ENTITY        // entity keyword
    }

    public enum PortType {
        IN,           // portin - required interface
        OUT,          // portout - provided interface
        BIDIRECTIONAL // port - both directions
    }

    public class ComponentPort : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public PortType port_type { get; set; }
        public string? parent_component { get; set; }

        private static int port_counter = 0;

        public ComponentPort(string? id, PortType type = PortType.BIDIRECTIONAL) {
            this.id = id ?? "_port_%d".printf(port_counter++);
            this.port_type = type;
            this.label = null;
            this.parent_component = null;
        }

        public static void reset_counter() {
            port_counter = 0;
        }
    }

    public class Component : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public string? alias { get; set; }
        public ComponentType component_type { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<Component> children { get; private set; }
        public bool is_container { get; set; default = false; }

        public Component(string id, ComponentType type = ComponentType.COMPONENT, int line = 0) {
            this.id = id;
            this.component_type = type;
            this.label = null;
            this.alias = null;
            this.stereotype = null;
            this.color = null;
            this.source_line = line;
            this.children = new Gee.ArrayList<Component>();
        }

        public string get_display_label() {
            if (label != null && label.length > 0) {
                return label;
            }
            if (alias != null && alias.length > 0) {
                return alias;
            }
            return id;
        }

        public string get_identifier() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
            return id;
        }
    }

    public class ComponentInterface : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public string? alias { get; set; }
        public string? stereotype { get; set; }

        public ComponentInterface(string id) {
            this.id = id;
            this.label = null;
            this.alias = null;
            this.stereotype = null;
        }

        public string get_display_label() {
            if (label != null && label.length > 0) {
                return label;
            }
            return id;
        }

        public string get_identifier() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
            return id;
        }
    }

    public enum ComponentRelationType {
        DEPENDENCY,      // -->
        ASSOCIATION,     // --
        REALIZATION,     // ..>
        USE,             // ..
        AGGREGATION,     // o--
        COMPOSITION      // *--
    }

    public class ComponentRelationship : Object {
        public string from_id { get; set; }
        public string to_id { get; set; }
        public ComponentRelationType relation_type { get; set; }
        public string? label { get; set; }
        public string? color { get; set; }
        public bool is_dashed { get; set; default = false; }
        public bool left_arrow { get; set; default = false; }
        public bool right_arrow { get; set; default = true; }

        public ComponentRelationship(string from, string to, ComponentRelationType type = ComponentRelationType.DEPENDENCY) {
            this.from_id = from;
            this.to_id = to;
            this.relation_type = type;
            this.label = null;
            this.color = null;
        }
    }

    public class ComponentNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
        public string position { get; set; }

        private static int note_counter = 0;

        public ComponentNote(string text) {
            this.id = "_component_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public class ComponentDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<Component> components { get; private set; }
        public Gee.ArrayList<ComponentInterface> interfaces { get; private set; }
        public Gee.ArrayList<ComponentPort> ports { get; private set; }
        public Gee.ArrayList<ComponentRelationship> relationships { get; private set; }
        public Gee.ArrayList<ComponentNote> notes { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        // Direction
        public bool left_to_right { get; set; default = false; }

        public ComponentDiagram() {
            this.diagram_type = DiagramType.COMPONENT;
            this.components = new Gee.ArrayList<Component>();
            this.interfaces = new Gee.ArrayList<ComponentInterface>();
            this.ports = new Gee.ArrayList<ComponentPort>();
            this.relationships = new Gee.ArrayList<ComponentRelationship>();
            this.notes = new Gee.ArrayList<ComponentNote>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();

            // Reset counters for new diagram
            ComponentNote.reset_counter();
            ComponentPort.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public Component? find_component(string id) {
            foreach (var comp in components) {
                if (comp.id == id || comp.alias == id) {
                    return comp;
                }
                // Check children
                var nested = find_nested_component(comp, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        private Component? find_nested_component(Component parent, string id) {
            foreach (var comp in parent.children) {
                if (comp.id == id || comp.alias == id) {
                    return comp;
                }
                var nested = find_nested_component(comp, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        public ComponentInterface? find_interface(string id) {
            foreach (var iface in interfaces) {
                if (iface.id == id || iface.alias == id) {
                    return iface;
                }
            }
            return null;
        }

        public Component get_or_create_component(string id, ComponentType type = ComponentType.COMPONENT, int line = 0) {
            var existing = find_component(id);
            if (existing != null) {
                // Update line if this is a better definition
                if (line > 0 && existing.source_line == 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var comp = new Component(id, type, line);
            components.add(comp);
            return comp;
        }
    }
}
