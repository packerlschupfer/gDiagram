namespace GDiagram {
    public enum DeploymentNodeType {
        NODE,
        DEVICE,
        ARTIFACT,
        COMPONENT,
        DATABASE,
        CLOUD,
        RECTANGLE,
        FOLDER,
        FRAME,
        STORAGE,
        QUEUE,
        STACK,
        FILE,
        CARD,
        AGENT
    }

    public class DeploymentNode : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public string? alias { get; set; }
        public DeploymentNodeType node_type { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<DeploymentNode> children { get; private set; }
        public bool is_container { get; set; default = false; }

        public DeploymentNode(string id, DeploymentNodeType type = DeploymentNodeType.NODE, int line = 0) {
            this.id = id;
            this.node_type = type;
            this.label = null;
            this.alias = null;
            this.stereotype = null;
            this.color = null;
            this.source_line = line;
            this.children = new Gee.ArrayList<DeploymentNode>();
        }

        public string get_dot_id() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
            // Sanitize id for DOT
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
                return "node_" + result;
            }
            return result;
        }

        public string get_display_label() {
            if (label != null && label.length > 0) {
                return label;
            }
            return id;
        }
    }

    public enum DeploymentConnectionType {
        ASSOCIATION,     // --
        DEPENDENCY,      // ..>
        DIRECTED,        // -->
        BIDIRECTIONAL    // <-->
    }

    public class DeploymentConnection : Object {
        public string from_id { get; set; }
        public string to_id { get; set; }
        public DeploymentConnectionType connection_type { get; set; }
        public string? label { get; set; }
        public string? protocol { get; set; }
        public bool is_dashed { get; set; default = false; }

        public DeploymentConnection(string from_id, string to_id,
                                    DeploymentConnectionType type = DeploymentConnectionType.DIRECTED) {
            this.from_id = from_id;
            this.to_id = to_id;
            this.connection_type = type;
            this.label = null;
            this.protocol = null;
        }
    }

    public class DeploymentNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
        public string position { get; set; }
        public int source_line { get; set; }

        private static int note_counter = 0;

        public DeploymentNote(string text, int line = 0) {
            this.id = "_deploy_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
            this.source_line = line;
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public class DeploymentDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<DeploymentNode> nodes { get; private set; }
        public Gee.ArrayList<DeploymentConnection> connections { get; private set; }
        public Gee.ArrayList<DeploymentNote> notes { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        // Direction
        public bool left_to_right { get; set; default = false; }

        public DeploymentDiagram() {
            this.diagram_type = DiagramType.DEPLOYMENT;
            this.nodes = new Gee.ArrayList<DeploymentNode>();
            this.connections = new Gee.ArrayList<DeploymentConnection>();
            this.notes = new Gee.ArrayList<DeploymentNote>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counters
            DeploymentNote.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public DeploymentNode? find_node(string id) {
            foreach (var node in nodes) {
                if (node.id == id || node.alias == id) {
                    return node;
                }
                // Check children
                var nested = find_nested_node(node, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        private DeploymentNode? find_nested_node(DeploymentNode parent, string id) {
            foreach (var node in parent.children) {
                if (node.id == id || node.alias == id) {
                    return node;
                }
                var nested = find_nested_node(node, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        public DeploymentNode get_or_create_node(string id, DeploymentNodeType type = DeploymentNodeType.NODE, int line = 0) {
            var existing = find_node(id);
            if (existing != null) {
                if (line > 0 && existing.source_line == 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var node = new DeploymentNode(id, type, line);
            nodes.add(node);
            return node;
        }
    }
}
