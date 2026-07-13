namespace GDiagram {
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

        public string generate_dot(MermaidPie diagram) {
            var dot = new StringBuilder();
            double total = diagram.get_total();

            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\" fontcolor=\"%s\"];\n".printf(palette.node_text));
            dot.append("  edge [style=invis color=\"%s\" fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("  newrank=true;\n\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontname=\"Sans\";\n");
                dot.append("  fontsize=16;\n");
                dot.append("  fontcolor=\"%s\";\n\n".printf(palette.node_text));
            }

            // Build wedged pie node with color weights
            var color_list = new StringBuilder();
            int i = 0;
            foreach (var slice in diagram.slices) {
                if (i > 0) color_list.append(":");
                string color = get_slice_color(i, slice);
                double weight = (total > 0) ? slice.value / total : 1.0 / diagram.slices.size;
                color_list.append_printf("%s;%f", color, weight);
                i++;
            }

            dot.append_printf("  pie [shape=circle, style=wedged, fillcolor=\"%s\", " +
                "label=\"\", width=4, height=4, fixedsize=true];\n\n",
                color_list.str);

            // Legend: HTML TABLE with colored squares, labels, and percentages
            dot.append("  legend [shape=plaintext, label=<\n");
            dot.append("    <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"4\" CELLPADDING=\"3\">\n");
            i = 0;
            foreach (var slice in diagram.slices) {
                double percentage = slice.get_percentage(total);
                string color = get_slice_color(i, slice);
                string escaped_label = Markup.escape_text(slice.label);

                string value_text;
                if (diagram.show_data) {
                    value_text = "%s [%.1f%%  %.0f]".printf(escaped_label, percentage, slice.value);
                } else {
                    value_text = "%s [%.1f%%]".printf(escaped_label, percentage);
                }

                dot.append_printf("      <TR><TD BGCOLOR=\"%s\" WIDTH=\"20\" HEIGHT=\"20\">" +
                    "</TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"11\" COLOR=\"%s\">%s" +
                    "</FONT></TD></TR>\n",
                    color, palette.node_text, value_text);
                i++;
            }
            dot.append("    </TABLE>\n");
            dot.append("  >];\n\n");

            // Stack pie above legend
            dot.append("  pie -> legend;\n");

            dot.append("}\n");
            return dot.str;
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

            var graph = Gvc.Graph.read_string(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout graph with engine: %s", layout_engine);
                return null;
            }

            uint8[] svg_data;
            ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

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
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

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
            var surface = render_to_surface(diagram);
            if (surface == null) return false;
            return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
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
