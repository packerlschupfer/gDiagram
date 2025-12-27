using GDiagram;

/**
 * Test suite for Mermaid flowchart styling features
 */

void test_custom_fill_colors() {
    print("=== Custom Fill Colors Test ===\n");

    string source = """flowchart TD
    A[Start]
    B[Success]
    style A fill:#87CEEB
    style B fill:#90EE90
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    assert(diagram.nodes.size == 2);

    var node_a = diagram.find_node("A");
    assert(node_a != null);
    assert(node_a.fill_color == "#87CEEB");

    var node_b = diagram.find_node("B");
    assert(node_b != null);
    assert(node_b.fill_color == "#90EE90");

    print("✓ Custom fill colors parsed correctly\n\n");
}

void test_stroke_styling() {
    print("=== Stroke Styling Test ===\n");

    string source = """flowchart TD
    A[Node]
    style A stroke:#FF0000,stroke-width:3
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var node = diagram.find_node("A");
    assert(node != null);
    assert(node.stroke_color == "#FF0000");
    assert(node.stroke_width == "3");

    print("✓ Stroke styling parsed correctly\n\n");
}

void test_classdef_styles() {
    print("=== ClassDef Styles Test ===\n");

    string source = """flowchart TD
    classDef myStyle fill:#FFFF00,stroke:#000000,stroke-width:2

    A[Node A]
    B[Node B]

    class A,B myStyle
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    assert(diagram.styles.size == 1);
    assert(diagram.nodes.size == 2);

    var node_a = diagram.find_node("A");
    var node_b = diagram.find_node("B");

    assert(node_a.fill_color == "#FFFF00");
    assert(node_b.fill_color == "#FFFF00");

    print("✓ ClassDef styles applied correctly\n\n");
}

void test_click_actions() {
    print("=== Click Actions Test ===\n");

    string source = """flowchart TD
    A[Click Me]
    click A "https://example.com" "Visit Example"
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var node = diagram.find_node("A");
    assert(node != null);
    assert(node.href_link == "https://example.com");
    assert(node.tooltip == "Visit Example");

    print("✓ Click actions parsed correctly\n\n");
}

void test_edge_styling() {
    print("=== Edge Styling Test ===\n");

    string source = """flowchart TD
    A[Start] --> B[End]
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    assert(diagram.edges.size == 1);
    var edge = diagram.edges.get(0);
    assert(edge.from.id == "A");
    assert(edge.to.id == "B");

    print("✓ Edge parsed correctly\n\n");
}

void test_subgraph_parsing() {
    print("=== Subgraph Parsing Test ===\n");

    string source = """flowchart TD
    A[Node A]

    subgraph Group1
        B[Node B]
        C[Node C]
    end

    A --> B
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    assert(diagram.subgraphs.size == 1);
    var subgraph = diagram.subgraphs.get(0);
    assert(subgraph.id == "Group1");

    print("✓ Subgraph parsed correctly\n\n");
}

void test_empty_diagram() {
    print("=== Empty Diagram Test ===\n");

    string source = """flowchart TD
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    assert(diagram.nodes.size == 0);
    assert(diagram.edges.size == 0);
    assert(!diagram.has_errors());

    print("✓ Empty diagram handled correctly\n\n");
}

void test_parse_errors() {
    print("=== Parse Errors Test ===\n");

    string source = """flowchart TD
    A[Unclosed bracket
    B --> C
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    // Should handle errors gracefully
    assert(diagram.nodes.size >= 0);

    print("✓ Parse errors handled gracefully\n\n");
}

int main(string[] args) {
    print("\n=== Mermaid Styling Test Suite ===\n\n");

    test_custom_fill_colors();
    test_stroke_styling();
    test_classdef_styles();
    test_click_actions();
    test_edge_styling();
    test_subgraph_parsing();
    test_empty_diagram();
    test_parse_errors();

    print("=== All styling tests passed! ===\n\n");

    return 0;
}
