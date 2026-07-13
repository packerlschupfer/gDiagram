namespace GDiagram {
    public class GitBlameEntry : Object {
        public string hash;
        public string short_hash;
        public string author;
        public string date_str;
        public string summary;
    }

    /**
     * Owns all git-related editor gutter logic for a DocumentView: the diff
     * marks against HEAD, the blame gutter, and the per-file dirty check.
     *
     * DocumentView keeps the toolbar toggle buttons themselves and delegates
     * their actions here. The controller holds the caches (blame + HEAD diff
     * content) and invalidates them via invalidate_caches() when the active
     * file changes.
     */
    public class GitGutterController : Object {
        private GtkSource.View source_view;
        private GtkSource.Buffer source_buffer;
        private Document document;

        // Git diff marks
        private Debouncer diff_debouncer;
        private string diff_head_content = "";
        private string diff_head_file_path = "";

        // Git blame gutter
        private GtkSource.GutterRendererText? blame_renderer = null;
        private Gee.HashMap<uint, string>? blame_line_text = null;
        private Gee.HashMap<uint, GitBlameEntry>? blame_entries = null;
        private string blame_loaded_for = "";

        public GitGutterController(GtkSource.View view, GtkSource.Buffer buffer, Document document) {
            this.source_view = view;
            this.source_buffer = buffer;
            this.document = document;

            diff_debouncer = new Debouncer(800);

            setup_diff_mark_attributes();
            setup_blame_gutter();
        }

        // ==================== Public entry points ====================

        // Delegated from DocumentView's blame toggle button.
        public void set_blame_active(bool active) {
            if (blame_renderer == null) return;
            if (active) {
                load_blame_if_needed();
                blame_renderer.visible = true;
            } else {
                blame_renderer.visible = false;
            }
        }

        // Delegated from DocumentView's diff-marks toggle button.
        public void set_diff_marks_active(bool active) {
            if (active) schedule_diff_refresh();
            else clear_diff_marks();
        }

        // Called from DocumentView's source_buffer.changed handler when the
        // diff-marks toggle is active.
        public void schedule_diff_refresh() {
            diff_debouncer.call(() => refresh_diff_marks());
        }

        // Invalidate git caches when the active file changes, then re-check
        // the dirty state. Wired to document.notify["file"].
        public void invalidate_caches() {
            blame_loaded_for = "";
            blame_line_text = null;
            blame_entries = null;
            diff_head_file_path = "";
            diff_head_content = "";
            Idle.add(() => { refresh_git_dirty(); return false; });
        }

        // ==================== Git: Tab Dirty ====================

        public void refresh_git_dirty() {
            if (document.file == null) { document.git_dirty = false; return; }
            string path = document.file.get_path();
            string dir  = Path.get_dirname(path);
            string? out_str = null;
            int status = 0;
            try {
                string[] argv = {"git", "-C", dir, "diff", "--name-only", "HEAD", "--", path};
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out out_str, null, out status);
            } catch {}
            document.git_dirty = (status == 0 && out_str != null && out_str.strip().length > 0);
        }

        // ==================== Git: Diff Marks ====================

        private void setup_diff_mark_attributes() {
            var added_attrs = new GtkSource.MarkAttributes();
            added_attrs.background = Gdk.RGBA() { red = 0.1f, green = 0.75f, blue = 0.1f, alpha = 0.25f };
            source_view.set_mark_attributes("git-diff-added", added_attrs, 10);

            var changed_attrs = new GtkSource.MarkAttributes();
            changed_attrs.background = Gdk.RGBA() { red = 0.9f, green = 0.6f, blue = 0.0f, alpha = 0.25f };
            source_view.set_mark_attributes("git-diff-changed", changed_attrs, 10);

            var removed_attrs = new GtkSource.MarkAttributes();
            removed_attrs.icon_name = "list-remove-symbolic";
            source_view.set_mark_attributes("git-diff-removed", removed_attrs, 10);

            source_view.show_line_marks = true;
        }

        private void refresh_diff_marks() {
            if (document.file == null) return;
            string path = document.file.get_path();
            string dir  = Path.get_dirname(path);

            if (diff_head_file_path != path) {
                string? repo_root = git_util_repo_root(dir);
                if (repo_root == null) { clear_diff_marks(); return; }
                string? rel = git_util_rel_path(repo_root, path);
                if (rel == null) { clear_diff_marks(); return; }
                string? head = git_util_show_head(repo_root, rel);
                if (head == null) { clear_diff_marks(); return; }
                diff_head_content = head;
                diff_head_file_path = path;
            }

            string tmp_old = Path.build_filename(Environment.get_tmp_dir(), "_gdiagram_diff_old.puml");
            string tmp_new = Path.build_filename(Environment.get_tmp_dir(), "_gdiagram_diff_new.puml");
            try {
                FileUtils.set_contents(tmp_old, diff_head_content);
                FileUtils.set_contents(tmp_new, source_buffer.text);
                string? diff_out = null;
                int status = 0;
                Process.spawn_sync(null, {"diff", "--unified=0", tmp_old, tmp_new}, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out diff_out, null, out status);
                clear_diff_marks();
                if (diff_out != null && diff_out.length > 0)
                    apply_diff_marks(diff_out);
            } catch (Error e) {
                warning("diff failed: %s", e.message);
            }
        }

        private void apply_diff_marks(string diff_out) {
            Regex hunk_re;
            try { hunk_re = new Regex("^@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@"); }
            catch { return; }

            foreach (string line in diff_out.split("\n")) {
                MatchInfo m;
                if (!hunk_re.match(line, 0, out m)) continue;

                int old_count = (m.fetch(2) != null && m.fetch(2).length > 0) ? int.parse(m.fetch(2)) : 1;
                int new_start = int.parse(m.fetch(3));
                int new_count = (m.fetch(4) != null && m.fetch(4).length > 0) ? int.parse(m.fetch(4)) : 1;

                string category;
                if (old_count == 0)      category = "git-diff-added";
                else if (new_count == 0) category = "git-diff-removed";
                else                     category = "git-diff-changed";

                if (category == "git-diff-removed") {
                    int mark_line = int.max(0, new_start - 2);
                    Gtk.TextIter iter;
                    source_buffer.get_iter_at_line(out iter, mark_line);
                    source_buffer.create_source_mark(null, category, iter);
                } else {
                    for (int i = 0; i < new_count; i++) {
                        int mark_line = new_start - 1 + i;
                        if (mark_line >= source_buffer.get_line_count()) break;
                        Gtk.TextIter iter;
                        source_buffer.get_iter_at_line(out iter, mark_line);
                        source_buffer.create_source_mark(null, category, iter);
                    }
                }
            }
        }

        private void clear_diff_marks() {
            Gtk.TextIter start, end;
            source_buffer.get_bounds(out start, out end);
            source_buffer.remove_source_marks(start, end, "git-diff-added");
            source_buffer.remove_source_marks(start, end, "git-diff-changed");
            source_buffer.remove_source_marks(start, end, "git-diff-removed");
        }

        // ==================== Git Utilities ====================

        private string? git_util_repo_root(string dir) {
            string? out_str = null; int status = 0;
            try {
                Process.spawn_sync(null, {"git", "-C", dir, "rev-parse", "--show-toplevel"}, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL, null, out out_str, null, out status);
                if (status != 0 || out_str == null) return null;
                return out_str.strip();
            } catch { return null; }
        }

        private string? git_util_rel_path(string root, string abs_path) {
            // Prefix match alone is unsafe: root="/home/user/repo" would
            // accept "/home/user/reposome/file" as being inside it.
            // Require a path separator right after root's end.
            if (!abs_path.has_prefix(root)) return null;
            if (abs_path.length == root.length) return null;
            char after = abs_path[root.length];
            if (after != '/') return null;
            string rel = abs_path.substring(root.length);
            while (rel.has_prefix("/")) rel = rel.substring(1);
            return rel.length > 0 ? rel : null;
        }

        private string? git_util_show_head(string root, string rel) {
            string? out_str = null; int status = 0;
            try {
                Process.spawn_sync(null, {"git", "-C", root, "show", "HEAD:%s".printf(rel)}, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL, null, out out_str, null, out status);
                if (status != 0 || out_str == null) return null;
                return out_str;
            } catch { return null; }
        }

        // ==================== Git: Blame Gutter ====================

        private void setup_blame_gutter() {
            blame_renderer = new GtkSource.GutterRendererText();
            blame_renderer.xpad = 4;
            blame_renderer.visible = false;

            blame_renderer.query_data.connect((lines_obj, line) => {
                if (blame_line_text != null && blame_line_text.has_key(line))
                    blame_renderer.set_text(blame_line_text[line], -1);
                else
                    blame_renderer.set_text("        ", -1);
            });

            blame_renderer.query_activatable.connect((iter, area) => {
                return blame_entries != null && blame_entries.has_key((uint)iter.get_line());
            });

            blame_renderer.activate.connect((iter, area, button, state, n_presses) => {
                uint line_num = (uint)iter.get_line();
                if (blame_entries != null && blame_entries.has_key(line_num))
                    show_blame_popover(blame_entries[line_num], area);
            });

            var gutter = source_view.get_gutter(Gtk.TextWindowType.LEFT);
            gutter.insert(blame_renderer, 200);
        }

        private void load_blame_if_needed() {
            if (document.file == null) return;
            string path = document.file.get_path();
            if (path == blame_loaded_for && blame_line_text != null) return;

            string? out_str = null;
            int status = 0;
            try {
                Process.spawn_sync(null, {"git", "blame", "--porcelain", path}, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out out_str, null, out status);
            } catch {}
            if (status != 0 || out_str == null) return;

            parse_blame_output(out_str);
            blame_loaded_for = path;
            update_blame_gutter_width();
        }

        // GutterRendererText does not size itself to its content — without
        // an explicit width the column collapses to roughly one character.
        // Measure the widest blame string and request that width. Lines from
        // the same commit share identical text, so measure each distinct
        // string once (a Pango layout per measurement) instead of per line.
        private void update_blame_gutter_width() {
            if (blame_line_text == null) return;
            var seen = new Gee.HashSet<string>();
            int max_width = 0;
            foreach (var text in blame_line_text.values) {
                if (!seen.add(text)) continue;
                int w, h;
                blame_renderer.measure(text, out w, out h);
                if (w > max_width) max_width = w;
            }
            if (max_width > 0) {
                blame_renderer.width_request = max_width + 2 * (int) blame_renderer.xpad;
            }
        }

        // Hex and digit checks used by parse_blame_output to validate the
        // porcelain header fields before trusting them.
        private static bool is_all_hex(string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                bool ok = (c >= '0' && c <= '9')
                    || (c >= 'a' && c <= 'f')
                    || (c >= 'A' && c <= 'F');
                if (!ok) return false;
            }
            return true;
        }

        private static bool is_all_digit(string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                if (s[i] < '0' || s[i] > '9') return false;
            }
            return true;
        }

        private void parse_blame_output(string output) {
            blame_line_text = new Gee.HashMap<uint, string>();
            blame_entries   = new Gee.HashMap<uint, GitBlameEntry>();

            var entry_map = new Gee.HashMap<string, GitBlameEntry>();
            uint current_final_line = 0;
            string current_hash = "";

            foreach (string raw_line in output.split("\n")) {
                if (raw_line.length == 0) continue;

                if (raw_line[0] == '\t') {
                    // Guard: current_final_line > 0 avoids uint underflow
                    // when uint.parse returned 0 on a malformed header.
                    if (current_hash.length > 0 && current_final_line > 0) {
                        GitBlameEntry? e = entry_map[current_hash];
                        if (e != null) {
                            blame_line_text[current_final_line - 1] =
                                "%s %s".printf(e.short_hash, e.author);
                            blame_entries[current_final_line - 1] = e;
                        }
                    }
                    continue;
                }

                string[] parts = raw_line.split(" ");
                // Porcelain header: "<hash> <orig-line> <final-line> [<num-lines>]"
                // Accept SHA1 (40 hex), SHA256 (64 hex), or any 7+ hex prefix
                // for future-proofing. The second field (orig_line) and third
                // field (final_line) must both be purely numeric.
                if (parts.length >= 3
                    && parts[0].length >= 7
                    && is_all_hex(parts[0])
                    && is_all_digit(parts[1])
                    && is_all_digit(parts[2])) {
                    current_hash = parts[0];
                    current_final_line = uint.parse(parts[2]);
                    if (!entry_map.has_key(current_hash)) {
                        var e = new GitBlameEntry();
                        e.hash = current_hash;
                        // substring bound clamped: short hashes from
                        // abbreviated output still produce something valid.
                        int prefix_len = int.min(7, current_hash.length);
                        e.short_hash = current_hash.substring(0, prefix_len);
                        entry_map[current_hash] = e;
                    }
                    continue;
                }

                if (raw_line.has_prefix("author ") && !raw_line.has_prefix("author-")) {
                    if (entry_map.has_key(current_hash))
                        entry_map[current_hash].author = raw_line.substring(7);
                } else if (raw_line.has_prefix("author-time ")) {
                    if (entry_map.has_key(current_hash)) {
                        int64 ts = int64.parse(raw_line.substring(12));
                        var dt = new DateTime.from_unix_utc(ts).to_local();
                        entry_map[current_hash].date_str = dt.format("%Y-%m-%d");
                    }
                } else if (raw_line.has_prefix("summary ")) {
                    if (entry_map.has_key(current_hash))
                        entry_map[current_hash].summary = raw_line.substring(8);
                }
            }
        }

        private void show_blame_popover(GitBlameEntry entry, Gdk.Rectangle cell_area) {
            var popover = new Gtk.Popover();
            // Anchor to the clicked gutter cell, not the view's default
            // (bottom-center) position.
            popover.set_parent(blame_renderer);
            popover.pointing_to = cell_area;
            popover.position = Gtk.PositionType.RIGHT;
            popover.closed.connect(() => {
                Idle.add(() => { popover.unparent(); return false; });
            });

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 10;

            var hash_lbl = new Gtk.Label(entry.hash);
            hash_lbl.add_css_class("monospace");
            hash_lbl.xalign = 0;
            box.append(hash_lbl);

            var meta_lbl = new Gtk.Label("%s — %s".printf(entry.author, entry.date_str));
            meta_lbl.xalign = 0;
            box.append(meta_lbl);

            if (entry.summary != null && entry.summary.length > 0) {
                var summ_lbl = new Gtk.Label(entry.summary);
                summ_lbl.xalign = 0;
                summ_lbl.wrap = true;
                summ_lbl.max_width_chars = 40;
                box.append(summ_lbl);
            }

            popover.child = box;
            popover.popup();
        }
    }
}
