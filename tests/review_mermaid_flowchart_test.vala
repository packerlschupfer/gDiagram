using GDiagram;

/*
 * Mermaid fidelity review: the shared lexer's text reconstruction and the flowchart
 * parser / renderer syntax (compared with Mermaid CLI 11.17).
 *
 * Checks are non-fatal so one run reports every failing case.
 */

bool check(bool ok, string what) {
    if (!ok) {
        printerr("FAILED: %s\n", what);
        Test.fail();
    }
    return ok;
}

void check_str(string? got, string want, string what) {
    if (got != want) {
        printerr("FAILED: %s: got '%s', want '%s'\n", what, got ?? "(null)", want);
        Test.fail();
    }
}

MermaidFlowchart flow(string src) {
    return new MermaidFlowchartParser().parse(src);
}

string dot_of(string src) {
    string? dot = new DiagramEngine("dot").generate_dot(src, "x.mmd", null);
    if (dot == null) {
        printerr("FAILED: no DOT for:\n%s\n", src);
        Test.fail();
        return "";
    }
    return dot;
}

Gvc.Context? gv_context = null;

// SVG text of the rendered source, null when rendering failed
string? svg_of(string src) {
    var d = flow(src);
    if (gv_context == null) gv_context = new Gvc.Context();  // the renderer holds it unowned
    var renderer = new MermaidFlowchartRenderer(gv_context, new Gee.ArrayList<ElementRegion>(), "dot");
    uint8[]? data = renderer.render_to_svg(d);
    if (data == null) return null;
    var sb = new StringBuilder.sized(data.length + 1);
    sb.append_len((string) data, data.length);
    return sb.str;
}

int index_of_type(Gee.List<MermaidToken> tokens, MermaidTokenType type, int from = 0) {
    for (int i = from; i < tokens.size; i++) {
        if (tokens[i].token_type == type) return i;
    }
    return -1;
}

bool has_node(MermaidFlowchart d, string id) {
    return d.find_node(id) != null;
}

bool has_edge(MermaidFlowchart d, string from, string to) {
    foreach (var e in d.edges) {
        if (e.from.id == from && e.to.id == to) return true;
    }
    return false;
}

// ---- L1: characters without a token of their own ----

void test_lexer_emoji_kept() {
    var tokens = new MermaidLexer("A[🚀 Start ✓ ⚙️ x]").scan_all();
    int texts = 0;
    foreach (var t in tokens) {
        if (t.token_type == MermaidTokenType.TEXT) texts++;
    }
    check(texts == 3, "emoji / symbol runs become TEXT tokens (got %d)".printf(texts));
    var d = flow("flowchart TD\n    A([🚀 Start Process]) --> B{✓ Validate}\n");
    check_str(d.find_node("A").text, "🚀 Start Process", "emoji kept in label");
    check_str(d.find_node("B").text, "✓ Validate", "check mark kept in label");
}

void test_lexer_apostrophe() {
    var d = flow("flowchart LR\n    J[Don't stop] --> K(it's fine)\n    K --> L\n");
    check(has_node(d, "L"), "an apostrophe inside a word does not swallow the diagram");
    check_str(d.find_node("J").text, "Don't stop", "apostrophe label");
    check_str(d.find_node("K").text, "it's fine", "apostrophe in round node");
}

// ---- L2: exact text reconstruction ----

void test_lexer_text_range() {
    string src = "A[GET /a/b (x: 1)] --> B[Processing...]\nC[Click \"Place Order\" now]\n";
    var tokens = new MermaidLexer(src).scan_all();
    int open = index_of_type(tokens, MermaidTokenType.LBRACKET);
    int close = index_of_type(tokens, MermaidTokenType.RBRACKET, open);
    check_str(MermaidLexer.text_range(tokens, open + 1, close), "GET /a/b (x: 1)", "punctuation kept without spaces");
    open = index_of_type(tokens, MermaidTokenType.LBRACKET, close);
    close = index_of_type(tokens, MermaidTokenType.RBRACKET, open);
    check_str(MermaidLexer.text_range(tokens, open + 1, close), "Processing...", "skipped dots recovered");
    open = index_of_type(tokens, MermaidTokenType.LBRACKET, close);
    close = index_of_type(tokens, MermaidTokenType.RBRACKET, open);
    check_str(MermaidLexer.text_range(tokens, open + 1, close), "Click \"Place Order\" now", "quotes kept in text_range");

    // offsets, raw text and whitespace flags
    var t = new MermaidLexer("A  -->B").scan_all();
    check(t[1].offset == 3 && t[1].end_offset == 6 && t[1].raw == "-->", "token offsets / raw");
    check(t[1].space_before && t[1].leading == "  ", "leading whitespace");
    check(!t[2].space_before && t[2].leading == "", "no space before B");

    // label_text drops the quotes of a lone string
    var q = new MermaidLexer("[\"quoted\"]").scan_all();
    check_str(MermaidLexer.label_text(q, 1, 2), "quoted", "label_text of a lone string");
}

void test_lexer_entities() {
    check_str(MermaidLexer.decode_entities("He said #quot;hi#quot; #9829; #x2665; #amp; #unknown;"),
        "He said \"hi\" ♥ ♥ & #unknown;", "entity decoding");
}

void test_flowchart_label_text() {
    var d = flow("flowchart TD\n    A[GET /a/b, x: 1] --> B[Processing...]\n    B -->|a/b (c)| C\n");
    check_str(d.find_node("A").text, "GET /a/b, x: 1", "node label exact");
    check_str(d.find_node("B").text, "Processing...", "trailing dots kept");
    if (check(d.edges.size == 2, "2 edges")) {
        check_str(d.edges[1].label, "a/b (c)", "edge label exact");
    }
    var s = flow("flowchart TD\n    subgraph S1 [Title: One/Two]\n      a\n    end\n");
    check_str(s.subgraphs[0].title, "Title: One/Two", "subgraph title exact");
}

// ---- F1: :::class ----

void test_class_suffix() {
    var d = flow("flowchart TD\n    A:::hot --> B:::cold\n    C --> D\n    D:::hot\n    classDef hot fill:#f96,color:#fff\n    classDef cold fill:#9cf\n");
    check(!has_node(d, "hot") && !has_node(d, "cold"), ":::class is not a node");
    check(has_edge(d, "A", "B"), ":::class on a source keeps the edge A -> B");
    check(d.nodes.size == 4, "4 nodes (got %d)".printf(d.nodes.size));
    check_str(d.find_node("A").fill_color, "#f96", "class applied to source (classDef after use)");
    check_str(d.find_node("A").font_color, "#fff", "classDef color is the text colour");
    check_str(d.find_node("B").fill_color, "#9cf", "class applied to target");
    check_str(d.find_node("D").fill_color, "#f96", "A:::cls statement");
}

// ---- F2: unquoted link text ----

void test_link_text() {
    var d = flow("flowchart LR\n    A -- yes --> B\n    C == thick one ==> D\n    E -. maybe .-> F\n    G -- \"quoted\" --> H\n");
    check(d.nodes.size == 8, "no fake label nodes (got %d)".printf(d.nodes.size));
    check(!has_node(d, "yes") && !has_node(d, "maybe"), "label words are not nodes");
    check(d.edges.size == 4, "4 edges");
    if (d.edges.size == 4) {
        check_str(d.edges[0].label, "yes", "-- text -->");
        check_str(d.edges[1].label, "thick one", "== text ==>");
        check(d.edges[1].edge_type == FlowchartEdgeType.THICK, "thick text link");
        check_str(d.edges[2].label, "maybe", "-. text .->");
        check(d.edges[2].edge_type == FlowchartEdgeType.DOTTED, "dotted text link");
        check_str(d.edges[3].label, "quoted", "-- \"text\" -->");
    }
}

// ---- F3: subgraph as edge end ----

void test_subgraph_edge() {
    string src = "flowchart LR\n    subgraph X\n      a\n    end\n    subgraph Y\n      b\n    end\n    X --> Y\n";
    var d = flow(src);
    check(!has_node(d, "X") && !has_node(d, "Y"), "subgraph ids are not nodes");
    check(d.edges.size == 1 && d.edges[0].from_subgraph != null && d.edges[0].to_subgraph != null,
        "edge attached to both subgraphs");
    string dot = dot_of(src);
    check(dot.contains("a -> b [ltail=cluster_0, lhead=cluster_1]"), "DOT edge clipped at the clusters");
    // empty subgraph gets an invisible anchor
    string empty = dot_of("flowchart LR\n    subgraph E\n    end\n    n --> E\n");
    check(empty.contains("cluster_0_anchor [shape=point") && empty.contains("n -> cluster_0_anchor [lhead=cluster_0]"),
        "empty subgraph anchor");
    // "subgraph My Group" has no usable id: My stays a node
    var g = flow("flowchart TD\n    subgraph My Group\n        My --> X\n    end\n");
    check(has_node(g, "My"), "subgraph title with spaces is not an id");
}

// ---- F4: @{ shape } ----

void test_shape_data() {
    var d = flow("flowchart TD\n    D --> E@{ shape: cyl, label: \"New DB\" }\n    E --> F@{ shape: diam, label: \"Decide\" }\n    G@{ shape: lean-l }\n    H@{ icon: \"fa:user\", form: \"circle\", label: \"User\" }\n    I@{ shape: docs,\n        label: \"Multi\" }\n    D e1@--> I\n    e1@{ animate: true }\n");
    check(!has_node(d, "shape") && !has_node(d, "cyl") && !has_node(d, "label"), "shape data is not nodes");
    check(!has_node(d, "e1"), "edge id is not a node");
    check(d.find_node("E").shape == FlowchartNodeShape.CYLINDRICAL, "shape: cyl");
    check_str(d.find_node("E").text, "New DB", "label from shape data");
    check(d.find_node("F").shape == FlowchartNodeShape.RHOMBUS, "shape: diam");
    check(d.find_node("G").shape == FlowchartNodeShape.PARALLELOGRAM_ALT, "shape: lean-l");
    check_str(d.find_node("G").text, "G", "no label: the id");
    check(d.find_node("H").shape == FlowchartNodeShape.CIRCLE && d.find_node("H").text == "User", "icon form circle");
    check(d.find_node("I").shape == FlowchartNodeShape.STACKED_RECT && d.find_node("I").text == "Multi", "multi-line shape data");
    check(has_edge(d, "D", "I"), "edge with an edge id");
    check(MermaidFlowchartParser.shape_from_name("notch-rect") == FlowchartNodeShape.NOTCHED_RECT, "notch-rect");
    check(MermaidFlowchartParser.shape_from_name("hourglass") == FlowchartNodeShape.HOURGLASS, "hourglass");
    check(MermaidFlowchartParser.shape_from_name("trap-t") == FlowchartNodeShape.TRAPEZOID_ALT, "trap-t");
    string dot = dot_of("flowchart TD\n    E@{ shape: cyl, label: \"New DB\" }\n");
    check(dot.contains("E [label=\"New DB\", shape=cylinder"), "cylinder DOT");
}

// ---- F5: circle / cross ends ----

void test_circle_cross_ends() {
    var d = flow("flowchart LR\n    A o--o B\n    C x--x D\n    E --o F\n    G --x H\n");
    check(d.nodes.size == 8 && !has_node(d, "o") && !has_node(d, "x"), "o / x are not nodes");
    if (d.edges.size == 4) {
        check(d.edges[0].arrow_type == FlowchartArrowType.OPEN && d.edges[0].tail_arrow_type == FlowchartArrowType.OPEN, "o--o");
        check(d.edges[1].arrow_type == FlowchartArrowType.CROSS && d.edges[1].tail_arrow_type == FlowchartArrowType.CROSS, "x--x");
    } else {
        check(false, "4 edges (got %d)".printf(d.edges.size));
    }
    string dot = dot_of("flowchart LR\n    E --o F\n    G --x H\n");
    check(dot.contains("E -> F [arrowhead=dot]"), "--o is a filled circle");
    check(dot.contains("G -> H [arrowhead=obox, class=\"gdfcross\"]"), "--x placeholder");
    string? svg = svg_of("flowchart LR\n    G --x H\n    C x--x D\n");
    check(svg != null, "cross SVG");
    if (svg != null) {
        string s = svg;
        int marks = 0;
        int pos = 0;
        while ((pos = s.index_of("class=\"gdmark\"", pos)) >= 0) {
            marks++;
            pos++;
        }
        check(marks == 3, "every cross end drawn as an x (got %d)".printf(marks));
        check(!s.contains("<polygon fill=\"none\""), "no obox left");
    }
}

// ---- F6: bidirectional links ----

void test_bidirectional() {
    string src = "flowchart LR\n    F <--> G\n    E <-.-> H\n    I <==> J\n";
    var d = flow(src);
    check(d.edges.size == 3, "3 bidirectional edges (got %d)".printf(d.edges.size));
    if (d.edges.size == 3) {
        check(d.edges[0].tail_arrow_type == FlowchartArrowType.NORMAL && d.edges[0].edge_type == FlowchartEdgeType.SOLID, "<-->");
        check(d.edges[1].tail_arrow_type == FlowchartArrowType.NORMAL && d.edges[1].edge_type == FlowchartEdgeType.DOTTED, "<-.->");
        check(d.edges[2].tail_arrow_type == FlowchartArrowType.NORMAL && d.edges[2].edge_type == FlowchartEdgeType.THICK, "<==>");
    }
    string dot = dot_of(src);
    check(dot.contains("F -> G [dir=both, arrowtail=normal]"), "both-ended DOT");
    check(svg_of(src) != null, "bidirectional render");
}

// ---- F7: bracket shapes ----

void test_bracket_shapes() {
    var d = flow("flowchart LR\n    Z[(DB)] --> A[/Para/] --> B[\\Alt\\] --> C[/Trap\\] --> D[\\TrapAlt/] --> E>Asym]\n");
    check(d.find_node("Z").shape == FlowchartNodeShape.CYLINDRICAL && d.find_node("Z").text == "DB", "[(DB)] cylinder");
    check(d.find_node("A").shape == FlowchartNodeShape.PARALLELOGRAM, "[/Para/]");
    check(d.find_node("B").shape == FlowchartNodeShape.PARALLELOGRAM_ALT, "[\\Alt\\]");
    check(d.find_node("C").shape == FlowchartNodeShape.TRAPEZOID && d.find_node("C").text == "Trap", "[/Trap\\]");
    check(has_node(d, "D") && d.find_node("D").shape == FlowchartNodeShape.TRAPEZOID_ALT && d.find_node("D").text == "TrapAlt", "[\\TrapAlt/]");
    check(has_edge(d, "C", "D") && has_edge(d, "D", "E"), "chain through the trapezoids");
    string dot = dot_of("flowchart LR\n    A[/Para/] --> B[\\Alt\\] --> E>Asym]\n");
    check(dot.contains("shape=parallelogram"), "parallelogram shape");
    check(dot.contains("shape=polygon, sides=4, skew=-0.4"), "lean-left polygon");
    check(dot.contains("shape=cds, orientation=180"), "asymmetric cds");
    check(!dot.contains("skew=0.2") && !dot.contains("skew=0.3"), "no ignored box skew");
}

// ---- F8: linkStyle and subgraph style ----

void test_link_style_and_subgraph_style() {
    string src = "flowchart TB\n    subgraph S1 [One]\n      a --> b\n    end\n    b --> c\n    linkStyle default stroke:#999\n    linkStyle 1 stroke:#ff0000,stroke-width:4px,color:blue\n    style S1 fill:#ffcccc,stroke:#f00\n";
    var d = flow(src);
    check(d.edges.size == 2, "2 edges");
    if (d.edges.size == 2) {
        check_str(d.edges[0].edge_color, "#999", "linkStyle default");
        check_str(d.edges[1].edge_color, "#ff0000", "linkStyle 1 stroke");
        check_str(d.edges[1].edge_thickness, "4", "linkStyle stroke-width");
        check_str(d.edges[1].label_color, "blue", "linkStyle color");
    }
    check_str(d.subgraphs[0].fill_color, "#ffcccc", "style on subgraph fill");
    string dot = dot_of(src);
    check(dot.contains("b -> c [color=\"#ff0000\", penwidth=4, fontcolor=\"blue\"]"), "linkStyle DOT");
    check(dot.contains("fillcolor=\"#ffcccc\"") && dot.contains("color=\"#f00\""), "subgraph style DOT");
}

// ---- F9: markdown, <br>, entities ----

void test_rich_labels() {
    string src = "flowchart TD\n    A[\"Line1<br>Line2<br/>3\"] --> B[\"He said #quot;hi#quot; #9829;\"]\n    B --> C[\"`**Bold** and _it_`\"]\n    C --> D[\"a < b & c > d\"]\n    D -->|\"`**e**`\"| E[\"<b>x</i>\"]\n";
    string dot = dot_of(src);
    check(dot.contains("A [label=<Line1<BR/>Line2<BR/>3>"), "<br> line breaks");
    check(dot.contains("B [label=\"He said \\\"hi\\\" ♥\""), "entity codes decoded");
    check(dot.contains("C [label=<<B>Bold</B> and <I>it</I>>"), "markdown string");
    check(dot.contains("D [label=\"a < b & c > d\""), "plain text with < & > stays plain");
    check(dot.contains("label=<<B>e</B>>"), "markdown edge label");
    check(dot.contains("E [label=<<B>x</B>>"), "unbalanced tags repaired");
    check(svg_of(src) != null, "rich labels render");
}

// ---- headers ----

void test_graph_header() {
    var d = flow("graph LR\n    A --> B\n");
    check(!d.has_errors() && d.edges.size == 1, "graph LR header");
    check(d.direction == FlowchartDirection.LEFT_RIGHT, "graph direction");
    var f = flow("---\ntitle: My Flow\n---\nflowchart TD\n    A --> B\n");
    check(!f.has_errors() && f.edges.size == 1, "frontmatter skipped");
    check_str(f.title, "My Flow", "frontmatter title");
}

int main(string[] args) {
    Test.init(ref args);
    Test.set_nonfatal_assertions();
    Test.add_func("/review/mermaid/lexer_emoji_kept", test_lexer_emoji_kept);
    Test.add_func("/review/mermaid/lexer_apostrophe", test_lexer_apostrophe);
    Test.add_func("/review/mermaid/lexer_text_range", test_lexer_text_range);
    Test.add_func("/review/mermaid/lexer_entities", test_lexer_entities);
    Test.add_func("/review/mermaid/flowchart_label_text", test_flowchart_label_text);
    Test.add_func("/review/mermaid/class_suffix", test_class_suffix);
    Test.add_func("/review/mermaid/link_text", test_link_text);
    Test.add_func("/review/mermaid/subgraph_edge", test_subgraph_edge);
    Test.add_func("/review/mermaid/shape_data", test_shape_data);
    Test.add_func("/review/mermaid/circle_cross_ends", test_circle_cross_ends);
    Test.add_func("/review/mermaid/bidirectional", test_bidirectional);
    Test.add_func("/review/mermaid/bracket_shapes", test_bracket_shapes);
    Test.add_func("/review/mermaid/link_style_subgraph_style", test_link_style_and_subgraph_style);
    Test.add_func("/review/mermaid/rich_labels", test_rich_labels);
    Test.add_func("/review/mermaid/graph_header", test_graph_header);
    return Test.run();
}
