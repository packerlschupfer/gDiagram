// Export formats the CLI accepts, matched case-insensitively. Anything else is an
// error: "-f SVG", "-f jpeg" and "-f ''" all used to fall through to a silent PNG.
const string[] CLI_EXPORT_FORMATS = { "png", "svg", "pdf", "dot" };

// Every option this binary understands itself. An argument starting with "-" that is
// not one of these is a typo: "--scal" (for --scale) used to export happily, unscaled
// and unmentioned, and "--bogus" was ignored outright. Only the headless paths below
// reject them -- GUI mode still forwards its arguments to GApplication, which has its
// own (--gapplication-service, --display, ...).
const string[] CLI_KNOWN_FLAGS = {
    "-e", "--export", "-f", "--format", "--scale",
    "-d", "--debug", "-h", "--help", "--version", "--dump-preprocessed"
};

// The canonical (lower-case) name of `format`, or null when it is not one of ours.
string? cli_normalize_export_format(string format) {
    string lowered = format.down();
    foreach (string known in CLI_EXPORT_FORMATS) {
        if (lowered == known) return known;
    }
    return null;
}

void cli_export_usage_error(string message) {
    stderr.printf("Error: %s\n", message);
    stderr.printf("Usage: gdiagram FILE -e OUTPUT [-f png|svg|pdf|dot] [--scale]\n");
}

bool cli_is_known_flag(string arg) {
    foreach (string known in CLI_KNOWN_FLAGS) {
        if (arg == known) return true;
    }
    return false;
}

/**
 * True when both names reach the same file.
 *
 * `gdiagram x.puml -e x.puml -f png` exited 0 and left a PNG where the source used to
 * be -- the diagram was read first, so nothing complained. GFile canonicalises the
 * path (".", "..", duplicate slashes, relative names), and when both names exist the
 * device/inode pair also catches a symlink or a hard link to the input.
 */
bool cli_same_file(string a, string b) {
    if (File.new_for_path(a).equal(File.new_for_path(b))) return true;
    try {
        // "id::file" is GIO's device+inode identity, so a symlink or a hard link
        // pointing back at the input is caught too. It needs both files to exist --
        // the output usually does not, and then the path comparison above is all
        // there is to go on.
        string? id_a = File.new_for_path(a)
            .query_info(FileAttribute.ID_FILE, FileQueryInfoFlags.NONE)
            .get_attribute_string(FileAttribute.ID_FILE);
        string? id_b = File.new_for_path(b)
            .query_info(FileAttribute.ID_FILE, FileQueryInfoFlags.NONE)
            .get_attribute_string(FileAttribute.ID_FILE);
        return id_a != null && id_a == id_b;
    } catch (Error e) {
        return false;
    }
}

int main(string[] args) {
    // --help/--version are printed here, before GApplication registration. Handling
    // them in Application.command_line() runs after GApplication/Adw startup, and
    // adw_init() -> adw_settings_get_default() opens a settings-portal D-Bus proxy
    // that never answers without a portal: `gdiagram --version` hung forever with no
    // output at all (repro: env -u WAYLAND_DISPLAY -u DISPLAY dbus-run-session --
    // gdiagram --version).
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--help" || args[i] == "-h") {
            GDiagram.Application.print_help();
            return 0;
        }
        if (args[i] == "--version") {
            GDiagram.Application.print_version();
            return 0;
        }
    }

    // One pass over the arguments for both headless paths below. Everything that used
    // to be dropped in silence -- a second input file, a repeated -e, an unknown flag --
    // is collected here so it can be reported instead.
    string? export_output = null;
    string export_format = "png";
    bool export_scale = false;
    bool export_requested = false;
    bool format_requested = false;
    bool dump_requested = false;
    int export_count = 0;
    int format_count = 0;
    string[] inputs = {};
    string[] unknown_flags = {};

    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--export" || args[i] == "-e") {
            // The value must be a real file name: `-e -f png` used to take "-f"
            // as the output path and write a file literally called "-f"
            if (i + 1 >= args.length || args[i + 1].has_prefix("-")) {
                cli_export_usage_error("%s needs an output file name".printf(args[i]));
                return 2;
            }
            export_requested = true;
            export_count++;
            export_output = args[++i];
        } else if (args[i] == "--format" || args[i] == "-f") {
            if (i + 1 >= args.length || args[i + 1].has_prefix("-")) {
                cli_export_usage_error("%s needs a format (png, svg, pdf or dot)".printf(args[i]));
                return 2;
            }
            format_requested = true;
            format_count++;
            export_format = args[++i];
        } else if (args[i] == "--scale") {
            export_scale = true;
        } else if (args[i] == "--dump-preprocessed") {
            dump_requested = true;
        } else if (args[i].has_prefix("-")) {
            if (!cli_is_known_flag(args[i])) unknown_flags += args[i];
        } else {
            inputs += args[i];
        }
    }

    // Early dispatch for the --dump-preprocessed debug flag — this avoids
    // the cost (and potential failure) of registering as a GApplication just
    // to dump preprocessor output. Useful for debugging macro expansion.
    if (dump_requested) {
        if (unknown_flags.length > 0) {
            stderr.printf("Error: unknown option '%s'\n", unknown_flags[0]);
            stderr.printf("Usage: gdiagram --dump-preprocessed FILE\n");
            return 2;
        }
        // The dump used to win silently over a simultaneous export, so
        // `gdiagram f.puml --dump-preprocessed -e out.png` wrote no file and said so
        if (export_requested || format_requested) {
            stderr.printf("Error: --dump-preprocessed cannot be combined with %s\n",
                          export_requested ? "-e/--export" : "-f/--format");
            return 2;
        }
        if (inputs.length == 0) {
            stderr.printf("Usage: gdiagram --dump-preprocessed FILE\n");
            return 1;
        }
        if (inputs.length > 1) {
            stderr.printf("Error: --dump-preprocessed takes one input file (got %d: %s)\n",
                          inputs.length, string.joinv(", ", inputs));
            return 2;
        }
        string input_file = inputs[0];
        try {
            string content;
            FileUtils.get_contents(input_file, out content);
            var pp = new GDiagram.Preprocessor();
            stdout.printf("%s", pp.process(content, input_file));
            // The export path exits 1 on an unresolved !include; dumping the same file
            // exited 0, so the two contracts disagreed about the same broken source
            bool include_failed = false;
            foreach (var err in pp.errors) {
                bool is_include = GDiagram.Application.is_include_failure(err.message);
                include_failed = include_failed || is_include;
                stderr.printf("%s: preprocessor: line %d: %s\n",
                              is_include ? "Error" : "Warning", err.line, err.message);
            }
            return include_failed ? 1 : 0;
        } catch (Error e) {
            stderr.printf("Error: %s\n", e.message);
            return 1;
        }
    }

    if (format_requested) {
        string? normalized = cli_normalize_export_format(export_format);
        if (normalized == null) {
            cli_export_usage_error("unknown export format '%s' (png, svg, pdf or dot)".printf(export_format));
            return 2;
        }
        export_format = normalized;
        if (!export_requested) {
            cli_export_usage_error("-f/--format only applies to an export; add -e OUTPUT");
            return 2;
        }
    }

    // Early dispatch for headless export (-e/--export). This must happen
    // BEFORE GApplication registration: command_line() only runs after the
    // app registers, and on display-less hosts (ssh, CI, containers) GTK
    // registration fails first — so a truly headless export never ran.
    // Registration also forwards args to an already-running primary
    // instance, which would export in the wrong process — an incomplete
    // export command (`gdiagram f.puml -e`) must therefore fail here rather
    // than fall through and put a stray window on the user's desktop.
    if (export_requested && export_output != null) {
        if (unknown_flags.length > 0) {
            cli_export_usage_error("unknown option '%s'".printf(unknown_flags[0]));
            return 2;
        }
        if (inputs.length == 0) {
            cli_export_usage_error("no input file to export");
            return 2;
        }
        // Two input files exported only the first one, without a word
        if (inputs.length > 1) {
            cli_export_usage_error("only one input file can be exported (got %d: %s)"
                                   .printf(inputs.length, string.joinv(", ", inputs)));
            return 2;
        }
        // A repeat is harmless, but which one won was invisible
        if (export_count > 1) {
            stderr.printf("Warning: -e/--export given %d times; exporting to '%s'\n",
                          export_count, export_output);
        }
        if (format_count > 1) {
            stderr.printf("Warning: -f/--format given %d times; using '%s'\n",
                          format_count, export_format);
        }
        string export_input = inputs[0];
        if (cli_same_file(export_input, export_output)) {
            cli_export_usage_error("the export would overwrite the input file '%s'"
                                   .printf(export_input));
            return 2;
        }
        var export_app = new GDiagram.Application();
        return export_app.run_headless_export(export_input, export_output,
                                              export_format, export_scale);
    }

    var app = new GDiagram.Application();
    return app.run(args);
}
