namespace GDiagram {
    public enum MermaidTokenType {
        // Diagram type declarations
        FLOWCHART,              // flowchart
        SEQUENCE_DIAGRAM,       // sequenceDiagram
        STATE_DIAGRAM,          // stateDiagram-v2
        CLASS_DIAGRAM,          // classDiagram
        ER_DIAGRAM,             // erDiagram
        GANTT,                  // gantt
        PIE,                    // pie
        GIT_GRAPH,              // gitGraph
        USER_JOURNEY,           // journey

        // Flowchart direction keywords
        TD,                     // top-down (alias: TB)
        TB,                     // top-bottom (alias: TD)
        BT,                     // bottom-top
        LR,                     // left-right
        RL,                     // right-left

        // Flowchart keywords
        SUBGRAPH,               // subgraph
        END,                    // end
        STYLE,                  // style
        CLASS_DEF,              // classDef
        CLASS_KW,               // class
        CLICK,                  // click

        // Sequence diagram keywords
        PARTICIPANT,            // participant
        ACTOR,                  // actor
        ACTIVATE,               // activate
        DEACTIVATE,             // deactivate
        NOTE,                   // Note
        OVER,                   // over
        LEFT_OF,                // left of
        RIGHT_OF,               // right of
        AUTONUMBER,             // autonumber
        LOOP,                   // loop
        ALT,                    // alt
        ELSE,                   // else
        OPT,                    // opt
        PAR,                    // par
        AND,                    // and
        CRITICAL,               // critical
        BREAK,                  // break
        RECT,                   // rect

        // State diagram keywords
        STATE,                  // state
        INITIAL,                // [*]
        CHOICE,                 // <<choice>>
        FORK_KW,                // <<fork>>
        JOIN,                   // <<join>>

        // Common keywords
        AS,                     // as
        TITLE,                  // title
        DIRECTION,              // direction

        // Arrows and connectors
        ARROW_SOLID,            // -->
        ARROW_DOTTED,           // -.->
        ARROW_THICK,            // ==>
        ARROW_INVISIBLE,        // ~~~
        LINE_SOLID,             // ---
        LINE_DOTTED,            // -.-
        LINE_THICK,             // ===
        ARROW_OPEN_SOLID,       // --o
        ARROW_OPEN_DOTTED,      // -.o
        ARROW_CROSS_SOLID,      // --x
        ARROW_CROSS_DOTTED,     // -.x
        ARROW_CIRCLE_SOLID,     // --@
        ARROW_BIDIRECTIONAL,    // <-->

        // Sequence diagram specific arrows
        SEQ_SOLID_ARROW,        // ->
        SEQ_DOTTED_ARROW,       // -->
        SEQ_SOLID_OPEN,         // -)
        SEQ_DOTTED_OPEN,        // --)
        SEQ_SOLID_CROSS,        // -x
        SEQ_DOTTED_CROSS,       // --x
        SEQ_SOLID_LINE,         // -
        SEQ_DOTTED_LINE,        // --
        SEQ_ACTIVATION,         // +
        SEQ_DEACTIVATION,       // -

        // Symbols and delimiters
        LBRACKET,               // [
        RBRACKET,               // ]
        LPAREN,                 // (
        RPAREN,                 // )
        LBRACE,                 // {
        RBRACE,                 // }
        DOUBLE_LPAREN,          // ((
        DOUBLE_RPAREN,          // ))
        TRIPLE_LPAREN,          // (((
        TRIPLE_RPAREN,          // )))
        LBRACKET_LPAREN,        // ([
        RPAREN_RBRACKET,        // ])
        DOUBLE_LBRACKET,        // [[
        DOUBLE_RBRACKET,        // ]]
        LBRACE_LBRACE,          // {{
        RBRACE_RBRACE,          // }}
        LBRACKET_SLASH,         // [/
        SLASH_RBRACKET,         // /]
        LBRACKET_BACKSLASH,     // [\
        BACKSLASH_RBRACKET,     // \]
        ASYMMETRIC_START,       // >
        ASYMMETRIC_END,         // ]
        PIPE,                   // |
        COLON,                  // :
        SEMICOLON,              // ;
        COMMA,                  // ,
        QUOTE,                  // "
        BACKTICK,               // `
        AMPERSAND,              // &
        HASH,                   // #
        PERCENT,                // %
        QUESTION,               // ?
        EXCLAMATION,            // !
        AT,                     // @
        DOLLAR,                 // $
        EQUALS,                 // =
        PLUS,                   // +
        ASTERISK,               // *

        // Text and literals
        IDENTIFIER,             // alphanumeric identifier
        STRING,                 // "text" or 'text'
        NUMBER,                 // numeric literal
        TEXT,                   // unquoted text

        // Whitespace and structure
        NEWLINE,
        INDENT,                 // indentation (for subgraphs)
        DEDENT,                 // dedentation
        COMMENT,                // %% comment
        EOF
    }

    public class MermaidToken : Object {
        public MermaidTokenType token_type { get; set; }
        public string lexeme { get; set; }
        public int line { get; set; }
        public int column { get; set; }

        public MermaidToken(MermaidTokenType type, string lexeme, int line, int column) {
            this.token_type = type;
            this.lexeme = lexeme;
            this.line = line;
            this.column = column;
        }

        public string to_string() {
            return "%s('%s') at %d:%d".printf(
                token_type.to_string(),
                lexeme,
                line,
                column
            );
        }
    }
}
