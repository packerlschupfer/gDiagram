namespace GDiagram {

    /**
     * One shared icon paintable per (display, icon name, size, scale, direction).
     *
     * A widget that names its icon ("icon-name") makes GTK look that name up again for every
     * instance. The two places that build icons in bulk — the outline, which throws away and
     * rebuilds a row per element on every render, and the element palette, which adds a button
     * per snippet — did that hundreds of times per document.
     *
     * GTK answers those from its own icon cache, but every hit also pushes the icon onto a
     * 100-entry LRU ring (gtkicontheme.c, `_icon_cache_add_to_lru_cache`), and that ring is
     * the only thing keeping a cached icon alive once no widget shows it. A few hundred
     * lookups dominated by a handful of names therefore push every other icon off the ring,
     * and the icon that falls off is finalized on whichever thread evicted it — including
     * GTK's own icon-loading thread (`load_icon_thread` -> `icon_ensure_texture__locked` ->
     * `icon_cache_mark_used_if_cached`). `icon_cache_lookup()` on the main thread meanwhile
     * takes a reference to whatever the hash table still holds, so it can reference an icon
     * whose count already reached zero:
     *
     *     GLib-GObject-CRITICAL: object_ref: assertion '!object_already_finalized' failed
     *
     * That race is inside GTK (4.18.6, and still there upstream), but it only opens when the
     * ring is being cycled. Resolving each icon once and handing the same paintable to every
     * widget keeps the app from cycling it: the bulk call sites stop looking icons up at all,
     * and the paintables they do use are held here for the rest of the session, so they can
     * never be the LRU's last reference.
     *
     * Sharing is what GTK does anyway — two widgets with the same icon name already draw the
     * same GtkIconPaintable, recoloured per widget at snapshot time (GtkIconPaintable is a
     * GtkSymbolicPaintable, so the CSS colour still applies). What is lost is GTK's automatic
     * re-lookup when the scale factor or text direction changes; both are part of the key
     * here, and both call sites rebuild their widgets often enough to pick a new one up.
     */
    public class IconCache : Object {

        // What a symbolic icon in a button, a row or a toolbar measures in this app: the
        // GtkIconSize.NORMAL of the current stylesheet
        public const int NORMAL_SIZE = 16;

        // Where the bundled uml-*-symbolic icons live in the GResource
        private const string RESOURCE_PATH = "/org/gnome/gDiagram/icons";

        private static Gee.HashMap<string, Gtk.IconPaintable>? icons = null;
        private static Gee.TreeSet<string>? asked = null;
        private static Gee.ArrayList<Gdk.Display>? watched = null;
        private static Gee.ArrayList<Gdk.Display>? registered = null;

        /**
         * Make the bundled uml-*-symbolic icons resolvable, once per display.
         *
         * gtk_icon_theme_add_resource_path() appends the path and marks the theme changed
         * every time it is called — it is not the no-op the palette and the gallery both
         * assumed. Each of those changes empties GTK's icon cache, so every icon on screen is
         * looked up and rasterized again.
         */
        public static void register_resource_path(Gdk.Display? display) {
            if (display == null) return;
            if (registered == null) registered = new Gee.ArrayList<Gdk.Display>();
            if (registered.contains(display)) return;
            Gtk.IconTheme.get_for_display(display).add_resource_path(RESOURCE_PATH);
            registered.add(display);
        }

        /**
         * The paintable for `icon_name`, resolved once for the display, scale factor and text
         * direction `context` is on. Null only when there is no display at all.
         */
        public static Gdk.Paintable? paintable(Gtk.Widget context, string icon_name,
                                               int size = NORMAL_SIZE) {
            var display = context.get_display();
            if (display == null) return null;
            ensure(display);

            int scale = int.max(1, context.scale_factor);
            var direction = context.get_direction();
            string key = "%s|%s|%d|%d|%d".printf(display.get_name(), icon_name, size,
                                                 scale, (int) direction);
            var found = icons.get(key);
            if (found != null) return found;

            // No PRELOAD: the texture is built on the main thread when the icon is first
            // drawn, which is what keeps GTK's icon-loading thread out of this entirely
            var icon = Gtk.IconTheme.get_for_display(display)
                .lookup_icon(icon_name, null, size, scale, direction, 0);
            icons.set(key, icon);
            asked.add(icon_name);
            return icon;
        }

        /** A Gtk.Image showing `icon_name`, drawn from the shared paintable. */
        public static Gtk.Image image(Gtk.Widget context, string icon_name,
                                      int size = NORMAL_SIZE) {
            var shared = paintable(context, icon_name, size);
            if (shared == null) return new Gtk.Image.from_icon_name(icon_name);
            var image = new Gtk.Image();
            image.set_from_paintable(shared);
            return image;
        }

        /** Point an existing image at another shared icon. */
        public static void set_image(Gtk.Image image, string icon_name,
                                     int size = NORMAL_SIZE) {
            var shared = paintable(image, icon_name, size);
            if (shared == null) {
                image.set_from_icon_name(icon_name);
                return;
            }
            image.set_from_paintable(shared);
        }

        /**
         * Every icon name asked for so far.
         *
         * Widgets drawn from a shared paintable no longer carry the name they were built
         * from, so the smoke test that walks the widget tree for names to check against the
         * installed theme reads them here instead.
         */
        public static Gee.Collection<string> requested_names() {
            if (asked == null) asked = new Gee.TreeSet<string>();
            return asked;
        }

        private static void ensure(Gdk.Display display) {
            if (icons == null) icons = new Gee.HashMap<string, Gtk.IconPaintable>();
            if (asked == null) asked = new Gee.TreeSet<string>();
            if (watched == null) watched = new Gee.ArrayList<Gdk.Display>();
            if (watched.contains(display)) return;
            // A new search path or another icon theme gives different files for the same
            // names; widgets built from the old paintables refresh on their next rebuild
            Gtk.IconTheme.get_for_display(display).changed.connect(on_theme_changed);
            watched.add(display);
        }

        private static void on_theme_changed() {
            if (icons != null) icons.clear();
        }
    }
}
