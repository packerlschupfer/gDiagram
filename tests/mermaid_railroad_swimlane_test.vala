/*
 * mermaid_railroad_swimlane_test.vala — Mermaid `railroad-beta` (plus its
 * -ebnf/-abnf/-peg grammar front ends) and `swimlane-beta`.
 *
 * Every grammar rule asserted here was transcribed from mermaid 12.2.0's own
 * serialised Langium grammar and checked against `mmdc` 12.2.0 as an
 * accept/reject oracle, so these tests pin mermaid's behaviour, not a guess:
 *
 *   - all four rules end with ";" (mmdc: "Expecting token of type ';'")
 *   - ABNF's ";" is BOTH the rule terminator and the comment opener; the
 *     longest lexer match wins, so ";" at the end of a line terminates and
 *     ";" with text after it comments the rest out
 *   - PEG has no character classes: "[0-9]" is a lexer error in mmdc
 *   - a special sequence is drawn as "? text ?" exactly once
 *   - mermaid's renderer ignores a repetition's max; only min == 0 adds a bypass
 *   - `swimlane-beta` is lexed to the same GRAPH token as `flowchart`, so the
 *     grammar is the flowchart's and the lanes are the top-level subgraphs
 *
 * Snapshot tests go through DiagramEngine.generate_dot(src, "test.mmd", null):
 * the ".mmd" matters, because the filename extension picks the format before
 * the content does and a ".puml" name would route Mermaid source to the
 * PlantUML parser.
 */
using GDiagram;

namespace MermaidRailroadSwimlaneTests {

    static DiagramEngine? shared_engine = null;

    DiagramEngine engine() {
        if (shared_engine == null) {
            shared_engine = new DiagramEngine("dot");
        }
        return shared_engine;
    }

    string dot_of(string source) {
        string? dot = engine().generate_dot(source, "test.mmd", null);
        if (dot == null) {
            printerr("\nFAILED: generate_dot returned null for:\n%s\n", source);
            assert_not_reached();
        }
        return dot;
    }

    MermaidRailroad parse_rr(string source) {
        return new MermaidRailroadParser().parse(source);
    }

    void assert_clean(MermaidRailroad d, string source) {
        if (d.has_errors()) {
            printerr("\nFAILED: parse errors for:\n%s\n  first: %s\n",
                     source, d.errors[0].to_string());
            assert_not_reached();
        }
    }

    // Every terminal/nonterminal/special label in a rule, in document order.
    void collect(MermaidRailroadNode n, Gee.ArrayList<string> into) {
        switch (n.node_type) {
            case MermaidRailroadNodeType.TERMINAL:    into.add("T:" + n.text); break;
            case MermaidRailroadNodeType.NONTERMINAL: into.add("N:" + n.text); break;
            case MermaidRailroadNodeType.SPECIAL:     into.add("S:" + n.text); break;
            case MermaidRailroadNodeType.OPTIONAL:    into.add("opt"); break;
            case MermaidRailroadNodeType.REPETITION:
                into.add("rep%d".printf(n.min)); break;
            case MermaidRailroadNodeType.SEQUENCE:    into.add("seq"); break;
            case MermaidRailroadNodeType.CHOICE:      into.add("alt"); break;
        }
        foreach (var c in n.children) collect(c, into);
    }

    string shape_of(MermaidRailroadRule r) {
        var list = new Gee.ArrayList<string>();
        collect(r.definition, list);
        return string.joinv(" ", list.to_array());
    }

    // ════════════════════════ detection ════════════════════════

    // All four keywords must reach ONE diagram type. They share an AST and a
    // renderer; only the grammar that read them differs.
    void test_all_four_keywords_detect() {
        string[] sources = {
            "railroad-beta\na = terminal(\"x\");",
            "railroad-ebnf-beta\na = \"x\";",
            "railroad-abnf-beta\na = \"x\";",
            "railroad-peg-beta\na <- \"x\";"
        };
        MermaidRailroadGrammar[] grammars = {
            MermaidRailroadGrammar.NATIVE, MermaidRailroadGrammar.EBNF,
            MermaidRailroadGrammar.ABNF, MermaidRailroadGrammar.PEG
        };
        for (int i = 0; i < sources.length; i++) {
            assert(TypeDetector.is_mermaid(sources[i]));
            var t = TypeDetector.detect_mermaid(sources[i]);
            if (t != DiagramType.MERMAID_RAILROAD) {
                printerr("\nFAILED: %s detected as %d, not MERMAID_RAILROAD\n",
                         sources[i].split("\n")[0], (int) t);
                assert_not_reached();
            }
            var d = parse_rr(sources[i]);
            assert_clean(d, sources[i]);
            assert(d.grammar == grammars[i]);
            assert(d.rules.size == 1);
        }
    }

    // Mermaid's detectors are case-insensitive (/^\s*railroad-beta/i).
    void test_keyword_is_case_insensitive_and_indented() {
        string src = "   RailRoad-Beta\na = terminal(\"x\");";
        assert(TypeDetector.detect_mermaid(src) == DiagramType.MERMAID_RAILROAD);
        var d = parse_rr(src);
        assert_clean(d, src);
        assert(d.rules.size == 1);
    }

    void test_swimlane_detects_and_is_not_a_flowchart() {
        string src = "swimlane-beta LR\n  subgraph A\n    X --> Y\n  end";
        assert(TypeDetector.is_mermaid(src));
        var t = TypeDetector.detect_mermaid(src);
        if (t != DiagramType.MERMAID_SWIMLANE) {
            printerr("\nFAILED: swimlane-beta detected as %d\n", (int) t);
            assert_not_reached();
        }
        // ... and a real flowchart must NOT become a swimlane
        assert(TypeDetector.detect_mermaid("flowchart LR\n  X --> Y") ==
               DiagramType.MERMAID_FLOWCHART);
    }

    // ════════════════════════ native grammar ════════════════════════

    void test_native_constructors() {
        string src = "railroad-beta\n" +
            "title Native\n" +
            "g = sequence(terminal(\"hi\"), optional(nonterminal(\"n\")), " +
            "zeroOrMore(terminal(\",\")), oneOrMore(special(\"digit\")), " +
            "choice(terminal(\"a\"), terminal(\"b\")));";
        var d = parse_rr(src);
        assert_clean(d, src);
        assert(d.title == "Native");
        assert(d.rules.size == 1);
        assert(shape_of(d.rules[0]) ==
            "seq T:hi opt N:n rep0 T:, rep1 S:digit alt T:a T:b");
    }

    // Mermaid collapses a one-element sequence/choice into that element
    // (`elements.length === 1 ? elements[0] : {...}`).
    void test_native_single_element_collapses() {
        var d = parse_rr("railroad-beta\na = sequence(terminal(\"x\"));\n" +
                         "b = choice(nonterminal(\"y\"));");
        assert(!d.has_errors());
        assert(shape_of(d.rules[0]) == "T:x");
        assert(shape_of(d.rules[1]) == "N:y");
    }

    void test_native_rejects_bare_terminal() {
        // mermaid's Railroad grammar has no bare strings: every expression is a
        // constructor call.
        var d = parse_rr("railroad-beta\na = \"x\";");
        assert(d.has_errors());
    }

    // ════════════════════════ EBNF grammar ════════════════════════

    void test_ebnf_operators() {
        string src = "railroad-ebnf-beta\n" +
            "a = \"x\" | \"y\";\n" +
            "b ::= c, { d };\n" +
            "e = [ \"-\" ] f;\n" +
            "g = h ( i | j )*;\n" +
            "k = ? any letter ?;\n" +
            "l = m+;\n" +
            "n = o?;";
        var d = parse_rr(src);
        assert_clean(d, src);
        assert(shape_of(d.rules[0]) == "alt T:x T:y");
        assert(shape_of(d.rules[1]) == "seq N:c rep0 N:d");     // { d } is zero-or-more
        assert(shape_of(d.rules[2]) == "seq opt T:- N:f");       // [ - ] is optional
        assert(shape_of(d.rules[3]) == "seq N:h rep0 alt N:i N:j");
        assert(shape_of(d.rules[4]) == "S:any letter");          // "?" stripped and trimmed
        assert(shape_of(d.rules[5]) == "rep1 N:m");
        assert(shape_of(d.rules[6]) == "opt N:o");
    }

    // EbnfExceptionPostfix: mermaid flattens "a - b" into [a, terminal("-"), b]
    // rather than modelling an exception node.
    void test_ebnf_exception_flattens_to_sequence() {
        var d = parse_rr("railroad-ebnf-beta\na = b - \"end\";");
        assert(!d.has_errors());
        assert(shape_of(d.rules[0]) == "seq N:b T:- T:end");
    }

    // The comma between terms is optional, so juxtaposition concatenates.
    void test_ebnf_comma_is_optional() {
        var a = parse_rr("railroad-ebnf-beta\nr = b, c, d;");
        var b = parse_rr("railroad-ebnf-beta\nr = b c d;");
        assert(!a.has_errors() && !b.has_errors());
        assert(shape_of(a.rules[0]) == shape_of(b.rules[0]));
        assert(shape_of(a.rules[0]) == "seq N:b N:c N:d");
    }

    // ════════════════════════ ABNF grammar ════════════════════════

    void test_abnf_repeat_forms() {
        string src = "railroad-abnf-beta\n" +
            "a = 1*DIGIT;\n" +
            "b = *DIGIT;\n" +
            "c = 3DIGIT;\n" +
            "d = 2*4ALPHA;\n" +
            "e = [ \"+\" ] DIGIT;\n" +
            "f = %x41-5A / %x61-7A;\n" +
            "g = ( A / B ) C;";
        var d = parse_rr(src);
        assert_clean(d, src);
        assert(shape_of(d.rules[0]) == "rep1 N:DIGIT");
        assert(shape_of(d.rules[1]) == "rep0 N:DIGIT");
        assert(shape_of(d.rules[2]) == "rep3 N:DIGIT");
        assert(shape_of(d.rules[3]) == "rep2 N:ALPHA");
        assert(shape_of(d.rules[4]) == "seq opt T:+ N:DIGIT");
        assert(shape_of(d.rules[5]) == "alt T:%x41-5A T:%x61-7A");
        assert(shape_of(d.rules[6]) == "seq alt N:A N:B N:C");
    }

    // A bounded repeat keeps both bounds in the AST even though mermaid's
    // renderer only ever looks at min.
    void test_abnf_repeat_bounds_are_kept() {
        var d = parse_rr("railroad-abnf-beta\nd = 2*4ALPHA;\ne = 3DIGIT;\nf = *A;");
        assert(!d.has_errors());
        assert(d.rules[0].definition.min == 2 && d.rules[0].definition.max == 4);
        assert(d.rules[1].definition.min == 3 && d.rules[1].definition.max == 3);
        assert(d.rules[2].definition.min == 0 && d.rules[2].definition.max == -1);
    }

    // "0*1X" is min 0 max 1, which mermaid turns into an optional, not a loop.
    void test_abnf_zero_or_one_becomes_optional() {
        var d = parse_rr("railroad-abnf-beta\na = 0*1DIGIT;");
        assert(!d.has_errors());
        assert(shape_of(d.rules[0]) == "opt N:DIGIT");
    }

    /*
     * The ABNF lexer quirk, straight from mmdc:
     *   "a = X;"              -> ";" terminates the rule        (accepted)
     *   "a = X; comment"      -> ABNF_COMMENT eats ";" and the  (rejected: the
     *                            rest of the line, so the rule   next rule's "="
     *                            never terminates                is unexpected)
     * ABNF_COMMENT matches ";" followed by the rest of the line and competes
     * with the ";" keyword; the longest match wins and a tie goes to the keyword.
     */
    void test_abnf_semicolon_terminates_only_at_end_of_line() {
        var ok = parse_rr("railroad-abnf-beta\na = \"x\" ;\nb = \"y\";");
        assert_clean(ok, "abnf trailing-space semicolon");
        assert(ok.rules.size == 2);

        var swallowed = parse_rr("railroad-abnf-beta\na = \"x\"; trailing words\nb = \"y\";");
        assert(swallowed.has_errors());

        var leading_comment = parse_rr("railroad-abnf-beta\n; a comment\na = \"x\";");
        assert_clean(leading_comment, "abnf leading comment");
        assert(leading_comment.rules.size == 1);
    }

    // ABNF rule names may not contain "_" (ABNF_RULENAME is /[A-Za-z][A-Za-z0-9-]*/),
    // unlike the ID of the other three flavours.
    void test_abnf_rulename_charset() {
        var dashed = parse_rr("railroad-abnf-beta\nrequest-line = \"x\";");
        assert(!dashed.has_errors());
        assert(dashed.rules[0].name == "request-line");
    }

    // ════════════════════════ PEG grammar ════════════════════════

    void test_peg_operators() {
        string src = "railroad-peg-beta\n" +
            "A <- B (\"+\" B)*;\n" +
            "C <- D+;\n" +
            "E <- F?;\n" +
            "G <- \"(\" A \")\" / H;\n" +
            "I <- .;";
        var d = parse_rr(src);
        assert_clean(d, src);
        assert(shape_of(d.rules[0]) == "seq N:B rep0 seq T:+ N:B");
        assert(shape_of(d.rules[1]) == "rep1 N:D");
        assert(shape_of(d.rules[2]) == "opt N:F");
        assert(shape_of(d.rules[3]) == "alt seq T:( N:A T:) N:H");
        assert(shape_of(d.rules[4]) == "S:.");
    }

    // Lookahead becomes a special node labelled with mermaid's nodeToLabel():
    // a terminal is re-quoted, a nonterminal is bare.
    void test_peg_lookahead_becomes_special() {
        var d = parse_rr("railroad-peg-beta\nA <- &\"a\" \"ab\";\nB <- !C D;");
        assert(!d.has_errors());
        assert(shape_of(d.rules[0]) == "seq S:&\"a\" T:ab");
        assert(shape_of(d.rules[1]) == "seq S:!C N:D");
    }

    // mmdc rejects "[0-9]": PegPrimary is literal / identifier / group / "." only.
    void test_peg_rejects_character_class() {
        var d = parse_rr("railroad-peg-beta\nNumber <- [0-9]+;");
        assert(d.has_errors());
    }

    void test_peg_requires_arrow() {
        assert(parse_rr("railroad-peg-beta\nA = \"x\";").has_errors());
        assert(!parse_rr("railroad-peg-beta\nA <- \"x\";").has_errors());
    }

    // ════════════════════════ shared grammar rules ════════════════════════

    // mmdc on a rule without ";": "Expecting token of type ';' but found `=`".
    void test_every_flavour_requires_the_semicolon() {
        assert(parse_rr("railroad-beta\na = terminal(\"x\")\nb = terminal(\"y\");").has_errors());
        assert(parse_rr("railroad-ebnf-beta\na = \"x\"\nb = \"y\";").has_errors());
        assert(parse_rr("railroad-abnf-beta\na = \"x\"\nb = \"y\";").has_errors());
        assert(parse_rr("railroad-peg-beta\na <- \"x\"\nb <- \"y\";").has_errors());
    }

    void test_comments_and_directives_are_hidden() {
        string src = "---\ntitle: front matter\n---\n" +
            "railroad-ebnf-beta\n" +
            "%%{init: {\"theme\": \"dark\"}}%%\n" +
            "%% a line comment\n" +
            "(* an ISO comment *)\n" +
            "/* a block comment */\n" +
            "a = \"x\";";
        var d = parse_rr(src);
        assert_clean(d, src);
        assert(d.rules.size == 1);
        assert(shape_of(d.rules[0]) == "T:x");
    }

    void test_rules_carry_their_source_line() {
        string src = "railroad-beta\n\na = terminal(\"x\");\n\nb = terminal(\"y\");";
        var d = parse_rr(src);
        assert(!d.has_errors());
        assert(d.rules[0].source_line == 3);
        assert(d.rules[1].source_line == 5);
    }

    /*
     * Progress guard: a parser that rewinds without consuming spins at 100% CPU
     * and no assertion ever fires. These inputs are the shapes that would do it
     * — unterminated groups, a stray operator, a rule that never closes — and
     * the test simply has to RETURN.
     */
    void test_malformed_input_always_terminates() {
        string[] nasty = {
            "railroad-beta\na = sequence(",
            "railroad-beta\na = sequence(terminal(\"x\"),,,,,);",
            "railroad-beta\n((((((((((",
            "railroad-ebnf-beta\na = ( ( ( ( (;",
            "railroad-ebnf-beta\na = | | | | ;",
            "railroad-ebnf-beta\na = { { { ;",
            "railroad-ebnf-beta\na = ?unterminated special;",
            "railroad-abnf-beta\na = ( ( ( ;",
            "railroad-abnf-beta\na = ///// ;",
            "railroad-abnf-beta\na = %zz;",
            "railroad-abnf-beta\na = \"unterminated;",
            "railroad-peg-beta\nA <- ((((;",
            "railroad-peg-beta\nA <- &&&&&;",
            "railroad-peg-beta\nA <- / / / ;",
            "railroad-peg-beta\n;;;;;;;;;;",
            "railroad-beta\n=;=;=;=;=;=;=;",
            "railroad-beta\n"
        };
        foreach (string s in nasty) {
            var d = parse_rr(s);
            // No assertion on the outcome: reaching this line at all is the test.
            assert(d.rules.size >= 0);
        }
    }

    // A long but valid file must not hit a guard and silently drop rules.
    void test_many_rules_all_parse() {
        var sb = new StringBuilder("railroad-ebnf-beta\n");
        for (int i = 0; i < 400; i++) {
            sb.append_printf("r%d = \"a\" | \"b\", { c%d };\n", i, i);
        }
        var d = parse_rr(sb.str);
        assert_clean(d, "400 generated rules");
        assert(d.rules.size == 400);
    }

    // ════════════════════════ railroad rendering ════════════════════════

    // The engine must route all four keywords to the railroad renderer and the
    // DOT must be the pinned kind (layout=nop2), not a Graphviz-laid-out graph.
    void test_railroad_dot_is_pinned_for_every_flavour() {
        string[] sources = {
            "railroad-beta\ng = sequence(terminal(\"hi\"), nonterminal(\"n\"));",
            "railroad-ebnf-beta\ng = \"hi\", n;",
            "railroad-abnf-beta\ng = \"hi\" n;",
            "railroad-peg-beta\ng <- \"hi\" n;"
        };
        foreach (string src in sources) {
            string dot = dot_of(src);
            assert(dot.contains("layout=nop2"));
            assert(dot.contains("hi"));
            // The rule name is drawn as "g =", the way mermaid's renderRule does
            assert(dot.contains("g ="));
            // Start and end markers are filled circles
            assert(dot.contains("shape=circle"));
        }
    }

    // Mermaid inverts PlantUML's convention: a terminal is the ROUNDED box
    // (fill #FFFFC0) and a non-terminal the square one (fill #FFFFFF).
    void test_terminal_is_rounded_and_nonterminal_square() {
        string dot = dot_of("railroad-beta\ng = sequence(terminal(\"t\"), nonterminal(\"n\"));");
        assert(dot.contains("#FFFFC0"));
        assert(dot.contains("rounded,filled"));
        assert(dot.contains("#FFFFFF"));
        // the special box carries mermaid's purple
        string sdot = dot_of("railroad-beta\ng = special(\"s\");");
        assert(sdot.contains("#F0E0FF"));
        assert(sdot.contains("#8800CC"));
    }

    // renderSpecial draws "? text ?" — exactly one pair of question marks,
    // whether the text came from special(...) or from an EBNF "? ... ?".
    void test_special_is_wrapped_once() {
        string a = dot_of("railroad-beta\ng = special(\"any id\");");
        assert(a.contains("? any id ?"));
        assert(!a.contains("? ? any id ? ?"));
        string b = dot_of("railroad-ebnf-beta\ng = ? any id ?;");
        assert(b.contains("? any id ?"));
        assert(!b.contains("? ? any id ? ?"));
    }

    /*
     * Every number written into DOT must be C-formatted. A German desktop
     * rendered "nodesep=0,8333" and Graphviz refused the graph with "syntax
     * error near ','" — while the headless CLI on the same machine was fine,
     * because it never calls setlocale().
     *
     * Asserting byte equality between the two locales beats grepping for a
     * comma: a railroad DOT is full of legitimate commas (pos="x,y"), and a
     * regex loose enough to catch "0,8333" also matches "...8,0".
     */
    string? dot_in_comma_locale(string source, out string used) {
        used = "";
        string? had = Intl.setlocale(LocaleCategory.NUMERIC, null);
        string? found = null;
        foreach (string cand in new string[] { "de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8" }) {
            if (Intl.setlocale(LocaleCategory.NUMERIC, cand) != null) { found = cand; break; }
        }
        if (found == null) {
            Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");
            return null;
        }
        // Prove the locale really is comma-decimal before trusting the result;
        // a locale that exists but formats like C would make this test vacuous.
        // string.printf("%.1f") follows LC_NUMERIC, unlike g_ascii_formatd.
        string probe = "%.1f".printf(0.5);
        string dot = dot_of(source);
        Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");
        if (!probe.contains(",")) {
            printerr("\nlocale %s is not comma-decimal (%%.1f gave %s)\n", found, probe);
            return null;
        }
        used = found;
        return dot;
    }

    void assert_locale_independent(string source) {
        string used;
        string? comma_dot = dot_in_comma_locale(source, out used);
        if (comma_dot == null) {
            Test.skip("no comma-decimal locale installed; cannot prove the locale guard here");
            return;
        }
        string c_dot = dot_of(source);
        if (comma_dot != c_dot) {
            printerr("\nFAILED: the DOT differs between C and %s\n--- C ---\n%s\n--- %s ---\n%s\n",
                     used, c_dot, used, comma_dot);
            assert_not_reached();
        }
        assert(c_dot.length > 0);
    }

    void test_railroad_dot_is_locale_independent() {
        assert_locale_independent("railroad-beta\ng = sequence(terminal(\"hi\"), " +
            "optional(nonterminal(\"n\")), oneOrMore(terminal(\",\")));");
    }

    void test_railroad_svg_round_trip() {
        string path = Path.build_filename(Environment.get_tmp_dir(),
            "gdiagram-rr-%d.svg".printf(Random.int_range(0, 1 << 30)));
        assert(engine().export_to_svg(
            "railroad-beta\ng = sequence(terminal(\"hi\"), zeroOrMore(nonterminal(\"n\")));",
            "test.mmd", null, path));
        string svg;
        try {
            FileUtils.get_contents(path, out svg);
        } catch (FileError e) {
            error("%s", e.message);
        }
        FileUtils.unlink(path);
        assert(svg.contains("<svg"));
        assert(svg.contains("hi"));
        assert(svg.contains("g ="));
    }

    // ════════════════════════ swimlanes ════════════════════════

    string swimlane_src(string direction) {
        return "swimlane-beta " + direction + "\n" +
            "  subgraph Customer\n    A[Place order] --> B[Pay]\n  end\n" +
            "  subgraph Warehouse\n    C[Pick items] --> D[Ship]\n  end\n" +
            "  subgraph Carrier\n    E[Collect] --> F[Deliver]\n  end\n" +
            "  B --> C\n  D --> E\n";
    }

    // The swimlane source is parsed by the FLOWCHART parser (mermaid reuses it
    // wholesale) and its lanes are the top-level subgraphs.
    void test_swimlane_parses_as_a_flowchart() {
        var d = new MermaidFlowchartParser().parse(swimlane_src("LR"));
        if (d.has_errors()) {
            printerr("\nFAILED: %s\n", d.errors[0].to_string());
            assert_not_reached();
        }
        assert(d.nodes.size == 6);
        assert(d.subgraphs.size == 3);
        assert(d.subgraphs[0].id == "Customer");
        assert(d.subgraphs[1].id == "Warehouse");
        assert(d.subgraphs[2].id == "Carrier");
        assert(d.direction == FlowchartDirection.LEFT_RIGHT);
    }

    // The lane layout is pinned by the renderer, because Graphviz's crossing
    // minimisation will not keep the author's lane order.
    void test_swimlane_dot_is_pinned_with_one_band_per_lane() {
        string dot = dot_of(swimlane_src("LR"));
        assert(dot.contains("layout=nop2"));
        assert(dot.contains("lane_band_0"));
        assert(dot.contains("lane_band_1"));
        assert(dot.contains("lane_band_2"));
        assert(dot.contains("lane_name_0"));
        assert(!dot.contains("lane_band_3"));
        // Every node carries a position, or nop2 would stack them at the origin
        foreach (string id in new string[] { "A", "B", "C", "D", "E", "F" }) {
            if (!dot.contains("  %s [".printf(id))) {
                printerr("\nFAILED: node %s missing from the DOT\n", id);
                assert_not_reached();
            }
        }
        int poses = 0;
        int at = 0;
        while ((at = dot.index_of("pos=\"", at)) >= 0) { poses++; at += 5; }
        // 6 nodes + 3 bands + 3 lane names
        assert(poses >= 12);
    }

    /*
     * The point of the pinned layout: lane bands come out in DECLARATION order.
     * Left Graphviz to decide, this very graph put Carrier above Warehouse,
     * because mincross ignores inter-cluster flat edges under newrank.
     */
    void test_swimlane_lanes_keep_declaration_order() {
        // LR: lanes are rows, lane 0 at the top, so y descends with lane index
        string dot = dot_of(swimlane_src("LR"));
        double y0 = band_coord(dot, 0, false);
        double y1 = band_coord(dot, 1, false);
        double y2 = band_coord(dot, 2, false);
        if (!(y0 > y1 && y1 > y2)) {
            printerr("\nFAILED: LR lane order y0=%f y1=%f y2=%f (expected descending)\n",
                     y0, y1, y2);
            assert_not_reached();
        }

        // TB: lanes are columns, lane 0 at the left, so x ascends with lane index
        string tb = dot_of(swimlane_src("TB"));
        double x0 = band_coord(tb, 0, true);
        double x1 = band_coord(tb, 1, true);
        double x2 = band_coord(tb, 2, true);
        if (!(x0 < x1 && x1 < x2)) {
            printerr("\nFAILED: TB lane order x0=%f x1=%f x2=%f (expected ascending)\n",
                     x0, x1, x2);
            assert_not_reached();
        }
    }

    // Centre coordinate of lane_band_<n> from its pos="x,y"
    double band_coord(string dot, int n, bool want_x) {
        try {
            var re = new Regex("lane_band_%d \\[[^\\]]*pos=\"([-0-9.]+),([-0-9.]+)\"".printf(n));
            MatchInfo mi;
            if (!re.match(dot, 0, out mi)) {
                printerr("\nFAILED: no pos for lane_band_%d in:\n%s\n", n, dot);
                assert_not_reached();
            }
            return double.parse(mi.fetch(want_x ? 1 : 2));
        } catch (RegexError e) {
            assert_not_reached();
        }
    }

    // A node outside every lane must still be drawn, in a band of its own.
    void test_swimlane_keeps_unlaned_nodes() {
        string src = "swimlane-beta LR\n  Start[Begin] --> A\n" +
            "  subgraph Customer\n    A[Place order] --> B[Pay]\n  end\n" +
            "  B --> Done[Finish]\n";
        string dot = dot_of(src);
        assert(dot.contains("layout=nop2"));
        assert(dot.contains("Begin"));
        assert(dot.contains("Finish"));
        // one declared lane only
        assert(dot.contains("lane_band_0"));
        assert(!dot.contains("lane_band_1"));
    }

    // Without any lane the diagram is just a flowchart, and the renderer must
    // fall back to the ordinary Graphviz layout rather than pinning nothing.
    void test_swimlane_without_lanes_falls_back() {
        string dot = dot_of("swimlane-beta LR\n  A --> B\n");
        assert(!dot.contains("layout=nop2"));
        assert(!dot.contains("lane_band_"));
        assert(dot.contains("rankdir=LR"));
    }

    // The pinned swimlane layout writes a width, a height and a pos for every
    // band and every node, so it has far more numbers to get wrong than most.
    void test_swimlane_dot_is_locale_independent() {
        assert_locale_independent(swimlane_src("LR"));
    }

    void test_swimlane_svg_round_trip() {
        string path = Path.build_filename(Environment.get_tmp_dir(),
            "gdiagram-sw-%d.svg".printf(Random.int_range(0, 1 << 30)));
        assert(engine().export_to_svg(swimlane_src("LR"), "test.mmd", null, path));
        string svg;
        try {
            FileUtils.get_contents(path, out svg);
        } catch (FileError e) {
            error("%s", e.message);
        }
        FileUtils.unlink(path);
        assert(svg.contains("<svg"));
        assert(svg.contains("Place order"));
        assert(svg.contains("Customer"));
        assert(svg.contains("Carrier"));
    }

    // A plain flowchart must be unaffected by the swimlane work: no pinning,
    // no lane bands, clusters still drawn for its subgraphs.
    void test_plain_flowchart_is_unchanged() {
        string dot = dot_of("flowchart LR\n  subgraph S\n    A --> B\n  end\n  B --> C\n");
        assert(!dot.contains("layout=nop2"));
        assert(!dot.contains("lane_band_"));
        assert(dot.contains("subgraph cluster_0"));
    }

    // ════════════════════════ engine plumbing ════════════════════════

    void test_engine_parse_exposes_the_right_ast() {
        var rr = engine().parse("railroad-beta\na = terminal(\"x\");", "test.mmd");
        assert(rr.diagram_type == DiagramType.MERMAID_RAILROAD);
        assert(rr.ast is MermaidRailroad);
        assert(((MermaidRailroad) rr.ast).rules.size == 1);

        var sw = engine().parse(swimlane_src("LR"), "test.mmd");
        assert(sw.diagram_type == DiagramType.MERMAID_SWIMLANE);
        assert(sw.ast is MermaidFlowchart);
        assert(((MermaidFlowchart) sw.ast).subgraphs.size == 3);
    }

    void test_engine_renders_both_types() {
        var rr = engine().render(DiagramType.MERMAID_RAILROAD, DiagramFormat.MERMAID,
            "railroad-beta\na = sequence(terminal(\"x\"), nonterminal(\"y\"));");
        assert(rr.status == RenderStatus.OK);
        assert(rr.surface != null);

        var sw = engine().render(DiagramType.MERMAID_SWIMLANE, DiagramFormat.MERMAID,
            swimlane_src("LR"));
        assert(sw.status == RenderStatus.OK);
        assert(sw.surface != null);
    }

    // An empty document must offer the example, not an error.
    void test_empty_documents_are_reported_empty() {
        var rr = engine().render(DiagramType.MERMAID_RAILROAD, DiagramFormat.MERMAID,
            "railroad-beta\n");
        assert(rr.status == RenderStatus.EMPTY);
        assert(rr.message.contains("railroad-beta"));

        var sw = engine().render(DiagramType.MERMAID_SWIMLANE, DiagramFormat.MERMAID,
            "swimlane-beta LR\n");
        assert(sw.status == RenderStatus.EMPTY);
        assert(sw.message.contains("swimlane-beta"));
    }

    void test_png_and_pdf_export() {
        string stem = Path.build_filename(Environment.get_tmp_dir(),
            "gdiagram-rrsw-%d".printf(Random.int_range(0, 1 << 30)));
        string rr_src = "railroad-beta\na = sequence(terminal(\"x\"), oneOrMore(nonterminal(\"y\")));";

        assert(engine().export_to_png(rr_src, "test.mmd", null, stem + "-rr.png"));
        assert(FileUtils.test(stem + "-rr.png", FileTest.EXISTS));
        assert(engine().export_to_pdf(rr_src, "test.mmd", null, stem + "-rr.pdf"));
        assert(FileUtils.test(stem + "-rr.pdf", FileTest.EXISTS));

        assert(engine().export_to_png(swimlane_src("TB"), "test.mmd", null, stem + "-sw.png"));
        assert(FileUtils.test(stem + "-sw.png", FileTest.EXISTS));
        assert(engine().export_to_pdf(swimlane_src("TB"), "test.mmd", null, stem + "-sw.pdf"));
        assert(FileUtils.test(stem + "-sw.pdf", FileTest.EXISTS));

        foreach (string suffix in new string[] { "-rr.png", "-rr.pdf", "-sw.png", "-sw.pdf" }) {
            FileUtils.unlink(stem + suffix);
        }
    }

    // A parse error must surface as an error, not as a blank drawing.
    void test_parse_errors_reach_the_render_result() {
        var r = engine().render(DiagramType.MERMAID_RAILROAD, DiagramFormat.MERMAID,
            "railroad-peg-beta\nA <- [0-9];");
        assert(r.status == RenderStatus.PARSE_ERROR);
    }

    int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/railroad/all-four-keywords-detect", test_all_four_keywords_detect);
        Test.add_func("/railroad/keyword-case-insensitive", test_keyword_is_case_insensitive_and_indented);
        Test.add_func("/swimlane/detects-and-is-not-a-flowchart", test_swimlane_detects_and_is_not_a_flowchart);

        Test.add_func("/railroad/native-constructors", test_native_constructors);
        Test.add_func("/railroad/native-single-element-collapses", test_native_single_element_collapses);
        Test.add_func("/railroad/native-rejects-bare-terminal", test_native_rejects_bare_terminal);

        Test.add_func("/railroad/ebnf-operators", test_ebnf_operators);
        Test.add_func("/railroad/ebnf-exception-flattens", test_ebnf_exception_flattens_to_sequence);
        Test.add_func("/railroad/ebnf-comma-optional", test_ebnf_comma_is_optional);

        Test.add_func("/railroad/abnf-repeat-forms", test_abnf_repeat_forms);
        Test.add_func("/railroad/abnf-repeat-bounds-kept", test_abnf_repeat_bounds_are_kept);
        Test.add_func("/railroad/abnf-zero-or-one-optional", test_abnf_zero_or_one_becomes_optional);
        Test.add_func("/railroad/abnf-semicolon-quirk", test_abnf_semicolon_terminates_only_at_end_of_line);
        Test.add_func("/railroad/abnf-rulename-charset", test_abnf_rulename_charset);

        Test.add_func("/railroad/peg-operators", test_peg_operators);
        Test.add_func("/railroad/peg-lookahead-special", test_peg_lookahead_becomes_special);
        Test.add_func("/railroad/peg-rejects-character-class", test_peg_rejects_character_class);
        Test.add_func("/railroad/peg-requires-arrow", test_peg_requires_arrow);

        Test.add_func("/railroad/semicolon-required", test_every_flavour_requires_the_semicolon);
        Test.add_func("/railroad/comments-hidden", test_comments_and_directives_are_hidden);
        Test.add_func("/railroad/rules-carry-source-line", test_rules_carry_their_source_line);
        Test.add_func("/railroad/malformed-input-terminates", test_malformed_input_always_terminates);
        Test.add_func("/railroad/many-rules-all-parse", test_many_rules_all_parse);

        Test.add_func("/railroad/dot-is-pinned", test_railroad_dot_is_pinned_for_every_flavour);
        Test.add_func("/railroad/terminal-rounded-nonterminal-square", test_terminal_is_rounded_and_nonterminal_square);
        Test.add_func("/railroad/special-wrapped-once", test_special_is_wrapped_once);
        Test.add_func("/railroad/dot-locale-independent", test_railroad_dot_is_locale_independent);
        Test.add_func("/railroad/svg-round-trip", test_railroad_svg_round_trip);

        Test.add_func("/swimlane/parses-as-flowchart", test_swimlane_parses_as_a_flowchart);
        Test.add_func("/swimlane/dot-pinned-one-band-per-lane", test_swimlane_dot_is_pinned_with_one_band_per_lane);
        Test.add_func("/swimlane/lanes-keep-declaration-order", test_swimlane_lanes_keep_declaration_order);
        Test.add_func("/swimlane/keeps-unlaned-nodes", test_swimlane_keeps_unlaned_nodes);
        Test.add_func("/swimlane/without-lanes-falls-back", test_swimlane_without_lanes_falls_back);
        Test.add_func("/swimlane/dot-locale-independent", test_swimlane_dot_is_locale_independent);
        Test.add_func("/swimlane/svg-round-trip", test_swimlane_svg_round_trip);
        Test.add_func("/swimlane/plain-flowchart-unchanged", test_plain_flowchart_is_unchanged);

        Test.add_func("/railroad-swimlane/engine-parse-ast", test_engine_parse_exposes_the_right_ast);
        Test.add_func("/railroad-swimlane/engine-renders", test_engine_renders_both_types);
        Test.add_func("/railroad-swimlane/empty-documents", test_empty_documents_are_reported_empty);
        Test.add_func("/railroad-swimlane/png-pdf-export", test_png_and_pdf_export);
        Test.add_func("/railroad-swimlane/parse-errors-surface", test_parse_errors_reach_the_render_result);

        return Test.run();
    }
}
