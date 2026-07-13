namespace GDiagram {
    public class MermaidClassRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> regions;
        private string layout_engine;
        private MermaidClassDiagram? current_diagram = null;

        public MermaidClassRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(MermaidClassDiagram diagram) {
            current_diagram = diagram;
            var dot = new StringBuilder();

            var palette = ThemeManager.get_active_palette();
            dot.append("digraph G {\n");
            dot.append_printf("  rankdir=%s;\n", MermaidSourceLine.rankdir(diagram.direction));
            dot.append("  bgcolor=\"%s\";\n".printf(palette.background));
            // Classes are HTML tables (shape=plain): name, attribute and method
            // compartments as in Mermaid, with italic/underlined members
            dot.append("  node [fontname=\"Sans\", fontsize=10, shape=plain, fontcolor=\"%s\", color=\"%s\"];\n".printf(palette.node_text, palette.node_border));
            dot.append("  edge [fontname=\"Sans\", fontsize=9, color=\"%s\", fontcolor=\"%s\"];\n".printf(palette.edge_color, palette.edge_text));
            dot.append("\n");

            // Title
            if (diagram.title != null && diagram.title.length > 0) {
                dot.append_printf("  label=\"%s\";\n", RenderUtils.escape_label(diagram.title));
                dot.append("  labelloc=t;\n");
                dot.append("  fontsize=14;\n");
                dot.append_printf("  fontcolor=\"%s\";\n\n", palette.node_text);
            }

            // Render classes (namespaces as clusters, in first-seen order)
            dot.append("  // Classes\n");
            var namespaces = new Gee.ArrayList<string>();
            foreach (var cls in diagram.classes) {
                if (cls.namespace_name != null && !namespaces.contains(cls.namespace_name)) {
                    namespaces.add(cls.namespace_name);
                }
            }
            int ns_idx = 0;
            foreach (string ns in namespaces) {
                dot.append_printf("  subgraph cluster_ns_%d {\n", ns_idx++);
                dot.append_printf("    label=\"%s\";\n", RenderUtils.escape_label(ns));
                dot.append_printf("    style=\"rounded\";\n    color=\"%s\";\n    fontcolor=\"%s\";\n    fontname=\"Sans\";\n    fontsize=11;\n",
                                  palette.node_border, palette.node_text);
                foreach (var cls in diagram.classes) {
                    if (cls.namespace_name == ns) render_class(dot, cls, "    ");
                }
                dot.append("  }\n");
            }
            foreach (var cls in diagram.classes) {
                if (cls.namespace_name == null) render_class(dot, cls, "  ");
            }

            // Notes
            int note_idx = 0;
            foreach (var note in diagram.notes) {
                string note_id = "note_%d".printf(note_idx++);
                dot.append_printf("  %s [label=\"%s\", shape=note, style=filled, fillcolor=\"%s\", fontcolor=\"%s\", color=\"%s\"];\n",
                    note_id, RenderUtils.escape_label(note.text), palette.accent_secondary,
                    RenderUtils.contrast_text(palette.accent_secondary), palette.node_border);
                if (note.for_class != null) {
                    dot.append_printf("  %s -> %s [style=dotted, arrowhead=none];\n",
                        note_id, RenderUtils.sanitize_id(note.for_class.name));
                }
            }

            dot.append("\n");

            // Render relationships
            if (diagram.relations.size > 0) {
                dot.append("  // Relationships\n");
                foreach (var relation in diagram.relations) {
                    render_relation(dot, relation);
                }
            }

            dot.append("}\n");

            return dot.str;
        }

        private void render_class(StringBuilder dot, MermaidClass cls, string indent) {
            var palette = ThemeManager.get_active_palette();
            string safe_id = RenderUtils.sanitize_id(cls.name);

            // A lollipop interface is just its name: the circle is the edge's marker
            if (is_lollipop_only(cls)) {
                dot.append_printf("%s%s [label=\"%s\", shape=plaintext, margin=0.02, fontcolor=\"%s\"];\n",
                    indent, safe_id, RenderUtils.escape_label(cls.label ?? cls.name), palette.node_text);
                return;
            }

            string fill = palette.node_fill;
            string border = palette.node_border;
            string? text = null;
            var specs = new Gee.ArrayList<string>();
            if (current_diagram != null) {
                foreach (string css in cls.css_classes) {
                    if (current_diagram.class_defs.has_key(css)) specs.add(current_diagram.class_defs.get(css));
                }
            }
            if (cls.inline_style != null) specs.add(cls.inline_style);
            string? s_fill, s_stroke, s_text;
            MermaidSourceLine.style_colors(specs, out s_fill, out s_stroke, out s_text);
            if (s_fill != null) {
                fill = RenderUtils.sanitize_color(s_fill);
                text = RenderUtils.contrast_text(fill);
            }
            if (s_stroke != null) border = RenderUtils.sanitize_color(s_stroke);
            if (s_text != null) text = RenderUtils.sanitize_color(s_text);

            var attrs = new StringBuilder();
            var methods = new StringBuilder();
            foreach (var member in cls.members) {
                unowned StringBuilder target = member.is_method ? methods : attrs;
                target.append(member_html(member));
                target.append("<BR ALIGN=\"LEFT\"/>");
            }

            var label = new StringBuilder();
            label.append_printf("<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\" BGCOLOR=\"%s\" COLOR=\"%s\">",
                                fill, border);
            label.append("<TR><TD>");
            string stereotype = get_stereotype_label(cls);
            if (stereotype.length > 0) {
                label.append(Markup.escape_text(stereotype)).append("<BR/>");
            }
            string title = cls.label ?? cls.name;
            if (cls.generic_type != null) title += "<" + cls.generic_type + ">";
            label.append("<B>").append(Markup.escape_text(title)).append("</B></TD></TR><HR/>");
            label.append_printf("<TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">%s</TD></TR><HR/>",
                                attrs.len > 0 ? attrs.str : " ");
            label.append_printf("<TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\">%s</TD></TR>",
                                methods.len > 0 ? methods.str : " ");
            label.append("</TABLE>");

            string font = text != null ? ", fontcolor=\"%s\"".printf(text) : "";
            dot.append_printf("%s%s [label=<%s>%s];\n", indent, safe_id, label.str, font);

            // (Regions populated with real bounds in render_to_surface)
        }

        // Drawn as a bare lollipop: marked by the parser and with nothing a box would show
        private static bool is_lollipop_only(MermaidClass cls) {
            return cls.lollipop_interface && cls.members.size == 0 &&
                   (cls.stereotype == null || cls.stereotype.length == 0) &&
                   cls.class_type == MermaidClassType.CLASS;
        }

        // "+getArea(x float) : float", italic when abstract, underlined when static
        private string member_html(MermaidClassMember member) {
            string text = member.display_text;
            if (text == null) {
                var sb = new StringBuilder();
                sb.append(get_visibility_symbol(member.visibility));
                if (member.is_method) {
                    sb.append(member.name).append("(").append(member.parameters ?? "").append(")");
                    if (member.type_name != null && member.type_name.length > 0) {
                        sb.append(" : ").append(member.type_name);
                    }
                } else {
                    if (member.type_name != null && member.type_name.length > 0) {
                        sb.append(member.type_name).append(" ");
                    }
                    sb.append(member.name);
                }
                text = sb.str;
            }
            string html = Markup.escape_text(text);
            if (member.is_abstract) html = "<I>" + html + "</I>";
            if (member.is_static) html = "<U>" + html + "</U>";
            return html;
        }

        private string get_stereotype_label(MermaidClass cls) {
            string? st = cls.stereotype;
            if (st == null || st.length == 0) {
                switch (cls.class_type) {
                    case MermaidClassType.INTERFACE: st = "interface"; break;
                    case MermaidClassType.ABSTRACT:  st = "abstract"; break;
                    case MermaidClassType.ENUM:      st = "enumeration"; break;
                    default: return "";
                }
            }
            return "«%s»".printf(st);
        }

        private string get_visibility_symbol(MermaidVisibility vis) {
            switch (vis) {
                case MermaidVisibility.PRIVATE:
                    return "-";
                case MermaidVisibility.PROTECTED:
                    return "#";
                case MermaidVisibility.PACKAGE:
                    return "~";
                default:
                    return "+";
            }
        }

        // "A <|-- B": A ranks above B (as in Mermaid) and each marker sits at the end
        // it is written on
        private void render_relation(StringBuilder dot, MermaidRelation relation) {
            string from_id = RenderUtils.sanitize_id(relation.from.name);
            string to_id = RenderUtils.sanitize_id(relation.to.name);

            var attrs = new Gee.ArrayList<string>();

            if (relation.label != null && relation.label.length > 0) {
                attrs.add("label=\"%s\"".printf(RenderUtils.escape_label(relation.label)));
            }
            if (relation.from_cardinality != null) {
                attrs.add("taillabel=\"%s\"".printf(RenderUtils.escape_label(relation.from_cardinality)));
            }
            if (relation.to_cardinality != null) {
                attrs.add("headlabel=\"%s\"".printf(RenderUtils.escape_label(relation.to_cardinality)));
            }
            if (relation.from_cardinality != null || relation.to_cardinality != null) {
                // keep "*" clear of the arrowhead
                attrs.add("labeldistance=2");
            }
            if (relation.dashed) {
                attrs.add("style=dashed");
            }
            attrs.add("dir=both");
            attrs.add("arrowtail=%s".printf(marker_arrow(relation.from_end)));
            attrs.add("arrowhead=%s".printf(marker_arrow(relation.to_end)));
            if (relation.from_end == MermaidRelationEnd.LOLLIPOP ||
                relation.to_end == MermaidRelationEnd.LOLLIPOP) {
                // Mermaid's lollipop circle is as wide as the interface marker, not a dot
                attrs.add("arrowsize=1.4");
            }

            dot.append_printf("  %s -> %s [%s];\n", from_id, to_id, string.joinv(", ", attrs.to_array()));
        }

        private string marker_arrow(MermaidRelationEnd end) {
            switch (end) {
                case MermaidRelationEnd.INHERITANCE: return "empty";
                case MermaidRelationEnd.COMPOSITION: return "diamond";
                case MermaidRelationEnd.AGGREGATION: return "odiamond";
                case MermaidRelationEnd.ARROW:       return "vee";
                case MermaidRelationEnd.LOLLIPOP:    return "odot";
                default:                             return "none";
            }
        }

        // Render to SVG using Graphviz
        public uint8[]? render_to_svg(MermaidClassDiagram diagram) {
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
        public Cairo.ImageSurface? render_to_surface(MermaidClassDiagram diagram) {
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
                foreach (var cls in diagram.classes) {
                    if (cls.source_line > 0)
                        element_lines.set(RenderUtils.sanitize_id(cls.name), cls.source_line);
                }
                RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
                return surface;
            } catch (Error e) {
                warning("Failed to render SVG: %s", e.message);
                return null;
            }
        }

        // Export methods
        public bool export_to_png(MermaidClassDiagram diagram, string filename) {
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(MermaidClassDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(MermaidClassDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
