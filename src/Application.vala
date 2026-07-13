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
            // Window shortcuts are registered here: MainWindow's construct block runs before
            // its `application` property is set, so the ones it registered never took effect
            this.set_accels_for_action("win.save-as", {"<primary><shift>s"});
            this.set_accels_for_action("win.export", {"<primary>e"});
            // Search/replace: window actions, so they fire from the preview and outline too
            this.set_accels_for_action("win.find", {"<primary>f"});
            this.set_accels_for_action("win.replace", {"<primary>h"});
            this.set_accels_for_action("win.print", {"<primary>p"});
            this.set_accels_for_action("win.zoom-in", {"<primary>plus", "<primary>equal"});
            this.set_accels_for_action("win.zoom-out", {"<primary>minus"});
            this.set_accels_for_action("win.zoom-reset", {"<primary>0"});
            this.set_accels_for_action("win.zoom-fit", {"<primary>9"});
            this.set_accels_for_action("win.toggle-outline", {"<primary>backslash"});
            this.set_accels_for_action("win.toggle-properties", {"F9"});
            this.set_accels_for_action("win.beautify", {"<primary><shift>b"});
            this.set_accels_for_action("win.compare-diagrams", {"<primary><shift>d"});
            this.set_accels_for_action("win.git-history", {"<primary><shift>h"});
            this.set_accels_for_action("win.git-visualizer", {"<primary><shift>g"});
            this.set_accels_for_action("win.navigate-back", {"<alt>Left"});
            this.set_accels_for_action("win.convert-format", {"<primary><shift>c"});
            this.set_accels_for_action("win.show-templates", {"<primary>t"});
            this.set_accels_for_action("win.ai-assistant", {"<primary><shift>a"});
            this.set_accels_for_action("win.show-shortcuts", {"<primary>question"});
            // No accels for win.undo/win.redo: the editor handles Ctrl+Z itself, and a window
            // accel would take Ctrl+Z from every other text field
        }

        // Flags main.vala dispatches (and validates) before GApplication registration.
        // They can only reach command_line() by being forwarded from another process,
        // where acting on them would export in the wrong process or, worse, open a
        // stray window on the primary instance's desktop. This used to hold a second
        // copy of the export and --dump-preprocessed handling, parsing included.
        private static bool is_headless_only_flag(string arg) {
            switch (arg) {
                case "-e":
                case "--export":
                case "-f":
                case "--format":
                case "--dump-preprocessed":
                    return true;
                default:
                    return false;
            }
        }

        // --help / --version. main.vala prints these BEFORE GApplication registration:
        // doing it here runs after Adw.init(), whose adw_settings_get_default() opens a
        // settings-portal D-Bus proxy. With no display and no portal (ssh, CI, a private
        // session bus) nothing answers it, so `gdiagram --version` printed nothing at all
        // for ~25 s until the proxy timed out — and, as reported, sometimes never came
        // back. The text lives here so both callers print exactly the same thing.
        public static void print_help() {
            print("Usage: gdiagram [OPTIONS] [FILE]\n");
            print("Options:\n");
            print("  -d, --debug              Enable debug output\n");
            print("  -e, --export OUTPUT      Export to file (headless)\n");
            print("  -f, --format FORMAT      Export format: png, svg, pdf, dot (default: png)\n");
            print("  --scale                  Scale output 71.5%% to match PlantUML dimensions\n");
            print("  -h, --help               Show this help\n");
            print("  --version                Show version information\n");
            print("\n");
            print("Examples:\n");
            print("  gdiagram diagram.puml                    # Open in GUI\n");
            print("  gdiagram diagram.puml -e output.png     # Export to PNG\n");
            print("  gdiagram diagram.puml -e out.svg -f svg # Export to SVG\n");
        }

        public static void print_version() {
            print("gDiagram version %s (%s, %s)\n", VERSION, BUILD_ID, BUILD_DATE);
        }

        protected override int command_line(ApplicationCommandLine command_line) {
            string[] args = command_line.get_arguments();

            for (int i = 1; i < args.length; i++) {
                if (is_headless_only_flag(args[i])) {
                    command_line.printerr("Error: %s only works on the command line that starts gdiagram, " +
                                          "not through a running instance\n", args[i]);
                    return 2;
                }
            }

            // Parse command line options for GUI mode
            var files = new Gee.ArrayList<File>();
            for (int i = 1; i < args.length; i++) {
                if (args[i] == "--debug" || args[i] == "-d") {
                    debug_mode = true;
                    Environment.set_variable("G_MESSAGES_DEBUG", "all", true);
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
                    print("gDiagram Debug Mode Enabled\n");
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
                    print("Version: %s (%s, %s)\n", VERSION, BUILD_ID, BUILD_DATE);
                    print("Debug messages: Enabled\n");
                    print("GLib debug: Enabled\n");
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n");
                } else if (args[i] == "--help" || args[i] == "-h") {
                    print_help();
                    return 0;
                } else if (args[i] == "--version") {
                    print_version();
                    return 0;
                } else if (!args[i].has_prefix("-")) {
                    // A file to open, relative to the invoking process's directory (this
                    // may be the primary instance, running elsewhere)
                    files.add(command_line.create_file_for_arg(args[i]));
                }
            }
            if (files.size > 0) {
                activate();
                var win = this.active_window as MainWindow;
                if (win != null) {
                    // An already open file focuses its tab (MainWindow.open_file)
                    foreach (var file in files) win.open_file(file);
                    win.present();
                }
                return 0;
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

            // Resolve active color palette from settings before any window
            // is created — renderers read it during construction.
            ThemeManager.refresh_from_settings(new GLib.Settings(APP_ID));

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

        // Entry point for main.vala's pre-registration export dispatch —
        // runs without a display (no GApplication registration involved).
        public int run_headless_export(string input_path, string output_path,
                                       string format, bool scale_output) {
            return handle_export(input_path, output_path, format, scale_output);
        }

        private int handle_export(string input_path, string output_path, string format, bool scale_output = false) {
            try {
                // Resolve the active color palette before any renderer runs.
                // GUI mode does this in activate(); CLI export mode skips
                // activate(), so without this the renderer would fall back
                // to the built-in default palette instead of the user's
                // configured preset.
                // Guard on schema existence — calling `new GLib.Settings`
                // against a missing schema aborts via g_error(), so we
                // check SettingsSchemaSource first.
                var schema_src = GLib.SettingsSchemaSource.get_default();
                if (schema_src != null && schema_src.lookup(APP_ID, true) != null) {
                    ThemeManager.refresh_from_settings(new GLib.Settings(APP_ID));
                }

                print("Exporting %s → %s (%s)\n", input_path, output_path, format);

                // Read input file
                string content;
                FileUtils.get_contents(input_path, out content);

                // All parse/detect/render logic now lives in DiagramEngine —
                // the CLI just detects for informational output and dispatches.
                var engine = new DiagramEngine("dot");

                if (engine.detect_format(content, input_path) == DiagramFormat.MERMAID) {
                    var mtype = engine.detect_mermaid_type(content);
                    print("  Detected Mermaid type: %s\n", mtype.to_string());
                    if (mtype == DiagramType.UNKNOWN) {
                        printerr("Error: Could not determine Mermaid diagram type\n");
                        printerr("  No Mermaid keyword (flowchart, sequenceDiagram, ...) found.\n");
                        print_source_head(content);
                        return 1;
                    }
                    return do_export(engine, content, null, DiagramType.UNKNOWN, input_path,
                                     output_path, format, scale_output);
                }

                string processed = engine.preprocess(content, input_path);
                // An unresolved !include used to vanish without a word, leaving
                // a diagram that rendered "fine" minus its theme.
                // PlantUML fails such a file (exit 200); scripts must see it too, so the
                // partial export below still happens but the exit status is 1
                bool include_failed = false;
                foreach (var err in engine.preprocessor_errors) {
                    // An include that exists but cannot be READ (chmod 000, a directory)
                    // only warned and exited 0, so a broken build passed silently. Any
                    // include that did not make it into the source is an error.
                    bool is_include = is_include_failure(err.message);
                    include_failed = include_failed || is_include;
                    printerr("%s: preprocessor: line %d: %s\n", is_include ? "Error" : "Warning", err.line, err.message);
                }
                var diagram_type = engine.detect_plantuml_type(processed);
                print("  Detected type: %s\n", diagram_type.to_string());

                if (diagram_type == DiagramType.UNKNOWN) {
                    printerr("Error: Could not determine diagram type for %s\n", input_path);
                    printerr("  No PlantUML keywords (@startuml, class, participant, state, ...)\n");
                    printerr("  and no Mermaid keywords (flowchart, sequenceDiagram, ...) found.\n");
                    print_source_head(processed);
                    return 1;
                }

                // Export the text preprocessed above: preprocessing it again (C4 stdlib
                // includes are expensive) produced the same text a second time
                int status = do_export(engine, content, processed, diagram_type, input_path,
                                       output_path, format, scale_output);
                if (status == 0 && include_failed) {
                    printerr("Error: unresolved !include; the exported diagram is incomplete\n");
                    return 1;
                }
                return status;

            } catch (Error e) {
                printerr("Export failed: %s\n", e.message);
                return 1;
            }
        }

        /**
         * A preprocessor message meaning an !include did not make it into the source.
         *
         * "Cannot read include file" (chmod 000, or an !include naming a directory) used
         * to be a mere warning here, so a build with a missing include exited 0 and no
         * script noticed. LspDocumentState.is_include_error() keeps the same list for the
         * LSP; the two binaries do not share a compilation unit.
         */
        public static bool is_include_failure(string message) {
            return message.has_prefix("Cannot resolve include") ||
                   message.has_prefix("Standard library include not available") ||
                   message.has_prefix("Cannot read include file");
        }

        // Print the first few non-blank lines of a source, used when type
        // detection fails so the user can see what was parsed.
        private void print_source_head(string source) {
            printerr("  First lines of the source:\n");
            int shown = 0;
            foreach (var raw_line in source.split("\n")) {
                string line = raw_line.strip();
                if (line.length == 0) continue;
                printerr("    %s\n", line);
                if (++shown >= 5) break;
            }
        }

        // Shared dispatch for the CLI export: `dot` writes engine-generated
        // DOT text; png/svg/pdf route through the engine export pipeline,
        // with optional 71.5% PlantUML-dimension scaling applied to PNG via
        // ImageMagick `convert` (matching the pre-engine behavior).
        // `processed` is the preprocessed PlantUML source of the detected `type`,
        // or null for Mermaid (exported from `source`).
        private int do_export(DiagramEngine engine, string source, string? processed, DiagramType type,
                              string input_path, string output_path, string format,
                              bool scale_output) throws Error {
            if (format == "dot") {
                string? dot_output = processed != null
                    ? engine.generate_dot_preprocessed(processed, type)
                    : engine.generate_dot(source, input_path, input_path);
                if (dot_output == null || dot_output.length == 0) {
                    printerr("Error: could not generate DOT output\n");
                    return 1;
                }
                FileUtils.set_contents(output_path, dot_output);
                print("✓ Exported DOT file: %s\n", output_path);
                return 0;
            }

            // For scaled PNG, render to a private temp file first, then scale it down.
            // (A fixed /tmp name let two exports overwrite each other's image, and it
            // was a predictable path in a shared directory.)
            bool scale_png = scale_output && format == "png";
            string render_path = output_path;
            if (scale_png) {
                int fd = FileUtils.open_tmp("gdiagram-export-XXXXXX.png", out render_path);
                FileUtils.close(fd);
            }

            RenderUtils.png_downscale_note = null;
            bool ok;
            if (processed != null) {
                ok = engine.export_preprocessed(processed, type, format, render_path);
            } else if (format == "svg") {
                ok = engine.export_to_svg(source, input_path, input_path, render_path);
            } else if (format == "pdf") {
                ok = engine.export_to_pdf(source, input_path, input_path, render_path);
            } else if (format == "png") {
                ok = engine.export_to_png(source, input_path, input_path, render_path);
            } else {
                // main.vala validates -f, so this is only reachable from a caller that
                // skipped it. Say so instead of quietly writing a PNG.
                if (scale_png) FileUtils.unlink(render_path);
                printerr("Error: unknown export format '%s' (png, svg, pdf or dot)\n", format);
                return 1;
            }

            if (!ok) {
                if (scale_png) {
                    FileUtils.unlink(render_path);
                }
                // A render failure is usually a parse error the user can act on
                // ("Packet block 8 - 23 is not contiguous…"); saying only "export
                // failed" hides it.
                var parsed = engine.parse(processed ?? source, input_path, input_path);
                if (parsed.errors != null) {
                    foreach (var err in parsed.errors) {
                        printerr("Error: line %d: %s\n", err.line, err.message);
                    }
                }
                printerr("Error: export failed\n");
                return 1;
            }
            if (format == "png" && RenderUtils.png_downscale_note != null) {
                printerr("Warning: %s; export as SVG or PDF for full resolution\n",
                         RenderUtils.png_downscale_note);
            }

            if (scale_png) {
                string[] scale_cmd = {"convert", render_path, "-filter", "Lanczos", "-resize", "71.5%", output_path};
                int scale_exit = 0;
                try {
                    Process.spawn_sync(null, scale_cmd, null, SpawnFlags.SEARCH_PATH, null, null, null, out scale_exit);
                } finally {
                    FileUtils.unlink(render_path);
                }
                if (scale_exit != 0) {
                    printerr("Error: scaling the PNG with ImageMagick convert failed\n");
                    return 1;
                }
            }

            print("✓ Exported: %s\n", output_path);
            return 0;
        }

        private void on_about_action() {
            var about = new Adw.AboutDialog() {
                application_name = APP_NAME,
                application_icon = APP_ID,
                developer_name = "gDiagram Contributors",
                version = "%s (%s)".printf(VERSION, BUILD_ID),
                developers = { "gDiagram Contributors" },
                copyright = "© 2024 gDiagram Contributors",
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
