namespace GDiagram {
    public class ComponentDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public ComponentDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ComponentDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values
            string bg_color = diagram.skin_params.background_color ?? "#FAFAFA";
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = diagram.skin_params.default_font_color ?? "#424242";

            sb.append("digraph component {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [style=\"filled\", fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9];\n".printf(font_name));
            sb.append("  compound=true;\n");

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
            }

            sb.append("\n");

            // Get colors from theme
            string comp_color = diagram.skin_params.get_element_property("component", "BackgroundColor") ?? "#FEFECE";
            string comp_border = diagram.skin_params.get_element_property("component", "BorderColor") ?? "black";
            string iface_color = diagram.skin_params.get_element_property("interface", "BackgroundColor") ?? "#B4A7E5";
            string pkg_color = diagram.skin_params.get_element_property("package", "BackgroundColor") ?? "#DDDDDD";

            // Render components
            sb.append("  // Components\n");
            int cluster_idx = 0;
            foreach (var comp in diagram.components) {
                append_component_node(sb, comp, comp_color, comp_border, pkg_color, ref cluster_idx);
            }

            // Render standalone interfaces
            sb.append("\n  // Interfaces\n");
            foreach (var iface in diagram.interfaces) {
                string id = RenderUtils.sanitize_id(iface.get_identifier());
                string label = RenderUtils.escape_label(iface.get_display_label());
                sb.append("  %s [label=\"%s\", shape=circle, width=0.3, height=0.3, style=filled, fillcolor=\"%s\"];\n".printf(
                    id, label, iface_color));
            }

            // Render ports
            if (diagram.ports.size > 0) {
                sb.append("\n  // Ports\n");
                foreach (var port in diagram.ports) {
                    string id = RenderUtils.sanitize_id(port.id);
                    string label = port.label != null ? RenderUtils.escape_label(port.label) : "";
                    string shape = "square";
                    string fill_color = "#FFFFFF";

                    // Different colors for port types
                    switch (port.port_type) {
                        case PortType.IN:
                            fill_color = "#CCFFCC";  // Green - required/input
                            label = label.length > 0 ? "← " + label : "←";
                            break;
                        case PortType.OUT:
                            fill_color = "#FFCCCC";  // Red - provided/output
                            label = label.length > 0 ? label + " →" : "→";
                            break;
                        default:
                            fill_color = "#FFFFCC";  // Yellow - bidirectional
                            label = label.length > 0 ? "↔ " + label : "↔";
                            break;
                    }

                    sb.append("  %s [label=\"%s\", shape=%s, style=filled, fillcolor=\"%s\", width=0.3, height=0.3];\n".printf(
                        id, label, shape, fill_color));

                    // Connect port to parent component if specified
                    if (port.parent_component != null) {
                        string parent_id = RenderUtils.sanitize_id(port.parent_component);
                        sb.append("  %s -> %s [style=dotted, arrowhead=none];\n".printf(id, parent_id));
                    }
                }
            }

            // Render relationships
            sb.append("\n  // Relationships\n");
            foreach (var rel in diagram.relationships) {
                string from_id = RenderUtils.sanitize_id(rel.from_id);
                string to_id = RenderUtils.sanitize_id(rel.to_id);

                string style = rel.is_dashed ? "dashed" : "solid";
                string arrowhead = rel.right_arrow ? "vee" : "none";
                string arrowtail = rel.left_arrow ? "vee" : "none";

                // Handle special relationship types
                switch (rel.relation_type) {
                    case ComponentRelationType.AGGREGATION:
                        arrowtail = "odiamond";
                        break;
                    case ComponentRelationType.COMPOSITION:
                        arrowtail = "diamond";
                        break;
                    default:
                        break;
                }

                var attrs = new StringBuilder();
                attrs.append("style=%s".printf(style));
                attrs.append(", arrowhead=%s".printf(arrowhead));
                if (arrowtail != "none") {
                    attrs.append(", arrowtail=%s, dir=both".printf(arrowtail));
                }

                if (rel.label != null && rel.label.length > 0) {
                    attrs.append(", label=\"%s\"".printf(RenderUtils.escape_label(rel.label)));
                }

                if (rel.color != null) {
                    attrs.append(", color=\"%s\"".printf(rel.color));
                }

                sb.append("  %s -> %s [%s];\n".printf(from_id, to_id, attrs.str));
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";

                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(note.text), note_color));

                    if (note.attached_to != null) {
                        string attached_id = RenderUtils.sanitize_id(note.attached_to);
                        sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(note_id, attached_id));
                    }
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        private void append_component_node(StringBuilder sb, Component comp, string default_color,
                                           string default_border, string pkg_color, ref int cluster_idx) {
            string id = RenderUtils.sanitize_id(comp.get_identifier());
            string label = RenderUtils.escape_label(comp.get_display_label());
            string fill_color = comp.color ?? default_color;

            if (comp.is_container || comp.children.size > 0) {
                // Render as cluster subgraph
                sb.append("\n  subgraph cluster_%d {\n".printf(cluster_idx++));
                sb.append("    label=\"%s\";\n".printf(label));

                // Style based on container type
                switch (comp.component_type) {
                    case ComponentType.CLOUD:
                        sb.append("    style=rounded;\n");
                        sb.append("    bgcolor=\"#E8E8E8\";\n");
                        break;
                    case ComponentType.DATABASE:
                        sb.append("    style=rounded;\n");
                        sb.append("    bgcolor=\"#CCFFCC\";\n");
                        break;
                    case ComponentType.FOLDER:
                        sb.append("    style=\"rounded,bold\";\n");
                        sb.append("    bgcolor=\"%s\";\n".printf(pkg_color));
                        break;
                    case ComponentType.FRAME:
                        sb.append("    style=solid;\n");
                        sb.append("    bgcolor=\"%s\";\n".printf(pkg_color));
                        break;
                    case ComponentType.NODE:
                        sb.append("    style=bold;\n");
                        sb.append("    bgcolor=\"#FFFFCC\";\n");
                        break;
                    default:
                        sb.append("    style=rounded;\n");
                        sb.append("    bgcolor=\"%s\";\n".printf(pkg_color));
                        break;
                }

                if (comp.stereotype != null) {
                    sb.append("    // Stereotype: <<%s>>\n".printf(comp.stereotype));
                }

                // Render children
                foreach (var child in comp.children) {
                    append_component_node(sb, child, default_color, default_border, pkg_color, ref cluster_idx);
                }

                sb.append("  }\n");
            } else {
                // Render as individual node
                string shape;
                string style = "filled";

                switch (comp.component_type) {
                    case ComponentType.DATABASE:
                        shape = "cylinder";
                        fill_color = comp.color ?? "#CCFFCC";
                        break;
                    case ComponentType.CLOUD:
                        shape = "ellipse";
                        fill_color = comp.color ?? "#E8E8E8";
                        break;
                    case ComponentType.ARTIFACT:
                        shape = "note";
                        break;
                    case ComponentType.STORAGE:
                        shape = "folder";
                        break;
                    case ComponentType.CARD:
                        shape = "box";
                        style = "filled,rounded";
                        break;
                    case ComponentType.AGENT:
                        shape = "box";
                        break;
                    case ComponentType.INTERFACE:
                        shape = "circle";
                        break;
                    case ComponentType.QUEUE:
                        shape = "box";
                        style = "filled";
                        fill_color = comp.color ?? "#E8E8FF";
                        break;
                    case ComponentType.BOUNDARY:
                        shape = "box";
                        style = "filled,rounded";
                        fill_color = comp.color ?? "#FFFFCC";
                        break;
                    case ComponentType.CONTROL:
                        shape = "circle";
                        fill_color = comp.color ?? "#CCFFCC";
                        break;
                    case ComponentType.ENTITY:
                        shape = "box";
                        style = "filled";
                        fill_color = comp.color ?? "#CCCCFF";
                        break;
                    case ComponentType.FILE:
                        shape = "note";
                        fill_color = comp.color ?? "#FFFFFF";
                        break;
                    case ComponentType.STACK:
                        shape = "box3d";
                        fill_color = comp.color ?? "#E8E8E8";
                        break;
                    case ComponentType.RECTANGLE:
                        shape = "box";
                        style = "filled";
                        fill_color = comp.color ?? "#FEFECE";
                        break;
                    default:
                        shape = "component";
                        break;
                }

                var attrs = new StringBuilder();
                attrs.append("label=\"%s\"".printf(label));
                attrs.append(", shape=%s".printf(shape));
                attrs.append(", style=\"%s\"".printf(style));
                attrs.append(", fillcolor=\"%s\"".printf(fill_color));
                attrs.append(", color=\"%s\"".printf(default_border));

                if (comp.stereotype != null) {
                    attrs.append(", xlabel=\"<<%s>>\"".printf(comp.stereotype));
                }

                sb.append("  %s [%s];\n".printf(id, attrs.str));
            }
        }

        public uint8[]? render_to_svg(ComponentDiagram diagram) {
            string dot = generate_dot(diagram);

            string[] argv = {layout_engine, "-Tsvg"};
            string std_out;
            string std_err;
            int exit_status;

            try {
                var proc = new Subprocess.newv(argv, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                proc.communicate_utf8(dot, null, out std_out, out std_err);
                proc.wait(null);
                exit_status = proc.get_exit_status();

                if (exit_status != 0) {
                    warning("Graphviz dot failed: %s", std_err);
                    return null;
                }

                return std_out.data;
            } catch (Error e) {
                warning("Failed to run dot: %s", e.message);
                return null;
            }
        }

        public Cairo.ImageSurface? render_to_surface(ComponentDiagram diagram) {
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

                // Build element line number map from components
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var comp in diagram.components) {
                    if (comp.source_line > 0) {
                        element_lines.set(comp.id, comp.source_line);
                        if (comp.label != null && comp.label.length > 0) {
                            element_lines.set(comp.label, comp.source_line);
                        }
                        if (comp.alias != null && comp.alias.length > 0) {
                            element_lines.set(comp.alias, comp.source_line);
                        }
                    }
                }

                // Parse SVG regions for click-to-source navigation (with pixel scaling)
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, width, height);

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

        public bool export_to_png(ComponentDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(ComponentDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                FileUtils.set_data(filename, svg_data);
                return true;
            } catch (Error e) {
                warning("Failed to write SVG: %s", e.message);
                return false;
            }
        }

        public bool export_to_pdf(ComponentDiagram diagram, string filename) {
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
