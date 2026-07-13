namespace GDiagram {

public class MermaidRequirementParser : Object {

    public MermaidRequirementParser() {}

    public MermaidRequirement parse(string source) {
        var diagram = new MermaidRequirement();
        string[] lines = source.split("\n");
        int i = 0;

        while (i < lines.length) {
            string line = lines[i].strip();
            i++;

            if (line.length == 0 || line.has_prefix("%%")) continue;
            if (line.down().has_prefix("requirementdiagram")) continue;

            // Title directive
            if (line.down().has_prefix("title ")) {
                diagram.title = line.substring(6).strip();
                continue;
            }

            // Element/requirement block: "type name {"
            if (line.has_suffix("{")) {
                // Parse: "functionalRequirement test_req2 {"
                string header = line.substring(0, line.length - 1).strip();
                string[] parts = header.split(" ");
                if (parts.length >= 2) {
                    string parsed_type = parts[0];
                    string elem_name = parts[parts.length - 1];
                    var elem = new ReqElement(elem_name, parsed_type, i);

                    // Parse block contents until "}"
                    while (i < lines.length) {
                        string inner = lines[i].strip();
                        i++;
                        if (inner == "}") break;
                        if (inner.length == 0 || inner.has_prefix("%%")) continue;

                        int colon = inner.index_of(":");
                        if (colon >= 0) {
                            string key = inner.substring(0, colon).strip().down();
                            string val = inner.substring(colon + 1).strip();
                            switch (key) {
                                case "id":           elem.id = val; break;
                                case "text":         elem.text = val; break;
                                case "risk":         elem.risk = val.down(); break;
                                case "verifymethod": elem.verifymethod = val; break;
                                case "docref":       elem.docref = val; break;
                                case "type":         elem.elem_type = val; break;
                            }
                        }
                    }
                    diagram.add_element(elem);
                }
                continue;
            }

            // Relationship: "source - type -> target"
            if (line.contains(" - ") && line.contains(" -> ")) {
                int dash = line.index_of(" - ");
                int arrow = line.index_of(" -> ");
                if (dash >= 0 && arrow > dash) {
                    string src = line.substring(0, dash).strip();
                    string rel = line.substring(dash + 3, arrow - dash - 3).strip();
                    string tgt = line.substring(arrow + 4).strip();
                    diagram.add_relationship(new ReqRelationship(src, rel, tgt, i));
                }
                continue;
            }
        }

        return diagram;
    }
}

}
