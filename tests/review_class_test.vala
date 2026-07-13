// Class and object diagram review findings: note alias ids, same-named classes in
// packages, notes inside namespaces, DOT id collisions, colour specs, "note on link" and
// dotted note targets, object field rows, keyword/separator members, and the smaller
// declaration forms (annotation, struct, abstract, generics, "C::x" links, bare members).
// Every source goes through DiagramEngine and asserts its detected type, so detection
// cannot route a test to another parser.
using GDiagram;

DiagramEngine? shared_engine = null;

DiagramEngine engine() {
    if (shared_engine == null) shared_engine = new DiagramEngine("dot");
    return shared_engine;
}

string wrap(string body) {
    return "@startuml\n" + body + "\n@enduml\n";
}

string dot_as(string body, DiagramType want) {
    string src = wrap(body);
    var r = engine().parse(src, "test.puml");
    if (r.diagram_type != want) {
        printerr("\ndetected %s, want %s for:\n%s\n", r.diagram_type.to_string(), want.to_string(), src);
        assert_not_reached();
    }
    string? dot = engine().generate_dot(src, "test.puml", null);
    assert(dot != null);
    return dot;
}

ClassDiagram class_ast(string body) {
    var r = engine().parse(wrap(body), "test.puml");
    if (r.diagram_type != DiagramType.CLASS || !(r.ast is ClassDiagram)) {
        printerr("\ndetected %s, want class for:\n%s\n", r.diagram_type.to_string(), body);
        assert_not_reached();
    }
    return (ClassDiagram) r.ast;
}

void expect_contains(string dot, string want, string what) {
    if (!dot.contains(want)) {
        printerr("\n%s: missing [%s] in:\n%s\n", what, want, dot);
        assert_not_reached();
    }
}

void expect_not_contains(string dot, string unwanted, string what) {
    if (dot.contains(unwanted)) {
        printerr("\n%s: unexpected [%s] in:\n%s\n", what, unwanted, dot);
        assert_not_reached();
    }
}

// The DOT must parse: Graphviz rejects e.g. a DOT keyword used as a node id
void expect_valid_dot(string dot, string what) {
    var g = Gvc.Graph.read_string(dot);
    if (g == null) {
        printerr("\n%s: Graphviz could not parse:\n%s\n", what, dot);
        assert_not_reached();
    }
}

// Number of statement lines starting with `prefix`
int lines_starting(string dot, string prefix) {
    int n = 0;
    foreach (string raw in dot.split("\n")) {
        if (raw.strip().has_prefix(prefix)) n++;
    }
    return n;
}

// ── 1. object note aliases ───────────────────────────────────

void test_object_note_alias_keyword() {
    string dot = dot_as("object A\nnote \"n\" as edge\nA .. edge", DiagramType.OBJECT);
    expect_valid_dot(dot, "alias edge");
    expect_contains(dot, "A -> _obj_note_0 [", "link to the note");
    expect_contains(dot, "_obj_note_0 [label=\"n\"", "note node");
}

void test_object_note_alias_quoted() {
    string dot = dot_as("object A\nnote \"n\" as \"my note\"\nA .. \"my note\"", DiagramType.OBJECT);
    expect_valid_dot(dot, "quoted alias");
    assert(lines_starting(dot, "my") == 0);
    expect_contains(dot, "A -> _obj_note_0 [", "link to the quoted alias");
}

void test_object_note_alias_half_typed() {
    string dot = dot_as("object A\nnote \"floating\" as. N1\nnote \"x\" as @enduml", DiagramType.OBJECT);
    expect_valid_dot(dot, "half-typed alias");
    assert(lines_starting(dot, ".") == 0);
    expect_not_contains(dot, "@", "no @ in ids");
    expect_contains(dot, "_obj_note_0 [label=\"floating\"", "floating note");
}

void test_object_note_alias_same_as_object() {
    string dot = dot_as("object N1\nnote \"x\" as N1\nobject B\nN1 --> B", DiagramType.OBJECT);
    expect_valid_dot(dot, "alias = object name");
    assert(lines_starting(dot, "N1 [label=\"{N1}\"") == 1);
    assert(lines_starting(dot, "_obj_note_0 [label=\"x\"") == 1);
    expect_contains(dot, "N1 -> B [", "object link");
}

// ── 2. same class name in two packages ───────────────────────

void test_same_name_in_two_packages() {
    var d = class_ast("package P {\n  class Person\n}\npackage Q {\n  class Person\n}\nclass A\nA --> Person");
    var p = d.find_package("P");
    var q = d.find_package("Q");
    assert(p != null && q != null);
    expect_int(p.classes.size, 1, "P classes");
    expect_int(q.classes.size, 1, "Q classes");
    assert(p.classes[0] != q.classes[0]);
    // Ambiguous at the top level: PlantUML makes a new top-level Person
    var rel = d.relationships[0];
    assert(rel.to.owner_package == null);
    expect_str(rel.to.display_name ?? rel.to.name, "Person", "target label");
    assert(rel.to != p.classes[0] && rel.to != q.classes[0]);

    string dot = dot_as("package P {\n  class Person\n}\npackage Q {\n  class Person\n}\nclass A\nA --> Person", DiagramType.CLASS);

    int person_nodes = 0;
    foreach (string raw in dot.split("\n")) {
        if (raw.contains("&#160; Person</TD>")) person_nodes++;
    }
    expect_int(person_nodes, 3, "Person boxes");
}

void test_unique_package_class_is_reused() {
    var d = class_ast("package P {\n  class Person\n}\nclass A\nA --> Person");
    expect_int(d.classes.size, 2, "classes");
    assert(d.relationships[0].to.owner_package == d.find_package("P"));
}

// ── 3. note inside a namespace ───────────────────────────────

void test_namespace_note_attached() {
    string dot = dot_as("namespace net.dummy {\n  class Person\n  note right of Person : a note\n}", DiagramType.CLASS);
    expect_contains(dot, "net_dummy_Person -> _class_note_0 [", "note connector (class first: the note sits on its right)");
}

// ── 4. DOT id collisions ─────────────────────────────────────

void test_dot_id_collisions() {
    string dot = dot_as("class a.b\nclass a_b\na.b --> a_b\nclass \"B C\"\nclass B_C\n\"B C\" --> B_C\n" +
                        "class node\nclass node_\nnode --> node_", DiagramType.CLASS);
    expect_valid_dot(dot, "collisions");
    expect_contains(dot, "a_b -> a_b_2 [", "a.b -> a_b");
    expect_contains(dot, "B_C -> B_C_2 [", "\"B C\" -> B_C");
    // RenderUtils.sanitize_id already keeps keyword ids apart (node → node_, node_ → node__)
    expect_contains(dot, "node_ -> node__ [", "node -> node_");
    foreach (string raw in dot.split("\n")) {
        string l = raw.strip();
        int arrow = l.index_of(" -> ");
        int bracket = l.index_of(" [");
        if (arrow > 0 && bracket > arrow) {
            assert(l.substring(0, arrow) != l.substring(arrow + 4, bracket - arrow - 4));
        }
    }
}

// ── 5. colour specs ──────────────────────────────────────────

string node_line(string dot, string id) {
    string? found = null;
    foreach (string raw in dot.split("\n")) {
        string l = raw.strip();
        if (l.has_prefix(id + " [")) {
            found = l;
            break;
        }
    }
    if (found == null) {
        printerr("\nno node %s in:\n%s\n", id, dot);
        assert_not_reached();
    }
    return found;
}

void test_color_spec_back() {
    string dot = dot_as("class Foo #back:pink {\n  +x : int\n}", DiagramType.CLASS);
    string l = node_line(dot, "Foo");
    expect_contains(l, "fillcolor=\"pink\"", "fill");
    expect_contains(l, "+ x : int", "member kept");
    expect_not_contains(dot, "\"back\"", "no colour named back");
}

void test_color_spec_line_and_text() {
    string dot = dot_as("class Bar #pink;line:red {\n  +y : int\n}\nclass A #back:lightblue;line:red;line.dashed;text:blue\n" +
                        "class Baz #pink ##[dashed]blue", DiagramType.CLASS);
    string bar = node_line(dot, "Bar");
    expect_contains(bar, "fillcolor=\"pink\"", "Bar fill");
    expect_contains(bar, "color=\"red\"", "Bar border");
    expect_contains(bar, "+ y : int", "Bar member");
    string a = node_line(dot, "A");
    expect_contains(a, "fillcolor=\"lightblue\"", "A fill");
    expect_contains(a, "color=\"red\"", "A border");
    expect_contains(a, "STYLE=\"dashed\">", "A border style");
    expect_contains(a, "fontcolor=\"blue\"", "A text");
    string baz = node_line(dot, "Baz");
    expect_contains(baz, "color=\"blue\"", "Baz border");
    expect_contains(baz, "STYLE=\"dashed\">", "Baz border style");
}

// ── 6. note targets ──────────────────────────────────────────

void test_note_on_link() {
    string dot = dot_as("class A\nclass B\nA --> B\nnote on link : hi\nclass C", DiagramType.CLASS);
    expect_contains(dot, "_class_note_0 [shape=note, label=<hi<BR ALIGN=\"LEFT\"/>>", "link note");
    expect_contains(dot, "A -> _class_note_0 [style=invis]", "ranked after the link's tail");
    expect_contains(dot, "_class_note_0 -> B [style=invis]", "ranked before the link's head");
    assert(class_box(dot, "C", "C"));  // rest of the file kept
}

void test_note_dotted_target() {
    string dot = dot_as("class net.dummy.Person\nnote right of net.dummy.Person : hi\nclass Bar", DiagramType.CLASS);
    expect_contains(dot, "label=<hi<BR ALIGN=\"LEFT\"/>>", "note text");
    expect_contains(dot, "net_dummy_Person -> _class_note_0 [", "note connector");
    assert(class_box(dot, "Bar", "Bar"));  // rest of the file kept
}

void test_unclosed_note_stops_at_enduml() {
    string dot = dot_as("class A\nnote left of A\n  unclosed", DiagramType.CLASS);
    expect_contains(dot, "label=<unclosed<BR ALIGN=\"LEFT\"/>>", "note text");
    expect_not_contains(dot, "enduml", "@enduml kept out of the note");
}

// ── 7. object fields ─────────────────────────────────────────

void test_object_fields_as_written() {
    string dot = dot_as("object user {\n  name = \"Dummy\"\n  id = 123\n}", DiagramType.OBJECT);
    expect_contains(dot, "{user|name = \\\"Dummy\\\"\\lid = 123\\l}", "field rows");
}

// ── 8. keyword / separator members ───────────────────────────

void test_keyword_and_separator_members() {
    string dot = dot_as("class A {\n  note : String\n  title : String\n  left : int\n  +end()\n  object : Obj\n" +
                        "  -- separator --\n  .. dots ..\n  \"quoted\" : int\n  +package : String\n}", DiagramType.CLASS);
    string l = node_line(dot, "A");
    string br = "<BR ALIGN=\"LEFT\"/>";
    expect_contains(l, "<HR/><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">note : String" + br + "title : String" + br +
                    "left : int" + br + "+ end()" + br + "object : Obj" + br + "</TD></TR>" +
                    "<HR/><TR><TD>separator</TD></TR>" +
                    "<HR/><TR><TD>dots</TD></TR><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">&quot;quoted&quot; : int" + br +
                    "+ package : String" + br + "</TD></TR></TABLE>", "members in order");
}

// ── 9. declaration forms ─────────────────────────────────────

void test_annotation_and_struct() {
    string dot = dot_as("annotation Ann\nstruct S\nclass X", DiagramType.CLASS);
    assert(class_box(dot, "Ann", "Ann", ">@</FONT>"));  // annotation spot
    assert(class_box(dot, "S", "S", ">S</FONT>"));  // struct spot
    assert(lines_starting(dot, "annotation [") == 0);
    assert(lines_starting(dot, "struct [") == 0);
}

void test_abstract_short_form() {
    var d = class_ast("abstract D\nabstract class E");
    expect_int(d.classes.size, 2, "classes");
    assert(d.find_class("D").class_type == ClassType.ABSTRACT);
    assert(d.find_class("E").class_type == ClassType.ABSTRACT);
}

void test_generic_class_body() {
    string dot = dot_as("class E<T> {\n  +get() : T\n}", DiagramType.CLASS);
    expect_contains(node_line(dot, "E"), "&#160; E&lt;T&gt;</TD></TR><HR/><TR><TD CELLPADDING=\"3\"></TD></TR>" +
                    "<HR/><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">+ get() : T<BR ALIGN=\"LEFT\"/></TD>", "generic name and member");
}

void test_member_link() {
    string dot = dot_as("class A\nclass C\nC::x --> A", DiagramType.CLASS);
    expect_contains(dot, "C -> A [", "link anchored to the class");
}

void test_member_without_visibility() {
    string dot = dot_as("class M {\n  field : int\n  -secret : int\n  run()\n}", DiagramType.CLASS);
    expect_contains(node_line(dot, "M"), "<TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">field : int<BR ALIGN=\"LEFT\"/>- secret : int" +
                    "<BR ALIGN=\"LEFT\"/></TD></TR><HR/><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">run()<BR ALIGN=\"LEFT\"/></TD>", "markers as written");
}

void expect_int(int got, int want, string what) {
    if (got != want) {
        printerr("\n%s: got %d, want %d\n", what, got, want);
        assert_not_reached();
    }
}

void expect_str(string? got, string? want, string what) {
    if (got != want) {
        printerr("\n%s: got [%s], want [%s]\n", what, got ?? "(null)", want ?? "(null)");
        assert_not_reached();
    }
}

// ── declaration keywords (exception, protocol, record, ...) ─────────────

void test_declaration_keywords() {
    string[] kws = { "exception", "protocol", "metaclass", "stereotype", "dataclass", "record" };
    string body = "class X\n";
    foreach (string kw in kws) {
        body += "%s K_%s\n".printf(kw, kw);
    }
    var d = class_ast(body);
    // Each line declares one class; none is named after the keyword
    expect_int(d.classes.size, kws.length + 1, "classes");
    string dot = dot_as(body, DiagramType.CLASS);
    foreach (string kw in kws) {
        assert(d.find_class(kw) == null);
        assert(d.find_class("K_" + kw) != null);
        assert(class_box(dot, "K_" + kw, "K_" + kw, ">%s</FONT>".printf(keyword_spot(kw))));
        assert(lines_starting(dot, kw + " [") == 0);
    }
    assert(d.find_class("K_exception").class_type == ClassType.EXCEPTION);
    assert(d.find_class("K_protocol").class_type == ClassType.PROTOCOL);
    assert(d.find_class("K_metaclass").class_type == ClassType.METACLASS);
    assert(d.find_class("K_stereotype").class_type == ClassType.STEREOTYPE);
    assert(d.find_class("K_dataclass").class_type == ClassType.DATACLASS);
    assert(d.find_class("K_record").class_type == ClassType.RECORD);
}

void test_declaration_keyword_forms() {
    string body = "exception \"Bad Thing\" as MyError <<checked>> #pink {\n  +code : int\n}\n" +
                  "record R {\n  x : int\n}\nclass P\nMyError --> P\nR ..> P";
    var d = class_ast(body);
    expect_int(d.classes.size, 3, "classes");
    var e = d.find_class("MyError");
    assert(e.class_type == ClassType.EXCEPTION);
    expect_str(e.display_name, "Bad Thing", "label");
    expect_str(e.stereotype, "checked", "stereotype");
    expect_str(e.color, "#pink", "colour");
    expect_int(e.members.size, 1, "exception members");
    expect_int(d.find_class("R").members.size, 1, "record members");
    expect_int(d.relationships.size, 2, "links");
    // Still a class named after the word when an arrow follows it
    var linked = class_ast("class A\nrecord --> A");
    assert(linked.find_class("record") != null);
}

void test_circle_keyword() {
    string body = "class A\ncircle Ci\nCi -- A";
    var d = class_ast(body);
    assert(d.find_class("circle") == null);
    assert(d.find_class("Ci").class_type == ClassType.CIRCLE);
    string dot = dot_as(body, DiagramType.CLASS);
    string l = node_line(dot, "Ci");
    expect_contains(l, "shape=circle", "circle shape");
    expect_contains(l, "xlabel=\"Ci\"", "circle name");
    expect_contains(l, "label=\"\"", "no record label");
    expect_valid_dot(dot, "circle");
}

void test_existing_declaration_keywords_unchanged() {
    var d = class_ast("entity E\nenum En\nannotation An\nstruct St\ninterface I\nabstract Ab");
    expect_int(d.classes.size, 6, "classes");
    assert(d.find_class("E").class_type == ClassType.ENTITY);
    assert(d.find_class("En").class_type == ClassType.ENUM);
    assert(d.find_class("An").class_type == ClassType.ANNOTATION);
    assert(d.find_class("St").class_type == ClassType.STRUCT);
    assert(d.find_class("I").class_type == ClassType.INTERFACE);
    assert(d.find_class("Ab").class_type == ClassType.ABSTRACT);
}


// "legend top left ... endlegend": its lines became classes ("Key", "endlegend"). It is
// drawn at its corner as the label of a frameless cluster around the body.
void test_class_legend() {
    string body = "class A\nclass B\nA --> B\nlegend top left\n  Key\n  |= Color |= Layer |\n  | <#FFEBEE> | Engine |\n" +
                  "  Crow's feet\nendlegend";
    var d = class_ast(body);
    assert(d.classes.size == 2);
    assert(d.find_class("endlegend") == null);
    assert(d.find_class("Key") == null);
    assert(d.legend != null);
    assert(d.legend.valign == "top" && d.legend.halign == "left");
    string dot = dot_as(body, DiagramType.CLASS);
    expect_contains(dot, "subgraph cluster_legend {", "legend cluster");
    expect_contains(dot, "labelloc=t;", "legend at the top");
    expect_contains(dot, "labeljust=l;", "legend on the left");
    expect_contains(dot, "BGCOLOR=\"#FFEBEE\"", "legend colour cell");
    expect_contains(dot, "Crow's feet", "legend text");
    expect_not_contains(dot, "endlegend", "legend end as a class");
    expect_valid_dot(dot, "class legend");

    // "end legend", default position bottom centre
    var d2 = class_ast("class A\nlegend\nnote\nend legend\nclass B");
    assert(d2.classes.size == 2);
    assert(d2.legend != null && d2.legend.valign == "bottom" && d2.legend.halign == "center");
    assert(d2.legend.text == "note");
}

// Object diagram legend: no ghost "Key"/"endlegend" objects, the legend is drawn
void test_object_legend() {
    string dot = dot_as("object A\nobject B\nA --> B\nlegend top left\n  |= Key |= Meaning |\n  | A | first |\nendlegend", DiagramType.OBJECT);
    assert(!dot.contains("endlegend"));
    assert(!dot.contains("Key [label"));
    assert(dot.contains("Meaning"));
}

void main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/object_note/keyword_alias", test_object_note_alias_keyword);
    Test.add_func("/review/object_note/quoted_alias", test_object_note_alias_quoted);
    Test.add_func("/review/object_note/half_typed_alias", test_object_note_alias_half_typed);
    Test.add_func("/review/object_note/alias_is_object_name", test_object_note_alias_same_as_object);
    Test.add_func("/review/class/same_name_two_packages", test_same_name_in_two_packages);
    Test.add_func("/review/class/unique_package_class_reused", test_unique_package_class_is_reused);
    Test.add_func("/review/class/namespace_note", test_namespace_note_attached);
    Test.add_func("/review/class/dot_id_collisions", test_dot_id_collisions);
    Test.add_func("/review/class/color_back", test_color_spec_back);
    Test.add_func("/review/class/color_line_text", test_color_spec_line_and_text);
    Test.add_func("/review/class/note_on_link", test_note_on_link);
    Test.add_func("/review/class/note_dotted_target", test_note_dotted_target);
    Test.add_func("/review/class/note_unclosed", test_unclosed_note_stops_at_enduml);
    Test.add_func("/review/object/fields_as_written", test_object_fields_as_written);
    Test.add_func("/review/class/keyword_separator_members", test_keyword_and_separator_members);
    Test.add_func("/review/class/annotation_struct", test_annotation_and_struct);
    Test.add_func("/review/class/abstract_short", test_abstract_short_form);
    Test.add_func("/review/class/generic_body", test_generic_class_body);
    Test.add_func("/review/class/member_link", test_member_link);
    Test.add_func("/review/class/member_without_visibility", test_member_without_visibility);
    Test.add_func("/review/class/declaration_keywords", test_declaration_keywords);
    Test.add_func("/review/class/declaration_keyword_forms", test_declaration_keyword_forms);
    Test.add_func("/review/class/circle_keyword", test_circle_keyword);
    Test.add_func("/review/class/existing_declaration_keywords", test_existing_declaration_keywords_unchanged);
    Test.add_func("/review/class/legend", test_class_legend);
    Test.add_func("/review/object/legend", test_object_legend);
    Test.add_func("/review/class/fidelity/inline_link_style", test_fid_inline_link_style);
    Test.add_func("/review/class/fidelity/colon_members", test_fid_colon_members);
    Test.add_func("/review/class/fidelity/association_class", test_fid_association_class);
    Test.add_func("/review/class/fidelity/hide_show_members", test_fid_hide_show_members);
    Test.add_func("/review/class/fidelity/field_method_modifiers", test_fid_field_method_modifiers);
    Test.add_func("/review/class/fidelity/static_abstract_styling", test_fid_static_abstract_styling);
    Test.add_func("/review/class/fidelity/note_placement", test_fid_note_placement);
    Test.add_func("/review/class/fidelity/custom_separator", test_fid_custom_separator);
    Test.add_func("/review/class/fidelity/diamond_circle_lollipop", test_fid_diamond_circle_lollipop);
    Test.add_func("/review/class/fidelity/extends_list", test_fid_extends_list);
    Test.add_func("/review/class/fidelity/escape_and_spots", test_fid_escape_and_spots);
    Test.add_func("/review/class/fidelity/page_directive", test_fid_page_directive);
    Test.add_func("/review/class/fidelity/multiplicity_room", test_fid_multiplicity_room);
    Test.add_func("/review/class/fidelity/cosmetics", test_fid_cosmetics);
    Test.add_func("/review/class/fidelity/click_regions_and_spots", test_fid_click_regions_and_spots);
    Test.run();
}

// A class node drawn as an HTML table: the line "id [label=<" whose header cell ends with
// the name (after the spot), holding `extra` too
bool class_box(string dot, string id, string name, string extra = "") {
    foreach (string raw in dot.split("\n")) {
        string line = raw.strip();
        if (line.has_prefix(id + " [label=<") && line.contains("&#160; " + Markup.escape_text(name) + "</TD>") &&
            line.contains(extra)) {
            return true;
        }
    }
    return false;
}

// PlantUML's spot letter for a declaration keyword
string keyword_spot(string kw) {
    switch (kw) {
        case "exception": return "X";
        case "protocol": return "P";
        case "metaclass": return "M";
        case "stereotype": return "S";
        case "dataclass": return "D";
        case "record": return "R";
        case "annotation": return "@";
        case "struct": return "S";
        default: return "C";
    }
}

// ── 10. PlantUML fidelity (2026-09-17) ───────────────────────

// F1: "foo --> bar #red : lbl" and "#line:red;line.bold;text:red": colour, style and the label
void test_fid_inline_link_style() {
    string dot = dot_as("class foo\nfoo --> bar1 #red : lbl\nfoo --> bar2 #line:red;line.bold;text:blue : l2\n" +
                        "foo --> bar3 #green;line.dashed;text:green : l3", DiagramType.CLASS);
    string e1 = edge_line(dot, "foo -> bar1 [");
    expect_contains(e1, "xlabel=\"lbl\"", "label kept after #red");
    expect_contains(e1, "color=\"red\"", "#red colour");
    string e2 = edge_line(dot, "foo -> bar2 [");
    expect_contains(e2, "style=bold", "line.bold");
    expect_contains(e2, "color=\"red\"", "line:red");
    expect_contains(e2, "fontcolor=\"blue\"", "text:blue");
    expect_contains(e2, "xlabel=\"l2\"", "label l2");
    string e3 = edge_line(dot, "foo -> bar3 [");
    expect_contains(e3, "style=dashed", "line.dashed");
    expect_contains(e3, "color=\"green\"", "#green");
    var d = class_ast("class foo\nfoo --> bar1 #red : lbl");
    expect_int(d.classes.size, 2, "no ghost class from the colour");
}

// F2: "ClassName : member" adds the member
void test_fid_colon_members() {
    var d = class_ast("Object <|-- ArrayList\nObject : equals()\nArrayList : Object[] elementData\n" +
                      "class Foo\nFoo : {static} int count\nFoo : -secret");
    expect_int(d.classes.size, 3, "classes");
    var obj = d.find_class("Object");
    expect_int(obj.members.size, 1, "Object members");
    assert(obj.members[0].is_method && obj.members[0].name == "equals()");
    var al = d.find_class("ArrayList");
    expect_int(al.members.size, 1, "ArrayList members");
    assert(!al.members[0].is_method && al.members[0].name == "Object[] elementData");
    var foo = d.find_class("Foo");
    expect_int(foo.members.size, 2, "Foo members");
    assert(foo.members[0].is_static);
    assert(foo.members[1].visibility == MemberVisibility.PRIVATE && foo.members[1].name == "secret");
}

// F3: "(A, B) .. C": the A-B link runs through a point that C hangs from
void test_fid_association_class() {
    string src = "class Student\nclass Course\nclass Enrollment\nStudent \"0..*\" - \"1..*\" Course\n" +
                 "(Student, Course) .. Enrollment";
    var d = class_ast(src);
    expect_int(d.classes.size, 3, "no ghost classes");
    expect_int(d.relationships.size, 1, "one link");
    assert(d.relationships[0].association_classes.size == 1);
    string dot = dot_as(src, DiagramType.CLASS);
    expect_contains(dot, "_assoc0 [label=\"\", shape=point", "junction point");
    expect_contains(dot, "Student -> _assoc0 [", "first half");
    expect_contains(dot, "_assoc0 -> Course [", "second half");
    expect_contains(dot, "_assoc0 -> Enrollment [style=dashed", "dashed line to the association class");
    expect_valid_dot(dot, "association");
    // "." (one character) puts the class beside the point
    string side = dot_as("class A\nA -- B\n(A, B) . C", DiagramType.CLASS);
    expect_contains(side, "{ rank=same; _assoc0; C; }", "beside the point");
}

// F4: hide/show of member portions
void test_fid_hide_show_members() {
    var d = class_ast("class A {\n +m()\n f\n}\nclass B <<S>> {\n String name\n}\nhide members\n" +
                      "show A methods\nshow <<S>> fields\nhide <<S>> circle\nhide stereotype");
    var a = d.find_class("A");
    var b = d.find_class("B");
    assert(a.fields_hidden && !a.methods_hidden);
    assert(!b.fields_hidden && b.methods_hidden);
    assert(b.circle_hidden && !a.circle_hidden);
    assert(a.stereotype_hidden && b.stereotype_hidden);
    string dot = dot_as("class A {\n +m()\n f\n}\nhide fields", DiagramType.CLASS);
    string l = node_line(dot, "A");
    expect_not_contains(l, ">f<BR", "field hidden");
    expect_contains(l, "+ m()", "method shown");
    var v = class_ast("hide private members\nclass Foo {\n - priv\n + pub\n}");
    var foo = v.find_class("Foo");
    assert(foo.members[0].hidden_member && !foo.members[1].hidden_member);
    string vdot = dot_as("hide private members\nclass Foo {\n - priv\n + pub\n}", DiagramType.CLASS);
    expect_not_contains(vdot, "priv", "private member not drawn");
    var e = class_ast("class E\nclass F {\n x\n}\nhide empty members");
    assert(e.find_class("E").empty_fields_hidden && e.find_class("F").empty_methods_hidden);
    string edot = dot_as("class E\nhide empty members", DiagramType.CLASS);
    expect_not_contains(node_line(edot, "E"), "<HR/>", "empty compartments hidden");
    // "show X" is no longer taken as a class
    var s = class_ast("class A\nshow A methods\nshow A");
    expect_int(s.classes.size, 1, "show lines make no class");
}

// F5: {field} / {method} pick the compartment
void test_fid_field_method_modifiers() {
    var d = class_ast("class Dummy {\n {field} A field (despite parentheses)\n {method} Some method\n}");
    var c = d.find_class("Dummy");
    expect_int(c.members.size, 2, "members");
    assert(!c.members[0].is_method && c.members[0].name == "A field (despite parentheses)");
    assert(c.members[1].is_method && c.members[1].name == "Some method");
}

// F6: static underlined, abstract italic, abstract/interface names italic, modifier before marker
void test_fid_static_abstract_styling() {
    string dot = dot_as("class Dummy {\n {static} String id\n {abstract} void m()\n {static} + get(): int\n}\n" +
                        "abstract class Abs\ninterface I", DiagramType.CLASS);
    string l = node_line(dot, "Dummy");
    expect_contains(l, "<U>String id</U>", "static underlined");
    expect_contains(l, "<I>void m()</I>", "abstract italic");
    expect_contains(l, "+ <U>get(): int</U>", "{static} before the visibility marker");
    expect_contains(node_line(dot, "Abs"), "<I>Abs</I>", "abstract class name italic");
    expect_contains(node_line(dot, "I"), "<I>I</I>", "interface name italic");
    expect_not_contains(dot, "shape=record", "no record labels");
    expect_valid_dot(dot, "html labels");
}

// F7: notes on quoted members, on the last class, and placed on the requested side
void test_fid_note_placement() {
    var d = class_ast("class A {\n +void start(int t)\n}\nnote right of A::\"start(int t)\"\n   with int\nend note");
    expect_int(d.classes.size, 1, "no ghost class 'with'");
    expect_int(d.notes.size, 1, "note");
    expect_str(d.notes[0].text, "with int", "note text");
    expect_str(d.notes[0].attached_to, "A", "attached to A");

    var last = class_ast("class Foo\nnote left: On last defined class");
    expect_str(last.notes[0].attached_to, "Foo", "attached to the last class");

    string dot = dot_as("class A\nclass B\nclass C\nclass D\nnote left of A : l\nnote right of B : r\n" +
                        "note top of C : t\nnote bottom of D : b", DiagramType.CLASS);
    expect_contains(dot, "{ rank=same; A; _class_note_0; }", "left note in A's rank");
    expect_contains(dot, "_class_note_0 -> A [style=dashed", "left: note before A");
    expect_contains(dot, "{ rank=same; B; _class_note_1; }", "right note in B's rank");
    expect_contains(dot, "B -> _class_note_1 [style=dashed", "right: B before note");
    expect_contains(dot, "_class_note_2 -> C [style=dashed", "top: note above C");
    expect_contains(dot, "D -> _class_note_3 [style=dashed", "bottom: note below D");
    expect_not_contains(dot, "constraint=false];\n", "notes rank with their class");
    // Left-aligned HTML note text with formatting
    string md = dot_as("class Foo\nnote top of Foo\n <b>bold</b> <color:red>red</color> **x**\n <img:a.png>\nend note",
                       DiagramType.CLASS);
    expect_contains(md, "label=<<B>bold</B>&#160;<FONT COLOR=\"red\">red</FONT>&#160;<B>x</B><BR ALIGN=\"LEFT\"/>",
                    "formatting as HTML");
    expect_not_contains(md, "img", "image tag not shown literally");
    expect_valid_dot(md, "note html");
}

// F8: "set separator ::"
void test_fid_custom_separator() {
    var d = class_ast("set separator ::\nclass X1::X2::foo {\n some info\n}");
    expect_int(d.classes.size, 1, "one class");
    var foo = d.classes[0];
    expect_str(foo.display_name ?? foo.name, "foo", "class foo");
    expect_int(foo.members.size, 1, "member kept");
    assert(foo.owner_package != null && foo.owner_package.label == "X2");
    var none = class_ast("set separator none\nclass X1.X2.foo");
    assert(none.classes[0].owner_package == null && none.classes[0].name == "X1.X2.foo");
}

// F9: diamond keyword, "() c1", lollipops
void test_fid_diamond_circle_lollipop() {
    var d = class_ast("class X\ndiamond d1\n() c1\n");
    assert(d.find_class("diamond") == null);
    assert(d.find_class("d1").is_diamond);
    assert(d.find_class("c1").class_type == ClassType.CIRCLE);
    var l = class_ast("class foo\nbar ()- foo\nfoo -() baz");
    expect_int(l.classes.size, 3, "classes");
    assert(l.find_class("bar").class_type == ClassType.CIRCLE);
    assert(l.find_class("baz").class_type == ClassType.CIRCLE);
    assert(l.find_class("foo").class_type == ClassType.CLASS);
    expect_int(l.relationships.size, 2, "lollipop links");
}

// F10: several parents after extends / implements
void test_fid_extends_list() {
    var d = class_ast("class A extends B, C implements I, J");
    expect_int(d.relationships.size, 4, "parents");
    expect_int(d.classes.size, 5, "classes");
    int impl = 0;
    foreach (var r in d.relationships) {
        if (r.relationship_type == RelationshipType.IMPLEMENTATION) impl++;
    }
    expect_int(impl, 2, "implements");
}

// F11: backslash escape, custom spots
void test_fid_escape_and_spots() {
    var d = class_ast("class Dummy {\n \\~Dummy()\n}\nclass System << (S,#FF7700) Singleton >>\nclass Date << (D,orchid) >>");
    expect_str(d.find_class("Dummy").members[0].name, "~Dummy()", "escape dropped");
    var sys = d.find_class("System");
    expect_str(sys.spot_letter, "S", "spot letter");
    expect_str(sys.spot_color, "#FF7700", "spot colour");
    expect_str(sys.get_stereotype_text(), "Singleton", "stereotype text");
    assert(d.find_class("Date").get_stereotype_text() == null);
    string dot = dot_as("class System << (S,#FF7700) Singleton >>\nclass Date << (D,orchid) >>", DiagramType.CLASS);
    expect_contains(node_line(dot, "System"), "\u00ABSingleton\u00BB", "stereotype shown");
    expect_contains(node_line(dot, "System"), "COLOR=\"#FF7700\"", "spot colour");
    expect_contains(node_line(dot, "System"), ">S</FONT>", "spot letter");
    expect_not_contains(node_line(dot, "Date"), "\u00AB", "spot spec alone shows no stereotype");
    expect_not_contains(dot, "(S,", "spot spec not shown raw");
}

// F12: "page 2x2" is ignored
void test_fid_page_directive() {
    var d = class_ast("page 2x2\nclass A");
    expect_int(d.classes.size, 1, "no ghost class 'page'");
}

// F13: multiplicities get a longer edge; side-by-side ones more room
void test_fid_multiplicity_room() {
    string dot = dot_as("Class01 \"1\" *-- \"many\" Class02 : contains", DiagramType.CLASS);
    expect_contains(edge_line(dot, "Class01 -> Class02 ["), "minlen=2", "longer edge");
    string flat = dot_as("class A\nA \"1\" - \"many\" B", DiagramType.CLASS);
    expect_contains(flat, "nodesep=0.9;", "room between side-by-side classes");
}

// F14: thickness, skinparam colours, package styles, class visibility, label arrows,
// open crow's foot, double separators, spots, left-to-right order
void test_fid_cosmetics() {
    string thick = dot_as("class foo\nfoo -[#blue,dotted,thickness=4]-> baz", DiagramType.CLASS);
    string te = edge_line(thick, "foo -> baz [");
    expect_contains(te, "penwidth=4", "thickness");
    expect_contains(te, "style=dotted", "dotted kept");

    string skin = dot_as("skinparam class {\n ArrowColor SeaGreen\n BorderColor<<Foo>> Tomato\n}\n" +
                         "skinparam stereotypeCBackgroundColor YellowGreen\n" +
                         "skinparam stereotypeCBackgroundColor<<Foo>> DimGray\nclass A <<Foo>>\nA --> B", DiagramType.CLASS);
    expect_contains(skin, "edge [fontsize=9, fontname=\"Sans\", color=\"SeaGreen\"", "class ArrowColor");
    expect_contains(node_line(skin, "A"), "color=\"Tomato\"", "stereotype border colour");
    expect_contains(node_line(skin, "A"), "COLOR=\"DimGray\"", "stereotype spot colour");
    expect_contains(node_line(skin, "B"), "COLOR=\"YellowGreen\"", "spot colour");

    string pk = dot_as("package f1 <<Node>> {\n class C1\n}\npackage f2 <<Frame>> {\n class C2\n}\n" +
                       "package f3 <<Database>> {\n class C3\n}\npackage f4 <<Folder>> {\n class C4\n}", DiagramType.CLASS);
    expect_contains(pk, "penwidth=2;", "node outline");
    expect_contains(pk, "SIDES=\"BR\"", "frame title");
    expect_contains(pk, "style=\"filled,rounded\";", "database outline");
    expect_valid_dot(pk, "package styles");

    string vis = dot_as("-class Priv {\n}", DiagramType.CLASS);
    expect_contains(node_line(vis, "Priv"), "- Priv</TD>", "class visibility marker");

    string arrows = dot_as("class Car\nDriver - Car : drives >\nCar -- Person : < owns", DiagramType.CLASS);
    expect_contains(arrows, "xlabel=\"\u25B6 drives\"", "right arrow glyph");
    expect_contains(arrows, "xlabel=\"\u25C0 owns\"", "left arrow glyph");

    string crow = dot_as("class Class25\nClass25 }-- Class26", DiagramType.CLASS);
    expect_contains(crow, "arrowtail=ocrow", "open crow's foot");

    string sep = dot_as("class S {\n a\n ====\n b\n}", DiagramType.CLASS);
    expect_contains(node_line(sep, "S"), "<HR/><TR><TD CELLPADDING=\"0\" HEIGHT=\"2\"></TD></TR><HR/>", "double line");

    string lr = dot_as("left to right direction\nclass First\nclass Second\nclass Third", DiagramType.CLASS);
    assert(lr.index_of("Third [label=") < lr.index_of("First [label="));
}

// Click regions still map to the class nodes, and the spot is drawn as a circle
void test_fid_click_regions_and_spots() {
    string src = wrap("class Alpha {\n +run()\n}\ninterface Beta\nAlpha ..|> Beta\nnote right of Alpha : n");
    var eng = new DiagramEngine("dot");
    var r = eng.render(DiagramType.CLASS, DiagramFormat.PLANTUML, src);
    assert(r.surface != null);
    bool alpha = false;
    bool beta = false;
    foreach (var region in eng.last_regions) {
        if (region.name == "Alpha") {
            alpha = region.width > 20 && region.height > 20;
            expect_int(region.source_line, 2, "Alpha line");
        }
        if (region.name == "Beta") beta = region.width > 20 && region.height > 10;
    }
    assert(alpha && beta);
    string path = Path.build_filename(Environment.get_tmp_dir(), "gd_review_class_spot.svg");
    assert(eng.export_to_svg(src, "test.puml", null, path));
    string svg;
    try {
        FileUtils.get_contents(path, out svg);
    } catch (Error e) {
        assert_not_reached();
    }
    FileUtils.unlink(path);
    expect_not_contains(svg, "\u25CF", "spot glyph replaced");
    expect_not_contains(svg, "#fefefd", "marker run replaced");
    expect_contains(svg, "<ellipse fill=\"#add1b2\"", "class spot circle");
    expect_contains(svg, "<ellipse fill=\"#b4a7e5\"", "interface spot circle");
    expect_contains(svg, ">I</text>", "interface letter");
}

// The DOT statement line starting with `prefix`
string edge_line(string dot, string prefix) {
    foreach (string raw in dot.split("\n")) {
        if (raw.strip().has_prefix(prefix)) return raw;
    }
    printerr("\nno line starting [%s] in:\n%s\n", prefix, dot);
    assert_not_reached();
}
