namespace GDiagram {

    // ==================== MERMAID GIT GRAPH ====================

    public enum GitGraphCommitType {
        NORMAL,
        REVERSE,
        HIGHLIGHT
    }

    public class GitGraphCommit : Object {
        public string id { get; set; }
        public GitGraphCommitType commit_type { get; set; }
        public string? tag { get; set; }
        public string branch_name { get; set; }
        public int order { get; set; }
        public int source_line { get; set; }
        public string? parent_id { get; set; }      // sequential parent on same/parent branch
        public string? merge_from_id { get; set; }  // HEAD of merged branch (if merge commit)

        // Mermaid details: all tags (tag holds the first), the message, and
        // whether this is a merge / cherry-pick commit. A merge keeps its
        // commit_type as the symbol override ("merge x type: HIGHLIGHT").
        public Gee.ArrayList<string> tags { get; private set; }
        public string? message { get; set; default = null; }
        public bool is_merge { get; set; default = false; }
        public bool is_cherry_pick { get; set; default = false; }
        public bool has_custom_type { get; set; default = false; }
        public bool custom_id { get; set; default = true; }

        public GitGraphCommit(string id, string branch_name, int order, int line = 0) {
            this.id = id;
            this.branch_name = branch_name;
            this.order = order;
            this.source_line = line;
            this.commit_type = GitGraphCommitType.NORMAL;
            this.tag = null;
            this.parent_id = null;
            this.merge_from_id = null;
            this.tags = new Gee.ArrayList<string>();
        }
    }

    public class GitGraphBranch : Object {
        public string name { get; set; }
        public Gee.ArrayList<GitGraphCommit> commits { get; private set; }
        public string? branched_from_branch { get; set; }
        public string? branched_from_commit { get; set; }
        // "branch x order: N" (Mermaid sorts lanes by it, default 0)
        public int order { get; set; default = 0; }

        public GitGraphBranch(string name) {
            this.name = name;
            this.commits = new Gee.ArrayList<GitGraphCommit>();
            this.branched_from_branch = null;
            this.branched_from_commit = null;
        }

        public void add_commit(GitGraphCommit c) {
            commits.add(c);
        }

        public GitGraphCommit? get_head() {
            if (commits.size == 0) return null;
            return commits.get(commits.size - 1);
        }
    }

    public class MermaidGitGraph : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<GitGraphBranch> branches { get; private set; }
        public Gee.ArrayList<GitGraphCommit> all_commits { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        private Gee.HashMap<string, GitGraphBranch> branch_map;

        // "gitGraph LR:|TB:|BT:" and the gitGraph config options
        public string direction { get; set; default = "LR"; }
        public bool show_branches { get; set; default = true; }
        public bool show_commit_label { get; set; default = true; }
        public bool rotate_commit_label { get; set; default = true; }
        public bool parallel_commits { get; set; default = false; }

        public MermaidGitGraph() {
            this.diagram_type = MermaidDiagramType.GIT_GRAPH;
            this.title = null;
            this.branches = new Gee.ArrayList<GitGraphBranch>();
            this.all_commits = new Gee.ArrayList<GitGraphCommit>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.branch_map = new Gee.HashMap<string, GitGraphBranch>();

            // Create default main branch
            var main_branch = new GitGraphBranch("main");
            branches.add(main_branch);
            branch_map.set("main", main_branch);
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public GitGraphBranch? find_branch(string name) {
            return branch_map.get(name);
        }

        // mainBranchName option: the default branch takes the new name
        public void rename_main_branch(string name) {
            var main_branch = branches.size > 0 ? branches.get(0) : null;
            if (main_branch == null || name.length == 0 || main_branch.name == name) return;
            branch_map.unset(main_branch.name);
            main_branch.name = name;
            branch_map.set(name, main_branch);
        }

        public GitGraphBranch get_or_create_branch(string name) {
            var existing = branch_map.get(name);
            if (existing != null) return existing;

            var branch = new GitGraphBranch(name);
            branches.add(branch);
            branch_map.set(name, branch);
            return branch;
        }
    }

}
