namespace GDiagram {

// ==================== Treemap ====================

public class TreemapNode : Object {
    public string label { get; set; }
    public double value { get; set; }  // 0 if branch node
    public bool is_leaf { get; set; }
    public int depth { get; set; }
    public Gee.ArrayList<TreemapNode> children { get; private set; }
    public int source_line { get; set; }

    public TreemapNode(string label, double value, bool is_leaf, int depth, int line = 0) {
        this.label = label;
        this.value = value;
        this.is_leaf = is_leaf;
        this.depth = depth;
        this.children = new Gee.ArrayList<TreemapNode>();
        this.source_line = line;
    }

    public void add_child(TreemapNode child) { children.add(child); }

    // Total value of subtree
    public double total_value() {
        if (is_leaf) return value;
        double sum = 0.0;
        foreach (var child in children) sum += child.total_value();
        return sum;
    }
}

public class MermaidTreemap : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<TreemapNode> roots { get; private set; }  // top-level nodes
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidTreemap() {
        this.diagram_type = MermaidDiagramType.TREEMAP;
        this.title = null;
        this.roots = new Gee.ArrayList<TreemapNode>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return roots.size == 0; }
}

}
