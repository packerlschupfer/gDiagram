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
        /**
         * Parses DOT for layout with Sans as the default graph font. Graph and cluster
         * titles without their own fontname otherwise fall back to Graphviz's serif
         * default (Times), which clashed with the Sans node text. The default is declared
         * first in the body, so clusters inherit it and any explicit fontname still wins.
         */
        public static Gvc.Graph? read_dot(string dot) {
            int brace = dot.index_of("{");
            if (brace < 0) {
                return Gvc.Graph.read_string(dot);
            }
            string with_font = dot.substring(0, brace + 1) + "\n  fontname=\"Sans\";" + dot.substring(brace + 1);
            return Gvc.Graph.read_string(with_font);
        }

        /**
         * GraphvizCompat.render_data() plus fill_svg_background() for SVG output. Every
         * in-process render goes through here.
         */
        public static int render_data(Gvc.Context context, Gvc.Graph graph, string format, out uint8[] output_data) {
            int ret = GraphvizCompat.render_data(context, graph, format, out output_data);
            if (ret == 0 && format == "svg") {
                output_data = fill_svg_background(output_data);
            }
            return ret;
        }

        /**
         * Graphviz rounds the SVG width/height to whole points but draws the background
         * polygon over the exact bounding box, so a sliver along the right edge (up to a
         * point) stays transparent and showed as a light line on dark diagrams. A rect in
         * the background colour over the whole canvas, drawn first, closes it.
         */
        public static uint8[] fill_svg_background(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            int svg_tag = svg.index_of("<svg");
            if (svg_tag < 0) return svg_data;
            int tag_end = svg.index_of(">", svg_tag);
            int graph = svg.index_of("<g id=\"graph0\"", tag_end);
            if (tag_end < 0 || graph < 0) return svg_data;
            // The first polygon inside graph0 is the graph background
            int poly = svg.index_of("<polygon fill=\"", graph);
            if (poly < 0) return svg_data;
            int value_start = poly + "<polygon fill=\"".length;
            int value_end = svg.index_of("\"", value_start);
            if (value_end < 0) return svg_data;
            string fill = svg.substring(value_start, value_end - value_start);
            if (fill == "none" || fill == "transparent") return svg_data;
            string result = svg.substring(0, tag_end + 1) +
                "\n<rect x=\"0\" y=\"0\" width=\"100%\" height=\"100%\" fill=\"%s\"/>".printf(fill) +
                svg.substring(tag_end + 1);
            return colour_default_titles(result, fill).data;
        }

        /**
         * Graphviz writes no fill for black text, and graph/cluster titles default to black:
         * on a dark background or a dark cluster fill they were unreadable. Titles without a
         * fill (the graph's own texts before its first group, and every text of a cluster
         * group) get the text colour that contrasts with what is behind them: the cluster's
         * fill, or the graph background for unfilled clusters. Gradient fills are left alone.
         */
        private static string colour_default_titles(string svg, string background) {
            var sb = new StringBuilder.sized(svg.length + 256);
            int pos = 0;
            int graph = svg.index_of("<g id=\"graph0\"");
            if (graph < 0) return svg;
            int first_group = svg.index_of("<g id=", graph + 1);
            if (first_group < 0) first_group = svg.length;
            // Graph titles
            sb.append(svg.substring(pos, graph - pos));
            sb.append(fill_plain_texts(svg.substring(graph, first_group - graph), background));
            pos = first_group;
            // Clusters (Graphviz writes them as flat groups)
            while (true) {
                int clust = svg.index_of("class=\"cluster\">", pos);
                if (clust < 0) break;
                // last_index_of(s, start) searches from start to the END, not backwards
                int group_start = svg.substring(0, clust).last_index_of("<g ");
                int group_end = svg.index_of("</g>", clust);
                if (group_start < pos || group_end < 0) break;
                string group = svg.substring(group_start, group_end - group_start);
                string behind = background;
                int shape = group.index_of(" fill=\"");
                if (shape >= 0) {
                    int v = shape + " fill=\"".length;
                    string cluster_fill = group.substring(v, group.index_of("\"", v) - v);
                    if (cluster_fill.has_prefix("url(")) {
                        behind = "";
                    } else if (cluster_fill != "none" && cluster_fill != "transparent") {
                        behind = cluster_fill;
                    }
                }
                sb.append(svg.substring(pos, group_start - pos));
                sb.append(behind.length > 0 ? fill_plain_texts(group, behind) : group);
                pos = group_end;
            }
            sb.append(svg.substring(pos));
            return sb.str;
        }

        // Adds fill="<contrast with bg>" to every <text> of `fragment` that has no fill
        private static string fill_plain_texts(string fragment, string bg) {
            if (!fragment.contains("<text")) return fragment;
            string colour = contrast_text(bg);
            var sb = new StringBuilder();
            int pos = 0;
            while (true) {
                int t = fragment.index_of("<text", pos);
                if (t < 0) break;
                int close = fragment.index_of(">", t);
                if (close < 0) break;
                sb.append(fragment.substring(pos, close - pos));
                if (!fragment.substring(t, close - t).contains(" fill=")) {
                    sb.append(" fill=\"%s\"".printf(colour));
                }
                pos = close;
            }
            sb.append(fragment.substring(pos));
            return sb.str;
        }

        // Escape identifier to make valid DOT identifier
        public static string escape_id(string? s) {
            // The null check is intentional: the signature is nullable so
            // Vala doesn't add a g_return_val_if_fail precondition that
            // would abort the process before this body runs. Several
            // code paths pass `node.id` or similar nullable fields.
            if (s == null || s.length == 0) {
                return "n_empty";
            }

            // Make valid DOT identifier - properly handle UTF-8
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                // Non-ASCII letters and digits are valid in DOT ids (bytes 0x80-0xFF); turning
                // them into "_" made "Ä" and "Ü" the same node
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_' || (c > 127 && c.isalnum())) {
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
        /**
         * Conservative Creole stripping for text the user wrote directly —
         * edge labels, note bodies, state descriptions.
         *
         * strip_plantuml_markup() below is tuned for C4-PlantUML macro
         * expansions and deletes "stray" fragments such as a leading "< ",
         * which in user text is real content: "< 100ms" rendered as "100ms".
         * This removes only well-formed markup — **bold**, //italic//,
         * complete <b>/<i>/<u>/<s>/<size:..>/<color:..>/<font:..> tags and
         * [[links]] — and tolerates the spaces parsers insert when rejoining
         * tokens ("* * x * *", "< color : #101010 >").
         */
        public static string strip_inline_creole(string? s) {
            if (s == null || s.length == 0) return "";
            string r = s;
            try {
                var value_tag = new Regex("<\\s*/?\\s*(size|color|font)\\s*(:[^<>]*)?>", RegexCompileFlags.CASELESS);
                r = value_tag.replace_literal(r, -1, 0, "");
                var simple_tag = new Regex("<\\s*/?\\s*(b|i|u|s)\\s*>", RegexCompileFlags.CASELESS);
                r = simple_tag.replace_literal(r, -1, 0, "");
                var bold = new Regex("\\*\\s*\\*\\s*(.+?)\\s*\\*\\s*\\*");
                r = bold.replace(r, -1, 0, "\\1");
                // (?<!:) keeps URL schemes like "https://" intact.
                var italic = new Regex("(?<!:)//(.+?)(?<!:)//");
                r = italic.replace(r, -1, 0, "\\1");
                var link_text = new Regex("\\[\\[\\s*([^\\]\\s]+)\\s+([^\\]]+?)\\s*\\]\\]");
                r = link_text.replace(r, -1, 0, "\\2");
                var link_bare = new Regex("\\[\\[\\s*([^\\]]+?)\\s*\\]\\]");
                r = link_bare.replace(r, -1, 0, "\\1");
            } catch (RegexError e) {
                warning("strip_inline_creole: %s", e.message);
            }
            return r;
        }

        /**
         * Strip PlantUML inline-creole markup that the renderer can't render
         * meaningfully — e.g. <size:N>, </size>, <color:X>, </color>, **bold**,
         * //italic//, [[link text]], == headings ==, leading "== " bullets.
         *
         * Used by the C4-PlantUML rendering path: the C4 stdlib's
         * $getElementBase, $getRel, etc. wrap labels in size+color+bold+link
         * markup that PlantUML's own renderer interprets but graphviz does not.
         * Without stripping, the markup appears as raw text in the output.
         *
         * Newline escapes (\n, \l, \r) are preserved — graphviz handles them
         * as line breaks.
         */
        public static string strip_plantuml_markup(string? s) {
            if (s == null || s.length == 0) return "";
            string r = s;
            try {
                // <size:N>...</size>, <color:X>...</color>, <font:...>
                // Tolerate stray spaces from token-rejoining (the component
                // parser joins tokens like "< size : 12 >" with spaces around
                // punctuation) by allowing whitespace inside the markers.
                var size_open  = new Regex("<\\s*size\\s*:\\s*[^>]*>", RegexCompileFlags.CASELESS);
                r = size_open.replace_literal(r, -1, 0, "");
                var size_close = new Regex("<\\s*/\\s*size\\s*>", RegexCompileFlags.CASELESS);
                r = size_close.replace_literal(r, -1, 0, "");
                var color_open = new Regex("<\\s*color\\s*:\\s*[^>]*>", RegexCompileFlags.CASELESS);
                r = color_open.replace_literal(r, -1, 0, "");
                var color_close = new Regex("<\\s*/\\s*color\\s*>", RegexCompileFlags.CASELESS);
                r = color_close.replace_literal(r, -1, 0, "");
                var font_open = new Regex("<\\s*font\\s*:\\s*[^>]*>", RegexCompileFlags.CASELESS);
                r = font_open.replace_literal(r, -1, 0, "");
                var font_close = new Regex("<\\s*/\\s*font\\s*>", RegexCompileFlags.CASELESS);
                r = font_close.replace_literal(r, -1, 0, "");
                // Stray "//" italic markers and leading "< " left over from
                // partial expansions. Don't touch "//" preceded by ":" so
                // URL schemes like "https://" survive intact.
                r = r.replace(" / / ", " ");
                r = r.replace("/ /", "");
                var stray_slashes = new Regex("(?<!:)//");
                r = stray_slashes.replace_literal(r, -1, 0, "");
                // Stray leading "< " that comes from <size> opening that lost its body
                var stray_lt = new Regex("^\\s*<\\s+");
                r = stray_lt.replace_literal(r, -1, 0, "");

                // **bold** and //italic// — keep the inner text.
                // Allow whitespace between and around the asterisks: parsers that
                // rejoin tokens with spaces turn "**text**" into "* * text * *".
                var bold = new Regex("\\*\\s*\\*\\s*(.*?)\\s*\\*\\s*\\*");
                r = bold.replace(r, -1, 0, "\\1");
                var italic = new Regex("//(.*?)//");
                r = italic.replace(r, -1, 0, "\\1");

                // [[link text]] — keep just "text"
                var link_text = new Regex("\\[\\[([^\\]]*?)\\s+([^\\]]+)\\]\\]");
                r = link_text.replace(r, -1, 0, "\\2");
                // [[link]] alone — keep the link
                var link_bare = new Regex("\\[\\[([^\\]]*)\\]\\]");
                r = link_bare.replace(r, -1, 0, "\\1");

                // Stray opening "[[" or closing "]]" left over from partial expansions
                var stray_open = new Regex("\\[\\[< ?");
                r = stray_open.replace_literal(r, -1, 0, "");
                var stray_close = new Regex(" ?\\]\\]");
                r = stray_close.replace_literal(r, -1, 0, "");

                // Leading "== " heading marker (PlantUML uses this for big text)
                var heading = new Regex("^\\s*== ");
                r = heading.replace_literal(r, -1, 0, "");
                // Inner == that survived after a \n
                r = r.replace("\\n== ", "\\n");
                r = r.replace("\\n\\n", "\\n");

                // Stray standalone characters at line boundaries from
                // partial preprocessor expansions (e.g. an unmatched "<"
                // from <size:N> or "[" from [[link]] that survived stripping).
                var leading_lt = new Regex("(^|\\\\n)\\s*<\\s*(\\\\n|$)");
                r = leading_lt.replace(r, -1, 0, "\\1\\2");
                var leading_lb = new Regex("(^|\\\\n)\\s*\\[\\s*(\\\\n|$)");
                r = leading_lb.replace(r, -1, 0, "\\1\\2");
                // Collapse multiple consecutive \n
                while (r.contains("\\n\\n")) {
                    r = r.replace("\\n\\n", "\\n");
                }
                // Strip leading/trailing \n
                while (r.has_prefix("\\n")) r = r.substring(2);
                while (r.has_suffix("\\n")) r = r.substring(0, r.length - 2);
            } catch (RegexError e) {
                // Fall through with whatever was processed so far
            }
            // Trim trailing whitespace and stray nbsp markers
            r = r.replace("<U+00A0>", " ");
            return r.strip();
        }

        /**
         * Sanitize a color value for Graphviz consumption. Strips:
         *   - PlantUML gradient separators: "Color1/Color2" or "Color1|Color2" → "Color1"
         *   - Leading "#" on named colors: "#red" → "red" (keep for hex)
         * Returns a single color Graphviz can handle.
         */
        public static string sanitize_color(string color) {
            // A gradient gives its first colour, as parse_gradient reads it ("#FF0000-00FF00"
            // kept the whole value, "white | gray" the second colour)
            string first, second;
            int angle;
            if (parse_gradient(color, out first, out second, out angle)) {
                return first;
            }
            string c = color.strip();
            // Strip leaked stereotype prefixes: "Foo Tomato" → "Tomato"
            // (skinparam parser sometimes includes <<Stereo>> name in the value)
            if (c.contains(" ") && !c.has_prefix("#")) {
                string[] parts = c.split(" ");
                c = parts[parts.length - 1].strip();
            }
            // Strip gradient separators — PlantUML uses / | - \ for gradients.
            // Keep only the first color.
            foreach (string sep in new string[] { "/", "|", "-", "\\" }) {
                int pos = c.index_of(sep);
                // For "-", skip if it's a real hex code like #FF0000-00FF00 → keep first
                // But still split named colors like #red-green or red-green
                if (sep == "-" && pos > 0 && c.has_prefix("#") && c.length > 1) {
                    // Check if char after # is hex digit → real hex color, don't split
                    char h = c[1];
                    if ((h >= '0' && h <= '9') || (h >= 'a' && h <= 'f') || (h >= 'A' && h <= 'F'))
                        continue;
                }
                if (pos > 0) {
                    c = c.substring(0, pos).strip();
                    break;
                }
            }
            // "#FF0000" → keep; "#red" → "red"
            if (c.has_prefix("#") && c.length > 1) {
                string after = c.substring(1);
                bool is_hex = true;
                foreach (char ch in after.to_utf8()) {
                    if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'))) {
                        is_hex = false;
                        break;
                    }
                }
                if (!is_hex) c = after;  // named color — strip #
            }
            return c;
        }

        /**
         * Split a PlantUML colour value into a two-colour gradient: "#red-green",
         * "AntiqueWhite/Gold", "#blue\9932CC" (second colour hex without "#"),
         * "#FF0000|00FF00". Only the part before ";" is the fill ("#pink-red;line:blue").
         * Returns false for a plain colour. `first`/`second` are Graphviz-ready
         * ("red", "#9932CC"); `angle` is the Graphviz gradientangle matching
         * PlantUML's direction, verified against PlantUML 1.2026.1 SVG output:
         *   "|" left→right = 0, "-" top→bottom = 270,
         *   "/" top-left→bottom-right = 315, "\" bottom-left→top-right = 45.
         */
        public static bool parse_gradient(string? color, out string first, out string second, out int angle) {
            first = "";
            second = "";
            angle = 0;
            if (color == null) {
                return false;
            }
            string c = join_gradient_spaces(color.strip());
            // Same leaked-stereotype handling as sanitize_color ("Foo Tomato/Gold")
            if (c.contains(" ") && !c.has_prefix("#")) {
                string[] parts = c.split(" ");
                c = parts[parts.length - 1].strip();
            }
            int semi = c.index_of(";");
            if (semi >= 0) {
                c = c.substring(0, semi).strip();
            }
            if (c.has_prefix("#")) {
                c = c.substring(1);
            }
            int pos = -1;
            for (int i = 0; i < c.length; i++) {
                char ch = c[i];
                if (ch == '|' || ch == '-' || ch == '/' || ch == '\\') {
                    pos = i;
                    break;
                }
            }
            if (pos <= 0 || pos >= c.length - 1) {
                return false;
            }
            string a = c.substring(0, pos);
            string b = c.substring(pos + 1);
            if (b.has_prefix("#")) {
                b = b.substring(1);
            }
            if (!is_color_word(a) || !is_color_word(b)) {
                return false;
            }
            angle = gradient_angle_for_separator(c.substring(pos, 1));
            first = gradient_part(a);
            second = gradient_part(b);
            return true;
        }

        /**
         * Graphviz gradientangle for a PlantUML gradient separator (see parse_gradient):
         * "|" 0, "-" 270, "/" 315, "\" 45. Graphviz angles run counter-clockwise from
         * left→right; SVG y grows downwards, so top→bottom is 270.
         */
        public static int gradient_angle_for_separator(string? separator) {
            switch (separator) {
                case "|": return 0;
                case "/": return 315;
                case "\\": return 45;
                default: return 270;  // "-"
            }
        }

        // "white | gray" -> "white|gray": some skinparam parsers join value tokens with spaces,
        // and the leaked-stereotype rule then kept only "gray"
        private static string join_gradient_spaces(string c) {
            if (!c.contains(" ")) {
                return c;
            }
            string r = c;
            foreach (string sep in new string[] { "|", "-", "/", "\\" }) {
                r = r.replace(" " + sep, sep).replace(sep + " ", sep);
            }
            return r;
        }

        // Letters and digits only: a colour name or hex digits
        private static bool is_color_word(string s) {
            if (s.length == 0) {
                return false;
            }
            for (int i = 0; i < s.length; i++) {
                if (!s[i].isalnum()) {
                    return false;
                }
            }
            return true;
        }

        // One side of a gradient: hex digits get "#" (a 3-digit "F00" expanded, which
        // Graphviz doesn't read), anything else is a colour name as written
        private static string gradient_part(string s) {
            if (is_hex_digits(s) && (s.length == 3 || s.length == 6 || s.length == 8)) {
                if (s.length == 3) {
                    return "#%c%c%c%c%c%c".printf(s[0], s[0], s[1], s[1], s[2], s[2]);
                }
                return "#" + s;
            }
            return s;
        }

        /**
         * Fill colour for Graphviz `fillcolor` / `bgcolor` / HTML `BGCOLOR`: a gradient
         * becomes the colour list "first:second" (pair it with gradient_attr()), anything
         * else is sanitize_color(). Borders, fonts and edges must keep sanitize_color: a
         * colour list there draws parallel lines instead of a gradient.
         */
        public static string fill_color(string color) {
            string first, second;
            int angle;
            if (parse_gradient(color, out first, out second, out angle)) {
                return first + ":" + second;
            }
            return sanitize_color(color);
        }

        /** Graphviz gradientangle of a gradient colour value, -1 for a plain colour. */
        public static int gradient_angle(string? color) {
            string first, second;
            int angle;
            if (!parse_gradient(color, out first, out second, out angle)) {
                return -1;
            }
            return angle;
        }

        /**
         * `, gradientangle=N` for a gradient colour, "" otherwise. Always explicit (also 0):
         * clusters inherit the root graph's gradientangle.
         */
        public static string gradient_attr(string? color) {
            int angle = gradient_angle(color);
            return angle < 0 ? "" : ", gradientangle=%d".printf(angle);
        }

        /** Graph/cluster statement form of gradient_attr(): "gradientangle=N;" or "". */
        public static string gradient_stmt(string? color) {
            int angle = gradient_angle(color);
            return angle < 0 ? "" : "gradientangle=%d;".printf(angle);
        }

        /** HTML-label attribute form: ` GRADIENTANGLE="N"` or "". */
        public static string gradient_html_attr(string? color) {
            int angle = gradient_angle(color);
            return angle < 0 ? "" : " GRADIENTANGLE=\"%d\"".printf(angle);
        }

        /**
         * Return a contrasting text color ("#000000" or "#FFFFFF") for the
         * given background hex color. Uses the W3C luminance formula.
         * Accepts "#RRGGBB", "RRGGBB", or named CSS colors (falls back
         * to white for unrecognized names).
         *
         * A gradient fill list from fill_color() ("red:green") uses the mean luminance of
         * its two colours: the label sits in the middle of the shape, where the gradient is
         * about half way, so the first colour alone can pick poorly readable text (white on
         * Gray-White, which is mostly light).
         */
        public static string contrast_text(string bg_color) {
            if (bg_color.contains(":")) {
                string[] stops = bg_color.split(":");
                double sum = 0.0;
                foreach (string stop in stops) {
                    double l = luminance(stop);
                    if (l < 0.0) {
                        return contrast_text(stops[0]);
                    }
                    sum += l;
                }
                return sum / stops.length > 0.55 ? "#000000" : "#FFFFFF";
            }
            string c = bg_color.strip().down();
            if (c == "transparent" || c == "#transparent" || c == "none" || c == "#none" || c.length == 0) {
                // No fill of its own: the text sits on the canvas
                return contrast_text_themed(bg_color, ThemeManager.get_active_palette().node_text);
            }
            double lum = luminance(bg_color);
            if (lum < 0.0) return "#FFFFFF";  // unknown → white
            return lum > 0.55 ? "#000000" : "#FFFFFF";
        }

        /**
         * contrast_text() for a caller that knows its theme's text colour: a background
         * that paints nothing ("transparent", "none", empty) or is mostly see-through
         * ("#RRGGBBAA" with alpha below 50%) gets `theme_text`, since the text then sits on
         * the canvas, not on the fill. White text on a light canvas was unreadable.
         */
        public static string contrast_text_themed(string bg_color, string theme_text) {
            string c = bg_color.strip().down();
            if (c.has_prefix("#")) {
                c = c.substring(1);
            }
            if (c == "transparent" || c == "none" || c.length == 0) {
                return theme_text;
            }
            if (c.length == 8 && is_hex_digits(c) && parse_hex_byte(c.substring(6, 2)) < 128) {
                return theme_text;
            }
            return contrast_text(bg_color);
        }

        // W3C luminance 0..1 of a hex or named colour, -1 when unrecognized
        private static double luminance(string bg_color) {
            string c = bg_color.strip();
            if (c.has_prefix("#")) c = c.substring(1);
            // "#FFF" short hex
            if (c.length == 3 && is_hex_digits(c)) {
                c = "%c%c%c%c%c%c".printf(c[0], c[0], c[1], c[1], c[2], c[2]);
            }
            // "#RRGGBBAA": the colour part (the alpha is contrast_text_themed's business)
            if (c.length == 8 && is_hex_digits(c)) {
                c = c.substring(0, 6);
            }

            // Named color lookup. A 6-letter name ("Yellow", "Maroon", "Silver") was read as
            // hex digits and gave a meaningless brightness.
            if (c.length != 6 || !is_hex_digits(c)) {
                c = named_color_to_hex(bg_color.strip());
            }
            if (c.length != 6 || !is_hex_digits(c)) return -1.0;

            int r = parse_hex_byte(c.substring(0, 2));
            int g = parse_hex_byte(c.substring(2, 2));
            int b = parse_hex_byte(c.substring(4, 2));
            return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        }

        /**
         * Edge label colour as PlantUML picks it: arrow FontColor (or ArrowFontColor), then
         * DefaultFontColor. Without either, a canvas colour set in the file gets a contrasting
         * colour, otherwise the palette's. Labels were black (state) or the palette's grey
         * (which is dark grey in the light palette) on a file's dark backgroundColor.
         * canvas_from_skin: false for renderers that do not paint the file's backgroundColor.
         */
        public static string edge_label_color(SkinParams skin, Palette palette, bool canvas_from_skin = true) {
            string? set_color = skin.get_element_property("arrow", "FontColor") ?? skin.default_font_color;
            if (set_color != null) {
                return sanitize_color(set_color);
            }
            if (canvas_from_skin && skin.background_color != null) {
                return contrast_text(sanitize_color(skin.background_color));
            }
            return palette.edge_text;
        }

        /**
         * Edge line colour: "skinparam arrow { Color }" or "skinparam ArrowColor", as PlantUML
         * 1.2026.1 applies it to every link; otherwise the palette's. The setting was ignored.
         */
        public static string edge_line_color(SkinParams skin, Palette palette) {
            string? set_color = skin.get_element_property("arrow", "Color");
            return set_color != null ? sanitize_color(set_color) : palette.edge_color;
        }

        /**
         * Title colour as PlantUML picks it: title FontColor (titleFontColor), then
         * DefaultFontColor. Without either, a canvas colour set in the file gets a contrasting
         * colour, otherwise the palette's text colour. The state title was black on a dark
         * backgroundColor; others used the palette's text colour, dark in the light palette.
         */
        public static string title_color(SkinParams skin, Palette palette, bool canvas_from_skin = true) {
            string? set_color = skin.get_element_property("title", "FontColor") ?? skin.default_font_color;
            if (set_color != null) {
                return sanitize_color(set_color);
            }
            if (canvas_from_skin && skin.background_color != null) {
                return contrast_text(sanitize_color(skin.background_color));
            }
            return palette.node_text;
        }

        private static bool is_hex_digits(string s) {
            if (s.length == 0) {
                return false;
            }
            for (int i = 0; i < s.length; i++) {
                if (!s[i].isxdigit()) {
                    return false;
                }
            }
            return true;
        }

        private static int parse_hex_byte(string s) {
            int v = 0;
            for (int i = 0; i < s.length && i < 2; i++) {
                v <<= 4;
                char ch = s[i];
                if (ch >= '0' && ch <= '9') v += ch - '0';
                else if (ch >= 'a' && ch <= 'f') v += 10 + ch - 'a';
                else if (ch >= 'A' && ch <= 'F') v += 10 + ch - 'A';
            }
            return v;
        }

        // All 147 CSS/SVG colour names, which PlantUML accepts. Only about 60 were listed, and
        // an unknown name gave white text, unreadable on light fills such as DarkSeaGreen,
        // YellowGreen or Tan.
        private static string named_color_to_hex(string name) {
            string n = name.down().replace("#", "");
            switch (n) {
                case "aliceblue": return "F0F8FF";
                case "antiquewhite": return "FAEBD7";
                case "aqua": return "00FFFF";
                case "aquamarine": return "7FFFD4";
                case "azure": return "F0FFFF";
                case "beige": return "F5F5DC";
                case "bisque": return "FFE4C4";
                case "black": return "000000";
                case "blanchedalmond": return "FFEBCD";
                case "blue": return "0000FF";
                case "blueviolet": return "8A2BE2";
                case "brown": return "A52A2A";
                case "burlywood": return "DEB887";
                case "cadetblue": return "5F9EA0";
                case "chartreuse": return "7FFF00";
                case "chocolate": return "D2691E";
                case "coral": return "FF7F50";
                case "cornflowerblue": return "6495ED";
                case "cornsilk": return "FFF8DC";
                case "crimson": return "DC143C";
                case "cyan": return "00FFFF";
                case "darkblue": return "00008B";
                case "darkcyan": return "008B8B";
                case "darkgoldenrod": return "B8860B";
                case "darkgray": case "darkgrey": return "A9A9A9";
                case "darkgreen": return "006400";
                case "darkkhaki": return "BDB76B";
                case "darkmagenta": return "8B008B";
                case "darkolivegreen": return "556B2F";
                case "darkorange": return "FF8C00";
                case "darkorchid": return "9932CC";
                case "darkred": return "8B0000";
                case "darksalmon": return "E9967A";
                case "darkseagreen": return "8FBC8F";
                case "darkslateblue": return "483D8B";
                case "darkslategray": case "darkslategrey": return "2F4F4F";
                case "darkturquoise": return "00CED1";
                case "darkviolet": return "9400D3";
                case "deeppink": return "FF1493";
                case "deepskyblue": return "00BFFF";
                case "dimgray": case "dimgrey": return "696969";
                case "dodgerblue": return "1E90FF";
                case "firebrick": return "B22222";
                case "floralwhite": return "FFFAF0";
                case "forestgreen": return "228B22";
                case "fuchsia": return "FF00FF";
                case "gainsboro": return "DCDCDC";
                case "ghostwhite": return "F8F8FF";
                case "gold": return "FFD700";
                case "goldenrod": return "DAA520";
                case "gray": case "grey": return "808080";
                case "green": return "008000";
                case "greenyellow": return "ADFF2F";
                case "honeydew": return "F0FFF0";
                case "hotpink": return "FF69B4";
                case "indianred": return "CD5C5C";
                case "indigo": return "4B0082";
                case "ivory": return "FFFFF0";
                case "khaki": return "F0E68C";
                case "lavender": return "E6E6FA";
                case "lavenderblush": return "FFF0F5";
                case "lawngreen": return "7CFC00";
                case "lemonchiffon": return "FFFACD";
                case "lightblue": return "ADD8E6";
                case "lightcoral": return "F08080";
                case "lightcyan": return "E0FFFF";
                case "lightgoldenrodyellow": return "FAFAD2";
                case "lightgray": case "lightgrey": return "D3D3D3";
                case "lightgreen": return "90EE90";
                case "lightpink": return "FFB6C1";
                case "lightsalmon": return "FFA07A";
                case "lightseagreen": return "20B2AA";
                case "lightskyblue": return "87CEFA";
                case "lightslategray": case "lightslategrey": return "778899";
                case "lightsteelblue": return "B0C4DE";
                case "lightyellow": return "FFFFE0";
                case "lime": return "00FF00";
                case "limegreen": return "32CD32";
                case "linen": return "FAF0E6";
                case "magenta": return "FF00FF";
                case "maroon": return "800000";
                case "mediumaquamarine": return "66CDAA";
                case "mediumblue": return "0000CD";
                case "mediumorchid": return "BA55D3";
                case "mediumpurple": return "9370DB";
                case "mediumseagreen": return "3CB371";
                case "mediumslateblue": return "7B68EE";
                case "mediumspringgreen": return "00FA9A";
                case "mediumturquoise": return "48D1CC";
                case "mediumvioletred": return "C71585";
                case "midnightblue": return "191970";
                case "mintcream": return "F5FFFA";
                case "mistyrose": return "FFE4E1";
                case "moccasin": return "FFE4B5";
                case "navajowhite": return "FFDEAD";
                case "navy": return "000080";
                case "oldlace": return "FDF5E6";
                case "olive": return "808000";
                case "olivedrab": return "6B8E23";
                case "orange": return "FFA500";
                case "orangered": return "FF4500";
                case "orchid": return "DA70D6";
                case "palegoldenrod": return "EEE8AA";
                case "palegreen": return "98FB98";
                case "paleturquoise": return "AFEEEE";
                case "palevioletred": return "DB7093";
                case "papayawhip": return "FFEFD5";
                case "peachpuff": return "FFDAB9";
                case "peru": return "CD853F";
                case "pink": return "FFC0CB";
                case "plum": return "DDA0DD";
                case "powderblue": return "B0E0E6";
                case "purple": return "800080";
                case "rebeccapurple": return "663399";
                case "red": return "FF0000";
                case "rosybrown": return "BC8F8F";
                case "royalblue": return "4169E1";
                case "saddlebrown": return "8B4513";
                case "salmon": return "FA8072";
                case "sandybrown": return "F4A460";
                case "seagreen": return "2E8B57";
                case "seashell": return "FFF5EE";
                case "sienna": return "A0522D";
                case "silver": return "C0C0C0";
                case "skyblue": return "87CEEB";
                case "slateblue": return "6A5ACD";
                case "slategray": case "slategrey": return "708090";
                case "snow": return "FFFAFA";
                case "springgreen": return "00FF7F";
                case "steelblue": return "4682B4";
                case "tan": return "D2B48C";
                case "teal": return "008080";
                case "thistle": return "D8BFD8";
                case "tomato": return "FF6347";
                case "turquoise": return "40E0D0";
                case "violet": return "EE82EE";
                case "wheat": return "F5DEB3";
                case "white": return "FFFFFF";
                case "whitesmoke": return "F5F5F5";
                case "yellow": return "FFFF00";
                case "yellowgreen": return "9ACD32";
                default: return name;  // might be hex without #
            }
        }

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

        // Escape label for DOT record shapes (also escapes <, >, {, })
        public static string escape_record_label(string? s) {
            if (s == null || s.length == 0) {
                return "";
            }

            if (!s.validate()) {
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

            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                if (c == '\\') {
                    if (i < s.length) {
                        unichar next;
                        int next_i = i;
                        if (s.get_next_char(ref next_i, out next) && next == 'n') {
                            sb.append("\\n");
                            i = next_i;
                            continue;
                        }
                    }
                    sb.append("\\\\");
                } else if (c == '"') {
                    sb.append("\\\"");
                } else if (c == '\n') {
                    sb.append("\\n");
                } else if (c == '<') {
                    sb.append("\\<");
                } else if (c == '>') {
                    sb.append("\\>");
                } else if (c == '{') {
                    sb.append("\\{");
                } else if (c == '}') {
                    sb.append("\\}");
                } else {
                    sb.append_unichar(c);
                }
            }

            return sb.str;
        }

        // Sanitize identifier for DOT
        public static string sanitize_id(string? id) {
            // Nullable to avoid a g_return_val_if_fail precondition abort
            // when callers pass `node.alias ?? node.name` with both null
            // (shouldn't happen in practice but is defensive).
            if (id == null || id.length == 0) {
                return "_empty";
            }

            // Convert name to valid DOT identifier
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (id.get_next_char(ref i, out c)) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_' || (c > 127 && c.isalnum())) {
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
            // DOT keywords can't be node IDs: "node [label=...]" is a default
            // attribute statement, so an element named "node" vanished and restyled
            // every node after it. A keyword gets one more "_", and so does a keyword that
            // already ends in underscores ("node_" -> "node__"), so "node" and "node_" stay
            // two ids; any other id is unchanged.
            int base_len = result.length;
            while (base_len > 0 && result[base_len - 1] == '_') {
                base_len--;
            }
            switch (result.substring(0, base_len).down()) {
                case "node":
                case "edge":
                case "graph":
                case "digraph":
                case "subgraph":
                case "strict":
                    result = result + "_";
                    break;
                default:
                    break;
            }
            return result.length > 0 ? result : "_empty";
        }

        // Check if string has Creole formatting or embedded newlines
        public static bool has_creole_formatting(string? s) {
            if (s == null) return false;
            return s.contains("**") || s.contains("//") || s.contains("__") ||
                   s.contains("--") || s.contains("~~") || s.contains("\n");
        }

        // Convert Creole formatting to Graphviz HTML-like labels
        public static string convert_creole_to_html(string? s) {
            if (s == null || s.length == 0) {
                return "";
            }
            // Convert Creole formatting to Graphviz HTML-like label format
            string result = s;
            string? temp;

            // Escape HTML special characters BEFORE inserting any HTML tags,
            // so that user text like "a->b" becomes "a-&gt;b" and doesn't
            // break the label=<...> HTML context.  Order matters: & must be
            // first to avoid double-escaping.
            temp = result.replace("&", "&amp;");
            if (temp != null) result = temp;
            temp = result.replace("<", "&lt;");
            if (temp != null) result = temp;
            temp = result.replace(">", "&gt;");
            if (temp != null) result = temp;

            // Now insert HTML line-break tags.  Plain text is already escaped
            // so these <BR/> tags are the only raw HTML in the string.
            temp = result.replace("\n", "<BR/>");
            if (temp != null) result = temp;

            // Convert legacy \n escape sequences to <BR/>
            temp = result.replace("\\n", "<BR/>");
            if (temp != null) result = temp;

            // Note: Graphviz HTML labels should preserve regular spaces
            // Remove the &#160; conversion as it may not be supported

            // Convert Creole markers to HTML tags using regex
            try {
                // Bold: **text** - trim spaces around captured text
                Regex bold_re = new Regex("\\*\\*\\s*(.+?)\\s*\\*\\*");
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

            // Don't wrap in TABLE - let caller handle table wrapping for consistent sizing
            // (Wrapping here causes height issues with nested tables)
            return result;
        }

        // Shared SVG-to-surface rendering: creates a Cairo ImageSurface from SVG data
        public static Cairo.ImageSurface? svg_to_surface(uint8[] svg_data) {
            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        /**
         * Run a Graphviz layout engine subprocess on `dot_source` and
         * return the generated SVG bytes, or null on failure.
         *
         * Uses secure unique temp files (mkstemp-style) — no race or
         * symlink-attack risk, and safe for concurrent calls from
         * multiple tabs. Replaces the old pattern of writing to
         * hardcoded `/tmp/gplantuml_*.dot` paths.
         */
        public static uint8[]? run_graphviz_subprocess(string dot_source, string engine, string suffix) {
            string tmp_dot = "";
            string tmp_svg = "";
            try {
                // Create unique temp paths using mkstemp semantics.
                // FileUtils.open_tmp atomically creates the file with
                // O_EXCL | O_CREAT, defeating symlink attacks.
                int fd_dot = FileUtils.open_tmp(
                    "gdiagram_%s_XXXXXX.dot".printf(suffix),
                    out tmp_dot);
                if (fd_dot < 0) return null;
                // Wrap the fd in a FileStream so it closes when the
                // variable goes out of scope (via the `using` idiom).
                // We only needed the path; the content is written via
                // FileUtils.set_contents below.
                FileStream.fdopen(fd_dot, "w");

                int fd_svg = FileUtils.open_tmp(
                    "gdiagram_%s_XXXXXX.svg".printf(suffix),
                    out tmp_svg);
                if (fd_svg < 0) {
                    FileUtils.unlink(tmp_dot);
                    return null;
                }
                FileStream.fdopen(fd_svg, "w");

                FileUtils.set_contents(tmp_dot, dot_source);

                // -Gfontname: graph/cluster titles default to Sans, not Graphviz's serif Times
                string[] argv = {engine, "-Gfontname=Sans", "-Tsvg", "-o", tmp_svg, tmp_dot};
                int exit_status;
                Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH,
                    null, null, null, out exit_status);

                if (exit_status != 0) {
                    warning("Graphviz %s returned error %d", engine, exit_status);
                    FileUtils.unlink(tmp_dot);
                    FileUtils.unlink(tmp_svg);
                    return null;
                }

                uint8[] svg_data;
                FileUtils.get_data(tmp_svg, out svg_data);
                FileUtils.unlink(tmp_dot);
                FileUtils.unlink(tmp_svg);
                return fill_svg_background(svg_data);
            } catch (Error e) {
                warning("Graphviz subprocess (%s) failed: %s", suffix, e.message);
                if (tmp_dot.length > 0) FileUtils.unlink(tmp_dot);
                if (tmp_svg.length > 0) FileUtils.unlink(tmp_svg);
                return null;
            }
        }

        /**
         * Edge attribute text marking circle-plus ends for draw_custom_markers():
         * `, class="gdplus gdplustail", arrowsize=1.3` etc. Naming the end lets the plus go
         * into the right circle when the other end is a plain circle too ("0--+"); the
         * placeholder arrow on a "+" end must be odot. "" when neither end is a plus.
         */
        public static string plus_marker_class(bool tail, bool head) {
            if (!tail && !head) {
                return "";
            }
            return ", class=\"gdplus%s%s\", arrowsize=1.3".printf(tail ? " gdplustail" : "", head ? " gdplushead" : "");
        }

        // Graphviz has no circle-plus ("+--") or cross ("x--") arrow shape. Edges with those
        // ends carry class "gdplus" / "gdcross" and an odot / obox placeholder; this draws the
        // real marker over it: a plus inside the odot circle, and an x replacing the obox with
        // the line running on through it to the node, as PlantUML draws them. No hyphen in the
        // class names: Graphviz writes "-" as "&#45;" in SVG.
        public static uint8[] draw_custom_markers(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            if (!svg.contains("edge gdplus") && !svg.contains("edge gdcross")) {
                return svg_data;
            }
            try {
                // Each gdplus edge group: the plus goes into the circle of the "+" end. Graphviz
                // writes the tail arrow before the head arrow, so "gdplustail" is the first
                // ellipse and "gdplushead" the last. A bare "gdplus" does not say which end
                // is the "+": every hollow circle gets one ("A +--+ B" had only the first).
                var group = new Regex(
                    "(class=\"edge (gdplus[^\"]*)\">)((?:(?!</g>).)*?)(</g>)",
                    RegexCompileFlags.DOTALL);
                var ellipse = new Regex(
                    "<ellipse ([^>]*?)cx=\"([-0-9.]+)\" cy=\"([-0-9.]+)\" rx=\"([-0-9.]+)\" ry=\"([-0-9.]+)\"/>");
                svg = group.replace_eval(svg, -1, 0, 0, (gm, result) => {
                    string classes = gm.fetch(2);
                    string body = gm.fetch(3);
                    bool tail = classes.contains("gdplustail");
                    bool head = classes.contains("gdplushead");
                    var starts = new Gee.ArrayList<int>();
                    var ends = new Gee.ArrayList<int>();
                    var marks = new Gee.ArrayList<string>();
                    var hollow = new Gee.ArrayList<bool>();
                    MatchInfo em;
                    ellipse.match(body, 0, out em);
                    while (em.matches()) {
                        int es, ee;
                        em.fetch_pos(0, out es, out ee);
                        double cx = double.parse(em.fetch(2));
                        double cy = double.parse(em.fetch(3));
                        double rx = double.parse(em.fetch(4));
                        double ry = double.parse(em.fetch(5));
                        starts.add(es);
                        ends.add(ee);
                        hollow.add(em.fetch(1).contains("fill=\"none\""));
                        marks.add("\n<path class=\"gdmark\" %sd=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/>".printf(
                            em.fetch(1),
                            (cx - rx).to_string(), cy.to_string(), (cx + rx).to_string(), cy.to_string(),
                            cx.to_string(), (cy - ry).to_string(), cx.to_string(), (cy + ry).to_string()));
                        try {
                            em.next();
                        } catch (RegexError e) {
                            break;
                        }
                    }
                    var out_body = new StringBuilder();
                    int copied = 0;
                    for (int k = 0; k < starts.size; k++) {
                        bool mark;
                        if (tail || head) {
                            mark = (tail && k == 0) || (head && k == starts.size - 1);
                        } else {
                            mark = hollow[k];
                        }
                        if (!mark) {
                            continue;
                        }
                        out_body.append(body.substring(copied, ends[k] - copied));
                        out_body.append(marks[k]);
                        copied = ends[k];
                    }
                    out_body.append(body.substring(copied));
                    result.append(gm.fetch(1));
                    result.append(out_body.str);
                    result.append(gm.fetch(4));
                    return false;
                });

                var cross = new Regex(
                    "(class=\"edge gdcross\">(?:(?!</g>).)*?)<polygon ([^>]*?)points=\"([^\"]*)\"/>(\\s*<polyline [^>]*?points=\"([-0-9.]+),([-0-9.]+) [^\"]*\"/>)?",
                    RegexCompileFlags.DOTALL);
                svg = cross.replace_eval(svg, -1, 0, 0, (m, result) => {
                    string[] pts = m.fetch(3).strip().split(" ");
                    if (pts.length < 4) {
                        result.append(m.fetch(0));
                        return false;
                    }
                    double[] xs = new double[4];
                    double[] ys = new double[4];
                    for (int i = 0; i < 4; i++) {
                        string[] xy = pts[i].split(",");
                        if (xy.length != 2) {
                            result.append(m.fetch(0));
                            return false;
                        }
                        xs[i] = double.parse(xy[0]);
                        ys[i] = double.parse(xy[1]);
                    }
                    var d = new StringBuilder();
                    d.append("M%s,%s L%s,%s M%s,%s L%s,%s".printf(
                        xs[0].to_string(), ys[0].to_string(), xs[2].to_string(), ys[2].to_string(),
                        xs[1].to_string(), ys[1].to_string(), xs[3].to_string(), ys[3].to_string()));
                    string? stub = m.fetch(4);
                    string? sx = m.fetch(5);
                    string? sy = m.fetch(6);
                    if (sx != null && sx.length > 0 && sy != null && sy.length > 0) {
                        // The stub starts on the box side facing the line; mirror it through
                        // the centre so the line reaches the node
                        double cx = (xs[0] + xs[2]) / 2;
                        double cy = (ys[0] + ys[2]) / 2;
                        double x0 = double.parse(sx);
                        double y0 = double.parse(sy);
                        d.append(" M%s,%s L%s,%s".printf(
                            x0.to_string(), y0.to_string(), (2 * cx - x0).to_string(), (2 * cy - y0).to_string()));
                    }
                    result.append(m.fetch(1));
                    result.append("<path class=\"gdmark\" %sd=\"%s\"/>".printf(m.fetch(2), d.str));
                    if (stub != null) {
                        result.append(stub);
                    }
                    return false;
                });
            } catch (RegexError e) {
                warning("Failed to draw custom arrow markers: %s", e.message);
                return svg_data;
            }
            return svg.data;
        }

        // Use-case actor stick figures and business "/" markers, drawn over their placeholders
        // (see UseCaseDiagramRenderer.actor_node): the sentinel cell (fill #010203) inside a
        // "gdactor" node becomes head, body, arms and legs; "gdbusiness" adds a slash through
        // the head, or near the right edge of a use-case ellipse. Graphviz has no such shapes.
        public static uint8[] draw_actor_figures(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            if (!svg.contains("node gdactor") && !svg.contains("node gdbusiness")) {
                return svg_data;
            }
            try {
                var actor = new Regex(
                    "(class=\"node gdactor gdfill_([A-Za-z0-9]+) gdstroke_([A-Za-z0-9]+)((?: gd(?:business|awesome|hollow|bold))*)\">(?:(?!</g>).)*?)<polygon fill=\"#010203\" stroke=\"none\" points=\"([^\"]*)\"/>",
                    RegexCompileFlags.DOTALL);
                svg = actor.replace_eval(svg, -1, 0, 0, (m, result) => {
                    double minx = double.MAX;
                    double miny = double.MAX;
                    double maxx = -double.MAX;
                    double maxy = -double.MAX;
                    foreach (string pt in m.fetch(5).strip().split(" ")) {
                        string[] xy = pt.split(",");
                        if (xy.length != 2) {
                            continue;
                        }
                        double x = double.parse(xy[0]);
                        double y = double.parse(xy[1]);
                        minx = double.min(minx, x);
                        maxx = double.max(maxx, x);
                        miny = double.min(miny, y);
                        maxy = double.max(maxy, y);
                    }
                    result.append(m.fetch(1));
                    if (minx > maxx || miny > maxy) {
                        return false;
                    }
                    // Paint attributes: `fill="#FF0000" fill-opacity="0.502"` for "#FF000080"
                    string fill = svg_paint("fill", m.fetch(2));
                    string stroke = svg_paint("stroke", m.fetch(3));
                    double h = maxy - miny;
                    double cx = (minx + maxx) / 2;
                    double r = h * 0.14;
                    double head_y = miny + r + 1;
                    double neck = head_y + r;
                    double hip = miny + h * 0.64;
                    double arm_y = neck + h * 0.12;
                    double half_arm = h * 0.28;
                    double foot = maxy - 1;
                    double half_leg = h * 0.24;
                    string? flag_text = m.fetch(4);
                    string flags = flag_text != null ? flag_text : "";
                    // The head drawn last: a business actor lightens it and puts the slash on it
                    double head_cx = cx;
                    double head_cy = head_y;
                    double head_r = r;
                    size_t figure_start = result.len;
                    if (flags.contains("gdawesome")) {
                        // "skinparam actorStyle awesome": a head over a rounded, filled bust
                        double ar = h * 0.2;
                        double ahead = miny + ar + 1;
                        double sh = ahead + ar + h * 0.05;
                        double w = h * 0.36;
                        double rr = h * 0.14;
                        head_cy = ahead;
                        head_r = ar;
                        result.append("<circle class=\"gdfigure\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s %s stroke-width=\"1.3\"/>".printf(
                            cx.to_string(), ahead.to_string(), ar.to_string(), fill, stroke));
                        result.append("<path class=\"gdfigure gdawesome\" %s %s stroke-width=\"1.3\" d=\"M%s,%s L%s,%s Q%s,%s %s,%s L%s,%s Q%s,%s %s,%s L%s,%s Z\"/>".printf(
                            fill, stroke,
                            (cx - w).to_string(), foot.to_string(), (cx - w).to_string(), (sh + rr).to_string(),
                            (cx - w).to_string(), sh.to_string(), (cx - w + rr).to_string(), sh.to_string(),
                            (cx + w - rr).to_string(), sh.to_string(),
                            (cx + w).to_string(), sh.to_string(), (cx + w).to_string(), (sh + rr).to_string(),
                            (cx + w).to_string(), foot.to_string()));
                    } else if (flags.contains("gdhollow")) {
                        // "skinparam actorStyle hollow": an outlined, filled star-shaped figure
                        double t = h * 0.07;
                        double n = h * 0.07;
                        double arm = h * 0.34;
                        double leg = h * 0.26;
                        result.append("<circle class=\"gdfigure\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s %s stroke-width=\"1.3\"/>".printf(
                            cx.to_string(), head_y.to_string(), r.to_string(), fill, stroke));
                        double[] px = { cx - n, cx - arm, cx - arm, cx - n, cx - n, cx - leg - t, cx - leg + t, cx,
                                        cx + leg - t, cx + leg + t, cx + n, cx + n, cx + arm, cx + arm, cx + n };
                        double[] py = { neck, arm_y - t, arm_y + t, arm_y + t, hip, foot, foot, hip + t * 1.5,
                                        foot, foot, hip, arm_y + t, arm_y + t, arm_y - t, neck };
                        var pts = new StringBuilder();
                        for (int i = 0; i < px.length; i++) {
                            if (i > 0) {
                                pts.append(" ");
                            }
                            pts.append("%s,%s".printf(px[i].to_string(), py[i].to_string()));
                        }
                        result.append("<polygon class=\"gdfigure gdhollow\" %s %s stroke-width=\"1.3\" points=\"%s\"/>".printf(
                            fill, stroke, pts.str));
                    } else {
                        result.append("<circle class=\"gdfigure\" cx=\"%s\" cy=\"%s\" r=\"%s\" %s %s stroke-width=\"1.3\"/>".printf(
                            cx.to_string(), head_y.to_string(), r.to_string(), fill, stroke));
                        var d = new StringBuilder();
                        d.append("M%s,%s L%s,%s".printf(cx.to_string(), neck.to_string(), cx.to_string(), hip.to_string()));
                        d.append(" M%s,%s L%s,%s".printf((cx - half_arm).to_string(), arm_y.to_string(),
                                                         (cx + half_arm).to_string(), arm_y.to_string()));
                        d.append(" M%s,%s L%s,%s L%s,%s".printf((cx - half_leg).to_string(), foot.to_string(),
                                                               cx.to_string(), hip.to_string(),
                                                               (cx + half_leg).to_string(), foot.to_string()));
                        result.append("<path class=\"gdfigure\" fill=\"none\" %s stroke-width=\"1.3\" d=\"%s\"/>".printf(stroke, d.str));
                    }
                    if (flags.contains("gdbusiness")) {
                        // PlantUML's business actor has a light head crossed by a dark slash. The
                        // slash was drawn in the stroke colour over the filled head (often the
                        // same dark colour), so it did not show.
                        result.append("<circle class=\"gdbizhead\" cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#FFFFFF\" fill-opacity=\"0.75\" stroke=\"none\"/>".printf(
                            head_cx.to_string(), head_cy.to_string(), (head_r - 0.65).to_string()));
                        double k = head_r * 0.72;
                        result.append("<path class=\"gdslash\" fill=\"none\" stroke=\"#333333\" stroke-width=\"1.3\" d=\"M%s,%s L%s,%s\"/>".printf(
                            (head_cx - k).to_string(), (head_cy + k).to_string(), (head_cx + k).to_string(), (head_cy - k).to_string()));
                    }
                    if (flags.contains("gdbold")) {
                        // "line.bold" in an inline style: a heavier figure
                        string figure = result.str.substring((long) figure_start).replace(
                            "stroke-width=\"1.3\"", "stroke-width=\"2.4\"");
                        result.truncate(figure_start);
                        result.append(figure);
                    }
                    return false;
                });

                var business = new Regex(
                    "class=\"node gdbusiness\">(?:(?!</g>).)*?<ellipse ([^>]*?)cx=\"([-0-9.]+)\" cy=\"([-0-9.]+)\" rx=\"([-0-9.]+)\" ry=\"([-0-9.]+)\"/>",
                    RegexCompileFlags.DOTALL);
                svg = business.replace_eval(svg, -1, 0, 0, (m, result) => {
                    double cx = double.parse(m.fetch(2));
                    double cy = double.parse(m.fetch(3));
                    double rx = double.parse(m.fetch(4));
                    double ry = double.parse(m.fetch(5));
                    string attrs = m.fetch(1);
                    string stroke = "#000000";
                    int si = attrs.index_of("stroke=\"");
                    if (si >= 0) {
                        int se = attrs.index_of("\"", si + 8);
                        if (se > si + 8) {
                            stroke = attrs.substring(si + 8, se - si - 8);
                        }
                    }
                    result.append(m.fetch(0));
                    result.append("\n<path class=\"gdslash\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.3\" d=\"M%s,%s L%s,%s\"/>".printf(
                        stroke, (cx + rx * 0.45).to_string(), (cy + ry * 0.89).to_string(),
                        (cx + rx * 0.89).to_string(), (cy - ry * 0.45).to_string()));
                    return false;
                });
            } catch (RegexError e) {
                warning("Failed to draw actor figures: %s", e.message);
                return svg_data;
            }
            return svg.data;
        }

        // DOT node attributes for an actor figure: an HTML label whose sentinel cell (#010203)
        // draw_actor_figures replaces with the figure. `above_html` (optional) and `below_html`
        // are escaped HTML; `extra_classes` adds " gdbusiness", " gdawesome" or " gdhollow".
        public static string actor_figure_attrs(string? above_html, string below_html, string fill, string stroke,
                                                string extra_classes, string? font_color) {
            string open_font = font_color != null ? "<FONT COLOR=\"%s\">".printf(font_color) : "";
            string close_font = font_color != null ? "</FONT>" : "";
            var rows = new StringBuilder();
            if (above_html != null) {
                rows.append("<TR><TD>%s%s%s</TD></TR>".printf(open_font, above_html, close_font));
            }
            rows.append("<TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"30\" HEIGHT=\"46\" BGCOLOR=\"#010203\"> </TD></TR>");
            rows.append("<TR><TD>%s%s%s</TD></TR>".printf(open_font, below_html, close_font));
            return "shape=none, class=\"gdactor gdfill_%s gdstroke_%s%s\", style=\"solid\", label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"1\">%s</TABLE>>".printf(
                class_color_token(fill), class_color_token(stroke), extra_classes, rows.str);
        }

        // A colour as a class-name token: "#0A4A89" -> "0A4A89", "Gold" -> "Gold",
        // "#FF000080" -> "FF000080". A gradient ("#red-blue", the fill list "red:blue")
        // gives its first colour, and line/text styling after ";" is dropped: the tokens
        // of a whole gradient ran together into "redblue", which is no colour.
        public static string class_color_token(string color) {
            string c = color.strip();
            int semi = c.index_of_char(';');
            if (semi >= 0) {
                c = c.substring(0, semi);
            }
            string lower = c.down();
            if (lower.has_prefix("#back:") || lower.has_prefix("back:")) {
                c = c.substring(c.index_of_char(':') + 1);
            }
            int colon = c.index_of_char(':');
            if (colon > 0) {
                c = c.substring(0, colon);
            }
            string first, second;
            int angle;
            if (parse_gradient(c, out first, out second, out angle)) {
                c = first;
            }
            var sb = new StringBuilder();
            for (int i = 0; i < c.length; i++) {
                if (c[i].isalnum()) {
                    sb.append_c(c[i]);
                }
            }
            return sb.len > 0 ? sb.str : "000000";
        }

        // Class-name colour token back to an SVG paint attribute (`attr` is "fill" or
        // "stroke"): hex digits get "#", 8 hex digits split into the colour and an
        // `-opacity`, "transparent" is "none", names stay
        private static string svg_paint(string attr, string token) {
            string value = token;
            string opacity = "";
            if ((token.length == 6 || token.length == 3) && is_hex_digits(token)) {
                value = "#" + token;
            } else if (token.length == 8 && is_hex_digits(token)) {
                value = "#" + token.substring(0, 6);
                double alpha = parse_hex_byte(token.substring(6, 2)) / 255.0;
                opacity = " %s-opacity=\"%s\"".printf(attr, "%.3f".printf(alpha).replace(",", "."));
            } else if (token.down() == "transparent") {
                value = "none";
            }
            return "%s=\"%s\"%s".printf(attr, value, opacity);
        }

        // Shared SVG file export: writes SVG data to a file
        public static bool write_svg_to_file(uint8[] svg_data, string filename) {
            try {
                var file = File.new_for_path(filename);
                var stream = file.replace(null, false, FileCreateFlags.NONE);
                stream.write_all(svg_data, null);
                stream.close();
                return true;
            } catch (Error e) {
                warning("Failed to write SVG: %s", e.message);
                return false;
            }
        }

        // Shared PDF export: renders SVG data to a PDF file
        public static bool export_svg_to_pdf(uint8[] svg_data, string filename) {
            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.PdfSurface(filename, width, height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                surface.finish();

                return surface.status() == Cairo.Status.SUCCESS;
            } catch (Error e) {
                warning("Failed to export PDF: %s", e.message);
                return false;
            }
        }

        // Parse SVG to extract element bounding boxes for click navigation
        // surface_width/height are optional - if provided, coordinates will be scaled from SVG units to pixels
        public static void parse_svg_regions(uint8[] svg_data, Gee.ArrayList<ElementRegion> regions,
                                             Gee.HashMap<string, int>? element_lines = null,
                                             double surface_width = 0, double surface_height = 0) {
            regions.clear();

            // Guard against zero-length input. `(string) svg_data` on an
            // empty uint8[] is effectively a null/zero-length C string; any
            // further operation on it would segfault.
            if (svg_data.length == 0) return;

            // Bit-exact copy of the svg byte array into a Vala string.
            // Two failure modes we guard against:
            //   1. `(string) svg_data` calls strlen, which reads *past* the
            //      array if there's no trailing NUL — producing a Vala
            //      `length` longer than `svg_data.length`. GRegex then sees
            //      garbage tail bytes and silently refuses to match.
            //   2. `svg_data` contains an embedded NUL, so strlen returns
            //      a length *shorter* than `svg_data.length`. Calling
            //      `raw.substring(0, svg_data.length)` in that case runs
            //      past the terminator and trips a g_critical in
            //      `string_substring`, aborting the process.
            // Use the *minimum* of the two lengths as the safe bound.
            string svg_str;
            unowned string raw = (string) svg_data;
            int safe_len = int.min(raw.length, (int) svg_data.length);
            if (raw.length == svg_data.length) {
                svg_str = raw;
            } else {
                svg_str = raw.substring(0, safe_len);
            }

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
                        if (min_x >= double.MAX || max_x <= -double.MAX) {
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
