namespace GDiagram {

    /**
     * Mermaid 12.2.0 `agentflow-beta`.
     *
     * agentflow's grammar is mermaid's flowchart grammar, forked and narrowed, so the
     * work is done by MermaidFlowchartParser's agentflow mode rather than by a second
     * copy of 1400 lines of bracket-shape and link scanning. This class is the
     * per-type entry point the engine owns, matching every other Mermaid parser here.
     *
     * What the agentflow mode adds is listed on MermaidAgentflow; the sites that
     * implement it are all marked "agentflow:" in MermaidFlowchartParser.
     */
    public class MermaidAgentflowParser : Object {
        private MermaidFlowchartParser inner;

        public MermaidAgentflowParser() {
            this.inner = new MermaidFlowchartParser();
        }

        public MermaidAgentflow parse(string source) {
            return inner.parse_agentflow(source);
        }
    }

}
