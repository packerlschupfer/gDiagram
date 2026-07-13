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

        public GitGraphCommit(string id, string branch_name, int order, int line = 0) {
            this.id = id;
            this.branch_name = branch_name;
            this.order = order;
            this.source_line = line;
            this.commit_type = GitGraphCommitType.NORMAL;
            this.tag = null;
            this.parent_id = null;
            this.merge_from_id = null;
        }
    }

    public class GitGraphBranch : Object {
        public string name { get; set; }
        public Gee.ArrayList<GitGraphCommit> commits { get; private set; }
        public string? branched_from_branch { get; set; }
        public string? branched_from_commit { get; set; }

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
