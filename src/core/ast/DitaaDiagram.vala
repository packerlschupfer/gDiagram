/* DitaaDiagram.vala — AST for PlantUML DITAA ASCII art (@startditaa) */
namespace GDiagram {

public class DitaaDiagram : Object {
    public string ascii_text { get; set; default = ""; }
    public string? title { get; set; default = null; }
}

}
