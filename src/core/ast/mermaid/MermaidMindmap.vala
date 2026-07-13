namespace GDiagram {

    // ==================== Mindmap ====================

    public class MindmapNode : Object {
        public string id { get; set; }
        public string label { get; set; }
        public string shape { get; set; }  // "rectangle", "rounded", "circle", "hexagon", "cloud", "bang", "default"
        public int depth { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<MindmapNode> children { get; private set; }

        public MindmapNode(string label, string shape = "default", int depth = 0, int line = 0) {
            // Build a safe ID from label
            var sb = new StringBuilder();
            foreach (char c in label.to_utf8()) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_') {
                    sb.append_c(c);
                } else {
                    sb.append_c('_');
                }
            }
            this.id = sb.str;
            this.label = label;
            this.shape = shape;
            this.depth = depth;
            this.source_line = line;
            this.children = new Gee.ArrayList<MindmapNode>();
        }

        public void add_child(MindmapNode child) { children.add(child); }
    }

    public class MermaidMindmap : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public MindmapNode? root { get; set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidMindmap() {
            this.diagram_type = MermaidDiagramType.MINDMAP;
            this.title = null;
            this.root = null;
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return root == null; }
    }

}
