/* GitLogDiagram.vala — AST for PlantUML's @startgit / @startgitlog diagram type
 *
 * This type has no authored grammar at all. PlantUML's GitDiagramFactory
 * registers *no* commands: it drains the source lines into a GitTextArea and
 * GNodeBuilder then walks the characters. In other words @startgit redraws the
 * ASCII art of `git log --graph` as boxes and arrows — it is a renderer for
 * text produced by another tool, like @startditaa, not a language.
 *
 * It never reads a repository: there is no process execution and no file API
 * anywhere in net.sourceforge.plantuml.gitlog. Verified by disassembling all
 * ten classes and by rendering an empty block from inside a real repository
 * with history — the output was blank.
 *
 * Note the keyword is really `git`; `@startgitlog` reaches the same factory
 * only because PlantUML matches diagram keywords by case-insensitive prefix.
 */
namespace GDiagram {

    /** One `*` in the art, with the commit it stands for. */
    public class GitLogCommit : Object {
        /** The hash (or whatever word git printed first), e.g. "6f35da9". */
        public string name { get; set; default = ""; }

        /** The decoration in parentheses: "HEAD -> main", "tag: v0.1". */
        public string? label { get; set; default = null; }

        /** Where the `*` was: art row and character column. */
        public int row { get; set; default = 0; }
        public int column { get; set; default = 0; }

        /** The graph lane; git prints lanes two characters apart. */
        public int lane {
            get { return column / 2; }
        }

        public int source_line { get; set; default = 0; }

        /** Indices into GitLogDiagram.commits of the commits below this one. */
        public Gee.ArrayList<int> parents { get; set; default = new Gee.ArrayList<int>(); }

        public GitLogCommit(string name, int row, int column, int source_line) {
            this.name = name;
            this.row = row;
            this.column = column;
            this.source_line = source_line;
        }

        /** What the box shows: the name, and the decoration under it if any. */
        public string display_label() {
            if (label != null && label.length > 0) {
                return name + "\n" + label;
            }
            return name;
        }
    }

    public class GitLogDiagram : Object {
        public Gee.ArrayList<GitLogCommit> commits { get; set; default = new Gee.ArrayList<GitLogCommit>(); }
        public Gee.ArrayList<ParseError> errors { get; set; default = new Gee.ArrayList<ParseError>(); }

        public bool has_errors() {
            return errors.size > 0;
        }

        public bool is_empty() {
            return commits.size == 0;
        }

        /** How many lanes the art uses, for the renderer's width estimate. */
        public int lane_count() {
            int n = 0;
            foreach (var c in commits) {
                n = int.max(n, c.lane + 1);
            }
            return n;
        }
    }
}
