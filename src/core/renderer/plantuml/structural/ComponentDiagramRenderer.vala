namespace GDiagram {
    // A cluster whose ports go on its border, for the SVG step in render_to_svg()
    public class PortBorderLayout : Object {
        public string cluster { get; set; }
        public Gee.ArrayList<string> top_ports { get; private set; }
        public Gee.ArrayList<string> bottom_ports { get; private set; }

        public PortBorderLayout(string cluster) {
            this.cluster = cluster;
            this.top_ports = new Gee.ArrayList<string>();
            this.bottom_ports = new Gee.ArrayList<string>();
        }
    }

    // The PlantUML shape draw_shapes() draws for a node or cluster, with its colours
    public class ComponentShapeInfo : Object {
        public string kind { get; set; }
        public string fill { get; set; }
        public string stroke { get; set; }
        public string dash { get; set; }

        public ComponentShapeInfo(string kind, string fill, string stroke, string dash) {
            this.kind = kind;
            this.fill = fill;
            this.stroke = stroke;
            this.dash = dash;
        }
    }

    // One "<$name>" drawn in a label: its sentinel cell, size and colour
    public class SpriteUse : Object {
        public PlantUmlSprite sprite { get; set; }
        public string sentinel { get; set; }
        public int width { get; set; }
        public int height { get; set; }
        public string? color { get; set; default = null; }  // "<$x,color=red>", else the text colour
        public string? tint { get; set; default = null; }   // the label's text colour

        public SpriteUse(PlantUmlSprite sprite, string sentinel, int width, int height) {
            this.sprite = sprite;
            this.sentinel = sentinel;
            this.width = width;
            this.height = height;
        }
    }

    /**
     * Sprites in labels. Graphviz can't draw them: each "<$name>" becomes an em space in a font
     * as large as the sprite, coloured with a unique sentinel, which reserves the sprite's room
     * in the text line. draw() replaces that text in the SVG by the sprite, an embedded
     * grey-level mask filled with the text colour. SVG, PNG, PDF and the preview all come from
     * that SVG. They were dropped.
     */
    public class SpriteCells : Object {
        public Gee.HashMap<string, PlantUmlSprite> sprites { get; private set; }
        public Gee.ArrayList<SpriteUse> uses { get; private set; default = new Gee.ArrayList<SpriteUse>(); }
        private Gee.HashMap<string, string> png_cache = new Gee.HashMap<string, string>();
        // Stands for a use in text that is still to be escaped: U+E000, the use index, U+E001
        private const string MARK_OPEN = "\xee\x80\x80";
        private const string MARK_CLOSE = "\xee\x80\x81";

        public SpriteCells(Gee.HashMap<string, PlantUmlSprite> sprites) {
            this.sprites = sprites;
        }

        /**
         * The HTML for a "<$name>", "<$name,scale=.25>", "<$name{scale=0.5,color=red}>" or
         * "<$name*0.5>" reference, or null for an unknown sprite
         */
        public string? span(string reference, string? tint = null) {
            int index = register(reference, tint);
            return index < 0 ? null : span_html(index);
        }

        private string span_html(int index) {
            var use = uses[index];
            return "<FONT POINT-SIZE=\"%d\" COLOR=\"%s\">&#x2003;</FONT>".printf(
                int.max(use.width, use.height), use.sentinel);
        }

        private int register(string reference, string? tint) {
            string inner = reference;
            if (inner.has_prefix("<$")) {
                inner = inner.substring(2);
            }
            if (inner.has_suffix(">")) {
                inner = inner.substring(0, inner.length - 1);
            }
            int end = 0;
            while (end < inner.length && (inner[end].isalnum() || inner[end] == '_' || inner[end] == '.')) {
                end++;
            }
            string name = inner.substring(0, end);
            if (!sprites.has_key(name)) {
                return -1;
            }
            double scale = 1.0;
            string? color = null;
            string rest = inner.substring(end).replace("{", ",").replace("}", ",");
            if (rest.has_prefix("*")) {
                scale = double.parse(rest.substring(1).split(",")[0]);
            }
            foreach (string part in rest.split(",")) {
                string[] kv = part.split("=", 2);
                if (kv.length != 2) {
                    continue;
                }
                string key = kv[0].strip().down();
                if (key == "scale") {
                    scale = double.parse(kv[1].strip());
                } else if (key == "color") {
                    color = RenderUtils.sanitize_color(kv[1].strip());
                }
            }
            if (scale <= 0 || scale > 100) {
                scale = 1.0;
            }
            var sprite = sprites.get(name);
            string sentinel = "#03%04d".printf(uses.size % 10000);
            int w = int.max(1, (int) Math.round(sprite.width * scale));
            int h = int.max(1, (int) Math.round(sprite.height * scale));
            var use = new SpriteUse(sprite, sentinel, w, h);
            use.color = color;
            use.tint = tint;
            uses.add(use);
            return uses.size - 1;
        }

        // Uses from index `from` on that have no colour yet get `colour`
        public void tint_since(int from, string colour) {
            for (int i = from; i < uses.size; i++) {
                if (uses[i].tint == null) {
                    uses[i].tint = colour;
                }
            }
        }

        // Known sprite references in label text replaced by marks that survive escaping and
        // markup stripping; unknown ones stay
        public string mark(string text) {
            if (!text.contains("<$")) {
                return text;
            }
            var sb = new StringBuilder();
            int pos = 0;
            try {
                MatchInfo mi;
                new Regex("<\\$[^>]*>").match(text, 0, out mi);
                while (mi.matches()) {
                    int ms, me;
                    mi.fetch_pos(0, out ms, out me);
                    string reference = text.substring(ms, me - ms);
                    int index = register(reference, null);
                    sb.append(text.substring(pos, ms - pos));
                    sb.append(index < 0 ? reference : "%s%d%s".printf(MARK_OPEN, index, MARK_CLOSE));
                    pos = me;
                    mi.next();
                }
            } catch (RegexError e) {
                return text;
            }
            sb.append(text.substring(pos));
            return sb.str;
        }

        public static bool has_mark(string text) {
            return text.contains(MARK_OPEN);
        }

        // HTML with the marks replaced by the sprites' spans
        public string resolve(string html) {
            if (!has_mark(html)) {
                return html;
            }
            var sb = new StringBuilder();
            int pos = 0;
            try {
                MatchInfo mi;
                new Regex(MARK_OPEN + "([0-9]+)" + MARK_CLOSE).match(html, 0, out mi);
                while (mi.matches()) {
                    int ms, me;
                    mi.fetch_pos(0, out ms, out me);
                    int index = int.parse(mi.fetch(1));
                    sb.append(html.substring(pos, ms - pos));
                    if (index >= 0 && index < uses.size) {
                        sb.append(span_html(index));
                    }
                    pos = me;
                    mi.next();
                }
            } catch (RegexError e) {
                return html;
            }
            sb.append(html.substring(pos));
            return sb.str;
        }

        // The sentinel texts in Graphviz's SVG replaced by the sprites
        public string draw(string svg, string default_tint) {
            if (uses.size == 0) {
                return svg;
            }
            string result = svg;
            for (int i = 0; i < uses.size; i++) {
                var use = uses[i];
                try {
                    var re = new Regex("<text [^>]*x=\"(-?[0-9.]+)\" y=\"(-?[0-9.]+)\"[^>]*font-size=\"([0-9.]+)\"[^>]*fill=\"%s\"[^>]*>[^<]*</text>".printf(use.sentinel));
                    MatchInfo mi;
                    if (!re.match(result, 0, out mi)) {
                        continue;
                    }
                    int ms, me;
                    mi.fetch_pos(0, out ms, out me);
                    double x = double.parse(mi.fetch(1));
                    double y = double.parse(mi.fetch(2));
                    double size = double.parse(mi.fetch(3));
                    // Centred in the em box: Graphviz gives the line the font size as its height, the baseline
                    // near its bottom, so the middle is about 0.47 em above the baseline
                    double x0 = x + (size - use.width) / 2;
                    double y0 = y - 0.47 * size - use.height / 2.0;
                    string colour = use.color ?? use.tint ?? default_tint;
                    string box = "x=\"%s\" y=\"%s\" width=\"%d\" height=\"%d\"".printf(num(x0), num(y0), use.width, use.height);
                    string drawn = "<mask id=\"gdsprite%d\" maskUnits=\"userSpaceOnUse\" %s><image %s preserveAspectRatio=\"none\" xlink:href=\"data:image/png;base64,%s\"/></mask><rect %s fill=\"%s\" mask=\"url(#gdsprite%d)\"/>".printf(
                        i, box, box, png_base64(use.sprite), box, Markup.escape_text(colour), i);
                    result = result.substring(0, ms) + drawn + result.substring(me);
                } catch (RegexError e) {
                    warning("Sprite regex: %s", e.message);
                }
            }
            return result;
        }

        private static string num(double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, "%.2f");
        }

        // The sprite as a white PNG whose alpha is the ink: a luminance mask
        private string png_base64(PlantUmlSprite sprite) {
            if (png_cache.has_key(sprite.name)) {
                return png_cache.get(sprite.name);
            }
            // Grey + alpha, 8 bits: each row a filter byte, then (white, ink) per pixel
            var raw = new ByteArray();
            for (int y = 0; y < sprite.height; y++) {
                raw.append({ 0 });
                for (int x = 0; x < sprite.width; x++) {
                    raw.append({ 255, sprite.ink[y * sprite.width + x] });
                }
            }
            var png = new ByteArray();
            png.append({ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n' });
            var ihdr = new ByteArray();
            append_be32(ihdr, sprite.width);
            append_be32(ihdr, sprite.height);
            ihdr.append({ 8, 4, 0, 0, 0 });
            append_chunk(png, "IHDR", ihdr.data);
            append_chunk(png, "IDAT", zlib_compress(raw.data));
            append_chunk(png, "IEND", {});
            string encoded = Base64.encode(png.data);
            png_cache.set(sprite.name, encoded);
            return encoded;
        }

        private static void append_be32(ByteArray bytes, uint32 v) {
            bytes.append({ (uint8) (v >> 24), (uint8) (v >> 16), (uint8) (v >> 8), (uint8) v });
        }

        private static void append_chunk(ByteArray png, string type, uint8[] data) {
            append_be32(png, data.length);
            var body = new ByteArray();
            body.append(type.data);
            body.append(data);
            png.append(body.data);
            append_be32(png, crc32(body.data));
        }

        private static uint32 crc32(uint8[] data) {
            uint32 crc = (uint32) 0xFFFFFFFFU;
            foreach (uint8 b in data) {
                crc ^= b;
                for (int k = 0; k < 8; k++) {
                    crc = (crc & 1) != 0 ? (crc >> 1) ^ (uint32) 0xEDB88320U : crc >> 1;
                }
            }
            return crc ^ (uint32) 0xFFFFFFFFU;
        }

        private static uint8[] zlib_compress(uint8[] data) {
            try {
                var output = new MemoryOutputStream.resizable();
                var stream = new ConverterOutputStream(output, new ZlibCompressor(ZlibCompressorFormat.ZLIB, 9));
                size_t written;
                stream.write_all(data, out written);
                stream.close();
                return output.steal_data()[0:output.get_data_size()];
            } catch (Error e) {
                warning("Sprite PNG: %s", e.message);
                return {};
            }
        }
    }

    // A link's style from "skinparam arrow<<stereotype>>"
    public struct LinkSkin {
        public string? color;
        public string? text_color;
        public string? style;   // dashed, dotted
        public int thickness;
    }

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
            string bg_raw = diagram.skin_params.background_color ?? palette.background;
            string bg_color = RenderUtils.fill_color(bg_raw);
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            diagram_font = font_name;
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = RenderUtils.sanitize_color(diagram.skin_params.default_font_color ?? palette.node_text);
            node_font_color = font_color;

            sb.append("digraph component {\n");
            sb.append("  rankdir=%s;\n".printf(diagram.left_to_right ? "LR" : "TB"));
            // "skinparam linetype ortho|polyline": the links' routing was ignored
            string? linetype = diagram.skin_params.get_global("linetype");
            ortho = linetype != null && linetype.strip().down() == "ortho";
            if (ortho) {
                sb.append("  splines=ortho;\n");
            } else if (linetype != null && linetype.strip().down() == "polyline") {
                sb.append("  splines=polyline;\n");
            }
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            string bg_angle = RenderUtils.gradient_stmt(bg_raw);
            if (bg_angle != "") {
                sb.append("  %s\n".printf(bg_angle));
            }
            sb.append("  node [style=\"filled\", fontname=\"%s\", fontsize=%s, fontcolor=\"%s\"];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(
                font_name, RenderUtils.edge_line_color(diagram.skin_params, palette),
                RenderUtils.edge_label_color(diagram.skin_params, palette)));
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

            // Get colors from theme (palette as fallback).
            comp_color_raw = diagram.skin_params.get_element_property("component", "BackgroundColor") ?? palette.component_fill;
            string comp_color = RenderUtils.fill_color(comp_color_raw);
            string comp_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("component", "BorderColor") ?? palette.component_border);
            // Interfaces are small hollow circles as in PlantUML; they were filled dots in the
            // person colour
            iface_fill = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("interface", "BackgroundColor") ?? palette.node_fill);
            iface_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("interface", "BorderColor") ?? palette.node_border);
            pkg_color_raw = diagram.skin_params.get_element_property("package", "BackgroundColor") ?? palette.grid;
            string pkg_color = RenderUtils.fill_color(pkg_color_raw);
            string? style_word = diagram.skin_params.get_global("componentstyle");
            component_style = style_word != null ? style_word.strip().down() : "uml2";
            hide_stereotype = diagram.hide_stereotype;
            sprite_cells = new SpriteCells(diagram.sprites);
            string? arrow_font_size = diagram.skin_params.get_element_property("arrow", "FontSize");
            edge_size_scale = 9.0 / (arrow_font_size != null && int.parse(arrow_font_size) > 0 ? int.parse(arrow_font_size) : 13);
            canvas_color = bg_color;
            node_shapes = new Gee.HashMap<string, ComponentShapeInfo>();
            cluster_shapes = new Gee.HashMap<string, ComponentShapeInfo>();

            // Containers with a port in their body are clusters even without children
            port_parents = new Gee.HashSet<string>();
            foreach (var port in diagram.ports) {
                if (port.parent_component != null) {
                    port_parents.add(RenderUtils.sanitize_id(port.parent_component));
                }
            }

            // Collect container component identifiers — these render as clusters (not nodes),
            // so relationships must use an anchor node as the edge endpoint.
            var container_ids = new Gee.HashSet<string>();
            collect_container_ids(diagram.components, container_ids);
            link_ends_are_actors = has_type(diagram.components, ComponentType.ACTOR) ||
                                   has_type(diagram.components, ComponentType.USECASE);
            var iface_ids = new Gee.HashSet<string>();
            foreach (var iface_decl in diagram.interfaces) {
                iface_ids.add(RenderUtils.sanitize_id(iface_decl.get_identifier()));
            }
            collect_interface_ids(diagram.components, iface_ids);
            var enclosing = new Gee.HashMap<string, Gee.HashSet<string>>();
            innermost = new Gee.HashMap<string, string>();
            collect_enclosing(diagram.components, new Gee.ArrayList<string>(), enclosing);
            cluster_names = new Gee.HashMap<string, string>();
            skin = diagram.skin_params;

            // Names used only in links. In a component or deployment diagram PlantUML draws
            // them as interfaces (a small circle, the name below); they were Graphviz's
            // default grey ellipse with the name inside. With actors or use cases around
            // they are actors.
            var known = new Gee.HashSet<string>();
            collect_known_ids(diagram.components, known);
            foreach (var iface in diagram.interfaces) {
                known.add(RenderUtils.sanitize_id(iface.get_identifier()));
            }
            foreach (var port in diagram.ports) {
                known.add(RenderUtils.sanitize_id(port.id));
            }
            foreach (var note in diagram.notes) {
                known.add(RenderUtils.sanitize_id(note.id));
            }
            var implicit_ends = new Gee.ArrayList<string>();
            var implicit_ids = new Gee.HashSet<string>();
            foreach (var rel in diagram.relationships) {
                foreach (string end in new string[] { rel.from_id, rel.to_id }) {
                    string end_id = RenderUtils.sanitize_id(end);
                    if (!known.contains(end_id) && !implicit_ids.contains(end_id)) {
                        implicit_ids.add(end_id);
                        implicit_ends.add(end);
                        if (!link_ends_are_actors) {
                            iface_ids.add(end_id);
                        }
                    }
                }
            }
            // Ports declared in a container body are drawn on its cluster's border
            container_ports = new Gee.HashMap<string, Gee.ArrayList<ComponentPort>>();
            port_on_top = new Gee.HashMap<string, bool>();
            port_parent = new Gee.HashMap<string, string>();
            port_layouts = new Gee.ArrayList<PortBorderLayout>();
            left_to_right = diagram.left_to_right;
            foreach (var port in diagram.ports) {
                if (port.parent_component != null &&
                    container_ids.contains(RenderUtils.sanitize_id(port.parent_component))) {
                    string key = RenderUtils.sanitize_id(port.parent_component);
                    if (!container_ports.has_key(key)) {
                        container_ports.set(key, new Gee.ArrayList<ComponentPort>());
                    }
                    container_ports.get(key).add(port);
                    string port_id = RenderUtils.sanitize_id(port.id);
                    port_on_top.set(port_id, port_goes_on_top(port, diagram.relationships));
                    port_parent.set(port_id, key);
                }
            }

            // Clusters whose anchor a link or note ends at, or whose ports need it
            var anchor_used = new Gee.HashSet<string>();
            foreach (var rel in diagram.relationships) {
                foreach (string end in new string[] { rel.from_id, rel.to_id }) {
                    if (container_ids.contains(RenderUtils.sanitize_id(end))) {
                        anchor_used.add(RenderUtils.sanitize_id(end));
                    }
                }
            }
            foreach (var note in diagram.notes) {
                if (note.attached_to != null && container_ids.contains(RenderUtils.sanitize_id(note.attached_to))) {
                    anchor_used.add(RenderUtils.sanitize_id(note.attached_to));
                }
            }
            foreach (var port in diagram.ports) {
                if (port.parent_component != null && container_ids.contains(RenderUtils.sanitize_id(port.parent_component))) {
                    anchor_used.add(RenderUtils.sanitize_id(port.parent_component));
                }
            }
            // "-right->" / "Rel_R" between nodes in different containers ("c1 -RIGHT->> c2" with c2
            // in a boundary): rank=same would pull a node out of its cluster, so these were
            // laid out top to bottom. As PlantUML does, the link may have length 0 (minlen=0),
            // which puts both ends in one rank; an end sitting directly in the containers' common
            // parent goes into an invisible cluster of its own, without which dot ordered it
            // after the other end's cluster.
            side_links = new Gee.HashSet<ComponentRelationship>();
            side_wrapped = new Gee.HashSet<string>();
            // The containers around such links' ends leave out their anchor when nothing uses
            // it: an invisible node in the ends' rank, it pushed the link's label above the nodes
            var side_containers = new Gee.HashSet<string>();
            foreach (var rel in diagram.relationships) {
                if ((rel.placement != "left" && rel.placement != "right") || rel.mid_ball) {
                    continue;
                }
                string a = RenderUtils.sanitize_id(rel.from_id);
                string b = RenderUtils.sanitize_id(rel.to_id);
                if (a == b || container_ids.contains(a) || container_ids.contains(b) ||
                    port_parent.has_key(a) || port_parent.has_key(b)) {
                    continue;
                }
                string pa = innermost.has_key(a) ? innermost.get(a) : "";
                string pb = innermost.has_key(b) ? innermost.get(b) : "";
                if (pa == pb) {
                    continue;  // rank=same in append_decorated_link()
                }
                side_links.add(rel);
                string common = common_container(pa, pb);
                if (pa == common) {
                    side_wrapped.add(a);
                }
                if (pb == common) {
                    side_wrapped.add(b);
                }
                foreach (string parent in new string[] { pa, pb }) {
                    for (string cur = parent; cur != ""; cur = innermost.has_key(cur) ? innermost.get(cur) : "") {
                        side_containers.add(cur);
                    }
                }
            }
            anchored = new Gee.HashSet<string>();
            foreach (string cid in container_ids) {
                if (anchor_used.contains(cid) || !side_containers.contains(cid)) {
                    anchored.add(cid);
                }
            }

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
                // A small circle with the name underneath, as PlantUML draws interfaces.
                // The name inside blew the circle up to the width of the text, and an
                // xlabel collided with neighbouring names. Links attach to port "c".
                sb.append("  %s [%s];\n".printf(id, icon_node_attrs(id, "interface", null,
                    html_text(iface.get_display_label()), iface_fill, iface_border, null, "")));
            }

            // Render ports
            if (diagram.ports.size > 0) {
                sb.append("\n  // Ports\n");
                foreach (var port in diagram.ports) {
                    if (port.parent_component != null &&
                        container_ids.contains(RenderUtils.sanitize_id(port.parent_component))) {
                        continue;  // drawn inside its container
                    }
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
                        string port_clip = "";
                        if (container_ids.contains(parent_id)) {
                            port_clip = ", lhead=%s".printf(cluster_names.get(parent_id));
                            parent_id = parent_id + "_anchor";
                        }
                        sb.append("  %s -> %s [style=dotted, arrowhead=none%s];\n".printf(id, parent_id, port_clip));
                    }
                }
            }

            // Names used only in links: interfaces, or actors next to actors / use cases
            foreach (string end in implicit_ends) {
                sb.append("  %s;\n".printf(implicit_end_node(RenderUtils.sanitize_id(end), end)));
            }

            // Render relationships
            sb.append("\n  // Relationships\n");
            int ball_idx = 0;
            foreach (var rel in diagram.relationships) {
                string from_id = RenderUtils.sanitize_id(rel.from_id);
                string to_id = RenderUtils.sanitize_id(rel.to_id);

                // Container components render as clusters. The edge runs to the anchor
                // inside the cluster and ltail/lhead clip it at the border; unclipped it
                // ended at a point beside the box. No clipping when the other end is
                // inside that same container.
                string clip = "";
                string raw_from = from_id;
                string raw_to = to_id;
                if (container_ids.contains(raw_from)) {
                    from_id = raw_from + "_anchor";
                    if (raw_to != raw_from && !is_enclosed_by(enclosing, raw_to, raw_from)) {
                        clip += ", ltail=%s".printf(cluster_names.get(raw_from));
                    }
                }
                if (container_ids.contains(raw_to)) {
                    to_id = raw_to + "_anchor";
                    if (raw_to != raw_from && !is_enclosed_by(enclosing, raw_from, raw_to)) {
                        clip += ", lhead=%s".printf(cluster_names.get(raw_to));
                    }
                }

                // Links to an interface attach to its circle, not its caption
                if (iface_ids.contains(raw_from)) {
                    from_id = raw_from + ":c";
                }
                if (iface_ids.contains(raw_to)) {
                    to_id = raw_to + ":c";
                }
                // Links to a border port attach to its square, on the side facing the other end
                if (port_on_top.has_key(raw_from)) {
                    from_id = port_endpoint(raw_from, raw_to, enclosing);
                }
                if (port_on_top.has_key(raw_to)) {
                    to_id = port_endpoint(raw_to, raw_from, enclosing);
                }

                var link_skin = arrow_stereotype_skin(rel);
                string style = rel.is_dashed ? "dashed" : "solid";
                if (rel.line_style == null && link_skin.style != null &&
                    (link_skin.style == "dashed" || link_skin.style == "dotted")) {
                    style = link_skin.style;
                }
                string arrowhead = rel.right_arrow ? "vee" : "none";
                string arrowtail = rel.left_arrow ? "vee" : "none";

                // Handle special relationship types
                switch (rel.relation_type) {
                    case ComponentRelationType.AGGREGATION:
                        if (rel.marker_at_head) {
                            arrowhead = "odiamond";
                        } else {
                            arrowtail = "odiamond";
                        }
                        break;
                    case ComponentRelationType.COMPOSITION:
                        if (rel.marker_at_head) {
                            arrowhead = "diamond";
                        } else {
                            arrowtail = "diamond";
                        }
                        break;
                    default:
                        break;
                }

                if (rel.decorated) {
                    append_decorated_link(sb, rel, link_skin, from_id, to_id, clip, style, arrowtail, arrowhead,
                                          RenderUtils.edge_line_color(diagram.skin_params, palette), enclosing, ref ball_idx);
                    continue;
                }

                var attrs = new StringBuilder();
                attrs.append("style=%s".printf(style));
                attrs.append(", arrowhead=%s".printf(arrowhead));
                if (arrowtail != "none") {
                    attrs.append(", arrowtail=%s, dir=both".printf(arrowtail));
                }

                attrs.append(edge_label_attr(rel));

                attrs.append(link_paint_attrs(rel, link_skin));
                attrs.append(multiplicity_attrs(rel.tail_label, rel.head_label));

                attrs.append(clip);
                sb.append("  %s -> %s [%s];\n".printf(from_id, to_id, attrs.str));
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color_raw = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary;
                string note_color = RenderUtils.fill_color(note_color_raw);
                string note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_color));

                foreach (var note in diagram.notes) {
                    string note_id = RenderUtils.sanitize_id(note.id);
                    string fill = note.color != null ? RenderUtils.fill_color(note.color) : note_color;
                    string font = note.color != null ? RenderUtils.contrast_text(fill) : note_font;
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"%s, fontcolor=\"%s\"];\n".printf(
                        note_id, RenderUtils.escape_label(RenderUtils.strip_inline_creole(note.text)), fill,
                        RenderUtils.gradient_attr(note.color ?? note_color_raw), font));

                    if (note.attached_to != null) {
                        string attached_id = RenderUtils.sanitize_id(note.attached_to);
                        // Container components render as clusters, not nodes. Without the
                        // anchor redirect Graphviz invents a default ellipse node named
                        // after the alias and the note points at that bubble instead.
                        string note_clip = "";
                        bool on_cluster = container_ids.contains(attached_id);
                        if (on_cluster) {
                            note_clip = ", lhead=%s".printf(cluster_names.get(attached_id));
                            attached_id = attached_id + "_anchor";
                        }
                        if (iface_ids.contains(RenderUtils.sanitize_id(note.attached_to))) {
                            attached_id += ":c";
                        }
                        // "note left/right of X" beside X, "note bottom of X" below it. Every
                        // note was drawn above its element. A rank constraint would pull an
                        // element out of its container, so nested targets keep the default.
                        string target_node = attached_id.split(":")[0];
                        bool nested = on_cluster || (enclosing.has_key(target_node) && enclosing.get(target_node).size > 0);
                        bool side = note.position == "left" || note.position == "right";
                        if (side && !nested) {
                            if (note.position == "right") {
                                sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(attached_id, note_id));
                            } else {
                                sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(note_id, attached_id));
                            }
                            sb.append("  { rank=same; %s; %s; }\n".printf(note_id, target_node));
                        } else if (note.position == "bottom") {
                            sb.append("  %s -> %s [style=dashed, arrowhead=none%s];\n".printf(
                                attached_id, note_id, note_clip.replace("lhead", "ltail")));
                        } else {
                            sb.append("  %s -> %s [style=dashed, arrowhead=none%s];\n".printf(note_id, attached_id, note_clip));
                        }
                    }
                }
            }

            sb.append("}\n");

            string result = add_legend(sb.str, "  // Components\n", diagram.legend, diagram.skin_params, sprite_cells);
            sprite_cells.tint_since(0, node_font_color);
            return result;
        }

        // ── Legend ─────────────────────────────────────────────────────────
        // "legend ... endlegend" was dropped. Graphviz can't place a node outside the layout,
        // so the diagram body goes into an unframed cluster whose label is the legend: at its
        // top or bottom, left, right or centre, like PlantUML (bottom centre by default). The
        // graph label stays free for the title. Shared with ClassDiagramRenderer.

        /** `dot` with its body from `body_marker` to the final "}" wrapped in the legend cluster. */
        public static string add_legend(string dot, string body_marker, DiagramLegend? legend, SkinParams skin,
                                        SpriteCells? sprites = null) {
            if (legend == null || legend.text.strip().length == 0) {
                return dot;
            }
            int body = dot.index_of(body_marker);
            int close = dot.last_index_of("}");
            if (body < 0 || close < body) {
                return dot;
            }
            var palette = ThemeManager.get_active_palette();
            string fill = RenderUtils.sanitize_color(skin.get_element_property("legend", "BackgroundColor") ?? palette.node_fill);
            string border = RenderUtils.sanitize_color(skin.get_element_property("legend", "BorderColor") ?? palette.node_border);
            string? font_set = skin.get_element_property("legend", "FontColor");
            string font = legend_text_colour(font_set != null ? RenderUtils.sanitize_color(font_set) : RenderUtils.contrast_text(fill));

            var sb = new StringBuilder();
            sb.append(dot.substring(0, body));
            sb.append("  subgraph cluster_legend {\n");
            sb.append(dot.substring(body, close - body));
            // The cluster's own attributes after the body: set before it, the clusters inside
            // would inherit them (no frames, titles at the legend's corner)
            sb.append("  // Legend\n");
            sb.append("  peripheries=0;\n  bgcolor=\"transparent\";\n");
            sb.append("  labelloc=%s;\n  labeljust=%s;\n".printf(
                legend.valign == "top" ? "t" : "b",
                legend.halign == "left" ? "l" : (legend.halign == "right" ? "r" : "c")));
            sb.append("  fontname=\"Sans\";\n  fontsize=10;\n  fontcolor=\"%s\";\n".printf(font));
            sb.append("  label=<%s>;\n".printf(legend_html(legend.text, fill, border, sprites, font)));
            sb.append("  }\n");
            sb.append(dot.substring(close));
            return sb.str;
        }

        // Graphviz writes no fill for black text, and fill_svg_background() then gives such
        // text the colour contrasting with the canvas, not with the legend box: white on a
        // light legend in the dark theme. A black that isn't "#000000" keeps its fill.
        private static string legend_text_colour(string colour) {
            string c = colour.strip().down();
            return c == "#000000" || c == "black" || c == "#000" ? "#010101" : colour;
        }

        // The legend box: text lines left-aligned with creole, "|= a |= b |" / "| <#color> | c |"
        // rows as a table
        private static string legend_html(string text, string fill, string border, SpriteCells? sprites, string font) {
            var rows = new StringBuilder();
            string[] lines = text.split("\n");
            // "<#color>| a | b |": a table row with a colour for all its cells
            for (int k = 0; k < lines.length; k++) {
                string l = lines[k].strip();
                int close = l.has_prefix("<#") ? l.index_of(">|") : -1;
                if (close > 0) {
                    string colour = l.substring(0, close + 1);
                    string row = l.substring(close + 1);
                    var cells = new StringBuilder();
                    foreach (string cell in row.substring(1).split("|")) {
                        if (cells.len > 0) {
                            cells.append("|");
                        }
                        string c = cell.strip();
                        bool header = c.has_prefix("=");
                        if (c.length > 0 && !c.has_prefix("<#")) {
                            c = (header ? "= " : "") + colour + (header ? c.substring(1) : c);
                        }
                        cells.append(c);
                    }
                    lines[k] = "|" + cells.str;
                }
            }
            int i = 0;
            while (i < lines.length) {
                if (lines[i].strip().has_prefix("|")) {
                    var table = new StringBuilder();
                    while (i < lines.length && lines[i].strip().has_prefix("|")) {
                        table.append(legend_table_row(lines[i].strip(), sprites, font));
                        i++;
                    }
                    rows.append("<TR><TD ALIGN=\"LEFT\"><TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"3\" COLOR=\"%s\">%s</TABLE></TD></TR>".printf(
                        border, table.str));
                } else {
                    var block = new StringBuilder();
                    while (i < lines.length && !lines[i].strip().has_prefix("|")) {
                        block.append(legend_cell_html(lines[i].strip()));
                        block.append("<BR ALIGN=\"LEFT\"/>");
                        i++;
                    }
                    rows.append("<TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">%s</TD></TR>".printf(block.str));
                }
            }
            return "<TABLE BORDER=\"1\" CELLBORDER=\"0\" STYLE=\"rounded\" CELLSPACING=\"2\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">%s</TABLE>".printf(
                fill, border, rows.str);
        }

        private static string legend_table_row(string line, SpriteCells? sprites, string font) {
            string inner = line.substring(1);
            if (inner.has_suffix("|")) {
                inner = inner.substring(0, inner.length - 1);
            }
            var row = new StringBuilder("<TR>");
            foreach (string raw in inner.split("|")) {
                string cell = raw.strip();
                bool header = cell.has_prefix("=");
                if (header) {
                    cell = cell.substring(1).strip();
                }
                string? bg = null;
                int end = cell.has_prefix("<#") ? cell.index_of(">") : -1;
                if (end > 2) {
                    // "<#transparent,#transparent>": the cell colour, then the border colour
                    bg = RenderUtils.sanitize_color(cell.substring(1, end - 1).split(",")[0]);
                    cell = cell.substring(end + 1).strip();
                }
                string content = legend_cell_html(cell, sprites,
                    bg != null ? legend_text_colour(RenderUtils.contrast_text(bg)) : font);
                if (content.length > 0 && header) {
                    content = "<B>%s</B>".printf(content);
                }
                if (bg != null) {
                    if (content.length > 0) {
                        content = "<FONT COLOR=\"%s\">%s</FONT>".printf(
                            legend_text_colour(RenderUtils.contrast_text(bg)), content);
                    }
                    row.append("<TD BGCOLOR=\"%s\" WIDTH=\"24\" ALIGN=\"LEFT\">%s</TD>".printf(bg, content));
                } else {
                    row.append("<TD ALIGN=\"LEFT\">%s</TD>".printf(content));
                }
            }
            row.append("</TR>");
            return row.str;
        }

        // Component id -> Graphviz cluster name, filled while containers are emitted
        private Gee.HashMap<string, string> cluster_names = new Gee.HashMap<string, string>();
        // Container id -> ports declared in its body
        private Gee.HashMap<string, Gee.ArrayList<ComponentPort>> container_ports =
            new Gee.HashMap<string, Gee.ArrayList<ComponentPort>>();
        // In a diagram with actors or use cases, names used only in links are actors
        private bool link_ends_are_actors = false;
        // Container port id -> drawn on the top (true) or bottom (false) border
        private Gee.HashMap<string, bool> port_on_top = new Gee.HashMap<string, bool>();
        private Gee.HashMap<string, string> port_parent = new Gee.HashMap<string, string>();
        private Gee.ArrayList<PortBorderLayout> port_layouts = new Gee.ArrayList<PortBorderLayout>();
        private bool left_to_right = false;

        // portin on the top border, portout on the bottom one. A plain port goes on top
        // unless it is only ever a link's source.
        private static bool port_goes_on_top(ComponentPort port, Gee.ArrayList<ComponentRelationship> rels) {
            if (port.port_type != PortType.BIDIRECTIONAL) {
                return port.port_type == PortType.IN;
            }
            bool source = false;
            foreach (var rel in rels) {
                if (rel.to_id == port.id) {
                    return true;
                }
                source = source || rel.from_id == port.id;
            }
            return !source;
        }

        // "p1:sq:n": the port's square, entered from outside the container on the border's
        // outer side and from inside on its inner side
        private string port_endpoint(string port_id, string other_id, Gee.HashMap<string, Gee.HashSet<string>> enclosing) {
            bool top = port_on_top.get(port_id);
            string parent = port_parent.get(port_id);
            // another port of this container (or of one nested in it) counts as inside
            string other_node = port_parent.has_key(other_id) ? port_parent.get(other_id) : other_id;
            bool other_inside = other_node == parent || is_enclosed_by(enclosing, other_node, parent);
            // the first-rank side: outside of a top port, inside of a bottom port
            bool min_side = top != other_inside;
            string compass = left_to_right ? (min_side ? "w" : "e") : (min_side ? "n" : "s");
            return "%s:sq:%s".printf(port_id, compass);
        }

        private static string join_ids(Gee.ArrayList<string> ids) {
            var sb = new StringBuilder();
            foreach (string id in ids) {
                if (sb.len > 0) {
                    sb.append("; ");
                }
                sb.append(id);
            }
            return sb.str;
        }

        // Graphviz node ids of everything drawn inside these components
        private void collect_node_ids(Gee.ArrayList<Component> comps, Gee.ArrayList<string> ids) {
            foreach (var c in comps) {
                string cid = RenderUtils.sanitize_id(c.get_identifier());
                if (is_cluster(c)) {
                    collect_node_ids(c.children, ids);
                    if (anchored.contains(cid)) {
                        ids.add(cid + "_anchor");
                    }
                    if (container_ports.has_key(cid)) {
                        foreach (var port in container_ports.get(cid)) {
                            ids.add(RenderUtils.sanitize_id(port.id));
                        }
                    }
                } else {
                    ids.add(cid);
                }
            }
        }
        // Node id -> id of the container drawn directly around it
        private Gee.HashMap<string, string> innermost = new Gee.HashMap<string, string>();
        // Containers named as a port's parent: clusters even with no children
        private Gee.HashSet<string> port_parents = new Gee.HashSet<string>();
        private bool ortho = false;
        private bool hide_stereotype = false;
        private SpriteCells sprite_cells = new SpriteCells(new Gee.HashMap<string, PlantUmlSprite>());
        // Edge label <size:N>: our edge font size over PlantUML's
        private double edge_size_scale = 9.0 / 13.0;
        // Containers that get an anchor node
        private Gee.HashSet<string> anchored = new Gee.HashSet<string>();
        // Left/right links between different containers (minlen=0), and the ends drawn in an
        // invisible cluster of their own for them
        private Gee.HashSet<ComponentRelationship> side_links = new Gee.HashSet<ComponentRelationship>();
        private Gee.HashSet<string> side_wrapped = new Gee.HashSet<string>();
        private int side_idx = 0;
        private string component_style = "uml2";
        private string canvas_color = "#FFFFFF";
        private string iface_fill = "#FFFFFF";
        private string iface_border = "#000000";
        // Node id / cluster name -> the shape draw_shapes() draws over Graphviz's
        private Gee.HashMap<string, ComponentShapeInfo> node_shapes = new Gee.HashMap<string, ComponentShapeInfo>();
        private Gee.HashMap<string, ComponentShapeInfo> cluster_shapes = new Gee.HashMap<string, ComponentShapeInfo>();
        // Background of the HTML cell that draw_shapes() replaces by an icon
        public const string SENTINEL = "#010207";
        private string diagram_font = "Sans";
        private string node_font_color = "#000000";  // the graph-wide node fontcolor
        private SkinParams? skin = null;
        // component / package BackgroundColor as written, for their gradient angle
        private string comp_color_raw = "";
        private string pkg_color_raw = "";

        // Records, for every component, the containers drawn around it
        private void collect_enclosing(Gee.ArrayList<Component> comps, Gee.ArrayList<string> stack,
                                       Gee.HashMap<string, Gee.HashSet<string>> enclosing) {
            foreach (var comp in comps) {
                string cid = RenderUtils.sanitize_id(comp.get_identifier());
                if (!enclosing.has_key(cid)) {
                    var outer = new Gee.HashSet<string>();
                    outer.add_all(stack);
                    enclosing.set(cid, outer);
                    if (stack.size > 0) {
                        innermost.set(cid, stack[stack.size - 1]);
                    }
                }
                if (is_cluster(comp)) {
                    stack.add(cid);
                    collect_enclosing(comp.children, stack, enclosing);
                    stack.remove_at(stack.size - 1);
                }
            }
        }

        private bool is_enclosed_by(Gee.HashMap<string, Gee.HashSet<string>> enclosing, string id, string container_id) {
            return enclosing.has_key(id) && enclosing.get(id).contains(container_id);
        }

        // Interfaces declared inside containers ("node N { interface I }")
        private void collect_interface_ids(Gee.ArrayList<Component> comps, Gee.HashSet<string> ids) {
            foreach (var c in comps) {
                if ((c.component_type == ComponentType.INTERFACE || (c.link_end && !link_ends_are_actors)) && !is_cluster(c)) {
                    ids.add(RenderUtils.sanitize_id(c.get_identifier()));
                }
                collect_interface_ids(c.children, ids);
            }
        }

        private bool has_type(Gee.ArrayList<Component> comps, ComponentType type) {
            foreach (var c in comps) {
                if (c.component_type == type || has_type(c.children, type)) {
                    return true;
                }
            }
            return false;
        }

        private void collect_known_ids(Gee.ArrayList<Component> comps, Gee.HashSet<string> known) {
            foreach (var c in comps) {
                known.add(RenderUtils.sanitize_id(c.get_identifier()));
                known.add(RenderUtils.sanitize_id(c.id));
                collect_known_ids(c.children, known);
            }
        }

        // taillabel / headlabel for link multiplicities ("1", "many")
        private static string multiplicity_attrs(string? tail, string? head) {
            var sb = new StringBuilder();
            if (tail != null && tail.length > 0) {
                sb.append(", taillabel=\"%s\"".printf(RenderUtils.escape_label(tail)));
            }
            if (head != null && head.length > 0) {
                sb.append(", headlabel=\"%s\"".printf(RenderUtils.escape_label(head)));
            }
            return sb.str;
        }

        private static string clip_part(string clip, string key) {
            int i = clip.index_of(", " + key + "=");
            if (i < 0) {
                return "";
            }
            int j = clip.index_of(",", i + 2);
            return j < 0 ? clip.substring(i) : clip.substring(i, j - i);
        }

        // A link with a ball/socket, end markers beyond the classic ones, a dotted or
        // bold line, or a direction word. A ball on the line is a small circle node
        // splitting the edge; its sockets are half-circle arrow ends against it.
        private void append_decorated_link(StringBuilder sb, ComponentRelationship rel, LinkSkin link_skin,
                                           string from_id, string to_id,
                                           string clip, string style, string arrowtail, string arrowhead,
                                           string edge_color, Gee.HashMap<string, Gee.HashSet<string>> enclosing,
                                           ref int ball_idx) {
            string line = rel.line_style ?? style;
            string tail_shape = rel.tail_marker ?? arrowtail;
            string head_shape = rel.head_marker ?? arrowhead;
            bool left_socket = rel.mid_left_socket;
            bool right_socket = rel.mid_right_socket;
            string a = from_id;
            string b = to_id;
            string a_clip = clip_part(clip, "ltail");
            string b_clip = clip_part(clip, "lhead");
            // "-up->" / "-left->": draw from the target back to the source, so ranking
            // and left-to-right order place the target above / to the left
            if (rel.placement == "up" || rel.placement == "left") {
                a = to_id;
                b = from_id;
                string t = tail_shape;
                tail_shape = head_shape;
                head_shape = t;
                bool s = left_socket;
                left_socket = right_socket;
                right_socket = s;
                string c = a_clip;
                a_clip = b_clip.replace("lhead", "ltail");
                b_clip = c.replace("ltail", "lhead");
            }
            string color = link_paint_attrs(rel, link_skin);
            if (side_links.contains(rel)) {
                color += ", minlen=0";
            }
            string label = edge_label_attr(rel);
            // Multiplicities stay at their written ends when the edge is drawn reversed
            bool reversed = rel.placement == "up" || rel.placement == "left";
            string mult_a = reversed ? multiplicity_attrs(rel.head_label, null) : multiplicity_attrs(rel.tail_label, null);
            string mult_b = reversed ? multiplicity_attrs(null, rel.tail_label) : multiplicity_attrs(null, rel.head_label);
            // "+" ends: RenderUtils.draw_custom_markers() draws the plus into the odot circle
            // of the named end, so "0--+" doesn't put it into the plain circle
            string ball_id = "";
            if (!rel.mid_ball) {
                // After an up/left swap the written tail end is drawn at b
                string plus = RenderUtils.plus_marker_class(reversed ? rel.plus_head : rel.plus_tail,
                                                            reversed ? rel.plus_tail : rel.plus_head);
                sb.append("  %s -> %s [style=%s, arrowtail=%s, arrowhead=%s, dir=both%s%s%s%s%s];\n".printf(
                    a, b, line, tail_shape, head_shape, color, label + mult_a + mult_b, a_clip, b_clip, plus));
            } else {
                ball_id = "_link_ball%d".printf(ball_idx++);
                // After an up/left swap the written tail end is drawn at b
                bool swapped = rel.placement == "up" || rel.placement == "left";
                bool plus_a = swapped ? rel.plus_head : rel.plus_tail;
                bool plus_b = swapped ? rel.plus_tail : rel.plus_head;
                sb.append("  %s [label=\"\", shape=circle, width=0.14, height=0.14, fixedsize=true, style=solid, color=\"%s\"];\n".printf(
                    ball_id, RenderUtils.sanitize_color(rel.color ?? edge_color).split(":")[0]));
                sb.append("  %s -> %s [style=%s, arrowtail=%s, arrowhead=%s, dir=both%s%s%s];\n".printf(
                    a, ball_id, line, tail_shape, left_socket ? "icurve" : "none", color, a_clip + mult_a, RenderUtils.plus_marker_class(plus_a, false)));
                sb.append("  %s -> %s [style=%s, arrowtail=%s, arrowhead=%s, dir=both%s%s%s%s];\n".printf(
                    ball_id, b, line, right_socket ? "icurve" : "none", head_shape, color, label + mult_b, b_clip, RenderUtils.plus_marker_class(false, plus_b)));
            }
            // Side by side for "-left->" / "-right->", unless an end is a container anchor or
            // sits inside a container: a root-level rank=same pulls such a node out of its
            // cluster, leaving the container an empty box. The reversed edge still orders them.
            string a_node = a.split(":")[0];  // rank lists take node IDs, not ports
            string b_node = b.split(":")[0];
            bool a_nested = (enclosing.has_key(a_node) && enclosing.get(a_node).size > 0) || port_parent.has_key(a_node);
            bool b_nested = (enclosing.has_key(b_node) && enclosing.get(b_node).size > 0) || port_parent.has_key(b_node);
            if ((rel.placement == "left" || rel.placement == "right") &&
                !a_node.has_suffix("_anchor") && !b_node.has_suffix("_anchor") && !a_nested && !b_nested) {
                if (ball_id.length > 0) {
                    sb.append("  { rank=same; %s; %s; %s; }\n".printf(a_node, ball_id, b_node));
                } else {
                    sb.append("  { rank=same; %s; %s; }\n".printf(a_node, b_node));
                }
            } else if ((rel.placement == "left" || rel.placement == "right") &&
                       !a_node.has_suffix("_anchor") && !b_node.has_suffix("_anchor") &&
                       !port_parent.has_key(a_node) && !port_parent.has_key(b_node) &&
                       innermost.has_key(a_node) && innermost.has_key(b_node) &&
                       innermost.get(a_node) == innermost.get(b_node) &&
                       cluster_names.has_key(innermost.get(a_node))) {
                // Both ends in the same container: side by side inside that cluster (the
                // subgraph is reopened by name), which keeps them in it. "HTTP - [First]" in a
                // package was drawn top to bottom.
                string ranks = ball_id.length > 0 ? "%s; %s; %s;".printf(a_node, ball_id, b_node)
                                                  : "%s; %s;".printf(a_node, b_node);
                sb.append("  subgraph %s { { rank=same; %s } }\n".printf(cluster_names.get(innermost.get(a_node)), ranks));
            }
        }

        // Colour(s), pen width and label colour of a link: "-[#blue;#green]->" draws both
        // colours (only the last was used), "-[thickness=8]->" and "line.bold" widen the pen,
        // "text:red" colours the label
        private static string link_paint_attrs(ComponentRelationship rel, LinkSkin link_skin) {
            var sb = new StringBuilder();
            int thickness = rel.thickness > 0 ? rel.thickness : link_skin.thickness;
            string? text_color = rel.text_color ?? link_skin.text_color;
            if (rel.colors.size > 1) {
                var list = new StringBuilder();
                foreach (string c in rel.colors) {
                    if (list.len > 0) {
                        list.append(":");
                    }
                    list.append(RenderUtils.sanitize_color(c));
                }
                sb.append(", color=\"%s\"".printf(list.str));
            } else if (rel.color != null) {
                sb.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(rel.color)));
            } else if (link_skin.color != null) {
                sb.append(", color=\"%s\"".printf(link_skin.color));
            }
            if (thickness > 0) {
                sb.append(", penwidth=%d".printf(thickness));
                // Graphviz scales the arrowhead with the pen; at thickness 8 it was a blot
                if (thickness > 2) {
                    sb.append(", arrowsize=0.5");
                }
            }
            if (text_color != null) {
                sb.append(", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(text_color)));
            }
            return sb.str;
        }

        /**
         * "skinparam arrow<<async>> { Color blue;text:blue;line.dashed }" as C4's AddRelTag writes
         * it, and the FontColor / LineColor / LineStyle / Thickness forms, for the link's
         * stereotypes ("a -->> b <<async>>"). The link's own inline style wins. They were ignored.
         */
        private LinkSkin arrow_stereotype_skin(ComponentRelationship rel) {
            var ls = LinkSkin();
            if (skin == null) {
                return ls;
            }
            foreach (string st in rel.stereotypes) {
                string? spec = skin.get_stereotype_property("arrow", "Color", st);
                if (spec != null) {
                    foreach (string raw_part in spec.replace(" ", "").split(";")) {
                        string part = raw_part.has_prefix("#") ? raw_part.substring(1) : raw_part;
                        string low = part.down();
                        if (part.length == 0) {
                            continue;
                        } else if (low.has_prefix("text:")) {
                            ls.text_color = ls.text_color ?? arrow_colour(part.substring(5));
                        } else if (low.has_prefix("line:")) {
                            ls.color = ls.color ?? arrow_colour(part.substring(5));
                        } else if (low.has_prefix("line.")) {
                            string style = low.substring(5);
                            if (style == "bold") {
                                ls.thickness = int.max(ls.thickness, 2);
                            } else if (ls.style == null) {
                                ls.style = style;
                            }
                        } else if (!low.contains(":") && !low.contains(".")) {
                            ls.color = ls.color ?? arrow_colour(part);
                        }
                    }
                }
                string? v = skin.get_stereotype_property("arrow", "LineColor", st);
                if (v != null && ls.color == null) {
                    ls.color = arrow_colour(v);
                }
                v = skin.get_stereotype_property("arrow", "FontColor", st);
                if (v != null && ls.text_color == null) {
                    ls.text_color = arrow_colour(v);
                }
                v = skin.get_stereotype_property("arrow", "LineStyle", st);
                if (v != null && ls.style == null) {
                    string style = v.strip().down();
                    if (style == "bold") {
                        ls.thickness = int.max(ls.thickness, 2);
                    } else {
                        ls.style = style;
                    }
                }
                v = skin.get_stereotype_property("arrow", "Thickness", st);
                if (v != null && ls.thickness == 0) {
                    ls.thickness = int.parse(v.strip());
                }
            }
            return ls;
        }

        // An arrow colour as C4 writes it: named, "#hex", or hex without the "#" (whose tokens the
        // skinparam block rejoined with spaces: "2 e7d32")
        private static string arrow_colour(string raw) {
            string v = raw.replace(" ", "");
            if (v.has_prefix("#")) {
                v = v.substring(1);
            }
            bool hex = (v.length == 3 || v.length == 6 || v.length == 8) && v.length > 0;
            for (int i = 0; i < v.length && hex; i++) {
                hex = v[i].isxdigit();
            }
            return RenderUtils.sanitize_color(hex ? "#" + v : v);
        }

        // The link's label attribute: HTML when it has creole ("**Uses**\n//<size:12>[HTTPS]</size>//"
        // from C4's Rel), which was stripped to plain text; a quoted string otherwise
        private string edge_label_attr(ComponentRelationship rel) {
            if (rel.label == null || rel.label.length == 0) {
                return "";
            }
            string text = expand_tabs(rel.label);
            if (has_creole(text)) {
                string html = creole_html(text, edge_size_scale);
                if (html.length > 0) {
                    return ", %s=<%s>".printf(label_attr_name(), html);
                }
            }
            return ", %s=\"%s\"".printf(label_attr_name(), RenderUtils.escape_label(RenderUtils.strip_inline_creole(text)));
        }

        private static bool has_creole(string text) {
            try {
                return new Regex("\\*\\*|(?<!:)//|__|<\\s*/?\\s*(b|i|u|s|strike|color|size)\\s*[:>]|<U\\+[0-9A-Fa-f]{4,6}>",
                                 RegexCompileFlags.CASELESS).match(text);
            } catch (RegexError e) {
                return false;
            }
        }

        /**
         * PlantUML creole as Graphviz HTML, line by line: **bold**, //italic//, __underline__,
         * <b> <i> <u> <s>, <color:X>, <size:N> (scaled by `size_scale` from PlantUML's font size to
         * ours), <U+XXXX>, "~" escapes. Sprites and icons are dropped. Markup left open at the end
         * of a line is closed there; a tag closed out of order closes and reopens the ones inside.
         */
        public static string creole_html(string text, double size_scale) {
            var sb = new StringBuilder();
            foreach (string line in text.replace("\\n", "\n").split("\n")) {
                if (sb.len > 0) {
                    sb.append("<BR/>");
                }
                sb.append(creole_line_html(line, size_scale));
            }
            return sb.str;
        }

        private static string creole_line_html(string line, double size_scale) {
            var sb = new StringBuilder();
            var kinds = new Gee.ArrayList<string>();   // "bold", "italic", ..., "color", "size"
            var markup = new Gee.ArrayList<string>();  // the opening tag written for each
            int i = 0;
            int text_start = 0;
            while (i < line.length) {
                char c = line[i];
                string? action = null;  // toggle kind or a tag
                int used = 0;
                if (c == '~' && i + 1 < line.length) {
                    sb.append(Markup.escape_text(line.substring(text_start, i - text_start)));
                    unichar next = line.get_char(i + 1);
                    string ch = next.to_string();
                    // "~**" / "~//" / "~__": the whole marker is text
                    if (i + 2 < line.length && line[i + 2] == line[i + 1] && "*/_".index_of_char(line[i + 1]) >= 0) {
                        ch = line.substring(i + 1, 2);
                    }
                    sb.append(Markup.escape_text(ch));
                    i += 1 + ch.length;
                    text_start = i;
                    continue;
                }
                if (i + 1 < line.length) {
                    string two = line.substring(i, 2);
                    if (two == "**") {
                        action = "bold";
                    } else if (two == "//" && (i == 0 || line[i - 1] != ':')) {
                        action = "italic";
                    } else if (two == "__") {
                        action = "underline";
                    }
                    if (action != null) {
                        used = 2;
                    }
                }
                string? open_markup = null;
                bool closing = false;
                if (action == null && c == '<') {
                    int close = line.index_of(">", i);
                    if (close > i) {
                        string tag = line.substring(i + 1, close - i - 1).strip();
                        closing = tag.has_prefix("/");
                        if (closing) {
                            tag = tag.substring(1).strip();
                        }
                        string[] nv = tag.split(":", 2);
                        string name = nv[0].strip().down();
                        string? value = nv.length > 1 ? nv[1].strip() : null;
                        used = close - i + 1;
                        if (name == "b" || name == "i" || name == "u" || name == "s" || name == "strike") {
                            action = name == "b" ? "bold" : name == "i" ? "italic" : name == "u" ? "underline" : "strike";
                        } else if (name == "color") {
                            action = "color";
                            if (!closing && value != null && value.length > 0) {
                                open_markup = "<FONT COLOR=\"%s\">".printf(Markup.escape_text(RenderUtils.sanitize_color(value)));
                            } else if (!closing) {
                                action = "drop";
                            }
                        } else if (name == "size") {
                            action = "size";
                            if (!closing && value != null && int.parse(value) > 0) {
                                double pt = double.max(1.0, Math.round(int.parse(value) * size_scale));
                                open_markup = "<FONT POINT-SIZE=\"%d\">".printf((int) pt);
                            } else if (!closing) {
                                action = "drop";
                            }
                        } else if (name.has_prefix("u+") && !closing && tag.length > 2) {
                            action = "char";
                            open_markup = "&#x%s;".printf(Markup.escape_text(tag.substring(2)));
                        } else if (name.has_prefix("$") || name.has_prefix("&") || name == "back" || name == "font") {
                            action = "drop";
                        } else {
                            used = 0;
                        }
                    }
                }
                if (action == null) {
                    i++;
                    continue;
                }
                sb.append(Markup.escape_text(line.substring(text_start, i - text_start)));
                i += used;
                text_start = i;
                if (action == "drop") {
                    continue;
                }
                if (action == "char") {
                    sb.append(open_markup);
                    continue;
                }
                bool is_toggle = used == 2 && (action == "bold" || action == "italic" || action == "underline");
                int at = -1;
                for (int k = kinds.size - 1; k >= 0 && at < 0; k--) {
                    if (kinds[k] == action) {
                        at = k;
                    }
                }
                if ((is_toggle && at >= 0) || (!is_toggle && closing)) {
                    if (at < 0) {
                        continue;
                    }
                    // Close down to it, then reopen what was inside
                    for (int k = kinds.size - 1; k >= at; k--) {
                        sb.append(closing_tag(kinds[k]));
                    }
                    kinds.remove_at(at);
                    markup.remove_at(at);
                    for (int k = at; k < kinds.size; k++) {
                        sb.append(markup[k]);
                    }
                } else if (!closing) {
                    string tag_open = open_markup ?? "<" + closing_tag(action).substring(2);
                    kinds.add(action);
                    markup.add(tag_open);
                    sb.append(tag_open);
                }
            }
            sb.append(Markup.escape_text(line.substring(text_start)));
            for (int k = kinds.size - 1; k >= 0; k--) {
                sb.append(closing_tag(kinds[k]));
            }
            // Elements with nothing in them are Graphviz syntax errors
            string result = sb.str;
            try {
                var empty = new Regex("<(B|I|U|S|FONT)(?: [^>]*)?></\\1>");
                string prev = "";
                do {
                    prev = result;
                    result = empty.replace_literal(result, -1, 0, "");
                } while (result != prev);
            } catch (RegexError e) {
                warning("Creole regex: %s", e.message);
            }
            return result;
        }

        private static string closing_tag(string kind) {
            switch (kind) {
                case "bold": return "</B>";
                case "italic": return "</I>";
                case "underline": return "</U>";
                case "strike": return "</S>";
                default: return "</FONT>";
            }
        }

        // PlantUML's "\t": spaces to the next multiple of 8 characters in the line, counting the
        // visible text (no "==" heading marker, no <tags>). It was shown as "\t".
        public static string expand_tabs(string text) {
            if (!text.contains("\\t")) {
                return text;
            }
            var sb = new StringBuilder();
            int col = 0;
            int i = 0;
            bool line_start = true;
            while (i < text.length) {
                char c = text[i];
                if (line_start && c == '=') {
                    while (i < text.length && (text[i] == '=' || text[i] == ' ')) {
                        sb.append_c(text[i]);
                        i++;
                    }
                    line_start = false;
                    continue;
                }
                line_start = false;
                if (c == '\\' && i + 1 < text.length && (text[i + 1] == 't' || text[i + 1] == 'n')) {
                    if (text[i + 1] == 't') {
                        int spaces = 8 - col % 8;
                        for (int k = 0; k < spaces; k++) {
                            sb.append_c(' ');
                        }
                        col += spaces;
                    } else {
                        sb.append("\\n");
                        col = 0;
                        line_start = true;
                    }
                    i += 2;
                    continue;
                }
                if (c == '<' && text.index_of(">", i) > i) {
                    int close = text.index_of(">", i);
                    sb.append(text.substring(i, close - i + 1));
                    i = close + 1;
                    continue;
                }
                if (c == '\n') {
                    col = 0;
                    line_start = true;
                } else if ((c & 0xC0) != 0x80) {
                    col++;
                }
                sb.append_c(c);
                i++;
            }
            return sb.str;
        }

        // The innermost container around both (ids from `innermost`, "" for the top level)
        private string common_container(string a, string b) {
            var chain = new Gee.HashSet<string>();
            string cur = a;
            while (cur != "") {
                chain.add(cur);
                cur = innermost.has_key(cur) ? innermost.get(cur) : "";
            }
            cur = b;
            while (cur != "" && !chain.contains(cur)) {
                cur = innermost.has_key(cur) ? innermost.get(cur) : "";
            }
            return cur;
        }

        // Orthogonal routing can't place edge labels ("Try using xlabels")
        private string label_attr_name() {
            return ortho ? "xlabel" : "label";
        }

        private void collect_container_ids(Gee.ArrayList<Component> comps, Gee.HashSet<string> container_ids) {
            foreach (var comp in comps) {
                if (is_cluster(comp)) {
                    container_ids.add(RenderUtils.sanitize_id(comp.get_identifier()));
                    collect_container_ids(comp.children, container_ids);
                }
            }
        }

        // A component drawn as a Graphviz cluster: it has children, or ports on its border.
        // An empty body ("node node { }") is drawn as the element's own shape, as PlantUML does.
        private bool is_cluster(Component comp) {
            return comp.children.size > 0 || port_parents.contains(RenderUtils.sanitize_id(comp.get_identifier()));
        }

        // Skinparam element name for a component type ("database", "node", ...)
        private static string type_word(ComponentType type) {
            return type.to_string().down().replace("gdiagram_component_type_", "");
        }

        // A per-stereotype skinparam of this element type, for any of its stereotypes
        // ("skinparam rectangle<<boundary>> { BorderStyle dashed }")
        private string? stereo_prop(Component comp, string property) {
            if (skin == null) {
                return null;
            }
            string type_name = type_word(comp.component_type);
            var names = new Gee.ArrayList<string>();
            names.add_all(comp.stereotypes);
            if (names.size == 0 && comp.stereotype != null) {
                names.add(comp.stereotype);
            }
            foreach (string st in names) {
                if (st.length == 0) {
                    continue;
                }
                string? v = skin.get_stereotype_property(type_name, property, st);
                if (v == null && comp.component_type == ComponentType.RECTANGLE) {
                    v = skin.get_stereotype_property("package", property, st);
                }
                if (v != null) {
                    return v.strip();
                }
            }
            return null;
        }

        private static bool is_boundary(Component comp) {
            foreach (string st in comp.stereotypes) {
                if (st.has_suffix("boundary")) {
                    return true;
                }
            }
            return comp.stereotype != null && comp.stereotype.has_suffix("boundary");
        }

        // The C4 stereotype of an element: the first one with a C4 colour
        private string? c4_stereotype(Component comp) {
            foreach (string st in comp.stereotypes) {
                if (c4_color_for_stereotype(st) != null) {
                    return st;
                }
            }
            return comp.stereotype;
        }

        // A label with PlantUML heading lines ("== Name") as HTML: the heading bold and a size
        // up, "//text//" lines italic, other markup stripped, blank lines kept once. Null for
        // a label without a heading.
        private static string? heading_html(string raw) {
            if (!raw.has_prefix("==") && !raw.contains("\\n==") && !raw.contains("\n==")) {
                return null;
            }
            var sb = new StringBuilder();
            bool last_blank = true;
            foreach (string part in raw.replace("\\n", "\n").split("\n")) {
                string line = part.strip();
                string html;
                if (line.has_prefix("==")) {
                    string text = RenderUtils.strip_plantuml_markup(line.substring(2).strip());
                    while (text.has_suffix("=")) {
                        text = text.substring(0, text.length - 1).strip();
                    }
                    html = "<FONT POINT-SIZE=\"13\"><B>%s</B></FONT>".printf(Markup.escape_text(text));
                } else if (line.has_prefix("//") && line.has_suffix("//") && line.length > 4) {
                    string text = RenderUtils.strip_plantuml_markup(line.substring(2, line.length - 4));
                    html = text.strip().length > 0 ? "<I>%s</I>".printf(Markup.escape_text(text)) : "";
                } else {
                    html = Markup.escape_text(RenderUtils.strip_plantuml_markup(line));
                }
                if (html.length == 0) {
                    if (!last_blank) {
                        sb.append("<BR/>");  // one blank line between blocks
                        last_blank = true;
                    }
                    continue;
                }
                if (sb.len > 0) {
                    sb.append("<BR/>");
                }
                sb.append(html);
                last_blank = false;
            }
            string result = sb.str;
            while (result.has_suffix("<BR/>")) {
                result = result.substring(0, result.length - 5);
            }
            return result.length > 0 ? result : null;
        }

        // Legend text with PlantUML's inline markup as HTML: <color:X>, <size:N>, <b>, <i>,
        // <u>, "<U+25AF>" characters, **bold**; sprites ("<$person>") dropped. The tags were
        // shown as text.
        public static string legend_cell_html(string text, SpriteCells? sprites = null, string? tint = null) {
            var sb = new StringBuilder();
            var open = new Gee.ArrayList<string>();
            // With `sprites`, "<$name>" is drawn in the text colour at that point
            var open_colour = new Gee.ArrayList<string>();
            // Output length before / after each open tag: an element closed with nothing in it
            // is dropped ("<FONT POINT-SIZE="10"></FONT>" is a Graphviz syntax error)
            var open_before = new Gee.ArrayList<int>();
            var open_after = new Gee.ArrayList<int>();
            try {
                var tag = new Regex("<(/?)(color|size|b|i|u)(?::([^>]*))?>|<U\\+([0-9A-Fa-f]{4,6})>|<\\$[^>]*>",
                                    RegexCompileFlags.CASELESS);
                MatchInfo mi;
                int pos = 0;
                tag.match(text, 0, out mi);
                while (mi.matches()) {
                    int s, e;
                    mi.fetch_pos(0, out s, out e);
                    sb.append(RenderUtils.convert_creole_to_html(text.substring(pos, s - pos)));
                    string? code = mi.fetch(4);
                    string? name = mi.fetch(2);
                    string matched = text.substring(s, e - s);
                    string? sprite_span = null;
                    if (sprites != null && matched.has_prefix("<$")) {
                        string? colour = tint;
                        foreach (string oc in open_colour) {
                            if (oc.length > 0) {
                                colour = oc;
                            }
                        }
                        sprite_span = sprites.span(matched, colour);
                    }
                    if (sprite_span != null) {
                        sb.append(sprite_span);
                    } else if (code != null && code.length > 0) {
                        sb.append("&#x%s;".printf(code));
                    } else if (name != null && name.length > 0) {
                        string kind = name.down();
                        bool closing = mi.fetch(1) == "/";
                        string html_tag = kind == "color" || kind == "size" ? "FONT" : kind.up();
                        if (closing) {
                            int top = open.size - 1;
                            if (top >= 0 && open[top] == html_tag) {
                                if ((int) sb.len == open_after[top]) {
                                    sb.truncate(open_before[top]);
                                } else {
                                    sb.append("</%s>".printf(html_tag));
                                }
                                open.remove_at(top);
                                open_before.remove_at(top);
                                open_after.remove_at(top);
                                open_colour.remove_at(top);
                            }
                        } else {
                            string? value = mi.fetch(3);
                            int before = (int) sb.len;
                            if (kind == "color" && value != null && value.strip().length > 0) {
                                sb.append("<FONT COLOR=\"%s\">".printf(Markup.escape_text(legend_text_colour(RenderUtils.sanitize_color(value.strip())))));
                            } else if (kind == "size" && value != null && int.parse(value.strip()) > 0) {
                                sb.append("<FONT POINT-SIZE=\"%d\">".printf(int.parse(value.strip())));
                            } else if (kind != "color" && kind != "size") {
                                sb.append("<%s>".printf(html_tag));
                            }
                            if ((int) sb.len > before) {
                                open.add(html_tag);
                                open_before.add(before);
                                open_after.add((int) sb.len);
                                open_colour.add(kind == "color" ? legend_text_colour(RenderUtils.sanitize_color(value.strip())) : "");
                            }
                        }
                    }
                    pos = e;
                    mi.next();
                }
                sb.append(RenderUtils.convert_creole_to_html(text.substring(pos)));
            } catch (RegexError e) {
                return RenderUtils.convert_creole_to_html(text);
            }
            for (int i = open.size - 1; i >= 0; i--) {
                if ((int) sb.len == open_after[i]) {
                    sb.truncate(open_before[i]);
                } else {
                    sb.append("</%s>".printf(open[i]));
                }
            }
            return sb.str;
        }

        // Text as HTML: escaped, "\n" line breaks
        private static string html_text(string text) {
            return Markup.escape_text(text).replace("\\n", "<BR/>").replace("\n", "<BR/>");
        }

        // "<$person>" / "<$person,scale=.25>" sprite references: Graphviz can't draw them and
        // they were shown as text
        private static string strip_sprites(string text) {
            try {
                return new Regex("<\\$[^>]*>").replace_literal(text, -1, 0, "");
            } catch (RegexError e) {
                return text;
            }
        }

        // «stereotype» line(s) as HTML, or null when there is none or "hide stereotype"
        private string? stereotype_html(Component comp) {
            if (hide_stereotype || comp.stereotype == null || comp.stereotype.strip().length == 0) {
                return null;
            }
            // "skinparam rectangle<<boundary>> { StereotypeFontColor transparent }" (C4 boundaries):
            // PlantUML draws no stereotype
            var written = new Gee.ArrayList<string>();
            written.add_all(comp.stereotypes);
            if (written.size == 0) {
                written.add(comp.stereotype);
            }
            foreach (string st in written) {
                string? colour = skin != null ? skin.get_stereotype_property(type_word(comp.component_type), "StereotypeFontColor", st) : null;
                if (colour == null && skin != null && comp.component_type == ComponentType.RECTANGLE) {
                    colour = skin.get_stereotype_property("package", "StereotypeFontColor", st);
                }
                if (colour != null && colour.strip().down() == "transparent") {
                    return null;
                }
            }
            var sb = new StringBuilder();
            var names = comp.stereotypes.size > 0 ? comp.stereotypes : null;
            if (names == null) {
                sb.append("«%s»".printf(Markup.escape_text(comp.stereotype.strip())));
            } else {
                foreach (string st in names) {
                    sb.append("«%s»".printf(Markup.escape_text(st.strip())));
                }
            }
            return "<I>%s</I>".printf(sb.str);
        }

        // DOT style value from a PlantUML line style ("dashed", "dotted", "bold")
        private static string line_style_word(string? style) {
            if (style == null) {
                return "";
            }
            switch (style.strip().down()) {
                case "dashed": return "dashed";
                case "dotted": return "dotted";
                case "bold": return "bold";
                default: return "";
            }
        }

        // A colour Graphviz can draw text with and that is readable on `fill` (or on the canvas
        // for a see-through fill). Black is written "#010101": Graphviz writes no fill for
        // black text and fill_svg_background() would recolour it.
        private string readable_on(string? wanted, string fill) {
            string behind = fill;
            string f = fill.strip().down();
            if (f == "transparent" || f == "none" || f.length == 0) {
                behind = canvas_color;
            }
            string colour = wanted != null ? RenderUtils.sanitize_color(wanted) : RenderUtils.contrast_text(behind);
            if (wanted != null && RenderUtils.contrast_text(colour) == RenderUtils.contrast_text(behind) &&
                !behind.contains(":")) {
                colour = RenderUtils.contrast_text(behind);
            }
            string c = colour.strip().down();
            return c == "#000000" || c == "black" || c == "#000" ? "#010101" : colour;
        }

        // DOT attributes for an element drawn as an icon over its caption (interface, circle,
        // boundary, control, entity): an HTML label whose sentinel cell becomes the icon in
        // draw_shapes(). Links attach to port "c", the icon.
        private string icon_node_attrs(string id, string kind, string? above_html, string name_html,
                                       string fill, string stroke, string? font, string dash) {
            int w = 16, h = 16;
            switch (kind) {
                case "boundary": w = 34; h = 26; break;
                case "control": w = 26; h = 28; break;
                case "entity": w = 26; h = 28; break;
                case "circle": w = 14; h = 14; break;
                default: break;
            }
            node_shapes.set(id, new ComponentShapeInfo(kind, fill, stroke, dash));
            string open_font = font != null ? "<FONT COLOR=\"%s\">".printf(font) : "";
            string close_font = font != null ? "</FONT>" : "";
            var rows = new StringBuilder();
            if (above_html != null) {
                rows.append("<TR><TD>%s%s%s</TD></TR>".printf(open_font, above_html, close_font));
            }
            rows.append("<TR><TD PORT=\"c\" FIXEDSIZE=\"TRUE\" WIDTH=\"%d\" HEIGHT=\"%d\" BGCOLOR=\"%s\"></TD></TR>".printf(w, h, SENTINEL));
            rows.append("<TR><TD>%s%s%s</TD></TR>".printf(open_font, name_html, close_font));
            return "shape=plaintext, style=solid, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"1\">%s</TABLE>>".printf(rows.str);
        }

        // A name used only in links: an interface circle, or an actor in a diagram with actors
        private string implicit_end_node(string id, string name) {
            var palette = ThemeManager.get_active_palette();
            if (link_ends_are_actors) {
                return "%s [%s]".printf(id, RenderUtils.actor_figure_attrs(null, html_text(name),
                    RenderUtils.sanitize_color(palette.person_fill), RenderUtils.sanitize_color(palette.person_border), "", null));
            }
            return "%s [%s]".printf(id, icon_node_attrs(id, "interface", null, html_text(name), iface_fill, iface_border, null, ""));
        }

        private void append_component_node(StringBuilder sb, Component comp, string default_color,
                                           string default_border, string pkg_color, ref int cluster_idx) {
            string id = RenderUtils.sanitize_id(comp.get_identifier());
            int sprites_before = sprite_cells.uses.size;
            bool wrap = side_wrapped.contains(id) && !is_cluster(comp);
            if (wrap) {
                sb.append("  subgraph cluster_side_%d { style=invis; label=\"\";\n".printf(side_idx++));
            }
            append_component_node_inner(sb, comp, default_color, default_border, pkg_color, ref cluster_idx);
            if (wrap) {
                sb.append("  }\n");
            }
            // Sprites not coloured by their element take the graph's text colour
            sprite_cells.tint_since(sprites_before, node_font_color);
        }

        // The label text: "\t" expanded
        private static string display_text(Component comp) {
            return expand_tabs(comp.get_display_label());
        }

        private void append_component_node_inner(StringBuilder sb, Component comp, string default_color,
                                                 string default_border, string pkg_color, ref int cluster_idx) {
            var palette = ThemeManager.get_active_palette();
            string id = RenderUtils.sanitize_id(comp.get_identifier());
            int sprites_before = sprite_cells.uses.size;
            // Strip PlantUML inline markup (<size:N>, **bold**, [[link]], etc.)
            // before escaping for dot. C4-PlantUML expansion produces a lot of
            // this markup that the component renderer can't render visually.
            // "<$person>\n== User" (C4 Person): the sprite, marked until the text is HTML
            string raw = sprite_cells.mark(display_text(comp));
            string clean = RenderUtils.strip_plantuml_markup(strip_sprites(raw));
            string label = RenderUtils.escape_label(clean);
            // "== Web App\n//[React]//\n\nUser interface" (C4): a bold title line and italics
            string? rich = heading_html(strip_sprites(raw));
            if (rich == null && SpriteCells.has_mark(clean)) {
                rich = html_text(clean);
            }
            if (rich != null) {
                rich = sprite_cells.resolve(rich);
            }
            string name_html = rich ?? html_text(clean);
            string? stereo_html = stereotype_html(comp);
            string fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : default_color;

            // C4-PlantUML color scheme: looked up here, applied AFTER the
            // type-based switch below so the C4 fill overrides the default
            // rectangle/database fillcolor.
            string? c4_st = c4_stereotype(comp);
            string? c4_fill = c4_color_for_stereotype(c4_st);
            string? c4_border = c4_border_for_stereotype(c4_st);
            string? c4_font = c4_font_for_stereotype(c4_st);

            if (is_cluster(comp)) {
                append_cluster(sb, comp, raw, clean, stereo_html, default_color, default_border, pkg_color, ref cluster_idx,
                               sprites_before);
                return;
            }

            // Render as individual node
            // A name only used by a link in a container body: drawn inside the
            // container, looking like the undeclared link ends at the top level
            if (comp.link_end) {
                sb.append("  %s;\n".printf(implicit_end_node(id, comp.id)));
                return;
            }

            // Colours that apply to every shape: explicit, per-stereotype skinparam, C4
            string? stereo_fill = stereo_prop(comp, "BackgroundColor");
            string? stereo_border = stereo_prop(comp, "BorderColor");
            string? stereo_font = stereo_prop(comp, "FontColor");
            string type_name = type_word(comp.component_type);
            string? type_fill = skin != null && comp.component_type != ComponentType.COMPONENT
                ? skin.get_element_property(type_name, "BackgroundColor") : null;
            string? type_border = skin != null && comp.component_type != ComponentType.COMPONENT
                ? skin.get_element_property(type_name, "BorderColor") : null;
            // An explicit fill keeps the neutral border; the component blue border was drawn
            // around any colour
            string border;
            if (comp.line_color != null) {
                border = RenderUtils.sanitize_color(comp.line_color);
            } else if (stereo_border != null) {
                border = RenderUtils.sanitize_color(stereo_border);
            } else if (c4_border != null) {
                border = c4_border;
            } else if (type_border != null) {
                border = RenderUtils.sanitize_color(type_border);
            } else if (comp.color != null && skin != null && skin.get_element_property("component", "BorderColor") == null) {
                border = RenderUtils.sanitize_color(palette.node_border);
            } else {
                border = default_border;
            }
            string dash = line_style_word(or_else(comp.line_style, stereo_prop(comp, "BorderStyle")));
            if (dash == "" && is_boundary(comp)) {
                dash = "dashed";
            }

            // Interfaces inside containers: the same small circle over a caption as
            // top-level interfaces
            if (comp.component_type == ComponentType.INTERFACE) {
                string ifill = comp.color != null ? RenderUtils.sanitize_color(comp.color) : iface_fill;
                sb.append("  %s [%s];\n".printf(id, icon_node_attrs(id, "interface", stereo_html, name_html, ifill,
                    comp.line_color != null ? border : iface_border, text_font(comp, stereo_font), dash)));
                return;
            }
            if (comp.component_type == ComponentType.JSON) {
                sb.append("  %s [%s];\n".printf(id, json_node_attrs(comp, clean, border)));
                return;
            }

            string shape;
            string style = "filled";
            string extra = "";
            string? outline = null;  // SVG outline drawn by draw_shapes()

            switch (comp.component_type) {
                case ComponentType.DATABASE:
                    shape = "cylinder";
                    fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : palette.database_fill;
                    break;
                case ComponentType.CLOUD:
                    shape = "box";
                    outline = "cloud";
                    extra = ", margin=\"0.25,0.15\"";
                    fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : palette.external_fill;
                    break;
                case ComponentType.ARTIFACT:
                case ComponentType.FILE:
                    shape = "note";
                    if (comp.component_type == ComponentType.FILE) {
                        fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : palette.node_fill;
                    }
                    break;
                case ComponentType.STORAGE:
                    // A rounded stadium in PlantUML; it was drawn as a folder
                    shape = "box";
                    outline = "storage";
                    extra = ", margin=\"0.22,0.1\"";
                    break;
                case ComponentType.CARD:
                case ComponentType.AGENT:
                    shape = "box";
                    break;
                case ComponentType.QUEUE:
                    shape = "box";
                    outline = "queue";
                    extra = ", margin=\"0.25,0.1\"";
                    fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : palette.person_fill;
                    break;
                case ComponentType.BOUNDARY:
                case ComponentType.CONTROL:
                case ComponentType.ENTITY:
                case ComponentType.CIRCLE: {
                    // UML icons over the caption
                    string icon_fill = comp.color != null ? RenderUtils.sanitize_color(comp.color)
                        : RenderUtils.sanitize_color(or_else(stereo_fill, or_else(type_fill, iface_fill)));
                    string icon_stroke = comp.line_color != null || stereo_border != null || type_border != null ? border : iface_border;
                    sb.append("  %s [%s];\n".printf(id, icon_node_attrs(id, type_name, stereo_html, name_html,
                        icon_fill, icon_stroke, text_font(comp, stereo_font), dash)));
                    return;
                }
                case ComponentType.ACTOR: {
                    // A stick figure over the name (RenderUtils.draw_actor_figures)
                    string actor_fill = comp.color != null ? RenderUtils.sanitize_color(comp.color)
                        : RenderUtils.sanitize_color(or_else(stereo_fill, or_else(type_fill, palette.person_fill)));
                    string actor_stroke = comp.line_color != null || stereo_border != null || type_border != null
                        ? border : RenderUtils.sanitize_color(palette.person_border);
                    sb.append("  %s [%s];\n".printf(id, RenderUtils.actor_figure_attrs(stereo_html, name_html,
                        actor_fill, actor_stroke, comp.business ? " gdbusiness" : "", text_font(comp, stereo_font))));
                    return;
                }
                case ComponentType.USECASE:
                    shape = "ellipse";
                    if (comp.business) {
                        extra = ", class=\"gdbusiness\"";
                    }
                    break;
                case ComponentType.PERSON: {
                    // A head over a rounded body holding the name
                    string pfill = comp.color != null ? RenderUtils.fill_color(comp.color).split(":")[0]
                        : RenderUtils.sanitize_color(or_else(c4_fill, or_else(stereo_fill, or_else(type_fill, palette.person_fill))));
                    string pfont = or_else(text_font(comp, stereo_font), readable_on(c4_font, pfill));
                    node_shapes.set(id, new ComponentShapeInfo("person", pfill, border, dash));
                    string body = stereo_html != null ? "%s<BR/>%s".printf(stereo_html, name_html) : name_html;
                    sprite_cells.tint_since(sprites_before, pfont);
                    sb.append("  %s [shape=plaintext, style=solid, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR><TD FIXEDSIZE=\"TRUE\" WIDTH=\"26\" HEIGHT=\"26\" BGCOLOR=\"%s\"></TD></TR><TR><TD BORDER=\"1\" STYLE=\"rounded\" BGCOLOR=\"%s\" COLOR=\"%s\" CELLPADDING=\"8\"><FONT COLOR=\"%s\">%s</FONT></TD></TR></TABLE>>];\n".printf(
                        id, SENTINEL, pfill, border, pfont, body));
                    return;
                }
                case ComponentType.ACTION:
                case ComponentType.PROCESS:
                    shape = "cds";
                    break;
                case ComponentType.HEXAGON:
                    shape = "hexagon";
                    break;
                case ComponentType.LABEL:
                    shape = "plaintext";
                    style = "solid";
                    break;
                case ComponentType.COLLECTIONS:
                    shape = "box";
                    outline = "collections";
                    extra = ", margin=\"0.15,0.1\"";
                    break;
                case ComponentType.STACK:
                    shape = "box";
                    outline = "stack";
                    extra = ", margin=\"0.3,0.1\"";
                    fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : palette.grid;
                    break;
                case ComponentType.RECTANGLE:
                    shape = "box";
                    fill_color = comp.color != null ? RenderUtils.fill_color(comp.color) : palette.node_fill;
                    break;
                // Element keywords that open a container when given a body; without one
                // they are single elements with PlantUML's shapes
                case ComponentType.NODE:
                    shape = "box3d";
                    break;
                case ComponentType.FOLDER:
                    shape = "box";
                    outline = "folder";
                    extra = ", margin=\"0.15,0.15\"";
                    break;
                case ComponentType.PACKAGE:
                    shape = "box";
                    outline = "package";
                    extra = ", margin=\"0.15,0.2\"";
                    break;
                case ComponentType.FRAME:
                    shape = "box";
                    outline = "frame";
                    extra = ", margin=\"0.2,0.15\"";
                    break;
                default:
                    // "skinparam componentStyle": uml2 (a box with the component icon at its
                    // top right, as PlantUML draws it), uml1 (side tabs), rectangle
                    if (component_style == "uml1") {
                        shape = "component";
                    } else {
                        shape = "box";
                        if (component_style != "rectangle") {
                            outline = "component";
                            extra = ", margin=\"0.3,0.14\"";
                        }
                    }
                    break;
            }

            // C4 stereotype overrides — apply now that the type switch
            // above has set the per-shape default. User-set colors still
            // win (we only override when comp.color is null).
            // Raw colour behind the fill, for a gradient's angle
            string? fill_raw = comp.color;
            if (fill_raw == null && fill_color == default_color) {
                fill_raw = comp_color_raw;
            }
            if (type_fill != null && comp.color == null) {
                fill_color = RenderUtils.fill_color(type_fill);
                fill_raw = type_fill;
            }
            if (c4_fill != null && comp.color == null) {
                fill_color = c4_fill;
                fill_raw = null;
            }
            // <style> ".stereotype" colours ("skinparam component { BackgroundColor<<x>> }")
            if (stereo_fill != null && comp.color == null) {
                fill_color = RenderUtils.fill_color(stereo_fill);
                fill_raw = stereo_fill;
                if (c4_font == null) {
                    c4_font = RenderUtils.contrast_text(fill_color);
                }
            }
            if (stereo_font != null) {
                c4_font = RenderUtils.sanitize_color(stereo_font);
            }
            if (comp.text_color != null) {
                c4_font = RenderUtils.sanitize_color(comp.text_color);
            }
            // Boundary stereotypes are dashed-outline transparent boxes
            if (dash.length > 0) {
                style = style + "," + dash;
            }
            // "skinparam rectangle { roundCorner<<Concept>> 25 }" / "RoundCorner 25"
            string? round = or_else(stereo_prop(comp, "RoundCorner"),
                            skin != null ? skin.get_element_property(type_name, "RoundCorner") : null);
            if (shape == "box" && outline == null && round != null && int.parse(round) > 0) {
                style = style + ",rounded";
            }

            var attrs = new StringBuilder();
            if (stereo_html != null) {
                // «stereotype» in italics above the name, inside the shape, as PlantUML
                // draws it. It used to be an external xlabel beside the box.
                attrs.append("label=<%s<BR/>%s>".printf(stereo_html, name_html));
            } else {
                attrs.append(rich != null ? "label=<%s>".printf(rich) : "label=\"%s\"".printf(label));
            }
            attrs.append(", shape=%s".printf(shape));
            attrs.append(", style=\"%s\"".printf(style));
            attrs.append(", fillcolor=\"%s\"".printf(fill_color));
            attrs.append(RenderUtils.gradient_attr(fill_raw));
            attrs.append(", color=\"%s\"".printf(border));
            attrs.append(extra);
            // The graph-wide node text colour was unreadable on some fills: dark text on
            // the person/queue blue (#08427B) or an explicit dark colour, light text on the
            // dark theme's component, boundary and control fills (#6BA8E0, #FFD54F,
            // #66BB6A). Set a contrasting colour where the default has the wrong polarity.
            if (c4_font == null && style.contains("filled") && (skin == null || skin.default_font_color == null)) {
                string needed = RenderUtils.contrast_text(fill_color);
                bool default_is_dark = RenderUtils.contrast_text(node_font_color) == "#FFFFFF";
                if ((needed == "#000000") != default_is_dark) {
                    c4_font = needed;
                }
            }
            if (c4_font != null) {
                attrs.append(", fontcolor=\"%s\"".printf(c4_font));
                sprite_cells.tint_since(sprites_before, c4_font);
            }
            if (outline != null) {
                node_shapes.set(id, new ComponentShapeInfo(outline, fill_color, border, dash));
            }

            sb.append("  %s [%s];\n".printf(id, attrs.str));
        }

        // a ?? b, as a call: chained "??" over unowned properties and temporaries freed the
        // chosen string early in the generated C
        private static string? or_else(string? a, string? b) {
            return a != null ? a : b;
        }

        // The element's own text colour: inline "text:" or a per-stereotype FontColor
        private static string? text_font(Component comp, string? stereo_font) {
            if (comp.text_color != null) {
                return RenderUtils.sanitize_color(comp.text_color);
            }
            return stereo_font != null ? RenderUtils.sanitize_color(stereo_font) : null;
        }

        // Container fill: its own colour, a per-stereotype skinparam, a C4 boundary (see-through),
        // the type's skinparam ("skinparam node { BackgroundColor }"), the package skinparam
        // (PlantUML uses it for every container), then the palette. Nodes were always orange and
        // databases blue, whatever the theme said.
        private void append_cluster(StringBuilder sb, Component comp, string raw, string clean, string? stereo_html,
                                    string default_color, string default_border, string pkg_color,
                                    ref int cluster_idx, int sprites_before) {
            var palette = ThemeManager.get_active_palette();
            string id = RenderUtils.sanitize_id(comp.get_identifier());
            string cluster = "cluster_%d".printf(cluster_idx);
            cluster_names.set(id, cluster);
            sb.append("\n  subgraph cluster_%d {\n".printf(cluster_idx++));

            string type_name = type_word(comp.component_type);
            string? stereo_fill = stereo_prop(comp, "BackgroundColor");
            string? type_fill = skin != null ? skin.get_element_property(type_name, "BackgroundColor") : null;
            string? fill_raw;
            if (comp.color != null) {
                fill_raw = comp.color;
            } else if (stereo_fill != null) {
                fill_raw = stereo_fill;
            } else if (is_boundary(comp)) {
                fill_raw = "transparent";
            } else if (type_fill != null && comp.component_type != ComponentType.COMPONENT) {
                fill_raw = type_fill;
            } else {
                fill_raw = pkg_color_raw;
            }
            string fill = fill_raw == pkg_color_raw ? pkg_color : RenderUtils.fill_color(fill_raw);

            string? stereo_border = stereo_prop(comp, "BorderColor");
            string? type_border = skin != null ? skin.get_element_property(type_name, "BorderColor") : null;
            string? pkg_border = skin != null ? skin.get_element_property("package", "BorderColor") : null;
            string border_raw = palette.node_border;
            if (comp.line_color != null) {
                border_raw = comp.line_color;
            } else if (stereo_border != null) {
                border_raw = stereo_border;
            } else if (is_boundary(comp)) {
                border_raw = palette.boundary_stroke;
            } else if (type_border != null) {
                border_raw = type_border;
            } else if (pkg_border != null) {
                border_raw = pkg_border;
            }
            string border = RenderUtils.sanitize_color(border_raw);

            string dash = line_style_word(or_else(comp.line_style, stereo_prop(comp, "BorderStyle")));
            if (dash == "" && is_boundary(comp)) {
                dash = "dashed";
            }

            // Title: explicit text colour, then skinparams, readable on the fill
            string? stereo_font = stereo_prop(comp, "FontColor");
            string? wanted = or_else(comp.text_color, stereo_font);
            if (wanted == null && skin != null) {
                wanted = or_else(skin.get_element_property(type_name, "FontColor"),
                                 or_else(skin.get_element_property("package", "FontColor"), skin.default_font_color));
            }
            if (wanted == null && is_boundary(comp)) {
                wanted = palette.boundary_stroke;
            }
            string title_color = readable_on(wanted, fill);

            string kind;
            bool left_title = false;
            switch (comp.component_type) {
                case ComponentType.NODE: kind = "node"; break;
                case ComponentType.CLOUD: kind = "cloud"; break;
                case ComponentType.DATABASE: kind = "database"; break;
                case ComponentType.QUEUE: kind = "queue"; break;
                case ComponentType.STORAGE: kind = "storage"; break;
                case ComponentType.FOLDER: kind = "folder"; left_title = true; break;
                case ComponentType.PACKAGE: kind = "package"; left_title = true; break;
                case ComponentType.FRAME: kind = "frame"; left_title = true; break;
                case ComponentType.COMPONENT:
                    kind = component_style == "uml2" ? "component" : "rect";
                    break;
                default: kind = "rect"; break;
            }

            // «stereotype» in italics above the bold name, as PlantUML labels a container
            var title = new StringBuilder();
            if (kind == "database") {
                title.append("<BR/>");  // clear of the cylinder's top ellipse
            }
            if (stereo_html != null) {
                title.append(stereo_html);
                title.append("<BR/>");
            }
            // `raw` and `clean` have their sprites marked
            string raw_title = strip_sprites(raw);
            string? rich_title = heading_html(raw_title);
            if (rich_title != null) {
                title.append(rich_title);
            } else if (clean.strip().length > 0) {
                title.append("<B>%s</B>".printf(html_text(clean)));
            }
            // "cloud { ... }" has no name: an empty <B></B> is a Graphviz syntax error
            string title_html = sprite_cells.resolve(title.str);
            while (title_html.has_suffix("<BR/>")) {
                title_html = title_html.substring(0, title_html.length - 5);
            }
            sprite_cells.tint_since(sprites_before, title_color);
            sb.append(title_html.length > 0 ? "    label=<%s>;\n".printf(title_html) : "    label=\"\";\n");
            // Without a graph font the two-line header falls back to Times and cramps
            sb.append("    fontname=\"%s\";\n".printf(diagram_font));
            sb.append("    fontsize=12;\n");
            sb.append("    fontcolor=\"%s\";\n".printf(title_color));
            if (left_title) {
                sb.append("    labeljust=l;\n");
            }
            string style = "filled";
            if (dash.length > 0) {
                style += "," + dash;
            }
            if (kind == "rect" && stereo_prop(comp, "RoundCorner") != null && int.parse(stereo_prop(comp, "RoundCorner")) > 0) {
                style += ",rounded";
            }
            sb.append("    style=\"%s\";\n".printf(style));
            sb.append("    fillcolor=\"%s\";\n".printf(fill));
            sb.append("    color=\"%s\";\n".printf(border));
            if (kind == "node" || kind == "cloud" || kind == "queue" || kind == "storage") {
                sb.append("    margin=16;\n");
            }
            string angle = RenderUtils.gradient_stmt(fill_raw);
            if (angle != "") {
                sb.append("    %s\n".printf(angle));
            }
            if (kind != "rect") {
                cluster_shapes.set(cluster, new ComponentShapeInfo(kind, fill, border, dash));
            }

            if (comp.stereotype != null) {
                sb.append("    // Stereotype: <<%s>>\n".printf(comp.stereotype));
            }

            // Render children
            foreach (var child in comp.children) {
                append_component_node(sb, child, default_color, default_border, pkg_color, ref cluster_idx);
            }

            // Ports: small squares with the name beside them, on the container's border
            // as PlantUML draws them: portin (and a port linked from outside) on the
            // top edge, portout on the bottom edge. Graphviz can only lay them out in
            // the cluster's first / last rank; render_to_svg() then moves that border
            // onto the squares. They were drawn inside the cluster.
            if (container_ports.has_key(id)) {
                var layout = new PortBorderLayout(cluster_names.get(id));
                string square = "<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\" FIXEDSIZE=\"TRUE\" WIDTH=\"10\" HEIGHT=\"10\" PORT=\"sq\" BGCOLOR=\"%s\" COLOR=\"%s\"><TR><TD></TD></TR></TABLE>".printf(
                    RenderUtils.sanitize_color(palette.node_fill), default_border);
                foreach (var port in container_ports.get(id)) {
                    string port_id = RenderUtils.sanitize_id(port.id);
                    bool top = port_on_top.get(port_id);
                    // The name diagonally outside the square, clear of the links at its middle
                    string name_row = "<TR><TD ALIGN=\"RIGHT\">%s</TD><TD></TD></TR>".printf(Markup.escape_text(port.label ?? port.id));
                    string square_row = "<TR><TD></TD><TD>%s</TD></TR>".printf(square);
                    sb.append("    %s [shape=plaintext, style=solid, label=<<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\">%s%s</TABLE>>];\n".printf(
                        port_id, top ? name_row : square_row, top ? square_row : name_row));
                    (top ? layout.top_ports : layout.bottom_ports).add(port_id);
                }
                // Every other node of the container below the top ports and above the
                // bottom ones, so the moved border cuts through the ports only
                var inner = new Gee.ArrayList<string>();
                collect_node_ids(comp.children, inner);
                if (anchored.contains(id)) {
                    inner.add(id + "_anchor");
                }
                if (layout.top_ports.size > 0) {
                    sb.append("    { rank=min; %s; }\n".printf(join_ids(layout.top_ports)));
                }
                if (layout.bottom_ports.size > 0) {
                    sb.append("    { rank=max; %s; }\n".printf(join_ids(layout.bottom_ports)));
                }
                foreach (string node_id in inner) {
                    if (layout.top_ports.size > 0) {
                        sb.append("    %s -> %s [style=invis, weight=0];\n".printf(layout.top_ports[0], node_id));
                    }
                    if (layout.bottom_ports.size > 0) {
                        sb.append("    %s -> %s [style=invis, weight=0];\n".printf(node_id, layout.bottom_ports[0]));
                    }
                }
                port_layouts.add(layout);
            }

            // Anchor inside the cluster: lhead/ltail only clip an edge at a
            // cluster border when the endpoint is a node of that cluster.
            if (anchored.contains(id)) {
                sb.append("    %s [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(id + "_anchor"));
            }
            sb.append("  }\n");
        }

        // ── JSON ───────────────────────────────────────────────────────────
        // "json J { ... }" under allowmixing: a table with the name on top and a key | value
        // row per member, nested objects and arrays as inner tables, as PlantUML draws it

        private string json_node_attrs(Component comp, string title, string border) {
            var palette = ThemeManager.get_active_palette();
            string fill = comp.color != null ? RenderUtils.sanitize_color(comp.color) : RenderUtils.sanitize_color(palette.node_fill);
            string font = readable_on(comp.text_color, fill);
            string body;
            try {
                var parser = new Json.Parser();
                parser.load_from_data(comp.json_text ?? "{}");
                body = json_html(parser.get_root(), border, font);
            } catch (Error e) {
                body = "<TABLE BORDER=\"0\"><TR><TD>%s</TD></TR></TABLE>".printf(html_text(comp.json_text ?? ""));
            }
            return "shape=plaintext, style=solid, label=<<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\" BGCOLOR=\"%s\" COLOR=\"%s\"><TR><TD CELLPADDING=\"3\"><FONT COLOR=\"%s\">%s</FONT></TD></TR><TR><TD>%s</TD></TR></TABLE>>".printf(
                fill, border, font, html_text(title), body);
        }

        private static string json_html(Json.Node? node, string border, string font) {
            if (node == null) {
                return "";
            }
            switch (node.get_node_type()) {
                case Json.NodeType.OBJECT: {
                    var obj = node.get_object();
                    if (obj.get_size() == 0) {
                        return "";
                    }
                    var rows = new StringBuilder();
                    foreach (string key in obj.get_members()) {
                        rows.append("<TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">%s</FONT></TD><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(
                            font, Markup.escape_text(key), json_html(obj.get_member(key), border, font)));
                    }
                    return "<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"3\" COLOR=\"%s\">%s</TABLE>".printf(border, rows.str);
                }
                case Json.NodeType.ARRAY: {
                    var rows = new StringBuilder();
                    foreach (var item in node.get_array().get_elements()) {
                        rows.append("<TR><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(json_html(item, border, font)));
                    }
                    if (rows.len == 0) {
                        return "";
                    }
                    return "<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"3\" COLOR=\"%s\">%s</TABLE>".printf(border, rows.str);
                }
                case Json.NodeType.NULL:
                    return "<FONT COLOR=\"%s\">null</FONT>".printf(font);
                default: {
                    string text;
                    var t = node.get_value_type();
                    if (t == typeof(string)) {
                        text = node.get_string();
                    } else if (t == typeof(bool)) {
                        text = node.get_boolean() ? "true" : "false";
                    } else if (t == typeof(int64)) {
                        text = node.get_int().to_string();
                    } else {
                        text = Json.to_string(node, false);
                    }
                    return "<FONT COLOR=\"%s\">%s</FONT>".printf(font, Markup.escape_text(text));
                }
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

        // ── Ports on the container border ──────────────────────────────────
        // Graphviz keeps every node of a cluster inside its box, so the ports are laid out in
        // the cluster's first / last rank. Here the cluster's top (left with left-to-right)
        // and bottom (right) edges are moved onto the centres of those port squares and the
        // title goes below the top ports. Nodes and links stay where Graphviz put them.

        private static string svg_title(string id) {
            return Markup.escape_text(id).replace("-", "&#45;");
        }

        // The <g class="kind"> element whose <title> is `title`, or null
        private static string? svg_group(string svg, string kind, string title, out int start, out int end) {
            start = -1;
            end = -1;
            try {
                var re = new Regex("<g id=\"[^\"]*\" class=\"%s\">\\s*<title>%s</title>.*?</g>".printf(
                    kind, Regex.escape_string(svg_title(title))), RegexCompileFlags.DOTALL);
                MatchInfo mi;
                if (re.match(svg, 0, out mi)) {
                    mi.fetch_pos(0, out start, out end);
                    return svg.substring(start, end - start);
                }
            } catch (RegexError e) {
                warning("Port border regex: %s", e.message);
            }
            return null;
        }

        // Bounding box of the polygon points / path coordinates in an SVG fragment
        private static bool svg_shape_bbox(string fragment, out double x0, out double y0, out double x1, out double y1) {
            x0 = double.MAX;
            y0 = double.MAX;
            x1 = -double.MAX;
            y1 = -double.MAX;
            bool found = false;
            try {
                var shapes = new Regex("(?:points|d)=\"([^\"]*)\"");
                var pair = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                MatchInfo mi;
                shapes.match(fragment, 0, out mi);
                while (mi.matches()) {
                    // MatchInfo keeps a pointer to the subject: it must outlive the loop
                    string coords = mi.fetch(1);
                    MatchInfo pi;
                    pair.match(coords, 0, out pi);
                    while (pi.matches()) {
                        double x = double.parse(pi.fetch(1));
                        double y = double.parse(pi.fetch(2));
                        x0 = double.min(x0, x);
                        y0 = double.min(y0, y);
                        x1 = double.max(x1, x);
                        y1 = double.max(y1, y);
                        found = true;
                        pi.next();
                    }
                    mi.next();
                }
            } catch (RegexError e) {
                warning("Port border regex: %s", e.message);
            }
            return found;
        }

        private static string svg_number(double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, "%.2f");
        }

        // Mean centre (x with left-to-right, else y) of the port squares, or NAN
        private static double port_centre(string svg, Gee.ArrayList<string> ports, bool lr) {
            double sum = 0;
            int n = 0;
            foreach (string port in ports) {
                int s, e;
                string? group = svg_group(svg, "node", port, out s, out e);
                double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
                if (group != null && svg_shape_bbox(group, out x0, out y0, out x1, out y1)) {
                    sum += lr ? (x0 + x1) / 2 : (y0 + y1) / 2;
                    n++;
                }
            }
            return n > 0 ? sum / n : double.NAN;
        }

        // Adds `delta` to the x or y attribute of every <text> element in `fragment`
        private static string shift_text_position(string fragment, string axis, double delta) {
            if (delta == 0) {
                return fragment;
            }
            var sb = new StringBuilder();
            try {
                var re = new Regex("<text[^>]* %s=\"(-?[0-9.]+)\"".printf(axis));
                int copied = 0;
                MatchInfo mi;
                re.match(fragment, 0, out mi);
                while (mi.matches()) {
                    int vs, ve;
                    mi.fetch_pos(1, out vs, out ve);
                    sb.append(fragment.substring(copied, vs - copied));
                    sb.append(svg_number(double.parse(mi.fetch(1)) + delta));
                    copied = ve;
                    mi.next();
                }
                sb.append(fragment.substring(copied));
            } catch (RegexError e) {
                warning("Port border regex: %s", e.message);
                return fragment;
            }
            return sb.str;
        }

        public static string place_ports_on_border(string svg, Gee.ArrayList<PortBorderLayout> layouts, bool lr) {
            string result = svg;
            foreach (var layout in layouts) {
                int start, end;
                string? group = svg_group(result, "cluster", layout.cluster, out start, out end);
                double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
                if (group == null || !svg_shape_bbox(group, out x0, out y0, out x1, out y1)) {
                    continue;
                }
                double lo = lr ? x0 : y0;
                double hi = lr ? x1 : y1;
                double top = port_centre(result, layout.top_ports, lr);
                double bottom = port_centre(result, layout.bottom_ports, lr);
                double d_lo = top.is_nan() ? 0 : top - lo;
                double d_hi = bottom.is_nan() ? 0 : bottom - hi;
                if (d_lo < 0 || d_hi > 0 || lo + d_lo >= hi + d_hi) {
                    continue;
                }
                // Coordinates of an edge and its rounded corners move with it
                double band = double.min(13, (hi - lo) / 3);
                var moved = new StringBuilder();
                try {
                    var attr = new Regex("(?:points|d)=\"([^\"]*)\"");
                    var pair = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                    int copied = 0;
                    MatchInfo mi;
                    attr.match(group, 0, out mi);
                    while (mi.matches()) {
                        int cs, ce;
                        mi.fetch_pos(1, out cs, out ce);
                        moved.append(group.substring(copied, cs - copied));
                        string coords = group.substring(cs, ce - cs);
                        int done = 0;
                        MatchInfo pi;
                        pair.match(coords, 0, out pi);
                        while (pi.matches()) {
                            int ps, pe;
                            pi.fetch_pos(0, out ps, out pe);
                            moved.append(coords.substring(done, ps - done));
                            double x = double.parse(pi.fetch(1));
                            double y = double.parse(pi.fetch(2));
                            double c = lr ? x : y;
                            if (c <= lo + band) {
                                c += d_lo;
                            } else if (c >= hi - band) {
                                c += d_hi;
                            }
                            moved.append("%s,%s".printf(svg_number(lr ? c : x), svg_number(lr ? y : c)));
                            done = pe;
                            pi.next();
                        }
                        moved.append(coords.substring(done));
                        copied = ce;
                        mi.next();
                    }
                    moved.append(group.substring(copied));
                } catch (RegexError e) {
                    warning("Port border regex: %s", e.message);
                    continue;
                }
                // The title: below the top ports, or re-centred between the moved sides
                double text_shift = lr ? (d_lo + d_hi) / 2 : (d_lo > 0 ? d_lo + 5 : 0);
                string shifted = shift_text_position(moved.str, lr ? "x" : "y", text_shift);
                result = result.substring(0, start) + shifted + result.substring(end);
            }
            return result;
        }

        public uint8[]? render_to_svg(ComponentDiagram diagram) {
            string dot = generate_dot(diagram);

            string[] argv = {layout_engine, "-Gfontname=Sans", "-Tsvg"};  // Sans cluster titles, not Times
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

                string with_sprites = sprite_cells.draw(std_out, node_font_color);
                string laid_out = port_layouts.size > 0 ? place_ports_on_border(with_sprites, port_layouts, left_to_right) : with_sprites;
                string shaped = draw_shapes(laid_out, node_shapes, cluster_shapes);
                return RenderUtils.draw_actor_figures(RenderUtils.draw_custom_markers(RenderUtils.fill_svg_background(shaped.data)));
            } catch (Error e) {
                warning("Failed to run dot: %s", e.message);
                return null;
            }
        }

        // The SVG with every node group's class reduced to "node", for parse_svg_regions()
        public static uint8[] region_svg(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            try {
                return new Regex("class=\"node [^\"]*\"").replace_literal(text.str, -1, 0, "class=\"node\"").data;
            } catch (RegexError e) {
                return svg_data;
            }
        }

        // ── Element and container shapes ───────────────────────────────────
        // Graphviz has no cloud, queue, stack, storage, frame, package tab, 3D node container,
        // UML component icon or boundary / control / entity / interface icons. The DOT draws a
        // box (or an HTML label with a sentinel cell) and this step draws PlantUML's shape
        // over it. Graphviz's own shape stays in the group, see-through, so click regions
        // (which read its points) and title colouring keep working.

        private static string num(double v) {
            return svg_number(v);
        }

        private static string paint(string attr, string colour) {
            string c = colour.strip();
            if (c.contains(":")) {
                c = c.split(":")[0];
            }
            string low = c.down();
            if (low == "transparent" || low == "none" || c.length == 0) {
                return "%s=\"none\"".printf(attr);
            }
            string first, second;
            int angle;
            if (RenderUtils.parse_gradient(c, out first, out second, out angle)) {
                c = first;
            }
            return "%s=\"%s\"".printf(attr, Markup.escape_text(RenderUtils.sanitize_color(c)));
        }

        private static string dash_attr(string dash) {
            switch (dash) {
                case "dashed": return " stroke-dasharray=\"5,2\"";
                case "dotted": return " stroke-dasharray=\"1,5\"";
                case "bold": return " stroke-width=\"2\"";
                default: return "";
            }
        }

        private static bool points_bbox(string coords, out double x0, out double y0, out double x1, out double y1) {
            x0 = double.MAX;
            y0 = double.MAX;
            x1 = -double.MAX;
            y1 = -double.MAX;
            bool found = false;
            try {
                var pair = new Regex("(-?[0-9.]+),(-?[0-9.]+)");
                MatchInfo pi;
                pair.match(coords, 0, out pi);
                while (pi.matches()) {
                    double x = double.parse(pi.fetch(1));
                    double y = double.parse(pi.fetch(2));
                    x0 = double.min(x0, x);
                    y0 = double.min(y0, y);
                    x1 = double.max(x1, x);
                    y1 = double.max(y1, y);
                    found = true;
                    pi.next();
                }
            } catch (RegexError e) {
                warning("Shape regex: %s", e.message);
            }
            return found;
        }

        public static string draw_shapes(string svg, Gee.HashMap<string, ComponentShapeInfo> nodes,
                                         Gee.HashMap<string, ComponentShapeInfo> clusters) {
            string result = svg;
            foreach (var entry in nodes.entries) {
                int start, end;
                string? group = svg_group(result, "node", entry.key, out start, out end);
                if (group == null) {
                    continue;
                }
                string? drawn = is_icon_kind(entry.value.kind) ? draw_icon(group, entry.value)
                                                                : draw_outline(group, entry.value, false);
                if (drawn != null) {
                    result = result.substring(0, start) + drawn + result.substring(end);
                }
            }
            foreach (var entry in clusters.entries) {
                int start, end;
                string? group = svg_group(result, "cluster", entry.key, out start, out end);
                if (group == null) {
                    continue;
                }
                string? drawn = draw_outline(group, entry.value, true);
                if (drawn != null) {
                    result = result.substring(0, start) + drawn + result.substring(end);
                }
            }
            return result;
        }

        private static bool is_icon_kind(string kind) {
            return kind == "interface" || kind == "circle" || kind == "boundary" || kind == "control" ||
                   kind == "entity" || kind == "person";
        }

        // The sentinel cell of an icon node becomes the icon
        private static string? draw_icon(string group, ComponentShapeInfo info) {
            try {
                var re = new Regex("<polygon fill=\"%s\" stroke=\"[^\"]*\" points=\"([^\"]*)\"/>".printf(SENTINEL));
                MatchInfo mi;
                if (!re.match(group, 0, out mi)) {
                    return null;
                }
                double x0, y0, x1, y1;
                if (!points_bbox(mi.fetch(1), out x0, out y0, out x1, out y1)) {
                    return null;
                }
                int ms, me;
                mi.fetch_pos(0, out ms, out me);
                double w = x1 - x0;
                double h = y1 - y0;
                double cx = (x0 + x1) / 2;
                double cy = (y0 + y1) / 2;
                string attrs = "%s %s stroke-width=\"1.2\"%s".printf(paint("fill", info.fill), paint("stroke", info.stroke), dash_attr(info.dash));
                string line_attrs = "fill=\"none\" %s stroke-width=\"1.2\"%s".printf(paint("stroke", info.stroke), dash_attr(info.dash));
                var icon = new StringBuilder();
                switch (info.kind) {
                    case "boundary": {
                        double r = h / 2 - 1;
                        double ccx = x1 - r - 1;
                        double bar = x0 + 1;
                        icon.append("<path class=\"gdicon\" %s d=\"M%s,%s L%s,%s M%s,%s L%s,%s\"/>".printf(line_attrs,
                            num(bar), num(cy - r), num(bar), num(cy + r), num(bar), num(cy), num(ccx - r), num(cy)));
                        icon.append("<circle class=\"gdicon\" %s cx=\"%s\" cy=\"%s\" r=\"%s\"/>".printf(attrs, num(ccx), num(cy), num(r)));
                        break;
                    }
                    case "control": {
                        double r = double.min(w, h) / 2 - 3;
                        double ccy = cy + 2;
                        icon.append("<circle class=\"gdicon\" %s cx=\"%s\" cy=\"%s\" r=\"%s\"/>".printf(attrs, num(cx), num(ccy), num(r)));
                        icon.append("<path class=\"gdicon\" %s d=\"M%s,%s L%s,%s L%s,%s\"/>".printf(line_attrs,
                            num(cx + 3), num(ccy - r - 4), num(cx - 2), num(ccy - r), num(cx + 3), num(ccy - r + 4)));
                        break;
                    }
                    case "entity": {
                        double r = double.min(w, h - 4) / 2 - 1;
                        double ccy = y0 + 1 + r;
                        icon.append("<circle class=\"gdicon\" %s cx=\"%s\" cy=\"%s\" r=\"%s\"/>".printf(attrs, num(cx), num(ccy), num(r)));
                        icon.append("<path class=\"gdicon\" %s d=\"M%s,%s L%s,%s\"/>".printf(line_attrs,
                            num(cx - r), num(ccy + r + 2), num(cx + r), num(ccy + r + 2)));
                        break;
                    }
                    default: {
                        double r = double.min(w, h) / 2 - 1;
                        icon.append("<circle class=\"gdicon\" %s cx=\"%s\" cy=\"%s\" r=\"%s\"/>".printf(attrs, num(cx), num(cy), num(r)));
                        break;
                    }
                }
                string hidden = "<polygon fill=\"none\" stroke=\"none\" points=\"%s\"/>".printf(mi.fetch(1));
                return group.substring(0, ms) + hidden + icon.str + group.substring(me);
            } catch (RegexError e) {
                warning("Shape regex: %s", e.message);
                return null;
            }
        }

        // Estimated right edge and lowest baseline of the title texts in a cluster group
        private static void title_extent(string group, double x0, out double right, out double bottom) {
            right = x0;
            bottom = -double.MAX;
            try {
                var re = new Regex("<text[^>]* x=\"(-?[0-9.]+)\" y=\"(-?[0-9.]+)\"[^>]*font-size=\"([0-9.]+)\"[^>]*>([^<]*)</text>");
                MatchInfo mi;
                re.match(group, 0, out mi);
                while (mi.matches()) {
                    double x = double.parse(mi.fetch(1));
                    double y = double.parse(mi.fetch(2));
                    double size = double.parse(mi.fetch(3));
                    string content = mi.fetch(4);
                    right = double.max(right, x + content.char_count() * size * 0.62);
                    bottom = double.max(bottom, y);
                    mi.next();
                }
            } catch (RegexError e) {
                warning("Shape regex: %s", e.message);
            }
        }

        private static string rect_path(double x0, double y0, double x1, double y1) {
            return "M%s,%s L%s,%s L%s,%s L%s,%s Z".printf(num(x0), num(y0), num(x1), num(y0), num(x1), num(y1), num(x0), num(y1));
        }

        private static string cloud_path(double x0, double y0, double x1, double y1) {
            double i = double.min(8, double.min((y1 - y0) / 4, (x1 - x0) / 4));
            double l = x0 + i, t = y0 + i, r = x1 - i, b = y1 - i;
            int nx = int.max(2, (int) Math.round((r - l) / 26));
            int ny = int.max(1, (int) Math.round((b - t) / 26));
            double sx = (r - l) / nx;
            double sy = (b - t) / ny;
            var d = new StringBuilder("M%s,%s".printf(num(l), num(t)));
            for (int k = 1; k <= nx; k++) {
                d.append(" A%s,%s 0 0 1 %s,%s".printf(num(sx / 2), num(i), num(l + sx * k), num(t)));
            }
            for (int k = 1; k <= ny; k++) {
                d.append(" A%s,%s 0 0 1 %s,%s".printf(num(i), num(sy / 2), num(r), num(t + sy * k)));
            }
            for (int k = 1; k <= nx; k++) {
                d.append(" A%s,%s 0 0 1 %s,%s".printf(num(sx / 2), num(i), num(r - sx * k), num(b)));
            }
            for (int k = 1; k <= ny; k++) {
                d.append(" A%s,%s 0 0 1 %s,%s".printf(num(i), num(sy / 2), num(l), num(b - sy * k)));
            }
            d.append(" Z");
            return d.str;
        }

        private static string rounded_path(double x0, double y0, double x1, double y1, double rad) {
            double r = double.min(rad, double.min((x1 - x0) / 2, (y1 - y0) / 2));
            return "M%s,%s L%s,%s A%s,%s 0 0 1 %s,%s L%s,%s A%s,%s 0 0 1 %s,%s L%s,%s A%s,%s 0 0 1 %s,%s L%s,%s A%s,%s 0 0 1 %s,%s Z".printf(
                num(x0 + r), num(y0), num(x1 - r), num(y0), num(r), num(r), num(x1), num(y0 + r),
                num(x1), num(y1 - r), num(r), num(r), num(x1 - r), num(y1),
                num(x0 + r), num(y1), num(r), num(r), num(x0), num(y1 - r),
                num(x0), num(y0 + r), num(r), num(r), num(x0 + r), num(y0));
        }

        // Graphviz's outline of a box node or cluster, replaced by the PlantUML shape
        private static string? draw_outline(string group, ComponentShapeInfo info, bool cluster) {
            try {
                var re = new Regex("<(polygon|path) fill=\"([^\"]*)\" stroke=\"([^\"]*)\"((?: [a-z-]+=\"[^\"]*\")*?) (points|d)=\"([^\"]*)\"/>");
                MatchInfo mi;
                if (!re.match(group, 0, out mi)) {
                    return null;
                }
                double x0, y0, x1, y1;
                if (!points_bbox(mi.fetch(6), out x0, out y0, out x1, out y1)) {
                    return null;
                }
                int ms, me;
                mi.fetch_pos(0, out ms, out me);
                string fill = mi.fetch(2);
                string stroke = mi.fetch(3);
                string extra = mi.fetch(4);
                string attrs = "fill=\"%s\" stroke=\"%s\"%s".printf(fill, stroke, extra);
                string line_attrs = "fill=\"none\" stroke=\"%s\"%s".printf(stroke, extra);
                double w = x1 - x0;
                double h = y1 - y0;
                var shape = new StringBuilder();
                string rest = group.substring(me);
                switch (info.kind) {
                    case "cloud":
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs, cloud_path(x0, y0, x1, y1)));
                        break;
                    case "queue": {
                        double rx = double.min(cluster ? 12 : 8, w / 6);
                        double ry = h / 2;
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s A%s,%s 0 0 1 %s,%s L%s,%s A%s,%s 0 0 1 %s,%s Z\"/>".printf(attrs,
                            num(x0 + rx), num(y0), num(x1 - rx), num(y0), num(rx), num(ry), num(x1 - rx), num(y1),
                            num(x0 + rx), num(y1), num(rx), num(ry), num(x0 + rx), num(y0)));
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s A%s,%s 0 0 0 %s,%s\"/>".printf(line_attrs,
                            num(x1 - rx), num(y0), num(rx), num(ry), num(x1 - rx), num(y1)));
                        break;
                    }
                    case "storage":
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs,
                            rounded_path(x0, y0, x1, y1, cluster ? 25 : h / 2)));
                        break;
                    case "stack": {
                        double d = double.min(10, w / 6);
                        shape.append("<path class=\"gdshape\" fill=\"%s\" stroke=\"none\" d=\"%s\"/>".printf(fill, rect_path(x0 + d, y0, x1 - d, y1)));
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s\"/>".printf(line_attrs,
                            num(x0), num(y0), num(x0 + d), num(y0), num(x0 + d), num(y1), num(x1 - d), num(y1),
                            num(x1 - d), num(y0), num(x1), num(y0)));
                        break;
                    }
                    case "collections": {
                        double o = 4;
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs, rect_path(x0 + o, y0 + o, x1, y1)));
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs, rect_path(x0, y0, x1 - o, y1 - o)));
                        break;
                    }
                    case "component": {
                        double ix = x1 - 20;
                        double iy = y0 + 5;
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs, rect_path(x0, y0, x1, y1)));
                        shape.append("<path class=\"gdicon\" %s d=\"%s\"/>".printf(attrs, rect_path(ix, iy, ix + 15, iy + 10)));
                        shape.append("<path class=\"gdicon\" %s d=\"%s %s\"/>".printf(attrs,
                            rect_path(ix - 2, iy + 2, ix + 2, iy + 4), rect_path(ix - 2, iy + 6, ix + 2, iy + 8)));
                        break;
                    }
                    case "node": {
                        // A 3D box: front face, top and right side
                        double d = 10;
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs, rect_path(x0, y0 + d, x1 - d, y1)));
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s L%s,%s L%s,%s Z M%s,%s L%s,%s L%s,%s L%s,%s Z\"/>".printf(attrs,
                            num(x0), num(y0 + d), num(x0 + d), num(y0), num(x1), num(y0), num(x1 - d), num(y0 + d),
                            num(x1 - d), num(y0 + d), num(x1), num(y0), num(x1), num(y1 - d), num(x1 - d), num(y1)));
                        rest = shift_text_position(rest, "y", d);
                        break;
                    }
                    case "database": {
                        double ry = double.min(10, h / 10);
                        double rx = w / 2;
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s A%s,%s 0 0 0 %s,%s L%s,%s A%s,%s 0 0 0 %s,%s Z\"/>".printf(attrs,
                            num(x0), num(y0 + ry), num(x0), num(y1 - ry), num(rx), num(ry), num(x1), num(y1 - ry),
                            num(x1), num(y0 + ry), num(rx), num(ry), num(x0), num(y0 + ry)));
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s A%s,%s 0 0 0 %s,%s\"/>".printf(line_attrs,
                            num(x0), num(y0 + ry), num(rx), num(ry), num(x1), num(y0 + ry)));
                        break;
                    }
                    case "package":
                    case "folder": {
                        // A tab at the top left; a container's title sits in it
                        double tab_right, tab_bottom;
                        if (cluster) {
                            double text_right, baseline;
                            title_extent(rest, x0, out text_right, out baseline);
                            tab_right = double.min(x1 - 8, double.max(text_right + 6, x0 + 30));
                            tab_bottom = baseline > y0 ? double.min(y1 - 4, baseline + 5) : y0 + 14;
                        } else {
                            tab_right = x0 + double.max(18, w * (info.kind == "folder" ? 0.3 : 0.4));
                            tab_bottom = y0 + double.min(10, h / 4);
                        }
                        double slant = info.kind == "folder" ? 4 : 6;
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s Z\"/>".printf(attrs,
                            num(x0), num(y0), num(tab_right), num(y0), num(tab_right + slant), num(tab_bottom),
                            num(x1), num(tab_bottom), num(x1), num(y1), num(x0), num(y1)));
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s\"/>".printf(line_attrs,
                            num(x0), num(tab_bottom), num(tab_right + slant), num(tab_bottom)));
                        break;
                    }
                    case "frame": {
                        // The title in a notched box at the top left corner
                        double tab_right, tab_bottom;
                        if (cluster) {
                            double text_right, baseline;
                            title_extent(rest, x0, out text_right, out baseline);
                            tab_right = double.min(x1 - 10, double.max(text_right + 4, x0 + 20));
                            tab_bottom = baseline > y0 ? double.min(y1 - 4, baseline + 5) : y0 + 14;
                        } else {
                            tab_right = x0 + double.min(14, w / 3);
                            tab_bottom = y0 + double.min(10, h / 3);
                        }
                        double notch = double.min(8, tab_bottom - y0);
                        shape.append("<path class=\"gdshape\" %s d=\"%s\"/>".printf(attrs, rect_path(x0, y0, x1, y1)));
                        shape.append("<path class=\"gdshape\" %s d=\"M%s,%s L%s,%s L%s,%s L%s,%s\"/>".printf(line_attrs,
                            num(x0), num(tab_bottom), num(tab_right), num(tab_bottom), num(tab_right + notch),
                            num(tab_bottom - notch), num(tab_right + notch), num(y0)));
                        break;
                    }
                    default:
                        return null;
                }
                // Graphviz's own shape stays, see-through: click regions and title colours read it
                string hidden = group.substring(ms, me - ms).replace(" fill=\"", " fill-opacity=\"0\" stroke-opacity=\"0\" fill=\"");
                return group.substring(0, ms) + hidden + shape.str + rest;
            } catch (RegexError e) {
                warning("Shape regex: %s", e.message);
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

                // Parse SVG regions for click-to-source navigation (with pixel scaling). Actor
                // figures carry extra classes ("node gdactor ..."), which the region parser
                // doesn't take for nodes.
                RenderUtils.parse_svg_regions(region_svg(svg_data), last_regions, element_lines, width, height);

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
