/* MermaidPacketParser.vala — Mermaid packet-beta diagram parser */
namespace GDiagram {

public class MermaidPacketParser : Object {
    private Gee.ArrayList<string> lines;
    private MermaidPacket diagram;

    // Mermaid stops after maxPacketSize (1e4) drawn blocks — a block being one
    // field's slice of one 32-bit row. Without the cap `0-2000000: "Payload"`
    // drew 62 501 rows into a 56 MB SVG. Past the cap the prefix is drawn and
    // MermaidPacket.truncated says so, which is what Mermaid does too.
    public const int BITS_PER_ROW = 32;
    public const int MAX_BLOCKS = 10000;

    public MermaidPacket parse(string source) {
        this.diagram = new MermaidPacket();
        this.lines = new Gee.ArrayList<string>();

        foreach (var line in source.split("\n")) {
            lines.add(line);
        }

        parse_packet();

        return diagram;
    }

    private static bool all_digits(string s) {
        if (s.length == 0) return false;
        for (int i = 0; i < s.length; i++) {
            if (!s[i].isdigit()) return false;
        }
        return true;
    }

    /** "+N", "N" or "N-M" with unsigned decimal numbers — Mermaid's packet grammar. */
    private static bool is_range_syntax(string text) {
        if (text.has_prefix("+")) {
            return all_digits(text.substring(1).strip());
        }
        int dash = text.index_of("-");
        if (dash >= 0) {
            return all_digits(text.substring(0, dash).strip())
                && all_digits(text.substring(dash + 1).strip());
        }
        return all_digits(text);
    }

    // The number of row slices a field occupies, which is what the renderer
    // draws and what Mermaid counts against maxPacketSize.
    private static int block_count(int bit_start, int bit_end) {
        return bit_end / BITS_PER_ROW - bit_start / BITS_PER_ROW + 1;
    }

    private void parse_packet() {
        int blocks = 0;
        // The last bit any accepted field ended on; -1 before the first one, as in
        // Mermaid's populate(). A field must start right after it.
        int last_bit = -1;
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

            // Mermaid's grammar knows exactly three shapes, all with unsigned
            // decimal numbers: "+N", "N" and "N-M". `int.parse()` quietly reads 0
            // out of everything else, so a negative start such as `-5-10` split
            // into ["", "5", "10"] and was drawn as bits 0-5 — the bit numbers the
            // file asked for were gone without a word. Mermaid reports a syntax
            // error for it.
            if (!is_range_syntax(range_part)) {
                diagram.errors.add(new ParseError(
                    "Packet block '%s' is invalid. Expected \"start-end\", \"bit\" or \"+count\".".printf(
                        range_part), i + 1, 1));
                continue;
            }

            int bit_start = 0;
            int bit_end = 0;
            // "+N" carries no start: it always continues where the last field ended,
            // so it can never be non-contiguous.
            bool implicit_start = false;

            if (range_part.has_prefix("+")) {
                // Increment syntax: +N
                int count = int.parse(range_part.substring(1));
                // Mermaid: "Packet block 8 is invalid. Cannot have a zero bit field."
                if (count == 0) {
                    diagram.errors.add(new ParseError(
                        "Packet block %d is invalid. Cannot have a zero bit field.".printf(last_bit + 1),
                        i + 1, 1));
                    continue;
                }
                if (count < 0) count = 1;
                implicit_start = true;
                bit_start = last_bit + 1;
                bit_end = bit_start + count - 1;
            } else if (range_part.contains("-")) {
                // Explicit range: start-end
                string[] parts = range_part.split("-");
                bit_start = int.parse(parts[0].strip());
                bit_end = (parts.length > 1) ? int.parse(parts[1].strip()) : bit_start;
            } else {
                // Single bit
                bit_start = int.parse(range_part);
                bit_end = bit_start;
            }

            // Mermaid: "Packet block 10 - 3 is invalid. End must be greater
            // than start." Silently collapsing it to a 1-bit field hid the typo.
            if (bit_end < bit_start) {
                diagram.errors.add(new ParseError(
                    "Packet block %d - %d is invalid. End must be greater than start.".printf(
                        bit_start, bit_end), i + 1, 1));
                continue;
            }
            if (bit_start < 0) {
                diagram.errors.add(new ParseError(
                    "Packet block %d is invalid. Bit numbers start at 0.".printf(bit_start), i + 1, 1));
                continue;
            }
            // Mermaid: "Packet block 8 - 23 is not contiguous. It should start from 16."
            // Fields have to tile the packet; overlapping and gapped ranges were taken
            // as written and drawn on top of each other.
            if (!implicit_start && bit_start != last_bit + 1) {
                diagram.errors.add(new ParseError(
                    "Packet block %d - %d is not contiguous. It should start from %d.".printf(
                        bit_start, bit_end, last_bit + 1), i + 1, 1));
                // Carry on from where this field ends, so one mistyped range reports
                // once instead of making every field after it non-contiguous too.
                last_bit = bit_end;
                continue;
            }

            int need = block_count(bit_start, bit_end);
            if (blocks + need > MAX_BLOCKS) {
                // Mermaid fills the packet up to maxPacketSize and draws that; so do
                // we. The field is kept and cut to the blocks that are left — dropping
                // it whole left `0-2000000: "Payload"` with nothing to draw at all —
                // and the renderer says the drawing is cut short.
                diagram.truncated = true;
                int room = MAX_BLOCKS - blocks;
                if (room > 0) {
                    // The last bit of the `room`-th row this field reaches into
                    bit_end = (bit_start / BITS_PER_ROW + room) * BITS_PER_ROW - 1;
                    diagram.add_field(new PacketField(bit_start, bit_end, label_part, i + 1));
                }
                break;
            }
            blocks += need;
            last_bit = bit_end;

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
