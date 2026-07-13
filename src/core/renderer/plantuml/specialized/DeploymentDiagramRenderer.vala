namespace GDiagram {
    public class DeploymentDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public DeploymentDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(DeploymentDiagram diagram) {
            var sb = new StringBuilder();
            var palette = ThemeManager.get_active_palette();
            sb.append("digraph G {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  compound=true;\n");
            sb.append("  fontname=\"Sans\";\n");
            sb.append("  node [style=\"filled\", fontname=\"Sans\", fontsize=11];\n");
            sb.append("  edge [fontname=\"Sans\", fontsize=10, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));

            // Title
            if (diagram.title != null) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=16;\n");
                sb.append("  fontcolor=\"%s\";\n".printf(palette.node_text));
            }

            // Collect container node IDs — containers render as clusters (not nodes),
            // so connections must use an anchor node as the edge endpoint.
            var container_ids = new Gee.HashSet<string>();
            collect_container_node_ids(diagram.nodes, container_ids);

            // Render nodes
            sb.append("\n  // Nodes\n");
            foreach (var node in diagram.nodes) {
                generate_deployment_node_dot(sb, node, diagram, 1);
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "BackgroundColor") ?? ThemeManager.get_active_palette().accent_secondary);
                string note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_color));

                foreach (var note in diagram.notes) {
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\"];\n".printf(
                        note.id, RenderUtils.escape_label(note.text), note_color, note_font));

                    if (note.attached_to != null) {
                        var target = diagram.find_node(note.attached_to);
                        if (target != null) {
                            string target_id = target.get_dot_id();
                            if (container_ids.contains(target_id)) {
                                target_id = target_id + "_anchor";
                            }
                            sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                note.id, target_id));
                        }
                    }
                }
            }

            // Render connections
            sb.append("\n  // Connections\n");
            foreach (var conn in diagram.connections) {
                var from = diagram.find_node(conn.from_id);
                var to = diagram.find_node(conn.to_id);

                if (from == null || to == null) continue;

                string from_id = from.get_dot_id();
                string to_id = to.get_dot_id();

                // Container nodes render as clusters; use anchor nodes for edge endpoints
                if (container_ids.contains(from_id)) {
                    from_id = from_id + "_anchor";
                }
                if (container_ids.contains(to_id)) {
                    to_id = to_id + "_anchor";
                }
                string style = conn.is_dashed ? "dashed" : "solid";
                string arrowhead = "vee";
                string arrowtail = "none";

                switch (conn.connection_type) {
                    case DeploymentConnectionType.ASSOCIATION:
                        arrowhead = "none";
                        break;
                    case DeploymentConnectionType.DEPENDENCY:
                        style = "dashed";
                        break;
                    case DeploymentConnectionType.DIRECTED:
                        arrowhead = "vee";
                        break;
                    case DeploymentConnectionType.BIDIRECTIONAL:
                        arrowhead = "vee";
                        arrowtail = "vee";
                        break;
                }

                // Build label with protocol if present
                var label_builder = new StringBuilder();
                if (conn.label != null && conn.label.length > 0) {
                    label_builder.append(RenderUtils.escape_label(conn.label));
                }
                if (conn.protocol != null && conn.protocol.length > 0) {
                    if (label_builder.len > 0) {
                        label_builder.append("\\n");
                    }
                    label_builder.append("<<");
                    label_builder.append(conn.protocol);
                    label_builder.append(">>");
                }

                if (label_builder.len > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s, arrowhead=%s, arrowtail=%s, dir=both];\n".printf(
                        from_id, to_id, label_builder.str, style, arrowhead, arrowtail));
                } else {
                    sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=%s, dir=both];\n".printf(
                        from_id, to_id, style, arrowhead, arrowtail));
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        private string get_deployment_node_shape(DeploymentNodeType node_type) {
            switch (node_type) {
                case DeploymentNodeType.NODE:
                    return "box3d";
                case DeploymentNodeType.DEVICE:
                    return "component";
                case DeploymentNodeType.ARTIFACT:
                    return "note";
                case DeploymentNodeType.COMPONENT:
                    return "component";
                case DeploymentNodeType.DATABASE:
                    return "cylinder";
                case DeploymentNodeType.CLOUD:
                    return "ellipse";
                case DeploymentNodeType.RECTANGLE:
                    return "box";
                case DeploymentNodeType.FOLDER:
                    return "folder";
                case DeploymentNodeType.FRAME:
                    return "box";
                case DeploymentNodeType.STORAGE:
                    return "cylinder";
                case DeploymentNodeType.QUEUE:
                    return "cds";
                case DeploymentNodeType.STACK:
                    return "box3d";
                case DeploymentNodeType.FILE:
                    return "note";
                case DeploymentNodeType.CARD:
                    return "box";
                case DeploymentNodeType.AGENT:
                    return "house";
                default:
                    return "box";
            }
        }

        private string get_deployment_node_color(DeploymentNodeType node_type, DeploymentDiagram diagram) {
            var palette = ThemeManager.get_active_palette();
            switch (node_type) {
                case DeploymentNodeType.NODE:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("node", "BackgroundColor") ?? palette.container_fill);
                case DeploymentNodeType.DEVICE:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("device", "BackgroundColor") ?? palette.system_fill);
                case DeploymentNodeType.ARTIFACT:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("artifact", "BackgroundColor") ?? palette.accent_secondary);
                case DeploymentNodeType.COMPONENT:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("component", "BackgroundColor") ?? palette.component_fill);
                case DeploymentNodeType.DATABASE:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("database", "BackgroundColor") ?? palette.database_fill);
                case DeploymentNodeType.CLOUD:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("cloud", "BackgroundColor") ?? palette.external_fill);
                case DeploymentNodeType.FOLDER:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("folder", "BackgroundColor") ?? palette.accent_secondary);
                case DeploymentNodeType.FRAME:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("frame", "BackgroundColor") ?? palette.grid);
                case DeploymentNodeType.STORAGE:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("storage", "BackgroundColor") ?? palette.warning);
                case DeploymentNodeType.QUEUE:
                    return RenderUtils.sanitize_color(diagram.skin_params.get_element_property("queue", "BackgroundColor") ?? palette.success);
                default:
                    return palette.node_fill;
            }
        }

        private void generate_deployment_node_dot(StringBuilder sb, DeploymentNode node, DeploymentDiagram diagram, int indent) {
            string indent_str = string.nfill(indent * 2, ' ');
            string node_id = node.get_dot_id();
            string label = node.get_display_label();

            if (node.is_container && node.children.size > 0) {
                // Create a subgraph (cluster) for container nodes
                sb.append("%ssubgraph cluster_%s {\n".printf(indent_str, node_id));
                sb.append("%s  label=\"%s\";\n".printf(indent_str, RenderUtils.escape_label(label)));

                // Add stereotype if present
                if (node.stereotype != null) {
                    sb.append("%s  labelloc=\"t\";\n".printf(indent_str));
                }

                string fill_color = node.color != null ? RenderUtils.sanitize_color(node.color) : get_deployment_node_color(node.node_type, diagram);
                var palette = ThemeManager.get_active_palette();
                sb.append("%s  style=filled;\n".printf(indent_str));
                sb.append("%s  fillcolor=\"%s\";\n".printf(indent_str, fill_color));
                sb.append("%s  color=\"%s\";\n".printf(indent_str, palette.node_border));

                // Add children
                foreach (var child in node.children) {
                    generate_deployment_node_dot(sb, child, diagram, indent + 1);
                }

                sb.append("%s}\n".printf(indent_str));
                // Invisible anchor node so outer connections have a real node to connect to
                sb.append("  %s [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(node_id + "_anchor"));
            } else {
                // Regular node
                string shape = get_deployment_node_shape(node.node_type);
                string fill_color = node.color != null ? RenderUtils.sanitize_color(node.color) : get_deployment_node_color(node.node_type, diagram);

                // Build label with stereotype
                var label_builder = new StringBuilder();
                if (node.stereotype != null) {
                    label_builder.append("<<");
                    label_builder.append(node.stereotype);
                    label_builder.append(">>\\n");
                }
                label_builder.append(RenderUtils.escape_label(label));

                var palette = ThemeManager.get_active_palette();
                sb.append("%s%s [label=\"%s\", shape=%s, style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\"];\n".printf(
                    indent_str, node_id, label_builder.str, shape, fill_color, palette.node_border, RenderUtils.contrast_text(fill_color)));
            }
        }

        private void collect_container_node_ids(Gee.ArrayList<DeploymentNode> nodes, Gee.HashSet<string> container_ids) {
            foreach (var node in nodes) {
                if (node.is_container && node.children.size > 0) {
                    container_ids.add(node.get_dot_id());
                    collect_container_node_ids(node.children, container_ids);
                }
            }
        }

        private void add_deployment_node_lines(Gee.ArrayList<DeploymentNode> nodes, Gee.HashMap<string, int> element_lines) {
            foreach (var node in nodes) {
                if (node.source_line > 0) {
                    element_lines.set(node.id, node.source_line);
                    element_lines.set(node.get_dot_id(), node.source_line);
                    if (node.alias != null) {
                        element_lines.set(node.alias, node.source_line);
                    }
                }
                // Recursively add children
                add_deployment_node_lines(node.children, element_lines);
            }
        }

        public uint8[]? render_to_svg(DeploymentDiagram diagram) {
            string dot = generate_dot(diagram);
            return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "deployment");
        }

        public Cairo.ImageSurface? render_to_surface(DeploymentDiagram diagram) {
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

                // Build element lines map for click-to-source
                var element_lines = new Gee.HashMap<string, int>();
                add_deployment_node_lines(diagram.nodes, element_lines);
                foreach (var note in diagram.notes) {
                    if (note.source_line > 0) {
                        element_lines.set(note.id, note.source_line);
                    }
                }
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, (int)width, (int)height);

                return surface;
            } catch (Error e) {
                warning("Failed to create surface from SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(DeploymentDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(DeploymentDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(DeploymentDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
