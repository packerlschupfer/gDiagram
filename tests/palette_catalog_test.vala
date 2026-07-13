/*
 * palette_catalog_test.vala — every element palette snippet must parse.
 *
 * Each entry is inserted into a minimal diagram of its group's type (General
 * entries into every type of their format) and run through
 * DiagramEngine.parse(). The detected type must be the intended one — type
 * detection is content-based, so a snippet can silently route the file to a
 * different parser — and there must be no parse errors.
 *
 * Set GDIAGRAM_PALETTE_DUMP=<dir> to write every composed source there, for
 * checking against the reference PlantUML jar.
 */
using GDiagram;

const string MARK = "%SNIPPET%";

// Minimal diagram per group; the snippet replaces the marker line.
string base_for(PaletteGroup? group, DiagramType type) {
    if (group != null && group.name == "C4") {
        return "@startuml\n!include <C4/C4_Container>\nPerson(user, \"User\")\nSystem(sys, \"System\")\n" +
               MARK + "\n@enduml\n";
    }
    if (group != null && group.format == DiagramFormat.PLANTUML && type == DiagramType.MERMAID_PACKET) {
        return "@startpacketdiag\n" + MARK + "\n@endpacketdiag\n";
    }
    switch (type) {
        case DiagramType.SEQUENCE:
            return "@startuml\nparticipant Alice\nparticipant Bob\n" + MARK + "\n@enduml\n";
        case DiagramType.CLASS:
            return "@startuml\nclass ClassA\nclass ClassB\n" + MARK + "\n@enduml\n";
        case DiagramType.USECASE:
            return "@startuml\nactor ActorName\nusecase \"Use case\" as UC\n" + MARK + "\n@enduml\n";
        case DiagramType.ACTIVITY:
            return "@startuml\nstart\n:Step;\n" + MARK + "\nstop\n@enduml\n";
        case DiagramType.STATE:
            return "@startuml\n[*] --> StateA\n" + MARK + "\n@enduml\n";
        case DiagramType.COMPONENT:
            return "@startuml\ncomponent ComponentA\n" + MARK + "\n@enduml\n";
        case DiagramType.OBJECT:
            return "@startuml\nobject ObjectA\n" + MARK + "\n@enduml\n";
        case DiagramType.ER_DIAGRAM:
            return "@startuml\nentity EntityA\nentity EntityB\n" + MARK + "\n@enduml\n";
        case DiagramType.MINDMAP:
            return "@startmindmap\n* Root\n" + MARK + "\n@endmindmap\n";
        case DiagramType.GANTT:
            return "@startgantt\nProject starts 2026-01-05\n[Task A] requires 5 days\n[Task B] requires 2 days\n" +
                   MARK + "\n@endgantt\n";
        case DiagramType.TIMING:
            return "@startuml\nconcise \"User\" as U\n@0\nU is Idle\n" + MARK + "\n@enduml\n";
        case DiagramType.BOARD:
            return "@startboard\nBacklog\n+ Task\n" + MARK + "\n@endboard\n";
        case DiagramType.CHEN_ER:
            return "@startchen\nentity Person {\n  Name\n}\n" + MARK + "\n@endchen\n";
        case DiagramType.EBNF:
            return "@startebnf\nletter = \"a\" | \"b\" ;\n" + MARK + "\n@endebnf\n";
        case DiagramType.REGEX_DIAGRAM:
            return "@startregex\n" + MARK + "\n@endregex\n";
        case DiagramType.SALT:
            return "@startsalt\n" + MARK + "\n@endsalt\n";
        case DiagramType.DITAA:
            return "@startditaa\n" + MARK + "\n@endditaa\n";
        case DiagramType.NWDIAG:
            return "@startnwdiag\n" + MARK + "\n@endnwdiag\n";
        case DiagramType.ARCHIMATE:
            return "@startuml\narchimate #Business \"Owner\" as owner <<business-role>>\n" + MARK + "\n@enduml\n";
        case DiagramType.CHRONOLOGY:
            return "@startchronology\n[Kickoff] happens on 2026-01-05\n" + MARK + "\n@endchronology\n";
        case DiagramType.MERMAID_FLOWCHART:
            return "flowchart TD\n    A[Start] --> B[End]\n" + MARK + "\n";
        case DiagramType.MERMAID_SEQUENCE:
            return "sequenceDiagram\n    participant Alice\n    participant Bob\n" + MARK + "\n";
        case DiagramType.MERMAID_CLASS:
            return "classDiagram\n    class ClassA\n" + MARK + "\n";
        case DiagramType.MERMAID_STATE:
            return "stateDiagram-v2\n    [*] --> StateA\n" + MARK + "\n";
        case DiagramType.MERMAID_ER:
            return "erDiagram\n    CUSTOMER ||--o{ ORDER : places\n" + MARK + "\n";
        case DiagramType.MERMAID_GANTT:
            return "gantt\n    dateFormat YYYY-MM-DD\n    section Work\n    Task A :a1, 2026-01-05, 5d\n" + MARK + "\n";
        default:
            assert_not_reached();
    }
}

// Known detection reroutes, which the test asserts instead of the group type.
// - PlantUML itself draws IE crow's-foot links in class diagrams; gDiagram's
//   detector treats "o--" / "--o" as class arrows, so links with a zero-or end
//   go to the class parser (which understands entities and crow's feet).
DiagramType expected_type(PaletteEntry entry, DiagramType base_type) {
    if (base_type == DiagramType.ER_DIAGRAM &&
        (entry.snippet.contains("--o") || entry.snippet.contains("o--"))) {
        return DiagramType.CLASS;
    }
    return base_type;
}

string compose(PaletteGroup group, PaletteEntry entry, DiagramType base_type) {
    string indent = group.format == DiagramFormat.MERMAID ? "    " : "";
    var sb = new StringBuilder();
    foreach (string line in entry.snippet.split("\n")) {
        if (sb.len > 0) sb.append_c('\n');
        sb.append(indent + line);
    }
    string base_source = base_for(group.diagram_type == DiagramType.UNKNOWN ? null : group, base_type);
    // The C4 include entry takes the place of the base's own include
    if (entry.snippet.has_prefix("!include")) {
        base_source = base_source.replace("\n" + MARK + "\n", "\n").replace("!include <C4/C4_Container>", MARK);
    }
    return base_source.replace(MARK, sb.str);
}

// Parse `source` and describe the problem, or return null if it is clean.
string? check_source(DiagramEngine engine, string source, DiagramType expected) {
    var result = engine.parse(source, null);
    if (result.diagram_type != expected) {
        return "detected %s, expected %s".printf(result.diagram_type.to_string(), expected.to_string());
    }
    if (result.errors != null && result.errors.size > 0) {
        return "parse error: " + result.errors[0].to_string();
    }
    if (result.ast == null) {
        return "no AST";
    }
    return null;
}

// Render `source` the way the GUI does; describe the failure or return null.
string? check_render(DiagramEngine engine, string source, DiagramType type, DiagramFormat format) {
    string text = format == DiagramFormat.PLANTUML ? engine.preprocess(source, null) : source;
    var result = engine.render(type, format, text);
    if (result.status != RenderStatus.OK) {
        return "render status %s: %s".printf(result.status.to_string(), result.message);
    }
    if (result.surface == null) {
        return "render produced no image: " + result.fail_message;
    }
    return null;
}

// Whole-document types (their own @start tag or a single block) take no General entries
bool takes_general_entries(DiagramType type) {
    switch (type) {
        case DiagramType.BOARD: case DiagramType.CHEN_ER: case DiagramType.EBNF:
        case DiagramType.REGEX_DIAGRAM: case DiagramType.SALT: case DiagramType.DITAA:
        case DiagramType.MERMAID_PACKET: case DiagramType.NWDIAG: case DiagramType.ARCHIMATE:
        case DiagramType.CHRONOLOGY:
            return false;
        default:
            return true;
    }
}

int dump_counter = 0;

void dump(string source, DiagramFormat format) {
    string? dir = Environment.get_variable("GDIAGRAM_PALETTE_DUMP");
    if (dir == null) return;
    string ext = format == DiagramFormat.MERMAID ? "mmd" : "puml";
    string path = Path.build_filename(dir, "%03d.%s".printf(dump_counter++, ext));
    try {
        FileUtils.set_contents(path, source);
    } catch (FileError e) {
        stderr.printf("dump failed: %s\n", e.message);
    }
}

Gee.ArrayList<DiagramType> group_types(DiagramFormat format) {
    var types = new Gee.ArrayList<DiagramType>();
    foreach (var group in PaletteCatalog.get_groups()) {
        if (group.format == format && group.diagram_type != DiagramType.UNKNOWN &&
            !types.contains(group.diagram_type)) {
            types.add(group.diagram_type);
        }
    }
    return types;
}

// Insert every entry of `format` and report all failures at once.
void check_format(DiagramFormat format) {
    var engine = new DiagramEngine("dot");
    int checked = 0;
    var failures = new StringBuilder();
    foreach (var group in PaletteCatalog.get_groups()) {
        if (group.format != format) continue;
        var base_types = new Gee.ArrayList<DiagramType>();
        if (group.diagram_type == DiagramType.UNKNOWN) {
            foreach (var t in group_types(format)) {
                if (takes_general_entries(t)) base_types.add(t);
            }
        } else {
            base_types.add(group.diagram_type);
        }
        foreach (var entry in group.entries) {
            foreach (var base_type in base_types) {
                string source = compose(group, entry, base_type);
                dump(source, format);
                DiagramType expected = expected_type(entry, base_type);
                string? problem = check_source(engine, source, expected);
                if (problem == null) {
                    problem = check_render(engine, source, expected, format);
                }
                checked++;
                if (problem != null) {
                    failures.append("  [%s / %s in %s] %s\n".printf(group.name, entry.label,
                        base_type.to_string(), problem));
                }
            }
        }
    }
    if (failures.len > 0) {
        stderr.printf("\nPalette snippet failures:\n%s", failures.str);
        Test.fail();
    }
    // Guard against a vacuous pass (no entries iterated)
    assert(checked > 50);
    Test.message("%d snippet insertions checked", checked);
}

void test_plantuml_snippets() {
    check_format(DiagramFormat.PLANTUML);
}

void test_mermaid_snippets() {
    check_format(DiagramFormat.MERMAID);
}

void test_entries_well_formed() {
    foreach (var group in PaletteCatalog.get_groups()) {
        assert(group.entries.size > 0);
        foreach (var entry in group.entries) {
            assert(entry.label.length > 0);
            assert(entry.icon_name.has_suffix("-symbolic"));
            assert(entry.snippet.strip().length > 0);
            if (entry.select != null) {
                assert(entry.snippet.contains(entry.select));
            }
        }
    }
}

void test_required_groups() {
    DiagramType[] required = {
        DiagramType.SEQUENCE, DiagramType.CLASS, DiagramType.USECASE, DiagramType.ACTIVITY,
        DiagramType.STATE, DiagramType.COMPONENT, DiagramType.OBJECT,
        DiagramType.ER_DIAGRAM, DiagramType.MINDMAP, DiagramType.GANTT, DiagramType.TIMING,
        DiagramType.MERMAID_FLOWCHART, DiagramType.MERMAID_SEQUENCE, DiagramType.MERMAID_CLASS,
        DiagramType.MERMAID_STATE, DiagramType.MERMAID_ER, DiagramType.MERMAID_GANTT
    };
    foreach (var type in required) {
        assert(group_types(DiagramFormat.PLANTUML).contains(type) ||
               group_types(DiagramFormat.MERMAID).contains(type));
    }
    int general = 0;
    foreach (var group in PaletteCatalog.get_groups()) {
        if (group.diagram_type == DiagramType.UNKNOWN) general++;
    }
    assert(general == 2);
}

void test_relevance() {
    foreach (var group in PaletteCatalog.get_groups()) {
        int rank = PaletteCatalog.relevance(group, DiagramType.COMPONENT, DiagramFormat.PLANTUML);
        if (group.format == DiagramFormat.MERMAID) {
            assert(rank == 4);
        } else if (group.diagram_type == DiagramType.COMPONENT) {
            assert(rank == 0);
        } else if (group.diagram_type == DiagramType.UNKNOWN) {
            assert(rank == 2);
        } else {
            assert(rank == 3);
        }
    }
}

// Inserting into an empty editor wraps the snippet in a document of its type
void test_wrap_document() {
    var engine = new DiagramEngine("dot");
    string puml = PaletteCatalog.wrap_document("class Foo", DiagramType.CLASS);
    assert(puml == "@startuml\nclass Foo\n@enduml\n");
    assert(check_source(engine, puml, DiagramType.CLASS) == null);

    string mindmap = PaletteCatalog.wrap_document("* Root\n** Child", DiagramType.MINDMAP);
    assert(mindmap.has_prefix("@startmindmap\n"));
    assert(check_source(engine, mindmap, DiagramType.MINDMAP) == null);

    string mmd = PaletteCatalog.wrap_document("A --> B", DiagramType.MERMAID_FLOWCHART);
    assert(mmd == "flowchart TD\n    A --> B\n");
    assert(check_source(engine, mmd, DiagramType.MERMAID_FLOWCHART) == null);

    string seq = PaletteCatalog.wrap_document("Alice->>Bob: hi", DiagramType.MERMAID_SEQUENCE);
    assert(check_source(engine, seq, DiagramType.MERMAID_SEQUENCE) == null);

    // Whole-document types get their own @start tag
    string board = PaletteCatalog.wrap_document("Todo\n+ Card", DiagramType.BOARD);
    assert(board.has_prefix("@startboard\n"));
    assert(check_source(engine, board, DiagramType.BOARD) == null);
    string regex = PaletteCatalog.wrap_document("[a-z]+", DiagramType.REGEX_DIAGRAM);
    assert(check_source(engine, regex, DiagramType.REGEX_DIAGRAM) == null);
    string packet = PaletteCatalog.wrap_document("packetdiag {\n  0-15: Port\n}", DiagramType.MERMAID_PACKET,
                                                 DiagramFormat.PLANTUML);
    assert(packet.has_prefix("@startpacketdiag\n"));
    assert(check_source(engine, packet, DiagramType.MERMAID_PACKET) == null);
}

// Every group added for the newly supported syntax is present with its key entries
void test_new_syntax_groups() {
    string[] required = {
        "Timing/Analog signal", "Timing/Constraint", "Timing/Highlight", "Timing/Anchor",
        "Gantt/Separator", "Gantt/Resources", "Gantt/Then", "Gantt/Closed date",
        "C4/Person", "C4/System", "C4/Container", "C4/Relationship", "C4/Boundary", "C4/Legend",
        "Sequence/Autoactivate", "Sequence/Call with return", "Sequence/New page",
        "Sequence/Hexagonal note", "Sequence/Incoming message",
        "State/Concurrent regions", "State/History", "State/Entry and exit points",
        "Class/Association class", "Class/Lollipop interface",
        "Component/Ports", "Component/Legend", "Activity/Split", "Activity/End",
        "Board/Column", "Chen ER/Entity", "EBNF/Rule", "Regex/Regular expression", "Salt/Form",
        "Ditaa/Boxes", "Packet/Packet", "Network/Network", "ArchiMate/Business actor"
    };
    foreach (string key in required) {
        bool found = false;
        foreach (var group in PaletteCatalog.get_groups()) {
            if (group.format != DiagramFormat.PLANTUML) continue;
            foreach (var entry in group.entries) {
                if (group.name + "/" + entry.label == key) found = true;
            }
        }
        if (!found) {
            stderr.printf("missing palette entry %s\n", key);
            Test.fail();
        }
    }
}

// Groups do not move under the pointer: a type change waits until it leaves the palette
void test_order_policy() {
    var policy = new PaletteOrderPolicy();
    assert(policy.request(DiagramType.SEQUENCE, DiagramFormat.PLANTUML));
    assert(policy.applied_type == DiagramType.SEQUENCE);
    // Same type again (every render): no reorder
    assert(!policy.request(DiagramType.SEQUENCE, DiagramFormat.PLANTUML));

    // A click inserts a snippet that changes the detected type: nothing moves yet
    policy.pointer_entered();
    assert(!policy.request(DiagramType.COMPONENT, DiagramFormat.PLANTUML));
    assert(!policy.request(DiagramType.CLASS, DiagramFormat.PLANTUML));
    assert(policy.applied_type == DiagramType.SEQUENCE);
    // Leaving applies the latest type once
    assert(policy.pointer_left());
    assert(policy.applied_type == DiagramType.CLASS);
    assert(!policy.pointer_left());

    // Back to the applied type while inside: the waiting change is dropped
    policy.pointer_entered();
    assert(!policy.request(DiagramType.STATE, DiagramFormat.PLANTUML));
    assert(!policy.request(DiagramType.CLASS, DiagramFormat.PLANTUML));
    assert(!policy.pointer_left());

    // An undetectable document mid-edit keeps the order
    assert(!policy.request(DiagramType.UNKNOWN, DiagramFormat.UNKNOWN));
    assert(policy.applied_type == DiagramType.CLASS);
    // Outside the palette a real change applies at once
    assert(policy.request(DiagramType.MERMAID_FLOWCHART, DiagramFormat.MERMAID));
    assert(policy.applied_format == DiagramFormat.MERMAID);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/palette/entries-well-formed", test_entries_well_formed);
    Test.add_func("/palette/required-groups", test_required_groups);
    Test.add_func("/palette/relevance", test_relevance);
    Test.add_func("/palette/wrap-document", test_wrap_document);
    Test.add_func("/palette/plantuml-snippets", test_plantuml_snippets);
    Test.add_func("/palette/mermaid-snippets", test_mermaid_snippets);
    Test.add_func("/palette/new-syntax-groups", test_new_syntax_groups);
    Test.add_func("/palette/order-policy", test_order_policy);
    return Test.run();
}
