namespace GDiagram.Tests {
    /**
     * PlantUML gantt charts: calendar arithmetic (working days, closed/open days),
     * dependency scheduling and the calendar renderer's geometry. Expected dates
     * are the ones PlantUML 1.2026.8 prints in its Start/End/Duration table.
     */
    public class ReviewGanttTests {

        private static PumlGanttDiagram parse(string body) {
            var d = new GanttDiagramParser().parse("@startgantt\n" + body + "\n@endgantt\n");
            assert(!d.has_errors());
            return d;
        }

        private static PumlGanttTask task(PumlGanttDiagram d, string name) {
            foreach (var t in d.tasks) {
                if (t.name == name || t.alias_name == name) return t;
            }
            error("no task %s", name);
        }

        private static int day(int y, int m, int dd) {
            return GanttScheduler.day_from_ymd(y, m, dd);
        }

        private static ElementRegion region(Gee.ArrayList<ElementRegion> regions, string name) {
            foreach (var r in regions) {
                if (r.name == name) return r;
            }
            error("no region %s", name);
        }

        private static bool near(double a, double b) {
            return Math.fabs(a - b) < 0.01;
        }

        // ---- date arithmetic ----

        public static void test_dates() {
            assert(GanttScheduler.day_from_ymd(1970, 1, 1) == 0);
            assert(PumlGanttDiagram.weekday_of(0) == 3);                  // Thursday
            assert(PumlGanttDiagram.weekday_of(day(2026, 9, 7)) == 0);    // Monday
            assert(GanttScheduler.parse_date("2026-09-03") == day(2026, 9, 3));
            assert(GanttScheduler.parse_date("2026/09/03") == day(2026, 9, 3));
            assert(GanttScheduler.parse_date("the 20th of september 2017") == day(2017, 9, 20));
            assert(GanttScheduler.parse_date("not a date") == int.MIN);
            int y, m, dd;
            GanttScheduler.ymd_from_day(day(2024, 2, 29), out y, out m, out dd);
            assert(y == 2024 && m == 2 && dd == 29);
            assert(GanttScheduler.iso_week(day(2026, 9, 7)) == 37);
        }

        public static void test_working_days_skip_closed_days() {
            var d = parse("Project starts 2026-09-07\nsaturday are closed\nsunday are closed\n" +
                          "[A] lasts 6 days");
            var a = task(d, "A");
            assert(a.start_day == day(2026, 9, 7));
            assert(a.last_day == day(2026, 9, 14));       // Mon..Fri + Mon
            assert(a.duration_days == 8);

            // Closed date and an open Saturday
            d = parse("Project starts 2026-09-07\nsaturday are closed\nsunday are closed\n" +
                      "2026-09-10 is closed\n2026-09-12 is open\n[T] lasts 5 days");
            var t = task(d, "T");
            assert(d.is_closed(day(2026, 9, 10)));
            assert(!d.is_closed(day(2026, 9, 12)));
            assert(t.last_day == day(2026, 9, 12));       // 7, 8, 9, 11, 12

            // A range
            d = parse("Project starts 2026-09-07\n2026-09-08 to 2026-09-09 is closed\n[R] lasts 2 days");
            assert(task(d, "R").last_day == day(2026, 9, 10));

            // Arithmetic helpers
            assert(GanttScheduler.snap_open(d, day(2026, 9, 8)) == day(2026, 9, 10));
            assert(near(GanttScheduler.end_after_working_days(d, day(2026, 9, 7), 2), day(2026, 9, 11)));
            assert(GanttScheduler.step_working_days(d, day(2026, 9, 7), 1) == day(2026, 9, 10));

            // Undated charts start on day 0, a Thursday: Day 3 and Day 4 are the weekend
            d = parse("saturday are closed\nsunday are closed\n[A] lasts 8 days");
            assert(!d.is_dated());
            assert(task(d, "A").last_day == 11);          // PlantUML: "Day 12"
        }

        public static void test_durations_and_dates() {
            var d = parse("Project starts 2026-09-07\n[W] lasts 1 week and 4 days\n[M] requires 1 month\n" +
                          "[E] ends 2026-09-18 and lasts 3 days\n[R] starts 2026-09-03 and ends 2026-09-10\n" +
                          "[F] starts D+2 and lasts 2 days");
            assert(task(d, "W").duration_days == 11);
            assert(task(d, "M").duration_days == 30);
            assert(task(d, "E").start_day == day(2026, 9, 16));
            // The gantt_dates repro: 8 days, not "1 days"
            assert(task(d, "R").start_day == day(2026, 9, 3));
            assert(task(d, "R").duration_days == 8);
            assert(task(d, "F").start_day == day(2026, 9, 9));

            // Resources load the task: 2 days on {A:50%} {B} last 1 day 8 hours
            d = parse("Project starts 2026-09-14\n[Review] on {Alice:50%} {Bob} requires 2 days");
            var r = task(d, "Review");
            assert(r.resources.size == 2);
            assert(r.resources[0].percent == 50 && r.resources[1].percent == 100);
            assert(near(r.end_instant - r.start_day, 4.0 / 3.0));
            assert(r.last_day == day(2026, 9, 15));
            assert(GanttLanguage.for_code("en").duration(r.end_instant - r.start_day) == "1 day, 8 hours");
        }

        // ---- dependencies ----

        public static void test_dependency_starts() {
            var d = parse("Project starts 2026-09-02\nsaturday are closed\nsunday are closed\n" +
                          "[A] lasts 3 days\n[B] starts at [A]'s end\n[B] lasts 2 days\n" +
                          "[C] starts at [A]'s start and lasts 1 day\n" +
                          "[D] starts 1 working days after [A]'s end and lasts 2 days\n" +
                          "[M1] happens at [A]'s end\n[M3] happens 2 days after [A]'s end\n" +
                          "[M4] happens 2026-09-15");
            var a = task(d, "A");
            assert(a.last_day == day(2026, 9, 4));                     // Friday
            assert(task(d, "B").start_day == day(2026, 9, 7));         // next Monday
            assert(task(d, "C").start_day == day(2026, 9, 2));
            assert(task(d, "D").start_day == day(2026, 9, 7));
            assert(task(d, "M1").is_milestone && task(d, "M1").start_day == day(2026, 9, 4));
            assert(task(d, "M3").start_day == day(2026, 9, 6));
            assert(task(d, "M4").is_milestone && task(d, "M4").start_day == day(2026, 9, 15));

            // Calendar offsets count from the day after the end
            d = parse("Project starts 2026-09-07\n[X] lasts 2 days\n" +
                      "[T0] starts 0 days after [X]'s end and lasts 1 day\n" +
                      "[T2] starts 2 days after [X]'s end and lasts 1 day\n" +
                      "[W] starts 1 working days after [X]'s end and lasts 1 day\n" +
                      "[S] starts 2 days before [X]'s end and lasts 1 day");
            assert(task(d, "T0").start_day == day(2026, 9, 9));
            assert(task(d, "T2").start_day == day(2026, 9, 11));
            assert(task(d, "W").start_day == day(2026, 9, 10));
            assert(task(d, "S").start_day == day(2026, 9, 7));
        }

        public static void test_arrows_then_alias() {
            var d = parse("Project starts 2026-09-01\nsaturday are closed\nsunday are closed\n" +
                          "[Prototype design] as [D] lasts 5 days\n[D] is 40% completed\n" +
                          "[Test prototype] lasts 4 days\n[D] -> [Test prototype]\n" +
                          "then [Deploy] lasts 3 days\n[B] -[#FF00FF]-> [C]\n[M] happens at [Deploy]'s end");
            var proto = task(d, "D");
            assert(proto.name == "Prototype design");
            assert(proto.completion_pct == 40);
            assert(proto.last_day == day(2026, 9, 7));
            assert(task(d, "Test prototype").start_day == day(2026, 9, 8));
            assert(task(d, "Test prototype").last_day == day(2026, 9, 11));
            assert(task(d, "Deploy").start_day == day(2026, 9, 14));
            assert(task(d, "M").start_day == day(2026, 9, 16));

            // Arrows: D→Test, Test→Deploy, B→C; none into the milestone
            assert(d.links.size == 3);
            assert(d.links[0].from == proto && d.links[0].to.name == "Test prototype");
            assert(d.links[0].from_anchor == PumlGanttAnchor.END);
            assert(d.links[1].to.name == "Deploy");
            assert(d.links[2].color == "#FF00FF");
            foreach (var l in d.links) assert(!l.to.is_milestone);
        }

        public static void test_document_lines() {
            var d = parse("title Plan\n-- Phase 1 --\n[A] lasts 2 days and is colored in Gold/DarkGoldenRod\n" +
                          "note bottom\nline one\nline two\nend note\n" +
                          "printscale weekly zoom 2\nlanguage de\nhide ressources names\ntoday is 2026-09-08 and is colored in #AAF");
            assert(d.title == "Plan");
            assert(d.rows.size == 2 && d.rows[0].separator == "Phase 1");
            var a = task(d, "A");
            assert(a.section == "Phase 1");
            assert(a.color == "Gold" && a.line_color == "DarkGoldenRod");
            assert(a.note == "line one\nline two");
            assert(d.scale == PumlGanttScale.WEEKLY && near(d.zoom, 2));
            assert(d.language == "de");
            assert(d.hide_resource_names);
            assert(d.today_day == day(2026, 9, 8) && d.today_color == "#AAF");
        }

        // ---- renderer geometry ----

        public static void test_bar_geometry_undated() {
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
            var d = parse("[Requirements] requires 5 days\n[Design] requires 7 days\n" +
                          "[Design] starts at [Requirements]'s end\n[Development] requires 14 days\n" +
                          "[Development] starts at [Design]'s end\n[Done] happens at [Development]'s end");
            var layout = new GanttLayout(d, ThemeManager.get_active_palette());
            string svg = layout.build();
            assert(near(layout.day_width, 16));

            var req = region(layout.regions, "Requirements");
            var des = region(layout.regions, "Design");
            var dev = region(layout.regions, "Development");
            var done = region(layout.regions, "Done");
            // x proportional to the start day, width to the duration
            assert(near(req.x, layout.chart_x + 2));
            assert(near(des.x - req.x, 5 * 16));
            assert(near(dev.x - req.x, 12 * 16));
            assert(near(req.width, 5 * 16 - 4));
            assert(near(des.width, 7 * 16 - 4));
            assert(near(dev.width, 14 * 16 - 4));
            // Milestone diamond centred on the last day of Development (day 26)
            assert(near(done.x + 5, layout.chart_x + 25 * 16 + 8));
            // Rows
            assert(near(des.y - req.y, GanttLayout.ROW_HEIGHT));
            // No invented title; day numbers in the header
            assert(!svg.contains("Gantt Chart"));
            assert(svg.contains(">26</text>"));
            assert(svg.contains(">Day 13</text>"));
        }

        public static void test_bar_geometry_dated() {
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
            var d = parse("Project starts 2026-09-01\nsaturday are closed\nsunday are closed\n" +
                          "[A] starts 2026-09-03 and lasts 4 days\n[M] happens 2026-09-15");
            var layout = new GanttLayout(d, ThemeManager.get_active_palette());
            string svg = layout.build();
            assert(layout.range_start == day(2026, 9, 1));
            assert(layout.range_end == day(2026, 9, 15));
            var a = region(layout.regions, "A");
            // Thu 3 .. Tue 8 across the weekend: starts 2 days in, spans 6 calendar days
            assert(near(a.x, layout.chart_x + 2 * 16 + 2));
            assert(near(a.width, 6 * 16 - 4));
            assert(near(layout.bar_left(task(d, "A")), a.x));
            // Weekend shading, weekday + month headers, dashed bar across the closed days
            assert(svg.contains("stroke-dasharray=\"2,3\""));
            assert(svg.contains(">September 2026</text>"));
            assert(svg.contains(">Mo</text>"));
            assert(svg.contains(">Sep 15</text>"));

            // Weekly scale: 4 px per day
            d = parse("printscale weekly\nProject starts 2026-09-01\n[A] lasts 21 days\n[B] lasts 20 days\n[A] -> [B]");
            layout = new GanttLayout(d, ThemeManager.get_active_palette());
            layout.build();
            assert(near(layout.day_width, 4));
            assert(near(region(layout.regions, "B").x - region(layout.regions, "A").x, 21 * 4));
            assert(near(region(layout.regions, "B").width, 20 * 4 - 4));
        }

        public static void test_renderer_regions_and_exports() {
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-dark"));
            var d = parse("title T\n[A] lasts 2 days\n[B] lasts 1 day\n[A] -> [B]");
            var regions = new Gee.ArrayList<ElementRegion>();
            var renderer = new GanttDiagramRenderer(new Gvc.Context(), regions, "dot");
            uint8[]? svg = renderer.render_to_svg(d);
            assert(svg != null);
            assert(region(regions, "A").source_line == 3);
            assert(region(regions, "B").source_line == 4);
            var surface = renderer.render_to_surface(d);
            assert(surface != null && surface.get_width() > 100);
            string dot = renderer.generate_dot(d);
            assert(dot.has_prefix("digraph") && dot.contains("->"));
            ThemeManager.set_active_palette(ThemeManager.get_preset("default-light"));
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/gantt/dates", ReviewGanttTests.test_dates);
        Test.add_func("/gantt/working_days", ReviewGanttTests.test_working_days_skip_closed_days);
        Test.add_func("/gantt/durations", ReviewGanttTests.test_durations_and_dates);
        Test.add_func("/gantt/dependency_starts", ReviewGanttTests.test_dependency_starts);
        Test.add_func("/gantt/arrows_then_alias", ReviewGanttTests.test_arrows_then_alias);
        Test.add_func("/gantt/document_lines", ReviewGanttTests.test_document_lines);
        Test.add_func("/gantt/geometry_undated", ReviewGanttTests.test_bar_geometry_undated);
        Test.add_func("/gantt/geometry_dated", ReviewGanttTests.test_bar_geometry_dated);
        Test.add_func("/gantt/regions_exports", ReviewGanttTests.test_renderer_regions_and_exports);
        return Test.run();
    }
}
