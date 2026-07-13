/* ChenDiagram.vala — AST for PlantUML @startchen Chen ER notation */
namespace GDiagram {

public class ChenAttribute : Object {
    public string name { get; set; }
    public bool is_key { get; set; default = false; }
    public bool is_derived { get; set; default = false; }
    public bool is_multivalued { get; set; default = false; }
    public int source_line { get; set; default = 0; }
    // `"Shown text" as CODE`: the text drawn instead of the code
    public string? display { get; set; default = null; }
    // Composite attribute: `Name { First  Last }`
    public Gee.ArrayList<ChenAttribute> children { get; private set; }

    public ChenAttribute(string name, int line = 0) {
        this.name = name;
        this.source_line = line;
        this.children = new Gee.ArrayList<ChenAttribute>();
    }

    public string label() { return display ?? name; }
}

public class ChenEntity : Object {
    public string name { get; set; }
    public Gee.ArrayList<ChenAttribute> attributes { get; private set; }
    public string? color { get; set; }
    public bool is_weak { get; set; default = false; }
    public int source_line { get; set; default = 0; }
    public string? display { get; set; default = null; }

    public string label() { return display ?? name; }

    public ChenEntity(string name, int line = 0) {
        this.name = name;
        this.attributes = new Gee.ArrayList<ChenAttribute>();
        this.source_line = line;
    }
}

public class ChenRelationship : Object {
    public string name { get; set; }
    public string? color { get; set; }
    public Gee.ArrayList<ChenAttribute> attributes { get; private set; }
    public int source_line { get; set; default = 0; }
    public string? display { get; set; default = null; }
    // <<identifying>>: drawn with a double border
    public bool is_identifying { get; set; default = false; }

    public string label() { return display ?? name; }

    public ChenRelationship(string name, int line = 0) {
        this.name = name;
        this.attributes = new Gee.ArrayList<ChenAttribute>();
        this.source_line = line;
    }
}

public class ChenLink : Object {
    public string from_name { get; set; }
    public string to_name { get; set; }
    public string cardinality { get; set; default = ""; }
    public int source_line { get; set; default = 0; }
    // `A =N= B`: total participation, drawn as a heavy line
    public bool total { get; set; default = false; }

    public ChenLink(string from_name, string to_name, string cardinality = "", int line = 0) {
        this.from_name = from_name;
        this.to_name = to_name;
        this.cardinality = cardinality;
        this.source_line = line;
    }
}

// Specialisation: `A ->- B` (B is a subclass of A), `A -<- B` (A is a
// subclass of B) or `A =>= d { B, C }` (disjoint `d`, overlapping `o` or union
// `U` subclasses through a circle).
public class ChenSubclass : Object {
    public string superclass { get; set; }
    public Gee.ArrayList<string> subclasses { get; private set; }
    public bool total { get; set; default = false; }
    // Simple form: true for `->-`, false for `-<-`
    public bool downwards { get; set; default = true; }
    // Multi form: "d", "o" or "U"; null for the simple form
    public string? symbol { get; set; default = null; }
    public int source_line { get; set; default = 0; }

    public ChenSubclass(string superclass, int line = 0) {
        this.superclass = superclass;
        this.subclasses = new Gee.ArrayList<string>();
        this.source_line = line;
    }
}

public class ChenDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<ChenEntity> entities { get; private set; }
    public Gee.ArrayList<ChenRelationship> relationships { get; private set; }
    public Gee.ArrayList<ChenLink> links { get; private set; }
    public Gee.ArrayList<ChenSubclass> subclasses { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public ChenDiagram() {
        this.diagram_type = DiagramType.CHEN_ER;
        this.entities = new Gee.ArrayList<ChenEntity>();
        this.relationships = new Gee.ArrayList<ChenRelationship>();
        this.links = new Gee.ArrayList<ChenLink>();
        this.subclasses = new Gee.ArrayList<ChenSubclass>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return entities.size == 0 && relationships.size == 0; }
}

}
