using GDiagram;

void test_flowchart_tokens() {
    string source = """flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Process]
    B -->|No| D[End]
""";

    var lexer = new MermaidLexer(source);
    var tokens = lexer.scan_all();

    print("Flowchart lexer test:\n");
    print("Found %d tokens\n", tokens.size);

    // Verify diagram type is recognized
    assert(tokens[0].token_type == MermaidTokenType.FLOWCHART);
    assert(tokens[1].token_type == MermaidTokenType.TD);

    // Check some identifiers
    bool found_a = false;
    bool found_arrow = false;
    bool found_bracket = false;

    foreach (var token in tokens) {
        print("  %s\n", token.to_string());

        if (token.lexeme == "A") {
            found_a = true;
        }
        if (token.token_type == MermaidTokenType.ARROW_SOLID) {
            found_arrow = true;
        }
        if (token.token_type == MermaidTokenType.LBRACKET) {
            found_bracket = true;
        }
    }

    assert(found_a);
    assert(found_arrow);
    assert(found_bracket);

    print("✓ Flowchart tokens test passed\n\n");
}

void test_sequence_diagram_tokens() {
    string source = """sequenceDiagram
    participant Alice
    participant Bob
    Alice->>Bob: Hello Bob
    Bob-->>Alice: Hi Alice
""";

    var lexer = new MermaidLexer(source);
    var tokens = lexer.scan_all();

    print("Sequence diagram lexer test:\n");
    print("Found %d tokens\n", tokens.size);

    // Verify diagram type
    assert(tokens[0].token_type == MermaidTokenType.SEQUENCE_DIAGRAM);

    // Check for participant keyword
    bool found_participant = false;
    bool found_alice = false;
    bool found_arrow = false;

    foreach (var token in tokens) {
        print("  %s\n", token.to_string());

        if (token.token_type == MermaidTokenType.PARTICIPANT) {
            found_participant = true;
        }
        if (token.lexeme == "Alice") {
            found_alice = true;
        }
        if (token.token_type == MermaidTokenType.SEQ_SOLID_ARROW) {
            found_arrow = true;
        }
    }

    assert(found_participant);
    assert(found_alice);
    assert(found_arrow);

    print("✓ Sequence diagram tokens test passed\n\n");
}

void test_arrow_types() {
    string source = """A --> B
C -.-> D
E ==> F
G --o H
I --x J
""";

    var lexer = new MermaidLexer(source);
    var tokens = lexer.scan_all();

    print("Arrow types test:\n");
    print("Found %d tokens\n", tokens.size);

    bool found_solid = false;
    bool found_dotted = false;
    bool found_thick = false;
    bool found_open = false;
    bool found_cross = false;

    foreach (var token in tokens) {
        print("  %s\n", token.to_string());

        if (token.token_type == MermaidTokenType.ARROW_SOLID) {
            found_solid = true;
        }
        if (token.token_type == MermaidTokenType.ARROW_DOTTED) {
            found_dotted = true;
        }
        if (token.token_type == MermaidTokenType.ARROW_THICK) {
            found_thick = true;
        }
        if (token.token_type == MermaidTokenType.ARROW_OPEN_SOLID) {
            found_open = true;
        }
        if (token.token_type == MermaidTokenType.ARROW_CROSS_SOLID) {
            found_cross = true;
        }
    }

    assert(found_solid);
    assert(found_dotted);
    assert(found_thick);
    assert(found_open);
    assert(found_cross);

    print("✓ Arrow types test passed\n\n");
}

void test_node_shapes() {
    string source = """A[Rectangle]
B(Rounded)
C([Stadium])
D[[Subroutine]]
E{Diamond}
F{{Hexagon}}
""";

    var lexer = new MermaidLexer(source);
    var tokens = lexer.scan_all();

    print("Node shapes test:\n");
    print("Found %d tokens\n", tokens.size);

    bool found_bracket = false;
    bool found_paren = false;
    bool found_stadium_start = false;
    bool found_double_bracket = false;
    bool found_brace = false;
    bool found_double_brace = false;

    foreach (var token in tokens) {
        print("  %s\n", token.to_string());

        if (token.token_type == MermaidTokenType.LBRACKET) {
            found_bracket = true;
        }
        if (token.token_type == MermaidTokenType.LPAREN) {
            found_paren = true;
        }
        if (token.token_type == MermaidTokenType.LBRACKET_LPAREN) {
            found_stadium_start = true;
        }
        if (token.token_type == MermaidTokenType.DOUBLE_LBRACKET) {
            found_double_bracket = true;
        }
        if (token.token_type == MermaidTokenType.LBRACE) {
            found_brace = true;
        }
        if (token.token_type == MermaidTokenType.LBRACE_LBRACE) {
            found_double_brace = true;
        }
    }

    assert(found_bracket);
    assert(found_paren);
    assert(found_stadium_start);
    assert(found_double_bracket);
    assert(found_brace);
    assert(found_double_brace);

    print("✓ Node shapes test passed\n\n");
}

void test_comments() {
    string source = """flowchart TD
    %% This is a comment
    A --> B
    %% Another comment
""";

    var lexer = new MermaidLexer(source);
    var tokens = lexer.scan_all();

    print("Comments test:\n");
    int comment_count = 0;

    foreach (var token in tokens) {
        if (token.token_type == MermaidTokenType.COMMENT) {
            comment_count++;
            print("  Found comment: %s\n", token.lexeme);
        }
    }

    assert(comment_count == 2);

    print("✓ Comments test passed\n\n");
}

int main(string[] args) {
    print("\n=== Mermaid Lexer Tests ===\n\n");

    test_flowchart_tokens();
    test_sequence_diagram_tokens();
    test_arrow_types();
    test_node_shapes();
    test_comments();

    print("=== All tests passed! ===\n\n");

    return 0;
}
