// Timing diagram review: parser coverage of PlantUML's timing commands and the
// waveform renderer's geometry (ported from PlantUML's TimingRuler/Panels).

using GDiagram;

TimingDiagram parse(string body) {
    var p = new TimingDiagramParser();
    return p.parse("@startuml\n" + body + "\n@enduml\n");
}

string render_svg(TimingDiagram d, out TimingDiagramRenderer renderer) {
    var regions = new Gee.ArrayList<ElementRegion>();
    renderer = new TimingDiagramRenderer(new Gvc.Context(), regions, "dot");
    return svg_string(renderer.render_to_svg(d));
}

// The SVG byte array carries no NUL terminator: copy exactly data.length bytes
string svg_string(uint8[]? data) {
    assert(data != null);
    var sb = new StringBuilder.sized(data.length + 1);
    sb.append_len((string) data, data.length);
    return sb.str;
}

void fail_with(string label, string message, string text) {
    stderr.printf("[%s] %s in:\n%s\n", label, message, text);
    assert_not_reached();
}

void assert_has(string label, string text, string needle) {
    if (!text.contains(needle)) fail_with(label, "missing '%s'".printf(needle), text);
}

void assert_lacks(string label, string text, string needle) {
    if (text.contains(needle)) fail_with(label, "unexpected '%s'".printf(needle), text);
}

// Same number formatting as the renderer (%.3f, trailing zeros trimmed, '.' decimal point)
string num(double v) {
    char[] buf = new char[64];
    string s = v.format(buf, "%.3f");
    if (s.contains(".")) {
        while (s.has_suffix("0")) s = s.substring(0, s.length - 1);
        if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
    }
    return s;
}

string vline(double x, double y1, double y2) {
    return "<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\"".printf(num(x), num(y1), num(x), num(y2));
}

int count_substr(string hay, string needle) {
    int n = 0, pos = 0;
    while ((pos = hay.index_of(needle, pos)) >= 0) { n++; pos += needle.length; }
    return n;
}

// ── Parser ──────────────────────────────────────────────────────────────────

void test_declarations() {
    var d = parse("robust \"Web Browser\" as WB\n" +
                  "concise \"Web User\" <<user>> as WU #pink\n" +
                  "rectangle \"Rect\" as R\n" +
                  "binary en\n" +
                  "clock clk with period 1.5 pulse 0.5 offset 0.25\n" +
                  "analog \"Volt\" between -1.5 and 3 as V\n" +
                  "compact concise \"Small\" as S\n" +
                  "V ticks num on multiple 2\n" +
                  "V is 80 pixels height");
    assert(d.signals.size == 7);
    var wb = d.find_signal("WB");
    assert(wb.signal_type == SignalType.ROBUST && wb.label == "Web Browser");
    var wu = d.find_signal("WU");
    assert(wu.signal_type == SignalType.CONCISE && wu.stereotype == "<<user>>" && wu.back_color == "#pink");
    assert(d.find_signal("R").signal_type == SignalType.RECTANGLE);
    var en = d.find_signal("en");
    assert(en != null && en.signal_type == SignalType.BINARY && en.label == "");
    var clk = d.find_signal("clk");
    assert(clk.signal_type == SignalType.CLOCK && clk.clock_period == 1.5 && clk.clock_pulse == 0.5
           && clk.clock_offset == 0.25 && clk.label == "");
    var v = d.find_signal("V");
    assert(v.signal_type == SignalType.ANALOG && v.analog_min == "-1.5" && v.analog_max == "3");
    assert(v.ticks_every == 2 && v.suggested_height == 80);
    assert(d.find_signal("S").compact);
    // The clock period is a ruler time (drives the tick unit)
    assert(d.times.contains(1.5));
}

void test_time_oriented_states() {
    var d = parse("robust \"WB\" as WB\nconcise \"WU\" as WU\n" +
                  "@0\nWU is Idle\nWB is Idle\n" +
                  "@100\nWU is Waiting #LightCyan;line:Aqua : a note\nWB is \"Proc. X\"\n" +
                  "@+200\nWB is {0,1} #SlateGrey\nWU is {-}\n" +
                  "@+50\nWU is {hidden}");
    var wu = d.find_signal("WU");
    assert(wu.state_changes.size == 4);
    assert(wu.state_changes[1].time == 100 && wu.state_changes[1].state == "Waiting");
    assert(wu.state_changes[1].back_color == "#LightCyan" && wu.state_changes[1].line_color == "Aqua");
    assert(wu.state_changes[1].comment == "a note");
    assert(wu.state_changes[2].time == 300 && wu.state_changes[2].is_flat());
    assert(wu.state_changes[3].time == 350 && wu.state_changes[3].is_hidden());
    var wb = d.find_signal("WB");
    assert(wb.state_changes[1].state == "Proc. X");  // quotes stripped
    assert(wb.state_changes[2].is_intricated() && wb.state_changes[2].states[1] == "1");
    assert(wb.state_changes[2].back_color == "#SlateGrey");
}

void test_participant_oriented_and_initial() {
    var d = parse("robust \"WB\" as WB\nconcise \"WU\" as WU\n" +
                  "WB is Initializing\n" +
                  "@WB\n0 is idle\n+200 is Proc.\n+100 is Waiting\n" +
                  "@WU\n0 is Waiting\n+500 is ok");
    var wb = d.find_signal("WB");
    assert(wb.initial_state != null && wb.initial_state.state == "Initializing");
    assert(wb.state_changes.size == 3);
    assert(wb.state_changes[1].time == 200 && wb.state_changes[2].time == 300);
    var wu = d.find_signal("WU");
    assert(wu.state_changes.size == 2 && wu.state_changes[1].time == 500);
    assert(d.times.contains(300.0) && d.times.contains(500.0));
}

void test_dates_hours_anchors() {
    var d = parse("concise \"S\" as S\n@2000/11/01\nS is Winter\n@2001/02/01\nS is Spring");
    assert(d.time_format == TimingTimeFormat.DATE);
    var s = d.find_signal("S");
    assert(s.state_changes[0].time == 973036800.0);          // 2000-11-01T00:00Z
    assert(s.state_changes[1].time - s.state_changes[0].time == 92 * 86400.0);

    d = parse("concise \"S\" as S\n@1:15:00\nS is A\n@1:16:30\nS is B");
    assert(d.time_format == TimingTimeFormat.HOUR);
    assert(d.find_signal("S").state_changes[1].time == 3600 + 16 * 60 + 30);

    d = parse("clock clk with period 1\nconcise \"D\" as D\n" +
              "@0 as :start\n@5 as :en_high\n@:en_high-2 as :m2\n" +
              "@:start\nD is a\n@:m2\nD is b\n@:en_high+6\nD is c\n@clk*8\nD is e");
    var dd = d.find_signal("D");
    assert(d.anchors["m2"] == 3.0);
    assert(dd.state_changes[1].time == 3 && dd.state_changes[2].time == 11 && dd.state_changes[3].time == 8);
}

void test_has_declarations() {
    var d = parse("robust \"S\" as S\nS has 0,1,2,hello\nS has \"Down\" as D\n@0\nS is D\n@1\nS is hello");
    var s = d.find_signal("S");
    assert(s.state_codes.size == 5);
    assert(s.state_labels["D"] == "Down");
    assert(s.state_changes[0].state == "Down");   // code decoded to its label
}

void test_messages_constraints_highlights_notes() {
    var d = parse("robust \"WB\" as WB\nconcise \"WU\" as WU\n" +
                  "@100\nWU -> WB : URL\n@300\nWB -> WU@+50 : back\n" +
                  "WB@0 <-> @50 : {50 ms lag}\n" +
                  "@WU\n@200 <-> @+150 : {150 ms}\n" +
                  "highlight 200 to 450 #Gold;line:DimGrey : caption\\nline 2\n" +
                  "note top of WU : first\\nsecond\n" +
                  "note bottom of WU\n  long\n  note\nend note\n" +
                  "hide time-axis\nmode compact\nscale 2 m as 40 pixels\nuse date format \"YY-MM-dd\"");
    assert(d.messages.size == 2);
    assert(d.messages[0].from_signal == "WU" && d.messages[0].to_signal == "WB");
    assert(d.messages[0].from_time == 100 && d.messages[0].label == "URL");
    assert(d.messages[1].from_time == 300 && d.messages[1].to_time == 350);
    var wb = d.find_signal("WB");
    assert(wb.constraints.size == 1 && wb.constraints[0].time2 == 50 && wb.constraints[0].label == "{50 ms lag}");
    var wu = d.find_signal("WU");
    // Constraint without participant goes to the current player; +150 is relative to its first time
    assert(wu.constraints.size == 1 && wu.constraints[0].time1 == 200 && wu.constraints[0].time2 == 350);
    assert(d.highlights.size == 1 && d.highlights[0].to_time == 450);
    assert(d.highlights[0].back_color == "#Gold" && d.highlights[0].line_color == "DimGrey");
    assert(d.highlights[0].caption == "caption\nline 2");
    assert(wu.notes.size == 2);
    assert(wu.notes[0].position == TimingNotePosition.TOP && wu.notes[0].text == "first\nsecond");
    assert(wu.notes[0].time == 300 && wu.notes[0].has_time);
    assert(wu.notes[1].position == TimingNotePosition.BOTTOM && wu.notes[1].text == "long\nnote");
    assert(d.hide_time_axis && d.compact_mode);
    assert(d.scale_ticks == 120 && d.scale_pixels == 40);
    assert(d.date_format == "YY-MM-dd");
}

void test_source_lines_and_comments() {
    var d = parse("' comment\n/' block\nrobust \"X\" as X\n'/\nskinparam foo {\n bar 1\n}\n<style>\ntimingDiagram {\n}\n</style>\n" +
                  "title My title\nconcise \"C\" as C");
    assert(d.signals.size == 1);        // the declaration inside the block comment is skipped
    assert(d.title == "My title");
    assert(d.find_signal("C").source_line == 14);
}

// ── Renderer geometry ───────────────────────────────────────────────────────

const string BASIC = "robust \"Web Browser\" as WB\nconcise \"Web User\" as WU\n" +
                     "@0\nWU is Idle\nWB is Idle\n@100\nWU is Waiting\nWB is Processing\n@300\nWB is Waiting";

void test_ruler_and_robust_transition_x() {
    TimingDiagramRenderer r;
    var d = parse(BASIC);
    string svg = render_svg(d, out r);
    // Tick unit = HCF of the times (100), 50 px per tick
    assert(r.get_tick_unit() == 100 && r.get_tick_pixels() == 50);
    double x0 = r.time_to_x(0);
    assert(r.time_to_x(300) - x0 == 150);
    assert(r.time_to_x(100) - x0 == 50);
    // Robust Processing -> Waiting transition: vertical step at x(300) between the two levels
    double base_y = r.lane_panel_y("WB") + 10;
    assert_has("robust step", svg, vline(r.time_to_x(300), base_y + 0, base_y + 20));
    assert_has("robust step 100", svg, vline(r.time_to_x(100), base_y + 20, base_y + 40));
    // Level names on the left
    assert_has("levels", svg, ">Processing</text>");
    // Concise value bars: hexagon for Idle, open pentagon for the last value
    assert_has("hexa", svg, "<polygon points=\"%s,".printf(num(x0 + 12)));
    assert_has("concise label", svg, ">Waiting</text>");
    // Time axis labels only at used times
    assert_has("axis 300", svg, ">300</text>");
    assert_lacks("axis 200", svg, ">200</text>");
    // Scale overrides the tick unit
    d = parse("scale 100 as 20 pixels\n" + BASIC);
    render_svg(d, out r);
    assert(r.get_tick_unit() == 100 && r.get_tick_pixels() == 20);
    assert(r.time_to_x(300) - r.time_to_x(0) == 60);
}

void test_clock_period() {
    TimingDiagramRenderer r;
    var d = parse("clock \"C\" as C with period 50\n@0\n@300");
    string svg = render_svg(d, out r);
    double y = r.lane_panel_y("C");
    // Square wave: rising and falling edges every half period
    for (int i = 0; i <= 6; i++) {
        assert_has("clock edge %d".printf(i), svg, vline(r.time_to_x(25 * i), y + 8, y + 22));
    }
    // Decimal period with pulse: high for 0.5, low for 1.0
    d = parse("clock \"C\" as C with period 1.5 pulse 0.5\n@0\n@3");
    svg = render_svg(d, out r);
    y = r.lane_panel_y("C");
    assert_has("pulse fall", svg, vline(r.time_to_x(0.5), y + 8, y + 22));
    assert_has("pulse rise", svg, vline(r.time_to_x(1.5), y + 8, y + 22));
    assert_lacks("no edge at 1", svg, vline(r.time_to_x(1), y + 8, y + 22));
}

void test_participant_oriented_equals_time_oriented() {
    TimingDiagramRenderer r;
    string a = render_svg(parse("robust \"WB\" as WB\nconcise \"WU\" as WU\n" +
                                "@WB\n0 is idle\n+200 is busy\n@WU\n0 is Waiting\n+500 is ok"), out r);
    string b = render_svg(parse("robust \"WB\" as WB\nconcise \"WU\" as WU\n" +
                                "@0\nWB is idle\nWU is Waiting\n@200\nWB is busy\n@500\nWU is ok"), out r);
    assert(a == b);
    assert_has("waveform", a, ">busy</text>");
}

void test_binary_and_hidden_states() {
    TimingDiagramRenderer r;
    var d = parse("binary \"EN\" as EN\nconcise \"U\" as U\n" +
                  "@0\nEN is low\nU is {-}\n@5\nEN is high\nU is A1\n@10\nEN is {low,high}\nU is {hidden}\n@15\nEN is low\nU is A3");
    string svg = render_svg(d, out r);
    double y = r.lane_panel_y("EN");
    // Rising edge at 5 from high (y+8) to low (y+22)
    assert_has("binary edge", svg, vline(r.time_to_x(5), y + 8, y + 22));
    // Intricated {low,high}: hatching every 5 px between 10 and 15
    assert_has("hatch", svg, vline(r.time_to_x(10) + 5, y + 8, y + 22));
    // {-} is a flat line through the ribbon middle; {hidden} draws nothing, no "{hidden}" text
    double ry = r.lane_panel_y("U") + 5;
    assert_has("flat", svg, "<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\"".printf(
        num(r.time_to_x(0)), num(ry + 12), num(r.time_to_x(5)), num(ry + 12)));
    assert_lacks("hidden text", svg, "{hidden}");
    assert_lacks("flat text", svg, "{-}");
    assert(count_substr(svg, "<polygon") == 2);  // A1 hexagon + A3 open pentagon (2 shapes)
}

void test_messages_constraints_highlights_notes_render() {
    TimingDiagramRenderer r;
    var d = parse("robust \"WB\" as WB\nconcise \"WU\" as WU\n@0\nWU is Idle\nWB is Idle\n" +
                  "@100\nWU -> WB : URL\nWU is Waiting\nWB is Processing\nWB@0 <-> @100 : {lag}\n" +
                  "highlight 0 to 50 #Gold : hl\nnote top of WU : note text\n@300\nWB is Waiting");
    string svg = render_svg(d, out r);
    // Message: vertical arrow at x(100) from the WU ribbon middle to the nearer WB level (Idle)
    // WU ribbon middle: panel top + min constraint height 5 + top note (1 line + 10 + 10) + ribbon/2
    double wu_mid = r.lane_panel_y("WU") + 5 + TimingTextMetrics.line_height(13, true) + 20 + 12;
    double wb_idle = r.lane_panel_y("WB") + 10 + 40;
    assert_has("message", svg, "<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\"".printf(
        num(r.time_to_x(100)), num(wu_mid), num(r.time_to_x(100)), num(wb_idle),
        ThemeManager.get_active_palette().accent_primary));
    assert_has("message label", svg, ">URL</text>");
    assert_has("constraint label", svg, ">{lag}</text>");
    assert_has("highlight", svg, "fill=\"gold\"");
    assert_has("highlight caption", svg, ">hl</text>");
    assert_has("note", svg, ">note text</text>");
    assert_has("dashed highlight line", svg, "stroke-dasharray=\"4,4\"");
}

void test_axis_formats_and_hide() {
    TimingDiagramRenderer r;
    string svg = render_svg(parse("scale 2592000 as 50 pixels\nconcise \"S\" as S\n@2000/11/01\nS is W\n@2001/02/01\nS is Sp"), out r);
    assert_has("date label", svg, ">11/01</text>");
    assert_has("date tick", svg, ">12/01</text>");
    svg = render_svg(parse("concise \"S\" as S\n@1:15:00\nS is A\n@1:16:30\nS is B"), out r);
    assert_has("hour label", svg, ">1:16:30</text>");
    svg = render_svg(parse("hide time-axis\nconcise \"S\" as S\n@0\nS is A\n@100\nS is B"), out r);
    assert_lacks("hidden axis", svg, ">100</text>");
    svg = render_svg(parse("manual time-axis\nconcise \"S\" as S\n@0 as :start\nS is A\n@100\nS is B"), out r);
    assert_has("manual anchor label", svg, ">start</text>");
}

void test_regions_and_theme() {
    var regions = new Gee.ArrayList<ElementRegion>();
    var r = new TimingDiagramRenderer(new Gvc.Context(), regions, "dot");
    var saved = ThemeManager.get_active_palette();
    var dark = ThemeManager.get_preset("default-dark");
    ThemeManager.set_active_palette(dark);
    string svg = svg_string(r.render_to_svg(parse(BASIC)));
    ThemeManager.set_active_palette(saved);
    assert(regions.size == 2);
    assert(regions[0].name == "WB" && regions[0].source_line == 2);
    assert(regions[1].name == "WU" && regions[1].y == r.lane_frame_y("WU"));
    assert(regions[0].y + regions[0].height == regions[1].y);
    assert_has("dark background", svg, "fill=\"%s\"".printf(dark.background));
    assert_has("dark text", svg, "fill=\"%s\"".printf(dark.node_text));
    var light = ThemeManager.get_preset("default-light");
    assert_lacks("no light background", svg, "fill=\"%s\"".printf(light.background));
}

void test_engine_exports() {
    var engine = new DiagramEngine("dot");
    string src = "@startuml\n" + BASIC + "\n@enduml\n";
    string dir;
    try {
        dir = DirUtils.make_tmp("timing-test-XXXXXX");
    } catch (FileError e) {
        assert_not_reached();
    }
    foreach (var ext in new string[] { "png", "svg", "pdf" }) {
        string path = Path.build_filename(dir, "t." + ext);
        bool ok = false;
        if (ext == "png") ok = engine.export_to_png(src, "t.puml", null, path);
        if (ext == "svg") ok = engine.export_to_svg(src, "t.puml", null, path);
        if (ext == "pdf") ok = engine.export_to_pdf(src, "t.puml", null, path);
        assert(ok);
        assert(FileUtils.test(path, FileTest.EXISTS));
        FileUtils.remove(path);
    }
    DirUtils.remove(dir);
    string? dot = engine.generate_dot(src, "t.puml", null);
    assert(dot != null && dot.has_prefix("digraph"));
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/timing/parser/declarations", test_declarations);
    Test.add_func("/review/timing/parser/time_oriented_states", test_time_oriented_states);
    Test.add_func("/review/timing/parser/participant_oriented", test_participant_oriented_and_initial);
    Test.add_func("/review/timing/parser/dates_hours_anchors", test_dates_hours_anchors);
    Test.add_func("/review/timing/parser/has", test_has_declarations);
    Test.add_func("/review/timing/parser/messages_constraints", test_messages_constraints_highlights_notes);
    Test.add_func("/review/timing/parser/comments_lines", test_source_lines_and_comments);
    Test.add_func("/review/timing/render/ruler_robust", test_ruler_and_robust_transition_x);
    Test.add_func("/review/timing/render/clock", test_clock_period);
    Test.add_func("/review/timing/render/participant_equals_time", test_participant_oriented_equals_time_oriented);
    Test.add_func("/review/timing/render/binary_hidden", test_binary_and_hidden_states);
    Test.add_func("/review/timing/render/decorations", test_messages_constraints_highlights_notes_render);
    Test.add_func("/review/timing/render/axis", test_axis_formats_and_hide);
    Test.add_func("/review/timing/render/regions_theme", test_regions_and_theme);
    Test.add_func("/review/timing/render/engine_exports", test_engine_exports);
    return Test.run();
}
