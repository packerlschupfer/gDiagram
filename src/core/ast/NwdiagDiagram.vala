/* NwdiagDiagram.vala — AST for PlantUML nwdiag network diagrams */
namespace GDiagram {

public class NwNode : Object {
    public string name { get; set; }
    public string? address { get; set; }
    public string? shape { get; set; }
    public string? color { get; set; }
    public string? description { get; set; }
    public int source_line { get; set; }

    public NwNode(string name, int line = 0) {
        this.name = name;
        this.source_line = line;
    }
}

public class NwNetwork : Object {
    public string name { get; set; }
    public string? address { get; set; }
    public string? color { get; set; }
    public Gee.ArrayList<NwNode> nodes { get; private set; }
    public int source_line { get; set; }

    public NwNetwork(string name, int line = 0) {
        this.name = name;
        this.nodes = new Gee.ArrayList<NwNode>();
        this.source_line = line;
    }
}

public class NwGroup : Object {
    public string name { get; set; }
    public string? color { get; set; }
    public Gee.ArrayList<string> node_names { get; private set; }
    public int source_line { get; set; }

    public NwGroup(string name, int line = 0) {
        this.name = name;
        this.node_names = new Gee.ArrayList<string>();
        this.source_line = line;
    }
}

public class NwPeerLink : Object {
    public string node_a { get; set; }
    public string node_b { get; set; }
    public int source_line { get; set; }

    public NwPeerLink(string node_a, string node_b, int line = 0) {
        this.node_a = node_a;
        this.node_b = node_b;
        this.source_line = line;
    }
}

public class NwdiagDiagram : Object {
    public DiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<NwNetwork> networks { get; private set; }
    public Gee.ArrayList<NwGroup> groups { get; private set; }
    public Gee.ArrayList<NwPeerLink> peer_links { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public NwdiagDiagram() {
        this.diagram_type = DiagramType.NWDIAG;
        this.networks = new Gee.ArrayList<NwNetwork>();
        this.groups = new Gee.ArrayList<NwGroup>();
        this.peer_links = new Gee.ArrayList<NwPeerLink>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return networks.size == 0; }
}

}
