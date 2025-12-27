namespace GDiagram {
    // Represents a clickable region in the rendered diagram
    public class DiagramRegion : Object {
        public string element_name { get; set; }
        public int source_line { get; set; }
        public double x { get; set; }
        public double y { get; set; }
        public double width { get; set; }
        public double height { get; set; }

        public DiagramRegion(string name, int line, double x, double y, double w, double h) {
            this.element_name = name;
            this.source_line = line;
            this.x = x;
            this.y = y;
            this.width = w;
            this.height = h;
        }

        public bool contains(double px, double py) {
            return px >= x && px <= x + width && py >= y && py <= y + height;
        }
    }

    public class PreviewPane : Gtk.Frame {
        private Gtk.DrawingArea drawing_area;
        private Gtk.Label placeholder_label;
        private Gtk.Stack stack;
        private Gtk.ScrolledWindow scroll_window;

        private Cairo.ImageSurface? rendered_surface = null;
        private double zoom_level = 1.0;
        private double pan_x = 0;
        private double pan_y = 0;

        // Minimap settings
        private bool show_minimap = true;
        private const int MINIMAP_WIDTH = 120;
        private const int MINIMAP_HEIGHT = 90;
        private const int MINIMAP_MARGIN = 10;

        // Click regions for source navigation
        private Gee.ArrayList<DiagramRegion> click_regions;

        // Currently highlighted element (for reverse navigation)
        private string? highlighted_element = null;
        private int highlight_fade_timeout = 0;

        // Signal emitted when user clicks on a diagram element
        public signal void element_clicked(string element_name, int source_line);

        // Signal emitted when zoom level changes
        public signal void zoom_changed(double level);

        public PreviewPane() {
            Object();
        }

        construct {
            add_css_class("view");

            click_regions = new Gee.ArrayList<DiagramRegion>();

            stack = new Gtk.Stack();
            stack.hexpand = true;
            stack.vexpand = true;

            // Placeholder for when there's no diagram
            placeholder_label = new Gtk.Label(null);
            placeholder_label.add_css_class("dim-label");
            placeholder_label.valign = Gtk.Align.CENTER;
            placeholder_label.halign = Gtk.Align.CENTER;
            stack.add_named(placeholder_label, "placeholder");

            // Drawing area for rendered diagram
            scroll_window = new Gtk.ScrolledWindow();
            scroll_window.hexpand = true;
            scroll_window.vexpand = true;

            drawing_area = new Gtk.DrawingArea();
            drawing_area.hexpand = true;
            drawing_area.vexpand = true;
            drawing_area.set_draw_func(on_draw);

            scroll_window.child = drawing_area;
            stack.add_named(scroll_window, "preview");

            // Spinner for loading state
            var spinner_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            spinner_box.valign = Gtk.Align.CENTER;
            spinner_box.halign = Gtk.Align.CENTER;

            var spinner = new Gtk.Spinner();
            spinner.spinning = true;
            spinner.width_request = 32;
            spinner.height_request = 32;
            spinner_box.append(spinner);

            var loading_label = new Gtk.Label("Rendering...");
            loading_label.add_css_class("dim-label");
            spinner_box.append(loading_label);

            stack.add_named(spinner_box, "loading");

            // Error state
            var error_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            error_box.valign = Gtk.Align.CENTER;
            error_box.halign = Gtk.Align.CENTER;

            var error_icon = new Gtk.Image.from_icon_name("dialog-error-symbolic");
            error_icon.pixel_size = 48;
            error_icon.add_css_class("error");
            error_box.append(error_icon);

            var error_label = new Gtk.Label("Error rendering diagram");
            error_label.add_css_class("dim-label");
            error_box.append(error_label);

            stack.add_named(error_box, "error");

            stack.visible_child_name = "placeholder";
            this.child = stack;

            // Zoom gesture
            var scroll_controller = new Gtk.EventControllerScroll(
                Gtk.EventControllerScrollFlags.VERTICAL
            );
            scroll_controller.scroll.connect((dx, dy) => {
                if ((scroll_controller.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (dy < 0) {
                        zoom_in();
                    } else {
                        zoom_out();
                    }
                    return true;
                }
                return false;
            });
            drawing_area.add_controller(scroll_controller);

            // Click gesture for element selection and focus
            var click_gesture = new Gtk.GestureClick();
            click_gesture.button = Gdk.BUTTON_PRIMARY;
            click_gesture.pressed.connect((n_press, x, y) => {
                // Grab focus when clicking the diagram
                drawing_area.grab_focus();
                on_click(n_press, x, y);
            });
            drawing_area.add_controller(click_gesture);

            // Motion controller for hover effects
            var motion_controller = new Gtk.EventControllerMotion();
            motion_controller.motion.connect(on_motion);
            motion_controller.leave.connect(on_leave);
            drawing_area.add_controller(motion_controller);

            // Drag gesture for panning
            var drag_gesture = new Gtk.GestureDrag();
            drag_gesture.drag_update.connect((offset_x, offset_y) => {
                var h_adj = scroll_window.hadjustment;
                var v_adj = scroll_window.vadjustment;

                // Pan in opposite direction of drag
                h_adj.value = h_adj.value - offset_x;
                v_adj.value = v_adj.value - offset_y;
            });
            drawing_area.add_controller(drag_gesture);

            // Keyboard controller for shortcuts
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect(on_key_pressed);
            drawing_area.add_controller(key_controller);

            // Make drawing area focusable
            drawing_area.can_focus = true;
            drawing_area.focusable = true;

            // Listen for dark mode changes
            var style_manager = Adw.StyleManager.get_default();
            style_manager.notify["dark"].connect(() => {
                drawing_area.queue_draw();
            });
        }

        private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
            const double PAN_STEP = 50.0;

            var h_adj = scroll_window.hadjustment;
            var v_adj = scroll_window.vadjustment;

            switch (keyval) {
                case Gdk.Key.Left:
                case Gdk.Key.KP_Left:
                    h_adj.value = double.max(h_adj.value - PAN_STEP, h_adj.lower);
                    return true;
                case Gdk.Key.Right:
                case Gdk.Key.KP_Right:
                    h_adj.value = double.min(h_adj.value + PAN_STEP, h_adj.upper - h_adj.page_size);
                    return true;
                case Gdk.Key.Up:
                case Gdk.Key.KP_Up:
                    v_adj.value = double.max(v_adj.value - PAN_STEP, v_adj.lower);
                    return true;
                case Gdk.Key.Down:
                case Gdk.Key.KP_Down:
                    v_adj.value = double.min(v_adj.value + PAN_STEP, v_adj.upper - v_adj.page_size);
                    return true;
                case Gdk.Key.Home:
                case Gdk.Key.KP_Home:
                    zoom_reset();
                    return true;
                case Gdk.Key.plus:
                case Gdk.Key.equal:
                case Gdk.Key.KP_Add:
                    zoom_in();
                    return true;
                case Gdk.Key.minus:
                case Gdk.Key.underscore:
                case Gdk.Key.KP_Subtract:
                    zoom_out();
                    return true;
                case Gdk.Key.@0:
                case Gdk.Key.KP_0:
                    zoom_fit();
                    return true;
                default:
                    return false;
            }
        }

        public void set_placeholder_text(string text) {
            placeholder_label.label = text;
            stack.visible_child_name = "placeholder";
        }

        public void show_loading() {
            stack.visible_child_name = "loading";
        }

        public void show_error(string? message = null) {
            stack.visible_child_name = "error";
        }

        public void set_surface(Cairo.ImageSurface surface) {
            this.rendered_surface = surface;
            drawing_area.set_size_request(
                (int)(surface.get_width() * zoom_level),
                (int)(surface.get_height() * zoom_level)
            );
            drawing_area.queue_draw();
            stack.visible_child_name = "preview";
        }

        private void on_draw(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            // Check if dark mode is active
            var style_manager = Adw.StyleManager.get_default();
            bool is_dark = style_manager.dark;

            if (rendered_surface == null) {
                // Draw placeholder background
                if (is_dark) {
                    cr.set_source_rgba(0.3, 0.3, 0.3, 0.3);
                } else {
                    cr.set_source_rgba(0.5, 0.5, 0.5, 0.1);
                }
                cr.rectangle(0, 0, width, height);
                cr.fill();
                return;
            }

            // Clear background - use neutral gray in dark mode for better diagram visibility
            if (is_dark) {
                // Draw a subtle checkerboard pattern to indicate diagram area
                cr.set_source_rgb(0.2, 0.2, 0.2);
                cr.rectangle(0, 0, width, height);
                cr.fill();

                // Add a subtle border around the diagram area
                cr.set_source_rgb(0.3, 0.3, 0.3);
                cr.set_line_width(1);
                cr.rectangle(0.5, 0.5, width - 1, height - 1);
                cr.stroke();
            } else {
                cr.set_source_rgb(1, 1, 1);
                cr.rectangle(0, 0, width, height);
                cr.fill();
            }

            // Draw the rendered diagram with zoom and pan
            cr.translate(pan_x, pan_y);
            cr.scale(zoom_level, zoom_level);
            cr.set_source_surface(rendered_surface, 0, 0);
            cr.paint();

            // Draw highlight around selected element
            if (highlighted_element != null) {
                foreach (var region in click_regions) {
                    if (region.element_name == highlighted_element) {
                        // Draw highlight rectangle
                        cr.set_source_rgba(0.2, 0.5, 1.0, 0.3);
                        cr.rectangle(region.x - 4, region.y - 4,
                                    region.width + 8, region.height + 8);
                        cr.fill();

                        // Draw border
                        cr.set_source_rgba(0.2, 0.5, 1.0, 0.8);
                        cr.set_line_width(2.0 / zoom_level);
                        cr.rectangle(region.x - 4, region.y - 4,
                                    region.width + 8, region.height + 8);
                        cr.stroke();
                        break;
                    }
                }
            }

            // Reset transform for minimap (draw in screen coordinates)
            cr.identity_matrix();

            // Draw minimap for large diagrams when zoomed in
            if (show_minimap && zoom_level > 1.0) {
                draw_minimap(cr, width, height);
            }
        }

        private void draw_minimap(Cairo.Context cr, int view_width, int view_height) {
            if (rendered_surface == null) return;

            int img_width = rendered_surface.get_width();
            int img_height = rendered_surface.get_height();

            // Calculate minimap scale to fit in MINIMAP_WIDTH x MINIMAP_HEIGHT
            double scale_x = (double)MINIMAP_WIDTH / img_width;
            double scale_y = (double)MINIMAP_HEIGHT / img_height;
            double minimap_scale = double.min(scale_x, scale_y);

            int minimap_w = (int)(img_width * minimap_scale);
            int minimap_h = (int)(img_height * minimap_scale);

            // Position in bottom-right corner
            int minimap_x = view_width - minimap_w - MINIMAP_MARGIN;
            int minimap_y = view_height - minimap_h - MINIMAP_MARGIN;

            // Draw minimap background
            cr.set_source_rgba(0.9, 0.9, 0.9, 0.9);
            cr.rectangle(minimap_x - 2, minimap_y - 2, minimap_w + 4, minimap_h + 4);
            cr.fill();

            // Draw minimap border
            cr.set_source_rgba(0.5, 0.5, 0.5, 1.0);
            cr.set_line_width(1);
            cr.rectangle(minimap_x - 2, minimap_y - 2, minimap_w + 4, minimap_h + 4);
            cr.stroke();

            // Draw scaled diagram
            cr.save();
            cr.translate(minimap_x, minimap_y);
            cr.scale(minimap_scale, minimap_scale);
            cr.set_source_surface(rendered_surface, 0, 0);
            cr.paint();
            cr.restore();

            // Draw viewport rectangle showing visible area
            double vp_x = -pan_x / zoom_level * minimap_scale;
            double vp_y = -pan_y / zoom_level * minimap_scale;
            double vp_w = view_width / zoom_level * minimap_scale;
            double vp_h = view_height / zoom_level * minimap_scale;

            // Clamp to minimap bounds
            vp_x = double.max(0, double.min(vp_x, minimap_w - vp_w));
            vp_y = double.max(0, double.min(vp_y, minimap_h - vp_h));
            vp_w = double.min(vp_w, minimap_w);
            vp_h = double.min(vp_h, minimap_h);

            // Draw viewport outline
            cr.set_source_rgba(0.2, 0.5, 1.0, 0.5);
            cr.rectangle(minimap_x + vp_x, minimap_y + vp_y, vp_w, vp_h);
            cr.fill();

            cr.set_source_rgba(0.2, 0.5, 1.0, 1.0);
            cr.set_line_width(2);
            cr.rectangle(minimap_x + vp_x, minimap_y + vp_y, vp_w, vp_h);
            cr.stroke();
        }

        public void toggle_minimap() {
            show_minimap = !show_minimap;
            drawing_area.queue_draw();
        }

        public bool get_minimap_visible() {
            return show_minimap;
        }

        public void zoom_in() {
            zoom_level = double.min(zoom_level * 1.2, 5.0);
            update_zoom();
        }

        public void zoom_out() {
            zoom_level = double.max(zoom_level / 1.2, 0.1);
            update_zoom();
        }

        public void zoom_reset() {
            zoom_level = 1.0;
            pan_x = 0;
            pan_y = 0;
            update_zoom();
        }

        public void zoom_fit() {
            if (rendered_surface == null) return;

            int img_width = rendered_surface.get_width();
            int img_height = rendered_surface.get_height();
            int view_width = drawing_area.get_width();
            int view_height = drawing_area.get_height();

            if (view_width <= 0 || view_height <= 0) {
                view_width = 400;
                view_height = 300;
            }

            double scale_x = (double)view_width / img_width;
            double scale_y = (double)view_height / img_height;
            zoom_level = double.min(scale_x, scale_y) * 0.95; // 95% to add margin
            zoom_level = double.max(0.1, double.min(zoom_level, 5.0));
            pan_x = 0;
            pan_y = 0;
            update_zoom();
        }

        public double get_zoom_level() {
            return zoom_level;
        }

        public void set_zoom_level(double level) {
            zoom_level = double.max(0.1, double.min(level, 5.0));
            update_zoom();
        }

        public Cairo.ImageSurface? get_surface() {
            return rendered_surface;
        }

        private void update_zoom() {
            if (rendered_surface != null) {
                drawing_area.set_size_request(
                    (int)(rendered_surface.get_width() * zoom_level),
                    (int)(rendered_surface.get_height() * zoom_level)
                );
            }
            drawing_area.queue_draw();
            zoom_changed(zoom_level);
        }

        private void on_click(int n_press, double x, double y) {
            if (rendered_surface == null) return;

            // Convert screen coordinates to image coordinates
            double img_x = (x - pan_x) / zoom_level;
            double img_y = (y - pan_y) / zoom_level;

            // Check if click is within any registered region
            foreach (var region in click_regions) {
                if (region.contains(img_x, img_y)) {
                    element_clicked(region.element_name, region.source_line);
                    return;
                }
            }
        }

        public void clear_regions() {
            click_regions.clear();
        }

        public void add_region(string element_name, int source_line, double x, double y, double width, double height) {
            click_regions.add(new DiagramRegion(element_name, source_line, x, y, width, height));
        }

        public void set_regions(Gee.ArrayList<DiagramRegion> regions) {
            click_regions.clear();
            click_regions.add_all(regions);
        }

        private void on_motion(double x, double y) {
            if (rendered_surface == null) return;

            // Convert screen coordinates to image coordinates
            double img_x = (x - pan_x) / zoom_level;
            double img_y = (y - pan_y) / zoom_level;

            // Check if mouse is over any clickable region
            DiagramRegion? hover_region = null;
            foreach (var region in click_regions) {
                if (region.contains(img_x, img_y)) {
                    hover_region = region;
                    break;
                }
            }

            // Change cursor and show tooltip
            if (hover_region != null) {
                drawing_area.set_cursor_from_name("pointer");
                drawing_area.set_tooltip_text(hover_region.element_name);
            } else {
                drawing_area.set_cursor(null);
                drawing_area.set_tooltip_text(null);
            }
        }

        private void on_leave() {
            drawing_area.set_cursor(null);
        }

        // Highlight and pan to an element by name
        public void highlight_element(string element_name) {
            // Find the region for this element
            DiagramRegion? target = null;
            foreach (var region in click_regions) {
                if (region.element_name == element_name) {
                    target = region;
                    break;
                }
            }

            if (target == null) return;

            // Set highlighted element
            highlighted_element = element_name;

            // Pan to center the element in view
            int view_width = drawing_area.get_width();
            int view_height = drawing_area.get_height();

            // Calculate pan to center the element
            double element_center_x = target.x + target.width / 2;
            double element_center_y = target.y + target.height / 2;

            pan_x = view_width / 2 - element_center_x * zoom_level;
            pan_y = view_height / 2 - element_center_y * zoom_level;

            // Redraw
            drawing_area.queue_draw();

            // Clear highlight after 2 seconds
            if (highlight_fade_timeout > 0) {
                Source.remove(highlight_fade_timeout);
            }
            highlight_fade_timeout = (int) Timeout.add(2000, () => {
                highlighted_element = null;
                drawing_area.queue_draw();
                highlight_fade_timeout = 0;
                return false;
            });
        }

        public void clear_highlight() {
            highlighted_element = null;
            if (highlight_fade_timeout > 0) {
                Source.remove(highlight_fade_timeout);
                highlight_fade_timeout = 0;
            }
            drawing_area.queue_draw();
        }
    }
}
