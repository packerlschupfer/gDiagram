/* AncestryDiagramParser.vala — line-based parser for @startancestry / @endancestry */
namespace GDiagram {

public class AncestryDiagramParser : Object {

    public AncestryDiagram parse(string source) {
        var diagram = new AncestryDiagram();
        var lines = source.split("\n");

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i].strip();
            int line_num = i + 1;

            // Skip empty lines, comments, delimiters
            if (line.length == 0) continue;
            if (line.has_prefix("'") || line.has_prefix("//")) continue;
            if (line.down().has_prefix("@startancestry")) continue;
            if (line.down().has_prefix("@endancestry")) continue;

            string lower = line.down();

            if (lower.has_prefix("title ")) {
                diagram.title = line.substring(6).strip();
            } else if (lower.has_prefix("person ")) {
                parse_person(diagram, line.substring(7).strip(), line_num);
            } else if (lower.has_prefix("married ")) {
                parse_marriage(diagram, line.substring(8).strip(), line_num);
            } else if (lower.has_prefix("child ")) {
                parse_child(diagram, line.substring(6).strip(), line_num);
            }
            // Silently ignore unrecognized lines (skinparam, notes, etc.)
        }

        return diagram;
    }

    private void parse_person(AncestryDiagram diagram, string rest, int line_num) {
        // Format: ID [Display Name] born YYYY died YYYY #male/#female
        // All parts after ID are optional

        string remaining = rest;

        // Extract ID (first word)
        int space_idx = remaining.index_of(" ");
        string id;
        if (space_idx < 0) {
            id = remaining;
            remaining = "";
        } else {
            id = remaining.substring(0, space_idx);
            remaining = remaining.substring(space_idx + 1).strip();
        }

        if (id.length == 0) {
            diagram.errors.add(new ParseError("Missing person ID", line_num, 0));
            return;
        }

        // Extract display name from [...]
        string display_name = id;
        int bracket_start = remaining.index_of("[");
        int bracket_end = remaining.index_of("]");
        if (bracket_start >= 0 && bracket_end > bracket_start) {
            display_name = remaining.substring(bracket_start + 1, bracket_end - bracket_start - 1).strip();
            // Convert literal \n escape to actual newline for multi-line labels
            display_name = display_name.replace("\\n", "\n");
            remaining = remaining.substring(0, bracket_start) + remaining.substring(bracket_end + 1);
            remaining = remaining.strip();
        }

        var person = new AncestryPerson(id, display_name, line_num);

        // Parse remaining tokens for dates and gender.
        // Dates can be: "born 1920", "born 1920-03-15", "born 15.03.1920"
        // Captures everything after born/died until the next keyword or #.
        string lower_rem = remaining.down();
        try {
            var born_re = new Regex("""born\s+([\d][\d./:-]+[\d])""");
            MatchInfo mi;
            if (born_re.match(lower_rem, 0, out mi)) {
                person.birth_date = mi.fetch(1);
            }
        } catch (RegexError e) { /* ignore */ }

        try {
            var died_re = new Regex("""died\s+([\d][\d./:-]+[\d])""");
            MatchInfo mi;
            if (died_re.match(lower_rem, 0, out mi)) {
                person.death_date = mi.fetch(1);
            }
        } catch (RegexError e) { /* ignore */ }

        // Gender
        if (lower_rem.contains("#male")) {
            person.gender = AncestryGender.MALE;
        } else if (lower_rem.contains("#female")) {
            person.gender = AncestryGender.FEMALE;
        } else if (lower_rem.contains("#unknown")) {
            person.gender = AncestryGender.UNKNOWN;
        }

        diagram.persons.add(person);
    }

    private void parse_marriage(AncestryDiagram diagram, string rest, int line_num) {
        // Format: ID1 -- ID2 : YEAR
        string[] parts = rest.split("--");
        if (parts.length < 2) {
            diagram.errors.add(new ParseError("Invalid marriage syntax, expected 'ID1 -- ID2'", line_num, 0));
            return;
        }

        string p1 = parts[0].strip();
        string p2_and_year = parts[1].strip();

        // Split on ':' for optional year
        string p2;
        string? year = null;
        int colon_idx = p2_and_year.index_of(":");
        if (colon_idx >= 0) {
            p2 = p2_and_year.substring(0, colon_idx).strip();
            year = p2_and_year.substring(colon_idx + 1).strip();
        } else {
            p2 = p2_and_year;
        }

        if (p1.length == 0 || p2.length == 0) {
            diagram.errors.add(new ParseError("Missing person ID in marriage", line_num, 0));
            return;
        }

        var marriage = new AncestryMarriage(p1, p2, line_num);
        marriage.year = year;
        diagram.marriages.add(marriage);
    }

    private void parse_child(AncestryDiagram diagram, string rest, int line_num) {
        // Format: PARENT_ID -- CHILD_ID
        string[] parts = rest.split("--");
        if (parts.length < 2) {
            diagram.errors.add(new ParseError("Invalid child syntax, expected 'PARENT_ID -- CHILD_ID'", line_num, 0));
            return;
        }

        string parent = parts[0].strip();
        string child = parts[1].strip();

        if (parent.length == 0 || child.length == 0) {
            diagram.errors.add(new ParseError("Missing ID in child link", line_num, 0));
            return;
        }

        diagram.children.add(new AncestryChildLink(parent, child, line_num));
    }
}

}
