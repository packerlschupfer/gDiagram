namespace GDiagram {

// ==================== Architecture ====================

public class ArchService : Object {
    public string id { get; set; }
    public string icon { get; set; }
    public string label { get; set; }
    public string? group_id { get; set; }
    public bool is_junction { get; set; }
    public int source_line { get; set; }

    public ArchService(string id, string icon, string label, int line = 0) {
        this.id = id;
        this.icon = icon;
        this.label = label;
        this.is_junction = false;
        this.source_line = line;
    }
}

public class ArchGroup : Object {
    public string id { get; set; }
    public string icon { get; set; }
    public string label { get; set; }
    public string? parent_id { get; set; }
    public int source_line { get; set; }

    public ArchGroup(string id, string icon, string label, int line = 0) {
        this.id = id;
        this.icon = icon;
        this.label = label;
        this.source_line = line;
    }
}

public class ArchEdge : Object {
    public string from_id { get; set; }
    public string from_side { get; set; }  // T, B, L, R
    public string to_id { get; set; }
    public string to_side { get; set; }
    public bool directed { get; set; }
    public int source_line { get; set; }

    public ArchEdge(string from_id, string from_side, string to_id, string to_side, bool directed, int line = 0) {
        this.from_id = from_id;
        this.from_side = from_side;
        this.to_id = to_id;
        this.to_side = to_side;
        this.directed = directed;
        this.source_line = line;
    }
}

public class MermaidArchitecture : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<ArchGroup> groups { get; private set; }
    public Gee.ArrayList<ArchService> services { get; private set; }
    public Gee.ArrayList<ArchEdge> edges { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidArchitecture() {
        this.diagram_type = MermaidDiagramType.ARCHITECTURE;
        this.title = null;
        this.groups = new Gee.ArrayList<ArchGroup>();
        this.services = new Gee.ArrayList<ArchService>();
        this.edges = new Gee.ArrayList<ArchEdge>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return services.size == 0 && groups.size == 0; }
}

}
