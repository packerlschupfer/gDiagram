namespace GDiagram {
    public enum ClassType {
        CLASS,
        INTERFACE,
        ABSTRACT,
        ENUM,
        ANNOTATION,
        ENTITY,       // entity keyword (IE/crow's-foot diagrams)
        STRUCT,       // struct keyword
        // Further declaration keywords of PlantUML's class diagram, each drawn with its
        // own spot letter there (X, P, M, S, D, R); "circle" is a small circle
        EXCEPTION,
        PROTOCOL,
        METACLASS,
        STEREOTYPE,
        DATACLASS,
        RECORD,
        CIRCLE
    }

    public enum MemberVisibility {
        PUBLIC,      // +
        PRIVATE,     // -
        PROTECTED,   // #
        PACKAGE      // ~
    }

    public enum RelationshipType {
        INHERITANCE,      // --|>
        IMPLEMENTATION,   // ..|>
        ASSOCIATION,      // -->
        DEPENDENCY,       // ..>
        AGGREGATION,      // o--
        COMPOSITION       // *--
    }

    public class ClassMember : Object {
        public string name { get; set; }
        public string? type_name { get; set; }
        public MemberVisibility visibility { get; set; }
        public bool is_static { get; set; }
        public bool is_abstract { get; set; }
        public bool is_method { get; set; }
        public bool mandatory { get; set; default = false; }  // "* id : int" entity attribute
        // Written with a visibility marker (+ - # ~). PlantUML shows none for a bare member.
        public bool visibility_explicit = false;
        // Separator line in the body ("--", "..", "==", "__"); `name` holds its title
        public string? separator = null;
        // Hidden by a "hide private members" / "hide fields" style command
        public bool hidden_member = false;

        public ClassMember(string name, bool is_method = false) {
            this.name = name;
            this.is_method = is_method;
            this.visibility = MemberVisibility.PUBLIC;
            this.is_static = false;
            this.is_abstract = false;
            this.type_name = null;
        }

        // Marker drawn before the member: "* " (mandatory), the visibility, or nothing
        public string get_marker_text() {
            if (mandatory) {
                return "* ";
            }
            if (visibility_explicit || visibility != MemberVisibility.PUBLIC) {
                return get_visibility_symbol() + " ";
            }
            return "";
        }

        public string get_visibility_symbol() {
            switch (visibility) {
                case MemberVisibility.PRIVATE: return "-";
                case MemberVisibility.PROTECTED: return "#";
                case MemberVisibility.PACKAGE: return "~";
                default: return "+";
            }
        }
    }

    public class UmlClass : Object {
        public string name { get; set; }
        public string? display_name { get; set; }  // set when "as Alias" is used; quoted name as label
        public ClassType class_type { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        // "#back:pink;line:red;line.dashed;text:blue" / "##[dashed]blue": border colour
        // and style, text colour
        public string? line_color;
        public string? line_style;
        public string? text_color;
        // "class E<T>": the generic parameters ("T")
        public string? generic;
        // Unique DOT id, set by ClassDiagram.assign_ids()
        public string? dot_id;
        public int source_line { get; set; }
        public Gee.ArrayList<ClassMember> members { get; private set; }
        public bool is_diamond;  // "<> name": association diamond, not a class box
        // "$tag" markers written after the declaration ("class C1 $tag13 $tag1")
        public Gee.ArrayList<string> tags = new Gee.ArrayList<string>();
        public bool removed = false;  // "remove X": not drawn, nor its links
        public bool hidden = false;   // "hide X": drawn invisibly, so the layout keeps its place
        // Package the class was declared in (the package owns the reference)
        public unowned ClassPackage? owner_package;
        // "<< (S,#FF7700) Singleton >>": the spot letter and colour of a custom spot
        public string? spot_letter;
        public string? spot_color;
        // "-class Foo" / "#class Foo": the class's own visibility marker ("-", "#", "~", "+")
        public string? visibility_marker;
        // Results of "hide/show ... fields|methods|members|circle|stereotype"
        public bool fields_hidden = false;
        public bool methods_hidden = false;
        public bool empty_fields_hidden = false;
        public bool empty_methods_hidden = false;
        public bool circle_hidden = false;
        public bool stereotype_hidden = false;

        public UmlClass(string name, ClassType type = ClassType.CLASS, int line = 0) {
            this.name = name;
            this.display_name = null;
            this.class_type = type;
            this.stereotype = null;
            this.color = null;
            this.source_line = line;
            this.members = new Gee.ArrayList<ClassMember>();
        }

        public void add_member(ClassMember member) {
            members.add(member);
        }

        // The stereotype as shown: "Singleton" of "(S,#FF7700) Singleton", null for a spot
        // spec alone ("(D,orchid)")
        public string? get_stereotype_text() {
            if (stereotype == null) {
                return null;
            }
            string s = stereotype.strip();
            if (s.has_prefix("(")) {
                int close = s.index_of(")");
                if (close > 0) {
                    s = s.substring(close + 1).strip();
                }
            }
            return s.length > 0 ? s : null;
        }

        public string get_id() {
            if (dot_id != null) {
                return dot_id;
            }
            return get_base_id();
        }

        // DOT id from the name alone; different names can give the same one ("a.b" and
        // "a_b"), which ClassDiagram.assign_ids() resolves
        public string get_base_id() {
            // Create valid identifier from name
            var sb = new StringBuilder();
            foreach (char c in name.to_utf8()) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_' || (uchar) c >= 0x80) {  // UTF-8 bytes are valid in DOT ids
                    sb.append_c(c);
                } else {
                    sb.append_c('_');
                }
            }
            string result = sb.str;
            if (result.length == 0 || (result[0] >= '0' && result[0] <= '9')) {
                return "c_" + result;
            }
            // DOT keywords can't be node ids: an alias "node" is a default-attribute statement
            return RenderUtils.sanitize_id(result);
        }
    }

    public class ClassRelationship : Object {
        public UmlClass from { get; set; }
        public UmlClass to { get; set; }
        public RelationshipType relationship_type { get; set; }
        public string? label { get; set; }
        public string? from_cardinality { get; set; }
        public string? to_cardinality { get; set; }
        public bool horizontal { get; set; default = false; }  // single-dash arrow: side by side
        public bool text_reversed { get; set; default = false; } // written target-first ("A <|-- B")
        public string? end_marker { get; set; default = null; }   // aggregation marker as written ("+", "#", ...)
        // Explicit Graphviz end shapes at `from` (tail) and `to` (head): crow's-foot (IE) ends
        // ("}o--||": crowodot / teetee), or both ends of a two-marker arrow ("*-->")
        public string? ie_tail { get; set; default = null; }
        public string? ie_head { get; set; default = null; }
        // Arrow direction word ("-up->"): where `to` is placed relative to `from`
        public string placement { get; set; default = ""; }
        public string? line_style { get; set; default = null; }  // [hidden] / [dashed] / [dotted] / [bold]
        public string? line_color { get; set; default = null; }  // [#red]
        public string? text_color { get; set; default = null; }  // "#text:red" after the target
        public int thickness { get; set; default = 0; }          // [thickness=4]
        // "(A, B) .. C": association classes hung from a point on this link; `side` when the
        // line was written with one character ("." / "-": beside the point, not below it)
        public Gee.ArrayList<UmlClass> association_classes = new Gee.ArrayList<UmlClass>();
        public Gee.ArrayList<bool> association_side = new Gee.ArrayList<bool>();
        public Gee.ArrayList<bool> association_dashed = new Gee.ArrayList<bool>();
        // True for undirected lines (-- and ..) — no arrowhead rendered
        public bool undirected { get; set; default = false; }

        public ClassRelationship(UmlClass from, UmlClass to, RelationshipType type) {
            this.from = from;
            this.to = to;
            this.relationship_type = type;
            this.label = null;
            this.from_cardinality = null;
            this.to_cardinality = null;
        }
    }

    // A line between a floating note and a class ("N1 .. A")
    public class ClassNoteLink : Object {
        public string target;     // class key
        public bool dashed;
        public bool note_first;   // written "N1 .. A": the note ranks above the class

        public ClassNoteLink(string target, bool dashed, bool note_first) {
            this.target = target;
            this.dashed = dashed;
            this.note_first = note_first;
        }
    }

    public class ClassNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
        public string? alias;  // note "text" as N1
        public string? color;  // "note left of Foo #pink"
        public unowned ClassRelationship? on_link;  // "note on link": the relationship before it
        public Gee.ArrayList<ClassNoteLink> links = new Gee.ArrayList<ClassNoteLink>();
        public string position { get; set; }
        public int source_line { get; set; }

        private static int note_counter = 0;

        public ClassNote(string text, int line = 0) {
            this.id = "_class_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
            this.source_line = line;
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    // package / namespace: a named group of classes, drawn as a box around them
    public class ClassPackage : Object {
        public string name { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<ClassPackage> children { get; private set; }
        public Gee.ArrayList<UmlClass> classes { get; private set; }
        public unowned ClassPackage? parent;
        public bool is_namespace;  // "namespace X": bare class names inside mean X.Name
        public string? label;      // last name segment for nested dotted packages ("b" of "a.b")
        public string? alias;      // package "Long Name" as LN
        public string? style;      // <<Node>> <<Folder>> <<Frame>> <<Cloud>> <<Database>> <<Rectangle>>

        public ClassPackage(string name, int line = 0) {
            this.name = name;
            this.color = null;
            this.source_line = line;
            this.children = new Gee.ArrayList<ClassPackage>();
            this.classes = new Gee.ArrayList<UmlClass>();
        }
    }

    // A relationship with a package at one or both ends, drawn cluster to cluster.
    // Before, the package name was taken as a class and a stray box appeared.
    public class ClassPackageLink : Object {
        public UmlClass? from_class;
        public ClassPackage? from_package;
        public UmlClass? to_class;
        public ClassPackage? to_package;
        public RelationshipType relationship_type;
        public bool undirected;
        public string? label;
        public string? end_marker;

        public ClassPackageLink(RelationshipType type) {
            this.relationship_type = type;
            this.undirected = false;
            this.label = null;
        }
    }

    public class ClassDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<UmlClass> classes { get; private set; }
        public Gee.ArrayList<ClassRelationship> relationships { get; private set; }
        public Gee.ArrayList<ClassNote> notes { get; private set; }
        public Gee.ArrayList<ClassPackage> packages { get; private set; }  // top-level packages
        public bool left_to_right { get; set; default = false; }
        public Gee.ArrayList<ClassPackageLink> package_links { get; private set; }
        // "together { ... }" groups, kept next to each other in the layout
        public Gee.ArrayList<Gee.ArrayList<UmlClass>> together_groups { get; private set; }
        public SkinParams skin_params { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }
        // "legend ... endlegend" (DiagramLegend is declared in ComponentDiagram.vala)
        public DiagramLegend? legend { get; set; }

        public ClassDiagram() {
            this.diagram_type = DiagramType.CLASS;
            this.classes = new Gee.ArrayList<UmlClass>();
            this.relationships = new Gee.ArrayList<ClassRelationship>();
            this.notes = new Gee.ArrayList<ClassNote>();
            this.packages = new Gee.ArrayList<ClassPackage>();
            this.package_links = new Gee.ArrayList<ClassPackageLink>();
            this.together_groups = new Gee.ArrayList<Gee.ArrayList<UmlClass>>();
            this.skin_params = new SkinParams();
            this.errors = new Gee.ArrayList<ParseError>();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counters for new diagram
            ClassNote.reset_counter();
        }

        // Gives every class a unique DOT id. Ids come from the name with other characters
        // replaced, so "a.b" and "a_b", or "node" (a DOT keyword, made "node_") and "node_",
        // were one node and the link between them a self-loop.
        public void assign_ids() {
            var used = new Gee.HashSet<string>();
            foreach (var c in classes) {
                c.dot_id = null;
            }
            foreach (var c in classes) {
                string base_id = c.get_base_id();
                // The renderer's own nodes (notes, package anchors, link notes) keep their ids
                if (base_id.has_prefix("_class_note_") || base_id.has_prefix("_pkg")) {
                    base_id = "c" + base_id;
                }
                string id = base_id;
                int n = 2;
                while (used.contains(id)) {
                    id = "%s_%d".printf(base_id, n++);
                }
                used.add(id);
                c.dot_id = id;
            }
        }

        public ClassPackage? find_package(string name) {
            return find_package_in(packages, name);
        }

        private ClassPackage? find_package_in(Gee.ArrayList<ClassPackage> list, string name) {
            foreach (var pkg in list) {
                if (pkg.name == name || pkg.alias == name) {
                    return pkg;
                }
                var nested = find_package_in(pkg.children, name);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        public UmlClass? find_class(string name) {
            foreach (var c in classes) {
                if (c.name == name) {
                    return c;
                }
            }
            return null;
        }

        public UmlClass get_or_create_class(string name, int line = 0) {
            var existing = find_class(name);
            if (existing != null) {
                // Update line if not set and we have a valid line
                if (existing.source_line == 0 && line > 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var uml_class = new UmlClass(name, ClassType.CLASS, line);
            classes.add(uml_class);
            return uml_class;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }
}
