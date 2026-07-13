/* SaltDiagram.vala — AST for PlantUML @startsalt UI wireframes */
namespace GDiagram {

public enum SaltElementType {
    PANEL,
    BUTTON,
    TEXT_FIELD,
    LABEL,
    SEPARATOR,
    TREE,
    TABLE,
    DROPDOWN,
    RADIO,
    CHECKBOX
}

public class SaltElement : Object {
    public SaltElementType element_type { get; set; }
    public string text { get; set; default = ""; }
    public bool checked { get; set; default = false; }
    public int source_line { get; set; default = 0; }
    public Gee.ArrayList<SaltElement> children { get; private set; }
    // For PANEL-type elements: the nested panel containing rows
    public SaltPanel? nested_panel { get; set; default = null; }

    public SaltElement(SaltElementType t, string text = "", int line = 0) {
        this.element_type = t;
        this.text = text;
        this.source_line = line;
        this.children = new Gee.ArrayList<SaltElement>();
    }
}

public class SaltRow : Object {
    public Gee.ArrayList<SaltElement> cells { get; private set; }
    public int source_line { get; set; default = 0; }

    public SaltRow(int line = 0) {
        this.cells = new Gee.ArrayList<SaltElement>();
        this.source_line = line;
    }
}

public class SaltPanel : Object {
    public string panel_type { get; set; default = ""; }  // "", "T" (tree), "#" (table)
    public Gee.ArrayList<SaltRow> rows { get; private set; }
    public int source_line { get; set; default = 0; }

    public SaltPanel(string panel_type = "", int line = 0) {
        this.panel_type = panel_type;
        this.rows = new Gee.ArrayList<SaltRow>();
        this.source_line = line;
    }
}

public class SaltDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public SaltPanel root { get; set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public SaltDiagram() {
        this.diagram_type = DiagramType.SALT;
        this.root = new SaltPanel("", 0);
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return root.rows.size == 0; }
}

}
