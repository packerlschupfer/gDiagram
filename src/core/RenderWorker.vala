namespace GDiagram {

    /**
     * Serializes every use of parsers, renderers and Graphviz in the process.
     *
     * They keep static state that is not thread-safe (id counters, lazily built
     * regexes, Graphviz's global parser state, SequenceDiagramRenderer.image_base_dir),
     * so at most one thread may run any of them at a time. The render thread holds
     * this lock for each job; UI-thread code that still parses or renders directly
     * (export, the compare / git history dialogs, the git graph view) takes it too
     * and waits for at most the one render in flight.
     */
    public class EngineLock {
        private static RecMutex mutex;

        public static void acquire() {
            mutex.lock();
        }

        public static void release() {
            mutex.unlock();
        }
    }

    /**
     * Orders preview renders of one document: every request gets a newer generation,
     * and a result is applied only if it belongs to the newest request and nothing newer
     * was applied yet. A newer edit supersedes a render still in flight, and an older
     * result can never replace a newer one. Main thread only.
     */
    public class RenderSequencer : Object {
        public int latest_requested { get; private set; default = 0; }
        public int latest_applied { get; private set; default = 0; }

        // A new request; results of all earlier ones become stale
        public int begin() {
            latest_requested++;
            return latest_requested;
        }

        public bool is_current(int generation) {
            return generation == latest_requested;
        }

        // True when this result may be shown (and records it as shown)
        public bool accept(int generation) {
            if (generation != latest_requested || generation <= latest_applied) return false;
            latest_applied = generation;
            return true;
        }

        public bool pending {
            get { return latest_requested > latest_applied; }
        }
    }

    // What to render: a snapshot of the document taken on the main thread
    public class RenderRequest : Object {
        public int generation;
        public string source;
        public string? doc_filename;
        public string? base_path;
        public string layout_engine;

        public RenderRequest(string source, string? doc_filename, string? base_path, string layout_engine) {
            this.source = source;
            this.doc_filename = doc_filename;
            this.base_path = base_path;
            this.layout_engine = layout_engine;
        }
    }

    /**
     * A finished preview render, handed from the render thread to the main thread.
     * Everything in it is owned by the receiver: lists are copies, so the engine reusing
     * its own lists for the next render cannot change them.
     */
    public class PreviewRender : Object {
        public int generation;
        public RenderRequest request;
        public DiagramFormat format;
        public DiagramType diagram_type;
        public RenderResult result;
        public Gee.ArrayList<ElementRegion> regions;
        public double elapsed_ms;
        /**
         * What this render had to scale down to stay inside the Cairo image size limit
         * ("PNG scaled down from 221x35940 to 201x32767 px ..."), or null.
         *
         * RenderUtils records that globally, so it is taken here — on the render thread,
         * under EngineLock, right after the render that may have set it — rather than read
         * from the main thread, where an unrelated render or export could have replaced it.
         * The GUI shows it when the render produced no bitmap: without it the preview said
         * only "Failed to render class diagram" while the CLI printed the size it hit.
         */
        public string? downscale_note;
    }

    // A sharper rendering of part of the diagram at a zoom above 100% (see PreviewPane)
    public class TileRequest : Object {
        public int generation;       // preview generation the tile belongs to
        public RenderRequest source;  // the request that produced that preview
        public int serial;           // PreviewPane surface serial, echoed back
        public double scale;         // device pixels per diagram pixel
        public double x;             // area in diagram pixels
        public double y;
        public double width;
        public double height;
        public int base_width;       // size of the preview surface
        public int base_height;
    }

    public class SvgTile : Object {
        public TileRequest request;
        public Cairo.ImageSurface? surface;  // null: nothing to draw, see svg_missing
        // True only when this diagram has no SVG at all, so sharp zoom can be switched off
        // for it. A null surface with this false is one tile that failed (too many pixels,
        // or a draw error) and says nothing about the rest of the diagram.
        public bool svg_missing;
    }

    /**
     * One document's connection to the render thread. The worker delivers results
     * through the signals, always on the main thread. detach() before the document
     * view goes away: results still in flight are then dropped.
     */
    public class RenderTicket : Object {
        public RenderSequencer sequencer { get; private set; }
        public signal void preview_ready(PreviewRender render);
        public signal void tile_ready(SvgTile tile);

        // Newest generation, readable from the worker to skip stale jobs early
        internal int latest = 0;
        internal int detached = 0;

        // Render thread only: SVG of one preview generation, for sharp zoom tiles
        internal int svg_generation = 0;
        internal Rsvg.Handle? svg_handle = null;
        internal bool svg_missing = false;

        construct {
            sequencer = new RenderSequencer();
        }

        // Main thread: a new request, superseding the ones in flight
        public int begin() {
            int generation = sequencer.begin();
            AtomicInt.set(ref latest, generation);
            return generation;
        }

        public bool is_stale(int generation) {
            return AtomicInt.get(ref detached) != 0 || generation != AtomicInt.get(ref latest);
        }

        public void detach() {
            AtomicInt.set(ref detached, 1);
        }

        public bool is_detached() {
            return AtomicInt.get(ref detached) != 0;
        }
    }

    /**
     * The render thread. Owns the one DiagramEngine the GUI uses; jobs run one at a time
     * under EngineLock. A queued preview job is replaced by a newer one for the same
     * document, and jobs whose generation became stale are skipped before they start.
     */
    public class RenderWorker : Object {
        private static RenderWorker? instance = null;

        // Largest sharp tile in device pixels (16 MP, 64 MB)
        public const int MAX_TILE_PIXELS = 4096 * 4096;

        private class Job {
            public RenderTicket? ticket;
            public RenderRequest? preview;
            public TileRequest? tile;
            public Object? garbage;
        }

        private Mutex queue_mutex;
        private Cond queue_cond;
        private Gee.LinkedList<Job> queue = new Gee.LinkedList<Job>();
        private Thread<bool>? thread = null;
        private DiagramEngine? engine = null;

        public static RenderWorker get_default() {
            if (instance == null) instance = new RenderWorker();
            return instance;
        }

        /**
         * The shared engine, for synchronous callers on any thread. Only valid while the
         * caller holds EngineLock.
         */
        public DiagramEngine locked_engine(string layout_engine) {
            if (engine == null) engine = new DiagramEngine(layout_engine);
            engine.set_layout_engine(layout_engine);
            return engine;
        }

        public void submit_preview(RenderTicket ticket, RenderRequest request) {
            var job = new Job();
            job.ticket = ticket;
            job.preview = request;
            enqueue(job);
        }

        public void submit_tile(RenderTicket ticket, TileRequest request) {
            var job = new Job();
            job.ticket = ticket;
            job.tile = request;
            enqueue(job);
        }

        /**
         * Drop the main thread's last reference to `garbage` on the render thread. A big
         * diagram's bitmap is hundreds of megabytes, and freeing the previous one when a new
         * render was shown took the main thread about 100 ms.
         */
        public void release_later(owned Object garbage) {
            var job = new Job();
            job.garbage = (owned) garbage;
            enqueue(job);
        }

        private void enqueue(Job job) {
            queue_mutex.lock();
            // Only the newest job of each kind per document matters
            var it = queue.iterator();
            while (job.ticket != null && it.next()) {
                var queued = it.get();
                if (queued.ticket == job.ticket && (queued.preview != null) == (job.preview != null)) {
                    it.remove();
                }
            }
            queue.add(job);
            if (thread == null) {
                thread = new Thread<bool>("gdiagram-render", run);
            }
            queue_cond.signal();
            queue_mutex.unlock();
        }

        private bool run() {
            while (true) {
                queue_mutex.lock();
                while (queue.is_empty) {
                    queue_cond.wait(queue_mutex);
                }
                var job = queue.poll_head();
                queue_mutex.unlock();

                if (job.preview != null) {
                    run_preview_job(job.ticket, job.preview);
                } else if (job.tile != null) {
                    run_tile_job(job.ticket, job.tile);
                }
                // Frees garbage (and anything else the job held) here, off the main thread
                job = null;
            }
        }

        private void run_preview_job(RenderTicket ticket, RenderRequest request) {
            if (ticket.is_stale(request.generation)) return;
            EngineLock.acquire();
            PreviewRender render;
            try {
                render = render_preview(locked_engine(request.layout_engine), request);
            } finally {
                EngineLock.release();
            }
            if (ticket.is_stale(request.generation)) return;
            deliver_preview(ticket, render);
        }

        private static void deliver_preview(RenderTicket ticket, PreviewRender render) {
            Idle.add(() => {
                if (!ticket.is_detached()) ticket.preview_ready(render);
                return Source.REMOVE;
            });
        }

        private static void deliver_tile(RenderTicket ticket, SvgTile tile) {
            Idle.add(() => {
                if (!ticket.is_detached()) ticket.tile_ready(tile);
                return Source.REMOVE;
            });
        }

        /**
         * Detect, preprocess and render one request: the GUI's whole render pipeline.
         * The caller holds EngineLock.
         */
        public static PreviewRender render_preview(DiagramEngine engine, RenderRequest request) {
            int64 start = get_monotonic_time();
            var render = new PreviewRender();
            render.generation = request.generation;
            render.request = request;

            string source = request.source;
            render.format = engine.detect_format(source, request.doc_filename);
            string render_source;
            if (render.format == DiagramFormat.MERMAID) {
                // Mermaid diagrams don't need preprocessing
                render_source = source;
                render.diagram_type = engine.detect_mermaid_type(source);
            } else {
                render_source = engine.preprocess(source, request.base_path);
                render.diagram_type = engine.detect_plantuml_type(render_source);
            }

            // Cleared first so a note left by an earlier render or export is not read as
            // this render's (see PreviewRender.downscale_note)
            RenderUtils.png_downscale_note = null;
            render.result = engine.render(render.diagram_type, render.format, render_source);
            render.downscale_note = RenderUtils.png_downscale_note;
            if (render.result.errors != null) {
                var errors = new Gee.ArrayList<ParseError>();
                errors.add_all(render.result.errors);
                render.result.errors = errors;
            }
            render.regions = new Gee.ArrayList<ElementRegion>();
            render.regions.add_all(engine.last_regions);
            render.elapsed_ms = (get_monotonic_time() - start) / 1000.0;
            return render;
        }

        private void run_tile_job(RenderTicket ticket, TileRequest request) {
            if (ticket.is_stale(request.generation)) {
                // A newer preview is coming; its tiles will be asked for again
                return;
            }
            if (ticket.svg_generation != request.generation) {
                ticket.svg_generation = request.generation;
                ticket.svg_handle = null;
                ticket.svg_missing = false;
                uint8[]? svg = null;
                var src = request.source;
                EngineLock.acquire();
                try {
                    svg = locked_engine(src.layout_engine).generate_svg(src.source, src.doc_filename, src.base_path);
                } finally {
                    EngineLock.release();
                }
                if (svg != null && svg.length > 0) {
                    try {
                        var stream = new MemoryInputStream.from_data(svg);
                        ticket.svg_handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);
                    } catch (Error e) {
                        ticket.svg_handle = null;
                    }
                }
                ticket.svg_missing = ticket.svg_handle == null;
            }
            if (ticket.is_stale(request.generation)) return;

            var tile = new SvgTile();
            tile.request = request;
            tile.svg_missing = ticket.svg_missing;
            tile.surface = ticket.svg_missing ? null : rasterize_tile(ticket.svg_handle, request);
            deliver_tile(ticket, tile);
        }

        /**
         * Draw `request`'s area of the SVG at its scale. The document is fitted to the
         * preview surface's size, so tile pixels line up with the bitmap preview and the
         * click regions. Returns null for an empty or oversized area.
         */
        public static Cairo.ImageSurface? rasterize_tile(Rsvg.Handle handle, TileRequest request) {
            int w = (int) Math.ceil(request.width * request.scale);
            int h = (int) Math.ceil(request.height * request.scale);
            if (w <= 0 || h <= 0 || (int64) w * h > MAX_TILE_PIXELS) return null;

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context(surface);
            cr.scale(request.scale, request.scale);
            cr.translate(-request.x, -request.y);
            // Same white underlay as the preview bitmap (RenderUtils.svg_to_surface)
            cr.set_source_rgb(1, 1, 1);
            cr.rectangle(request.x, request.y, request.width, request.height);
            cr.fill();
            var viewport = Rsvg.Rectangle() {
                x = 0, y = 0, width = request.base_width, height = request.base_height
            };
            try {
                handle.render_document(cr, viewport);
            } catch (Error e) {
                return null;
            }
            return surface;
        }
    }
}
