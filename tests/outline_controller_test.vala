/*
 * outline_controller_test.vala — outline entries for the parsed diagram (OutlineController).
 *
 * The controller fills a Gtk.ListBox, so this test needs a display: meson runs it under
 * xvfb-run (a private X server) and skips it where xvfb-run is missing.
 */
using GDiagram;

// "depth:text" of every row, in list order
string[] outline_rows(string source) {
    var engine = new DiagramEngine("dot");
    var result = engine.parse(source, null);
    var list = new Gtk.ListBox();
    var controller = new OutlineController(list);
    controller.update(result.diagram_type, result.ast);
    string[] rows = {};
    for (var child = list.get_first_child(); child != null; child = child.get_next_sibling()) {
        var row = child as OutlineRow;
        if (row == null) continue;
        int depth = 0;
        for (var p = row.node.parent; p != null; p = p.parent) depth++;
        rows += "%d:%s".printf(depth, row.node.text);
    }
    return rows;
}

void expect_rows(string what, string source, string[] want, string[] absent = {}) {
    string[] rows = outline_rows(source);
    string joined = string.joinv("\n", rows);
    bool ok = true;
    foreach (string w in want) {
        if (!(w in rows)) {
            stderr.printf("%s: missing row '%s'\n", what, w);
            ok = false;
        }
    }
    foreach (string a in absent) {
        if (joined.contains(a)) {
            stderr.printf("%s: unexpected '%s'\n", what, a);
            ok = false;
        }
    }
    if (!ok) {
        stderr.printf("%s rows:\n%s\n", what, joined);
        Test.fail();
    }
}

void test_timing() {
    expect_rows("timing",
        "@startuml\nrobust \"Web\" as W\nconcise \"User\" as U\n@0\nW is Idle\nU is Busy\n@100\nU -> W : ping\n" +
        "highlight 0 to 50 #Gold : Setup\n@enduml\n",
        { "0:Web [Robust]", "0:User [Concise]", "0:Messages", "1:U@100 -> W@100: ping", "0:Highlight 0 to 50: Setup" });
}

void test_gantt() {
    expect_rows("gantt",
        "@startgantt\nProject starts 2026-01-05\n[Design] lasts 5 days\n[Design] is 40% completed\n" +
        "[Review] lasts 1 day\n-- Build --\n[Code] lasts 3 days\n[Done] happens at [Code]'s end\n-- Empty --\n@endgantt\n",
        { "0:Design (5 days, 40%)", "0:Review (1 day)", "0:Build", "1:Code (3 days)", "1:Done (milestone)", "0:Empty" },
        { "(1 days)" });
}

void test_sequence() {
    expect_rows("sequence",
        "@startuml\nparticipant A\nparticipant B\nalt ok\n  A -> B : x\n  loop 3 times\n    A -> B : y\n  end\n" +
        "else bad\n  A -> B : z\nend\ngroup Setup\n A -> B : s\nend\nnewpage Second part\nA -> B : n\n@enduml\n",
        { "0:A", "0:B", "0:alt: ok", "1:loop: 3 times", "0:group: Setup", "0:Page 2: Second part" });
}

void test_state() {
    expect_rows("state",
        "@startuml\n[*] --> Active\nstate Active {\n  [*] --> Running\n  Running --> Paused\n  --\n  [*] --> Logging\n}\n" +
        "Active --> Active[H]\nActive --> [*]\n@enduml\n",
        { "0:Active", "1:Region 1", "2:Running", "2:Paused", "1:Region 2", "2:Logging" },
        { "_initial_", "_final_", "_history_" });
}

void test_class_and_c4() {
    expect_rows("class",
        "@startuml\nclass Student\nclass Course\nclass Enrollment\n(Student, Course) .. Enrollment\n@enduml\n",
        { "0:Student", "0:Course", "0:Enrollment / association of Student, Course" });
    expect_rows("c4",
        "@startuml\n!include <C4/C4_Container>\nPerson(customer, \"Customer\", \"A user of the system\")\n" +
        "System_Boundary(c1, \"Online Store\") {\n  Container(web, \"Web App\", \"React\", \"User interface\")\n}\n" +
        "Rel(customer, web, \"Uses\")\n@enduml\n",
        { "0:Customer", "0:Online Store", "1:Web App" },
        { "<$", "==", "React", "User interf" });
}

// Ports are clickable in the preview but had no outline row; they belong under the
// component or node that declares them. An unnamed port ("_port_3") has no source text
// to navigate to and stays out.
void test_deployment_ports() {
    expect_rows("deployment ports",
        "@startuml\n[c]\nnode node {\n  port p1\n  portin p2\n  portout p3\n  file f1\n}\n" +
        "c --> p1\nc --> p2\np1 --> f1\n@enduml\n",
        { "0:node", "1:f1", "1:Port: p1", "1:Port in: p2", "1:Port out: p3" },
        { "_port_" });
}

// Swimlanes, partitions and groups are boxes in the preview and clickable there; the
// outline showed none of them (the old "Partition: " row could only appear on a node
// that was neither a start, a stop nor a labelled action), so the steps inside a
// partition had nothing to hang off.
void test_activity_partitions() {
    expect_rows("activity partitions",
        "@startuml\n|Customer|\nstart\n:Order;\n|Shop|\npartition Checkout {\n  :Pay;\n}\n" +
        "group Shipping\n  :Send;\nend group\nstop\n@enduml\n",
        { "0:Swimlane: Customer", "1:Start", "1:Order", "0:Swimlane: Shop",
          "1:Partition: Checkout", "2:Pay", "1:Partition: Shipping", "2:Send" });
}

// A Mermaid subgraph is a container in the preview, like a PlantUML package, but the
// outline listed the diagram's nodes flat and showed no subgraph at all — so the nodes
// inside one had nothing to hang off, and a nested subgraph was invisible.
void test_mermaid_flowchart_subgraphs() {
    expect_rows("mermaid flowchart subgraphs",
        "flowchart TD\n" +
        "  Loose[Outside]\n" +
        "  subgraph Grp[Group]\n" +
        "    A[First] --> B[Second]\n" +
        "    subgraph Deep[Deeper]\n" +
        "      C[Third]\n" +
        "    end\n" +
        "  end\n" +
        "  Loose --> A\n",
        { "0:Group", "1:Deeper", "2:Third", "1:First", "1:Second", "0:Outside" },
        { "0:First", "0:Second", "0:Third", "1:Outside" });
}

int main(string[] args) {
    Test.init(ref args);
    if (!Gtk.init_check()) {
        Test.message("no display: outline tests skipped");
        return 77;
    }
    Test.add_func("/outline/timing", test_timing);
    Test.add_func("/outline/gantt", test_gantt);
    Test.add_func("/outline/sequence", test_sequence);
    Test.add_func("/outline/state", test_state);
    Test.add_func("/outline/class-c4", test_class_and_c4);
    Test.add_func("/outline/deployment-ports", test_deployment_ports);
    Test.add_func("/outline/activity-partitions", test_activity_partitions);
    Test.add_func("/outline/mermaid-flowchart-subgraphs", test_mermaid_flowchart_subgraphs);
    return Test.run();
}
