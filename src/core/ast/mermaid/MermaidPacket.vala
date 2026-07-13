namespace GDiagram {

// ==================== Packet ====================

public class PacketField : Object {
    public int bit_start { get; set; }
    public int bit_end { get; set; }
    public string label { get; set; }
    public int source_line { get; set; }

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
