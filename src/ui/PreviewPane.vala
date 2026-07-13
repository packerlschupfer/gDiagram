namespace GDiagram {
    public class PreviewPane : Gtk.Frame {
        private Gtk.DrawingArea drawing_area;
        private Gtk.Label placeholder_label;
        private Gtk.Label error_label;
        private Gtk.Label loading_label;
        private const string LOADING_TEXT = "Rendering…";
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

        // Last known mouse position (drawing-area coords), for the pinch fallback
        private double last_mouse_x = 0;
        private double last_mouse_y = 0;
        // The same position in viewport coordinates, taken when the event arrived: that is
        // where the pointer physically is, and it stays valid while the pointer does not move.
        // Drawing-area coordinates do not: a zoom resizes and re-scrolls the drawing area
        // under a motionless pointer, so `last_mouse_* - adjustment` drifted further from the
        // pointer with every wheel notch (~95 px after three).
        private double pointer_view_x = 0;
        private double pointer_view_y = 0;
        private bool pointer_known = false;

        // Pinch-to-zoom start level and the viewport point the gesture zooms around
        private double pinch_start_zoom = 1.0;
        private double pinch_anchor_x = 0;
        private double pinch_anchor_y = 0;

        // Sharp zoom: above 100% the bitmap is blurry when scaled up, so the visible part
        // is rendered again from the SVG at the zoom's resolution (DocumentView asks the
        // render thread) and drawn over it. The serial ties a tile to the bitmap it belongs to.
        private int surface_serial = 0;
        private Cairo.ImageSurface? sharp_surface = null;
        private int sharp_serial = -1;
        private double sharp_scale = 0;
        private PreviewRect sharp_rect;
        private uint sharp_timeout = 0;
        // Last tile asked for, so an unchanged view is not asked for again
        private int requested_serial = -1;
        private double requested_scale = 0;
        private PreviewRect requested_rect;
        // No SVG for the current bitmap: stay with the scaled bitmap
        private int sharp_unavailable_serial = -1;

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

        // A sharp rendering of diagram area (x, y, width, height) at `scale` device pixels
        // per diagram pixel is wanted for the bitmap with this serial (see set_sharp_tile)
        public signal void sharp_tile_needed(int serial, double scale, double x, double y, double width, double height);

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
            // Wrapped: unwrapped, the long "Could not determine diagram type" text was the
            // label's minimum width, which made the preview column wider than the window
            // (a Gtk.Paned end child below its minimum runs off the right edge) and the
            // stack kept that width after a diagram replaced the text
            placeholder_label.wrap = true;
            placeholder_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            placeholder_label.width_chars = 10;
            placeholder_label.max_width_chars = 60;
            placeholder_label.margin_start = 12;
            placeholder_label.margin_end = 12;
            stack.add_named(placeholder_label, "placeholder");

            // Drawing area for rendered diagram
            scroll_window = new Gtk.ScrolledWindow();
            scroll_window.hexpand = true;
            scroll_window.vexpand = true;
            // Scrolling or resizing shows another part of the diagram to sharpen
            scroll_window.hadjustment.value_changed.connect(schedule_sharp_tile);
            scroll_window.vadjustment.value_changed.connect(schedule_sharp_tile);
            scroll_window.hadjustment.notify["page-size"].connect(schedule_sharp_tile);
            scroll_window.vadjustment.notify["page-size"].connect(schedule_sharp_tile);

            drawing_area = new Gtk.DrawingArea();
            drawing_area.hexpand = true;
            drawing_area.vexpand = true;
            // A static function: an instance method as draw func makes the drawing area hold
            // this pane, which holds the drawing area, and neither was ever freed
            drawing_area.set_draw_func(draw_preview);

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

            loading_label = new Gtk.Label(LOADING_TEXT);
            loading_label.add_css_class("dim-label");
            loading_label.wrap = true;
            loading_label.justify = Gtk.Justification.CENTER;
            loading_label.max_width_chars = 40;
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
                wheel_zoom(dy < 0 ? 1.2 : 1.0 / 1.2);
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
                set_pointer_position(x, y);
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
            // On the scrolled window, not the drawing area: scrolling moves the drawing area
            // under the pointer, so offsets measured on it changed with every adjustment and
            // a diagram larger than the view jittered back and forth while dragged
            scroll_window.add_controller(drag_gesture);

            // Pinch-to-zoom for trackpad users
            var pinch_gesture = new Gtk.GestureZoom();
            pinch_gesture.begin.connect(on_pinch_begin);
            pinch_gesture.scale_changed.connect(on_pinch_scale_changed);
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

        // Tests: what the pane says when it has no diagram to show
        public string placeholder_text {
            get { return placeholder_label.label; }
        }

        /**
         * The spinner page, with an optional second line under "Rendering…".
         *
         * A big diagram left the pane blank for over a minute with nothing to say a render
         * was even running, so DocumentView switches to this once a render outlives the
         * moment it could still finish unnoticed, and feeds the elapsed time in as `detail`.
         */
        public void show_loading(string? detail = null) {
            loading_label.label = detail != null && detail.length > 0
                ? "%s\n%s".printf(LOADING_TEXT, detail)
                : LOADING_TEXT;
            stack.visible_child_name = "loading";
        }

        // Tests: the pane is showing the spinner rather than a diagram or a placeholder
        public bool loading_visible {
            get { return stack.visible_child_name == "loading"; }
        }

        // Tests: what the spinner page says
        public string loading_text {
            get { return loading_label.label; }
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

        /**
         * A freshly rendered bitmap. The viewport (zoom, pan and scroll offsets) is kept: the
         * preview re-renders on every keystroke, and resetting it to the top-left threw the
         * user back to the top of the diagram on each edit. reset_view() puts it back when the
         * document behind the pane changes.
         */
        /**
         * Drops the bitmaps and click regions of a closed document. The view calls this from
         * close_document(): on libadwaita 1.5 a closed tab's widgets are never disposed (the
         * tab view keeps them parented), so the memory has to be released explicitly rather
         * than as a side effect of disposal.
         */
        public void release_surfaces() {
            rendered_surface = null;
            sharp_surface = null;
            surface_serial++;
            requested_serial = -1;
            click_regions.clear();
            queue_draw();
        }

        public void set_surface(Cairo.ImageSurface surface) {
            this.rendered_surface = surface;
            // Tiles of the previous bitmap no longer match
            surface_serial++;
            sharp_surface = null;
            requested_serial = -1;
            schedule_sharp_tile();
            double keep_h = scroll_window != null ? scroll_window.hadjustment.value : 0;
            double keep_v = scroll_window != null ? scroll_window.vadjustment.value : 0;
            drawing_area.set_size_request(
                (int)(surface.get_width() * zoom_level),
                (int)(surface.get_height() * zoom_level)
            );
            // The adjustments are clamped while the drawing area is re-laid out: put the
            // offsets back once it has its new size (a shorter diagram clamps them itself)
            if (scroll_window != null && (keep_h != 0 || keep_v != 0)) {
                restore_scroll(keep_h, keep_v);
            }
            drawing_area.queue_draw();
            stack.visible_child_name = "preview";
        }

        // Scroll offsets to put back once the drawing area has been re-laid out
        private double pending_scroll_h = -1;
        private double pending_scroll_v = -1;

        private void restore_scroll(double h, double v) {
            pending_scroll_h = h;
            pending_scroll_v = v;
            scroll_window.hadjustment.value = h;
            scroll_window.vadjustment.value = v;
            // A taller diagram raises the adjustment's upper only at the next allocation, and
            // until then the value above is clamped to the old one
            Idle.add(apply_pending_scroll, Priority.HIGH_IDLE);
        }

        private bool apply_pending_scroll() {
            if (pending_scroll_h >= 0 || pending_scroll_v >= 0) {
                scroll_window.hadjustment.value = pending_scroll_h;
                scroll_window.vadjustment.value = pending_scroll_v;
                pending_scroll_h = -1;
                pending_scroll_v = -1;
            }
            return Source.REMOVE;
        }

        /** Where the viewport is, for tests and for restoring it. */
        public void get_scroll_position(out double h, out double v) {
            h = scroll_window != null ? scroll_window.hadjustment.value : 0;
            v = scroll_window != null ? scroll_window.vadjustment.value : 0;
        }

        /** Scroll the viewport to (h, v) in drawing-area pixels. */
        public void scroll_to(double h, double v) {
            if (scroll_window == null) return;
            scroll_window.hadjustment.value = h;
            scroll_window.vadjustment.value = v;
        }

        /** A different document: back to 100% at the top-left. */
        public void reset_view() {
            pending_scroll_h = -1;
            pending_scroll_v = -1;
            zoom_level = 1.0;
            pan_x = 0;
            pan_y = 0;
            if (scroll_window != null) {
                scroll_window.hadjustment.value = scroll_window.hadjustment.lower;
                scroll_window.vadjustment.value = scroll_window.vadjustment.lower;
            }
            update_zoom();
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

        private static void draw_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            var pane = area.get_ancestor(typeof(PreviewPane)) as PreviewPane;
            if (pane != null) pane.on_draw(area, cr, width, height);
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
            draw_sharp_tile(cr);

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

        // Button and keyboard zoom keep the viewport centre in place; before, the scroll
        // position stayed, so the diagram grew and shrank around the top-left corner
        public void zoom_in() {
            zoom_around_center(zoom_level * 1.2);
        }

        public void zoom_out() {
            zoom_around_center(zoom_level / 1.2);
        }

        private void zoom_around_center(double new_zoom) {
            var v = current_view();
            zoom_around(new_zoom, v.view_w / 2.0, v.view_h / 2.0);
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
            zoom_around_center(level);
        }

        public Cairo.ImageSurface? get_surface() {
            return rendered_surface;
        }

        /**
         * Remember where the pointer is. `x`/`y` are drawing-area coordinates of a live
         * pointer event; they are converted to viewport coordinates right away, while the
         * scroll offsets they were measured against are still the current ones.
         * Public so the display tests can place the pointer.
         */
        public void set_pointer_position(double x, double y) {
            last_mouse_x = x;
            last_mouse_y = y;
            pointer_view_x = x - scroll_window.hadjustment.value;
            pointer_view_y = y - scroll_window.vadjustment.value;
            pointer_known = true;
        }

        /** Where the pointer is in viewport coordinates (tests). */
        public void get_pointer_anchor(out double vx, out double vy) {
            vx = pointer_view_x;
            vy = pointer_view_y;
        }

        /** One wheel notch: zoom by `factor` keeping the diagram point under the pointer. */
        public void wheel_zoom(double factor) {
            if (rendered_surface == null) return;
            if (!pointer_known) {
                zoom_around_center(zoom_level * factor);
                return;
            }
            zoom_around(zoom_level * factor, pointer_view_x, pointer_view_y);
        }

        /**
         * Pinch zoom keeps the point between the fingers fixed. The anchor is taken once,
         * when the gesture starts: every scale_changed re-zooms from pinch_start_zoom, and
         * re-reading the bounding box against the scroll offsets our own zoom had just
         * changed drifted the same way the wheel did.
         */
        private void on_pinch_begin(Gtk.Gesture gesture, Gdk.EventSequence? seq) {
            pinch_start_zoom = zoom_level;
            double x, y;
            if (gesture.get_bounding_box_center(out x, out y)) {
                set_pointer_position(x, y);
            }
            var v = current_view();
            pinch_anchor_x = pointer_known ? pointer_view_x : v.view_w / 2.0;
            pinch_anchor_y = pointer_known ? pointer_view_y : v.view_h / 2.0;
        }

        private void on_pinch_scale_changed(Gtk.GestureZoom gesture, double scale) {
            zoom_around(pinch_start_zoom * scale, pinch_anchor_x, pinch_anchor_y);
        }

        // The viewport as PreviewGeometry sees it (public for tests)
        public PreviewView current_view() {
            return PreviewView() {
                view_w = scroll_window.get_width(),
                view_h = scroll_window.get_height(),
                img_w = rendered_surface != null ? rendered_surface.get_width() : 0,
                img_h = rendered_surface != null ? rendered_surface.get_height() : 0,
                zoom = zoom_level,
                pan_x = pan_x,
                pan_y = pan_y,
                scroll_x = scroll_window.hadjustment.value,
                scroll_y = scroll_window.vadjustment.value
            };
        }

        /**
         * Zoom so the diagram point at viewport position (ax, ay) stays put. The drawing
         * area only gets its new size at the next allocation, and setting the scroll
         * position before that clamped it to the old, smaller range, so the adjustments
         * are given their new range right away.
         */
        public void zoom_around(double new_zoom, double ax, double ay) {
            new_zoom = PreviewGeometry.clamp_zoom(new_zoom);
            if (rendered_surface == null) {
                zoom_level = new_zoom;
                update_zoom();
                return;
            }
            if (new_zoom == zoom_level) return;

            var v = current_view();
            var r = PreviewGeometry.zoom_at(v, new_zoom, ax, ay);
            zoom_level = r.zoom;
            pan_x = r.pan_x;
            pan_y = r.pan_y;

            double w = r.img_w * r.zoom;
            double h = r.img_h * r.zoom;
            drawing_area.set_size_request((int) w, (int) h);
            if (v.view_w > 0 && v.view_h > 0) {
                var hadj = scroll_window.hadjustment;
                var vadj = scroll_window.vadjustment;
                hadj.configure(r.scroll_x, 0, double.max((int) w, v.view_w),
                    hadj.step_increment, hadj.page_increment, v.view_w);
                vadj.configure(r.scroll_y, 0, double.max((int) h, v.view_h),
                    vadj.step_increment, vadj.page_increment, v.view_h);
            }

            drawing_area.queue_draw();
            zoom_changed(zoom_level);
            schedule_sharp_tile();
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
            PreviewGeometry.draw_offset(current_view(), out ox, out oy);
        }

        // True when the scaled diagram fits entirely within the visible
        // viewport (i.e. no scrolling needed in either direction).
        private bool diagram_fits_viewport() {
            if (rendered_surface == null) return true;
            return PreviewGeometry.fits(current_view());
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
            schedule_sharp_tile();
        }

        // ==================== Sharp zoom ====================

        public int get_surface_serial() {
            return surface_serial;
        }

        // Asks for a new tile once the view has been still for a moment
        private void schedule_sharp_tile() {
            if (sharp_timeout != 0) Source.remove(sharp_timeout);
            sharp_timeout = Timeout.add(120, on_sharp_timeout);
        }

        private bool on_sharp_timeout() {
            sharp_timeout = 0;
            request_sharp_tile();
            return Source.REMOVE;
        }

        private double device_scale() {
            return zoom_level * drawing_area.get_scale_factor();
        }

        private void request_sharp_tile() {
            if (rendered_surface == null || stack.visible_child_name != "preview") return;
            if (sharp_unavailable_serial == surface_serial) return;
            double scale = device_scale();
            var v = current_view();
            PreviewRect tile;
            if (!PreviewGeometry.plan_tile(v, scale, RenderWorker.MAX_TILE_PIXELS, out tile)) {
                // At or below 100% the bitmap is sharp
                sharp_surface = null;
                requested_serial = -1;
                return;
            }
            var visible = PreviewGeometry.visible_rect(v);
            // The tile on screen (or the one on its way) already covers the view
            if (sharp_surface != null && sharp_serial == surface_serial && sharp_scale == scale &&
                sharp_rect.contains_rect(visible)) return;
            if (requested_serial == surface_serial && requested_scale == scale &&
                requested_rect.contains_rect(visible)) return;
            requested_serial = surface_serial;
            requested_scale = scale;
            requested_rect = tile;
            sharp_tile_needed(surface_serial, scale, tile.x, tile.y, tile.width, tile.height);
        }

        /**
         * A tile asked for with sharp_tile_needed. Ignored if the bitmap changed since.
         *
         * `no_svg` is what latches sharp zoom off for this bitmap — the diagram has no SVG
         * to sharpen from, so asking again is pointless. A null surface with `no_svg` false
         * is one tile that could not be drawn (over the pixel cap, or a Cairo/rsvg error);
         * treating that as "no SVG" disabled sharp zoom for the rest of the bitmap's life,
         * so one awkward viewport left the whole diagram blurry until the next edit.
         */
        public void set_sharp_tile(int serial, double scale, double x, double y, double width, double height,
                                   Cairo.ImageSurface? surface, bool no_svg = false) {
            if (serial != surface_serial) return;
            if (surface == null) {
                if (no_svg) sharp_unavailable_serial = serial;
                // A failed tile: forget it was asked for, so a different view asks again
                else if (requested_serial == serial) requested_serial = -1;
                return;
            }
            sharp_surface = surface;
            sharp_serial = serial;
            sharp_scale = scale;
            sharp_rect = PreviewRect() { x = x, y = y, width = width, height = height };
            drawing_area.queue_draw();
        }

        public bool has_sharp_tile() {
            return sharp_surface != null && sharp_serial == surface_serial;
        }

        // Called with the context in diagram coordinates
        private void draw_sharp_tile(Cairo.Context cr) {
            if (sharp_surface == null || sharp_serial != surface_serial) return;
            cr.save();
            cr.translate(sharp_rect.x, sharp_rect.y);
            cr.scale(1.0 / sharp_scale, 1.0 / sharp_scale);
            cr.set_source_surface(sharp_surface, 0, 0);
            if (Math.fabs(device_scale() - sharp_scale) < 1e-9) {
                // One tile pixel per device pixel: no resampling blur
                cr.get_source().set_filter(Cairo.Filter.NEAREST);
            }
            cr.rectangle(0, 0, sharp_surface.get_width(), sharp_surface.get_height());
            cr.fill();
            cr.restore();
        }

        private void on_click(int n_press, double x, double y) {
            if (rendered_surface == null) return;

            // Convert screen coordinates to image coordinates
            double ox, oy;
            get_draw_offset(out ox, out oy);
            double img_x = (x - ox) / zoom_level;
            double img_y = (y - oy) / zoom_level;

            // The innermost region under the pointer, not the first one that happens to
            // contain it (see DiagramRegion.pick)
            var region = DiagramRegion.pick(click_regions, img_x, img_y);
            if (region == null) return;
            if (n_press >= 2) {
                // Double-click → drill down into related file
                element_drilled(region.element_name);
            } else {
                element_clicked(region.element_name, region.source_line);
            }
        }

        private void on_right_click(double x, double y) {
            if (rendered_surface == null) return;
            double ox, oy;
            get_draw_offset(out ox, out oy);
            double img_x = (x - ox) / zoom_level;
            double img_y = (y - oy) / zoom_level;
            var region = DiagramRegion.pick(click_regions, img_x, img_y);
            if (region != null) {
                element_context_menu(region.element_name, region.source_line, x, y);
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

            // The same innermost-wins pick as the click, so the tooltip names what a click
            // would select
            DiagramRegion? hover_region = DiagramRegion.pick(click_regions, img_x, img_y);

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
                    // A generated id ("_class_note_2") is shown as its kind ("Note")
                    drawing_area.set_tooltip_text(ElementInspector.hover_name(alias));
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
