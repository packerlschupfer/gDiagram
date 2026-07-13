namespace GDiagram {
    public class MermaidERRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidERRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidERDiagram diagram) {
            var dot = new StringBuilder();

            var palette = ThemeManager.get_active_palette();
            // Use top-down layout for ER diagrams
            dot.append("digraph G {\n");
            dot.append("  rankdir=TB;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=10, shape=box, style=\"rounded,filled\", fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n".printf(palette.component_fill, palette.node_text, palette.node_border));
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n\n");
            }

            // Render entities
            dot.append("  // Entities\n");
            foreach (var entity in diagram.entities) {
                render_entity(dot, entity);
            }

            dot.append("\n");

            // Render relationships
            if (diagram.relationships.size > 0) {
                dot.append("  // Relationships\n");
                foreach (var relationship in diagram.relationships) {
                    render_relationship(dot, relationship);
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_entity(StringBuilder dot, MermaidEREntity entity) {
            string safe_id = RenderUtils.sanitize_id(entity.name);

            // Build label with attributes if any
            if (entity.attributes.size > 0) {
                var label = new StringBuilder();
                label.append("{");
                label.append(RenderUtils.escape_record_label(entity.name));
                label.append("|");

                bool first = true;
                foreach (var attr in entity.attributes) {
                    if (!first) {
                        label.append("\\n");
                    }
                    first = false;

                    var attr_sb = new StringBuilder();
                    if (attr.is_primary_key) attr_sb.append("PK ");
                    if (attr.is_foreign_key) attr_sb.append("FK ");
                    if (attr.type_name != null) {
                        attr_sb.append(attr.type_name);
                        attr_sb.append(" ");
                    }
                    attr_sb.append(attr.name);
                    label.append(RenderUtils.escape_record_label(attr_sb.str));
                }

                label.append("}");
                dot.append_printf("  %s [label=\"%s\", shape=record];\n", safe_id, label.str);
            } else {
                // Simple box for entity without attributes
                string label = RenderUtils.escape_label(entity.name);
                dot.append_printf("  %s [label=\"%s\"];\n", safe_id, label);
            }

            // Store region
            // (Regions populated with real bounds in render_to_surface)
        }

        private void render_relationship(StringBuilder dot, MermaidERRelationship relationship) {
            string from_id = RenderUtils.sanitize_id(relationship.from.name);
            string to_id = RenderUtils.sanitize_id(relationship.to.name);

            var attrs = new Gee.ArrayList<string>();

            // ER relationships are undirected (no arrowhead)
            attrs.add("dir=none");

            // Add relationship label
            if (relationship.label != null && relationship.label.length > 0) {
                string label = RenderUtils.escape_label(relationship.label);
                attrs.add("label=\"%s\"".printf(label));
                attrs.add("fontsize=9");
            }

            // Add cardinality labels, positioned near the endpoints
            string from_card = get_cardinality_label(relationship.from_cardinality);
            string to_card = get_cardinality_label(relationship.to_cardinality);

            if (from_card.length > 0) {
                attrs.add("taillabel=\"%s\"".printf(from_card));
            }
            if (to_card.length > 0) {
                attrs.add("headlabel=\"%s\"".printf(to_card));
            }
            if (from_card.length > 0 || to_card.length > 0) {
                attrs.add("labeldistance=2.0");
                attrs.add("labelangle=25");
                attrs.add("labelfontsize=8");
            }

            dot.append_printf("  %s -> %s [%s];\n", from_id, to_id,
                string.joinv(", ", attrs.to_array()));
        }

        private string get_cardinality_label(MermaidERCardinality card) {
            switch (card) {
                case MermaidERCardinality.EXACTLY_ONE:
                    return "1";
                case MermaidERCardinality.ZERO_OR_ONE:
                    return "0..1";
                case MermaidERCardinality.ZERO_OR_MORE:
                    return "0..*";
                case MermaidERCardinality.ONE_OR_MORE:
                    return "1..*";
                default:
                    return "";
            }
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidERDiagram diagram) {
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
        public Cairo.ImageSurface? render_to_surface(MermaidERDiagram diagram) {
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
                foreach (var entity in diagram.entities) {
                    if (entity.source_line > 0)
                        element_lines.set(RenderUtils.sanitize_id(entity.name), entity.source_line);
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidERDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidERDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidERDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
