namespace GDiagram {

    public class GitCommit : Object {
        public string hash      { get; set; }
        public string short_hash { get; set; }
        public string date_str  { get; set; }
        public string subject   { get; set; }
        public string author    { get; set; }

        public GitCommit(string hash, string date_str, string subject, string author) {
            this.hash       = hash;
            this.short_hash = hash.length >= 7 ? hash.substring(0, 7) : hash;
            this.date_str   = date_str;
            this.subject    = subject;
            this.author     = author;
        }
    }

    public class GitHistoryDialog : Adw.Dialog {

        public signal void restore_requested(string content);

        // Commit panel
        private Gtk.ListBox   commit_list;
        private Gtk.Label     status_label;

        // Left pane — historical version (read-only)
        private GtkSource.Buffer left_buffer;
        private Gtk.DrawingArea  left_preview;
        private Gtk.Label        left_header_label;

        // Right pane — current version (read-only)
        private GtkSource.Buffer right_buffer;
        private Gtk.DrawingArea  right_preview;

        // Footer
        private Gtk.Label diff_label;
        private Gtk.Button restore_button;
        private Gtk.Button meld_button;

        // Render state
        private Cairo.ImageSurface? left_surface  = null;
        private Cairo.ImageSurface? right_surface = null;
        private GraphvizRenderer    renderer;

        // Data
        private string  file_path;
        private string? repo_root   = null;
        private string? rel_path    = null;
        private string  current_content;
        private Gee.ArrayList<GitCommit> commits;

        // ── Constructor ────────────────────────────────────────────────────────

        public GitHistoryDialog(string file_path, string current_content) {
            Object();
            this.file_path       = file_path;
            this.current_content = current_content;

            // Detect git context
            string dir = Path.get_dirname(file_path);
            repo_root = git_repo_root(dir);
            if (repo_root != null) {
                rel_path = compute_rel_path(repo_root, file_path);
            }

            // Show filename in title
            title = "History: %s".printf(Path.get_basename(file_path));

            // Populate the right (current) pane
            right_buffer.text = current_content;
            right_surface = render_diagram(current_content);

            // Load commit history into the sidebar
            load_history();
        }

        // ── Widget construction ────────────────────────────────────────────────

        construct {
            content_width  = 1140;
            content_height = 700;

            renderer = new GraphvizRenderer();
            commits  = new Gee.ArrayList<GitCommit>();

            var toolbar_view = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            toolbar_view.add_top_bar(header);

            // Outer vertical box: content + footer
            var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            outer.vexpand = true;

            // ── Main horizontal area ──────────────────────────────────────────
            var main_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            main_box.vexpand = true;
            outer.append(main_box);

            // ── Commit sidebar (220 px) ───────────────────────────────────────
            var sidebar = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            sidebar.width_request = 220;
            sidebar.add_css_class("sidebar");

            var sidebar_heading = new Gtk.Label("Commits");
            sidebar_heading.add_css_class("heading");
            sidebar_heading.xalign = 0;
            sidebar_heading.margin_start  = 12;
            sidebar_heading.margin_top    = 10;
            sidebar_heading.margin_bottom = 8;
            sidebar.append(sidebar_heading);

            sidebar.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

            var commit_scroll = new Gtk.ScrolledWindow();
            commit_scroll.vexpand = true;
            commit_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;

            commit_list = new Gtk.ListBox();
            commit_list.add_css_class("navigation-sidebar");
            commit_list.selection_mode = Gtk.SelectionMode.SINGLE;
            commit_list.row_selected.connect(on_commit_selected);
            commit_scroll.child = commit_list;
            sidebar.append(commit_scroll);

            status_label = new Gtk.Label("Loading…");
            status_label.add_css_class("dim-label");
            status_label.xalign = 0;
            status_label.wrap = true;
            status_label.margin_start  = 10;
            status_label.margin_end    = 6;
            status_label.margin_top    = 4;
            status_label.margin_bottom = 6;
            sidebar.append(status_label);

            main_box.append(sidebar);
            main_box.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));

            // ── Two-pane comparison area ──────────────────────────────────────
            var compare_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            compare_box.hexpand = true;
            compare_box.margin_start  = 6;
            compare_box.margin_end    = 6;
            compare_box.margin_top    = 6;
            compare_box.margin_bottom = 6;
            compare_box.homogeneous = true;
            main_box.append(compare_box);

            // Left pane (historical)
            left_header_label = new Gtk.Label("Select a commit ←");
            left_header_label.add_css_class("heading");
            left_header_label.xalign = 0;
            left_header_label.ellipsize = Pango.EllipsizeMode.END;

            left_buffer = new GtkSource.Buffer(null);
            left_preview = new Gtk.DrawingArea();
            left_preview.hexpand = left_preview.vexpand = true;
            left_preview.set_draw_func((a, cr, w, h) => draw_preview(cr, w, h, left_surface));

            compare_box.append(
                build_pane(left_header_label, left_buffer, left_preview, true));

            compare_box.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));

            // Right pane (current)
            var right_heading = new Gtk.Label("Current Version");
            right_heading.add_css_class("heading");
            right_heading.xalign = 0;

            right_buffer = new GtkSource.Buffer(null);
            right_preview = new Gtk.DrawingArea();
            right_preview.hexpand = right_preview.vexpand = true;
            right_preview.set_draw_func((a, cr, w, h) => draw_preview(cr, w, h, right_surface));

            compare_box.append(
                build_pane(right_heading, right_buffer, right_preview, false));

            // ── Footer ────────────────────────────────────────────────────────
            outer.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

            var footer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            footer.add_css_class("toolbar");

            diff_label = new Gtk.Label("Select a commit to compare");
            diff_label.add_css_class("dim-label");
            diff_label.xalign = 0;
            diff_label.hexpand = true;
            diff_label.ellipsize = Pango.EllipsizeMode.END;
            diff_label.margin_start  = 12;
            diff_label.margin_top    = 4;
            diff_label.margin_bottom = 4;
            footer.append(diff_label);

            restore_button = new Gtk.Button.with_label("Restore This Version");
            restore_button.add_css_class("suggested-action");
            restore_button.sensitive = false;
            restore_button.margin_end = 6;
            restore_button.clicked.connect(() => {
                restore_requested(left_buffer.text);
                this.close();
            });
            footer.append(restore_button);

            meld_button = new Gtk.Button.with_label("Open in Meld");
            meld_button.sensitive = meld_available();
            if (!meld_available()) meld_button.tooltip_text = "Meld not installed";
            meld_button.margin_end = 12;
            meld_button.clicked.connect(() => {
                launch_meld(left_buffer.text, current_content, "historical", "current");
            });
            footer.append(meld_button);

            outer.append(footer);

            toolbar_view.content = outer;
            this.child = toolbar_view;
        }

        // Build one editor+preview vertical pane.
        private Gtk.Box build_pane(Gtk.Label heading,
                                   GtkSource.Buffer buf,
                                   Gtk.DrawingArea preview,
                                   bool read_only) {
            var pane = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            pane.hexpand = true;
            pane.append(heading);

            var vpaned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
            vpaned.vexpand = true;
            vpaned.shrink_start_child = false;
            vpaned.shrink_end_child   = false;
            vpaned.position = 180;

            // Source editor
            var src_scroll = new Gtk.ScrolledWindow();
            src_scroll.add_css_class("card");
            src_scroll.min_content_height = 80;

            var view = new GtkSource.View.with_buffer(buf);
            view.monospace       = true;
            view.show_line_numbers = true;
            view.editable        = !read_only;
            view.top_margin      = 4;
            view.bottom_margin   = 4;
            view.left_margin     = 4;
            apply_source_style(buf);

            src_scroll.child = view;
            vpaned.start_child = src_scroll;

            // Preview
            var prev_scroll = new Gtk.ScrolledWindow();
            prev_scroll.add_css_class("card");
            prev_scroll.vexpand = true;
            prev_scroll.child = preview;
            vpaned.end_child = prev_scroll;

            pane.append(vpaned);
            return pane;
        }

        private void apply_source_style(GtkSource.Buffer buf) {
            var lm = GtkSource.LanguageManager.get_default();
            var lang = lm.get_language("plantuml");
            if (lang != null) buf.language = lang;

            var adw = Adw.StyleManager.get_default();
            string sid = adw.dark ? "Adwaita-dark" : "Adwaita";
            var scheme = GtkSource.StyleSchemeManager.get_default().get_scheme(sid);
            if (scheme != null) buf.style_scheme = scheme;
        }

        // ── Git helpers ────────────────────────────────────────────────────────

        private string? git_repo_root(string dir) {
            string? out_str = null;
            int status = 0;
            try {
                string[] argv = {"git", "-C", dir, "rev-parse", "--show-toplevel"};
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out out_str, null, out status);
                if (status != 0 || out_str == null) return null;
                return out_str.strip();
            } catch (Error e) { return null; }
        }

        private string? compute_rel_path(string root, string abs) {
            // Prefix match alone is unsafe: if root="/home/user/repo" and
            // abs="/home/user/reposome/file.puml", has_prefix returns true
            // and we'd treat an unrelated file as being inside the repo.
            // Require abs to equal root exactly or have a path separator
            // right after root's end.
            if (!abs.has_prefix(root)) return null;
            if (abs.length == root.length) return null;  // abs == root → no file
            char after = abs[root.length];
            if (after != '/') return null;

            string rel = abs.substring(root.length);
            while (rel.has_prefix("/")) rel = rel.substring(1);
            return rel.length > 0 ? rel : null;
        }

        private static bool meld_available() {
            return Environment.find_program_in_path("meld") != null;
        }

        private void launch_meld(string content_a, string content_b, string label_a, string label_b) {
            string path_a = Path.build_filename(Environment.get_tmp_dir(), "gdiagram_%s.puml".printf(label_a));
            string path_b = Path.build_filename(Environment.get_tmp_dir(), "gdiagram_%s.puml".printf(label_b));
            try {
                FileUtils.set_contents(path_a, content_a);
                FileUtils.set_contents(path_b, content_b);
                Process.spawn_async(null, {"meld", path_a, path_b}, null,
                    SpawnFlags.SEARCH_PATH, null, null);
            } catch (Error e) {
                warning("Failed to launch meld: %s", e.message);
            }
        }

        private Gee.ArrayList<GitCommit> fetch_history() {
            var list = new Gee.ArrayList<GitCommit>();
            if (repo_root == null || rel_path == null) return list;
            string? out_str = null;
            int status = 0;
            try {
                string[] argv = {
                    "git", "-C", repo_root,
                    "log", "--format=%H|%ai|%s|%an", "--follow", "--", rel_path
                };
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out out_str, null, out status);
                if (status != 0 || out_str == null) return list;

                foreach (string line in out_str.split("\n")) {
                    string l = line.strip();
                    if (l.length == 0) continue;
                    string[] parts = l.split("|", 4);
                    if (parts.length < 3) continue;
                    string hash    = parts[0].strip();
                    string date    = parts[1].strip();
                    if (date.length > 16) date = date.substring(0, 16);
                    string subject = parts[2].strip();
                    string author  = parts.length >= 4 ? parts[3].strip() : "";
                    list.add(new GitCommit(hash, date, subject, author));
                }
            } catch (Error e) { /* ignore */ }
            return list;
        }

        private string? get_file_at_commit(string commit_hash) {
            if (repo_root == null || rel_path == null) return null;

            // Defensive: only accept a purely-hex commit hash so a
            // maliciously-crafted value can't be interpreted as a git flag
            // (e.g. `-e`, `--help`). In normal use the hash comes from
            // our own `git log --format=%H` output, but defense in depth.
            if (commit_hash.length == 0 || commit_hash.length > 64) return null;
            for (int i = 0; i < commit_hash.length; i++) {
                char c = commit_hash[i];
                bool is_hex = (c >= '0' && c <= '9')
                    || (c >= 'a' && c <= 'f')
                    || (c >= 'A' && c <= 'F');
                if (!is_hex) return null;
            }

            string? out_str = null;
            int status = 0;
            try {
                string[] argv = {
                    "git", "-C", repo_root,
                    "show", "%s:%s".printf(commit_hash, rel_path)
                };
                Process.spawn_sync(null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, out out_str, null, out status);
                if (status != 0 || out_str == null) return null;
                return out_str;
            } catch (Error e) { return null; }
        }

        // ── UI population ──────────────────────────────────────────────────────

        private void load_history() {
            // Clear existing rows
            var row = commit_list.get_row_at_index(0);
            while (row != null) {
                commit_list.remove(row);
                row = commit_list.get_row_at_index(0);
            }

            if (repo_root == null) {
                status_label.label = "Not a git repository";
                return;
            }
            if (rel_path == null) {
                status_label.label = "Cannot determine file path";
                return;
            }

            commits = fetch_history();

            if (commits.size == 0) {
                status_label.label = "No history found\n(file may be untracked)";
                return;
            }

            status_label.label = "%d commit(s)".printf(commits.size);

            foreach (var c in commits) {
                commit_list.append(build_commit_row(c));
            }

            // Auto-select most recent commit
            var first = commit_list.get_row_at_index(0);
            if (first != null) {
                commit_list.select_row(first);
            }
        }

        private Gtk.ListBoxRow build_commit_row(GitCommit c) {
            var row = new Gtk.ListBoxRow();
            row.set_data<string>("hash", c.hash);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            box.margin_start  = 10;
            box.margin_end    = 8;
            box.margin_top    = 6;
            box.margin_bottom = 6;

            // hash + date
            var meta = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            var hash_lbl = new Gtk.Label(c.short_hash);
            hash_lbl.add_css_class("monospace");
            hash_lbl.add_css_class("accent");
            hash_lbl.xalign = 0;
            meta.append(hash_lbl);

            var date_lbl = new Gtk.Label(c.date_str);
            date_lbl.add_css_class("dim-label");
            date_lbl.add_css_class("caption");
            date_lbl.hexpand = true;
            date_lbl.xalign = 0;
            meta.append(date_lbl);
            box.append(meta);

            // Subject
            var subj = new Gtk.Label(c.subject);
            subj.xalign = 0;
            subj.ellipsize = Pango.EllipsizeMode.END;
            subj.max_width_chars = 26;
            box.append(subj);

            // Author (dimmed)
            if (c.author.length > 0) {
                var auth = new Gtk.Label(c.author);
                auth.add_css_class("dim-label");
                auth.add_css_class("caption");
                auth.xalign = 0;
                auth.ellipsize = Pango.EllipsizeMode.END;
                auth.max_width_chars = 26;
                box.append(auth);
            }

            row.child = box;
            return row;
        }

        // ── Event handlers ─────────────────────────────────────────────────────

        private void on_commit_selected(Gtk.ListBoxRow? row) {
            if (row == null) return;
            string? hash = row.get_data<string>("hash");
            if (hash == null || hash.length == 0) return;

            // Find commit metadata
            GitCommit? selected = null;
            foreach (var c in commits) {
                if (c.hash == hash) { selected = c; break; }
            }

            string? hist = get_file_at_commit(hash);
            if (hist == null) {
                left_header_label.label = "Could not retrieve commit";
                left_buffer.text = "";
                left_surface = null;
                left_preview.queue_draw();
                diff_label.label = "Failed to load version %s".printf(hash.substring(0, 7));
                restore_button.sensitive = false;
                meld_button.sensitive = false;
                return;
            }

            // Update left pane
            if (selected != null) {
                left_header_label.label = "%s  •  %s  —  %s".printf(
                    selected.short_hash, selected.date_str, selected.subject);
            }
            left_buffer.text = hist;
            left_surface = render_diagram(hist);
            restore_button.sensitive = true;
            meld_button.sensitive = meld_available();
            left_preview.queue_draw();

            // Diff summary
            update_diff_summary(hist, current_content);
        }

        private void update_diff_summary(string old_src, string new_src) {
            string[] old_lines = old_src.split("\n");
            string[] new_lines = new_src.split("\n");

            var old_set = new Gee.HashSet<string>();
            var new_set = new Gee.HashSet<string>();
            foreach (string l in old_lines) {
                string t = l.strip();
                if (t.length > 0) old_set.add(t);
            }
            foreach (string l in new_lines) {
                string t = l.strip();
                if (t.length > 0) new_set.add(t);
            }

            int added = 0, removed = 0;
            foreach (string l in new_set) { if (!old_set.contains(l)) added++; }
            foreach (string l in old_set) { if (!new_set.contains(l)) removed++; }

            if (added == 0 && removed == 0) {
                diff_label.label = "No differences — content is identical to current version";
            } else {
                diff_label.label =
                    "Lines: %d → %d  |  +%d new line(s)  −%d removed line(s)".printf(
                        old_lines.length, new_lines.length, added, removed);
            }
        }

        // ── Rendering ─────────────────────────────────────────────────────────

        private void draw_preview(Cairo.Context cr, int w, int h, Cairo.ImageSurface? surface) {
            cr.set_source_rgb(1, 1, 1);
            cr.rectangle(0, 0, w, h);
            cr.fill();

            if (surface == null) {
                cr.set_source_rgb(0.55, 0.55, 0.55);
                cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
                cr.set_font_size(12);
                string msg = "No preview";
                Cairo.TextExtents te;
                cr.text_extents(msg, out te);
                cr.move_to(w / 2.0 - te.width / 2.0, h / 2.0 + te.height / 2.0);
                cr.show_text(msg);
                return;
            }

            int iw = surface.get_width();
            int ih = surface.get_height();
            if (iw <= 0 || ih <= 0) return;

            double scale = double.min((double)w / iw, (double)h / ih) * 0.95;
            double ox = (w - iw * scale) / 2.0;
            double oy = (h - ih * scale) / 2.0;

            cr.translate(ox, oy);
            cr.scale(scale, scale);
            cr.set_source_surface(surface, 0, 0);
            cr.paint();
        }

        private Cairo.ImageSurface? render_diagram(string source) {
            string lower = source.strip().down();
            unowned Gvc.Context gvc = renderer.get_context();
            var regions = new Gee.ArrayList<ElementRegion>();

            // ── Mermaid ────────────────────────────────────────────────────────
            if (lower.has_prefix("flowchart") || lower.has_prefix("graph ")) {
                var d = new MermaidFlowchartParser().parse(source);
                if (!d.has_errors())
                    return new MermaidFlowchartRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("sequencediagram")) {
                var d = new MermaidSequenceParser().parse(source);
                if (!d.has_errors())
                    return new MermaidSequenceRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("statediagram")) {
                var d = new MermaidStateParser().parse(source);
                if (!d.has_errors())
                    return new MermaidStateRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("classdiagram")) {
                var d = new MermaidClassParser().parse(source);
                if (!d.has_errors())
                    return new MermaidClassRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("erdiagram")) {
                var d = new MermaidERParser().parse(source);
                if (!d.has_errors())
                    return new MermaidERRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("gantt")) {
                var d = new MermaidGanttParser().parse(source);
                if (!d.has_errors())
                    return new MermaidGanttRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("pie")) {
                var d = new MermaidPieParser().parse(source);
                if (!d.has_errors())
                    return new MermaidPieRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("journey")) {
                var d = new MermaidUserJourneyParser().parse(source);
                if (!d.has_errors())
                    return new MermaidUserJourneyRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("gitgraph")) {
                var d = new MermaidGitGraphParser().parse(source);
                if (!d.has_errors())
                    return new MermaidGitGraphRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("mindmap")) {
                var d = new MermaidMindmapParser().parse(source);
                if (!d.has_errors())
                    return new MermaidMindmapRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("timeline")) {
                var d = new MermaidTimelineParser().parse(source);
                if (!d.has_errors())
                    return new MermaidTimelineRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("quadrantchart")) {
                var d = new MermaidQuadrantParser().parse(source);
                if (!d.has_errors())
                    return new MermaidQuadrantRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("xychart-beta") || lower.has_prefix("xychart")) {
                var d = new MermaidXYChartParser().parse(source);
                if (!d.has_errors())
                    return new MermaidXYChartRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("kanban")) {
                var d = new MermaidKanbanParser().parse(source);
                if (!d.has_errors())
                    return new MermaidKanbanRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("sankey-beta") || lower.has_prefix("sankey")) {
                var d = new MermaidSankeyParser().parse(source);
                if (!d.has_errors())
                    return new MermaidSankeyRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("requirementdiagram") || lower.has_prefix("requirement")) {
                var d = new MermaidRequirementParser().parse(source);
                if (!d.has_errors())
                    return new MermaidRequirementRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("block-beta") || lower.has_prefix("block")) {
                var d = new MermaidBlockParser().parse(source);
                if (!d.has_errors())
                    return new MermaidBlockRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("packet-beta") || lower.has_prefix("packet")) {
                var d = new MermaidPacketParser().parse(source);
                if (!d.has_errors())
                    return new MermaidPacketRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("c4context") || lower.has_prefix("c4container") ||
                lower.has_prefix("c4component") || lower.has_prefix("c4dynamic") ||
                lower.has_prefix("c4deployment")) {
                var d = new MermaidC4Parser().parse(source);
                if (!d.has_errors())
                    return renderer.render_mermaid_c4_to_surface(d);
            }
            if (lower.has_prefix("architecture-beta") || lower.has_prefix("architecture")) {
                var d = new MermaidArchitectureParser().parse(source);
                if (!d.has_errors())
                    return renderer.render_mermaid_architecture_to_surface(d);
            }
            if (lower.has_prefix("zenuml")) {
                var d = new MermaidZenUMLParser().parse(source);
                if (!d.has_errors())
                    return renderer.render_mermaid_zenuml_to_surface(d);
            }
            if (lower.has_prefix("radar-beta") || lower.has_prefix("radar")) {
                var d = new MermaidRadarParser().parse(source);
                if (!d.has_errors())
                    return renderer.render_mermaid_radar_to_surface(d);
            }
            if (lower.has_prefix("treemap-beta") || lower.has_prefix("treemap")) {
                var d = new MermaidTreemapParser().parse(source);
                if (!d.has_errors())
                    return renderer.render_mermaid_treemap_to_surface(d);
            }

            // ── PlantUML (default) ─────────────────────────────────────────────
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            if (lower.contains("class ") || lower.contains("interface ") || lower.contains("--|>")) {
                var diagram = new ClassDiagramParser().parse(tokens);
                if (!diagram.has_errors())
                    return renderer.render_class_to_surface(diagram);
            }

            // Fall through to sequence diagram
            var preprocessor = new Preprocessor();
            string processed = preprocessor.process(source, null);
            var parser = new Parser();
            var diagram = parser.parse(processed);
            return renderer.render_to_surface(diagram);
        }
    }
}
