/*
 * examples_health_test.vala — every shipped example file must detect
 * and parse cleanly.
 *
 * Walks examples/ under the project root, runs each .puml / .mmd file
 * through the TypeDetector dispatch that DocumentView uses, and then
 * feeds it to the matching parser. This is the integration layer
 * between "file on disk" and "AST" — regressions here are what
 * users actually see when they open example files from the gallery.
 *
 * Scope:
 *  - 67 Mermaid examples: format + type detection, then parser dispatch
 *    with non-empty / no-errors assertions (covers all 24 Mermaid types)
 *  - 298 PlantUML examples: format + type detection + lexer smoke test
 *    (asserts every file is recognized and tokenizes without crashing)
 *
 * What it catches that existing tests don't:
 *  - Regressions on real-world user content (not just curated snippets)
 *  - TypeDetector drift: a change that misclassifies a whole category
 *  - Parser crashes or infinite loops on specific example files
 *  - Files that become unrecognizable after refactoring detection logic
 *
 * Not covered (requires GTK widget scaffolding — out of scope):
 *  - Live DocumentView debouncer + source-buffer wiring
 *  - Outline list population via row_activated
 *  - Preview pane click-to-source region mapping
 */
using GDiagram;

int fail_count = 0;
int pass_count = 0;

// Print a failure but keep going so we see every broken example in one run.
void record_fail(string path, string reason) {
    stderr.printf("[examples] FAIL %s — %s\n", path, reason);
    fail_count++;
}

void record_pass() {
    pass_count++;
}

// ────────────────────────────────────────────────────────────────
// File discovery
// ────────────────────────────────────────────────────────────────

void collect_files(File dir, string extension, Gee.ArrayList<string> out_paths) {
    try {
        var enumerator = dir.enumerate_children(
            "standard::name,standard::type",
            FileQueryInfoFlags.NONE
        );
        FileInfo info;
        while ((info = enumerator.next_file()) != null) {
            var child = dir.resolve_relative_path(info.get_name());
            if (info.get_file_type() == FileType.DIRECTORY) {
                collect_files(child, extension, out_paths);
            } else if (info.get_name().has_suffix(extension)) {
                out_paths.add(child.get_path());
            }
        }
    } catch (Error e) {
        stderr.printf("[examples] warning: could not enumerate %s: %s\n",
                      dir.get_path(), e.message);
    }
}

string? read_file(string path) {
    try {
        string contents;
        FileUtils.get_contents(path, out contents);
        return contents;
    } catch (Error e) {
        return null;
    }
}

// ────────────────────────────────────────────────────────────────
// Mermaid parser dispatch — mirrors DocumentView.render_mermaid_diagram
// ────────────────────────────────────────────────────────────────

string first_error(Gee.ArrayList<ParseError> errors) {
    if (errors.size == 0) return "unknown error";
    var e = errors.get(0);
    return "line %d: %s".printf(e.line, e.message);
}

void check_mermaid_parse(string path, DiagramType type, string source) {
    switch (type) {
        case DiagramType.MERMAID_FLOWCHART: {
            var d = new MermaidFlowchartParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.nodes.size == 0) { record_fail(path, "flowchart: no nodes"); return; }
            break;
        }
        case DiagramType.MERMAID_SEQUENCE: {
            var d = new MermaidSequenceParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.messages.size == 0 && d.actors.size == 0) {
                record_fail(path, "sequence: no actors or messages"); return;
            }
            break;
        }
        case DiagramType.MERMAID_STATE: {
            var d = new MermaidStateParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.states.size == 0) { record_fail(path, "state: no states"); return; }
            break;
        }
        case DiagramType.MERMAID_CLASS: {
            var d = new MermaidClassParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.classes.size == 0) { record_fail(path, "class: no classes"); return; }
            break;
        }
        case DiagramType.MERMAID_ER: {
            var d = new MermaidERParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.entities.size == 0) { record_fail(path, "er: no entities"); return; }
            break;
        }
        case DiagramType.MERMAID_GANTT: {
            var d = new MermaidGanttParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.tasks.size == 0) { record_fail(path, "gantt: no tasks"); return; }
            break;
        }
        case DiagramType.MERMAID_PIE: {
            var d = new MermaidPieParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.slices.size == 0) { record_fail(path, "pie: no slices"); return; }
            break;
        }
        case DiagramType.MERMAID_USER_JOURNEY: {
            var d = new MermaidUserJourneyParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.all_tasks.size == 0) { record_fail(path, "journey: no tasks"); return; }
            break;
        }
        case DiagramType.MERMAID_GIT_GRAPH: {
            var d = new MermaidGitGraphParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.all_commits.size == 0) { record_fail(path, "gitgraph: no commits"); return; }
            break;
        }
        case DiagramType.MERMAID_MINDMAP: {
            var d = new MermaidMindmapParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "mindmap: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_TIMELINE: {
            var d = new MermaidTimelineParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "timeline: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_QUADRANT: {
            var d = new MermaidQuadrantParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "quadrant: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_XYCHART: {
            var d = new MermaidXYChartParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "xychart: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_KANBAN: {
            var d = new MermaidKanbanParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "kanban: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_SANKEY: {
            var d = new MermaidSankeyParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "sankey: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_REQUIREMENT: {
            var d = new MermaidRequirementParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "requirement: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_BLOCK: {
            var d = new MermaidBlockParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "block: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_PACKET: {
            var d = new MermaidPacketParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "packet: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_C4: {
            var d = new MermaidC4Parser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "c4: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_ARCHITECTURE: {
            var d = new MermaidArchitectureParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "architecture: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_ZENUML: {
            var d = new MermaidZenUMLParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "zenuml: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_RADAR: {
            var d = new MermaidRadarParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "radar: empty"); return; }
            break;
        }
        case DiagramType.MERMAID_TREEMAP: {
            var d = new MermaidTreemapParser().parse(source);
            if (d.has_errors()) { record_fail(path, first_error(d.errors)); return; }
            if (d.is_empty()) { record_fail(path, "treemap: empty"); return; }
            break;
        }
        default:
            record_fail(path, "no parser wired for type %d".printf((int)type));
            return;
    }
    record_pass();
}

// ────────────────────────────────────────────────────────────────
// Test entry points
// ────────────────────────────────────────────────────────────────

string examples_root() {
    string? env = Environment.get_variable("GDIAGRAM_EXAMPLES_ROOT");
    if (env != null && env.length > 0) return env;
    stderr.printf("[examples] GDIAGRAM_EXAMPLES_ROOT not set\n");
    assert_not_reached();
}

void test_mermaid_examples() {
    string root = examples_root() + "/mermaid";
    var paths = new Gee.ArrayList<string>();
    collect_files(File.new_for_path(root), ".mmd", paths);

    if (paths.size == 0) {
        stderr.printf("[examples] no .mmd files found under %s\n", root);
        assert_not_reached();
    }

    int local_fails = fail_count;
    foreach (var path in paths) {
        string? source = read_file(path);
        if (source == null) { record_fail(path, "could not read file"); continue; }
        if (!TypeDetector.is_mermaid(source)) {
            record_fail(path, "TypeDetector.is_mermaid returned false");
            continue;
        }
        var type = TypeDetector.detect_mermaid(source);
        if (type == DiagramType.UNKNOWN) {
            record_fail(path, "TypeDetector.detect_mermaid returned UNKNOWN");
            continue;
        }
        check_mermaid_parse(path, type, source);
    }
    stderr.printf("[examples] mermaid: %d files, %d failures\n",
                  paths.size, fail_count - local_fails);
    if (fail_count > local_fails) assert_not_reached();
}

void test_plantuml_examples() {
    string root = examples_root() + "/plantuml";
    var paths = new Gee.ArrayList<string>();
    collect_files(File.new_for_path(root), ".puml", paths);

    if (paths.size == 0) {
        stderr.printf("[examples] no .puml files found under %s\n", root);
        assert_not_reached();
    }

    int local_fails = fail_count;
    foreach (var path in paths) {
        string? source = read_file(path);
        if (source == null) { record_fail(path, "could not read file"); continue; }

        // These files are fragments meant to be !include'd from a parent
        // diagram. They intentionally don't carry their own @start marker
        // so detection can't classify them. Skip.
        if (!source.contains("@start")) continue;

        if (TypeDetector.is_mermaid(source)) {
            record_fail(path, "PlantUML file misdetected as Mermaid");
            continue;
        }
        var type = TypeDetector.detect_plantuml(source);
        if (type == DiagramType.UNKNOWN) {
            record_fail(path, "TypeDetector.detect_plantuml returned UNKNOWN");
            continue;
        }

        // Lexer smoke test: tokenize without crashing. Catches infinite
        // loops, null-deref on certain tokens, and regex misbehavior.
        var lexer = new Lexer(source);
        var tokens = lexer.scan_all();
        if (tokens == null || tokens.size == 0) {
            record_fail(path, "lexer produced no tokens"); continue;
        }
        record_pass();
    }
    stderr.printf("[examples] plantuml: %d files, %d failures\n",
                  paths.size, fail_count - local_fails);
    if (fail_count > local_fails) assert_not_reached();
}

void test_summary() {
    stderr.printf("[examples] total: %d passed, %d failed\n", pass_count, fail_count);
    assert(pass_count > 0);
    assert(fail_count == 0);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/examples/mermaid_parse", test_mermaid_examples);
    Test.add_func("/examples/plantuml_detect_and_lex", test_plantuml_examples);
    Test.add_func("/examples/summary", test_summary);
    return Test.run();
}
