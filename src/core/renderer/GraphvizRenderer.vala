namespace GDiagram {
    // Facade pattern: GraphvizRenderer delegates to specialized diagram renderers
    public class GraphvizRenderer : Object {
        private Gvc.Context context;

        // Stores element regions from last render for click navigation
        public Gee.ArrayList<ElementRegion> last_regions { get; private set; }

        // Expose the Graphviz context for external renderers (e.g. compare dialog)
        public unowned Gvc.Context get_context() { return context; }

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
        private GanttDiagramRenderer gantt_renderer;
        private JsonDiagramRenderer json_renderer;
        private YamlDiagramRenderer yaml_renderer;
        private ChronologyDiagramRenderer chronology_renderer;
        private TimingDiagramRenderer timing_renderer;
        private NwdiagDiagramRenderer nwdiag_renderer;
        private ArchimateDiagramRenderer archimate_renderer;
        private MermaidTimelineRenderer mermaid_timeline_renderer;
        private MermaidQuadrantRenderer mermaid_quadrant_renderer;
        private MermaidXYChartRenderer mermaid_xychart_renderer;
        private MermaidKanbanRenderer mermaid_kanban_renderer;
        private MermaidSankeyRenderer mermaid_sankey_renderer;
        private MermaidRequirementRenderer mermaid_requirement_renderer;
        private MermaidBlockRenderer mermaid_block_renderer;
        private MermaidPacketRenderer mermaid_packet_renderer;
        private MermaidC4Renderer mermaid_c4_renderer;
        private MermaidArchitectureRenderer mermaid_architecture_renderer;
        private MermaidZenUMLRenderer mermaid_zenuml_renderer;
        private MermaidRadarRenderer mermaid_radar_renderer;
        private MermaidTreemapRenderer mermaid_treemap_renderer;

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
            gantt_renderer = new GanttDiagramRenderer(context, last_regions, layout_engine);
            json_renderer = new JsonDiagramRenderer(context, last_regions, layout_engine);
            yaml_renderer = new YamlDiagramRenderer(context, last_regions, layout_engine);
            chronology_renderer = new ChronologyDiagramRenderer(context, last_regions, layout_engine);
            timing_renderer = new TimingDiagramRenderer(context, last_regions, layout_engine);
            nwdiag_renderer = new NwdiagDiagramRenderer(context, last_regions, layout_engine);
            archimate_renderer = new ArchimateDiagramRenderer(context, last_regions, layout_engine);
            mermaid_timeline_renderer = new MermaidTimelineRenderer(context, last_regions, layout_engine);
            mermaid_quadrant_renderer = new MermaidQuadrantRenderer(context, last_regions, layout_engine);
            mermaid_xychart_renderer = new MermaidXYChartRenderer(context, last_regions, layout_engine);
            mermaid_kanban_renderer = new MermaidKanbanRenderer(context, last_regions, layout_engine);
            mermaid_sankey_renderer = new MermaidSankeyRenderer(context, last_regions, layout_engine);
            mermaid_requirement_renderer = new MermaidRequirementRenderer(context, last_regions, layout_engine);
            mermaid_block_renderer = new MermaidBlockRenderer(context, last_regions, layout_engine);
            mermaid_packet_renderer = new MermaidPacketRenderer(context, last_regions, layout_engine);
            mermaid_c4_renderer = new MermaidC4Renderer(context, last_regions, layout_engine);
            mermaid_architecture_renderer = new MermaidArchitectureRenderer(context, last_regions, layout_engine);
            mermaid_zenuml_renderer = new MermaidZenUMLRenderer(context, last_regions, layout_engine);
            mermaid_radar_renderer = new MermaidRadarRenderer(context, last_regions, layout_engine);
            mermaid_treemap_renderer = new MermaidTreemapRenderer(context, last_regions, layout_engine);

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
            gantt_renderer = new GanttDiagramRenderer(context, last_regions, layout_engine);
            json_renderer = new JsonDiagramRenderer(context, last_regions, layout_engine);
            yaml_renderer = new YamlDiagramRenderer(context, last_regions, layout_engine);
            chronology_renderer = new ChronologyDiagramRenderer(context, last_regions, layout_engine);
            timing_renderer = new TimingDiagramRenderer(context, last_regions, layout_engine);
            nwdiag_renderer = new NwdiagDiagramRenderer(context, last_regions, layout_engine);
            archimate_renderer = new ArchimateDiagramRenderer(context, last_regions, layout_engine);
            mermaid_timeline_renderer = new MermaidTimelineRenderer(context, last_regions, layout_engine);
            mermaid_quadrant_renderer = new MermaidQuadrantRenderer(context, last_regions, layout_engine);
            mermaid_xychart_renderer = new MermaidXYChartRenderer(context, last_regions, layout_engine);
            mermaid_kanban_renderer = new MermaidKanbanRenderer(context, last_regions, layout_engine);
            mermaid_sankey_renderer = new MermaidSankeyRenderer(context, last_regions, layout_engine);
            mermaid_requirement_renderer = new MermaidRequirementRenderer(context, last_regions, layout_engine);
            mermaid_block_renderer = new MermaidBlockRenderer(context, last_regions, layout_engine);
            mermaid_packet_renderer = new MermaidPacketRenderer(context, last_regions, layout_engine);
            mermaid_c4_renderer = new MermaidC4Renderer(context, last_regions, layout_engine);
            mermaid_architecture_renderer = new MermaidArchitectureRenderer(context, last_regions, layout_engine);
            mermaid_zenuml_renderer = new MermaidZenUMLRenderer(context, last_regions, layout_engine);
            mermaid_radar_renderer = new MermaidRadarRenderer(context, last_regions, layout_engine);
            mermaid_treemap_renderer = new MermaidTreemapRenderer(context, last_regions, layout_engine);
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

        // ==================== PlantUML Gantt ====================

        public string generate_gantt_dot(PumlGanttDiagram diagram) {

            return gantt_renderer.generate_dot(diagram);

        }

        public uint8[]? render_gantt_to_svg(PumlGanttDiagram diagram) {

            return gantt_renderer.render_to_svg(diagram);

        }

        public Cairo.ImageSurface? render_gantt_to_surface(PumlGanttDiagram diagram) {

            return gantt_renderer.render_to_surface(diagram);

        }

        public bool export_gantt_to_png(PumlGanttDiagram diagram, string filename) {

            return gantt_renderer.export_to_png(diagram, filename);

        }

        public bool export_gantt_to_svg(PumlGanttDiagram diagram, string filename) {

            return gantt_renderer.export_to_svg(diagram, filename);

        }

        public bool export_gantt_to_pdf(PumlGanttDiagram diagram, string filename) {

            return gantt_renderer.export_to_pdf(diagram, filename);

        }

        // ==================== PlantUML JSON ====================

        public string generate_json_dot(JsonDiagram diagram) {
            return json_renderer.generate_dot(diagram);
        }

        public uint8[]? render_json_to_svg(JsonDiagram diagram) {
            return json_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_json_to_surface(JsonDiagram diagram) {
            return json_renderer.render_to_surface(diagram);
        }

        public bool export_json_to_png(JsonDiagram diagram, string filename) {
            return json_renderer.export_to_png(diagram, filename);
        }

        public bool export_json_to_svg(JsonDiagram diagram, string filename) {
            return json_renderer.export_to_svg(diagram, filename);
        }

        public bool export_json_to_pdf(JsonDiagram diagram, string filename) {
            return json_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== PlantUML YAML ====================

        public string generate_yaml_dot(YamlDiagram diagram) {
            return yaml_renderer.generate_dot(diagram);
        }

        public uint8[]? render_yaml_to_svg(YamlDiagram diagram) {
            return yaml_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_yaml_to_surface(YamlDiagram diagram) {
            return yaml_renderer.render_to_surface(diagram);
        }

        public bool export_yaml_to_png(YamlDiagram diagram, string filename) {
            return yaml_renderer.export_to_png(diagram, filename);
        }

        public bool export_yaml_to_svg(YamlDiagram diagram, string filename) {
            return yaml_renderer.export_to_svg(diagram, filename);
        }

        public bool export_yaml_to_pdf(YamlDiagram diagram, string filename) {
            return yaml_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== PlantUML Chronology ====================

        public string generate_chronology_dot(ChronologyDiagram diagram) {
            return chronology_renderer.generate_dot(diagram);
        }

        public uint8[]? render_chronology_to_svg(ChronologyDiagram diagram) {
            return chronology_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_chronology_to_surface(ChronologyDiagram diagram) {
            return chronology_renderer.render_to_surface(diagram);
        }

        public bool export_chronology_to_png(ChronologyDiagram diagram, string filename) {
            return chronology_renderer.export_to_png(diagram, filename);
        }

        public bool export_chronology_to_svg(ChronologyDiagram diagram, string filename) {
            return chronology_renderer.export_to_svg(diagram, filename);
        }

        public bool export_chronology_to_pdf(ChronologyDiagram diagram, string filename) {
            return chronology_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== PlantUML Timing ====================

        public string generate_timing_dot(TimingDiagram diagram) {
            return timing_renderer.generate_dot(diagram);
        }

        public uint8[]? render_timing_to_svg(TimingDiagram diagram) {
            return timing_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_timing_to_surface(TimingDiagram diagram) {
            return timing_renderer.render_to_surface(diagram);
        }

        public bool export_timing_to_png(TimingDiagram diagram, string filename) {
            return timing_renderer.export_to_png(diagram, filename);
        }

        public bool export_timing_to_svg(TimingDiagram diagram, string filename) {
            return timing_renderer.export_to_svg(diagram, filename);
        }

        public bool export_timing_to_pdf(TimingDiagram diagram, string filename) {
            return timing_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== PlantUML Network (nwdiag) ====================

        public string generate_nwdiag_dot(NwdiagDiagram diagram) {
            return nwdiag_renderer.generate_dot(diagram);
        }

        public uint8[]? render_nwdiag_to_svg(NwdiagDiagram diagram) {
            return nwdiag_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_nwdiag_to_surface(NwdiagDiagram diagram) {
            return nwdiag_renderer.render_to_surface(diagram);
        }

        public bool export_nwdiag_to_png(NwdiagDiagram diagram, string filename) {
            return nwdiag_renderer.export_to_png(diagram, filename);
        }

        public bool export_nwdiag_to_svg(NwdiagDiagram diagram, string filename) {
            return nwdiag_renderer.export_to_svg(diagram, filename);
        }

        public bool export_nwdiag_to_pdf(NwdiagDiagram diagram, string filename) {
            return nwdiag_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== PlantUML Archimate ====================

        public string generate_archimate_dot(ArchimateDiagram diagram) {
            return archimate_renderer.generate_dot(diagram);
        }

        public uint8[]? render_archimate_to_svg(ArchimateDiagram diagram) {
            return archimate_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_archimate_to_surface(ArchimateDiagram diagram) {
            return archimate_renderer.render_to_surface(diagram);
        }

        public bool export_archimate_to_png(ArchimateDiagram diagram, string filename) {
            return archimate_renderer.export_to_png(diagram, filename);
        }

        public bool export_archimate_to_svg(ArchimateDiagram diagram, string filename) {
            return archimate_renderer.export_to_svg(diagram, filename);
        }

        public bool export_archimate_to_pdf(ArchimateDiagram diagram, string filename) {
            return archimate_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Timeline ====================

        public string generate_mermaid_timeline_dot(MermaidTimeline diagram) {
            return mermaid_timeline_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_timeline_to_svg(MermaidTimeline diagram) {
            return mermaid_timeline_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_timeline_to_surface(MermaidTimeline diagram) {
            return mermaid_timeline_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_timeline_to_png(MermaidTimeline diagram, string filename) {
            return mermaid_timeline_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_timeline_to_svg(MermaidTimeline diagram, string filename) {
            return mermaid_timeline_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_timeline_to_pdf(MermaidTimeline diagram, string filename) {
            return mermaid_timeline_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Quadrant Chart ====================

        public string generate_mermaid_quadrant_dot(MermaidQuadrant diagram) {
            return mermaid_quadrant_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_quadrant_to_svg(MermaidQuadrant diagram) {
            return mermaid_quadrant_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_quadrant_to_surface(MermaidQuadrant diagram) {
            return mermaid_quadrant_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_quadrant_to_png(MermaidQuadrant diagram, string filename) {
            return mermaid_quadrant_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_quadrant_to_svg(MermaidQuadrant diagram, string filename) {
            return mermaid_quadrant_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_quadrant_to_pdf(MermaidQuadrant diagram, string filename) {
            return mermaid_quadrant_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid XY Chart ====================

        public string generate_mermaid_xychart_dot(MermaidXYChart diagram) {
            return mermaid_xychart_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_xychart_to_svg(MermaidXYChart diagram) {
            return mermaid_xychart_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_xychart_to_surface(MermaidXYChart diagram) {
            return mermaid_xychart_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_xychart_to_png(MermaidXYChart diagram, string filename) {
            return mermaid_xychart_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_xychart_to_svg(MermaidXYChart diagram, string filename) {
            return mermaid_xychart_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_xychart_to_pdf(MermaidXYChart diagram, string filename) {
            return mermaid_xychart_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Kanban ====================

        public string generate_mermaid_kanban_dot(MermaidKanban diagram) {
            return mermaid_kanban_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_kanban_to_svg(MermaidKanban diagram) {
            return mermaid_kanban_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_kanban_to_surface(MermaidKanban diagram) {
            return mermaid_kanban_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_kanban_to_png(MermaidKanban diagram, string filename) {
            return mermaid_kanban_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_kanban_to_svg(MermaidKanban diagram, string filename) {
            return mermaid_kanban_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_kanban_to_pdf(MermaidKanban diagram, string filename) {
            return mermaid_kanban_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Sankey ====================

        public string generate_mermaid_sankey_dot(MermaidSankey diagram) {
            return mermaid_sankey_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_sankey_to_svg(MermaidSankey diagram) {
            return mermaid_sankey_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_sankey_to_surface(MermaidSankey diagram) {
            return mermaid_sankey_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_sankey_to_png(MermaidSankey diagram, string filename) {
            return mermaid_sankey_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_sankey_to_svg(MermaidSankey diagram, string filename) {
            return mermaid_sankey_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_sankey_to_pdf(MermaidSankey diagram, string filename) {
            return mermaid_sankey_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Requirement Diagram ====================

        public string generate_mermaid_requirement_dot(MermaidRequirement diagram) {
            return mermaid_requirement_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_requirement_to_svg(MermaidRequirement diagram) {
            return mermaid_requirement_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_requirement_to_surface(MermaidRequirement diagram) {
            return mermaid_requirement_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_requirement_to_png(MermaidRequirement diagram, string filename) {
            return mermaid_requirement_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_requirement_to_svg(MermaidRequirement diagram, string filename) {
            return mermaid_requirement_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_requirement_to_pdf(MermaidRequirement diagram, string filename) {
            return mermaid_requirement_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Block Diagram ====================

        public string generate_mermaid_block_dot(MermaidBlock diagram) {
            return mermaid_block_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_block_to_svg(MermaidBlock diagram) {
            return mermaid_block_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_block_to_surface(MermaidBlock diagram) {
            return mermaid_block_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_block_to_png(MermaidBlock diagram, string filename) {
            return mermaid_block_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_block_to_svg(MermaidBlock diagram, string filename) {
            return mermaid_block_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_block_to_pdf(MermaidBlock diagram, string filename) {
            return mermaid_block_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Packet ====================

        public string generate_mermaid_packet_dot(MermaidPacket diagram) {
            return mermaid_packet_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_packet_to_svg(MermaidPacket diagram) {
            return mermaid_packet_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_packet_to_surface(MermaidPacket diagram) {
            return mermaid_packet_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_packet_to_png(MermaidPacket diagram, string filename) {
            return mermaid_packet_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_packet_to_svg(MermaidPacket diagram, string filename) {
            return mermaid_packet_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_packet_to_pdf(MermaidPacket diagram, string filename) {
            return mermaid_packet_renderer.export_to_pdf(diagram, filename);
        }


        public string generate_mermaid_c4_dot(MermaidC4 diagram) {
            return mermaid_c4_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_c4_to_svg(MermaidC4 diagram) {
            return mermaid_c4_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_c4_to_surface(MermaidC4 diagram) {
            return mermaid_c4_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_c4_to_png(MermaidC4 diagram, string filename) {
            return mermaid_c4_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_c4_to_svg(MermaidC4 diagram, string filename) {
            return mermaid_c4_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_c4_to_pdf(MermaidC4 diagram, string filename) {
            return mermaid_c4_renderer.export_to_pdf(diagram, filename);
        }

    
        // ==================== Mermaid Architecture ====================

        public string generate_mermaid_architecture_dot(MermaidArchitecture diagram) {
            return mermaid_architecture_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_architecture_to_svg(MermaidArchitecture diagram) {
            return mermaid_architecture_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_architecture_to_surface(MermaidArchitecture diagram) {
            return mermaid_architecture_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_architecture_to_png(MermaidArchitecture diagram, string filename) {
            return mermaid_architecture_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_architecture_to_svg(MermaidArchitecture diagram, string filename) {
            return mermaid_architecture_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_architecture_to_pdf(MermaidArchitecture diagram, string filename) {
            return mermaid_architecture_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid ZenUML ====================

        public string generate_mermaid_zenuml_dot(MermaidZenUML diagram) {
            return mermaid_zenuml_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_zenuml_to_svg(MermaidZenUML diagram) {
            return mermaid_zenuml_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_zenuml_to_surface(MermaidZenUML diagram) {
            return mermaid_zenuml_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_zenuml_to_png(MermaidZenUML diagram, string filename) {
            return mermaid_zenuml_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_zenuml_to_svg(MermaidZenUML diagram, string filename) {
            return mermaid_zenuml_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_zenuml_to_pdf(MermaidZenUML diagram, string filename) {
            return mermaid_zenuml_renderer.export_to_pdf(diagram, filename);
        }


        // ==================== Mermaid Radar ====================

        public string generate_mermaid_radar_dot(MermaidRadar diagram) {
            return mermaid_radar_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_radar_to_svg(MermaidRadar diagram) {
            return mermaid_radar_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_radar_to_surface(MermaidRadar diagram) {
            return mermaid_radar_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_radar_to_png(MermaidRadar diagram, string filename) {
            return mermaid_radar_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_radar_to_svg(MermaidRadar diagram, string filename) {
            return mermaid_radar_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_radar_to_pdf(MermaidRadar diagram, string filename) {
            return mermaid_radar_renderer.export_to_pdf(diagram, filename);
        }

        // ==================== Mermaid Treemap ====================

        public string generate_mermaid_treemap_dot(MermaidTreemap diagram) {
            return mermaid_treemap_renderer.generate_dot(diagram);
        }

        public uint8[]? render_mermaid_treemap_to_svg(MermaidTreemap diagram) {
            return mermaid_treemap_renderer.render_to_svg(diagram);
        }

        public Cairo.ImageSurface? render_mermaid_treemap_to_surface(MermaidTreemap diagram) {
            return mermaid_treemap_renderer.render_to_surface(diagram);
        }

        public bool export_mermaid_treemap_to_png(MermaidTreemap diagram, string filename) {
            return mermaid_treemap_renderer.export_to_png(diagram, filename);
        }

        public bool export_mermaid_treemap_to_svg(MermaidTreemap diagram, string filename) {
            return mermaid_treemap_renderer.export_to_svg(diagram, filename);
        }

        public bool export_mermaid_treemap_to_pdf(MermaidTreemap diagram, string filename) {
            return mermaid_treemap_renderer.export_to_pdf(diagram, filename);
        }

    }
}