/* MermaidUseCase.vala — AST for Mermaid `usecase-beta` diagrams
 *
 * Mirrors the committed model of mermaid 12.2.0's usecaseModelBuilder.ts /
 * usecaseTypes.ts (UsecaseFields): actors, use cases, system boundaries,
 * relationships, notes, json nodes, classDefs and a direction.
 *
 * Every type here is prefixed `MermaidUseCase…`: the PlantUML use case AST in
 * src/core/ast/UseCaseDiagram.vala already owns `UseCase`, `UseCaseActor`,
 * `UseCaseNote` and friends in the same namespace.
 */
namespace GDiagram {

// `actor X@{ type: … }` — the stick-figure variant. ICON is implied by an
// `icon:` property, as mermaid's builder does.
public enum MermaidActorType {
    NORMAL,
    HOLLOW,
    AWESOME,
    ICON
}

// `id(Label)` is an ellipse, `id[Label]` a rectangle; an undeclared relation
// endpoint defaults to an ellipse.
public enum MermaidUseCaseShape {
    ELLIPSE,
    RECT
}

// `systemBoundary X@{ type: … }`
public enum MermaidBoundaryType {
    RECT,
    PACKAGE
}

public enum MermaidUseCaseRelationKind {
    ASSOCIATION,
    INCLUDE,
    EXTEND,
    GENERALIZATION
}

// mermaid's numeric arrowType, same order and meaning.
public enum MermaidUseCaseArrow {
    SOLID_ARROW,             // 0  A --> B
    BACK_ARROW,              // 1  A <-- B
    LINE_SOLID,              // 2  A -- B
    CIRCLE_ARROW,            // 3  A --o B
    CROSS_ARROW,             // 4  A --x B
    CIRCLE_ARROW_REVERSED,   // 5  A o-- B
    CROSS_ARROW_REVERSED,    // 6  A x-- B
    // Not one of mermaid's arrowTypes: `--|>` carries no arrowType of its own
    // (the model stores 0 and sets kind = generalization). The parser uses this
    // as the marker the operator scanner returns, and never stores it.
    GENERALIZATION_MARK
}

// Shared by every element that may carry `:::class` and `style` declarations.
public abstract class MermaidUseCaseElement : Object {
    public string id { get; set; }
    public string label { get; set; }
    public bool label_markdown { get; set; default = false; }
    public string? stereotype { get; set; default = null; }
    public bool business { get; set; default = false; }
    public string? parent_id { get; set; default = null; }
    public Gee.ArrayList<string> classes { get; private set; }
    public Gee.ArrayList<string> styles { get; private set; }
    public int source_line { get; set; default = 0; }

    construct {
        this.classes = new Gee.ArrayList<string>();
        this.styles = new Gee.ArrayList<string>();
    }
}

public class MermaidUseCaseActor : MermaidUseCaseElement {
    public MermaidActorType actor_type { get; set; default = MermaidActorType.NORMAL; }
    public string? icon { get; set; default = null; }

    public MermaidUseCaseActor(string id, string label, int line = 0) {
        this.id = id;
        this.label = label;
        this.source_line = line;
    }
}

public class MermaidUseCaseItem : MermaidUseCaseElement {
    public MermaidUseCaseShape shape { get; set; default = MermaidUseCaseShape.ELLIPSE; }

    public MermaidUseCaseItem(string id, string label, int line = 0) {
        this.id = id;
        this.label = label;
        this.source_line = line;
    }
}

public class MermaidUseCaseBoundary : MermaidUseCaseElement {
    public MermaidBoundaryType boundary_type { get; set; default = MermaidBoundaryType.RECT; }
    public Gee.ArrayList<string> members { get; private set; }

    public MermaidUseCaseBoundary(string id, string label, int line = 0) {
        this.id = id;
        this.label = label;
        this.source_line = line;
        this.members = new Gee.ArrayList<string>();
    }
}

// `json config @{ … }` — the body is kept as written; mermaid renders it as a
// key/value table.
public class MermaidUseCaseJsonNode : MermaidUseCaseElement {
    public string body { get; set; }
    public Gee.ArrayList<string> keys { get; private set; }
    public Gee.ArrayList<string> values { get; private set; }

    public MermaidUseCaseJsonNode(string id, string body, int line = 0) {
        this.id = id;
        this.label = id;
        this.body = body;
        this.source_line = line;
        this.keys = new Gee.ArrayList<string>();
        this.values = new Gee.ArrayList<string>();
    }
}

public class MermaidUseCaseRelation : Object {
    public string id { get; set; }
    public bool explicit_id { get; set; default = false; }
    public string source { get; set; }
    public string target { get; set; }
    public MermaidUseCaseRelationKind kind { get; set; default = MermaidUseCaseRelationKind.ASSOCIATION; }
    public MermaidUseCaseArrow arrow { get; set; default = MermaidUseCaseArrow.SOLID_ARROW; }
    public string? label { get; set; default = null; }
    public bool label_markdown { get; set; default = false; }
    public int minlen { get; set; default = 1; }
    public bool animate { get; set; default = false; }
    public string? animation { get; set; default = null; }
    public Gee.ArrayList<string> classes { get; private set; }
    public Gee.ArrayList<string> styles { get; private set; }
    public int source_line { get; set; default = 0; }

    public MermaidUseCaseRelation(string id, string source, string target, int line = 0) {
        this.id = id;
        this.source = source;
        this.target = target;
        this.source_line = line;
        this.classes = new Gee.ArrayList<string>();
        this.styles = new Gee.ArrayList<string>();
    }
}

// `note for Login "Requires MFA"`
public class MermaidUseCaseNote : Object {
    public string id { get; set; }
    public string target { get; set; }
    public string label { get; set; }
    public bool label_markdown { get; set; default = false; }
    public int source_line { get; set; default = 0; }

    public MermaidUseCaseNote(string id, string target, string label, int line = 0) {
        this.id = id;
        this.target = target;
        this.label = label;
        this.source_line = line;
    }
}

// `classDef critical fill:#f96,stroke:#333`
public class MermaidUseCaseClassDef : Object {
    public string id { get; set; }
    public Gee.ArrayList<string> styles { get; private set; }

    public MermaidUseCaseClassDef(string id) {
        this.id = id;
        this.styles = new Gee.ArrayList<string>();
    }
}

public class MermaidUseCase : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; default = null; }
    public string? acc_title { get; set; default = null; }
    public string? acc_descr { get; set; default = null; }
    // mermaid's default when no `direction` statement is given is LR.
    public string direction { get; set; default = "LR"; }

    public Gee.ArrayList<MermaidUseCaseActor> actors { get; private set; }
    public Gee.ArrayList<MermaidUseCaseItem> use_cases { get; private set; }
    public Gee.ArrayList<MermaidUseCaseBoundary> boundaries { get; private set; }
    public Gee.ArrayList<MermaidUseCaseRelation> relations { get; private set; }
    public Gee.ArrayList<MermaidUseCaseNote> notes { get; private set; }
    public Gee.ArrayList<MermaidUseCaseJsonNode> json_nodes { get; private set; }
    public Gee.ArrayList<MermaidUseCaseClassDef> class_defs { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidUseCase() {
        this.diagram_type = MermaidDiagramType.USECASE;
        this.actors = new Gee.ArrayList<MermaidUseCaseActor>();
        this.use_cases = new Gee.ArrayList<MermaidUseCaseItem>();
        this.boundaries = new Gee.ArrayList<MermaidUseCaseBoundary>();
        this.relations = new Gee.ArrayList<MermaidUseCaseRelation>();
        this.notes = new Gee.ArrayList<MermaidUseCaseNote>();
        this.json_nodes = new Gee.ArrayList<MermaidUseCaseJsonNode>();
        this.class_defs = new Gee.ArrayList<MermaidUseCaseClassDef>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public MermaidUseCaseActor? find_actor(string id) {
        foreach (var a in actors) {
            if (a.id == id) return a;
        }
        return null;
    }

    public MermaidUseCaseItem? find_use_case(string id) {
        foreach (var u in use_cases) {
            if (u.id == id) return u;
        }
        return null;
    }

    public MermaidUseCaseBoundary? find_boundary(string id) {
        foreach (var b in boundaries) {
            if (b.id == id) return b;
        }
        return null;
    }

    public MermaidUseCaseJsonNode? find_json(string id) {
        foreach (var j in json_nodes) {
            if (j.id == id) return j;
        }
        return null;
    }

    // The kind an id already resolves to, or null: mermaid's `symbols` map.
    public string? kind_of(string id) {
        if (find_actor(id) != null) return "actor";
        if (find_use_case(id) != null) return "usecase";
        if (find_boundary(id) != null) return "boundary";
        if (find_json(id) != null) return "json";
        foreach (var r in relations) {
            if (r.explicit_id && r.id == id) return "edge";
        }
        return null;
    }

    public MermaidUseCaseElement? find_element(string id) {
        MermaidUseCaseElement? e = find_actor(id);
        if (e != null) return e;
        e = find_use_case(id);
        if (e != null) return e;
        e = find_boundary(id);
        if (e != null) return e;
        return find_json(id);
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() {
        return actors.size == 0 && use_cases.size == 0 && boundaries.size == 0 &&
               json_nodes.size == 0;
    }
}

}
