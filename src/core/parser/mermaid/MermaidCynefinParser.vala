/* MermaidCynefinParser.vala — Mermaid `cynefin-beta` diagram parser
 *
 * Ports the `CynefinGrammar` rules of mermaid 12.2.0 (see MermaidCynefin.vala
 * for the grammar itself). The grammar is line-insensitive — NEWLINE is an
 * ordinary optional separator — but every construct is anchored on a
 * DOMAIN_NAME or a STRING, so a line-based scan reproduces it exactly as long
 * as items may also sit on the domain's own line.
 *
 * Mermaid's DB drops a self-loop transition (`complex --> complex`) with a
 * warning; we record it as a parse error instead so the user sees it.
 */
namespace GDiagram {

public class MermaidCynefinParser : Object {
    private MermaidCynefin diagram;

    public MermaidCynefinParser() {}

    public MermaidCynefin parse(string source) {
        this.diagram = new MermaidCynefin();

        string[] lines = source.split("\n");
        bool in_front_matter = false;
        bool seen_content = false;
        bool in_acc_descr_block = false;
        var descr = new StringBuilder();
        CynefinDomain? current = null;

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            int lineno = i + 1;

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

            trimmed = strip_trailing_comment(trimmed);
            if (trimmed.length == 0) continue;

            string lower = trimmed.down();

            // Header: `cynefin-beta` or `cynefin-beta:` (both are keywords).
            if (lower == "cynefin-beta" || lower == "cynefin-beta:") {
                diagram.declared = true;
                continue;
            }

            if (lower.has_prefix("title") &&
                (trimmed.length == 5 || trimmed[5] == ' ' || trimmed[5] == '\t')) {
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

            // Transition: DOMAIN_NAME '-->' DOMAIN_NAME (':' STRING)?
            if (trimmed.contains("-->")) {
                if (parse_transition(trimmed, lineno)) continue;
                // parse_transition recorded the error
                continue;
            }

            // A quoted string continues the open domain block.
            if (trimmed.has_prefix("\"") || trimmed.has_prefix("'")) {
                if (current == null) {
                    diagram.errors.add(new ParseError(
                        "item %s has no domain — put it under complex/complicated/clear/chaotic/confusion"
                            .printf(trimmed), lineno, 1));
                    continue;
                }
                add_items(current, trimmed, lineno);
                continue;
            }

            // DomainBlock: a domain name, optionally followed by items on the same line.
            string head = first_word(trimmed);
            CynefinDomainName name;
            if (CynefinDomainName.try_parse(head.down(), out name)) {
                var existing = diagram.find_domain(name);
                if (existing != null) {
                    current = existing;
                } else {
                    current = new CynefinDomain(name, lineno);
                    diagram.domains.add(current);
                }
                string rest = trimmed.substring(head.length).strip();
                if (rest.length > 0) add_items(current, rest, lineno);
                continue;
            }

            diagram.errors.add(new ParseError(
                "unexpected `%s` — expected a domain name, a quoted item or a `-->` transition"
                    .printf(head), lineno, 1));
        }

        if (!diagram.declared) {
            diagram.errors.add(new ParseError("missing `cynefin-beta` keyword", 1, 1));
        }
        return diagram;
    }

    /** `from --> to` with an optional `: "label"`. Returns false after recording an error. */
    private bool parse_transition(string line, int lineno) {
        int arrow = line.index_of("-->");
        string from_part = line.substring(0, arrow).strip();
        string rest = line.substring(arrow + 3).strip();

        string? label = null;
        int colon = rest.index_of(":");
        if (colon >= 0) {
            string tail = rest.substring(colon + 1).strip();
            rest = rest.substring(0, colon).strip();
            if (tail.length > 0) {
                if (!is_quoted(tail)) {
                    diagram.errors.add(new ParseError(
                        "transition label must be quoted: `: \"%s\"`".printf(tail), lineno, 1));
                    return false;
                }
                label = strip_quotes(tail);
            }
        }

        CynefinDomainName from_name, to_name;
        if (!CynefinDomainName.try_parse(from_part.down(), out from_name)) {
            diagram.errors.add(new ParseError(
                "unknown domain `%s` on the left of `-->`".printf(from_part), lineno, 1));
            return false;
        }
        if (!CynefinDomainName.try_parse(rest.down(), out to_name)) {
            diagram.errors.add(new ParseError(
                "unknown domain `%s` on the right of `-->`".printf(rest), lineno, 1));
            return false;
        }
        if (from_name == to_name) {
            diagram.errors.add(new ParseError(
                "self-loop transition on `%s` is not meaningful".printf(from_name.id()), lineno, 1));
            return false;
        }
        diagram.transitions.add(new CynefinTransition(from_name, to_name, label, lineno));
        return true;
    }

    /** Appends every quoted string found in `spec` to `domain`. */
    private void add_items(CynefinDomain domain, string spec, int lineno) {
        int i = 0;
        bool any = false;
        while (i < spec.length) {
            char c = spec[i];
            if (c == ' ' || c == '\t' || c == ',') { i++; continue; }
            if (c != '"' && c != '\'') {
                diagram.errors.add(new ParseError(
                    "domain items must be quoted strings, found `%s`".printf(spec.substring(i).strip()),
                    lineno, i + 1));
                return;
            }
            int end = i + 1;
            var text = new StringBuilder();
            while (end < spec.length && spec[end] != c) {
                if (spec[end] == '\\' && end + 1 < spec.length) {
                    end++;
                    text.append_c(spec[end]);
                } else {
                    text.append_c(spec[end]);
                }
                end++;
            }
            if (end >= spec.length) {
                diagram.errors.add(new ParseError("unterminated string", lineno, i + 1));
                return;
            }
            domain.items.add(new CynefinItem(text.str, lineno));
            any = true;
            i = end + 1;
        }
        if (!any) {
            diagram.errors.add(new ParseError("expected a quoted item", lineno, 1));
        }
    }

    private static string first_word(string s) {
        int end = 0;
        while (end < s.length && !s[end].isspace() && s[end] != '"' && s[end] != '\'') end++;
        return s.substring(0, end);
    }

    // A `%%` outside a quoted string starts a comment.
    private static string strip_trailing_comment(string s) {
        bool in_quote = false;
        char quote = '"';
        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (in_quote) {
                if (c == '\\') { i++; continue; }
                if (c == quote) in_quote = false;
                continue;
            }
            if (c == '"' || c == '\'') { in_quote = true; quote = c; continue; }
            if (c == '%' && i + 1 < s.length && s[i + 1] == '%') {
                return s.substring(0, i).strip();
            }
        }
        return s;
    }

    private static bool is_quoted(string s) {
        return s.length >= 2 &&
               ((s.has_prefix("\"") && s.has_suffix("\"")) || (s.has_prefix("'") && s.has_suffix("'")));
    }

    private static string strip_quotes(string s) {
        // `is_quoted(s) ? s.substring(1, s.length - 2) : s` would be fine —
        // a single, non-nested conditional mixing owned and unowned branches
        // is safe. Written out only for readability.
        if (is_quoted(s)) return s.substring(1, s.length - 2);
        return s;
    }
}

}
