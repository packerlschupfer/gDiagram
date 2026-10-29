namespace GDiagram.Tests {

    /**
     * Every icon we install must load with GdkPixbuf, not merely render with
     * librsvg.
     *
     * The two disagree, and the disagreement is not academic: flatpak validates
     * exported icons with GdkPixbuf, so an icon librsvg draws happily can still
     * fail `flatpak build-export` with "not a valid icon: Format not
     * recognized" and take the whole release with it. That is how v0.1.3 failed
     * — a multi-line comment before `<svg>` pushed the signature out of the
     * window GdkPixbuf sniffs, while every local render looked fine.
     *
     * The suite walks the installed icon tree rather than naming files, so an
     * icon added later is covered without anyone remembering this.
     */
    public class IconAssetsTests {

        /** data/icons in the source tree, from the env the test() sets. */
        private static string icons_root() {
            string? root = Environment.get_variable("GDIAGRAM_ICONS_ROOT");
            if (root == null || root.length == 0) {
                error("GDIAGRAM_ICONS_ROOT is unset — tests/meson.build must pass it");
            }
            return root;
        }

        private static void collect_svgs(File dir, Gee.ArrayList<string> into) {
            try {
                var e = dir.enumerate_children("standard::name,standard::type",
                                               FileQueryInfoFlags.NONE);
                FileInfo? info;
                while ((info = e.next_file()) != null) {
                    var child = dir.resolve_relative_path(info.get_name());
                    if (info.get_file_type() == FileType.DIRECTORY) {
                        collect_svgs(child, into);
                    } else if (info.get_name().has_suffix(".svg")) {
                        into.add(child.get_path());
                    }
                }
            } catch (Error err) {
                error("walking %s: %s", dir.get_path(), err.message);
            }
        }

        public static void test_every_icon_loads() {
            var svgs = new Gee.ArrayList<string>();
            collect_svgs(File.new_for_path(icons_root()), svgs);

            // A sanity floor: if the walk finds nothing, the test is vacuous
            // and would pass against an empty tree.
            if (svgs.size < 2) {
                printerr("only %d SVG(s) under %s — the walk is not seeing the icons\n",
                         svgs.size, icons_root());
                assert_not_reached();
            }

            int failed = 0;
            foreach (string path in svgs) {
                try {
                    var pb = new Gdk.Pixbuf.from_file(path);
                    if (pb.get_width() <= 0 || pb.get_height() <= 0) {
                        printerr("%s loaded with no size\n", path);
                        failed++;
                    }
                } catch (Error err) {
                    printerr("%s does not load with GdkPixbuf: %s\n", path, err.message);
                    failed++;
                }
            }
            if (failed > 0) {
                printerr("%d of %d icon(s) would fail flatpak's export validation\n",
                         failed, svgs.size);
                assert_not_reached();
            }
        }

        /**
         * The app icon and its symbolic must both exist under the names the
         * desktop file and the shell look up.
         */
        public static void test_app_and_symbolic_present() {
            string app = Path.build_filename(icons_root(), "hicolor", "scalable",
                                             "apps", "org.gnome.gDiagram.svg");
            string sym = Path.build_filename(icons_root(), "hicolor", "symbolic",
                                             "apps", "org.gnome.gDiagram-symbolic.svg");
            assert(FileUtils.test(app, FileTest.EXISTS));
            assert(FileUtils.test(sym, FileTest.EXISTS));

            // A symbolic is recoloured by GTK, so it must be single-colour: no
            // gradients, and nothing painted in the brand blue.
            string text;
            try {
                FileUtils.get_contents(sym, out text);
            } catch (FileError e) {
                error("reading %s: %s", sym, e.message);
            }
            assert(!text.down().contains("lineargradient"));
            assert(!text.down().contains("radialgradient"));
            assert(!text.down().contains("#1c71d8"));
        }

        public static int main(string[] args) {
            Test.init(ref args);
            Test.add_func("/icons/every-icon-loads", test_every_icon_loads);
            Test.add_func("/icons/app-and-symbolic-present", test_app_and_symbolic_present);
            return Test.run();
        }
    }
}
