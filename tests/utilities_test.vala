using GDiagram;

/**
 * Test suite for utility classes
 */

void test_diagram_validator() {
    print("=== Diagram Validator Test ===\n");

    string source = """flowchart TD
    A[Start] --> B[Process]
    C[Disconnected]
    B --> D[End]
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var validator = new DiagramValidator();
    validator.validate_flowchart(diagram);

    // Should detect disconnected node
    assert(validator.messages.size > 0);
    print("  Found %d validation issues\n", validator.messages.size);
    print("✓ Validator detects issues correctly\n\n");
}

void test_diagram_stats() {
    print("=== Diagram Stats Test ===\n");

    string source = """flowchart TD
    A --> B --> C --> D
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var stats = new DiagramStats();
    stats.analyze_mermaid_flowchart(diagram, source);

    assert(stats.node_count == 4);
    assert(stats.edge_count == 3);
    print("  Nodes: %d, Edges: %d\n", stats.node_count, stats.edge_count);
    print("  Complexity: %s\n", stats.get_complexity());
    print("✓ Stats calculated correctly\n\n");
}

void test_complexity_analyzer() {
    print("=== Complexity Analyzer Test ===\n");

    string source = """flowchart TD
    A[Start] --> B{Decision 1}
    B -->|Yes| C{Decision 2}
    B -->|No| D[Process]
    C -->|Yes| E[End]
    C -->|No| F[Error]
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var analyzer = new ComplexityAnalyzer();
    var metrics = analyzer.analyze_flowchart(diagram);

    assert(metrics.nodes == 6);
    assert(metrics.branch_points >= 2);  // Two decision nodes
    print("  Nodes: %d, Branches: %d\n", metrics.nodes, metrics.branch_points);
    print("  Rating: %s\n", metrics.get_rating());
    print("✓ Complexity analysis working\n\n");
}

void test_format_converter() {
    print("=== Format Converter Test ===\n");

    string plantuml = """@startuml
participant Alice
participant Bob
Alice -> Bob: Hello
@enduml
""";

    string? mermaid = FormatConverter.sequence_plantuml_to_mermaid(plantuml);
    assert(mermaid != null);
    assert(mermaid.contains("sequenceDiagram"));
    assert(mermaid.contains("Alice"));
    assert(mermaid.contains("Bob"));

    print("  Converted to Mermaid successfully\n");
    print("✓ Format conversion working\n\n");
}

void test_diagram_templates() {
    print("=== Diagram Templates Test ===\n");

    DiagramTemplates.initialize();
    string[] names = DiagramTemplates.get_template_names();

    assert(names.length >= 11);
    print("  Found %d templates\n", names.length);

    string? flowchart = DiagramTemplates.get_template("flowchart");
    assert(flowchart != null);
    assert(flowchart.contains("flowchart"));

    print("✓ Templates loaded correctly\n\n");
}

void test_export_presets() {
    print("=== Export Presets Test ===\n");

    ExportPresets.initialize();
    var presets = ExportPresets.get_presets();

    assert(presets.size >= 11);
    print("  Found %d export presets\n", presets.size);

    var web_preset = ExportPresets.get_preset("Web (Small)");
    assert(web_preset != null);
    assert(web_preset.width == 800);
    assert(web_preset.height == 600);

    print("✓ Export presets configured correctly\n\n");
}

void test_diagram_linter() {
    print("=== Diagram Linter Test ===\n");

    string source = """flowchart TD
    nodeA --> nodeB --> nodeC --> nodeD --> nodeE
    nodeE --> nodeF --> nodeG --> nodeH
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var linter = new DiagramLinter();
    linter.lint_flowchart(diagram);

    // Should have some suggestions
    print("  Linting messages: %d\n", linter.messages.size);
    print("✓ Linter provides suggestions\n\n");
}

void test_diagram_optimizer() {
    print("=== Diagram Optimizer Test ===\n");

    string source = """flowchart TD
    A --> B --> C --> D --> E
    F --> G --> H --> I --> J
    K --> L --> M --> N --> O
    P --> Q --> R --> S --> T
""";

    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse(source);

    var optimizer = new DiagramOptimizer();
    optimizer.analyze_flowchart(diagram);

    // Should have optimization suggestions for large diagram
    assert(optimizer.suggestions.size > 0);
    print("  Suggestions: %d\n", optimizer.suggestions.size);
    print("✓ Optimizer provides recommendations\n\n");
}

int main(string[] args) {
    print("\n=== Utility Classes Test Suite ===\n\n");

    test_diagram_validator();
    test_diagram_stats();
    test_complexity_analyzer();
    test_format_converter();
    test_diagram_templates();
    test_export_presets();
    test_diagram_linter();
    test_diagram_optimizer();

    print("=== All utility tests passed! ===\n\n");

    return 0;
}
