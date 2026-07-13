// Click-to-source regions (GUI smoke test, September 2026): what a click on the preview
// selects. Every region is checked through DiagramEngine.render() -> last_regions: its name,
// its source line, and that the element really has one (actor figures, sequence messages
// and group frames, composite states, history states, deployment containers, ports,
// activity partitions, YAML rows, ditaa shapes). Plus the inspector's view of the new
// region kinds, the line/selection choice behind the editor cursor (ClickNavigation), the
// region parser itself, the stick-figure colours on a dark canvas and the ditaa document
// shape's wavy fill.
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

class Rendered : Object {
    public DiagramType type;
    public Object? ast;
    public string source;
    public double canvas_width;
    public double canvas_height;
    public Gee.ArrayList<ElementRegion> regions = new Gee.ArrayList<ElementRegion>();

    public ElementRegion? find(string name) {
        foreach (var r in regions) {
            if (r.name == name) return r;
        }
        return null;
    }

    public void dump() {
        foreach (var r in regions) {
            printerr("  %s line=%d %.0f,%.0f %.0fx%.0f\n", r.name, r.source_line, r.x, r.y, r.width, r.height);
        }
    }

    // The region `name` exists, has a size and is at `line`
    public ElementRegion expect_region(string name, int line) {
        var r = find(name);
        if (r == null) {
            printerr("\nno region %s; regions:\n", name);
            dump();
            assert_not_reached();
        }
        if (r.width <= 1 || r.height <= 1) {
            printerr("\nregion %s has no size: %.1fx%.1f\n", name, r.width, r.height);
            assert_not_reached();
        }
        if (r.source_line != line) {
            printerr("\nregion %s: line %d, want %d\n", name, r.source_line, line);
            assert_not_reached();
        }
        return r;
    }

    public ElementInfo inspect(string name) {
        var r = find(name);
        var info = ElementInspector.inspect(type, ast, name, r != null ? r.source_line : 0, source);
        if (info == null) {
            printerr("\nno inspector info for %s\n", name);
            assert_not_reached();
        }
        return info;
    }
}

Rendered render(string source, string filename = "t.puml") {
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
    var eng = engine();
    var format = eng.detect_format(source, filename);
    var type = format == DiagramFormat.MERMAID ? eng.detect_mermaid_type(source) : eng.detect_plantuml_type(source);
    var result = eng.render(type, format, source);
    expect_true(result.surface != null, "render failed");
    var r = new Rendered();
    r.type = type;
    r.ast = result.ast;
    r.source = source;
    r.canvas_width = result.surface.get_width();
    r.canvas_height = result.surface.get_height();
    r.regions.add_all(eng.last_regions);
    return r;
}

bool contains_point(ElementRegion r, double x, double y) {
    return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
}

// The region a click at (x, y) hits: the first containing one, as PreviewPane does
string? hit(Rendered r, double x, double y) {
    foreach (var region in r.regions) {
        if (contains_point(region, x, y)) return region.name;
    }
    return null;
}

// ── 0. the static SVG regexes go up as one set ───────────────────

// Five of them were compiled under one "is the first null" check, and the first was
// assigned before the rest were built: a second thread that does not hold EngineLock
// found that one set and the others still null. This runs first in the binary, so the
// set starts empty; one call through any entry point must leave all of them compiled.
void test_svg_regexes_ready_together() {
    expect_true(!RenderUtils.svg_regexes_ready(), "the regexes are compiled before the first call");
    var regions = new Gee.ArrayList<ElementRegion>();
    // No node/cluster/edge group: only the group regex is needed to answer this
    string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10pt\" height=\"10pt\" " +
                 "viewBox=\"0.00 0.00 10.00 10.00\"><g class=\"graph\"></g></svg>";
    RenderUtils.parse_svg_regions(svg.data, regions);
    expect_true(RenderUtils.svg_regexes_ready(), "one call left part of the regex set null");
}

// ── 0b. path bounds: arcs are not coordinate pairs ───────────────

const string DEPLOY_ELEMENTS_SRC =
    "@startuml\naction action\nactor actor\nagent agent\nartifact artifact\nboundary boundary\n" +
    "card card\ncircle circle\ncloud cloud\ncollections collections\ncomponent component\n" +
    "control control\ndatabase database\nentity entity\nfile file\nfolder folder\nframe frame\n" +
    "hexagon hexagon\ninterface interface\nlabel label\nnode node\npackage package\nperson person\n" +
    "process process\nqueue queue\nrectangle rectangle\nstack stack\nstorage storage\n" +
    "usecase usecase\n@enduml\n";

// Every number of a path's "d" used to be pulled out and paired up as x,y. An arc is
// "A rx ry rotation large-arc sweep x y" — seven numbers — so the pairing lost step and
// radii and flags became coordinates: on this source the "queue" region came out
// 2243x2278 and "storage" 2574x2597 on a canvas 2745 wide and 97 high. The element
// shapes here (queue, stack, storage, card, cloud, ...) are the ones Graphviz draws
// with arcs.
void test_path_region_bounds_inside_canvas() {
    var r = render(DEPLOY_ELEMENTS_SRC);
    expect_true(r.canvas_width > 100 && r.canvas_height > 10, "the deployment canvas has a size");
    // Graphviz rounds the canvas to whole points; allow a pixel of slack on each side
    double slack = 2.0;
    int outside = 0;
    foreach (var region in r.regions) {
        if (region.x < -slack || region.y < -slack ||
            region.x + region.width > r.canvas_width + slack ||
            region.y + region.height > r.canvas_height + slack) {
            printerr("\nregion %s %.0f,%.0f %.0fx%.0f leaves the %.0fx%.0f canvas\n",
                     region.name, region.x, region.y, region.width, region.height,
                     r.canvas_width, r.canvas_height);
            outside++;
        }
    }
    expect_int(outside, 0, "regions outside the canvas");
    // The arc-drawn shapes have a region of their own, no taller than the drawing
    foreach (string name in new string[] { "queue", "stack", "storage", "card", "database" }) {
        var region = r.find(name);
        if (region == null) {
            printerr("\nno region for %s\n", name);
            r.dump();
            assert_not_reached();
        }
        expect_true(region.height > 1 && region.height <= r.canvas_height + slack,
                    "%s region %.0f high on a %.0f canvas".printf(name, region.height, r.canvas_height));
        expect_true(region.width > 1 && region.width < r.canvas_width / 2,
                    "%s region %.0f wide on a %.0f canvas".printf(name, region.width, r.canvas_width));
    }
}

// ── 1. actor figures ─────────────────────────────────────────────

const string USECASE_SRC = "@startuml\n:User: --> (Use)\n\"Main Admin\" as Admin\n\"Use the application\" as (Use)\nAdmin --> (Admin the application)\n@enduml\n";

// The figure group holds only <circle>/<path class="gdfigure"> and the label text, with
// extra classes on the group ("node gdactor ..."): it had no region at all
void test_usecase_actor_figure() {
    var r = render(USECASE_SRC);
    var user = r.expect_region("User", 2);
    var admin = r.expect_region("Admin", 3);
    // Figure (head at the top) and label below: taller than wide
    expect_true(user.height > user.width, "the actor region covers figure and label");
    expect_true(admin.height > 50, "the Main Admin region covers figure and label");
    // Top (head) and bottom (label) of the figure hit it
    expect_str(hit(r, user.x + user.width / 2, user.y + 3), "User", "click on the head");
    expect_str(hit(r, user.x + user.width / 2, user.y + user.height - 3), "User", "click on the label");
}

const string SEQ_SRC = "@startuml\nactor User\nparticipant Server\nUser -> Server: login\nalt success\n  Server --> User: ok\nelse failure\n  Server --> User: error\nend\nloop 3 times\n  User -> Server: ping\nend\n@enduml\n";

void test_sequence_actor_figure() {
    var r = render(SEQ_SRC);
    var top = r.expect_region("User_top", 2);
    r.expect_region("User_bottom", 2);
    expect_true(top.height > top.width, "the sequence actor region covers figure and label");
    r.expect_region("Server_top", 3);
}

// ── 2. sequence messages, frames and else sections ───────────────

void test_sequence_messages_and_frames() {
    var r = render(SEQ_SRC);
    var login = r.expect_region("_seq_msg_0", 4);
    r.expect_region("_seq_msg_1", 6);
    r.expect_region("_seq_msg_2", 8);
    r.expect_region("_seq_msg_3", 11);
    var alt = r.expect_region("_seq_frame_0", 5);
    r.expect_region("_seq_frame_1", 10);
    var else_section = r.expect_region("_seq_else_0_0", 7);
    // The message region spans its arrow between the two lifelines, not only the label
    var user = r.find("User_top");
    var server = r.find("Server_top");
    double user_x = user.x + user.width / 2;
    double server_x = server.x + server.width / 2;
    expect_true(login.x <= user_x + 8 && login.x + login.width >= server_x - 8, "message region spans the arrow");
    // The raw label ids are no regions of their own any more
    expect_true(r.find("_seq_lbl_m0") == null && r.find("_seq_ftab0") == null && r.find("_seq_felse0_0") == null,
                "label/tab nodes are merged into their message or frame");
    // Inside the frame, the message wins; on the frame's empty area, the frame
    var ok = r.find("_seq_msg_1");
    expect_str(hit(r, ok.x + ok.width / 2, ok.y + ok.height / 2), "_seq_msg_1", "a message inside a frame");
    expect_str(hit(r, alt.x + alt.width - 3, alt.y + alt.height - 3), "_seq_frame_0", "the frame's corner");
    expect_true(else_section.width > 50, "the else region spans its dashed line");
}

void test_inspector_sequence_kinds() {
    var r = render(SEQ_SRC);
    var msg = r.inspect("_seq_msg_0");
    expect_str(msg.kind, "Message", "message kind");
    expect_str(msg.label, "login", "message label");
    expect_str(msg.id, "User -> Server", "message id");
    expect_int(msg.line, 4, "message line");
    expect_true(!msg.editable, "a message is read-only");
    var alt = r.inspect("_seq_frame_0");
    expect_str(alt.kind, "Alt", "alt kind");
    expect_str(alt.label, "success", "alt condition");
    expect_int(alt.line, 5, "alt line");
    var loop = r.inspect("_seq_frame_1");
    expect_str(loop.kind, "Loop", "loop kind");
    expect_int(loop.line, 10, "loop line");
    var else_info = r.inspect("_seq_else_0_0");
    expect_str(else_info.kind, "Else", "else kind");
    expect_str(else_info.label, "failure", "else condition");
    expect_int(else_info.line, 7, "else line");
    // Hover tooltips name the kind
    expect_str(ElementInspector.hover_name("_seq_msg_0"), "Message", "message tooltip");
    expect_str(ElementInspector.hover_name("_seq_else_0_0"), "Else", "else tooltip");
}

// ── 3. use cases go to their own line ────────────────────────────

void test_usecase_lines_and_navigation() {
    var r = render(USECASE_SRC);
    r.expect_region("Use", 4);
    r.expect_region("Admin_the_application", 5);

    // "Use the application": the declaration line 4, and "Use" there, not inside ":User:"
    var use = r.inspect("Use");
    int line = ClickNavigation.target_line(r.find("Use").source_line, use, 6);
    expect_int(line, 4, "Use navigates to its declaration");
    string[] lines = USECASE_SRC.split("\n");
    int start, end;
    expect_true(ClickNavigation.name_span(lines[line - 1], ClickNavigation.name_candidates("Use", use), out start, out end),
                "a name on the Use line");
    expect_str(lines[line - 1].substring(start, end - start), "Use", "selected text on line 4");

    // "Admin the application": region id Admin_the_application, written with spaces
    var admin = r.inspect("Admin_the_application");
    line = ClickNavigation.target_line(r.find("Admin_the_application").source_line, admin, 6);
    expect_int(line, 5, "Admin the application navigates to line 5");
    expect_true(ClickNavigation.name_span(lines[4], ClickNavigation.name_candidates("Admin_the_application", admin),
                                          out start, out end), "the use case is found on line 5");
    expect_str(lines[4].substring(start, end - start), "Admin the application", "selected text on line 5");
}

// ── 3b. an element first named inside a container gets that line ─

// Only the top-level statement loop moved the use case parser's statement_line on, so
// everything a container body created — a use case first named by a link inside it, an
// implicit actor — was recorded at the container's own "rectangle checkout {" line. A
// click on the "help" ellipse selected the right element and showed it in the properties
// panel, but put the editor cursor on the container's declaration.
const string UC_CONTAINER_SRC =
    "@startuml\nleft to right direction\nactor customer\nrectangle checkout {\n" +
    "  customer -- (checkout)\n  (checkout) .> (payment) : include\n" +
    "  (help) .> (checkout) : extends\n  rectangle Inner {\n    (refund) -- (payment)\n  }\n}\n@enduml\n";

void test_usecase_implicit_element_lines() {
    var r = render(UC_CONTAINER_SRC);
    string[] lines = UC_CONTAINER_SRC.split("\n");

    // name -> the line it is first written on, inside the container
    var want = new Gee.HashMap<string, int>();
    want.set("payment", 6);
    want.set("help", 7);
    want.set("refund", 9);
    foreach (var e in want.entries) {
        var region = r.expect_region(e.key, e.value);
        var info = r.inspect(e.key);
        expect_int(info.line, e.value, "%s: inspector declaration line".printf(e.key));
        int line = ClickNavigation.target_line(region.source_line, info, lines.length);
        expect_int(line, e.value, "%s: cursor line".printf(e.key));
        // and the name itself is selected there, not the whole line
        int start, end;
        expect_true(ClickNavigation.name_span(lines[line - 1],
                                              ClickNavigation.name_candidates(e.key, info), out start, out end),
                    "%s: a name span on line %d".printf(e.key, line));
        expect_str(lines[line - 1].substring(start, end - start), e.key,
                   "%s: selected text".printf(e.key));
    }

    // The explicitly declared actor is unaffected
    var customer = r.inspect("customer");
    expect_int(customer.line, 3, "the declared actor keeps its own line");
}

// The same must hold for the other container-bearing types, which already set their
// statement line inside the body: a component in a package, a state in a composite and
// an activity action in a partition.
void test_container_members_keep_their_own_line() {
    var comp = render("@startuml\npackage Frontend {\n  [Web UI] --> [API Client]\n  [API Client] --> [Cache]\n}\n@enduml\n");
    expect_int(comp.inspect("Cache").line, 4, "a component first named inside a package");
    expect_int(comp.inspect("Web_UI").line, 3, "the first component in the package");

    var st = render("@startuml\n[*] --> Running\nstate Running {\n  Idle --> Busy\n  Busy --> Waiting\n}\n@enduml\n");
    expect_int(st.inspect("Waiting").line, 5, "a state first named inside a composite");
    expect_int(st.inspect("Idle").line, 4, "the first state in the composite");

    var act = render("@startuml\nstart\npartition Setup {\n  :load config;\n  :open port;\n}\nstop\n@enduml\n");
    var open_port = act.find("node2");
    expect_true(open_port != null, "the second partition action has a region");
    expect_int(open_port.source_line, 5, "an action inside a partition");
}

// ── 3c. no region may leave the canvas ───────────────────────────

// Two ways a click region ended up outside the drawing, both found by scanning all 307
// PlantUML examples (41 files affected):
//
//  * a diagram type that maps no regions at all (archimate, chronology, nwdiag, an empty
//    or failed render) left the PREVIOUS diagram's regions in last_regions, so a click
//    picked an element of another file and jumped the cursor to its line;
//  * a group's text extent is estimated from the character count — there are no font
//    metrics here — and the estimate runs wider than the box Graphviz sized around it,
//    so text-heavy nodes (class bodies, notes) stuck out past the right edge.
void test_regions_stay_inside_the_canvas() {
    // A class box whose longest member used to push its region past the drawing
    var r = render("@startuml\nclass Dummy {\n  {static} String id\n  {abstract} void methods()\n}\n@enduml\n");
    var dummy = r.find("Dummy");
    expect_true(dummy != null, "the class has a region");
    expect_true(dummy.x + dummy.width <= r.canvas_width + 2,
                "the class region %.0f+%.0f stays inside the %.0f canvas".printf(
                    dummy.x, dummy.width, r.canvas_width));
    // It still covers the box, not just a sliver of it
    expect_true(dummy.width > r.canvas_width / 2, "the class region still covers the box");

    // A note is a polygon with its text inside: same estimate, same overshoot
    var n = render("@startuml\nclass A\nnote right of A : a fairly long note text here\n@enduml\n");
    foreach (var region in n.regions) {
        expect_true(region.x + region.width <= n.canvas_width + 2 &&
                    region.y + region.height <= n.canvas_height + 2,
                    "region %s %.0f,%.0f %.0fx%.0f leaves the %.0fx%.0f canvas".printf(
                        region.name, region.x, region.y, region.width, region.height,
                        n.canvas_width, n.canvas_height));
    }

    // Text drawn OUTSIDE the group's shapes still grows the region: an actor's label
    // sits below its stick figure and has to stay clickable.
    var uc = render(USECASE_SRC);
    var user = uc.find("User");
    expect_true(user != null && user.height > user.width, "the actor region still covers figure and label");

    // A type that maps no regions must not inherit the last diagram's. The engine is
    // shared across renders here exactly as the GUI shares it across tabs.
    var before = render(CLASS_SRC);
    expect_true(before.regions.size > 0, "the class diagram has regions");
    var after = render("@startuml\narchimate #Business \"Customer\" as cust\n" +
                       "archimate #Application \"Web App\" as app\ncust --> app : uses\n@enduml\n");
    expect_int(after.regions.size, 0, "the archimate render left the class diagram's regions behind");
}

// ── 4. class: the declaration line, for cursor and panel alike ───

const string CLASS_SRC = "@startuml\nabstract class AbstractList\ninterface List\nList <|-- AbstractList\nAbstractList <|-- ArrayList\n\nclass ArrayList {\n  Object[] elementData\n}\n@enduml\n";

void test_class_declaration_line() {
    var r = render(CLASS_SRC);
    r.expect_region("ArrayList", 7);
    var info = r.inspect("ArrayList");
    expect_int(info.line, 7, "inspector line");
    expect_int(ClickNavigation.target_line(r.find("ArrayList").source_line, info, 10), 7, "cursor line");
    r.expect_region("AbstractList", 2);
}

// ── 6. composite states, history, containers, ports, partitions, YAML, ditaa ──

const string STATE_SRC = "@startuml\n[*] -> State1\nState1 --> State3 : go\nstate State3 {\n  [*] --> long1\n  long1 --> [H]\n}\nState1 --> State3[H*]\n@enduml\n";

void test_state_composite_and_history() {
    var r = render(STATE_SRC);
    var composite = r.expect_region("State3", 4);
    var long1 = r.expect_region("long1", 5);
    r.expect_region("State1", 2);
    r.expect_region("_initial_0", 2);
    r.expect_region("_history_0", 6);
    r.expect_region("_history_1", 8);
    // The composite is behind what it holds
    expect_str(hit(r, long1.x + long1.width / 2, long1.y + long1.height / 2), "long1", "a state inside the composite");
    expect_true(composite.width > long1.width && composite.height > long1.height, "the composite region is the box");
    var composite_info = r.inspect("State3");
    expect_str(composite_info.kind, "Composite state", "composite kind");
    expect_int(composite_info.line, 4, "composite declaration line");
    var history = r.inspect("_history_0");
    expect_str(history.kind, "History", "history kind");
    expect_int(history.line, 6, "history line");
    expect_str(r.inspect("_history_1").kind, "Deep history", "deep history kind");
}

const string DEPLOY_SRC = "@startuml\n[c]\nnode node {\n  port p1\n  portin p2\n  file f1\n}\nc --> p1\nc --> p2\np1 --> f1\n@enduml\n";

void test_deployment_container_and_ports() {
    var r = render(DEPLOY_SRC);
    r.expect_region("c", 2);
    var f1 = r.expect_region("f1", 6);
    var node = r.expect_region("node_", 3);
    r.expect_region("p1", 4);
    r.expect_region("p2", 5);
    expect_str(hit(r, f1.x + f1.width / 2, f1.y + f1.height / 2), "f1", "an element inside the node");
    expect_true(node.width > f1.width, "the node region is the container box");
    var p1 = r.inspect("p1");
    expect_str(p1.kind, "Port", "port kind");
    expect_int(p1.line, 4, "port line");
    expect_str(r.inspect("p2").kind, "Port in", "portin kind");
    expect_str(r.inspect("node_").kind, "Node", "container kind");
}

const string ACTIVITY_SRC = "@startuml\n|Customer|\nstart\n:Order;\n|Shop|\npartition Checkout {\n  :Pay;\n}\ngroup Shipping\n  :Send;\nend group\nstop\n@enduml\n";

void test_activity_partitions() {
    var r = render(ACTIVITY_SRC);
    r.expect_region("Customer", 2);
    r.expect_region("Shop", 5);
    var checkout = r.expect_region("Checkout", 6);
    r.expect_region("Shipping", 9);
    // The action inside the partition wins over it
    ElementRegion? pay = null;
    foreach (var region in r.regions) {
        if (region.source_line == 7 && region.name.has_prefix("node")) pay = region;
    }
    expect_true(pay != null, "the action in the partition has a region");
    expect_str(hit(r, pay.x + pay.width / 2, pay.y + pay.height / 2), pay.name, "an action inside a partition");
    expect_true(contains_point(checkout, pay.x + pay.width / 2, pay.y + pay.height / 2), "the partition holds it");
    var info = r.inspect("Checkout");
    expect_str(info.kind, "Partition", "partition kind");
    expect_int(info.line, 6, "partition line");
    expect_str(r.inspect("Customer").kind, "Swimlane", "swimlane kind");
}

const string YAML_SRC = "@startyaml\napplication:\n  name: MyApp\n  version: 2.1.0\nfeatures:\n  - auth\n  - cache\n@endyaml\n";

void test_yaml_rows() {
    var r = render(YAML_SRC);
    // t0 is the root, t1 "application", t2 "features"
    r.expect_region("t0_r0", 2);
    r.expect_region("t0_r1", 5);
    r.expect_region("t1", 2);
    var name = r.expect_region("t1_r0", 3);
    var version = r.expect_region("t1_r1", 4);
    r.expect_region("t2_r0", 6);
    r.expect_region("t2_r1", 7);
    expect_true(version.y >= name.y + name.height - 1, "rows are stacked top to bottom");
    expect_str(hit(r, name.x + name.width / 2, name.y + name.height / 2), "t1_r0", "a click on a row");
    var info = r.inspect("t1_r1");
    expect_str(info.kind, "Entry", "row kind");
    expect_str(info.label, "version: 2.1.0", "row text");
    expect_int(info.line, 4, "row line");
    var item = r.inspect("t2_r1");
    expect_str(item.kind, "Item", "list item kind");
    expect_str(item.label, "cache", "list item text");
    expect_str(r.inspect("t2").kind, "List", "list table kind");
}

const string DITAA_SRC = "@startditaa\n+--------+   +-------+\n|  Text  +---+ ditaa |\n|Document|   +-------+\n|     {d}|\n+--------+\n\n  loose text\n@endditaa\n";

void test_ditaa_shapes() {
    var r = render(DITAA_SRC);
    int shapes = 0;
    foreach (var region in r.regions) {
        expect_true(region.name.has_prefix("_ditaa_"), "ditaa regions are named shapes or text, not DOT nodes: " + region.name);
        if (region.name.has_prefix("_ditaa_shape_")) shapes++;
    }
    expect_int(shapes, 2, "two shapes");
    // The document starts on line 2 (its top border), the ditaa box too; the text on line 8
    var doc = r.expect_region("_ditaa_shape_0", 2);
    r.expect_region("_ditaa_shape_1", 2);
    r.expect_region("_ditaa_text_0", 8);
    // The text inside the document is part of it
    expect_true(doc.height > 40, "the document region covers the shape");
    var info = r.inspect("_ditaa_shape_0");
    expect_str(info.kind, "Shape", "ditaa shape kind");
    expect_int(info.line, 2, "ditaa shape line");
}

// ── 7. stick figures contrast with the canvas ────────────────────

void test_actor_contrast() {
    foreach (string preset in ThemeManager.preset_names()) {
        var palette = ThemeManager.get_preset(preset);
        ThemeManager.set_active_palette(palette);
        string fill, stroke;
        RenderUtils.default_actor_colors(out fill, out stroke);
        double ratio = RenderUtils.contrast_ratio(stroke, palette.background);
        if (ratio < 2.5) {
            printerr("\n%s: actor lines %s on %s, contrast %.2f\n", preset, stroke, palette.background, ratio);
            assert_not_reached();
        }
    }
    // default-dark's person colours hardly show: the figure takes the container colours
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-dark"));
    string fill, stroke;
    RenderUtils.default_actor_colors(out fill, out stroke);
    expect_true(RenderUtils.contrast_ratio(fill, "#1E1E1E") >= 3.0, "dark fill contrast");
    expect_true(RenderUtils.contrast_ratio(stroke, "#1E1E1E") >= 3.0, "dark stroke contrast");
    string? dot = engine().generate_dot(USECASE_SRC, "t.puml", null);
    expect_true(dot != null && !dot.contains("gdstroke_1168BD") && dot.contains("gdstroke_" + stroke.substring(1)),
                "the dark use-case actor is drawn in the contrasting colours");
    // The light theme keeps the C4 person blue
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
    RenderUtils.default_actor_colors(out fill, out stroke);
    expect_str(fill, "#08427B", "light actor fill");
}

// ── 8. ditaa {d}: the fill follows the wavy bottom ───────────────

void test_ditaa_document_fill() {
    ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
    string src = "@startditaa -S\n+--------+\n|        |\n|     {d}|\n+--------+\n@endditaa\n";
    string? dot = engine().generate_dot(src, "t.puml", null);
    expect_true(dot != null, "ditaa DOT");
    // White fill boxes: height= of each; a wavy fill is many strips of different heights
    var heights = new Gee.HashSet<string>();
    int strips = 0;
    try {
        var re = new Regex("fillcolor=\"#FFFFFF\" color=\"#FFFFFF\" penwidth=0 width=[0-9.]+ height=([0-9.]+)");
        MatchInfo m;
        if (re.match(dot, 0, out m)) {
            do {
                strips++;
                heights.add(m.fetch(1));
            } while (m.next());
        }
    } catch (RegexError e) {
        assert_not_reached();
    }
    expect_true(strips >= 16, "the document fill is drawn in strips (%d)".printf(strips));
    expect_true(heights.size >= 4, "the strips follow the wave (%d heights)".printf(heights.size));
}

// ── the region parser ────────────────────────────────────────────

void test_region_parser() {
    string svg = """<svg width="200pt" height="200pt" viewBox="0.00 0.00 200.00 200.00">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 196)">
<g id="clust1" class="cluster">
<title>cluster_0</title>
<polygon fill="none" stroke="black" points="0,-190 190,-190 190,0 0,0 0,-190"/>
</g>
<g id="node1" class="node">
<title>label</title>
<text xml:space="preserve" text-anchor="middle" x="50" y="-100" font-family="Sans" font-size="10.00">hi</text>
</g>
<g id="node2" class="node gdactor gdfill_08427B">
<title>fig</title>
<circle class="gdfigure" cx="120" cy="-150" r="6"/><path class="gdfigure" d="M120,-144 L120,-120"/>
<text x="112" y="-105" font-size="10.00">Fig</text>
</g>
<g id="node3" class="node">
<title>anchored</title>
<g id="a_node3_0"><a xlink:title="x">
<polygon fill="none" points="10,-40 30,-40 30,-20 10,-20 10,-40"/>
</a>
</g>
<polygon fill="none" points="10,-60 60,-60 60,-10 10,-10 10,-60"/>
</g>
<g id="edge1" class="edge">
<title>a&#45;&gt;b</title>
<path fill="none" d="M70,-30 C80,-30 90,-30 100,-30"/>
</g>
<g id="edge2" class="edge">
<title>c&#45;&gt;d</title>
<path fill="none" d="M70,-50 L100,-50"/>
</g>
</g>
</svg>""";
    var regions = new Gee.ArrayList<ElementRegion>();
    var names = new Gee.HashMap<string, string>();
    names.set("cluster_0", "Box");
    names.set("a->b", "anchored");
    var lines = new Gee.HashMap<string, int>();
    lines.set("Box", 3);
    lines.set("anchored", 7);
    RenderUtils.parse_svg_regions(svg.data, regions, lines, 0, 0, names);
    var by_name = new Gee.HashMap<string, ElementRegion>();
    foreach (var r in regions) by_name.set(r.name, r);
    expect_int(regions.size, 4, "label, fig, anchored (+ edge), Box; the unmapped edge is skipped");
    // Text only: y from the y attribute, not from font-famil"y"
    var label = by_name.get("label");
    expect_true(label != null && label.y > 80 && label.y < 96, "text region at its baseline (%.1f)".printf(label.y));
    // Extra classes, circle + path + text
    var fig = by_name.get("fig");
    expect_true(fig != null && fig.y <= 46 - 6 + 0.1 && fig.y + fig.height >= 196 - 105, "actor figure bounds");
    // Nested <g> does not cut the group short: the outer polygon counts, and the mapped
    // edge grows the same region
    var anchored = by_name.get("anchored");
    expect_true(anchored != null && anchored.width >= 90 - 0.1 && anchored.height >= 50 - 0.1, "anchored bounds");
    expect_int(anchored.source_line, 7, "line by region name");
    var box = by_name.get("Box");
    expect_true(box != null && box.source_line == 3, "a mapped cluster");
    // Smallest first
    for (int i = 1; i < regions.size; i++) {
        expect_true(regions[i - 1].width * regions[i - 1].height <= regions[i].width * regions[i].height,
                    "regions are ordered by size");
    }
    expect_str(RenderUtils.decode_xml_text("A&#45;&gt;B &amp; &#246;"), "A->B & ö", "title decoding");
}

// ── ClickNavigation ──────────────────────────────────────────────

void test_click_navigation() {
    var info = new ElementInfo();
    info.line = 15;
    expect_int(ClickNavigation.target_line(13, info, 40), 15, "the inspector's declaration line wins");
    expect_int(ClickNavigation.target_line(13, null, 40), 13, "else the region line");
    info.line = 0;
    expect_int(ClickNavigation.target_line(13, info, 40), 13, "an inspector without line");
    expect_int(ClickNavigation.target_line(99, null, 40), 0, "a line past the end is none");

    int start, end;
    var names = new Gee.ArrayList<string>();
    names.add("Use");
    // Whole words only: not the "Use" in ":User:"
    expect_true(!ClickNavigation.name_span(":User: --> (Usecase)", names, out start, out end), "no partial word");
    expect_true(ClickNavigation.name_span(":User: --> (Use)", names, out start, out end), "whole word");
    expect_int(start, 12, "span start");
    expect_int(end, 15, "span end");
    // Case-insensitive, UTF-8 before the match keeps byte offsets
    names.clear();
    names.add("bob");
    expect_true(ClickNavigation.name_span("\"Ä\" -> Bob", names, out start, out end), "case-insensitive");
    expect_str("\"Ä\" -> Bob".substring(start, end - start), "Bob", "span on UTF-8 text");

    // Candidates: suffixes stripped, underscores as spaces, generated ids never
    var c = ClickNavigation.name_candidates("Foo_top", null);
    expect_true(c.contains("Foo"), "lifeline suffix stripped");
    c = ClickNavigation.name_candidates("Admin_the_application", null);
    expect_true(c.contains("Admin the application"), "underscores as spaces");
    c = ClickNavigation.name_candidates("_seq_msg_3", null);
    expect_int(c.size, 0, "a generated id is not searched for");
}

// ── containers are click targets (September 2026 smoke test) ─────

// A click on a package title, or on the empty space inside one, did nothing: the class
// renderer never told parse_svg_regions the names of its package clusters, and clusters
// are only taken when named. Composite states and deployment nodes already were.
const string CLASS_PACKAGE_SRC =
    "@startuml\n" +                     // 1
    "class Outside\n" +                 // 2
    "package Core {\n" +                // 3
    "  class Inner\n" +                 // 4
    "}\n" +                             // 5
    "Outside --> Inner : uses\n" +      // 6
    "@enduml\n";                        // 7

// PreviewGeometry.pick() is what PreviewPane asks; a region list it can read
Gee.ArrayList<DiagramRegion> pickable(Rendered r) {
    var list = new Gee.ArrayList<DiagramRegion>();
    foreach (var region in r.regions) {
        list.add(new DiagramRegion(region.name, region.source_line,
                                   region.x, region.y, region.width, region.height));
    }
    return list;
}

void test_class_package_is_clickable() {
    var r = render(CLASS_PACKAGE_SRC);
    var pkg = r.expect_region("Core", 3);
    var inner = r.expect_region("Inner", 4);
    var regions = pickable(r);

    // The package box holds the class it contains
    expect_true(pkg.width > inner.width && pkg.height > inner.height, "the package region is the cluster box");
    expect_true(inner.x > pkg.x && inner.y > pkg.y, "the class sits inside the package region");

    // A click on the class picks the class, not the package around it
    var on_class = DiagramRegion.pick(regions, inner.x + inner.width / 2, inner.y + inner.height / 2);
    expect_true(on_class != null, "no region under the class");
    expect_str(on_class.element_name, "Inner", "a click on the class");

    // A click on the package title strip (above the class) picks the package
    double title_y = (pkg.y + inner.y) / 2;
    var on_title = DiagramRegion.pick(regions, pkg.x + pkg.width / 2, title_y);
    expect_true(on_title != null, "no region on the package title");
    expect_str(on_title.element_name, "Core", "a click on the package title");
    expect_int(on_title.source_line, 3, "the package's declaration line");
}

const string MERMAID_SUBGRAPH_SRC =
    "flowchart TD\n" +                  // 1
    "  A --> B\n" +                     // 2
    "  subgraph Grp[Group]\n" +         // 3
    "    C --> D\n" +                   // 4
    "    subgraph Deep[Deeper]\n" +     // 5
    "      E\n" +                       // 6
    "    end\n" +                       // 7
    "  end\n";                          // 8

void test_mermaid_subgraph_is_clickable() {
    var r = render(MERMAID_SUBGRAPH_SRC, "t.mmd");
    var grp = r.expect_region("Grp", 3);
    var deep = r.expect_region("Deep", 5);
    var c = r.expect_region("C", 4);
    var regions = pickable(r);

    expect_true(grp.width > deep.width && grp.height > deep.height, "the outer subgraph is the larger box");
    var on_node = DiagramRegion.pick(regions, c.x + c.width / 2, c.y + c.height / 2);
    expect_true(on_node != null && on_node.element_name == "C", "a click on a node inside the subgraph");

    // The nested subgraph's frame wins over the outer one it sits in
    var e = r.expect_region("E", 6);
    double inner_title_y = (deep.y + e.y) / 2;
    var on_inner = DiagramRegion.pick(regions, deep.x + deep.width / 2, inner_title_y);
    expect_true(on_inner != null, "no region on the nested subgraph title");
    expect_str(on_inner.element_name, "Deep", "a click on the nested subgraph title");
    expect_int(on_inner.source_line, 5, "the nested subgraph's declaration line");
}

// ── tall pages: the surface is capped, and the click regions with it ──

// render_to_surface() built its Cairo surface at the raw SVG size, so a page past Cairo's
// 32767 px limit (2500 classes: 2075x40433 px) made librsvg refuse to draw it ("cannot
// render on a cairo_t with a failure status (status=InvalidSize)"): the GUI preview said
// "Failed to render" for a file the CLI exported fine, because the CLI's PNG path already
// went through RenderUtils. Every renderer now sizes its page with RenderUtils
// .svg_page_size(), which scales it down to fit and records the note — and the same scaled
// size goes to parse_svg_regions(), or a click on the scaled preview would land on
// whatever element the unscaled map has at those coordinates.

// The region drawn for source line `line` (the first one), or null
ElementRegion? region_at_line(Rendered r, int line) {
    foreach (var region in r.regions) {
        if (region.source_line == line) return region;
    }
    return null;
}

// The region a click at (x, y) hits, as hit() but the region itself
ElementRegion? hit_region(Rendered r, double x, double y) {
    foreach (var region in r.regions) {
        if (contains_point(region, x, y)) return region;
    }
    return null;
}

// The page fits Cairo, the scaling was recorded, and no region hangs outside the canvas
void expect_scaled_page(Rendered r, string what) {
    expect_true(r.canvas_height >= 1 && r.canvas_height <= RenderUtils.MAX_SURFACE_SIDE,
                "%s: the canvas is %.0f px tall".printf(what, r.canvas_height));
    expect_true(r.canvas_width >= 1, "%s: the canvas is %.0f px wide".printf(what, r.canvas_width));
    expect_true(r.canvas_height > 1000, "%s: only %.0f px tall — not the big page".printf(what, r.canvas_height));
    string? note = RenderUtils.png_downscale_note;
    expect_true(note != null && note.contains("scaled down"),
                "%s: the scaling was not recorded (%s)".printf(what, note ?? "(none)"));
    expect_true(r.regions.size > 0, "%s: no click regions".printf(what));
    foreach (var region in r.regions) {
        if (region.x < -1 || region.y < -1 ||
            region.x + region.width > r.canvas_width + 1 ||
            region.y + region.height > r.canvas_height + 1) {
            printerr("\n%s: region %s at %.0f,%.0f %.0fx%.0f is outside the %.0fx%.0f canvas\n",
                     what, region.name, region.x, region.y, region.width, region.height,
                     r.canvas_width, r.canvas_height);
            assert_not_reached();
        }
    }
}

// The first element is drawn in the top half of the scaled page and the last one in the
// bottom half, and a click in the middle of the last one selects that source line
void expect_first_and_last(Rendered r, int first_line, int last_line, string what) {
    var top = region_at_line(r, first_line);
    var bottom = region_at_line(r, last_line);
    expect_true(top != null, "%s: no region at the first element's line %d".printf(what, first_line));
    expect_true(bottom != null, "%s: no region at the last element's line %d".printf(what, last_line));
    expect_true(top.y < r.canvas_height / 2,
                "%s: the first element is at y=%.0f of %.0f".printf(what, top.y, r.canvas_height));
    expect_true(bottom.y > r.canvas_height / 2,
                "%s: the last element is at y=%.0f of %.0f".printf(what, bottom.y, r.canvas_height));
    var clicked = hit_region(r, bottom.x + bottom.width / 2, bottom.y + bottom.height / 2);
    expect_true(clicked != null, "%s: a click on the last element hits nothing".printf(what));
    expect_int(clicked.source_line, last_line, "%s: the line a click on the last element selects".printf(what));
}

// PlantUML structural: 40 classes of 50 fields each is ~38000 px tall
// The four tall cases below must exceed MAX_SURFACE_SIDE on ANY Graphviz build, not just
// this box's: at 40 classes / 45 states / 500 steps / 45 nodes the pages were only 17-38 %
// over the limit, and CI's Graphviz 14.1.3 packed the state one UNDER it, so nothing was
// scaled and the suite failed on a missing downscale note. Sized for ~2x the limit.
void test_tall_class_page_scaled() {
    var sb = new StringBuilder("@startuml\n");
    for (int i = 0; i < 70; i++) {
        sb.append_printf("class C%d {\n", i);
        for (int m = 0; m < 50; m++) {
            sb.append_printf("  +int field%d_%d\n", i, m);
        }
        sb.append("}\n");
    }
    for (int i = 0; i < 69; i++) {
        sb.append_printf("C%d --> C%d\n", i, i + 1);
    }
    sb.append("@enduml\n");
    RenderUtils.png_downscale_note = null;
    var r = render(sb.str);
    expect_scaled_page(r, "tall class diagram");
    r.expect_region("C0", 2);
    r.expect_region("C69", 2 + 69 * 52);
    expect_first_and_last(r, 2, 2 + 69 * 52, "tall class diagram");
}

// PlantUML behavioral (state): 45 states of 40 description lines is ~35000 px tall
void test_tall_state_page_scaled() {
    var sb = new StringBuilder("@startuml\n");
    for (int i = 0; i < 80; i++) {
        sb.append_printf("state S%d\n", i);
        for (int m = 0; m < 40; m++) {
            sb.append_printf("S%d : detail line %d\n", i, m);
        }
    }
    for (int i = 0; i < 79; i++) {
        sb.append_printf("S%d --> S%d\n", i, i + 1);
    }
    sb.append("@enduml\n");
    RenderUtils.png_downscale_note = null;
    var r = render(sb.str);
    expect_scaled_page(r, "tall state diagram");
    r.expect_region("S0", 2);
    r.expect_region("S79", 2 + 79 * 41);
    expect_first_and_last(r, 2, 2 + 79 * 41, "tall state diagram");
}

// PlantUML behavioral (activity, its own /usr/local/bin/dot path): 500 steps is ~37000 px
void test_tall_activity_page_scaled() {
    var sb = new StringBuilder("@startuml\nstart\n");
    for (int i = 0; i < 900; i++) {
        sb.append_printf(":step %d;\n", i);
    }
    sb.append("stop\n@enduml\n");
    RenderUtils.png_downscale_note = null;
    var r = render(sb.str);
    expect_scaled_page(r, "tall activity diagram");
    // Action node ids are generated, so the source lines are what a click resolves to
    expect_first_and_last(r, 3, 902, "tall activity diagram");
}

// Mermaid: 80 flowchart nodes of 40 label lines, ~2x MAX_SURFACE_SIDE on any Graphviz
void test_tall_mermaid_page_scaled() {
    var sb = new StringBuilder("flowchart TD\n");
    for (int i = 0; i < 80; i++) {
        sb.append_printf("  N%d[\"", i);
        for (int m = 0; m < 40; m++) {
            if (m > 0) sb.append("<br/>");
            sb.append_printf("line %d of node %d", m, i);
        }
        sb.append("\"]\n");
    }
    for (int i = 0; i < 79; i++) {
        sb.append_printf("  N%d --> N%d\n", i, i + 1);
    }
    RenderUtils.png_downscale_note = null;
    var r = render(sb.str, "t.mmd");
    expect_scaled_page(r, "tall mermaid flowchart");
    r.expect_region("N0", 2);
    r.expect_region("N79", 81);
    expect_first_and_last(r, 2, 81, "tall mermaid flowchart");
}

// ── block-beta: the canvas never leaves what Graphviz can describe ──

// Mermaid's block grid gives every cell the widest child's size, so a group nested in a
// group multiplies the canvas per level (mermaid-cli does the same: 17340pt at depth 3,
// 44791530pt at depth 8). Past 2^31 points Graphviz printed the SVG width as
// width="-2147483648pt", librsvg read no size, and the PNG came out a blank 400x300
// image at exit 0. Now the renderer says so instead.
string nested_blocks(int depth) {
    var sb = new StringBuilder();
    sb.append("block-beta\ncolumns 1\n");
    string indent = "  ";
    for (int d = depth; d > 0; d--) {
        for (int i = 0; i < 5; i++) sb.append_printf("%sn%d_%d\n", indent, d, i);
        sb.append_printf("%sblock:g%d\n", indent, d);
        indent += "  ";
    }
    for (int i = 0; i < 5; i++) sb.append_printf("%sleaf%d\n", indent, i);
    for (int d = depth; d > 0; d--) {
        indent = indent.substring(2);
        sb.append_printf("%send\n", indent);
    }
    return sb.str;
}

void test_block_canvas_stays_renderable() {
    // Shallow nesting is unchanged: the grid is Mermaid's, and it fits
    var shallow = render(nested_blocks(2), "b.mmd");
    expect_true(shallow.canvas_width > 100 && shallow.canvas_width < 100000,
                "depth 2 canvas: %.0f".printf(shallow.canvas_width));

    // Deeper: whatever the grid asks for, the drawn canvas stays positive and sane
    foreach (int depth in new int[] { 6, 8, 10, 12 }) {
        var r = render(nested_blocks(depth), "b.mmd");
        if (r.canvas_width <= 0 || r.canvas_height <= 0 ||
            r.canvas_width > 100000 || r.canvas_height > 100000) {
            printerr("\ndepth %d canvas is %.0f x %.0f\n", depth, r.canvas_width, r.canvas_height);
            assert_not_reached();
        }
        // The blank 400x300 fallback is not an answer: the render must say what happened
        var block = r.ast as MermaidBlock;
        expect_true(block != null, "no block AST at depth %d".printf(depth));
        bool explained = false;
        foreach (var err in block.errors) {
            if (err.message.contains("too large to render")) explained = true;
        }
        expect_true(explained, "depth %d renders without saying the layout is too large".printf(depth));
    }
}

public static int main(string[] args) {
    Test.init(ref args);
    // First: these check the state the process starts in
    Test.add_func("/regions/svg-regexes-ready", test_svg_regexes_ready_together);
    Test.add_func("/regions/path-bounds/inside-canvas", test_path_region_bounds_inside_canvas);
    Test.add_func("/regions/actor-figure/usecase", test_usecase_actor_figure);
    Test.add_func("/regions/actor-figure/sequence", test_sequence_actor_figure);
    Test.add_func("/regions/sequence/messages-frames", test_sequence_messages_and_frames);
    Test.add_func("/regions/sequence/inspector", test_inspector_sequence_kinds);
    Test.add_func("/regions/usecase/lines-navigation", test_usecase_lines_and_navigation);
    Test.add_func("/regions/usecase/implicit-element-lines", test_usecase_implicit_element_lines);
    Test.add_func("/regions/containers/member-lines", test_container_members_keep_their_own_line);
    Test.add_func("/regions/inside-canvas", test_regions_stay_inside_the_canvas);
    Test.add_func("/regions/class/declaration-line", test_class_declaration_line);
    Test.add_func("/regions/state/composite-history", test_state_composite_and_history);
    Test.add_func("/regions/deployment/containers-ports", test_deployment_container_and_ports);
    Test.add_func("/regions/activity/partitions", test_activity_partitions);
    Test.add_func("/regions/yaml/rows", test_yaml_rows);
    Test.add_func("/regions/ditaa/shapes", test_ditaa_shapes);
    Test.add_func("/regions/theme/actor-contrast", test_actor_contrast);
    Test.add_func("/regions/ditaa/document-fill", test_ditaa_document_fill);
    Test.add_func("/regions/parser", test_region_parser);
    Test.add_func("/regions/click-navigation", test_click_navigation);
    Test.add_func("/regions/class/package-clickable", test_class_package_is_clickable);
    Test.add_func("/regions/mermaid/subgraph-clickable", test_mermaid_subgraph_is_clickable);
    Test.add_func("/regions/mermaid/block-canvas-renderable", test_block_canvas_stays_renderable);
    Test.add_func("/regions/tall/class", test_tall_class_page_scaled);
    Test.add_func("/regions/tall/state", test_tall_state_page_scaled);
    Test.add_func("/regions/tall/activity", test_tall_activity_page_scaled);
    Test.add_func("/regions/tall/mermaid-flowchart", test_tall_mermaid_page_scaled);
    return Test.run();
}
