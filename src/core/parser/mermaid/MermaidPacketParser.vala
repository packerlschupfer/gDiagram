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
}

}
