/* MermaidTreeViewParser.vala — Mermaid `treeView-beta` parser
 *
 * Port of mermaid 12.2.0's treeView front end, which is two stages:
 *
 *   1. boxDrawingPreprocessor.ts — `tree`-command style input (├── └── │ and
 *      the heavy variants ┣━━ ┗━━ ┃) is rewritten into indentation form before
 *      the grammar ever sees it. The indent *unit* of the input is inferred
 *      from the column of the first branch character, so 2-, 3- or 4-space
 *      `tree` output all work.
 *   2. the Langium grammar (treeView.langium), whose node line is
 *        indent=INDENTATION? (QUOTED_NAME | BARE_NAME) (CLASS|ICON|DESC)*
 *      with INDENTATION = `[ \t]{1,}` valued as its *character count* — the db
 *      only ever compares two levels, so any consistent indent width works.
 *
 * Column arithmetic runs on a unichar array, not on the UTF-8 string: a box
 * drawing character is three bytes, so a byte offset would put ├ at column 3
 * and infer a segment width of 3 for `tree`'s 4-column output.
 */
namespace GDiagram {

public class MermaidTreeViewParser : Object {
    private MermaidTreeView diagram;

    // Box-drawing character classes (boxDrawingPreprocessor.ts).
    private const unichar DASH_LIGHT = 0x2500;      // ─
    private const unichar DASH_HEAVY = 0x2501;      // ━
    private const unichar VERT_LIGHT = 0x2502;      // │
    private const unichar VERT_HEAVY = 0x2503;      // ┃
    private const unichar CORNER_LIGHT = 0x2514;    // └
    private const unichar CORNER_HEAVY = 0x2517;    // ┗
    private const unichar TEE_LIGHT = 0x251C;       // ├
    private const unichar TEE_HEAVY = 0x2523;       // ┣

    // One output indentation level per depth, as the preprocessor emits it.
    private const int INDENT_UNIT = 4;

    public MermaidTreeViewParser() {}

    public MermaidTreeView parse(string source) {
        this.diagram = new MermaidTreeView();
        var lines = split_lines(source);
        var content = preprocess(lines);
        build(content);
        return diagram;
    }

    // ==================== line plumbing ====================

    private class SourceLine : Object {
        public string text;
        public int number;      // 1-based line number in the original source
        public SourceLine(string text, int number) {
            this.text = text;
            this.number = number;
        }
    }

    private Gee.ArrayList<SourceLine> split_lines(string source) {
        var list = new Gee.ArrayList<SourceLine>();
        string[] raw = source.split("\n");
        for (int i = 0; i < raw.length; i++) {
            string text = raw[i];
            if (text.has_suffix("\r")) text = text.substring(0, text.length - 1);
            list.add(new SourceLine(text, i + 1));
        }
        return list;
    }

    private static unichar[] to_chars(string s) {
        unichar[] chars = {};
        int index = 0;
        unichar c;
        while (s.get_next_char(ref index, out c)) chars += c;
        return chars;
    }

    private static string from_chars(unichar[] chars, int start, int end) {
        var sb = new StringBuilder();
        for (int i = start; i < end && i < chars.length; i++) sb.append_unichar(chars[i]);
        return sb.str;
    }

    private static bool is_space(unichar c) { return c == ' ' || c == '\t'; }

    // Same test for a byte of a plain ASCII string (Vala's char, not unichar).
    private static bool is_space_byte(char c) { return c == ' ' || c == '\t'; }

    private static bool is_branch(unichar c) {
        return c == CORNER_LIGHT || c == CORNER_HEAVY || c == TEE_LIGHT || c == TEE_HEAVY;
    }

    private static bool is_dash(unichar c) { return c == DASH_LIGHT || c == DASH_HEAVY; }

    private static bool is_vert(unichar c) { return c == VERT_LIGHT || c == VERT_HEAVY; }

    private static bool is_box(unichar c) { return is_branch(c) || is_dash(c) || is_vert(c); }

    /** `^[\s│┃]+$` — a line that only continues the trunk, with no content. */
    private static bool is_decoration_only(unichar[] chars) {
        if (chars.length == 0) return false;
        foreach (unichar c in chars) {
            if (!c.isspace() && !is_vert(c)) return false;
        }
        return true;
    }

    /** `^[\s─━│┃└┗├┣]+$` — the whole line is box drawing and whitespace. */
    private static bool is_all_box(unichar[] chars) {
        if (chars.length == 0) return false;
        foreach (unichar c in chars) {
            if (!c.isspace() && !is_box(c)) return false;
        }
        return true;
    }

    private static bool has_box(unichar[] chars) {
        foreach (unichar c in chars) {
            if (is_box(c)) return true;
        }
        return false;
    }

    /** `^\s*%%` */
    private static bool is_comment(string line) {
        return line.strip().has_prefix("%%");
    }

    /** `^\s*(title[\t ]|accTitle[\t ]*:|accDescr[\t ]*[:{])` */
    private static bool is_metadata(string line) {
        string s = line.chug();
        string lower = s.down();
        if (lower.has_prefix("title") && s.length > 5 && is_space_byte(s[5])) return true;
        if (lower.has_prefix("acctitle")) {
            string rest = s.substring(8).chug();
            return rest.has_prefix(":");
        }
        if (lower.has_prefix("accdescr")) {
            string rest = s.substring(8).chug();
            return rest.has_prefix(":") || rest.has_prefix("{");
        }
        return false;
    }

    /** Tabs → 4 spaces, so segment-width inference sees consistent columns. */
    private static string expand_tabs(string line) {
        return line.replace("\t", "    ");
    }

    // ==================== stage 1: box drawing ====================

    /**
     * The content lines after the keyword, with box-drawing input rewritten to
     * indentation. Front matter is consumed first (mermaid strips it upstream).
     */
    private Gee.ArrayList<SourceLine> preprocess(Gee.ArrayList<SourceLine> lines) {
        var body = strip_front_matter(lines);

        int keyword = -1;
        for (int i = 0; i < body.size; i++) {
            string t = body.get(i).text.strip().down();
            if (t == "treeview-beta" ||
                (t.has_prefix("treeview-beta") && is_space_byte(t[13]))) {
                keyword = i;
                break;
            }
        }

        var content = new Gee.ArrayList<SourceLine>();
        for (int i = keyword + 1; i < body.size; i++) content.add(body.get(i));
        if (!needs_box_conversion(content)) return content;
        return convert_box_drawing(content);
    }

    private Gee.ArrayList<SourceLine> strip_front_matter(Gee.ArrayList<SourceLine> lines) {
        var body = new Gee.ArrayList<SourceLine>();
        bool in_front = false;
        bool seen = false;
        foreach (var line in lines) {
            string t = line.text.strip();
            if (in_front) {
                if (t == "---") in_front = false;
                else if (t.has_prefix("title:") && diagram.title == null) {
                    diagram.title = unquote(t.substring(6).strip());
                }
                continue;
            }
            if (!seen && t == "---") {
                seen = true;
                in_front = true;
                continue;
            }
            if (t.length > 0) seen = true;
            body.add(line);
        }
        return body;
    }

    /** isBoxDrawingFormat() over the lines the preprocessor counts as content. */
    private static bool needs_box_conversion(Gee.ArrayList<SourceLine> content) {
        foreach (var line in content) {
            string text = line.text;
            if (text.strip().length == 0 || is_comment(text) || is_metadata(text)) continue;
            var chars = to_chars(text);
            if (is_decoration_only(chars)) continue;
            if (has_box(to_chars(expand_tabs(text)))) return true;
        }
        return false;
    }

    /**
     * The indent unit of the input: the column of the first branch character
     * that is not at column 0 (`tree` puts the first ├ at column 0 for a
     * top-level entry, which says nothing about the unit). 4 when there is none.
     */
    private static int infer_segment_width(Gee.ArrayList<SourceLine> content) {
        foreach (var line in content) {
            string text = line.text;
            if (text.strip().length == 0 || is_comment(text) || is_metadata(text)) continue;
            var chars = to_chars(expand_tabs(text));
            if (is_decoration_only(chars)) continue;
            for (int i = 0; i < chars.length; i++) {
                if (is_branch(chars[i])) {
                    if (i > 0) return i;
                    break;
                }
            }
        }
        return 4;
    }

    private Gee.ArrayList<SourceLine> convert_box_drawing(Gee.ArrayList<SourceLine> content) {
        int segment = infer_segment_width(content);
        var output = new Gee.ArrayList<SourceLine>();

        foreach (var line in content) {
            string text = line.text;
            if (text.strip().length == 0 || is_comment(text) || is_metadata(text)) {
                output.add(line);
                continue;
            }
            var chars = to_chars(text);
            if (is_decoration_only(chars)) continue;

            string normalized = expand_tabs(text);
            var norm = to_chars(normalized);

            int branch = -1;
            for (int i = 0; i < norm.length; i++) {
                if (is_branch(norm[i])) { branch = i; break; }
            }

            if (branch >= 0) {
                // The column of the branch character gives the depth; the name
                // follows the branch, its dashes and the spaces after them.
                int depth = (int) Math.round((double) branch / segment) + 1;
                int pos = branch + 1;
                while (pos < norm.length && is_dash(norm[pos])) pos++;
                while (pos < norm.length && norm[pos] == ' ') pos++;
                string body = from_chars(norm, pos, norm.length);
                while (body.length > 0 && is_space_byte(body[body.length - 1])) {
                    body = body.substring(0, body.length - 1);
                }
                if (body.length == 0) {
                    diagram.errors.add(new ParseError(
                        "Empty node — expected a filename or directory name after the box-drawing prefix",
                        line.number, 1));
                    continue;
                }
                output.add(new SourceLine(string.nfill(depth * INDENT_UNIT, ' ') + body, line.number));
            } else if (is_all_box(norm)) {
                continue;
            } else if (has_box(norm)) {
                // Box characters but no branch: content that happens to contain
                // one ("Section ─ A.txt"). A root-level item.
                output.add(line);
            } else if (norm.length > 0 && norm[0].isspace()) {
                diagram.errors.add(new ParseError(
                    "Unexpected indentation without box-drawing characters. " +
                    "In box-drawing format, use ├── or └── prefixes for indented nodes.",
                    line.number, 1));
                continue;
            } else {
                output.add(line);
            }
        }
        return output;
    }

    // ==================== stage 2: the node grammar ====================

    private void build(Gee.ArrayList<SourceLine> content) {
        var stack = new Gee.ArrayList<TreeViewNode>();
        stack.add(diagram.root);

        foreach (var line in content) {
            string text = line.text;
            if (text.strip().length == 0) continue;
            if (is_comment(text)) continue;
            if (take_metadata(text)) continue;

            var chars = to_chars(text);
            int level = 0;
            while (level < chars.length && is_space(chars[level])) level++;
            if (level >= chars.length) continue;

            int pos = level;
            string? name = read_name(chars, ref pos);
            if (name == null) {
                diagram.errors.add(new ParseError(
                    "Expected a file or directory name", line.number, level + 1));
                continue;
            }

            string? css_class = null;
            string? icon = null;
            string? description = null;
            read_annotations(chars, pos, ref css_class, ref icon, ref description);

            bool is_dir = name.has_suffix("/");
            if (is_dir) name = name.substring(0, name.length - 1);

            var node = new TreeViewNode(name,
                is_dir ? TreeViewNodeType.DIRECTORY : TreeViewNodeType.FILE,
                level, line.number);
            node.css_class = css_class;
            node.icon = icon;
            node.description = description;

            // db.addNode(): the parent is the first node on the stack with a
            // strictly smaller level. The synthetic root is at -1 and so can
            // never be popped.
            while (stack.get(stack.size - 1).level >= level) {
                stack.remove_at(stack.size - 1);
            }
            stack.get(stack.size - 1).add_child(node);
            stack.add(node);
        }
    }

    /** `title ...` / `accTitle: ...` / `accDescr: ...` (TitleAndAccessibilities). */
    private bool take_metadata(string line) {
        string s = line.strip();
        string lower = s.down();
        if (lower == "title" || (lower.has_prefix("title") && s.length > 5 && is_space_byte(s[5]))) {
            string value = s.length > 5 ? s.substring(5).strip() : "";
            if (diagram.title == null) diagram.title = value;
            return true;
        }
        if (lower.has_prefix("acctitle")) {
            string rest = s.substring(8).chug();
            if (rest.has_prefix(":")) {
                diagram.acc_title = rest.substring(1).strip();
                return true;
            }
        }
        if (lower.has_prefix("accdescr")) {
            string rest = s.substring(8).chug();
            if (rest.has_prefix(":")) {
                diagram.acc_descr = rest.substring(1).strip();
                return true;
            }
            if (rest.has_prefix("{")) {
                // Single-line form only; a block form's body lines fall through
                // to the node grammar exactly as they do in mermaid.
                diagram.acc_descr = rest.substring(1).replace("}", "").strip();
                return true;
            }
        }
        return false;
    }

    /**
     * QUOTED_NAME or BARE_NAME starting at `pos`, which is left just past the
     * name. Null when the text there cannot start a name (it begins with an
     * annotation), which is a parse error in mermaid too.
     */
    private static string? read_name(unichar[] chars, ref int pos) {
        if (pos >= chars.length) return null;
        unichar q = chars[pos];
        if (q == '"' || q == '\'') {
            for (int i = pos + 1; i < chars.length; i++) {
                if (chars[i] == q) {
                    string name = from_chars(chars, pos + 1, i);
                    pos = i + 1;
                    return name;
                }
            }
            // Unterminated quote: mermaid's lexer rejects the line. Be lenient
            // and take the rest of it, quote included.
            string rest = from_chars(chars, pos, chars.length);
            pos = chars.length;
            return rest.strip();
        }

        // BARE_NAME cannot start with an annotation marker.
        if (annotation_at(chars, pos, true)) return null;

        int end = pos + 1;
        while (end < chars.length && !annotation_at(chars, end, false)) end++;
        string name = from_chars(chars, pos, end);
        pos = end;
        // The value converter trims trailing spaces and tabs only.
        while (name.length > 0 && is_space_byte(name[name.length - 1])) {
            name = name.substring(0, name.length - 1);
        }
        return name.length > 0 ? name : null;
    }

    /**
     * Whether an annotation starts at `i`. The three annotation terminals all
     * begin with `[ \t]+`; `at_name_start` drops that requirement so a line
     * that opens with `:::x`, `icon(` or `##` is rejected as a name, as
     * BARE_NAME's leading lookahead does.
     */
    private static bool annotation_at(unichar[] chars, int i, bool at_name_start) {
        int p = i;
        if (!at_name_start) {
            if (p >= chars.length || !is_space(chars[p])) return false;
            while (p < chars.length && is_space(chars[p])) p++;
        }
        if (p + 1 < chars.length && chars[p] == '#' && chars[p + 1] == '#') return true;
        if (starts_with(chars, p, "icon(")) return true;
        if (p + 2 < chars.length && chars[p] == ':' && chars[p + 1] == ':' && chars[p + 2] == ':') {
            // CLASS_ANNOTATION also needs a class name after the colons.
            if (at_name_start) return true;
            int q = p + 3;
            while (q < chars.length && is_space(chars[q])) q++;
            return q < chars.length && (chars[q].isalpha() || chars[q] == '_');
        }
        return false;
    }

    private static bool starts_with(unichar[] chars, int i, string literal) {
        for (int k = 0; k < literal.length; k++) {
            if (i + k >= chars.length || chars[i + k] != (unichar) literal[k]) return false;
        }
        return true;
    }

    private static bool is_word(unichar c) {
        return c.isalnum() || c == '_';
    }

    /**
     * The `(CLASS_ANNOTATION | ICON_ANNOTATION | DESC_ANNOTATION)*` tail. A
     * repeated annotation of the same kind overwrites the earlier one, as
     * Langium's `=` assignment does.
     */
    private static void read_annotations(unichar[] chars, int pos,
                                         ref string? css_class, ref string? icon,
                                         ref string? description) {
        int i = pos;
        while (i < chars.length) {
            int p = i;
            if (!is_space(chars[p])) return;
            while (p < chars.length && is_space(chars[p])) p++;

            if (p + 1 < chars.length && chars[p] == '#' && chars[p + 1] == '#') {
                description = from_chars(chars, p + 2, chars.length).strip();
                if (description.length == 0) description = null;
                return;
            }

            if (starts_with(chars, p, "icon(")) {
                int q = p + 5;
                while (q < chars.length && (is_word(chars[q]) || chars[q] == '-' || chars[q] == ':')) q++;
                if (q >= chars.length || chars[q] != ')') return;
                string name = from_chars(chars, p + 5, q);
                // `icon()` means "no icon"; the renderer reads "none" that way.
                icon = name.length > 0 ? name : "none";
                i = q + 1;
                continue;
            }

            if (p + 2 < chars.length && chars[p] == ':' && chars[p + 1] == ':' && chars[p + 2] == ':') {
                int q = p + 3;
                while (q < chars.length && is_space(chars[q])) q++;
                if (q >= chars.length || !(chars[q].isalpha() || chars[q] == '_')) return;
                int start = q;
                q++;
                while (q < chars.length && (is_word(chars[q]) || chars[q] == '-')) q++;
                css_class = from_chars(chars, start, q);
                i = q;
                continue;
            }

            // Not an annotation: mermaid's lexer would fail here. Ignore the
            // remainder rather than failing the whole diagram.
            return;
        }
    }

    private static string unquote(string s) {
        if (s.length >= 2 && ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                              (s.has_prefix("'") && s.has_suffix("'")))) {
            return s.substring(1, s.length - 2);
        }
        return s;
    }
}

}
