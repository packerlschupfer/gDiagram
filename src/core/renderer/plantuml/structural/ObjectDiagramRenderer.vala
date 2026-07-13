namespace GDiagram {
    public class ObjectDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public ObjectDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ObjectDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values (palette as fallback when skin_params empty)
            var palette = ThemeManager.get_active_palette();
            string bg_raw = diagram.skin_params.background_color ?? palette.background;
            string bg_color = RenderUtils.fill_color(bg_raw);
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            string font_color = RenderUtils.sanitize_color(diagram.skin_params.default_font_color ?? palette.node_text);

            sb.append("digraph object {\n");
            skin = diagram.skin_params;
            left_to_right = diagram.left_to_right;
            package_index = new Gee.HashMap<ObjectPackage, int>();
            assign_node_ids(diagram);
            sb.append("  rankdir=%s;\n".printf(left_to_right ? "LR" : "TB"));
            sb.append("  compound=true;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            string bg_angle = RenderUtils.gradient_stmt(bg_raw);
            if (bg_angle != "") {
                sb.append("  %s\n".printf(bg_angle));
            }
            sb.append("  node [style=\"filled\", fontname=\"%s\", fontsize=%s, fontcolor=\"%s\", shape=record];\n".printf(font_name, font_size, font_color));
            sb.append("  edge [fontname=\"%s\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(
                font_name, RenderUtils.edge_line_color(diagram.skin_params, palette),
                RenderUtils.edge_label_color(diagram.skin_params, palette)));

            // Add title if present
            if (diagram.title != null && diagram.title.length > 0) {
                sb.append("  labelloc=\"t\";\n");
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"Sans Bold\";\n");
                sb.append("  fontcolor=\"%s\";\n".printf(RenderUtils.title_color(diagram.skin_params, palette)));
            }

            sb.append("\n");

            // Get object colors from theme
            obj_color_raw = diagram.skin_params.get_element_property("object", "BackgroundColor") ?? palette.node_fill;
            string obj_color = RenderUtils.fill_color(obj_color_raw);
            string obj_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("object", "BorderColor") ?? palette.node_border);

            // Render objects and maps; those declared in a package go inside its box
            sb.append("  // Objects\n");
            foreach (var obj in diagram.objects) {
                if (obj.owner_package == null) {
                    append_object_node(sb, obj, "  ", obj_color, obj_border);
                }
            }
            if (diagram.packages.size > 0) {
                pkg_bg_raw = diagram.skin_params.get_element_property("package", "BackgroundColor") ?? palette.grid;
                string pkg_bg = RenderUtils.fill_color(pkg_bg_raw);
                string pkg_border = RenderUtils.sanitize_color(
                    diagram.skin_params.get_element_property("package", "BorderColor") ?? obj_border);
                int pkg_idx = 0;
                foreach (var pkg in diagram.packages) {
                    append_package(sb, pkg, "  ", pkg_bg, pkg_border, obj_color, obj_border, font_name, ref pkg_idx);
                }
            }

            // Render notes
            if (diagram.notes.size > 0) {
                sb.append("\n  // Notes\n");
                string note_color_raw = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary;
                string note_color = RenderUtils.fill_color(note_color_raw);
                string note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_color));

                foreach (var note in diagram.notes) {
                    sb.append("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\"%s, fontcolor=\"%s\"];\n".printf(
                        note.id, RenderUtils.escape_label(RenderUtils.strip_inline_creole(note.text)), note_color,
                        RenderUtils.gradient_attr(note_color_raw), note_font));

                    if (note.attached_to != null) {
                        var target = diagram.find_object(note.attached_to);
                        if (target != null) {
                            sb.append("  %s -> %s [style=dashed, arrowhead=none];\n".printf(
                                note.id, node_id(target)));
                        }
                    }
                }
            }

            // Render links
            sb.append("\n  // Links\n");
            foreach (var link in diagram.links) {
                int from_pkg;
                int to_pkg;
                string? from_id = endpoint_id(diagram, link.from_id, link.from_row, out from_pkg);
                string? to_id = endpoint_id(diagram, link.to_id, link.to_row, out to_pkg);
                if (from_id == null || to_id == null) continue;

                string style = link.is_dashed ? "dashed" : "solid";
                string arrowhead = link.has_head ? "vee" : "none";
                string arrowtail = "none";

                switch (link.link_type) {
                    case ObjectLinkType.AGGREGATION:
                        arrowtail = aggregation_marker_shape(link.end_marker);
                        break;
                    case ObjectLinkType.COMPOSITION:
                        arrowtail = "diamond";
                        break;
                    case ObjectLinkType.INHERITANCE:
                        arrowhead = "empty";
                        break;
                    case ObjectLinkType.DEPENDENCY:
                        style = "dashed";
                        break;
                    default:
                        break;
                }
                if (link.has_tail_head && arrowtail == "none") {
                    arrowtail = "vee";
                }
                if (link.line_style != null) {
                    style = link.line_style;
                }
                string? tail_card = link.from_cardinality;
                string? head_card = link.to_cardinality;
                // "A <|-- B" keeps A above B (PlantUML layout): draw in the written
                // order with the ends swapped
                if (link.text_reversed) {
                    string swap_id = from_id;
                    from_id = to_id;
                    to_id = swap_id;
                    string swap_marker = arrowhead;
                    arrowhead = arrowtail;
                    arrowtail = swap_marker;
                    string? swap_card = tail_card;
                    tail_card = head_card;
                    head_card = swap_card;
                    int swap_pkg = from_pkg;
                    from_pkg = to_pkg;
                    to_pkg = swap_pkg;
                }
                string dir = link.undirected ? "none" : "both";
                var extra = new StringBuilder();
                if (link.line_color != null) {
                    extra.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(link.line_color)));
                }
                if (tail_card != null && tail_card.length > 0) {
                    extra.append(", taillabel=\"%s\"".printf(RenderUtils.escape_label(tail_card)));
                }
                if (head_card != null && head_card.length > 0) {
                    extra.append(", headlabel=\"%s\"".printf(RenderUtils.escape_label(head_card)));
                }
                if ((tail_card != null && tail_card.length > 0) || (head_card != null && head_card.length > 0)) {
                    extra.append(", labeldistance=2, labelangle=-40");
                }
                // A link to a package ends at its border
                if (from_pkg >= 0) {
                    extra.append(", ltail=cluster_opkg%d".printf(from_pkg));
                }
                if (to_pkg >= 0) {
                    extra.append(", lhead=cluster_opkg%d".printf(to_pkg));
                }

                if (link.label != null && link.label.length > 0) {
                    sb.append("  %s -> %s [label=\"%s\", style=%s, arrowhead=%s, arrowtail=%s, dir=%s%s];\n".printf(
                        from_id, to_id, RenderUtils.escape_label(link.label), style, arrowhead, arrowtail, dir, extra.str));
                } else {
                    sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=%s, dir=%s%s];\n".printf(
                        from_id, to_id, style, arrowhead, arrowtail, dir, extra.str));
                }
            }

            sb.append("}\n");

            return ComponentDiagramRenderer.add_legend(sb.str, "  // Objects\n", diagram.legend, diagram.skin_params);
        }

        // Graphviz arrow shape for an aggregation-style end marker as written
        // ("+--" circle-plus, "#--" square, "x--" cross, "}--" crow's foot,
        // "^--" open triangle). All of them used to be drawn as an open diamond.
        // Graphviz has no circle-plus or cross; an open circle and a bar come closest.
        private static string aggregation_marker_shape(string? marker) {
            switch (marker) {
                case "+": return "odot";
                case "#": return "obox";
                case "x": return "tee";
                case "}":
                case "{": return "crow";
                case "^": return "onormal";
                default: return "odiamond";
            }
        }

        private bool left_to_right = false;
        private SkinParams? skin = null;
        // object / package BackgroundColor as written, for their gradient angle
        private string obj_color_raw = "";
        private string pkg_bg_raw = "";
        private Gee.HashMap<ObjectPackage, int> package_index = new Gee.HashMap<ObjectPackage, int>();
        private Gee.HashMap<ObjectInstance, string> node_ids = new Gee.HashMap<ObjectInstance, string>();

        // One DOT id per object: keyword-safe ("edge" as an alias produced invalid DOT)
        // and unique ("task.1" and "task_1" both became task_1 and merged into one node)
        private void assign_node_ids(ObjectDiagram diagram) {
            node_ids = new Gee.HashMap<ObjectInstance, string>();
            var used = new Gee.HashSet<string>();
            foreach (var obj in diagram.objects) {
                string base_id = RenderUtils.sanitize_id(obj.get_id());
                // Note and package anchor ids are the renderer's own
                if (base_id.has_prefix("_obj_note_") || base_id.has_prefix("_opkg")) {
                    base_id = "o" + base_id;
                }
                string id = base_id;
                int n = 2;
                while (used.contains(id)) {
                    id = "%s_%d".printf(base_id, n++);
                }
                used.add(id);
                node_ids.set(obj, id);
            }
        }

        private string node_id(ObjectInstance obj) {
            if (node_ids.has_key(obj)) {
                return node_ids.get(obj);
            }
            return RenderUtils.sanitize_id(obj.get_id());
        }

        private void append_object_node(StringBuilder sb, ObjectInstance obj, string indent,
                                        string obj_color, string obj_border) {
            string id = node_id(obj);
            string? stereo_fill = skin != null && obj.color == null
                ? skin.get_stereotype_property(obj.is_map ? "map" : "object", "BackgroundColor", obj.stereotype) : null;
            string fill = obj.color != null ? RenderUtils.fill_color(obj.color)
                : (stereo_fill != null ? RenderUtils.fill_color(stereo_fill) : obj_color);
            string fill_raw = obj.color ?? stereo_fill ?? obj_color_raw;
            string? stereo_font = skin != null ? skin.get_stereotype_property(obj.is_map ? "map" : "object", "FontColor", obj.stereotype) : null;
            string font = stereo_font != null ? RenderUtils.sanitize_color(stereo_font) : RenderUtils.contrast_text(fill);
            if (obj.is_diamond) {
                sb.append("%s%s [shape=diamond, label=\"\", width=0.3, height=0.3, fixedsize=true, style=filled, fillcolor=\"%s\"%s, color=\"%s\"];\n".printf(
                    indent, id, fill, RenderUtils.gradient_attr(fill_raw), obj_border));
                return;
            }
            if (obj.json_root != null) {
                // PlantUML's json element: the data as nested tables under its name
                var style = DataTableStyle.from_skin(null);
                style.fill = fill;
                style.border = obj_border;
                style.font = font;
                var builder = new DataTableBuilder(style, null, id + "_");
                sb.append("%s%s [shape=plaintext, style=solid, margin=0, fontcolor=\"%s\", label=<%s>];\n".printf(
                    indent, id, font, builder.inline_table(obj.json_root, obj.name)));
                return;
            }
            if (obj.is_class) {
                // A class among objects: circled C, name, empty attribute and method rows
                var c = new StringBuilder();
                c.append("<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">".printf(
                    fill, obj_border));
                c.append("<TR><TD><FONT COLOR=\"#3A8F4A\">Ⓒ</FONT> %s</TD></TR>".printf(
                    Markup.escape_text(obj.get_display_label())));
                var fields = new StringBuilder();
                foreach (var field in obj.fields) {
                    fields.append(Markup.escape_text(field.get_display_text()));
                    fields.append("<BR ALIGN=\"LEFT\"/>");
                }
                c.append("<TR><TD ALIGN=\"LEFT\" HEIGHT=\"8\">%s</TD></TR>".printf(fields.len > 0 ? fields.str : " "));
                c.append("<TR><TD HEIGHT=\"8\"> </TD></TR>");
                c.append("</TABLE>");
                sb.append("%s%s [shape=plaintext, style=solid, fontcolor=\"%s\", label=<%s>];\n".printf(indent, id, font, c.str));
                return;
            }
            if (obj.is_map) {
                // A map is a two-column table: title row, then one "key | value" row
                // each, with a port per row for "Map::key" links
                var t = new StringBuilder();
                t.append("<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\"%s COLOR=\"%s\">".printf(
                    fill, RenderUtils.gradient_html_attr(fill_raw), obj_border));
                // The title as written: "Map **Contry => CapitalCity**" bolds only its part
                t.append("<TR><TD COLSPAN=\"2\">%s</TD></TR>".printf(
                    RenderUtils.convert_creole_to_html(obj.name)));
                for (int i = 0; i < obj.entries.size; i++) {
                    var e = obj.entries[i];
                    if (e.link_row) {
                        // A row holding a link spans the map, as in PlantUML
                        t.append("<TR><TD PORT=\"r%d\" COLSPAN=\"2\">%s</TD></TR>".printf(
                            i, Markup.escape_text(e.key)));
                        continue;
                    }
                    t.append("<TR><TD PORT=\"r%d\" ALIGN=\"LEFT\">%s</TD><TD ALIGN=\"LEFT\">%s</TD></TR>".printf(
                        i, Markup.escape_text(e.key), Markup.escape_text(e.value)));
                }
                t.append("</TABLE>");
                sb.append("%s%s [shape=plaintext, style=solid, fontcolor=\"%s\", label=<%s>];\n".printf(indent, id, font, t.str));
                return;
            }

            var label_parts = new StringBuilder();
            label_parts.append("{");
            label_parts.append(RenderUtils.escape_record_label(obj.get_display_label()));
            if (obj.fields.size > 0) {
                label_parts.append("|");
                bool first = true;
                foreach (var field in obj.fields) {
                    if (!first) {
                        label_parts.append("\\l");
                    }
                    // As written: "name = \"Dummy\"" came out as "name = = Dummy"
                    label_parts.append(RenderUtils.escape_record_label(field.get_display_text()));
                    first = false;
                }
                label_parts.append("\\l");
            }
            label_parts.append("}");
            string label = label_parts.str;
            // Record compartments flip with rankdir; without the braces they stay stacked
            if (left_to_right) {
                label = label.substring(1, label.length - 2);
            }
            sb.append("%s%s [label=\"%s\", style=filled, fillcolor=\"%s\"%s, color=\"%s\", fontcolor=\"%s\"];\n".printf(
                indent, id, label, fill, RenderUtils.gradient_attr(fill_raw), obj_border, font));
        }

        private void append_package(StringBuilder sb, ObjectPackage pkg, string indent, string bg, string border,
                                    string obj_color, string obj_border, string font_name, ref int pkg_idx) {
            int idx = pkg_idx++;
            package_index.set(pkg, idx);
            string fill = pkg.color != null ? RenderUtils.fill_color(pkg.color) : bg;
            string inner = indent + "  ";
            sb.append("%ssubgraph cluster_opkg%d {\n".printf(indent, idx));
            sb.append("%slabel=\"%s\";\n".printf(inner, RenderUtils.escape_label(pkg.label ?? pkg.name)));
            sb.append("%slabeljust=l;\n".printf(inner));
            sb.append("%sstyle=filled;\n".printf(inner));
            sb.append("%sfillcolor=\"%s\";\n".printf(inner, fill));
            string angle = RenderUtils.gradient_stmt(pkg.color ?? pkg_bg_raw);
            if (angle != "") {
                sb.append("%s%s\n".printf(inner, angle));
            }
            sb.append("%scolor=\"%s\";\n".printf(inner, border));
            sb.append("%sfontcolor=\"%s\";\n".printf(inner, RenderUtils.contrast_text(fill)));
            sb.append("%sfontname=\"%s\";\n".printf(inner, font_name));
            foreach (var obj in pkg.objects) {
                append_object_node(sb, obj, inner, obj_color, obj_border);
            }
            foreach (var child in pkg.children) {
                append_package(sb, child, inner, bg, border, obj_color, obj_border, font_name, ref pkg_idx);
            }
            sb.append("%s_opkg%d_anchor [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(inner, idx));
            if (pkg.objects.size == 0 && pkg.children.size == 0) {
                sb.append("%s_opkg%d_empty [label=\"\", shape=point, style=invis, width=0.5];\n".printf(inner, idx));
            }
            sb.append("%s}\n".printf(indent));
        }

        // DOT endpoint for a link end: an object (with its row port for "Map::key") or a
        // package anchor (pkg_idx set so the edge can be clipped at the package border)
        private string? endpoint_id(ObjectDiagram diagram, string name, string? row, out int pkg_idx) {
            pkg_idx = -1;
            var obj = diagram.find_object(name);
            if (obj != null) {
                string id = node_id(obj);
                if (row != null && obj.is_map) {
                    for (int i = 0; i < obj.entries.size; i++) {
                        if (obj.entries[i].key == row) {
                            return "%s:r%d".printf(id, i);
                        }
                    }
                }
                return id;
            }
            // A floating note's alias ("Foo .. N1"); such links were dropped
            foreach (var note in diagram.notes) {
                if (note.alias == name) return note.id;
            }
            var pkg = diagram.find_package(name);
            if (pkg != null && package_index.has_key(pkg)) {
                pkg_idx = package_index.get(pkg);
                return "_opkg%d_anchor".printf(pkg_idx);
            }
            return null;
        }

        public uint8[]? render_to_svg(ObjectDiagram diagram) {
            string dot = generate_dot(diagram);
            return RenderUtils.run_graphviz_subprocess(dot, layout_engine, "object");
        }

        public Cairo.ImageSurface? render_to_surface(ObjectDiagram diagram) {
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
                foreach (var obj in diagram.objects) {
                    if (obj.source_line > 0) {
                        element_lines.set(obj.name, obj.source_line);
                        element_lines.set(node_id(obj), obj.source_line);
                    }
                }
                foreach (var note in diagram.notes) {
                    if (note.source_line > 0) {
                        element_lines.set(note.id, note.source_line);
                    }
                }
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, (int)width, (int)height);

                return surface;
            } catch (Error e) {
                warning("Failed to create surface from SVG: %s", e.message);
                return null;
            }
        }

        public bool export_to_png(ObjectDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(ObjectDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(ObjectDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
