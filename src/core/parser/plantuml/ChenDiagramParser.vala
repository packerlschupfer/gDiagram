/* ChenDiagramParser.vala — line-based parser for PlantUML @startchen */
namespace GDiagram {

/*
 * PlantUML's Chen syntax:
 *
 *   entity ["Shown" as] CODE [<<weak>>] {           relationship CODE [<<identifying>>] {
 *     ["Shown" as] Attr [: TYPE] [<<key>>|<<derived>>|<<multi>>]
 *     Composite {                                     (attributes of an attribute)
 *       Part
 *     }
 *   }
 *   A -N- B     A =(0,N)= B     (`=` is total participation)
 *   A ->- B     A -<- B     A =>= d { B, C }           (subclasses; d, o or U)
 *
 * The earlier gDiagram forms still parse: `*key`, `/derived`, `{multi}`
 * attributes, `entity weak NAME`, and `A -[N]- B` / `A -- B` links.
 */
public class ChenDiagramParser : Object {
    private ChenDiagram diagram;
    private Regex block_re;
    private Regex attr_re;
    private Regex link_re;
    private Regex simple_sub_re;
    private Regex multi_sub_re;

    public ChenDiagramParser() {
        try {
            block_re = new Regex("""^(entity|relationship)\s+(?:"([^"]+)"\s+as\s+)?([\w.]+)\s*(<<.+>>)?\s*(\{)?\s*(\})?$""",
                RegexCompileFlags.CASELESS);
            attr_re = new Regex("""^(?:"([^"]+)"\s+as\s+)?(.*?)\s*(<<.*>>)?\s*(\{)?$""");
            link_re = new Regex("""^([\w.-]+?)\s*([-=])(\w+|\(\s*\w+\s*,\s*\w+\s*\))([-=])\s*([\w.-]+)$""");
            simple_sub_re = new Regex("""^([\w.-]+?)\s*([-=])([<>])([-=])\s*([\w.-]+)$""");
            multi_sub_re = new Regex("""^([\w.-]+?)\s*([-=])>([-=])\s*([doU])\s*\{(.+)\}$""");
        } catch (RegexError e) {
            error("ChenDiagramParser regex: %s", e.message);
        }
    }

    public ChenDiagram parse(string source) {
        this.diagram = new ChenDiagram();
        parse_chen(source);
        return diagram;
    }

    private void parse_chen(string source) {
        string[] lines = source.split("\n");
        // Main-file line numbers: included text reports its !include line
        int[] line_nos = Preprocessor.source_line_numbers(lines);

        // Attribute list of the innermost open block: the entity or
        // relationship itself, then composite attributes nested inside it.
        var stack = new Gee.ArrayList<Gee.ArrayList<ChenAttribute>>();

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower.has_prefix("@startchen") || lower.has_prefix("@endchen")) continue;
            if (lower.has_prefix("skinparam") || lower.has_prefix("<style>") || lower == "</style>") continue;

            if (trimmed == "}") {
                if (stack.size > 0) stack.remove_at(stack.size - 1);
                continue;
            }

            if (stack.size == 0 && lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            MatchInfo m;
            if (lower.has_prefix("entity ") || lower.has_prefix("relationship ")) {
                string text = trimmed;
                bool legacy_weak = false;
                if (lower.has_prefix("entity weak ")) {
                    legacy_weak = true;
                    text = "entity " + trimmed.substring(12).strip();
                }
                if (block_re.match(text, 0, out m)) {
                    bool is_entity = m.fetch(1).down() == "entity";
                    string? display = empty_null(m.fetch(2));
                    string code = m.fetch(3);
                    string stereo = m.fetch(4) ?? "";
                    bool opens = (m.fetch(5) ?? "") == "{" && (m.fetch(6) ?? "") != "}";
                    if (is_entity) {
                        var entity = new ChenEntity(code, line_nos[i]);
                        entity.display = display;
                        entity.is_weak = legacy_weak || stereo.contains("<<weak>>");
                        diagram.entities.add(entity);
                        if (opens) stack.add(entity.attributes);
                    } else {
                        var rel = new ChenRelationship(code, line_nos[i]);
                        rel.display = display;
                        rel.is_identifying = stereo.contains("<<identifying>>");
                        diagram.relationships.add(rel);
                        if (opens) stack.add(rel.attributes);
                    }
                    continue;
                }
            }

            if (stack.size == 0 && try_parse_association(trimmed, line_nos[i])) {
                continue;
            }

            if (stack.size > 0) {
                bool opens_block;
                var attr = parse_attribute(trimmed, line_nos[i], out opens_block);
                if (attr != null) {
                    stack[stack.size - 1].add(attr);
                    if (opens_block) {
                        stack.add(attr.children);
                    }
                }
                continue;
            }
        }
    }

    private static string? empty_null(string? s) {
        return (s == null || s.length == 0) ? null : s;
    }

    // `opens_block`: the line ends in `{` (a composite attribute)
    private ChenAttribute? parse_attribute(string line, int lineno, out bool opens_block) {
        opens_block = false;
        string text = line.strip();
        if (text.has_suffix(";")) text = text.substring(0, text.length - 1).strip();
        if (text.length == 0) return null;

        bool is_key = false;
        bool is_derived = false;
        bool is_multivalued = false;

        // Earlier gDiagram markers: *key, /derived, {multi}
        if (text.has_prefix("*")) {
            is_key = true;
            text = text.substring(1).strip();
        }
        if (text.has_prefix("/")) {
            is_derived = true;
            text = text.substring(1).strip();
        }
        if (text.has_prefix("{") && text.has_suffix("}")) {
            is_multivalued = true;
            text = text.substring(1, text.length - 2).strip();
        }

        string name = text;
        string? display = null;
        MatchInfo mi;
        if (attr_re.match(text, 0, out mi)) {
            display = empty_null(mi.fetch(1));
            name = mi.fetch(2).strip();
            string stereo = mi.fetch(3) ?? "";
            if (stereo.contains("<<key>>")) is_key = true;
            if (stereo.contains("<<derived>>")) is_derived = true;
            if (stereo.contains("<<multi>>")) is_multivalued = true;
            opens_block = (mi.fetch(4) ?? "") == "{";
        }
        if (name.length == 0) return null;

        var attr = new ChenAttribute(name, lineno);
        attr.display = display;
        attr.is_key = is_key;
        attr.is_derived = is_derived;
        attr.is_multivalued = is_multivalued;
        return attr;
    }

    private bool try_parse_association(string line, int lineno) {
        string trimmed = line.strip();
        if (trimmed.has_suffix(";")) trimmed = trimmed.substring(0, trimmed.length - 1).strip();
        MatchInfo m;

        if (multi_sub_re.match(trimmed, 0, out m)) {
            var sub = new ChenSubclass(m.fetch(1), lineno);
            sub.total = m.fetch(2) == "=";
            sub.symbol = m.fetch(4);
            foreach (string part in m.fetch(5).split(",")) {
                if (part.strip().length > 0) sub.subclasses.add(part.strip());
            }
            diagram.subclasses.add(sub);
            return true;
        }
        if (simple_sub_re.match(trimmed, 0, out m)) {
            var sub = new ChenSubclass(m.fetch(1), lineno);
            sub.total = m.fetch(2) == "=";
            sub.downwards = m.fetch(3) == ">";
            sub.subclasses.add(m.fetch(5));
            diagram.subclasses.add(sub);
            return true;
        }
        if (link_re.match(trimmed, 0, out m)) {
            var link = new ChenLink(m.fetch(1), m.fetch(5), m.fetch(3).replace(" ", ""), lineno);
            link.total = m.fetch(2) == "=";
            diagram.links.add(link);
            return true;
        }

        // Earlier gDiagram forms: A -[card]- B, A -[card]-> B, A -- B
        int bracket_open = trimmed.index_of("-[");
        if (bracket_open >= 0) {
            int bracket_close = trimmed.index_of("]-", bracket_open);
            int bracket_close_arrow = trimmed.index_of("]->", bracket_open);
            if (bracket_close >= 0 || bracket_close_arrow >= 0) {
                string from_name = trimmed.substring(0, bracket_open).strip();
                string card;
                string to_name;
                if (bracket_close_arrow >= 0) {
                    card = trimmed.substring(bracket_open + 2, bracket_close_arrow - bracket_open - 2);
                    to_name = trimmed.substring(bracket_close_arrow + 3).strip();
                } else {
                    card = trimmed.substring(bracket_open + 2, bracket_close - bracket_open - 2);
                    to_name = trimmed.substring(bracket_close + 2).strip();
                }
                if (from_name.length > 0 && to_name.length > 0) {
                    diagram.links.add(new ChenLink(from_name, to_name, card, lineno));
                    return true;
                }
            }
        }

        int dash_pos = trimmed.index_of(" -- ");
        if (dash_pos >= 0) {
            string from_name = trimmed.substring(0, dash_pos).strip();
            string to_name = trimmed.substring(dash_pos + 4).strip();
            if (from_name.length > 0 && to_name.length > 0) {
                diagram.links.add(new ChenLink(from_name, to_name, "", lineno));
                return true;
            }
        }

        return false;
    }
}

}
