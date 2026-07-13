/* EbnfDiagram.vala — AST for PlantUML @startebnf grammar railroad diagrams */
namespace GDiagram {

public enum EbnfExprType {
    SEQUENCE,
    ALTERNATION,
    REPETITION,
    OPTIONAL,
    TERMINAL,
    NONTERMINAL,
    SPECIAL,
    GROUP
}

public class EbnfExpr : Object {
    public EbnfExprType expr_type { get; set; }
    public string text { get; set; default = ""; }
    public Gee.ArrayList<EbnfExpr> children { get; private set; }

    public EbnfExpr(EbnfExprType t, string text = "") {
        this.expr_type = t;
        this.text = text;
        this.children = new Gee.ArrayList<EbnfExpr>();
    }

    public EbnfExpr.terminal(string text) {
        this(EbnfExprType.TERMINAL, text);
    }

    public EbnfExpr.nonterminal(string name) {
        this(EbnfExprType.NONTERMINAL, name);
    }
}

public class EbnfRule : Object {
    public string name { get; set; }
    public EbnfExpr body { get; set; }
    public int source_line { get; set; default = 0; }

    public EbnfRule(string name, EbnfExpr body, int line = 0) {
        this.name = name;
        this.body = body;
        this.source_line = line;
    }
}

public class EbnfDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<EbnfRule> rules { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public EbnfDiagram() {
        this.diagram_type = DiagramType.EBNF;
        this.rules = new Gee.ArrayList<EbnfRule>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return rules.size == 0; }
}

}
