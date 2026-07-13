/* MermaidGitGraphParser.vala — Mermaid gitGraph parser.
 *
 * Reads statements straight from the source lines with the terminals of
 * Mermaid 11.17's Langium grammar: branch names are REFERENCE tokens
 * (\w([-./\w]*[-\w])?) or strings, so "feature/login" stays one name.
 * The commit/branch/merge/checkout/cherry-pick semantics and their errors
 * follow gitGraphAst.ts.
 */
namespace GDiagram {
    public class MermaidGitGraphParser : Object {
        private MermaidGitGraph diagram;
        private string current_branch_name;
        private Gee.HashMap<string, string?> branch_heads;  // branch -> last commit id
        private Gee.HashMap<string, GitGraphCommit> commits;
        private int seq;

        // Tokens of the current line
        private Gee.ArrayList<string> toks;
        private Gee.ArrayList<bool> quoted;
        private int pos;
        private int line_no;

        public MermaidGitGraphParser() {
        }

        public MermaidGitGraph parse(string source) {
            this.diagram = new MermaidGitGraph();
            this.current_branch_name = "main";
            this.branch_heads = new Gee.HashMap<string, string?>();
            this.branch_heads.set("main", null);
            this.commits = new Gee.HashMap<string, GitGraphCommit>();
            this.seq = 0;

            string[] lines = source.replace("\r\n", "\n").split("\n");
            int i = 0;
            string? main_name = null;

            // YAML front matter: title and gitGraph config
            while (i < lines.length && lines[i].strip().length == 0) i++;
            if (i < lines.length && lines[i].strip() == "---") {
                var fm = new StringBuilder();
                int j = i + 1;
                while (j < lines.length && lines[j].strip() != "---") {
                    string fl = lines[j].strip();
                    if (fl.has_prefix("title:")) diagram.title = unquote(fl.substring(6).strip());
                    fm.append(lines[j]).append("\n");
                    j++;
                }
                apply_options(fm.str, ref main_name);
                i = j < lines.length ? j + 1 : j;
            }

            bool seen_header = false;
            for (; i < lines.length; i++) {
                string line = lines[i].strip();
                line_no = i + 1;
                if (line.length == 0) continue;
                if (line.has_prefix("%%{")) {
                    var dir = new StringBuilder(line);
                    while (!dir.str.contains("}%%") && i + 1 < lines.length) {
                        i++;
                        dir.append("\n").append(lines[i]);
                    }
                    apply_options(dir.str, ref main_name);
                    continue;
                }
                if (line.has_prefix("%%")) continue;
                int comment = line.index_of("%%");
                if (comment > 0) line = line.substring(0, comment).strip();

                if (!seen_header) {
                    if (!line.has_prefix("gitGraph")) {
                        add_error("Expected 'gitGraph' (found: '%s')".printf(line));
                        return diagram;
                    }
                    seen_header = true;
                    if (main_name != null) {
                        diagram.rename_main_branch(main_name);
                        branch_heads.unset("main");
                        branch_heads.set(main_name, null);
                        current_branch_name = main_name;
                    }
                    string rest = line.substring(8).strip();
                    if (rest.has_prefix(":")) rest = rest.substring(1).strip();
                    foreach (string dir in new string[] { "LR", "TB", "BT" }) {
                        if (rest.has_prefix(dir)) {
                            diagram.direction = dir;
                            rest = rest.substring(2).strip();
                            if (rest.has_prefix(":")) rest = rest.substring(1).strip();
                        }
                    }
                    if (rest.length > 0) add_error("Unexpected '%s' after gitGraph".printf(rest));
                    continue;
                }

                if (line.has_prefix("title") && (line.length == 5 || line[5].isspace())) {
                    diagram.title = line.substring(5).strip();
                    continue;
                }
                if (line.has_prefix("accTitle") || line.has_prefix("accDescr")) {
                    if (line.contains("{") && !line.contains("}")) {
                        while (i + 1 < lines.length && !lines[i].contains("}")) i++;
                    }
                    continue;
                }

                if (!tokenize(line)) {
                    add_error("Unterminated string");
                    continue;
                }
                if (toks.size == 0) continue;
                pos = 0;
                string keyword = toks[0];
                pos = 1;
                switch (keyword) {
                    case "commit":      parse_commit(); break;
                    case "branch":      parse_branch(); break;
                    case "checkout":
                    case "switch":      parse_checkout(); break;
                    case "merge":       parse_merge(); break;
                    case "cherry-pick": parse_cherry_pick(); break;
                    default:
                        add_error("Unexpected statement '%s'".printf(keyword));
                        break;
                }
            }

            if (!seen_header) add_error("Expected 'gitGraph'");
            return diagram;
        }

        // ---- options (front matter / %%{init}%%) ----

        private void apply_options(string text, ref string? main_name) {
            bool b;
            if (find_bool(text, "showBranches", out b)) diagram.show_branches = b;
            if (find_bool(text, "showCommitLabel", out b)) diagram.show_commit_label = b;
            if (find_bool(text, "rotateCommitLabel", out b)) diagram.rotate_commit_label = b;
            if (find_bool(text, "parallelCommits", out b)) diagram.parallel_commits = b;
            try {
                var re = new Regex("[\"']?mainBranchName[\"']?\\s*:\\s*[\"']([^\"']+)[\"']");
                MatchInfo m;
                if (re.match(text, 0, out m)) main_name = m.fetch(1);
                var re2 = new Regex("^\\s*mainBranchName\\s*:\\s*([\\w./-]+)\\s*$", RegexCompileFlags.MULTILINE);
                if (main_name == null && re2.match(text, 0, out m)) main_name = m.fetch(1);
            } catch (RegexError e) {
                warning("gitGraph option regex: %s", e.message);
            }
        }

        private static bool find_bool(string text, string key, out bool val) {
            val = false;
            try {
                var re = new Regex("[\"']?" + key + "[\"']?\\s*:\\s*[\"']?(true|false)");
                MatchInfo m;
                if (re.match(text, 0, out m)) {
                    val = m.fetch(1) == "true";
                    return true;
                }
            } catch (RegexError e) {
                warning("gitGraph option regex: %s", e.message);
            }
            return false;
        }

        private static string unquote(string s) {
            if (s.length >= 2 && ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                                  (s.has_prefix("'") && s.has_suffix("'")))) {
                return s.substring(1, s.length - 2);
            }
            return s;
        }

        // ---- tokens ----

        // Strings (quotes removed, escapes resolved), "key:" keywords and
        // REFERENCE / word tokens
        private bool tokenize(string line) {
            toks = new Gee.ArrayList<string>();
            quoted = new Gee.ArrayList<bool>();
            int i = 0;
            while (i < line.length) {
                char c = line[i];
                if (c.isspace()) { i++; continue; }
                if (c == '"' || c == '\'') {
                    var sb = new StringBuilder();
                    int j = i + 1;
                    bool closed = false;
                    while (j < line.length) {
                        if (line[j] == '\\' && j + 1 < line.length) {
                            sb.append_c(line[j + 1]);
                            j += 2;
                            continue;
                        }
                        if (line[j] == c) { closed = true; break; }
                        sb.append_c(line[j]);
                        j++;
                    }
                    if (!closed) return false;
                    toks.add(sb.str);
                    quoted.add(true);
                    i = j + 1;
                    continue;
                }
                if (c == ':') {
                    // "key :" — attach to the previous word
                    if (toks.size > 0 && !quoted[toks.size - 1] && !toks[toks.size - 1].has_suffix(":")) {
                        toks[toks.size - 1] = toks[toks.size - 1] + ":";
                    } else {
                        toks.add(":");
                        quoted.add(false);
                    }
                    i++;
                    continue;
                }
                int j = i;
                while (j < line.length && !line[j].isspace() && line[j] != '"' && line[j] != '\'' &&
                       line[j] != ':') j++;
                if (j < line.length && line[j] == ':') j++;   // keyword like "id:"
                toks.add(line.substring(i, j - i));
                quoted.add(false);
                i = j;
            }
            return true;
        }

        private bool at_end() {
            return pos >= toks.size;
        }

        // A branch name: REFERENCE or STRING
        private string? take_name() {
            if (at_end()) return null;
            string t = toks[pos];
            if (!quoted[pos] && t.has_suffix(":")) return null;
            pos++;
            return t;
        }

        private string? take_value() {
            if (at_end()) return null;
            return toks[pos++];
        }

        private void add_error(string message) {
            diagram.errors.add(new ParseError(message, line_no, 1));
        }

        private string auto_id() {
            // Mermaid uses seq + '-' + a random 7-character id; keep it stable
            uint h = (uint) (seq + 1) * 2654435761U;
            return "%d-%07x".printf(seq, h & 0xFFFFFFF);
        }

        private GitGraphCommitType? parse_type(string? v) {
            switch (v) {
                case "NORMAL": return GitGraphCommitType.NORMAL;
                case "REVERSE": return GitGraphCommitType.REVERSE;
                case "HIGHLIGHT": return GitGraphCommitType.HIGHLIGHT;
            }
            return null;
        }

        private GitGraphCommit add_commit(string id, int line) {
            var commit = new GitGraphCommit(id, current_branch_name, diagram.all_commits.size, line);
            commit.parent_id = branch_heads.get(current_branch_name);
            var branch = diagram.get_or_create_branch(current_branch_name);
            branch.add_commit(commit);
            diagram.all_commits.add(commit);
            commits.set(id, commit);
            branch_heads.set(current_branch_name, id);
            seq++;
            return commit;
        }

        // ---- statements ----

        private void parse_commit() {
            string? id = null, msg = null;
            var tags = new Gee.ArrayList<string>();
            GitGraphCommitType type = GitGraphCommitType.NORMAL;
            while (!at_end()) {
                bool q = quoted[pos];
                string t = toks[pos++];
                if (q) { msg = t; continue; }
                switch (t) {
                    case "id:": id = take_value(); break;
                    case "msg:": msg = take_value(); break;
                    case "tag:": { string? v = take_value(); if (v != null) tags.add(v); break; }
                    case "type:": {
                        var ty = parse_type(take_value());
                        if (ty == null) { add_error("Invalid commit type"); return; }
                        type = ty;
                        break;
                    }
                    default:
                        add_error("Unexpected '%s' in commit".printf(t));
                        return;
                }
            }
            var commit = add_commit(id != null && id.length > 0 ? id : auto_id(), line_no);
            commit.commit_type = type;
            commit.message = msg;
            commit.tags.add_all(tags);
            if (tags.size > 0) commit.tag = tags[0];
        }

        private void parse_branch() {
            string? name = take_name();
            if (name == null || name.length == 0) {
                add_error("Expected a branch name");
                return;
            }
            int order = 0;
            while (!at_end()) {
                string t = toks[pos++];
                if (t == "order:") {
                    string? v = take_value();
                    order = v != null ? int.parse(v) : 0;
                } else {
                    add_error("Unexpected '%s' in branch".printf(t));
                    return;
                }
            }
            if (branch_heads.has_key(name)) {
                add_error("Trying to create an existing branch. (Help: Either use a new name if you want create a new branch or try using \"checkout %s\")".printf(name));
                return;
            }
            var branch = diagram.get_or_create_branch(name);
            branch.order = order;
            branch.branched_from_branch = current_branch_name;
            branch.branched_from_commit = branch_heads.get(current_branch_name);
            branch_heads.set(name, branch_heads.get(current_branch_name));
            current_branch_name = name;
        }

        private void parse_checkout() {
            string? name = take_name();
            if (name == null || name.length == 0) {
                add_error("Expected a branch name");
                return;
            }
            if (!branch_heads.has_key(name)) {
                add_error("Trying to checkout branch which is not yet created. (Help try using \"branch %s\")".printf(name));
                return;
            }
            current_branch_name = name;
        }

        private void parse_merge() {
            string? other = take_name();
            if (other == null || other.length == 0) {
                add_error("Expected a branch name to merge");
                return;
            }
            string? custom_id = null;
            var tags = new Gee.ArrayList<string>();
            GitGraphCommitType? override_type = null;
            while (!at_end()) {
                string t = toks[pos++];
                switch (t) {
                    case "id:": custom_id = take_value(); break;
                    case "tag:": { string? v = take_value(); if (v != null) tags.add(v); break; }
                    case "type:":
                        override_type = parse_type(take_value());
                        if (override_type == null) { add_error("Invalid commit type"); return; }
                        break;
                    default:
                        add_error("Unexpected '%s' in merge".printf(t));
                        return;
                }
            }

            string? current_head = branch_heads.get(current_branch_name);
            string? other_head = branch_heads.has_key(other) ? branch_heads.get(other) : null;
            var current_commit = current_head != null ? commits.get(current_head) : null;
            var other_commit = other_head != null ? commits.get(other_head) : null;
            if (current_commit != null && other_commit != null && current_commit.branch_name == other) {
                add_error("Cannot merge branch '%s' into itself.".printf(other));
                return;
            }
            if (current_branch_name == other) {
                add_error("Incorrect usage of \"merge\". Cannot merge a branch to itself");
                return;
            }
            if (current_commit == null) {
                add_error("Incorrect usage of \"merge\". Current branch (%s)has no commits".printf(current_branch_name));
                return;
            }
            if (!branch_heads.has_key(other)) {
                add_error("Incorrect usage of \"merge\". Branch to be merged (%s) does not exist".printf(other));
                return;
            }
            if (other_commit == null) {
                add_error("Incorrect usage of \"merge\". Branch to be merged (%s) has no commits".printf(other));
                return;
            }
            if (current_commit == other_commit) {
                add_error("Incorrect usage of \"merge\". Both branches have same head");
                return;
            }
            if (custom_id != null && custom_id.length > 0 && commits.has_key(custom_id)) {
                add_error("Incorrect usage of \"merge\". Commit with id:%s already exists, use different custom id".printf(custom_id));
                return;
            }

            bool has_id = custom_id != null && custom_id.length > 0;
            var commit = add_commit(has_id ? custom_id : auto_id(), line_no);
            commit.is_merge = true;
            commit.custom_id = has_id;
            commit.merge_from_id = other_head;
            commit.message = "merged branch %s into %s".printf(other, current_branch_name);
            if (override_type != null) {
                commit.commit_type = override_type;
                commit.has_custom_type = true;
            }
            commit.tags.add_all(tags);
            if (tags.size > 0) commit.tag = tags[0];
        }

        private void parse_cherry_pick() {
            string? source_id = null, parent = null;
            var tags = new Gee.ArrayList<string>();
            while (!at_end()) {
                string t = toks[pos++];
                switch (t) {
                    case "id:": source_id = take_value(); break;
                    case "tag:": { string? v = take_value(); if (v != null) tags.add(v); break; }
                    case "parent:": parent = take_value(); break;
                    default:
                        add_error("Unexpected '%s' in cherry-pick".printf(t));
                        return;
                }
            }
            if (source_id == null || !commits.has_key(source_id)) {
                add_error("Incorrect usage of \"cherryPick\". Source commit id should exist and provided");
                return;
            }
            var source = commits.get(source_id);
            if (parent != null && parent.length > 0 &&
                source.parent_id != parent && source.merge_from_id != parent) {
                add_error("Invalid operation: The specified parent commit is not an immediate parent of the cherry-picked commit.");
                return;
            }
            if (source.is_merge && (parent == null || parent.length == 0)) {
                add_error("Incorrect usage of cherry-pick: If the source commit is a merge commit, an immediate parent commit must be specified.");
                return;
            }
            if (source.branch_name == current_branch_name) {
                add_error("Incorrect usage of \"cherryPick\". Source commit is already on current branch");
                return;
            }
            if (branch_heads.get(current_branch_name) == null) {
                add_error("Incorrect usage of \"cherry-pick\". Current branch (%s)has no commits".printf(current_branch_name));
                return;
            }

            var commit = add_commit(auto_id(), line_no);
            commit.is_cherry_pick = true;
            commit.merge_from_id = source.id;
            commit.message = "cherry-picked %s into %s".printf(source.id, current_branch_name);
            // tag: "" entries are dropped; no tags at all → the default label
            var kept = new Gee.ArrayList<string>();
            foreach (string tg in tags) if (tg.length > 0) kept.add(tg);
            if (tags.size == 0) {
                kept.add("cherry-pick:%s%s".printf(source.id,
                    source.is_merge ? "|parent:%s".printf(parent) : ""));
            }
            commit.tags.add_all(kept);
            if (kept.size > 0) commit.tag = kept[0];
        }
    }
}
