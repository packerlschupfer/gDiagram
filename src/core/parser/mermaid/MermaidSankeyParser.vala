namespace GDiagram {

public class MermaidSankeyParser : Object {

    public MermaidSankeyParser() {}

    public MermaidSankey parse(string source) {
        var diagram = new MermaidSankey();
        int line_num = 0;
        bool in_front_matter = false;
        bool seen_content = false;

        foreach (var raw in source.split("\n")) {
            line_num++;
            string line = raw.strip();

            // YAML front matter: `title:` and `config: sankey: showValues:`
            if (line == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) {
                if (line.has_prefix("title:")) {
                    diagram.title = unquote_yaml(line.substring(6).strip());
                } else if (line.has_prefix("showValues:")) {
                    diagram.show_values = line.substring(11).strip().down() != "false";
                }
                continue;
            }

            if (line.length == 0 || line.has_prefix("%%")) continue;

            string low = line.down();
            // The `sankey-beta` keyword is the diagram's first statement and
            // nothing else. Skipping every line that merely *starts with*
            // "sankey" swallowed data rows such as `Sankey Ltd,Revenue,100`,
            // which Mermaid reads as an ordinary CSV record.
            if (!seen_content && (low == "sankey-beta" || low == "sankey")) {
                seen_content = true;
                continue;
            }
            seen_content = true;

            // Not Mermaid syntax (sankey-beta has no title statement), but
            // older gDiagram examples used it.
            if (low.has_prefix("title ")) { diagram.title = line.substring(6).strip(); continue; }

            // CSV line: source,target,value (RFC 4180 quoting)
            string[] parts = parse_csv(line);
            string src = parts.length > 0 ? parts[0].strip() : "";
            string tgt = parts.length > 1 ? parts[1].strip() : "";
            string val_str = parts.length > 2 ? parts[2].strip() : "";
            if (parts.length < 3 || src.length == 0 || tgt.length == 0 || val_str.length == 0) {
                // Mermaid's grammar is `field COMMA field COMMA field`: a short
                // or empty record is a parse error, not something to drop.
                diagram.errors.add(new ParseError(
                    "Expected a `source,target,value` record", line_num, 1));
                continue;
            }
            diagram.add_link(new SankeyLink(src, tgt, double.parse(val_str), line_num));
        }

        return diagram;
    }

    private static string unquote_yaml(string s) {
        if (s.length >= 2 && ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                              (s.has_prefix("'") && s.has_suffix("'")))) {
            return s.substring(1, s.length - 2);
        }
        return s;
    }

    // CSV as Mermaid reads it (RFC 4180): a field may be wrapped in double
    // quotes to hold commas, and "" inside it is a literal quote. Single
    // quotes are ordinary characters.
    internal static string[] parse_csv(string line) {
        var parts = new Gee.ArrayList<string>();
        var current = new StringBuilder();
        bool in_quote = false;

        for (int i = 0; i < line.length; i++) {
            char c = line[i];
            if (in_quote) {
                if (c == '"') {
                    if (i + 1 < line.length && line[i + 1] == '"') {
                        current.append_c('"');
                        i++;
                    } else {
                        in_quote = false;
                    }
                } else {
                    current.append_c(c);
                }
                continue;
            }
            if (c == '"' && current.str.strip().length == 0) {
                current.truncate(0);
                in_quote = true;
                continue;
            }
            if (c == ',') {
                parts.add(current.str);
                current = new StringBuilder();
                continue;
            }
            current.append_c(c);
        }
        parts.add(current.str);

        return parts.to_array();
    }
}

}
