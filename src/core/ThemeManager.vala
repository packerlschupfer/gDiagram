namespace GDiagram {
    public enum DiagramTheme {
        LIGHT,
        DARK,
        AUTO  // Follow system theme
    }

    public class ColorScheme : Object {
        public string background { get; set; }
        public string node_fill { get; set; }
        public string node_border { get; set; }
        public string edge_color { get; set; }
        public string text_color { get; set; }

        public ColorScheme(string bg, string fill, string border, string edge, string text) {
            this.background = bg;
            this.node_fill = fill;
            this.node_border = border;
            this.edge_color = edge;
            this.text_color = text;
        }
    }

    public class ThemeManager : Object {
        private static Gee.HashMap<string, ColorScheme>? light_schemes = null;
        private static Gee.HashMap<string, ColorScheme>? dark_schemes = null;

        public static void initialize() {
            if (light_schemes != null) return;

            light_schemes = new Gee.HashMap<string, ColorScheme>();
            dark_schemes = new Gee.HashMap<string, ColorScheme>();

            // Light theme color schemes
            light_schemes.set("flowchart", new ColorScheme("#FAFAFA", "#FFFFFF", "#424242", "#424242", "#212121"));
            light_schemes.set("sequence", new ColorScheme("#FAFAFA", "#E3F2FD", "#1976D2", "#424242", "#1565C0"));
            light_schemes.set("state", new ColorScheme("#FAFAFA", "#FFF9E6", "#F9A825", "#424242", "#F57F17"));
            light_schemes.set("class", new ColorScheme("#FAFAFA", "#E8F5E9", "#388E3C", "#424242", "#1B5E20"));
            light_schemes.set("er", new ColorScheme("#FAFAFA", "#FFF3E0", "#F57C00", "#424242", "#E65100"));

            // Dark theme color schemes
            dark_schemes.set("flowchart", new ColorScheme("#1E1E1E", "#2D2D2D", "#CCCCCC", "#AAAAAA", "#E0E0E0"));
            dark_schemes.set("sequence", new ColorScheme("#1E1E1E", "#1A237E", "#7986CB", "#90CAF9", "#BBDEFB"));
            dark_schemes.set("state", new ColorScheme("#1E1E1E", "#3E2723", "#FFCA28", "#FDD835", "#FFF59D"));
            dark_schemes.set("class", new ColorScheme("#1E1E1E", "#1B5E20", "#66BB6A", "#81C784", "#A5D6A7"));
            dark_schemes.set("er", new ColorScheme("#1E1E1E", "#4E342E", "#FF9800", "#FFB74D", "#FFCC80"));
        }

        public static ColorScheme get_scheme(string diagram_type, DiagramTheme theme) {
            initialize();

            var schemes = (theme == DiagramTheme.DARK) ? dark_schemes : light_schemes;

            if (schemes.has_key(diagram_type)) {
                return schemes.get(diagram_type);
            }

            // Default fallback
            return schemes.get("flowchart");
        }

        public static string apply_theme_to_dot(string dot_source, DiagramTheme theme, string diagram_type = "flowchart") {
            var scheme = get_scheme(diagram_type, theme);
            var output = new StringBuilder(dot_source);

            // Replace default colors with theme colors
            if (theme == DiagramTheme.DARK) {
                output.str = output.str.replace("#FAFAFA", scheme.background);
                output.str = output.str.replace("#FFFFFF", scheme.node_fill);
                output.str = output.str.replace("fillcolor=\"white\"", "fillcolor=\"%s\"".printf(scheme.node_fill));
            }

            return output.str;
        }

        // Detect system theme (simplified - would integrate with GTK StyleContext)
        public static DiagramTheme get_system_theme() {
            // In a full implementation, would check:
            // var style_manager = Adw.StyleManager.get_default();
            // return style_manager.dark ? DiagramTheme.DARK : DiagramTheme.LIGHT;

            // For now, return light as default
            return DiagramTheme.LIGHT;
        }
    }
}
