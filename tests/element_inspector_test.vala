// ElementInspector: reads a clicked element from the AST and rewrites the source.
// Every edit test parses the edited text again and checks the AST, and every source
// asserts its detected diagram type so content-based detection cannot silently route
// a test to another parser.
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

ParseResult parse_as(string src, DiagramType want) {
    var r = engine().parse(src, null);
    if (r.diagram_type != want) {
        printerr("\ndetected %s, want %s for:\n%s\n", r.diagram_type.to_string(), want.to_string(), src);
        assert_not_reached();
    }
    assert(r.ast != null);
    return r;
}

ElementInfo inspect_as(string src, DiagramType want, string element_name) {
    var r = parse_as(src, want);
    var info = ElementInspector.inspect(r.diagram_type, r.ast, element_name, 0, src);
    if (info == null) {
        printerr("\nno element '%s' in:\n%s\n", element_name, src);
        assert_not_reached();
    }
    return info;
}

string line_of(string src, int line_number) {
    return src.split("\n")[line_number - 1];
}

UmlClass find_class(ParseResult r, string name) {
    foreach (var c in ((ClassDiagram) r.ast).classes) {
        if (c.name == name) return c;
    }
    printerr("\nno class %s\n", name);
    assert_not_reached();
}

// ==================== Inspect ====================

const string CLASS_SRC = "@startuml\nclass \"My Class\" as C <<entity>> #pink\nclass Foo\nclass Bar as \"Bar Label\"\nFoo --> C\nnote right of Foo : a note\n@enduml\n";

void test_inspect_class() {
    var c = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    expect_str(c.kind, "Class", "kind");
    expect_str(c.id, "C", "id");
    expect_str(c.label, "My Class", "label");
    expect_str(c.alias, "C", "alias");
    expect_str(c.stereotype, "entity", "stereotype");
    expect_str(c.color, "#pink", "color");
    expect_int(c.line, 2, "line");
    assert(c.declared && c.editable);
    assert(c.note == null);

    var foo = inspect_as(CLASS_SRC, DiagramType.CLASS, "Foo");
    expect_str(foo.label, "Foo", "bare label");
    assert(foo.alias == null);
    expect_str(foo.note, "a note", "note");
    expect_int(foo.line, 3, "foo line");

    var bar = inspect_as(CLASS_SRC, DiagramType.CLASS, "Bar");
    expect_str(bar.label, "Bar Label", "label written after as");
    expect_str(bar.id, "Bar", "id before as");

    var r = parse_as(CLASS_SRC, DiagramType.CLASS);
    assert(ElementInspector.inspect(r.diagram_type, r.ast, "Nope", 0, CLASS_SRC) == null);
    // Note nodes are not elements
    assert(ElementInspector.inspect(r.diagram_type, r.ast, "_class_note_0", 0, CLASS_SRC) == null);
}

void test_inspect_ie_entity() {
    string src = "@startuml\nentity \"User Table\" as U <<table>> #lightblue {\n  * id : int\n}\nentity Order\nU }o--|| Order\n@enduml\n";
    var u = inspect_as(src, DiagramType.CLASS, "U");
    expect_str(u.kind, "Entity", "kind");
    expect_str(u.label, "User Table", "label");
    expect_str(u.stereotype, "table", "stereotype");
    expect_str(u.color, "#lightblue", "color");
    expect_str(u.keyword, "entity", "keyword");
}

// The further class declaration keywords (exception, record, ...) are edited in place
void test_inspect_class_declaration_keywords() {
    string src = "@startuml\nexception MyError\nrecord R\nMyError --> R\n@enduml\n";
    var e = inspect_as(src, DiagramType.CLASS, "MyError");
    expect_str(e.kind, "Exception", "kind");
    expect_str(e.keyword, "exception", "keyword");
    expect_str(ElementInspector.set_color(e, src, "red"),
               "@startuml\nexception MyError #red\nrecord R\nMyError --> R\n@enduml\n", "colour in place");
    var r = inspect_as(src, DiagramType.CLASS, "R");
    expect_str(r.kind, "Record", "kind");
    expect_str(ElementInspector.set_label(r, src, "Rec ord"),
               "@startuml\nexception MyError\nrecord \"Rec ord\" as R\nMyError --> R\n@enduml\n", "label in place");
}

const string COMPONENT_SRC = "@startuml\ncomponent \"Web Server\" as WS <<svc>> #yellow\n[Database] as DB\ncomponent Cache\nWS --> DB\nnote left of WS : web note\n@enduml\n";

void test_inspect_component() {
    var ws = inspect_as(COMPONENT_SRC, DiagramType.COMPONENT, "WS");
    expect_str(ws.kind, "Component", "kind");
    expect_str(ws.label, "Web Server", "label");
    expect_str(ws.alias, "WS", "alias");
    expect_str(ws.stereotype, "svc", "stereotype");
    expect_str(ws.color, "#yellow", "color");
    expect_int(ws.line, 2, "line from the declaration text (the AST has none)");
    expect_str(ws.note, "web note", "note");

    var db = inspect_as(COMPONENT_SRC, DiagramType.COMPONENT, "DB");
    expect_str(db.label, "Database", "bracket label");
    expect_int(db.line, 3, "bracket line");
}

const string USECASE_SRC = "@startuml\nactor \"Admin User\" as A <<human>> #red\nusecase \"Log in\" as UC1\n(Buy Stuff) as UC2\n:Guest:\nA --> UC1\nnote right of A : admin note\n@enduml\n";

void test_inspect_usecase() {
    var a = inspect_as(USECASE_SRC, DiagramType.USECASE, "A");
    expect_str(a.kind, "Actor", "kind");
    expect_str(a.label, "Admin User", "label");
    expect_str(a.stereotype, "human", "stereotype");
    expect_str(a.color, "#red", "color");
    expect_str(a.note, "admin note", "note");

    var uc1 = inspect_as(USECASE_SRC, DiagramType.USECASE, "UC1");
    expect_str(uc1.kind, "Use case", "use case kind");
    expect_str(uc1.label, "Log in", "use case label");

    var uc2 = inspect_as(USECASE_SRC, DiagramType.USECASE, "UC2");
    expect_str(uc2.label, "Buy Stuff", "paren label");
    expect_int(uc2.line, 4, "paren line");

    var guest = inspect_as(USECASE_SRC, DiagramType.USECASE, "Guest");
    expect_str(guest.kind, "Actor", "colon actor kind");
    expect_int(guest.line, 5, "colon actor line");
}

const string STATE_SRC = "@startuml\nstate \"Long Name\" as S1 #pink\nstate Idle <<choice>>\n[*] --> S1\nS1 --> Idle\nnote right of S1 : state note\n@enduml\n";

void test_inspect_state() {
    var s1 = inspect_as(STATE_SRC, DiagramType.STATE, "S1");
    expect_str(s1.kind, "State", "kind");
    expect_str(s1.label, "Long Name", "label");
    expect_str(s1.color, "#pink", "color");
    expect_str(s1.note, "state note", "note");

    var idle = inspect_as(STATE_SRC, DiagramType.STATE, "Idle");
    expect_str(idle.kind, "Choice", "choice kind");
    expect_str(idle.stereotype, "choice", "stereotype");

    var r = parse_as(STATE_SRC, DiagramType.STATE);
    assert(ElementInspector.inspect(r.diagram_type, r.ast, "_initial_0", 0, STATE_SRC) == null);
}

const string SEQUENCE_SRC = "@startuml\nparticipant \"Alice X\" as A <<x>> #red\nactor Bob\nboundary Bo\ncontrol Ct\nentity En\ndatabase Db\ncollections Co\nqueue Qu\nA -> Bob : hi Bob\nnote left of A : seq note\n@enduml\n";

void test_inspect_sequence() {
    // Click regions name lifeline boxes and message anchors, not the participant
    var a = inspect_as(SEQUENCE_SRC, DiagramType.SEQUENCE, "A_top");
    expect_str(a.kind, "Participant", "kind");
    expect_str(a.id, "A", "id");
    expect_str(a.label, "Alice X", "label");
    expect_str(a.stereotype, "x", "stereotype");
    expect_str(a.color, "#red", "color");
    expect_str(a.note, "seq note", "note");
    expect_str(inspect_as(SEQUENCE_SRC, DiagramType.SEQUENCE, "A_m0").id, "A", "message anchor");

    string[] names = { "Bob_bottom", "Bo_top", "Ct_top", "En_top", "Db_top", "Co_top", "Qu_top" };
    string[] kinds = { "Actor", "Boundary", "Control", "Entity", "Database", "Collections", "Queue" };
    for (int i = 0; i < names.length; i++) {
        var p = inspect_as(SEQUENCE_SRC, DiagramType.SEQUENCE, names[i]);
        expect_str(p.kind, kinds[i], names[i]);
        expect_int(p.line, i + 3, names[i] + " line");
        assert(p.declared);
    }
}

const string OBJECT_SRC = "@startuml\nobject \"My Obj\" as o1 <<s>> #pink\nobject user\no1 --> user\nnote right of user : obj note\n@enduml\n";

void test_inspect_object() {
    var o1 = inspect_as(OBJECT_SRC, DiagramType.OBJECT, "o1");
    expect_str(o1.kind, "Object", "kind");
    expect_str(o1.label, "My Obj", "label");
    expect_str(o1.stereotype, "s", "stereotype");
    expect_str(o1.color, "#pink", "color");

    var user = inspect_as(OBJECT_SRC, DiagramType.OBJECT, "user");
    expect_str(user.note, "obj note", "note");
}

// "device" is drawn as a node by the component parser (no separate deployment type)
const string DEVICE_SRC = "@startuml\ndevice \"Server 1\" as S1 <<linux>> #lightblue\ndevice Phone\nS1 --> Phone\nnote right of Phone : dep note\n@enduml\n";

void test_inspect_device() {
    var s1 = inspect_as(DEVICE_SRC, DiagramType.COMPONENT, "S1");
    expect_str(s1.kind, "Node", "kind");
    expect_str(s1.label, "Server 1", "label");
    expect_str(s1.stereotype, "linux", "stereotype");
    expect_str(s1.color, "#lightblue", "color");

    var phone = inspect_as(DEVICE_SRC, DiagramType.COMPONENT, "Phone");
    expect_str(phone.note, "dep note", "note");
}

const string ER_SRC = "@startuml\nentity \"User Table\" as U #pink {\n  id : int\n}\nentity Order\nU ||--|| Order\nnote right of U : er note\n@enduml\n";

void test_inspect_er() {
    var u = inspect_as(ER_SRC, DiagramType.ER_DIAGRAM, "U");
    expect_str(u.kind, "Entity", "kind");
    expect_str(u.label, "User Table", "label");
    expect_str(u.color, "#pink", "color");
    expect_str(u.note, "er note", "note");

    // The inline colour used to be left unread and became an entity, and the body after
    // it turned "id" and "int" into entities too
    var r = parse_as(ER_SRC, DiagramType.ER_DIAGRAM);
    expect_int(((ERDiagram) r.ast).entities.size, 2, "entity count");
    expect_str(((ERDiagram) r.ast).find_entity("U").color, "#pink", "parsed colour");
}

void test_inspect_uncovered_type() {
    string src = "@startuml\nstart\n:Hello;\nstop\n@enduml\n";
    var r = parse_as(src, DiagramType.ACTIVITY);
    var info = ElementInspector.inspect(r.diagram_type, r.ast, "action_1", 3, src);
    assert(info != null);
    assert(!info.editable);
    expect_str(info.id, "action_1", "id");
    expect_int(info.line, 3, "line");
    assert(ElementInspector.set_label(info, src, "x") == null);
    assert(ElementInspector.rename(info, src, "x") == null);
}

// ==================== set_label ====================

void test_label_quoted_keeps_alias_stereotype_color() {
    var info = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    string? out_src = ElementInspector.set_label(info, CLASS_SRC, "Your Class");
    assert(out_src != null);
    expect_str(line_of(out_src, 2), "class \"Your Class\" as C <<entity>> #pink", "line");
    var c = find_class(parse_as(out_src, DiagramType.CLASS), "C");
    expect_str(c.display_name, "Your Class", "parsed label");
    expect_str(c.stereotype, "entity", "parsed stereotype");
    expect_str(c.color, "#pink", "parsed colour");
}

void test_label_bare_moves_name_to_alias() {
    var info = inspect_as(CLASS_SRC, DiagramType.CLASS, "Foo");
    string? out_src = ElementInspector.set_label(info, CLASS_SRC, "Nice Foo");
    assert(out_src != null);
    expect_str(line_of(out_src, 3), "class \"Nice Foo\" as Foo", "line");
    var r = parse_as(out_src, DiagramType.CLASS);
    expect_str(find_class(r, "Foo").display_name, "Nice Foo", "parsed label");
    // The relationship still resolves to the same class
    expect_int(((ClassDiagram) r.ast).classes.size, 3, "class count");
    expect_str(((ClassDiagram) r.ast).relationships[0].from.name, "Foo", "relationship source");
}

void test_label_written_after_as() {
    var info = inspect_as(CLASS_SRC, DiagramType.CLASS, "Bar");
    string? out_src = ElementInspector.set_label(info, CLASS_SRC, "Other");
    expect_str(line_of(out_src, 4), "class Bar as \"Other\"", "line");
    expect_str(find_class(parse_as(out_src, DiagramType.CLASS), "Bar").display_name, "Other", "parsed label");
}

void test_label_empty_collapses_to_id() {
    var info = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    string? out_src = ElementInspector.set_label(info, CLASS_SRC, "");
    expect_str(line_of(out_src, 2), "class C <<entity>> #pink", "line");
    var c = find_class(parse_as(out_src, DiagramType.CLASS), "C");
    expect_str(c.stereotype, "entity", "parsed stereotype");
}

void test_label_rejections() {
    var info = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    assert(ElementInspector.set_label(info, CLASS_SRC, "say \"hi\"") == null);
    // Unchanged label: text comes back as is
    expect_str(ElementInspector.set_label(inspect_as(CLASS_SRC, DiagramType.CLASS, "Foo"), CLASS_SRC, "Foo"),
               CLASS_SRC, "no-op");

    // A spaced shorthand name can't become an alias: rename it first
    string spaced = "@startuml\n[Web Server]\n[Web Server] --> [DB]\n@enduml\n";
    var web = inspect_as(spaced, DiagramType.COMPONENT, "Web Server");
    assert(ElementInspector.set_label(web, spaced, "Frontend") == null);
}

// A shorthand name moves into the alias: `[Database]` -> `[Main DB] as Database`
void test_label_shorthand_moves_name_to_alias() {
    string src = "@startuml\n[Database]\n[Web] --> [Database]\n@enduml\n";
    var db = inspect_as(src, DiagramType.COMPONENT, "Database");
    string? out_src = ElementInspector.set_label(db, src, "Main DB");
    expect_str(line_of(out_src, 2), "[Main DB] as Database", "declaration");
    var d = (ComponentDiagram) parse_as(out_src, DiagramType.COMPONENT).ast;
    int named = 0;
    foreach (var comp in d.components) {
        if (comp.get_identifier() == "Database") {
            named++;
            expect_str(comp.get_display_label(), "Main DB", "label");
        }
    }
    expect_int(named, 1, "one Database component");
    expect_int(d.relationships.size, 1, "relationship kept");

    // The business "/" marker stays with the use case text
    string uc = "@startuml\n(Buy)/\nUser --> (Buy)\n@enduml\n";
    var buy = inspect_as(uc, DiagramType.USECASE, "Buy");
    string? uc_out = ElementInspector.set_label(buy, uc, "Buy now");
    expect_str(line_of(uc_out, 2), "(Buy now)/ as Buy", "business use case");
    parse_as(uc_out, DiagramType.USECASE);
}

void test_label_other_types() {
    // component with bracket label and alias
    var db = inspect_as(COMPONENT_SRC, DiagramType.COMPONENT, "DB");
    string? s = ElementInspector.set_label(db, COMPONENT_SRC, "Main DB");
    expect_str(line_of(s, 3), "[Main DB] as DB", "bracket line");
    var comp = ((ComponentDiagram) parse_as(s, DiagramType.COMPONENT).ast).find_component("DB");
    expect_str(comp.label, "Main DB", "parsed component label");
    assert(ElementInspector.set_label(db, COMPONENT_SRC, "a]b") == null);

    // sequence participant written bare
    var bob = inspect_as(SEQUENCE_SRC, DiagramType.SEQUENCE, "Bob_top");
    s = ElementInspector.set_label(bob, SEQUENCE_SRC, "Bob B");
    expect_str(line_of(s, 3), "actor \"Bob B\" as Bob", "sequence line");
    var seq = (SequenceDiagram) parse_as(s, DiagramType.SEQUENCE).ast;
    var p = seq.find_participant("Bob");
    assert(p != null);
    expect_str(p.name, "Bob B", "parsed participant name");
    expect_int(seq.participants.size, 8, "participant count");

    // use case written in parentheses
    var uc2 = inspect_as(USECASE_SRC, DiagramType.USECASE, "UC2");
    s = ElementInspector.set_label(uc2, USECASE_SRC, "Buy Things");
    expect_str(line_of(s, 4), "(Buy Things) as UC2", "use case line");
    expect_str(((UseCaseDiagram) parse_as(s, DiagramType.USECASE).ast).find_usecase("UC2").name,
               "Buy Things", "parsed use case");

    // state
    var s1 = inspect_as(STATE_SRC, DiagramType.STATE, "S1");
    s = ElementInspector.set_label(s1, STATE_SRC, "Short");
    expect_str(line_of(s, 2), "state \"Short\" as S1 #pink", "state line");
    expect_str(((StateDiagram) parse_as(s, DiagramType.STATE).ast).find_state("S1").label, "Short", "parsed state");

    // object written bare
    var user = inspect_as(OBJECT_SRC, DiagramType.OBJECT, "user");
    s = ElementInspector.set_label(user, OBJECT_SRC, "The User");
    expect_str(line_of(s, 3), "object \"The User\" as user", "object line");
    expect_str(((ObjectDiagram) parse_as(s, DiagramType.OBJECT).ast).find_object("user").name, "The User", "parsed object");

    // device (a node)
    var phone = inspect_as(DEVICE_SRC, DiagramType.COMPONENT, "Phone");
    s = ElementInspector.set_label(phone, DEVICE_SRC, "My Phone");
    expect_str(line_of(s, 3), "device \"My Phone\" as Phone", "device line");
    expect_str(((ComponentDiagram) parse_as(s, DiagramType.COMPONENT).ast).find_component("Phone").label, "My Phone", "parsed device");

    // ER entity with a body
    var u = inspect_as(ER_SRC, DiagramType.ER_DIAGRAM, "U");
    s = ElementInspector.set_label(u, ER_SRC, "Users");
    expect_str(line_of(s, 2), "entity \"Users\" as U #pink {", "entity line");
    var er = (ERDiagram) parse_as(s, DiagramType.ER_DIAGRAM).ast;
    expect_str(er.find_entity("U").name, "Users", "parsed entity");
    expect_int(er.find_entity("U").attributes.size, 1, "entity body kept");
}

// ==================== set_stereotype ====================

void test_stereotype_edits() {
    // change, next to a colour
    var c = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    string? s = ElementInspector.set_stereotype(c, CLASS_SRC, "table");
    expect_str(line_of(s, 2), "class \"My Class\" as C <<table>> #pink", "change");
    var parsed = find_class(parse_as(s, DiagramType.CLASS), "C");
    expect_str(parsed.stereotype, "table", "parsed change");
    expect_str(parsed.color, "#pink", "colour kept");

    // remove
    s = ElementInspector.set_stereotype(c, CLASS_SRC, "");
    expect_str(line_of(s, 2), "class \"My Class\" as C #pink", "remove");
    parsed = find_class(parse_as(s, DiagramType.CLASS), "C");
    assert(parsed.stereotype == null);
    expect_str(parsed.color, "#pink", "colour kept after remove");

    // add, written with angle brackets
    var foo = inspect_as(CLASS_SRC, DiagramType.CLASS, "Foo");
    s = ElementInspector.set_stereotype(foo, CLASS_SRC, "<<service>>");
    expect_str(line_of(s, 3), "class Foo <<service>>", "add");
    expect_str(find_class(parse_as(s, DiagramType.CLASS), "Foo").stereotype, "service", "parsed add");

    // add before an existing colour
    string src = "@startuml\nclass Foo #pink\n@enduml\n";
    s = ElementInspector.set_stereotype(inspect_as(src, DiagramType.CLASS, "Foo"), src, "svc");
    expect_str(line_of(s, 2), "class Foo <<svc>> #pink", "add before colour");
    parsed = find_class(parse_as(s, DiagramType.CLASS), "Foo");
    expect_str(parsed.stereotype, "svc", "parsed stereotype before colour");
    expect_str(parsed.color, "#pink", "parsed colour after stereotype");

    assert(ElementInspector.set_stereotype(foo, CLASS_SRC, "a>>b") == null);

    // other types
    var a = inspect_as(SEQUENCE_SRC, DiagramType.SEQUENCE, "A_top");
    s = ElementInspector.set_stereotype(a, SEQUENCE_SRC, "boss");
    expect_str(line_of(s, 2), "participant \"Alice X\" as A <<boss>> #red", "sequence");
    expect_str(((SequenceDiagram) parse_as(s, DiagramType.SEQUENCE).ast).find_participant("A").stereotype,
               "boss", "parsed sequence stereotype");

    // (keyword form: gDiagram's component parser drops a stereotype after "[X] as Y")
    var cache = inspect_as(COMPONENT_SRC, DiagramType.COMPONENT, "Cache");
    s = ElementInspector.set_stereotype(cache, COMPONENT_SRC, "db");
    expect_str(line_of(s, 4), "component Cache <<db>>", "component");
    expect_str(((ComponentDiagram) parse_as(s, DiagramType.COMPONENT).ast).find_component("Cache").stereotype,
               "db", "parsed component stereotype");

    var uc1 = inspect_as(USECASE_SRC, DiagramType.USECASE, "UC1");
    s = ElementInspector.set_stereotype(uc1, USECASE_SRC, "main");
    expect_str(line_of(s, 3), "usecase \"Log in\" as UC1 <<main>>", "use case");
    expect_str(((UseCaseDiagram) parse_as(s, DiagramType.USECASE).ast).find_usecase("UC1").stereotype,
               "main", "parsed use case stereotype");
}

// ==================== set_color ====================

void test_color_edits() {
    // change, next to a stereotype
    var c = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    string? s = ElementInspector.set_color(c, CLASS_SRC, "#FF0000");
    expect_str(line_of(s, 2), "class \"My Class\" as C <<entity>> #FF0000", "change");
    var parsed = find_class(parse_as(s, DiagramType.CLASS), "C");
    expect_str(parsed.color, "#FF0000", "parsed change");
    expect_str(parsed.stereotype, "entity", "stereotype kept");

    // remove
    s = ElementInspector.set_color(c, CLASS_SRC, "");
    expect_str(line_of(s, 2), "class \"My Class\" as C <<entity>>", "remove");
    assert(find_class(parse_as(s, DiagramType.CLASS), "C").color == null);

    // add, named colour without '#'
    var foo = inspect_as(CLASS_SRC, DiagramType.CLASS, "Foo");
    s = ElementInspector.set_color(foo, CLASS_SRC, "red");
    expect_str(line_of(s, 3), "class Foo #red", "add");
    expect_str(find_class(parse_as(s, DiagramType.CLASS), "Foo").color, "#red", "parsed add");

    assert(ElementInspector.set_color(foo, CLASS_SRC, "red blue") == null);

    // other types: the parsed AST must carry the colour
    var guest = inspect_as(USECASE_SRC, DiagramType.USECASE, "UC1");
    s = ElementInspector.set_color(guest, USECASE_SRC, "#yellow");
    expect_str(line_of(s, 3), "usecase \"Log in\" as UC1 #yellow", "use case");
    expect_str(((UseCaseDiagram) parse_as(s, DiagramType.USECASE).ast).find_usecase("UC1").color,
               "#yellow", "parsed use case colour");

    var user = inspect_as(OBJECT_SRC, DiagramType.OBJECT, "user");
    s = ElementInspector.set_color(user, OBJECT_SRC, "#00FF00");
    expect_str(line_of(s, 3), "object user #00FF00", "object");
    expect_str(((ObjectDiagram) parse_as(s, DiagramType.OBJECT).ast).find_object("user").color,
               "#00FF00", "parsed object colour");

    var order = inspect_as(ER_SRC, DiagramType.ER_DIAGRAM, "Order");
    s = ElementInspector.set_color(order, ER_SRC, "#lightgreen");
    expect_str(line_of(s, 5), "entity Order #lightgreen", "entity");
    expect_str(((ERDiagram) parse_as(s, DiagramType.ER_DIAGRAM).ast).find_entity("Order").color,
               "#lightgreen", "parsed entity colour");

    var idle = inspect_as(STATE_SRC, DiagramType.STATE, "Idle");
    s = ElementInspector.set_color(idle, STATE_SRC, "#orange");
    expect_str(line_of(s, 3), "state Idle <<choice>> #orange", "state");
    expect_str(((StateDiagram) parse_as(s, DiagramType.STATE).ast).find_state("Idle").color,
               "#orange", "parsed state colour");

    var s1 = inspect_as(DEVICE_SRC, DiagramType.COMPONENT, "S1");
    s = ElementInspector.set_color(s1, DEVICE_SRC, "");
    expect_str(line_of(s, 2), "device \"Server 1\" as S1 <<linux>>", "device remove");
    assert(((ComponentDiagram) parse_as(s, DiagramType.COMPONENT).ast).find_component("S1").color == null);

    var bob = inspect_as(SEQUENCE_SRC, DiagramType.SEQUENCE, "Bob_top");
    s = ElementInspector.set_color(bob, SEQUENCE_SRC, "#pink");
    expect_str(line_of(s, 3), "actor Bob #pink", "sequence");
    expect_str(((SequenceDiagram) parse_as(s, DiagramType.SEQUENCE).ast).find_participant("Bob").color,
               "pink", "parsed sequence colour");
}

// ==================== Undeclared elements ====================

void test_undeclared_gets_declaration_above_first_use() {
    string src = "@startuml\nclass Foo\nFoo --> Undeclared\n@enduml\n";
    var info = inspect_as(src, DiagramType.CLASS, "Undeclared");
    assert(!info.declared);
    expect_int(info.line, 3, "first use line");

    string? s = ElementInspector.set_color(info, src, "#pink");
    expect_str(s, "@startuml\nclass Foo\nclass Undeclared #pink\nFoo --> Undeclared\n@enduml\n", "inserted colour");
    expect_str(find_class(parse_as(s, DiagramType.CLASS), "Undeclared").color, "#pink", "parsed colour");

    s = ElementInspector.set_label(info, src, "Now Declared");
    expect_str(line_of(s, 3), "class \"Now Declared\" as Undeclared", "inserted label");
    var r = parse_as(s, DiagramType.CLASS);
    expect_str(find_class(r, "Undeclared").display_name, "Now Declared", "parsed label");
    expect_int(((ClassDiagram) r.ast).classes.size, 2, "no duplicate class");

    // Inside a package body the declaration keeps the indentation and the scope
    string pkg = "@startuml\npackage P {\n  class A\n  A --> B\n}\n@enduml\n";
    var b = inspect_as(pkg, DiagramType.CLASS, "B");
    s = ElementInspector.set_stereotype(b, pkg, "svc");
    expect_str(line_of(s, 4), "  class B <<svc>>", "indented insert");
    expect_str(find_class(parse_as(s, DiagramType.CLASS), "B").stereotype, "svc", "parsed stereotype");
}

// ==================== rename ====================

void test_rename_skips_strings_comments_and_longer_words() {
    string src = "@startuml\nclass Foo\nclass FooBar\nFoo --> FooBar : Foo uses\nnote \"Foo\" as N1\n' Foo comment\nFoo .. N1\nnote right of Foo\nFoo in a note body\nend note\n@enduml\n";
    var info = inspect_as(src, DiagramType.CLASS, "Foo");
    string? s = ElementInspector.rename(info, src, "Baz");
    expect_str(s, "@startuml\nclass Baz\nclass FooBar\nBaz --> FooBar : Foo uses\nnote \"Foo\" as N1\n' Foo comment\nBaz .. N1\nnote right of Baz\nFoo in a note body\nend note\n@enduml\n", "renamed");

    var r = parse_as(s, DiagramType.CLASS);
    var d = (ClassDiagram) r.ast;
    bool has_foo = false;
    foreach (var c in d.classes) {
        if (c.name == "Foo") has_foo = true;
    }
    assert(!has_foo);
    find_class(r, "Baz");
    find_class(r, "FooBar");
    expect_str(d.relationships[0].from.name, "Baz", "relationship source");
}

void test_rename_rejections() {
    var info = inspect_as(CLASS_SRC, DiagramType.CLASS, "Foo");
    assert(ElementInspector.rename(info, CLASS_SRC, "C") == null);        // already used
    assert(ElementInspector.rename(info, CLASS_SRC, "1abc") == null);     // not an identifier
    assert(ElementInspector.rename(info, CLASS_SRC, "has space") == null);
    expect_str(ElementInspector.rename(info, CLASS_SRC, "Foo"), CLASS_SRC, "no-op");

    // A delimited id can't take text that closes its delimiters, or a name already written
    string src = "@startuml\nusecase \"Log in\"\n(Sign up)\n@enduml\n";
    var r = parse_as(src, DiagramType.USECASE);
    var uc = ElementInspector.inspect(r.diagram_type, r.ast, "Log in", 0, src);
    assert(uc != null);
    assert(ElementInspector.rename(uc, src, "say \"hi\"") == null);
    assert(ElementInspector.rename(uc, src, "Sign up") == null);
}

// Ids written only inside delimiters are renamed in their delimiters; labels after " : " stay
void test_rename_delimited_ids() {
    string src = "@startuml\nusecase \"Log in\"\nUser --> (Log in) : wants to (Log in)\n@enduml\n";
    var r = parse_as(src, DiagramType.USECASE);
    var uc = ElementInspector.inspect(r.diagram_type, r.ast, "Log in", 0, src);
    assert(uc != null);
    string? s = ElementInspector.rename(uc, src, "Sign in");
    expect_str(s, "@startuml\nusecase \"Sign in\"\nUser --> (Sign in) : wants to (Log in)\n@enduml\n", "use case rename");
    var ud = (UseCaseDiagram) parse_as(s, DiagramType.USECASE).ast;
    assert(ud.find_usecase("Sign in") != null);
    assert(ud.find_usecase("Log in") == null);

    string comp = "@startuml\n[Web Server]\n[Web Server] --> [DB]\n@enduml\n";
    var web = inspect_as(comp, DiagramType.COMPONENT, "Web Server");
    s = ElementInspector.rename(web, comp, "Frontend");
    expect_str(s, "@startuml\n[Frontend]\n[Frontend] --> [DB]\n@enduml\n", "component rename");
    var cd = (ComponentDiagram) parse_as(s, DiagramType.COMPONENT).ast;
    int old_named = 0;
    foreach (var c in cd.components) {
        if (c.get_identifier() == "Web Server") old_named++;
    }
    expect_int(old_named, 0, "no Web Server left");
}

void test_rename_sequence_and_actor_shorthand() {
    string src = "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob : hi Bob\nBob->Alice: Bob again\nnote over Bob\nBob is here\nend note\n@enduml\n";
    var info = inspect_as(src, DiagramType.SEQUENCE, "Bob_top");
    string? s = ElementInspector.rename(info, src, "Robert");
    expect_str(s, "@startuml\nparticipant Alice\nparticipant Robert\nAlice -> Robert : hi Bob\nRobert->Alice: Bob again\nnote over Robert\nBob is here\nend note\n@enduml\n", "sequence rename");
    var seq = (SequenceDiagram) parse_as(s, DiagramType.SEQUENCE).ast;
    assert(seq.find_participant("Robert") != null);
    assert(seq.find_participant("Bob") == null);

    string uc = "@startuml\n:Guest: --> (Buy)\nactor Admin\nAdmin --> (Buy)\n@enduml\n";
    var guest = inspect_as(uc, DiagramType.USECASE, "Guest");
    s = ElementInspector.rename(guest, uc, "Visitor");
    expect_str(line_of(s, 2), ":Visitor: --> (Buy)", "colon actor");
    var ud = (UseCaseDiagram) parse_as(s, DiagramType.USECASE).ast;
    assert(ud.find_actor("Visitor") != null);
    assert(ud.find_actor("Guest") == null);
}

// ==================== Review findings: PlantUML ====================
// Each edited source (and its original) is written to $ELEMENT_INSPECTOR_PUML_DIR when
// set, so it can be checked against the PlantUML jar (valid, same element count).

string puml_edit(string name, string src, string? text) {
    if (text == null) {
        printerr("\nedit %s returned null\n", name);
        assert_not_reached();
    }
    string? dir = Environment.get_variable("ELEMENT_INSPECTOR_PUML_DIR");
    if (dir != null) {
        try {
            FileUtils.set_contents(Path.build_filename(dir, name + ".orig.puml"), src);
            FileUtils.set_contents(Path.build_filename(dir, name + ".puml"), text);
        } catch (FileError e) {
            printerr("dump %s: %s\n", name, e.message);
        }
    }
    return text;
}

int participant_count(string src) {
    return ((SequenceDiagram) parse_as(src, DiagramType.SEQUENCE).ast).participants.size;
}

// A quoted declaration name, or a quoted reference, is the id: rename rewrites it in
// its quotes instead of splitting the element in two
void test_review_rename_quoted_declaration() {
    string q1 = "@startuml\nparticipant \"Bob\" #red\nAlice -> Bob : hi Bob\n@enduml\n";
    string s = puml_edit("rq_participant", q1, ElementInspector.rename(
        inspect_as(q1, DiagramType.SEQUENCE, "Bob_top"), q1, "Rob"));
    expect_str(s, "@startuml\nparticipant \"Rob\" #red\nAlice -> Rob : hi Bob\n@enduml\n", "quoted participant");
    expect_int(participant_count(s), 2, "no split participant");
    assert(((SequenceDiagram) parse_as(s, DiagramType.SEQUENCE).ast).find_participant("Rob").color != null);

    string q2 = "@startuml\nclass \"Foo\" <<S>>\nclass Bar\nFoo --> Bar\n@enduml\n";
    s = puml_edit("rq_class", q2, ElementInspector.rename(inspect_as(q2, DiagramType.CLASS, "Foo"), q2, "Baz"));
    expect_str(s, "@startuml\nclass \"Baz\" <<S>>\nclass Bar\nBaz --> Bar\n@enduml\n", "quoted class");
    expect_int(((ClassDiagram) parse_as(s, DiagramType.CLASS).ast).classes.size, 2, "class count");
    expect_str(find_class(parse_as(s, DiagramType.CLASS), "Baz").stereotype, "S", "stereotype kept");

    string rev = "@startuml\nparticipant Bob\nAlice -> \"Bob\" : hi\n@enduml\n";
    s = puml_edit("rq_reverse", rev, ElementInspector.rename(inspect_as(rev, DiagramType.SEQUENCE, "Bob_top"), rev, "Rob"));
    expect_str(s, "@startuml\nparticipant Rob\nAlice -> \"Rob\" : hi\n@enduml\n", "quoted reference");
    expect_int(participant_count(s), 2, "reverse participant count");

    string umlaut = "@startuml\nparticipant \"Größe\"\nGröße -> Bob : hi\n@enduml\n";
    s = puml_edit("rq_umlaut", umlaut, ElementInspector.rename(
        inspect_as(umlaut, DiagramType.SEQUENCE, "Größe"), umlaut, "Size"));
    expect_str(s, "@startuml\nparticipant \"Size\"\nSize -> Bob : hi\n@enduml\n", "non-ASCII id");
    expect_int(participant_count(s), 2, "umlaut participant count");

    // Quoted text that is a label, or only contains the word, stays
    string labels = "@startuml\nclass Foo\nclass \"Foo\" as F2\nclass Bar as \"Foo\"\nclass \"Foo thing\" as F3\nFoo --> F2\n@enduml\n";
    s = puml_edit("rq_labels", labels, ElementInspector.rename(inspect_as(labels, DiagramType.CLASS, "Foo"), labels, "Baz"));
    expect_str(s, "@startuml\nclass Baz\nclass \"Foo\" as F2\nclass Bar as \"Foo\"\nclass \"Foo thing\" as F3\nBaz --> F2\n@enduml\n", "labels stay");
}

// The new id may not exist already in any written form
void test_review_rename_clash_any_form() {
    string quoted = "@startuml\nclass \"Bar\"\nclass Foo\nFoo --> Bar\n@enduml\n";
    assert(ElementInspector.rename(inspect_as(quoted, DiagramType.CLASS, "Foo"), quoted, "Bar") == null);

    string bracket = "@startuml\n[Web Server]\ndatabase DB\n[Web Server] --> DB\n@enduml\n";
    var web = inspect_as(bracket, DiagramType.COMPONENT, "Web Server");
    assert(ElementInspector.rename(web, bracket, "DB") == null);
    // A free name still works
    string s = puml_edit("rc_bracket_ok", bracket, ElementInspector.rename(web, bracket, "Frontend"));
    expect_str(s, "@startuml\n[Frontend]\ndatabase DB\n[Frontend] --> DB\n@enduml\n", "free name");

    string shorthand = "@startuml\n[Cache]\ncomponent Foo\nFoo --> [Cache]\n@enduml\n";
    assert(ElementInspector.rename(inspect_as(shorthand, DiagramType.COMPONENT, "Foo"), shorthand, "Cache") == null);
}

// A delimited name followed by "as Alias" is a label: its words are not references
void test_review_rename_skips_delimited_labels() {
    string uc = "@startuml\n:Main Admin: as Admin\n(Use the Admin) as UA\nAdmin --> UA\n@enduml\n";
    string s = puml_edit("rl_usecase", uc, ElementInspector.rename(inspect_as(uc, DiagramType.USECASE, "Admin"), uc, "Boss"));
    expect_str(s, "@startuml\n:Main Admin: as Boss\n(Use the Admin) as UA\nBoss --> UA\n@enduml\n", "use case labels");
    var ud = (UseCaseDiagram) parse_as(s, DiagramType.USECASE).ast;
    assert(ud.find_actor("Boss") != null);
    expect_str(ud.find_usecase("UA").name, "Use the Admin", "use case label kept");

    string comp = "@startuml\n[Web Server] as Server\nServer --> [DB]\n@enduml\n";
    s = puml_edit("rl_component", comp, ElementInspector.rename(inspect_as(comp, DiagramType.COMPONENT, "Server"), comp, "Srv"));
    expect_str(s, "@startuml\n[Web Server] as Srv\nSrv --> [DB]\n@enduml\n", "component label");
    expect_str(((ComponentDiagram) parse_as(s, DiagramType.COMPONENT).ast).find_component("Srv").label,
               "Web Server", "component label kept");
}

void test_review_rename_after_double_arrow_head() {
    string src = "@startuml\nparticipant Alice\nparticipant Bob\nBob <<- Alice : hi\nBob <<-- Alice\n@enduml\n";
    // The reference after the arrow head is the one the "<<" stereotype skip swallowed
    string s = puml_edit("ra_arrows", src, ElementInspector.rename(inspect_as(src, DiagramType.SEQUENCE, "Alice_top"), src, "Ann"));
    expect_str(s, "@startuml\nparticipant Ann\nparticipant Bob\nBob <<- Ann : hi\nBob <<-- Ann\n@enduml\n", "<<- arrows");
    expect_int(participant_count(s), 2, "participant count");
}

// Prose is never renamed: note bodies after headers with quotes or "::", group labels,
// dividers, delays, return values, header/footer/title/legend text, [ ] descriptions
void test_review_rename_skips_prose() {
    string n1 = "@startuml\nparticipant Alice\nparticipant \"Long Name\" as L\nAlice -> L : hi\nnote over Alice, \"Long Name\"\n  Alice waits here\nend note\n@enduml\n";
    string s = puml_edit("rp_note_quote", n1, ElementInspector.rename(inspect_as(n1, DiagramType.SEQUENCE, "Alice_top"), n1, "Ann"));
    expect_str(s, "@startuml\nparticipant Ann\nparticipant \"Long Name\" as L\nAnn -> L : hi\nnote over Ann, \"Long Name\"\n  Alice waits here\nend note\n@enduml\n", "note header with quote");

    string n2 = "@startuml\nclass Foo {\n  bar()\n}\nnote right of Foo::bar\n  Foo calls this\nend note\n@enduml\n";
    s = puml_edit("rp_note_member", n2, ElementInspector.rename(inspect_as(n2, DiagramType.CLASS, "Foo"), n2, "Baz"));
    expect_str(s, "@startuml\nclass Baz {\n  bar()\n}\nnote right of Baz::bar\n  Foo calls this\nend note\n@enduml\n", "note on a member");

    string seq = "@startuml\ncenter header Bob report\ntitle\n  Bob and Alice\nend title\nparticipant Alice\nbox \"Bob\" #LightBlue\nparticipant Bob\nend box\nalt Bob is busy\n  Alice -> Bob : ping\nelse Bob is free\n  Bob -> Alice : pong\nend\ngroup Bob phase\n  Alice -> Bob\nend\nloop Bob retries\n  Alice -> Bob\nend\n== Bob phase ==\n... Bob waits ...\nAlice -> Bob : call\nactivate Bob\nreturn Bob result\nref over Bob\n  Bob internals\nend ref\nlegend\n  Bob legend\nendlegend\n@enduml\n";
    s = puml_edit("rp_sequence", seq, ElementInspector.rename(inspect_as(seq, DiagramType.SEQUENCE, "Bob_top"), seq, "Rob"));
    expect_str(s, "@startuml\ncenter header Bob report\ntitle\n  Bob and Alice\nend title\nparticipant Alice\nbox \"Bob\" #LightBlue\nparticipant Rob\nend box\nalt Bob is busy\n  Alice -> Rob : ping\nelse Bob is free\n  Rob -> Alice : pong\nend\ngroup Bob phase\n  Alice -> Rob\nend\nloop Bob retries\n  Alice -> Rob\nend\n== Bob phase ==\n... Bob waits ...\nAlice -> Rob : call\nactivate Rob\nreturn Bob result\nref over Rob\n  Bob internals\nend ref\nlegend\n  Bob legend\nendlegend\n@enduml\n", "sequence prose");
    expect_int(participant_count(s), 2, "sequence participant count");

    string desc = "@startuml\ncomponent Web [\n  Web front end\n  talks to DB\n]\ncomponent DB\nWeb --> DB\n@enduml\n";
    s = puml_edit("rp_description", desc, ElementInspector.rename(inspect_as(desc, DiagramType.COMPONENT, "DB"), desc, "Store"));
    expect_str(s, "@startuml\ncomponent Web [\n  Web front end\n  talks to DB\n]\ncomponent Store\nWeb --> Store\n@enduml\n", "multi-line description");
}

// PlantUML rejects "#red order 10": the colour goes after "order N", a stereotype before it
void test_review_color_after_order() {
    string src = "@startuml\nparticipant Foo order 10\nparticipant Bar\nFoo -> Bar\n@enduml\n";
    var foo = inspect_as(src, DiagramType.SEQUENCE, "Foo_top");
    assert(foo.declared);
    string s = puml_edit("ro_color", src, ElementInspector.set_color(foo, src, "red"));
    expect_str(line_of(s, 2), "participant Foo order 10 #red", "colour after order");
    s = puml_edit("ro_stereo", src, ElementInspector.set_stereotype(foo, src, "S"));
    expect_str(line_of(s, 2), "participant Foo <<S>> order 10", "stereotype before order");
    s = puml_edit("ro_both", s, ElementInspector.set_color(inspect_as(s, DiagramType.SEQUENCE, "Foo_top"), s, "#00FF00"));
    expect_str(line_of(s, 2), "participant Foo <<S>> order 10 #00FF00", "both");
    expect_int(participant_count(s), 2, "participant count");
}

// Only the first stereotype is edited; the others stay
void test_review_stereotype_keeps_others() {
    string src = "@startuml\nclass Foo <<A>> <<B>>\n@enduml\n";
    var foo = inspect_as(src, DiagramType.CLASS, "Foo");
    expect_str(foo.stereotype, "A", "first stereotype");
    string s = puml_edit("rs_change", src, ElementInspector.set_stereotype(foo, src, "C"));
    expect_str(line_of(s, 2), "class Foo <<C>> <<B>>", "change first");
    s = puml_edit("rs_clear", src, ElementInspector.set_stereotype(foo, src, ""));
    expect_str(line_of(s, 2), "class Foo <<B>>", "clear first");
    expect_str(find_class(parse_as(s, DiagramType.CLASS), "Foo").stereotype, "B", "parsed remaining");
}

// A fill colour does not replace border/line styling
void test_review_color_keeps_border() {
    string src = "@startuml\nclass Foo ##[dashed]red\n@enduml\n";
    var foo = inspect_as(src, DiagramType.CLASS, "Foo");
    string s = puml_edit("rb_border", src, ElementInspector.set_color(foo, src, "blue"));
    expect_str(line_of(s, 2), "class Foo #blue ##[dashed]red", "fill before border");

    string both = "@startuml\nclass Foo #pink;line:red\n@enduml\n";
    var f2 = inspect_as(both, DiagramType.CLASS, "Foo");
    s = puml_edit("rb_line_change", both, ElementInspector.set_color(f2, both, "blue"));
    expect_str(line_of(s, 2), "class Foo #blue;line:red", "fill part replaced");
    s = puml_edit("rb_line_clear", both, ElementInspector.set_color(f2, both, ""));
    expect_str(line_of(s, 2), "class Foo #line:red", "fill part removed");

    string line_only = "@startuml\nclass Foo #line:red\n@enduml\n";
    s = puml_edit("rb_line_add", line_only, ElementInspector.set_color(
        inspect_as(line_only, DiagramType.CLASS, "Foo"), line_only, "blue"));
    expect_str(line_of(s, 2), "class Foo #blue;line:red", "fill added to line styling");
}

// "class Foo<T>" declares Foo
void test_review_generic_class() {
    string src = "@startuml\nclass Foo<T>\nclass Bar\nFoo --> Bar\n@enduml\n";
    var foo = inspect_as(src, DiagramType.CLASS, "Foo");
    assert(foo.declared);
    expect_int(foo.line, 2, "declaration line");
    string s = puml_edit("rg_label", src, ElementInspector.set_label(foo, src, "New"));
    expect_str(s, "@startuml\nclass \"New\" as Foo<T>\nclass Bar\nFoo --> Bar\n@enduml\n", "label");
    expect_int(((ClassDiagram) parse_as(s, DiagramType.CLASS).ast).classes.size, 2, "label class count");
    string back = ElementInspector.set_label(inspect_as(s, DiagramType.CLASS, "Foo"), s, "");
    expect_str(back, src, "label removed again");
    s = puml_edit("rg_color", src, ElementInspector.set_color(foo, src, "red"));
    expect_str(s, "@startuml\nclass Foo<T> #red\nclass Bar\nFoo --> Bar\n@enduml\n", "colour");
    s = puml_edit("rg_stereo", src, ElementInspector.set_stereotype(foo, src, "S"));
    expect_str(line_of(s, 2), "class Foo<T> <<S>>", "stereotype");
}

// An element declared in an !include'd file is not edited in the including file
void test_review_included_declaration() {
    string dir;
    try {
        dir = DirUtils.make_tmp("inspector-XXXXXX");
        FileUtils.set_contents(Path.build_filename(dir, "inc.iuml"), "participant Bob #red\nparticipant Carol\n");
    } catch (Error e) {
        printerr("%s\n", e.message);
        assert_not_reached();
    }
    string src = "@startuml\n!include inc.iuml\nAlice -> Bob : hi\nAlice -> Carol\n@enduml\n";
    string pre = engine().preprocess(src, dir);
    var r = parse_as(pre, DiagramType.SEQUENCE);

    var bob = ElementInspector.inspect(r.diagram_type, r.ast, "Bob_top", 0, src);
    assert(bob != null && !bob.declared);
    assert(!bob.can_label && !bob.can_stereotype && !bob.can_color && !bob.can_rename);
    assert(bob.read_only_reason != null);
    assert(ElementInspector.set_color(bob, src, "blue") == null);
    assert(ElementInspector.rename(bob, src, "Rob") == null);

    // Unstyled: a declaration here is harmless, a rename would orphan the included one
    var carol = ElementInspector.inspect(r.diagram_type, r.ast, "Carol_top", 0, src);
    assert(carol != null && carol.can_color && !carol.can_rename);
    assert(ElementInspector.rename(carol, src, "Caroline") == null);

    // Without includes nothing changes
    string plain = "@startuml\nAlice -> Bob : hi\n@enduml\n";
    var pb = inspect_as(plain, DiagramType.SEQUENCE, "Bob_top");
    assert(pb.can_rename && pb.can_color && pb.read_only_reason == null);

    FileUtils.remove(Path.build_filename(dir, "inc.iuml"));
    DirUtils.remove(dir);
}

void test_review_create_participant() {
    string src = "@startuml\nAlice -> Bob : hi\ncreate participant Foo\nAlice -> Foo : new\n@enduml\n";
    var foo = inspect_as(src, DiagramType.SEQUENCE, "Foo_top");
    assert(foo.declared);
    expect_int(foo.line, 3, "create line");
    string s = puml_edit("rcreate_color", src, ElementInspector.set_color(foo, src, "red"));
    expect_str(s, "@startuml\nAlice -> Bob : hi\ncreate participant Foo #red\nAlice -> Foo : new\n@enduml\n", "colour on create");
    s = puml_edit("rcreate_label", src, ElementInspector.set_label(foo, src, "The Foo"));
    expect_str(line_of(s, 3), "create participant \"The Foo\" as Foo", "label on create");
    expect_int(participant_count(s), 3, "participant count");
}

// ==================== Mermaid ====================
// Each edited source is also written to $ELEMENT_INSPECTOR_MMD_DIR (when set) so it
// can be checked against the real Mermaid CLI.

void dump_mmd(string name, string? text) {
    string? dir = Environment.get_variable("ELEMENT_INSPECTOR_MMD_DIR");
    if (dir == null || text == null) return;
    try {
        FileUtils.set_contents(Path.build_filename(dir, name + ".mmd"), text);
    } catch (FileError e) {
        printerr("dump %s: %s\n", name, e.message);
    }
}

// An edit that must apply: dumped, non-null
string edited(string name, string? text) {
    if (text == null) {
        printerr("\nedit %s returned null\n", name);
        assert_not_reached();
    }
    dump_mmd(name, text);
    return text;
}

FlowchartNode flow_node(string src, string id) {
    var node = ((MermaidFlowchart) parse_as(src, DiagramType.MERMAID_FLOWCHART).ast).find_node(id);
    if (node == null) {
        printerr("\nno node %s in:\n%s\n", id, src);
        assert_not_reached();
    }
    return node;
}

const string FLOW_SRC = "flowchart TD\n    %% A comment naming A, B and C\n    A[Start] --> B{Is it ok?}\n    B -->|B says C| C(Round)\n    B -- \"text with C\" --> D((Circle))\n    C --> E>Flag]\n    D --> F[/Slanted/]\n    E --> G[\"Quoted (x)\"]\n    F --> H\n    style A fill:#f9f,stroke:#333,stroke-width:4px\n";

void test_mermaid_flowchart_inspect() {
    dump_mmd("flow_src", FLOW_SRC);
    var a = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "A");
    expect_str(a.kind, "Node", "kind");
    expect_str(a.id, "A", "id");
    expect_str(a.label, "Start", "label");
    expect_str(a.color, "#f9f", "colour from the style line");
    expect_int(a.line, 3, "line");
    assert(a.editable && a.declared);
    assert(a.can_label && a.can_color && a.can_rename && !a.can_stereotype);

    string[] ids = { "B", "C", "D", "E", "F", "G" };
    string[] labels = { "Is it ok?", "Round", "Circle", "Flag", "Slanted", "Quoted (x)" };
    int[] decl_lines = { 3, 4, 5, 6, 7, 8 };
    for (int i = 0; i < ids.length; i++) {
        var n = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, ids[i]);
        expect_str(n.label, labels[i], ids[i] + " label");
        expect_int(n.line, decl_lines[i], ids[i] + " line");
        // gDiagram parsed the same text
        expect_str(flow_node(FLOW_SRC, ids[i]).text, labels[i], ids[i] + " parsed label");
    }
    var h = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "H");
    assert(!h.declared);
    expect_str(h.label, "H", "shapeless label");
    expect_int(h.line, 9, "first use");

    // Click regions name nodes by their DOT id: "-" becomes "_"
    string num = "flowchart LR\n    my-node[One] --> other\n";
    expect_str(inspect_as(num, DiagramType.MERMAID_FLOWCHART, "my_node").label, "One", "sanitized id");

    var r = parse_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART);
    assert(ElementInspector.inspect(r.diagram_type, r.ast, "Nope", 0, FLOW_SRC) == null);
    assert(ElementInspector.is_covered(DiagramType.MERMAID_FLOWCHART));
}

void test_mermaid_flowchart_label() {
    string s = edited("flow_label_rect", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "A"), FLOW_SRC, "Begin"));
    expect_str(line_of(s, 3), "    A[Begin] --> B{Is it ok?}", "rectangle");
    expect_str(flow_node(s, "A").text, "Begin", "parsed rectangle");
    expect_str(flow_node(s, "A").fill_color, "#f9f", "style kept");

    s = edited("flow_label_rhombus", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "B"), FLOW_SRC, "Yes or no"));
    expect_str(line_of(s, 3), "    A[Start] --> B{Yes or no}", "rhombus");
    expect_str(flow_node(s, "B").text, "Yes or no", "parsed rhombus");
    assert(flow_node(s, "B").shape == FlowchartNodeShape.RHOMBUS);

    s = edited("flow_label_circle", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "D"), FLOW_SRC, "Ring"));
    expect_str(line_of(s, 5), "    B -- \"text with C\" --> D((Ring))", "circle");
    assert(flow_node(s, "D").shape == FlowchartNodeShape.CIRCLE);
    expect_str(flow_node(s, "D").text, "Ring", "parsed circle");

    s = edited("flow_label_asym", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "E"), FLOW_SRC, "a (b) [c]"));
    expect_str(line_of(s, 6), "    C --> E>\"a (b) [c]\"]", "special characters get quoted");
    expect_str(flow_node(s, "E").text, "a (b) [c]", "parsed quoted");
    assert(flow_node(s, "E").shape == FlowchartNodeShape.ASYMMETRIC);

    s = edited("flow_label_round", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "C"), FLOW_SRC, "Soft"));
    expect_str(line_of(s, 4), "    B -->|B says C| C(Soft)", "round");
    expect_str(flow_node(s, "C").text, "Soft", "parsed round");

    s = edited("flow_label_parallelogram", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "F"), FLOW_SRC, "Input"));
    expect_str(line_of(s, 7), "    D --> F[/Input/]", "parallelogram");
    assert(flow_node(s, "F").shape == FlowchartNodeShape.PARALLELOGRAM);
    expect_str(flow_node(s, "F").text, "Input", "parsed parallelogram");

    // Written with quotes: stays quoted
    s = edited("flow_label_quoted", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "G"), FLOW_SRC, "Plain"));
    expect_str(line_of(s, 8), "    E --> G[\"Plain\"]", "quoted kept");
    expect_str(flow_node(s, "G").text, "Plain", "parsed quoted");

    // A node without a shape gets one at its first use
    s = edited("flow_label_shapeless", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "H"), FLOW_SRC, "Hello"));
    expect_str(line_of(s, 9), "    F --> H[Hello]", "shape added");
    expect_str(flow_node(s, "H").text, "Hello", "parsed added shape");

    // Empty label: a rectangle loses its brackets, other shapes show the id
    s = edited("flow_label_empty", ElementInspector.set_label(
        inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "A"), FLOW_SRC, ""));
    expect_str(line_of(s, 3), "    A --> B{Is it ok?}", "empty rectangle");
    expect_str(flow_node(s, "A").text, "A", "parsed empty");
    s = ElementInspector.set_label(inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "B"), FLOW_SRC, "");
    expect_str(line_of(s, 3), "    A[Start] --> B{B}", "empty rhombus");

    var a = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "A");
    assert(ElementInspector.set_label(a, FLOW_SRC, "say \"hi\"") == null);
    expect_str(ElementInspector.set_label(inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "H"), FLOW_SRC, "H"),
               FLOW_SRC, "no-op");
    assert(ElementInspector.set_stereotype(a, FLOW_SRC, "x") == null);
}

void test_mermaid_flowchart_color() {
    // Change: the other style properties stay
    var a = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "A");
    string s = edited("flow_color_change", ElementInspector.set_color(a, FLOW_SRC, "#00FF00"));
    expect_str(line_of(s, 10), "    style A fill:#00FF00,stroke:#333,stroke-width:4px", "change");
    expect_str(flow_node(s, "A").fill_color, "#00FF00", "parsed fill");
    expect_str(flow_node(s, "A").stroke_color, "#333", "stroke kept");

    // Remove the fill, keep the line for the stroke
    s = edited("flow_color_remove", ElementInspector.set_color(a, FLOW_SRC, ""));
    expect_str(line_of(s, 10), "    style A stroke:#333,stroke-width:4px", "remove");
    assert(flow_node(s, "A").fill_color == null);
    expect_str(flow_node(s, "A").stroke_width, "4", "stroke width kept");

    // Add: a new style line; a named colour loses the '#'
    var b = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "B");
    s = edited("flow_color_add", ElementInspector.set_color(b, FLOW_SRC, "#red"));
    expect_str(s, FLOW_SRC + "    style B fill:red\n", "added line");
    expect_str(flow_node(s, "B").fill_color, "red", "parsed named fill");

    // A style line without fill gets one in front
    string no_fill = "flowchart LR\n    A --> B\n    style B stroke:#333\n";
    s = edited("flow_color_merge", ElementInspector.set_color(
        inspect_as(no_fill, DiagramType.MERMAID_FLOWCHART, "B"), no_fill, "FF0000"));
    expect_str(line_of(s, 3), "    style B fill:#FF0000,stroke:#333", "merged");
    expect_str(flow_node(s, "B").fill_color, "#FF0000", "parsed merged fill");
    expect_str(flow_node(s, "B").stroke_color, "#333", "parsed merged stroke");

    // Removing the only property drops the line
    string only_fill = "flowchart LR\n    A --> B\n    style B fill:#abcdef\n    B --> C\n";
    var ob = inspect_as(only_fill, DiagramType.MERMAID_FLOWCHART, "B");
    expect_str(ob.color, "#abcdef", "read");
    s = edited("flow_color_drop_line", ElementInspector.set_color(ob, only_fill, ""));
    expect_str(s, "flowchart LR\n    A --> B\n    B --> C\n", "line dropped");
    assert(flow_node(s, "B").fill_color == null);

    assert(ElementInspector.set_color(a, FLOW_SRC, "red blue") == null);
    assert(ElementInspector.set_color(a, FLOW_SRC, "rgb(1,2,3)") == null);
    expect_str(ElementInspector.set_color(b, FLOW_SRC, ""), FLOW_SRC, "removing nothing");
}

void test_mermaid_flowchart_rename() {
    var c = inspect_as(FLOW_SRC, DiagramType.MERMAID_FLOWCHART, "C");
    string s = edited("flow_rename", ElementInspector.rename(c, FLOW_SRC, "Cee"));
    // The comment, the |edge label| and the "-- text -->" label keep their C
    expect_str(s, "flowchart TD\n    %% A comment naming A, B and C\n    A[Start] --> B{Is it ok?}\n    B -->|B says C| Cee(Round)\n    B -- \"text with C\" --> D((Circle))\n    Cee --> E>Flag]\n    D --> F[/Slanted/]\n    E --> G[\"Quoted (x)\"]\n    F --> H\n    style A fill:#f9f,stroke:#333,stroke-width:4px\n", "renamed C");
    var d = (MermaidFlowchart) parse_as(s, DiagramType.MERMAID_FLOWCHART).ast;
    assert(d.find_node("C") == null);
    expect_str(d.find_node("Cee").text, "Round", "renamed node keeps its label");
    expect_int(d.nodes.size, 8, "no stray node from label text");

    // The style line follows; shape text naming the id stays
    string src = "flowchart LR\n    A[A and B] --> B\n    style A fill:#f9f\n    click A callback \"A tip\"\n    class A,B important\n";
    s = edited("flow_rename_style", ElementInspector.rename(inspect_as(src, DiagramType.MERMAID_FLOWCHART, "A"), src, "Alpha"));
    expect_str(s, "flowchart LR\n    Alpha[A and B] --> B\n    style Alpha fill:#f9f\n    click Alpha callback \"A tip\"\n    class Alpha,B important\n", "style, click and class lines");
    var n = flow_node(s, "Alpha");
    expect_str(n.text, "A and B", "label");
    expect_str(n.fill_color, "#f9f", "style applied to the renamed node");

    // Unquoted "-- text -->" and "== text ==>" labels are text in Mermaid too. (gDiagram's
    // parser reads the unquoted form as a chain through a node named after the text, so
    // only the rewrite is checked here; the real Mermaid CLI validates the dump.)
    string unquoted = "flowchart LR\n    A -- to B --> B\n    B == A again ==> A\n    A -. via B .-> B\n";
    var ua = inspect_as(unquoted, DiagramType.MERMAID_FLOWCHART, "A");
    s = edited("flow_rename_unquoted_labels", ElementInspector.rename(ua, unquoted, "Start"));
    expect_str(s, "flowchart LR\n    Start -- to B --> B\n    B == A again ==> Start\n    Start -. via B .-> B\n", "unquoted edge labels");

    assert(ElementInspector.rename(c, FLOW_SRC, "B") == null);     // already used
    assert(ElementInspector.rename(c, FLOW_SRC, "end") == null);   // closes blocks
    assert(ElementInspector.rename(c, FLOW_SRC, "1x") == null);
    expect_str(ElementInspector.rename(c, FLOW_SRC, "C"), FLOW_SRC, "no-op");
}

const string SEQ_MMD = "sequenceDiagram\n    %% Bob is mentioned here\n    participant A as Alice\n    actor Bob\n    A->>Bob: Hello Bob\n    Bob-->>A: Hi A\n    A->>Carol: Hey Carol\n    Note right of Bob: Bob thinks\n    loop Every Bob\n        Bob->>Carol: ping\n    end\n";

MermaidActor seq_actor(string src, string id) {
    var a = ((MermaidSequenceDiagram) parse_as(src, DiagramType.MERMAID_SEQUENCE).ast).find_actor(id);
    if (a == null) {
        printerr("\nno actor %s in:\n%s\n", id, src);
        assert_not_reached();
    }
    return a;
}

void test_mermaid_sequence() {
    dump_mmd("seq_src", SEQ_MMD);
    // Click regions: "actor_X" header boxes and "s_X_N" lifeline slots
    var a = inspect_as(SEQ_MMD, DiagramType.MERMAID_SEQUENCE, "actor_A");
    expect_str(a.kind, "Participant", "kind");
    expect_str(a.id, "A", "id");
    expect_str(a.label, "Alice", "label");
    expect_int(a.line, 3, "line");
    assert(a.declared && a.can_label && a.can_rename && !a.can_color && !a.can_stereotype);
    var bob = inspect_as(SEQ_MMD, DiagramType.MERMAID_SEQUENCE, "actor_Bob");
    expect_str(bob.kind, "Actor", "actor kind");
    expect_str(bob.label, "Bob", "bare label");
    expect_str(bob.note, "Bob thinks", "note");
    var carol = inspect_as(SEQ_MMD, DiagramType.MERMAID_SEQUENCE, "s_Carol_2");
    expect_str(carol.id, "Carol", "slot id");
    assert(!carol.declared);
    expect_int(carol.line, 7, "first message");

    // Label: change, remove, add
    string s = edited("seq_label_change", ElementInspector.set_label(a, SEQ_MMD, "Alice Cooper"));
    expect_str(line_of(s, 3), "    participant A as Alice Cooper", "change");
    expect_str(seq_actor(s, "A").alias, "Alice Cooper", "parsed alias");
    s = edited("seq_label_remove", ElementInspector.set_label(a, SEQ_MMD, ""));
    expect_str(line_of(s, 3), "    participant A", "remove");
    assert(seq_actor(s, "A").alias == null);
    s = edited("seq_label_add", ElementInspector.set_label(bob, SEQ_MMD, "Bobby"));
    expect_str(line_of(s, 4), "    actor Bob as Bobby", "add");
    expect_str(seq_actor(s, "Bob").alias, "Bobby", "parsed added alias");
    assert(!seq_actor(s, "Bob").is_participant);

    // A participant only used in messages is declared above its first message
    s = edited("seq_label_undeclared", ElementInspector.set_label(carol, SEQ_MMD, "Caroline"));
    expect_str(s, "sequenceDiagram\n    %% Bob is mentioned here\n    participant A as Alice\n    actor Bob\n    A->>Bob: Hello Bob\n    Bob-->>A: Hi A\n    participant Carol as Caroline\n    A->>Carol: Hey Carol\n    Note right of Bob: Bob thinks\n    loop Every Bob\n        Bob->>Carol: ping\n    end\n", "inserted declaration");
    var d = (MermaidSequenceDiagram) parse_as(s, DiagramType.MERMAID_SEQUENCE).ast;
    expect_str(d.find_actor("Carol").alias, "Caroline", "parsed inserted alias");
    expect_int(d.actors.size, 3, "no duplicate participant");
    expect_int(d.messages.size, 4, "messages kept");

    assert(ElementInspector.set_label(a, SEQ_MMD, "a;b") == null);
    assert(ElementInspector.set_color(a, SEQ_MMD, "red") == null);
    assert(ElementInspector.set_stereotype(a, SEQ_MMD, "x") == null);

    // Rename: message and note text, the comment and the loop label keep "Bob"
    s = edited("seq_rename", ElementInspector.rename(bob, SEQ_MMD, "Robert"));
    expect_str(s, "sequenceDiagram\n    %% Bob is mentioned here\n    participant A as Alice\n    actor Robert\n    A->>Robert: Hello Bob\n    Robert-->>A: Hi A\n    A->>Carol: Hey Carol\n    Note right of Robert: Bob thinks\n    loop Every Bob\n        Robert->>Carol: ping\n    end\n", "renamed");
    d = (MermaidSequenceDiagram) parse_as(s, DiagramType.MERMAID_SEQUENCE).ast;
    assert(d.find_actor("Bob") == null);
    assert(!d.find_actor("Robert").is_participant);
    expect_int(d.actors.size, 3, "actor count");
    expect_str(d.messages[1].from.id, "Robert", "message source");
    expect_str(d.notes[0].text, "Bob thinks", "note text untouched");

    // The alias text is not an id
    string alias_src = "sequenceDiagram\n    participant A as A friend\n    A->>A: self\n";
    s = edited("seq_rename_alias", ElementInspector.rename(
        inspect_as(alias_src, DiagramType.MERMAID_SEQUENCE, "actor_A"), alias_src, "Z"));
    expect_str(s, "sequenceDiagram\n    participant Z as A friend\n    Z->>Z: self\n", "alias untouched");
    expect_str(seq_actor(s, "Z").alias, "A friend", "parsed alias after rename");
    assert(ElementInspector.rename(bob, SEQ_MMD, "Carol") == null);
}

const string CLASS_MMD = "classDiagram\n    %% Animal comment\n    class Animal\n    <<interface>> Animal\n    class Duck {\n        <<service>>\n        +String beakColor\n        +swim()\n    }\n    class Fish\n    class Shape <<abstract>>\n    Animal <|-- Duck : Animal link\n    Animal <|-- Fish\n    Animal <|-- Zebra\n";

MermaidClass mclass(string src, string name) {
    var c = ((MermaidClassDiagram) parse_as(src, DiagramType.MERMAID_CLASS).ast).find_class(name);
    if (c == null) {
        printerr("\nno class %s in:\n%s\n", name, src);
        assert_not_reached();
    }
    return c;
}

void test_mermaid_class() {
    dump_mmd("class_src", CLASS_MMD);
    var animal = inspect_as(CLASS_MMD, DiagramType.MERMAID_CLASS, "Animal");
    expect_str(animal.kind, "Interface", "standalone annotation sets the kind");
    expect_str(animal.stereotype, "interface", "standalone annotation");
    expect_int(animal.line, 3, "line");
    assert(animal.can_stereotype && animal.can_rename && !animal.can_label && !animal.can_color);
    expect_str(inspect_as(CLASS_MMD, DiagramType.MERMAID_CLASS, "Duck").stereotype, "service", "body annotation");
    var shape = inspect_as(CLASS_MMD, DiagramType.MERMAID_CLASS, "Shape");
    expect_str(shape.stereotype, "abstract", "inline annotation");
    expect_str(shape.kind, "Abstract class", "abstract kind");
    var zebra = inspect_as(CLASS_MMD, DiagramType.MERMAID_CLASS, "Zebra");
    assert(!zebra.declared);
    expect_int(zebra.line, 14, "first use");
    // `<<interface>> Animal` used to create a class named "interface"
    var d = (MermaidClassDiagram) parse_as(CLASS_MMD, DiagramType.MERMAID_CLASS).ast;
    assert(d.find_class("interface") == null);
    expect_int(d.classes.size, 5, "class count");

    // Standalone: change, remove the line
    string s = edited("class_stereo_standalone", ElementInspector.set_stereotype(animal, CLASS_MMD, "<<base>>"));
    expect_str(line_of(s, 4), "    <<base>> Animal", "standalone change");
    expect_str(mclass(s, "Animal").stereotype, "base", "parsed standalone");
    s = edited("class_stereo_standalone_remove", ElementInspector.set_stereotype(animal, CLASS_MMD, ""));
    expect_str(line_of(s, 4), "    class Duck {", "standalone line removed");
    assert(mclass(s, "Animal").stereotype == null);

    // Body: change, remove the line (members stay)
    var duck = inspect_as(CLASS_MMD, DiagramType.MERMAID_CLASS, "Duck");
    s = edited("class_stereo_body", ElementInspector.set_stereotype(duck, CLASS_MMD, "entity"));
    expect_str(line_of(s, 6), "        <<entity>>", "body change");
    expect_str(mclass(s, "Duck").stereotype, "entity", "parsed body");
    s = edited("class_stereo_body_remove", ElementInspector.set_stereotype(duck, CLASS_MMD, ""));
    expect_str(line_of(s, 6), "        +String beakColor", "body line removed");
    assert(mclass(s, "Duck").stereotype == null);
    expect_int(mclass(s, "Duck").members.size, 2, "members kept");

    // Inline: remove, add
    s = edited("class_stereo_inline_remove", ElementInspector.set_stereotype(shape, CLASS_MMD, ""));
    expect_str(line_of(s, 11), "    class Shape", "inline removed");
    assert(mclass(s, "Shape").stereotype == null);
    s = edited("class_stereo_inline_add", ElementInspector.set_stereotype(
        inspect_as(CLASS_MMD, DiagramType.MERMAID_CLASS, "Fish"), CLASS_MMD, "model"));
    expect_str(line_of(s, 10), "    class Fish <<model>>", "inline added");
    expect_str(mclass(s, "Fish").stereotype, "model", "parsed inline add");

    // Undeclared: a declaration above the first use (Mermaid rejects `<<x>> Zebra`
    // before anything created Zebra)
    s = edited("class_stereo_undeclared", ElementInspector.set_stereotype(zebra, CLASS_MMD, "striped"));
    expect_str(line_of(s, 14), "    class Zebra <<striped>>", "inserted");
    expect_str(line_of(s, 15), "    Animal <|-- Zebra", "above first use");
    expect_str(mclass(s, "Zebra").stereotype, "striped", "parsed inserted");
    expect_int(((MermaidClassDiagram) parse_as(s, DiagramType.MERMAID_CLASS).ast).classes.size, 5, "no extra class");

    // A class with a body gets the annotation as the first body line
    string body = "classDiagram\n    class Cat {\n        +meow()\n    }\n";
    s = edited("class_stereo_body_add", ElementInspector.set_stereotype(
        inspect_as(body, DiagramType.MERMAID_CLASS, "Cat"), body, "pet"));
    expect_str(s, "classDiagram\n    class Cat {\n        <<pet>>\n        +meow()\n    }\n", "body add");
    expect_str(mclass(s, "Cat").stereotype, "pet", "parsed body add");
    expect_int(mclass(s, "Cat").members.size, 1, "member kept");

    assert(ElementInspector.set_stereotype(animal, CLASS_MMD, "two words") == null);
    assert(ElementInspector.set_label(animal, CLASS_MMD, "Beast") == null);
    assert(ElementInspector.set_color(animal, CLASS_MMD, "red") == null);

    // Rename: comment, relationship label and body members stay
    s = edited("class_rename", ElementInspector.rename(animal, CLASS_MMD, "Creature"));
    expect_str(s, "classDiagram\n    %% Animal comment\n    class Creature\n    <<interface>> Creature\n    class Duck {\n        <<service>>\n        +String beakColor\n        +swim()\n    }\n    class Fish\n    class Shape <<abstract>>\n    Creature <|-- Duck : Animal link\n    Creature <|-- Fish\n    Creature <|-- Zebra\n", "renamed");
    d = (MermaidClassDiagram) parse_as(s, DiagramType.MERMAID_CLASS).ast;
    assert(d.find_class("Animal") == null);
    expect_str(d.find_class("Creature").stereotype, "interface", "annotation follows");
    expect_int(d.relations.size, 3, "relations kept");
    expect_str(d.relations[0].from.name, "Creature", "relation source");
    expect_str(d.relations[0].label, "Animal link", "relation label untouched");
    assert(ElementInspector.rename(animal, CLASS_MMD, "Duck") == null);
}

const string STATE_MMD = "stateDiagram-v2\n    %% Idle comment\n    state \"Waiting for input\" as Idle\n    [*] --> Idle\n    Idle --> Busy : Idle ends\n    Busy : working hard\n    Busy --> Done\n    state Done\n    Done --> [*]\n    note right of Busy : Busy note\n";

MermaidState mstate(string src, string id) {
    var st = ((MermaidStateDiagram) parse_as(src, DiagramType.MERMAID_STATE).ast).find_state(id);
    if (st == null) {
        printerr("\nno state %s in:\n%s\n", id, src);
        assert_not_reached();
    }
    return st;
}

void test_mermaid_state() {
    dump_mmd("state_src", STATE_MMD);
    var idle = inspect_as(STATE_MMD, DiagramType.MERMAID_STATE, "Idle");
    expect_str(idle.kind, "State", "kind");
    expect_str(idle.label, "Waiting for input", "quoted label");
    expect_int(idle.line, 3, "line");
    assert(idle.can_label && idle.can_rename && !idle.can_color && !idle.can_stereotype);
    var busy = inspect_as(STATE_MMD, DiagramType.MERMAID_STATE, "Busy");
    expect_str(busy.label, "working hard", "description label");
    expect_int(busy.line, 6, "description line");
    var done = inspect_as(STATE_MMD, DiagramType.MERMAID_STATE, "Done");
    expect_str(done.label, "Done", "bare");
    expect_int(done.line, 8, "state line");
    var r = parse_as(STATE_MMD, DiagramType.MERMAID_STATE);
    assert(ElementInspector.inspect(r.diagram_type, r.ast, "____start", 0, STATE_MMD) == null);
    // `state "Label" as Id` used to create a state named after its label
    var d = (MermaidStateDiagram) r.ast;
    assert(d.find_state("Waiting for input") == null);
    expect_str(d.find_state("Idle").description, "Waiting for input", "parsed quoted label");

    string s = edited("state_label_quoted", ElementInspector.set_label(idle, STATE_MMD, "Ready"));
    expect_str(line_of(s, 3), "    state \"Ready\" as Idle", "quoted change");
    expect_str(mstate(s, "Idle").description, "Ready", "parsed change");
    s = edited("state_label_quoted_remove", ElementInspector.set_label(idle, STATE_MMD, ""));
    expect_str(line_of(s, 3), "    state Idle", "quoted remove");
    assert(mstate(s, "Idle").description == null);

    s = edited("state_label_desc", ElementInspector.set_label(busy, STATE_MMD, "Crunching"));
    expect_str(line_of(s, 6), "    Busy : Crunching", "description change");
    expect_str(mstate(s, "Busy").description, "Crunching", "parsed description");
    s = edited("state_label_desc_remove", ElementInspector.set_label(busy, STATE_MMD, ""));
    expect_str(line_of(s, 6), "    Busy --> Done", "description line removed");
    assert(mstate(s, "Busy").description == null);

    s = edited("state_label_bare", ElementInspector.set_label(done, STATE_MMD, "Finished"));
    expect_str(line_of(s, 8), "    state \"Finished\" as Done", "bare gets a label");
    expect_str(mstate(s, "Done").description, "Finished", "parsed bare label");
    expect_int(((MermaidStateDiagram) parse_as(s, DiagramType.MERMAID_STATE).ast).states.size,
               d.states.size, "no extra state");

    string undeclared = "stateDiagram-v2\n    [*] --> A\n    A --> B\n";
    s = edited("state_label_undeclared", ElementInspector.set_label(
        inspect_as(undeclared, DiagramType.MERMAID_STATE, "B"), undeclared, "Bee"));
    expect_str(s, "stateDiagram-v2\n    [*] --> A\n    state \"Bee\" as B\n    A --> B\n", "inserted");
    expect_str(mstate(s, "B").description, "Bee", "parsed inserted");

    assert(ElementInspector.set_label(idle, STATE_MMD, "say \"hi\"") == null);
    assert(ElementInspector.set_color(idle, STATE_MMD, "red") == null);

    s = edited("state_rename", ElementInspector.rename(busy, STATE_MMD, "Working"));
    expect_str(s, "stateDiagram-v2\n    %% Idle comment\n    state \"Waiting for input\" as Idle\n    [*] --> Idle\n    Idle --> Working : Idle ends\n    Working : working hard\n    Working --> Done\n    state Done\n    Done --> [*]\n    note right of Working : Busy note\n", "renamed");
    d = (MermaidStateDiagram) parse_as(s, DiagramType.MERMAID_STATE).ast;
    assert(d.find_state("Busy") == null);
    expect_str(d.find_state("Working").description, "working hard", "description follows");
    expect_str(d.transitions[1].label, "Idle ends", "transition label untouched");
}

const string ER_MMD = "erDiagram\n    %% CUSTOMER comment\n    CUSTOMER ||--o{ ORDER : \"CUSTOMER places\"\n    ORDER ||--|{ LINE-ITEM : contains\n    CUSTOMER {\n        string name\n        string CUSTOMER\n    }\n";

void test_mermaid_er() {
    dump_mmd("er_src", ER_MMD);
    var c = inspect_as(ER_MMD, DiagramType.MERMAID_ER, "CUSTOMER");
    expect_str(c.kind, "Entity", "kind");
    expect_int(c.line, 5, "body line");
    assert(c.can_rename && !c.can_label && !c.can_color && !c.can_stereotype);
    var li = inspect_as(ER_MMD, DiagramType.MERMAID_ER, "LINE_ITEM");
    expect_str(li.id, "LINE-ITEM", "hyphenated id from the sanitized region name");
    expect_int(li.line, 4, "first use");

    assert(ElementInspector.set_label(c, ER_MMD, "Client") == null);

    string s = edited("er_rename", ElementInspector.rename(c, ER_MMD, "CLIENT"));
    expect_str(s, "erDiagram\n    %% CUSTOMER comment\n    CLIENT ||--o{ ORDER : \"CUSTOMER places\"\n    ORDER ||--|{ LINE-ITEM : contains\n    CLIENT {\n        string name\n        string CUSTOMER\n    }\n", "renamed");
    var d = (MermaidERDiagram) parse_as(s, DiagramType.MERMAID_ER).ast;
    assert(d.find_entity("CUSTOMER") == null);
    expect_int(d.find_entity("CLIENT").attributes.size, 2, "attributes kept");
    expect_str(d.relationships[0].from.name, "CLIENT", "relationship source");
    expect_str(d.relationships[0].label, "CUSTOMER places", "label untouched");

    s = edited("er_rename_hyphen", ElementInspector.rename(li, ER_MMD, "ITEM"));
    expect_str(line_of(s, 4), "    ORDER ||--|{ ITEM : contains", "hyphenated");
    d = (MermaidERDiagram) parse_as(s, DiagramType.MERMAID_ER).ast;
    assert(d.find_entity("LINE-ITEM") == null);
    assert(d.find_entity("ITEM") != null);
}

// ==================== Review findings: Mermaid ====================

// Clearing a label never deletes the element
void test_review_mermaid_clear_keeps_element() {
    string only_desc = "stateDiagram-v2\n    [*] --> A\n    B : waiting\n";
    var b = inspect_as(only_desc, DiagramType.MERMAID_STATE, "B");
    expect_str(b.label, "waiting", "description");
    string s = edited("rv_state_clear_only", ElementInspector.set_label(b, only_desc, ""));
    expect_str(s, "stateDiagram-v2\n    [*] --> A\n    B\n", "state kept");
    assert(mstate(s, "B").description == null);

    // "S:::hot" is a class, not a "::hot" description
    string cls = "stateDiagram-v2\n    classDef hot fill:red\n    [*] --> S\n    S:::hot\n";
    var st = inspect_as(cls, DiagramType.MERMAID_STATE, "S");
    expect_str(ElementInspector.set_label(st, cls, ""), cls, "clearing nothing");
    s = edited("rv_state_class_label", ElementInspector.set_label(st, cls, "New"));
    expect_str(s, "stateDiagram-v2\n    classDef hot fill:red\n    state \"New\" as S\n    [*] --> S\n    S:::hot\n", "label with class kept");
    // (gDiagram's state parser reads "S:::hot" as the description ": : hot"; the Mermaid
    // CLI checks the dumped source instead)

    // The standalone annotation was the only line creating the class
    string ann = "classDiagram\n    <<interface>> Shape\n    class Circle\n";
    var shape = inspect_as(ann, DiagramType.MERMAID_CLASS, "Shape");
    s = edited("rv_class_ann_clear", ElementInspector.set_stereotype(shape, ann, ""));
    expect_str(s, "classDiagram\n    class Shape\n    class Circle\n", "class kept");
    assert(mclass(s, "Shape").stereotype == null);
}

void test_review_mermaid_css_class_rename() {
    string src = "classDiagram\n    class Animal\n    class Duck\n    Animal <|-- Duck\n    cssClass \"Animal,Duck\" hot\n    classDef hot fill:#f96\n";
    string s = edited("rv_css_rename", ElementInspector.rename(
        inspect_as(src, DiagramType.MERMAID_CLASS, "Animal"), src, "Creature"));
    expect_str(s, "classDiagram\n    class Creature\n    class Duck\n    Creature <|-- Duck\n    cssClass \"Creature,Duck\" hot\n    classDef hot fill:#f96\n", "cssClass list");
    assert(ElementInspector.rename(inspect_as(src, DiagramType.MERMAID_CLASS, "Duck"), src, "hot") != null);
}

void test_review_mermaid_pseudo_state_label() {
    string src = "stateDiagram-v2\n    state C <<choice>>\n    [*] --> C\n    C --> A: C yes\n    C --> B\n";
    var c = inspect_as(src, DiagramType.MERMAID_STATE, "C");
    assert(!c.can_label && c.can_rename);
    assert(ElementInspector.set_label(c, src, "Pick") == null);
}

void test_review_mermaid_reserved_ids() {
    string flow = "flowchart LR\n    A---B\n";
    var b = inspect_as(flow, DiagramType.MERMAID_FLOWCHART, "B");
    string s = edited("rv_flow_ops", ElementInspector.rename(b, flow, "ops"));
    expect_str(s, "flowchart LR\n    A--- ops\n", "space before an o-id after a link");
    assert(ElementInspector.rename(b, flow, "style") == null);
    assert(ElementInspector.rename(b, flow, "subgraph") == null);
    edited("rv_flow_Style", ElementInspector.rename(b, flow, "Style"));

    string seq = "sequenceDiagram\n    A->>B: hi\n";
    var sb = inspect_as(seq, DiagramType.MERMAID_SEQUENCE, "actor_B");
    assert(ElementInspector.rename(sb, seq, "note") == null);
    assert(ElementInspector.rename(sb, seq, "Loop") == null);
    edited("rv_seq_left", ElementInspector.rename(sb, seq, "left"));

    string cls = "classDiagram\n    class A\n    A <|-- B\n";
    var ca = inspect_as(cls, DiagramType.MERMAID_CLASS, "A");
    assert(ElementInspector.rename(ca, cls, "namespace") == null);
    edited("rv_class_Note", ElementInspector.rename(ca, cls, "Note"));

    string state = "stateDiagram-v2\n    [*] --> A\n    A --> B\n";
    assert(ElementInspector.rename(inspect_as(state, DiagramType.MERMAID_STATE, "A"), state, "State") == null);

    string er = "erDiagram\n    A ||--o{ B : has\n";
    assert(ElementInspector.rename(inspect_as(er, DiagramType.MERMAID_ER, "A"), er, "Style") == null);
}

void test_review_mermaid_stereotype_after_css_class() {
    string src = "classDiagram\n    classDef hot fill:#f96\n    class A:::hot\n    A <|-- B\n";
    string s = edited("rv_class_css_stereo", ElementInspector.set_stereotype(
        inspect_as(src, DiagramType.MERMAID_CLASS, "A"), src, "interface"));
    expect_str(s, "classDiagram\n    classDef hot fill:#f96\n    class A:::hot\n    <<interface>> A\n    A <|-- B\n", "standalone annotation");
    expect_str(mclass(s, "A").stereotype, "interface", "parsed");
}

void test_review_mermaid_subgraph_title() {
    string src = "flowchart TD\n    subgraph My Group\n        My --> X\n    end\n    subgraph sg1 [Title]\n        X --> Y\n    end\n";
    string s = edited("rv_subgraph_title", ElementInspector.rename(
        inspect_as(src, DiagramType.MERMAID_FLOWCHART, "My"), src, "Boss"));
    expect_str(s, "flowchart TD\n    subgraph My Group\n        Boss --> X\n    end\n    subgraph sg1 [Title]\n        X --> Y\n    end\n", "title kept");
}

void test_review_mermaid_participant_order() {
    string src = "sequenceDiagram\n    A->>B: hi\n";
    string s = edited("rv_seq_order", ElementInspector.set_label(
        inspect_as(src, DiagramType.MERMAID_SEQUENCE, "actor_B"), src, "Bob"));
    expect_str(s, "sequenceDiagram\n    participant A\n    participant B as Bob\n    A->>B: hi\n", "earlier participant declared first");
    var d = (MermaidSequenceDiagram) parse_as(s, DiagramType.MERMAID_SEQUENCE).ast;
    expect_int(d.actors.size, 2, "actor count");
    expect_str(d.actors[0].id, "A", "first lifeline");

    // A note's placement words are not participants
    string note = "sequenceDiagram\n    actor A\n    Note right of A: x\n    A->>C: hi\n";
    s = edited("rv_seq_order_note", ElementInspector.set_label(
        inspect_as(note, DiagramType.MERMAID_SEQUENCE, "actor_C"), note, "Carol"));
    expect_str(s, "sequenceDiagram\n    actor A\n    Note right of A: x\n    participant C as Carol\n    A->>C: hi\n", "declared A needs nothing");
}

void test_review_mermaid_letter_hex() {
    string src = "flowchart TD\n    A --> B\n";
    string s = edited("rv_flow_hex_letters", ElementInspector.set_color(
        inspect_as(src, DiagramType.MERMAID_FLOWCHART, "A"), src, "ABCDEF"));
    expect_str(s, "flowchart TD\n    A --> B\n    style A fill:#ABCDEF\n", "letters-only hex");
    expect_str(flow_node(s, "A").fill_color, "#ABCDEF", "parsed fill");
}

// PlantUML elements keep every edit available
void test_plantuml_capability_flags() {
    var c = inspect_as(CLASS_SRC, DiagramType.CLASS, "C");
    assert(c.can_label && c.can_stereotype && c.can_color && c.can_rename);
    string src = "@startuml\nstart\n:Hello;\nstop\n@enduml\n";
    var r = parse_as(src, DiagramType.ACTIVITY);
    var ro = ElementInspector.inspect(r.diagram_type, r.ast, "action_1", 3, src);
    assert(!ro.editable && !ro.can_label && !ro.can_rename);
}

void main(string[] args) {
    Test.init(ref args);
    Test.add_func("/inspector/inspect/class", test_inspect_class);
    Test.add_func("/inspector/inspect/ie_entity", test_inspect_ie_entity);
    Test.add_func("/inspector/inspect/component", test_inspect_component);
    Test.add_func("/inspector/inspect/usecase", test_inspect_usecase);
    Test.add_func("/inspector/inspect/state", test_inspect_state);
    Test.add_func("/inspector/inspect/sequence", test_inspect_sequence);
    Test.add_func("/inspector/inspect/object", test_inspect_object);
    Test.add_func("/inspector/inspect/device", test_inspect_device);
    Test.add_func("/inspector/inspect/er", test_inspect_er);
    Test.add_func("/inspector/inspect/uncovered", test_inspect_uncovered_type);
    Test.add_func("/inspector/label/quoted", test_label_quoted_keeps_alias_stereotype_color);
    Test.add_func("/inspector/label/bare", test_label_bare_moves_name_to_alias);
    Test.add_func("/inspector/label/after_as", test_label_written_after_as);
    Test.add_func("/inspector/label/empty", test_label_empty_collapses_to_id);
    Test.add_func("/inspector/label/rejections", test_label_rejections);
    Test.add_func("/inspector/label/shorthand", test_label_shorthand_moves_name_to_alias);
    Test.add_func("/inspector/label/other_types", test_label_other_types);
    Test.add_func("/inspector/stereotype", test_stereotype_edits);
    Test.add_func("/inspector/color", test_color_edits);
    Test.add_func("/inspector/undeclared", test_undeclared_gets_declaration_above_first_use);
    Test.add_func("/inspector/rename/strings_comments", test_rename_skips_strings_comments_and_longer_words);
    Test.add_func("/inspector/rename/rejections", test_rename_rejections);
    Test.add_func("/inspector/rename/delimited", test_rename_delimited_ids);
    Test.add_func("/inspector/rename/sequence_actor", test_rename_sequence_and_actor_shorthand);
    Test.add_func("/inspector/mermaid/flowchart/inspect", test_mermaid_flowchart_inspect);
    Test.add_func("/inspector/mermaid/flowchart/label", test_mermaid_flowchart_label);
    Test.add_func("/inspector/mermaid/flowchart/color", test_mermaid_flowchart_color);
    Test.add_func("/inspector/mermaid/flowchart/rename", test_mermaid_flowchart_rename);
    Test.add_func("/inspector/mermaid/sequence", test_mermaid_sequence);
    Test.add_func("/inspector/mermaid/class", test_mermaid_class);
    Test.add_func("/inspector/mermaid/state", test_mermaid_state);
    Test.add_func("/inspector/mermaid/er", test_mermaid_er);
    Test.add_func("/inspector/flags/plantuml", test_plantuml_capability_flags);
    Test.add_func("/inspector/review/rename_quoted", test_review_rename_quoted_declaration);
    Test.add_func("/inspector/review/rename_clash", test_review_rename_clash_any_form);
    Test.add_func("/inspector/review/rename_delimited_labels", test_review_rename_skips_delimited_labels);
    Test.add_func("/inspector/review/rename_double_arrow", test_review_rename_after_double_arrow_head);
    Test.add_func("/inspector/review/rename_prose", test_review_rename_skips_prose);
    Test.add_func("/inspector/review/color_order", test_review_color_after_order);
    Test.add_func("/inspector/review/stereotype_others", test_review_stereotype_keeps_others);
    Test.add_func("/inspector/review/color_border", test_review_color_keeps_border);
    Test.add_func("/inspector/review/generic_class", test_review_generic_class);
    Test.add_func("/inspector/review/include", test_review_included_declaration);
    Test.add_func("/inspector/review/create", test_review_create_participant);
    Test.add_func("/inspector/review/mermaid_clear_keeps_element", test_review_mermaid_clear_keeps_element);
    Test.add_func("/inspector/review/mermaid_css_class_rename", test_review_mermaid_css_class_rename);
    Test.add_func("/inspector/review/mermaid_pseudo_state_label", test_review_mermaid_pseudo_state_label);
    Test.add_func("/inspector/review/mermaid_reserved_ids", test_review_mermaid_reserved_ids);
    Test.add_func("/inspector/review/mermaid_stereotype_css", test_review_mermaid_stereotype_after_css_class);
    Test.add_func("/inspector/review/mermaid_subgraph_title", test_review_mermaid_subgraph_title);
    Test.add_func("/inspector/review/mermaid_participant_order", test_review_mermaid_participant_order);
    Test.add_func("/inspector/review/mermaid_letter_hex", test_review_mermaid_letter_hex);
    Test.add_func("/inspector/class_declaration_keywords", test_inspect_class_declaration_keywords);
    Test.run();
}
