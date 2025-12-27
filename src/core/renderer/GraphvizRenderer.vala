namespace GDiagram {
    // Facade pattern: GraphvizRenderer delegates to specialized diagram renderers
    public class GraphvizRenderer : Object {
        private Gvc.Context context;

        // Stores element regions from last render for click navigation
        public Gee.ArrayList<ElementRegion> last_regions { get; private set; }

        // Layout engine to use (dot, neato, fdp, sfdp, circo, twopi)
        public string layout_engine { get; set; default = "dot"; }

        // Available layout engines
        public static string[] LAYOUT_ENGINES = { "dot", "neato", "fdp", "sfdp", "circo", "twopi" };

        // Specialized renderers for each diagram type
        private SequenceDiagramRenderer sequence_renderer;
        private ClassDiagramRenderer class_renderer;
        private ActivityDiagramRenderer activity_renderer;
        private UseCaseDiagramRenderer usecase_renderer;
        private StateDiagramRenderer state_renderer;
        private ComponentDiagramRenderer component_renderer;
        private ObjectDiagramRenderer object_renderer;
        private DeploymentDiagramRenderer deployment_renderer;
        private ERDiagramRenderer er_renderer;
        private MindMapDiagramRenderer mindmap_renderer;

        public GraphvizRenderer() {
            context = new Gvc.Context();
            last_regions = new Gee.ArrayList<ElementRegion>();

            // Instantiate all specialized renderers
            sequence_renderer = new SequenceDiagramRenderer(context, last_regions, layout_engine);
            class_renderer = new ClassDiagramRenderer(context, last_regions, layout_engine);
            activity_renderer = new ActivityDiagramRenderer(context, last_regions, layout_engine);
            usecase_renderer = new UseCaseDiagramRenderer(context, last_regions, layout_engine);
            state_renderer = new StateDiagramRenderer(context, last_regions, layout_engine);
            component_renderer = new ComponentDiagramRenderer(context, last_regions, layout_engine);
            object_renderer = new ObjectDiagramRenderer(context, last_regions, layout_engine);
            deployment_renderer = new DeploymentDiagramRenderer(context, last_regions, layout_engine);
            er_renderer = new ERDiagramRenderer(context, last_regions, layout_engine);
            mindmap_renderer = new MindMapDiagramRenderer(context, last_regions, layout_engine);

            // Connect layout_engine property changes to all renderers
            this.notify["layout-engine"].connect(() => {
                update_renderer_layout_engines();
            });
        }

        private void update_renderer_layout_engines() {
            // Note: Since renderers store layout_engine in their constructor,
            // they'll use the GraphvizRenderer's layout_engine value
            // We need to recreate renderers when layout_engine changes
            sequence_renderer = new SequenceDiagramRenderer(context, last_regions, layout_engine);
            class_renderer = new ClassDiagramRenderer(context, last_regions, layout_engine);
            activity_renderer = new ActivityDiagramRenderer(context, last_regions, layout_engine);
            usecase_renderer = new UseCaseDiagramRenderer(context, last_regions, layout_engine);
            state_renderer = new StateDiagramRenderer(context, last_regions, layout_engine);
            component_renderer = new ComponentDiagramRenderer(context, last_regions, layout_engine);
            object_renderer = new ObjectDiagramRenderer(context, last_regions, layout_engine);
            deployment_renderer = new DeploymentDiagramRenderer(context, last_regions, layout_engine);
            er_renderer = new ERDiagramRenderer(context, last_regions, layout_engine);
            mindmap_renderer = new MindMapDiagramRenderer(context, last_regions, layout_engine);
        }

        // ==================== Sequence Diagram ====================

        public string generate_dot(SequenceDiagram diagram) {
            return sequence_renderer.generate_dot(diagram);
        }

        public uint8[]? render_to_svg(SequenceDiagram diagram) {
            return sequence_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_to_surface(SequenceDiagram diagram) {
            return sequence_renderer.render_to_surface(diagram);
        }

        public bool export_to_png(SequenceDiagram diagram, string filename) {
            return sequence_renderer.export_to_png(diagram, filename);
        }

        public bool export_to_svg(SequenceDiagram diagram, string filename) {
            return sequence_renderer.export_to_svg(diagram, filename);
        }

        public bool export_to_pdf(SequenceDiagram diagram, string filename) {
            return sequence_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Class Diagram ====================

        public string generate_class_dot(ClassDiagram diagram) {
            return class_renderer.generate_dot(diagram);
        }

        public uint8[]? render_class_to_svg(ClassDiagram diagram) {
            return class_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_class_to_surface(ClassDiagram diagram) {
            return class_renderer.render_to_surface(diagram);
        }

        public bool export_class_to_png(ClassDiagram diagram, string filename) {
            return class_renderer.export_to_png(diagram, filename);
        }

        public bool export_class_to_svg(ClassDiagram diagram, string filename) {
            return class_renderer.export_to_svg(diagram, filename);
        }

        public bool export_class_to_pdf(ClassDiagram diagram, string filename) {
            return class_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Activity Diagram ====================

        public string generate_activity_dot(ActivityDiagram diagram) {
            return activity_renderer.generate_dot(diagram);
        }

        public uint8[]? render_activity_to_svg(ActivityDiagram diagram) {
            return activity_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_activity_to_surface(ActivityDiagram diagram) {
            return activity_renderer.render_to_surface(diagram);
        }

        public bool export_activity_to_png(ActivityDiagram diagram, string filename) {
            return activity_renderer.export_to_png(diagram, filename);
        }

        public bool export_activity_to_svg(ActivityDiagram diagram, string filename) {
            return activity_renderer.export_to_svg(diagram, filename);
        }

        public bool export_activity_to_pdf(ActivityDiagram diagram, string filename) {
            return activity_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Use Case Diagram ====================

        public string generate_usecase_dot(UseCaseDiagram diagram) {
            return usecase_renderer.generate_dot(diagram);
        }

        public uint8[]? render_usecase_to_svg(UseCaseDiagram diagram) {
            return usecase_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_usecase_to_surface(UseCaseDiagram diagram) {
            return usecase_renderer.render_to_surface(diagram);
        }

        public bool export_usecase_to_png(UseCaseDiagram diagram, string filename) {
            return usecase_renderer.export_to_png(diagram, filename);
        }

        public bool export_usecase_to_svg(UseCaseDiagram diagram, string filename) {
            return usecase_renderer.export_to_svg(diagram, filename);
        }

        public bool export_usecase_to_pdf(UseCaseDiagram diagram, string filename) {
            return usecase_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== State Diagram ====================

        public string generate_state_dot(StateDiagram diagram) {
            return state_renderer.generate_dot(diagram);
        }

        public uint8[]? render_state_to_svg(StateDiagram diagram) {
            return state_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_state_to_surface(StateDiagram diagram) {
            return state_renderer.render_to_surface(diagram);
        }

        public bool export_state_to_png(StateDiagram diagram, string filename) {
            return state_renderer.export_to_png(diagram, filename);
        }

        public bool export_state_to_svg(StateDiagram diagram, string filename) {
            return state_renderer.export_to_svg(diagram, filename);
        }

        public bool export_state_to_pdf(StateDiagram diagram, string filename) {
            return state_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Component Diagram ====================

        public string generate_component_dot(ComponentDiagram diagram) {
            return component_renderer.generate_dot(diagram);
        }

        public uint8[]? render_component_to_svg(ComponentDiagram diagram) {
            return component_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_component_to_surface(ComponentDiagram diagram) {
            return component_renderer.render_to_surface(diagram);
        }

        public bool export_component_to_png(ComponentDiagram diagram, string filename) {
            return component_renderer.export_to_png(diagram, filename);
        }

        public bool export_component_to_svg(ComponentDiagram diagram, string filename) {
            return component_renderer.export_to_svg(diagram, filename);
        }

        public bool export_component_to_pdf(ComponentDiagram diagram, string filename) {
            return component_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Object Diagram ====================

        public string generate_object_dot(ObjectDiagram diagram) {
            return object_renderer.generate_dot(diagram);
        }

        public uint8[]? render_object_to_svg(ObjectDiagram diagram) {
            return object_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_object_to_surface(ObjectDiagram diagram) {
            return object_renderer.render_to_surface(diagram);
        }

        public bool export_object_to_png(ObjectDiagram diagram, string filename) {
            return object_renderer.export_to_png(diagram, filename);
        }

        public bool export_object_to_svg(ObjectDiagram diagram, string filename) {
            return object_renderer.export_to_svg(diagram, filename);
        }

        public bool export_object_to_pdf(ObjectDiagram diagram, string filename) {
            return object_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Deployment Diagram ====================

        public string generate_deployment_dot(DeploymentDiagram diagram) {
            return deployment_renderer.generate_dot(diagram);
        }

        public uint8[]? render_deployment_to_svg(DeploymentDiagram diagram) {
            return deployment_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_deployment_to_surface(DeploymentDiagram diagram) {
            return deployment_renderer.render_to_surface(diagram);
        }

        public bool export_deployment_to_png(DeploymentDiagram diagram, string filename) {
            return deployment_renderer.export_to_png(diagram, filename);
        }

        public bool export_deployment_to_svg(DeploymentDiagram diagram, string filename) {
            return deployment_renderer.export_to_svg(diagram, filename);
        }

        public bool export_deployment_to_pdf(DeploymentDiagram diagram, string filename) {
            return deployment_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== ER Diagram ====================

        public string generate_er_dot(ERDiagram diagram) {
            return er_renderer.generate_dot(diagram);
        }

        public uint8[]? render_er_to_svg(ERDiagram diagram) {
            return er_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_er_to_surface(ERDiagram diagram) {
            return er_renderer.render_to_surface(diagram);
        }

        public bool export_er_to_png(ERDiagram diagram, string filename) {
            return er_renderer.export_to_png(diagram, filename);
        }

        public bool export_er_to_svg(ERDiagram diagram, string filename) {
            return er_renderer.export_to_svg(diagram, filename);
        }

        public bool export_er_to_pdf(ERDiagram diagram, string filename) {
            return er_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== MindMap Diagram ====================

        public string generate_mindmap_dot(MindMapDiagram diagram) {
            return mindmap_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mindmap_to_svg(MindMapDiagram diagram) {
            return mindmap_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mindmap_to_surface(MindMapDiagram diagram) {
            return mindmap_renderer.render_to_surface(diagram);
        }

        public bool export_mindmap_to_png(MindMapDiagram diagram, string filename) {
            return mindmap_renderer.export_to_png(diagram, filename);
        }

        public bool export_mindmap_to_svg(MindMapDiagram diagram, string filename) {
            return mindmap_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mindmap_to_pdf(MindMapDiagram diagram, string filename) {
            return mindmap_renderer.export_to_pdf(diagram, filename);
        }
    }
}
