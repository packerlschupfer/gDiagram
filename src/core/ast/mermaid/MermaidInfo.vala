/* MermaidInfo.vala — AST for Mermaid's `info` diagram
 *
 * Mermaid's info diagram carries no user data at all: its grammar
 * (src/language/generated/grammar.ts, rule `Info`) is
 *
 *     NEWLINE* 'info' NEWLINE* ('showInfo' NEWLINE*)? TitleAndAccessibilities?
 *
 * and its renderer (src/diagrams/info/infoRenderer.ts) draws one text node
 * with the renderer's own version. We keep the accessibility/title fields the
 * grammar accepts so they can be shown, plus the `showInfo` flag.
 */
namespace GDiagram {

public class MermaidInfo : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public bool declared { get; set; default = false; }   // the `info` keyword was seen
    public bool show_info { get; set; default = false; }  // the legacy `showInfo` keyword
    public string? title { get; set; }
    public string? acc_title { get; set; }
    public string? acc_descr { get; set; }
    public string version { get; set; }
    public int source_line { get; set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidInfo() {
        this.diagram_type = MermaidDiagramType.INFO;
        this.title = null;
        this.acc_title = null;
        this.acc_descr = null;
        this.version = VERSION;
        this.source_line = 0;
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }

    // An `info` document with nothing but its keyword is complete, not empty.
    public bool is_empty() { return !declared; }
}

}
