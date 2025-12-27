namespace GDiagram {
    public enum MindMapNodeStyle {
        DEFAULT,      // plain text
        BOX,          // [text]
        ROUNDED,      // (text)
        CLOUD,        // {{text}}
        PILL,         // ((text))
    }

    public enum MindMapSide {
        RIGHT,
        LEFT,
        AUTO
    }

    public class MindMapNode : Object {
        public string id { get; set; }
        public string text { get; set; }
        public int level { get; set; }
        public MindMapNodeStyle style { get; set; default = MindMapNodeStyle.DEFAULT; }
        public MindMapSide side { get; set; default = MindMapSide.AUTO; }
        public string? color { get; set; }
        public string? icon { get; set; }
        public int source_line { get; set; }
        public MindMapNode? parent { get; set; }
        public Gee.ArrayList<MindMapNode> children { get; private set; }

        private static int node_counter = 0;

        public MindMapNode(string text, int level = 0, int line = 0) {
            this.id = "_mm_node_%d".printf(node_counter++);
            this.text = text;
            this.level = level;
            this.color = null;
            this.icon = null;
            this.source_line = line;
            this.parent = null;
            this.children = new Gee.ArrayList<MindMapNode>();
        }

        public static void reset_counter() {
            node_counter = 0;
        }

        public string get_dot_id() {
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
                return "mmnode_" + result;
            }
            return result;
        }

        public void add_child(MindMapNode child) {
            child.parent = this;
            children.add(child);
        }
    }

    public class MindMapDiagram : Object {
        public DiagramType diagram_type { get; set; }  // MINDMAP or WBS
        public MindMapNode? root { get; set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        // Layout options
        public bool left_to_right { get; set; default = false; }

        public MindMapDiagram(DiagramType type = DiagramType.MINDMAP) {
            this.diagram_type = type;
            this.root = null;
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counter
            MindMapNode.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public int get_node_count() {
            if (root == null) return 0;
            return count_nodes(root);
        }

        private int count_nodes(MindMapNode node) {
            int count = 1;
            foreach (var child in node.children) {
                count += count_nodes(child);
            }
            return count;
        }

        public Gee.ArrayList<MindMapNode> get_all_nodes() {
            var nodes = new Gee.ArrayList<MindMapNode>();
            if (root != null) {
                collect_nodes(root, nodes);
            }
            return nodes;
        }

        private void collect_nodes(MindMapNode node, Gee.ArrayList<MindMapNode> nodes) {
            nodes.add(node);
            foreach (var child in node.children) {
                collect_nodes(child, nodes);
            }
        }
    }
}
