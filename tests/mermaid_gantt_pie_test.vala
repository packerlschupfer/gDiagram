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
    assert(dot.contains("graph pie"));
    assert(dot.contains("Product 1"));
}

/**
 * Mermaid's getStartDate falls back to `new Date(string)` when the strict
 * dateFormat parse fails, and that parser only enforces the ranges the ISO
 * grammar spells out — it never checks the day against its month. So Mermaid
 * renders "2024-02-30" as 1 March and "0000-01-01" as year 0, while gDiagram
 * rejected both (and "0000-01-01" also reached g_date_get_days_in_month() with
 * year 0 and logged a GLib critical). A month past 12 or a day past 31 has no
 * ISO reading and stays invalid for both.
 */
void test_gantt_date_rollover_matches_dayjs() {
    // Compared through the same branch: a rolled-over date is the date it rolls to.
    // (The two branches differ by the UTC offset, in Mermaid exactly as here — the
    // strict dayjs parse is local, `new Date(string)` is UTC.)
    int64 feb30, mar1, feb31, mar2, zero, ignored;
    assert(MermaidGanttTime.parse_js_date("2024-02-30", out feb30));
    assert(MermaidGanttTime.parse_js_date("2024-03-01", out mar1));
    assert(feb30 == mar1);
    assert(MermaidGanttTime.parse_js_date("2024-02-31", out feb31));
    assert(MermaidGanttTime.parse_js_date("2024-03-02", out mar2));
    assert(feb31 == mar2);

    // Year 0 is a real instant in JS; GLib's DateTime starts at year 1, so it is
    // pinned to the earliest instant that can be drawn rather than refused.
    assert(MermaidGanttTime.parse_start("0000-01-01", "YYYY-MM-DD", out zero));
    assert(zero == MermaidGanttTime.MIN_MS);

    assert(!MermaidGanttTime.parse_start("2024-13-01", "YYYY-MM-DD", out ignored));
    assert(!MermaidGanttTime.parse_start("2024-01-32", "YYYY-MM-DD", out ignored));

    // The strict dateFormat parse itself keeps dayjs's strict rules: no rollover.
    assert(!MermaidGanttTime.parse_format("2024-02-30", "YYYY-MM-DD", out ignored));
    assert(!MermaidGanttTime.parse_format("0000-01-01", "YYYY-MM-DD", out ignored));

    // End to end: the task schedules, so the file exports instead of exiting 1.
    // No dateFormat, so both dates take the `new Date(string)` branch.
    string doc = "gantt\n    section S\n    A :a1, %s, 3d\n";
    var rolled = new MermaidGanttParser().parse(doc.printf("2024-02-30"));
    var plain = new MermaidGanttParser().parse(doc.printf("2024-03-01"));
    assert(!rolled.has_errors());
    assert(rolled.tasks.size == 1 && plain.tasks.size == 1);
    assert(rolled.tasks.get(0).start_ms == plain.tasks.get(0).start_ms);
    assert(rolled.tasks.get(0).end_ms == plain.tasks.get(0).end_ms);

    var year_zero = new MermaidGanttParser().parse(doc.printf("0000-01-01"));
    assert(!year_zero.has_errors());
    assert(year_zero.tasks.get(0).start_ms == MermaidGanttTime.MIN_MS);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/mermaid/gantt/basic", test_gantt_basic);
    Test.add_func("/mermaid/gantt/date-rollover", test_gantt_date_rollover_matches_dayjs);
    Test.add_func("/mermaid/gantt/rendering", test_gantt_rendering);
    Test.add_func("/mermaid/pie/basic", test_pie_basic);
    Test.add_func("/mermaid/pie/percentages", test_pie_percentages);
    Test.add_func("/mermaid/pie/rendering", test_pie_rendering);
    return Test.run();
}
