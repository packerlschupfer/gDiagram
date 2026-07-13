/* GitLogDiagramParser.vala — parser for PlantUML's @startgit / @startgitlog
 *
 * The body is `git log --graph` output, so this is a character walker, not a
 * grammar — PlantUML's GitDiagramFactory registers no commands at all and its
 * GitTextArea/CursorPosition pair does exactly what happens below:
 *
 *   - a line containing `*` is a commit, at (column of the `*`, line index);
 *     every other line is connector art and is ignored, never an error
 *   - the commit's name is the line with `[-.*|/\]` deleted, trimmed, up to
 *     the first space — so `*   6f35da9 (HEAD -> main) merge` gives `6f35da9`
 *   - its label is the text between the first `(` at or after the `*` and the
 *     next `)`
 *   - edges come only from the `| / \` connectors between commit rows
 *
 * The one glyph not handled is `_`, git's octopus-merge connector; PlantUML
 * walks it too, but an octopus merge of more than two parents is rare enough
 * that its lanes are reported as an error rather than drawn wrongly.
 */
namespace GDiagram {

    public class GitLogDiagramParser : Object {
        // A pasted log should not be able to cost unbounded work.
        public const int MAX_COMMITS = 2000;
        public const int MAX_ROWS = 20000;

        public GitLogDiagram parse(string source) {
            var d = new GitLogDiagram();
            string[] raw = source.split("\n");

            // The art rows, with their 1-based source line numbers. The
            // @start/@end tag lines are not art.
            var art = new Gee.ArrayList<string>();
            var art_lines = new Gee.ArrayList<int>();
            for (int i = 0; i < raw.length && art.size < MAX_ROWS; i++) {
                string line = raw[i];
                string t = line.strip();
                if (t.has_prefix("@start") || t.has_prefix("@end")) continue;
                // A quote is a PlantUML comment, but git decorations never start
                // a line with one, so dropping it is safe.
                if (t.has_prefix("'")) continue;
                art.add(line);
                art_lines.add(i + 1);
            }

            // Commits, in art order (top first, which is newest first in git).
            for (int r = 0; r < art.size; r++) {
                int col = art.get(r).index_of("*");
                if (col < 0) continue;
                if (d.commits.size >= MAX_COMMITS) {
                    d.errors.add(new ParseError(
                        "Too many commits: a git log draws at most %d".printf(MAX_COMMITS),
                        art_lines.get(r), 1));
                    break;
                }
                var c = new GitLogCommit(commit_name(art.get(r)), r, col, art_lines.get(r));
                c.label = commit_label(art.get(r), col);
                d.commits.add(c);
            }

            if (d.commits.size == 0) {
                // An empty block is what PlantUML draws as a blank page; only
                // say something when there was text that looked like art.
                foreach (string line in art) {
                    if (line.strip().length > 0) {
                        d.errors.add(new ParseError(
                            "No commits found: a git log body needs `git log --graph` output, " +
                            "whose commits are marked with `*`", art_lines.size > 0 ? art_lines.get(0) : 1, 1));
                        break;
                    }
                }
                return d;
            }

            link_parents(d, art);
            return d;
        }

        /**
         * The commit name: every connector character deleted from the whole
         * line, trimmed, then the first word. PlantUML's
         * CursorPosition.getCommitNameInLine() does exactly this.
         */
        internal static string commit_name(string line) {
            var sb = new StringBuilder();
            for (int i = 0; i < line.length; i++) {
                char ch = line[i];
                if (ch == '-' || ch == '.' || ch == '*' || ch == '|' || ch == '/' || ch == '\\') {
                    continue;
                }
                sb.append_c(ch);
            }
            string s = sb.str.strip();
            int sp = s.index_of(" ");
            return sp < 0 ? s : s.substring(0, sp);
        }

        /** The decoration: between the first `(` at or after the `*` and the next `)`. */
        internal static string? commit_label(string line, int star_col) {
            int open = line.index_of("(", star_col);
            if (open < 0) return null;
            int close = line.index_of(")", open + 1);
            if (close < 0) return null;
            string inner = line.substring(open + 1, close - open - 1).strip();
            return inner.length > 0 ? inner : null;
        }

        private static char at(Gee.ArrayList<string> art, int row, int col) {
            if (row < 0 || row >= art.size) return ' ';
            string line = art.get(row);
            if (col < 0 || col >= line.length) return ' ';
            return line[col];
        }

        /** The index of the commit whose `*` is at (row, col), or -1. */
        private static int commit_at(GitLogDiagram d, int row, int col) {
            for (int i = 0; i < d.commits.size; i++) {
                var c = d.commits.get(i);
                if (c.row == row && c.column == col) return i;
            }
            return -1;
        }

        /**
         * Walks the connector art downward from every commit to the commits
         * below it. Each lane leaving a commit is followed one row at a time:
         * `|` keeps the column, `\` steps right, `/` steps left, and a `*`
         * ends the lane at that parent.
         */
        private static void link_parents(GitLogDiagram d, Gee.ArrayList<string> art) {
            for (int i = 0; i < d.commits.size; i++) {
                var c = d.commits.get(i);
                int row = c.row + 1;
                // The lanes leaving this commit: straight down, and a branch
                // that peels off to either side. `|\` and `|/` put the slash in
                // the column next to the lane.
                var starts = new Gee.ArrayList<int>();
                if (is_down(at(art, row, c.column))) starts.add(c.column);
                if (at(art, row, c.column + 1) == '\\') starts.add(c.column + 1);
                if (at(art, row, c.column - 1) == '/') starts.add(c.column - 1);
                // A merge drawn as `*-.` reaches a lane two columns over.
                if (at(art, row, c.column + 2) == '\\') starts.add(c.column + 2);

                foreach (int start in starts) {
                    int parent = walk_down(art, d, row, start);
                    if (parent >= 0 && parent != i && !c.parents.contains(parent)) {
                        c.parents.add(parent);
                    }
                }

                // A commit with no connector below it may still be followed by
                // the next commit in the same lane (git prints no `|` when the
                // rows are adjacent).
                if (c.parents.size == 0) {
                    int next = commit_at(d, c.row + 1, c.column);
                    if (next >= 0) c.parents.add(next);
                }
            }
        }

        private static bool is_down(char ch) {
            return ch == '|' || ch == '*';
        }

        /**
         * Follows one lane from (row, col) downward, returning the index of the
         * commit it reaches, or -1 when the art runs out. Bounded by the art
         * height, so inconsistent art cannot loop (PlantUML throws there).
         */
        private static int walk_down(Gee.ArrayList<string> art, GitLogDiagram d, int row, int col) {
            int cx = col;
            for (int cy = row; cy < art.size; cy++) {
                char ch = at(art, cy, cx);
                if (ch == '*') {
                    return commit_at(d, cy, cx);
                }
                // A diagonal spans two columns: the `\` drawn at column k joins
                // the lane at k-1 above to the one at k+1 below, and `/` the
                // other way round. Stepping only one column is what made a
                // `|/` collapse miss its parent entirely.
                if (ch == '|') {
                    continue;
                }
                if (ch == '\\') {
                    cx += 1;
                    continue;
                }
                if (ch == '/') {
                    cx -= 1;
                    continue;
                }
                // Nothing in this lane's own column: the lane bends in the
                // column beside it, and so resumes two columns over.
                if (at(art, cy, cx + 1) == '\\') {
                    cx += 2;
                    continue;
                }
                if (at(art, cy, cx - 1) == '/') {
                    cx -= 2;
                    continue;
                }
                return -1;
            }
            return -1;
        }
    }
}
