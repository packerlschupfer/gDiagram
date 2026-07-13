/* MermaidVennParser.vala — Mermaid `venn-beta` diagram parser
 *
 * Ports mermaid 12.2.0's jison grammar (see MermaidVenn.vala). The jison lexer
 * is line-aware through its `bol` start condition:
 *
 *   - leading whitespace followed by `text` emits INDENT_TEXT *when indent mode
 *     is on* — i.e. right after a `set`/`union` statement — and that form takes
 *     the sets of the statement above it instead of an explicit list;
 *   - any other non-whitespace character at the start of a line turns indent
 *     mode off again, so `set`/`union`/`style` may be indented freely.
 *
 * `size` defaults from vennDB.ts: `10 / identifiers²`.
 */
namespace GDiagram {

public class MermaidVennParser : Object {
    private MermaidVenn diagram;
    private Gee.HashSet<string> known_sets;
    private Gee.ArrayList<string>? current_sets;

    public MermaidVennParser() {}

    public MermaidVenn parse(string source) {
        this.diagram = new MermaidVenn();
        this.known_sets = new Gee.HashSet<string>();
        this.current_sets = null;

        string[] lines = source.split("\n");
        bool in_front_matter = false;
        bool seen_content = false;
        bool indent_mode = false;

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();
            int lineno = i + 1;

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
            if (trimmed.length == 0) continue;        // whitespace-only line: lexer rule 2
            if (trimmed.has_prefix("%%")) continue;   // comment: lexer rules 0/7
            seen_content = true;

            trimmed = strip_trailing_comment(trimmed);
            if (trimmed.length == 0) continue;

            bool indented = raw.length > 0 && (raw[0] == ' ' || raw[0] == '\t');
            string lower = trimmed.down();

            if (lower == "venn-beta") {
                diagram.declared = true;
                indent_mode = false;
                continue;
            }
            // `title <text>`: the TITLE terminal is /title\s[^#\n;]+/, so the
            // whole rest of the line is the title (`substr(6)` in the action).
            if (lower.has_prefix("title") &&
                trimmed.length > 5 && (trimmed[5] == ' ' || trimmed[5] == '\t')) {
                diagram.title = trimmed.substring(6).strip();
                indent_mode = false;
                continue;
            }

            string head = first_word(lower);

            if (head == "set") {
                parse_set(trimmed.substring(3).strip(), lineno);
                indent_mode = true;
                continue;
            }
            if (head == "union") {
                parse_union(trimmed.substring(5).strip(), lineno);
                indent_mode = true;
                continue;
            }
            if (head == "style") {
                parse_style(trimmed.substring(5).strip(), lineno);
                indent_mode = false;
                continue;
            }
            if (head == "text") {
                string rest = trimmed.substring(4).strip();
                if (indented && indent_mode) {
                    parse_indented_text(rest, lineno);
                } else {
                    parse_text(rest, lineno);
                    indent_mode = false;
                }
                continue;
            }

            indent_mode = false;
            diagram.errors.add(new ParseError(
                "unexpected `%s` — expected set, union, text, style or title".printf(head),
                lineno, 1));
        }

        if (!diagram.declared) {
            diagram.errors.add(new ParseError("missing `venn-beta` keyword", 1, 1));
        }
        return diagram;
    }

    // ── statements ───────────────────────────────────────────────

    // SET identifier (BRACKET_LABEL)? (COLON NUMERIC)?
    private void parse_set(string spec, int lineno) {
        string? label;
        double? size;
        string body = split_tail(spec, out label, out size);
        var ids = parse_identifier_list(body, lineno);
        if (ids.size != 1) {
            diagram.errors.add(new ParseError(
                "`set` takes exactly one identifier — use `union` for several", lineno, 1));
            return;
        }
        add_subset(ids, label, size, lineno);
    }

    // UNION identifierList (BRACKET_LABEL)? (COLON NUMERIC)?
    private void parse_union(string spec, int lineno) {
        string? label;
        double? size;
        string body = split_tail(spec, out label, out size);
        var ids = parse_identifier_list(body, lineno);
        if (ids.size < 2) {
            diagram.errors.add(new ParseError("union requires multiple identifiers", lineno, 1));
            return;
        }
        // validateUnionIdentifiers: every member must already be a declared set.
        var unknown = new Gee.ArrayList<string>();
        foreach (var id in ids) {
            if (!known_sets.contains(id)) unknown.add(id);
        }
        if (unknown.size > 0) {
            diagram.errors.add(new ParseError(
                "unknown set identifier: %s".printf(string.joinv(", ", venn_string_array(unknown))),
                lineno, 1));
            return;
        }
        add_subset(ids, label, size, lineno);
    }

    // TEXT identifierList (IDENTIFIER|STRING|NUMERIC) (BRACKET_LABEL)?
    private void parse_text(string spec, int lineno) {
        string? label;
        double? ignored;
        string body = split_tail(spec, out label, out ignored);
        var parts = parse_identifier_list(body, lineno, true);
        if (parts.size < 2) {
            diagram.errors.add(new ParseError(
                "`text` needs a set list and an id: `text A,B item`", lineno, 1));
            return;
        }
        string id = parts.remove_at(parts.size - 1);
        diagram.text_nodes.add(new VennTextNode(sorted_copy(parts), id, label, lineno));
    }

    // INDENT_TEXT (IDENTIFIER|STRING|NUMERIC) (BRACKET_LABEL)?
    private void parse_indented_text(string spec, int lineno) {
        if (current_sets == null) {
            diagram.errors.add(new ParseError("text requires set", lineno, 1));
            return;
        }
        string? label;
        double? ignored;
        string body = split_tail(spec, out label, out ignored);
        var parts = parse_identifier_list(body, lineno, true);
        if (parts.size != 1) {
            diagram.errors.add(new ParseError(
                "an indented `text` takes exactly one id", lineno, 1));
            return;
        }
        var sets = new Gee.ArrayList<string>();
        sets.add_all(current_sets);
        diagram.text_nodes.add(new VennTextNode(sets, parts.get(0), label, lineno));
    }

    // STYLE identifierList stylesOpt
    private void parse_style(string spec, int lineno) {
        // The identifier list ends at the first identifier followed by a colon
        // (`style A fill: red` → targets [A], then `fill: red`).
        int split = find_style_split(spec);
        if (split < 0) {
            diagram.errors.add(new ParseError(
                "`style` needs at least one `key: value` pair", lineno, 1));
            return;
        }
        var ids = parse_identifier_list(spec.substring(0, split).strip(), lineno, true);
        if (ids.size == 0) {
            diagram.errors.add(new ParseError("`style` needs a target", lineno, 1));
            return;
        }
        var entry = new VennStyleEntry(sorted_copy(ids), lineno);
        foreach (string field in split_top_level(spec.substring(split), ',')) {
            string f = field.strip();
            if (f.length == 0) continue;
            int colon = f.index_of(":");
            if (colon <= 0) {
                diagram.errors.add(new ParseError(
                    "style field `%s` is not `key: value`".printf(f), lineno, 1));
                continue;
            }
            string key = f.substring(0, colon).strip();
            string value = normalize_text(f.substring(colon + 1).strip());
            if (key.length > 0) entry.styles.set(key, value);
        }
        if (entry.styles.size > 0) diagram.style_entries.add(entry);
    }

    // ── helpers ──────────────────────────────────────────────────

    private void add_subset(Gee.ArrayList<string> ids, string? label, double? size, int lineno) {
        var sets = sorted_copy(ids);
        // vennDB.addSubsetData: size ?? 10 / identifierList.length²
        // Spelled as if/else, NOT `size != null ? size : ...`: `size` is a
        // boxed `double?`, and valac frees that temporary before the read in a
        // conditional. Harmless at -O0, garbage at -O2 — so it passed here and
        // in CI and failed only in the deb build, which is what ships.
        double resolved;
        if (size != null) {
            resolved = (double) size;
        } else {
            resolved = 10.0 / (ids.size * ids.size);
        }
        current_sets = sets;
        if (sets.size == 1) known_sets.add(sets.get(0));
        diagram.subsets.add(new VennSubset(sets, resolved, label, lineno));
    }

    /**
     * Splits off a trailing `["label"]` / `[label]` and `: <number>`, returning
     * the part before them. Both are optional and the label comes first.
     */
    private static string split_tail(string spec, out string? label, out double? size) {
        label = null;
        size = null;
        string s = spec.strip();

        // `: <number>` at the very end (COLON NUMERIC).
        int colon = s.last_index_of(":");
        if (colon >= 0 && !inside_brackets(s, colon)) {
            string tail = s.substring(colon + 1).strip();
            if (tail.length > 0 && is_number(tail)) {
                size = double.parse(tail);
                s = s.substring(0, colon).strip();
            }
        }

        // `[...]` at the end (BRACKET_LABEL).
        if (s.has_suffix("]")) {
            int open = s.last_index_of("[");
            if (open >= 0) {
                string inner = s.substring(open + 1, s.length - open - 2);
                // Lexer rule 16 (`["..."]`) slices (2, -2); rule 17 (`[...]`) slices (1, -1).trim().
                label = normalize_text(inner);
                s = s.substring(0, open).strip();
            }
        }
        return s;
    }

    private static bool inside_brackets(string s, int at) {
        int depth = 0;
        bool in_quote = false;
        for (int i = 0; i < at; i++) {
            char c = s[i];
            if (c == '"') in_quote = !in_quote;
            else if (!in_quote && c == '[') depth++;
            else if (!in_quote && c == ']') depth--;
        }
        return depth > 0 || in_quote;
    }

    /**
     * `identifierList` = identifier (COMMA identifier)*, where an identifier is
     * `[A-Za-z_][A-Za-z0-9\-_]*` or a quoted string. With `allow_trailing` the
     * list may be followed by one more space-separated token (the `text` id and
     * the `style` targets are written that way).
     */
    private Gee.ArrayList<string> parse_identifier_list(string spec, int lineno,
                                                        bool allow_trailing = false) {
        var out_list = new Gee.ArrayList<string>();
        if (spec.strip().length == 0) return out_list;
        foreach (string chunk in split_top_level(spec, ',')) {
            string c = chunk.strip();
            if (c.length == 0) continue;
            if (!allow_trailing) {
                out_list.add(normalize_text(c));
                continue;
            }
            // The last comma-group may hold two space-separated tokens.
            foreach (string piece in split_space_tokens(c)) {
                out_list.add(normalize_text(piece));
            }
        }
        return out_list;
    }

    /** Splits on `sep` outside quotes and brackets. */
    private static Gee.ArrayList<string> split_top_level(string spec, char sep) {
        var parts = new Gee.ArrayList<string>();
        var cur = new StringBuilder();
        int depth = 0;
        bool in_quote = false;
        for (int i = 0; i < spec.length; i++) {
            char c = spec[i];
            if (c == '"') in_quote = !in_quote;
            else if (!in_quote && c == '[') depth++;
            else if (!in_quote && c == ']') depth--;
            if (c == sep && depth == 0 && !in_quote) {
                parts.add(cur.str);
                cur.truncate(0);
                continue;
            }
            cur.append_c(c);
        }
        parts.add(cur.str);
        return parts;
    }

    /** Splits on runs of whitespace outside quotes. */
    private static Gee.ArrayList<string> split_space_tokens(string spec) {
        var parts = new Gee.ArrayList<string>();
        var cur = new StringBuilder();
        bool in_quote = false;
        for (int i = 0; i < spec.length; i++) {
            char c = spec[i];
            if (c == '"') { in_quote = !in_quote; cur.append_c(c); continue; }
            if (!in_quote && (c == ' ' || c == '\t')) {
                if (cur.len > 0) { parts.add(cur.str); cur.truncate(0); }
                continue;
            }
            cur.append_c(c);
        }
        if (cur.len > 0) parts.add(cur.str);
        return parts;
    }

    /** The index of the first `key:` field in a `style` body, or -1. */
    private static int find_style_split(string spec) {
        bool in_quote = false;
        for (int i = 0; i < spec.length; i++) {
            char c = spec[i];
            if (c == '"') { in_quote = !in_quote; continue; }
            if (in_quote || c != ':') continue;
            // Walk back over the identifier before the colon to its start.
            int j = i - 1;
            while (j >= 0 && (spec[j] == ' ' || spec[j] == '\t')) j--;
            while (j >= 0 && (spec[j].isalnum() || spec[j] == '-' || spec[j] == '_')) j--;
            return j + 1;
        }
        return -1;
    }

    // vennDB.normalizeText: trim, then drop one layer of double quotes.
    private static string normalize_text(string text) {
        string t = text.strip();
        if (t.length >= 2 && t.has_prefix("\"") && t.has_suffix("\"")) {
            return t.substring(1, t.length - 2);
        }
        return t;
    }

    private static string strip_quotes(string s) {
        return normalize_text(s);
    }

    private static Gee.ArrayList<string> sorted_copy(Gee.Collection<string> ids) {
        var list = new Gee.ArrayList<string>();
        list.add_all(ids);
        list.sort((a, b) => strcmp(a, b));
        return list;
    }

    private static bool is_number(string s) {
        if (s.length == 0) return false;
        int i = 0;
        if (s[0] == '+' || s[0] == '-') i = 1;
        bool digits = false, dot = false;
        for (; i < s.length; i++) {
            if (s[i].isdigit()) { digits = true; continue; }
            if (s[i] == '.' && !dot) { dot = true; continue; }
            return false;
        }
        return digits;
    }

    private static string first_word(string s) {
        int end = 0;
        while (end < s.length && !s[end].isspace()) end++;
        return s.substring(0, end);
    }

    private static string strip_trailing_comment(string s) {
        bool in_quote = false;
        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (c == '"') { in_quote = !in_quote; continue; }
            if (!in_quote && c == '%' && i + 1 < s.length && s[i + 1] == '%') {
                return s.substring(0, i).strip();
            }
        }
        return s;
    }
}

}
