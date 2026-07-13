/*
 * Integration test for the built `gdiagram-lsp` binary.
 *
 * Spawns the real server, speaks JSON-RPC over its stdin/stdout using
 * Content-Length framing, and verifies the full LSP lifecycle:
 *   - initialize            -> capabilities response
 *   - didOpen (broken doc)  -> publishDiagnostics with a non-empty list
 *   - didOpen (valid doc)   -> publishDiagnostics with an empty list
 *   - documentSymbol        -> non-empty symbols
 *   - completion            -> non-empty items
 *   - shutdown + exit       -> clean process exit (code 0)
 *
 * The binary path is provided by meson via the GDIAGRAM_LSP_BIN env var.
 * All reads are bounded by a timeout so a wedged server fails the test
 * instead of hanging forever.
 */
namespace GDiagram.Tests {

    // Bounded-timeout LSP transport over a child process's pipes.
    public class LspClient {
        private int in_fd;
        private int out_fd;
        private GLib.ByteArray pending = new GLib.ByteArray();

        public LspClient(int in_fd, int out_fd) {
            this.in_fd = in_fd;
            this.out_fd = out_fd;
        }

        // ── Writing ──────────────────────────────────────────────────
        public void send(string body) {
            send_raw("Content-Length: %d\r\n\r\n%s".printf(body.length, body));
        }

        // Exactly these bytes, framing and all: the tests below have to send headers
        // the server must reject and bodies shorter than their Content-Length.
        public void send_raw(string msg) {
            uint8[] data = msg.data;   // byte view, no NUL in .length
            int off = 0;
            while (off < data.length) {
                ssize_t n = Posix.write(in_fd, (uint8[]) data[off:data.length],
                                        data.length - off);
                if (n <= 0) break;
                off += (int) n;
            }
        }

        // ── Reading ──────────────────────────────────────────────────
        private bool fill(int timeout_ms) {
            Posix.pollfd[] pfds = new Posix.pollfd[1];
            pfds[0].fd = out_fd;
            pfds[0].events = Posix.POLLIN;
            int r = Posix.poll(pfds, timeout_ms);
            if (r <= 0) return false; // timeout or error
            uint8[] tmp = new uint8[8192];
            ssize_t n = Posix.read(out_fd, tmp, tmp.length);
            if (n <= 0) return false; // EOF
            pending.append(tmp[0:(int) n]);
            return true;
        }

        private bool fill_deadline(int64 deadline_us) {
            int64 now = get_monotonic_time();
            if (now >= deadline_us) return false;
            int ms = (int) ((deadline_us - now) / 1000);
            if (ms <= 0) ms = 1;
            return fill(ms);
        }

        private int find_header_end() {
            uint8[] d = pending.data;
            int len = (int) pending.len;
            for (int i = 0; i + 3 < len; i++) {
                if (d[i] == '\r' && d[i + 1] == '\n' &&
                    d[i + 2] == '\r' && d[i + 3] == '\n') {
                    return i;
                }
            }
            return -1;
        }

        private static string bytes_to_string(uint8[] data, int start, int len) {
            uint8[] b = new uint8[len + 1];
            for (int i = 0; i < len; i++) b[i] = data[start + i];
            b[len] = 0;
            return (string) b;
        }

        private int parse_content_length(int header_end) {
            string header = bytes_to_string(pending.data, 0, header_end);
            int idx = header.down().index_of("content-length:");
            if (idx < 0) return -1;
            string rest = header.substring(idx + "content-length:".length);
            int nl = rest.index_of("\n");
            if (nl >= 0) rest = rest.substring(0, nl);
            return int.parse(rest.strip());
        }

        // Read one framed JSON message, or null on timeout/EOF.
        public string? read_message(int timeout_ms) {
            int64 deadline = get_monotonic_time() + (int64) timeout_ms * 1000;
            while (true) {
                int hdr_end = find_header_end();
                if (hdr_end >= 0) {
                    int clen = parse_content_length(hdr_end);
                    if (clen < 0) return null;
                    int total = hdr_end + 4 + clen;
                    while ((int) pending.len < total) {
                        if (!fill_deadline(deadline)) return null;
                    }
                    string body = bytes_to_string(pending.data, hdr_end + 4, clen);
                    pending.remove_range(0, total);
                    return body;
                }
                if (!fill_deadline(deadline)) return null;
            }
        }

        private Json.Object? next_json(int timeout_ms) {
            string? m = read_message(timeout_ms);
            if (m == null) return null;
            var p = new Json.Parser();
            try {
                p.load_from_data(m);
            } catch (Error e) {
                return null;
            }
            var root = p.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return null;
            return root.get_object();
        }

        // Wait for a response with the given request id, skipping notifications.
        public Json.Object? await_response(int64 id, int timeout_ms) {
            int64 deadline = get_monotonic_time() + (int64) timeout_ms * 1000;
            while (true) {
                int ms = (int) ((deadline - get_monotonic_time()) / 1000);
                if (ms <= 0) return null;
                var o = next_json(ms);
                if (o == null) return null;
                if (o.has_member("id") && !o.get_member("id").is_null()) {
                    var idn = o.get_member("id");
                    if (idn.get_node_type() == Json.NodeType.VALUE &&
                        o.get_int_member("id") == id) {
                        return o;
                    }
                }
                // otherwise a notification: keep reading
            }
        }

        // Wait for a notification with the given method, skipping others.
        public Json.Object? await_notification(string method, int timeout_ms) {
            int64 deadline = get_monotonic_time() + (int64) timeout_ms * 1000;
            while (true) {
                int ms = (int) ((deadline - get_monotonic_time()) / 1000);
                if (ms <= 0) return null;
                var o = next_json(ms);
                if (o == null) return null;
                if (o.has_member("method") && !o.has_member("id") &&
                    o.get_string_member("method") == method) {
                    return o;
                }
            }
        }
    }

    public class LspServerTests {

        private const int TIMEOUT_MS = 10000;

        private static string valid_sequence() {
            return "@startuml\nparticipant Alice\nparticipant Bob\nAlice -> Bob: Hello\n@enduml\n";
        }

        private static string broken_doc() {
            // Not recognisable as any diagram type -> server emits a diagnostic.
            return "@startuml\nxyzzy nonsense qwerty zork\n@enduml\n";
        }

        private static string did_open(string uri, string text, string lang) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("method"); b.add_string_value("textDocument/didOpen");
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("textDocument");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.set_member_name("languageId"); b.add_string_value(lang);
            b.set_member_name("version"); b.add_int_value(1);
            b.set_member_name("text"); b.add_string_value(text);
            b.end_object();
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        private static string request(int64 id, string method, string uri) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("id"); b.add_int_value(id);
            b.set_member_name("method"); b.add_string_value(method);
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("textDocument");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.end_object();
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        private static string simple_request(int64 id, string method) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("id"); b.add_int_value(id);
            b.set_member_name("method"); b.add_string_value(method);
            b.end_object();
            return to_json(b);
        }

        private static string simple_notification(string method) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("method"); b.add_string_value(method);
            b.end_object();
            return to_json(b);
        }

        private static string to_json(Json.Builder b) {
            var gen = new Json.Generator();
            gen.root = b.get_root();
            return gen.to_data(null);
        }

        public static void test_full_session() {
            string? bin = Environment.get_variable("GDIAGRAM_LSP_BIN");
            assert(bin != null);
            assert(FileUtils.test(bin, FileTest.IS_EXECUTABLE));

            string[] argv = { bin };
            Pid pid = (Pid) 0;
            int stdin_fd = -1, stdout_fd = -1, stderr_fd = -1;

            try {
                Process.spawn_async_with_pipes(
                    null, argv, null,
                    SpawnFlags.DO_NOT_REAP_CHILD | SpawnFlags.STDERR_TO_DEV_NULL,
                    null,
                    out pid, out stdin_fd, out stdout_fd, out stderr_fd);
            } catch (SpawnError e) {
                error("Failed to spawn gdiagram-lsp: %s", e.message);
            }

            var client = new LspClient(stdin_fd, stdout_fd);

            // 1. initialize -> capabilities
            client.send(simple_request(1, "initialize"));
            var init_resp = client.await_response(1, TIMEOUT_MS);
            assert(init_resp != null);
            assert(init_resp.has_member("result"));
            var result = init_resp.get_object_member("result");
            var caps = result.get_object_member("capabilities");
            assert(caps.get_boolean_member("hoverProvider") == true);
            assert(caps.get_boolean_member("documentSymbolProvider") == true);
            assert(caps.has_member("completionProvider"));
            assert(result.get_object_member("serverInfo").get_string_member("name") == "gdiagram-lsp");

            // 2. initialized (notification, no response)
            client.send(simple_notification("initialized"));

            // 3. didOpen a broken doc -> publishDiagnostics with items
            string broken_uri = "file:///broken.puml";
            client.send(did_open(broken_uri, broken_doc(), "plantuml"));
            var diag_notif = client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS);
            assert(diag_notif != null);
            var dparams = diag_notif.get_object_member("params");
            assert(dparams.get_string_member("uri") == broken_uri);
            assert(dparams.get_array_member("diagnostics").get_length() > 0);

            // 4. didOpen a valid doc -> publishDiagnostics with an empty list
            string good_uri = "file:///good.puml";
            client.send(did_open(good_uri, valid_sequence(), "plantuml"));
            var good_notif = client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS);
            assert(good_notif != null);
            var gparams = good_notif.get_object_member("params");
            assert(gparams.get_string_member("uri") == good_uri);
            assert(gparams.get_array_member("diagnostics").get_length() == 0);

            // 5. documentSymbol on the valid doc -> non-empty symbols
            client.send(request(2, "textDocument/documentSymbol", good_uri));
            var sym_resp = client.await_response(2, TIMEOUT_MS);
            assert(sym_resp != null);
            var symbols = sym_resp.get_array_member("result");
            assert(symbols.get_length() > 0);

            // 6. completion -> non-empty items
            client.send(completion_request(3, good_uri));
            var comp_resp = client.await_response(3, TIMEOUT_MS);
            assert(comp_resp != null);
            var items = comp_resp.get_array_member("result");
            assert(items.get_length() > 0);

            // 6b. renderSvg on the valid doc -> non-empty SVG payload
            client.send(render_svg_request(5, good_uri));
            var svg_resp = client.await_response(5, TIMEOUT_MS);
            assert(svg_resp != null);
            assert(svg_resp.has_member("result"));
            var svg_result = svg_resp.get_object_member("result");
            string svg_b64 = svg_result.get_string_member("svg");
            assert(svg_b64.length > 0);
            uint8[] svg_bytes = GLib.Base64.decode(svg_b64);
            assert(svg_bytes.length > 0);

            // 6c. completion in a C4 document offers the C4 macros (the server passes the content)
            string c4_uri = "file:///c4.puml";
            client.send(did_open(c4_uri,
                "@startuml\n!include <C4/C4_Context>\nPerson(user, \"User\")\nSystem(sys, \"System\")\n" +
                "Rel(user, sys, \"Uses\")\n@enduml\n", "plantuml"));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);
            client.send(completion_request(6, c4_uri));
            var c4_resp = client.await_response(6, TIMEOUT_MS);
            assert(c4_resp != null);
            var c4_items = c4_resp.get_array_member("result");
            bool has_person = false;
            for (uint i = 0; i < c4_items.get_length(); i++) {
                if (c4_items.get_object_element(i).get_string_member("label") == "Person") has_person = true;
            }
            assert(has_person);

            // 7. shutdown -> response, then exit -> clean process exit
            client.send(simple_request(4, "shutdown"));
            var shut_resp = client.await_response(4, TIMEOUT_MS);
            assert(shut_resp != null);

            client.send(simple_notification("exit"));

            // Closing stdin guarantees EOF even if the exit notification is
            // somehow missed; the server exits cleanly in either case.
            Posix.close(stdin_fd);

            int status = 0;
            Posix.waitpid((Posix.pid_t) pid, out status, 0);
            Process.close_pid(pid);
            Posix.close(stdout_fd);

            // Decode wait status manually (Posix.WIFEXITED/WEXITSTATUS are not
            // bound in this vapi): a normal exit has the low 7 bits clear and
            // the exit code in bits 8-15.
            bool exited_normally = (status & 0x7f) == 0;
            int exit_code = (status >> 8) & 0xff;
            assert(exited_normally);
            assert(exit_code == 0);
        }

        // gdiagram/renderSvg expects the uri directly on params (not nested
        // under textDocument), matching the server's handle_render_svg.
        private static string render_svg_request(int64 id, string uri) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("id"); b.add_int_value(id);
            b.set_member_name("method"); b.add_string_value("gdiagram/renderSvg");
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        private static string completion_request(int64 id, string uri) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("id"); b.add_int_value(id);
            b.set_member_name("method"); b.add_string_value("textDocument/completion");
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("textDocument");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.end_object();
            b.set_member_name("position");
            b.begin_object();
            b.set_member_name("line"); b.add_int_value(3);
            b.set_member_name("character"); b.add_int_value(0);
            b.end_object();
            b.end_object();
            b.end_object();
            return to_json(b);
        }
    }

    // A relative !include in a file:// document resolves against the document's
    // directory for renderSvg and exportFile, not the server's working directory.
    public class LspIncludeTests {

        private const int TIMEOUT_MS = 10000;

        private static string to_json(Json.Builder b) {
            var gen = new Json.Generator();
            gen.root = b.get_root();
            return gen.to_data(null);
        }

        private static string did_open(string uri, string text) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("method"); b.add_string_value("textDocument/didOpen");
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("textDocument");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.set_member_name("languageId"); b.add_string_value("plantuml");
            b.set_member_name("version"); b.add_int_value(1);
            b.set_member_name("text"); b.add_string_value(text);
            b.end_object();
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        private static string command(int64 id, string method, string uri, string? output_path) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("id"); b.add_int_value(id);
            b.set_member_name("method"); b.add_string_value(method);
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            if (output_path != null) {
                b.set_member_name("outputPath"); b.add_string_value(output_path);
                b.set_member_name("format"); b.add_string_value("svg");
            }
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        public static void test_include_base_path() {
            string? bin = Environment.get_variable("GDIAGRAM_LSP_BIN");
            assert(bin != null);

            string root;
            try {
                root = DirUtils.make_tmp("gdiagram-lsp-inc-XXXXXX");
            } catch (FileError e) {
                error("mkdtemp: %s", e.message);
            }
            string doc_dir = Path.build_filename(root, "My Diagrams");
            DirUtils.create_with_parents(doc_dir, 0755);
            string doc_path = Path.build_filename(doc_dir, "plan.puml");
            string src = "@startgantt\n!include srv_parts.iuml\n[MainTask] requires 1 days\n@endgantt\n";
            string uri;
            try {
                FileUtils.set_contents(Path.build_filename(doc_dir, "srv_parts.iuml"),
                                       "[IncludedTask] requires 2 days\n");
                FileUtils.set_contents(doc_path, src);
                uri = Filename.to_uri(doc_path, null);
            } catch (Error e) {
                error("setup: %s", e.message);
            }

            // The server runs in / so the working directory cannot supply the include
            string[] argv = { bin };
            Pid pid = (Pid) 0;
            int stdin_fd = -1, stdout_fd = -1, stderr_fd = -1;
            try {
                Process.spawn_async_with_pipes(
                    "/", argv, null,
                    SpawnFlags.DO_NOT_REAP_CHILD | SpawnFlags.STDERR_TO_DEV_NULL,
                    null,
                    out pid, out stdin_fd, out stdout_fd, out stderr_fd);
            } catch (SpawnError e) {
                error("Failed to spawn gdiagram-lsp: %s", e.message);
            }
            var client = new LspClient(stdin_fd, stdout_fd);

            client.send(did_open(uri, src));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

            client.send(command(1, "gdiagram/renderSvg", uri, null));
            var svg_resp = client.await_response(1, TIMEOUT_MS);
            assert(svg_resp != null);
            assert(svg_resp.has_member("result"));
            uint8[] svg_bytes = GLib.Base64.decode(
                svg_resp.get_object_member("result").get_string_member("svg"));
            var sb = new StringBuilder();
            sb.append_len((string) svg_bytes, svg_bytes.length);
            assert(sb.str.contains("IncludedTask"));

            string out_path = Path.build_filename(root, "out.svg");
            client.send(command(2, "gdiagram/exportFile", uri, out_path));
            var exp_resp = client.await_response(2, TIMEOUT_MS);
            assert(exp_resp != null);
            assert(exp_resp.has_member("result"));
            string exported;
            try {
                FileUtils.get_contents(out_path, out exported);
            } catch (FileError e) {
                error("read export: %s", e.message);
            }
            assert(exported.contains("IncludedTask"));

            Posix.close(stdin_fd);
            int status = 0;
            Posix.waitpid((Posix.pid_t) pid, out status, 0);
            Process.close_pid(pid);
            Posix.close(stdout_fd);
        }
    }

    // Errors reach the client, malformed params are answered quietly, and a slow render
    // neither blocks diagnostics nor outlives a newer render request.
    public class LspRobustnessTests {

        private const int TIMEOUT_MS = 60000;

        private static string to_json(Json.Builder b) {
            var gen = new Json.Generator();
            gen.root = b.get_root();
            return gen.to_data(null);
        }

        private static string did_open(string uri, string text) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("method"); b.add_string_value("textDocument/didOpen");
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("textDocument");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            b.set_member_name("languageId"); b.add_string_value("plantuml");
            b.set_member_name("version"); b.add_int_value(1);
            b.set_member_name("text"); b.add_string_value(text);
            b.end_object();
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        private static string command(int64 id, string method, string uri, string? output_path = null) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");
            b.set_member_name("id"); b.add_int_value(id);
            b.set_member_name("method"); b.add_string_value(method);
            b.set_member_name("params");
            b.begin_object();
            b.set_member_name("uri"); b.add_string_value(uri);
            if (output_path != null) {
                b.set_member_name("outputPath"); b.add_string_value(output_path);
                b.set_member_name("format"); b.add_string_value("svg");
            }
            b.end_object();
            b.end_object();
            return to_json(b);
        }

        private static LspClient spawn(out Pid pid, out int stdin_fd, out int stdout_fd) {
            string? bin = Environment.get_variable("GDIAGRAM_LSP_BIN");
            assert(bin != null);
            string[] argv = { bin };
            // A Json-CRITICAL (or any critical) kills the server, so quiet validation is checked
            string[] envp = Environ.set_variable(Environ.get(), "G_DEBUG", "fatal-criticals", true);
            int stderr_fd;
            pid = (Pid) 0;
            stdin_fd = -1;
            stdout_fd = -1;
            try {
                Process.spawn_async_with_pipes(null, argv, envp,
                    SpawnFlags.DO_NOT_REAP_CHILD | SpawnFlags.STDERR_TO_DEV_NULL, null,
                    out pid, out stdin_fd, out stdout_fd, out stderr_fd);
            } catch (SpawnError e) {
                error("Failed to spawn gdiagram-lsp: %s", e.message);
            }
            return new LspClient(stdin_fd, stdout_fd);
        }

        private static void stop(LspClient client, Pid pid, int stdin_fd, int stdout_fd) {
            Posix.close(stdin_fd);
            int status = 0;
            Posix.waitpid((Posix.pid_t) pid, out status, 0);
            Process.close_pid(pid);
            Posix.close(stdout_fd);
        }

        private static Json.Object? next(LspClient client, int timeout_ms) {
            string? m = client.read_message(timeout_ms);
            if (m == null) return null;
            var p = new Json.Parser();
            try {
                p.load_from_data(m);
            } catch (Error e) {
                return null;
            }
            return p.get_root().get_object();
        }

        private static int64 error_code(Json.Object? response) {
            if (response == null || !response.has_member("error")) return 0;
            return response.get_object_member("error").get_int_member("code");
        }

        private static string error_message(Json.Object response) {
            return response.get_object_member("error").get_string_member("message");
        }

        public static void test_malformed_params() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/hover\",\"params\":[]}");
            assert(error_code(client.await_response(1, TIMEOUT_MS)) == -32602);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":5}}");
            assert(error_code(client.await_response(2, TIMEOUT_MS)) == -32602);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"gdiagram/renderSvg\",\"params\":\"x\"}");
            assert(error_code(client.await_response(3, TIMEOUT_MS)) == -32602);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"textDocument/hover\"," +
                        "\"params\":{\"textDocument\":{\"uri\":\"file:///x.puml\"},\"position\":{\"line\":\"a\"}}}");
            assert(error_code(client.await_response(4, TIMEOUT_MS)) == -32602);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":7}");
            assert(error_code(client.await_response(5, TIMEOUT_MS)) == -32600);
            // Malformed notifications are ignored, and the server is still alive
            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":[]}}");
            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"contentChanges\":3}}");
            client.send("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"initialize\"}");
            var init = client.await_response(6, TIMEOUT_MS);
            assert(init != null && init.has_member("result"));
            stop(client, pid, in_fd, out_fd);
        }

        public static void test_include_errors_reach_client() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            string uri = "file:///tmp/gdiagram-lsp-missing-dir/doc.puml";
            client.send(did_open(uri, "@startuml\n!include does_not_exist.iuml\nclass A\n@enduml\n"));
            var diag = client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS);
            assert(diag != null);
            var list = diag.get_object_member("params").get_array_member("diagnostics");
            assert(list.get_length() > 0);
            var first = list.get_object_element(0);
            assert(first.get_int_member("severity") == 1);
            assert(first.get_object_member("range").get_object_member("start").get_int_member("line") == 1);

            client.send(command(1, "gdiagram/renderSvg", uri));
            var render = client.await_response(1, TIMEOUT_MS);
            assert(error_code(render) == -32603);
            assert(error_message(render).contains("Unresolved !include"));
            client.send(command(2, "gdiagram/exportFile", uri, "/tmp/gdiagram-lsp-missing-dir-out.svg"));
            assert(error_code(client.await_response(2, TIMEOUT_MS)) == -32603);

            // renderSvg names the type and format readably
            string ok_uri = "file:///ok.puml";
            client.send(did_open(ok_uri, "@startuml\nclass A\nclass B\nA --> B\n@enduml\n"));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);
            client.send(command(3, "gdiagram/renderSvg", ok_uri));
            var ok = client.await_response(3, TIMEOUT_MS);
            assert(ok != null && ok.has_member("result"));
            var result = ok.get_object_member("result");
            assert(result.get_string_member("format") == "plantuml");
            assert(result.get_string_member("type") == "class");
            assert(result.get_string_member("typeName") == "Class Diagram");
            stop(client, pid, in_fd, out_fd);
        }

        private static string big_class_diagram(int count) {
            var sb = new StringBuilder("@startuml\n");
            for (int i = 0; i < count; i++) {
                sb.append("class C%d {\n  +field%d : int\n  +method%d() : void\n}\n".printf(i, i, i));
                if (i > 0) sb.append("C%d --> C%d : uses\n".printf(i - 1, i));
                if (i > 2) sb.append("C%d ..> C%d\n".printf(i, i / 3));
            }
            sb.append("@enduml\n");
            return sb.str;
        }

        public static void test_render_does_not_block_diagnostics() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            string big = "file:///big.puml";
            client.send(did_open(big, big_class_diagram(90)));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

            client.send(command(10, "gdiagram/renderSvg", big));
            client.send(command(11, "gdiagram/renderSvg", big));
            client.send(did_open("file:///small.puml", "@startuml\nclass Small\n@enduml\n"));

            // In arrival order: 10 is cancelled by 11, the small document's diagnostics come
            // while 11 still renders, then 11's SVG
            string[] order = {};
            int64 start = get_monotonic_time();
            int64 diag_at = 0;
            while (true) {
                var msg = next(client, TIMEOUT_MS);
                if (msg == null) {
                    stderr.printf("no message after %lld ms; so far: %s\n", (get_monotonic_time() - start) / 1000,
                                  string.joinv(", ", order));
                    assert_not_reached();
                }
                if (msg.has_member("method")) {
                    if (msg.get_string_member("method") == "textDocument/publishDiagnostics") {
                        order += "diagnostics";
                        diag_at = get_monotonic_time();
                    }
                    continue;
                }
                int64 id = msg.get_int_member("id");
                if (id == 10) {
                    assert(error_code(msg) == -32800);
                    order += "cancelled 10";
                } else if (id == 11) {
                    assert(msg.has_member("result"));
                    order += "svg 11";
                    break;
                }
            }
            int64 total_ms = (get_monotonic_time() - start) / 1000;
            stderr.printf("order: %s; diagnostics after %lld ms, render after %lld ms\n",
                          string.joinv(", ", order), (diag_at - start) / 1000, total_ms);
            assert(order.length == 3);
            assert(order[0] == "cancelled 10");
            assert(order[1] == "diagnostics");
            assert(order[2] == "svg 11");
            stop(client, pid, in_fd, out_fd);
        }

        // ── Finding the render worker so the test can kill it ────────

        // Parent pid from /proc/PID/stat. The comm field can hold spaces and
        // parentheses, so the fields are read after its closing ")".
        private static int proc_ppid(int pid) {
            string stat;
            try {
                FileUtils.get_contents("/proc/%d/stat".printf(pid), out stat);
            } catch (FileError e) {
                return -1;
            }
            int close = stat.last_index_of_char(')');
            if (close < 0 || close + 2 >= stat.length) return -1;
            string[] fields = stat.substring(close + 2).split(" ");
            return fields.length >= 2 ? int.parse(fields[1]) : -1;   // state, ppid, ...
        }

        // The server's only children are render workers; wait for one to appear.
        private static int await_render_worker(Pid parent, int timeout_ms) {
            int64 deadline = get_monotonic_time() + (int64) timeout_ms * 1000;
            while (get_monotonic_time() < deadline) {
                try {
                    var dir = Dir.open("/proc", 0);
                    string? name;
                    while ((name = dir.read_name()) != null) {
                        int pid = int.parse(name);
                        if (pid > 0 && proc_ppid(pid) == (int) parent) return pid;
                    }
                } catch (FileError e) {
                }
                Thread.usleep(10000);
            }
            return -1;
        }

        // A worker killed by a signal (the OOM killer on a big diagram) leaves an
        // EMPTY stderr, and an empty GBytes hands back a NULL data pointer. Casting
        // it straight to a string segfaulted the server, taking every open document
        // with it. The request must be answered and the server must stay up.
        public static void test_worker_killed_by_signal() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            string uri = "file:///killed.puml";
            client.send(did_open(uri, big_class_diagram(200)));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

            client.send(command(20, "gdiagram/renderSvg", uri));
            int worker = await_render_worker(pid, 15000);
            stderr.printf("render worker pid %d\n", worker);
            assert(worker > 0);
            // Let the server finish writing the document into the worker's stdin, so
            // the kill leaves empty output rather than a write error on our side
            Thread.usleep(400000);
            assert(Posix.kill((Posix.pid_t) worker, Posix.Signal.KILL) == 0);

            var resp = client.await_response(20, TIMEOUT_MS);
            assert(resp != null);
            assert(error_code(resp) == -32603);
            assert(error_message(resp).has_prefix("Rendering failed"));

            // Still alive, and the documents it held are still open
            string small = "file:///still-alive.puml";
            client.send(did_open(small, "@startuml\nclass A\nclass B\nA --> B\n@enduml\n"));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);
            client.send(command(21, "gdiagram/renderSvg", small));
            var ok = client.await_response(21, TIMEOUT_MS);
            assert(ok != null && ok.has_member("result"));
            stop(client, pid, in_fd, out_fd);
        }

        // JSON-RPC forbids replying to a notification. The custom commands used to
        // answer one with "id": null, which is not a valid response at all.
        public static void test_custom_commands_as_notifications() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            string uri = "file:///notified.puml";
            client.send(did_open(uri, "@startuml\nclass A\nclass B\nA --> B\n@enduml\n"));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

            string export_path = "/tmp/gdiagram-lsp-notification-export.svg";
            FileUtils.unlink(export_path);

            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"gdiagram/renderSvg\",\"params\":{\"uri\":\"" +
                        uri + "\"}}");
            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"gdiagram/exportFile\",\"params\":{\"uri\":\"" +
                        uri + "\",\"outputPath\":\"" + export_path + "\",\"format\":\"svg\"}}");
            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"gdiagram/getTemplates\"}");

            // The next message carrying an id must be this request's answer — an
            // "id": null response for any of the notifications above would come first
            client.send("{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"initialize\"}");
            while (true) {
                var msg = next(client, TIMEOUT_MS);
                assert(msg != null);
                if (!msg.has_member("id")) continue;    // a server notification
                assert(!msg.get_member("id").is_null());
                assert(msg.get_int_member("id") == 30);
                break;
            }
            // The dropped exportFile wrote nothing
            assert(!FileUtils.test(export_path, FileTest.EXISTS));

            // A string id is a valid JSON-RPC id and must come back as the same string
            client.send("{\"jsonrpc\":\"2.0\",\"id\":\"req-a\",\"method\":\"gdiagram/getTemplates\"}");
            while (true) {
                var msg = next(client, TIMEOUT_MS);
                assert(msg != null);
                if (!msg.has_member("id")) continue;
                assert(!msg.get_member("id").is_null());
                assert(msg.get_string_member("id") == "req-a");
                break;
            }
            stop(client, pid, in_fd, out_fd);
        }

        /**
         * A render worker must not outlive the server.
         *
         * g_subprocess_force_exit() only wakes GLib's worker thread, which then issues
         * the kill(); the server's _exit() stopped every thread first, so the signal was
         * usually never delivered (about 3 runs in 5). The worker ran on at 100% CPU --
         * forever, when its layout was wedged, because the watchdog died with its parent.
         */
        public static void test_worker_dies_with_the_server() {
            for (int attempt = 1; attempt <= 3; attempt++) {
                Pid pid; int in_fd; int out_fd;
                var client = spawn(out pid, out in_fd, out out_fd);
                string uri = "file:///orphan.puml";
                client.send(did_open(uri, big_class_diagram(200)));
                assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

                client.send(command(50, "gdiagram/renderSvg", uri));
                int worker = await_render_worker(pid, 15000);
                assert(worker > 0);
                // Let the server finish writing the document into the worker's stdin, so
                // the worker is really laying the diagram out when the server goes away
                Thread.usleep(400000);

                // stdin stays open: `exit` alone ends the process
                client.send("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}");
                int status = 0;
                Posix.waitpid((Posix.pid_t) pid, out status, 0);
                Process.close_pid(pid);
                Posix.close(in_fd);
                Posix.close(out_fd);

                // The server reaps the worker before exiting, so its pid is released too
                if (FileUtils.test("/proc/%d".printf(worker), FileTest.EXISTS)) {
                    Posix.kill((Posix.pid_t) worker, Posix.Signal.KILL);
                    int reaped = 0;
                    Posix.waitpid((Posix.pid_t) worker, out reaped, 0);
                    printerr("\nFAILED: render worker %d outlived the server (attempt %d/3)\n",
                             worker, attempt);
                    assert_not_reached();
                }
                stderr.printf("attempt %d: worker %d went with the server\n", attempt, worker);
            }
        }

        /**
         * One bad Content-Length must not take the server down or wedge its reader.
         *
         * The header went through an unvalidated int.parse() straight into a
         * `content_length + 1` allocation: "Content-Length: 2147483647" overflowed
         * negative and GLib aborted the process on the resulting 18-exabyte request
         * (GLib-ERROR gmem.c: failed to allocate ...), losing every open document.
         * "Content-Length: 999999999" instead parked the reader in getc() for good.
         */
        public static void test_bad_content_length_is_rejected() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            string uri = "file:///framing.puml";
            client.send(did_open(uri, "@startuml\nclass A\nclass B\nA --> B\n@enduml\n"));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

            string[] bad = { "2147483647", "999999999", "99999999999999999999",
                             "abc", "-5", "0", "12 34" };
            int64 id = 60;
            foreach (string length in bad) {
                string body = "{\"jsonrpc\":\"2.0\",\"method\":\"gdiagram/getTemplates\"}";
                client.send_raw("Content-Length: %s\r\n\r\n%s".printf(length, body));

                // The next well-formed request still has to be answered, from a server
                // that is still holding the document it had open
                client.send(command(id, "gdiagram/renderSvg", uri));
                var resp = client.await_response(id, TIMEOUT_MS);
                if (resp == null || !resp.has_member("result")) {
                    printerr("\nFAILED: no answer after `Content-Length: %s`\n", length);
                    assert_not_reached();
                }
                id++;
            }
            stop(client, pid, in_fd, out_fd);
        }

        /**
         * A body shorter than its Content-Length must not desync the reader for good.
         *
         * The reader sat in getc() waiting for bytes the client had never promised, so
         * every request sent after the short frame went unanswered while the process
         * happily stayed alive. Framing now ends the body where the next header starts.
         */
        public static void test_truncated_message_resynchronises() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"initialize\"}");
            assert(client.await_response(70, TIMEOUT_MS) != null);

            // A complete request under a Content-Length far larger than its body
            string truncated = "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"gdiagram/getTemplates\"}";
            client.send_raw("Content-Length: 500000\r\n\r\n%s".printf(truncated));

            // Ten well-formed requests behind it, all of which must be answered
            for (int64 i = 72; i < 82; i++) {
                client.send("{\"jsonrpc\":\"2.0\",\"id\":%lld,\"method\":\"gdiagram/getTemplates\"}"
                            .printf(i));
            }
            bool[] seen = new bool[10];
            int answered = 0;
            int64 deadline = get_monotonic_time() + (int64) TIMEOUT_MS * 1000;
            while (answered < 10 && get_monotonic_time() < deadline) {
                var msg = next(client, 3000);
                if (msg == null) break;
                if (!msg.has_member("id") || msg.get_member("id").is_null()) continue;
                int64 got = msg.get_int_member("id");
                if (got >= 72 && got < 82 && !seen[got - 72]) {
                    seen[got - 72] = true;
                    answered++;
                }
            }
            if (answered < 10) {
                printerr("\nFAILED: only %d of 10 requests after a truncated frame were answered\n",
                         answered);
                assert_not_reached();
            }
            stop(client, pid, in_fd, out_fd);
        }

        // A non-string "format" fell through to the "svg" default and silently wrote
        // the wrong file; $/cancelRequest was not handled at all.
        public static void test_format_validation_and_cancel() {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            string uri = "file:///cancel.puml";
            client.send(did_open(uri, big_class_diagram(200)));
            assert(client.await_notification("textDocument/publishDiagnostics", TIMEOUT_MS) != null);

            FileUtils.unlink("/tmp/gdiagram-lsp-badformat.out");
            client.send("{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"gdiagram/exportFile\",\"params\":" +
                        "{\"uri\":\"" + uri + "\",\"outputPath\":\"/tmp/gdiagram-lsp-badformat.out\"," +
                        "\"format\":[]}}");
            assert(error_code(client.await_response(40, TIMEOUT_MS)) == -32602);
            assert(!FileUtils.test("/tmp/gdiagram-lsp-badformat.out", FileTest.EXISTS));

            client.send(command(41, "gdiagram/renderSvg", uri));
            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"$/cancelRequest\",\"params\":{\"id\":41}}");
            assert(error_code(client.await_response(41, TIMEOUT_MS)) == -32800);
            stop(client, pid, in_fd, out_fd);
        }
    }

    // The `exit` notification ends the process by itself, with the spec's exit code.
    // It used to return from main() and hang forever in exit()'s stdio flush, because
    // the reader thread sits in getc() holding stdin's lock -- so the server only ever
    // died on stdin EOF and a client waiting on the child hung with it.
    public class LspExitTests {

        private const int TIMEOUT_MS = 10000;

        private static LspClient spawn(out Pid pid, out int stdin_fd, out int stdout_fd) {
            string? bin = Environment.get_variable("GDIAGRAM_LSP_BIN");
            assert(bin != null);
            string[] argv = { bin };
            int stderr_fd;
            pid = (Pid) 0;
            stdin_fd = -1;
            stdout_fd = -1;
            try {
                Process.spawn_async_with_pipes(null, argv, null,
                    SpawnFlags.DO_NOT_REAP_CHILD | SpawnFlags.STDERR_TO_DEV_NULL, null,
                    out pid, out stdin_fd, out stdout_fd, out stderr_fd);
            } catch (SpawnError e) {
                error("Failed to spawn gdiagram-lsp: %s", e.message);
            }
            return new LspClient(stdin_fd, stdout_fd);
        }

        // Wait status, or -1 if the process is still running after `timeout_ms`.
        private static int wait_for_exit(Pid pid, int timeout_ms) {
            int64 deadline = get_monotonic_time() + (int64) timeout_ms * 1000;
            while (get_monotonic_time() < deadline) {
                int status = 0;
                Posix.pid_t r = Posix.waitpid((Posix.pid_t) pid, out status, Posix.WNOHANG);
                if (r == (Posix.pid_t) pid) {
                    Process.close_pid(pid);
                    return status;
                }
                Thread.usleep(20000);
            }
            return -1;
        }

        // stdin deliberately stays OPEN: `exit` alone has to end the process.
        private static int exit_code_after(bool send_shutdown) {
            Pid pid; int in_fd; int out_fd;
            var client = spawn(out pid, out in_fd, out out_fd);
            client.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}");
            assert(client.await_response(1, TIMEOUT_MS) != null);
            if (send_shutdown) {
                client.send("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}");
                assert(client.await_response(2, TIMEOUT_MS) != null);
            }
            client.send("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}");

            int status = wait_for_exit(pid, TIMEOUT_MS);
            if (status < 0) {
                Posix.kill((Posix.pid_t) pid, Posix.Signal.KILL);
                int reaped = 0;
                Posix.waitpid((Posix.pid_t) pid, out reaped, 0);
                Process.close_pid(pid);
                Posix.close(in_fd);
                Posix.close(out_fd);
                return -1;   // never exited on its own
            }
            Posix.close(in_fd);
            Posix.close(out_fd);
            assert((status & 0x7f) == 0);   // a normal exit, not a signal
            return (status >> 8) & 0xff;
        }

        public static void test_exit_after_shutdown() {
            assert(exit_code_after(true) == 0);
        }

        public static void test_exit_without_shutdown() {
            assert(exit_code_after(false) == 1);
        }
    }

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/lsp-server/full_session", LspServerTests.test_full_session);
        Test.add_func("/lsp-server/include_base_path", LspIncludeTests.test_include_base_path);
        Test.add_func("/lsp-server/malformed_params", LspRobustnessTests.test_malformed_params);
        Test.add_func("/lsp-server/include_errors", LspRobustnessTests.test_include_errors_reach_client);
        Test.add_func("/lsp-server/render_off_main_loop", LspRobustnessTests.test_render_does_not_block_diagnostics);
        Test.add_func("/lsp-server/worker_killed_by_signal", LspRobustnessTests.test_worker_killed_by_signal);
        Test.add_func("/lsp-server/commands_as_notifications",
                      LspRobustnessTests.test_custom_commands_as_notifications);
        Test.add_func("/lsp-server/format_validation_and_cancel",
                      LspRobustnessTests.test_format_validation_and_cancel);
        Test.add_func("/lsp-server/worker_dies_with_server",
                      LspRobustnessTests.test_worker_dies_with_the_server);
        Test.add_func("/lsp-server/bad_content_length",
                      LspRobustnessTests.test_bad_content_length_is_rejected);
        Test.add_func("/lsp-server/truncated_message_resync",
                      LspRobustnessTests.test_truncated_message_resynchronises);
        Test.add_func("/lsp-server/exit_after_shutdown", LspExitTests.test_exit_after_shutdown);
        Test.add_func("/lsp-server/exit_without_shutdown", LspExitTests.test_exit_without_shutdown);
        return Test.run();
    }
}
