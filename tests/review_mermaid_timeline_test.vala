namespace GDiagram.Tests {
    /**
     * Mermaid gantt, gitGraph and mindmap fidelity against Mermaid CLI 11.17:
     * gantt dates on a time axis (after/until, excludes, inclusive end dates,
     * status combinations), gitGraph branch names with "/", merges and
     * cherry-picks, and mindmap node shapes.
     */
    public class ReviewMermaidTimelineTests {

        private const int64 DAY = 86400000;

        private static int64 date(int y, int m, int d, int h = 0, int mi = 0) {
            return MermaidGanttTime.make(y, m, d, h, mi);
        }

        private static MermaidGantt gantt(string src) {
            var d = new MermaidGanttParser().parse(src);
            foreach (var e in d.errors) printerr("gantt error: %s (line %d)\n", e.message, e.line);
            assert(!d.has_errors());
            return d;
        }

        private static GanttTask task(MermaidGantt d, string id) {
            var t = d.find_task(id);
            if (t == null) error("no task %s", id);
            return t;
        }

        private static string gantt_svg(MermaidGantt d) {
            var regions = new Gee.ArrayList<ElementRegion>();
            var r = new MermaidGanttRenderer(new Gvc.Context(), regions, "dot");
            uint8[] data = r.render_to_svg(d);
            var sb = new StringBuilder();
            sb.append_len((string) data, data.length);
            return sb.str;
        }

        // x / width / fill / stroke of the bar <rect id="task_ID">
        private static bool bar(string svg, string id, out double x, out double w,
                                out string fill, out string stroke) {
            x = 0; w = 0; fill = ""; stroke = "";
            try {
                var re = new Regex("<rect id=\"task_" + Regex.escape_string(id) +
                    "\" x=\"([-0-9.]+)\" y=\"[-0-9.]+\" width=\"([-0-9.]+)\" height=\"[-0-9.]+\" rx=\"3\" ry=\"3\" fill=\"([^\"]+)\" stroke=\"([^\"]+)\"");
                MatchInfo m;
                if (!re.match(svg, 0, out m)) return false;
                x = double.parse(m.fetch(1));
                w = double.parse(m.fetch(2));
                fill = m.fetch(3);
                stroke = m.fetch(4);
                return true;
            } catch (RegexError e) {
                return false;
            }
        }

        private const string STATUS = """gantt
    dateFormat YYYY-MM-DD
    excludes weekends
    section S
    Plain task      :t1, 2025-01-01, 3d
    Active task     :active, t2, 2025-01-02, 3d
    Done task       :done, t3, 2025-01-01, 2d
    Crit active     :crit, active, t4, after t1, 2d
    Ends at date    :t5, 2025-01-03, 2025-01-10
    Multi after     :t6, after t2 t4, 1d
    Until           :t7, 2025-01-04, until t6
    Hours           :t8, 2025-01-05, 12h
""";

        // G3: "after a b" starts at the latest end; excluded weekend days push ends out
        public static void test_gantt_dependencies() {
            var d = gantt(STATUS);
            // t1: 3 days from Wed 1 Jan crosses the weekend → ends Mon 6 Jan, bar to Sat 4 Jan
            assert(task(d, "t1").end_ms == date(2025, 1, 6));
            assert(task(d, "t1").visible_end_ms() == date(2025, 1, 4));
            assert(task(d, "t4").start_ms == date(2025, 1, 6));
            assert(task(d, "t2").end_ms == date(2025, 1, 7));
            assert(task(d, "t4").end_ms == date(2025, 1, 8));
            // several predecessors: the later end (t4) wins
            assert(task(d, "t6").start_ms == date(2025, 1, 8));
            assert(task(d, "t6").end_ms == date(2025, 1, 9));
            assert(task(d, "t6").after_ids.size == 2);
        }

        // G4: end dates and until give real durations
        public static void test_gantt_end_date_and_until() {
            var d = gantt(STATUS);
            var t5 = task(d, "t5");
            assert(t5.start_ms == date(2025, 1, 3));
            assert(t5.end_ms == date(2025, 1, 10));     // an explicit end date is not extended
            var t7 = task(d, "t7");
            assert(t7.start_ms == date(2025, 1, 4));
            assert(t7.visible_end_ms() == date(2025, 1, 9));
            var t8 = task(d, "t8");
            assert(t8.end_ms - t8.start_ms == 12 * 3600000);
        }

        // G1: bars sit on a time scale — x ∝ start date, width ∝ duration
        public static void test_gantt_bar_geometry() {
            var d = gantt(STATUS);
            string svg = gantt_svg(d);
            double x1, w1, x2, w2, x3, w3, x5, w5;
            string f, s;
            assert(bar(svg, "t1", out x1, out w1, out f, out s));
            assert(bar(svg, "t2", out x2, out w2, out f, out s));
            assert(bar(svg, "t3", out x3, out w3, out f, out s));
            assert(bar(svg, "t5", out x5, out w5, out f, out s));
            // Domain 1 Jan .. 10 Jan over 784 - 150 px
            double per_day = (784.0 - 150.0) / 9.0;
            assert(x1 == 75);
            assert(Math.fabs((x2 - x1) - per_day) <= 1);
            assert(Math.fabs(w3 - 2 * per_day) <= 1);
            assert(Math.fabs((x5 - x1) - 2 * per_day) <= 1);
            assert(Math.fabs(w5 - 7 * per_day) <= 1);
            // a daily date axis
            assert(svg.contains(">2025-01-01</text>"));
            assert(svg.contains(">2025-01-10</text>"));
        }

        // G2: no tag is the plain task colour; crit + active keeps both
        public static void test_gantt_status_colours() {
            var d = gantt(STATUS);
            string svg = gantt_svg(d);
            double x, w;
            string fill, stroke;
            assert(!task(d, "t1").is_active && task(d, "t1").status == GanttTaskStatus.NONE);
            assert(bar(svg, "t1", out x, out w, out fill, out stroke));
            assert(fill == "#8A90DD" && stroke == "#534FBC");
            assert(bar(svg, "t2", out x, out w, out fill, out stroke));
            assert(fill == "#BFC7FF" && stroke == "#534FBC");
            assert(bar(svg, "t3", out x, out w, out fill, out stroke));
            assert(fill == "#D3D3D3" && stroke == "#808080");
            var t4 = task(d, "t4");
            assert(t4.is_crit && t4.is_active);
            assert(bar(svg, "t4", out x, out w, out fill, out stroke));
            assert(fill == "#BFC7FF" && stroke == "#FF8888");
        }

        // G5: milestones are diamonds at their date, click lines are accepted, vert markers
        public static void test_gantt_milestone_click_vert() {
            var d = gantt("""gantt
    dateFormat YYYY-MM-DD
    section A
    Work      :a1, 2025-01-01, 10d
    Release   :milestone, m1, 2025-01-06, 0d
    Freeze    :vert, v1, 2025-01-08, 0d
    click a1 href "https://example.com"
    click m1 call alert("x")
""");
            assert(task(d, "a1").clickable && task(d, "a1").link == "https://example.com");
            assert(task(d, "m1").is_milestone);
            assert(task(d, "v1").is_vert && task(d, "v1").order == -1);
            string svg = gantt_svg(d);
            // diamond centred on 6 Jan: 75 + 5/10 of 634 px
            assert(svg.contains("<polygon points=\"392,"));
            assert(svg.contains(">Freeze</text>"));
            assert(svg.contains("font-weight=\"bold\">Work</text>"));
            // the vert marker takes no row: 2 rows → height 2 * 50 + 2 * 24
            var layout = new MermaidGanttLayout(d, ThemeManager.get_active_palette());
            layout.build();
            assert(layout.height == 148);
        }

        // dateFormat with times, inclusiveEndDates, axisFormat / tickInterval
        public static void test_gantt_formats() {
            var d = gantt("""gantt
    dateFormat YYYY-MM-DD HH:mm
    axisFormat %H:%M
    section Day
    Wake       :w, 2025-03-01 07:00, 30m
    Work       :k, after w, 8h
""");
            assert(task(d, "w").start_ms == date(2025, 3, 1, 7, 0));
            assert(task(d, "k").start_ms == date(2025, 3, 1, 7, 30));
            assert(task(d, "k").end_ms == date(2025, 3, 1, 15, 30));

            var inc = gantt("gantt\n    dateFormat YYYY-MM-DD\n    inclusiveEndDates\n    A :a, 2025-01-01, 2025-01-03\n    B :b, after a, 2d\n");
            assert(task(inc, "a").end_ms == date(2025, 1, 4));
            assert(task(inc, "b").start_ms == date(2025, 1, 4));

            assert(MermaidGanttTime.format_d3(date(2025, 2, 1), "%e. %B") == " 1. February");
            assert(MermaidGanttTime.format_d3(date(2025, 1, 6), "%d %b") == "06 Jan");
            int64 ms;
            assert(MermaidGanttTime.parse_format("01.02.2025", "DD.MM.YYYY", out ms) && ms == date(2025, 2, 1));
            assert(!MermaidGanttTime.parse_format("2025-02-30", "YYYY-MM-DD", out ms));

            var weekly = gantt("""gantt
    dateFormat YYYY-MM-DD
    tickInterval 1week
    weekday monday
    A :a, 2025-01-01, 28d
""");
            var layout = new MermaidGanttLayout(weekly, ThemeManager.get_active_palette());
            var ticks = layout.ticks();
            assert(ticks.size == 4);
            assert(ticks[0] == date(2025, 1, 6));
            assert(ticks[3] == date(2025, 1, 27));
        }

        // ---- gitGraph ----

        private static MermaidGitGraph git(string src) {
            var d = new MermaidGitGraphParser().parse(src);
            foreach (var e in d.errors) printerr("git error: %s (line %d)\n", e.message, e.line);
            return d;
        }

        private static GitGraphCommit commit(MermaidGitGraph d, string id) {
            foreach (var c in d.all_commits) if (c.id == id) return c;
            error("no commit %s", id);
        }

        private static string git_svg(MermaidGitGraph d, Gee.ArrayList<ElementRegion> regions) {
            var r = new MermaidGitGraphRenderer(new Gvc.Context(), regions, "dot");
            uint8[] data = r.render_to_svg(d);
            var sb = new StringBuilder();
            sb.append_len((string) data, data.length);
            return sb.str;
        }

        // H2: "feature/x" is one branch name, so its merge has a source commit
        public static void test_gitgraph_slash_branch_merge() {
            var d = git("gitGraph\n    commit id: \"A\"\n    branch feature/x\n    checkout feature/x\n    commit id: \"B\"\n    checkout main\n    merge feature/x id: \"M\"\n");
            assert(!d.has_errors());
            assert(d.find_branch("feature/x") != null);
            assert(d.branches.size == 2);
            var m = commit(d, "M");
            assert(m.is_merge && m.merge_from_id == "B" && m.parent_id == "A");
            assert(commit(d, "B").branch_name == "feature/x");

            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = git_svg(d, regions);
            // the merge arrow comes down from B (x 60, lane y 88) into M (x 110, y -2) in the branch colour
            assert(svg.contains("d=\"M 60 88 L 90 88 A 20 20, 0, 0, 0, 110 68 L 110 -2\" fill=\"none\" stroke=\"#DEDE00\""));
            assert(svg.contains(">feature/x</text>"));
        }

        // H2 on the shipped example: both feature merges resolve
        public static void test_gitgraph_branching_example() {
            var d = git("""gitGraph
    commit id: "ZERO"
    branch develop
    checkout develop
    commit id: "dev-A"
    branch feature/login
    checkout feature/login
    commit id: "login-1"
    commit id: "login-2" type: HIGHLIGHT
    checkout develop
    merge feature/login id: "merge-login"
    branch feature/payments
    checkout feature/payments
    commit id: "pay-1"
    commit id: "pay-2"
    checkout develop
    merge feature/payments id: "merge-payments"
    checkout main
    merge develop id: "Release" tag: "v2.0.0"
    commit id: "Hotfix" type: REVERSE
""");
            assert(!d.has_errors());
            assert(commit(d, "merge-login").merge_from_id == "login-2");
            assert(commit(d, "merge-payments").merge_from_id == "pay-2");
            assert(commit(d, "Release").merge_from_id == "merge-payments");
            assert(commit(d, "Release").tag == "v2.0.0");
            assert(commit(d, "Hotfix").commit_type == GitGraphCommitType.REVERSE);
        }

        // H1: cherry-pick adds a commit on the current branch with a label
        public static void test_gitgraph_cherry_pick() {
            var d = git("""gitGraph
    commit
    commit id: "c2" tag: "v1"
    branch dev order: 1
    switch dev
    commit id: "d1"
    commit id: "d2"
    checkout main
    cherry-pick id: "d1"
    merge dev tag: "v2" type: HIGHLIGHT
    commit id: "last"
""");
            assert(!d.has_errors());
            assert(d.all_commits.size == 7);
            var pick = d.all_commits[4];
            assert(pick.is_cherry_pick && pick.branch_name == "main");
            assert(pick.merge_from_id == "d1" && pick.parent_id == "c2");
            assert(pick.tag == "cherry-pick:d1");
            assert(d.find_branch("dev").order == 1);
            var merge = d.all_commits[5];
            assert(merge.is_merge && merge.commit_type == GitGraphCommitType.HIGHLIGHT && !merge.custom_id);

            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = git_svg(d, regions);
            assert(svg.contains(">cherry-pick:d1</text>"));
            // commits advance 50 px per step on the main lane
            assert(regions.size == 7);
            assert(regions[1].x - regions[0].x == 50);
        }

        // H3: orientation, errors for unknown branches
        public static void test_gitgraph_orientation_and_errors() {
            var tb = git("gitGraph TB:\n    commit id: \"A\"\n    commit id: \"B\"\n");
            assert(!tb.has_errors() && tb.direction == "TB");
            var regions = new Gee.ArrayList<ElementRegion>();
            git_svg(tb, regions);
            assert(regions.size == 2 && regions[0].x == regions[1].x && regions[1].y - regions[0].y == 50);

            assert(git("gitGraph\n    checkout nope\n").has_errors());
            assert(git("gitGraph\n    commit\n    merge nope\n").has_errors());
            assert(git("gitGraph\n    commit\n    branch main\n").has_errors());
        }

        // ---- mindmap ----

        private static MindmapNode child(MindmapNode n, int i) {
            return n.children[i];
        }

        // M1 / M2: Mermaid's shape delimiters; anything else is literal text
        public static void test_mindmap_shapes() {
            var d = new MermaidMindmapParser().parse("""mindmap
  root((Root))
    Plain text
    id1[Square]
    id2(Rounded)
    c)Cloud(
    b))Bang((
    h{{Hexagon}}
    >Better recall]
    {Structured}
    q["`**Bold** text`"]
""");
            assert(!d.has_errors());
            var r = d.root;
            assert(r.shape == "circle" && r.label == "Root");
            assert(child(r, 0).shape == "default" && child(r, 0).label == "Plain text");
            assert(child(r, 1).shape == "rectangle" && child(r, 1).label == "Square" && child(r, 1).node_id == "id1");
            assert(child(r, 2).shape == "rounded" && child(r, 2).label == "Rounded");
            assert(child(r, 3).shape == "cloud" && child(r, 3).label == "Cloud");
            assert(child(r, 4).shape == "bang" && child(r, 4).label == "Bang");
            assert(child(r, 5).shape == "hexagon" && child(r, 5).label == "Hexagon");
            assert(child(r, 6).shape == "default" && child(r, 6).label == ">Better recall]");
            assert(child(r, 7).shape == "default" && child(r, 7).label == "{Structured}");
            assert(child(r, 8).markdown && child(r, 8).label == "**Bold** text");
            // each top-level branch is its own colour section
            assert(r.section == -1 && child(r, 0).section == 0 && child(r, 8).section == 8);
        }

        // M1: (x) is a rounded rectangle, not an ellipse; clouds get a scalloped outline
        public static void test_mindmap_rendered_shapes() {
            var d = new MermaidMindmapParser().parse("mindmap\n  root\n    (Rounded)\n    )Cloud(\n");
            // The renderer keeps an unowned context: it must outlive the renderer
            var ctx = new Gvc.Context();
            var r = new MermaidMindmapRenderer(ctx, new Gee.ArrayList<ElementRegion>(), "dot");
            string dot = r.generate_dot(d);
            assert(dot.contains("n_3_1 [label=<<FONT COLOR=\"#000000\">Rounded</FONT>> shape=box style=\"filled,rounded\""));
            uint8[] data = r.render_to_svg(d);
            var sb = new StringBuilder();
            sb.append_len((string) data, data.length);
            string svg = sb.str;
            int at = svg.index_of("<title>n_4_1</title>");
            assert(at > 0);
            string after = svg.substring(at, 200);
            assert(after.contains("<path fill=\"#d7ff86\"") && !after.contains("<ellipse"));
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/mermaid-timeline/gantt/dependencies", ReviewMermaidTimelineTests.test_gantt_dependencies);
        Test.add_func("/mermaid-timeline/gantt/end-date-until", ReviewMermaidTimelineTests.test_gantt_end_date_and_until);
        Test.add_func("/mermaid-timeline/gantt/bar-geometry", ReviewMermaidTimelineTests.test_gantt_bar_geometry);
        Test.add_func("/mermaid-timeline/gantt/status-colours", ReviewMermaidTimelineTests.test_gantt_status_colours);
        Test.add_func("/mermaid-timeline/gantt/milestone-click-vert", ReviewMermaidTimelineTests.test_gantt_milestone_click_vert);
        Test.add_func("/mermaid-timeline/gantt/formats", ReviewMermaidTimelineTests.test_gantt_formats);
        Test.add_func("/mermaid-timeline/gitgraph/slash-branch-merge", ReviewMermaidTimelineTests.test_gitgraph_slash_branch_merge);
        Test.add_func("/mermaid-timeline/gitgraph/branching-example", ReviewMermaidTimelineTests.test_gitgraph_branching_example);
        Test.add_func("/mermaid-timeline/gitgraph/cherry-pick", ReviewMermaidTimelineTests.test_gitgraph_cherry_pick);
        Test.add_func("/mermaid-timeline/gitgraph/orientation-errors", ReviewMermaidTimelineTests.test_gitgraph_orientation_and_errors);
        Test.add_func("/mermaid-timeline/mindmap/shapes", ReviewMermaidTimelineTests.test_mindmap_shapes);
        Test.add_func("/mermaid-timeline/mindmap/rendered-shapes", ReviewMermaidTimelineTests.test_mindmap_rendered_shapes);
        return Test.run();
    }
}
