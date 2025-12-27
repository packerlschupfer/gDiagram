namespace GDiagram.Tests {
    public class ParserTests {
        public static void test_basic_sequence_diagram() {
            string source = """
@startuml
participant Alice
participant Bob
Alice -> Bob: Hello
@enduml
""";
            var parser = new Parser(source);
            var diagram = parser.parse();

            assert(diagram != null);
        }

        public static void test_class_diagram() {
            string source = """
@startuml
class User {
  +name: String
  +email: String
}
@enduml
""";
            var parser = new Parser(source);
            var diagram = parser.parse();

            assert(diagram != null);
        }

        public static void test_activity_diagram() {
            string source = """
@startuml
start
:Action 1;
:Action 2;
stop
@enduml
""";
            var parser = new Parser(source);
            var diagram = parser.parse();

            assert(diagram != null);
        }

        public static void test_empty_diagram() {
            string source = """
@startuml
@enduml
""";
            var parser = new Parser(source);
            var diagram = parser.parse();

            assert(diagram != null);
        }

        public static void test_invalid_syntax() {
            string source = """
@startuml
this is not valid plantuml
@enduml
""";
            var parser = new Parser(source);
            var diagram = parser.parse();

            // Parser should handle gracefully, even if with errors
            assert(diagram != null);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/parser/basic_sequence_diagram", ParserTests.test_basic_sequence_diagram);
        Test.add_func("/parser/class_diagram", ParserTests.test_class_diagram);
        Test.add_func("/parser/activity_diagram", ParserTests.test_activity_diagram);
        Test.add_func("/parser/empty_diagram", ParserTests.test_empty_diagram);
        Test.add_func("/parser/invalid_syntax", ParserTests.test_invalid_syntax);

        return Test.run();
    }
}
