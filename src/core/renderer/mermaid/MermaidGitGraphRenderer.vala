namespace GDiagram {
    public class MermaidGitGraphRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // Branch colors cycle through palette role slots so each branch
        // is visually distinct within the active theme.
        private string[] branch_fill() {
            var p = ThemeManager.get_active_palette();
            return new string[] {
                p.success, p.container_fill, p.warning, p.accent_secondary,
                p.person_fill, p.component_fill, p.accent_primary, p.database_fill
            };
        }
        private string[] branch_border() {
            var p = ThemeManager.get_active_palette();
            return new string[] {
                p.success, p.container_border, p.warning, p.accent_secondary,
                p.person_border, p.component_border, p.accent_primary, p.database_border
            };
        }

        public MermaidGitGraphRenderer(
            Gvc.Context ctx,
            Gee.ArrayList<ElementRegion> regions,
            string engine
        ) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidGitGraph diagram) {
            var dot = new StringBuilder();

            // Map branch name -> index for color selection (int? to allow ?? 0 fallback)
            var branch_idx = new Gee.HashMap<string, int?>();
            for (int i = 0; i < diagram.branches.size; i++) {
                branch_idx.set(diagram.branches.get(i).name, (int?) i);
            }

            // Build a set of valid commit IDs for safe edge rendering
            var commit_ids = new Gee.HashSet<string>();
            foreach (var c in diagram.all_commits) {
                commit_ids.add(c.id);
            }

            var palette = ThemeManager.get_active_palette();
            var BRANCH_FILL = branch_fill();
            var BRANCH_BORDER = branch_border();
            dot.append("digraph gitgraph {\n");
            dot.append("  rankdir=LR;\n");
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Monospace\", fontsize=9, width=0.65, height=0.65];\n");
            dot.append("  edge [fontname=\"Sans\", fontsize=8, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("\n");

            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n",
                    RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n");
                dot.append("  fontname=\"Sans\";\n\n");
            }

            int n = diagram.all_commits.size;

            // Invisible timeline chain to enforce left-to-right ordering by commit.order
            if (n > 1) {
                for (int i = 0; i < n; i++) {
                    dot.append_printf("  _t%d [label=\"\", style=invis, fixedsize=true, width=0.01, height=0.01];\n", i);
                }
                dot.append("  ");
                for (int i = 0; i < n; i++) {
                    if (i > 0) dot.append(" -> ");
                    dot.append_printf("_t%d", i);
                }
                dot.append(" [style=invis, weight=10];\n\n");

                // Pin each commit to its timeline slot.
                // Use the loop index (0..n-1) rather than commit.order, because
                // commit.order is assigned from the full unfiltered log and may
                // have gaps when branches are filtered out — Graphviz would then
                // auto-create undeclared _t* nodes as visible artifacts.
                for (int i = 0; i < n; i++) {
                    dot.append_printf("  {rank=same; _t%d; %s;}\n",
                        i, node_id(diagram.all_commits.get(i).id));
                }
                dot.append("\n");
            }

            // Commit nodes
            foreach (var commit in diagram.all_commits) {
                int idx = branch_idx.get(commit.branch_name) ?? 0;
                string fill   = BRANCH_FILL[idx % BRANCH_FILL.length];
                string border = BRANCH_BORDER[idx % BRANCH_BORDER.length];

                string shape;
                switch (commit.commit_type) {
                    case GitGraphCommitType.REVERSE:
                        shape = "diamond";
                        break;
                    case GitGraphCommitType.HIGHLIGHT:
                        shape = "doublecircle";
                        break;
                    default:
                        shape = "circle";
                        break;
                }

                string label;
                if (commit.tag != null && commit.tag.length > 0) {
                    label = RenderUtils.escape_label(
                        "%s\\n[%s]".printf(commit.id, commit.tag));
                } else {
                    label = RenderUtils.escape_label(commit.id);
                }

                dot.append_printf(
                    "  %s [label=\"\", xlabel=\"%s\", shape=%s, style=\"filled\", " +
                    "fixedsize=true, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", penwidth=2];\n",
                    node_id(commit.id), label, shape, fill, border,
                    RenderUtils.contrast_text(fill)
                );
            }

            dot.append("\n");

            // Edges: sequential parent and merge-from
            foreach (var commit in diagram.all_commits) {
                int idx = branch_idx.get(commit.branch_name) ?? 0;
                string border = BRANCH_BORDER[idx % BRANCH_BORDER.length];

                if (commit.parent_id != null && commit.parent_id.length > 0 &&
                    commit_ids.contains(commit.parent_id)) {
                    dot.append_printf(
                        "  %s -> %s [color=\"%s\", penwidth=2];\n",
                        node_id(commit.parent_id), node_id(commit.id), border
                    );
                }

                if (commit.merge_from_id != null && commit.merge_from_id.length > 0 &&
                    commit_ids.contains(commit.merge_from_id)) {
                    dot.append_printf(
                        "  %s -> %s [style=dashed, color=\"" + palette.edge_color + "\", penwidth=1.5];\n",
                        node_id(commit.merge_from_id), node_id(commit.id)
                    );
                }
            }

            dot.append("\n");

            // Branch label nodes (rounded box at end of each branch chain)
            foreach (var branch in diagram.branches) {
                var head = branch.get_head();
                if (head == null) continue;

                int idx = branch_idx.get(branch.name) ?? 0;
                string fill   = BRANCH_FILL[idx % BRANCH_FILL.length];
                string border = BRANCH_BORDER[idx % BRANCH_BORDER.length];
                string lbl_nid = "branch_lbl_" + node_id(branch.name);

                dot.append_printf(
                    "  %s [label=\"%s\", shape=box, style=\"filled,rounded\", " +
                    "fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", fontsize=9, fontname=\"Sans Bold\", " +
                    "fixedsize=false, width=0, height=0];\n",
                    lbl_nid, RenderUtils.escape_label(branch.name), fill, border,
                    RenderUtils.contrast_text(fill)
                );
                dot.append_printf(
                    "  %s -> %s [style=dashed, color=\"%s\", arrowhead=none, penwidth=1];\n",
                    node_id(head.id), lbl_nid, border
                );
            }

            dot.append("}\n");
            return dot.str;
        }

        // Returns a valid Graphviz node identifier for a commit id string.
        private string node_id(string id) {
            var sb = new StringBuilder("n_");
            foreach (char c in id.to_utf8()) {
                if (c.isalnum() || c == '_') sb.append_c(c);
                else sb.append("_");
            }
            return sb.str;
        }

        public uint8[]? render_to_svg(MermaidGitGraph diagram) {
            string dot_source = generate_dot(diagram);

            var graph = Gvc.Graph.read_string(dot_source);
            if (graph == null) {
                warning("Failed to parse DOT for git graph");
                return null;
            }

            int ret = context.layout(graph, layout_engine);
            if (ret != 0) {
                warning("Failed to layout git graph");
                return null;
            }

            uint8[] svg_data;
            ret = GraphvizCompat.render_data(context, graph, "svg", out svg_data);
            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render git graph");
                return null;
            }

            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(MermaidGitGraph diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return null;

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(
                    stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 600;
                if (height <= 0) height = 300;

                var surface = new Cairo.ImageSurface(
                    Cairo.Format.ARGB32, (int)width, (int)height);
                var cr = new Cairo.Context(surface);

                cr.set_source_rgb(1, 1, 1);
                cr.paint();

                var viewport = Rsvg.Rectangle() {
                    x = 0, y = 0, width = width, height = height
                };
                handle.render_document(cr, viewport);

                var element_lines = new Gee.HashMap<string, int>();
                foreach (var commit in diagram.all_commits) {
                    if (commit.source_line > 0)
                        element_lines.set(node_id(commit.id), commit.source_line);
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);

                // Strip invisible helper nodes (_t* timeline anchors, branch_lbl_* labels)
                // — only commit nodes (id starts with "n_") should be clickable.
                var commit_regions = new Gee.ArrayList<ElementRegion>();
                foreach (var r in regions) {
                    if (r.name.has_prefix("n_")) commit_regions.add(r);
                }
                regions.clear();
                regions.add_all(commit_regions);

                return surface;
            } catch (Error e) {
                warning("Failed to render git graph SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(MermaidGitGraph diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) return false;
            return surface.write_to_png(filename) == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(MermaidGitGraph diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidGitGraph diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) return false;
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
