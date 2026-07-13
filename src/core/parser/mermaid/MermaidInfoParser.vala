/* MermaidInfoParser.vala — Mermaid `info` diagram parser
 *
 * Ports the `Info` rule of mermaid 12.2.0's langium grammar:
 *
 *     NEWLINE* 'info' NEWLINE* ('showInfo' NEWLINE*)? TitleAndAccessibilities?
 *
 * The `info`/`showInfo` keywords carry mermaid's token-builder restriction
 * `(?:(?=%%)|(?!\S))` — no non-whitespace may follow them on the same line,
 * so `information` is not an info diagram.
 */
namespace GDiagram {

public class MermaidInfoParser : Object {
    private MermaidInfo diagram;

    public MermaidInfoParser() {}

    public MermaidInfo parse(string source) {
        this.diagram = new MermaidInfo();

        string[] lines = source.split("\n");
        bool in_front_matter = false;
        bool seen_content = false;
        bool in_acc_descr_block = false;
        var descr = new StringBuilder();

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();

            if (in_acc_descr_block) {
                int close = trimmed.index_of("}");
                if (close >= 0) {
                    if (close > 0) descr.append(trimmed.substring(0, close));
                    diagram.acc_descr = descr.str.strip();
                    in_acc_descr_block = false;
                } else {
                    if (descr.len > 0) descr.append_c('\n');
                    descr.append(trimmed);
                }
                continue;
            }

            // YAML front matter is a hidden terminal in every mermaid grammar.
            if (trimmed == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) {
                if (trimmed.has_prefix("title:") && diagram.title == null) {
                    diagram.title = strip_quotes(trimmed.substring(6).strip());
                }
                continue;
            }
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;
            seen_content = true;

            // Strip a trailing `%%` comment, as SINGLE_LINE_COMMENT does.
            int comment = trimmed.index_of("%%");
            if (comment >= 0) trimmed = trimmed.substring(0, comment).strip();
            if (trimmed.length == 0) continue;

            string lower = trimmed.down();

            if (lower == "info") {
                diagram.declared = true;
                if (diagram.source_line == 0) diagram.source_line = i + 1;
                continue;
            }
            if (lower == "showinfo") {
                diagram.show_info = true;
                continue;
            }
            if (lower.has_prefix("title") && (trimmed.length == 5 || trimmed[5] == ' ' || trimmed[5] == '\t')) {
                if (trimmed.length > 5) { diagram.title = trimmed.substring(5).strip(); } else { diagram.title = ""; }
                continue;
            }
            if (lower.has_prefix("acctitle")) {
                int colon = trimmed.index_of(":");
                if (colon >= 0) diagram.acc_title = trimmed.substring(colon + 1).strip();
                continue;
            }
            if (lower.has_prefix("accdescr")) {
                int brace = trimmed.index_of("{");
                if (brace >= 0) {
                    descr.truncate(0);
                    string rest = trimmed.substring(brace + 1);
                    int close = rest.index_of("}");
                    if (close >= 0) {
                        diagram.acc_descr = rest.substring(0, close).strip();
                    } else {
                        descr.append(rest.strip());
                        in_acc_descr_block = true;
                    }
                    continue;
                }
                int colon = trimmed.index_of(":");
                if (colon >= 0) diagram.acc_descr = trimmed.substring(colon + 1).strip();
                continue;
            }

            diagram.errors.add(new ParseError(
                "info diagram accepts only `info`, `showInfo`, `title` and accessibility lines",
                i + 1, 1));
        }

        if (!diagram.declared) {
            diagram.errors.add(new ParseError("missing `info` keyword", 1, 1));
        }
        return diagram;
    }

    private static string strip_quotes(string s) {
        if (s.length >= 2 && s.has_prefix("\"") && s.has_suffix("\"")) {
            return s.substring(1, s.length - 2);
        }
        if (s.length >= 2 && s.has_prefix("'") && s.has_suffix("'")) {
            return s.substring(1, s.length - 2);
        }
        return s;
    }
}

}
