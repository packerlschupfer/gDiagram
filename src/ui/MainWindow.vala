namespace GDiagram {
    [GtkTemplate(ui = "/org/gnome/gDiagram/ui/main-window.ui")]
    public class MainWindow : Adw.ApplicationWindow {
        [GtkChild]
        private unowned Adw.TabView tab_view;
        [GtkChild]
        private unowned Gtk.MenuButton recent_menu_button;

        private int untitled_count = 0;
        private Gee.ArrayList<string> recent_files;
        private const int MAX_RECENT_FILES = 10;
        private Menu recent_files_menu;

        public MainWindow(Application app) {
            Object(application: app);
        }

        construct {
            recent_files = new Gee.ArrayList<string>();
            load_recent_files();

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
                { "toggle-outline", this.on_toggle_outline },
            };
            this.add_action_entries(action_entries, this);

            // Add action for opening recent files (with string parameter)
            var open_recent_action = new SimpleAction("open-recent", VariantType.STRING);
            open_recent_action.activate.connect(on_open_recent);
            this.add_action(open_recent_action);

            // Add action to clear recent files
            var clear_recent_action = new SimpleAction("clear-recent", null);
            clear_recent_action.activate.connect(() => {
                recent_files.clear();
                save_recent_files();
                update_recent_files_menu();
            });
            this.add_action(clear_recent_action);

            // Add keyboard shortcuts for zoom
            var app = this.application as Application;
            if (app != null) {
                app.set_accels_for_action("win.print", {"<primary>p"});
                app.set_accels_for_action("win.zoom-in", {"<primary>plus", "<primary>equal"});
                app.set_accels_for_action("win.zoom-out", {"<primary>minus"});
                app.set_accels_for_action("win.zoom-reset", {"<primary>0"});
                app.set_accels_for_action("win.zoom-fit", {"<primary>9"});
                app.set_accels_for_action("win.toggle-outline", {"<primary>backslash"});
            }

            // Initialize recent files menu
            recent_files_menu = new Menu();
            update_recent_files_menu();
            recent_menu_button.menu_model = recent_files_menu;

            // Create initial empty document
            create_new_document();
        }

        private void on_new_tab() {
            create_new_document();
        }

        private void create_new_document() {
            untitled_count++;
            var doc = new Document();
            doc.title = "Untitled %d".printf(untitled_count);

            var view = new DocumentView(doc);
            var page = tab_view.append(view);
            page.title = doc.title;
            page.icon = new ThemedIcon("text-x-generic");

            doc.notify["title"].connect(() => {
                page.title = doc.title;
            });
            doc.notify["modified"].connect(() => {
                page.indicator_icon = doc.modified ? new ThemedIcon("media-record-symbolic") : null;
            });

            tab_view.set_selected_page(page);
            view.grab_focus();
        }

        public void open_file(File file) {
            var doc = new Document();
            doc.load_from_file.begin(file, (obj, res) => {
                try {
                    doc.load_from_file.end(res);
                    var view = new DocumentView(doc);
                    var page = tab_view.append(view);
                    page.title = doc.title;
                    page.icon = new ThemedIcon("text-x-generic");

                    doc.notify["title"].connect(() => {
                        page.title = doc.title;
                    });
                    doc.notify["modified"].connect(() => {
                        page.indicator_icon = doc.modified ? new ThemedIcon("media-record-symbolic") : null;
                    });

                    tab_view.set_selected_page(page);

                    // Add to recent files
                    string? path = file.get_path();
                    if (path != null) {
                        add_recent_file(path);
                        update_recent_files_menu();
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
            chooser.title = "Open PlantUML File";

            var filter = new Gtk.FileFilter();
            filter.name = "PlantUML Files";
            filter.add_pattern("*.puml");
            filter.add_pattern("*.plantuml");
            filter.add_pattern("*.pu");

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
            chooser.title = "Save PlantUML File";
            chooser.initial_name = view.document.title.has_suffix(".puml")
                ? view.document.title
                : view.document.title + ".puml";

            chooser.save.begin(this, null, (obj, res) => {
                try {
                    var file = chooser.save.end(res);
                    if (file != null) {
                        view.document.file = file;
                        view.document.save.begin((obj2, res2) => {
                            try {
                                view.document.save.end(res2);
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

            dialog.export_requested.connect((format, scale, filename) => {
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

            var print_op = new Gtk.PrintOperation();
            print_op.n_pages = 1;
            print_op.job_name = view.document.title;

            print_op.draw_page.connect((context, page_nr) => {
                var cr = context.get_cairo_context();
                double page_width = context.get_width();
                double page_height = context.get_height();

                int img_width = surface.get_width();
                int img_height = surface.get_height();

                // Scale to fit page
                double scale_x = page_width / img_width;
                double scale_y = page_height / img_height;
                double scale = double.min(scale_x, scale_y) * 0.95;

                // Center on page
                double x = (page_width - img_width * scale) / 2;
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

        private void load_recent_files() {
            var config_dir = Environment.get_user_config_dir();
            var recent_file = Path.build_filename(config_dir, "gplantuml", "recent_files.txt");

            try {
                string contents;
                if (FileUtils.get_contents(recent_file, out contents)) {
                    foreach (var line in contents.split("\n")) {
                        if (line.strip().length > 0 && FileUtils.test(line, FileTest.EXISTS)) {
                            recent_files.add(line.strip());
                        }
                    }
                }
            } catch (Error e) {
                // No recent files yet
            }
        }

        private void save_recent_files() {
            var config_dir = Environment.get_user_config_dir();
            var app_config = Path.build_filename(config_dir, "gplantuml");

            try {
                DirUtils.create_with_parents(app_config, 0755);
                var recent_file = Path.build_filename(app_config, "recent_files.txt");
                var contents = string.joinv("\n", recent_files.to_array());
                FileUtils.set_contents(recent_file, contents);
            } catch (Error e) {
                warning("Could not save recent files: %s", e.message);
            }
        }

        public void add_recent_file(string path) {
            // Remove if already exists
            recent_files.remove(path);
            // Add to front
            recent_files.insert(0, path);
            // Keep max size
            while (recent_files.size > MAX_RECENT_FILES) {
                recent_files.remove_at(recent_files.size - 1);
            }
            save_recent_files();
        }

        public Gee.ArrayList<string> get_recent_files() {
            return recent_files;
        }

        private void on_open_recent(Variant? parameter) {
            if (parameter == null) return;
            string path = parameter.get_string();
            if (path.length > 0) {
                var file = File.new_for_path(path);
                if (file.query_exists()) {
                    open_file(file);
                } else {
                    // File no longer exists, remove from recent
                    recent_files.remove(path);
                    save_recent_files();
                    update_recent_files_menu();

                    var dialog = new Adw.AlertDialog(
                        "File Not Found",
                        "The file \"%s\" no longer exists.".printf(Path.get_basename(path))
                    );
                    dialog.add_response("ok", "OK");
                    dialog.present(this);
                }
            }
        }

        private void update_recent_files_menu() {
            // Clear and rebuild the menu
            recent_files_menu.remove_all();

            if (recent_files.size == 0) {
                // Add "No Recent Files" placeholder
                recent_files_menu.append("No Recent Files", null);
            } else {
                // Add recent files section
                var files_section = new Menu();
                foreach (var path in recent_files) {
                    string basename = Path.get_basename(path);
                    var item = new MenuItem(basename, null);
                    item.set_action_and_target_value("win.open-recent", new Variant.string(path));
                    files_section.append_item(item);
                }
                recent_files_menu.append_section(null, files_section);

                // Add clear option in separate section
                var clear_section = new Menu();
                clear_section.append("Clear Recent Files", "win.clear-recent");
                recent_files_menu.append_section(null, clear_section);
            }
        }

        // ==================== Templates ====================

        private void on_show_templates() {
            var dialog = new Adw.Dialog();
            dialog.title = "Template Gallery";
            dialog.content_width = 600;
            dialog.content_height = 500;

            var toolbar_view = new Adw.ToolbarView();

            var header = new Adw.HeaderBar();
            toolbar_view.add_top_bar(header);

            var scroll = new Gtk.ScrolledWindow();
            scroll.hexpand = true;
            scroll.vexpand = true;

            var flowbox = new Gtk.FlowBox();
            flowbox.selection_mode = Gtk.SelectionMode.SINGLE;
            flowbox.homogeneous = true;
            flowbox.min_children_per_line = 2;
            flowbox.max_children_per_line = 4;
            flowbox.column_spacing = 12;
            flowbox.row_spacing = 12;
            flowbox.margin_start = 12;
            flowbox.margin_end = 12;
            flowbox.margin_top = 12;
            flowbox.margin_bottom = 12;

            // Add templates
            add_template_item(flowbox, "Class Diagram", "class-diagram", CLASS_DIAGRAM_TEMPLATE);
            add_template_item(flowbox, "Sequence Diagram", "sequence-diagram", SEQUENCE_DIAGRAM_TEMPLATE);
            add_template_item(flowbox, "Activity Diagram", "activity-diagram", ACTIVITY_DIAGRAM_TEMPLATE);
            add_template_item(flowbox, "State Diagram", "state-diagram", STATE_DIAGRAM_TEMPLATE);
            add_template_item(flowbox, "Use Case Diagram", "usecase-diagram", USECASE_DIAGRAM_TEMPLATE);
            add_template_item(flowbox, "Component Diagram", "component-diagram", COMPONENT_DIAGRAM_TEMPLATE);

            flowbox.child_activated.connect((child) => {
                var box = child.child as Gtk.Box;
                if (box != null) {
                    var template_name = box.get_data<string>("template");
                    if (template_name != null) {
                        use_template(template_name);
                        dialog.close();
                    }
                }
            });

            scroll.child = flowbox;
            toolbar_view.content = scroll;
            dialog.child = toolbar_view;
            dialog.present(this);
        }

        private void add_template_item(Gtk.FlowBox flowbox, string title, string id, string template) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            box.width_request = 120;
            box.set_data("template", template);

            var icon = new Gtk.Image.from_icon_name("text-x-generic-symbolic");
            icon.pixel_size = 48;
            icon.margin_top = 12;
            box.append(icon);

            var label = new Gtk.Label(title);
            label.wrap = true;
            label.justify = Gtk.Justification.CENTER;
            label.margin_bottom = 12;
            box.append(label);

            flowbox.append(box);
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
            doc.notify["modified"].connect(() => {
                page.indicator_icon = doc.modified ? new ThemedIcon("media-record-symbolic") : null;
            });

            tab_view.set_selected_page(page);
            view.grab_focus();
        }

        // ==================== Templates Content ====================

        private const string CLASS_DIAGRAM_TEMPLATE = """@startuml
title Class Diagram Example

class Animal {
    +name: String
    +age: int
    +eat()
    +sleep()
}

class Dog {
    +breed: String
    +bark()
}

class Cat {
    +color: String
    +meow()
}

Animal <|-- Dog
Animal <|-- Cat
@enduml""";

        private const string SEQUENCE_DIAGRAM_TEMPLATE = """@startuml
title Sequence Diagram Example

actor User
participant "Web App" as App
participant "API Server" as API
database "Database" as DB

User -> App : Request page
App -> API : GET /data
API -> DB : Query
DB --> API : Results
API --> App : JSON response
App --> User : Rendered page
@enduml""";

        private const string ACTIVITY_DIAGRAM_TEMPLATE = """@startuml
title Activity Diagram Example

start
:Receive order;
if (In stock?) then (yes)
    :Process order;
    :Ship order;
else (no)
    :Notify customer;
    :Reorder from supplier;
endif
:Update inventory;
stop
@enduml""";

        private const string STATE_DIAGRAM_TEMPLATE = """@startuml
title State Diagram Example

[*] --> Idle

Idle --> Processing : Start
Processing --> Completed : Success
Processing --> Failed : Error

Completed --> [*]
Failed --> Idle : Retry

state Processing {
    [*] --> Validating
    Validating --> Executing
    Executing --> [*]
}
@enduml""";

        private const string USECASE_DIAGRAM_TEMPLATE = """@startuml
title Use Case Diagram Example

left to right direction

actor Customer
actor Admin

rectangle "Online Store" {
    usecase "Browse Products" as UC1
    usecase "Add to Cart" as UC2
    usecase "Checkout" as UC3
    usecase "Manage Inventory" as UC4
    usecase "Process Orders" as UC5
}

Customer --> UC1
Customer --> UC2
Customer --> UC3
Admin --> UC4
Admin --> UC5
UC3 ..> UC2 : <<include>>
@enduml""";

        private const string COMPONENT_DIAGRAM_TEMPLATE = """@startuml
title Component Diagram Example

package "Frontend" {
    [Web App] as webapp
    [Mobile App] as mobile
}

package "Backend" {
    [API Gateway] as gateway
    [Auth Service] as auth
    [User Service] as users
    [Order Service] as orders
}

database "PostgreSQL" as db

webapp --> gateway
mobile --> gateway
gateway --> auth
gateway --> users
gateway --> orders
users --> db
orders --> db
@enduml""";

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
                doc.notify["modified"].connect(() => {
                    page.indicator_icon = doc.modified ? new ThemedIcon("media-record-symbolic") : null;
                });

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
    }
}
