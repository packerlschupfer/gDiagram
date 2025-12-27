namespace GDiagram {
    public enum ClassType {
        CLASS,
        INTERFACE,
        ABSTRACT,
        ENUM,
        ANNOTATION
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

        public ClassMember(string name, bool is_method = false) {
            this.name = name;
            this.is_method = is_method;
            this.visibility = MemberVisibility.PUBLIC;
            this.is_static = false;
            this.is_abstract = false;
            this.type_name = null;
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
        public ClassType class_type { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<ClassMember> members { get; private set; }

        public UmlClass(string name, ClassType type = ClassType.CLASS, int line = 0) {
            this.name = name;
            this.class_type = type;
            this.stereotype = null;
            this.color = null;
            this.source_line = line;
            this.members = new Gee.ArrayList<ClassMember>();
        }

        public void add_member(ClassMember member) {
            members.add(member);
        }

        public string get_id() {
            // Create valid identifier from name
            var sb = new StringBuilder();
            foreach (char c in name.to_utf8()) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_') {
                    sb.append_c(c);
                } else {
                    sb.append_c('_');
                }
            }
            string result = sb.str;
            if (result.length == 0 || (result[0] >= '0' && result[0] <= '9')) {
                return "c_" + result;
            }
            return result;
        }
    }

    public class ClassRelationship : Object {
        public UmlClass from { get; set; }
        public UmlClass to { get; set; }
        public RelationshipType relationship_type { get; set; }
        public string? label { get; set; }
        public string? from_cardinality { get; set; }
        public string? to_cardinality { get; set; }

        public ClassRelationship(UmlClass from, UmlClass to, RelationshipType type) {
            this.from = from;
            this.to = to;
            this.relationship_type = type;
            this.label = null;
            this.from_cardinality = null;
            this.to_cardinality = null;
        }
    }

    public class ClassNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
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

    public class ClassDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<UmlClass> classes { get; private set; }
        public Gee.ArrayList<ClassRelationship> relationships { get; private set; }
        public Gee.ArrayList<ClassNote> notes { get; private set; }
        public SkinParams skin_params { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        public ClassDiagram() {
            this.diagram_type = DiagramType.CLASS;
            this.classes = new Gee.ArrayList<UmlClass>();
            this.relationships = new Gee.ArrayList<ClassRelationship>();
            this.notes = new Gee.ArrayList<ClassNote>();
            this.skin_params = new SkinParams();
            this.errors = new Gee.ArrayList<ParseError>();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counters for new diagram
            ClassNote.reset_counter();
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
