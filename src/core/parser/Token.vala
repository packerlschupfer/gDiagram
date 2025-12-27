namespace GPlantUML {
    public enum TokenType {
        // Structure
        STARTUML,
        ENDUML,

        // Participants
        PARTICIPANT,
        ACTOR,
        BOUNDARY,
        CONTROL,
        ENTITY,
        DATABASE,
        COLLECTIONS,
        QUEUE,

        // Keywords
        AS,
        NOTE,
        END,
        LEFT,
        RIGHT,
        TOP,
        BOTTOM,
        OVER,
        OF,
        ACTIVATE,
        DEACTIVATE,
        DESTROY,
        RETURN,

        // Class diagram keywords
        CLASS,
        INTERFACE,
        ABSTRACT,
        ENUM,
        EXTENDS,
        IMPLEMENTS,

        // Object diagram keywords
        OBJECT,
        EQUALS,              // =

        // Activity diagram keywords
        START,
        STOP,
        KILL,
        DETACH,
        IF,
        THEN,
        ELSE,
        ELSEIF,
        ENDIF,
        FORK,
        FORK_AGAIN,
        END_FORK,
        MERGE,
        WHILE,
        ENDWHILE,
        REPEAT,
        REPEAT_WHILE,
        PARTITION,
        SWITCH,
        CASE,
        ENDSWITCH,
        GROUP,
        SPLIT,
        SPLIT_AGAIN,
        END_SPLIT,
        BACKWARD,
        BREAK,
        FLOATING,
        TITLE,
        HEADER,
        FOOTER,
        CAPTION,
        SKINPARAM,
        SCALE,
        HIDE,
        SHOW,
        LEGEND,
        CENTER,

        // Arrows
        ARROW_RIGHT,           // ->
        ARROW_LEFT,            // <-
        ARROW_RIGHT_DOTTED,    // -->
        ARROW_LEFT_DOTTED,     // <--
        ARROW_RIGHT_OPEN,      // ->>
        ARROW_LEFT_OPEN,       // <<-
        ARROW_BIDIRECTIONAL,   // <->

        // Symbols
        COLON,
        SEMICOLON,             // ;
        NEWLINE,
        PLUS_PLUS,             // ++
        MINUS_MINUS,           // --
        LBRACE,                // {
        RBRACE,                // }
        LPAREN,                // (
        RPAREN,                // )
        LBRACKET,              // [
        RBRACKET,              // ]
        PLUS,                  // +
        MINUS,                 // -
        HASH,                  // #
        TILDE,                 // ~
        PIPE,                  // |
        SEPARATOR,             // ==== (horizontal line)
        VSPACE,                // ||| (vertical space)

        // Class relationship arrows
        INHERITANCE,           // --|> or <|--
        IMPLEMENTATION,        // ..|> or <|..
        AGGREGATION,           // o-- or --o
        COMPOSITION,           // *-- or --*
        DEPENDENCY,            // ..>

        // Use Case diagram keywords
        USECASE,               // usecase keyword
        PACKAGE,               // package keyword
        RECTANGLE,             // rectangle keyword
        LEFT_TO_RIGHT,         // left to right direction
        TOP_TO_BOTTOM,         // top to bottom direction

        // State diagram keywords
        STATE,                 // state keyword
        INITIAL_FINAL,         // [*]
        HISTORY,               // [H]
        DEEP_HISTORY,          // [H*]
        STEREOTYPE,            // <<choice>>, <<fork>>, <<join>>, <<end>>, etc.

        // Component diagram keywords
        COMPONENT,             // component keyword
        CLOUD,                 // cloud keyword
        FOLDER,                // folder keyword
        FRAME,                 // frame keyword
        NODE_KW,               // node keyword
        ARTIFACT,              // artifact keyword
        STORAGE,               // storage keyword
        PORTIN,                // portin keyword
        PORTOUT,               // portout keyword
        PORT,                  // port keyword
        CARD,                  // card keyword
        AGENT,                 // agent keyword
        USECASE_ARROW,         // <<include>> or <<extend>>

        // Sequence diagram grouping frames
        ALT,                   // alt (alternative)
        OPT,                   // opt (optional)
        LOOP,                  // loop
        PAR,                   // par (parallel)
        CRITICAL,              // critical section
        REF,                   // ref (reference)

        // MindMap / WBS diagram tokens
        STARTMINDMAP,          // @startmindmap
        ENDMINDMAP,            // @endmindmap
        STARTWBS,              // @startwbs
        ENDWBS,                // @endwbs
        MULT,                  // * (for mindmap levels)

        // Content
        IDENTIFIER,
        STRING,

        // Special
        COMMENT,
        EOF,
        ERROR
    }

    public class Token : Object {
        public TokenType token_type { get; set; }
        public string lexeme { get; set; }
        public int line { get; set; }
        public int column { get; set; }

        public Token(TokenType type, string lexeme, int line, int column) {
            this.token_type = type;
            this.lexeme = lexeme;
            this.line = line;
            this.column = column;
        }

        public string to_string() {
            return "%s '%s' at %d:%d".printf(
                token_type.to_string(),
                lexeme,
                line,
                column
            );
        }
    }
}
