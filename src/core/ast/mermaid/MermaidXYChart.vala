namespace GDiagram {

    // ==================== XY Chart ====================

    public enum XYSeriesType {
        BAR,
        LINE
    }

    public class XYSeries : Object {
        public XYSeriesType series_type { get; set; }
        public Gee.ArrayList<double?> values { get; private set; }

        public XYSeries(XYSeriesType t) {
            this.series_type = t;
            this.values = new Gee.ArrayList<double?>();
        }

        public void add_value(double v) { values.add(v); }
    }

    public class MermaidXYChart : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<string> x_labels { get; private set; }
        public string x_axis_label { get; set; default = ""; }
        public string y_axis_label { get; set; default = ""; }
        public double y_min { get; set; default = 0.0; }
        public double y_max { get; set; default = 100.0; }
        public bool has_y_range { get; set; default = false; }
        public Gee.ArrayList<XYSeries> series { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidXYChart() {
            this.diagram_type = MermaidDiagramType.XYCHART;
            this.x_labels = new Gee.ArrayList<string>();
            this.series = new Gee.ArrayList<XYSeries>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_series(XYSeries s) { series.add(s); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return series.size == 0; }
    }

}
