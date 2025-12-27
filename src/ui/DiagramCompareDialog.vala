namespace GDiagram {
    public class DiagramCompareDialog : Adw.Dialog {
        private GtkSource.View left_view;
        private GtkSource.Buffer left_buffer;
        private GtkSource.View right_view;
        private GtkSource.Buffer right_buffer;
        private Gtk.DrawingArea left_preview;
        private Gtk.DrawingArea right_preview;

        private GraphvizRenderer renderer;
        private Cairo.ImageSurface? left_surface = null;
        private Cairo.ImageSurface? right_surface = null;

        private Debouncer left_debouncer;
        private Debouncer right_debouncer;

        public DiagramCompareDialog(string? initial_left = null) {
            Object();
            if (initial_left != null) {
                left_buffer.text = initial_left;
            }
        }

        construct {
            title = "Compare Diagrams";
            content_width = 1200;
            content_height = 700;

            renderer = new GraphvizRenderer();
            left_debouncer = new Debouncer(300);
            right_debouncer = new Debouncer(300);

            var toolbar_view = new Adw.ToolbarView();

            var header = new Adw.HeaderBar();
            toolbar_view.add_top_bar(header);

            // Main content - two panes
            var main_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            main_box.margin_start = 6;
            main_box.margin_end = 6;
            main_box.margin_top = 6;
            main_box.margin_bottom = 6;
            main_box.homogeneous = true;

            // Left pane
            var left_pane = create_pane("Original", out left_view, out left_buffer, out left_preview, true);
            main_box.append(left_pane);

            // Separator
            var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            main_box.append(sep);

            // Right pane
            var right_pane = create_pane("Modified", out right_view, out right_buffer, out right_preview, false);
            main_box.append(right_pane);

            toolbar_view.content = main_box;
            this.child = toolbar_view;

            // Connect buffer changes
            left_buffer.changed.connect(() => {
                left_debouncer.call(() => render_left());
            });

            right_buffer.changed.connect(() => {
                right_debouncer.call(() => render_right());
            });

            // Initial sample diagrams
            left_buffer.text = """@startuml
class User {
  +name: String
  +email: String
}
class Order {
  +items: List
}
User --> Order
@enduml""";

            right_buffer.text = """@startuml
class User {
  +name: String
  +email: String
  +phone: String
}
class Order {
  +items: List
  +total: Decimal
}
class Payment {
  +amount: Decimal
}
User --> Order
Order --> Payment
@enduml""";
        }

        private Gtk.Box create_pane(string label_text, out GtkSource.View view,
                                    out GtkSource.Buffer buffer, out Gtk.DrawingArea preview,
                                    bool is_left) {
            var pane = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            pane.hexpand = true;

            // Header with label and load button
            var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            var label = new Gtk.Label(label_text);
            label.add_css_class("heading");
            label.hexpand = true;
            label.xalign = 0;
            header_box.append(label);

            var load_btn = new Gtk.Button.with_label("Load File...");
            load_btn.clicked.connect(() => {
                load_file.begin(is_left);
            });
            header_box.append(load_btn);

            pane.append(header_box);

            // Paned for source and preview
            var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
            paned.vexpand = true;
            paned.shrink_start_child = false;
            paned.shrink_end_child = false;

            // Source view
            var source_scroll = new Gtk.ScrolledWindow();
            source_scroll.add_css_class("card");
            source_scroll.min_content_height = 150;

            buffer = new GtkSource.Buffer(null);
            view = new GtkSource.View.with_buffer(buffer);
            view.monospace = true;
            view.show_line_numbers = true;
            view.top_margin = 6;
            view.bottom_margin = 6;
            view.left_margin = 6;
            view.right_margin = 6;

            // Set up syntax highlighting
            var lang_manager = GtkSource.LanguageManager.get_default();
            var language = lang_manager.get_language("plantuml");
            if (language != null) {
                buffer.language = language;
            }

            var style_manager = GtkSource.StyleSchemeManager.get_default();
            var scheme = style_manager.get_scheme("Adwaita-dark");
            if (scheme != null) {
                buffer.style_scheme = scheme;
            }

            source_scroll.child = view;
            paned.start_child = source_scroll;

            // Preview
            var preview_scroll = new Gtk.ScrolledWindow();
            preview_scroll.add_css_class("card");
            preview_scroll.vexpand = true;

            preview = new Gtk.DrawingArea();
            preview.hexpand = true;
            preview.vexpand = true;

            if (is_left) {
                preview.set_draw_func(draw_left_preview);
            } else {
                preview.set_draw_func(draw_right_preview);
            }

            preview_scroll.child = preview;
            paned.end_child = preview_scroll;
            paned.position = 200;

            pane.append(paned);

            return pane;
        }

        private void draw_left_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            draw_preview(cr, width, height, left_surface);
        }

        private void draw_right_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            draw_preview(cr, width, height, right_surface);
        }

        private void draw_preview(Cairo.Context cr, int width, int height, Cairo.ImageSurface? surface) {
            // White background
            cr.set_source_rgb(1, 1, 1);
            cr.rectangle(0, 0, width, height);
            cr.fill();

            if (surface == null) {
                cr.set_source_rgb(0.5, 0.5, 0.5);
                cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
                cr.set_font_size(12);
                cr.move_to(width / 2 - 40, height / 2);
                cr.show_text("No diagram");
                return;
            }

            // Scale to fit
            int img_width = surface.get_width();
            int img_height = surface.get_height();

            double scale_x = (double)width / img_width;
            double scale_y = (double)height / img_height;
            double scale = double.min(scale_x, scale_y) * 0.95;

            double offset_x = (width - img_width * scale) / 2;
            double offset_y = (height - img_height * scale) / 2;

            cr.translate(offset_x, offset_y);
            cr.scale(scale, scale);
            cr.set_source_surface(surface, 0, 0);
            cr.paint();
        }

        private void render_left() {
            left_surface = render_diagram(left_buffer.text);
            left_preview.queue_draw();
        }

        private void render_right() {
            right_surface = render_diagram(right_buffer.text);
            right_preview.queue_draw();
        }

        private Cairo.ImageSurface? render_diagram(string source) {
            // Detect diagram type and render
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            // Try to detect diagram type
            string lower = source.down();
            if (lower.contains("class ") || lower.contains("interface ") || lower.contains("--|>")) {
                var parser = new ClassDiagramParser();
                var diagram = parser.parse(tokens);
                if (!diagram.has_errors()) {
                    return renderer.render_class_to_surface(diagram);
                }
            }

            if (lower.contains(":") && lower.contains("activity")) {
                var parser = new ActivityDiagramParser();
                var diagram = parser.parse(tokens);
                if (!diagram.has_errors()) {
                    return renderer.render_activity_to_surface(diagram);
                }
            }

            // Default to sequence
            var preprocessor = new Preprocessor();
            string processed = preprocessor.process(source, null);
            var parser = new Parser();
            var diagram = parser.parse(processed);
            return renderer.render_to_surface(diagram);
        }

        private async void load_file(bool is_left) {
            var dialog = new Gtk.FileDialog();
            dialog.title = "Open PlantUML File";

            var filter = new Gtk.FileFilter();
            filter.name = "PlantUML files";
            filter.add_pattern("*.puml");
            filter.add_pattern("*.plantuml");
            filter.add_pattern("*.wsd");
            filter.add_pattern("*.pu");
            filter.add_pattern("*.txt");

            var filters = new ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            dialog.filters = filters;
            dialog.default_filter = filter;

            try {
                var file = yield dialog.open(null, null);
                if (file != null) {
                    uint8[] contents;
                    yield file.load_contents_async(null, out contents, null);
                    string text = (string)contents;
                    if (is_left) {
                        left_buffer.text = text;
                    } else {
                        right_buffer.text = text;
                    }
                }
            } catch (Error e) {
                if (!(e is IOError.CANCELLED)) {
                    warning("Failed to load file: %s", e.message);
                }
            }
        }
    }
}
