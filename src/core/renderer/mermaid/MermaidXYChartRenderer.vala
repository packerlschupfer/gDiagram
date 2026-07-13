namespace GDiagram {
    public class MermaidXYChartRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        private string[] bar_colors(Palette p) {
            return {
                p.system_fill, p.success, p.accent_secondary, p.container_fill, p.person_fill
            };
        }

        // Chart dimensions in HTML table pixels
        private const int CHART_HEIGHT = 200;
        private const int BAR_WIDTH = 30;
        private const int BAR_GAP = 6;
        private const int Y_AXIS_WIDTH = 50;
        private const int TICK_ROWS = 5;

        public MermaidXYChartRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidXYChart diagram) {
            var palette = ThemeManager.get_active_palette();
            var dot = new StringBuilder();

            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=11, shape=plaintext, margin=0];\n");
            dot.append("  edge [style=invis];\n\n");

            // Title (with Y-axis label as subtitle since HTML tables can't rotate text)
            var title_parts = new StringBuilder();
            if (diagram.title != null && diagram.title.length > 0) {
                title_parts.append(RenderUtils.escape_label(diagram.title));
            }
            if (diagram.y_axis_label.length > 0) {
                if (title_parts.len > 0) title_parts.append("\\n");
                title_parts.append_printf("Y: %s", RenderUtils.escape_label(diagram.y_axis_label));
            }
            if (title_parts.len > 0) {
                dot.append_printf("  label=\"%s\";\n", title_parts.str);
                dot.append("  labelloc=t;\n");
                dot.append("  fontname=\"Sans\";\n");
                dot.append("  fontsize=14;\n\n");
            }

            if (diagram.series.size == 0) {
                dot.append("  empty [label=\"(no data)\"];\n");
                dot.append("}\n");
                return dot.str;
            }

            // Determine ranges
            double y_min = diagram.has_y_range ? diagram.y_min : 0.0;
            double y_max = diagram.has_y_range ? diagram.y_max : 0.0;

            if (!diagram.has_y_range) {
                // Auto-detect from data
                foreach (var s in diagram.series) {
                    foreach (var v in s.values) {
                        if (v != null && v > y_max) y_max = v;
                    }
                }
                // Round up to a nice number
                y_max = nice_ceil(y_max);
            }
            if (y_max <= y_min) y_max = y_min + 1.0;
            double y_range = y_max - y_min;

            int cat_count = diagram.x_labels.size;
            if (cat_count == 0) {
                foreach (var s in diagram.series) {
                    if (s.values.size > cat_count) cat_count = s.values.size;
                }
            }

            // Count bar series for grouped bar layout
            int bar_series_count = 0;
            int line_series_count = 0;
            foreach (var s in diagram.series) {
                if (s.series_type == XYSeriesType.BAR) bar_series_count++;
                else line_series_count++;
            }

            // Total width per category group
            int bars_in_group = (bar_series_count > 0) ? bar_series_count : 1;

            // Build the chart as an HTML TABLE:
            // The chart area is a grid of cells.
            // Each row is a "height slice" from the top of the chart down.
            // Left column = Y-axis labels, then one column group per category.

            dot.append("  chart [label=<\n");
            dot.append("    <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">\n");

            // Y-axis label (rotated text not supported in HTML tables, use plain left column)
            // We'll use TICK_ROWS rows for the chart area.
            int row_height = CHART_HEIGHT / TICK_ROWS;

            // Chart rows from top (y_max) to bottom (y_min)
            for (int row = 0; row < TICK_ROWS; row++) {
                double tick_val = y_max - (row * y_range / TICK_ROWS);
                dot.append("      <TR>\n");

                // Y-axis tick label
                dot.append_printf("        <TD WIDTH=\"%d\" ALIGN=\"RIGHT\" VALIGN=\"TOP\">" +
                    "<FONT POINT-SIZE=\"9\" COLOR=\"%s\">%.0f </FONT></TD>\n",
                    Y_AXIS_WIDTH, palette.edge_text, tick_val);

                // Bar cells for each category
                for (int c = 0; c < cat_count; c++) {
                    // Spacer between categories
                    if (c > 0) {
                        dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"%d\"></TD>\n",
                            BAR_GAP * 2, row_height);
                    }

                    // One sub-cell per bar series in this row
                    int bidx = 0;
                    foreach (var s in diagram.series) {
                        if (s.series_type != XYSeriesType.BAR) continue;

                        double val = (c < s.values.size && s.values.get(c) != null) ? s.values.get(c) : 0.0;
                        double fraction = (val - y_min) / y_range;
                        if (fraction < 0) fraction = 0;
                        if (fraction > 1) fraction = 1;

                        // This row covers the range [row_bottom_frac, row_top_frac]
                        double row_top_frac = 1.0 - (double)row / TICK_ROWS;
                        double row_bottom_frac = 1.0 - (double)(row + 1) / TICK_ROWS;

                        string[] bc = bar_colors(palette);
                        string color = bc[bidx % bc.length];

                        if (fraction >= row_top_frac) {
                            // Bar fills entire row
                            dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"%d\" BGCOLOR=\"%s\"></TD>\n",
                                BAR_WIDTH, row_height, color);
                        } else if (fraction > row_bottom_frac) {
                            // Bar partially fills this row
                            double fill_frac = (fraction - row_bottom_frac) / (row_top_frac - row_bottom_frac);
                            int fill_h = (int)(fill_frac * row_height);
                            int empty_h = row_height - fill_h;
                            // Use a nested table to split the cell
                            dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"%d\">" +
                                "<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">" +
                                "<TR><TD HEIGHT=\"%d\" WIDTH=\"%d\"></TD></TR>" +
                                "<TR><TD HEIGHT=\"%d\" WIDTH=\"%d\" BGCOLOR=\"%s\"></TD></TR>" +
                                "</TABLE></TD>\n",
                                BAR_WIDTH, row_height,
                                empty_h, BAR_WIDTH,
                                fill_h, BAR_WIDTH, color);
                        } else {
                            // Bar doesn't reach this row
                            dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"%d\"></TD>\n",
                                BAR_WIDTH, row_height);
                        }

                        if (bidx < bar_series_count - 1) {
                            // Gap between bars in same group
                            dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"%d\"></TD>\n",
                                BAR_GAP, row_height);
                        }
                        bidx++;
                    }
                }
                dot.append("      </TR>\n");
            }

            // Bottom Y-axis tick (y_min)
            dot.append("      <TR>\n");
            dot.append_printf("        <TD WIDTH=\"%d\" ALIGN=\"RIGHT\" VALIGN=\"TOP\">" +
                "<FONT POINT-SIZE=\"9\" COLOR=\"%s\">%.0f </FONT></TD>\n",
                Y_AXIS_WIDTH, palette.edge_text, y_min);
            // Empty cells for alignment
            for (int c = 0; c < cat_count; c++) {
                if (c > 0) {
                    dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"2\"></TD>\n", BAR_GAP * 2);
                }
                int bidx = 0;
                foreach (var s in diagram.series) {
                    if (s.series_type != XYSeriesType.BAR) continue;
                    dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"2\"></TD>\n", BAR_WIDTH);
                    if (bidx < bar_series_count - 1) {
                        dot.append_printf("        <TD WIDTH=\"%d\" HEIGHT=\"2\"></TD>\n", BAR_GAP);
                    }
                    bidx++;
                }
            }
            dot.append("      </TR>\n");

            // X-axis category labels
            dot.append("      <TR>\n");
            dot.append_printf("        <TD WIDTH=\"%d\"></TD>\n", Y_AXIS_WIDTH);
            for (int c = 0; c < cat_count; c++) {
                if (c > 0) {
                    dot.append_printf("        <TD WIDTH=\"%d\"></TD>\n", BAR_GAP * 2);
                }
                string cat_label;
                if (c < diagram.x_labels.size) {
                    cat_label = Markup.escape_text(diagram.x_labels.get(c));
                } else {
                    cat_label = "%d".printf(c + 1);
                }
                int colspan = bar_series_count + (bar_series_count > 1 ? bar_series_count - 1 : 0);
                if (colspan < 1) colspan = 1;
                dot.append_printf("        <TD COLSPAN=\"%d\" ALIGN=\"CENTER\">" +
                    "<FONT POINT-SIZE=\"10\">%s</FONT></TD>\n",
                    colspan, cat_label);
            }
            dot.append("      </TR>\n");

            // X-axis label
            if (diagram.x_axis_label.length > 0) {
                int total_cols = 1 + cat_count * (bar_series_count > 0 ? bar_series_count : 1) + (cat_count - 1);
                dot.append("      <TR>\n");
                dot.append_printf("        <TD></TD><TD COLSPAN=\"%d\" ALIGN=\"CENTER\">" +
                    "<FONT POINT-SIZE=\"10\"><I>%s</I></FONT></TD>\n",
                    total_cols, Markup.escape_text(diagram.x_axis_label));
                dot.append("      </TR>\n");
            }

            // Line series rendering is not yet supported (would need SVG post-processing
            // to draw a polyline connecting bar tops). For now only bar series are shown.

            dot.append("    </TABLE>\n");
            dot.append("  >];\n");
            dot.append("}\n");

            return dot.str;
        }

        // Round up to a "nice" ceiling for Y-axis
        private double nice_ceil(double v) {
            if (v <= 0) return 10;
            double magnitude = Math.pow(10, Math.floor(Math.log10(v)));
            double normalized = v / magnitude;
            double nice;
            if (normalized <= 1.0) nice = 1.0;
            else if (normalized <= 2.0) nice = 2.0;
            else if (normalized <= 5.0) nice = 5.0;
            else nice = 10.0;
            return nice * magnitude;
        }

        public uint8[]? render_to_svg(MermaidXYChart diagram) {
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

        public Cairo.ImageSurface? render_to_surface(MermaidXYChart diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 500;
                if (height <= 0) height = 400;

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0, y = 0, width = width, height = height
                };
                handle.render_document(cr, viewport);

                RenderUtils.parse_svg_regions(svg_data, regions, null, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(MermaidXYChart diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) return false;
            return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidXYChart diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidXYChart diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
