namespace GPlantUML.Tests {
    public class LexerTests {
        public static void test_basic_tokens() {
            var lexer = new Lexer("@startuml\n@enduml");
            var tokens = lexer.tokenize();

            assert(tokens.size >= 2);
            assert(tokens[0].type == TokenType.START_UML);
            assert(tokens[tokens.size - 2].type == TokenType.END_UML);
            assert(tokens[tokens.size - 1].type == TokenType.EOF);
        }

        public static void test_participant_tokens() {
            var lexer = new Lexer("participant Alice");
            var tokens = lexer.tokenize();

            assert(tokens.size == 3); // PARTICIPANT, IDENTIFIER, EOF
            assert(tokens[0].type == TokenType.PARTICIPANT);
            assert(tokens[1].type == TokenType.IDENTIFIER);
            assert(tokens[1].value == "Alice");
        }

        public static void test_arrow_tokens() {
            var lexer = new Lexer("Alice -> Bob");
            var tokens = lexer.tokenize();

            assert(tokens.size >= 4); // IDENTIFIER, ARROW, IDENTIFIER, EOF
            assert(tokens[0].type == TokenType.IDENTIFIER);
            assert(tokens[1].type == TokenType.ARROW);
            assert(tokens[2].type == TokenType.IDENTIFIER);
        }

        public static void test_string_literals() {
            var lexer = new Lexer("\"Hello World\"");
            var tokens = lexer.tokenize();

            assert(tokens.size == 2); // STRING, EOF
            assert(tokens[0].type == TokenType.STRING);
            assert(tokens[0].value == "Hello World");
        }

        public static void test_comments() {
            var lexer = new Lexer("' This is a comment\nparticipant Alice");
            var tokens = lexer.tokenize();

            // Comments should be skipped
            assert(tokens[0].type == TokenType.PARTICIPANT);
        }

        public static void test_keywords() {
            var lexer = new Lexer("class interface abstract enum");
            var tokens = lexer.tokenize();

            assert(tokens[0].type == TokenType.CLASS);
            assert(tokens[1].type == TokenType.INTERFACE);
            assert(tokens[2].type == TokenType.ABSTRACT);
            assert(tokens[3].type == TokenType.ENUM);
        }

        public static void test_line_tracking() {
            var lexer = new Lexer("participant Alice\nparticipant Bob");
            var tokens = lexer.tokenize();

            assert(tokens[0].line == 1);
            assert(tokens[2].line == 2); // Bob should be on line 2
        }

        public static void test_empty_source() {
            var lexer = new Lexer("");
            var tokens = lexer.tokenize();

            assert(tokens.size == 1);
            assert(tokens[0].type == TokenType.EOF);
        }

        public static void test_multiline_string() {
            var lexer = new Lexer("note left\nThis is\na multi-line\nnote\nend note");
            var tokens = lexer.tokenize();

            // Should handle multi-line content
            assert(tokens.size > 0);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);

        Test.add_func("/lexer/basic_tokens", LexerTests.test_basic_tokens);
        Test.add_func("/lexer/participant_tokens", LexerTests.test_participant_tokens);
        Test.add_func("/lexer/arrow_tokens", LexerTests.test_arrow_tokens);
        Test.add_func("/lexer/string_literals", LexerTests.test_string_literals);
        Test.add_func("/lexer/comments", LexerTests.test_comments);
        Test.add_func("/lexer/keywords", LexerTests.test_keywords);
        Test.add_func("/lexer/line_tracking", LexerTests.test_line_tracking);
        Test.add_func("/lexer/empty_source", LexerTests.test_empty_source);
        Test.add_func("/lexer/multiline_string", LexerTests.test_multiline_string);

        return Test.run();
    }
}
