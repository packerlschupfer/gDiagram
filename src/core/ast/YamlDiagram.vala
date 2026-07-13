/* YamlDiagram.vala — AST for PlantUML YAML visualization */
namespace GDiagram {

public enum YamlNodeType {
    MAPPING,    // key: value pairs object
    SEQUENCE,   // list
    SCALAR      // leaf value
}

public class YamlNode : Object {
    public YamlNodeType node_type { get; set; }
    public string? key { get; set; }
    public string? value { get; set; }      // for SCALAR
    public Gee.ArrayList<YamlNode> children { get; private set; }
    public bool highlighted { get; set; }
    public int depth { get; set; }

    public YamlNode(YamlNodeType type, int depth = 0) {
        this.node_type = type;
        this.depth = depth;
        this.children = new Gee.ArrayList<YamlNode>();
        this.highlighted = false;
    }
}

public class YamlDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public YamlNode? root { get; set; }
    public Gee.ArrayList<string> highlights { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public YamlDiagram() {
        this.diagram_type = DiagramType.YAML_DIAGRAM;
        this.highlights = new Gee.ArrayList<string>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return root == null; }
}

}
