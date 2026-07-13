namespace GDiagram {
    public enum ComponentType {
        COMPONENT,    // [Name] or component keyword
        INTERFACE,    // () Name or interface keyword
        DATABASE,     // database keyword
        CLOUD,        // cloud keyword
        PACKAGE,      // package keyword
        FOLDER,       // folder keyword
        FRAME,        // frame keyword
        NODE,         // node keyword
        ARTIFACT,     // artifact keyword
        STORAGE,      // storage keyword
        CARD,         // card keyword
        AGENT,        // agent keyword
        RECTANGLE,    // rectangle keyword
        QUEUE,        // queue keyword
        STACK,        // stack keyword
        FILE,         // file keyword
        BOUNDARY,     // boundary keyword
        CONTROL,      // control keyword
        ENTITY,       // entity keyword
        ACTOR,        // actor keyword or :Name: (description diagrams)
        USECASE,      // usecase keyword or (Name)
        PERSON,       // person keyword
        ACTION,       // action keyword
        PROCESS,      // process keyword
        CIRCLE,       // circle keyword
        HEXAGON,      // hexagon keyword
        LABEL,        // label keyword
        COLLECTIONS,  // collections keyword
        JSON          // json keyword (allowmixing): a JSON document drawn as a table
    }

    public enum PortType {
        IN,           // portin - required interface
        OUT,          // portout - provided interface
        BIDIRECTIONAL // port - both directions
    }

    public class ComponentPort : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public PortType port_type { get; set; }
        public string? parent_component { get; set; }

        private static int port_counter = 0;

        public ComponentPort(string? id, PortType type = PortType.BIDIRECTIONAL) {
            this.id = id ?? "_port_%d".printf(port_counter++);
            this.port_type = type;
            this.label = null;
            this.parent_component = null;
        }

        public static void reset_counter() {
            port_counter = 0;
        }
    }

    public class Component : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public string? alias { get; set; }
        public ComponentType component_type { get; set; }
        public string? stereotype { get; set; }
        public string? color { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<Component> children { get; private set; }
        public bool is_container { get; set; default = false; }
        // Named only by a link inside a container body ("node N { A --> B }"), never declared
        public bool link_end { get; set; default = false; }
        // Every <<stereotype>> written, in order ("<<system_boundary>><<boundary>>");
        // `stereotype` is the first
        public Gee.ArrayList<string> stereotypes { get; private set; default = new Gee.ArrayList<string>(); }
        // Inline style after the colour: "#pink;line:red;line.dotted;text:blue"
        public string? line_color { get; set; default = null; }
        public string? line_style { get; set; default = null; }   // dashed, dotted, bold
        public string? text_color { get; set; default = null; }
        // "json J { ... }": the JSON text of the body
        public string? json_text { get; set; default = null; }
        // "actor/", "usecase/": business variants
        public bool business { get; set; default = false; }

        public bool has_stereotype(string name) {
            if (stereotype == name) {
                return true;
            }
            foreach (string s in stereotypes) {
                if (s == name) {
                    return true;
                }
            }
            return false;
        }

        public Component(string id, ComponentType type = ComponentType.COMPONENT, int line = 0) {
            this.id = id;
            this.component_type = type;
            this.label = null;
            this.alias = null;
            this.stereotype = null;
            this.color = null;
            this.source_line = line;
            this.children = new Gee.ArrayList<Component>();
        }

        public string get_display_label() {
            if (label != null && label.length > 0) {
                return label;
            }
            if (alias != null && alias.length > 0) {
                return alias;
            }
            return id;
        }

        public string get_identifier() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
            return id;
        }
    }

    public class ComponentInterface : Object {
        public string id { get; set; }
        public string? label { get; set; }
        public string? alias { get; set; }
        public string? stereotype { get; set; }

        public ComponentInterface(string id) {
            this.id = id;
            this.label = null;
            this.alias = null;
            this.stereotype = null;
        }

        public string get_display_label() {
            if (label != null && label.length > 0) {
                return label;
            }
            return id;
        }

        public string get_identifier() {
            if (alias != null && alias.length > 0) {
                return alias;
            }
            return id;
        }
    }

    public enum ComponentRelationType {
        DEPENDENCY,      // -->
        ASSOCIATION,     // --
        REALIZATION,     // ..>
        USE,             // ..
        AGGREGATION,     // o--
        COMPOSITION      // *--
    }

    public class ComponentRelationship : Object {
        public string from_id { get; set; }
        public string to_id { get; set; }
        public ComponentRelationType relation_type { get; set; }
        public string? label { get; set; }
        public string? color { get; set; }
        public bool is_dashed { get; set; default = false; }
        public bool left_arrow { get; set; default = false; }
        public bool right_arrow { get; set; default = true; }
        // Description-diagram arrow details ("-le(0)->", "#~~(", "*-0)-+")
        public string placement { get; set; default = ""; }          // up/down/left/right
        public string? line_style { get; set; default = null; }      // dotted (~), bold (=), invis
        public string? tail_marker { get; set; default = null; }     // Graphviz arrow shapes
        public string? head_marker { get; set; default = null; }
        public bool mid_ball { get; set; default = false; }          // "0" on the line
        public bool mid_left_socket { get; set; default = false; }   // "(" before the ball
        public bool mid_right_socket { get; set; default = false; }  // ")" after the ball
        public bool decorated { get; set; default = false; }         // needs the detailed renderer path
        // "+" circle-plus ends: drawn as odot, the plus is added in the SVG step
        public bool plus_tail { get; set; default = false; }
        public bool plus_head { get; set; default = false; }
        // "--*" / "--o": the diamond was written on the target end
        public bool marker_at_head { get; set; default = false; }
        // Multiplicities at the ends: C "1" --> "many" D
        public string? tail_label { get; set; default = null; }
        public string? head_label { get; set; default = null; }
        // "-[thickness=8]->", "#line:red;line.bold": pen width (0 = default)
        public int thickness { get; set; default = 0; }
        // "-[#blue;#green]->": every colour; `color` is the first
        public Gee.ArrayList<string> colors { get; private set; default = new Gee.ArrayList<string>(); }
        // "#...;text:red": the label colour
        public string? text_color { get; set; default = null; }
        // "a --> b <<async>> : x": styled by "skinparam arrow<<async>> { ... }"
        public Gee.ArrayList<string> stereotypes { get; private set; default = new Gee.ArrayList<string>(); }

        public ComponentRelationship(string from, string to, ComponentRelationType type = ComponentRelationType.DEPENDENCY) {
            this.from_id = from;
            this.to_id = to;
            this.relation_type = type;
            this.label = null;
            this.color = null;
        }
    }

    public class ComponentNote : Object {
        public string id { get; set; }
        public string text { get; set; }
        public string? attached_to { get; set; }
        public string position { get; set; }
        public string? color { get; set; }  // inline "#color" after the note position

        private static int note_counter = 0;

        public ComponentNote(string text) {
            this.id = "_component_note_%d".printf(note_counter++);
            this.text = text;
            this.attached_to = null;
            this.position = "right";
            this.color = null;
        }

        public static void reset_counter() {
            note_counter = 0;
        }
    }

    // "legend [top|bottom] [left|right|center] ... endlegend" in component and class
    // diagrams. The text keeps its lines and creole ("|= a | b |" tables, "<#color>" cells).
    public class DiagramLegend : Object {
        public string text { get; set; }
        public string halign { get; set; default = "center"; }  // left, right, center
        public string valign { get; set; default = "bottom"; }  // top, bottom

        public DiagramLegend(string text) {
            this.text = text;
        }
    }

    /**
     * "sprite $name [WxH/16] { rows }", "[WxH/8]", "[WxH/4]" and the compressed "[WxH/16z] data"
     * forms: a grey-level image PlantUML draws in the text colour where a label says "<$name>".
     * Level 0 is see-through, the top level the full text colour.
     */
    public class PlantUmlSprite : Object {
        public string name { get; private set; }
        public int width { get; private set; }
        public int height { get; private set; }
        // Ink per pixel, row by row: 0 (see-through) .. 255 (the text colour)
        public uint8[] ink;

        private PlantUmlSprite(string name, int width, int height) {
            this.name = name;
            this.width = width;
            this.height = height;
            this.ink = new uint8[width * height];
        }

        // PlantUML's 6-bit text alphabet: 0-9 A-Z a-z - _
        public static int decode6bit(char c) {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
            if (c >= 'a' && c <= 'z') return c - 'a' + 36;
            if (c == '-') return 62;
            if (c == '_') return 63;
            return -1;
        }

        /**
         * `spec` is the text between the brackets ("48x48/16", "16x16/8z") or null for a block
         * without one (hex rows, size from the rows). `rows` are the block's lines, or the one
         * data line of a compressed sprite. Null when the data doesn't decode.
         */
        public static PlantUmlSprite? decode(string name, string? spec, Gee.List<string> rows) {
            int w = 0, h = 0, levels = 16;
            bool compressed = false;
            if (spec != null) {
                string s = spec.replace(" ", "").down();
                int slash = s.index_of("/");
                string size = slash >= 0 ? s.substring(0, slash) : s;
                string depth = slash >= 0 ? s.substring(slash + 1) : "16";
                if (depth.has_suffix("z")) {
                    compressed = true;
                    depth = depth.substring(0, depth.length - 1);
                }
                levels = int.parse(depth);
                string[] wh = size.split("x");
                if (wh.length == 2) {
                    w = int.parse(wh[0]);
                    h = int.parse(wh[1]);
                }
            }
            if (levels != 4 && levels != 8 && levels != 16) {
                return null;
            }
            var lines = new Gee.ArrayList<string>();
            foreach (string r in rows) {
                string t = r.strip();
                if (t.length > 0) {
                    lines.add(t);
                }
            }
            if (lines.size == 0) {
                return null;
            }
            if (compressed) {
                var data = new StringBuilder();
                foreach (string l in lines) {
                    data.append(l);
                }
                return decode_compressed(name, w, h, levels, data.str);
            }
            // Pixels per character down a column: 1 hex digit, 2 of 3 bits, 3 of 2 bits
            int per_char = levels == 16 ? 1 : (levels == 8 ? 2 : 3);
            if (w <= 0 || h <= 0) {
                w = lines[0].length;
                h = lines.size * per_char;
            }
            if (w <= 0 || h <= 0 || w > 4096 || h > 4096) {
                return null;
            }
            var sprite = new PlantUmlSprite(name, w, h);
            for (int line = 0; line < lines.size; line++) {
                string text = lines[line];
                for (int x = 0; x < w && x < text.length; x++) {
                    int v;
                    if (levels == 16) {
                        v = text[x].xdigit_value();
                        if (v < 0) continue;
                        sprite.set_level(x, line, v, 15);
                    } else if (levels == 8) {
                        v = decode6bit(text[x]);
                        if (v < 0) continue;
                        sprite.set_level(x, line * 2, v >> 3, 7);
                        sprite.set_level(x, line * 2 + 1, v & 7, 7);
                    } else {
                        v = decode6bit(text[x]);
                        if (v < 0) continue;
                        sprite.set_level(x, line * 3, v >> 4, 3);
                        sprite.set_level(x, line * 3 + 1, (v >> 2) & 3, 3);
                        sprite.set_level(x, line * 3 + 2, v & 3, 3);
                    }
                }
            }
            return sprite;
        }

        private void set_level(int x, int y, int level, int max) {
            if (x < 0 || y < 0 || x >= width || y >= height) {
                return;
            }
            ink[y * width + x] = (uint8) (int.min(level, max) * 255 / max);
        }

        // "/16z": the 6-bit text decodes to raw-deflated bytes, one grey level per pixel
        private static PlantUmlSprite? decode_compressed(string name, int w, int h, int levels, string data) {
            if (w <= 0 || h <= 0 || w > 4096 || h > 4096) {
                return null;
            }
            var bytes = new ByteArray();
            for (int i = 0; i + 1 < data.length; i += 4) {
                int[] c = { 0, 0, 0, 0 };
                for (int k = 0; k < 4; k++) {
                    int v = i + k < data.length ? decode6bit(data[i + k]) : 0;
                    if (v < 0) {
                        return null;
                    }
                    c[k] = v;
                }
                uint8[] three = { (uint8) (((c[0] << 2) | (c[1] >> 4)) & 0xFF),
                                  (uint8) ((((c[1] & 0x0F) << 4) | (c[2] >> 2)) & 0xFF),
                                  (uint8) ((((c[2] & 0x03) << 6) | c[3]) & 0xFF) };
                bytes.append(three);
            }
            var pixels = new ByteArray();
            try {
                var input = new ConverterInputStream(new MemoryInputStream.from_data(bytes.data.copy()),
                                                     new ZlibDecompressor(ZlibCompressorFormat.RAW));
                uint8[] buf = new uint8[4096];
                while (pixels.len < w * h) {
                    ssize_t n = input.read(buf);
                    if (n <= 0) {
                        break;
                    }
                    pixels.append(buf[0:n]);
                }
            } catch (Error e) {
                // Trailing padding after the deflate stream: keep what decoded
            }
            if (pixels.len < w * h) {
                return null;
            }
            var sprite = new PlantUmlSprite(name, w, h);
            for (int i = 0; i < w * h; i++) {
                sprite.set_level(i % w, i / w, pixels.data[i], levels - 1);
            }
            return sprite;
        }
    }

    public class ComponentDiagram : Object {
        public DiagramType diagram_type { get; private set; }
        public Gee.ArrayList<Component> components { get; private set; }
        public Gee.ArrayList<ComponentInterface> interfaces { get; private set; }
        public Gee.ArrayList<ComponentPort> ports { get; private set; }
        public Gee.ArrayList<ComponentRelationship> relationships { get; private set; }
        public Gee.ArrayList<ComponentNote> notes { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public SkinParams skin_params { get; set; }

        // Title/header/footer
        public string? title { get; set; }
        public string? header { get; set; }
        public string? footer { get; set; }
        public DiagramLegend? legend { get; set; }

        // Direction
        public bool left_to_right { get; set; default = false; }
        // "hide stereotype"
        public bool hide_stereotype { get; set; default = false; }
        // "sprite $name ...": by name without the "$"
        public Gee.HashMap<string, PlantUmlSprite> sprites { get; private set; default = new Gee.HashMap<string, PlantUmlSprite>(); }

        public ComponentDiagram() {
            this.diagram_type = DiagramType.COMPONENT;
            this.components = new Gee.ArrayList<Component>();
            this.interfaces = new Gee.ArrayList<ComponentInterface>();
            this.ports = new Gee.ArrayList<ComponentPort>();
            this.relationships = new Gee.ArrayList<ComponentRelationship>();
            this.notes = new Gee.ArrayList<ComponentNote>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.skin_params = new SkinParams();

            // Reset counters for new diagram
            ComponentNote.reset_counter();
            ComponentPort.reset_counter();
        }

        public bool has_errors() {
            return errors.size > 0;
        }

        public Component? find_component(string id) {
            foreach (var comp in components) {
                if (comp.id == id || comp.alias == id) {
                    return comp;
                }
                // Check children
                var nested = find_nested_component(comp, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        private Component? find_nested_component(Component parent, string id) {
            foreach (var comp in parent.children) {
                if (comp.id == id || comp.alias == id) {
                    return comp;
                }
                var nested = find_nested_component(comp, id);
                if (nested != null) {
                    return nested;
                }
            }
            return null;
        }

        public ComponentInterface? find_interface(string id) {
            foreach (var iface in interfaces) {
                if (iface.id == id || iface.alias == id) {
                    return iface;
                }
            }
            return null;
        }

        public Component get_or_create_component(string id, ComponentType type = ComponentType.COMPONENT, int line = 0) {
            var existing = find_component(id);
            if (existing != null) {
                // Update line if this is a better definition
                if (line > 0 && existing.source_line == 0) {
                    existing.source_line = line;
                }
                return existing;
            }
            var comp = new Component(id, type, line);
            components.add(comp);
            return comp;
        }
    }
}
