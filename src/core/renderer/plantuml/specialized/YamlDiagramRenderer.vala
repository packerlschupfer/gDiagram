/* YamlDiagramRenderer.vala — renders PlantUML YAML visualization */
namespace GDiagram {

public class YamlDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> regions;
    private string layout_engine;

    public YamlDiagramRenderer(Gvc.Context ctx,
                                Gee.ArrayList<ElementRegion> regions,
                                string engine) {
        this.context = ctx;
        this.regions = regions;
        this.layout_engine = engine;
    }

    // Drawn like JSON, as PlantUML does: nested tables linked by dashed arrows
    public string generate_dot(YamlDiagram diagram) {
        return DataTableBuilder.diagram_dot(diagram.root != null ? to_json(diagram.root) : null,
            diagram.title, DataTableStyle.from_skin(diagram.skin), diagram.highlights);
    }

    // A YAML tree as the JSON tree the table builder draws; scalars are shown as written
    public static JsonNode to_json(YamlNode node) {
        JsonNode j;
        switch (node.node_type) {
            case YamlNodeType.MAPPING:
                j = new JsonNode(JsonNodeType.OBJECT);
                break;
            case YamlNodeType.SEQUENCE:
                j = new JsonNode(JsonNodeType.ARRAY);
                break;
            default:
                j = new JsonNode(JsonNodeType.STRING);
                j.string_value = node.value ?? "";
                break;
        }
        j.key = node.key;
        foreach (var child in node.children) {
            j.children.add(to_json(child));
        }
        return j;
    }

    public uint8[]? render_to_svg(YamlDiagram diagram) {
        string dot = generate_dot(diagram);

        var graph = RenderUtils.read_dot(dot);
        if (graph == null) {
            warning("Failed to parse YAML DOT graph");
            return null;
        }

        int ret = context.layout(graph, "dot");
        if (ret != 0) {
            warning("Failed to layout YAML graph");
            context.free_layout(graph);
            return null;
        }

        uint8[] svg_data;
        ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

        context.free_layout(graph);

        if (ret != 0) {
            warning("Failed to render YAML diagram to SVG");
            return null;
        }

        return svg_data;
    }

    public Cairo.ImageSurface? render_to_surface(YamlDiagram diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return null;
        }
        return RenderUtils.svg_to_surface(svg_data);
    }

    public bool export_to_png(YamlDiagram diagram, string filename) {
        var surface = render_to_surface(diagram);
        if (surface == null) {
            return false;
        }
        var status = surface.write_to_png(filename);
        return status == Cairo.Status.SUCCESS;
    }

    public bool export_to_svg(YamlDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(YamlDiagram diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) {
            return false;
        }
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
