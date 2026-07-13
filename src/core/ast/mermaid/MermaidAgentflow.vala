namespace GDiagram {

    // ==================== MERMAID AGENTFLOW ====================
    //
    // Mermaid 12.2.0's `agentflow-beta`: an agent-workflow graph of nodes and edges.
    //
    // Its grammar is mermaid's *flowchart* jison grammar, forked and then narrowed —
    // verified against the generated parser shipped in mermaid 12.2.0
    // (diagrams/agentflow/parser/agentflow.jison). The differences from flowchart,
    // and the whole of what makes agentflow its own diagram type, are:
    //
    //   * header `agentflow-beta` (+ an optional direction) instead of `flowchart`
    //   * `flow <id>[<title>] … end` containers instead of `subgraph … end`
    //   * `global … end`, a block that exempts the ids inside it from container
    //     membership so they stay drawn at top level
    //   * `connector <id>[<title>]`, a node of its own kind
    //   * a *narrowed* edge-operator set: only `-->`/`--->`…, `--x`/`---x`… and
    //     `-.-`/`-..-`… are lexable. `==>`, `~~~`, `-.->` and `--o` are hard syntax
    //     errors in agentflow, where flowchart accepts them.
    //   * a restricted shape vocabulary with author-friendly aliases, and a colour
    //     per node *kind* rather than per shape.
    //
    // Because it is structurally a flowchart, MermaidAgentflow extends
    // MermaidFlowchart and the parser and renderer extend the flowchart ones rather
    // than forking them. What is agentflow-only lives here: the kind of each node,
    // the global-node and collapsed-container sets, the container declaration order
    // that drives container colours, and the shape diagnostics.

    /**
     * `vertexKind` — agentflow's seven node kinds.
     *
     * mermaid derives the kind from the resolved shape on every read
     * (`agentflowDb.deriveVertexKind`) rather than storing it, in this precedence:
     * a tool shape first, then hexagon → action, lean-right → input,
     * lin-doc → refdoc, diamond → decision, everything else → task. A node declared
     * by the `connector` statement reports CONNECTOR ahead of all of that — a
     * connector and a task are both drawn as a rounded rectangle, so the kind cannot
     * be read back off the shape.
     *
     * The slot numbers are mermaid's fixed palette slots (`colorSlots.KIND_SLOT`), so
     * a tool is the same colour in every diagram.
     */
    public enum AgentflowKind {
        TOOL,       // slot 0
        TASK,       // slot 1
        DECISION,   // slot 2
        INPUT,      // slot 3
        REFDOC,     // slot 4
        CONNECTOR,  // slot 5
        ACTION;     // slot 6

        public int slot() {
            switch (this) {
                case AgentflowKind.TOOL:      return 0;
                case AgentflowKind.TASK:      return 1;
                case AgentflowKind.DECISION:  return 2;
                case AgentflowKind.INPUT:     return 3;
                case AgentflowKind.REFDOC:    return 4;
                case AgentflowKind.CONNECTOR: return 5;
                default:                      return 6;
            }
        }

        public string name_of() {
            switch (this) {
                case AgentflowKind.TOOL:      return "tool";
                case AgentflowKind.TASK:      return "task";
                case AgentflowKind.DECISION:  return "decision";
                case AgentflowKind.INPUT:     return "input";
                case AgentflowKind.REFDOC:    return "refdoc";
                case AgentflowKind.CONNECTOR: return "connector";
                default:                      return "action";
            }
        }

        /**
         * Stroke colour, read out of mermaid 12.2.0's own rendered stylesheet for the
         * default theme (`borderColorArray` slot of this kind).
         */
        public string stroke_color() {
            return AgentflowPalette.BORDER[slot()];
        }

        /** Fill colour — the matching `bkgColorArray` slot. */
        public string fill_color() {
            return AgentflowPalette.BACKGROUND[slot()];
        }
    }

    /**
     * The 12-colour palette mermaid's default theme hands agentflow, measured from a
     * rendered agentflow SVG (mermaid 12.2.0, default theme, `neo` look).
     *
     * Slots 0..6 are owned by the node kinds; containers cycle slots 7..11 in
     * declaration order, which is why a container frame can never take the colour of
     * a node inside it.
     */
    namespace AgentflowPalette {
        public const string[] BORDER = {
            "#E879F9",  // 0 tool
            "#2DD4BF",  // 1 task
            "#FB923C",  // 2 decision
            "#22D3EE",  // 3 input
            "#4ADE80",  // 4 refdoc
            "#A78BFA",  // 5 connector
            "#F87171",  // 6 action
            "#FACC15",  // 7 container
            "#818CF8",  // 8 container
            "#A3E635",  // 9 container
            "#38BDF8",  // 10 container
            "#FB7185"   // 11 container
        };
        public const string[] BACKGROUND = {
            "#FDF4FF", "#F0FDFA", "#FFF7ED", "#ECFEFF", "#F0FDF4", "#F5F3FF",
            "#FEF2F2", "#FEFCE8", "#EEF2FF", "#F7FEE7", "#F0F9FF", "#FFF1F2"
        };

        /** Slots reserved for the node kinds; containers start above this. */
        public const int KIND_COUNT = 7;

        /** `colorSlots.containerSlot`: the slot for the n-th container, in source order. */
        public int container_slot(int n) {
            int span = BORDER.length - KIND_COUNT;
            if (span < 1) span = 1;
            return (KIND_COUNT + (n % span)) % BORDER.length;
        }
    }

    /** Severity of an agentflow shape diagnostic. */
    public enum AgentflowSeverity {
        WARNING,
        ERROR
    }

    /**
     * A recoverable agentflow diagnostic.
     *
     * Only the three diagnostics mermaid's parser actually emits are modelled —
     * `SHAPE_REMOVED`, `SHAPE_UNSUPPORTED` and `CONTAINMENT_VIOLATION`. The other
     * nine ids in mermaid's `AgentflowWarning` enum are reserved and never emitted by
     * any code path in 12.2.0.
     *
     * All three are recoverable: the drawing continues with a coerced value. They are
     * deliberately kept off `MermaidFlowchart.errors`, which the engine treats as a
     * parse failure — a removed shape must still draw.
     */
    public class AgentflowDiagnostic : Object {
        public string id { get; set; }
        public AgentflowSeverity severity { get; set; }
        public string message { get; set; }
        public string? node_id { get; set; }
        public int source_line { get; set; }

        public AgentflowDiagnostic(string id, AgentflowSeverity severity, string message,
                                   string? node_id, int line) {
            this.id = id;
            this.severity = severity;
            this.message = message;
            this.node_id = node_id;
            this.source_line = line;
        }
    }

    public class MermaidAgentflow : MermaidFlowchart {
        /** Node id → kind. A node absent from the map is a TASK (mermaid's fallback). */
        public Gee.HashMap<string, AgentflowKind> kinds { get; private set; }
        /** Ids declared inside a `global … end` block: never adopted by a container. */
        public Gee.HashSet<string> global_nodes { get; private set; }
        /** Ids declared by a `connector` statement. */
        public Gee.HashSet<string> connectors { get; private set; }
        /** Containers carrying `@{ view: collapsed }`. */
        public Gee.HashSet<string> collapsed { get; private set; }
        /** Container id → declaration order, which drives the container colour cycle. */
        public Gee.HashMap<string, int> container_order { get; private set; }
        public Gee.ArrayList<AgentflowDiagnostic> diagnostics { get; private set; }

        public MermaidAgentflow() {
            base(MermaidDiagramType.AGENTFLOW);
            this.kinds = new Gee.HashMap<string, AgentflowKind>();
            this.global_nodes = new Gee.HashSet<string>();
            this.connectors = new Gee.HashSet<string>();
            this.collapsed = new Gee.HashSet<string>();
            this.container_order = new Gee.HashMap<string, int>();
            this.diagnostics = new Gee.ArrayList<AgentflowDiagnostic>();
        }

        public AgentflowKind kind_of(string node_id) {
            if (connectors.contains(node_id)) return AgentflowKind.CONNECTOR;
            if (kinds.has_key(node_id)) return kinds.get(node_id);
            return AgentflowKind.TASK;
        }

        public void add_diagnostic(string id, AgentflowSeverity severity, string message,
                                   string? node_id, int line) {
            // getData() is idempotent in mermaid and may run twice, so it de-duplicates
            // on (id, severity, message, nodeId). Same here, for the same reason.
            foreach (var d in diagnostics) {
                if (d.id == id && d.severity == severity && d.message == message &&
                    d.node_id == node_id) {
                    return;
                }
            }
            diagnostics.add(new AgentflowDiagnostic(id, severity, message, node_id, line));
        }
    }

    /**
     * Agentflow's shape vocabulary — a direct port of mermaid 12.2.0's
     * `diagrams/agentflow/shapes.ts`, which is that file's stated single source of
     * truth for the v0.8.1 aliases, the shapes it removed, and the shapes it allows.
     */
    namespace AgentflowShapes {
        public const string DEFAULT_SHAPE = "roundedRect";

        /** v0.8.1 author-friendly aliases → canonical mermaid shape ids. */
        public static string? resolve_alias(string? shape) {
            if (shape == null) return null;
            switch (shape) {
                case "task":     return "roundedRect";
                case "tool":     return "subroutine";
                case "input":    return "lean-right";
                case "decision": return "diamond";
                case "refdoc":   return "lin-doc";
                case "action":   return "hexagon";
                case "round":    return "rect";
                default:         return shape;
            }
        }

        /** Shapes removed in v0.8.1: authoring one is an error, coerced to the default. */
        public static bool is_removed(string shape) {
            switch (shape) {
                case "doc": case "stadium": case "terminal": case "circle":
                case "trapezoid": case "inv_trapezoid": case "inv-trapezoid":
                case "doublecircle": case "double-circle": case "typeDeclaration":
                case "procs": case "lean_left": case "lean-left": case "in-out":
                case "cylinder": case "ellipse": case "odd":
                // Instance shapes — the instancing mechanism was removed entirely.
                case "tag-rect": case "tagged-rectangle": case "delay":
                case "half-rounded-rectangle": case "lin-rect": case "lined-rectangle":
                case "win-pane": case "window-pane": case "curv-trap":
                case "curved-trapezoid":
                    return true;
                default:
                    return false;
            }
        }

        /**
         * Shapes the spec allows, as canonical ids after alias resolution.
         * `rect`/`squareRect` are normalised to the default before this is consulted,
         * so they are deliberately not listed.
         */
        public static bool is_allowed(string shape) {
            switch (shape) {
                case "roundedRect": case "subroutine": case "subprocess": case "subproc":
                case "framed-rectangle": case "lean-right": case "diamond":
                case "lin-doc": case "lined-document": case "hexagon": case "hex":
                case "connector": case "collapsedGroup":
                    return true;
                default:
                    return false;
            }
        }

        /**
         * The shapes `isToolDefinition` recognises, tested against the *raw* authored
         * type rather than the resolved one.
         */
        public static bool is_tool_shape(string? raw) {
            if (raw == null) return false;
            switch (raw) {
                case "subroutine": case "subprocess": case "subproc":
                case "framed-rectangle": case "tool":
                    return true;
                default:
                    return false;
            }
        }

        /**
         * `deriveVertexKind`: the kind of a node, from its raw authored shape and the
         * alias-resolved one. Mirrors mermaid's precedence exactly.
         */
        public static AgentflowKind derive_kind(string? raw_shape, string? resolved) {
            if (is_tool_shape(raw_shape)) return AgentflowKind.TOOL;
            if (resolved == null) return AgentflowKind.TASK;
            switch (resolved) {
                case "hexagon": case "hex":          return AgentflowKind.ACTION;
                case "lean-right": case "lean_right": return AgentflowKind.INPUT;
                case "lin-doc": case "lined-document": return AgentflowKind.REFDOC;
                case "diamond":                      return AgentflowKind.DECISION;
                default:                             return AgentflowKind.TASK;
            }
        }
    }

}
