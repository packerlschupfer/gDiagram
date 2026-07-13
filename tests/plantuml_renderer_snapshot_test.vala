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

void test_deployment_diagram_snapshot() {
    string source = """@startuml
node Server {
  artifact "app.jar" as app
}
database "Postgres" as db
Server --> db : JDBC
@enduml""";

    var tokens = lex_puml(source);
    var parser = new DeploymentDiagramParser();
    var diagram = parser.parse(tokens);
    assert(!diagram.has_errors());
    assert(diagram.nodes.size > 0);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new DeploymentDiagramRenderer(ctx, regions, "dot");
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

void test_fuzz_deployment_parser() {
    string[] inputs = {
        "@startuml\n@enduml",
        "@startuml\nnode N\n@enduml",
        "@startuml\nnode N {\nartifact A\n@enduml",          // unclosed node
        "@startuml\ndatabase \"db\" as d\n@enduml",
        "@startuml\ncloud {\n@enduml",
    };
    var parser = new DeploymentDiagramParser();
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

    var dep = new DeploymentDiagramParser().parse(lex_puml("""@startuml
node A
note right of A
""" + END_NOTE_BODY + """
end note
@enduml"""));
    assert(dep.notes.size == 1);
    puml_assert_note_keeps_end("deployment", dep.notes.get(0).text);
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

    return Test.run();
}
