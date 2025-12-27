namespace GDiagram {
    public enum UseCaseRelationType {
        ASSOCIATION,      // --> or --
        INCLUDE,          // <<include>>
        EXTEND,           // <<extend>>
        GENERALIZATION    // --|>
    }

    public class UseCaseActor : Object {
        public string name { get; set; }
        public string? alias { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }

        public UseCaseActor(string name, int line = 0) {
            this.name = name;
            this.alias = null;
            this.stereotype = null;
            this.color = null;
            this.source_line = line;
        }

        public string get_id() {
            return alias ?? name;
        }
    }

    public class UseCase : Object {
        public string name { get; set; }
        public string? alias { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        public string? container { get; set; }  // Which package/rectangle it belongs to
        public int source_line { get; set; }

        public UseCase(string name, int line = 0) {
            this.name = name;
            this.alias = null;
            this.stereotype = null;
            this.color = null;
            this.container = null;
            this.source_line = line;
        }

        public string get_id() {
            return alias ?? name;
        }
    }

    public enum UseCaseContainerType {
        PACKAGE,     // package "Name" { }
        RECTANGLE,   // rectangle "Name" { } - system boundary
        COMPONENT,   // component "Name" { }
        FOLDER       // folder "Name" { }
    }

    public class UseCasePackage : Object {
        public string name { get; set; }
        public string? alias { get; set; }
        public UseCaseContainerType container_type { get; set; }
        public Gee.ArrayList<UseCase> use_cases { get; private set; }
        public Gee.ArrayList<UseCaseActor> actors { get; private set; }

        public UseCasePackage(string name, UseCaseContainerType type = UseCaseContainerType.PACKAGE) {
            this.name = name;
            this.alias = null;
            this.container_type = type;
            this.use_cases = new Gee.ArrayList<UseCase>();
            this.actors = new Gee.ArrayList<UseCaseActor>();
        }
    }

    public class UseCaseNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }  // Actor or UseCase ID this note is attached to
        public string position { get; set; }       // left, right, top, bottom

        private static int note_counter = 0;

        public UseCaseNote(string text) {
            this.id = "_uc_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public class UseCaseRelationship : Object {
        public string from_id { get; set; }
        public string to_id { get; set; }
        public UseCaseRelationType relation_type { get; set; }
        public string? label { get; set; }
        public bool is_dashed { get; set; }

        public UseCaseRelationship(string from_id, string to_id, UseCaseRelationType type) {
            this.from_id = from_id;
            this.to_id = to_id;
            this.relation_type = type;
            this.label = null;
            this.is_dashed = false;
        }
    }

    public class UseCaseDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<UseCaseActor> actors { get; private set; }
        public Gee.ArrayList<UseCase> use_cases { get; private set; }
        public Gee.ArrayList<UseCasePackage> packages { get; private set; }
        public Gee.ArrayList<UseCaseRelationship> relationships { get; private set; }
        public Gee.ArrayList<UseCaseNote> notes { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Diagram layout direction
        public bool left_to_right { get; set; default = false; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        public UseCaseDiagram() {
            this.diagram_type = DiagramType.USECASE;
            this.actors = new Gee.ArrayList<UseCaseActor>();
            this.use_cases = new Gee.ArrayList<UseCase>();
            this.packages = new Gee.ArrayList<UseCasePackage>();
            this.relationships = new Gee.ArrayList<UseCaseRelationship>();
            this.notes = new Gee.ArrayList<UseCaseNote>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();

            // Reset counters
            UseCaseNote.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public UseCaseActor? find_actor(string name) {
            foreach (var actor in actors) {
                if (actor.name == name || actor.alias == name) {
                    return actor;
                }
            }
            // Check in packages
            foreach (var pkg in packages) {
                foreach (var actor in pkg.actors) {
                    if (actor.name == name || actor.alias == name) {
                        return actor;
                    }
                }
            }
            return null;
        }

        public UseCase? find_usecase(string name) {
            foreach (var uc in use_cases) {
                if (uc.name == name || uc.alias == name) {
                    return uc;
                }
            }
            // Check in packages
            foreach (var pkg in packages) {
                foreach (var uc in pkg.use_cases) {
                    if (uc.name == name || uc.alias == name) {
                        return uc;
                    }
                }
            }
            return null;
        }

        public UseCaseActor get_or_create_actor(string name) {
            var existing = find_actor(name);
            if (existing != null) {
                return existing;
            }
            var actor = new UseCaseActor(name);
            actors.add(actor);
            return actor;
        }

        public UseCase get_or_create_usecase(string name) {
            var existing = find_usecase(name);
            if (existing != null) {
                return existing;
            }
            var uc = new UseCase(name);
            use_cases.add(uc);
            return uc;
        }

        // Check if a name refers to an actor or use case
        public bool is_actor(string name) {
            return find_actor(name) != null;
        }

        public bool is_usecase(string name) {
            return find_usecase(name) != null;
        }
    }
}
