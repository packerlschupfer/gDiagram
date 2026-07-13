/*
 * plantuml_renderer_snapshot_test.vala — content-based tests for the
 * PlantUML renderer subtree (mirror of the Mermaid snapshot test).
 *
 * Covers: Class, Component/C4, Activity, State, ER. These five span
 * the main PlantUML renderer subdirectories (structural, behavioral,
 * specialized) and each uses a different layout pattern (record,
 * clusters, swim-lane arrows, stereotypes).
 *
 * Same design principle as the Mermaid snapshot tests: assert on
 * substrings the renderer puts in the SVG (labels, stereotypes,
 * titles) rather than on exact coordinates or byte-level output.
 */
using GDiagram;

void puml_assert_svg_contains(uint8[]? svg_data, string label, string[] expected) {
    assert(svg_data != null);
    assert(svg_data.length > 0);

    string svg_str;
    unowned string raw = (string) svg_data;
    if (raw.length == svg_data.length) {
        svg_str = raw;
    } else {
        svg_str = raw.substring(0, svg_data.length);
    }

    if (!svg_str.contains("<svg")) {
        stderr.printf("[%s] SVG missing <svg tag\n", label);
        assert_not_reached();
    }
    if (!svg_str.contains("</svg>")) {
        stderr.printf("[%s] SVG missing </svg>\n", label);
        assert_not_reached();
    }

    foreach (var needle in expected) {
        if (!svg_str.contains(needle)) {
            stderr.printf("[%s] Expected '%s' in SVG but not found\n", label, needle);
            assert_not_reached();
        }
    }
}

// Helper: lex PlantUML source into tokens.
Gee.ArrayList<Token> lex_puml(string source) {
    var lexer = new Lexer(source);
    return lexer.scan_all();
}

// =====================================================================

void test_class_diagram_snapshot() {
    string source = """@startuml
class Vehicle {
  +String model
  +int year
  +start()
}
class Car {
  +int doors
  +drive()
}
Vehicle <|-- Car
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ClassDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.classes.size == 2);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ClassDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "class", {
        "Vehicle", "Car", "model", "year", "start", "doors", "drive"
    });
}

void test_component_c4_snapshot() {
    string source = """@startuml
title C4 Context
rectangle "Customer" <<person>> as customer
rectangle "Shopping App" <<system>> as app
rectangle "Payment Gateway" <<external_system>> as pay
customer --> app : "Uses"
app --> pay : "Charges"
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ComponentDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ComponentDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    // C4 rectangles with stereotypes must appear as labels and the
    // stereotype palette colors must reach the SVG (container_fill).
    puml_assert_svg_contains(svg, "component/c4", {
        "Customer", "Shopping App", "Payment Gateway", "Uses", "Charges"
    });
}

void test_activity_diagram_snapshot() {
    string source = """@startuml
start
:Initialize;
if (Ready?) then (yes)
  :Process;
else (no)
  :Abort;
endif
:Complete;
stop
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ActivityDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.nodes.size > 0);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ActivityDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "activity", {
        "Initialize", "Process", "Abort", "Complete"
    });
}

void test_state_diagram_snapshot() {
    string source = """@startuml
[*] --> Idle
Idle --> Loading : start
Loading --> Success : ok
Loading --> Failed : error
Success --> [*]
Failed --> Idle : retry
@enduml""";

    var tokens = lex_puml(source);
    var parser = new StateDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.states.size > 0);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new StateDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "state", {
        "Idle", "Loading", "Success", "Failed", "start", "retry"
    });
}

void test_er_diagram_snapshot() {
    // Full rich ER syntax: PK markers (*), attribute separator (--),
    // typed attributes, and cardinality relationship. Used to hang the
    // parser until the MULT-vs-IDENTIFIER bug in parse_entity_attribute
    // was fixed — now serves as a regression test.
    string source = """@startuml
entity Customer {
  * id : int
  --
  * name : string
  email : string
}
entity Order {
  * id : int
  --
  * customer_id : int
  total : decimal
}
Customer ||--o{ Order
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ERDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.entities.size == 2);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ERDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "er", {
        "Customer", "Order", "name", "email", "total"
    });
}

// =====================================================================
// Remaining PlantUML renderer tests (12 types)
// =====================================================================

void test_sequence_diagram_snapshot() {
    string source = """@startuml
participant Alice
participant Bob
Alice -> Bob : Hello
Bob --> Alice : Hi back
@enduml""";

    // GDiagram.Parser handles lexing internally for sequence diagrams.
    var parser = new GDiagram.Parser();
    var diagram = parser.parse(source);
    assert(diagram.participants.size == 2);
    assert(diagram.messages.size == 2);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new SequenceDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "sequence", {
        "Alice", "Bob", "Hello", "Hi back"
    });
}

void test_usecase_diagram_snapshot() {
    // Top-level use cases (no rectangle wrapper). Use cases inside a
    // `rectangle { }` block live on the package, not on diagram.use_cases.
    string source = """@startuml
left to right direction
actor User
actor Admin
usecase "Login" as UC1
usecase "View Dashboard" as UC2
usecase "Manage Users" as UC3
User --> UC1
User --> UC2
Admin --> UC3
@enduml""";

    var tokens = lex_puml(source);
    var parser = new UseCaseDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.actors.size >= 2);
    assert(diagram.use_cases.size >= 3);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new UseCaseDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "usecase", {
        "User", "Admin", "Login", "Dashboard", "Manage Users"
    });
}

void test_object_diagram_snapshot() {
    string source = """@startuml
object alice {
  name = "Alice"
  age = 30
}
object bob {
  name = "Bob"
  age = 25
}
alice --> bob : knows
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ObjectDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.objects.size == 2);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ObjectDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "object", {
        "alice", "bob", "Alice", "Bob", "knows"
    });
}

// Deployment-style files (node, artifact, database) go through the component path
void test_deployment_diagram_snapshot() {
    string source = """@startuml
node Server {
  artifact "app.jar" as app
}
database "Postgres" as db
Server --> db : JDBC
@enduml""";

    assert(TypeDetector.detect_plantuml(source) == DiagramType.COMPONENT);
    var tokens = lex_puml(source);
    var parser = new ComponentDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.components.size > 0);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ComponentDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "deployment", {
        "Server", "Postgres", "JDBC"
    });
}

void test_mindmap_diagram_snapshot() {
    string source = """@startmindmap
* Root
** Branch A
*** Leaf A1
*** Leaf A2
** Branch B
*** Leaf B1
@endmindmap""";

    var tokens = lex_puml(source);
    var parser = new MindMapDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MindMapDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "mindmap", {
        "Root", "Branch A", "Leaf A1", "Branch B"
    });
}

void test_archimate_diagram_snapshot() {
    string source = """@startuml
archimate #Business "Customer" as customer <<Actor>>
archimate #Application "Order App" as app <<Application>>
archimate #Technology "DB Server" as db <<Node>>
customer --> app : Uses
app --> db : Stores
@enduml""";

    var parser = new ArchimateDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.elements.size == 3);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ArchimateDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "archimate", {
        "Customer", "Order App", "DB Server"
    });
}

void test_json_diagram_snapshot() {
    string source = """@startjson
{
  "name": "Alice",
  "age": 30,
  "active": true
}
@endjson""";

    var parser = new JsonDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.root != null);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new JsonDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "json", {
        "name", "Alice", "age", "active"
    });
}

void test_yaml_diagram_snapshot() {
    string source = """@startyaml
name: Alice
age: 30
active: true
@endyaml""";

    var parser = new YamlDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.root != null);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new YamlDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "yaml", {
        "name", "Alice", "age", "active"
    });
}

void test_gantt_diagram_snapshot() {
    string source = """@startgantt
[Design] requires 5 days
[Development] requires 10 days
[Testing] requires 3 days
[Development] starts at [Design]'s end
[Testing] starts at [Development]'s end
@endgantt""";

    var parser = new GanttDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.tasks.size == 3);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new GanttDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "gantt", {
        "Design", "Development", "Testing"
    });
}

void test_timing_diagram_snapshot() {
    string source = """@startuml
binary "Clock" as CLK
binary "Data" as DATA
@0
CLK is HIGH
DATA is LOW
@5
CLK is LOW
@10
CLK is HIGH
DATA is HIGH
@enduml""";

    var parser = new TimingDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.signals.size == 2);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new TimingDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "timing", {
        "Clock", "Data"
    });
}

void test_nwdiag_diagram_snapshot() {
    string source = """@startuml
nwdiag {
  network dmz {
    address = "192.168.0.x/24"
    web01 [address = "192.168.0.1"]
    web02 [address = "192.168.0.2"]
  }
  network internal {
    address = "10.0.0.x/24"
    web01 [address = "10.0.0.1"]
    db01  [address = "10.0.0.2"]
  }
}
@enduml""";

    var parser = new NwdiagDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.networks.size == 2);
    // Each network should have parsed nodes. Used to be broken because
    // `node [address = ...]` lines matched the parser's bare-property
    // check and got consumed without entering parse_network_node.
    assert(diagram.networks.get(0).nodes.size > 0);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new NwdiagDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "nwdiag", {
        "dmz", "internal", "web01", "db01"
    });
}

void test_chronology_diagram_snapshot() {
    string source = """@startchronology
title Product Roadmap
[Kickoff] happens on 2025-01-01
[Alpha] happens on 2025-04-01
[Beta] happens on 2025-06-01
[GA] happens on 2025-09-01
@endchronology""";

    var parser = new ChronologyDiagramParser();
    var diagram = parser.parse(source);
    assert(!diagram.has_errors());
    assert(diagram.events.size == 4);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ChronologyDiagramRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    puml_assert_svg_contains(svg, "chronology", {
        "Kickoff", "Alpha", "Beta", "GA"
    });
}

// =====================================================================
// Edge-case fuzz tests — hunt for parser hangs and crashes on malformed
// or adversarial input. Each test runs under the overall test timeout;
// individual inputs here are deliberately trying to trip up parsers that
// use `while (!is_at_end())` patterns without reliable forward progress.
// =====================================================================

void assert_parser_does_not_hang(string label) {
    // This is a marker — the real timeout comes from running the test
    // with `timeout 5s` externally. We just need to confirm the parser
    // returned. The assertion value here is that execution reached the
    // end of the test function at all.
    stderr.printf("[fuzz] %s completed\n", label);
}

void test_fuzz_class_parser() {
    string[] inputs = {
        // Empty
        "@startuml\n@enduml",
        // Only start tag
        "@startuml",
        // Stray operators
        "@startuml\n* * *\n@enduml",
        "@startuml\n< > | = & ^\n@enduml",
        // Mismatched braces
        "@startuml\nclass Foo {\n@enduml",
        "@startuml\nclass Foo {\n  + bar\n  + baz\n@enduml",
        // Deeply nested / weird
        "@startuml\nclass A { + x : Map<String, List<Integer>> }\n@enduml",
        // Unicode
        "@startuml\nclass 日本語 { + メソッド() }\n@enduml",
        // Isolated punctuation
        "@startuml\n{\n}\n@enduml",
    };
    var parser = new ClassDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        // Only assertion: it returned.
        assert(diagram != null);
    }
    assert_parser_does_not_hang("class");
}

void test_fuzz_state_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\n[*]\n@enduml",
        "@startuml\nA --> B\n@enduml",
        "@startuml\nstate S {\n@enduml",            // unclosed composite
        "@startuml\nstate S {\nA --> B\n}\n@enduml",
        "@startuml\n--> --> -->\n@enduml",          // stray arrows
        "@startuml\nstate \"Weird <name>\" as s1\n@enduml",
    };
    var parser = new StateDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("state");
}

void test_fuzz_activity_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nstart\nstop\n@enduml",
        "@startuml\n:A;\n:B;\n@enduml",
        "@startuml\nif (cond) then\nendif\n@enduml",          // missing else branch
        "@startuml\nif (cond) then\nelse\nendif\n@enduml",   // empty branches
        "@startuml\nrepeat\n  :work;\nrepeat while (more?)\n@enduml",
        "@startuml\npartition X {\n:A;\n@enduml",            // unclosed partition
    };
    var parser = new ActivityDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("activity");
}

void test_fuzz_component_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\n[Comp]\n@enduml",
        "@startuml\n() \"iface\" as I\n[A] --> I\n@enduml",
        "@startuml\npackage P {\n[A]\n@enduml",              // unclosed package
        "@startuml\nrectangle R <<system>>\n@enduml",
        "@startuml\nrectangle \"Multi\\nLine\" <<container>>\n@enduml",
    };
    var parser = new ComponentDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("component");
}

void test_fuzz_er_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nentity A\n@enduml",
        "@startuml\nentity A {\n}\n@enduml",
        "@startuml\nentity A {\n  * id : int\n  --\n  * name : string\n}\n@enduml",
        "@startuml\nentity A {\n  * id\n  * name\n  --\n  age\n}\n@enduml",
        "@startuml\n* * *\n@enduml",                          // stray markers
        "@startuml\nentity A { * }\n@enduml",                 // * without name
    };
    var parser = new ERDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("er");
}

void test_fuzz_usecase_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nactor User\n@enduml",
        "@startuml\nactor A\nactor B\n(UC)\nA --> (UC)\n@enduml",
        "@startuml\nrectangle R {\n@enduml",                  // unclosed
    };
    var parser = new UseCaseDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("usecase");
}

void test_fuzz_object_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nobject Alice\n@enduml",
        "@startuml\nobject Alice { name = \"A\"\n@enduml",     // unclosed
        "@startuml\nobject A\nobject B\nA --> B\n@enduml",
    };
    var parser = new ObjectDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("object");
}

// Deployment-style input, which the component parser handles
void test_fuzz_deployment_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nnode N\n@enduml",
        "@startuml\nnode N {\nartifact A\n@enduml",          // unclosed node
        "@startuml\ndevice D {\nnode N {\n@enduml",           // unclosed device
        "@startuml\ndevice\n@enduml",
        "@startuml\ndevice \"D\" as\n@enduml",
        "@startuml\ndatabase \"db\" as d\n@enduml",
        "@startuml\ncloud {\n@enduml",
    };
    var parser = new ComponentDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("deployment");
}

void test_fuzz_nwdiag_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nnwdiag {\n@enduml",
        "@startuml\nnwdiag {\nnetwork X { }\n}\n@enduml",
        // The bug I just fixed: node attrs with `=` inside brackets
        "@startuml\nnwdiag {\nnetwork n1 {\n  host1 [address = \"1.2.3.4\"]\n}\n}\n@enduml",
        // Empty network
        "@startuml\nnwdiag {\nnetwork n1 { }\n}\n@enduml",
    };
    var parser = new NwdiagDiagramParser();
    foreach (var src in inputs) {
        var diagram = parser.parse(src);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("nwdiag");
}

void test_fuzz_archimate_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\narchimate \"X\" as x <<Actor>>\n@enduml",
        "@startuml\narchimate #Business \"A\" as a\n@enduml",  // missing stereotype
        "@startuml\narchimate\n@enduml",                       // keyword only
    };
    var parser = new ArchimateDiagramParser();
    foreach (var src in inputs) {
        var diagram = parser.parse(src);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("archimate");
}

void test_fuzz_json_parser() {
    string[] inputs = {
        "@startjson\n{}\n@endjson",
        "@startjson\n[]\n@endjson",
        "@startjson\n{ \"a\": [1, 2, { \"b\": null }] }\n@endjson",
        "@startjson\n{ \"a\":\n@endjson",                      // truncated
        "@startjson\nnot json at all\n@endjson",
    };
    var parser = new JsonDiagramParser();
    foreach (var src in inputs) {
        var diagram = parser.parse(src);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("json");
}

void test_fuzz_yaml_parser() {
    string[] inputs = {
        "@startyaml\n@endyaml",
        "@startyaml\na: 1\n@endyaml",
        "@startyaml\nlist:\n  - a\n  - b\n  - c\n@endyaml",
        "@startyaml\na:\n  b:\n    c: 1\n@endyaml",
        "@startyaml\n: : :\n@endyaml",                           // stray colons
    };
    var parser = new YamlDiagramParser();
    foreach (var src in inputs) {
        var diagram = parser.parse(src);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("yaml");
}

void test_fuzz_mindmap_parser() {
    string[] inputs = {
        "@startmindmap\n@endmindmap",
        "@startmindmap\n* Root\n@endmindmap",
        "@startmindmap\n* A\n** B\n*** C\n**** D\n@endmindmap",
        "@startmindmap\n****** Too deep\n@endmindmap",          // root at depth 6
    };
    var parser = new MindMapDiagramParser();
    foreach (var src in inputs) {
        var tokens = lex_puml(src);
        var diagram = parser.parse(tokens);
        assert(diagram != null);
    }
    assert_parser_does_not_hang("mindmap");
}

// =====================================================================
// Palette integration: verify PlantUML renderers respond to palette swap
// =====================================================================

void test_plantuml_palette_integration() {
    string source = """@startuml
class Foo {
  +bar()
}
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ClassDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ClassDiagramRenderer(ctx, regions, "dot");

    // Light palette
    var light = ThemeManager.get_preset("default-light");
    ThemeManager.set_active_palette(light);
    string light_dot = renderer.generate_dot(diagram);
    assert(light_dot.contains(light.background));

    // Solarized-dark palette — very different background
    var sol_dark = ThemeManager.get_preset("solarized-dark");
    ThemeManager.set_active_palette(sol_dark);
    string dark_dot = renderer.generate_dot(diagram);
    assert(dark_dot.contains(sol_dark.background));
    assert(sol_dark.background != light.background);

    // Restore so later tests see the default baseline.
    ThemeManager.set_active_palette(light);
}

// =====================================================================
// Note legibility: a note keeps a light fill on every palette, so its text
// must get a fill-derived (or skinparam-supplied) foreground rather than
// inheriting the global node font color — which is light on dark themes.

void test_note_font_contrasts_with_fill() {
    string source = """@startuml
rectangle "A" <<container>> as a
note right of a
  is this legible?
end note
@enduml""";

    var tokens = lex_puml(source);
    var parser = new ComponentDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ComponentDiagramRenderer(ctx, regions, "dot");

    var light = ThemeManager.get_preset("default-light");
    var dark = ThemeManager.get_preset("default-dark");

    // On BOTH palettes the note fill stays light, so the note font must be
    // dark — never the palette's own (light) node_text.
    foreach (var palette in new Palette[] { light, dark }) {
        ThemeManager.set_active_palette(palette);
        string dot = renderer.generate_dot(diagram);
        string expected = "fillcolor=\"%s\", fontcolor=\"%s\"".printf(
            palette.accent_secondary, RenderUtils.contrast_text(palette.accent_secondary));
        if (!dot.contains(expected)) {
            stderr.printf("[note_contrast] expected '%s' in DOT\n%s\n", expected, dot);
            assert_not_reached();
        }
    }

    ThemeManager.set_active_palette(light);
}

void test_note_font_color_skinparam_honoured() {
    // Both spellings PlantUML accepts for the same setting.
    string[] sources = {
        """@startuml
skinparam note {
  BackgroundColor #FFF6CC
  FontColor #1A1A1A
}
rectangle "A" <<container>> as a
note right of a
  explicit font color
end note
@enduml""",
        """@startuml
skinparam noteBackgroundColor #FFF6CC
skinparam noteFontColor #1A1A1A
rectangle "A" <<container>> as a
note right of a
  explicit font color
end note
@enduml"""
    };

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ComponentDiagramRenderer(ctx, regions, "dot");
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-dark"));

    foreach (var source in sources) {
        var parser = new ComponentDiagramParser();
        var diagram = parser.parse(lex_puml(source));
        assert(!diagram.has_errors());

        string dot = renderer.generate_dot(diagram);
        if (!dot.contains("fillcolor=\"#FFF6CC\", fontcolor=\"#1A1A1A\"")) {
            stderr.printf("[note_skinparam] skinparam note colors ignored\n%s\n", dot);
            assert_not_reached();
        }
    }

    ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
}

void test_note_on_container_uses_cluster_anchor() {
    // A container renders as a cluster, not a node. Without the anchor
    // redirect Graphviz invents a default ellipse named after the alias.
    string source = """@startuml
rectangle "Boundary" <<system_boundary>> as outer {
  rectangle "Inner" <<component>> as inner
}
note right of outer
  attached to a cluster
end note
@enduml""";

    var parser = new ComponentDiagramParser();
    var diagram = parser.parse(lex_puml(source));
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new ComponentDiagramRenderer(ctx, regions, "dot");
    string dot = renderer.generate_dot(diagram);

    assert(dot.contains("-> outer_anchor"));
    // The bare alias must not appear as an edge target — that's the bubble.
    assert(!dot.contains("-> outer ["));
}

void test_style_block_is_skipped_not_parsed() {
    // <style> bodies contain element names ("note {") that must not be
    // parsed as diagram elements — doing so swallowed the whole file.
    string source = """@startuml
<style>
note {
  BackGroundColor #FFF6CC
  FontColor #101010
}
</style>
rectangle "A" <<container>> as a
note right of a
  survives the style block
end note
@enduml""";

    var parser = new ComponentDiagramParser();
    var diagram = parser.parse(lex_puml(source));
    assert(!diagram.has_errors());

    // The rectangle and exactly one note survive...
    assert(diagram.components.size == 1);
    assert(diagram.notes.size == 1);
    assert(diagram.notes.get(0).text.contains("survives the style block"));
    // ...and no part of the style block leaked into the note text.
    assert(!diagram.notes.get(0).text.contains("BackGroundColor"));
}

// =====================================================================
// A bare "end" inside a note body is prose, not the "end note" terminator.
// The parsers used to consume the END token before checking what followed,
// which silently deleted the word from the rendered diagram.

const string END_NOTE_BODY = """  the end is nigh
  reaching the end of the file
  ENDED and endless survive""";

void puml_assert_note_keeps_end(string label, string text) {
    foreach (var needle in new string[] { "the end is nigh", "reaching the end of the file",
                                          "ENDED", "endless" }) {
        if (!text.contains(needle)) {
            stderr.printf("[%s] note body lost '%s' — got: %s\n", label, needle, text);
            assert_not_reached();
        }
    }
}

void test_note_body_keeps_bare_end_word() {
    var state = new StateDiagramParser().parse(lex_puml("""@startuml
state "A" as a
note right of a
""" + END_NOTE_BODY + """
end note
@enduml"""));
    assert(state.notes.size == 1);
    puml_assert_note_keeps_end("state", state.notes.get(0).text);

    // The class parser had the same bug in truncating form: its loop stopped
    // at any END, dropping the rest of the note entirely.
    var cls = new ClassDiagramParser().parse(lex_puml("""@startuml
class A
note top of A
""" + END_NOTE_BODY + """
end note
@enduml"""));
    assert(cls.notes.size == 1);
    puml_assert_note_keeps_end("class", cls.notes.get(0).text);

    var obj = new ObjectDiagramParser().parse(lex_puml("""@startuml
object A
note right of A
""" + END_NOTE_BODY + """
end note
@enduml"""));
    assert(obj.notes.size == 1);
    puml_assert_note_keeps_end("object", obj.notes.get(0).text);

    var uc = new UseCaseDiagramParser().parse(lex_puml("""@startuml
usecase A
note right of A
""" + END_NOTE_BODY + """
end note
@enduml"""));
    assert(uc.notes.size == 1);
    puml_assert_note_keeps_end("usecase", uc.notes.get(0).text);

    var dep = new ComponentDiagramParser().parse(lex_puml("""@startuml
node A
note right of A
""" + END_NOTE_BODY + """
end note
@enduml"""));
    assert(dep.notes.size == 1);
    puml_assert_note_keeps_end("component", dep.notes.get(0).text);
}

// =====================================================================
// State diagrams: per-state colour and inline markup, both of which the
// component renderer already supported.

string puml_state_dot(string source) {
    var diagram = new StateDiagramParser().parse(lex_puml(source));
    assert(!diagram.has_errors());
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    return new StateDiagramRenderer(ctx, regions, "dot").generate_dot(diagram);
}

void test_state_background_per_stereotype() {
    // Each BackgroundColor<<x>> needs its own key; they used to collide on
    // "BackgroundColor" so the last declaration coloured every state.
    string dot = puml_state_dot("""@startuml
skinparam state {
  BackgroundColor<<good>> #2E7D32
  BackgroundColor<<bad>>  #B71C1C
}
state "plain" as p
state "good" as g <<good>>
state "bad" as b <<bad>>
@enduml""");

    assert(dot.contains("g [label=\"good\", shape=box, style=\"rounded,filled\", fillcolor=\"#2E7D32\""));
    assert(dot.contains("b [label=\"bad\", shape=box, style=\"rounded,filled\", fillcolor=\"#B71C1C\""));
    // The unstereotyped state keeps the palette default, not either colour.
    assert(!dot.contains("p [label=\"plain\", shape=box, style=\"rounded,filled\", fillcolor=\"#B71C1C\""));
}

void test_state_inline_color() {
    // scan_color() returns "#RRGGBB" as one IDENTIFIER, so the parser's bare
    // HASH check missed the usual spelling entirely.
    string dot = puml_state_dot("""@startuml
state "ended cleanly" as ok #2E7D32
state "plain" as p
@enduml""");

    // Dark fill ⇒ light text, via the shared contrast helper. The border
    // between them is palette-dependent, so build the needle from the palette
    // rather than hard-coding a colour another test may have changed.
    string border = ThemeManager.get_active_palette().accent_primary;
    string expected = "fillcolor=\"#2E7D32\", color=\"%s\", fontcolor=\"#FFFFFF\"".printf(border);
    if (!dot.contains(expected)) {
        stderr.printf("[state_inline_color] expected '%s' in:\n%s\n", expected, dot);
        assert_not_reached();
    }
}

void test_state_edge_label_strips_creole() {
    // The state parser rejoins tokens with spaces, so "**x**" arrives as
    // "* * x * *" — the stripper has to tolerate that spacing.
    string dot = puml_state_dot("""@startuml
state "a" as a
state "b" as b
a --> b : ran out\n**because it could not go on**
@enduml""");

    assert(dot.contains("because it could not go on"));
    if (dot.contains("*")) {
        stderr.printf("[state_creole] literal asterisks survived:\n%s\n", dot);
        assert_not_reached();
    }
}

// =====================================================================
// 2026-09-14 round: include base path, description-in-braces states, theme
// skinparam blocks in state diagrams, conservative Creole stripping.

void test_include_resolves_against_document_file() {
    // The CLI passed the document's FILE path as the include base, so
    // "!include theme.puml" became "diagram.puml/theme.puml" and the theme was
    // silently dropped unless the cwd happened to be the diagram's directory.
    string dir = "";
    try {
        dir = DirUtils.make_tmp("gdiagram-include-XXXXXX");
        FileUtils.set_contents(Path.build_filename(dir, "theme.puml"),
            "@startuml\nskinparam backgroundColor #123456\n@enduml\n");
    } catch (Error e) {
        stderr.printf("[include] setup failed: %s\n", e.message);
        assert_not_reached();
    }
    string source = "@startuml\n!include theme.puml\nstate A\n@enduml\n";

    var pp = new Preprocessor();
    string via_file = pp.process(source, Path.build_filename(dir, "diagram.puml"));
    string via_dir = pp.process(source, dir);

    FileUtils.remove(Path.build_filename(dir, "theme.puml"));
    DirUtils.remove(dir);

    assert(via_file.contains("#123456"));
    assert(via_dir.contains("#123456"));
}

void test_state_description_block_is_simple_state() {
    // "state X { X : text }" is PlantUML's description-in-braces form. It used
    // to become an empty cluster: the state vanished and its text was lost.
    string dot = puml_state_dot("""@startuml
state IDLE {
    IDLE : Entry: All relays OFF
    IDLE : Do: Wait for demand
}
[*] --> IDLE
@enduml""");

    if (dot.contains("subgraph cluster") || dot.contains("IDLE_anchor")) {
        stderr.printf("[state_desc_block] still rendered as a composite:\n%s\n", dot);
        assert_not_reached();
    }
    assert(dot.contains("IDLE [label=\"IDLE"));
    assert(dot.contains("All relays OFF"));
    assert(dot.contains("Wait for demand"));
}

void test_state_theme_skinparam_blocks_do_not_create_states() {
    // "note" and "class" lex as keywords; the state parser rejected them as
    // skinparam element names and parsed the block body as states.
    string dot = puml_state_dot("""@startuml
skinparam note {
    BackgroundColor #2F4F4F
    FontColor #ffffff
}
skinparam class {
    HeaderBackgroundColor #2F4F4F
}
state A
note right of A
  themed
end note
@enduml""");

    foreach (var ghost in new string[] { "BackgroundColor [", "FontColor [", "HeaderBackgroundColor [" }) {
        if (dot.contains(ghost)) {
            stderr.printf("[state_skinparam] ghost state '%s' in:\n%s\n", ghost, dot);
            assert_not_reached();
        }
    }
    assert(dot.contains("shape=note, style=filled, fillcolor=\"#2F4F4F\""));
    assert(dot.down().contains("fontcolor=\"#ffffff\""));
}

void test_state_note_on_composite_uses_anchor() {
    string dot = puml_state_dot("""@startuml
state Outer {
  [*] --> Inner
}
note right of Outer
  on a composite
end note
@enduml""");

    assert(dot.contains("-> Outer_anchor"));
    assert(!dot.contains("-> Outer ["));
}

void test_edge_label_keeps_leading_less_than() {
    // "< 100ms" is content. The C4-oriented stripper deleted a leading "< "
    // as a macro leftover, in both state and component edge labels.
    string sdot = puml_state_dot("""@startuml
state A
state B
A --> B : < 100ms
@enduml""");
    if (!sdot.contains("< 100")) {
        stderr.printf("[edge_lt] state label lost '<':\n%s\n", sdot);
        assert_not_reached();
    }

    var comp = new ComponentDiagramParser().parse(lex_puml("""@startuml
component [A] as a
component [B] as b
a --> b : < 100ms
@enduml"""));
    var ctx = new Gvc.Context();
    string cdot = new ComponentDiagramRenderer(ctx, new Gee.ArrayList<ElementRegion>(), "dot").generate_dot(comp);
    if (!cdot.contains("< 100")) {
        stderr.printf("[edge_lt] component label lost '<':\n%s\n", cdot);
        assert_not_reached();
    }
}

void test_note_body_strips_bold_markup() {
    string dot = puml_state_dot("""@startuml
state A
note right of A
  **Safety Checks:**
  plain line
end note
@enduml""");

    assert(dot.contains("Safety Checks"));
    if (dot.contains("*")) {
        stderr.printf("[note_bold] literal asterisks survived:\n%s\n", dot);
        assert_not_reached();
    }
}

void test_element_fill_does_not_inherit_canvas_background() {
    // A bare "skinparam backgroundColor" is the canvas. It used to become the
    // fallback fill for notes and states too, making them invisible.
    string dot = puml_state_dot("""@startuml
skinparam backgroundColor #101010
state A
note right of A
  visible
end note
@enduml""");

    assert(dot.contains("bgcolor=\"#101010\""));
    if (dot.contains("fillcolor=\"#101010\"")) {
        stderr.printf("[canvas_fill] element filled with canvas colour:\n%s\n", dot);
        assert_not_reached();
    }
}

// =====================================================================
// 2026-09-14 round 2: class/use-case/object/deployment theme blocks, class
// {static} and notes, component labels/storage/dotted arrows/label spacing,
// sequence theme colours and note placement. Driven through DiagramEngine so
// each source goes through the same detection and parser a user gets.

string engine_dot(string source) {
    var engine = new DiagramEngine("dot");
    string? dot = engine.generate_dot(source, "test.puml", null);
    assert(dot != null);
    return dot;
}

void assert_no_theme_ghosts(string label, string dot) {
    foreach (var ghost in new string[] { "StartColor", "HeaderBackgroundColor", "BackgroundColor" }) {
        if (dot.contains(ghost)) {
            stderr.printf("[%s] theme property '%s' became a diagram element:\n%s\n", label, ghost, dot);
            assert_not_reached();
        }
    }
}

const string THEME_BLOCKS = """skinparam state {
    StartColor #2F4F2F
}
skinparam class {
    HeaderBackgroundColor #2F4F4F
}
skinparam note {
    BackgroundColor #2F4F4F
}
""";

void test_theme_blocks_create_no_elements() {
    // Keyword element names ("state", "class", "note") were rejected by the
    // class, use-case, deployment and object parsers, and the block body was
    // parsed as elements named after its properties.
    assert_no_theme_ghosts("class", engine_dot("@startuml\n" + THEME_BLOCKS + "class A\n@enduml"));
    assert_no_theme_ghosts("usecase", engine_dot("@startuml\n" + THEME_BLOCKS + "actor User\nusecase (Login)\nUser --> (Login)\n@enduml"));
    assert_no_theme_ghosts("object", engine_dot("@startuml\n" + THEME_BLOCKS + "object Foo\nobject Bar\nFoo --> Bar\n@enduml"));
    assert_no_theme_ghosts("deployment", engine_dot("@startuml\n" + THEME_BLOCKS + "device Server\nartifact App\nServer --> App\n@enduml"));
}

void test_class_trailing_static_keeps_members() {
    // "+ one() {static}": the modifier's "}" ended the class body, dropping
    // every later member and the next class.
    string dot = engine_dot("""@startuml
class A {
    + one() {static}
    + two()
}
class B
@enduml""");
    if (!dot.contains("two()") || !dot.contains("B [label")) {
        stderr.printf("[class_static] members after {static} lost:\n%s\n", dot);
        assert_not_reached();
    }
    assert(!dot.contains("\\{"));
}

void test_class_note_of_attaches() {
    // "of" lexes as the OF keyword; the note kept "of A" as text, unattached.
    string dot = engine_dot("""@startuml
class A
class B
note right of A
  attached right
end note
note bottom of B
  attached bottom
end note
@enduml""");
    if (dot.contains("label=\"of ")) {
        stderr.printf("[class_note_of] 'of X' left in note text:\n%s\n", dot);
        assert_not_reached();
    }
    // two note nodes plus one edge each
    assert(dot.split("_class_note_").length - 1 >= 4);
}

void test_component_labels_storage_arrows() {
    string dot = engine_dot("""@startuml
package "P" {
    component [Title Line\nsecond line] as a
    storage "Store\nline two" as s
}
component [B] as b
a -.-> b : dotted label
a --> s : DEGRADED failsafe logged,\ngraceful stop via POST_PURGE
@enduml""");
    // bracket label shown, not the alias
    assert(dot.contains("a [label=\"Title Line"));
    // storage without braces is a leaf node, not an empty cluster
    if (!dot.contains("s [label=\"Store") || dot.contains("label=\"s\"")) {
        stderr.printf("[component_storage] storage rendered as a cluster:\n%s\n", dot);
        assert_not_reached();
    }
    // "-.->" keeps its target and label
    if (dot.contains("-> _") || !dot.contains("dotted label")) {
        stderr.printf("[component_dotted] -.-> lost its target:\n%s\n", dot);
        assert_not_reached();
    }
    // keyword "stop" still separated by spaces
    if (!dot.contains("graceful stop via")) {
        stderr.printf("[component_label_spacing] words merged:\n%s\n", dot);
        assert_not_reached();
    }
}

void test_sequence_theme_and_notes() {
    string dot = engine_dot("""@startuml
skinparam backgroundColor #1e1e1e
skinparam note {
    BackgroundColor #2F4F4F
    FontColor #ffffff
}
skinparam sequence {
    ParticipantBackgroundColor #36648B
}
participant "Alpha" as A
participant "Beta" as B
A -> B : hello
note right of A
  right note
end note
note over A, B
  spanning note
end note
@enduml""");
    assert(dot.contains("bgcolor=\"#1e1e1e\""));
    assert(dot.contains("fillcolor=\"#36648B\""));
    assert(dot.contains("shape=note, style=filled, fillcolor=\"#2F4F4F\""));
    // message text was hard-coded black on any background
    if (dot.contains("color=black") || !dot.contains("fontsize=11, color=")) {
        stderr.printf("[sequence_labels] message colours not themed:\n%s\n", dot);
        assert_not_reached();
    }
    // "note over A, B" must not leak ", B" into the text
    assert(!dot.contains(", B"));
    // notes sit at a fixed position without connector edges, and nothing links to a
    // bare participant id (ghost node)
    if (dot.contains("-> A [") || dot.contains("-> B [") || dot.contains("note0 ->") ||
        dot.contains("-> note0") || !line_with(dot, "note0 [").contains("pos=")) {
        stderr.printf("[sequence_notes] note not placed on its row:\n%s\n", dot);
        assert_not_reached();
    }
}

// y of a node's fixed position in the layout (downwards; the DOT has it negated)
double seq_pos_y(string dot, string id) {
    string l = line_with(dot, "  %s [".printf(id));
    int at = l.index_of("pos=\"");
    assert(at >= 0);
    string[] xy = l.substring(at + 5).split("!")[0].split(",");
    return -double.parse(xy[1]);
}

void test_sequence_rows_follow_source_order() {
    // Rows were ordered only within each participant's lifeline chain, so a
    // message between other participants could render above an earlier one.
    // Every message and note row lies below the one before it.
    string dot = engine_dot("""@startuml
participant A
participant B
participant C
A -> B : first
note right of B
  after first
end note
B -> C : second
A -> C : third
@enduml""");
    string[] rows = { "A_top", "A_m0", "note0", "B_m1", "A_m2", "A_bottom" };
    for (int i = 1; i < rows.length; i++) {
        if (!(seq_pos_y(dot, rows[i]) > seq_pos_y(dot, rows[i - 1]))) {
            stderr.printf("[sequence_order] '%s' is not below '%s':\n%s\n", rows[i], rows[i - 1], dot);
            assert_not_reached();
        }
    }
}

// =====================================================================

// ---- 2026-09-14 round 3 ----

int count_substr(string hay, string needle) {
    int n = 0;
    int pos = 0;
    while ((pos = hay.index_of(needle, pos)) >= 0) {
        n++;
        pos += needle.length;
    }
    return n;
}

// Labels are rebuilt from tokens. Joining every token with a space changed the
// text: ">=" became "> =", "°C" became "° C", "Result<void>" became
// "Result < void >". Spaces now come from the source.
void test_labels_keep_source_spacing() {
    string state = engine_dot("@startuml\n[*] --> Idle\nIdle --> Busy : tank >= 5°C\nIdle : Entry: wait (t<2)\nnote right of Busy\n  limit: 90°C\n  pump >= 1\nend note\n@enduml");
    assert(state.contains("Idle -> Busy [label=\"tank >= 5°C\""));
    assert(state.contains("Entry: wait (t<2)"));
    assert(state.contains("label=\"limit: 90°C\\npump >= 1\""));
    string cls = engine_dot("@startuml\nclass Ctl {\n  + init(): Result<void>\n  - load(a, b): int\n}\n@enduml");
    assert(cls.contains("+ init(): Result&lt;void&gt;<BR ALIGN=\"LEFT\"/>- load(a, b): int<BR ALIGN=\"LEFT\"/>"));
    string comp = engine_dot("@startuml\ncomponent [Heater] as H\nH --> [Pump] : temp >= 60°C\nnote left of H : single >= 1°C\n@enduml");
    assert(comp.contains("label=\"temp >= 60°C\""));
    assert(comp.contains("label=\"single >= 1°C\""));
    string seq = engine_dot("@startuml\nA -> B : go >= 1°C\n@enduml");
    assert(seq.contains("label=\"  go >= 1°C  \""));
}

// Multi-line component notes got a blank line between lines (the NEWLINE
// token's "\n" lexeme was appended as well as a real newline), and an inline
// "#color" after the note position was ignored.
void test_component_note_lines_and_color() {
    string dot = engine_dot("@startuml\ncomponent [Heater] as H\nnote right of H #LightYellow\n  first line\n  second line\nend note\n@enduml");
    assert(dot.contains("label=\"first line\\nsecond line\""));
    assert(dot.contains("fillcolor=\"LightYellow\", fontcolor=\"#000000\""));
}

// Activity actions and notes and mindmap nodes had their own spacing guesses
// with the same defect: "> =", "° C", "Result < void >".
void test_activity_mindmap_keep_source_spacing() {
    string act = engine_dot("@startuml\nstart\n:tank >= 5°C (Result<void>);\nnote right: limit 90°C\nstop\n@enduml");
    // Action text sits in an HTML table cell, so ">" and "<" arrive escaped
    assert(act.contains("tank &gt;= 5°C (Result&lt;void&gt;)"));
    assert(act.contains("limit 90°C"));
    string mind = engine_dot("@startmindmap\n* Root >= 1°C\n** child Result<void>\n@endmindmap");
    assert(mind.contains("Root >= 1°C"));
}

// A class first mentioned by a relationship inside a package belongs to that
// package; only declarations used to count, so the boxes came out empty.
void test_class_package_relationship_members() {
    string dot = engine_dot("""@startuml
package "Classic Collections" {
  Object <|-- ArrayList
}
Object <|-- Demo1
@enduml""");
    int pkg = dot.index_of("subgraph cluster_pkg0 {");
    int end = dot.index_of("\n  }\n", pkg);
    int arr = dot.index_of("ArrayList [label=");
    int demo = dot.index_of("Demo1 [label=");
    assert(pkg >= 0 && end > pkg);
    assert(arr > pkg && arr < end);
    assert(demo >= 0 && (demo < pkg || demo > end));
}

// ---- 2026-09-14 round 4: older bugs ----

// Plain action text went into an HTML table cell escaped only for a DOT string,
// so ":a < b;" made the whole graph a syntax error and the export failed.
void test_activity_action_text_is_html_escaped() {
    string dot = engine_dot("@startuml\nstart\n:a < b and c > d;\nstop\n@enduml");
    assert(dot.contains("<td>a &lt; b and c &gt; d</td>"));
}

// Single-dash/single-dot class arrows were lost in the lexer ("*-" swallowed its
// dash, "<|-" returned a bare "<", "-|>" ".|>" ".>" had no token).
void test_class_single_dash_arrows() {
    string dot = engine_dot("@startuml\nclass A\nA -|> D\nE <|- A\nA .|> K\nA .> H\nA *- B\nA o- C\n@enduml");
    assert(dot.contains("A -> D [style=solid, arrowhead=empty"));
    assert(dot.contains("E -> A [style=solid, arrowhead=none, arrowtail=empty"));  // written order kept
    assert(dot.contains("A -> K [style=dashed, arrowhead=empty"));
    assert(dot.contains("A -> H [style=dashed, arrowhead=open"));
    assert(dot.contains("A -> B [style=solid, arrowhead=none, arrowtail=diamond"));
    assert(dot.contains("A -> C [style=solid, arrowhead=none, arrowtail=odiamond"));
    assert(dot.contains("{ rank=same; A; D; }"));
}

// The composition/aggregation marker belongs to the "whole" end: "A *-- J" puts
// the diamond at A (stock PlantUML agrees). The reverse test was inverted.
void test_class_composition_marker_side() {
    string dot = engine_dot("@startuml\nclass A\nA *-- J\nA --o E\n@enduml");
    assert(dot.contains("A -> J [style=solid, arrowhead=none, arrowtail=diamond"));
    assert(dot.contains("A -> E [style=solid, arrowhead=odiamond, arrowtail=none"));  // written order kept
}

// "A - B" and "A . B" were not recognised as links at all.
void test_class_plain_single_links() {
    string dot = engine_dot("@startuml\nclass A\nA - F\nA . G\n@enduml");
    assert(dot.contains("A -> F [style=solid, arrowhead=open, arrowtail=none, dir=none]"));
    assert(dot.contains("A -> G [style=dashed, arrowhead=open, arrowtail=none, dir=none]"));
}

// A relationship between packages took "foo1" (the name split at its dot) as a
// class and drew a stray box; it now runs between the package clusters.
void test_class_package_to_package_link() {
    string dot = engine_dot("@startuml\npackage foo1.foo2 { }\npackage foo1.foo2.foo3 {\n   class Object\n}\nfoo1.foo2 +-- foo1.foo2.foo3\n@enduml");
    assert(!dot.contains("foo1 [label="));
    // foo1 > foo2 > foo3 nest; the link runs from foo2 to foo3, which sits inside it
    assert(dot.contains("_pkg1_anchor -> _pkg2_anchor ["));
    assert(dot.contains("lhead=cluster_pkg2, class=\"gdplus\""));
    assert(!dot.contains("ltail=cluster_pkg1"));
}

// "left to right direction" was skipped in class diagrams.
void test_class_left_to_right_direction() {
    string dot = engine_dot("@startuml\nleft to right direction\nclass A\nclass B\nA --> B\n@enduml");
    assert(dot.contains("rankdir=LR;"));
    assert(dot.contains("A [label=<<TABLE"));
}

// Component edges to a container ended at an invisible point beside the box.
void test_component_container_edges_clip_at_border() {
    string dot = engine_dot("""@startuml
rectangle "Outer" <<system_boundary>> as outer {
  rectangle "Inner" <<component>> as inner
}
[Client] as client
client --> outer : uses
inner --> client
@enduml""");
    assert(dot.contains("    outer_anchor [label=\"\""));
    assert(dot.contains("client -> outer_anchor [style=solid, arrowhead=vee, label=\"uses\", lhead=cluster_0]"));
    assert(dot.contains("inner -> client [style=solid, arrowhead=vee];"));
}

// Deployment-style connections to a container had the same problem (drawn by the
// component renderer since "device" files stopped being a separate type).
void test_deployment_container_edges_clip_at_border() {
    string dot = engine_dot("""@startuml
node "Server" as srv {
  artifact app
}
device Phone
Phone --> srv : https
app --> Phone
@enduml""");
    assert(dot.contains("    srv_anchor [label=\"\""));
    assert(dot.contains("Phone -> srv_anchor [style=solid, arrowhead=vee, label=\"https\", lhead=cluster_0]"));
    assert(dot.contains("app -> Phone [style=solid, arrowhead=vee];"));
}

// Quoted cardinalities around an arrow were taken as class names:
// 'diamond - "from 0..*" Station' drew a ghost class "from 0..*".
void test_class_link_cardinality_is_not_a_class() {
    string dot = engine_dot("@startuml\nclass Station\n<> diamond\ndiamond - \"from 0..*\" Station\nCustomer \"1\" *-- \"many\" Order\n@enduml");
    assert(dot.contains("diamond -> Station ["));
    assert(!dot.contains("from_0"));
    assert(dot.contains("headlabel=\"from 0..*\""));
    assert(dot.contains("Customer -> Order [") && dot.contains("taillabel=\"1\"") && dot.contains("headlabel=\"many\""));
}

// A dash followed directly by more arrow ("-ri(0)->") is not a plain "A - B"
// link; the next word used to become a ghost target class.
void test_class_dash_word_arrow_makes_no_ghost() {
    string dot = engine_dot("@startuml\nclass ac1\nac1 -ri(0)-> right1\nac1 - plain\n@enduml");
    assert(!dot.contains("ri [label="));
    assert(dot.contains("ac1 -> plain ["));
}

// ---- 2026-09-14 round 5: new finds ----

// "-->" in a class diagram is a solid association (stock PlantUML), not dashed.
void test_class_double_dash_arrow_is_solid() {
    string dot = engine_dot("@startuml\nclass A\nA --> B\nC <-- A\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=open"));
    assert(dot.contains("C -> A [style=solid, arrowhead=none, arrowtail=open"));  // "C <-- A", written order kept
}

// Direction words and bracket options inside arrows were dropped with the line.
void test_class_direction_and_option_arrows() {
    string dot = engine_dot("@startuml\nclass A\nA -up-> B\nA -left-|> C\nA -[hidden]- D\nA -[#red]-> E\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=open, arrowtail=none, dir=both, constraint=false]"));
    assert(dot.contains("B -> A [style=invis];"));
    assert(dot.contains("A -> C [style=solid, arrowhead=empty"));
    assert(dot.contains("{ rank=same; A; C; }"));
    assert(dot.contains("A -> D [style=invis"));
    assert(dot.contains("A -> E [style=solid, arrowhead=open, arrowtail=none, dir=both, color=\"red\"]"));
}

// "<> name" drew a class box named "<" next to the intended diamond.
void test_class_association_diamond() {
    string dot = engine_dot("@startuml\nclass A\n<> dia\ndia - A\n@enduml");
    assert(dot.contains("dia [label=\"\", shape=diamond"));
    assert(dot.contains("dia -> A ["));
}

// "device" (not PlantUML syntax) was a separate deployment diagram type; it is a node
// in a component diagram: box3d, linked, and a container only with a body.
void test_deployment_device_keyword() {
    string src = "@startuml\ndevice Phone\nnode Server\nPhone --> Server\n@enduml";
    assert(TypeDetector.detect_plantuml(src) == DiagramType.COMPONENT);
    string dot = engine_dot(src);
    assert(dot.has_prefix("digraph component"));
    assert(!dot.contains("device [label="));
    assert(dot.contains("Phone [label=\"Phone\"") && dot.contains("Server [label=\"Server\""));
    assert(line_with(dot, "Phone [label=").contains("shape=box3d"));
    assert(line_with(dot, "Server [label=").contains("shape=box3d"));
    assert(dot.contains("Phone -> Server ["));

    // "as" alias (quoted side is the label) and a body making a container
    string nested = engine_dot("@startuml\ndevice \"Edge Box\" as edge {\n  device Sensor as s1\n}\nnode Hub\ns1 --> Hub\n@enduml");
    assert(nested.contains("subgraph cluster_0 {\n    label=<<B>Edge Box</B>>;"));
    assert(line_with(nested, "s1 [label=\"Sensor\"").contains("shape=box3d"));
    assert(nested.contains("s1 -> Hub ["));
}

// "--++" activation shorthand looked like the class arrow "--+"; use case files
// with "(Start) <|-- (Use)" were claimed by the class-arrow check.
void test_detect_sequence_and_usecase_shorthand() {
    var engine = new DiagramEngine("dot");
    assert(engine.detect_plantuml_type("@startuml\nalice -> bob ++ : hello\nbob -> charlie --++ : hello2\n@enduml") == DiagramType.SEQUENCE);
    assert(engine.detect_plantuml_type("@startuml\n:Main Admin: as Admin\n(Use the application) as (Use)\nUser <|-- Admin\n(Start) <|-- (Use)\n@enduml") == DiagramType.USECASE);
    assert(engine.detect_plantuml_type("@startuml\nclass A\nA --+ B\n@enduml") == DiagramType.CLASS);
}

// A note body line starting with "(" is prose, not a use case: a component
// diagram with "(default 5 min)" in a note was detected as a use case diagram.
void test_detect_component_with_parenthesised_note_line() {
    var engine = new DiagramEngine("dot");
    string src = "@startuml\ncomponent [Heater] as H\n[Pump] --> H\nnote right of H\n  Recovery:\n  (default 5 min)\nend note\n@enduml";
    assert(engine.detect_plantuml_type(src) == DiagramType.COMPONENT);
}

// ---- 2026-09-14 round 6: namespaces ----

// "class net.dummy.Person" is class Person in a "net.dummy" box (stock PlantUML);
// it used to be a loose "net.dummy.Person" box plus a ghost class "net".
void test_class_qualified_name_goes_into_namespace() {
    string dot = engine_dot("@startuml\nclass net.dummy.Person\nclass net.other.Thing\nnet.dummy.Person --> net.other.Thing\n@enduml");
    assert(class_box(dot, "net_dummy_Person", "Person"));
    // Nested as PlantUML 1.2026 draws dotted names: net > dummy, net > other
    assert(count_substr(dot, "label=\"net\";") == 1);
    assert(dot.contains("label=\"dummy\";"));
    assert(dot.contains("label=\"other\";"));
    assert(!dot.contains("net [label="));
    assert(dot.contains("net_dummy_Person -> net_other_Thing ["));
}

// Inside a namespace a new bare name belongs to it and ".X" is global. A bare name that
// already exists elsewhere is that class: PlantUML 1.2026.1 draws "Person" in net.foo as
// the existing net.dummy.Person (a self-link), so there are two Persons, not three.
const string NAMESPACE_SOURCE = """@startuml
class BaseClass
namespace net.dummy {
    .BaseClass <|-- Person
    Meeting o-- Person
}
namespace net.foo {
  net.dummy.Person <|- Person
  .BaseClass <|-- Person
}
BaseClass <|-- net.unused.Person
@enduml""";

void test_class_namespace_name_resolution() {
    string dot = engine_dot(NAMESPACE_SOURCE);
    assert(count_substr(dot, "&#160; Person</TD>") == 2);
    assert(count_substr(dot, "BaseClass [label=") == 1);
    assert(dot.contains("net_dummy_Person -> net_dummy_Person [style=solid, arrowhead=none, arrowtail=empty"));
    assert(!dot.contains("[label=\"{.}\"]") && !dot.contains("&#160; .</TD>"));
}

// A class declared with indentation inside a package block was not seen by type
// detection, and the file rendered as a component diagram.
void test_detect_indented_class_declaration() {
    var engine = new DiagramEngine("dot");
    assert(engine.detect_plantuml_type("@startuml\npackage p.q {\n  class Z\n}\n@enduml") == DiagramType.CLASS);
}

// ---- 2026-09-14 round 6: description diagrams ----

// Components, interfaces and actors with class-looking arrows ("#-->>") and an
// "interface" line were detected as a class diagram.
void test_detect_description_diagram_as_component() {
    var engine = new DiagramEngine("dot");
    assert(engine.detect_plantuml_type("@startuml\nactor foo1\ncomponent comp1\ninterface interf1\ncomp1 #~~( interf1\n[aze1] #-->> [aze2]\n@enduml") == DiagramType.COMPONENT);
}

// Sequence actors were octagons; PlantUML draws stick figures with the name below
void test_sequence_actor_stick_figure() {
    string dot = engine_dot("@startuml\nactor Alice\nactor Bob\nAlice -> Bob : hello\n@enduml");
    assert(line_with(dot, "Alice_top [").contains("class=\"gdactor"));
    assert(line_with(dot, "Bob_bottom [").contains("class=\"gdactor"));
    assert(!dot.contains("octagon"));
}

// "hide footbox" was ignored: participant boxes were drawn at the bottom too
void test_sequence_hide_footbox() {
    string dot = engine_dot("@startuml\nactor Alice\nparticipant Bob\nAlice -> Bob : hello\nhide footbox\n@enduml");
    assert(line_with(dot, "Alice_bottom [").contains("shape=point"));
    assert(line_with(dot, "Bob_bottom [").contains("shape=point"));
    assert(line_with(dot, "Bob_top [").contains("label="));
}

// "skinparam actorStyle awesome" / "hollow" draw a filled bust / an outlined figure
void test_sequence_actor_styles_svg() {
    var engine = new DiagramEngine("dot");
    foreach (string style in new string[] { "awesome", "hollow" }) {
        uint8[]? data = engine.generate_svg("@startuml\nskinparam actorStyle %s\nactor Alice\nactor Bob\nAlice -> Bob : hello\n@enduml".printf(style), "test.puml", null);
        assert(data != null);
        var text = new StringBuilder();
        text.append_len((string) data, data.length);
        assert(!text.str.contains("#010203"));
        assert(count_substr(text.str, "class=\"gdfigure gd%s\"".printf(style)) == 4);
    }
}

// Actor-only files with messages are sequence diagrams in PlantUML ("actor Alice" /
// "Alice -> Bob : hello"); every file with an "actor" line and no "participant" was a use case
// diagram, drawing actors and a link instead of lifelines
void test_detect_actor_messages_as_sequence() {
    var engine = new DiagramEngine("dot");
    assert(engine.detect_plantuml_type("@startuml\nactor Alice\nactor Bob\nAlice -> Bob : hello\nhide footbox\n@enduml") == DiagramType.SEQUENCE);
    assert(engine.detect_plantuml_type("@startuml\nskinparam actorStyle awesome\nactor A\nactor B\nA --> B\n@enduml") == DiagramType.SEQUENCE);
    assert(engine.detect_plantuml_type("@startuml\nactor A\nactor B\nA -> B : hi\n@enduml") == DiagramType.SEQUENCE);
}

// ...but a use case, a "(Name)" element, ":Name:" actors or a business "/" keep a use case diagram
void test_detect_actor_usecase_files_stay_usecase() {
    var engine = new DiagramEngine("dot");
    assert(engine.detect_plantuml_type("@startuml\nactor User\nusecase Login\nUser -> Login : does\n@enduml") == DiagramType.USECASE);
    assert(engine.detect_plantuml_type("@startuml\nactor A\nA --> (Login)\n@enduml") == DiagramType.USECASE);
    assert(engine.detect_plantuml_type("@startuml\n:First Actor:\nactor Woman3\n@enduml") == DiagramType.USECASE);
    assert(engine.detect_plantuml_type("@startuml\nactor A\nactor B\nrectangle Sys {\n  A -> B\n}\n@enduml") == DiagramType.USECASE);
}

// actor / "(Use case)" / ":Actor:" elements were skipped in component diagrams, an
// "() iface" line lost its link, and names used only in links drew as ellipses.
void test_component_actor_usecase_shorthand() {
    string dot = engine_dot("@startuml\nactor foo1\ncomponent comp1\n(ac1) -ri-> r1\n:ma: -- foo1\n() api - comp1\n@enduml");
    // actors (declared, ":ma:" and names only used in links next to actors) are stick figures
    assert(dot.contains("foo1 [shape=none, class=\"gdactor ") && dot.contains(">foo1<"));
    assert(dot.contains("ac1 [label=\"ac1\", shape=ellipse"));
    assert(dot.contains("ma [shape=none, class=\"gdactor ") && dot.contains(">ma<"));
    assert(dot.contains("r1 [shape=none, class=\"gdactor ") && dot.contains(">r1<"));
    assert(dot.contains("api:c -> comp1 ["));  // links attach to the interface circle
}

// Ball/socket decorations, "#" ends, "~" dotted lines and direction words were
// dropped with the whole link.
void test_component_decorated_arrows() {
    string dot = engine_dot("@startuml\ncomponent a\ncomponent b\ncomponent c\nb -(0)- c\na #~~( c\na -le-> b\n@enduml");
    assert(dot.contains("_link_ball0 [label=\"\", shape=circle"));
    assert(dot.contains("b -> _link_ball0 [style=solid, arrowtail=none, arrowhead=icurve, dir=both]"));
    assert(dot.contains("_link_ball0 -> c [style=solid, arrowtail=icurve, arrowhead=none, dir=both]"));
    assert(dot.contains("a -> c [style=dotted, arrowtail=obox, arrowhead=icurve, dir=both]"));
    assert(dot.contains("b -> a [style=solid, arrowtail=vee, arrowhead=none, dir=both]"));
    assert(dot.contains("{ rank=same; b; a; }"));
}

// Element keywords used as names ("actor actor") came back empty and merged into
// one "_empty" node; person/hexagon/label/... and "actor/" were not understood.
void test_component_element_keywords_as_names() {
    string dot = engine_dot("@startuml\nactor actor\ncomponent component\nhexagon hexagon\nlabel label\nperson person\nactor/ \"Business\"\n@enduml");
    assert(dot.contains("actor [shape=none, class=\"gdactor ") && dot.contains(">actor<"));
    assert(dot.contains("component [label=\"component\", shape=box"));
    assert(dot.contains("hexagon [label=\"hexagon\", shape=hexagon"));
    assert(dot.contains("label [label=\"label\", shape=plaintext"));
    assert(dot.contains("person [shape=plaintext") && dot.contains(">person</FONT>"));
    assert(dot.contains(" gdbusiness\"") && dot.contains(">Business<"));
    assert(!dot.contains("_empty ["));
}

// An element named after a DOT keyword ("node", "edge") was written as a bare ID,
// which Graphviz reads as a default-attribute statement: the element vanished.
void test_dot_keyword_names_get_safe_ids() {
    string dot = engine_dot("@startuml\ncomponent node\ncomponent edge\n[node] --> [edge]\n@enduml");
    assert(dot.contains("node_ [label=\"node\""));
    assert(dot.contains("node_ -> edge_ ["));
}

// "-->" is solid in stock PlantUML component diagrams; it was drawn dashed.
// "..>" stays dashed.
void test_component_double_dash_arrow_is_solid() {
    string dot = engine_dot("@startuml\ncomponent a\ncomponent b\ncomponent c\n[a] --> [b]\n[a] ..> [c]\n@enduml");
    assert(dot.contains("a -> b [style=solid, arrowhead=vee"));
    assert(dot.contains("a -> c [style=dashed, arrowhead=vee"));
}

// Same for deployment diagrams, where "..>" used to be dropped entirely.
void test_deployment_double_dash_arrow_is_solid() {
    string dot = engine_dot("@startuml\nnode n1\nnode n2\ndevice d\nn1 --> n2\nn1 ..> d\n@enduml");
    assert(dot.contains("n1 -> n2 [style=solid, arrowhead=vee"));
    assert(dot.contains("n1 -> d [style=dashed, arrowhead=vee"));
}

// ---- 2026-09-14 round 7 ----

// "-->" is a solid arrow in state diagrams (stock PlantUML); it was dashed.
void test_state_double_dash_arrow_is_solid() {
    string dot = engine_dot("@startuml\nstate A\nstate B\nA --> B\n@enduml");
    assert(dot.contains("A -> B [style=solid]"));
}

// Same in use case diagrams; "..>" stays dashed.
void test_usecase_double_dash_arrow_is_solid() {
    string dot = engine_dot("@startuml\nactor User\nusecase (Login)\nusecase (Logout)\nUser --> (Login)\nUser ..> (Logout)\n@enduml");
    assert(dot.contains("User -> Login [style=solid"));
    assert(dot.contains("User -> Logout [style=dashed"));
}

// Composite state descriptions were written raw into a "// Description:" DOT
// comment; the second line became bare node statements (ghost nodes "then", "retries").
void test_state_composite_multiline_description() {
    string dot = engine_dot("@startuml\nstate Outer {\n  [*] --> A\n}\nOuter : waits (for input)\nOuter : then \"retries\" [x]; a=b\n[*] --> Outer\n@enduml");
    assert(!dot.contains("// Description"));
    assert(count_substr(dot, "\nthen") == 0);
    assert(dot.contains("<TD>Outer</TD></TR><HR/><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">waits (for input)<BR ALIGN=\"LEFT\"/>then"));
}

// A state declared as a composite inside another composite ("state Parent { state
// Busy { ... } }") after "[*] --> Busy" left a ghost simple box "Busy" beside the cluster.
void test_state_nested_composite_reuses_existing_state() {
    string dot = engine_dot("@startuml\n[*] --> Busy\nstate Parent {\n  [*] --> Busy\n  state Busy {\n    [*] --> Work\n  }\n}\n@enduml");
    assert(!dot.contains("Busy [label="));
    assert(count_substr(dot, "label=\"Busy\"") == 1);
    // both links enter the one Busy cluster (at its first node, clipped at the border)
    assert(count_substr(dot, "[style=solid, lhead=cluster_1, minlen=2]") == 2);
}

// A DOT keyword as map alias ("as edge") emitted "edge [shape=plaintext" / "edge:r0 ->":
// invalid DOT, the whole render failed.
void test_object_keyword_map_alias_id() {
    string dot = engine_dot("@startuml\nobject Other\nmap \"Cfg\" as edge {\n k => v\n}\nedge::k --> Other\n@enduml");
    assert(dot.contains("  edge_ [shape=plaintext"));
    assert(dot.contains("edge_:r0 -> Other [style=solid"));
}

// "object \"Foo Bar\" as node" lost its alias ("node" lexes as a keyword), so
// "node --> Other" did not link to it.
void test_object_keyword_word_alias() {
    string dot = engine_dot("@startuml\nobject \"Foo Bar\" as node\nobject Other\nnode --> Other\n@enduml");
    assert(dot.contains("node_ [label=\"{Foo Bar}\""));
    assert(dot.contains("node_ -> Other [style=solid"));
}

// A quoted dotted name ("a.b") was nested into a package "a"; only unquoted names nest.
void test_object_quoted_dotted_name_not_packaged() {
    string dot = engine_dot("@startuml\nobject \"a.b\" as ab\nobject Bob\n@enduml");
    assert(!dot.contains("cluster_opkg"));
    assert(dot.contains("  ab [label=\"{a.b}\""));
}

// "task.1" and "task_1" both got DOT id task_1 and merged into one node.
void test_object_colliding_ids_unique() {
    string dot = engine_dot("@startuml\nobject task.1\nobject task_1\n@enduml");
    assert(dot.contains("task_1 [label=\"{task.1}\""));
    assert(dot.contains("task_1_2 [label=\"{task_1}\""));
}

// "<-->" drew a single head (arrowtail=none); PlantUML draws both.
void test_object_bidirectional_arrow() {
    string dot = engine_dot("@startuml\nobject Bob\nobject London\nBob <--> London\n@enduml");
    assert(dot.contains("Bob -> London [style=solid, arrowhead=vee, arrowtail=vee, dir=both]"));
}

// "-[#red]->", "-[dashed]->", "-[hidden]-" were dropped at the "[".
void test_object_arrow_bracket_options() {
    string dot = engine_dot("@startuml\nobject A\nobject B\nobject C\nobject D\nA -[#red]-> B\nA -[dashed]-> C\nA -[hidden]- D\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=vee, arrowtail=none, dir=both, color=\"red\"]"));
    assert(dot.contains("A -> C [style=dashed, arrowhead=vee"));
    assert(dot.contains("A -> D [style=invis"));
}

// "*[#red] root" was read as a "[text]" box: empty label and fillcolor="#red"
// (a named colour with '#', which Graphviz rejects).
void test_mindmap_bracket_color() {
    string dot = engine_dot("@startmindmap\n*[#red] root\n**[#lightblue] child\n**[#FF0000] hex\n@endmindmap");
    assert(dot.contains("[label=\"root\", shape=box, style=\"filled\", fillcolor=\"red\""));
    assert(dot.contains("[label=\"child\", shape=box, style=\"filled\", fillcolor=\"lightblue\""));
    assert(dot.contains("[label=\"hex\", shape=box, style=\"filled\", fillcolor=\"#FF0000\""));
    assert(!dot.contains("label=\"\""));
}

// Object links: "-->" solid, "..>" dashed (it was dropped), "*--" diamond at
// the whole (it was on the part).
// "participant Bob <<foo>>" dropped the stereotype; PlantUML draws «foo» above the
// name in the head and foot boxes, for every participant kind.
void test_seq_participant_stereotype_label() {
    string dot = engine_dot("@startuml\nparticipant Bob <<foo>>\nactor Al <<hero>>\nBob -> Al : hi\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("label=<<I>«foo»</I><BR/>Bob>"));
    assert(line_with(dot, "Bob_bottom [").contains("label=<<I>«foo»</I><BR/>Bob>"));
    // Actors are stick figures: the stereotype is the row above the figure, the name below it
    string al = line_with(dot, "Al_top [");
    assert(al.contains("class=\"gdactor") && al.contains("<I>«hero»</I>") && al.contains(">Al<"));
    assert(al.index_of("«hero»") < al.index_of(">Al<"));
}

void test_seq_participant_stereotype_multiword() {
    string dot = engine_dot("@startuml\nparticipant A\ndatabase DB << multi word >>\nA -> DB : x\n@enduml");
    assert(line_with(dot, "DB_top [").contains("label=<<I>«multi word»</I><BR/>DB>"));
}

// A stereotype the lexer cannot take as one token ("<<a > b>>") comes as "<", "<",
// words, ">", ">"; PlantUML shows «a > b».
void test_seq_participant_stereotype_split_tokens() {
    string dot = engine_dot("@startuml\nparticipant Bob <<a > b>>\nparticipant Tom\nBob -> Tom : hi\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("label=<<I>«a &gt; b»</I><BR/>Bob>"));
}

// The spot of "<<(C,#ADD1B2) Testable>>" is a placeholder cell before the text (the circle
// and letter are drawn over it in the SVG); the text keeps «Testable» above the name.
void test_seq_participant_spot_stereotype() {
    string dot = engine_dot("@startuml\nparticipant A\nparticipant \"Long\" as L <<(C,#ADD1B2) Testable>>\nA -> L : y\n@enduml");
    string top = line_with(dot, "L_top [");
    assert(top.contains("BGCOLOR=\"#01F2"));
    assert(top.contains("<TD><I>«Testable»</I><BR/>Long</TD>"));
}

// skinparam participant { BackgroundColor<<foo>> ... } colours only stereotyped
// participants of that kind (not an actor <<foo>>), and an inline colour wins.
void test_seq_participant_stereotype_skinparam_colors() {
    string dot = engine_dot("@startuml\nskinparam participant {\n  BackgroundColor<<foo>> red\n  BorderColor<<foo>> blue\n  FontColor<<foo>> white\n}\nparticipant Bob <<foo>>\nparticipant Tom\nactor Al <<foo>>\nparticipant Dan <<foo>> #lightgreen\nBob -> Tom : hi\nTom -> Al : x\nAl -> Dan : y\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("fillcolor=\"red\", color=\"blue\", fontcolor=\"white\""));
    assert(!line_with(dot, "Tom_top [").contains("fillcolor=\"red\""));
    assert(!line_with(dot, "Al_top [").contains("fillcolor=\"red\""));
    assert(line_with(dot, "Dan_top [").contains("fillcolor=\"lightgreen\""));
}

// "skinparam participantBackgroundColor<<bar>> yellow" used to store "bar yellow" globally.
void test_seq_participant_stereotype_global_skinparam() {
    string dot = engine_dot("@startuml\nskinparam participantBackgroundColor<<bar>> yellow\nparticipant Tom <<bar>>\nparticipant Ann\nTom -> Ann : x\n@enduml");
    assert(line_with(dot, "Tom_top [").contains("fillcolor=\"yellow\""));
    assert(!line_with(dot, "Ann_top [").contains("fillcolor=\"yellow\""));
}

// PlantUML 1.2026.1 does not colour a participant from a "participant.foo" style.
void test_seq_participant_style_element_selector_ignored() {
    string dot = engine_dot("@startuml\n<style>\nparticipant.foo {\n  BackgroundColor red\n}\n</style>\nparticipant Bob <<foo>>\nparticipant Tom\nBob -> Tom : hi\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("<I>«foo»</I>"));
    assert(!line_with(dot, "Bob_top [").contains("fillcolor=\"red\""));
}

// ... but it does from a bare ".foo" style selector.
void test_seq_participant_style_bare_selector_applied() {
    string dot = engine_dot("@startuml\n<style>\n.foo {\n  BackgroundColor red\n}\n</style>\nparticipant Bob <<foo>>\nparticipant Tom\nBob -> Tom : hi\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("fillcolor=\"red\""));
}

// The lexer strips a STRING token's quotes; PlantUML keeps them in state descriptions
// (simple states and the composite header).
void test_state_description_keeps_quotes() {
    string dot = engine_dot("@startuml\nstate Simple : then \"retries\"\nstate Outer {\n  state Inner\n}\nOuter : then \"retries\"\n[*] --> Simple\nSimple --> Outer\n@enduml");
    assert(line_with(dot, "Simple [label=").contains("label=\"Simple\\nthen \\\"retries\\\"\""));
    assert(line_with(dot, "label=<<TABLE").contains(">then &quot;retries&quot;<"));
}

void test_state_transition_label_keeps_quotes() {
    string dot = engine_dot("@startuml\nstate A\n[*] --> A : \"go\"\nA --> B : say \"hi\" now\n@enduml");
    assert(dot.contains("[label=\"\\\"go\\\"\""));
    assert(dot.contains("[label=\"say \\\"hi\\\" now\""));
}

void test_state_note_keeps_quotes() {
    string dot = engine_dot("@startuml\nstate A\nnote right of A : note \"quoted\"\nnote left of A\n  multi \"line\" note\nend note\n@enduml");
    assert(line_with(dot, "shape=note").contains("label=\"note \\\"quoted\\\"\""));
    assert(dot.contains("label=\"multi \\\"line\\\" note\""));
}

// "skinparam guillemet false": PlantUML shows <<foo>> instead of «foo».
void test_seq_participant_stereotype_no_guillemet() {
    string dot = engine_dot("@startuml\nskinparam guillemet false\nparticipant Bob <<foo>>\nparticipant Tom\nBob -> Tom : hi\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("label=<&lt;&lt;<I>foo</I>&gt;&gt;<BR/>Bob>"));
}

// "skinparam stereotypePosition bottom" puts the stereotype under the name.
void test_seq_participant_stereotype_position_bottom() {
    string dot = engine_dot("@startuml\nskinparam stereotypePosition bottom\nparticipant Bob <<foo>>\nparticipant Tom\nBob -> Tom : hi\n@enduml");
    assert(line_with(dot, "Bob_top [").contains("label=<Bob<BR/><I>«foo»</I>>"));
}

// A floating note 'note "text" as N1' shows its text without quotes, as PlantUML does.
void test_state_floating_note_without_quotes() {
    string dot = engine_dot("@startuml\nstate foo\nnote \"This is a floating note\" as N1\nstate bar\n@enduml");
    assert(line_with(dot, "shape=note").contains("label=\"This is a floating note\""));
}

void test_object_link_arrows() {
    string dot = engine_dot("@startuml\nobject a\nobject b\nobject c\nobject d\na --> b\na ..> c\na *-- d\n@enduml");
    assert(dot.contains("a -> b [style=solid, arrowhead=vee, arrowtail=none, dir=both]"));
    assert(dot.contains("a -> c [style=dashed, arrowhead=vee, arrowtail=none, dir=both]"));
    assert(dot.contains("a -> d [style=solid, arrowhead=none, arrowtail=diamond, dir=both]"));
}

// Maps were not understood: "map" and each key became separate boxes.
void test_object_maps_and_row_links() {
    string dot = engine_dot("""@startuml
object London
object NewYork
map CapitalCity {
  UK *-> London
  USA => Washington
}
NewYork --> CapitalCity::USA
@enduml""");
    assert(dot.contains("CapitalCity [shape=plaintext"));
    // A row holding a link spans the map (O3)
    assert(dot.contains("<TD PORT=\"r0\" COLSPAN=\"2\">UK</TD>"));
    assert(dot.contains("<TD PORT=\"r1\" ALIGN=\"LEFT\">USA</TD><TD ALIGN=\"LEFT\">Washington</TD>"));
    assert(dot.contains("CapitalCity:r0 -> London [style=solid, arrowhead=vee, arrowtail=none, dir=both]"));
    assert(dot.contains("NewYork -> CapitalCity:r1 [style=solid, arrowhead=vee, arrowtail=none, dir=both]"));
    assert(!dot.contains("UK [label="));
}

// Packages holding objects and maps, "pkg.obj" references and a row-to-package link.
void test_object_packages_and_maps() {
    string dot = engine_dot("""@startuml
package foo {
    object baz
}
package bar {
    map A {
        b *-> foo.baz
        c =>
    }
}
A::c --> foo
@enduml""");
    int foo = dot.index_of("subgraph cluster_opkg0 {");
    int bar = dot.index_of("subgraph cluster_opkg1 {");
    assert(foo >= 0 && bar > foo);
    assert(dot.index_of("baz [label=") > foo && dot.index_of("baz [label=") < bar);
    assert(dot.index_of("A [shape=plaintext") > bar);
    assert(dot.contains("A:r0 -> baz [style=solid, arrowhead=vee, arrowtail=none, dir=both]"));
    assert(dot.contains("A:r1 -> _opkg0_anchor [style=solid, arrowhead=vee, arrowtail=none, dir=both, lhead=cluster_opkg0]"));
    assert(!dot.contains("[label=\"{.}\""));
}

// Object diagrams with class-style arrows or packages were detected as class or
// component diagrams.
void test_detect_object_diagrams() {
    var engine = new DiagramEngine("dot");
    assert(engine.detect_plantuml_type("@startuml\nobject Object01\nobject Object02\nObject01 <|-- Object02\n@enduml") == DiagramType.OBJECT);
    assert(engine.detect_plantuml_type("@startuml\npackage foo {\n    object baz\n}\npackage bar {\n    map A {\n        c =>\n    }\n}\n@enduml") == DiagramType.OBJECT);
}

// Interfaces are small circles with the name outside, not a circle the size of the name.
void test_component_interface_small_circle() {
    string dot = engine_dot("@startuml\ncomponent [Svc]\ninterface \"HTTP API\" as HTTP\n[Svc] - HTTP\n@enduml");
    assert(dot.contains("HTTP [shape=plaintext"));
    assert(dot.contains(">HTTP API<"));
    assert(dot.contains("Svc -> HTTP:c ["));
}

// Dotted package names nest (PlantUML 1.2026): "package a.b" is b inside a, and
// "namespace a" reopens a.
void test_class_dotted_packages_nest() {
    string dot = engine_dot("@startuml\npackage a.b {\n  class X\n}\nnamespace a {\n  class Y\n}\n@enduml");
    int a = dot.index_of("label=\"a\";");
    int b = dot.index_of("label=\"b\";");
    assert(a >= 0 && b > a);
    assert(!dot.contains("label=\"a.b\";"));
    int y = dot.index_of("a_Y [label=");
    assert(y > a && y < b);
    assert(dot.index_of("X [label=") > b);
}

// Dotted object and map names sit in a package for their prefix, as in the PERT example.
void test_object_dotted_names_get_packages() {
    string dot = engine_dot("@startuml\nleft to right direction\nmap Kick.Off {\n}\nmap task.1 {\n    Start => End\n}\nKick.Off --> task.1 : Label 1\n@enduml");
    assert(dot.contains("label=\"Kick\";"));
    assert(dot.contains("label=\"task\";"));
    assert(dot.contains("rankdir=LR;"));
    assert(dot.contains("Kick_Off -> task_1 [label=\"Label 1\", style=solid, arrowhead=vee"));
}

// "A <|-- B" puts A above B in PlantUML. The edge used to run from B to A, so the
// subclass ranked above its parent; it now runs in the written order.
void test_class_reversed_arrow_keeps_written_order() {
    string dot = engine_dot("@startuml\nclass A\nclass B\nA <|-- B\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=none, arrowtail=empty, dir=both]"));
}

void test_object_reversed_arrow_keeps_written_order() {
    string dot = engine_dot("@startuml\nobject A\nobject B\nA <|-- B\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=none, arrowtail=empty, dir=both]"));
}

// ---- 2026-09-14 round 8 ----

string line_with(string dot, string needle) {
    foreach (string l in dot.split("\n")) {
        if (l.contains(needle)) {
            return l;
        }
    }
    return "";
}

// "entity" lines were skipped by the class parser, and "as" (an AS token) never
// registered an alias, so the box, its label and attributes vanished.
void test_class_entity_declaration() {
    string dot = engine_dot("@startuml\nentity \"Order Line\" as ol {\n  * id : int\n}\nentity Customer\nol }o--|| Customer\n@enduml");
    assert(class_box(dot, "ol", "Order Line", ">E</FONT>"));
    assert(dot.contains("id : int"));
    assert(class_box(dot, "Customer", "Customer", ">E</FONT>"));
    assert(!dot.contains("Order_Line ["));
}

// "class class2 as \"Label\"": the quoted side is the label, the bare name the key.
void test_class_quoted_alias_label() {
    string dot = engine_dot("@startuml\nclass \"This is my class\" as class1\nclass class2 as \"It works this way too\"\nclass1 --> class2\n@enduml");
    assert(class_box(dot, "class1", "This is my class"));
    assert(class_box(dot, "class2", "It works this way too"));
    assert(dot.contains("class1 -> class2 ["));
}

// "remove X" was ignored: the class and its links stayed.
void test_class_remove_by_name() {
    string dot = engine_dot("@startuml\nclass Foo1\nclass Foo2\nFoo2 *-- Foo1\nremove Foo2\n@enduml");
    assert(dot.contains("Foo1 [label="));
    assert(!dot.contains("Foo2"));
    assert(!dot.contains("remove"));
}

// "hide X" keeps the class's place, as PlantUML does: node and links drawn invisibly.
void test_class_hide_keeps_space() {
    string dot = engine_dot("@startuml\nclass Foo1\nclass Foo2\nFoo2 *-- Foo1\nhide Foo2\n@enduml");
    assert(class_box(dot, "Foo1", "Foo1") && !class_box(dot, "Foo1", "Foo1", "style=invis"));
    assert(class_box(dot, "Foo2", "Foo2", "style=invis"));
    assert(dot.contains("Foo2 -> Foo1 [style=invis"));
}

// "remove $tag13" then "restore $tag1": C1 carries both tags and comes back, I1 stays removed.
void test_class_remove_restore_tags() {
    string dot = engine_dot("@startuml\nclass C1 $tag13 $tag1\nenum E1\ninterface I1 $tag13\nC1 -- I1\nremove $tag13\nrestore $tag1\n@enduml");
    assert(dot.contains("C1 [label="));
    assert(dot.contains("E1 [label="));
    assert(!dot.contains("I1 [label="));
    assert(!dot.contains("C1 -> I1"));
}

// "remove *" then "restore $tag1" keeps only the restored class.
void test_class_remove_all_restore() {
    string dot = engine_dot("@startuml\nclass C1 $tag13 $tag1\nenum E1\ninterface I1 $tag13\nC1 -- I1\nremove *\nrestore $tag1\n@enduml");
    assert(dot.contains("C1 [label="));
    assert(!dot.contains("E1 [label="));
    assert(!dot.contains("I1 [label="));
}

// "@unlinked" selects classes without relationships.
void test_class_unlinked() {
    string removed = engine_dot("@startuml\nclass C1\nclass C2\nclass C3\nC1 -- C2\nremove @unlinked\n@enduml");
    assert(removed.contains("C1 [label=") && removed.contains("C2 [label="));
    assert(!removed.contains("C3"));
    string hidden = engine_dot("@startuml\nclass C1\nclass C2\nclass C3\nC1 -- C2\nhide @unlinked\n@enduml");
    assert(class_box(hidden, "C3", "C3", "style=invis"));
    assert(!class_box(hidden, "C1", "C1", "style=invis"));
}

// Member-level hide lines must not hide classes.
void test_class_member_hide_untouched() {
    string dot = engine_dot("@startuml\nclass A <<S>> {\n  +x : int\n}\nclass B\nA --> B\nhide empty members\nhide A methods\nhide <<S>> circle\nhide members\n@enduml");
    assert(dot.contains("A [label="));
    assert(!dot.contains("style=invis"));
}

// "class $C1" vanished; "remove $C1" is a tag removal in PlantUML and leaves the class alone.
void test_class_dollar_names() {
    string dot = engine_dot("@startuml\nclass $C1\nclass $C2\nclass \"$C2\" as dollarC2\nremove $C1\nremove $C2\nremove dollarC2\n@enduml");
    assert(class_box(dot, "_C1", "$C1"));
    assert(class_box(dot, "_C2", "$C2"));
    assert(!dot.contains("dollarC2"));
}

// Crow's-foot ends were not taken as arrows: the links and their target boxes vanished.
void test_class_crows_foot_ends() {
    string dot = engine_dot("@startuml\nA1 }o--|| B1\nA2 |o--o{ B2\nA3 }|--|{ B3\nA4 ||--o| B4\n@enduml");
    assert(dot.contains("A1 -> B1 [style=solid, arrowhead=teetee, arrowtail=crowodot, dir=both"));
    assert(dot.contains("A2 -> B2 [style=solid, arrowhead=crowodot, arrowtail=teeodot, dir=both"));
    assert(dot.contains("A3 -> B3 [style=solid, arrowhead=crowtee, arrowtail=crowtee, dir=both"));
    assert(dot.contains("A4 -> B4 [style=solid, arrowhead=teeodot, arrowtail=teetee, dir=both"));
}

// A keyword alias ("as node") was not read, a line starting with it was skipped, and as a
// DOT id "node" would be a default-attribute statement.
void test_class_keyword_alias() {
    string dot = engine_dot("@startuml\nentity \"Order Line\" as node {\n  * id : int\n}\nentity Customer\nnode }o--|| Customer : places\nCustomer ||--|| node : has\n@enduml");
    assert(class_box(dot, "node_", "Order Line", ">E</FONT>"));
    assert(dot.contains("node_ -> Customer [style=solid, arrowhead=teetee, arrowtail=crowodot"));
    assert(dot.contains("Customer -> node_ [style=solid, arrowhead=teetee, arrowtail=teetee"));
}

const string ARTIFACT_ARROWS = "@startuml\nartifact artifact1\nartifact artifact2\nartifact artifact3\nartifact artifact4\nartifact artifact5\nartifact artifact6\nartifact artifact7\nartifact artifact8\nartifact artifact9\nartifact artifact10\nartifact1 --> artifact2\nartifact1 --* artifact3\nartifact1 --o artifact4\nartifact1 --+ artifact5\nartifact1 --# artifact6\nartifact1 -->> artifact7\nartifact1 --0 artifact8\nartifact1 --^ artifact9\nartifact1 --(0 artifact10\n@enduml";

// A file of "artifact" lines with class-style arrows was a class diagram: "--0 artifact8"
// drew a class named "0" and artifact8 and artifact10 vanished.
void test_detect_deployment_elements_as_component() {
    string dot = engine_dot(ARTIFACT_ARROWS);
    assert(dot.has_prefix("digraph component"));
    assert(dot.contains("artifact8 [label="));
    assert(dot.contains("artifact10 [label="));
    assert(!dot.contains("c_0"));
    assert(dot.contains("artifact1 -> artifact8 ["));
}

// A file listing every element type ("component", "entity", "artifact", ...) stays a component
// diagram: the "entity" exclusion is only for files made of deployment elements alone.
void test_detect_element_list_with_entity_stays_component() {
    string dot = engine_dot("@startuml\nactor actor\nagent agent\nartifact artifact\ncomponent component\nentity entity\nnode node\n@enduml");
    assert(dot.has_prefix("digraph component"));
    assert(dot.contains("agent [label="));
}

// Description-diagram ends as PlantUML draws them: "--#" a hollow square (was filled),
// "-->>" a filled triangle (was an open vee), "--+" a circle-plus (was a plain circle).
void test_component_end_marker_shapes() {
    string dot = engine_dot(ARTIFACT_ARROWS);
    assert(dot.contains("artifact1 -> artifact6 [style=solid, arrowtail=none, arrowhead=obox, dir=both]"));
    assert(dot.contains("artifact1 -> artifact7 [style=solid, arrowtail=none, arrowhead=normal, dir=both]"));
    assert(dot.contains("artifact1 -> artifact5 [style=solid, arrowtail=none, arrowhead=odot, dir=both, class=\"gdplus gdplushead\""));
    assert(count_substr(dot, "class=\"gdplus") == 1);
}

// "-left->" between elements in two containers: a root rank=same pulled both out of their clusters.
void test_component_side_link_keeps_containers() {
    string dot = engine_dot("@startuml\nnode N1 {\n  [A]\n}\nnode N2 {\n  [B]\n}\nA -left-> B\n@enduml");
    assert(dot.contains("B -> A [style=solid, arrowtail=vee, arrowhead=none"));
    assert(!dot.contains("rank=same"));
    string top = engine_dot("@startuml\ncomponent C\ncomponent D\nC -right-> D\n@enduml");
    assert(top.contains("{ rank=same; C; D; }"));
}

// Note text is not a declaration: "node version ..." / "[optional] ..." in activity notes made them component diagrams.
void test_detect_note_text_not_declarations() {
    assert(TypeDetector.detect_plantuml("@startuml\nstart\n:Deploy app;\nnote right\n  node version must be >= 18\nend note\nstop\n@enduml") == DiagramType.ACTIVITY);
    assert(TypeDetector.detect_plantuml("@startuml\nstart\n:step;\nnote right\n  [optional] retry\nend note\nstop\n@enduml") == DiagramType.ACTIVITY);
    // no start/stop to fall back on: only the note stripping keeps this a use case diagram
    assert(TypeDetector.detect_plantuml("@startuml\nactor User\nUser --> (Login)\nnote right of User\n  node must be up\nend note\n@enduml") == DiagramType.USECASE);
}

// Activity action text on its own line ("node packages;") is not a node declaration.
void test_detect_activity_action_text_not_declaration() {
    assert(TypeDetector.detect_plantuml("@startuml\nstart\n:Upgrade\nnode packages;\nstop\n@enduml") == DiagramType.ACTIVITY);
}

// Sequence messages between queue/collections participants (and "[->" from outside) are a sequence diagram.
void test_detect_queue_participants_sequence() {
    assert(TypeDetector.detect_plantuml("@startuml\ncollections Workers\nqueue Jobs\nJobs -> Workers : dispatch\n@enduml") == DiagramType.SEQUENCE);
    assert(TypeDetector.detect_plantuml("@startuml\nqueue Jobs\n[-> Jobs : submit\nJobs ->] : done\n@enduml") == DiagramType.SEQUENCE);
}

// A use case diagram with its use cases in a frame stays a use case diagram (was component boxes).
void test_detect_usecase_in_frame() {
    assert(TypeDetector.detect_plantuml("@startuml\nactor Customer\nframe \"Shop\" {\n  usecase Checkout\n  (Browse)\n}\nCustomer --> Checkout\nCustomer --> (Browse)\n@enduml") == DiagramType.USECASE);
}

// Legacy activity "(*) --> "First"" was a use case diagram.
void test_detect_legacy_activity_start() {
    assert(TypeDetector.detect_plantuml("@startuml\n(*) --> \"First\"\n\"First\" --> (*)\n@enduml") == DiagramType.ACTIVITY);
}

// Indented "class" lines count as class declarations: an association class "(A, B) .. C" was a use case.
void test_detect_indented_class_association() {
    assert(TypeDetector.detect_plantuml("@startuml\npackage p {\n  class Student\n  class Course\n}\n(Student, Course) .. Enrollment\n@enduml") == DiagramType.CLASS);
}

// A floating 'note "x" as N' has no body: it switched note-skipping on for the rest of the file.
void test_detect_floating_note_usecase() {
    assert(TypeDetector.detect_plantuml("@startuml\nnote \"Hint\" as N\n(Login) --> (Logout)\n@enduml") == DiagramType.USECASE);
}

// actor, ":Ops: as O", stack, hexagon, person inside a container: they were component boxes or ghosts named after the keyword.
void test_component_nested_element_words() {
    string dot = engine_dot("@startuml\nnode N {\n  actor Admin\n  :Ops: as O\n  stack S\n  hexagon H\n  person P\n}\nAdmin --> S\n@enduml");
    assert(dot.contains("Admin [shape=none, class=\"gdactor ") && dot.contains(">Admin<"));
    assert(dot.contains("O [shape=none, class=\"gdactor ") && dot.contains(">Ops<"));
    assert(dot.contains("S [label=\"S\", shape=box"));
    assert(dot.contains("H [label=\"H\", shape=hexagon"));
    assert(!dot.contains("stack [") && !dot.contains("person ["));
    assert(dot.index_of("P [label=\"P\"") < dot.index_of("N_anchor"));
}

// "[A]--[B]" / "[C]..[D]": the "[" of the target was read as an arrow options block, dropping B, D and both links.
void test_component_glued_bracket_links() {
    string dot = engine_dot("@startuml\n[A]--[B]\n[C]..[D]\n[E] -[#red]-> [F]\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=none]"));
    assert(dot.contains("C -> D [style=dashed, arrowhead=none]"));
    assert(dot.contains("E -> F [") && dot.contains("color=\"red\""));  // "-[#red]->" options still read
}

// "component _internal" lost its declaration: names had to start with a letter or digit.
void test_component_underscore_name() {
    string dot = engine_dot("@startuml\ncomponent _internal\ncomponent Other\n_internal --> Other\n@enduml");
    assert(dot.contains("_internal [label=\"_internal\", shape=box"));
}

// "A --* B" / "A --o B" draw the diamond at B, where it is written; it was always at A.
void test_component_diamond_written_end() {
    string dot = engine_dot("@startuml\ncomponent A\ncomponent B\ncomponent C\ncomponent D\nA --* B\nA *-- C\nA --o D\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=diamond"));
    assert(dot.contains("A -> C [style=solid, arrowhead=none, arrowtail=diamond, dir=both"));
    assert(dot.contains("A -> D [style=solid, arrowhead=odiamond"));
}

// Graphviz has no circle-plus or cross: the SVG gets a plus inside the odot circle and an x in
// place of the obox, as PlantUML draws "+--" and "x--" (they were an open circle and a bar).
// Same-named packages in different parents merged: Beta's "Common" got Alpha's classes
void test_class_same_named_nested_packages() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\npackage Alpha {\n  package Common {\n    class X\n  }\n}\npackage Beta {\n  package Common {\n    class Y\n  }\n}\n@enduml"));
    assert(d.packages.size == 2);
    assert(d.packages[0].children.size == 1);
    assert(d.packages[1].children.size == 1);
    var alpha_common = d.packages[0].children[0];
    var beta_common = d.packages[1].children[0];
    assert(alpha_common.classes.size == 1 && alpha_common.classes[0].name == "X");
    assert(beta_common.classes.size == 1 && beta_common.classes[0].name == "Y");
}

// Use case "Auth <.. Login" / "Admin <. User" were drawn pointing at Login / User
void test_usecase_reverse_dotted_arrow() {
    var d = new UseCaseDiagramParser().parse(lex_puml("@startuml\nactor User\nactor Admin\nusecase Login\nusecase Auth\nAuth <.. Login\nAdmin <. User\n@enduml"));
    assert(d.relationships.size == 2);
    assert(d.relationships[0].from_id == "Login" && d.relationships[0].to_id == "Auth");
    assert(d.relationships[1].from_id == "User" && d.relationships[1].to_id == "Admin");
}

// Use cases inside frame/node/cloud/folder lost their container: only package and rectangle
// were parsed as containers (now that such files are detected as use case diagrams)
void test_usecase_frame_container() {
    string dot = engine_dot("@startuml\nactor Customer\nframe \"Shop\" {\n  usecase Checkout\n  (Browse)\n}\nnode Web {\n  usecase Pay\n}\nCustomer --> Checkout\nCustomer --> (Browse)\nCustomer --> Pay\n@enduml");
    int shop = dot.index_of("label=\"Shop\"");
    assert(shop >= 0);
    int web = dot.index_of("label=\"Web\"");
    assert(web > shop);
    int checkout = dot.index_of("Checkout [label=\"Checkout\", shape=ellipse");
    int browse = dot.index_of("Browse [label=\"Browse\", shape=ellipse");
    int pay = dot.index_of("Pay [label=\"Pay\", shape=ellipse");
    assert(checkout > shop && checkout < web);
    assert(browse > shop && browse < web);
    assert(pay > web);
    assert(dot.contains("Customer -> Checkout") && dot.contains("Customer -> Browse") && dot.contains("Customer -> Pay"));
}

// "(A) --> (B)" inside a container: the relationship parser did not accept "(" as the first
// element, and the container body loop never advanced (the parse hung)
void test_usecase_link_inside_container() {
    string dot = engine_dot("@startuml\nactor U\nrectangle R {\n  (A) --> (B)\n  (C)\n}\nU --> (A)\n@enduml");
    assert(dot.contains("A -> B ["));
    assert(dot.contains("U -> A ["));
    int r = dot.index_of("label=\"R\"");
    int c = dot.index_of("C [label=\"C\", shape=ellipse");
    assert(r >= 0 && c > r);
}

// Top-level "(A) --> (B)" was skipped as an unknown line, and "(X)" ends were never declared
// (grey default nodes with unreadable labels)
void test_usecase_paren_statement_top_level() {
    string dot = engine_dot("@startuml\nactor U\n(A) --> (B)\nU --> (A)\n@enduml");
    assert(dot.contains("A -> B ["));
    assert(dot.contains("A [label=\"A\", shape=ellipse"));
    assert(dot.contains("B [label=\"B\", shape=ellipse"));
}

// "--" and ".." are plain lines and "-.->" is dashed; every link used to get an arrowhead
void test_usecase_undirected_links() {
    string dot = engine_dot("@startuml\nactor U\nactor V\nU -- (A)\nU --> (C)\nV .> (B)\nV .. (D)\nU -.-> (E)\n@enduml");
    assert(dot.contains("U -> A [style=solid, arrowhead=none"));
    assert(dot.contains("U -> C [style=solid, arrowhead=vee"));
    assert(dot.contains("V -> B [style=dashed, arrowhead=vee"));
    assert(dot.contains("V -> D [style=dashed, arrowhead=none"));
    assert(dot.contains("U -> E [style=dashed, arrowhead=vee"));
}

// A link end named like its container is the container ("(Sys) -- V" in "rectangle Sys"):
// it became a separate node "Sys" and the empty rectangle was dropped
void test_usecase_container_as_endpoint() {
    string dot = engine_dot("@startuml\nactor V\nrectangle Sys {\n  (Sys) -- V\n  (Inner) .> (Sys) : include\n}\n@enduml");
    assert(!dot.contains("Sys [label="));
    assert(dot.contains("_ucpkg0_anchor -> V [style=solid, arrowhead=none, ltail=cluster_0]"));
    // linked from inside its own container: a use case node of its own, not the anchor
    assert(dot.contains("Inner -> _ucpkg0_self [label=\"include\", style=dashed, arrowhead=vee]"));
    int sys = dot.index_of("label=\"Sys\"");
    int inner = dot.index_of("Inner [label=\"Inner\", shape=ellipse");
    int anchor = dot.index_of("_ucpkg0_anchor [label=\"\"");
    assert(sys >= 0 && inner > sys && anchor > inner);
}

// "(Use the application) as (Use)": the parenthesised alias was ignored, so "(Start) <|-- (Use)"
// created a second use case "Use" and linked that ghost
void test_usecase_paren_alias() {
    string dot = engine_dot("@startuml\n:Main Admin: as Admin\n(Use the application) as (Use)\nUser <|-- Admin\n(Start) <|-- (Use)\n@enduml");
    assert(count_substr(dot, "[label=\"Use the application\"") == 1);
    assert(dot.contains("Use [label=\"Use the application\""));
    assert(!dot.contains("Use_the_application ["));
    assert(dot.contains("Use -> Start ["));
}

// ":Main Admin: as Admin" created an actor "User" and dropped the name; "User" (only used in a
// link) was a grey default node instead of an actor
void test_usecase_colon_actor_declaration() {
    string dot = engine_dot("@startuml\n:Main Admin: as Admin\nUser <|-- Admin\n@enduml");
    assert(line_with(dot, "Admin [shape=none").contains("class=\"gdactor") && line_with(dot, "Admin [shape=none").contains(">Main Admin<"));
    assert(line_with(dot, "User [shape=none").contains(">User<"));
    assert(count_substr(dot, "User [shape=none") == 1);
    assert(dot.contains("Admin -> User [style=solid, arrowhead=empty"));
}

// "(Use case 1) <.. :user:": an actor as the link target was not accepted and the link dropped
void test_usecase_colon_actor_endpoint() {
    string dot = engine_dot("@startuml\n(Use case 1) <.. :user:\n(Use case 2) <- :user:\n@enduml");
    assert(count_substr(dot, "user [shape=none, class=\"gdactor") == 1);
    assert(dot.contains("user -> Use_case_1 [style=dashed, arrowhead=vee"));
    assert(dot.contains("user -> Use_case_2 [style=solid, arrowhead=vee"));
}

// "#line:red;line.bold;text:red" link styles were ignored and the ": label" after them lost
void test_usecase_link_inline_style() {
    string dot = engine_dot("@startuml\nactor foo\nfoo --> (bar) : normal\nfoo --> (bar1) #line:red;line.bold;text:red  : red bold\nfoo --> (bar2) #green;line.dashed;text:green : green dashed\nfoo --> (bar3) #blue;line.dotted;text:blue   : blue dotted\n@enduml");
    string normal = line_with(dot, "foo -> bar [");
    assert(normal.contains("label=\"normal\""));
    string red = line_with(dot, "foo -> bar1 [");
    assert(red.contains("label=\"red bold\"") && red.contains("color=\"red\"") && red.contains("penwidth=2") && red.contains("fontcolor=\"red\""));
    string green = line_with(dot, "foo -> bar2 [");
    assert(green.contains("label=\"green dashed\"") && green.contains("style=dashed") && green.contains("color=\"green\""));
    string blue = line_with(dot, "foo -> bar3 [");
    assert(blue.contains("label=\"blue dotted\"") && blue.contains("style=dotted") && blue.contains("fontcolor=\"blue\""));
}

// "BackgroundColor<< Main >> YellowGreen" overwrote the plain BackgroundColor, so every use case
// got the Main colour; ArrowColor was ignored
void test_usecase_stereotype_colors() {
    string dot = engine_dot("@startuml\nskinparam usecase {\n  BackgroundColor DarkSeaGreen\n  BorderColor DarkSlateGray\n  BackgroundColor<< Main >> YellowGreen\n  BorderColor<< Main >> YellowGreen\n  ArrowColor Olive\n}\nUser << Human >>\n(Start) << One Shot >>\n(Use the application) as (Use) << Main >>\nUser -> (Start)\nUser --> (Use)\n@enduml");
    string start = line_with(dot, "Start [label=");
    assert(start.contains("fillcolor=\"DarkSeaGreen\"") && start.contains("color=\"DarkSlateGray\""));
    string use = line_with(dot, "Use [label=");
    assert(use.contains("fillcolor=\"YellowGreen\"") && use.contains("color=\"YellowGreen\""));
    assert(line_with(dot, "edge [").contains("color=\"Olive\""));
}

// Stereotypes were not shown, and "<< One Shot >>" (several words) was not even read
void test_usecase_stereotype_labels() {
    string dot = engine_dot("@startuml\nUser << Human >>\n:Main Database: as MySql << Application >>\n(Start) << One Shot >>\n(Use the application) as (Use) << Main >>\nUser -> (Start)\nUser --> (Use)\nMySql --> (Use)\n@enduml");
    assert(line_with(dot, "User [shape=none").contains("<I>«Human»</I>"));
    assert(line_with(dot, "MySql [shape=none").contains("<I>«Application»</I>") && line_with(dot, "MySql [shape=none").contains(">Main Database<"));
    assert(dot.contains("Start [label=\"«One Shot»\\nStart\""));
    assert(dot.contains("Use [label=\"«Main»\\nUse the application\""));
}

// Business actors ":Name:/", "actor/ Name" and "actor :Label: as X": the "/" became an actor
// named "/", and the actor label and alias were lost
void test_usecase_business_actors() {
    string dot = engine_dot("@startuml\n:First Actor:/\n:Another\\nactor:/ as Man2\nactor/ Woman3\nactor/ :Last actor: as Person1\n@enduml");
    assert(line_with(dot, "First_Actor [shape=none").contains(">First Actor<"));
    assert(line_with(dot, "Man2 [shape=none").contains(">Another<BR/>actor<"));
    assert(line_with(dot, "Woman3 [shape=none").contains(">Woman3<"));
    assert(line_with(dot, "Person1 [shape=none").contains(">Last actor<"));
    assert(count_substr(dot, "gdbusiness") == 4);
    assert(!dot.contains(">/<"));
}

// Actors were filled ellipses; PlantUML draws stick figures, and business elements get a "/"
// (through an actor's head, near the right edge of a use case)
void test_usecase_actor_stick_figures_svg() {
    var engine = new DiagramEngine("dot");
    uint8[]? data = engine.generate_svg("@startuml\nactor User\n:Boss:/\n(Pay)/\nUser --> (Pay)\nBoss --> (Pay)\n@enduml", "test.puml", null);
    assert(data != null);
    var text = new StringBuilder();
    text.append_len((string) data, data.length);
    string svg = text.str;
    assert(!svg.contains("#010203"));
    assert(count_substr(svg, "<circle class=\"gdfigure\"") == 2);
    assert(count_substr(svg, "class=\"gdslash\"") == 2);
}

// PlantUML's own example: use cases first named inside "rectangle checkout" belong to it
void test_usecase_endpoints_declared_in_container() {
    string dot = engine_dot("@startuml\nleft to right direction\nactor customer\nactor clerk\nrectangle checkout {\n  customer -- (checkout)\n  (checkout) .> (payment) : include\n  (help) .> (checkout) : extends\n  (checkout) -- clerk\n}\n@enduml");
    int box = dot.index_of("label=\"checkout\"");
    int help = dot.index_of("help [label=\"help\", shape=ellipse");
    int payment = dot.index_of("payment [label=\"payment\", shape=ellipse");
    int anchor = dot.index_of("_ucpkg0_anchor [label=\"\"");
    assert(box >= 0 && help > box && payment > box && anchor > help && anchor > payment);
    assert(dot.contains("customer -> _ucpkg0_anchor [style=solid, arrowhead=none, lhead=cluster_0]"));
    assert(dot.contains("_ucpkg0_anchor -> clerk [style=solid, arrowhead=none, ltail=cluster_0]"));
}

// "-o : Point" lexed as the arrow "-o" and the member vanished
void test_class_member_named_o() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\nclass A {\n  -o : Point\n  -x : int\n}\n@enduml"));
    var a = d.find_class("A");
    assert(a != null);
    assert(a.members.size == 2);
    assert(a.members[0].name == "o : Point");
    assert(a.members[0].visibility == MemberVisibility.PRIVATE);
}

// "+* : int" was taken as a mandatory marker with no name, and the member vanished
void test_class_member_named_star() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\nclass A {\n  +* : int\n}\n@enduml"));
    var a = d.find_class("A");
    assert(a != null);
    assert(a.members.size == 1);
    assert(a.members[0].name == "* : int");
    assert(!a.members[0].mandatory);
}

// "Bar --> Foo" inside namespace n made a second box n.Foo instead of linking the global Foo
void test_class_namespace_reference_reuses_global() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\nclass Foo\nnamespace n {\n  class Bar\n  Bar --> Foo\n}\n@enduml"));
    assert(d.find_class("n.Foo") == null);
    assert(d.classes.size == 2);
    assert(d.relationships.size == 1 && d.relationships[0].to.name == "Foo");
}

// "B --> P.A" for a class declared in package P made a second box P.A
void test_class_package_qualified_reference() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\npackage P {\n  class A\n}\nclass B\nB --> P.A\n@enduml"));
    assert(d.classes.size == 2);
    assert(d.relationships.size == 1 && d.relationships[0].to.name == "A");
}

// "package ... as DM": the alias was dropped and "Service --> DM" drew a class box DM
void test_class_package_alias_link() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\npackage \"Domain Model\" as DM {\n  class User\n}\nclass Service\nService --> DM\n@enduml"));
    assert(d.find_class("DM") == null);
    assert(d.package_links.size == 1);
    assert(d.package_links[0].to_package == d.packages[0]);
}

// "A <--> B" lost its tail arrowhead and "C *--> D" its arrowhead
void test_class_two_marker_arrows() {
    string dot = engine_dot("@startuml\nclass A\nclass B\nclass C\nclass D\nA <--> B\nC *--> D\n@enduml");
    assert(dot.contains("A -> B [style=solid, arrowhead=open, arrowtail=open, dir=both"));
    assert(dot.contains("C -> D [style=solid, arrowhead=open, arrowtail=diamond, dir=both"));
}

// note "text" as N1 (no colon) swallowed the rest of the file as note text
void test_class_floating_note_alias() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\nclass A\nnote \"floating text\" as N1\nN1 .. A\nclass B\nA --> B\n@enduml"));
    assert(d.notes.size == 1);
    assert(d.notes[0].text == "floating text");
    assert(d.find_class("N1") == null);
    assert(d.find_class("B") != null);
    assert(d.relationships.size == 1);
    assert(d.notes[0].links.size == 1 && d.notes[0].links[0].target == "A");
}

// "together {" became a ghost class named "together"
void test_class_together_no_ghost() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\ntogether {\n  class A\n  class B\n}\nA --> B\n@enduml"));
    assert(d.find_class("together") == null);
    assert(d.classes.size == 2);
    assert(d.relationships.size == 1);
}

// "A }|..|{ B" lost its head crow; "C |o..o| D" and "E }o..|| F" made no edge
void test_class_dotted_crowsfoot_ends() {
    var d = new ClassDiagramParser().parse(lex_puml("@startuml\nclass A\nclass B\nclass C\nclass D\nclass E\nclass F\nA }|..|{ B\nC |o..o| D\nE }o..|| F\n@enduml"));
    assert(d.classes.size == 6);
    assert(d.relationships.size == 3);
    assert(d.relationships[0].ie_tail == "crowtee" && d.relationships[0].ie_head == "crowtee");
    assert(d.relationships[1].ie_tail == "teeodot" && d.relationships[1].ie_head == "teeodot");
    assert(d.relationships[2].ie_tail == "crowodot" && d.relationships[2].ie_head == "teetee");
}

// ER: "Order }|..|| Cust" and "Item |o..|| Order" were dropped, leaving ghost entities
void test_er_dotted_crowsfoot_ends() {
    var d = new ERDiagramParser().parse(lex_puml("@startuml\nentity Order\nentity Item\nentity Cust\nOrder }|..|| Cust\nItem |o..|| Order\n@enduml"));
    assert(d.entities.size == 3);
    assert(d.relationships.size == 2);
    assert(d.relationships[0].from_cardinality == ERCardinality.MANY_MANDATORY);
    assert(d.relationships[0].to_cardinality == ERCardinality.ONE_MANDATORY);
    assert(d.relationships[1].from_cardinality == ERCardinality.ZERO_OR_ONE);
    assert(d.relationships[1].is_dashed);
}

void test_class_plus_cross_markers_svg() {
    var diagram = new ClassDiagramParser().parse(lex_puml("@startuml\nclass Outer\nclass Inner\nOuter +-- Inner\nclass A\nclass B\nA x-- B\n@enduml"));
    // The renderer holds the context unowned: keep it alive for the render
    var ctx = new Gvc.Context();
    var renderer = new ClassDiagramRenderer(ctx, new Gee.ArrayList<ElementRegion>(), "dot");
    uint8[]? data = renderer.render_to_svg(diagram);
    assert(data != null);
    var text = new StringBuilder();
    text.append_len((string) data, data.length);
    string svg = text.str;
    int plus = svg.index_of("class=\"edge gdplus\"");
    assert(plus >= 0);
    string plus_group = svg.substring(plus, svg.index_of("</g>", plus) - plus);
    assert(plus_group.contains("<ellipse"));
    assert(plus_group.contains("class=\"gdmark\""));
    int cross = svg.index_of("class=\"edge gdcross\"");
    assert(cross >= 0);
    string cross_group = svg.substring(cross, svg.index_of("</g>", cross) - cross);
    assert(cross_group.contains("class=\"gdmark\""));
    assert(!cross_group.contains("<polygon"));
}

// "+--", "#--", "x--", "}--", "^--" were all drawn as an open diamond.
void test_class_aggregation_marker_shapes() {
    string dot = engine_dot("@startuml\nclass A1\nA1 +-- B1\nA2 #-- B2\nA3 x-- B3\nA4 }-- B4\nA5 ^-- B5\nA6 o-- B6\n@enduml");
    assert(dot.contains("A1 -> B1 [style=solid, arrowhead=none, arrowtail=odot"));
    assert(dot.contains("A2 -> B2 [style=solid, arrowhead=none, arrowtail=obox"));
    assert(dot.contains("A3 -> B3 [style=solid, arrowhead=none, arrowtail=obox"));
    // "+" and "x" carry a marker class; the SVG gets the real marker drawn over the placeholder
    assert(dot.contains("A1 -> B1 [style=solid, arrowhead=none, arrowtail=odot, dir=both, class=\"gdplus\""));
    assert(dot.contains("A3 -> B3 [style=solid, arrowhead=none, arrowtail=obox, dir=both, class=\"gdcross\""));
    assert(count_substr(dot, "gdplus") == 1 && count_substr(dot, "gdcross") == 1);
    assert(dot.contains("A4 -> B4 [style=solid, arrowhead=none, arrowtail=ocrow"));
    assert(dot.contains("A5 -> B5 [style=solid, arrowhead=none, arrowtail=onormal"));
    assert(dot.contains("A6 -> B6 [style=solid, arrowhead=none, arrowtail=odiamond"));
}

// Cardinality labels sat on the arrow end, where a short "1" hid under the diamond.
void test_class_cardinality_labels_offset() {
    string dot = engine_dot("@startuml\nClass01 \"1\" *-- \"many\" Class02 : contains\n@enduml");
    assert(dot.contains("taillabel=\"1\", headlabel=\"many\", labeldistance=2, labelangle=-40"));
}

// <style> ".stereotype" selectors were skipped.
void test_style_stereotype_selectors() {
    string comp = engine_dot("""@startuml
<style>
.warning {
  BackgroundColor #E53935
  FontColor #FFFFFF
}
componentDiagram {
  component {
    .db {
      BackgroundColor #1E88E5
    }
  }
}
</style>
component "Plain" as P
component "Alert" as W <<warning>>
component "Store" as D <<db>>
P --> W
W --> D
@enduml""");
    assert(line_with(comp, "W [label=<").contains("fillcolor=\"#E53935\""));
    assert(line_with(comp, "W [label=<").contains("fontcolor=\"#FFFFFF\""));
    assert(line_with(comp, "D [label=<").contains("fillcolor=\"#1E88E5\""));
    assert(!line_with(comp, "P [label=\"Plain\"").contains("#E53935"));
    string cls = engine_dot("@startuml\n<style>\nclassDiagram {\n  class {\n    .entity { BackgroundColor #6A1B9A }\n  }\n}\n</style>\nclass User <<entity>>\nclass Plain\nUser --> Plain\n@enduml");
    assert(line_with(cls, "User [label=").contains("fillcolor=\"#6A1B9A\""));
    string st = engine_dot("@startuml\n<style>\nstateDiagram {\n  state {\n    .good { BackgroundColor #2E7D32 }\n  }\n}\n</style>\nstate \"ok\" as ok <<good>>\n[*] --> ok\n@enduml");
    assert(line_with(st, "ok [label=").contains("fillcolor=\"#2E7D32\""));
}

// <style> ":depth(n)" selectors were skipped, and the mind map renderer read no styles.
void test_style_depth_selectors() {
    string dot = engine_dot("""@startmindmap
<style>
mindmapDiagram {
  node {
    BackgroundColor #EEEEEE
  }
  :depth(0) {
    BackgroundColor #FFB300
  }
  :depth(1) {
    BackgroundColor #43A047
    FontColor #FFFFFF
  }
}
</style>
* Root
** Branch A
*** Leaf A1
@endmindmap""");
    assert(line_with(dot, "label=\"Root\"").contains("fillcolor=\"#FFB300\""));
    assert(line_with(dot, "label=\"Branch A\"").contains("fillcolor=\"#43A047\""));
    assert(line_with(dot, "label=\"Branch A\"").contains("fontcolor=\"#FFFFFF\""));
    assert(line_with(dot, "label=\"Leaf A1\"").contains("fillcolor=\"#EEEEEE\""));
}

// ---- 2026-09-15 round 9 ----

// A component stereotype was an external "<<name>>" xlabel beside the box; PlantUML
// draws «name» in italics above the name, inside the shape.
void test_component_stereotype_inside_label() {
    string dot = engine_dot("@startuml\ncomponent \"Alert\" as W <<warning>>\nrectangle \"Web App\\n[React]\" <<container>> as web\nW --> web\n@enduml");
    assert(dot.contains("W [label=<<I>«warning»</I><BR/>Alert>"));
    assert(dot.contains("web [label=<<I>«container»</I><BR/>Web App<BR/>[React]>"));
    assert(!dot.contains("xlabel=\"<<"));
    string boundary = engine_dot("@startuml\nrectangle \"Online Store\" <<system_boundary>> as store {\n  rectangle \"API\" <<container>> as api\n}\n@enduml");
    assert(boundary.contains("label=<<I>«system_boundary»</I><BR/><B>Online Store</B>>;"));
}

// An interface inside a container was written twice: in the cluster and again at
// the top level.
void test_component_nested_interface_emitted_once() {
    string dot = engine_dot("@startuml\nnode \"PHY\" as phy {\n  interface \"10/100 Mbps\" as ETH\n}\n[Svc] --> ETH\n@enduml");
    assert(count_substr(dot, "ETH [shape=plaintext") == 1);
    int cluster = dot.index_of("subgraph cluster_0 {");
    int node = dot.index_of("ETH [shape=plaintext");
    assert(cluster >= 0 && node > cluster && node < dot.index_of("\n  }\n", cluster));
    assert(dot.contains("Svc -> ETH:c ["));
}

// A one-line skinparam block (what a <style> stereotype selector translates to) lost its "}"
// to the value, so every later line became a skinparam property and all messages vanished.
void test_seq_one_line_skinparam_block_keeps_messages() {
    string dot = engine_dot("@startuml\n<style>\nparticipant.foo {\n  BackgroundColor red\n}\n</style>\n" +
                            "Alice -> Bob : hello\nBob -> Carol : second\n@enduml");
    assert(dot.contains("label=\"  hello  \""));
    assert(dot.contains("label=\"  second  \""));
    dot = engine_dot("@startuml\nskinparam participant { BackgroundColor red }\nAlice -> Bob : hello\n@enduml");
    assert(dot.contains("label=\"  hello  \""));
    assert(dot.contains("Alice_top [label=\"Alice\", shape=box, style=filled, fillcolor=\"red\""));
}

// Divider titles lost the quotes of a "string" and showed <b> literally.
void test_seq_divider_title_quotes_and_creole() {
    string dot = engine_dot("@startuml\nparticipant Solo\n== Only divider <b> & \"q\" ==\nSolo -> Solo : self\n" +
                            "== **Bold** </i> <i>x ==\n@enduml");
    assert(dot.contains(">Only divider <b> &amp; &quot;q&quot;</b></FONT>"));
    assert(dot.contains("><b>Bold</b> &lt;/i&gt; <i>x</i></FONT>"));
}

// An ER alias that is a keyword ("as node") was dropped, a relationship starting with it
// was skipped, and as a DOT id "node" would be a default-attribute statement
// The lexer splits crow's-foot ends into "}" "o--" "||" / "||" "--o" "{", and the ER parser
// checked token by token, so "}o--" and "--o{" relationships were dropped. Plain lines have no
// ends; exactly-one was a single bar, and "|{" was drawn as zero-or-many.
void test_er_crows_foot_links() {
    var tokens = lex_puml("@startuml\nentity A1\nA1 }o--|| B1\nA2 |o--o{ B2\nA3 }|--|{ B3\nA4 ||..o| B4\nA5 -- B5\n@enduml");
    var diagram = new ERDiagramParser().parse(tokens);
    var renderer = new ERDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("A1 -> B1 [style=solid, arrowhead=teetee, arrowtail=crowodot, dir=both]"));
    assert(dot.contains("A2 -> B2 [style=solid, arrowhead=crowodot, arrowtail=teeodot, dir=both]"));
    assert(dot.contains("A3 -> B3 [style=solid, arrowhead=crowtee, arrowtail=crowtee, dir=both]"));
    assert(dot.contains("A4 -> B4 [style=dashed, arrowhead=teeodot, arrowtail=teetee, dir=both]"));
    assert(dot.contains("A5 -> B5 [style=solid, arrowhead=none, arrowtail=none, dir=both]"));
}

// Drives the ER parser directly: type detection sends crow's-foot sources to the class parser.
void test_er_keyword_alias() {
    var tokens = lex_puml("@startuml\nentity \"Order Line\" as node {\n  * id : int\n}\nentity Customer\nnode ||--|| Customer : places\nCustomer ||--|| node : has\n@enduml");
    var diagram = new ERDiagramParser().parse(tokens);
    var renderer = new ERDiagramRenderer(new Gvc.Context(), new Gee.ArrayList<ElementRegion>(), "dot");
    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("node_ [label=\"{Order Line"));
    assert(!dot.contains("Order_Line ["));
    assert(dot.contains("node_ -> Customer ["));
    assert(dot.contains("Customer -> node_ ["));
}

// "as node {" used a keyword as the alias; the alias and "{" were left unread, so the
// boundary rendered as an empty box with its children outside it
void test_component_keyword_alias_container() {
    string dot = engine_dot("@startuml\nrectangle \"Worker Node\" <<container_boundary>> as node {\n  rectangle \"kubelet\" <<container>> as kubelet\n}\nrectangle \"API\" as api\nkubelet --> api\n@enduml");
    int cluster = dot.index_of("<B>Worker Node</B>");
    int node = dot.index_of("kubelet [label=");
    assert(cluster >= 0 && node > cluster && node < dot.index_of("\n  }\n", cluster));
    assert(dot.contains("kubelet -> api"));
}

const string STATE_NESTED = """@startuml
[*] --> Water
state Water {
  [*] --> Check
  Check --> Busy : go
  state Busy {
    Busy : heating
  }
}
state Mixed {
  [*] --> Prio
  Prio --> Water : switch
}
Water --> Mixed : both
@enduml""";

// A transition from inside a composite to an outer state created an inner copy
// of that state, and "state X {" after "A --> X" in the same body declared X twice.
void test_state_nested_transition_targets_outer_state() {
    string dot = engine_dot(STATE_NESTED);
    assert(count_substr(dot, " Busy [label=\"Busy") == 1);
    assert(!dot.contains("Water [label="));
}

// Edges into or out of a composite ended at an invisible point beside the
// cluster. The anchor now sits inside the cluster and lhead/ltail clip the edge
// at the border.
void test_state_composite_edges_clip_at_border() {
    string dot = engine_dot(STATE_NESTED);
    assert(dot.contains("    Water_anchor [label=\"\""));
    // Incoming links end at the cluster's first node, outgoing ones leave from its last,
    // so links in both directions do not share one anchor point
    assert(dot.contains("Prio -> _initial_1 [xlabel=\"switch\", style=solid, lhead=cluster_0, minlen=2]"));
    assert(dot.contains("Busy -> _initial_2 [xlabel=\"both\", style=solid, ltail=cluster_0, lhead=cluster_1, minlen=2]"));
}

// "scale 2" / "scale max 800 width" size the output; the state, object, deployment
// and ER parsers read the words after "scale" as elements ("2", "max", "800", "width").
void test_scale_line_makes_no_element() {
    string[] bodies = {
        "[*] --> Idle\nIdle --> Busy",
        "object Foo\nobject Bar\nFoo --> Bar",
        "device Dev\nnode Srv\nDev --> Srv",
        "entity Foo\nentity Bar\nFoo ||--|| Bar"
    };
    string[] real = { "Idle", "Foo", "Srv", "Foo" };
    for (int i = 0; i < bodies.length; i++) {
        foreach (string scale in new string[] { "scale 2", "scale 1.5", "scale max 800 width" }) {
            string dot = engine_dot("@startuml\n" + scale + "\n" + bodies[i] + "\n@enduml");
            assert(dot.contains(real[i]));
            foreach (string ghost in new string[] { "2", "1.5", "1_5", "max", "800", "width" }) {
                assert(!dot.contains("label=\"" + ghost + "\""));
                assert(!dot.contains("label=\"{" + ghost + "}"));
                assert(!dot.contains(">" + ghost + "<"));
            }
        }
    }
}

// Floating notes: "note as N1 ... end note" showed "as N1" as body text (state, object,
// use case); note "text" as N1 read on past @enduml (object, use case) or was dropped
// (component, deployment).
void test_floating_note_alias_forms() {
    string[] bodies = {
        "[*] --> Idle",
        "object Foo",
        "actor User\nusecase Login\nUser --> Login",
        "component Foo\ncomponent Bar\nFoo --> Bar",
        "node Srv\ncloud Net\nSrv --> Net",
        "class Foo"
    };
    foreach (string body in bodies) {
        string block = engine_dot("@startuml\n" + body +
            "\nnote as Warning\n  Body line one\n  Body line two\nend note\n@enduml");
        assert(block.contains("Body line one"));
        assert(block.contains("Body line two"));
        assert(!block.contains("as Warning"));

        string quoted = engine_dot("@startuml\n" + body + "\nnote \"Single body\" as N1\n@enduml");
        assert(quoted.contains("Single body"));
        assert(!quoted.contains("as N1"));
        assert(!quoted.contains("@enduml"));
    }
}

// A link to a floating note's alias ("(Start) .. N2") runs to the note, as in PlantUML; the
// alias used to become a ghost actor, object, state or default node.
void test_floating_note_alias_links() {
    string[] sources = {
        "[*] --> Idle\nnote \"Single body\" as N1\nIdle --> N1",
        "object Foo\nnote \"Single body\" as N1\nFoo .. N1",
        "actor User\nusecase Login\nUser --> Login\nnote \"Single body\" as N1\nLogin .. N1",
        "component Foo\ncomponent Bar\nFoo --> Bar\nnote \"Single body\" as N1\nFoo .. N1",
        "object Foo\nnote as N1\n  Single body\nend note\nN1 .. Foo",
        "actor User\nusecase Login\nUser --> Login\nnote as N1\n  Single body\nend note\nN1 .. Login"
    };
    foreach (string src in sources) {
        string dot = engine_dot("@startuml\n" + src + "\n@enduml");
        // Object notes get a generated DOT id: an alias such as "edge" is not a valid one
        string id = src.has_prefix("object") ? "_obj_note_0" : "N1";
        int node_lines = 0;
        bool edge = false;
        foreach (string raw in dot.split("\n")) {
            string l = raw.strip();
            if (l.has_prefix(id + " [")) {
                node_lines++;
                assert(l.contains("shape=note"));
                assert(l.contains("Single body"));
            }
            if (l.contains("-> " + id + " [") || l.has_prefix(id + " -> ")) edge = true;
        }
        assert(node_lines == 1);
        assert(edge);
    }

    // "note right of (Use)" left "(Use)" in the note text and drew no connector
    string uc = engine_dot("@startuml\n(Use the application) as (Use)\nnote right of (Use)\n  A note\nend note\n@enduml");
    assert(!uc.contains("(Use)"));
    assert(uc.contains("label=\"A note\""));
    assert(uc.contains(" -> Use [style=dotted, arrowhead=none]"));
}

// Edge label colour follows arrow FontColor, then DefaultFontColor (PlantUML 1.2026.1); with
// neither, a file's dark backgroundColor gets light labels. State labels were black and the
// other renderers used the palette's label grey whatever the file set.
string default_edge_line(string dot) {
    foreach (string raw in dot.split("\n")) {
        string l = raw.strip();
        if (l.has_prefix("edge [") && l.contains("fontname")) return l;
    }
    return "";
}

void test_edge_label_color_follows_skinparams() {
    string[] bodies = {
        "[*] --> Idle : Start\nIdle --> Busy : Go",
        "class Idle\nclass Busy\nIdle --> Busy : Go",
        "component Idle\ncomponent Busy\nIdle --> Busy : Go",
        "object Idle\nobject Busy\nIdle --> Busy : Go",
        "actor Idle\nusecase Busy\nIdle --> Busy : Go"
    };
    foreach (string body in bodies) {
        string dflt = engine_dot("@startuml\nskinparam backgroundColor #1e1e1e\nskinparam DefaultFontColor #ffffff\n" + body + "\n@enduml");
        assert(default_edge_line(dflt).contains("fontcolor=\"#ffffff\""));

        string arrow = engine_dot("@startuml\nskinparam backgroundColor #1e1e1e\nskinparam DefaultFontColor #ffffff\nskinparam arrow {\n  FontColor #ff8800\n}\n" + body + "\n@enduml");
        assert(default_edge_line(arrow).contains("fontcolor=\"#ff8800\""));

        string bg_only = engine_dot("@startuml\nskinparam backgroundColor #1e1e1e\n" + body + "\n@enduml");
        assert(default_edge_line(bg_only).contains("fontcolor=\"#FFFFFF\""));

        string light_bg = engine_dot("@startuml\nskinparam backgroundColor #fafafa\n" + body + "\n@enduml");
        assert(default_edge_line(light_bg).contains("fontcolor=\"#000000\""));
    }
}

// 'node "Web Server" as web' without a body is a node box labelled with the quoted text
// (it was an empty cluster titled "web"); a stereotype and colour after '[X] as Y' are
// kept; a mind map's lines follow "skinparam arrow { Color }"
void test_component_node_stereotype_and_mindmap_arrow() {
    string nodes = engine_dot("@startuml\nnode \"Web Server\" as web\nnode \"App Server\" as app\nweb --> app\n@enduml");
    assert(nodes.contains("web [label=\"Web Server\", shape=box3d"));
    assert(!nodes.contains("subgraph cluster"));

    string nested = engine_dot("@startuml\nnode \"Host\" as host {\n  [Service]\n}\n@enduml");
    assert(nested.contains("subgraph cluster"));

    // "X as Y": the quoted side is the label, otherwise the name (PlantUML 1.2026.1)
    string aliases = engine_dot("@startuml\nnode Node1 as n1\nfile f1 as \"File 1\"\ncloud c1 as \"this is a cloud\"\nn1 --> f1\nf1 --> c1\n@enduml");
    assert(aliases.contains("n1 [label=\"Node1\""));
    assert(aliases.contains("f1 [label=\"File 1\""));
    assert(aliases.contains("c1 [label=\"this is a cloud\""));
    assert(aliases.contains("n1 -> f1"));

    string comp = engine_dot("@startuml\n[Web Server] as WS <<frontend>> #pink\n[Cache]\nWS --> Cache\n@enduml");
    assert(comp.contains("«frontend»"));
    assert(comp.contains("fillcolor=\"pink\""));

    string mm = engine_dot("@startmindmap\nskinparam arrow {\n  Color #ff8800\n}\n* root\n** child\n@endmindmap");
    assert(default_edge_line(mm).contains("color=\"#ff8800\""));
}

// Text contrast on file-set fills and a nested bodyless node:
// - a Mermaid node with "style A fill:" got the palette text (white on yellow)
// - classes on a "classBackgroundColor" without FontColor got the palette text
// - a nested 'node X' inside a body was an empty cluster
void test_fill_text_contrast_and_nested_node() {
    string mmd = new DiagramEngine("dot").generate_dot("flowchart TD\n    A[Yellow] --> B[Dark]\n    style A fill:#ffcc00\n    style B fill:#222222\n", "test.mmd", null);
    assert(mmd.contains("A [label=\"Yellow\", shape=box, fillcolor=\"#ffcc00\", fontcolor=\"#000000\""));
    assert(mmd.contains("B [label=\"Dark\", shape=box, fillcolor=\"#222222\", fontcolor=\"#FFFFFF\""));

    string cls = engine_dot("@startuml\nskinparam classBackgroundColor Wheat\nclass Foo\n@enduml");
    assert(default_node_line(cls).contains("fontcolor=\"#000000\""));
    string cls_set = engine_dot("@startuml\nskinparam classBackgroundColor Wheat\nskinparam classFontColor #ff8800\nclass Foo\n@enduml");
    assert(default_node_line(cls_set).contains("fontcolor=\"#ff8800\""));

    string nested = engine_dot("@startuml\nnode Host {\n  node \"Inner Box\" as inner\n  [Service]\n}\ninner --> Service\n@enduml");
    assert(count_substr(nested, "subgraph cluster") == 1);
    assert(nested.contains("inner [label=\"Inner Box\", shape=box3d"));
    assert(nested.contains("inner -> Service"));
}

string default_node_line(string dot) {
    foreach (string raw in dot.split("\n")) {
        string l = raw.strip();
        if (l.has_prefix("node [")) return l;
    }
    return "";
}

// Edge line colour: "skinparam arrow { Color }" and "skinparam ArrowColor" apply to links in
// every diagram type (PlantUML 1.2026.1); only use case diagrams read ArrowColor.
void test_edge_line_color_follows_skinparams() {
    string[] bodies = {
        "[*] --> Idle\nIdle --> Busy : Go",
        "class Idle\nclass Busy\nIdle --> Busy : Go",
        "component Idle\ncomponent Busy\nIdle --> Busy : Go",
        "object Idle\nobject Busy\nIdle --> Busy : Go",
        "actor Idle\nusecase Busy\nIdle --> Busy : Go",
        // ER renderer ("||--o{" is routed to class) and "device"/"node" files (component)
        "entity Idle\nentity Busy\nIdle ||--|| Busy : Go",
        "device Idle\nnode Busy\nIdle --> Busy : Go"
    };
    foreach (string body in bodies) {
        string block = engine_dot("@startuml\nskinparam arrow {\n  Color #5a5a5a\n}\n" + body + "\n@enduml");
        assert(default_edge_line(block).contains("color=\"#5a5a5a\""));

        string flat = engine_dot("@startuml\nskinparam ArrowColor #ff8800\n" + body + "\n@enduml");
        assert(default_edge_line(flat).contains("color=\"#ff8800\""));
    }
}

// ER and mind map renderers (and "device" files, drawn by the component renderer) do not paint the file's backgroundColor; labels and
// titles still follow the skinparams. The ER and mind map parsers dropped every one-line
// skinparam (GObject set_property) and read "skinparam arrow { }" as a one-line skinparam.
void test_label_and_title_color_er_deployment_mindmap() {
    string[] bodies = {
        "entity Idle\nentity Busy\nIdle ||--|| Busy : Go",
        "device Idle\nnode Busy\nIdle --> Busy : Go"
    };
    foreach (string body in bodies) {
        string dflt = engine_dot("@startuml\nskinparam DefaultFontColor #ffffff\ntitle My Title\n" + body + "\n@enduml");
        assert(default_edge_line(dflt).contains("fontcolor=\"#ffffff\""));
        assert(dflt.contains("\n  fontcolor=\"#ffffff\";"));

        string arrow = engine_dot("@startuml\nskinparam titleFontColor #00aa00\nskinparam arrow {\n  FontColor #ff8800\n}\ntitle My Title\n" + body + "\n@enduml");
        assert(default_edge_line(arrow).contains("fontcolor=\"#ff8800\""));
        assert(arrow.contains("\n  fontcolor=\"#00aa00\";"));
    }

    string mindmap = engine_dot("@startmindmap\nskinparam DefaultFontColor #ffffff\ntitle My Title\n* root\n** child\n@endmindmap");
    assert(mindmap.contains("\n  fontcolor=\"#ffffff\";"));
    string mindmap_title = engine_dot("@startmindmap\nskinparam titleFontColor #00aa00\ntitle My Title\n* root\n** child\n@endmindmap");
    assert(mindmap_title.contains("\n  fontcolor=\"#00aa00\";"));
}

// Title colour: titleFontColor, then DefaultFontColor (PlantUML 1.2026.1); with neither, a
// file's dark backgroundColor gets a light title. The state and activity titles were black.
void test_title_color_follows_skinparams() {
    string[] bodies = {
        "[*] --> Idle : Start",
        "class Idle\nclass Busy\nIdle --> Busy",
        "component Idle\ncomponent Busy\nIdle --> Busy",
        "object Idle\nobject Busy\nIdle --> Busy",
        "actor Idle\nusecase Busy\nIdle --> Busy",
        "start\n:Idle;\nstop"
    };
    foreach (string body in bodies) {
        string head = "@startuml\nskinparam backgroundColor #1e1e1e\n";
        string dflt = engine_dot(head + "skinparam DefaultFontColor #ffffff\ntitle My Title\n" + body + "\n@enduml");
        assert(dflt.contains("\n  fontcolor=\"#ffffff\";"));

        string titled = engine_dot(head + "skinparam DefaultFontColor #ffffff\nskinparam titleFontColor #ff8800\ntitle My Title\n" + body + "\n@enduml");
        assert(titled.contains("\n  fontcolor=\"#ff8800\";"));

        string bg_only = engine_dot(head + "title My Title\n" + body + "\n@enduml");
        assert(bg_only.contains("\n  fontcolor=\"#FFFFFF\";"));
    }

    // A composite state's label keeps a colour readable on its own fill, not the title's
    string composite = engine_dot("@startuml\nskinparam titleFontColor #ff8800\ntitle My Title\nskinparam state {\n  BackgroundColor #4682B4\n}\nstate Outer {\n  [*] --> Idle\n}\n@enduml");
    assert(composite.contains("\n    fontcolor=\"#FFFFFF\";"));
}

// "== Title ==" dividers were parsed and thrown away; autonumber was ignored.
void test_sequence_dividers_and_autonumber() {
    string dot = engine_dot("""@startuml
participant A
participant B
autonumber
== Setup ==
A -> B : hello
B --> A : ack
autonumber stop
A -> B : unnumbered
@enduml""");
    assert(dot.contains(">Setup</FONT>"));
    // the divider row lies between the heads and the first message
    assert(seq_pos_y(dot, "_seq_div0") > seq_pos_y(dot, "A_top"));
    assert(seq_pos_y(dot, "_seq_div0") < seq_pos_y(dot, "A_m0"));
    // the number is bold by default, in its own cell before the text (PlantUML's "<b>0</b>")
    assert(dot.contains("<TD><b>1</b></TD><TD WIDTH=\"4\"></TD><TD BALIGN=\"LEFT\">hello</TD>"));
    assert(dot.contains("<TD><b>2</b></TD><TD WIDTH=\"4\"></TD><TD BALIGN=\"LEFT\">ack</TD>"));
    assert(dot.contains("label=\"  unnumbered  \""));
}

// Class diagrams dropped packages; their classes were drawn loose.
void test_class_packages_draw_clusters() {
    string dot = engine_dot("""@startuml
class Top
package "Group A" #DDDDDD {
  class Inner
  package Nested {
    class Deep
  }
}
Top --> Inner
@enduml""");
    int pkg = dot.index_of("subgraph cluster_pkg0 {");
    int nested = dot.index_of("subgraph cluster_pkg1 {");
    assert(pkg >= 0 && nested > pkg);
    assert(dot.contains("label=\"Group A\";"));
    assert(dot.contains("fillcolor=\"#DDDDDD\";"));
    assert(dot.index_of("Inner [label=") > pkg);
    assert(dot.index_of("Deep [label=") > nested);
    assert(dot.index_of("Top [label=") < pkg);
}

const string STYLE_SOURCE = """@startuml
<style>
componentDiagram {
  component {
    BackgroundColor #123456
    LineColor #ABCDEF
  }
  note { FontColor #654321 }
}
document { BackgroundColor #0A0B0C }
</style>
component [Comp] as C
note right of C : hi
@enduml""";

// <style> blocks were skipped by the lexer; they now become skinparams.
void test_style_block_is_applied() {
    string dot = engine_dot(STYLE_SOURCE);
    assert(dot.contains("bgcolor=\"#0A0B0C\""));
    assert(dot.contains("fillcolor=\"#123456\", color=\"#ABCDEF\""));
    assert(dot.contains("fontcolor=\"#654321\""));
    // The translation keeps later line numbers stable
    string processed = new Preprocessor().process(STYLE_SOURCE, null);
    string marker = "component [Comp] as C";
    assert(processed.contains("skinparam componentBackgroundColor #123456"));
    assert(count_substr(processed.substring(0, processed.index_of(marker)), "\n") ==
           count_substr(STYLE_SOURCE.substring(0, STYLE_SOURCE.index_of(marker)), "\n"));
}

// =====================================================================
// Gradient fills ("#red-green", "AntiqueWhite/Gold"): only the first colour was drawn.
// PlantUML 1.2026.1 directions: "|" left→right (Graphviz gradientangle 0), "-" top→bottom
// (270), "/" top-left→bottom-right (315), "\" bottom-left→top-right (45).

// The DOT line (stripped) that starts with `prefix`, or fails the test
string dot_line(string label, string dot, string prefix) {
    foreach (string line in dot.split("\n")) {
        if (line.strip().has_prefix(prefix)) {
            return line.strip();
        }
    }
    stderr.printf("[%s] no line starting with '%s':\n%s\n", label, prefix, dot);
    assert_not_reached();
}

void assert_dot_has(string label, string dot, string needle) {
    if (!dot.contains(needle)) {
        stderr.printf("[%s] missing '%s' in:\n%s\n", label, needle, dot);
        assert_not_reached();
    }
}

void test_gradient_class_example() {
    string dot = engine_dot("""@startuml
skinparam backgroundcolor AntiqueWhite/Gold
skinparam classBackgroundColor Wheat|CornflowerBlue

class Foo #red-green
note left of Foo #blue\9932CC
   this is my
   note on this class
end note

package example #GreenYellow/LightGoldenRodYellow {
   class Dummy
}
@enduml""");
    // Canvas
    assert_dot_has("canvas", dot, "  bgcolor=\"AntiqueWhite:Gold\";\n  gradientangle=315;\n");
    // classBackgroundColor default
    assert_dot_has("class default", dot_line("class default", dot, "node ["),
                   "fillcolor=\"Wheat:CornflowerBlue\", gradientangle=0");
    // Inline class colour
    assert_dot_has("class", dot_line("class", dot, "Foo ["), "fillcolor=\"red:green\", gradientangle=270");
    // Note: its own fill, the colour no longer part of the text
    string note = dot_line("note", dot, "_class_note_");
    assert_dot_has("note", note, "fillcolor=\"blue:#9932CC\", gradientangle=45");
    assert(!note.contains("9932CC\\n"));
    // Package cluster: fill plus its own angle (clusters inherit the canvas angle), and
    // the second colour no longer in the name
    assert_dot_has("package", dot, "fillcolor=\"GreenYellow:LightGoldenRodYellow\";\n    gradientangle=315;\n");
    assert_dot_has("package", dot, "label=\"example\";");
    // Borders and edges keep one colour
    assert(!dot.contains(" color=\"red:green\"") && !dot.contains("fontcolor=\"red:green\""));
}

void test_gradient_component_state_object_usecase() {
    string comp = engine_dot("@startuml\nskinparam backgroundColor white|gray\ncomponent [Heater] as H #red-green\nnode Box #red|green {\n  component C\n}\nnote right of H #red/green\n  hot\nend note\n@enduml");
    assert_dot_has("component canvas", comp, "bgcolor=\"white:gray\";\n  gradientangle=0;\n");
    assert_dot_has("component", dot_line("component", comp, "H ["), "fillcolor=\"red:green\", gradientangle=270");
    assert_dot_has("component cluster", comp, "fillcolor=\"red:green\";\n");
    assert_dot_has("component cluster", comp, "gradientangle=0;\n");
    assert_dot_has("component note", dot_line("component note", comp, "_component_note_"),
                   "fillcolor=\"red:green\", gradientangle=315");

    string state = engine_dot("@startuml\n[*] --> Busy\nstate Busy #red\\green\nstate Outer #red|green {\n  state Inner\n}\n@enduml");
    assert_dot_has("state", dot_line("state", state, "Busy ["), "fillcolor=\"red:green\", gradientangle=45");
    assert_dot_has("state composite", state, "bgcolor=\"red:green\";\n    gradientangle=0;\n");

    string obj = engine_dot("@startuml\nobject o #red-green\nobject m\n@enduml");
    assert_dot_has("object", dot_line("object", obj, "o ["), "fillcolor=\"red:green\", gradientangle=270");
    assert(!dot_line("object plain", obj, "m [").contains("gradientangle"));

    string uc = engine_dot("@startuml\nusecase (Login) #red/green\n@enduml");
    assert_dot_has("usecase", dot_line("usecase", uc, "Login ["), "fillcolor=\"red:green\", gradientangle=315");
}

// ---- Activity inline colours ----
// The Lexer reads "#pink", "#FF0000" and "#red/white" as ONE IDENTIFIER, but the
// activity parsers only looked for a separate HASH token, so the colours were lost.

// A coloured action keeps its colour, and "point!;" no longer swallows the next action
// (a "!" anywhere was lexed as a preprocessor line).
void test_activity_inline_color_action() {
    string dot = engine_dot("""@startuml
start
:starting progress;
#HotPink:reading configuration files
These files should be edited at this point!;
#AAAAAA:ending of the process;
@enduml""");
    string pink = dot_line("pink action", dot, "node2 [");
    assert_dot_has("pink action", pink, "fillcolor=\"HotPink\"");
    assert_dot_has("pink action", pink, "These files should be edited at this point!</td>");
    string grey = dot_line("grey action", dot, "node3 [");
    assert_dot_has("grey action", grey, "fillcolor=\"#AAAAAA\"");
    assert_dot_has("grey action", grey, "<td>ending of the process</td>");
    assert_dot_has("edge", dot, "node2 -> node3;");
    // Dark text on the light fills, not the dark theme's light node font
    assert_dot_has("pink action font", pink, "fontcolor=\"#000000\"");
    assert_dot_has("grey action font", grey, "fontcolor=\"#000000\"");
}

// kill/detach end a branch with no symbol and no arrow, and the next
// statement goes below the whole if (PlantUML 1.2026.1)
void test_activity_structure_kill() {
    string dot = engine_dot("@startuml\nif (condition?) then\n  #pink:error;\n  kill\nendif\n#palegreen:action;\n@enduml");
    assert_dot_has("kill node", dot_line("kill node", dot, "node2 ["), "style=\"invis\"");
    assert(!dot.contains("label=\"X\""));
    assert_dot_has("arrow into kill", dot, "node1 -> node2 [style=\"invis\"];");
    assert_dot_has("rank below kill", dot, "node2 -> node3 [style=\"invis\"];");
    // The "no" path of an if without else leaves the diamond's no-branch port
    assert_dot_has("no-branch edge", dot, "node0:se -> node3;");

    string det = engine_dot("@startuml\nif (c?) then\n  :a;\n  detach\nendif\n:b;\n@enduml");
    assert_dot_has("rank below detach", det, "node2 -> node3 [style=\"invis\"];");
}

// An empty "else (yes)" leaves one edge from the condition, not two
void test_activity_structure_empty_else() {
    string dot = engine_dot("@startuml\nstart\nif (c?) then (no)\n  :a;\n  stop\nelse (yes)\nendif\n:b;\n@enduml");
    string cond_id = "";
    string b_id = "";
    foreach (string line in dot.split("\n")) {
        if (line.contains("shape=hexagon")) cond_id = line.strip().split(" ")[0];
        if (line.contains("<td>b</td>")) b_id = line.strip().split(" ")[0];
    }
    assert(cond_id != "" && b_id != "");
    // The edge leaves the no-branch port and carries the else label
    assert(count_substr(dot, "%s -> %s".printf(cond_id, b_id)) + count_substr(dot, "%s:se -> %s".printf(cond_id, b_id)) == 1);
}

// "|a1| First Lane" titles the lane; "|a1|" later reuses it
void test_activity_structure_swimlane_title() {
    string dot = engine_dot("@startuml\n|a1| First Lane\nstart\n:one;\n|a2| Second\n:two;\n|a1|\n:three;\nstop\n@enduml");
    assert_dot_has("title", dot, "label=\"First Lane\";");
    assert_dot_has("title", dot, "label=\"Second\";");
    assert(!dot.contains("label=\"a1\";"));
    assert(count_substr(dot, "subgraph cluster") == 2);
    int lane = dot.index_of("label=\"First Lane\";");
    int three = dot.index_of("<td>three</td>");
    int second = dot.index_of("label=\"Second\";");
    assert(lane < three && three < second);
}

// group draws a frame (old "end group" and braced forms), nested inside an
// enclosing partition
void test_activity_structure_group() {
    string old_form = engine_dot("@startuml\nstart\ngroup Init\n  :load config;\nend group\n:done;\nstop\n@enduml");
    int init = old_form.index_of("label=\"Init\";");
    assert(init >= 0);
    int load = old_form.index_of("<td>load config</td>");
    int close = old_form.index_of("\n  }\n", init);
    assert(init < load && load < close);
    assert(old_form.index_of("<td>done</td>") > close);

    // A stray "}" in an unbraced group used to hang the parser
    string stray = engine_dot("@startuml\nstart\ngroup Init\n  :x;\n}\n:y;\nstop\n@enduml");
    assert_dot_has("stray brace", stray, "<td>x</td>");

    string nested = engine_dot("@startuml\nstart\npartition Outer {\n  group Inner {\n    :x;\n  }\n  :y;\n}\ngroup #LightBlue Tail {\n  :z;\n}\nstop\n@enduml");
    assert_dot_has("nested", nested, "  subgraph cluster_0 {\n    label=\"Outer\";");
    assert_dot_has("nested", nested, "    subgraph cluster_1 {\n      label=\"Inner\";");
    assert_dot_has("tail", nested, "  subgraph cluster_2 {\n    label=\"Tail\";");
    assert_dot_has("tail colour", nested, "fillcolor=\"LightBlue\";");
    // Outer's own nodes come first, then the nested cluster
    int outer = nested.index_of("label=\"Outer\";");
    int inner = nested.index_of("label=\"Inner\";");
    int x = nested.index_of("<td>x</td>");
    int y = nested.index_of("<td>y</td>");
    int inner_close = nested.index_of("\n    }\n", inner);
    int tail = nested.index_of("label=\"Tail\";");
    assert(outer < y && y < inner && inner < x && x < inner_close && inner_close < tail);
    assert(nested.index_of("<td>z</td>") > tail);
}

// PlantUML draws branch labels only when written: no default yes/no on
// if, elseif, else, while or repeat
void test_activity_structure_default_labels() {
    string dot = engine_dot("@startuml\nstart\nif (a?) then\n  :A;\nelseif (b?) then\n  :B;\nelse\n  :C;\nendif\nwhile (more?)\n  :W;\nendwhile\nrepeat\n  :R;\nrepeat while (again?)\nstop\n@enduml");
    assert(!dot.contains("label=\"yes\""));
    assert(!dot.contains("label=\"no\""));

    string labelled = engine_dot("@startuml\nstart\nif (a?) then (ok)\n  :A;\nelse (bad)\n  :C;\nendif\nrepeat\n  :R;\nrepeat while (again?) is (retry) not (done)\nstop\n@enduml");
    assert_dot_has("then label", labelled, "label=\"ok\"");
    assert_dot_has("else label", labelled, "label=\"bad\"");
    assert_dot_has("repeat label", labelled, "label=\"retry\"");
    assert_dot_has("repeat exit label", labelled, "label=\"done\"");
}

// Swimlanes are side-by-side full-height columns in declaration order, and
// a repeat condition stays in its lane
void test_activity_structure_swimlane_columns() {
    string dot = engine_dot("@startuml\n|Customer|\nstart\n:Place order;\n|#AntiqueWhite|Shop|\n:Check stock;\nrepeat\n  :Charge card;\nrepeat while (declined?) is (retry)\n|Customer|\n:Receive parcel;\nstop\n@enduml");
    assert_dot_has("rank tops", dot, "{ rank=same; lane_top_0; lane_top_1; }");
    assert_dot_has("rank bottoms", dot, "{ rank=same; lane_bottom_0; lane_bottom_1; }");
    assert_dot_has("lane order", dot, "lane_top_0 -> lane_top_1 [style=invis];");

    int customer = dot.index_of("label=\"Customer\";");
    int shop = dot.index_of("label=\"Shop\";");
    assert(customer >= 0 && customer < shop);
    string customer_cluster = dot.substring(customer, dot.index_of("\n  }\n", customer) - customer);
    string shop_cluster = dot.substring(shop, dot.index_of("\n  }\n", shop) - shop);
    assert_dot_has("customer column", customer_cluster, "labeljust=c;");
    assert_dot_has("customer column", customer_cluster, "style=solid;");
    assert_dot_has("customer column", customer_cluster, "lane_top_0 [");
    assert_dot_has("customer column", customer_cluster, "<td>Receive parcel</td>");
    assert_dot_has("shop colour", shop_cluster, "fillcolor=\"AntiqueWhite\";");
    // Titles are Sans and readable on the lane fill, not Graphviz's black serif
    assert_dot_has("shop title", shop_cluster, "fontname=\"Sans\";");
    assert_dot_has("shop title", shop_cluster, "fontcolor=\"#000000\";");
    assert_dot_has("shop column", shop_cluster, "lane_bottom_1 [");
    assert_dot_has("repeat condition in lane", shop_cluster, "label=\"declined?\"");

    // An elseif condition stays in the lane of its if
    string elseif_dot = engine_dot("@startuml\n|L1|\nstart\n|L2|\nif (a?) then\n  :x;\nelseif (b?) then\n  :y;\nendif\nstop\n@enduml");
    int l2 = elseif_dot.index_of("label=\"L2\";");
    assert(l2 >= 0);
    string l2_cluster = elseif_dot.substring(l2, elseif_dot.index_of("\n  }\n", l2) - l2);
    assert_dot_has("elseif in lane", l2_cluster, "label=\"b?\"");

    // Each lane's nodes hang between its anchors
    string place_id = "";
    foreach (string line in dot.split("\n")) {
        if (line.contains("<td>Place order</td>")) place_id = line.strip().split(" ")[0];
    }
    assert_dot_has("top anchor edge", dot, "lane_top_0 -> %s [style=invis, weight=0];".printf(place_id));
    assert_dot_has("bottom anchor edge", dot, "%s -> lane_bottom_0 [style=invis, weight=0];".printf(place_id));
}

// A repeat starts at a diamond (unless "repeat :label;" names a start action
// on the same line), loops back up the right side and exits straight down
// with no second diamond
void test_activity_structure_repeat_diamond() {
    string dot = engine_dot("@startuml\nstart\n:a;\nrepeat\n  :R;\nrepeat while (again?)\nstop\n@enduml");
    assert(count_substr(dot, "shape=diamond") == 1);
    assert_dot_has("start diamond", dot, "node2 [shape=diamond");
    assert_dot_has("body", dot, "node1 -> node2;");
    assert_dot_has("body", dot, "node2 -> node3;");
    assert_dot_has("loop back", dot, "node4:e -> node2:e [constraint=false];");
    assert_dot_has("exit", dot, "node4:s -> node5 [arrowhead=none];");
    assert_dot_has("pass-through", dot, "node5 [shape=point, style=invis");
    // The loop-back must not rank the condition level with the node before the loop
    assert(!dot.contains("rank=same; node1; node4;"));

    string labelled = engine_dot("@startuml\nstart\nrepeat :first;\n  :R;\nrepeat while (again?)\nstop\n@enduml");
    assert(count_substr(labelled, "shape=diamond") == 0);
    assert_dot_has("start action", labelled, "node3:e -> node1:e [constraint=false];");

    // A break adds a second way into the exit, which keeps its diamond
    string with_break = engine_dot("@startuml\nstart\nrepeat\n  if (stop?) then\n    break\n  endif\n  :R;\nrepeat while (again?)\nstop\n@enduml");
    assert(count_substr(with_break, "shape=diamond") == 2);
}

// Edge labels on a coloured lane contrast with its fill; on the theme
// background they keep the theme colour
void test_activity_structure_lane_label_contrast() {
    string dot = engine_dot("@startuml\n|Plain|\nstart\nif (x?) then (left)\n  :a;\nelse (right)\n  :b;\nendif\n|#AntiqueWhite|Shop|\nrepeat\n  :Charge;\nrepeat while (declined?) is (retry)\nstop\n@enduml");
    string retry = "";
    string left = "";
    foreach (string line in dot.split("\n")) {
        if (line.contains("label=\"retry\"")) retry = line;
        if (line.contains("label=\"left\"")) left = line;
    }
    assert_dot_has("label on beige lane", retry, "fontcolor=\"#000000\"");
    assert(left != "" && !left.contains("fontcolor"));
}

// A gradient action gets the colour list and the separator's angle
void test_activity_inline_color_gradient() {
    string dot = engine_dot("@startuml\nstart\n#blue\\green:testActivity;\n#FF0000|00FF00:hex;\n#red-green:dash;\n@enduml");
    assert_dot_has("backslash", dot_line("backslash", dot, "node1 ["), "fillcolor=\"blue:green\"");
    assert_dot_has("backslash", dot_line("backslash", dot, "node1 ["), "gradientangle=45");
    assert_dot_has("hex", dot_line("hex", dot, "node2 ["), "fillcolor=\"#FF0000:#00FF00\"");
    assert_dot_has("hex", dot_line("hex", dot, "node2 ["), "gradientangle=0");
    assert_dot_has("dash", dot_line("dash", dot, "node3 ["), "fillcolor=\"red:green\"");
    assert_dot_has("dash", dot_line("dash", dot, "node3 ["), "gradientangle=270");
}

// A coloured partition is drawn as a filled cluster around its actions (colour before
// or after the name); "partition #red/white Name {" was not drawn at all.
void test_activity_inline_color_partition() {
    string dot = engine_dot("@startuml\nstart\npartition #red/white testPartition {\n  #blue\\green:testActivity;\n}\npartition P3 #yellow {\n  :in p3;\n}\n@enduml");
    assert_dot_has("gradient partition", dot,
                   "label=\"testPartition\";\n    style=filled;\n    fillcolor=\"red:white\";\n    gradientangle=315;\n    color=\"red\";\n");
    int cluster = dot.index_of("label=\"testPartition\"");
    int action = dot.index_of("<td>testActivity</td>");
    int end = dot.index_of("\n  }\n", cluster);
    assert(cluster >= 0 && action > cluster && action < end);
    assert_dot_has("named partition", dot, "label=\"P3\";\n    style=filled;\n    fillcolor=\"yellow\";\n    color=\"yellow\";\n");
    assert(!dot.contains("\"#red"));
}

// Swimlane "|#pink|Name|" (lexed as the gradient-looking "#pink|Name"), a note colour
// and a "#color:if" condition
void test_activity_inline_color_swimlane_note_if() {
    string dot = engine_dot("@startuml\n|#pink|Actor|\nstart\n#pink:if (x?) then (yes)\n  :a;\nendif\n|#AAFFAA|Two|\n:two;\nnote right #orange: coloured note\n@enduml");
    assert_dot_has("swimlane", dot, "label=\"Actor\";\n    labeljust=c;\n    fontsize=16;\n    style=filled;\n    fillcolor=\"pink\";\n");
    assert_dot_has("hex swimlane", dot, "label=\"Two\";\n    labeljust=c;\n    fontsize=16;\n    style=filled;\n    fillcolor=\"#AAFFAA\";\n");
    assert(!dot.contains("#pink|"));
    assert_dot_has("if", dot, "shape=hexagon, style=\"filled\", fillcolor=\"pink\", label=\"x?\"");
    assert_dot_has("note", dot, "fillcolor=\"orange\", fontcolor=\"#000000\", label=\"coloured note\"");
}

int main(string[] args) {
    Test.init(ref args);

    Test.add_func("/puml/class",               test_class_diagram_snapshot);
    Test.add_func("/puml/component_c4",        test_component_c4_snapshot);
    Test.add_func("/puml/activity",            test_activity_diagram_snapshot);
    Test.add_func("/puml/state",               test_state_diagram_snapshot);
    Test.add_func("/puml/er",                  test_er_diagram_snapshot);
    Test.add_func("/puml/sequence",            test_sequence_diagram_snapshot);
    Test.add_func("/puml/usecase",             test_usecase_diagram_snapshot);
    Test.add_func("/puml/object",              test_object_diagram_snapshot);
    Test.add_func("/puml/deployment",          test_deployment_diagram_snapshot);
    Test.add_func("/puml/mindmap",             test_mindmap_diagram_snapshot);
    Test.add_func("/puml/archimate",           test_archimate_diagram_snapshot);
    Test.add_func("/puml/json",                test_json_diagram_snapshot);
    Test.add_func("/puml/yaml",                test_yaml_diagram_snapshot);
    Test.add_func("/puml/gantt",               test_gantt_diagram_snapshot);
    Test.add_func("/puml/timing",              test_timing_diagram_snapshot);
    Test.add_func("/puml/nwdiag",              test_nwdiag_diagram_snapshot);
    Test.add_func("/puml/chronology",          test_chronology_diagram_snapshot);
    Test.add_func("/puml/palette_integration", test_plantuml_palette_integration);

    // Note legibility + style-block regressions
    Test.add_func("/puml/note/font_contrast",    test_note_font_contrasts_with_fill);
    Test.add_func("/puml/note/font_skinparam",   test_note_font_color_skinparam_honoured);
    Test.add_func("/puml/note/cluster_anchor",   test_note_on_container_uses_cluster_anchor);
    Test.add_func("/puml/note/style_block",      test_style_block_is_skipped_not_parsed);
    Test.add_func("/puml/note/bare_end_word",    test_note_body_keeps_bare_end_word);

    // State-diagram colour + markup parity with the component renderer
    Test.add_func("/puml/state/stereotype_bg",   test_state_background_per_stereotype);
    Test.add_func("/puml/state/inline_color",    test_state_inline_color);
    Test.add_func("/puml/state/edge_creole",     test_state_edge_label_strips_creole);

    // 2026-09-14: include base path, description blocks, theme blocks, Creole
    Test.add_func("/puml/include/document_file_base", test_include_resolves_against_document_file);
    Test.add_func("/puml/state/description_block",    test_state_description_block_is_simple_state);
    Test.add_func("/puml/state/theme_skinparam",      test_state_theme_skinparam_blocks_do_not_create_states);
    Test.add_func("/puml/state/note_composite_anchor", test_state_note_on_composite_uses_anchor);
    Test.add_func("/puml/edge/leading_less_than",     test_edge_label_keeps_leading_less_than);
    Test.add_func("/puml/note/body_bold",             test_note_body_strips_bold_markup);
    Test.add_func("/puml/theme/canvas_not_fill",      test_element_fill_does_not_inherit_canvas_background);

    // 2026-09-14 round 2
    Test.add_func("/puml/theme/no_element_ghosts",     test_theme_blocks_create_no_elements);
    Test.add_func("/puml/class/trailing_static",       test_class_trailing_static_keeps_members);
    Test.add_func("/puml/class/note_of",               test_class_note_of_attaches);
    Test.add_func("/puml/component/labels_storage_arrows", test_component_labels_storage_arrows);
    Test.add_func("/puml/sequence/theme_and_notes",    test_sequence_theme_and_notes);
    Test.add_func("/puml/sequence/row_order",          test_sequence_rows_follow_source_order);

    // 2026-09-14 round 3
    Test.add_func("/puml/label/source_spacing",         test_labels_keep_source_spacing);
    Test.add_func("/puml/component/note_lines_color",   test_component_note_lines_and_color);
    Test.add_func("/puml/state/nested_outer_target",    test_state_nested_transition_targets_outer_state);
    Test.add_func("/puml/state/composite_edge_border",  test_state_composite_edges_clip_at_border);
    Test.add_func("/puml/scale_line_makes_no_element",  test_scale_line_makes_no_element);
    Test.add_func("/puml/floating_note_alias_forms",    test_floating_note_alias_forms);
    Test.add_func("/puml/floating_note_alias_links",    test_floating_note_alias_links);
    Test.add_func("/puml/edge_label_color_skinparams",  test_edge_label_color_follows_skinparams);
    Test.add_func("/puml/title_color_skinparams",       test_title_color_follows_skinparams);
    Test.add_func("/puml/edge_line_color_skinparams",   test_edge_line_color_follows_skinparams);
    Test.add_func("/puml/component_node_stereo_mindmap_arrow", test_component_node_stereotype_and_mindmap_arrow);
    Test.add_func("/puml/fill_text_contrast_nested_node", test_fill_text_contrast_and_nested_node);
    Test.add_func("/puml/label_title_color_er_deploy_mindmap", test_label_and_title_color_er_deployment_mindmap);
    Test.add_func("/puml/sequence/dividers_autonumber", test_sequence_dividers_and_autonumber);
    Test.add_func("/puml/class/packages",               test_class_packages_draw_clusters);
    Test.add_func("/puml/style/applied",                test_style_block_is_applied);
    Test.add_func("/puml/label/source_spacing_activity", test_activity_mindmap_keep_source_spacing);
    Test.add_func("/puml/class/package_relationship_members", test_class_package_relationship_members);

    // 2026-09-14 round 4
    Test.add_func("/puml/activity/html_escaped_text",        test_activity_action_text_is_html_escaped);
    Test.add_func("/puml/class/single_dash_arrows",          test_class_single_dash_arrows);
    Test.add_func("/puml/class/composition_marker_side",     test_class_composition_marker_side);
    Test.add_func("/puml/class/plain_single_links",          test_class_plain_single_links);
    Test.add_func("/puml/class/package_to_package_link",     test_class_package_to_package_link);
    Test.add_func("/puml/class/left_to_right",               test_class_left_to_right_direction);
    Test.add_func("/puml/component/container_edge_border",   test_component_container_edges_clip_at_border);
    Test.add_func("/puml/deployment/container_edge_border",  test_deployment_container_edges_clip_at_border);
    Test.add_func("/puml/class/link_cardinality",            test_class_link_cardinality_is_not_a_class);
    Test.add_func("/puml/class/dash_word_arrow_no_ghost",    test_class_dash_word_arrow_makes_no_ghost);

    // 2026-09-14 round 5
    Test.add_func("/puml/class/double_dash_solid",            test_class_double_dash_arrow_is_solid);
    Test.add_func("/puml/class/direction_option_arrows",      test_class_direction_and_option_arrows);
    Test.add_func("/puml/class/association_diamond",          test_class_association_diamond);
    Test.add_func("/puml/deployment/device_keyword",          test_deployment_device_keyword);
    Test.add_func("/puml/detect/sequence_usecase_shorthand",  test_detect_sequence_and_usecase_shorthand);
    Test.add_func("/puml/detect/component_note_parens",       test_detect_component_with_parenthesised_note_line);

    // 2026-09-14 round 6
    Test.add_func("/puml/class/qualified_name_namespace",     test_class_qualified_name_goes_into_namespace);
    Test.add_func("/puml/class/namespace_resolution",         test_class_namespace_name_resolution);
    Test.add_func("/puml/detect/indented_class",              test_detect_indented_class_declaration);
    Test.add_func("/puml/detect/description_diagram",         test_detect_description_diagram_as_component);
    Test.add_func("/puml/component/actor_usecase_shorthand",  test_component_actor_usecase_shorthand);
    Test.add_func("/puml/component/decorated_arrows",         test_component_decorated_arrows);
    Test.add_func("/puml/component/element_keywords_names",   test_component_element_keywords_as_names);
    Test.add_func("/puml/render/dot_keyword_ids",             test_dot_keyword_names_get_safe_ids);
    Test.add_func("/puml/component/double_dash_solid",        test_component_double_dash_arrow_is_solid);
    Test.add_func("/puml/deployment/double_dash_solid",       test_deployment_double_dash_arrow_is_solid);

    // 2026-09-14 round 7
    Test.add_func("/puml/state/double_dash_solid",            test_state_double_dash_arrow_is_solid);
    Test.add_func("/puml/usecase/double_dash_solid",          test_usecase_double_dash_arrow_is_solid);
    Test.add_func("/puml/object/link_arrows",                 test_object_link_arrows);
    Test.add_func("/puml/sequence/participant_stereotype_label", test_seq_participant_stereotype_label);
    Test.add_func("/puml/sequence/participant_stereotype_multiword", test_seq_participant_stereotype_multiword);
    Test.add_func("/puml/sequence/participant_stereotype_split_tokens", test_seq_participant_stereotype_split_tokens);
    Test.add_func("/puml/sequence/participant_spot_stereotype", test_seq_participant_spot_stereotype);
    Test.add_func("/puml/sequence/participant_stereotype_skinparam_colors", test_seq_participant_stereotype_skinparam_colors);
    Test.add_func("/puml/sequence/participant_stereotype_global_skinparam", test_seq_participant_stereotype_global_skinparam);
    Test.add_func("/puml/sequence/participant_style_element_selector_ignored", test_seq_participant_style_element_selector_ignored);
    Test.add_func("/puml/sequence/participant_style_bare_selector_applied", test_seq_participant_style_bare_selector_applied);
    Test.add_func("/puml/state/description_keeps_quotes",     test_state_description_keeps_quotes);
    Test.add_func("/puml/state/transition_label_keeps_quotes", test_state_transition_label_keeps_quotes);
    Test.add_func("/puml/state/note_keeps_quotes",            test_state_note_keeps_quotes);
    Test.add_func("/puml/sequence/participant_stereotype_no_guillemet", test_seq_participant_stereotype_no_guillemet);
    Test.add_func("/puml/sequence/participant_stereotype_position_bottom", test_seq_participant_stereotype_position_bottom);
    Test.add_func("/puml/state/floating_note_without_quotes", test_state_floating_note_without_quotes);
    Test.add_func("/puml/state/composite_multiline_description", test_state_composite_multiline_description);
    Test.add_func("/puml/state/nested_composite_reuses_state", test_state_nested_composite_reuses_existing_state);
    Test.add_func("/puml/object/keyword_map_alias_id",        test_object_keyword_map_alias_id);
    Test.add_func("/puml/object/keyword_word_alias",          test_object_keyword_word_alias);
    Test.add_func("/puml/object/quoted_dotted_name",          test_object_quoted_dotted_name_not_packaged);
    Test.add_func("/puml/object/colliding_ids_unique",        test_object_colliding_ids_unique);
    Test.add_func("/puml/object/bidirectional_arrow",         test_object_bidirectional_arrow);
    Test.add_func("/puml/object/arrow_bracket_options",       test_object_arrow_bracket_options);
    Test.add_func("/puml/mindmap/bracket_color",              test_mindmap_bracket_color);
    Test.add_func("/puml/object/maps_row_links",              test_object_maps_and_row_links);
    Test.add_func("/puml/object/packages_and_maps",           test_object_packages_and_maps);
    Test.add_func("/puml/detect/object_diagrams",             test_detect_object_diagrams);
    Test.add_func("/puml/component/interface_small_circle",   test_component_interface_small_circle);
    Test.add_func("/puml/class/dotted_packages_nest",         test_class_dotted_packages_nest);
    Test.add_func("/puml/object/dotted_names_packages",       test_object_dotted_names_get_packages);
    Test.add_func("/puml/class/reversed_arrow_order",         test_class_reversed_arrow_keeps_written_order);
    Test.add_func("/puml/object/reversed_arrow_order",        test_object_reversed_arrow_keeps_written_order);

    // 2026-09-14 round 8
    Test.add_func("/puml/class/aggregation_marker_shapes",    test_class_aggregation_marker_shapes);
    Test.add_func("/puml/class/cardinality_labels_offset",    test_class_cardinality_labels_offset);
    Test.add_func("/puml/style/stereotype_selectors",         test_style_stereotype_selectors);
    Test.add_func("/puml/style/depth_selectors",              test_style_depth_selectors);

    // 2026-09-15 round 9
    Test.add_func("/puml/component/stereotype_inside_label",  test_component_stereotype_inside_label);
    Test.add_func("/puml/component/nested_interface_once",    test_component_nested_interface_emitted_once);
    Test.add_func("/puml/component/keyword_alias_container",  test_component_keyword_alias_container);
    Test.add_func("/puml/er/keyword_alias",                   test_er_keyword_alias);
    Test.add_func("/puml/er/crows_foot_links",                test_er_crows_foot_links);
    Test.add_func("/puml/sequence/one_line_skinparam_block_keeps_messages", test_seq_one_line_skinparam_block_keeps_messages);
    Test.add_func("/puml/sequence/divider_title_quotes_and_creole", test_seq_divider_title_quotes_and_creole);
    Test.add_func("/puml/class/plus_cross_markers_svg",       test_class_plus_cross_markers_svg);
    Test.add_func("/puml/class/same_named_nested_packages",   test_class_same_named_nested_packages);
    Test.add_func("/puml/usecase/reverse_dotted_arrow",       test_usecase_reverse_dotted_arrow);
    Test.add_func("/puml/usecase/frame_container",            test_usecase_frame_container);
    Test.add_func("/puml/usecase/link_inside_container",      test_usecase_link_inside_container);
    Test.add_func("/puml/usecase/paren_statement_top_level",  test_usecase_paren_statement_top_level);
    Test.add_func("/puml/usecase/undirected_links",           test_usecase_undirected_links);
    Test.add_func("/puml/usecase/container_as_endpoint",      test_usecase_container_as_endpoint);
    Test.add_func("/puml/usecase/endpoints_declared_in_container", test_usecase_endpoints_declared_in_container);
    Test.add_func("/puml/usecase/paren_alias",                test_usecase_paren_alias);
    Test.add_func("/puml/usecase/colon_actor_declaration",    test_usecase_colon_actor_declaration);
    Test.add_func("/puml/usecase/colon_actor_endpoint",       test_usecase_colon_actor_endpoint);
    Test.add_func("/puml/usecase/link_inline_style",          test_usecase_link_inline_style);
    Test.add_func("/puml/usecase/stereotype_colors",          test_usecase_stereotype_colors);
    Test.add_func("/puml/usecase/stereotype_labels",          test_usecase_stereotype_labels);
    Test.add_func("/puml/usecase/business_actors",            test_usecase_business_actors);
    Test.add_func("/puml/usecase/actor_stick_figures_svg",    test_usecase_actor_stick_figures_svg);
    Test.add_func("/puml/class/member_named_o",               test_class_member_named_o);
    Test.add_func("/puml/class/member_named_star",            test_class_member_named_star);
    Test.add_func("/puml/class/namespace_reference_reuses_global", test_class_namespace_reference_reuses_global);
    Test.add_func("/puml/class/package_qualified_reference",  test_class_package_qualified_reference);
    Test.add_func("/puml/class/package_alias_link",           test_class_package_alias_link);
    Test.add_func("/puml/class/two_marker_arrows",            test_class_two_marker_arrows);
    Test.add_func("/puml/class/floating_note_alias",          test_class_floating_note_alias);
    Test.add_func("/puml/class/together_no_ghost",            test_class_together_no_ghost);
    Test.add_func("/puml/class/dotted_crowsfoot_ends",        test_class_dotted_crowsfoot_ends);
    Test.add_func("/puml/er/dotted_crowsfoot_ends",           test_er_dotted_crowsfoot_ends);
    Test.add_func("/puml/detect/deployment_elements_component", test_detect_deployment_elements_as_component);
    Test.add_func("/puml/component/end_marker_shapes",        test_component_end_marker_shapes);
    Test.add_func("/puml/component/diamond_written_end",      test_component_diamond_written_end);
    Test.add_func("/puml/detect/element_list_with_entity",    test_detect_element_list_with_entity_stays_component);
    Test.add_func("/puml/detect/actor_messages_sequence",     test_detect_actor_messages_as_sequence);
    Test.add_func("/puml/detect/actor_usecase_files",         test_detect_actor_usecase_files_stay_usecase);
    Test.add_func("/puml/sequence/actor_stick_figure",        test_sequence_actor_stick_figure);
    Test.add_func("/puml/sequence/hide_footbox",              test_sequence_hide_footbox);
    Test.add_func("/puml/sequence/actor_styles_svg",          test_sequence_actor_styles_svg);
    Test.add_func("/puml/component/side_link_keeps_containers", test_component_side_link_keeps_containers);
    Test.add_func("/puml/detect/note_text_not_declarations",  test_detect_note_text_not_declarations);
    Test.add_func("/puml/detect/activity_action_text",        test_detect_activity_action_text_not_declaration);
    Test.add_func("/puml/detect/queue_participants_sequence", test_detect_queue_participants_sequence);
    Test.add_func("/puml/detect/usecase_in_frame",            test_detect_usecase_in_frame);
    Test.add_func("/puml/detect/legacy_activity_start",       test_detect_legacy_activity_start);
    Test.add_func("/puml/detect/indented_class_association",  test_detect_indented_class_association);
    Test.add_func("/puml/detect/floating_note_usecase",       test_detect_floating_note_usecase);
    Test.add_func("/puml/component/nested_element_words",     test_component_nested_element_words);
    Test.add_func("/puml/component/glued_bracket_links",      test_component_glued_bracket_links);
    Test.add_func("/puml/component/underscore_name",          test_component_underscore_name);
    Test.add_func("/puml/class/entity_declaration",           test_class_entity_declaration);
    Test.add_func("/puml/class/crows_foot_ends",              test_class_crows_foot_ends);
    Test.add_func("/puml/class/quoted_alias_label",           test_class_quoted_alias_label);
    Test.add_func("/puml/class/remove_by_name",               test_class_remove_by_name);
    Test.add_func("/puml/class/hide_keeps_space",             test_class_hide_keeps_space);
    Test.add_func("/puml/class/remove_restore_tags",          test_class_remove_restore_tags);
    Test.add_func("/puml/class/remove_all_restore",           test_class_remove_all_restore);
    Test.add_func("/puml/class/unlinked",                     test_class_unlinked);
    Test.add_func("/puml/class/member_hide_untouched",        test_class_member_hide_untouched);
    Test.add_func("/puml/class/dollar_names",                 test_class_dollar_names);
    Test.add_func("/puml/class/keyword_alias",                test_class_keyword_alias);

    // Fuzz-style edge-case tests
    Test.add_func("/puml/fuzz/class",       test_fuzz_class_parser);
    Test.add_func("/puml/fuzz/state",       test_fuzz_state_parser);
    Test.add_func("/puml/fuzz/activity",    test_fuzz_activity_parser);
    Test.add_func("/puml/fuzz/component",   test_fuzz_component_parser);
    Test.add_func("/puml/fuzz/er",          test_fuzz_er_parser);
    Test.add_func("/puml/fuzz/usecase",     test_fuzz_usecase_parser);
    Test.add_func("/puml/fuzz/object",      test_fuzz_object_parser);
    Test.add_func("/puml/fuzz/deployment",  test_fuzz_deployment_parser);
    Test.add_func("/puml/fuzz/nwdiag",      test_fuzz_nwdiag_parser);
    Test.add_func("/puml/fuzz/archimate",   test_fuzz_archimate_parser);
    Test.add_func("/puml/fuzz/json",        test_fuzz_json_parser);
    Test.add_func("/puml/fuzz/yaml",        test_fuzz_yaml_parser);
    Test.add_func("/puml/fuzz/mindmap",     test_fuzz_mindmap_parser);
    Test.add_func("/puml/gradient/class_example", test_gradient_class_example);
    Test.add_func("/puml/gradient/component_state_object_usecase", test_gradient_component_state_object_usecase);

    // Activity inline colours
    Test.add_func("/puml/activity/inline_color/action",   test_activity_inline_color_action);
    Test.add_func("/puml/activity/structure/kill",           test_activity_structure_kill);
    Test.add_func("/puml/activity/structure/empty_else",     test_activity_structure_empty_else);
    Test.add_func("/puml/activity/structure/swimlane_title", test_activity_structure_swimlane_title);
    Test.add_func("/puml/activity/structure/group",          test_activity_structure_group);
    Test.add_func("/puml/activity/structure/default_labels",  test_activity_structure_default_labels);
    Test.add_func("/puml/activity/structure/swimlane_columns", test_activity_structure_swimlane_columns);
    Test.add_func("/puml/activity/structure/repeat_diamond",  test_activity_structure_repeat_diamond);
    Test.add_func("/puml/activity/structure/lane_label_contrast", test_activity_structure_lane_label_contrast);
    Test.add_func("/puml/activity/inline_color/gradient", test_activity_inline_color_gradient);
    Test.add_func("/puml/activity/inline_color/partition", test_activity_inline_color_partition);
    Test.add_func("/puml/activity/inline_color/swimlane_note_if", test_activity_inline_color_swimlane_note_if);

    return Test.run();
}

// A class node drawn as an HTML table: the line "id [label=<" whose header cell ends with
// the name (after the spot), holding `extra` too
bool class_box(string dot, string id, string name, string extra = "") {
    foreach (string raw in dot.split("\n")) {
        string line = raw.strip();
        if (line.has_prefix(id + " [label=<") && line.contains("&#160; " + Markup.escape_text(name) + "</TD>") &&
            line.contains(extra)) {
            return true;
        }
    }
    return false;
}
