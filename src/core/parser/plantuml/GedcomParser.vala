/* GedcomParser.vala — parser for GEDCOM (.ged) genealogy files.
 *
 * Converts GEDCOM 5.5.1 level-based text into an AncestryDiagram AST,
 * reusing the existing AncestryDiagramRenderer for visualisation.
 *
 * Each GEDCOM line: LEVEL [XREF] TAG [VALUE]
 */
namespace GDiagram {

public class GedcomParser : Object {

    public AncestryDiagram parse(string source) {
        var diagram = new AncestryDiagram();

        // Normalise line endings: GEDCOM often uses \r\n
        string normalised = source.replace("\r\n", "\n").replace("\r", "\n");
        var lines = normalised.split("\n");

        // First pass: collect all INDI and FAM records
        var individuals = new Gee.HashMap<string, GedcomIndi>();
        var families = new Gee.HashMap<string, GedcomFam>();

        int i = 0;
        while (i < lines.length) {
            string line = lines[i].strip();
            if (line.length == 0) { i++; continue; }

            int level = parse_level(line);
            if (level != 0) { i++; continue; }

            string? xref = parse_xref(line);
            string tag = parse_tag(line);

            if (tag == "INDI" && xref != null) {
                var indi = new GedcomIndi();
                indi.xref = xref;
                i = parse_indi(lines, i + 1, indi);
                individuals.set(xref, indi);
            } else if (tag == "FAM" && xref != null) {
                var fam = new GedcomFam();
                fam.xref = xref;
                i = parse_fam(lines, i + 1, fam);
                families.set(xref, fam);
            } else {
                i++;
            }
        }

        // Second pass: convert to AncestryDiagram AST
        int line_num = 1;
        foreach (var entry in individuals.entries) {
            var indi = entry.value;
            string id = clean_xref(entry.key);
            string name = format_gedcom_name(indi.name);

            var person = new AncestryPerson(id, name, line_num++);
            person.birth_date = indi.birth_date;
            person.death_date = indi.death_date;

            if (indi.sex == "M") {
                person.gender = AncestryGender.MALE;
            } else if (indi.sex == "F") {
                person.gender = AncestryGender.FEMALE;
            }

            diagram.persons.add(person);
        }

        // Create marriages and child links from FAM records
        foreach (var entry in families.entries) {
            var fam = entry.value;

            string? husb_id = fam.husb_xref != null ? clean_xref(fam.husb_xref) : null;
            string? wife_id = fam.wife_xref != null ? clean_xref(fam.wife_xref) : null;

            if (husb_id != null && wife_id != null) {
                var marriage = new AncestryMarriage(husb_id, wife_id, line_num++);
                marriage.year = fam.marr_date;
                diagram.marriages.add(marriage);
            }

            // Child links — link each child to both parents
            foreach (string child_xref in fam.children) {
                string child_id = clean_xref(child_xref);
                if (husb_id != null) {
                    diagram.children.add(new AncestryChildLink(husb_id, child_id, line_num++));
                }
                if (wife_id != null) {
                    diagram.children.add(new AncestryChildLink(wife_id, child_id, line_num++));
                }
            }
        }

        return diagram;
    }

    /* ---- Level-0 record parsers ---- */

    /** Parse an INDI record's sub-lines. Returns the index of the next level-0 line. */
    private int parse_indi(string[] lines, int start, GedcomIndi indi) {
        int i = start;
        while (i < lines.length) {
            string line = lines[i].strip();
            if (line.length == 0) { i++; continue; }

            int level = parse_level(line);
            if (level == 0) break;  // next top-level record

            string tag = parse_tag(line);
            string? val = parse_value(line);

            if (level == 1) {
                switch (tag) {
                case "NAME":
                    if (val != null) indi.name = val;
                    break;
                case "SEX":
                    if (val != null) indi.sex = val.strip();
                    break;
                case "BIRT": {
                    string? bdate;
                    string? bplace;
                    i = parse_event_date(lines, i + 1, out bdate, out bplace);
                    indi.birth_date = bdate;
                    indi.birth_place = bplace;
                    continue;
                }
                case "DEAT": {
                    string? ddate;
                    string? dplace;
                    i = parse_event_date(lines, i + 1, out ddate, out dplace);
                    indi.death_date = ddate;
                    indi.death_place = dplace;
                    continue;
                }
                default:
                    break;
                }
            }
            i++;
        }
        return i;
    }

    /** Parse a FAM record's sub-lines. Returns the index of the next level-0 line. */
    private int parse_fam(string[] lines, int start, GedcomFam fam) {
        int i = start;
        while (i < lines.length) {
            string line = lines[i].strip();
            if (line.length == 0) { i++; continue; }

            int level = parse_level(line);
            if (level == 0) break;

            string tag = parse_tag(line);
            string? val = parse_value(line);

            if (level == 1) {
                switch (tag) {
                case "HUSB":
                    if (val != null) fam.husb_xref = val.strip();
                    break;
                case "WIFE":
                    if (val != null) fam.wife_xref = val.strip();
                    break;
                case "CHIL":
                    if (val != null) fam.children.add(val.strip());
                    break;
                case "MARR": {
                    string? date;
                    string? place;
                    i = parse_event_date(lines, i + 1, out date, out place);
                    fam.marr_date = date;
                    continue;
                }
                default:
                    break;
                }
            }
            i++;
        }
        return i;
    }

    /** Scan sub-lines of an event (BIRT, DEAT, MARR) for DATE and PLAC.
     *  Returns index of the first line that is not a sub-record of this event. */
    private int parse_event_date(string[] lines, int start, out string? date, out string? place) {
        date = null;
        place = null;
        int i = start;
        while (i < lines.length) {
            string line = lines[i].strip();
            if (line.length == 0) { i++; continue; }

            int level = parse_level(line);
            if (level <= 1) break;  // back to parent or sibling

            string tag = parse_tag(line);
            string? val = parse_value(line);

            if (tag == "DATE" && val != null) {
                date = normalise_gedcom_date(val.strip());
            } else if (tag == "PLAC" && val != null) {
                place = val.strip();
            }
            i++;
        }
        return i;
    }

    /* ---- Low-level line helpers ---- */

    /** Extract the integer level (first token) from a GEDCOM line. */
    private int parse_level(string line) {
        int space = line.index_of(" ");
        string num_str = (space >= 0) ? line.substring(0, space) : line;
        return int.parse(num_str);
    }

    /** Extract the @XREF@ if present on a level-0 line. */
    private string? parse_xref(string line) {
        // Format: "0 @I1@ INDI" — xref is the second token if it starts with @
        string[] parts = line.split(" ");
        if (parts.length >= 2 && parts[1].has_prefix("@") && parts[1].has_suffix("@")) {
            return parts[1];
        }
        return null;
    }

    /** Extract the tag from a GEDCOM line.
     *  Level-0 with xref: "0 @I1@ INDI" → "INDI"
     *  Level-0 without:   "0 HEAD"       → "HEAD"
     *  Sub-level:         "1 NAME John"  → "NAME" */
    private string parse_tag(string line) {
        string[] parts = line.split(" ");
        if (parts.length < 2) return "";
        // If second token is an xref, tag is the third
        if (parts[1].has_prefix("@") && parts[1].has_suffix("@")) {
            return (parts.length >= 3) ? parts[2] : "";
        }
        return parts[1];
    }

    /** Extract the value after the tag (everything past the tag token). */
    private string? parse_value(string line) {
        string[] parts = line.split(" ");
        if (parts.length < 2) return null;

        int tag_index;
        if (parts[1].has_prefix("@") && parts[1].has_suffix("@")) {
            tag_index = 2;
        } else {
            tag_index = 1;
        }

        // Value is everything after the tag token
        if (parts.length <= tag_index + 1) return null;

        // Rejoin from tag_index+1 onward
        var sb = new StringBuilder();
        for (int j = tag_index + 1; j < parts.length; j++) {
            if (j > tag_index + 1) sb.append(" ");
            sb.append(parts[j]);
        }
        string result = sb.str.strip();
        return (result.length > 0) ? result : null;
    }

    /* ---- Name / date formatting ---- */

    /** Convert GEDCOM name "George /Smith/" to "George Smith". */
    private string format_gedcom_name(string? name) {
        if (name == null || name.length == 0) return "Unknown";
        // Strip slashes that surround the surname
        return name.replace("/", "").strip();
    }

    /** Strip @ characters from an xref: "@I1@" → "I1". */
    private string clean_xref(string xref) {
        string s = xref;
        if (s.has_prefix("@")) s = s.substring(1);
        if (s.has_suffix("@")) s = s.substring(0, s.length - 1);
        return s;
    }

    /** Normalise a GEDCOM date string.
     *  Strips known prefixes: ABT, BEF, AFT, CAL, EST.
     *  For "BET X AND Y", takes X only. */
    private string normalise_gedcom_date(string raw) {
        string d = raw.strip();
        string upper = d.up();

        // Handle BET ... AND ... — take first date
        if (upper.has_prefix("BET ")) {
            int and_pos = upper.index_of(" AND ");
            if (and_pos > 0) {
                d = d.substring(4, and_pos - 4).strip();
            } else {
                d = d.substring(4).strip();
            }
            return d;
        }

        // Strip simple prefixes
        string[] prefixes = { "ABT ", "AFT ", "BEF ", "CAL ", "EST ", "FROM ", "TO ", "INT " };
        foreach (string pfx in prefixes) {
            if (upper.has_prefix(pfx)) {
                d = d.substring(pfx.length).strip();
                break;
            }
        }

        return d;
    }
}

/* ---- Internal data structures for GEDCOM parsing ---- */

private class GedcomIndi : Object {
    public string xref { get; set; default = ""; }
    public string? name { get; set; default = null; }
    public string? sex { get; set; default = null; }
    public string? birth_date { get; set; default = null; }
    public string? death_date { get; set; default = null; }
    public string? birth_place { get; set; default = null; }
    public string? death_place { get; set; default = null; }
}

private class GedcomFam : Object {
    public string xref { get; set; default = ""; }
    public string? husb_xref { get; set; default = null; }
    public string? wife_xref { get; set; default = null; }
    public string? marr_date { get; set; default = null; }
    public Gee.ArrayList<string> children { get; set; }

    construct {
        children = new Gee.ArrayList<string>();
    }
}

}
