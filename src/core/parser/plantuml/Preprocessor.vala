namespace GDiagram {
    /**
     * Preprocessor runs PlantUML's preprocessing language before lexing.
     *
     * Supported:
     * - !include file / <C4/...> (bundled C4-PlantUML standard library)
     * - !define NAME VALUE, !define NAME(a, b) BODY, !definelong, !undef (legacy macros)
     * - variables: !$name = expr, !$name ?= expr, !name = expr, !global / !local
     * - !if / !elseif / !else / !endif, !ifdef / !ifndef, !while / !endwhile,
     *   !foreach $x in expr / !endfor
     * - !procedure, !function (with !return), !unquoted procedure / function,
     *   default and named arguments, overloads by argument count
     * - built-ins: %strlen, %substr, %strpos, %splitstr, %intval, %true, %false,
     *   %newline, %breakline, %get_variable_value, %set_variable_value,
     *   %variable_exists, %function_exists, %is_dark, %darken, %chr, ...
     *
     * The semantics follow PlantUML's own preprocessor: values are strings,
     * integers or arrays; a function call gets its own local scope in which an
     * assignment updates an existing global unless the name is local already
     * (parameters are local); variables are substituted in text lines, inside
     * quotes too, without rescanning the substituted value.
     *
     * Usage:
     *   var preprocessor = new Preprocessor();
     *   string processed = preprocessor.process(source, base_path);
     *   var lexer = new Lexer(processed);
     */
    public class Preprocessor : Object {
        // Track included files to prevent circular includes
        private Gee.HashSet<string> included_files;
        // Canonical path of the document being processed, when process() got its file path
        private string? main_document = null;

        // Legacy !define macros (simple and parameterized) and !definelong.
        private Gee.HashMap<string, Macro> defines;
        // !procedure / !function definitions by name as written ("$f", "Person"),
        // one entry per parameter count (PlantUML overloads by argument count).
        private Gee.HashMap<string, Gee.ArrayList<Macro>> functions;
        // Global variables by name as written ("$x", "NEW_C4_STYLE")
        private Gee.HashMap<string, PValue> globals;
        // Local scopes of the running function calls; only the innermost is visible
        private Gee.ArrayList<Gee.HashMap<string, PValue>> frames;

        // Maximum macro expansion recursion depth, to break infinite loops.
        private const int MAX_MACRO_DEPTH = 32;
        // Nested function/procedure calls
        private const int MAX_CALL_DEPTH = 100;
        // Executed body lines and loop iterations per process() call
        private const int64 MAX_STEPS = 100000;
        private int call_depth = 0;
        private int64 steps = 0;
        private bool step_limit_reported = false;

        // The legacy !define names currently being expanded; re-entering one
        // leaves the name literal, which breaks direct and indirect cycles.
        private Gee.HashSet<string> expanding_macros;

        // Stack of conditional frames for top-level !if/!ifdef/!ifndef/!else/!endif.
        private Gee.ArrayList<IfFrame> if_stack;

        // Maximum include depth to prevent infinite recursion
        private const int MAX_INCLUDE_DEPTH = 10;

        // Comment lines around included text. The Lexer keeps the line number of the
        // !include line between them, so the lines after an include keep their numbers.
        public const string INCLUDE_BEGIN_MARKER = "' [begin include: ";
        public const string INCLUDE_END_MARKER = "' [end include: ";

        /**
         * Main-file line number (1-based) of every line of preprocessed text, for
         * parsers that split the text into lines themselves instead of using the
         * Lexer. Same rule as the Lexer: everything from a begin-include marker to
         * its end marker has the line number of the !include line, so an included
         * element reports that line and the lines after an include keep their
         * numbers. Text without markers maps line i to i + 1.
         */
        public static int[] source_line_numbers(string[] lines) {
            var numbers = new int[lines.length];
            int line = 1;
            int depth = 0;
            for (int i = 0; i < lines.length; i++) {
                numbers[i] = line;
                if (is_include_marker(lines[i])) {
                    if (lines[i].chug().has_prefix(INCLUDE_BEGIN_MARKER)) {
                        depth++;
                    } else if (depth > 0) {
                        depth--;
                    }
                }
                if (depth == 0) {
                    line++;
                }
            }
            return numbers;
        }

        /** True for the begin/end include marker lines wrapped around included text. */
        public static bool is_include_marker(string line) {
            string s = line.chug();
            return s.has_prefix(INCLUDE_BEGIN_MARKER) || s.has_prefix(INCLUDE_END_MARKER);
        }

        /**
         * The text without its include marker lines, for parsers that hand the text
         * on as data (DOT source, ASCII art, YAML), where a marker is not a comment.
         */
        public static string strip_include_markers(string text) {
            if (!text.contains(INCLUDE_BEGIN_MARKER)) {
                return text;
            }
            var sb = new StringBuilder();
            string[] lines = text.split("\n");
            for (int i = 0; i < lines.length; i++) {
                if (is_include_marker(lines[i])) {
                    continue;
                }
                sb.append(lines[i]);
                if (i < lines.length - 1) {
                    sb.append_c('\n');
                }
            }
            return sb.str;
        }

        // Errors encountered during preprocessing
        public Gee.ArrayList<PreprocessorError> errors { get; private set; }

        public Preprocessor() {
            this.included_files = new Gee.HashSet<string>();
            this.defines = new Gee.HashMap<string, Macro>();
            this.functions = new Gee.HashMap<string, Gee.ArrayList<Macro>>();
            this.globals = new Gee.HashMap<string, PValue>();
            this.frames = new Gee.ArrayList<Gee.HashMap<string, PValue>>();
            this.if_stack = new Gee.ArrayList<IfFrame>();
            this.expanding_macros = new Gee.HashSet<string>();
            this.errors = new Gee.ArrayList<PreprocessorError>();
        }

        /**
         * Process source content, expanding all preprocessor directives.
         *
         * @param source The PlantUML source content
         * @param base_path The directory path for resolving relative includes (can be null)
         * @return The preprocessed source with all includes expanded
         */
        public string process(string source, string? base_path) {
            included_files.clear();
            defines.clear();
            functions.clear();
            globals.clear();
            frames.clear();
            if_stack.clear();
            expanding_macros.clear();
            errors.clear();
            call_depth = 0;
            steps = 0;
            step_limit_reported = false;
            main_document = null;
            // The document itself counts as included: without it a cycle back to
            // it (a includes b, b includes a) pasted the document's body in twice.
            if (base_path != null && base_path.length > 0 &&
                FileUtils.test(base_path, FileTest.IS_REGULAR)) {
                main_document = get_canonical_path(base_path);
                if (main_document != null) {
                    included_files.add(main_document);
                }
            }
            return process_internal(source, normalize_base_path(base_path), 0);
        }

        /**
         * Callers pass either the document's directory (the GUI) or the
         * document path itself (the CLI). Resolving "theme.puml" against a
         * FILE path yields "diagram.puml/theme.puml", which never exists, so
         * the include then fell back to the working directory and was
         * silently dropped anywhere else. Accept both.
         */
        private string? normalize_base_path(string? base_path) {
            if (base_path == null) {
                return null;
            }
            // Anything that is not an existing directory is a document path —
            // including one not saved yet — so resolve against its directory.
            if (!FileUtils.test(base_path, FileTest.IS_DIR)) {
                return Path.get_dirname(base_path);
            }
            return base_path;
        }

        /**
         * True iff every frame in the if-stack is currently active. When
         * false, the line loop suppresses both directive execution (except
         * for the conditional directives themselves) and text output.
         */
        private bool is_emitting() {
            foreach (var frame in if_stack) {
                if (!frame.active) return false;
            }
            return true;
        }

        private string process_internal(string source, string? base_path, int depth) {
            if (depth > MAX_INCLUDE_DEPTH) {
                errors.add(new PreprocessorError(
                    "Maximum include depth (%d) exceeded - possible circular include".printf(MAX_INCLUDE_DEPTH),
                    0
                ));
                return source;
            }

            var result = new StringBuilder();
            var lines = source.split("\n");
            int line_num = 0;
            int idx = 0;
            // <style> skinparams that did not fit in their block's lines
            var deferred_style = new Gee.ArrayList<string>();
            // Every source line consumed without output (directives, inactive
            // branches, definitions) leaves an empty placeholder line so later
            // lines keep their source line numbers for errors, click-to-source
            // and outline navigation. Inside a multi-line text block an empty
            // line would become part of the text, so there the placeholders wait
            // until the block has closed.
            int text_block = TEXT_BLOCK_NONE;
            int pending_placeholders = 0;

            while (idx < lines.length) {
                string line = lines[idx];
                line_num = idx + 1;
                string trimmed = line.strip();

                // Comments are not preprocessed; a block comment's lines pass through
                // untouched so a directive inside it does not run.
                if (trimmed.has_prefix("'")) {
                    result.append(line);
                    result.append("\n");
                    idx++;
                    continue;
                }
                if (trimmed.has_prefix("/'") && !trimmed.substring(2).contains("'/")) {
                    int k = idx;
                    while (k < lines.length && (k == idx || !lines[k].contains("'/"))) {
                        result.append(lines[k]);
                        result.append("\n");
                        k++;
                    }
                    if (k < lines.length) {
                        result.append(lines[k]);
                        result.append("\n");
                    }
                    idx = k + 1;
                    continue;
                }

                // Conditional directives are processed in every state because
                // they're how we escape an inactive branch.
                if (is_conditional_directive(trimmed)) {
                    process_conditional_directive(trimmed, line_num);
                    append_placeholder(result, text_block, ref pending_placeholders);
                    idx++;
                    continue;
                }

                string word = directive_word(trimmed);

                // Everything else is suppressed when we're inside an inactive branch.
                if (!is_emitting()) {
                    // A skipped definition or loop may hold its own !if/!endif lines;
                    // they must not close the branch they sit in.
                    int block_end = -1;
                    if (is_procedure_start(trimmed)) {
                        block_end = find_matching_proc_end(lines, idx);
                    } else if (word == "while" || word == "foreach") {
                        block_end = find_loop_end(lines, idx, lines.length);
                    }
                    int last = block_end >= 0 ? block_end : idx;
                    for (int k = idx; k <= last; k++) {
                        append_placeholder(result, text_block, ref pending_placeholders);
                    }
                    idx = last + 1;
                    continue;
                }

                // <style> ... </style> becomes the equivalent skinparam lines, which
                // every diagram parser already applies. The lexer used to skip the
                // block, so a style-based theme had no effect at all.
                if (trimmed.has_prefix("<style>")) {
                    int style_end = find_style_end(lines, idx);
                    if (style_end >= 0) {
                        var block = new StringBuilder();
                        for (int k = idx; k <= style_end; k++) {
                            block.append(expand_text(lines[k]));
                            block.append("\n");
                        }
                        string text = block.str;
                        int open = text.index_of("<style>") + "<style>".length;
                        int close = text.last_index_of("</style>");
                        string inner = close > open ? text.substring(open, close - open) : "";
                        var params = translate_style_block(inner);
                        // The translation occupies exactly the block's lines so later
                        // line numbers (errors, click-to-source, outline) stay stable.
                        // A block can yield more skinparams than it has lines
                        // ("<style>root { LineColor red }</style>" gives two); every
                        // parser reads one skinparam per line, so the surplus waits for
                        // the diagram's closing @end line. Skinparams apply to the whole
                        // diagram wherever they appear.
                        int block_lines = style_end - idx + 1;
                        for (int k = 0; k < block_lines; k++) {
                            if (k < params.size) {
                                result.append(params[k]);
                            }
                            result.append("\n");
                        }
                        for (int k = block_lines; k < params.size; k++) {
                            deferred_style.add(params[k]);
                        }
                        idx = style_end + 1;
                        continue;
                    }
                }
                if (deferred_style.size > 0 && trimmed.has_prefix("@end")) {
                    flush_deferred_style(result, deferred_style);
                }
                if (word == "include" && trimmed.length > 8 && (trimmed[8] == ' ' || trimmed[8] == '\t')) {
                    // The included text is already preprocessed; expanding it again
                    // substituted values into values
                    result.append(process_include_directive(trimmed, base_path, depth, line_num));
                    idx++;
                } else if (is_procedure_start(trimmed)) {
                    // Collect lines until matching !endprocedure / !enddefinelong
                    int proc_end = find_matching_proc_end(lines, idx);
                    if (proc_end < 0) {
                        errors.add(new PreprocessorError(
                            "Unterminated !procedure (no matching !endprocedure)",
                            line_num));
                        // Treat the whole rest of the file as the body to avoid
                        // dropping content silently
                        proc_end = lines.length - 1;
                    }
                    process_procedure_directive(lines, idx, proc_end, line_num);
                    for (int k = idx; k <= proc_end && k < lines.length; k++) {
                        append_placeholder(result, text_block, ref pending_placeholders);
                    }
                    idx = proc_end + 1;
                } else if (word == "while" || word == "foreach") {
                    int loop_end = find_loop_end(lines, idx, lines.length);
                    if (loop_end < 0) {
                        errors.add(new PreprocessorError(
                            "Unterminated !%s (no matching !end%s)".printf(word, word == "while" ? "while" : "for"),
                            line_num));
                        loop_end = lines.length - 1;
                        for (int k = idx; k <= loop_end; k++) {
                            append_placeholder(result, text_block, ref pending_placeholders);
                        }
                        idx = loop_end + 1;
                        continue;
                    }
                    var body = new Gee.ArrayList<string>();
                    for (int k = idx; k <= loop_end; k++) {
                        body.add(lines[k]);
                    }
                    var out_text = new StringBuilder();
                    PValue? ret = null;
                    exec_range(body, 0, body.size, false, out_text, ref ret);
                    if (steps > MAX_STEPS) {
                        // An endless loop: its thousands of lines would only stall the parsers
                        out_text.truncate(0);
                    }
                    // The loop output takes the loop's lines; spare lines stay as placeholders
                    int emitted = count_lines(out_text.str);
                    result.append(out_text.str);
                    for (int k = emitted; k < body.size; k++) {
                        append_placeholder(result, text_block, ref pending_placeholders);
                    }
                    idx = loop_end + 1;
                } else if (word == "define" && trimmed.length > 7 && (trimmed[7] == ' ' || trimmed[7] == '\t')) {
                    process_define_directive(trimmed, line_num);
                    append_placeholder(result, text_block, ref pending_placeholders);
                    idx++;
                } else if (is_assignment(trimmed)) {
                    process_assignment(trimmed);
                    append_placeholder(result, text_block, ref pending_placeholders);
                    idx++;
                } else if (word == "undef" && trimmed.length > 6 && (trimmed[6] == ' ' || trimmed[6] == '\t')) {
                    process_undef_directive(trimmed);
                    append_placeholder(result, text_block, ref pending_placeholders);
                    idx++;
                } else if (trimmed.down().has_prefix("!pragma")) {
                    // Pragmas configure the parsers ("!pragma useVerticalIf on"); pass them through.
                    // The lexer turns a line-start "!" line into a comment token others skip.
                    result.append(line);
                    result.append("\n");
                    idx++;
                } else if (trimmed.has_prefix("!")) {
                    // Other (unsupported) preprocessor directives — drop silently
                    append_placeholder(result, text_block, ref pending_placeholders);
                    idx++;
                } else {
                    result.append(expand_text(line));
                    result.append("\n");
                    text_block = next_text_block(text_block, trimmed, lines, idx);
                    if (text_block == TEXT_BLOCK_NONE) {
                        flush_placeholders(result, ref pending_placeholders);
                    }
                    idx++;
                }
            }
            // No @end line (an included file, or a source without tags)
            flush_placeholders(result, ref pending_placeholders);
            flush_deferred_style(result, deferred_style);

            return result.str;
        }

        private static int count_lines(string text) {
            int n = 0;
            for (int i = 0; i < text.length; i++) {
                if (text[i] == '\n') {
                    n++;
                }
            }
            return n;
        }

        // Multi-line text blocks in which an empty line is part of the text
        private const int TEXT_BLOCK_NONE = 0;
        private const int TEXT_BLOCK_NOTE = 1;      // note ... end note
        private const int TEXT_BLOCK_ACTIVITY = 2;  // :text ... ;
        private const int TEXT_BLOCK_QUOTE = 3;     // "text ... text"

        private void append_placeholder(StringBuilder result, int text_block, ref int pending) {
            if (text_block == TEXT_BLOCK_NONE) {
                result.append("\n");
            } else {
                pending++;
            }
        }

        private void flush_placeholders(StringBuilder result, ref int pending) {
            for (; pending > 0; pending--) {
                result.append("\n");
            }
        }

        /**
         * Text-block state after emitting the (active, non-directive) source
         * line `trimmed`. A misdetected block only moves placeholders further
         * down, it never drops them; any @end line closes a block.
         */
        private int next_text_block(int current, string trimmed, string[] lines, int idx) {
            if (trimmed.has_prefix("@end")) {
                return TEXT_BLOCK_NONE;
            }
            string low = trimmed.down();
            switch (current) {
                case TEXT_BLOCK_NOTE:
                    foreach (string end in new string[] { "end note", "endnote", "end hnote", "endhnote",
                                                          "end rnote", "endrnote" }) {
                        if (low.has_prefix(end)) {
                            return TEXT_BLOCK_NONE;
                        }
                    }
                    return TEXT_BLOCK_NOTE;
                case TEXT_BLOCK_ACTIVITY:
                    return ends_activity_text(trimmed) ? TEXT_BLOCK_NONE : TEXT_BLOCK_ACTIVITY;
                case TEXT_BLOCK_QUOTE:
                    return count_quotes(trimmed) % 2 == 1 ? TEXT_BLOCK_NONE : TEXT_BLOCK_QUOTE;
                default:
                    break;
            }
            if (low.has_prefix("'")) {
                return TEXT_BLOCK_NONE;
            }
            if (opens_note_block(low)) {
                return TEXT_BLOCK_NOTE;
            }
            // ":text" without its terminator; ":Actor:" (usecase) has a second colon
            if (trimmed.has_prefix(":") && trimmed.index_of(":", 1) < 0 && !ends_activity_text(trimmed)) {
                return TEXT_BLOCK_ACTIVITY;
            }
            if (count_quotes(trimmed) % 2 == 1 && opens_quoted_text(trimmed, lines, idx)) {
                return TEXT_BLOCK_QUOTE;
            }
            return TEXT_BLOCK_NONE;
        }

        /**
         * A line with an odd number of quotes starts a multi-line "text" only when its
         * last quote can open a string (at the line start or after a space or one of
         * "([{=,:") and a later line, before the diagram's @end, closes it. A stray
         * quote ("A -> B : 3.5" floppy") held back every later placeholder line until
         * @enduml, which moved the lines in between up.
         */
        private bool opens_quoted_text(string trimmed, string[] lines, int idx) {
            int q = trimmed.last_index_of_char('"');
            if (q > 0 && " \t([{=,:".index_of_char(trimmed[q - 1]) < 0) {
                return false;
            }
            for (int k = idx + 1; k < lines.length; k++) {
                string next = lines[k].strip();
                if (next.has_prefix("@end")) {
                    return false;
                }
                if (count_quotes(next) % 2 == 1) {
                    return true;
                }
            }
            return false;
        }

        // A note whose text follows on the next lines: no "note ... : text" and no "note "text""
        private bool opens_note_block(string low) {
            string s = low.has_prefix("floating ") ? low.substring("floating ".length).strip() : low;
            if (!(s == "note" || s.has_prefix("note ") || s.has_prefix("hnote ") || s.has_prefix("rnote "))) {
                return false;
            }
            if (s.contains("\"")) {
                return false;
            }
            // A single colon starts inline note text; "Class::member" does not
            for (int k = 0; k < s.length; k++) {
                if (s[k] == ':') {
                    bool doubled = (k + 1 < s.length && s[k + 1] == ':') || (k > 0 && s[k - 1] == ':');
                    if (!doubled) {
                        return false;
                    }
                }
            }
            return true;
        }

        private bool ends_activity_text(string trimmed) {
            if (trimmed.length < 2) {
                return false;
            }
            char last = trimmed[trimmed.length - 1];
            return last == ';' || last == '|' || last == '<' || last == '>' ||
                   last == '/' || last == '\\' || last == ']' || last == '}';
        }

        private int count_quotes(string text) {
            int n = 0;
            for (int k = 0; k < text.length; k++) {
                if (text[k] == '"') {
                    n++;
                }
            }
            return n;
        }

        private void flush_deferred_style(StringBuilder result, Gee.ArrayList<string> deferred) {
            if (deferred.size == 0) {
                return;
            }
            // Output must end in a newline before new lines are added after it
            if (result.len > 0 && !result.str.has_suffix("\n")) {
                result.append("\n");
            }
            foreach (var param in deferred) {
                result.append(param);
                result.append("\n");
            }
            deferred.clear();
        }

        private int find_style_end(string[] lines, int start) {
            for (int k = start; k < lines.length; k++) {
                if (lines[k].contains("</style>")) {
                    return k;
                }
            }
            return -1;
        }

        /**
         * Translate a <style> body into skinparam lines. Supported subset:
         *   document { BackgroundColor }                  -> backgroundColor
         *   root / element / fooDiagram { FontColor, FontName, FontSize,
         *                                 BackgroundColor, LineColor }
         *   arrow { LineColor, LineThickness, FontColor ... } -> arrowColor ...
         *   lifeLine { LineColor }                         -> sequenceLifeLineBorderColor
         *   separator { BackgroundColor, FontColor }       -> sequenceDivider...
         *   <element>[, <element>] { Property value }      -> <element><Property>
         *                                                     (LineColor -> BorderColor)
         * Stereotype (.name), element.stereotype and :depth() selectors are skipped.
         */
        private Gee.ArrayList<string> translate_style_block(string body) {
            var output = new Gee.ArrayList<string>();
            var selectors = new Gee.ArrayList<string>();
            var cleaned = new StringBuilder();
            foreach (string raw in body.split("\n")) {
                string t = raw.strip();
                if (t.has_prefix("'") || t.has_prefix("//")) {
                    continue;
                }
                cleaned.append(raw);
                cleaned.append("\n");
            }
            string text = cleaned.str;
            var buf = new StringBuilder();
            int i = 0;
            unichar c;
            while (text.get_next_char(ref i, out c)) {
                if (c == '{') {
                    selectors.add(buf.str.strip().down());
                    buf.truncate(0);
                } else if (c == '}') {
                    translate_style_property(buf.str, selectors, output);
                    buf.truncate(0);
                    if (selectors.size > 0) {
                        selectors.remove_at(selectors.size - 1);
                    }
                } else if (c == ';' || c == '\n') {
                    translate_style_property(buf.str, selectors, output);
                    buf.truncate(0);
                } else {
                    buf.append_unichar(c);
                }
            }
            return output;
        }

        private void translate_style_property(string raw, Gee.ArrayList<string> selectors,
                                              Gee.ArrayList<string> output) {
            string line = raw.strip();
            if (line.length == 0 || selectors.size == 0) {
                return;
            }
            int sp = -1;
            for (int k = 0; k < line.length; k++) {
                if (line[k] == ' ' || line[k] == '\t') {
                    sp = k;
                    break;
                }
            }
            if (sp <= 0) {
                return;
            }
            string prop = line.substring(0, sp);
            string value = line.substring(sp).strip();
            if (value.length == 0) {
                return;
            }
            string p = prop.down();

            // Innermost element selector; diagram-level selectors don't name one.
            // ".name" / "element.name" select a stereotype, ":depth(n)" a mind map level.
            string? element = null;
            string scope = "";
            string? stereotype = null;
            int depth = -1;
            foreach (var sel in selectors) {
                // An element nested in an element ("class { header { FontColor red } }",
                // a part of the class) has no skinparam: it became the page-level
                // "skinparam headerFontColor red". Ignored.
                bool names_element = !(sel.has_prefix(":depth(") || sel.has_prefix(".") ||
                                       sel == "root" || sel == "element" || sel == "document" ||
                                       sel.has_suffix("diagram"));
                if (names_element && element != null) {
                    return;
                }
                if (sel.length == 0 || sel.contains("*")) {
                    return;
                }
                if (sel.has_prefix(":depth(") && sel.has_suffix(")")) {
                    depth = int.parse(sel.substring(7, sel.length - 8));
                    continue;
                }
                if (sel.contains(":")) {
                    return;
                }
                if (sel.has_prefix(".")) {
                    stereotype = sel.substring(1);
                    continue;
                }
                int sel_dot = sel.index_of(".");
                if (sel_dot > 0) {
                    element = sel.substring(0, sel_dot);
                    stereotype = sel.substring(sel_dot + 1);
                    continue;
                }
                if (sel == "root" || sel == "element" || sel == "document" || sel.has_suffix("diagram")) {
                    scope = sel;
                } else {
                    element = sel;
                }
            }
            string mapped = p == "linecolor" ? "BorderColor" : (p == "linethickness" ? "BorderThickness" : prop);
            bool mind_map = scope == "mindmapdiagram" || scope == "wbsdiagram";

            // :depth(n) in a mind map / WBS: "skinparam depthN BackgroundColor x", the
            // form the mind map skinparam parser reads; "node {}" there is every level
            if (depth >= 0 || (mind_map && element == "node" && stereotype == null)) {
                if (p == "backgroundcolor" || p == "fontcolor" || p == "linecolor" || p == "fontsize") {
                    string target = depth >= 0 ? "depth%d".printf(depth) : "mindmapnode";
                    output.add("skinparam %s %s %s".printf(target, mapped, value));
                }
                return;
            }

            // Stereotype selectors: "skinparam class { BackgroundColor<<entity>> x }"
            if (stereotype != null && stereotype.length > 0) {
                output.add("skinparam %s { %s<<%s>> %s }".printf(element ?? "element", mapped, stereotype, value));
                return;
            }

            if (element == null) {
                if (scope == "document") {
                    if (p == "backgroundcolor") {
                        output.add("skinparam backgroundColor " + value);
                    }
                    return;
                }
                switch (p) {
                    case "fontcolor": output.add("skinparam defaultFontColor " + value); break;
                    case "fontname": output.add("skinparam defaultFontName " + value); break;
                    case "fontsize": output.add("skinparam defaultFontSize " + value); break;
                    case "backgroundcolor": output.add("skinparam elementBackgroundColor " + value); break;
                    case "linecolor":
                        output.add("skinparam elementBorderColor " + value);
                        output.add("skinparam arrowColor " + value);
                        break;
                    default: break;
                }
                return;
            }

            foreach (string part in element.split(",")) {
                string el = part.strip();
                if (el.length == 0) {
                    continue;
                }
                if (el == "arrow") {
                    if (p == "linecolor") {
                        output.add("skinparam arrowColor " + value);
                    } else if (p == "linethickness") {
                        output.add("skinparam arrowThickness " + value);
                    } else {
                        output.add("skinparam arrow%s %s".printf(prop, value));
                    }
                } else if (el == "lifeline") {
                    if (p == "linecolor") {
                        output.add("skinparam sequenceLifeLineBorderColor " + value);
                    } else if (p == "backgroundcolor") {
                        output.add("skinparam sequenceLifeLineBackgroundColor " + value);
                    }
                } else if (el == "separator") {
                    output.add("skinparam sequenceDivider%s %s".printf(p == "linecolor" ? "BorderColor" : prop, value));
                } else {
                    string name = p == "linecolor" ? "BorderColor" : (p == "linethickness" ? "BorderThickness" : prop);
                    output.add("skinparam %s%s %s".printf(el, name, value));
                }
            }
        }


        // ── Directive recognition ─────────────────────────────────

        /** The lowercase word after a line's leading '!' ("if", "procedure", ...), or "". */
        private static string directive_word(string trimmed) {
            if (!trimmed.has_prefix("!")) {
                return "";
            }
            int i = 1;
            while (i < trimmed.length && ((trimmed[i] >= 'a' && trimmed[i] <= 'z') ||
                                          (trimmed[i] >= 'A' && trimmed[i] <= 'Z'))) {
                i++;
            }
            return trimmed.substring(1, i - 1).down();
        }

        internal static bool is_ident_start(char c) {
            return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
        }

        internal static bool is_ident_char(char c) {
            return is_ident_start(c) || (c >= '0' && c <= '9');
        }

        /**
         * True for any !if/!ifdef/!ifndef/!else/!elseif/!endif directive.
         */
        private bool is_conditional_directive(string trimmed) {
            switch (directive_word(trimmed)) {
                case "if":
                case "ifdef":
                case "ifndef":
                case "elseif":
                case "else":
                case "endif":
                    return true;
                default:
                    return false;
            }
        }

        /**
         * Update the if-stack in response to a conditional directive.
         *
         *   !ifdef NAME    push frame, active = NAME is defined
         *   !ifndef NAME   push frame, active = NAME is NOT defined
         *   !if EXPR       push frame, active = EXPR is true
         *   !elseif EXPR   reuse top frame, active = !taken && EXPR
         *   !else          reuse top frame, active = !taken
         *   !endif         pop frame
         *
         * "taken" tracks whether any branch of the current chain has yet
         * emitted lines, so subsequent branches stay inactive. Expressions of
         * an inactive outer branch are not evaluated (they may call functions).
         */
        private void process_conditional_directive(string trimmed, int line_num) {
            string word = directive_word(trimmed);
            string arg = trimmed.substring(word.length + 1).strip();
            bool outer_active = true;
            int outer_frames = (word == "if" || word == "ifdef" || word == "ifndef") ? if_stack.size : if_stack.size - 1;
            for (int k = 0; k < outer_frames && k < if_stack.size; k++) {
                if (!if_stack[k].active) {
                    outer_active = false;
                }
            }
            switch (word) {
                case "ifdef":
                    push_if_frame(outer_active && is_defined(arg));
                    break;
                case "ifndef":
                    push_if_frame(outer_active && !is_defined(arg));
                    break;
                case "if":
                    push_if_frame(outer_active && evaluate_expression(arg));
                    break;
                case "elseif":
                    if (if_stack.size == 0) {
                        errors.add(new PreprocessorError(
                            "!elseif without matching !if/!ifdef", line_num));
                        return;
                    }
                    var frame = if_stack[if_stack.size - 1];
                    if (frame.taken || !outer_active) {
                        frame.active = false;
                    } else {
                        frame.active = evaluate_expression(arg);
                        frame.taken = frame.active;
                    }
                    break;
                case "else":
                    if (if_stack.size == 0) {
                        errors.add(new PreprocessorError(
                            "!else without matching !if/!ifdef", line_num));
                        return;
                    }
                    var frame = if_stack[if_stack.size - 1];
                    frame.active = !frame.taken;
                    frame.taken = true;
                    break;
                default:
                    if (if_stack.size == 0) {
                        errors.add(new PreprocessorError(
                            "!endif without matching !if/!ifdef", line_num));
                        return;
                    }
                    if_stack.remove_at(if_stack.size - 1);
                    break;
            }
        }

        private void push_if_frame(bool initially_active) {
            var frame = new IfFrame();
            frame.active = initially_active;
            frame.taken = initially_active;
            if_stack.add(frame);
        }

        private bool evaluate_expression(string expr) {
            return new PreprocessorExpression(expr, this).evaluate_bool();
        }

        private PValue eval(string expr) {
            return new PreprocessorExpression(expr, this).evaluate();
        }

        // !ifdef: a legacy define, a function or a variable of that name
        private bool is_defined(string name) {
            return defines.has_key(name) || functions.has_key(name) || get_var(name) != null;
        }

        /**
         * True if `trimmed` opens a multi-line procedure or function block:
         * !procedure, !function, !unquoted procedure/function, !definelong.
         */
        private bool is_procedure_start(string trimmed) {
            return trimmed.has_prefix("!procedure ") ||
                   trimmed.has_prefix("!procedure\t") ||
                   trimmed.has_prefix("!unquoted procedure ") ||
                   trimmed.has_prefix("!unquoted procedure\t") ||
                   trimmed.has_prefix("!function ") ||
                   trimmed.has_prefix("!function\t") ||
                   trimmed.has_prefix("!unquoted function ") ||
                   trimmed.has_prefix("!unquoted function\t") ||
                   trimmed.has_prefix("!definelong ") ||
                   trimmed.has_prefix("!definelong\t");
        }

        /**
         * Given the line index of a procedure-start directive, scan forward
         * for the matching !endprocedure / !endfunction / !enddefinelong.
         * Returns the line index of the end directive, or -1 if not found.
         */
        private int find_matching_proc_end(string[] lines, int start) {
            int depth = 1;
            for (int k = start + 1; k < lines.length; k++) {
                string t = lines[k].strip();
                if (is_procedure_start(t)) {
                    depth++;
                } else if (is_procedure_end(t)) {
                    depth--;
                    if (depth == 0) return k;
                }
            }
            return -1;
        }

        /**
         * True for any !endprocedure / !endfunction / !enddefinelong terminator.
         * Accepts both "!endfunction" and "!end function" forms (C4-PlantUML
         * uses the latter).
         */
        private bool is_procedure_end(string trimmed) {
            return trimmed == "!endprocedure" || trimmed.has_prefix("!endprocedure ") ||
                   trimmed == "!endfunction" || trimmed.has_prefix("!endfunction ") ||
                   trimmed == "!end procedure" || trimmed.has_prefix("!end procedure ") ||
                   trimmed == "!end function" || trimmed.has_prefix("!end function ") ||
                   trimmed == "!enddefinelong" || trimmed.has_prefix("!enddefinelong ");
        }

        // Index of the !endwhile / !endfor closing the loop opened at lines[start]
        private int find_loop_end(string[] lines, int start, int limit) {
            int depth = 0;
            for (int k = start; k < limit; k++) {
                string w = directive_word(lines[k].strip());
                if (w == "while" || w == "foreach") {
                    depth++;
                } else if (w == "endwhile" || w == "endfor" || w == "endforeach") {
                    depth--;
                    if (depth == 0) {
                        return k;
                    }
                }
            }
            return -1;
        }

        /**
         * Parse a multi-line procedure or function definition spanning
         * lines[start..end]. The first line is the directive itself, all
         * lines in between are the body, the last line is !endprocedure /
         * !endfunction / !enddefinelong (or the EOF if we recovered from
         * a missing terminator).
         */
        private void process_procedure_directive(string[] lines, int start, int end, int line_num) {
            var body = new Gee.ArrayList<string>();
            for (int k = start + 1; k < end && k < lines.length; k++) {
                body.add(lines[k]);
            }
            // A missing terminator: the last line is body too
            if (end < lines.length && !is_procedure_end(lines[end].strip())) {
                body.add(lines[end]);
            }
            define_procedure(lines[start].strip(), body, line_num);
        }

        private void define_procedure(string head, Gee.ArrayList<string> body, int line_num) {
            bool is_unquoted = false;
            bool is_function = false;
            bool is_legacy = false;
            string after_kw;

            if (head.has_prefix("!unquoted procedure")) {
                is_unquoted = true;
                after_kw = head.substring("!unquoted procedure".length).strip();
            } else if (head.has_prefix("!unquoted function")) {
                is_unquoted = true;
                is_function = true;
                after_kw = head.substring("!unquoted function".length).strip();
            } else if (head.has_prefix("!procedure")) {
                after_kw = head.substring("!procedure".length).strip();
            } else if (head.has_prefix("!function")) {
                is_function = true;
                after_kw = head.substring("!function".length).strip();
            } else if (head.has_prefix("!definelong")) {
                is_legacy = true;
                after_kw = head.substring("!definelong".length).strip();
            } else {
                return;
            }

            // The name keeps its '$' ("$getSprite"): PlantUML calls it that way
            int i = 0;
            if (i < after_kw.length && after_kw[i] == '$') i++;
            int name_start = i;
            while (i < after_kw.length && is_ident_char(after_kw[i]) && !(i == name_start && !is_ident_start(after_kw[i]))) {
                i++;
            }
            if (i == name_start) {
                errors.add(new PreprocessorError(
                    "Expected procedure name after directive", line_num));
                return;
            }
            string name = after_kw.substring(0, i);

            var macro = new Macro(name);
            macro.is_unquoted = is_unquoted;
            macro.is_function = is_function;
            macro.is_parameterized = true;
            macro.is_procedure = !is_legacy;

            if (i < after_kw.length && after_kw[i] == '(') {
                int paren_end;
                var param_list = parse_parameter_list(after_kw, i, out paren_end, line_num, !is_legacy);
                if (param_list == null) return;
                macro.parameters = param_list;
            }
            macro.body = body;

            if (is_legacy) {
                // !definelong NAME(a, b): a legacy define whose body has several lines
                defines.set(name.has_prefix("$") ? name.substring(1) : name, macro);
                return;
            }
            // Same name and parameter count replaces the earlier definition
            var overloads = functions.get(name);
            if (overloads == null) {
                overloads = new Gee.ArrayList<Macro>();
                functions.set(name, overloads);
            }
            for (int k = 0; k < overloads.size; k++) {
                if (overloads[k].parameters.size == macro.parameters.size) {
                    overloads.remove_at(k);
                    break;
                }
            }
            overloads.add(macro);
        }

        /**
         * Parse "!define NAME VALUE", "!define NAME(p1, p2) BODY",
         * or "!define NAME" (empty value).
         */
        private void process_define_directive(string line, int line_num) {
            // Strip "!define" + leading whitespace
            string body_text = line.substring(7).strip();
            if (body_text.length == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !define directive: missing name", line_num));
                return;
            }

            int i = 0;
            while (i < body_text.length && is_ident_char(body_text[i]) && !(i == 0 && !is_ident_start(body_text[i]))) {
                i++;
            }
            if (i == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !define directive: missing name", line_num));
                return;
            }

            string name = body_text.substring(0, i);
            var macro = new Macro(name);

            // Check for parameterized form: NAME(p1, p2) BODY
            if (i < body_text.length && body_text[i] == '(') {
                int paren_end;
                var param_list = parse_parameter_list(body_text, i, out paren_end, line_num, false);
                if (param_list == null) return;  // error already logged
                macro.parameters = param_list;
                macro.is_parameterized = true;
                i = paren_end + 1;  // skip past closing ')'
            }

            // Skip whitespace before the body
            while (i < body_text.length && (body_text[i] == ' ' || body_text[i] == '\t')) {
                i++;
            }

            // Everything after the name (and optional param list and whitespace) is the body.
            string value = (i < body_text.length) ? body_text.substring(i) : "";
            macro.body.add(value);

            defines.set(name, macro);
        }

        /**
         * Parse a "(p1, p2, p3=default)" parameter list starting at `start`
         * (which must point at the open paren). Returns the list of parameters
         * and sets `end` to the index of the closing paren. Returns null on
         * error (and logs to errors).
         *
         * For procedures and functions (`keep_dollar`) a parameter is a local
         * variable named as written ("$tags") and a default is an expression kept
         * as source text ("\"\"", "Small()"). Legacy defines drop the '$' and
         * store a quoted default without its quotes.
         */
        private Gee.ArrayList<MacroParameter>? parse_parameter_list(string text, int start, out int end,
                                                                   int line_num, bool keep_dollar) {
            end = start;
            var list = new Gee.ArrayList<MacroParameter>();
            if (start >= text.length || text[start] != '(') {
                errors.add(new PreprocessorError(
                    "Expected '(' in parameter list", line_num));
                return null;
            }

            int i = start + 1;
            while (i < text.length) {
                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;

                if (i >= text.length) break;
                if (text[i] == ')') {
                    end = i;
                    return list;
                }

                int name_start = i;
                if (text[i] == '$') i++;
                int name_real_start = i;
                while (i < text.length && is_ident_char(text[i]) && !(i == name_real_start && !is_ident_start(text[i]))) {
                    i++;
                }
                if (i == name_real_start) {
                    errors.add(new PreprocessorError(
                        "Expected parameter name in parameter list", line_num));
                    return null;
                }
                string param_name = keep_dollar
                    ? text.substring(name_start, i - name_start)
                    : text.substring(name_real_start, i - name_real_start);

                string? default_value = null;
                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                if (i < text.length && text[i] == '=') {
                    i++;
                    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                    int v_start = i;
                    int depth = 0;
                    char quote = 0;
                    while (i < text.length) {
                        char c = text[i];
                        if (quote != 0) {
                            if (c == quote) quote = 0;
                        } else if (c == '"' || c == '\'') {
                            quote = c;
                        } else if (c == '(') {
                            depth++;
                        } else if (c == ')') {
                            if (depth == 0) break;
                            depth--;
                        } else if (c == ',' && depth == 0) {
                            break;
                        }
                        i++;
                    }
                    default_value = text.substring(v_start, i - v_start).strip();
                    if (!keep_dollar && default_value.length >= 2 &&
                        (default_value[0] == '"' || default_value[0] == '\'') &&
                        default_value[default_value.length - 1] == default_value[0]) {
                        default_value = default_value.substring(1, default_value.length - 2);
                    }
                }

                list.add(new MacroParameter(param_name, default_value));

                while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
                if (i < text.length && text[i] == ',') {
                    i++;
                    continue;
                }
                if (i < text.length && text[i] == ')') {
                    end = i;
                    return list;
                }
            }

            errors.add(new PreprocessorError(
                "Unterminated parameter list (missing ')')", line_num));
            return null;
        }

        private void process_undef_directive(string line) {
            string name = line.substring(6).strip();
            defines.unset(name);
            functions.unset(name);
            globals.unset(name);
        }

        // ── Variables ─────────────────────────────────────────────

        internal PValue? get_var(string name) {
            if (frames.size > 0) {
                var local = frames[frames.size - 1].get(name);
                if (local != null) {
                    return local;
                }
            }
            return globals.get(name);
        }

        /**
         * PlantUML's assignment scope: !global and !local choose; otherwise a
         * name that is local already (a parameter, an earlier local) stays local,
         * an existing global is updated, and a new name is local inside a call.
         */
        private void put_var(string name, PValue value, string scope) {
            if (frames.size == 0 || scope == "global") {
                globals.set(name, value);
                return;
            }
            var local = frames[frames.size - 1];
            if (scope == "local" || local.has_key(name) || !globals.has_key(name)) {
                local.set(name, value);
            } else {
                globals.set(name, value);
            }
        }

        /** "!$x = e", "!$x ?= e", "!x = e", "!global $x = e", "!local $x = e" */
        private bool is_assignment(string trimmed) {
            int i;
            string scope;
            return parse_assignment_head(trimmed, out i, out scope) != null;
        }

        private string? parse_assignment_head(string t, out int after, out string scope) {
            after = 0;
            scope = "";
            if (!t.has_prefix("!")) {
                return null;
            }
            int i = 1;
            foreach (string kw in new string[] { "global", "local" }) {
                if (t.substring(i).has_prefix(kw) && i + kw.length < t.length &&
                    (t[i + kw.length] == ' ' || t[i + kw.length] == '\t')) {
                    scope = kw;
                    i += kw.length;
                    while (i < t.length && (t[i] == ' ' || t[i] == '\t')) i++;
                    break;
                }
            }
            int name_start = i;
            if (i < t.length && t[i] == '$') i++;
            if (i >= t.length || !is_ident_start(t[i])) {
                return null;
            }
            while (i < t.length && is_ident_char(t[i])) i++;
            string name = t.substring(name_start, i - name_start);
            while (i < t.length && (t[i] == ' ' || t[i] == '\t')) i++;
            if (i + 1 < t.length && t[i] == '?' && t[i + 1] == '=') {
                after = i + 2;
                scope = scope.length > 0 ? scope + "?" : "?";
                return name;
            }
            if (i < t.length && t[i] == '=' && (i + 1 >= t.length || t[i + 1] != '=')) {
                after = i + 1;
                return name;
            }
            return null;
        }

        private void process_assignment(string trimmed) {
            int after;
            string scope;
            string? name = parse_assignment_head(trimmed, out after, out scope);
            if (name == null) {
                return;
            }
            bool conditional = scope.has_suffix("?");
            if (conditional) {
                scope = scope.substring(0, scope.length - 1);
            }
            if (conditional && get_var(name) != null) {
                return;
            }
            put_var(name, eval(trimmed.substring(after).strip()), scope);
        }

        /**
         * Value of a name in an expression: a variable, else a legacy define
         * ("!define LEVEL 5" read as $LEVEL or LEVEL; numbers and true/false
         * become numbers so they compare and negate as such), else null.
         */
        internal PValue? lookup_expression_variable(string name) {
            var v = get_var(name);
            if (v != null) {
                return v;
            }
            string bare = name.has_prefix("$") ? name.substring(1) : name;
            var macro = defines.get(bare);
            if (macro == null || macro.is_parameterized) {
                return null;
            }
            string raw = macro.body.size > 0 ? macro.body[0].strip() : "";
            if (raw.length >= 2 && (raw[0] == '"' || raw[0] == '\'') && raw[raw.length - 1] == raw[0]) {
                raw = raw.substring(1, raw.length - 2);
            }
            int64 n;
            if (PValue.parse_int(raw, out n)) {
                return new PValue.of_int(n);
            }
            if (raw == "true" || raw == "false") {
                return new PValue.of_bool(raw == "true");
            }
            return new PValue.of_string(raw);
        }

        // ── Body execution ────────────────────────────────────────

        private bool step() {
            steps++;
            if (steps <= MAX_STEPS) {
                return true;
            }
            if (!step_limit_reported) {
                step_limit_reported = true;
                errors.add(new PreprocessorError(
                    "Preprocessor step limit exceeded - possible endless !while loop", 0));
            }
            return false;
        }

        /**
         * Run lines[from..to) of a procedure/function body (or a top-level loop).
         * Text lines are expanded; outside a function they are appended to `output`.
         * Returns true when a !return was executed (its value is in `ret`), which
         * ends the whole body.
         */
        private bool exec_range(Gee.List<string> lines, int from, int to, bool in_function,
                                StringBuilder output, ref PValue? ret) {
            int i = from;
            while (i < to) {
                if (!step()) {
                    return true;
                }
                string raw = lines[i];
                string t = raw.strip();

                if (t.has_prefix("'")) {
                    i++;
                    continue;
                }
                if (t.has_prefix("/'")) {
                    if (!t.substring(2).contains("'/")) {
                        while (i + 1 < to && !lines[i + 1].contains("'/")) {
                            i++;
                        }
                        i++;
                    }
                    i++;
                    continue;
                }
                if (!t.has_prefix("!")) {
                    string text = expand_text(raw);
                    if (!in_function) {
                        output.append(text);
                        output.append_c('\n');
                    }
                    i++;
                    continue;
                }

                string word = directive_word(t);
                switch (word) {
                    case "if":
                    case "ifdef":
                    case "ifndef":
                        int chain_end;
                        int branch_start;
                        int branch_end;
                        select_branch(lines, i, to, out branch_start, out branch_end, out chain_end);
                        if (branch_start >= 0 &&
                            exec_range(lines, branch_start, branch_end, in_function, output, ref ret)) {
                            return true;
                        }
                        i = chain_end + 1;
                        continue;
                    case "while":
                    case "foreach":
                        int loop_end = find_loop_end_in(lines, i, to);
                        int body_end = loop_end >= 0 ? loop_end : to;
                        if (word == "while") {
                            string cond = t.substring(6).strip();
                            while (step() && eval(cond).truthy()) {
                                if (exec_range(lines, i + 1, body_end, in_function, output, ref ret)) {
                                    return true;
                                }
                            }
                        } else if (exec_foreach(lines, i, body_end, in_function, output, ref ret)) {
                            return true;
                        }
                        i = body_end + 1;
                        continue;
                    case "return":
                        string expr = t.substring(7).strip();
                        ret = expr.length > 0 ? eval(expr) : new PValue.of_string("");
                        return true;
                    case "procedure":
                    case "function":
                    case "unquoted":
                    case "definelong":
                        if (is_procedure_start(t)) {
                            int end = i + 1;
                            int depth = 1;
                            for (; end < to; end++) {
                                string et = lines[end].strip();
                                if (is_procedure_start(et)) {
                                    depth++;
                                } else if (is_procedure_end(et) && --depth == 0) {
                                    break;
                                }
                            }
                            var body = new Gee.ArrayList<string>();
                            for (int k = i + 1; k < end && k < to; k++) {
                                body.add(lines[k]);
                            }
                            define_procedure(t, body, 0);
                            i = end + 1;
                            continue;
                        }
                        break;
                    case "define":
                        process_define_directive(t, 0);
                        break;
                    case "undef":
                        process_undef_directive(t);
                        break;
                    case "pragma":
                        if (!in_function) {
                            output.append(raw);
                            output.append_c('\n');
                        }
                        break;
                    default:
                        if (is_assignment(t)) {
                            process_assignment(t);
                        }
                        // !log, !assert, !option, stray !endif ... have no output
                        break;
                }
                i++;
            }
            return false;
        }

        private int find_loop_end_in(Gee.List<string> lines, int start, int limit) {
            int depth = 0;
            for (int k = start; k < limit; k++) {
                string w = directive_word(lines[k].strip());
                if (w == "while" || w == "foreach") {
                    depth++;
                } else if (w == "endwhile" || w == "endfor" || w == "endforeach") {
                    if (--depth == 0) {
                        return k;
                    }
                }
            }
            return -1;
        }

        /**
         * For the !if/!ifdef/!ifndef chain opening at lines[start]: the line range of
         * the branch whose condition holds (start -1 when none) and the !endif line.
         * Conditions are evaluated in order and only until one holds.
         */
        private void select_branch(Gee.List<string> lines, int start, int limit,
                                   out int branch_start, out int branch_end, out int chain_end) {
            branch_start = -1;
            branch_end = -1;
            chain_end = limit - 1;
            int depth = 0;
            bool chosen = false;
            int open_at = -1;  // body start of the chosen branch while its end is unknown
            for (int k = start; k < limit; k++) {
                string t = lines[k].strip();
                string w = directive_word(t);
                if (k > start) {
                    if (w == "if" || w == "ifdef" || w == "ifndef") {
                        depth++;
                        continue;
                    }
                    if (depth > 0) {
                        if (w == "endif") {
                            depth--;
                        }
                        continue;
                    }
                    if (w != "elseif" && w != "else" && w != "endif") {
                        continue;
                    }
                    if (open_at >= 0) {
                        branch_start = open_at;
                        branch_end = k;
                        open_at = -1;
                    }
                    if (w == "endif") {
                        chain_end = k;
                        return;
                    }
                }
                if (chosen) {
                    continue;
                }
                string arg = t.substring(w.length + 1).strip();
                bool holds;
                switch (w) {
                    case "ifdef":
                        holds = is_defined(arg);
                        break;
                    case "ifndef":
                        holds = !is_defined(arg);
                        break;
                    case "else":
                        holds = true;
                        break;
                    default:
                        holds = eval(arg).truthy();
                        break;
                }
                if (holds) {
                    chosen = true;
                    open_at = k + 1;
                }
            }
            // Unterminated chain: the chosen branch runs to the end
            if (open_at >= 0) {
                branch_start = open_at;
                branch_end = limit;
            }
        }

        // "!foreach $item in EXPR" over an array (from %splitstr / %str2json) or a single value
        private bool exec_foreach(Gee.List<string> lines, int start, int body_end, bool in_function,
                                  StringBuilder output, ref PValue? ret) {
            string t = lines[start].strip().substring(8).strip();
            int in_pos = t.index_of(" in ");
            if (in_pos <= 0) {
                return false;
            }
            string var_name = t.substring(0, in_pos).strip();
            PValue list = eval(t.substring(in_pos + 4).strip());
            var items = new Gee.ArrayList<PValue>();
            if (list.kind == PValue.ARR) {
                items.add_all(list.items);
            } else {
                var parsed = parse_json_array(list.to_text());
                if (parsed != null) {
                    items.add_all(parsed.items);
                } else {
                    items.add(list);
                }
            }
            foreach (var item in items) {
                if (!step()) {
                    return true;
                }
                put_var(var_name, item, "");
                if (exec_range(lines, start + 1, body_end, in_function, output, ref ret)) {
                    return true;
                }
            }
            return false;
        }

        // ── Calls ─────────────────────────────────────────────────

        /**
         * The overload of `name` that takes `positional` arguments plus the named
         * ones; with several, the one with the fewest parameters.
         */
        private Macro? resolve_function(string name, int positional, Gee.Set<string> named) {
            var overloads = functions.get(name);
            if (overloads == null) {
                return null;
            }
            Macro? best = null;
            foreach (var m in overloads) {
                if (positional > m.parameters.size) {
                    continue;
                }
                bool ok = true;
                for (int k = positional; k < m.parameters.size; k++) {
                    var p = m.parameters[k];
                    if (!named.contains(p.name) && p.default_value == null) {
                        ok = false;
                        break;
                    }
                }
                foreach (string key in named) {
                    bool known = false;
                    foreach (var p in m.parameters) {
                        if (p.name == key) {
                            known = true;
                        }
                    }
                    if (!known) {
                        ok = false;
                    }
                }
                if (ok && (best == null || m.parameters.size < best.parameters.size)) {
                    best = m;
                }
            }
            return best;
        }

        /** Call a function or procedure from an expression; null when there is no such function. */
        internal PValue? call_function_values(string name, Gee.ArrayList<PValue> args,
                                              Gee.HashMap<string, PValue> named) {
            var m = resolve_function(name, args.size, named.keys);
            if (m == null) {
                return null;
            }
            return invoke(m, args, named);
        }

        /**
         * Run a function or procedure with its parameters bound in a new local
         * scope. A function returns its !return value, a procedure its output
         * text (without the final newline).
         */
        private PValue invoke(Macro m, Gee.ArrayList<PValue> args, Gee.HashMap<string, PValue> named) {
            if (call_depth >= MAX_CALL_DEPTH) {
                return new PValue.of_string("");
            }
            var frame = new Gee.HashMap<string, PValue>();
            for (int k = 0; k < m.parameters.size; k++) {
                var p = m.parameters[k];
                PValue v;
                if (k < args.size) {
                    v = args[k];
                } else if (named.has_key(p.name)) {
                    v = named.get(p.name);
                } else if (p.default_value != null) {
                    // Defaults are expressions ("Small()", $LEGEND_IMAGE_SIZE_FACTOR),
                    // evaluated where the call is made
                    v = eval(p.default_value);
                } else {
                    v = new PValue.of_string("");
                }
                frame.set(p.name, v);
            }
            frames.add(frame);
            call_depth++;
            var output = new StringBuilder();
            PValue? ret = null;
            exec_range(m.body, 0, m.body.size, m.is_function, output, ref ret);
            call_depth--;
            frames.remove_at(frames.size - 1);
            if (steps > MAX_STEPS) {
                return new PValue.of_string("");
            }
            if (m.is_function) {
                return ret ?? new PValue.of_string("");
            }
            string text = output.str;
            if (text.has_suffix("\n")) {
                text = text.substring(0, text.length - 1);
            }
            return new PValue.of_string(text);
        }

        /**
         * A call written in a text line: `name` followed by the argument list at
         * `open` in `line`. Sets `end` to the closing paren and `text` to the
         * result. False when `name` has no overload taking these arguments; the
         * call then stays literal, as in PlantUML.
         */
        private bool try_text_call(string name, string line, int open, out int end, out string text) {
            text = "";
            end = open;
            if (!functions.has_key(name)) {
                return false;
            }
            var raw_args = split_arguments(line, open, out end);
            if (raw_args == null) {
                return false;
            }
            var positional = new Gee.ArrayList<string>();
            var raw_named = new Gee.HashMap<string, string>();
            foreach (string raw in raw_args) {
                string? arg_name;
                string value;
                if (split_named_argument(raw, out arg_name, out value)) {
                    raw_named.set(arg_name, value);
                } else {
                    positional.add(raw);
                }
            }
            var m = resolve_function(name, positional.size, raw_named.keys);
            if (m == null) {
                return false;
            }
            var args = new Gee.ArrayList<PValue>();
            foreach (string raw in positional) {
                args.add(text_argument_value(m, raw));
            }
            var named = new Gee.HashMap<string, PValue>();
            foreach (var entry in raw_named.entries) {
                named.set(entry.key, text_argument_value(m, entry.value));
            }
            text = invoke(m, args, named).to_text();
            return true;
        }

        /**
         * An argument of a call in a text line. A function or procedure evaluates
         * it as an expression. An !unquoted one takes the text itself: without its
         * quotes, with variables and calls substituted ("$PERSON_LEGEND_TEXT"), a
         * lone variable or call keeping its value's type.
         */
        private PValue text_argument_value(Macro m, string raw) {
            string s = raw.strip();
            if (!m.is_unquoted) {
                // gDiagram keeps the quotes of a string literal passed to a (quoted)
                // procedure: "note: $text" with Note("hello") gives note: "hello"
                if (!m.is_function && is_single_string_literal(s)) {
                    return new PValue.of_string(s);
                }
                return eval(s);
            }
            if (is_single_string_literal(s)) {
                return new PValue.of_string(expand_text(s.substring(1, s.length - 2)));
            }
            int64 n;
            if (PValue.parse_int(s, out n)) {
                return new PValue.of_int(n);
            }
            if (is_single_reference(s)) {
                return eval(s);
            }
            return new PValue.of_string(expand_text(s));
        }

        private static bool is_single_string_literal(string s) {
            if (s.length < 2 || (s[0] != '"' && s[0] != '\'') || s[s.length - 1] != s[0]) {
                return false;
            }
            return s.substring(1, s.length - 2).index_of_char(s[0]) < 0;
        }

        // "$name", "$f(...)", "f(...)" or "%f(...)" and nothing else
        private bool is_single_reference(string s) {
            int i = 0;
            if (i < s.length && (s[i] == '$' || s[i] == '%')) i++;
            if (i >= s.length || !is_ident_start(s[i])) {
                return false;
            }
            while (i < s.length && is_ident_char(s[i])) i++;
            if (i == s.length) {
                return s[0] == '$' && get_var(s) != null;
            }
            if (s[i] != '(') {
                return false;
            }
            int end;
            return split_arguments(s, i, out end) != null && end == s.length - 1;
        }

        // "$name = value" (not "==") → name "$name" and the value text
        private static bool split_named_argument(string raw, out string? name, out string value) {
            name = null;
            value = raw;
            string s = raw.strip();
            if (s.length < 3 || s[0] != '$' || !is_ident_start(s[1])) {
                return false;
            }
            int i = 1;
            while (i < s.length && is_ident_char(s[i])) i++;
            int name_end = i;
            while (i < s.length && (s[i] == ' ' || s[i] == '\t')) i++;
            if (i >= s.length || s[i] != '=' || (i + 1 < s.length && s[i + 1] == '=')) {
                return false;
            }
            name = s.substring(0, name_end);
            value = s.substring(i + 1).strip();
            return true;
        }

        /**
         * Parse a "(arg1, arg2, ...)" argument list starting at `start`
         * (which must point at the open paren). Respects nested parens and
         * quoted strings (so "Foo(Bar(x), \"a, b\")" parses as two args).
         * Sets `end` to the index of the closing paren.
         */
        private static Gee.ArrayList<string>? split_arguments(string text, int start, out int end) {
            end = start;
            var list = new Gee.ArrayList<string>();
            if (start >= text.length || text[start] != '(') return null;

            int i = start + 1;
            int paren_depth = 1;
            var current = new StringBuilder();
            char in_quote = 0;

            while (i < text.length) {
                char c = text[i];

                if (in_quote != 0) {
                    current.append_c(c);
                    if (c == in_quote) in_quote = 0;
                    i++;
                    continue;
                }
                if (c == '"' || c == '\'') {
                    in_quote = c;
                    current.append_c(c);
                    i++;
                    continue;
                }
                if (c == '(') {
                    paren_depth++;
                    current.append_c(c);
                    i++;
                    continue;
                }
                if (c == ')') {
                    paren_depth--;
                    if (paren_depth == 0) {
                        string arg = current.str.strip();
                        // Don't add an empty trailing arg from "Foo()"
                        if (list.size > 0 || arg.length > 0) {
                            list.add(arg);
                        }
                        end = i;
                        return list;
                    }
                    current.append_c(c);
                    i++;
                    continue;
                }
                if (c == ',' && paren_depth == 1) {
                    list.add(current.str.strip());
                    current = new StringBuilder();
                    i++;
                    continue;
                }
                current.append_c(c);
                i++;
            }
            return null;  // unterminated
        }

        // ── Text lines ────────────────────────────────────────────

        /**
         * Substitute a text line: calls of known functions/procedures ($f(...),
         * Name(...)), built-ins (%f(...)), variables ($x, bare legacy names) and
         * legacy !define macros. Substituted values are not scanned again (legacy
         * defines are, as before). Text inside quotes is substituted too.
         */
        internal string expand_text(string line) {
            if (line.index_of_char('$') < 0 && line.index_of_char('%') < 0 && defines.size == 0 &&
                functions.size == 0 && globals.size == 0 && frames.size == 0) {
                return line;
            }
            var sb = new StringBuilder();
            int n = line.length;
            int i = 0;
            while (i < n) {
                char c = line[i];
                bool sigil = (c == '$' || c == '%') && i + 1 < n && is_ident_start(line[i + 1]);
                bool bare = !sigil && is_ident_start(c) &&
                            !(i > 0 && (is_ident_char(line[i - 1]) || line[i - 1] == '$' || line[i - 1] == '%'));
                if (!sigil && !bare) {
                    sb.append_c(c);
                    i++;
                    continue;
                }
                int j = sigil ? i + 1 : i;
                while (j < n && is_ident_char(line[j])) j++;
                string name = line.substring(i, j - i);

                if (j < n && line[j] == '(') {
                    int end;
                    string text;
                    if (c == '%') {
                        var raw_args = split_arguments(line, j, out end);
                        if (raw_args != null) {
                            var args = new Gee.ArrayList<PValue>();
                            foreach (string raw in raw_args) {
                                args.add(eval(raw));
                            }
                            PValue? r = call_builtin(name.substring(1), args);
                            if (r != null) {
                                sb.append(r.to_text());
                                i = end + 1;
                                continue;
                            }
                        }
                    } else if (try_text_call(name, line, j, out end, out text)) {
                        sb.append(text);
                        i = end + 1;
                        continue;
                    } else if (!sigil || c == '$') {
                        string macro_name = sigil ? name.substring(1) : name;
                        var macro = defines.get(macro_name);
                        if (macro != null && macro.is_parameterized && !expanding_macros.contains(macro_name)) {
                            var raw_args = split_arguments(line, j, out end);
                            if (raw_args != null && expanding_macros.size < MAX_MACRO_DEPTH) {
                                expanding_macros.add(macro_name);
                                sb.append(expand_define_call(macro, raw_args));
                                expanding_macros.remove(macro_name);
                                i = end + 1;
                                continue;
                            }
                        }
                    }
                }

                if (c != '%') {
                    var v = get_var(name);
                    if (v != null) {
                        sb.append(v.to_text());
                        i = j;
                        continue;
                    }
                    string macro_name = sigil ? name.substring(1) : name;
                    var macro = defines.get(macro_name);
                    if (macro != null && !macro.is_parameterized && !expanding_macros.contains(macro_name) &&
                        expanding_macros.size < MAX_MACRO_DEPTH) {
                        expanding_macros.add(macro_name);
                        sb.append(expand_text(macro.body.size > 0 ? macro.body[0] : ""));
                        expanding_macros.remove(macro_name);
                        i = j;
                        continue;
                    }
                }
                sb.append(name);
                i = j;
            }
            return sb.str;
        }

        /**
         * A legacy "!define NAME(a, b) body" / !definelong call: the arguments
         * replace the parameters ("a" and "$a") verbatim, missing ones take the
         * default, and the result is expanded again.
         */
        private string expand_define_call(Macro macro, Gee.ArrayList<string> args) {
            var subs = new Gee.HashMap<string, string>();
            for (int p = 0; p < macro.parameters.size; p++) {
                var param = macro.parameters[p];
                subs.set(param.name, p < args.size ? args[p] : (param.default_value ?? ""));
            }
            var sb = new StringBuilder();
            for (int li = 0; li < macro.body.size; li++) {
                string line = macro.body[li];
                string t = line.strip();
                if (macro.body.size > 1 && (t.has_prefix("'") || t.has_prefix("!"))) {
                    continue;
                }
                if (sb.len > 0) {
                    sb.append_c('\n');
                }
                sb.append(expand_text(substitute_params(line, subs)));
            }
            return sb.str;
        }

        /**
         * Substitute parameter references in `line` with values from `subs`,
         * both the $name form and the bare name, whole words only.
         */
        private static string substitute_params(string line, Gee.HashMap<string, string> subs) {
            if (subs.size == 0) return line;
            var sb = new StringBuilder();
            int n = line.length;
            int i = 0;
            while (i < n) {
                char c = line[i];
                bool dollar = c == '$' && i + 1 < n && is_ident_start(line[i + 1]);
                bool bare = is_ident_start(c) && !(i > 0 && is_ident_char(line[i - 1]));
                if (!dollar && !bare) {
                    sb.append_c(c);
                    i++;
                    continue;
                }
                int j = dollar ? i + 1 : i;
                int name_start = j;
                while (j < n && is_ident_char(line[j])) j++;
                string name = line.substring(name_start, j - name_start);
                string? value = subs.get(name);
                sb.append(value ?? line.substring(i, j - i));
                i = j;
            }
            return sb.str;
        }

        // ── Built-in functions ────────────────────────────────────

        private static string[] BUILTINS = {
            "strlen", "substr", "strpos", "string", "intval", "lower", "upper", "strlower", "strupper",
            "true", "false", "not", "boolval", "newline", "breakline", "chr", "dec2hex", "hex2dec", "mod",
            "splitstr", "splitstr_regex", "size", "str2json", "get_variable_value", "set_variable_value",
            "variable_exists", "function_exists", "invoke_procedure", "call_user_func", "is_dark",
            "is_light", "darken", "lighten", "reverse_color", "version", "getenv", "get_env", "date",
            "filename", "dirpath", "feature", "json_key_exists", "random", "load_json", "tab"
        };

        /** A built-in %name(args); null for an unknown one (the call then stays literal). */
        internal PValue? call_builtin(string name, Gee.ArrayList<PValue> args) {
            string a0 = args.size > 0 ? args[0].to_text() : "";
            switch (name) {
                case "strlen":
                    return new PValue.of_int(a0.char_count());
                case "substr":
                    return new PValue.of_string(substr(a0, args));
                case "strpos":
                    if (args.size < 2) return new PValue.of_int(-1);
                    int at = a0.index_of(args[1].to_text());
                    return new PValue.of_int(at < 0 ? -1 : a0.char_count(at));
                case "string":
                    return new PValue.of_string(a0);
                case "intval":
                    int64 iv = 0;
                    return new PValue.of_int(args.size > 0 && args[0].to_int(out iv) ? iv : 0);
                case "lower":
                case "strlower":
                    return new PValue.of_string(a0.down());
                case "upper":
                case "strupper":
                    return new PValue.of_string(a0.up());
                case "true":
                    return new PValue.of_bool(true);
                case "false":
                    return new PValue.of_bool(false);
                case "not":
                    return new PValue.of_bool(!(args.size > 0 && args[0].truthy()));
                case "boolval":
                    string low = a0.strip().down();
                    return new PValue.of_bool(args.size > 0 && low != "false" && low != "0" && args[0].truthy());
                case "newline":
                case "breakline":
                    return new PValue.of_string("\n");
                case "tab":
                    return new PValue.of_string("\t");
                case "chr":
                    int64 code = 0;
                    if (args.size > 0 && args[0].to_int(out code) && code > 0 && code <= 0x10FFFF &&
                        ((unichar) code).validate()) {
                        return new PValue.of_string(((unichar) code).to_string());
                    }
                    return new PValue.of_string("");
                case "dec2hex":
                    int64 dv = 0;
                    return new PValue.of_string(args.size > 0 && args[0].to_int(out dv) ? ("%" + int64.FORMAT_MODIFIER + "x").printf(dv) : "");
                case "hex2dec":
                    int64 hv = 0;
                    foreach (uint8 hc in a0.strip().data) {
                        if (!((char) hc).isxdigit()) {
                            hv = 0;
                            break;
                        }
                        hv = hv * 16 + ((char) hc).xdigit_value();
                    }
                    return new PValue.of_int(hv);
                case "mod":
                    int64 x = 0, y = 0;
                    if (args.size >= 2 && args[0].to_int(out x) && args[1].to_int(out y) && y != 0) {
                        return new PValue.of_int(x % y);
                    }
                    return new PValue.of_int(0);
                case "splitstr":
                case "splitstr_regex":
                    var parts = new Gee.ArrayList<PValue>();
                    if (args.size >= 2 && a0.length > 0) {
                        string sep = args[1].to_text();
                        string[] pieces;
                        if (name == "splitstr_regex") {
                            try {
                                pieces = new Regex(sep).split(a0);
                            } catch (RegexError e) {
                                pieces = { a0 };
                            }
                        } else {
                            pieces = sep.length > 0 ? a0.split(sep) : new string[] { a0 };
                        }
                        foreach (string piece in pieces) {
                            parts.add(new PValue.of_string(piece));
                        }
                    }
                    return new PValue.of_array(parts);
                case "size":
                    if (args.size > 0 && args[0].kind == PValue.ARR) {
                        return new PValue.of_int(args[0].items.size);
                    }
                    return new PValue.of_int(a0.char_count());
                case "str2json":
                    return parse_json_array(a0) ?? new PValue.of_string(a0);
                case "get_variable_value":
                    return get_var(a0) ?? new PValue.of_string("");
                case "set_variable_value":
                    // Sets the global; a local of that name follows along
                    if (args.size >= 2) {
                        globals.set(a0, args[1]);
                        if (frames.size > 0 && frames[frames.size - 1].has_key(a0)) {
                            frames[frames.size - 1].set(a0, args[1]);
                        }
                    }
                    return new PValue.of_string("");
                case "variable_exists":
                    return new PValue.of_bool(get_var(a0) != null);
                case "function_exists":
                    if (a0.has_prefix("%")) {
                        return new PValue.of_bool(a0.substring(1) in BUILTINS);
                    }
                    return new PValue.of_bool(functions.has_key(a0) || defines.has_key(a0));
                case "invoke_procedure":
                case "call_user_func":
                    if (args.size == 0) return new PValue.of_string("");
                    var call_args = new Gee.ArrayList<PValue>();
                    for (int k = 1; k < args.size; k++) {
                        call_args.add(args[k]);
                    }
                    return call_function_values(a0, call_args, new Gee.HashMap<string, PValue>()) ??
                           new PValue.of_string("");
                case "is_dark":
                case "is_light":
                    int r, g, b;
                    if (!parse_color(a0, out r, out g, out b)) {
                        return new PValue.of_bool(false);
                    }
                    bool dark = (r * 299 + g * 587 + b * 114) / 1000 < 128;
                    return new PValue.of_bool(name == "is_dark" ? dark : !dark);
                case "darken":
                case "lighten":
                    int64 percent = 0;
                    if (args.size > 1) {
                        args[1].to_int(out percent);
                    }
                    return new PValue.of_string(adjust_lightness(a0, name == "darken" ? -percent : percent));
                case "reverse_color":
                    int rr, rg, rb;
                    if (!parse_color(a0, out rr, out rg, out rb)) {
                        return new PValue.of_string(a0);
                    }
                    return new PValue.of_string("#%02X%02X%02X".printf(255 - rr, 255 - rg, 255 - rb));
                case "version":
                    // A PlantUML version string; C4's LAYOUT_AS_SKETCH() compares its parts
                    return new PValue.of_string("1.2025.0");
                case "feature":
                case "json_key_exists":
                case "random":
                    return new PValue.of_int(0);
                case "getenv":
                case "get_env":
                case "date":
                case "filename":
                case "dirpath":
                case "load_json":
                    return new PValue.of_string("");
                default:
                    return null;
            }
        }

        private static string substr(string s, Gee.ArrayList<PValue> args) {
            int64 start = 0;
            if (args.size > 1) {
                args[1].to_int(out start);
            }
            int len = s.char_count();
            if (start < 0) {
                start = 0;
            }
            if (start >= len) {
                return "";
            }
            int64 count = len - start;
            if (args.size > 2) {
                int64 wanted;
                if (args[2].to_int(out wanted)) {
                    count = wanted < 0 ? 0 : int64.min(wanted, len - start);
                }
            }
            int from = s.index_of_nth_char((long) start);
            int to = s.index_of_nth_char((long) (start + count));
            return s.substring(from, to - from);
        }

        private static PValue? parse_json_array(string text) {
            string t = text.strip();
            if (!t.has_prefix("[")) {
                return null;
            }
            var parser = new Json.Parser();
            try {
                parser.load_from_data(t);
            } catch (Error e) {
                return null;
            }
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                return null;
            }
            var items = new Gee.ArrayList<PValue>();
            root.get_array().foreach_element((array, index, node) => {
                if (node.get_node_type() == Json.NodeType.VALUE && node.get_value_type() == typeof(string)) {
                    items.add(new PValue.of_string(node.get_string()));
                } else if (node.get_node_type() == Json.NodeType.VALUE && node.get_value_type() == typeof(int64)) {
                    items.add(new PValue.of_int(node.get_int()));
                } else {
                    items.add(new PValue.of_string(Json.to_string(node, false)));
                }
            });
            return new PValue.of_array(items);
        }

        // "#RGB", "#RRGGBB" or a common color name
        private static bool parse_color(string color, out int r, out int g, out int b) {
            r = g = b = 0;
            string c = color.strip().down();
            if (c.has_prefix("#")) {
                c = c.substring(1);
            }
            switch (c) {
                case "black": c = "000000"; break;
                case "white": c = "ffffff"; break;
                case "red": c = "ff0000"; break;
                case "green": c = "008000"; break;
                case "blue": c = "0000ff"; break;
                case "yellow": c = "ffff00"; break;
                case "orange": c = "ffa500"; break;
                case "purple": c = "800080"; break;
                case "gray":
                case "grey": c = "808080"; break;
                case "darkgray":
                case "darkgrey": c = "a9a9a9"; break;
                case "lightgray":
                case "lightgrey": c = "d3d3d3"; break;
                case "navy": c = "000080"; break;
                case "khaki": c = "f0e68c"; break;
                case "darkkhaki": c = "bdb76b"; break;
                default: break;
            }
            if (c.length == 3) {
                c = "%c%c%c%c%c%c".printf(c[0], c[0], c[1], c[1], c[2], c[2]);
            }
            if (c.length != 6) {
                return false;
            }
            for (int i = 0; i < 6; i++) {
                if (!c[i].isxdigit()) {
                    return false;
                }
            }
            r = (c[0].xdigit_value() << 4) | c[1].xdigit_value();
            g = (c[2].xdigit_value() << 4) | c[3].xdigit_value();
            b = (c[4].xdigit_value() << 4) | c[5].xdigit_value();
            return true;
        }

        // HSL lightness scaled down (darken) or towards white (lighten) by `percent`
        private static string adjust_lightness(string color, int64 percent) {
            int r, g, b;
            if (!parse_color(color, out r, out g, out b)) {
                return color;
            }
            double rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
            double max = double.max(rf, double.max(gf, bf));
            double min = double.min(rf, double.min(gf, bf));
            double l = (max + min) / 2;
            double h = 0, s = 0;
            if (max != min) {
                double d = max - min;
                s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
                if (max == rf) {
                    h = (gf - bf) / d + (gf < bf ? 6 : 0);
                } else if (max == gf) {
                    h = (bf - rf) / d + 2;
                } else {
                    h = (rf - gf) / d + 4;
                }
                h /= 6;
            }
            double p = percent / 100.0;
            l = p < 0 ? l * (1 + p) : l + (1 - l) * p;
            l = double.max(0, double.min(1, l));
            double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            double pp = 2 * l - q;
            int nr = (int) Math.round(hue_to_rgb(pp, q, h + 1.0 / 3) * 255);
            int ng = (int) Math.round(hue_to_rgb(pp, q, h) * 255);
            int nb = (int) Math.round(hue_to_rgb(pp, q, h - 1.0 / 3) * 255);
            return "#%02X%02X%02X".printf(nr, ng, nb);
        }

        private static double hue_to_rgb(double p, double q, double t) {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0 / 6) return p + (q - p) * 6 * t;
            if (t < 0.5) return q;
            if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
            return p;
        }

        private string process_include_directive(string line, string? base_path, int depth, int line_num) {
            // Parse: !include <path> or !include path
            string path = extract_include_path(line);

            if (path == null || path.length == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !include directive: missing path",
                    line_num
                ));
                return "' [preprocessor error] Invalid !include: %s\n".printf(line);
            }

            // "<C4/C4_Container>" and the C4-PlantUML GitHub URLs (which the C4 files
            // themselves include) resolve to the bundled C4-PlantUML copy, offline.
            // Other standard libraries are not bundled.
            string? stdlib_path = null;
            if (path.has_prefix("<") && path.has_suffix(">")) {
                stdlib_path = resolve_stdlib_include(path.substring(1, path.length - 2));
                if (stdlib_path == null) {
                    errors.add(new PreprocessorError(
                        "Standard library include not available: %s".printf(path),
                        line_num
                    ));
                    return "' [preprocessor] Unsupported standard library include: %s\n".printf(path);
                }
            } else {
                stdlib_path = resolve_c4_url(path);
            }

            // Resolve the file path
            string? resolved_path = stdlib_path ?? resolve_path(path, base_path);

            if (resolved_path == null) {
                errors.add(new PreprocessorError(
                    "Cannot resolve include path: %s".printf(path),
                    line_num
                ));
                return "' [preprocessor error] Cannot resolve: %s\n".printf(path);
            }

            // Check for circular includes
            string canonical_path = get_canonical_path(resolved_path);
            if (canonical_path != null && included_files.contains(canonical_path)) {
                if (canonical_path == main_document) {
                    errors.add(new PreprocessorError(
                        "Circular include of the document itself skipped: %s".printf(path),
                        line_num
                    ));
                    return "' [preprocessor] Circular include skipped: %s\n".printf(path);
                }
                // Already included - skip silently (this is valid PlantUML behavior)
                return "' [preprocessor] Already included: %s\n".printf(path);
            }

            if (canonical_path != null) {
                included_files.add(canonical_path);
            }

            // Read the file
            string? content = read_file(resolved_path);
            if (content == null) {
                errors.add(new PreprocessorError(
                    "Cannot read include file: %s".printf(resolved_path),
                    line_num
                ));
                return "' [preprocessor error] Cannot read: %s\n".printf(resolved_path);
            }

            // Get the directory of the included file for nested includes
            string? include_base_path = get_directory(resolved_path);

            // Strip @startuml and @enduml from included content
            string stripped = strip_uml_tags(content);

            // Recursively process the included content
            string processed = process_internal(stripped, include_base_path, depth + 1);

            // Wrap with markers for debugging
            var result = new StringBuilder();
            result.append("%s%s]\n".printf(INCLUDE_BEGIN_MARKER, path));
            result.append(processed);
            if (!processed.has_suffix("\n")) {
                result.append("\n");
            }
            result.append("%s%s]\n".printf(INCLUDE_END_MARKER, path));

            return result.str;
        }

        private string? extract_include_path(string line) {
            // !include <path> or !include path or !include "path"
            string after_include = line.substring(8).strip();  // Skip "!include"

            if (after_include.length == 0) {
                return null;
            }

            // Handle quoted paths
            if (after_include.has_prefix("\"") && after_include.has_suffix("\"") && after_include.length > 2) {
                return after_include.substring(1, after_include.length - 2);
            }

            // Handle angle-bracket paths (standard library)
            if (after_include.has_prefix("<") && after_include.has_suffix(">")) {
                return after_include;  // Return with brackets for identification
            }

            // Plain path - take until whitespace or end
            int space_idx = after_include.index_of(" ");
            if (space_idx > 0) {
                return after_include.substring(0, space_idx);
            }

            return after_include;
        }

        /**
         * Directories holding the bundled standard library (data/stdlib): the
         * GDIAGRAM_STDLIB_DIR override, the installed copy, and the source tree
         * next to a build-tree binary (build/src/gdiagram, build/tests/x).
         */
        public static Gee.ArrayList<string> stdlib_dirs() {
            var dirs = new Gee.ArrayList<string>();
            string? env = Environment.get_variable("GDIAGRAM_STDLIB_DIR");
            if (env != null && env.length > 0) {
                dirs.add(env);
            }
            dirs.add(Path.build_filename(DATADIR, "gdiagram", "stdlib"));
            try {
                string exe = FileUtils.read_link("/proc/self/exe");
                string dir = Path.get_dirname(exe);
                dirs.add(Path.build_filename(dir, "..", "..", "data", "stdlib"));
                dirs.add(Path.build_filename(dir, "..", "data", "stdlib"));
            } catch (FileError e) {
                // no /proc: installed locations only
            }
            return dirs;
        }

        // "C4/C4_Container" (library name case-insensitive, ".puml" optional) -> bundled file
        private static string? resolve_stdlib_include(string name) {
            string[] parts = name.strip().split("/", 2);
            if (parts.length != 2 || parts[0].down() != "c4") {
                return null;
            }
            string file = Path.get_basename(parts[1]);
            if (!file.has_suffix(".puml")) {
                file += ".puml";
            }
            foreach (string dir in stdlib_dirs()) {
                string candidate = Path.build_filename(dir, "C4", file);
                if (FileUtils.test(candidate, FileTest.IS_REGULAR)) {
                    return candidate;
                }
            }
            return null;
        }

        // ".../plantuml-stdlib/C4-PlantUML/<ref>/C4_Container.puml" -> the bundled file
        private static string? resolve_c4_url(string path) {
            string low = path.down();
            if (!(low.has_prefix("http://") || low.has_prefix("https://")) || !low.contains("/c4-plantuml/")) {
                return null;
            }
            return resolve_stdlib_include("C4/" + Path.get_basename(path));
        }

        private string? resolve_path(string path, string? base_path) {
            // Absolute path
            if (Path.is_absolute(path)) {
                if (FileUtils.test(path, FileTest.EXISTS)) {
                    return path;
                }
                return null;
            }

            // Relative path - resolve against base_path
            if (base_path != null) {
                string full_path = Path.build_filename(base_path, path);
                if (FileUtils.test(full_path, FileTest.EXISTS)) {
                    return full_path;
                }
            }

            // Try current working directory as fallback
            if (FileUtils.test(path, FileTest.EXISTS)) {
                return path;
            }

            return null;
        }

        private string? get_canonical_path(string path) {
            // Normalise `..`, `.`, and redundant slashes so includes
            // reached via different path strings (e.g. `foo.puml`,
            // `./foo.puml`, `a/../foo.puml`) produce the same key in
            // the circular-include set. Without this, a creative
            // !include chain could reload the same file repeatedly
            // until MAX_INCLUDE_DEPTH triggers.
            //
            // Note: this is path normalisation only — it does not
            // resolve symlinks. For include-loop prevention that's
            // enough; symlink resolution would be overkill.
            return GLib.Filename.canonicalize(path);
        }

        private string? get_directory(string path) {
            return Path.get_dirname(path);
        }

        private string? read_file(string path) {
            try {
                string content;
                FileUtils.get_contents(path, out content);
                return content;
            } catch (Error e) {
                return null;
            }
        }

        /**
         * Strip @startuml and @enduml tags from included file content.
         * These tags should only appear in the main file, not in includes.
         */
        private string strip_uml_tags(string content) {
            var result = new StringBuilder();
            var lines = content.split("\n");
            bool first = true;

            foreach (var line in lines) {
                string trimmed = line.strip().down();
                // Skip @startuml (with or without diagram name) and @enduml
                if (trimmed.has_prefix("@startuml") || trimmed == "@enduml") {
                    continue;
                }
                if (!first) {
                    result.append("\n");
                }
                first = false;
                result.append(line);
            }
            // The file's final newline ends its last line; process_internal ends every
            // line with one. Kept, it became blank lines inside the included text,
            // which a ditaa drawing shows.
            if (result.str.has_suffix("\n")) {
                result.truncate(result.len - 1);
            }

            return result.str;
        }

        /**
         * Check if preprocessing produced any errors.
         */
        public bool has_errors() {
            return errors.size > 0;
        }
    }

    /**
     * Represents an error encountered during preprocessing.
     */
    public class PreprocessorError : Object {
        public string message { get; private set; }
        public int line { get; private set; }

        public PreprocessorError(string message, int line) {
            this.message = message;
            this.line = line;
        }
    }

    /**
     * One frame on the conditional-compilation stack.
     *
     * `active` controls whether the line loop currently emits output for the
     * lines inside this if-branch. `taken` records whether any branch in
     * the if/elseif/else chain has been entered yet — once true, all
     * subsequent branches stay inactive.
     */
    public class IfFrame : Object {
        public bool active;
        public bool taken;
    }

    /**
     * A formal parameter of a macro/procedure/function. For procedures and
     * functions the name is the local variable as written ("$tags") and the
     * default is expression source text; for legacy defines the name has no '$'
     * and the default is the substituted text. default_value is null when no
     * default was given.
     */
    public class MacroParameter : Object {
        public string name { get; set; }
        public string? default_value { get; set; }

        public MacroParameter(string name, string? default_value = null) {
            this.name = name;
            this.default_value = default_value;
        }
    }

    /**
     * A preprocessor macro: a legacy !define / !definelong, or a !procedure /
     * !function (optionally !unquoted). The body is a list of lines so the same
     * class works for one-line defines and multi-line procedures.
     */
    public class Macro : Object {
        public string name { get; set; }
        public Gee.ArrayList<MacroParameter> parameters { get; set; }
        public Gee.ArrayList<string> body { get; set; }
        public bool is_parameterized { get; set; }
        public bool is_unquoted { get; set; }
        public bool is_function { get; set; }
        // True for !procedure / !function (not a legacy define)
        public bool is_procedure { get; set; }

        public Macro(string name) {
            this.name = name;
            this.parameters = new Gee.ArrayList<MacroParameter>();
            this.body = new Gee.ArrayList<string>();
            this.is_parameterized = false;
            this.is_unquoted = false;
            this.is_function = false;
            this.is_procedure = false;
        }
    }
}
