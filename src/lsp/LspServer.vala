namespace GDiagram {

    // _exit(2): terminate without running atexit handlers or flushing stdio.
    // The reader thread parks in getc() holding stdin's stdio lock, so the normal
    // exit() path deadlocks in _IO_flush_all trying to take that same lock.
    [CCode (cname = "_exit", cheader_filename = "unistd.h")]
    private extern void lsp_immediate_exit(int status);

    // kill(2)/waitpid(2) are used directly (rather than g_subprocess_force_exit) when the
    // server is about to _exit(): see LspServer.kill_worker_now(). Declared here because
    // the LSP binary does not link --pkg=posix.
    [CCode (cname = "kill", cheader_filename = "signal.h")]
    private extern int lsp_kill(int pid, int sig);
    [CCode (cname = "waitpid", cheader_filename = "sys/wait.h")]
    private extern int lsp_waitpid(int pid, out int status, int options);

    /**
     * LSP server for gDiagram. Communicates via JSON-RPC over stdin/stdout.
     * Supports PlantUML and Mermaid diagram editing with diagnostics,
     * completion, hover, document symbols, and custom rendering commands.
     *
     * Threading: a reader thread only frames incoming messages and queues them
     * on the main loop, which handles them in order. Parsing (didOpen/didChange,
     * completion, hover, symbols) runs on the main loop. Rendering and export run
     * in a child process of this binary (`gdiagram-lsp --render-worker`), so a
     * slow render never blocks diagnostics and a renderSvg that a newer renderSvg
     * for the same document supersedes is killed and answered with
     * RequestCancelled (-32800). A process rather than a thread: the parsers and
     * renderers keep static state (id counters, lazily built regexes, Graphviz)
     * that is not safe to use from two threads.
     */
    public class LspServer : Object {
        private const int REQUEST_CANCELLED = -32800;
        private const int INVALID_PARAMS = -32602;
        private const int INTERNAL_ERROR = -32603;

        // A worker that has not finished after this long is wedged (a Graphviz layout
        // that never converges): kill it so the request is answered instead of lost.
        private const uint WORKER_TIMEOUT_SECONDS = 120;

        // Largest LSP message body accepted, in bytes. A header asking for more is a
        // typo or a hostile/desynchronised stream, not a diagram: the biggest thing a
        // client ever sends is a document's full text on didChange.
        private const int64 MAX_CONTENT_LENGTH = 64 * 1024 * 1024;

        // SIGKILL; the Posix vapi is not linked into this binary
        private const int SIGKILL_NUMBER = 9;

        private Gee.HashMap<string, LspDocumentState> documents;
        private bool shutdown_requested = false;
        private MainLoop loop;

        // One shared engine for the whole server: owns every parser/renderer
        // instance and is handed to each open document so reparses reuse the
        // same parsers instead of allocating fresh ones per keystroke.
        private DiagramEngine engine;

        // Raw file streams for LSP I/O (input only touched by the reader thread,
        // output only by the main loop)
        private FileStream input_fs;
        private FileStream output_fs;

        // This executable, re-run as the render worker
        private string worker_path;
        // The running renderSvg per document URI (a newer one cancels it) and running exports
        private Gee.HashMap<string, RenderJob> renders = new Gee.HashMap<string, RenderJob>();
        private Gee.ArrayList<RenderJob> exports = new Gee.ArrayList<RenderJob>();

        private class RenderJob : Object {
            public Json.Node? id;
            public string uri;
            public Subprocess process;
            public Cancellable cancellable = new Cancellable();
            public string? output_path;
            // Watchdog source that kills a wedged worker; removed when the job finishes
            public uint timeout_id = 0;

            // True when this job answers the request carrying `other` (for $/cancelRequest)
            public bool has_id(Json.Node other) {
                if (id == null || id.get_node_type() != Json.NodeType.VALUE ||
                    other.get_node_type() != Json.NodeType.VALUE) return false;
                if (id.get_value_type() != other.get_value_type()) return false;
                if (id.get_value_type() == typeof(int64)) return id.get_int() == other.get_int();
                if (id.get_value_type() == typeof(string)) return id.get_string() == other.get_string();
                return false;
            }

            public void finish() {
                if (timeout_id != 0) {
                    Source.remove(timeout_id);
                    timeout_id = 0;
                }
            }
        }

        public LspServer(string? worker_path = null) {
            documents = new Gee.HashMap<string, LspDocumentState>();
            engine = new DiagramEngine("dot");
            string? self_path = null;
            try {
                self_path = FileUtils.read_link("/proc/self/exe");
            } catch (FileError e) {
            }
            this.worker_path = worker_path ?? self_path ?? "gdiagram-lsp";
        }

        /**
         * Main run loop. Reads JSON-RPC messages from stdin, dispatches, responds.
         * Returns exit code (0 on clean shutdown, 1 on error).
         */
        public int run() {
            input_fs = FileStream.fdopen(0, "rb");
            output_fs = FileStream.fdopen(1, "wb");
            loop = new MainLoop();

            log_debug("gdiagram-lsp started");

            new Thread<void*>("lsp-reader", read_loop);
            loop.run();

            foreach (var job in renders.values) {
                job.finish();
                kill_worker_now(job.process);
            }
            foreach (var job in exports) {
                job.finish();
                kill_worker_now(job.process);
            }

            // Spec exit codes: 0 when `exit` followed `shutdown`, 1 otherwise.
            int status = shutdown_requested ? 0 : 1;
            output_fs.flush();
            stderr.flush();
            // Returning from main() here would hang forever: the reader thread is
            // parked in getc() on stdin and exit()'s _IO_flush_all blocks on that
            // stream's lock. Everything this process owns is already flushed.
            lsp_immediate_exit(status);
            return status;
        }

        /**
         * Kill a render worker and reap it, before this process can exit.
         *
         * g_subprocess_force_exit() is asynchronous: it only wakes GLib's worker thread,
         * which then issues the kill(). lsp_immediate_exit() below stops every thread at
         * once, so that signal was usually never sent and the worker outlived the server
         * — running to completion at 100% CPU, or forever when its layout was wedged (its
         * watchdog died with us). Signal it here instead, on this thread, and wait for it.
         */
        private static void kill_worker_now(Subprocess process) {
            string? ident = process.get_identifier();   // the pid, on UNIX
            if (ident == null) return;                  // already reaped
            int pid = int.parse(ident);
            if (pid <= 0) return;
            lsp_kill(pid, SIGKILL_NUMBER);
            int status = 0;
            lsp_waitpid(pid, out status, 0);
        }

        // Reader thread: frames messages and hands them to the main loop in order
        private void* read_loop() {
            while (true) {
                string? json_body = null;
                try {
                    json_body = read_message();
                } catch (Error e) {
                    // Continue reading -- don't crash on malformed input. The rejected
                    // frame's body is still in the stream; the header scan above steps
                    // over it and picks up the next Content-Length.
                    report_framing_error(e.message);
                    continue;
                }
                if (json_body == null) {
                    log_debug("EOF on stdin, exiting");
                    Idle.add(() => {
                        loop.quit();
                        return Source.REMOVE;
                    });
                    return null;
                }
                string body = (owned) json_body;
                Idle.add(() => {
                    handle_message(body);
                    return Source.REMOVE;
                });
            }
        }

        // The value of a Content-Length header found anywhere in `line`, or null.
        //
        // Matching only at the START of a line is not enough once the stream is out of
        // step: an LSP body has no trailing newline, so a header the reader lands in
        // front of arrives as "<rest of a body>Content-Length: 55". Taking the last
        // occurrence anywhere in the line picks it up instead of skipping the line and
        // every message behind it. (The body reader below catches the common case
        // first; this is the second chance.)
        private static string? content_length_value(string line) {
            int at = line.down().last_index_of("content-length:");
            if (at < 0) return null;
            return line.substring(at + "content-length:".length).strip();
        }

        // A Content-Length value this server will act on, or -1 with `why` set.
        // int.parse() took anything: "Content-Length: 2147483647" overflowed the
        // `content_length + 1` allocation below into a 18-exabyte request, and GLib
        // aborts the whole process on a failed allocation, losing every open document.
        private static int64 validated_content_length(string val, out string? why) {
            why = null;
            if (val.length == 0) {
                why = "empty Content-Length";
                return -1;
            }
            for (int i = 0; i < val.length; i++) {
                if (val[i] < '0' || val[i] > '9') {
                    why = "Content-Length is not a number: '%s'".printf(val);
                    return -1;
                }
            }
            int64 parsed;
            if (!int64.try_parse(val, out parsed) || parsed < 0) {
                why = "Content-Length out of range: '%s'".printf(val);
                return -1;
            }
            if (parsed == 0) {
                why = "Content-Length is 0";
                return -1;
            }
            if (parsed > MAX_CONTENT_LENGTH) {
                why = "Content-Length %s exceeds the %lld byte limit".printf(val, MAX_CONTENT_LENGTH);
                return -1;
            }
            return parsed;
        }

        // Tell the client about a frame we refused, from the reader thread: the
        // response has to be written by the main loop, which owns stdout.
        private void report_framing_error(string why) {
            log_debug("Bad message frame: %s".printf(why));
            string message = why;
            Idle.add(() => {
                send_error(null, -32700, "Invalid message framing: %s".printf(message));
                return Source.REMOVE;
            });
        }

        // The header name a body may run into when the frame before it lied about its
        // length; see the resynchronisation in read_message().
        private const string HEADER_MARKER = "Content-Length:";

        // Set when the body reader has already taken a "Content-Length:" off the stream
        // while resynchronising: the next read_message() finds its value on the line it
        // starts at. Reader thread only.
        private bool resync_header_consumed = false;

        // True when the first `length` bytes of `buffer` are a whole JSON object — the
        // test for "the message really ended here" when a body runs into what looks like
        // the next header. An LSP body containing the text "Content-Length:" (a document
        // about LSP, say) is still an unfinished object at that point, so it is left alone.
        private static bool is_complete_json_object(uint8[] buffer, int64 length) {
            if (length <= 0) return false;
            uint8[] copy = new uint8[length + 1];
            Memory.copy(copy, buffer, (size_t) length);
            copy[length] = 0;
            var parser = new Json.Parser();
            try {
                parser.load_from_data((string) copy, (ssize_t) length);
            } catch (Error e) {
                return false;
            }
            var root = parser.get_root();
            return root != null && root.get_node_type() == Json.NodeType.OBJECT;
        }

        /**
         * Read a single LSP message (Content-Length header + JSON body).
         *
         * Returns null on EOF. A frame this server will not act on (no, or an absurd,
         * Content-Length) is skipped and reported — the reader keeps going rather than
         * taking the server down with it. A body that runs into the next message's
         * header (the frame before it declared more bytes than it sent) ends there, and
         * framing picks up again at that header: a single short body used to leave the
         * reader stuck in getc() waiting for bytes that never came, and every request
         * after it went unanswered for the life of the process.
         */
        private string? read_message() throws Error {
            // Read headers until blank line
            int64 content_length = -1;
            string? reject_reason = null;

            if (resync_header_consumed) {
                // "Content-Length:" is already off the stream; its value is the rest of
                // the line we are standing on.
                resync_header_consumed = false;
                string? value_line = read_line_from_stdin();
                if (value_line == null) return null;
                string? why;
                content_length = validated_content_length(value_line.strip(), out why);
                if (content_length < 0) reject_reason = why;
            }

            while (true) {
                string? line = read_line_from_stdin();
                if (line == null) return null; // EOF

                string trimmed = line.strip();

                if (trimmed.length == 0) {
                    // End of headers
                    break;
                }

                string? val = content_length_value(trimmed);
                if (val != null) {
                    string? why;
                    content_length = validated_content_length(val, out why);
                    if (content_length < 0) reject_reason = why;
                }
                // Ignore other headers (Content-Type, etc.)
            }

            if (content_length <= 0) {
                throw new IOError.INVALID_DATA(reject_reason ?? "Missing or invalid Content-Length header");
            }

            // Read exactly content_length bytes, unless the next header turns up first
            uint8[] buffer = new uint8[content_length + 1]; // +1 for null terminator
            int64 total_read = 0;
            int matched = 0;                      // characters of HEADER_MARKER seen
            while (total_read < content_length) {
                int ch = input_fs.getc();
                if (ch == FileStream.EOF) {
                    return null;
                }
                buffer[total_read] = (uint8) ch;
                total_read++;

                if (ch == HEADER_MARKER[matched]) {
                    matched++;
                } else {
                    matched = (ch == HEADER_MARKER[0]) ? 1 : 0;
                }
                if (matched < HEADER_MARKER.length) continue;
                matched = 0;
                int64 body_end = total_read - HEADER_MARKER.length;
                if (!is_complete_json_object(buffer, body_end)) continue;

                log_debug(("Resynchronised: a body declared %s bytes but ended after %s; " +
                           "framing resumes at the next header").printf(
                           content_length.to_string(), body_end.to_string()));
                resync_header_consumed = true;
                buffer[body_end] = 0;
                return (string) buffer;
            }
            buffer[content_length] = 0; // null-terminate

            return (string) buffer;
        }

        /**
         * Read a line from stdin (up to \n). Returns null on EOF.
         */
        private string? read_line_from_stdin() {
            var sb = new StringBuilder();
            while (true) {
                int ch = input_fs.getc();
                if (ch == FileStream.EOF) {
                    if (sb.len == 0) return null;
                    return sb.str;
                }
                if (ch == '\n') {
                    return sb.str;
                }
                sb.append_c((char) ch);
            }
        }

        /**
         * Send a JSON-RPC message to stdout with Content-Length header.
         */
        private void send_message(string json) {
            string header = "Content-Length: %d\r\n\r\n".printf(json.length);
            output_fs.printf("%s", header);
            output_fs.printf("%s", json);
            output_fs.flush();
        }

        private static void add_id(Json.Object response, Json.Node? id) {
            if (id != null && id.get_node_type() == Json.NodeType.VALUE) {
                if (id.get_value_type() == typeof(int64)) {
                    response.set_int_member("id", id.get_int());
                    return;
                }
                if (id.get_value_type() == typeof(string)) {
                    response.set_string_member("id", id.get_string());
                    return;
                }
            }
            response.set_null_member("id");
        }

        private static string to_json(Json.Object obj) {
            var root = new Json.Node(Json.NodeType.OBJECT);
            root.set_object(obj);
            var gen = new Json.Generator();
            gen.root = root;
            return gen.to_data(null);
        }

        /**
         * Send a JSON-RPC response for a given request id.
         */
        private void send_response(Json.Node? id, Json.Node? result) {
            var response = new Json.Object();
            response.set_string_member("jsonrpc", "2.0");
            add_id(response, id);
            if (result != null) {
                response.set_member("result", result.copy());
            } else {
                response.set_null_member("result");
            }
            send_message(to_json(response));
        }

        /**
         * Send a JSON-RPC error response.
         */
        private void send_error(Json.Node? id, int code, string message) {
            var response = new Json.Object();
            response.set_string_member("jsonrpc", "2.0");
            add_id(response, id);
            var error = new Json.Object();
            error.set_int_member("code", code);
            error.set_string_member("message", message);
            response.set_object_member("error", error);
            send_message(to_json(response));
        }

        /**
         * Send a JSON-RPC notification (no id).
         */
        private void send_notification(string json) {
            send_message(json);
        }

        // A request with unusable params gets an error; a notification is ignored
        private void invalid_params(Json.Node? id, string what) {
            log_debug("Invalid params: %s".printf(what));
            if (id != null) send_error(id, INVALID_PARAMS, "Invalid params: %s".printf(what));
        }

        /**
         * Parse and dispatch a JSON-RPC message.
         */
        private void handle_message(string json_body) {
            var parser = new Json.Parser();
            try {
                parser.load_from_data(json_body);
            } catch (Error e) {
                log_debug("Failed to parse JSON: %s".printf(e.message));
                send_error(null, -32700, "Parse error: %s".printf(e.message));
                return;
            }

            var obj = LspProtocol.as_object(parser.get_root());
            if (obj == null) {
                send_error(null, -32600, "Invalid Request: expected JSON object");
                return;
            }

            Json.Node? id_node = obj.has_member("id") ? obj.get_member("id") : null;
            if (id_node != null && id_node.get_node_type() != Json.NodeType.VALUE) id_node = null;
            string? method = LspProtocol.string_member(obj, "method");
            Json.Node? params_node = obj.has_member("params") ? obj.get_member("params") : null;

            if (method == null) {
                send_error(id_node, -32600, "Invalid Request: missing method");
                return;
            }

            log_debug("Received: %s".printf(method));

            // A request method sent without an id is a notification, and JSON-RPC 2.0
            // forbids replying to one. Answering it with "id": null (what every handler
            // below would do) is a protocol violation, so drop it instead.
            if (id_node == null && is_request_method(method)) {
                log_debug("Ignoring request method sent as a notification: %s".printf(method));
                return;
            }

            switch (method) {
                case "$/cancelRequest":
                    cancel_request(LspProtocol.as_object(params_node));
                    break;
                case "initialize":
                    send_response(id_node, LspProtocol.build_initialize_result());
                    break;
                case "initialized":
                    break;
                case "shutdown":
                    shutdown_requested = true;
                    send_response(id_node, null);
                    break;
                case "exit":
                    loop.quit();
                    break;
                case "textDocument/didOpen":
                    handle_did_open(params_node);
                    break;
                case "textDocument/didChange":
                    handle_did_change(params_node);
                    break;
                case "textDocument/didClose":
                    handle_did_close(params_node);
                    break;
                case "textDocument/completion":
                    handle_completion(id_node, params_node);
                    break;
                case "textDocument/hover":
                    handle_hover(id_node, params_node);
                    break;
                case "textDocument/documentSymbol":
                    handle_document_symbol(id_node, params_node);
                    break;
                case "gdiagram/renderSvg":
                    handle_render_svg(id_node, params_node);
                    break;
                case "gdiagram/exportFile":
                    handle_export_file(id_node, params_node);
                    break;
                case "gdiagram/getTemplates":
                    send_response(id_node, LspProtocol.build_templates_list());
                    break;
                default:
                    if (id_node != null) {
                        send_error(id_node, -32601, "Method not found: %s".printf(method));
                    }
                    // Unknown notifications are silently ignored per spec
                    break;
            }
        }

        // Methods the spec defines as requests: each one must carry an id and each
        // handler below answers it. Everything else is a notification.
        private static bool is_request_method(string method) {
            switch (method) {
                case "initialize":
                case "shutdown":
                case "textDocument/completion":
                case "textDocument/hover":
                case "textDocument/documentSymbol":
                case "gdiagram/renderSvg":
                case "gdiagram/exportFile":
                case "gdiagram/getTemplates":
                    return true;
                default:
                    return false;
            }
        }

        // $/cancelRequest: answer the named in-flight render/export with RequestCancelled
        // and stop its worker. Unknown ids are ignored (the request already finished).
        private void cancel_request(Json.Object? params) {
            if (params == null || !params.has_member("id")) return;
            var id = params.get_member("id");
            foreach (var job in renders.values) {
                if (job.has_id(id)) {
                    cancel_render(job.uri, "Request cancelled by the client");
                    return;
                }
            }
            foreach (var job in exports) {
                if (job.has_id(id)) {
                    exports.remove(job);
                    job.finish();
                    job.cancellable.cancel();
                    job.process.force_exit();
                    send_error(job.id, REQUEST_CANCELLED, "Request cancelled by the client");
                    return;
                }
            }
        }

        // params.textDocument.uri, or null
        private static string? text_document_uri(Json.Object? params) {
            return LspProtocol.string_member(LspProtocol.object_member(params, "textDocument"), "uri");
        }

        // ========================== Handler methods ==========================

        private void publish_diagnostics(string uri, LspDocumentState state) {
            send_notification(LspProtocol.build_diagnostics_notification(uri, state.diagnostics));
        }

        private void handle_did_open(Json.Node? params_node) {
            var td = LspProtocol.object_member(LspProtocol.as_object(params_node), "textDocument");
            string? uri = LspProtocol.string_member(td, "uri");
            string? text = LspProtocol.string_member(td, "text");
            if (uri == null || text == null) {
                invalid_params(null, "didOpen needs textDocument.uri and textDocument.text");
                return;
            }
            string language_id = LspProtocol.string_member(td, "languageId") ?? "";
            int version = (int) LspProtocol.int_member(td, "version", 0);

            var state = new LspDocumentState(uri, text, language_id, version, engine);
            state.reparse();
            documents.set(uri, state);
            publish_diagnostics(uri, state);
        }

        private void handle_did_change(Json.Node? params_node) {
            var params = LspProtocol.as_object(params_node);
            string? uri = text_document_uri(params);
            if (uri == null || !documents.has_key(uri)) return;
            int version = (int) LspProtocol.int_member(LspProtocol.object_member(params, "textDocument"), "version", 0);

            // Full sync: take the first content change
            var changes = LspProtocol.array_member(params, "contentChanges");
            if (changes == null || changes.get_length() == 0) return;
            string? new_text = LspProtocol.string_member(LspProtocol.as_object(changes.get_element(0)), "text");
            if (new_text == null) return;

            var state = documents.get(uri);
            state.content = new_text;
            state.version = version;
            state.reparse();
            publish_diagnostics(uri, state);
        }

        private void handle_did_close(Json.Node? params_node) {
            string? uri = text_document_uri(LspProtocol.as_object(params_node));
            if (uri == null) return;

            documents.unset(uri);
            cancel_render(uri, "Request cancelled: the document was closed");

            // Clear diagnostics
            var empty = new Gee.ArrayList<LspDiagnostic>();
            send_notification(LspProtocol.build_diagnostics_notification(uri, empty));
        }

        private void handle_completion(Json.Node? id, Json.Node? params_node) {
            string? uri = text_document_uri(LspProtocol.as_object(params_node));
            if (uri == null) {
                invalid_params(id, "completion needs textDocument.uri");
                return;
            }

            DiagramFormat format = DiagramFormat.UNKNOWN;
            DiagramType dtype = DiagramType.UNKNOWN;
            string? content = null;

            if (documents.has_key(uri)) {
                var state = documents.get(uri);
                format = state.format;
                dtype = state.diagram_type;
                content = state.content;
            }

            send_response(id, LspProtocol.build_completion_items(format, dtype, content));
        }

        private void handle_hover(Json.Node? id, Json.Node? params_node) {
            var params = LspProtocol.as_object(params_node);
            string? uri = text_document_uri(params);
            var pos = LspProtocol.object_member(params, "position");
            if (uri == null || pos == null) {
                invalid_params(id, "hover needs textDocument.uri and position");
                return;
            }
            int line = (int) LspProtocol.int_member(pos, "line", -1);
            int character = (int) LspProtocol.int_member(pos, "character", -1);
            if (line < 0 || character < 0) {
                invalid_params(id, "hover position needs line and character");
                return;
            }
            if (!documents.has_key(uri)) {
                send_response(id, null);
                return;
            }
            send_response(id, LspProtocol.build_hover(documents.get(uri), line, character));
        }

        private void handle_document_symbol(Json.Node? id, Json.Node? params_node) {
            string? uri = text_document_uri(LspProtocol.as_object(params_node));
            if (uri == null) {
                invalid_params(id, "documentSymbol needs textDocument.uri");
                return;
            }
            if (!documents.has_key(uri)) {
                send_response(id, new Json.Node(Json.NodeType.ARRAY).init_array(new Json.Array()));
                return;
            }
            send_response(id, LspProtocol.build_document_symbols(documents.get(uri)));
        }

        // ========================== Custom methods ==========================

        private LspDocumentState? render_target(Json.Node? id, Json.Object? params, string method) {
            string? uri = LspProtocol.string_member(params, "uri");
            if (uri == null) {
                invalid_params(id, "%s needs uri".printf(method));
                return null;
            }
            if (!documents.has_key(uri)) {
                send_error(id, INVALID_PARAMS, "Document not open: %s".printf(uri));
                return null;
            }
            var state = documents.get(uri);
            // Like PlantUML and the CLI: a diagram with an unresolved !include is an error
            if (state.include_error != null) {
                send_error(id, INTERNAL_ERROR, "Unresolved !include: %s".printf(state.include_error));
                return null;
            }
            return state;
        }

        // `output_path` null: render SVG to the worker's stdout
        private Subprocess? spawn_worker(Json.Node? id, string format, string base_path, string? output_path) {
            var flags = SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE;
            try {
                if (output_path == null) {
                    return new Subprocess(flags, worker_path, "--render-worker", format, base_path);
                }
                return new Subprocess(flags, worker_path, "--render-worker", format, base_path, output_path);
            } catch (Error e) {
                send_error(id, INTERNAL_ERROR, "Cannot start the renderer: %s".printf(e.message));
                return null;
            }
        }

        // Answers a running renderSvg of `uri` with RequestCancelled and stops its worker
        private void cancel_render(string uri, string reason) {
            if (!renders.has_key(uri)) return;
            var job = renders.get(uri);
            renders.unset(uri);
            job.finish();
            job.cancellable.cancel();
            job.process.force_exit();
            send_error(job.id, REQUEST_CANCELLED, reason);
        }

        // Kill a worker that has run far past any plausible render time, so its request
        // is answered (INTERNAL_ERROR, via the communicate callback) instead of lost.
        private void arm_worker_timeout(RenderJob job) {
            job.timeout_id = Timeout.add_seconds(WORKER_TIMEOUT_SECONDS, () => {
                job.timeout_id = 0;
                log_debug("Renderer timed out after %us; killing it".printf(WORKER_TIMEOUT_SECONDS));
                job.process.force_exit();
                return Source.REMOVE;
            });
        }

        // The worker's stderr as a usable string. GBytes of length 0 hands back a NULL
        // data pointer, and the bytes are not NUL-terminated either way — the old
        // unchecked `(string) bytes.get_data()` crashed the whole server (losing every
        // open document) whenever a worker died from a signal, e.g. the OOM killer.
        private static string worker_stderr_text(Bytes? stderr_bytes) {
            if (stderr_bytes == null) return "";
            size_t size = stderr_bytes.get_size();
            if (size == 0) return "";
            unowned uint8[]? raw = stderr_bytes.get_data();
            if (raw == null) return "";
            var sb = new StringBuilder.sized(raw.length + 1);
            sb.append_len((string) raw, raw.length);
            return sb.str.make_valid().strip();
        }

        private static string worker_failure(Subprocess process, Bytes? stderr_bytes, string fallback) {
            string message = worker_stderr_text(stderr_bytes);
            if (message.length > 0) {
                // Worker messages are "error: <text>" lines
                int nl = message.last_index_of("\n");
                if (nl >= 0) message = message.substring(nl + 1);
                if (message.has_prefix("error: ")) return message.substring(7);
            }
            // A signal-killed worker says nothing at all; name the signal so the cause
            // (SIGKILL from the OOM killer, the watchdog above) is visible in the client.
            if (process.get_if_signaled()) {
                return "%s (renderer killed by signal %d)".printf(fallback, process.get_term_sig());
            }
            return fallback;
        }

        private void handle_render_svg(Json.Node? id, Json.Node? params_node) {
            var params = LspProtocol.as_object(params_node);
            var state = render_target(id, params, "renderSvg");
            if (state == null) return;

            cancel_render(state.uri, "Request cancelled: a newer renderSvg for this document superseded it");

            var process = spawn_worker(id, "svg", state.file_path ?? "", null);
            if (process == null) return;
            var job = new RenderJob();
            job.id = id != null ? id.copy() : null;
            job.uri = state.uri;
            job.process = process;
            renders.set(state.uri, job);
            arm_worker_timeout(job);

            DiagramFormat format = state.format;
            DiagramType type = state.diagram_type;
            process.communicate_async.begin(new Bytes(state.content.data), job.cancellable, (obj, res) => {
                Bytes? out_bytes = null;
                Bytes? err_bytes = null;
                try {
                    process.communicate_async.end(res, out out_bytes, out err_bytes);
                } catch (Error e) {
                    if (job.cancellable.is_cancelled()) return; // already answered
                }
                if (job.cancellable.is_cancelled()) return;
                job.finish();
                if (renders.get(job.uri) == job) renders.unset(job.uri);

                if (!process.get_if_exited() || process.get_exit_status() != 0 ||
                    out_bytes == null || out_bytes.get_size() == 0) {
                    send_error(job.id, INTERNAL_ERROR, worker_failure(process, err_bytes, "Rendering failed"));
                    return;
                }
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("svg"); b.add_string_value(Base64.encode(out_bytes.get_data()));
                b.set_member_name("format"); b.add_string_value(LspProtocol.format_id(format));
                b.set_member_name("type"); b.add_string_value(LspProtocol.diagram_type_id(type));
                b.set_member_name("typeName"); b.add_string_value(LspProtocol.diagram_type_name(type));
                b.end_object();
                send_response(job.id, b.get_root());
            });
        }

        private void handle_export_file(Json.Node? id, Json.Node? params_node) {
            var params = LspProtocol.as_object(params_node);
            string? output_path = LspProtocol.string_member(params, "outputPath");
            if (output_path == null) {
                invalid_params(id, "exportFile needs outputPath");
                return;
            }
            // A non-string "format" (e.g. []) used to fall back to "svg" and silently
            // write the wrong file; only an absent format defaults.
            string export_format = "svg";
            if (params != null && params.has_member("format")) {
                string? requested = LspProtocol.string_member(params, "format");
                if (requested == null) {
                    invalid_params(id, "format must be a string (svg, png or pdf)");
                    return;
                }
                export_format = requested;
            }
            if (export_format != "svg" && export_format != "png" && export_format != "pdf") {
                invalid_params(id, "format must be svg, png or pdf");
                return;
            }
            var state = render_target(id, params, "exportFile");
            if (state == null) return;

            // Route through the engine's file-writing export pipeline (in the worker) so
            // png/pdf produce real files (not SVG bytes with the wrong suffix).
            var process = spawn_worker(id, export_format, state.file_path ?? "", output_path);
            if (process == null) return;
            var job = new RenderJob();
            job.id = id != null ? id.copy() : null;
            job.uri = state.uri;
            job.process = process;
            job.output_path = output_path;
            exports.add(job);
            arm_worker_timeout(job);

            process.communicate_async.begin(new Bytes(state.content.data), job.cancellable, (obj, res) => {
                Bytes? out_bytes = null;
                Bytes? err_bytes = null;
                try {
                    process.communicate_async.end(res, out out_bytes, out err_bytes);
                } catch (Error e) {
                    if (job.cancellable.is_cancelled()) return; // $/cancelRequest already answered
                }
                if (job.cancellable.is_cancelled()) return;
                job.finish();
                exports.remove(job);
                if (!process.get_if_exited() || process.get_exit_status() != 0) {
                    send_error(job.id, INTERNAL_ERROR, worker_failure(process, err_bytes, "Export failed"));
                    return;
                }
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("success"); b.add_boolean_value(true);
                b.set_member_name("path"); b.add_string_value(job.output_path);
                b.end_object();
                send_response(job.id, b.get_root());
            });
        }

        // ========================== Utilities ==========================

        private void log_debug(string message) {
            stderr.printf("[gdiagram-lsp] %s\n", message);
        }
    }

    /**
     * `gdiagram-lsp --render-worker svg|png|pdf <base path or ""> [output path]`: renders the
     * document read from stdin. svg writes the SVG to stdout; png/pdf/svg with an output
     * path write that file. Exit status 0 on success; otherwise an "error: ..." line on
     * stderr and exit 2 (render/export failed) or 3 (an !include could not be resolved,
     * after a partial export like the CLI's).
     */
    public class LspRenderWorker : Object {
        public static int run(string[] args) {
            if (args.length < 4) {
                stderr.printf("error: usage: --render-worker svg|png|pdf BASE [OUTPUT]\n");
                return 2;
            }
            string format = args[2];
            string? base_path = args[3].length > 0 ? args[3] : null;
            string? output = args.length > 4 ? args[4] : null;

            var input = FileStream.fdopen(0, "rb");
            var content = new ByteArray();
            uint8[] chunk = new uint8[65536];
            size_t n;
            while ((n = input.read(chunk)) > 0) {
                content.append(chunk[0:n]);
            }
            content.append({ 0 });
            string source = (string) content.data;

            var engine = new DiagramEngine("dot");
            bool ok;
            uint8[]? svg = null;
            if (output == null) {
                svg = engine.generate_svg(source, null, base_path);
                ok = svg != null && svg.length > 0;
            } else if (format == "png") {
                ok = engine.export_to_png(source, null, base_path, output);
            } else if (format == "pdf") {
                ok = engine.export_to_pdf(source, null, base_path, output);
            } else {
                ok = engine.export_to_svg(source, null, base_path, output);
            }

            if (engine.detect_format(source, null) != DiagramFormat.MERMAID) {
                foreach (var err in engine.preprocessor_errors) {
                    if (LspDocumentState.is_include_error(err.message)) {
                        stderr.printf("error: line %d: %s\n", err.line, err.message);
                        return 3;
                    }
                }
            }
            if (!ok) {
                stderr.printf("error: %s\n", output == null ? "Rendering failed" : "Export failed");
                return 2;
            }
            if (svg != null) {
                var out_fs = FileStream.fdopen(1, "wb");
                out_fs.write(svg);
                out_fs.flush();
            }
            return 0;
        }
    }
}
