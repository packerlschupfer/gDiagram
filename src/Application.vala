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

            // Check for export mode first (headless)
            string? input_file = null;
            string? output_file = null;
            string export_format = "png";
            bool scale_output = false;  // Default: no scaling (native GraphViz size)

            bool dump_preprocessed = false;
            for (int i = 1; i < args.length; i++) {
                if (args[i] == "--export" || args[i] == "-e") {
                    if (i + 1 < args.length) {
                        output_file = args[++i];
                    }
                } else if (args[i] == "--format" || args[i] == "-f") {
                    if (i + 1 < args.length) {
                        export_format = args[++i];
                    }
                } else if (args[i] == "--scale") {
                    scale_output = true;  // Enable 71.5% scaling to match PlantUML dimensions
                } else if (args[i] == "--dump-preprocessed") {
                    dump_preprocessed = true;
                } else if (!args[i].has_prefix("-") && input_file == null) {
                    input_file = args[i];
                }
            }

            // --dump-preprocessed: emit preprocessor output to stdout and exit.
            // Useful for debugging macro expansion / stdlib resolution.
            if (dump_preprocessed && input_file != null) {
                try {
                    string content;
                    FileUtils.get_contents(input_file, out content);
                    var pp = new Preprocessor();
                    print("%s", pp.process(content, input_file));
                    if (pp.has_errors()) {
                        foreach (var err in pp.errors) {
                            printerr("preprocessor: line %d: %s\n", err.line, err.message);
                        }
                    }
                    return 0;
                } catch (Error e) {
                    printerr("Error: %s\n", e.message);
                    return 1;
                }
            }

            // Handle export mode (headless, no GUI)
            if (output_file != null && input_file != null) {
                return handle_export(input_file, output_file, export_format, scale_output);
            }

            // Parse command line options for GUI mode
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
                    print("Usage: gdiagram [OPTIONS] [FILE]\n");
                    print("Options:\n");
                    print("  -d, --debug              Enable debug output\n");
                    print("  -e, --export OUTPUT      Export to file (headless)\n");
                    print("  -f, --format FORMAT      Export format: png, svg, dot (default: png)\n");
                    print("  --scale                  Scale output 71.5%% to match PlantUML dimensions\n");
                    print("  -h, --help               Show this help\n");
                    print("  --version                Show version information\n");
                    print("\n");
                    print("Examples:\n");
                    print("  gdiagram diagram.puml                    # Open in GUI\n");
                    print("  gdiagram diagram.puml -e output.png     # Export to PNG\n");
                    print("  gdiagram diagram.puml -e out.svg -f svg # Export to SVG\n");
                    return 0;
                } else if (args[i] == "--version") {
                    print("gDiagram version %s\n", VERSION);
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
                    return do_export(engine, content, input_path, input_path,
                                     output_path, format, scale_output);
                }

                string processed = engine.preprocess(content, input_path);
                var diagram_type = engine.detect_plantuml_type(processed);
                print("  Detected type: %s\n", diagram_type.to_string());

                // PlantUML's @startpacketdiag block uses the same bit-range
                // body syntax as Mermaid packet-beta. Strip the wrapper and
                // route to the Mermaid packet renderer. Passing null as the
                // doc_filename forces the engine to detect the converted
                // source as Mermaid regardless of the .puml extension.
                if (diagram_type == DiagramType.MERMAID_PACKET) {
                    string mermaid_form = convert_packetdiag_to_mermaid(processed);
                    return do_export(engine, mermaid_form, null, null,
                                     output_path, format, scale_output);
                }

                if (diagram_type == DiagramType.UNKNOWN) {
                    printerr("Error: Could not determine diagram type for %s\n", input_path);
                    printerr("  No PlantUML keywords (@startuml, class, participant, state, ...)\n");
                    printerr("  and no Mermaid keywords (flowchart, sequenceDiagram, ...) found.\n");
                    print_source_head(processed);
                    return 1;
                }

                return do_export(engine, content, input_path, input_path,
                                 output_path, format, scale_output);

            } catch (Error e) {
                printerr("Export failed: %s\n", e.message);
                return 1;
            }
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
        // with optional 71.5% PLantUML-dimension scaling applied to PNG via
        // ImageMagick `convert` (matching the pre-engine behavior).
        private int do_export(DiagramEngine engine, string source, string? doc_filename,
                              string? base_path, string output_path, string format,
                              bool scale_output) throws Error {
            if (format == "dot") {
                string? dot_output = engine.generate_dot(source, doc_filename, base_path);
                if (dot_output == null || dot_output.length == 0) {
                    printerr("Error: could not generate DOT output\n");
                    return 1;
                }
                FileUtils.set_contents(output_path, dot_output);
                print("✓ Exported DOT file: %s\n", output_path);
                return 0;
            }

            // For scaled PNG, render to a temp path first, then scale it down.
            string render_path = (scale_output && format == "png")
                ? "/tmp/gdiagram_cli_export.png"
                : output_path;

            bool ok;
            if (format == "svg") {
                ok = engine.export_to_svg(source, doc_filename, base_path, render_path);
            } else if (format == "pdf") {
                ok = engine.export_to_pdf(source, doc_filename, base_path, render_path);
            } else {
                ok = engine.export_to_png(source, doc_filename, base_path, render_path);
            }

            if (!ok) {
                printerr("Error: export failed\n");
                return 1;
            }

            if (scale_output && format == "png") {
                string[] scale_cmd = {"convert", render_path, "-filter", "Lanczos", "-resize", "71.5%", output_path};
                int scale_exit;
                Process.spawn_sync(null, scale_cmd, null, SpawnFlags.SEARCH_PATH, null, null, null, out scale_exit);
            }

            print("✓ Exported: %s\n", output_path);
            return 0;
        }

        /**
         * Convert a PlantUML @startpacketdiag block to Mermaid packet-beta
         * form. The body uses the same "0-7: Field Name" syntax in both
         * formats — only the wrapper differs.
         *
         *   @startpacketdiag             →   packet-beta
         *   packetdiag {                     0-7: Source Port
         *      0-7: Source Port              8-15: Destination Port
         *      8-15: Destination Port
         *   }
         *   @endpacketdiag
         */
        private string convert_packetdiag_to_mermaid(string source) {
            var sb = new StringBuilder();
            sb.append("packet-beta\n");
            bool inside = false;
            foreach (var raw in source.split("\n")) {
                string trimmed = raw.strip();
                if (trimmed.has_prefix("@startpacketdiag")) {
                    inside = true;
                    continue;
                }
                if (trimmed == "@endpacketdiag") {
                    inside = false;
                    continue;
                }
                if (!inside) continue;
                // Skip the "packetdiag {" wrapper line and its closing "}"
                if (trimmed.has_prefix("packetdiag") || trimmed == "{" || trimmed == "}") {
                    continue;
                }
                if (trimmed.length == 0) continue;
                sb.append(trimmed);
                sb.append("\n");
            }
            return sb.str;
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
