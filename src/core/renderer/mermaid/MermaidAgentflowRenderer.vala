namespace GDiagram {

    /**
     * Mermaid 12.2.0 `agentflow-beta`.
     *
     * Agentflow is a node-and-edge graph drawn through mermaid's *flowchart*
     * pipeline — its own renderer (`diagrams/agentflow/renderer.ts`) hands
     * `getData()` straight to the shared flowchart layout and only adds a title and
     * a stylesheet. This renderer does the same thing with gDiagram's flowchart
     * renderer: it extends MermaidFlowchartRenderer and adds exactly the two things
     * agentflow adds, both of which the flowchart renderer already knows how to draw
     * once the AST carries them:
     *
     *  1. a colour per node *kind* (not per shape), from a fixed palette slot, and
     *  2. a colour per container, cycling the slots above the kind range in
     *     declaration order so a frame never takes the colour of a node inside it.
     *
     * The colours are written onto the AST's own `fill_color` / `stroke_color`
     * fields, and only where they are still unset. That reproduces mermaid's
     * precedence for free: mermaid deliberately does *not* mark the palette rules
     * `!important`, so a node carrying `classDef` or `style` — which the parser has
     * already turned into those same fields — keeps winning over the palette.
     */
    public class MermaidAgentflowRenderer : MermaidFlowchartRenderer {

        public MermaidAgentflowRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions,
                                        string engine) {
            base(ctx, regions, engine);
        }

        /**
         * Paints the kind and container palettes onto the diagram.
         *
         * Idempotent: it only ever fills a null field, so running it again before a
         * second render changes nothing.
         */
        private static void apply_palette(MermaidAgentflow diagram) {
            foreach (var node in diagram.nodes) {
                var kind = diagram.kind_of(node.id);
                if (node.fill_color == null || node.fill_color.length == 0) {
                    node.fill_color = kind.fill_color();
                }
                if (node.stroke_color == null || node.stroke_color.length == 0) {
                    node.stroke_color = kind.stroke_color();
                }
            }
            apply_container_palette(diagram, diagram.subgraphs);
        }

        private static void apply_container_palette(MermaidAgentflow diagram,
                                                    Gee.List<FlowchartSubgraph> list) {
            foreach (var sg in list) {
                int order = diagram.container_order.has_key(sg.id)
                    ? diagram.container_order.get(sg.id) : 0;
                int slot = AgentflowPalette.container_slot(order);
                if (sg.fill_color == null || sg.fill_color.length == 0) {
                    sg.fill_color = AgentflowPalette.BACKGROUND[slot];
                }
                if (sg.stroke_color == null || sg.stroke_color.length == 0) {
                    sg.stroke_color = AgentflowPalette.BORDER[slot];
                }
                apply_container_palette(diagram, sg.subgraphs);
            }
        }

        public string generate_agentflow_dot(MermaidAgentflow diagram) {
            apply_palette(diagram);
            return generate_dot(diagram);
        }

        public uint8[]? render_agentflow_to_svg(MermaidAgentflow diagram) {
            apply_palette(diagram);
            return render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_agentflow_to_surface(MermaidAgentflow diagram) {
            apply_palette(diagram);
            return render_to_surface(diagram);
        }

        public bool export_agentflow_to_png(MermaidAgentflow diagram, string filename) {
            apply_palette(diagram);
            return export_to_png(diagram, filename);
        }

        public bool export_agentflow_to_svg(MermaidAgentflow diagram, string filename) {
            apply_palette(diagram);
            return export_to_svg(diagram, filename);
        }

        public bool export_agentflow_to_pdf(MermaidAgentflow diagram, string filename) {
            apply_palette(diagram);
            return export_to_pdf(diagram, filename);
        }
    }

}
