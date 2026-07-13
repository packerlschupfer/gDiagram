namespace GDiagram {

    // ==================== Block Diagram ====================

    public class BlockNode : Object {
        public string id { get; set; }
        public string label { get; set; }
        public string? group_id { get; set; }   // null if top-level, else parent group id
        public bool is_group { get; set; default = false; }
        public int col_span { get; set; default = 1; }
        // "square", "round", "stadium", "subroutine", "cylinder", "circle",
        // "doublecircle", "rect_left_inv_arrow", "diamond", "hexagon", "lean_right",
        // "lean_left", "trapezoid", "inv_trapezoid", "block_arrow"; "space" for a gap
        public string shape { get; set; default = "square"; }
        public bool is_space { get; set; default = false; }
        // Groups: "columns N" inside them; -1 = all children on one row
        public int columns { get; set; default = -1; }
        // Block arrows: "right", "left", "up", "down", "x", "y"
        public string arrow_direction { get; set; default = "right"; }
        // "style id ..." declarations, comma-separated CSS ("fill:#f96,stroke:#333")
        public string? styles { get; set; }
        // "class id name" assignments, space-separated class names
        public string? css_classes { get; set; }
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
        // "arrow_point", "arrow_cross", "arrow_circle" or "" (none) at the target end
        public string arrow_end { get; set; default = "arrow_point"; }
        public bool thick { get; set; default = false; }
        public bool dotted { get; set; default = false; }
        public bool invisible { get; set; default = false; }
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
        public int columns { get; set; default = 0; }   // top-level "columns N"; 0 = not set
        public Gee.ArrayList<BlockNode> nodes { get; private set; }
        public Gee.ArrayList<BlockEdge> edges { get; private set; }
        // classDef name -> CSS
        public Gee.HashMap<string, string> class_defs { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        // id -> the FIRST node added under it, mirroring the linear scan find_node
        // used to do. The parser calls find_node once per block reference and the
        // renderer twice per edge, so the scan made parsing quadratic in the node
        // count: 4000 blocks took ~0.9 s on the per-keystroke parse path.
        private Gee.HashMap<string, BlockNode> by_id;

        public MermaidBlock() {
            this.diagram_type = MermaidDiagramType.BLOCK;
            this.nodes = new Gee.ArrayList<BlockNode>();
            this.edges = new Gee.ArrayList<BlockEdge>();
            this.class_defs = new Gee.HashMap<string, string>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.by_id = new Gee.HashMap<string, BlockNode>();
        }

        public void add_node(BlockNode n) {
            nodes.add(n);
            // A repeated id keeps the first node: a `space` filler and a group can
            // carry the same id as a block, and find_node returning the earlier one
            // is what decides which of them a later reference updates.
            if (!by_id.has_key(n.id)) by_id.set(n.id, n);
        }
        public void add_edge(BlockEdge e) { edges.add(e); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return nodes.size == 0; }

        public BlockNode? find_node(string id) {
            return by_id.get(id);
        }
    }

}
