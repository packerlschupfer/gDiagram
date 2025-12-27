namespace GDiagram {
    public class MermaidFlowchartRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        public MermaidFlowchartRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidFlowchart diagram) {
            var dot = new StringBuilder();

            // Graph header - use direction to set rankdir
            string rankdir = get_rankdir(diagram.direction);
            dot.append("digraph G {\n");
            dot.append_printf("  rankdir=%s;\n", rankdir);
            dot.append("  node [fontname=\"Sans\", fontsize=12];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=10];\n");
            dot.append("  graph [fontname=\"Sans\"];\n");
            dot.append("\n");

            // Render nodes
            foreach (var node in diagram.nodes) {
                render_node(dot, node);
            }

            dot.append("\n");

            // Render subgraphs
            int subgraph_counter = 0;
            foreach (var subgraph in diagram.subgraphs) {
                render_subgraph(dot, subgraph, subgraph_counter++);
            }

            // Render edges
            foreach (var edge in diagram.edges) {
                render_edge(dot, edge);
            }

            dot.append("}\n");

            return dot.str;
        }

        private string get_rankdir(FlowchartDirection direction) {
            switch (direction) {
                case FlowchartDirection.TOP_DOWN:
                    return "TB";
                case FlowchartDirection.BOTTOM_UP:
                    return "BT";
                case FlowchartDirection.LEFT_RIGHT:
                    return "LR";
                case FlowchartDirection.RIGHT_LEFT:
                    return "RL";
                default:
                    return "TB";
            }
        }

        private void render_node(StringBuilder dot, FlowchartNode node) {
            string safe_id = node.get_safe_id();
            string label = RenderUtils.escape_label(node.text);
            string shape = get_node_shape(node.shape);
            string style_attr = get_node_style(node.shape);

            dot.append_printf("  %s [label=\"%s\", shape=%s%s];\n",
                safe_id, label, shape, style_attr);

            // Store region for click navigation
            regions.add(new ElementRegion(node.id, node.source_line, 0, 0, 0, 0));
        }

        private string get_node_shape(FlowchartNodeShape shape) {
            switch (shape) {
                case FlowchartNodeShape.RECTANGLE:
                    return "box";
                case FlowchartNodeShape.ROUNDED:
                    return "box";
                case FlowchartNodeShape.STADIUM:
                    return "box";
                case FlowchartNodeShape.SUBROUTINE:
                    return "box";
                case FlowchartNodeShape.CYLINDRICAL:
                    return "cylinder";
                case FlowchartNodeShape.CIRCLE:
                    return "circle";
                case FlowchartNodeShape.ASYMMETRIC:
                    return "box";
                case FlowchartNodeShape.RHOMBUS:
                    return "diamond";
                case FlowchartNodeShape.HEXAGON:
                    return "hexagon";
                case FlowchartNodeShape.PARALLELOGRAM:
                    return "box";
                case FlowchartNodeShape.TRAPEZOID:
                    return "trapezium";
                case FlowchartNodeShape.DOUBLE_CIRCLE:
                    return "doublecircle";
                default:
                    return "box";
            }
        }

        private string get_node_style(FlowchartNodeShape shape) {
            switch (shape) {
                case FlowchartNodeShape.ROUNDED:
                    return ", style=rounded";
                case FlowchartNodeShape.STADIUM:
                    return ", style=rounded, peripheries=1";
                case FlowchartNodeShape.SUBROUTINE:
                    return ", peripheries=2";
                case FlowchartNodeShape.ASYMMETRIC:
                    return ", skew=0.3";
                case FlowchartNodeShape.PARALLELOGRAM:
                    return ", skew=0.2";
                default:
                    return "";
            }
        }

        private void render_subgraph(StringBuilder dot, FlowchartSubgraph subgraph, int counter) {
            dot.append_printf("  subgraph cluster_%d {\n", counter);

            if (subgraph.title != null && subgraph.title.length > 0) {
                string label = RenderUtils.escape_label(subgraph.title);
                dot.append_printf("    label=\"%s\";\n", label);
            }

            if (subgraph.has_custom_direction) {
                string rankdir = get_rankdir(subgraph.direction);
                dot.append_printf("    rankdir=%s;\n", rankdir);
            }

            dot.append("    style=rounded;\n");
            dot.append("    color=gray;\n");

            // Render nodes in subgraph
            foreach (var node in subgraph.nodes) {
                dot.append_printf("    %s;\n", node.get_safe_id());
            }

            // Render nested subgraphs
            int nested_counter = 0;
            foreach (var nested in subgraph.subgraphs) {
                // Recursively render (would need to adjust indentation)
                render_subgraph(dot, nested, counter * 100 + nested_counter++);
            }

            dot.append("  }\n\n");
        }

        private void render_edge(StringBuilder dot, FlowchartEdge edge) {
            string from_id = edge.from.get_safe_id();
            string to_id = edge.to.get_safe_id();

            // Build edge attributes
            var attrs = new Gee.ArrayList<string>();

            // Label
            if (edge.label != null && edge.label.length > 0) {
                string label = RenderUtils.escape_label(edge.label);
                attrs.add("label=\"%s\"".printf(label));
            }

            // Edge style
            string edge_style = get_edge_style(edge.edge_type);
            if (edge_style.length > 0) {
                attrs.add(edge_style);
            }

            // Arrow type
            string arrow_style = get_arrow_style(edge.arrow_type);
            if (arrow_style.length > 0) {
                attrs.add(arrow_style);
            }

            // Min length for spacing
            if (edge.min_length > 1) {
                attrs.add("minlen=%d".printf(edge.min_length));
            }

            // Build attribute string
            string attr_str = "";
            if (attrs.size > 0) {
                attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            }

            dot.append_printf("  %s -> %s%s;\n", from_id, to_id, attr_str);
        }

        private string get_edge_style(FlowchartEdgeType edge_type) {
            switch (edge_type) {
                case FlowchartEdgeType.SOLID:
                    return "";
                case FlowchartEdgeType.DOTTED:
                    return "style=dotted";
                case FlowchartEdgeType.THICK:
                    return "penwidth=3";
                case FlowchartEdgeType.INVISIBLE:
                    return "style=invis";
                default:
                    return "";
            }
        }

        private string get_arrow_style(FlowchartArrowType arrow_type) {
            switch (arrow_type) {
                case FlowchartArrowType.NORMAL:
                    return "";
                case FlowchartArrowType.OPEN:
                    return "arrowhead=empty";
                case FlowchartArrowType.CROSS:
                    return "arrowhead=tee";
                case FlowchartArrowType.CIRCLE:
                    return "arrowhead=dot";
                case FlowchartArrowType.NONE:
                    return "arrowhead=none";
                default:
                    return "";
            }
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidFlowchart diagram) {
            string dot_source = generate_dot(diagram);

            // Parse DOT into graph
            var graph = Gvc.Graph.read_string(dot_source);
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

        // Render to Cairo surface
        public Cairo.ImageSurface? render_to_surface(MermaidFlowchart diagram) {
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

        // Export to PNG
        public bool export_to_png(MermaidFlowchart diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        // Export to SVG
        public bool export_to_svg(MermaidFlowchart diagram, string filename) {
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

        // Export to PDF
        public bool export_to_pdf(MermaidFlowchart diagram, string filename) {
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
