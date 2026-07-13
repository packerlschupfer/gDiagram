namespace GDiagram {
    public class AIService : Object {
        private Soup.Session session;
        private string? api_key;
        // Where the currently loaded key came from: "env", "keyring",
        // "file", or "none". Used by the Preferences UI for status display.
        private string api_key_source = "none";
        private const string CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";

        // libsecret schema for the Anthropic API key stored in the GNOME Keyring.
        private const string SECRET_SCHEMA_NAME = "org.gnome.gDiagram";
        private const string SECRET_KEY_TYPE = "anthropic-api-key";
        private const string SECRET_LABEL = "gDiagram Anthropic API Key";

        public signal void generation_started();
        public signal void generation_completed(string plantuml_code);
        public signal void generation_failed(string error_message);

        public AIService() {
            session = new Soup.Session();
            session.timeout = 60;
            load_api_key();
        }

        private Secret.Schema build_schema() {
            return new Secret.Schema(SECRET_SCHEMA_NAME, Secret.SchemaFlags.NONE,
                                     "key-type", Secret.SchemaAttributeType.STRING);
        }

        private void load_api_key() {
            // 1. Environment variable takes precedence (unchanged behaviour).
            api_key = Environment.get_variable("ANTHROPIC_API_KEY");
            if (api_key != null && api_key.length > 0) {
                api_key_source = "env";
                return;
            }
            api_key = null;
            api_key_source = "none";

            // 2. GNOME Keyring (libsecret).
            try {
                var schema = build_schema();
                string? stored = Secret.password_lookup_sync(schema, null, "key-type", SECRET_KEY_TYPE);
                if (stored != null && stored.strip().length > 0) {
                    api_key = stored.strip();
                    api_key_source = "keyring";
                    return;
                }
            } catch (Error e) {
                warning("Could not read API key from keyring: %s", e.message);
            }

            // 3. Legacy plaintext files. If found, migrate into the keyring and
            //    delete the plaintext copies once the store succeeds.
            foreach (var key_file in legacy_key_files()) {
                try {
                    string contents;
                    if (FileUtils.get_contents(key_file, out contents)) {
                        var found = contents.strip();
                        if (found.length > 0) {
                            api_key = found;
                            if (store_in_keyring(found)) {
                                delete_legacy_files();
                                api_key_source = "keyring";
                            } else {
                                api_key_source = "file";
                            }
                            return;
                        }
                    }
                } catch (Error e) {
                    // Not present in this location; try the next.
                }
            }
        }

        private string[] legacy_key_files() {
            var config_dir = Environment.get_user_config_dir();
            return {
                Path.build_filename(config_dir, "gdiagram", "api_key.txt"),
                Path.build_filename(config_dir, "gplantuml", "api_key.txt")
            };
        }

        private void delete_legacy_files() {
            foreach (var f in legacy_key_files()) {
                if (FileUtils.test(f, FileTest.EXISTS)) {
                    FileUtils.unlink(f);
                }
            }
        }

        private bool store_in_keyring(string key) {
            try {
                var schema = build_schema();
                return Secret.password_store_sync(schema, Secret.COLLECTION_DEFAULT,
                                                  SECRET_LABEL, key, null,
                                                  "key-type", SECRET_KEY_TYPE);
            } catch (Error e) {
                warning("Could not store API key in keyring: %s", e.message);
                return false;
            }
        }

        public void save_api_key(string key) {
            api_key = key;

            // If the environment variable is set it always wins at load time,
            // so record that as the effective source even though we persist
            // the new key for future runs.
            string env = Environment.get_variable("ANTHROPIC_API_KEY");
            bool env_wins = (env != null && env.length > 0);

            // Prefer the keyring; if it succeeds, make sure no stale plaintext remains.
            if (store_in_keyring(key)) {
                delete_legacy_files();
                api_key_source = env_wins ? "env" : "keyring";
                return;
            }
            // Fall back to plaintext file below; remember that for the source.
            api_key_source = env_wins ? "env" : "file";

            // Keyring unavailable (e.g. no secret service): fall back to a
            // plaintext file with restrictive (0600) permissions.
            var config_dir = Environment.get_user_config_dir();
            var app_config = Path.build_filename(config_dir, "gdiagram");
            try {
                DirUtils.create_with_parents(app_config, 0700);
                var key_file = Path.build_filename(app_config, "api_key.txt");
                FileUtils.set_contents(key_file, key);
                // Set restrictive permissions
                FileUtils.chmod(key_file, 0600);
            } catch (Error e) {
                warning("Could not save API key: %s", e.message);
            }
        }

        public void clear_api_key() {
            api_key = null;
            try {
                var schema = build_schema();
                Secret.password_clear_sync(schema, null, "key-type", SECRET_KEY_TYPE);
            } catch (Error e) {
                warning("Could not clear API key from keyring: %s", e.message);
            }
            delete_legacy_files();
            // Re-derive the effective source: an env var (which we can't and
            // shouldn't clear) still provides a key after the stored copy is
            // removed.
            load_api_key();
        }

        public bool has_api_key() {
            return api_key != null && api_key.length > 0;
        }

        public string? get_api_key() {
            return api_key;
        }

        /**
         * Where the currently active key comes from: "env" (ANTHROPIC_API_KEY
         * environment variable), "keyring" (GNOME Keyring / libsecret),
         * "file" (legacy plaintext fallback), or "none" (no key configured).
         * Read-only; for status display in the Preferences dialog.
         */
        public string key_source() {
            return api_key_source;
        }

        /**
         * True when a key is persisted in the keyring or a plaintext file
         * (i.e. something a Clear action could remove). An env-var-only key
         * returns false, since it cannot be cleared from here.
         */
        public bool has_stored_key() {
            return api_key_source == "keyring" || api_key_source == "file";
        }

        public async void generate_diagram(string description, string diagram_type = "auto") {
            if (!has_api_key()) {
                generation_failed("No API key configured. Please add your Anthropic API key in Preferences.");
                return;
            }

            generation_started();

            string type_hint = "";
            if (diagram_type != "auto") {
                type_hint = " The diagram should be a %s diagram.".printf(diagram_type);
            }

            string prompt = """Generate PlantUML code for the following description. Only output the PlantUML code, starting with @startuml and ending with @enduml. Do not include any explanation or markdown formatting.

Description: %s%s""".printf(description, type_hint);

            var json_builder = new Json.Builder();
            json_builder.begin_object();
            json_builder.set_member_name("model");
            json_builder.add_string_value("claude-sonnet-4-6");
            json_builder.set_member_name("max_tokens");
            json_builder.add_int_value(4096);
            json_builder.set_member_name("messages");
            json_builder.begin_array();
            json_builder.begin_object();
            json_builder.set_member_name("role");
            json_builder.add_string_value("user");
            json_builder.set_member_name("content");
            json_builder.add_string_value(prompt);
            json_builder.end_object();
            json_builder.end_array();
            json_builder.end_object();

            var generator = new Json.Generator();
            generator.root = json_builder.get_root();
            string request_body = generator.to_data(null);

            var message = new Soup.Message("POST", CLAUDE_API_URL);
            message.request_headers.append("x-api-key", api_key);
            message.request_headers.append("anthropic-version", "2023-06-01");
            message.request_headers.append("Content-Type", "application/json");
            message.set_request_body_from_bytes("application/json",
                new Bytes.take(request_body.data));

            try {
                var response = yield session.send_and_read_async(message, Priority.DEFAULT, null);

                // Length-aware cast of the HTTP response body. `(string) bytes`
                // would call strlen and (a) overread past the buffer if the
                // body isn't NUL-terminated or (b) truncate at an embedded
                // NUL. Pass the real length explicitly.
                unowned uint8[] body = response.get_data();
                int body_len = (int) body.length;

                if (message.status_code != 200) {
                    string error_text;
                    if (body_len == 0) {
                        error_text = "";
                    } else {
                        unowned string raw = (string) body;
                        int safe = int.min(raw.length, body_len);
                        error_text = (raw.length == body_len) ? raw : raw.substring(0, safe);
                    }
                    generation_failed("API Error (%u): %s".printf(message.status_code, error_text));
                    return;
                }

                var parser = new Json.Parser();
                // Pass the length explicitly so load_from_data doesn't
                // strlen into garbage.
                parser.load_from_data((string) body, (ssize_t) body_len);

                var root = parser.get_root().get_object();
                var content = root.get_array_member("content");
                if (content.get_length() > 0) {
                    var first = content.get_object_element(0);
                    var text = first.get_string_member("text");

                    // Extract PlantUML code
                    string plantuml = extract_plantuml(text);
                    if (plantuml.length > 0) {
                        generation_completed(plantuml);
                    } else {
                        generation_failed("Could not extract PlantUML code from response.");
                    }
                } else {
                    generation_failed("Empty response from API.");
                }
            } catch (Error e) {
                generation_failed("Request failed: %s".printf(e.message));
            }
        }

        private string extract_plantuml(string text) {
            // Find @startuml ... @enduml block
            int start_idx = text.index_of("@startuml");
            int end_idx = text.index_of("@enduml");

            if (start_idx >= 0 && end_idx > start_idx) {
                return text.substring(start_idx, end_idx - start_idx + 7);
            }

            // If not found with exact markers, try to find code block
            if (text.contains("```")) {
                int code_start = text.index_of("```");
                int code_end = text.index_of("```", code_start + 3);
                if (code_end > code_start) {
                    string code = text.substring(code_start + 3, code_end - code_start - 3);
                    // Remove language identifier line if present (plantuml, puml, uml, or empty)
                    int nl = code.index_of("\n");
                    if (nl >= 0) {
                        string tag = code.substring(0, nl).strip().down();
                        if (tag == "plantuml" || tag == "puml" || tag == "uml" || tag == "") {
                            code = code.substring(nl + 1);
                        }
                    }
                    return code.strip();
                }
            }

            return text.strip();
        }
    }
}
