// Mermaid architecture / C4 / sequence / ZenUML / flowchart leftovers, all
// compared against the Mermaid CLI 11.17: architecture placement computed from
// the L/R/T/B sides, C4 offsets / queue shape / same-row links, quoted sequence
// aliases, ZenUML bold frames, braceless blocks, comments and stereotypes, and
// flowchart markdown wrapping, icon placeholders and edge classes.

using GDiagram;

Gvc.Context? shared_ctx = null;

unowned Gvc.Context ctx() {
    if (shared_ctx == null) shared_ctx = new Gvc.Context();
    return shared_ctx;
}

string as_text(uint8[]? data) {
    assert(data != null);
    var sb = new StringBuilder.sized(data.length + 1);
    sb.append_len((string) data, data.length);
    return sb.str;
}

void fails(string label, string message, string text) {
    stderr.printf("[%s] %s in:\n%s\n", label, message, text);
    assert_not_reached();
}

void has(string label, string text, string needle) {
    if (!text.contains(needle)) fails(label, "missing '%s'".printf(needle), text);
}

void lacks(string label, string text, string needle) {
    if (text.contains(needle)) fails(label, "unexpected '%s'".printf(needle), text);
}

// Attribute of a pinned node in the generated DOT
double attr_of(string dot, string id, string key, double scale = 1.0) {
    int at = dot.index_of("\"%s\" [".printf(id));
    if (at < 0) at = dot.index_of("%s [".printf(id));
    if (at < 0) fails("attr", "no node '%s'".printf(id), dot);
    int end = dot.index_of("]", at);
    string decl = dot.substring(at, end - at);
    int k = decl.index_of(key);
    if (k < 0) fails("attr", "no '%s' on '%s'".printf(key, id), decl);
    return double.parse(decl.substring(k + key.length)) * scale;
}

// Pinned y grows upwards in Graphviz: "lower on the page" is a smaller value
double pin_y(string dot, string id) {
    int at = dot.index_of("\"%s\" [".printf(id));
    if (at < 0) at = dot.index_of("%s [".printf(id));
    if (at < 0) fails("pos", "no node '%s'".printf(id), dot);
    int p = dot.index_of("pos=\"", at);
    int comma = dot.index_of(",", p);
    return double.parse(dot.substring(comma + 1));
}

double pin_x(string dot, string id) {
    int at = dot.index_of("\"%s\" [".printf(id));
    if (at < 0) at = dot.index_of("%s [".printf(id));
    if (at < 0) fails("pos", "no node '%s'".printf(id), dot);
    int p = dot.index_of("pos=\"", at);
    return double.parse(dot.substring(p + 5));
}

// ── Architecture ────────────────────────────────────────────────────────────

MermaidArchitectureRenderer arch() {
    return new MermaidArchitectureRenderer(ctx(), new Gee.ArrayList<ElementRegion>(), "dot");
}

/*
 * "a:B -- T:low" puts `low` below `a`, even when `a` sits in a nested group:
 * Mermaid derives the placement from the edge sides, and Graphviz's ranking
 * could not push a node below a cluster it is not part of.
 */
void test_arch_below_nested_group() {
    string src = "architecture-beta\n    group outer(cloud)[Outer]\n" +
        "    group inner(server)[Inner] in outer\n" +
        "    service a(server)[A] in inner\n    service b(server)[B] in inner\n" +
        "    service low(disk)[Low]\n    junction jn\n" +
        "    a:R -- L:b\n    a:B -- T:low\n    low:R -- L:jn\n";
    var d = new MermaidArchitectureParser().parse(src);
    string dot = arch().generate_dot(d);

    double a_y = pin_y(dot, "a");
    double low_y = pin_y(dot, "low");
    double jn_y = pin_y(dot, "jn");
    // "low" is below "a"
    assert(low_y < a_y);
    // and below the whole nested group, not merely below its own tile
    double inner_y = pin_y(dot, "_ag_inner");
    double inner_h = attr_of(dot, "_ag_inner", "height=", 72.0);
    assert(low_y < inner_y - inner_h / 2);
    double outer_y = pin_y(dot, "_ag_outer");
    double outer_h = attr_of(dot, "_ag_outer", "height=", 72.0);
    assert(low_y < outer_y - outer_h / 2);
    // "low:R -- L:jn": the junction is to its right, on the same row
    assert(pin_x(dot, "jn") > pin_x(dot, "low"));
    assert(Math.fabs(jn_y - low_y) < 0.5);
    // "a:R -- L:b" keeps b right of a on a shared row
    assert(pin_x(dot, "b") > pin_x(dot, "a"));
    assert(Math.fabs(pin_y(dot, "b") - a_y) < 0.5);
}

// A bend ("a:B -- L:b") is routed through a corner, as Mermaid's "segments" edge
void test_arch_bend_corner() {
    var d = new MermaidArchitectureParser().parse(
        "architecture-beta\n    service a(server)[A]\n    service b(disk)[B]\n    a:B -- L:b\n");
    string dot = arch().generate_dot(d);
    has("bend", dot, "_ae0k [shape=point");
    // the corner shares x with the start and y with the end
    assert(Math.fabs(pin_x(dot, "_ae0k") - pin_x(dot, "_ae0a")) < 0.5);
    assert(Math.fabs(pin_y(dot, "_ae0k") - pin_y(dot, "_ae0b")) < 0.5);
}

// ── C4 ──────────────────────────────────────────────────────────────────────

MermaidC4Renderer c4() {
    return new MermaidC4Renderer(ctx(), new Gee.ArrayList<ElementRegion>(), "dot");
}

// A ContainerQueue is Mermaid's "h-cyl": a cylinder on its side, not a round box
void test_c4_queue_shape() {
    string src = "C4Container\n    Container(web, \"Web\", \"JS\", \"UI\")\n" +
        "    ContainerQueue(q, \"Events\", \"Kafka\", \"Bus\")\n    Rel(web, q, \"publishes\")\n";
    var d = new MermaidC4Parser().parse(src);
    C4Element? queue = null;
    foreach (var el in d.elements) if (el.id == "q") queue = el;
    assert(queue != null && queue.is_queue);
    string dot = c4().generate_dot(d);
    has("queue id", dot, "id=\"gdc4q_0\"");
    string svg = as_text(c4().render_to_svg(d));
    // the placeholder polygon is gone, two elliptical arcs and the cap seam remain
    has("queue outline", svg, "<path fill=\"none\"");
    int at = svg.index_of("id=\"gdc4q_0\"");
    assert(at > 0);
    string body = svg.substring(at, 900);
    has("queue arcs", body, "A");
    lacks("queue box", body, "<polygon");
}

// UpdateRelStyle's $offsetX / $offsetY move the relationship label
void test_c4_rel_offsets() {
    string plain = "C4Container\n    Container(a, \"A\", \"t\", \"d\")\n    Container(b, \"B\", \"t\", \"d\")\n" +
        "    Rel(a, b, \"calls\")\n";
    string moved = plain + "    UpdateRelStyle(a, b, $textColor=\"red\", $lineColor=\"red\", $offsetX=\"-40\", $offsetY=\"25\")\n";
    var d2 = new MermaidC4Parser().parse(moved);
    assert(d2.relationships.get(0).offset_x == -40);
    assert(d2.relationships.get(0).offset_y == 25);

    double x0, y0, x1, y1;
    label_xy(as_text(c4().render_to_svg(new MermaidC4Parser().parse(plain))), "calls", out x0, out y0);
    label_xy(as_text(c4().render_to_svg(d2)), "calls", out x1, out y1);
    assert(Math.fabs((x1 - x0) - (-40)) < 1.0);
    assert(Math.fabs((y1 - y0) - 25) < 1.0);
}

void label_xy(string svg, string text, out double x, out double y) {
    x = 0;
    y = 0;
    MatchInfo m;
    try {
        var re = new Regex("<text[^>]*x=\"([-0-9.]+)\" y=\"([-0-9.]+)\"[^>]*>%s</text>".printf(
            Regex.escape_string(text)));
        if (!re.match(svg, 0, out m)) fails("label", "no text '%s'".printf(text), svg);
    } catch (RegexError e) {
        assert_not_reached();
    }
    x = double.parse(m.fetch(1));
    y = double.parse(m.fetch(2));
}

/*
 * A link between two shapes of one row used to arch over the shapes between its
 * ends; Mermaid draws a straight line through them.
 */
void test_c4_same_row_link() {
    string src = "C4Context\n    Person(a, \"Alice\", \"u\")\n    System(b, \"B\", \"m\")\n" +
        "    System(c, \"C\", \"r\")\n    UpdateLayoutConfig($c4ShapeInRow=\"3\")\n" +
        "    Rel(a, c, \"far link\")\n";
    var d = new MermaidC4Parser().parse(src);
    string dot = c4().generate_dot(d);
    has("straight", dot, "splines=line");
    // the label sits along the line, where it cannot drag it out of the row
    has("taillabel", dot, "\"a\" -> \"c\" [taillabel=");
    has("label placing", dot, "labeldistance=3.0 labelangle=-22");
    has("plain label", dot, "\"a\" -> \"b\"");
}

// The same link, measured: it must stay level with the row it connects
void test_c4_same_row_link_geometry() {
    string src = "C4Context\n    Person(a, \"Alice\", \"u\")\n    System(b, \"B\", \"m\")\n" +
        "    System(c, \"C\", \"r\")\n    UpdateLayoutConfig($c4ShapeInRow=\"3\")\n" +
        "    Rel(a, c, \"far link\")\n";
    var d = new MermaidC4Parser().parse(src);
    string svg = as_text(c4().render_to_svg(d));
    double a_y = shape_center_y(svg, "a");
    double c_y = shape_center_y(svg, "c");
    double top, bottom;
    edge_y_range(svg, "a&#45;&gt;c", out top, out bottom);
    // an arch left the row entirely: its apex sat well above both shapes
    assert(top > double.min(a_y, c_y) - 60);
    assert(bottom < double.max(a_y, c_y) + 60);
}

double shape_center_y(string svg, string id) {
    int at = svg.index_of("<title>%s</title>".printf(id));
    if (at < 0) fails("shape", "no node '%s'".printf(id), svg);
    double lo, hi;
    coords_in(svg.substring(at, 1200), out lo, out hi);
    return (lo + hi) / 2;
}

void edge_y_range(string svg, string title, out double top, out double bottom) {
    int at = svg.index_of("<title>%s</title>".printf(title));
    if (at < 0) fails("edge", "no edge '%s'".printf(title), svg);
    int end = svg.index_of("</g>", at);
    coords_in(svg.substring(at, end - at), out top, out bottom);
}

// Smallest and largest y in every "x,y" pair of an SVG fragment
void coords_in(string fragment, out double lo, out double hi) {
    lo = double.MAX;
    hi = -double.MAX;
    try {
        var re = new Regex("[-0-9.]+,([-0-9.]+)");
        MatchInfo m;
        re.match(fragment, 0, out m);
        while (m.matches()) {
            double v = double.parse(m.fetch(1));
            lo = double.min(lo, v);
            hi = double.max(hi, v);
            m.next();
        }
    } catch (RegexError e) {
        assert_not_reached();
    }
    assert(lo <= hi);
}

// ── Sequence ────────────────────────────────────────────────────────────────

/*
 * Mermaid's sequence grammar has no string token for an actor: the quotes of
 * `participant A as "API Gateway"` and `box "Front End"` are drawn.
 */
void test_seq_quotes_kept() {
    string src = "sequenceDiagram\n    box \"Front End\"\n    participant A as \"API Gateway\"\n" +
        "    end\n    participant B\n    A->>B: x\n";
    var engine = new DiagramEngine("dot");
    var parsed = engine.parse(src, "t.mmd");
    assert(parsed.diagram_type == DiagramType.MERMAID_SEQUENCE);
    var d = (MermaidSequenceDiagram) parsed.ast;
    assert(d.find_actor("A").alias == "\"API Gateway\"");
    assert(d.boxes.size == 1 && d.boxes[0].label == "\"Front End\"");

    string dir;
    try {
        dir = DirUtils.make_tmp("mmd-arch2-XXXXXX");
    } catch (FileError e) {
        assert_not_reached();
    }
    string path = Path.build_filename(dir, "t.svg");
    assert(engine.export_to_svg(src, "t.mmd", null, path));
    string svg;
    try {
        FileUtils.get_contents(path, out svg);
    } catch (FileError e) {
        assert_not_reached();
    }
    FileUtils.remove(path);
    DirUtils.remove(dir);
    has("quoted alias", svg, "&quot;API Gateway&quot;");
    has("quoted box", svg, "&quot;Front End&quot;");
}

// ── ZenUML ──────────────────────────────────────────────────────────────────

MermaidZenUMLRenderer zen() {
    return new MermaidZenUMLRenderer(ctx(), new Gee.ArrayList<ElementRegion>(), "dot");
}

/*
 * Graphviz writes the requested "Sans Bold" straight into font-family, where no
 * renderer finds a family of that name and the text comes out regular.
 */
void test_zen_bold_frame_keyword() {
    var d = new MermaidZenUMLParser().parse(
        "zenuml\n    title Bold please\n    A.run() {\n      if (x) {\n        B.go()\n      }\n    }\n");
    string dot = zen().generate_dot(d);
    has("asks for bold", dot, "fontname=\"Sans Bold\"");
    string svg = as_text(zen().render_to_svg(d));
    lacks("bold family", svg, "font-family=\"Sans Bold\"");
    has("bold weight", svg, "font-weight=\"bold\"");
    has("frame tab", svg, "Alt");
}

// "if (x)" without braces is a block running to the end of the enclosing one
void test_zen_braceless_if() {
    var d = new MermaidZenUMLParser().parse(
        "zenuml\n    A.one()\n    if (x)\n    B.two()\n    A.three()\n");
    int starts = 0, ends = 0, messages = 0;
    int start_at = -1, end_at = -1;
    for (int i = 0; i < d.events.size; i++) {
        var ev = d.events[i];
        if (ev.kind == ZenEventKind.BLOCK_START) { starts++; start_at = i; }
        if (ev.kind == ZenEventKind.BLOCK_END) { ends++; end_at = i; }
        if (ev.kind == ZenEventKind.MESSAGE) messages++;
    }
    assert(starts == 1 && ends == 1);
    assert(messages == 3);
    // one() before the block, two() and three() inside it
    assert(start_at > 0 && end_at > start_at);
    int inside = 0;
    for (int i = start_at + 1; i < end_at; i++) {
        if (d.events[i].kind == ZenEventKind.MESSAGE) inside++;
    }
    assert(inside == 2);
    // and the numbering nests, as ZenUML numbers a block's children
    assert(d.messages[1].number == "2.1");
    assert(d.messages[2].number == "2.2");
}

// "// note" is kept and drawn in grey above the message it precedes
void test_zen_comment() {
    var d = new MermaidZenUMLParser().parse(
        "zenuml\n    // greet the user\n    A.load()\n    B.plain()\n");
    assert(d.messages[0].comment == "greet the user");
    assert(d.messages[1].comment == null);
    string dot = zen().generate_dot(d);
    has("comment text", dot, "label=\"greet the user\"");
    string svg = as_text(zen().render_to_svg(d));
    has("comment drawn", svg, ">greet the user</text>");
    // above the message label, and starting at the sender's lifeline
    double cy = text_y(svg, "greet the user");
    double ly = text_y(svg, "load()");
    assert(cy < ly);
}

double text_y(string svg, string text) {
    double x, y;
    label_xy(svg, text, out x, out y);
    return y;
}

// "@<<service>> Ext" draws «service» over the name; collections get two outlines
void test_zen_participant_shapes() {
    var d = new MermaidZenUMLParser().parse(
        "zenuml\n    @<<service>> Ext\n    @Collections Bag\n    @Boundary UI\n" +
        "    Ext.a()\n    Bag.b()\n    UI.c()\n");
    ZenParticipant? ext = null;
    ZenParticipant? bag = null;
    foreach (var p in d.participants) {
        if (p.name == "Ext") ext = p;
        if (p.name == "Bag") bag = p;
    }
    assert(ext != null && ext.stereotype == "service");
    assert(bag != null && bag.actor_type == "Collections");
    string dot = zen().generate_dot(d);
    has("stereotype", dot, "«service»");
    // ZenUML itself draws @Collections as a plain box, so we do too
    if (dot.contains("peripheries=2")) {
        printerr("\nFAILED: collections must not get a double border\n%s\n", dot);
        assert_not_reached();
    }
}

// ── Flowchart ───────────────────────────────────────────────────────────────

MermaidFlowchartRenderer flow() {
    return new MermaidFlowchartRenderer(ctx(), new Gee.ArrayList<ElementRegion>(), "dot");
}

// A markdown string wraps at Mermaid's wrappingWidth; a plain one does not
void test_flow_markdown_wraps() {
    var d = new MermaidFlowchartParser().parse(
        "flowchart TD\n    A[\"`This is a **markdown** string that is quite long and should wrap " +
        "automatically in Mermaid`\"] --> B[This is a plain string that is quite long and stays on one line]\n");
    string dot = flow().generate_dot(d);
    int at = dot.index_of("A [label=");
    assert(at > 0);
    string decl = dot.substring(at, dot.index_of("\n", at) - at);
    int breaks = 0, pos = 0;
    while ((pos = decl.index_of("<BR/>", pos)) >= 0) { breaks++; pos++; }
    assert(breaks >= 3);
    // the marked-up run survives the break it sits next to
    has("bold kept", decl, "<B>markdown</B>");
    lacks("stray marker", decl, "**");
    int bt = dot.index_of("B [label=");
    string bdecl = dot.substring(bt, dot.index_of("\n", bt) - bt);
    lacks("plain unwrapped", bdecl, "<BR/>");
}

/*
 * Font Awesome references and images would both need a network fetch, which the
 * live preview must never do: both become a placeholder glyph.
 */
void test_flow_icon_placeholders() {
    var d = new MermaidFlowchartParser().parse(
        "flowchart TD\n    C[fa:fa-car Car] --> D[fab:fa-github GitHub]\n" +
        "    D --> E@{ img: \"https://example.com/x.png\", label: \"Shot\", w: 60, h: 40 }\n");
    string dot = flow().generate_dot(d);
    lacks("fa token", dot, "fa:fa-car");
    lacks("fab token", dot, "fab:fa-github");
    has("placeholder", dot, MermaidFlowchartRenderer.ICON_MARK);
    // the image keeps its declared size and never names a URL as a source
    has("image frame", dot, "WIDTH=\"60\" HEIGHT=\"40\"");
    has("image label", dot, "Shot");
    string svg = as_text(flow().render_to_svg(d));
    lacks("no fetch", svg, "<image");
    lacks("no url", svg, "xlink:href=\"https://example.com/x.png\"");
}

// "class e1,e2 name" styles the edges with those ids, as Mermaid does
void test_flow_edge_classes() {
    var d = new MermaidFlowchartParser().parse(
        "flowchart LR\n    classDef hot stroke:#ff0000,stroke-width:4px,color:#0000ff;\n" +
        "    A e1@--> B\n    B e2@--> C\n    A --> C\n    class e1,e2 hot\n");
    assert(d.edges.size == 3);
    assert(d.edges[0].edge_id == "e1" && d.edges[1].edge_id == "e2");
    assert(d.edges[0].edge_color == "#ff0000");
    assert(d.edges[0].edge_thickness == "4");
    assert(d.edges[0].label_color == "#0000ff");
    assert(d.edges[2].edge_color == null);
    string dot = flow().generate_dot(d);
    has("edge stroke", dot, "color=\"#ff0000\"");
    has("edge width", dot, "penwidth=4");
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/mermaid-arch2/architecture/below_nested_group", test_arch_below_nested_group);
    Test.add_func("/review/mermaid-arch2/architecture/bend_corner", test_arch_bend_corner);
    Test.add_func("/review/mermaid-arch2/c4/queue_shape", test_c4_queue_shape);
    Test.add_func("/review/mermaid-arch2/c4/rel_offsets", test_c4_rel_offsets);
    Test.add_func("/review/mermaid-arch2/c4/same_row_link", test_c4_same_row_link);
    Test.add_func("/review/mermaid-arch2/c4/same_row_link_geometry", test_c4_same_row_link_geometry);
    Test.add_func("/review/mermaid-arch2/sequence/quotes_kept", test_seq_quotes_kept);
    Test.add_func("/review/mermaid-arch2/zenuml/bold_frame", test_zen_bold_frame_keyword);
    Test.add_func("/review/mermaid-arch2/zenuml/braceless_if", test_zen_braceless_if);
    Test.add_func("/review/mermaid-arch2/zenuml/comment", test_zen_comment);
    Test.add_func("/review/mermaid-arch2/zenuml/participant_shapes", test_zen_participant_shapes);
    Test.add_func("/review/mermaid-arch2/flowchart/markdown_wraps", test_flow_markdown_wraps);
    Test.add_func("/review/mermaid-arch2/flowchart/icon_placeholders", test_flow_icon_placeholders);
    Test.add_func("/review/mermaid-arch2/flowchart/edge_classes", test_flow_edge_classes);
    return Test.run();
}
