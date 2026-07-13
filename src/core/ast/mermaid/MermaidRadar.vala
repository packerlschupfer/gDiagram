namespace GDiagram {

// ==================== Radar ====================

public class RadarAxis : Object {
    public string id { get; set; }
    public string label { get; set; }
    public int source_line { get; set; }

    public RadarAxis(string id, string label, int line = 0) {
        this.id = id;
        this.label = label;
        this.source_line = line;
    }
}

public class RadarCurve : Object {
    public string id { get; set; }
    public string label { get; set; }
    public Gee.ArrayList<double?> values { get; private set; }  // positional values
    public Gee.HashMap<string, double?> key_values { get; private set; }  // axis_id -> value
    public int source_line { get; set; }

    public RadarCurve(string id, string label, int line = 0) {
        this.id = id;
        this.label = label;
        this.values = new Gee.ArrayList<double?>();
        this.key_values = new Gee.HashMap<string, double?>();
        this.source_line = line;
    }
}

public class MermaidRadar : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<RadarAxis> axes { get; private set; }
    public Gee.ArrayList<RadarCurve> curves { get; private set; }
    public double max_value { get; set; }
    public double min_value { get; set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public MermaidRadar() {
        this.diagram_type = MermaidDiagramType.RADAR;
        this.title = null;
        this.axes = new Gee.ArrayList<RadarAxis>();
        this.curves = new Gee.ArrayList<RadarCurve>();
        this.max_value = 100.0;
        this.min_value = 0.0;
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return axes.size == 0; }
}

}
