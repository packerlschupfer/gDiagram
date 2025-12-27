namespace GPlantUML {
    public class AIAssistantDialog : Adw.Dialog {
        private Gtk.TextView description_view;
        private Gtk.DropDown type_dropdown;
        private Gtk.Button generate_btn;
        private Gtk.Spinner spinner;
        private Gtk.Label status_label;
        private GtkSource.View result_view;
        private GtkSource.Buffer result_buffer;
        private Gtk.Button use_btn;
        private Gtk.Entry api_key_entry;
        private Gtk.Revealer api_key_revealer;

        private AIService ai_service;

        public signal void diagram_generated(string plantuml_code);

        public AIAssistantDialog() {
            Object();
        }

        construct {
            title = "AI Diagram Assistant";
            content_width = 700;
            content_height = 600;

            ai_service = new AIService();

            var toolbar_view = new Adw.ToolbarView();

            var header = new Adw.HeaderBar();
            toolbar_view.add_top_bar(header);

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            content.margin_start = 12;
            content.margin_end = 12;
            content.margin_top = 12;
            content.margin_bottom = 12;

            // API Key section (shown if not configured)
            api_key_revealer = new Gtk.Revealer();
            api_key_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            api_key_revealer.reveal_child = !ai_service.has_api_key();

            var api_key_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            api_key_box.add_css_class("card");
            api_key_box.margin_bottom = 12;

            var api_key_inner = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            api_key_inner.margin_start = 12;
            api_key_inner.margin_end = 12;
            api_key_inner.margin_top = 12;
            api_key_inner.margin_bottom = 12;

            var api_label = new Gtk.Label("Enter your Anthropic API key to use AI features:");
            api_label.xalign = 0;
            api_key_inner.append(api_label);

            var api_entry_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            api_key_entry = new Gtk.Entry();
            api_key_entry.hexpand = true;
            api_key_entry.placeholder_text = "sk-ant-...";
            api_key_entry.input_purpose = Gtk.InputPurpose.PASSWORD;
            api_key_entry.visibility = false;
            if (ai_service.get_api_key() != null) {
                api_key_entry.text = ai_service.get_api_key();
            }
            api_entry_box.append(api_key_entry);

            var save_key_btn = new Gtk.Button.with_label("Save");
            save_key_btn.add_css_class("suggested-action");
            save_key_btn.clicked.connect(() => {
                ai_service.save_api_key(api_key_entry.text);
                api_key_revealer.reveal_child = false;
                generate_btn.sensitive = true;
            });
            api_entry_box.append(save_key_btn);

            api_key_inner.append(api_entry_box);
            api_key_box.append(api_key_inner);
            api_key_revealer.child = api_key_box;
            content.append(api_key_revealer);

            // Description section
            var desc_label = new Gtk.Label("Describe the diagram you want to create:");
            desc_label.xalign = 0;
            desc_label.add_css_class("heading");
            content.append(desc_label);

            var desc_scroll = new Gtk.ScrolledWindow();
            desc_scroll.min_content_height = 100;
            desc_scroll.max_content_height = 150;
            desc_scroll.add_css_class("card");

            description_view = new Gtk.TextView();
            description_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            description_view.top_margin = 8;
            description_view.bottom_margin = 8;
            description_view.left_margin = 8;
            description_view.right_margin = 8;
            description_view.buffer.text = "A class diagram showing a User class with name and email fields, an Order class with items and total, and a relationship where a User can have multiple Orders.";

            desc_scroll.child = description_view;
            content.append(desc_scroll);

            // Diagram type selector
            var type_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            type_box.margin_top = 6;

            var type_label = new Gtk.Label("Diagram Type:");
            type_box.append(type_label);

            string[] types = { "Auto-detect", "Class", "Sequence", "Activity", "State", "Use Case", "Component" };
            var type_model = new Gtk.StringList(types);
            type_dropdown = new Gtk.DropDown(type_model, null);
            type_dropdown.selected = 0;
            type_box.append(type_dropdown);

            type_box.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            spinner = new Gtk.Spinner();
            type_box.append(spinner);

            generate_btn = new Gtk.Button.with_label("Generate");
            generate_btn.add_css_class("suggested-action");
            generate_btn.sensitive = ai_service.has_api_key();
            generate_btn.clicked.connect(on_generate);
            type_box.append(generate_btn);

            content.append(type_box);

            // Status label
            status_label = new Gtk.Label("");
            status_label.xalign = 0;
            status_label.add_css_class("dim-label");
            content.append(status_label);

            // Result section
            var result_label = new Gtk.Label("Generated PlantUML:");
            result_label.xalign = 0;
            result_label.add_css_class("heading");
            result_label.margin_top = 12;
            content.append(result_label);

            var result_scroll = new Gtk.ScrolledWindow();
            result_scroll.vexpand = true;
            result_scroll.add_css_class("card");

            result_buffer = new GtkSource.Buffer(null);
            result_view = new GtkSource.View.with_buffer(result_buffer);
            result_view.monospace = true;
            result_view.show_line_numbers = true;
            result_view.top_margin = 6;
            result_view.bottom_margin = 6;
            result_view.left_margin = 6;
            result_view.right_margin = 6;
            result_view.editable = true;

            // Set up syntax highlighting
            var lang_manager = GtkSource.LanguageManager.get_default();
            var language = lang_manager.get_language("plantuml");
            if (language != null) {
                result_buffer.language = language;
            }

            var style_manager = GtkSource.StyleSchemeManager.get_default();
            var scheme = style_manager.get_scheme("Adwaita-dark");
            if (scheme != null) {
                result_buffer.style_scheme = scheme;
            }

            result_scroll.child = result_view;
            content.append(result_scroll);

            // Action buttons
            var action_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            action_box.margin_top = 6;
            action_box.halign = Gtk.Align.END;

            var cancel_btn = new Gtk.Button.with_label("Cancel");
            cancel_btn.clicked.connect(() => this.close());
            action_box.append(cancel_btn);

            use_btn = new Gtk.Button.with_label("Use This Diagram");
            use_btn.add_css_class("suggested-action");
            use_btn.sensitive = false;
            use_btn.clicked.connect(() => {
                diagram_generated(result_buffer.text);
                this.close();
            });
            action_box.append(use_btn);

            content.append(action_box);

            toolbar_view.content = content;
            this.child = toolbar_view;

            // Connect AI service signals
            ai_service.generation_started.connect(() => {
                spinner.spinning = true;
                generate_btn.sensitive = false;
                status_label.label = "Generating...";
            });

            ai_service.generation_completed.connect((code) => {
                spinner.spinning = false;
                generate_btn.sensitive = true;
                status_label.label = "Generation complete!";
                result_buffer.text = code;
                use_btn.sensitive = true;
            });

            ai_service.generation_failed.connect((error) => {
                spinner.spinning = false;
                generate_btn.sensitive = true;
                status_label.label = "Error: " + error;
                status_label.add_css_class("error");
            });
        }

        private void on_generate() {
            status_label.remove_css_class("error");
            string description = description_view.buffer.text.strip();

            if (description.length == 0) {
                status_label.label = "Please enter a description.";
                return;
            }

            string diagram_type = "auto";
            switch (type_dropdown.selected) {
                case 1: diagram_type = "class"; break;
                case 2: diagram_type = "sequence"; break;
                case 3: diagram_type = "activity"; break;
                case 4: diagram_type = "state"; break;
                case 5: diagram_type = "use case"; break;
                case 6: diagram_type = "component"; break;
            }

            ai_service.generate_diagram.begin(description, diagram_type);
        }
    }
}
