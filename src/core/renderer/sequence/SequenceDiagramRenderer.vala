namespace GDiagram {
    public class SequenceDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public SequenceDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(SequenceDiagram diagram) {
            var sb = new StringBuilder();

            sb.append("digraph sequence {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  node [fontname=\"Sans\"];\n");
            sb.append("  edge [fontsize=10, fontname=\"Sans\"];\n");
            sb.append("  splines=line;\n");
            sb.append("  ranksep=0.5;\n");
            sb.append("\n");

            // Create participant nodes at top
            sb.append("  // Participants (top)\n");
            sb.append("  { rank=same;\n");
            foreach (var p in diagram.participants) {
                string shape = get_participant_shape(p.participant_type);
                string id = RenderUtils.escape_id(p.get_id()) + "_top";
                string color = normalize_color(p.color) ?? "#FEFECE";

                // Use HTML-like label for multi-line with visual boxes
                if (p.display_label != null && p.display_label.contains("║SEPARATOR║")) {
                    string html_label = create_html_table_label(p.display_label, color);
                    sb.append("    %s [label=<%s>, shape=plaintext];\n".printf(id, html_label));
                } else {
                    string label = RenderUtils.escape_label(p.display_label ?? p.name);
                    sb.append("    %s [label=\"%s\", shape=%s, style=filled, fillcolor=\"%s\"];\n".printf(id, label, shape, color));
                }
            }
            sb.append("  }\n\n");

            // Create invisible edges to maintain participant order at top
            if (diagram.participants.size > 1) {
                sb.append("  // Top ordering\n");
                sb.append("  edge [style=invis, weight=10];\n");
                for (int i = 0; i < diagram.participants.size - 1; i++) {
                    string id1 = RenderUtils.escape_id(diagram.participants[i].get_id()) + "_top";
                    string id2 = RenderUtils.escape_id(diagram.participants[i + 1].get_id()) + "_top";
                    sb.append("  %s -> %s;\n".printf(id1, id2));
                }
                sb.append("\n");
            }

            // Create lifeline nodes for each message - only for involved participants
            int msg_count = diagram.messages.size;
            for (int msg_idx = 0; msg_idx < msg_count; msg_idx++) {
                var msg = diagram.messages[msg_idx];
                sb.append("  // Lifeline nodes for message %d\n".printf(msg_idx));
                sb.append("  { rank=same;\n");

                // Only create points for participants involved in this message (invisible)
                foreach (var p in diagram.participants) {
                    if (p == msg.from || p == msg.to) {
                        string id = RenderUtils.escape_id(p.get_id()) + "_m%d".printf(msg_idx);
                        sb.append("    %s [label=\"\", shape=point, width=0.01, height=0.01, style=invis];\n".printf(id));
                    }
                }
                sb.append("  }\n");

                // Maintain horizontal ordering between involved participants
                var involved = new Gee.ArrayList<Participant>();
                foreach (var p in diagram.participants) {
                    if (p == msg.from || p == msg.to) {
                        involved.add(p);
                    }
                }
                if (involved.size > 1) {
                    sb.append("  edge [style=invis, weight=10];\n");
                    for (int i = 0; i < involved.size - 1; i++) {
                        string id1 = RenderUtils.escape_id(involved[i].get_id()) + "_m%d".printf(msg_idx);
                        string id2 = RenderUtils.escape_id(involved[i + 1].get_id()) + "_m%d".printf(msg_idx);
                        sb.append("  %s -> %s;\n".printf(id1, id2));
                    }
                }
                sb.append("\n");
            }

            // Create participant nodes at bottom
            sb.append("  // Participants (bottom)\n");
            sb.append("  { rank=same;\n");
            foreach (var p in diagram.participants) {
                string shape = get_participant_shape(p.participant_type);
                string id = RenderUtils.escape_id(p.get_id()) + "_bottom";
                string color = normalize_color(p.color) ?? "#FEFECE";

                // Use HTML-like label for multi-line with visual boxes
                if (p.display_label != null && p.display_label.contains("║SEPARATOR║")) {
                    string html_label = create_html_table_label(p.display_label, color);
                    sb.append("    %s [label=<%s>, shape=plaintext];\n".printf(id, html_label));
                } else {
                    string label = RenderUtils.escape_label(p.display_label ?? p.name);
                    sb.append("    %s [label=\"%s\", shape=%s, style=filled, fillcolor=\"%s\"];\n".printf(id, label, shape, color));
                }
            }
            sb.append("  }\n\n");

            // Create invisible edges to maintain participant order at bottom
            if (diagram.participants.size > 1) {
                sb.append("  // Bottom ordering\n");
                sb.append("  edge [style=invis, weight=10];\n");
                for (int i = 0; i < diagram.participants.size - 1; i++) {
                    string id1 = RenderUtils.escape_id(diagram.participants[i].get_id()) + "_bottom";
                    string id2 = RenderUtils.escape_id(diagram.participants[i + 1].get_id()) + "_bottom";
                    sb.append("  %s -> %s;\n".printf(id1, id2));
                }
                sb.append("\n");
            }

            // Create vertical lifelines - only connect points that exist
            sb.append("  // Lifelines\n");
            sb.append("  edge [style=dashed, arrowhead=none, color=\"#CCCCCC\", penwidth=1.5, weight=100];\n");
            foreach (var p in diagram.participants) {
                string base_id = RenderUtils.escape_id(p.get_id());

                // Find which message indices this participant is involved in
                var involved_msgs = new Gee.ArrayList<int>();
                for (int i = 0; i < msg_count; i++) {
                    if (diagram.messages[i].from == p || diagram.messages[i].to == p) {
                        involved_msgs.add(i);
                    }
                }

                if (involved_msgs.size > 0) {
                    // Connect top to first involvement
                    sb.append("  %s_top -> %s_m%d;\n".printf(base_id, base_id, involved_msgs[0]));

                    // Connect consecutive involvements
                    for (int i = 0; i < involved_msgs.size - 1; i++) {
                        sb.append("  %s_m%d -> %s_m%d;\n".printf(
                            base_id, involved_msgs[i], base_id, involved_msgs[i + 1]
                        ));
                    }

                    // Connect last involvement to bottom
                    sb.append("  %s_m%d -> %s_bottom;\n".printf(base_id, involved_msgs[involved_msgs.size - 1], base_id));
                } else {
                    // No messages - connect top directly to bottom
                    sb.append("  %s_top -> %s_bottom;\n".printf(base_id, base_id));
                }
            }
            sb.append("\n");

            // Create message edges
            sb.append("  // Messages\n");
            sb.append("  edge [constraint=false, weight=0, fontsize=11, color=black];\n");
            for (int msg_idx = 0; msg_idx < msg_count; msg_idx++) {
                var msg = diagram.messages[msg_idx];
                string from_id = RenderUtils.escape_id(msg.from.get_id()) + "_m%d".printf(msg_idx);
                string to_id = RenderUtils.escape_id(msg.to.get_id()) + "_m%d".printf(msg_idx);
                string label = msg.label != null ? RenderUtils.escape_label(msg.label) : "";
                string style = get_arrow_style(msg.style);
                string arrow = get_arrowhead(msg.style, msg.direction);

                if (msg.direction == ArrowDirection.LEFT) {
                    sb.append("  %s -> %s [label=\"  %s  \", style=%s, arrowhead=%s, dir=back, labeldistance=2.0];\n".printf(
                        to_id, from_id, label, style, arrow
                    ));
                } else {
                    sb.append("  %s -> %s [label=\"  %s  \", style=%s, arrowhead=%s, labeldistance=2.0];\n".printf(
                        from_id, to_id, label, style, arrow
                    ));
                }
            }

            // Create note nodes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                int note_num = 0;
                foreach (var note in diagram.notes) {
                    string note_id = "note%d".printf(note_num);
                    string note_text = RenderUtils.escape_label(note.text);
                    sb.append("  %s [shape=note, style=filled, fillcolor=\"#FFFFCC\", label=\"%s\"];\n".printf(
                        note_id, note_text
                    ));

                    // Connect note to participant if specified
                    if (note.participant != null) {
                        string part_id = RenderUtils.escape_id(note.participant.get_id());
                        sb.append("  %s -> %s [style=dotted, arrowhead=none, constraint=false];\n".printf(
                            note_id, part_id
                        ));
                    }
                    note_num++;
                }
            }

            // Render grouping frames as clusters
            if (diagram.frames.size > 0) {
                sb.append("\n  // Grouping Frames\n");
                foreach (var frame in diagram.frames) {
                    render_frame_cluster(sb, frame, diagram);
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        // Get appropriate shape for each participant type
        // Note: Graphviz has limitations when rendering too many different shapes in one rank.
        // Diagrams with 2-7 participants work fine. Using all 8 types together may cause
        // rendering issues due to Graphviz library bugs (not our code).
        // Shapes chosen to be visually distinct and stable.
        private string? format_color(string? color) {
            if (color == null) return null;

            // If starts with # and followed by only hex digits, it's a hex color - keep it
            if (color.has_prefix("#") && color.length >= 4) {
                bool is_hex = true;
                for (int i = 1; i < color.length; i++) {
                    char c = color[i];
                    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                        is_hex = false;
                        break;
                    }
                }
                if (is_hex) return color;  // Valid hex code, keep #
            }

            // Otherwise it's a color name with # prefix - remove the #
            if (color.has_prefix("#")) {
                return color.substring(1);  // "red" instead of "#red"
            }

            return color;
        }

        private string get_participant_shape(ParticipantType ptype) {
            switch (ptype) {
                case ParticipantType.ACTOR:
                    // Person/actor - use octagon as approximation (has more sides, person-like)
                    return "octagon";
                case ParticipantType.BOUNDARY:
                    // Boundary/interface - hexagon (boundary shape)
                    return "hexagon";
                case ParticipantType.CONTROL:
                    // Controller - circle (circular control)
                    return "circle";
                case ParticipantType.ENTITY:
                    // Data entity - ellipse (rounded data)
                    return "ellipse";
                case ParticipantType.DATABASE:
                    // Database - cylinder (standard DB symbol)
                    return "cylinder";
                case ParticipantType.COLLECTIONS:
                    // Collection/set - folder (multiple items)
                    return "folder";
                case ParticipantType.QUEUE:
                    // Queue - trapezium (queue/FIFO representation)
                    return "trapezium";
                default:
                    // Standard participant - box
                    return "box";
            }
        }

        private string get_arrow_style(ArrowStyle style) {
            switch (style) {
                case ArrowStyle.DOTTED:
                case ArrowStyle.DOTTED_OPEN:
                    return "dashed";
                default:
                    return "solid";
            }
        }

        private string get_arrowhead(ArrowStyle style, ArrowDirection dir) {
            if (dir == ArrowDirection.BIDIRECTIONAL) {
                return "normal";
            }
            switch (style) {
                case ArrowStyle.SOLID_OPEN:
                case ArrowStyle.DOTTED_OPEN:
                    return "open";
                default:
                    return "normal";
            }
        }

        private string? normalize_color(string? color) {
            if (color == null) return null;

            // If color starts with #, check if it's hex or named
            if (color.has_prefix("#")) {
                string value = color.substring(1);
                // Check if it's a hex color (3 or 6 hex digits)
                if (value.length == 3 || value.length == 6) {
                    bool is_hex = true;
                    foreach (char c in value.to_utf8()) {
                        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                            is_hex = false;
                            break;
                        }
                    }
                    if (is_hex) {
                        return color;  // Keep #FF0000 or #F00
                    }
                }
                // Named color with #, strip the #
                return value;  // Return 'red' not '#red'
            }
            return color;
        }

        private string create_html_table_label(string label, string bgcolor) {
            // Split label by separator marker
            string[] parts = label.split("║SEPARATOR║");

            var sb = new StringBuilder();
            // BORDER="0" to avoid thick outer border, CELLBORDER="1" for cell divisions
            sb.append("<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"6\">");

            foreach (string part in parts) {
                string trimmed = part.strip().replace("\\n", "<BR/>");
                if (trimmed.length > 0) {
                    sb.append("<TR><TD BGCOLOR=\"");
                    sb.append(bgcolor);
                    sb.append("\" ALIGN=\"CENTER\">");
                    sb.append(trimmed);
                    sb.append("</TD></TR>");
                }
            }

            sb.append("</TABLE>");
            return sb.str;
        }

        private void render_frame_cluster(StringBuilder sb, SequenceFrame frame, SequenceDiagram diagram) {
            string frame_id = frame.id;
            string type_label = frame.get_type_label();
            string fill_color = get_frame_color(frame.frame_type);

            // Build the cluster label with type and condition/label
            string cluster_label = type_label;
            if (frame.condition != null && frame.condition.length > 0) {
                cluster_label = "%s [%s]".printf(type_label, RenderUtils.escape_label(frame.condition));
            } else if (frame.label != null && frame.label.length > 0) {
                cluster_label = "%s %s".printf(type_label, RenderUtils.escape_label(frame.label));
            }

            // Create cluster subgraph
            sb.append("  subgraph cluster_%s {\n".printf(frame_id));
            sb.append("    label=\"%s\";\n".printf(cluster_label));
            sb.append("    labeljust=l;\n");  // Left-justify label
            sb.append("    style=filled;\n");
            sb.append("    fillcolor=\"%s\";\n".printf(fill_color));
            sb.append("    color=\"#888888\";\n");  // Border color
            sb.append("    fontname=\"Sans Bold\";\n");
            sb.append("    fontsize=10;\n");

            // Find messages that belong to this frame (between start_order and end_order)
            int msg_idx = 0;
            foreach (var msg in diagram.messages) {
                // Check if this message is within the frame's range
                // We use the event order to determine containment
                bool in_frame = is_message_in_frame(diagram, msg, frame);
                if (in_frame) {
                    sb.append("    msg%d;\n".printf(msg_idx));
                }
                msg_idx++;
            }

            // Render else sections within alt frames
            foreach (var section in frame.sections) {
                render_else_section(sb, section, diagram);
            }

            sb.append("  }\n");
        }

        private void render_else_section(StringBuilder sb, SequenceFrame section, SequenceDiagram diagram) {
            string section_label = "else";
            if (section.condition != null && section.condition.length > 0) {
                section_label = "else [%s]".printf(RenderUtils.escape_label(section.condition));
            }

            // Create a sub-cluster for the else section
            sb.append("    subgraph cluster_%s {\n".printf(section.id));
            sb.append("      label=\"%s\";\n".printf(section_label));
            sb.append("      labeljust=l;\n");
            sb.append("      style=filled;\n");
            sb.append("      fillcolor=\"#F8F8F8\";\n");
            sb.append("      color=\"#AAAAAA\";\n");
            sb.append("      fontname=\"Sans\";\n");
            sb.append("      fontsize=9;\n");
            sb.append("    }\n");
        }

        private bool is_message_in_frame(SequenceDiagram diagram, Message msg, SequenceFrame frame) {
            // Find the order of this message in the events list
            foreach (var evt in diagram.events) {
                if (evt is MessageEvent) {
                    var msg_evt = (MessageEvent) evt;
                    if (msg_evt.message == msg) {
                        return msg_evt.order > frame.start_order && msg_evt.order < frame.end_order;
                    }
                }
            }
            return false;
        }

        private string get_frame_color(SequenceFrameType frame_type) {
            switch (frame_type) {
                case SequenceFrameType.ALT:
                    return "#FFFACD";  // Light yellow
                case SequenceFrameType.OPT:
                    return "#E6F3FF";  // Light blue
                case SequenceFrameType.LOOP:
                    return "#E8F5E9";  // Light green
                case SequenceFrameType.PAR:
                    return "#FFF3E0";  // Light orange
                case SequenceFrameType.BREAK:
                    return "#FFEBEE";  // Light red
                case SequenceFrameType.CRITICAL:
                    return "#FCE4EC";  // Light pink
                case SequenceFrameType.REF:
                    return "#F3E5F5";  // Light purple
                default:
                    return "#F5F5F5";  // Light gray for group
            }
        }

        public uint8[]? render_to_svg(SequenceDiagram diagram) {
            string dot = generate_dot(diagram);

            // Parse DOT into graph
            var graph = Gvc.Graph.read_string(dot);
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

        public Cairo.ImageSurface? render_to_surface(SequenceDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                // Load SVG with librsvg
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                // Build element line number map from participants
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var participant in diagram.participants) {
                    if (participant.source_line > 0) {
                        element_lines.set(participant.name, participant.source_line);
                        if (participant.alias != null) {
                            element_lines.set(participant.alias, participant.source_line);
                        }
                    }
                }

                // Parse SVG regions for click-to-source navigation (with pixel scaling)
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, width, height);

                // Create Cairo surface
                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                // White background
                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                // Render SVG
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

        public bool export_to_png(SequenceDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(SequenceDiagram diagram, string filename) {
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

        public bool export_to_pdf(SequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                // Load SVG
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                // Create PDF surface
                var surface = new Cairo.PdfSurface(filename, width, height);
                var cr = new Cairo.Context(surface);

                // White background
                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                // Render SVG to PDF
                var viewport = Rsvg.Rectangle() {
                    x = 0,
                    y = 0,
                    width = width,
                    height = height
                };
                handle.render_document(cr, viewport);

                // Finish the PDF
                surface.finish();

                return surface.status() == Cairo.Status.SUCCESS;
            } catch (Error e) {
                warning("Failed to export PDF: %s", e.message);
                return false;
            }
        }
    }
}
