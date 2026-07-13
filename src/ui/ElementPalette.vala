namespace GDiagram {
    /**
     * Element palette for the left sidebar, modelled on Gaphor's toolbox:
     * collapsible groups of small icon buttons. gDiagram is text-first, so a
     * button does not place a shape — it emits snippet_activated() and
     * DocumentView inserts the entry's snippet at the editor cursor.
     *
     * Groups come from PaletteCatalog. The group(s) for the rendered diagram
     * type are moved to the top and expanded; the rest are collapsed.
     */
    public class ElementPalette : Gtk.Box {
        public signal void snippet_activated(PaletteEntry entry);

        // Type the last activated snippet is written for, so an empty editor gets the
        // right @start line or Mermaid header: the entry's own type, or for General
        // entries the rendered diagram's type.
        public DiagramType insert_type { get; private set; default = DiagramType.UNKNOWN; }

        private Gtk.Box groups_box;
        private Gee.ArrayList<PaletteGroup> groups;
        private Gee.ArrayList<Gtk.Expander> expanders;
        private DiagramType current_type = DiagramType.UNKNOWN;
        private DiagramFormat current_format = DiagramFormat.UNKNOWN;

        private static bool icons_registered = false;

        public ElementPalette() {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        construct {
            register_icons();

            var scroll = new Gtk.ScrolledWindow();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;

            groups_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            groups_box.margin_start = 6;
            groups_box.margin_end = 6;
            groups_box.margin_top = 6;
            groups_box.margin_bottom = 6;
            scroll.child = groups_box;
            append(scroll);

            groups = PaletteCatalog.get_groups();
            expanders = new Gee.ArrayList<Gtk.Expander>();
            foreach (var group in groups) {
                var expander = build_group(group);
                expanders.add(expander);
                groups_box.append(expander);
            }
            set_diagram_type(DiagramType.SEQUENCE, DiagramFormat.PLANTUML);
        }

        // The uml-*-symbolic icons are bundled in the GResource. GtkApplication already
        // searches <resource base path>/icons; registering it here keeps the palette
        // working when the application id and resource prefix differ.
        private static void register_icons() {
            if (icons_registered) return;
            var display = Gdk.Display.get_default();
            if (display == null) return;
            Gtk.IconTheme.get_for_display(display).add_resource_path("/org/gnome/gDiagram/icons");
            icons_registered = true;
        }

        private Gtk.Expander build_group(PaletteGroup group) {
            var title = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var name = new Gtk.Label(group.name);
            name.add_css_class("heading");
            title.append(name);
            var format = new Gtk.Label(group.format == DiagramFormat.MERMAID ? "Mermaid" : "PlantUML");
            format.add_css_class("dim-label");
            format.add_css_class("caption");
            title.append(format);

            var flow = new Gtk.FlowBox();
            flow.selection_mode = Gtk.SelectionMode.NONE;
            flow.homogeneous = true;
            flow.min_children_per_line = 3;
            flow.max_children_per_line = 12;
            flow.column_spacing = 2;
            flow.row_spacing = 2;
            flow.margin_top = 4;
            flow.margin_bottom = 4;
            foreach (var entry in group.entries) {
                flow.append(build_button(entry));
            }
            // Only the buttons take keyboard focus, not their FlowBox cells
            for (int i = 0; i < group.entries.size; i++) {
                flow.get_child_at_index(i).focusable = false;
            }

            var expander = new Gtk.Expander(null);
            expander.label_widget = title;
            expander.child = flow;
            return expander;
        }

        private void on_button_clicked(Gtk.Button button) {
            activate_entry(button.get_data<PaletteEntry>("gdiagram-palette-entry"));
        }

        private Gtk.Button build_button(PaletteEntry entry) {
            var button = new Gtk.Button.from_icon_name(entry.icon_name);
            button.add_css_class("flat");
            button.tooltip_text = entry.label;
            button.update_property(Gtk.AccessibleProperty.LABEL, entry.label, -1);
            // No closure over `entry`: it would hold the palette from its own button
            button.set_data<PaletteEntry>("gdiagram-palette-entry", entry);
            button.clicked.connect(on_button_clicked);
            return button;
        }

        private void activate_entry(PaletteEntry entry) {
            DiagramType type = entry.diagram_type;
            if (type == DiagramType.UNKNOWN) {
                type = current_type;
            }
            // A General entry of the other format: fall back to that format's default
            if (PaletteCatalog.is_mermaid_type(type) != (entry.format == DiagramFormat.MERMAID)) {
                type = entry.format == DiagramFormat.MERMAID ? DiagramType.MERMAID_FLOWCHART : DiagramType.UNKNOWN;
            }
            insert_type = type;
            snippet_activated(entry);
        }

        // Called after each render with the detected type. Reorders and re-expands the
        // groups only when the type changes, so manual expanding survives re-renders.
        public void set_diagram_type(DiagramType type, DiagramFormat format) {
            if (type == current_type && format == current_format) return;
            current_type = type;
            current_format = format;

            int[] ranks = new int[groups.size];
            var order = new Gee.ArrayList<int>();
            for (int i = 0; i < groups.size; i++) {
                ranks[i] = PaletteCatalog.relevance(groups[i], type, format);
                order.add(i);
            }
            // Most relevant first; catalog order breaks ties
            order.sort((a, b) => ranks[a] != ranks[b] ? ranks[a] - ranks[b] : a - b);

            Gtk.Widget? previous = null;
            foreach (int i in order) {
                var expander = expanders[i];
                groups_box.reorder_child_after(expander, previous);
                expander.expanded = ranks[i] <= 2;
                previous = expander;
            }
        }
    }
}
