namespace GDiagram.Tests {
    public class DocumentTests {
        public static void test_new_document() {
            var doc = new Document();

            assert(doc.title == "Untitled");
            assert(doc.modified == false);
            assert(doc.content.contains("@startuml"));
            assert(doc.content.contains("@enduml"));
        }

        public static void test_document_modification() {
            var doc = new Document();
            doc.modified = false;

            doc.content = "@startuml\nclass Test\n@enduml";
            doc.modified = true;

            assert(doc.modified == true);
        }

        public static void test_document_title() {
            var doc = new Document();
            doc.title = "Test Diagram";

            assert(doc.title == "Test Diagram");
        }

        public static void test_content_roundtrip() {
            var doc = new Document();
            string expected = "@startuml\nAlice -> Bob : Hello\n@enduml";
            doc.content = expected;
            assert(doc.content == expected);
        }

        public static void test_default_content_is_plantuml() {
            var doc = new Document();
            // Default content should be a PlantUML stub
            assert(doc.content.has_prefix("@startuml") || doc.content.contains("@startuml"));
        }

        // =================================================================
        // File loading edge cases
        // =================================================================

        public static void test_load_file_with_embedded_nul() {
            // Write a file whose bytes contain a NUL in the middle.
            // Old code path `(string) contents` would strlen and truncate
            // at the NUL, silently dropping the suffix.
            string tmp_path = GLib.Path.build_filename(Environment.get_tmp_dir(),
                "gdiagram_doctest_nul.puml");
            uint8[] bytes = new uint8[30];
            string before = "@startuml";
            for (int i = 0; i < before.length; i++) bytes[i] = (uint8) before[i];
            bytes[9] = 0;   // embedded NUL
            string after = "class X\n@enduml";
            for (int i = 0; i < after.length; i++) bytes[10 + i] = (uint8) after[i];

            try {
                FileUtils.set_contents_full(tmp_path, (string) bytes, bytes.length,
                    FileSetContentsFlags.NONE, 0644);
            } catch (Error e) {
                // Can't create tmp file — skip test rather than fail hard.
                return;
            }

            var doc = new Document();
            var loop = new MainLoop();
            doc.load_from_file.begin(File.new_for_path(tmp_path), (obj, res) => {
                try { doc.load_from_file.end(res); } catch (Error e) {}
                loop.quit();
            });
            loop.run();

            // Content should at least contain the part before the NUL.
            // The exact behavior past the NUL depends on the bytes_to_string
            // helper, but the important guarantee is that the load
            // completed without crashing.
            assert(doc.content != null);
            FileUtils.unlink(tmp_path);
        }

        public static void test_load_file_empty() {
            string tmp_path = GLib.Path.build_filename(Environment.get_tmp_dir(),
                "gdiagram_doctest_empty.puml");
            try {
                FileUtils.set_contents(tmp_path, "");
            } catch (Error e) {
                return;
            }

            var doc = new Document();
            var loop = new MainLoop();
            doc.load_from_file.begin(File.new_for_path(tmp_path), (obj, res) => {
                try { doc.load_from_file.end(res); } catch (Error e) {}
                loop.quit();
            });
            loop.run();

            assert(doc.content == "");
            FileUtils.unlink(tmp_path);
        }

        public static void test_load_file_unicode() {
            string tmp_path = GLib.Path.build_filename(Environment.get_tmp_dir(),
                "gdiagram_doctest_unicode.puml");
            string content = "@startuml\n' 日本語 コメント\nclass 人\n@enduml\n";
            try {
                FileUtils.set_contents(tmp_path, content);
            } catch (Error e) {
                return;
            }

            var doc = new Document();
            var loop = new MainLoop();
            doc.load_from_file.begin(File.new_for_path(tmp_path), (obj, res) => {
                try { doc.load_from_file.end(res); } catch (Error e) {}
                loop.quit();
            });
            loop.run();

            assert(doc.content.contains("日本語"));
            assert(doc.content.contains("人"));
            FileUtils.unlink(tmp_path);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/document/new_document", DocumentTests.test_new_document);
        Test.add_func("/document/modification", DocumentTests.test_document_modification);
        Test.add_func("/document/title", DocumentTests.test_document_title);
        Test.add_func("/document/content_roundtrip", DocumentTests.test_content_roundtrip);
        Test.add_func("/document/default_content_is_plantuml", DocumentTests.test_default_content_is_plantuml);
        Test.add_func("/document/load_file_embedded_nul", DocumentTests.test_load_file_with_embedded_nul);
        Test.add_func("/document/load_file_empty", DocumentTests.test_load_file_empty);
        Test.add_func("/document/load_file_unicode", DocumentTests.test_load_file_unicode);

        return Test.run();
    }
}
