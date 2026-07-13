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

        public string generate_dot(MermaidKanban diagram) {
            var palette = ThemeManager.get_active_palette();
            string[] column_colors = column_colors_from_palette(palette);
            var dot = new StringBuilder();

            dot.append("digraph kanban {\n");
            dot.append("    bgcolor=\"%s\"\n".printf(palette.background));
            dot.append("    rankdir=LR\n");
            dot.append("    compound=true\n");
            dot.append("    splines=false\n");
            dot.append("    nodesep=0.3\n");
            dot.append("    ranksep=1.0\n");
            dot.append("    node [fontname=\"Sans\" fontsize=10]\n");
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("    label=\"%s\"\n", RenderUtils.escape_label(diagram.title));
                dot.append("    labelloc=t\n");
                dot.append("    fontsize=14\n");
                dot.append("    fontname=\"Sans Bold\"\n\n");
            }

            int col_idx = 0;
            foreach (var col in diagram.columns) {
                string col_color = column_colors[col_idx % column_colors.length];
                string col_id_safe = make_safe_id("col_%d".printf(col_idx));

                dot.append_printf("    subgraph cluster_%s {\n", col_id_safe);
                dot.append_printf("        label=<%s>\n", xml_escape(col.label));
                dot.append_printf("        style=filled\n");
                dot.append_printf("        fillcolor=\"%s\"\n", col_color);
                dot.append("        color=\"%s\"\n".printf(palette.edge_color));
                dot.append("        fontcolor=\"%s\"\n".printf(palette.node_text));
                dot.append("        fontname=\"Sans Bold\"\n");
                dot.append("        fontsize=11\n");
                dot.append("        margin=12\n\n");

                int card_idx = 0;
                foreach (var card in col.cards) {
                    string node_id = "card_%d_%d".printf(col_idx, card_idx);
                    string card_color = get_card_color(card);

                    // Build HTML TABLE label
                    dot.append_printf("        %s [\n", node_id);
                    dot.append("            shape=plaintext\n");
                    dot.append_printf("            label=<%s>\n", build_card_label(card, card_color));
                    dot.append("        ]\n");

                    card_idx++;
                }

                // If no cards, add an invisible placeholder to give the cluster some body
                if (col.cards.size == 0) {
                    string placeholder_id = "placeholder_%d".printf(col_idx);
                    dot.append_printf("        %s [label=\"\" shape=point width=0.01 style=invis]\n", placeholder_id);
                }

                dot.append("    }\n\n");
                col_idx++;
            }

            // Connect columns invisibly to force left-to-right ordering
            for (int i = 0; i < diagram.columns.size - 1; i++) {
                string from_col = make_safe_id("col_%d".printf(i));
                string to_col = make_safe_id("col_%d".printf(i + 1));
                // Connect first cards of adjacent columns if they exist, else placeholders
                string from_node, to_node;
                if (diagram.columns.get(i).cards.size > 0) {
                    from_node = "card_%d_0".printf(i);
                } else {
                    from_node = "placeholder_%d".printf(i);
                }
                if (diagram.columns.get(i + 1).cards.size > 0) {
                    to_node = "card_%d_0".printf(i + 1);
                } else {
                    to_node = "placeholder_%d".printf(i + 1);
                }
                dot.append_printf("    %s -> %s [style=invis ltail=cluster_%s lhead=cluster_%s]\n",
                    from_node, to_node, from_col, to_col);
            }

            // Connect cards within each column invisibly to stack them vertically
            col_idx = 0;
            foreach (var col in diagram.columns) {
                for (int i = 0; i < col.cards.size - 1; i++) {
                    dot.append_printf("    card_%d_%d -> card_%d_%d [style=invis]\n",
                        col_idx, i, col_idx, i + 1);
                }
                col_idx++;
            }

            dot.append("}\n");
            return dot.str;
        }

        private string get_card_color(KanbanCard card) {
            var palette = ThemeManager.get_active_palette();
            if (card.priority != null) {
                string p = card.priority.down();
                if (p.contains("very high")) return palette.warning;
                if (p.contains("high"))      return palette.accent_secondary;
            }
            return palette.component_fill;
        }

        private string build_card_label(KanbanCard card, string bg_color) {
            var sb = new StringBuilder();
            sb.append("<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"6\" BGCOLOR=\"");
            sb.append(bg_color);
            sb.append("\">");

            // Main label row (bold)
            sb.append("<TR><TD><B>");
            sb.append(xml_escape(card.label));
            sb.append("</B></TD></TR>");

            // Metadata row (italic, smaller) — only if any metadata present
            bool has_meta = (card.assigned != null && card.assigned.length > 0) ||
                            (card.ticket != null && card.ticket.length > 0) ||
                            (card.priority != null && card.priority.length > 0);

            if (has_meta) {
                var meta_parts = new Gee.ArrayList<string>();
                if (card.ticket != null && card.ticket.length > 0) {
                    meta_parts.add(xml_escape(card.ticket));
                }
                if (card.assigned != null && card.assigned.length > 0) {
                    meta_parts.add("@" + xml_escape(card.assigned));
                }
                if (card.priority != null && card.priority.length > 0) {
                    meta_parts.add(xml_escape(card.priority));
                }
                sb.append("<TR><TD><FONT POINT-SIZE=\"8\"><I>");
                sb.append(string.joinv(" · ", meta_parts.to_array()));
                sb.append("</I></FONT></TD></TR>");
            }

            sb.append("</TABLE>");
            return sb.str;
        }

        private string xml_escape(string s) {
            return s.replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                    .replace("\"", "&quot;");
        }

        private string make_safe_id(string s) {
            var sb = new StringBuilder();
            foreach (char c in s.to_utf8()) {
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_') {
                    sb.append_c(c);
                } else {
                    sb.append_c('_');
                }
            }
            return sb.str;
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidKanban diagram) {
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
            // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
            ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);

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
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 800;
                if (height <= 0) height = 400;

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
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
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
