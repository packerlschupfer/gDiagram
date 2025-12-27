namespace GDiagram {
    public class MermaidClassRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidClassRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidClassDiagram diagram) {
            var dot = new StringBuilder();

            // Use top-down layout for class diagrams
            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  bgcolor=\"#FAFAFA\";\n");
            dot.append("  node [fontname=\"Sans\", fontsize=10, shape=record, style=\"filled\", fillcolor=\"#E8F5E9\"];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"#424242\"];\n");
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Render classes
            dot.append("  // Classes\n");
            foreach (var cls in diagram.classes) {
                render_class(dot, cls);
            }

            dot.append("\n");

            // Render relationships
            if (diagram.relations.size > 0) {
                dot.append("  // Relationships\n");
                foreach (var relation in diagram.relations) {
                    render_relation(dot, relation);
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_class(StringBuilder dot, MermaidClass cls) {
            string safe_id = RenderUtils.sanitize_id(cls.name);
            var label = new StringBuilder();

            // Build HTML-like label for record shape
            label.append("{");

            // Class name in bold
            string class_name = RenderUtils.escape_label(cls.name);
            label.append_printf("%s", class_name);

            // Add members if any
            if (cls.members.size > 0) {
                label.append("|");

                bool first = true;
                foreach (var member in cls.members) {
                    if (!first) {
                        label.append("\\n");
                    }
                    first = false;

                    // Visibility symbol
                    string vis = get_visibility_symbol(member.visibility);
                    label.append(vis);

                    // Member name
                    string member_name = RenderUtils.escape_label(member.name);
                    label.append(member_name);

                    // Type annotation
                    if (member.type_name != null && member.type_name.length > 0) {
                        string type_str = RenderUtils.escape_label(member.type_name);
                        label.append_printf(": %s", type_str);
                    }

                    // Method parentheses
                    if (member.is_method) {
                        label.append("()");
                    }
                }
            }

            label.append("}");

            dot.append_printf("  %s [label=\"%s\"];\n", safe_id, label.str);

            // Store region
            regions.add(new ElementRegion(cls.name, cls.source_line, 0, 0, 0, 0));
        }

        private string get_visibility_symbol(MermaidVisibility vis) {
            switch (vis) {
                case MermaidVisibility.PUBLIC:
                    return "+";
                case MermaidVisibility.PRIVATE:
                    return "-";
                case MermaidVisibility.PROTECTED:
                    return "#";
                case MermaidVisibility.PACKAGE:
                    return "~";
                default:
                    return "+";
            }
        }

        private void render_relation(StringBuilder dot, MermaidRelation relation) {
            string from_id = RenderUtils.sanitize_id(relation.from.name);
            string to_id = RenderUtils.sanitize_id(relation.to.name);

            var attrs = new Gee.ArrayList<string>();

            // Label
            if (relation.label != null && relation.label.length > 0) {
                string label = RenderUtils.escape_label(relation.label);
                attrs.add("label=\"%s\"".printf(label));
            }

            // Cardinality
            if (relation.from_cardinality != null) {
                attrs.add("taillabel=\"%s\"".printf(relation.from_cardinality));
            }
            if (relation.to_cardinality != null) {
                attrs.add("headlabel=\"%s\"".printf(relation.to_cardinality));
            }

            // Arrow style based on relation type
            string arrow_style = get_relation_arrow_style(relation.relation_type);
            if (arrow_style.length > 0) {
                attrs.add(arrow_style);
            }

            string arrowhead = get_relation_arrowhead(relation.relation_type);
            if (arrowhead.length > 0) {
                attrs.add("arrowhead=%s".printf(arrowhead));
            }

            string arrowtail = get_relation_arrowtail(relation.relation_type);
            if (arrowtail.length > 0) {
                attrs.add("arrowtail=%s".printf(arrowtail));
                attrs.add("dir=both");
            }

            string attr_str = "";
            if (attrs.size > 0) {
                attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            }

            dot.append_printf("  %s -> %s%s;\n", from_id, to_id, attr_str);
        }

        private string get_relation_arrow_style(MermaidRelationType type) {
            switch (type) {
                case MermaidRelationType.DEPENDENCY:
                case MermaidRelationType.REALIZATION:
                    return "style=dashed";
                default:
                    return "";
            }
        }

        private string get_relation_arrowhead(MermaidRelationType type) {
            switch (type) {
                case MermaidRelationType.INHERITANCE:
                case MermaidRelationType.REALIZATION:
                    return "empty";
                case MermaidRelationType.COMPOSITION:
                    return "diamond";
                case MermaidRelationType.AGGREGATION:
                    return "odiamond";
                case MermaidRelationType.DEPENDENCY:
                    return "vee";
                case MermaidRelationType.ASSOCIATION:
                default:
                    return "vee";
            }
        }

        private string get_relation_arrowtail(MermaidRelationType type) {
            // Most relations don't use arrowtail
            return "";
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidClassDiagram diagram) {
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
        public Cairo.ImageSurface? render_to_surface(MermaidClassDiagram diagram) {
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
        public bool export_to_png(MermaidClassDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidClassDiagram diagram, string filename) {
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

        public bool export_to_pdf(MermaidClassDiagram diagram, string filename) {
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
