/* AncestryDiagram.vala — AST for ancestry / family tree diagrams */
namespace GDiagram {

public enum AncestryGender {
    MALE,
    FEMALE,
    UNKNOWN
}

public class AncestryPerson : Object {
    public string id { get; set; }
    public string display_name { get; set; }
    // Full date string: "1920", "1920-03-15", "15 Mar 1920", etc.
    public string? birth_date { get; set; default = null; }
    public string? death_date { get; set; default = null; }
    public AncestryGender gender { get; set; default = AncestryGender.UNKNOWN; }
    public int source_line { get; set; default = 0; }

    public AncestryPerson(string id, string name, int line) {
        this.id = id;
        this.display_name = name;
        this.source_line = line;
    }

    // Format dates for display using ★ (birth) and ✝ (death)
    public string get_date_string() {
        if (birth_date != null && death_date != null)
            return "\xe2\x98\x85 %s  \xe2\x9c\x9d %s".printf(birth_date, death_date);
        if (birth_date != null)
            return "\xe2\x98\x85 %s".printf(birth_date);
        if (death_date != null)
            return "\xe2\x9c\x9d %s".printf(death_date);
        return "";
    }

    public bool is_deceased() {
        return death_date != null;
    }
}

public class AncestryMarriage : Object {
    public string person1_id { get; set; }
    public string person2_id { get; set; }
    public string? year { get; set; default = null; }
    public int source_line { get; set; default = 0; }

    public AncestryMarriage(string p1, string p2, int line) {
        this.person1_id = p1;
        this.person2_id = p2;
        this.source_line = line;
    }
}

public class AncestryChildLink : Object {
    public string parent_id { get; set; }
    public string child_id { get; set; }
    public int source_line { get; set; default = 0; }

    public AncestryChildLink(string parent, string child, int line) {
        this.parent_id = parent;
        this.child_id = child;
        this.source_line = line;
    }
}

public class AncestryDiagram : Object {
    public string? title { get; set; default = null; }
    public Gee.ArrayList<AncestryPerson> persons { get; private set; }
    public Gee.ArrayList<AncestryMarriage> marriages { get; private set; }
    public Gee.ArrayList<AncestryChildLink> children { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    public AncestryDiagram() {
        persons = new Gee.ArrayList<AncestryPerson>();
        marriages = new Gee.ArrayList<AncestryMarriage>();
        children = new Gee.ArrayList<AncestryChildLink>();
        errors = new Gee.ArrayList<ParseError>();
    }

    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return persons.size == 0; }

    public AncestryPerson? find_person(string id) {
        foreach (var p in persons) {
            if (p.id == id) return p;
        }
        return null;
    }
}

}
