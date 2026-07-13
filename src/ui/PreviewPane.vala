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
        private Gtk.Label error_label;
        private Gtk.Stack stack;
        private Gtk.ScrolledWindow scroll_window;

        private Cairo.ImageSurface? rendered_surface = null;
        private double zoom_level = 1.0;
        private double pan_x = 0;
        private double pan_y = 0;

        // Drag-start state for cumulative GestureDrag offset handling
        private double drag_start_pan_x = 0;
        private double drag_start_pan_y = 0;
        private double drag_start_h_adj = 0;
        private double drag_start_v_adj = 0;

        // Last known mouse position (drawing-area coords) for zoom-to-cursor
        private double last_mouse_x = 0;
        private double last_mouse_y = 0;

        // Pinch-to-zoom start level
        private double pinch_start_zoom = 1.0;

        // Minimap settings
        private bool show_minimap = true;
        private const int MINIMAP_WIDTH = 120;
        private const int MINIMAP_HEIGHT = 90;
        private const int MINIMAP_MARGIN = 10;

        // Click regions for source navigation
        private Gee.ArrayList<DiagramRegion> click_regions;
        // Map of element alias → resolved related-file basename (for drill-down).
        // Populated by DocumentView after each render so the hover tooltip can
        // tell the user which file a double-click would open.
        private Gee.HashMap<string, string> drill_targets;

        // Currently highlighted element (for reverse navigation)
        private string? highlighted_element = null;
        // Currently hovered drillable element (alias). Set by on_motion when
        // the mouse is over a click region whose alias has a drill target;
        // cleared otherwise. Used by on_draw to paint a subtle hover overlay
        // so the user can SEE that double-clicking would do something.
        private string? hovered_drillable = null;
        private int highlight_fade_timeout = 0;

        // Optional dark-mode override (null = follow system theme)
        private bool? dark_override = null;

        // Signal emitted when user clicks on a diagram element
        public signal void element_clicked(string element_name, int source_line);
        // Emitted on double-click — used by MainWindow's drill-down handler
        // to open a related file matching the clicked element's alias.
        public signal void element_drilled(string element_name);
        // Emitted on right-click (secondary button) — used by DocumentView
        // to pop up a context menu at the screen coordinates.
        public signal void element_context_menu(string element_name, int source_line, double x, double y);

        // Signal emitted when zoom level changes
        public signal void zoom_changed(double level);

        public PreviewPane() {
            Object();
        }

        construct {
            add_css_class("view");

            click_regions = new Gee.ArrayList<DiagramRegion>();
            drill_targets = new Gee.HashMap<string, string>();

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

            error_label = new Gtk.Label("Error rendering diagram");
            error_label.add_css_class("dim-label");
            error_label.wrap = true;
            error_label.max_width_chars = 60;
            error_box.append(error_label);

            stack.add_named(error_box, "error");

            stack.visible_child_name = "placeholder";
            this.child = stack;

            // Zoom via mousewheel — zoom toward cursor position (like
            // draw.io / Figma / Inkscape). No modifier needed since the
            // preview pane has no scrollable text content.
            var scroll_controller = new Gtk.EventControllerScroll(
                Gtk.EventControllerScrollFlags.VERTICAL
            );
            scroll_controller.scroll.connect((dx, dy) => {
                zoom_at_cursor(dy < 0 ? 1.2 : 1.0 / 1.2);
                return true;
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

            // Right-click → element_context_menu signal
            var rmb_gesture = new Gtk.GestureClick();
            rmb_gesture.button = Gdk.BUTTON_SECONDARY;
            rmb_gesture.pressed.connect((n_press, x, y) => {
                drawing_area.grab_focus();
                on_right_click(x, y);
            });
            drawing_area.add_controller(rmb_gesture);

            // Motion controller for hover effects + cursor tracking
            var motion_controller = new Gtk.EventControllerMotion();
            motion_controller.motion.connect((x, y) => {
                last_mouse_x = x;
                last_mouse_y = y;
                on_motion(x, y);
            });
            motion_controller.leave.connect(on_leave);
            drawing_area.add_controller(motion_controller);

            // Drag gesture for panning with cursor feedback.
            var drag_gesture = new Gtk.GestureDrag();
            drag_gesture.drag_begin.connect((start_x, start_y) => {
                drag_start_pan_x = pan_x;
                drag_start_pan_y = pan_y;
                drag_start_h_adj = scroll_window.hadjustment.value;
                drag_start_v_adj = scroll_window.vadjustment.value;
                drawing_area.set_cursor_from_name("grabbing");
            });
            drag_gesture.drag_update.connect((offset_x, offset_y) => {
                if (diagram_fits_viewport()) {
                    pan_x = drag_start_pan_x + offset_x;
                    pan_y = drag_start_pan_y + offset_y;
                    drawing_area.queue_draw();
                } else {
                    scroll_window.hadjustment.value = drag_start_h_adj - offset_x;
                    scroll_window.vadjustment.value = drag_start_v_adj - offset_y;
                }
            });
            drag_gesture.drag_end.connect((offset_x, offset_y) => {
                drawing_area.set_cursor_from_name("grab");
            });
            drawing_area.add_controller(drag_gesture);

            // Pinch-to-zoom for trackpad users
            var pinch_gesture = new Gtk.GestureZoom();
            pinch_gesture.begin.connect((seq) => {
                pinch_start_zoom = zoom_level;
            });
            pinch_gesture.scale_changed.connect((scale) => {
                double new_zoom = double.max(0.1, double.min(pinch_start_zoom * scale, 5.0));
                if (new_zoom != zoom_level) {
                    zoom_level = new_zoom;
                    update_zoom();
                }
            });
            drawing_area.add_controller(pinch_gesture);

            // Keyboard controller for shortcuts
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect(on_key_pressed);
            drawing_area.add_controller(key_controller);

            // Make drawing area focusable
            drawing_area.can_focus = true;
            drawing_area.focusable = true;

            // Default cursor — "grab" indicates the canvas is draggable
            drawing_area.set_cursor_from_name("grab");

            // Listen for dark mode changes
            var style_manager = Adw.StyleManager.get_default();
            style_manager.notify["dark"].connect(() => {
                drawing_area.queue_draw();
            });
        }

        private void pan_by(double dx, double dy) {
            if (diagram_fits_viewport()) {
                pan_x += dx;
                pan_y += dy;
                drawing_area.queue_draw();
            } else {
                var h = scroll_window.hadjustment;
                var v = scroll_window.vadjustment;
                h.value = double.max(h.lower, double.min(h.value - dx, h.upper - h.page_size));
                v.value = double.max(v.lower, double.min(v.value - dy, v.upper - v.page_size));
            }
        }

        private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
            const double PAN_STEP = 50.0;

            switch (keyval) {
                case Gdk.Key.Left:
                case Gdk.Key.KP_Left:
                    pan_by(PAN_STEP, 0);
                    return true;
                case Gdk.Key.Right:
                case Gdk.Key.KP_Right:
                    pan_by(-PAN_STEP, 0);
                    return true;
                case Gdk.Key.Up:
                case Gdk.Key.KP_Up:
                    pan_by(0, PAN_STEP);
                    return true;
                case Gdk.Key.Down:
                case Gdk.Key.KP_Down:
                    pan_by(0, -PAN_STEP);
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
            // Update the label with the caller's message if supplied,
            // otherwise fall back to the generic default. The old
            // implementation silently ignored `message`, leaving the
            // user with "Error rendering diagram" regardless of the
            // actual failure.
            if (message != null && message.length > 0) {
                error_label.label = message;
            } else {
                error_label.label = "Error rendering diagram";
            }
            stack.visible_child_name = "error";
        }

        public void set_dark_override(bool? val) {
            dark_override = val;
            drawing_area.queue_draw();
        }

        public void set_surface(Cairo.ImageSurface surface) {
            this.rendered_surface = surface;
            pan_x = 0;
            pan_y = 0;
            drawing_area.set_size_request(
                (int)(surface.get_width() * zoom_level),
                (int)(surface.get_height() * zoom_level)
            );
            // Reset scroll position to top-left so tall diagrams are not
            // stuck scrolled past the top of the new surface.
            if (scroll_window != null) {
                scroll_window.hadjustment.value = scroll_window.hadjustment.lower;
                scroll_window.vadjustment.value = scroll_window.vadjustment.lower;
            }
            drawing_area.queue_draw();
            stack.visible_child_name = "preview";
        }

        /**
         * Paint a subtle dotted-grid canvas as the preview background.
         * Light grey base with darker dots on a 24px grid in light mode;
         * inverted for dark mode. Pan-aware so the dots feel "stationary
         * relative to the diagram" when scrolling — this is a small but
         * disorienting-when-missing detail that distinguishes a CAD/diagram
         * canvas from a generic scroll area.
         */
        private void paint_dotted_canvas(Cairo.Context cr, int width, int height, bool is_dark) {
            // Base fill
            if (is_dark) {
                cr.set_source_rgb(0.16, 0.16, 0.18);   // near-black with a hint of warmth
            } else {
                cr.set_source_rgb(0.94, 0.94, 0.95);   // light cool grey
            }
            cr.rectangle(0, 0, width, height);
            cr.fill();

            // Dot grid
            const double spacing = 24.0;
            const double radius = 0.9;
            if (is_dark) {
                cr.set_source_rgba(1.0, 1.0, 1.0, 0.12);
            } else {
                cr.set_source_rgba(0.0, 0.0, 0.0, 0.25);
            }
            // Offset the grid by the pan amount (mod spacing) so the dots
            // appear to scroll with the diagram. This makes the canvas feel
            // like an infinite drafting board rather than a fixed window.
            double eff_ox, eff_oy;
            get_draw_offset(out eff_ox, out eff_oy);
            double offset_x = ((eff_ox % spacing) + spacing) % spacing;
            double offset_y = ((eff_oy % spacing) + spacing) % spacing;
            double y = offset_y;
            while (y < height) {
                double x = offset_x;
                while (x < width) {
                    cr.arc(x, y, radius, 0, 2 * Math.PI);
                    cr.fill();
                    x += spacing;
                }
                y += spacing;
            }
        }

        private void on_draw(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            // Check if dark mode is active (override or system)
            var style_manager = Adw.StyleManager.get_default();
            bool is_dark = dark_override ?? style_manager.dark;

            // Always paint the dotted-grid canvas background, even when no
            // diagram is loaded. Inspired by inno.navi's grey-with-dots
            // canvas — gives the preview area a "professional drafting board"
            // feel and makes pan/zoom orientation easier.
            paint_dotted_canvas(cr, width, height, is_dark);

            if (rendered_surface == null) {
                return;
            }

            // Draw the rendered diagram with zoom, pan, and auto-centering
            double draw_ox, draw_oy;
            get_draw_offset(out draw_ox, out draw_oy);
            cr.translate(draw_ox, draw_oy);
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

            // Hover overlay for drillable elements — subtle warm tint +
            // dashed gold border. Tells the user "double-click does
            // something here" without competing with the selection style.
            if (hovered_drillable != null) {
                foreach (var region in click_regions) {
                    string alias = region.element_name;
                    if (alias.has_prefix("n_")) alias = alias.substring(2);
                    if (alias != hovered_drillable) continue;

                    cr.set_source_rgba(1.0, 0.78, 0.20, 0.18);   // soft gold fill
                    cr.rectangle(region.x - 3, region.y - 3,
                                region.width + 6, region.height + 6);
                    cr.fill();

                    cr.set_source_rgba(0.95, 0.65, 0.10, 0.85); // gold border
                    cr.set_line_width(1.5 / zoom_level);
                    cr.set_dash({ 4.0 / zoom_level, 3.0 / zoom_level }, 0);
                    cr.rectangle(region.x - 3, region.y - 3,
                                region.width + 6, region.height + 6);
                    cr.stroke();
                    cr.set_dash(null, 0);
                    break;
                }
            }

            // Reset transform for minimap (draw in screen coordinates)
            cr.identity_matrix();

            // Draw minimap only when the scaled diagram exceeds the
            // viewport — not just when zoom > 1.0.
            if (show_minimap && !diagram_fits_viewport()) {
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
            // Use viewport size, not drawing_area (which is sized to diagram*zoom)
            int view_width = scroll_window.get_width();
            int view_height = scroll_window.get_height();

            if (view_width <= 0 || view_height <= 0) {
                view_width = 400;
                view_height = 300;
            }

            double scale_x = (double)view_width / img_width;
            double scale_y = (double)view_height / img_height;
            zoom_level = double.min(scale_x, scale_y) * 0.95;
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

        // Zoom keeping the point under the cursor fixed. The math:
        // record the image-space point under the cursor, apply the new
        // zoom, then reposition (pan or scroll) so that same image point
        // remains at the same viewport pixel.
        private void zoom_at_cursor(double factor) {
            if (rendered_surface == null) return;
            double old_zoom = zoom_level;
            double new_zoom = double.max(0.1, double.min(old_zoom * factor, 5.0));
            if (new_zoom == old_zoom) return;

            // Current effective offset (includes auto-centering)
            double old_ox, old_oy;
            get_draw_offset(out old_ox, out old_oy);

            // Image-space point under cursor
            double img_x = (last_mouse_x - old_ox) / old_zoom;
            double img_y = (last_mouse_y - old_oy) / old_zoom;

            // Cursor position relative to viewport
            double vp_x = last_mouse_x - scroll_window.hadjustment.value;
            double vp_y = last_mouse_y - scroll_window.vadjustment.value;

            zoom_level = new_zoom;

            drawing_area.set_size_request(
                (int)(rendered_surface.get_width() * zoom_level),
                (int)(rendered_surface.get_height() * zoom_level)
            );

            double img_w = rendered_surface.get_width() * new_zoom;
            double img_h = rendered_surface.get_height() * new_zoom;
            int view_w = scroll_window.get_width();
            int view_h = scroll_window.get_height();

            if (view_w > 0 && view_h > 0 && img_w <= view_w && img_h <= view_h) {
                // Diagram fits — the auto-center offset from get_draw_offset
                // will be added dynamically, so we set pan_x/pan_y as the
                // residual needed to keep the cursor point fixed.
                double auto_cx = (view_w - img_w) / 2.0;
                double auto_cy = (view_h - img_h) / 2.0;
                pan_x = vp_x - img_x * new_zoom - auto_cx;
                pan_y = vp_y - img_y * new_zoom - auto_cy;
            } else {
                pan_x = 0;
                pan_y = 0;
                scroll_window.hadjustment.value = img_x * new_zoom - vp_x;
                scroll_window.vadjustment.value = img_y * new_zoom - vp_y;
            }

            drawing_area.queue_draw();
            zoom_changed(zoom_level);
        }

        // True if the given diagram region is currently visible in the viewport.
        private bool element_visible_in_viewport(DiagramRegion region) {
            int view_w = scroll_window.get_width();
            int view_h = scroll_window.get_height();
            if (view_w <= 0 || view_h <= 0) return false;

            double ox, oy;
            get_draw_offset(out ox, out oy);
            double cx = region.x * zoom_level + ox - scroll_window.hadjustment.value;
            double cy = region.y * zoom_level + oy - scroll_window.vadjustment.value;
            double w = region.width * zoom_level;
            double h = region.height * zoom_level;

            return cx + w > 0 && cx < view_w && cy + h > 0 && cy < view_h;
        }

        // Effective draw offset: user-applied pan + auto-centering.
        // Computed dynamically so it adapts to viewport resizes and zoom
        // changes without going stale.
        private void get_draw_offset(out double ox, out double oy) {
            ox = pan_x;
            oy = pan_y;
            if (rendered_surface != null) {
                int vw = scroll_window.get_width();
                int vh = scroll_window.get_height();
                double img_w = rendered_surface.get_width() * zoom_level;
                double img_h = rendered_surface.get_height() * zoom_level;
                if (vw > 0 && vh > 0 && img_w <= vw && img_h <= vh) {
                    ox += (vw - img_w) / 2.0;
                    oy += (vh - img_h) / 2.0;
                }
            }
        }

        // True when the scaled diagram fits entirely within the visible
        // viewport (i.e. no scrolling needed in either direction).
        private bool diagram_fits_viewport() {
            if (rendered_surface == null) return true;
            int view_w = scroll_window.get_width();
            int view_h = scroll_window.get_height();
            if (view_w <= 0 || view_h <= 0) return true;
            double img_w = rendered_surface.get_width() * zoom_level;
            double img_h = rendered_surface.get_height() * zoom_level;
            return img_w <= view_w && img_h <= view_h;
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
            double ox, oy;
            get_draw_offset(out ox, out oy);
            double img_x = (x - ox) / zoom_level;
            double img_y = (y - oy) / zoom_level;

            // Check if click is within any registered region
            foreach (var region in click_regions) {
                if (region.contains(img_x, img_y)) {
                    if (n_press >= 2) {
                        // Double-click → drill down into related file
                        element_drilled(region.element_name);
                    } else {
                        element_clicked(region.element_name, region.source_line);
                    }
                    return;
                }
            }
        }

        private void on_right_click(double x, double y) {
            if (rendered_surface == null) return;
            double ox, oy;
            get_draw_offset(out ox, out oy);
            double img_x = (x - ox) / zoom_level;
            double img_y = (y - oy) / zoom_level;
            foreach (var region in click_regions) {
                if (region.contains(img_x, img_y)) {
                    element_context_menu(region.element_name, region.source_line, x, y);
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

        /**
         * Set the alias → filename map used by hover tooltips. Cleared on
         * each new render. DocumentView populates this after parsing the
         * click regions and resolving each one against the filesystem.
         */
        public void set_drill_targets(Gee.HashMap<string, string> targets) {
            drill_targets.clear();
            foreach (var entry in targets.entries) {
                drill_targets.set(entry.key, entry.value);
            }
        }

        public void set_regions(Gee.ArrayList<DiagramRegion> regions) {
            click_regions.clear();
            click_regions.add_all(regions);
        }

        private void on_motion(double x, double y) {
            if (rendered_surface == null) return;

            // Convert screen coordinates to image coordinates
            double ox, oy;
            get_draw_offset(out ox, out oy);
            double img_x = (x - ox) / zoom_level;
            double img_y = (y - oy) / zoom_level;

            // Check if mouse is over any clickable region
            DiagramRegion? hover_region = null;
            foreach (var region in click_regions) {
                if (region.contains(img_x, img_y)) {
                    hover_region = region;
                    break;
                }
            }

            // Change cursor, show tooltip, and update the drillable hover
            // overlay used by on_draw.
            string? new_drillable = null;
            if (hover_region != null) {
                // Strip the n_ prefix that SVG <title> elements get from
                // dot's node-id sanitization, so the tooltip shows the real
                // alias the user wrote.
                string alias = hover_region.element_name;
                if (alias.has_prefix("n_")) alias = alias.substring(2);

                string? drill = drill_targets.get(alias);
                if (drill != null) {
                    drawing_area.set_tooltip_text(
                        "%s\nDouble-click → %s".printf(alias, drill));
                    new_drillable = alias;
                } else {
                    drawing_area.set_tooltip_text(alias);
                }
                drawing_area.set_cursor_from_name("pointer");
            } else {
                drawing_area.set_cursor_from_name("grab");
                drawing_area.set_tooltip_text(null);
            }

            // Only redraw if the drillable hover state actually changed,
            // otherwise we'd repaint on every pixel of mouse movement.
            if (new_drillable != hovered_drillable) {
                hovered_drillable = new_drillable;
                drawing_area.queue_draw();
            }
        }

        private void on_leave() {
            drawing_area.set_cursor_from_name("grab");
            if (hovered_drillable != null) {
                hovered_drillable = null;
                drawing_area.queue_draw();
            }
        }

        // Highlight an element by name. Only scrolls/pans if the element
        // is not already visible — prevents jarring jumps when clicking
        // through the outline list.
        public void highlight_element(string element_name) {
            DiagramRegion? target = null;
            foreach (var region in click_regions) {
                if (region.element_name == element_name) {
                    target = region;
                    break;
                }
            }
            if (target == null) return;

            highlighted_element = element_name;

            // Only pan/scroll if element is out of view
            if (!element_visible_in_viewport(target)) {
                double element_cx = target.x + target.width / 2;
                double element_cy = target.y + target.height / 2;
                int view_w = scroll_window.get_width();
                int view_h = scroll_window.get_height();
                if (view_w <= 0) view_w = 400;
                if (view_h <= 0) view_h = 300;

                if (diagram_fits_viewport()) {
                    // Subtract auto-center offset since get_draw_offset adds it
                    double img_w = rendered_surface.get_width() * zoom_level;
                    double img_h = rendered_surface.get_height() * zoom_level;
                    double auto_cx = (view_w - img_w) / 2.0;
                    double auto_cy = (view_h - img_h) / 2.0;
                    pan_x = view_w / 2.0 - element_cx * zoom_level - auto_cx;
                    pan_y = view_h / 2.0 - element_cy * zoom_level - auto_cy;
                } else {
                    pan_x = 0;
                    pan_y = 0;
                    scroll_window.hadjustment.value = element_cx * zoom_level - view_w / 2.0;
                    scroll_window.vadjustment.value = element_cy * zoom_level - view_h / 2.0;
                }
            }

            drawing_area.queue_draw();

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
