/* BoardDiagram.vala — AST for PlantUML board/kanban layout (@startboard) */
namespace GDiagram {

public class BoardCard : Object {
    public string text { get; set; }
    public int source_line { get; set; }

    public BoardCard(string text, int line = 0) {
        this.text = text;
        this.source_line = line;
    }
}

public class BoardColumn : Object {
    public string title { get; set; }
    public int source_line { get; set; }
    public Gee.ArrayList<BoardCard> cards { get; private set; }

    public BoardColumn(string title, int line = 0) {
        this.title = title;
        this.source_line = line;
        this.cards = new Gee.ArrayList<BoardCard>();
    }
}

public class BoardDiagram : Object {
    public string? title { get; set; default = null; }
    public Gee.ArrayList<BoardColumn> columns { get; private set; }

    public BoardDiagram() {
        this.columns = new Gee.ArrayList<BoardColumn>();
    }
}

}
