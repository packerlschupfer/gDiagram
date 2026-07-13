namespace GDiagram {
    /**
     * Tracks the most-recently-opened files, persists them to the user
     * config dir, and maintains a {@link GLib.Menu} model for the recent
     * files menu button. Emits {@link open_requested} when the user picks
     * an existing recent file.
     */
    public class RecentFilesManager : Object {
        public signal void open_requested(File file);

        private Gee.ArrayList<string> recent_files;
        private const int MAX_RECENT_FILES = 10;

        /** Live menu model — assign directly to a MenuButton.menu_model. */
        public Menu menu_model { get; private set; }

        public RecentFilesManager() {
            recent_files = new Gee.ArrayList<string>();
            menu_model = new Menu();
            load_recent_files();
            update_recent_files_menu();
        }

        public Gee.ArrayList<string> get_recent_files() {
            return recent_files;
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
            update_recent_files_menu();
        }

        /**
         * Handle the "win.open-recent" action. Opens the file if it still
         * exists, otherwise prunes it and informs the user via a dialog
         * parented to `parent`.
         */
        public void activate_recent(string path, Gtk.Window parent) {
            if (path.length == 0) return;
            var file = File.new_for_path(path);
            if (file.query_exists()) {
                open_requested(file);
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
                dialog.present(parent);
            }
        }

        public void clear() {
            recent_files.clear();
            save_recent_files();
            update_recent_files_menu();
        }

        // Current location under the gdiagram config dir.
        private string recent_file_path() {
            var config_dir = Environment.get_user_config_dir();
            return Path.build_filename(config_dir, "gdiagram", "recent_files.txt");
        }

        // Legacy location under the old gplantuml config dir.
        private string legacy_recent_file_path() {
            var config_dir = Environment.get_user_config_dir();
            return Path.build_filename(config_dir, "gplantuml", "recent_files.txt");
        }

        // One-time migration: if the new file is absent but the legacy one
        // exists, copy its contents to the new location and delete the legacy
        // file (and the now-empty gplantuml dir). Mirrors the migrate-then-
        // delete pattern AIService uses for its key file. Errors are ignored.
        private void migrate_legacy_recent_file() {
            var new_file = recent_file_path();
            if (FileUtils.test(new_file, FileTest.EXISTS)) {
                return;
            }
            var legacy_file = legacy_recent_file_path();
            if (!FileUtils.test(legacy_file, FileTest.EXISTS)) {
                return;
            }
            try {
                string contents;
                if (FileUtils.get_contents(legacy_file, out contents)) {
                    var config_dir = Environment.get_user_config_dir();
                    var app_config = Path.build_filename(config_dir, "gdiagram");
                    DirUtils.create_with_parents(app_config, 0755);
                    FileUtils.set_contents(new_file, contents);
                    FileUtils.unlink(legacy_file);
                    // Remove the old gplantuml dir if it is now empty.
                    var legacy_dir = Path.build_filename(config_dir, "gplantuml");
                    DirUtils.remove(legacy_dir);
                }
            } catch (Error e) {
                // Migration is best-effort; ignore errors.
            }
        }

        private void load_recent_files() {
            migrate_legacy_recent_file();
            var recent_file = recent_file_path();

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
            var app_config = Path.build_filename(config_dir, "gdiagram");

            try {
                DirUtils.create_with_parents(app_config, 0755);
                var recent_file = Path.build_filename(app_config, "recent_files.txt");
                var contents = string.joinv("\n", recent_files.to_array());
                FileUtils.set_contents(recent_file, contents);
            } catch (Error e) {
                warning("Could not save recent files: %s", e.message);
            }
        }

        private void update_recent_files_menu() {
            // Clear and rebuild the menu
            menu_model.remove_all();

            if (recent_files.size == 0) {
                // Add "No Recent Files" placeholder
                menu_model.append("No Recent Files", null);
            } else {
                // Add recent files section
                var files_section = new Menu();
                foreach (var path in recent_files) {
                    string basename = Path.get_basename(path);
                    var item = new MenuItem(basename, null);
                    item.set_action_and_target_value("win.open-recent", new Variant.string(path));
                    files_section.append_item(item);
                }
                menu_model.append_section(null, files_section);

                // Add clear option in separate section
                var clear_section = new Menu();
                clear_section.append("Clear Recent Files", "win.clear-recent");
                menu_model.append_section(null, clear_section);
            }
        }
    }
}
