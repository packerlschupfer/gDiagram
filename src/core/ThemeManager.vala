namespace GDiagram {
    public enum DiagramTheme {
        LIGHT,
        DARK,
        AUTO
    }

    /**
     * Role-based color palette used by all renderers.
     *
     * Renderers should read colors from a Palette instance instead of
     * hardcoding hex literals. Each slot represents a semantic role, not
     * a diagram type — this keeps the surface small and reusable across
     * C4, class, sequence, ER, etc.
     *
     * Hex codes here always include the `#` prefix. If a renderer needs
     * a bare name like "transparent" it should handle that specially.
     */
    public class Palette : Object {
        // Canvas
        public string background        { get; set; }
        public string grid              { get; set; }

        // Generic node (fall-through for diagram types without a specific role)
        public string node_fill         { get; set; }
        public string node_border       { get; set; }
        public string node_text         { get; set; }

        // Semantic roles used by C4, component, deployment, ER, etc.
        public string person_fill       { get; set; }
        public string person_border     { get; set; }
        public string system_fill       { get; set; }
        public string system_border     { get; set; }
        public string container_fill    { get; set; }
        public string container_border  { get; set; }
        public string component_fill    { get; set; }
        public string component_border  { get; set; }
        public string database_fill     { get; set; }
        public string database_border   { get; set; }
        public string external_fill     { get; set; }
        public string external_border   { get; set; }
        public string boundary_stroke   { get; set; }
        public string on_colored_text   { get; set; }  // text over saturated fills (usually white)

        // Edges and misc
        public string edge_color        { get; set; }
        public string edge_text         { get; set; }
        public string accent_primary    { get; set; }
        public string accent_secondary  { get; set; }
        public string warning           { get; set; }
        public string success           { get; set; }

        public Palette() {
            // Initialize to the default-light preset — subclasses / factories
            // override as needed.
        }

        public Palette clone() {
            var p = new Palette();
            p.background       = background;
            p.grid             = grid;
            p.node_fill        = node_fill;
            p.node_border      = node_border;
            p.node_text        = node_text;
            p.person_fill      = person_fill;
            p.person_border    = person_border;
            p.system_fill      = system_fill;
            p.system_border    = system_border;
            p.container_fill   = container_fill;
            p.container_border = container_border;
            p.component_fill   = component_fill;
            p.component_border = component_border;
            p.database_fill    = database_fill;
            p.database_border  = database_border;
            p.external_fill    = external_fill;
            p.external_border  = external_border;
            p.boundary_stroke  = boundary_stroke;
            p.on_colored_text  = on_colored_text;
            p.edge_color       = edge_color;
            p.edge_text        = edge_text;
            p.accent_primary   = accent_primary;
            p.accent_secondary = accent_secondary;
            p.warning          = warning;
            p.success          = success;
            return p;
        }
    }

    public class ThemeManager : Object {
        private static Gee.HashMap<string, Palette>? presets = null;
        private static Palette? active_palette = null;

        /**
         * List of built-in preset names, in display order. Used by the
         * preferences UI to populate the preset combo box.
         */
        public static string[] preset_names() {
            return {
                "default-light",
                "default-dark",
                "solarized-light",
                "solarized-dark",
                "dracula",
                "nord-light",
                "nord-dark"
            };
        }

        public static string preset_display_name(string id) {
            switch (id) {
                case "default-light":   return "Default Light";
                case "default-dark":    return "Default Dark";
                case "solarized-light": return "Solarized Light";
                case "solarized-dark":  return "Solarized Dark";
                case "dracula":         return "Dracula";
                case "nord-light":      return "Nord Light";
                case "nord-dark":       return "Nord Dark";
                default:                return id;
            }
        }

        public static bool preset_is_dark(string id) {
            return id.contains("dark") || id == "dracula";
        }

        /**
         * Look up a preset by name. Returns a clone (safe to mutate).
         * Unknown names fall back to default-light.
         */
        public static Palette get_preset(string name) {
            ensure_initialized();
            if (presets.has_key(name)) {
                return presets.get(name).clone();
            }
            return presets.get("default-light").clone();
        }

        /**
         * The palette currently used by renderers. Updated via set_active_palette.
         * Never returns null — initializes to default-light on first call.
         */
        public static Palette get_active_palette() {
            if (active_palette == null) {
                active_palette = get_preset("default-light");
            }
            return active_palette;
        }

        public static void set_active_palette(Palette p) {
            active_palette = p;
        }

        public static DiagramTheme get_system_theme() {
            // Headless contexts (CLI export on display-less hosts, LSP):
            // Adw.StyleManager.get_default() reaches gdk_display_manager_get(),
            // which is fatal before gtk_init(). Fall back to LIGHT — the
            // default diagram rendering theme.
            if (!Gtk.is_initialized()) {
                return DiagramTheme.LIGHT;
            }
            var sm = Adw.StyleManager.get_default();
            return sm.dark ? DiagramTheme.DARK : DiagramTheme.LIGHT;
        }

        /**
         * Resolve GSettings into an active Palette. Reads:
         *   color-scheme-follow-system (b)
         *   color-scheme-light (s) — preset id
         *   color-scheme-dark  (s) — preset id
         *   custom-palette-overrides (s) — JSON of {slot: "#hex", ...}
         *
         * When follow-system is true, picks light or dark preset based on the
         * libadwaita system theme. Custom overrides are applied on top.
         * Sets and returns the new active palette.
         */
        public static Palette refresh_from_settings(GLib.Settings settings) {
            // Tolerate old installed schemas that predate these keys. Calling
            // get_boolean/get_string on a missing key aborts the process via
            // g_error() — not catchable — so we must check has_key first.
            var schema = settings.settings_schema;

            bool follow = schema.has_key("color-scheme-follow-system")
                ? settings.get_boolean("color-scheme-follow-system")
                : true;

            string preset_id;
            if (follow) {
                if (get_system_theme() == DiagramTheme.DARK) {
                    preset_id = schema.has_key("color-scheme-dark")
                        ? settings.get_string("color-scheme-dark")
                        : "default-dark";
                } else {
                    preset_id = schema.has_key("color-scheme-light")
                        ? settings.get_string("color-scheme-light")
                        : "default-light";
                }
            } else {
                preset_id = schema.has_key("color-scheme-light")
                    ? settings.get_string("color-scheme-light")
                    : "default-light";
            }

            var p = get_preset(preset_id);

            if (schema.has_key("custom-palette-overrides")) {
                string overrides_json = settings.get_string("custom-palette-overrides");
                if (overrides_json != null && overrides_json.length > 0) {
                    apply_overrides_json(p, overrides_json);
                }
            }

            set_active_palette(p);
            return p;
        }

        /**
         * Apply {"slot":"#hex",...} overrides to a palette in-place.
         * Unknown slots are silently ignored. Malformed JSON is logged.
         */
        private static void apply_overrides_json(Palette p, string json) {
            try {
                var parser = new Json.Parser();
                parser.load_from_data(json);
                var root = parser.get_root();
                if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return;
                var obj = root.get_object();
                obj.foreach_member((_o, name, node) => {
                    if (node.get_node_type() != Json.NodeType.VALUE) return;
                    string val = node.get_string();
                    if (val == null) return;
                    set_slot(p, name, val);
                });
            } catch (Error e) {
                warning("Failed to parse custom-palette-overrides: %s", e.message);
            }
        }

        /**
         * Serialize only the slots that differ from `base_preset` into a JSON
         * object string. Used by the preferences UI to persist user overrides
         * without writing the entire palette.
         */
        public static string overrides_to_json(Palette current, Palette base_preset) {
            var gen = new Json.Generator();
            var root = new Json.Node(Json.NodeType.OBJECT);
            var obj = new Json.Object();
            root.set_object(obj);

            // Check each slot; include if different.
            add_if_different(obj, "background",        current.background,        base_preset.background);
            add_if_different(obj, "grid",              current.grid,              base_preset.grid);
            add_if_different(obj, "node_fill",         current.node_fill,         base_preset.node_fill);
            add_if_different(obj, "node_border",       current.node_border,       base_preset.node_border);
            add_if_different(obj, "node_text",         current.node_text,         base_preset.node_text);
            add_if_different(obj, "person_fill",       current.person_fill,       base_preset.person_fill);
            add_if_different(obj, "person_border",     current.person_border,     base_preset.person_border);
            add_if_different(obj, "system_fill",       current.system_fill,       base_preset.system_fill);
            add_if_different(obj, "system_border",     current.system_border,     base_preset.system_border);
            add_if_different(obj, "container_fill",    current.container_fill,    base_preset.container_fill);
            add_if_different(obj, "container_border",  current.container_border,  base_preset.container_border);
            add_if_different(obj, "component_fill",    current.component_fill,    base_preset.component_fill);
            add_if_different(obj, "component_border",  current.component_border,  base_preset.component_border);
            add_if_different(obj, "database_fill",     current.database_fill,     base_preset.database_fill);
            add_if_different(obj, "database_border",   current.database_border,   base_preset.database_border);
            add_if_different(obj, "external_fill",     current.external_fill,     base_preset.external_fill);
            add_if_different(obj, "external_border",   current.external_border,   base_preset.external_border);
            add_if_different(obj, "boundary_stroke",   current.boundary_stroke,   base_preset.boundary_stroke);
            add_if_different(obj, "on_colored_text",   current.on_colored_text,   base_preset.on_colored_text);
            add_if_different(obj, "edge_color",        current.edge_color,        base_preset.edge_color);
            add_if_different(obj, "edge_text",         current.edge_text,         base_preset.edge_text);
            add_if_different(obj, "accent_primary",    current.accent_primary,    base_preset.accent_primary);
            add_if_different(obj, "accent_secondary",  current.accent_secondary,  base_preset.accent_secondary);
            add_if_different(obj, "warning",           current.warning,           base_preset.warning);
            add_if_different(obj, "success",           current.success,           base_preset.success);

            if (obj.get_size() == 0) return "";
            gen.set_root(root);
            return gen.to_data(null);
        }

        private static void add_if_different(Json.Object obj, string name, string cur, string base_val) {
            if (cur != base_val) obj.set_string_member(name, cur);
        }

        /**
         * Look up every Palette slot by name. Kept in one place so both the
         * overrides loader and the preferences UI can iterate them.
         */
        public static string[] slot_names() {
            return {
                "background", "grid",
                "node_fill", "node_border", "node_text",
                "person_fill", "person_border",
                "system_fill", "system_border",
                "container_fill", "container_border",
                "component_fill", "component_border",
                "database_fill", "database_border",
                "external_fill", "external_border",
                "boundary_stroke", "on_colored_text",
                "edge_color", "edge_text",
                "accent_primary", "accent_secondary",
                "warning", "success"
            };
        }

        public static string slot_display_name(string slot) {
            switch (slot) {
                case "background":       return "Canvas background";
                case "grid":             return "Canvas grid";
                case "node_fill":        return "Generic node fill";
                case "node_border":      return "Generic node border";
                case "node_text":        return "Generic node text";
                case "person_fill":      return "Person fill";
                case "person_border":    return "Person border";
                case "system_fill":      return "System fill";
                case "system_border":    return "System border";
                case "container_fill":   return "Container fill";
                case "container_border": return "Container border";
                case "component_fill":   return "Component fill";
                case "component_border": return "Component border";
                case "database_fill":    return "Database fill";
                case "database_border":  return "Database border";
                case "external_fill":    return "External fill";
                case "external_border":  return "External border";
                case "boundary_stroke":  return "Boundary stroke";
                case "on_colored_text":  return "Text on colored fills";
                case "edge_color":       return "Edge color";
                case "edge_text":        return "Edge label text";
                case "accent_primary":   return "Accent (primary)";
                case "accent_secondary": return "Accent (secondary)";
                case "warning":          return "Warning";
                case "success":          return "Success";
                default:                 return slot;
            }
        }

        public static string get_slot(Palette p, string slot) {
            switch (slot) {
                case "background":       return p.background;
                case "grid":             return p.grid;
                case "node_fill":        return p.node_fill;
                case "node_border":      return p.node_border;
                case "node_text":        return p.node_text;
                case "person_fill":      return p.person_fill;
                case "person_border":    return p.person_border;
                case "system_fill":      return p.system_fill;
                case "system_border":    return p.system_border;
                case "container_fill":   return p.container_fill;
                case "container_border": return p.container_border;
                case "component_fill":   return p.component_fill;
                case "component_border": return p.component_border;
                case "database_fill":    return p.database_fill;
                case "database_border":  return p.database_border;
                case "external_fill":    return p.external_fill;
                case "external_border":  return p.external_border;
                case "boundary_stroke":  return p.boundary_stroke;
                case "on_colored_text":  return p.on_colored_text;
                case "edge_color":       return p.edge_color;
                case "edge_text":        return p.edge_text;
                case "accent_primary":   return p.accent_primary;
                case "accent_secondary": return p.accent_secondary;
                case "warning":          return p.warning;
                case "success":          return p.success;
                default:                 return "#000000";
            }
        }

        public static void set_slot(Palette p, string slot, string value) {
            switch (slot) {
                case "background":       p.background       = value; break;
                case "grid":             p.grid             = value; break;
                case "node_fill":        p.node_fill        = value; break;
                case "node_border":      p.node_border      = value; break;
                case "node_text":        p.node_text        = value; break;
                case "person_fill":      p.person_fill      = value; break;
                case "person_border":    p.person_border    = value; break;
                case "system_fill":      p.system_fill      = value; break;
                case "system_border":    p.system_border    = value; break;
                case "container_fill":   p.container_fill   = value; break;
                case "container_border": p.container_border = value; break;
                case "component_fill":   p.component_fill   = value; break;
                case "component_border": p.component_border = value; break;
                case "database_fill":    p.database_fill    = value; break;
                case "database_border":  p.database_border  = value; break;
                case "external_fill":    p.external_fill    = value; break;
                case "external_border":  p.external_border  = value; break;
                case "boundary_stroke":  p.boundary_stroke  = value; break;
                case "on_colored_text":  p.on_colored_text  = value; break;
                case "edge_color":       p.edge_color       = value; break;
                case "edge_text":        p.edge_text        = value; break;
                case "accent_primary":   p.accent_primary   = value; break;
                case "accent_secondary": p.accent_secondary = value; break;
                case "warning":          p.warning          = value; break;
                case "success":          p.success          = value; break;
            }
        }

        // =====================================================================
        // Built-in preset construction
        // =====================================================================

        private static void ensure_initialized() {
            if (presets != null) return;
            presets = new Gee.HashMap<string, Palette>();
            presets.set("default-light",   build_default_light());
            presets.set("default-dark",    build_default_dark());
            presets.set("solarized-light", build_solarized_light());
            presets.set("solarized-dark",  build_solarized_dark());
            presets.set("dracula",         build_dracula());
            presets.set("nord-light",      build_nord_light());
            presets.set("nord-dark",       build_nord_dark());
        }

        private static Palette build_default_light() {
            var p = new Palette();
            // Canvas
            p.background       = "#FAFAFA";
            p.grid             = "#E8E8E8";
            // Generic
            p.node_fill        = "#FFFFFF";
            p.node_border      = "#424242";
            p.node_text        = "#212121";
            // C4-PlantUML canonical palette
            p.person_fill      = "#08427B";
            p.person_border    = "#073B6F";
            p.system_fill      = "#1168BD";
            p.system_border    = "#3C7FC0";
            p.container_fill   = "#438DD5";
            p.container_border = "#3C7FC0";
            p.component_fill   = "#85BBF0";
            p.component_border = "#78A8D8";
            p.database_fill    = "#438DD5";
            p.database_border  = "#3C7FC0";
            p.external_fill    = "#999999";
            p.external_border  = "#8A8A8A";
            p.boundary_stroke  = "#444444";
            p.on_colored_text  = "#FFFFFF";
            // Edges
            p.edge_color       = "#424242";
            p.edge_text        = "#424242";
            // Accents
            p.accent_primary   = "#1976D2";
            p.accent_secondary = "#F9A825";
            p.warning          = "#E53935";
            p.success          = "#43A047";
            return p;
        }

        private static Palette build_default_dark() {
            var p = new Palette();
            p.background       = "#1E1E1E";
            p.grid             = "#2E2E2E";
            p.node_fill        = "#2D2D2D";
            p.node_border      = "#888888";
            p.node_text        = "#E0E0E0";
            // Same C4 hues but on dark canvas — the saturated blues work fine.
            p.person_fill      = "#0A4A89";
            p.person_border    = "#1168BD";
            p.system_fill      = "#1373CE";
            p.system_border    = "#5A9EE0";
            p.container_fill   = "#4A96DD";
            p.container_border = "#6FA8DE";
            p.component_fill   = "#6BA8E0";
            p.component_border = "#8FC0E8";
            p.database_fill    = "#4A96DD";
            p.database_border  = "#6FA8DE";
            p.external_fill    = "#5C5C5C";
            p.external_border  = "#777777";
            p.boundary_stroke  = "#AAAAAA";
            p.on_colored_text  = "#FFFFFF";
            p.edge_color       = "#B0B0B0";
            p.edge_text        = "#D0D0D0";
            p.accent_primary   = "#64B5F6";
            p.accent_secondary = "#FFD54F";
            p.warning          = "#EF5350";
            p.success          = "#66BB6A";
            return p;
        }

        private static Palette build_solarized_light() {
            var p = new Palette();
            // Solarized base — https://ethanschoonover.com/solarized
            p.background       = "#FDF6E3";  // base3
            p.grid             = "#EEE8D5";  // base2
            p.node_fill        = "#EEE8D5";
            p.node_border      = "#93A1A1";  // base1
            p.node_text        = "#657B83";  // base00
            p.person_fill      = "#268BD2";  // blue
            p.person_border    = "#1A6496";
            p.system_fill      = "#2AA198";  // cyan
            p.system_border    = "#1F7D76";
            p.container_fill   = "#859900";  // green
            p.container_border = "#667A00";
            p.component_fill   = "#B58900";  // yellow
            p.component_border = "#8C6A00";
            p.database_fill    = "#6C71C4";  // violet
            p.database_border  = "#4E53A0";
            p.external_fill    = "#93A1A1";  // base1
            p.external_border  = "#586E75";
            p.boundary_stroke  = "#586E75";  // base01
            p.on_colored_text  = "#FDF6E3";
            p.edge_color       = "#586E75";
            p.edge_text        = "#657B83";
            p.accent_primary   = "#268BD2";
            p.accent_secondary = "#D33682";  // magenta
            p.warning          = "#DC322F";  // red
            p.success          = "#859900";  // green
            return p;
        }

        private static Palette build_solarized_dark() {
            var p = new Palette();
            p.background       = "#002B36";  // base03
            p.grid             = "#073642";  // base02
            p.node_fill        = "#073642";
            p.node_border      = "#586E75";
            p.node_text        = "#93A1A1";
            p.person_fill      = "#268BD2";
            p.person_border    = "#3DA0E5";
            p.system_fill      = "#2AA198";
            p.system_border    = "#3DBDB2";
            p.container_fill   = "#859900";
            p.container_border = "#9FB800";
            p.component_fill   = "#B58900";
            p.component_border = "#D1A210";
            p.database_fill    = "#6C71C4";
            p.database_border  = "#8388D0";
            p.external_fill    = "#586E75";
            p.external_border  = "#657B83";
            p.boundary_stroke  = "#93A1A1";
            p.on_colored_text  = "#FDF6E3";
            p.edge_color       = "#93A1A1";
            p.edge_text        = "#EEE8D5";
            p.accent_primary   = "#268BD2";
            p.accent_secondary = "#D33682";
            p.warning          = "#DC322F";
            p.success          = "#859900";
            return p;
        }

        private static Palette build_dracula() {
            var p = new Palette();
            // Dracula — https://draculatheme.com
            p.background       = "#282A36";
            p.grid             = "#44475A";
            p.node_fill        = "#44475A";
            p.node_border      = "#6272A4";
            p.node_text        = "#F8F8F2";
            p.person_fill      = "#BD93F9";  // purple
            p.person_border    = "#D4B4FB";
            p.system_fill      = "#8BE9FD";  // cyan
            p.system_border    = "#A4EFFD";
            p.container_fill   = "#50FA7B";  // green
            p.container_border = "#6FFB91";
            p.component_fill   = "#F1FA8C";  // yellow
            p.component_border = "#F6FCA5";
            p.database_fill    = "#FFB86C";  // orange
            p.database_border  = "#FFC987";
            p.external_fill    = "#6272A4";  // comment
            p.external_border  = "#8692BF";
            p.boundary_stroke  = "#F8F8F2";
            p.on_colored_text  = "#282A36";
            p.edge_color       = "#F8F8F2";
            p.edge_text        = "#F8F8F2";
            p.accent_primary   = "#FF79C6";  // pink
            p.accent_secondary = "#FFB86C";  // orange
            p.warning          = "#FF5555";  // red
            p.success          = "#50FA7B";
            return p;
        }

        private static Palette build_nord_light() {
            var p = new Palette();
            // Nord — https://www.nordtheme.com
            p.background       = "#ECEFF4";  // snow 3
            p.grid             = "#E5E9F0";  // snow 2
            p.node_fill        = "#E5E9F0";
            p.node_border      = "#4C566A";  // polar night 4
            p.node_text        = "#2E3440";  // polar night 1
            p.person_fill      = "#5E81AC";  // frost 4
            p.person_border    = "#4C6A8C";
            p.system_fill      = "#81A1C1";  // frost 3
            p.system_border    = "#6F8DAA";
            p.container_fill   = "#88C0D0";  // frost 2
            p.container_border = "#76A9B8";
            p.component_fill   = "#8FBCBB";  // frost 1
            p.component_border = "#77A4A3";
            p.database_fill    = "#B48EAD";  // aurora purple
            p.database_border  = "#9E7797";
            p.external_fill    = "#D8DEE9";  // snow 1
            p.external_border  = "#ADB1B8";
            p.boundary_stroke  = "#4C566A";
            p.on_colored_text  = "#ECEFF4";
            p.edge_color       = "#3B4252";
            p.edge_text        = "#2E3440";
            p.accent_primary   = "#5E81AC";
            p.accent_secondary = "#D08770";  // aurora orange
            p.warning          = "#BF616A";  // aurora red
            p.success          = "#A3BE8C";  // aurora green
            return p;
        }

        private static Palette build_nord_dark() {
            var p = new Palette();
            p.background       = "#2E3440";  // polar night 1
            p.grid             = "#3B4252";  // polar night 2
            p.node_fill        = "#3B4252";
            p.node_border      = "#D8DEE9";
            p.node_text        = "#ECEFF4";
            p.person_fill      = "#5E81AC";
            p.person_border    = "#81A1C1";
            p.system_fill      = "#81A1C1";
            p.system_border    = "#9FB9D5";
            p.container_fill   = "#88C0D0";
            p.container_border = "#A5D1DC";
            p.component_fill   = "#8FBCBB";
            p.component_border = "#ACCECD";
            p.database_fill    = "#B48EAD";
            p.database_border  = "#C9A9C3";
            p.external_fill    = "#4C566A";
            p.external_border  = "#6B7689";
            p.boundary_stroke  = "#D8DEE9";
            p.on_colored_text  = "#ECEFF4";
            p.edge_color       = "#D8DEE9";
            p.edge_text        = "#ECEFF4";
            p.accent_primary   = "#88C0D0";
            p.accent_secondary = "#D08770";
            p.warning          = "#BF616A";
            p.success          = "#A3BE8C";
            return p;
        }
    }
}
