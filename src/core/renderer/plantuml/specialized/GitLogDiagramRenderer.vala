/* GitLogDiagramRenderer.vala — renderer for PlantUML's @startgit / @startgitlog
 *
 * Unlike the other fixed-position renderers here this one hands the layout to
 * Graphviz, because PlantUML does the same: GitDiagram lays its nodes out with
 * SmetanaForGit, PlantUML's own in-process port of dot. A plain digraph of
 * commits with child -> parent edges therefore reproduces PlantUML's structure
 * rather than approximating it, and the lanes of the pasted art only need to
 * survive as the graph's shape, not as literal columns.
 *
 * Like PlantUML, the decoration in parentheses is drawn only on a tip commit
 * (one nothing points at) — MagicBox.getCommentBlock() requires node.isTop().
 */
namespace GDiagram {

    public class GitLogDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        /** Click-region name -> source line, for the generic render path. */
        public Gee.HashMap<string, int> element_lines = new Gee.HashMap<string, int>();

        public GitLogDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions,
                                     string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(GitLogDiagram d) {
            element_lines = new Gee.HashMap<string, int>();
            var palette = ThemeManager.get_active_palette();

            var sb = new StringBuilder();
            sb.append("digraph gitlog {\n");
            sb.append_printf("    bgcolor=\"%s\"\n", palette.background);
            sb.append("    rankdir=TB\n");
            sb.append("    nodesep=0.35\n");
            sb.append("    ranksep=0.45\n");
            sb.append_printf(
                "    node [fontname=\"Sans\" fontsize=12 shape=box style=\"rounded,filled\" " +
                "fillcolor=\"%s\" color=\"%s\" fontcolor=\"%s\" penwidth=1]\n",
                palette.node_fill, palette.node_border, palette.node_text);
            sb.append_printf("    edge [color=\"%s\" penwidth=1 arrowsize=0.7]\n",
                palette.node_border);

            if (d.commits.size == 0) {
                sb.append_printf(
                    "    empty [shape=plaintext style=\"\" label=\"%s\" fontcolor=\"%s\"]\n",
                    RenderUtils.escape_label("(no commits in this git log)"), palette.node_text);
                sb.append("}\n");
                return sb.str;
            }

            // A tip is a commit no other commit points at; only those show
            // their decoration, which is what PlantUML draws.
            var is_parent = new bool[d.commits.size];
            foreach (var c in d.commits) {
                foreach (int p in c.parents) {
                    if (p >= 0 && p < is_parent.length) is_parent[p] = true;
                }
            }

            for (int i = 0; i < d.commits.size; i++) {
                var c = d.commits.get(i);
                string node = "gc%d".printf(i);
                string label = c.name.length > 0 ? c.name : "(unnamed)";
                if (!is_parent[i] && c.label != null && c.label.length > 0) {
                    label = label + "\n" + c.label;
                }
                sb.append_printf("    %s [label=\"%s\"]\n", node,
                    RenderUtils.escape_label(label));
                element_lines.set(node, c.source_line);
            }

            for (int i = 0; i < d.commits.size; i++) {
                foreach (int p in d.commits.get(i).parents) {
                    if (p < 0 || p >= d.commits.size) continue;
                    sb.append_printf("    gc%d -> gc%d\n", i, p);
                }
            }

            sb.append("}\n");
            return sb.str;
        }

        public uint8[]? render_to_svg(GitLogDiagram diagram) {
            string dot_source = generate_dot(diagram);

            var graph = RenderUtils.read_dot(dot_source);
            if (graph == null) {
                warning("Failed to parse gitlog DOT graph");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout gitlog with engine: %s", layout_engine);
                context.free_layout(graph);
                return null;
            }

            uint8[] svg_data;
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);
            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render gitlog graph");
                return null;
            }
            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(GitLogDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null,
                    Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) width, (int) height);
                var cr = new Cairo.Context(surface);
                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
                handle.render_document(cr, viewport);

                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render gitlog SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(GitLogDiagram diagram, string filename) {
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(GitLogDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(GitLogDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
