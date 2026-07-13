namespace GDiagram.Tests {
    /**
     * Mermaid fidelity review: class, ER and state diagrams compared with Mermaid CLI 11.17.
     * One test per finding (C1-C6 class, E1-E4 ER, S1-S6 state).
     */
    public class ReviewMermaidStructuralTests {

        private static void check(bool ok, string what, string context = "") {
            if (!ok) {
                printerr("\nFAILED: %s\n%s\n", what, context);
                assert_not_reached();
            }
        }

        private static Object ast_of(string source, DiagramType expected) {
            var r = new DiagramEngine("dot").parse(source, "x.mmd");
            check(r.diagram_type == expected, "detected " + r.diagram_type.to_string(), source);
            check(r.errors == null || r.errors.size == 0,
                  "no parse errors" + ((r.errors != null && r.errors.size > 0) ? ": " + r.errors[0].message : ""),
                  source);
            return r.ast;
        }

        private static string dot_of(string source) {
            string? dot = new DiagramEngine("dot").generate_dot(source, "x.mmd", null);
            check(dot != null, "dot generated", source);
            return dot;
        }

        // The DOT line declaring or connecting `prefix` ("A -> B " / "A [")
        private static string line_starting(string dot, string prefix) {
            foreach (string line in dot.split("\n")) {
                if (line.strip().has_prefix(prefix)) return line.strip();
            }
            return "";
        }

        private static int count(string haystack, string needle) {
            int n = 0;
            int at = 0;
            while ((at = haystack.index_of(needle, at)) >= 0) {
                n++;
                at += needle.length;
            }
            return n;
        }

        // ==================== Class ====================

        // C1: every Mermaid relation draws an edge; labels and markers never become classes
        public static void test_c1_relation_types() {
            string src = "classDiagram\n    A *-- B : comp\n    C o-- D : agg\n    E -- F : assoc\n" +
                         "    G ..> H : dep\n    I <|.. J : real\n    K --> L : navig\n    M .. N : link\n" +
                         "    O \"1\" --> \"*\" P : card\n    Q <|--|> R\n    S *--* T\n    U o--o V\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.classes.size == 22, "22 classes, got %d".printf(d.classes.size));
            check(d.relations.size == 11, "11 relations, got %d".printf(d.relations.size));
            foreach (var c in d.classes) {
                check(c.name != "o" && c.name != "comp" && c.name != "agg", "no ghost class " + c.name);
            }
            check(d.relations[0].relation_type == MermaidRelationType.COMPOSITION, "composition");
            check(d.relations[1].relation_type == MermaidRelationType.AGGREGATION, "aggregation");
            check(d.relations[6].relation_type == MermaidRelationType.DASHED_LINK, "dashed link");
            check(d.relations[7].from_cardinality == "1" && d.relations[7].to_cardinality == "*", "cardinality");
            check(d.relations[7].label == "card", "label");

            string dot = dot_of(src);
            check(line_starting(dot, "A -> B ").contains("arrowtail=diamond") &&
                  line_starting(dot, "A -> B ").contains("arrowhead=none") &&
                  line_starting(dot, "A -> B ").contains("label=\"comp\""), "composition edge", dot);
            check(line_starting(dot, "C -> D ").contains("arrowtail=odiamond"), "aggregation edge", dot);
            check(line_starting(dot, "E -> F ").contains("arrowtail=none, arrowhead=none"), "plain link", dot);
            check(line_starting(dot, "G -> H ").contains("style=dashed") &&
                  line_starting(dot, "G -> H ").contains("arrowhead=vee"), "dependency", dot);
            check(line_starting(dot, "M -> N ").contains("style=dashed"), "dashed link", dot);
            check(line_starting(dot, "O -> P ").contains("taillabel=\"1\", headlabel=\"*\""), "cardinality labels", dot);
            check(line_starting(dot, "Q -> R ").contains("arrowtail=empty, arrowhead=empty"), "two-sided inheritance", dot);
            check(line_starting(dot, "S -> T ").contains("arrowtail=diamond, arrowhead=diamond"), "two-sided composition", dot);
            check(line_starting(dot, "U -> V ").contains("arrowtail=odiamond, arrowhead=odiamond"), "two-sided aggregation", dot);
        }

        // C2: generics in class names, member types and parameters
        public static void test_c2_generics() {
            string src = "classDiagram\n    class Repo~T~ {\n      -List~T~ items\n      +get(id int) T\n" +
                         "      +all() List~Map~K,V~~\n    }\n    Repo~T~ <|-- UserRepo\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.classes.size == 2, "Repo and UserRepo only, got %d".printf(d.classes.size));
            var repo = d.find_class("Repo");
            check(repo != null && repo.generic_type == "T", "generic type T");
            check(repo.members.size == 3, "3 members");
            check(repo.members[0].display_text == "-List<T> items", "attribute: " + repo.members[0].display_text);
            check(repo.members[0].name == "items" && repo.members[0].type_name == "List<T>", "attribute name/type");
            check(repo.members[1].display_text == "+get(id int) : T", "method: " + repo.members[1].display_text);
            check(repo.members[2].type_name == "List<Map<K,V>>", "nested generic: " + repo.members[2].type_name);
            check(d.relations.size == 1 && d.relations[0].from == repo, "relation from Repo~T~");
            string dot = dot_of(src);
            check(line_starting(dot, "Repo [").contains("<B>Repo&lt;T&gt;</B>"), "Repo<T> title", dot);
        }

        // C3: "Animal <|-- Dog": Animal ranks first and carries the triangle; <|.. is dashed
        public static void test_c3_inheritance_direction() {
            string dot = dot_of("classDiagram\n    Animal <|-- Dog\n    Shape <|.. Circle\n");
            string inh = line_starting(dot, "Animal -> Dog ");
            check(inh.contains("arrowtail=empty") && inh.contains("arrowhead=none") && !inh.contains("dashed"),
                  "triangle at Animal: " + inh, dot);
            string real = line_starting(dot, "Shape -> Circle ");
            check(real.contains("arrowtail=empty") && real.contains("style=dashed"), "dashed realization: " + real, dot);
        }

        // C4a: "A : +int x" is a member, `class A["Label"]` keeps its label
        public static void test_c4_colon_member_and_label() {
            string src = "classDiagram\n    class A[\"Label A\"]\n    A : +int x\n    A : +go() bool\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.classes.size == 1, "one class, got %d".printf(d.classes.size));
            var a = d.find_class("A");
            check(a.label == "Label A", "label");
            check(a.members.size == 2 && a.members[0].display_text == "+int x" &&
                  a.members[1].display_text == "+go() : bool", "colon members");
            check(line_starting(dot_of(src), "A [").contains("<B>Label A</B>"), "label rendered");
        }

        // C4b: style / classDef / ::: / cssClass colour the class and create no classes
        public static void test_c4_styles() {
            string src = "classDiagram\n    class A\n    style A fill:#f9f,stroke:#333\n    class C:::hot\n" +
                         "    class D\n    cssClass \"D\" cool\n    classDef hot fill:#f96\n    classDef cool fill:#9cf,color:#fff\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.classes.size == 3, "A, C, D only, got %d".printf(d.classes.size));
            string dot = dot_of(src);
            check(line_starting(dot, "A [").contains("BGCOLOR=\"#f9f\" COLOR=\"#333\""), "style fill/stroke", dot);
            check(line_starting(dot, "C [").contains("BGCOLOR=\"#f96\""), ":::hot", dot);
            check(line_starting(dot, "D [").contains("BGCOLOR=\"#9cf\"") &&
                  line_starting(dot, "D [").contains("fontcolor=\"#fff\""), "cssClass", dot);
        }

        // C4c: notes
        public static void test_c4_notes() {
            string src = "classDiagram\n    class A\n    note for A \"a note\"\n    note \"free note\"\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.classes.size == 1, "no class from the note");
            check(d.notes.size == 2 && d.notes[0].for_class == d.find_class("A") && d.notes[0].text == "a note" &&
                  d.notes[1].for_class == null && d.notes[1].text == "free note", "notes parsed");
            string dot = dot_of(src);
            check(line_starting(dot, "note_0 [").contains("label=\"a note\", shape=note"), "note node", dot);
            check(line_starting(dot, "note_0 -> A ").contains("style=dotted"), "note link", dot);
            check(line_starting(dot, "note_1 [").contains("label=\"free note\""), "free note", dot);
        }

        // C5: full method signatures, abstract (*) italic and static ($) underlined
        public static void test_c5_method_signatures() {
            string src = "classDiagram\n    class Shape {\n      +getArea(x float) float\n      +Circle(radius)\n" +
                         "      +someAbstract()*\n      +someStatic()$\n      -int count$\n    }\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            var m = d.find_class("Shape").members;
            check(m[0].display_text == "+getArea(x float) : float", "signature: " + m[0].display_text);
            check(m[0].parameters == "x float" && m[0].type_name == "float", "parameters/return");
            check(m[1].display_text == "+Circle(radius)", "constructor: " + m[1].display_text);
            check(m[2].is_abstract && !m[2].is_static, "abstract marker");
            check(m[3].is_static && m[4].is_static && !m[4].is_method, "static markers");
            string node = line_starting(dot_of(src), "Shape [");
            check(node.contains("+getArea(x float) : float"), "signature rendered", node);
            check(node.contains("<I>+someAbstract()</I>"), "italic abstract", node);
            check(node.contains("<U>+someStatic()</U>") && node.contains("<U>-int count</U>"), "underlined static", node);
        }

        // C6: annotations as «...», enumeration kind, direction
        public static void test_c6_annotations_direction() {
            string src = "classDiagram\n    direction LR\n    class Color {\n      <<enumeration>>\n      RED\n    }\n" +
                         "    class Shape\n    <<interface>> Shape\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.find_class("Color").class_type == MermaidClassType.ENUM, "enumeration kind");
            check(d.find_class("Shape").class_type == MermaidClassType.INTERFACE, "interface kind");
            check(d.direction == FlowchartDirection.LEFT_RIGHT, "direction");
            string dot = dot_of(src);
            check(dot.contains("rankdir=LR;"), "rankdir", dot);
            check(line_starting(dot, "Shape [").contains("«interface»<BR/><B>Shape</B>"), "annotation", dot);
        }

        // ==================== ER ====================

        // E1: attribute names that are keywords elsewhere keep their name
        public static void test_e1_keyword_attribute_names() {
            string src = "erDiagram\n    POST {\n      string title\n      string direction\n      string style\n" +
                         "      string class\n      string state\n    }\n";
            var d = (MermaidERDiagram) ast_of(src, DiagramType.MERMAID_ER);
            var attrs = d.find_entity("POST").attributes;
            check(attrs.size == 5, "5 attributes");
            string[] names = { "title", "direction", "style", "class", "state" };
            for (int i = 0; i < names.length; i++) {
                check(attrs[i].name == names[i] && attrs[i].type_name == "string", "attribute " + names[i]);
            }
            check(line_starting(dot_of(src), "POST [").contains("<TD ALIGN=\"LEFT\">title</TD>"), "title rendered");
        }

        // E2: UK keys and comments
        public static void test_e2_keys_and_comments() {
            string src = "erDiagram\n    USER {\n      string name UK\n      int id PK, FK\n      string email \"user email\"\n    }\n";
            var d = (MermaidERDiagram) ast_of(src, DiagramType.MERMAID_ER);
            var a = d.find_entity("USER").attributes;
            check(a[0].is_unique_key && !a[0].is_primary_key, "UK");
            check(a[1].is_primary_key && a[1].is_foreign_key, "PK, FK");
            check(a[2].comment == "user email" && a[2].name == "email", "comment");
            string node = line_starting(dot_of(src), "USER [");
            check(node.contains("<TD ALIGN=\"LEFT\">UK</TD>") && node.contains("<TD ALIGN=\"LEFT\">PK, FK</TD>") &&
                  node.contains("<TD ALIGN=\"LEFT\">user email</TD>"), "keys and comment columns", node);
        }

        // E3: ".." non-identifying relationships are dashed
        public static void test_e3_non_identifying_dashed() {
            string src = "erDiagram\n    A }|..|{ B : uses\n    C ||--o{ D : has\n";
            var d = (MermaidERDiagram) ast_of(src, DiagramType.MERMAID_ER);
            check(!d.relationships[0].identifying && d.relationships[1].identifying, "identifying flags");
            check(d.relationships[0].from_cardinality == MermaidERCardinality.ONE_OR_MORE &&
                  d.relationships[1].to_cardinality == MermaidERCardinality.ZERO_OR_MORE, "cardinalities");
            string dot = dot_of(src);
            check(line_starting(dot, "A -> B ").contains("style=dashed"), "dashed", dot);
            check(!line_starting(dot, "C -> D ").contains("dashed"), "solid", dot);
        }

        // E4: an entity alias keeps the attributes on the entity
        public static void test_e4_entity_alias() {
            string src = "erDiagram\n    CUST[\"Customer Entity\"] {\n      string name\n    }\n    CUST ||--o{ ORD : places\n";
            var d = (MermaidERDiagram) ast_of(src, DiagramType.MERMAID_ER);
            check(d.entities.size == 2, "CUST and ORD only, got %d".printf(d.entities.size));
            var cust = d.find_entity("CUST");
            check(cust.alias == "Customer Entity" && cust.attributes.size == 1 && cust.attributes[0].name == "name",
                  "alias and attribute");
            check(line_starting(dot_of(src), "CUST [").contains("<B>Customer Entity</B>"), "alias rendered");
        }

        // ==================== State ====================

        // S1: [*] inside a composite is that composite's own start/end marker
        public static void test_s1_scoped_markers() {
            string src = "stateDiagram-v2\n    [*] --> A\n    state A {\n      [*] --> A1\n      A1 --> [*]\n    }\n    A --> [*]\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            check(d.transitions[0].from == d.start_state && d.start_state.parent_id == null, "top start");
            check(d.transitions[1].from != d.start_state && d.transitions[1].from.parent_id == "A" &&
                  d.transitions[1].from.state_type == MermaidStateType.START, "inner start");
            check(d.transitions[2].to != d.end_state && d.transitions[2].to.parent_id == "A", "inner end");
            check(d.transitions[3].to == d.end_state, "top end");
        }

        // S2: transitions to/from a composite attach to its cluster border
        public static void test_s2_composite_edges() {
            string src = "stateDiagram-v2\n    X --> B\n    state B {\n      [*] --> B1\n      B1 --> [*]\n    }\n    B --> Y\n";
            string dot = dot_of(src);
            check(!dot.contains("_anchor"), "no anchor node", dot);
            string into = line_starting(dot, "X -> ");
            check(into.contains("lhead=cluster_B"), "lhead: " + into, dot);
            string out_of = line_starting(dot, "____end_B -> Y");
            check(out_of.contains("ltail=cluster_B"), "ltail: " + out_of, dot);
        }

        // S3: a nested composite is one cluster inside its parent, not also a plain state
        public static void test_s3_nested_composite_once() {
            string src = "stateDiagram-v2\n    state Outer {\n      state Inner {\n        x --> y\n      }\n      z --> Inner\n    }\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            check(d.find_state("Inner").parent_id == "Outer", "Inner inside Outer");
            string dot = dot_of(src);
            check(count(dot, "subgraph cluster_Inner") == 1, "one Inner cluster", dot);
            check(line_starting(dot, "Inner [") == "", "Inner is not a node", dot);
            int outer = dot.index_of("subgraph cluster_Outer");
            int inner = dot.index_of("subgraph cluster_Inner");
            int outer_end = dot.index_of("\n  }\n", outer);
            check(outer >= 0 && inner > outer && inner < outer_end, "Inner nested in Outer", dot);
        }

        // S4: notes (single line, left/right, multi-line blocks)
        public static void test_s4_notes() {
            string src = "stateDiagram-v2\n    [*] --> S3\n    S3 --> S4\n    note right of S3 : a note\n" +
                         "    note left of S4\n      line one\n      line two\n    end note\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            check(d.find_state("S3").note == "a note" && d.find_state("S3").note_position == "right", "single-line note");
            check(d.find_state("S4").note == "line one\nline two" && d.find_state("S4").note_position == "left",
                  "multi-line note");
            check(d.find_state("end") == null && d.find_state("note") == null && d.find_state("line") == null,
                  "no ghost states");
            string dot = dot_of(src);
            check(line_starting(dot, "S3_note [").contains("label=\"a note\""), "note node", dot);
            check(line_starting(dot, "S4_note -> S4 ").contains("style=dashed"), "left note link", dot);
        }

        // S5: the end marker is a bullseye, unlike the start marker
        public static void test_s5_end_marker() {
            string dot = dot_of("stateDiagram-v2\n    [*] --> A\n    A --> [*]\n");
            check(line_starting(dot, "____start [").contains("shape=circle"), "start circle", dot);
            check(line_starting(dot, "____end [").contains("shape=doublecircle"), "end bullseye", dot);
        }

        // S6: a <<fork>> declared after its first use stays a bar (Mermaid 11.17 draws a box;
        // gDiagram keeps the author's intent)
        public static void test_s6_fork_after_use() {
            string src = "stateDiagram-v2\n    [*] --> f\n    state f <<fork>>\n    f --> A\n    f --> B\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            check(d.find_state("f").state_type == MermaidStateType.FORK, "fork type");
            check(line_starting(dot_of(src), "f [").contains("shape=box, width=1.5, height=0.1"), "bar");
        }

        // A cycle through a composite keeps source order ("Idle" above the composite it enters)
        public static void test_state_back_edge_order() {
            string src = "stateDiagram-v2\n    [*] --> Idle\n    Idle --> Active : start\n    state Active {\n" +
                         "      [*] --> C\n      C --> [*]\n    }\n    Active --> Idle : reset\n";
            string dot = dot_of(src);
            check(line_starting(dot, "Idle -> ____start_Active").contains("lhead=cluster_Active"), "forward edge", dot);
            string back = line_starting(dot, "Idle -> ____end_Active");
            check(back.contains("dir=back") && back.contains("lhead=cluster_Active"), "reversed back edge: " + back, dot);
        }

        // Front matter title and %% comments
        public static void test_front_matter_and_comments() {
            string src = "---\ntitle: Pets\n---\nclassDiagram\n    %% a comment with Ghost --> Class\n    Animal <|-- Dog %% trailing\n";
            var d = (MermaidClassDiagram) ast_of(src, DiagramType.MERMAID_CLASS);
            check(d.title == "Pets", "title");
            check(d.classes.size == 2 && d.relations.size == 1, "comments ignored");
        }

        // Click regions still map to Mermaid class, entity and state nodes with their lines
        public static void test_click_regions() {
            var eng = new DiagramEngine("dot");
            var r = eng.render(DiagramType.MERMAID_CLASS, DiagramFormat.MERMAID,
                               "classDiagram\n    class Alpha {\n      +run()\n    }\n    Alpha <|-- Beta\n");
            check(r.surface != null, "class surface");
            bool alpha = false, beta = false;
            foreach (var region in eng.last_regions) {
                if (region.name == "Alpha") alpha = region.source_line == 2 && region.width > 20 && region.height > 20;
                if (region.name == "Beta") beta = region.source_line == 5 && region.width > 10;
            }
            check(alpha && beta, "class regions");

            r = eng.render(DiagramType.MERMAID_ER, DiagramFormat.MERMAID,
                           "erDiagram\n    CUSTOMER ||--o{ LINE-ITEM : has\n    CUSTOMER {\n      string name\n    }\n");
            check(r.surface != null, "er surface");
            bool customer = false, item = false;
            foreach (var region in eng.last_regions) {
                if (region.name == "CUSTOMER") customer = region.source_line == 3 && region.width > 20;
                if (region.name == "LINE_ITEM") item = region.source_line == 2 && region.width > 20;
            }
            check(customer && item, "er regions");

            r = eng.render(DiagramType.MERMAID_STATE, DiagramFormat.MERMAID,
                           "stateDiagram-v2\n    [*] --> Idle\n    state Busy {\n      [*] --> Work\n    }\n    Idle --> Busy\n");
            check(r.surface != null, "state surface");
            bool idle = false, work = false;
            foreach (var region in eng.last_regions) {
                if (region.name == "Idle") idle = region.source_line == 2 && region.width > 20;
                if (region.name == "Work") work = region.source_line == 4 && region.width > 20;
            }
            check(idle && work, "state regions (a sub-state inside a cluster too)");
        }

        // ==================== Review round 3 ====================

        // `format` holds one %d so every level gets its own id — repeating the same id
        // makes the nesting collapse and the case stop testing anything
        private static string numbered_lines(string format, int times, bool descending = false) {
            var sb = new StringBuilder();
            for (int i = 0; i < times; i++) {
                sb.append(format.printf(descending ? times - 1 - i : i));
            }
            return sb.str;
        }

        private static string repeat_lines(string line, int times) {
            var sb = new StringBuilder();
            for (int i = 0; i < times; i++) sb.append(line);
            return sb.str;
        }

        /**
         * Deeply nested groups / composites / subgraphs are capped instead of recursing
         * until the stack overflows. Every one of these segfaulted the process before.
         */
        public static void test_deep_nesting_does_not_crash() {
            var engine = new DiagramEngine("dot");

            string block = "block-beta\n" + numbered_lines("block:g%d\n", 6000) +
                           "x[\"leaf\"]\n" + repeat_lines("end\n", 6000);
            var br = engine.parse(block, "x.mmd");
            check(br.ast != null, "block AST");
            string? block_dot = engine.generate_dot(block, "x.mmd", null);
            check(block_dot != null && block_dot.contains("digraph block"), "block DOT after cap");
            check(((MermaidBlock) br.ast).nodes.size > 0, "blocks still parsed");

            string state = "stateDiagram-v2\n" + numbered_lines("state S%d {\n", 12000) +
                           "A --> B\n" + repeat_lines("}\n", 12000);
            check(engine.parse(state, "x.mmd").ast != null, "state AST");
            string? state_dot = engine.generate_dot(state, "x.mmd", null);
            check(state_dot != null && state_dot.contains("digraph G"), "state DOT after cap");
            // Only the first MAX_COMPOSITE_DEPTH levels become clusters
            check(count(state_dot, "subgraph cluster_") <= 256,
                  "composite clusters capped, got %d".printf(count(state_dot, "subgraph cluster_")));

            string flow = "flowchart TD\n" + numbered_lines("subgraph G%d\n", 12000) +
                          "A --> B\n" + repeat_lines("end\n", 12000);
            var fr = engine.parse(flow, "x.mmd");
            check(fr.ast != null, "flowchart AST");
            check(fr.errors != null && fr.errors.size > 0, "nesting limit reported");
            engine.generate_dot(flow, "x.mmd", null);
        }

        // A state description may contain an arrow: "Idle : waits -> ready" is text,
        // not a transition to a state called "ready"
        public static void test_state_description_with_arrow() {
            string src = "stateDiagram-v2\n    Idle : waits -> ready\n    Idle --> Busy\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            check(d.states.size == 2, "Idle and Busy only, got %d".printf(d.states.size));
            check(d.find_state("ready") == null, "no state invented from the description");
            check(d.find_state("Idle").description == "waits -> ready", "full description kept");
            check(d.transitions.size == 1, "one transition, got %d".printf(d.transitions.size));
            string dot = dot_of(src);
            check(line_starting(dot, "Idle [").contains("label=\"waits -> ready\""), "description drawn", dot);

            // A ":::class" shorthand before an arrow is still a transition
            var t = (MermaidStateDiagram) ast_of("stateDiagram-v2\n    classDef hot fill:#f96\n" +
                                                 "    A:::hot --> B\n", DiagramType.MERMAID_STATE);
            check(t.transitions.size == 1 && t.states.size == 2, "shorthand transition unchanged");
            check(t.find_state("A").css_classes.size == 1, "class shorthand applied");
        }

        // Requirement ids keep non-ASCII names apart: "Grüße" and "Größe" collapsed to
        // the same DOT id, so one box vanished and the relationship became a self-loop
        public static void test_requirement_unicode_ids() {
            string src = "requirementDiagram\nrequirement Grüße {\nid: 1\ntext: a\n}\n" +
                         "requirement Größe {\nid: 2\ntext: b\n}\nGrüße - contains -> Größe\n";
            var d = (MermaidRequirement) ast_of(src, DiagramType.MERMAID_REQUIREMENT);
            check(d.elements.size == 2, "two requirements, got %d".printf(d.elements.size));
            string dot = dot_of(src);
            check(count(dot, "[label=<") == 2, "two nodes emitted", dot);
            string edge = "";
            foreach (string line in dot.split("\n")) {
                if (line.contains(" -> ")) edge = line.strip();
            }
            int arrow = edge.index_of(" -> ");
            check(arrow > 0, "relationship edge", dot);
            check(edge.substring(0, arrow) != edge.substring(arrow + 4, edge.index_of(" ", arrow + 4) - arrow - 4),
                  "distinct ids, not a self-loop: " + edge, dot);
        }

        // A block group draws its own label inside its rect, above its children
        public static void test_block_group_label() {
            string src = "block-beta\n    columns 2\n    block:frontend[\"Frontend\"]\n" +
                         "        UI[\"UI Layer\"] API[\"API Client\"]\n    end\n    Ext[\"External\"]\n";
            string dot = dot_of(src);
            string group = line_starting(dot, "\"frontend\"");
            check(group.contains("label=\"Frontend\""), "group label emitted: " + group, dot);
            check(group.contains("labelloc=t"), "label above the children: " + group, dot);
            // The children still sit inside the group box
            double gy = pos_y(group);
            double gh = attr_num(group, "height=") * 72.0;
            double uy = pos_y(line_starting(dot, "\"UI\""));
            check(uy < gy + gh / 2 && uy > gy - gh / 2, "UI inside the group box", dot);
        }

        private static double pos_y(string line) {
            int at = line.index_of("pos=\"");
            if (at < 0) return 0;
            string v = line.substring(at + 5);
            int comma = v.index_of(",");
            return double.parse(v.substring(comma + 1, v.index_of("!") - comma - 1));
        }

        private static double attr_num(string line, string key) {
            int at = line.index_of(key);
            if (at < 0) return 0;
            string v = line.substring(at + key.length);
            int sp = v.index_of(" ");
            return double.parse(sp > 0 ? v.substring(0, sp) : v);
        }

        // A "%%{init}%%" directive spanning several lines is skipped whole: its body used
        // to leak in as blocks, which also hid the "block-beta" header
        public static void test_block_multiline_directive() {
            string src = "%%{init: {\n  \"theme\": \"dark\"\n}}%%\nblock-beta\ncolumns 2\na[\"A\"] b[\"B\"]\n";
            var d = (MermaidBlock) ast_of(src, DiagramType.MERMAID_BLOCK);
            check(d.nodes.size == 2, "two blocks, got %d".printf(d.nodes.size));
            check(d.find_node("a") != null && d.find_node("b") != null, "a and b");
            check(d.find_node("theme") == null && d.find_node("dark") == null, "no directive leftovers");
            check(d.columns == 2, "columns read after the directive, got %d".printf(d.columns));

            // Same for requirement diagrams. The nested "{" line inside the directive is
            // what used to be read as an element header.
            var r = (MermaidRequirement) ast_of(
                "%%{init: {\n  \"theme\": \"base\",\n  \"theme variables\": {\n" +
                "    \"primaryColor\": \"#ff0000\"\n  }\n}}%%\n" +
                "requirementDiagram\nrequirement R {\nid: 1\ntext: only one\n}\n",
                DiagramType.MERMAID_REQUIREMENT);
            check(r.elements.size == 1, "one requirement, got %d".printf(r.elements.size));
            check(r.elements[0].name == "R" && r.elements[0].text == "only one", "the real one");
        }

        // A mid-word "%%" is text, not a comment: Mermaid keeps "50%% complete"
        public static void test_percent_in_text() {
            var s = (MermaidStateDiagram) ast_of("stateDiagram-v2\n    A : 50%% complete\n" +
                                                 "    B : done %% trailing\n", DiagramType.MERMAID_STATE);
            check(s.find_state("A").description == "50%% complete",
                  "percent kept: " + (s.find_state("A").description ?? "null"));
            check(s.find_state("B").description == "done", "a trailing comment is still cut");

            var c = (MermaidClassDiagram) ast_of("classDiagram\n    class A {\n      +note 100%% sure\n    }\n",
                                                 DiagramType.MERMAID_CLASS);
            check(c.find_class("A").members.size == 1, "one member");
            check(c.find_class("A").members[0].display_text.contains("100%% sure"),
                  "percent kept in a member: " + c.find_class("A").members[0].display_text);
        }

        // index_unquoted() was quadratic per line: one long line took seconds on the
        // per-keystroke parse path
        public static void test_long_line_parse_is_linear() {
            // No arrow on the line, so the scan runs to the end — the worst case
            var sb = new StringBuilder("stateDiagram-v2\n    A : ");
            for (int i = 0; i < 80000; i++) sb.append("word ");
            sb.append("\n");
            var timer = new Timer();
            var d = (MermaidStateDiagram) ast_of(sb.str, DiagramType.MERMAID_STATE);
            double elapsed = timer.elapsed();
            check(d.states.size == 1, "one state");
            check(d.find_state("A").description.length > 399000, "the whole description is kept");
            check(elapsed < 2.0, "400 KB line parsed in %.2fs (was 10.3s)".printf(elapsed));
        }

        /**
         * The block link matcher, the requirement relationship matcher and the lexer's
         * entity decoder now compile their Regex once into a static instead of on every
         * call. A cached pattern that is never initialised, or one whose MatchInfo is
         * reused across calls, would show up as wrong counts here — the two parsers are
         * run twice so the second pass exercises the already-filled cache.
         */
        public static void test_cached_regexes_still_match() {
            var engine = new DiagramEngine("dot");

            var block = new StringBuilder("block-beta\n  columns 2\n");
            for (int i = 0; i < 500; i++) block.append_printf("  a%d --> b%d\n", i, i);
            for (int pass = 0; pass < 2; pass++) {
                var b = (MermaidBlock) engine.parse(block.str, "x.mmd").ast;
                check(b.edges.size == 500, "500 block links, got %d".printf(b.edges.size));
            }
            // A labelled link uses the other cached pattern
            var lb = (MermaidBlock) engine.parse("block-beta\n  a -- \"x\" --> b\n", "x.mmd").ast;
            check(lb.edges.size == 1 && lb.edges[0].label == "x", "labelled block link");

            var req = new StringBuilder("requirementDiagram\n");
            for (int i = 0; i < 500; i++) req.append_printf("r%d - satisfies -> e%d\n", i, i);
            for (int pass = 0; pass < 2; pass++) {
                var r = (MermaidRequirement) engine.parse(req.str, "x.mmd").ast;
                check(r.relationships.size == 500, "500 relationships, got %d".printf(r.relationships.size));
                check(r.relationships[499].source == "r499" && r.relationships[499].target == "e499",
                      "the last relationship still reads its own captures");
            }

            // decode_entities() runs in the flowchart renderer, once per label
            string flow_dot = dot_of("flowchart TD\n  n1[\"a #quot;b#quot; c\"]\n  n2[\"#9829; #x2665;\"]\n");
            check(line_starting(flow_dot, "n1 [").contains("a \\\"b\\\" c"),
                  "entity codes decoded", flow_dot);
            check(line_starting(flow_dot, "n2 [").contains("♥ ♥"), "numeric entity codes", flow_dot);
        }

        // Requirement diagrams honour front matter, direction, classDef/class and style
        public static void test_requirement_direction_and_styles() {
            string src = "---\ntitle: My Reqs\n---\nrequirementDiagram\ndirection LR\n" +
                         "requirement R1 {\nid: 1\ntext: first\n}\nelement E1 {\ntype: doc\n}\n" +
                         "classDef hot fill:#f96,stroke:#333\nclass R1 hot\nstyle E1 fill:#9f9\n" +
                         "R1 - traces -> E1\n";
            var d = (MermaidRequirement) ast_of(src, DiagramType.MERMAID_REQUIREMENT);
            check(d.title == "My Reqs", "front matter title: " + (d.title ?? "null"));
            check(d.direction == FlowchartDirection.LEFT_RIGHT, "direction LR");
            check(d.elements.size == 2 && d.relationships.size == 1, "two elements, one relation");
            string dot = dot_of(src);
            check(line_starting(dot, "rankdir=").contains("LR"), "rankdir=LR", dot);
            check(dot.contains("label=\"My Reqs\""), "title drawn", dot);
            check(line_starting(dot, "r_R1 [").contains("BGCOLOR=\"#f96\"") &&
                  line_starting(dot, "r_R1 [").contains("COLOR=\"#333\""), "classDef applied", dot);
            check(line_starting(dot, "r_E1 [").contains("BGCOLOR=\"#9f9\""), "style applied", dot);
        }

        // Invalid input is reported instead of inventing elements
        public static void test_invalid_input_reports_errors() {
            var engine = new DiagramEngine("dot");

            // "A ---> B": Mermaid errors; gDiagram made a class called "-"
            var r = engine.parse("classDiagram\n    A ---> B\n", "x.mmd");
            var cls = (MermaidClassDiagram) r.ast;
            check(r.errors != null && r.errors.size == 1, "one class error");
            check(cls.find_class("-") == null, "no class named '-'");
            check(cls.classes.size == 0 && cls.relations.size == 0, "no elements from the bad line");
            // The valid two-dash form is untouched
            var ok = (MermaidClassDiagram) ast_of("classDiagram\n    A --> B\n", DiagramType.MERMAID_CLASS);
            check(ok.classes.size == 2 && ok.relations.size == 1, "'-->' still works");

            // "a[\"unclosed": Mermaid errors; gDiagram invented a block called "unclosed"
            var b = engine.parse("block-beta\n    a[\"unclosed\n", "x.mmd");
            var block = (MermaidBlock) b.ast;
            check(b.errors != null && b.errors.size == 1, "one block error");
            check(block.find_node("unclosed") == null, "no block from the leftover text");
            check(block.nodes.size == 0, "no blocks at all, got %d".printf(block.nodes.size));

            // Bare backticks are literal text in Mermaid, not a markdown string
            var f = (MermaidFlowchart) ast_of("flowchart TD\n    A[`text`]\n", DiagramType.MERMAID_FLOWCHART);
            check(f.nodes.size == 1, "one node");
            check(f.nodes[0].text == "`text`", "backticks kept: " + f.nodes[0].text);
            check(!f.nodes[0].markdown, "not a markdown string");
            // Backticks inside a quoted label still are one
            var md = (MermaidFlowchart) ast_of("flowchart TD\n    A[\"`**b** x`\"]\n", DiagramType.MERMAID_FLOWCHART);
            check(md.nodes[0].markdown && md.nodes[0].text == "**b** x", "quoted markdown string still works");
        }

        // A composite state is a pastel container (Mermaid's #ECECFF), not a saturated fill
        public static void test_composite_state_pastel_fill() {
            string src = "stateDiagram-v2\n    state Active {\n        A --> B: inner\n    }\n";
            var saved = ThemeManager.get_active_palette();
            foreach (string preset in new string[] { "default-light", "default-dark" }) {
                var palette = ThemeManager.get_preset(preset);
                ThemeManager.set_active_palette(palette);
                string dot = dot_of(src);
                string fill = line_starting(dot, "fillcolor=");
                check(!fill.contains(palette.success), preset + ": not the saturated success colour", dot);
                // A tint of the container colour over the canvas: close to the background
                check(near(fill, palette.background, 60), preset + ": pastel tint " + fill, dot);
                // and clearly not the canvas itself, so the container is still visible
                check(!near(fill, palette.background, 8), preset + ": still distinguishable " + fill, dot);
            }
            ThemeManager.set_active_palette(saved);
        }

        // |fill - reference| per channel below `tol`
        private static bool near(string line, string reference, int tol) {
            int at = line.index_of("\"");
            if (at < 0) return false;
            string hex = line.substring(at + 1, 7);
            for (int c = 0; c < 3; c++) {
                int a = (int) uint64.parse(hex.substring(1 + c * 2, 2), 16);
                int b = (int) uint64.parse(reference.substring(1 + c * 2, 2), 16);
                if ((a - b).abs() > tol) return false;
            }
            return true;
        }

        // Truncated / malformed statements neither crash nor loop in the line parsers
        public static void test_malformed_inputs() {
            string[] inputs = {
                "classDiagram\n    class", "classDiagram\n    A <|--", "classDiagram\n    A \"1", "classDiagram\n    class A~",
                "classDiagram\n    class A[\"x", "classDiagram\n    `A", "classDiagram\n    note for", "classDiagram\n    <<",
                "classDiagram\n    A : +f(", "classDiagram\n    A : )x(", "classDiagram\n    namespace X {\n    }\n    }",
                "classDiagram\n    class A {\n    +x\n", "classDiagram\n    A~~ -- B", "classDiagram\n    ~",
                "erDiagram\n    A {", "erDiagram\n    A ||--", "erDiagram\n    \"A", "erDiagram\n    A[\"x\" {\n",
                "erDiagram\n    A {\n      \"c\"\n    }", "erDiagram\n    A only one to",
                "stateDiagram-v2\n    state \"x", "stateDiagram-v2\n    -->", "stateDiagram-v2\n    [*] -->",
                "stateDiagram-v2\n    note left of", "stateDiagram-v2\n    note right of A\n    text",
                "stateDiagram-v2\n    state A {\n      state A {\n        x --> y\n      }\n    }",
                "stateDiagram-v2\n    state A {\n      state B {\n      }\n    }\n    state B {\n      state A {\n        q --> r\n      }\n    }\n    A --> B",
                "stateDiagram-v2\n    }\n    }\n    A:::", "stateDiagram-v2\n    class", "stateDiagram-v2\n    style A"
            };
            var engine = new DiagramEngine("dot");
            var timer = new Timer();
            foreach (string src in inputs) {
                var r = engine.parse(src, "x.mmd");
                check(r.ast != null, "AST for malformed input", src);
                engine.generate_dot(src, "x.mmd", null);
            }
            // A parser that loops or backtracks on a truncated statement shows up here:
            // all 30 inputs are two or three short lines
            check(timer.elapsed() < 5.0,
                  "malformed inputs parsed in %.2fs".printf(timer.elapsed()));

            // Asserting only "the AST is not null" passed with every parsing fix
            // reverted, so pin what each truncated statement must yield.
            var c1 = (MermaidClassDiagram) engine.parse("classDiagram\n    A <|--", "x.mmd").ast;
            check(c1.relations.size == 0 && c1.classes.size <= 1,
                  "a relation without a target makes no relation, got %d/%d".printf(c1.classes.size, c1.relations.size));

            // "A~~ -- B": the empty generic is not closed, so the line is no relation and
            // only A is declared — B must not appear
            var c2 = (MermaidClassDiagram) engine.parse("classDiagram\n    A~~ -- B", "x.mmd").ast;
            check(c2.classes.size == 1 && c2.relations.size == 0,
                  "unterminated generic: A only, got %d/%d".printf(c2.classes.size, c2.relations.size));

            var c3 = (MermaidClassDiagram) engine.parse("classDiagram\n    class A {\n    +x\n", "x.mmd").ast;
            check(c3.classes.size == 1 && c3.find_class("A").members.size == 1,
                  "an unclosed class body still holds its member");

            var e1 = (MermaidERDiagram) engine.parse("erDiagram\n    A ||--", "x.mmd").ast;
            check(e1.relationships.size == 0, "no ER relationship without a target");

            var e2 = (MermaidERDiagram) engine.parse("erDiagram\n    A {\n      \"c\"\n    }", "x.mmd").ast;
            check(e2.entities.size == 1, "one entity, got %d".printf(e2.entities.size));

            var s1 = (MermaidStateDiagram) engine.parse("stateDiagram-v2\n    [*] -->", "x.mmd").ast;
            check(s1.transitions.size == 0, "no transition without a target, got %d".printf(s1.transitions.size));

            var s2 = (MermaidStateDiagram) engine.parse(
                "stateDiagram-v2\n    state A {\n      state A {\n        x --> y\n      }\n    }", "x.mmd").ast;
            check(s2.find_state("A") != null && s2.find_state("A").parent_id == null,
                  "a composite re-opened inside itself stays top level");
            check(s2.transitions.size == 1, "the inner transition survives");

            var s3 = (MermaidStateDiagram) engine.parse("stateDiagram-v2\n    }\n    }\n    A:::", "x.mmd").ast;
            check(s3.states.size == 1 && s3.find_state("A") != null,
                  "stray closers ignored, A kept, got %d".printf(s3.states.size));

            var s4 = (MermaidStateDiagram) engine.parse(
                "stateDiagram-v2\n    note right of A\n    text", "x.mmd").ast;
            check(s4.find_state("A") != null && s4.find_state("A").note == "text",
                  "an unterminated note block still attaches its text");
        }

        // Validator: entering a composite reaches its own [*] marker and the states after it
        public static void test_validator_composite_reachability() {
            string src = "stateDiagram-v2\n    [*] --> Active\n    state Active {\n        [*] --> Inner\n" +
                         "        Inner --> Deep\n    }\n    state Loose {\n        Solo --> Solo2\n    }\n" +
                         "    Active --> Loose\n    Active --> [*]\n    Orphan --> Active\n";
            var d = (MermaidStateDiagram) ast_of(src, DiagramType.MERMAID_STATE);
            var v = new DiagramValidator();
            v.validate_state(d);
            var unreachable = new StringBuilder();
            foreach (var m in v.messages) {
                if (m.message.contains("unreachable")) unreachable.append(m.message + "\n");
            }
            string got = unreachable.str;
            check(!got.contains("'Inner'") && !got.contains("'Deep'"), "composite sub-states reachable", got);
            check(!got.contains("'Solo'") && !got.contains("'Solo2'"), "sub-states of a composite without [*] reachable", got);
            check(got.contains("'Orphan'"), "a real unreachable state is still reported", got);
        }

        // Labels between sub-states contrast with the composite fill in both themes
        public static void test_state_label_on_composite_fill() {
            string src = "stateDiagram-v2\n    state Active {\n        A --> B: inner\n    }\n    Active --> C: outer\n";
            var saved = ThemeManager.get_active_palette();
            foreach (string preset in new string[] { "default-light", "default-dark" }) {
                var palette = ThemeManager.get_preset(preset);
                ThemeManager.set_active_palette(palette);
                string dot = dot_of(src);
                string inner = line_starting(dot, "A -> B");
                // The label sits on the composite's own (pastel) fill, whatever it is
                string fill = line_starting(dot, "fillcolor=");
                int q = fill.index_of("\"");
                string want = "fontcolor=\"%s\"".printf(
                    RenderUtils.contrast_text(fill.substring(q + 1, 7)));
                check(inner.contains(want), preset + ": inner label uses " + want, inner + "\n" + dot);
            }
            ThemeManager.set_active_palette(saved);
        }

        public static int main(string[] args) {
            Test.init(ref args);
            Test.add_func("/review-mermaid-structural/malformed-inputs", test_malformed_inputs);
            Test.add_func("/review-mermaid-structural/c1/relation-types", test_c1_relation_types);
            Test.add_func("/review-mermaid-structural/c2/generics", test_c2_generics);
            Test.add_func("/review-mermaid-structural/c3/inheritance-direction", test_c3_inheritance_direction);
            Test.add_func("/review-mermaid-structural/c4/colon-member-and-label", test_c4_colon_member_and_label);
            Test.add_func("/review-mermaid-structural/c4/styles", test_c4_styles);
            Test.add_func("/review-mermaid-structural/c4/notes", test_c4_notes);
            Test.add_func("/review-mermaid-structural/c5/method-signatures", test_c5_method_signatures);
            Test.add_func("/review-mermaid-structural/c6/annotations-direction", test_c6_annotations_direction);
            Test.add_func("/review-mermaid-structural/e1/keyword-attribute-names", test_e1_keyword_attribute_names);
            Test.add_func("/review-mermaid-structural/e2/keys-and-comments", test_e2_keys_and_comments);
            Test.add_func("/review-mermaid-structural/e3/non-identifying-dashed", test_e3_non_identifying_dashed);
            Test.add_func("/review-mermaid-structural/e4/entity-alias", test_e4_entity_alias);
            Test.add_func("/review-mermaid-structural/s1/scoped-markers", test_s1_scoped_markers);
            Test.add_func("/review-mermaid-structural/s2/composite-edges", test_s2_composite_edges);
            Test.add_func("/review-mermaid-structural/s3/nested-composite-once", test_s3_nested_composite_once);
            Test.add_func("/review-mermaid-structural/s4/notes", test_s4_notes);
            Test.add_func("/review-mermaid-structural/s5/end-marker", test_s5_end_marker);
            Test.add_func("/review-mermaid-structural/s6/fork-after-use", test_s6_fork_after_use);
            Test.add_func("/review-mermaid-structural/state/back-edge-order", test_state_back_edge_order);
            Test.add_func("/review-mermaid-structural/front-matter-and-comments", test_front_matter_and_comments);
            Test.add_func("/review-mermaid-structural/click-regions", test_click_regions);
            Test.add_func("/review-mermaid-structural/state/label-on-composite-fill", test_state_label_on_composite_fill);
            Test.add_func("/review-mermaid-structural/validator/composite-reachability", test_validator_composite_reachability);
            Test.add_func("/review-mermaid-structural/deep-nesting-no-crash", test_deep_nesting_does_not_crash);
            Test.add_func("/review-mermaid-structural/state/description-with-arrow", test_state_description_with_arrow);
            Test.add_func("/review-mermaid-structural/requirement/unicode-ids", test_requirement_unicode_ids);
            Test.add_func("/review-mermaid-structural/block/group-label", test_block_group_label);
            Test.add_func("/review-mermaid-structural/block/multiline-directive", test_block_multiline_directive);
            Test.add_func("/review-mermaid-structural/percent-in-text", test_percent_in_text);
            Test.add_func("/review-mermaid-structural/long-line-parse", test_long_line_parse_is_linear);
            Test.add_func("/review-mermaid-structural/cached-regexes", test_cached_regexes_still_match);
            Test.add_func("/review-mermaid-structural/requirement/direction-and-styles",
                          test_requirement_direction_and_styles);
            Test.add_func("/review-mermaid-structural/invalid-input-errors", test_invalid_input_reports_errors);
            Test.add_func("/review-mermaid-structural/state/composite-pastel-fill", test_composite_state_pastel_fill);
            return Test.run();
        }
    }
}
