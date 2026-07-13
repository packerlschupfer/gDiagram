/* ArchimateDiagram.vala — AST for PlantUML Archimate diagrams */
namespace GDiagram {

public enum ArchimateLayer {
    BUSINESS,
    APPLICATION,
    TECHNOLOGY,
    MOTIVATION,
    PHYSICAL,
    IMPLEMENTATION,
    STRATEGY,
    NONE
}

public class ArchimateElement : Object {
    public string id { get; set; }
    public string label { get; set; }
    public ArchimateLayer layer { get; set; }
    public string? stereotype { get; set; }    // <<Role>>, <<Component>>, etc.
    public string? color { get; set; }         // explicit #Color override
    public int source_line { get; set; }

    public ArchimateElement(string id, string label, ArchimateLayer layer, int line = 0) {
        this.id = id;
        this.label = label;
        this.layer = layer;
        this.stereotype = null;
        this.color = null;
        this.source_line = line;
    }
}

public class ArchimateRelation : Object {
    public string from_id { get; set; }
    public string to_id { get; set; }
    public string? label { get; set; }
    public string rel_type { get; set; }       // Association, Flow, Serving, etc.
    public bool is_dotted { get; set; }
    public int source_line { get; set; }

    public ArchimateRelation(string from_id, string to_id, string rel_type, int line = 0) {
        this.from_id = from_id;
        this.to_id = to_id;
        this.rel_type = rel_type;
        this.is_dotted = false;
        this.label = null;
        this.source_line = line;
    }
}

public class ArchimateGroup : Object {
    public string name { get; set; }
    public Gee.ArrayList<string> element_ids { get; private set; }
    public int source_line { get; set; }

    public ArchimateGroup(string name, int line = 0) {
        this.name = name;
        this.element_ids = new Gee.ArrayList<string>();
        this.source_line = line;
    }
}

public class ArchimateDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<ArchimateElement> elements { get; private set; }
    public Gee.ArrayList<ArchimateRelation> relations { get; private set; }
    public Gee.ArrayList<ArchimateGroup> groups { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public ArchimateDiagram() {
        this.diagram_type = DiagramType.ARCHIMATE;
        this.elements = new Gee.ArrayList<ArchimateElement>();
        this.relations = new Gee.ArrayList<ArchimateRelation>();
        this.groups = new Gee.ArrayList<ArchimateGroup>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return elements.size == 0; }

    public ArchimateElement? find_element(string id) {
        foreach (var e in elements) {
            if (e.id == id) return e;
        }
        return null;
    }
}

}
