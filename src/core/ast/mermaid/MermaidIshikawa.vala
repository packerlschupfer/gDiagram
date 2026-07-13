/* MermaidIshikawa.vala — AST for Mermaid `ishikawa` / `ishikawa-beta`
 * (fishbone / cause-and-effect diagrams)
 *
 * Mirrors mermaid 12.2.0's ishikawaDb.ts: the first statement is the effect
 * (the fish head, which also becomes the diagram title), every later statement
 * is a cause whose nesting comes from its indentation relative to the *first*
 * cause's indentation (`baseLevel`), not relative to the effect line.
 */
namespace GDiagram {

public class IshikawaNode : Object {
    public string text { get; set; }
    /** Level as the db computed it: 0 for the effect, >= 1 for causes. */
    public int level { get; set; }
    public int source_line { get; set; }
    public Gee.ArrayList<IshikawaNode> children { get; private set; }

    public IshikawaNode(string text, int level = 0, int line = 0) {
        this.text = text;
        this.level = level;
        this.source_line = line;
        this.children = new Gee.ArrayList<IshikawaNode>();
    }

    public void add_child(IshikawaNode child) { children.add(child); }

    /** Descendants of this node, not counting itself (mermaid's countDescendants). */
    public int descendant_count() {
        int n = 0;
        foreach (var c in children) n += 1 + c.descendant_count();
        return n;
    }
}

public class MermaidIshikawa : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    /** The effect node (fish head); null when the diagram has no statements. */
    public IshikawaNode? root { get; set; }
    /** mermaid's db sets the diagram title to the effect text. */
    public string? title { get { return root != null ? root.text : null; } }
    public string? acc_title { get; set; }
    public string? acc_descr { get; set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidIshikawa() {
        this.diagram_type = MermaidDiagramType.ISHIKAWA;
        this.root = null;
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    /** A bare `ishikawa` keyword with no body: mermaid draws nothing at all. */
    public bool is_empty() { return root == null; }

    /** The top-level causes (the main bones). */
    public Gee.ArrayList<IshikawaNode> causes() {
        return root != null ? root.children : new Gee.ArrayList<IshikawaNode>();
    }

    /** Every node including the effect. */
    public int node_count() {
        return root == null ? 0 : 1 + root.descendant_count();
    }
}

}
