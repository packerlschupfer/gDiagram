namespace GDiagram {
    public class MermaidGanttRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidGanttRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidGantt diagram) {
            var dot = new StringBuilder();

            // Use left-to-right layout for timeline feel
            dot.append("digraph G {\n");
            dot.append("  rankdir=LR;\n");
            dot.append("  bgcolor=\"#FAFAFA\";\n");
            dot.append("  node [fontname=\"Sans\", fontsize=10, shape=box, style=\"filled,rounded\"];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=9, style=invis];\n");
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Render tasks
            int task_num = 0;
            GanttTask? prev_task = null;

            // Group by sections if any
            if (diagram.sections.size > 0) {
                foreach (var section in diagram.sections) {
                    // Section header
                    string section_id = "section_%d".printf(task_num);
                    dot.append_printf("  %s [label=\"%s\", shape=box, style=\"filled,bold\", fillcolor=\"#E3F2FD\", fontsize=11];\n",
                        section_id, RenderUtils.escape_label(section.name));

                    if (prev_task != null) {
                        dot.append_printf("  %s -> %s [style=invis];\n",
                            get_task_id(prev_task), section_id);
                    }

                    GanttTask? section_prev = null;
                    foreach (var task in section.tasks) {
                        render_task(dot, task, task_num++);
                        if (section_prev != null) {
                            dot.append_printf("  %s -> %s;\n",
                                get_task_id(section_prev), get_task_id(task));
                        } else if (prev_task != null || section.tasks.size > 0) {
                            dot.append_printf("  %s -> %s;\n",
                                section_id, get_task_id(task));
                        }
                        section_prev = task;
                    }
                    prev_task = section_prev;
                }
            } else {
                // No sections, just tasks
                foreach (var task in diagram.tasks) {
                    render_task(dot, task, task_num++);
                    if (prev_task != null) {
                        dot.append_printf("  %s -> %s;\n",
                            get_task_id(prev_task), get_task_id(task));
                    }
                    prev_task = task;
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_task(StringBuilder dot, GanttTask task, int num) {
            string task_id = get_task_id(task);
            string label = RenderUtils.escape_label(task.description);

            // Choose color based on status
            string fill_color = get_status_color(task.status);

            dot.append_printf("  %s [label=\"%s\", fillcolor=\"%s\"];\n",
                task_id, label, fill_color);

            regions.add(new ElementRegion(task.id, task.source_line, 0, 0, 0, 0));
        }

        private string get_task_id(GanttTask task) {
            return "task_%s".printf(RenderUtils.sanitize_id(task.id));
        }

        private string get_status_color(GanttTaskStatus status) {
            switch (status) {
                case GanttTaskStatus.DONE:
                    return "#90EE90"; // Light green
                case GanttTaskStatus.ACTIVE:
                    return "#FFD700"; // Gold
                case GanttTaskStatus.CRITICAL:
                    return "#FFB6C1"; // Light pink
                case GanttTaskStatus.MILESTONE:
                    return "#87CEEB"; // Light blue
                default:
                    return "#E0E0E0"; // Gray
            }
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidGantt diagram) {
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
            ret = context.render_data(graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return svg_data;
        }

        // Render to Cairo surface
        public Cairo.ImageSurface? render_to_surface(MermaidGantt diagram) {
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
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidGantt diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidGantt diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                var file = File.new_for_path(filename);
                var stream = file.replace(null, false, FileCreateFlags.NONE);
                stream.write_all(svg_data, null);
                stream.close();
                return true;
            } catch (Error e) {
                warning("Failed to write SVG: %s", e.message);
                return false;
            }
        }

        public bool export_to_pdf(MermaidGantt diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.PdfSurface(filename, width, height);
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

                surface.finish();

                return surface.status() == Cairo.Status.SUCCESS;
            } catch (Error e) {
                warning("Failed to export PDF: %s", e.message);
                return false;
            }
        }
    }
}
