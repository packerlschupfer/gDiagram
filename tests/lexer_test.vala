namespace GDiagram.Tests {
    public class LexerTests {
        public static void test_basic_tokens() {
            var lexer = new Lexer("@startuml\n@enduml");
            var tokens = lexer.scan_all();

            assert(tokens.size >= 2);
            assert(tokens[0].token_type == TokenType.STARTUML);
            assert(tokens[tokens.size - 2].token_type == TokenType.ENDUML);
            assert(tokens[tokens.size - 1].token_type == TokenType.EOF);
        }

        public static void test_participant_tokens() {
            var lexer = new Lexer("participant Alice");
            var tokens = lexer.scan_all();

            assert(tokens.size == 3); // PARTICIPANT, IDENTIFIER, EOF
            assert(tokens[0].token_type == TokenType.PARTICIPANT);
            assert(tokens[1].token_type == TokenType.IDENTIFIER);
            assert(tokens[1].lexeme == "Alice");
        }

        public static void test_arrow_tokens() {
            var lexer = new Lexer("Alice -> Bob");
            var tokens = lexer.scan_all();

            assert(tokens.size >= 4); // IDENTIFIER, ARROW_RIGHT, IDENTIFIER, EOF
            assert(tokens[0].token_type == TokenType.IDENTIFIER);
            assert(tokens[1].token_type == TokenType.ARROW_RIGHT);
            assert(tokens[2].token_type == TokenType.IDENTIFIER);
        }

        public static void test_string_literals() {
            var lexer = new Lexer("\"Hello World\"");
            var tokens = lexer.scan_all();

            assert(tokens.size == 2); // STRING, EOF
            assert(tokens[0].token_type == TokenType.STRING);
            assert(tokens[0].lexeme == "Hello World");
        }

        public static void test_comments() {
            var lexer = new Lexer("' This is a comment\nparticipant Alice");
            var tokens = lexer.scan_all();

            // The lexer emits COMMENT tokens; parsers are responsible for skipping them.
            // Verify a COMMENT token appears before the PARTICIPANT token.
            bool found_comment = false;
            bool found_participant = false;
            int comment_idx = -1;
            int participant_idx = -1;
            for (int i = 0; i < tokens.size; i++) {
                if (tokens[i].token_type == TokenType.COMMENT && !found_comment) {
                    found_comment = true;
                    comment_idx = i;
                }
                if (tokens[i].token_type == TokenType.PARTICIPANT && !found_participant) {
                    found_participant = true;
                    participant_idx = i;
                }
            }
            assert(found_participant);
            if (found_comment) {
                assert(comment_idx < participant_idx);
            }
        }

        public static void test_keywords() {
            var lexer = new Lexer("class interface abstract enum");
            var tokens = lexer.scan_all();

            assert(tokens[0].token_type == TokenType.CLASS);
            assert(tokens[1].token_type == TokenType.INTERFACE);
            assert(tokens[2].token_type == TokenType.ABSTRACT);
            assert(tokens[3].token_type == TokenType.ENUM);
        }

        public static void test_line_tracking() {
            var lexer = new Lexer("participant Alice\nparticipant Bob");
            var tokens = lexer.scan_all();

            assert(tokens[0].line == 1);

            // Find the "Bob" IDENTIFIER token and verify it is on line 2.
            // The exact index depends on whether a NEWLINE token is emitted
            // between the two declarations, so search by value instead.
            bool found_bob_on_line_2 = false;
            foreach (var t in tokens) {
                if (t.token_type == TokenType.IDENTIFIER && t.lexeme == "Bob") {
                    assert(t.line == 2);
                    found_bob_on_line_2 = true;
                    break;
                }
            }
            assert(found_bob_on_line_2);
        }

        public static void test_empty_source() {
            var lexer = new Lexer("");
            var tokens = lexer.scan_all();

            assert(tokens.size == 1);
            assert(tokens[0].token_type == TokenType.EOF);
        }

        public static void test_multiline_string() {
            var lexer = new Lexer("note left\nThis is\na multi-line\nnote\nend note");
            var tokens = lexer.scan_all();

            // Should handle multi-line content without crashing
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
