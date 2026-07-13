namespace GDiagram {
    // Data layer: reads real git history and converts to MermaidGitGraph AST
    public class GitRepoGraph : Object {
        public string? repo_root { get; private set; }

        public GitRepoGraph(string dir) {
            repo_root = find_repo_root(dir);
        }

        private string? find_repo_root(string dir) {
            string stdout_str;
            int exit_status;
            try {
                string[] argv = {"git", "-C", dir, "rev-parse", "--show-toplevel"};
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out stdout_str, null, out exit_status);
                if (exit_status == 0)
                    return stdout_str.strip();
            } catch (SpawnError e) {
                // Not a git repo or git not available
            }
            return null;
        }

        // Returns all local + remote branch names
        public string[] get_all_branches() {
            if (repo_root == null) return {};

            string stdout_str;
            int exit_status;
            try {
                string[] argv = {"git", "-C", repo_root, "branch", "-a",
                    "--format=%(refname:short)"};
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out stdout_str, null, out exit_status);
                if (exit_status != 0) return {};
            } catch (SpawnError e) {
                warning("git branch: %s", e.message);
                return {};
            }

            var result = new Gee.ArrayList<string>();
            foreach (var line in stdout_str.split("\n")) {
                string b = line.strip();
                if (b.length > 0)
                    result.add(b);
            }
            return result.to_array();
        }

        // Builds MermaidGitGraph from live repo.
        // visible_branches: set of branch names to include; if non-empty only those branches shown.
        // Max 200 commits. Returns null if not a git repo or no commits to show.
        public MermaidGitGraph? load(Gee.HashSet<string> visible_branches) {
            if (repo_root == null) return null;
            if (visible_branches.size == 0) return null;

            string stdout_str;
            int exit_status;
            try {
                string[] argv = {
                    "git", "-C", repo_root, "log",
                    "--all",
                    "--pretty=format:%H|%P|%D|%s|%an|%ci",
                    "--topo-order",
                    "--max-count=200"
                };
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out stdout_str, null, out exit_status);
                if (exit_status != 0) return null;
            } catch (SpawnError e) {
                warning("git log: %s", e.message);
                return null;
            }

            // --- Parse log output ---
            // hashes list is in topo order, newest first
            var hashes = new Gee.ArrayList<string>();
            var parents_map = new Gee.HashMap<string, Gee.ArrayList<string>>();
            var decs_map = new Gee.HashMap<string, string>();
            var commit_set = new Gee.HashSet<string>();

            foreach (var line in stdout_str.split("\n")) {
                string l = line.strip();
                if (l.length == 0) continue;

                // Safely split on first 3 '|' separators.
                // %H and %P cannot contain '|'; %D may contain ',' but not '|'.
                int idx1 = l.index_of("|");
                if (idx1 < 0) continue;
                int idx2 = l.index_of("|", idx1 + 1);
                if (idx2 < 0) continue;
                int idx3 = l.index_of("|", idx2 + 1);
                if (idx3 < 0) continue;

                string hash = l.substring(0, idx1).strip();
                if (hash.length == 0) continue;

                string parents_str = l.substring(idx1 + 1, idx2 - idx1 - 1).strip();
                string decs = l.substring(idx2 + 1, idx3 - idx2 - 1).strip();

                hashes.add(hash);
                commit_set.add(hash);

                var plist = new Gee.ArrayList<string>();
                if (parents_str.length > 0) {
                    foreach (var p in parents_str.split(" ")) {
                        string ps = p.strip();
                        if (ps.length > 0) plist.add(ps);
                    }
                }
                parents_map.set(hash, plist);
                decs_map.set(hash, decs);
            }

            if (hashes.size == 0) return null;

            // --- Identify branch tips from %D decorations ---
            // decoration examples: "HEAD -> main, origin/main", "tag: v1.0", "dev"
            var branch_tips = new Gee.HashMap<string, string>(); // branch_name -> hash

            for (int i = 0; i < hashes.size; i++) {
                string hash = hashes.get(i);
                string decs = decs_map.get(hash) ?? "";
                if (decs.length == 0) continue;

                foreach (var dec in decs.split(",")) {
                    string d = dec.strip();
                    if (d.has_prefix("HEAD -> ")) {
                        string bn = d.substring(8).strip();
                        if (!branch_tips.has_key(bn))
                            branch_tips.set(bn, hash);
                    } else if (d == "HEAD" || d.has_prefix("tag: ")) {
                        // skip: detached HEAD or tag
                    } else if (d.length > 0) {
                        if (!branch_tips.has_key(d))
                            branch_tips.set(d, hash);
                    }
                }
            }

            // Fallback: if no branch tips found (e.g. bare repo), use newest commit as "main"
            if (branch_tips.size == 0 && hashes.size > 0) {
                branch_tips.set("main", hashes.get(0));
            }

            // --- Sort branch names: main/master first, then alphabetical ---
            var branch_names = new Gee.ArrayList<string>();
            branch_names.add_all(branch_tips.keys);
            branch_names.sort((a, b) => {
                bool a_prio = (a == "main" || a == "master");
                bool b_prio = (b == "main" || b == "master");
                if (a_prio && !b_prio) return -1;
                if (!a_prio && b_prio) return 1;
                return a.collate(b);
            });

            // --- Branch assignment: minimum-distance algorithm ---
            // For each visible branch, walk its full first-parent chain and record
            // the hop-distance from the branch tip to every reachable commit.
            // Each commit is then assigned to the branch that reaches it with the
            // smallest distance. Ties are broken by branch_names sort order
            // (main/master first, then alphabetical), so fast-forward-merged
            // branches don't "steal" commits that properly belong to main.
            var branch_dists = new Gee.HashMap<string, Gee.HashMap<string, int?>>();

            foreach (var bn in branch_names) {
                if (!visible_branches.contains(bn)) continue;
                string? tip_hash = branch_tips.get(bn);
                if (tip_hash == null) continue;

                var dist_map = new Gee.HashMap<string, int?>();
                string? cur = tip_hash;
                int d = 0;
                while (cur != null && cur.length > 0 && commit_set.contains(cur)) {
                    if (dist_map.has_key(cur)) break; // cycle guard
                    dist_map.set(cur, (int?) d);
                    var plist = parents_map.get(cur);
                    if (plist == null || plist.size == 0) break;
                    cur = plist.get(0);
                    d++;
                }
                branch_dists.set(bn, dist_map);
            }

            // Assign each commit to the branch with the smallest first-parent distance
            var commit_branch = new Gee.HashMap<string, string>(); // hash -> branch_name
            foreach (var hash in hashes) {
                int best_dist = int.MAX;
                string? best_bn = null;
                foreach (var bn in branch_names) {
                    if (!visible_branches.contains(bn)) continue;
                    var dist_map = branch_dists.get(bn);
                    if (dist_map == null) continue;
                    int? d = dist_map.get(hash);
                    if (d != null && (int) d < best_dist) {
                        best_dist = (int) d;
                        best_bn = bn;
                    }
                }
                if (best_bn != null) commit_branch.set(hash, best_bn);
            }

            // --- Build order map: hash -> int, oldest commit gets order 0 ---
            int n = hashes.size;
            var order_map = new Gee.HashMap<string, int?>();
            for (int i = 0; i < n; i++) {
                // hashes is newest-first; index i → order (n-1-i) → oldest=0
                order_map.set(hashes.get(i), (int?)(n - 1 - i));
            }

            // --- Short hash lookup ---
            var short_of = new Gee.HashMap<string, string>();
            foreach (var h in hashes) {
                short_of.set(h, h.length >= 7 ? h.substring(0, 7) : h);
            }

            // --- Build the diagram ---
            var diagram = new MermaidGitGraph();

            foreach (var hash in hashes) {
                string? bn = commit_branch.get(hash);
                if (bn == null) continue;
                if (!visible_branches.contains(bn)) continue;

                int order = order_map.get(hash) ?? 0;
                string short_hash = short_of.get(hash) ?? hash;

                var branch = diagram.get_or_create_branch(bn);
                var commit = new GitGraphCommit(short_hash, bn, order, 0);

                // Extract tag from decorations
                string decs = decs_map.get(hash) ?? "";
                foreach (var dec in decs.split(",")) {
                    string d = dec.strip();
                    if (d.has_prefix("tag: ")) {
                        commit.tag = d.substring(5).strip();
                        break;
                    }
                }

                // First-parent link
                var plist = parents_map.get(hash);
                if (plist != null && plist.size > 0) {
                    string pfull = plist.get(0);
                    commit.parent_id = short_of.get(pfull)
                        ?? (pfull.length >= 7 ? pfull.substring(0, 7) : pfull);
                }

                // Merge-from link (second parent)
                if (plist != null && plist.size > 1) {
                    string mfull = plist.get(1);
                    commit.merge_from_id = short_of.get(mfull)
                        ?? (mfull.length >= 7 ? mfull.substring(0, 7) : mfull);
                }

                branch.add_commit(commit);
                diagram.all_commits.add(commit);
            }

            if (diagram.all_commits.size == 0) return null;

            // Sort commits oldest-first within all_commits and within each branch
            diagram.all_commits.sort((a, b) => a.order - b.order);
            foreach (var branch in diagram.branches) {
                branch.commits.sort((a, b) => a.order - b.order);
            }

            return diagram;
        }

        // Returns formatted details for a commit (short hash is enough; git resolves it)
        public string? get_commit_details(string short_hash) {
            if (repo_root == null) return null;

            // Defensive: reject anything that isn't purely hex. Prevents
            // `short_hash` from being interpreted as a git flag (e.g.
            // `--exec` or `-e`) if it somehow contains a leading dash.
            // In normal use the hash comes from our own DOT node ids, but
            // any future caller that passes user input is protected.
            if (short_hash.length == 0 || short_hash.length > 64) return null;
            for (int i = 0; i < short_hash.length; i++) {
                char c = short_hash[i];
                bool is_hex = (c >= '0' && c <= '9')
                    || (c >= 'a' && c <= 'f')
                    || (c >= 'A' && c <= 'F');
                if (!is_hex) return null;
            }

            string stdout_str;
            int exit_status;
            try {
                string[] argv = {
                    "git", "-C", repo_root, "show",
                    "--stat",
                    "--format=hash:   %H%nauthor: %an <%ae>%ndate:   %ci%n%n%B",
                    short_hash
                };
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out stdout_str, null, out exit_status);
                if (exit_status != 0) return null;
            } catch (SpawnError e) {
                warning("git show: %s", e.message);
                return null;
            }

            return stdout_str;
        }
    }
}
