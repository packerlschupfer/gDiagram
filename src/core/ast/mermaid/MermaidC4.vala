namespace GDiagram {

// ==================== C4 ====================

public enum C4ElementType {
    PERSON,
    SYSTEM,
    CONTAINER,
    COMPONENT,
    DEPLOYMENT_NODE,
    BOUNDARY
}

public class C4Element : Object {
    public string id { get; set; }
    public string label { get; set; }
    public string? description { get; set; }
    public string? technology { get; set; }
    public C4ElementType element_type { get; set; }
    public bool is_external { get; set; }
    public bool is_db { get; set; }
    public bool is_queue { get; set; }
    public string? parent_boundary { get; set; }
    // Mermaid's shape type ("person", "external_system_db", ...), shown as the
    // "[Software System]" / "[Container: tech]" line
    public string c4_shape_type { get; set; default = ""; }
    // UpdateElementStyle overrides
    public string? bg_color { get; set; }
    public string? font_color { get; set; }
    public string? border_color { get; set; }
    public int source_line { get; set; }

    public C4Element(string id, string label, C4ElementType etype, int line = 0) {
        this.id = id;
        this.label = label;
        this.element_type = etype;
        this.is_external = false;
        this.is_db = false;
        this.is_queue = false;
        this.source_line = line;
    }
}

public class C4Boundary : Object {
    public string id { get; set; }
    public string label { get; set; }
    public string? boundary_type { get; set; }
    public string? parent_boundary { get; set; }
    public string? description { get; set; }
    // Deployment_Node / Node / Node_L / Node_R scopes
    public bool is_deployment_node { get; set; default = false; }
    // UpdateElementStyle overrides
    public string? bg_color { get; set; }
    public string? font_color { get; set; }
    public string? border_color { get; set; }
    public int source_line { get; set; }

    public C4Boundary(string id, string label, int line = 0) {
        this.id = id;
        this.label = label;
        this.source_line = line;
    }
}

public class C4Relationship : Object {
    public string from_id { get; set; }
    public string to_id { get; set; }
    public string label { get; set; }
    public string? technology { get; set; }
    public bool is_bidirectional { get; set; }
    public string direction { get; set; }  // "", "U", "D", "L", "R"
    public string? description { get; set; }
    // UpdateRelStyle overrides
    public string? text_color { get; set; }
    public string? line_color { get; set; }
    // $offsetX / $offsetY move the label, in pixels, y downwards (Mermaid drawRels)
    public double offset_x { get; set; default = 0; }
    public double offset_y { get; set; default = 0; }
    public int source_line { get; set; }

    public C4Relationship(string from_id, string to_id, string label, int line = 0) {
        this.from_id = from_id;
        this.to_id = to_id;
        this.label = label;
        this.is_bidirectional = false;
        this.direction = "";
        this.source_line = line;
    }
}

public class MermaidC4 : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public string c4_type { get; set; }  // "Context", "Container", "Component", etc.
    // UpdateLayoutConfig($c4ShapeInRow, $c4BoundaryInRow)
    public int shape_in_row { get; set; default = 4; }
    public int boundary_in_row { get; set; default = 2; }
    public Gee.ArrayList<C4Element> elements { get; private set; }
    public Gee.ArrayList<C4Boundary> boundaries { get; private set; }
    public Gee.ArrayList<C4Relationship> relationships { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidC4() {
        this.diagram_type = MermaidDiagramType.C4;
        this.title = null;
        this.c4_type = "Context";
        this.elements = new Gee.ArrayList<C4Element>();
        this.boundaries = new Gee.ArrayList<C4Boundary>();
        this.relationships = new Gee.ArrayList<C4Relationship>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return elements.size == 0 && relationships.size == 0 && boundaries.size == 0; }
}

}
