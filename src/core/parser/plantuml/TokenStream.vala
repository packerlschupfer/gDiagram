namespace GDiagram {
    /**
     * TokenStream - Encapsulates token array and position for parsing
     *
     * Provides a single source of truth for parser position, preventing
     * synchronization bugs when multiple parsers share token state.
     */
    public class TokenStream : Object {
    private Gee.ArrayList<Token> tokens;
    private int _current;

    /**
     * Current position in token stream
     */
    public int current {
        get { return _current; }
        set { _current = value; }
    }

    /**
     * Create a new token stream
     * @param tokens The token array to wrap
     */
    public TokenStream(Gee.ArrayList<Token> tokens) {
        this.tokens = tokens;
        this._current = 0;
    }

    /**
     * Get current token without advancing
     * @return Current token, or EOF if at end
     */
    public Token peek() {
        if (_current >= tokens.size) {
            return tokens[tokens.size - 1]; // Return EOF token
        }
        return tokens[_current];
    }

    /**
     * Get previous token
     * @return Previous token
     */
    public Token previous() {
        if (_current > 0) {
            return tokens[_current - 1];
        }
        return tokens[0];
    }

    /**
     * Advance to next token
     * @return The token that was current before advancing
     */
    public Token advance() {
        if (!is_at_end()) {
            _current++;
        }
        return previous();
    }

    /**
     * Check if current token matches type without advancing
     * @param type Token type to check
     * @return true if current token matches type
     */
    public bool check(TokenType type) {
        if (is_at_end()) {
            return false;
        }
        return peek().token_type == type;
    }

    /**
     * Check if at end of stream
     * @return true if at EOF
     */
    public bool is_at_end() {
        if (_current >= tokens.size) {
            return true;
        }
        return tokens[_current].token_type == TokenType.EOF;
    }

    /**
     * Match current token against types and advance if matched
     * @param types Variable number of types to match
     * @return true if matched and advanced
     */
    public bool match(params TokenType[] types) {
        foreach (var type in types) {
            if (check(type)) {
                advance();
                return true;
            }
        }
        return false;
    }

    /**
     * Get total number of tokens
     * @return Token count
     */
    public int size() {
        return tokens.size;
    }

    /**
     * Get current position in stream
     * @return Current position
     */
    public int position() {
        return _current;
    }

    /**
     * Peek at token at specific position
     * @param pos Position to peek at
     * @return Token at position, or EOF if out of bounds
     */
    public Token peek_at(int pos) {
        if (pos < 0 || pos >= tokens.size) {
            return tokens[tokens.size - 1]; // Return EOF token
        }
        return tokens[pos];
    }

    /**
     * Check if token at specific lookahead offset matches type
     * @param offset Offset from current position
     * @param type Token type to check
     * @return true if token at current+offset matches type
     */
    public bool check_lookahead(int offset, TokenType type) {
        int pos = _current + offset;
        if (pos < 0 || pos >= tokens.size) {
            return false;
        }
        return tokens[pos].token_type == type;
    }

    /**
     * Check if next token (current+1) matches type
     * @param type Token type to check
     * @return true if next token matches type
     */
    public bool check_next(TokenType type) {
        return check_lookahead(1, type);
    }

    /**
     * Check if next token matches a specific lexeme
     * @param lexeme Lexeme to check
     * @return true if next token has this lexeme
     */
    public bool check_next_lexeme(string lexeme) {
        int pos = _current + 1;
        if (pos < 0 || pos >= tokens.size) {
            return false;
        }
        return tokens[pos].lexeme == lexeme;
    }
    }
}
