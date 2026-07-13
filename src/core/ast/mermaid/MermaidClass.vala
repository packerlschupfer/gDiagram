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
        REALIZATION       // ..|>
    }

    public class MermaidClassMember : Object {
        public string name { get; set; }
        public string? type_name { get; set; }
        public MermaidVisibility visibility { get; set; }
        public bool is_static { get; set; }
        public bool is_abstract { get; set; }
        public bool is_method { get; set; }

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

        public MermaidRelation(MermaidClass from, MermaidClass to, MermaidRelationType type) {
            this.from = from;
            this.to = to;
            this.relation_type = type;
            this.label = null;
            this.from_cardinality = null;
            this.to_cardinality = null;
        }
    }

    public class MermaidClassDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidClass> classes { get; private set; }
        public Gee.ArrayList<MermaidRelation> relations { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }

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

}
