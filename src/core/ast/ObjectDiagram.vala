namespace GDiagram {
    public class ObjectField : Object {
        public string name { get; set; }
        public string value { get; set; }
        // The line as written ("name = \"Dummy\""), which PlantUML shows verbatim
        public string? text;

        public ObjectField(string name, string value) {
            this.name = name;
            this.value = value;
        }

        public string get_display_text() {
            if (text != null) {
                return text;
            }
            return value.length > 0 ? "%s = %s".printf(name, value) : name;
        }
    }

    // One "key => value" row of a map
    public class MapEntry : Object {
        public string key { get; set; }
        public string value { get; set; }
        // "UK *-> London": the row holds a link and spans both columns
        public bool link_row;

        public MapEntry(string key, string value) {
            this.key = key;
            this.value = value;
        }
    }

    // package / namespace block holding objects and maps
    public class ObjectPackage : Object {
        public string name { get; set; }
        public string? color { get; set; }
        public string? label;  // last name segment for nested dotted packages
        public unowned ObjectPackage? parent;
        public Gee.ArrayList<ObjectPackage> children { get; private set; }
        public Gee.ArrayList<ObjectInstance> objects { get; private set; }

        public ObjectPackage(string name) {
            this.name = name;
            this.color = null;
            this.children = new Gee.ArrayList<ObjectPackage>();
            this.objects = new Gee.ArrayList<ObjectInstance>();
        }
    }

    public class ObjectInstance : Object {
        public string name { get; set; }
        public string? class_name { get; set; }
        public string? alias { get; set; }
        public string? color { get; set; }
        public string? stereotype { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<ObjectField> fields { get; private set; }
        public bool is_map;                               // "map Name { key => value }"
        public bool is_diamond;                           // "diamond dia": a junction
        public bool is_class;                             // "class Name" beside objects
        public JsonNode? json_root;                       // "json Name { ... }"
        public Gee.ArrayList<MapEntry> entries { get; private set; }
        public unowned ObjectPackage? owner_package;

        public ObjectInstance(string name, int line = 0) {
            this.name = name;
            this.class_name = null;
            this.alias = null;
            this.color = null;
            this.stereotype = null;
            this.source_line = line;
            this.fields = new Gee.ArrayList<ObjectField>();
            this.entries = new Gee.ArrayList<MapEntry>();
        }

        public string get_id() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
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
                return "obj_" + result;
            }
            return result;
        }

        public string get_display_label() {
            if (class_name != null && class_name.length > 0) {
                return "%s : %s".printf(name, class_name);
            }
            return name;
        }
    }

    public enum ObjectLinkType {
        ASSOCIATION,      // -->
        DEPENDENCY,       // ..>
        AGGREGATION,      // o--
        COMPOSITION,      // *--
        INHERITANCE       // <|--
    }

    public class ObjectLink : Object {
        public string from_id { get; set; }
        public string to_id { get; set; }
        public ObjectLinkType link_type { get; set; }
        public string? label { get; set; }
        public string? from_cardinality { get; set; }
        public string? to_cardinality { get; set; }
        public bool is_dashed { get; set; default = false; }
        public string? from_row { get; set; default = null; }   // map key ("Map::key")
        public string? to_row { get; set; default = null; }
        public bool undirected { get; set; default = false; }   // "--" / ".."
        public bool has_head { get; set; default = true; }      // arrow ends in > or |>
        public bool text_reversed { get; set; default = false; } // written target-first ("A <|-- B")
        public string? end_marker { get; set; default = null; }   // aggregation marker as written
        public bool has_tail_head { get; set; default = false; } // "<-->" heads at both ends
        public string? line_color { get; set; default = null; }  // "-[#red]->"
        public string? line_style { get; set; default = null; }  // "-[dashed]->": dashed/dotted/bold/invis

        public ObjectLink(string from_id, string to_id, ObjectLinkType type = ObjectLinkType.ASSOCIATION) {
            this.from_id = from_id;
            this.to_id = to_id;
            this.link_type = type;
            this.label = null;
            this.from_cardinality = null;
            this.to_cardinality = null;
        }
    }

    public class ObjectNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
        // "note "text" as N1": the name links use. The id stays generated: the alias as a
        // DOT id broke export for "as edge", "as \"my note\"" or an object of the same name.
        public string? alias;
        public string position { get; set; }
        public int source_line { get; set; }

        private static int note_counter = 0;

        public ObjectNote(string text, int line = 0) {
            this.id = "_obj_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
            this.source_line = line;
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    public class ObjectDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<ObjectInstance> objects { get; private set; }
        public Gee.ArrayList<ObjectLink> links { get; private set; }
        public Gee.ArrayList<ObjectNote> notes { get; private set; }
        public DiagramLegend? legend { get; set; default = null; }
        public Gee.ArrayList<ObjectPackage> packages { get; private set; }  // top-level packages
        public bool left_to_right { get; set; default = false; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }

        public ObjectDiagram() {
            this.diagram_type = DiagramType.OBJECT;
            this.objects = new Gee.ArrayList<ObjectInstance>();
            this.links = new Gee.ArrayList<ObjectLink>();
            this.notes = new Gee.ArrayList<ObjectNote>();
            this.packages = new Gee.ArrayList<ObjectPackage>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();
            this.title = null;
            this.header = null;
            this.footer = null;

            // Reset counters
            ObjectNote.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public ObjectPackage? find_package(string name) {
            return find_package_in(packages, name);
        }

        private ObjectPackage? find_package_in(Gee.ArrayList<ObjectPackage> list, string name) {
            foreach (var pkg in list) {
                if (pkg.name == name) {
                    return pkg;
                }
                var nested = find_package_in(pkg.children, name);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        public ObjectInstance? find_object(string name) {
            foreach (var obj in objects) {
                if (obj.name == name || obj.alias == name) {
                    return obj;
                }
            }
            return null;
        }

        public ObjectInstance get_or_create_object(string name, int line = 0) {
            var existing = find_object(name);
            if (existing != null) {
                if (line > 0 && existing.source_line == 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var obj = new ObjectInstance(name, line);
            objects.add(obj);
            return obj;
        }
    }
}
