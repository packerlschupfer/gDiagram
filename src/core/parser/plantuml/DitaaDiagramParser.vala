/* DitaaDiagramParser.vala — strips @startditaa/@endditaa wrapper, stores ASCII */
namespace GDiagram {

public class DitaaDiagramParser : Object {
    public DitaaDiagram parse(string source) {
        var diagram = new DitaaDiagram();

        string content = source;

        // Strip @startditaa line (may have options after it)
        int start = content.index_of("@startditaa");
        if (start >= 0) {
            int nl = content.index_of("\n", start);
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
}

}
