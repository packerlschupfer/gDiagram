namespace GDiagram {
    public class Application : Adw.Application {
        private bool debug_mode = false;

        public Application() {
            Object(
                application_id: APP_ID,
                flags: ApplicationFlags.HANDLES_OPEN | ApplicationFlags.HANDLES_COMMAND_LINE
            );
        }

        construct {
            ActionEntry[] action_entries = {
                { "about", this.on_about_action },
                { "preferences", this.on_preferences_action },
                { "quit", this.quit }
            };
            this.add_action_entries(action_entries, this);
            this.set_accels_for_action("app.quit", {"<primary>q"});
            this.set_accels_for_action("app.preferences", {"<primary>comma"});
            this.set_accels_for_action("win.new-tab", {"<primary>n"});
            this.set_accels_for_action("win.open", {"<primary>o"});
            this.set_accels_for_action("win.save", {"<primary>s"});
            this.set_accels_for_action("win.close-tab", {"<primary>w"});
        }

        protected override int command_line(ApplicationCommandLine command_line) {
            string[] args = command_line.get_arguments();

            // Parse command line options
            for (int i = 1; i < args.length; i++) {
                if (args[i] == "--debug" || args[i] == "-d") {
                    debug_mode = true;
                    Environment.set_variable("G_MESSAGES_DEBUG", "all", true);
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
                    print("gDiagram Debug Mode Enabled\n");
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
                    print("Version: %s\n", VERSION);
                    print("Debug messages: Enabled\n");
                    print("GLib debug: Enabled\n");
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n");
                } else if (args[i] == "--help" || args[i] == "-h") {
                    print("Usage: gplantuml [OPTIONS] [FILE]\n");
                    print("Options:\n");
                    print("  -d, --debug    Enable debug output\n");
                    print("  -h, --help     Show this help\n");
                    print("  --version      Show version information\n");
                    return 0;
                } else if (args[i] == "--version") {
                    print("gPlantUML version %s\n", VERSION);
                    return 0;
                } else if (!args[i].has_prefix("-")) {
                    // It's a file to open
                    var file = File.new_for_commandline_arg(args[i]);
                    activate();
                    var win = this.active_window as MainWindow;
                    if (win != null) {
                        win.open_file(file);
                    }
                    return 0;
                }
            }

            if (debug_mode) {
                print("Activating application window...\n");
            }
            activate();
            if (debug_mode) {
                print("Application activated successfully\n");
            }
            return 0;
        }

        protected override void activate() {
            if (debug_mode) print("[DEBUG] Application.activate() called\n");
            base.activate();

            if (debug_mode) print("[DEBUG] Creating MainWindow...\n");
            var win = this.active_window ?? new MainWindow(this);

            if (debug_mode) print("[DEBUG] Presenting window...\n");
            win.present();

            if (debug_mode) print("[DEBUG] Window presented successfully\n");
        }

        protected override void open(File[] files, string hint) {
            base.open(files, hint);
            var win = this.active_window as MainWindow ?? new MainWindow(this);
            foreach (var file in files) {
                win.open_file(file);
            }
            win.present();
        }

        private void on_about_action() {
            var about = new Adw.AboutDialog() {
                application_name = APP_NAME,
                application_icon = APP_ID,
                developer_name = "gPlantUML Contributors",
                version = VERSION,
                developers = { "gPlantUML Contributors" },
                copyright = "© 2024 gPlantUML Contributors",
                license_type = Gtk.License.GPL_3_0
            };
            about.present(this.active_window);
        }

        private void on_preferences_action() {
            var prefs = new PreferencesDialog();
            prefs.present(this.active_window);
        }
    }
}
