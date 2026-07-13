/* DotDiagram.vala — AST for raw Graphviz DOT passthrough (@startdot) */
namespace GDiagram {

public class DotDiagram : Object {
    public string dot_source { get; set; default = ""; }
    public string? title { get; set; default = null; }
}

}
