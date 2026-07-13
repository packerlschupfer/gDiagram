namespace GDiagram {

    /**
     * Where a click on a preview element puts the editor cursor. GTK-free, so the
     * choice is unit-tested; DocumentView only applies it to the buffer.
     *
     * The line is the single truth: the properties panel's line (the declaration the
     * inspector found in the source) when there is one, else the click region's
     * source line. Searching the whole text for the element's name is only the last
     * resort: it found "Use" inside ":User:" on another line, and nothing at all for a
     * region id ("Admin_the_application") that is not written in the source.
     */
    public class ClickNavigation : Object {

        /** The 1-based line to go to, or 0 when neither the inspector nor the region knows one. */
        public static int target_line(int region_line, ElementInfo? info, int line_count) {
            if (info != null && info.line > 0 && info.line <= line_count) {
                return info.line;
            }
            if (region_line > 0 && region_line <= line_count) {
                return region_line;
            }
            return 0;
        }

        /**
         * Names the element may be written as, most specific first: the alias, the id,
         * the region name with a synthetic suffix removed ("Foo_top"), a DOT id with its
         * underscores as spaces ("Admin_the_application"), and the label.
         */
        public static Gee.ArrayList<string> name_candidates(string element_name, ElementInfo? info) {
            var names = new Gee.ArrayList<string>();
            if (info != null) {
                if (info.alias != null) add_candidate(names, info.alias);
                if (!info.synthetic_id) add_candidate(names, info.id);
            }
            string base_name = ElementInspector.strip_synthetic_suffix(element_name);
            if (!ElementInspector.is_synthetic_id(base_name)) {
                add_candidate(names, base_name);
                if (base_name.has_prefix("n_")) add_candidate(names, base_name.substring(2));
                add_candidate(names, base_name.replace("_", " ").strip());
            }
            if (info != null && info.label != null) add_candidate(names, info.label);
            return names;
        }

        private static void add_candidate(Gee.ArrayList<string> names, string name) {
            string n = name.strip();
            if (n.length > 0 && !names.contains(n)) names.add(n);
        }

        /**
         * The byte span [start, end) of the element's name in `line_text`, so the selection
         * shows the element on its line. False when no candidate is there: the caller selects
         * the whole line.
         *
         * A match inside a longer quoted display label loses to one written on its own, and a
         * match that is the line's leading declaration keyword loses to a later one: on
         * `actor "Main Admin" as Admin` the first hit was the "Admin" inside "Main Admin"
         * instead of the declared name, and on `node node {` it was the keyword instead of the
         * state named "node". A name written nowhere but inside a label selects the whole
         * label; one written nowhere but as the keyword keeps it.
         */
        public static bool name_span(string line_text, Gee.List<string> candidates, out int start, out int end) {
            start = 0;
            end = 0;
            // ascii_down keeps byte offsets valid for the original text
            string haystack = line_text.ascii_down();
            // A name written only inside a longer quoted label: the label is selected whole
            int label_start = -1;
            int label_end = 0;
            int fallback = -1;
            int fallback_len = 0;
            foreach (string candidate in candidates) {
                string needle = candidate.ascii_down();
                if (needle.length == 0) continue;
                // A word boundary is needed where the name itself starts or ends with a word character
                bool check_start = is_word_char(needle.get_char(0));
                bool check_end = is_word_char(last_char(needle));
                int from = 0;
                while (from <= haystack.length - needle.length) {
                    int at = haystack.index_of(needle, from);
                    if (at < 0) break;
                    int after = at + needle.length;
                    bool before_ok = !check_start || at == 0 || !is_word_char(char_before(haystack, at));
                    bool after_ok = !check_end || after >= haystack.length || !is_word_char(haystack.get_char(after));
                    if (before_ok && after_ok) {
                        int qs, qe;
                        if (is_leading_keyword(haystack, at, needle)) {
                            // Keep it in case the name is written nowhere else on the line
                            if (fallback < 0) {
                                fallback = at;
                                fallback_len = needle.length;
                            }
                        } else if (inside_longer_quotes(haystack, at, after, out qs, out qe)) {
                            if (label_start < 0) {
                                label_start = qs;
                                label_end = qe;
                            }
                        } else {
                            start = at;
                            end = after;
                            return true;
                        }
                    }
                    from = at + 1;
                }
            }
            if (label_start >= 0) {
                start = label_start;
                end = label_end;
                return true;
            }
            if (fallback >= 0) {
                start = fallback;
                end = fallback + fallback_len;
                return true;
            }
            return false;
        }

        /**
         * [at, after) sits inside a quoted string that holds more than it — the alias of
         * `actor "Main Admin" as Admin` is written inside its display label. `qs`/`qe` bound
         * the quoted text, which is what a click should show when the name is nowhere else.
         */
        private static bool inside_longer_quotes(string s, int at, int after, out int qs, out int qe) {
            qs = 0;
            qe = 0;
            int i = 0;
            while (i < s.length) {
                char c = s[i];
                if (c != '"' && c != '\'') {
                    i++;
                    continue;
                }
                int close = s.index_of_char(c, i + 1);
                if (close < 0) {
                    return false;
                }
                if (at > i && after <= close) {
                    if (at == i + 1 && after == close) {
                        return false;   // the name is the whole quoted text
                    }
                    qs = i + 1;
                    qe = close;
                    return true;
                }
                i = close + 1;
            }
            return false;
        }

        /**
         * Declaration keywords a name can collide with ("state state", "node node"): the word
         * opens the statement, so a match there is the keyword, not the element.
         */
        private const string[] DECL_KEYWORDS = {
            "abstract", "actor", "agent", "annotation", "artifact", "boundary", "card", "class",
            "cloud", "collections", "component", "container", "control", "database", "entity",
            "enum", "file", "folder", "frame", "hexagon", "interface", "json", "label", "map",
            "namespace", "node", "object", "package", "participant", "person", "protocol",
            "queue", "rectangle", "stack", "state", "storage", "struct", "together", "usecase"
        };

        // `at` is a match of `needle` that opens the line and is a declaration keyword
        private static bool is_leading_keyword(string haystack, int at, string needle) {
            for (int i = 0; i < at; i++) {
                if (haystack[i] != ' ' && haystack[i] != '\t') return false;
            }
            foreach (string kw in DECL_KEYWORDS) {
                if (needle == kw) return true;
            }
            return false;
        }

        private static bool is_word_char(unichar c) {
            return c.isalnum() || c == '_';
        }

        private static unichar last_char(string s) {
            unowned string tail = s.offset(s.length);
            tail = tail.prev_char();
            return tail.get_char();
        }

        private static unichar char_before(string s, int index) {
            unowned string at = s.offset(index);
            return at.prev_char().get_char();
        }
    }
}
