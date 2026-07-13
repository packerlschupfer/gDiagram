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

            // Period / event line: "2004 : Facebook" or ": Another event"
            // Try " : " separator first (space-colon-space), then ": " (colon-space)
            int colon_pos = line.index_of(" : ");
            bool three_char_sep = (colon_pos >= 0);
            if (!three_char_sep) {
                colon_pos = line.index_of(": ");
            }

            if (colon_pos >= 0) {
                string left = line.substring(0, colon_pos).strip();
                int sep_len = three_char_sep ? 3 : 2;
                string right = line.substring(colon_pos + sep_len).strip();

                if (left.length == 0 && current_period != null) {
                    // Continuation event under the same period
                    current_period.add_event(new TimelineEvent(right, line_num));
                } else if (left.length > 0) {
                    // New period
                    current_period = new TimelinePeriod(left, current_section, line_num);
                    current_period.add_event(new TimelineEvent(right, line_num));
                    diagram.add_period(current_period);
                }
                // left.length == 0 && current_period == null → ignore orphan continuation
            }
            // Lines with no colon and not a keyword are ignored
        }

        return diagram;
    }
}

}
