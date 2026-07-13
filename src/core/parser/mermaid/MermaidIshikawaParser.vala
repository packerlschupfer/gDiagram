/* MermaidIshikawaParser.vala — Mermaid `ishikawa` / `ishikawa-beta` parser
 *
 * Port of mermaid 12.2.0's ishikawa.jison + ishikawaDb.ts. The grammar is
 * line-oriented and tiny:
 *
 *   SPACELINE  \s*%%.*  |  [\s]+[\n]        -> ignored
 *   NL         [\n]+                        -> ignored
 *   ISHIKAWA   ishikawa-beta | ishikawa     -> the keyword (case-insensitive)
 *   SPACELIST  [\s]+                        -> indentation, valued as its length
 *   TEXT       [^\n]+                       -> the statement, trimmed
 *   statement: SPACELIST TEXT -> addNode(indent, text) | TEXT -> addNode(0, text)
 *
 * jison's lexer here is first-match-in-rule-order (no `flex` option), so
 * SPACELIST never swallows a newline: the indent is just the leading
 * whitespace of the line, with a tab counting as one character. Blank lines
 * and whole-line `%%` comments are no-ops; an inline `%%` stays part of TEXT.
 *
 * The db makes the first statement the effect (fish head) and takes the
 * indentation of the *first cause* as the zero point, so an effect line
 * indented more deeply than its causes still nests correctly.
 */
namespace GDiagram {

public class MermaidIshikawaParser : Object {
    private MermaidIshikawa diagram;

    public MermaidIshikawaParser() {}

    public MermaidIshikawa parse(string source) {
        this.diagram = new MermaidIshikawa();

        var stack = new Gee.ArrayList<IshikawaNode>();
        int base_level = -1;            // the first cause's raw indentation
        bool have_base = false;
        bool keyword_seen = false;

        string[] lines = source.split("\n");
        bool in_front_matter = false;
        bool seen_content = false;

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            if (raw.has_suffix("\r")) raw = raw.substring(0, raw.length - 1);
            string trimmed = raw.strip();

            // Front matter is stripped upstream of mermaid's parser.
            if (trimmed == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) continue;
            if (trimmed.length == 0) continue;            // SPACELINE / NL
            if (trimmed.has_prefix("%%")) continue;       // whole-line comment
            seen_content = true;

            int indent = 0;
            while (indent < raw.length && (raw[indent] == ' ' || raw[indent] == '\t')) indent++;
            string body = raw.substring(indent).strip();

            if (!keyword_seen) {
                // The keyword is the first token; anything left on its line is
                // the first statement (the lexer just carries on).
                string lower = body.down();
                string? rest = null;
                if (lower.has_prefix("ishikawa-beta") && word_break(body, 13)) {
                    rest = body.substring(13);
                } else if (lower.has_prefix("ishikawa") && word_break(body, 8)) {
                    rest = body.substring(8);
                }
                keyword_seen = true;   // only the first statement can be the keyword
                if (rest != null) {
                    string tail = rest.strip();
                    if (tail.length == 0) continue;
                    int gap = 0;
                    while (gap < rest.length && (rest[gap] == ' ' || rest[gap] == '\t')) gap++;
                    add_node(stack, ref base_level, ref have_base, gap, tail, i + 1);
                    continue;
                }
                // No keyword: gDiagram only routes a file here once detection
                // matched, so treat the line as a statement rather than failing.
            }

            add_node(stack, ref base_level, ref have_base, indent, body, i + 1);
        }

        return diagram;
    }

    /** The `\b` of the keyword rules: the keyword cannot run into a word character. */
    private static bool word_break(string s, int at) {
        if (at >= s.length) return true;
        char c = s[at];
        return !(c.isalnum() || c == '_');
    }

    private void add_node(Gee.ArrayList<IshikawaNode> stack, ref int base_level,
                          ref bool have_base, int raw_level, string text, int line) {
        if (diagram.root == null) {
            var root = new IshikawaNode(text, 0, line);
            diagram.root = root;
            stack.clear();
            stack.add(root);
            return;
        }

        if (!have_base) {
            base_level = raw_level;
            have_base = true;
        }

        int level = raw_level - base_level + 1;
        if (level <= 0) level = 1;

        // Pop until the top is a strictly shallower node (= the parent).
        while (stack.size > 1 && stack.get(stack.size - 1).level >= level) {
            stack.remove_at(stack.size - 1);
        }

        var node = new IshikawaNode(text, level, line);
        stack.get(stack.size - 1).add_child(node);
        stack.add(node);
    }
}

}
