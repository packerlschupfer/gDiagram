namespace GDiagram {

    // ==================== MERMAID PIE CHART ====================

    public class PieSlice : Object {
        public string label { get; set; }
        public double value { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }

        public PieSlice(string label, double value, int line = 0) {
            this.label = label;
            this.value = value;
            this.color = null;
            this.source_line = line;
        }

        public double get_percentage(double total) {
            if (total == 0) return 0;
            return (value / total) * 100.0;
        }
    }

    public class MermaidPie : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public bool show_data { get; set; }
        public Gee.ArrayList<PieSlice> slices { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidPie() {
            this.diagram_type = MermaidDiagramType.PIE;
            this.title = null;
            this.show_data = false;
            this.slices = new Gee.ArrayList<PieSlice>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_slice(PieSlice slice) {
            slices.add(slice);
        }

        public double get_total() {
            double total = 0;
            foreach (var slice in slices) {
                total += slice.value;
            }
            return total;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
