int main(string[] args) {
    // Early dispatch for the --dump-preprocessed debug flag — this avoids
    // the cost (and potential failure) of registering as a GApplication just
    // to dump preprocessor output. Useful for debugging macro expansion.
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--dump-preprocessed") {
            string? input_file = null;
            for (int j = 1; j < args.length; j++) {
                if (!args[j].has_prefix("-")) { input_file = args[j]; break; }
            }
            if (input_file == null) {
                stderr.printf("Usage: gdiagram --dump-preprocessed FILE\n");
                return 1;
            }
            try {
                string content;
                FileUtils.get_contents(input_file, out content);
                var pp = new GDiagram.Preprocessor();
                stdout.printf("%s", pp.process(content, input_file));
                if (pp.has_errors()) {
                    foreach (var err in pp.errors) {
                        stderr.printf("preprocessor: line %d: %s\n", err.line, err.message);
                    }
                }
                return 0;
            } catch (Error e) {
                stderr.printf("Error: %s\n", e.message);
                return 1;
            }
        }
    }

    // Early dispatch for headless export (-e/--export). This must happen
    // BEFORE GApplication registration: command_line() only runs after the
    // app registers, and on display-less hosts (ssh, CI, containers) GTK
    // registration fails first — so a truly headless export never ran.
    // Registration also forwards args to an already-running primary
    // instance, which would export in the wrong process.
    string? export_input = null;
    string? export_output = null;
    string export_format = "png";
    bool export_scale = false;
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--export" || args[i] == "-e") {
            if (i + 1 < args.length) export_output = args[++i];
        } else if (args[i] == "--format" || args[i] == "-f") {
            if (i + 1 < args.length) export_format = args[++i];
        } else if (args[i] == "--scale") {
            export_scale = true;
        } else if (!args[i].has_prefix("-") && export_input == null) {
            export_input = args[i];
        }
    }
    if (export_input != null && export_output != null) {
        var export_app = new GDiagram.Application();
        return export_app.run_headless_export(export_input, export_output,
                                              export_format, export_scale);
    }

    var app = new GDiagram.Application();
    return app.run(args);
}
