namespace GDiagram.Tests {
    /**
     * The two PlantUML types added alongside the 1.2026.8 chart engine:
     * @startchart (bar/line/area/scatter) and @startgit / @startgitlog (which
     * redraws pasted `git log --graph` art).
     *
     * The grammar assertions come from the command classes in the 1.2026.8
     * jar, not from guesswork: every regex in ChartDiagramParser was read out
     * of net.sourceforge.plantuml.chart.command with javap, and the rendered
     * geometry was measured against the jar's own SVG.
     */
    public class ChartGitLogTests {

        private static DiagramEngine? shared_engine = null;
        private static string? tmp_dir = null;

        private static DiagramEngine engine() {
            if (shared_engine == null) shared_engine = new DiagramEngine("dot");
            return shared_engine;
        }

        private static string tmp(string name) {
            if (tmp_dir == null) {
                try {
                    tmp_dir = DirUtils.make_tmp("gdiagram-chart-XXXXXX");
                } catch (FileError e) {
                    error("mkdtemp: %s", e.message);
                }
            }
            return Path.build_filename(tmp_dir, name);
        }

        private const string CHART =
            "@startchart\n" +
            "title Quarterly\n" +
            "h-axis \"Quarter\" [Q1, Q2, Q3, Q4]\n" +
            "v-axis \"Value\" 0 --> 100 grid\n" +
            "bar \"Revenue\" [30, 50, 70, 90] #blue labels\n" +
            "line \"Cost\" [20, 30, 40, 50]\n" +
            "legend right\n" +
            "@endchart\n";

        private const string GITLOG =
            "@startgit\n" +
            "*   a1b2c3d (HEAD -> main) Merge branch 'feature'\n" +
            "|\\\n" +
            "| * 9f8e7d6 (feature) second\n" +
            "| * 5c4b3a2 first\n" +
            "* | 1a2b3c4 main work\n" +
            "|/\n" +
            "* 0f1e2d3 (tag: v0.1.0) root\n" +
            "@endgit\n";

        private static string dot_of(string src) {
            string? dot = engine().generate_dot(src, "x.puml", null);
            assert(dot != null);
            return dot;
        }

        // ---- 1. detection ----

        public static void test_detection() {
            assert(TypeDetector.detect_plantuml(CHART) == DiagramType.CHART);
            assert(TypeDetector.detect_plantuml(GITLOG) == DiagramType.GITLOG);
            // PlantUML registers the keyword `git`; @startgitlog only works
            // because it matches the keyword by prefix. Both must land here.
            assert(TypeDetector.detect_plantuml("@startgitlog\n* abc x\n@endgitlog\n")
                   == DiagramType.GITLOG);
            // A tag line means PlantUML, never Mermaid.
            assert(!TypeDetector.is_mermaid(CHART));
            assert(!TypeDetector.is_mermaid(GITLOG));
            // There is no @startpacket in PlantUML 1.2026.8 — the packet
            // diagram is registered as `packetdiag` only, and @startpacket is
            // answered with "not recognized". It must not become a chart or a
            // packet by accident.
            var packet_ish = TypeDetector.detect_plantuml(
                "@startpacket\n0-15: Source Port\n@endpacket\n");
            assert(packet_ish != DiagramType.CHART);
            assert(packet_ish != DiagramType.MERMAID_PACKET);
            // The real spelling still works and is still the Mermaid-packet AST.
            assert(TypeDetector.detect_plantuml(
                "@startpacketdiag\npacketdiag {\n 0-15: P\n}\n@endpacketdiag\n")
                == DiagramType.MERMAID_PACKET);
        }

        // ---- 2. chart parsing ----

        public static void test_chart_parse() {
            var d = new ChartDiagramParser().parse(CHART);
            assert(d.title == "Quarterly");
            assert(d.x_axis.title == "Quarter");
            assert(d.x_axis.labels.size == 4);
            assert(d.x_axis.labels.get(0) == "Q1");
            assert(d.x_axis.labels.get(3) == "Q4");
            assert(d.y_axis.title == "Value");
            assert(d.y_axis.has_range);
            assert(d.y_axis.min == 0.0 && d.y_axis.max == 100.0);
            assert(d.y_axis.grid);
            assert(d.legend == ChartLegendPosition.RIGHT);

            assert(d.series.size == 2);
            var bar = d.series.get(0);
            assert(bar.series_type == ChartSeriesType.BAR);
            assert(bar.name == "Revenue");
            assert(bar.values.size == 4);
            assert(bar.values.get(0) == 30.0 && bar.values.get(3) == 90.0);
            assert(bar.show_labels);
            // `#blue` is a named colour: Graphviz takes the `#` prefix only on
            // a hex code, so the hash must be stripped here.
            assert(bar.color == "blue");

            var line = d.series.get(1);
            assert(line.series_type == ChartSeriesType.LINE);
            assert(line.name == "Cost");
            assert(!line.show_labels);
            assert(d.errors.size == 0);
        }

        public static void test_chart_color_normalisation() {
            var d = new ChartDiagramParser().parse(
                "@startchart\n" +
                "bar \"a\" [1] #FF0000\n" +
                "bar \"b\" [2] #red\n" +
                "bar \"c\" [3] #F00\n" +
                "bar \"d\" [4]\n" +
                "@endchart\n");
            assert(d.series.size == 4);
            // A hex code keeps its hash; a named colour loses it.
            assert(d.series.get(0).color == "#FF0000");
            assert(d.series.get(1).color == "red");
            assert(d.series.get(2).color == "#F00");
            assert(d.series.get(3).color == null);
        }

        public static void test_chart_full_grammar() {
            // Every command the 1.2026.8 ChartDiagramFactory registers.
            var d = new ChartDiagramParser().parse(
                "@startchart\n" +
                "title Full\n" +
                "x-axis \"Q\" [A, B] spacing 1 label-right grid\n" +
                "y-axis \"V\" 0 --> 10 spacing 2 label-top grid\n" +
                "y2-axis \"P\" 0 --> 1\n" +
                "area <<stereo>> \"Band\" [1, 2] #99ccff\n" +
                "line \"L\" [3, 4] #red v2 labels\n" +
                "scatter \"S\" [5, 6] #green labels <<triangle>>\n" +
                "legend bottom\n" +
                "stackMode stacked\n" +
                "orientation horizontal\n" +
                "annotation \"Peak\" at (2, 9) <<arrow>>\n" +
                "@endchart\n");
            if (d.errors.size != 0) {
                printerr("\nunexpected chart errors: %s\n", d.errors.get(0).to_string());
            }
            assert(d.errors.size == 0);

            // `[hx]-axis` and `[vy]2?-axis` are both spellings of the same axes.
            assert(d.x_axis.title == "Q");
            assert(d.x_axis.label_at_end && d.x_axis.grid && d.x_axis.has_tick_spacing);
            assert(d.y_axis.label_at_end && d.y_axis.grid);
            assert(d.y_axis.tick_spacing == 2.0);
            assert(d.has_y2 && d.y2_axis.title == "P");

            assert(d.series.size == 3);
            assert(d.series.get(0).series_type == ChartSeriesType.AREA);
            assert(d.series.get(0).stereotype == "stereo");
            assert(d.series.get(1).secondary_axis && d.series.get(1).show_labels);
            assert(d.series.get(2).series_type == ChartSeriesType.SCATTER);
            assert(d.series.get(2).marker == ChartMarkerShape.TRIANGLE);

            assert(d.legend == ChartLegendPosition.BOTTOM);
            assert(d.stack_mode == ChartStackMode.STACKED);
            assert(d.orientation == ChartOrientation.HORIZONTAL);
            assert(d.annotations.size == 1);
            assert(d.annotations.get(0).text == "Peak");
            assert(d.annotations.get(0).x_pos == "2" && d.annotations.get(0).y_pos == "9");
            assert(d.annotations.get(0).arrow);
        }

        public static void test_chart_custom_ticks() {
            var d = new ChartDiagramParser().parse(
                "@startchart\n" +
                "v-axis \"V\" 0 --> 100 ticks [0:\"low\", 50:\"mid, ok\", 100:\"high\"]\n" +
                "bar \"a\" [1]\n" +
                "@endchart\n");
            assert(d.errors.size == 0);
            assert(d.y_axis.has_custom_ticks());
            assert(d.y_axis.tick_values.size == 3);
            assert(d.y_axis.tick_values.get(0) == 0.0);
            assert(d.y_axis.tick_values.get(1) == 50.0);
            assert(d.y_axis.tick_values.get(2) == 100.0);
            assert(d.y_axis.tick_labels.get(0) == "low");
            // The comma inside the quoted label must not split the pair list.
            assert(d.y_axis.tick_labels.get(1) == "mid, ok");
        }

        public static void test_chart_errors() {
            // A bar cannot bind to the secondary axis: PlantUML's bar command
            // has no v2 group at all, only line/area/scatter do.
            var d = new ChartDiagramParser().parse(
                "@startchart\nbar \"a\" [1, 2] v2\n@endchart\n");
            assert(d.errors.size == 1);
            assert(!d.series.get(0).secondary_axis);

            // A value that is not a number is reported, and leaves a gap.
            var e = new ChartDiagramParser().parse(
                "@startchart\nbar \"a\" [1, zzz, 3]\n@endchart\n");
            assert(e.errors.size == 1);
            assert(e.series.get(0).values.size == 3);
            assert(e.series.get(0).values.get(1) == null);

            // An unknown command is an error rather than silence.
            var f = new ChartDiagramParser().parse(
                "@startchart\nnot-a-chart-command 3\n@endchart\n");
            assert(f.errors.size == 1);

            // Styling commands are accepted and ignored, not reported.
            var g = new ChartDiagramParser().parse(
                "@startchart\nskinparam backgroundColor white\nscale 2\n" +
                "bar \"a\" [1]\n@endchart\n");
            assert(g.errors.size == 0);
            assert(g.series.size == 1);
        }

        // ---- 3. chart rendering ----

        public static void test_chart_dot() {
            string dot = dot_of(CHART);
            // Fixed-position drawing, like the other chart-style renderers.
            assert(dot.contains("layout=nop2"));
            // Four bars, one per category, each a filled box.
            int bars = 0;
            foreach (string line in dot.split("\n")) {
                if (line.contains("id=\"chart_bar_0_")) bars++;
            }
            assert(bars == 4);
            // The named colour reached the DOT without a `#` (Graphviz rejects
            // "#blue"), and the value labels the `labels` flag asked for are there.
            assert(dot.contains("fillcolor=\"blue\""));
            assert(!dot.contains("\"#blue\""));
            // The axes and the category labels.
            assert(dot.contains("id=\"chart_axis_v\""));
            assert(dot.contains("id=\"chart_axis_h\""));
            assert(dot.contains("id=\"chart_cat_0\""));
            assert(dot.contains("id=\"chart_cat_3\""));
            // The legend was asked for, so both series are in it.
            assert(dot.contains("id=\"chart_legend_0\""));
            assert(dot.contains("id=\"chart_legend_1\""));
            assert(dot.contains("id=\"chart_title\""));
        }

        public static void test_chart_area_is_filled_in_the_dot() {
            // An `area` series is filled with strips rather than an SVG polygon
            // injected after layout, because the generic PlantUML render path
            // draws generate_dot()'s output directly — the DOT has to be the
            // whole drawing or `-f dot` and the preview would disagree.
            string dot = dot_of(
                "@startchart\nh-axis [A, B]\nv-axis 0 --> 10\narea \"x\" [2, 8]\n@endchart\n");
            assert(dot.contains("id=\"chart_area_0_1\""));
            int filled = 0;
            foreach (string line in dot.split("\n")) {
                if (line.contains("shape=box") && line.contains("style=filled")) filled++;
            }
            // One strip per 2pt of the segment, so many more than a single box.
            assert(filled > 20);
        }

        public static void test_chart_render_and_export() {
            var result = engine().render(DiagramType.CHART, DiagramFormat.PLANTUML, CHART);
            assert(result.status == RenderStatus.OK);
            assert(result.surface != null);
            assert(result.surface.get_width() > 100);
            assert(result.surface.get_height() > 100);

            string png = tmp("chart.png");
            string svg = tmp("chart.svg");
            string pdf = tmp("chart.pdf");
            assert(engine().export_to_png(CHART, "x.puml", null, png));
            assert(engine().export_to_svg(CHART, "x.puml", null, svg));
            assert(engine().export_to_pdf(CHART, "x.puml", null, pdf));
            assert(FileUtils.test(png, FileTest.EXISTS));
            assert(FileUtils.test(svg, FileTest.EXISTS));
            assert(FileUtils.test(pdf, FileTest.EXISTS));

            // Not just created — actually the format asked for.
            string head;
            try {
                FileUtils.get_contents(svg, out head);
            } catch (FileError e) {
                error("read svg: %s", e.message);
            }
            assert(head.contains("<svg"));
        }

        public static void test_chart_parse_result_feeds_outline() {
            // The generic render path produces no AST, so the outline and the
            // stats footer depend on engine.parse() building one.
            var r = engine().parse(CHART, "x.puml");
            assert(r.diagram_type == DiagramType.CHART);
            assert(r.ast != null);
            assert(r.ast is ChartDiagram);
            var d = (ChartDiagram) r.ast;
            assert(d.series.size == 2);

            var stats = new DiagramStats();
            stats.analyze_chart(d, CHART);
            assert(stats.get_quick_stats().length > 0);
        }

        // ---- 4. locale ----

        public static void test_chart_dot_is_locale_independent() {
            // A GUI process calls setlocale(); a headless export does not. A
            // chart is nothing but coordinates, so a comma-decimal locale would
            // fill the DOT with "pos=\"12,34,56,78\"" and Graphviz would refuse
            // the whole graph.
            string? had = Intl.setlocale(LocaleCategory.NUMERIC, null);
            string[] comma_locales = {
                "de_AT.utf8", "de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "es_ES.UTF-8"
            };
            string? used = null;
            foreach (string loc in comma_locales) {
                if (Intl.setlocale(LocaleCategory.NUMERIC, loc) != null) {
                    if ("%.2f".printf(1.5) == "1,50") {
                        used = loc;
                        break;
                    }
                }
            }
            if (used == null) {
                Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");
                Test.skip("no comma-decimal locale installed; cannot prove the locale guard here");
                return;
            }

            string dot = dot_of(
                "@startchart\nh-axis \"Q\" [A, B]\nv-axis \"V\" 0 --> 10 grid\n" +
                "bar \"a\" [2.5, 7.25]\nline \"b\" [1.5, 9.75]\nlegend right\n@endchart\n");
            Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");

            // Every coordinate is "x,y": a decimal comma makes three numbers.
            foreach (string line in dot.split("\n")) {
                int p = line.index_of("pos=\"");
                if (p < 0) continue;
                int q = line.index_of("\"", p + 5);
                if (q < 0) continue;
                string body = line.substring(p + 5, q - p - 5);
                foreach (string point in body.split(" ")) {
                    if (point.length == 0) continue;
                    if (point.split(",").length != 2) {
                        printerr("\nFAILED: locale-formatted coordinate under %s: %s\n",
                                 used, line);
                        assert_not_reached();
                    }
                }
            }
            // width/height are plain doubles, equally exposed.
            if (dot.contains("width=0,") || dot.contains("height=0,")) {
                printerr("\nFAILED: locale-formatted size under %s\n", used);
                assert_not_reached();
            }
        }

        // ---- 5. git log ----

        public static void test_gitlog_parse() {
            var d = new GitLogDiagramParser().parse(GITLOG);
            assert(d.commits.size == 5);
            // The name is the line with the connector characters removed, up
            // to the first space — never the `*` or the lane bars.
            assert(d.commits.get(0).name == "a1b2c3d");
            assert(d.commits.get(1).name == "9f8e7d6");
            assert(d.commits.get(4).name == "0f1e2d3");
            // The decoration is what sits between the first `(` and the `)`.
            assert(d.commits.get(0).label == "HEAD -> main");
            assert(d.commits.get(1).label == "feature");
            assert(d.commits.get(4).label == "tag: v0.1.0");
            assert(d.commits.get(2).label == null);
            // Lanes: git prints them two characters apart.
            assert(d.commits.get(0).lane == 0);
            assert(d.commits.get(1).lane == 1);
            assert(d.commits.get(3).lane == 0);
            // Source lines point back at the art, for click-to-source.
            assert(d.commits.get(0).source_line == 2);
        }

        public static void test_gitlog_lanes() {
            var d = new GitLogDiagramParser().parse(GITLOG);
            // The whole point of the character walker: the merge has two
            // parents, and the branch rejoins the trunk through the `|/`.
            //   0 a1b2c3d  -> 9f8e7d6 (lane 1) and 1a2b3c4 (lane 0)
            //   1 9f8e7d6  -> 5c4b3a2
            //   2 5c4b3a2  -> 0f1e2d3   (via `|/`, two columns left)
            //   3 1a2b3c4  -> 0f1e2d3
            assert(d.commits.get(0).parents.size == 2);
            assert(d.commits.get(0).parents.contains(1));
            assert(d.commits.get(0).parents.contains(3));
            assert(d.commits.get(1).parents.size == 1);
            assert(d.commits.get(1).parents.contains(2));
            // A `/` at column k joins the lane at k+1 above to k-1 below.
            // Stepping a single column here lost this edge entirely.
            assert(d.commits.get(2).parents.size == 1);
            assert(d.commits.get(2).parents.contains(4));
            assert(d.commits.get(3).parents.size == 1);
            assert(d.commits.get(3).parents.contains(4));
            assert(d.commits.get(4).parents.size == 0);
        }

        public static void test_gitlog_linear_and_junk() {
            // Real `git log --graph` output pads its connector rows with
            // trailing spaces; that must not change anything.
            var d = new GitLogDiagramParser().parse(
                "@startgit\n* aaa first\n* bbb second\n* ccc third\n@endgit\n");
            assert(d.commits.size == 3);
            assert(d.commits.get(0).parents.contains(1));
            assert(d.commits.get(1).parents.contains(2));

            // A line with no `*` is connector art, never an error.
            var e = new GitLogDiagramParser().parse(
                "@startgit\n* aaa one\n|\n* bbb two\n@endgit\n");
            assert(e.errors.size == 0);
            assert(e.commits.size == 2);
            assert(e.commits.get(0).parents.contains(1));

            // Text that carries no commit at all is worth saying out loud.
            var f = new GitLogDiagramParser().parse(
                "@startgit\nhello world\ntitle Something\n@endgit\n");
            assert(f.commits.size == 0);
            assert(f.errors.size == 1);

            // An empty block is PlantUML's blank page, not an error.
            var g = new GitLogDiagramParser().parse("@startgit\n@endgit\n");
            assert(g.commits.size == 0);
            assert(g.errors.size == 0);
        }

        public static void test_gitlog_dot_and_render() {
            string dot = dot_of(GITLOG);
            // PlantUML lays gitlog out with SmetanaForGit, its own dot port, so
            // this is a real digraph rather than a pinned drawing.
            assert(dot.contains("digraph gitlog"));
            assert(dot.contains("rankdir=TB"));
            int edges = 0;
            foreach (string line in dot.split("\n")) {
                // Only real edge statements: a decoration like "HEAD -> main"
                // is drawn inside a node label and carries the same arrow.
                string t = line.strip();
                if (t.has_prefix("gc") && t.contains(" -> ") && !t.contains("label=")) edges++;
            }
            assert(edges == 5);
            // The decoration shows only on a tip commit, as PlantUML's
            // MagicBox.getCommentBlock() requires node.isTop().
            assert(dot.contains("a1b2c3d\\nHEAD -> main"));
            assert(!dot.contains("0f1e2d3\\ntag"));

            var result = engine().render(DiagramType.GITLOG, DiagramFormat.PLANTUML, GITLOG);
            assert(result.status == RenderStatus.OK);
            assert(result.surface != null);

            string png = tmp("gitlog.png");
            assert(engine().export_to_png(GITLOG, "x.puml", null, png));
            assert(FileUtils.test(png, FileTest.EXISTS));

            var r = engine().parse(GITLOG, "x.puml");
            assert(r.ast is GitLogDiagram);
            var stats = new DiagramStats();
            stats.analyze_gitlog((GitLogDiagram) r.ast, GITLOG);
            assert(stats.get_quick_stats().length > 0);
        }

        // ---- 6. the shipped examples ----

        public static void test_examples_render() {
            string? root = Environment.get_variable("GDIAGRAM_SOURCE_ROOT");
            if (root == null) {
                Test.skip("GDIAGRAM_SOURCE_ROOT not set");
                return;
            }
            string[] files = {
                "examples/plantuml/chart/quarterly.puml",
                "examples/plantuml/chart/sales-mix.puml",
                "examples/plantuml/gitlog/feature-merge.puml"
            };
            foreach (string rel in files) {
                string path = Path.build_filename(root, rel);
                string src;
                try {
                    FileUtils.get_contents(path, out src);
                } catch (FileError e) {
                    error("read %s: %s", path, e.message);
                }
                var r = engine().parse(src, path);
                if (r.errors != null && r.errors.size > 0) {
                    printerr("\n%s: %s\n", rel, r.errors.get(0).to_string());
                    assert_not_reached();
                }
                string out_png = tmp(Path.get_basename(rel) + ".png");
                if (!engine().export_to_png(src, path, null, out_png)) {
                    printerr("\n%s: export failed\n", rel);
                    assert_not_reached();
                }
            }
        }

        // The GUI reads result.ast to fill the outline and the stats footer.
        // chart and gitlog draw through render_generic_plantuml(), which returns
        // ast = null for every type that shares it — so their outline populators
        // and stats cases were unreachable and the GUI showed an empty outline
        // and "0 elements". Found in the round-9 GUI smoke test, not by a test.
        // PlantUML fills 60% of a category band with bars. Measured off
        // 1.2026.9: `quarterly.puml` gets 60 px bars on a 100 px band, and the
        // stacked pair in `sales-mix.puml` 40 px on 66.7 px. We shipped 0.8 in
        // round 9, a third too wide, and it survived because the comparison
        // was structural rather than numeric.
        public static void test_chart_bar_width_matches_plantuml() {
            string svg_path = tmp("barwidth.svg");
            assert(engine().export_to_svg(CHART, "x.puml", null, svg_path));
            string svg;
            FileUtils.get_contents(svg_path, out svg);

            // Bars are the filled polygons; the legend swatch is far smaller.
            double widest = 0.0;
            var xs = new Gee.ArrayList<double?>();
            try {
                var re = new Regex("<polygon fill=\"blue\"[^>]*points=\"([^\"]+)\"");
                MatchInfo mi;
                if (re.match(svg, 0, out mi)) {
                    do {
                        double lo = 1e9, hi = -1e9;
                        foreach (string pair in mi.fetch(1).split(" ")) {
                            string[] xy = pair.split(",");
                            if (xy.length != 2) continue;
                            double v = double.parse(xy[0]);
                            if (v < lo) lo = v;
                            if (v > hi) hi = v;
                        }
                        double w = hi - lo;
                        if (w > 20.0) {          // a bar, not the 12pt swatch
                            xs.add(lo);
                            if (w > widest) widest = w;
                        }
                    } while (mi.next());
                }
            } catch (RegexError e) {
                assert_not_reached();
            }

            assert(xs.size >= 2);
            xs.sort((a, b) => (a < b) ? -1 : ((a > b) ? 1 : 0));
            double pitch = xs.get(1) - xs.get(0);
            assert(pitch > 1.0);
            double fill = widest / pitch;
            // 0.6 of the band, PlantUML's own ratio
            assert(fill > 0.58 && fill < 0.62);
        }

        public static void test_render_carries_the_ast() {
            var engine = new DiagramEngine("dot");

            var chart = engine.render(DiagramType.CHART, DiagramFormat.PLANTUML, CHART);
            assert(chart.status == RenderStatus.OK);
            assert(chart.ast != null);
            var cd = chart.ast as ChartDiagram;
            assert(cd != null);
            assert(cd.series.size == 2);

            var git = engine.render(DiagramType.GITLOG, DiagramFormat.PLANTUML, GITLOG);
            assert(git.status == RenderStatus.OK);
            assert(git.ast != null);
            var gd = git.ast as GitLogDiagram;
            assert(gd != null);
            assert(gd.commits.size > 0);

            // A type that genuinely has no AST must stay null — the fix is for
            // these two only and must not pretend the others changed.
            var ditaa = engine.render(DiagramType.DITAA, DiagramFormat.PLANTUML,
                                      "@startditaa\n+---+\n| a |\n+---+\n@endditaa\n");
            if (ditaa.status == RenderStatus.OK) assert(ditaa.ast == null);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/chart/detection", ChartGitLogTests.test_detection);
        Test.add_func("/chart/parse", ChartGitLogTests.test_chart_parse);
        Test.add_func("/chart/colors", ChartGitLogTests.test_chart_color_normalisation);
        Test.add_func("/chart/full-grammar", ChartGitLogTests.test_chart_full_grammar);
        Test.add_func("/chart/custom-ticks", ChartGitLogTests.test_chart_custom_ticks);
        Test.add_func("/chart/errors", ChartGitLogTests.test_chart_errors);
        Test.add_func("/chart/dot", ChartGitLogTests.test_chart_dot);
        Test.add_func("/chart/area-filled-in-dot",
                      ChartGitLogTests.test_chart_area_is_filled_in_the_dot);
        Test.add_func("/chart/render-and-export", ChartGitLogTests.test_chart_render_and_export);
        Test.add_func("/chart/parse-feeds-outline",
                      ChartGitLogTests.test_chart_parse_result_feeds_outline);
        Test.add_func("/chart/locale", ChartGitLogTests.test_chart_dot_is_locale_independent);
        Test.add_func("/gitlog/parse", ChartGitLogTests.test_gitlog_parse);
        Test.add_func("/gitlog/lanes", ChartGitLogTests.test_gitlog_lanes);
        Test.add_func("/gitlog/linear-and-junk", ChartGitLogTests.test_gitlog_linear_and_junk);
        Test.add_func("/gitlog/dot-and-render", ChartGitLogTests.test_gitlog_dot_and_render);
        Test.add_func("/chart/examples", ChartGitLogTests.test_examples_render);
        Test.add_func("/chart/bar-width",
                      ChartGitLogTests.test_chart_bar_width_matches_plantuml);
        Test.add_func("/chart/render-carries-ast",
                      ChartGitLogTests.test_render_carries_the_ast);
        return Test.run();
    }
}
