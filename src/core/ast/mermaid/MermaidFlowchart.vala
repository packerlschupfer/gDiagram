namespace GDiagram {

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

}
