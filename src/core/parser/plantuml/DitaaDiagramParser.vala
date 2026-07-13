/* DitaaDiagramParser.vala — strips @startditaa/@endditaa wrapper, stores ASCII */
namespace GDiagram {

public class DitaaDiagramParser : Object {
    public DitaaDiagram parse(string source) {
        var diagram = new DitaaDiagram();

        // Include markers are preprocessor comments, not part of the drawing
        string content = Preprocessor.strip_include_markers(source);

        // Strip @startditaa line; it may carry options:
        // @startditaa(--no-shadows, scale=0.7) or @startditaa -E -S
        int start = content.index_of("@startditaa");
        if (start >= 0) {
            int nl = content.index_of("\n", start);
            string header = nl >= 0 ? content.substring(start, nl - start) : content.substring(start);
            read_options(diagram, header.substring("@startditaa".length));
            content = nl >= 0 ? content.substring(nl + 1) : "";
        }

        // Strip @endditaa and everything after
        int end = content.index_of("@endditaa");
        if (end >= 0) {
            content = content.substring(0, end);
        }

        // Remove trailing blank lines but preserve internal structure
        diagram.ascii_text = content.chomp();
        return diagram;
    }

    private static void read_options(DitaaDiagram d, string header) {
        foreach (string raw in header.replace("(", " ").replace(")", " ").replace(",", " ").split(" ")) {
            string opt = raw.strip();
            if (opt == "--no-shadows" || opt == "-S") d.shadows = false;
            else if (opt == "--no-separation" || opt == "-E") d.separation = false;
            else if (opt == "--round-corners" || opt == "-r") d.round_corners = true;
            else if (opt.has_prefix("scale=")) {
                double s = double.parse(opt.substring(6));
                if (s > 0.05 && s <= 10) d.scale = s;
            }
        }
    }
}

}
