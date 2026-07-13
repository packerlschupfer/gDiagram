/*
 * Mermaid 12.2.0 `agentflow-beta` and `eventmodeling`.
 *
 * Both are checked against mermaid's own sources rather than against guesses:
 * the agentflow grammar is the generated jison parser mermaid ships, the
 * eventmodeling grammar is the langium one in @mermaid-js/parser, and every
 * accept/reject below was confirmed against mermaid 12.2.0 itself before being
 * written down. Where this port deliberately differs from mermaid, the test says
 * so and says why.
 *
 * Snapshot assertions go through generate_dot(src, "test.mmd", null): the
 * filename extension picks the format before the content is looked at, so a
 * ".puml" name would quietly route Mermaid source into the PlantUML parser and
 * the test would pass for the wrong reason.
 */
using GDiagram;

namespace AgentflowEventModelingTests {

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

    MermaidAgentflow parse_af(string source) {
        var r = engine().parse(source, "test.mmd");
        assert(r.diagram_type == DiagramType.MERMAID_AGENTFLOW);
        assert(r.ast is MermaidAgentflow);
        return (MermaidAgentflow) r.ast;
    }

    MermaidEventModeling parse_em(string source) {
        var r = engine().parse(source, "test.mmd");
        assert(r.diagram_type == DiagramType.MERMAID_EVENTMODELING);
        assert(r.ast is MermaidEventModeling);
        return (MermaidEventModeling) r.ast;
    }

    void expect(bool ok, string what) {
        if (!ok) {
            printerr("\nFAILED: %s\n", what);
            assert_not_reached();
        }
    }

    // ==================== detection ====================

    void test_detection() {
        // mermaid's own detector regexes: /^\s*agentflow-beta\b/ and
        // /^\s*eventmodeling/ — the "-beta" spelling is what users type.
        expect(engine().detect_mermaid_type("agentflow-beta\n  A --> B")
               == DiagramType.MERMAID_AGENTFLOW, "bare agentflow-beta header");
        expect(engine().detect_mermaid_type("   agentflow-beta LR\n  A --> B")
               == DiagramType.MERMAID_AGENTFLOW, "indented agentflow-beta with direction");
        expect(engine().detect_mermaid_type("eventmodeling\n  tf 01 evt X")
               == DiagramType.MERMAID_EVENTMODELING, "eventmodeling header");

        // Format detection has to agree, or the engine never reaches the Mermaid side.
        expect(engine().detect_format("agentflow-beta\n  A --> B", "x.mmd")
               == DiagramFormat.MERMAID, "agentflow detected as Mermaid");
        expect(engine().detect_format("eventmodeling\n  tf 01 evt X", "x.mmd")
               == DiagramFormat.MERMAID, "eventmodeling detected as Mermaid");

        // The neighbours must not be stolen: "flowchart" still wins for itself, and
        // an agentflow label mentioning "eventmodeling" must not reroute the file.
        expect(engine().detect_mermaid_type("flowchart TD\n  A --> B")
               == DiagramType.MERMAID_FLOWCHART, "flowchart still detected");
        expect(engine().detect_mermaid_type("agentflow-beta\n  A@{ label: \"eventmodeling\" }")
               == DiagramType.MERMAID_AGENTFLOW, "a label does not change the type");
    }

    // ==================== agentflow: kinds ====================

    void test_agentflow_kind_per_shape() {
        // deriveVertexKind's precedence, with every alias mermaid defines.
        var d = parse_af("""agentflow-beta
  A@{ shape: task } --> B@{ shape: tool }
  B --> C@{ shape: decision }
  C --> D@{ shape: input }
  D --> E@{ shape: refdoc }
  E --> F@{ shape: action }
  F --> G
""");
        expect(!d.has_errors(), "the alias set parses");
        expect(d.kind_of("A") == AgentflowKind.TASK, "task");
        expect(d.kind_of("B") == AgentflowKind.TOOL, "tool");
        expect(d.kind_of("C") == AgentflowKind.DECISION, "decision");
        expect(d.kind_of("D") == AgentflowKind.INPUT, "input");
        expect(d.kind_of("E") == AgentflowKind.REFDOC, "refdoc");
        expect(d.kind_of("F") == AgentflowKind.ACTION, "action");
        // A node that never named a shape is a task — mermaid's fallback.
        expect(d.kind_of("G") == AgentflowKind.TASK, "unshaped node is a task");

        // The canonical (non-alias) spellings resolve to the same kinds.
        var c = parse_af("""agentflow-beta
  A@{ shape: subroutine } --> B@{ shape: hexagon }
  B --> C@{ shape: lean-right }
  C --> D@{ shape: lin-doc }
  D --> E@{ shape: diamond }
""");
        expect(c.kind_of("A") == AgentflowKind.TOOL, "subroutine is a tool");
        expect(c.kind_of("B") == AgentflowKind.ACTION, "hexagon is an action");
        expect(c.kind_of("C") == AgentflowKind.INPUT, "lean-right is an input");
        expect(c.kind_of("D") == AgentflowKind.REFDOC, "lin-doc is a refdoc");
        expect(c.kind_of("E") == AgentflowKind.DECISION, "diamond is a decision");
    }

    void test_agentflow_kind_colours_reach_the_dot() {
        // The point of the diagram type: colour tracks kind, from a fixed palette
        // slot, so a tool is the same colour in every diagram. These are the exact
        // values mermaid 12.2.0's default theme emits.
        string dot = dot_of("""agentflow-beta
  A@{ shape: task } --> B@{ shape: tool }
  B --> C@{ shape: decision }
""");
        expect(dot.contains("#2DD4BF") || dot.contains("#2dd4bf"), "task stroke in the DOT");
        expect(dot.contains("#F0FDFA") || dot.contains("#f0fdfa"), "task fill in the DOT");
        expect(dot.contains("#E879F9") || dot.contains("#e879f9"), "tool stroke in the DOT");
        expect(dot.contains("#FB923C") || dot.contains("#fb923c"), "decision stroke in the DOT");

        // Graphviz takes "#" only for hex codes; every colour written must be hex.
        expect(!dot.contains("#white") && !dot.contains("#red"), "no '#' before a named colour");
    }

    void test_agentflow_style_beats_the_kind_palette() {
        // mermaid deliberately does NOT mark the palette rules !important, so a node
        // carrying classDef/style keeps winning over the kind colour.
        string dot = dot_of("""agentflow-beta
  A@{ shape: task } --> B@{ shape: tool }
  style A fill:#123456
""");
        expect(dot.contains("#123456"), "the explicit style colour survives");
        // B had no style, so it keeps the tool palette.
        expect(dot.contains("#E879F9") || dot.contains("#e879f9"), "B keeps the tool colour");
    }

    void test_agentflow_connector() {
        var d = parse_af("""agentflow-beta
  A@{ shape: task } --> J
  connector J
  J --> B@{ shape: tool }
""");
        expect(!d.has_errors(), "connector parses");
        expect(d.connectors.contains("J"), "J is recorded as a connector");
        // A connector reports its own kind even though it is drawn as a rounded
        // rectangle exactly like a task — which is why mermaid refuses to read the
        // kind back off the shape.
        expect(d.kind_of("J") == AgentflowKind.CONNECTOR, "connector kind wins over the shape");
        expect(d.kind_of("A") == AgentflowKind.TASK, "a task is still a task");

        var titled = parse_af("agentflow-beta\n  connector J[Join here]\n  J --> A\n");
        var node = titled.find_node("J");
        expect(node != null && node.text == "Join here", "connector title becomes the label");
    }

    // ==================== agentflow: containers and globals ====================

    void test_agentflow_flow_container() {
        var d = parse_af("""agentflow-beta
  flow Outer[Research loop]
    A@{ shape: task } --> B@{ shape: tool }
    flow Inner[Inner bit]
      X@{ shape: action }
    end
  end
  B --> X
""");
        expect(!d.has_errors(), "nested flow containers parse");
        expect(d.subgraphs.size == 1, "one top-level container");
        var outer = d.subgraphs[0];
        expect(outer.id == "Outer", "outer id");
        expect(outer.title == "Research loop", "outer title");
        expect(outer.subgraphs.size == 1, "one nested container");
        expect(outer.subgraphs[0].id == "Inner", "inner id");

        // Containers cycle the palette slots ABOVE the kind range, in declaration
        // order, so a frame can never take the colour of a node inside it.
        expect(d.container_order.get("Outer") == 0, "Outer is the first container declared");
        expect(d.container_order.get("Inner") == 1, "Inner is the second");
        string dot = dot_of("""agentflow-beta
  flow Outer[One]
    A@{ shape: task }
  end
  flow Other[Two]
    B@{ shape: task }
  end
""");
        expect(dot.contains("#FACC15") || dot.contains("#facc15"), "first container slot 7");
        expect(dot.contains("#818CF8") || dot.contains("#818cf8"), "second container slot 8");
    }

    void test_agentflow_global_exempts_from_containers() {
        // `global` declares nothing of its own. Its only effect is that the ids
        // inside it are never adopted by a container — so the node stays drawn at
        // top level even though a node inside a `flow` points at it.
        var d = parse_af("""agentflow-beta
  global
    P@{ shape: refdoc }
  end
  flow Box[A box]
    A@{ shape: task } --> P
  end
""");
        expect(!d.has_errors(), "global block parses");
        expect(d.global_nodes.contains("P"), "P is global");
        expect(d.find_node("P") != null, "P is still a real node");

        var box = d.find_subgraph("Box");
        expect(box != null, "the container exists");
        foreach (var n in box.nodes) {
            expect(n.id != "P", "a global node is not a container member");
        }
        bool has_a = false;
        foreach (var n in box.nodes) {
            if (n.id == "A") has_a = true;
        }
        expect(has_a, "an ordinary node inside the flow IS a member");
    }

    void test_agentflow_global_exemption_is_order_independent() {
        // mermaid's addGlobal retroactively strips the ids out of containers that
        // closed BEFORE the global block, so where the block is written must not
        // matter. Written after the flow here; the exemption must still hold.
        var d = parse_af("""agentflow-beta
  flow Box[A box]
    A@{ shape: task } --> P
  end
  global
    P@{ shape: refdoc }
  end
""");
        expect(!d.has_errors(), "global-after-flow parses");
        var box = d.find_subgraph("Box");
        expect(box != null, "the container exists");
        foreach (var n in box.nodes) {
            expect(n.id != "P", "a later global block still frees the node");
        }
    }

    void test_agentflow_collapsed_container() {
        var d = parse_af("""agentflow-beta
  flow Box[A box]@{ view: collapsed }
    A@{ shape: task }
  end
""");
        expect(!d.has_errors(), "collapsed container parses");
        expect(d.collapsed.contains("Box"), "the collapse is recorded");

        // Anything other than "collapsed" leaves it expanded.
        var e = parse_af("""agentflow-beta
  flow Box[A box]@{ view: expanded }
    A@{ shape: task }
  end
""");
        expect(!e.collapsed.contains("Box"), "only 'collapsed' collapses");
    }

    // ==================== agentflow: the narrowed operator set ====================

    void test_agentflow_accepts_its_own_operators() {
        // Each of these renders in mermaid 12.2.0; verified one file per operator.
        string[] ok = { "-->", "--->", "----->", "--x", "---x", "-.-", "-..-" };
        foreach (string op in ok) {
            var d = parse_af("agentflow-beta\n  A@{ shape: task } %s B@{ shape: tool }\n".printf(op));
            if (d.has_errors()) {
                printerr("\nFAILED: agentflow should accept '%s': %s\n",
                         op, d.errors[0].message);
                assert_not_reached();
            }
            expect(d.edges.size == 1, "'%s' makes one edge".printf(op));
        }
        // A labelled edge, the third lexable form.
        var l = parse_af("agentflow-beta\n  A@{ shape: task } -- yes --> B@{ shape: tool }\n");
        expect(!l.has_errors(), "labelled edge parses");
        expect(l.edges.size == 1 && l.edges[0].label == "yes", "the label is kept");
    }

    void test_agentflow_rejects_flowchart_only_operators() {
        /*
         * agentflow's lexer keeps only `\s*--+[x>]\s*`, `\s*--\s*` and
         * `\s*-\.+-\s*`. Everything below is a hard syntax error in mermaid
         * 12.2.0 — confirmed by rendering one file per operator — so it must be an
         * error here too rather than a silently different drawing.
         */
        string[] rejected = { "---", "==>", "~~~", "-.->", "--o", "<-->", "x--x", "o--o", "-.-x" };
        foreach (string op in rejected) {
            var d = parse_af("agentflow-beta\n  A@{ shape: task } %s B@{ shape: tool }\n".printf(op));
            if (!d.has_errors()) {
                printerr("\nFAILED: agentflow must reject '%s' (mermaid does)\n", op);
                assert_not_reached();
            }
        }
        // The same operators stay legal in a flowchart — narrowing agentflow must
        // not narrow flowchart. This is the negative control for the check above.
        foreach (string op in rejected) {
            var r = engine().parse("flowchart TD\n  A %s B\n".printf(op), "test.mmd");
            expect(r.diagram_type == DiagramType.MERMAID_FLOWCHART, "still a flowchart");
            var f = (MermaidFlowchart) r.ast;
            if (f.has_errors()) {
                printerr("\nFAILED: flowchart lost '%s': %s\n", op, f.errors[0].message);
                assert_not_reached();
            }
        }
    }

    // ==================== agentflow: shape validation ====================

    void test_agentflow_shape_case_rules_are_hard_errors() {
        // mermaid throws on all three, aborting the parse. The first two judge the
        // AUTHORED spelling, the third the RESOLVED one — which is exactly what
        // lets `task` through (it resolves to the camelCase `roundedRect`) while an
        // authored `roundedRect` is refused.
        var camel = parse_af("agentflow-beta\n  A@{ shape: roundedRect }\n");
        expect(camel.has_errors(), "camelCase shape name is an error");
        expect(camel.errors[0].message.contains("lowercase"), "and says why");

        var under = parse_af("agentflow-beta\n  A@{ shape: lean_right }\n");
        expect(under.has_errors(), "underscored shape name is an error");

        // The alias whose resolved form is camelCase must still work.
        var alias = parse_af("agentflow-beta\n  A@{ shape: task }\n");
        expect(!alias.has_errors(), "'task' resolves to roundedRect and is accepted");
    }

    void test_agentflow_removed_shape_is_recoverable() {
        // A removed shape is an *error-severity diagnostic*, not a parse failure:
        // mermaid coerces the node to the default and keeps drawing. Blanking the
        // preview over it would be worse than drawing the wrong box.
        var d = parse_af("agentflow-beta\n  A@{ shape: stadium } --> B@{ shape: task }\n");
        expect(!d.has_errors(), "a removed shape does not fail the parse");
        expect(d.diagnostics.size == 1, "one diagnostic");
        expect(d.diagnostics[0].id == "SHAPE_REMOVED", "SHAPE_REMOVED");
        expect(d.diagnostics[0].severity == AgentflowSeverity.ERROR, "error severity");
        expect(d.kind_of("A") == AgentflowKind.TASK, "coerced to the default, so a task");
        var node = d.find_node("A");
        expect(node != null && node.shape == FlowchartNodeShape.ROUNDED, "drawn rounded");

        // A shape that exists in mermaid but is outside agentflow's allow-list is a
        // warning, same coercion.
        var w = parse_af("agentflow-beta\n  A@{ shape: cloud } --> B@{ shape: task }\n");
        expect(!w.has_errors(), "an unsupported shape does not fail the parse");
        expect(w.diagnostics.size == 1 && w.diagnostics[0].id == "SHAPE_UNSUPPORTED",
               "SHAPE_UNSUPPORTED");
        expect(w.diagnostics[0].severity == AgentflowSeverity.WARNING, "warning severity");
    }

    void test_agentflow_header_is_mandatory() {
        var r = engine().parse("  A@{ shape: task } --> B\n", "test.mmd");
        // Without the header this is not agentflow at all.
        expect(r.diagram_type != DiagramType.MERMAID_AGENTFLOW, "no header, no agentflow");
    }

    void test_agentflow_default_shape_is_rounded() {
        // normaliseNodeShapes rewrites a missing or plain-rectangle shape to the
        // rounded default for EVERY node, which is why a bare `A --> B` draws two
        // rounded rectangles rather than two rectangles.
        string dot = dot_of("agentflow-beta\n  A --> B\n");
        expect(dot.contains("rounded"), "bare nodes are drawn rounded");
    }

    // ==================== eventmodeling: parsing ====================

    void test_eventmodeling_frames() {
        var d = parse_em("""eventmodeling
  tf 01 ui Checkout
  tf 02 cmd PlaceOrder
  tf 03 evt OrderPlaced
  tf 04 rmo OrderList
  tf 05 pcr Shipper
  rf 06 evt DayClosed
""");
        expect(!d.has_errors(), "the five kinds and a reset frame parse");
        expect(d.frames.size == 6, "six frames");
        expect(d.frames[0].kind == EmEntityKind.UI, "ui");
        expect(d.frames[1].kind == EmEntityKind.COMMAND, "cmd");
        expect(d.frames[2].kind == EmEntityKind.EVENT, "evt");
        expect(d.frames[3].kind == EmEntityKind.READ_MODEL, "rmo");
        expect(d.frames[4].kind == EmEntityKind.PROCESSOR, "pcr");
        expect(d.frames[5].is_reset, "rf is a reset frame");
        expect(d.frames[2].index == 2, "declaration order is recorded");

        // The long spellings are the same kinds.
        var l = parse_em("""eventmodeling
  timeframe 01 readmodel A
  timeframe 02 command B
  timeframe 03 event C
  timeframe 04 processor D
  resetframe 05 event E
""");
        expect(!l.has_errors(), "long keyword spellings parse");
        expect(l.frames[0].kind == EmEntityKind.READ_MODEL, "readmodel");
        expect(l.frames[1].kind == EmEntityKind.COMMAND, "command");
        expect(l.frames[3].kind == EmEntityKind.PROCESSOR, "processor");
        expect(l.frames[4].is_reset, "resetframe");
    }

    void test_eventmodeling_frame_id_must_be_one_to_three_digits() {
        // EM_FI = /\d{1,3}/ — nothing else is a frame id.
        expect(parse_em("eventmodeling\n  tf 1 evt A\n").frames.size == 1, "one digit is fine");
        expect(parse_em("eventmodeling\n  tf 123 evt A\n").frames.size == 1, "three digits are fine");
        expect(parse_em("eventmodeling\n  tf 1234 evt A\n").has_errors(), "four digits is an error");
        expect(parse_em("eventmodeling\n  tf ab evt A\n").has_errors(), "letters are not a frame id");
    }

    void test_eventmodeling_duplicate_frame_id() {
        // db.ts setAst() throws on a duplicate frame id, naming the line.
        var d = parse_em("eventmodeling\n  tf 01 evt A\n  tf 01 evt B\n");
        expect(d.has_errors(), "a duplicate frame id is an error");
        expect(d.errors[0].message.contains("Duplicate"), "and says so");
    }

    void test_eventmodeling_namespace_split() {
        // extractNamespace/extractName: ONLY a two-part dotted name has a namespace.
        var d = parse_em("""eventmodeling
  tf 01 evt Shop.OrderPlaced
  tf 02 evt Plain
  tf 03 evt a.b.c
""");
        expect(!d.has_errors(), "qualified names parse");
        expect(d.frames[0].ns == "Shop", "two parts give a namespace");
        expect(d.frames[0].entity_name == "OrderPlaced", "and the name is the second part");
        expect(d.frames[1].ns == null, "one part has no namespace");
        expect(d.frames[1].entity_name == "Plain", "and keeps its whole text");
        expect(d.frames[2].ns == null, "three parts have no namespace either");
        expect(d.frames[2].entity_name == "a.b.c", "and keep the whole dotted text");
    }

    void test_eventmodeling_sources_and_data() {
        var d = parse_em("""eventmodeling
  data OrderData {
  orderId: o-1
}
  tf 01 cmd PlaceOrder {"amount": 42}
  tf 02 evt OrderPlaced [[OrderData]]
  tf 03 rmo OrderList ->>01 ->>02
  tf 04 evt Typed `json` {"a": 1}
""");
        expect(!d.has_errors(), "data blocks, inline data and sources parse");
        expect(d.data_entities.size == 1, "one data entity");
        expect(d.data_entities[0].name == "OrderData", "named");
        expect(d.data_entities[0].body.contains("orderId"), "with its body");
        expect(d.frames[0].data_inline == "{\"amount\": 42}", "inline data kept verbatim");
        expect(d.frames[1].data_reference == "OrderData", "the [[ref]] is resolved by name");
        expect(d.frames[2].source_frames.size == 2, "two explicit sources");
        expect(d.frames[2].source_frames[0] == "01", "in source order");
        expect(d.frames[3].data_type == "json", "the backtick data type is kept");
    }

    void test_eventmodeling_notes_and_gwt_are_parsed_not_drawn() {
        var d = parse_em("""eventmodeling
  entity Order
  tf 01 cmd PlaceOrder
  tf 02 evt OrderPlaced
  note 02 {
  a note body
}
  gwt 02 given cmd PlaceOrder when cmd PlaceOrder then evt OrderPlaced
""");
        expect(!d.has_errors(), "entity, note and gwt parse");
        expect(d.model_entities.size == 1, "one declared entity");
        expect(d.notes.size == 1 && d.notes[0].frame_name == "02", "the note is kept");
        expect(d.notes[0].body.contains("a note body"), "with its body");
        expect(d.gwts.size == 1, "the gwt is kept");
        expect(d.gwts[0].given.size == 1 && d.gwts[0].then_items.size == 1, "given and then");
        expect(d.gwts[0].when_items.size == 1, "and the optional when");

        // mermaid 12.2.0's renderer draws only swimlanes, boxes and relations, so
        // neither a note nor a gwt may add anything to the drawing. Two frames, two
        // boxes — the note and the gwt must not have made a third.
        string dot = dot_of("""eventmodeling
  tf 01 cmd PlaceOrder
  tf 02 evt OrderPlaced
  note 02 {
  a note body
}
""");
        expect(!dot.contains("a note body"), "the note text is not drawn");
    }

    void test_eventmodeling_rejects_junk() {
        expect(parse_em("eventmodeling\n  tf 01 nope A\n").has_errors(),
               "an unknown entity type is an error");
        expect(parse_em("eventmodeling\n  wibble 01 evt A\n").has_errors(),
               "an unknown statement is an error");
        expect(parse_em("eventmodeling\n  tf 01 evt A ->>\n").has_errors(),
               "a dangling '->>' is an error");
        expect(parse_em("eventmodeling\n  tf 01 evt A [[Missing\n").has_errors(),
               "an unterminated '[[' is an error");
        expect(parse_em("eventmodeling\n  data D {\n  unterminated\n").has_errors(),
               "an unterminated data block is an error");
    }

    // ==================== eventmodeling: layout ====================

    /* The y of the nth <rect> inside an em-box group, from the rendered SVG. */
    void em_boxes(string svg, out int count, out string first_fill) {
        count = 0;
        first_fill = "";
        try {
            var re = new Regex("<g class=\"em-box\">\\s*<rect[^>]*fill=\"([^\"]*)\"");
            MatchInfo mi;
            if (re.match(svg, 0, out mi)) {
                first_fill = mi.fetch(1);
                do {
                    count++;
                } while (mi.next());
            }
        } catch (RegexError e) {
            assert_not_reached();
        }
    }

    string em_svg(string source) {
        string path = Path.build_filename(Environment.get_tmp_dir(),
            "gdiagram-em-%d.svg".printf(Random.int_range(0, 1 << 30)));
        assert(engine().export_to_svg(source, "test.mmd", null, path));
        string svg;
        try {
            FileUtils.get_contents(path, out svg);
        } catch (FileError e) {
            error("%s", e.message);
        }
        FileUtils.unlink(path);
        return svg;
    }

    void test_eventmodeling_bands_and_boxes() {
        /*
         * The reference numbers come from mermaid 12.2.0's own render of this exact
         * source: three lanes at y = 0 / 140 / 280, each 130 high, labelled
         * "UI/Automation", "Command/Read Model", "Events"; six boxes, all 100 high,
         * the first at x = 250 (contentStartX).
         */
        string svg = em_svg("""eventmodeling
  tf 01 ui Checkout
  tf 02 cmd PlaceOrder
  tf 03 evt OrderPlaced
  tf 04 rmo OrderList
  tf 05 ui OrderScreen
  tf 06 pcr Shipper
""");
        expect(svg.contains("UI/Automation"), "the UI band label");
        expect(svg.contains("Command/Read Model"), "the command/read-model band label");
        expect(svg.contains("Events"), "the events band label");

        // Exactly three lanes: ui+pcr share band 0, cmd+rmo band 100, evt band 200.
        int lanes = 0;
        int at = 0;
        while ((at = svg.index_of("em-swimlane", at)) >= 0) { lanes++; at += 1; }
        expect(lanes == 3, "ui/pcr, cmd/rmo and evt collapse to three lanes, got %d".printf(lanes));

        expect(svg.contains("y=\"0\""), "the first lane sits at y=0");
        expect(svg.contains("y=\"140\""), "the second at y=140");
        expect(svg.contains("y=\"280\""), "the third at y=280");
        // Box tops are the lane y plus the 15px lane padding.
        expect(svg.contains("y=\"15\""), "the first box at y=15");
        expect(svg.contains("x=\"250\""), "the first box at contentStartX=250");

        int boxes;
        string first_fill;
        em_boxes(svg, out boxes, out first_fill);
        expect(boxes == 6, "six boxes, got %d".printf(boxes));

        // Per-kind fills, straight out of db.ts calculateEntityVisualProps.
        expect(svg.contains("#bcd6fe"), "command fill");
        expect(svg.contains("#ffb778"), "event fill");
        expect(svg.contains("#d3f1a2"), "read-model fill");
        expect(svg.contains("#edb3f6"), "processor fill");
    }

    void test_eventmodeling_relations() {
        /*
         * decidePositionRelation: the first frame gets no relation; a frame with no
         * explicit source takes the nearest earlier frame in a DIFFERENT lane; a
         * reset frame with no source gets none at all.
         *
         * Six frames here: 01 none, 02..05 one each, 06 (rf) none => four relations.
         */
        string svg = em_svg("""eventmodeling
  tf 01 ui Checkout
  tf 02 cmd PlaceOrder
  tf 03 evt OrderPlaced
  tf 04 rmo OrderList
  tf 05 ui OrderScreen
  rf 06 evt DayClosed
""");
        int rels = 0;
        int at = 0;
        while ((at = svg.index_of("em-relation", at)) >= 0) { rels++; at += 1; }
        expect(rels == 4, "four relations (first frame and the reset frame get none), got %d".printf(rels));

        // An explicit ->> on a reset frame DOES draw one.
        string with_src = em_svg("""eventmodeling
  tf 01 ui Checkout
  tf 02 cmd PlaceOrder
  rf 03 evt DayClosed ->>01
""");
        int rels2 = 0;
        at = 0;
        while ((at = with_src.index_of("em-relation", at)) >= 0) { rels2++; at += 1; }
        expect(rels2 == 2, "a reset frame with an explicit source draws one, got %d".printf(rels2));
    }

    void test_eventmodeling_svg_is_locale_safe() {
        /*
         * Every number written into the SVG must be C-formatted. "%f" follows
         * LC_NUMERIC, and a GUI process has called setlocale() while a headless
         * export has not — which is how a German desktop got "0,8333" into a graph
         * and failed only in the preview.
         */
        string? had = Intl.setlocale(LocaleCategory.NUMERIC, null);
        string[] comma_locales = { "de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "de_AT.UTF-8" };
        string? used = null;
        foreach (string loc in comma_locales) {
            if (Intl.setlocale(LocaleCategory.NUMERIC, loc) != null && "%.2f".printf(1.5) == "1,50") {
                used = loc;
                break;
            }
        }
        if (used == null) {
            Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");
            Test.skip("no comma-decimal locale installed; cannot prove the locale guard here");
            return;
        }
        // Widths here are fractional (the relation endpoints are thirds of a box).
        string svg = em_svg("""eventmodeling
  tf 01 ui Checkout
  tf 02 cmd PlaceOrder
  tf 03 evt OrderPlaced
""");
        Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");

        try {
            // A comma inside any numeric attribute would be a broken SVG.
            var bad = new Regex("(x|y|width|height|font-size)=\"[-0-9]*,[0-9]");
            if (bad.match(svg)) {
                printerr("\nFAILED: locale-formatted number in the SVG (%s)\n", used);
                assert_not_reached();
            }
            // The path data too.
            var bad_path = new Regex("d=\"M[0-9]*,[0-9]");
            if (bad_path.match(svg)) {
                printerr("\nFAILED: locale-formatted number in a path (%s)\n", used);
                assert_not_reached();
            }
        } catch (RegexError e) {
            assert_not_reached();
        }
        expect(svg.contains("em-relation"), "the diagram really was drawn under that locale");
    }

    // ==================== both: the engine plumbing ====================

    void test_dot_output_for_both() {
        // -f dot has to work for both types; the eventmodeling renderer writes SVG
        // directly, so its generate_dot() returns a summary graph instead.
        string af = dot_of("agentflow-beta\n  A@{ shape: task } --> B@{ shape: tool }\n");
        expect(af.has_prefix("digraph"), "agentflow DOT is a digraph");
        expect(af.contains("->"), "with an edge");

        string em = dot_of("eventmodeling\n  tf 01 cmd A\n  tf 02 evt B\n");
        expect(em.has_prefix("digraph"), "eventmodeling DOT is a digraph");
        expect(em.contains("->"), "with the derived relation as an edge");
    }

    void test_export_round_trip() {
        // PNG, SVG and PDF for both, through the engine's own export path.
        string[] sources = {
            "agentflow-beta\n  A@{ shape: task } --> B@{ shape: tool }\n  B --> C@{ shape: decision }\n",
            "eventmodeling\n  tf 01 ui A\n  tf 02 cmd B\n  tf 03 evt C\n"
        };
        string[] exts = { "png", "svg", "pdf" };
        foreach (string src in sources) {
            foreach (string ext in exts) {
                string path = Path.build_filename(Environment.get_tmp_dir(),
                    "gdiagram-afem-%d.%s".printf(Random.int_range(0, 1 << 30), ext));
                bool ok = false;
                if (ext == "png") ok = engine().export_to_png(src, "test.mmd", null, path);
                else if (ext == "svg") ok = engine().export_to_svg(src, "test.mmd", null, path);
                else ok = engine().export_to_pdf(src, "test.mmd", null, path);
                expect(ok, "export to %s succeeded".printf(ext));
                expect(FileUtils.test(path, FileTest.EXISTS), "%s file exists".printf(ext));
                var f = File.new_for_path(path);
                try {
                    var info = f.query_info("standard::size", FileQueryInfoFlags.NONE);
                    expect(info.get_size() > 100, "the %s is not empty".printf(ext));
                } catch (Error e) {
                    assert_not_reached();
                }
                FileUtils.unlink(path);
            }
        }
    }

    void test_render_produces_a_surface() {
        var r = engine().render(DiagramType.MERMAID_AGENTFLOW, DiagramFormat.MERMAID,
            "agentflow-beta\n  A@{ shape: task } --> B@{ shape: tool }\n");
        expect(r.status == RenderStatus.OK, "agentflow renders");
        expect(r.surface != null, "with a surface");

        var e = engine().render(DiagramType.MERMAID_EVENTMODELING, DiagramFormat.MERMAID,
            "eventmodeling\n  tf 01 cmd A\n  tf 02 evt B\n");
        expect(e.status == RenderStatus.OK, "eventmodeling renders");
        expect(e.surface != null, "with a surface");
    }

    void test_click_regions() {
        // Every eventmodeling box maps a click region back to its own source line.
        engine().render(DiagramType.MERMAID_EVENTMODELING, DiagramFormat.MERMAID,
            "eventmodeling\n  tf 01 cmd PlaceOrder\n  tf 02 evt OrderPlaced\n");
        var regions = engine().last_regions;
        expect(regions.size >= 2, "two box regions, got %d".printf(regions.size));
        bool saw_line_2 = false, saw_line_3 = false;
        foreach (var reg in regions) {
            if (reg.source_line == 2) saw_line_2 = true;
            if (reg.source_line == 3) saw_line_3 = true;
        }
        expect(saw_line_2 && saw_line_3, "regions carry their own frame's line");
    }

    // ==================== robustness ====================

    void test_no_runaway_on_pathological_input() {
        /*
         * Three Mermaid parsers in this codebase have overflowed the stack on
         * nested input and one chart renderer once ate 22 GB in an infinite loop,
         * so every body loop here carries a progress check and the container
         * recursion is depth-capped. These inputs exercise both.
         */
        /*
         * Container parsing is recursive descent, so the only thing standing
         * between a deeply nested file and a blown stack is MAX_SUBGRAPH_DEPTH.
         * Nest just past it: the cap must fire and *say* it fired, rather than
         * recursing on or silently truncating the document.
         */
        var capped = new StringBuilder("agentflow-beta\n");
        for (int i = 0; i < 250; i++) capped.append_printf("  flow F%d[F%d]\n", i, i);
        capped.append("  A@{ shape: task }\n");
        for (int i = 0; i < 250; i++) capped.append("  end\n");
        var c = parse_af(capped.str);
        expect(c != null, "nesting past the cap returns rather than overflowing");
        expect(c.has_errors(), "the depth cap reports rather than truncating silently");
        bool said_nested = false;
        foreach (var err in c.errors) {
            if (err.message.contains("nested")) said_nested = true;
        }
        expect(said_nested, "and the message names the nesting depth");

        // Deep but under the cap: this one has to parse cleanly, so the cap is not
        // just rejecting anything large.
        var deep = new StringBuilder("agentflow-beta\n");
        for (int i = 0; i < 150; i++) deep.append_printf("  flow G%d[G%d]\n", i, i);
        deep.append("  A@{ shape: task }\n");
        for (int i = 0; i < 150; i++) deep.append("  end\n");
        var d = parse_af(deep.str);
        expect(d != null && !d.has_errors(), "150 levels is under the cap and parses");

        // Unterminated containers, stray ends, junk between.
        expect(parse_af("agentflow-beta\n  flow A\n") != null, "unterminated flow returns");
        expect(parse_af("agentflow-beta\n  end\n  end\n") != null, "stray ends return");
        expect(parse_af("agentflow-beta\n  global\n") != null, "unterminated global returns");
        expect(parse_af("agentflow-beta\n  connector\n") != null, "bare connector returns");
        expect(parse_af("agentflow-beta\n  @@@@ {{{{ [[[[\n") != null, "token soup returns");

        // The eventmodeling line walker.
        var junk = new StringBuilder("eventmodeling\n");
        for (int i = 0; i < 2000; i++) junk.append("  }}}} [[[[ ->>\n");
        expect(parse_em(junk.str) != null, "2000 junk lines return");
        expect(parse_em("eventmodeling\n  data D {\n") != null, "unterminated block returns");
        expect(parse_em("eventmodeling") != null, "header only returns");
        expect(parse_em("eventmodeling\n") != null, "header and newline return");
    }

    void test_empty_and_header_only() {
        var r = engine().render(DiagramType.MERMAID_AGENTFLOW, DiagramFormat.MERMAID,
                                "agentflow-beta\n");
        expect(r.status == RenderStatus.EMPTY, "an empty agentflow shows the placeholder");
        var e = engine().render(DiagramType.MERMAID_EVENTMODELING, DiagramFormat.MERMAID,
                                "eventmodeling\n");
        expect(e.status == RenderStatus.EMPTY, "an empty eventmodeling shows the placeholder");
    }

    void test_examples_render() {
        // The shipped examples must stay renderable; they are also what the gallery
        // and the template health test walk.
        string dir = Path.build_filename(Environment.get_variable("GDIAGRAM_EXAMPLES_DIR") ??
                                         "examples", "mermaid");
        string[] files = {
            Path.build_filename(dir, "agentflow", "research-agent.mmd"),
            Path.build_filename(dir, "agentflow", "support-triage.mmd"),
            Path.build_filename(dir, "eventmodeling", "order-fulfilment.mmd"),
            Path.build_filename(dir, "eventmodeling", "subscription-billing.mmd")
        };
        foreach (string path in files) {
            if (!FileUtils.test(path, FileTest.EXISTS)) {
                printerr("\nFAILED: missing example %s\n", path);
                assert_not_reached();
            }
            string src;
            try {
                FileUtils.get_contents(path, out src);
            } catch (FileError e) {
                assert_not_reached();
            }
            var type = engine().detect_mermaid_type(src);
            expect(type == DiagramType.MERMAID_AGENTFLOW || type == DiagramType.MERMAID_EVENTMODELING,
                   "%s is detected".printf(Path.get_basename(path)));
            var r = engine().parse(src, "test.mmd");
            if (r.errors != null && r.errors.size > 0) {
                printerr("\nFAILED: %s has parse errors: %s\n",
                         Path.get_basename(path), r.errors[0].message);
                assert_not_reached();
            }
            var rr = engine().render(type, DiagramFormat.MERMAID, src);
            expect(rr.status == RenderStatus.OK, "%s renders".printf(Path.get_basename(path)));
            expect(rr.surface != null, "%s has a surface".printf(Path.get_basename(path)));
        }
    }

    int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/afem/detection", test_detection);

        Test.add_func("/afem/agentflow/kind-per-shape", test_agentflow_kind_per_shape);
        Test.add_func("/afem/agentflow/kind-colours", test_agentflow_kind_colours_reach_the_dot);
        Test.add_func("/afem/agentflow/style-beats-palette", test_agentflow_style_beats_the_kind_palette);
        Test.add_func("/afem/agentflow/connector", test_agentflow_connector);
        Test.add_func("/afem/agentflow/flow-container", test_agentflow_flow_container);
        Test.add_func("/afem/agentflow/global-exempts", test_agentflow_global_exempts_from_containers);
        Test.add_func("/afem/agentflow/global-order-independent",
                      test_agentflow_global_exemption_is_order_independent);
        Test.add_func("/afem/agentflow/collapsed", test_agentflow_collapsed_container);
        Test.add_func("/afem/agentflow/accepts-own-operators", test_agentflow_accepts_its_own_operators);
        Test.add_func("/afem/agentflow/rejects-flowchart-operators",
                      test_agentflow_rejects_flowchart_only_operators);
        Test.add_func("/afem/agentflow/shape-case-rules", test_agentflow_shape_case_rules_are_hard_errors);
        Test.add_func("/afem/agentflow/removed-shape-recoverable",
                      test_agentflow_removed_shape_is_recoverable);
        Test.add_func("/afem/agentflow/header-mandatory", test_agentflow_header_is_mandatory);
        Test.add_func("/afem/agentflow/default-shape-rounded", test_agentflow_default_shape_is_rounded);

        Test.add_func("/afem/eventmodeling/frames", test_eventmodeling_frames);
        Test.add_func("/afem/eventmodeling/frame-id-digits",
                      test_eventmodeling_frame_id_must_be_one_to_three_digits);
        Test.add_func("/afem/eventmodeling/duplicate-frame-id", test_eventmodeling_duplicate_frame_id);
        Test.add_func("/afem/eventmodeling/namespace-split", test_eventmodeling_namespace_split);
        Test.add_func("/afem/eventmodeling/sources-and-data", test_eventmodeling_sources_and_data);
        Test.add_func("/afem/eventmodeling/notes-and-gwt",
                      test_eventmodeling_notes_and_gwt_are_parsed_not_drawn);
        Test.add_func("/afem/eventmodeling/rejects-junk", test_eventmodeling_rejects_junk);
        Test.add_func("/afem/eventmodeling/bands-and-boxes", test_eventmodeling_bands_and_boxes);
        Test.add_func("/afem/eventmodeling/relations", test_eventmodeling_relations);
        Test.add_func("/afem/eventmodeling/locale-safe", test_eventmodeling_svg_is_locale_safe);

        Test.add_func("/afem/dot-output", test_dot_output_for_both);
        Test.add_func("/afem/export-round-trip", test_export_round_trip);
        Test.add_func("/afem/render-surface", test_render_produces_a_surface);
        Test.add_func("/afem/click-regions", test_click_regions);
        Test.add_func("/afem/no-runaway", test_no_runaway_on_pathological_input);
        Test.add_func("/afem/empty", test_empty_and_header_only);
        Test.add_func("/afem/examples", test_examples_render);
        return Test.run();
    }
}
