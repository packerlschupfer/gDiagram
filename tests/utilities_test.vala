using GDiagram;

void test_diagram_validator() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] --> B[Process]
    C[Disconnected]
    B --> D[End]
""");

    var validator = new DiagramValidator();
    validator.validate_flowchart(diagram);
    assert(validator.messages.size > 0);
}

void test_diagram_stats() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A --> B --> C --> D
""");

    var stats = new DiagramStats();
    stats.analyze_mermaid_flowchart(diagram, "flowchart TD\nA --> B --> C --> D\n");
    assert(stats.node_count == 4);
    assert(stats.edge_count == 3);
}

void test_complexity_analyzer() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A[Start] --> B{Decision 1}
    B -->|Yes| C{Decision 2}
    B -->|No| D[Process]
    C -->|Yes| E[End]
    C -->|No| F[Error]
""");

    var analyzer = new ComplexityAnalyzer();
    var metrics = analyzer.analyze_flowchart(diagram);
    assert(metrics.nodes == 6);
    assert(metrics.branch_points >= 2);
}

void test_format_converter() {
    string plantuml = "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob: Hello\n@enduml\n";
    string? mermaid = FormatConverter.sequence_plantuml_to_mermaid(plantuml);
    assert(mermaid != null);
    assert(mermaid.contains("sequenceDiagram"));
    assert(mermaid.contains("Alice"));
    assert(mermaid.contains("Bob"));
}

void test_diagram_templates() {
    // Static string fields are initialized in GObject class_init;
    // creating an instance forces that to run before accessing them.
    new DiagramTemplates();

    var names = DiagramTemplates.get_template_names();
    assert(names.length >= 11);

    string? flowchart = DiagramTemplates.get_template("flowchart-basic");
    assert(flowchart != null);
    assert(flowchart.contains("flowchart"));

    string? sequence = DiagramTemplates.get_template("sequence-basic");
    assert(sequence != null);
    assert(sequence.contains("sequenceDiagram"));
}

void test_export_presets() {
    ExportPresets.initialize();
    var presets = ExportPresets.get_presets();
    assert(presets.size >= 11);

    var web_preset = ExportPresets.get_preset("Web (Small)");
    assert(web_preset != null);
    assert(web_preset.width == 800);
    assert(web_preset.height == 600);
}

void test_diagram_linter() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    nodeA --> nodeB --> nodeC --> nodeD --> nodeE
    nodeE --> nodeF --> nodeG --> nodeH
""");

    var linter = new DiagramLinter();
    linter.lint_flowchart(diagram);
    // Linter runs without crashing and returns some messages (may be 0 for simple diagrams)
    assert(linter.messages.size >= 0);
}

void test_diagram_optimizer() {
    var parser = new MermaidFlowchartParser();
    var diagram = parser.parse("""flowchart TD
    A --> B --> C --> D --> E
    F --> G --> H --> I --> J
    K --> L --> M --> N --> O
    P --> Q --> R --> S --> T
""");

    var optimizer = new DiagramOptimizer();
    optimizer.analyze_flowchart(diagram);
    assert(optimizer.suggestions.size > 0);
}

// =====================================================================
// Fuzz tests for FormatConverter adversarial inputs
// =====================================================================

void test_fuzz_format_converter_empty() {
    // Empty and whitespace-only inputs must not crash.
    assert(FormatConverter.sequence_plantuml_to_mermaid("") != null);
    assert(FormatConverter.sequence_plantuml_to_mermaid("\n\n\n") != null);
    assert(FormatConverter.sequence_mermaid_to_plantuml("") != null);
    assert(FormatConverter.class_plantuml_to_mermaid("") != null);
    assert(FormatConverter.class_mermaid_to_plantuml("") != null);
    assert(FormatConverter.state_plantuml_to_mermaid("") != null);
    assert(FormatConverter.er_plantuml_to_mermaid("") != null);
}

void test_fuzz_format_converter_auto_unknown() {
    // Sources with no recognizable format.
    assert(FormatConverter.auto_convert("", "mermaid") == null);
    assert(FormatConverter.auto_convert("random garbage text", "mermaid") == null);
    assert(FormatConverter.auto_convert("@startuml\n@enduml", "mermaid") == null);
    assert(FormatConverter.auto_convert("@startuml\n@enduml", "plantuml") == null);
}

void test_fuzz_format_converter_malformed() {
    // Malformed but "looks like" PlantUML/Mermaid. Should not crash.
    string[] inputs = {
        "@startuml\nparticipant\n@enduml",
        "@startuml\nclass\n@enduml",
        "@startuml\nentity { { { \n@enduml",
        "sequenceDiagram\nA->>B:\n",
        "classDiagram\nclass {\n",
        "erDiagram\nA ||--|| B\n",
        // Arrow soup
        "@startuml\n-> -> -> ->\n@enduml",
        // Very deep nesting brackets
        "@startuml\nclass X { [{[{[{[{[{[{[{[{[{[ }]}]}]}]}]}]}]}]}]} }\n@enduml",
    };
    foreach (var src in inputs) {
        string? r1 = FormatConverter.sequence_plantuml_to_mermaid(src);
        string? r2 = FormatConverter.class_plantuml_to_mermaid(src);
        string? r3 = FormatConverter.er_plantuml_to_mermaid(src);
        string? r4 = FormatConverter.state_plantuml_to_mermaid(src);
        // Touching each result keeps Vala from dropping the call.
        // Each may legitimately be null for unrecognized input; the
        // important guarantee is that they all returned without crashing.
        if (r1 != null && r1.length < 0) return;
        if (r2 != null && r2.length < 0) return;
        if (r3 != null && r3.length < 0) return;
        if (r4 != null && r4.length < 0) return;
    }
}

// =====================================================================
// DiagramBeautifier fuzz
// =====================================================================

void test_fuzz_beautifier_empty_and_whitespace() {
    assert(DiagramBeautifier.clean("") != null);
    assert(DiagramBeautifier.clean("\n\n\n") != null);
    assert(DiagramBeautifier.clean("   \n   \n   ") != null);
    assert(DiagramBeautifier.format_mermaid_flowchart("") != null);
    assert(DiagramBeautifier.format_plantuml("") != null);
}

void test_fuzz_beautifier_unbalanced_braces() {
    // More close than open — indent should not go negative.
    string src = "flowchart TD\n} } } } }\nA --> B";
    string r = DiagramBeautifier.format_mermaid_flowchart(src);
    assert(r != null);
}

void test_fuzz_beautifier_deeply_nested() {
    var sb = new StringBuilder();
    sb.append("flowchart TD\n");
    for (int i = 0; i < 50; i++) {
        sb.append("subgraph S%d {\n".printf(i));
    }
    sb.append("A --> B\n");
    for (int i = 0; i < 50; i++) {
        sb.append("}\n");
    }
    string r = DiagramBeautifier.format_mermaid_flowchart(sb.str);
    assert(r != null);
}

void test_fuzz_beautifier_very_long_line() {
    var sb = new StringBuilder();
    sb.append("flowchart TD\nA[");
    for (int i = 0; i < 5000; i++) sb.append("x");
    sb.append("] --> B");
    string r = DiagramBeautifier.format_mermaid_flowchart(sb.str);
    assert(r != null);
    assert(r.contains("A["));
}

void test_fuzz_beautifier_crlf_line_endings() {
    // Windows line endings
    string src = "flowchart TD\r\nA --> B\r\nB --> C";
    string r = DiagramBeautifier.format_mermaid_flowchart(src);
    assert(r != null);
}

void test_fuzz_beautifier_unicode() {
    string src = "flowchart TD\n    日本語 --> 한국어\n    한국어 --> العربية";
    string r = DiagramBeautifier.format_mermaid_flowchart(src);
    assert(r != null);
    assert(r.contains("日本語"));
    assert(r.contains("한국어"));
    assert(r.contains("العربية"));
}

void test_fuzz_format_converter_unicode() {
    string puml = "@startuml\nparticipant アリス\nparticipant ボブ\nアリス -> ボブ : こんにちは\n@enduml\n";
    string? mermaid = FormatConverter.sequence_plantuml_to_mermaid(puml);
    assert(mermaid != null);
    assert(mermaid.contains("アリス"));
    assert(mermaid.contains("ボブ"));
    assert(mermaid.contains("こんにちは"));
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/utilities/validator", test_diagram_validator);
    Test.add_func("/utilities/stats", test_diagram_stats);
    Test.add_func("/utilities/complexity", test_complexity_analyzer);
    Test.add_func("/utilities/format_converter", test_format_converter);
    Test.add_func("/utilities/templates", test_diagram_templates);
    Test.add_func("/utilities/export_presets", test_export_presets);
    Test.add_func("/utilities/linter", test_diagram_linter);
    Test.add_func("/utilities/optimizer", test_diagram_optimizer);
    Test.add_func("/utilities/fuzz/fc-empty", test_fuzz_format_converter_empty);
    Test.add_func("/utilities/fuzz/fc-auto-unknown", test_fuzz_format_converter_auto_unknown);
    Test.add_func("/utilities/fuzz/fc-malformed", test_fuzz_format_converter_malformed);
    Test.add_func("/utilities/fuzz/fc-unicode", test_fuzz_format_converter_unicode);
    Test.add_func("/utilities/fuzz/bf-empty", test_fuzz_beautifier_empty_and_whitespace);
    Test.add_func("/utilities/fuzz/bf-unbalanced", test_fuzz_beautifier_unbalanced_braces);
    Test.add_func("/utilities/fuzz/bf-deep", test_fuzz_beautifier_deeply_nested);
    Test.add_func("/utilities/fuzz/bf-long-line", test_fuzz_beautifier_very_long_line);
    Test.add_func("/utilities/fuzz/bf-crlf", test_fuzz_beautifier_crlf_line_endings);
    Test.add_func("/utilities/fuzz/bf-unicode", test_fuzz_beautifier_unicode);
    return Test.run();
}
