/* ChartDiagramParser.vala — parser for PlantUML's @startchart diagram type
 *
 * @startchart is a line-based grammar: PlantUML implements every command as a
 * SingleLineCommand2 whose regex is built in its `getRegexConcat()`. The
 * regexes below are those, transcribed from the 1.2026.8 command classes
 * (net.sourceforge.plantuml.chart.command), so a document that PlantUML
 * accepts is accepted here and one it rejects produces a ParseError.
 *
 * Two details worth keeping: every part after a command keyword is optional
 * except a series' `[data]`, and `bar` has no `v2` modifier — only line, area
 * and scatter can plot against the secondary axis. CommandChartGrid exists in
 * the jar but is NOT registered by ChartDiagramFactory, so `grid` is only ever
 * a trailing flag on an axis command, never a statement of its own.
 */
namespace GDiagram {

    public class ChartDiagramParser : Object {
        // A chart may not carry an unbounded number of series or values: a
        // mistyped data list should not hang the preview while the user types.
        public const int MAX_SERIES = 200;
        public const int MAX_VALUES = 2000;

        private Regex? x_axis_re = null;
        private Regex? y_axis_re = null;
        private Regex? series_re = null;
        private Regex? legend_re = null;
        private Regex? stack_re = null;
        private Regex? orient_re = null;
        private Regex? annotation_re = null;
        private Regex? tick_re = null;

        private const string TITLE_PART = """(?:"([^"]+)")?\s*""";
        private const string RANGE_PART = """(?:(-?[0-9.]+)\s*-?->\s*(-?[0-9.]+))?\s*""";

        public ChartDiagramParser() {
            try {
                // [hx]-axis ["title"] [min --> max] [[cats]] [spacing N] [label-right] [grid]
                x_axis_re = new Regex(
                    """^[hx]-axis\s*""" + TITLE_PART + RANGE_PART +
                    """(?:\[(.*?)\])?\s*(?:spacing\s+([0-9]+))?\s*(label-right)?\s*(grid)?$""",
                    RegexCompileFlags.CASELESS);
                // [vy]2?-axis ["title"] [min --> max] [[cats]] [ticks [...]]
                //             [spacing N] [label-top] [grid]
                y_axis_re = new Regex(
                    """^([vy]2?)-axis\s*""" + TITLE_PART + RANGE_PART +
                    """(?:\[([^\]]*)\])?\s*(?:ticks\s+\[(.*?)\])?\s*""" +
                    """(?:spacing\s+([0-9.]+))?\s*(label-top)?\s*(grid)?$""",
                    RegexCompileFlags.CASELESS);
                // bar|line|area|scatter [<<stereo>>] ["name"] [data] [#color]
                //                       [v2] [labels] [<<marker>>]
                // `bar` accepts no v2; that is enforced after the match so the
                // error names the real problem instead of "unrecognized line".
                series_re = new Regex(
                    """^(bar|line|area|scatter)\s*(?:<<([^>]+?)>>)?\s*""" + TITLE_PART +
                    """\[(.*?)\]\s*(?:#([0-9a-fA-F]{6}|[0-9a-fA-F]{3}|\w+))?\s*""" +
                    """(?:\s([vy]2))?\s*(?:\s(labels))?\s*(?:<<(circle|square|triangle)>>)?$""",
                    RegexCompileFlags.CASELESS);
                legend_re = new Regex("""^legend\s+(left|right|top|bottom)$""",
                                      RegexCompileFlags.CASELESS);
                stack_re = new Regex("""^stackmode\s+(grouped|stacked)$""",
                                     RegexCompileFlags.CASELESS);
                orient_re = new Regex("""^orientation\s+(vertical|horizontal)$""",
                                      RegexCompileFlags.CASELESS);
                annotation_re = new Regex(
                    """^annotation\s+"([^"]+)"\s+at\s*\(\s*([^,]+?)\s*,\s*([^)]+?)\s*\)\s*(?:<<(arrow)>>)?$""",
                    RegexCompileFlags.CASELESS);
                // One `value:"label"` pair of a `ticks [...]` list.
                tick_re = new Regex("""^(-?[0-9.]+)\s*:\s*"([^"]*)"$""");
            } catch (RegexError e) {
                warning("ChartDiagramParser: bad regex: %s", e.message);
            }
        }

        public ChartDiagram parse(string source) {
            var d = new ChartDiagram();
            if (series_re == null) {
                return d;
            }

            string[] lines = source.split("\n");
            bool in_title_block = false;
            var title_block = new StringBuilder();

            for (int i = 0; i < lines.length; i++) {
                string line = lines[i].strip();
                int line_no = i + 1;

                // `title` ... `end title` spans lines, so it is handled before
                // anything else can claim one of its body lines.
                if (in_title_block) {
                    if (line.down() == "end title") {
                        d.title = title_block.str.strip();
                        in_title_block = false;
                    } else {
                        if (title_block.len > 0) title_block.append("\n");
                        title_block.append(line);
                    }
                    continue;
                }

                if (line.length == 0 || line.has_prefix("'") || line.has_prefix("@")
                    || line.has_prefix("/'") || line.has_prefix("!")) {
                    continue;
                }
                // Styling commands carry no chart data; PlantUML accepts them on
                // any diagram and so do we, by ignoring them.
                string lower = line.down();
                if (lower.has_prefix("skinparam") || lower.has_prefix("scale ")
                    || lower.has_prefix("hide ") || lower.has_prefix("show ")
                    || lower.has_prefix("caption ") || lower.has_prefix("header ")
                    || lower.has_prefix("footer ") || lower == "<style>" || lower == "</style>") {
                    continue;
                }
                if (lower == "title") {
                    in_title_block = true;
                    title_block.erase();
                    continue;
                }
                if (lower.has_prefix("title ")) {
                    d.title = line.substring(6).strip();
                    continue;
                }

                MatchInfo m;
                if (x_axis_re.match(line, 0, out m)) {
                    parse_x_axis(d, m);
                    continue;
                }
                if (y_axis_re.match(line, 0, out m)) {
                    parse_y_axis(d, m, line_no);
                    continue;
                }
                if (series_re.match(line, 0, out m)) {
                    parse_series(d, m, line_no);
                    continue;
                }
                if (legend_re.match(line, 0, out m)) {
                    switch (m.fetch(1).down()) {
                        case "left": d.legend = ChartLegendPosition.LEFT; break;
                        case "top": d.legend = ChartLegendPosition.TOP; break;
                        case "bottom": d.legend = ChartLegendPosition.BOTTOM; break;
                        default: d.legend = ChartLegendPosition.RIGHT; break;
                    }
                    continue;
                }
                if (stack_re.match(line, 0, out m)) {
                    d.stack_mode = m.fetch(1).down() == "stacked"
                        ? ChartStackMode.STACKED : ChartStackMode.GROUPED;
                    continue;
                }
                if (orient_re.match(line, 0, out m)) {
                    d.orientation = m.fetch(1).down() == "horizontal"
                        ? ChartOrientation.HORIZONTAL : ChartOrientation.VERTICAL;
                    continue;
                }
                if (annotation_re.match(line, 0, out m)) {
                    var a = new ChartAnnotation(m.fetch(1), m.fetch(2).strip(), m.fetch(3).strip());
                    a.arrow = group(m, 4) != "";
                    a.source_line = line_no;
                    d.annotations.add(a);
                    continue;
                }

                d.errors.add(new ParseError("Unrecognized chart line: %s".printf(line), line_no, 1));
            }

            if (in_title_block) {
                d.title = title_block.str.strip();
            }
            return d;
        }

        // GLib returns null for a group that did not take part in the match.
        private static string group(MatchInfo m, int n) {
            string? s = m.fetch(n);
            return s == null ? "" : s;
        }

        private void parse_x_axis(ChartDiagram d, MatchInfo m) {
            var ax = d.x_axis;
            string title = group(m, 1);
            if (title.length > 0) ax.title = title;
            string lo = group(m, 2), hi = group(m, 3);
            if (lo.length > 0 && hi.length > 0) {
                ax.has_range = true;
                ax.min = double.parse(lo);
                ax.max = double.parse(hi);
            }
            string data = group(m, 4);
            if (data.length > 0) {
                ax.labels.clear();
                foreach (string c in data.split(",")) {
                    string cat = c.strip();
                    if (cat.length > 0) ax.labels.add(unquote(cat));
                }
            }
            string spacing = group(m, 5);
            if (spacing.length > 0) {
                double v = double.parse(spacing);
                if (v > 0) {
                    ax.has_tick_spacing = true;
                    ax.tick_spacing = v;
                }
            }
            if (group(m, 6).length > 0) ax.label_at_end = true;
            if (group(m, 7).length > 0) ax.grid = true;
        }

        private void parse_y_axis(ChartDiagram d, MatchInfo m, int line_no) {
            bool secondary = group(m, 1).down().has_suffix("2");
            ChartAxisSpec ax;
            if (secondary) {
                ax = d.y2_axis;
                d.has_y2 = true;
            } else {
                ax = d.y_axis;
            }
            string title = group(m, 2);
            if (title.length > 0) ax.title = title;
            string lo = group(m, 3), hi = group(m, 4);
            if (lo.length > 0 && hi.length > 0) {
                ax.has_range = true;
                ax.min = double.parse(lo);
                ax.max = double.parse(hi);
            }
            string labels = group(m, 5);
            if (labels.length > 0) {
                ax.labels.clear();
                foreach (string c in labels.split(",")) {
                    string cat = c.strip();
                    if (cat.length > 0) ax.labels.add(unquote(cat));
                }
            }
            string ticks = group(m, 6);
            if (ticks.length > 0) {
                ax.tick_values.clear();
                ax.tick_labels.clear();
                foreach (string pair in split_tick_list(ticks)) {
                    MatchInfo tm;
                    // The subject string must outlive the MatchInfo: GRegex
                    // keeps a pointer to it rather than copying, so matching
                    // against `pair.strip()` directly made every fetch() read
                    // the freed temporary.
                    string pair_text = pair.strip();
                    if (tick_re.match(pair_text, 0, out tm)) {
                        ax.tick_values.add(double.parse(tm.fetch(1)));
                        ax.tick_labels.add(tm.fetch(2));
                    } else {
                        d.errors.add(new ParseError(
                            """Invalid tick format. Expected: [value:"label", ...]""", line_no, 1));
                    }
                }
            }
            string spacing = group(m, 7);
            if (spacing.length > 0) {
                double v = double.parse(spacing);
                if (v > 0) {
                    ax.has_tick_spacing = true;
                    ax.tick_spacing = v;
                } else {
                    d.errors.add(new ParseError("Tick spacing must be greater than 0", line_no, 1));
                }
            }
            if (group(m, 8).length > 0) ax.label_at_end = true;
            if (group(m, 9).length > 0) ax.grid = true;
        }

        private void parse_series(ChartDiagram d, MatchInfo m, int line_no) {
            if (d.series.size >= MAX_SERIES) {
                return;
            }
            string kind = m.fetch(1).down();
            ChartSeriesType type;
            switch (kind) {
                case "line": type = ChartSeriesType.LINE; break;
                case "area": type = ChartSeriesType.AREA; break;
                case "scatter": type = ChartSeriesType.SCATTER; break;
                default: type = ChartSeriesType.BAR; break;
            }

            var s = new ChartSeries(group(m, 3), type);
            s.source_line = line_no;
            string stereo = group(m, 2);
            if (stereo.length > 0) s.stereotype = stereo;

            foreach (string raw in group(m, 4).split(",")) {
                if (s.values.size >= MAX_VALUES) break;
                string v = raw.strip();
                if (v.length == 0) continue;
                double parsed;
                if (double.try_parse(v, out parsed)) {
                    s.values.add(parsed);
                } else {
                    d.errors.add(new ParseError(
                        "Invalid number format in %s data: %s".printf(kind, v), line_no, 1));
                    s.values.add(null);
                }
            }

            string color = group(m, 5);
            if (color.length > 0) s.color = normalize_color(color);

            // PlantUML's bar command has no v2 group: only line, area and
            // scatter can be bound to the secondary axis.
            if (group(m, 6).length > 0) {
                if (type == ChartSeriesType.BAR) {
                    d.errors.add(new ParseError(
                        "A bar series cannot use the secondary axis (v2)", line_no, 1));
                } else {
                    s.secondary_axis = true;
                }
            }
            if (group(m, 7).length > 0) s.show_labels = true;

            string marker = group(m, 8).down();
            if (marker == "square") s.marker = ChartMarkerShape.SQUARE;
            else if (marker == "triangle") s.marker = ChartMarkerShape.TRIANGLE;
            else s.marker = ChartMarkerShape.CIRCLE;

            d.series.add(s);
        }

        /**
         * Splits a `ticks [...]` body on the commas that separate pairs, not on
         * a comma inside a quoted label ("10:\"one, two\"").
         */
        internal static Gee.ArrayList<string> split_tick_list(string body) {
            var parts = new Gee.ArrayList<string>();
            var cur = new StringBuilder();
            bool in_quotes = false;
            for (int i = 0; i < body.length; i++) {
                char c = body[i];
                if (c == '"') in_quotes = !in_quotes;
                if (c == ',' && !in_quotes) {
                    parts.add(cur.str);
                    cur.erase();
                } else {
                    cur.append_c(c);
                }
            }
            if (cur.len > 0) parts.add(cur.str);
            return parts;
        }

        private static string unquote(string s) {
            if (s.length >= 2 && s.has_prefix("\"") && s.has_suffix("\"")) {
                return s.substring(1, s.length - 2);
            }
            return s;
        }

        /**
         * Graphviz takes a `#` prefix only on a hex code, never on a named
         * colour: "FF0000" becomes "#FF0000" and "red" stays "red".
         */
        internal static string normalize_color(string raw) {
            string v = raw.strip();
            if (v.has_prefix("#")) v = v.substring(1);
            if (v.length == 0) return v;
            if (v.length != 3 && v.length != 6) return v.down();
            for (int i = 0; i < v.length; i++) {
                if (!v[i].isxdigit()) return v.down();
            }
            return "#" + v;
        }
    }
}
