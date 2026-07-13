/* MermaidPacketParser.vala — Mermaid packet-beta diagram parser */
namespace GDiagram {

public class MermaidPacketParser : Object {
    private Gee.ArrayList<string> lines;
    private MermaidPacket diagram;
    private int current_bit;

    public MermaidPacketParser() {
        this.current_bit = 0;
    }

    public MermaidPacket parse(string source) {
        this.diagram = new MermaidPacket();
        this.lines = new Gee.ArrayList<string>();
        this.current_bit = 0;

        foreach (var line in source.split("\n")) {
            lines.add(line);
        }

        parse_packet();

        return diagram;
    }

    private void parse_packet() {
        for (int i = 0; i < lines.size; i++) {
            string raw = lines.get(i);
            string trimmed = raw.strip();

            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("%%")) continue;
            // Skip the opening keyword line
            string lower = trimmed.down();
            if (lower == "packet-beta" || lower == "packet") continue;

            // Parse title
            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            // Parse field: "start-end: label" or "+count: label"
            int colon = trimmed.index_of(":");
            if (colon < 0) continue;

            string range_part = trimmed.substring(0, colon).strip();
            string label_part = trimmed.substring(colon + 1).strip();
            // Remove surrounding quotes
            if (label_part.has_prefix("\"") && label_part.has_suffix("\"") && label_part.length >= 2) {
                label_part = label_part.substring(1, label_part.length - 2);
            }

            int bit_start = 0;
            int bit_end = 0;

            if (range_part.has_prefix("+")) {
                // Increment syntax: +N
                int count = int.parse(range_part.substring(1));
                if (count <= 0) count = 1;
                bit_start = current_bit;
                bit_end = current_bit + count - 1;
                current_bit += count;
            } else if (range_part.contains("-")) {
                // Explicit range: start-end
                string[] parts = range_part.split("-");
                bit_start = int.parse(parts[0].strip());
                bit_end = (parts.length > 1) ? int.parse(parts[1].strip()) : bit_start;
                current_bit = bit_end + 1;
            } else {
                // Single bit
                bit_start = int.parse(range_part);
                bit_end = bit_start;
                current_bit = bit_end + 1;
            }

            diagram.add_field(new PacketField(bit_start, bit_end, label_part, i + 1));
        }
    }

    /**
     * Parses PlantUML's @startpacketdiag form:
     *
     *   @startpacketdiag
     *   packetdiag {
     *     colwidth = 16     node_height = 40     same_height = true
     *     scale_interval = 4     scale_direction = rtl
     *     0-15: Source Port          (a range; only its length counts)
     *     16: Flag [rotate = 270]
     *     * Options [len = 8, height = 2]
     *   }
     *   @endpacketdiag
     */
    public MermaidPacket parse_packetdiag(string source) {
        var d = new MermaidPacket();
        d.plantuml_style = true;
        string[] src_lines = source.split("\n");
        Regex setting_re, field_re, star_re;
        try {
            setting_re = new Regex("""^(colwidth|node_height|scale_interval|same_height|scale_direction)\s*(?:=\s*([A-Za-z0-9]+))?\s*;?$""");
            field_re = new Regex("""^(\d{1,7})(?:-(\d{1,7}))?:?\s+(.*?)(?:\s*\[(.*?)\])?\s*;?$""");
            star_re = new Regex("""^\*\s+(.*?)(?:\s*\[(.*?)\])?\s*;?$""");
        } catch (RegexError e) {
            return d;
        }
        bool in_block = false;
        for (int i = 0; i < src_lines.length; i++) {
            string t = src_lines[i].strip();
            int line_no = i + 1;
            if (t.length == 0 || t.has_prefix("'") || t.has_prefix("@")) continue;
            if (t == "{" || t == "}") continue;
            if (t.has_prefix("packetdiag")) {
                in_block = true;
                continue;
            }
            if (t.down().has_prefix("title ")) {
                d.title = t.substring(6).strip();
                continue;
            }
            MatchInfo m;
            if (setting_re.match(t, 0, out m)) {
                string key = m.fetch(1);
                string? val = m.fetch(2);
                if (val == null) val = "";
                switch (key) {
                    case "colwidth":
                        if (int.parse(val) > 0) d.colwidth = int.parse(val);
                        break;
                    case "node_height":
                        d.node_height = int.max(0, int.parse(val));
                        break;
                    case "scale_interval":
                        if (int.parse(val) > 0) d.scale_interval = int.parse(val);
                        break;
                    case "same_height":
                        d.same_height = (val == "" || val.down() == "true");
                        break;
                    default:
                        d.scale_rtl = (val.down() == "rtl");
                        break;
                }
                continue;
            }
            int width;
            string label;
            string? attrs;
            if (field_re.match(t, 0, out m)) {
                int start = int.parse(m.fetch(1));
                string? end_s = m.fetch(2);
                int end = (end_s != null && end_s.length > 0) ? int.parse(end_s) : start;
                width = (end >= start) ? end - start + 1 : 1;
                label = m.fetch(3);
                attrs = m.fetch(4);
            } else if (star_re.match(t, 0, out m)) {
                width = 1;
                label = m.fetch(1);
                attrs = m.fetch(2);
            } else {
                if (in_block) {
                    d.errors.add(new ParseError("Unrecognized packetdiag line: %s".printf(t), line_no, 1));
                }
                continue;
            }
            // Fields follow each other: a field starts where the previous
            // one ended, whatever range it was written with.
            int start_bit = d.fields.size == 0 ? 0 : d.fields.get(d.fields.size - 1).bit_end + 1;
            var field = new PacketField(start_bit, start_bit, label.strip(), line_no);
            if (attrs != null) {
                foreach (string kv in attrs.split(",")) {
                    string[] parts = kv.split("=", 2);
                    if (parts.length < 2) continue;
                    string k = parts[0].strip().down();
                    int v = int.parse(parts[1].strip());
                    if (k == "len" && v > 0) width = v;
                    else if (k == "height" && v > 0) field.row_span = v;
                    else if (k == "rotate") field.rotate = v;
                }
            }
            field.bit_end = start_bit + width - 1;
            d.add_field(field);
        }
        return d;
    }
}

}
