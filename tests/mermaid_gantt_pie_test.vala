using GDiagram;

/**
 * Test suite for Mermaid Gantt and Pie chart diagrams
 */

void test_gantt_basic() {
    print("=== Gantt Basic Test ===\n");

    string source = """gantt
    title Project Schedule
    section Planning
    Requirements : done, 5d
    Design : active, 7d
""";

    var parser = new MermaidGanttParser();
    var diagram = parser.parse(source);

    assert(!diagram.has_errors());
    assert(diagram.title == "Project Schedule");
    assert(diagram.tasks.size >= 2);
    assert(diagram.sections.size == 1);

    print("  Title: %s\n", diagram.title);
    print("  Tasks: %d\n", diagram.tasks.size);
    print("  Sections: %d\n", diagram.sections.size);
    print("✓ Gantt parsing works\n\n");
}

void test_gantt_rendering() {
    print("=== Gantt Rendering Test ===\n");

    string source = """gantt
    Task 1 : done, 3d
    Task 2 : active, 5d
""";

    var parser = new MermaidGanttParser();
    var diagram = parser.parse(source);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidGanttRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph"));
    assert(dot.contains("Task 1"));

    print("  DOT generated successfully\n");
    print("✓ Gantt rendering works\n\n");
}

void test_pie_basic() {
    print("=== Pie Basic Test ===\n");

    string source = """pie title Data Distribution
    \"Category A\" : 45
    \"Category B\" : 30
    \"Category C\" : 25
""";

    var parser = new MermaidPieParser();
    var diagram = parser.parse(source);

    assert(!diagram.has_errors());
    assert(diagram.title == "Data Distribution");
    assert(diagram.slices.size == 3);

    double total = diagram.get_total();
    assert(total == 100.0);

    print("  Title: %s\n", diagram.title);
    print("  Slices: %d\n", diagram.slices.size);
    print("  Total: %.0f\n", total);
    print("✓ Pie parsing works\n\n");
}

void test_pie_percentages() {
    print("=== Pie Percentages Test ===\n");

    string source = """pie
    \"A\" : 50
    \"B\" : 30
    \"C\" : 20
""";

    var parser = new MermaidPieParser();
    var diagram = parser.parse(source);

    double total = diagram.get_total();
    var slice_a = diagram.slices.get(0);

    double percentage = slice_a.get_percentage(total);
    assert(percentage == 50.0);

    print("  Slice A percentage: %.1f%%\n", percentage);
    print("✓ Percentage calculation correct\n\n");
}

void test_pie_rendering() {
    print("=== Pie Rendering Test ===\n");

    string source = """pie
    \"Product 1\" : 40
    \"Product 2\" : 35
    \"Product 3\" : 25
""";

    var parser = new MermaidPieParser();
    var diagram = parser.parse(source);

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidPieRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph"));
    assert(dot.contains("Product 1"));

    print("  DOT generated successfully\n");
    print("✓ Pie rendering works\n\n");
}

int main(string[] args) {
    print("\n=== Gantt & Pie Test Suite ===\n\n");

    test_gantt_basic();
    test_gantt_rendering();
    test_pie_basic();
    test_pie_percentages();
    test_pie_rendering();

    print("=== All Gantt & Pie tests passed! ===\n\n");

    return 0;
}
