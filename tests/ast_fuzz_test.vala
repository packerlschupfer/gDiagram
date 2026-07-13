/*
 * ast_fuzz_test.vala — feed renderers hand-built AST objects with
 * adversarial labels and empty collections to exercise the DOT
 * escaping and defensive edge cases without going through parsers.
 *
 * The previous snapshot/fuzz tests all drove the renderers via
 * source text → parser → AST → DOT. That covers the happy path, but
 * a parser bug could mask a renderer bug by filtering out weird
 * labels before they reach escape_label(). Building the AST by hand
 * lets us inject labels like `"` (bare quote), `\` (backslash),
 * `\n` (newline), `{` (brace), empty strings, and multi-line
 * unicode directly into the DOT output.
 *
 * Each test calls generate_dot() and asserts:
 *   1. The call returned (no crash, no hang)
 *   2. The output is non-null
 *   3. The output contains `digraph` or `graph` (basic sanity)
 *   4. For select cases, that a known-safe substring appears
 */
using GDiagram;

void assert_dot_well_formed(string label, string dot) {
    if (dot == null || dot.length == 0) {
        stderr.printf("[%s] DOT output is null/empty\n", label);
        assert_not_reached();
    }
    if (!dot.contains("digraph") && !dot.contains("graph")) {
        stderr.printf("[%s] DOT missing graph header\n", label);
        assert_not_reached();
    }
    // Count unescaped quotes. Inside DOT string literals quotes must
    // be escaped as \". If we see an odd number of raw quotes that
    // aren't preceded by a backslash, DOT would fail to parse.
    int unescaped = 0;
    for (int i = 0; i < dot.length; i++) {
        if (dot[i] == '"' && (i == 0 || dot[i - 1] != '\\')) {
            unescaped++;
        }
    }
    if (unescaped % 2 != 0) {
        stderr.printf("[%s] odd number of unescaped quotes in DOT: %d\n",
            label, unescaped);
        stderr.printf("---- DOT ----\n%s\n---- end ----\n", dot);
        assert_not_reached();
    }
}

// =====================================================================
// Class diagram renderer
// =====================================================================

ClassDiagramRenderer make_class_renderer() {
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    return new ClassDiagramRenderer(ctx, regions, "dot");
}

void test_class_empty_diagram() {
    var diagram = new ClassDiagram();
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_empty", dot);
}

void test_class_label_with_quote() {
    var diagram = new ClassDiagram();
    var c = new UmlClass("Foo\"Bar");
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_quote_in_name", dot);
}

void test_class_label_with_backslash() {
    var diagram = new ClassDiagram();
    var c = new UmlClass("Foo\\Bar\\Baz");
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_backslash", dot);
}

void test_class_label_with_newline() {
    var diagram = new ClassDiagram();
    var c = new UmlClass("Line1\nLine2\nLine3");
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_newline", dot);
}

void test_class_label_with_dot_metachars() {
    var diagram = new ClassDiagram();
    var c = new UmlClass("A; { B } -> C");
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_dot_metachars", dot);
}

void test_class_label_unicode() {
    var diagram = new ClassDiagram();
    var c = new UmlClass("日本語");
    var member = new ClassMember("メソッド", true);
    member.type_name = "int";
    c.add_member(member);
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_unicode", dot);
    assert(dot.contains("日本語"));
}

void test_class_member_name_with_quote() {
    var diagram = new ClassDiagram();
    var c = new UmlClass("Foo");
    var member = new ClassMember("broken\"field");
    c.add_member(member);
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_member_quote", dot);
}

void test_class_relationship_with_null_label() {
    var diagram = new ClassDiagram();
    var a = new UmlClass("A");
    var b = new UmlClass("B");
    diagram.classes.add(a);
    diagram.classes.add(b);
    var rel = new ClassRelationship(a, b, RelationshipType.ASSOCIATION);
    // label is already null by default — assert that the renderer
    // doesn't crash on null label/cardinality fields.
    diagram.relationships.add(rel);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_null_label", dot);
}

void test_class_relationship_label_with_quote() {
    var diagram = new ClassDiagram();
    var a = new UmlClass("A");
    var b = new UmlClass("B");
    diagram.classes.add(a);
    diagram.classes.add(b);
    var rel = new ClassRelationship(a, b, RelationshipType.ASSOCIATION);
    rel.label = "uses \"quoted\" stuff";
    diagram.relationships.add(rel);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_rel_label_quote", dot);
}

void test_class_huge_diagram() {
    var diagram = new ClassDiagram();
    for (int i = 0; i < 500; i++) {
        var c = new UmlClass("C%d".printf(i));
        for (int m = 0; m < 5; m++) {
            c.add_member(new ClassMember("field%d".printf(m)));
        }
        diagram.classes.add(c);
    }
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_huge", dot);
    assert(dot.contains("C0"));
    assert(dot.contains("C499"));
}

void test_class_title_with_metachars() {
    var diagram = new ClassDiagram();
    diagram.title = "Title with \"quotes\" and \\ backslash";
    var c = new UmlClass("Foo");
    diagram.classes.add(c);
    string dot = make_class_renderer().generate_dot(diagram);
    assert_dot_well_formed("class_title_meta", dot);
}

// =====================================================================
// Component diagram renderer (C4)
// =====================================================================

ComponentDiagramRenderer make_component_renderer() {
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    return new ComponentDiagramRenderer(ctx, regions, "dot");
}

void test_component_empty() {
    var diagram = new ComponentDiagram();
    string dot = make_component_renderer().generate_dot(diagram);
    assert_dot_well_formed("component_empty", dot);
}

void test_component_label_with_quote() {
    var diagram = new ComponentDiagram();
    var comp = new Component("foo\"bar", ComponentType.RECTANGLE);
    comp.label = "Tricky \"label\"";
    comp.stereotype = "container";
    diagram.components.add(comp);
    string dot = make_component_renderer().generate_dot(diagram);
    assert_dot_well_formed("component_label_quote", dot);
}

void test_component_null_stereotype() {
    var diagram = new ComponentDiagram();
    var comp = new Component("foo", ComponentType.RECTANGLE);
    // stereotype is null by default — the C4 code path checks for it
    diagram.components.add(comp);
    string dot = make_component_renderer().generate_dot(diagram);
    assert_dot_well_formed("component_null_stereo", dot);
}

// =====================================================================
// ER diagram renderer
// =====================================================================

ERDiagramRenderer make_er_renderer() {
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    return new ERDiagramRenderer(ctx, regions, "dot");
}

void test_er_empty() {
    var diagram = new ERDiagram();
    string dot = make_er_renderer().generate_dot(diagram);
    assert_dot_well_formed("er_empty", dot);
}

void test_er_entity_with_record_chars() {
    var diagram = new ERDiagram();
    var entity = new EREntity("Table");
    // Record labels use < > { } | as structural chars — attribute
    // text containing them must be escaped. escape_record_label
    // handles this.
    var attr = new ERAttribute("weird<field>{name}|pipe", null, 0);
    entity.attributes.add(attr);
    diagram.entities.add(entity);
    string dot = make_er_renderer().generate_dot(diagram);
    assert_dot_well_formed("er_record_chars", dot);
}

// =====================================================================
// State diagram renderer
// =====================================================================

StateDiagramRenderer make_state_renderer() {
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    return new StateDiagramRenderer(ctx, regions, "dot");
}

void test_state_empty() {
    var diagram = new StateDiagram();
    string dot = make_state_renderer().generate_dot(diagram);
    assert_dot_well_formed("state_empty", dot);
}

void test_state_transition_label_with_newline() {
    var diagram = new StateDiagram();
    var s1 = new State("Idle");
    var s2 = new State("Running");
    diagram.states.add(s1);
    diagram.states.add(s2);
    var t = new StateTransition(s1, s2);
    t.label = "multi\nline\nevent";
    diagram.transitions.add(t);
    string dot = make_state_renderer().generate_dot(diagram);
    assert_dot_well_formed("state_trans_newline", dot);
}

// =====================================================================
// Activity diagram renderer
// =====================================================================

ActivityDiagramRenderer make_activity_renderer() {
    var ctx = new Gvc.Context();
    var regions = new Gee.ArrayList<ElementRegion>();
    return new ActivityDiagramRenderer(ctx, regions, "dot");
}

void test_activity_empty() {
    var diagram = new ActivityDiagram();
    string dot = make_activity_renderer().generate_dot(diagram);
    assert_dot_well_formed("activity_empty", dot);
}

void test_activity_action_with_metachars() {
    var diagram = new ActivityDiagram();
    var node = new ActivityNode(
        ActivityNodeType.ACTION,
        "Process { data } ; return -> result"
    );
    diagram.nodes.add(node);
    string dot = make_activity_renderer().generate_dot(diagram);
    assert_dot_well_formed("activity_metachars", dot);
}

// =====================================================================
// Entry point
// =====================================================================

int main(string[] args) {
    Test.init(ref args);

    // Class
    Test.add_func("/ast/class/empty",                    test_class_empty_diagram);
    Test.add_func("/ast/class/label_quote",              test_class_label_with_quote);
    Test.add_func("/ast/class/label_backslash",          test_class_label_with_backslash);
    Test.add_func("/ast/class/label_newline",            test_class_label_with_newline);
    Test.add_func("/ast/class/label_dot_metachars",      test_class_label_with_dot_metachars);
    Test.add_func("/ast/class/label_unicode",            test_class_label_unicode);
    Test.add_func("/ast/class/member_quote",             test_class_member_name_with_quote);
    Test.add_func("/ast/class/rel_null_label",           test_class_relationship_with_null_label);
    Test.add_func("/ast/class/rel_label_quote",          test_class_relationship_label_with_quote);
    Test.add_func("/ast/class/huge",                     test_class_huge_diagram);
    Test.add_func("/ast/class/title_meta",               test_class_title_with_metachars);

    // Component (C4)
    Test.add_func("/ast/component/empty",                test_component_empty);
    Test.add_func("/ast/component/label_quote",          test_component_label_with_quote);
    Test.add_func("/ast/component/null_stereotype",      test_component_null_stereotype);

    // ER
    Test.add_func("/ast/er/empty",                       test_er_empty);
    Test.add_func("/ast/er/record_chars",                test_er_entity_with_record_chars);

    // State
    Test.add_func("/ast/state/empty",                    test_state_empty);
    Test.add_func("/ast/state/trans_newline",            test_state_transition_label_with_newline);

    // Activity
    Test.add_func("/ast/activity/empty",                 test_activity_empty);
    Test.add_func("/ast/activity/metachars",             test_activity_action_with_metachars);

    return Test.run();
}
