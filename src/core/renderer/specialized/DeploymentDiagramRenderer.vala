namespace GDiagram {
    public class DeploymentDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public DeploymentDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(DeploymentDiagram diagram) {
            var sb = new StringBuilder();
            sb.append("digraph G {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  compound=true;\n");
            sb.append("  fontname=\"Sans\";\n");
            sb.append("  node [fontname=\"Sans\", fontsize=11];\n");
            sb.append("  edge [fontname=\"Sans\", fontsize=10];\n");

            // Title
            if (diagram.title != null) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=16;\n");
            }

            // Render nodes
            sb.append("\n  // Nodes\n");
            foreach (var node in diagram.nodes) {
                generate_deployment_node_dot(sb, node, diagram, 1);
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";

                foreach (var note in diagram.notes) {
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"];\n".printf(
                        note.id, RenderUtils.escape_label(note.text), note_color));

                    if (note.attached_to != null) {
                        var target = diagram.find_node(note.attached_to);
                        if (target != null) {
                            sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                note.id, target.get_dot_id()));
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
            switch (node_type) {
                case DeploymentNodeType.NODE:
                    return diagram.skin_params.get_element_property("node", "BackgroundColor") ?? "#FEFECE";
                case DeploymentNodeType.DEVICE:
                    return diagram.skin_params.get_element_property("device", "BackgroundColor") ?? "#E8F4FA";
                case DeploymentNodeType.ARTIFACT:
                    return diagram.skin_params.get_element_property("artifact", "BackgroundColor") ?? "#FFFFCC";
                case DeploymentNodeType.COMPONENT:
                    return diagram.skin_params.get_element_property("component", "BackgroundColor") ?? "#FEFECE";
                case DeploymentNodeType.DATABASE:
                    return diagram.skin_params.get_element_property("database", "BackgroundColor") ?? "#DFF0D8";
                case DeploymentNodeType.CLOUD:
                    return diagram.skin_params.get_element_property("cloud", "BackgroundColor") ?? "#E6F3FF";
                case DeploymentNodeType.FOLDER:
                    return diagram.skin_params.get_element_property("folder", "BackgroundColor") ?? "#FFFACD";
                case DeploymentNodeType.FRAME:
                    return diagram.skin_params.get_element_property("frame", "BackgroundColor") ?? "#F5F5F5";
                case DeploymentNodeType.STORAGE:
                    return diagram.skin_params.get_element_property("storage", "BackgroundColor") ?? "#FFE4E1";
                case DeploymentNodeType.QUEUE:
                    return diagram.skin_params.get_element_property("queue", "BackgroundColor") ?? "#E0FFE0";
                default:
                    return "#FEFECE";
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

                string fill_color = node.color ?? get_deployment_node_color(node.node_type, diagram);
                sb.append("%s  style=filled;\n".printf(indent_str));
                sb.append("%s  fillcolor=\"%s\";\n".printf(indent_str, fill_color));
                sb.append("%s  color=\"#333333\";\n".printf(indent_str));

                // Add children
                foreach (var child in node.children) {
                    generate_deployment_node_dot(sb, child, diagram, indent + 1);
                }

                sb.append("%s}\n".printf(indent_str));
            } else {
                // Regular node
                string shape = get_deployment_node_shape(node.node_type);
                string fill_color = node.color ?? get_deployment_node_color(node.node_type, diagram);

                // Build label with stereotype
                var label_builder = new StringBuilder();
                if (node.stereotype != null) {
                    label_builder.append("<<");
                    label_builder.append(node.stereotype);
                    label_builder.append(">>\\n");
                }
                label_builder.append(RenderUtils.escape_label(label));

                sb.append("%s%s [label=\"%s\", shape=%s, style=filled, fillcolor=\"%s\", color=\"#333333\"];\n".printf(
                    indent_str, node_id, label_builder.str, shape, fill_color));
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

            try {
                string tmp_dot = "/tmp/gplantuml_deployment.dot";
                string tmp_svg = "/tmp/gplantuml_deployment.svg";

                FileUtils.set_contents(tmp_dot, dot);

                string[] argv = {layout_engine, "-Tsvg", "-o", tmp_svg, tmp_dot};
                int exit_status;
                Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);

                if (exit_status != 0) {
                    warning("Graphviz returned error %d", exit_status);
                    return null;
                }

                string svg_content;
                FileUtils.get_contents(tmp_svg, out svg_content);

                return svg_content.data;
            } catch (Error e) {
                warning("Failed to render deployment diagram: %s", e.message);
                return null;
            }
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

            try {
                FileUtils.set_contents(filename, (string)svg_data);
                return true;
            } catch (Error e) {
                warning("Failed to write SVG: %s", e.message);
                return false;
            }
        }

        public bool export_to_pdf(DeploymentDiagram diagram, string filename) {
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
