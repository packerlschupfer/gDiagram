namespace GDiagram {

public class MermaidRequirementParser : Object {

    // Compiled once: parse() ran this on every source line
    private static Regex? rel_re = null;

    private static void init_regex() {
        if (rel_re != null) return;
        try {
            rel_re = new Regex(
                "^(\"[^\"]*\"|[^\\s\"]+?)\\s*(<-|-)\\s*(\\w+)\\s*(->|-)\\s*(\"[^\"]*\"|[^\\s\"]+)$");
        } catch (RegexError e) {
            warning("MermaidRequirementParser regex: %s", e.message);
        }
    }

    public MermaidRequirementParser() {}

    public MermaidRequirement parse(string source) {
        init_regex();
        var diagram = new MermaidRequirement();

        // Front matter and multi-line "%%{init}%%" directives are handled here, as in the
        // class / ER / state parsers: a directive body used to leak in as statements.
        string? fm_title;
        bool header_ok;
        var lines = MermaidSourceLine.split(source, { "requirementDiagram" }, out fm_title, out header_ok);
        if (fm_title != null) diagram.title = fm_title;

        var pending_styles = new Gee.ArrayList<string>();
        int i = 0;
        while (i < lines.size) {
            string line = lines[i].text;
            int line_num = lines[i].line;
            i++;

            // Title directive
            if (line.down().has_prefix("title ")) {
                diagram.title = line.substring(6).strip();
                continue;
            }

            // direction TB|BT|LR|RL (Mermaid 11.17 honours it in requirement diagrams)
            if (MermaidSourceLine.starts_with_word(line, "direction")) {
                FlowchartDirection dir;
                if (MermaidSourceLine.parse_direction(line.substring(9), out dir)) diagram.direction = dir;
                continue;
            }

            // classDef name fill:#f00,stroke:#333
            if (MermaidSourceLine.starts_with_word(line, "classDef")) {
                string rest = line.substring(8).strip();
                int sp = MermaidSourceLine.first_space(rest);
                if (sp > 0) {
                    string spec = rest.substring(sp).strip().replace(" ", "");
                    foreach (string name in rest.substring(0, sp).split(",")) {
                        if (name.strip().length > 0) diagram.class_defs.set(name.strip(), spec);
                    }
                }
                continue;
            }

            // class a,b name / style a fill:#f00 — applied once the whole diagram is read,
            // so they work whether written before or after the elements they name
            if (MermaidSourceLine.starts_with_word(line, "class") ||
                MermaidSourceLine.starts_with_word(line, "style")) {
                pending_styles.add(line);
                continue;
            }

            // Element/requirement block: "type name {". The name may be quoted
            // ("requirement \"Login Req\" {"): splitting on spaces kept only `Req"`.
            if (line.has_suffix("{")) {
                string header = line.substring(0, line.length - 1).strip();
                int sp = header.index_of_char(' ');
                if (sp > 0) {
                    string parsed_type = header.substring(0, sp);
                    string elem_name = unquote(header.substring(sp + 1));
                    var elem = new ReqElement(elem_name, parsed_type, line_num);

                    // Parse block contents until "}"
                    while (i < lines.size) {
                        string inner = lines[i].text;
                        i++;
                        if (inner == "}") break;

                        int colon = inner.index_of(":");
                        if (colon >= 0) {
                            string key = inner.substring(0, colon).strip().down();
                            // Quoted values ("text: \"a: b\"") lose their quotes
                            string val = unquote(inner.substring(colon + 1));
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

            // Relationship: "source - type -> target", or the reversed form
            // "target <- type - source"; either name may be quoted
            var rel = parse_relationship(line, line_num);
            if (rel != null) {
                diagram.add_relationship(rel);
            }
        }

        foreach (string line in pending_styles) {
            apply_style_statement(diagram, line);
        }
        return diagram;
    }

    // "class a,b name" assigns classDefs; "style a fill:#f00" sets an inline spec
    private static void apply_style_statement(MermaidRequirement diagram, string line) {
        bool is_class = MermaidSourceLine.starts_with_word(line, "class");
        string rest = line.substring(5).strip();
        int sp = is_class ? rest.last_index_of(" ") : MermaidSourceLine.first_space(rest);
        if (sp <= 0) return;
        string value = is_class ? rest.substring(sp + 1).strip()
                                : rest.substring(sp).strip().replace(" ", "");
        if (value.length == 0) return;
        foreach (string id in rest.substring(0, sp).split(",")) {
            var elem = diagram_find(diagram, id.strip());
            if (elem == null) continue;
            if (is_class) elem.css_classes.add(value);
            else elem.inline_style = value;
        }
    }

    private static ReqElement? diagram_find(MermaidRequirement diagram, string name) {
        foreach (var e in diagram.elements) {
            if (e.name == name) return e;
        }
        return null;
    }

    private ReqRelationship? parse_relationship(string line, int line_num) {
        MatchInfo m = null;
        if (rel_re == null || !rel_re.match(line, 0, out m)) return null;
        string left = unquote(m.fetch(1));
        string open = m.fetch(2);
        string rel_type = m.fetch(3);
        string close = m.fetch(4);
        string right = unquote(m.fetch(5));
        if (open == "-" && close == "->") {
            return new ReqRelationship(left, rel_type, right, line_num);
        }
        if (open == "<-" && close == "-") {
            // "a <- satisfies - b": b satisfies a
            return new ReqRelationship(right, rel_type, left, line_num);
        }
        return null;
    }

    private static string unquote(string s) {
        string t = s.strip();
        if (t.length >= 2 && t.has_prefix("\"") && t.has_suffix("\"")) {
            return t.substring(1, t.length - 2);
        }
        return t;
    }
}

}
