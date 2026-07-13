namespace GDiagram {

// ==================== Packet ====================

public class PacketField : Object {
    public int bit_start { get; set; }
    public int bit_end { get; set; }
    public string label { get; set; }
    public int source_line { get; set; }
    // PlantUML packetdiag attributes: `height` (rows the block spans) and
    // `rotate` (parsed; PlantUML 1.2026.8 does not draw it either).
    public int row_span { get; set; default = 1; }
    public int rotate { get; set; default = 0; }

    public PacketField(int start, int end, string label, int line = 0) {
        this.bit_start = start;
        this.bit_end = end;
        this.label = label;
        this.source_line = line;
    }

    public int bit_width() { return bit_end - bit_start + 1; }
}

public class MermaidPacket : Object {
    public MermaidDiagramType diagram_type { get; private set; }
    public string? title { get; set; }
    public Gee.ArrayList<PacketField> fields { get; private set; }
    public Gee.ArrayList<ParseError> errors { get; private set; }

    // PlantUML @startpacketdiag form. Mermaid packet-beta places a field at its
    // bit range in 32-bit rows; PlantUML packetdiag lays the fields out one
    // after another in `colwidth`-bit rows (a range only gives the length) and
    // draws a bit ruler above them.
    public bool plantuml_style { get; set; default = false; }
    public int colwidth { get; set; default = 16; }
    public int node_height { get; set; default = 0; }
    public bool same_height { get; set; default = false; }
    public int scale_interval { get; set; default = 0; }   // 0 = colwidth / 2
    public bool scale_rtl { get; set; default = false; }

    public MermaidPacket() {
        this.diagram_type = MermaidDiagramType.PACKET;
        this.title = null;
        this.fields = new Gee.ArrayList<PacketField>();
        this.errors = new Gee.ArrayList<ParseError>();
    }

    public void add_field(PacketField field) { fields.add(field); }
    public bool has_errors() { return errors.size > 0; }
    public bool is_empty() { return fields.size == 0; }
}

}
