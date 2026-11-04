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


// ---- PlantUML `scale` (2026-11-04) ----
//
// gDiagram ignored `scale` entirely, and that is the directive that exists to stop stock
// PlantUML silently cropping a drawing at 4096 px. Because gDiagram renders at any size, the
// preview - the only place an author would notice - could not show them whether the line they
// added did anything. Semantics measured against PlantUML 1.2026.9; see RenderUtils.ScaleSpec.

// The rendered pixel width, which is what `scale ... width` is specified in - NOT the
// point value on the <svg> tag. A first version of this test converted pt to px at 96/72
// and failed a correct implementation: librsvg's intrinsic size does not follow that ratio
// for these pages, and the directive has to be computed in the units it is written in.
double svg_width_px(string svg) {
    try {
        var stream = new MemoryInputStream.from_data(svg.data);
        var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);
        double w, h;
        handle.get_intrinsic_size_in_pixels(out w, out h);
        return w;
    } catch (Error e) {
        printerr("could not parse the exported SVG: %s\n", e.message);
        assert_not_reached();
    }
}

const string SCALE_BODY = "participant \"Service Number 01\" as A\n" +
                          "participant \"Service Number 02\" as B\n" +
                          "A -> B : hello world this is a message\n";

string scaled_svg(string directive) {
    string head = directive.length > 0 ? directive + "\n" : "";
    return exported_svg("@startuml\n" + head + SCALE_BODY + "@enduml\n");
}

void test_scale_forms() {
    double plain = svg_width_px(scaled_svg(""));
    assert(plain > 0);

    // A uniform factor, including the ratio spelling.
    double twice = svg_width_px(scaled_svg("scale 2"));
    double half  = svg_width_px(scaled_svg("scale 0.5"));
    double ratio = svg_width_px(scaled_svg("scale 2/3"));
    assert((twice / plain - 2.0).abs() < 0.02);
    assert((half / plain - 0.5).abs() < 0.02);
    assert((ratio / plain - 2.0 / 3.0).abs() < 0.02);

    // Scale TO a width, and fit inside a box (width-limited here).
    assert((svg_width_px(scaled_svg("scale 800 width")) - 800.0).abs() < 2.0);
    assert((svg_width_px(scaled_svg("scale 800*600")) - 800.0).abs() < 2.0);
}

void test_scale_max_only_shrinks() {
    double plain = svg_width_px(scaled_svg(""));

    // `max` caps a drawing that is too wide ...
    double capped = svg_width_px(scaled_svg("scale max 300 width"));
    assert((capped - 300.0).abs() < 2.0);
    assert(capped < plain);

    // ... and does NOTHING when the drawing already fits. This is the half that
    // distinguishes `max` from a plain `scale N width`, and the one a test that only
    // checked shrinking would miss: measured in PlantUML 1.2026.9, a 358x137 drawing is
    // unchanged by `scale max 300 height`.
    double uncapped = svg_width_px(scaled_svg("scale max 300 height"));
    assert((uncapped - plain).abs() < 0.01);
}

void test_plantuml_crop_prediction() {
    // Fixed numbers on purpose: the first version of this check rendered a 26-participant
    // diagram and asserted on its pixel width. That passed on Debian and FAILED on CI's
    // Ubuntu, because the width depends on which fonts are installed - the test was
    // measuring the font stack, not the rule.
    //
    // Measured against PlantUML 1.2026.9: our 5125 px is 3875 px there (fine), our
    // 7890 px is cropped at 4096 (not fine).
    assert(!RenderUtils.exceeds_plantuml_crop(5125, 1200));
    assert(RenderUtils.exceeds_plantuml_crop(7890, 1547));

    // The boundary is PlantUML's 4096, reached at ~5389 of ours - NOT at 4096 of ours,
    // which is what the warning used to use and why it cried wolf.
    assert(!RenderUtils.exceeds_plantuml_crop(4097, 100));
    assert(!RenderUtils.exceeds_plantuml_crop(5300, 100));
    assert(RenderUtils.exceeds_plantuml_crop(5500, 100));

    // Height counts too: a tall diagram is cropped just as silently.
    assert(RenderUtils.exceeds_plantuml_crop(100, 5500));
}

void test_scale_inside_a_note_is_text() {
    // A note body is drawn, not executed. Measured: PlantUML leaves this diagram at its
    // original size; we doubled it. Found by review, not by me.
    string plain = exported_svg("@startuml\nnote left of A\nhello\nend note\nA -> B : x\n@enduml\n");
    string noted = exported_svg("@startuml\nnote left of A\nscale 2\nend note\nA -> B : x\n@enduml\n");
    assert(svg_width_px(noted) == svg_width_px(plain));

    // ... while the same line at top level still scales, which is the half a fix for the
    // above can silently break - an earlier attempt disabled the directive outright and
    // only test_scale_forms caught it.
    double top = svg_width_px(exported_svg("@startuml\nscale 2\nA -> B : x\n@enduml\n"));
    double unscaled = svg_width_px(exported_svg("@startuml\nA -> B : x\n@enduml\n"));
    assert((top / unscaled - 2.0).abs() < 0.02);
}

void test_scale_directive_parsing() {
    var f = RenderUtils.parse_scale_directive("@startuml\nscale 2\n@enduml\n");
    assert(f != null && f.kind == RenderUtils.ScaleSpec.Kind.FACTOR && !f.is_max);
    assert((f.a - 2.0).abs() < 1e-9);

    var w = RenderUtils.parse_scale_directive("@startuml\nscale max 4000 width\n@enduml\n");
    assert(w != null && w.kind == RenderUtils.ScaleSpec.Kind.WIDTH && w.is_max);
    assert((w.a - 4000.0).abs() < 1e-9);

    var box = RenderUtils.parse_scale_directive("@startuml\nscale 800*600\n@enduml\n");
    assert(box != null && box.kind == RenderUtils.ScaleSpec.Kind.BOX);
    assert((box.a - 800.0).abs() < 1e-9 && (box.b - 600.0).abs() < 1e-9);

    // Anchored to a whole line: the word inside a label is not the directive. Without this
    // a ditaa drawing or any participant called "scale 2" would resize the diagram.
    assert(RenderUtils.parse_scale_directive("@startuml\nA -> B : scale 2 of them\n@enduml\n") == null);
    assert(RenderUtils.parse_scale_directive("@startuml\nparticipant \"scale 2\"\n@enduml\n") == null);
    assert(RenderUtils.parse_scale_directive("@startuml\nA -> B : x\n@enduml\n") == null);

    // `max` only ever shrinks.
    var cap = new RenderUtils.ScaleSpec();
    cap.kind = RenderUtils.ScaleSpec.Kind.WIDTH;
    cap.a = 300;
    cap.is_max = true;
    assert((cap.factor_for(600, 200) - 0.5).abs() < 1e-9);   // too wide: shrink
    assert((cap.factor_for(100, 200) - 1.0).abs() < 1e-9);   // already fits: no-op
    cap.is_max = false;
    assert((cap.factor_for(100, 200) - 3.0).abs() < 1e-9);   // plain form: grows
}


// ---- PlantUML's <U+XXXX> escape, and the \" that is not one (2026-11-04) ----

void test_unicode_escape_dot_labels() {
    string svg = exported_svg("@startuml\n" +
        "participant \"NVS <U+0022>boot<U+0022>\" as P\n" +
        "participant \"caf<U+00E9> <U+2192> done\" as Q\n" +
        "P -> Q : x\n@enduml\n");
    assert(!svg.contains("U+"));
    assert(svg.contains("café"));
    assert(svg.contains("→"));
}

void test_unicode_escape_html_labels() {
    // Class members are HTML-table labels, which never touch escape_label(); they went
    // through Markup.escape_text() directly and drew the tag.
    string cls = exported_svg("@startuml\nclass \"Caf<U+00E9>\" {\n  +field <U+2192> t\n}\n@enduml\n");
    assert(!cls.contains("U+"));
    assert(cls.contains("Café"));

    // A sequence NOTE body is a third path again - that renderer escapes char by char
    // through its own xml_escape(), not through either of the other two.
    string note = exported_svg("@startuml\nA -> B : msg <U+2192> ok\n" +
        "note right of B\nbody <U+00E9> and <U+0022>q<U+0022>\nend note\n@enduml\n");
    assert(!note.contains("U+"));
    assert(note.contains("→"));
    assert(note.contains("é"));
}

void test_unicode_escape_keeps_message_fast_path() {
    // is_plain_text() picks the fast path by comparing creole_html(t) with xml_escape(t).
    // Teaching only ONE of them to decode made any message containing an escape look like
    // markup, pushing it off the fast path - at which point the escape stopped working in
    // messages while it started working in notes. Both must decode.
    string svg = exported_svg("@startuml\nA -> B : msg <U+2192> ok\n@enduml\n");
    assert(svg.contains("→"));
    assert(!svg.contains("U+"));
}

void test_unicode_escape_invalid_left_alone() {
    // Called directly rather than through the engine, so the PlantUML-only flag has to be
    // set by hand: it defaults OFF so a Mermaid render cannot pick up a PlantUML escape.
    RenderUtils.unicode_escapes_enabled = true;
    // Past U+10FFFF is not a code point, so it was never an escape: it is text.
    assert(RenderUtils.decode_unicode_escapes("a <U+110000> b") == "a <U+110000> b");
    assert(RenderUtils.decode_unicode_escapes("a <U+D800> b") == "a <U+D800> b");
    assert(RenderUtils.decode_unicode_escapes("nothing here") == "nothing here");
    assert(RenderUtils.decode_unicode_escapes("<u+0041>") == "A");

    // PlantUML decodes 4- and 5-digit forms only (measured): these stay literal.
    assert(RenderUtils.decode_unicode_escapes("<U+41>") == "<U+41>");
    assert(RenderUtils.decode_unicode_escapes("<U+01F600>") == "<U+01F600>");

    // And nothing is decoded for a Mermaid render.
    RenderUtils.unicode_escapes_enabled = false;
    assert(RenderUtils.decode_unicode_escapes("<U+2192>") == "<U+2192>");
}

void test_escaped_quote_detection() {
    // PlantUML rejects the WHOLE file for this one ...
    var bad = DiagramLinter.escaped_quote_lines(
        "@startuml\nparticipant \"NVS \\\"boot\\\"\" as P\n@enduml\n", DiagramType.SEQUENCE);
    assert(bad.size == 1);
    assert(bad.get(0) == 2);

    // ... and accepts these, measured: nothing is quoted, so the backslash-quote is just
    // text. A check that grepped for the two characters would flag both and cry wolf.
    var msg = DiagramLinter.escaped_quote_lines("@startuml\nA -> B : he said \\\"hi\\\"\n@enduml\n",
                                                DiagramType.SEQUENCE);
    assert(msg.size == 0);
    var note = DiagramLinter.escaped_quote_lines(
        "@startuml\nnote over A\nhe said \\\"hi\\\"\nend note\n@enduml\n", DiagramType.SEQUENCE);
    assert(note.size == 0);

    // Data types are not code: PlantUML renders both of these, so warning about them told
    // the author a valid file was broken. Measured against 1.2026.9.
    var json = DiagramLinter.escaped_quote_lines(
        "@startjson\n{\"msg\": \"he said \\\"hi\\\"\"}\n@endjson\n", DiagramType.JSON_DIAGRAM);
    assert(json.size == 0);
    var yaml = DiagramLinter.escaped_quote_lines(
        "@startyaml\nmsg: \"he said \\\"hi\\\"\"\n@endyaml\n", DiagramType.YAML_DIAGRAM);
    assert(yaml.size == 0);

    // Nor is a comment.
    var comment = DiagramLinter.escaped_quote_lines(
        "@startuml\n' a comment with \"quoted \\\" x\"\nA -> B : ok\n@enduml\n", DiagramType.SEQUENCE);
    assert(comment.size == 0);
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
    Test.add_func("/renderutils/scale/forms", test_scale_forms);
    Test.add_func("/renderutils/scale/max_only_shrinks", test_scale_max_only_shrinks);
    Test.add_func("/renderutils/crop/plantuml_prediction", test_plantuml_crop_prediction);
    Test.add_func("/renderutils/scale/note_body_is_text", test_scale_inside_a_note_is_text);
    Test.add_func("/renderutils/scale/parsing", test_scale_directive_parsing);
    Test.add_func("/renderutils/unicode/dot_labels", test_unicode_escape_dot_labels);
    Test.add_func("/renderutils/unicode/html_labels", test_unicode_escape_html_labels);
    Test.add_func("/renderutils/unicode/message_fast_path", test_unicode_escape_keeps_message_fast_path);
    Test.add_func("/renderutils/unicode/invalid_left_alone", test_unicode_escape_invalid_left_alone);
    Test.add_func("/renderutils/portability/escaped_quote", test_escaped_quote_detection);
    Test.run();
}
