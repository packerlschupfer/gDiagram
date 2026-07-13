/* MermaidTreeView.vala — AST for Mermaid `treeView-beta` (file/directory trees)
 *
 * Mirrors mermaid 12.2.0's treeView db.ts: a synthetic root (name "/",
 * level -1, directory) always exists and is drawn, and every parsed node hangs
 * off it. `level` is the raw indentation *character* count, not a depth — the
 * db only ever compares levels, so any consistent indent width works.
 */
namespace GDiagram {

public enum TreeViewNodeType {
    FILE,
    DIRECTORY
}

public class TreeViewNode : Object {
    /** Node name with the directory-marking trailing "/" already stripped. */
    public string name { get; set; }
    public TreeViewNodeType node_type { get; set; }
    /** Indentation character count of the source line (-1 for the synthetic root). */
    public int level { get; set; }
    /** `:::className` annotation, null when absent. */
    public string? css_class { get; set; default = null; }
    /**
     * `icon(name)` annotation: null without an annotation, "none" for a bare
     * `icon()` (mermaid's "suppress the icon" spelling).
     */
    public string? icon { get; set; default = null; }
    /** `## description` annotation, null when absent. */
    public string? description { get; set; default = null; }
    public int source_line { get; set; }
    public Gee.ArrayList<TreeViewNode> children { get; private set; }

    public TreeViewNode(string name, TreeViewNodeType node_type, int level, int line = 0) {
        this.name = name;
        this.node_type = node_type;
        this.level = level;
        this.source_line = line;
        this.children = new Gee.ArrayList<TreeViewNode>();
    }

    public void add_child(TreeViewNode child) { children.add(child); }

    public bool is_directory() { return node_type == TreeViewNodeType.DIRECTORY; }

    /** This node plus every descendant. */
    public int subtree_count() {
        int n = 1;
        foreach (var c in children) n += c.subtree_count();
        return n;
    }

    /** Whether any node in this subtree carries a `:::highlight` class. */
    public bool has_class(string wanted) {
        if (css_class != null) {
            foreach (string part in css_class.split(" ")) {
                if (part == wanted) return true;
            }
        }
        return false;
    }
}

public class MermaidTreeView : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    /** `title ...` — parsed and reported, but mermaid's renderer does not draw it. */
    public string? title { get; set; }
    public string? acc_title { get; set; }
    public string? acc_descr { get; set; }
    /** The synthetic "/" root; always present, always drawn. */
    public TreeViewNode root { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidTreeView() {
        this.diagram_type = MermaidDiagramType.TREE_VIEW;
        this.title = null;
        this.root = new TreeViewNode("/", TreeViewNodeType.DIRECTORY, -1, 0);
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    /** Empty = nothing but the synthetic root. */
    public bool is_empty() { return root.children.size == 0; }
    /** Node count excluding the synthetic root. */
    public int node_count() { return root.subtree_count() - 1; }
}

}
