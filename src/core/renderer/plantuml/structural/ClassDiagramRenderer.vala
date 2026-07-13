namespace GDiagram {
    public class ClassDiagramRenderer : Object {
        private unowned Gvc.Context context;
        private Gee.ArrayList<ElementRegion> last_regions;
        private string layout_engine;

        // A class's spot is written as SPOT_GLYPH in the spot colour, then its letter in a 2pt
        // run of SPOT_MARKER_COLOR; round_spots() replaces the pair with a circle and letter
        private const string SPOT_GLYPH = "●";
        private const string SPOT_MARKER_COLOR = "#FEFEFD";
        // A member's visibility icon is written as VISIBILITY_GLYPH in VISIBILITY_MARKER_COLOR
        // followed by the kind (1-4 private / protected / package / public field, 5-8 the
        // same for methods); draw_visibility_icons() replaces it with PlantUML's shape
        private const string VISIBILITY_GLYPH = "■";
        private const string VISIBILITY_MARKER_COLOR = "#FEFE0";

        public ClassDiagramRenderer(Gvc.Context ctx, Gee.ArrayList<ElementRegion> regions, string engine) {
            this.context = ctx;
            this.last_regions = regions;
            this.layout_engine = engine;
        }

        public string generate_dot(ClassDiagram diagram) {
            var sb = new StringBuilder();
            note_images.clear();

            // Get theme values — skin_params (from source file) takes
            // precedence, then the active Palette, then a hardcoded fallback.
            var palette = ThemeManager.get_active_palette();
            string bg_raw = diagram.skin_params.background_color ?? palette.background;
            string bg_color = RenderUtils.fill_color(bg_raw);
            string class_bg_raw = diagram.skin_params.get_element_property("class", "BackgroundColor") ?? palette.node_fill;
            string class_bg = RenderUtils.fill_color(class_bg_raw);
            string class_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("class", "BorderColor") ?? palette.node_border);
            // Class text: class FontColor, then DefaultFontColor, then readable on a class
            // background the file sets (gradients use the average), then the palette's.
            // The palette text alone was light grey on e.g. "classBackgroundColor Wheat".
            string? class_font_set = diagram.skin_params.get_element_property("class", "FontColor") ??
                                     diagram.skin_params.default_font_color;
            string class_font_color;
            if (class_font_set != null) {
                class_font_color = RenderUtils.sanitize_color(class_font_set);
            } else if (diagram.skin_params.get_element_property("class", "BackgroundColor") != null) {
                class_font_color = RenderUtils.contrast_text(class_bg);
            } else {
                class_font_color = RenderUtils.sanitize_color(palette.node_text);
            }
            string font_name = diagram.skin_params.default_font_name ?? "Sans";
            string font_size = diagram.skin_params.default_font_size ?? "10";
            base_font_size = int.parse(font_size);
            if (base_font_size <= 0) {
                base_font_size = 10;
            }

            sb.append("digraph classes {\n");
            diagram.assign_ids();
            skin = diagram.skin_params;
            left_to_right = diagram.left_to_right;
            package_index = new Gee.HashMap<ClassPackage, int>();
            package_notes = new Gee.HashMap<ClassPackage, Gee.ArrayList<ClassNote>>();
            assoc_index = 0;
            wide_flat_labels = false;
            sb.append("  rankdir=%s;\n".printf(left_to_right ? "LR" : "TB"));
            // "skinparam nodesep 60" / "skinparam ranksep 50"
            sb.append(RenderUtils.graph_spacing(diagram.skin_params));
            sb.append("  compound=true;\n");  // lhead/ltail on package links
            sb.append("  bgcolor=\"%s\";\n".printf(bg_color));
            string bg_angle = RenderUtils.gradient_stmt(bg_raw);
            if (bg_angle != "") {
                sb.append("  %s\n".printf(bg_angle));
            }
            // Class boxes are HTML tables (shape=plain): the node fill paints the table's
            // area, the table draws the border in the node colour. Records can't underline
            // static members, italicise abstract ones or draw the spot circle.
            sb.append("  node [shape=plain, style=filled, fillcolor=\"%s\"%s, color=\"%s\", fontcolor=\"%s\", fontname=\"%s\", fontsize=%s];\n".printf(
                class_bg, RenderUtils.gradient_attr(class_bg_raw), class_border, class_font_color, font_name, font_size
            ));
            // "skinparam class { ArrowColor }" / "classArrowColor" colour the class links
            string? class_arrow = diagram.skin_params.get_element_property("class", "ArrowColor");
            string edge_color = class_arrow != null
                ? RenderUtils.sanitize_color(class_arrow) : RenderUtils.edge_line_color(diagram.skin_params, palette);
            string edge_text_color = RenderUtils.edge_label_color(diagram.skin_params, palette);
            sb.append("  edge [fontsize=9, fontname=\"%s\", color=\"%s\", fontcolor=\"%s\"];\n".printf(font_name, edge_color, edge_text_color));
            sb.append("  splines=ortho;\n");

            // Title
            if (diagram.title != null) {
                sb.append("  label=\"%s\";\n".printf(RenderUtils.escape_label(diagram.title)));
                sb.append("  labelloc=t;\n");
                sb.append("  fontsize=14;\n");
                sb.append("  fontname=\"%s\";\n".printf(font_name));
                sb.append("  fontcolor=\"%s\";\n".printf(RenderUtils.title_color(diagram.skin_params, palette)));
            }
            sb.append("\n");

            // Note colours
            string note_bg_raw = diagram.skin_params.get_element_property("note", "BackgroundColor") ?? palette.accent_secondary;
            note_bg = RenderUtils.fill_color(note_bg_raw);
            note_bg_source = note_bg_raw;
            note_border = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "BorderColor") ?? palette.node_border);
            note_font = RenderUtils.sanitize_color(diagram.skin_params.get_element_property("note", "FontColor") ?? RenderUtils.contrast_text(note_bg));

            // Notes beside a class inside a package are drawn in the package's cluster, so
            // they can share the class's rank
            var top_notes = new Gee.ArrayList<ClassNote>();
            foreach (var note in diagram.notes) {
                var target = note.attached_to != null ? diagram.find_class(note.attached_to) : null;
                if (target != null && target.owner_package != null && !target.removed) {
                    var list = package_notes.get(target.owner_package);
                    if (list == null) {
                        list = new Gee.ArrayList<ClassNote>();
                        package_notes.set(target.owner_package, list);
                    }
                    list.add(note);
                } else {
                    top_notes.add(note);
                }
            }
            current_diagram = diagram;

            // Create class nodes. Classes declared in a package are drawn inside a
            // cluster for it; packages used to be dropped.
            sb.append("  // Classes\n");
            foreach (var c in in_layout_order(diagram.classes)) {
                if (c.owner_package == null) {
                    append_class_node(sb, c, "  ");
                }
            }
            if (diagram.packages.size > 0) {
                bg_raw_pkg = diagram.skin_params.get_element_property("package", "BackgroundColor") ?? palette.grid;
                string pkg_bg = RenderUtils.fill_color(bg_raw_pkg);
                string pkg_border = RenderUtils.sanitize_color(
                    diagram.skin_params.get_element_property("package", "BorderColor") ?? class_border);
                string pkg_font = RenderUtils.sanitize_color(
                    diagram.skin_params.get_element_property("package", "FontColor") ?? RenderUtils.contrast_text(pkg_bg));
                int pkg_idx = 0;
                foreach (var pkg in in_layout_order(diagram.packages)) {
                    append_package_cluster(sb, pkg, pkg_bg, pkg_border, pkg_font, font_name, "  ", ref pkg_idx);
                }
            }
            sb.append("\n");

            // Create notes
            var ranked = new Gee.HashSet<UmlClass>();
            if (diagram.notes.size > 0) {
                sb.append("  // Notes\n");
                foreach (var note in top_notes) {
                    append_note(sb, note, "  ", ranked);
                }

                foreach (var note in diagram.notes) {
                    // "note on link": ranked between the link's two classes, so it sits beside
                    // the middle of the link as in PlantUML. Side-by-side links keep their rank.
                    var rel = note.on_link;
                    if (rel != null && rel.from != rel.to && !rel.from.removed && !rel.to.removed &&
                        !rel.horizontal && rel.placement == "") {
                        var upper = rel.text_reversed ? rel.to : rel.from;
                        var lower = rel.text_reversed ? rel.from : rel.to;
                        sb.append("  %s -> %s [style=invis];\n".printf(upper.get_id(), note.id));
                        sb.append("  %s -> %s [style=invis];\n".printf(note.id, lower.get_id()));
                    }
                    // Floating note links ("N1 .. A"), ranked in the order written
                    foreach (var link in note.links) {
                        var target_class = diagram.find_class(link.target);
                        if (target_class == null || target_class.removed) {
                            continue;
                        }
                        string style = target_class.hidden ? "invis" : (link.dashed ? "dashed" : "solid");
                        if (link.note_first) {
                            sb.append("  %s -> %s [style=%s, arrowhead=none];\n".printf(
                                note.id, target_class.get_id(), style));
                        } else {
                            sb.append("  %s -> %s [style=%s, arrowhead=none];\n".printf(
                                target_class.get_id(), note.id, style));
                        }
                    }
                }
                sb.append("\n");
            }

            // Create relationship edges
            sb.append("  // Relationships\n");
            var assoc_ranks = new StringBuilder();
            foreach (var rel in in_layout_order(diagram.relationships)) {
                if (rel.from.removed || rel.to.removed) {
                    continue;
                }
                string from_id = rel.from.get_id();
                string to_id = rel.to.get_id();
                string style = rel.line_style ?? get_relationship_style(rel.relationship_type);
                string arrowhead = get_relationship_arrowhead(rel.relationship_type);
                string arrowtail = rel.relationship_type == RelationshipType.AGGREGATION
                    ? aggregation_marker_shape(rel.end_marker) : get_relationship_arrowtail(rel.relationship_type);
                // Crow's-foot (IE) ends as written ("}o--||"); these links were dropped
                if (rel.ie_tail != null || rel.ie_head != null) {
                    if (rel.ie_tail != null) {
                        arrowtail = rel.ie_tail;
                    } else {
                        arrowtail = "none";
                    }
                    if (rel.ie_head != null) {
                        arrowhead = rel.ie_head;
                    } else {
                        arrowhead = "none";
                    }
                }
                // Padded, so the link's own line doesn't run through the first glyph of
                // every line of the label (RenderUtils.pad_edge_label)
                string label = rel.label != null
                    ? RenderUtils.escape_label(RenderUtils.pad_edge_label(direction_glyphs(rel.label))) : "";
                string? tail_card = rel.from_cardinality;
                string? head_card = rel.to_cardinality;
                // "hide X": its links are drawn invisibly too, so the layout keeps their place
                if (rel.from.hidden || rel.to.hidden) {
                    style = "invis";
                    label = "";
                    tail_card = null;
                    head_card = null;
                }
                // "A <|-- B" keeps A above B, as PlantUML lays it out: the edge runs in
                // the order written with its ends swapped. Running it from B made the
                // subclass rank above its parent.
                if (rel.text_reversed) {
                    string swap_id = from_id;
                    from_id = to_id;
                    to_id = swap_id;
                    string swap_marker = arrowhead;
                    arrowhead = arrowtail;
                    arrowtail = swap_marker;
                    string? swap_card = tail_card;
                    tail_card = head_card;
                    head_card = swap_card;
                }

                // Undirected edges (-- and ..) use dir=none to suppress arrows
                string dir = rel.undirected ? "none" : "both";
                var attrs = new StringBuilder();
                if (label != "") {
                    // Not an xlabel: that is placed after layout by a pass that knows
                    // nothing about packages, and it landed on the package border and under
                    // its title. A plain label gets a rank of its own, so the room is
                    // reserved before anything is drawn. Graphviz's orthogonal router does
                    // not route around a label either way; render_to_svg() moves a label
                    // the line ended up crossing (RenderUtils.clear_edge_label_lines).
                    attrs.append(", label=\"%s\"".printf(label));
                }
                if (rel.line_color != null) {
                    attrs.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(rel.line_color)));
                }
                if (rel.text_color != null) {
                    attrs.append(", fontcolor=\"%s\"".printf(RenderUtils.sanitize_color(rel.text_color)));
                }
                if (rel.thickness > 0) {
                    attrs.append(", penwidth=%d".printf(rel.thickness));
                    // Graphviz grows the arrowhead with the pen; PlantUML keeps it near its size
                    if (rel.thickness > 2 && rel.relationship_type != RelationshipType.AGGREGATION) {
                        attrs.append(", arrowsize=%s".printf(fmt(double.max(0.3, 2.0 / rel.thickness))));
                    }
                }
                if (rel.relationship_type == RelationshipType.AGGREGATION) {
                    append_marker_class(attrs, rel.end_marker);
                }
                // "-up->" / "-left->": the edge must not rank the classes itself; an
                // invisible reverse edge (added below) does the placement
                bool top_level = rel.from.owner_package == null && rel.to.owner_package == null;
                if (rel.from != rel.to && (rel.placement == "up" || (rel.placement == "left" && top_level))) {
                    attrs.append(", constraint=false");
                }
                bool has_cards = (tail_card != null && tail_card.length > 0) || (head_card != null && head_card.length > 0);
                // Side-by-side classes sit close together: the labels at both ends of the
                // short link crossed over ("many" showed by A), so such diagrams get more room
                bool flat = top_level && rel.from != rel.to &&
                            (rel.placement == "right" || (rel.placement == "" && rel.horizontal));
                if (flat && (has_cards || label != "")) {
                    wide_flat_labels = true;
                }
                string card_style = "";
                if (has_cards) {
                    // Further out and to the side, so a short "1" isn't hidden under the
                    // diamond or arrowhead
                    card_style = ", labeldistance=2, labelangle=-40";
                }

                bool with_assoc = rel.association_classes.size > 0 && rel.from != rel.to;
                if (!with_assoc) {
                    sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=%s, dir=%s%s".printf(
                        from_id, to_id, style, arrowhead, arrowtail, dir, attrs.str));
                    // Cardinalities at the two ends ("1", "0..*")
                    if (tail_card != null && tail_card.length > 0) {
                        sb.append(", taillabel=\"%s\"".printf(RenderUtils.escape_label(tail_card)));
                    }
                    if (head_card != null && head_card.length > 0) {
                        sb.append(", headlabel=\"%s\"".printf(RenderUtils.escape_label(head_card)));
                    }
                    sb.append(card_style);
                    // Labels at both ends of a short edge ran into each other at the tail:
                    // one more rank of length gives each end room. A labelled edge that
                    // crosses a package boundary used to need the same, as a workaround for
                    // its xlabel being dropped on the package border; the label now has a
                    // rank of its own and does not.
                    if (has_cards && !rel.horizontal &&
                        rel.placement == "" && rel.from != rel.to) {
                        sb.append(", minlen=2");
                    }
                    sb.append("];\n");
                    continue;
                }

                // "(A, B) .. C": the link runs through a point, and C hangs from the point
                string point = "_assoc%d".printf(assoc_index++);
                string point_style = rel.from.hidden || rel.to.hidden ? ", style=invis" : "";
                sb.append("  %s [label=\"\", shape=point, width=0.05, height=0.05, color=\"%s\"%s];\n".printf(
                    point, rel.line_color != null ? RenderUtils.sanitize_color(rel.line_color) : edge_color, point_style));
                sb.append("  %s -> %s [style=%s, arrowhead=none, arrowtail=%s, dir=%s%s".printf(
                    from_id, point, style, arrowtail, dir, attrs.str));
                if (tail_card != null && tail_card.length > 0) {
                    sb.append(", taillabel=\"%s\"".printf(RenderUtils.escape_label(tail_card)));
                }
                sb.append(card_style + "];\n");
                string second_attrs = attrs.str.replace(", label=\"%s\"".printf(label), "");
                sb.append("  %s -> %s [style=%s, arrowhead=%s, arrowtail=none, dir=%s%s".printf(
                    point, to_id, style, arrowhead, dir, second_attrs));
                if (head_card != null && head_card.length > 0) {
                    sb.append(", headlabel=\"%s\"".printf(RenderUtils.escape_label(head_card)));
                }
                sb.append(card_style + "];\n");
                if (top_level && (rel.placement == "right" || rel.placement == "left" ||
                                  (rel.placement == "" && rel.horizontal))) {
                    assoc_ranks.append("  { rank=same; %s; %s; %s; }\n".printf(from_id, point, to_id));
                }
                for (int i = 0; i < rel.association_classes.size; i++) {
                    var ac = rel.association_classes[i];
                    if (ac.removed) {
                        continue;
                    }
                    bool side = rel.association_side[i];
                    string astyle = ac.hidden ? "invis" : (rel.association_dashed[i] ? "dashed" : "solid");
                    sb.append("  %s -> %s [style=%s, arrowhead=none, dir=none];\n".printf(point, ac.get_id(), astyle));
                    if (side && ac.owner_package == null && top_level) {
                        assoc_ranks.append("  { rank=same; %s; %s; }\n".printf(point, ac.get_id()));
                        ranked.add(ac);
                    }
                }
            }
            sb.append(assoc_ranks.str);

            // Relationships with a package end run between cluster anchors and are
            // clipped at the package border (unless the other end is inside it)
            foreach (var link in diagram.package_links) {
                if ((link.from_class != null && (link.from_class.removed || link.from_class.hidden)) ||
                    (link.to_class != null && (link.to_class.removed || link.to_class.hidden))) {
                    continue;
                }
                if ((link.from_class == null && link.from_package == null) ||
                    (link.to_class == null && link.to_package == null)) {
                    continue;
                }
                string from_id = link.from_package != null
                    ? "_pkg%d_anchor".printf(package_index.get(link.from_package)) : link.from_class.get_id();
                string to_id = link.to_package != null
                    ? "_pkg%d_anchor".printf(package_index.get(link.to_package)) : link.to_class.get_id();
                var attrs = new StringBuilder();
                attrs.append("style=%s, arrowhead=%s, arrowtail=%s, dir=%s".printf(
                    get_relationship_style(link.relationship_type),
                    get_relationship_arrowhead(link.relationship_type),
                    link.relationship_type == RelationshipType.AGGREGATION
                        ? aggregation_marker_shape(link.end_marker) : get_relationship_arrowtail(link.relationship_type),
                    link.undirected ? "none" : "both"));
                if (link.from_package != null && !end_inside(link.to_class, link.to_package, link.from_package)) {
                    attrs.append(", ltail=cluster_pkg%d".printf(package_index.get(link.from_package)));
                }
                if (link.to_package != null && !end_inside(link.from_class, link.from_package, link.to_package)) {
                    attrs.append(", lhead=cluster_pkg%d".printf(package_index.get(link.to_package)));
                }
                if (link.label != null && link.label.length > 0) {
                    attrs.append(", label=\"%s\"".printf(RenderUtils.escape_label(
                        RenderUtils.pad_edge_label(direction_glyphs(link.label)))));
                }
                if (link.relationship_type == RelationshipType.AGGREGATION) {
                    append_marker_class(attrs, link.end_marker);
                }
                sb.append("  %s -> %s [%s];\n".printf(from_id, to_id, attrs.str));
            }

            // "together { ... }": an invisible cluster keeps the group next to each other.
            // Only for classes outside packages, which already have their own cluster, and not
            // for classes in a rank=same set below (Graphviz takes those out of the cluster
            // with a warning; the rank already keeps them together).
            foreach (var rel in diagram.relationships) {
                if (rel.from == rel.to || rel.from.removed || rel.to.removed ||
                    rel.from.owner_package != null || rel.to.owner_package != null) {
                    continue;
                }
                if (rel.placement == "left" || rel.placement == "right" || (rel.placement == "" && rel.horizontal)) {
                    ranked.add(rel.from);
                    ranked.add(rel.to);
                }
            }
            int together_idx = 0;
            foreach (var group in diagram.together_groups) {
                var ids = new StringBuilder();
                int count = 0;
                foreach (var c in group) {
                    if (c.owner_package == null && !c.removed && !ranked.contains(c)) {
                        ids.append(" %s;".printf(c.get_id()));
                        count++;
                    }
                }
                if (count >= 2) {
                    sb.append("  subgraph cluster_together%d { style=invis; label=\"\";%s }\n".printf(
                        together_idx++, ids.str));
                }
            }

            // Single-dash arrows (A *- B) put both classes side by side, as in PlantUML.
            // Only for classes outside packages: a rank constraint across cluster
            // boundaries breaks the cluster layout.
            // Direction words place `to` relative to `from` the same way.
            foreach (var rel in diagram.relationships) {
                if (rel.from == rel.to || rel.from.removed || rel.to.removed) {
                    continue;
                }
                bool top_level = rel.from.owner_package == null && rel.to.owner_package == null;
                string f = rel.from.get_id();
                string t = rel.to.get_id();
                if (rel.placement == "up") {
                    sb.append("  %s -> %s [style=invis];\n".printf(t, f));
                } else if (rel.placement == "left" && top_level) {
                    sb.append("  { rank=same; %s; %s; }\n".printf(f, t));
                    sb.append("  %s -> %s [style=invis];\n".printf(t, f));
                } else if (top_level && (rel.placement == "right" || (rel.placement == "" && rel.horizontal))) {
                    sb.append("  { rank=same; %s; %s; }\n".printf(f, t));
                }
            }

            // Room between side-by-side classes for the multiplicities at both ends.
            // A "skinparam nodesep" in the file is the user's own answer to the same
            // question and already stands in the header — don't override it here.
            if (wide_flat_labels && RenderUtils.skin_spacing(skin, "nodesep") == null) {
                sb.append("  nodesep=0.9;\n");
            }
            sb.append("}\n");

            // "legend ... endlegend": the whole body in a cluster labelled with the legend
            return ComponentDiagramRenderer.add_legend(sb.str, "  // Classes\n", diagram.legend, diagram.skin_params);
        }

        // Graphviz orders the nodes of a rank by input order; a left-to-right layout turns
        // that order into bottom-to-top, so the first class ended up at the bottom of its
        // column. PlantUML stacks them top to bottom as written.
        private Gee.List<G> in_layout_order<G>(Gee.List<G> items) {
            if (!left_to_right) {
                return items;
            }
            var reversed = new Gee.ArrayList<G>();
            for (int i = items.size - 1; i >= 0; i--) {
                reversed.add(items[i]);
            }
            return reversed;
        }

        // "drives >" / "< owns": PlantUML draws the direction marker as a small triangle
        private static string direction_glyphs(string label) {
            string l = label.strip();
            if (l.has_suffix(">") && !l.has_suffix("->") && l.length > 1) {
                return "▶ " + l.substring(0, l.length - 1).strip();
            }
            if (l.has_prefix("<") && !l.has_prefix("<-") && l.length > 1) {
                return "◀ " + l.substring(1).strip();
            }
            return label;
        }

        // A note node and, when it is attached to a class, the dashed line and placement on
        // the requested side ("note left of A" beside A on its left, "top of" above it)
        private void append_note(StringBuilder sb, ClassNote note, string indent, Gee.HashSet<UmlClass> ranked) {
            // "note left of Foo #color": own fill (gradients too), text contrasted to it
            string fill = note.color != null ? RenderUtils.fill_color(note.color) : note_bg;
            string text = note.color != null ? RenderUtils.contrast_text(fill) : note_font;
            sb.append("%s%s [shape=note, label=<%s>, fillcolor=\"%s\"%s, color=\"%s\", fontcolor=\"%s\"];\n".printf(
                indent, note.id, note_label(note_html(note.text, base_font_size)), fill,
                RenderUtils.gradient_attr(note.color ?? note_bg_source), note_border, text
            ));
            if (note.attached_to == null) {
                return;
            }
            var target_class = current_diagram.find_class(note.attached_to);
            if (target_class == null || target_class.removed) {
                return;
            }
            string cid = target_class.get_id();
            string line_style = target_class.hidden ? "invis" : "dashed";
            // Sides in screen terms. A flat edge (both ends in one rank) puts its tail left of
            // its head in a top-to-bottom layout, and above it in a left-to-right one.
            string pos = note.position;
            bool same_rank;
            bool note_first;
            if (!left_to_right) {
                same_rank = pos == "left" || pos == "right";
                note_first = pos == "left" || pos == "top";
            } else {
                same_rank = pos == "top" || pos == "bottom";
                note_first = pos == "left" || pos == "top";
            }
            if (same_rank) {
                sb.append("%s{ rank=same; %s; %s; }\n".printf(indent, cid, note.id));
                if (target_class.owner_package == null) {
                    ranked.add(target_class);
                }
            }
            if (note_first) {
                sb.append("%s%s -> %s [style=%s, arrowhead=none];\n".printf(indent, note.id, cid, line_style));
            } else {
                sb.append("%s%s -> %s [style=%s, arrowhead=none];\n".printf(indent, cid, note.id, line_style));
            }
        }

        // Images met by note_html(): "\x01<index>\x01" in its output, resolved by note_label().
        // An entry starting with "\x02" is a placeholder (remote or missing), else a local file.
        private Gee.ArrayList<string> note_images = new Gee.ArrayList<string>();

        /**
         * A note_html() result as a Graphviz label: the text block on its own, or — when the
         * note holds an "<img:...>" — a table of text runs and image cells, an image only being
         * drawable inside a <TD>. A local file is drawn (and embedded by embed_note_images());
         * a remote one becomes a dashed box with its file name, as in the sequence renderer:
         * the preview re-renders on every keystroke and must never fetch over the network.
         */
        private string note_label(string html) {
            if (!html.contains("\x01")) {
                return html;
            }
            var sb = new StringBuilder("<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"0\"><TR>");
            string[] parts = html.split("\x01");
            for (int k = 0; k < parts.length; k++) {
                if (k % 2 == 1) {
                    int idx = int.parse(parts[k]);
                    if (idx < 0 || idx >= note_images.size) {
                        continue;
                    }
                    sb.append(SequenceDiagramRenderer.image_cell(note_images[idx]));
                } else if (!is_blank_run(parts[k])) {
                    sb.append("<TD BALIGN=\"LEFT\" ALIGN=\"LEFT\">%s</TD>".printf(parts[k]));
                }
            }
            sb.append("</TR></TABLE>");
            return sb.str;
        }

        // A text run with nothing to show: the line break an image at the end of a line leaves
        // behind would otherwise become an empty cell beside it
        private static bool is_blank_run(string run) {
            return run.replace("<BR ALIGN=\"LEFT\"/>", "").replace("<BR/>", "")
                      .replace("&#160;", "").strip().length == 0;
        }

        /**
         * The local note images the SVG links to, embedded as data: URIs — librsvg loads no file
         * an SVG read from memory links to, so the preview and the PNG / PDF exports drew nothing
         * where an "<img:file>" was.
         */
        private uint8[] embed_note_images(uint8[] svg_data) {
            return SequenceDiagramRenderer.embed_image_files(svg_data, note_images);
        }

        /**
         * The file an image tag names: "img:logo.png", "img:https://host/x.jpg{scale=0.5}" or
         * "img src=logo.png". Null when the tag carries no source.
         */
        private static string? image_source(string tag) {
            string src = tag.strip();
            if (src.down().has_prefix("img:")) {
                src = src.substring(4).strip();
            } else {
                try {
                    MatchInfo m;
                    if (!new Regex("src\\s*=\\s*\"?([^\"\\s>]+)").match(src, 0, out m)) {
                        return null;
                    }
                    src = m.fetch(1).strip();
                } catch (RegexError e) {
                    return null;
                }
            }
            // "<img:logo.png{scale=0.5}>"
            int brace = src.index_of_char('{');
            if (brace > 0 && src.has_suffix("}")) {
                src = src.substring(0, brace).strip();
            }
            return src.length > 0 ? src : null;
        }

        // Note text as an HTML label: lines left-aligned as in PlantUML, with the creole and
        // HTML formatting PlantUML understands (<b> <i> <u> <s> <color:X> <size:N>, **bold**,
        // //italic//, __underline__) and "<img:...>" images (note_label() draws them).
        private string note_html(string text, int font_size = 10) {
            var out_sb = new StringBuilder();
            var open = new Gee.ArrayList<string>();  // closing tags of open elements
            string[] lines = text.replace("\\n", "\n").split("\n");
            for (int li = 0; li < lines.length; li++) {
                string line = lines[li];
                int i = 0;
                while (i < line.length) {
                    unichar ch = line.get_char(i);
                    if (ch == '<') {
                        int close = line.index_of(">", i);
                        if (close > i) {
                            string tag = line.substring(i + 1, close - i - 1).strip();
                            string low = tag.down();
                            string? opened = null;
                            string? closing = null;
                            bool known = true;
                            if (low == "b" || low == "i" || low == "u" || low == "s") {
                                opened = "<" + low.up() + ">";
                                closing = "</" + low.up() + ">";
                            } else if (low == "strike" || low == "del") {
                                opened = "<S>";
                                closing = "</S>";
                            } else if (low.has_prefix("color:")) {
                                string col = RenderUtils.sanitize_color(tag.substring(6).strip());
                                opened = "<FONT COLOR=\"%s\">".printf(Markup.escape_text(col));
                                closing = "</FONT>";
                            } else if (low.has_prefix("size:")) {
                                int size = int.parse(tag.substring(5).strip());
                                if (size > 0) {
                                    opened = "<FONT POINT-SIZE=\"%d\">".printf(size * font_size / 12 > 0 ? size * font_size / 12 : size);
                                    closing = "</FONT>";
                                }
                            } else if (low.has_prefix("/")) {
                                string name = low.substring(1).strip();
                                string want;
                                switch (name) {
                                    case "b": want = "</B>"; break;
                                    case "i": want = "</I>"; break;
                                    case "u": want = "</U>"; break;
                                    case "s":
                                    case "strike":
                                    case "del": want = "</S>"; break;
                                    case "color":
                                    case "size": want = "</FONT>"; break;
                                    case "back":
                                    case "font": want = ""; break;
                                    default: want = "?"; break;
                                }
                                if (want == "?") {
                                    known = false;
                                } else if (want != "") {
                                    close_tag(out_sb, open, want);
                                }
                            } else if (low.has_prefix("img:") || low.has_prefix("img ") || low == "img") {
                                // A local file is drawn, a remote one gets a placeholder box;
                                // note_label() turns the marker into the image cell
                                string? src = image_source(tag);
                                if (src != null) {
                                    // The image ends the cell, so it ends the open styles with
                                    // it (PlantUML ends them at the line anyway)
                                    for (int k = open.size - 1; k >= 0; k--) {
                                        out_sb.append(open[k]);
                                    }
                                    open.clear();
                                    out_sb.append("\x01%d\x01".printf(note_images.size));
                                    note_images.add(SequenceDiagramRenderer.local_image_path(src)
                                                    ?? SequenceDiagramRenderer.image_placeholder(src, tag));
                                }
                            } else if (low.has_prefix("back:") || low.has_prefix("font:") ||
                                       low.has_prefix("font ") || low == "font") {
                                // unsupported styling: nothing drawn
                            } else {
                                known = false;
                            }
                            if (known) {
                                if (opened != null) {
                                    out_sb.append(opened);
                                    open.add(closing);
                                }
                                i = close + 1;
                                continue;
                            }
                        }
                    }
                    // Creole pairs toggle a style
                    string rest = line.substring(i);
                    string? toggle = null;
                    if (rest.has_prefix("**")) {
                        toggle = "B";
                    } else if (rest.has_prefix("//") && !(i > 0 && line[i - 1] == ':')) {
                        toggle = "I";
                    } else if (rest.has_prefix("__")) {
                        toggle = "U";
                    }
                    if (toggle != null) {
                        string closing = "</%s>".printf(toggle);
                        if (open.size > 0 && open[open.size - 1] == closing) {
                            out_sb.append(closing);
                            open.remove_at(open.size - 1);
                        } else if (rest.substring(2).index_of(toggle == "B" ? "**" : (toggle == "I" ? "//" : "__")) >= 0) {
                            out_sb.append("<%s>".printf(toggle));
                            open.add(closing);
                        } else {
                            out_sb.append(Markup.escape_text(rest.substring(0, 2)));
                        }
                        i += 2;
                        continue;
                    }
                    int next = i;
                    line.get_next_char(ref next, out ch);
                    out_sb.append(Markup.escape_text(line.substring(i, next - i)));
                    i = next;
                }
                // PlantUML ends every style with its line ("<b>" left open doesn't carry over)
                for (int k = open.size - 1; k >= 0; k--) {
                    out_sb.append(open[k]);
                }
                open.clear();
                out_sb.append("<BR ALIGN=\"LEFT\"/>");
            }
            // Graphviz drops a space at the edge of a styled run ("is <u>also" read "isalso")
            return out_sb.str.replace(" <", "&#160;<").replace("> ", ">&#160;");
        }

        // Closes the open elements down to (and including) `want`; a closing tag with no open
        // element is dropped, so the HTML label always stays balanced
        private static void close_tag(StringBuilder sb, Gee.ArrayList<string> open, string want) {
            int idx = -1;
            for (int k = open.size - 1; k >= 0; k--) {
                if (open[k] == want) {
                    idx = k;
                    break;
                }
            }
            if (idx < 0) {
                return;
            }
            for (int k = open.size - 1; k >= idx; k--) {
                sb.append(open[k]);
                open.remove_at(k);
            }
        }

        // Graphviz arrow shape for an aggregation-style end marker as written
        // ("+--" circle-plus, "#--" square, "x--" cross, "}--" crow's foot,
        // "^--" open triangle). All of them used to be drawn as an open diamond.
        // Graphviz has no circle-plus or cross: "+" and "x" get an odot / obox placeholder,
        // and draw_custom_markers() draws the real marker over it in the SVG.
        private static string aggregation_marker_shape(string? marker) {
            switch (marker) {
                case "+": return "odot";
                case "#": return "obox";
                case "x": return "obox";
                // PlantUML's crow's foot is open lines, not a filled shape
                case "}":
                case "{": return "ocrow";
                case "^": return "onormal";
                default: return "odiamond";
            }
        }

        private bool left_to_right = false;
        private string bg_raw_pkg = "";  // package BackgroundColor as written (gradient angle)
        private SkinParams? skin = null;
        private Gee.HashMap<ClassPackage, int> package_index = new Gee.HashMap<ClassPackage, int>();
        private Gee.HashMap<ClassPackage, Gee.ArrayList<ClassNote>> package_notes =
            new Gee.HashMap<ClassPackage, Gee.ArrayList<ClassNote>>();
        private unowned ClassDiagram? current_diagram = null;
        private int base_font_size = 10;
        private int assoc_index = 0;
        private bool wide_flat_labels = false;
        private string note_bg = "";
        private string note_bg_source = "";
        private string note_border = "";
        private string note_font = "";

        // True when the link end (class or package) is drawn inside `container`
        private bool end_inside(UmlClass? c, ClassPackage? p, ClassPackage container) {
            ClassPackage? cur = p != null ? p : (c != null ? c.owner_package : null);
            while (cur != null) {
                if (cur == container) {
                    return true;
                }
                cur = cur.parent;
            }
            return false;
        }

        private void append_class_node(StringBuilder sb, UmlClass c, string indent) {
            string id = c.get_id();
            if (c.removed) {
                return;
            }
            if (c.hidden) {
                sb.append("%s%s [label=<%s>, style=invis];\n".printf(indent, id, build_class_label(c)));
                return;
            }
            if (c.is_diamond) {
                sb.append("%s%s [label=\"\", shape=diamond, width=0.35, height=0.35, fixedsize=true];\n".printf(indent, id));
                return;
            }
            if (c.class_type == ClassType.CIRCLE) {
                // "circle C": a small circle with the name under it, as in PlantUML
                string cfont = c.text_color != null ? RenderUtils.sanitize_color(c.text_color) : "";
                sb.append("%s%s [label=\"\", shape=circle, width=0.18, height=0.18, fixedsize=true, xlabel=\"%s\"%s%s%s];\n".printf(
                    indent, id, RenderUtils.escape_label(c.display_name ?? c.name),
                    c.color != null ? ", fillcolor=\"%s\"%s".printf(RenderUtils.fill_color(c.color), RenderUtils.gradient_attr(c.color)) : "",
                    c.line_color != null ? ", color=\"%s\"".printf(RenderUtils.sanitize_color(c.line_color)) : "",
                    cfont != "" ? ", fontcolor=\"%s\"".printf(cfont) : ""));
                return;
            }
            string label = build_class_label(c);
            string? stereo = c.get_stereotype_text();
            // <style> ".stereotype" colours ("skinparam class { BackgroundColor<<x>> }")
            string? stereo_fill = skin != null ? skin.get_stereotype_property("class", "BackgroundColor", stereo) : null;
            string? stereo_font = skin != null ? skin.get_stereotype_property("class", "FontColor", stereo) : null;
            string? stereo_border = skin != null ? skin.get_stereotype_property("class", "BorderColor", stereo) : null;
            // "#back:X;line:Y;line.dashed;text:Z" / "##[dashed]Y": border and text colour
            string? text_color = c.text_color != null ? RenderUtils.sanitize_color(c.text_color) : null;
            var border = new StringBuilder();
            if (c.line_color != null) {
                border.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(c.line_color)));
            } else if (stereo_border != null) {
                border.append(", color=\"%s\"".printf(RenderUtils.sanitize_color(stereo_border)));
            }
            if (c.color != null && c.color.length > 0) {
                string safe_color = RenderUtils.fill_color(c.color);
                string font = text_color != null ? text_color : RenderUtils.contrast_text(safe_color);
                sb.append("%s%s [label=<%s>, fillcolor=\"%s\"%s, fontcolor=\"%s\"%s];\n".printf(
                    indent, id, label, safe_color, RenderUtils.gradient_attr(c.color), font, border.str));
            } else if (stereo_fill != null) {
                string fill = RenderUtils.fill_color(stereo_fill);
                string font = stereo_font != null ? RenderUtils.sanitize_color(stereo_font) : RenderUtils.contrast_text(fill);
                if (text_color != null) {
                    font = text_color;
                }
                sb.append("%s%s [label=<%s>, fillcolor=\"%s\"%s, fontcolor=\"%s\"%s];\n".printf(
                    indent, id, label, fill, RenderUtils.gradient_attr(stereo_fill), font, border.str));
            } else if (stereo_font != null || text_color != null) {
                string font = text_color != null ? text_color : RenderUtils.sanitize_color(stereo_font);
                sb.append("%s%s [label=<%s>, fontcolor=\"%s\"%s];\n".printf(indent, id, label, font, border.str));
            } else {
                sb.append("%s%s [label=<%s>%s];\n".printf(indent, id, label, border.str));
            }
        }

        private void append_package_cluster(StringBuilder sb, ClassPackage pkg, string bg, string border,
                                            string font, string font_name, string indent, ref int pkg_idx) {
            string fill = pkg.color != null ? RenderUtils.fill_color(pkg.color) : bg;
            string text = pkg.color != null ? RenderUtils.contrast_text(fill) : font;
            int idx = pkg_idx++;
            package_index.set(pkg, idx);
            string inner = indent + "  ";
            string name = pkg.label ?? pkg.name;
            sb.append("%ssubgraph cluster_pkg%d {\n".printf(indent, idx));
            // The package's look follows its shape stereotype, as in PlantUML: a folder's tab,
            // a frame's cut-corner title, a 3D node's heavier outline, a cloud's or database's
            // rounded outline, a rectangle's centred title. All were the same box.
            string look = pkg.style ?? "";
            string style = "filled";
            switch (look) {
                case "frame":
                    sb.append("%slabel=<<TABLE BORDER=\"1\" SIDES=\"BR\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\" COLOR=\"%s\"><TR><TD><B>%s</B></TD></TR></TABLE>>;\n".printf(
                        inner, border, Markup.escape_text(name)));
                    sb.append("%slabeljust=l;\n".printf(inner));
                    break;
                case "node":
                    sb.append("%slabel=<<B>%s</B>>;\n".printf(inner, Markup.escape_text(name)));
                    sb.append("%slabeljust=l;\n".printf(inner));
                    sb.append("%speripheries=1;\n%spenwidth=2;\n".printf(inner, inner));
                    break;
                case "cloud":
                case "database":
                    sb.append("%slabel=<<B>%s</B>>;\n".printf(inner, Markup.escape_text(name)));
                    sb.append("%slabeljust=c;\n".printf(inner));
                    style = "filled,rounded";
                    break;
                case "rectangle":
                case "rect":
                    sb.append("%slabel=<<B>%s</B>>;\n".printf(inner, Markup.escape_text(name)));
                    sb.append("%slabeljust=c;\n".printf(inner));
                    break;
                case "folder":
                    // the name in a tab at the top left
                    sb.append("%slabel=<<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\" COLOR=\"%s\"><TR><TD><B>%s</B></TD></TR></TABLE>>;\n".printf(
                        inner, border, Markup.escape_text(name)));
                    sb.append("%slabeljust=l;\n".printf(inner));
                    break;
                default:
                    sb.append("%slabel=\"%s\";\n".printf(inner, RenderUtils.escape_label(name)));
                    sb.append("%slabeljust=l;\n".printf(inner));
                    break;
            }
            sb.append(style == "filled" ? "%sstyle=filled;\n".printf(inner) : "%sstyle=\"%s\";\n".printf(inner, style));
            sb.append("%sfillcolor=\"%s\";\n".printf(inner, fill));
            string angle = RenderUtils.gradient_stmt(pkg.color != null ? pkg.color : bg_raw_pkg);
            if (angle != "") {
                sb.append("%s%s\n".printf(inner, angle));
            }
            sb.append("%scolor=\"%s\";\n".printf(inner, border));
            sb.append("%sfontcolor=\"%s\";\n".printf(inner, text));
            sb.append("%sfontname=\"%s\";\n".printf(inner, font_name));
            sb.append("%sfontsize=11;\n".printf(inner));
            foreach (var c in in_layout_order(pkg.classes)) {
                append_class_node(sb, c, inner);
            }
            var notes = package_notes.get(pkg);
            if (notes != null) {
                var unused = new Gee.HashSet<UmlClass>();
                foreach (var note in notes) {
                    append_note(sb, note, inner, unused);
                }
            }
            foreach (var child in in_layout_order(pkg.children)) {
                append_package_cluster(sb, child, bg, border, font, font_name, inner, ref pkg_idx);
            }
            // Anchor for relationships that end at the package itself
            sb.append("%s_pkg%d_anchor [label=\"\", shape=point, width=0, height=0, style=invis];\n".printf(inner, idx));
            if (pkg.classes.size == 0 && pkg.children.size == 0) {
                // Graphviz drops empty clusters; keep the package box visible
                sb.append("%s_pkg%d_empty [label=\"\", shape=point, style=invis, width=0.5];\n".printf(inner, idx));
            }
            sb.append("%s}\n".printf(indent));
        }

        // Spot letter and colour of a class header, as PlantUML draws them; false for none
        private bool class_spot(UmlClass c, out string letter, out string color) {
            letter = "";
            color = "";
            if (c.circle_hidden) {
                return false;
            }
            switch (c.class_type) {
                case ClassType.INTERFACE: letter = "I"; color = "#B4A7E5"; break;
                case ClassType.ABSTRACT: letter = "A"; color = "#A9DCDF"; break;
                case ClassType.ENUM: letter = "E"; color = "#EB937F"; break;
                case ClassType.ANNOTATION: letter = "@"; color = "#E3664A"; break;
                case ClassType.ENTITY: letter = "E"; color = "#ADD1B2"; break;
                case ClassType.STRUCT: letter = "S"; color = "#F1F1F1"; break;
                case ClassType.EXCEPTION: letter = "X"; color = "#D94321"; break;
                case ClassType.PROTOCOL: letter = "P"; color = "#F1F1F1"; break;
                case ClassType.METACLASS: letter = "M"; color = "#CCCCCC"; break;
                case ClassType.STEREOTYPE: letter = "S"; color = "#FF77FF"; break;
                case ClassType.DATACLASS: letter = "D"; color = "#7C5CC4"; break;
                case ClassType.RECORD: letter = "R"; color = "#FF8000"; break;
                default: letter = "C"; color = "#ADD1B2"; break;
            }
            if (c.spot_letter != null) {
                letter = c.spot_letter;
                if (c.spot_color != null) {
                    color = c.spot_color;
                }
                return true;
            }
            // "skinparam stereotypeCBackgroundColor YellowGreen" (and "<<Foo>>" variants)
            if (skin != null) {
                string key = "stereotype%sBackgroundColor".printf(letter);
                string? stereo = c.get_stereotype_text();
                string? set_color = stereo != null ? skin.get_global("%s<<%s>>".printf(key, stereo.down())) : null;
                if (set_color == null) {
                    set_color = skin.get_global(key);
                }
                if (set_color != null) {
                    color = set_color;
                }
            }
            return true;
        }

        // "skinparam classAttributeIconSize 0" turns the visibility icons back into + - # ~
        private bool visibility_icons() {
            if (skin == null) {
                return true;
            }
            string? size = skin.get_global("classAttributeIconSize") ??
                           skin.get_element_property("class", "AttributeIconSize");
            return size == null || double.parse(size.strip()) > 0 || size.strip() == "";
        }

        private string member_line(ClassMember m) {
            string marker = Markup.escape_text(m.get_marker_text());
            // A written visibility is PlantUML's icon: VISIBILITY_GLYPH in a sentinel colour
            // that draw_visibility_icons() replaces with the shape
            if (!m.mandatory && marker.length > 0 && !visibility_icons()) {
                // As written, "-field1": PlantUML puts no space after the character
                marker = Markup.escape_text(m.get_visibility_symbol());
            } else if (!m.mandatory && marker.length > 0) {
                int kind;
                switch (m.visibility) {
                    case MemberVisibility.PRIVATE: kind = 1; break;
                    case MemberVisibility.PROTECTED: kind = 2; break;
                    case MemberVisibility.PACKAGE: kind = 3; break;
                    default: kind = 4; break;
                }
                // Larger than the text: Graphviz makes a line of several runs as high as its
                // largest font, so at the text size the member lines closed up. The extra height
                // lands above the text (Graphviz hangs a line from the top of its largest font),
                // which MEMBER_PAD takes off the compartment again.
                marker = "<FONT POINT-SIZE=\"%d\" COLOR=\"%s%d\">%s</FONT>&#160;".printf(
                    base_font_size + 4, VISIBILITY_MARKER_COLOR, kind + (m.is_method ? 4 : 0), VISIBILITY_GLYPH);
            }
            string text = Markup.escape_text(m.name);
            if (text.length > 0) {
                if (m.is_static) {
                    text = "<U>" + text + "</U>";
                }
                if (m.is_abstract) {
                    text = "<I>" + text + "</I>";
                }
            }
            return marker + text + MEMBER_BREAK;
        }

        private static string compartment(string lines) {
            if (lines.length == 0) {
                return "<HR/><TR><TD CELLPADDING=\"3\"></TD></TR>";
            }
            return "<HR/><TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\" CELLPADDING=\"%d\">%s</TD></TR>".printf(
                MEMBER_PAD, lines);
        }

        /**
         * Padding above the first and below the last member of a compartment, smaller than the
         * class table's own. A member line holds the visibility icon in a font 4pt larger than
         * its text — the only way to keep Graphviz from closing the lines up — and Graphviz
         * hangs a line from the top of its largest font, so that extra height sat above the
         * text as padding: the compartment was 3.5 pt taller than PlantUML's and its first row
         * 2.5 pt further from the separator. Taking 2 pt off both ends puts them back.
         */
        private const int MEMBER_PAD = 2;

        // Ends every member line, left-aligned as PlantUML draws them
        private const string MEMBER_BREAK = "<BR ALIGN=\"LEFT\"/>";

        // The class box as an HTML table: header (spot, stereotype, name), then the field and
        // method compartments, or the written sections when the body has separator lines
        private string build_class_label(UmlClass c) {
            var sb = new StringBuilder();
            string table_style = "";
            int border_width = 1;
            if (c.line_style == "dashed" || c.line_style == "dotted") {
                table_style = " STYLE=\"%s\"".printf(c.line_style);
            } else if (c.line_style == "bold") {
                border_width = 2;
            }
            sb.append("<TABLE BORDER=\"%d\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\"%s>".printf(
                border_width, table_style));

            // Header
            string header_attr = "";
            string? header_bg = skin != null ? skin.get_element_property("class", "HeaderBackgroundColor") : null;
            if (header_bg != null && c.color == null) {
                header_attr = " BGCOLOR=\"%s\"%s".printf(RenderUtils.fill_color(header_bg),
                                                        RenderUtils.gradient_html_attr(header_bg));
            }
            sb.append("<TR><TD%s>".printf(header_attr));
            string? stereo = c.get_stereotype_text();
            if (stereo != null && !c.stereotype_hidden) {
                sb.append("<FONT POINT-SIZE=\"%d\"><I>«%s»</I></FONT><BR/>".printf(
                    int.max(base_font_size - 2, 6), Markup.escape_text(stereo)));
            }
            string label_name = c.display_name ?? c.name;
            if (c.generic != null && c.generic.length > 0) {
                label_name = "%s<%s>".printf(label_name, c.generic);
            }
            string name_html = Markup.escape_text(label_name).replace("\\n", "<BR/>");
            if (c.visibility_marker != null) {
                name_html = Markup.escape_text(c.visibility_marker) + " " + name_html;
            }
            // Abstract classes and interfaces have their name in italics
            if (c.class_type == ClassType.ABSTRACT || c.class_type == ClassType.INTERFACE) {
                name_html = "<I>" + name_html + "</I>";
            }
            // The spot: a coloured glyph before the name, kept in the name's cell so the two
            // stay centred together (a cell of its own drifted apart on wide boxes), followed
            // by the letter in a 2pt marker run (a 1pt "I" measures zero wide and Graphviz
            // warns). round_spots() draws the circle and letter.
            string letter, spot_color;
            if (class_spot(c, out letter, out spot_color)) {
                sb.append("<FONT POINT-SIZE=\"%d\" COLOR=\"%s\">%s</FONT><FONT POINT-SIZE=\"2\" COLOR=\"%s\">%s</FONT>&#160; ".printf(
                    base_font_size + 6, RenderUtils.sanitize_color(spot_color), SPOT_GLYPH, SPOT_MARKER_COLOR,
                    Markup.escape_text(letter)));
            }
            sb.append(name_html);
            sb.append("</TD></TR>");

            bool has_separator = false;
            foreach (var m in c.members) {
                if (m.separator != null) {
                    has_separator = true;
                    break;
                }
            }

            if (has_separator) {
                // With separator lines PlantUML keeps the written order: each separator
                // starts a new compartment, its title centred at the top
                var lines = new StringBuilder();
                bool first = true;
                string? pending_title = null;
                foreach (var m in c.members) {
                    bool leading = first;
                    first = false;
                    if (m.separator != null) {
                        // A body that starts with a separator has no empty compartment above it
                        if (!leading) {
                            sb.append(section(pending_title, lines.str));
                            lines.truncate(0);
                        }
                        if (m.separator == "==") {
                            // A double line
                            sb.append("<HR/><TR><TD CELLPADDING=\"0\" HEIGHT=\"2\"></TD></TR>");
                        }
                        pending_title = m.name.length > 0 ? m.name : null;
                        continue;
                    }
                    if (m.hidden_member || (m.is_method && c.methods_hidden) || (!m.is_method && c.fields_hidden)) {
                        continue;
                    }
                    lines.append(member_line(m));
                }
                sb.append(section(pending_title, lines.str));
            } else {
                var fields = new StringBuilder();
                var methods = new StringBuilder();
                int field_count = 0;
                int method_count = 0;
                foreach (var m in c.members) {
                    if (m.is_method) {
                        method_count++;
                        if (!m.hidden_member) {
                            methods.append(member_line(m));
                        }
                    } else {
                        field_count++;
                        if (!m.hidden_member) {
                            fields.append(member_line(m));
                        }
                    }
                }
                if (!c.fields_hidden && !(c.empty_fields_hidden && fields.len == 0)) {
                    sb.append(compartment(fields.str));
                }
                if (!c.methods_hidden && !(c.empty_methods_hidden && methods.len == 0)) {
                    sb.append(compartment(methods.str));
                }
            }

            sb.append("</TABLE>");
            return sb.str;
        }

        // One compartment of a body with separators: its centred title, then its members
        private static string section(string? title, string lines) {
            if (title == null) {
                return compartment(lines);
            }
            var sb = new StringBuilder();
            sb.append("<HR/><TR><TD>%s</TD></TR>".printf(Markup.escape_text(title)));
            if (lines.length > 0) {
                sb.append("<TR><TD ALIGN=\"LEFT\" BALIGN=\"LEFT\" CELLPADDING=\"%d\">%s</TD></TR>".printf(
                    MEMBER_PAD, lines));
            }
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

            var graph = RenderUtils.read_dot(dot);
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

            // The graph is laid out with splines=ortho, whose router ignores link labels.
            // Kept in a local: the bytes of a temporary string do not outlive the statement.
            string routed = RenderUtils.clear_edge_label_lines(svg_string(svg_data));
            // Text runs of one line meeting at a space share one <text>: "This note is <u>also</u>"
            // read "isalso" (see ComponentDiagramRenderer.join_split_text())
            string drawn = svg_string(draw_visibility_icons(round_spots(embed_note_images(routed.data))));
            return RenderUtils.draw_custom_markers(ComponentDiagramRenderer.join_split_text(drawn).data);
        }

        /**
         * PlantUML's visibility icons over their sentinel glyphs: private a square, protected a
         * diamond, package a triangle, public a circle; outlined for fields, filled for methods,
         * in PlantUML's colours. They were the + - # ~ characters.
         */
        public static uint8[] draw_visibility_icons(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            string sentinel = VISIBILITY_MARKER_COLOR.down();
            if (!svg.contains("fill=\"%s".printf(sentinel))) {
                return svg_data;
            }
            // Line colour / method fill per kind 1-4
            string[] strokes = { "#C82930", "#B38D22", "#1963A0", "#038048" };
            string[] fills = { "#F24D5C", "#FFFF44", "#4177AF", "#84BE84" };
            try {
                var icon_re = new Regex(
                    "<text [^>]*x=\"([-0-9.]+)\" y=\"([-0-9.]+)\"[^>]*font-size=\"([0-9.]+)\" fill=\"" + sentinel +
                    "([1-8])\">" + VISIBILITY_GLYPH + "</text>(\\s*<text [^>]*x=\"([-0-9.]+)\"[^>]*font-size=\"([0-9.]+)\")?", RegexCompileFlags.OPTIMIZE);
                string result = icon_re.replace_eval(svg, -1, 0, 0, (info, res) => {
                    double x = double.parse(info.fetch(1));
                    double y = double.parse(info.fetch(2));
                    double glyph_size = double.parse(info.fetch(3));
                    int kind = int.parse(info.fetch(4));
                    string? next = info.fetch(6);
                    double advance = next != null && next.length > 0 ? double.parse(next) - x : glyph_size * 0.8;
                    if (advance <= 0 || advance > glyph_size * 2) {
                        advance = glyph_size * 0.8;
                    }
                    // Sized to the member's text, not the enlarged glyph
                    string? text_size = info.fetch(7);
                    double size = text_size != null && text_size.length > 0 ? double.parse(text_size) : glyph_size;
                    bool method = kind > 4;
                    int k = (kind - 1) % 4;
                    string stroke = strokes[k];
                    string fill = method ? fills[k] : "none";
                    // An icon about 0.6 em across, centred in the glyph's space on the x-height
                    double r = size * 0.3;
                    double cx = x + double.max(advance * 0.45, r);
                    double cy = y - size * 0.34;
                    string shape;
                    switch (k) {
                        case 0:
                            double h = r * 0.85;
                            shape = "<rect class=\"gdvisibility\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\"".printf(
                                fmt(cx - h), fmt(cy - h), fmt(2 * h), fmt(2 * h));
                            break;
                        case 1:
                            shape = "<polygon class=\"gdvisibility\" points=\"%s,%s %s,%s %s,%s %s,%s\"".printf(
                                fmt(cx), fmt(cy - r), fmt(cx + r), fmt(cy), fmt(cx), fmt(cy + r), fmt(cx - r), fmt(cy));
                            break;
                        case 2:
                            shape = "<polygon class=\"gdvisibility\" points=\"%s,%s %s,%s %s,%s\"".printf(
                                fmt(cx), fmt(cy - r), fmt(cx + r * 1.15), fmt(cy + r * 0.8), fmt(cx - r * 1.15), fmt(cy + r * 0.8));
                            break;
                        default:
                            shape = "<ellipse class=\"gdvisibility\" cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\"".printf(
                                fmt(cx), fmt(cy), fmt(r * 0.85), fmt(r * 0.85));
                            break;
                    }
                    res.append("%s fill=\"%s\" stroke=\"%s\" stroke-width=\"1\"/>".printf(shape, fill, stroke));
                    if (info.fetch(5) != null) {
                        res.append(info.fetch(5));
                    }
                    return false;
                });
                return result.data;
            } catch (RegexError e) {
                return svg_data;
            }
        }

        // Graphviz HTML labels can't draw a circle with a letter in it: the header holds the
        // spot glyph in the spot colour, then the letter in a 2pt SPOT_MARKER_COLOR run. The
        // pair becomes an outlined circle over the glyph's space with the letter centred in it.
        public static uint8[] round_spots(uint8[] svg_data) {
            var text = new StringBuilder.sized(svg_data.length + 1);
            text.append_len((string) svg_data, svg_data.length);
            string svg = text.str;
            if (!svg.contains(SPOT_MARKER_COLOR.down())) {
                return svg_data;
            }
            try {
                var spot_re = new Regex(
                    "<text [^>]*x=\"([-0-9.]+)\" y=\"([-0-9.]+)\" font-family=\"([^\"]*)\"[^>]*font-size=\"([0-9.]+)\" fill=\"([^\"]+)\">" +
                    SPOT_GLYPH + "</text>\\s*<text [^>]*x=\"([-0-9.]+)\"[^>]*fill=\"" + SPOT_MARKER_COLOR.down() +
                    "\">([^<]*)</text>", RegexCompileFlags.OPTIMIZE);
                string result = spot_re.replace_eval(svg, -1, 0, 0, (info, res) => {
                    double x = double.parse(info.fetch(1));
                    double y = double.parse(info.fetch(2));
                    string family = info.fetch(3);
                    double size = double.parse(info.fetch(4));
                    string fill = info.fetch(5);
                    double next_x = double.parse(info.fetch(6));
                    string letter = info.fetch(7);
                    // The glyph's advance, as Graphviz measured it
                    double width = next_x - x;
                    if (width <= 0 || width > size * 2) {
                        width = size * 0.8;
                    }
                    double r = size * 0.4;
                    double cx = x + double.max(width / 2, r);
                    double cy = y - size * 0.36;
                    double letter_size = r * 1.35;
                    res.append("<ellipse fill=\"%s\" stroke=\"#181818\" stroke-width=\"0.8\" cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\"/>\n".printf(
                        fill, fmt(cx), fmt(cy), fmt(r), fmt(r)));
                    res.append("<text xml:space=\"preserve\" text-anchor=\"middle\" x=\"%s\" y=\"%s\" font-family=\"%s\" font-size=\"%s\" fill=\"#000000\">%s</text>".printf(
                        fmt(cx), fmt(cy + letter_size * 0.36), family, fmt(letter_size), letter));
                    return false;
                });
                return result.data;
            } catch (RegexError e) {
                return svg_data;
            }
        }

        private static string svg_string(uint8[] data) {
            var text = new StringBuilder.sized(data.length + 1);
            text.append_len((string) data, data.length);
            return text.str;
        }

        private static string fmt(double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, "%.2f");
        }

        // Marks an edge whose end marker Graphviz can't draw ("+" circle-plus, "x" cross)
        private static void append_marker_class(StringBuilder sb, string? marker) {
            if (marker == "+") {
                // PlantUML's circle-plus is larger than the default odot. Class links draw
                // no other hollow circles, so the plain class marks every circle (incl. "+--+")
                sb.append(", class=\"gdplus\", arrowsize=1.3");
            } else if (marker == "x") {
                sb.append(", class=\"gdcross\"");
            }
        }

        /**
         * Maps each package's Graphviz cluster ("cluster_pkg<N>", assigned by
         * append_package_cluster during generate_dot) to the package name, and records the
         * package's declaration line in `element_lines` so the click lands on `package X {`.
         * A package whose name a class already uses is skipped: parse_svg_regions merges
         * groups sharing a name, which would grow the class's region to the whole cluster.
         */
        private Gee.HashMap<string, string> package_region_names(ClassDiagram diagram,
                                                                 Gee.HashMap<string, int> element_lines) {
            var region_names = new Gee.HashMap<string, string>();
            var class_names = new Gee.HashSet<string>();
            foreach (var uml_class in diagram.classes) {
                class_names.add(uml_class.name);
                class_names.add(uml_class.get_id());
            }
            foreach (var entry in package_index.entries) {
                var pkg = entry.key;
                if (pkg.name == null || pkg.name.length == 0 || class_names.contains(pkg.name)) {
                    continue;
                }
                region_names.set("cluster_pkg%d".printf(entry.value), pkg.name);
                if (pkg.source_line > 0 && !element_lines.has_key(pkg.name)) {
                    element_lines.set(pkg.name, pkg.source_line);
                }
            }
            return region_names;
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
                    element_lines.set(uml_class.get_id(), uml_class.source_line);
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

            // A package is a cluster, and parse_svg_regions only takes a cluster whose title
            // is mapped to a name — without this a click on a package title, or on the empty
            // space inside one, selected nothing. The regions sort smallest first, so a class
            // inside the package still wins over the package itself.
            var region_names = package_region_names(diagram, element_lines);

            try {
                var stream = new MemoryInputStream.from_data(svg_data);
                var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

                double width, height;
                RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

                // Parse SVG regions for click-to-source navigation (with pixel scaling)
                RenderUtils.parse_svg_regions(svg_data, last_regions, element_lines, width, height,
                                              region_names);

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
            // The shared path: scaled down to fit the Cairo image size limit
            return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
        }

        public bool export_to_svg(ClassDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.write_svg_to_file(svg_data, filename);
        }

        public bool export_to_pdf(ClassDiagram diagram, string filename) {
            uint8[]? svg_data = render_to_svg(diagram);
            if (svg_data == null) {
                return false;
            }
            return RenderUtils.export_svg_to_pdf(svg_data, filename);
        }
    }
}
