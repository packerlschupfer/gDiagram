namespace GDiagram {
    /**
     * SkinParams stores PlantUML skinparam configuration for theming.
     *
     * Supports:
     * - Global settings: skinparam BackgroundColor #1e1e1e
     * - Element settings: skinparam class { BackgroundColor #36648B }
     *
     * Usage in renderer:
     *   string color = skin_params.get_element_property("class", "BackgroundColor") ?? "#FEFECE";
     */
    public class SkinParams : Object {
        // Global settings (skinparam name value)
        private HashTable<string, string> global_params;

        // Element-specific settings (skinparam element { property value })
        // element -> (property -> value)
        private HashTable<string, HashTable<string, string>> element_params;

        public SkinParams() {
            this.global_params = new HashTable<string, string>(str_hash, str_equal);
            this.element_params = new HashTable<string, HashTable<string, string>>(str_hash, str_equal);
        }

        /**
         * Set a global skinparam value.
         * Example: set_global("BackgroundColor", "#1e1e1e")
         */
        public void set_global(string property, string value) {
            global_params.set(property.down(), value);
        }

        /**
         * Get a global skinparam value.
         * Returns null if not set.
         */
        public string? get_global(string property) {
            return global_params.get(property.down());
        }

        /**
         * Set an element-specific skinparam value.
         * Example: set_element_property("class", "BackgroundColor", "#36648B")
         */
        public void set_element_property(string element, string property, string value) {
            string elem_key = element.down();
            string prop_key = property.down();

            if (!element_params.contains(elem_key)) {
                element_params.set(elem_key, new HashTable<string, string>(str_hash, str_equal));
            }

            var props = element_params.get(elem_key);
            props.set(prop_key, value);
        }

        /**
         * Get an element-specific skinparam value.
         * Falls back to global settings if element-specific not found.
         * Returns null if neither is set.
         */
        public string? get_element_property(string element, string property) {
            string elem_key = element.down();
            string prop_key = property.down();

            // First check element-specific
            if (element_params.contains(elem_key)) {
                var props = element_params.get(elem_key);
                if (props.contains(prop_key)) {
                    return props.get(prop_key);
                }
            }

            // Check for combined key (e.g., "classbackgroundcolor" for "class.BackgroundColor")
            string combined = elem_key + prop_key;
            if (global_params.contains(combined)) {
                return global_params.get(combined);
            }

            // Fall back to global
            return global_params.get(prop_key);
        }

        /**
         * Convenience getters for common properties
         */
        public string? background_color {
            owned get { return get_global("backgroundcolor"); }
        }

        public string? default_font_name {
            owned get { return get_global("defaultfontname"); }
        }

        public string? default_font_size {
            owned get { return get_global("defaultfontsize"); }
        }

        public string? default_font_color {
            owned get { return get_global("defaultfontcolor"); }
        }

        /**
         * Check if any skinparams have been set
         */
        public bool is_empty() {
            return global_params.size() == 0 && element_params.size() == 0;
        }

        /**
         * Merge another SkinParams into this one (e.g., from included file).
         * Values from 'other' take precedence.
         */
        public void merge(SkinParams other) {
            // Merge global params
            other.global_params.foreach((key, val) => {
                global_params.set(key, val);
            });

            // Merge element params
            other.element_params.foreach((elem_key, props) => {
                if (!element_params.contains(elem_key)) {
                    element_params.set(elem_key, new HashTable<string, string>(str_hash, str_equal));
                }
                var our_props = element_params.get(elem_key);
                props.foreach((prop_key, val) => {
                    our_props.set(prop_key, val);
                });
            });
        }
    }
}
