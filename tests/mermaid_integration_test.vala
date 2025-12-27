using GDiagram;

/**
 * Comprehensive integration test for all Mermaid diagram types
 * Tests the complete pipeline: Lexer → Parser → Renderer → Export
 */

void test_flowchart_pipeline() {
    print("=== Flowchart Pipeline Test ===\n");

    string source = """flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Process]
    B -->|No| D[End]
    C --> D
""";

    // Parse
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    assert(!diagram.has_errors());
    assert(diagram.nodes.size == 4);
    assert(diagram.edges.size == 4);
    print("✓ Flowchart parsing: 4 nodes, 4 edges\n");

    // Render
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph G"));
    assert(dot.contains("shape=diamond"));
    print("✓ DOT generation: valid structure\n");

    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);
    print("✓ SVG rendering: %d bytes\n", svg.length);

    // Export
    bool png_ok = renderer.export_to_png(diagram, "/tmp/test_flowchart_integration.png");
    assert(png_ok);
    print("✓ PNG export: successful\n");

    bool svg_ok = renderer.export_to_svg(diagram, "/tmp/test_flowchart_integration.svg");
    assert(svg_ok);
    print("✓ SVG export: successful\n");

    bool pdf_ok = renderer.export_to_pdf(diagram, "/tmp/test_flowchart_integration.pdf");
    assert(pdf_ok);
    print("✓ PDF export: successful\n\n");
}

void test_sequence_pipeline() {
    print("=== Sequence Diagram Pipeline Test ===\n");

    string source = """sequenceDiagram
    autonumber
    participant Alice
    participant Bob
    Alice->>Bob: Hello
    Bob-->>Alice: Hi
    Note over Alice,Bob: Conversation
""";

    // Parse
    var parser = new MermaidSequenceParser();
    var diagram = parser.parse(source);

    assert(!diagram.has_errors());
    assert(diagram.actors.size == 2);
    assert(diagram.messages.size == 2);
    assert(diagram.notes.size == 1);
    assert(diagram.autonumber == true);
    print("✓ Sequence parsing: 2 actors, 2 messages, 1 note\n");

    // Render
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidSequenceRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph G"));
    assert(dot.contains("Alice"));
    assert(dot.contains("Bob"));
    print("✓ DOT generation: valid structure\n");

    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);
    print("✓ SVG rendering: %d bytes\n", svg.length);

    // Export
    bool png_ok = renderer.export_to_png(diagram, "/tmp/test_sequence_integration.png");
    assert(png_ok);
    print("✓ PNG export: successful\n");

    bool svg_ok = renderer.export_to_svg(diagram, "/tmp/test_sequence_integration.svg");
    assert(svg_ok);
    print("✓ SVG export: successful\n");

    bool pdf_ok = renderer.export_to_pdf(diagram, "/tmp/test_sequence_integration.pdf");
    assert(pdf_ok);
    print("✓ PDF export: successful\n\n");
}

void test_state_pipeline() {
    print("=== State Diagram Pipeline Test ===\n");

    string source = """stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: Start
    Processing --> Success: Complete
    Processing --> Error: Failed
    Success --> [*]
    Error --> Idle: Retry
""";

    // Parse
    var parser = new MermaidStateParser();
    var diagram = parser.parse(source);

    assert(!diagram.has_errors());
    assert(diagram.states.size == 6); // Idle, Processing, Success, Error, [*]_start, [*]_end
    assert(diagram.transitions.size == 6);
    print("✓ State parsing: 6 states, 6 transitions\n");

    // Render
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidStateRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph G"));
    assert(dot.contains("Idle"));
    assert(dot.contains("shape=circle")); // Start/end states
    print("✓ DOT generation: valid structure\n");

    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);
    print("✓ SVG rendering: %d bytes\n", svg.length);

    // Export
    bool png_ok = renderer.export_to_png(diagram, "/tmp/test_state_integration.png");
    assert(png_ok);
    print("✓ PNG export: successful\n");

    bool svg_ok = renderer.export_to_svg(diagram, "/tmp/test_state_integration.svg");
    assert(svg_ok);
    print("✓ SVG export: successful\n");

    bool pdf_ok = renderer.export_to_pdf(diagram, "/tmp/test_state_integration.pdf");
    assert(pdf_ok);
    print("✓ PDF export: successful\n\n");
}

void test_error_handling() {
    print("=== Error Handling Test ===\n");

    // Test invalid flowchart
    string bad_flowchart = """flowchart TD
    A[Unclosed bracket
    B --> C
""";

    var fc_parser = new MermaidFlowchartParser();
    var fc_diagram = fc_parser.parse(bad_flowchart);
    print("✓ Flowchart handles parse errors gracefully\n");

    // Test invalid sequence
    string bad_sequence = """sequenceDiagram
    Alice->>: Missing destination
""";

    var seq_parser = new MermaidSequenceParser();
    var seq_diagram = seq_parser.parse(bad_sequence);
    assert(seq_diagram.has_errors());
    print("✓ Sequence detects missing destination: %d errors\n", seq_diagram.errors.size);

    // Test empty diagrams
    string empty = """flowchart TD
""";

    var empty_diagram = fc_parser.parse(empty);
    assert(!empty_diagram.has_errors());
    assert(empty_diagram.nodes.size == 0);
    print("✓ Empty diagrams handled correctly\n\n");
}

void test_complex_features() {
    print("=== Complex Features Test ===\n");

    // Test chained edges
    string chained = """flowchart LR
    A --> B --> C --> D --> E
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(chained);
    assert(diagram.nodes.size == 5);
    assert(diagram.edges.size == 4);
    print("✓ Chained edges: 5 nodes, 4 edges\n");

    // Test multiple edge labels
    string labeled = """flowchart TD
    A -->|Label 1| B
    B -->|Label 2| C
    C -->|Label 3| D
""";

    diagram = parser.parse(labeled);
    assert(diagram.edges.get(0).label == "Label 1");
    assert(diagram.edges.get(1).label == "Label 2");
    assert(diagram.edges.get(2).label == "Label 3");
    print("✓ Edge labels: all 3 labels preserved\n");

    // Test all node shapes
    string shapes = """flowchart TD
    A[Rectangle]
    B(Rounded)
    C{Diamond}
    D([Stadium])
    E[[Subroutine]]
    F((Circle))
    G{{Hexagon}}
    H(((Double)))
""";

    diagram = parser.parse(shapes);
    assert(diagram.nodes.size == 8);
    assert(diagram.find_node("A").shape == FlowchartNodeShape.RECTANGLE);
    assert(diagram.find_node("B").shape == FlowchartNodeShape.ROUNDED);
    assert(diagram.find_node("C").shape == FlowchartNodeShape.RHOMBUS);
    assert(diagram.find_node("D").shape == FlowchartNodeShape.STADIUM);
    assert(diagram.find_node("E").shape == FlowchartNodeShape.SUBROUTINE);
    assert(diagram.find_node("F").shape == FlowchartNodeShape.CIRCLE);
    assert(diagram.find_node("G").shape == FlowchartNodeShape.HEXAGON);
    assert(diagram.find_node("H").shape == FlowchartNodeShape.DOUBLE_CIRCLE);
    print("✓ All 8 node shapes parsed correctly\n\n");
}

void test_performance() {
    print("=== Performance Test ===\n");

    // Generate large diagram programmatically
    var source_builder = new StringBuilder();
    source_builder.append("flowchart TD\n");

    int node_count = 50;
    for (int i = 0; i < node_count; i++) {
        source_builder.append_printf("    N%d[Node %d]\n", i, i);
    }

    for (int i = 0; i < node_count - 1; i++) {
        source_builder.append_printf("    N%d --> N%d\n", i, i + 1);
    }

    string large_diagram = source_builder.str;

    var timer = new Timer();
    timer.start();

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(large_diagram);

    double parse_time = timer.elapsed();
    print("✓ Parsed %d nodes in %.3f seconds\n", node_count, parse_time);

    timer.reset();
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    uint8[]? svg = renderer.render_to_svg(diagram);
    double render_time = timer.elapsed();

    assert(svg != null);
    print("✓ Rendered %d nodes in %.3f seconds\n", node_count, render_time);
    print("✓ Total time: %.3f seconds\n", parse_time + render_time);
    print("✓ SVG size: %d bytes\n\n", svg.length);
}

int main(string[] args) {
    print("\n╔════════════════════════════════════════════╗\n");
    print("║  Mermaid Integration Test Suite          ║\n");
    print("║  Testing Complete Pipeline                ║\n");
    print("╚════════════════════════════════════════════╝\n\n");

    test_flowchart_pipeline();
    test_sequence_pipeline();
    test_state_pipeline();
    test_error_handling();
    test_complex_features();
    test_performance();

    print("╔════════════════════════════════════════════╗\n");
    print("║  ✅ ALL INTEGRATION TESTS PASSED!         ║\n");
    print("║  Flowchart, Sequence, State - Complete!  ║\n");
    print("╚════════════════════════════════════════════╝\n\n");

    return 0;
}
