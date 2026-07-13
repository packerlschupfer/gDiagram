/* MermaidWardley.vala — AST for Mermaid `wardley-beta` maps
 *
 * Mirrors mermaid 12.2.0's WardleyBuildResult (packages/mermaid/src/diagrams/
 * wardley/wardleyBuilder.ts): every coordinate is already a percentage, 0-100,
 * with `visibility` on the y axis and `evolution` on the x axis.
 */
namespace GDiagram {

// What a node is, which decides how it is drawn: a plain component circle, a
// bold anchor label with no circle, or a child of a pipeline box.
public enum WardleyNodeKind {
    COMPONENT,
    ANCHOR,
    PIPELINE_COMPONENT
}

// `component X [0.1, 0.2] (build)` — the sourcing decorator drawn as an
// overlay circle behind the component.
public enum WardleySourceStrategy {
    NONE,
    BUILD,
    BUY,
    OUTSOURCE,
    MARKET
}

// Which ends of a link carry an arrowhead. Mermaid leaves `->` and `-->`
// without any marker; only the `+<`/`+>`/`+<>` ports and the `+'label'<>`
// arrow forms ask for one.
public enum WardleyFlow {
    NONE,
    FORWARD,
    BACKWARD,
    BIDIRECTIONAL
}

public class WardleyMapNode : Object {
    public string id { get; set; }
    public string label { get; set; }
    // Percentages, 0-100. `x` is evolution, `y` is visibility.
    public double x { get; set; }
    public double y { get; set; }
    public WardleyNodeKind kind { get; set; default = WardleyNodeKind.COMPONENT; }
    // `label [-57, 4]`: nullable, because 0 is a legal explicit offset and the
    // renderer's default offset differs per node kind. Plain fields rather
    // than properties — `double?` is not a usable GLib.Object property type.
    public double? label_offset_x = null;
    public double? label_offset_y = null;
    public bool in_pipeline { get; set; default = false; }
    public bool is_pipeline_parent { get; set; default = false; }
    public bool inertia { get; set; default = false; }
    public WardleySourceStrategy source_strategy { get; set; default = WardleySourceStrategy.NONE; }
    public int source_line { get; set; default = 0; }

    public WardleyMapNode(string id, string label, double x, double y,
                          WardleyNodeKind kind = WardleyNodeKind.COMPONENT, int line = 0) {
        this.id = id;
        this.label = label;
        this.x = x;
        this.y = y;
        this.kind = kind;
        this.source_line = line;
    }
}

public class WardleyLink : Object {
    public string source { get; set; }
    public string target { get; set; }
    public bool dashed { get; set; default = false; }
    public string? label { get; set; default = null; }
    public WardleyFlow flow { get; set; default = WardleyFlow.NONE; }
    public int source_line { get; set; default = 0; }

    public WardleyLink(string source, string target, bool dashed = false,
                       string? label = null, WardleyFlow flow = WardleyFlow.NONE, int line = 0) {
        this.source = source;
        this.target = target;
        this.dashed = dashed;
        this.label = label;
        this.flow = flow;
        this.source_line = line;
    }
}

// `evolve Kettle 0.62` — a dashed red arrow from the component's own position
// to (target evolution, same visibility).
public class WardleyTrend : Object {
    public string node_id { get; set; }
    public double target_x { get; set; }
    public double target_y { get; set; }
    public int source_line { get; set; default = 0; }

    public WardleyTrend(string node_id, double target_x, double target_y, int line = 0) {
        this.node_id = node_id;
        this.target_x = target_x;
        this.target_y = target_y;
        this.source_line = line;
    }
}

public class WardleyPipeline : Object {
    public string node_id { get; set; }
    public Gee.ArrayList<string> component_ids { get; private set; }
    public int source_line { get; set; default = 0; }

    public WardleyPipeline(string node_id, int line = 0) {
        this.node_id = node_id;
        this.component_ids = new Gee.ArrayList<string>();
        this.source_line = line;
    }
}

public class WardleyPoint : Object {
    public double x { get; set; }
    public double y { get; set; }

    public WardleyPoint(double x, double y) {
        this.x = x;
        this.y = y;
    }
}

public class WardleyAnnotation : Object {
    public int number { get; set; }
    public Gee.ArrayList<WardleyPoint> coordinates { get; private set; }
    public string? text { get; set; default = null; }
    public int source_line { get; set; default = 0; }

    public WardleyAnnotation(int number, string? text = null, int line = 0) {
        this.number = number;
        this.text = text;
        this.coordinates = new Gee.ArrayList<WardleyPoint>();
        this.source_line = line;
    }
}

public class WardleyNote : Object {
    public string text { get; set; }
    public double x { get; set; }
    public double y { get; set; }
    public int source_line { get; set; default = 0; }

    public WardleyNote(string text, double x, double y, int line = 0) {
        this.text = text;
        this.x = x;
        this.y = y;
        this.source_line = line;
    }
}

// `accelerator Name [x, y]` and `deaccelerator Name [x, y]`: the same shape,
// mirrored, so one class carries both with a flag.
public class WardleyAccelerator : Object {
    public string name { get; set; }
    public double x { get; set; }
    public double y { get; set; }
    public bool decelerating { get; set; default = false; }
    public int source_line { get; set; default = 0; }

    public WardleyAccelerator(string name, double x, double y, bool decelerating = false, int line = 0) {
        this.name = name;
        this.x = x;
        this.y = y;
        this.decelerating = decelerating;
        this.source_line = line;
    }
}

public class MermaidWardley : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; default = null; }
    public string? acc_title { get; set; default = null; }
    public string? acc_descr { get; set; default = null; }

    public Gee.ArrayList<WardleyMapNode> nodes { get; private set; }
    public Gee.ArrayList<WardleyLink> links { get; private set; }
    public Gee.ArrayList<WardleyTrend> trends { get; private set; }
    public Gee.ArrayList<WardleyPipeline> pipelines { get; private set; }
    public Gee.ArrayList<WardleyAnnotation> annotations { get; private set; }
    public Gee.ArrayList<WardleyNote> notes { get; private set; }
    public Gee.ArrayList<WardleyAccelerator> accelerators { get; private set; }

    // `evolution Genesis -> Custom -> Product -> Commodity`, with the optional
    // `@0.25` boundaries. Boundaries are only honoured when there is one per
    // stage, as mermaid's renderer requires.
    public Gee.ArrayList<string> stages { get; private set; }
    public Gee.ArrayList<double?> stage_boundaries { get; private set; }

    // `size [1200, 800]`
    public bool has_size { get; set; default = false; }
    public int size_width { get; set; default = 0; }
    public int size_height { get; set; default = 0; }

    // `annotations [0.1, 0.1]` — where the numbered-annotation legend box goes.
    public bool has_annotations_box { get; set; default = false; }
    public double annotations_box_x { get; set; default = 0; }
    public double annotations_box_y { get; set; default = 0; }

    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidWardley() {
        this.diagram_type = MermaidDiagramType.WARDLEY;
        this.nodes = new Gee.ArrayList<WardleyMapNode>();
        this.links = new Gee.ArrayList<WardleyLink>();
        this.trends = new Gee.ArrayList<WardleyTrend>();
        this.pipelines = new Gee.ArrayList<WardleyPipeline>();
        this.annotations = new Gee.ArrayList<WardleyAnnotation>();
        this.notes = new Gee.ArrayList<WardleyNote>();
        this.accelerators = new Gee.ArrayList<WardleyAccelerator>();
        this.stages = new Gee.ArrayList<string>();
        this.stage_boundaries = new Gee.ArrayList<double?>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public WardleyMapNode? find_node(string id) {
        foreach (var n in nodes) {
            if (n.id == id) return n;
        }
        return null;
    }

    /**
     * A name as a node id: an exact id first, then the first node whose label
     * matches — mermaid's WardleyBuilder.resolveNodeId(), which is how a link
     * may name a pipeline child by its plain name while the node itself is
     * keyed "Parent_Child".
     */
    public string resolve_node_id(string name) {
        if (find_node(name) != null) return name;
        foreach (var n in nodes) {
            if (n.label == name) return n.id;
        }
        return name;
    }

    public WardleyPipeline? find_pipeline(string node_id) {
        foreach (var p in pipelines) {
            if (p.node_id == node_id) return p;
        }
        return null;
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() {
        return nodes.size == 0 && notes.size == 0 && annotations.size == 0 && accelerators.size == 0;
    }
}

}
