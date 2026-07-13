namespace GDiagram {
    public class ExportDialog : Adw.Dialog {
        private Adw.ComboRow format_row;
        private Adw.ComboRow preset_row;
        private Gtk.SpinButton scale_spin;
        private Gtk.Label size_label;
        private Gtk.Label dpi_label;
        private Gtk.Button export_button;
        private Gtk.Button copy_button;
        private Adw.SwitchRow transparent_row;

        private Cairo.ImageSurface? source_surface;
        private string document_title;
        private bool updating_from_preset = false;

        public signal void export_requested(string format, double scale, string filename, bool transparent);

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

            copy_button = new Gtk.Button.with_label("Copy");
            copy_button.tooltip_text = "Copy diagram to clipboard";
            copy_button.clicked.connect(on_copy_clicked);
            copy_button.sensitive = source_surface != null;
            header.pack_end(copy_button);

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

            // Preset selection
            preset_row = new Adw.ComboRow();
            preset_row.title = "Preset";
            preset_row.subtitle = "Quick export configurations";

            var preset_strings = new Gtk.StringList(null);
            preset_strings.append("Custom");
            foreach (var preset in ExportPresets.get_presets()) {
                preset_strings.append(preset.name);
            }
            preset_row.model = preset_strings;
            preset_row.selected = 0;
            prefs_group.add(preset_row);

            // Format selection
            format_row = new Adw.ComboRow();
            format_row.title = "Format";
            format_row.subtitle = "Output file format";

            var formats = new Gtk.StringList(null);
            formats.append("PNG Image");
            formats.append("SVG Vector");
            formats.append("PDF Document");
            format_row.model = formats;
            format_row.selected = 0;

            prefs_group.add(format_row);

            // Scale factor (PNG only)
            var scale_row = new Adw.ActionRow();
            scale_row.title = "Scale";
            scale_row.subtitle = "Export resolution multiplier";

            var scale_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            scale_box.valign = Gtk.Align.CENTER;

            scale_spin = new Gtk.SpinButton.with_range(0.5, 4.0, 0.25);
            scale_spin.value = 1.0;
            scale_spin.digits = 2;
            scale_spin.value_changed.connect(update_size_preview);
            scale_box.append(scale_spin);

            var scale_x_label = new Gtk.Label("×");
            scale_x_label.add_css_class("dim-label");
            scale_box.append(scale_x_label);

            dpi_label = new Gtk.Label("96 DPI");
            dpi_label.add_css_class("dim-label");
            scale_box.append(dpi_label);

            scale_row.add_suffix(scale_box);
            prefs_group.add(scale_row);

            // Output size preview
            var size_row = new Adw.ActionRow();
            size_row.title = "Output Size";
            size_row.subtitle = "Resulting dimensions";

            size_label = new Gtk.Label("");
            size_label.add_css_class("dim-label");
            size_label.valign = Gtk.Align.CENTER;
            size_row.add_suffix(size_label);
            prefs_group.add(size_row);

            // Transparent background toggle — applies to all formats.
            // Temporarily overrides the active palette's background slot
            // during export, then restores it.
            transparent_row = new Adw.SwitchRow();
            transparent_row.title = "Transparent background";
            transparent_row.subtitle = "Export without the current theme's canvas color";
            transparent_row.active = false;
            prefs_group.add(transparent_row);

            content_box.append(prefs_group);

            // Info label when no surface
            if (source_surface == null) {
                var info_label = new Gtk.Label("No diagram to export. Create a valid diagram first.");
                info_label.add_css_class("dim-label");
                info_label.wrap = true;
                info_label.margin_top = 24;
                content_box.append(info_label);
            }

            toolbar_view.content = content_box;
            this.child = toolbar_view;

            format_row.notify["selected"].connect(() => {
                bool is_raster = format_row.selected == 0;
                scale_spin.sensitive = is_raster;
                dpi_label.visible = is_raster;
                update_size_preview();
            });

            preset_row.notify["selected"].connect(() => {
                uint idx = preset_row.selected;
                if (idx == 0) return; // Custom — leave controls as-is

                var presets = ExportPresets.get_presets();
                if (idx - 1 >= presets.size) return;
                var preset = presets.get((int)(idx - 1));

                updating_from_preset = true;

                // Apply format
                switch (preset.format) {
                    case "svg": format_row.selected = 1; break;
                    case "pdf": format_row.selected = 2; break;
                    default:    format_row.selected = 0; break;
                }

                // Apply scale from DPI (96 is the base DPI of Cairo surfaces)
                if (preset.format == "png") {
                    double scale = preset.dpi / 96.0;
                    scale = scale.clamp(0.5, 4.0);
                    scale_spin.value = scale;
                }

                preset_row.subtitle = preset.description;
                updating_from_preset = false;
                update_size_preview();
            });
        }

        private void update_size_preview() {
            if (source_surface == null) {
                size_label.label = "N/A";
                dpi_label.label = "—";
                return;
            }

            int base_width  = source_surface.get_width();
            int base_height = source_surface.get_height();

            if (format_row.selected != 0) {
                // SVG / PDF: no raster scaling, show natural size
                size_label.label = "%d × %d px".printf(base_width, base_height);
            } else {
                double scale = scale_spin.value;
                int out_w = (int)(base_width  * scale);
                int out_h = (int)(base_height * scale);
                size_label.label = "%d × %d px".printf(out_w, out_h);
                dpi_label.label = "%d DPI".printf((int)(scale * 96));
            }
        }

        private void on_export_clicked() {
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

            // Set initial filename, stripping known diagram extensions
            string base_name = document_title;
            if (base_name.has_suffix(".puml")) {
                base_name = base_name.substring(0, base_name.length - 5);
            } else if (base_name.has_suffix(".mmd")) {
                base_name = base_name.substring(0, base_name.length - 4);
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
                        export_requested(format, scale_spin.value, path, transparent_row.active);
                        this.close();
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        warning("Export error: %s", e.message);
                    }
                }
            });
        }

        private void on_copy_clicked() {
            if (source_surface == null) return;

            // Write surface to PNG bytes in memory, then put on clipboard as a texture
            string tmp = GLib.Path.build_filename(
                GLib.Environment.get_tmp_dir(), "_gdiagram_clipboard.png");

            if (source_surface.write_to_png(tmp) != Cairo.Status.SUCCESS) {
                warning("Failed to render diagram for clipboard");
                return;
            }

            try {
                var texture = Gdk.Texture.from_filename(tmp);
                get_clipboard().set_texture(texture);

                // Brief label feedback
                copy_button.label = "Copied!";
                GLib.Timeout.add(1500, () => {
                    copy_button.label = "Copy";
                    return GLib.Source.REMOVE;
                });
            } catch (Error e) {
                warning("Clipboard copy failed: %s", e.message);
            } finally {
                GLib.FileUtils.unlink(tmp);
            }
        }
    }
}
