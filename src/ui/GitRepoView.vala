namespace GDiagram {
    // Tab widget: shows git commit/branch graph for a repository directory.
    // Layout: toolbar | outer_paned(top: h-paned(sidebar + PreviewPane), bottom: detail panel)
    public class GitRepoView : Gtk.Box {
        public GitRepoGraph repo_graph { get; private set; }

        private GraphvizRenderer base_renderer;
        private MermaidGitGraphRenderer git_renderer;
        private Gee.ArrayList<ElementRegion> regions;
        private PreviewPane preview_pane;
        private Debouncer refresh_debouncer;
        private FileMonitor? git_monitor;
        private Gee.HashSet<string> visible_branches;
        private string[] all_branch_names;

        private Gtk.Label path_label;
        private Gtk.ListBox branch_list;
        private Gtk.SearchEntry branch_search;
        private Gee.ArrayList<Gtk.CheckButton> branch_checks;

        private Gtk.Paned outer_paned;
        private Gtk.Label detail_label;
        private bool detail_shown = false;

        public GitRepoView(string dir) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            repo_graph = new GitRepoGraph(dir);
            base_renderer = new GraphvizRenderer();
            regions = new Gee.ArrayList<ElementRegion>();
            git_renderer = new MermaidGitGraphRenderer(
                base_renderer.get_context(), regions, "dot");
            refresh_debouncer = new Debouncer(1000);
            visible_branches = new Gee.HashSet<string>();
            branch_checks = new Gee.ArrayList<Gtk.CheckButton>();

            build_ui();

            if (repo_graph.repo_root != null) {
                path_label.label = repo_graph.repo_root;
                all_branch_names = repo_graph.get_all_branches();
                foreach (var bn in all_branch_names) {
                    visible_branches.add(bn);
                }
                populate_branch_sidebar();
                setup_file_monitor();
                Idle.add(() => { refresh(); return false; });
            } else {
                path_label.label = "Not a git repository";
                preview_pane.set_placeholder_text("Not a git repository");
            }
        }

        private void build_ui() {
            // ── Toolbar ──────────────────────────────────────────────────────────
            var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            toolbar.margin_start = 8;
            toolbar.margin_end = 8;
            toolbar.margin_top = 6;
            toolbar.margin_bottom = 6;

            var folder_icon = new Gtk.Image.from_icon_name("folder-symbolic");
            toolbar.append(folder_icon);

            path_label = new Gtk.Label("");
            path_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            path_label.hexpand = true;
            path_label.halign = Gtk.Align.START;
            path_label.add_css_class("dim-label");
            toolbar.append(path_label);

            var refresh_btn = new Gtk.Button();
            refresh_btn.icon_name = "view-refresh-symbolic";
            refresh_btn.tooltip_text = "Refresh (F5)";
            refresh_btn.add_css_class("flat");
            refresh_btn.clicked.connect(() => refresh());
            toolbar.append(refresh_btn);

            this.append(toolbar);
            this.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

            // ── Main paned: sidebar (start) + PreviewPane (end) ──────────────────
            var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            paned.hexpand = true;
            paned.vexpand = true;
            paned.position = 200;

            // Branch sidebar
            var sidebar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            sidebar_box.margin_start = 4;
            sidebar_box.margin_end = 4;
            sidebar_box.margin_top = 4;
            sidebar_box.margin_bottom = 4;
            sidebar_box.width_request = 180;

            branch_search = new Gtk.SearchEntry();
            branch_search.placeholder_text = "Filter branches…";
            sidebar_box.append(branch_search);

            var branch_scroll = new Gtk.ScrolledWindow();
            branch_scroll.vexpand = true;
            branch_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;

            branch_list = new Gtk.ListBox();
            branch_list.selection_mode = Gtk.SelectionMode.NONE;
            branch_list.add_css_class("navigation-sidebar");
            branch_scroll.child = branch_list;
            sidebar_box.append(branch_scroll);

            // All / None buttons
            var btn_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            var all_btn = new Gtk.Button.with_label("All");
            all_btn.hexpand = true;
            all_btn.add_css_class("flat");
            all_btn.clicked.connect(on_select_all_branches);
            var none_btn = new Gtk.Button.with_label("None");
            none_btn.hexpand = true;
            none_btn.add_css_class("flat");
            none_btn.clicked.connect(on_select_no_branches);
            btn_row.append(all_btn);
            btn_row.append(none_btn);
            sidebar_box.append(btn_row);

            paned.start_child = sidebar_box;
            paned.shrink_start_child = false;

            // Preview pane
            preview_pane = new PreviewPane();
            preview_pane.hexpand = true;
            preview_pane.vexpand = true;
            preview_pane.set_placeholder_text("Loading…");
            preview_pane.element_clicked.connect(on_commit_clicked);
            paned.end_child = preview_pane;
            paned.shrink_end_child = false;

            // ── Outer vertical paned: top=diagram paned, bottom=detail panel ────
            // detail panel starts hidden (position clamped to full height)
            outer_paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
            outer_paned.hexpand = true;
            outer_paned.vexpand = true;
            outer_paned.wide_handle = true;
            outer_paned.start_child = paned;
            outer_paned.shrink_start_child = false;
            // position=99999 is clamped by GTK to the actual height → detail hidden
            outer_paned.position = 99999;

            // ── Detail panel ────────────────────────────────────────────────────
            var detail_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            var detail_header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            detail_header.margin_start = 8;
            detail_header.margin_end = 8;
            detail_header.margin_top = 4;
            detail_header.margin_bottom = 4;

            var detail_title = new Gtk.Label("Commit Details");
            detail_title.add_css_class("heading");
            detail_title.halign = Gtk.Align.START;
            detail_title.hexpand = true;
            detail_header.append(detail_title);

            var close_btn = new Gtk.Button();
            close_btn.icon_name = "window-close-symbolic";
            close_btn.add_css_class("flat");
            close_btn.tooltip_text = "Close";
            close_btn.clicked.connect(() => {
                outer_paned.position = 99999;
                detail_shown = false;
            });
            detail_header.append(close_btn);

            detail_box.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
            detail_box.append(detail_header);

            var detail_scroll = new Gtk.ScrolledWindow();
            detail_scroll.vexpand = true;
            detail_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;

            detail_label = new Gtk.Label("");
            detail_label.halign = Gtk.Align.START;
            detail_label.valign = Gtk.Align.START;
            detail_label.wrap = true;
            detail_label.selectable = true;
            detail_label.margin_start = 8;
            detail_label.margin_end = 8;
            detail_label.margin_top = 4;
            detail_label.margin_bottom = 8;
            detail_label.add_css_class("monospace");
            detail_scroll.child = detail_label;
            detail_box.append(detail_scroll);

            outer_paned.end_child = detail_box;
            outer_paned.shrink_end_child = true;

            this.append(outer_paned);

            // ── Branch search filter ─────────────────────────────────────────────
            branch_search.search_changed.connect(() => {
                branch_list.invalidate_filter();
            });
            branch_list.set_filter_func((row) => {
                string q = branch_search.text.down().strip();
                if (q.length == 0) return true;
                var check = row.child as Gtk.CheckButton;
                if (check == null) return true;
                return check.label != null && check.label.down().contains(q);
            });
        }

        private void populate_branch_sidebar() {
            // Remove all existing rows
            Gtk.Widget? child = branch_list.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                branch_list.remove(child);
                child = next;
            }
            branch_checks.clear();

            foreach (var bn in all_branch_names) {
                var row = new Gtk.ListBoxRow();
                row.activatable = false;
                row.selectable = false;

                var check = new Gtk.CheckButton.with_label(bn);
                check.active = visible_branches.contains(bn);
                check.margin_start = 4;
                check.margin_end = 4;
                check.margin_top = 2;
                check.margin_bottom = 2;

                check.toggled.connect(() => {
                    if (check.label == null) return;
                    if (check.active) {
                        visible_branches.add(check.label);
                    } else {
                        visible_branches.remove(check.label);
                    }
                    refresh_debouncer.call(() => refresh());
                });

                row.child = check;
                branch_list.append(row);
                branch_checks.add(check);
            }
        }

        private void on_select_all_branches() {
            visible_branches.clear();
            foreach (var bn in all_branch_names) {
                visible_branches.add(bn);
            }
            foreach (var check in branch_checks) {
                check.active = true;
            }
            refresh_debouncer.call(() => refresh());
        }

        private void on_select_no_branches() {
            visible_branches.clear();
            foreach (var check in branch_checks) {
                check.active = false;
            }
            refresh_debouncer.call(() => refresh());
        }

        private void refresh() {
            if (repo_graph.repo_root == null) return;

            if (visible_branches.size == 0) {
                preview_pane.set_placeholder_text("No branches selected");
                return;
            }

            var diagram = repo_graph.load(visible_branches);
            if (diagram == null) {
                preview_pane.set_placeholder_text("No commits to display");
                return;
            }

            regions.clear();
            preview_pane.clear_regions();

            var surface = git_renderer.render_to_surface(diagram);
            if (surface == null) {
                preview_pane.show_error();
                return;
            }

            preview_pane.set_surface(surface);
            foreach (var r in regions) {
                preview_pane.add_region(r.name, r.source_line, r.x, r.y, r.width, r.height);
            }
        }

        private void on_commit_clicked(string element_name, int source_line) {
            // element_name is the DOT node id: "n_<short_hash>"
            // Strip the "n_" prefix to recover the short hash
            string short_hash = (element_name.length > 2 && element_name.has_prefix("n_"))
                ? element_name.substring(2)
                : element_name;

            string? details = repo_graph.get_commit_details(short_hash);
            if (details == null || details.strip().length == 0) {
                details = "Could not load commit details for %s".printf(short_hash);
            }

            detail_label.label = details.strip();
            // Only set the split position on first open; subsequent clicks just
            // update the label so any user resize is preserved.
            if (!detail_shown) {
                int h = outer_paned.get_height();
                outer_paned.position = (h > 300) ? (h * 7 / 10) : (h > 0 ? h - 150 : 500);
                detail_shown = true;
            }
        }

        private void setup_file_monitor() {
            if (repo_graph.repo_root == null) return;
            string git_dir = Path.build_filename(repo_graph.repo_root, ".git");
            try {
                var f = File.new_for_path(Path.build_filename(git_dir, "HEAD"));
                git_monitor = f.monitor_file(FileMonitorFlags.NONE, null);
                git_monitor.changed.connect((file, other_file, event) => {
                    if (event == FileMonitorEvent.CHANGED ||
                        event == FileMonitorEvent.CREATED) {
                        refresh_debouncer.call(() => refresh());
                    }
                });
            } catch (Error e) {
                warning("FileMonitor: %s", e.message);
            }
        }
    }
}
