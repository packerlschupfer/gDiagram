namespace GDiagram {
    public class MindMapDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public MindMapDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MindMapDiagram diagram) {
            var sb = new StringBuilder();
            bool is_wbs = diagram.diagram_type == DiagramType.WBS;

            sb.append("digraph G {\n");
            sb.append("  rankdir=LR;\n");  // Left to right for mindmaps
            sb.append("  fontname=\"Sans\";\n");
            var palette = ThemeManager.get_active_palette();
            sb.append("  node [style=\"filled\", fontname=\"Sans\", fontsize=11];\n");
            sb.append("  edge [fontname=\"Sans\", fontsize=10, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            sb.append("  nodesep=0.3;\n");
            sb.append("  ranksep=0.5;\n");

            // Title
            if (diagram.title != null) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=16;\n");
                sb.append("  fontcolor=\"%s\";\n".printf(palette.node_text));
            }

            // Render tree from root
            sb.append("\n  // Nodes\n");
            if (diagram.root != null) {
                generate_mindmap_node_dot(sb, diagram.root, diagram, is_wbs);
            }

            sb.append("}\n");

            return sb.str;
        }

        private string get_mindmap_node_shape(MindMapNodeStyle style, bool is_wbs) {
            if (is_wbs) {
                // WBS always uses boxes
                return "box";
            }

            switch (style) {
                case MindMapNodeStyle.BOX:
                    return "box";
                case MindMapNodeStyle.ROUNDED:
                    return "box";  // Will add rounded corners
                case MindMapNodeStyle.CLOUD:
                    return "ellipse";
                case MindMapNodeStyle.PILL:
                    return "ellipse";
                default:
                    return "box";
            }
        }

        private void generate_mindmap_node_dot(StringBuilder sb, MindMapNode node, MindMapDiagram diagram, bool is_wbs) {
            string id = node.get_dot_id();
            string shape = get_mindmap_node_shape(node.style, is_wbs);
            string text = RenderUtils.escape_label(node.text);

            // Color based on level — cycle through palette role fills so each
            // level gets a visually distinct but theme-consistent color.
            var palette = ThemeManager.get_active_palette();
            string[] level_colors = {
                palette.node_fill,
                palette.component_fill,
                palette.container_fill,
                palette.system_fill,
                palette.accent_secondary,
                palette.person_fill
            };
            string fill_color = node.color ?? level_colors[node.level % level_colors.length];

            string style = "filled";
            if (node.style == MindMapNodeStyle.ROUNDED || node.style == MindMapNodeStyle.PILL) {
                style = "filled,rounded";
            }

            sb.append("  %s [label=\"%s\", shape=%s, style=\"%s\", fillcolor=\"%s\", color=\"%s\"];\n".printf(
                id, text, shape, style, fill_color, palette.node_border));

            // Connect to children
            foreach (var child in node.children) {
                generate_mindmap_node_dot(sb, child, diagram, is_wbs);
                sb.append("  %s -> %s [arrowhead=none];\n".printf(id, child.get_dot_id()));
            }
        }

        public uint8[]? render_to_svg(MindMapDiagram diagram) {
            string dot = generate_dot(diagram);
            return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "mindmap");
        }

        public Cairo.ImageSurface? render_to_surface(MindMapDiagram diagram) {
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
                var all_nodes = diagram.get_all_nodes();
                foreach (var node in all_nodes) {
                    if (node.source_line > 0) {
                        element_lines.set(node.get_dot_id(), node.source_line);
                    }
                }
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, (int)width, (int)height);

                return surface;
            } catch (Error e) {
                warning("Failed to create surface from SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(MindMapDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MindMapDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MindMapDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
