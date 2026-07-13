namespace GDiagram {
    public class MermaidGanttRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidGanttRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidGantt diagram) {
            var dot = new StringBuilder();

            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=10, shape=box, style=\"filled,rounded\"];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("  compound=true;\n");
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Build task-id lookup for dependency arrows
            var task_by_id = new Gee.HashMap<string, GanttTask>();
            foreach (var t in diagram.tasks) {
                task_by_id.set(t.id, t);
            }

            int cluster_num = 0;
            GanttTask? prev_task = null;

            if (diagram.sections.size > 0) {
                foreach (var section in diagram.sections) {
                    if (section.tasks.size == 0) continue;

                    dot.append_printf("  subgraph cluster_section_%d {\n", cluster_num++);
                    dot.append_printf("    label=\"%s\";\n", RenderUtils.escape_label(section.name));
                    dot.append("    style=rounded;\n");
                    dot.append("    color=\"%s\";\n".printf(palette.boundary_stroke));
                    dot.append("    fillcolor=\"%s\";\n".printf(palette.grid));
                    dot.append("    fontsize=11;\n\n");

                    GanttTask? section_prev = null;
                    foreach (var task in section.tasks) {
                        render_task(dot, task, "    ");
                        // Sequential edge within section (invisible ordering)
                        if (section_prev != null && task.depends_on == null) {
                            dot.append_printf("    %s -> %s [style=invis];\n",
                                get_task_id(section_prev), get_task_id(task));
                        }
                        section_prev = task;
                    }
                    dot.append("  }\n\n");

                    // Connect last task of previous section to first of this one (invisible)
                    if (prev_task != null && section.tasks.size > 0) {
                        var first_task = section.tasks.get(0);
                        dot.append_printf("  %s -> %s [style=invis];\n",
                            get_task_id(prev_task), get_task_id(first_task));
                    }
                    prev_task = section_prev;
                }
            } else {
                // No sections — render flat list
                foreach (var task in diagram.tasks) {
                    render_task(dot, task, "  ");
                    if (prev_task != null && task.depends_on == null) {
                        dot.append_printf("  %s -> %s [style=invis];\n",
                            get_task_id(prev_task), get_task_id(task));
                    }
                    prev_task = task;
                }
            }

            // Dependency arrows (visible, dashed)
            dot.append("\n  // Dependencies\n");
            foreach (var task in diagram.tasks) {
                if (task.depends_on != null && task.depends_on.length > 0 &&
                    task_by_id.has_key(task.depends_on)) {
                    dot.append_printf("  %s -> %s [style=dashed, color=\"%s\", " +
                        "arrowhead=vee, constraint=false];\n",
                        get_task_id(task_by_id.get(task.depends_on)),
                        get_task_id(task),
                        palette.edge_color);
                }
            }

            dot.append("}\n");
            return dot.str;
        }

        private void render_task(StringBuilder dot, GanttTask task, string indent) {
            string task_id = get_task_id(task);
            string fill_color = get_status_color(task.status);

            // Build label: description + duration hint if available
            string label = RenderUtils.escape_label(task.description);
            if (task.duration != null && task.duration.length > 0 &&
                task.duration != task.description) {
                // Only append a short duration (e.g. "3d"), not the full detail string
                string dur = task.duration;
                if (dur.length <= 6) {
                    label = "%s\\n(%s)".printf(label, RenderUtils.escape_label(dur));
                }
            }

            // Milestone: diamond shape
            if (task.status == GanttTaskStatus.MILESTONE) {
                dot.append_printf("%s%s [label=\"%s\", shape=diamond, " +
                    "fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\"];\n",
                    indent, task_id, label, fill_color,
                    ThemeManager.get_active_palette().accent_primary,
                    RenderUtils.contrast_text(fill_color));
            } else {
                dot.append_printf("%s%s [label=\"%s\", fillcolor=\"%s\", fontcolor=\"%s\"];\n",
                    indent, task_id, label, fill_color,
                    RenderUtils.contrast_text(fill_color));
            }

        }

        private string get_task_id(GanttTask task) {
            return "task_%s".printf(RenderUtils.sanitize_id(task.id));
        }

        private string get_status_color(GanttTaskStatus status) {
            var palette = ThemeManager.get_active_palette();
            switch (status) {
                case GanttTaskStatus.DONE:     return palette.success;
                case GanttTaskStatus.ACTIVE:   return palette.accent_secondary;
                case GanttTaskStatus.CRITICAL: return palette.warning;
                case GanttTaskStatus.MILESTONE: return palette.container_fill;
                default:                       return palette.grid;
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

                var element_lines = new Gee.HashMap<string, int>();
                foreach (var task in diagram.tasks) {
                    if (task.source_line > 0)
                        element_lines.set(get_task_id(task), task.source_line);
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
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
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidGantt diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
