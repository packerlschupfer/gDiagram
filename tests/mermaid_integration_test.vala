using GDiagram;

void test_flowchart_pipeline() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Process]
    B -->|No| D[End]
    C --> D
""");

    assert(!diagram.has_errors());
    assert(diagram.nodes.size == 4);
    assert(diagram.edges.size == 4);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph G"));
    assert(dot.contains("shape=diamond"));

    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);

    assert(renderer.export_to_png(diagram, "/tmp/test_flowchart_integration.png"));
    assert(renderer.export_to_svg(diagram, "/tmp/test_flowchart_integration.svg"));
    assert(renderer.export_to_pdf(diagram, "/tmp/test_flowchart_integration.pdf"));
}

void test_sequence_pipeline() {
    var parser = new MermaidSequenceParser();
    var diagram = parser.parse("""sequenceDiagram
    autonumber
    participant Alice
    participant Bob
    Alice->>Bob: Hello
    Bob-->>Alice: Hi
    Note over Alice,Bob: Conversation
""");

    assert(!diagram.has_errors());
    assert(diagram.actors.size == 2);
    assert(diagram.messages.size == 2);
    assert(diagram.notes.size == 1);
    assert(diagram.autonumber == true);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidSequenceRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph G"));
    assert(dot.contains("Alice"));
    assert(dot.contains("Bob"));

    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);

    assert(renderer.export_to_png(diagram, "/tmp/test_sequence_integration.png"));
    assert(renderer.export_to_svg(diagram, "/tmp/test_sequence_integration.svg"));
    assert(renderer.export_to_pdf(diagram, "/tmp/test_sequence_integration.pdf"));
}

void test_state_pipeline() {
    var parser = new MermaidStateParser();
    var diagram = parser.parse("""stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: Start
    Processing --> Success: Complete
    Processing --> Error: Failed
    Success --> [*]
    Error --> Idle: Retry
""");

    assert(!diagram.has_errors());

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidStateRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph G"));
    assert(dot.contains("Idle"));

    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);

    assert(renderer.export_to_png(diagram, "/tmp/test_state_integration.png"));
    assert(renderer.export_to_svg(diagram, "/tmp/test_state_integration.svg"));
    assert(renderer.export_to_pdf(diagram, "/tmp/test_state_integration.pdf"));
}

void test_error_handling() {
    var fc_parser = new MermaidFlowchartParser();

    // Unclosed bracket — must not crash
    fc_parser.parse("""flowchart TD
    A[Unclosed bracket
    B --> C
""");

    // Missing destination in sequence
    var seq_parser = new MermaidSequenceParser();
    var seq_diagram = seq_parser.parse("""sequenceDiagram
    Alice->>: Missing destination
""");
    assert(seq_diagram.has_errors());

    // Empty diagram
    var empty = fc_parser.parse("flowchart TD\n");
    assert(!empty.has_errors());
    assert(empty.nodes.size == 0);
}

void test_complex_features() {
    var parser = new MermaidFlowchartParser();

    // Chained edges
    var diagram = parser.parse("""flowchart LR
    A --> B --> C --> D --> E
""");
    assert(diagram.nodes.size == 5);
    assert(diagram.edges.size == 4);

    // Edge labels
    diagram = parser.parse("""flowchart TD
    A -->|Label 1| B
    B -->|Label 2| C
    C -->|Label 3| D
""");
    assert(diagram.edges.get(0).label == "Label 1");
    assert(diagram.edges.get(1).label == "Label 2");
    assert(diagram.edges.get(2).label == "Label 3");

    // All node shapes
    diagram = parser.parse("""flowchart TD
    A[Rectangle]
    B(Rounded)
    C{Diamond}
    D([Stadium])
    E[[Subroutine]]
    F((Circle))
    G{{Hexagon}}
    H(((Double)))
""");
    assert(diagram.nodes.size == 8);
    assert(diagram.find_node("A").shape == FlowchartNodeShape.RECTANGLE);
    assert(diagram.find_node("B").shape == FlowchartNodeShape.ROUNDED);
    assert(diagram.find_node("C").shape == FlowchartNodeShape.RHOMBUS);
    assert(diagram.find_node("D").shape == FlowchartNodeShape.STADIUM);
    assert(diagram.find_node("E").shape == FlowchartNodeShape.SUBROUTINE);
    assert(diagram.find_node("F").shape == FlowchartNodeShape.CIRCLE);
    assert(diagram.find_node("G").shape == FlowchartNodeShape.HEXAGON);
    assert(diagram.find_node("H").shape == FlowchartNodeShape.DOUBLE_CIRCLE);
}

void test_performance() {
    var source_builder = new StringBuilder();
    source_builder.append("flowchart TD\n");
    int node_count = 50;
    for (int i = 0; i < node_count; i++)
        source_builder.append_printf("    N%d[Node %d]\n", i, i);
    for (int i = 0; i < node_count - 1; i++)
        source_builder.append_printf("    N%d --> N%d\n", i, i + 1);

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source_builder.str);
    assert(diagram.nodes.size == node_count);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");
    uint8[]? svg = renderer.render_to_svg(diagram);
    assert(svg != null && svg.length > 0);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/mermaid/integration/flowchart_pipeline", test_flowchart_pipeline);
    Test.add_func("/mermaid/integration/sequence_pipeline", test_sequence_pipeline);
    Test.add_func("/mermaid/integration/state_pipeline", test_state_pipeline);
    Test.add_func("/mermaid/integration/error_handling", test_error_handling);
    Test.add_func("/mermaid/integration/complex_features", test_complex_features);
    Test.add_func("/mermaid/integration/performance", test_performance);
    return Test.run();
}
