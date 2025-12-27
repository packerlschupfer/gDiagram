namespace GDiagram {
    public class ClassDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        public ClassDiagramRenderer(unowned Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ClassDiagram diagram) {
            var sb = new StringBuilder();

            // Get theme values with defaults
            string bg_color = diagram.skin_params.background_color ?? "white";
            string class_bg = diagram.skin_params.get_element_property("class", "BackgroundColor") ?? "#FEFECE";
            string class_border = diagram.skin_params.get_element_property("class", "BorderColor") ?? "black";
            string class_font_color = diagram.skin_params.get_element_property("class", "FontColor") ?? "black";
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";

            sb.append("digraph classes {\n");
            sb.append("  rankdir=TB;\n");
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            sb.append("  node [shape=record, style=filled, fillcolor=\"%s\", color=\"%s\", fontcolor=\"%s\", fontname=\"%s\", fontsize=%s];\n".printf(
                class_bg, class_border, class_font_color, font_name, font_size
            ));
            sb.append("  edge [fontsize=9, fontname=\"%s\"];\n".printf(font_name));
            sb.append("  splines=ortho;\n");

            // Title
            if (diagram.title != null) {
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  labelloc=t;\n");
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"%s\";\n".printf(font_name));
            }
            sb.append("\n");

            // Create class nodes
            sb.append("  // Classes\n");
            foreach (var c in diagram.classes) {
                string id = c.get_id();
                string label = build_class_label(c);
                if (c.color != null && c.color.length > 0) {
                    sb.append("  %s [label=\"%s\", fillcolor=\"%s\"];\n".printf(id, label, c.color));
                } else {
                    sb.append("  %s [label=\"%s\"];\n".printf(id, label));
                }
            }
            sb.append("\n");

            // Create notes
            if (diagram.notes.size > 0) {
                sb.append("  // Notes\n");
                string note_bg = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? "#FFFFCC";
                string note_border = diagram.skin_params.get_element_property("note", "BorderColor") ?? "#A0A000";

                foreach (var note in diagram.notes) {
                    string note_label = RenderUtils.escape_label(note.text);
                    sb.append("  %s [shape=note, label=\"%s\", fillcolor=\"%s\", color=\"%s\"];\n".printf(
                        note.id, note_label, note_bg, note_border
                    ));

                    // Connect note to class if attached
                    if (note.attached_to != null) {
                        var target_class = diagram.find_class(note.attached_to);
                        if (target_class != null) {
                            string rank = "";
                            if (note.position == "left" || note.position == "right") {
                                rank = "same";
                            }
                            sb.append("  %s -> %s [style=dashed, arrowhead=none, constraint=false];\n".printf(
                                note.id, target_class.get_id()
                            ));
                        }
                    }
                }
                sb.append("\n");
            }

            // Create relationship edges
            sb.append("  // Relationships\n");
            foreach (var rel in diagram.relationships) {
                string from_id = rel.from.get_id();
                string to_id = rel.to.get_id();
                string style = get_relationship_style(rel.relationship_type);
                string arrowhead = get_relationship_arrowhead(rel.relationship_type);
                string arrowtail = get_relationship_arrowtail(rel.relationship_type);
                string label = rel.label != null ? RenderUtils.escape_label(rel.label) : "";

                sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=%s, dir=both".printf(
                    from_id, to_id, style, arrowhead, arrowtail
                ));
                if (label != "") {
                    sb.append(", label=\"%s\"".printf(label));
                }
                sb.append("];\n");
            }

            sb.append("}\n");

            return sb.str;
        }

        private string build_class_label(UmlClass c) {
            var sb = new StringBuilder();

            // Header with stereotype and class name
            sb.append("{");

            // Stereotype - class type or custom
            string stereotype = "";
            if (c.stereotype != null && c.stereotype.length > 0) {
                // Custom stereotype
                stereotype = "\\<\\<%s\\>\\>\\n".printf(RenderUtils.escape_label(c.stereotype));
            } else {
                // Type-based stereotype
                switch (c.class_type) {
                    case ClassType.INTERFACE:
                        stereotype = "\\<\\<interface\\>\\>\\n";
                        break;
                    case ClassType.ABSTRACT:
                        stereotype = "\\<\\<abstract\\>\\>\\n";
                        break;
                    case ClassType.ENUM:
                        stereotype = "\\<\\<enum\\>\\>\\n";
                        break;
                    default:
                        break;
                }
            }

            sb.append(stereotype);
            sb.append(RenderUtils.escape_label(c.name));

            // Members
            if (c.members.size > 0) {
                // Separate fields and methods
                var fields = new Gee.ArrayList<ClassMember>();
                var methods = new Gee.ArrayList<ClassMember>();

                foreach (var m in c.members) {
                    if (m.is_method) {
                        methods.add(m);
                    } else {
                        fields.add(m);
                    }
                }

                // Fields section
                sb.append("|");
                foreach (var f in fields) {
                    sb.append(f.get_visibility_symbol());
                    sb.append(" ");
                    sb.append(RenderUtils.escape_label(f.name));
                    sb.append("\\l");
                }

                // Methods section
                sb.append("|");
                foreach (var m in methods) {
                    sb.append(m.get_visibility_symbol());
                    sb.append(" ");
                    sb.append(RenderUtils.escape_label(m.name));
                    sb.append("\\l");
                }
            }

            sb.append("}");

            return sb.str;
        }

        private string get_relationship_style(RelationshipType type) {
            switch (type) {
                case RelationshipType.IMPLEMENTATION:
                case RelationshipType.DEPENDENCY:
                    return "dashed";
                default:
                    return "solid";
            }
        }

        private string get_relationship_arrowhead(RelationshipType type) {
            switch (type) {
                case RelationshipType.INHERITANCE:
                case RelationshipType.IMPLEMENTATION:
                    return "empty";
                case RelationshipType.DEPENDENCY:
                case RelationshipType.ASSOCIATION:
                    return "open";
                case RelationshipType.AGGREGATION:
                    return "none";
                case RelationshipType.COMPOSITION:
                    return "none";
                default:
                    return "open";
            }
        }

        private string get_relationship_arrowtail(RelationshipType type) {
            switch (type) {
                case RelationshipType.AGGREGATION:
                    return "odiamond";
                case RelationshipType.COMPOSITION:
                    return "diamond";
                default:
                    return "none";
            }
        }

        public uint8[]? render_to_svg(ClassDiagram diagram) {
            string dot = generate_dot(diagram);

            var graph = Gvc.Graph.read_string(dot);
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
            ret = context.render_data(graph, "svg", out svg_data);

            context.free_layout(graph);

            if (ret != 0) {
                warning("Failed to render graph");
                return null;
            }

            return svg_data;
        }

        public Cairo.ImageSurface? render_to_surface(ClassDiagram diagram) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return null;
            }

            // Build element line number map from diagram
            var element_lines = new Gee.HashMap<string, int>();
            foreach (var uml_class in diagram.classes) {
                if (uml_class.source_line > 0) {
                    element_lines.set(uml_class.name, uml_class.source_line);
                }
            }
            foreach (var note in diagram.notes) {
                if (note.source_line > 0) {
                    element_lines.set(note.id, note.source_line);
                    // Also map by first few words of note text for better matching
                    string short_text = note.text.length > 20 ? note.text.substring(0, 20) : note.text;
                    element_lines.set(short_text, note.source_line);
                }
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

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

        public bool export_to_png(ClassDiagram diagram, string filename) {
            var surface = render_to_surface(diagram);
            if (surface == null) {
                return false;
            }

            var status = surface.write_to_png(filename);
            return status == Cairo.Status.SUCCESS;
        }

        public bool export_to_svg(ClassDiagram diagram, string filename) {
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

        public bool export_to_pdf(ClassDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                handle.get_intrinsic_size_in_pixels(out width, out height);

                if (width <= 0) width = 400;
                if (height <= 0) height = 300;

                var surface = new Cairo.PdfSurface(filename, width, height);
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

                surface.finish();

                return surface.status() == Cairo.Status.SUCCESS;
            } catch (Error e) {
                warning("Failed to export PDF: %s", e.message);
                return false;
            }
        }
    }
}
