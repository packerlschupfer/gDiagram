namespace GDiagram {
    public class MermaidKanbanRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // Column header and card colors are resolved from the active Palette
        // in generate_dot rather than statically — lets the Kanban respond
        // to theme changes at runtime.
        private string[] column_colors_from_palette(Palette p) {
            return {
                p.grid,
                p.component_fill,
                p.success,
                p.accent_secondary,
                p.warning,
                p.person_fill
            };
        }

        public MermaidKanbanRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        // Card text wraps at about this many characters (Mermaid wraps cards
        // to the column width).
        private const int WRAP_CHARS = 26;
        private const int CARD_WIDTH = 190;

        /**
         * The board is one HTML table: a cell per column, left to right, each
         * holding the column title and its cards stacked top to bottom. No
         * Graphviz ranking is involved, so columns cannot drift apart.
         */
        public string generate_dot(MermaidKanban diagram) {
            var palette = ThemeManager.get_active_palette();
            string[] column_colors = column_colors_from_palette(palette);
            var dot = new StringBuilder();

            dot.append("digraph kanban {\n");
            dot.append("    bgcolor=\"%s\"\n".printf(palette.background));
            dot.append("    node [fontname=\"Sans\" fontsize=11 shape=plaintext]\n");

            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
                dot.append("    labelloc=t\n");
                dot.append("    fontsize=14\n");
                dot.append("    fontname=\"Sans Bold\"\n");
                dot.append_printf("    fontcolor=\"%s\"\n", palette.node_text);
            }

            if (diagram.columns.size == 0) {
                dot.append("    empty [label=\"(empty board)\"]\n}\n");
                return dot.str;
            }

            // Each column as its own table first, so they can be measured.
            var column_tables = new Gee.ArrayList<string>();
            int col_idx = 0;
            foreach (var col in diagram.columns) {
                column_tables.add(build_column(col, col_idx, column_colors[col_idx % column_colors.length], palette, 0));
                col_idx++;
            }

            // Graphviz stretches a nested table to its cell, spreading the
            // extra height over the rows: a short column's cards would drift
            // down. Pad every column to the tallest with an empty last row.
            double[] heights = measure_heights(column_tables);
            double tallest = 0;
            foreach (var h in heights) tallest = double.max(tallest, h);

            dot.append("    board [label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"10\" CELLPADDING=\"0\"><TR>");
            col_idx = 0;
            foreach (var col in diagram.columns) {
                double pad = heights[col_idx] > 0 ? tallest - heights[col_idx] : 0;
                string table = pad >= 8
                    ? build_column(col, col_idx, column_colors[col_idx % column_colors.length], palette, (int) Math.floor(pad - 6))
                    : column_tables.get(col_idx);
                dot.append_printf("<TD VALIGN=\"TOP\" ID=\"kanban_col_%d\">%s</TD>", col_idx, table);
                col_idx++;
            }
            dot.append("</TR></TABLE>>]\n");
            dot.append("}\n");
            return dot.str;
        }

        private string build_column(KanbanColumn col, int col_idx, string col_color, Palette palette, int filler) {
            var sb = new StringBuilder();
            string col_bg = col_color.length == 7 ? col_color + "55" : col_color;
            sb.append_printf("<TABLE BORDER=\"1\" COLOR=\"%s\" STYLE=\"ROUNDED\" BGCOLOR=\"%s\" CELLBORDER=\"0\" CELLSPACING=\"6\" CELLPADDING=\"3\">",
                col_color, col_bg);
            sb.append_printf("<TR><TD WIDTH=\"%d\"><FONT POINT-SIZE=\"14\" COLOR=\"%s\">%s</FONT></TD></TR>",
                CARD_WIDTH, palette.node_text, Markup.escape_text(col.label));
            int card_idx = 0;
            foreach (var card in col.cards) {
                sb.append_printf("<TR><TD ID=\"kanban_card_%d_%d\">%s</TD></TR>",
                    col_idx, card_idx, build_card_label(card, palette));
                card_idx++;
            }
            if (col.cards.size == 0) {
                sb.append("<TR><TD HEIGHT=\"20\"> </TD></TR>");
            }
            if (filler > 0) {
                sb.append_printf("<TR><TD HEIGHT=\"%d\" CELLPADDING=\"0\"></TD></TR>", filler);
            }
            sb.append("</TABLE>");
            return sb.str;
        }

        // Laid-out heights (points) of the column tables, from a throwaway
        // Graphviz run; 0 when it fails.
        private double[] measure_heights(Gee.ArrayList<string> tables) {
            double[] heights = new double[tables.size];
            var sb = new StringBuilder("digraph measure {\n  node [fontname=\"Sans\" fontsize=11 shape=plain];\n");
            for (int i = 0; i < tables.size; i++) {
                sb.append_printf("  m%d [label=<%s>];\n", i, tables.get(i));
            }
            sb.append("}\n");
            var graph = RenderUtils.read_dot(sb.str);
            if (graph == null) return heights;
            if (context.layout(graph, "dot") == 0) {
                uint8[] data;
                if (RenderUtils.render_data(context, graph, "plain", out data) == 0) {
                    var text = new StringBuilder.sized(data.length + 1);
                    text.append_len((string) data, data.length);
                    foreach (string line in text.str.split("\n")) {
                        string[] f = line.split(" ");
                        if (f.length >= 6 && f[0] == "node" && f[1].has_prefix("m")) {
                            int idx = int.parse(f[1].substring(1));
                            if (idx >= 0 && idx < heights.length) heights[idx] = double.parse(f[5]) * 72.0;
                        }
                    }
                }
                context.free_layout(graph);
            }
            return heights;
        }

        // Priority marker colours, as Mermaid: red, orange, (none), blue, grey-blue.
        private string? priority_color(KanbanCard card, Palette palette) {
            if (card.priority == null) return null;
            string p = card.priority.down().strip();
            if (p == "very high") return palette.warning;
            if (p == "high") return palette.accent_secondary;
            if (p == "low") return palette.system_fill;
            if (p == "very low") return palette.container_fill;
            return null;
        }

        // Greedy word wrap into <BR/>-separated lines. A word longer than the
        // column is hard-broken: left whole it made its card — and with it the
        // whole column — as wide as the word.
        private static string wrap_text(string text, int width) {
            var lines = new Gee.ArrayList<string>();
            var cur = new StringBuilder();
            foreach (var raw in text.split(" ")) {
                if (raw.length == 0) continue;
                string word = raw;
                // Break by character index, not by byte: a multi-byte word cut
                // at a byte offset would split a character in half.
                while (word.char_count() > width) {
                    if (cur.len > 0) {
                        lines.add(cur.str);
                        cur.truncate(0);
                    }
                    lines.add(word.substring(0, word.index_of_nth_char(width)));
                    word = word.substring(word.index_of_nth_char(width));
                }
                if (word.char_count() == 0) continue;
                if (cur.len > 0 && cur.str.char_count() + 1 + word.char_count() > width) {
                    lines.add(cur.str);
                    cur.truncate(0);
                }
                if (cur.len > 0) cur.append_c(' ');
                cur.append(word);
            }
            if (cur.len > 0) lines.add(cur.str);
            var sb = new StringBuilder();
            for (int i = 0; i < lines.size; i++) {
                if (i > 0) sb.append("<BR ALIGN=\"LEFT\"/>");
                sb.append(Markup.escape_text(lines.get(i)));
            }
            sb.append("<BR ALIGN=\"LEFT\"/>");
            return sb.str;
        }

        // Graphviz rejects an empty <FONT>: a blank cell gets a space.
        private static string meta_text(string? text, Palette palette) {
            if (text == null || text.length == 0) return " ";
            return "<FONT POINT-SIZE=\"10\" COLOR=\"%s\">%s</FONT>".printf(palette.node_text, Markup.escape_text(text));
        }

        // A card: priority bar on the left, the wrapped label, then the ticket
        // (left) and the assignee (right) when given.
        private string build_card_label(KanbanCard card, Palette palette) {
            string? bar = priority_color(card, palette);
            bool has_meta = (card.ticket != null && card.ticket.length > 0) ||
                            (card.assigned != null && card.assigned.length > 0);
            var sb = new StringBuilder();
            sb.append_printf("<TABLE BORDER=\"1\" COLOR=\"%s\" BGCOLOR=\"%s\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"5\">",
                palette.node_border, palette.node_fill);
            sb.append_printf("<TR><TD ROWSPAN=\"%d\" WIDTH=\"4\" CELLPADDING=\"0\" BGCOLOR=\"%s\"></TD>",
                has_meta ? 2 : 1, bar ?? palette.node_fill);
            sb.append_printf("<TD COLSPAN=\"2\" WIDTH=\"%d\" ALIGN=\"LEFT\" BALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD></TR>",
                CARD_WIDTH - 20, palette.node_text, wrap_text(card.label, WRAP_CHARS));
            if (has_meta) {
                sb.append_printf("<TR><TD ALIGN=\"LEFT\">%s</TD><TD ALIGN=\"RIGHT\">%s</TD></TR>",
                    meta_text(card.ticket, palette), meta_text(card.assigned, palette));
            }
            sb.append("</TABLE>");
            return sb.str;
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidKanban diagram) {
            string dot_source = generate_dot(diagram);

            var graph = RenderUtils.read_dot(dot_source);
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
            // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return svg_data;
        }

        // Render to Cairo surface
        public Cairo.ImageSurface? render_to_surface(MermaidKanban diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 800, 400, out width, out height);

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                int ci = 0;
                foreach (var col in diagram.columns) {
                    int cardi = 0;
                    foreach (var card in col.cards) {
                        if (card.source_line > 0)
                            element_lines.set("card_%d_%d".printf(ci, cardi), card.source_line);
                        cardi++;
                    }
                    ci++;
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidKanban diagram, string filename) {
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(MermaidKanban diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidKanban diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
