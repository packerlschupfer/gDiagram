namespace GDiagram {

    /**
     * LSP server for gDiagram. Communicates via JSON-RPC over stdin/stdout.
     * Supports PlantUML and Mermaid diagram editing with diagnostics,
     * completion, hover, document symbols, and custom rendering commands.
     */
    public class LspServer : Object {
        private Gee.HashMap<string, LspDocumentState> documents;
        private bool shutdown_requested = false;
        private bool running = true;

        // One shared engine for the whole server: owns every parser/renderer
        // instance and is handed to each open document so reparses reuse the
        // same parsers instead of allocating fresh ones per keystroke.
        private DiagramEngine engine;

        // Raw file streams for LSP I/O
        private FileStream input_fs;
        private FileStream output_fs;

        public LspServer() {
            documents = new Gee.HashMap<string, LspDocumentState>();
            engine = new DiagramEngine("dot");
        }

        /**
         * Main run loop. Reads JSON-RPC messages from stdin, dispatches, responds.
         * Returns exit code (0 on clean shutdown, 1 on error).
         */
        public int run() {
            input_fs = FileStream.fdopen(0, "rb");
            output_fs = FileStream.fdopen(1, "wb");

            log_debug("gdiagram-lsp started");

            while (running) {
                try {
                    string? json_body = read_message();
                    if (json_body == null) {
                        // EOF on stdin
                        log_debug("EOF on stdin, exiting");
                        break;
                    }

                    handle_message(json_body);
                } catch (Error e) {
                    log_debug("Error reading message: %s".printf(e.message));
                    // Continue reading -- don't crash on malformed input
                }
            }

            return shutdown_requested ? 0 : 1;
        }

        /**
         * Read a single LSP message (Content-Length header + JSON body).
         * Returns null on EOF.
         */
        private string? read_message() throws Error {
            // Read headers until blank line
            int content_length = -1;

            while (true) {
                string? line = read_line_from_stdin();
                if (line == null) return null; // EOF

                string trimmed = line.strip();

                if (trimmed.length == 0) {
                    // End of headers
                    break;
                }

                if (trimmed.has_prefix("Content-Length:")) {
                    string val = trimmed.substring("Content-Length:".length).strip();
                    content_length = int.parse(val);
                }
                // Ignore other headers (Content-Type, etc.)
            }

            if (content_length <= 0) {
                throw new IOError.INVALID_DATA("Missing or invalid Content-Length header");
            }

            // Read exactly content_length bytes
            uint8[] buffer = new uint8[content_length + 1]; // +1 for null terminator
            size_t total_read = 0;
            while (total_read < content_length) {
                int ch = input_fs.getc();
                if (ch == FileStream.EOF) {
                    throw new IOError.PARTIAL_INPUT("EOF during body read at byte %zu of %d".printf(
                        total_read, content_length));
                }
                buffer[total_read] = (uint8) ch;
                total_read++;
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

        /**
         * Send a JSON-RPC response for a given request id.
         */
        private void send_response(Json.Node? id, Json.Node? result) {
            // Build the response using Json.Node/Object directly to embed
            // the result node without double-serialization issues.
            var response = new Json.Object();
            response.set_string_member("jsonrpc", "2.0");

            if (id != null && id.get_node_type() == Json.NodeType.VALUE) {
                var vtype = id.get_value_type();
                if (vtype == typeof(int64)) {
                    response.set_int_member("id", id.get_int());
                } else {
                    response.set_string_member("id", id.get_string());
                }
            } else {
                response.set_null_member("id");
            }

            if (result != null) {
                response.set_member("result", result.copy());
            } else {
                response.set_null_member("result");
            }

            var root = new Json.Node(Json.NodeType.OBJECT);
            root.set_object(response);

            var gen = new Json.Generator();
            gen.root = root;
            string json = gen.to_data(null);
            send_message(json);
        }

        /**
         * Send a JSON-RPC error response.
         */
        private void send_error(Json.Node? id, int code, string message) {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("jsonrpc"); b.add_string_value("2.0");

            b.set_member_name("id");
            if (id != null && id.get_node_type() == Json.NodeType.VALUE) {
                var vtype = id.get_value_type();
                if (vtype == typeof(int64)) {
                    b.add_int_value(id.get_int());
                } else {
                    b.add_string_value(id.get_string());
                }
            } else {
                b.add_null_value();
            }

            b.set_member_name("error");
            b.begin_object();
            b.set_member_name("code"); b.add_int_value(code);
            b.set_member_name("message"); b.add_string_value(message);
            b.end_object();

            b.end_object();

            var gen = new Json.Generator();
            gen.root = b.get_root();
            send_message(gen.to_data(null));
        }

        /**
         * Send a JSON-RPC notification (no id).
         */
        private void send_notification(string json) {
            send_message(json);
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

            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                send_error(null, -32600, "Invalid Request: expected JSON object");
                return;
            }

            var obj = root.get_object();
            Json.Node? id_node = obj.has_member("id") ? obj.get_member("id") : null;
            string? method = obj.has_member("method") ? obj.get_string_member("method") : null;
            Json.Node? params_node = obj.has_member("params") ? obj.get_member("params") : null;

            if (method == null) {
                send_error(id_node, -32600, "Invalid Request: missing method");
                return;
            }

            log_debug("Received: %s".printf(method));

            // Dispatch
            switch (method) {
                case "initialize":
                    handle_initialize(id_node);
                    break;
                case "initialized":
                    // No-op notification
                    break;
                case "shutdown":
                    handle_shutdown(id_node);
                    break;
                case "exit":
                    handle_exit();
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
                    handle_get_templates(id_node);
                    break;
                default:
                    if (id_node != null) {
                        // Request with unknown method
                        send_error(id_node, -32601, "Method not found: %s".printf(method));
                    }
                    // Unknown notifications are silently ignored per spec
                    break;
            }
        }

        // ========================== Handler methods ==========================

        private void handle_initialize(Json.Node? id) {
            var result = LspProtocol.build_initialize_result();
            send_response(id, result);
        }

        private void handle_shutdown(Json.Node? id) {
            shutdown_requested = true;
            // Response with null result
            send_response(id, null);
        }

        private void handle_exit() {
            running = false;
        }

        private void handle_did_open(Json.Node? params_node) {
            if (params_node == null) return;
            var params = params_node.get_object();
            if (params == null || !params.has_member("textDocument")) return;

            var td = params.get_object_member("textDocument");
            string uri = td.get_string_member("uri");
            string text = td.get_string_member("text");
            string language_id = td.has_member("languageId") ? td.get_string_member("languageId") : "";
            int version = td.has_member("version") ? (int) td.get_int_member("version") : 0;

            var state = new LspDocumentState(uri, text, language_id, version, engine);
            state.reparse();
            documents.set(uri, state);

            // Publish diagnostics
            string diag_json = LspProtocol.build_diagnostics_notification(uri, state.diagnostics);
            send_notification(diag_json);
        }

        private void handle_did_change(Json.Node? params_node) {
            if (params_node == null) return;
            var params = params_node.get_object();
            if (params == null || !params.has_member("textDocument")) return;

            var td = params.get_object_member("textDocument");
            string uri = td.get_string_member("uri");
            int version = td.has_member("version") ? (int) td.get_int_member("version") : 0;

            if (!documents.has_key(uri)) return;

            // Full sync: take the first content change
            if (params.has_member("contentChanges")) {
                var changes = params.get_array_member("contentChanges");
                if (changes.get_length() > 0) {
                    var change = changes.get_object_element(0);
                    string new_text = change.get_string_member("text");

                    var state = documents.get(uri);
                    state.content = new_text;
                    state.version = version;
                    state.reparse();

                    // Publish diagnostics
                    string diag_json = LspProtocol.build_diagnostics_notification(uri, state.diagnostics);
                    send_notification(diag_json);
                }
            }
        }

        private void handle_did_close(Json.Node? params_node) {
            if (params_node == null) return;
            var params = params_node.get_object();
            if (params == null || !params.has_member("textDocument")) return;

            var td = params.get_object_member("textDocument");
            string uri = td.get_string_member("uri");

            documents.unset(uri);

            // Clear diagnostics
            var empty = new Gee.ArrayList<LspDiagnostic>();
            string diag_json = LspProtocol.build_diagnostics_notification(uri, empty);
            send_notification(diag_json);
        }

        private void handle_completion(Json.Node? id, Json.Node? params_node) {
            if (params_node == null) {
                send_response(id, null);
                return;
            }

            var params = params_node.get_object();
            var td = params.get_object_member("textDocument");
            string uri = td.get_string_member("uri");

            DiagramFormat format = DiagramFormat.UNKNOWN;
            DiagramType dtype = DiagramType.UNKNOWN;

            if (documents.has_key(uri)) {
                var state = documents.get(uri);
                format = state.format;
                dtype = state.diagram_type;
            }

            var items = LspProtocol.build_completion_items(format, dtype);
            send_response(id, items);
        }

        private void handle_hover(Json.Node? id, Json.Node? params_node) {
            if (params_node == null) {
                send_response(id, null);
                return;
            }

            var params = params_node.get_object();
            var td = params.get_object_member("textDocument");
            string uri = td.get_string_member("uri");

            if (!documents.has_key(uri)) {
                send_response(id, null);
                return;
            }

            var pos = params.get_object_member("position");
            int line = (int) pos.get_int_member("line");
            int character = (int) pos.get_int_member("character");

            var state = documents.get(uri);
            var hover = LspProtocol.build_hover(state, line, character);
            send_response(id, hover);
        }

        private void handle_document_symbol(Json.Node? id, Json.Node? params_node) {
            if (params_node == null) {
                send_response(id, null);
                return;
            }

            var params = params_node.get_object();
            var td = params.get_object_member("textDocument");
            string uri = td.get_string_member("uri");

            if (!documents.has_key(uri)) {
                var b = new Json.Builder();
                b.begin_array();
                b.end_array();
                send_response(id, b.get_root());
                return;
            }

            var state = documents.get(uri);
            var symbols = LspProtocol.build_document_symbols(state);
            send_response(id, symbols);
        }

        // ========================== Custom methods ==========================

        private void handle_render_svg(Json.Node? id, Json.Node? params_node) {
            if (params_node == null) {
                send_error(id, -32602, "Missing params");
                return;
            }

            var params = params_node.get_object();
            string uri = params.get_string_member("uri");

            if (!documents.has_key(uri)) {
                send_error(id, -32602, "Document not open: %s".printf(uri));
                return;
            }

            var state = documents.get(uri);
            uint8[]? svg_data = state.render_svg();

            if (svg_data == null) {
                send_error(id, -32603, "Rendering failed");
                return;
            }

            // Return base64-encoded SVG
            string base64 = GLib.Base64.encode(svg_data);

            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("svg"); b.add_string_value(base64);
            b.set_member_name("format"); b.add_string_value(state.format.to_string());
            b.set_member_name("type"); b.add_string_value(state.diagram_type.to_string());
            b.end_object();

            send_response(id, b.get_root());
        }

        private void handle_export_file(Json.Node? id, Json.Node? params_node) {
            if (params_node == null) {
                send_error(id, -32602, "Missing params");
                return;
            }

            var params = params_node.get_object();
            string uri = params.get_string_member("uri");
            string output_path = params.get_string_member("outputPath");
            string export_format = params.has_member("format") ? params.get_string_member("format") : "svg";

            if (!documents.has_key(uri)) {
                send_error(id, -32602, "Document not open: %s".printf(uri));
                return;
            }

            var state = documents.get(uri);

            // Route through the shared engine's file-writing export pipeline so
            // png/pdf produce real files (not SVG bytes with the wrong suffix).
            bool success;
            switch (export_format) {
                case "png":
                    success = engine.export_to_png(state.content, null, null, output_path);
                    break;
                case "pdf":
                    success = engine.export_to_pdf(state.content, null, null, output_path);
                    break;
                default:
                    success = engine.export_to_svg(state.content, null, null, output_path);
                    break;
            }

            if (!success) {
                send_error(id, -32603, "Export failed");
                return;
            }

            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("success"); b.add_boolean_value(success);
            b.set_member_name("path"); b.add_string_value(output_path);
            b.end_object();

            send_response(id, b.get_root());
        }

        private void handle_get_templates(Json.Node? id) {
            var templates = LspProtocol.build_templates_list();
            send_response(id, templates);
        }

        // ========================== Utilities ==========================

        private void log_debug(string message) {
            stderr.printf("[gdiagram-lsp] %s\n", message);
        }
    }
}
