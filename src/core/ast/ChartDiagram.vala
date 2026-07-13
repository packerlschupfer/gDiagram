/* ChartDiagram.vala — AST for PlantUML's @startchart diagram type
 *
 * PlantUML 1.2026.8 draws bar/line/area/scatter charts from a handful of
 * single-line commands (net.sourceforge.plantuml.chart). The grammar below is
 * the one its command classes carry as regexes:
 *
 *   title <text>
 *   [hx]-axis ["title"] [min --> max] [[a, b, c]] [spacing N] [label-right] [grid]
 *   [vy]2?-axis ["title"] [min --> max] [[a, b, c]] [ticks [v:"l", ...]]
 *                                       [spacing N] [label-top] [grid]
 *   bar|line|area ["name"] [data] [#color] [v2] [labels]
 *   scatter ["name"] [data] [#color] [v2] [labels] [<<circle|square|triangle>>]
 *   legend left|right|top|bottom
 *   stackMode grouped|stacked
 *   orientation vertical|horizontal
 *   annotation "<text>" at (<x>, <y>) [<<arrow>>]
 *
 * A bar/line/area may also carry a leading <<stereotype>>, which PlantUML uses
 * for styling only; it is kept on the series so the inspector can show it.
 */
namespace GDiagram {

    public enum ChartSeriesType {
        BAR,
        LINE,
        AREA,
        SCATTER
    }

    public enum ChartMarkerShape {
        CIRCLE,
        SQUARE,
        TRIANGLE
    }

    public enum ChartLegendPosition {
        NONE,
        LEFT,
        RIGHT,
        TOP,
        BOTTOM
    }

    public enum ChartStackMode {
        GROUPED,
        STACKED
    }

    public enum ChartOrientation {
        VERTICAL,
        HORIZONTAL
    }

    /**
     * One axis of a chart. An axis is either a *value* axis (`has_range`, or no
     * explicit range at all and the data decides) or a *category* axis
     * (`labels` non-empty) — PlantUML's own ChartAxis keeps both, and the
     * h-axis regex accepts a range and a category list in the same line.
     */
    public class ChartAxisSpec : Object {
        public string title { get; set; default = ""; }

        public bool has_range { get; set; default = false; }
        public double min { get; set; default = 0.0; }
        public double max { get; set; default = 0.0; }

        /** Category labels, from `[Q1, Q2, Q3]`. Empty on a value axis. */
        public Gee.ArrayList<string> labels { get; set; default = new Gee.ArrayList<string>(); }

        /** `grid` — draw grid lines across the plot at this axis' ticks. */
        public bool grid { get; set; default = false; }

        /**
         * `label-right` on the h-axis / `label-top` on the v-axis: put the axis
         * title at the far end of the axis instead of beside its middle.
         */
        public bool label_at_end { get; set; default = false; }

        /** `spacing N` — one tick every N units (value axis) or N categories. */
        public bool has_tick_spacing { get; set; default = false; }
        public double tick_spacing { get; set; default = 0.0; }

        /** `ticks [10:"low", 90:"high"]` — explicit tick positions and labels. */
        public Gee.ArrayList<double?> tick_values { get; set; default = new Gee.ArrayList<double?>(); }
        public Gee.ArrayList<string> tick_labels { get; set; default = new Gee.ArrayList<string>(); }

        public bool has_custom_ticks() {
            return tick_values.size > 0;
        }

        public bool is_category_axis() {
            return labels.size > 0;
        }
    }

    /** One plotted series: `bar "Revenue" [30, 50] #blue labels`. */
    public class ChartSeries : Object {
        public string name { get; set; default = ""; }
        public ChartSeriesType series_type { get; set; default = ChartSeriesType.BAR; }

        /** The series values; a null entry is a gap (an unparseable number). */
        public Gee.ArrayList<double?> values { get; set; default = new Gee.ArrayList<double?>(); }

        /** Normalised colour: "#RRGGBB" kept with its hash, a named colour bare. */
        public string? color { get; set; default = null; }

        /** `labels` — print each value next to its bar/point. */
        public bool show_labels { get; set; default = false; }

        /** `v2` — plot against the secondary value axis. */
        public bool secondary_axis { get; set; default = false; }

        public ChartMarkerShape marker { get; set; default = ChartMarkerShape.CIRCLE; }

        /** A leading `<<stereo>>`, kept verbatim without the angle brackets. */
        public string? stereotype { get; set; default = null; }

        public int source_line { get; set; default = 0; }

        public ChartSeries(string name, ChartSeriesType type) {
            this.name = name;
            this.series_type = type;
        }

        public string type_name() {
            switch (series_type) {
                case ChartSeriesType.BAR: return "bar";
                case ChartSeriesType.LINE: return "line";
                case ChartSeriesType.AREA: return "area";
                default: return "scatter";
            }
        }
    }

    /** `annotation "Peak" at (3, 90) <<arrow>>`. */
    public class ChartAnnotation : Object {
        public string text { get; set; default = ""; }
        /**
         * The x position as written: a number on a value axis, or a category
         * label / 1-based index on a category axis. Resolved by the renderer,
         * which is the only place that knows the axis kind.
         */
        public string x_pos { get; set; default = ""; }
        public string y_pos { get; set; default = ""; }
        public bool arrow { get; set; default = false; }
        public int source_line { get; set; default = 0; }

        public ChartAnnotation(string text, string x_pos, string y_pos) {
            this.text = text;
            this.x_pos = x_pos;
            this.y_pos = y_pos;
        }
    }

    public class ChartDiagram : Object {
        public string? title { get; set; default = null; }

        public ChartAxisSpec x_axis { get; set; default = new ChartAxisSpec(); }
        public ChartAxisSpec y_axis { get; set; default = new ChartAxisSpec(); }
        public ChartAxisSpec y2_axis { get; set; default = new ChartAxisSpec(); }
        public bool has_y2 { get; set; default = false; }

        public Gee.ArrayList<ChartSeries> series { get; set; default = new Gee.ArrayList<ChartSeries>(); }
        public Gee.ArrayList<ChartAnnotation> annotations {
            get; set; default = new Gee.ArrayList<ChartAnnotation>();
        }

        public ChartLegendPosition legend { get; set; default = ChartLegendPosition.NONE; }
        public ChartStackMode stack_mode { get; set; default = ChartStackMode.GROUPED; }
        public ChartOrientation orientation { get; set; default = ChartOrientation.VERTICAL; }

        public Gee.ArrayList<ParseError> errors { get; set; default = new Gee.ArrayList<ParseError>(); }

        public bool has_errors() {
            return errors.size > 0;
        }

        public bool is_empty() {
            return series.size == 0;
        }

        /** The longest series, which fixes how many categories the chart has. */
        public int value_count() {
            int n = 0;
            foreach (var s in series) {
                n = int.max(n, s.values.size);
            }
            return n;
        }
    }
}
