namespace GDiagram {

    // ==================== Quadrant Chart ====================

    public class QuadrantPoint : Object {
        public string label { get; set; }
        public double x { get; set; }
        public double y { get; set; }
        public int source_line { get; set; }

        public QuadrantPoint(string label, double x, double y, int line = 0) {
            this.label = label;
            this.x = x;
            this.y = y;
            this.source_line = line;
        }
    }

    public class MermaidQuadrant : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public string x_axis_left { get; set; default = ""; }
        public string x_axis_right { get; set; default = ""; }
        public string y_axis_bottom { get; set; default = ""; }
        public string y_axis_top { get; set; default = ""; }
        public string quadrant_1 { get; set; default = ""; }
        public string quadrant_2 { get; set; default = ""; }
        public string quadrant_3 { get; set; default = ""; }
        public string quadrant_4 { get; set; default = ""; }
        public Gee.ArrayList<QuadrantPoint> points { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidQuadrant() {
            this.diagram_type = MermaidDiagramType.QUADRANT;
            this.points = new Gee.ArrayList<QuadrantPoint>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_point(QuadrantPoint p) { points.add(p); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return points.size == 0; }
    }

}
