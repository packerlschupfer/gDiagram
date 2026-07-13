/* DotDiagramParser.vala — strips @startdot/@enddot wrapper, returns raw DOT */
namespace GDiagram {

public class DotDiagramParser : Object {
    public DotDiagram parse(string source) {
        var diagram = new DotDiagram();

        string content = source;

        // Strip @startdot line
        int start = content.index_of("@startdot");
        if (start >= 0) {
            int nl = content.index_of("\n", start);
            content = nl >= 0 ? content.substring(nl + 1) : "";
        }

        // Strip @enddot and everything after
        int end = content.index_of("@enddot");
        if (end >= 0) {
            content = content.substring(0, end);
        }

        diagram.dot_source = content.strip();
        return diagram;
    }
}

}
