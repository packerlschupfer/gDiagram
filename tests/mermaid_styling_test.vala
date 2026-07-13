using GDiagram;

void test_custom_fill_colors() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start]
    B[Success]
    style A fill:#87CEEB
    style B fill:#90EE90
""");

    assert(diagram.nodes.size == 2);
    var node_a = diagram.find_node("A");
    assert(node_a != null);
    assert(node_a.fill_color == "#87CEEB");
    var node_b = diagram.find_node("B");
    assert(node_b != null);
    assert(node_b.fill_color == "#90EE90");
}

void test_stroke_styling() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Node]
    style A stroke:#FF0000,stroke-width:3
""");

    var node = diagram.find_node("A");
    assert(node != null);
    assert(node.stroke_color == "#FF0000");
    assert(node.stroke_width == "3");
}

void test_classdef_styles() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    classDef myStyle fill:#FFFF00,stroke:#000000,stroke-width:2
    A[Node A]
    B[Node B]
    class A,B myStyle
""");

    assert(diagram.styles.size == 1);
    assert(diagram.nodes.size == 2);
    assert(diagram.find_node("A").fill_color == "#FFFF00");
    assert(diagram.find_node("B").fill_color == "#FFFF00");
}

void test_click_actions() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Click Me]
    click A "https://example.com" "Visit Example"
""");

    var node = diagram.find_node("A");
    assert(node != null);
    assert(node.href_link == "https://example.com");
    assert(node.tooltip == "Visit Example");
}

void test_edge_parsing() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] --> B[End]
""");

    assert(diagram.edges.size == 1);
    assert(diagram.edges.get(0).from.id == "A");
    assert(diagram.edges.get(0).to.id == "B");
}

void test_subgraph_parsing() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Node A]
    subgraph Group1
        B[Node B]
        C[Node C]
    end
    A --> B
""");

    assert(diagram.subgraphs.size == 1);
    assert(diagram.subgraphs.get(0).id == "Group1");
}

void test_empty_diagram() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("flowchart TD\n");

    assert(diagram.nodes.size == 0);
    assert(diagram.edges.size == 0);
    assert(!diagram.has_errors());
}

void test_parse_errors_graceful() {
    var parser = new MermaidFlowchartParser();
    // Unclosed bracket — should not crash
    var diagram = parser.parse("""flowchart TD
    A[Unclosed bracket
    B --> C
""");
    assert(diagram.nodes.size >= 0);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/mermaid/styling/fill_colors", test_custom_fill_colors);
    Test.add_func("/mermaid/styling/stroke", test_stroke_styling);
    Test.add_func("/mermaid/styling/classdef", test_classdef_styles);
    Test.add_func("/mermaid/styling/click_actions", test_click_actions);
    Test.add_func("/mermaid/styling/edge_parsing", test_edge_parsing);
    Test.add_func("/mermaid/styling/subgraph", test_subgraph_parsing);
    Test.add_func("/mermaid/styling/empty_diagram", test_empty_diagram);
    Test.add_func("/mermaid/styling/parse_errors_graceful", test_parse_errors_graceful);
    return Test.run();
}
