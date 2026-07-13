using GDiagram;

// Component diagram with colons in edge labels AND a semicolon inside a node
// label. The old activity heuristic (any ':' + any ';' anywhere) misdetected
// this as ACTIVITY — the exact regression seen with
// docs/architecture/01_architecture_overview.puml.
void test_component_with_semicolon_in_label() {
    string source = """@startuml
package "AST Layer" {
    [Mermaid ASTs\n(one file per type;\nshared enum only)] as mermaid_ast
    [DiagramNode] as base_ast
}
mermaid_ast --> base_ast : produces
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.COMPONENT);
}

// Real activity actions — ':text;' at line starts — must still detect.
void test_activity_action_lines() {
    string source = """@startuml
:Read the file;
:Parse the content;
:Render the diagram;
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.ACTIVITY);
}

// Multi-line action: the ':' opens on one line, the ';' terminates later.
void test_activity_multiline_action() {
    string source = """@startuml
:This is a long action
that spans two lines;
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.ACTIVITY);
}

// start/stop keywords alone must still detect as activity.
void test_activity_start_stop() {
    string source = """@startuml
start
:Do something;
stop
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.ACTIVITY);
}

// Sequence messages use mid-line colons; a semicolon in a note must not
// flip detection to ACTIVITY.
void test_sequence_with_semicolon_in_note() {
    string source = """@startuml
participant Alice
participant Bob
Alice -> Bob : hello there
note right of Bob : uses gtk; cairo and librsvg
Bob --> Alice : hi
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.SEQUENCE);
}


// A legend/caption/note TABLE row looks exactly like an activity swimlane
// ("| <#C8E6C9> | primary |" vs "|#color|Lane|"). A user's component diagram with a
// colour-key legend was detected as ACTIVITY and then failed to export outright.
void test_legend_table_is_not_a_swimlane() {
    string source = """@startuml
rectangle "nginx" as a
rectangle "haproxy" as b
a --> b : https
legend right
  | <#C8E6C9> | primary |
  | <#FFE0B2> | fallback |
endlegend
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.COMPONENT);
}

// ...while a real swimlane still means an activity diagram.
void test_swimlane_still_detects_activity() {
    string source = """@startuml
|Customer|
:places order;
|#AntiqueWhite|Warehouse|
:ships it;
stop
@enduml
""";
    assert(TypeDetector.detect_plantuml(source) == DiagramType.ACTIVITY);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/type-detector/component_with_semicolon_in_label",
                  test_component_with_semicolon_in_label);
    Test.add_func("/type-detector/activity_action_lines",
                  test_activity_action_lines);
    Test.add_func("/type-detector/activity_multiline_action",
                  test_activity_multiline_action);
    Test.add_func("/type-detector/activity_start_stop",
                  test_activity_start_stop);
    Test.add_func("/type-detector/legend_table_not_swimlane", test_legend_table_is_not_a_swimlane);
    Test.add_func("/type-detector/swimlane_still_activity", test_swimlane_still_detects_activity);
    Test.add_func("/type-detector/sequence_with_semicolon_in_note",
                  test_sequence_with_semicolon_in_note);
    return Test.run();
}
