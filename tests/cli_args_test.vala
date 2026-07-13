/*
 * CLI argument validation for the gdiagram binary (src/main.vala).
 *
 * Every case here must be rejected BEFORE GApplication registration: an
 * incomplete export command used to fall through to GUI mode, where the args
 * were forwarded to a running primary instance and put a stray window on the
 * user's desktop. The runs below therefore also have no display and a bogus
 * session bus, so a regression cannot touch a real session -- but the point of
 * the test is the exit status and the message, not that containment.
 *
 * The binary path arrives from meson via GDIAGRAM_BIN.
 */
namespace GDiagram.Tests {

    public class CliArgsTests {

        private static string gdiagram_bin() {
            string? bin = Environment.get_variable("GDIAGRAM_BIN");
            if (bin == null || !FileUtils.test(bin, FileTest.IS_EXECUTABLE)) {
                error("GDIAGRAM_BIN must name the built gdiagram binary");
            }
            return bin;
        }

        private static string tmp_root() {
            if (root == null) {
                try {
                    root = DirUtils.make_tmp("gdiagram-cli-args-XXXXXX");
                } catch (FileError e) {
                    error("mkdtemp: %s", e.message);
                }
            }
            return root;
        }
        private static string? root = null;

        // A small valid diagram to export
        private static string source_file() {
            string path = Path.build_filename(tmp_root(), "doc.puml");
            if (!FileUtils.test(path, FileTest.EXISTS)) {
                try {
                    FileUtils.set_contents(path, "@startuml\nAlice -> Bob : hi\n@enduml\n");
                } catch (FileError e) {
                    error("write: %s", e.message);
                }
            }
            return path;
        }

        // A command that wrongly reaches GUI mode sits there waiting for a window to
        // close, so every run is bounded rather than hanging the suite.
        private const int TIMEOUT_S = 30;

        /**
         * Runs the CLI with no display and an unreachable session bus, so a command that
         * wrongly reaches GUI mode fails instead of opening a window. Returns the exit
         * status (-1 when it had to be killed) and the combined stderr.
         */
        private static int run_cli(string[] args, out string err_text) {
            err_text = "";
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE |
                                                  SubprocessFlags.STDERR_PIPE);
            launcher.setenv("GSETTINGS_BACKEND", "memory", true);
            launcher.setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-gdiagram-test", true);
            launcher.unsetenv("DISPLAY");
            launcher.unsetenv("WAYLAND_DISPLAY");

            string[] argv = { gdiagram_bin() };
            foreach (string a in args) argv += a;

            Subprocess proc;
            try {
                proc = launcher.spawnv(argv);
            } catch (Error e) {
                error("spawn: %s", e.message);
            }

            Bytes? err_bytes = null;
            bool done = false;
            bool timed_out = false;
            proc.communicate_async.begin(null, null, (obj, res) => {
                try {
                    proc.communicate_async.end(res, null, out err_bytes);
                } catch (Error e) {
                }
                done = true;
            });
            int64 deadline = get_monotonic_time() + (int64) TIMEOUT_S * 1000000;
            while (!done) {
                if (get_monotonic_time() > deadline) {
                    timed_out = true;
                    proc.force_exit();
                    break;
                }
                MainContext.default().iteration(false);
                Thread.usleep(20000);
            }
            if (timed_out) {
                while (!done) {
                    MainContext.default().iteration(false);
                    Thread.usleep(20000);
                }
                return -1;
            }
            if (err_bytes != null && err_bytes.get_size() > 0) {
                unowned uint8[]? raw = err_bytes.get_data();
                if (raw != null) {
                    var sb = new StringBuilder.sized(raw.length + 1);
                    sb.append_len((string) raw, raw.length);
                    err_text = sb.str;
                }
            }
            if (!proc.get_if_exited()) return -1;
            return proc.get_exit_status();
        }

        // -e with no output name (alone, or followed by another flag) must not reach
        // GUI mode: "-e -f png" used to write a file literally called "-f".
        public static void test_export_without_output() {
            string err;
            string doc = source_file();

            int rc = run_cli({ doc, "-e" }, out err);
            stderr.printf("`-e`: rc %d, stderr: %s", rc, err);
            assert(rc == 2);
            assert(err.contains("needs an output file name"));

            string stray = Path.build_filename(Environment.get_current_dir(), "-f");
            FileUtils.unlink(stray);
            rc = run_cli({ doc, "-e", "-f", "png" }, out err);
            stderr.printf("`-e -f png`: rc %d, stderr: %s", rc, err);
            assert(rc == 2);
            assert(err.contains("needs an output file name"));
            assert(!FileUtils.test(stray, FileTest.EXISTS));
            assert(!FileUtils.test("-f", FileTest.EXISTS));

            // --export behaves the same
            rc = run_cli({ doc, "--export" }, out err);
            assert(rc == 2);
            assert(err.contains("needs an output file name"));

            // ... and so does an export with no input file
            rc = run_cli({ "-e", Path.build_filename(tmp_root(), "noinput.png") }, out err);
            stderr.printf("`-e out.png` alone: rc %d, stderr: %s", rc, err);
            assert(rc == 2);
            assert(err.contains("no input file"));
        }

        // -f took anything and silently produced a PNG, including a wrong-case name
        public static void test_format_validation() {
            string err;
            string doc = source_file();
            string output = Path.build_filename(tmp_root(), "out.png");

            foreach (string bad in new string[] { "jpeg", "", "PNGG", "x" }) {
                FileUtils.unlink(output);
                int rc = run_cli({ doc, "-e", output, "-f", bad }, out err);
                stderr.printf("`-f %s`: rc %d, stderr: %s", bad, rc, err);
                assert(rc == 2);
                assert(err.contains("unknown export format"));
                assert(!FileUtils.test(output, FileTest.EXISTS));
            }

            // -f with no value at all
            int rc_bare = run_cli({ doc, "-e", output, "-f" }, out err);
            assert(rc_bare == 2);
            assert(err.contains("needs a format"));

            // -f without -e has nothing to apply to
            int rc_lonely = run_cli({ doc, "-f", "png" }, out err);
            stderr.printf("`-f png` without -e: rc %d, stderr: %s", rc_lonely, err);
            assert(rc_lonely == 2);
            assert(err.contains("only applies to an export"));
        }

        // A known format is accepted whatever its case, and produces that format
        public static void test_format_is_case_insensitive() {
            string err;
            string doc = source_file();
            string output = Path.build_filename(tmp_root(), "upper.svg");
            FileUtils.unlink(output);

            int rc = run_cli({ doc, "-e", output, "-f", "SVG" }, out err);
            stderr.printf("`-f SVG`: rc %d, stderr: %s", rc, err);
            assert(rc == 0);
            string written;
            try {
                FileUtils.get_contents(output, out written);
            } catch (FileError e) {
                error("read export: %s", e.message);
            }
            assert(written.contains("<svg"));
        }

        /**
         * Same as run_cli, but under `dbus-run-session`: a private session bus with no
         * settings portal on it. That is what hung --help and --version -- they were
         * handled inside command_line(), which only runs after GApplication/Adw startup,
         * and adw_init() -> adw_settings_get_default() waits forever on a settings-portal
         * proxy that nothing answers. Falls back to a plain run (and says so) where
         * dbus-run-session is not installed.
         */
        private static int run_cli_on_private_bus(string[] args, out string out_text, out string err_text) {
            out_text = "";
            err_text = "";
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE |
                                                  SubprocessFlags.STDERR_PIPE);
            launcher.setenv("GSETTINGS_BACKEND", "memory", true);
            launcher.unsetenv("DISPLAY");
            launcher.unsetenv("WAYLAND_DISPLAY");

            string[] argv = {};
            string? bus_runner = Environment.find_program_in_path("dbus-run-session");
            if (bus_runner != null) {
                argv += bus_runner;
                argv += "--";
            } else {
                stderr.printf("dbus-run-session not found: running without a session bus\n");
                launcher.setenv("DBUS_SESSION_BUS_ADDRESS",
                                "unix:path=/nonexistent-gdiagram-test", true);
            }
            argv += gdiagram_bin();
            foreach (string a in args) argv += a;

            Subprocess proc;
            try {
                proc = launcher.spawnv(argv);
            } catch (Error e) {
                error("spawn: %s", e.message);
            }

            Bytes? out_bytes = null;
            Bytes? err_bytes = null;
            bool done = false;
            bool timed_out = false;
            proc.communicate_async.begin(null, null, (obj, res) => {
                try {
                    proc.communicate_async.end(res, out out_bytes, out err_bytes);
                } catch (Error e) {
                }
                done = true;
            });
            int64 deadline = get_monotonic_time() + (int64) TIMEOUT_S * 1000000;
            while (!done) {
                if (get_monotonic_time() > deadline) {
                    timed_out = true;
                    proc.force_exit();
                    break;
                }
                MainContext.default().iteration(false);
                Thread.usleep(20000);
            }
            while (!done) {
                MainContext.default().iteration(false);
                Thread.usleep(20000);
            }
            out_text = bytes_text(out_bytes);
            err_text = bytes_text(err_bytes);
            if (timed_out) return -1;
            if (!proc.get_if_exited()) return -1;
            return proc.get_exit_status();
        }

        private static string bytes_text(Bytes? bytes) {
            if (bytes == null || bytes.get_size() == 0) return "";
            unowned uint8[]? raw = bytes.get_data();
            if (raw == null) return "";
            var sb = new StringBuilder.sized(raw.length + 1);
            sb.append_len((string) raw, raw.length);
            return sb.str;
        }

        /**
         * --help and --version must print and exit at once, with no display and no portal.
         *
         * They used to be handled in Application.command_line(), i.e. after GApplication
         * and Adw startup, and adw_init() -> adw_settings_get_default() opens a settings-
         * portal D-Bus proxy that nothing answers there:
         *   env -u WAYLAND_DISPLAY -u DISPLAY dbus-run-session -- gdiagram --version
         * printed nothing at all until that proxy gave up ~25 s later (the reporter saw
         * it never come back), so the check is on the TIME, not just on finishing.
         */
        private const int PROMPT_MS = 10000;

        public static void test_help_and_version_do_not_hang() {
            string output, err;

            int64 started = get_monotonic_time();
            int rc = run_cli_on_private_bus({ "--version" }, out output, out err);
            int64 took_ms = (get_monotonic_time() - started) / 1000;
            stderr.printf("`--version`: rc %d after %s ms, stdout: %s", rc, took_ms.to_string(), output);
            if (rc != 0) {
                printerr("\nFAILED: --version did not exit (rc %d)\n%s\n", rc, err);
                assert_not_reached();
            }
            if (took_ms > PROMPT_MS) {
                printerr("\nFAILED: --version took %s ms; it must not wait on any D-Bus proxy\n",
                         took_ms.to_string());
                assert_not_reached();
            }
            assert(output.contains("gDiagram version"));

            foreach (string flag in new string[] { "--help", "-h" }) {
                started = get_monotonic_time();
                rc = run_cli_on_private_bus({ flag }, out output, out err);
                took_ms = (get_monotonic_time() - started) / 1000;
                stderr.printf("`%s`: rc %d after %s ms\n", flag, rc, took_ms.to_string());
                if (rc != 0) {
                    printerr("\nFAILED: %s did not exit (rc %d)\n%s\n", flag, rc, err);
                    assert_not_reached();
                }
                if (took_ms > PROMPT_MS) {
                    printerr("\nFAILED: %s took %s ms; it must not wait on any D-Bus proxy\n",
                             flag, took_ms.to_string());
                    assert_not_reached();
                }
                // The wording the GUI path printed, unchanged
                assert(output.contains("Usage: gdiagram [OPTIONS] [FILE]"));
                assert(output.contains("-e, --export OUTPUT      Export to file (headless)"));
                assert(output.contains("--scale                  Scale output 71.5% to match PlantUML dimensions"));
                assert(output.contains("gdiagram diagram.puml -e out.svg -f svg # Export to SVG"));
            }
        }

        /**
         * An !include that exists but cannot be READ (chmod 000, or a directory) only
         * warned and exited 0, so a build missing half its diagram passed silently. It
         * is as unresolved as a missing file: exit 1, partial export still written.
         */
        public static void test_unreadable_include_is_an_error() {
            string dir = Path.build_filename(tmp_root(), "unreadable");
            DirUtils.create_with_parents(dir, 0755);
            string secret = Path.build_filename(dir, "secret.iuml");
            string doc = Path.build_filename(dir, "doc.puml");
            string as_dir = Path.build_filename(dir, "adir");
            DirUtils.create_with_parents(as_dir, 0755);
            try {
                FileUtils.set_contents(secret, "Bob -> Carol : hidden\n");
                FileUtils.set_contents(doc, "@startuml\n!include secret.iuml\nAlice -> Bob : hi\n@enduml\n");
                FileUtils.set_contents(Path.build_filename(dir, "dirdoc.puml"),
                                       "@startuml\n!include adir\nAlice -> Bob : hi\n@enduml\n");
            } catch (FileError e) {
                error("write: %s", e.message);
            }
            FileUtils.chmod(secret, 0);
            if (FileUtils.test(secret, FileTest.IS_REGULAR) &&
                access_is_allowed(secret)) {
                // root, or a filesystem that ignores the mode: the directory case below
                // still exercises the same path
                stderr.printf("note: %s is still readable, skipping the chmod case\n", secret);
            } else {
                string err;
                string svg_out = Path.build_filename(dir, "doc.svg");
                int rc = run_cli({ doc, "-e", svg_out, "-f", "svg" }, out err);
                stderr.printf("unreadable include: rc %d, stderr: %s", rc, err);
                if (rc == 0) {
                    printerr("\nFAILED: an unreadable !include must not exit 0\n%s\n", err);
                    assert_not_reached();
                }
                assert(err.contains("Cannot read include file"));
                // The contract the resolvable-include case already had: the partial
                // export is still written, only the status says it is incomplete
                assert(FileUtils.test(svg_out, FileTest.EXISTS));
            }

            string err2;
            string out2 = Path.build_filename(dir, "dirdoc.svg");
            int rc2 = run_cli({ Path.build_filename(dir, "dirdoc.puml"), "-e", out2, "-f", "svg" },
                              out err2);
            stderr.printf("include of a directory: rc %d, stderr: %s", rc2, err2);
            if (rc2 == 0) {
                printerr("\nFAILED: `!include <a directory>` must not exit 0\n%s\n", err2);
                assert_not_reached();
            }
            assert(err2.contains("Cannot read include file"));

            FileUtils.chmod(secret, 0600);
        }

        private static bool access_is_allowed(string path) {
            string ignored;
            try {
                FileUtils.get_contents(path, out ignored);
                return true;
            } catch (FileError e) {
                return false;
            }
        }

        /**
         * `gdiagram x.puml -e x.puml -f png` exited 0 and left a PNG where the source
         * had been -- the file was read before it was written, so nothing complained.
         */
        public static void test_export_over_input_is_refused() {
            string dir = Path.build_filename(tmp_root(), "overwrite");
            DirUtils.create_with_parents(dir, 0755);
            string doc = Path.build_filename(dir, "self.puml");
            string text = "@startuml\nAlice -> Bob : hi\n@enduml\n";
            try {
                FileUtils.set_contents(doc, text);
            } catch (FileError e) {
                error("write: %s", e.message);
            }

            string err;
            int rc = run_cli({ doc, "-e", doc, "-f", "png" }, out err);
            stderr.printf("export onto the input: rc %d, stderr: %s", rc, err);
            assert(rc == 2);
            assert(err.contains("would overwrite the input file"));
            string after;
            try {
                FileUtils.get_contents(doc, out after);
            } catch (FileError e) {
                error("read back: %s", e.message);
            }
            assert(after == text);

            // The same file under a different name: "./self.puml", and a symlink to it
            rc = run_cli({ doc, "-e", Path.build_filename(dir, ".") + "/self.puml", "-f", "png" },
                         out err);
            assert(rc == 2);
            assert(err.contains("would overwrite the input file"));

            string link = Path.build_filename(dir, "link.puml");
            FileUtils.unlink(link);
            if (FileUtils.symlink(doc, link) == 0) {
                rc = run_cli({ doc, "-e", link, "-f", "png" }, out err);
                stderr.printf("export onto a symlink to the input: rc %d, stderr: %s", rc, err);
                assert(rc == 2);
                try {
                    FileUtils.get_contents(doc, out after);
                } catch (FileError e) {
                    error("read back: %s", e.message);
                }
                assert(after == text);
            }

            // A different output is of course still fine
            string ok_out = Path.build_filename(dir, "self.svg");
            rc = run_cli({ doc, "-e", ok_out, "-f", "svg" }, out err);
            assert(rc == 0);
            assert(FileUtils.test(ok_out, FileTest.EXISTS));
        }

        /**
         * A typo used to export happily and say nothing: "--scal" (for --scale) produced
         * unscaled output, "--bogus" was ignored, a second input file was dropped, and a
         * repeated -e silently took the last one.
         */
        public static void test_unknown_flags_and_extra_inputs() {
            string doc = source_file();
            string err;
            string output = Path.build_filename(tmp_root(), "args.png");

            foreach (string bad in new string[] { "--scal", "--bogus", "-z" }) {
                FileUtils.unlink(output);
                int rc = run_cli({ doc, "-e", output, bad }, out err);
                stderr.printf("`%s`: rc %d, stderr: %s", bad, rc, err);
                if (rc == 0) {
                    printerr("\nFAILED: the unknown option %s was accepted\n%s\n", bad, err);
                    assert_not_reached();
                }
                assert(rc == 2);
                assert(err.contains("unknown option '%s'".printf(bad)));
                assert(!FileUtils.test(output, FileTest.EXISTS));
            }

            // Two input files exported only the first, in silence
            string second = Path.build_filename(tmp_root(), "second.puml");
            try {
                FileUtils.set_contents(second, "@startuml\nclass Second\n@enduml\n");
            } catch (FileError e) {
                error("write: %s", e.message);
            }
            FileUtils.unlink(output);
            int rc_two = run_cli({ doc, second, "-e", output }, out err);
            stderr.printf("two inputs: rc %d, stderr: %s", rc_two, err);
            assert(rc_two == 2);
            assert(err.contains("only one input file"));
            assert(!FileUtils.test(output, FileTest.EXISTS));

            // A repeat is harmless -- but which one won has to be said
            string first_out = Path.build_filename(tmp_root(), "first.svg");
            string last_out = Path.build_filename(tmp_root(), "last.svg");
            FileUtils.unlink(first_out);
            FileUtils.unlink(last_out);
            int rc_rep = run_cli({ doc, "-e", first_out, "-e", last_out, "-f", "svg" }, out err);
            stderr.printf("repeated -e: rc %d, stderr: %s", rc_rep, err);
            assert(rc_rep == 0);
            assert(err.contains(last_out));
            assert(FileUtils.test(last_out, FileTest.EXISTS));
            assert(!FileUtils.test(first_out, FileTest.EXISTS));

            // ... and the same for a repeated -f
            FileUtils.unlink(last_out);
            int rc_fmt = run_cli({ doc, "-e", last_out, "-f", "png", "-f", "svg" }, out err);
            stderr.printf("repeated -f: rc %d, stderr: %s", rc_fmt, err);
            assert(rc_fmt == 0);
            assert(err.contains("-f/--format given 2 times"));
        }

        /**
         * --dump-preprocessed exited 0 on an include the export path exits 1 for, and
         * quietly won over a simultaneous -e (which then wrote nothing at all).
         */
        public static void test_dump_preprocessed_contract() {
            string dir = Path.build_filename(tmp_root(), "dump");
            DirUtils.create_with_parents(dir, 0755);
            string broken = Path.build_filename(dir, "broken.puml");
            string clean = Path.build_filename(dir, "clean.puml");
            try {
                FileUtils.set_contents(broken,
                    "@startuml\n!include does_not_exist.iuml\nAlice -> Bob : hi\n@enduml\n");
                FileUtils.set_contents(clean, "@startuml\nAlice -> Bob : hi\n@enduml\n");
            } catch (FileError e) {
                error("write: %s", e.message);
            }

            // A clean file still dumps and exits 0
            string err;
            int rc = run_cli({ "--dump-preprocessed", clean }, out err);
            stderr.printf("clean dump: rc %d, stderr: %s", rc, err);
            assert(rc == 0);

            // The export path exits 1 for this file; the dump must agree
            int rc_export = run_cli({ broken, "-e", Path.build_filename(dir, "b.svg"), "-f", "svg" },
                                    out err);
            assert(rc_export == 1);
            int rc_dump = run_cli({ "--dump-preprocessed", broken }, out err);
            stderr.printf("broken dump: rc %d, stderr: %s", rc_dump, err);
            if (rc_dump == 0) {
                printerr("\nFAILED: --dump-preprocessed exited 0 on an include the export " +
                         "path exits %d for\n%s\n", rc_export, err);
                assert_not_reached();
            }
            assert(rc_dump == rc_export);
            assert(err.contains("does_not_exist.iuml"));

            // Asking for both at once used to dump and drop the export without a word
            string combo_out = Path.build_filename(dir, "combo.svg");
            FileUtils.unlink(combo_out);
            int rc_combo = run_cli({ clean, "--dump-preprocessed", "-e", combo_out, "-f", "svg" },
                                   out err);
            stderr.printf("dump + export: rc %d, stderr: %s", rc_combo, err);
            assert(rc_combo == 2);
            assert(err.contains("cannot be combined"));
            assert(!FileUtils.test(combo_out, FileTest.EXISTS));
        }

        /**
         * A PNG that could not be written said only "export failed", while the SVG and
         * PDF paths printed the underlying error. The Cairo status was dropped on the
         * floor in RenderUtils.export_svg_to_png().
         */
        public static void test_png_write_failure_reports_the_reason() {
            string doc = source_file();
            string unwritable = "/nonexistent-directory-gdiagram-test/out.png";
            string err;
            int rc = run_cli({ doc, "-e", unwritable, "-f", "png" }, out err);
            stderr.printf("unwritable PNG: rc %d, stderr: %s", rc, err);
            assert(rc != 0);
            if (!err.contains("Failed to write PNG")) {
                printerr("\nFAILED: the PNG write failure gave no reason:\n%s\n", err);
                assert_not_reached();
            }
            assert(err.contains(unwritable));
            // Cairo's own wording for the status, not just our sentence
            assert(err.down().contains("error while writing to output stream") ||
                   err.down().contains("no memory") || err.down().contains("write error"));
        }

        /**
         * A render that fails because the source is wrong must say WHY: only
         * "export failed" left the user with nothing to act on.
         */
        public static void test_parse_error_is_reported() {
            string path = Path.build_filename(tmp_root(), "bad.mmd");
            try {
                FileUtils.set_contents(path, "packet-beta\n0-15: \"H\"\n8-23: \"Overlap\"\n");
            } catch (FileError e) {
                error("write: %s", e.message);
            }
            string out_path = Path.build_filename(tmp_root(), "bad.svg");
            string err;
            int status = run_cli({ path, "-e", out_path, "-f", "svg" }, out err);
            if (status == 0) {
                printerr("\nFAILED: an overlapping packet range must not export\n%s\n", err);
                assert_not_reached();
            }
            if (!err.contains("not contiguous")) {
                printerr("\nFAILED: the parse error must reach the user, got:\n%s\n", err);
                assert_not_reached();
            }
        }

        /**
         * `--version` must identify the BUILD, not just the frozen release version: the
         * version is pinned at 0.1.0 and the .deb's file mtimes are pinned by
         * SOURCE_DATE_EPOCH, so a user had no way to tell a July build from an October one
         * except by probing behaviour.
         */
        public static void test_version_identifies_the_build() {
            string outp;
            string err;
            int status = run_cli_on_private_bus({ "--version" }, out outp, out err);
            string text = outp + err;
            if (status != 0) {
                printerr("\nFAILED: --version exited %d\n%s\n", status, text);
                assert_not_reached();
            }
            if (!text.contains(VERSION)) {
                printerr("\nFAILED: no release version in: %s\n", text);
                assert_not_reached();
            }
            if (BUILD_ID == "unknown" || !text.contains(BUILD_ID)) {
                printerr("\nFAILED: no build id (%s) in: %s\n", BUILD_ID, text);
                assert_not_reached();
            }
            if (BUILD_DATE == "unknown" || !text.contains(BUILD_DATE)) {
                printerr("\nFAILED: no build date (%s) in: %s\n", BUILD_DATE, text);
                assert_not_reached();
            }
        }
        /**
         * Graphviz warns "Orthogonal edges do not currently handle edge labels" on every
         * labelled link once we ask for ortho routing — which we do deliberately, because
         * the alternative (xlabel) is placed after layout and lands on container borders.
         * The user can do nothing about it, so it must not reach their terminal.
         */
        public static void test_no_graphviz_ortho_label_noise() {
            string path = Path.build_filename(tmp_root(), "ortho.puml");
            try {
                FileUtils.set_contents(path,
                    "@startuml\nskinparam linetype ortho\nclass A\nclass B\nA --> B : labelled\n@enduml\n");
            } catch (FileError e) {
                error("write: %s", e.message);
            }
            string outp;
            string err;
            int status = run_cli_on_private_bus(
                { path, "-e", Path.build_filename(tmp_root(), "ortho.svg"), "-f", "svg" }, out outp, out err);
            string text = outp + err;
            if (status != 0) {
                printerr("\nFAILED: the export failed: %s\n", text);
                assert_not_reached();
            }
            if (text.contains("Orthogonal edges") || text.contains("Try using xlabels")) {
                printerr("\nFAILED: Graphviz's ortho/label warning reached the user:\n%s\n", text);
                assert_not_reached();
            }
            // and the suppression must be that one message, not all of Graphviz's output
            if (text.down().contains("warning:")) {
                printerr("\nFAILED: an unexpected warning survived:\n%s\n", text);
                assert_not_reached();
            }
        }
    }



    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/cli-args/export_without_output", CliArgsTests.test_export_without_output);
        Test.add_func("/cli-args/format_validation", CliArgsTests.test_format_validation);
        Test.add_func("/cli-args/format_case_insensitive", CliArgsTests.test_format_is_case_insensitive);
        Test.add_func("/cli-args/parse_error_reported", CliArgsTests.test_parse_error_is_reported);
        Test.add_func("/cli-args/version_identifies_build", CliArgsTests.test_version_identifies_the_build);
        Test.add_func("/cli-args/no_graphviz_label_noise", CliArgsTests.test_no_graphviz_ortho_label_noise);
        Test.add_func("/cli-args/help_and_version_do_not_hang",
                      CliArgsTests.test_help_and_version_do_not_hang);
        Test.add_func("/cli-args/unreadable_include_is_an_error",
                      CliArgsTests.test_unreadable_include_is_an_error);
        Test.add_func("/cli-args/export_over_input_refused",
                      CliArgsTests.test_export_over_input_is_refused);
        Test.add_func("/cli-args/unknown_flags_and_extra_inputs",
                      CliArgsTests.test_unknown_flags_and_extra_inputs);
        Test.add_func("/cli-args/dump_preprocessed_contract",
                      CliArgsTests.test_dump_preprocessed_contract);
        Test.add_func("/cli-args/png_write_failure_reason",
                      CliArgsTests.test_png_write_failure_reports_the_reason);
        return Test.run();
    }
}
