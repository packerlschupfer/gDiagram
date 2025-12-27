namespace GDiagram {
    public class AIService : Object {
        private Soup.Session session;
        private string? api_key;
        private const string CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";

        public signal void generation_started();
        public signal void generation_completed(string plantuml_code);
        public signal void generation_failed(string error_message);

        public AIService() {
            session = new Soup.Session();
            session.timeout = 60;
            load_api_key();
        }

        private void load_api_key() {
            // Try to load from settings or environment
            api_key = Environment.get_variable("ANTHROPIC_API_KEY");

            // Also try from config file
            if (api_key == null || api_key.length == 0) {
                var config_dir = Environment.get_user_config_dir();
                var key_file = Path.build_filename(config_dir, "gplantuml", "api_key.txt");
                try {
                    string contents;
                    if (FileUtils.get_contents(key_file, out contents)) {
                        api_key = contents.strip();
                    }
                } catch (Error e) {
                    // No API key configured
                }
            }
        }

        public void save_api_key(string key) {
            api_key = key;
            var config_dir = Environment.get_user_config_dir();
            var app_config = Path.build_filename(config_dir, "gplantuml");

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

        public bool has_api_key() {
            return api_key != null && api_key.length > 0;
        }

        public string? get_api_key() {
            return api_key;
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
            json_builder.add_string_value("claude-sonnet-4-5-20250929");
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

                if (message.status_code != 200) {
                    var error_text = (string)response.get_data();
                    generation_failed("API Error (%u): %s".printf(message.status_code, error_text));
                    return;
                }

                var response_text = (string)response.get_data();
                var parser = new Json.Parser();
                parser.load_from_data(response_text);

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
                    // Remove language identifier if present
                    if (code.has_prefix("plantuml\n")) {
                        code = code.substring(9);
                    }
                    return code.strip();
                }
            }

            return text.strip();
        }
    }
}
