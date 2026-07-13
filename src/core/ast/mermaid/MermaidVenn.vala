/* MermaidVenn.vala — AST for Mermaid's `venn-beta` diagram
 *
 * Grammar, from mermaid 12.2.0's jison parser (src/diagrams/venn/parser/venn.jison,
 * recovered from the shipped sourcemap):
 *
 *     start:      optNewlines VENN document EOF
 *     statement:  TITLE
 *               | SET   identifier     (BRACKET_LABEL)? (COLON NUMERIC)?
 *               | UNION identifierList (BRACKET_LABEL)? (COLON NUMERIC)?
 *               | TEXT  identifierList (IDENTIFIER|STRING|NUMERIC) (BRACKET_LABEL)?
 *               | INDENT_TEXT         (IDENTIFIER|STRING|NUMERIC) (BRACKET_LABEL)?
 *               | STYLE identifierList stylesOpt
 *     identifier: IDENTIFIER | STRING
 *     styleField: IDENTIFIER COLON (STRING | valueTokens)
 *
 * `size` defaults to `10 / n²` for an n-identifier subset (vennDB.ts
 * addSubsetData), i.e. 10 for a set, 2.5 for a pair, 10/9 for a triple.
 * Set ids inside a `union` must already have been declared with `set`.
 */
namespace GDiagram {

/**
 * A `string[]` copy of a string list.
 *
 * Not `list.to_array()`: valac emits Gee's generic to_array() as a `gpointer*`
 * and then assigns it straight into a `gchar**`, which trips the
 * -Wincompatible-pointer-types the build deliberately keeps switched on.
 */
internal string[] venn_string_array(Gee.List<string> list) {
    string[] result = new string[list.size];
    for (int i = 0; i < list.size; i++) result[i] = list.get(i);
    return result;
}

/** A `set` or `union` statement: the sets it covers plus its area weight. */
public class VennSubset : Object {
    // Sorted, as vennDB.ts sorts the identifier list before storing it.
    public Gee.ArrayList<string> sets { get; private set; }
    public double size { get; set; }
    public string? label { get; set; }
    public int source_line { get; set; }

    public VennSubset(Gee.ArrayList<string> sets, double size, string? label = null, int line = 0) {
        this.sets = sets;
        this.size = size;
        this.label = label;
        this.source_line = line;
    }

    /** The stable key vennRenderer.ts uses to match styles and layouts: "A|B". */
    public string key() {
        return string.joinv("|", venn_string_array(sets));
    }

    public bool is_set() { return sets.size == 1; }
}

/** A `text` statement: an extra label placed inside the area of `sets`. */
public class VennTextNode : Object {
    public Gee.ArrayList<string> sets { get; private set; }
    public string id { get; set; }
    public string? label { get; set; }
    public int source_line { get; set; }

    public VennTextNode(Gee.ArrayList<string> sets, string id, string? label = null, int line = 0) {
        this.sets = sets;
        this.id = id;
        this.label = label;
        this.source_line = line;
    }

    public string key() {
        return string.joinv("|", venn_string_array(sets));
    }

    public string display_label() {
        if (label != null && label.length > 0) return label;
        return id;
    }
}

/** A `style` statement: CSS-ish properties for one area or text node. */
public class VennStyleEntry : Object {
    public Gee.ArrayList<string> targets { get; private set; }
    public Gee.HashMap<string, string> styles { get; private set; }
    public int source_line { get; set; }

    public VennStyleEntry(Gee.ArrayList<string> targets, int line = 0) {
        this.targets = targets;
        this.styles = new Gee.HashMap<string, string>();
        this.source_line = line;
    }

    public string key() {
        return string.joinv("|", venn_string_array(targets));
    }
}

public class MermaidVenn : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public bool declared { get; set; default = false; }
    public string? title { get; set; }
    public Gee.ArrayList<VennSubset> subsets { get; private set; }
    public Gee.ArrayList<VennTextNode> text_nodes { get; private set; }
    public Gee.ArrayList<VennStyleEntry> style_entries { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidVenn() {
        this.diagram_type = MermaidDiagramType.VENN;
        this.title = null;
        this.subsets = new Gee.ArrayList<VennSubset>();
        this.text_nodes = new Gee.ArrayList<VennTextNode>();
        this.style_entries = new Gee.ArrayList<VennStyleEntry>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    /** The single-identifier subsets, in declaration order. */
    public Gee.ArrayList<VennSubset> sets() {
        var list = new Gee.ArrayList<VennSubset>();
        foreach (var s in subsets) {
            if (s.is_set()) list.add(s);
        }
        return list;
    }

    public VennSubset? find_subset(string key) {
        foreach (var s in subsets) {
            if (s.key() == key) return s;
        }
        return null;
    }

    /** Merged style properties for an area key ("A", "A|B"), as buildStyleByKey does. */
    public Gee.HashMap<string, string> styles_for(string key) {
        var merged = new Gee.HashMap<string, string>();
        foreach (var e in style_entries) {
            if (e.key() != key) continue;
            foreach (var k in e.styles.keys) merged.set(k, e.styles.get(k));
        }
        return merged;
    }

    public bool has_errors() { return errors.size > 0; }

    // Without a single `set` there is nothing to lay out — mermaid itself
    // crashes inside venn.js on a `venn-beta` with no sets.
    public bool is_empty() { return sets().size == 0; }
}

}
