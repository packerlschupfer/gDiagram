/*
 * template_health_test.vala — every built-in template must parse cleanly.
 *
 * Iterates DiagramTemplates.get_template_names() and feeds each template
 * through its matching parser. Fails on any parse error, empty diagram,
 * or unknown template name.
 *
 * Would have caught the Kanban template regression where the gallery
 * template used indent=2 for columns but the parser requires indent=0.
 */
using GDiagram;

// Shared error reporting: print the template name and the first parse
// error (or the is_empty reason) before aborting.
void fail_template(string name, string reason) {
    stderr.printf("[template] %s — %s\n", name, reason);
    assert_not_reached();
}

// ------- Mermaid -------
void check_mermaid_template(string name, string source) {
    switch (name) {
        case "mermaid-flowchart":
        case "mermaid-flowchart-styled":
            var d = new MermaidFlowchartParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.nodes.size == 0) fail_template(name, "empty — no nodes parsed");
            break;
        case "mermaid-sequence":
        case "mermaid-sequence-loops":
            var d = new MermaidSequenceParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.messages.size == 0 && d.actors.size == 0)
                fail_template(name, "empty — no actors or messages");
            break;
        case "mermaid-state":
            var d = new MermaidStateParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.states.size == 0) fail_template(name, "empty — no states");
            break;
        case "mermaid-class":
            var d = new MermaidClassParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.classes.size == 0) fail_template(name, "empty — no classes");
            break;
        case "mermaid-er":
            var d = new MermaidERParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.entities.size == 0) fail_template(name, "empty — no entities");
            break;
        case "mermaid-gantt":
            var d = new MermaidGanttParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.tasks.size == 0) fail_template(name, "empty — no tasks");
            break;
        case "mermaid-pie":
            var d = new MermaidPieParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.slices.size == 0) fail_template(name, "empty — no slices");
            break;
        case "mermaid-user-journey":
            var d = new MermaidUserJourneyParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.all_tasks.size == 0) fail_template(name, "empty — no tasks");
            break;
        case "mermaid-git-graph":
            var d = new MermaidGitGraphParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.all_commits.size == 0) fail_template(name, "empty — no commits");
            break;
        case "mermaid-mindmap":
            var d = new MermaidMindmapParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no root");
            break;
        case "mermaid-timeline":
            var d = new MermaidTimelineParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no periods");
            break;
        case "mermaid-quadrant":
            var d = new MermaidQuadrantParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no points");
            break;
        case "mermaid-xychart":
            var d = new MermaidXYChartParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no series");
            break;
        case "mermaid-kanban":
            var d = new MermaidKanbanParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no columns");
            break;
        case "mermaid-sankey":
            var d = new MermaidSankeyParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no links");
            break;
        case "mermaid-requirement":
            var d = new MermaidRequirementParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no elements");
            break;
        case "mermaid-block":
            var d = new MermaidBlockParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no blocks");
            break;
        case "mermaid-packet":
            var d = new MermaidPacketParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no fields");
            break;
        case "mermaid-c4":
            var d = new MermaidC4Parser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no elements");
            break;
        case "mermaid-architecture":
            var d = new MermaidArchitectureParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no services");
            break;
        case "mermaid-zenuml":
            var d = new MermaidZenUMLParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no messages");
            break;
        case "mermaid-radar":
            var d = new MermaidRadarParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no axes");
            break;
        case "mermaid-treemap":
            var d = new MermaidTreemapParser().parse(source);
            if (d.has_errors()) fail_template(name, first_error(d.errors));
            if (d.is_empty()) fail_template(name, "empty — no roots");
            break;
        default:
            fail_template(name, "no parser wired for this template");
            break;
    }
}

string first_error(Gee.ArrayList<ParseError> errors) {
    if (errors.size == 0) return "unknown error";
    var e = errors.get(0);
    return "line %d: %s".printf(e.line, e.message);
}

// ------- Test entries -------

void test_all_mermaid_templates_parse() {
    foreach (var name in DiagramTemplates.get_mermaid_template_names()) {
        string? source = DiagramTemplates.get_template(name);
        if (source == null) {
            fail_template(name, "get_template returned null");
            continue;
        }
        check_mermaid_template(name, source);
    }
}

void test_get_template_names_is_non_empty() {
    var names = DiagramTemplates.get_template_names();
    assert(names.length > 0);
    // Spot-check: a few well-known names resolve.
    assert(DiagramTemplates.get_template("mermaid-flowchart") != null);
    assert(DiagramTemplates.get_template("mermaid-kanban") != null);
    assert(DiagramTemplates.get_template("plantuml-class") != null);
}

void test_every_name_resolves() {
    foreach (var name in DiagramTemplates.get_template_names()) {
        string? source = DiagramTemplates.get_template(name);
        if (source == null) {
            fail_template(name, "listed by get_template_names but get_template returned null");
        }
    }
}

void test_descriptions_are_non_default() {
    foreach (var name in DiagramTemplates.get_template_names()) {
        string desc = DiagramTemplates.get_template_description(name);
        if (desc == "Diagram template" || desc.length == 0) {
            fail_template(name, "generic/empty description");
        }
    }
}

int main(string[] args) {
    Test.init(ref args);
    // Force DiagramTemplates class_init to run so its static string fields
    // are initialized before any static method call. Without this,
    // accessing DiagramTemplates.FLOWCHART_BASIC returns null because
    // Vala stores initial values in a class struct that only gets
    // populated once g_type_class_ref() has fired for the type.
    var _init = new DiagramTemplates();
    if (_init == null) return 1;  // unreachable; keeps _init from being optimised out

    Test.add_func("/template/all_mermaid_parse", test_all_mermaid_templates_parse);
    Test.add_func("/template/names_not_empty",   test_get_template_names_is_non_empty);
    Test.add_func("/template/every_name_resolves", test_every_name_resolves);
    Test.add_func("/template/descriptions_non_default", test_descriptions_are_non_default);
    return Test.run();
}
