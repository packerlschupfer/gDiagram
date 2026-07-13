namespace GDiagram {
    public class PreferencesDialog : Adw.PreferencesDialog {
        private GLib.Settings settings;
        private AIService ai_service;

        construct {
            settings = new GLib.Settings(APP_ID);
            ai_service = new AIService();

            title = "Preferences";
            search_enabled = false;
            // Force wide enough for the 5-page header view switcher, otherwise
            // libadwaita pushes the tabs to a bottom bar.
            content_width = 960;
            content_height = 680;

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

            // ---- Diagram palette (presets + per-slot color overrides) ----
            // Gated on the installed schema actually containing the new keys
            // so the dialog still opens against an older installed .gschema.
            if (settings.settings_schema.has_key("color-scheme-follow-system")) {
                add_diagram_palette_group(theme_page);
            }

            this.add(theme_page);

            // Navigation Page — drill-down filename patterns
            // Gated on the settings schema actually containing the new keys:
            // if the app is running against an older installed .gschema (e.g.
            // from an out-of-date .deb) the keys are missing and
            // `settings.get_strv("drill-down-patterns")` would crash the whole
            // Preferences dialog. In that case we show a simple info note so
            // the user knows what's happening.
            var nav_page = new Adw.PreferencesPage();
            nav_page.title = "Navigation";
            nav_page.icon_name = "view-list-symbolic";

            if (settings.settings_schema.has_key("drill-down-patterns")) {
                var drill_group = new Adw.PreferencesGroup();
                drill_group.title = "Drill-down patterns";
                drill_group.description = "Filename templates used when you double-click an element to open a related file. $alias is the clicked element's identifier; $base is the current file's basename without extension.";

                var patterns_row = new Adw.EntryRow();
                patterns_row.title = "Patterns (comma-separated)";
                patterns_row.text = string.joinv(", ", settings.get_strv("drill-down-patterns"));
                patterns_row.apply.connect(() => {
                    string[] parts = {};
                    foreach (string p in patterns_row.text.split(",")) {
                        string trimmed = p.strip();
                        if (trimmed.length > 0) parts += trimmed;
                    }
                    settings.set_strv("drill-down-patterns", parts);
                });
                drill_group.add(patterns_row);

                var subdirs_row = new Adw.EntryRow();
                subdirs_row.title = "Search subdirectories (comma-separated)";
                subdirs_row.text = string.joinv(", ", settings.get_strv("drill-down-subdirs"));
                subdirs_row.apply.connect(() => {
                    string[] parts = {};
                    foreach (string p in subdirs_row.text.split(",")) {
                        string trimmed = p.strip();
                        if (trimmed.length > 0) parts += trimmed;
                    }
                    settings.set_strv("drill-down-subdirs", parts);
                });
                drill_group.add(subdirs_row);

                var reset_row = new Adw.ActionRow();
                reset_row.title = "Reset to defaults";
                reset_row.subtitle = "Restore the built-in pattern list";
                var reset_btn = new Gtk.Button.with_label("Reset");
                reset_btn.add_css_class("flat");
                reset_btn.valign = Gtk.Align.CENTER;
                reset_btn.clicked.connect(() => {
                    settings.reset("drill-down-patterns");
                    settings.reset("drill-down-subdirs");
                    patterns_row.text = string.joinv(", ", settings.get_strv("drill-down-patterns"));
                    subdirs_row.text = string.joinv(", ", settings.get_strv("drill-down-subdirs"));
                });
                reset_row.add_suffix(reset_btn);
                drill_group.add(reset_row);

                nav_page.add(drill_group);
            } else {
                var info_group = new Adw.PreferencesGroup();
                info_group.title = "Drill-down patterns";
                info_group.description = "This feature needs a schema update. Reinstall the gDiagram package (or run glib-compile-schemas against the development tree) to enable configurable drill-down patterns. The built-in defaults are used in the meantime.";
                nav_page.add(info_group);
            }

            this.add(nav_page);

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
            add_shortcut_row(shortcuts_group, "Find &amp; Replace", "Ctrl+H");
            add_shortcut_row(shortcuts_group, "Find Next", "Ctrl+G / F3");
            add_shortcut_row(shortcuts_group, "Find Previous", "Ctrl+Shift+G / Shift+F3");
            add_shortcut_row(shortcuts_group, "Quit", "Ctrl+Q");

            shortcuts_page.add(shortcuts_group);
            this.add(shortcuts_page);

            // AI Assistant Page — Anthropic API key management
            var ai_page = new Adw.PreferencesPage();
            ai_page.title = "AI Assistant";
            ai_page.icon_name = "starred-symbolic";
            add_ai_group(ai_page);
            this.add(ai_page);
        }

        // ===================================================================
        // AI Assistant — Anthropic API key management
        // ===================================================================

        // Kept so the status row and Clear button can be refreshed after a
        // save or clear without rebuilding the page.
        private Adw.ActionRow? ai_status_row = null;
        private Gtk.Button? ai_clear_button = null;

        private void add_ai_group(Adw.PreferencesPage page) {
            var group = new Adw.PreferencesGroup();
            group.title = "AI Assistant";
            group.description = "Configure the Anthropic API key used to generate diagrams from natural-language descriptions. The key is stored securely in the system keyring and never displayed back in plain text.";

            // Status row: whether a key is configured and where it comes from.
            ai_status_row = new Adw.ActionRow();
            ai_status_row.title = "Status";
            var status_icon = new Gtk.Image();
            status_icon.valign = Gtk.Align.CENTER;
            ai_status_row.add_prefix(status_icon);
            group.add(ai_status_row);

            // Key entry — password style so the value is never revealed.
            // show-apply-button gives the idiomatic libadwaita checkmark that
            // acts as the explicit Save action.
            var key_row = new Adw.PasswordEntryRow();
            key_row.title = "API Key";
            key_row.show_apply_button = true;
            key_row.apply.connect(() => {
                string key = key_row.text.strip();
                if (key.length == 0) return;
                ai_service.save_api_key(key);
                key_row.text = "";   // never keep the value visible in the field
                refresh_ai_status();
            });
            group.add(key_row);

            // Clear row — removes the stored key. Insensitive when there is
            // nothing to clear (no stored key, or an env-var-only key).
            var clear_row = new Adw.ActionRow();
            clear_row.title = "Stored Key";
            clear_row.subtitle = "Remove the key saved in the keyring";
            ai_clear_button = new Gtk.Button.with_label("Clear");
            ai_clear_button.valign = Gtk.Align.CENTER;
            ai_clear_button.add_css_class("destructive-action");
            ai_clear_button.clicked.connect(() => {
                ai_service.clear_api_key();
                refresh_ai_status();
            });
            clear_row.add_suffix(ai_clear_button);
            clear_row.activatable_widget = ai_clear_button;
            group.add(clear_row);

            page.add(group);
            refresh_ai_status();
        }

        // Syncs the status row text/icon and the Clear button sensitivity
        // with the AIService's current key source.
        private void refresh_ai_status() {
            if (ai_status_row == null) return;

            string src = ai_service.key_source();
            string subtitle;
            string icon_name;
            switch (src) {
                case "env":
                    subtitle = "Configured via the ANTHROPIC_API_KEY environment variable. The environment variable always takes precedence and cannot be cleared here.";
                    icon_name = "emblem-ok-symbolic";
                    break;
                case "keyring":
                    subtitle = "Configured — stored securely in the system keyring.";
                    icon_name = "emblem-ok-symbolic";
                    break;
                case "file":
                    subtitle = "Configured — stored in a local file (keyring unavailable).";
                    icon_name = "emblem-ok-symbolic";
                    break;
                default:
                    subtitle = "No API key configured. Enter one above to enable AI diagram generation.";
                    icon_name = "dialog-warning-symbolic";
                    break;
            }
            ai_status_row.subtitle = subtitle;

            // The status icon is the first prefix widget we added.
            var img = find_status_image(ai_status_row);
            if (img != null) img.icon_name = icon_name;

            if (ai_clear_button != null) {
                ai_clear_button.sensitive = ai_service.has_stored_key();
            }
        }

        // Locate the Gtk.Image we added as the status row prefix.
        private Gtk.Image? find_status_image(Gtk.Widget root) {
            var child = root.get_first_child();
            while (child != null) {
                if (child is Gtk.Image) return (Gtk.Image) child;
                var found = find_status_image(child);
                if (found != null) return found;
                child = child.get_next_sibling();
            }
            return null;
        }

        // ===================================================================
        // Diagram palette UI (presets + per-slot color overrides)
        // ===================================================================

        // Tracks the color picker buttons keyed by slot name so the "Reset
        // to preset" button and the preset combos can refresh them without
        // rebuilding the UI.
        private Gee.HashMap<string, Gtk.ColorDialogButton>? palette_buttons = null;

        private void add_diagram_palette_group(Adw.PreferencesPage page) {
            palette_buttons = new Gee.HashMap<string, Gtk.ColorDialogButton>();

            // --- Presets group -------------------------------------------
            var preset_group = new Adw.PreferencesGroup();
            preset_group.title = "Diagram Colors";
            preset_group.description = "Palette used for rendered diagrams (nodes, edges, background)";

            // Follow-system switch
            var follow_row = new Adw.SwitchRow();
            follow_row.title = "Follow system theme";
            follow_row.subtitle = "Automatically switch between light and dark presets";
            settings.bind("color-scheme-follow-system", follow_row, "active", SettingsBindFlags.DEFAULT);
            preset_group.add(follow_row);

            // Preset names model shared by both combos
            var preset_ids = ThemeManager.preset_names();
            var preset_model = new Gtk.StringList(null);
            foreach (var id in preset_ids) {
                preset_model.append(ThemeManager.preset_display_name(id));
            }

            // Light preset combo with color swatches.
            var light_row = new Adw.ComboRow();
            light_row.title = "Light preset";
            light_row.subtitle = "Used when the system is in light mode";
            light_row.model = preset_model;
            light_row.selected = index_of(preset_ids, settings.get_string("color-scheme-light"));
            var light_swatches = build_preset_swatches(preset_ids[(int) light_row.selected]);
            light_row.add_suffix(light_swatches);
            light_row.notify["selected"].connect(() => {
                string id = preset_ids[(int) light_row.selected];
                settings.set_string("color-scheme-light", id);
                update_swatches(light_swatches, id);
                refresh_palette_buttons();
            });
            preset_group.add(light_row);

            // Dark preset combo — use a fresh StringList, GTK doesn't like
            // sharing one model between two ComboRows.
            var dark_model = new Gtk.StringList(null);
            foreach (var id in preset_ids) {
                dark_model.append(ThemeManager.preset_display_name(id));
            }
            var dark_row = new Adw.ComboRow();
            dark_row.title = "Dark preset";
            dark_row.subtitle = "Used when the system is in dark mode";
            dark_row.model = dark_model;
            dark_row.selected = index_of(preset_ids, settings.get_string("color-scheme-dark"));
            var dark_swatches = build_preset_swatches(preset_ids[(int) dark_row.selected]);
            dark_row.add_suffix(dark_swatches);
            dark_row.notify["selected"].connect(() => {
                string id = preset_ids[(int) dark_row.selected];
                settings.set_string("color-scheme-dark", id);
                update_swatches(dark_swatches, id);
                refresh_palette_buttons();
            });
            preset_group.add(dark_row);

            page.add(preset_group);

            // --- Custom slot overrides group ----------------------------
            // Collapsible via an expander row; hidden by default so the
            // page isn't overwhelming for users who just want a preset.
            var custom_group = new Adw.PreferencesGroup();
            custom_group.title = "Custom Colors";
            custom_group.description = "Override individual palette slots. Changes apply on top of the active preset and persist across launches.";

            var expander = new Adw.ExpanderRow();
            expander.title = "Per-slot overrides";
            expander.subtitle = "25 slots — background, generic, C4 roles, edges, accents";
            custom_group.add(expander);

            foreach (var slot in ThemeManager.slot_names()) {
                expander.add_row(build_slot_row(slot));
            }

            var reset_row = new Adw.ActionRow();
            reset_row.title = "Reset to preset";
            reset_row.subtitle = "Discard all custom color overrides";
            var reset_button = new Gtk.Button.with_label("Reset");
            reset_button.valign = Gtk.Align.CENTER;
            reset_button.add_css_class("destructive-action");
            reset_button.clicked.connect(() => {
                settings.set_string("custom-palette-overrides", "");
                refresh_palette_buttons();
            });
            reset_row.add_suffix(reset_button);
            custom_group.add(reset_row);

            page.add(custom_group);
        }

        // Which slots to preview in the preset swatches. Chosen so the five
        // squares give an at-a-glance sense of the preset's character:
        // background tint + the four main role fills.
        private const string[] SWATCH_SLOTS = {
            "background", "person_fill", "system_fill", "container_fill", "edge_color"
        };

        private Gtk.Box build_preset_swatches(string preset_id) {
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            box.valign = Gtk.Align.CENTER;
            update_swatches(box, preset_id);
            return box;
        }

        // Rebuild the swatch box's children to reflect `preset_id`.
        // Each swatch is a small DrawingArea with a filled rounded square.
        private void update_swatches(Gtk.Box box, string preset_id) {
            // Clear existing children
            Gtk.Widget? child = box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                box.remove(child);
                child = next;
            }

            var preset = ThemeManager.get_preset(preset_id);
            foreach (var slot in SWATCH_SLOTS) {
                string hex = ThemeManager.get_slot(preset, slot);
                var rgba = Gdk.RGBA();
                if (!rgba.parse(hex)) rgba.parse("#000000");

                var swatch = new Gtk.DrawingArea();
                swatch.content_width = 16;
                swatch.content_height = 16;
                swatch.tooltip_text = ThemeManager.slot_display_name(slot);
                swatch.set_draw_func((da, cr, w, h) => {
                    cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha);
                    // Rounded square
                    double r = 3.0;
                    cr.new_sub_path();
                    cr.arc(w - r, r, r, -Math.PI / 2, 0);
                    cr.arc(w - r, h - r, r, 0, Math.PI / 2);
                    cr.arc(r, h - r, r, Math.PI / 2, Math.PI);
                    cr.arc(r, r, r, Math.PI, 3 * Math.PI / 2);
                    cr.close_path();
                    cr.fill_preserve();
                    cr.set_source_rgba(0, 0, 0, 0.3);
                    cr.set_line_width(0.5);
                    cr.stroke();
                });
                box.append(swatch);
            }
        }

        private Adw.ActionRow build_slot_row(string slot) {
            var row = new Adw.ActionRow();
            row.title = ThemeManager.slot_display_name(slot);
            row.subtitle = slot;

            var cur_palette = ThemeManager.get_active_palette();
            string hex = ThemeManager.get_slot(cur_palette, slot);

            var button = new Gtk.ColorDialogButton(new Gtk.ColorDialog());
            button.valign = Gtk.Align.CENTER;
            button.rgba = parse_rgba(hex);

            button.notify["rgba"].connect(() => {
                unowned Gdk.RGBA? r = button.get_rgba();
                if (r == null) return;
                int ri = (int) Math.round(r.red   * 255);
                int gi = (int) Math.round(r.green * 255);
                int bi = (int) Math.round(r.blue  * 255);
                string new_hex = "#%02X%02X%02X".printf(ri, gi, bi);
                update_override(slot, new_hex);
            });

            palette_buttons.set(slot, button);
            row.add_suffix(button);
            return row;
        }

        // Writes one slot override into custom-palette-overrides. Serializes
        // the full (current-preset vs. active-palette) diff so removing an
        // override also cleans up its key.
        private void update_override(string slot, string new_hex) {
            // Figure out which preset is currently active — depends on
            // follow-system + system dark flag.
            string preset_id = current_active_preset_id();
            var base_preset = ThemeManager.get_preset(preset_id);

            // Start from the current active palette (which already includes
            // any previous overrides) and update just this slot.
            var cur = ThemeManager.get_active_palette().clone();
            ThemeManager.set_slot(cur, slot, new_hex);
            ThemeManager.set_active_palette(cur);

            string json = ThemeManager.overrides_to_json(cur, base_preset);
            settings.set_string("custom-palette-overrides", json);
        }

        private string current_active_preset_id() {
            bool follow = settings.get_boolean("color-scheme-follow-system");
            if (follow) {
                var sm = Adw.StyleManager.get_default();
                return sm.dark
                    ? settings.get_string("color-scheme-dark")
                    : settings.get_string("color-scheme-light");
            }
            return settings.get_string("color-scheme-light");
        }

        // Called after a preset change or reset — re-reads the active
        // palette and syncs every color button's displayed color.
        private void refresh_palette_buttons() {
            if (palette_buttons == null) return;
            // Force a refresh: the setting-change signal handlers on
            // DocumentView will have already updated the active palette,
            // but if the preferences dialog is open in isolation we
            // refresh explicitly.
            ThemeManager.refresh_from_settings(settings);
            var p = ThemeManager.get_active_palette();
            foreach (var entry in palette_buttons.entries) {
                string slot = entry.key;
                var button = entry.value;
                string hex = ThemeManager.get_slot(p, slot);
                button.rgba = parse_rgba(hex);
            }
        }

        private int index_of(string[] arr, string needle) {
            for (int i = 0; i < arr.length; i++) {
                if (arr[i] == needle) return i;
            }
            return 0;
        }

        private Gdk.RGBA parse_rgba(string hex) {
            var rgba = Gdk.RGBA();
            if (!rgba.parse(hex)) {
                rgba.parse("#000000");
            }
            return rgba;
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
