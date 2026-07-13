// Activity diagram review findings: parser structure (if/else, loops, break),
// partitions, groups and lanes, and renderer layout/colour details.
// Each test was checked to fail without its fix.

string engine_dot(string source) {
    var engine = new GDiagram.DiagramEngine("dot");
    string? dot = engine.generate_dot(source, "test.puml", null);
    assert(dot != null);
    return dot;
}

void fail_with(string label, string message, string dot) {
    stderr.printf("[%s] %s in:\n%s\n", label, message, dot);
    assert_not_reached();
}

void assert_has(string label, string dot, string needle) {
    if (!dot.contains(needle)) {
        fail_with(label, "missing '%s'".printf(needle), dot);
    }
}

void assert_lacks(string label, string dot, string needle) {
    if (dot.contains(needle)) {
        fail_with(label, "unexpected '%s'".printf(needle), dot);
    }
}

int count_substr(string hay, string needle) {
    int n = 0;
    int pos = 0;
    while ((pos = hay.index_of(needle, pos)) >= 0) {
        n++;
        pos += needle.length;
    }
    return n;
}

// Node id of the action "<td>text</td>" or the node with label="text"
string node_id(string label, string dot, string text) {
    foreach (string line in dot.split("\n")) {
        string l = line.strip();
        if (l.has_prefix("node") && (l.contains("<td>%s</td>".printf(text)) || l.contains("label=\"%s\"".printf(text)))) {
            return l.split(" ")[0];
        }
    }
    fail_with(label, "no node '%s'".printf(text), dot);
    return "";
}

// The edge statement from -> to (any ports), or null
string? edge_line(string dot, string from, string to) {
    foreach (string line in dot.split("\n")) {
        string l = line.strip();
        string[] parts = l.split(" -> ");
        if (parts.length != 2) {
            continue;
        }
        string head = parts[1].split(" ")[0].split(":")[0].replace(";", "");
        if (parts[0].split(":")[0] == from && head == to) {
            return l;
        }
    }
    return null;
}

string edge(string label, string dot, string from, string to) {
    string? e = edge_line(dot, from, to);
    if (e == null) {
        fail_with(label, "no edge %s -> %s".printf(from, to), dot);
    }
    return e;
}

// Ids of the nodes a node points to (visible edges)
Gee.ArrayList<string> successors(string dot, string from) {
    var result = new Gee.ArrayList<string>();
    foreach (string line in dot.split("\n")) {
        string l = line.strip();
        string[] parts = l.split(" -> ");
        if (parts.length == 2 && parts[0].split(":")[0] == from && !l.contains("invis")) {
            result.add(parts[1].split(" ")[0].split(":")[0].replace(";", ""));
        }
    }
    return result;
}

// The body of the cluster whose label line is `label="title";`, from `start`
string cluster_body(string label, string dot, string title, int start = 0) {
    int at = dot.index_of("label=\"%s\";".printf(title), start);
    if (at < 0) {
        fail_with(label, "no cluster '%s'".printf(title), dot);
    }
    // Nearest "subgraph cluster_" before the label (string.last_index_of searches
    // forward from its start index)
    int open = 0;
    int next = dot.index_of("subgraph cluster_", 0);
    while (next >= 0 && next < at) {
        open = next;
        next = dot.index_of("subgraph cluster_", next + 1);
    }
    // Matching closing brace
    int depth = 0;
    for (int i = dot.index_of("{", open); i < dot.length; i++) {
        if (dot[i] == '{') depth++;
        if (dot[i] == '}') {
            depth--;
            if (depth == 0) {
                return dot.substring(open, i - open + 1);
            }
        }
    }
    return dot.substring(open);
}

// x positions from Graphviz's plain output
Gee.HashMap<string, double?> layout_x(string dot) {
    var result = new Gee.HashMap<string, double?>();
    string path;
    try {
        int fd = FileUtils.open_tmp("review_activity_XXXXXX.dot", out path);
        FileStream.fdopen(fd, "w");
        FileUtils.set_contents(path, dot);
        string output;
        int status;
        Process.spawn_sync(null, { "dot", "-Tplain", path }, null, SpawnFlags.SEARCH_PATH, null, out output, null, out status);
        FileUtils.unlink(path);
        foreach (string line in output.split("\n")) {
            string[] f = line.split(" ");
            if (f.length > 3 && f[0] == "node") {
                result.set(f[1], double.parse(f[2]));
            }
        }
    } catch (Error e) {
        assert_not_reached();
    }
    return result;
}

// 1. "#pink:if needed, retry;" is a coloured action, not a condition
void test_color_prefix_keyword_action() {
    string dot = engine_dot("@startuml\nstart\n#pink:if needed, retry;\n:next;\n#lightblue:while waiting, poll;\n:last;\nstop\n@enduml");
    assert_lacks("keyword action", dot, "shape=hexagon");
    assert_has("keyword action", dot, "<td>if needed, retry</td>");
    assert_has("keyword action", dot, "<td>while waiting, poll</td>");

    string cond = engine_dot("@startuml\nstart\n#pink:if (x?) then (yes)\n  :a;\nendif\nstop\n@enduml");
    assert_has("coloured if", cond, "shape=hexagon, style=\"filled\", fillcolor=\"pink\"");
}

// 2. Lanes stay left to right in declaration order
void test_lane_declaration_order() {
    string dot = engine_dot("@startuml\n|Left|\n|Middle|\n|Right|\n|Right|\nstart\n:r1;\n|Middle|\n:m1;\n|Left|\n:l1;\n|Right|\n:r2;\nstop\n@enduml");
    var x = layout_x(dot);
    assert(x.has_key("lane_top_0") && x.has_key("lane_top_1") && x.has_key("lane_top_2"));
    if (!(x["lane_top_0"] < x["lane_top_1"] && x["lane_top_1"] < x["lane_top_2"])) {
        fail_with("lane order", "lanes out of order %f %f %f".printf(x["lane_top_0"], x["lane_top_1"], x["lane_top_2"]), dot);
    }
    int left = dot.index_of("label=\"Left\";");
    int middle = dot.index_of("label=\"Middle\";");
    int right = dot.index_of("label=\"Right\";");
    assert(left < middle && middle < right);

    // "|A| Alpha" titles lane A; a later "|Alpha|" is a lane of its own
    string titled = engine_dot("@startuml\n|A|\nstart\n:one;\n|B|\n:two;\n|A| Alpha\n:three;\n|Alpha|\n:four;\nstop\n@enduml");
    assert(count_substr(titled, "labeljust=c;") == 3);
    string first = cluster_body("titled", titled, "Alpha");
    assert_has("titled", first, "<td>three</td>");
    assert_lacks("titled", first, "<td>four</td>");
}

// 3. Partitions and groups with the same name are separate boxes
void test_same_name_blocks_separate() {
    string dot = engine_dot("@startuml\n|A|\nstart\npartition Setup {\n  :a1;\n}\n|B|\npartition Setup {\n  :b1;\n}\nstop\n@enduml");
    assert(count_substr(dot, "label=\"Setup\";") == 2);
    string lane_a = cluster_body("lane A", dot, "A");
    string lane_b = cluster_body("lane B", dot, "B");
    assert_has("setup in A", lane_a, "label=\"Setup\";");
    assert_has("setup in A", lane_a, "<td>a1</td>");
    assert_lacks("setup in A", lane_a, "<td>b1</td>");
    assert_has("setup in B", lane_b, "label=\"Setup\";");
    assert_has("setup in B", lane_b, "<td>b1</td>");

    string grp = engine_dot("@startuml\nstart\ngroup Same {\n  :a;\n}\npartition Same {\n  :b;\n}\ngroup X {\n  partition X {\n    :c;\n  }\n}\nstop\n@enduml");
    assert(count_substr(grp, "label=\"Same\";") == 2);
    assert(count_substr(grp, "label=\"X\";") == 2);
    string first = cluster_body("group", grp, "Same");
    assert_has("group", first, "<td>a</td>");
    assert_lacks("group", first, "<td>b</td>");
    string outer_x = cluster_body("nested", grp, "X");
    assert(count_substr(outer_x, "subgraph cluster_") == 2);
}

// 4. A partition named like a lane title is a box inside the current lane
void test_partition_named_like_lane_title() {
    string dot = engine_dot("@startuml\n|a| Build\nstart\n:compile;\n|b| Test\npartition Build {\n  :unit;\n}\nstop\n@enduml");
    assert(count_substr(dot, "labeljust=c;") == 2);
    string test_lane = cluster_body("lane", dot, "Test");
    assert_has("partition in Test", test_lane, "label=\"Build\";");
    assert_has("partition in Test", test_lane, "<td>unit</td>");
    string build_lane = cluster_body("lane", dot, "Build");
    assert_lacks("Build lane", build_lane, "<td>unit</td>");
}

// 5. An edge label between backgrounds needing different text gets a patch
void test_edge_label_contrast_between_lanes() {
    string dot = engine_dot("@startuml\n|#AntiqueWhite|Shop|\nstart\n:Check;\n-> to dark;\n|#DarkBlue|Dark|\n:Pack;\n-> back;\n|Plain|\n:Store;\n-> into dark;\n|Dark|\n:Ship;\nstop\n@enduml");
    string check = node_id("label", dot, "Check");
    string pack = node_id("label", dot, "Pack");
    string store = node_id("label", dot, "Store");
    string ship = node_id("label", dot, "Ship");
    // beige -> dark blue: a beige patch with black text
    string e1 = edge("beige to dark", dot, check, pack);
    assert_has("beige to dark", e1, "bgcolor=\"AntiqueWhite\"><tr><td>to dark</td>");
    assert_has("beige to dark", e1, "fontcolor=\"#000000\"");
    // light theme canvas -> dark blue: a canvas patch with the theme's dark text
    string e3 = edge("plain to dark", dot, store, ship);
    assert_has("plain to dark", e3, "bgcolor=\"#FAFAFA\"><tr><td>into dark</td>");
    // dark blue -> plain: same text colour needed? white vs dark: patched too
    string e2 = edge("dark to plain", dot, pack, store);
    assert_has("dark to plain", e2, "bgcolor=\"DarkBlue\"><tr><td>back</td>");
    assert_has("dark to plain", e2, "fontcolor=\"#FFFFFF\"");
}

// 6. Merges of a switch / "end merge" with one continuing branch stay diamonds;
//    a repeat exit is still invisible
void test_real_merges_not_hidden() {
    string sw = engine_dot("@startuml\nstart\nswitch (mode?)\ncase (A)\n  :a;\ncase (B)\n  :b;\n  stop\nendswitch\n:after;\nstop\n@enduml");
    assert(count_substr(sw, "shape=diamond") == 1);
    string fk = engine_dot("@startuml\nstart\nfork\n  :a;\nfork again\n  :b;\n  stop\nend merge\n:after;\nstop\n@enduml");
    assert(count_substr(fk, "shape=diamond") == 1);
    string rep = engine_dot("@startuml\nstart\nrepeat\n  :a;\nrepeat while (more?)\n:done;\nstop\n@enduml");
    assert(count_substr(rep, "shape=diamond") == 1);  // the repeat start only
    assert(count_substr(rep, "shape=point, style=invis") == 1);
}

// 7. "#7" is not a colour
void test_group_hash_number_is_text() {
    string dot = engine_dot("@startuml\nstart\ngroup Issue #7\n  :b;\nend group\nstop\n@enduml");
    assert_has("group name", dot, "label=\"Issue #7\";");
    assert_lacks("group colour", dot, "\"#7\"");
    string col = engine_dot("@startuml\nstart\ngroup Tail #LightBlue\n  :b;\nend group\ngroup #F00 Head\n  :c;\nend group\nstop\n@enduml");
    assert_has("group colour", col, "label=\"Tail\";");
    assert_has("group colour", col, "fillcolor=\"LightBlue\";");
    assert_has("group colour", col, "label=\"Head\";");
}

// 8. Notes sit next to their node inside its lane
void test_notes_inside_lanes() {
    string dot = engine_dot("@startuml\n|A|\nstart\n:a;\nnote right: note on a\n|B|\n:b;\nnote left\n  left note on b\nend note\n|C|\n:c;\nstop\n@enduml");
    string lane_a = cluster_body("lane A", dot, "A");
    string lane_b = cluster_body("lane B", dot, "B");
    assert_has("note in A", lane_a, "label=\"note on a\"");
    assert_has("note in B", lane_b, "label=\"left note on b\"");
    var x = layout_x(dot);
    string a = node_id("a", dot, "a");
    string b = node_id("b", dot, "b");
    if (!(x["note0"] > x[a] && x["note1"] < x[b])) {
        fail_with("note sides", "right note left of its node or left note right of it", dot);
    }
    if (!(x["note0"] < x["lane_top_1"] && x["note1"] > x["lane_top_0"] && x["note1"] < x["lane_top_2"])) {
        fail_with("note lanes", "note outside its lane", dot);
    }
}

// 9. A lane switch inside a group persists after the group
void test_lane_switch_inside_group() {
    string dot = engine_dot("@startuml\n|A|\nstart\ngroup G {\n  :a;\n  |B|\n  :b;\n}\n:after;\nstop\n@enduml");
    string lane_a = cluster_body("lane A", dot, "A");
    string lane_b = cluster_body("lane B", dot, "B");
    assert_has("after in B", lane_b, "<td>after</td>");
    assert_lacks("after not in A", lane_a, "<td>after</td>");
    assert_has("group in A", lane_a, "label=\"G\";");
    assert_has("group in B", lane_b, "label=\"G\";");
    string group_b = cluster_body("group in B", lane_b, "G");
    assert_has("b in group", group_b, "<td>b</td>");
    assert_lacks("after outside group", group_b, "<td>after</td>");
}

// 10. Empty declared lane, repeat at the end, gradient note, coloured if merge
void test_minor_details() {
    string empty = engine_dot("@startuml\n|Empty|\n|B|\nstart\n:x;\n|C|\n:y;\n|#pink|B|\n:z;\nstop\n@enduml");
    assert_has("empty lane", empty, "label=\"Empty\";");
    assert_has("empty lane", cluster_body("empty lane", empty, "Empty"), "lane_top_0 [");

    string end = engine_dot("@startuml\nstart\nrepeat\n  :a;\nrepeat while (more?) is (yes) not (no)\n@enduml");
    string cond = node_id("repeat end", end, "more?");
    bool exit_found = false;
    foreach (string s in successors(end, cond)) {
        string e = edge("repeat end", end, cond, s);
        if (e.contains("label=\"no\"")) {
            exit_found = true;
            assert_has("repeat end exit line hidden", e, "color=\"transparent\"");
        }
    }
    assert(exit_found);

    string note = engine_dot("@startuml\nstart\n:a;\nnote left #red/white\n  gradient note\nend note\nstop\n@enduml");
    string note_line = "";
    foreach (string line in note.split("\n")) {
        if (line.contains("gradient note")) note_line = line;
    }
    assert_has("note gradient", note_line, "fillcolor=\"red:white\"");
    assert_has("note gradient", note_line, "gradientangle=315");

    string merge = engine_dot("@startuml\nstart\n#yellow:if (x?) then (yes)\n  :b;\nelse (no)\n  :c;\nendif\nstop\n@enduml");
    assert_has("merge colour", merge, "shape=diamond, style=\"filled\", fillcolor=\"yellow\"");
}

// 11. A nested if doesn't swallow the outer else/endif
void test_nested_if_keeps_outer_else() {
    string dot = engine_dot("@startuml\nstart\nif (a?) then (yes)\n  if (b?) then (yes)\n    :x;\n  endif\n  :y;\nelse (no)\n  :z;\nendif\n:after;\nstop\n@enduml");
    string a = node_id("nested", dot, "a?");
    string z = node_id("nested", dot, "z");
    string y = node_id("nested", dot, "y");
    string after = node_id("nested", dot, "after");
    assert_has("outer else", edge("outer else", dot, a, z), "label=\"no\"");
    // y and z join in a merge that continues to "after"
    var y_next = successors(dot, y);
    var z_next = successors(dot, z);
    assert(y_next.size == 1 && z_next.size == 1 && y_next[0] == z_next[0]);
    edge("after merge", dot, y_next[0], after);
}

// 12. An if without else keeps its "no" path into a merge
void test_if_without_else_no_path() {
    string dot = engine_dot("@startuml\nstart\nif (c?) then (yes)\n  :a;\nendif\n:b;\nstop\n@enduml");
    string c = node_id("no else", dot, "c?");
    string a = node_id("no else", dot, "a");
    string b = node_id("no else", dot, "b");
    var c_next = successors(dot, c);
    var a_next = successors(dot, a);
    assert(c_next.size == 2);
    assert(a_next.size == 1 && c_next.contains(a_next[0]));
    assert_has("merge", dot, "%s [shape=diamond".printf(a_next[0]));
    edge("merge to b", dot, a_next[0], b);
}

// 13. The repeat condition is reached after an if ending in stop, or a while
bool reaches(string dot, string from, string to, int depth = 0) {
    if (from == to) return true;
    if (depth > 20) return false;
    foreach (string s in successors(dot, from)) {
        if (reaches(dot, s, to, depth + 1)) return true;
    }
    return false;
}

void test_repeat_condition_reached() {
    string kill = engine_dot("@startuml\nstart\nrepeat\n  :a;\n  if (fatal?) then (yes)\n    stop\n  endif\nrepeat while (more?) is (yes) not (no)\n:done;\nstop\n@enduml");
    string fatal = node_id("repeat kill", kill, "fatal?");
    string more = node_id("repeat kill", kill, "more?");
    edge("fatal to more", kill, fatal, more);

    string wh = engine_dot("@startuml\nstart\nrepeat\n  :a;\n  while (inner?) is (yes)\n    :b;\n  endwhile (no)\nrepeat while (outer?) is (yes) not (no)\n:done;\nstop\n@enduml");
    string inner = node_id("repeat while", wh, "inner?");
    string outer = node_id("repeat while", wh, "outer?");
    assert_has("inner exit", edge("inner to outer", wh, inner, outer), "label=\"no\"");
}

// 14. endwhile / empty else labels survive; break draws no box
void test_pending_labels_and_break() {
    string wh = engine_dot("@startuml\nstart\nwhile (data?) is (yes)\n  :read;\nendwhile (no)\nstop\n@enduml");
    string data = node_id("endwhile", wh, "data?");
    bool labelled = false;
    foreach (string s in successors(wh, data)) {
        if (edge("endwhile", wh, data, s).contains("label=\"no\"")) labelled = true;
    }
    if (!labelled) fail_with("endwhile label", "no 'no' label", wh);

    string el = engine_dot("@startuml\nstart\nif (c?) then (no)\n  :a;\n  stop\nelse (yes)\nendif\n:b;\n@enduml");
    string c = node_id("empty else", el, "c?");
    string b = node_id("empty else", el, "b");
    assert_has("empty else label", edge("empty else", el, c, b), "label=\"yes\"");

    string brk = engine_dot("@startuml\nstart\nrepeat\n  :a;\n  if (err?) then (yes)\n    :log;\n    break\n  endif\n  :b;\nrepeat while (more?)\n:done;\nstop\n@enduml");
    assert_lacks("break box", brk, "<td>break</td>");
    string log = node_id("break", brk, "log");
    string done = node_id("break", brk, "done");
    assert(reaches(brk, log, done));
}

// The note with `text` in the parsed activity diagram
GDiagram.ActivityNote find_note(string source, string text) {
    var r = new GDiagram.DiagramEngine("dot").parse(source, "test.puml");
    assert(r.diagram_type == GDiagram.DiagramType.ACTIVITY);
    foreach (var note in ((GDiagram.ActivityDiagram) r.ast).notes) {
        if (note.text == text) return note;
    }
    stderr.printf("no note '%s'\n", text);
    assert_not_reached();
}

// Label (or type name) of the node a note is attached to, "(none)" when unattached
string note_owner(string source, string text) {
    var note = find_note(source, text);
    GDiagram.ActivityNode? node = note.attached_to;
    if (node == null) return "(none)";
    if (node.label != null && node.label.length > 0) return node.label;
    switch (node.node_type) {
        case GDiagram.ActivityNodeType.START: return "START";
        case GDiagram.ActivityNodeType.STOP: return "STOP";
        default: return "type %d".printf((int) node.node_type);
    }
}

void expect_owner(string what, string source, string text, string expected) {
    string owner = note_owner(source, text);
    if (owner != expected) {
        stderr.printf("[%s] note '%s' attached to '%s', expected '%s'\n", what, text, owner, expected);
        assert_not_reached();
    }
}

// 15. A note after a block, a stop or before the first node belongs to the element
// PlantUML 1.2026.1 draws it beside; unattached, it was drawn at the top by the start
void test_notes_after_blocks() {
    expect_owner("endif", "@startuml\nstart\nif (a?) then (yes)\n  :x;\nelse (no)\n  :y;\nendif\nnote right: after the if\n:z;\nstop\n@enduml",
                 "after the if", "a?");
    expect_owner("endwhile", "@startuml\nstart\nwhile (more?) is (yes)\n  :x;\nendwhile (no)\nnote right: after the while\n:z;\nstop\n@enduml",
                 "after the while", "x");
    expect_owner("repeat while", "@startuml\nstart\nrepeat\n  :x;\nrepeat while (again?) is (yes) not (no)\nnote right: after the repeat\n:z;\nstop\n@enduml",
                 "after the repeat", "x");
    expect_owner("endswitch", "@startuml\nstart\nswitch (v?)\ncase (a)\n  :x;\ncase (b)\n  :y;\nendswitch\nnote right: after the switch\n:z;\nstop\n@enduml",
                 "after the switch", "y");
    expect_owner("end group", "@startuml\nstart\ngroup G\n  :x;\nend group\nnote right: after the group\n:z;\nstop\n@enduml",
                 "after the group", "x");
    expect_owner("partition }", "@startuml\nstart\npartition P {\n  :x;\n}\nnote right: after the partition\n:z;\nstop\n@enduml",
                 "after the partition", "x");
    expect_owner("stop", "@startuml\nstart\n:x;\nstop\nnote right: after stop\n@enduml", "after stop", "STOP");
    expect_owner("else start", "@startuml\nstart\nif (a?) then (yes)\n  :x;\nelse (no)\n  note right: in else\n  :y;\nendif\nstop\n@enduml",
                 "in else", "a?");
    var fork = find_note("@startuml\nstart\nfork\n  :x;\nfork again\n  :y;\nend fork\nnote right: after the fork\n:z;\nstop\n@enduml",
                         "after the fork");
    assert(fork.attached_to != null && fork.attached_to.node_type == GDiagram.ActivityNodeType.JOIN);

    // Before any node: above the first one
    string first_src = "@startuml\nnote right: before anything\nstart\n:x;\nstop\n@enduml";
    expect_owner("leading note", first_src, "before anything", "START");
    assert(find_note(first_src, "before anything").position == GDiagram.NotePosition.TOP);

    // A floating note sits beside the previous element without a connector
    string fl = "@startuml\nstart\n:x;\nfloating note left: floating\n:y;\nstop\n@enduml";
    expect_owner("floating", fl, "floating", "x");
    assert(find_note(fl, "floating").floating);
    string dot = engine_dot(fl);
    string x = node_id("floating", dot, "x");
    assert_has("floating beside", dot, "rank=same; %s; note".printf(x));
    assert_lacks("floating connector", dot, "arrowhead=none, constraint=false");
}

// "!pragma useVerticalIf on" survives preprocessing and changes the layout through the engine
void test_vertical_if_pragma_through_engine() {
    string body = "start\nif (a?) then (yes)\n  :x;\nelseif (b?) then (yes)\n  :y;\nelse (no)\n  :z;\nendif\nstop\n@enduml";
    string plain = engine_dot("@startuml\n" + body);
    string vertical = engine_dot("@startuml\n!pragma useVerticalIf on\n" + body);
    assert(plain != vertical);
}

void main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/activity/color_prefix_keyword_action", test_color_prefix_keyword_action);
    Test.add_func("/review/activity/lane_declaration_order", test_lane_declaration_order);
    Test.add_func("/review/activity/same_name_blocks_separate", test_same_name_blocks_separate);
    Test.add_func("/review/activity/partition_named_like_lane_title", test_partition_named_like_lane_title);
    Test.add_func("/review/activity/edge_label_contrast_between_lanes", test_edge_label_contrast_between_lanes);
    Test.add_func("/review/activity/real_merges_not_hidden", test_real_merges_not_hidden);
    Test.add_func("/review/activity/group_hash_number_is_text", test_group_hash_number_is_text);
    Test.add_func("/review/activity/notes_inside_lanes", test_notes_inside_lanes);
    Test.add_func("/review/activity/lane_switch_inside_group", test_lane_switch_inside_group);
    Test.add_func("/review/activity/minor_details", test_minor_details);
    Test.add_func("/review/activity/nested_if_keeps_outer_else", test_nested_if_keeps_outer_else);
    Test.add_func("/review/activity/if_without_else_no_path", test_if_without_else_no_path);
    Test.add_func("/review/activity/repeat_condition_reached", test_repeat_condition_reached);
    Test.add_func("/review/activity/pending_labels_and_break", test_pending_labels_and_break);
    Test.add_func("/review/activity/notes_after_blocks", test_notes_after_blocks);
    Test.add_func("/review/activity/multiline_arrow_label", test_multiline_arrow_label);
    Test.add_func("/review/activity/arrow_style_after_else", test_arrow_style_after_else);
    Test.add_func("/review/activity/end_is_flow_final", test_end_is_flow_final);
    Test.add_func("/review/activity/split_draws_lines", test_split_draws_lines);
    Test.add_func("/review/activity/pipe_is_text", test_pipe_is_text);
    Test.add_func("/review/activity/color_suffix", test_color_suffix);
    Test.add_func("/review/activity/repeated_spaces_kept", test_repeated_spaces_kept);
    Test.add_func("/review/activity/diamond_skin_colour", test_diamond_skin_colour);
    Test.add_func("/review/activity/vertical_if_pragma_in_tokens", test_vertical_if_pragma_in_tokens);
    Test.add_func("/review/activity/vertical_if_pragma_through_engine", test_vertical_if_pragma_through_engine);
    Test.run();
}

// ---- PlantUML fidelity review (activity, September 2026) ----

// A1. An arrow label without ";" continues on the next lines up to the ";"
void test_multiline_arrow_label() {
    string dot = engine_dot("@startuml\n:foo1;\n-> line one\nline two\nand **three**;\n:foo2;\n@enduml");
    assert_lacks("ml label node", dot, "three**");
    string foo1 = node_id("ml label", dot, "foo1");
    string foo2 = node_id("ml label", dot, "foo2");
    string e = edge("ml label", dot, foo1, foo2);
    if (!e.contains("line one<br align=\"left\"/>line two") || !e.contains("<b>three</b>")) {
        fail_with("ml label", "label lost its lines", dot);
    }
    // An arrow alone on its line has no label and takes nothing from the next line
    string plain = engine_dot("@startuml\n:a;\n->\n:b;\n@enduml");
    assert_lacks("bare arrow", edge("bare arrow", plain, node_id("bare arrow", plain, "a"), node_id("bare arrow", plain, "b")), "label=");
}

// A2. A styled arrow right after "else" styles the else branch
void test_arrow_style_after_else() {
    string dot = engine_dot("@startuml\n:c;\nif (t) then\n:d;\nelse\n-[#green,dotted]->\n:e;\nendif\n:f;\n@enduml");
    string e = node_id("else style", dot, "e");
    string cond = "";
    foreach (string line in dot.split("\n")) {
        if (line.contains("shape=hexagon")) cond = line.strip().split(" ")[0];
    }
    string branch = edge("else style", dot, cond, e);
    if (!branch.contains("style=\"dotted\"") || !branch.contains("color=\"green\"")) {
        fail_with("else style", "else edge unstyled: " + branch, dot);
    }
    // ... and the style is not left over for a later edge
    assert_lacks("else style leak", edge("else style", dot, e, successors(dot, e)[0]), "dotted");
}

// A3. "end" is a flow final (circled X), not the stop bullseye
void test_end_is_flow_final() {
    string dot = engine_dot("@startuml\nstart\n:A;\nend\n@enduml");
    assert_has("end", dot, "×");
    assert_lacks("end", dot, "doublecircle");
    string stop = engine_dot("@startuml\nstart\n:A;\nstop\n@enduml");
    assert_has("stop", stop, "doublecircle");
}

// A4. split / end split: plain lines with a port per branch, no bar, no diamond
void test_split_draws_lines() {
    string dot = engine_dot("@startuml\nstart\nsplit\n  :A;\nsplit again\n  :B;\nend split\n:D;\nend\n@enduml");
    assert_lacks("split", dot, "shape=diamond");
    assert_lacks("split", dot, "height=0.05");
    string a = node_id("split", dot, "A");
    string b = node_id("split", dot, "B");
    int ports_out = count_substr(dot, ":b0:s -> ") + count_substr(dot, ":b1:s -> ");
    assert(ports_out == 2);
    assert_has("split", dot, "%s -> ".printf(a));
    assert(count_substr(dot, ":b0:n") == 1 && count_substr(dot, ":b1:n") == 1);
    assert(edge("split", dot, b, successors(dot, b)[0]).contains(":b1:n"));
}

// A5. "|" in an action is literal text
void test_pipe_is_text() {
    string dot = engine_dot("@startuml\n:First line|Second line;\n@enduml");
    assert_has("pipe", dot, "First line|Second line");
}

// A7. ":error; <<#pink>>" colours the action; the "#pink:" prefix still does
void test_color_suffix() {
    string dot = engine_dot("@startuml\nstart\n:error; <<#pink>>\n:ok; <<#palegreen>>\n#yellow:old;\nstop\n@enduml");
    foreach (string pair in new string[] { "error|pink", "ok|palegreen", "old|yellow" }) {
        string[] p = pair.split("|");
        string id = node_id("suffix", dot, p[0]);
        foreach (string line in dot.split("\n")) {
            if (line.strip().has_prefix(id + " [") && !line.contains("fillcolor=\"%s\"".printf(p[1]))) {
                fail_with("suffix", "%s not %s".printf(p[0], p[1]), dot);
            }
        }
    }
    assert_lacks("suffix", dot, "«");
}

// A8. Repeated spaces in an action are kept
void test_repeated_spaces_kept() {
    string dot = engine_dot("@startuml\n:process only   __sequence__ and x;\n@enduml");
    assert_has("spaces", dot, "only   ");
}

// A9. Diamonds take activity DiamondBackgroundColor (merge diamonds were white)
void test_diamond_skin_colour() {
    string dot = engine_dot("@startuml\nskinparam activity {\n  BackgroundColor #4682B4\n  DiamondBackgroundColor #36648B\n  DiamondBorderColor #ffffff\n}\nstart\nif (a?) then (yes)\n  :x;\nelse (no)\n  :y;\nendif\nstop\n@enduml");
    foreach (string line in dot.split("\n")) {
        if (line.contains("shape=diamond") || line.contains("shape=hexagon")) {
            if (!line.contains("fillcolor=\"#36648B\"") || !line.contains("color=\"#ffffff\"")) {
                fail_with("diamond", "diamond colour: " + line, dot);
            }
        }
    }
    assert_has("diamond", dot, "shape=diamond");
}

// A6. The parser honours "!pragma useVerticalIf on" when it reaches it (the
// preprocessor currently drops the line before the parser sees it)
void test_vertical_if_pragma_in_tokens() {
    string src = "@startuml\n!pragma useVerticalIf on\nstart\nif (a) then (yes)\n:x;\nelseif (b) then (yes)\n:y;\nendif\n@enduml";
    var parser = new GDiagram.ActivityDiagramParser();
    var d = parser.parse(new GDiagram.Lexer(src).scan_all());
    assert(d.use_vertical_if);
}
