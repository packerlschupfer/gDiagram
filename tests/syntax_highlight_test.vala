/*
 * syntax_highlight_test.vala — the GtkSourceView language definitions in data/lang.
 *
 * Each case highlights a small document with plantuml.lang / mermaid.lang and checks
 * the style a token gets. Styles are told apart through a generated style scheme that
 * gives every style id of the language ("plantuml:keyword", ...) its own colour.
 * A plain GtkSource.Buffer needs no display. Runs with G_DEBUG=fatal-warnings, so a
 * language file that fails to load (bad XML, a regex that doesn't compile) fails.
 */

GtkSource.LanguageManager language_manager;
GtkSource.StyleSchemeManager scheme_manager;
Gee.HashMap<string, string> color_to_style;

void setup_managers() {
    string? root = Environment.get_variable("GDIAGRAM_SOURCE_ROOT");
    assert(root != null);
    language_manager = new GtkSource.LanguageManager();
    // Our files first; def.lang comes from the library's own search path
    string[] path = { Path.build_filename(root, "data", "lang") };
    foreach (unowned string dir in language_manager.get_search_path()) {
        path += dir;
    }
    language_manager.set_search_path(path);

    color_to_style = new Gee.HashMap<string, string>();
    var scheme = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
        "<style-scheme id=\"gdiagram-highlight-test\" name=\"Test\" version=\"1.0\">\n");
    int n = 1;
    foreach (string lang_id in new string[] { "plantuml", "mermaid" }) {
        var lang = language_manager.get_language(lang_id);
        assert(lang != null);
        // The language must come from the source tree, not an installed copy
        assert(lang.get_metadata("globs") != null);
        foreach (unowned string style_id in lang.get_style_ids()) {
            string color = "#%06x".printf(n++ * 7);
            color_to_style[color] = style_id;
            scheme.append("  <style name=\"%s\" foreground=\"%s\"/>\n".printf(style_id, color));
        }
    }
    scheme.append("</style-scheme>\n");
    try {
        string dir = DirUtils.make_tmp("gdiagram-hl-XXXXXX");
        FileUtils.set_contents(Path.build_filename(dir, "test.xml"), scheme.str);
        scheme_manager = new GtkSource.StyleSchemeManager();
        scheme_manager.set_search_path({ dir });
    } catch (Error e) {
        error("scheme setup: %s", e.message);
    }
}

// The style of the character at `char_offset`, or "" when it has none
string style_at(GtkSource.Buffer buffer, int char_offset) {
    Gtk.TextIter iter;
    buffer.get_iter_at_offset(out iter, char_offset);
    string style = "";
    // Tags come lowest priority first: the innermost context's style wins
    foreach (var tag in iter.get_tags()) {
        if (!tag.foreground_set) continue;
        string color = "#%02x%02x%02x".printf((uint) Math.round(tag.foreground_rgba.red * 255),
                                              (uint) Math.round(tag.foreground_rgba.green * 255),
                                              (uint) Math.round(tag.foreground_rgba.blue * 255));
        if (color_to_style.has_key(color)) style = color_to_style[color];
    }
    return style;
}

int failures = 0;

// `token` (its first occurrence following `after`, when given) must be styled `expected`
// ("plantuml:keyword", or "" for no style) on its first and last character.
void expect(string lang_id, string source, string token, string expected, string? after = null) {
    var buffer = new GtkSource.Buffer.with_language(language_manager.get_language(lang_id));
    buffer.style_scheme = scheme_manager.get_scheme("gdiagram-highlight-test");
    buffer.text = source;
    Gtk.TextIter start, end;
    buffer.get_bounds(out start, out end);
    buffer.ensure_highlight(start, end);

    int from = after != null ? source.index_of(after) : 0;
    assert(from >= 0);
    if (after != null) from += after.length;
    int index = source.index_of(token, from);
    if (index < 0) {
        stderr.printf("token '%s' not in source\n", token);
        failures++;
        return;
    }
    int first = source.substring(0, index).char_count();
    int last = first + token.char_count() - 1;
    string got_first = style_at(buffer, first);
    string got_last = style_at(buffer, last);
    if (got_first != expected || got_last != expected) {
        stderr.printf("[%s] '%s': expected '%s', got '%s' .. '%s'\n", lang_id, token, expected, got_first, got_last);
        failures++;
    }
}

void check_failures() {
    if (failures > 0) {
        stderr.printf("%d highlighting mismatches\n", failures);
        failures = 0;
        Test.fail();
    }
}

const string P = "plantuml";
const string M = "mermaid";

void test_plantuml_timing() {
    string src = "@startuml\n" +
        "concise \"User\" as U\n" +
        "compact robust \"Web\" as W\n" +
        "clock \"Clock\" as CLK with period 50 pulse 15 offset 10\n" +
        "analog \"Volt\" between 0 and 10 as V\n" +
        "V ticks num on multiple 5\n" +
        "scale 100 as 50 pixels\n" +
        "hide time-axis\n" +
        "mode compact\n" +
        "@0 as :start\n" +
        "U is Idle\n" +
        "@W\n" +
        "+50 is Busy\n" +
        "U -> W@100 : ping\n" +
        "U@0 <-> @100 : {100 ms}\n" +
        "highlight 0 to 100 #Gold : Setup\n" +
        "note top of U : a note\n" +
        "@enduml\n";
    expect(P, src, "concise", "plantuml:participant-type");
    expect(P, src, "robust", "plantuml:participant-type");
    expect(P, src, "clock", "plantuml:participant-type");
    expect(P, src, "analog", "plantuml:participant-type");
    expect(P, src, "with period", "plantuml:keyword");
    expect(P, src, "pulse", "plantuml:keyword");
    expect(P, src, "offset", "plantuml:keyword");
    expect(P, src, "between", "plantuml:keyword");
    expect(P, src, "ticks num on multiple", "plantuml:keyword");
    expect(P, src, "pixels", "plantuml:keyword");
    expect(P, src, "hide time-axis", "plantuml:keyword");
    expect(P, src, "mode compact", "plantuml:keyword");
    expect(P, src, "@0", "plantuml:special");
    expect(P, src, ":start", "plantuml:special");
    expect(P, src, "is", "plantuml:keyword", "\nU ");
    expect(P, src, "@W", "plantuml:special");
    expect(P, src, "is", "plantuml:keyword", "+50 ");
    expect(P, src, "<->", "plantuml:arrow");
    expect(P, src, "highlight", "plantuml:keyword");
    expect(P, src, "#Gold", "plantuml:color");
    expect(P, src, "Idle", "", "U is ");
    check_failures();
}

void test_plantuml_gantt() {
    string src = "@startgantt\n" +
        "Project starts 2026-01-05\n" +
        "printscale weekly zoom 2\n" +
        "language de\n" +
        "hide ressources names\n" +
        "saturday are closed\n" +
        "2026-01-19 is closed\n" +
        "today is 2026-01-08 and is colored in #AAF\n" +
        "[Design] as [D] lasts 5 days\n" +
        "[Build] requires 3 days\n" +
        "[Build] starts at [Design]'s end\n" +
        "then [Test] requires 2 days\n" +
        "-- Phase 2 --\n" +
        "[Staffed] on {Alice:50%} {Bob} lasts 4 days\n" +
        "[Release] happens at [Build]'s end\n" +
        "[Design] is 40% completed\n" +
        "[Build] is colored in LightBlue\n" +
        "[Design] -> [Build]\n" +
        "' a comment\n" +
        "@endgantt\n";
    expect(P, src, "@startgantt", "plantuml:directive");
    expect(P, src, "Project starts", "plantuml:keyword");
    expect(P, src, "printscale", "plantuml:keyword");
    expect(P, src, "zoom", "plantuml:keyword");
    expect(P, src, "language", "plantuml:keyword");
    expect(P, src, "hide ressources names", "plantuml:keyword");
    expect(P, src, "are closed", "plantuml:keyword");
    expect(P, src, "is closed", "plantuml:keyword");
    expect(P, src, "today is", "plantuml:keyword");
    expect(P, src, "is colored in", "plantuml:keyword");
    expect(P, src, "[Design]", "plantuml:participant-type");
    expect(P, src, "lasts", "plantuml:keyword");
    expect(P, src, "requires", "plantuml:keyword");
    expect(P, src, "starts", "plantuml:keyword", "3 days\n[Build] ");
    expect(P, src, "'s end", "plantuml:keyword", "[Build] starts");
    expect(P, src, "then", "plantuml:keyword");
    expect(P, src, "[Test]", "plantuml:participant-type");
    expect(P, src, "-- Phase 2 --", "plantuml:special");
    expect(P, src, "{Alice:50%} {Bob}", "plantuml:special");
    expect(P, src, "happens", "plantuml:keyword");
    expect(P, src, "is 40% completed", "plantuml:keyword");
    expect(P, src, "' a comment", "plantuml:comment");
    check_failures();
}

void test_plantuml_c4() {
    string src = "@startuml\n" +
        "!include <C4/C4_Container>\n" +
        "Person(user, \"User\", \"A user\")\n" +
        "System_Ext(ext, \"External\")\n" +
        "System_Boundary(sb, \"Shop\") {\n" +
        "  ContainerDb(db, \"Database\", \"SQL\")\n" +
        "}\n" +
        "Rel_U(user, db, \"Reads\")\n" +
        "BiRel(user, ext, \"Syncs\")\n" +
        "AddElementTag(\"critical\", $bgColor=\"#C00000\")\n" +
        "UpdateRelStyle(\"red\", \"blue\")\n" +
        "LAYOUT_LEFT_RIGHT()\n" +
        "SHOW_LEGEND()\n" +
        "Business_Actor(actor, \"Actor\")\n" +
        "@enduml\n";
    expect(P, src, "!include", "plantuml:preprocessor");
    expect(P, src, "<C4/C4_Container>", "plantuml:string");
    foreach (string macro in new string[] { "Person", "System_Ext", "System_Boundary", "ContainerDb", "Rel_U",
                                             "BiRel", "AddElementTag", "UpdateRelStyle", "LAYOUT_LEFT_RIGHT",
                                             "SHOW_LEGEND", "Business_Actor" }) {
        expect(P, src, macro, "plantuml:macro");
    }
    // A name that only looks like a macro, without a call, stays plain
    expect(P, "@startuml\nPerson -> System : hi\n@enduml\n", "System", "");
    check_failures();
}

void test_plantuml_sequence() {
    string src = "@startuml\n" +
        "autonumber \"<b>[000]\"\n" +
        "autoactivate on\n" +
        "participant Last order 10\n" +
        "{start} Alice -> Bob : call << (C,#FF7700) >>\n" +
        "return done\n" +
        "[-> Alice : incoming\n" +
        "Alice ->] : outgoing\n" +
        "?-> Bob : short\n" +
        "hnote over Alice : idle\n" +
        "rnote over Bob : busy\n" +
        "activate Bob #Gold\n" +
        "newpage Second\n" +
        "ignore newpage\n" +
        "Alice -> Bob : it's fine\n" +
        "@enduml\n";
    expect(P, src, "autonumber", "plantuml:keyword");
    expect(P, src, "autoactivate on", "plantuml:keyword");
    expect(P, src, "order", "plantuml:keyword");
    expect(P, src, "{start}", "plantuml:keyword");
    expect(P, src, "return", "plantuml:keyword");
    expect(P, src, "[->", "plantuml:arrow");
    expect(P, src, "->]", "plantuml:arrow");
    expect(P, src, "?->", "plantuml:arrow");
    expect(P, src, "hnote", "plantuml:note-keyword");
    expect(P, src, "rnote", "plantuml:note-keyword");
    expect(P, src, "<< (C,#FF7700) >>", "plantuml:stereotype");
    expect(P, src, "#Gold", "plantuml:color");
    expect(P, src, "newpage", "plantuml:keyword");
    expect(P, src, "ignore newpage", "plantuml:keyword");
    // A quote inside a message is not a comment
    expect(P, src, "fine", "", "it's");
    check_failures();
}

void test_plantuml_state_class_component() {
    string state = "@startuml\n" +
        "state Active {\n" +
        "  [*] --> Running\n" +
        "  --\n" +
        "  [*] --> Logging\n" +
        "  ||\n" +
        "  state entry1 <<entryPoint>>\n" +
        "  state recv <<sdlreceive>>\n" +
        "}\n" +
        "Idle --> Active[H*]\n" +
        "Idle --> Active\n" +
        "note on link\n" +
        "  resumes\n" +
        "end note\n" +
        "@enduml\n";
    expect(P, state, "--", "plantuml:special", "Running\n");
    expect(P, state, "||", "plantuml:special");
    expect(P, state, "<<entryPoint>>", "plantuml:special");
    expect(P, state, "<<sdlreceive>>", "plantuml:special");
    expect(P, state, "[H*]", "plantuml:special");
    expect(P, state, "note on link", "plantuml:note-keyword");
    expect(P, state, "state", "plantuml:participant-type");

    string cls = "@startuml\n" +
        "set separator ::\n" +
        "hide empty members\n" +
        "show Foo methods\n" +
        "dataclass Point {\n" +
        "  {field} x : int\n" +
        "  {method} norm()\n" +
        "}\n" +
        "exception AppError #back:pink;line:red\n" +
        "class Child extends Base, Other\n" +
        "Provided ()- Point\n" +
        "@enduml\n";
    expect(P, cls, "set separator", "plantuml:keyword");
    expect(P, cls, "hide empty members", "plantuml:keyword");
    expect(P, cls, "show Foo methods", "plantuml:keyword");
    expect(P, cls, "dataclass", "plantuml:participant-type");
    expect(P, cls, "{field}", "plantuml:builtin");
    expect(P, cls, "{method}", "plantuml:builtin");
    expect(P, cls, "exception", "plantuml:participant-type");
    expect(P, cls, "#back:pink;line:red", "plantuml:color");
    expect(P, cls, "extends", "plantuml:participant-type");
    expect(P, cls, "()-", "plantuml:keyword");

    string comp = "@startuml\n" +
        "actor/ \"Business\" as B\n" +
        "usecase/ \"Goal\" as G\n" +
        "queue Jobs\n" +
        "component Server {\n" +
        "  portin in1\n" +
        "}\n" +
        "B -[thickness=3]-> Jobs\n" +
        "legend right\n" +
        "  text\n" +
        "endlegend\n" +
        "@enduml\n";
    expect(P, comp, "actor/", "plantuml:participant-type");
    expect(P, comp, "usecase/", "plantuml:participant-type");
    expect(P, comp, "queue", "plantuml:participant-type");
    expect(P, comp, "portin", "plantuml:participant-type");
    expect(P, comp, "-[thickness=3]->", "plantuml:arrow");
    expect(P, comp, "legend", "plantuml:note-keyword");
    check_failures();
}

void test_plantuml_other_types() {
    string activity = "@startuml\nstart\nsplit\n  :A;\nsplit again\n  :B;\nend split\n:C;\nend\n@enduml\n";
    expect(P, activity, "split", "plantuml:control-flow");
    expect(P, activity, "end", "plantuml:control-flow", ":C;");

    expect(P, "@startboard\nTodo\n+ Card\n++ Sub\n@endboard\n", "@startboard", "plantuml:directive");
    expect(P, "@startboard\nTodo\n+ Card\n++ Sub\n@endboard\n", "++", "plantuml:special");

    string chen = "@startchen\nentity Person {\n  Id <<key>>\n}\nrelationship Owns {\n}\nPerson -N- Owns\n@endchen\n";
    expect(P, chen, "@startchen", "plantuml:directive");
    expect(P, chen, "-N-", "plantuml:arrow");
    expect(P, chen, "relationship", "plantuml:participant-type");
    expect(P, chen, "<<key>>", "plantuml:stereotype");

    string nw = "@startnwdiag\nnwdiag {\n  network dmz {\n    address = \"210.x.x.x/24\"\n" +
        "    web01 [address = \"210.x.x.1\"];\n  }\n}\n@endnwdiag\n";
    expect(P, nw, "@startnwdiag", "plantuml:directive");
    expect(P, nw, "nwdiag", "plantuml:keyword", "@startnwdiag\n");
    expect(P, nw, "network", "plantuml:keyword");
    expect(P, nw, "address", "plantuml:keyword");

    string packet = "@startpacketdiag\npacketdiag {\n  colwidth = 32\n  0-15: Source Port\n}\n@endpacketdiag\n";
    expect(P, packet, "colwidth", "plantuml:keyword");
    expect(P, packet, "0-15", "plantuml:special");

    expect(P, "@startsalt\n{T\n + Root\n}\n@endsalt\n", "{T", "plantuml:special");
    expect(P, "@startebnf\nrule = \"a\" ;\n@endebnf\n", "@startebnf", "plantuml:directive");
    expect(P, "@startregex\n[a-z]+\n@endregex\n", "@endregex", "plantuml:directive");
    expect(P, "@startuml\narchimate #Business \"Customer\" as c <<business-actor>>\n@enduml\n",
           "archimate", "plantuml:participant-type");
    expect(P, "@startchronology\n[Release] happens on 2026-03-01\n@endchronology\n", "happens", "plantuml:keyword");
    check_failures();
}

void test_mermaid() {
    expect(M, "%%{init: {\"theme\": \"forest\"}}%%\nflowchart TD\n  A --> B\n", "%%{init", "mermaid:diagram-type");
    expect(M, "%% note\nflowchart TD\n", "%% note", "mermaid:comment");
    string flow = "flowchart LR\n  A@{ shape: rounded, label: \"Start\" } --> B\n";
    expect(M, flow, "flowchart", "mermaid:diagram-type");
    expect(M, flow, "shape", "mermaid:keyword");
    expect(M, flow, "label", "mermaid:keyword");
    expect(M, flow, "\"Start\"", "mermaid:string");

    foreach (string header in new string[] { "architecture-beta", "block-beta", "packet-beta", "radar-beta",
                                              "treemap-beta", "kanban", "mindmap", "timeline", "quadrantChart",
                                              "xychart-beta", "sankey-beta", "requirementDiagram", "C4Context",
                                              "zenuml", "stateDiagram-v2", "gitGraph" }) {
        expect(M, header + "\n", header, "mermaid:diagram-type");
    }

    string arch = "architecture-beta\n  group api(cloud)[API]\n  service db(database)[Database] in api\n" +
        "  junction j1\n  db:L -- R:j1\n";
    expect(M, arch, "group", "mermaid:keyword");
    expect(M, arch, "service", "mermaid:keyword");
    expect(M, arch, "in", "mermaid:keyword", "[Database]");
    expect(M, arch, "junction", "mermaid:keyword");

    string gantt = "gantt\n  dateFormat YYYY-MM-DD\n  axisFormat %d\n  excludes weekends\n  section Work\n" +
        "  Task :done, a1, 2026-01-05, 3d\n  Next :crit, after a1, 2d\n";
    expect(M, gantt, "dateFormat", "mermaid:keyword");
    expect(M, gantt, "axisFormat", "mermaid:keyword");
    expect(M, gantt, "excludes", "mermaid:keyword");
    expect(M, gantt, "section", "mermaid:keyword");
    expect(M, gantt, "done", "mermaid:keyword");
    expect(M, gantt, "crit", "mermaid:keyword");
    expect(M, gantt, "after", "mermaid:keyword");

    string radar = "radar-beta\n  axis A, B, C\n  curve c1{1, 2, 3}\n  max 5\n  showLegend true\n";
    expect(M, radar, "axis", "mermaid:keyword");
    expect(M, radar, "curve", "mermaid:keyword");
    expect(M, radar, "max", "mermaid:keyword");

    string kanban = "kanban\n  Todo\n    t1[Write docs]@{ assigned: 'alice', ticket: 42, priority: 'High' }\n";
    expect(M, kanban, "assigned", "mermaid:keyword");
    expect(M, kanban, "priority", "mermaid:keyword");

    string block = "block-beta\n  columns 3\n  a b c\n  space\n";
    expect(M, block, "columns", "mermaid:keyword");
    expect(M, block, "space", "mermaid:keyword");

    string git = "gitGraph\n  commit id: \"a\"\n  branch dev\n  checkout dev\n  merge main\n";
    expect(M, git, "commit", "mermaid:keyword");
    expect(M, git, "branch", "mermaid:keyword");
    expect(M, git, "checkout", "mermaid:keyword");

    string c4 = "C4Context\n  Person(user, \"User\")\n  System_Ext(ext, \"Ext\")\n  Rel(user, ext, \"Uses\")\n";
    expect(M, c4, "Person", "mermaid:node-id");
    expect(M, c4, "System_Ext", "mermaid:node-id");
    expect(M, c4, "Rel", "mermaid:node-id", "System_Ext(ext, \"Ext\")\n");

    string req = "requirementDiagram\n  requirement r1 {\n    id: 1\n    risk: high\n  }\n  element e1\n  e1 - satisfies -> r1\n";
    expect(M, req, "requirement", "mermaid:keyword", "Diagram\n");
    expect(M, req, "risk", "mermaid:keyword");
    expect(M, req, "satisfies", "mermaid:keyword");

    string seq = "sequenceDiagram\n  box Aqua Group\n  participant A\n  end\n  create participant B\n  A->>B: hi\n";
    expect(M, seq, "box", "mermaid:keyword");
    expect(M, seq, "create", "mermaid:keyword");
    expect(M, seq, "->>", "mermaid:arrow");
    check_failures();
}

// Constructs highlighted before the new rules keep their styles
void test_plantuml_unchanged() {
    string src = "@startuml\n" +
        "skinparam backgroundColor #FFFFFF\n" +
        "' comment\n" +
        "class Foo <<Entity>> {\n" +
        "  +name : String\n" +
        "  -id : int\n" +
        "}\n" +
        "Foo --> Bar : uses **bold** text\n" +
        "alt ok\n" +
        "  Alice -> Bob : \"quoted\"\n" +
        "end\n" +
        "note left of Foo : text\n" +
        "@enduml\n";
    expect(P, src, "skinparam", "plantuml:keyword");
    expect(P, src, "#FFFFFF", "plantuml:color");
    expect(P, src, "' comment", "plantuml:comment");
    expect(P, src, "class", "plantuml:participant-type");
    expect(P, src, "<<Entity>>", "plantuml:stereotype");
    expect(P, src, "+", "plantuml:keyword", "{\n  ");
    expect(P, src, "-", "plantuml:keyword", "String\n  ");
    expect(P, src, "-->", "plantuml:arrow");
    expect(P, src, "**bold**", "plantuml:creole");
    expect(P, src, "alt", "plantuml:group-keyword");
    expect(P, src, "\"quoted\"", "plantuml:string");
    expect(P, src, "note", "plantuml:note-keyword");
    expect(P, src, "@enduml", "plantuml:directive");
    check_failures();
}

int main(string[] args) {
    Test.init(ref args);
    GtkSource.init();
    setup_managers();
    Test.add_func("/highlight/plantuml/timing", test_plantuml_timing);
    Test.add_func("/highlight/plantuml/gantt", test_plantuml_gantt);
    Test.add_func("/highlight/plantuml/c4", test_plantuml_c4);
    Test.add_func("/highlight/plantuml/sequence", test_plantuml_sequence);
    Test.add_func("/highlight/plantuml/state-class-component", test_plantuml_state_class_component);
    Test.add_func("/highlight/plantuml/other-types", test_plantuml_other_types);
    Test.add_func("/highlight/mermaid", test_mermaid);
    Test.add_func("/highlight/plantuml/unchanged", test_plantuml_unchanged);
    return Test.run();
}
