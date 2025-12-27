namespace GDiagram {
    // Element region for click-to-source navigation
    public class ElementRegion : Object {
        public string name { get; set; }
        public int source_line { get; set; }
        public double x { get; set; }
        public double y { get; set; }
        public double width { get; set; }
        public double height { get; set; }

        public ElementRegion(string name, int line, double x, double y, double w, double h) {
            this.name = name;
            this.source_line = line;
            this.x = x;
            this.y = y;
            this.width = w;
            this.height = h;
        }
    }

    // Shared rendering utilities for all diagram renderers
    public class RenderUtils : Object {
        // Escape identifier to make valid DOT identifier
        public static string escape_id(string s) {
            if (s == null || s.length == 0) {
                return "n_empty";
            }

            // Make valid DOT identifier - properly handle UTF-8
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_') {
                    sb.append_unichar(c);
                } else {
                    sb.append_c('_');
                }
            }
            string result = sb.str;
            if (result.length == 0 || (result[0] >= '0' && result[0] <= '9')) {
                return "n_" + result;
            }
            return result;
        }

        // Escape label for DOT format
        public static string escape_label(string? s) {
            if (s == null || s.length == 0) {
                return "";
            }

            // Validate UTF-8 and copy to a clean string
            if (!s.validate()) {
                // If invalid UTF-8, convert to safe ASCII representation
                var safe_sb = new StringBuilder();
                for (int i = 0; i < s.length; i++) {
                    char c = s[i];
                    if (c >= 32 && c < 127) {
                        safe_sb.append_c(c);
                    } else {
                        safe_sb.append_c('?');
                    }
                }
                return safe_sb.str;
            }

            // Build result by iterating over UTF-8 characters properly
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                if (c == '\\') {
                    // Check for \n escape sequence
                    if (i < s.length) {
                        unichar next;
                        int next_i = i;
                        if (s.get_next_char(ref next_i, out next) && next == 'n') {
                            sb.append("\\n");  // Keep as escaped newline for DOT
                            i = next_i;
                            continue;
                        }
                    }
                    sb.append("\\\\");  // Escape backslash
                } else if (c == '"') {
                    sb.append("\\\"");  // Escape quote
                } else if (c == '\n') {
                    sb.append("\\n");   // Convert newline
                } else {
                    sb.append_unichar(c);
                }
            }

            return sb.str;
        }

        // Sanitize identifier for DOT
        public static string sanitize_id(string id) {
            if (id == null || id.length == 0) {
                return "_empty";
            }

            // Convert name to valid DOT identifier
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (id.get_next_char(ref i, out c)) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_') {
                    sb.append_unichar(c);
                } else {
                    sb.append_c('_');
                }
            }
            string result = sb.str;
            // Ensure it doesn't start with a number
            if (result.length > 0 && result[0] >= '0' && result[0] <= '9') {
                result = "_" + result;
            }
            return result.length > 0 ? result : "_empty";
        }

        // Check if string has Creole formatting
        public static bool has_creole_formatting(string? s) {
            if (s == null) return false;
            return s.contains("**") || s.contains("//") || s.contains("__") ||
                   s.contains("--") || s.contains("~~");
        }

        // Convert Creole formatting to Graphviz HTML-like labels
        public static string convert_creole_to_html(string? s) {
            if (s == null || s.length == 0) {
                return "";
            }
            // Convert Creole formatting to Graphviz HTML-like label format
            string result = s;
            string? temp;

            // Convert \n to <br/>
            temp = result.replace("\\n", "<br/>");
            if (temp != null) result = temp;

            // Escape HTML special characters first (but not our markers)
            temp = result.replace("&", "&amp;");
            if (temp != null) result = temp;

            // Note: Graphviz HTML labels should preserve regular spaces
            // Remove the &#160; conversion as it may not be supported

            // Convert Creole markers to HTML tags using regex
            try {
                // Bold: **text**
                Regex bold_re = new Regex("\\*\\*(.+?)\\*\\*");
                string? regex_temp = bold_re.replace(result, -1, 0, "<b>\\1</b>");
                if (regex_temp != null) result = regex_temp;

                // Italic: //text// - use non-greedy match
                Regex italic_re = new Regex("//(.+?)//");
                regex_temp = italic_re.replace(result, -1, 0, "<i>\\1</i>");
                if (regex_temp != null) result = regex_temp;

                // Underline: __text__
                Regex underline_re = new Regex("__(.+?)__");
                regex_temp = underline_re.replace(result, -1, 0, "<u>\\1</u>");
                if (regex_temp != null) result = regex_temp;

                // Strikethrough: --text--
                Regex strike_re = new Regex("--(.+?)--");
                regex_temp = strike_re.replace(result, -1, 0, "<s>\\1</s>");
                if (regex_temp != null) result = regex_temp;

                // Monospace: ~~text~~
                Regex mono_re = new Regex("~~(.+?)~~");
                regex_temp = mono_re.replace(result, -1, 0, "<font face=\"monospace\">\\1</font>");
                if (regex_temp != null) result = regex_temp;
            } catch (RegexError e) {
                // If regex fails, return original
            }

            // Wrap in TABLE structure to fix libgvc spacing issues with mixed HTML content
            result = "<TABLE BORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\" CELLBORDER=\"0\"><TR><TD ALIGN=\"LEFT\">" + result + "</TD></TR></TABLE>";

            return result;
        }

        // Parse SVG to extract element bounding boxes for click navigation
        // surface_width/height are optional - if provided, coordinates will be scaled from SVG units to pixels
        public static void parse_svg_regions(uint8[] svg_data, Gee.ArrayList<ElementRegion> regions,
                                             Gee.HashMap<string, int>? element_lines = null,
                                             double surface_width = 0, double surface_height = 0) {
            regions.clear();

            string svg_str = (string)svg_data;

            try {
                // Extract SVG viewBox or width/height to determine coordinate scaling
                double svg_width = 0, svg_height = 0;
                var viewbox_regex = new Regex("viewBox=\"([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)\"");
                MatchInfo viewbox_match;
                if (viewbox_regex.match(svg_str, 0, out viewbox_match)) {
                    svg_width = double.parse(viewbox_match.fetch(3));
                    svg_height = double.parse(viewbox_match.fetch(4));
                }

                // Calculate scale factor (pt to pixels)
                double scale_x = 1.0, scale_y = 1.0;
                if (surface_width > 0 && svg_width > 0) {
                    scale_x = surface_width / svg_width;
                }
                if (surface_height > 0 && svg_height > 0) {
                    scale_y = surface_height / svg_height;
                }

                // Extract the root graph transform (Graphviz uses translate to flip Y-axis)
                double translate_x = 0, translate_y = 0;
                var transform_regex = new Regex("<g[^>]*class=\"graph\"[^>]*transform=\"[^\"]*translate\\(([\\d.]+)\\s+([\\d.]+)\\)");
                MatchInfo transform_match;
                if (transform_regex.match(svg_str, 0, out transform_match)) {
                    translate_x = double.parse(transform_match.fetch(1));
                    translate_y = double.parse(transform_match.fetch(2));
                }

                // Parse all <g> groups that have a <title> element (Graphviz convention)
                // Only match nodes (class="node"), not clusters or edges
                var group_regex = new Regex(
                    "<g[^>]*class=\"node\"[^>]*>\\s*<title>([^<]+)</title>(.*?)</g>",
                    RegexCompileFlags.DOTALL
                );

                MatchInfo match;
                if (group_regex.match(svg_str, 0, out match)) {
                    do {
                        string title = match.fetch(1);
                        string content = match.fetch(2);

                        if (title == null || title.length == 0 || title == "G") {
                            continue; // Skip the root graph
                        }

                        // Skip edges (title contains "->")
                        if (title.contains("->") || title.contains("&#45;&gt;")) {
                            continue;
                        }

                        double min_x = double.MAX, min_y = double.MAX;
                        double max_x = -double.MAX, max_y = -double.MAX;

                        // Try to extract bounding box from various SVG shapes

                        // 1. Polygon points
                        var poly_regex = new Regex("points=\"([^\"]+)\"");
                        MatchInfo poly_match;
                        if (poly_regex.match(content, 0, out poly_match)) {
                            string points = poly_match.fetch(1);
                            parse_polygon_bounds(points, ref min_x, ref min_y, ref max_x, ref max_y);
                        }

                        // 2. Ellipse
                        var ellipse_regex = new Regex("cx=\"([^\"]+)\"[^>]*cy=\"([^\"]+)\"[^>]*rx=\"([^\"]+)\"[^>]*ry=\"([^\"]+)\"");
                        MatchInfo ellipse_match;
                        if (ellipse_regex.match(content, 0, out ellipse_match)) {
                            double cx = double.parse(ellipse_match.fetch(1));
                            double cy = double.parse(ellipse_match.fetch(2));
                            double rx = double.parse(ellipse_match.fetch(3));
                            double ry = double.parse(ellipse_match.fetch(4));
                            min_x = double.min(min_x, cx - rx);
                            max_x = double.max(max_x, cx + rx);
                            min_y = double.min(min_y, cy - ry);
                            max_y = double.max(max_y, cy + ry);
                        }

                        // 3. Rectangle
                        var rect_regex = new Regex("<rect[^>]*x=\"([^\"]+)\"[^>]*y=\"([^\"]+)\"[^>]*width=\"([^\"]+)\"[^>]*height=\"([^\"]+)\"");
                        MatchInfo rect_match;
                        if (rect_regex.match(content, 0, out rect_match)) {
                            double x = double.parse(rect_match.fetch(1));
                            double y = double.parse(rect_match.fetch(2));
                            double w = double.parse(rect_match.fetch(3));
                            double h = double.parse(rect_match.fetch(4));
                            min_x = double.min(min_x, x);
                            max_x = double.max(max_x, x + w);
                            min_y = double.min(min_y, y);
                            max_y = double.max(max_y, y + h);
                        }

                        // 4. Path - extract from 'd' attribute (basic bounding box)
                        var path_regex = new Regex("<path[^>]*d=\"([^\"]+)\"");
                        MatchInfo path_match;
                        if (path_regex.match(content, 0, out path_match)) {
                            string d = path_match.fetch(1);
                            parse_path_bounds(d, ref min_x, ref min_y, ref max_x, ref max_y);
                        }

                        // 5. Text position as fallback (only if no shape bounds found)
                        if (min_x >= double.MAX || max_x <= double.MIN) {
                            var text_regex = new Regex("<text[^>]*x=\"([^\"]+)\"[^>]*y=\"([^\"]+)\"");
                            MatchInfo text_match;
                            if (text_regex.match(content, 0, out text_match)) {
                                double tx = double.parse(text_match.fetch(1));
                                double ty = double.parse(text_match.fetch(2));
                                // Approximate text bounds
                                min_x = double.min(min_x, tx - 50);
                                max_x = double.max(max_x, tx + 50);
                                min_y = double.min(min_y, ty - 15);
                                max_y = double.max(max_y, ty + 5);
                            }
                        }

                        if (min_x < double.MAX && max_x > -double.MAX) {
                            int line = 0;
                            if (element_lines != null && element_lines.has_key(title)) {
                                line = element_lines.get(title);
                            }
                            // Apply the graph transform (translate_x, translate_y)
                            // Graphviz uses inverted Y-axis, so we add the translate values
                            // Then scale to pixel coordinates
                            double final_x = (translate_x + min_x) * scale_x;
                            double final_y = (translate_y + min_y) * scale_y;
                            double final_width = (max_x - min_x) * scale_x;
                            double final_height = (max_y - min_y) * scale_y;

                            regions.add(new ElementRegion(
                                title, line,
                                final_x, final_y,
                                final_width, final_height
                            ));
                        }
                    } while (match.next());
                }
            } catch (Error e) {
                warning("Failed to parse SVG regions: %s", e.message);
            }
        }

        // Parse polygon points to extract bounding box
        private static void parse_polygon_bounds(string points, ref double min_x, ref double min_y,
                                                  ref double max_x, ref double max_y) {
            string[] point_pairs = points.split(" ");
            foreach (var pair in point_pairs) {
                string[] coords = pair.split(",");
                if (coords.length >= 2) {
                    double x = double.parse(coords[0]);
                    double y = double.parse(coords[1]);
                    min_x = double.min(min_x, x);
                    min_y = double.min(min_y, y);
                    max_x = double.max(max_x, x);
                    max_y = double.max(max_y, y);
                }
            }
        }

        // Parse SVG path to extract bounding box
        private static void parse_path_bounds(string d, ref double min_x, ref double min_y,
                                               ref double max_x, ref double max_y) {
            // Simple path parsing - extract numeric coordinates
            try {
                var num_regex = new Regex("(-?[0-9]+\\.?[0-9]*)");
                MatchInfo match;
                var numbers = new Gee.ArrayList<double?>();

                if (num_regex.match(d, 0, out match)) {
                    do {
                        numbers.add(double.parse(match.fetch(1)));
                    } while (match.next());
                }

                // Assume alternating x,y pairs
                for (int i = 0; i < numbers.size - 1; i += 2) {
                    double x = numbers[i];
                    double y = numbers[i + 1];
                    min_x = double.min(min_x, x);
                    min_y = double.min(min_y, y);
                    max_x = double.max(max_x, x);
                    max_y = double.max(max_y, y);
                }
            } catch (Error e) {
                // Ignore path parsing errors
            }
        }
    }
}
