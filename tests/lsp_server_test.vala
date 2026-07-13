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
            string msg = "Content-Length: %d\r\n\r\n%s".printf(body.length, body);
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

    public static int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/lsp-server/full_session", LspServerTests.test_full_session);
        return Test.run();
    }
}
