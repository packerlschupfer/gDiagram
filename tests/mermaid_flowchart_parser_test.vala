using GDiagram;

void test_simple_flowchart() {
    string source = """flowchart TD
    A[Start] --> B[Process]
    B --> C[End]
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("Simple flowchart test:\n");
    print("  Direction: %s\n", diagram.direction.to_string());
    print("  Nodes: %d\n", diagram.nodes.size);
    print("  Edges: %d\n", diagram.edges.size);
    print("  Errors: %d\n", diagram.errors.size);

    assert(diagram.direction == FlowchartDirection.TOP_DOWN);
    assert(diagram.nodes.size == 3);
    assert(diagram.edges.size == 2);
    assert(!diagram.has_errors());

    // Check node details
    var node_a = diagram.find_node("A");
    assert(node_a != null);
    assert(node_a.text == "Start");
    assert(node_a.shape == FlowchartNodeShape.RECTANGLE);

    var node_b = diagram.find_node("B");
    assert(node_b != null);
    assert(node_b.text == "Process");

    var node_c = diagram.find_node("C");
    assert(node_c != null);
    assert(node_c.text == "End");

    // Check edges
    var edge1 = diagram.edges.get(0);
    assert(edge1.from.id == "A");
    assert(edge1.to.id == "B");
    assert(edge1.edge_type == FlowchartEdgeType.SOLID);

    var edge2 = diagram.edges.get(1);
    assert(edge2.from.id == "B");
    assert(edge2.to.id == "C");

    print("✓ Simple flowchart test passed\n\n");
}

void test_flowchart_with_shapes() {
    string source = """flowchart LR
    A[Rectangle]
    B(Rounded)
    C{Diamond}
    D([Stadium])
    E[[Subroutine]]
    A --> B --> C --> D --> E
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("Flowchart shapes test:\n");
    print("  Direction: %s\n", diagram.direction.to_string());
    print("  Nodes: %d\n", diagram.nodes.size);
    print("  Edges: %d\n", diagram.edges.size);

    assert(diagram.direction == FlowchartDirection.LEFT_RIGHT);
    assert(diagram.nodes.size == 5);
    assert(diagram.edges.size == 4);

    // Check shapes
    var node_a = diagram.find_node("A");
    assert(node_a.shape == FlowchartNodeShape.RECTANGLE);
    assert(node_a.text == "Rectangle");

    var node_b = diagram.find_node("B");
    assert(node_b.shape == FlowchartNodeShape.ROUNDED);
    assert(node_b.text == "Rounded");

    var node_c = diagram.find_node("C");
    assert(node_c.shape == FlowchartNodeShape.RHOMBUS);
    assert(node_c.text == "Diamond");

    var node_d = diagram.find_node("D");
    assert(node_d.shape == FlowchartNodeShape.STADIUM);
    assert(node_d.text == "Stadium");

    var node_e = diagram.find_node("E");
    assert(node_e.shape == FlowchartNodeShape.SUBROUTINE);
    assert(node_e.text == "Subroutine");

    print("✓ Flowchart shapes test passed\n\n");
}

void test_flowchart_with_labels() {
    string source = """flowchart TD
    A[Start] -->|Success| B[Process]
    A -->|Failure| C[Error]
    B --> D[End]
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("Flowchart with labels test:\n");
    print("  Nodes: %d\n", diagram.nodes.size);
    print("  Edges: %d\n", diagram.edges.size);

    assert(diagram.nodes.size == 4);
    assert(diagram.edges.size == 3);

    // Check edge labels
    var edge1 = diagram.edges.get(0);
    assert(edge1.label == "Success");
    assert(edge1.from.id == "A");
    assert(edge1.to.id == "B");

    var edge2 = diagram.edges.get(1);
    assert(edge2.label == "Failure");
    assert(edge2.from.id == "A");
    assert(edge2.to.id == "C");

    var edge3 = diagram.edges.get(2);
    assert(edge3.label == null);
    assert(edge3.from.id == "B");
    assert(edge3.to.id == "D");

    print("✓ Flowchart with labels test passed\n\n");
}

void test_flowchart_arrow_types() {
    string source = """flowchart TD
    A --> B
    C -.-> D
    E ==> F
    G --o H
    I --x J
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("Arrow types test:\n");
    print("  Nodes: %d\n", diagram.nodes.size);
    print("  Edges: %d\n", diagram.edges.size);

    assert(diagram.nodes.size == 10);
    assert(diagram.edges.size == 5);

    // Check arrow types
    var edge1 = diagram.edges.get(0);
    assert(edge1.edge_type == FlowchartEdgeType.SOLID);
    assert(edge1.arrow_type == FlowchartArrowType.NORMAL);

    var edge2 = diagram.edges.get(1);
    assert(edge2.edge_type == FlowchartEdgeType.DOTTED);
    assert(edge2.arrow_type == FlowchartArrowType.NORMAL);

    var edge3 = diagram.edges.get(2);
    assert(edge3.edge_type == FlowchartEdgeType.THICK);
    assert(edge3.arrow_type == FlowchartArrowType.NORMAL);

    var edge4 = diagram.edges.get(3);
    assert(edge4.edge_type == FlowchartEdgeType.SOLID);
    assert(edge4.arrow_type == FlowchartArrowType.OPEN);

    var edge5 = diagram.edges.get(4);
    assert(edge5.edge_type == FlowchartEdgeType.SOLID);
    assert(edge5.arrow_type == FlowchartArrowType.CROSS);

    print("✓ Arrow types test passed\n\n");
}

void test_chained_edges() {
    string source = """flowchart TD
    A --> B --> C --> D
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("Chained edges test:\n");
    print("  Nodes: %d\n", diagram.nodes.size);
    print("  Edges: %d\n", diagram.edges.size);

    assert(diagram.nodes.size == 4);
    assert(diagram.edges.size == 3);

    // Check edge chain
    assert(diagram.edges.get(0).from.id == "A");
    assert(diagram.edges.get(0).to.id == "B");

    assert(diagram.edges.get(1).from.id == "B");
    assert(diagram.edges.get(1).to.id == "C");

    assert(diagram.edges.get(2).from.id == "C");
    assert(diagram.edges.get(2).to.id == "D");

    print("✓ Chained edges test passed\n\n");
}

void test_complex_flowchart() {
    string source = """flowchart TD
    Start[Start Process] --> Input{Input Valid?}
    Input -->|Yes| Process[Process Data]
    Input -->|No| Error[Show Error]
    Process --> Output[Display Result]
    Error --> End[End]
    Output --> End
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("Complex flowchart test:\n");
    print("  Nodes: %d\n", diagram.nodes.size);
    print("  Edges: %d\n", diagram.edges.size);
    print("  Errors: %d\n", diagram.errors.size);

    foreach (var node in diagram.nodes) {
        print("  Node: %s [%s] (%s)\n", node.id, node.text, node.shape.to_string());
    }

    foreach (var edge in diagram.edges) {
        string label_str = edge.label != null ? " | " + edge.label : "";
        print("  Edge: %s --> %s%s\n", edge.from.id, edge.to.id, label_str);
    }

    assert(diagram.nodes.size == 6);
    assert(diagram.edges.size == 6);
    assert(!diagram.has_errors());

    // Check specific nodes
    var start = diagram.find_node("Start");
    assert(start.text == "Start Process");
    assert(start.shape == FlowchartNodeShape.RECTANGLE);

    var input = diagram.find_node("Input");
    assert(input.text == "Input Valid?");
    assert(input.shape == FlowchartNodeShape.RHOMBUS);

    print("✓ Complex flowchart test passed\n\n");
}

int main(string[] args) {
    print("\n=== Mermaid Flowchart Parser Tests ===\n\n");

    test_simple_flowchart();
    test_flowchart_with_shapes();
    test_flowchart_with_labels();
    test_flowchart_arrow_types();
    test_chained_edges();
    test_complex_flowchart();

    print("=== All flowchart parser tests passed! ===\n\n");

    return 0;
}
