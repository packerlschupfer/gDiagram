namespace GDiagram {

    /**
     * Right-sidebar property editor for the element clicked in the preview.
     *
     * The source text stays the single source of truth: the panel reads the element
     * through ElementInspector and hands every edit back as complete new source text
     * (`source_edited`), which DocumentView applies as one undoable buffer change. The
     * next successful render calls `refresh()`, which re-reads the element.
     */
    public class PropertiesPanel : Gtk.Box {
        public signal void source_edited(string new_text);
        public signal void go_to_source(string id, int line);

        // The editor buffer. Not a delegate from DocumentView: its closure held the view,
        // which holds this panel, so closed tabs were never freed.
        private Gtk.TextBuffer source_buffer;
        private DiagramType diagram_type = DiagramType.UNKNOWN;
        private Object? ast = null;
        private string? element_name = null;
        private int element_line = 0;
        private ElementInfo? info = null;
        private bool updating = false;

        private Gtk.Stack stack;
        private Adw.PreferencesGroup header_group;
        private Adw.PreferencesGroup edit_group;
        private Adw.EntryRow label_row;
        private Adw.ActionRow alias_row;
        private Adw.EntryRow stereotype_row;
        private Adw.EntryRow color_row;
        private Gtk.ColorDialogButton color_button;
        private Adw.EntryRow id_row;
        private Adw.PreferencesGroup note_group;
        private Gtk.Label note_label;
        private Gtk.Label status_label;

        public PropertiesPanel(Gtk.TextBuffer source_buffer) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.source_buffer = source_buffer;
            vexpand = true;

            stack = new Gtk.Stack();
            stack.vexpand = true;

            var empty = new Adw.StatusPage();
            empty.icon_name = "document-properties-symbolic";
            empty.title = "Properties";
            empty.description = "Click an element in the preview";
            empty.add_css_class("compact");
            stack.add_named(empty, "empty");

            var page = new Adw.PreferencesPage();

            // Header: kind + id, with a jump to the declaration
            header_group = new Adw.PreferencesGroup();
            var go_button = new Gtk.Button.from_icon_name("go-jump-symbolic");
            go_button.tooltip_text = "Go to source";
            go_button.valign = Gtk.Align.CENTER;
            go_button.add_css_class("flat");
            go_button.clicked.connect(() => {
                if (info != null) go_to_source(info.id, info.line);
            });
            header_group.header_suffix = go_button;
            page.add(header_group);

            edit_group = new Adw.PreferencesGroup();
            edit_group.title = "Properties";

            label_row = new Adw.EntryRow();
            label_row.title = "Label";
            label_row.show_apply_button = true;
            label_row.apply.connect(() => {
                if (info != null) apply_edit(ElementInspector.set_label(info, get_source(), label_row.text));
            });
            edit_group.add(label_row);

            alias_row = new Adw.ActionRow();
            alias_row.title = "Alias";
            alias_row.use_markup = false;
            alias_row.subtitle_selectable = true;
            edit_group.add(alias_row);

            stereotype_row = new Adw.EntryRow();
            stereotype_row.title = "Stereotype";
            stereotype_row.show_apply_button = true;
            stereotype_row.apply.connect(() => {
                if (info != null) {
                    apply_edit(ElementInspector.set_stereotype(info, get_source(), stereotype_row.text));
                }
            });
            edit_group.add(stereotype_row);

            color_row = new Adw.EntryRow();
            color_row.title = "Colour";
            color_row.show_apply_button = true;
            color_row.apply.connect(() => {
                if (info != null) apply_edit(ElementInspector.set_color(info, get_source(), color_row.text));
            });
            color_button = new Gtk.ColorDialogButton(new Gtk.ColorDialog());
            color_button.valign = Gtk.Align.CENTER;
            color_button.tooltip_text = "Pick a colour";
            color_button.notify["rgba"].connect(() => {
                if (updating || info == null) return;
                // Read through GObject: the vapi's rgba getter generates a C call with an
                // extra out argument that gtk_color_dialog_button_get_rgba() doesn't take
                var value = Value(typeof(Gdk.RGBA));
                color_button.get_property("rgba", ref value);
                unowned Gdk.RGBA? picked = (Gdk.RGBA?) value.get_boxed();
                if (picked == null) return;
                apply_edit(ElementInspector.set_color(info, get_source(), rgba_to_hex(picked)));
            });
            color_row.add_suffix(color_button);
            edit_group.add(color_row);

            id_row = new Adw.EntryRow();
            id_row.title = "Id (rename)";
            id_row.show_apply_button = true;
            id_row.apply.connect(() => {
                if (info == null) return;
                string new_id = id_row.text.strip();
                string? result = ElementInspector.rename(info, get_source(), new_id);
                if (result != null && result != get_source()) {
                    // Follow the element under its new id
                    element_name = new_id;
                    info.id = new_id;
                }
                apply_edit(result);
            });
            edit_group.add(id_row);
            page.add(edit_group);

            note_group = new Adw.PreferencesGroup();
            note_group.title = "Note";
            note_label = new Gtk.Label("");
            note_label.wrap = true;
            note_label.selectable = true;
            note_label.xalign = 0;
            note_group.add(note_label);
            page.add(note_group);

            var status_group = new Adw.PreferencesGroup();
            status_label = new Gtk.Label("");
            status_label.wrap = true;
            status_label.xalign = 0;
            status_label.visible = false;
            status_group.add(status_label);
            page.add(status_group);

            stack.add_named(page, "element");
            append(stack);
            clear();
        }

        /** Shows the element behind a preview click region. */
        public void show_element(string name, int source_line) {
            element_name = name;
            element_line = source_line;
            update(true);
        }

        /**
         * Called after each successful render: keeps the AST for later clicks and
         * re-reads the shown element, clearing the panel when it no longer exists.
         */
        public void refresh(DiagramType type, Object? new_ast, Gee.List<ElementRegion>? regions) {
            diagram_type = type;
            ast = new_ast;
            if (element_name == null) return;
            // Uncovered types have no AST lookup: the click regions tell whether it still exists
            if (!ElementInspector.is_covered(type) && regions != null && regions.size > 0) {
                bool found = false;
                foreach (var region in regions) {
                    if (region.name == element_name) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    clear();
                    return;
                }
            }
            update(false);
        }

        public void clear() {
            element_name = null;
            element_line = 0;
            info = null;
            stack.visible_child_name = "empty";
        }

        // `new_element`: a click on an element replaces every value. A re-read after a render
        // (300 ms after typing) keeps rows the user is editing.
        private void update(bool new_element) {
            if (element_name == null) return;
            info = ElementInspector.inspect(diagram_type, ast, element_name, element_line, get_source());
            if (info == null) {
                clear();
                return;
            }

            updating = true;
            header_group.title = Markup.escape_text(info.kind);
            header_group.description = Markup.escape_text(
                info.line > 0 ? "%s  ·  line %d".printf(info.id, info.line) : info.id);

            edit_group.visible = info.editable;
            // Only the edits this element's declaration form can carry
            label_row.visible = info.can_label;
            alias_row.visible = info.alias != null || !MermaidElementInspector.covers(info.diagram_type);
            stereotype_row.visible = info.can_stereotype;
            color_row.visible = info.can_color;
            id_row.visible = info.can_rename;
            set_entry(label_row, info.label ?? "", new_element);
            alias_row.subtitle = info.alias ?? "none";
            set_entry(stereotype_row, info.stereotype ?? "", new_element);
            set_entry(color_row, info.color ?? "", new_element);
            // No (readable) colour: a transparent swatch, so the swatch shows "none" rather
            // than GTK's default or the previous element's colour, and any pick differs from
            // it and is applied
            var rgba = Gdk.RGBA();
            if (!parse_color(info.color, ref rgba)) {
                rgba = Gdk.RGBA() { red = 0, green = 0, blue = 0, alpha = 0 };
            }
            color_button.rgba = rgba;
            color_button.tooltip_text = rgba.alpha > 0 ? "Pick a colour" : "No colour set. Pick a colour";
            set_entry(id_row, info.id, new_element);

            note_group.visible = info.note != null;
            note_label.label = info.note ?? "";

            if (!info.editable) {
                show_status("Editing is not available for this diagram type", false);
            } else if (info.read_only_reason != null) {
                // e.g. the declaration lives in an !include'd file
                show_status(info.read_only_reason, false);
            } else {
                status_label.visible = false;
            }
            updating = false;
            stack.visible_child_name = "element";
        }

        private string get_source() {
            return source_buffer.text;
        }

        private void apply_edit(string? new_text) {
            if (new_text == null) {
                show_status("This edit can't be applied to this declaration", true);
                return;
            }
            status_label.visible = false;
            if (new_text == get_source()) return;
            source_edited(new_text);
        }

        private void show_status(string message, bool is_error) {
            status_label.label = message;
            if (is_error) {
                status_label.add_css_class("error");
                status_label.remove_css_class("dim-label");
            } else {
                status_label.add_css_class("dim-label");
                status_label.remove_css_class("error");
            }
            status_label.visible = true;
        }

        // Setting the text of an entry row with the apply button on would reveal the button.
        // Unless `force`, a row that has the focus or holds unapplied typing keeps its text:
        // resetting it wiped what was typed and moved the cursor.
        private static void set_entry(Adw.EntryRow row, string text, bool force) {
            string? loaded = row.get_data<string>("gdiagram-loaded");
            if (row.text == text) {
                row.set_data<string>("gdiagram-loaded", text);
                return;
            }
            if (!force && (has_focus_within(row) || (loaded != null && row.text != loaded))) return;
            row.show_apply_button = false;
            row.text = text;
            row.show_apply_button = true;
            row.set_data<string>("gdiagram-loaded", text);
        }

        private static bool has_focus_within(Gtk.Widget widget) {
            var root = widget.get_root();
            if (root == null) return false;
            var focus = root.get_focus();
            return focus != null && (focus == widget || focus.is_ancestor(widget));
        }

        // "#FF0000", "#red", "#pink;line:red" -> RGBA of the fill colour
        private static bool parse_color(string? color, ref Gdk.RGBA rgba) {
            if (color == null) return false;
            string c = color.has_prefix("#") ? color.substring(1) : color;
            int end = c.index_of_char(';');
            if (end >= 0) c = c.substring(0, end);
            if (c.length == 0) return false;
            return rgba.parse("#" + c) || rgba.parse(c);
        }

        private static string rgba_to_hex(Gdk.RGBA rgba) {
            return "#%02X%02X%02X".printf(
                (uint) (rgba.red * 255.0 + 0.5),
                (uint) (rgba.green * 255.0 + 0.5),
                (uint) (rgba.blue * 255.0 + 0.5));
        }
    }
}
