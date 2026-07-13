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

        public double area() {
            return width * height;
        }

        /**
         * The region a click at (px, py) belongs to: the smallest one containing the point,
         * so an element inside a container wins over the container drawn around it.
         *
         * Taking the first match instead made every click inside a `System_Boundary`,
         * `rectangle` or `package` select the container, because a cluster region is listed
         * before the nodes inside it whenever the renderer names the cluster first.
         * RenderUtils.parse_svg_regions orders regions smallest first, so equal-area ties
         * keep that order, but the pick must not depend on the order being right.
         */
        public static DiagramRegion? pick(Gee.List<DiagramRegion> regions, double px, double py) {
            DiagramRegion? best = null;
            foreach (var region in regions) {
                if (!region.contains(px, py)) continue;
                if (best == null || region.area() < best.area()) best = region;
            }
            return best;
        }
    }

    /**
     * The preview's viewport, in logical pixels. The diagram bitmap is img_w x img_h at
     * 100%; the drawing area is scrolled by (scroll_x, scroll_y) when the zoomed diagram
     * is larger than the viewport, and offset by (pan_x, pan_y) when it fits.
     */
    public struct PreviewView {
        public double view_w;
        public double view_h;
        public double img_w;
        public double img_h;
        public double zoom;
        public double pan_x;
        public double pan_y;
        public double scroll_x;
        public double scroll_y;
    }

    // An area of the diagram in diagram pixels
    public struct PreviewRect {
        public double x;
        public double y;
        public double width;
        public double height;

        public bool contains_rect(PreviewRect other) {
            return other.x >= x - 0.5 && other.y >= y - 0.5 &&
                   other.x + other.width <= x + width + 0.5 &&
                   other.y + other.height <= y + height + 0.5;
        }
    }

    /**
     * Display-free preview math: where the diagram is drawn, zooming around an anchor
     * point, and the area worth rendering sharply at the current zoom.
     */
    public class PreviewGeometry {
        public const double MIN_ZOOM = 0.1;
        public const double MAX_ZOOM = 5.0;

        public static double clamp_zoom(double zoom) {
            return double.max(MIN_ZOOM, double.min(zoom, MAX_ZOOM));
        }

        // The zoomed diagram fits the viewport in both directions (no scrolling)
        public static bool fits(PreviewView v) {
            if (v.view_w <= 0 || v.view_h <= 0) return true;
            return v.img_w * v.zoom <= v.view_w && v.img_h * v.zoom <= v.view_h;
        }

        /**
         * Where the diagram's origin is drawn in drawing-area coordinates: the pan plus
         * centring along each direction in which the diagram is smaller than the viewport.
         */
        public static void draw_offset(PreviewView v, out double ox, out double oy) {
            ox = v.pan_x;
            oy = v.pan_y;
            if (v.view_w <= 0 || v.view_h <= 0) return;
            double w = v.img_w * v.zoom;
            double h = v.img_h * v.zoom;
            if (w <= v.view_w) ox += (v.view_w - w) / 2.0;
            if (h <= v.view_h) oy += (v.view_h - h) / 2.0;
        }

        // Diagram pixel under viewport position (vx, vy)
        public static void image_point(PreviewView v, double vx, double vy, out double ix, out double iy) {
            double ox, oy;
            draw_offset(v, out ox, out oy);
            ix = (vx + v.scroll_x - ox) / v.zoom;
            iy = (vy + v.scroll_y - oy) / v.zoom;
        }

        /**
         * The view after zooming to `new_zoom` so the diagram point under viewport position
         * (ax, ay) stays there: the pointer for wheel and pinch zoom, the viewport centre for
         * the zoom buttons and keys. While the diagram fits the viewport the pan moves it;
         * otherwise the scroll position does, clamped to the scrollable range.
         */
        public static PreviewView zoom_at(PreviewView v, double new_zoom, double ax, double ay) {
            double ix, iy;
            image_point(v, ax, ay, out ix, out iy);

            PreviewView r = v;
            r.zoom = clamp_zoom(new_zoom);
            r.pan_x = 0;
            r.pan_y = 0;
            r.scroll_x = 0;
            r.scroll_y = 0;

            double w = r.img_w * r.zoom;
            double h = r.img_h * r.zoom;
            if (fits(r)) {
                double ox, oy;
                draw_offset(r, out ox, out oy);  // centring only, pan is 0
                r.pan_x = ax - ix * r.zoom - ox;
                r.pan_y = ay - iy * r.zoom - oy;
            } else {
                double cx = w <= r.view_w ? (r.view_w - w) / 2.0 : 0;
                double cy = h <= r.view_h ? (r.view_h - h) / 2.0 : 0;
                r.scroll_x = double.max(0, double.min(ix * r.zoom + cx - ax, double.max(0, w - r.view_w)));
                r.scroll_y = double.max(0, double.min(iy * r.zoom + cy - ay, double.max(0, h - r.view_h)));
            }
            return r;
        }

        // The part of the diagram visible in the viewport, clipped to the diagram
        public static PreviewRect visible_rect(PreviewView v) {
            double x0, y0, x1, y1;
            image_point(v, 0, 0, out x0, out y0);
            image_point(v, v.view_w, v.view_h, out x1, out y1);
            x0 = double.max(0, x0);
            y0 = double.max(0, y0);
            x1 = double.min(v.img_w, x1);
            y1 = double.min(v.img_h, y1);
            return PreviewRect() {
                x = x0, y = y0, width = double.max(0, x1 - x0), height = double.max(0, y1 - y0)
            };
        }

        /**
         * The area to render sharply at `scale` device pixels per diagram pixel (zoom times
         * the display's scale factor): the visible part plus a margin for scrolling, cut
         * down to at most `max_pixels` device pixels around the visible part's centre.
         * False when the bitmap preview is already sharp (scale at or below 1) or nothing
         * of the diagram is visible.
         */
        public static bool plan_tile(PreviewView v, double scale, int64 max_pixels, out PreviewRect tile) {
            tile = PreviewRect();
            if (scale <= 1.0001 || v.img_w <= 0 || v.img_h <= 0 || v.view_w <= 0 || v.view_h <= 0) return false;
            var vis = visible_rect(v);
            if (vis.width < 1 || vis.height < 1) return false;

            // Half a viewport of margin on each side
            double x0 = double.max(0, Math.floor(vis.x - vis.width / 2));
            double y0 = double.max(0, Math.floor(vis.y - vis.height / 2));
            double x1 = double.min(v.img_w, Math.ceil(vis.x + vis.width * 1.5));
            double y1 = double.min(v.img_h, Math.ceil(vis.y + vis.height * 1.5));

            double budget = (double) max_pixels / (scale * scale);  // in diagram pixels
            if ((x1 - x0) * (y1 - y0) > budget) {
                // Shrink evenly around the visible centre
                double cx = vis.x + vis.width / 2;
                double cy = vis.y + vis.height / 2;
                double f = Math.sqrt(budget / ((x1 - x0) * (y1 - y0)));
                double hw = (x1 - x0) * f / 2;
                double hh = (y1 - y0) * f / 2;
                x0 = double.max(0, Math.ceil(cx - hw));
                y0 = double.max(0, Math.ceil(cy - hh));
                x1 = double.min(v.img_w, Math.floor(cx + hw));
                y1 = double.min(v.img_h, Math.floor(cy + hh));
            }
            // The rasterizer rounds both axes up, so a rect exactly on the budget becomes
            // w + h + 1 device pixels too big and the tile is refused. Give those back.
            while (x1 - x0 >= 1 && y1 - y0 >= 1 && tile_device_pixels(x1 - x0, y1 - y0, scale) > max_pixels) {
                x1 -= 1;
                y1 -= 1;
            }
            if (x1 - x0 < 1 || y1 - y0 < 1) return false;
            tile = PreviewRect() { x = x0, y = y0, width = x1 - x0, height = y1 - y0 };
            return true;
        }

        // The surface the rasterizer allocates for a tile of this size (it rounds up)
        public static int64 tile_device_pixels(double width, double height, double scale) {
            return (int64) Math.ceil(width * scale) * (int64) Math.ceil(height * scale);
        }
    }
}
