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
            dot.append("digraph G {\n");
            dot.append_printf("  rankdir=%s;\n", MermaidSourceLine.rankdir(diagram.direction));
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=10, shape=box, style=\"rounded,filled\", fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n".printf(palette.component_fill, RenderUtils.contrast_text_themed(palette.component_fill, palette.node_text), palette.node_border));
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
            string title = entity.alias ?? entity.name;

            if (entity.attributes.size > 0) {
                // Mermaid's attribute table: type | name | keys | comment, the key and
                // comment columns only when some attribute has one
                var palette = ThemeManager.get_active_palette();
                bool has_keys = false, has_comment = false;
                foreach (var attr in entity.attributes) {
                    if (attr.keys_text().length > 0) has_keys = true;
                    if (attr.comment != null && attr.comment.length > 0) has_comment = true;
                }
                int columns = 2 + (has_keys ? 1 : 0) + (has_comment ? 1 : 0);

                var label = new StringBuilder();
                label.append_printf("<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">",
                                    palette.component_fill, palette.node_border);
                label.append_printf("<TR><TD COLSPAN=\"%d\"><B>%s</B></TD></TR>", columns, Markup.escape_text(title));
                foreach (var attr in entity.attributes) {
                    label.append("<TR>");
                    label.append_printf("<TD ALIGN=\"LEFT\">%s</TD>", cell(attr.type_name));
                    label.append_printf("<TD ALIGN=\"LEFT\">%s</TD>", cell(attr.name));
                    if (has_keys) label.append_printf("<TD ALIGN=\"LEFT\">%s</TD>", cell(attr.keys_text()));
                    if (has_comment) label.append_printf("<TD ALIGN=\"LEFT\">%s</TD>", cell(attr.comment));
                    label.append("</TR>");
                }
                label.append("</TABLE>");
                dot.append_printf("  %s [label=<%s>, shape=plain, style=solid];\n", safe_id, label.str);
            } else {
                // Simple box for entity without attributes
                dot.append_printf("  %s [label=\"%s\"];\n", safe_id, RenderUtils.escape_label(title));
            }

            // (Regions populated with real bounds in render_to_surface)
        }

        private static string cell(string? text) {
            return (text == null || text.length == 0) ? " " : Markup.escape_text(text);
        }

        private void render_relationship(StringBuilder dot, MermaidERRelationship relationship) {
            string from_id = RenderUtils.sanitize_id(relationship.from.name);
            string to_id = RenderUtils.sanitize_id(relationship.to.name);

            var attrs = new Gee.ArrayList<string>();

            // Crow's-foot notation at both ends, as Mermaid draws it
            attrs.add("dir=both");
            attrs.add("arrowtail=%s".printf(crows_foot(relationship.from_cardinality)));
            attrs.add("arrowhead=%s".printf(crows_foot(relationship.to_cardinality)));
            attrs.add("arrowsize=1.1");

            // Non-identifying relationships ("..") are dashed
            if (!relationship.identifying) {
                attrs.add("style=dashed");
            }

            // Add relationship label
            if (relationship.label != null && relationship.label.length > 0) {
                string label = RenderUtils.escape_label(relationship.label);
                attrs.add("label=\"%s\"".printf(label));
                attrs.add("fontsize=9");
            }

            dot.append_printf("  %s -> %s [%s];\n", from_id, to_id,
                string.joinv(", ", attrs.to_array()));
        }

        /**
         * Mermaid's crow's-foot markers as a Graphviz compound arrow type. The first
         * primitive is drawn closest to the entity, so "many" (crow) or the "zero"
         * circle sit where Mermaid puts them: the bar next to the box for one/one-or-more,
         * the circle set back for the optional ends.
         */
        private string crows_foot(MermaidERCardinality card) {
            switch (card) {
                case MermaidERCardinality.EXACTLY_ONE:
                    return "teetee";
                case MermaidERCardinality.ZERO_OR_ONE:
                    return "teeodot";
                case MermaidERCardinality.ONE_OR_MORE:
                    return "crowtee";
                case MermaidERCardinality.ZERO_OR_MORE:
                    return "crowodot";
                default:
                    return "none";
            }
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidERDiagram diagram) {
            string dot_source = generate_dot(diagram);

            var graph = RenderUtils.read_dot(dot_source);
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
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

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
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

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
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
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
