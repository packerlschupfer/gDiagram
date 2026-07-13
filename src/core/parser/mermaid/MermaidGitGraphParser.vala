namespace GDiagram {
    public class MermaidGitGraphParser : Object {
        private Gee.ArrayList<MermaidToken> tokens;
        private int current;
        private MermaidGitGraph diagram;
        private string current_branch_name;
        private Gee.HashMap<string, string?> branch_heads;  // branch -> last commit id
        private int commit_counter;

        public MermaidGitGraphParser() {
            this.current = 0;
            this.commit_counter = 0;
        }

        public MermaidGitGraph parse(string source) {
            var lexer = new MermaidLexer(source);
            this.tokens = lexer.scan_all();
            this.current = 0;
            this.diagram = new MermaidGitGraph();
            this.current_branch_name = "main";
            this.branch_heads = new Gee.HashMap<string, string?>();
            this.branch_heads.set("main", null);
            this.commit_counter = 0;

            try {
                parse_git_graph();
            } catch (GLib.Error e) {
                diagram.errors.add(new ParseError(e.message, error_line, error_column));
            }

            return diagram;
        }

        private void parse_git_graph() throws GLib.Error {
            skip_newlines();

            // Expect 'gitGraph' keyword (lexed as GIT_GRAPH token or IDENTIFIER)
            if (!match(MermaidTokenType.GIT_GRAPH)) {
                if (check(MermaidTokenType.IDENTIFIER) &&
                    peek().lexeme.down() == "gitgraph") {
                    advance();
                } else {
                    error_at_current("Expected 'gitGraph'");
                }
            }

            // Optional direction hint on the same line (LR, TB, BT, RL)
            if (check(MermaidTokenType.LR) || check(MermaidTokenType.TD) ||
                check(MermaidTokenType.TB) || check(MermaidTokenType.BT)) {
                advance();
            } else if (check(MermaidTokenType.IDENTIFIER)) {
                string up = peek().lexeme.up();
                if (up == "LR" || up == "TB" || up == "BT" || up == "RL") {
                    advance();
                }
            }

            skip_newlines();

            while (!is_at_end()) {
                try {
                    parse_statement();
                } catch (GLib.Error e) {
                    diagram.errors.add(new ParseError(
                        e.message,
                        previous().line,
                        previous().column
                    ));
                    synchronize();
                }
                skip_newlines();
            }
        }

        private void parse_statement() throws GLib.Error {
            skip_newlines();
            if (is_at_end()) return;
            if (match(MermaidTokenType.COMMENT)) return;

            if (check(MermaidTokenType.TITLE)) {
                parse_title();
                return;
            }

            if (!check(MermaidTokenType.IDENTIFIER)) {
                // Skip non-identifier tokens (symbols, etc.)
                advance();
                return;
            }

            string keyword = peek().lexeme.down();
            switch (keyword) {
                case "commit":
                    advance();
                    parse_commit();
                    break;
                case "branch":
                    advance();
                    parse_branch();
                    break;
                case "checkout":
                case "switch":
                    advance();
                    parse_checkout();
                    break;
                case "merge":
                    advance();
                    parse_merge();
                    break;
                default:
                    // Skip unrecognised line
                    consume_line();
                    break;
            }
        }

        private void parse_title() {
            advance(); // consume TITLE token
            var parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                if (parts.len > 0) parts.append(" ");
                parts.append(advance().lexeme);
            }
            diagram.title = parts.str.strip();
        }

        private void parse_commit() {
            int line = previous().line;
            string auto_id = "c%d".printf(commit_counter++);
            string? id = null;
            var type = GitGraphCommitType.NORMAL;
            string? tag = null;

            parse_commit_options(ref id, ref type, ref tag);
            if (id == null || id.length == 0) id = auto_id;

            var commit = new GitGraphCommit(
                id, current_branch_name, diagram.all_commits.size, line
            );
            commit.commit_type = type;
            commit.tag = tag;
            commit.parent_id = branch_heads.get(current_branch_name);

            var branch = diagram.get_or_create_branch(current_branch_name);
            branch.add_commit(commit);
            diagram.all_commits.add(commit);
            branch_heads.set(current_branch_name, id);
        }

        private void parse_branch() {
            // branch <name> [order: N]
            var parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end() &&
                   !check(MermaidTokenType.COMMENT)) {
                string lex = peek().lexeme;
                // Skip "order: N" options
                if (lex.down() == "order") {
                    advance();
                    if (match(MermaidTokenType.COLON)) {
                        if (check(MermaidTokenType.NUMBER) || check(MermaidTokenType.IDENTIFIER))
                            advance();
                    }
                    continue;
                }
                if (lex == ":") { advance(); continue; }
                if (parts.len > 0) parts.append(" ");
                parts.append(advance().lexeme);
            }
            string branch_name = parts.str.strip();
            if (branch_name.length == 0) return;

            var branch = diagram.get_or_create_branch(branch_name);
            branch.branched_from_branch = current_branch_name;
            branch.branched_from_commit = branch_heads.get(current_branch_name);

            // New branch inherits the parent's current HEAD
            if (!branch_heads.has_key(branch_name)) {
                branch_heads.set(branch_name, branch_heads.get(current_branch_name));
            }
            current_branch_name = branch_name;
        }

        private void parse_checkout() {
            // checkout <name>  or  switch <name>
            var parts = new StringBuilder();
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end() &&
                   !check(MermaidTokenType.COMMENT)) {
                if (parts.len > 0) parts.append(" ");
                parts.append(advance().lexeme);
            }
            string branch_name = parts.str.strip();
            if (branch_name.length == 0) return;

            diagram.get_or_create_branch(branch_name);
            if (!branch_heads.has_key(branch_name)) {
                branch_heads.set(branch_name, null);
            }
            current_branch_name = branch_name;
        }

        private void parse_merge() {
            int line = previous().line;

            // First token after 'merge' is the source branch name
            string source_branch = "";
            if (check(MermaidTokenType.IDENTIFIER) || check(MermaidTokenType.STRING)) {
                source_branch = advance().lexeme.strip();
            }
            if (source_branch.length == 0) return;

            string auto_id = "c%d".printf(commit_counter++);
            string? id = null;
            var type = GitGraphCommitType.NORMAL;
            string? tag = null;

            parse_commit_options(ref id, ref type, ref tag);
            if (id == null || id.length == 0) id = auto_id;

            var commit = new GitGraphCommit(
                id, current_branch_name, diagram.all_commits.size, line
            );
            commit.commit_type = type;
            commit.tag = tag;
            commit.parent_id = branch_heads.get(current_branch_name);
            commit.merge_from_id = branch_heads.get(source_branch);

            var branch = diagram.get_or_create_branch(current_branch_name);
            branch.add_commit(commit);
            diagram.all_commits.add(commit);
            branch_heads.set(current_branch_name, id);
        }

        // Parses key: "value" / key: VALUE options on the current line.
        private void parse_commit_options(
            ref string? id,
            ref GitGraphCommitType type,
            ref string? tag
        ) {
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end() &&
                   !check(MermaidTokenType.COMMENT)) {
                if (!check(MermaidTokenType.IDENTIFIER)) {
                    advance();
                    continue;
                }
                string key = advance().lexeme.down();
                if (!match(MermaidTokenType.COLON)) continue;

                string? value = null;
                if (check(MermaidTokenType.STRING)) {
                    value = advance().lexeme;
                } else if (check(MermaidTokenType.IDENTIFIER)) {
                    value = advance().lexeme;
                } else if (check(MermaidTokenType.NUMBER)) {
                    value = advance().lexeme;
                }
                if (value == null) continue;

                switch (key) {
                    case "id":
                        id = value;
                        break;
                    case "type":
                        switch (value.up()) {
                            case "REVERSE":
                                type = GitGraphCommitType.REVERSE;
                                break;
                            case "HIGHLIGHT":
                                type = GitGraphCommitType.HIGHLIGHT;
                                break;
                            default:
                                type = GitGraphCommitType.NORMAL;
                                break;
                        }
                        break;
                    case "tag":
                        tag = value;
                        break;
                    case "msg":
                        // 'msg' used in older Mermaid as display label
                        if (id == null) id = value;
                        break;
                }
            }
        }

        private void consume_line() {
            while (!check(MermaidTokenType.NEWLINE) && !is_at_end()) {
                advance();
            }
        }

        private void skip_newlines() {
            while (match(MermaidTokenType.NEWLINE) || match(MermaidTokenType.COMMENT)) {}
        }

        private void synchronize() {
            while (!is_at_end()) {
                if (previous().token_type == MermaidTokenType.NEWLINE) return;
                advance();
            }
        }

        private bool match(MermaidTokenType type) {
            if (check(type)) { advance(); return true; }
            return false;
        }

        private bool check(MermaidTokenType type) {
            if (is_at_end()) return false;
            return peek().token_type == type;
        }

        private MermaidToken advance() {
            if (!is_at_end()) current++;
            return previous();
        }

        private bool is_at_end() {
            return peek().token_type == MermaidTokenType.EOF;
        }

        private MermaidToken peek() {
            return tokens.get(current);
        }

        private MermaidToken previous() {
            return tokens.get(current - 1);
        }

        private int error_line = 1;
        private int error_column = 1;

        private void error_at_current(string message) throws GLib.Error {
            var token = peek();
            error_line = token.line;
            error_column = token.column;
            string ctx = token.lexeme.length > 0
                ? " (found: '%s')".printf(token.lexeme) : "";
            throw new GLib.IOError.FAILED("%s%s", message, ctx);
        }
    }
}
