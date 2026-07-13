namespace GDiagram {

    /**
     * Mermaid 12.2.0 `eventmodeling`.
     *
     * The grammar is line-oriented (every statement is one line, except the `{ … }`
     * data blocks of `data` and `note`, which span lines), so this parser walks raw
     * source lines rather than the token stream — the same approach the Mermaid
     * class, ER, state, sequence and gitgraph parsers already take here.
     *
     * The recovered langium grammar is reproduced in MermaidEventModeling.vala.
     * Deliberate differences from mermaid 12.2.0, both supersets that cannot draw
     * anything wrong:
     *
     *  * `title` / `accTitle` / `accDescr` are accepted. The grammar defines
     *    EM_TITLE / EM_ACC_TITLE / EM_ACC_DESCR terminals for them, but in the
     *    shipped build a generic keyword token shadows each one, so mermaid itself
     *    fails `title X` with "Expecting token of type 'EOF' but found `title`".
     *    Verified against @mermaid-js/parser 12.2.0. gDiagram honours the grammar.
     *  * a data block's closing `}` may be indented. EM_DATA_BLOCK requires it in
     *    column 0 (`\{[\t ]*\r?\n(?:[\S\s]*?\r?\n)?\}`), which rejects the natural
     *    indentation of a nested block.
     */
    public class MermaidEventModelingParser : Object {
        private MermaidEventModeling diagram;
        private string[] lines;
        private int pos;

        // A frame id is one to three digits (EM_FI = /\d{1,3}/); an entity id is
        // EM_ID = /[_a-zA-Z][\w_]*/, optionally dotted (QualifiedName).
        private const int MAX_LINES = 100000;

        public MermaidEventModeling parse(string source) {
            diagram = new MermaidEventModeling();
            lines = source.split("\n");
            pos = 0;

            skip_frontmatter();

            // Header. Mermaid's detector is /^\s*eventmodeling/, so anything may
            // follow the keyword on that line; the grammar consumes just the word.
            bool header = false;
            while (pos < lines.length) {
                string t = strip_comment(lines[pos]).strip();
                if (t.length == 0) { pos++; continue; }
                if (t == "eventmodeling" || t.has_prefix("eventmodeling ") ||
                    t.has_prefix("eventmodeling\t")) {
                    header = true;
                    pos++;
                }
                break;
            }
            if (!header) {
                diagram.errors.add(new ParseError("Expected 'eventmodeling'", pos + 1, 1));
                return diagram;
            }

            int guard = 0;
            while (pos < lines.length) {
                int before = pos;
                parse_statement();
                // Progress guard: a statement handler that consumed nothing would spin
                // here forever on malformed input.
                if (pos == before) pos++;
                if (++guard > MAX_LINES) {
                    diagram.errors.add(new ParseError("Document too long", pos + 1, 1));
                    break;
                }
            }

            renumber();
            return diagram;
        }

        // ---- lines ----

        /** `%%` starts a comment, unless it opens a `%%{ … }%%` directive. */
        private static string strip_comment(string line) {
            int i = line.index_of("%%");
            if (i < 0) return line;
            if (i + 2 < line.length && line[i + 2] == '{') return line;
            return line.substring(0, i);
        }

        private void skip_frontmatter() {
            int i = pos;
            while (i < lines.length && lines[i].strip().length == 0) i++;
            if (i >= lines.length || lines[i].strip() != "---") return;
            int j = i + 1;
            while (j < lines.length && lines[j].strip() != "---") {
                string t = lines[j].strip();
                if (t.has_prefix("title:")) {
                    string v = t.substring(6).strip();
                    if (v.length > 0) diagram.title = unquote(v);
                }
                j++;
            }
            // An unterminated front matter is not front matter at all.
            if (j < lines.length) pos = j + 1;
        }

        private static string unquote(string s) {
            if (s.length >= 2 &&
                ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                 (s.has_prefix("'") && s.has_suffix("'")))) {
                return s.substring(1, s.length - 2);
            }
            return s;
        }

        // ---- statements ----

        private void parse_statement() {
            int line_no = pos + 1;
            string raw = strip_comment(lines[pos]);
            string text = raw.strip();
            if (text.length == 0) { pos++; return; }

            // `%%{init: …}%%` directives are hidden terminals in the grammar.
            if (text.has_prefix("%%{")) { pos++; return; }

            string head = first_word(text);
            switch (head) {
                case "title":
                    diagram.title = rest_after(text, head);
                    pos++;
                    return;
                case "accTitle":
                    diagram.acc_title = strip_colon(rest_after(text, head));
                    pos++;
                    return;
                case "accDescr":
                    parse_acc_descr(text);
                    return;
                case "entity":
                    parse_entity(text, line_no);
                    return;
                case "data":
                    parse_data(text, line_no);
                    return;
                case "note":
                    parse_note(text, line_no);
                    return;
                case "gwt":
                    parse_gwt(text, line_no);
                    return;
                case "tf": case "timeframe":
                    parse_frame(text, head, false, line_no);
                    return;
                case "rf": case "resetframe":
                    parse_frame(text, head, true, line_no);
                    return;
                default:
                    diagram.errors.add(new ParseError(
                        "Unknown event modeling statement '%s'".printf(head), line_no, 1));
                    pos++;
                    return;
            }
        }

        private static string first_word(string text) {
            int i = 0;
            while (i < text.length && !text[i].isspace() && text[i] != ':') i++;
            return text.substring(0, i);
        }

        private static string rest_after(string text, string head) {
            return text.substring(head.length).strip();
        }

        private static string strip_colon(string s) {
            return s.has_prefix(":") ? s.substring(1).strip() : s;
        }

        private void parse_acc_descr(string text) {
            string rest = rest_after(text, "accDescr");
            if (rest.has_prefix("{")) {
                // accDescr { … } spans lines until the closing brace.
                var sb = new StringBuilder();
                string first = rest.substring(1);
                int close = first.index_of("}");
                if (close >= 0) {
                    diagram.acc_descr = first.substring(0, close).strip();
                    pos++;
                    return;
                }
                sb.append(first);
                pos++;
                while (pos < lines.length) {
                    string l = lines[pos];
                    int c = l.index_of("}");
                    if (c >= 0) {
                        sb.append("\n").append(l.substring(0, c));
                        pos++;
                        break;
                    }
                    sb.append("\n").append(l);
                    pos++;
                }
                diagram.acc_descr = sb.str.strip();
                return;
            }
            diagram.acc_descr = strip_colon(rest);
            pos++;
        }

        private void parse_entity(string text, int line_no) {
            string name = rest_after(text, "entity");
            if (name.length == 0) {
                diagram.errors.add(new ParseError("'entity' needs a name", line_no, 1));
            } else if (!is_qualified_name(name)) {
                diagram.errors.add(new ParseError(
                    "'%s' is not a valid entity name".printf(name), line_no, 1));
            } else {
                diagram.model_entities.add(new EmModelEntity(name, line_no));
            }
            pos++;
        }

        /** `data NAME [`type`] { … }` */
        private void parse_data(string text, int line_no) {
            string rest = rest_after(text, "data");
            string? dtype;
            string name = take_word(rest, out rest);
            rest = take_data_type(rest, out dtype);

            if (name.length == 0 || !is_entity_id(name)) {
                diagram.errors.add(new ParseError(
                    "'data' needs an identifier", line_no, 1));
                pos++;
                return;
            }
            string body = read_block(rest, line_no, "data");
            var d = new EmDataEntity(name, body, line_no);
            d.data_type = dtype;
            if (diagram.find_data(name) != null) {
                diagram.errors.add(new ParseError(
                    "Duplicate data block \"%s\"".printf(name), line_no, 1));
            }
            diagram.data_entities.add(d);
        }

        /** `note FRAME [`type`] { … }` — parsed and kept; mermaid 12.2.0 draws no notes. */
        private void parse_note(string text, int line_no) {
            string rest = rest_after(text, "note");
            string? dtype;
            string frame = take_word(rest, out rest);
            rest = take_data_type(rest, out dtype);

            if (!is_frame_id(frame)) {
                diagram.errors.add(new ParseError(
                    "'note' needs a frame id (one to three digits)", line_no, 1));
                pos++;
                return;
            }
            string body = read_block(rest, line_no, "note");
            var n = new EmNote(frame, body, line_no);
            n.data_type = dtype;
            diagram.notes.add(n);
        }

        /**
         * `gwt FRAME given <stmt>+ [when <stmt>+] then <stmt>+`, one line.
         * Parsed and kept; mermaid 12.2.0 draws no given/when/then.
         */
        private void parse_gwt(string text, int line_no) {
            pos++;
            string rest = rest_after(text, "gwt");
            string frame = take_word(rest, out rest);
            if (!is_frame_id(frame)) {
                diagram.errors.add(new ParseError(
                    "'gwt' needs a frame id (one to three digits)", line_no, 1));
                return;
            }
            var gwt = new EmGwt(frame, line_no);
            // given / when / then sections, in that order; `when` is optional.
            string[] words = rest.split_set(" \t");
            var section = gwt.given;
            bool seen_given = false, seen_then = false;
            int i = 0;
            EmEntityKind pending_kind = EmEntityKind.EVENT;
            bool has_pending = false;

            while (i < words.length) {
                string w = words[i].strip();
                i++;
                if (w.length == 0) continue;
                if (w == "given") { section = gwt.given; seen_given = true; has_pending = false; continue; }
                if (w == "when")  { section = gwt.when_items; has_pending = false; continue; }
                if (w == "then")  { section = gwt.then_items; seen_then = true; has_pending = false; continue; }

                EmEntityKind k = EmEntityKind.EVENT;
                if (!has_pending && EmEntityKind.try_parse(w, out k)) {
                    pending_kind = k;
                    has_pending = true;
                    continue;
                }
                if (has_pending) {
                    section.add(new EmGwtStatement(pending_kind, w));
                    has_pending = false;
                    continue;
                }
                diagram.errors.add(new ParseError(
                    "Expected an entity type before '%s' in 'gwt'".printf(w), line_no, 1));
                return;
            }
            if (!seen_given || !seen_then) {
                diagram.errors.add(new ParseError(
                    "'gwt' needs both a 'given' and a 'then' section", line_no, 1));
                return;
            }
            diagram.gwts.add(gwt);
        }

        /**
         * `tf|timeframe|rf|resetframe ID KIND ENTITY ('->>'ID)* ('[['REF']]')?
         *  ('`'TYPE'`')? (INLINE)?`
         */
        private void parse_frame(string text, string head, bool is_reset, int line_no) {
            pos++;
            string rest = rest_after(text, head);

            string name = take_word(rest, out rest);
            if (!is_frame_id(name)) {
                diagram.errors.add(new ParseError(
                    "A frame id must be one to three digits, not '%s'".printf(name),
                    line_no, 1));
                return;
            }
            string kind_word = take_word(rest, out rest);
            EmEntityKind kind;
            if (!EmEntityKind.try_parse(kind_word, out kind)) {
                diagram.errors.add(new ParseError(
                    "'%s' is not an entity type (ui, pcr/processor, rmo/readmodel, cmd/command, evt/event)".printf(kind_word),
                    line_no, 1));
                return;
            }
            string ident = take_word(rest, out rest);
            if (ident.length == 0 || !is_qualified_name(ident)) {
                diagram.errors.add(new ParseError(
                    "A frame needs an entity identifier", line_no, 1));
                return;
            }

            var frame = new EmFrame(name, kind, ident, line_no);
            frame.is_reset = is_reset;

            if (diagram.find_frame(name) != null) {
                // db.ts setAst() throws on a duplicate frame id, naming the line.
                diagram.errors.add(new ParseError(
                    "Duplicate event modeling frame ID \"%s\"".printf(name), line_no, 1));
                return;
            }

            // `->>NN` source frames, any number of them.
            int guard = 0;
            while (rest.has_prefix("->>")) {
                if (++guard > 1000) break;
                rest = rest.substring(3).strip();
                string src = take_word(rest, out rest);
                if (!is_frame_id(src)) {
                    diagram.errors.add(new ParseError(
                        "'->>' needs a frame id (one to three digits)", line_no, 1));
                    return;
                }
                frame.source_frames.add(src);
            }

            // `[[dataEntity]]`
            if (rest.has_prefix("[[")) {
                int close = rest.index_of("]]");
                if (close < 0) {
                    diagram.errors.add(new ParseError("Expected ']]'", line_no, 1));
                    return;
                }
                frame.data_reference = rest.substring(2, close - 2).strip();
                rest = rest.substring(close + 2).strip();
            }

            // Optional `` `type` `` then the inline data value.
            string? dtype;
            rest = take_data_type(rest, out dtype);
            frame.data_type = dtype;

            if (rest.length > 0) {
                if (is_inline_data(rest)) {
                    frame.data_inline = rest;
                } else {
                    diagram.errors.add(new ParseError(
                        "Unexpected '%s' after the frame".printf(rest), line_no, 1));
                    return;
                }
            }

            diagram.frames.add(frame);
        }

        // ---- small scanners ----

        /** Takes the next whitespace-delimited word, returning the remainder stripped. */
        private static string take_word(string s, out string rest) {
            string t = s.strip();
            int i = 0;
            while (i < t.length && !t[i].isspace()) i++;
            rest = t.substring(i).strip();
            return t.substring(0, i);
        }

        /** An optional `` `json` ``-style data type prefix. */
        private static string take_data_type(string s, out string? dtype) {
            dtype = null;
            string t = s.strip();
            if (!t.has_prefix("`")) return t;
            int close = t.index_of("`", 1);
            if (close < 0) return t;
            string word = t.substring(1, close - 1).strip();
            switch (word) {
                case "json": case "jsobj": case "figma": case "salt":
                case "uri": case "md": case "html": case "text":
                    dtype = word;
                    return t.substring(close + 1).strip();
                default:
                    // Not a data type — leave the backtick to the caller's own check.
                    return t;
            }
        }

        /** EM_DATA_INLINE = /\{(.*)\}|"(.*)"|'(.*)'/ */
        private static bool is_inline_data(string s) {
            if (s.length < 2) return false;
            return (s.has_prefix("{") && s.has_suffix("}")) ||
                   (s.has_prefix("\"") && s.has_suffix("\"")) ||
                   (s.has_prefix("'") && s.has_suffix("'"));
        }

        /**
         * Reads a `{ … }` block starting on the current line and advances past it.
         * `head` is whatever followed the statement on the opening line.
         *
         * The grammar wants the closing `}` in column 0; this accepts it indented
         * too (see the class comment).
         */
        private string read_block(string head, int line_no, string what) {
            string h = head.strip();
            if (!h.has_prefix("{")) {
                diagram.errors.add(new ParseError(
                    "'%s' needs a '{ … }' block".printf(what), line_no, 1));
                pos++;
                return "";
            }
            // A single-line block: `{ … }` closed on the same line.
            string after = h.substring(1);
            if (after.strip().has_suffix("}")) {
                string one = after.strip();
                pos++;
                return one.substring(0, one.length - 1).strip();
            }

            var sb = new StringBuilder();
            if (after.strip().length > 0) sb.append(after);
            pos++;
            bool closed = false;
            while (pos < lines.length) {
                string l = lines[pos];
                if (l.strip() == "}") { pos++; closed = true; break; }
                if (l.strip().has_suffix("}") && l.strip().length == 1) { pos++; closed = true; break; }
                sb.append(sb.len > 0 ? "\n" : "").append(l);
                pos++;
            }
            if (!closed) {
                diagram.errors.add(new ParseError(
                    "Unterminated '%s' block".printf(what), line_no, 1));
            }
            return sb.str;
        }

        // ---- validators ----

        /** EM_FI = /\d{1,3}/ */
        private static bool is_frame_id(string s) {
            if (s.length < 1 || s.length > 3) return false;
            for (int i = 0; i < s.length; i++) {
                if (!s[i].isdigit()) return false;
            }
            return true;
        }

        // EM_ID = /[_a-zA-Z][\w_]*/
        private static bool is_entity_id(string s) {
            if (s.length == 0) return false;
            char c = s[0];
            if (!(c == '_' || c.isalpha())) return false;
            for (int i = 1; i < s.length; i++) {
                if (!(s[i] == '_' || s[i].isalnum())) return false;
            }
            return true;
        }

        /** QualifiedName = EM_EID ('.' EM_EID)* */
        private static bool is_qualified_name(string s) {
            if (s.length == 0) return false;
            foreach (string part in s.split(".")) {
                if (!is_entity_id(part)) return false;
            }
            return true;
        }

        /** 0-based declaration order; the relation rules index frames by it. */
        private void renumber() {
            for (int i = 0; i < diagram.frames.size; i++) {
                diagram.frames[i].index = i;
            }
        }
    }

}
