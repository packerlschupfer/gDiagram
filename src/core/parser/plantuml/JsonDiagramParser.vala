/* JsonDiagramParser.vala — parser for PlantUML @startjson */
namespace GDiagram {

public class JsonDiagramParser : Object {
    private JsonDiagram diagram;
    private string src;
    private int pos;

    public JsonDiagramParser() {}

    public JsonDiagram parse(string source) {
        this.diagram = new JsonDiagram();

        parse_json_diagram(source);

        return diagram;
    }

    private void parse_json_diagram(string source) {
        // Extract JSON content between @startjson and @endjson
        // Also collect #highlight directives
        var json_lines = new StringBuilder();
        string[] lines = source.split("\n");

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            string lower = trimmed.down();

            if (lower == "@startjson" || lower == "@endjson") continue;
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }
            if (trimmed.has_prefix("#highlight ")) {
                // Parse highlight path: #highlight "key" / "subkey"
                string highlight_spec = trimmed.substring(11).strip();
                // Remove quotes and slashes to build a simple path string
                string path = highlight_spec.replace("\"", "").replace(" / ", ".").replace("/", ".");
                diagram.highlights.add(path.strip());
                continue;
            }
            if (trimmed.has_prefix("'") || trimmed.has_prefix("/'")) continue;
            if (trimmed.has_prefix("<style>") || trimmed == "</style>") continue;
            if (trimmed.has_prefix("skinparam")) continue;

            json_lines.append(lines[i]);
            json_lines.append("\n");
        }

        string json_content = json_lines.str.strip();
        if (json_content.length == 0) return;

        this.src = json_content;
        this.pos = 0;

        skip_whitespace();
        if (pos < src.length) {
            diagram.root = parse_value(null);
        }
    }

    private JsonNode? parse_value(string? key) {
        skip_whitespace();
        if (pos >= src.length) return null;

        char c = src[pos];

        if (c == '{') return parse_object(key);
        if (c == '[') return parse_array(key);
        if (c == '"') return parse_string_value(key);
        if (c == 't' || c == 'f') return parse_bool_value(key);
        if (c == 'n') return parse_null_value(key);
        if (c == '-' || (c >= '0' && c <= '9')) return parse_number_value(key);

        // Skip unknown characters
        pos++;
        return null;
    }

    private JsonNode parse_object(string? key) {
        pos++; // consume {
        var node = new JsonNode(JsonNodeType.OBJECT);
        node.key = key;
        skip_whitespace();

        while (pos < src.length && src[pos] != '}') {
            skip_whitespace();
            if (pos >= src.length || src[pos] == '}') break;

            // Parse key
            if (src[pos] != '"') { pos++; continue; }
            string child_key = parse_raw_string();
            skip_whitespace();
            if (pos < src.length && src[pos] == ':') pos++; // consume :
            skip_whitespace();

            // Parse value
            var child = parse_value(child_key);
            if (child != null) node.children.add(child);

            skip_whitespace();
            if (pos < src.length && src[pos] == ',') pos++; // consume ,
            skip_whitespace();
        }

        if (pos < src.length && src[pos] == '}') pos++; // consume }
        return node;
    }

    private JsonNode parse_array(string? key) {
        pos++; // consume [
        var node = new JsonNode(JsonNodeType.ARRAY);
        node.key = key;
        skip_whitespace();
        int idx = 0;

        while (pos < src.length && src[pos] != ']') {
            skip_whitespace();
            if (pos >= src.length || src[pos] == ']') break;

            var child = parse_value(idx.to_string());
            if (child != null) node.children.add(child);
            idx++;

            skip_whitespace();
            if (pos < src.length && src[pos] == ',') pos++;
            skip_whitespace();
        }

        if (pos < src.length && src[pos] == ']') pos++; // consume ]
        return node;
    }

    private JsonNode parse_string_value(string? key) {
        var node = new JsonNode(JsonNodeType.STRING);
        node.key = key;
        node.string_value = parse_raw_string();
        return node;
    }

    private string parse_raw_string() {
        if (pos >= src.length || src[pos] != '"') return "";
        pos++; // consume opening "
        var sb = new StringBuilder();
        while (pos < src.length && src[pos] != '"') {
            if (src[pos] == '\\' && pos + 1 < src.length) {
                pos++;
                char esc = src[pos];
                switch (esc) {
                    case '"': sb.append_c('"'); break;
                    case '\\': sb.append_c('\\'); break;
                    case 'n': sb.append_c('\n'); break;
                    case 't': sb.append_c('\t'); break;
                    default: sb.append_c(esc); break;
                }
            } else {
                sb.append_c(src[pos]);
            }
            pos++;
        }
        if (pos < src.length && src[pos] == '"') pos++; // consume closing "
        return sb.str;
    }

    private JsonNode parse_number_value(string? key) {
        var node = new JsonNode(JsonNodeType.NUMBER);
        node.key = key;
        var sb = new StringBuilder();
        while (pos < src.length && (src[pos] == '-' || src[pos] == '+' || src[pos] == '.' ||
               src[pos] == 'e' || src[pos] == 'E' ||
               (src[pos] >= '0' && src[pos] <= '9'))) {
            sb.append_c(src[pos]);
            pos++;
        }
        node.number_value = double.parse(sb.str);
        node.string_value = sb.str;
        return node;
    }

    private JsonNode parse_bool_value(string? key) {
        var node = new JsonNode(JsonNodeType.BOOLEAN);
        node.key = key;
        if (src.substring(pos).has_prefix("true")) {
            node.bool_value = true;
            pos += 4;
        } else {
            node.bool_value = false;
            pos += 5; // "false"
        }
        node.string_value = node.bool_value ? "true" : "false";
        return node;
    }

    private JsonNode parse_null_value(string? key) {
        var node = new JsonNode(JsonNodeType.NULL_VALUE);
        node.key = key;
        node.string_value = "null";
        pos += 4; // "null"
        return node;
    }

    private void skip_whitespace() {
        while (pos < src.length && (src[pos] == ' ' || src[pos] == '\t' ||
               src[pos] == '\n' || src[pos] == '\r')) {
            pos++;
        }
    }
}

}
