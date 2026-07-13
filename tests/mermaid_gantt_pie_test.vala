using GDiagram;

void test_gantt_basic() {
    var parser = new MermaidGanttParser();
    var diagram = parser.parse("""gantt
    title Project Schedule
    section Planning
    Requirements : done, 5d
    Design : active, 7d
""");

    assert(!diagram.has_errors());
    assert(diagram.title == "Project Schedule");
    assert(diagram.tasks.size >= 2);
    assert(diagram.sections.size == 1);
}

void test_gantt_rendering() {
    var parser = new MermaidGanttParser();
    var diagram = parser.parse("""gantt
    Task 1 : done, 3d
    Task 2 : active, 5d
""");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidGanttRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph"));
    assert(dot.contains("Task 1"));
}

void test_pie_basic() {
    var parser = new MermaidPieParser();
    var diagram = parser.parse(
        "pie title Data Distribution\n" +
        "    \"Category A\" : 45\n" +
        "    \"Category B\" : 30\n" +
        "    \"Category C\" : 25\n");

    assert(!diagram.has_errors());
    assert(diagram.title == "Data Distribution");
    assert(diagram.slices.size == 3);
    assert(diagram.get_total() == 100.0);
}

void test_pie_percentages() {
    var parser = new MermaidPieParser();
    var diagram = parser.parse(
        "pie\n" +
        "    \"A\" : 50\n" +
        "    \"B\" : 30\n" +
        "    \"C\" : 20\n");

    double total = diagram.get_total();
    double percentage = diagram.slices.get(0).get_percentage(total);
    assert(percentage == 50.0);
}

void test_pie_rendering() {
    var parser = new MermaidPieParser();
    var diagram = parser.parse(
        "pie\n" +
        "    \"Product 1\" : 40\n" +
        "    \"Product 2\" : 35\n" +
        "    \"Product 3\" : 25\n");

    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    var renderer = new MermaidPieRenderer(ctx, regions, "dot");

    string dot = renderer.generate_dot(diagram);
    assert(dot.contains("digraph"));
    assert(dot.contains("Product 1"));
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/mermaid/gantt/basic", test_gantt_basic);
    Test.add_func("/mermaid/gantt/rendering", test_gantt_rendering);
    Test.add_func("/mermaid/pie/basic", test_pie_basic);
    Test.add_func("/mermaid/pie/percentages", test_pie_percentages);
    Test.add_func("/mermaid/pie/rendering", test_pie_rendering);
    return Test.run();
}
