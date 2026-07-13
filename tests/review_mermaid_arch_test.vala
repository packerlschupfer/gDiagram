// Mermaid block, C4, architecture and requirement review: syntax the parsers
// dropped or misread, and the renderers' grid layout, labels, styles and icons,
// compared with Mermaid CLI 11.17.

using GDiagram;

// Renderers hold the context unowned: keep one alive for the whole run
Gvc.Context? shared_gvc = null;

unowned Gvc.Context gvc() {
    if (shared_gvc == null) shared_gvc = new Gvc.Context();
    return shared_gvc;
}

string svg_string(uint8[]? data) {
    assert(data != null);
    var sb = new StringBuilder.sized(data.length + 1);
    sb.append_len((string) data, data.length);
    return sb.str;
}

void fail_with(string label, string message, string text) {
    stderr.printf("[%s] %s in:\n%s\n", label, message, text);
    assert_not_reached();
}

void assert_has(string label, string text, string needle) {
    if (!text.contains(needle)) fail_with(label, "missing '%s'".printf(needle), text);
}

void assert_lacks(string label, string text, string needle) {
    if (text.contains(needle)) fail_with(label, "unexpected '%s'".printf(needle), text);
}

// Exports through the engine the way the CLI does
void assert_exports(string label, string src) {
    var engine = new DiagramEngine("dot");
    string dir;
    try {
        dir = DirUtils.make_tmp("mmd-arch-test-XXXXXX");
    } catch (FileError e) {
        assert_not_reached();
    }
    foreach (var ext in new string[] { "png", "svg", "pdf" }) {
        string path = Path.build_filename(dir, "t." + ext);
        bool ok = false;
        if (ext == "png") ok = engine.export_to_png(src, "t.mmd", null, path);
        if (ext == "svg") ok = engine.export_to_svg(src, "t.mmd", null, path);
        if (ext == "pdf") ok = engine.export_to_pdf(src, "t.mmd", null, path);
        if (!ok || !FileUtils.test(path, FileTest.EXISTS)) {
            fail_with(label, "export to %s failed".printf(ext), src);
        }
        FileUtils.remove(path);
    }
    DirUtils.remove(dir);
}

// "pos" of a node in pinned DOT: x, y (y grows upwards)
bool node_pos(string dot, string id, out double x, out double y, out double w, out double h) {
    x = y = w = h = 0;
    MatchInfo m;
    try {
        var re = new Regex("\"%s\" \\[pos=\"([-0-9.]+),([-0-9.]+)!\" width=([0-9.]+) height=([0-9.]+)".printf(Regex.escape_string(id)));
        if (!re.match(dot, 0, out m)) return false;
    } catch (RegexError e) {
        return false;
    }
    x = double.parse(m.fetch(1));
    y = double.parse(m.fetch(2));
    w = double.parse(m.fetch(3)) * 72;
    h = double.parse(m.fetch(4)) * 72;
    return true;
}

MermaidBlockRenderer block_renderer() {
    return new MermaidBlockRenderer(gvc(), new Gee.ArrayList<ElementRegion>(), "dot");
}

// ── Block ───────────────────────────────────────────────────────────────────

// B1: non-square shapes, plain links, style lines and block arrows broke the DOT
void test_block_syntax_exports() {
    string shapes = "block-beta\n  columns 3\n  a(\"Round\") b((\"Circle\")) c{\"Decision\"}\n  a --> b\n";
    var d = new MermaidBlockParser().parse(shapes);
    assert(d.nodes.size == 3);
    assert(d.find_node("a").shape == "round" && d.find_node("a").label == "Round");
    assert(d.find_node("b").shape == "circle" && d.find_node("b").label == "Circle");
    assert(d.find_node("c").shape == "diamond" && d.find_node("c").label == "Decision");
    assert(d.edges.size == 1);
    assert_exports("shapes", shapes);

    string plain = "block-beta\n  columns 2\n  a[\"A\"] b[\"B\"]\n  a --- b\n";
    d = new MermaidBlockParser().parse(plain);
    assert(d.nodes.size == 2 && d.edges.size == 1);
    assert(d.edges.get(0).source == "a" && d.edges.get(0).target == "b");
    assert(d.edges.get(0).arrow_end == "");
    assert_has("plain link", block_renderer().generate_dot(d), "arrowhead=none");
    assert_exports("plain link", plain);

    string styled = "block-beta\n  columns 2\n  a[\"A\"] b[\"B\"]\n  style b fill:#f96,stroke:#333\n";
    d = new MermaidBlockParser().parse(styled);
    assert(d.nodes.size == 2);
    assert(d.find_node("b").styles == "fill:#f96,stroke:#333");
    string dot = block_renderer().generate_dot(d);
    assert_has("style", dot, "fillcolor=\"#f96\" color=\"#333\"");
    assert_exports("style", styled);

    string arrow = "block-beta\n  columns 3\n  api_gw[\"Gateway\"] arrow<[\"calls\"]>(right) svc[\"Service\"]\n  style svc fill:#f96\n";
    d = new MermaidBlockParser().parse(arrow);
    assert(d.nodes.size == 3);
    var an = d.find_node("arrow");
    assert(an.shape == "block_arrow" && an.label == "calls" && an.arrow_direction == "right");
    string svg = svg_string(block_renderer().render_to_svg(d));
    assert_has("block arrow", svg, "id=\"gdblk_arrowright_");
    assert_has("block arrow", svg, ">calls<");
    assert_exports("block arrow", arrow);
}

// B2: columns, spans and spaces make a grid
void test_block_grid() {
    string src = "block-beta\n  columns 3\n  a[\"A wide\"]:2 b[\"B\"]\n  c[\"C\"] space d[\"D\"]\n  e[\"E full\"]:3\n";
    var d = new MermaidBlockParser().parse(src);
    assert(d.columns == 3);
    assert(d.find_node("a").col_span == 2 && d.find_node("e").col_span == 3);
    int spaces = 0;
    foreach (var n in d.nodes) if (n.is_space) spaces++;
    assert(spaces == 1);
    string dot = block_renderer().generate_dot(d);
    double ax, ay, aw, ah, bx, by, bw, bh, cx, cy, cw, ch, dx, dy, dw, dh, ex, ey, ew, eh;
    assert(node_pos(dot, "a", out ax, out ay, out aw, out ah));
    assert(node_pos(dot, "b", out bx, out by, out bw, out bh));
    assert(node_pos(dot, "c", out cx, out cy, out cw, out ch));
    assert(node_pos(dot, "d", out dx, out dy, out dw, out dh));
    assert(node_pos(dot, "e", out ex, out ey, out ew, out eh));
    // Rows top-down, same row same y
    assert(ay == by && cy == dy && ay > cy && cy > ey);
    // Columns: c under a's left cell, d under b, the space leaves the middle cell empty
    assert(Math.fabs((cx - cw / 2) - (ax - aw / 2)) < 0.6);
    assert(Math.fabs(dx - bx) < 0.6 && Math.fabs(dw - bw) < 0.6);
    assert(dx - cx > 1.9 * cw);
    // Spans: a is two cells plus a gap, e the whole row
    assert(aw > 2 * bw);
    assert(Math.fabs((ex - ew / 2) - (ax - aw / 2)) < 0.6 && Math.fabs((ex + ew / 2) - (bx + bw / 2)) < 0.6);
    assert_lacks("space", dot, "label=\"space\"");
}

// B3: nested groups keep their parents; each group has its own columns
void test_block_nested_groups() {
    string src = "block-beta\n  columns 2\n  block:outer:2\n    columns 2\n    block:inner\n      x[\"X\"]\n    end\n    y[\"Y\"]\n  end\n  z[\"Z\"] w[\"W\"]\n  x --> z\n";
    var d = new MermaidBlockParser().parse(src);
    assert(d.find_node("outer").is_group && d.find_node("outer").group_id == null);
    assert(d.find_node("outer").columns == 2 && d.find_node("outer").col_span == 2);
    assert(d.find_node("inner").is_group && d.find_node("inner").group_id == "outer");
    assert(d.find_node("x").group_id == "inner");
    assert(d.find_node("y").group_id == "outer");
    assert(d.find_node("z").group_id == null && d.find_node("w").group_id == null);
    assert(d.edges.size == 1);
    string dot = block_renderer().generate_dot(d);
    double ox, oy, ow, oh, ix, iy, iw, ih, xx, xy, xw, xh, zx, zy, zw, zh;
    assert(node_pos(dot, "outer", out ox, out oy, out ow, out oh));
    assert(node_pos(dot, "inner", out ix, out iy, out iw, out ih));
    assert(node_pos(dot, "x", out xx, out xy, out xw, out xh));
    assert(node_pos(dot, "z", out zx, out zy, out zw, out zh));
    // x inside inner inside outer; z below outer
    assert(ix - iw / 2 > ox - ow / 2 && ix + iw / 2 < ox + ow / 2);
    assert(xx - xw / 2 > ix - iw / 2 && xx + xw / 2 < ix + iw / 2);
    assert(zy + zh / 2 < oy - oh / 2);
    // The group is drawn before (under) its blocks
    assert(dot.index_of("\"outer\" [") < dot.index_of("\"inner\" [") && dot.index_of("\"inner\" [") < dot.index_of("\"x\" ["));
    assert_exports("nested", src);
}

/**
 * B3b: looking a block up is not a linear scan of every block.
 *
 * `find_node()` walked `nodes`, and the parser calls it once per block reference while
 * the renderer calls it twice per edge, so a block diagram cost O(n²) on the parse path
 * the LSP and the preview run on every keystroke: 4000 `a --> b` lines took 0.86 s
 * (2000: 0.22 s, 8000: 3.4 s — four times the work for twice the input).
 *
 * The index has to keep the old answer exactly: `find_node` returned the FIRST node with
 * an id, and a repeated id is reachable — `block:g ... end` twice declares two group
 * nodes under "g", and the later references (a child's group_id, `style`, `class`) all
 * resolve to the first.
 */
void test_block_lookup_is_indexed_and_keeps_the_first_duplicate() {
    // Two groups share an id: the first one is what every reference resolves to.
    var dup = new MermaidBlockParser().parse(
        "block-beta\n  block:g\n    x[\"X\"]\n  end\n  block:g\n    y[\"Y\"]\n  end\n  style g fill:#f96\n");
    int g_nodes = 0;
    BlockNode? first_g = null;
    foreach (var n in dup.nodes) {
        if (n.id == "g") {
            g_nodes++;
            if (first_g == null) first_g = n;
        }
    }
    assert(g_nodes == 2);                       // the duplicate really is in the list
    assert(dup.find_node("g") == first_g);      // and the first one still wins
    assert(first_g.styles == "fill:#f96");      // `style g` reached the first, as before
    assert(dup.find_node("missing") == null);

    // Scaling: quadratic lookup grows four times per doubling, the index twice.
    var timer = new Timer();
    double t_small = block_parse_seconds(timer, 2000);
    double t_large = block_parse_seconds(timer, 8000);
    // 4x the input: linear is ~4x the time, the old scan was ~16x. The 50 ms floor
    // keeps a fast machine's timer noise from deciding this.
    if (t_large > 8 * t_small + 0.05) {
        error("block parse scales quadratically: 2000 lines %.3f s, 8000 lines %.3f s", t_small, t_large);
    }
}

// Seconds to parse a block diagram of `lines` edges between distinct ids.
double block_parse_seconds(Timer timer, int lines) {
    var sb = new StringBuilder("block-beta\n");
    for (int i = 0; i < lines; i++) sb.append_printf("  a%d --> b%d\n", i, i);
    string src = sb.str;
    timer.start();
    var d = new MermaidBlockParser().parse(src);
    timer.stop();
    assert(d.nodes.size == 2 * lines);
    return timer.elapsed();
}

// B4: front matter holds the title; "title" in the body would be blocks, as in Mermaid
void test_block_front_matter_title() {
    var d = new MermaidBlockParser().parse("---\ntitle: Basic\n---\nblock-beta\n  columns 2\n  a b\n");
    assert(d.title == "Basic");
    assert(d.nodes.size == 2);
    string? root = Environment.get_variable("GDIAGRAM_SOURCE_ROOT");
    if (root != null) {
        foreach (string name in new string[] { "basic.mmd", "groups.mmd" }) {
            string text;
            try {
                FileUtils.get_contents(Path.build_filename(root, "examples", "mermaid", "block", name), out text);
            } catch (FileError e) {
                assert_not_reached();
            }
            var ex = new MermaidBlockParser().parse(text);
            assert(ex.find_node("title") == null);
            assert(ex.title != null);
        }
    }
}

// ── C4 ──────────────────────────────────────────────────────────────────────

MermaidC4Renderer c4_renderer() {
    return new MermaidC4Renderer(gvc(), new Gee.ArrayList<ElementRegion>(), "dot");
}

// K1: deployment nodes are nested boundaries holding their elements
void test_c4_deployment_nodes() {
    string src = "C4Deployment\n    title Deployment\n    Deployment_Node(cloud, \"AWS\", \"Amazon Web Services\") {\n" +
        "        Deployment_Node(ec2, \"EC2\", \"Ubuntu 22.04\") {\n            Container(api, \"API\", \"Go\", \"REST API\")\n        }\n" +
        "        ContainerDb(rds, \"RDS\", \"PostgreSQL\", \"Data\")\n    }\n    Rel(api, rds, \"Reads\", \"SQL\")\n";
    var d = new MermaidC4Parser().parse(src);
    assert(d.boundaries.size == 2);
    assert(d.boundaries.get(0).id == "cloud" && d.boundaries.get(0).boundary_type == "Amazon Web Services");
    assert(d.boundaries.get(1).id == "ec2" && d.boundaries.get(1).parent_boundary == "cloud");
    assert(d.elements.size == 2);
    foreach (var el in d.elements) {
        if (el.id == "api") assert(el.parent_boundary == "ec2");
        if (el.id == "rds") assert(el.parent_boundary == "cloud");
    }
    string dot = c4_renderer().generate_dot(d);
    int outer = dot.index_of("subgraph cluster_cloud");
    int inner = dot.index_of("subgraph cluster_ec2");
    assert(outer >= 0 && inner > outer);
    assert(dot.index_of("\"api\" [") > inner);
    assert_has("deployment", dot, "[Amazon Web Services]");
    assert_lacks("deployment", dot, "\"cloud\" [");
    assert_exports("deployment", src);
}

// K2 + K4: "[Container: tech]" and the description; element and boundary types
void test_c4_labels() {
    string src = "C4Context\n    Enterprise_Boundary(b0, \"Bank\") {\n        Person(p, \"Customer\", \"Buys\")\n" +
        "        System_Boundary(b1, \"Core\") {\n            System(s, \"Banking\", \"Core system\")\n        }\n    }\n" +
        "    Container_Boundary(c0, \"Shop\") {\n        Container(web_app, \"Web Application\", \"React\", \"Frontend\")\n    }\n" +
        "    SystemDb_Ext(x, \"Mainframe\")\n";
    var d = new MermaidC4Parser().parse(src);
    string dot = c4_renderer().generate_dot(d);
    assert_has("techn", dot, "[Container: React]");
    assert_has("descr", dot, "Frontend");
    assert_has("person", dot, "[Person]");
    assert_has("system", dot, "[Software System]");
    assert_has("enterprise", dot, "[ENTERPRISE]");
    assert_has("system boundary", dot, "[SYSTEM]");
    assert_has("container boundary", dot, "[CONTAINER]");
    foreach (var el in d.elements) {
        if (el.id == "x") assert(el.c4_shape_type == "external_system_db");
    }
    assert_exports("labels", src);
}

// K3: UpdateRelStyle, UpdateElementStyle, UpdateLayoutConfig
void test_c4_styles_and_layout_config() {
    string src = "C4Container\n    title T\n    Person(user, \"User\", \"A user\")\n" +
        "    Container(web, \"Web App\", \"React\", \"Serves UI\")\n    ContainerDb(db, \"DB\", \"PostgreSQL\", \"Stores data\")\n" +
        "    Rel(user, web, \"Uses\", \"HTTPS\")\n    BiRel(web, db, \"Reads/writes\", \"SQL\")\n" +
        "    UpdateRelStyle(user, web, $textColor=\"red\", $lineColor=\"red\", $offsetX=\"5\")\n" +
        "    UpdateElementStyle(db, $bgColor=\"orange\", $fontColor=\"black\")\n" +
        "    UpdateLayoutConfig($c4ShapeInRow=\"2\", $c4BoundaryInRow=\"1\")\n";
    var d = new MermaidC4Parser().parse(src);
    var rel = d.relationships.get(0);
    assert(rel.text_color == "red" && rel.line_color == "red");
    C4Element? db = null;
    foreach (var el in d.elements) if (el.id == "db") db = el;
    assert(db != null && db.bg_color == "orange" && db.font_color == "black");
    assert(d.shape_in_row == 2 && d.boundary_in_row == 1);
    string dot = c4_renderer().generate_dot(d);
    assert_has("rel text", dot, "<FONT COLOR=\"red\">");
    assert_has("rel line", dot, "constraint=false color=\"red\"");
    assert_has("element bg", dot, "fillcolor=\"orange\" color=");
    assert_has("element font", dot, "fontcolor=\"black\"");
    // Two shapes per row: user and web share a row, db starts the next
    assert_has("rows", dot, "{ rank=same; \"user\"; \"web\" }");
    assert_has("rows", dot, "\"user\" -> \"db\" [style=invis]");
    assert_exports("styles", src);
}

// K4: RelIndex and C4Dynamic numbering
void test_c4_rel_index() {
    string src = "C4Dynamic\n    title Dynamic\n    Container(a, \"SPA\", \"JS\", \"UI\")\n" +
        "    Container(b, \"API\", \"Go\", \"Backend\")\n    ContainerDb(c, \"DB\", \"SQL\", \"Data\")\n" +
        "    Rel(a, b, \"1. Submit\")\n    RelIndex(2, b, c, \"Store\")\n";
    var d = new MermaidC4Parser().parse(src);
    assert(d.relationships.size == 2);
    var r = d.relationships.get(1);
    assert(r.from_id == "b" && r.to_id == "c" && r.label == "Store");
    string dot = c4_renderer().generate_dot(d);
    assert_has("index", dot, "1: 1. Submit");
    assert_has("index", dot, "2: Store");
}

// ── Architecture ────────────────────────────────────────────────────────────

MermaidArchitectureRenderer arch_renderer() {
    return new MermaidArchitectureRenderer(gvc(), new Gee.ArrayList<ElementRegion>(), "dot");
}

// A1: "<-->" has heads at both ends
void test_arch_bidirectional() {
    var d = new MermaidArchitectureParser().parse(
        "architecture-beta\n    service a(server)[A]\n    service b(database)[B]\n    a:R <--> L:b\n");
    assert(d.edges.size == 1);
    var e = d.edges.get(0);
    assert(e.from_id == "a" && e.to_id == "b" && e.from_side == "R" && e.to_side == "L");
    assert(e.arrow_from && e.arrow_to);
    string dot = arch_renderer().generate_dot(d);
    // The layout is computed here and pinned (layout=nop2), so an edge runs between
    // two of its own points rather than between the service nodes
    assert_has("nop2", dot, "layout=nop2");
    assert_has("both", dot, "_ae0a -> _ae0b [dir=both arrowtail=normal arrowhead=normal]");

    d = new MermaidArchitectureParser().parse(
        "architecture-beta\n    service a(server)[A]\n    service b(database)[B]\n    a:R <-- L:b\n    a:L -[calls]- R:b\n");
    assert(d.edges.size == 2);
    assert(d.edges.get(0).arrow_from && !d.edges.get(0).arrow_to);
    assert(d.edges.get(1).label == "calls" && !d.edges.get(1).directed);
}

// A2: {group} edges join the groups instead of inventing services
void test_arch_group_edges() {
    string src = "architecture-beta\n    group g1(cloud)[G1]\n    group g2(cloud)[G2]\n" +
        "    service a(server)[A] in g1\n    service b(database)[B] in g2\n    a{group}:R --> L:b{group}\n";
    var d = new MermaidArchitectureParser().parse(src);
    assert(d.edges.size == 1);
    var e = d.edges.get(0);
    assert(e.from_id == "a" && e.to_id == "b" && e.from_group && e.to_group);
    string dot = arch_renderer().generate_dot(d);
    // the ends sit on the group outlines, not on the service tiles
    assert_lacks("group edge", dot, "{group}");
    double g1_right = node_pos_x(dot, "\"_ag_g1\"") + node_width(dot, "\"_ag_g1\"") / 2;
    double g2_left = node_pos_x(dot, "\"_ag_g2\"") - node_width(dot, "\"_ag_g2\"") / 2;
    assert(Math.fabs(node_pos_x(dot, "_ae0a") - g1_right) < 0.5);
    assert(Math.fabs(node_pos_x(dot, "_ae0b") - g2_left) < 0.5);
    assert_exports("group edge", src);
}

// A3: icons are drawn; nested groups keep a visible border
void test_arch_icons() {
    string src = "architecture-beta\n    group outer(cloud)[Outer]\n    group inner(server)[Inner] in outer\n" +
        "    service a(server)[A] in inner\n    service b(disk)[B]\n    service c(internet)[C]\n    service d(database)[D]\n" +
        "    service e(logos:aws)[E]\n    a:R -- L:b\n";
    var d = new MermaidArchitectureParser().parse(src);
    string svg = svg_string(arch_renderer().render_to_svg(d));
    assert_lacks("icon text", svg, "[server]");
    assert_lacks("icon text", svg, "[database]");
    assert_lacks("placeholder", svg, "#0a0b0");
    // 5 service tiles + 2 group tiles
    int tiles = 0, pos = 0;
    while ((pos = svg.index_of("fill=\"#087ebf\"", pos)) >= 0) { tiles++; pos++; }
    assert(tiles == 7);
    int glyphs = 0;
    pos = 0;
    while ((pos = svg.index_of("class=\"gdarchicon\"", pos)) >= 0) { glyphs++; pos++; }
    assert(glyphs == 6);  // the unknown icon gets a "?" instead
    assert_has("unknown icon", svg, ">?</text>");
    string dot = arch_renderer().generate_dot(d);
    int inner = dot.index_of("\"_ag_inner\"");
    assert(inner > 0);
    assert(dot.index_of("style=dashed", inner) > inner);
    // the nested outline stays inside its parent's
    assert(node_width(dot, "\"_ag_inner\"") < node_width(dot, "\"_ag_outer\""));
}

// Centre x of a pinned node, in points
double node_pos_x(string dot, string id) {
    int at = dot.index_of(id + " [");
    assert(at >= 0);
    int p = dot.index_of("pos=\"", at);
    assert(p > at);
    return double.parse(dot.substring(p + 5));
}

double node_width(string dot, string id) {
    int at = dot.index_of(id + " [");
    assert(at >= 0);
    int w = dot.index_of(" width=", at);
    assert(w > at);
    return double.parse(dot.substring(w + 7)) * 72.0;
}

// ── Requirement ─────────────────────────────────────────────────────────────

// R1: "a <- satisfies - b" is b satisfies a
void test_req_reversed_links() {
    var d = new MermaidRequirementParser().parse(
        "requirementDiagram\n    requirement r1 {\n        id: 1\n        text: t\n    }\n" +
        "    element e1 {\n        type: x\n    }\n    r1 <- satisfies - e1\n    e1 - traces -> r1\n");
    assert(d.relationships.size == 2);
    var r = d.relationships.get(0);
    assert(r.source == "e1" && r.target == "r1" && r.rel_type == "satisfies");
    r = d.relationships.get(1);
    assert(r.source == "e1" && r.target == "r1" && r.rel_type == "traces");
}

// R2: quoted names and values
void test_req_quoted() {
    string src = "requirementDiagram\n    requirement \"Login Req\" {\n        id: 1\n" +
        "        text: \"Users log in: with password\"\n        risk: high\n        verifymethod: test\n    }\n" +
        "    element \"Auth Module\" {\n        type: \"component\"\n    }\n    \"Login Req\" <- satisfies - \"Auth Module\"\n";
    var d = new MermaidRequirementParser().parse(src);
    assert(d.elements.size == 2);
    var req = d.elements.get(0);
    assert(req.name == "Login Req");
    assert(req.text == "Users log in: with password");
    var el = d.elements.get(1);
    assert(el.name == "Auth Module" && el.elem_type == "component");
    assert(d.relationships.size == 1);
    assert(d.relationships.get(0).source == "Auth Module" && d.relationships.get(0).target == "Login Req");
    var r = new MermaidRequirementRenderer(gvc(), new Gee.ArrayList<ElementRegion>(), "dot");
    string dot = r.generate_dot(d);
    assert_lacks("quotes", dot, "Req&quot;");
    assert_lacks("quotes", dot, "&quot;component&quot;");
    assert_has("edge", dot, "r_Auth_Module -> r_Login_Req");
    assert_exports("quoted", src);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/mermaid-arch/block/syntax_exports", test_block_syntax_exports);
    Test.add_func("/review/mermaid-arch/block/grid", test_block_grid);
    Test.add_func("/review/mermaid-arch/block/nested_groups", test_block_nested_groups);
    Test.add_func("/review/mermaid-arch/block/indexed_lookup", test_block_lookup_is_indexed_and_keeps_the_first_duplicate);
    Test.add_func("/review/mermaid-arch/block/front_matter", test_block_front_matter_title);
    Test.add_func("/review/mermaid-arch/c4/deployment_nodes", test_c4_deployment_nodes);
    Test.add_func("/review/mermaid-arch/c4/labels", test_c4_labels);
    Test.add_func("/review/mermaid-arch/c4/styles_layout", test_c4_styles_and_layout_config);
    Test.add_func("/review/mermaid-arch/c4/rel_index", test_c4_rel_index);
    Test.add_func("/review/mermaid-arch/architecture/bidirectional", test_arch_bidirectional);
    Test.add_func("/review/mermaid-arch/architecture/group_edges", test_arch_group_edges);
    Test.add_func("/review/mermaid-arch/architecture/icons", test_arch_icons);
    Test.add_func("/review/mermaid-arch/requirement/reversed", test_req_reversed_links);
    Test.add_func("/review/mermaid-arch/requirement/quoted", test_req_quoted);
    return Test.run();
}
