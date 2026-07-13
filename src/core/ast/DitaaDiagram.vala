/* DitaaDiagram.vala — AST for PlantUML DITAA ASCII art (@startditaa) */
namespace GDiagram {

public class DitaaDiagram : Object {
    public string ascii_text { get; set; default = ""; }
    public string? title { get; set; default = null; }
    // @startditaa options: --no-shadows / -S, --no-separation / -E,
    // --round-corners / -r, scale=N
    public bool shadows { get; set; default = true; }
    public bool separation { get; set; default = true; }
    public bool round_corners { get; set; default = false; }
    public double scale { get; set; default = 1.0; }
}

}
