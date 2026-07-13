/*
 * Regression tests for review findings in the component (incl. deployment-style),
 * use case and state diagram parsers and renderers.
 *
 * Hang tests parse in a GLib test subprocess with a timeout, so a regression fails
 * the test instead of hanging the suite.
 */
using GDiagram;

Gee.ArrayList<Token> lex(string source) {
    return new Lexer(source).scan_all();
}

ComponentDiagram parse_component(string source) {
    return new ComponentDiagramParser().parse(lex(source));
}

UseCaseDiagram parse_usecase(string source) {
    return new UseCaseDiagramParser().parse(lex(source));
}

StateDiagram parse_state(string source) {
    return new StateDiagramParser().parse(lex(source));
}

string component_dot(ComponentDiagram d) {
    var r = new ComponentDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    return r.generate_dot(d);
}

string usecase_dot(UseCaseDiagram d) {
    var r = new UseCaseDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    return r.generate_dot(d);
}

string state_dot(StateDiagram d) {
    var r = new StateDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    return r.generate_dot(d);
}

// The DOT statement line that starts with `prefix` (after indentation), or ""
string dot_line(string dot, string prefix) {
    foreach (string line in dot.split("\n")) {
        if (line.strip().has_prefix(prefix)) {
            return line.strip();
        }
    }
    return "";
}

// Value of attribute `name` in a DOT statement line, or null
string? dot_attr(string line, string name) {
    int i = line.index_of(" " + name + "=\"");
    if (i < 0) {
        i = line.index_of("[" + name + "=\"");
    }
    if (i < 0) {
        return null;
    }
    int start = line.index_of("\"", i) + 1;
    int end = line.index_of("\"", start);
    return line.substring(start, end - start);
}

int count_components_named(Gee.ArrayList<Component> comps, string id) {
    int n = 0;
    foreach (var c in comps) {
        if (c.id == id) {
            n++;
        }
        n += count_components_named(c.children, id);
    }
    return n;
}

// ── 1. hang: unclosed "together {" ───────────────────────────────────

void test_component_together_unclosed_no_hang() {
    if (Test.subprocess()) {
        var d = parse_component("@startuml\ncomponent A\ntogether {\n@enduml\n");
        assert(d.components.size == 1);
        // every prefix of a diagram using together / containers terminates too
        string full = "@startuml\ncomponent A\ntogether {\n  [B]\n  node N {\n    [C] --> [B]\n  }\n}\n@enduml\n";
        for (int i = 0; i <= full.length; i++) {
            parse_component(full.substring(0, i));
            parse_component(full.substring(0, i) + "\n@enduml\n");
        }
        return;
    }
    Test.trap_subprocess(null, 10 * 1000000, 0);
    Test.trap_assert_passed();
}

void test_usecase_state_unclosed_bodies_no_hang() {
    if (Test.subprocess()) {
        string uc = "@startuml\nrectangle Sys {\n  actor/ W\n  package P {\n    (X) -up-> (Y)\n  }\n  note right of (X) : n\n}\n@enduml\n";
        string st = "@startuml\nstate Outer {\n  A -[#red]up-> B\n  state Inner {\n    [*] -left-> C\n  }\n}\n@enduml\n";
        for (int i = 0; i <= uc.length; i++) {
            parse_usecase(uc.substring(0, i));
            parse_usecase(uc.substring(0, i) + "\n@enduml\n");
        }
        for (int i = 0; i <= st.length; i++) {
            parse_state(st.substring(0, i));
            parse_state(st.substring(0, i) + "\n@enduml\n");
        }
        // an unclosed body stops at @enduml instead of swallowing it
        var d = parse_state("@startuml\nstate Outer {\nA --> B\n@enduml\nC --> D\n");
        assert(d.find_state("C") == null);
        return;
    }
    Test.trap_subprocess(null, 20 * 1000000, 0);
    Test.trap_assert_passed();
}

// Every line of the component / deployment / use case / state examples cut short (the file
// as it is while typing that line), with and without the rest of the file, through all
// three parsers. The GUI and the LSP re-parse on every keystroke.
void test_example_prefixes_no_hang() {
    string? root = Environment.get_variable("GDIAGRAM_EXAMPLES_ROOT");
    if (root == null) {
        Test.skip("GDIAGRAM_EXAMPLES_ROOT not set");
        return;
    }
    if (Test.subprocess()) {
        int cases = 0;
        foreach (string sub in new string[] { "component", "deployment", "usecase", "state" }) {
            string dir_path = Path.build_filename(root, "plantuml", sub);
            try {
                var dir = Dir.open(dir_path);
                string? name;
                while ((name = dir.read_name()) != null) {
                    if (!name.has_suffix(".puml")) {
                        continue;
                    }
                    string text;
                    FileUtils.get_contents(Path.build_filename(dir_path, name), out text);
                    string[] lines = text.split("\n");
                    for (int i = 0; i < lines.length; i++) {
                        if (lines[i].strip().has_prefix("@")) {
                            continue;
                        }
                        string head = string.joinv("\n", lines[0:i]);
                        string tail = i + 1 < lines.length ? string.joinv("\n", lines[i + 1:lines.length]) : "";
                        for (int k = 0; k < lines[i].length; k += 2) {
                            string cut = lines[i].substring(0, k);
                            foreach (string v in new string[] { head + "\n" + cut + "\n" + tail,
                                                                head + "\n" + cut + "\n@enduml\n" }) {
                                parse_component(v);
                                parse_usecase(v);
                                parse_state(v);
                                cases++;
                            }
                        }
                    }
                }
            } catch (Error e) {
                error("%s: %s", dir_path, e.message);
            }
        }
        assert(cases > 1000);
        return;
    }
    Test.trap_subprocess(null, 90 * 1000000, 0);
    Test.trap_assert_passed();
}

// ── 2. use case arrows with direction / options ──────────────────────

UseCaseRelationship? find_uc_rel(UseCaseDiagram d, string from, string to) {
    foreach (var r in d.relationships) {
        if (r.from_id == from && r.to_id == to) {
            return r;
        }
    }
    return null;
}

void test_usecase_direction_arrows() {
    var d = parse_usecase("""@startuml
usecase X
:user: -left-> (dummyLeft)
:user: -right-> (dummyRight)
:user: -up-> (dummyUp)
:user: -down-> (dummyDown)
User -up-> (Login)
A -[#blue]-> (Y)
A .up.> (Z)
@enduml""");
    assert(d.find_actor("up") == null);
    assert(d.find_actor("left") == null);
    foreach (string dir in new string[] { "Left", "Right", "Up", "Down" }) {
        var r = find_uc_rel(d, "user", "dummy" + dir);
        assert(r != null);
        assert(r.placement == dir.down());
        assert(r.directed);
    }
    var login = find_uc_rel(d, "User", "Login");
    assert(login != null && login.placement == "up");
    assert(d.find_usecase("Login") != null);
    var y = find_uc_rel(d, "A", "Y");
    assert(y != null && y.line_color == "blue" && y.placement == "");
    var z = find_uc_rel(d, "A", "Z");
    assert(z != null && z.is_dashed && z.placement == "up");

    string dot = usecase_dot(d);
    // up/left are written reversed with dir=back
    assert(dot.contains("Login -> User [style=solid, arrowhead=none, arrowtail=vee, dir=back]"));
    assert(dot.contains("{ rank=same; dummyLeft; user; }"));
}

// Plain arrows keep their meaning after the arrow reader rewrite
void test_usecase_plain_arrows_unchanged() {
    var d = parse_usecase("""@startuml
usecase U
A --> (B)
A -- (C)
A .. (D)
A <.. (E)
A <|-- F
A -.-> (G)
@enduml""");
    var b = find_uc_rel(d, "A", "B");
    assert(b != null && b.directed && !b.is_dashed);
    var c = find_uc_rel(d, "A", "C");
    assert(c != null && !c.directed);
    var dd = find_uc_rel(d, "A", "D");
    assert(dd != null && !dd.directed && dd.is_dashed);
    var e = find_uc_rel(d, "E", "A");
    assert(e != null && e.directed && e.is_dashed);
    var f = find_uc_rel(d, "F", "A");
    assert(f != null && f.relation_type == UseCaseRelationType.GENERALIZATION);
    var g = find_uc_rel(d, "A", "G");
    assert(g != null && g.is_dashed);
}

// ── 3. use case inline hex link colour ───────────────────────────────

void test_usecase_hex_link_color() {
    var d = parse_usecase("@startuml\nactor A\nA --> (X) #FF0000;line.bold : red\nA --> (Y) #line:00FF00;text:F00\n@enduml");
    var x = find_uc_rel(d, "A", "X");
    assert(x != null);
    assert(x.line_color == "#FF0000");
    assert(x.line_bold);
    assert(x.label == "red");
    var y = find_uc_rel(d, "A", "Y");
    assert(y != null && y.line_color == "#00FF00" && y.text_color == "#F00");
    string dot = usecase_dot(d);
    assert(dot.contains("color=\"#FF0000\""));
    assert(!dot.contains("color=\"FF0000\""));
}

// ── 4. component text contrast on person/queue/boundary fills ────────

void test_component_text_contrast() {
    var d = parse_component("@startuml\nactor User\nperson P\nqueue Q\nboundary B\ncontrol C\n[App] #000080\n@enduml");
    string dot = component_dot(d);
    string node_font = "";
    string node_defaults = dot_line(dot, "node [");
    node_font = dot_attr(node_defaults, "fontcolor");
    // Filled shapes: the text colour has the polarity contrast_text picks for the fill
    foreach (string id in new string[] { "Q", "App" }) {
        string line = dot_line(dot, id + " [");
        assert(line != "");
        string fill = dot_attr(line, "fillcolor");
        string? font = dot_attr(line, "fontcolor") ?? node_font;
        string needed = RenderUtils.contrast_text(fill);
        assert(RenderUtils.contrast_text(font) != needed);
    }
    // Actor figures and boundary / control icons have their caption on the canvas, in the
    // graph-wide node colour; the person's name sits in its filled body cell
    foreach (string id in new string[] { "User", "B", "C" }) {
        string line = dot_line(dot, id + " [");
        assert(line != "" && dot_attr(line, "fillcolor") == null && dot_attr(line, "fontcolor") == null);
    }
    string person = dot_line(dot, "P [");
    int bg = person.index_of("BORDER=\"1\" STYLE=\"rounded\" BGCOLOR=\"");
    assert(bg > 0);
    string body_fill = person.substring(bg + 35, 7);
    int fc = person.index_of("<FONT COLOR=\"");
    string body_font = person.substring(fc + 13, 7);
    assert(RenderUtils.contrast_text(body_font) != RenderUtils.contrast_text(body_fill));
}

// ── 5. component 3- and 8-digit hex colours ──────────────────────────

void test_component_short_and_alpha_hex() {
    var d = parse_component("@startuml\n[App] #F00\ncomponent B #00FF0080\nnode N #F00 {\n[X]\n}\n@enduml");
    assert(d.find_component("App").color == "#F00");
    assert(d.find_component("B").color == "#00FF0080");
    assert(d.find_component("N").color == "#F00");
    string dot = component_dot(d);
    assert(!dot.contains("\"F00\""));
    assert(!dot.contains("\"00FF0080\""));
}

// ── 6. state transitions with direction / style brackets ─────────────

void test_state_arrow_direction_and_style() {
    var d = parse_state("""@startuml

[*] -up-> First
First -right-> Second
Second --> Third
Third -left-> Last

@enduml""");
    assert(d.transitions.size == 4);
    assert(d.transitions[0].direction == "up");
    assert(d.transitions[1].direction == "right");
    assert(d.transitions[2].direction == "");
    assert(d.transitions[3].direction == "left");

    var s = parse_state("@startuml\nIdle -[#red]-> Red\nIdle -[dashed]-> Dashed\nIdle -[#blue,dotted]left-> Left\nstate Outer {\n  A -down-> B\n}\n@enduml");
    assert(s.transitions.size == 3);
    assert(s.transitions[0].color == "#red");
    assert(s.transitions[1].is_dashed);
    assert(s.transitions[2].color == "#blue" && s.transitions[2].line_style == "dotted" &&
           s.transitions[2].direction == "left");
    var outer = s.find_state("Outer");
    assert(outer.nested_transitions.size == 1 && outer.nested_transitions[0].direction == "down");

    string dot = state_dot(s);
    assert(dot.contains("Idle -> Red [style=solid, color=\"red\"]"));
    assert(dot.contains("Idle -> Dashed [style=dashed]"));
    assert(dot.contains("Left -> Idle [style=dotted, color=\"blue\", dir=back]"));
    // a coloured nested composite keeps its own body
    var n = parse_state("@startuml\nstate Outer {\n  state Hw #lightblue {\n    Site -[hidden]-> Ctl\n  }\n}\n@enduml");
    var hw = n.find_state("Hw");
    assert(hw != null && hw.color == "#lightblue" && hw.nested_states.size == 2);
    assert(hw.nested_transitions.size == 1 && hw.nested_transitions[0].line_style == "invis");

    string dot18 = state_dot(d);
    assert(dot18.contains("First -> _initial_0 [style=solid, dir=back]"));
}

// ── 7. component re-mentioned in a link reuses the declaration ───────

void test_component_link_reuses_declared() {
    var d = parse_component("""@startuml
node "Web Server" as web {
  [App] <<svc>> #F00
}
[DB] --> web
[App] --> [DB] : uses
[App]
@enduml""");
    assert(count_components_named(d.components, "App") == 1);
    var app = d.find_component("App");
    assert(app.stereotype == "svc");
    assert(app.color == "#F00");
    assert(d.find_component("web").children.contains(app));
    bool found = false;
    foreach (var r in d.relationships) {
        if (r.from_id == "App" && r.to_id == "DB" && r.label == "uses") {
            found = true;
        }
    }
    assert(found);
}

// ── 8. component links with options + direction, multiplicities ──────

void test_component_link_options_direction_and_multiplicity() {
    var d = parse_component("@startuml\n[A]\n[B]\n[C]\n[D]\nA -[#FF0000]up-> B\nC \"1\" --> \"many\" D : lbl\n@enduml");
    assert(d.relationships.size == 2);
    var ab = d.relationships[0];
    assert(ab.from_id == "A" && ab.to_id == "B");
    assert(ab.color == "#FF0000" && ab.placement == "up");
    var cd = d.relationships[1];
    assert(cd.from_id == "C" && cd.to_id == "D");
    assert(cd.tail_label == "1" && cd.head_label == "many" && cd.label == "lbl");
    string dot = component_dot(d);
    assert(dot.contains("taillabel=\"1\""));
    assert(dot.contains("headlabel=\"many\""));
    // a quoted target is still a target, not a multiplicity
    var q = parse_component("@startuml\n[A] --> \"Quoted\" : x\n@enduml");
    assert(q.relationships.size == 1 && q.relationships[0].to_id == "Quoted" &&
           q.relationships[0].head_label == null);
}

// ── 9. ports inside a node body ──────────────────────────────────────

void test_deployment_ports_in_node() {
    var d = parse_component("""@startuml
[i]
node node {
  portin p1
  portout po1
  port p2
  file f1
}
i --> p1
p1 --> f1
f1 --> po1
@enduml""");
    assert(d.find_component("p1") == null);
    assert(d.find_component("po1") == null);
    assert(d.ports.size == 3);
    foreach (var p in d.ports) {
        assert(p.parent_component == "node");
    }
    string dot = component_dot(d);
    // drawn as small squares inside the node's cluster
    int cluster = dot.index_of("subgraph cluster_");
    int close = dot.index_of("\n  }", cluster);
    // (a small square with the name beside it; render_to_svg moves the border onto it)
    int p1 = dot.index_of("p1 [shape=plaintext, style=solid, label=<<TABLE");
    assert(cluster >= 0 && p1 > cluster && p1 < close);
    assert(!dot.contains("p1 [label=\"p1\""));
}

// ── 10. use case note on a container ─────────────────────────────────

void test_usecase_note_on_container() {
    var d = parse_usecase("@startuml\nactor A\nrectangle Sys {\n  (Inner)\n}\nnote bottom of Sys : n3\n@enduml");
    string dot = usecase_dot(d);
    string note_edge = dot_line(dot, "_uc_note_0 ->");
    assert(note_edge.has_prefix("_uc_note_0 -> _ucpkg0_anchor"));
    assert(note_edge.contains("lhead=cluster_0"));
    assert(!dot.contains("-> Sys"));
}

// ── 11. use case container bodies ────────────────────────────────────

void test_usecase_container_body() {
    var d = parse_usecase("""@startuml
rectangle Sys {
  actor/ Woman
  (Inner)
  note right of (Inner) : inside
  package Sub {
    (Deep)
  }
  (After)
}
note bottom of Sys : n3
@enduml""");
    var sys = d.find_package("Sys");
    var sub = d.find_package("Sub");
    assert(sys != null && sub != null);
    assert(sub.parent == sys);
    assert(sys.parent == null);
    assert(d.find_actor("/") == null);
    var woman = d.find_actor("Woman");
    assert(woman != null && woman.business);
    assert(sys.actors.contains(woman));
    assert(sub.use_cases.size == 1 && sub.use_cases[0].name == "Deep");
    // the nested body's "}" no longer closes the outer one
    bool after_in_sys = false;
    foreach (var uc in sys.use_cases) {
        if (uc.name == "After") after_in_sys = true;
    }
    assert(after_in_sys);
    bool inner_note = false;
    foreach (var n in d.notes) {
        if (n.attached_to == "Inner" && n.text == "inside") inner_note = true;
    }
    assert(inner_note);

    string dot = usecase_dot(d);
    int sys_at = dot.index_of("label=\"Sys\"");
    int sub_at = dot.index_of("label=\"Sub\"");
    int deep_at = dot.index_of("Deep [label=\"Deep\"");
    int sys_anchor = dot.index_of("_ucpkg%d_anchor [".printf(d.packages.index_of(sys)));
    // Sub is drawn inside Sys, Deep inside Sub
    assert(sys_at >= 0 && sub_at > sys_at && deep_at > sub_at && sys_anchor > deep_at);
}

// ── 12. state: floating note alias used inside a composite ───────────

bool state_tree_has(Gee.List<State> states, string id) {
    foreach (var s in states) {
        if (s.id == id || state_tree_has(s.nested_states, id)) {
            return true;
        }
    }
    return false;
}

void test_state_note_alias_in_composite() {
    var d = parse_state("@startuml\nnote \"floating\" as N1\nstate Outer {\n  A --> N1\n}\n@enduml");
    assert(!state_tree_has(d.states, "N1"));
    var outer = d.find_state("Outer");
    assert(outer.nested_transitions.size == 1);
    assert(outer.nested_transitions[0].to.id == "N1");
    string dot = state_dot(d);
    int cluster = dot.index_of("subgraph cluster_0");
    int close = dot.index_of("\n  }", cluster);
    int n1_node = dot.index_of("N1 [label=\"floating\"");
    assert(n1_node > close);
    assert(!dot.substring(cluster, close - cluster).contains("N1"));
}

// ── nested state colours ────────────────────────────────────────────

// The cluster block of the composite whose label is `name` (from "subgraph" to its "label=" line
// through the lines before the first nested node or cluster), or ""
string cluster_header(string dot, string name) {
    int at = dot.index_of("label=\"%s\";".printf(name));
    if (at < 0) {
        return "";
    }
    int start = dot.substring(0, at).last_index_of("subgraph cluster_");
    int end = dot.index_of("fontcolor=", at);
    end = dot.index_of("\n", end);
    return dot.substring(start, end - start);
}

void test_state_nested_colors() {
    var d = parse_state("@startuml\nstate Outer #lightblue {\n  state Inner #pink\n  state Plain\n" +
                        "  [*] --> Inner\n  state Hw #yellow {\n    state Leaf\n  }\n}\nstate Top\n@enduml");
    assert(d.find_state("Inner").color == "#pink");
    assert(d.find_state("Hw").color == "#yellow");
    string dot = state_dot(d);
    string inner = dot_line(dot, "Inner [");
    string? inner_fill = dot_attr(inner, "fillcolor");
    if (inner_fill != "pink") {
        printerr("\nnested state fill: %s\n%s\n", inner, dot);
        assert_not_reached();
    }
    assert(dot_attr(inner, "fontcolor") == RenderUtils.contrast_text("pink"));
    // Uncoloured nested states keep the default state fill, not the composite's
    string top_fill = dot_attr(dot_line(dot, "Top ["), "fillcolor");
    assert(dot_attr(dot_line(dot, "Plain ["), "fillcolor") == top_fill);
    assert(dot_attr(dot_line(dot, "Leaf ["), "fillcolor") == top_fill);
    // A nested composite (cluster) takes its own fill and readable text
    string hw = cluster_header(dot, "Hw");
    if (!hw.contains("bgcolor=\"yellow\";") ||
        !hw.contains("fontcolor=\"%s\";".printf(RenderUtils.contrast_text("yellow")))) {
        printerr("\nnested cluster header:\n%s\n", hw);
        assert_not_reached();
    }
    assert(cluster_header(dot, "Outer").contains("bgcolor=\"lightblue\";"));
}

void test_state_color_spec_line_text() {
    var d = parse_state("@startuml\nstate Outer {\n  state Inner #palegreen;line:red;text:blue\n" +
                        "  state Dash #back:pink;line.dashed\n  Inner --> Dash\n" +
                        "  state Pick <<choice>> #red\n  Dash --> Pick\n}\n" +
                        "state Top #white;line:green;line.bold\n@enduml");
    // The spec's items were read as a description line of a state "line"
    assert(d.find_state("line") == null);
    assert(d.find_state("text") == null);
    var inner = d.find_state("Inner");
    assert(inner.color == "#palegreen" && inner.line_color == "#red" && inner.text_color == "#blue");
    assert(inner.description == null);
    // A nested stereotype is read too; it used to block the colour after it
    var pick = d.find_state("Pick");
    assert(pick.state_type == StateType.CHOICE && pick.color == "#red");
    string dot = state_dot(d);
    string l = dot_line(dot, "Inner [");
    assert(dot_attr(l, "fillcolor") == "palegreen");
    assert(dot_attr(l, "color") == "red");
    assert(dot_attr(l, "fontcolor") == "blue");
    string dash = dot_line(dot, "Dash [");
    assert(dot_attr(dash, "fillcolor") == "pink");
    assert(dot_attr(dash, "style") == "rounded,filled,dashed");
    string top = dot_line(dot, "Top [");
    assert(dot_attr(top, "color") == "green");
    assert(top.contains("penwidth=2"));
}

// ── 13. links inside a container body declare their ends in it ──────

bool has_child(ComponentDiagram d, string container, string id) {
    var c = d.find_component(container);
    if (c == null) {
        return false;
    }
    foreach (var child in c.children) {
        if (child.id == id) {
            return true;
        }
    }
    return false;
}

void test_component_links_in_body_declare_ends_there() {
    var d = parse_component("""@startuml
[Z]
node N {
  [A] --> [B]
  [Z] --> [B]
}
[B] --> [C]
package P {
  HTTP - [First Component]
  [First Component] --> FTP
}
node M {
  N --> Q
}
@enduml""");
    // first mentions inside a body belong to it
    assert(has_child(d, "N", "A"));
    assert(has_child(d, "N", "B"));
    assert(has_child(d, "P", "HTTP"));
    assert(has_child(d, "P", "First Component"));
    assert(has_child(d, "P", "FTP"));
    assert(has_child(d, "M", "Q"));
    // an element declared earlier, or the container itself, is not moved or duplicated
    assert(count_components_named(d.components, "Z") == 1 && d.components.contains(d.find_component("Z")));
    assert(count_components_named(d.components, "B") == 1);
    assert(count_components_named(d.components, "N") == 1 && !has_child(d, "M", "N"));
    // a later top-level mention does not move it; a new name there stays at the top level
    assert(d.components.contains(d.find_component("C")));
    assert(!d.components.contains(d.find_component("B")));
    assert(d.find_component("HTTP").link_end && !d.find_component("A").link_end);

    string dot = component_dot(d);
    int cluster = dot.index_of("subgraph cluster_1");
    int close = dot.index_of("\n  }", cluster);
    string body = dot.substring(cluster, close - cluster);
    assert(body.contains("First_Component [label=\"First Component\""));
    // names only used in links are interface circles with their caption, inside the body
    assert(body.contains("HTTP [shape=plaintext") && body.contains(">HTTP<"));
    assert(body.contains("FTP [shape=plaintext") && body.contains(">FTP<"));
}

void test_component_body_link_end_declared_later_wins() {
    // "database DB" after "node N { A --> DB }": the declaration stays the only DB
    var d = parse_component("@startuml\nnode N {\n  [A] --> DB\n}\ndatabase DB\n@enduml");
    assert(count_components_named(d.components, "DB") == 1);
    assert(d.components.contains(d.find_component("DB")));
    // a body "[A]" after "[A] --> [B]" at the top level keeps A there, as PlantUML
    var e = parse_component("@startuml\n[A] --> [B]\nnode N {\n  [A]\n  [B] --> [X]\n}\n@enduml");
    assert(count_components_named(e.components, "A") == 1 && e.components.contains(e.find_component("A")));
    assert(has_child(e, "N", "X") && !has_child(e, "N", "A"));
}

// ── 14. deployment ports sit on the container border ────────────────

// Bounding box of the polygon / path coordinates in the SVG group titled `title`
bool svg_group_bbox(string svg, string title, out double x0, out double y0, out double x1, out double y1) {
    x0 = y0 = double.MAX;
    x1 = y1 = -double.MAX;
    int t = svg.index_of("<title>" + title + "</title>");
    if (t < 0) {
        return false;
    }
    string group = svg.substring(t, svg.index_of("</g>", t) - t);
    bool found = false;
    try {
        var shapes = new Regex("(?:points|d)=\"([^\"]*)\"");
        var pair = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
        MatchInfo mi;
        shapes.match(group, 0, out mi);
        while (mi.matches()) {
            string coords = mi.fetch(1);
            MatchInfo pi;
            pair.match(coords, 0, out pi);
            while (pi.matches()) {
                double x = double.parse(pi.fetch(1));
                double y = double.parse(pi.fetch(2));
                x0 = double.min(x0, x);
                x1 = double.max(x1, x);
                y0 = double.min(y0, y);
                y1 = double.max(y1, y);
                found = true;
                pi.next();
            }
            mi.next();
        }
    } catch (RegexError e) {
        assert_not_reached();
    }
    return found;
}

void test_deployment_ports_on_border() {
    var d = parse_component("""@startuml
[i]
node node {
  portin p1
  portin p2
  portout po1
  port pb
  file f1
}
[o]
i --> p1
p1 --> f1
f1 --> po1
po1 --> o
pb --> o
@enduml""");
    var r = new ComponentDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    string dot = r.generate_dot(d);
    // portin in the cluster's first rank, portout and a port that only links out in its last
    assert(dot.contains("{ rank=min; p1; p2; }"));
    assert(dot.contains("{ rank=max; po1; pb; }"));
    // links attach to the square on the side facing the other end
    assert(dot.contains("i -> p1:sq:n"));
    assert(dot.contains("p1:sq:s -> f1"));
    assert(dot.contains("f1 -> po1:sq:n"));
    assert(dot.contains("po1:sq:s -> o"));

    uint8[]? data = r.render_to_svg(d);
    assert(data != null);
    string svg = (string) data;
    double cx0, cy0, cx1, cy1;
    assert(svg_group_bbox(svg, "cluster_0", out cx0, out cy0, out cx1, out cy1));
    foreach (string port in new string[] { "p1", "p2", "po1", "pb" }) {
        double x0, y0, x1, y1;
        assert(svg_group_bbox(svg, port, out x0, out y0, out x1, out y1));
        double centre = (y0 + y1) / 2;
        // the top (portin) or bottom (portout) edge runs through the square's centre
        double edge = (port == "p1" || port == "p2") ? cy0 : cy1;
        assert(Math.fabs(centre - edge) < 0.6);
        assert(x0 > cx0 && x1 < cx1);
    }
}

// "database [PostgreSQL] #LightBlue" / "file [Logs] #Yellow": one coloured component each,
// no empty-named element beside it
void test_component_keyword_bracket_form() {
    var d = parse_component("@startuml\ncomponent [Application]\ndatabase [PostgreSQL] #LightBlue\nfile [Logs] #Yellow\n" +
                            "[Application] --> [PostgreSQL]\n[Application] ..> [Logs]\n@enduml");
    foreach (var c in d.components) {
        assert(c.id.length > 0);
    }
    assert(d.components.size == 3);
    assert(d.find_component("PostgreSQL").color.replace("#", "") == "LightBlue");
    assert(d.find_component("Logs").color.replace("#", "") == "Yellow");
}


// ── Alias, label, direction-word and legend bugs (docs/architecture diagrams) ──

// Every link end in the DOT is a declared node: an undeclared one is a ghost ellipse
void assert_no_ghost_link_ends(string dot) {
    foreach (string raw in dot.split("\n")) {
        string line = raw.strip();
        int arrow = line.index_of(" -> ");
        int attrs = line.index_of(" [");
        if (arrow <= 0 || attrs < arrow) {
            continue;
        }
        foreach (string end in new string[] { line.substring(0, arrow), line.substring(arrow + 4, attrs - arrow - 4) }) {
            string id = end.split(":")[0];
            if (dot_line(dot, id + " [") == "") {
                printerr("\nghost link end [%s] in:\n%s\n", id, dot);
                assert_not_reached();
            }
        }
    }
}

// "[X] <<ui>> as a": the stereotype before the alias lost the alias, so links to "a" drew
// ghost nodes. Also with "component", a colour, and inside a container body.
void test_component_stereotype_before_alias() {
    var d = parse_component("@startuml\n[X] <<ui>> as a\ncomponent [Y] <<s>> as b\n" +
                            "[Long Name] <<s>> as c #pink\npackage P {\n  [Z] <<ui>> as d\n  component [W] <<s>> as e #FF0000\n}\n" +
                            "a --> b\nb --> c\nc --> d\nd --> e\n@enduml");
    assert(d.find_component("a") != null);
    assert(d.find_component("a").stereotype == "ui");
    assert(d.find_component("b").stereotype == "s");
    assert(d.find_component("c").get_display_label() == "Long Name");
    assert(d.find_component("c").color.replace("#", "") == "pink");
    var p = d.find_component("P");
    assert(p != null && p.children.size == 2);
    assert(count_components_named(d.components, "Z") == 1);
    string dot = component_dot(d);
    assert_no_ghost_link_ends(dot);
    assert(dot_line(dot, "d [").contains("«ui»"));
    assert(dot_attr(dot_line(dot, "e ["), "fillcolor") == "#FF0000");
}

// "[Preprocessor\n(<style> blocks)]": "<style>" lexed as a style block to the end of the
// file, so the label swallowed every following line
void test_component_style_text_in_bracket_label() {
    var d = parse_component("@startuml\n[Preprocessor\\n(<style> blocks)] as pp\n[Lexer] as lx\npp --> lx\n@enduml");
    assert(d.find_component("pp") != null);
    assert(d.find_component("pp").get_display_label() == "Preprocessor\\n(<style> blocks)");
    assert(d.find_component("lx") != null);
    assert(d.relationships.size == 1);
    assert_no_ghost_link_ends(component_dot(d));
}

// "[crow's foot]": "'" lexed as a comment start, merging the label with the next line
void test_component_apostrophe_in_labels() {
    var d = parse_component("@startuml\n[crow's foot] as cf\n[Other] as o\ncomponent \"it's quoted\" as q\n" +
                            "cf --> o\no --> q\n[A] --> [Bob's box] : it's a link\n" +
                            "package P {\n  [a's] as x\n  [b's] as y\n}\nx --> y\n@enduml");
    assert(d.find_component("cf").get_display_label() == "crow's foot");
    assert(d.find_component("o").get_display_label() == "Other");
    assert(d.find_component("q").get_display_label() == "it's quoted");
    assert(d.find_component("Bob's box") != null);
    assert(d.find_component("x").get_display_label() == "a's");
    assert(d.find_component("y").get_display_label() == "b's");
    assert(d.relationships.size == 4);
    bool labelled = false;
    foreach (var rel in d.relationships) {
        if (rel.to_id == "Bob's box") {
            labelled = rel.label == "it's a link";
        }
    }
    assert(labelled);
    assert_no_ghost_link_ends(component_dot(d));
}

// "[Left Panel] as left" / "left --> right": left, right, top, bottom lex as keywords, and
// the link line was skipped
void test_component_direction_word_aliases() {
    var d = parse_component("@startuml\n[Left Panel] as left\n[Right Panel] as right\n[Top] as top\n[Bottom] as bottom\n" +
                            "left --> right\ntop --> bottom\nright --> top\n" +
                            "node N {\n  [In] as up\n  [Out] as down\n  left --> down\n}\n@enduml");
    assert(d.relationships.size == 4);
    string dot = component_dot(d);
    assert(dot_line(dot, "left -> right") != "");
    assert(dot_line(dot, "top -> bottom") != "");
    assert(dot_line(dot, "right -> top") != "");
    assert(dot_line(dot, "left -> down") != "");
    assert_no_ghost_link_ends(dot);
}

// "legend right ... endlegend" was dropped; it is drawn at its corner as the label of a
// frameless cluster around the body, with creole tables
void test_component_legend() {
    var d = parse_component("@startuml\ntitle T\n[A] --> [B]\nlegend right\n  |= Color |= Part |\n  | <#E3F2FD> | UI |\n" +
                            "  Key: it's A\nendlegend\n@enduml");
    assert(d.legend != null);
    assert(d.legend.halign == "right");
    assert(d.legend.valign == "bottom");
    assert(d.legend.text.contains("Key: it's A"));
    assert(d.components.size == 2);  // no element from the legend lines
    assert(d.relationships.size == 1);
    string dot = component_dot(d);
    assert(dot.contains("subgraph cluster_legend {"));
    assert(dot.contains("labelloc=b;"));
    assert(dot.contains("labeljust=r;"));
    assert(dot.contains("BGCOLOR=\"#E3F2FD\""));
    assert(dot.contains("<B>Color</B>"));
    assert(dot.contains("Key: it's A"));
    assert(Gvc.Graph.read_string(dot) != null);

    var top = parse_component("@startuml\n[A]\nlegend top left\nx\nend legend\n[B]\n@enduml");
    assert(top.legend != null && top.legend.valign == "top" && top.legend.halign == "left");
    assert(top.legend.text == "x");
    assert(top.components.size == 2);
    string top_dot = component_dot(top);
    assert(top_dot.contains("labelloc=t;") && top_dot.contains("labeljust=l;"));

    // No legend, no wrapper
    assert(!component_dot(parse_component("@startuml\n[A]\n@enduml")).contains("cluster_legend"));
}

// Use case: stereotype before "as", keyword aliases (left/right) and legend
void test_usecase_alias_forms_and_legend() {
    var d = parse_usecase("@startuml\nactor User <<human>> as u\nusecase \"Log in\" <<main>> as li\nu --> li\n" +
                          "actor \"Left One\" as left\nusecase (Right) as right\nleft --> right\n" +
                          "legend right\n  a legend\nendlegend\n@enduml");
    assert(d.actors.size == 2);
    assert(d.relationships.size == 2);
    assert(d.legend != null && d.legend.text.contains("a legend"));
    string dot = usecase_dot(d);
    assert(dot.contains("u -> li"));
    assert(dot.contains("left -> right"));
    assert(dot.contains("a legend"));
}

// ── 15. PlantUML fidelity: component / deployment / C4 (September 2026) ──

string component_svg(ComponentDiagram d, Gee.ArrayList<ElementRegion>? regions = null) {
    var r = new ComponentDiagramRenderer(new Gvc.Context(), regions ?? new Gee.ArrayList<ElementRegion>(), "dot");
    uint8[]? data = r.render_to_svg(d);
    assert(data != null);
    var sb = new StringBuilder();
    sb.append_len((string) data, data.length);
    return sb.str;
}

// ── 2026-09-17: state and use case PlantUML fidelity ────────────────

int count_text(string haystack, string needle) {
    int n = 0;
    int at = 0;
    while ((at = haystack.index_of(needle, at)) >= 0) {
        n++;
        at += needle.length;
    }
    return n;
}

string svg_text(uint8[] data) {
    var sb = new StringBuilder.sized(data.length + 1);
    sb.append_len((string) data, data.length);
    return sb.str;
}

// The SVG group of the node or cluster titled `title`
string svg_group_of(string svg, string title) {
    int t = svg.index_of("<title>" + title + "</title>");
    if (t < 0) {
        return "";
    }
    return svg.substring(t, svg.index_of("</g>", t) - t);
}

// 1. "note right of [First Component] : text" swallowed the rest of the file into the note
void test_fidelity_note_bracket_target() {
    var d = parse_component("@startuml\n[First Component]\nnote right of [First Component] : attached?\ncomponent After\nAfter --> [First Component]\n@enduml");
    assert(d.notes.size == 1);
    assert(d.notes[0].attached_to == "First Component");
    assert(d.notes[0].text == "attached?");
    assert(d.find_component("After") != null);
    assert(d.relationships.size == 1);
    var m = parse_component("@startuml\n[First Component]\nnote left of [First Component]\n  multi line\nend note\ncomponent After\n@enduml");
    assert(m.notes.size == 1 && m.notes[0].attached_to == "First Component" && m.notes[0].text == "multi line");
    assert(m.find_component("After") != null);
    string dot = component_dot(m);
    assert(dot.contains("_component_note_0 -> First_Component [style=dashed"));
}

// 2a. "!include <C4/C4_Container>" resolves to the bundled C4-PlantUML, as do the GitHub URLs
void test_fidelity_c4_stdlib_include() {
    var pp = new Preprocessor();
    string out_text = pp.process("@startuml\n!include <C4/C4_Container>\nContainer(web, \"Web App\", \"React\")\n@enduml\n", null);
    foreach (var e in pp.errors) {
        assert(!e.message.contains("C4"));
    }
    assert(out_text.contains("[begin include: <C4/C4_Container>]"));
    assert(!out_text.contains("Unsupported standard library include"));
    assert(out_text.contains("<<container>>"));
    var url = new Preprocessor();
    string via_url = url.process("@startuml\n!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Context.puml\n@enduml\n", null);
    assert(url.errors.size == 0);
    assert(via_url.contains("[begin include: https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Context.puml]"));
    // other standard libraries still report that they are missing
    var other = new Preprocessor();
    other.process("@startuml\n!include <awslib/AWSCommon>\n@enduml\n", null);
    assert(other.errors.size == 1);
}

// 2b. two stereotypes, "hide stereotype", sprites and legend markup (C4 expansion)
void test_fidelity_c4_expansion_elements() {
    var d = parse_component("@startuml\nrectangle \"Store\" <<system_boundary>><<boundary>> as c1  {\n  rectangle \"Web\" <<container>> as web\n}\nrectangle \"<$person>\\n== Customer\\n\\nA user\" <<person>> as u\nu --> web\nhide stereotype\n" +
                            "legend right\n|<#08427B><color:#FFFFFF> <U+25AF> person <size:10></size></color> |\nendlegend\n@enduml");
    var c1 = d.find_component("c1");
    assert(c1 != null && c1.children.size == 1 && c1.stereotypes.size == 2);
    assert(d.hide_stereotype);
    string dot = component_dot(d);
    assert(!dot.contains("«"));
    assert(!dot.contains("$person"));
    assert(dot.contains("<B>Customer</B>"));
    // the boundary is a dashed see-through box
    int cl = dot.index_of("subgraph cluster_0");
    string cluster = dot.substring(cl, dot.index_of("\n  }", cl) - cl);
    assert(cluster.contains("style=\"filled,dashed\"") && cluster.contains("fillcolor=\"transparent\""));
    // legend markup rendered, not shown
    assert(!dot.contains("color:#") && !dot.contains("U+25AF") && !dot.contains("size:10"));
    assert(dot.contains("&#x25AF;") && dot.contains("<FONT COLOR=\"#FFFFFF\">"));
    assert(Gvc.Graph.read_string(dot) != null);
}

// 3. "foo --> bar1 #line:red;line.bold;text:red : red bold" lost style and label
void test_fidelity_inline_link_style() {
    var d = parse_component("@startuml\nnode foo\nfoo --> bar1 #line:red;line.bold;text:red : red bold\nfoo --> bar2 #green;line.dashed;text:green : green dashed\n@enduml");
    assert(d.relationships.size == 2);
    var r = d.relationships[0];
    assert(r.color == "red" && r.thickness == 2 && r.text_color == "red" && r.label == "red bold");
    var g = d.relationships[1];
    assert(g.color == "green" && g.line_style == "dashed" && g.label == "green dashed");
    string dot = component_dot(d);
    string l1 = dot_line(dot, "foo -> bar1");
    assert(l1.contains("color=\"red\"") && l1.contains("penwidth=2") && l1.contains("fontcolor=\"red\"") && l1.contains("label=\"red bold\""));
    string l2 = dot_line(dot, "foo -> bar2");
    assert(l2.contains("style=dashed") && l2.contains("color=\"green\""));
}

// 4. 'interface "10/100 Mbps" as ETH' in a container showed "ETH"
void test_fidelity_interface_label_in_container() {
    var d = parse_component("@startuml\nnode \"PHY\" {\n  interface \"10/100 Mbps\" as ETH\n}\n[A] --> ETH\n@enduml");
    var eth = d.find_component("ETH");
    assert(eth != null && eth.label == "10/100 Mbps");
    string dot = component_dot(d);
    assert(dot.contains(">10/100 Mbps<") && !dot.contains(">ETH<"));
    assert(dot.contains("A -> ETH:c"));
}

// 5. interfaces are small hollow circles with the caption below: declared ones were filled
// dots, names only used in links big grey ellipses
void test_fidelity_interface_circles() {
    var d = parse_component("@startuml\ninterface \"Explicit\" as EX\n[Comp] - EX\n[Comp] ..> HTTP : use\n@enduml");
    string dot = component_dot(d);
    assert(!dot.contains("&#9679;"));
    assert(dot_line(dot, "HTTP [").contains("shape=plaintext") && dot.contains("Comp -> HTTP:c"));
    string svg = component_svg(d);
    var palette = ThemeManager.get_active_palette();
    foreach (string id in new string[] { "EX", "HTTP" }) {
        string group = svg_group_of(svg, id);
        assert(group.contains("<circle class=\"gdicon\" fill=\"%s\"".printf(palette.node_fill)));
        assert(!group.contains("fill=\"" + ComponentDiagramRenderer.SENTINEL));
    }
}

// 6. element shapes: stick figure, UML icons, cloud, queue, stack, storage, frame, package,
// component icon; click regions still map to the elements
void test_fidelity_element_shapes() {
    var d = parse_component("@startuml\nactor a1\nboundary b1\ncontrol c1\nentity e1\ncloud cl1\nqueue q1\nstack s1\nstorage st1\nframe f1\npackage p1\nperson pe1\ncomponent co1\na1 --> b1\n@enduml");
    string dot = component_dot(d);
    assert(dot_line(dot, "a1 [").contains("class=\"gdactor "));
    assert(!dot_line(dot, "st1 [").contains("folder"));
    var regions = new Gee.ArrayList<ElementRegion>();
    var r = new ComponentDiagramRenderer(new Gvc.Context(), regions, "dot");
    var surface = r.render_to_surface(d);
    assert(surface != null);
    string svg = component_svg(d);
    assert(svg.contains("class=\"gdfigure\""));  // the actor
    foreach (string id in new string[] { "b1", "c1", "e1", "pe1" }) {
        assert(svg_group_of(svg, id).contains("class=\"gdicon\""));
    }
    foreach (string id in new string[] { "cl1", "q1", "s1", "st1", "f1", "p1", "co1" }) {
        assert(svg_group_of(svg, id).contains("class=\"gdshape\""));
    }
    var names = new Gee.HashSet<string>();
    foreach (var region in regions) {
        names.add(region.name);
    }
    foreach (string id in new string[] { "a1", "b1", "c1", "e1", "cl1", "q1", "s1", "st1", "f1", "p1", "pe1", "co1" }) {
        assert(names.contains(id));
    }
}

// 7. containers: node 3D box, cloud, database cylinder, folder / package tab, frame, queue;
// an empty body is the element's own shape
void test_fidelity_container_shapes() {
    var d = parse_component("@startuml\nnode N {\n  component c1\n}\ncloud C {\n  component c2\n}\ndatabase D {\n  component c3\n}\nfolder F {\n  component c4\n}\nframe Fr {\n  component c5\n}\npackage P {\n  component c6\n}\nqueue Q {\n  component c7\n}\ncomponent component {\n}\n@enduml");
    string dot = component_dot(d);
    assert(dot_line(dot, "component [").contains("shape=box"));  // not a cluster
    assert(!dot.contains("database_fill") && !dot.contains("bgcolor=\"#F9A825\""));
    string svg = component_svg(d);
    for (int i = 0; i < 7; i++) {
        assert(svg_group_of(svg, "cluster_%d".printf(i)).contains("class=\"gdshape\""));
    }
    // children keep their own borders: databases are no longer filled with the database blue
    var palette = ThemeManager.get_active_palette();
    int db = dot.index_of("subgraph cluster_2");
    assert(dot.substring(db, dot.index_of("\n  }", db) - db).contains("fillcolor=\"%s\"".printf(palette.grid)));
}

// 8. node / cloud containers follow the theme's package colours with a readable title
void test_fidelity_container_theme_colours() {
    var d = parse_component("@startuml\nskinparam DefaultFontColor #ffffff\nskinparam package {\n  BackgroundColor #2F4F4F\n}\nnode \"ESP32\" {\n  [A]\n}\ncloud \"Net\" {\n  [B]\n}\n@enduml");
    string dot = component_dot(d);
    int n = dot.index_of("subgraph cluster_0");
    string node = dot.substring(n, dot.index_of("\n  }", n) - n);
    assert(node.contains("fillcolor=\"#2F4F4F\"") && node.contains("fontcolor=\"#ffffff\""));
    int c = dot.index_of("subgraph cluster_1");
    assert(dot.substring(c, dot.index_of("\n  }", c) - c).contains("fillcolor=\"#2F4F4F\""));
    // without a package colour: the palette's container fill, and white default text is
    // replaced by a readable one
    var plain = parse_component("@startuml\nskinparam DefaultFontColor #ffffff\nnode \"ESP32\" {\n  [A]\n}\n@enduml");
    string pdot = component_dot(plain);
    var palette = ThemeManager.get_active_palette();
    assert(pdot.contains("fillcolor=\"%s\"".printf(palette.grid)));
    assert(!pdot.contains("fillcolor=\"#F9A825\""));
    assert(pdot.contains("fontcolor=\"%s\"".printf(RenderUtils.contrast_text(palette.grid) == "#000000" ? "#010101" : "#FFFFFF")));
}

// 9. "-[thickness=8]->" and "-[#blue;#green,dashed]->"
void test_fidelity_link_thickness_and_colours() {
    var d = parse_component("@startuml\nnode foo\nfoo -[thickness=8]-> bar1 : eight\nfoo -[#blue;#green,dashed]-> bar2 : two\n@enduml");
    assert(d.relationships[0].thickness == 8);
    assert(d.relationships[1].colors.size == 2);
    string dot = component_dot(d);
    assert(dot_line(dot, "foo -> bar1").contains("penwidth=8"));
    string two = dot_line(dot, "foo -> bar2");
    assert(two.contains("color=\"blue:green\"") && two.contains("style=dashed"));
}

// 10. "node n #aliceblue;line:red;line.dotted;text:blue": only the fill was used
void test_fidelity_inline_element_style() {
    var d = parse_component("@startuml\nnode n #aliceblue;line:red;line.dotted;text:blue\ncloud c #pink;line:red;line.bold;text:red\n@enduml");
    var n = d.find_component("n");
    assert(n.color == "aliceblue" && n.line_color == "red" && n.line_style == "dotted" && n.text_color == "blue");
    string dot = component_dot(d);
    string line = dot_line(dot, "n [");
    assert(line.contains("fillcolor=\"aliceblue\"") && line.contains("color=\"red\"") &&
           line.contains("dotted") && line.contains("fontcolor=\"blue\""));
    assert(dot_line(dot, "c [").contains("bold"));
}

// 11. "json J { ... }" under allowmixing was dropped
void test_fidelity_json_block() {
    var d = parse_component("@startuml\nallowmixing\ncomponent C\njson J {\n  \"fruit\":\"Apple\",\n  \"color\": [\"Red\", \"Green\"]\n}\n[D]\n@enduml");
    var j = d.find_component("J");
    assert(j != null && j.component_type == ComponentType.JSON);
    assert(d.find_component("D") != null);
    string dot = component_dot(d);
    string line = dot_line(dot, "J [");
    assert(line.contains(">fruit<") && line.contains(">Apple<") && line.contains(">Green<"));
    assert(Gvc.Graph.read_string(dot) != null);
}

// 12. "skinparam componentStyle rectangle" and "skinparam linetype ortho"
void test_fidelity_component_style_and_linetype() {
    var d = parse_component("@startuml\nskinparam componentStyle rectangle\nskinparam linetype ortho\n[A] --> [B] : go\n@enduml");
    string dot = component_dot(d);
    assert(dot.contains("splines=ortho;"));
    assert(dot_line(dot, "A -> B").contains("xlabel=\"go\""));
    string svg = component_svg(d);
    assert(!svg_group_of(svg, "A").contains("gdicon"));
    // the default (UML2) draws the component icon
    string uml2 = component_svg(parse_component("@startuml\n[A]\n@enduml"));
    assert(svg_group_of(uml2, "A").contains("gdicon"));
}

// 13. short links side by side, notes beside their element, roundCorner per stereotype,
// neutral border around an explicit fill
void test_fidelity_minor_layout_and_style() {
    string dot = component_dot(parse_component("@startuml\nnode n1\nnode n2\nn1 -> n2\n@enduml"));
    assert(dot.contains("{ rank=same; n1; n2; }"));
    // inside one container the rank goes into that cluster
    string nested = component_dot(parse_component("@startuml\npackage P {\n  HTTP - [First]\n}\n@enduml"));
    assert(nested.contains("subgraph cluster_0 { { rank=same;"));

    string notes = component_dot(parse_component("@startuml\n[A]\n[B]\nnote left of A : l\nnote right of B : r\n@enduml"));
    assert(notes.contains("_component_note_0 -> A [style=dashed") && notes.contains("{ rank=same; _component_note_0; A; }"));
    assert(notes.contains("B -> _component_note_1 [style=dashed") && notes.contains("{ rank=same; _component_note_1; B; }"));

    string round = component_dot(parse_component("@startuml\nskinparam rectangle {\n  roundCorner<<Concept>> 25\n}\nrectangle \"Example\" <<Concept>> as ex1\nrectangle other\n@enduml"));
    assert(dot_line(round, "ex1 [").contains("rounded"));
    assert(!dot_line(round, "other [").contains("rounded"));

    var palette = ThemeManager.get_active_palette();
    string fill = component_dot(parse_component("@startuml\n[A] #pink\n[B]\n@enduml"));
    assert(dot_line(fill, "A [").contains("color=\"%s\"".printf(palette.node_border)));
    assert(dot_line(fill, "B [").contains("color=\"%s\"".printf(palette.component_border)));
}

// S1: "state p as \"Plain desc\"" shows the quoted text; "state \"Long\" as L" too
void test_state_alias_description() {
    var d = parse_state("@startuml\nstate p as \"Plain desc\"\nstate \"Long name\" as L\n\"Bare desc\" as B\n@enduml");
    var p = d.find_state("p");
    assert(p != null && p.label == "Plain desc");
    assert(d.find_state("Plain desc") == null);
    var l = d.find_state("L");
    assert(l != null && l.label == "Long name");
    var b = d.find_state("B");
    assert(b != null && b.label == "Bare desc");
    assert(dot_line(state_dot(d), "p [").contains("label=\"Plain desc\""));
}

// S2: history states as transition targets, inside the composite that owns them
void test_state_history_targets() {
    var d = parse_state("@startuml\nstate S {\n  state Inner\n  Outer --> [H]\n}\nOuter --> S[H*]\n@enduml");
    var s = d.find_state("S");
    State? shallow = null;
    State? deep = null;
    foreach (var n in s.nested_states) {
        if (n.state_type == StateType.HISTORY) shallow = n;
        if (n.state_type == StateType.DEEP_HISTORY) deep = n;
    }
    assert(shallow != null && deep != null);
    assert(s.nested_transitions.size == 1 && s.nested_transitions[0].to == shallow);
    assert(d.transitions.size == 1 && d.transitions[0].to == deep);
    assert(d.transitions[0].from.id == "Outer");
    // one history per composite, however often it is named
    var twice = parse_state("@startuml\nstate S {\n  A --> [H]\n  B --> [H]\n}\n@enduml");
    int h = 0;
    foreach (var n in twice.find_state("S").nested_states) {
        if (n.state_type == StateType.HISTORY) h++;
    }
    assert(h == 1);
}

// S3: "--" and "||" split a composite into concurrent regions
void test_state_concurrent_regions() {
    var d = parse_state("@startuml\nstate Active {\n  [*] -> A\n  --\n  [*] -> B\n}\n@enduml");
    var active = d.find_state("Active");
    assert(active.region_separator == "--");
    assert(d.find_state("A").region == 0 && d.find_state("B").region == 1);
    int initials = 0;
    foreach (var n in active.nested_states) {
        if (n.state_type == StateType.INITIAL) initials++;
    }
    assert(initials == 2);
    string dot = state_dot(d);
    assert(dot.contains("subgraph cluster_0_r0 {") && dot.contains("subgraph cluster_0_r1 {"));
    var v = parse_state("@startuml\nstate Active {\n  [*] -> A\n  ||\n  [*] -> B\n}\n@enduml");
    assert(v.find_state("Active").region_separator == "||");
    assert(v.find_state("B").region == 1);
    // the separator is not a state or a transition
    assert(v.find_state("|") == null && v.find_state("Active").nested_transitions.size == 2);
}

// S4: "state A.X" puts X inside composite A
void test_state_dot_notation() {
    var d = parse_state("@startuml\nstate A.X\nstate A.Y\nstate B.Z\nX --> Z\n@enduml");
    assert(d.states.size == 2);
    var a = d.find_state("A");
    assert(a.state_type == StateType.COMPOSITE && a.nested_states.size == 2);
    assert(d.find_state("B").nested_states[0].id == "Z");
    assert(d.transitions.size == 1 && d.transitions[0].from.id == "X");
}

// S5: stereotypes map to their pseudo states; points, pins and expansion nodes sit on the border
void test_state_stereotype_shapes() {
    var d = parse_state("@startuml\nstate s1 <<start>>\nstate e3 <<end>>\nstate r <<sdlreceive>>\n" +
                        "state h <<history>>\nstate h2 <<history*>>\n" +
                        "state Somp {\n  state e1 <<entryPoint>>\n  state p1 <<inputPin>>\n  state ei <<expansionInput>>\n" +
                        "  state o1 <<outputPin>>\n  state eo <<expansionOutput>>\n  e1 --> sin\n  sin --> exitA <<exitPoint>>\n}\n@enduml");
    assert(d.find_state("s1").state_type == StateType.INITIAL);
    assert(d.find_state("e3").state_type == StateType.END_STATE);
    assert(d.find_state("r").state_type == StateType.SDL_RECEIVE);
    assert(d.find_state("h").state_type == StateType.HISTORY);
    assert(d.find_state("h2").state_type == StateType.DEEP_HISTORY);
    assert(d.find_state("e1").state_type == StateType.ENTRY_POINT);
    assert(d.find_state("p1").state_type == StateType.INPUT_PIN);
    assert(d.find_state("ei").state_type == StateType.EXPANSION_INPUT);
    assert(d.find_state("o1").state_type == StateType.OUTPUT_PIN);
    assert(d.find_state("eo").state_type == StateType.EXPANSION_OUTPUT);
    // the stereotype after a transition target (as PlantUML 1.2026.1 draws it)
    assert(d.find_state("exitA").state_type == StateType.EXIT_POINT);
    string dot = state_dot(d);
    assert(dot_line(dot, "e1 [").contains("BGCOLOR=\"#010204\"") && dot_line(dot, "e1 [").contains(">e1<"));
    assert(dot_line(dot, "exitA [").contains("BGCOLOR=\"#010205\""));
    assert(dot_line(dot, "p1 [").contains("BGCOLOR=\"#010206\""));
    assert(dot_line(dot, "eo [").contains("BGCOLOR=\"#010207\""));
    assert(dot.contains("{ rank=min; e1; p1; ei; }"));
    assert(dot.contains("e1:sq:s -> sin"));
    assert(dot_line(dot, "r [").contains("class=\"gdsdl\""));
    assert(dot_line(dot, "h2 [").contains("label=\"H*\""));

    // the SVG: shapes over the sentinels, and the border moved onto the ports
    var r = new StateDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    uint8[]? data = r.render_to_svg(d);
    assert(data != null);
    string svg = svg_text(data);
    assert(!svg.contains("#01020"));
    assert(count_text(svg, "class=\"gdportshape\"") >= 6);
    assert(svg.contains("class=\"gdfold\""));
    // the composite's border runs through the port circles (Graphviz y grows upwards here)
    int cl = svg.index_of("<title>cluster_0</title>");
    string group = svg.substring(cl, svg.index_of("</g>", cl) - cl);
    double top = double.MAX;
    double bottom = -double.MAX;
    try {
        MatchInfo mi;
        new Regex("(-?[0-9.]+),(-?[0-9.]+)").match(group, 0, out mi);
        while (mi.matches()) {
            top = double.min(top, double.parse(mi.fetch(2)));
            bottom = double.max(bottom, double.parse(mi.fetch(2)));
            mi.next();
        }
    } catch (RegexError e) {
        assert_not_reached();
    }
    int circle = svg.index_of("<circle class=\"gdportshape\"");
    int cy = svg.index_of("cy=\"", circle) + 4;
    double entry_y = double.parse(svg.substring(cy, svg.index_of("\"", cy) - cy));
    assert(circle >= 0 && ((top - entry_y).abs() < 1.5 || (bottom - entry_y).abs() < 1.5));

    // click-to-source: nested states and border ports map to their declaration lines
    var regions = new Gee.ArrayList<ElementRegion>();
    var rr = new StateDiagramRenderer(new Gvc.Context(), regions, "dot");
    assert(rr.render_to_surface(d) != null);
    bool e1_mapped = false;
    foreach (var region in regions) {
        if (region.name == "e1" && region.source_line == 8) {
            e1_mapped = true;
        }
    }
    assert(e1_mapped);
}

// S6: a transition naming a composite before its "state \"desc\" as X {" block: no ghost X
void test_state_declared_after_reference_no_ghost() {
    var d = parse_state("@startuml\n[*] --> NS\nstate \"Not Shooting\" as NS {\n  state Idle\n}\n@enduml");
    assert(d.states.size == 2);
    var ns = d.find_state("NS");
    assert(ns.state_type == StateType.COMPOSITE && ns.label == "Not Shooting");
    assert(d.find_state("Not Shooting") == null);
    string dot = state_dot(d);
    assert(!dot.contains("NS [label="));
    assert(count_text(dot, "label=\"Not Shooting\"") == 1);
}

// S7: "State S1" (capitalised keyword) declares S1, no state "State"
void test_state_capitalised_keyword() {
    var d = parse_state("@startuml\nState S1\nS1 --> S2\n@enduml");
    assert(d.find_state("State") == null);
    assert(d.find_state("S1") != null && d.states.size == 2);
}

// S8: "note on link" sits beside the transition before it
void test_state_note_on_link() {
    var d = parse_state("@startuml\n[*] --> State1\nState1 --> State2\nnote on link\n  transition note\nend note\n@enduml");
    assert(d.notes.size == 1);
    var note = d.notes[0];
    assert(note.text == "transition note");
    assert(note.link == d.transitions[1]);
    string dot = state_dot(d);
    assert(dot.contains("State1 -> %s [style=invis];".printf(note.id)));
    assert(dot.contains("%s -> State2 [style=invis];".printf(note.id)));
}

// S9: a later top-level declaration makes a state top-level, wherever a link first put it
void test_state_toplevel_redeclaration() {
    var d = parse_state("@startuml\nstate A {\n  [*] --> A1\n  A1 --> B : go\n}\nstate B {\n  [*] --> B1\n}\n@enduml");
    var a = d.find_state("A");
    var b = d.find_state("B");
    assert(d.states.contains(b));
    assert(!a.nested_states.contains(b));
    assert(b.state_type == StateType.COMPOSITE && b.nested_states.size == 2);
    var c = parse_state("@startuml\nstate Outer {\n  Idle --> Conf\n}\nstate Conf {\n  state Inner\n}\n@enduml");
    assert(c.states.contains(c.find_state("Conf")));
    // a state declared inside a composite stays there
    var e = parse_state("@startuml\nstate Outer {\n  state Conf\n}\nstate Conf\n@enduml");
    assert(e.find_state("Outer").nested_states.contains(e.find_state("Conf")));
}

// S10: one start / end per scope, StartColor / EndColor, "->" side by side, spread and clipped
// composite links, and a composite's self transition around its box
void test_state_visual_details() {
    var d = parse_state("@startuml\nskinparam state {\n StartColor MediumBlue\n EndColor Red\n}\n" +
                        "[*] --> A\nA --> [*]\nA --> B\nB --> [*]\nA -> C\n@enduml");
    int finals = 0;
    foreach (var s in d.states) {
        if (s.state_type == StateType.FINAL) finals++;
    }
    assert(finals == 1);
    string dot = state_dot(d);
    assert(dot_attr(dot_line(dot, "_initial_0 ["), "fillcolor") == "MediumBlue");
    assert(dot_attr(dot_line(dot, "_final_0 ["), "fillcolor") == "Red");
    assert(d.transitions[4].arrow_length == 1 && d.transitions[2].arrow_length == 2);
    assert(dot.contains("{ rank=same; A; C; }"));
    assert(!dot.contains("{ rank=same; A; B; }"));

    var c = parse_state("@startuml\nstate Outer {\n  state P {\n    S1 -> S2\n  }\n  Sel --> P : EvNewValue\n  P --> Sel : Back\n}\nP --> P : Again\n@enduml");
    string cdot = state_dot(c);
    string into = dot_line(cdot, "Sel -> ");
    string out_of = dot_line(cdot, "S2 -> Sel") != "" ? dot_line(cdot, "S2 -> Sel") : dot_line(cdot, "S1 -> Sel");
    assert(into.contains("lhead=cluster_1") && into.contains("xlabel=\"EvNewValue\""));
    assert(out_of.contains("ltail=cluster_1") && out_of.contains("xlabel=\"Back\""));
    // the two links end at different nodes
    assert(!into.has_prefix("Sel -> S2") || !out_of.has_prefix("S2 -> "));
    assert(!cdot.contains("P_anchor -> P_anchor"));
    assert(cdot.contains("-> P_loop0 [") && cdot.contains("P_loop0 -> "));
    assert(dot_line(cdot, "S1 -> S2").contains("minlen=0"));
}

// U11: "usecase UC1 as \"Long description\"", "actor A1 as \"Actor desc\"", "\"Main Admin\" as Admin"
void test_usecase_alias_description() {
    var d = parse_usecase("@startuml\nusecase UC1 as \"Long description\"\nactor A1 as \"Actor desc\"\n" +
                          "usecase \"Eat Food\" as UC2\n\"Main Admin\" as Admin\n:User: --> (Use)\n" +
                          "\"Use the application\" as (Use)\nAdmin --> (Use)\n@enduml");
    var uc1 = d.find_usecase("UC1");
    assert(uc1.name == "Long description" && uc1.get_id() == "UC1");
    var a1 = d.find_actor("A1");
    assert(a1.name == "Actor desc" && a1.get_id() == "A1");
    assert(d.find_usecase("UC2").name == "Eat Food");
    var admin = d.find_actor("Admin");
    assert(admin != null && admin.name == "Main Admin");
    var use = d.find_usecase("Use");
    assert(use.name == "Use the application" && use.get_id() == "Use");
    assert(d.use_cases.size == 3 && d.actors.size == 3);
    string dot = usecase_dot(d);
    assert(dot_line(dot, "UC1 [").contains("label=\"Long description\""));
    assert(dot_line(dot, "Admin [").contains(">Main Admin<"));
    assert(dot.contains("Admin -> Use"));
}

// U12: "usecase/ UC3" is a business use case, not a use case named "/"
void test_usecase_business_keyword_form() {
    var d = parse_usecase("@startuml\nusecase/ UC3\nusecase/ (Last usecase) as UC4\npackage P {\n  usecase/ UC5\n}\n@enduml");
    assert(d.find_usecase("/") == null);
    assert(d.find_usecase("UC3").business);
    var uc4 = d.find_usecase("UC4");
    assert(uc4.business && uc4.name == "Last usecase");
    assert(d.find_usecase("UC5").business);
}

// U13: the business actor's slash shows: a light head, a dark slash
void test_usecase_business_actor_slash_visible() {
    string svg = "<svg><g id=\"node1\" class=\"node gdactor gdfill_08427B gdstroke_073B6F gdbusiness\">\n<polygon fill=\"#010203\" stroke=\"none\" points=\"10,-10 10,-56 40,-56 40,-10 10,-10\"/>\n</g></svg>";
    string result = svg_text(RenderUtils.draw_actor_figures(svg.data));
    assert(result.contains("class=\"gdbizhead\"") && result.contains("fill=\"#FFFFFF\""));
    int head = result.index_of("class=\"gdbizhead\"");
    int slash = result.index_of("class=\"gdslash\"");
    assert(head >= 0 && slash > head);
    assert(result.substring(slash).contains("stroke=\"#333333\""));
}

// U14: "skinparam actorStyle awesome|hollow" in use case diagrams
void test_usecase_actor_style() {
    foreach (string style in new string[] { "awesome", "Hollow" }) {
        var d = parse_usecase("@startuml\nskinparam actorStyle %s\nactor A\nA --> (U)\n@enduml".printf(style));
        string line = dot_line(usecase_dot(d), "A [");
        assert(line.contains("gd" + style.down()));
    }
}

// U15: inline element styles beyond the fill
void test_usecase_element_style() {
    var d = parse_usecase("@startuml\nactor b #pink;line:red;line.bold;text:red\n" +
                          "usecase c #palegreen;line:green;line.dashed;text:green\nusecase e #aliceblue;line:blue;line.dotted\n@enduml");
    var b = d.find_actor("b");
    assert(b.color == "#pink" && b.line_color == "#red" && b.line_style == "bold" && b.text_color == "#red");
    var c = d.find_usecase("c");
    assert(c.color == "#palegreen" && c.line_color == "#green" && c.line_style == "dashed" && c.text_color == "#green");
    string dot = usecase_dot(d);
    string bl = dot_line(dot, "b [");
    assert(bl.contains("gdstroke_red") && bl.contains("gdbold") && bl.contains("<FONT COLOR=\"red\">b</FONT>"));
    string cl = dot_line(dot, "c [");
    assert(cl.contains("style=\"filled,dashed\"") && dot_attr(cl, "color") == "green" && dot_attr(cl, "fontcolor") == "green");
    assert(dot_line(dot, "e [").contains("style=\"filled,dotted\""));
}

// U16: a json block under allowmixing is drawn as a table
void test_usecase_json_block() {
    var d = parse_usecase("@startuml\nallowmixing\nactor A\njson J {\n  \"fruit\":\"Apple\",\n  \"color\": [\"Red\", \"Green\"]\n}\n@enduml");
    assert(d.json_blocks.size == 1 && d.json_blocks[0].name == "J");
    assert(d.find_actor("json") == null && d.find_actor("fruit") == null);
    string line = dot_line(usecase_dot(d), "_ucjson0 [");
    assert(line.contains(">J<") && line.contains(">fruit<") && line.contains(">Apple<") &&
           line.contains(">Red<") && line.contains(">Green<"));
    assert(Gvc.Graph.read_string(usecase_dot(d)) != null);
}

// U17: package tabs, "->" side by side, a use case named like its container, newpage
void test_usecase_minor_layout() {
    var p = parse_usecase("@startuml\npackage Restaurant {\n  usecase Eat\n}\nrectangle Sys {\n  usecase Pay\n}\n@enduml");
    string pdot = usecase_dot(p);
    assert(pdot.contains("labeljust=\"l\""));
    assert(count_text(pdot, "labeljust") == 1);
    var r = new UseCaseDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    uint8[]? data = r.render_to_svg(p);
    assert(data != null && svg_text(data).contains("class=\"gdtab\""));
    // "skinparam packageStyle rectangle": no tabs
    var rect = parse_usecase("@startuml\nskinparam packageStyle rectangle\npackage P {\n  usecase U\n}\n@enduml");
    assert(!usecase_dot(rect).contains("labeljust"));

    var h = parse_usecase("@startuml\n:user: --> (UC1)\n:user: -> (UC2)\n@enduml");
    assert(!h.relationships[0].horizontal && h.relationships[1].horizontal);
    string hdot = usecase_dot(h);
    assert(hdot.contains("{ rank=same; user; UC2; }") && !hdot.contains("{ rank=same; user; UC1; }"));

    var c = parse_usecase("@startuml\nrectangle checkout {\n  (checkout) .> (payment) : include\n  (help) .> (checkout) : extends\n}\n@enduml");
    string cdot = usecase_dot(c);
    assert(cdot.contains("_ucpkg0_self [label=\"checkout\", shape=ellipse"));
    assert(cdot.contains("_ucpkg0_self -> payment") && cdot.contains("help -> _ucpkg0_self"));

    var n = parse_usecase("@startuml\n:a1: --> (U1)\nnewpage\n:a2: --> (U2)\n@enduml");
    assert(n.find_actor("newpage") == null && n.find_usecase("newpage") == null);
    assert(!usecase_dot(n).contains("newpage"));
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/component/together_unclosed_no_hang", test_component_together_unclosed_no_hang);
    Test.add_func("/review/usecase_state/unclosed_bodies_no_hang", test_usecase_state_unclosed_bodies_no_hang);
    Test.add_func("/review/all/example_prefixes_no_hang", test_example_prefixes_no_hang);
    Test.add_func("/review/usecase/direction_arrows", test_usecase_direction_arrows);
    Test.add_func("/review/usecase/plain_arrows_unchanged", test_usecase_plain_arrows_unchanged);
    Test.add_func("/review/usecase/hex_link_color", test_usecase_hex_link_color);
    Test.add_func("/review/component/text_contrast", test_component_text_contrast);
    Test.add_func("/review/component/short_and_alpha_hex", test_component_short_and_alpha_hex);
    Test.add_func("/review/state/arrow_direction_and_style", test_state_arrow_direction_and_style);
    Test.add_func("/review/component/link_reuses_declared", test_component_link_reuses_declared);
    Test.add_func("/review/component/link_options_multiplicity", test_component_link_options_direction_and_multiplicity);
    Test.add_func("/review/deployment/ports_in_node", test_deployment_ports_in_node);
    Test.add_func("/review/usecase/note_on_container", test_usecase_note_on_container);
    Test.add_func("/review/usecase/container_body", test_usecase_container_body);
    Test.add_func("/review/state/note_alias_in_composite", test_state_note_alias_in_composite);
    Test.add_func("/review/state/nested_colors", test_state_nested_colors);
    Test.add_func("/review/state/color_spec_line_text", test_state_color_spec_line_text);
    Test.add_func("/review/component/body_links_declare_ends", test_component_links_in_body_declare_ends_there);
    Test.add_func("/review/component/body_link_end_declared_later", test_component_body_link_end_declared_later_wins);
    Test.add_func("/review/deployment/ports_on_border", test_deployment_ports_on_border);
    Test.add_func("/review/component/keyword_bracket_form", test_component_keyword_bracket_form);
    Test.add_func("/review/component/stereotype_before_alias", test_component_stereotype_before_alias);
    Test.add_func("/review/component/style_text_in_bracket_label", test_component_style_text_in_bracket_label);
    Test.add_func("/review/component/apostrophe_in_labels", test_component_apostrophe_in_labels);
    Test.add_func("/review/component/direction_word_aliases", test_component_direction_word_aliases);
    Test.add_func("/review/component/legend", test_component_legend);
    Test.add_func("/review/usecase/alias_forms_and_legend", test_usecase_alias_forms_and_legend);
    Test.add_func("/review/fidelity/note_bracket_target", test_fidelity_note_bracket_target);
    Test.add_func("/review/fidelity/c4_stdlib_include", test_fidelity_c4_stdlib_include);
    Test.add_func("/review/fidelity/c4_expansion_elements", test_fidelity_c4_expansion_elements);
    Test.add_func("/review/fidelity/inline_link_style", test_fidelity_inline_link_style);
    Test.add_func("/review/fidelity/interface_label_in_container", test_fidelity_interface_label_in_container);
    Test.add_func("/review/fidelity/interface_circles", test_fidelity_interface_circles);
    Test.add_func("/review/fidelity/element_shapes", test_fidelity_element_shapes);
    Test.add_func("/review/fidelity/container_shapes", test_fidelity_container_shapes);
    Test.add_func("/review/fidelity/container_theme_colours", test_fidelity_container_theme_colours);
    Test.add_func("/review/fidelity/link_thickness_and_colours", test_fidelity_link_thickness_and_colours);
    Test.add_func("/review/fidelity/inline_element_style", test_fidelity_inline_element_style);
    Test.add_func("/review/fidelity/json_block", test_fidelity_json_block);
    Test.add_func("/review/fidelity/component_style_and_linetype", test_fidelity_component_style_and_linetype);
    Test.add_func("/review/fidelity/minor_layout_and_style", test_fidelity_minor_layout_and_style);
    Test.add_func("/review/state/alias_description", test_state_alias_description);
    Test.add_func("/review/state/history_targets", test_state_history_targets);
    Test.add_func("/review/state/concurrent_regions", test_state_concurrent_regions);
    Test.add_func("/review/state/dot_notation", test_state_dot_notation);
    Test.add_func("/review/state/stereotype_shapes", test_state_stereotype_shapes);
    Test.add_func("/review/state/declared_after_reference_no_ghost", test_state_declared_after_reference_no_ghost);
    Test.add_func("/review/state/capitalised_keyword", test_state_capitalised_keyword);
    Test.add_func("/review/state/note_on_link", test_state_note_on_link);
    Test.add_func("/review/state/toplevel_redeclaration", test_state_toplevel_redeclaration);
    Test.add_func("/review/state/visual_details", test_state_visual_details);
    Test.add_func("/review/usecase/alias_description", test_usecase_alias_description);
    Test.add_func("/review/usecase/business_keyword_form", test_usecase_business_keyword_form);
    Test.add_func("/review/usecase/business_actor_slash_visible", test_usecase_business_actor_slash_visible);
    Test.add_func("/review/usecase/actor_style", test_usecase_actor_style);
    Test.add_func("/review/usecase/element_style", test_usecase_element_style);
    Test.add_func("/review/usecase/json_block", test_usecase_json_block);
    Test.add_func("/review/usecase/minor_layout", test_usecase_minor_layout);
    Test.add_func("/review/c4/sprite_decode", test_c4_sprite_decode);
    Test.add_func("/review/c4/sprite_drawn", test_c4_sprite_drawn);
    Test.add_func("/review/c4/person_sprite_end_to_end", test_c4_person_sprite_end_to_end);
    Test.add_func("/review/c4/transparent_stereotype_hidden", test_c4_transparent_stereotype_hidden);
    Test.add_func("/review/c4/arrow_stereotype_style", test_c4_arrow_stereotype_style);
    Test.add_func("/review/c4/html_edge_label", test_c4_html_edge_label);
    Test.add_func("/review/c4/tab_in_label", test_c4_tab_in_label);
    Test.add_func("/review/c4/direction_across_containers", test_c4_direction_across_containers);
    return Test.run();
}

// ── 2026-09-17: C4-PlantUML rendering gaps ──────────────────────────

Gee.ArrayList<string> string_list(string[] items) {
    var list = new Gee.ArrayList<string>();
    foreach (string item in items) {
        list.add(item);
    }
    return list;
}

// The first <polygon> of an SVG node group: its left x (axis 0) or vertical middle (axis 1)
double svg_node_pos(string svg, string title, int axis) {
    string group = svg_group_of(svg, title);
    int p = group.index_of("points=\"");
    assert(p >= 0);
    string[] pairs = group.substring(p + 8, group.index_of("\"", p + 8) - p - 8).split(" ");
    double lo = double.MAX, hi = -double.MAX;
    foreach (string pair in pairs) {
        string[] xy = pair.split(",");
        if (xy.length == 2) {
            lo = double.min(lo, double.parse(xy[axis]));
            hi = double.max(hi, double.parse(xy[axis]));
        }
    }
    return axis == 0 ? lo : (lo + hi) / 2;
}

double svg_node_left(string svg, string title) {
    return svg_node_pos(svg, title, 0);
}

// 1a. sprite data: "[WxH/16]" hex rows, "/8" and "/4" 6-bit columns, "/16z" deflated. The
// encodings are what plantuml.jar -encodesprite writes for the same 7x5 grey image.
void test_c4_sprite_decode() {
    var hex = string_list({ "FDB9642", "CA8531E", "97420DB", "631FCA8", "20EB974" });
    var s16 = PlantUmlSprite.decode("g", "7x5/16", hex);
    assert(s16 != null && s16.width == 7 && s16.height == 5);
    assert(s16.ink[0] == 255 && s16.ink[1] == 13 * 17 && s16.ink[6] == 2 * 17 && s16.ink[7] == 12 * 17);
    var s8 = PlantUmlSprite.decode("g", "7x5/8", string_list({ "-riYPGF", "ZPGF6ri", "80ueWOG" }));
    assert(s8 != null && s8.ink[0] == 255 && s8.ink[7] == 6 * 255 / 7 && s8.ink[14] == 4 * 255 / 7 && s8.ink[28] == 1 * 255 / 7);
    var s4 = PlantUmlSprite.decode("g", "7x5/4", string_list({ "-vfaGJE", "G0Cuuaa" }));
    assert(s4 != null && s4.ink[0] == 255 && s4.ink[7] == 255 && s4.ink[14] == 170 && s4.ink[21] == 85 && s4.ink[28] == 0);
    var sz = PlantUmlSprite.decode("g", "7x5/16z", string_list({ "3SWt0G0W300me7lxTqjpPYgCyQKhmMqJVAU2uSxEEnqx7m" }));
    assert(sz != null);
    for (int i = 0; i < 35; i++) {
        assert(sz.ink[i] == s16.ink[i]);
    }
    // No size: taken from the hex rows
    var bare = PlantUmlSprite.decode("b", null, string_list({ "0F", "F0", "88" }));
    assert(bare != null && bare.width == 2 && bare.height == 3 && bare.ink[1] == 255 && bare.ink[4] == 136);
    assert(PlantUmlSprite.decode("x", "7x5/16z", string_list({ "!!!!" })) == null);
}

// 1b. "sprite $g [..] { rows }" is read as a sprite (its rows were elements and links), and
// "<$g>" in a label, cluster title and legend cell is drawn: an em space reserves its room,
// the SVG gets the image as a mask filled with the text colour. It was dropped.
void test_c4_sprite_drawn() {
    string src = "@startuml\nsprite $g [7x5/16] {\nFDB9642\nCA8531E\n97420DB\n631FCA8\n20EB974\n}\n" +
        "skinparam rectangle<<red>> {\n  FontColor #FF0000\n}\n" +
        "rectangle \"<$g>\\n== Person\" <<red>> as p\nrectangle \"<$nope> Box\" as q\n" +
        "rectangle \"<$g,scale=2> Group\" as grp {\n  rectangle Inner\n}\n" +
        "legend right\n|<#08427B><color:#00FF00><$g,scale=.5> person</color> |\nendlegend\n@enduml";
    var d = parse_component(src);
    assert(d.sprites.has_key("g") && d.sprites["g"].width == 7);
    assert(d.find_component("FDB9642") == null && d.components.size == 3);
    string dot = component_dot(d);
    assert(dot_line(dot, "p [").contains("<FONT POINT-SIZE=\"7\" COLOR=\"#030000\">&#x2003;</FONT>"));
    assert(dot.contains("<FONT POINT-SIZE=\"14\" COLOR=\"#030001\">&#x2003;</FONT>"));
    assert(dot.contains("<FONT POINT-SIZE=\"4\" COLOR=\"#030002\">&#x2003;</FONT>"));
    assert(!dot.contains("$nope") && !dot.contains("$g"));
    string svg = component_svg(d);
    assert(!svg.contains("fill=\"#030000\"") && !svg.contains("fill=\"#030001\"") && !svg.contains("fill=\"#030002\""));
    string node = svg_group_of(svg, "p");
    assert(node.contains("<mask id=\"gdsprite0\"") && node.contains("xlink:href=\"data:image/png;base64,iVBORw0KGgo"));
    assert(node.contains("width=\"7\" height=\"5\" fill=\"#FF0000\" mask=\"url(#gdsprite0)\""));
    assert(svg.contains("width=\"14\" height=\"10\"") && svg.contains("mask=\"url(#gdsprite1)\""));
    assert(svg.contains("width=\"4\" height=\"3\" fill=\"#00FF00\" mask=\"url(#gdsprite2)\""));
    // The embedded PNG is 7x5
    int b64 = node.index_of("base64,") + 7;
    uchar[] png = Base64.decode(node.substring(b64, node.index_of("\"", b64) - b64));
    assert(png.length > 33 && png[16] == 0 && png[19] == 7 && png[23] == 5);
}

// 1c. the whole C4 path: Person() from the bundled stdlib draws the person sprite
void test_c4_person_sprite_end_to_end() {
    var pp = new Preprocessor();
    string out_text = pp.process("@startuml\n!include <C4/C4_Context>\nPerson(u, \"User\", \"A person\")\n@enduml\n", null);
    var d = parse_component(out_text);
    assert(d.sprites.has_key("person") && d.sprites["person"].width == 48);
    string svg = component_svg(d);
    string node = svg_group_of(svg, "u");
    assert(node.contains("<mask id=\"gdsprite0\"") && node.contains("width=\"48\" height=\"48\" fill=\"#FFFFFF\""));
}

// 2. "skinparam rectangle<<boundary>> { StereotypeFontColor transparent }" (C4 boundaries) hides
// the stereotype; «system_boundary»«boundary» was drawn over every boundary
void test_c4_transparent_stereotype_hidden() {
    var d = parse_component("@startuml\nskinparam rectangle<<boundary>> {\n  StereotypeFontColor transparent\n}\n" +
        "skinparam package<<pkgonly>>StereotypeFontColor transparent\n" +
        "rectangle \"B\" <<system_boundary>><<boundary>> as b {\n  rectangle \"In\" <<container>> as i\n}\n" +
        "rectangle \"C\" <<boundary>> as c\nrectangle \"P\" <<pkgonly>> as p\nrectangle \"O\" <<other>> as o\n@enduml");
    string dot = component_dot(d);
    assert(!dot.contains("«boundary»") && !dot.contains("«system_boundary»") && !dot.contains("«pkgonly»"));
    assert(dot.contains("«container»") && dot.contains("«other»"));
}

// 3. "skinparam arrow<<async>> { Color blue;text:blue;line.dashed }" (C4 AddRelTag) and the
// FontColor / LineColor / LineStyle / Thickness forms style "a --> b <<async>>"; ignored before
void test_c4_arrow_stereotype_style() {
    var d = parse_component("@startuml\nskinparam arrow<<async>> {\n    Color blue;text:blue;line.dashed\n}\n" +
        "skinparam arrow<<t2>> {\n  LineColor 2e7d32\n  FontColor #FF0000\n  LineStyle dotted\n  Thickness 3\n}\n" +
        "a --> b <<async>> : one\nc --> d <<t2>> : two\ne --> f #line:red : three\ng -[#green]-> h <<async>> : four\ni --> j : five\n@enduml");
    assert(d.relationships[0].stereotypes.size == 1 && d.relationships[0].stereotypes[0] == "async");
    assert(d.relationships[0].label == "one" && d.relationships[1].label == "two");
    string dot = component_dot(d);
    string one = dot_line(dot, "a:c -> b:c");
    assert(one.contains("style=dashed") && one.contains(", color=\"blue\"") && one.contains("fontcolor=\"blue\""));
    string two = dot_line(dot, "c:c -> d:c");
    assert(two.contains("style=dotted") && two.contains(", color=\"#2e7d32\"") && two.contains("fontcolor=\"#FF0000\"") && two.contains("penwidth=3"));
    assert(!dot_line(dot, "e:c -> f:c").contains("blue"));
    string four = dot_line(dot, "g:c -> h:c");
    assert(four.contains(", color=\"green\"") && !four.contains(", color=\"blue\"") && four.contains("fontcolor=\"blue\""));
    string five = dot_line(dot, "i:c -> j:c");
    assert(five.contains("style=solid") && !five.contains("color="));
}

// 4. creole in link labels ("**Uses**\n//<size:12>[HTTPS]</size>//" from C4 Rel) as HTML; it was
// stripped to plain text
void test_c4_html_edge_label() {
    var d = parse_component("@startuml\na --> b : **Uses**\\n//<size:12>[HTTPS]</size>//\nc --> d : plain < text\ne -right-> f : <color:red>x & **y**</color>\n@enduml");
    string dot = component_dot(d);
    assert(dot_line(dot, "a:c -> b:c").contains("label=<<B>Uses</B><BR/><I><FONT POINT-SIZE=\"8\">[HTTPS]</FONT></I>>"));
    assert(dot_line(dot, "c:c -> d:c").contains("label=\"plain < text\""));
    assert(dot_line(dot, "e:c -> f:c").contains("label=<<FONT COLOR=\"red\">x &amp; <B>y</B></FONT>>"));
    // arrow FontSize 12 (C4): <size:12> is the label size
    var c4 = parse_component("@startuml\nskinparam arrow {\n  FontSize 12\n}\na --> b : //<size:12>[x]</size>//\n@enduml");
    assert(dot_line(component_dot(c4), "a:c -> b:c").contains("<I><FONT POINT-SIZE=\"9\">[x]</FONT></I>"));
    // Out of order and unclosed markup stays well formed; "~" escapes; URLs keep "//"
    assert(ComponentDiagramRenderer.creole_html("**a //b** c//", 1.0) == "<B>a <I>b</I></B><I> c</I>");
    assert(ComponentDiagramRenderer.creole_html("**open", 1.0) == "<B>open</B>");
    assert(ComponentDiagramRenderer.creole_html("~**x~** see https://a.b <b></b>", 1.0) == "**x** see https://a.b ");
    // The rendered SVG has the bold and italic spans
    string svg = component_svg(d);
    assert(svg.contains("font-weight=\"bold\"") && svg.contains("font-style=\"italic\""));
}

// 5. "\t" in a label is a tab (spaces to the next multiple of 8 characters); it was shown as "\t"
void test_c4_tab_in_label() {
    var d = parse_component("@startuml\nrectangle \"== bigbank-api***\\tx8\" as n\nrectangle \"ab\\tc\" as m\na --> b : x\\ty\n@enduml");
    string dot = component_dot(d);
    assert(!dot.contains("\\t"));
    assert(dot_line(dot, "n [").contains("bigbank-api***  x8"));
    assert(dot_line(dot, "m [").contains("label=\"ab      c\""));
    assert(dot_line(dot, "a:c -> b:c").contains("label=\"x       y\""));
    assert(ComponentDiagramRenderer.expand_tabs("<b>ab</b>\\tc\\nabcdefghi\\tj") == "<b>ab</b>      c\\nabcdefghi       j");
}

// 6. "-right->" / Rel_R between nodes in different containers: side by side (minlen=0, the
// shallow end in an invisible cluster, no anchors in the ends' rank). They were stacked.
void test_c4_direction_across_containers() {
    string src = "@startuml\nrectangle \"Single-Page Application\" as c1\nrectangle \"API\" as b {\n" +
        "  rectangle \"Sign In Controller\" as c2\n  rectangle \"Security\" as c3\n}\n" +
        "c1 -RIGHT->> c2 : **1: submits**\nc2 --> c3\nnode N {\n  node A {\n    rectangle \"Deep\" as x\n  }\n" +
        "  node D {\n    rectangle \"Db\" as y\n  }\n}\nx -right-> y : reads\nlegend right\nkey\nendlegend\n@enduml";
    var d = parse_component(src);
    assert(d.relationships[0].placement == "right");
    string dot = component_dot(d);
    assert(dot_line(dot, "c1 -> c2").contains("minlen=0"));
    assert(dot_line(dot, "x -> y").contains("minlen=0"));
    assert(dot.contains("subgraph cluster_side_0 { style=invis; label=\"\";\n  c1 ["));
    assert(!dot.contains("subgraph cluster_side_1"));
    assert(!dot.contains("b_anchor") && !dot.contains("A_anchor") && !dot.contains("N_anchor"));
    assert(!dot_line(dot, "c2 -> c3").contains("minlen"));
    string svg = component_svg(d);
    assert(svg_node_left(svg, "c1") < svg_node_left(svg, "c2"));
    assert(svg_node_left(svg, "x") < svg_node_left(svg, "y"));
    // Same rank: the middles line up
    assert((svg_node_pos(svg, "c1", 1) - svg_node_pos(svg, "c2", 1)).abs() < 1.0);
    assert((svg_node_pos(svg, "x", 1) - svg_node_pos(svg, "y", 1)).abs() < 1.0);
    // A container end keeps its anchor, and "-left->" is still drawn reversed
    var e = parse_component("@startuml\nrectangle R {\n  rectangle \"In\" as i\n}\nrectangle \"Out\" as o\no -left-> i\no --> R\n@enduml");
    string edot = component_dot(e);
    assert(edot.contains("R_anchor [") && dot_line(edot, "i -> o").contains("minlen=0"));
    assert(svg_node_left(component_svg(e), "i") < svg_node_left(component_svg(e), "o"));
}
