namespace GDiagram {

    // ==================== Block Diagram ====================

    public class BlockNode : Object {
        public string id { get; set; }
        public string label { get; set; }
        public string? group_id { get; set; }   // null if top-level, else parent group id
        public bool is_group { get; set; default = false; }
        public int col_span { get; set; default = 1; }
        public int source_line { get; set; }

        public BlockNode(string id, string label, int line = 0) {
            this.id = id;
            this.label = label;
            this.source_line = line;
        }
    }

    public class BlockEdge : Object {
        public string source { get; set; }
        public string target { get; set; }
        public string? label { get; set; }
        public int source_line { get; set; }

        public BlockEdge(string source, string target, string? label = null, int line = 0) {
            this.source = source;
            this.target = target;
            this.label = label;
            this.source_line = line;
        }
    }

    public class MermaidBlock : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public int columns { get; set; default = 0; }
        public Gee.ArrayList<BlockNode> nodes { get; private set; }
        public Gee.ArrayList<BlockEdge> edges { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidBlock() {
            this.diagram_type = MermaidDiagramType.BLOCK;
            this.nodes = new Gee.ArrayList<BlockNode>();
            this.edges = new Gee.ArrayList<BlockEdge>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_node(BlockNode n) { nodes.add(n); }
        public void add_edge(BlockEdge e) { edges.add(e); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return nodes.size == 0; }
    }

}
