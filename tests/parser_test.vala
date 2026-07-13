namespace GDiagram.Tests {
    public class ParserTests {
        public static void test_basic_sequence_diagram() {
            string source = """@startuml
participant Alice
participant Bob
Alice -> Bob: Hello
@enduml
""";
            var parser = new Parser();
            var diagram = parser.parse(source);
            assert(diagram != null);
            assert(diagram.participants.size >= 2);
        }

        public static void test_sequence_with_message() {
            string source = """@startuml
Alice -> Bob: Hello World
@enduml
""";
            var parser = new Parser();
            var diagram = parser.parse(source);
            assert(diagram != null);
            assert(diagram.participants.size >= 2);
        }

        public static void test_empty_diagram() {
            string source = """@startuml
@enduml
""";
            var parser = new Parser();
            var diagram = parser.parse(source);
            assert(diagram != null);
        }

        public static void test_invalid_syntax_graceful() {
            string source = """@startuml
this is not valid plantuml
@enduml
""";
            var parser = new Parser();
            var diagram = parser.parse(source);
            // Parser must never crash on invalid input
            assert(diagram != null);
        }

        public static void test_participant_aliases() {
            string source = """@startuml
participant "Alice Smith" as A
participant "Bob Jones" as B
A -> B: Hi
@enduml
""";
            var parser = new Parser();
            var diagram = parser.parse(source);
            assert(diagram != null);
            assert(diagram.participants.size >= 2);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/parser/basic_sequence_diagram", ParserTests.test_basic_sequence_diagram);
        Test.add_func("/parser/sequence_with_message", ParserTests.test_sequence_with_message);
        Test.add_func("/parser/empty_diagram", ParserTests.test_empty_diagram);
        Test.add_func("/parser/invalid_syntax_graceful", ParserTests.test_invalid_syntax_graceful);
        Test.add_func("/parser/participant_aliases", ParserTests.test_participant_aliases);

        return Test.run();
    }
}
