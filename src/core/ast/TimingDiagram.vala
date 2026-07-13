/* TimingDiagram.vala — AST for PlantUML Timing diagrams */
namespace GDiagram {

public enum SignalType {
    CONCISE,
    ROBUST,
    BINARY,
    CLOCK,
    ANALOG
}

public class SignalStateChange : Object {
    public int time_value { get; set; }
    public string state { get; set; }

    public SignalStateChange(int time, string state) {
        this.time_value = time;
        this.state = state;
    }
}

public class TimingSignal : Object {
    public string alias_name { get; set; }
    public string label { get; set; }
    public SignalType signal_type { get; set; }
    public int clock_period { get; set; }
    public Gee.ArrayList<SignalStateChange> state_changes { get; private set; }
    public int source_line { get; set; }

    public TimingSignal(string alias_name, string label, SignalType signal_type, int line = 0) {
        this.alias_name = alias_name;
        this.label = label;
        this.signal_type = signal_type;
        this.clock_period = 10;
        this.state_changes = new Gee.ArrayList<SignalStateChange>();
        this.source_line = line;
    }
}

public class TimingDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<TimingSignal> signals { get; private set; }
    public int max_time { get; set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public TimingDiagram() {
        this.diagram_type = DiagramType.TIMING;
        this.signals = new Gee.ArrayList<TimingSignal>();
        this.max_time = 100;
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return signals.size == 0; }
}

}
