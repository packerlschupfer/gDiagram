/* ChronologyDiagramParser.vala — parser for PlantUML @startchronology */
namespace GDiagram {

public class ChronologyDiagramParser : Object {
    private ChronologyDiagram diagram;

    public ChronologyDiagramParser() {}

    public ChronologyDiagram parse(string source) {
        this.diagram = new ChronologyDiagram();

        parse_chronology(source);

        return diagram;
    }

    private void parse_chronology(string source) {
        string[] lines = source.split("\n");

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower == "@startchronology" || lower == "@endchronology") continue;
            if (lower.has_prefix("skinparam") || lower.has_prefix("<style>") || lower == "</style>") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            // [Event Name] happens on DATE
            if (trimmed.has_prefix("[")) {
                parse_event_line(trimmed, i + 1);
            }
        }
    }

    private void parse_event_line(string line, int lineno) {
        // Extract event name from [...]
        int close_bracket = line.index_of("]");
        if (close_bracket < 0) return;

        string event_name = line.substring(1, close_bracket - 1).strip();
        string rest = line.substring(close_bracket + 1).strip().down();

        // Find "happens on DATE"
        int happens_pos = rest.index_of("happens on ");
        if (happens_pos < 0) return;

        string date_str = line.substring(close_bracket + 1 + happens_pos + 11).strip();
        if (date_str.length == 0) return;

        // Clean up event name — if it contains a colon + date, strip the date part
        int colon_pos = event_name.index_of(": 20");
        if (colon_pos < 0) colon_pos = event_name.index_of(": 19");
        if (colon_pos > 0) {
            event_name = event_name.substring(0, colon_pos).strip();
        }

        diagram.add_event(new ChronologyEvent(event_name, date_str, lineno));
    }
}

}
