/* MermaidRailroad.vala — AST for Mermaid railroad diagrams (railroad-beta and
 * its EBNF / ABNF / PEG grammar front ends).
 *
 * Mermaid 12.2.0 ships four separate Langium grammars (RailroadGrammar,
 * RailroadEbnfGrammar, RailroadAbnfGrammar, RailroadPegGrammar) whose parsers
 * all transform into ONE node vocabulary and feed ONE railroadDb consumed by
 * ONE railroadRenderer.  This file mirrors that node vocabulary exactly, so the
 * four flavours share a single AST, a single renderer and a single DiagramType;
 * `grammar` only records which front end read the source.
 */
namespace GDiagram {

/** Which input grammar produced the rules — the drawing is identical. */
public enum MermaidRailroadGrammar {
    NATIVE,   // railroad-beta         sequence(...) / choice(...) / optional(...)
    EBNF,     // railroad-ebnf-beta    a = "x" | b, { c };
    ABNF,     // railroad-abnf-beta    a = "x" / 1*b;
    PEG;      // railroad-peg-beta     a <- "x" / b+;

    public string keyword() {
        switch (this) {
            case EBNF: return "railroad-ebnf-beta";
            case ABNF: return "railroad-abnf-beta";
            case PEG:  return "railroad-peg-beta";
            default:   return "railroad-beta";
        }
    }

    public string display_name() {
        switch (this) {
            case EBNF: return "EBNF";
            case ABNF: return "ABNF";
            case PEG:  return "PEG";
            default:   return "native";
        }
    }
}

/** Mermaid's railroadTypes.ts ASTNode union. */
public enum MermaidRailroadNodeType {
    TERMINAL,      // literal text        -> rounded box
    NONTERMINAL,   // rule reference      -> square box
    SPECIAL,       // "? text ?"          -> square box
    SEQUENCE,      // children in a row
    CHOICE,        // children stacked
    OPTIONAL,      // child with a bypass above
    REPETITION     // child with a loop below; min 0 also gets a bypass
}

public class MermaidRailroadNode : Object {
    public MermaidRailroadNodeType node_type { get; set; }
    /** terminal value, nonterminal name or special text; empty for containers. */
    public string text { get; set; default = ""; }
    /** REPETITION only: 0 for `*`, 1 for `+`, n for ABNF `n*m`. */
    public int min { get; set; default = 0; }
    /** REPETITION only: -1 means Infinity (mermaid's renderer ignores max). */
    public int max { get; set; default = -1; }
    public Gee.ArrayList<MermaidRailroadNode> children { get; private set; }

    public MermaidRailroadNode(MermaidRailroadNodeType t, string text = "") {
        this.node_type = t;
        this.text = text;
        this.children = new Gee.ArrayList<MermaidRailroadNode>();
    }

    public MermaidRailroadNode.terminal(string value) {
        this(MermaidRailroadNodeType.TERMINAL, value);
    }

    public MermaidRailroadNode.nonterminal(string name) {
        this(MermaidRailroadNodeType.NONTERMINAL, name);
    }

    public MermaidRailroadNode.special(string text) {
        this(MermaidRailroadNodeType.SPECIAL, text);
    }

    public MermaidRailroadNode.optional(MermaidRailroadNode inner) {
        this(MermaidRailroadNodeType.OPTIONAL);
        this.children.add(inner);
    }

    public MermaidRailroadNode.repetition(MermaidRailroadNode inner, int min, int max) {
        this(MermaidRailroadNodeType.REPETITION);
        this.min = min;
        this.max = max;
        this.children.add(inner);
    }

    public void add_child(MermaidRailroadNode c) { children.add(c); }

    /**
     * Mermaid collapses a one-element sequence/choice into that element
     * (`elements.length === 1 ? elements[0] : {...}`); the parsers call this so
     * the AST matches node for node.
     */
    public static MermaidRailroadNode collapse(MermaidRailroadNodeType t,
                                               Gee.ArrayList<MermaidRailroadNode> items) {
        if (items.size == 1) return items.get(0);
        var n = new MermaidRailroadNode(t);
        foreach (var i in items) n.children.add(i);
        return n;
    }

    /** PEG lookahead label: mermaid's nodeToLabel(). */
    public string to_label() {
        switch (node_type) {
            case MermaidRailroadNodeType.TERMINAL:    return "\"%s\"".printf(text);
            case MermaidRailroadNodeType.NONTERMINAL: return text;
            case MermaidRailroadNodeType.SPECIAL:     return text;
            default:                                  return "(...)";
        }
    }
}

public class MermaidRailroadRule : Object {
    public string name { get; set; }
    public MermaidRailroadNode definition { get; set; }
    public int source_line { get; set; default = 0; }

    public MermaidRailroadRule(string name, MermaidRailroadNode definition, int line = 0) {
        this.name = name;
        this.definition = definition;
        this.source_line = line;
    }
}

public class MermaidRailroad : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public MermaidRailroadGrammar grammar { get; set; default = MermaidRailroadGrammar.NATIVE; }
    public string? title { get; set; default = null; }
    public string? acc_title { get; set; default = null; }
    public string? acc_descr { get; set; default = null; }
    public Gee.ArrayList<MermaidRailroadRule> rules { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidRailroad() {
        this.diagram_type = MermaidDiagramType.RAILROAD;
        this.rules = new Gee.ArrayList<MermaidRailroadRule>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    /** Mermaid warns and overwrites on a duplicate rule name; it keeps both in `rules`. */
    public void add_rule(MermaidRailroadRule r) { rules.add(r); }

    public MermaidRailroadRule? find_rule(string name) {
        foreach (var r in rules) {
            if (r.name == name) return r;
        }
        return null;
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return rules.size == 0; }
}

}
