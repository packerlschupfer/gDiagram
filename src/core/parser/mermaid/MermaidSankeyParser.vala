namespace GDiagram {

public class MermaidSankeyParser : Object {

    public MermaidSankeyParser() {}

    public MermaidSankey parse(string source) {
        var diagram = new MermaidSankey();
        int line_num = 0;

        foreach (var raw in source.split("\n")) {
            line_num++;
            string line = raw.strip();
            if (line.length == 0 || line.has_prefix("%%")) continue;

            string low = line.down();
            if (low.has_prefix("sankey")) continue;
            if (low.has_prefix("title ")) { diagram.title = line.substring(6).strip(); continue; }

            // Parse CSV line: source,target,value
            // Handle single-quoted fields containing commas
            string[] parts = parse_csv(line);
            if (parts.length >= 3) {
                string src = parts[0].strip().replace("'", "");
                string tgt = parts[1].strip().replace("'", "");
                string val_str = parts[2].strip();
                double val = 0.0;
                if (val_str.length > 0) val = double.parse(val_str);
                if (src.length > 0 && tgt.length > 0) {
                    diagram.add_link(new SankeyLink(src, tgt, val, line_num));
                }
            }
        }

        return diagram;
    }

    // Simple CSV parser that respects single-quoted fields
    private string[] parse_csv(string line) {
        var parts = new Gee.ArrayList<string>();
        var current = new StringBuilder();
        bool in_quote = false;

        for (int i = 0; i < line.length; i++) {
            char c = line[i];
            if (c == '\'' && !in_quote) { in_quote = true; continue; }
            if (c == '\'' && in_quote) { in_quote = false; continue; }
            if (c == ',' && !in_quote) {
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
