// RenderUtils review findings: circle-plus markers on the right edge end, actor figure
// colours, contrast text on see-through fills, collision-free DOT keyword ids.
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

int count_of(string text, string needle) {
    int n = 0;
    int at = text.index_of(needle);
    while (at >= 0) {
        n++;
        at = text.index_of(needle, at + needle.length);
    }
    return n;
}

string exported_svg(string source) {
    string path = Path.build_filename(Environment.get_tmp_dir(),
        "review_renderutils_%u_%u.svg".printf(Random.next_int(), Random.next_int()));
    if (!engine().export_to_svg(source, null, null, path)) {
        printerr("\nexport failed for:\n%s\n", source);
        assert_not_reached();
    }
    string svg;
    try {
        FileUtils.get_contents(path, out svg);
    } catch (FileError e) {
        printerr("%s\n", e.message);
        assert_not_reached();
    }
    FileUtils.remove(path);
    return svg;
}

string edge_svg(string classes, string ellipses) {
    return "<svg><g id=\"edge1\" class=\"edge %s\">\n<title>A&#45;&gt;B</title>\n<path fill=\"none\" stroke=\"black\" d=\"M27,-62C27,-56 27,-50 27,-44\"/>\n%s</g>\n</svg>".printf(classes, ellipses);
}

const string TAIL_ELLIPSE = "<ellipse fill=\"none\" stroke=\"black\" cx=\"27\" cy=\"-66\" rx=\"5\" ry=\"5\"/>\n";
const string HEAD_ELLIPSE = "<ellipse fill=\"none\" stroke=\"black\" cx=\"27\" cy=\"-41\" rx=\"5\" ry=\"5\"/>\n";
const string FILLED_ELLIPSE = "<ellipse fill=\"black\" stroke=\"black\" cx=\"27\" cy=\"-66\" rx=\"4\" ry=\"4\"/>\n";

string markers(string svg) {
    uint8[] data = svg.data;
    uint8[] result = RenderUtils.draw_custom_markers(data);
    var sb = new StringBuilder();
    sb.append_len((string) result, result.length);
    return sb.str;
}

// ==================== draw_custom_markers ====================

void test_plus_both_ends() {
    string out_svg = markers(edge_svg("gdplus", TAIL_ELLIPSE + HEAD_ELLIPSE));
    expect_int(count_of(out_svg, "class=\"gdmark\""), 2, "a plus in both circles");
    assert(out_svg.contains("M22,-66 L32,-66"));
    assert(out_svg.contains("M22,-41 L32,-41"));

    // End to end: "A +--+ B"
    string svg = exported_svg("@startuml\nclass A\nclass B\nA +--+ B\n@enduml\n");
    expect_int(count_of(svg, "class=\"gdmark\""), 2, "class diagram +--+");
}

void test_plus_named_end() {
    // "0--+": tail circle plain, head circle plus
    string out_svg = markers(edge_svg("gdplus gdplushead", TAIL_ELLIPSE + HEAD_ELLIPSE));
    expect_int(count_of(out_svg, "class=\"gdmark\""), 1, "head only");
    assert(out_svg.contains("M22,-41 L32,-41"));
    assert(!out_svg.contains("M22,-66 L32,-66"));

    out_svg = markers(edge_svg("gdplus gdplustail", TAIL_ELLIPSE + HEAD_ELLIPSE));
    expect_int(count_of(out_svg, "class=\"gdmark\""), 1, "tail only");
    assert(out_svg.contains("M22,-66 L32,-66"));

    // A filled dot at the other end never gets a plus
    out_svg = markers(edge_svg("gdplus", FILLED_ELLIPSE + HEAD_ELLIPSE));
    expect_int(count_of(out_svg, "class=\"gdmark\""), 1, "hollow circle only");
    assert(out_svg.contains("M22,-41 L32,-41"));

    expect_str(RenderUtils.plus_marker_class(true, false), ", class=\"gdplus gdplustail\", arrowsize=1.3", "tail class");
    expect_str(RenderUtils.plus_marker_class(false, true), ", class=\"gdplus gdplushead\", arrowsize=1.3", "head class");
    expect_str(RenderUtils.plus_marker_class(false, false), "", "no plus");
    // Other edges are left alone
    string plain = edge_svg("", TAIL_ELLIPSE);
    expect_str(markers(plain), plain, "unmarked edge");
}

// ==================== actor figure colours ====================

void test_actor_color_tokens() {
    expect_str(RenderUtils.class_color_token("#0A4A89"), "0A4A89", "hex");
    expect_str(RenderUtils.class_color_token("Gold"), "Gold", "name");
    expect_str(RenderUtils.class_color_token("#FF000080"), "FF000080", "8-digit hex");
    expect_str(RenderUtils.class_color_token("#red-blue"), "red", "gradient");
    expect_str(RenderUtils.class_color_token("red:blue"), "red", "fill list");
    expect_str(RenderUtils.class_color_token("#pink;line:blue"), "pink", "line styling");
    expect_str(RenderUtils.class_color_token("#back:pink;line:blue"), "pink", "back: prefix");
}

string actor_svg(string fill_token) {
    return "<svg><g id=\"node1\" class=\"node gdactor gdfill_%s gdstroke_1168BD\">\n<polygon fill=\"#010203\" stroke=\"none\" points=\"10,-10 10,-56 40,-56 40,-10 10,-10\"/>\n</g></svg>".printf(fill_token);
}

string figures(string svg) {
    uint8[] result = RenderUtils.draw_actor_figures(svg.data);
    var sb = new StringBuilder();
    sb.append_len((string) result, result.length);
    return sb.str;
}

void test_actor_figure_fills() {
    string s = figures(actor_svg("FF000080"));
    assert(s.contains("fill=\"#FF0000\" fill-opacity=\"0.502\" stroke=\"#1168BD\""));
    s = figures(actor_svg("red"));
    assert(s.contains("fill=\"red\" stroke=\"#1168BD\""));
    s = figures(actor_svg("transparent"));
    assert(s.contains("fill=\"none\" stroke=\"#1168BD\""));
    assert(!figures(actor_svg("FF000080")).contains("fill=\"FF000080\""));

    // End to end: use case and sequence actors
    string uc = exported_svg("@startuml\nactor A #FF000080\nusecase U\nA --> U\n@enduml\n");
    assert(uc.contains("fill=\"#FF0000\" fill-opacity=\"0.502\""));
    string seq = exported_svg("@startuml\nactor A #red-blue\nparticipant B\nA -> B\n@enduml\n");
    assert(!seq.contains("fill=\"redblue\""));
    assert(seq.contains("<circle class=\"gdfigure\"") && seq.contains("fill=\"red\" stroke="));
}

// ==================== contrast_text ====================

void test_contrast_text_see_through() {
    string theme_text = ThemeManager.get_active_palette().node_text;
    expect_str(RenderUtils.contrast_text("transparent"), theme_text, "transparent");
    expect_str(RenderUtils.contrast_text("none"), theme_text, "none");
    expect_str(RenderUtils.contrast_text_themed("#FFFFFF10", "#123456"), "#123456", "mostly see-through");
    expect_str(RenderUtils.contrast_text_themed("transparent", "#EEEEEE"), "#EEEEEE", "themed transparent");
    // 8-digit hex reads its colour: a light yellow gets dark text
    expect_str(RenderUtils.contrast_text("#FFFF00C0"), "#000000", "8-digit light");
    expect_str(RenderUtils.contrast_text("#000080FF"), "#FFFFFF", "8-digit dark");
    expect_str(RenderUtils.contrast_text_themed("#FFFF00C0", "#123456"), "#000000", "opaque enough");
    // Unchanged cases
    expect_str(RenderUtils.contrast_text("#FFFFFF"), "#000000", "white");
    expect_str(RenderUtils.contrast_text("navy"), "#FFFFFF", "navy");
}

// ==================== sanitize_id ====================

void test_sanitize_id_keywords_collision_free() {
    expect_str(RenderUtils.sanitize_id("node"), "node_", "keyword");
    expect_str(RenderUtils.sanitize_id("node_"), "node__", "keyword with underscore");
    expect_str(RenderUtils.sanitize_id("node__"), "node___", "keyword with two underscores");
    expect_str(RenderUtils.sanitize_id("Graph"), "Graph_", "any case");
    expect_str(RenderUtils.sanitize_id("edge-"), "edge__", "sanitized to a keyword form");
    expect_str(RenderUtils.sanitize_id("foo_"), "foo_", "other ids unchanged");
    expect_str(RenderUtils.sanitize_id("nodes"), "nodes", "longer word");
    expect_str(RenderUtils.sanitize_id("_"), "_", "underscore only");

    // Two classes "node" and "node_" stay two nodes
    string dot = engine().generate_dot("@startuml\nclass node\nclass node_\nnode --> node_\n@enduml\n", null, null);
    assert(dot != null);
    assert(dot.contains("node_ -> node__") || dot.contains("node_ -> node__ "));
}

// The component and class renderers name the "+" end, so "0--+" puts the plus
// into the head circle, and after an up swap into the tail circle
void test_plus_end_from_renderers() {
    string svg = exported_svg("@startuml\n[A] 0--+ [B]\n[C] 0-up-+ [D]\n@enduml\n");
    expect_int(count_of(svg, "class=\"edge gdplus gdplushead\""), 1, "0--+ marks the head");
    expect_int(count_of(svg, "class=\"edge gdplus gdplustail\""), 1, "0-up-+ marks the swapped tail");
}

// Non-ASCII names keep their letters in DOT ids ("Ä" and "Ü" were both "_", one node),
// and click regions still name the elements
string engine_dot_named(string source, string filename) {
    string? dot = engine().generate_dot(source, filename, null);
    assert(dot != null);
    return dot;
}

void test_non_ascii_ids() {
    string comp = engine_dot_named("@startuml\ncomponent Ä\ncomponent Ü\nÄ --> Ü\n@enduml\n", "t.puml");
    expect_int(count_of(comp, "Ä -> Ü"), 1, "component edge between two nodes");
    string cls = engine_dot_named("@startuml\nclass Äpfel\nclass Öpfel\nÄpfel --> Öpfel\n@enduml\n", "t.puml");
    expect_int(count_of(cls, "Äpfel -> Öpfel"), 1, "class edge");
    string mmd = engine_dot_named("flowchart TD\n  Ä[Grüße] --> Ü[Welt]\n", "t.mmd");
    expect_int(count_of(mmd, "Ä -> Ü"), 1, "flowchart edge");

    var eng = engine();
    var result = eng.render(DiagramType.COMPONENT, DiagramFormat.PLANTUML, "@startuml\ncomponent Ä\ncomponent Ü\nÄ --> Ü\n@enduml\n");
    assert(result.surface != null);
    int named = 0;
    foreach (var r in eng.last_regions) {
        if (r.name == "Ä" || r.name == "Ü") named++;
    }
    expect_int(named, 2, "click regions for both components");
}

// Graphviz SVG: the background covers the whole rounded canvas, and default (black)
// graph/cluster titles contrast with what is behind them
void test_svg_background_and_titles() {
    string svg = """<svg width="216pt" height="528pt" viewBox="0.00 0.00 216.00 528.00">
<g id="graph0" class="graph" transform="translate(4 524)">
<title>G</title>
<polygon fill="#1e1e1e" stroke="none" points="-4,4 -4,-524 211.5,-524 211.5,4 -4,4"/>
<text x="100" y="-500" font-size="14.00">Title</text>
<g id="clust1" class="cluster">
<title>cluster_0</title>
<path fill="#2e2e2e" stroke="black" d="M0,0"/>
<text x="10" y="-10">Dark cluster</text>
</g>
<g id="clust2" class="cluster">
<title>cluster_1</title>
<polygon fill="#ffd54f" stroke="black" points="0,0"/>
<text x="10" y="-10">Light cluster</text>
<text x="10" y="-20" fill="#ff0000">Explicit</text>
</g>
<g id="node1" class="node"><title>a</title><text x="1" y="1">node text</text></g>
</g>
</svg>""";
    var bytes = RenderUtils.fill_svg_background(svg.data);
    var sb = new StringBuilder();
    sb.append_len((string) bytes, bytes.length);
    string out_svg = sb.str;
    assert(out_svg.contains("<rect x=\"0\" y=\"0\" width=\"100%\" height=\"100%\" fill=\"#1e1e1e\"/>"));
    assert(out_svg.contains("fill=\"#FFFFFF\">Title</text>"));
    assert(out_svg.contains("fill=\"#FFFFFF\">Dark cluster</text>"));
    assert(out_svg.contains("fill=\"#000000\">Light cluster</text>"));
    assert(out_svg.contains("fill=\"#ff0000\">Explicit</text>"));
    assert(out_svg.contains("<text x=\"1\" y=\"1\">node text</text>"));
    assert(count_of(out_svg, "</svg>") == 1);
}

// Cluster titles default to Sans, not Graphviz's Times, in-process (Mermaid flowchart)
// and through the dot subprocess (PlantUML use case)
void test_cluster_titles_sans() {
    string mmd = exported_svg("flowchart TD\n  subgraph Group\n    A --> B\n  end\n");
    string uc = exported_svg("@startuml\nactor User\nrectangle Shop {\n  (Buy)\n}\nUser --> (Buy)\n@enduml\n");
    assert(!mmd.contains("Times"));
    assert(!uc.contains("Times"));
    assert(uc.contains("font-family=\"Sans\""));
}

void main(string[] args) {
    Test.init(ref args);
    Test.add_func("/renderutils/markers/plus_both_ends", test_plus_both_ends);
    Test.add_func("/renderutils/markers/plus_named_end", test_plus_named_end);
    Test.add_func("/renderutils/markers/plus_end_from_renderers", test_plus_end_from_renderers);
    Test.add_func("/renderutils/ids/non_ascii", test_non_ascii_ids);
    Test.add_func("/renderutils/svg/background_and_titles", test_svg_background_and_titles);
    Test.add_func("/renderutils/svg/cluster_titles_sans", test_cluster_titles_sans);
    Test.add_func("/renderutils/actor/color_tokens", test_actor_color_tokens);
    Test.add_func("/renderutils/actor/figure_fills", test_actor_figure_fills);
    Test.add_func("/renderutils/contrast/see_through", test_contrast_text_see_through);
    Test.add_func("/renderutils/sanitize_id/keywords", test_sanitize_id_keywords_collision_free);
    Test.run();
}
