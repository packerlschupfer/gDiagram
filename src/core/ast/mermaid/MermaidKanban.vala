namespace GDiagram {

    // ==================== Kanban ====================

    public class KanbanCard : Object {
        public string id { get; set; }
        public string label { get; set; }
        public string? assigned { get; set; }
        public string? ticket { get; set; }
        public string? priority { get; set; }
        public int source_line { get; set; }

        public KanbanCard(string label, string id = "", int line = 0) {
            this.label = label;
            this.id = id.length > 0 ? id : label;
            this.source_line = line;
        }
    }

    public class KanbanColumn : Object {
        public string id { get; set; }
        public string label { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<KanbanCard> cards { get; private set; }

        public KanbanColumn(string label, string id = "", int line = 0) {
            this.label = label;
            this.id = id.length > 0 ? id : label;
            this.source_line = line;
            this.cards = new Gee.ArrayList<KanbanCard>();
        }

        public void add_card(KanbanCard c) { cards.add(c); }
    }

    public class MermaidKanban : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<KanbanColumn> columns { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }

        public MermaidKanban() {
            this.diagram_type = MermaidDiagramType.KANBAN;
            this.columns = new Gee.ArrayList<KanbanColumn>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public void add_column(KanbanColumn c) { columns.add(c); }
        public bool has_errors() { return errors.size > 0; }
        public bool is_empty() { return columns.size == 0; }
    }

}
