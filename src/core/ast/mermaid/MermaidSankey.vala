namespace GDiagram {

    // ==================== Sankey ====================

    public class SankeyLink : Object {
        public string source { get; set; }
        public string target { get; set; }
        public double value { get; set; }
        public int source_line { get; set; }

        public SankeyLink(string source, string target, double value, int line = 0) {
            this.source = source;
            this.target = target;
            this.value = value;
            this.source_line = line;
        }
    }

    public class MermaidSankey : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<SankeyLink> links { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidSankey() {
            this.diagram_type = MermaidDiagramType.SANKEY;
            this.links = new Gee.ArrayList<SankeyLink>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_link(SankeyLink l) { links.add(l); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return links.size == 0; }

        // Get unique nodes in order of first appearance
        public Gee.ArrayList<string> get_nodes() {
            var seen = new Gee.HashSet<string>();
            var nodes = new Gee.ArrayList<string>();
            foreach (var link in links) {
                if (!seen.contains(link.source)) { seen.add(link.source); nodes.add(link.source); }
                if (!seen.contains(link.target)) { seen.add(link.target); nodes.add(link.target); }
            }
            return nodes;
        }
    }

}
