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
         * Return a contrasting text color ("#000000" or "#FFFFFF") for the
         * given background hex color. Uses the W3C luminance formula.
         * Accepts "#RRGGBB", "RRGGBB", or named CSS colors (falls back
         * to white for unrecognized names).
         */
        public static string contrast_text(string bg_color) {
            string c = bg_color.strip();
            if (c.has_prefix("#")) c = c.substring(1);

            // Named color lookup (common palette colors)
            if (c.length != 6) {
                c = named_color_to_hex(bg_color.strip());
            }
            if (c.length != 6) return "#FFFFFF";  // unknown → white

            int r = parse_hex_byte(c.substring(0, 2));
            int g = parse_hex_byte(c.substring(2, 2));
            int b = parse_hex_byte(c.substring(4, 2));
            double lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
            return lum > 0.55 ? "#000000" : "#FFFFFF";
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

        private static string named_color_to_hex(string name) {
            string n = name.down().replace("#", "");
            switch (n) {
                case "red":     return "FF0000";
                case "green":   return "008000";
                case "blue":    return "0000FF";
                case "yellow":  return "FFFF00";
                case "orange":  return "FFA500";
                case "white":   return "FFFFFF";
                case "black":   return "000000";
                case "gray": case "grey": return "808080";
                case "pink":    return "FFC0CB";
                case "purple":  return "800080";
                case "cyan":    return "00FFFF";
                case "magenta": return "FF00FF";
                case "gold":    return "FFD700";
                case "coral":   return "FF7F50";
                case "salmon":  return "FA8072";
                case "lime":    return "00FF00";
                case "teal":    return "008080";
                case "navy":    return "000080";
                case "maroon":  return "800000";
                case "olive":   return "808000";
                default:        return name;  // might be hex without #
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

                string[] argv = {engine, "-Tsvg", "-o", tmp_svg, tmp_dot};
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
                return svg_data;
            } catch (Error e) {
                warning("Graphviz subprocess (%s) failed: %s", suffix, e.message);
                if (tmp_dot.length > 0) FileUtils.unlink(tmp_dot);
                if (tmp_svg.length > 0) FileUtils.unlink(tmp_svg);
                return null;
            }
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
