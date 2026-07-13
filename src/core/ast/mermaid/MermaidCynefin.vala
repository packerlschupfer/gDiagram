/* MermaidCynefin.vala — AST for Mermaid's `cynefin-beta` diagram
 *
 * Grammar, from mermaid 12.2.0's langium grammar
 * (@mermaid-js/parser src/language/generated/grammar.ts, `CynefinGrammar`):
 *
 *     Cynefin:     NEWLINE* ('cynefin-beta' | 'cynefin-beta:') NEWLINE*
 *                  ( TitleAndAccessibilities | domains+=DomainBlock
 *                  | transitions+=Transition | NEWLINE )*
 *     DomainBlock: domain=DOMAIN_NAME NEWLINE* (items+=DomainItem NEWLINE*)*
 *     DomainItem:  label=STRING
 *     Transition:  from=DOMAIN_NAME '-->' to=DOMAIN_NAME (':' label=STRING)? EOL
 *     DOMAIN_NAME: 'complex' | 'complicated' | 'clear' | 'chaotic' | 'confusion'
 *     STRING:      "..." | '...'
 *
 * Note that domain items and transition labels MUST be quoted — the grammar has
 * no bare-word alternative for either.
 */
namespace GDiagram {

/** One of the five Cynefin domains. The grammar admits no others. */
public enum CynefinDomainName {
    COMPLEX,
    COMPLICATED,
    CLEAR,
    CHAOTIC,
    CONFUSION;

    public string id() {
        switch (this) {
            case COMPLEX:     return "complex";
            case COMPLICATED: return "complicated";
            case CLEAR:       return "clear";
            case CHAOTIC:     return "chaotic";
            default:          return "confusion";
        }
    }

    /** The capitalised label mermaid's renderer draws for the domain. */
    public string label() {
        switch (this) {
            case COMPLEX:     return "Complex";
            case COMPLICATED: return "Complicated";
            case CLEAR:       return "Clear";
            case CHAOTIC:     return "Chaotic";
            default:          return "Confusion";
        }
    }

    /** DOMAIN_META[x].model in cynefinRenderer.ts (empty for confusion). */
    public string decision_model() {
        switch (this) {
            case COMPLEX:     return "Probe → Sense → Respond";
            case COMPLICATED: return "Sense → Analyse → Respond";
            case CLEAR:       return "Sense → Categorise → Respond";
            case CHAOTIC:     return "Act → Sense → Respond";
            default:          return "";
        }
    }

    /** DOMAIN_META[x].practice in cynefinRenderer.ts. */
    public string practice() {
        switch (this) {
            case COMPLEX:     return "Emergent Practices";
            case COMPLICATED: return "Good Practices";
            case CLEAR:       return "Best Practices";
            case CHAOTIC:     return "Novel Practices";
            default:          return "Disorder";
        }
    }

    public static bool try_parse(string word, out CynefinDomainName name) {
        switch (word) {
            case "complex":     name = COMPLEX;     return true;
            case "complicated": name = COMPLICATED; return true;
            case "clear":       name = CLEAR;       return true;
            case "chaotic":     name = CHAOTIC;     return true;
            case "confusion":   name = CONFUSION;   return true;
            default:            name = COMPLEX;     return false;
        }
    }
}

public class CynefinItem : Object {
    public string label { get; set; }
    public int source_line { get; set; }

    public CynefinItem(string label, int line = 0) {
        this.label = label;
        this.source_line = line;
    }
}

public class CynefinDomain : Object {
    public CynefinDomainName name { get; set; }
    public Gee.ArrayList<CynefinItem> items { get; private set; }
    public int source_line { get; set; }

    public CynefinDomain(CynefinDomainName name, int line = 0) {
        this.name = name;
        this.items = new Gee.ArrayList<CynefinItem>();
        this.source_line = line;
    }
}

public class CynefinTransition : Object {
    public CynefinDomainName from_domain { get; set; }
    public CynefinDomainName to_domain { get; set; }
    public string? label { get; set; }
    public int source_line { get; set; }

    public CynefinTransition(CynefinDomainName from_domain, CynefinDomainName to_domain,
                             string? label = null, int line = 0) {
        this.from_domain = from_domain;
        this.to_domain = to_domain;
        this.label = label;
        this.source_line = line;
    }
}

public class MermaidCynefin : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public bool declared { get; set; default = false; }
    public string? title { get; set; }
    public string? acc_title { get; set; }
    public string? acc_descr { get; set; }
    // Declaration order, as mermaid's Map<DomainName, CynefinDomain> keeps it.
    public Gee.ArrayList<CynefinDomain> domains { get; private set; }
    public Gee.ArrayList<CynefinTransition> transitions { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidCynefin() {
        this.diagram_type = MermaidDiagramType.CYNEFIN;
        this.title = null;
        this.domains = new Gee.ArrayList<CynefinDomain>();
        this.transitions = new Gee.ArrayList<CynefinTransition>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    /** The declared block for `name`, or null. A later block of the same name merges into the first. */
    public CynefinDomain? find_domain(CynefinDomainName name) {
        foreach (var d in domains) {
            if (d.name == name) return d;
        }
        return null;
    }

    public int item_count() {
        int n = 0;
        foreach (var d in domains) n += d.items.size;
        return n;
    }

    public bool has_errors() { return errors.size > 0; }

    // The grid of four domains is always drawn, so a bare `cynefin-beta` is a
    // valid (if empty-looking) diagram; only a missing header makes it empty.
    public bool is_empty() { return !declared; }
}

}
