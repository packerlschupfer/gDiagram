namespace GDiagram {
    public class MermaidFlowchartRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;

        // Per generate_dot(): cluster name and edge anchor node of each subgraph
        private Gee.HashMap<FlowchartSubgraph, string> cluster_names;
        private Gee.HashMap<FlowchartSubgraph, string> cluster_anchors;
        private Gee.HashSet<FlowchartSubgraph> empty_anchors;
        private bool sideways = false;

        public MermaidFlowchartRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidFlowchart diagram) {
            var dot = new StringBuilder();

            // Graph header - use direction to set rankdir
            string rankdir = get_rankdir(diagram.direction);
            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append_printf("  rankdir=%s;\n", rankdir);
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            dot.append("  node [fontname=\"Sans\", fontsize=12, style=\"filled\", fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n".printf(palette.node_fill, palette.node_text, palette.node_border));
            dot.append("  edge [fontname=\"Sans\", fontsize=10, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("  graph [fontname=\"Sans\", compound=true];\n");
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=%s;\n  labelloc=t;\n  fontsize=16;\n  fontcolor=\"%s\";\n",
                    format_label(diagram.title, false), palette.node_text);
            }
            dot.append("\n");

            sideways = diagram.direction == FlowchartDirection.LEFT_RIGHT ||
                       diagram.direction == FlowchartDirection.RIGHT_LEFT;
            assign_clusters(diagram);

            // Render nodes
            foreach (var node in diagram.nodes) {
                render_node(dot, node);
            }

            dot.append("\n");

            // Render subgraphs
            foreach (var subgraph in diagram.subgraphs) {
                render_subgraph(dot, subgraph);
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

        // ---- labels ----

        private static Regex? tag_re = null;
        private static Regex? html_hint_re = null;
        private static Regex? bold_re = null;
        private static Regex? bold2_re = null;
        private static Regex? italic_re = null;
        private static Regex? italic2_re = null;
        private static Regex? icon_re = null;

        private static void init_label_regexes() {
            if (tag_re != null) return;
            try {
                tag_re = new Regex("<\\s*(/?)\\s*(br|b|strong|i|em|u|s|del|sub|sup)\\s*/?\\s*>", RegexCompileFlags.CASELESS);
                html_hint_re = new Regex("<\\s*/?\\s*(br|b|strong|i|em|u|s|del|sub|sup)\\s*/?\\s*>", RegexCompileFlags.CASELESS);
                bold_re = new Regex("\\*\\*(.+?)\\*\\*");
                bold2_re = new Regex("(?<![A-Za-z0-9])__(.+?)__(?![A-Za-z0-9])");
                italic_re = new Regex("\\*(.+?)\\*");
                italic2_re = new Regex("(?<![A-Za-z0-9])_(.+?)_(?![A-Za-z0-9])");
                // Mermaid's own pattern (createText.replaceIconSubstring)
                icon_re = new Regex("(fa[bklrs]?):fa-([\\w-]+)");
            } catch (RegexError e) {
                warning("flowchart label regex: %s", e.message);
            }
        }

        /*
         * Mermaid turns "fa:fa-car" / "fab:fa-github" into a Font Awesome glyph, which
         * means a web font gDiagram would have to fetch — and the preview re-renders on
         * every keystroke, so it never goes to the network. The reference is replaced
         * by a neutral placeholder glyph instead, which keeps the label readable and
         * marks the spot where Mermaid draws its icon.
         */
        public const string ICON_MARK = "▣";

        public static string replace_icons(string text) {
            init_label_regexes();
            try {
                return icon_re.replace_literal(text, -1, 0, ICON_MARK);
            } catch (RegexError e) {
                return text;
            }
        }

        /**
         * DOT label value for Mermaid label text: a quoted string for plain text, or an
         * HTML label when the text is a markdown string ("`**bold** _it_`") or uses
         * <br>, <b>, <i>, … Entity codes (#quot; #9829;) are decoded either way.
         */
        public static string format_label(string text, bool markdown) {
            init_label_regexes();
            if (!markdown && !html_hint_re.match(text)) {
                return "\"%s\"".printf(RenderUtils.escape_label(
                    replace_icons(MermaidLexer.decode_entities(text))));
            }
            string body = html_body(text, markdown);
            return body.length > 0 ? "<" + body + ">" : "\"\"";
        }

        // Graphviz HTML-label content (without the outer < >), always well-formed
        public static string html_body(string text, bool markdown) {
            init_label_regexes();
            var sb = new StringBuilder();
            var open = new Gee.ArrayList<string>();
            MatchInfo m;
            int pos = 0;
            tag_re.match(text, 0, out m);
            while (m.matches()) {
                int s, e;
                m.fetch_pos(0, out s, out e);
                sb.append(text_html(text.substring(pos, s - pos), markdown));
                bool closing = m.fetch(1) == "/";
                string tag = graphviz_tag(m.fetch(2).down());
                if (tag == "BR") {
                    sb.append("<BR/>");
                } else if (!closing) {
                    sb.append("<" + tag + ">");
                    open.add(tag);
                } else if (open.size > 0 && open[open.size - 1] == tag) {
                    sb.append("</" + tag + ">");
                    open.remove_at(open.size - 1);
                }
                // An unmatched closing tag is dropped: Graphviz rejects unbalanced HTML
                pos = e;
                try {
                    m.next();
                } catch (RegexError err) {
                    break;
                }
            }
            sb.append(text_html(text.substring(pos), markdown));
            for (int i = open.size - 1; i >= 0; i--) {
                sb.append("</" + open[i] + ">");
            }
            return sb.str;
        }

        private static string graphviz_tag(string tag) {
            switch (tag) {
                case "br": return "BR";
                case "b": case "strong": return "B";
                case "i": case "em": return "I";
                case "u": return "U";
                case "s": case "del": return "S";
                case "sub": return "SUB";
                case "sup": return "SUP";
                default: return "B";
            }
        }

        // Node font size, and Mermaid's flowchart.wrappingWidth (200 at its 16px font)
        private const double LABEL_FONT = 12.0;
        private const double WRAP_WIDTH = 200.0 * LABEL_FONT / 16.0;

        /*
         * Mermaid wraps a markdown string at `wrappingWidth`; a plain string only
         * breaks where the source does. Wrapping happens before the ** / _ markers are
         * turned into tags, so a marked-up run is kept on one line (splitting it would
         * leave an unbalanced marker behind).
         */
        private static string[] wrap_markdown_line(string line) {
            if (line.length == 0) return new string[] { line };
            var words = new Gee.ArrayList<string>();
            var pending = new StringBuilder();
            foreach (string piece in line.split(" ")) {
                if (piece.length == 0) continue;
                if (pending.len > 0) pending.append(" ");
                pending.append(piece);
                if (markers_balanced(pending.str)) {
                    words.add(pending.str);
                    pending.truncate();
                }
            }
            if (pending.len > 0) words.add(pending.str);

            var lines = new Gee.ArrayList<string>();
            var current = new StringBuilder();
            foreach (string w in words) {
                string candidate = current.len > 0 ? current.str + " " + w : w;
                if (current.len > 0 && GanttText.width(plain_markdown(candidate), LABEL_FONT, false, "Sans") > WRAP_WIDTH) {
                    lines.add(current.str);
                    current.truncate();
                    current.append(w);
                } else {
                    current.truncate();
                    current.append(candidate);
                }
            }
            if (current.len > 0 || lines.size == 0) lines.add(current.str);
            return lines.to_array();
        }

        private static bool markers_balanced(string s) {
            int bold = 0, star = 0, under = 0;
            for (int i = 0; i < s.length; i++) {
                if (s[i] == '*') {
                    if (i + 1 < s.length && s[i + 1] == '*') {
                        bold++;
                        i++;
                    } else {
                        star++;
                    }
                } else if (s[i] == '_') {
                    under++;
                }
            }
            return bold % 2 == 0 && star % 2 == 0 && under % 2 == 0;
        }

        private static string plain_markdown(string s) {
            return s.replace("**", "").replace("*", "").replace("_", "");
        }

        private static string text_html(string text, bool markdown) {
            if (text.length == 0) return "";
            string[] lines;
            if (markdown) {
                var wrapped = new Gee.ArrayList<string>();
                foreach (string raw in text.split("\n")) {
                    foreach (string piece in wrap_markdown_line(raw.strip())) wrapped.add(piece);
                }
                lines = wrapped.to_array();
            } else {
                lines = new string[] { text };
            }
            var sb = new StringBuilder();
            for (int i = 0; i < lines.length; i++) {
                if (i > 0) sb.append("<BR/>");
                string line = markdown ? lines[i].strip() : lines[i];
                string esc = Markup.escape_text(replace_icons(MermaidLexer.decode_entities(line)));
                if (markdown) {
                    try {
                        esc = bold_re.replace(esc, -1, 0, "<B>\\1</B>");
                        esc = bold2_re.replace(esc, -1, 0, "<B>\\1</B>");
                        esc = italic_re.replace(esc, -1, 0, "<I>\\1</I>");
                        esc = italic2_re.replace(esc, -1, 0, "<I>\\1</I>");
                    } catch (RegexError e) {
                        // keep the escaped text
                    }
                }
                sb.append(esc);
            }
            return sb.str;
        }

        // CSS colour → Graphviz colour: rgb()/rgba() become hex, the rest passes through
        public static string css_color(string color) {
            string c = color.strip();
            string lower = c.down();
            if (lower.has_prefix("rgb")) {
                int open = c.index_of("(");
                int close = c.index_of(")");
                if (open > 0 && close > open) {
                    string[] parts = c.substring(open + 1, close - open - 1).split(",");
                    if (parts.length >= 3) {
                        var sb = new StringBuilder("#");
                        for (int i = 0; i < 3; i++) {
                            int v = int.parse(parts[i].strip());
                            sb.append_printf("%02x", v.clamp(0, 255));
                        }
                        if (parts.length >= 4) {
                            double a = double.parse(parts[3].strip());
                            sb.append_printf("%02x", ((int) Math.round(a * 255)).clamp(0, 255));
                        }
                        return sb.str;
                    }
                }
            }
            if (lower == "none") return "transparent";
            return c;
        }

        // ---- nodes ----

        private void render_node(StringBuilder dot, FlowchartNode node) {
            var palette = ThemeManager.get_active_palette();
            string safe_id = node.get_safe_id();
            string shape = get_node_shape(node.shape);
            string base_style = get_node_style(node.shape);
            string text = node.text;
            bool hides_label = shape_hides_label(node.shape);

            var attrs = new Gee.ArrayList<string>();
            if (node.icon != null && node.icon_is_image) {
                // A@{ img: "…" }: the image would have to be fetched, which the live
                // preview must never do, so a frame of the declared size holds a
                // placeholder glyph and the label sits beside it, as Mermaid places it.
                double iw = node.img_w > 0 ? node.img_w : 80;
                double ih = node.img_h > 0 ? node.img_h : 80;
                string cell = "<TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"%d\" BORDER=\"1\" STYLE=\"rounded\"><FONT POINT-SIZE=\"%d\">%s</FONT></TD></TR>".printf(
                    (int) iw, (int) ih, (int) double.min(28, double.min(iw, ih) * 0.6), ICON_MARK);
                string label_row = text.length > 0
                    ? "<TR><TD>%s</TD></TR>".printf(html_body(text, node.markdown)) : "";
                bool label_first = node.img_pos != null && node.img_pos.down().has_prefix("t");
                attrs.add("label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">%s%s</TABLE>>".printf(
                    label_first ? label_row + cell : cell + label_row, ""));
                attrs.add("shape=plain");
                attrs.add("fontcolor=\"%s\"".printf(
                    node.font_color != null ? css_color(node.font_color) : palette.node_text));
                attrs.add("tooltip=\"%s\"".printf(RenderUtils.escape_label(node.icon)));
                dot.append_printf("  %s [%s];\n", safe_id, string.joinv(", ", attrs.to_array()));
                return;
            }
            if (node.icon != null) {
                // A@{ icon: "fa:user" }: the same placeholder, in front of the label
                text = text.length > 0 ? ICON_MARK + " " + text : ICON_MARK;
            }
            if (hides_label) {
                // Bolt: a lightning-like glyph of the text font (the ⚡ emoji drew nothing)
                attrs.add(node.shape == FlowchartNodeShape.BOLT ? "label=\"ϟ\", fontsize=24" : "label=\"\"");
            } else if (is_brace(node.shape)) {
                string sides = node.shape == FlowchartNodeShape.BRACE_LEFT ? "L"
                    : (node.shape == FlowchartNodeShape.BRACE_RIGHT ? "R" : "LR");
                attrs.add("label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLPADDING=\"6\"><TR><TD SIDES=\"%s\">%s</TD></TR></TABLE>>".printf(
                    sides, html_body(text, node.markdown)));
            } else {
                attrs.add("label=%s".printf(format_label(text, node.markdown)));
            }
            attrs.add("shape=%s".printf(shape));

            // Build style attribute — always include "filled" so the node
            // renders with a background color even when a shape-specific style
            // (e.g. "rounded") would otherwise override the global default.
            var style_parts = new Gee.ArrayList<string>();
            bool unfilled = node.shape == FlowchartNodeShape.TEXT_BLOCK || is_brace(node.shape) ||
                            node.shape == FlowchartNodeShape.BOLT;
            style_parts.add(unfilled ? "solid" : "filled");
            if (node.fill_color != null && node.fill_color.length > 0 && !unfilled) {
                string fill = css_color(node.fill_color);
                attrs.add("fillcolor=\"%s\"".printf(fill));
                // Text readable on the node's own fill: the palette text stayed white on
                // light fills such as "style A fill:#ffcc00"
                if (node.font_color == null) {
                    attrs.add("fontcolor=\"%s\"".printf(RenderUtils.contrast_text(fill)));
                }
            } else if (node.shape == FlowchartNodeShape.FILLED_CIRCLE || node.shape == FlowchartNodeShape.FORK_BAR) {
                attrs.add("fillcolor=\"%s\"".printf(palette.node_border));
            }
            if (node.font_color != null && node.font_color.length > 0) {
                attrs.add("fontcolor=\"%s\"".printf(css_color(node.font_color)));
            }

            // Apply shape-specific styles and extra attributes (peripheries, skew, etc.)
            if (base_style.length > 0) {
                string[] parts = base_style.split(",");
                foreach (var part in parts) {
                    string trimmed = part.strip();
                    if (trimmed.length == 0) continue;
                    if (trimmed.has_prefix("style=")) {
                        // Add the style value (e.g. "rounded") to style_parts
                        style_parts.add(trimmed.substring("style=".length));
                    } else {
                        // Add directly as an attribute (peripheries=2, skew=0.3, etc.)
                        attrs.add(trimmed);
                    }
                }
            }
            if (node.stroke_dasharray != null && node.stroke_dasharray.length > 0) {
                style_parts.add("dashed");
            }

            if (style_parts.size > 0) {
                attrs.add("style=\"%s\"".printf(string.joinv(",", style_parts.to_array())));
            }

            // Stroke color
            if (node.stroke_color != null && node.stroke_color.length > 0) {
                attrs.add("color=\"%s\"".printf(css_color(node.stroke_color)));
            }

            // Stroke width
            if (node.stroke_width != null && node.stroke_width.length > 0) {
                attrs.add("penwidth=%s".printf(node.stroke_width));
            }

            // Add link/URL if present
            if (node.href_link != null && node.href_link.length > 0) {
                attrs.add("URL=\"%s\"".printf(RenderUtils.escape_label(node.href_link)));
                attrs.add("target=\"_blank\"");
            }

            // Add tooltip if present
            if (node.tooltip != null && node.tooltip.length > 0) {
                attrs.add("tooltip=\"%s\"".printf(RenderUtils.escape_label(node.tooltip)));
            }

            dot.append_printf("  %s [%s];\n",
                safe_id, string.joinv(", ", attrs.to_array()));

            // (Regions are populated with real bounds in render_to_surface)
        }

        private static bool is_brace(FlowchartNodeShape shape) {
            return shape == FlowchartNodeShape.BRACE_LEFT || shape == FlowchartNodeShape.BRACE_RIGHT ||
                   shape == FlowchartNodeShape.BRACES;
        }

        // Mermaid draws these small symbols without their text
        private static bool shape_hides_label(FlowchartNodeShape shape) {
            switch (shape) {
                case FlowchartNodeShape.SMALL_CIRCLE:
                case FlowchartNodeShape.FILLED_CIRCLE:
                case FlowchartNodeShape.FRAMED_CIRCLE:
                case FlowchartNodeShape.CROSSED_CIRCLE:
                case FlowchartNodeShape.FORK_BAR:
                case FlowchartNodeShape.BOLT:
                case FlowchartNodeShape.HOURGLASS:
                    return true;
                default:
                    return false;
            }
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
                    // >text] has a notched left side: the nearest Graphviz outline is a
                    // cds pointing left (skew on a box was ignored)
                    return "cds";
                case FlowchartNodeShape.RHOMBUS:
                    return "diamond";
                case FlowchartNodeShape.HEXAGON:
                    return "hexagon";
                case FlowchartNodeShape.PARALLELOGRAM:
                    return "parallelogram";
                case FlowchartNodeShape.TRAPEZOID:
                    return "trapezium";
                case FlowchartNodeShape.DOUBLE_CIRCLE:
                    return "doublecircle";
                case FlowchartNodeShape.PARALLELOGRAM_ALT:
                    return "polygon";
                case FlowchartNodeShape.TRAPEZOID_ALT:
                    return "invtrapezium";
                case FlowchartNodeShape.DOCUMENT:
                case FlowchartNodeShape.NOTCHED_RECT:
                    return "note";
                case FlowchartNodeShape.STACKED_RECT:
                    return "box3d";
                case FlowchartNodeShape.TRIANGLE:
                    return "triangle";
                case FlowchartNodeShape.INV_TRIANGLE:
                case FlowchartNodeShape.HOURGLASS:
                    return "invtriangle";
                case FlowchartNodeShape.BOLT:
                case FlowchartNodeShape.TEXT_BLOCK:
                    return "plaintext";
                case FlowchartNodeShape.BRACE_LEFT:
                case FlowchartNodeShape.BRACE_RIGHT:
                case FlowchartNodeShape.BRACES:
                    return "plain";
                case FlowchartNodeShape.SMALL_CIRCLE:
                case FlowchartNodeShape.FILLED_CIRCLE:
                    return "circle";
                case FlowchartNodeShape.FRAMED_CIRCLE:
                    return "doublecircle";
                case FlowchartNodeShape.CROSSED_CIRCLE:
                    return "Mcircle";
                case FlowchartNodeShape.FORK_BAR:
                    return "box";
                case FlowchartNodeShape.NOTCHED_PENTAGON:
                    return "house";
                case FlowchartNodeShape.WINDOW_PANE:
                    return "Msquare";
                case FlowchartNodeShape.BANG:
                    return "star";
                case FlowchartNodeShape.CLOUD:
                    return "ellipse";
                case FlowchartNodeShape.FLAG:
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
                    return ", orientation=180";
                case FlowchartNodeShape.PARALLELOGRAM_ALT:
                    return ", sides=4, skew=-0.4";
                case FlowchartNodeShape.SMALL_CIRCLE:
                case FlowchartNodeShape.FRAMED_CIRCLE:
                    return ", width=0.2, fixedsize=true";
                case FlowchartNodeShape.FILLED_CIRCLE:
                    return ", width=0.15, fixedsize=true";
                case FlowchartNodeShape.CROSSED_CIRCLE:
                case FlowchartNodeShape.HOURGLASS:
                    return ", width=0.3, fixedsize=true";
                case FlowchartNodeShape.FORK_BAR:
                    // A bar across the flow: vertical in LR / RL layouts
                    return sideways ? ", width=0.08, height=1.2, fixedsize=true"
                                    : ", width=1.2, height=0.08, fixedsize=true";
                default:
                    return "";
            }
        }

        // ---- subgraphs ----

        // Cluster names keep the old numbering (top level n, nested parent*100+k) but a
        // name already taken gets a fresh one: nested cluster_1 of cluster_0 merged with
        // the second top-level subgraph
        private void assign_clusters(MermaidFlowchart diagram) {
            cluster_names = new Gee.HashMap<FlowchartSubgraph, string>();
            cluster_anchors = new Gee.HashMap<FlowchartSubgraph, string>();
            empty_anchors = new Gee.HashSet<FlowchartSubgraph>();
            var taken = new Gee.HashSet<string>();
            for (int i = 0; i < diagram.subgraphs.size; i++) {
                string name = "cluster_%d".printf(i);
                cluster_names.set(diagram.subgraphs[i], name);
                taken.add(name);
            }
            int fresh = 0;
            for (int i = 0; i < diagram.subgraphs.size; i++) {
                assign_nested(diagram.subgraphs[i], i, taken, ref fresh);
            }
            foreach (var entry in cluster_names.entries) {
                var first = first_node(entry.key);
                if (first != null) {
                    cluster_anchors.set(entry.key, first.get_safe_id());
                } else {
                    cluster_anchors.set(entry.key, "%s_anchor".printf(entry.value));
                    empty_anchors.add(entry.key);
                }
            }
        }

        private void assign_nested(FlowchartSubgraph sg, int number, Gee.HashSet<string> taken, ref int fresh) {
            for (int k = 0; k < sg.subgraphs.size; k++) {
                int n = number * 100 + k;
                string name = "cluster_%d".printf(n);
                while (taken.contains(name)) {
                    name = "cluster_s%d".printf(fresh++);
                }
                taken.add(name);
                cluster_names.set(sg.subgraphs[k], name);
                assign_nested(sg.subgraphs[k], n, taken, ref fresh);
            }
        }

        private static FlowchartNode? first_node(FlowchartSubgraph sg) {
            if (sg.nodes.size > 0) return sg.nodes[0];
            foreach (var inner in sg.subgraphs) {
                var n = first_node(inner);
                if (n != null) return n;
            }
            return null;
        }

        private static bool subgraph_contains(FlowchartSubgraph sg, FlowchartNode node) {
            if (sg.nodes.contains(node)) return true;
            foreach (var inner in sg.subgraphs) {
                if (subgraph_contains(inner, node)) return true;
            }
            return false;
        }

        private static bool subgraph_within(FlowchartSubgraph outer, FlowchartSubgraph inner) {
            if (outer == inner) return true;
            foreach (var sg in outer.subgraphs) {
                if (subgraph_within(sg, inner)) return true;
            }
            return false;
        }

        // Matches MermaidFlowchartParser.MAX_SUBGRAPH_DEPTH: an AST built by hand could
        // still nest deeper than the stack allows, so the renderer stops descending too.
        private const int MAX_SUBGRAPH_DEPTH = 200;

        private void render_subgraph(StringBuilder dot, FlowchartSubgraph subgraph, int depth = 0) {
            dot.append_printf("  subgraph %s {\n", cluster_names.get(subgraph));
            var sub_palette = ThemeManager.get_active_palette();

            if (subgraph.title != null && subgraph.title.length > 0) {
                dot.append_printf("    label=%s;\n", format_label(subgraph.title, subgraph.title_markdown));
                dot.append("    fontsize=12;\n");
                dot.append("    fontname=\"Sans Bold\";\n");
                // Graphviz draws cluster titles black unless told otherwise
                string title_color = subgraph.font_color != null ? css_color(subgraph.font_color)
                    : (subgraph.fill_color != null ? RenderUtils.contrast_text(css_color(subgraph.fill_color))
                                                   : sub_palette.node_text);
                dot.append("    fontcolor=\"%s\";\n".printf(title_color));
            }

            if (subgraph.has_custom_direction) {
                string rankdir = get_rankdir(subgraph.direction);
                dot.append_printf("    rankdir=%s;\n", rankdir);
            }

            bool dashed = subgraph.stroke_dasharray != null && subgraph.stroke_dasharray.length > 0;
            dot.append("    style=\"rounded,filled%s\";\n".printf(dashed ? ",dashed" : ""));
            dot.append("    color=\"%s\";\n".printf(subgraph.stroke_color != null ? css_color(subgraph.stroke_color) : sub_palette.container_border));
            dot.append("    fillcolor=\"%s\";\n".printf(subgraph.fill_color != null ? css_color(subgraph.fill_color) : sub_palette.grid));
            dot.append("    penwidth=%s;\n".printf(subgraph.stroke_width ?? "2"));

            // An empty subgraph used as an edge end needs a node to attach the edge to
            if (empty_anchors.contains(subgraph)) {
                dot.append_printf("    %s [shape=point, style=invis, width=0.01, label=\"\"];\n",
                    cluster_anchors.get(subgraph));
            }

            // Render nodes in subgraph
            foreach (var node in subgraph.nodes) {
                dot.append_printf("    %s;\n", node.get_safe_id());
            }

            // Render nested subgraphs
            if (depth < MAX_SUBGRAPH_DEPTH) {
                foreach (var nested in subgraph.subgraphs) {
                    render_subgraph(dot, nested, depth + 1);
                }
            }

            dot.append("  }\n\n");
        }

        // ---- edges ----

        private void render_edge(StringBuilder dot, FlowchartEdge edge) {
            string from_id = edge.from.get_safe_id();
            string to_id = edge.to.get_safe_id();

            // Build edge attributes
            var attrs = new Gee.ArrayList<string>();

            // Label
            if (edge.label != null && edge.label.length > 0) {
                attrs.add("label=%s".printf(format_label(edge.label, edge.label_markdown)));
            }

            // Edge style
            bool dashed = edge.stroke_dasharray != null && edge.stroke_dasharray.length > 0;
            if (dashed && edge.edge_type != FlowchartEdgeType.INVISIBLE) {
                attrs.add("style=dashed");
            } else {
                string edge_style = get_edge_style(edge.edge_type);
                if (edge_style.length > 0 &&
                    !(edge.edge_type == FlowchartEdgeType.THICK && edge.edge_thickness != null)) {
                    attrs.add(edge_style);
                }
            }

            // Arrow type
            string arrow_style = get_arrow_style(edge.arrow_type);
            if (arrow_style.length > 0) {
                attrs.add(arrow_style);
            }
            if (edge.tail_arrow_type != FlowchartArrowType.NONE) {
                attrs.add("dir=both");
                attrs.add("arrowtail=%s".printf(arrow_shape(edge.tail_arrow_type)));
            }
            if (edge.arrow_type == FlowchartArrowType.CROSS || edge.tail_arrow_type == FlowchartArrowType.CROSS) {
                // obox placeholder, redrawn as an x by draw_crosses()
                attrs.add("class=\"gdfcross\"");
            }

            // Min length for spacing
            if (edge.min_length > 1) {
                attrs.add("minlen=%d".printf(edge.min_length));
            }

            // Edge styling
            if (edge.edge_color != null && edge.edge_color.length > 0) {
                attrs.add("color=\"%s\"".printf(css_color(edge.edge_color)));
            }

            if (edge.edge_thickness != null && edge.edge_thickness.length > 0) {
                attrs.add("penwidth=%s".printf(edge.edge_thickness));
            }

            if (edge.label_color != null && edge.label_color.length > 0) {
                attrs.add("fontcolor=\"%s\"".printf(css_color(edge.label_color)));
            }

            // Subgraph ends: attach to a node inside the cluster and clip at its border
            if (edge.from_subgraph != null && cluster_names.has_key(edge.from_subgraph)) {
                from_id = cluster_anchors.get(edge.from_subgraph);
                if (!end_inside(edge.from_subgraph, edge.to, edge.to_subgraph)) {
                    attrs.add("ltail=%s".printf(cluster_names.get(edge.from_subgraph)));
                }
            }
            if (edge.to_subgraph != null && cluster_names.has_key(edge.to_subgraph)) {
                to_id = cluster_anchors.get(edge.to_subgraph);
                if (!end_inside(edge.to_subgraph, edge.from, edge.from_subgraph)) {
                    attrs.add("lhead=%s".printf(cluster_names.get(edge.to_subgraph)));
                }
            }

            // Build attribute string
            string attr_str = "";
            if (attrs.size > 0) {
                attr_str = " [" + string.joinv(", ", attrs.to_array()) + "]";
            }

            dot.append_printf("  %s -> %s%s;\n", from_id, to_id, attr_str);
        }

        // Is the other end of the edge inside (or the same as / around) this cluster?
        // lhead/ltail are then invalid for Graphviz.
        private static bool end_inside(FlowchartSubgraph sg, FlowchartNode other, FlowchartSubgraph? other_sg) {
            if (other_sg != null) {
                return subgraph_within(sg, other_sg) || subgraph_within(other_sg, sg);
            }
            return subgraph_contains(sg, other);
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
                default:
                    return "arrowhead=%s".printf(arrow_shape(arrow_type));
            }
        }

        // Mermaid ends: --o is a filled circle, --x a cross (drawn over an obox)
        private static string arrow_shape(FlowchartArrowType arrow_type) {
            switch (arrow_type) {
                case FlowchartArrowType.NORMAL:
                    return "normal";
                case FlowchartArrowType.OPEN:
                case FlowchartArrowType.CIRCLE:
                    return "dot";
                case FlowchartArrowType.CROSS:
                    return "obox";
                case FlowchartArrowType.NONE:
                default:
                    return "none";
            }
        }

        // Replaces the hollow obox arrow placeholders of "gdfcross" edges with an x
        public static uint8[] draw_crosses(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            if (!svg.contains("gdfcross")) {
                return svg_data;
            }
            try {
                var group = new Regex("(class=\"edge gdfcross\">)((?:(?!</g>).)*?)(</g>)", RegexCompileFlags.DOTALL);
                var box = new Regex("<polygon ([^>]*?fill=\"none\"[^>]*?)points=\"([^\"]*)\"\\s*/>");
                svg = group.replace_eval(svg, -1, 0, 0, (gm, result) => {
                    string body = gm.fetch(2);
                    try {
                        body = box.replace_eval(body, -1, 0, 0, (bm, r) => {
                            string[] pts = bm.fetch(2).strip().split(" ");
                            if (pts.length < 4) {
                                r.append(bm.fetch(0));
                                return false;
                            }
                            string[] p0 = pts[0].split(",");
                            string[] p1 = pts[1].split(",");
                            string[] p2 = pts[2].split(",");
                            string[] p3 = pts[3].split(",");
                            if (p0.length != 2 || p1.length != 2 || p2.length != 2 || p3.length != 2) {
                                r.append(bm.fetch(0));
                                return false;
                            }
                            r.append("<path class=\"gdmark\" %sd=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/>".printf(
                                bm.fetch(1), p0[0], p0[1], p2[0], p2[1], p1[0], p1[1], p3[0], p3[1]));
                            return false;
                        });
                    } catch (RegexError e) {
                        // keep the box
                    }
                    result.append(gm.fetch(1));
                    result.append(body);
                    result.append(gm.fetch(3));
                    return false;
                });
            } catch (RegexError e) {
                warning("Failed to draw flowchart cross ends: %s", e.message);
                return svg_data;
            }
            return svg.data;
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidFlowchart diagram) {
            string dot_source = generate_dot(diagram);

            // Parse DOT into graph
            var graph = RenderUtils.read_dot(dot_source);
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
            // Use ABI-compatible wrapper (patched Graphviz uses size_t, VAPI declares unsigned int)
            ret = RenderUtils.render_data(context, graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return draw_crosses(svg_data);
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
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

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

                var element_lines = new Gee.HashMap<string, int>();
                var node_ids = new Gee.HashSet<string>();
                foreach (var node in diagram.nodes) {
                    node_ids.add(node.get_safe_id());
                    if (node.source_line > 0)
                        element_lines.set(node.get_safe_id(), node.source_line);
                }
                // A subgraph is a cluster, and parse_svg_regions only takes a cluster whose
                // title is mapped — without this, clicking a subgraph title or the empty space
                // inside its frame selected nothing. Regions sort smallest first, so a node
                // inside the subgraph, and a nested subgraph, still win over the frame.
                var region_names = new Gee.HashMap<string, string>();
                foreach (var entry in cluster_names.entries) {
                    var sg = entry.key;
                    if (sg.id == null || sg.id.length == 0 || node_ids.contains(sg.id)) continue;
                    region_names.set(entry.value, sg.id);
                    if (sg.source_line > 0 && !element_lines.has_key(sg.id)) {
                        element_lines.set(sg.id, sg.source_line);
                    }
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height,
                                              region_names);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        // Export to PNG
        public bool export_to_png(MermaidFlowchart diagram, string filename) {
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        // Export to SVG
        public bool export_to_svg(MermaidFlowchart diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        // Export to PDF
        public bool export_to_pdf(MermaidFlowchart diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
