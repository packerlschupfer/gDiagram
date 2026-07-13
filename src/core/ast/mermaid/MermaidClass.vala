namespace GDiagram {

    // ==================== MERMAID CLASS DIAGRAM ====================

    public enum MermaidClassType {
        CLASS,
        INTERFACE,
        ABSTRACT,
        ENUM
    }

    public enum MermaidVisibility {
        PUBLIC,      // +
        PRIVATE,     // -
        PROTECTED,   // #
        PACKAGE      // ~
    }

    public enum MermaidRelationType {
        INHERITANCE,      // <|--
        COMPOSITION,      // *--
        AGGREGATION,      // o--
        ASSOCIATION,      // -->
        DEPENDENCY,       // ..>
        REALIZATION,      // ..|>
        LINK,             // --
        DASHED_LINK       // ..
    }

    // The marker drawn at one end of a class relationship
    public enum MermaidRelationEnd {
        NONE,
        INHERITANCE,      // <| or |>
        COMPOSITION,      // *
        AGGREGATION,      // o
        ARROW,            // < or >
        LOLLIPOP          // ()
    }

    public class MermaidClassMember : Object {
        public string name { get; set; }
        public string? type_name { get; set; }
        public MermaidVisibility visibility { get; set; }
        public bool is_static { get; set; }
        public bool is_abstract { get; set; }
        public bool is_method { get; set; }
        // Method parameter text as written (generics as <T>), null for attributes
        public string? parameters { get; set; }
        // The member as Mermaid displays it: "+List<T> items", "+getArea(x float) : float"
        public string? display_text { get; set; }
        // Written with a visibility prefix (+ - # ~)
        public bool has_visibility { get; set; default = false; }

        public MermaidClassMember(string name, bool is_method = false) {
            this.name = name;
            this.is_method = is_method;
            this.visibility = MermaidVisibility.PUBLIC;
            this.is_static = false;
            this.is_abstract = false;
            this.type_name = null;
        }
    }

    public class MermaidClass : Object {
        public string name { get; set; }
        public MermaidClassType class_type { get; set; }
        public string? stereotype { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<MermaidClassMember> members { get; private set; }
        // class A["Label"]
        public string? label { get; set; }
        // class Repo~T~ -> "T" (displayed as Repo<T>)
        public string? generic_type { get; set; }
        // classDef names applied with cssClass / ":::"; a "style A ..." spec
        public Gee.ArrayList<string> css_classes { get; private set; default = new Gee.ArrayList<string>(); }
        public string? inline_style { get; set; }
        public string? namespace_name { get; set; }
        // "I ()-- J": I is the provided interface, drawn as a bare lollipop circle
        // with its name beside it instead of a class box (as Mermaid does)
        public bool lollipop_interface { get; set; default = false; }

        public MermaidClass(string name, MermaidClassType type = MermaidClassType.CLASS, int line = 0) {
            this.name = name;
            this.class_type = type;
            this.stereotype = null;
            this.source_line = line;
            this.members = new Gee.ArrayList<MermaidClassMember>();
        }

        public void add_member(MermaidClassMember member) {
            members.add(member);
        }
    }

    public class MermaidRelation : Object {
        public MermaidClass from { get; set; }
        public MermaidClass to { get; set; }
        public MermaidRelationType relation_type { get; set; }
        public string? label { get; set; }
        public string? from_cardinality { get; set; }
        public string? to_cardinality { get; set; }
        // Markers as written: "A <|-- B" has from_end INHERITANCE (drawn at A)
        public MermaidRelationEnd from_end { get; set; default = MermaidRelationEnd.NONE; }
        public MermaidRelationEnd to_end { get; set; default = MermaidRelationEnd.NONE; }
        public bool dashed { get; set; default = false; }

        public MermaidRelation(MermaidClass from, MermaidClass to, MermaidRelationType type) {
            this.from = from;
            this.to = to;
            this.relation_type = type;
            this.label = null;
            this.from_cardinality = null;
            this.to_cardinality = null;
        }
    }

    // note for A "text" (for_class set) or a free-standing note "text"
    public class MermaidClassNote : Object {
        public string text { get; set; }
        public MermaidClass? for_class { get; set; }
        public int source_line { get; set; }

        public MermaidClassNote(string text, MermaidClass? for_class, int line) {
            this.text = text;
            this.for_class = for_class;
            this.source_line = line;
        }
    }

    public class MermaidClassDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidClass> classes { get; private set; }
        public Gee.ArrayList<MermaidRelation> relations { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }
        public Gee.ArrayList<MermaidClassNote> notes { get; private set; default = new Gee.ArrayList<MermaidClassNote>(); }
        public FlowchartDirection direction { get; set; default = FlowchartDirection.TOP_DOWN; }
        // classDef name -> "fill:#f00,stroke:#333,color:white"
        public Gee.HashMap<string, string> class_defs { get; private set; default = new Gee.HashMap<string, string>(); }

        private Gee.HashMap<string, MermaidClass> class_map;

        public MermaidClassDiagram() {
            this.diagram_type = MermaidDiagramType.CLASS;
            this.classes = new Gee.ArrayList<MermaidClass>();
            this.relations = new Gee.ArrayList<MermaidRelation>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.class_map = new Gee.HashMap<string, MermaidClass>();
            this.title = null;
        }

        public void add_class(MermaidClass cls) {
            if (!class_map.has_key(cls.name)) {
                classes.add(cls);
                class_map.set(cls.name, cls);
            }
        }

        public MermaidClass? find_class(string name) {
            return class_map.get(name);
        }

        public MermaidClass get_or_create_class(string name) {
            var existing = find_class(name);
            if (existing != null) {
                return existing;
            }

            var cls = new MermaidClass(name);
            add_class(cls);
            return cls;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

    /**
     * Line-level helpers shared by the Mermaid class, ER and state parsers. Those
     * grammars are line oriented, so their parsers read the source text directly: the
     * exact text of labels, members and notes survives, and keywords used as names
     * ("string title", "state style") are ordinary words.
     */
    public class MermaidSourceLine : Object {
        public int line { get; set; }        // 1-based
        public string text { get; set; }     // comment-stripped and trimmed

        public MermaidSourceLine(int line, string text) {
            this.line = line;
            this.text = text;
        }

        /**
         * Split `source` into non-empty statement lines after the header keyword.
         * Front matter (`---` ... `---`) and `%%{init}%%` directives are skipped; a
         * front matter `title:` is returned in `title`. `header_ok` is false when the
         * first statement is not one of `headers` (that statement is then returned too).
         */
        public static Gee.ArrayList<MermaidSourceLine> split(string source, string[] headers,
                                                             out string? title, out bool header_ok) {
            title = null;
            header_ok = false;
            var result = new Gee.ArrayList<MermaidSourceLine>();
            string[] lines = source.split("\n");
            int i = 0;
            while (i < lines.length && lines[i].strip().length == 0) i++;
            if (i < lines.length && lines[i].strip() == "---") {
                int j = i + 1;
                while (j < lines.length && lines[j].strip() != "---") {
                    string l = lines[j].strip();
                    if (l.has_prefix("title:")) title = unquote(l.substring(6).strip());
                    j++;
                }
                if (j < lines.length) i = j + 1;
            }
            bool in_directive = false;
            bool seen_header = false;
            for (; i < lines.length; i++) {
                string raw = lines[i];
                if (in_directive) {
                    if (raw.contains("}%%")) in_directive = false;
                    continue;
                }
                string t = raw.strip();
                if (t.has_prefix("%%{")) {
                    if (!t.contains("}%%")) in_directive = true;
                    continue;
                }
                t = strip_comment(t).strip();
                if (t.length == 0) continue;
                if (!seen_header) {
                    seen_header = true;
                    string word = t;
                    int sp = first_space(t);
                    if (sp >= 0) word = t.substring(0, sp);
                    foreach (string h in headers) {
                        if (word == h) header_ok = true;
                    }
                    if (!header_ok) {
                        result.add(new MermaidSourceLine(i + 1, t));
                    } else if (sp >= 0) {
                        string rest = t.substring(sp).strip();
                        if (rest.length > 0) result.add(new MermaidSourceLine(i + 1, rest));
                    }
                    continue;
                }
                result.add(new MermaidSourceLine(i + 1, t));
            }
            return result;
        }

        /**
         * Cut a "%% comment" that starts outside double quotes. The "%%" must start a
         * word (line start or after whitespace): Mermaid keeps "50%% complete" and
         * "+note 100%% sure" as text, and cutting at any "%%" truncated them.
         */
        public static string strip_comment(string t) {
            bool quoted = false;
            int len = t.length;   // Vala re-reads `t.length` as strlen() on every test
            for (int k = 0; k + 1 < len; k++) {
                if (t[k] == '"') {
                    quoted = !quoted;
                } else if (!quoted && t[k] == '%' && t[k + 1] == '%' &&
                           (k == 0 || t[k - 1] == ' ' || t[k - 1] == '\t')) {
                    return t.substring(0, k);
                }
            }
            return t;
        }

        public static int first_space(string t, int from = 0) {
            int len = t.length;
            for (int k = from; k < len; k++) {
                if (t[k] == ' ' || t[k] == '\t') return k;
            }
            return -1;
        }

        public static string unquote(string s) {
            string t = s.strip();
            if (t.length >= 2 && ((t[0] == '"' && t[t.length - 1] == '"') ||
                                  (t[0] == '\'' && t[t.length - 1] == '\''))) {
                return t.substring(1, t.length - 2);
            }
            return t;
        }

        /**
         * First occurrence of `needle` at or after `from` outside double quotes, or -1.
         * Compares bytes in place and keeps the length in a local: materialising
         * `t.substring(k)` per character, and re-reading `t.length` (a strlen() call) in
         * the loop condition, made this quadratic on the per-keystroke parse path — a
         * 400 KB line took ~8 s.
         */
        public static int index_unquoted(string t, string needle, int from = 0) {
            bool quoted = false;
            int n = needle.length;
            int len = t.length;
            int limit = len - n;
            for (int k = 0; k < len; k++) {
                if (k >= from && !quoted && k <= limit) {
                    int j = 0;
                    while (j < n && t[k + j] == needle[j]) j++;
                    if (j == n) return k;
                }
                if (t[k] == '"') quoted = !quoted;
            }
            return -1;
        }

        // Keyword followed by whitespace or the end of the line
        public static bool starts_with_word(string t, string word) {
            if (!t.has_prefix(word)) return false;
            if (t.length == word.length) return true;
            char c = t[word.length];
            return c == ' ' || c == '\t';
        }

        public static bool parse_direction(string word, out FlowchartDirection dir) {
            dir = FlowchartDirection.TOP_DOWN;
            switch (word.strip()) {
                case "TB": case "TD": return true;
                case "BT": dir = FlowchartDirection.BOTTOM_UP; return true;
                case "LR": dir = FlowchartDirection.LEFT_RIGHT; return true;
                case "RL": dir = FlowchartDirection.RIGHT_LEFT; return true;
                default: return false;
            }
        }

        public static string rankdir(FlowchartDirection d) {
            switch (d) {
                case FlowchartDirection.LEFT_RIGHT: return "LR";
                case FlowchartDirection.RIGHT_LEFT: return "RL";
                case FlowchartDirection.BOTTOM_UP: return "BT";
                default: return "TB";
            }
        }

        /**
         * fill / stroke / color from "fill:#f9f,stroke:#333,color:white" specs, later
         * specs winning. Values are returned as written (null when absent).
         */
        public static void style_colors(Gee.List<string> specs, out string? fill, out string? stroke,
                                        out string? text) {
            fill = null; stroke = null; text = null;
            foreach (string spec in specs) {
                foreach (string part in spec.split(",")) {
                    int colon = part.index_of(":");
                    if (colon <= 0) continue;
                    string key = part.substring(0, colon).strip();
                    string value = part.substring(colon + 1).strip();
                    if (value.has_suffix(";")) value = value.substring(0, value.length - 1).strip();
                    if (value.length == 0) continue;
                    if (key == "fill") fill = value;
                    else if (key == "stroke") stroke = value;
                    else if (key == "color") text = value;
                }
            }
        }

        /** Mermaid generics: "List~Map~K,V~~" -> "List<Map<K,V>>" */
        public static string generics(string s) {
            if (!s.contains("~")) return s;
            var sb = new StringBuilder();
            int depth = 0;
            for (int k = 0; k < s.length; k++) {
                char c = s[k];
                if (c != '~') {
                    sb.append_c(c);
                    continue;
                }
                char next = k + 1 < s.length ? s[k + 1] : '\0';
                bool opens = next.isalnum() || next == '_' || next == '(' || next == '[' ||
                             (((uint8) next) & 0x80) != 0;
                if (depth > 0 && !opens) {
                    sb.append_c('>');
                    depth--;
                } else {
                    sb.append_c('<');
                    depth++;
                }
            }
            return sb.str;
        }
    }
}
