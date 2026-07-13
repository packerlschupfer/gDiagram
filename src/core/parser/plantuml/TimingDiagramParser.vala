/* TimingDiagramParser.vala — line-based parser for PlantUML timing diagrams
 *
 * One regex per PlantUML timing command (see net.sourceforge.plantuml
 * .timingdiagram.command), tried in the same order as PlantUML's
 * TimingDiagramFactory. Supports time- and participant-oriented state changes,
 * relative/absolute/date/hh:mm:ss/anchor/clock-multiple times, messages,
 * constraints, highlights, notes, scale, compact mode and date formats.
 */
namespace GDiagram {

public class TimingDiagramParser : Object {
    // Time expression (PlantUML TimeTickBuilder.expressionAtWithoutArobase), one capture group.
    private const string TIME =
        "(:[\\p{L}\\p{N}_.]+(?:[-+][.\\d]+)?|\\d+/\\d+/\\d+|\\d+:\\d+:\\d+|\\+?-?\\d+\\.?\\d*|[\\p{L}\\p{N}_.@]+\\*\\d+)";
    private const string CODE = "([\\p{L}\\p{N}_.@]+)";
    private const string PLAYER = "([\\p{L}_][\\p{L}\\p{N}_.]*)";
    private const string STATE_CODE = "[-\\p{L}\\p{N}_][-\\p{L}\\p{N}_.]*";
    private const string FULL = "[\"\\x{201C}\\x{201D}]([^\"\\x{201C}\\x{201D}]+)[\"\\x{201C}\\x{201D}]";
    private const string STEREO = "(<<.+?>>)?";
    private const string COLOR = "(#[\\w#;:.\\-\\\\|/]+)?";

    private TimingDiagram diagram;
    private Gee.HashMap<string, TimingSignal> signal_map;
    private bool has_now;
    private double now;
    private TimingSignal? last_player;

    private Regex re_robust;
    private Regex re_clock;
    private Regex re_analog;
    private Regex re_binary;
    private Regex re_has_short;
    private Regex re_has_long;
    private Regex re_state_by_code;
    private Regex re_state_by_time;
    private Regex re_at_time;
    private Regex re_at_player;
    private Regex re_message;
    private Regex re_note;
    private Regex re_note_long;
    private Regex re_constraint;
    private Regex re_scale;
    private Regex re_hide_axis;
    private Regex re_highlight;
    private Regex re_compact;
    private Regex re_ticks;
    private Regex re_height;
    private Regex re_date_format;
    private Regex re_title;
    private Regex re_time_date;
    private Regex re_time_hour;
    private Regex re_time_code;
    private Regex re_time_clock;

    public TimingDiagramParser() {
        try {
            var f = RegexCompileFlags.CASELESS | RegexCompileFlags.OPTIMIZE;
            string state = "(?:\"([^\"]*)\"|(" + STATE_CODE + ")|(\\{hidden\\})|(\\{\\.\\.\\.\\})|(\\{-\\})|(\\{\\?\\})"
                + "|\\{(" + STATE_CODE + ")\\s*,\\s*(" + STATE_CODE + ")\\})";
            string state_tail = "\\s*" + COLOR + "\\s*(?::\\s*(.*?))?\\s*$";

            re_robust = new Regex("^(?:(compact)\\s+)?(robust|concise|rectangle)\\s+(?:" + FULL + "\\s*" + STEREO
                + "\\s*as\\s+)?" + CODE + "\\s*" + STEREO + "\\s*" + COLOR + "\\s*$", f);
            re_clock = new Regex("^(?:(compact)\\s+)?clock\\s+(?:" + FULL + "\\s+as\\s+)?" + CODE
                + "\\s+with\\s+period\\s+(\\d+(?:\\.\\d+)?)(?:\\s+pulse\\s+(\\d+(?:\\.\\d+)?))?"
                + "(?:\\s+offset\\s+(\\d+(?:\\.\\d+)?))?\\s*" + STEREO + "\\s*$", f);
            re_analog = new Regex("^(?:(compact)\\s+)?analog\\s+(?:" + FULL + "\\s*" + STEREO
                + "\\s*(?:(?:between|from)\\s+(-?\\d*\\.?\\d+)\\s+(?:and|to)\\s+(-?\\d*\\.?\\d+)\\s+)?as\\s+)?"
                + CODE + "\\s*" + STEREO + "\\s*$", f);
            re_binary = new Regex("^(?:(compact)\\s+)?binary\\s+(?:" + FULL + "\\s*" + STEREO + "\\s*as\\s+)?"
                + CODE + "\\s*" + STEREO + "\\s*$", f);
            re_has_short = new Regex("^" + CODE + "\\s+has\\s+([-\\p{L}\\p{N}_.@]+(?:\\s*,\\s*[-\\p{L}\\p{N}_.@]+)*)\\s*$", f);
            re_has_long = new Regex("^" + CODE + "\\s+has\\s+" + FULL + "\\s+as\\s+" + CODE + "\\s*$", f);
            re_state_by_code = new Regex("^" + PLAYER + "\\s*is\\s*" + state + state_tail, f);
            re_state_by_time = new Regex("^" + TIME + "\\s*is\\s*" + state + state_tail, f);
            re_at_time = new Regex("^@" + TIME + "(?:\\s+as\\s+:([\\p{L}\\p{N}_.]+))?\\s*$", f);
            re_at_player = new Regex("^@" + PLAYER + "\\s*$", f);
            re_message = new Regex("^" + PLAYER + "(?:@" + TIME + ")?\\s*(-+)(?:\\[([^\\]]*)\\])?>\\s*" + PLAYER
                + "(?:@" + TIME + ")?\\s*(?::\\s*(.*?))?\\s*$", f);
            re_note = new Regex("^note\\s+(top|bottom)\\s+of\\s+" + PLAYER + "\\s*" + STEREO + "\\s*:\\s*(.+?)\\s*$", f);
            re_note_long = new Regex("^note\\s+(top|bottom)\\s+of\\s+" + PLAYER + "\\s*" + STEREO + "\\s*$", f);
            re_constraint = new Regex("^(" + "[\\p{L}_][\\p{L}\\p{N}_.]*" + ")?@" + TIME
                + "\\s*<-+(?:\\[([^\\]]*)\\])?-*>\\s*@" + TIME + "\\s*(?::\\s*(.*?))?\\s*$", f);
            re_scale = new Regex("^scale\\s+(\\d+)(?:\\s?([smhdy]))?\\s+as\\s+(\\d+)\\s+pixels?\\s*$", f);
            re_hide_axis = new Regex("^(hide|manual)\\s+time.?axis\\s*$", f);
            re_highlight = new Regex("^highlight\\s+" + TIME + "\\s+to\\s+" + TIME + "\\s*" + COLOR
                + "\\s*(?::\\s*(.*?))?\\s*$", f);
            re_compact = new Regex("^mode\\s+compact\\s*$", f);
            re_ticks = new Regex("^" + CODE + "\\s+ticks\\s+(?:every|num\\s+on\\s+multiple)\\s+(\\d+)\\s*$", f);
            re_height = new Regex("^" + CODE + "\\s+is\\s+(\\d+)\\s+pixels?\\s+height\\s*$", f);
            re_date_format = new Regex("^use\\s+date\\s+format\\s+" + FULL + "\\s*$", f);
            re_title = new Regex("^title\\s*:?\\s*(.*?)\\s*$", f);
            re_time_date = new Regex("^(\\d+)/(\\d+)/(\\d+)$");
            re_time_hour = new Regex("^(\\d+):(\\d+):(\\d+)$");
            re_time_code = new Regex("^:([\\p{L}\\p{N}_.]+)([-+][.\\d]+)?$");
            re_time_clock = new Regex("^([\\p{L}\\p{N}_.@]+)\\*(\\d+)$");
        } catch (RegexError e) {
            critical("TimingDiagramParser: bad regex: %s", e.message);
        }
    }

    public TimingDiagram parse(string source) {
        this.diagram = new TimingDiagram();
        this.signal_map = new Gee.HashMap<string, TimingSignal>();
        this.has_now = false;
        this.now = 0;
        this.last_player = null;

        parse_lines(source);
        return diagram;
    }

    private void parse_lines(string source) {
        string[] lines = source.split("\n");
        // Main-file line numbers: included text reports its !include line
        int[] line_nos = Preprocessor.source_line_numbers(lines);

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i].strip();
            int lineno = line_nos[i];
            if (line.length == 0 || line.has_prefix("'")) continue;
            string lower = line.down();

            if (lower.has_prefix("@startuml") || lower.has_prefix("@enduml")) continue;

            // Block comment /' ... '/
            if (line.has_prefix("/'")) {
                while (i < lines.length && !lines[i].contains("'/")) i++;
                continue;
            }
            // <style> ... </style>
            if (lower.has_prefix("<style>")) {
                while (i < lines.length && !lines[i].down().contains("</style>")) i++;
                continue;
            }
            // skinparam blocks
            if (lower.has_prefix("skinparam")) {
                if (line.has_suffix("{")) {
                    while (i < lines.length && lines[i].strip() != "}") i++;
                }
                continue;
            }
            // Multi-line title / legend / header / footer / caption blocks
            if (lower == "title" || lower == "legend" || lower.has_prefix("legend ") ||
                lower == "header" || lower == "footer" || lower == "caption") {
                string end_kw = "end" + lower.split(" ")[0];
                var sb = new StringBuilder();
                i++;
                while (i < lines.length) {
                    string l = lines[i].strip();
                    string ll = l.down().replace(" ", "");
                    if (ll == end_kw) break;
                    if (sb.len > 0) sb.append("\n");
                    sb.append(l);
                    i++;
                }
                if (lower == "title") diagram.title = sb.str;
                continue;
            }
            if (lower.has_prefix("header ") || lower.has_prefix("footer ") ||
                lower.has_prefix("caption ") || lower.has_prefix("hide footbox") ||
                lower.has_prefix("!") || lower == "left to right direction") {
                continue;
            }

            parse_command(line, lines, ref i, lineno);
        }
    }

    private void parse_command(string line, string[] lines, ref int i, int lineno) {
        MatchInfo m;

        if (re_robust.match(line, 0, out m)) {
            string type = m.fetch(2).down();
            SignalType st = type == "robust" ? SignalType.ROBUST
                : (type == "concise" ? SignalType.CONCISE : SignalType.RECTANGLE);
            var sig = add_signal(m.fetch(5), fetch_or_empty(m, 3), st, lineno);
            sig.compact = nonempty(m, 1) || diagram.compact_mode;
            sig.stereotype = first_nonempty(m, 4, 6);
            string? unused_line;
            sig.back_color = parse_color_spec(fetch_or_null(m, 7), out unused_line);
            last_player = sig;
            return;
        }
        if (re_clock.match(line, 0, out m)) {
            var sig = add_signal(m.fetch(3), fetch_or_empty(m, 2), SignalType.CLOCK, lineno);
            sig.compact = diagram.compact_mode;
            sig.clock_period = double.parse(m.fetch(4));
            sig.clock_pulse = nonempty(m, 5) ? double.parse(m.fetch(5)) : 0;
            sig.clock_offset = nonempty(m, 6) ? double.parse(m.fetch(6)) : 0;
            sig.stereotype = fetch_or_null(m, 7);
            // PlantUML adds the period to the ruler (it drives the tick unit)
            diagram.times.add(sig.clock_period);
            return;
        }
        if (re_analog.match(line, 0, out m)) {
            var sig = add_signal(m.fetch(6), fetch_or_empty(m, 2), SignalType.ANALOG, lineno);
            sig.compact = diagram.compact_mode;
            sig.stereotype = first_nonempty(m, 3, 7);
            if (nonempty(m, 4) && nonempty(m, 5)) {
                sig.analog_min = m.fetch(4);
                sig.analog_max = m.fetch(5);
            }
            return;
        }
        if (re_binary.match(line, 0, out m)) {
            var sig = add_signal(m.fetch(4), fetch_or_empty(m, 2), SignalType.BINARY, lineno);
            sig.compact = diagram.compact_mode;
            sig.stereotype = first_nonempty(m, 3, 5);
            return;
        }
        if (re_has_long.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(1)];
            if (sig != null) define_state(sig, m.fetch(3), m.fetch(2));
            return;
        }
        if (re_has_short.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(1)];
            if (sig != null) {
                foreach (var code in m.fetch(2).split(",")) {
                    string c = code.strip();
                    if (c.length > 0) define_state(sig, c, c);
                }
            }
            return;
        }
        if (re_state_by_code.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(1)];
            if (sig != null) {
                add_state(sig, m, 2, has_now, now, lineno);
                return;
            }
            // Unknown code: may still be a time expression (e.g. "clk*2 is x")
        }
        if (re_state_by_time.match(line, 0, out m)) {
            if (last_player != null) {
                bool ok;
                double t = resolve_time(m.fetch(1), out ok, true);
                if (ok) {
                    add_time(t);
                    add_state(last_player, m, 2, true, t, lineno);
                }
            }
            return;
        }
        if (re_at_time.match(line, 0, out m)) {
            bool ok;
            double t = resolve_time(m.fetch(1), out ok, true);
            if (ok) {
                add_time(t);
                if (nonempty(m, 2)) diagram.anchors[m.fetch(2)] = t;
            }
            return;
        }
        if (re_at_player.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(1)];
            if (sig != null) last_player = sig;
            return;
        }
        if (re_message.match(line, 0, out m)) {
            var p1 = signal_map[m.fetch(1)];
            var p2 = signal_map[m.fetch(5)];
            if (p1 != null && p2 != null) {
                double t1 = double.NAN, t2 = double.NAN;
                bool ok1 = true, ok2 = true;
                if (nonempty(m, 2)) t1 = resolve_time(m.fetch(2), out ok1, false);
                else if (has_now) t1 = now;
                if (nonempty(m, 6)) t2 = resolve_time(m.fetch(6), out ok2, false);
                else if (has_now) t2 = now;
                var msg = new TimingMessage(p1.alias_name, ok1 ? t1 : double.NAN,
                                            p2.alias_name, ok2 ? t2 : double.NAN,
                                            fetch_or_null(m, 7));
                msg.color = arrow_color(fetch_or_null(m, 4));
                msg.source_line = lineno;
                diagram.messages.add(msg);
            }
            return;
        }
        if (re_note.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(2)];
            if (sig != null) add_note(sig, m.fetch(1), unescape_newlines(m.fetch(4)), lineno);
            return;
        }
        if (re_note_long.match(line, 0, out m)) {
            var sb = new StringBuilder();
            int j = i + 1;
            while (j < lines.length) {
                string l = lines[j].strip();
                string ll = l.down();
                if (ll == "end note" || ll == "endnote") break;
                if (sb.len > 0) sb.append("\n");
                sb.append(l);
                j++;
            }
            i = j;
            var sig = signal_map[m.fetch(2)];
            if (sig != null) add_note(sig, m.fetch(1), sb.str, lineno);
            return;
        }
        if (re_constraint.match(line, 0, out m)) {
            TimingSignal? sig = nonempty(m, 1) ? signal_map[m.fetch(1)] : last_player;
            if (sig == null) return;
            bool ok1, ok2;
            double t1 = resolve_time(m.fetch(2), out ok1, false);
            if (!ok1) return;
            // The second time is relative to the first one
            bool saved_has = has_now;
            double saved_now = now;
            has_now = true;
            now = t1;
            double t2 = resolve_time(m.fetch(4), out ok2, false);
            has_now = saved_has;
            now = saved_now;
            if (!ok2) return;
            var c = new TimingConstraint(t1, t2, fetch_or_null(m, 5));
            c.color = arrow_color(fetch_or_null(m, 3));
            c.source_line = lineno;
            sig.constraints.add(c);
            return;
        }
        if (re_scale.match(line, 0, out m)) {
            int64 tick = int64.parse(m.fetch(1)) * unit_factor(fetch_or_null(m, 2));
            int64 pixels = int64.parse(m.fetch(3));
            if (tick > 0 && pixels > 0) {
                diagram.scale_ticks = tick;
                diagram.scale_pixels = pixels;
            }
            return;
        }
        if (re_hide_axis.match(line, 0, out m)) {
            if (m.fetch(1).down() == "hide") diagram.hide_time_axis = true;
            else diagram.manual_time_axis = true;
            return;
        }
        if (re_highlight.match(line, 0, out m)) {
            bool ok1, ok2;
            double t1 = resolve_time(m.fetch(1), out ok1, false);
            double t2 = resolve_time(m.fetch(2), out ok2, false);
            if (ok1 && ok2) {
                var h = new TimingHighlight(t1, t2);
                string? line_color = null;
                h.back_color = parse_color_spec(fetch_or_null(m, 3), out line_color);
                h.line_color = line_color;
                h.caption = nonempty(m, 4) ? unescape_newlines(m.fetch(4)) : null;
                h.source_line = lineno;
                diagram.highlights.add(h);
            }
            return;
        }
        if (re_compact.match(line, 0, out m)) {
            diagram.compact_mode = true;
            return;
        }
        if (re_ticks.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(1)];
            if (sig != null && sig.signal_type == SignalType.ANALOG) sig.ticks_every = int.parse(m.fetch(2));
            return;
        }
        if (re_height.match(line, 0, out m)) {
            var sig = signal_map[m.fetch(1)];
            if (sig != null) sig.suggested_height = int.parse(m.fetch(2));
            return;
        }
        if (re_date_format.match(line, 0, out m)) {
            diagram.date_format = m.fetch(1);
            return;
        }
        if (re_title.match(line, 0, out m) && line.down().has_prefix("title")) {
            diagram.title = unescape_newlines(m.fetch(1));
            return;
        }
        // Anything else (hide/show/scale factor/...) is ignored
    }

    // ── helpers ──────────────────────────────────────────────

    private TimingSignal add_signal(string code, string full, SignalType type, int lineno) {
        var sig = new TimingSignal(code, full, type, lineno);
        if (signal_map.has_key(code)) {
            // PlantUML's LinkedHashMap keeps the first position, replaces the player
            int idx = diagram.signals.index_of(signal_map[code]);
            diagram.signals[idx] = sig;
        } else {
            diagram.signals.add(sig);
        }
        signal_map[code] = sig;
        return sig;
    }

    private void define_state(TimingSignal sig, string code, string label) {
        if (sig.signal_type != SignalType.ROBUST && sig.signal_type != SignalType.CONCISE &&
            sig.signal_type != SignalType.RECTANGLE) return;
        if (!sig.state_labels.has_key(code)) sig.state_codes.add(code);
        sig.state_labels[code] = label;
    }

    /** Builds a state change from the state groups starting at `base`. */
    private void add_state(TimingSignal sig, MatchInfo m, int base_group, bool timed, double t, int lineno) {
        if (sig.signal_type == SignalType.CLOCK) return;
        SignalStateChange change;
        if (nonempty(m, base_group + 6) && nonempty(m, base_group + 7)) {
            change = new SignalStateChange.intricated(t, decode_state(sig, m.fetch(base_group + 6)),
                                                      decode_state(sig, m.fetch(base_group + 7)));
        } else {
            string? s = null;
            // Quoted state may legitimately be empty
            string? quoted = null;
            int qs, qe;
            if (m.fetch_pos(base_group, out qs, out qe) && qs >= 0) quoted = m.fetch(base_group);
            if (quoted != null) {
                s = quoted;
            } else {
                for (int g = base_group + 1; g <= base_group + 5; g++) {
                    if (nonempty(m, g)) { s = m.fetch(g); break; }
                }
            }
            if (s == null) return;
            change = new SignalStateChange(t, decode_state(sig, s));
        }
        string? line_color = null;
        change.back_color = parse_color_spec(fetch_or_null(m, base_group + 8), out line_color);
        change.line_color = line_color;
        string? comment = fetch_or_null(m, base_group + 9);
        change.comment = comment != null ? unescape_newlines(comment) : null;
        change.source_line = lineno;
        if (!timed) {
            sig.initial_state = change;
        } else {
            sig.state_changes.add(change);
        }
    }

    private string decode_state(TimingSignal sig, string code) {
        if (sig.state_labels.has_key(code)) return sig.state_labels[code];
        return code;
    }

    private void add_note(TimingSignal sig, string pos, string text, int lineno) {
        var note = new TimingNote(pos.down() == "bottom" ? TimingNotePosition.BOTTOM : TimingNotePosition.TOP, text);
        note.has_time = has_now;
        note.time = has_now ? now : 0;
        note.source_line = lineno;
        sig.notes.add(note);
    }

    private void add_time(double t) {
        has_now = true;
        now = t;
        diagram.times.add(t);
    }

    /**
     * Resolves a time expression (PlantUML TimeTickBuilder.parseTimeTick).
     * Updates the diagram time format for dates and hh:mm:ss.
     */
    public double resolve_time(string expr, out bool ok, bool update_format) {
        ok = true;
        MatchInfo m;
        if (re_time_code.match(expr, 0, out m)) {
            string code = m.fetch(1);
            if (!diagram.anchors.has_key(code)) { ok = false; return 0; }
            double v = diagram.anchors[code];
            if (nonempty(m, 2)) v += double.parse(m.fetch(2));
            return v;
        }
        if (re_time_date.match(expr, 0, out m)) {
            if (update_format) diagram.time_format = TimingTimeFormat.DATE;
            return days_from_civil(int.parse(m.fetch(1)), int.parse(m.fetch(2)), int.parse(m.fetch(3))) * 86400.0;
        }
        if (re_time_hour.match(expr, 0, out m)) {
            if (update_format) diagram.time_format = TimingTimeFormat.HOUR;
            return int.parse(m.fetch(1)) * 3600.0 + int.parse(m.fetch(2)) * 60.0 + int.parse(m.fetch(3));
        }
        if (re_time_clock.match(expr, 0, out m)) {
            var clk = signal_map[m.fetch(1)];
            if (clk == null || clk.signal_type != SignalType.CLOCK) { ok = false; return 0; }
            return clk.clock_period * int.parse(m.fetch(2));
        }
        bool relative = expr.has_prefix("+");
        double v = double.parse(relative ? expr.substring(1) : expr);
        if (relative && has_now) v += now;
        return v;
    }

    /** Days since 1970-01-01 for a proleptic Gregorian date (month/day may overflow like GregorianCalendar). */
    public static int64 days_from_civil(int y, int mo, int d) {
        // Normalise month overflow
        y += (mo - 1) / 12;
        mo = (mo - 1) % 12 + 1;
        int64 yy = mo <= 2 ? y - 1 : y;
        int64 era = (yy >= 0 ? yy : yy - 399) / 400;
        int64 yoe = yy - era * 400;
        int64 mp = (mo + 9) % 12;
        int64 doy = (153 * mp + 2) / 5 + d - 1;
        int64 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    private static int64 unit_factor(string? unit) {
        if (unit == null) return 1;
        switch (unit.down()) {
            case "m": return 60;
            case "h": return 3600;
            case "d": return 86400;
            case "y": return 3600L * 8766L;
            default: return 1;
        }
    }

    /** `#back;line:#x` / `#back` → back colour, line colour through `line_color`. */
    public static string? parse_color_spec(string? spec, out string? line_color) {
        line_color = null;
        if (spec == null || spec.length == 0) return null;
        string? back = null;
        foreach (var raw in spec.split(";")) {
            string part = raw.strip();
            if (part.length == 0) continue;
            string lower = part.down();
            if (lower.has_prefix("#line:") || lower.has_prefix("line:") || lower.has_prefix("line.") ||
                lower.has_prefix("#line.")) {
                int idx = part.index_of_char(':');
                if (idx < 0) idx = part.index_of_char('.');
                line_color = part.substring(idx + 1).strip();
            } else if (lower.has_prefix("text:") || lower.has_prefix("#text:")) {
                continue;
            } else if (lower.has_prefix("back:") || lower.has_prefix("#back:")) {
                back = part.substring(part.index_of_char(':') + 1).strip();
            } else if (back == null) {
                back = part;
            }
        }
        return back;
    }

    private static string? arrow_color(string? style) {
        if (style == null) return null;
        foreach (var part in style.split(",")) {
            string p = part.strip();
            if (p.has_prefix("#")) return p;
        }
        return null;
    }

    private static string unescape_newlines(string s) {
        return s.replace("\\n", "\n");
    }

    private static bool nonempty(MatchInfo m, int g) {
        string? s = m.fetch(g);
        return s != null && s.length > 0;
    }

    private static string? fetch_or_null(MatchInfo m, int g) {
        string? s = m.fetch(g);
        return (s != null && s.length > 0) ? s : null;
    }

    private static string fetch_or_empty(MatchInfo m, int g) {
        string? s = m.fetch(g);
        return s != null ? s : "";
    }

    private static string? first_nonempty(MatchInfo m, int a, int b) {
        return fetch_or_null(m, a) ?? fetch_or_null(m, b);
    }
}

}
