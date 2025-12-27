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

        public static async void test_save_and_load() {
            var doc = new Document();
            var temp_file = File.new_for_path("/tmp/test_diagram.puml");

            doc.file = temp_file;
            doc.content = "@startuml\nclass Test\n@enduml";

            try {
                yield doc.save();

                var new_doc = new Document();
                yield new_doc.load_from_file(temp_file);

                assert(new_doc.content == doc.content);
                assert(new_doc.title == "test_diagram.puml");
                assert(new_doc.modified == false);

                // Cleanup
                temp_file.delete();
            } catch (Error e) {
                assert_not_reached();
            }
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/document/new_document", DocumentTests.test_new_document);
        Test.add_func("/document/modification", DocumentTests.test_document_modification);
        Test.add_func("/document/title", DocumentTests.test_document_title);

        // Async test
        var loop = new MainLoop();
        Test.add_func("/document/save_and_load", () => {
            DocumentTests.test_save_and_load.begin((obj, res) => {
                DocumentTests.test_save_and_load.end(res);
                loop.quit();
            });
            loop.run();
        });

        return Test.run();
    }
}
