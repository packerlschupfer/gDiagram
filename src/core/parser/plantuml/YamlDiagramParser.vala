/* YamlDiagramParser.vala — parser for PlantUML @startyaml */
namespace GDiagram {

public class YamlDiagramParser : Object {
    private YamlDiagram diagram;
    // Content lines: indent (spaces, a tab counts 2) and text without the indent
    private Gee.ArrayList<int> indents;
    private Gee.ArrayList<string> texts;

    public YamlDiagramParser() {}

    public YamlDiagram parse(string source) {
        this.diagram = new YamlDiagram();
        this.indents = new Gee.ArrayList<int>();
        this.texts = new Gee.ArrayList<string>();

        parse_yaml_diagram(source);

        return diagram;
    }

    private void parse_yaml_diagram(string source) {
        string[] lines = source.split("\n");
        bool in_style = false;

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i].replace("\r", "");
            string trimmed = raw.strip();
            string lower = trimmed.down();

            if (in_style) {
                if (lower.contains("</style>")) in_style = false;
                continue;
            }
            if (lower.has_prefix("@startyaml") || lower.has_prefix("@endyaml")) continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }
            if (trimmed.has_prefix("#highlight ")) {
                diagram.highlights.add(JsonDiagramParser.highlight_path(trimmed.substring(11)));
                continue;
            }
            if (trimmed == "---" || trimmed == "...") continue;
            // Include markers are preprocessor comments, not YAML scalars
            if (Preprocessor.is_include_marker(trimmed)) continue;
            if (lower.has_prefix("<style>")) {
                in_style = !lower.contains("</style>");
                continue;
            }
            if (DataTableStyle.read_skinparam_line(trimmed, diagram.skin)) continue;

            // Blank and comment lines are kept inside a block scalar ("multi: |")
            indents.add(count_indent(raw));
            texts.add(trimmed);
        }

        int pos = 0;
        skip_blank(ref pos);
        if (pos >= texts.size) return;

        var root = parse_node(ref pos, indents[pos]);
        // A lone scalar document still gets a table
        if (root.node_type == YamlNodeType.SCALAR) {
            var wrapper = new YamlNode(YamlNodeType.SEQUENCE, 0);
            wrapper.children.add(root);
            root = wrapper;
        }
        diagram.root = root;
    }

    private static bool is_comment_or_blank(string text) {
        return text.length == 0 || text.has_prefix("#");
    }

    private void skip_blank(ref int pos) {
        while (pos < texts.size && is_comment_or_blank(texts[pos])) {
            pos++;
        }
    }

    private static bool is_seq_item(string text) {
        return text == "-" || text.has_prefix("- ");
    }

    // The block starting at `pos` whose lines are indented by `indent`: a sequence
    // ("- item" lines) or a mapping ("key: value" lines)
    private YamlNode parse_node(ref int pos, int indent) {
        skip_blank(ref pos);
        if (pos < texts.size && is_seq_item(texts[pos])) {
            return parse_sequence(ref pos, indent);
        }
        if (pos < texts.size && find_key_colon(texts[pos]) < 0) {
            // A bare scalar line
            var scalar = new YamlNode(YamlNodeType.SCALAR, indent);
            scalar.value = scalar_value(texts[pos]);
            pos++;
            return scalar;
        }
        return parse_mapping(ref pos, indent);
    }

    private YamlNode parse_sequence(ref int pos, int indent) {
        var seq = new YamlNode(YamlNodeType.SEQUENCE, indent);
        while (true) {
            skip_blank(ref pos);
            if (pos >= texts.size || indents[pos] != indent || !is_seq_item(texts[pos])) {
                break;
            }
            string content = texts[pos].length > 1 ? texts[pos].substring(2).strip() : "";
            if (content.length == 0) {
                pos++;
                skip_blank(ref pos);
                if (pos < texts.size && indents[pos] > indent) {
                    seq.children.add(parse_node(ref pos, indents[pos]));
                } else {
                    var empty = new YamlNode(YamlNodeType.SCALAR, indent);
                    empty.value = "";
                    seq.children.add(empty);
                }
                continue;
            }
            // "- name: app" starts a mapping whose keys line up with "name": the
            // item's text becomes a line of its own at that column. Taking the item as
            // a scalar made "image:" a sibling of the list item.
            int item_indent = indent + (texts[pos].length - content.length);
            if (is_seq_item(content) || find_key_colon(content) >= 0) {
                texts[pos] = content;
                indents[pos] = item_indent;
                seq.children.add(parse_node(ref pos, item_indent));
                continue;
            }
            pos++;
            seq.children.add(scalar_node(content, indent, ref pos));
        }
        return seq;
    }

    private YamlNode parse_mapping(ref int pos, int indent) {
        var map = new YamlNode(YamlNodeType.MAPPING, indent);
        while (true) {
            skip_blank(ref pos);
            if (pos >= texts.size || indents[pos] != indent || is_seq_item(texts[pos])) {
                break;
            }
            string text = texts[pos];
            int colon = find_key_colon(text);
            if (colon < 0) {
                // Not a key: shown as a bare value
                var bare = new YamlNode(YamlNodeType.SCALAR, indent);
                bare.value = scalar_value(text);
                map.children.add(bare);
                pos++;
                continue;
            }
            string key = unquote(text.substring(0, colon).strip());
            string rest = text.substring(colon + 1).strip();
            pos++;
            YamlNode child;
            if (rest.length == 0 || rest.has_prefix("#")) {
                int next = pos;
                skip_blank(ref next);
                if (next < texts.size && (indents[next] > indent ||
                    (indents[next] == indent && is_seq_item(texts[next])))) {
                    pos = next;
                    child = parse_node(ref pos, indents[pos]);
                } else {
                    // "empty:" is an empty value, not an empty mapping
                    child = new YamlNode(YamlNodeType.SCALAR, indent);
                    child.value = "";
                }
            } else {
                child = scalar_node(rest, indent, ref pos);
            }
            child.key = key;
            map.children.add(child);
        }
        return map;
    }

    // A value written after "key:" or "- ": a block scalar ("|", ">"), a flow list or
    // mapping, or a plain / quoted scalar
    private YamlNode scalar_node(string rest, int indent, ref int pos) {
        if (rest.has_prefix("|") || rest.has_prefix(">")) {
            bool literal = rest.has_prefix("|");
            var sb = new StringBuilder();
            int block_indent = -1;
            while (pos < texts.size && (texts[pos].length == 0 || indents[pos] > indent)) {
                if (texts[pos].length > 0) {
                    if (block_indent < 0) block_indent = indents[pos];
                    if (sb.len > 0) sb.append(literal ? "\n" : " ");
                    sb.append(string.nfill(int.max(0, indents[pos] - block_indent), ' '));
                    sb.append(texts[pos]);
                } else if (sb.len > 0 && literal) {
                    sb.append("\n");
                }
                pos++;
            }
            var block = new YamlNode(YamlNodeType.SCALAR, indent);
            block.value = sb.str.strip();
            return block;
        }
        if (rest.has_prefix("[") && rest.has_suffix("]")) {
            var seq = new YamlNode(YamlNodeType.SEQUENCE, indent);
            foreach (string item in split_flow(rest.substring(1, rest.length - 2))) {
                var s = new YamlNode(YamlNodeType.SCALAR, indent);
                s.value = scalar_value(item);
                seq.children.add(s);
            }
            return seq;
        }
        if (rest.has_prefix("{") && rest.has_suffix("}")) {
            var map = new YamlNode(YamlNodeType.MAPPING, indent);
            foreach (string item in split_flow(rest.substring(1, rest.length - 2))) {
                int c = find_key_colon(item);
                var s = new YamlNode(YamlNodeType.SCALAR, indent);
                if (c >= 0) {
                    s.key = unquote(item.substring(0, c).strip());
                    s.value = scalar_value(item.substring(c + 1));
                } else {
                    s.value = scalar_value(item);
                }
                map.children.add(s);
            }
            return map;
        }
        var node = new YamlNode(YamlNodeType.SCALAR, indent);
        node.value = scalar_value(rest);
        return node;
    }

    private static Gee.ArrayList<string> split_flow(string body) {
        var items = new Gee.ArrayList<string>();
        var sb = new StringBuilder();
        char quote = 0;
        for (int i = 0; i < body.length; i++) {
            char c = body[i];
            if (quote != 0) {
                if (c == quote) quote = 0;
            } else if (c == '"' || c == '\'') {
                quote = c;
            } else if (c == ',') {
                if (sb.str.strip().length > 0) items.add(sb.str.strip());
                sb.truncate(0);
                continue;
            }
            sb.append_c(c);
        }
        if (sb.str.strip().length > 0) items.add(sb.str.strip());
        return items;
    }

    // A value as shown: quotes removed, a trailing " # comment" dropped
    private static string scalar_value(string raw) {
        string v = raw.strip();
        if ((v.has_prefix("\"") && v.has_suffix("\"") && v.length >= 2) ||
            (v.has_prefix("'") && v.has_suffix("'") && v.length >= 2)) {
            return unquote(v);
        }
        int hash = v.index_of(" #");
        if (hash > 0) {
            v = v.substring(0, hash).strip();
        }
        return v;
    }

    private static string unquote(string v) {
        if (v.length >= 2 && ((v.has_prefix("\"") && v.has_suffix("\"")) ||
                              (v.has_prefix("'") && v.has_suffix("'")))) {
            string inner = v.substring(1, v.length - 2);
            return v[0] == '"' ? inner.replace("\\\"", "\"") : inner.replace("''", "'");
        }
        return v;
    }

    // Position of the ":" ending a key ("key: value" or "key:"), outside quotes; -1
    // when the line is not a key ("http://x" or a plain scalar)
    private static int find_key_colon(string text) {
        char quote = 0;
        for (int i = 0; i < text.length; i++) {
            char c = text[i];
            if (quote != 0) {
                if (c == quote) quote = 0;
                continue;
            }
            if ((c == '"' || c == '\'') && i == 0) {
                quote = c;
                continue;
            }
            if (c == ':' && (i + 1 == text.length || text[i + 1] == ' ' || text[i + 1] == '\t')) {
                return i > 0 ? i : -1;
            }
        }
        return -1;
    }

    private int count_indent(string line) {
        int count = 0;
        foreach (char c in line.to_utf8()) {
            if (c == ' ') count++;
            else if (c == '\t') count += 2;
            else break;
        }
        return count;
    }
}

}
