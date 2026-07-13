namespace GDiagram {
    public class ComponentDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public ComponentDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ComponentDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values with active Palette fallbacks.
            var palette = ThemeManager.get_active_palette();
            string bg_color = RenderUtils.sanitize_color(diagram.skin_params.background_color ?? palette.background);
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = RenderUtils.sanitize_color(diagram.skin_params.default_font_color ?? palette.node_text);

            sb.append("digraph component {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [style=\"filled\", fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(font_name, palette.edge_color, palette.edge_text));
            sb.append("  compound=true;\n");

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
                sb.append("  fontcolor=\"%s\";\n".printf(font_color));
            }

            sb.append("\n");

            // Get colors from theme (palette as fallback).
            string comp_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("component", "BackgroundColor") ?? palette.component_fill);
            string comp_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("component", "BorderColor") ?? palette.component_border);
            string iface_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("interface", "BackgroundColor") ?? palette.person_fill);
            string pkg_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("package", "BackgroundColor") ?? palette.grid);

            // Collect container component identifiers — these render as clusters (not nodes),
            // so relationships must use an anchor node as the edge endpoint.
            var container_ids = new Gee.HashSet<string>();
            collect_container_ids(diagram.components, container_ids);

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
                    string fill_color = palette.node_fill;

                    // Different colors for port types
                    switch (port.port_type) {
                        case PortType.IN:
                            fill_color = palette.success;
                            label = label.length > 0 ? "← " + label : "←";
                            break;
                        case PortType.OUT:
                            fill_color = palette.warning;
                            label = label.length > 0 ? label + " →" : "→";
                            break;
                        default:
                            fill_color = palette.accent_secondary;
                            label = label.length > 0 ? "↔ " + label : "↔";
                            break;
                    }

                    sb.append("  %s [label=\"%s\", shape=%s, style=filled, fillcolor=\"%s\", width=0.3, height=0.3];\n".printf(
                        id, label, shape, fill_color));

                    // Connect port to parent component — redirect to anchor if parent is a container
                    if (port.parent_component != null) {
                        string parent_id = RenderUtils.sanitize_id(port.parent_component);
                        if (container_ids.contains(parent_id)) {
                            parent_id = parent_id + "_anchor";
                        }
                        sb.append("  %s -> %s [style=dotted, arrowhead=none];\n".printf(id, parent_id));
                    }
                }
            }

            // Render relationships
            sb.append("\n  // Relationships\n");
            foreach (var rel in diagram.relationships) {
                string from_id = RenderUtils.sanitize_id(rel.from_id);
                string to_id = RenderUtils.sanitize_id(rel.to_id);

                // Container components render as clusters; use anchor nodes for edge endpoints
                if (container_ids.contains(from_id)) {
                    from_id = from_id + "_anchor";
                }
                if (container_ids.contains(to_id)) {
                    to_id = to_id + "_anchor";
                }

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
                    string clean_rel = RenderUtils.strip_plantuml_markup(rel.label);
                    attrs.append(", label=\"%s\"".printf(RenderUtils.escape_label(clean_rel)));
                }

                if (rel.color != null) {
                    attrs.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(rel.color)));
                }

                sb.append("  %s -> %s [%s];\n".printf(from_id, to_id, attrs.str));
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary);
                string note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_color));

                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(note.text), note_color, note_font));

                    if (note.attached_to != null) {
                        string attached_id = RenderUtils.sanitize_id(note.attached_to);
                        // Container components render as clusters, not nodes. Without the
                        // anchor redirect Graphviz invents a default ellipse node named
                        // after the alias and the note points at that bubble instead.
                        if (container_ids.contains(attached_id)) {
                            attached_id = attached_id + "_anchor";
                        }
                        sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(note_id, attached_id));
                    }
                }
            }

            sb.append("}\n");

            return sb.str;
        }

        private void collect_container_ids(Gee.ArrayList<Component> comps, Gee.HashSet<string> container_ids) {
            foreach (var comp in comps) {
                if (comp.is_container || comp.children.size > 0) {
                    container_ids.add(RenderUtils.sanitize_id(comp.get_identifier()));
                    collect_container_ids(comp.children, container_ids);
                }
            }
        }

        private void append_component_node(StringBuilder sb, Component comp, string default_color,
                                           string default_border, string pkg_color, ref int cluster_idx) {
            var palette = ThemeManager.get_active_palette();
            string id = RenderUtils.sanitize_id(comp.get_identifier());
            // Strip PlantUML inline markup (<size:N>, **bold**, [[link]], etc.)
            // before escaping for dot. C4-PlantUML expansion produces a lot of
            // this markup that the component renderer can't render visually.
            string clean = RenderUtils.strip_plantuml_markup(comp.get_display_label());
            string label = RenderUtils.escape_label(clean);
            string fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : default_color;

            // C4-PlantUML color scheme: looked up here, applied AFTER the
            // type-based switch below so the C4 fill overrides the default
            // rectangle/database fillcolor.
            string? c4_fill = c4_color_for_stereotype(comp.stereotype);
            string? c4_border = c4_border_for_stereotype(comp.stereotype);
            string? c4_font = c4_font_for_stereotype(comp.stereotype);

            if (comp.is_container || comp.children.size > 0) {
                // Render as cluster subgraph
                sb.append("\n  subgraph cluster_%d {\n".printf(cluster_idx++));
                // Cluster label also needs PlantUML markup stripped (System_Boundary
                // emits things like "== Online Store\n<size:12>[" which would
                // otherwise show in the cluster header).
                sb.append("    label=\"%s\";\n".printf(label));

                // Style based on container type, use comp.color if set
                string container_bg;
                switch (comp.component_type) {
                    case ComponentType.CLOUD:
                        sb.append("    style=rounded;\n");
                        container_bg = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.grid;
                        break;
                    case ComponentType.DATABASE:
                        sb.append("    style=rounded;\n");
                        container_bg = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.database_fill;
                        break;
                    case ComponentType.FOLDER:
                        sb.append("    style=\"rounded,bold\";\n");
                        container_bg = comp.color != null ? RenderUtils.sanitize_color(comp.color) : pkg_color;
                        break;
                    case ComponentType.FRAME:
                        sb.append("    style=solid;\n");
                        container_bg = comp.color != null ? RenderUtils.sanitize_color(comp.color) : pkg_color;
                        break;
                    case ComponentType.NODE:
                        sb.append("    style=bold;\n");
                        container_bg = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.accent_secondary;
                        break;
                    default:
                        sb.append("    style=rounded;\n");
                        container_bg = comp.color != null ? RenderUtils.sanitize_color(comp.color) : pkg_color;
                        break;
                }
                sb.append("    bgcolor=\"%s\";\n".printf(container_bg));

                if (comp.stereotype != null) {
                    sb.append("    // Stereotype: <<%s>>\n".printf(comp.stereotype));
                }

                // Render children
                foreach (var child in comp.children) {
                    append_component_node(sb, child, default_color, default_border, pkg_color, ref cluster_idx);
                }

                sb.append("  }\n");
                // Invisible anchor node so outer edges can reach the cluster boundary
                sb.append("  %s [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(id + "_anchor"));
            } else {
                // Render as individual node
                string shape;
                string style = "filled";

                switch (comp.component_type) {
                    case ComponentType.DATABASE:
                        shape = "cylinder";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.database_fill;
                        break;
                    case ComponentType.CLOUD:
                        shape = "ellipse";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.external_fill;
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
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.person_fill;
                        break;
                    case ComponentType.BOUNDARY:
                        shape = "box";
                        style = "filled,rounded";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.accent_secondary;
                        break;
                    case ComponentType.CONTROL:
                        shape = "circle";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.success;
                        break;
                    case ComponentType.ENTITY:
                        shape = "box";
                        style = "filled";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.component_fill;
                        break;
                    case ComponentType.FILE:
                        shape = "note";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.node_fill;
                        break;
                    case ComponentType.STACK:
                        shape = "box3d";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.grid;
                        break;
                    case ComponentType.RECTANGLE:
                        shape = "box";
                        style = "filled";
                        fill_color = comp.color != null ? RenderUtils.sanitize_color(comp.color) : palette.node_fill;
                        break;
                    default:
                        shape = "component";
                        break;
                }

                // C4 stereotype overrides — apply now that the type switch
                // above has set the per-shape default. User-set colors still
                // win (we only override when comp.color is null).
                if (c4_fill != null && comp.color == null) {
                    fill_color = c4_fill;
                }
                // Boundary stereotypes are dashed-outline transparent boxes
                if (comp.stereotype != null && comp.stereotype.has_suffix("boundary")) {
                    style = "dashed";
                }

                var attrs = new StringBuilder();
                attrs.append("label=\"%s\"".printf(label));
                attrs.append(", shape=%s".printf(shape));
                attrs.append(", style=\"%s\"".printf(style));
                attrs.append(", fillcolor=\"%s\"".printf(fill_color));
                string border = c4_border ?? default_border;
                attrs.append(", color=\"%s\"".printf(border));
                if (c4_font != null) {
                    attrs.append(", fontcolor=\"%s\"".printf(c4_font));
                }

                if (comp.stereotype != null) {
                    attrs.append(", xlabel=\"<<%s>>\"".printf(comp.stereotype));
                }

                sb.append("  %s [%s];\n".printf(id, attrs.str));
            }
        }

        /**
         * Map a C4-PlantUML stereotype to a fill color from the active
         * Palette. Returns null for stereotypes that aren't C4 element
         * types so the caller falls back to the shape default.
         *
         * Boundary stereotypes return "transparent" — the border is what
         * carries the visual in that case (see the dashed style).
         */
        private string? c4_color_for_stereotype(string? stereo) {
            if (stereo == null) return null;
            var p = ThemeManager.get_active_palette();
            switch (stereo) {
                case "person":             return p.person_fill;
                case "external_person":    return p.external_fill;
                case "system":             return p.system_fill;
                case "external_system":    return p.external_fill;
                case "container":          return p.container_fill;
                case "external_container": return p.external_fill;
                case "component":          return p.component_fill;
                case "external_component": return p.external_fill;
                case "system_boundary":
                case "container_boundary":
                case "enterprise_boundary":
                case "boundary":           return "transparent";
                default: return null;
            }
        }

        private string? c4_border_for_stereotype(string? stereo) {
            if (stereo == null) return null;
            var p = ThemeManager.get_active_palette();
            switch (stereo) {
                case "person":             return p.person_border;
                case "external_person":    return p.external_border;
                case "system":             return p.system_border;
                case "external_system":    return p.external_border;
                case "container":          return p.container_border;
                case "external_container": return p.external_border;
                case "component":          return p.component_border;
                case "external_component": return p.external_border;
                case "system_boundary":
                case "container_boundary":
                case "enterprise_boundary":
                case "boundary":           return p.boundary_stroke;
                default: return null;
            }
        }

        /**
         * C4 elements compute contrast text from their fill color.
         * Boundaries use the boundary stroke color.
         */
        private string? c4_font_for_stereotype(string? stereo) {
            if (stereo == null) return null;
            var fill = c4_color_for_stereotype(stereo);
            if (fill == null) return null;
            var p = ThemeManager.get_active_palette();
            switch (stereo) {
                case "system_boundary":
                case "container_boundary":
                case "enterprise_boundary":
                case "boundary":
                    return p.boundary_stroke;
                default:
                    return RenderUtils.contrast_text(fill);
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
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(ComponentDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
