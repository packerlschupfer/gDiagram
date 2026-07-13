namespace GDiagram {
    // NOTE: This file generates some expected C-level warnings:
    // - "cast between incompatible function types" warnings are from Vala's signal
    //   handler code generation when using lambda functions. This is standard Vala
    //   behavior and not a bug. Common in all Vala/GTK projects.
    // - Any other C-level warnings (unused parameters, etc.) are from Vala's
    //   conservative code generation and GObject boilerplate. Safe to ignore.
    public class DocumentView : Gtk.Box {
        public Document document { get; construct; }

        private GtkSource.View source_view;
        private GtkSource.Buffer source_buffer;
        private PreviewPane preview_pane;
        private Debouncer render_debouncer;
        private DiagramEngine engine;
        private DiagramType current_diagram_type;
        private DiagramFormat current_diagram_format;

        // Search/Replace
        private Gtk.Revealer search_revealer;
        private Gtk.SearchEntry search_entry;
        private Gtk.Entry replace_entry;
        private Gtk.Label search_status_label;
        private GtkSource.SearchContext search_context;
        private GtkSource.SearchSettings search_settings;

        // Settings
        private GLib.Settings app_settings;

        // Error highlighting
        private Gtk.TextTag error_tag;
        private Gee.ArrayList<ParseError> current_errors;

        // Outline view
        private Gtk.ListBox outline_list;
        private Gtk.Revealer outline_revealer;
        private Gtk.Paned left_paned;
        private int saved_outline_position = 150;
        private Gtk.Label outline_stats_label;
        private Gtk.Button lint_button;
        private Gtk.Button validate_button;
        private Gtk.Button complexity_button;

        // Linter
        private DiagramLinter diagram_linter;

        // Validator
        private DiagramValidator diagram_validator;

        // Complexity / optimizer
        private ComplexityAnalyzer complexity_analyzer;
        private DiagramOptimizer diagram_optimizer;
        private ComplexityMetrics? last_complexity_metrics = null;
        private bool last_has_optimizer = false;

        // Performance monitor
        private PerformanceMonitor perf_monitor;
        private Gtk.Label perf_label;

        // Diagram theme
        private DiagramTheme diagram_theme;
        private Gtk.ToggleButton dark_diagram_toggle;

        // Zoom controls
        private Gtk.Label zoom_label;

        // Diagram search
        private int diagram_search_index = 0;
        private string last_diagram_search = "";

        // Performance: cache to avoid re-rendering unchanged diagrams
        private string last_rendered_source = "";
        private Cairo.ImageSurface? cached_surface = null;

        // Debug: track render calls to detect infinite loops within a single debounce burst
        private int render_call_count = 0;

        // Split view
        private Gtk.Paned main_paned;

        // External change notification
        private Adw.Banner? external_change_banner = null;

        // Font styling
        private Gtk.CssProvider? font_css_provider = null;

        // Git editor gutter (diff marks + blame). Toolbar toggle buttons live
        // here; the actual git logic lives in GitGutterController.
        private GitGutterController git_gutter;
        private Gtk.ToggleButton diff_marks_toggle;
        private Gtk.ToggleButton blame_toggle;

        // Outline sidebar content population.
        private OutlineController outline_controller;

        // Drill-down navigation history. Each entry is a file the user
        // descended FROM to reach the current document. The breadcrumb bar
        // renders this list as clickable items so the user can jump back
        // up the chain. Empty for top-level documents.
        public Gee.ArrayList<File> nav_history { get; private set; }
        private Gtk.Box breadcrumb_box;

        public DocumentView(Document doc) {
            Object(
                document: doc,
                orientation: Gtk.Orientation.HORIZONTAL,
                spacing: 0
            );
        }

        construct {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] DocumentView.construct() starting...\n");

            // Initialize settings
            app_settings = new GLib.Settings(APP_ID);
            if (debug) print("[DEBUG] Settings initialized\n");

            // Re-render when the color palette changes (preset swap, custom
            // override, or follow-system flip). Cache is keyed on source text
            // so we have to clear it manually before scheduling. Gated on
            // schema.has_key so older installed schemas don't abort.
            var app_schema = app_settings.settings_schema;
            if (app_schema.has_key("color-scheme-light"))
                app_settings.changed["color-scheme-light"].connect(on_palette_setting_changed);
            if (app_schema.has_key("color-scheme-dark"))
                app_settings.changed["color-scheme-dark"].connect(on_palette_setting_changed);
            if (app_schema.has_key("color-scheme-follow-system"))
                app_settings.changed["color-scheme-follow-system"].connect(on_palette_setting_changed);
            if (app_schema.has_key("custom-palette-overrides"))
                app_settings.changed["custom-palette-overrides"].connect(on_palette_setting_changed);
            // System theme flip (GNOME light <-> dark) also re-resolves the
            // preset when follow-system is on.
            Adw.StyleManager.get_default().notify["dark"].connect(on_palette_setting_changed);

            render_debouncer = new Debouncer(app_settings.get_int("render-delay"));
            current_errors = new Gee.ArrayList<ParseError>();
            engine = new DiagramEngine(app_settings.get_string("layout-engine"));
            current_diagram_type = DiagramType.SEQUENCE;
            current_diagram_format = DiagramFormat.PLANTUML;

            diagram_linter = new DiagramLinter();
            diagram_validator = new DiagramValidator();
            complexity_analyzer = new ComplexityAnalyzer();
            diagram_optimizer = new DiagramOptimizer();
            perf_monitor = new PerformanceMonitor();
            diagram_theme = ThemeManager.get_system_theme();

            // Listen for layout engine changes
            app_settings.changed["layout-engine"].connect(() => {
                engine.set_layout_engine(app_settings.get_string("layout-engine"));
                schedule_render();
            });

            // Create paned container for editor and preview
            var orientation = app_settings.get_string("split-orientation") == "vertical"
                ? Gtk.Orientation.VERTICAL
                : Gtk.Orientation.HORIZONTAL;
            main_paned = new Gtk.Paned(orientation);
            main_paned.hexpand = true;
            main_paned.vexpand = true;
            main_paned.shrink_start_child = true;
            main_paned.shrink_end_child = true;
            main_paned.resize_start_child = true;
            main_paned.resize_end_child = true;

            // Create a horizontal box for outline + editor
            left_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            left_paned.hexpand = true;
            left_paned.vexpand = true;
            left_paned.shrink_start_child = true;
            left_paned.shrink_end_child = true;

            // Outline sidebar
            setup_outline_view();
            outline_controller = new OutlineController(outline_list);
            // Row click → navigate in source + highlight in preview. The
            // controller extracts the search key from the row; the source
            // buffer and preview pane stay here.
            outline_controller.navigate_to_element.connect((search_key) => {
                search_and_navigate(search_key);
                preview_pane.highlight_element(search_key);
            });
            left_paned.start_child = outline_revealer;

            // Editor side - container for search bar and editor
            var editor_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            // Show outline button (visible when outline is hidden)
            var show_outline_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            show_outline_bar.add_css_class("toolbar");
            show_outline_bar.margin_start = 6;
            show_outline_bar.margin_end = 6;
            show_outline_bar.margin_top = 6;
            show_outline_bar.margin_bottom = 6;

            var show_outline_btn = new Gtk.Button.from_icon_name("sidebar-show-symbolic");
            show_outline_btn.tooltip_text = "Show Outline (Ctrl+\\)";
            show_outline_btn.clicked.connect(() => {
                toggle_outline_visibility();
            });
            show_outline_bar.append(show_outline_btn);

            var show_outline_revealer = new Gtk.Revealer();
            show_outline_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            show_outline_revealer.reveal_child = false;
            show_outline_revealer.child = show_outline_bar;
            editor_box.append(show_outline_revealer);

            // Bind outline visibility to show/hide the toggle button
            outline_revealer.notify["reveal-child"].connect(() => {
                show_outline_revealer.reveal_child = !outline_revealer.reveal_child;
            });

            // Search/Replace bar
            setup_search_bar(editor_box);

            var editor_frame = new Gtk.Frame(null);
            editor_frame.add_css_class("view");
            editor_frame.vexpand = true;

            var scroll = new Gtk.ScrolledWindow();
            scroll.hexpand = true;
            scroll.vexpand = true;

            // Create source buffer and view
            source_buffer = new GtkSource.Buffer(null);
            source_view = new GtkSource.View.with_buffer(source_buffer);

            // Create error tag for highlighting error lines
            error_tag = source_buffer.create_tag("error",
                "underline", Pango.Underline.ERROR,
                "underline-rgba", Gdk.RGBA() { red = 0.9f, green = 0.2f, blue = 0.2f, alpha = 1.0f }
            );
            source_view.monospace = true;
            source_view.auto_indent = true;
            source_view.indent_width = 2;
            source_view.tab_width = 2;
            source_view.insert_spaces_instead_of_tabs = true;
            source_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            source_view.top_margin = 6;
            source_view.bottom_margin = 6;
            source_view.left_margin = 6;
            source_view.right_margin = 6;

            // Add CSS class for targeted styling
            source_view.add_css_class("plantuml-editor");

            // Apply settings
            apply_editor_settings();

            // Listen for settings changes
            app_settings.changed.connect((key) => {
                apply_editor_settings();
            });

            // Set up style scheme
            var style_manager = GtkSource.StyleSchemeManager.get_default();
            var scheme = style_manager.get_scheme("Adwaita-dark");
            if (scheme == null) {
                scheme = style_manager.get_scheme("classic");
            }
            if (scheme != null) {
                source_buffer.style_scheme = scheme;
            }

            // Set up PlantUML syntax highlighting
            setup_language();

            // Set up auto-completion
            setup_completion();

            // Git editor gutter controller: sets up diff-mark attributes,
            // show_line_marks, and the blame gutter renderer on source_view.
            git_gutter = new GitGutterController(source_view, source_buffer, document);

            scroll.child = source_view;
            editor_frame.child = scroll;
            editor_box.append(editor_frame);

            // Add editor to left_paned
            left_paned.end_child = editor_box;
            left_paned.position = 150;

            // Preview side with zoom controls
            preview_pane = new PreviewPane();

            // Connect element click signal for source navigation
            preview_pane.element_clicked.connect(on_element_clicked);
            // Double-click drills into a related file (C4 navigation: click
            // a Container box → opens the file describing that Container's
            // internal Components, etc.)
            preview_pane.element_drilled.connect(on_element_drilled);
            // Right-click on an element shows a contextual menu (drill,
            // go to source, copy alias)
            preview_pane.element_context_menu.connect(on_element_context_menu);

            // Connect zoom signal
            preview_pane.zoom_changed.connect((level) => {
                zoom_label.label = "%.0f%%".printf(level * 100);
            });

            // Create preview box with zoom controls at bottom
            var preview_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            // Drill-down breadcrumb bar — hidden until the user descends
            // into a related file via double-click. Renders nav_history as
            // clickable buttons separated by "›" arrows.
            nav_history = new Gee.ArrayList<File>();
            breadcrumb_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            breadcrumb_box.margin_start = 12;
            breadcrumb_box.margin_end = 12;
            breadcrumb_box.margin_top = 6;
            breadcrumb_box.margin_bottom = 6;
            breadcrumb_box.add_css_class("toolbar");
            breadcrumb_box.add_css_class("gdiagram-breadcrumb");
            breadcrumb_box.visible = false;
            preview_box.append(breadcrumb_box);

            preview_box.append(preview_pane);

            // Zoom control bar
            var zoom_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            zoom_bar.halign = Gtk.Align.CENTER;
            zoom_bar.margin_top = 4;
            zoom_bar.margin_bottom = 4;
            zoom_bar.add_css_class("toolbar");

            var zoom_out_btn = new Gtk.Button.from_icon_name("zoom-out-symbolic");
            zoom_out_btn.tooltip_text = "Zoom Out";
            zoom_out_btn.clicked.connect(() => preview_pane.zoom_out());
            zoom_bar.append(zoom_out_btn);

            zoom_label = new Gtk.Label("100%");
            zoom_label.width_chars = 5;
            zoom_bar.append(zoom_label);

            var zoom_in_btn = new Gtk.Button.from_icon_name("zoom-in-symbolic");
            zoom_in_btn.tooltip_text = "Zoom In";
            zoom_in_btn.clicked.connect(() => preview_pane.zoom_in());
            zoom_bar.append(zoom_in_btn);

            var zoom_fit_btn = new Gtk.Button.from_icon_name("zoom-fit-best-symbolic");
            zoom_fit_btn.tooltip_text = "Zoom to Fit";
            zoom_fit_btn.clicked.connect(() => preview_pane.zoom_fit());
            zoom_bar.append(zoom_fit_btn);

            var zoom_reset_btn = new Gtk.Button.from_icon_name("zoom-original-symbolic");
            zoom_reset_btn.tooltip_text = "Reset Zoom (100%)";
            zoom_reset_btn.clicked.connect(() => preview_pane.zoom_reset());
            zoom_bar.append(zoom_reset_btn);

            // Separator
            var separator = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            separator.margin_start = 8;
            separator.margin_end = 8;
            zoom_bar.append(separator);

            // Diagram search
            var diagram_search = new Gtk.SearchEntry();
            diagram_search.placeholder_text = "Find element...";
            diagram_search.width_chars = 15;
            diagram_search.tooltip_text = "Search for elements in the diagram";
            diagram_search.search_changed.connect(() => {
                string query = diagram_search.text.strip().down();
                if (query.length >= 2) {
                    search_diagram_element(query);
                } else {
                    preview_pane.clear_highlight();
                }
            });
            diagram_search.activate.connect(() => {
                string query = diagram_search.text.strip().down();
                if (query.length >= 2) {
                    search_diagram_element_next(query);
                }
            });
            zoom_bar.append(diagram_search);

            // Split orientation toggle
            var split_separator = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            split_separator.margin_start = 8;
            split_separator.margin_end = 8;
            zoom_bar.append(split_separator);

            var split_toggle = new Gtk.Button();
            split_toggle.icon_name = orientation == Gtk.Orientation.VERTICAL
                ? "view-dual-symbolic"
                : "object-flip-vertical-symbolic";
            split_toggle.tooltip_text = "Toggle Split Orientation";
            split_toggle.clicked.connect(() => {
                toggle_split_orientation(split_toggle);
            });
            zoom_bar.append(split_toggle);

            blame_toggle = new Gtk.ToggleButton();
            blame_toggle.icon_name = "system-users-symbolic";
            blame_toggle.tooltip_text = "Show git blame";
            blame_toggle.add_css_class("flat");
            blame_toggle.toggled.connect(() => git_gutter.set_blame_active(blame_toggle.active));
            zoom_bar.append(blame_toggle);

            diff_marks_toggle = new Gtk.ToggleButton();
            diff_marks_toggle.icon_name = "view-list-compact-symbolic";
            diff_marks_toggle.add_css_class("flat");
            diff_marks_toggle.tooltip_text = "Show diff vs HEAD";
            diff_marks_toggle.toggled.connect(() => git_gutter.set_diff_marks_active(diff_marks_toggle.active));
            zoom_bar.append(diff_marks_toggle);

            preview_box.append(zoom_bar);

            main_paned.start_child = left_paned;
            main_paned.end_child = preview_box;
            main_paned.position = 550;

            this.append(main_paned);

            // Set up keyboard shortcuts
            setup_keyboard_shortcuts();

            // Sync buffer with document
            source_buffer.text = document.content;

            source_buffer.changed.connect(() => {
                document.content = source_buffer.text;
                document.modified = true;
                schedule_render();
                if (diff_marks_toggle.active) {
                    git_gutter.schedule_diff_refresh();
                }
            });

            document.notify["content"].connect(() => {
                if (source_buffer.text != document.content) {
                    source_buffer.text = document.content;
                }
            });

            // Handle external file changes (auto-reload)
            document.external_change.connect(on_external_file_change);

            // Invalidate git caches when the active file changes
            document.notify["file"].connect(() => {
                git_gutter.invalidate_caches();
            });

            // Track cursor position for source-to-diagram highlighting
            source_buffer.notify["cursor-position"].connect(on_cursor_position_changed);

            if (debug) print("[DEBUG] DocumentView construct complete, scheduling initial render...\n");
            // Initial render
            schedule_render();
            if (debug) print("[DEBUG] Initial render scheduled\n");
            if (debug) print("[DEBUG] DocumentView.construct() finished successfully\n");
        }

        private void on_cursor_position_changed() {
            // Get current cursor position
            Gtk.TextIter cursor_iter;
            source_buffer.get_iter_at_mark(out cursor_iter, source_buffer.get_insert());
            int line = cursor_iter.get_line() + 1;

            // Get the word/identifier under the cursor to disambiguate when
            // multiple elements share the same source line (e.g. "A <|-- B").
            string? word = get_word_at_iter(cursor_iter);

            string? element_name = find_element_at_line(line, word);
            if (element_name != null) {
                preview_pane.highlight_element(element_name);
            }
        }

        // Extract the identifier/word surrounding the given iterator.
        private string? get_word_at_iter(Gtk.TextIter iter) {
            var start = iter;
            var end = iter;
            // Walk backward to word start
            while (start.backward_char()) {
                unichar c = start.get_char();
                if (!c.isalnum() && c != '_') {
                    start.forward_char();
                    break;
                }
            }
            // Walk forward to word end
            while (end.forward_char()) {
                unichar c = end.get_char();
                if (!c.isalnum() && c != '_') break;
            }
            string word = start.get_text(end).strip();
            return word.length > 0 ? word : null;
        }

        private string? find_element_at_line(int line, string? hint = null) {
            // If we have a hint (word at cursor), prefer a region whose
            // name matches it — this disambiguates lines like "A <|-- B"
            // where both A and B have source_line pointing to the same line.
            if (hint != null) {
                foreach (var region in engine.last_regions) {
                    if (region.source_line == line && region.name == hint) {
                        return region.name;
                    }
                }
            }
            // Fallback: first region on this line
            foreach (var region in engine.last_regions) {
                if (region.source_line == line) {
                    return region.name;
                }
            }
            return null;
        }

        private void on_external_file_change() {
            // Only auto-reload if not modified, otherwise show notification
            if (document.modified) {
                // Show an info bar or toast that file changed externally
                show_external_change_notification();
            } else {
                // Auto-reload
                reload_from_file.begin();
            }
        }

        private async void reload_from_file() {
            try {
                yield document.reload();
                // Content will be synced via the notify["content"] signal
            } catch (Error e) {
                warning("Failed to reload file: %s", e.message);
            }
        }

        private void show_external_change_notification() {
            // Create banner if it doesn't exist
            if (external_change_banner == null) {
                external_change_banner = new Adw.Banner("File changed on disk.");
                external_change_banner.button_label = "Reload";
                external_change_banner.revealed = false;

                external_change_banner.button_clicked.connect(() => {
                    reload_from_file.begin();
                    external_change_banner.revealed = false;
                });

                // Add banner at the top of the document view
                this.prepend(external_change_banner);
            }

            // Show the banner
            external_change_banner.revealed = true;
        }

        // Called when any of the color-scheme GSettings keys change, or when
        // the libadwaita system dark flag flips. Re-resolves the active
        // palette, clears the cached render, and schedules a fresh render.
        private void on_palette_setting_changed() {
            // Don't override the palette when the user explicitly flipped
            // the dark/light toggle — the toggle has already set the palette.
            if (dark_diagram_toggle.active) {
                return;
            }
            ThemeManager.refresh_from_settings(app_settings);
            last_rendered_source = "";
            cached_surface = null;
            schedule_render();
        }

        private void schedule_render() {
            render_call_count++;
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] schedule_render() called (count: %d)\n", render_call_count);

            if (render_call_count > 100) {
                printerr("[ERROR] Infinite render loop detected! Stopping at %d calls.\n", render_call_count);
                return;
            }

            render_debouncer.call(() => {
                if (debug) print("[DEBUG] Debouncer triggered, calling render_preview()...\n");
                render_call_count = 0;
                render_preview();
            });
        }

        private void set_and_cache_surface(Cairo.ImageSurface? surface, string source) {
            if (surface != null) {
                preview_pane.set_surface(surface);
                cached_surface = surface;
                last_rendered_source = source;
            } else {
                preview_pane.set_placeholder_text("Failed to render diagram");
                cached_surface = null;
            }
        }

        private void apply_editor_settings() {
            // Apply line numbers and highlighting settings
            source_view.show_line_numbers = app_settings.get_boolean("show-line-numbers");
            source_view.highlight_current_line = app_settings.get_boolean("highlight-current-line");

            // Apply font setting
            var font_desc = Pango.FontDescription.from_string(
                app_settings.get_string("editor-font")
            );
            var font_family = font_desc.get_family();
            var font_size = font_desc.get_size() / Pango.SCALE;

            // Create or reuse CSS provider
            if (font_css_provider == null) {
                font_css_provider = new Gtk.CssProvider();
                // INTENTIONAL: This triggers a deprecation warning but is actually correct.
                // StyleContext.add_provider_for_display() is the official GTK4 API for CSS.
                // The warning is a false positive - only instance methods are deprecated, not this static method.
                // Suppress with: valac --disable-warnings (if needed)
                Gtk.StyleContext.add_provider_for_display(
                    Gdk.Display.get_default(),
                    font_css_provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
            }

            // Use specific CSS selector for this editor
            var css = ".plantuml-editor { font-family: %s; font-size: %dpt; }".printf(font_family, font_size);
            font_css_provider.load_from_string(css);

            // Update render delay
            render_debouncer.delay_ms = app_settings.get_int("render-delay");
        }

        // ==================== Outline View ====================

        private void setup_outline_view() {
            outline_revealer = new Gtk.Revealer();
            outline_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT;
            outline_revealer.reveal_child = true;

            var outline_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            outline_box.add_css_class("sidebar");
            outline_box.width_request = 150;

            // Header with toggle button
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            header.add_css_class("toolbar");
            header.margin_start = 6;
            header.margin_end = 6;
            header.margin_top = 6;
            header.margin_bottom = 6;

            var title_label = new Gtk.Label("Outline");
            title_label.add_css_class("heading");
            title_label.xalign = 0;
            title_label.hexpand = true;
            header.append(title_label);

            var hide_btn = new Gtk.Button.from_icon_name("pan-start-symbolic");
            hide_btn.add_css_class("flat");
            hide_btn.tooltip_text = "Hide Outline";
            hide_btn.clicked.connect(() => {
                toggle_outline_visibility();
            });
            header.append(hide_btn);

            outline_box.append(header);

            // List box for elements
            var scroll = new Gtk.ScrolledWindow();
            scroll.vexpand = true;

            outline_list = new Gtk.ListBox();
            outline_list.selection_mode = Gtk.SelectionMode.SINGLE;
            outline_list.activate_on_single_click = true;
            outline_list.add_css_class("navigation-sidebar");

            // Row activation (click-to-source) is wired by OutlineController,
            // which emits navigate_to_element() with the extracted search key.

            scroll.child = outline_list;
            outline_box.append(scroll);

            // Stats footer
            var stats_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            stats_box.add_css_class("toolbar");
            outline_stats_label = new Gtk.Label("");
            outline_stats_label.xalign = 0;
            outline_stats_label.add_css_class("dim-label");
            outline_stats_label.margin_start = 6;
            outline_stats_label.margin_top = 3;
            outline_stats_label.margin_bottom = 3;
            outline_stats_label.ellipsize = Pango.EllipsizeMode.END;
            outline_stats_label.hexpand = true;
            stats_box.append(outline_stats_label);

            lint_button = new Gtk.Button();
            lint_button.icon_name = "emblem-ok-symbolic";
            lint_button.add_css_class("flat");
            lint_button.tooltip_text = "No lint suggestions";
            lint_button.visible = false;
            lint_button.margin_end = 4;
            lint_button.clicked.connect(show_lint_popover);
            stats_box.append(lint_button);

            validate_button = new Gtk.Button();
            validate_button.icon_name = "shield-symbolic";
            validate_button.add_css_class("flat");
            validate_button.tooltip_text = "No validation issues";
            validate_button.visible = false;
            validate_button.margin_end = 4;
            validate_button.clicked.connect(show_validate_popover);
            stats_box.append(validate_button);

            complexity_button = new Gtk.Button();
            complexity_button.icon_name = "view-list-symbolic";
            complexity_button.add_css_class("flat");
            complexity_button.tooltip_text = "Diagram complexity";
            complexity_button.visible = false;
            complexity_button.margin_end = 4;
            complexity_button.clicked.connect(show_complexity_popover);
            stats_box.append(complexity_button);

            perf_label = new Gtk.Label("");
            perf_label.add_css_class("dim-label");
            perf_label.visible = false;
            perf_label.margin_start = 2;
            perf_label.margin_end = 4;
            stats_box.append(perf_label);

            dark_diagram_toggle = new Gtk.ToggleButton();
            dark_diagram_toggle.icon_name = "night-light-symbolic";
            dark_diagram_toggle.add_css_class("flat");
            dark_diagram_toggle.tooltip_text = "Flip diagram theme (opposite of system)";
            dark_diagram_toggle.active = false;
            dark_diagram_toggle.toggled.connect(on_dark_diagram_toggled);
            stats_box.append(dark_diagram_toggle);

            outline_box.append(stats_box);

            outline_revealer.child = outline_box;
        }

        private bool search_and_navigate(string text) {
            // Guard: empty search matches at position 0 and does nothing useful
            // (and GtkTextIter.forward_search warns on empty needle).
            if (text == null || text.length == 0) return false;
            // Search for the text and scroll to it
            Gtk.TextIter start;
            source_buffer.get_start_iter(out start);

            Gtk.TextIter match_start, match_end;
            if (start.forward_search(text, Gtk.TextSearchFlags.CASE_INSENSITIVE,
                                      out match_start, out match_end, null)) {
                source_buffer.select_range(match_start, match_end);
                // Only scroll if the match is not already visible — prevents
                // jarring jumps when clicking through the outline list.
                Gdk.Rectangle visible_rect;
                source_view.get_visible_rect(out visible_rect);
                Gdk.Rectangle iter_rect;
                source_view.get_iter_location(match_start, out iter_rect);
                if (iter_rect.y < visible_rect.y ||
                    iter_rect.y + iter_rect.height > visible_rect.y + visible_rect.height) {
                    source_view.scroll_to_iter(match_start, 0.1, true, 0.5, 0.5);
                }
                return true;
            }
            return false;
        }

        private void navigate_to_line(int line_number) {
            if (line_number < 1) return;

            Gtk.TextIter iter;
            source_buffer.get_iter_at_line(out iter, line_number - 1);

            // Select the entire line
            Gtk.TextIter line_end = iter;
            line_end.forward_to_line_end();

            source_buffer.select_range(iter, line_end);
            source_view.scroll_to_iter(iter, 0.1, true, 0.5, 0.5);
        }

        private void on_element_clicked(string element_name, int source_line) {
            // Search for the element name first so the selection
            // highlights the specific identifier, not the whole line.
            // Relationship lines like "Class01 <|-- Class02" contain both
            // names — navigate_to_line would select from "Class01" which
            // misleads the user into thinking the wrong element was clicked.
            if (search_and_navigate(element_name)) return;

            // Some renderers synthesize DOT node ids that never appear in
            // the source text (sequence lifelines "Foo_top"/"Foo_bottom",
            // message anchors "Foo_m0") — retry with the suffix stripped.
            string base_name = element_name;
            if (base_name.has_suffix("_top")) {
                base_name = base_name.substring(0, base_name.length - 4);
            } else if (base_name.has_suffix("_bottom")) {
                base_name = base_name.substring(0, base_name.length - 7);
            } else {
                int m = base_name.last_index_of("_m");
                if (m > 0 && is_all_digits(base_name.substring(m + 2))) {
                    base_name = base_name.substring(0, m);
                }
            }
            if (base_name != element_name && search_and_navigate(base_name)) return;

            // Last resort: jump to the line the click region reported
            // (0 when the renderer had no mapping — then this is a no-op).
            navigate_to_line(source_line);
        }

        private static bool is_all_digits(string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                if (s[i] < '0' || s[i] > '9') return false;
            }
            return true;
        }

        /**
         * Apply a navigation history list (used by MainWindow when opening
         * a document via drill-down). Stores the chain of parent files and
         * rebuilds the breadcrumb bar.
         */
        public void apply_nav_history(Gee.ArrayList<File> history) {
            nav_history.clear();
            nav_history.add_all(history);
            rebuild_breadcrumbs();
        }

        private void rebuild_breadcrumbs() {
            // Clear existing children
            var child = breadcrumb_box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                breadcrumb_box.remove(child);
                child = next;
            }

            if (nav_history.size == 0) {
                breadcrumb_box.visible = false;
                return;
            }

            // Back button — jumps up one level (to the last entry in history).
            // Also bound to Alt+Left for keyboard navigation.
            var back_btn = new Gtk.Button.from_icon_name("go-previous-symbolic");
            back_btn.tooltip_text = "Go back (Alt+Left)";
            back_btn.add_css_class("flat");
            back_btn.add_css_class("circular");
            back_btn.clicked.connect(() => navigate_breadcrumb_to(nav_history.size - 1));
            breadcrumb_box.append(back_btn);

            var back_sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            back_sep.margin_start = 6;
            back_sep.margin_end = 6;
            breadcrumb_box.append(back_sep);

            // Render each history entry as a button + "›" separator
            for (int i = 0; i < nav_history.size; i++) {
                File hf = nav_history[i];
                string name = hf.get_basename();
                if (name.has_suffix(".puml")) name = name.substring(0, name.length - 5);
                else if (name.has_suffix(".mmd")) name = name.substring(0, name.length - 4);
                else if (name.has_suffix(".ged")) name = name.substring(0, name.length - 4);

                var btn = new Gtk.Button.with_label(name);
                btn.add_css_class("flat");
                btn.tooltip_text = "Go back to %s".printf(name);
                int captured_index = i;
                btn.clicked.connect(() => navigate_breadcrumb_to(captured_index));
                breadcrumb_box.append(btn);

                var sep = new Gtk.Label("›");
                sep.add_css_class("dim-label");
                sep.add_css_class("title-3");
                breadcrumb_box.append(sep);
            }

            // Current document — strong emphasis, not clickable
            string here = document.file != null ? document.file.get_basename() : "(unsaved)";
            if (here.has_suffix(".puml")) here = here.substring(0, here.length - 5);
            else if (here.has_suffix(".mmd")) here = here.substring(0, here.length - 4);
            else if (here.has_suffix(".ged")) here = here.substring(0, here.length - 4);
            var here_label = new Gtk.Label(here);
            here_label.add_css_class("heading");
            here_label.add_css_class("accent");
            here_label.margin_start = 4;
            breadcrumb_box.append(here_label);

            // Push the depth indicator to the right edge for context
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            breadcrumb_box.append(spacer);

            var depth_label = new Gtk.Label(
                "Level %d".printf(nav_history.size + 1));
            depth_label.add_css_class("dim-label");
            depth_label.add_css_class("caption");
            breadcrumb_box.append(depth_label);

            breadcrumb_box.visible = true;
        }

        /**
         * Public entry point for the Alt+Left keyboard shortcut. Goes back
         * one breadcrumb level. No-op if there's no history.
         */
        public void navigate_back() {
            if (nav_history.size == 0) return;
            navigate_breadcrumb_to(nav_history.size - 1);
        }

        private void navigate_breadcrumb_to(int index) {
            if (index < 0 || index >= nav_history.size) return;
            var target = nav_history[index];
            // The target's history is everything BEFORE it in the current chain
            var sub_history = new Gee.ArrayList<File>();
            for (int i = 0; i < index; i++) sub_history.add(nav_history[i]);
            var window = (MainWindow) get_root();
            if (window != null) {
                window.open_file_with_history(target, sub_history);
            }
        }

        /**
         * Right-click context menu on a diagram element. Builds a popover
         * with the actions that make sense for this element:
         *
         *   - Drill into <related-file>     (only if a related file exists)
         *   - Go to source line             (only if source_line > 0)
         *   - Copy element name
         */
        private void on_element_context_menu(string element_name, int source_line, double x, double y) {
            string alias = element_name;
            if (alias.has_prefix("n_")) alias = alias.substring(2);

            var menu = new GLib.Menu();

            // Drill action
            string? drill_target = null;
            if (document != null && document.file != null) {
                var dir = document.file.get_parent();
                if (dir != null) {
                    string current_base = document.file.get_basename();
                    if (current_base.has_suffix(".puml"))
                        current_base = current_base.substring(0, current_base.length - 5);
                    else if (current_base.has_suffix(".mmd"))
                        current_base = current_base.substring(0, current_base.length - 4);
                    drill_target = find_drill_candidate(dir, current_base, alias);
                }
            }
            if (drill_target != null) {
                menu.append("Drill into " + drill_target, "ctxmenu.drill");
            }
            if (source_line > 0) {
                menu.append("Go to source line " + source_line.to_string(), "ctxmenu.gotoline");
            }
            menu.append("Copy element name", "ctxmenu.copy");

            // Build a per-popover action group so the action handlers see
            // the captured element name without leaking through globals.
            var action_group = new GLib.SimpleActionGroup();

            var drill_action = new GLib.SimpleAction("drill", null);
            drill_action.activate.connect(() => on_element_drilled(element_name));
            action_group.add_action(drill_action);

            int captured_line = source_line;
            var goto_action = new GLib.SimpleAction("gotoline", null);
            goto_action.activate.connect(() => navigate_to_line(captured_line));
            action_group.add_action(goto_action);

            string captured_alias = alias;
            var copy_action = new GLib.SimpleAction("copy", null);
            copy_action.activate.connect(() => {
                var clipboard = preview_pane.get_clipboard();
                clipboard.set_text(captured_alias);
            });
            action_group.add_action(copy_action);

            var popover = new Gtk.PopoverMenu.from_model(menu);
            popover.set_parent(preview_pane);
            popover.insert_action_group("ctxmenu", action_group);

            // Position at the click point
            var rect = Gdk.Rectangle();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = 1;
            rect.height = 1;
            popover.set_pointing_to(rect);
            popover.popup();
        }

        /**
         * Drill-down: double-click an element to open the file that describes
         * its internals. Looks for files in the same directory matching the
         * clicked alias, in order of preference:
         *
         *   <alias>.puml
         *   <alias>.mmd
         *   <currentbasename>-<alias>.puml      (e.g. context-web.puml)
         *   <alias>-container.puml
         *   <alias>-component.puml
         *
         * If found, opens it in a new tab. Otherwise shows a brief
         * "no related file found" toast/log so the user knows nothing happened.
         */
        private void on_element_drilled(string element_name) {
            if (document == null || document.file == null) return;
            var dir = document.file.get_parent();
            if (dir == null) return;
            string current_base = document.file.get_basename();
            if (current_base.has_suffix(".puml")) {
                current_base = current_base.substring(0, current_base.length - 5);
            } else if (current_base.has_suffix(".mmd")) {
                current_base = current_base.substring(0, current_base.length - 4);
            }
            // Strip leading "n_" prefix sometimes added by SVG title sanitisation
            string alias = element_name;
            if (alias.has_prefix("n_")) alias = alias.substring(2);

            string? match = find_drill_candidate(dir, current_base, alias);
            if (match != null) {
                var f = dir.resolve_relative_path(match);
                if (f.query_exists(null)) {
                    var window = (MainWindow) get_root();
                    if (window != null) {
                        // Pass our nav_history + the current file forward so
                        // the new tab's breadcrumb shows the chain.
                        var new_history = new Gee.ArrayList<File>();
                        new_history.add_all(nav_history);
                        if (document.file != null) new_history.add(document.file);
                        window.open_file_with_history(f, new_history);
                    }
                    return;
                }
            }
            // Nothing matched. Stay silent — the tooltip already told the
            // user which elements have drill targets, so a missed click is
            // expected behaviour (e.g. on a Person or external system).
        }

        private void transfer_click_regions() {
            preview_pane.clear_regions();
            foreach (var region in engine.last_regions) {
                preview_pane.add_region(
                    region.name,
                    region.source_line,
                    region.x,
                    region.y,
                    region.width,
                    region.height
                );
            }
            // Resolve drill-down targets for each region so the hover
            // tooltip can show "Double-click → other-file.puml" hints.
            update_drill_targets();
        }

        /**
         * For each click region, check whether a related file exists in
         * the same directory and pass the alias → filename map to the
         * preview pane for hover tooltips.
         */
        private void update_drill_targets() {
            var targets = new Gee.HashMap<string, string>();
            if (document == null || document.file == null) {
                preview_pane.set_drill_targets(targets);
                return;
            }
            var dir = document.file.get_parent();
            if (dir == null) {
                preview_pane.set_drill_targets(targets);
                return;
            }
            string current_base = document.file.get_basename();
            if (current_base.has_suffix(".puml")) {
                current_base = current_base.substring(0, current_base.length - 5);
            } else if (current_base.has_suffix(".mmd")) {
                current_base = current_base.substring(0, current_base.length - 4);
            }
            foreach (var region in engine.last_regions) {
                string alias = region.name;
                if (alias.has_prefix("n_")) alias = alias.substring(2);
                if (targets.has_key(alias)) continue;
                string? match = find_drill_candidate(dir, current_base, alias);
                if (match != null) {
                    targets.set(alias, match);
                }
            }
            preview_pane.set_drill_targets(targets);
        }

        /**
         * Find a related file for the given alias by searching the source
         * directory and common subdirectories. Returns the relative path
         * (e.g. "containers/web.puml") or null if no candidate exists.
         *
         * Patterns and subdirectories come from GSettings (configurable
         * in Preferences) so users can customise the resolution. Each
         * pattern is a template with $alias and $base placeholders:
         *
         *   $alias.puml
         *   $base-$alias.puml
         *   containers/$alias.puml      (slashes treated as path components)
         *
         * The first existing file wins. Same logic is used by both
         * on_element_drilled (click handler) and update_drill_targets
         * (hover tooltip) so the tooltip never promises a drill that
         * wouldn't actually open.
         */
        private string? find_drill_candidate(File dir, string current_base, string alias) {
            // GSettings.get_strv on a missing key calls g_error() which is a
            // fatal abort (NOT a catchable Vala exception). Guard with
            // has_key so running against an older installed schema (e.g.
            // /usr/share/glib-2.0/schemas/org.gnome.gDiagram.gschema.xml
            // from a pre-drill-down .deb) falls back to the compiled-in
            // defaults instead of crashing.
            string[] patterns;
            string[] subdirs;
            var schema = app_settings.settings_schema;
            if (schema != null && schema.has_key("drill-down-patterns")) {
                patterns = app_settings.get_strv("drill-down-patterns");
            } else {
                patterns = {
                    "$alias.puml", "$alias.mmd",
                    "$base-$alias.puml", "$base-$alias.mmd",
                    "$alias-container.puml", "$alias-component.puml",
                    "$alias_container.puml", "$alias_component.puml",
                };
            }
            if (schema != null && schema.has_key("drill-down-subdirs")) {
                subdirs = app_settings.get_strv("drill-down-subdirs");
            } else {
                subdirs = { "containers", "components", "c4", "levels", "sub" };
            }

            // Direct hit in the source directory
            foreach (string pattern in patterns) {
                string name = pattern.replace("$alias", alias).replace("$base", current_base);
                var f = dir.resolve_relative_path(name);
                if (f != null && f.query_exists(null)) {
                    return name;
                }
            }
            // Try each configured subdirectory
            foreach (string sub in subdirs) {
                var sub_dir = dir.get_child(sub);
                if (!sub_dir.query_exists(null)) continue;
                foreach (string pattern in patterns) {
                    string name = pattern.replace("$alias", alias).replace("$base", current_base);
                    if (sub_dir.resolve_relative_path(name).query_exists(null)) {
                        return sub + "/" + name;
                    }
                }
            }
            return null;
        }

        private void search_diagram_element(string query) {
            // Search for first matching element
            if (query != last_diagram_search) {
                diagram_search_index = 0;
                last_diagram_search = query;
            }

            // Find matching regions
            var matches = new Gee.ArrayList<string>();
            foreach (var region in engine.last_regions) {
                if (region.name.down().contains(query)) {
                    matches.add(region.name);
                }
            }

            if (matches.size > 0) {
                string element_name = matches.get(diagram_search_index % matches.size);
                preview_pane.highlight_element(element_name);
            } else {
                preview_pane.clear_highlight();
            }
        }

        private void search_diagram_element_next(string query) {
            // Move to next match
            var matches = new Gee.ArrayList<string>();
            foreach (var region in engine.last_regions) {
                if (region.name.down().contains(query)) {
                    matches.add(region.name);
                }
            }

            if (matches.size > 0) {
                diagram_search_index = (diagram_search_index + 1) % matches.size;
                string element_name = matches.get(diagram_search_index);
                preview_pane.highlight_element(element_name);
            }
        }

        private void toggle_split_orientation(Gtk.Button toggle_button) {
            bool is_vertical = main_paned.orientation == Gtk.Orientation.VERTICAL;
            var new_orientation = is_vertical
                ? Gtk.Orientation.HORIZONTAL
                : Gtk.Orientation.VERTICAL;

            main_paned.orientation = new_orientation;

            // Update button icon
            toggle_button.icon_name = new_orientation == Gtk.Orientation.VERTICAL
                ? "view-dual-symbolic"
                : "object-flip-vertical-symbolic";

            // Save to settings
            app_settings.set_string("split-orientation",
                new_orientation == Gtk.Orientation.VERTICAL ? "vertical" : "horizontal");
        }

        private void update_outline_stats(string quick_stats) {
            outline_stats_label.label = quick_stats;
        }

        private void update_lint_state() {
            int count = diagram_linter.messages.size;
            lint_button.visible = true;
            if (count == 0) {
                lint_button.icon_name = "emblem-ok-symbolic";
                lint_button.tooltip_text = "No lint suggestions";
                lint_button.remove_css_class("warning");
            } else {
                lint_button.icon_name = "dialog-warning-symbolic";
                lint_button.tooltip_text = "%d lint suggestion(s) — click for details".printf(count);
                if (!lint_button.has_css_class("warning")) {
                    lint_button.add_css_class("warning");
                }
            }
        }

        private void show_lint_popover() {
            string report = diagram_linter.get_report();

            var popover = new Gtk.Popover();
            popover.set_parent(lint_button);

            var scroll = new Gtk.ScrolledWindow();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.min_content_height = 200;
            scroll.max_content_height = 450;
            scroll.min_content_width = 380;

            var label = new Gtk.Label(report);
            label.xalign = 0;
            label.wrap = true;
            label.selectable = true;
            label.margin_top = 8;
            label.margin_bottom = 8;
            label.margin_start = 8;
            label.margin_end = 8;

            scroll.child = label;
            popover.child = scroll;
            popover.popup();
        }

        private void update_validate_state() {
            int errors   = 0;
            int warnings = 0;
            int infos    = 0;
            foreach (var msg in diagram_validator.messages) {
                switch (msg.severity) {
                    case ValidationMessage.Severity.ERROR:   errors++;   break;
                    case ValidationMessage.Severity.WARNING: warnings++; break;
                    case ValidationMessage.Severity.INFO:    infos++;    break;
                }
            }
            validate_button.visible = true;
            int total = diagram_validator.messages.size;
            if (total == 0) {
                validate_button.icon_name = "shield-symbolic";
                validate_button.tooltip_text = "No validation issues";
                validate_button.remove_css_class("error");
                validate_button.remove_css_class("warning");
            } else if (errors > 0) {
                validate_button.icon_name = "dialog-error-symbolic";
                validate_button.tooltip_text = "%d error(s), %d warning(s) — click for details"
                    .printf(errors, warnings);
                if (!validate_button.has_css_class("error")) validate_button.add_css_class("error");
                validate_button.remove_css_class("warning");
            } else {
                validate_button.icon_name = "dialog-warning-symbolic";
                validate_button.tooltip_text = "%d warning(s), %d suggestion(s) — click for details"
                    .printf(warnings, infos);
                if (!validate_button.has_css_class("warning")) validate_button.add_css_class("warning");
                validate_button.remove_css_class("error");
            }
        }

        private void show_validate_popover() {
            string report = diagram_validator.get_summary();

            var popover = new Gtk.Popover();
            popover.set_parent(validate_button);

            var scroll = new Gtk.ScrolledWindow();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.min_content_height = 200;
            scroll.max_content_height = 450;
            scroll.min_content_width = 380;

            var label = new Gtk.Label(report);
            label.xalign = 0;
            label.wrap = true;
            label.selectable = true;
            label.margin_top = 8;
            label.margin_bottom = 8;
            label.margin_start = 8;
            label.margin_end = 8;

            scroll.child = label;
            popover.child = scroll;
            popover.popup();
        }

        private void on_dark_diagram_toggled() {
            // Determine which palette is currently active, then switch to
            // the opposite. Detect "currently dark" from the active palette's
            // background luminance rather than trusting the system theme
            // detection (which can be wrong under non-standard sessions).
            var current = ThemeManager.get_active_palette();
            bool currently_dark = is_dark_color(current.background);

            if (dark_diagram_toggle.active) {
                // Flip to opposite
                string preset_id;
                if (currently_dark) {
                    preset_id = "default-light";
                    preview_pane.set_dark_override(false);
                } else {
                    preset_id = "default-dark";
                    preview_pane.set_dark_override(true);
                }
                var palette = ThemeManager.get_preset(preset_id);
                ThemeManager.set_active_palette(palette);
            } else {
                // Restore system-matched palette
                preview_pane.set_dark_override(null);
                ThemeManager.refresh_from_settings(app_settings);
            }
            // Clear cache and re-render immediately — no debounce needed
            // since this is a user-initiated toggle, not a keystroke.
            last_rendered_source = "";
            cached_surface = null;
            render_preview();
        }

        // Quick luminance check for a hex color string
        private bool is_dark_color(string color) {
            string c = color.replace("#", "");
            if (c.length < 6) return true;
            int r = parse_hex(c.substring(0, 2));
            int g = parse_hex(c.substring(2, 2));
            int b = parse_hex(c.substring(4, 2));
            return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0 < 0.5;
        }

        private int parse_hex(string s) {
            int v = 0;
            for (int i = 0; i < s.length && i < 2; i++) {
                v <<= 4;
                char ch = s[i];
                if (ch >= '0' && ch <= '9') v += ch - '0';
                else if (ch >= 'a' && ch <= 'f') v += 10 + ch - 'a';
                else if (ch >= 'A' && ch <= 'F') v += 10 + ch - 'A';
            }
            return v;
        }

        private void update_perf_label() {
            perf_label.label = perf_monitor.get_quick_stats();
            perf_label.visible = true;
        }

        private void update_complexity_state(ComplexityMetrics metrics, bool has_optimizer) {
            last_complexity_metrics = metrics;
            last_has_optimizer = has_optimizer;
            complexity_button.visible = true;
            complexity_button.tooltip_text = metrics.get_rating();
        }

        private void show_complexity_popover() {
            if (last_complexity_metrics == null) return;

            var popover = new Gtk.Popover();
            popover.set_parent(complexity_button);

            var scroll = new Gtk.ScrolledWindow();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.min_content_height = 200;
            scroll.max_content_height = 450;
            scroll.min_content_width = 380;

            string report = last_complexity_metrics.get_summary();
            if (last_has_optimizer) {
                report += "\n" + diagram_optimizer.get_report();
            }

            var label = new Gtk.Label(report);
            label.xalign = 0;
            label.wrap = true;
            label.selectable = true;
            label.margin_top = 8;
            label.margin_bottom = 8;
            label.margin_start = 8;
            label.margin_end = 8;

            scroll.child = label;
            popover.child = scroll;
            popover.popup();
        }

        // ==================== Error Highlighting ====================

        private void clear_error_highlights() {
            Gtk.TextIter start, end;
            source_buffer.get_start_iter(out start);
            source_buffer.get_end_iter(out end);
            source_buffer.remove_tag(error_tag, start, end);
            current_errors.clear();
        }

        private void apply_error_highlights(Gee.ArrayList<ParseError> errors) {
            clear_error_highlights();
            current_errors = errors;

            foreach (var error in errors) {
                if (error.line < 1) continue;

                // Get the line bounds
                Gtk.TextIter line_start, line_end;
                source_buffer.get_iter_at_line(out line_start, error.line - 1);
                line_end = line_start.copy();
                line_end.forward_to_line_end();

                // Apply error tag to the line
                source_buffer.apply_tag(error_tag, line_start, line_end);
            }
        }

        // ==================== Search/Replace ====================

        private void setup_search_bar(Gtk.Box parent) {
            search_revealer = new Gtk.Revealer();
            search_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;

            var search_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            search_box.add_css_class("toolbar");
            search_box.margin_start = 6;
            search_box.margin_end = 6;
            search_box.margin_top = 6;
            search_box.margin_bottom = 6;

            // Search entry
            search_entry = new Gtk.SearchEntry();
            search_entry.placeholder_text = "Find...";
            search_entry.hexpand = true;
            search_entry.width_chars = 20;

            // Replace entry
            replace_entry = new Gtk.Entry();
            replace_entry.placeholder_text = "Replace...";
            replace_entry.width_chars = 20;

            // Status label
            search_status_label = new Gtk.Label("");
            search_status_label.add_css_class("dim-label");

            // Buttons
            var prev_btn = new Gtk.Button.from_icon_name("go-up-symbolic");
            prev_btn.tooltip_text = "Previous (Shift+Enter)";
            prev_btn.clicked.connect(find_previous);

            var next_btn = new Gtk.Button.from_icon_name("go-down-symbolic");
            next_btn.tooltip_text = "Next (Enter)";
            next_btn.clicked.connect(find_next);

            var replace_btn = new Gtk.Button.with_label("Replace");
            replace_btn.clicked.connect(replace_current);

            var replace_all_btn = new Gtk.Button.with_label("All");
            replace_all_btn.tooltip_text = "Replace All";
            replace_all_btn.clicked.connect(replace_all);

            var close_btn = new Gtk.Button.from_icon_name("window-close-symbolic");
            close_btn.tooltip_text = "Close (Escape)";
            close_btn.clicked.connect(hide_search);

            // Case sensitive toggle
            var case_btn = new Gtk.ToggleButton();
            case_btn.icon_name = "format-text-uppercase-symbolic";
            case_btn.tooltip_text = "Case Sensitive";
            case_btn.toggled.connect(() => {
                search_settings.case_sensitive = case_btn.active;
            });

            // Regex toggle
            var regex_btn = new Gtk.ToggleButton();
            regex_btn.label = ".*";
            regex_btn.tooltip_text = "Regular Expression";
            regex_btn.toggled.connect(() => {
                search_settings.regex_enabled = regex_btn.active;
            });

            search_box.append(search_entry);
            search_box.append(prev_btn);
            search_box.append(next_btn);
            search_box.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
            search_box.append(replace_entry);
            search_box.append(replace_btn);
            search_box.append(replace_all_btn);
            search_box.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
            search_box.append(case_btn);
            search_box.append(regex_btn);
            search_box.append(search_status_label);
            search_box.append(close_btn);

            search_revealer.child = search_box;
            parent.append(search_revealer);

            // Set up search context
            search_settings = new GtkSource.SearchSettings();
            search_settings.wrap_around = true;

            // Connect search entry
            search_entry.search_changed.connect(() => {
                search_settings.search_text = search_entry.text;
                update_search_status();
            });

            search_entry.activate.connect(() => {
                find_next();
            });

            // Handle Shift+Enter for previous
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Return && (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    find_previous();
                    return true;
                }
                if (keyval == Gdk.Key.Escape) {
                    hide_search();
                    return true;
                }
                return false;
            });
            search_entry.add_controller(key_controller);
        }

        private void setup_keyboard_shortcuts() {
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;

                if (ctrl) {
                    switch (keyval) {
                        case Gdk.Key.f:
                        case Gdk.Key.F:
                            show_search();
                            return true;
                        case Gdk.Key.h:
                        case Gdk.Key.H:
                            show_search();
                            replace_entry.grab_focus();
                            return true;
                        case Gdk.Key.g:
                        case Gdk.Key.G:
                            if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                                find_previous();
                            } else {
                                find_next();
                            }
                            return true;
                    }
                }

                if (keyval == Gdk.Key.Escape && search_revealer.reveal_child) {
                    hide_search();
                    return true;
                }

                return false;
            });
            source_view.add_controller(key_controller);
        }

        public void show_search() {
            // Create search context if needed
            if (search_context == null) {
                search_context = new GtkSource.SearchContext(source_buffer, search_settings);
                search_context.highlight = true;
            }

            search_revealer.reveal_child = true;

            // Select current word if nothing selected
            Gtk.TextIter start, end;
            if (!source_buffer.get_selection_bounds(out start, out end)) {
                // Get word at cursor
                var cursor = source_buffer.get_insert();
                source_buffer.get_iter_at_mark(out start, cursor);
                end = start;

                if (start.inside_word() || start.ends_word()) {
                    start.backward_word_start();
                    end.forward_word_end();
                    string word = source_buffer.get_text(start, end, false);
                    search_entry.text = word;
                }
            } else {
                string selected = source_buffer.get_text(start, end, false);
                if (!selected.contains("\n")) {
                    search_entry.text = selected;
                }
            }

            search_entry.grab_focus();
            search_entry.select_region(0, -1);
        }

        public void hide_search() {
            search_revealer.reveal_child = false;
            source_view.grab_focus();
            if (search_context != null) {
                search_context.highlight = false;
            }
        }

        private void find_next() {
            if (search_context == null || search_settings.search_text == null) return;

            Gtk.TextIter start, match_start, match_end;
            var cursor = source_buffer.get_insert();
            source_buffer.get_iter_at_mark(out start, cursor);

            bool has_wrapped;
            if (search_context.forward(start, out match_start, out match_end, out has_wrapped)) {
                // If we found the same position, search from end of match
                if (match_start.equal(start)) {
                    if (search_context.forward(match_end, out match_start, out match_end, out has_wrapped)) {
                        source_buffer.select_range(match_start, match_end);
                        source_view.scroll_to_iter(match_start, 0.2, false, 0, 0);
                    }
                } else {
                    source_buffer.select_range(match_start, match_end);
                    source_view.scroll_to_iter(match_start, 0.2, false, 0, 0);
                }
            }
            update_search_status();
        }

        private void find_previous() {
            if (search_context == null || search_settings.search_text == null) return;

            Gtk.TextIter end, match_start, match_end;
            var cursor = source_buffer.get_insert();
            source_buffer.get_iter_at_mark(out end, cursor);

            bool has_wrapped;
            if (search_context.backward(end, out match_start, out match_end, out has_wrapped)) {
                source_buffer.select_range(match_start, match_end);
                source_view.scroll_to_iter(match_start, 0.2, false, 0, 0);
            }
            update_search_status();
        }

        private void replace_current() {
            if (search_context == null) return;

            Gtk.TextIter start, end;
            if (source_buffer.get_selection_bounds(out start, out end)) {
                try {
                    search_context.replace(start, end, replace_entry.text, -1);
                    find_next();
                } catch (Error e) {
                    warning("Replace error: %s", e.message);
                }
            } else {
                find_next();
            }
        }

        private void replace_all() {
            if (search_context == null) return;

            try {
                int count = (int) search_context.replace_all(replace_entry.text, -1);
                search_status_label.label = "Replaced %d".printf(count);
            } catch (Error e) {
                warning("Replace all error: %s", e.message);
            }
        }

        private void update_search_status() {
            if (search_context == null) {
                search_status_label.label = "";
                return;
            }

            int count = (int) search_context.occurrences_count;
            if (count < 0) {
                search_status_label.label = "...";
            } else if (count == 0) {
                search_status_label.label = "No results";
            } else {
                search_status_label.label = "%d found".printf(count);
            }
        }

        private void render_preview() {
            string source = source_buffer.text;

            // Performance: Check cache first
            if (source == last_rendered_source && cached_surface != null) {
                preview_pane.set_surface(cached_surface);
                return;
            }

            // Clear cache for new render
            cached_surface = null;
            lint_button.visible = false;
            validate_button.visible = false;
            complexity_button.visible = false;
            perf_label.visible = false;

            string? doc_filename = document.file != null ? document.file.get_basename() : null;
            current_diagram_format = engine.detect_format(source, doc_filename);

            string render_source;
            if (current_diagram_format == DiagramFormat.MERMAID) {
                // Mermaid diagrams don't need preprocessing
                render_source = source;
                current_diagram_type = engine.detect_mermaid_type(source);
            } else {
                render_source = engine.preprocess(source, get_document_base_path());
                current_diagram_type = engine.detect_plantuml_type(render_source);
            }

            perf_monitor.start_render();
            var result = engine.render(current_diagram_type, current_diagram_format, render_source);
            apply_render_result(result, source);
            perf_monitor.end_render(0);
            update_perf_label();
        }

        // Translate an engine RenderResult into UI actions: error highlights,
        // placeholder text, outline/stats updates and the preview surface. This
        // is the single generic render path that replaced the ~50 per-type
        // render methods (their parse+render core now lives in DiagramEngine).
        private void apply_render_result(RenderResult result, string source) {
            switch (result.status) {
                case RenderStatus.PARSE_ERROR:
                    apply_error_highlights(result.errors);
                    preview_pane.set_placeholder_text(result.message);
                    return;
                case RenderStatus.EMPTY:
                    clear_error_highlights();
                    preview_pane.set_placeholder_text(result.message);
                    return;
                case RenderStatus.UNKNOWN:
                    preview_pane.set_placeholder_text(result.message);
                    return;
                case RenderStatus.OK:
                default:
                    clear_error_highlights();
                    update_ui_after_render(result, source);
                    if (current_diagram_format == DiagramFormat.MERMAID) {
                        set_and_cache_surface(result.surface, source);
                    } else if (result.surface != null) {
                        preview_pane.set_surface(result.surface);
                        transfer_click_regions();
                    } else {
                        preview_pane.set_placeholder_text(result.fail_message);
                    }
                    return;
            }
        }

        // Per-type UI work driven off the parsed AST the engine exposes on the
        // result: outline entries plus (for Mermaid) stats/lint/validate and,
        // where applicable, complexity metrics. PlantUML types only feed the
        // outline; generic Graphviz-passthrough types have no AST and do
        // nothing here.
        private void update_ui_after_render(RenderResult result, string source) {
            // Outline population is delegated to the controller; the
            // remaining per-type work here is stats/lint/validate/complexity.
            outline_controller.update(result.diagram_type, result.ast);
            switch (result.diagram_type) {
                case DiagramType.MERMAID_FLOWCHART: {
                    var d = (MermaidFlowchart) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_flowchart(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_flowchart(d);
                    update_lint_state();
                    diagram_validator.validate_flowchart(d);
                    update_validate_state();
                    var fc_metrics = complexity_analyzer.analyze_flowchart(d);
                    diagram_optimizer.analyze_flowchart(d);
                    update_complexity_state(fc_metrics, true);
                    break;
                }
                case DiagramType.MERMAID_SEQUENCE: {
                    var d = (MermaidSequenceDiagram) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_sequence(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_sequence(d);
                    update_lint_state();
                    diagram_validator.validate_sequence(d);
                    update_validate_state();
                    var seq_metrics = complexity_analyzer.analyze_sequence(d);
                    update_complexity_state(seq_metrics, false);
                    break;
                }
                case DiagramType.MERMAID_STATE: {
                    var d = (MermaidStateDiagram) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_state(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_state(d);
                    update_lint_state();
                    diagram_validator.validate_state(d);
                    update_validate_state();
                    var st_metrics = complexity_analyzer.analyze_state(d);
                    update_complexity_state(st_metrics, false);
                    break;
                }
                case DiagramType.MERMAID_CLASS: {
                    var d = (MermaidClassDiagram) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_class(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_class(d);
                    update_lint_state();
                    diagram_validator.validate_class(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_ER: {
                    var d = (MermaidERDiagram) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_er(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_er(d);
                    update_lint_state();
                    diagram_validator.validate_er(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_GANTT: {
                    var d = (MermaidGantt) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_gantt(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_gantt(d);
                    update_lint_state();
                    diagram_validator.validate_gantt(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_PIE: {
                    var d = (MermaidPie) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_pie(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_pie(d);
                    update_lint_state();
                    diagram_validator.validate_pie(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_USER_JOURNEY: {
                    var d = (MermaidUserJourney) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_user_journey(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_user_journey(d);
                    update_lint_state();
                    diagram_validator.validate_user_journey(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_GIT_GRAPH: {
                    var d = (MermaidGitGraph) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_git_graph(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_git_graph(d);
                    update_lint_state();
                    diagram_validator.validate_git_graph(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_MINDMAP: {
                    var d = (MermaidMindmap) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_mindmap(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_mindmap(d);
                    update_lint_state();
                    diagram_validator.validate_mindmap(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_TIMELINE: {
                    var d = (MermaidTimeline) result.ast;
                    var tstats = new DiagramStats();
                    tstats.analyze_mermaid_timeline(d, source);
                    update_outline_stats(tstats.get_quick_stats());
                    diagram_linter.lint_timeline(d);
                    update_lint_state();
                    diagram_validator.validate_timeline(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_QUADRANT: {
                    var d = (MermaidQuadrant) result.ast;
                    var qstats = new DiagramStats();
                    qstats.analyze_mermaid_quadrant(d, source);
                    update_outline_stats(qstats.get_quick_stats());
                    diagram_linter.lint_quadrant(d);
                    update_lint_state();
                    diagram_validator.validate_quadrant(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_XYCHART: {
                    var d = (MermaidXYChart) result.ast;
                    var xstats = new DiagramStats();
                    xstats.analyze_mermaid_xychart(d, source);
                    update_outline_stats(xstats.get_quick_stats());
                    diagram_linter.lint_xychart(d);
                    update_lint_state();
                    diagram_validator.validate_xychart(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_KANBAN: {
                    var d = (MermaidKanban) result.ast;
                    var kstats = new DiagramStats();
                    kstats.analyze_mermaid_kanban(d, source);
                    update_outline_stats(kstats.get_quick_stats());
                    diagram_linter.lint_kanban(d);
                    update_lint_state();
                    diagram_validator.validate_kanban(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_SANKEY: {
                    var d = (MermaidSankey) result.ast;
                    var sstats = new DiagramStats();
                    sstats.analyze_mermaid_sankey(d, source);
                    update_outline_stats(sstats.get_quick_stats());
                    diagram_linter.lint_sankey(d);
                    update_lint_state();
                    diagram_validator.validate_sankey(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_REQUIREMENT: {
                    var d = (MermaidRequirement) result.ast;
                    var rstats = new DiagramStats();
                    rstats.analyze_mermaid_requirement(d, source);
                    update_outline_stats(rstats.get_quick_stats());
                    diagram_linter.lint_requirement(d);
                    update_lint_state();
                    diagram_validator.validate_requirement(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_BLOCK: {
                    var d = (MermaidBlock) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_block(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_block(d);
                    update_lint_state();
                    diagram_validator.validate_block(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_PACKET: {
                    var d = (MermaidPacket) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_packet(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_packet(d);
                    update_lint_state();
                    diagram_validator.validate_packet(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_C4: {
                    var d = (MermaidC4) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_c4(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_c4(d);
                    update_lint_state();
                    diagram_validator.validate_c4(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_ARCHITECTURE: {
                    var d = (MermaidArchitecture) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_architecture(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_architecture(d);
                    update_lint_state();
                    diagram_validator.validate_architecture(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_ZENUML: {
                    var d = (MermaidZenUML) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_zenuml(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_zenuml(d);
                    update_lint_state();
                    diagram_validator.validate_zenuml(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_RADAR: {
                    var d = (MermaidRadar) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_radar(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_radar(d);
                    update_lint_state();
                    diagram_validator.validate_radar(d);
                    update_validate_state();
                    break;
                }
                case DiagramType.MERMAID_TREEMAP: {
                    var d = (MermaidTreemap) result.ast;
                    var stats = new DiagramStats();
                    stats.analyze_mermaid_treemap(d, source);
                    update_outline_stats(stats.get_quick_stats());
                    diagram_linter.lint_treemap(d);
                    update_lint_state();
                    diagram_validator.validate_treemap(d);
                    update_validate_state();
                    break;
                }
                default:
                    // Generic Graphviz-passthrough PlantUML types: no outline AST.
                    break;
            }
        }

        public new void grab_focus() {
            source_view.grab_focus();
        }

        public void beautify_source() {
            string current = source_buffer.text;
            string formatted;

            if (current_diagram_format == DiagramFormat.MERMAID) {
                switch (current_diagram_type) {
                    case DiagramType.MERMAID_FLOWCHART:
                        formatted = DiagramBeautifier.format_mermaid_flowchart(current);
                        break;
                    case DiagramType.MERMAID_SEQUENCE:
                        formatted = DiagramBeautifier.format_mermaid_sequence(current);
                        break;
                    case DiagramType.MERMAID_STATE:
                        formatted = DiagramBeautifier.format_mermaid_state(current);
                        break;
                    case DiagramType.MERMAID_CLASS:
                        formatted = DiagramBeautifier.format_mermaid_class(current);
                        break;
                    case DiagramType.MERMAID_ER:
                        formatted = DiagramBeautifier.format_mermaid_er(current);
                        break;
                    case DiagramType.MERMAID_GANTT:
                        formatted = DiagramBeautifier.format_mermaid_gantt(current);
                        break;
                    default:
                        formatted = DiagramBeautifier.format_mermaid_uniform(current);
                        break;
                }
            } else {
                // PlantUML and anything else
                formatted = DiagramBeautifier.format_plantuml(current);
            }

            if (formatted != current) {
                source_buffer.text = formatted;
            }
        }

        public void zoom_in() {
            preview_pane.zoom_in();
        }

        public void zoom_out() {
            preview_pane.zoom_out();
        }

        public void zoom_reset() {
            preview_pane.zoom_reset();
        }

        public void zoom_fit() {
            preview_pane.zoom_fit();
        }

        // ==================== Outline Toggle ====================

        public void toggle_outline_visibility() {
            if (outline_revealer.reveal_child) {
                // Hide outline - save position and collapse pane
                saved_outline_position = left_paned.position;
                outline_revealer.reveal_child = false;
                left_paned.position = 0;
            } else {
                // Show outline - restore position
                outline_revealer.reveal_child = true;
                left_paned.position = saved_outline_position;
            }
        }

        public Cairo.ImageSurface? get_preview_surface() {
            return preview_pane.get_surface();
        }

        // ==================== Export ====================

        // Clears the cached render so the next export/preview re-runs the
        // DOT generator. Used when something outside the source text changes
        // (e.g. active palette swap for transparent export).
        public void invalidate_render_cache() {
            last_rendered_source = "";
            cached_surface = null;
        }

        // Force a synchronous re-render of the preview surface. Needed
        // before export when the palette has been swapped out-of-band so
        // the resulting surface reflects the override.
        public void render_preview_now() {
            last_rendered_source = "";
            cached_surface = null;
            render_preview();
        }

        public bool export_to_png_scaled(string filename, double scale) {
            var surface = preview_pane.get_surface();
            if (surface == null) return false;

            int orig_width = surface.get_width();
            int orig_height = surface.get_height();
            int new_width = (int)(orig_width * scale);
            int new_height = (int)(orig_height * scale);

            // Create scaled surface
            var scaled_surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, new_width, new_height);
            var cr = new Cairo.Context(scaled_surface);

            // Fill with the palette background color. If the palette's
            // background is "transparent" (set by the transparent-export
            // toggle), leave the surface's natural ARGB32 alpha channel.
            string bg = ThemeManager.get_active_palette().background;
            if (bg != "transparent") {
                var rgba = Gdk.RGBA();
                if (!rgba.parse(bg)) rgba.parse("#FFFFFF");
                cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha);
                cr.rectangle(0, 0, new_width, new_height);
                cr.fill();
            }

            // Scale and draw
            cr.scale(scale, scale);
            cr.set_source_surface(surface, 0, 0);
            cr.paint();

            // Save to PNG
            var status = scaled_surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_png(string filename) {
            return engine.export_to_png(
                source_buffer.text,
                document.file != null ? document.file.get_basename() : null,
                get_document_base_path(),
                filename);
        }

        public bool export_to_svg(string filename) {
            return engine.export_to_svg(
                source_buffer.text,
                document.file != null ? document.file.get_basename() : null,
                get_document_base_path(),
                filename);
        }

        public bool export_to_pdf(string filename) {
            return engine.export_to_pdf(
                source_buffer.text,
                document.file != null ? document.file.get_basename() : null,
                get_document_base_path(),
                filename);
        }


        private void setup_completion() {
            // Get the completion object
            var completion = source_view.completion;
            completion.show_icons = true;

            // Add a word-based completion provider for PlantUML keywords
            var words_provider = new GtkSource.CompletionWords("PlantUML Keywords");
            words_provider.minimum_word_size = 2;
            words_provider.priority = 1;

            // Register PlantUML keywords as a word buffer
            var keyword_buffer = new GtkSource.Buffer(null);
            keyword_buffer.text = string.joinv("\n", get_plantuml_keywords());
            words_provider.register(keyword_buffer);

            completion.add_provider(words_provider);
        }

        private string[] get_plantuml_keywords() {
            return {
                // Diagram types
                "@startuml", "@enduml", "@startmindmap", "@endmindmap",
                // Class diagram
                "class", "interface", "abstract", "enum", "annotation",
                "extends", "implements", "package", "namespace",
                // Relationships
                "--|>", "<|--", "..|>", "<|..", "o--", "--o", "*--", "--*",
                // Sequence diagram
                "participant", "actor", "boundary", "control", "entity",
                "database", "collections", "queue",
                "activate", "deactivate", "destroy",
                "autonumber", "return", "group", "opt", "alt", "else",
                "loop", "par", "break", "critical", "ref", "end",
                // Activity diagram
                "start", "stop", "kill", "detach",
                "if", "then", "else", "elseif", "endif",
                "while", "endwhile", "repeat", "repeatwhile",
                "fork", "endfork", "split", "endsplit",
                "switch", "case", "endswitch",
                "partition", "floating",
                // State diagram
                "state", "[*]", "<<choice>>", "<<fork>>", "<<join>>", "<<end>>",
                // Use case diagram
                "usecase", "rectangle", "left to right direction", "top to bottom direction",
                // Component diagram
                "component", "node", "folder", "frame", "cloud", "database",
                "artifact", "storage", "file", "portin", "portout",
                // Notes
                "note", "note left", "note right", "note top", "note bottom",
                "note over", "end note", "hnote", "rnote",
                // Styling
                "skinparam", "hide", "show", "title", "header", "footer",
                "legend", "caption", "scale", "newpage",
                // Colors
                "BackgroundColor", "BorderColor", "FontColor", "FontSize",
                "ArrowColor", "LineColor"
            };
        }

        private void setup_language() {
            // Use the default language manager
            var lang_manager = GtkSource.LanguageManager.get_default();

            // Determine which language to use based on file extension or content
            string lang_id = "plantuml";  // Default

            // Check file extension first
            if (document.file != null) {
                string filename = document.file.get_basename().down();
                if (filename.has_suffix(".mmd") || filename.has_suffix(".mermaid")) {
                    lang_id = "mermaid";
                }
            } else {
                // No file yet, check content
                string content = source_buffer.text.down();
                if (content.contains("flowchart") ||
                    content.contains("sequencediagram") ||
                    content.contains("statediagram-v2") ||
                    content.contains("statediagram")) {
                    lang_id = "mermaid";
                }
            }

            // Apply the language
            var language = lang_manager.get_language(lang_id);
            if (language != null) {
                source_buffer.language = language;
            }
            // If not found, syntax highlighting just won't be available
        }

        /**
         * Get the directory path of the current document for resolving relative includes.
         * Returns null if the document hasn't been saved yet.
         */
        private string? get_document_base_path() {
            if (document.file == null) {
                return null;
            }
            var parent = document.file.get_parent();
            if (parent == null) {
                return null;
            }
            return parent.get_path();
        }

        // ==================== Git ====================

        // Public delegate kept for MainWindow, which calls it after save and
        // on tab/file changes. The implementation lives in GitGutterController.
        public void refresh_git_dirty() {
            git_gutter.refresh_git_dirty();
        }
    }
}
