namespace GDiagram {
    public class MermaidSequenceRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidSequenceRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidSequenceDiagram diagram) {
            var dot = new StringBuilder();

            // Use DOT for sequence diagrams (left-to-right layout)
            dot.append("digraph G {\n");
            dot.append("  rankdir=LR;\n");
            dot.append("  bgcolor=\"#FAFAFA\";\n");
            dot.append("  node [fontname=\"Sans\", fontsize=11, shape=box, style=\"rounded,filled\", fillcolor=\"#E3F2FD\"];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"#424242\"];\n");
            dot.append("  splines=ortho;\n");
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Create lifeline nodes for actors
            dot.append("  // Actors/Participants\n");
            foreach (var actor in diagram.actors) {
                string safe_id = sanitize_actor_id(actor.id);
                string label = RenderUtils.escape_label(actor.get_display_name());
                string shape = actor.is_participant ? "box" : "box";
                string style = actor.is_participant ? "rounded,filled" : "rounded,filled";

                dot.append_printf("  %s [label=\"%s\", shape=%s, style=\"%s\"];\n",
                    safe_id, label, shape, style);

                // Store region
                regions.add(new ElementRegion(actor.id, actor.source_line, 0, 0, 0, 0));
            }

            dot.append("\n");

            // Enforce actor ordering with invisible edges
            if (diagram.actors.size > 1) {
                dot.append("  // Actor ordering\n");
                for (int i = 0; i < diagram.actors.size - 1; i++) {
                    string from = sanitize_actor_id(diagram.actors[i].id);
                    string to = sanitize_actor_id(diagram.actors[i + 1].id);
                    dot.append_printf("  %s -> %s [style=invis, weight=10];\n", from, to);
                }
                dot.append("\n");
            }

            // Render messages
            if (diagram.messages.size > 0) {
                dot.append("  // Messages\n");
                int msg_num = 1;
                foreach (var message in diagram.messages) {
                    render_message(dot, message, msg_num, diagram.autonumber);
                    msg_num++;
                }
            }

            // Render notes
            if (diagram.notes.size > 0) {
                dot.append("\n  // Notes\n");
                int note_num = 0;
                foreach (var note in diagram.notes) {
                    render_note(dot, note, note_num++);
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_message(StringBuilder dot, MermaidMessage message, int num, bool autonumber) {
            string from_id = sanitize_actor_id(message.from.id);
            string to_id = sanitize_actor_id(message.to.id);

            // Build label
            string label = "";
            if (autonumber) {
                label = "%d. ".printf(num);
            }
            if (message.text != null && message.text.length > 0) {
                label += RenderUtils.escape_label(message.text);
            }

            // Determine arrow style
            string style = get_arrow_style(message.arrow_type);
            string arrowhead = get_arrow_head(message.arrow_type);

            // Build attributes
            var attrs = new Gee.ArrayList<string>();
            if (label.length > 0) {
                attrs.add("label=\"%s\"".printf(label));
            }
            if (style.length > 0) {
                attrs.add(style);
            }
            if (arrowhead.length > 0) {
                attrs.add(arrowhead);
            }

            string attr_str = "";
            if (attrs.size > 0) {
                attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            }

            dot.append_printf("  %s -> %s%s;\n", from_id, to_id, attr_str);
        }

        private void render_note(StringBuilder dot, MermaidNote note, int num) {
            string note_id = "note_%d".printf(num);
            string label = RenderUtils.escape_label(note.text);

            dot.append_printf("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"#FFFFCC\"];\n",
                note_id, label);

            // Connect note to actor(s)
            if (note.over_actor != null) {
                string actor_id = sanitize_actor_id(note.over_actor.id);
                dot.append_printf("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n",
                    note_id, actor_id);
            }

            if (note.to_actor != null) {
                string to_id = sanitize_actor_id(note.to_actor.id);
                dot.append_printf("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n",
                    note_id, to_id);
            }
        }

        private string get_arrow_style(MermaidArrowType arrow_type) {
            switch (arrow_type) {
                case MermaidArrowType.DOTTED_ARROW:
                case MermaidArrowType.DOTTED_LINE:
                case MermaidArrowType.DOTTED_CROSS:
                case MermaidArrowType.DOTTED_OPEN:
                    return "style=dashed";
                default:
                    return "";
            }
        }

        private string get_arrow_head(MermaidArrowType arrow_type) {
            switch (arrow_type) {
                case MermaidArrowType.SOLID_LINE:
                case MermaidArrowType.DOTTED_LINE:
                    return "arrowhead=none";
                case MermaidArrowType.SOLID_CROSS:
                case MermaidArrowType.DOTTED_CROSS:
                    return "arrowhead=tee";
                case MermaidArrowType.SOLID_OPEN:
                case MermaidArrowType.DOTTED_OPEN:
                    return "arrowhead=empty";
                case MermaidArrowType.SOLID_ARROW:
                case MermaidArrowType.DOTTED_ARROW:
                default:
                    return "arrowhead=vee";
            }
        }

        private string sanitize_actor_id(string id) {
            return RenderUtils.sanitize_id(id);
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidSequenceDiagram diagram) {
            string dot_source = generate_dot(diagram);

            // Parse DOT into graph
            var graph = Gvc.Graph.read_string(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph");
                return null;
            }

            // Layout
            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout graph with engine: %s", layout_engine);
                return null;
            }

            // Render to SVG
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
        public Cairo.ImageSurface? render_to_surface(MermaidSequenceDiagram diagram) {
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
        public bool export_to_png(MermaidSequenceDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidSequenceDiagram diagram, string filename) {
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

        public bool export_to_pdf(MermaidSequenceDiagram diagram, string filename) {
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
