namespace GDiagram {

    // Outcome of a render request. Carries everything the UI needs to update
    // the preview, error highlights, outline and stats bar WITHOUT the engine
    // touching any widget. The parsed AST is exposed on `ast` so the UI can
    // build its outline / stats / lint views from it (a single parse feeds
    // both render and UI).
    public enum RenderStatus {
        OK,           // surface produced (may still be null → use fail_message)
        PARSE_ERROR,  // parse failed → highlight `errors`, show `message`
        EMPTY,        // nothing to render → clear highlights, show `message`
        UNKNOWN       // type not recognised → show `message` (no highlight change)
    }

    public class RenderResult : Object {
        public RenderStatus status;
        public DiagramType diagram_type;
        public Cairo.ImageSurface? surface = null;
        public Object? ast = null;
        public Gee.ArrayList<ParseError>? errors = null;
        public string message = "";
        // Shown when status == OK but surface == null (PlantUML render failed).
        public string fail_message = "Failed to render diagram";
    }

    // Outcome of a parse-only request (see DiagramEngine.parse). Carries the
    // detected format/type, the parsed AST and any parse errors WITHOUT the
    // engine invoking Graphviz or building a Cairo surface. Used by tooling
    // (the LSP server) that reparses on every keystroke and only needs the
    // AST + diagnostics, never a rendered image.
    public class ParseResult : Object {
        public DiagramFormat format = DiagramFormat.UNKNOWN;
        public DiagramType diagram_type = DiagramType.UNKNOWN;
        public Object? ast = null;
        public Gee.ArrayList<ParseError>? errors = null;
        // True when the type was detected but the engine has no parser for it.
        public bool unsupported = false;
    }

    /**
     * Core, UI-free diagram engine.
     *
     * Owns every PlantUML and Mermaid parser/renderer instance and the shared
     * Gvc.Context used by the Mermaid renderers. Handles format/type detection,
     * source preprocessing, the parse+render pipeline (behind the single
     * `render()` entry point) and the export pipeline. DocumentView keeps all
     * widget/UI concerns and drives this engine.
     */
    public class DiagramEngine : Object {
        // PlantUML parsers
        private Preprocessor preprocessor;
        private Parser parser;
        private ClassDiagramParser class_parser;
        private ActivityDiagramParser activity_parser;
        private UseCaseDiagramParser usecase_parser;
        private StateDiagramParser state_parser;
        private ComponentDiagramParser component_parser;
        private ObjectDiagramParser object_parser;
        private DeploymentDiagramParser deployment_parser;
        private ERDiagramParser er_parser;
        private MindMapDiagramParser mindmap_parser;
        private GanttDiagramParser gantt_parser;
        private JsonDiagramParser json_parser;
        private YamlDiagramParser yaml_parser;
        private ChronologyDiagramParser chronology_parser;
        private TimingDiagramParser timing_parser;
        private NwdiagDiagramParser nwdiag_parser;
        private ArchimateDiagramParser archimate_parser;

        private GraphvizRenderer renderer;

        // Owned Gvc.Context for all Mermaid renderers (must outlive them)
        private Gvc.Context mermaid_context;

        // Mermaid parsers and renderers
        private MermaidFlowchartParser mermaid_flowchart_parser;
        private MermaidFlowchartRenderer mermaid_flowchart_renderer;
        private MermaidSequenceParser mermaid_sequence_parser;
        private MermaidSequenceRenderer mermaid_sequence_renderer;
        private MermaidStateParser mermaid_state_parser;
        private MermaidStateRenderer mermaid_state_renderer;
        private MermaidClassParser mermaid_class_parser;
        private MermaidClassRenderer mermaid_class_renderer;
        private MermaidERParser mermaid_er_parser;
        private MermaidERRenderer mermaid_er_renderer;
        private MermaidGanttParser mermaid_gantt_parser;
        private MermaidGanttRenderer mermaid_gantt_renderer;
        private MermaidPieParser mermaid_pie_parser;
        private MermaidPieRenderer mermaid_pie_renderer;
        private MermaidUserJourneyParser mermaid_user_journey_parser;
        private MermaidUserJourneyRenderer mermaid_user_journey_renderer;
        private MermaidGitGraphParser mermaid_git_graph_parser;
        private MermaidGitGraphRenderer mermaid_git_graph_renderer;
        private MermaidMindmapParser mermaid_mindmap_parser;
        private MermaidMindmapRenderer mermaid_mindmap_renderer;
        private MermaidTimelineParser mermaid_timeline_parser;
        private MermaidTimelineRenderer mermaid_timeline_renderer;
        private MermaidQuadrantParser mermaid_quadrant_parser;
        private MermaidQuadrantRenderer mermaid_quadrant_renderer;
        private MermaidXYChartParser mermaid_xychart_parser;
        private MermaidXYChartRenderer mermaid_xychart_renderer;
        private MermaidKanbanParser mermaid_kanban_parser;
        private MermaidKanbanRenderer mermaid_kanban_renderer;
        private MermaidSankeyParser mermaid_sankey_parser;
        private MermaidSankeyRenderer mermaid_sankey_renderer;
        private MermaidRequirementParser mermaid_requirement_parser;
        private MermaidRequirementRenderer mermaid_requirement_renderer;
        private MermaidBlockParser mermaid_block_parser;
        private MermaidBlockRenderer mermaid_block_renderer;
        private MermaidPacketParser mermaid_packet_parser;
        private MermaidPacketRenderer mermaid_packet_renderer;
        private MermaidC4Parser mermaid_c4_parser;
        private MermaidArchitectureParser mermaid_architecture_parser;
        private MermaidZenUMLParser mermaid_zenuml_parser;
        private MermaidRadarParser mermaid_radar_parser;
        private MermaidTreemapParser mermaid_treemap_parser;

        public DiagramEngine(string layout_engine) {
            preprocessor = new Preprocessor();
            parser = new Parser();
            class_parser = new ClassDiagramParser();
            activity_parser = new ActivityDiagramParser();
            usecase_parser = new UseCaseDiagramParser();
            state_parser = new StateDiagramParser();
            component_parser = new ComponentDiagramParser();
            object_parser = new ObjectDiagramParser();
            deployment_parser = new DeploymentDiagramParser();
            er_parser = new ERDiagramParser();
            mindmap_parser = new MindMapDiagramParser();
            gantt_parser = new GanttDiagramParser();
            json_parser = new JsonDiagramParser();
            yaml_parser = new YamlDiagramParser();
            chronology_parser = new ChronologyDiagramParser();
            timing_parser = new TimingDiagramParser();
            nwdiag_parser = new NwdiagDiagramParser();
            archimate_parser = new ArchimateDiagramParser();

            renderer = new GraphvizRenderer();
            renderer.layout_engine = layout_engine;

            mermaid_flowchart_parser = new MermaidFlowchartParser();
            mermaid_sequence_parser = new MermaidSequenceParser();
            mermaid_state_parser = new MermaidStateParser();
            mermaid_class_parser = new MermaidClassParser();

            mermaid_context = new Gvc.Context();
            mermaid_flowchart_renderer = new MermaidFlowchartRenderer(
                mermaid_context, renderer.last_regions, layout_engine);
            mermaid_sequence_renderer = new MermaidSequenceRenderer(
                mermaid_context, renderer.last_regions, layout_engine);
            mermaid_state_renderer = new MermaidStateRenderer(
                mermaid_context, renderer.last_regions, layout_engine);
            mermaid_class_renderer = new MermaidClassRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_er_parser = new MermaidERParser();
            mermaid_er_renderer = new MermaidERRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_gantt_parser = new MermaidGanttParser();
            mermaid_gantt_renderer = new MermaidGanttRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_pie_parser = new MermaidPieParser();
            mermaid_pie_renderer = new MermaidPieRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_user_journey_parser = new MermaidUserJourneyParser();
            mermaid_user_journey_renderer = new MermaidUserJourneyRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_git_graph_parser = new MermaidGitGraphParser();
            mermaid_git_graph_renderer = new MermaidGitGraphRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_mindmap_parser = new MermaidMindmapParser();
            mermaid_mindmap_renderer = new MermaidMindmapRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_timeline_parser = new MermaidTimelineParser();
            mermaid_timeline_renderer = new MermaidTimelineRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_quadrant_parser = new MermaidQuadrantParser();
            mermaid_quadrant_renderer = new MermaidQuadrantRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_xychart_parser = new MermaidXYChartParser();
            mermaid_xychart_renderer = new MermaidXYChartRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_kanban_parser = new MermaidKanbanParser();
            mermaid_kanban_renderer = new MermaidKanbanRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_sankey_parser = new MermaidSankeyParser();
            mermaid_sankey_renderer = new MermaidSankeyRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_requirement_parser = new MermaidRequirementParser();
            mermaid_requirement_renderer = new MermaidRequirementRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_block_parser = new MermaidBlockParser();
            mermaid_block_renderer = new MermaidBlockRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_packet_parser = new MermaidPacketParser();
            mermaid_packet_renderer = new MermaidPacketRenderer(
                mermaid_context, renderer.last_regions, layout_engine);

            mermaid_c4_parser = new MermaidC4Parser();
            mermaid_architecture_parser = new MermaidArchitectureParser();
            mermaid_zenuml_parser = new MermaidZenUMLParser();
            mermaid_radar_parser = new MermaidRadarParser();
            mermaid_treemap_parser = new MermaidTreemapParser();
        }

        // ==================== Accessors ====================

        // Click-to-source regions produced by the most recent render. All
        // renderers (Graphviz + Mermaid) write into this shared list.
        public Gee.ArrayList<ElementRegion> last_regions {
            get { return renderer.last_regions; }
        }

        public void set_layout_engine(string engine) {
            renderer.layout_engine = engine;
        }

        // ==================== Detection / preprocessing ====================

        public DiagramFormat detect_format(string source, string? doc_filename) {
            // Check file extension first (most reliable).
            if (doc_filename != null) {
                string filename = doc_filename.down();
                if (filename.has_suffix(".mmd") || filename.has_suffix(".mermaid")) {
                    return DiagramFormat.MERMAID;
                }
                if (filename.has_suffix(".puml") || filename.has_suffix(".plantuml") || filename.has_suffix(".pu") || filename.has_suffix(".ged")) {
                    return DiagramFormat.PLANTUML;
                }
            }
            return TypeDetector.is_mermaid(source)
                ? DiagramFormat.MERMAID
                : DiagramFormat.PLANTUML;
        }

        public DiagramType detect_plantuml_type(string source) {
            return TypeDetector.detect_plantuml(source);
        }

        public DiagramType detect_mermaid_type(string source) {
            return TypeDetector.detect_mermaid(source);
        }

        public string preprocess(string source, string? base_path) {
            return preprocessor.process(source, base_path);
        }

        // ==================== Render ====================

        // Single generic entry point. `type` is the already-detected diagram
        // type, `format` distinguishes the two switch tables, `source` is the
        // (already preprocessed, for PlantUML) source text.
        public RenderResult render(DiagramType type, DiagramFormat format, string source) {
            if (format == DiagramFormat.MERMAID) {
                return render_mermaid(type, source);
            }
            return render_plantuml(type, source);
        }

        private RenderResult render_mermaid(DiagramType type, string source) {
            switch (type) {
                case DiagramType.MERMAID_FLOWCHART:    return render_mermaid_flowchart(source);
                case DiagramType.MERMAID_SEQUENCE:     return render_mermaid_sequence(source);
                case DiagramType.MERMAID_STATE:        return render_mermaid_state(source);
                case DiagramType.MERMAID_CLASS:        return render_mermaid_class(source);
                case DiagramType.MERMAID_ER:           return render_mermaid_er(source);
                case DiagramType.MERMAID_GANTT:        return render_mermaid_gantt(source);
                case DiagramType.MERMAID_PIE:          return render_mermaid_pie(source);
                case DiagramType.MERMAID_USER_JOURNEY: return render_mermaid_user_journey(source);
                case DiagramType.MERMAID_GIT_GRAPH:    return render_mermaid_git_graph(source);
                case DiagramType.MERMAID_MINDMAP:      return render_mermaid_mindmap(source);
                case DiagramType.MERMAID_TIMELINE:     return render_mermaid_timeline(source);
                case DiagramType.MERMAID_QUADRANT:     return render_mermaid_quadrant(source);
                case DiagramType.MERMAID_XYCHART:      return render_mermaid_xychart(source);
                case DiagramType.MERMAID_KANBAN:       return render_mermaid_kanban(source);
                case DiagramType.MERMAID_SANKEY:       return render_mermaid_sankey(source);
                case DiagramType.MERMAID_REQUIREMENT:  return render_mermaid_requirement(source);
                case DiagramType.MERMAID_BLOCK:        return render_mermaid_block(source);
                case DiagramType.MERMAID_PACKET:       return render_mermaid_packet(source);
                case DiagramType.MERMAID_C4:           return render_mermaid_c4(source);
                case DiagramType.MERMAID_ARCHITECTURE: return render_mermaid_architecture(source);
                case DiagramType.MERMAID_ZENUML:       return render_mermaid_zenuml(source);
                case DiagramType.MERMAID_RADAR:        return render_mermaid_radar(source);
                case DiagramType.MERMAID_TREEMAP:      return render_mermaid_treemap(source);
                case DiagramType.UNKNOWN:              return unknown(build_unknown_message(source));
                default:                               return unknown("Unknown Mermaid diagram type");
            }
        }

        private RenderResult render_plantuml(DiagramType type, string source) {
            switch (type) {
                case DiagramType.CLASS:        return render_class_diagram(source);
                case DiagramType.ACTIVITY:     return render_activity_diagram(source);
                case DiagramType.USECASE:      return render_usecase_diagram(source);
                case DiagramType.STATE:        return render_state_diagram(source);
                case DiagramType.COMPONENT:    return render_component_diagram(source);
                case DiagramType.OBJECT:       return render_object_diagram(source);
                case DiagramType.DEPLOYMENT:   return render_deployment_diagram(source);
                case DiagramType.ER_DIAGRAM:   return render_er_diagram(source);
                case DiagramType.MINDMAP:      return render_mindmap_diagram(source, DiagramType.MINDMAP);
                case DiagramType.WBS:          return render_mindmap_diagram(source, DiagramType.WBS);
                case DiagramType.GANTT:        return render_gantt_diagram(source);
                case DiagramType.JSON_DIAGRAM: return render_json_diagram(source);
                case DiagramType.YAML_DIAGRAM: return render_yaml_diagram(source);
                case DiagramType.CHRONOLOGY:   return render_chronology_diagram(source);
                case DiagramType.TIMING:       return render_timing_diagram(source);
                case DiagramType.NWDIAG:       return render_nwdiag_diagram(source);
                case DiagramType.ARCHIMATE:    return render_archimate_diagram(source);
                case DiagramType.DOT_DIAGRAM:
                case DiagramType.TREE:
                case DiagramType.BOARD:
                case DiagramType.DITAA:
                case DiagramType.SALT:
                case DiagramType.CHEN_ER:
                case DiagramType.EBNF:
                case DiagramType.REGEX_DIAGRAM:
                case DiagramType.ANCESTRY:
                    return render_generic_plantuml(source, type);
                case DiagramType.UNKNOWN:
                    return unknown(build_unknown_message(source));
                default:
                    return render_sequence_diagram(source);
            }
        }

        // ==================== Parse-only ====================

        // Parse-only entry point for tooling that needs the AST + parse
        // errors but NOT a rendered image (the LSP server reparses on every
        // didChange). Runs the same detection + preprocessing + parsing as
        // render() but stops before Graphviz/Cairo, and reuses the engine's
        // shared parser instances instead of allocating fresh ones per call.
        public ParseResult parse(string source, string? doc_filename) {
            var result = new ParseResult();
            if (source.strip().length == 0) {
                return result; // format/type stay UNKNOWN
            }

            var format = detect_format(source, doc_filename);
            result.format = format;

            if (format == DiagramFormat.MERMAID) {
                result.diagram_type = detect_mermaid_type(source);
                if (result.diagram_type == DiagramType.UNKNOWN) return result;
                parse_mermaid_ast(result, source);
            } else {
                string processed = preprocess(source, null);
                result.diagram_type = detect_plantuml_type(processed);
                if (result.diagram_type == DiagramType.UNKNOWN) return result;
                parse_plantuml_ast(result, processed);
            }
            return result;
        }

        private Gee.ArrayList<Token> lex(string source) {
            var lexer = new Lexer(source);
            return lexer.scan_all();
        }

        private void parse_plantuml_ast(ParseResult r, string source) {
            switch (r.diagram_type) {
                // string-based parsers
                case DiagramType.SEQUENCE: {
                    var d = parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.GANTT: {
                    var d = gantt_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.JSON_DIAGRAM: {
                    var d = json_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.YAML_DIAGRAM: {
                    var d = yaml_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.CHRONOLOGY: {
                    var d = chronology_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.TIMING: {
                    var d = timing_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.NWDIAG: {
                    var d = nwdiag_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.ARCHIMATE: {
                    var d = archimate_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                // token-based parsers
                case DiagramType.CLASS: {
                    var d = class_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.ACTIVITY: {
                    var d = activity_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.STATE: {
                    var d = state_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.USECASE: {
                    var d = usecase_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.COMPONENT: {
                    var d = component_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.OBJECT: {
                    var d = object_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.DEPLOYMENT: {
                    var d = deployment_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.ER_DIAGRAM: {
                    var d = er_parser.parse(lex(source)); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MINDMAP:
                case DiagramType.WBS: {
                    var d = mindmap_parser.parse(lex(source), r.diagram_type);
                    r.ast = d; r.errors = d.errors; break;
                }
                // generic DOT-based types (no AST-level error list)
                case DiagramType.DOT_DIAGRAM:
                    r.ast = new DotDiagramParser().parse(source); break;
                case DiagramType.TREE:
                    r.ast = new TreeDiagramParser().parse(source); break;
                case DiagramType.BOARD:
                    r.ast = new BoardDiagramParser().parse(source); break;
                case DiagramType.DITAA:
                    r.ast = new DitaaDiagramParser().parse(source); break;
                case DiagramType.SALT:
                    r.ast = new SaltDiagramParser().parse(source); break;
                case DiagramType.CHEN_ER:
                    r.ast = new ChenDiagramParser().parse(source); break;
                case DiagramType.EBNF:
                    r.ast = new EbnfDiagramParser().parse(source); break;
                case DiagramType.REGEX_DIAGRAM:
                    r.ast = new RegexDiagramParser().parse(source); break;
                case DiagramType.ANCESTRY:
                    if (source.strip().has_prefix("0 ")) {
                        r.ast = new GedcomParser().parse(source);
                    } else {
                        r.ast = new AncestryDiagramParser().parse(source);
                    }
                    break;
                default:
                    r.unsupported = true;
                    break;
            }
        }

        private void parse_mermaid_ast(ParseResult r, string source) {
            switch (r.diagram_type) {
                case DiagramType.MERMAID_FLOWCHART: {
                    var d = mermaid_flowchart_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_SEQUENCE: {
                    var d = mermaid_sequence_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_STATE: {
                    var d = mermaid_state_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_CLASS: {
                    var d = mermaid_class_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_ER: {
                    var d = mermaid_er_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_GANTT: {
                    var d = mermaid_gantt_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_PIE: {
                    var d = mermaid_pie_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_USER_JOURNEY: {
                    var d = mermaid_user_journey_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_GIT_GRAPH: {
                    var d = mermaid_git_graph_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_MINDMAP: {
                    var d = mermaid_mindmap_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_TIMELINE: {
                    var d = mermaid_timeline_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_QUADRANT: {
                    var d = mermaid_quadrant_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_XYCHART: {
                    var d = mermaid_xychart_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_KANBAN: {
                    var d = mermaid_kanban_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_SANKEY: {
                    var d = mermaid_sankey_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_REQUIREMENT: {
                    var d = mermaid_requirement_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_BLOCK: {
                    var d = mermaid_block_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_PACKET: {
                    var d = mermaid_packet_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_C4: {
                    var d = mermaid_c4_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_ARCHITECTURE: {
                    var d = mermaid_architecture_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_ZENUML: {
                    var d = mermaid_zenuml_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_RADAR: {
                    var d = mermaid_radar_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                case DiagramType.MERMAID_TREEMAP: {
                    var d = mermaid_treemap_parser.parse(source); r.ast = d; r.errors = d.errors; break;
                }
                default:
                    r.unsupported = true;
                    break;
            }
        }

        // ---- result constructors ----

        private RenderResult ok(DiagramType t, Cairo.ImageSurface? surface, Object? ast,
                                string fail_message = "Failed to render diagram") {
            var r = new RenderResult();
            r.status = RenderStatus.OK;
            r.diagram_type = t;
            r.surface = surface;
            r.ast = ast;
            r.fail_message = fail_message;
            return r;
        }

        private RenderResult parse_error(Gee.ArrayList<ParseError> errors, string message) {
            var r = new RenderResult();
            r.status = RenderStatus.PARSE_ERROR;
            r.errors = errors;
            r.message = message;
            return r;
        }

        private RenderResult empty(DiagramType t, string message) {
            var r = new RenderResult();
            r.status = RenderStatus.EMPTY;
            r.diagram_type = t;
            r.message = message;
            return r;
        }

        private RenderResult unknown(string message) {
            var r = new RenderResult();
            r.status = RenderStatus.UNKNOWN;
            r.message = message;
            return r;
        }

        // Standard "Parse errors:" placeholder (uses ParseError.to_string()).
        private string errors_message(Gee.ArrayList<ParseError> errors) {
            var sb = new StringBuilder();
            sb.append("Parse errors:\n\n");
            foreach (var err in errors) {
                sb.append(err.to_string());
                sb.append("\n");
            }
            return sb.str;
        }

        // "Line N: msg" variant used by the newer Mermaid parsers.
        private string errors_message_lines(Gee.ArrayList<ParseError> errors) {
            var sb = new StringBuilder();
            sb.append("Parse errors:\n\n");
            foreach (var err in errors) {
                sb.append_printf("  Line %d: %s\n", err.line, err.message);
            }
            return sb.str;
        }

        public string build_unknown_message(string source) {
            var sb = new StringBuilder();
            sb.append("Could not determine diagram type.\n\n");
            sb.append("gDiagram looks for known PlantUML keywords (@startuml, class, ");
            sb.append("participant, state, ...) and Mermaid keywords (flowchart, ");
            sb.append("sequenceDiagram, ...) but found neither.\n\n");
            sb.append("First lines of the source:\n");
            int shown = 0;
            foreach (var raw_line in source.split("\n")) {
                string line = raw_line.strip();
                if (line.length == 0) continue;
                sb.append("  ").append(line).append("\n");
                if (++shown >= 5) break;
            }
            return sb.str;
        }

        // ---- Mermaid render methods ----

        private RenderResult render_mermaid_flowchart(string source) {
            var diagram = mermaid_flowchart_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.nodes.size == 0) {
                return empty(DiagramType.MERMAID_FLOWCHART,
                    "Enter Mermaid code to see preview.\n\n" +
                    "Flowchart Example:\n" +
                    "flowchart TD\n" +
                    "    A[Start] --> B{Decision}\n" +
                    "    B -->|Yes| C[Process]\n" +
                    "    B -->|No| D[End]\n" +
                    "    C --> D");
            }
            var surface = mermaid_flowchart_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_FLOWCHART, surface, diagram);
        }

        private RenderResult render_mermaid_sequence(string source) {
            var diagram = mermaid_sequence_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.actors.size == 0 && diagram.messages.size == 0) {
                return empty(DiagramType.MERMAID_SEQUENCE,
                    "Enter Mermaid sequence diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "sequenceDiagram\n" +
                    "    participant Alice\n" +
                    "    participant Bob\n" +
                    "    Alice->>Bob: Hello Bob!\n" +
                    "    Bob-->>Alice: Hi Alice!");
            }
            var surface = mermaid_sequence_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_SEQUENCE, surface, diagram);
        }

        private RenderResult render_mermaid_state(string source) {
            var diagram = mermaid_state_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.states.size == 0 && diagram.transitions.size == 0) {
                return empty(DiagramType.MERMAID_STATE,
                    "Enter Mermaid state diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "stateDiagram-v2\n" +
                    "    [*] --> Still\n" +
                    "    Still --> Moving\n" +
                    "    Moving --> [*]");
            }
            var surface = mermaid_state_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_STATE, surface, diagram);
        }

        private RenderResult render_mermaid_class(string source) {
            var diagram = mermaid_class_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.classes.size == 0) {
                return empty(DiagramType.MERMAID_CLASS,
                    "Enter Mermaid class diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "classDiagram\n" +
                    "    class Animal {\n" +
                    "        +string name\n" +
                    "        +makeSound()\n" +
                    "    }\n" +
                    "    class Dog {\n" +
                    "        +bark()\n" +
                    "    }");
            }
            var surface = mermaid_class_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_CLASS, surface, diagram);
        }

        private RenderResult render_mermaid_er(string source) {
            var diagram = mermaid_er_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.entities.size == 0) {
                return empty(DiagramType.MERMAID_ER,
                    "Enter Mermaid ER diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "erDiagram\n" +
                    "    CUSTOMER ||--o{ ORDER : places\n" +
                    "    ORDER ||--|{ LINE-ITEM : contains");
            }
            var surface = mermaid_er_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_ER, surface, diagram);
        }

        private RenderResult render_mermaid_gantt(string source) {
            var diagram = mermaid_gantt_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.tasks.size == 0) {
                return empty(DiagramType.MERMAID_GANTT,
                    "Enter Mermaid Gantt chart code to see preview.\n\n" +
                    "Example:\n" +
                    "gantt\n" +
                    "    title Project Schedule\n" +
                    "    section Planning\n" +
                    "    Requirements : done, 5d\n" +
                    "    Design : active, 7d");
            }
            var surface = mermaid_gantt_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_GANTT, surface, diagram);
        }

        private RenderResult render_mermaid_pie(string source) {
            var diagram = mermaid_pie_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.slices.size == 0) {
                return empty(DiagramType.MERMAID_PIE,
                    "Enter Mermaid Pie chart code to see preview.\n\n" +
                    "Example:\n" +
                    "pie title Sales Distribution\n" +
                    "    \"Product A\" : 45\n" +
                    "    \"Product B\" : 30\n" +
                    "    \"Product C\" : 25");
            }
            var surface = mermaid_pie_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_PIE, surface, diagram);
        }

        private RenderResult render_mermaid_user_journey(string source) {
            var diagram = mermaid_user_journey_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.all_tasks.size == 0) {
                return empty(DiagramType.MERMAID_USER_JOURNEY,
                    "Enter Mermaid User Journey code to see preview.\n\n" +
                    "Example:\n" +
                    "journey\n" +
                    "    title My working day\n" +
                    "    section Go to work\n" +
                    "      Make tea: 5: Me\n" +
                    "      Go upstairs: 3: Me, Cat\n" +
                    "    section At work\n" +
                    "      Do work: 1: Me, Cat");
            }
            var surface = mermaid_user_journey_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_USER_JOURNEY, surface, diagram);
        }

        private RenderResult render_mermaid_git_graph(string source) {
            var diagram = mermaid_git_graph_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.all_commits.size == 0) {
                return empty(DiagramType.MERMAID_GIT_GRAPH,
                    "Enter Mermaid Git Graph code to see preview.\n\n" +
                    "Example:\n" +
                    "gitGraph\n" +
                    "   commit id: \"Alpha\"\n" +
                    "   commit id: \"Beta\"\n" +
                    "   branch develop\n" +
                    "   checkout develop\n" +
                    "   commit id: \"Feature\"\n" +
                    "   checkout main\n" +
                    "   merge develop id: \"Merge\"");
            }
            var surface = mermaid_git_graph_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_GIT_GRAPH, surface, diagram);
        }

        private RenderResult render_mermaid_mindmap(string source) {
            var diagram = mermaid_mindmap_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_MINDMAP,
                    "Enter Mermaid Mindmap code to see preview.\n\n" +
                    "Example:\n" +
                    "mindmap\n" +
                    "  root((Central Topic))\n" +
                    "    Branch One\n" +
                    "      Leaf A\n" +
                    "      Leaf B\n" +
                    "    Branch Two\n" +
                    "      Leaf C");
            }
            var surface = mermaid_mindmap_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_MINDMAP, surface, diagram);
        }

        private RenderResult render_mermaid_timeline(string source) {
            var diagram = mermaid_timeline_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_TIMELINE,
                    "Enter Mermaid Timeline code to see preview.\n\n" +
                    "Example:\n" +
                    "timeline\n" +
                    "    title History of Social Media\n" +
                    "    2002 : LinkedIn\n" +
                    "    2004 : Facebook\n" +
                    "         : Google\n" +
                    "    2005 : YouTube\n" +
                    "    2006 : Twitter");
            }
            var surface = mermaid_timeline_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_TIMELINE, surface, diagram);
        }

        private RenderResult render_mermaid_quadrant(string source) {
            var diagram = mermaid_quadrant_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_QUADRANT,
                    "Enter Mermaid Quadrant Chart code to see preview.\n\n" +
                    "Example:\n" +
                    "quadrantChart\n" +
                    "    title Reach and engagement\n" +
                    "    x-axis Low Reach --> High Reach\n" +
                    "    y-axis Low Engagement --> High Engagement\n" +
                    "    quadrant-1 We should expand\n" +
                    "    quadrant-2 Need to promote\n" +
                    "    quadrant-3 Re-evaluate\n" +
                    "    quadrant-4 May be improved\n" +
                    "    Campaign A: [0.3, 0.6]\n" +
                    "    Campaign B: [0.45, 0.23]");
            }
            var surface = mermaid_quadrant_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_QUADRANT, surface, diagram);
        }

        private RenderResult render_mermaid_xychart(string source) {
            var diagram = mermaid_xychart_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_XYCHART,
                    "Enter Mermaid XY Chart code to see preview.\n\n" +
                    "Example:\n" +
                    "xychart-beta\n" +
                    "    title \"Sales Revenue\"\n" +
                    "    x-axis [jan, feb, mar, apr, may, jun]\n" +
                    "    y-axis \"Revenue (in $)\" 4000 --> 11000\n" +
                    "    bar [5000, 6000, 7500, 8200, 9500, 10500]\n" +
                    "    line [5000, 6000, 7500, 8200, 9500, 10500]");
            }
            var surface = mermaid_xychart_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_XYCHART, surface, diagram);
        }

        private RenderResult render_mermaid_kanban(string source) {
            var diagram = mermaid_kanban_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_KANBAN,
                    "Enter Mermaid Kanban code to see preview.\n\n" +
                    "Example:\n" +
                    "kanban\n" +
                    "  Todo\n" +
                    "    [Create Documentation]\n" +
                    "  In Progress\n" +
                    "    id1[Implement feature]\n" +
                    "  Done\n" +
                    "    id2[Design]");
            }
            var surface = mermaid_kanban_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_KANBAN, surface, diagram);
        }

        private RenderResult render_mermaid_sankey(string source) {
            var diagram = mermaid_sankey_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_SANKEY,
                    "Empty Sankey diagram.\n\nExample:\n" +
                    "sankey-beta\n\n" +
                    "Agricultural 'waste',Bio-conversion,124.729\n" +
                    "Bio-conversion,Liquid,0.597\n" +
                    "Bio-conversion,Losses,26.862");
            }
            var surface = mermaid_sankey_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_SANKEY, surface, diagram);
        }

        private RenderResult render_mermaid_requirement(string source) {
            var diagram = mermaid_requirement_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_REQUIREMENT,
                    "Empty requirement diagram.\n\nExample:\n" +
                    "requirementDiagram\n\n" +
                    "    requirement test_req {\n" +
                    "        id: 1\n" +
                    "        text: the test text.\n" +
                    "        risk: high\n" +
                    "        verifymethod: test\n" +
                    "    }\n\n" +
                    "    element test_entity {\n" +
                    "        type: simulation\n" +
                    "        docref: SDD/test_entity\n" +
                    "    }\n\n" +
                    "    test_entity - satisfies -> test_req");
            }
            var surface = mermaid_requirement_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_REQUIREMENT, surface, diagram);
        }

        private RenderResult render_mermaid_block(string source) {
            var diagram = mermaid_block_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_BLOCK,
                    "Empty block diagram.\n\nExample:\n" +
                    "block-beta\n" +
                    "    columns 3\n" +
                    "    A[\"Block A\"] B[\"Block B\"] C[\"Block C\"]\n" +
                    "    A --> B\n" +
                    "    B --> C");
            }
            var surface = mermaid_block_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_BLOCK, surface, diagram);
        }

        private RenderResult render_mermaid_packet(string source) {
            var diagram = mermaid_packet_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message_lines(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_PACKET,
                    "Enter Mermaid packet code to see preview.\n\n" +
                    "Example:\npacket-beta\n0-15: \"Source Port\"\n16-31: \"Dest Port\"\n32-63: \"Sequence Number\"");
            }
            var surface = mermaid_packet_renderer.render_to_surface(diagram);
            return ok(DiagramType.MERMAID_PACKET, surface, diagram);
        }

        private RenderResult render_mermaid_c4(string source) {
            var diagram = mermaid_c4_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message_lines(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_C4,
                    "Enter Mermaid C4 code to see preview.\n\n" +
                    "Example:\nC4Context\n    Person(user, user, A user)\n    System(sys, System)");
            }
            var surface = renderer.render_mermaid_c4_to_surface(diagram);
            return ok(DiagramType.MERMAID_C4, surface, diagram);
        }

        private RenderResult render_mermaid_architecture(string source) {
            var diagram = mermaid_architecture_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message_lines(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_ARCHITECTURE,
                    "Enter Mermaid Architecture code to see preview.\n\n" +
                    "Example:\narchitecture-beta\n    service db(database)[Database]\n    service server(server)[Server]\n    db:L -- R:server");
            }
            var surface = renderer.render_mermaid_architecture_to_surface(diagram);
            return ok(DiagramType.MERMAID_ARCHITECTURE, surface, diagram);
        }

        private RenderResult render_mermaid_zenuml(string source) {
            var diagram = mermaid_zenuml_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message_lines(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_ZENUML,
                    "Enter ZenUML code to see preview.\n\n" +
                    "Example:\nzenuml\n    title Order Service\n    @Actor Client\n    @Database DB\n\n    Client -> DB.save(data) {\n        return result\n    }");
            }
            var surface = renderer.render_mermaid_zenuml_to_surface(diagram);
            return ok(DiagramType.MERMAID_ZENUML, surface, diagram);
        }

        private RenderResult render_mermaid_radar(string source) {
            var diagram = mermaid_radar_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message_lines(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_RADAR,
                    "Enter radar-beta code to see preview.\n\n" +
                    "Example:\nradar-beta\n  title Skills\n  axis A, B, C, D, E\n  curve c1{85, 70, 60, 75, 80}");
            }
            var surface = renderer.render_mermaid_radar_to_surface(diagram);
            return ok(DiagramType.MERMAID_RADAR, surface, diagram);
        }

        private RenderResult render_mermaid_treemap(string source) {
            var diagram = mermaid_treemap_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message_lines(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.MERMAID_TREEMAP,
                    "Enter treemap-beta code to see preview.\n\n" +
                    "Example:\ntreemap-beta\ntitle My Treemap\n\"Section\"\n    \"Leaf\": 10");
            }
            var surface = renderer.render_mermaid_treemap_to_surface(diagram);
            return ok(DiagramType.MERMAID_TREEMAP, surface, diagram);
        }

        // ---- PlantUML render methods ----

        private RenderResult render_sequence_diagram(string source) {
            var diagram = parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.participants.size == 0 && diagram.messages.size == 0) {
                return empty(DiagramType.SEQUENCE,
                    "Enter PlantUML code to see preview.\n\n" +
                    "Sequence Example:\n" +
                    "@startuml\n" +
                    "Alice -> Bob : Hello\n" +
                    "Bob --> Alice : Hi!\n" +
                    "@enduml\n\n" +
                    "Class Example:\n" +
                    "@startuml\n" +
                    "class Animal\n" +
                    "class Dog\n" +
                    "Dog --|> Animal\n" +
                    "@enduml");
            }
            // Sanity check: prevent rendering massive diagrams that will hang
            if (diagram.participants.size > 50) {
                var error_msg = "ERROR: Too many participants (%d)\n\n".printf(diagram.participants.size) +
                    "This diagram has an unusually high number of participants which suggests\n" +
                    "a parsing issue or auto-created phantom participants.\n\n" +
                    "Declared participants in source: 4\n" +
                    "Parser found: %d\n\n".printf(diagram.participants.size) +
                    "This would cause the renderer to hang. Please check the diagram syntax.";
                return empty(DiagramType.SEQUENCE, error_msg);
            }
            var surface = renderer.render_to_surface(diagram);
            return ok(DiagramType.SEQUENCE, surface, diagram);
        }

        private RenderResult render_class_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = class_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.classes.size == 0) {
                return empty(DiagramType.CLASS,
                    "Enter class diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "class Animal {\n" +
                    "  +name: String\n" +
                    "  +eat()\n" +
                    "}\n" +
                    "class Dog {\n" +
                    "  +bark()\n" +
                    "}\n" +
                    "Dog --|> Animal\n" +
                    "@enduml");
            }
            var surface = renderer.render_class_to_surface(diagram);
            return ok(DiagramType.CLASS, surface, diagram, "Failed to render class diagram");
        }

        private RenderResult render_activity_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = activity_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.nodes.size == 0) {
                return empty(DiagramType.ACTIVITY,
                    "Enter activity diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "start\n" +
                    ":Hello world;\n" +
                    ":This is an action;\n" +
                    "if (condition?) then (yes)\n" +
                    "  :Action 1;\n" +
                    "else (no)\n" +
                    "  :Action 2;\n" +
                    "endif\n" +
                    "stop\n" +
                    "@enduml");
            }
            var surface = renderer.render_activity_to_surface(diagram);
            return ok(DiagramType.ACTIVITY, surface, diagram, "Failed to render activity diagram");
        }

        private RenderResult render_usecase_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = usecase_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.actors.size == 0 && diagram.use_cases.size == 0 && diagram.packages.size == 0) {
                return empty(DiagramType.USECASE,
                    "Enter use case diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "left to right direction\n" +
                    "actor User\n" +
                    "actor Admin\n" +
                    "usecase \"Login\" as UC1\n" +
                    "usecase \"Manage Users\" as UC2\n" +
                    "User --> UC1\n" +
                    "Admin --> UC1\n" +
                    "Admin --> UC2\n" +
                    "@enduml");
            }
            var surface = renderer.render_usecase_to_surface(diagram);
            return ok(DiagramType.USECASE, surface, diagram, "Failed to render use case diagram");
        }

        private RenderResult render_state_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = state_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.states.size == 0 && diagram.transitions.size == 0) {
                return empty(DiagramType.STATE,
                    "Enter state diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "[*] --> Idle\n" +
                    "Idle --> Running : start\n" +
                    "Running --> Idle : stop\n" +
                    "Running --> [*] : error\n" +
                    "@enduml");
            }
            var surface = renderer.render_state_to_surface(diagram);
            return ok(DiagramType.STATE, surface, diagram, "Failed to render state diagram");
        }

        private RenderResult render_component_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = component_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.components.size == 0 && diagram.interfaces.size == 0) {
                return empty(DiagramType.COMPONENT,
                    "Enter component diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "package \"Backend\" {\n" +
                    "  [API Server]\n" +
                    "  [Database]\n" +
                    "}\n" +
                    "[Web Client] --> [API Server]\n" +
                    "[API Server] --> [Database]\n" +
                    "@enduml");
            }
            var surface = renderer.render_component_to_surface(diagram);
            return ok(DiagramType.COMPONENT, surface, diagram, "Failed to render component diagram");
        }

        private RenderResult render_object_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = object_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.objects.size == 0) {
                return empty(DiagramType.OBJECT,
                    "Enter object diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "object London {\n" +
                    "  country = \"UK\"\n" +
                    "  population = 9000000\n" +
                    "}\n" +
                    "object Paris {\n" +
                    "  country = \"France\"\n" +
                    "}\n" +
                    "London --> Paris : flight\n" +
                    "@enduml");
            }
            var surface = renderer.render_object_to_surface(diagram);
            return ok(DiagramType.OBJECT, surface, diagram, "Failed to render object diagram");
        }

        private RenderResult render_deployment_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = deployment_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.nodes.size == 0) {
                return empty(DiagramType.DEPLOYMENT,
                    "Enter deployment diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "node \"Web Server\" {\n" +
                    "  [Apache]\n" +
                    "  [PHP]\n" +
                    "}\n" +
                    "device \"Mobile\" as mobile\n" +
                    "database \"MySQL\" as db\n" +
                    "[Apache] --> db : SQL\n" +
                    "mobile --> [Apache] : HTTP\n" +
                    "@enduml");
            }
            var surface = renderer.render_deployment_to_surface(diagram);
            return ok(DiagramType.DEPLOYMENT, surface, diagram, "Failed to render deployment diagram");
        }

        private RenderResult render_er_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = er_parser.parse(tokens);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.entities.size == 0) {
                return empty(DiagramType.ER_DIAGRAM,
                    "Enter ER diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "entity User {\n" +
                    "  *user_id : int <<PK>>\n" +
                    "  --\n" +
                    "  name : varchar\n" +
                    "  email : varchar\n" +
                    "}\n\n" +
                    "entity Order {\n" +
                    "  *order_id : int <<PK>>\n" +
                    "  --\n" +
                    "  user_id : int <<FK>>\n" +
                    "  total : decimal\n" +
                    "}\n\n" +
                    "User ||--o{ Order : places\n" +
                    "@enduml");
            }
            var surface = renderer.render_er_to_surface(diagram);
            return ok(DiagramType.ER_DIAGRAM, surface, diagram, "Failed to render ER diagram");
        }

        private RenderResult render_mindmap_diagram(string source, DiagramType type) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();
            var diagram = mindmap_parser.parse(tokens, type);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.root == null) {
                string example = type == DiagramType.WBS ?
                    "Enter WBS diagram code.\n\n" +
                    "Example:\n" +
                    "@startwbs\n" +
                    "* Project\n" +
                    "** Phase 1\n" +
                    "*** Task 1.1\n" +
                    "*** Task 1.2\n" +
                    "** Phase 2\n" +
                    "*** Task 2.1\n" +
                    "@endwbs"
                    :
                    "Enter MindMap diagram code.\n\n" +
                    "Example:\n" +
                    "@startmindmap\n" +
                    "* Root Topic\n" +
                    "** Branch 1\n" +
                    "*** Leaf 1.1\n" +
                    "*** Leaf 1.2\n" +
                    "** Branch 2\n" +
                    "left side\n" +
                    "** Left Branch\n" +
                    "@endmindmap";
                return empty(type, example);
            }
            var surface = renderer.render_mindmap_to_surface(diagram);
            return ok(type, surface, diagram, "Failed to render MindMap/WBS diagram");
        }

        private RenderResult render_gantt_diagram(string source) {
            var diagram = gantt_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.GANTT,
                    "Enter Gantt diagram code.\n\n" +
                    "Example:\n" +
                    "@startgantt\n" +
                    "[Task 1] requires 3 days\n" +
                    "[Task 2] requires 5 days\n" +
                    "[Task 2] starts at [Task 1]'s end\n" +
                    "@endgantt");
            }
            var surface = renderer.render_gantt_to_surface(diagram);
            return ok(DiagramType.GANTT, surface, diagram, "Failed to render Gantt diagram");
        }

        private RenderResult render_json_diagram(string source) {
            var diagram = json_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.root == null) {
                return empty(DiagramType.JSON_DIAGRAM,
                    "Enter JSON diagram code.\n\n" +
                    "Example:\n" +
                    "@startjson\n" +
                    "{\n" +
                    "  \"name\": \"Alice\",\n" +
                    "  \"age\": 30\n" +
                    "}\n" +
                    "@endjson");
            }
            var surface = renderer.render_json_to_surface(diagram);
            return ok(DiagramType.JSON_DIAGRAM, surface, diagram, "Failed to render JSON diagram");
        }

        private RenderResult render_yaml_diagram(string source) {
            var diagram = yaml_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.root == null) {
                return empty(DiagramType.YAML_DIAGRAM,
                    "Enter YAML diagram code.\n\n" +
                    "Example:\n" +
                    "@startyaml\n" +
                    "key: value\n" +
                    "nested:\n" +
                    "  child: data\n" +
                    "list:\n" +
                    "  - item1\n" +
                    "  - item2\n" +
                    "@endyaml");
            }
            var surface = renderer.render_yaml_to_surface(diagram);
            return ok(DiagramType.YAML_DIAGRAM, surface, diagram, "Failed to render YAML diagram");
        }

        private RenderResult render_chronology_diagram(string source) {
            var diagram = chronology_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.CHRONOLOGY,
                    "Enter Chronology diagram code.\n\n" +
                    "Example:\n" +
                    "@startchronology\n" +
                    "title Project History\n" +
                    "[Event One] happens on 2024-01-15\n" +
                    "[Event Two] happens on 2024-03-01\n" +
                    "@endchronology");
            }
            var surface = renderer.render_chronology_to_surface(diagram);
            return ok(DiagramType.CHRONOLOGY, surface, diagram, "Failed to render Chronology diagram");
        }

        private RenderResult render_timing_diagram(string source) {
            var diagram = timing_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.TIMING,
                    "Enter Timing diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "robust \"HTTP\" as HTTP\n" +
                    "binary \"ACK\" as ACK\n" +
                    "@0\n" +
                    "HTTP is Idle\n" +
                    "ACK is 0\n" +
                    "@100\n" +
                    "HTTP is RequestSent\n" +
                    "ACK is 1\n" +
                    "@enduml");
            }
            var surface = renderer.render_timing_to_surface(diagram);
            return ok(DiagramType.TIMING, surface, diagram, "Failed to render Timing diagram");
        }

        private RenderResult render_nwdiag_diagram(string source) {
            var diagram = nwdiag_parser.parse(source);
            if (diagram.has_errors()) return parse_error(diagram.errors, errors_message(diagram.errors));
            if (diagram.is_empty()) {
                return empty(DiagramType.NWDIAG,
                    "Enter Network diagram code.\n\n" +
                    "Example:\n" +
                    "@startnwdiag\n" +
                    "nwdiag {\n" +
                    "  network dmz {\n" +
                    "    address = \"192.168.1.x/24\"\n" +
                    "    web01 [address = \"192.168.1.10\"]\n" +
                    "  }\n" +
                    "}\n" +
                    "@endnwdiag");
            }
            var surface = renderer.render_nwdiag_to_surface(diagram);
            return ok(DiagramType.NWDIAG, surface, diagram, "Failed to render Network diagram");
        }

        private RenderResult render_archimate_diagram(string source) {
            var diagram = archimate_parser.parse(source);
            if (diagram.has_errors() && diagram.elements.size == 0) {
                return parse_error(diagram.errors, errors_message(diagram.errors));
            }
            if (diagram.is_empty()) {
                return empty(DiagramType.ARCHIMATE,
                    "Enter Archimate diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "archimate #Business \"Customer\" as cust\n" +
                    "archimate #Application \"Web App\" as app\n" +
                    "cust --> app : uses\n" +
                    "@enduml");
            }
            var surface = renderer.render_archimate_to_surface(diagram);
            return ok(DiagramType.ARCHIMATE, surface, diagram, "Failed to render Archimate diagram");
        }

        // Generic render for the newer PlantUML types (DOT, Tree, Board,
        // Ditaa, Salt, Chen, EBNF, Regex, Ancestry) that all follow the same
        // pattern: parse source → generate DOT → render via Graphviz. Produces
        // no AST for the outline (ast == null).
        private RenderResult render_generic_plantuml(string source, DiagramType type) {
            string? dot_output = null;
            unowned Gvc.Context ctx = renderer.get_context();

            switch (type) {
                case DiagramType.DOT_DIAGRAM: {
                    var p = new DotDiagramParser();
                    var d = p.parse(source);
                    var r = new DotDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.TREE: {
                    var p = new TreeDiagramParser();
                    var d = p.parse(source);
                    var r = new TreeDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.BOARD: {
                    var p = new BoardDiagramParser();
                    var d = p.parse(source);
                    var r = new BoardDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.DITAA: {
                    var p = new DitaaDiagramParser();
                    var d = p.parse(source);
                    var r = new DitaaDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.SALT: {
                    var p = new SaltDiagramParser();
                    var d = p.parse(source);
                    var r = new SaltDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.CHEN_ER: {
                    var p = new ChenDiagramParser();
                    var d = p.parse(source);
                    var r = new ChenDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.EBNF: {
                    var p = new EbnfDiagramParser();
                    var d = p.parse(source);
                    var r = new EbnfDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.REGEX_DIAGRAM: {
                    var p = new RegexDiagramParser();
                    var d = p.parse(source);
                    var r = new RegexDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                case DiagramType.ANCESTRY: {
                    AncestryDiagram d;
                    if (source.strip().has_prefix("0 ")) {
                        var gp = new GedcomParser();
                        d = gp.parse(source);
                    } else {
                        var ap = new AncestryDiagramParser();
                        d = ap.parse(source);
                    }
                    var r = new AncestryDiagramRenderer(ctx, renderer.last_regions, "dot");
                    dot_output = r.generate_dot(d);
                    break;
                }
                default:
                    return unknown("Unsupported diagram type");
            }

            if (dot_output == null || dot_output.length == 0) {
                return unknown("Failed to generate diagram");
            }

            // Render DOT → SVG → Surface via libgvc
            var graph = Gvc.Graph.read_string(dot_output);
            if (graph == null) {
                return unknown("Failed to parse DOT output");
            }

            ctx.layout(graph, "dot");
            uint8[] svg_data;
            int ret = GraphvizCompat.render_data(ctx, graph, "svg", out svg_data);
            ctx.free_layout(graph);

            if (ret != 0 || svg_data == null || svg_data.length == 0) {
                return unknown("Failed to render diagram");
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);
                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);
                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);
                cr.set_source_rgb(1, 1, 1);
                cr.paint();
                var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                RenderUtils.parse_svg_regions(svg_data, renderer.last_regions, element_lines, width, height);

                return ok(type, surface, null);
            } catch (Error e) {
                return unknown("Render error: %s".printf(e.message));
            }
        }

        // ==================== Export ====================

        public bool export_to_png(string source, string? doc_filename, string? base_path, string filename) {
            if (detect_format(source, doc_filename) == DiagramFormat.MERMAID) {
                return export_mermaid_diagram(source, "png", filename);
            }
            string processed_source = preprocess(source, base_path);
            var diagram_type = detect_plantuml_type(processed_source);
            var lexer = new Lexer(processed_source);
            var tokens = lexer.scan_all();

            switch (diagram_type) {
                case DiagramType.CLASS:
                    var class_diagram = class_parser.parse(tokens);
                    if (class_diagram.has_errors() || class_diagram.classes.size == 0) return false;
                    return renderer.export_class_to_png(class_diagram, filename);
                case DiagramType.ACTIVITY:
                    var activity_diagram = activity_parser.parse(tokens);
                    if (activity_diagram.has_errors() || activity_diagram.nodes.size == 0) return false;
                    return renderer.export_activity_to_png(activity_diagram, filename);
                case DiagramType.USECASE:
                    var usecase_diagram = usecase_parser.parse(tokens);
                    if (usecase_diagram.has_errors()) return false;
                    return renderer.export_usecase_to_png(usecase_diagram, filename);
                case DiagramType.STATE:
                    var state_diagram = state_parser.parse(tokens);
                    if (state_diagram.has_errors()) return false;
                    return renderer.export_state_to_png(state_diagram, filename);
                case DiagramType.COMPONENT:
                    var component_diagram = component_parser.parse(tokens);
                    if (component_diagram.has_errors()) return false;
                    return renderer.export_component_to_png(component_diagram, filename);
                case DiagramType.OBJECT:
                    var object_diagram = object_parser.parse(tokens);
                    if (object_diagram.has_errors()) return false;
                    return renderer.export_object_to_png(object_diagram, filename);
                case DiagramType.DEPLOYMENT:
                    var deployment_diagram = deployment_parser.parse(tokens);
                    if (deployment_diagram.has_errors()) return false;
                    return renderer.export_deployment_to_png(deployment_diagram, filename);
                case DiagramType.ER_DIAGRAM:
                    var er_diagram = er_parser.parse(tokens);
                    if (er_diagram.has_errors()) return false;
                    return renderer.export_er_to_png(er_diagram, filename);
                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    var mm_diagram = mindmap_parser.parse(tokens, diagram_type);
                    if (mm_diagram.has_errors()) return false;
                    return renderer.export_mindmap_to_png(mm_diagram, filename);
                case DiagramType.GANTT: {
                    var gantt_d = gantt_parser.parse(processed_source);
                    if (gantt_d.has_errors() || gantt_d.is_empty()) return false;
                    return renderer.export_gantt_to_png(gantt_d, filename);
                }
                case DiagramType.JSON_DIAGRAM: {
                    var json_d = json_parser.parse(processed_source);
                    if (json_d.has_errors() || json_d.is_empty()) return false;
                    return renderer.export_json_to_png(json_d, filename);
                }
                case DiagramType.YAML_DIAGRAM: {
                    var yaml_d = yaml_parser.parse(processed_source);
                    if (yaml_d.has_errors() || yaml_d.is_empty()) return false;
                    return renderer.export_yaml_to_png(yaml_d, filename);
                }
                case DiagramType.CHRONOLOGY: {
                    var chron_d = chronology_parser.parse(processed_source);
                    if (chron_d.has_errors() || chron_d.is_empty()) return false;
                    return renderer.export_chronology_to_png(chron_d, filename);
                }
                case DiagramType.TIMING: {
                    var timing_d = timing_parser.parse(processed_source);
                    if (timing_d.has_errors() || timing_d.is_empty()) return false;
                    return renderer.export_timing_to_png(timing_d, filename);
                }
                case DiagramType.NWDIAG: {
                    var nwdiag_d = nwdiag_parser.parse(processed_source);
                    if (nwdiag_d.has_errors() || nwdiag_d.is_empty()) return false;
                    return renderer.export_nwdiag_to_png(nwdiag_d, filename);
                }
                case DiagramType.ARCHIMATE: {
                    var arch_d = archimate_parser.parse(processed_source);
                    if (arch_d.is_empty()) return false;
                    return renderer.export_archimate_to_png(arch_d, filename);
                }
                default:
                    var seq_diagram = parser.parse(processed_source);
                    if (seq_diagram.has_errors() || seq_diagram.participants.size == 0) return false;
                    return renderer.export_to_png(seq_diagram, filename);
            }
        }

        public bool export_to_svg(string source, string? doc_filename, string? base_path, string filename) {
            if (detect_format(source, doc_filename) == DiagramFormat.MERMAID) {
                return export_mermaid_diagram(source, "svg", filename);
            }
            string processed_source = preprocess(source, base_path);
            var diagram_type = detect_plantuml_type(processed_source);
            var lexer = new Lexer(processed_source);
            var tokens = lexer.scan_all();

            switch (diagram_type) {
                case DiagramType.CLASS:
                    var class_diagram = class_parser.parse(tokens);
                    if (class_diagram.has_errors() || class_diagram.classes.size == 0) return false;
                    return renderer.export_class_to_svg(class_diagram, filename);
                case DiagramType.ACTIVITY:
                    var activity_diagram = activity_parser.parse(tokens);
                    if (activity_diagram.has_errors() || activity_diagram.nodes.size == 0) return false;
                    return renderer.export_activity_to_svg(activity_diagram, filename);
                case DiagramType.USECASE:
                    var usecase_diagram = usecase_parser.parse(tokens);
                    if (usecase_diagram.has_errors()) return false;
                    return renderer.export_usecase_to_svg(usecase_diagram, filename);
                case DiagramType.STATE:
                    var state_diagram = state_parser.parse(tokens);
                    if (state_diagram.has_errors()) return false;
                    return renderer.export_state_to_svg(state_diagram, filename);
                case DiagramType.COMPONENT:
                    var component_diagram = component_parser.parse(tokens);
                    if (component_diagram.has_errors()) return false;
                    return renderer.export_component_to_svg(component_diagram, filename);
                case DiagramType.OBJECT:
                    var object_diagram = object_parser.parse(tokens);
                    if (object_diagram.has_errors()) return false;
                    return renderer.export_object_to_svg(object_diagram, filename);
                case DiagramType.DEPLOYMENT:
                    var deployment_diagram = deployment_parser.parse(tokens);
                    if (deployment_diagram.has_errors()) return false;
                    return renderer.export_deployment_to_svg(deployment_diagram, filename);
                case DiagramType.ER_DIAGRAM:
                    var er_diagram = er_parser.parse(tokens);
                    if (er_diagram.has_errors()) return false;
                    return renderer.export_er_to_svg(er_diagram, filename);
                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    var mm_diagram = mindmap_parser.parse(tokens, diagram_type);
                    if (mm_diagram.has_errors()) return false;
                    return renderer.export_mindmap_to_svg(mm_diagram, filename);
                case DiagramType.GANTT: {
                    var gantt_d = gantt_parser.parse(processed_source);
                    if (gantt_d.has_errors() || gantt_d.is_empty()) return false;
                    return renderer.export_gantt_to_svg(gantt_d, filename);
                }
                case DiagramType.JSON_DIAGRAM: {
                    var json_d = json_parser.parse(processed_source);
                    if (json_d.has_errors() || json_d.is_empty()) return false;
                    return renderer.export_json_to_svg(json_d, filename);
                }
                case DiagramType.YAML_DIAGRAM: {
                    var yaml_d = yaml_parser.parse(processed_source);
                    if (yaml_d.has_errors() || yaml_d.is_empty()) return false;
                    return renderer.export_yaml_to_svg(yaml_d, filename);
                }
                case DiagramType.CHRONOLOGY: {
                    var chron_d = chronology_parser.parse(processed_source);
                    if (chron_d.has_errors() || chron_d.is_empty()) return false;
                    return renderer.export_chronology_to_svg(chron_d, filename);
                }
                case DiagramType.TIMING: {
                    var timing_d = timing_parser.parse(processed_source);
                    if (timing_d.has_errors() || timing_d.is_empty()) return false;
                    return renderer.export_timing_to_svg(timing_d, filename);
                }
                case DiagramType.NWDIAG: {
                    var nwdiag_d = nwdiag_parser.parse(processed_source);
                    if (nwdiag_d.has_errors() || nwdiag_d.is_empty()) return false;
                    return renderer.export_nwdiag_to_svg(nwdiag_d, filename);
                }
                case DiagramType.ARCHIMATE: {
                    var arch_d = archimate_parser.parse(processed_source);
                    if (arch_d.is_empty()) return false;
                    return renderer.export_archimate_to_svg(arch_d, filename);
                }
                default:
                    var seq_diagram = parser.parse(processed_source);
                    if (seq_diagram.has_errors() || seq_diagram.participants.size == 0) return false;
                    return renderer.export_to_svg(seq_diagram, filename);
            }
        }

        public bool export_to_pdf(string source, string? doc_filename, string? base_path, string filename) {
            if (detect_format(source, doc_filename) == DiagramFormat.MERMAID) {
                return export_mermaid_diagram(source, "pdf", filename);
            }
            string processed_source = preprocess(source, base_path);
            var diagram_type = detect_plantuml_type(processed_source);
            var lexer = new Lexer(processed_source);
            var tokens = lexer.scan_all();

            switch (diagram_type) {
                case DiagramType.CLASS:
                    var class_diagram = class_parser.parse(tokens);
                    if (class_diagram.has_errors() || class_diagram.classes.size == 0) return false;
                    return renderer.export_class_to_pdf(class_diagram, filename);
                case DiagramType.ACTIVITY:
                    var activity_diagram = activity_parser.parse(tokens);
                    if (activity_diagram.has_errors() || activity_diagram.nodes.size == 0) return false;
                    return renderer.export_activity_to_pdf(activity_diagram, filename);
                case DiagramType.USECASE:
                    var usecase_diagram = usecase_parser.parse(tokens);
                    if (usecase_diagram.has_errors()) return false;
                    return renderer.export_usecase_to_pdf(usecase_diagram, filename);
                case DiagramType.STATE:
                    var state_diagram = state_parser.parse(tokens);
                    if (state_diagram.has_errors()) return false;
                    return renderer.export_state_to_pdf(state_diagram, filename);
                case DiagramType.COMPONENT:
                    var component_diagram = component_parser.parse(tokens);
                    if (component_diagram.has_errors()) return false;
                    return renderer.export_component_to_pdf(component_diagram, filename);
                case DiagramType.OBJECT:
                    var object_diagram = object_parser.parse(tokens);
                    if (object_diagram.has_errors()) return false;
                    return renderer.export_object_to_pdf(object_diagram, filename);
                case DiagramType.DEPLOYMENT:
                    var deployment_diagram = deployment_parser.parse(tokens);
                    if (deployment_diagram.has_errors()) return false;
                    return renderer.export_deployment_to_pdf(deployment_diagram, filename);
                case DiagramType.ER_DIAGRAM:
                    var er_diagram = er_parser.parse(tokens);
                    if (er_diagram.has_errors()) return false;
                    return renderer.export_er_to_pdf(er_diagram, filename);
                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    var mm_diagram = mindmap_parser.parse(tokens, diagram_type);
                    if (mm_diagram.has_errors()) return false;
                    return renderer.export_mindmap_to_pdf(mm_diagram, filename);
                case DiagramType.GANTT: {
                    var gantt_d = gantt_parser.parse(processed_source);
                    if (gantt_d.has_errors() || gantt_d.is_empty()) return false;
                    return renderer.export_gantt_to_pdf(gantt_d, filename);
                }
                case DiagramType.JSON_DIAGRAM: {
                    var json_d = json_parser.parse(processed_source);
                    if (json_d.has_errors() || json_d.is_empty()) return false;
                    return renderer.export_json_to_pdf(json_d, filename);
                }
                case DiagramType.YAML_DIAGRAM: {
                    var yaml_d = yaml_parser.parse(processed_source);
                    if (yaml_d.has_errors() || yaml_d.is_empty()) return false;
                    return renderer.export_yaml_to_pdf(yaml_d, filename);
                }
                case DiagramType.CHRONOLOGY: {
                    var chron_d = chronology_parser.parse(processed_source);
                    if (chron_d.has_errors() || chron_d.is_empty()) return false;
                    return renderer.export_chronology_to_pdf(chron_d, filename);
                }
                case DiagramType.TIMING: {
                    var timing_d = timing_parser.parse(processed_source);
                    if (timing_d.has_errors() || timing_d.is_empty()) return false;
                    return renderer.export_timing_to_pdf(timing_d, filename);
                }
                case DiagramType.NWDIAG: {
                    var nwdiag_d = nwdiag_parser.parse(processed_source);
                    if (nwdiag_d.has_errors() || nwdiag_d.is_empty()) return false;
                    return renderer.export_nwdiag_to_pdf(nwdiag_d, filename);
                }
                case DiagramType.ARCHIMATE: {
                    var arch_d = archimate_parser.parse(processed_source);
                    if (arch_d.is_empty()) return false;
                    return renderer.export_archimate_to_pdf(arch_d, filename);
                }
                default:
                    var seq_diagram = parser.parse(processed_source);
                    if (seq_diagram.has_errors() || seq_diagram.participants.size == 0) return false;
                    return renderer.export_to_pdf(seq_diagram, filename);
            }
        }

        // Export a Mermaid diagram to the given format ("png", "svg", or "pdf").
        // Returns false if the diagram has parse errors or rendering fails.
        private bool export_mermaid_diagram(string source, string format, string filename) {
            var mtype = detect_mermaid_type(source);
            switch (mtype) {
                case DiagramType.MERMAID_FLOWCHART: {
                    var d = mermaid_flowchart_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_flowchart_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_flowchart_renderer.export_to_pdf(d, filename);
                    return mermaid_flowchart_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_SEQUENCE: {
                    var d = mermaid_sequence_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_sequence_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_sequence_renderer.export_to_pdf(d, filename);
                    return mermaid_sequence_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_STATE: {
                    var d = mermaid_state_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_state_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_state_renderer.export_to_pdf(d, filename);
                    return mermaid_state_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_CLASS: {
                    var d = mermaid_class_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_class_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_class_renderer.export_to_pdf(d, filename);
                    return mermaid_class_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_ER: {
                    var d = mermaid_er_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_er_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_er_renderer.export_to_pdf(d, filename);
                    return mermaid_er_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_GANTT: {
                    var d = mermaid_gantt_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_gantt_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_gantt_renderer.export_to_pdf(d, filename);
                    return mermaid_gantt_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_PIE: {
                    var d = mermaid_pie_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_pie_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_pie_renderer.export_to_pdf(d, filename);
                    return mermaid_pie_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_USER_JOURNEY: {
                    var d = mermaid_user_journey_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_user_journey_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_user_journey_renderer.export_to_pdf(d, filename);
                    return mermaid_user_journey_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_GIT_GRAPH: {
                    var d = mermaid_git_graph_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_git_graph_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_git_graph_renderer.export_to_pdf(d, filename);
                    return mermaid_git_graph_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_MINDMAP: {
                    var d = mermaid_mindmap_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_mindmap_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_mindmap_renderer.export_to_pdf(d, filename);
                    return mermaid_mindmap_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_TIMELINE: {
                    var d = mermaid_timeline_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_timeline_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_timeline_renderer.export_to_pdf(d, filename);
                    return mermaid_timeline_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_QUADRANT: {
                    var d = mermaid_quadrant_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_quadrant_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_quadrant_renderer.export_to_pdf(d, filename);
                    return mermaid_quadrant_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_XYCHART: {
                    var d = mermaid_xychart_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_xychart_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_xychart_renderer.export_to_pdf(d, filename);
                    return mermaid_xychart_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_KANBAN: {
                    var d = mermaid_kanban_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_kanban_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_kanban_renderer.export_to_pdf(d, filename);
                    return mermaid_kanban_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_SANKEY: {
                    var d = mermaid_sankey_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_sankey_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_sankey_renderer.export_to_pdf(d, filename);
                    return mermaid_sankey_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_REQUIREMENT: {
                    var d = mermaid_requirement_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_requirement_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_requirement_renderer.export_to_pdf(d, filename);
                    return mermaid_requirement_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_BLOCK: {
                    var d = mermaid_block_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_block_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_block_renderer.export_to_pdf(d, filename);
                    return mermaid_block_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_PACKET: {
                    var d = mermaid_packet_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return mermaid_packet_renderer.export_to_svg(d, filename);
                    if (format == "pdf") return mermaid_packet_renderer.export_to_pdf(d, filename);
                    return mermaid_packet_renderer.export_to_png(d, filename);
                }
                case DiagramType.MERMAID_C4: {
                    var d = mermaid_c4_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return renderer.export_mermaid_c4_to_svg(d, filename);
                    if (format == "pdf") return renderer.export_mermaid_c4_to_pdf(d, filename);
                    return renderer.export_mermaid_c4_to_png(d, filename);
                }
                case DiagramType.MERMAID_ARCHITECTURE: {
                    var d = mermaid_architecture_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return renderer.export_mermaid_architecture_to_svg(d, filename);
                    if (format == "pdf") return renderer.export_mermaid_architecture_to_pdf(d, filename);
                    return renderer.export_mermaid_architecture_to_png(d, filename);
                }
                case DiagramType.MERMAID_ZENUML: {
                    var d = mermaid_zenuml_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return renderer.export_mermaid_zenuml_to_svg(d, filename);
                    if (format == "pdf") return renderer.export_mermaid_zenuml_to_pdf(d, filename);
                    return renderer.export_mermaid_zenuml_to_png(d, filename);
                }
                case DiagramType.MERMAID_RADAR: {
                    var d = mermaid_radar_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return renderer.export_mermaid_radar_to_svg(d, filename);
                    if (format == "pdf") return renderer.export_mermaid_radar_to_pdf(d, filename);
                    return renderer.export_mermaid_radar_to_png(d, filename);
                }
                case DiagramType.MERMAID_TREEMAP: {
                    var d = mermaid_treemap_parser.parse(source);
                    if (d.has_errors()) return false;
                    if (format == "svg") return renderer.export_mermaid_treemap_to_svg(d, filename);
                    if (format == "pdf") return renderer.export_mermaid_treemap_to_pdf(d, filename);
                    return renderer.export_mermaid_treemap_to_png(d, filename);
                }
                default:
                    return false;
            }
        }

        // ==================== DOT generation (headless CLI) ====================

        // Produce raw Graphviz DOT for `source`, mirroring the export
        // pipeline's parse step but stopping at DOT rather than rendering.
        // Used by the headless CLI `-f dot` path. Returns null on an
        // unknown/unsupported diagram type or parse failure.
        public string? generate_dot(string source, string? doc_filename, string? base_path) {
            if (detect_format(source, doc_filename) == DiagramFormat.MERMAID) {
                return generate_mermaid_dot(source);
            }
            string processed = preprocess(source, base_path);
            var type = detect_plantuml_type(processed);
            return generate_plantuml_dot(processed, type);
        }

        private string? generate_plantuml_dot(string processed, DiagramType type) {
            unowned Gvc.Context ctx = renderer.get_context();
            var regions = renderer.last_regions;
            var lexer = new Lexer(processed);
            var tokens = lexer.scan_all();

            switch (type) {
                case DiagramType.ACTIVITY: {
                    var d = activity_parser.parse(tokens);
                    return new ActivityDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.COMPONENT: {
                    var d = component_parser.parse(tokens);
                    return new ComponentDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.DEPLOYMENT: {
                    var d = deployment_parser.parse(tokens);
                    return new DeploymentDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.CLASS: {
                    var d = class_parser.parse(tokens);
                    return new ClassDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.STATE: {
                    var d = state_parser.parse(tokens);
                    return new StateDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.SEQUENCE: {
                    var d = parser.parse(processed);
                    return new SequenceDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.USECASE: {
                    var d = usecase_parser.parse(tokens);
                    return new UseCaseDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.OBJECT: {
                    var d = object_parser.parse(tokens);
                    return new ObjectDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.ER_DIAGRAM: {
                    var d = er_parser.parse(tokens);
                    return new ERDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.MINDMAP:
                case DiagramType.WBS: {
                    var d = mindmap_parser.parse(tokens, type);
                    return new MindMapDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.GANTT: {
                    var d = gantt_parser.parse(processed);
                    return new GanttDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.JSON_DIAGRAM: {
                    var d = json_parser.parse(processed);
                    return new JsonDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.YAML_DIAGRAM: {
                    var d = yaml_parser.parse(processed);
                    return new YamlDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.CHRONOLOGY: {
                    var d = chronology_parser.parse(processed);
                    return new ChronologyDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.TIMING: {
                    var d = timing_parser.parse(processed);
                    return new TimingDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.NWDIAG: {
                    var d = nwdiag_parser.parse(processed);
                    return new NwdiagDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.ARCHIMATE: {
                    var d = archimate_parser.parse(processed);
                    return new ArchimateDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.DOT_DIAGRAM: {
                    var d = new DotDiagramParser().parse(processed);
                    return new DotDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.TREE: {
                    var d = new TreeDiagramParser().parse(processed);
                    return new TreeDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.BOARD: {
                    var d = new BoardDiagramParser().parse(processed);
                    return new BoardDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.DITAA: {
                    var d = new DitaaDiagramParser().parse(processed);
                    return new DitaaDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.SALT: {
                    var d = new SaltDiagramParser().parse(processed);
                    return new SaltDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.CHEN_ER: {
                    var d = new ChenDiagramParser().parse(processed);
                    return new ChenDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.EBNF: {
                    var d = new EbnfDiagramParser().parse(processed);
                    return new EbnfDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.REGEX_DIAGRAM: {
                    var d = new RegexDiagramParser().parse(processed);
                    return new RegexDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.ANCESTRY: {
                    AncestryDiagram d;
                    if (processed.strip().has_prefix("0 ")) {
                        d = new GedcomParser().parse(processed);
                    } else {
                        d = new AncestryDiagramParser().parse(processed);
                    }
                    return new AncestryDiagramRenderer(ctx, regions, "dot").generate_dot(d);
                }
                default:
                    return null;
            }
        }

        private string? generate_mermaid_dot(string source) {
            unowned Gvc.Context ctx = mermaid_context;
            var regions = renderer.last_regions;
            var mtype = detect_mermaid_type(source);
            switch (mtype) {
                case DiagramType.MERMAID_FLOWCHART: {
                    var d = mermaid_flowchart_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_flowchart_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_SEQUENCE: {
                    var d = mermaid_sequence_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_sequence_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_STATE: {
                    var d = mermaid_state_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_state_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_CLASS: {
                    var d = mermaid_class_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_class_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_ER: {
                    var d = mermaid_er_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_er_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_GANTT: {
                    var d = mermaid_gantt_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_gantt_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_PIE: {
                    var d = mermaid_pie_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_pie_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_USER_JOURNEY: {
                    var d = mermaid_user_journey_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_user_journey_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_GIT_GRAPH: {
                    var d = mermaid_git_graph_parser.parse(source);
                    return mermaid_git_graph_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_MINDMAP: {
                    var d = mermaid_mindmap_parser.parse(source);
                    return mermaid_mindmap_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_TIMELINE: {
                    var d = mermaid_timeline_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_timeline_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_QUADRANT: {
                    var d = mermaid_quadrant_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_quadrant_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_XYCHART: {
                    var d = mermaid_xychart_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_xychart_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_KANBAN: {
                    var d = mermaid_kanban_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_kanban_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_SANKEY: {
                    var d = mermaid_sankey_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_sankey_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_REQUIREMENT: {
                    var d = mermaid_requirement_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_requirement_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_BLOCK: {
                    var d = mermaid_block_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_block_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_PACKET: {
                    var d = mermaid_packet_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_packet_renderer.generate_dot(d);
                }
                case DiagramType.MERMAID_C4: {
                    var d = mermaid_c4_parser.parse(source);
                    if (d.has_errors()) return null;
                    return new MermaidC4Renderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.MERMAID_ARCHITECTURE: {
                    var d = mermaid_architecture_parser.parse(source);
                    if (d.has_errors()) return null;
                    return new MermaidArchitectureRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.MERMAID_ZENUML: {
                    var d = mermaid_zenuml_parser.parse(source);
                    if (d.has_errors()) return null;
                    return new MermaidZenUMLRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.MERMAID_RADAR: {
                    var d = mermaid_radar_parser.parse(source);
                    if (d.has_errors()) return null;
                    return new MermaidRadarRenderer(ctx, regions, "dot").generate_dot(d);
                }
                case DiagramType.MERMAID_TREEMAP: {
                    var d = mermaid_treemap_parser.parse(source);
                    if (d.has_errors()) return null;
                    return new MermaidTreemapRenderer(ctx, regions, "dot").generate_dot(d);
                }
                default:
                    return null;
            }
        }

        // ==================== SVG generation (LSP / headless) ====================

        // Produce rendered SVG bytes for `source`, mirroring the export
        // pipeline's parse step but returning the SVG payload in-memory rather
        // than writing a file. Used by the LSP `gdiagram/renderSvg` command.
        // Reuses the engine's shared parser/renderer instances. Returns null on
        // an unknown/unsupported diagram type or a parse failure.
        public uint8[]? generate_svg(string source, string? doc_filename, string? base_path) {
            if (detect_format(source, doc_filename) == DiagramFormat.MERMAID) {
                return generate_mermaid_svg(source);
            }
            string processed = preprocess(source, base_path);
            var type = detect_plantuml_type(processed);
            return generate_plantuml_svg(processed, type);
        }

        private uint8[]? generate_plantuml_svg(string processed, DiagramType type) {
            var lexer = new Lexer(processed);
            var tokens = lexer.scan_all();

            switch (type) {
                case DiagramType.CLASS: {
                    var d = class_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_class_to_svg(d);
                }
                case DiagramType.ACTIVITY: {
                    var d = activity_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_activity_to_svg(d);
                }
                case DiagramType.USECASE: {
                    var d = usecase_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_usecase_to_svg(d);
                }
                case DiagramType.STATE: {
                    var d = state_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_state_to_svg(d);
                }
                case DiagramType.COMPONENT: {
                    var d = component_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_component_to_svg(d);
                }
                case DiagramType.OBJECT: {
                    var d = object_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_object_to_svg(d);
                }
                case DiagramType.DEPLOYMENT: {
                    var d = deployment_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_deployment_to_svg(d);
                }
                case DiagramType.ER_DIAGRAM: {
                    var d = er_parser.parse(tokens);
                    if (d.has_errors()) return null;
                    return renderer.render_er_to_svg(d);
                }
                case DiagramType.MINDMAP:
                case DiagramType.WBS: {
                    var d = mindmap_parser.parse(tokens, type);
                    if (d.has_errors()) return null;
                    return renderer.render_mindmap_to_svg(d);
                }
                case DiagramType.GANTT: {
                    var d = gantt_parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_gantt_to_svg(d);
                }
                case DiagramType.JSON_DIAGRAM: {
                    var d = json_parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_json_to_svg(d);
                }
                case DiagramType.YAML_DIAGRAM: {
                    var d = yaml_parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_yaml_to_svg(d);
                }
                case DiagramType.CHRONOLOGY: {
                    var d = chronology_parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_chronology_to_svg(d);
                }
                case DiagramType.TIMING: {
                    var d = timing_parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_timing_to_svg(d);
                }
                case DiagramType.NWDIAG: {
                    var d = nwdiag_parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_nwdiag_to_svg(d);
                }
                case DiagramType.ARCHIMATE: {
                    var d = archimate_parser.parse(processed);
                    return renderer.render_archimate_to_svg(d);
                }
                // Generic DOT-based types: render their generated DOT to SVG.
                case DiagramType.DOT_DIAGRAM:
                case DiagramType.TREE:
                case DiagramType.BOARD:
                case DiagramType.DITAA:
                case DiagramType.SALT:
                case DiagramType.CHEN_ER:
                case DiagramType.EBNF:
                case DiagramType.REGEX_DIAGRAM:
                case DiagramType.ANCESTRY:
                    return render_dot_to_svg(generate_plantuml_dot(processed, type));
                case DiagramType.UNKNOWN:
                    return null;
                default: {
                    var d = parser.parse(processed);
                    if (d.has_errors()) return null;
                    return renderer.render_to_svg(d);
                }
            }
        }

        private uint8[]? generate_mermaid_svg(string source) {
            var mtype = detect_mermaid_type(source);
            switch (mtype) {
                case DiagramType.MERMAID_FLOWCHART: {
                    var d = mermaid_flowchart_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_flowchart_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_SEQUENCE: {
                    var d = mermaid_sequence_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_sequence_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_STATE: {
                    var d = mermaid_state_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_state_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_CLASS: {
                    var d = mermaid_class_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_class_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_ER: {
                    var d = mermaid_er_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_er_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_GANTT: {
                    var d = mermaid_gantt_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_gantt_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_PIE: {
                    var d = mermaid_pie_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_pie_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_USER_JOURNEY: {
                    var d = mermaid_user_journey_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_user_journey_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_GIT_GRAPH: {
                    var d = mermaid_git_graph_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_git_graph_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_MINDMAP: {
                    var d = mermaid_mindmap_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_mindmap_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_TIMELINE: {
                    var d = mermaid_timeline_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_timeline_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_QUADRANT: {
                    var d = mermaid_quadrant_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_quadrant_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_XYCHART: {
                    var d = mermaid_xychart_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_xychart_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_KANBAN: {
                    var d = mermaid_kanban_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_kanban_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_SANKEY: {
                    var d = mermaid_sankey_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_sankey_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_REQUIREMENT: {
                    var d = mermaid_requirement_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_requirement_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_BLOCK: {
                    var d = mermaid_block_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_block_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_PACKET: {
                    var d = mermaid_packet_parser.parse(source);
                    if (d.has_errors()) return null;
                    return mermaid_packet_renderer.render_to_svg(d);
                }
                case DiagramType.MERMAID_C4: {
                    var d = mermaid_c4_parser.parse(source);
                    if (d.has_errors()) return null;
                    return renderer.render_mermaid_c4_to_svg(d);
                }
                case DiagramType.MERMAID_ARCHITECTURE: {
                    var d = mermaid_architecture_parser.parse(source);
                    if (d.has_errors()) return null;
                    return renderer.render_mermaid_architecture_to_svg(d);
                }
                case DiagramType.MERMAID_ZENUML: {
                    var d = mermaid_zenuml_parser.parse(source);
                    if (d.has_errors()) return null;
                    return renderer.render_mermaid_zenuml_to_svg(d);
                }
                case DiagramType.MERMAID_RADAR: {
                    var d = mermaid_radar_parser.parse(source);
                    if (d.has_errors()) return null;
                    return renderer.render_mermaid_radar_to_svg(d);
                }
                case DiagramType.MERMAID_TREEMAP: {
                    var d = mermaid_treemap_parser.parse(source);
                    if (d.has_errors()) return null;
                    return renderer.render_mermaid_treemap_to_svg(d);
                }
                default:
                    return null;
            }
        }

        // Render a Graphviz DOT string to SVG bytes via the shared context.
        // Used for the generic DOT-based PlantUML types that have no dedicated
        // render_*_to_svg facade method. Returns null on any failure.
        private uint8[]? render_dot_to_svg(string? dot) {
            if (dot == null || dot.length == 0) return null;
            var graph = Gvc.Graph.read_string(dot);
            if (graph == null) return null;
            unowned Gvc.Context ctx = renderer.get_context();
            ctx.layout(graph, "dot");
            uint8[] svg_data;
            int ret = GraphvizCompat.render_data(ctx, graph, "svg", out svg_data);
            ctx.free_layout(graph);
            if (ret != 0 || svg_data == null || svg_data.length == 0) return null;
            return svg_data;
        }
    }
}
