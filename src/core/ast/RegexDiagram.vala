/* RegexDiagram.vala — AST for PlantUML @startregex regex visualization */
namespace GDiagram {

public enum RegexNodeType {
    LITERAL,
    CHAR_CLASS,
    DOT,           // . matches any
    GROUP,
    ALTERNATION,
    QUANTIFIER,
    ANCHOR,
    SEQUENCE
}

public class RegexNode : Object {
    public RegexNodeType node_type { get; set; }
    public string text { get; set; default = ""; }
    // For QUANTIFIER
    public int min_count { get; set; default = 0; }
    public int max_count { get; set; default = -1; }  // -1 = unlimited
    public bool greedy { get; set; default = true; }
    // Children (for GROUP, ALTERNATION, SEQUENCE, QUANTIFIER)
    public Gee.ArrayList<RegexNode> children { get; private set; }

    public RegexNode(RegexNodeType t, string text = "") {
        this.node_type = t;
        this.text = text;
        this.children = new Gee.ArrayList<RegexNode>();
    }

    public RegexNode.literal(string ch) {
        this(RegexNodeType.LITERAL, ch);
    }

    public RegexNode.char_class(string cls) {
        this(RegexNodeType.CHAR_CLASS, cls);
    }

    public RegexNode.dot() {
        this(RegexNodeType.DOT, ".");
    }

    public RegexNode.anchor(string a) {
        this(RegexNodeType.ANCHOR, a);
    }
}

public class RegexDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public string pattern { get; set; default = ""; }
    public RegexNode root { get; set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public RegexDiagram() {
        this.diagram_type = DiagramType.REGEX_DIAGRAM;
        this.root = new RegexNode(RegexNodeType.SEQUENCE);
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return root.children.size == 0 && root.text.length == 0; }
}

}
