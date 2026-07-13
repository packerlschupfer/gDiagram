namespace GDiagram {
    [GtkTemplate(ui = "/org/gnome/gDiagram/ui/main-window.ui")]
    public class MainWindow : Adw.ApplicationWindow {
        [GtkChild]
        private unowned Adw.TabView tab_view;
        [GtkChild]
        private unowned Gtk.MenuButton recent_menu_button;

        private int untitled_count = 0;
        private RecentFilesManager recent_manager;

        public MainWindow(Application app) {
            Object(application: app);
        }

        construct {
            if (Environment.get_variable("G_MESSAGES_DEBUG") != null) {
                print("[DEBUG] MainWindow.construct() started\n");
            }
            recent_manager = new RecentFilesManager();
            recent_manager.open_requested.connect(open_file);

            ActionEntry[] action_entries = {
                { "new-tab", this.on_new_tab },
                { "open", this.on_open },
                { "save", this.on_save },
                { "save-as", this.on_save_as },
                { "close-tab", this.on_close_tab },
                { "export", this.on_export },
                { "export-png", this.on_export_png },
                { "export-svg", this.on_export_svg },
                { "export-pdf", this.on_export_pdf },
                { "print", this.on_print },
                { "zoom-in", this.on_zoom_in },
                { "zoom-out", this.on_zoom_out },
                { "zoom-reset", this.on_zoom_reset },
                { "zoom-fit", this.on_zoom_fit },
                { "show-templates", this.on_show_templates },
                { "ai-assistant", this.on_ai_assistant },
                { "compare-diagrams", this.on_compare_diagrams },
                { "git-history", this.on_git_history },
                { "git-visualizer", this.on_git_visualizer },
                { "toggle-outline", this.on_toggle_outline },
                { "beautify", this.on_beautify },
                { "convert-format", this.on_convert_format },
                { "show-shortcuts", this.on_show_shortcuts },
                { "navigate-back", this.on_navigate_back },
            };
            this.add_action_entries(action_entries, this);

            // Add action for opening recent files (with string parameter)
            var open_recent_action = new SimpleAction("open-recent", VariantType.STRING);
            open_recent_action.activate.connect((parameter) => {
                if (parameter != null) {
                    recent_manager.activate_recent(parameter.get_string(), this);
                }
            });
            this.add_action(open_recent_action);

            // Add action to clear recent files
            var clear_recent_action = new SimpleAction("clear-recent", null);
            clear_recent_action.activate.connect(() => {
                recent_manager.clear();
            });
            this.add_action(clear_recent_action);

            // Add keyboard shortcuts for zoom
            var app = this.application as Application;
            if (app != null) {
                app.set_accels_for_action("win.new-tab", {"<primary>n"});
                app.set_accels_for_action("win.open", {"<primary>o"});
                app.set_accels_for_action("win.save", {"<primary>s"});
                app.set_accels_for_action("win.save-as", {"<primary><shift>s"});
                app.set_accels_for_action("win.close-tab", {"<primary>w"});
                app.set_accels_for_action("win.export", {"<primary>e"});
                app.set_accels_for_action("win.print", {"<primary>p"});
                app.set_accels_for_action("win.zoom-in", {"<primary>plus", "<primary>equal"});
                app.set_accels_for_action("win.zoom-out", {"<primary>minus"});
                app.set_accels_for_action("win.zoom-reset", {"<primary>0"});
                app.set_accels_for_action("win.zoom-fit", {"<primary>9"});
                app.set_accels_for_action("win.toggle-outline", {"<primary>backslash"});
                app.set_accels_for_action("win.beautify", {"<primary><shift>b"});
                app.set_accels_for_action("win.compare-diagrams", {"<primary><shift>d"});
                app.set_accels_for_action("win.git-history", {"<primary><shift>h"});
                app.set_accels_for_action("win.git-visualizer", {"<primary><shift>g"});
                app.set_accels_for_action("win.navigate-back", {"<alt>Left"});
                app.set_accels_for_action("win.convert-format", {"<primary><shift>c"});
                app.set_accels_for_action("win.show-templates", {"<primary>t"});
                app.set_accels_for_action("win.ai-assistant", {"<primary><shift>a"});
                app.set_accels_for_action("win.show-shortcuts", {"<primary>question"});
            }

            // Initialize recent files menu
            recent_menu_button.menu_model = recent_manager.menu_model;

            // Create initial empty document
            create_new_document();
        }

        private void update_tab_indicator(Adw.TabPage page, Document doc) {
            if (doc.modified)
                page.indicator_icon = new ThemedIcon("media-record-symbolic");
            else if (doc.git_dirty)
                page.indicator_icon = new ThemedIcon("emblem-important-symbolic");
            else
                page.indicator_icon = null;
        }

        private void on_new_tab() {
            create_new_document();
        }

        private void create_new_document() {
            if (Environment.get_variable("G_MESSAGES_DEBUG") != null) {
                print("[DEBUG] create_new_document() called\n");
            }
            untitled_count++;
            var doc = new Document();
            doc.title = "Untitled %d".printf(untitled_count);

            if (Environment.get_variable("G_MESSAGES_DEBUG") != null) {
                print("[DEBUG] Creating DocumentView (this may take a moment)...\n");
            }
            var view = new DocumentView(doc);
            if (Environment.get_variable("G_MESSAGES_DEBUG") != null) {
                print("[DEBUG] DocumentView created successfully\n");
            }
            var page = tab_view.append(view);
            page.title = doc.title;
            page.icon = new ThemedIcon("text-x-generic");

            doc.notify["title"].connect(() => {
                page.title = doc.title;
            });
            doc.notify["modified"].connect(() => update_tab_indicator(page, doc));
            doc.notify["git_dirty"].connect(() => update_tab_indicator(page, doc));

            tab_view.set_selected_page(page);
            view.grab_focus();
        }

        public void open_file(File file) {
            open_file_with_history(file, null);
        }

        // Close the first empty, unmodified, unsaved scratch tab — but never
        // the page we just opened.
        private void close_empty_untitled_tab(Adw.TabPage keep) {
            uint n = tab_view.n_pages;
            for (uint i = 0; i < n; i++) {
                var p = tab_view.get_nth_page((int) i);
                if (p == keep) continue;
                var v = p.child as DocumentView;
                if (v == null) continue;
                var d = v.document;
                if (d.file == null && !d.modified) {
                    tab_view.close_page(p);
                    return;
                }
            }
        }

        /**
         * Open a file as a new tab. If `history` is non-null, the resulting
         * DocumentView's breadcrumb bar shows the navigation chain that led
         * here (used by the drill-down navigation).
         */
        public void open_file_with_history(File file, Gee.ArrayList<File>? history) {
            var doc = new Document();
            doc.load_from_file.begin(file, (obj, res) => {
                try {
                    doc.load_from_file.end(res);
                    var view = new DocumentView(doc);
                    if (history != null) {
                        view.apply_nav_history(history);
                    }
                    var page = tab_view.append(view);
                    page.title = doc.title;
                    page.icon = new ThemedIcon("text-x-generic");

                    doc.notify["title"].connect(() => {
                        page.title = doc.title;
                    });
                    doc.notify["modified"].connect(() => update_tab_indicator(page, doc));
                    doc.notify["git_dirty"].connect(() => update_tab_indicator(page, doc));
                    Idle.add(() => { view.refresh_git_dirty(); return false; });

                    tab_view.set_selected_page(page);

                    // Close an untouched "Untitled" scratch tab if one exists.
                    close_empty_untitled_tab(page);

                    // Add to recent files
                    string? path = file.get_path();
                    if (path != null) {
                        recent_manager.add_recent_file(path);
                    }
                } catch (Error e) {
                    var dialog = new Adw.AlertDialog(
                        "Error Opening File",
                        "Could not open %s: %s".printf(file.get_basename(), e.message)
                    );
                    dialog.add_response("ok", "OK");
                    dialog.present(this);
                }
            });
        }

        private void on_open() {
            var chooser = new Gtk.FileDialog();
            chooser.title = "Open Diagram";

            // Accept both PlantUML and Mermaid files. The old version only
            // showed *.puml/.pu/.plantuml, making .mmd files invisible in
            // the dialog unless the user toggled "show all".
            var filter = new Gtk.FileFilter();
            filter.name = "Diagram Files";
            filter.add_pattern("*.puml");
            filter.add_pattern("*.plantuml");
            filter.add_pattern("*.pu");
            filter.add_pattern("*.mmd");
            filter.add_pattern("*.mermaid");

            var filters = new ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            chooser.filters = filters;

            chooser.open.begin(this, null, (obj, res) => {
                try {
                    var file = chooser.open.end(res);
                    if (file != null) {
                        open_file(file);
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        warning("File open error: %s", e.message);
                    }
                }
            });
        }

        private void on_save() {
            var page = tab_view.selected_page;
            if (page == null) return;

            var view = page.child as DocumentView;
            if (view == null) return;

            if (view.document.file == null) {
                on_save_as();
            } else {
                view.document.save.begin((obj, res) => {
                    try {
                        view.document.save.end(res);
                        view.refresh_git_dirty();
                    } catch (Error e) {
                        var dialog = new Adw.AlertDialog(
                            "Error Saving File",
                            e.message
                        );
                        dialog.add_response("ok", "OK");
                        dialog.present(this);
                    }
                });
            }
        }

        private void on_save_as() {
            var page = tab_view.selected_page;
            if (page == null) return;

            var view = page.child as DocumentView;
            if (view == null) return;

            var chooser = new Gtk.FileDialog();
            chooser.title = "Save Diagram";
            // Preserve an existing diagram extension when present; otherwise
            // pick .mmd for Mermaid-looking source and .puml for PlantUML.
            // The old version unconditionally appended .puml to titles like
            // "foo.mmd", producing "foo.mmd.puml".
            string t = view.document.title;
            if (t.has_suffix(".puml") || t.has_suffix(".pu") ||
                t.has_suffix(".plantuml") || t.has_suffix(".mmd") ||
                t.has_suffix(".mermaid")) {
                chooser.initial_name = t;
            } else {
                // Sniff the source: Mermaid diagrams start with one of
                // several well-known keywords; default to PlantUML.
                string src_head = view.document.content.strip().down();
                bool is_mermaid = src_head.has_prefix("flowchart") ||
                    src_head.has_prefix("sequencediagram") ||
                    src_head.has_prefix("classdiagram") ||
                    src_head.has_prefix("statediagram") ||
                    src_head.has_prefix("erdiagram") ||
                    src_head.has_prefix("gantt") ||
                    src_head.has_prefix("pie") ||
                    src_head.has_prefix("journey") ||
                    src_head.has_prefix("gitgraph") ||
                    src_head.has_prefix("mindmap") ||
                    src_head.has_prefix("timeline") ||
                    src_head.has_prefix("quadrantchart") ||
                    src_head.has_prefix("xychart") ||
                    src_head.has_prefix("kanban") ||
                    src_head.has_prefix("sankey") ||
                    src_head.has_prefix("requirementdiagram") ||
                    src_head.has_prefix("block-beta") ||
                    src_head.has_prefix("packet-beta") ||
                    src_head.has_prefix("c4context") ||
                    src_head.has_prefix("c4container") ||
                    src_head.has_prefix("c4component") ||
                    src_head.has_prefix("architecture-beta") ||
                    src_head.has_prefix("zenuml") ||
                    src_head.has_prefix("radar-beta") ||
                    src_head.has_prefix("treemap-beta");
                chooser.initial_name = t + (is_mermaid ? ".mmd" : ".puml");
            }

            chooser.save.begin(this, null, (obj, res) => {
                try {
                    var file = chooser.save.end(res);
                    if (file != null) {
                        view.document.file = file;
                        view.document.save.begin((obj2, res2) => {
                            try {
                                view.document.save.end(res2);
                                view.refresh_git_dirty();
                            } catch (Error e) {
                                var dialog = new Adw.AlertDialog(
                                    "Error Saving File",
                                    e.message
                                );
                                dialog.add_response("ok", "OK");
                                dialog.present(this);
                            }
                        });
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        warning("File save error: %s", e.message);
                    }
                }
            });
        }

        /**
         * Alt+Left handler — navigates the active tab one step up its
         * drill-down breadcrumb chain. No-op if the active view has no
         * navigation history.
         */
        private void on_navigate_back() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) {
                view.navigate_back();
            }
        }

        private void on_close_tab() {
            var page = tab_view.selected_page;
            if (page == null) return;

            var view = page.child as DocumentView;
            if (view != null && view.document.modified) {
                var dialog = new Adw.AlertDialog(
                    "Save Changes?",
                    "Do you want to save changes to \"%s\"?".printf(view.document.title)
                );
                dialog.add_response("discard", "Discard");
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("save", "Save");
                dialog.set_response_appearance("discard", Adw.ResponseAppearance.DESTRUCTIVE);
                dialog.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED);
                dialog.default_response = "save";
                dialog.close_response = "cancel";

                dialog.response.connect((response) => {
                    if (response == "save") {
                        if (view.document.file == null) {
                            on_save_as();
                        } else {
                            view.document.save.begin((obj, res) => {
                                try {
                                    view.document.save.end(res);
                                    tab_view.close_page(page);
                                } catch (Error e) {
                                    warning("Save error: %s", e.message);
                                }
                            });
                        }
                    } else if (response == "discard") {
                        tab_view.close_page(page);
                    }
                });
                dialog.present(this);
            } else {
                tab_view.close_page(page);
            }
        }

        private void on_export() {
            var page = tab_view.selected_page;
            if (page == null) return;

            var view = page.child as DocumentView;
            if (view == null) return;

            var surface = view.get_preview_surface();
            var dialog = new ExportDialog(surface, view.document.title);

            dialog.export_requested.connect((format, scale, filename, transparent) => {
                // Transparent-background export: swap the active palette for
                // a clone with background="transparent" during the export,
                // then restore. Renderers read background on each render, so
                // this transparently (heh) affects the emitted DOT.
                Palette? saved_palette = null;
                if (transparent) {
                    saved_palette = ThemeManager.get_active_palette();
                    var temp = saved_palette.clone();
                    temp.background = "transparent";
                    ThemeManager.set_active_palette(temp);
                    // export_to_png_scaled operates on the current preview
                    // surface, so we need to re-render the preview with the
                    // transparent palette before taking the scaled snapshot.
                    view.render_preview_now();
                }

                bool success = false;
                switch (format) {
                    case "png":
                        success = view.export_to_png_scaled(filename, scale);
                        break;
                    case "svg":
                        success = view.export_to_svg(filename);
                        break;
                    case "pdf":
                        success = view.export_to_pdf(filename);
                        break;
                }

                if (saved_palette != null) {
                    ThemeManager.set_active_palette(saved_palette);
                    view.render_preview_now();
                }

                if (success) {
                    var toast_dialog = new Adw.AlertDialog("Success",
                        "Exported to %s".printf(Path.get_basename(filename)));
                    toast_dialog.add_response("ok", "OK");
                    toast_dialog.present(this);
                } else {
                    var error_dialog = new Adw.AlertDialog("Export Failed",
                        "Could not export diagram. Make sure it has valid content.");
                    error_dialog.add_response("ok", "OK");
                    error_dialog.present(this);
                }
            });

            dialog.present(this);
        }

        private void on_export_png() {
            export_diagram("png", "PNG Image", "*.png");
        }

        private void on_export_svg() {
            export_diagram("svg", "SVG Image", "*.svg");
        }

        private void on_export_pdf() {
            export_diagram("pdf", "PDF Document", "*.pdf");
        }

        private void export_diagram(string format, string filter_name, string pattern) {
            var page = tab_view.selected_page;
            if (page == null) return;

            var view = page.child as DocumentView;
            if (view == null) return;

            var chooser = new Gtk.FileDialog();
            chooser.title = "Export as %s".printf(format.up());

            // Set initial filename based on document title
            string base_name = view.document.title;
            if (base_name.has_suffix(".puml")) {
                base_name = base_name.substring(0, base_name.length - 5);
            } else if (base_name.has_suffix(".mmd")) {
                base_name = base_name.substring(0, base_name.length - 4);
            }
            chooser.initial_name = "%s.%s".printf(base_name, format);

            var filter = new Gtk.FileFilter();
            filter.name = filter_name;
            filter.add_pattern(pattern);

            var filters = new ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            chooser.filters = filters;

            chooser.save.begin(this, null, (obj, res) => {
                try {
                    var file = chooser.save.end(res);
                    if (file != null) {
                        string path = file.get_path();
                        bool success = false;

                        switch (format) {
                            case "png":
                                success = view.export_to_png(path);
                                break;
                            case "svg":
                                success = view.export_to_svg(path);
                                break;
                            case "pdf":
                                success = view.export_to_pdf(path);
                                break;
                        }

                        if (success) {
                            var toast = new Adw.Toast("Exported to %s".printf(file.get_basename()));
                            toast.timeout = 3;
                            // Find the toast overlay - we need to add one
                            show_toast(toast);
                        } else {
                            var dialog = new Adw.AlertDialog(
                                "Export Failed",
                                "Could not export diagram. Make sure it has valid PlantUML content."
                            );
                            dialog.add_response("ok", "OK");
                            dialog.present(this);
                        }
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        warning("Export error: %s", e.message);
                    }
                }
            });
        }

        private void show_toast(Adw.Toast toast) {
            // Simple notification via dialog for now
            var dialog = new Adw.AlertDialog("Success", toast.title);
            dialog.add_response("ok", "OK");
            dialog.present(this);
        }

        // ==================== Print ====================

        private void on_print() {
            var page = tab_view.selected_page;
            if (page == null) return;

            var view = page.child as DocumentView;
            if (view == null) return;

            var surface = view.get_preview_surface();
            if (surface == null) {
                var dialog = new Adw.AlertDialog(
                    "Nothing to Print",
                    "Please create a diagram first."
                );
                dialog.add_response("ok", "OK");
                dialog.present(this);
                return;
            }

            // Export SVG to a temp file for vector-quality printing
            string tmp_svg = Path.build_filename(
                Environment.get_tmp_dir(), "_gdiagram_print.svg");
            bool have_svg = view.export_to_svg(tmp_svg);

            var print_op = new Gtk.PrintOperation();
            print_op.n_pages = 1;
            print_op.job_name = view.document.title;

            print_op.draw_page.connect((context, page_nr) => {
                var cr = context.get_cairo_context();
                double page_width = context.get_width();
                double page_height = context.get_height();

                if (have_svg) {
                    // Render SVG at printer native resolution via librsvg
                    try {
                        uint8[] svg_bytes;
                        FileUtils.get_data(tmp_svg, out svg_bytes);
                        var stream = new MemoryInputStream.from_data(svg_bytes);
                        var handle = new Rsvg.Handle.from_stream_sync(
                            stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                        double img_w, img_h;
                        handle.get_intrinsic_size_in_pixels(out img_w, out img_h);
                        if (img_w <= 0) img_w = page_width;
                        if (img_h <= 0) img_h = page_height;

                        // Scale to fit with 5% margins
                        double avail_w = page_width  * 0.90;
                        double avail_h = page_height * 0.90;
                        double scale = double.min(avail_w / img_w, avail_h / img_h);
                        double x = (page_width  - img_w * scale) / 2;
                        double y = (page_height - img_h * scale) / 2;

                        cr.save();
                        cr.translate(x, y);
                        cr.scale(scale, scale);
                        var viewport = Rsvg.Rectangle() {
                            x = 0, y = 0, width = img_w, height = img_h
                        };
                        handle.render_document(cr, viewport);
                        cr.restore();
                        return;
                    } catch (Error e) {
                        warning("SVG print render failed: %s — falling back to raster", e.message);
                    }
                }

                // Fallback: scale the raster preview surface to fit
                int img_width  = surface.get_width();
                int img_height = surface.get_height();
                double scale_x = page_width  / img_width;
                double scale_y = page_height / img_height;
                double scale   = double.min(scale_x, scale_y) * 0.90;
                double x = (page_width  - img_width  * scale) / 2;
                double y = (page_height - img_height * scale) / 2;

                cr.translate(x, y);
                cr.scale(scale, scale);
                cr.set_source_surface(surface, 0, 0);
                cr.paint();
            });

            try {
                print_op.run(Gtk.PrintOperationAction.PRINT_DIALOG, this);
            } catch (Error e) {
                var dialog = new Adw.AlertDialog("Print Error", e.message);
                dialog.add_response("ok", "OK");
                dialog.present(this);
            }

            // Clean up temp file
            if (have_svg) FileUtils.unlink(tmp_svg);
        }

        // ==================== Zoom ====================

        private void on_zoom_in() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) view.zoom_in();
        }

        private void on_zoom_out() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) view.zoom_out();
        }

        private void on_zoom_reset() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) view.zoom_reset();
        }

        private void on_zoom_fit() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) view.zoom_fit();
        }

        // ==================== Recent Files ====================

        public void add_recent_file(string path) {
            recent_manager.add_recent_file(path);
        }

        public Gee.ArrayList<string> get_recent_files() {
            return recent_manager.get_recent_files();
        }

        // ==================== Templates ====================

        private void on_show_templates() {
            var gallery = new TemplateGallery();
            gallery.template_chosen.connect(use_template);
            gallery.present(this);
        }

        private void use_template(string template) {
            // Create new document with template
            untitled_count++;
            var doc = new Document();
            doc.title = "Untitled %d".printf(untitled_count);
            doc.content = template;

            var view = new DocumentView(doc);
            var page = tab_view.append(view);
            page.title = doc.title;
            page.icon = new ThemedIcon("text-x-generic");

            doc.notify["title"].connect(() => {
                page.title = doc.title;
            });
            doc.notify["modified"].connect(() => update_tab_indicator(page, doc));
            doc.notify["git_dirty"].connect(() => update_tab_indicator(page, doc));

            tab_view.set_selected_page(page);
            view.grab_focus();

            // Close the initial empty "Untitled 1" tab if the user hasn't
            // touched it — same behaviour as opening a file from disk.
            close_empty_untitled_tab(page);
        }

        // ==================== Convert Format ====================

        private void on_convert_format() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view == null) return;

            string source = view.document.content;
            string lower = source.down();

            // Auto-detect current format and offer opposite
            string? converted = null;
            string target_format;

            if (lower.contains("@startuml")) {
                converted = FormatConverter.auto_convert(source, "mermaid");
                target_format = "Mermaid";
            } else {
                converted = FormatConverter.auto_convert(source, "plantuml");
                target_format = "PlantUML";
            }

            if (converted == null) {
                var dialog = new Adw.AlertDialog("Cannot Convert",
                    "This diagram type cannot be automatically converted. " +
                    "Supported conversions: sequence and class diagrams between PlantUML and Mermaid.");
                dialog.add_response("ok", "OK");
                dialog.present(this);
                return;
            }

            // Open converted diagram in a new tab
            untitled_count++;
            var doc = new Document();
            doc.title = "Converted to %s %d".printf(target_format, untitled_count);
            doc.content = converted;
            doc.modified = true;

            var new_view = new DocumentView(doc);
            var new_page = tab_view.append(new_view);
            new_page.title = doc.title;
            new_page.icon = new ThemedIcon("document-new-symbolic");
            tab_view.selected_page = new_page;
        }

        // ==================== Beautify Source ====================

        private void on_beautify() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) {
                view.beautify_source();
            }
        }

        // ==================== AI Assistant ====================

        private void on_ai_assistant() {
            var dialog = new AIAssistantDialog();

            dialog.diagram_generated.connect((code) => {
                // Create new document with generated code
                untitled_count++;
                var doc = new Document();
                doc.title = "AI Generated %d".printf(untitled_count);
                doc.content = code;

                var view = new DocumentView(doc);
                var page = tab_view.append(view);
                page.title = doc.title;
                page.icon = new ThemedIcon("starred-symbolic");

                doc.notify["title"].connect(() => {
                    page.title = doc.title;
                });
                doc.notify["modified"].connect(() => update_tab_indicator(page, doc));
                doc.notify["git_dirty"].connect(() => update_tab_indicator(page, doc));

                tab_view.set_selected_page(page);
                view.grab_focus();
            });

            dialog.present(this);
        }

        // ==================== Compare Diagrams ====================

        private void on_toggle_outline() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view != null) {
                view.toggle_outline_visibility();
            }
        }

        private void on_compare_diagrams() {
            // Get current document content if available
            string? current_content = null;
            var page = tab_view.selected_page;
            if (page != null) {
                var view = page.child as DocumentView;
                if (view != null) {
                    current_content = view.document.content;
                }
            }

            var dialog = new DiagramCompareDialog(current_content);
            dialog.present(this);
        }

        private void on_git_history() {
            var page = tab_view.selected_page;
            if (page == null) return;
            var view = page.child as DocumentView;
            if (view == null) return;

            if (view.document.file == null) {
                var dlg = new Adw.AlertDialog("No File", "Save the file first to view git history.");
                dlg.add_response("ok", "OK");
                dlg.present(this);
                return;
            }

            string file_path    = view.document.file.get_path();
            string cur_content  = view.document.content;
            var dialog = new GitHistoryDialog(file_path, cur_content);
            dialog.restore_requested.connect((content) => {
                view.document.content = content;
                view.document.modified = true;
            });
            dialog.present(this);
        }

        private void on_git_visualizer() {
            var chooser = new Gtk.FileDialog();
            chooser.title = "Open Git Repository";
            chooser.select_folder.begin(this, null, (obj, res) => {
                try {
                    var folder = chooser.select_folder.end(res);
                    if (folder == null) return;
                    string dir = folder.get_path();
                    var view = new GitRepoView(dir);
                    if (view.repo_graph.repo_root == null) {
                        var dlg = new Adw.AlertDialog("Not a Git Repository",
                            "The selected folder is not inside a git repository.");
                        dlg.add_response("ok", "OK");
                        dlg.present(this);
                        return;
                    }
                    var page = tab_view.append(view);
                    string name = Path.get_basename(view.repo_graph.repo_root);
                    page.title = name;
                    page.icon = new ThemedIcon("vcs-branch-symbolic");
                    tab_view.selected_page = page;
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        warning("Git repo open error: %s", e.message);
                    }
                }
            });
        }

        private void on_show_shortcuts() {
            var builder = new Gtk.Builder.from_resource("/org/gnome/gDiagram/ui/shortcuts-window.ui");
            var window = (Gtk.ShortcutsWindow) builder.get_object("shortcuts_window");
            window.transient_for = this;
            window.present();
        }
    }
}
