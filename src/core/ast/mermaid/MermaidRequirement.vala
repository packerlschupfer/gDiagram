namespace GDiagram {

    // ==================== Requirement Diagram ====================

    public class ReqElement : Object {
        public string id { get; set; }      // req id field (e.g. "1.1")
        public string name { get; set; }    // diagram identifier (e.g. "test_req2")
        public string req_type { get; set; }    // requirement, functionalRequirement, element, etc.
        public string text { get; set; default = ""; }
        public string risk { get; set; default = ""; }        // high/medium/low
        public string verifymethod { get; set; default = ""; }
        public string docref { get; set; default = ""; }
        public string elem_type { get; set; default = ""; }   // for element nodes: "type" field
        public int source_line { get; set; }

        public ReqElement(string name, string req_type, int line = 0) {
            this.name = name;
            this.req_type = req_type;
            this.id = name;
            this.source_line = line;
        }
    }

    public class ReqRelationship : Object {
        public string source { get; set; }
        public string rel_type { get; set; }
        public string target { get; set; }
        public int source_line { get; set; }

        public ReqRelationship(string source, string rel_type, string target, int line = 0) {
            this.source = source;
            this.rel_type = rel_type;
            this.target = target;
            this.source_line = line;
        }
    }

    public class MermaidRequirement : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<ReqElement> elements { get; private set; }
        public Gee.ArrayList<ReqRelationship> relationships { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidRequirement() {
            this.diagram_type = MermaidDiagramType.REQUIREMENT;
            this.elements = new Gee.ArrayList<ReqElement>();
            this.relationships = new Gee.ArrayList<ReqRelationship>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_element(ReqElement e) { elements.add(e); }
        public void add_relationship(ReqRelationship r) { relationships.add(r); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return elements.size == 0 && relationships.size == 0; }
    }

}
