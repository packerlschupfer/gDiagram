/* JsonDiagram.vala — AST for PlantUML JSON visualization */
namespace GDiagram {

public enum JsonNodeType {
    OBJECT,
    ARRAY,
    STRING,
    NUMBER,
    BOOLEAN,
    NULL_VALUE
}

public class JsonNode : Object {
    public JsonNodeType node_type { get; set; }
    public string? key { get; set; }               // null for array elements
    public string? string_value { get; set; }
    public double number_value { get; set; }
    public bool bool_value { get; set; }
    public Gee.ArrayList<JsonNode> children { get; private set; }
    public bool highlighted { get; set; }

    public JsonNode(JsonNodeType type) {
        this.node_type = type;
        this.children = new Gee.ArrayList<JsonNode>();
        this.highlighted = false;
    }

    public bool is_leaf() {
        return node_type != JsonNodeType.OBJECT && node_type != JsonNodeType.ARRAY;
    }

    public string get_display_value() {
        switch (node_type) {
            case JsonNodeType.STRING:  return "\"%s\"".printf(string_value ?? "");
            case JsonNodeType.NUMBER:  return "%.10g".printf(number_value);
            case JsonNodeType.BOOLEAN: return bool_value ? "true" : "false";
            case JsonNodeType.NULL_VALUE: return "null";
            case JsonNodeType.OBJECT: return "{...}";
            case JsonNodeType.ARRAY:  return "[...]";
            default: return "";
        }
    }
}

public class JsonDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public JsonNode? root { get; set; }
    public Gee.ArrayList<string> highlights { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public JsonDiagram() {
        this.diagram_type = DiagramType.JSON_DIAGRAM;
        this.highlights = new Gee.ArrayList<string>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return root == null; }
}

}
