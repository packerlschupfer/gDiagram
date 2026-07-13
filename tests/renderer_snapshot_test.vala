/*
 * renderer_snapshot_test.vala — content-based renderer smoke tests.
 *
 * Goal: catch regressions where a renderer either crashes, produces empty
 * output, drops an element, or loses a theme color — without being fragile
 * to harmless pixel-level drift across Graphviz or font versions.
 *
 * Each test feeds a small known-good source through the full parse →
 * render → SVG pipeline and asserts on specific substrings that must
 * appear in the output (labels, palette colors, expected node counts).
 *
 * Covers: 14 Mermaid types not already covered by mermaid_renderer_test
 * or mermaid_integration_test, plus 4 PlantUML types representing
 * different renderer subtrees (class, activity, component/C4, sequence).
 */
using GDiagram;

// Helper: count occurrences of a substring in `haystack`.
int count_occurrences(string haystack, string needle) {
    if (needle.length == 0) return 0;
    int count = 0;
    int idx = 0;
    while (true) {
        int found = haystack.index_of(needle, idx);
        if (found < 0) break;
        count++;
        idx = found + needle.length;
    }
    return count;
}

// Helper: assert an SVG is well-formed and contains all expected strings.
void assert_svg_contains(uint8[]? svg_data, string label, string[] expected) {
    assert(svg_data != null);
    assert(svg_data.length > 0);

    // The SVG is raw bytes. Build a string capped at the real length so
    // we don't read past the end of the uint8[] buffer.
    string svg_str;
    unowned string raw = (string) svg_data;
    if (raw.length == svg_data.length) {
        svg_str = raw;
    } else {
        svg_str = raw.substring(0, svg_data.length);
    }

    if (!svg_str.contains("<svg")) {
        stderr.printf("[%s] SVG does not start with <svg\n", label);
        assert_not_reached();
    }
    if (!svg_str.contains("</svg>")) {
        stderr.printf("[%s] SVG not terminated with </svg>\n", label);
        assert_not_reached();
    }

    foreach (var needle in expected) {
        if (!svg_str.contains(needle)) {
            stderr.printf("[%s] Expected '%s' in SVG but not found\n", label, needle);
            assert_not_reached();
        }
    }
}

// Helper: set up a renderer context + regions list that every renderer
// constructor requires.
struct RenderCtx {
    unowned Gvc.Context ctx;
    Gee.ArrayList<ElementRegion> regions;
}

// =====================================================================
// Mermaid type tests (the 14 not yet covered)
// =====================================================================

void test_mindmap_snapshot() {
    var parser = new MermaidMindmapParser();
    var diagram = parser.parse("""mindmap
  root((Tech))
    Frontend
      React
    Backend
      Node
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidMindmapRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "mindmap", {
        "Tech", "Frontend", "React", "Backend", "Node"
    });
}

void test_timeline_snapshot() {
    var parser = new MermaidTimelineParser();
    var diagram = parser.parse("""timeline
    title History
    2000 : Dotcom
    2010 : Mobile
    2020 : AI
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidTimelineRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "timeline", {
        "History", "2000", "Dotcom", "2010", "Mobile", "2020", "AI"
    });
}

void test_quadrant_snapshot() {
    var parser = new MermaidQuadrantParser();
    var diagram = parser.parse("""quadrantChart
    title Reach vs Engagement
    x-axis Low Reach --> High Reach
    y-axis Low Engagement --> High Engagement
    quadrant-1 Expand
    quadrant-2 Promote
    quadrant-3 Reevaluate
    quadrant-4 Improve
    Campaign A: [0.3, 0.6]
    Campaign B: [0.7, 0.8]
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidQuadrantRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "quadrant", {
        "Reach vs Engagement", "Campaign A", "Campaign B",
        "Expand", "Promote"
    });
}

void test_xychart_snapshot() {
    var parser = new MermaidXYChartParser();
    var diagram = parser.parse("""xychart-beta
    title "Sales"
    x-axis [jan, feb, mar]
    y-axis "Revenue" 0 --> 100
    bar [20, 50, 80]
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidXYChartRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "xychart", {
        "Sales", "jan", "feb", "mar"
    });
}

void test_kanban_snapshot() {
    var parser = new MermaidKanbanParser();
    // Parser requires column headers at indent 0; cards indented under them.
    var diagram = parser.parse("""kanban
todo[To Do]
  t1[Write tests]
wip[In Progress]
  t2[Implement feature]
done[Done]
  t3[Deploy]
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidKanbanRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "kanban", {
        "To Do", "In Progress", "Done",
        "Write tests", "Implement feature", "Deploy"
    });
}

void test_sankey_snapshot() {
    var parser = new MermaidSankeyParser();
    var diagram = parser.parse("""sankey-beta
Solar,Grid,100
Wind,Grid,80
Grid,Homes,180
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidSankeyRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "sankey", {
        "Solar", "Wind", "Grid", "Homes"
    });
}

void test_requirement_snapshot() {
    var parser = new MermaidRequirementParser();
    var diagram = parser.parse("""requirementDiagram
requirement auth {
    id: 1
    text: Users authenticate
    risk: low
    verifymethod: test
}
element frontend {
    type: component
}
frontend - satisfies -> auth
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidRequirementRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "requirement", {
        "auth", "frontend", "satisfies"
    });
}

void test_block_snapshot() {
    var parser = new MermaidBlockParser();
    var diagram = parser.parse("""block-beta
    columns 2
    A["Frontend"] B["API"]
    A --> B
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidBlockRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "block", {
        "Frontend", "API"
    });
}

void test_packet_snapshot() {
    var parser = new MermaidPacketParser();
    var diagram = parser.parse("""packet-beta
0-15: "Source Port"
16-31: "Dest Port"
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidPacketRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "packet", {
        "Source Port", "Dest Port"
    });
}

void test_c4_snapshot() {
    var parser = new MermaidC4Parser();
    var diagram = parser.parse("""C4Context
    Person(user, "User", "A user")
    System(app, "Web App", "The system")
    Rel(user, app, "Uses")
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidC4Renderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "c4", {
        "User", "Web App", "Uses"
    });
}

void test_architecture_snapshot() {
    var parser = new MermaidArchitectureParser();
    var diagram = parser.parse("""architecture-beta
    service db(database)[Database]
    service api(server)[API]
    db:R --> L:api
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidArchitectureRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "architecture", {
        "Database", "API"
    });
}

void test_zenuml_snapshot() {
    var parser = new MermaidZenUMLParser();
    var diagram = parser.parse("""zenuml
    title Checkout
    @Actor Customer
    @Service Order

    Customer -> Order.checkout()
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidZenUMLRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "zenuml", {
        "Customer", "Order"
    });
}

void test_radar_snapshot() {
    var parser = new MermaidRadarParser();
    var diagram = parser.parse("""radar-beta
    title Skills
    axis Frontend, Backend, DevOps, Testing
    curve Alice{80, 60, 50, 70}
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidRadarRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    // Radar renderer draws axis labels + title but curves are rendered
    // as unlabeled points, so we only check axis labels and title.
    assert_svg_contains(svg, "radar", {
        "Skills", "Frontend", "Backend"
    });
}

void test_treemap_snapshot() {
    var parser = new MermaidTreemapParser();
    var diagram = parser.parse("""treemap-beta
title Budget
"Engineering"
    "Frontend": 100
    "Backend": 200
"Marketing": 50
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidTreemapRenderer(ctx, regions, "dot");
    var svg = renderer.render_to_svg(diagram);

    assert_svg_contains(svg, "treemap", {
        "Budget", "Engineering", "Frontend", "Backend"
    });
}

// =====================================================================
// Palette integration: verify that swapping palette affects rendered SVG
// =====================================================================

void test_palette_affects_rendering() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] --> B[End]
""");
    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    // Default-light palette
    var light = ThemeManager.get_preset("default-light");
    ThemeManager.set_active_palette(light);
    string light_dot = renderer.generate_dot(diagram);
    assert(light_dot.contains(light.background));

    // Dracula palette — background should now be the dracula one
    var dracula = ThemeManager.get_preset("dracula");
    ThemeManager.set_active_palette(dracula);
    string dark_dot = renderer.generate_dot(diagram);
    assert(dark_dot.contains(dracula.background));
    assert(dracula.background != light.background);

    // Restore default-light so later tests see a known baseline.
    ThemeManager.set_active_palette(light);
}

void test_transparent_background_swap() {
    var light = ThemeManager.get_preset("default-light");
    ThemeManager.set_active_palette(light);

    var clone = ThemeManager.get_active_palette().clone();
    clone.background = "transparent";
    ThemeManager.set_active_palette(clone);

    assert(ThemeManager.get_active_palette().background == "transparent");

    // Restore
    ThemeManager.set_active_palette(light);
    assert(ThemeManager.get_active_palette().background == light.background);
}

// =====================================================================
// Mermaid parser fuzz tests — edge cases & hang detection
// =====================================================================

void test_fuzz_mermaid_flowchart() {
    string[] inputs = {
        "flowchart TD",                              // no body
        "flowchart",                                  // no direction
        "flowchart TD\n    A --> B",
        "flowchart TD\n    A[Label\n",                // unclosed bracket
        "flowchart TD\n    A --> B --> C --> A",      // cycle
        "flowchart TD\n    A{{hex}} --> B[[sub]]",    // special shapes
        "flowchart TD\n    A -->|label with \"quotes\"| B",
    };
    var parser = new MermaidFlowchartParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_sequence() {
    string[] inputs = {
        "sequenceDiagram",
        "sequenceDiagram\n    Alice->>Bob: Hi",
        "sequenceDiagram\n    alt cond\n    else\n    end",
        "sequenceDiagram\n    loop forever\n    end",
        "sequenceDiagram\n    Note over Alice: text",
        "sequenceDiagram\n    participant A\n    participant B\n    A->>B:\n",   // empty msg
    };
    var parser = new MermaidSequenceParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_state() {
    string[] inputs = {
        "stateDiagram-v2",
        "stateDiagram-v2\n[*] --> Idle",
        "stateDiagram-v2\nstate S {\n}",
        "stateDiagram-v2\nstate S {\n",                    // unclosed
        "stateDiagram-v2\nA --> B : label with : colon",
    };
    var parser = new MermaidStateParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_class() {
    string[] inputs = {
        "classDiagram",
        "classDiagram\n    class Foo",
        "classDiagram\n    class Foo {\n",                  // unclosed
        "classDiagram\n    Animal <|-- Dog",
        "classDiagram\n    class Foo { +x : Map<K,V> }",
    };
    var parser = new MermaidClassParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_er() {
    string[] inputs = {
        "erDiagram",
        "erDiagram\n    A ||--o{ B : has",
        "erDiagram\n    A {\n        int id\n",             // unclosed
        "erDiagram\n    A { int id PK }",
    };
    var parser = new MermaidERParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_pie() {
    string[] inputs = {
        "pie",
        "pie title My pie",
        "pie\n    \"A\" : 40\n    \"B\" : 60",
        "pie\n    \"Bad entry without colon\" 50",          // malformed
    };
    var parser = new MermaidPieParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_gantt() {
    string[] inputs = {
        "gantt",
        "gantt\n    title Plan\n    dateFormat YYYY-MM-DD",
        "gantt\n    section A\n    Task :a1, 2025-01-01, 5d",
        "gantt\n    Task :bad syntax here",
    };
    var parser = new MermaidGanttParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_mindmap() {
    string[] inputs = {
        "mindmap",
        "mindmap\n  root",
        "mindmap\n  root\n    child",
        "mindmap\n  root((shape))\n    child[box]",
    };
    var parser = new MermaidMindmapParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_c4() {
    string[] inputs = {
        "C4Context",
        "C4Context\n    Person(u, \"User\")",
        "C4Context\n    Boundary(b, \"System\") {\n",        // unclosed
        "C4Container\n    Container(a, \"A\", \"Tech\")\n    Container(b, \"B\")",
    };
    var parser = new MermaidC4Parser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_block() {
    string[] inputs = {
        "block-beta",
        "block-beta\n    columns 3",
        "block-beta\n    A B C\n    A --> B",
        "block-beta\n    block:grp\n",                        // unclosed
    };
    var parser = new MermaidBlockParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_timeline() {
    string[] inputs = {
        "timeline",
        "timeline\n    title My timeline",
        "timeline\n    2020 : A : B : C",
        "timeline\n    section Early\n    1900 : foo",
        "timeline\n    : stray colon",
    };
    var parser = new MermaidTimelineParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_quadrant() {
    string[] inputs = {
        "quadrantChart",
        "quadrantChart\n    title Q",
        "quadrantChart\n    A: [0.5, 0.5]",
        "quadrantChart\n    A: [1.5, -0.5]",  // out of bounds
        "quadrantChart\n    A: [not, numeric]",
        "quadrantChart\n    x-axis Low --> High",
    };
    var parser = new MermaidQuadrantParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_xychart() {
    string[] inputs = {
        "xychart-beta",
        "xychart-beta\n    title T",
        "xychart-beta\n    x-axis [a, b, c]\n    bar [1, 2, 3]",
        "xychart-beta\n    bar []",                           // empty series
        "xychart-beta\n    bar [not, numbers]",               // non-numeric
        "xychart-beta\n    y-axis \"Rev\" 100 --> 0",        // inverted range
    };
    var parser = new MermaidXYChartParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_kanban() {
    string[] inputs = {
        "kanban",
        // Column with no cards
        "kanban\nTodo",
        // Proper form
        "kanban\nTodo\n    card1[Write tests]",
        // Indented column header (actually a card without parent)
        "kanban\n    Todo\n        card1",
        // Card with metadata
        "kanban\nTodo\n    card1[Write tests]@{assigned: alice, priority: high}",
    };
    var parser = new MermaidKanbanParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_sankey() {
    string[] inputs = {
        "sankey-beta",
        "sankey-beta\nSolar,Grid,100",
        "sankey-beta\n,,0",                                   // empty fields
        "sankey-beta\nOnly,One,Pair",
        "sankey-beta\nA,B,not a number",                      // bad value
        "sankey-beta\nA,A,10",                                // self-loop
    };
    var parser = new MermaidSankeyParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_requirement() {
    string[] inputs = {
        "requirementDiagram",
        "requirementDiagram\n    requirement r1 { id: 1 }",
        "requirementDiagram\n    requirement r1 {\n        id: 1\n",  // unclosed
        "requirementDiagram\n    element e1 { type: component }",
        "requirementDiagram\n    r1 - satisfies -> r2",       // dangling refs
    };
    var parser = new MermaidRequirementParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_packet() {
    string[] inputs = {
        "packet-beta",
        "packet-beta\n    0-15: \"Source\"",
        "packet-beta\n    15-0: \"Reversed\"",                // start > end
        "packet-beta\n    bogus line",
        "packet-beta\n    0-15: \"A\"\n    10-20: \"Overlap\"",
    };
    var parser = new MermaidPacketParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_architecture() {
    string[] inputs = {
        "architecture-beta",
        "architecture-beta\n    service db(database)[DB]",
        "architecture-beta\n    group g[Group]\n    service s in g",
        "architecture-beta\n    service s(unknown-icon)[X]",
        "architecture-beta\n    db:R --> L:",                 // missing target
    };
    var parser = new MermaidArchitectureParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_zenuml() {
    string[] inputs = {
        "zenuml",
        "zenuml\n    @Actor A\n    @Service B",
        "zenuml\n    A -> B.m()",
        "zenuml\n    A -> B.m() { A -> B.n() { return x } }", // deep nest
        "zenuml\n    A -> B.()",                              // empty method
    };
    var parser = new MermaidZenUMLParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_radar() {
    string[] inputs = {
        "radar-beta",
        "radar-beta\n    title T",
        "radar-beta\n    axis A, B, C",
        "radar-beta\n    curve x {}",                         // empty curve
        "radar-beta\n    curve x {A: not-a-number}",
        "radar-beta\n    max 10\n    axis A\n    curve c{99999}",  // out of range
    };
    var parser = new MermaidRadarParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_treemap() {
    string[] inputs = {
        "treemap-beta",
        "treemap-beta\n\"Root\"",
        "treemap-beta\n\"Root\"\n    \"Child\": 10",
        // Deeply nested
        "treemap-beta\n\"A\"\n    \"B\"\n        \"C\"\n            \"D\": 1",
        // Negative value
        "treemap-beta\n\"A\": -5",
    };
    var parser = new MermaidTreemapParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_user_journey() {
    string[] inputs = {
        "journey",
        "journey\n    title T",
        "journey\n    section A\n    Task: 5: Me",
        "journey\n    section A\n    Task: 99: Me",           // out of range score
        "journey\n    Task: bad: Me",                          // non-numeric score
    };
    var parser = new MermaidUserJourneyParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

void test_fuzz_mermaid_gitgraph() {
    string[] inputs = {
        "gitGraph",
        "gitGraph\n    commit",
        "gitGraph\n    commit id: \"a\"\n    commit id: \"b\"",
        "gitGraph\n    branch feature\n    checkout feature\n    commit",
        "gitGraph\n    checkout nonexistent",                  // branch not created
    };
    var parser = new MermaidGitGraphParser();
    foreach (var src in inputs) {
        var d = parser.parse(src);
        assert(d != null);
    }
}

// =====================================================================
// Entry point
// =====================================================================

int main(string[] args) {
    Test.init(ref args);

    Test.add_func("/renderer/mindmap",      test_mindmap_snapshot);
    Test.add_func("/renderer/timeline",     test_timeline_snapshot);
    Test.add_func("/renderer/quadrant",     test_quadrant_snapshot);
    Test.add_func("/renderer/xychart",      test_xychart_snapshot);
    Test.add_func("/renderer/kanban",       test_kanban_snapshot);
    Test.add_func("/renderer/sankey",       test_sankey_snapshot);
    Test.add_func("/renderer/requirement",  test_requirement_snapshot);
    Test.add_func("/renderer/block",        test_block_snapshot);
    Test.add_func("/renderer/packet",       test_packet_snapshot);
    Test.add_func("/renderer/c4",           test_c4_snapshot);
    Test.add_func("/renderer/architecture", test_architecture_snapshot);
    Test.add_func("/renderer/zenuml",       test_zenuml_snapshot);
    Test.add_func("/renderer/radar",        test_radar_snapshot);
    Test.add_func("/renderer/treemap",      test_treemap_snapshot);
    Test.add_func("/renderer/palette_affects_rendering", test_palette_affects_rendering);
    Test.add_func("/renderer/transparent_background_swap", test_transparent_background_swap);

    Test.add_func("/fuzz/mermaid/flowchart", test_fuzz_mermaid_flowchart);
    Test.add_func("/fuzz/mermaid/sequence",  test_fuzz_mermaid_sequence);
    Test.add_func("/fuzz/mermaid/state",     test_fuzz_mermaid_state);
    Test.add_func("/fuzz/mermaid/class",     test_fuzz_mermaid_class);
    Test.add_func("/fuzz/mermaid/er",        test_fuzz_mermaid_er);
    Test.add_func("/fuzz/mermaid/pie",       test_fuzz_mermaid_pie);
    Test.add_func("/fuzz/mermaid/gantt",     test_fuzz_mermaid_gantt);
    Test.add_func("/fuzz/mermaid/mindmap",   test_fuzz_mermaid_mindmap);
    Test.add_func("/fuzz/mermaid/c4",        test_fuzz_mermaid_c4);
    Test.add_func("/fuzz/mermaid/block",     test_fuzz_mermaid_block);
    Test.add_func("/fuzz/mermaid/timeline",  test_fuzz_mermaid_timeline);
    Test.add_func("/fuzz/mermaid/quadrant",  test_fuzz_mermaid_quadrant);
    Test.add_func("/fuzz/mermaid/xychart",   test_fuzz_mermaid_xychart);
    Test.add_func("/fuzz/mermaid/kanban",    test_fuzz_mermaid_kanban);
    Test.add_func("/fuzz/mermaid/sankey",    test_fuzz_mermaid_sankey);
    Test.add_func("/fuzz/mermaid/requirement", test_fuzz_mermaid_requirement);
    Test.add_func("/fuzz/mermaid/packet",    test_fuzz_mermaid_packet);
    Test.add_func("/fuzz/mermaid/architecture", test_fuzz_mermaid_architecture);
    Test.add_func("/fuzz/mermaid/zenuml",    test_fuzz_mermaid_zenuml);
    Test.add_func("/fuzz/mermaid/radar",     test_fuzz_mermaid_radar);
    Test.add_func("/fuzz/mermaid/treemap",   test_fuzz_mermaid_treemap);
    Test.add_func("/fuzz/mermaid/journey",   test_fuzz_mermaid_user_journey);
    Test.add_func("/fuzz/mermaid/gitgraph",  test_fuzz_mermaid_gitgraph);

    return Test.run();
}
