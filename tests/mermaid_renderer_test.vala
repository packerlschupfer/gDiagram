using GDiagram;

void test_dot_generation() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    Start[Start Process] --> Decision{Is Valid?}
    Decision -->|Yes| Process[Process Data]
    Decision -->|No| Error[Show Error]
    Process --> End[End]
    Error --> End
""");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);

    assert(dot.contains("digraph G"));
    assert(dot.contains("rankdir=TB"));
    assert(dot.contains("Start"));
    assert(dot.contains("Decision"));
    assert(dot.contains("shape=diamond"));
    assert(dot.contains("label=\"Yes\""));
    assert(dot.contains("label=\"No\""));
}

void test_svg_rendering() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart LR
    A[Start] --> B(Process)
    B --> C{Decision}
    C -->|Yes| D[End]
    C -->|No| A
""");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    uint8[]? svg_data = renderer.render_to_svg(diagram);

    assert(svg_data != null);
    assert(svg_data.length > 0);

    string svg_str = (string)svg_data;
    assert(svg_str.contains("<svg"));
    assert(svg_str.contains("</svg>"));
}

void test_png_export() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Rectangle] --> B(Rounded)
    B --> C{Diamond}
""");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string filename = "/tmp/mermaid_renderer_test.png";
    bool result = renderer.export_to_png(diagram, filename);
    assert(result == true);

    var file = File.new_for_path(filename);
    assert(file.query_exists());
    try {
        FileInfo info = file.query_info("standard::size", FileQueryInfoFlags.NONE);
        assert(info.get_size() > 0);
    } catch (Error e) {
        assert_not_reached();
    }
}

void test_different_shapes_dot() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Box] --> B(Rounded)
    B --> C((Circle))
    C --> D{{Hexagon}}
    D --> E[[Subroutine]]
""");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);

    assert(dot.contains("shape=box"));
    assert(dot.contains("shape=circle"));
    assert(dot.contains("shape=hexagon"));
    assert(dot.contains("rounded"));    // style="filled,rounded" for ROUNDED/STADIUM nodes
    assert(dot.contains("peripheries=2"));
}

void test_arrow_styles_dot() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A --> B
    C -.-> D
    E ==> F
    G --o H
""");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidFlowchartRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);

    assert(dot.contains("style=dotted"));
    assert(dot.contains("penwidth=3"));
    assert(dot.contains("arrowhead=empty"));
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/mermaid/renderer/dot_generation", test_dot_generation);
    Test.add_func("/mermaid/renderer/svg_rendering", test_svg_rendering);
    Test.add_func("/mermaid/renderer/png_export", test_png_export);
    Test.add_func("/mermaid/renderer/shapes_dot", test_different_shapes_dot);
    Test.add_func("/mermaid/renderer/arrow_styles_dot", test_arrow_styles_dot);
    return Test.run();
}
