/*
 * review_leftovers_test.vala — the leftovers of the September 2026 review.
 *
 * - A link out of a composite state attaches to one of the composite's own states, not to a
 *   node inside a nested composite (the link was routed around both and crossed a neighbour's
 *   title).
 * - A class's member compartment is as tall as its rows, and the first row starts one row
 *   below the separator: the enlarged visibility icon no longer pads it out on top.
 * - Images in class notes: a local file is drawn and embedded, a remote one becomes a dashed
 *   placeholder box and is never fetched.
 * - A C4 stereotype claims a file only on the elements C4 draws (rectangle/database/queue);
 *   "actor X <<person>>" stays a use case diagram.
 * - Click navigation picks the quoted display label, and not a declaration keyword.
 * - JSON rows carry the source line of their key, so a click navigates like a YAML row.
 */
using GDiagram;

DiagramEngine? shared_engine = null;

DiagramEngine engine() {
    if (shared_engine == null) shared_engine = new DiagramEngine("dot");
    return shared_engine;
}

void expect_str(string? got, string? want, string what) {
    if (got != want) {
        printerr("\n%s: got [%s], want [%s]\n", what, got ?? "(null)", want ?? "(null)");
        assert_not_reached();
    }
}

void expect_int(int got, int want, string what) {
    if (got != want) {
        printerr("\n%s: got %d, want %d\n", what, got, want);
        assert_not_reached();
    }
}

void expect_true(bool condition, string what) {
    if (!condition) {
        printerr("\n%s\n", what);
        assert_not_reached();
    }
}

DiagramType type_of(string source, string filename = "t.puml") {
    var eng = engine();
    var format = eng.detect_format(source, filename);
    return format == DiagramFormat.MERMAID ? eng.detect_mermaid_type(source)
                                           : eng.detect_plantuml_type(source);
}

class Rendered : Object {
    public DiagramType type;
    public string source;
    public Cairo.ImageSurface? surface;
    public Gee.ArrayList<ElementRegion> regions = new Gee.ArrayList<ElementRegion>();

    public ElementRegion? find(string name) {
        foreach (var r in regions) {
            if (r.name == name) return r;
        }
        return null;
    }

    public ElementRegion expect_region(string name, int line) {
        var r = find(name);
        if (r == null) {
            printerr("\nno region %s; regions:\n", name);
            foreach (var reg in regions) printerr("  %s line=%d\n", reg.name, reg.source_line);
            assert_not_reached();
        }
        if (r.source_line != line) {
            printerr("\nregion %s: line %d, want %d\n", name, r.source_line, line);
            assert_not_reached();
        }
        return r;
    }
}

Rendered render(string source, string filename = "t.puml") {
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
    var eng = engine();
    var format = eng.detect_format(source, filename);
    var type = format == DiagramFormat.MERMAID ? eng.detect_mermaid_type(source)
                                               : eng.detect_plantuml_type(source);
    var result = eng.render(type, format, source);
    expect_true(result.surface != null, "render failed");
    var r = new Rendered();
    r.type = type;
    r.source = source;
    r.surface = result.surface;
    r.regions.add_all(eng.last_regions);
    return r;
}

string dot_of(string source, string filename = "t.puml") {
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
    return engine().generate_dot(source, filename, null);
}

// The whole line of `dot` that contains `needle`
string? dot_line(string dot, string needle) {
    foreach (string line in dot.split("\n")) {
        if (line.contains(needle)) return line.strip();
    }
    return null;
}

// ── 1. A link out of a composite state ───────────────────────────

const string COMPOSITE_SRC = """@startuml
[*] --> NotShooting

state NotShooting {
  [*] --> Idle
  Idle --> Configuring : EvConfig
  Configuring --> Idle : EvConfig
}

state Configuring {
  [*] --> NewValueSelection
  NewValueSelection --> NewValuePreview : EvNewValue
  NewValuePreview --> NewValueSelection : EvNewValueRejected

  state NewValuePreview {
     State1 -> State2
  }
}
@enduml
""";

void test_composite_exit_attaches_to_own_state() {
    string dot = dot_of(COMPOSITE_SRC);
    // "Configuring -> Idle" is clipped at Configuring's border (ltail) and has to leave from a
    // state Configuring itself holds; State1/State2 live one cluster deeper, and a link drawn
    // from there was routed around both clusters, over the NotShooting title.
    string? edge = dot_line(dot, "ltail=cluster_1");
    expect_true(edge != null, "no link clipped at the Configuring cluster:\n" + dot);
    expect_true(edge.has_prefix("NewValueSelection ->"),
                "the link out of Configuring starts inside the nested composite: " + edge);
    expect_true(edge.contains("-> Idle"), "the link out of Configuring does not reach Idle: " + edge);

    // And the same still holds for the nested composite's own outgoing links
    string? inner = dot_line(dot, "ltail=cluster_2");
    expect_true(inner != null && inner.contains("-> NewValueSelection"),
                "NewValuePreview's outgoing link: " + (inner ?? "(none)"));
}

// ── 2. Class member rows ─────────────────────────────────────────

const string MEMBERS_SRC = """@startuml
class Dummy {
  -field1
  #field2
  ~method1()
  +method2()
}
@enduml
""";

// The SVG of `source`, as text
string svg_of(string source) {
    uint8[]? svg = engine().generate_svg(source, "t.puml", null);
    expect_true(svg != null, "the SVG render failed");
    var sb = new StringBuilder.sized(svg.length + 1);
    sb.append_len((string) svg, svg.length);
    return sb.str;
}

// The y of the <text> whose content is `label` (Graphviz y grows upwards, so it is negative)
double text_baseline(string svg, string label) {
    try {
        var re = new Regex("<text [^>]*y=\"([-0-9.]+)\"[^>]*>\\s*" + Regex.escape_string(label) + "</text>");
        MatchInfo m;
        if (!re.match(svg, 0, out m)) {
            printerr("\nno <text> for %s in:\n%s\n", label, svg);
            assert_not_reached();
        }
        return double.parse(m.fetch(1));
    } catch (RegexError e) {
        assert_not_reached();
    }
}

// The y of every compartment separator of a class box (a filled, zero-height polygon)
Gee.ArrayList<double?> separator_ys(string svg) {
    var ys = new Gee.ArrayList<double?>();
    try {
        var re = new Regex("<polygon fill=\"#[0-9a-fA-F]{6}\" stroke=\"#[0-9a-fA-F]{6}\" points=\"0,([-0-9.]+) 0,\\1 ");
        MatchInfo m;
        re.match(svg, 0, out m);
        while (m.matches()) {
            ys.add(double.parse(m.fetch(1)));
            m.next();
        }
    } catch (RegexError e) {
        assert_not_reached();
    }
    return ys;
}

void test_member_rows_match_plain_text_rows() {
    string svg = svg_of(MEMBERS_SRC);
    double first = text_baseline(svg, "field1");
    double second = text_baseline(svg, "field2");
    double pitch = second - first;
    var seps = separator_ys(svg);
    expect_int(seps.size, 2, "one separator above the fields and one below");
    double top = double.min(seps[0], seps[1]);      // Graphviz y grows upwards
    double bottom = double.max(seps[0], seps[1]);

    // PlantUML puts the first member one row-height below the separator and the compartment
    // holds its rows plus a little padding. The visibility icon is written in a font 4pt
    // larger than the text (the only way to keep Graphviz from closing the lines up) and
    // Graphviz hangs a line from the top of its largest font, so all of that extra height sat
    // above the first row: the compartment was a row-height too tall and top-heavy.
    double head = first - top;
    if (Math.fabs(head - pitch) > 1.0) {
        printerr("\nfirst member %.2f below the separator, row pitch %.2f\n", head, pitch);
        assert_not_reached();
    }
    double slack = (bottom - top) - 2 * pitch;
    if (slack < 0.0 || slack > 5.0) {
        printerr("\ncompartment %.2f tall for two %.2f rows\n", bottom - top, pitch);
        assert_not_reached();
    }

    string dot = dot_of(MEMBERS_SRC);
    // The compartment carries its own padding, smaller than the class table's
    expect_true(dot.contains("<TD ALIGN=\"LEFT\" BALIGN=\"LEFT\" CELLPADDING=\"2\">"),
                "member compartment padding:\n" + dot);
}

// ── 3. Images in class notes ─────────────────────────────────────

void test_class_note_images() {
    string remote = "@startuml\nclass Foo\nnote as N1\n  hosted by <img:https://plantuml.com/sourceforge.jpg>\nend note\n@enduml\n";
    string dot = dot_of(remote);
    // A dashed box with the file name, and nothing that could be fetched
    expect_true(dot.contains("STYLE=\"dashed\""), "no placeholder box for the remote image:\n" + dot);
    expect_true(dot.contains("sourceforge.jpg"), "the placeholder does not name the image:\n" + dot);
    expect_true(!dot.contains("<IMG SRC=\"https"), "a remote image would be fetched:\n" + dot);
    // It still renders
    expect_true(render(remote).surface != null, "a note with a remote image renders");

    // A local file is drawn, and embedded so librsvg (and a moved SVG) can show it
    string dir;
    try {
        dir = DirUtils.make_tmp("gd-note-img-XXXXXX");
    } catch (FileError e) {
        printerr("\nno temp dir: %s\n", e.message);
        assert_not_reached();
    }
    string png = Path.build_filename(dir, "logo.png");
    var img = new Cairo.ImageSurface(Cairo.Format.ARGB32, 8, 8);
    img.write_to_png(png);
    string local = "@startuml\nclass Foo\nnote as N1\n  shipped with <img:%s>\nend note\n@enduml\n".printf(png);
    string local_dot = dot_of(local);
    expect_true(local_dot.contains("<IMG SRC=\"" + png + "\"/>"), "the local image is not drawn:\n" + local_dot);
    uint8[]? svg = engine().generate_svg(local, "t.puml", null);
    expect_true(svg != null, "the SVG render failed");
    var sb = new StringBuilder.sized(svg.length + 1);
    sb.append_len((string) svg, svg.length);
    string svg_text = sb.str;
    expect_true(svg_text.contains("data:image/png;base64,"), "the local image is not embedded in the SVG");
    FileUtils.remove(png);
    DirUtils.remove(dir);
}

// ── 4. C4 stereotypes vs. the element's own type ─────────────────

void test_c4_stereotype_needs_a_c4_element() {
    // C4 draws every element as a rectangle, a database or a queue
    expect_true(type_of("@startuml\nrectangle \"Web\" <<container>> as web\nrectangle \"DB\" <<container_db>> as db\nweb --> db\n@enduml\n")
                == DiagramType.COMPONENT, "a C4 rectangle is a component diagram");
    expect_true(type_of("@startuml\nskinparam rectangle<<person>> {\n  BackgroundColor #08427B\n}\nrectangle \"User\" <<person>> as u\n@enduml\n")
                == DiagramType.COMPONENT, "the C4 skinparam block is a component diagram");

    // PlantUML's own stereotypes on their own elements keep their diagram type
    expect_true(type_of("@startuml\nactor Customer <<person>>\nusecase (Buy) as UC1\nCustomer --> UC1\n@enduml\n")
                == DiagramType.USECASE, "an actor with a <<person>> stereotype is a use case diagram");
    expect_true(type_of("@startuml\nparticipant Bob <<system>>\nAlice -> Bob : hi\n@enduml\n")
                == DiagramType.SEQUENCE, "a participant with a <<system>> stereotype is a sequence diagram");
    expect_true(type_of("@startuml\nclass ArrayList <<container>>\nclass List\nList <|-- ArrayList\n@enduml\n")
                == DiagramType.CLASS, "a class with a <<container>> stereotype is a class diagram");
    expect_true(type_of("@startuml\nstate Running <<system>>\n[*] --> Running\n@enduml\n")
                == DiagramType.STATE, "a state with a <<system>> stereotype is a state diagram");

    // A C4 file that draws its people as actors still lands on the component renderer: it
    // calls the stdlib macros
    expect_true(type_of("@startuml\n!include <C4/C4_Context>\nPerson(user, \"User\")\nSystem(sys, \"System\")\nRel(user, sys, \"uses\")\n@enduml\n")
                == DiagramType.COMPONENT, "a raw C4 file is a component diagram");
}

// ── 5. Which token a click selects ───────────────────────────────

int span_start(string line, string[] names, out int end) {
    var list = new Gee.ArrayList<string>();
    foreach (string n in names) list.add(n);
    int start;
    expect_true(ClickNavigation.name_span(line, list, out start, out end), "no span in: " + line);
    return start;
}

void test_click_navigation_token_choice() {
    int end;
    // The declared name, not the same word inside the quoted display label
    string line = "actor \"Main Admin\" as Admin";
    int start = span_start(line, { "Admin", "Main Admin" }, out end);
    expect_int(start, 22, "the alias inside the display label is not the declaration");
    expect_str(line.substring(start, end - start), "Admin", "the declared name is selected");

    // Written nowhere but inside the label: the label is selected whole
    line = "actor \"Main Admin\"";
    start = span_start(line, { "Admin" }, out end);
    expect_str(line.substring(start, end - start), "Main Admin", "the whole display label");

    // A use case whose alias is written on its own after the label
    line = "\"Use the application\" as (Use)";
    start = span_start(line, { "Use", "Use the application" }, out end);
    expect_str(line.substring(start, end - start), "Use", "the alias outside the label");

    // The declared name, not the keyword of the same name
    line = "node node {";
    start = span_start(line, { "node" }, out end);
    expect_int(start, 5, "the keyword is not the element");

    // ... but a keyword-named element written only once is still selected
    line = "  state --> Idle";
    start = span_start(line, { "state" }, out end);
    expect_int(start, 2, "the only occurrence is selected even when it reads as a keyword");

    // Unquoted names keep working
    line = "Admin --> (Use)";
    start = span_start(line, { "Admin" }, out end);
    expect_int(start, 0, "a plain name");
}

// ── 6. JSON rows carry their source line ─────────────────────────

const string JSON_SRC = """@startjson
{
  "firstName": "John",
  "address": {
    "city": "Springfield"
  },
  "hobbies": ["coding", "reading"]
}
@endjson
""";

void test_json_rows_have_source_lines() {
    var r = render(JSON_SRC, "t.puml");
    // t0 is the root object, t1 "address", t2 "hobbies"
    r.expect_region("t0_r0", 3);   // "firstName"
    r.expect_region("t0_r1", 4);   // "address"
    r.expect_region("t0_r2", 7);   // "hobbies"
    r.expect_region("t1_r0", 5);   // "city"
    r.expect_region("t2_r0", 7);   // the array items are written on one line
    r.expect_region("t2_r1", 7);
    // and the tables themselves are at the line of their key
    r.expect_region("t1", 4);
    r.expect_region("t2", 7);
}

public static int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/leftovers/state/composite_exit", test_composite_exit_attaches_to_own_state);
    Test.add_func("/leftovers/class/member_rows", test_member_rows_match_plain_text_rows);
    Test.add_func("/leftovers/class/note_images", test_class_note_images);
    Test.add_func("/leftovers/detect/c4_stereotype", test_c4_stereotype_needs_a_c4_element);
    Test.add_func("/leftovers/click/token_choice", test_click_navigation_token_choice);
    Test.add_func("/leftovers/json/row_lines", test_json_rows_have_source_lines);
    return Test.run();
}
