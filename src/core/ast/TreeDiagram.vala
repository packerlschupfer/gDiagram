/* TreeDiagram.vala — AST for PlantUML tree structure (@starttree) */
namespace GDiagram {

public class TreeNode : Object {
    public string id { get; set; }
    public string text { get; set; }
    public int depth { get; set; }
    public int source_line { get; set; }
    public Gee.ArrayList<TreeNode> children { get; private set; }

    private static int counter = 0;

    public TreeNode(string text, int depth, int line = 0) {
        this.id = "tree_%d".printf(counter++);
        this.text = text;
        this.depth = depth;
        this.source_line = line;
        this.children = new Gee.ArrayList<TreeNode>();
    }

    public static void reset_counter() {
        counter = 0;
    }

    public void add_child(TreeNode child) {
        children.add(child);
    }
}

public class TreeDiagram : Object {
    public TreeNode? root { get; set; default = null; }
    public string? title { get; set; default = null; }

    public TreeDiagram() {
        TreeNode.reset_counter();
    }

    public Gee.ArrayList<TreeNode> get_all_nodes() {
        var nodes = new Gee.ArrayList<TreeNode>();
        if (root != null) {
            collect_nodes(root, nodes);
        }
        return nodes;
    }

    private void collect_nodes(TreeNode node, Gee.ArrayList<TreeNode> list) {
        list.add(node);
        foreach (var child in node.children) {
            collect_nodes(child, list);
        }
    }
}

}
