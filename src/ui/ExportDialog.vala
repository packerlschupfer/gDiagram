namespace GPlantUML {
    public class ExportDialog : Adw.Dialog {
        private Gtk.DropDown format_dropdown;
        private Gtk.SpinButton scale_spin;
        private Gtk.Label size_label;
        private Gtk.Button export_button;

        private Cairo.ImageSurface? source_surface;
        private string document_title;

        public signal void export_requested(string format, double scale, string filename);

        public ExportDialog(Cairo.ImageSurface? surface, string title) {
            this.source_surface = surface;
            this.document_title = title;

            this.title = "Export Diagram";
            this.content_width = 400;
            this.content_height = 300;

            build_ui();
            update_size_preview();
        }

        private void build_ui() {
            var toolbar_view = new Adw.ToolbarView();

            var header = new Adw.HeaderBar();
            header.show_end_title_buttons = false;
            header.show_start_title_buttons = false;

            var cancel_btn = new Gtk.Button.with_label("Cancel");
            cancel_btn.clicked.connect(() => this.close());
            header.pack_start(cancel_btn);

            export_button = new Gtk.Button.with_label("Export");
            export_button.add_css_class("suggested-action");
            export_button.clicked.connect(on_export_clicked);
            export_button.sensitive = source_surface != null;
            header.pack_end(export_button);

            toolbar_view.add_top_bar(header);

            // Content
            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            content_box.margin_start = 24;
            content_box.margin_end = 24;
            content_box.margin_top = 24;
            content_box.margin_bottom = 24;

            // Preferences group
            var prefs_group = new Adw.PreferencesGroup();
            prefs_group.title = "Export Options";

            // Format selection
            var format_row = new Adw.ComboRow();
            format_row.title = "Format";
            format_row.subtitle = "Output file format";

            var formats = new Gtk.StringList(null);
            formats.append("PNG Image");
            formats.append("SVG Vector");
            formats.append("PDF Document");
            format_row.model = formats;
            format_row.selected = 0;

            prefs_group.add(format_row);

            // Scale factor
            var scale_row = new Adw.ActionRow();
            scale_row.title = "Scale";
            scale_row.subtitle = "Export resolution multiplier";

            var scale_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            scale_box.valign = Gtk.Align.CENTER;

            scale_spin = new Gtk.SpinButton.with_range(0.5, 4.0, 0.5);
            scale_spin.value = 1.0;
            scale_spin.digits = 1;
            scale_spin.value_changed.connect(update_size_preview);
            scale_box.append(scale_spin);

            var scale_label = new Gtk.Label("x");
            scale_label.add_css_class("dim-label");
            scale_box.append(scale_label);

            scale_row.add_suffix(scale_box);
            prefs_group.add(scale_row);

            // Output size preview
            var size_row = new Adw.ActionRow();
            size_row.title = "Output Size";
            size_row.subtitle = "Resulting image dimensions";

            size_label = new Gtk.Label("");
            size_label.add_css_class("dim-label");
            size_label.valign = Gtk.Align.CENTER;
            size_row.add_suffix(size_label);
            prefs_group.add(size_row);

            content_box.append(prefs_group);

            // Info label
            if (source_surface == null) {
                var info_label = new Gtk.Label("No diagram to export. Create a valid diagram first.");
                info_label.add_css_class("dim-label");
                info_label.wrap = true;
                info_label.margin_top = 24;
                content_box.append(info_label);
            }

            toolbar_view.content = content_box;
            this.child = toolbar_view;

            // Store format dropdown reference
            this.format_dropdown = null; // Using format_row.selected instead
            format_row.notify["selected"].connect(() => {
                // SVG and PDF don't need scale
                bool is_raster = format_row.selected == 0;
                scale_spin.sensitive = is_raster;
                update_size_preview();
            });

            // Store reference for export
            format_row.set_data("format_index", format_row);
        }

        private void update_size_preview() {
            if (source_surface == null) {
                size_label.label = "N/A";
                return;
            }

            int base_width = source_surface.get_width();
            int base_height = source_surface.get_height();
            double scale = scale_spin.value;

            int output_width = (int)(base_width * scale);
            int output_height = (int)(base_height * scale);

            size_label.label = "%d × %d px".printf(output_width, output_height);
        }

        private void on_export_clicked() {
            // Get format from the combo row
            var content = ((Adw.ToolbarView)this.child).content;
            var box = (Gtk.Box)content;
            var prefs_group = (Adw.PreferencesGroup)box.get_first_child();
            var format_row = (Adw.ComboRow)prefs_group.get_first_child();

            uint format_index = format_row.selected;
            string format;
            string extension;
            string filter_name;

            switch (format_index) {
                case 1:
                    format = "svg";
                    extension = ".svg";
                    filter_name = "SVG Vector";
                    break;
                case 2:
                    format = "pdf";
                    extension = ".pdf";
                    filter_name = "PDF Document";
                    break;
                default:
                    format = "png";
                    extension = ".png";
                    filter_name = "PNG Image";
                    break;
            }

            // Show file chooser
            var chooser = new Gtk.FileDialog();
            chooser.title = "Export as %s".printf(format.up());

            // Set initial filename
            string base_name = document_title;
            if (base_name.has_suffix(".puml")) {
                base_name = base_name.substring(0, base_name.length - 5);
            }
            chooser.initial_name = base_name + extension;

            var filter = new Gtk.FileFilter();
            filter.name = filter_name;
            filter.add_pattern("*" + extension);

            var filters = new ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            chooser.filters = filters;

            var parent_window = this.get_root() as Gtk.Window;

            chooser.save.begin(parent_window, null, (obj, res) => {
                try {
                    var file = chooser.save.end(res);
                    if (file != null) {
                        string path = file.get_path();
                        export_requested(format, scale_spin.value, path);
                        this.close();
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        warning("Export error: %s", e.message);
                    }
                }
            });
        }
    }
}
