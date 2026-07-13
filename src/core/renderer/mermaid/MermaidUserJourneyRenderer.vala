namespace GDiagram {
    public class MermaidUserJourneyRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidUserJourneyRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidUserJourney diagram) {
            var dot = new StringBuilder();
            // Assign stable numeric IDs to tasks
            var task_id_map = new Gee.HashMap<UserJourneyTask, string>();
            int id = 0;
            foreach (var t in diagram.all_tasks) {
                task_id_map.set(t, "task_%d".printf(id++));
            }

            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append("  rankdir=LR;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=10, fontcolor=\"%s\"];\n".printf(palette.node_text));
            dot.append("  edge [style=invis, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("  splines=false;\n");
            dot.append("\n");

            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n");
                dot.append("  fontcolor=\"%s\";\n\n".printf(palette.node_text));
            }

            int section_num = 0;

            if (diagram.sections.size > 0) {
                UserJourneyTask? prev_task = null;

                foreach (var section in diagram.sections) {
                    string section_node_id = "section_%d".printf(section_num++);

                    // Section header node
                    dot.append_printf(
                        "  %s [label=\"%s\", shape=box, style=\"filled,bold\", " +
                        "fillcolor=\"%s\", fontcolor=\"%s\", fontsize=11];\n",
                        section_node_id,
                        RenderUtils.escape_label(section.name),
                        palette.container_fill,
                        RenderUtils.contrast_text(palette.container_fill)
                    );

                    if (prev_task != null) {
                        dot.append_printf("  %s -> %s;\n",
                            task_id_map.get(prev_task), section_node_id);
                    }

                    UserJourneyTask? section_prev = null;
                    foreach (var task in section.tasks) {
                        render_task(dot, task, task_id_map.get(task));

                        if (section_prev == null) {
                            dot.append_printf("  %s -> %s;\n",
                                section_node_id, task_id_map.get(task));
                        } else {
                            dot.append_printf("  %s -> %s;\n",
                                task_id_map.get(section_prev), task_id_map.get(task));
                        }
                        section_prev = task;
                    }
                    prev_task = section_prev;
                }
            } else {
                // No sections, render all tasks in sequence
                UserJourneyTask? prev = null;
                foreach (var task in diagram.all_tasks) {
                    render_task(dot, task, task_id_map.get(task));
                    if (prev != null) {
                        dot.append_printf("  %s -> %s;\n",
                            task_id_map.get(prev), task_id_map.get(task));
                    }
                    prev = task;
                }
            }

            dot.append("}\n");
            return dot.str;
        }

        private void render_task(StringBuilder dot, UserJourneyTask task, string node_id) {
            var palette = ThemeManager.get_active_palette();
            string fill = get_score_color(task.score);
            string font_color = palette.node_text;

            // Build label: description + score meter + actors
            var label = new StringBuilder();
            label.append("<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"2\" CELLPADDING=\"4\">");

            // Task description
            label.append_printf(
                "<TR><TD ALIGN=\"CENTER\"><B>%s</B></TD></TR>",
                Markup.escape_text(task.description)
            );

            // Score as filled circles
            label.append("<TR><TD ALIGN=\"CENTER\">");
            label.append(build_score_meter(task.score));
            label.append("</TD></TR>");

            // Actors (if any)
            if (task.actors.size > 0) {
                label.append("<TR><TD ALIGN=\"CENTER\"><FONT POINT-SIZE=\"8\">");
                label.append(Markup.escape_text(string.joinv(", ", task.actors.to_array())));
                label.append("</FONT></TD></TR>");
            }

            label.append("</TABLE>");

            dot.append_printf(
                "  %s [label=<%s>, shape=plaintext, style=\"filled\", fillcolor=\"%s\", " +
                "fontcolor=\"%s\"];\n",
                node_id, label.str, fill, font_color
            );

        }

        private string build_score_meter(int score) {
            // Render score as filled/empty dots: ● ● ○ ○ ○
            var sb = new StringBuilder();
            for (int i = 1; i <= 5; i++) {
                if (i <= score) {
                    sb.append("&#9679;");  // ● filled circle
                } else {
                    sb.append("&#9675;");  // ○ open circle
                }
            }
            return sb.str;
        }

        // Score scale uses palette role fills so the whole gradient flips
        // sensibly with the theme: warning (bad) → success (good).
        private string get_score_color(int score) {
            var palette = ThemeManager.get_active_palette();
            switch (score) {
                case 1: return palette.warning;
                case 2: return palette.accent_secondary;
                case 3: return palette.component_fill;
                case 4: return palette.container_fill;
                case 5: return palette.success;
                default: return palette.node_fill;
            }
        }

        public uint8[]? render_to_svg(MermaidUserJourney diagram) {
            string dot_source = generate_dot(diagram);

            var graph = Gvc.Graph.read_string(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph for user journey");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout user journey graph");
                return null;
            }

            uint8[] svg_data;
            ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);
            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render user journey graph");
                return null;
            }

            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(MermaidUserJourney diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return null;

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 500;
                if (height <= 0) height = 300;

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                int task_id = 0;
                foreach (var task in diagram.all_tasks) {
                    if (task.source_line > 0)
                        element_lines.set("task_%d".printf(task_id), task.source_line);
                    task_id++;
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render user journey SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(MermaidUserJourney diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) return false;
            return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidUserJourney diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidUserJourney diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
