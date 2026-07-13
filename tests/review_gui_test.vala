/*
 * review_gui_test.vala — display-free logic behind the GUI smoke-test fixes (Sept 2026).
 *
 * - RenderSequencer / RenderTicket / RenderWorker: the preview renders on a render thread;
 *   a newer request supersedes one in flight, stale results are never shown, results arrive
 *   on the main thread, a detached (closed) document gets nothing, the main thread can use
 *   the engine under EngineLock while the thread renders, sharp zoom tiles.
 * - PathIdentity: opening a file that is already open (symlink, relative path, hard link).
 * - CleanState / Document: undoing back to the saved text clears the modified marker.
 * - PreviewGeometry: zoom keeps the anchor point (pointer or viewport centre) in place,
 *   and the sharp-tile area stays within its pixel budget.
 *
 * None of this needs a display (the engine renders headless).
 */
namespace GDiagram.Tests {
    public class ReviewGuiTests {

        // ── RenderSequencer ──────────────────────────────────────────

        static void test_sequencer_supersede() {
            var seq = new RenderSequencer();
            assert(!seq.pending);
            int g1 = seq.begin();
            int g2 = seq.begin();
            assert(g2 > g1);
            assert(seq.pending);
            // The superseded render finishing first is dropped
            assert(!seq.accept(g1));
            assert(seq.accept(g2));
            assert(!seq.pending);
            // A result is applied once
            assert(!seq.accept(g2));
        }

        static void test_sequencer_never_older() {
            var seq = new RenderSequencer();
            int g1 = seq.begin();
            int g2 = seq.begin();
            // Newer result first, the older one arriving late must not replace it
            assert(seq.accept(g2));
            assert(!seq.accept(g1));
            assert(seq.latest_applied == g2);
            // And after a newer request, the shown one's late duplicates stay out too
            int g3 = seq.begin();
            assert(!seq.accept(g2));
            assert(seq.is_current(g3));
            assert(seq.accept(g3));
        }

        // ── RenderWorker ─────────────────────────────────────────────

        static string sequence_source(string name) {
            return "@startuml\nparticipant %s\nparticipant Other\n%s -> Other : hello\n@enduml\n".printf(name, name);
        }

        // A class diagram big enough to take a noticeable time on the render thread
        static string big_class_source(int n) {
            var sb = new StringBuilder("@startuml\n");
            for (int i = 0; i < n; i++) {
                sb.append_printf("class C%d {\n  +field%d : int\n  +op%d() : void\n}\n", i, i, i);
                if (i > 0) sb.append_printf("C%d --> C%d\n", i - 1, i);
            }
            sb.append("@enduml\n");
            return sb.str;
        }

        static RenderRequest request(RenderTicket ticket, string source) {
            var r = new RenderRequest(source, null, null, "dot");
            r.generation = ticket.begin();
            return r;
        }

        // Runs the main loop until `done` or the timeout; false on timeout
        delegate bool Condition();
        static bool spin_until(Condition done, int timeout_ms = 30000) {
            int64 end = get_monotonic_time() + timeout_ms * 1000;
            var ctx = MainContext.default();
            while (!done()) {
                if (get_monotonic_time() > end) return false;
                ctx.iteration(false);
                Thread.usleep(1000);
            }
            return true;
        }

        static unowned Thread<void*> main_thread;

        class Collector : Object {
            public Gee.ArrayList<PreviewRender> delivered = new Gee.ArrayList<PreviewRender>();
            public Gee.ArrayList<PreviewRender> applied = new Gee.ArrayList<PreviewRender>();
            public bool off_main_thread = false;
            public Gee.ArrayList<SvgTile> tiles = new Gee.ArrayList<SvgTile>();

            public void on_ready(RenderTicket ticket, PreviewRender render) {
                if (Thread.self<void*>() != main_thread) off_main_thread = true;
                delivered.add(render);
                if (ticket.sequencer.accept(render.generation)) applied.add(render);
            }

            public void on_tile(RenderTicket ticket, SvgTile tile) {
                if (Thread.self<void*>() != main_thread) off_main_thread = true;
                tiles.add(tile);
            }
        }

        static void test_worker_burst_shows_newest_only() {
            var ticket = new RenderTicket();
            var c = new Collector();
            ticket.preview_ready.connect(c.on_ready);
            var worker = RenderWorker.get_default();

            // A slow render in flight, then quick edits superseding it
            worker.submit_preview(ticket, request(ticket, big_class_source(40)));
            Thread.usleep(30000);
            worker.submit_preview(ticket, request(ticket, sequence_source("First")));
            worker.submit_preview(ticket, request(ticket, sequence_source("Second")));
            var last = request(ticket, sequence_source("Newest"));
            worker.submit_preview(ticket, last);

            assert(spin_until(() => c.applied.size > 0 && !ticket.sequencer.pending));
            // Let anything else still queued come in
            spin_until(() => false, 1500);

            assert(!c.off_main_thread);
            assert(c.applied.size == 1);
            var shown = c.applied[0];
            assert(shown.generation == last.generation);
            assert(shown.request.source.contains("Newest"));
            assert(shown.result.status == RenderStatus.OK);
            assert(shown.result.surface != null);
            assert(shown.result.ast is SequenceDiagram);
            assert(shown.regions.size > 0);
            // Superseded renders were skipped or dropped, never shown
            foreach (var d in c.delivered) {
                if (d != shown) assert(d.generation < last.generation);
            }
        }

        static void test_worker_result_owned_by_receiver() {
            var ticket = new RenderTicket();
            var c = new Collector();
            ticket.preview_ready.connect(c.on_ready);
            var worker = RenderWorker.get_default();

            worker.submit_preview(ticket, request(ticket, sequence_source("Alpha")));
            assert(spin_until(() => c.applied.size == 1));
            var first = c.applied[0];
            int regions = first.regions.size;
            assert(regions > 0);

            // The engine reuses its region list for the next render; ours must not change
            worker.submit_preview(ticket, request(ticket, "@startuml\nclass Solo\n@enduml\n"));
            assert(spin_until(() => c.applied.size == 2));
            assert(first.regions.size == regions);
            bool has_alpha = false;
            foreach (var r in first.regions) if (r.name.contains("Alpha")) has_alpha = true;
            assert(has_alpha);
        }

        static void test_worker_detached_gets_nothing() {
            var ticket = new RenderTicket();
            var c = new Collector();
            ticket.preview_ready.connect(c.on_ready);
            RenderWorker.get_default().submit_preview(ticket, request(ticket, big_class_source(20)));
            Thread.usleep(20000);
            ticket.detach();  // the tab was closed mid-render
            spin_until(() => false, 3000);
            assert(c.delivered.size == 0);
        }

        /*
         * EngineLock really keeps the render thread out while the main thread uses the
         * engine: the parsers, the renderers and Graphviz keep static state, so the two
         * running at once corrupts it, and the transparent-background export swaps a
         * process-wide palette that a render dequeuing meanwhile would pick up.
         *
         * The proof is that a submitted render cannot finish while the main thread holds
         * the lock, and finishes as soon as it is released. Asserting only that the DOT
         * the main thread asked for came back (what this test used to do) passed just as
         * well with EngineLock deleted.
         */
        static void test_engine_lock_serializes_main_thread_use() {
            var ticket = new RenderTicket();
            var c = new Collector();
            ticket.preview_ready.connect(c.on_ready);
            var worker = RenderWorker.get_default();

            // Let anything an earlier test left in flight drain
            spin_until(() => false, 300);

            EngineLock.acquire();
            var r = request(ticket, big_class_source(15));
            worker.submit_preview(ticket, r);

            // Runs the main loop the whole time, so a finished render would be delivered
            spin_until(() => c.delivered.size > 0, 2500);
            int while_locked = c.delivered.size;

            // ... and the lock holder may use the engine itself meanwhile
            string? dot = worker.locked_engine("dot").generate_dot(sequence_source("Main"), null, null);
            EngineLock.release();

            assert(while_locked == 0);   // the worker waited instead of rendering in parallel
            assert(dot != null && dot.contains("Main"));

            // Released: the queued render goes through
            assert(spin_until(() => c.delivered.size > 0, 30000));
            assert(c.applied.size == 1);
            assert(c.applied[0].generation == r.generation);
        }

        // ── Click regions: the innermost element wins ────────────────

        /*
         * Clicking inside a container selected the container: on_click returned the FIRST
         * region whose rectangle contained the point, and a cluster is listed before the
         * nodes drawn inside it. "Web App" inside a C4 System_Boundary, and every element
         * inside `rectangle checkout { ... }`, navigated to the container's line.
         */
        static void test_click_picks_innermost_region() {
            var regions = new Gee.ArrayList<DiagramRegion>();
            // Container first, the way the renderer lists a named cluster
            regions.add(new DiagramRegion("System_Boundary", 10, 0, 0, 400, 300));
            regions.add(new DiagramRegion("WebApp", 11, 40, 40, 120, 60));
            regions.add(new DiagramRegion("Database", 12, 220, 40, 120, 60));
            // A group inside the group: the innermost of the three must win
            regions.add(new DiagramRegion("Inner", 13, 20, 20, 360, 260));

            var hit = DiagramRegion.pick(regions, 80, 60);
            assert(hit != null && hit.element_name == "WebApp" && hit.source_line == 11);
            hit = DiagramRegion.pick(regions, 260, 70);
            assert(hit != null && hit.element_name == "Database" && hit.source_line == 12);

            // Inside the inner container but on no element: the inner container
            hit = DiagramRegion.pick(regions, 200, 200);
            assert(hit != null && hit.element_name == "Inner");
            // Outside it but inside the boundary: the boundary
            hit = DiagramRegion.pick(regions, 5, 290);
            assert(hit != null && hit.element_name == "System_Boundary");
            // Outside everything
            assert(DiagramRegion.pick(regions, 500, 500) == null);
            assert(DiagramRegion.pick(new Gee.ArrayList<DiagramRegion>(), 1, 1) == null);

            // Equal areas keep the list order (regions come smallest first)
            var tied = new Gee.ArrayList<DiagramRegion>();
            tied.add(new DiagramRegion("first", 1, 0, 0, 10, 10));
            tied.add(new DiagramRegion("second", 2, 0, 0, 10, 10));
            var t = DiagramRegion.pick(tied, 5, 5);
            assert(t != null && t.element_name == "first");
        }

        // ── Document.identity_key ────────────────────────────────────

        /*
         * Opening a file asked PathIdentity for every open tab's identity, i.e. one blocking
         * query_info per tab on the main thread. Each document works its key out once.
         */
        static void test_document_identity_key_is_cached() {
            string dir;
            string path;
            try {
                dir = DirUtils.make_tmp("gdiagram-ident-XXXXXX");
                path = Path.build_filename(dir, "a.puml");
                FileUtils.set_contents(path, "@startuml\nA -> B\n@enduml\n");
            } catch (Error e) {
                error("setup: %s", e.message);
            }
            var file = File.new_for_path(path);
            var doc = new Document();
            assert(doc.identity_key == "");          // never saved

            doc.file = file;
            string key = doc.identity_key;
            assert(key == PathIdentity.key(file));
            assert(key.has_prefix("id:"));           // the file exists: device + inode

            // Deleting the file changes what PathIdentity would answer now; the document
            // keeps the key it already has, which only a cache can do
            FileUtils.remove(path);
            assert(PathIdentity.key(file) != key);
            assert(doc.identity_key == key);

            // A new file means a new key
            var other = File.new_for_path(Path.build_filename(dir, "b.puml"));
            doc.file = other;
            assert(doc.identity_key == PathIdentity.key(other));
            assert(doc.identity_key != key);

            doc.file = null;
            assert(doc.identity_key == "");
            DirUtils.remove(dir);
        }

        // ── Document.loaded ──────────────────────────────────────────

        /*
         * Save As sets `file` on the document already on screen. The preview used to reset
         * to 100% at the top-left on any path change, so naming an untitled diagram threw
         * the user's zoom and scroll away. Only loading another file's text is a document
         * change, and only that is announced.
         */
        static void test_loaded_only_on_real_load() {
            string dir;
            string path;
            try {
                dir = DirUtils.make_tmp("gdiagram-loaded-XXXXXX");
                path = Path.build_filename(dir, "a.puml");
                FileUtils.set_contents(path, "@startuml\nA -> B\n@enduml\n");
            } catch (Error e) {
                error("setup: %s", e.message);
            }
            var doc = new Document();
            int loads = 0;
            doc.loaded.connect(() => loads++);

            // Save As: a name for the text on screen, not another document
            doc.file = File.new_for_path(Path.build_filename(dir, "saved-as.puml"));
            assert(loads == 0);

            bool done = false;
            doc.load_from_file.begin(File.new_for_path(path), (obj, res) => {
                try { doc.load_from_file.end(res); } catch (Error e) { error("load: %s", e.message); }
                done = true;
            });
            assert(spin_until(() => done));
            assert(loads == 1);

            // Re-reading the same file (it changed on disk) is the same document
            done = false;
            doc.reload.begin((obj, res) => {
                try { doc.reload.end(res); } catch (Error e) { error("reload: %s", e.message); }
                done = true;
            });
            assert(spin_until(() => done));
            assert(loads == 1);

            FileUtils.remove(path);
            DirUtils.remove(dir);
        }

        static void test_worker_sharp_tile() {
            var ticket = new RenderTicket();
            var c = new Collector();
            ticket.preview_ready.connect(c.on_ready);
            ticket.tile_ready.connect(c.on_tile);
            var worker = RenderWorker.get_default();
            var req = request(ticket, "@startuml\nclass Alpha {\n  +name : String\n}\nclass Beta\nAlpha --> Beta\n@enduml\n");
            worker.submit_preview(ticket, req);
            assert(spin_until(() => c.applied.size == 1));
            var shown = c.applied[0];
            var surface = shown.result.surface;
            assert(surface != null);

            var tile = new TileRequest();
            tile.generation = ticket.sequencer.latest_applied;
            tile.source = shown.request;
            tile.serial = 7;
            tile.scale = 3.0;
            tile.x = 0;
            tile.y = 0;
            tile.width = surface.get_width();
            tile.height = surface.get_height();
            tile.base_width = surface.get_width();
            tile.base_height = surface.get_height();
            worker.submit_tile(ticket, tile);
            assert(spin_until(() => c.tiles.size == 1));
            assert(!c.off_main_thread);
            var t = c.tiles[0];
            assert(t.request.serial == 7);
            assert(t.surface != null);
            assert(t.surface.get_width() == (int) Math.ceil(surface.get_width() * 3.0));
            assert(t.surface.get_height() == (int) Math.ceil(surface.get_height() * 3.0));

            // Same picture as the bitmap: compare the tile scaled down with the preview
            t.surface.flush();
            surface.flush();
            unowned uchar[] big = t.surface.get_data();
            unowned uchar[] small = surface.get_data();
            int bs = t.surface.get_stride();
            int ss = surface.get_stride();
            int dark_small = 0, matches = 0;
            for (int y = 0; y < surface.get_height(); y++) {
                for (int x = 0; x < surface.get_width(); x++) {
                    bool s_dark = small[y * ss + x * 4 + 1] < 128;
                    if (!s_dark) continue;
                    dark_small++;
                    // any dark pixel in the matching 3x3 block of the tile
                    bool found = false;
                    for (int dy = -1; dy <= 3 && !found; dy++) {
                        for (int dx = -1; dx <= 3 && !found; dx++) {
                            int by = y * 3 + dy, bx = x * 3 + dx;
                            if (by < 0 || bx < 0 || by >= t.surface.get_height() || bx >= t.surface.get_width()) continue;
                            if (big[by * bs + bx * 4 + 1] < 160) found = true;
                        }
                    }
                    if (found) matches++;
                }
            }
            assert(dark_small > 50);
            assert(matches * 100 >= dark_small * 95);

            // Over the pixel budget: no tile rather than a huge bitmap
            var huge = new TileRequest();
            huge.scale = 5.0;
            huge.width = 2000;
            huge.height = 2000;
            huge.base_width = 2000;
            huge.base_height = 2000;
            try {
                var handle = new Rsvg.Handle.from_data("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'/>".data);
                assert(RenderWorker.rasterize_tile(handle, huge) == null);
            } catch (Error e) {
                error("svg: %s", e.message);
            }
        }

        // ── PathIdentity ─────────────────────────────────────────────

        static void test_path_identity() {
            string dir;
            try {
                dir = DirUtils.make_tmp("gdiagram-path-XXXXXX");
                DirUtils.create(Path.build_filename(dir, "sub"), 0755);
                FileUtils.set_contents(Path.build_filename(dir, "a.puml"), "@startuml\n@enduml\n");
                FileUtils.set_contents(Path.build_filename(dir, "b.puml"), "@startuml\n@enduml\n");
                FileUtils.symlink(Path.build_filename(dir, "a.puml"), Path.build_filename(dir, "link.puml"));
                FileUtils.symlink(dir, Path.build_filename(dir, "dirlink"));
            } catch (Error e) {
                error("setup: %s", e.message);
            }
            var a = File.new_for_path(Path.build_filename(dir, "a.puml"));
            var b = File.new_for_path(Path.build_filename(dir, "b.puml"));
            var link = File.new_for_path(Path.build_filename(dir, "link.puml"));
            var via_dirlink = File.new_for_path(Path.build_filename(dir, "dirlink", "a.puml"));
            // Command-line style relative path, resolved against a working directory
            var relative = File.new_for_commandline_arg_and_cwd("sub/../a.puml", dir);
            var dotted = File.new_for_commandline_arg_and_cwd("./a.puml", Path.build_filename(dir, "sub", ".."));

            assert(PathIdentity.same_file(a, a));
            assert(PathIdentity.same_file(a, link));
            assert(PathIdentity.same_file(a, via_dirlink));
            assert(PathIdentity.same_file(a, relative));
            assert(PathIdentity.same_file(dotted, a));
            assert(!PathIdentity.same_file(a, b));
            assert(!PathIdentity.same_file(link, b));

            // Not on disk: canonical paths
            var gone1 = File.new_for_path(Path.build_filename(dir, "sub", "..", "gone.puml"));
            var gone2 = File.new_for_path(Path.build_filename(dir, "gone.puml"));
            assert(PathIdentity.same_file(gone1, gone2));

            // The tab lookup: unsaved tabs (null) are skipped, the symlinked file is found
            var open_files = new Gee.ArrayList<File?>();
            open_files.add(null);
            open_files.add(b);
            open_files.add(a);
            assert(PathIdentity.index_of(open_files, link) == 2);
            assert(PathIdentity.index_of(open_files, relative) == 2);
            assert(PathIdentity.index_of(open_files, b) == 1);
            assert(PathIdentity.index_of(open_files, File.new_for_path(Path.build_filename(dir, "c.puml"))) == -1);

            FileUtils.remove(Path.build_filename(dir, "dirlink"));
            FileUtils.remove(Path.build_filename(dir, "link.puml"));
            FileUtils.remove(Path.build_filename(dir, "a.puml"));
            FileUtils.remove(Path.build_filename(dir, "b.puml"));
            DirUtils.remove(Path.build_filename(dir, "sub"));
            DirUtils.remove(dir);
        }

        // ── CleanState / Document ────────────────────────────────────

        static void test_clean_state() {
            var cs = new CleanState();
            assert(!cs.has_baseline);
            assert(!cs.is_clean(""));
            cs.mark_saved("@startuml\nA -> B\n@enduml\n");
            assert(cs.is_clean("@startuml\nA -> B\n@enduml\n"));
            assert(!cs.is_clean("@startuml\nA -> C\n@enduml\n"));  // same length
            assert(!cs.is_clean("@startuml\nA -> B\n@enduml"));
            assert(!cs.is_clean(""));
            cs.clear();
            assert(!cs.is_clean("@startuml\nA -> B\n@enduml\n"));
        }

        static void test_document_modified_follows_saved_text() {
            string path;
            try {
                string dir = DirUtils.make_tmp("gdiagram-clean-XXXXXX");
                path = Path.build_filename(dir, "doc.puml");
                FileUtils.set_contents(path, "@startuml\nA -> B\n@enduml\n");
            } catch (Error e) {
                error("setup: %s", e.message);
            }
            var doc = new Document();
            bool loaded = false;
            doc.load_from_file.begin(File.new_for_path(path), (obj, res) => {
                try {
                    doc.load_from_file.end(res);
                } catch (Error e) {
                    error("load: %s", e.message);
                }
                loaded = true;
            });
            assert(spin_until(() => loaded));
            assert(!doc.modified);

            // Typing, then undoing back to the loaded text
            doc.update_modified("@startuml\nA -> BX\n@enduml\n");
            assert(doc.modified);
            doc.update_modified("@startuml\nA -> B\n@enduml\n");
            assert(!doc.modified);

            // After a save, the saved text is the new baseline
            doc.content = "@startuml\nA -> C\n@enduml\n";
            doc.update_modified(doc.content);
            assert(doc.modified);
            bool saved = false;
            doc.save.begin((obj, res) => {
                try {
                    doc.save.end(res);
                } catch (Error e) {
                    error("save: %s", e.message);
                }
                saved = true;
            });
            assert(spin_until(() => saved));
            assert(!doc.modified);
            doc.update_modified("@startuml\nA -> B\n@enduml\n");
            assert(doc.modified);
            doc.update_modified("@startuml\nA -> C\n@enduml\n");
            assert(!doc.modified);

            FileUtils.remove(path);
            DirUtils.remove(Path.get_dirname(path));
        }

        // ── PreviewGeometry ──────────────────────────────────────────

        static PreviewView view(double vw, double vh, double iw, double ih, double zoom,
                                double sx = 0, double sy = 0, double px = 0, double py = 0) {
            return PreviewView() {
                view_w = vw, view_h = vh, img_w = iw, img_h = ih, zoom = zoom,
                scroll_x = sx, scroll_y = sy, pan_x = px, pan_y = py
            };
        }

        static void assert_anchor_kept(PreviewView before, double new_zoom, double ax, double ay) {
            double ix0, iy0, ix1, iy1;
            PreviewGeometry.image_point(before, ax, ay, out ix0, out iy0);
            var after = PreviewGeometry.zoom_at(before, new_zoom, ax, ay);
            PreviewGeometry.image_point(after, ax, ay, out ix1, out iy1);
            if (Math.fabs(ix0 - ix1) > 1e-6 || Math.fabs(iy0 - iy1) > 1e-6) {
                error("anchor (%.1f,%.1f) at zoom %.2f -> %.2f moved from (%.3f,%.3f) to (%.3f,%.3f)",
                    ax, ay, before.zoom, new_zoom, ix0, iy0, ix1, iy1);
            }
        }

        static void test_zoom_keeps_anchor() {
            // Fits before and after: the pan moves the diagram
            assert_anchor_kept(view(800, 600, 200, 100, 1.0), 1.2, 350, 280);
            // Fits, then larger than the viewport (the zoom-in button's case)
            assert_anchor_kept(view(800, 600, 600, 500, 1.0), 1.44, 400, 300);
            // Scrolled, zooming in and out around the viewport centre
            assert_anchor_kept(view(800, 600, 2000, 1500, 1.0, 500, 400), 1.2, 400, 300);
            assert_anchor_kept(view(800, 600, 2000, 1500, 1.2, 700, 600), 1.0, 400, 300);
            // Around the pointer
            assert_anchor_kept(view(800, 600, 2000, 1500, 2.0, 1000, 900), 2.4, 120, 510);
            // A diagram wider than the viewport but not as tall: the scrolling direction keeps it
            var wide = view(800, 600, 3000, 200, 1.0, 1000, 0);
            double ix0, iy0, ix1, iy1;
            PreviewGeometry.image_point(wide, 400, 300, out ix0, out iy0);
            var wide_after = PreviewGeometry.zoom_at(wide, 1.2, 400, 300);
            PreviewGeometry.image_point(wide_after, 400, 300, out ix1, out iy1);
            assert(Math.fabs(ix0 - ix1) < 1e-6);
            assert(Math.fabs(iy0 - iy1) < 1e-6);  // centred vertically before and after

            // The old button zoom kept the scroll position: the centre point moved
            var before = view(800, 600, 2000, 1500, 1.0, 500, 400);
            var top_left_anchored = before;
            top_left_anchored.zoom = 1.2;
            double ox, oy, nx, ny;
            PreviewGeometry.image_point(before, 400, 300, out ox, out oy);
            PreviewGeometry.image_point(top_left_anchored, 400, 300, out nx, out ny);
            assert(Math.fabs(ox - nx) > 50);

            // Scroll positions stay in range at the edges
            var edge = PreviewGeometry.zoom_at(view(800, 600, 2000, 1500, 1.0, 1200, 900), 0.5, 790, 590);
            assert(edge.scroll_x >= 0 && edge.scroll_x <= double.max(0, 2000 * 0.5 - 800));
            assert(edge.scroll_y >= 0 && edge.scroll_y <= double.max(0, 1500 * 0.5 - 600));

            assert(PreviewGeometry.clamp_zoom(9) == PreviewGeometry.MAX_ZOOM);
            assert(PreviewGeometry.clamp_zoom(0.01) == PreviewGeometry.MIN_ZOOM);
        }

        static void test_tile_plan() {
            PreviewRect tile;
            // At or below 100% the bitmap is sharp
            assert(!PreviewGeometry.plan_tile(view(800, 600, 2000, 1500, 1.0), 1.0, RenderWorker.MAX_TILE_PIXELS, out tile));

            var v = view(800, 600, 2000, 1500, 3.0, 2400, 1500);
            assert(PreviewGeometry.plan_tile(v, 3.0, RenderWorker.MAX_TILE_PIXELS, out tile));
            var visible = PreviewGeometry.visible_rect(v);
            assert(tile.contains_rect(visible));
            assert(tile.width * tile.height * 9 <= RenderWorker.MAX_TILE_PIXELS);
            assert(PreviewGeometry.tile_device_pixels(tile.width, tile.height, 3.0)
                <= RenderWorker.MAX_TILE_PIXELS);
            assert(tile.x >= 0 && tile.y >= 0 && tile.x + tile.width <= 2000 && tile.y + tile.height <= 1500);

            // A huge window on a big diagram at 5x: cut to the budget around the view
            var big = view(3840, 2160, 20000, 20000, 5.0, 40000, 40000);
            assert(PreviewGeometry.plan_tile(big, 5.0, RenderWorker.MAX_TILE_PIXELS, out tile));
            assert(tile.width * tile.height * 25 <= RenderWorker.MAX_TILE_PIXELS);
            assert(PreviewGeometry.tile_device_pixels(tile.width, tile.height, 5.0)
                <= RenderWorker.MAX_TILE_PIXELS);
            var big_visible = PreviewGeometry.visible_rect(big);
            double cx = big_visible.x + big_visible.width / 2, cy = big_visible.y + big_visible.height / 2;
            assert(tile.x <= cx && cx <= tile.x + tile.width && tile.y <= cy && cy <= tile.y + tile.height);

            // The surface the rasterizer actually allocates has to fit too: it rounds both
            // axes up, so a tile planned exactly on the budget came out up to w + h + 1
            // device pixels too big and was refused — and a refused tile used to switch
            // sharp zoom off for the whole bitmap. Integer scales hide it; this viewport
            // (found by searching the parameter space) does not.
            double odd = 1.240398;
            var tight = view(3840, 1440, 37160, 39919, odd, 35109.769, 8813.643);
            assert(PreviewGeometry.plan_tile(tight, odd, RenderWorker.MAX_TILE_PIXELS, out tile));
            Test.message("tight tile %.0fx%.0f -> %" + int64.FORMAT + " device pixels (cap %d)",
                tile.width, tile.height,
                PreviewGeometry.tile_device_pixels(tile.width, tile.height, odd),
                RenderWorker.MAX_TILE_PIXELS);
            assert(PreviewGeometry.tile_device_pixels(tile.width, tile.height, odd)
                <= RenderWorker.MAX_TILE_PIXELS);
            assert(tile.width > 5000 && tile.height > 1800);   // still a useful tile
            assert(tile.contains_rect(PreviewGeometry.visible_rect(tight)));
        }

        public static int main(string[] args) {
            Test.init(ref args);
            main_thread = Thread.self<void*>();
            Test.add_func("/review_gui/sequencer_supersede", test_sequencer_supersede);
            Test.add_func("/review_gui/sequencer_never_older", test_sequencer_never_older);
            Test.add_func("/review_gui/worker_burst_shows_newest_only", test_worker_burst_shows_newest_only);
            Test.add_func("/review_gui/worker_result_owned_by_receiver", test_worker_result_owned_by_receiver);
            Test.add_func("/review_gui/worker_detached_gets_nothing", test_worker_detached_gets_nothing);
            Test.add_func("/review_gui/engine_lock_serializes", test_engine_lock_serializes_main_thread_use);
            Test.add_func("/review_gui/worker_sharp_tile", test_worker_sharp_tile);
            Test.add_func("/review_gui/click_picks_innermost_region", test_click_picks_innermost_region);
            Test.add_func("/review_gui/path_identity", test_path_identity);
            Test.add_func("/review_gui/document_identity_key_cached", test_document_identity_key_is_cached);
            Test.add_func("/review_gui/loaded_only_on_real_load", test_loaded_only_on_real_load);
            Test.add_func("/review_gui/clean_state", test_clean_state);
            Test.add_func("/review_gui/document_modified", test_document_modified_follows_saved_text);
            Test.add_func("/review_gui/zoom_keeps_anchor", test_zoom_keeps_anchor);
            Test.add_func("/review_gui/tile_plan", test_tile_plan);
            return Test.run();
        }
    }
}
