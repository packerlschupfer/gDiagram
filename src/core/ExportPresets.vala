namespace GDiagram {
    public class ExportPreset : Object {
        public string name { get; set; }
        public string description { get; set; }
        public string format { get; set; } // svg, png, pdf
        public int width { get; set; default = 0; } // 0 = auto
        public int height { get; set; default = 0; }
        public int dpi { get; set; default = 96; }
        public bool transparent { get; set; default = false; }
        public string background_color { get; set; default = "#FFFFFF"; }
        public bool multi_page { get; set; default = false; }
        public int max_page_width { get; set; default = 0; }
        public int max_page_height { get; set; default = 0; }

        public ExportPreset(string name, string format) {
            this.name = name;
            this.format = format;
            this.description = "";
        }
    }

    public class ExportPresets : Object {
        private static Gee.ArrayList<ExportPreset>? presets = null;

        public static void initialize() {
            if (presets != null) return;

            presets = new Gee.ArrayList<ExportPreset>();

            // Web/Documentation presets
            var web_small = new ExportPreset("Web (Small)", "png");
            web_small.description = "Small PNG for web (800x600)";
            web_small.width = 800;
            web_small.height = 600;
            web_small.dpi = 96;
            presets.add(web_small);

            var web_large = new ExportPreset("Web (Large)", "png");
            web_large.description = "Large PNG for web (1920x1080)";
            web_large.width = 1920;
            web_large.height = 1080;
            web_large.dpi = 96;
            presets.add(web_large);

            var web_svg = new ExportPreset("Web (SVG)", "svg");
            web_svg.description = "Scalable vector for web";
            presets.add(web_svg);

            // Print presets
            var print_a4 = new ExportPreset("Print (A4)", "pdf");
            print_a4.description = "A4 paper size (210x297mm)";
            print_a4.width = 2480; // A4 at 300dpi
            print_a4.height = 3508;
            print_a4.dpi = 300;
            presets.add(print_a4);

            var print_letter = new ExportPreset("Print (Letter)", "pdf");
            print_letter.description = "US Letter (8.5x11in)";
            print_letter.width = 2550; // Letter at 300dpi
            print_letter.height = 3300;
            print_letter.dpi = 300;
            presets.add(print_letter);

            // Presentation presets
            var presentation_4k = new ExportPreset("Presentation (4K)", "png");
            presentation_4k.description = "4K resolution (3840x2160)";
            presentation_4k.width = 3840;
            presentation_4k.height = 2160;
            presentation_4k.dpi = 96;
            presets.add(presentation_4k);

            var presentation_hd = new ExportPreset("Presentation (HD)", "png");
            presentation_hd.description = "Full HD (1920x1080)";
            presentation_hd.width = 1920;
            presentation_hd.height = 1080;
            presentation_hd.dpi = 96;
            presets.add(presentation_hd);

            // Social media presets
            var social_square = new ExportPreset("Social (Square)", "png");
            social_square.description = "Instagram/Twitter (1080x1080)";
            social_square.width = 1080;
            social_square.height = 1080;
            social_square.dpi = 96;
            presets.add(social_square);

            var social_wide = new ExportPreset("Social (Wide)", "png");
            social_wide.description = "LinkedIn banner (1584x396)";
            social_wide.width = 1584;
            social_wide.height = 396;
            social_wide.dpi = 96;
            presets.add(social_wide);

            // Documentation presets
            var doc_transparent = new ExportPreset("Docs (Transparent)", "png");
            doc_transparent.description = "PNG with transparent background";
            doc_transparent.transparent = true;
            doc_transparent.dpi = 150;
            presets.add(doc_transparent);

            var doc_vector = new ExportPreset("Docs (Vector)", "svg");
            doc_vector.description = "SVG for documentation";
            presets.add(doc_vector);

            // High DPI presets
            var high_dpi_print = new ExportPreset("Print (High DPI)", "pdf");
            high_dpi_print.description = "300 DPI for professional printing";
            high_dpi_print.dpi = 300;
            presets.add(high_dpi_print);

            var ultra_hd = new ExportPreset("Ultra HD (4K 300dpi)", "png");
            ultra_hd.description = "4K at 300 DPI for maximum quality";
            ultra_hd.width = 3840;
            ultra_hd.height = 2160;
            ultra_hd.dpi = 300;
            presets.add(ultra_hd);

            // Multi-page PDF preset
            var multi_page_doc = new ExportPreset("Multi-Page PDF", "pdf");
            multi_page_doc.description = "Split large diagrams across pages";
            multi_page_doc.multi_page = true;
            multi_page_doc.max_page_width = 2480;  // A4 width at 300dpi
            multi_page_doc.max_page_height = 3508; // A4 height at 300dpi
            multi_page_doc.dpi = 300;
            presets.add(multi_page_doc);
        }

        public static Gee.ArrayList<ExportPreset> get_presets() {
            initialize();
            return presets;
        }

        public static ExportPreset? get_preset(string name) {
            initialize();
            foreach (var preset in presets) {
                if (preset.name == name) {
                    return preset;
                }
            }
            return null;
        }

        public static string[] get_preset_names() {
            initialize();
            var names = new Gee.ArrayList<string>();
            foreach (var preset in presets) {
                names.add(preset.name);
            }
            return names.to_array();
        }

        public static ExportPreset[] get_presets_for_format(string format) {
            initialize();
            var filtered = new Gee.ArrayList<ExportPreset>();
            foreach (var preset in presets) {
                if (preset.format == format) {
                    filtered.add(preset);
                }
            }
            return filtered.to_array();
        }
    }
}
