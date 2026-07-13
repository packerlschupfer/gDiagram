namespace GDiagram {
    public class MermaidSequenceRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidSequenceRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidSequenceDiagram diagram) {
            var dot = new StringBuilder();
            int n_msgs = diagram.messages.size;

            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  compound=true;\n");
            dot.append("  node [fontname=\"Sans\", fontsize=10];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("\n");

            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n",
                    RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // ── Actor header row ────────────────────────────────────────────
            if (diagram.actors.size > 0) {
                dot.append("  // Actor header nodes\n");
                dot.append("  {rank=same;");
                foreach (var actor in diagram.actors) {
                    dot.append_printf(" %s;", actor_id(actor.id));
                }
                dot.append("}\n");

                foreach (var actor in diagram.actors) {
                    string aid = actor_id(actor.id);
                    string shape = actor.is_participant ? "box" : "underline";
                    dot.append_printf(
                        "  %s [label=\"%s\", shape=%s, style=\"rounded,filled\", " +
                        "fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", penwidth=1.5];\n",
                        aid, RenderUtils.escape_label(actor.get_display_name()), shape,
                        palette.container_fill, palette.container_border, palette.node_text
                    );
                    // (Regions populated with real bounds in render_to_surface)
                }
                dot.append("\n");

                // Enforce left-to-right actor ordering
                if (diagram.actors.size > 1) {
                    dot.append("  // Actor ordering\n  ");
                    for (int i = 0; i < diagram.actors.size; i++) {
                        if (i > 0) dot.append(" -> ");
                        dot.append(actor_id(diagram.actors[i].id));
                    }
                    dot.append(" [style=invis, weight=10];\n\n");
                }
            }

            // ── Lifeline slot rows (one per message) ────────────────────────
            // Each message gets its own "row" of invisible slot nodes (one per actor).
            // Messages are rendered as constraint=false edges between matching slots.
            // This preserves message ordering without confusing rank assignments.
            if (n_msgs > 0) {
                dot.append("  // Lifeline slot nodes\n");
                for (int i = 0; i < n_msgs; i++) {
                    // One invisible node per actor at this time step
                    foreach (var actor in diagram.actors) {
                        dot.append_printf(
                            "  %s [style=invis, width=0.01, height=0.01, label=\"\"];\n",
                            slot_id(actor.id, i)
                        );
                    }
                    // All slots at this step share the same rank
                    dot.append("  {rank=same;");
                    foreach (var actor in diagram.actors) {
                        dot.append_printf(" %s;", slot_id(actor.id, i));
                    }
                    dot.append("}\n");
                }
                dot.append("\n");

                // Vertical lifeline chains: actor_header -> slot_0 -> slot_1 -> ...
                // These are the "dashed lifeline" lines in a sequence diagram.
                dot.append("  // Vertical lifelines\n");
                foreach (var actor in diagram.actors) {
                    string aid = actor_id(actor.id);
                    dot.append_printf("  %s -> %s", aid, slot_id(actor.id, 0));
                    dot.append_printf(" [style=dashed, arrowhead=none, color=\"%s\", weight=5];\n", palette.edge_color);
                    for (int i = 0; i < n_msgs - 1; i++) {
                        dot.append_printf(
                            "  %s -> %s [style=dashed, arrowhead=none, color=\"%s\", weight=5];\n",
                            slot_id(actor.id, i), slot_id(actor.id, i + 1), palette.edge_color
                        );
                    }
                }
                dot.append("\n");

                // ── Loop/alt/par frame clusters ──────────────────────────────
                // Each loop claims the slot nodes that fall within its message range.
                int cluster_num = 0;
                foreach (var loop in diagram.loops) {
                    int start = loop.msg_start;
                    int end = loop.msg_end;
                    if (start < 0 || start > end || end >= n_msgs) continue;

                    string frame_label = get_loop_label(loop);
                    string frame_color = get_loop_color(loop.loop_type);

                    dot.append_printf(
                        "  subgraph cluster_loop_%d {\n", cluster_num++
                    );
                    dot.append_printf(
                        "    label=\"%s\";\n", RenderUtils.escape_label(frame_label)
                    );
                    dot.append_printf(
                        "    style=dashed;\n    color=\"%s\";\n    fontcolor=\"%s\";\n" +
                        "    fontsize=9;\n    fontname=\"Sans Bold\";\n",
                        frame_color, frame_color
                    );
                    for (int i = start; i <= end; i++) {
                        foreach (var actor in diagram.actors) {
                            dot.append_printf("    %s;\n", slot_id(actor.id, i));
                        }
                    }
                    dot.append("  }\n\n");
                }

                // ── Message edges ─────────────────────────────────────────────
                dot.append("  // Messages\n");
                for (int i = 0; i < n_msgs; i++) {
                    var msg = diagram.messages.get(i);
                    render_message_edge(dot, msg, i, diagram.autonumber, i + 1);
                }
            }

            // ── Notes (attached as side nodes) ───────────────────────────────
            if (diagram.notes.size > 0) {
                dot.append("\n  // Notes\n");
                for (int i = 0; i < diagram.notes.size; i++) {
                    render_note(dot, diagram.notes.get(i), i);
                }
            }

            dot.append("}\n");
            return dot.str;
        }

        private void render_message_edge(
            StringBuilder dot,
            MermaidMessage msg,
            int row,
            bool autonumber,
            int num
        ) {
            string from_slot = slot_id(msg.from.id, row);
            string to_slot   = slot_id(msg.to.id,   row);

            // Build label
            var label = new StringBuilder();
            if (autonumber) label.append_printf("%d. ", num);
            if (msg.text != null && msg.text.length > 0) {
                label.append(RenderUtils.escape_label(msg.text));
            }

            string style     = get_arrow_style(msg.arrow_type);
            string arrowhead = get_arrow_head(msg.arrow_type);

            var attrs = new Gee.ArrayList<string>();
            if (label.len > 0) attrs.add("label=\"%s\"".printf(label.str));
            if (style.length > 0) attrs.add(style);
            if (arrowhead.length > 0) attrs.add(arrowhead);
            attrs.add("constraint=false");
            attrs.add("color=\"%s\"".printf(ThemeManager.get_active_palette().edge_color));

            string attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            dot.append_printf("  %s -> %s%s;\n", from_slot, to_slot, attr_str);
        }

        private void render_note(StringBuilder dot, MermaidNote note, int num) {
            string note_id = "note_%d".printf(num);
            string label = RenderUtils.escape_label(note.text);

            var palette = ThemeManager.get_active_palette();
            dot.append_printf(
                "  %s [label=\"%s\", shape=note, style=filled, " +
                "fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\"];\n",
                note_id, label, palette.accent_secondary, palette.node_border,
                RenderUtils.contrast_text(palette.accent_secondary)
            );

            // Connect to the actor it's associated with
            var target = note.over_actor ?? note.from_actor;
            if (target != null) {
                dot.append_printf(
                    "  %s -> %s [style=dashed, arrowhead=none, " +
                    "constraint=false, color=\"%s\"];\n",
                    note_id, actor_id(target.id), palette.edge_color
                );
            }
        }

        private string get_loop_label(MermaidLoop loop) {
            string type_str;
            switch (loop.loop_type) {
                case MermaidLoopType.ALT:      type_str = "alt";      break;
                case MermaidLoopType.OPT:      type_str = "opt";      break;
                case MermaidLoopType.PAR:      type_str = "par";      break;
                case MermaidLoopType.CRITICAL: type_str = "critical"; break;
                case MermaidLoopType.BREAK:    type_str = "break";    break;
                case MermaidLoopType.RECT:     type_str = "rect";     break;
                default:                       type_str = "loop";     break;
            }
            if (loop.condition != null && loop.condition.length > 0) {
                return "%s [%s]".printf(type_str, loop.condition);
            }
            return type_str;
        }

        private string get_loop_color(MermaidLoopType type) {
            var palette = ThemeManager.get_active_palette();
            switch (type) {
                case MermaidLoopType.ALT:      return palette.accent_primary;
                case MermaidLoopType.OPT:      return palette.success;
                case MermaidLoopType.PAR:      return palette.person_fill;
                case MermaidLoopType.CRITICAL: return palette.warning;
                case MermaidLoopType.BREAK:    return palette.accent_secondary;
                case MermaidLoopType.RECT:     return palette.edge_color;
                default:                       return palette.edge_color;
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
                default:
                    return "arrowhead=vee";
            }
        }

        // Stable Graphviz node ID for an actor
        private string actor_id(string id) {
            return "actor_" + RenderUtils.sanitize_id(id);
        }

        // Stable Graphviz node ID for a lifeline slot (actor x time-step)
        private string slot_id(string actor, int step) {
            return "s_%s_%d".printf(RenderUtils.sanitize_id(actor), step);
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidSequenceDiagram diagram) {
            string dot_source = generate_dot(diagram);

            var graph = Gvc.Graph.read_string(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT graph for Mermaid sequence");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout Mermaid sequence graph");
                return null;
            }

            uint8[] svg_data;
            ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);
            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render Mermaid sequence graph");
                return null;
            }

            return svg_data;
        }

        // Render to Cairo surface
        public Cairo.ImageSurface? render_to_surface(MermaidSequenceDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return null;

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(
                    stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.ImageSurface(
                    Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0, y = 0, width = width, height = height
                };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                foreach (var actor in diagram.actors) {
                    if (actor.source_line > 0)
                        element_lines.set("actor_" + RenderUtils.sanitize_id(actor.id), actor.source_line);
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render Mermaid sequence SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidSequenceDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) return false;
            return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidSequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidSequenceDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
