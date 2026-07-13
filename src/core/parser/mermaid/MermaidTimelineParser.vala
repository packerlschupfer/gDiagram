/* MermaidTimelineParser.vala — line-based parser for Mermaid timeline diagrams */
namespace GDiagram {

public class MermaidTimelineParser : Object {

    public MermaidTimelineParser() {}

    public MermaidTimeline parse(string source) {
        var diagram = new MermaidTimeline();
        string? current_section = null;
        TimelinePeriod? current_period = null;
        int line_num = 0;

        foreach (var raw_line in source.split("\n")) {
            line_num++;
            string line = raw_line.strip();

            if (line.length == 0) continue;

            // Comment
            if (line.has_prefix("%%")) continue;

            // "timeline" keyword line
            if (line.down() == "timeline" || line.down().has_prefix("timeline ")) continue;

            // Title line
            if (line.down().has_prefix("title ")) {
                diagram.title = line.substring(6).strip();
                continue;
            }

            // Section line
            if (line.down().has_prefix("section ")) {
                current_section = line.substring(8).strip();
                current_period = null;
                continue;
            }

            // Period / event line: "2004 : Facebook", "2023 : A : B : C", or a
            // continuation ": Google". As in Mermaid, the period ends at the
            // first colon and every further ": " starts another event.
            int colon_pos = line.index_of_char(':');
            if (colon_pos >= 0) {
                string left = line.substring(0, colon_pos).strip();
                var events = new Gee.ArrayList<string>();
                foreach (var part in Regex.split_simple(":(?=\\s|$)", line.substring(colon_pos))) {
                    string ev = part.strip();
                    if (ev.length > 0) events.add(ev);
                }

                if (left.length > 0) {
                    current_period = new TimelinePeriod(left, current_section, line_num);
                    diagram.add_period(current_period);
                }
                if (current_period != null) {
                    foreach (var ev in events) {
                        current_period.add_event(new TimelineEvent(ev, line_num));
                    }
                }
                // an orphan continuation (no period yet) is ignored
            }
            // Lines with no colon and not a keyword are ignored
        }

        return diagram;
    }
}

}
