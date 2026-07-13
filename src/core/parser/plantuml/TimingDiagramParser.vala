/* TimingDiagramParser.vala — line-based parser for PlantUML timing diagrams */
namespace GDiagram {

public class TimingDiagramParser : Object {
    private TimingDiagram diagram;
    private int current_time;
    private Gee.HashMap<string, TimingSignal> signal_map;

    public TimingDiagramParser() {}

    public TimingDiagram parse(string source) {
        this.diagram = new TimingDiagram();
        this.current_time = 0;
        this.signal_map = new Gee.HashMap<string, TimingSignal>();

        parse_timing(source);

        return diagram;
    }

    private void parse_timing(string source) {
        string[] lines = source.split("\n");

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower == "@startuml" || lower == "@enduml") continue;
            if (lower.has_prefix("hide ") || lower.has_prefix("scale ") ||
                lower.has_prefix("skinparam") || lower.has_prefix("<style>") ||
                lower == "</style>") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            // Time marker: @N or @+N
            if (trimmed.has_prefix("@")) {
                string time_str = trimmed.substring(1).strip().down();
                if (time_str.has_prefix("+")) {
                    current_time += int.parse(time_str.substring(1));
                } else {
                    current_time = int.parse(time_str);
                }
                if (current_time > diagram.max_time) diagram.max_time = current_time;
                continue;
            }

            // Signal declaration: concise/robust/binary/clock/analog "Label" as ALIAS
            SignalType? stype = null;
            if (lower.has_prefix("concise ")) stype = SignalType.CONCISE;
            else if (lower.has_prefix("robust ")) stype = SignalType.ROBUST;
            else if (lower.has_prefix("binary ")) stype = SignalType.BINARY;
            else if (lower.has_prefix("clock ")) stype = SignalType.CLOCK;
            else if (lower.has_prefix("analog ")) stype = SignalType.ANALOG;

            if (stype != null) {
                parse_signal_declaration(trimmed, stype, i + 1);
                continue;
            }

            // State assignment: ALIAS is STATE
            if (trimmed.contains(" is ")) {
                int is_pos = trimmed.index_of(" is ");
                if (is_pos > 0) {
                    string alias = trimmed.substring(0, is_pos).strip();
                    string state = trimmed.substring(is_pos + 4).strip();
                    // Remove comment at end of state
                    int note_pos = state.index_of(" : ");
                    if (note_pos >= 0) state = state.substring(0, note_pos).strip();

                    if (signal_map.has_key(alias)) {
                        signal_map.get(alias).state_changes.add(
                            new SignalStateChange(current_time, state)
                        );
                    }
                }
            }
        }
    }

    private void parse_signal_declaration(string line, SignalType stype, int lineno) {
        // Parse: TYPE "Label" as ALIAS [with period N]
        string rest = line;
        // Strip type keyword
        int space = rest.index_of(" ");
        if (space < 0) return;
        rest = rest.substring(space + 1).strip();

        string label;
        string alias_name;

        // Extract quoted label
        if (rest.has_prefix("\"")) {
            int close_quote = rest.index_of("\"", 1);
            if (close_quote < 0) return;
            label = rest.substring(1, close_quote - 1);
            rest = rest.substring(close_quote + 1).strip();
        } else {
            // No quotes — use first word as label
            int sp = rest.index_of(" ");
            if (sp < 0) {
                label = rest;
                rest = "";
            } else {
                label = rest.substring(0, sp);
                rest = rest.substring(sp + 1).strip();
            }
        }

        // Extract alias: "as ALIAS [with period N]"
        string lower_rest = rest.down();
        if (lower_rest.has_prefix("as ")) {
            rest = rest.substring(3).strip();
            // Check for "with period N"
            int with_pos = rest.down().index_of(" with ");
            if (with_pos >= 0) {
                alias_name = rest.substring(0, with_pos).strip();
                // period value parsed but not used for rendering
            } else {
                alias_name = rest.strip();
                // Remove any trailing modifiers
                int sp2 = alias_name.index_of(" ");
                if (sp2 >= 0) alias_name = alias_name.substring(0, sp2);
            }
        } else {
            // No alias — use label as alias
            alias_name = label.replace(" ", "_");
        }

        var signal = new TimingSignal(alias_name, label, stype, lineno);
        diagram.signals.add(signal);
        signal_map.set(alias_name, signal);
    }
}

}
