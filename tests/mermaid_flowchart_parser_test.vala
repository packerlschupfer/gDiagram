using GDiagram;

void test_simple_flowchart() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] --> B[Process]
    B --> C[End]
""");

    assert(diagram.direction == FlowchartDirection.TOP_DOWN);
    assert(diagram.nodes.size == 3);
    assert(diagram.edges.size == 2);
    assert(!diagram.has_errors());

    var node_a = diagram.find_node("A");
    assert(node_a != null);
    assert(node_a.text == "Start");
    assert(node_a.shape == FlowchartNodeShape.RECTANGLE);

    assert(diagram.find_node("B") != null);
    assert(diagram.find_node("C") != null);

    var edge1 = diagram.edges.get(0);
    assert(edge1.from.id == "A");
    assert(edge1.to.id == "B");
    assert(edge1.edge_type == FlowchartEdgeType.SOLID);

    var edge2 = diagram.edges.get(1);
    assert(edge2.from.id == "B");
    assert(edge2.to.id == "C");
}

void test_flowchart_shapes() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart LR
    A[Rectangle]
    B(Rounded)
    C{Diamond}
    D([Stadium])
    E[[Subroutine]]
    A --> B --> C --> D --> E
""");

    assert(diagram.direction == FlowchartDirection.LEFT_RIGHT);
    assert(diagram.nodes.size == 5);
    assert(diagram.edges.size == 4);

    assert(diagram.find_node("A").shape == FlowchartNodeShape.RECTANGLE);
    assert(diagram.find_node("A").text == "Rectangle");
    assert(diagram.find_node("B").shape == FlowchartNodeShape.ROUNDED);
    assert(diagram.find_node("B").text == "Rounded");
    assert(diagram.find_node("C").shape == FlowchartNodeShape.RHOMBUS);
    assert(diagram.find_node("C").text == "Diamond");
    assert(diagram.find_node("D").shape == FlowchartNodeShape.STADIUM);
    assert(diagram.find_node("D").text == "Stadium");
    assert(diagram.find_node("E").shape == FlowchartNodeShape.SUBROUTINE);
    assert(diagram.find_node("E").text == "Subroutine");
}

void test_flowchart_edge_labels() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] -->|Success| B[Process]
    A -->|Failure| C[Error]
    B --> D[End]
""");

    assert(diagram.nodes.size == 4);
    assert(diagram.edges.size == 3);

    assert(diagram.edges.get(0).label == "Success");
    assert(diagram.edges.get(0).from.id == "A");
    assert(diagram.edges.get(0).to.id == "B");

    assert(diagram.edges.get(1).label == "Failure");
    assert(diagram.edges.get(1).from.id == "A");
    assert(diagram.edges.get(1).to.id == "C");

    assert(diagram.edges.get(2).label == null);
    assert(diagram.edges.get(2).from.id == "B");
    assert(diagram.edges.get(2).to.id == "D");
}

void test_flowchart_arrow_types() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A --> B
    C -.-> D
    E ==> F
    G --o H
    I --x J
""");

    assert(diagram.nodes.size == 10);
    assert(diagram.edges.size == 5);

    assert(diagram.edges.get(0).edge_type == FlowchartEdgeType.SOLID);
    assert(diagram.edges.get(0).arrow_type == FlowchartArrowType.NORMAL);

    assert(diagram.edges.get(1).edge_type == FlowchartEdgeType.DOTTED);
    assert(diagram.edges.get(1).arrow_type == FlowchartArrowType.NORMAL);

    assert(diagram.edges.get(2).edge_type == FlowchartEdgeType.THICK);
    assert(diagram.edges.get(2).arrow_type == FlowchartArrowType.NORMAL);

    assert(diagram.edges.get(3).edge_type == FlowchartEdgeType.SOLID);
    assert(diagram.edges.get(3).arrow_type == FlowchartArrowType.OPEN);

    assert(diagram.edges.get(4).edge_type == FlowchartEdgeType.SOLID);
    assert(diagram.edges.get(4).arrow_type == FlowchartArrowType.CROSS);
}

void test_chained_edges() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A --> B --> C --> D
""");

    assert(diagram.nodes.size == 4);
    assert(diagram.edges.size == 3);

    assert(diagram.edges.get(0).from.id == "A");
    assert(diagram.edges.get(0).to.id == "B");
    assert(diagram.edges.get(1).from.id == "B");
    assert(diagram.edges.get(1).to.id == "C");
    assert(diagram.edges.get(2).from.id == "C");
    assert(diagram.edges.get(2).to.id == "D");
}

void test_complex_flowchart() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    Start[Start Process] --> Input{Input Valid?}
    Input -->|Yes| Process[Process Data]
    Input -->|No| Error[Show Error]
    Process --> Output[Display Result]
    Error --> End[End]
    Output --> End
""");

    assert(diagram.nodes.size == 6);
    assert(diagram.edges.size == 6);
    assert(!diagram.has_errors());

    var start = diagram.find_node("Start");
    assert(start.text == "Start Process");
    assert(start.shape == FlowchartNodeShape.RECTANGLE);

    var input = diagram.find_node("Input");
    assert(input.text == "Input Valid?");
    assert(input.shape == FlowchartNodeShape.RHOMBUS);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/mermaid/flowchart/simple", test_simple_flowchart);
    Test.add_func("/mermaid/flowchart/shapes", test_flowchart_shapes);
    Test.add_func("/mermaid/flowchart/edge_labels", test_flowchart_edge_labels);
    Test.add_func("/mermaid/flowchart/arrow_types", test_flowchart_arrow_types);
    Test.add_func("/mermaid/flowchart/chained_edges", test_chained_edges);
    Test.add_func("/mermaid/flowchart/complex", test_complex_flowchart);
    return Test.run();
}
