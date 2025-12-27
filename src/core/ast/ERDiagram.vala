namespace GDiagram {
    public enum ERCardinality {
        ONE_TO_ONE,        // ||--||
        ONE_TO_MANY,       // ||--o{
        MANY_TO_ONE,       // }o--||
        MANY_TO_MANY,      // }o--o{
        ZERO_OR_ONE,       // |o--
        ZERO_OR_MANY,      // }o--
        ONE_MANDATORY,     // ||--
        MANY_MANDATORY     // }|--
    }

    public enum ERAttributeType {
        NORMAL,
        PRIMARY_KEY,
        FOREIGN_KEY
    }

    public class ERAttribute : Object {
        public string name { get; set; }
        public string? data_type { get; set; }
        public ERAttributeType attr_type { get; set; default = ERAttributeType.NORMAL; }
        public bool is_not_null { get; set; default = false; }
        public string? comment { get; set; }
        public int source_line { get; set; }

        public ERAttribute(string name, string? data_type = null, int line = 0) {
            this.name = name;
            this.data_type = data_type;
            this.comment = null;
            this.source_line = line;
        }

        public string get_display_text() {
            var sb = new StringBuilder();

            // Add key markers
            if (attr_type == ERAttributeType.PRIMARY_KEY) {
                sb.append("* ");
            } else if (attr_type == ERAttributeType.FOREIGN_KEY) {
                sb.append("# ");
            }

            sb.append(name);

            if (data_type != null && data_type.length > 0) {
                sb.append(" : ");
                sb.append(data_type);
            }

            return sb.str;
        }
    }

    public class EREntity : Object {
        public string name { get; set; }
        public string? alias { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<ERAttribute> attributes { get; private set; }
        public bool has_separator { get; set; default = false; }

        public EREntity(string name, int line = 0) {
            this.name = name;
            this.alias = null;
            this.color = null;
            this.source_line = line;
            this.attributes = new Gee.ArrayList<ERAttribute>();
        }

        public string get_dot_id() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
            // Sanitize name for DOT
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
                return "entity_" + result;
            }
            return result;
        }

        public string get_display_name() {
            return name;
        }
    }

    public class ERRelationship : Object {
        public string from_entity { get; set; }
        public string to_entity { get; set; }
        public ERCardinality from_cardinality { get; set; }
        public ERCardinality to_cardinality { get; set; }
        public string? label { get; set; }
        public bool is_identifying { get; set; default = false; }
        public bool is_dashed { get; set; default = false; }
        public int source_line { get; set; }

        public ERRelationship(string from, string to, int line = 0) {
            this.from_entity = from;
            this.to_entity = to;
            this.from_cardinality = ERCardinality.ONE_MANDATORY;
            this.to_cardinality = ERCardinality.MANY_MANDATORY;
            this.label = null;
            this.source_line = line;
        }

        public string get_from_decoration() {
            return cardinality_to_string(from_cardinality);
        }

        public string get_to_decoration() {
            return cardinality_to_string(to_cardinality);
        }

        private string cardinality_to_string(ERCardinality card) {
            switch (card) {
                case ERCardinality.ONE_TO_ONE:
                    return "||";
                case ERCardinality.ONE_TO_MANY:
                    return "}o";
                case ERCardinality.MANY_TO_ONE:
                    return "o{";
                case ERCardinality.MANY_TO_MANY:
                    return "}o";
                case ERCardinality.ZERO_OR_ONE:
                    return "|o";
                case ERCardinality.ZERO_OR_MANY:
                    return "o{";
                case ERCardinality.ONE_MANDATORY:
                    return "||";
                case ERCardinality.MANY_MANDATORY:
                    return "}|";
                default:
                    return "--";
            }
        }
    }

    public class ERNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
        public string position { get; set; }
        public int source_line { get; set; }

        private static int note_counter = 0;

        public ERNote(string text, int line = 0) {
            this.id = "_er_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
            this.source_line = line;
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public class ERDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<EREntity> entities { get; private set; }
        public Gee.ArrayList<ERRelationship> relationships { get; private set; }
        public Gee.ArrayList<ERNote> notes { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        // Direction
        public bool left_to_right { get; set; default = false; }

        public ERDiagram() {
            this.diagram_type = DiagramType.ER_DIAGRAM;
            this.entities = new Gee.ArrayList<EREntity>();
            this.relationships = new Gee.ArrayList<ERRelationship>();
            this.notes = new Gee.ArrayList<ERNote>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counters
            ERNote.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public EREntity? find_entity(string id) {
            foreach (var entity in entities) {
                if (entity.name == id || entity.alias == id) {
                    return entity;
                }
            }
            return null;
        }

        public EREntity get_or_create_entity(string name, int line = 0) {
            var existing = find_entity(name);
            if (existing != null) {
                if (line > 0 && existing.source_line == 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var entity = new EREntity(name, line);
            entities.add(entity);
            return entity;
        }
    }
}
