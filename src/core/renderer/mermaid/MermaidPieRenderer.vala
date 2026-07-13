namespace GDiagram {
    private class PiePiece {
        public int slice;
        public double start;
        public double end;
        public PiePiece(int slice, double start, double end) {
            this.slice = slice;
            this.start = start;
            this.end = end;
        }
    }

    public class MermaidPieRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // Pie slice colors cycle through the palette's distinctive role
        // slots so each slice is visually distinct and theme-aware.
        private string[] slice_colors() {
            var p = ThemeManager.get_active_palette();
            return new string[] {
                p.person_fill, p.system_fill, p.container_fill, p.component_fill,
                p.success, p.warning, p.accent_secondary, p.accent_primary,
                p.database_fill, p.external_fill, p.node_border, p.boundary_stroke
            };
        }

        public MermaidPieRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        // Pie radius and legend geometry, in points.
        private const double RADIUS = 150.0;
        private const double LEGEND_BOX = 14.0;
        private const double LEGEND_ROW = 22.0;

        public string generate_dot(MermaidPie diagram) {
            double total = diagram.get_total();
            var palette = ThemeManager.get_active_palette();
            var cv = new ChartCanvas();

            double top = 0;
            if (diagram.title != null && diagram.title.length > 0) {
                cv.text(RADIUS, 10, diagram.title, 16, palette.node_text, 'c', false, "pie_title");
                top = 34;
            }
            double cx = RADIUS, cy = top + RADIUS;

            if (diagram.slices.size == 0) {
                cv.circle(cx, cy, RADIUS, palette.grid, palette.node_border, 1.0, "pie");
                return cv.finish("pie", palette.background);
            }

            // Mermaid runs the slices clockwise from 12 o'clock; Graphviz draws
            // wedges counter-clockwise from 3 o'clock. Convert each slice to its
            // counter-clockwise interval, split the one crossing 3 o'clock, and
            // list the pieces in counter-clockwise order. The wedges have no
            // outline (a split slice would show a seam); the rim and the slice
            // borders are drawn on top.
            // d3.pie() over a dataset that sums to zero produces no arcs at all, so
            // Mermaid draws the outer circle and the legend and nothing else. Sharing
            // the circle out evenly instead invented a 50/50 split for `"A" : 0` /
            // `"B" : 0` — two values that say the opposite.
            bool no_data = !(total > 0);
            var fracs = new double[diagram.slices.size];
            for (int i = 0; i < diagram.slices.size; i++) {
                fracs[i] = no_data ? 0.0 : diagram.slices.get(i).value / total;
            }
            // Mermaid drops a slice whose share rounds to "0%" (filteredArcs):
            // neither its wedge nor its label is drawn, but it keeps its angular
            // space and stays in the legend.
            var dropped = new bool[fracs.length];
            for (int i = 0; i < fracs.length; i++) {
                dropped[i] = Math.round(fracs[i] * 100.0) < 1;
            }
            var pieces = new Gee.ArrayList<PiePiece>();
            double cw = 0;
            for (int i = 0; i < fracs.length; i++) {
                // clockwise [cw, cw + f] from 12 o'clock == counter-clockwise
                // [0.25 - cw - f, 0.25 - cw] from 3 o'clock (in turns)
                double lo = 0.25 - cw - fracs[i];
                double hi = 0.25 - cw;
                cw += fracs[i];
                lo -= Math.floor(hi);
                hi -= Math.floor(hi);
                if (lo < 0) {
                    pieces.add(new PiePiece(i, lo + 1.0, 1.0));
                    pieces.add(new PiePiece(i, 0.0, hi));
                } else {
                    pieces.add(new PiePiece(i, lo, hi));
                }
            }
            pieces.sort((x, y) => x.start < y.start ? -1 : (x.start > y.start ? 1 : 0));
            var color_list = new StringBuilder();
            foreach (var piece in pieces) {
                double w = piece.end - piece.start;
                if (w <= 0) continue;
                if (color_list.len > 0) color_list.append(":");
                string wedge = dropped[piece.slice]
                    ? palette.background
                    : get_slice_color(piece.slice, diagram.slices.get(piece.slice));
                color_list.append_printf("%s;%s", wedge, "%.6f".printf(w).replace(",", "."));
            }
            // No wedge at all when nothing has width — an empty `style=wedged`
            // fillcolor is not a colour Graphviz accepts.
            if (color_list.len > 0) {
                cv.shape(cx, cy, 2 * RADIUS, 2 * RADIUS,
                    "id=\"pie\" shape=circle style=wedged fillcolor=\"%s\" color=\"transparent\" label=\"\"".printf(
                        color_list.str));
            }
            // Paint over the anti-aliased seam of the slice split at 3 o'clock.
            foreach (var piece in pieces) {
                if (piece.start == 0.0 && piece.end > 0.0 && piece.end < 1.0) {
                    bool split = false;
                    foreach (var other in pieces) {
                        if (other != piece && other.slice == piece.slice) split = true;
                    }
                    if (split) {
                        cv.line(cx, cy, cx + RADIUS, cy,
                            get_slice_color(piece.slice, diagram.slices.get(piece.slice)), 1.5);
                    }
                }
            }
            cv.circle(cx, cy, RADIUS, "none", palette.node_border, 1.5, "pie_rim");
            // Zero-sum: no slices, so no dividing lines either — they would all sit
            // on top of each other at 12 o'clock.
            if (!no_data && fracs.length > 1) {
                double at = 0;
                for (int i = 0; i < fracs.length; i++) {
                    double ang = 2 * Math.PI * at;
                    cv.line(cx, cy, cx + RADIUS * Math.sin(ang), cy - RADIUS * Math.cos(ang),
                        palette.node_border, 1.0, "pie_border_%d".printf(i));
                    at += fracs[i];
                }
            }

            // Percentages on the slices, at 3/4 of the radius (Mermaid's textPosition).
            double cum = 0;
            for (int i = 0; i < diagram.slices.size; i++) {
                var slice = diagram.slices.get(i);
                double frac = fracs[i];
                double mid = 2 * Math.PI * (cum + frac / 2);
                cum += frac;
                if (dropped[i]) continue;
                string pct = "%.0f%%".printf(Math.round(frac * 100.0));
                string fill = get_slice_color(i, slice);
                cv.text(cx + 0.75 * RADIUS * Math.sin(mid), cy - 0.75 * RADIUS * Math.cos(mid), pct, 12,
                    RenderUtils.contrast_text(fill), 'c', false, "pie_pct_%d".printf(i));
            }

            // Legend to the right: colour box and label, with the value when showData.
            double lx = 2 * RADIUS + 30;
            double ly = cy - diagram.slices.size * LEGEND_ROW / 2;
            for (int i = 0; i < diagram.slices.size; i++) {
                var slice = diagram.slices.get(i);
                double rowy = ly + i * LEGEND_ROW + LEGEND_ROW / 2;
                cv.rect(lx, rowy - LEGEND_BOX / 2, LEGEND_BOX, LEGEND_BOX, get_slice_color(i, slice),
                    palette.node_border, 0.5, "pie_legend_box_%d".printf(i));
                string text = diagram.show_data
                    ? "%s [%s]".printf(slice.label, ChartCanvas.format_value(slice.value))
                    : slice.label;
                cv.text(lx + LEGEND_BOX + 6, rowy, text, 12, palette.node_text, 'l', false,
                    "pie_legend_%d".printf(i));
            }

            return cv.finish("pie", palette.background);
        }

        private string get_slice_color(int index, PieSlice slice) {
            if (slice.color != null && slice.color.length > 0) {
                return slice.color;
            }
            var colors = slice_colors();
            return colors[index % colors.length];
        }

        public uint8[]? render_to_svg(MermaidPie diagram) {
            string dot_source = generate_dot(diagram);

            var graph = RenderUtils.read_dot(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout graph with engine: %s", layout_engine);
                context.free_layout(graph);
                return null;
            }

            uint8[] svg_data;
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(MermaidPie diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0, y = 0, width = width, height = height
                };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                int sn = 0;
                foreach (var slice in diagram.slices) {
                    if (slice.source_line > 0)
                        element_lines.set("legend", slice.source_line);
                    sn++;
                }
                regions.clear();
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(MermaidPie diagram, string filename) {
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(MermaidPie diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidPie diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
