namespace GDiagram {
    public class DiagramCompareDialog : Adw.Dialog {
        private GtkSource.View left_view;
        private GtkSource.Buffer left_buffer;
        private GtkSource.View right_view;
        private GtkSource.Buffer right_buffer;
        private Gtk.DrawingArea left_preview;
        private Gtk.DrawingArea right_preview;

        private GraphvizRenderer renderer;
        private Cairo.ImageSurface? left_surface = null;
        private Cairo.ImageSurface? right_surface = null;

        private Debouncer left_debouncer;
        private Debouncer right_debouncer;

        private DiagramComparison diagram_comparison;
        private Gtk.Label diff_summary_label;
        private Gtk.Button diff_details_button;
        private Gtk.Button meld_button;

        public DiagramCompareDialog(string? initial_left = null) {
            Object();
            if (initial_left != null) {
                left_buffer.text = initial_left;
            }
        }

        construct {
            title = "Compare Diagrams";
            content_width = 1200;
            content_height = 700;

            renderer = new GraphvizRenderer();
            left_debouncer = new Debouncer(300);
            right_debouncer = new Debouncer(300);
            diagram_comparison = new DiagramComparison();

            var toolbar_view = new Adw.ToolbarView();

            var header = new Adw.HeaderBar();
            toolbar_view.add_top_bar(header);

            // Main content - two panes
            var main_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            main_box.margin_start = 6;
            main_box.margin_end = 6;
            main_box.margin_top = 6;
            main_box.margin_bottom = 6;
            main_box.homogeneous = true;

            // Left pane
            var left_pane = create_pane("Original", out left_view, out left_buffer, out left_preview, true);
            main_box.append(left_pane);

            // Separator
            var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            main_box.append(sep);

            // Right pane
            var right_pane = create_pane("Modified", out right_view, out right_buffer, out right_preview, false);
            main_box.append(right_pane);

            toolbar_view.content = main_box;

            // Bottom diff summary bar
            var diff_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            diff_box.margin_start = 12;
            diff_box.margin_end = 12;
            diff_box.margin_top = 4;
            diff_box.margin_bottom = 4;

            diff_summary_label = new Gtk.Label("Render both diagrams to compare");
            diff_summary_label.hexpand = true;
            diff_summary_label.xalign = 0;
            diff_summary_label.add_css_class("dim-label");
            diff_box.append(diff_summary_label);

            diff_details_button = new Gtk.Button.with_label("Details");
            diff_details_button.add_css_class("flat");
            diff_details_button.visible = false;
            diff_details_button.clicked.connect(show_diff_popover);
            diff_box.append(diff_details_button);

            meld_button = new Gtk.Button.with_label("Open in Meld");
            meld_button.add_css_class("flat");
            meld_button.sensitive = meld_available();
            if (!meld_available()) meld_button.tooltip_text = "Meld not installed";
            meld_button.clicked.connect(() => {
                launch_meld(left_buffer.text, right_buffer.text, "original", "modified");
            });
            diff_box.append(meld_button);

            toolbar_view.add_bottom_bar(diff_box);
            this.child = toolbar_view;

            // Connect buffer changes
            left_buffer.changed.connect(() => {
                left_debouncer.call(() => render_left());
            });

            right_buffer.changed.connect(() => {
                right_debouncer.call(() => render_right());
            });

            // Initial sample diagrams
            left_buffer.text = """@startuml
class User {
  +name: String
  +email: String
}
class Order {
  +items: List
}
User --> Order
@enduml""";

            right_buffer.text = """@startuml
class User {
  +name: String
  +email: String
  +phone: String
}
class Order {
  +items: List
  +total: Decimal
}
class Payment {
  +amount: Decimal
}
User --> Order
Order --> Payment
@enduml""";
        }

        private Gtk.Box create_pane(string label_text, out GtkSource.View view,
                                    out GtkSource.Buffer buffer, out Gtk.DrawingArea preview,
                                    bool is_left) {
            var pane = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            pane.hexpand = true;

            // Header with label and load button
            var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            var label = new Gtk.Label(label_text);
            label.add_css_class("heading");
            label.hexpand = true;
            label.xalign = 0;
            header_box.append(label);

            var load_btn = new Gtk.Button.with_label("Load File...");
            load_btn.clicked.connect(() => {
                load_file.begin(is_left);
            });
            header_box.append(load_btn);

            pane.append(header_box);

            // Paned for source and preview
            var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
            paned.vexpand = true;
            paned.shrink_start_child = false;
            paned.shrink_end_child = false;

            // Source view
            var source_scroll = new Gtk.ScrolledWindow();
            source_scroll.add_css_class("card");
            source_scroll.min_content_height = 150;

            buffer = new GtkSource.Buffer(null);
            view = new GtkSource.View.with_buffer(buffer);
            view.monospace = true;
            view.show_line_numbers = true;
            view.top_margin = 6;
            view.bottom_margin = 6;
            view.left_margin = 6;
            view.right_margin = 6;

            // Set up syntax highlighting
            var lang_manager = GtkSource.LanguageManager.get_default();
            var language = lang_manager.get_language("plantuml");
            if (language != null) {
                buffer.language = language;
            }

            var style_manager = GtkSource.StyleSchemeManager.get_default();
            var scheme = style_manager.get_scheme("Adwaita-dark");
            if (scheme != null) {
                buffer.style_scheme = scheme;
            }

            source_scroll.child = view;
            paned.start_child = source_scroll;

            // Preview
            var preview_scroll = new Gtk.ScrolledWindow();
            preview_scroll.add_css_class("card");
            preview_scroll.vexpand = true;

            preview = new Gtk.DrawingArea();
            preview.hexpand = true;
            preview.vexpand = true;

            if (is_left) {
                preview.set_draw_func(draw_left_preview);
            } else {
                preview.set_draw_func(draw_right_preview);
            }

            preview_scroll.child = preview;
            paned.end_child = preview_scroll;
            paned.position = 200;

            pane.append(paned);

            return pane;
        }

        private void draw_left_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            draw_preview(cr, width, height, left_surface);
        }

        private void draw_right_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            draw_preview(cr, width, height, right_surface);
        }

        private void draw_preview(Cairo.Context cr, int width, int height, Cairo.ImageSurface? surface) {
            // White background
            cr.set_source_rgb(1, 1, 1);
            cr.rectangle(0, 0, width, height);
            cr.fill();

            if (surface == null) {
                cr.set_source_rgb(0.5, 0.5, 0.5);
                cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
                cr.set_font_size(12);
                cr.move_to(width / 2 - 40, height / 2);
                cr.show_text("No diagram");
                return;
            }

            // Scale to fit
            int img_width = surface.get_width();
            int img_height = surface.get_height();

            double scale_x = (double)width / img_width;
            double scale_y = (double)height / img_height;
            double scale = double.min(scale_x, scale_y) * 0.95;

            double offset_x = (width - img_width * scale) / 2;
            double offset_y = (height - img_height * scale) / 2;

            cr.translate(offset_x, offset_y);
            cr.scale(scale, scale);
            cr.set_source_surface(surface, 0, 0);
            cr.paint();
        }

        private void render_left() {
            left_surface = render_diagram(left_buffer.text);
            left_preview.queue_draw();
            run_comparison();
        }

        private void render_right() {
            right_surface = render_diagram(right_buffer.text);
            right_preview.queue_draw();
            run_comparison();
        }

        private Cairo.ImageSurface? render_diagram(string source) {
            string lower = source.strip().down();
            unowned Gvc.Context gvc = renderer.get_context();
            var regions = new Gee.ArrayList<ElementRegion>();

            // ── Mermaid ────────────────────────────────────────────────────────
            if (lower.has_prefix("flowchart") || lower.has_prefix("graph ")) {
                var d = new MermaidFlowchartParser().parse(source);
                if (!d.has_errors()) return new MermaidFlowchartRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("sequencediagram")) {
                var d = new MermaidSequenceParser().parse(source);
                if (!d.has_errors()) return new MermaidSequenceRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("statediagram")) {
                var d = new MermaidStateParser().parse(source);
                if (!d.has_errors()) return new MermaidStateRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("classdiagram")) {
                var d = new MermaidClassParser().parse(source);
                if (!d.has_errors()) return new MermaidClassRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("erdiagram")) {
                var d = new MermaidERParser().parse(source);
                if (!d.has_errors()) return new MermaidERRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("gantt")) {
                var d = new MermaidGanttParser().parse(source);
                if (!d.has_errors()) return new MermaidGanttRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("pie")) {
                var d = new MermaidPieParser().parse(source);
                if (!d.has_errors()) return new MermaidPieRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("journey")) {
                var d = new MermaidUserJourneyParser().parse(source);
                if (!d.has_errors()) return new MermaidUserJourneyRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("gitgraph")) {
                var d = new MermaidGitGraphParser().parse(source);
                if (!d.has_errors()) return new MermaidGitGraphRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("mindmap")) {
                var d = new MermaidMindmapParser().parse(source);
                if (!d.has_errors()) return new MermaidMindmapRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("timeline")) {
                var d = new MermaidTimelineParser().parse(source);
                if (!d.has_errors()) return new MermaidTimelineRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("quadrantchart")) {
                var d = new MermaidQuadrantParser().parse(source);
                if (!d.has_errors()) return new MermaidQuadrantRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("xychart-beta") || lower.has_prefix("xychart")) {
                var d = new MermaidXYChartParser().parse(source);
                if (!d.has_errors()) return new MermaidXYChartRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("kanban")) {
                var d = new MermaidKanbanParser().parse(source);
                if (!d.has_errors()) return new MermaidKanbanRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("sankey-beta") || lower.has_prefix("sankey")) {
                var d = new MermaidSankeyParser().parse(source);
                if (!d.has_errors()) return new MermaidSankeyRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("requirementdiagram") || lower.has_prefix("requirement")) {
                var d = new MermaidRequirementParser().parse(source);
                if (!d.has_errors()) return new MermaidRequirementRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("block-beta") || lower.has_prefix("block")) {
                var d = new MermaidBlockParser().parse(source);
                if (!d.has_errors()) return new MermaidBlockRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("packet-beta") || lower.has_prefix("packet")) {
                var d = new MermaidPacketParser().parse(source);
                if (!d.has_errors()) return new MermaidPacketRenderer(gvc, regions, "dot").render_to_surface(d);
            }
            if (lower.has_prefix("c4context") || lower.has_prefix("c4container") ||
                lower.has_prefix("c4component") || lower.has_prefix("c4dynamic") ||
                lower.has_prefix("c4deployment")) {
                var d = new MermaidC4Parser().parse(source);
                if (!d.has_errors()) return renderer.render_mermaid_c4_to_surface(d);
            }
            if (lower.has_prefix("architecture-beta") || lower.has_prefix("architecture")) {
                var d = new MermaidArchitectureParser().parse(source);
                if (!d.has_errors()) return renderer.render_mermaid_architecture_to_surface(d);
            }
            if (lower.has_prefix("zenuml")) {
                var d = new MermaidZenUMLParser().parse(source);
                if (!d.has_errors()) return renderer.render_mermaid_zenuml_to_surface(d);
            }
            if (lower.has_prefix("radar-beta") || lower.has_prefix("radar")) {
                var d = new MermaidRadarParser().parse(source);
                if (!d.has_errors()) return renderer.render_mermaid_radar_to_surface(d);
            }
            if (lower.has_prefix("treemap-beta") || lower.has_prefix("treemap")) {
                var d = new MermaidTreemapParser().parse(source);
                if (!d.has_errors()) return renderer.render_mermaid_treemap_to_surface(d);
            }

            // ── PlantUML ───────────────────────────────────────────────────────
            var lexer = new Lexer(source);
            var tokens = lexer.scan_all();

            if (lower.contains("class ") || lower.contains("interface ") || lower.contains("--|>")) {
                var diagram = new ClassDiagramParser().parse(tokens);
                if (!diagram.has_errors()) return renderer.render_class_to_surface(diagram);
            }

            // Default: PlantUML sequence
            var preprocessor = new Preprocessor();
            string processed = preprocessor.process(source, null);
            var diagram = new Parser().parse(processed);
            return renderer.render_to_surface(diagram);
        }

        private void run_comparison() {
            if (left_surface == null || right_surface == null) return;

            string left_src  = left_buffer.text.strip();
            string right_src = right_buffer.text.strip();
            string left_lower = left_src.down();

            if (left_lower.has_prefix("flowchart") || left_lower.has_prefix("graph ")) {
                var old_d = new MermaidFlowchartParser().parse(left_src);
                var new_d = new MermaidFlowchartParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_flowcharts(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("sequencediagram")) {
                var old_d = new MermaidSequenceParser().parse(left_src);
                var new_d = new MermaidSequenceParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_sequences(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("statediagram")) {
                var old_d = new MermaidStateParser().parse(left_src);
                var new_d = new MermaidStateParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_states(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("classdiagram")) {
                var old_d = new MermaidClassParser().parse(left_src);
                var new_d = new MermaidClassParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_classes(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("erdiagram")) {
                var old_d = new MermaidERParser().parse(left_src);
                var new_d = new MermaidERParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_er_diagrams(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("gantt")) {
                var old_d = new MermaidGanttParser().parse(left_src);
                var new_d = new MermaidGanttParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_gantt(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("pie")) {
                var old_d = new MermaidPieParser().parse(left_src);
                var new_d = new MermaidPieParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_pie(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("journey")) {
                var old_d = new MermaidUserJourneyParser().parse(left_src);
                var new_d = new MermaidUserJourneyParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_user_journeys(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }
            if (left_lower.has_prefix("gitgraph")) {
                var old_d = new MermaidGitGraphParser().parse(left_src);
                var new_d = new MermaidGitGraphParser().parse(right_src);
                if (!old_d.has_errors() && !new_d.has_errors()) {
                    diagram_comparison.compare_git_graphs(old_d, new_d);
                    update_diff_ui();
                    return;
                }
            }

            // Fallback: line-level diff
            // Check whether the two diagrams are even the same type
            // Both sides must be stripped before prefix matching, otherwise
            // a source with leading whitespace (e.g. copy-pasted from a
            // quoted block) always falls through to "unknown".
            string left_type  = detect_type_label(left_src.strip().down());
            string right_type = detect_type_label(right_src.strip().down());
            if (left_type != right_type) {
                run_line_diff(left_src, right_src,
                    "Semantic comparison unavailable (%s vs %s) — line diff only"
                    .printf(left_type, right_type));
            } else {
                run_line_diff(left_src, right_src,
                    "Semantic comparison not supported for this diagram type — line diff only");
            }
        }

        private string detect_type_label(string lower) {
            if (lower.has_prefix("flowchart") || lower.has_prefix("graph ")) return "flowchart";
            if (lower.has_prefix("sequencediagram"))  return "sequence";
            if (lower.has_prefix("statediagram"))     return "state";
            if (lower.has_prefix("classdiagram"))     return "class";
            if (lower.has_prefix("erdiagram"))        return "ER";
            if (lower.has_prefix("gantt"))            return "gantt";
            if (lower.has_prefix("pie"))              return "pie";
            if (lower.has_prefix("journey"))          return "user-journey";
            if (lower.has_prefix("gitgraph"))         return "git-graph";
            if (lower.has_prefix("mindmap"))          return "mindmap";
            if (lower.has_prefix("timeline"))         return "timeline";
            if (lower.has_prefix("quadrantchart"))    return "quadrant";
            if (lower.has_prefix("xychart"))          return "xychart";
            if (lower.has_prefix("kanban"))           return "kanban";
            if (lower.has_prefix("sankey"))           return "sankey";
            if (lower.has_prefix("block"))            return "block";
            if (lower.has_prefix("packet"))           return "packet";
            if (lower.has_prefix("c4"))               return "c4";
            if (lower.has_prefix("architecture"))     return "architecture";
            if (lower.has_prefix("zenuml"))           return "zenuml";
            if (lower.has_prefix("radar"))            return "radar";
            if (lower.has_prefix("treemap"))          return "treemap";
            if (lower.contains("@startuml"))          return "plantuml";
            return "unknown";
        }

        private void update_diff_ui() {
            int count = diagram_comparison.get_change_count();
            if (count == 0) {
                diff_summary_label.label = "Diagrams are identical";
                diff_summary_label.remove_css_class("dim-label");
            } else {
                int added = 0, removed = 0, modified = 0;
                foreach (var d in diagram_comparison.diffs) {
                    switch (d.change_type) {
                        case DiagramDiff.ChangeType.ADDED:    added++;    break;
                        case DiagramDiff.ChangeType.REMOVED:  removed++;  break;
                        case DiagramDiff.ChangeType.MODIFIED: modified++; break;
                        default:                                           break;
                    }
                }
                diff_summary_label.label = "%d change(s): +%d added  -%d removed  ~%d modified"
                    .printf(count, added, removed, modified);
                diff_summary_label.add_css_class("dim-label");
            }
            diff_details_button.visible = (count > 0);
        }

        private void run_line_diff(string left_src, string right_src, string? prefix = null) {
            string[] left_lines  = left_src.split("\n");
            string[] right_lines = right_src.split("\n");

            var left_set  = new Gee.HashSet<string>();
            var right_set = new Gee.HashSet<string>();
            foreach (var l in left_lines)  if (l.strip() != "") left_set.add(l.strip());
            foreach (var l in right_lines) if (l.strip() != "") right_set.add(l.strip());

            int added = 0, removed = 0;
            foreach (var l in right_lines) if (l.strip() != "" && !left_set.contains(l.strip()))  added++;
            foreach (var l in left_lines)  if (l.strip() != "" && !right_set.contains(l.strip())) removed++;

            string suffix;
            if (added == 0 && removed == 0) {
                suffix = "Diagrams are identical";
                diff_summary_label.remove_css_class("dim-label");
            } else {
                suffix = "~%d line-level changes (+%d -%d)".printf(added + removed, added, removed);
                diff_summary_label.add_css_class("dim-label");
            }

            if (prefix != null) {
                diff_summary_label.label = "%s  |  %s".printf(prefix, suffix);
                diff_summary_label.add_css_class("dim-label");
            } else {
                diff_summary_label.label = suffix;
            }
            diff_details_button.visible = false;
        }

        private void show_diff_popover() {
            var popover = new Gtk.Popover();
            popover.set_parent(diff_details_button);

            var scroll = new Gtk.ScrolledWindow();
            scroll.min_content_width = 420;
            scroll.min_content_height = 300;
            scroll.max_content_height = 500;

            var text = new Gtk.TextView();
            text.editable = false;
            text.monospace = true;
            text.top_margin = 8;
            text.bottom_margin = 8;
            text.left_margin = 10;
            text.right_margin = 10;
            text.buffer.text = diagram_comparison.get_summary();
            scroll.child = text;

            popover.child = scroll;
            popover.popup();
        }

        private static bool meld_available() {
            return Environment.find_program_in_path("meld") != null;
        }

        private void launch_meld(string content_a, string content_b, string label_a, string label_b) {
            string path_a = Path.build_filename(Environment.get_tmp_dir(), "gdiagram_%s.puml".printf(label_a));
            string path_b = Path.build_filename(Environment.get_tmp_dir(), "gdiagram_%s.puml".printf(label_b));
            try {
                FileUtils.set_contents(path_a, content_a);
                FileUtils.set_contents(path_b, content_b);
                Process.spawn_async(null, {"meld", path_a, path_b}, null,
                    SpawnFlags.SEARCH_PATH, null, null);
            } catch (Error e) {
                warning("Failed to launch meld: %s", e.message);
            }
        }

        private async void load_file(bool is_left) {
            var dialog = new Gtk.FileDialog();
            dialog.title = "Open PlantUML File";

            var filter = new Gtk.FileFilter();
            filter.name = "PlantUML files";
            filter.add_pattern("*.puml");
            filter.add_pattern("*.plantuml");
            filter.add_pattern("*.wsd");
            filter.add_pattern("*.pu");
            filter.add_pattern("*.txt");

            var filters = new ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            dialog.filters = filters;
            dialog.default_filter = filter;

            try {
                var file = yield dialog.open(null, null);
                if (file != null) {
                    uint8[] contents;
                    yield file.load_contents_async(null, out contents, null);
                    // Length-aware cast to avoid strlen reading past the
                    // end of the array (when not NUL-terminated) or
                    // truncating at an embedded NUL.
                    string text;
                    if (contents.length == 0) {
                        text = "";
                    } else {
                        unowned string raw = (string) contents;
                        int safe_len = int.min(raw.length, (int) contents.length);
                        text = (raw.length == contents.length)
                            ? raw
                            : raw.substring(0, safe_len);
                    }
                    if (is_left) {
                        left_buffer.text = text;
                    } else {
                        right_buffer.text = text;
                    }
                }
            } catch (Error e) {
                if (!(e is IOError.CANCELLED)) {
                    warning("Failed to load file: %s", e.message);
                }
            }
        }
    }
}
