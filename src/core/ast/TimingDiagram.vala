/* TimingDiagram.vala — AST for PlantUML Timing diagrams
 *
 * Mirrors PlantUML's own timing model (net.sourceforge.plantuml.timingdiagram):
 * players (signals) with state changes, a shared set of ruler times, messages
 * between players, constraints, highlights and notes. Times are seconds/units
 * held as doubles; dates and hh:mm:ss are converted to seconds.
 */
namespace GDiagram {

public enum SignalType {
    CONCISE,
    ROBUST,
    BINARY,
    CLOCK,
    ANALOG,
    RECTANGLE
}

/** How ruler labels are formatted (PlantUML TimingFormat). */
public enum TimingTimeFormat {
    DECIMAL,
    HOUR,
    DATE
}

public enum TimingNotePosition {
    TOP,
    BOTTOM
}

/** A state change of a signal. `states` has 1 entry, or 2 for `{a,b}`. */
public class SignalStateChange : Object {
    /** Change time; ignored for the initial (pre-time) state. */
    public double time { get; set; }
    public string[] states;
    public string? comment { get; set; }
    public string? back_color { get; set; }
    public string? line_color { get; set; }
    public int source_line { get; set; }

    /** First state (the only one unless the change is intricated). */
    public string state { get { return states[0]; } }

    public SignalStateChange(double time, string state) {
        this.time = time;
        this.states = { state };
    }

    public SignalStateChange.intricated(double time, string state1, string state2) {
        this.time = time;
        this.states = { state1, state2 };
    }

    public bool is_intricated() { return states.length == 2; }
    public bool is_hidden() { return states[0] == "{hidden}"; }
    public bool is_flat() { return states[0] == "{-}"; }
    public bool is_blank() { return states[0] == "{...}"; }
}

public class TimingConstraint : Object {
    public double time1 { get; set; }
    public double time2 { get; set; }
    public string? label { get; set; }
    public string? color { get; set; }
    public int source_line { get; set; }

    public TimingConstraint(double t1, double t2, string? label) {
        this.time1 = t1;
        this.time2 = t2;
        this.label = label;
    }
}

public class TimingNote : Object {
    /** Note time; has_time false when declared before any @time. */
    public double time { get; set; }
    public bool has_time { get; set; }
    public TimingNotePosition position { get; set; }
    public string text { get; set; }
    public int source_line { get; set; }

    public TimingNote(TimingNotePosition position, string text) {
        this.position = position;
        this.text = text;
    }
}

public class TimingSignal : Object {
    /** Code used in the source (`as CODE`, or the bare name). */
    public string alias_name { get; set; }
    /** Display title ("" when declared without a quoted label). */
    public string label { get; set; }
    public SignalType signal_type { get; set; }
    public bool compact { get; set; }
    public string? stereotype { get; set; }
    /** Whole-lane background colour (`robust "X" as X #pink`). */
    public string? back_color { get; set; }
    public int source_line { get; set; }

    // Clock
    public double clock_period { get; set; default = 10; }
    public double clock_pulse { get; set; default = 0; }
    public double clock_offset { get; set; default = 0; }

    // Analog
    public string? analog_min { get; set; }
    public string? analog_max { get; set; }
    public int ticks_every { get; set; default = 0; }

    /** `X is N pixels height`; 0 = type default. */
    public int suggested_height { get; set; default = 0; }

    /** Declared states (`has`), code -> label, in declaration order. */
    public Gee.ArrayList<string> state_codes { get; private set; }
    public Gee.HashMap<string, string> state_labels { get; private set; }

    /** State set before any time was given (`WB is Initializing`). */
    public SignalStateChange? initial_state { get; set; }
    public Gee.ArrayList<SignalStateChange> state_changes { get; private set; }
    public Gee.ArrayList<TimingConstraint> constraints { get; private set; }
    public Gee.ArrayList<TimingNote> notes { get; private set; }

    public TimingSignal(string alias_name, string label, SignalType signal_type, int line = 0) {
        this.alias_name = alias_name;
        this.label = label;
        this.signal_type = signal_type;
        this.source_line = line;
        this.state_codes = new Gee.ArrayList<string>();
        this.state_labels = new Gee.HashMap<string, string>();
        this.state_changes = new Gee.ArrayList<SignalStateChange>();
        this.constraints = new Gee.ArrayList<TimingConstraint>();
        this.notes = new Gee.ArrayList<TimingNote>();
    }

    public string display_name() {
        return label.length > 0 ? label : alias_name;
    }

    /** State changes sorted by time (stable, later duplicates replace earlier ones). */
    public Gee.ArrayList<SignalStateChange> sorted_changes() {
        var result = new Gee.ArrayList<SignalStateChange>();
        foreach (var c in state_changes) {
            int idx = -1;
            for (int i = 0; i < result.size; i++) {
                if (result[i].time == c.time) { idx = i; break; }
            }
            if (idx >= 0) {
                // PlantUML keeps changes in a TreeSet: the first one at a time wins
                continue;
            }
            int pos = result.size;
            while (pos > 0 && result[pos - 1].time > c.time) pos--;
            result.insert(pos, c);
        }
        return result;
    }
}

public class TimingMessage : Object {
    public string from_signal { get; set; }
    public string to_signal { get; set; }
    public double from_time { get; set; }
    public double to_time { get; set; }
    public string? label { get; set; }
    public string? color { get; set; }
    public int source_line { get; set; }

    public TimingMessage(string from_signal, double from_time, string to_signal, double to_time, string? label) {
        this.from_signal = from_signal;
        this.from_time = from_time;
        this.to_signal = to_signal;
        this.to_time = to_time;
        this.label = label;
    }
}

public class TimingHighlight : Object {
    public double from_time { get; set; }
    public double to_time { get; set; }
    public string? caption { get; set; }
    public string? back_color { get; set; }
    public string? line_color { get; set; }
    public int source_line { get; set; }

    public TimingHighlight(double from_time, double to_time) {
        this.from_time = from_time;
        this.to_time = to_time;
    }
}

public class TimingDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<TimingSignal> signals { get; private set; }
    public Gee.ArrayList<TimingMessage> messages { get; private set; }
    public Gee.ArrayList<TimingHighlight> highlights { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    /** Ruler times (sorted, unique): @time marks, `N is X` times, clock periods. */
    public Gee.TreeSet<double?> times { get; private set; }
    /** Anchors: `@0 as :start` -> "start" = 0. */
    public Gee.HashMap<string, double?> anchors { get; private set; }

    public TimingTimeFormat time_format { get; set; default = TimingTimeFormat.DECIMAL; }
    /** `use date format "..."` (SimpleDateFormat pattern), or null. */
    public string? date_format { get; set; }

    /** `scale N as M pixels`: 0 = automatic tick unit. */
    public int64 scale_ticks { get; set; default = 0; }
    public int64 scale_pixels { get; set; default = 50; }

    public bool hide_time_axis { get; set; }
    public bool manual_time_axis { get; set; }
    public bool compact_mode { get; set; }

    public TimingDiagram() {
        this.diagram_type = DiagramType.TIMING;
        this.signals = new Gee.ArrayList<TimingSignal>();
        this.messages = new Gee.ArrayList<TimingMessage>();
        this.highlights = new Gee.ArrayList<TimingHighlight>();
        this.errors = new Gee.ArrayList<ParseError>();
        this.times = new Gee.TreeSet<double?>((a, b) => {
            double x = a, y = b;
            return x < y ? -1 : (x > y ? 1 : 0);
        });
        this.anchors = new Gee.HashMap<string, double?>();
    }

    public TimingSignal? find_signal(string code) {
        foreach (var s in signals) {
            if (s.alias_name == code) return s;
        }
        return null;
    }

    /** Largest ruler time (0 when no time was given). */
    public double max_time {
        get {
            if (times.size == 0) return 0;
            double v = times.last();
            return v;
        }
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return signals.size == 0; }
}

}
