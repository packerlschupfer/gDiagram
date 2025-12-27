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
        private Preprocessor preprocessor;
        private Parser parser;
        private ClassDiagramParser class_parser;
        private ActivityDiagramParser activity_parser;
        private UseCaseDiagramParser usecase_parser;
        private StateDiagramParser state_parser;
        private ComponentDiagramParser component_parser;
        private ObjectDiagramParser object_parser;
        private DeploymentDiagramParser deployment_parser;
        private ERDiagramParser er_parser;
        private MindMapDiagramParser mindmap_parser;
        private GraphvizRenderer renderer;
        private DiagramType current_diagram_type;
        private DiagramFormat current_diagram_format;

        // Mermaid parsers and renderers
        private MermaidFlowchartParser mermaid_flowchart_parser;
        private MermaidFlowchartRenderer mermaid_flowchart_renderer;
        private MermaidSequenceParser mermaid_sequence_parser;
        private MermaidSequenceRenderer mermaid_sequence_renderer;
        private MermaidStateParser mermaid_state_parser;
        private MermaidStateRenderer mermaid_state_renderer;
        private MermaidClassParser mermaid_class_parser;
        private MermaidClassRenderer mermaid_class_renderer;
        private MermaidERParser mermaid_er_parser;
        private MermaidERRenderer mermaid_er_renderer;
        private MermaidGanttParser mermaid_gantt_parser;
        private MermaidGanttRenderer mermaid_gantt_renderer;
        private MermaidPieParser mermaid_pie_parser;
        private MermaidPieRenderer mermaid_pie_renderer;

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

        // Zoom controls
        private Gtk.Label zoom_label;

        // Diagram search
        private int diagram_search_index = 0;
        private string last_diagram_search = "";

        // Performance: cache to avoid re-rendering unchanged diagrams
        private string last_rendered_source = "";
        private Cairo.ImageSurface? cached_surface = null;

        // Debug: track render calls to detect infinite loops
        private static int render_call_count = 0;

        // Split view
        private Gtk.Paned main_paned;

        // External change notification
        private Adw.Banner? external_change_banner = null;

        // Font styling
        private Gtk.CssProvider? font_css_provider = null;

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

            render_debouncer = new Debouncer(app_settings.get_int("render-delay"));
            current_errors = new Gee.ArrayList<ParseError>();
            if (debug) print("[DEBUG] Creating PlantUML parsers...\n");
            preprocessor = new Preprocessor();
            parser = new Parser();
            class_parser = new ClassDiagramParser();
            activity_parser = new ActivityDiagramParser();
            usecase_parser = new UseCaseDiagramParser();
            state_parser = new StateDiagramParser();
            component_parser = new ComponentDiagramParser();
            object_parser = new ObjectDiagramParser();
            deployment_parser = new DeploymentDiagramParser();
            er_parser = new ERDiagramParser();
            mindmap_parser = new MindMapDiagramParser();
            if (debug) print("[DEBUG] PlantUML parsers created\n");

            if (debug) print("[DEBUG] Creating GraphvizRenderer...\n");
            renderer = new GraphvizRenderer();
            renderer.layout_engine = app_settings.get_string("layout-engine");
            current_diagram_type = DiagramType.SEQUENCE;
            current_diagram_format = DiagramFormat.PLANTUML;
            if (debug) print("[DEBUG] GraphvizRenderer created\n");

            // Initialize Mermaid parsers and renderers
            if (debug) print("[DEBUG] Creating Mermaid parsers...\n");
            mermaid_flowchart_parser = new MermaidFlowchartParser();
            mermaid_sequence_parser = new MermaidSequenceParser();
            mermaid_state_parser = new MermaidStateParser();
            mermaid_class_parser = new MermaidClassParser();
            if (debug) print("[DEBUG] Mermaid parsers created\n");

            if (debug) print("[DEBUG] Creating Gvc.Context for Mermaid...\n");
            var mermaid_context = new Gvc.Context();
            if (debug) print("[DEBUG] Gvc.Context created\n");
            if (debug) print("[DEBUG] Creating Mermaid renderers...\n");
            mermaid_flowchart_renderer = new MermaidFlowchartRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] Flowchart renderer OK\n");

            mermaid_sequence_renderer = new MermaidSequenceRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] Sequence renderer OK\n");

            mermaid_state_renderer = new MermaidStateRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] State renderer OK\n");

            mermaid_class_renderer = new MermaidClassRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] Class renderer OK\n");

            mermaid_er_parser = new MermaidERParser();
            mermaid_er_renderer = new MermaidERRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] ER parser/renderer OK\n");

            mermaid_gantt_parser = new MermaidGanttParser();
            mermaid_gantt_renderer = new MermaidGanttRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] Gantt parser/renderer OK\n");

            mermaid_pie_parser = new MermaidPieParser();
            mermaid_pie_renderer = new MermaidPieRenderer(
                mermaid_context,
                renderer.last_regions,
                app_settings.get_string("layout-engine")
            );
            if (debug) print("[DEBUG] Pie parser/renderer OK\n");
            if (debug) print("[DEBUG] All Mermaid components initialized successfully\n");

            // Listen for layout engine changes
            app_settings.changed["layout-engine"].connect(() => {
                renderer.layout_engine = app_settings.get_string("layout-engine");
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

            // Connect zoom signal
            preview_pane.zoom_changed.connect((level) => {
                zoom_label.label = "%.0f%%".printf(level * 100);
            });

            // Create preview box with zoom controls at bottom
            var preview_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
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
            });

            document.notify["content"].connect(() => {
                if (source_buffer.text != document.content) {
                    source_buffer.text = document.content;
                }
            });

            // Handle external file changes (auto-reload)
            document.external_change.connect(on_external_file_change);

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
            int line = cursor_iter.get_line() + 1;  // Convert to 1-based line number

            // Find element at this line
            string? element_name = find_element_at_line(line);
            if (element_name != null) {
                preview_pane.highlight_element(element_name);
            }
        }

        private string? find_element_at_line(int line) {
            // Search through click regions to find element matching this line
            foreach (var region in renderer.last_regions) {
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
                // NOTE: StyleContext.add_provider_for_display() is the correct modern GTK4 API.
                // The deprecation warning is a false positive - GTK4 deprecated the entire
                // StyleContext class but this static method is still the recommended approach.
                // See: https://docs.gtk.org/gtk4/class.StyleContext.html#css-in-gtk
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
            outline_list.add_css_class("navigation-sidebar");

            // Handle row selection to navigate to element
            outline_list.row_activated.connect((row) => {
                var box = row.child as Gtk.Box;
                if (box != null) {
                    // Find the label in the box (second child after icon)
                    var child = box.get_first_child();
                    if (child != null) {
                        child = child.get_next_sibling();  // Skip icon
                        var label = child as Gtk.Label;
                        if (label != null) {
                            var text = label.label;
                            // Navigate to the element in the editor
                            search_and_navigate(text);
                            // Also highlight the element in the diagram
                            preview_pane.highlight_element(text);
                        }
                    }
                }
            });

            scroll.child = outline_list;
            outline_box.append(scroll);

            outline_revealer.child = outline_box;
        }

        private void search_and_navigate(string text) {
            // Search for the text and scroll to it
            Gtk.TextIter start;
            source_buffer.get_start_iter(out start);

            Gtk.TextIter match_start, match_end;
            if (start.forward_search(text, Gtk.TextSearchFlags.CASE_INSENSITIVE,
                                      out match_start, out match_end, null)) {
                source_buffer.select_range(match_start, match_end);
                source_view.scroll_to_iter(match_start, 0.1, true, 0.5, 0.5);
            }
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
            if (source_line > 0) {
                // Navigate directly to the line
                navigate_to_line(source_line);
            } else {
                // Fall back to text search
                search_and_navigate(element_name);
            }
        }

        private void transfer_click_regions() {
            preview_pane.clear_regions();
            foreach (var region in renderer.last_regions) {
                preview_pane.add_region(
                    region.name,
                    region.source_line,
                    region.x,
                    region.y,
                    region.width,
                    region.height
                );
            }
        }

        private void search_diagram_element(string query) {
            // Search for first matching element
            if (query != last_diagram_search) {
                diagram_search_index = 0;
                last_diagram_search = query;
            }

            // Find matching regions
            var matches = new Gee.ArrayList<string>();
            foreach (var region in renderer.last_regions) {
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
            foreach (var region in renderer.last_regions) {
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

        private void update_outline_from_class_diagram(ClassDiagram diagram) {
            // Clear existing items
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            // Add title if present
            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add classes
            foreach (var c in diagram.classes) {
                string icon = "view-list-symbolic";
                if (c.class_type == ClassType.INTERFACE) {
                    icon = "view-list-bullet-symbolic";
                } else if (c.class_type == ClassType.ABSTRACT) {
                    icon = "view-list-compact-symbolic";
                }
                add_outline_item(c.name, icon);
            }
        }

        private void update_outline_from_sequence_diagram(SequenceDiagram diagram) {
            // Clear existing items
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            // Add title if present
            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add participants
            foreach (var p in diagram.participants) {
                add_outline_item(p.name, "avatar-default-symbolic");
            }
        }

        private void update_outline_from_activity_diagram(ActivityDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add main activities/actions
            foreach (var node in diagram.nodes) {
                string icon = "system-run-symbolic";
                if (node.node_type == ActivityNodeType.START) {
                    add_outline_item("Start", "media-playback-start-symbolic");
                } else if (node.node_type == ActivityNodeType.STOP) {
                    add_outline_item("Stop", "media-playback-stop-symbolic");
                } else if (node.node_type == ActivityNodeType.ACTION && node.label != null) {
                    add_outline_item(node.label, icon);
                } else if (node.partition != null) {
                    add_outline_item("Partition: " + node.partition, "view-list-symbolic");
                }
            }
        }

        private void update_outline_from_state_diagram(StateDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add states
            foreach (var state in diagram.states) {
                string icon = "view-grid-symbolic";
                string display_name = state.label ?? state.id;
                add_outline_item(display_name, icon);
            }
        }

        private void update_outline_from_usecase_diagram(UseCaseDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add actors
            foreach (var actor in diagram.actors) {
                add_outline_item(actor.name, "avatar-default-symbolic");
            }

            // Add use cases
            foreach (var uc in diagram.use_cases) {
                add_outline_item(uc.name, "emblem-system-symbolic");
            }

            // Add packages
            foreach (var pkg in diagram.packages) {
                add_outline_item(pkg.name, "folder-symbolic");
            }
        }

        private void update_outline_from_component_diagram(ComponentDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add components
            foreach (var comp in diagram.components) {
                string display_name = comp.label ?? comp.id;
                add_outline_item(display_name, "package-x-generic-symbolic");
            }

            // Add interfaces
            foreach (var iface in diagram.interfaces) {
                string display_name = iface.label ?? iface.id;
                add_outline_item(display_name, "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_object_diagram(ObjectDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add objects
            foreach (var obj in diagram.objects) {
                add_outline_item(obj.name, "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_deployment_diagram(DeploymentDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add nodes
            foreach (var node in diagram.nodes) {
                string display_name = node.label ?? node.id;
                add_outline_item(display_name, "computer-symbolic");
            }
        }

        private void update_outline_from_er_diagram(ERDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add entities
            foreach (var entity in diagram.entities) {
                add_outline_item(entity.name, "view-list-symbolic");
            }
        }

        private void update_outline_from_mindmap_diagram(MindMapDiagram diagram) {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add root node and its children
            if (diagram.root != null) {
                add_outline_item(diagram.root.text, "view-paged-symbolic");
                foreach (var child in diagram.root.children) {
                    add_outline_item("  " + child.text, "view-paged-symbolic");
                }
            }
        }

        private void add_outline_item(string text, string icon_name) {
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.margin_start = 6;
            box.margin_end = 6;
            box.margin_top = 3;
            box.margin_bottom = 3;

            var icon = new Gtk.Image.from_icon_name(icon_name);
            icon.add_css_class("dim-label");
            box.append(icon);

            var label = new Gtk.Label(text);
            label.xalign = 0;
            label.ellipsize = Pango.EllipsizeMode.END;
            box.append(label);

            outline_list.append(box);
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
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] render_preview() ENTERED\n");

            string source = source_buffer.text;
            if (debug) print("[DEBUG] Source length: %d chars\n", source.length);

            // Performance: Check cache first
            if (source == last_rendered_source && cached_surface != null) {
                if (debug) print("[DEBUG] Using cached surface (source unchanged)\n");
                // Source unchanged, use cached render
                preview_pane.set_surface(cached_surface);
                if (debug) print("[DEBUG] Cached surface set, returning\n");
                return;
            }

            if (debug) print("[DEBUG] Cache miss, will render diagram\n");
            // Clear cache for new render
            cached_surface = null;

            // Detect format first (Mermaid vs PlantUML)
            if (debug) print("[DEBUG] Detecting diagram format...\n");
            current_diagram_format = detect_diagram_format(source);
            if (debug) print("[DEBUG] Format: %s\n", current_diagram_format.to_string());

            if (current_diagram_format == DiagramFormat.MERMAID) {
                if (debug) print("[DEBUG] Mermaid path - detecting type...\n");
                // Mermaid diagrams don't need preprocessing
                current_diagram_type = detect_mermaid_diagram_type(source);
                if (debug) print("[DEBUG] Mermaid type: %s\n", current_diagram_type.to_string());
                render_mermaid_diagram(source);
                if (debug) print("[DEBUG] Mermaid render complete\n");
                return;
            }

            // PlantUML processing path
            if (debug) print("[DEBUG] PlantUML path - preprocessing source...\n");
            string processed_source = preprocess_source(source);
            if (debug) print("[DEBUG] Preprocessing complete, detecting diagram type...\n");
            current_diagram_type = detect_diagram_type(processed_source);
            if (debug) print("[DEBUG] PlantUML type: %s\n", current_diagram_type.to_string());

            switch (current_diagram_type) {
                case DiagramType.CLASS:
                    if (debug) print("[DEBUG] Rendering CLASS diagram...\n");
                    render_class_diagram(processed_source);
                    break;
                case DiagramType.ACTIVITY:
                    if (debug) print("[DEBUG] Rendering ACTIVITY diagram...\n");
                    render_activity_diagram(processed_source);
                    if (debug) print("[DEBUG] Activity diagram render completed\n");
                    break;
                case DiagramType.USECASE:
                    render_usecase_diagram(processed_source);
                    break;
                case DiagramType.STATE:
                    render_state_diagram(processed_source);
                    break;
                case DiagramType.COMPONENT:
                    render_component_diagram(processed_source);
                    break;
                case DiagramType.OBJECT:
                    render_object_diagram(processed_source);
                    break;
                case DiagramType.DEPLOYMENT:
                    render_deployment_diagram(processed_source);
                    break;
                case DiagramType.ER_DIAGRAM:
                    render_er_diagram(processed_source);
                    break;
                case DiagramType.MINDMAP:
                    render_mindmap_diagram(processed_source, DiagramType.MINDMAP);
                    break;
                case DiagramType.WBS:
                    render_mindmap_diagram(processed_source, DiagramType.WBS);
                    break;
                default:
                    render_sequence_diagram(processed_source);
                    break;
            }
        }

        private DiagramType detect_diagram_type(string source) {
            string lower = source.down();

            // Check for sequence diagram indicators FIRST before other types
            // Sequence diagrams have unique participant keywords
            bool has_sequence_syntax =
                lower.contains("\nparticipant ") ||
                lower.has_prefix("participant ") ||
                (lower.contains("\nactor ") && lower.contains("\nparticipant "));

            if (has_sequence_syntax) {
                return DiagramType.SEQUENCE;
            }

            // Check for activity diagram indicators (high priority)
            // Activity diagrams have distinctive syntax that can't be confused
            bool has_start_stop = lower.contains("\nstart") || lower.contains("\nstop") ||
                                  lower.has_prefix("@startuml\nstart") ||
                                  lower.has_prefix("@startuml\r\nstart");

            bool has_activity_syntax = lower.contains("endif") ||
                                       lower.contains("endwhile") ||
                                       lower.contains("end fork") ||
                                       lower.contains("endswitch") ||
                                       lower.contains("fork again") ||
                                       lower.contains("partition ") ||
                                       (lower.contains(":") && lower.contains(";"));

            if (has_start_stop || has_activity_syntax) {
                return DiagramType.ACTIVITY;
            }

            // Check for state diagram indicators
            bool has_state_syntax =
                lower.contains("[*]") ||
                lower.contains("\nstate ") ||
                lower.has_prefix("state ");

            if (has_state_syntax) {
                return DiagramType.STATE;
            }

            // Check for use case diagram indicators
            bool has_usecase_syntax =
                lower.contains("\nusecase ") ||
                lower.contains("\nusecase(") ||
                (lower.contains("\nactor ") && !lower.contains("\nparticipant "));

            if (has_usecase_syntax) {
                return DiagramType.USECASE;
            }

            // Check for MindMap / WBS indicators
            bool has_mindmap_syntax =
                lower.contains("@startmindmap") ||
                lower.contains("@startwbs");

            if (has_mindmap_syntax) {
                if (lower.contains("@startwbs")) {
                    return DiagramType.WBS;
                }
                return DiagramType.MINDMAP;
            }

            // Check for ER diagram indicators
            bool has_er_syntax =
                lower.contains("\nentity ") ||
                lower.has_prefix("entity ") ||
                lower.contains("||--") ||
                lower.contains("}o--") ||
                lower.contains("|o--") ||
                lower.contains("--||") ||
                lower.contains("--o{") ||
                lower.contains("--o|");

            if (has_er_syntax) {
                return DiagramType.ER_DIAGRAM;
            }

            // Check for deployment diagram indicators (device keyword is unique to deployment)
            bool has_deployment_syntax =
                lower.contains("\ndevice ") ||
                lower.has_prefix("device ");

            if (has_deployment_syntax) {
                return DiagramType.DEPLOYMENT;
            }

            // Check for component diagram indicators
            bool has_component_syntax =
                lower.contains("\ncomponent ") ||
                lower.contains("\n[") ||
                lower.contains("\ncloud ") ||
                lower.contains("\nnode ") ||
                lower.contains("\nfolder ") ||
                lower.contains("\nframe ") ||
                lower.contains("\nrectangle ") ||
                lower.contains("\nartifact ") ||
                lower.contains("\nstorage ") ||
                lower.contains("\ndatabase ");

            if (has_component_syntax) {
                return DiagramType.COMPONENT;
            }

            // Check for object diagram indicators
            bool has_object_syntax =
                lower.contains("\nobject ") ||
                lower.has_prefix("object ");

            if (has_object_syntax) {
                return DiagramType.OBJECT;
            }

            // Check for class diagram indicators
            // Note: "class " can appear in skinparam, so check for actual class declarations
            bool has_class_syntax =
                // Class declarations (word boundary check with newline)
                (lower.contains("\nclass ") || lower.has_prefix("class ")) ||
                lower.contains("\ninterface ") ||
                lower.contains("\nabstract class") ||
                lower.contains("\nenum ") ||
                // Class relationship arrows
                lower.contains("--|>") ||
                lower.contains("<|--") ||
                lower.contains("..|>") ||
                lower.contains("<|..") ||
                lower.contains("o--") ||
                lower.contains("--o") ||
                lower.contains("*--") ||
                lower.contains("--*");

            if (has_class_syntax) {
                return DiagramType.CLASS;
            }

            // Check for sequence diagram indicators (arrows)
            if (lower.contains("->") || lower.contains("-->") ||
                lower.contains("<-") || lower.contains("<--")) {
                return DiagramType.SEQUENCE;
            }

            // Default to sequence
            return DiagramType.SEQUENCE;
        }

        private DiagramFormat detect_diagram_format(string source) {
            string lower = source.down();

            // Check for Mermaid diagram type keywords
            if (lower.contains("flowchart ") ||
                lower.contains("sequencediagram") ||
                lower.contains("statediagram-v2") ||
                lower.contains("classdiagram") ||
                lower.contains("erdiagram") ||
                lower.contains("gantt") ||
                lower.contains("gitgraph") ||
                lower.contains("journey") ||
                lower.has_prefix("flowchart") ||
                lower.has_prefix("sequencediagram")) {
                return DiagramFormat.MERMAID;
            }

            // Check for PlantUML markers
            if (lower.contains("@startuml") || lower.contains("@enduml")) {
                return DiagramFormat.PLANTUML;
            }

            // Check file extension if available
            if (document.file != null) {
                string filename = document.file.get_basename().down();
                if (filename.has_suffix(".mmd") || filename.has_suffix(".mermaid")) {
                    return DiagramFormat.MERMAID;
                }
                if (filename.has_suffix(".puml") || filename.has_suffix(".plantuml") || filename.has_suffix(".pu")) {
                    return DiagramFormat.PLANTUML;
                }
            }

            // Default to PlantUML for backward compatibility
            return DiagramFormat.PLANTUML;
        }

        private DiagramType detect_mermaid_diagram_type(string source) {
            string lower = source.down();

            if (lower.contains("flowchart") || lower.has_prefix("flowchart")) {
                return DiagramType.MERMAID_FLOWCHART;
            }
            if (lower.contains("sequencediagram") || lower.has_prefix("sequencediagram")) {
                return DiagramType.MERMAID_SEQUENCE;
            }
            if (lower.contains("statediagram-v2") || lower.has_prefix("statediagram-v2")) {
                return DiagramType.MERMAID_STATE;
            }
            if (lower.contains("classdiagram") || lower.has_prefix("classdiagram")) {
                return DiagramType.MERMAID_CLASS;
            }
            if (lower.contains("erdiagram") || lower.has_prefix("erdiagram")) {
                return DiagramType.MERMAID_ER;
            }
            if (lower.contains("gantt") || lower.has_prefix("gantt")) {
                return DiagramType.MERMAID_GANTT;
            }
            if (lower.contains("pie") || lower.has_prefix("pie")) {
                return DiagramType.MERMAID_PIE;
            }

            return DiagramType.MERMAID_FLOWCHART;  // Default
        }

        private void render_mermaid_diagram(string source) {
            switch (current_diagram_type) {
                case DiagramType.MERMAID_FLOWCHART:
                    render_mermaid_flowchart(source);
                    break;
                case DiagramType.MERMAID_SEQUENCE:
                    render_mermaid_sequence(source);
                    break;
                case DiagramType.MERMAID_STATE:
                    render_mermaid_state(source);
                    break;
                case DiagramType.MERMAID_CLASS:
                    render_mermaid_class(source);
                    break;
                case DiagramType.MERMAID_ER:
                    render_mermaid_er(source);
                    break;
                case DiagramType.MERMAID_GANTT:
                    render_mermaid_gantt(source);
                    break;
                case DiagramType.MERMAID_PIE:
                    render_mermaid_pie(source);
                    break;
                default:
                    preview_pane.set_placeholder_text("Unknown Mermaid diagram type");
                    break;
            }
        }

        private void render_mermaid_flowchart(string source) {
            var diagram = mermaid_flowchart_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.nodes.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid code to see preview.\n\n" +
                    "Flowchart Example:\n" +
                    "flowchart TD\n" +
                    "    A[Start] --> B{Decision}\n" +
                    "    B -->|Yes| C[Process]\n" +
                    "    B -->|No| D[End]\n" +
                    "    C --> D"
                );
                return;
            }

            // Render using Mermaid flowchart renderer
            var surface = mermaid_flowchart_renderer.render_to_surface(diagram);
            if (surface != null) {
                preview_pane.set_surface(surface);
            } else {
                preview_pane.set_placeholder_text("Failed to render diagram");
            }
        }

        private void render_mermaid_sequence(string source) {
            var diagram = mermaid_sequence_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.actors.size == 0 && diagram.messages.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid sequence diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "sequenceDiagram\n" +
                    "    participant Alice\n" +
                    "    participant Bob\n" +
                    "    Alice->>Bob: Hello Bob!\n" +
                    "    Bob-->>Alice: Hi Alice!"
                );
                return;
            }

            // Render using Mermaid sequence renderer
            var surface = mermaid_sequence_renderer.render_to_surface(diagram);
            if (surface != null) {
                preview_pane.set_surface(surface);
            } else {
                preview_pane.set_placeholder_text("Failed to render diagram");
            }
        }

        private void render_mermaid_state(string source) {
            var diagram = mermaid_state_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.states.size == 0 && diagram.transitions.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid state diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "stateDiagram-v2\n" +
                    "    [*] --> Still\n" +
                    "    Still --> Moving\n" +
                    "    Moving --> [*]"
                );
                return;
            }

            // Render using Mermaid state renderer
            var surface = mermaid_state_renderer.render_to_surface(diagram);
            if (surface != null) {
                preview_pane.set_surface(surface);
            } else {
                preview_pane.set_placeholder_text("Failed to render diagram");
            }
        }

        private void render_mermaid_class(string source) {
            var diagram = mermaid_class_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.classes.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid class diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "classDiagram\n" +
                    "    class Animal {\n" +
                    "        +string name\n" +
                    "        +makeSound()\n" +
                    "    }\n" +
                    "    class Dog {\n" +
                    "        +bark()\n" +
                    "    }"
                );
                return;
            }

            // Render using Mermaid class renderer
            var surface = mermaid_class_renderer.render_to_surface(diagram);
            if (surface != null) {
                preview_pane.set_surface(surface);
            } else {
                preview_pane.set_placeholder_text("Failed to render diagram");
            }
        }

        private void render_mermaid_er(string source) {
            var diagram = mermaid_er_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.entities.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid ER diagram code to see preview.\n\n" +
                    "Example:\n" +
                    "erDiagram\n" +
                    "    CUSTOMER ||--o{ ORDER : places\n" +
                    "    ORDER ||--|{ LINE-ITEM : contains"
                );
                return;
            }

            // Render using Mermaid ER renderer
            var surface = mermaid_er_renderer.render_to_surface(diagram);
            set_and_cache_surface(surface, source);
        }

        private void render_mermaid_gantt(string source) {
            var diagram = mermaid_gantt_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.tasks.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid Gantt chart code to see preview.\n\n" +
                    "Example:\n" +
                    "gantt\n" +
                    "    title Project Schedule\n" +
                    "    section Planning\n" +
                    "    Requirements : done, 5d\n" +
                    "    Design : active, 7d"
                );
                return;
            }

            // Render using Mermaid Gantt renderer
            var surface = mermaid_gantt_renderer.render_to_surface(diagram);
            set_and_cache_surface(surface, source);
        }

        private void render_mermaid_pie(string source) {
            var diagram = mermaid_pie_parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.slices.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter Mermaid Pie chart code to see preview.\n\n" +
                    "Example:\n" +
                    "pie title Sales Distribution\n" +
                    "    \"Product A\" : 45\n" +
                    "    \"Product B\" : 30\n" +
                    "    \"Product C\" : 25"
                );
                return;
            }

            // Render using Mermaid Pie renderer
            var surface = mermaid_pie_renderer.render_to_surface(diagram);
            set_and_cache_surface(surface, source);
        }

        private void render_sequence_diagram(string source) {
            var diagram = parser.parse(source);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.participants.size == 0 && diagram.messages.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter PlantUML code to see preview.\n\n" +
                    "Sequence Example:\n" +
                    "@startuml\n" +
                    "Alice -> Bob : Hello\n" +
                    "Bob --> Alice : Hi!\n" +
                    "@enduml\n\n" +
                    "Class Example:\n" +
                    "@startuml\n" +
                    "class Animal\n" +
                    "class Dog\n" +
                    "Dog --|> Animal\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_sequence_diagram(diagram);

            var surface = renderer.render_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render diagram");
            }
        }

        private void render_class_diagram(string source) {
            // Tokenize with the lexer
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            // Parse as class diagram
            var diagram = class_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.classes.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter class diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "class Animal {\n" +
                    "  +name: String\n" +
                    "  +eat()\n" +
                    "}\n" +
                    "class Dog {\n" +
                    "  +bark()\n" +
                    "}\n" +
                    "Dog --|> Animal\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_class_diagram(diagram);

            var surface = renderer.render_class_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                // Transfer click regions for source navigation
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render class diagram");
            }
        }

        private void render_activity_diagram(string source) {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] render_activity_diagram() ENTERED\n");

            if (debug) print("[DEBUG] Creating lexer...\n");
            var lexer = new Lexer(source);
            if (debug) print("[DEBUG] Scanning tokens...\n");
            var tokens = lexer.scan_all();
            if (debug) print("[DEBUG] Scanned %d tokens\n", tokens.size);

            if (debug) print("[DEBUG] Parsing activity diagram...\n");
            var diagram = activity_parser.parse(tokens);
            if (debug) print("[DEBUG] Parsing complete, checking for errors...\n");

            if (diagram.has_errors()) {
                if (debug) print("[DEBUG] Diagram has %d errors\n", diagram.errors.size);
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            if (debug) print("[DEBUG] No parse errors, clearing highlights\n");
            clear_error_highlights();

            if (debug) print("[DEBUG] Checking if diagram has nodes (%d nodes)...\n", diagram.nodes.size);
            if (diagram.nodes.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter activity diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "start\n" +
                    ":Hello world;\n" +
                    ":This is an action;\n" +
                    "if (condition?) then (yes)\n" +
                    "  :Action 1;\n" +
                    "else (no)\n" +
                    "  :Action 2;\n" +
                    "endif\n" +
                    "stop\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            if (debug) print("[DEBUG] Updating outline from activity diagram...\n");
            update_outline_from_activity_diagram(diagram);
            if (debug) print("[DEBUG] Outline updated\n");

            if (debug) print("[DEBUG] Calling renderer.render_activity_to_surface()...\n");
            var surface = renderer.render_activity_to_surface(diagram);
            if (debug) print("[DEBUG] Renderer returned, surface: %s\n", surface != null ? "OK" : "NULL");

            if (surface != null) {
                if (debug) print("[DEBUG] Setting surface on preview pane...\n");
                preview_pane.set_surface(surface);
                if (debug) print("[DEBUG] Transferring click regions...\n");
                transfer_click_regions();
                if (debug) print("[DEBUG] Activity diagram render COMPLETE\n");
            } else {
                if (debug) print("[DEBUG] Surface is null, showing error\n");
                preview_pane.set_placeholder_text("Failed to render activity diagram");
            }
            if (debug) print("[DEBUG] render_activity_diagram() EXITING\n");
        }

        private void render_usecase_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = usecase_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.actors.size == 0 && diagram.use_cases.size == 0 && diagram.packages.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter use case diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "left to right direction\n" +
                    "actor User\n" +
                    "actor Admin\n" +
                    "usecase \"Login\" as UC1\n" +
                    "usecase \"Manage Users\" as UC2\n" +
                    "User --> UC1\n" +
                    "Admin --> UC1\n" +
                    "Admin --> UC2\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_usecase_diagram(diagram);

            var surface = renderer.render_usecase_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render use case diagram");
            }
        }

        private void render_state_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = state_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.states.size == 0 && diagram.transitions.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter state diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "[*] --> Idle\n" +
                    "Idle --> Running : start\n" +
                    "Running --> Idle : stop\n" +
                    "Running --> [*] : error\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_state_diagram(diagram);

            var surface = renderer.render_state_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render state diagram");
            }
        }

        private void render_component_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = component_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.components.size == 0 && diagram.interfaces.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter component diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "package \"Backend\" {\n" +
                    "  [API Server]\n" +
                    "  [Database]\n" +
                    "}\n" +
                    "[Web Client] --> [API Server]\n" +
                    "[API Server] --> [Database]\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_component_diagram(diagram);

            var surface = renderer.render_component_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render component diagram");
            }
        }

        private void render_object_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = object_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.objects.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter object diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "object London {\n" +
                    "  country = \"UK\"\n" +
                    "  population = 9000000\n" +
                    "}\n" +
                    "object Paris {\n" +
                    "  country = \"France\"\n" +
                    "}\n" +
                    "London --> Paris : flight\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_object_diagram(diagram);

            var surface = renderer.render_object_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render object diagram");
            }
        }

        private void render_deployment_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = deployment_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.nodes.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter deployment diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "node \"Web Server\" {\n" +
                    "  [Apache]\n" +
                    "  [PHP]\n" +
                    "}\n" +
                    "device \"Mobile\" as mobile\n" +
                    "database \"MySQL\" as db\n" +
                    "[Apache] --> db : SQL\n" +
                    "mobile --> [Apache] : HTTP\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_deployment_diagram(diagram);

            var surface = renderer.render_deployment_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render deployment diagram");
            }
        }

        private void render_er_diagram(string source) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = er_parser.parse(tokens);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.entities.size == 0) {
                preview_pane.set_placeholder_text(
                    "Enter ER diagram code.\n\n" +
                    "Example:\n" +
                    "@startuml\n" +
                    "entity User {\n" +
                    "  *user_id : int <<PK>>\n" +
                    "  --\n" +
                    "  name : varchar\n" +
                    "  email : varchar\n" +
                    "}\n\n" +
                    "entity Order {\n" +
                    "  *order_id : int <<PK>>\n" +
                    "  --\n" +
                    "  user_id : int <<FK>>\n" +
                    "  total : decimal\n" +
                    "}\n\n" +
                    "User ||--o{ Order : places\n" +
                    "@enduml"
                );
                return;
            }

            // Update outline
            update_outline_from_er_diagram(diagram);

            var surface = renderer.render_er_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render ER diagram");
            }
        }

        private void render_mindmap_diagram(string source, DiagramType type) {
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            var diagram = mindmap_parser.parse(tokens, type);

            if (diagram.has_errors()) {
                apply_error_highlights(diagram.errors);
                var sb = new StringBuilder();
                sb.append("Parse errors:\n\n");
                foreach (var err in diagram.errors) {
                    sb.append(err.to_string());
                    sb.append("\n");
                }
                preview_pane.set_placeholder_text(sb.str);
                return;
            }

            clear_error_highlights();

            if (diagram.root == null) {
                string example = type == DiagramType.WBS ?
                    "Enter WBS diagram code.\n\n" +
                    "Example:\n" +
                    "@startwbs\n" +
                    "* Project\n" +
                    "** Phase 1\n" +
                    "*** Task 1.1\n" +
                    "*** Task 1.2\n" +
                    "** Phase 2\n" +
                    "*** Task 2.1\n" +
                    "@endwbs"
                    :
                    "Enter MindMap diagram code.\n\n" +
                    "Example:\n" +
                    "@startmindmap\n" +
                    "* Root Topic\n" +
                    "** Branch 1\n" +
                    "*** Leaf 1.1\n" +
                    "*** Leaf 1.2\n" +
                    "** Branch 2\n" +
                    "left side\n" +
                    "** Left Branch\n" +
                    "@endmindmap";

                preview_pane.set_placeholder_text(example);
                return;
            }

            // Update outline
            update_outline_from_mindmap_diagram(diagram);

            var surface = renderer.render_mindmap_to_surface(diagram);

            if (surface != null) {
                preview_pane.set_surface(surface);
                transfer_click_regions();
            } else {
                preview_pane.set_placeholder_text("Failed to render MindMap/WBS diagram");
            }
        }

        public new void grab_focus() {
            source_view.grab_focus();
        }

        // ==================== Zoom Controls ====================

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

            // Fill with white background
            cr.set_source_rgb(1, 1, 1);
            cr.rectangle(0, 0, new_width, new_height);
            cr.fill();

            // Scale and draw
            cr.scale(scale, scale);
            cr.set_source_surface(surface, 0, 0);
            cr.paint();

            // Save to PNG
            var status = scaled_surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_png(string filename) {
            string source = source_buffer.text;
            string processed_source = preprocess_source(source);
            var diagram_type = detect_diagram_type(processed_source);

            var lexer = new Lexer(processed_source);
            var tokens = lexer.scan_all();

            switch (diagram_type) {
                case DiagramType.CLASS:
                    var class_diagram = class_parser.parse(tokens);
                    if (class_diagram.has_errors() || class_diagram.classes.size == 0) {
                        return false;
                    }
                    return renderer.export_class_to_png(class_diagram, filename);

                case DiagramType.ACTIVITY:
                    var activity_diagram = activity_parser.parse(tokens);
                    if (activity_diagram.has_errors() || activity_diagram.nodes.size == 0) {
                        return false;
                    }
                    return renderer.export_activity_to_png(activity_diagram, filename);

                case DiagramType.USECASE:
                    var usecase_diagram = usecase_parser.parse(tokens);
                    if (usecase_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_usecase_to_png(usecase_diagram, filename);

                case DiagramType.STATE:
                    var state_diagram = state_parser.parse(tokens);
                    if (state_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_state_to_png(state_diagram, filename);

                case DiagramType.COMPONENT:
                    var component_diagram = component_parser.parse(tokens);
                    if (component_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_component_to_png(component_diagram, filename);

                case DiagramType.OBJECT:
                    var object_diagram = object_parser.parse(tokens);
                    if (object_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_object_to_png(object_diagram, filename);

                case DiagramType.DEPLOYMENT:
                    var deployment_diagram = deployment_parser.parse(tokens);
                    if (deployment_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_deployment_to_png(deployment_diagram, filename);

                case DiagramType.ER_DIAGRAM:
                    var er_diagram = er_parser.parse(tokens);
                    if (er_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_er_to_png(er_diagram, filename);

                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    var mm_diagram = mindmap_parser.parse(tokens, diagram_type);
                    if (mm_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_mindmap_to_png(mm_diagram, filename);

                default:
                    var seq_diagram = parser.parse(processed_source);
                    if (seq_diagram.has_errors() || seq_diagram.participants.size == 0) {
                        return false;
                    }
                    return renderer.export_to_png(seq_diagram, filename);
            }
        }

        public bool export_to_svg(string filename) {
            string source = source_buffer.text;
            string processed_source = preprocess_source(source);
            var diagram_type = detect_diagram_type(processed_source);

            var lexer = new Lexer(processed_source);
            var tokens = lexer.scan_all();

            switch (diagram_type) {
                case DiagramType.CLASS:
                    var class_diagram = class_parser.parse(tokens);
                    if (class_diagram.has_errors() || class_diagram.classes.size == 0) {
                        return false;
                    }
                    return renderer.export_class_to_svg(class_diagram, filename);

                case DiagramType.ACTIVITY:
                    var activity_diagram = activity_parser.parse(tokens);
                    if (activity_diagram.has_errors() || activity_diagram.nodes.size == 0) {
                        return false;
                    }
                    return renderer.export_activity_to_svg(activity_diagram, filename);

                case DiagramType.USECASE:
                    var usecase_diagram = usecase_parser.parse(tokens);
                    if (usecase_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_usecase_to_svg(usecase_diagram, filename);

                case DiagramType.STATE:
                    var state_diagram = state_parser.parse(tokens);
                    if (state_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_state_to_svg(state_diagram, filename);

                case DiagramType.COMPONENT:
                    var component_diagram = component_parser.parse(tokens);
                    if (component_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_component_to_svg(component_diagram, filename);

                case DiagramType.OBJECT:
                    var object_diagram = object_parser.parse(tokens);
                    if (object_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_object_to_svg(object_diagram, filename);

                case DiagramType.DEPLOYMENT:
                    var deployment_diagram = deployment_parser.parse(tokens);
                    if (deployment_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_deployment_to_svg(deployment_diagram, filename);

                case DiagramType.ER_DIAGRAM:
                    var er_diagram = er_parser.parse(tokens);
                    if (er_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_er_to_svg(er_diagram, filename);

                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    var mm_diagram = mindmap_parser.parse(tokens, diagram_type);
                    if (mm_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_mindmap_to_svg(mm_diagram, filename);

                default:
                    var seq_diagram = parser.parse(processed_source);
                    if (seq_diagram.has_errors() || seq_diagram.participants.size == 0) {
                        return false;
                    }
                    return renderer.export_to_svg(seq_diagram, filename);
            }
        }

        public bool export_to_pdf(string filename) {
            string source = source_buffer.text;
            string processed_source = preprocess_source(source);
            var diagram_type = detect_diagram_type(processed_source);

            var lexer = new Lexer(processed_source);
            var tokens = lexer.scan_all();

            switch (diagram_type) {
                case DiagramType.CLASS:
                    var class_diagram = class_parser.parse(tokens);
                    if (class_diagram.has_errors() || class_diagram.classes.size == 0) {
                        return false;
                    }
                    return renderer.export_class_to_pdf(class_diagram, filename);

                case DiagramType.ACTIVITY:
                    var activity_diagram = activity_parser.parse(tokens);
                    if (activity_diagram.has_errors() || activity_diagram.nodes.size == 0) {
                        return false;
                    }
                    return renderer.export_activity_to_pdf(activity_diagram, filename);

                case DiagramType.USECASE:
                    var usecase_diagram = usecase_parser.parse(tokens);
                    if (usecase_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_usecase_to_pdf(usecase_diagram, filename);

                case DiagramType.STATE:
                    var state_diagram = state_parser.parse(tokens);
                    if (state_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_state_to_pdf(state_diagram, filename);

                case DiagramType.COMPONENT:
                    var component_diagram = component_parser.parse(tokens);
                    if (component_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_component_to_pdf(component_diagram, filename);

                case DiagramType.OBJECT:
                    var object_diagram = object_parser.parse(tokens);
                    if (object_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_object_to_pdf(object_diagram, filename);

                case DiagramType.DEPLOYMENT:
                    var deployment_diagram = deployment_parser.parse(tokens);
                    if (deployment_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_deployment_to_pdf(deployment_diagram, filename);

                case DiagramType.ER_DIAGRAM:
                    var er_diagram = er_parser.parse(tokens);
                    if (er_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_er_to_pdf(er_diagram, filename);

                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    var mm_diagram = mindmap_parser.parse(tokens, diagram_type);
                    if (mm_diagram.has_errors()) {
                        return false;
                    }
                    return renderer.export_mindmap_to_pdf(mm_diagram, filename);

                default:
                    var seq_diagram = parser.parse(processed_source);
                    if (seq_diagram.has_errors() || seq_diagram.participants.size == 0) {
                        return false;
                    }
                    return renderer.export_to_pdf(seq_diagram, filename);
            }
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
                    content.contains("statediagram-v2")) {
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

        /**
         * Preprocess the source, expanding includes and handling preprocessor directives.
         */
        private string preprocess_source(string source) {
            string? base_path = get_document_base_path();
            return preprocessor.process(source, base_path);
        }
    }
}
