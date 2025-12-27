using GDiagram;

void test_dot_generation() {
    string source = """flowchart TD
    Start[Start Process] --> Decision{Is Valid?}
    Decision -->|Yes| Process[Process Data]
    Decision -->|No| Error[Show Error]
    Process --> End[End]
    Error --> End
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("DOT Generation Test:\n");
    print("===================\n\n");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    print("Generated DOT:\n%s\n", dot);

    // Verify DOT structure
    assert(dot.contains("digraph G"));
    assert(dot.contains("rankdir=TB"));
    assert(dot.contains("Start"));
    assert(dot.contains("Decision"));
    assert(dot.contains("shape=diamond"));  // Decision node
    assert(dot.contains("label=\"Yes\""));   // Edge label
    assert(dot.contains("label=\"No\""));

    print("✓ DOT generation test passed\n\n");
}

void test_svg_rendering() {
    string source = """flowchart LR
    A[Start] --> B(Process)
    B --> C{Decision}
    C -->|Yes| D[End]
    C -->|No| A
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("SVG Rendering Test:\n");
    print("==================\n\n");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    uint8[]? svg_data = renderer.render_to_svg(diagram);

    assert(svg_data != null);
    assert(svg_data.length > 0);

    string svg_str = (string)svg_data;
    print("SVG output size: %d bytes\n", svg_data.length);
    print("First 200 chars: %s...\n", svg_str.substring(0, 200.clamp(0, svg_str.length)));

    // Verify SVG structure
    assert(svg_str.contains("<svg"));
    assert(svg_str.contains("</svg>"));

    print("✓ SVG rendering test passed\n\n");
}

void test_png_export() {
    string source = """flowchart TD
    A[Rectangle] --> B(Rounded)
    B --> C{Diamond}
    C --> D([Stadium])
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    print("PNG Export Test:\n");
    print("================\n\n");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string filename = "/tmp/mermaid_test.png";
    bool result = renderer.export_to_png(diagram, filename);

    assert(result == true);

    // Verify file exists
    var file = File.new_for_path(filename);
    assert(file.query_exists());

    FileInfo info = file.query_info("standard::size", FileQueryInfoFlags.NONE);
    int64 size = info.get_size();

    print("PNG exported to: %s\n", filename);
    print("File size: %lld bytes\n", size);

    assert(size > 0);

    print("✓ PNG export test passed\n\n");
}

void test_different_shapes() {
    string source = """flowchart TD
    A[Box] --> B(Rounded)
    B --> C((Circle))
    C --> D{{Hexagon}}
    D --> E[[Subroutine]]
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);

    print("Shape Rendering Test:\n");
    print("====================\n\n");
    print("%s\n", dot);

    // Verify different shapes in DOT
    assert(dot.contains("shape=box"));
    assert(dot.contains("shape=circle"));
    assert(dot.contains("shape=hexagon"));
    assert(dot.contains("style=rounded"));
    assert(dot.contains("peripheries=2"));  // subroutine

    print("✓ Shape rendering test passed\n\n");
}

void test_arrow_styles() {
    string source = """flowchart TD
    A --> B
    C -.-> D
    E ==> F
    G --o H
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);

    print("Arrow Styles Test:\n");
    print("==================\n\n");
    print("%s\n", dot);

    // Verify arrow styles
    assert(dot.contains("style=dotted"));
    assert(dot.contains("penwidth=3"));
    assert(dot.contains("arrowhead=empty"));

    print("✓ Arrow styles test passed\n\n");
}

int main(string[] args) {
    print("\n=== Mermaid Flowchart Renderer Tests ===\n\n");

    test_dot_generation();
    test_svg_rendering();
    test_png_export();
    test_different_shapes();
    test_arrow_styles();

    print("=== All renderer tests passed! ===\n\n");

    return 0;
}
