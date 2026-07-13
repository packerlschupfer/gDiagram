/* MermaidRailroadParser.vala — the four Mermaid railroad grammar front ends.
 *
 * Mermaid 12.2.0 drives railroad diagrams from four Langium grammars that all
 * transform into one node vocabulary.  The grammars below are transcribed from
 * mermaid's own generated grammar (the serialised Langium grammar shipped in
 * @mermaid-js/parser), not guessed, and every edge case noted in a comment was
 * confirmed against `mmdc` 12.2.0 as an accept/reject oracle.
 *
 *   railroad-beta        Railroad:      "railroad-beta" header* rules*
 *                        RailroadRule:  ID "=" Expression ";"
 *                        Expression:    sequence( e, ... ) | choice( e, ... )
 *                                     | optional( e ) | oneOrMore( e )
 *                                     | zeroOrMore( e ) | terminal( STRING )
 *                                     | nonterminal( STRING ) | special( STRING )
 *
 *   railroad-ebnf-beta   EbnfRule:      ID ("=" | "::=") Choice ";"
 *                        Choice:        Sequence ("|" Sequence)*
 *                        Sequence:      Term (","? Term)*
 *                        Term:          Primary Postfix*
 *                        Primary:       STRING | SPECIAL | ID | "(" Choice ")"
 *                                     | "[" Choice "]" | "{" Choice "}"
 *                        Postfix:       "?" | "*" | "+" | "-" Primary
 *
 *   railroad-abnf-beta   AbnfRule:      RULENAME "=" Alternation ";"
 *                        Alternation:   Concatenation ("/" Concatenation)*
 *                        Concatenation: Element+
 *                        Element:       (REPEAT | EXACT_REPEAT)? Primary
 *                        Primary:       STRING | NUMVAL | RULENAME
 *                                     | "(" Alternation ")" | "[" Alternation "]"
 *
 *   railroad-peg-beta    PegRule:       ID "<-" OrderedChoice ";"
 *                        OrderedChoice: Sequence ("/" Sequence)*
 *                        Sequence:      Prefix+
 *                        Prefix:        ("&" | "!")? Suffix
 *                        Suffix:        Primary ("?" | "*" | "+")?
 *                        Primary:       STRING | ID | "(" OrderedChoice ")" | "."
 *
 * All four require the trailing ";" on every rule (verified: dropping it makes
 * mmdc report `Expecting token of type ';'`).
 */
namespace GDiagram {

public class MermaidRailroadParser : Object {

    private string src;
    private int pos;
    private int line;
    private int col;
    private MermaidRailroad diagram;
    private MermaidRailroadGrammar flavour;
    /** Set once a rule failed: the rest of that rule is skipped, parsing goes on. */
    private bool failed;

    // Guards against a pathological input driving the rule loop forever.  Every
    // body loop also carries an explicit progress guard; this is the backstop.
    private const int MAX_RULES = 20000;
    private const int MAX_DEPTH = 200;

    public MermaidRailroadParser() {
        this.src = "";
    }

    /**
     * Which flavour a source belongs to, or null when it is not a railroad.
     *
     * The keyword is on the first line that is not blank, YAML front matter, a
     * `%%{...}%%` directive or a `%%` comment — the same lines TypeDetector
     * skips, and the reason this cannot just read `source.split("\n")[0]`.
     */
    public static MermaidRailroadGrammar? detect_grammar(string source) {
        bool front_matter = false;
        bool directive = false;
        bool seen = false;
        foreach (string raw in source.split("\n")) {
            string l = raw.strip();
            if (front_matter) {
                if (l == "---") front_matter = false;
                continue;
            }
            if (directive) {
                if (l.contains("}%%")) directive = false;
                continue;
            }
            if (l.length == 0) continue;
            if (!seen && l == "---") { seen = true; front_matter = true; continue; }
            seen = true;
            if (l.has_prefix("%%{") && !l.contains("}%%")) { directive = true; continue; }
            if (l.has_prefix("%%")) continue;

            string low = l.down();
            if (low.has_prefix("railroad-ebnf-beta")) return MermaidRailroadGrammar.EBNF;
            if (low.has_prefix("railroad-abnf-beta")) return MermaidRailroadGrammar.ABNF;
            if (low.has_prefix("railroad-peg-beta"))  return MermaidRailroadGrammar.PEG;
            if (low.has_prefix("railroad-beta"))      return MermaidRailroadGrammar.NATIVE;
            return null;   // the first real line names the diagram, or nothing does
        }
        return null;
    }

    public MermaidRailroad parse(string source) {
        this.src = source;
        this.pos = 0;
        this.line = 1;
        this.col = 1;
        this.failed = false;
        this.diagram = new MermaidRailroad();

        var detected = detect_grammar(source);
        this.flavour = detected ?? MermaidRailroadGrammar.NATIVE;
        diagram.grammar = flavour;

        skip_front_matter();
        skip_hidden();
        if (!eat_keyword(flavour.keyword())) {
            error("Expected '%s'".printf(flavour.keyword()));
            return diagram;
        }
        parse_headers();

        int guard = 0;
        while (!at_end() && guard++ < MAX_RULES) {
            skip_hidden();
            if (at_end()) break;
            int before = pos;
            failed = false;
            parse_rule();
            if (pos == before) {
                // Nothing consumed: report once and skip the offending line so a
                // malformed file cannot spin the loop at 100% CPU.
                error("Unexpected '%s'".printf(glimpse()));
                skip_to_next_line();
                if (pos == before) break;   // skip_to_next_line() hit EOF
            }
        }
        return diagram;
    }

    // ==================== rules ====================

    private void parse_rule() {
        int rule_line = line;
        string? name = read_rule_name();
        if (name == null) return;

        skip_hidden();
        bool ok;
        switch (flavour) {
            case MermaidRailroadGrammar.PEG:
                ok = eat("<-");
                if (!ok) error("Expected '<-' after rule name '%s'".printf(name));
                break;
            case MermaidRailroadGrammar.EBNF:
                ok = eat("::=") || eat("=");
                if (!ok) error("Expected '=' or '::=' after rule name '%s'".printf(name));
                break;
            default:
                ok = eat("=");
                if (!ok) error("Expected '=' after rule name '%s'".printf(name));
                break;
        }
        if (!ok) { skip_to_next_line(); return; }

        MermaidRailroadNode? body = parse_definition(0);
        if (body == null || failed) {
            skip_to_rule_end();
            return;
        }

        skip_hidden();
        if (!eat(";")) {
            // Every flavour's grammar ends a rule with ";".
            error("Expected ';' at the end of rule '%s'".printf(name));
            skip_to_rule_end();
            return;
        }
        diagram.add_rule(new MermaidRailroadRule(name, body, rule_line));
    }

    private MermaidRailroadNode? parse_definition(int depth) {
        if (depth > MAX_DEPTH) {
            error("Expression nested deeper than %d levels".printf(MAX_DEPTH));
            return null;
        }
        switch (flavour) {
            case MermaidRailroadGrammar.EBNF: return ebnf_choice(depth);
            case MermaidRailroadGrammar.ABNF: return abnf_alternation(depth);
            case MermaidRailroadGrammar.PEG:  return peg_choice(depth);
            default:                          return native_expression(depth);
        }
    }

    private string? read_rule_name() {
        skip_hidden();
        string? name = (flavour == MermaidRailroadGrammar.ABNF) ? read_abnf_rulename() : read_id();
        if (name == null) return null;
        return name;
    }

    // ==================== railroad-beta (native) ====================

    // Expression: one of the eight constructor calls.  Mermaid's grammar has no
    // bare terminals here — "hello" on its own is a parse error.
    private MermaidRailroadNode? native_expression(int depth) {
        skip_hidden();
        string? head = read_id();
        if (head == null) {
            error("Expected a railroad expression (sequence, choice, optional, oneOrMore, " +
                  "zeroOrMore, terminal, nonterminal or special)");
            return null;
        }
        skip_hidden();
        if (!eat("(")) {
            error("Expected '(' after '%s'".printf(head));
            return null;
        }

        MermaidRailroadNode? result = null;
        switch (head) {
            case "sequence":
            case "choice": {
                var items = new Gee.ArrayList<MermaidRailroadNode>();
                int guard = 0;
                while (guard++ < MAX_RULES) {
                    int before = pos;
                    var e = native_expression(depth + 1);
                    if (e == null) return null;
                    items.add(e);
                    skip_hidden();
                    if (!eat(",")) break;
                    if (pos == before) break;   // progress guard
                }
                if (items.size == 0) {
                    error("'%s' needs at least one element".printf(head));
                    return null;
                }
                result = MermaidRailroadNode.collapse(
                    head == "sequence" ? MermaidRailroadNodeType.SEQUENCE
                                       : MermaidRailroadNodeType.CHOICE, items);
                break;
            }
            case "optional":
            case "oneOrMore":
            case "zeroOrMore": {
                var inner = native_expression(depth + 1);
                if (inner == null) return null;
                if (head == "optional") {
                    result = new MermaidRailroadNode.optional(inner);
                } else if (head == "oneOrMore") {
                    result = new MermaidRailroadNode.repetition(inner, 1, -1);
                } else {
                    result = new MermaidRailroadNode.repetition(inner, 0, -1);
                }
                break;
            }
            case "terminal":
            case "nonterminal":
            case "special": {
                string? s = read_quoted();
                if (s == null) {
                    error("'%s' needs a quoted string".printf(head));
                    return null;
                }
                if (head == "terminal") result = new MermaidRailroadNode.terminal(s);
                else if (head == "nonterminal") result = new MermaidRailroadNode.nonterminal(s);
                else result = new MermaidRailroadNode.special(s);
                break;
            }
            default:
                error("Unsupported railroad expression '%s'".printf(head));
                return null;
        }

        skip_hidden();
        if (!eat(")")) {
            error("Expected ')' to close '%s'".printf(head));
            return null;
        }
        return result;
    }

    // ==================== railroad-ebnf-beta ====================

    private MermaidRailroadNode? ebnf_choice(int depth) {
        var alts = new Gee.ArrayList<MermaidRailroadNode>();
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            var s = ebnf_sequence(depth + 1);
            if (s == null) return null;
            alts.add(s);
            skip_hidden();
            if (!eat("|")) break;
            if (pos == before) break;   // progress guard
        }
        if (alts.size == 0) return null;
        return MermaidRailroadNode.collapse(MermaidRailroadNodeType.CHOICE, alts);
    }

    // Sequence: Term (","? Term)* — the comma is optional, so juxtaposition
    // concatenates ("letter ( letter | digit )*" is one sequence).
    private MermaidRailroadNode? ebnf_sequence(int depth) {
        var items = new Gee.ArrayList<MermaidRailroadNode>();
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            skip_hidden();
            if (eat(",")) skip_hidden();
            if (!ebnf_starts_primary()) break;
            var t = ebnf_term(depth + 1);
            if (t == null) return null;
            items.add(t);
            if (pos == before) break;   // progress guard
        }
        if (items.size == 0) {
            error("Expected an EBNF term");
            return null;
        }
        return MermaidRailroadNode.collapse(MermaidRailroadNodeType.SEQUENCE, items);
    }

    private bool ebnf_starts_primary() {
        skip_hidden();
        if (at_end()) return false;
        char c = src[pos];
        if (c == '"' || c == '\'' || c == '(' || c == '[' || c == '{') {
            // "(*" opens an ISO comment, handled by skip_hidden(); a bare "(" is a group
            return true;
        }
        if (c == '?') return ebnf_special_len() > 0;
        return is_id_start(c);
    }

    private MermaidRailroadNode? ebnf_term(int depth) {
        var node = ebnf_primary(depth);
        if (node == null) return null;
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            skip_hidden();
            if (eat("?")) {
                node = new MermaidRailroadNode.optional(node);
            } else if (eat("*")) {
                node = new MermaidRailroadNode.repetition(node, 0, -1);
            } else if (eat("+")) {
                node = new MermaidRailroadNode.repetition(node, 1, -1);
            } else if (eat("-")) {
                // EbnfExceptionPostfix: mermaid flattens "a - b" to the sequence
                // [a, terminal("-"), b].
                var except = ebnf_primary(depth + 1);
                if (except == null) return null;
                var seq = new MermaidRailroadNode(MermaidRailroadNodeType.SEQUENCE);
                seq.add_child(node);
                seq.add_child(new MermaidRailroadNode.terminal("-"));
                seq.add_child(except);
                node = seq;
            } else {
                break;
            }
            if (pos == before) break;   // progress guard
        }
        return node;
    }

    private MermaidRailroadNode? ebnf_primary(int depth) {
        skip_hidden();
        if (at_end()) { error("Unexpected end of input in EBNF rule"); return null; }
        char c = src[pos];
        if (c == '"' || c == '\'') {
            string? s = read_quoted();
            if (s == null) return null;
            return new MermaidRailroadNode.terminal(s);
        }
        if (c == '?') {
            int len = ebnf_special_len();
            if (len > 0) {
                // EBNF_SPECIAL_SEQUENCE is "?...?".  The renderer re-adds the
                // "? " / " ?" around the text, so the delimiters and the padding
                // inside them come off here: mmdc draws "? any letter ?" for
                // `? any letter ?`, not "? ? any letter ? ?".
                string inner = src.substring(pos + 1, len - 2).strip();
                advance_by(len);
                return new MermaidRailroadNode.special(inner);
            }
        }
        if (c == '(' || c == '[' || c == '{') {
            string close = c == '(' ? ")" : (c == '[' ? "]" : "}");
            advance_by(1);
            var inner = ebnf_choice(depth + 1);
            if (inner == null) return null;
            skip_hidden();
            if (!eat(close)) {
                error("Expected '%s' to close the group".printf(close));
                return null;
            }
            if (c == '[') return new MermaidRailroadNode.optional(inner);
            if (c == '{') return new MermaidRailroadNode.repetition(inner, 0, -1);
            return inner;   // EbnfGroup transforms to the inner choice itself
        }
        string? id = read_id();
        if (id == null) {
            error("Expected an EBNF primary, found '%s'".printf(glimpse()));
            return null;
        }
        return new MermaidRailroadNode.nonterminal(id);
    }

    // EBNF_SPECIAL_SEQUENCE: /\?(?=[^?;]*[^?\s;][^?;]*\?)[^?;]*\?/ — a "?...?"
    // pair on one stretch with at least one non-space inside and no ";".
    // Returns the full length including both "?", or 0 when it does not match.
    private int ebnf_special_len() {
        if (pos >= src.length || src[pos] != '?') return 0;
        bool has_visible = false;
        int i = pos + 1;
        while (i < src.length) {
            char c = src[i];
            if (c == ';') return 0;
            if (c == '?') return has_visible ? (i - pos + 1) : 0;
            if (!c.isspace()) has_visible = true;
            i++;
        }
        return 0;
    }

    // ==================== railroad-abnf-beta ====================

    private MermaidRailroadNode? abnf_alternation(int depth) {
        var alts = new Gee.ArrayList<MermaidRailroadNode>();
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            var c = abnf_concatenation(depth + 1);
            if (c == null) return null;
            alts.add(c);
            skip_hidden();
            if (!eat("/")) break;
            if (pos == before) break;   // progress guard
        }
        if (alts.size == 0) return null;
        return MermaidRailroadNode.collapse(MermaidRailroadNodeType.CHOICE, alts);
    }

    private MermaidRailroadNode? abnf_concatenation(int depth) {
        var items = new Gee.ArrayList<MermaidRailroadNode>();
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            skip_hidden();
            if (!abnf_starts_element()) break;
            var e = abnf_element(depth + 1);
            if (e == null) return null;
            items.add(e);
            if (pos == before) break;   // progress guard
        }
        if (items.size == 0) {
            error("Expected an ABNF element");
            return null;
        }
        return MermaidRailroadNode.collapse(MermaidRailroadNodeType.SEQUENCE, items);
    }

    private bool abnf_starts_element() {
        skip_hidden();
        if (at_end()) return false;
        char c = src[pos];
        return c == '"' || c == '%' || c == '(' || c == '[' || c.isdigit() || c == '*' ||
               c.isalpha();
    }

    private MermaidRailroadNode? abnf_element(int depth) {
        skip_hidden();
        // (repeat=ABNF_REPEAT | repeat=ABNF_EXACT_REPEAT)?
        // ABNF_REPEAT      /[0-9]*\*[0-9]*/
        // ABNF_EXACT_REPEAT /[0-9]+/
        string? repeat = read_abnf_repeat();
        var inner = abnf_primary(depth);
        if (inner == null) return null;
        if (repeat == null) return inner;

        int min, max;
        parse_abnf_repeat(repeat, out min, out max);
        if (min == 0 && max == 1) return new MermaidRailroadNode.optional(inner);
        return new MermaidRailroadNode.repetition(inner, min, max);
    }

    /** mermaid's parseRepeat(): "n*m" -> n..m, "*" -> 0..inf, "n" -> n..n. */
    internal static void parse_abnf_repeat(string repeat, out int min, out int max) {
        int star = repeat.index_of_char('*');
        if (star >= 0) {
            string lo = repeat.substring(0, star);
            string hi = repeat.substring(star + 1);
            min = lo.length > 0 ? int.parse(lo) : 0;
            max = hi.length > 0 ? int.parse(hi) : -1;   // -1 = Infinity
            return;
        }
        int exact = int.parse(repeat);
        min = exact;
        max = exact;
    }

    private string? read_abnf_repeat() {
        int i = pos;
        while (i < src.length && src[i].isdigit()) i++;
        if (i < src.length && src[i] == '*') {
            i++;
            while (i < src.length && src[i].isdigit()) i++;
            string r = src.substring(pos, i - pos);
            advance_by(i - pos);
            return r;
        }
        if (i > pos) {
            // digits not followed by "*" = ABNF_EXACT_REPEAT
            string r = src.substring(pos, i - pos);
            advance_by(i - pos);
            return r;
        }
        return null;
    }

    private MermaidRailroadNode? abnf_primary(int depth) {
        skip_hidden();
        if (at_end()) { error("Unexpected end of input in ABNF rule"); return null; }
        char c = src[pos];
        if (c == '"') {
            // ABNF_STRING is /"[^"]*"/ — no escapes
            int end = src.index_of_char('"', pos + 1);
            if (end < 0) { error("Unterminated ABNF string"); return null; }
            string v = src.substring(pos + 1, end - pos - 1);
            advance_by(end - pos + 1);
            return new MermaidRailroadNode.terminal(v);
        }
        if (c == '%') {
            string? v = read_abnf_numval();
            if (v == null) { error("Malformed ABNF numeric value"); return null; }
            return new MermaidRailroadNode.terminal(v);
        }
        if (c == '(' || c == '[') {
            string close = c == '(' ? ")" : "]";
            advance_by(1);
            var inner = abnf_alternation(depth + 1);
            if (inner == null) return null;
            skip_hidden();
            if (!eat(close)) {
                error("Expected '%s' to close the ABNF group".printf(close));
                return null;
            }
            return c == '[' ? new MermaidRailroadNode.optional(inner) : inner;
        }
        string? name = read_abnf_rulename();
        if (name == null) {
            error("Expected an ABNF primary, found '%s'".printf(glimpse()));
            return null;
        }
        return new MermaidRailroadNode.nonterminal(name);
    }

    // ABNF_NUMVAL: /%[xXdDbB][0-9A-Fa-f]+(?:-[0-9A-Fa-f]+|\.[0-9A-Fa-f]+)*/
    private string? read_abnf_numval() {
        int i = pos;
        if (i >= src.length || src[i] != '%') return null;
        i++;
        if (i >= src.length) return null;
        char b = src[i].tolower();
        if (b != 'x' && b != 'd' && b != 'b') return null;
        i++;
        int digits = 0;
        while (i < src.length && src[i].isxdigit()) { i++; digits++; }
        if (digits == 0) return null;
        while (i < src.length && (src[i] == '-' || src[i] == '.')) {
            int j = i + 1;
            int d2 = 0;
            while (j < src.length && src[j].isxdigit()) { j++; d2++; }
            if (d2 == 0) break;
            i = j;
        }
        string v = src.substring(pos, i - pos);
        advance_by(i - pos);
        return v;
    }

    // ABNF_RULENAME: /[A-Za-z][A-Za-z0-9-]*/ — note: no underscore, unlike the
    // other three flavours' ID.
    private string? read_abnf_rulename() {
        if (at_end()) return null;
        char c = src[pos];
        if (!c.isalpha()) return null;
        int i = pos + 1;
        while (i < src.length && (src[i].isalnum() || src[i] == '-')) i++;
        string n = src.substring(pos, i - pos);
        advance_by(i - pos);
        return n;
    }

    // ==================== railroad-peg-beta ====================

    private MermaidRailroadNode? peg_choice(int depth) {
        var alts = new Gee.ArrayList<MermaidRailroadNode>();
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            var s = peg_sequence(depth + 1);
            if (s == null) return null;
            alts.add(s);
            skip_hidden();
            if (!eat("/")) break;
            if (pos == before) break;   // progress guard
        }
        if (alts.size == 0) return null;
        return MermaidRailroadNode.collapse(MermaidRailroadNodeType.CHOICE, alts);
    }

    private MermaidRailroadNode? peg_sequence(int depth) {
        var items = new Gee.ArrayList<MermaidRailroadNode>();
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            skip_hidden();
            if (!peg_starts_prefix()) break;
            var p = peg_prefix(depth + 1);
            if (p == null) return null;
            items.add(p);
            if (pos == before) break;   // progress guard
        }
        if (items.size == 0) {
            error("Expected a PEG expression");
            return null;
        }
        return MermaidRailroadNode.collapse(MermaidRailroadNodeType.SEQUENCE, items);
    }

    private bool peg_starts_prefix() {
        skip_hidden();
        if (at_end()) return false;
        char c = src[pos];
        return c == '&' || c == '!' || c == '"' || c == '\'' || c == '(' || c == '.' ||
               is_id_start(c);
    }

    private MermaidRailroadNode? peg_prefix(int depth) {
        skip_hidden();
        string? op = null;
        if (eat("&")) op = "&";
        else if (eat("!")) op = "!";

        var inner = peg_suffix(depth);
        if (inner == null) return null;
        if (op == null) return inner;
        // Mermaid renders a lookahead as a special node labelled "&x" / "!x".
        return new MermaidRailroadNode.special(op + inner.to_label());
    }

    private MermaidRailroadNode? peg_suffix(int depth) {
        var inner = peg_primary(depth);
        if (inner == null) return null;
        skip_hidden();
        if (eat("?")) return new MermaidRailroadNode.optional(inner);
        if (eat("*")) return new MermaidRailroadNode.repetition(inner, 0, -1);
        if (eat("+")) return new MermaidRailroadNode.repetition(inner, 1, -1);
        return inner;
    }

    private MermaidRailroadNode? peg_primary(int depth) {
        skip_hidden();
        if (at_end()) { error("Unexpected end of input in PEG rule"); return null; }
        char c = src[pos];
        if (c == '"' || c == '\'') {
            string? s = read_quoted();
            if (s == null) return null;
            return new MermaidRailroadNode.terminal(s);
        }
        if (c == '(') {
            advance_by(1);
            var inner = peg_choice(depth + 1);
            if (inner == null) return null;
            skip_hidden();
            if (!eat(")")) { error("Expected ')' to close the PEG group"); return null; }
            return inner;
        }
        if (c == '.') {
            advance_by(1);
            return new MermaidRailroadNode.special(".");
        }
        string? id = read_id();
        if (id == null) {
            // Character classes ("[0-9]") are NOT in mermaid's PEG grammar; mmdc
            // reports a lexer error on "[", so refusing them here matches it.
            error("Expected a PEG primary, found '%s'".printf(glimpse()));
            return null;
        }
        return new MermaidRailroadNode.nonterminal(id);
    }

    // ==================== headers ====================

    // (title=TITLE | accTitle=ACC_TITLE | accDescr=ACC_DESCR)*
    private void parse_headers() {
        int guard = 0;
        while (guard++ < MAX_RULES) {
            int before = pos;
            skip_hidden();
            if (try_header("accTitle")) { continue; }
            if (try_header("accDescr")) { continue; }
            if (try_header("title")) { continue; }
            if (pos == before) break;   // progress guard
        }
    }

    private bool try_header(string word) {
        if (!looking_at_word(word)) return false;
        int save_pos = pos, save_line = line, save_col = col;
        advance_by(word.length);
        // accDescr may use a brace block: /accDescr\s*\{([^}]*)\}/
        if (word == "accDescr") {
            int probe = pos;
            while (probe < src.length && src[probe].isspace()) probe++;
            if (probe < src.length && src[probe] == '{') {
                int end = src.index_of_char('}', probe + 1);
                if (end < 0) { pos = save_pos; line = save_line; col = save_col; return false; }
                diagram.acc_descr = src.substring(probe + 1, end - probe - 1).strip();
                advance_by(end + 1 - pos);
                return true;
            }
        }
        // Otherwise: optional ":" then the rest of the line, with a trailing
        // "%%" comment cut off (mermaid's (?=%%) lookahead).
        while (pos < src.length && (src[pos] == ' ' || src[pos] == '\t')) advance_by(1);
        if (pos < src.length && src[pos] == ':') advance_by(1);
        int eol = pos;
        while (eol < src.length && src[eol] != '\n' && src[eol] != '\r') eol++;
        string text = src.substring(pos, eol - pos);
        int cut = text.index_of("%%");
        if (cut >= 0) text = text.substring(0, cut);
        advance_by(eol - pos);
        text = text.strip();
        if (word == "title") diagram.title = text;
        else if (word == "accTitle") diagram.acc_title = text;
        else diagram.acc_descr = text;
        return true;
    }

    private bool looking_at_word(string word) {
        if (pos + word.length > src.length) return false;
        if (src.substring(pos, word.length) != word) return false;
        // "title" must be followed by space/tab/colon/EOL, never by more word
        // characters ("titled = ..." is a rule, not a title).
        int after = pos + word.length;
        if (after >= src.length) return true;
        char c = src[after];
        return !(c.isalnum() || c == '_' || c == '-');
    }

    // ==================== scanner ====================

    private bool at_end() { return pos >= src.length; }

    private static bool is_id_start(char c) { return c.isalpha() || c == '_'; }

    private void advance_by(int n) {
        for (int i = 0; i < n && pos < src.length; i++) {
            if (src[pos] == '\n') { line++; col = 1; } else { col++; }
            pos++;
        }
    }

    private bool eat(string s) {
        if (pos + s.length > src.length) return false;
        if (src.substring(pos, s.length) != s) return false;
        advance_by(s.length);
        return true;
    }

    private bool eat_keyword(string s) {
        if (pos + s.length > src.length) return false;
        if (src.substring(pos, s.length).down() != s) return false;
        advance_by(s.length);
        return true;
    }

    // ID: /[A-Za-z_][\w-]*/ for the native, EBNF and PEG flavours.  A trailing
    // "-" is only part of the name when a word character follows, so the EBNF
    // exception postfix "a - b" and "a-b" both read correctly.
    private string? read_id() {
        if (at_end()) return null;
        if (!is_id_start(src[pos])) return null;
        int i = pos + 1;
        while (i < src.length) {
            char c = src[i];
            if (c.isalnum() || c == '_') { i++; continue; }
            if (c == '-' && i + 1 < src.length &&
                (src[i + 1].isalnum() || src[i + 1] == '_')) { i += 2; continue; }
            break;
        }
        string id = src.substring(pos, i - pos);
        advance_by(i - pos);
        return id;
    }

    // STRING: /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/ — the quotes are stripped and
    // backslash escapes unescaped, as mermaid's value converter does.
    private string? read_quoted() {
        skip_hidden();
        if (at_end()) return null;
        char q = src[pos];
        if (q != '"' && q != '\'') return null;
        var sb = new StringBuilder();
        int i = pos + 1;
        while (i < src.length) {
            char c = src[i];
            if (c == '\\' && i + 1 < src.length) {
                sb.append_c(src[i + 1]);
                i += 2;
                continue;
            }
            if (c == q) {
                advance_by(i + 1 - pos);
                return sb.str;
            }
            if (c == '\n') break;
            sb.append_c(c);
            i++;
        }
        error("Unterminated string");
        return null;
    }

    /**
     * Skips everything the four grammars declare `hidden`: whitespace, YAML
     * front matter, `%%{...}%%` directives, `%%` line comments, and the
     * flavour's own comment forms.
     */
    private void skip_hidden() {
        int guard = 0;
        while (!at_end() && guard++ < 1000000) {
            int before = pos;
            while (!at_end() && src[pos].isspace()) advance_by(1);
            if (at_end()) return;

            if (eat_directive()) continue;
            if (pos + 1 < src.length && src[pos] == '%' && src[pos + 1] == '%') {
                skip_to_next_line();
                continue;
            }
            if (flavour != MermaidRailroadGrammar.ABNF &&
                pos + 1 < src.length && src[pos] == '/' && src[pos + 1] == '*') {
                // Native, EBNF and PEG all hide /* ... */
                int end = src.index_of("*/", pos + 2);
                advance_by((end < 0 ? src.length : end + 2) - pos);
                continue;
            }
            if (flavour == MermaidRailroadGrammar.EBNF &&
                pos + 1 < src.length && src[pos] == '(' && src[pos + 1] == '*') {
                int end = src.index_of("*)", pos + 2);
                advance_by((end < 0 ? src.length : end + 2) - pos);
                continue;
            }
            if (flavour == MermaidRailroadGrammar.PEG && src[pos] == '#') {
                skip_to_next_line();
                continue;
            }
            if (flavour == MermaidRailroadGrammar.ABNF && src[pos] == ';') {
                // ABNF_COMMENT is /;[^\n\r]*/ and competes with the ";" that ends a
                // rule.  Langium's lexer takes the longest match and falls back to
                // the keyword on a tie, so ";" directly before the end of the line
                // terminates the rule while ";" with anything after it is a comment.
                // Verified with mmdc: "a = ALPHA; trailing text" swallows the
                // terminator and fails on the next rule's "=".
                int eol = pos + 1;
                while (eol < src.length && src[eol] != '\n' && src[eol] != '\r') eol++;
                if (eol > pos + 1) { advance_by(eol - pos); continue; }
                return;   // bare ";" at end of line: the rule terminator
            }
            if (pos == before) return;   // progress guard: nothing hidden here
        }
    }

    private bool eat_directive() {
        if (pos + 2 >= src.length) return false;
        if (!(src[pos] == '%' && src[pos + 1] == '%' && src[pos + 2] == '{')) return false;
        int end = src.index_of("}%%", pos + 3);
        advance_by((end < 0 ? src.length : end + 3) - pos);
        return true;
    }

    private void skip_front_matter() {
        int i = 0;
        while (i < src.length && (src[i] == ' ' || src[i] == '\t' || src[i] == '\n' ||
                                  src[i] == '\r')) i++;
        if (i + 2 >= src.length || src.substring(i, 3) != "---") return;
        int nl = src.index_of_char('\n', i);
        if (nl < 0) return;
        int end = src.index_of("\n---", nl);
        if (end < 0) return;
        int after = src.index_of_char('\n', end + 1);
        advance_by((after < 0 ? src.length : after) - pos);
    }

    private void skip_to_next_line() {
        while (!at_end() && src[pos] != '\n') advance_by(1);
        if (!at_end()) advance_by(1);
    }

    /** After a bad rule: resume at the next ";" or line, whichever comes first. */
    private void skip_to_rule_end() {
        int guard = 0;
        while (!at_end() && guard++ < 1000000) {
            if (src[pos] == ';') { advance_by(1); return; }
            if (src[pos] == '\n') { advance_by(1); return; }
            advance_by(1);
        }
    }

    private string glimpse() {
        if (at_end()) return "end of input";
        int end = pos;
        while (end < src.length && end < pos + 12 && src[end] != '\n') end++;
        return src.substring(pos, end - pos);
    }

    private void error(string message) {
        failed = true;
        // One error per rule is enough; a cascade buries the real one.
        if (diagram.errors.size < 20) {
            diagram.errors.add(new ParseError(message, line, col));
        }
    }
}

}
