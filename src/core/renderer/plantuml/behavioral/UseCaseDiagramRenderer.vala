namespace GDiagram {
    public class UseCaseDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public UseCaseDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(UseCaseDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values with active Palette fallbacks.
            var palette = ThemeManager.get_active_palette();
            string bg_raw = diagram.skin_params.background_color ?? palette.background;
            string bg_color = RenderUtils.fill_color(bg_raw);
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = RenderUtils.sanitize_color(diagram.skin_params.default_font_color ?? palette.node_text);

            sb.append("digraph usecase {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            string bg_angle = RenderUtils.gradient_stmt(bg_raw);
            if (bg_angle != "") {
                sb.append("  %s\n".printf(bg_angle));
            }
            sb.append("  node [style=\"filled\", fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            // "skinparam usecase { ArrowColor Olive }" (or a global ArrowColor) was ignored
            string arrow_color = RenderUtils.sanitize_color(
                diagram.skin_params.get_element_property("usecase", "ArrowColor") ??
                diagram.skin_params.get_global("ArrowColor") ?? RenderUtils.edge_line_color(diagram.skin_params, palette));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(
                font_name, arrow_color, RenderUtils.edge_label_color(diagram.skin_params, palette)));
            sb.append("  compound=true;\n");

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
                sb.append("  fontcolor=\"%s\";\n".printf(RenderUtils.title_color(diagram.skin_params, palette)));
            }

            sb.append("\n");

            // Render actors — use the palette's person slot.
            string actor_color = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("actor", "BackgroundColor") ?? palette.person_fill);
            string actor_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("actor", "BorderColor") ?? palette.person_border);

            // "skinparam actorStyle awesome" / "hollow": only sequence diagrams read it
            string actor_style = "";
            string? style_param = diagram.skin_params.get_global("actorstyle");
            if (style_param != null) {
                string st = style_param.strip().down();
                if (st == "awesome") {
                    actor_style = " gdawesome";
                } else if (st == "hollow") {
                    actor_style = " gdhollow";
                }
            }

            sb.append("  // Actors\n");
            foreach (var actor in diagram.actors) {
                string id = RenderUtils.sanitize_id(actor.get_id());
                string fill = actor_fill(diagram, actor, actor_color);
                sb.append(actor_node("  ", id, actor, fill, actor_border, actor_style));
            }

            // Render use cases
            // As written: usecase_fill() keeps a gradient, converted where it is emitted
            string uc_color = diagram.skin_params.get_element_property("usecase", "BackgroundColor") ?? palette.component_fill;
            string uc_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("usecase", "BorderColor") ?? palette.component_border);

            sb.append("\n  // Use Cases\n");
            foreach (var uc in diagram.use_cases) {
                sb.append(usecase_node("  ", diagram, uc, uc_color, uc_border));
            }

            // Render packages/rectangles as clusters
            string pkg_color_raw = diagram.skin_params.get_element_property("package", "BackgroundColor") ?? palette.grid;
            string pkg_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("package", "BorderColor") ?? palette.boundary_stroke);
            string rect_color_raw = diagram.skin_params.get_element_property("rectangle", "BackgroundColor") ?? palette.node_fill;
            string rect_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("rectangle", "BorderColor") ?? palette.boundary_stroke);

            // Container name/alias -> cluster index, for links that end at a container.
            // Indices follow diagram.packages; nested containers are drawn inside their parent.
            var pkg_clusters = new Gee.HashMap<string, int>();
            for (int i = 0; i < diagram.packages.size; i++) {
                var pkg = diagram.packages[i];
                pkg_clusters.set(pkg.name, i);
                if (pkg.alias != null) {
                    pkg_clusters.set(pkg.alias, i);
                }
            }
            // Containers linked as "(Name)" from inside themselves get a use case node of their own
            self_usecases = new Gee.HashSet<int>();
            tab_clusters = new Gee.ArrayList<string>();
            string? package_style = diagram.skin_params.get_global("packagestyle");
            tabs_for_packages = package_style == null || package_style.strip().down() != "rectangle";
            foreach (var rel in diagram.relationships) {
                foreach (bool from_end in new bool[] { true, false }) {
                    string end = from_end ? rel.from_id : rel.to_id;
                    string other = from_end ? rel.to_id : rel.from_id;
                    if (diagram.find_actor(end) == null && diagram.find_usecase(end) == null && pkg_clusters.has_key(end)) {
                        int idx = pkg_clusters.get(end);
                        if (in_container(diagram, other, idx)) {
                            self_usecases.add(idx);
                        }
                    }
                }
            }
            var cstyle = new ContainerStyle();
            cstyle.rect_color_raw = rect_color_raw;
            cstyle.pkg_color_raw = pkg_color_raw;
            cstyle.rect_border = rect_border;
            cstyle.pkg_border = pkg_border;
            cstyle.actor_color = actor_color;
            cstyle.actor_border = actor_border;
            cstyle.actor_style = actor_style;
            cstyle.uc_color = uc_color;
            cstyle.uc_border = uc_border;
            foreach (var pkg in diagram.packages) {
                if (pkg.parent == null || !diagram.packages.contains(pkg.parent)) {
                    append_container(sb, diagram, pkg, cstyle, "  ");
                }
            }

            // Render notes
            string note_color_raw = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary;
            string note_color = RenderUtils.fill_color(note_color_raw);
            string note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_color));
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"%s, fontcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(RenderUtils.strip_inline_creole(note.text)), note_color,
                        RenderUtils.gradient_attr(note_color_raw), note_font));

                    if (note.attached_to != null) {
                        string target_id = RenderUtils.sanitize_id(note.attached_to);
                        // A container is a cluster, not a node: the note links to its anchor,
                        // clipped at the border, as relationships do. It pointed at a ghost
                        // ellipse named after the container.
                        string note_clip = "";
                        if (diagram.find_actor(note.attached_to) == null && diagram.find_usecase(note.attached_to) == null &&
                            pkg_clusters.has_key(note.attached_to)) {
                            int idx = pkg_clusters.get(note.attached_to);
                            target_id = "_ucpkg%d_anchor".printf(idx);
                            note_clip = ", lhead=cluster_%d".printf(idx);
                        }
                        sb.append("  %s -> %s [style=dotted, arrowhead=none%s];\n".printf(note_id, target_id, note_clip));
                    }
                }
            }

            // Render relationships
            sb.append("\n  // Relationships\n");
            foreach (var rel in diagram.relationships) {
                string from_id = RenderUtils.sanitize_id(rel.from_id);
                string to_id = RenderUtils.sanitize_id(rel.to_id);
                // An end named like a container (and not an actor or use case) is the container:
                // the edge runs to its anchor and is clipped at the border, unless the other
                // end sits inside that container ("(Inner) .> (Sys)" in "rectangle Sys { }")
                string clip = "";
                bool from_is_pkg = diagram.find_actor(rel.from_id) == null && diagram.find_usecase(rel.from_id) == null &&
                                   pkg_clusters.has_key(rel.from_id);
                bool to_is_pkg = diagram.find_actor(rel.to_id) == null && diagram.find_usecase(rel.to_id) == null &&
                                 pkg_clusters.has_key(rel.to_id);
                if (from_is_pkg) {
                    int idx = pkg_clusters.get(rel.from_id);
                    from_id = "_ucpkg%d_anchor".printf(idx);
                    if (!in_container(diagram, rel.to_id, idx)) {
                        clip += ", ltail=cluster_%d".printf(idx);
                    } else {
                        from_id = "_ucpkg%d_self".printf(idx);
                    }
                }
                if (to_is_pkg) {
                    int idx = pkg_clusters.get(rel.to_id);
                    to_id = "_ucpkg%d_anchor".printf(idx);
                    if (!in_container(diagram, rel.from_id, idx)) {
                        clip += ", lhead=cluster_%d".printf(idx);
                    } else {
                        to_id = "_ucpkg%d_self".printf(idx);
                    }
                }

                string style = rel.is_dashed ? "dashed" : "solid";
                // "--" / ".." are plain lines; every association used to get an arrowhead
                string arrowhead = rel.directed ? "vee" : "none";

                // Handle different relationship types
                switch (rel.relation_type) {
                    case UseCaseRelationType.INCLUDE:
                        style = "dashed";
                        break;
                    case UseCaseRelationType.EXTEND:
                        style = "dashed";
                        break;
                    case UseCaseRelationType.GENERALIZATION:
                        arrowhead = "empty";
                        break;
                    default:
                        break;
                }

                // Inline link style ("#line:red;line.bold;text:red", "#green;line.dashed"); it was
                // ignored, and the label after it lost
                if (rel.line_style != null) {
                    style = rel.line_style;
                }
                var extra = new StringBuilder(clip);
                if (rel.line_color != null) {
                    extra.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(rel.line_color)));
                }
                if (rel.line_bold) {
                    extra.append(", penwidth=2");
                }
                if (rel.text_color != null) {
                    extra.append(", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(rel.text_color)));
                }

                // "-up->" / "-left->": the edge is written from the target back to the source
                // (drawn with dir=back), so ranking and left-to-right order put the target
                // above / to the left. The direction word used to break the link.
                string a = from_id;
                string b = to_id;
                string arrows = "arrowhead=%s".printf(arrowhead);
                string extra_str = extra.str;
                if (rel.placement == "up" || rel.placement == "left") {
                    a = to_id;
                    b = from_id;
                    arrows = "arrowhead=none, arrowtail=%s, dir=back".printf(arrowhead);
                    extra_str = extra_str.replace("ltail=", "@TAIL@").replace("lhead=", "ltail=").replace("@TAIL@", "lhead=");
                }

                if (rel.label != null && rel.label.length > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s, %s%s];\n".printf(
                        a, b, RenderUtils.escape_label(rel.label), style, arrows, extra_str));
                } else {
                    sb.append("  %s -> %s [style=%s, %s%s];\n".printf(
                        a, b, style, arrows, extra_str));
                }
                // Side by side for "-left->" / "-right->". Not for a container anchor or an
                // element inside a container: a root-level rank=same pulls it out of its cluster.
                // "->" (one line character) too, as PlantUML draws it
                if ((rel.placement == "left" || rel.placement == "right" || rel.horizontal) && !from_is_pkg && !to_is_pkg &&
                    !in_any_container(diagram, rel.from_id) && !in_any_container(diagram, rel.to_id)) {
                    sb.append("  { rank=same; %s; %s; }\n".printf(a, b));
                }
            }

            // "json Name { }" blocks (allowmixing) as tables
            if (diagram.json_blocks.size > 0) {
                sb.append("\n  // JSON\n");
                for (int i = 0; i < diagram.json_blocks.size; i++) {
                    sb.append(json_node(diagram.json_blocks[i], i, palette));
                }
            }

            sb.append("}\n");

            return ComponentDiagramRenderer.add_legend(sb.str, "  // Actors\n", diagram.legend, diagram.skin_params);
        }

        private Gee.HashSet<int> self_usecases = new Gee.HashSet<int>();
        // Cluster names drawn with a folder tab (packages, folders), for render_to_svg()
        private Gee.ArrayList<string> tab_clusters = new Gee.ArrayList<string>();
        private bool tabs_for_packages = true;

        // A JSON value as HTML table content: scalars as text, objects as key / value rows,
        // arrays one row per element
        private static string json_html(Json.Node node) {
            switch (node.get_node_type()) {
                case Json.NodeType.OBJECT: {
                    var rows = new StringBuilder();
                    var obj = node.get_object();
                    foreach (string member in obj.get_members()) {
                        rows.append("<TR><TD ALIGN=\"LEFT\">%s</TD><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(
                            Markup.escape_text(member), json_cell(obj.get_member(member))));
                    }
                    return rows.str;
                }
                case Json.NodeType.ARRAY: {
                    var rows = new StringBuilder();
                    foreach (var element in node.get_array().get_elements()) {
                        rows.append("<TR><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(json_cell(element)));
                    }
                    return rows.str;
                }
                case Json.NodeType.NULL:
                    return "<TR><TD>null</TD></TR>";
                default:
                    return "<TR><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(json_cell(node));
            }
        }

        private static string json_cell(Json.Node node) {
            switch (node.get_node_type()) {
                case Json.NodeType.OBJECT:
                case Json.NodeType.ARRAY:
                    return "<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"3\">%s</TABLE>".printf(json_html(node));
                case Json.NodeType.NULL:
                    return "null";
                default:
                    var v = node.get_value();
                    string text;
                    if (v.holds(typeof(string))) {
                        text = v.get_string();
                    } else if (v.holds(typeof(bool))) {
                        text = v.get_boolean() ? "true" : "false";
                    } else if (v.holds(typeof(int64))) {
                        text = v.get_int64().to_string();
                    } else if (v.holds(typeof(double))) {
                        text = node.get_double().to_string();
                    } else {
                        text = "";
                    }
                    return Markup.escape_text(text);
            }
        }

        // "json Name { ... }" as a table: the name over key / value rows. Text that is not
        // valid JSON is shown line by line.
        private static string json_node(UseCaseJson block, int index, Palette palette) {
            string body;
            try {
                var parser = new Json.Parser();
                parser.load_from_data(block.text);
                var root = parser.get_root();
                body = root != null ? json_html(root) : "";
            } catch (Error e) {
                var rows = new StringBuilder();
                foreach (string line in block.text.split("\n")) {
                    if (line.strip().length > 0) {
                        rows.append("<TR><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(Markup.escape_text(line.strip())));
                    }
                }
                body = rows.str;
            }
            string fill = RenderUtils.fill_color(palette.node_fill);
            string border = RenderUtils.sanitize_color(palette.node_border);
            return "  _ucjson%d [shape=plain, style=solid, fontcolor=\"%s\", label=<<TABLE BORDER=\"1\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"3\" BGCOLOR=\"%s\" COLOR=\"%s\"><TR><TD COLSPAN=\"2\">%s</TD></TR><TR><TD COLSPAN=\"2\" BORDER=\"0\" CELLPADDING=\"0\"><TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"3\">%s</TABLE></TD></TR></TABLE>>];\n".printf(
                index, RenderUtils.contrast_text(fill), fill, border, Markup.escape_text(block.name), body);
        }

        // Colours shared by every container cluster
        private class ContainerStyle {
            public string rect_color_raw = "";
            public string pkg_color_raw = "";
            public string rect_border = "";
            public string pkg_border = "";
            public string actor_color = "";
            public string actor_border = "";
            public string actor_style = "";
            public string uc_color = "";
            public string uc_border = "";
        }

        // One container as a cluster, with the containers nested in it drawn inside. The
        // cluster number is the container's index in diagram.packages.
        private void append_container(StringBuilder sb, UseCaseDiagram diagram, UseCasePackage pkg,
                                      ContainerStyle cs, string indent) {
            int cluster_idx = diagram.packages.index_of(pkg);
            bool rect = pkg.container_type == UseCaseContainerType.RECTANGLE;
            string container_name = rect ? "Rectangle" : "Package";
            string fill_raw = rect ? cs.rect_color_raw : cs.pkg_color_raw;
            string fill_color = RenderUtils.fill_color(fill_raw);
            string fill_angle = RenderUtils.gradient_stmt(fill_raw);
            string border_color = rect ? cs.rect_border : cs.pkg_border;
            string inner = indent + "  ";

            sb.append("\n%s// %s: %s\n".printf(indent, container_name, pkg.name));
            sb.append("%ssubgraph cluster_%d {\n".printf(indent, cluster_idx));
            sb.append("%slabel=\"%s\";\n".printf(inner, RenderUtils.escape_label(pkg.name)));
            // A package (or folder) is drawn as PlantUML draws it: a folder with its name in
            // a tab (render_to_svg() shapes the tab); it was a plain box
            bool tab = tabs_for_packages && (pkg.container_type == UseCaseContainerType.PACKAGE ||
                                             pkg.container_type == UseCaseContainerType.FOLDER);
            if (tab) {
                sb.append("%slabeljust=\"l\";\n%sfontname=\"Sans Bold\";\n".printf(inner, inner));
                tab_clusters.add("cluster_%d".printf(cluster_idx));
            }

            if (rect) {
                // Rectangle: system boundary style
                sb.append("%sstyle=\"filled\";\n".printf(inner));
                sb.append("%sfillcolor=\"%s\";\n".printf(inner, fill_color));
                if (fill_angle != "") {
                    sb.append("%s%s\n".printf(inner, fill_angle));
                }
                sb.append("%scolor=\"%s\";\n".printf(inner, border_color));
                sb.append("%spenwidth=2;\n".printf(inner));
            } else {
                // Package: tab style (simulated with filled)
                sb.append("%sstyle=filled;\n".printf(inner));
                sb.append("%sfillcolor=\"%s\";\n".printf(inner, fill_color));
                if (fill_angle != "") {
                    sb.append("%s%s\n".printf(inner, fill_angle));
                }
                sb.append("%scolor=\"%s\";\n".printf(inner, border_color));
            }
            sb.append("\n");

            // Actors in container
            foreach (var actor in pkg.actors) {
                string id = RenderUtils.sanitize_id(actor.get_id());
                string fill = actor_fill(diagram, actor, cs.actor_color);
                sb.append(actor_node(inner, id, actor, fill, cs.actor_border, cs.actor_style));
            }

            // Use cases in container
            foreach (var uc in pkg.use_cases) {
                sb.append(usecase_node(inner, diagram, uc, cs.uc_color, cs.uc_border));
            }
            // A use case named like this container and linked from inside it
            // ("(checkout) .> (payment)" in "rectangle checkout"): a use case node of its own.
            // The links ran to the container's invisible anchor between the other use cases.
            if (self_usecases.contains(cluster_idx)) {
                var self_uc = new UseCase(pkg.name);
                sb.append(usecase_node(inner, diagram, self_uc, cs.uc_color, cs.uc_border).replace(
                    inner + RenderUtils.sanitize_id(pkg.name) + " [", inner + "_ucpkg%d_self [".printf(cluster_idx)));
            }

            // Nested containers ("rectangle Sys { package Sub { } }")
            foreach (var child in diagram.packages) {
                if (child.parent == pkg) {
                    append_container(sb, diagram, child, cs, inner);
                }
            }

            // Anchor for links that end at the container itself; it also keeps a
            // container that only holds links from being dropped as an empty cluster
            sb.append("%s_ucpkg%d_anchor [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(inner, cluster_idx));
            sb.append("%s}\n".printf(indent));
        }

        // Actors are stick figures in PlantUML; they were filled ellipses. Graphviz has no such
        // shape: the node is an HTML label with an empty sized cell marked by the sentinel
        // background #010203, which RenderUtils.draw_actor_figures replaces with the figure in
        // the SVG. Fill and stroke colours travel in the class names.
        private static string actor_node(string indent, string id, UseCaseActor actor, string fill, string border,
                                         string style_class) {
            var rows = new StringBuilder();
            // "text:red" in the inline style
            string open_font = actor.text_color != null
                ? "<FONT COLOR=\"%s\">".printf(RenderUtils.sanitize_color(actor.text_color)) : "";
            string close_font = actor.text_color != null ? "</FONT>" : "";
            if (actor.stereotype != null && actor.stereotype.strip().length > 0) {
                rows.append("<TR><TD>%s<I>«%s»</I>%s</TD></TR>".printf(open_font, Markup.escape_text(actor.stereotype.strip()), close_font));
            }
            rows.append("<TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"30\" HEIGHT=\"46\" BGCOLOR=\"#010203\"> </TD></TR>");
            rows.append("<TR><TD>%s%s%s</TD></TR>".printf(open_font, Markup.escape_text(actor.name).replace("\\n", "<BR/>"), close_font));
            // "line:red" / "line.bold" in the inline style
            string stroke = actor.line_color != null ? RenderUtils.sanitize_color(actor.line_color) : border;
            string classes = "gdactor gdfill_%s gdstroke_%s%s%s%s".printf(
                color_token(fill), color_token(stroke), actor.business ? " gdbusiness" : "", style_class,
                actor.line_style == "bold" ? " gdbold" : "");
            // style=solid: the graph-wide "node [style=filled]" filled the whole node box grey
            return "%s%s [shape=none, class=\"%s\", style=\"solid\", label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"1\">%s</TABLE>>];\n".printf(
                indent, id, classes, rows.str);
        }

        // A colour as a class-name token: "#0A4A89" -> "0A4A89", "Gold" -> "Gold"
        private static string color_token(string color) {
            var sb = new StringBuilder();
            for (int i = 0; i < color.length; i++) {
                if (color[i].isalnum()) {
                    sb.append_c(color[i]);
                }
            }
            return sb.len > 0 ? sb.str : "000000";
        }

        // One use case ellipse, with its colour and inline style ("#palegreen;line:green;
        // line.dashed;text:green"): only the fill was applied
        private static string usecase_node(string indent, UseCaseDiagram diagram, UseCase uc, string uc_color,
                                           string uc_border) {
            string id = RenderUtils.sanitize_id(uc.get_id());
            string label = stereotype_label(uc.stereotype, uc.name);
            string fill_raw = usecase_fill(diagram, uc, uc_color);
            string fill = RenderUtils.fill_color(fill_raw);
            string border = uc.line_color != null ? RenderUtils.sanitize_color(uc.line_color)
                                                  : usecase_border(diagram, uc, uc_border);
            string text = uc.text_color != null ? RenderUtils.sanitize_color(uc.text_color) : RenderUtils.contrast_text(fill);
            string style = "filled";
            if (uc.line_style == "dashed" || uc.line_style == "dotted") {
                style = "\"filled,%s\"".printf(uc.line_style);
            }
            return "%s%s [label=\"%s\", shape=ellipse, style=%s, fillcolor=\"%s\"%s, color=\"%s\", fontcolor=\"%s\"%s%s];\n".printf(
                indent, id, RenderUtils.escape_label(label), style, fill, RenderUtils.gradient_attr(fill_raw),
                border, text, uc.line_style == "bold" ? ", penwidth=2" : "",
                uc.business ? ", class=\"gdbusiness\"" : "");
        }

        // "«Human»" above the name, as PlantUML labels stereotyped actors and use cases; the
        // stereotype was not shown. "\\n" is the DOT line break that escape_label keeps.
        private static string stereotype_label(string? stereotype, string name) {
            if (stereotype == null || stereotype.strip().length == 0) {
                return name;
            }
            return "«%s»\\n%s".printf(stereotype.strip(), name);
        }

        // Explicit colour, then a per-stereotype skinparam ("BackgroundColor<< Main >>"), then
        // the diagram default. Stereotype colours were ignored. Returned as written (a gradient
        // keeps both colours).
        private static string usecase_fill(UseCaseDiagram diagram, UseCase uc, string fallback) {
            if (uc.color != null) {
                return uc.color;
            }
            string? stereo = diagram.skin_params.get_stereotype_property("usecase", "BackgroundColor", uc.stereotype);
            if (stereo != null) {
                return stereo;
            }
            return fallback;
        }

        private static string usecase_border(UseCaseDiagram diagram, UseCase uc, string fallback) {
            string? stereo = diagram.skin_params.get_stereotype_property("usecase", "BorderColor", uc.stereotype);
            if (stereo != null) {
                return RenderUtils.sanitize_color(stereo);
            }
            return fallback;
        }

        // Actor colours may be written as "skinparam actor { BackgroundColor<<s>> }" or inside
        // "skinparam usecase { ActorBackgroundColor<<s>> }". A gradient gives its first colour:
        // the figure is drawn by draw_actor_figures from a single colour class token.
        private static string actor_fill(UseCaseDiagram diagram, UseCaseActor actor, string fallback) {
            if (actor.color != null) {
                return RenderUtils.sanitize_color(actor.color);
            }
            string? stereo = diagram.skin_params.get_stereotype_property("actor", "BackgroundColor", actor.stereotype);
            if (stereo == null) {
                stereo = diagram.skin_params.get_stereotype_property("usecase", "ActorBackgroundColor", actor.stereotype);
            }
            if (stereo != null) {
                return RenderUtils.sanitize_color(stereo);
            }
            return fallback;
        }

        // True when the actor or use case `id` is declared inside the container with this
        // cluster index (packages are numbered in declaration order)
        private static bool in_container(UseCaseDiagram diagram, string id, int cluster_idx) {
            if (cluster_idx < 0 || cluster_idx >= diagram.packages.size) {
                return false;
            }
            var container = diagram.packages[cluster_idx];
            // Directly in it, or in a container nested inside it
            foreach (var pkg in diagram.packages) {
                bool inside = false;
                for (var p = pkg; p != null; p = p.parent) {
                    if (p == container) {
                        inside = true;
                        break;
                    }
                }
                if (!inside) {
                    continue;
                }
                if (pkg != container && (pkg.name == id || pkg.alias == id)) {
                    return true;
                }
                foreach (var uc in pkg.use_cases) {
                    if (uc.name == id || uc.alias == id) {
                        return true;
                    }
                }
                foreach (var actor in pkg.actors) {
                    if (actor.name == id || actor.alias == id) {
                        return true;
                    }
                }
            }
            return false;
        }

        private static bool in_any_container(UseCaseDiagram diagram, string id) {
            for (int i = 0; i < diagram.packages.size; i++) {
                if (in_container(diagram, id, i)) {
                    return true;
                }
            }
            return false;
        }

        public uint8[]? render_to_svg(UseCaseDiagram diagram) {
            string dot = generate_dot(diagram);
            uint8[]? svg = RenderUtils.run_graphviz_subprocess(dot, layout_engine, "usecase");
            if (svg == null) {
                return null;
            }
            return RenderUtils.draw_actor_figures(draw_package_tabs(svg, tab_clusters));
        }

        private static string num(double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, "%.2f");
        }

        // Folder tabs on package clusters: the cluster's rectangle becomes a tab around its
        // (left-justified) title over the body, with a line under the tab
        private static uint8[] draw_package_tabs(uint8[] svg_data, Gee.ArrayList<string> clusters) {
            if (clusters.size == 0) {
                return svg_data;
            }
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            foreach (string cluster in clusters) {
                int t = svg.index_of("<title>%s</title>".printf(cluster));
                if (t < 0) {
                    continue;
                }
                int end = svg.index_of("</g>", t);
                int poly = svg.index_of("<polygon ", t);
                if (end < 0 || poly < 0 || poly > end) {
                    continue;
                }
                int ps = svg.index_of("points=\"", poly);
                if (ps < 0 || ps > end) {
                    continue;
                }
                ps += 8;
                int pe = svg.index_of("\"", ps);
                double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
                foreach (string pt in svg.substring(ps, pe - ps).strip().split(" ")) {
                    string[] xy = pt.split(",");
                    if (xy.length != 2) {
                        continue;
                    }
                    x0 = double.min(x0, double.parse(xy[0]));
                    x1 = double.max(x1, double.parse(xy[0]));
                    y0 = double.min(y0, double.parse(xy[1]));
                    y1 = double.max(y1, double.parse(xy[1]));
                }
                if (x0 >= x1 || y0 >= y1) {
                    continue;
                }
                // Tab size from the title: its font size and an estimated width
                string group = svg.substring(t, end - t);
                double font_size = 14;
                int title_len = 6;
                int fs = group.index_of("font-size=\"");
                if (fs >= 0) {
                    font_size = double.parse(group.substring(fs + 11, group.index_of("\"", fs + 11) - fs - 11));
                }
                int tx = group.index_of("<text");
                if (tx >= 0) {
                    int gt = group.index_of(">", tx);
                    int lt = group.index_of("</text>", gt);
                    if (gt >= 0 && lt > gt) {
                        title_len = group.substring(gt + 1, lt - gt - 1).char_count();
                    }
                }
                double tab_w = double.min(x1 - x0 - 10, title_len * font_size * 0.62 + 18);
                double tab_h = double.min((y1 - y0) / 2, font_size + 8);
                string points = "%s,%s %s,%s %s,%s %s,%s %s,%s %s,%s %s,%s".printf(
                    num(x0), num(y0), num(x0 + tab_w), num(y0), num(x0 + tab_w), num(y0 + tab_h),
                    num(x1), num(y0 + tab_h), num(x1), num(y1), num(x0), num(y1), num(x0), num(y0));
                string poly_tag_end = svg.substring(poly, end - poly);
                string stroke = "#000000";
                int st = poly_tag_end.index_of("stroke=\"");
                if (st >= 0) {
                    stroke = poly_tag_end.substring(st + 8, poly_tag_end.index_of("\"", st + 8) - st - 8);
                }
                string line = "\n<path class=\"gdtab\" fill=\"none\" stroke=\"%s\" d=\"M%s,%s L%s,%s\"/>".printf(
                    stroke, num(x0), num(y0 + tab_h), num(x0 + tab_w), num(y0 + tab_h));
                svg = svg.substring(0, ps) + points + svg.substring(pe, end - pe) + line + "\n" + svg.substring(end);
            }
            return svg.data;
        }

        public Cairo.ImageSurface? render_to_surface(UseCaseDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            // Length-aware cast (avoid strlen overread past the array end).
            string svg_str;
            if (svg_data.length == 0) {
                svg_str = "";
            } else {
                unowned string raw = (string) svg_data;
                int safe_len = int.min(raw.length, (int) svg_data.length);
                svg_str = (raw.length == svg_data.length)
                    ? raw
                    : raw.substring(0, safe_len);
            }
            if (svg_str != null && svg_str.length > 0) {
                // Ensure xml:space="preserve" on all <text> elements without duplicating
                svg_str = svg_str.replace(" xml:space=\"preserve\"", "");
                svg_str = svg_str.replace("<text ", "<text xml:space=\"preserve\" ");
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_str.data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                // Build element line number map from actors and use cases
                var element_lines = new Gee.HashMap<string, int>();
                foreach (var actor in diagram.actors) {
                    if (actor.source_line > 0) {
                        element_lines.set(actor.name, actor.source_line);
                        if (actor.alias != null) {
                            element_lines.set(actor.alias, actor.source_line);
                        }
                    }
                }
                foreach (var uc in diagram.use_cases) {
                    if (uc.source_line > 0) {
                        element_lines.set(uc.name, uc.source_line);
                        if (uc.alias != null) {
                            element_lines.set(uc.alias, uc.source_line);
                        }
                    }
                }
                // Also check actors/use cases in packages
                foreach (var pkg in diagram.packages) {
                    foreach (var actor in pkg.actors) {
                        if (actor.source_line > 0) {
                            element_lines.set(actor.name, actor.source_line);
                            if (actor.alias != null) {
                                element_lines.set(actor.alias, actor.source_line);
                            }
                        }
                    }
                    foreach (var uc in pkg.use_cases) {
                        if (uc.source_line > 0) {
                            element_lines.set(uc.name, uc.source_line);
                            if (uc.alias != null) {
                                element_lines.set(uc.alias, uc.source_line);
                            }
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

        public bool export_to_png(UseCaseDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(UseCaseDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(UseCaseDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
