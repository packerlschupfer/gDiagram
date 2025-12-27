namespace GDiagram {
    public class PreferencesDialog : Adw.PreferencesDialog {
        private GLib.Settings settings;

        construct {
            settings = new GLib.Settings(APP_ID);

            title = "Preferences";
            search_enabled = false;

            // Editor Page
            var editor_page = new Adw.PreferencesPage();
            editor_page.title = "Editor";
            editor_page.icon_name = "document-edit-symbolic";

            // Appearance Group
            var appearance_group = new Adw.PreferencesGroup();
            appearance_group.title = "Appearance";
            appearance_group.description = "Customize the editor appearance";

            // Font row
            var font_row = new Adw.ActionRow();
            font_row.title = "Editor Font";
            font_row.subtitle = settings.get_string("editor-font");

            var font_button = new Gtk.FontDialogButton(new Gtk.FontDialog());
            font_button.valign = Gtk.Align.CENTER;
            font_button.level = Gtk.FontLevel.FONT;

            // Parse current font setting
            var current_font = settings.get_string("editor-font");
            var font_desc = Pango.FontDescription.from_string(current_font);
            font_button.font_desc = font_desc;

            font_button.notify["font-desc"].connect(() => {
                var new_font = font_button.font_desc.to_string();
                settings.set_string("editor-font", new_font);
                font_row.subtitle = new_font;
            });

            font_row.add_suffix(font_button);
            font_row.activatable_widget = font_button;
            appearance_group.add(font_row);

            // Line numbers switch
            var line_numbers_row = new Adw.SwitchRow();
            line_numbers_row.title = "Show Line Numbers";
            line_numbers_row.subtitle = "Display line numbers in the editor margin";
            settings.bind("show-line-numbers", line_numbers_row, "active",
                         GLib.SettingsBindFlags.DEFAULT);
            appearance_group.add(line_numbers_row);

            // Highlight current line
            var highlight_row = new Adw.SwitchRow();
            highlight_row.title = "Highlight Current Line";
            highlight_row.subtitle = "Highlight the line where the cursor is";
            settings.bind("highlight-current-line", highlight_row, "active",
                         GLib.SettingsBindFlags.DEFAULT);
            appearance_group.add(highlight_row);

            editor_page.add(appearance_group);

            // Behavior Group
            var behavior_group = new Adw.PreferencesGroup();
            behavior_group.title = "Behavior";
            behavior_group.description = "Editor behavior settings";

            // Render delay
            var delay_row = new Adw.SpinRow.with_range(100, 2000, 50);
            delay_row.title = "Render Delay";
            delay_row.subtitle = "Delay in milliseconds before rendering after typing";
            delay_row.value = settings.get_int("render-delay");
            delay_row.notify["value"].connect(() => {
                settings.set_int("render-delay", (int)delay_row.value);
            });
            behavior_group.add(delay_row);

            editor_page.add(behavior_group);

            // Add page
            this.add(editor_page);

            // Rendering Page
            var rendering_page = new Adw.PreferencesPage();
            rendering_page.title = "Rendering";
            rendering_page.icon_name = "view-reveal-symbolic";

            var layout_group = new Adw.PreferencesGroup();
            layout_group.title = "Layout Engine";
            layout_group.description = "Choose the Graphviz layout engine for diagram rendering";

            // Layout engine combo
            var layout_row = new Adw.ComboRow();
            layout_row.title = "Layout Engine";
            layout_row.subtitle = "Different engines produce different diagram layouts";

            // Layout engine options with descriptions
            string[] engine_names = { "dot (hierarchical)", "neato (spring model)", "fdp (force-directed)",
                                      "sfdp (large graphs)", "circo (circular)", "twopi (radial)" };
            string[] engine_values = { "dot", "neato", "fdp", "sfdp", "circo", "twopi" };

            var layout_model = new Gtk.StringList(engine_names);
            layout_row.model = layout_model;

            // Find current engine index
            string current_engine = settings.get_string("layout-engine");
            int engine_index = 0;
            for (int i = 0; i < engine_values.length; i++) {
                if (engine_values[i] == current_engine) {
                    engine_index = i;
                    break;
                }
            }
            layout_row.selected = engine_index;

            layout_row.notify["selected"].connect(() => {
                int idx = (int)layout_row.selected;
                if (idx >= 0 && idx < engine_values.length) {
                    settings.set_string("layout-engine", engine_values[idx]);
                }
            });

            layout_group.add(layout_row);
            rendering_page.add(layout_group);
            this.add(rendering_page);

            // Theme Page
            var theme_page = new Adw.PreferencesPage();
            theme_page.title = "Theme";
            theme_page.icon_name = "applications-graphics-symbolic";

            var scheme_group = new Adw.PreferencesGroup();
            scheme_group.title = "Color Scheme";
            scheme_group.description = "Select a color scheme for syntax highlighting";

            // Get available schemes
            var style_manager = GtkSource.StyleSchemeManager.get_default();
            var scheme_ids = style_manager.get_scheme_ids();

            // Create combo row for scheme selection
            var scheme_names = new GLib.GenericArray<string>();
            foreach (var id in scheme_ids) {
                var scheme = style_manager.get_scheme(id);
                if (scheme != null) {
                    scheme_names.add(scheme.name ?? id);
                }
            }

            var scheme_row = new Adw.ComboRow();
            scheme_row.title = "Color Scheme";
            scheme_row.subtitle = "Syntax highlighting color scheme";

            var scheme_model = new Gtk.StringList(null);
            for (int i = 0; i < scheme_names.length; i++) {
                scheme_model.append(scheme_names[i]);
            }
            scheme_row.model = scheme_model;

            // Find current scheme index (default to Adwaita-dark or first)
            int current_index = 0;
            for (int i = 0; i < scheme_ids.length; i++) {
                if (scheme_ids[i] == "Adwaita-dark") {
                    current_index = i;
                    break;
                }
            }
            scheme_row.selected = current_index;

            scheme_group.add(scheme_row);
            theme_page.add(scheme_group);

            this.add(theme_page);

            // About Page with keyboard shortcuts
            var shortcuts_page = new Adw.PreferencesPage();
            shortcuts_page.title = "Shortcuts";
            shortcuts_page.icon_name = "preferences-desktop-keyboard-shortcuts-symbolic";

            var shortcuts_group = new Adw.PreferencesGroup();
            shortcuts_group.title = "Keyboard Shortcuts";

            add_shortcut_row(shortcuts_group, "New Tab", "Ctrl+N");
            add_shortcut_row(shortcuts_group, "Open File", "Ctrl+O");
            add_shortcut_row(shortcuts_group, "Save", "Ctrl+S");
            add_shortcut_row(shortcuts_group, "Close Tab", "Ctrl+W");
            add_shortcut_row(shortcuts_group, "Find", "Ctrl+F");
            add_shortcut_row(shortcuts_group, "Find & Replace", "Ctrl+H");
            add_shortcut_row(shortcuts_group, "Find Next", "Ctrl+G / F3");
            add_shortcut_row(shortcuts_group, "Find Previous", "Ctrl+Shift+G / Shift+F3");
            add_shortcut_row(shortcuts_group, "Quit", "Ctrl+Q");

            shortcuts_page.add(shortcuts_group);
            this.add(shortcuts_page);
        }

        private void add_shortcut_row(Adw.PreferencesGroup group, string action, string shortcut) {
            var row = new Adw.ActionRow();
            row.title = action;

            var label = new Gtk.Label(shortcut);
            label.add_css_class("dim-label");
            label.add_css_class("monospace");
            label.valign = Gtk.Align.CENTER;
            row.add_suffix(label);

            group.add(row);
        }
    }
}
