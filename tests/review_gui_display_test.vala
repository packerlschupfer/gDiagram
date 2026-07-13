/*
 * review_gui_display_test.vala — GUI smoke-test fixes that need real widgets.
 *
 * Runs under xvfb-run (a private X server, never the user's session) with the app's
 * GSettings schema compiled into the build tree; skipped without a display.
 *
 * - The main loop keeps running while a big diagram renders, and the newest edit is
 *   what ends up on screen (DocumentView + render thread).
 * - Closing a document while its render is in flight.
 * - The "Could not determine diagram type" placeholder no longer widens the preview.
 * - Ctrl+H focuses Find (with its text selected), not Replace.
 * - Undoing back to the saved text clears the modified marker.
 * - Button zoom keeps the viewport centre, pointer zoom the pointer position.
 * - Zooming in gets a sharp tile.
 * - A closed tab is freed: its editor, AST and render bitmap do not outlive it.
 * - The preview keeps its viewport across re-renders of the same document, and across
 *   Save As; another file's text does start at the top again.
 * - Wheel zoom keeps the point under the pointer over several notches.
 * - A PlantUML render is cached, so returning to rendered text does not render it again.
 * - One failed sharp-zoom tile does not switch sharp zoom off for the whole bitmap.
 * - The outline stats are readable and carry their full text as a tooltip.
 * - Ctrl+F / Ctrl+H are window accelerators, not editor-only key controllers.
 * - A closed view stops reacting to system theme flips.
 * - Every icon name the UI asks for resolves in the installed theme.
 * - Notes are shown with their line breaks, not a literal \n.
 * - The properties panel re-reads the element after an undo instead of going stale.
 * - A render that produced no bitmap says why and points at SVG/PDF, and a slow one shows
 *   a spinner instead of an empty pane.
 * - The lint/validate/complexity report popover is wide enough to read.
 * - No "gPlantUML" left in the menus.
 * - Each template gallery tile has its diagram type's icon.
 */
using GDiagram;

delegate bool Condition();

bool spin_until(Condition done, int timeout_ms = 30000) {
    int64 end = get_monotonic_time() + timeout_ms * 1000;
    var ctx = MainContext.default();
    while (!done()) {
        if (get_monotonic_time() > end) return false;
        ctx.iteration(false);
        Thread.usleep(500);
    }
    return true;
}

void spin_for(int ms) {
    spin_until(() => false, ms);
}

string big_class_source(int n) {
    var sb = new StringBuilder("@startuml\n");
    for (int i = 0; i < n; i++) {
        sb.append_printf("class C%d {\n  +field%d : int\n  +op%d() : void\n}\n", i, i, i);
        if (i >= 12) sb.append_printf("C%d --> C%d\n", i - 12, i);  // 12 per rank: a bitmap cairo can hold
    }
    sb.append("@enduml\n");
    return sb.str;
}

Gtk.Window make_window(Gtk.Widget child, int w = 1200, int h = 800) {
    var window = new Gtk.Window();
    window.set_default_size(w, h);
    window.child = child;
    window.present();
    spin_for(200);
    return window;
}

DocumentView make_view(string content, out Gtk.Window window) {
    var doc = new Document();
    doc.content = content;
    var view = new DocumentView(doc);
    window = make_window(view);
    return view;
}

// ── Render off the main thread ───────────────────────────────────

class StallMeter : Object {
    public int64 last = 0;
    public int64 max_gap = 0;
    public bool tick() {
        int64 now = get_monotonic_time();
        if (last != 0 && now - last > max_gap) max_gap = now - last;
        last = now;
        return Source.CONTINUE;
    }
}

void test_render_keeps_main_loop_running() {
    Gtk.Window window;
    var view = make_view("@startuml\nA -> B\n@enduml\n", out window);
    assert(spin_until(() => !view.render_pending && view.displayed_source != null));

    // A diagram that takes a while to render
    string big = big_class_source(250);
    int64 t0 = get_monotonic_time();
    view.document.content = big;
    assert(spin_until(() => !view.render_pending && view.displayed_source == big, 60000));
    double render_ms = (get_monotonic_time() - t0) / 1000.0;

    // Now edit again and measure how long the main loop stalls while it renders
    var meter = new StallMeter();
    uint source = Timeout.add(5, meter.tick);
    string big2 = big + "class Extra\n";
    view.document.content = big2;
    // Superseded while rendering: the newest text wins
    spin_for(500);
    string newest = big2 + "class Newest\n";
    view.document.content = newest;
    assert(spin_until(() => !view.render_pending && view.displayed_source == newest, 60000));
    spin_for(300);
    Source.remove(source);

    double stall_ms = meter.max_gap / 1000.0;
    Test.message("render %.0f ms, longest main loop stall %.0f ms", render_ms, stall_ms);
    // Before, the main loop was blocked for the whole render
    assert(render_ms > 300);
    assert(stall_ms < render_ms / 2);
    assert(view.get_preview_surface() != null);
    window.destroy();
}

void test_close_while_rendering() {
    Gtk.Window window;
    var view = make_view("@startuml\nA -> B\n@enduml\n", out window);
    assert(spin_until(() => !view.render_pending));
    view.document.content = big_class_source(250);
    spin_for(400);  // debounce passed, render in flight
    assert(view.render_pending);
    // Closing while the render runs: no crash when it finishes (the view is disposed, or
    // at least no longer shown)
    var weak_view = WeakRef(view);
    window.child = null;
    view = null;
    window.destroy();
    spin_for(3000);
    Test.message("closed view finalized: %s", weak_view.get() == null ? "yes" : "no");

    // The render thread still serves other documents
    Gtk.Window window2;
    var view2 = make_view("@startuml\nclass Afterwards\n@enduml\n", out window2);
    assert(spin_until(() => !view2.render_pending && view2.displayed_source != null));
    assert(view2.get_preview_surface() != null);
    window2.destroy();
}

// ── Placeholder width ────────────────────────────────────────────

void test_placeholder_does_not_widen_preview() {
    var pane = new PreviewPane();
    var window = make_window(pane, 900, 600);
    string message = "Could not determine diagram type.\n\ngDiagram looks for known PlantUML keywords " +
        "(@startuml, class, participant, state, ...) and Mermaid keywords (flowchart, sequenceDiagram, " +
        "classDiagram, ...) but found none of them in this document.\n\nFirst lines of the source:\n  @startuml\n  @enduml";
    pane.set_placeholder_text(message);
    spin_for(100);
    int min, nat, mb, nb;
    pane.measure(Gtk.Orientation.HORIZONTAL, -1, out min, out nat, out mb, out nb);
    Test.message("placeholder minimum width %d", min);
    assert(min < 400);

    // Still narrow once a diagram replaced the message
    pane.set_surface(new Cairo.ImageSurface(Cairo.Format.ARGB32, 300, 200));
    spin_for(100);
    pane.measure(Gtk.Orientation.HORIZONTAL, -1, out min, out nat, out mb, out nb);
    assert(min < 400);
    window.destroy();
}

// ── Ctrl+H ───────────────────────────────────────────────────────

void test_ctrl_h_focuses_find() {
    Gtk.Window window;
    var view = make_view("@startuml\nAlice -> Bob : hello\n@enduml\n", out window);
    view.grab_focus();
    spin_for(100);
    var editor = window.get_focus();
    assert(editor is GtkSource.View);
    // Cursor on "Alice"
    var buffer = ((GtkSource.View) editor).buffer;
    Gtk.TextIter iter;
    buffer.get_iter_at_line_offset(out iter, 1, 2);
    buffer.place_cursor(iter);

    // Ctrl+H is a window accelerator now (win.replace, see test_find_is_a_window_shortcut),
    // not a key controller on the editor, so it is driven through the action's handler here
    view.show_search_replace();
    spin_for(300);

    var focus = window.get_focus();
    var find = view.get_search_entry();
    var replace = view.get_replace_entry();
    assert(focus != null);
    assert(focus == find || focus.is_ancestor(find));
    assert(!(focus == replace || focus.is_ancestor(replace)));
    var editable = (Gtk.Editable) find;
    assert(editable.text == "Alice");
    int start, end;
    assert(editable.get_selection_bounds(out start, out end));
    assert(start == 0 && end == 5);
    window.destroy();
}

// ── Modified marker ──────────────────────────────────────────────

void test_undo_to_saved_clears_modified() {
    string path;
    try {
        string dir = DirUtils.make_tmp("gdiagram-undo-XXXXXX");
        path = Path.build_filename(dir, "doc.puml");
        FileUtils.set_contents(path, "@startuml\nA -> B\n@enduml\n");
    } catch (Error e) {
        error("setup: %s", e.message);
    }
    var doc = new Document();
    bool loaded = false;
    doc.load_from_file.begin(File.new_for_path(path), (obj, res) => {
        try { doc.load_from_file.end(res); } catch (Error e) { error("load: %s", e.message); }
        loaded = true;
    });
    assert(spin_until(() => loaded));
    var view = new DocumentView(doc);
    var window = make_window(view);
    assert(!doc.modified);

    view.replace_source_text("@startuml\nA -> B : edited\n@enduml\n");
    spin_for(50);
    assert(doc.modified);
    view.undo();
    spin_for(50);
    assert(doc.content == "@startuml\nA -> B\n@enduml\n");
    assert(!doc.modified);
    view.redo();
    spin_for(50);
    assert(doc.modified);
    window.destroy();
    FileUtils.remove(path);
    DirUtils.remove(Path.get_dirname(path));
}

// ── Zoom anchor ──────────────────────────────────────────────────

void center_image_point(PreviewPane pane, out double ix, out double iy) {
    var v = pane.current_view();
    PreviewGeometry.image_point(v, v.view_w / 2, v.view_h / 2, out ix, out iy);
}

void test_zoom_anchor() {
    var pane = new PreviewPane();
    var window = make_window(pane, 700, 500);
    pane.set_surface(new Cairo.ImageSurface(Cairo.Format.ARGB32, 2400, 1800));
    spin_for(200);
    var v = pane.current_view();
    assert(v.view_w > 100 && v.view_h > 100);

    // Button / Ctrl+plus zoom, from a diagram that fits to one that does not
    pane.zoom_fit();
    spin_for(200);
    double x0, y0, x1, y1;
    center_image_point(pane, out x0, out y0);
    for (int i = 0; i < 6; i++) {
        pane.zoom_in();
        spin_for(100);
    }
    center_image_point(pane, out x1, out y1);
    Test.message("centre (%.1f, %.1f) -> (%.1f, %.1f)", x0, y0, x1, y1);
    assert(Math.fabs(x0 - x1) < 2 && Math.fabs(y0 - y1) < 2);

    pane.zoom_out();
    spin_for(100);
    center_image_point(pane, out x1, out y1);
    assert(Math.fabs(x0 - x1) < 2 && Math.fabs(y0 - y1) < 2);

    // Pointer zoom (wheel): the point under the pointer stays, also when the scroll
    // range grows with the zoom
    v = pane.current_view();
    double px = v.view_w * 0.8, py = v.view_h * 0.75;
    PreviewGeometry.image_point(v, px, py, out x0, out y0);
    pane.zoom_around(v.zoom * 1.44, px, py);
    spin_for(150);
    PreviewGeometry.image_point(pane.current_view(), px, py, out x1, out y1);
    Test.message("pointer (%.1f, %.1f) -> (%.1f, %.1f)", x0, y0, x1, y1);
    assert(Math.fabs(x0 - x1) < 2 && Math.fabs(y0 - y1) < 2);
    window.destroy();
}

// ── Sharp zoom ───────────────────────────────────────────────────

void test_zoom_gets_sharp_tile() {
    Gtk.Window window;
    var view = make_view("@startuml\nclass Alpha {\n  +name : String\n}\nclass Beta\nAlpha --> Beta\n@enduml\n", out window);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null));
    var pane = view.get_preview_pane();
    spin_for(300);
    assert(!pane.has_sharp_tile());  // 100%: the bitmap is sharp
    pane.set_zoom_level(3.0);
    assert(spin_until(() => pane.has_sharp_tile(), 15000));
    window.destroy();
}

// ── A closed tab is freed ────────────────────────────────────────

// A closed document must be finalized: while it lives it holds its editor buffer, its AST and
// its render bitmap (megabytes for a big diagram), so a session of opening and closing files
// grew without bound.
DocumentView? find_document_view(Gtk.Widget root) {
    if (root is DocumentView) return (DocumentView) root;
    for (var c = root.get_first_child(); c != null; c = c.get_next_sibling()) {
        var found = find_document_view(c);
        if (found != null) return found;
    }
    return null;
}

/*
 * Registration is required (GTK refuses to add a window before ::startup), so tests that
 * need a MainWindow MUST run on a private session bus — tests/meson.build wraps this suite
 * in dbus-run-session. On the developer's own bus it would claim the production app id,
 * routing their `gdiagram FILE` into this process, and crash in gtk_window_set_application
 * whenever the name is already owned (remote instance, NULL impl).
 *
 * One instance for the whole suite: a second GDiagram.Application cannot export the same
 * object path, so it would stay unregistered and its windows would be rejected.
 */
GDiagram.Application? shared_app = null;

GDiagram.Application get_shared_app() {
    if (shared_app == null) {
        shared_app = new GDiagram.Application();
        try {
            shared_app.register();
        } catch (Error e) {
            Test.message("no app registration: %s", e.message);
        }
    }
    return shared_app;
}

void test_closed_view_is_finalized() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var view = find_document_view(win);
    assert(view != null);
    view.document.content = "@startuml\nclass Alpha {\n  +name : String\n}\nclass Beta\nAlpha --> Beta\n@enduml\n";
    view.document.clean_state.mark_saved(view.document.content);
    view.document.modified = false;
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 30000));
    // Use the document the way a user does before closing it: search, properties, a click on
    // an element, the outline, zoom, and an open element context menu. The menu's actions hold
    // the view through their closures, and the menu stays parented to the preview.
    view.show_search();
    spin_for(100);
    view.hide_search();
    view.toggle_properties_visibility();
    view.get_preview_pane().element_clicked("Alpha", 2);
    view.toggle_outline_visibility();
    view.zoom_in();
    view.refresh_git_dirty();
    view.get_preview_pane().element_context_menu("Alpha", 2, 20.0, 20.0);
    spin_for(400);
    assert(((Object) view).ref_count > 1);   // the open menu really holds it

    // The view's own widgets outlive it only if it is still referenced: a weak ref on one of
    // them says whether the view was really finalized (a weak ref on the view itself does not:
    // g_object_run_dispose() clears those while the object is still alive)
    var weak_pane = WeakRef(view.get_preview_pane());

    win.activate_action("close-tab", null);

    // The view must let go of the document's heavy state on close. It must NOT depend on
    // the widget being unparented: libadwaita 1.5 (Ubuntu 24.04, CI) keeps a closed page's
    // child parented to its own AdwBin, where 1.7 unparents promptly — verified in a 24.04
    // container, which is where the earlier unparent-driven versions of this silently did
    // nothing and kept the whole document for the session.
    if (!spin_until(() => view.closed, 5000)) {
        printerr("\nFAILED: the closed view never released (parent: %s)\n",
                 view.parent == null ? "none" : view.parent.get_type().name());
        assert_not_reached();
    }
    if (view.get_preview_surface() != null) {
        printerr("\nFAILED: the render bitmap survived the close\n");
        assert_not_reached();
    }
    // Where the toolkit does unparent (libadwaita 1.7 here), nothing else may hold the view
    if (view.parent == null && !spin_until(() => ((Object) view).ref_count == 1, 8000)) {
        printerr("\nFAILED: the closed, unparented view still has %u references\n",
                 ((Object) view).ref_count);
        assert_not_reached();
    }

    // Destroying the window unparents on every version, so the widgets must go for good
    view = null;
    win.destroy();
    assert(spin_until(() => weak_pane.get() == null, 5000));
}

// ── The preview keeps its viewport across re-renders ─────────────

void test_preview_keeps_scroll_across_renders() {
    Gtk.Window window;
    var view = make_view(big_class_source(60), out window);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 60000));
    var pane = view.get_preview_pane();
    pane.set_zoom_level(2.0);
    spin_for(200);
    pane.scroll_to(180.0, 420.0);
    spin_for(200);
    double h0, v0;
    pane.get_scroll_position(out h0, out v0);
    assert(v0 > 100.0);   // really scrolled

    // An edit that keeps the diagram the same size: the viewport must not jump home
    view.document.content = view.document.content.replace("field0 : int", "field0 : long");
    assert(spin_until(() => !view.render_pending && view.displayed_source == view.document.content, 60000));
    spin_for(300);
    double h1, v1;
    pane.get_scroll_position(out h1, out v1);
    Test.message("scroll %.0f,%.0f -> %.0f,%.0f", h0, v0, h1, v1);
    assert(Math.fabs(h1 - h0) < 4.0 && Math.fabs(v1 - v0) < 4.0);
    assert(pane.get_zoom_level() == 2.0);

    // A different document starts at the top again
    pane.reset_view();
    spin_for(100);
    pane.get_scroll_position(out h1, out v1);
    assert(h1 == 0.0 && v1 == 0.0);
    window.destroy();
}

// ── Wheel zoom keeps the point under the pointer ─────────────────

/*
 * The wheel anchored on last_mouse_* (drawing-area coordinates, updated only when the
 * pointer moves) minus the CURRENT scroll offset. A zoom resizes and re-scrolls the drawing
 * area under a motionless pointer, so the anchor drifted further away with every notch:
 * one notch held the point, three moved it ~95 px.
 */
void test_wheel_zoom_keeps_pointer() {
    var pane = new PreviewPane();
    var window = make_window(pane, 700, 500);
    pane.set_surface(new Cairo.ImageSurface(Cairo.Format.ARGB32, 2400, 1800));
    spin_for(250);

    var v0 = pane.current_view();
    assert(v0.view_w > 100 && v0.view_h > 100);
    // One motion event: the pointer sits here in the viewport and does not move again
    double ax = v0.view_w * 0.75, ay = v0.view_h * 0.7;
    pane.set_pointer_position(ax + v0.scroll_x, ay + v0.scroll_y);
    double px, py;
    pane.get_pointer_anchor(out px, out py);
    assert(Math.fabs(px - ax) < 0.01 && Math.fabs(py - ay) < 0.01);

    double ix0, iy0;
    PreviewGeometry.image_point(v0, ax, ay, out ix0, out iy0);

    for (int i = 0; i < 3; i++) {
        pane.wheel_zoom(1.2);
        spin_for(150);
    }
    var v1 = pane.current_view();
    assert(v1.zoom > v0.zoom * 1.7);
    double ix1, iy1;
    PreviewGeometry.image_point(v1, ax, ay, out ix1, out iy1);
    double drift_x = Math.fabs(ix0 - ix1) * v1.zoom;   // on screen
    double drift_y = Math.fabs(iy0 - iy1) * v1.zoom;
    Test.message("wheel drift after 3 notches: %.1f, %.1f px", drift_x, drift_y);
    assert(drift_x < 3.0 && drift_y < 3.0);

    // And back out again
    for (int i = 0; i < 3; i++) {
        pane.wheel_zoom(1.0 / 1.2);
        spin_for(150);
    }
    var v2 = pane.current_view();
    PreviewGeometry.image_point(v2, ax, ay, out ix1, out iy1);
    assert(Math.fabs(ix0 - ix1) * v2.zoom < 3.0 && Math.fabs(iy0 - iy1) * v2.zoom < 3.0);
    window.destroy();
}

// ── The preview cache works for PlantUML too ─────────────────────

/*
 * apply_preview_render nulls cached_surface, and only the Mermaid branch put it back, so
 * the "already on screen" early return in render_preview could never fire for a PlantUML
 * diagram: undoing back to rendered text rendered it again from scratch.
 */
void test_plantuml_render_is_cached() {
    Gtk.Window window;
    string src = "@startuml\nAlice -> Bob : hello\n@enduml\n";
    var view = make_view(src, out window);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null));
    assert(view.has_cached_render);

    var surface = view.get_preview_surface();
    int before = view.applied_render_count;

    // An edit and an undo inside the debounce window: the render that comes due is for the
    // text already on screen and must be skipped
    view.document.content = "@startuml\nAlice -> Bob : hello there\n@enduml\n";
    view.document.content = src;
    assert(spin_until(() => !view.render_pending, 30000));
    spin_for(600);
    assert(view.applied_render_count == before);
    assert(view.get_preview_surface() == surface);

    // A real edit still renders
    view.document.content = "@startuml\nAlice -> Bob : different\n@enduml\n";
    assert(spin_until(() => view.applied_render_count > before, 30000));
    window.destroy();
}

// ── A failed tile is not "this diagram has no SVG" ───────────────

class TileRequests : Object {
    public int count = 0;
    public int serial = 0;
    public double scale = 0;
    public double x = 0;
    public double y = 0;
    public double w = 0;
    public double h = 0;
    public void on_needed(int serial, double scale, double x, double y, double w, double h) {
        count++;
        this.serial = serial;
        this.scale = scale;
        this.x = x; this.y = y; this.w = w; this.h = h;
    }
}

void test_failed_tile_does_not_disable_sharp_zoom() {
    var pane = new PreviewPane();
    var window = make_window(pane, 700, 500);
    var asked = new TileRequests();
    pane.sharp_tile_needed.connect(asked.on_needed);
    pane.set_surface(new Cairo.ImageSurface(Cairo.Format.ARGB32, 2400, 1800));
    pane.set_zoom_level(3.0);
    assert(spin_until(() => asked.count > 0, 8000));

    // One tile that could not be drawn (over the pixel cap, or a draw error). That says
    // nothing about the rest of the diagram, so the pane must keep asking.
    int after_first = asked.count;
    pane.set_sharp_tile(asked.serial, asked.scale, asked.x, asked.y, asked.w, asked.h, null, false);
    pane.scroll_to(300, 400);
    assert(spin_until(() => asked.count > after_first, 8000));

    // No SVG for this diagram at all: stop asking
    int after_second = asked.count;
    pane.set_sharp_tile(asked.serial, asked.scale, asked.x, asked.y, asked.w, asked.h, null, true);
    pane.scroll_to(700, 900);
    spin_for(1000);
    assert(asked.count == after_second);
    window.destroy();
}

// ── Save As keeps the viewport ───────────────────────────────────

/*
 * Save As sets `file` on the document on screen; that fired notify["file"] and reset the
 * preview to 100% at the top-left, even though the diagram behind the pane had not changed.
 */
void test_save_as_keeps_viewport() {
    Gtk.Window window;
    var view = make_view(big_class_source(60), out window);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 60000));
    var pane = view.get_preview_pane();
    pane.set_zoom_level(2.0);
    spin_for(200);
    pane.scroll_to(150.0, 380.0);
    spin_for(200);
    double h0, v0;
    pane.get_scroll_position(out h0, out v0);
    assert(v0 > 100.0);

    string dir;
    try {
        dir = DirUtils.make_tmp("gdiagram-saveas-XXXXXX");
    } catch (Error e) {
        error("setup: %s", e.message);
    }
    view.document.file = File.new_for_path(Path.build_filename(dir, "named.puml"));
    spin_for(500);
    double h1, v1;
    pane.get_scroll_position(out h1, out v1);
    Test.message("save-as scroll %.0f,%.0f -> %.0f,%.0f", h0, v0, h1, v1);
    assert(Math.fabs(h1 - h0) < 4.0 && Math.fabs(v1 - v0) < 4.0);
    assert(pane.get_zoom_level() == 2.0);

    // Another file's text really is another document: back to the top at 100%
    string other = Path.build_filename(dir, "other.puml");
    try {
        FileUtils.set_contents(other, "@startuml\nAlice -> Bob : hi\n@enduml\n");
    } catch (Error e) {
        error("setup: %s", e.message);
    }
    bool loaded = false;
    view.document.load_from_file.begin(File.new_for_path(other), (obj, res) => {
        try { view.document.load_from_file.end(res); } catch (Error e) { error("load: %s", e.message); }
        loaded = true;
    });
    assert(spin_until(() => loaded, 10000));
    assert(spin_until(() => !view.render_pending, 30000));
    spin_for(300);
    pane.get_scroll_position(out h1, out v1);
    assert(h1 == 0.0 && v1 == 0.0);
    assert(pane.get_zoom_level() == 1.0);

    window.destroy();
    FileUtils.remove(other);
    DirUtils.remove(dir);
}

// ── The outline stats are readable ───────────────────────────────

/*
 * The counts shared one toolbar row with the lint, validate and complexity buttons, the
 * render-time label and the theme toggle inside a sidebar capped at 320 px, so they were
 * ellipsized to "7 no…" — and with no tooltip the text could not be recovered at all.
 */
void test_outline_stats_are_readable() {
    Gtk.Window window;
    var view = make_view("flowchart TD\n  A[Start] --> B[Middle]\n  B --> C[End]\n  C --> D[Done]\n",
        out window);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 30000));
    spin_for(400);

    var label = view.get_outline_stats_label();
    assert(label.visible);
    assert(label.label.length > 0);
    Test.message("stats: '%s' in %d px", label.label, label.get_width());
    // The whole text is always recoverable
    assert(label.tooltip_text == label.label);
    assert(label.ellipsize == Pango.EllipsizeMode.NONE);
    assert(label.wrap);

    // A row of its own: the buttons no longer take the width away from it
    var row = label.get_parent();
    assert(row != null);
    assert(label.get_width() >= row.get_width() - 24);

    // And that row is wide enough to show more than a few characters
    int min, nat, mb, nb;
    label.measure(Gtk.Orientation.HORIZONTAL, -1, out min, out nat, out mb, out nb);
    assert(label.get_width() >= int.min(nat, row.get_width() - 24));
    window.destroy();
}

// ── Ctrl+F / Ctrl+H work wherever the focus is ───────────────────

// A shortcut registered on the window itself, so it fires wherever the focus is inside it.
// (GTK re-homes a GLOBAL-scope controller into the root's shortcut manager once the window
// is rooted, and the scope property reads LOCAL again afterwards — hence no scope check.)
// Ctrl+F / Ctrl+H are application accelerators for the window's actions. A
// Gtk.ShortcutController on the window was tried instead and segfaulted inside GTK's
// shortcut dispatch on the first chord, so this asserts the accel, not a controller.
bool has_app_accel(Gtk.Application app, string accel, string action) {
    foreach (string a in app.get_accels_for_action(action)) {
        uint key;
        Gdk.ModifierType mods;
        uint want_key;
        Gdk.ModifierType want_mods;
        if (!Gtk.accelerator_parse(a, out key, out mods)) continue;
        if (!Gtk.accelerator_parse(accel, out want_key, out want_mods)) continue;
        if (key == want_key && mods == want_mods) return true;
    }
    return false;
}

void test_find_is_a_window_shortcut() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var view = find_document_view(win);
    assert(view != null);
    assert(!view.search_visible);

    // Registered on the application for the window's actions, so the editor no
    // longer has to have the focus
    assert(has_app_accel(get_shared_app(), "<Control>f", "win.find"));
    assert(has_app_accel(get_shared_app(), "<Control>h", "win.replace"));

    // The focus in the preview, not in the editor
    view.get_preview_pane().grab_focus();
    spin_for(100);
    win.activate_action("find", null);
    spin_for(300);
    assert(view.search_visible);

    view.hide_search();
    spin_for(100);
    view.get_preview_pane().grab_focus();
    win.activate_action("replace", null);
    spin_for(300);
    assert(view.search_visible);
    win.destroy();
}

// ── A closed view stops following the theme ──────────────────────

void test_disposed_view_ignores_theme_flip() {
    Gtk.Window window;
    var view = make_view("@startuml\nAlice -> Bob : hi\n@enduml\n", out window);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null));
    assert(view.follows_theme_changes);

    var manager = Adw.StyleManager.get_default();
    var saved = manager.color_scheme;
    // While it is open the view does react
    manager.color_scheme = Adw.ColorScheme.FORCE_DARK;
    spin_for(50);
    assert(view.render_scheduled);
    assert(spin_until(() => !view.render_pending, 30000));

    // The tab was closed: MainWindow takes the view out of the tab view, then disposes it
    window.child = null;
    spin_for(50);
    view.close_document();
    assert(!view.follows_theme_changes);
    assert(!view.render_scheduled);

    manager.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
    spin_for(200);
    // The debounce timer dispose() cancelled must not be armed again
    assert(!view.render_scheduled);
    manager.color_scheme = saved;
    spin_for(100);
    assert(!view.render_scheduled);
    window.destroy();
}

// ── Icons the UI asks for exist ──────────────────────────────────

/*
 * Thirteen icon names in the UI are not in the installed Adwaita theme and drew the
 * broken-image placeholder, the lint button (on every document) and the git-dirty tab
 * indicator among them.
 */
void collect_icon_names(Gtk.Widget root, Gee.ArrayList<string> names) {
    var image = root as Gtk.Image;
    if (image != null && image.storage_type == Gtk.ImageType.ICON_NAME && image.icon_name != null
        && !names.contains(image.icon_name)) {
        names.add(image.icon_name);
    }
    for (var c = root.get_first_child(); c != null; c = c.get_next_sibling()) {
        collect_icon_names(c, names);
    }
}

/*
 * Every icon name the window's widgets ask for has to exist in the installed theme.
 *
 * Names that do not draw the broken-image placeholder — and it was the lint button, shown
 * on every document, and the git-dirty tab indicator among them. This walks the real widget
 * tree instead of a hand-kept list, so a new call site with a made-up name fails here.
 */
void test_ui_icons_resolve() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var view = find_document_view(win);
    assert(view != null);
    // A Mermaid diagram: this is what makes the lint, validate and complexity buttons
    // visible and gives them their state icons
    view.document.content = "flowchart TD\n  A[Start] --> B[Middle]\n  B --> C[End]\n";
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 30000));
    view.toggle_properties_visibility();
    spin_for(400);

    var names = new Gee.ArrayList<string>();
    collect_icon_names(win, names);
    // The outline rows and the palette buttons draw a shared paintable, so their widgets no
    // longer carry the name they were built from — IconCache knows what it was asked for
    foreach (var name in IconCache.requested_names()) {
        if (!names.contains(name)) names.add(name);
    }
    // Tab icons and indicators are GIcons on the page, not widgets
    names.add("text-x-generic");
    names.add("media-record-symbolic");      // modified
    names.add("emblem-important-symbolic");  // git-dirty
    names.add("network-workgroup-symbolic"); // git graph tab
    assert(names.size > 15);   // the walk really reached the toolbars

    /*
     * Icon names that are still missing from the theme, in OutlineController.vala and
     * PaletteCatalog.vala. Listed so the test fails for the call sites already fixed
     * without waiting for those two; the list must shrink to nothing.
     */
    // Every icon we name must resolve: the outline and palette replacements landed too,
    // so there is nothing left to excuse. Keep this empty.
    string[] not_ours = {};

    var theme = Gtk.IconTheme.get_for_display(win.get_display());
    int missing = 0;
    foreach (var name in names) {
        if (theme.has_icon(name)) continue;
        bool excused = false;
        foreach (var other in not_ours) if (other == name) excused = true;
        Test.message("%s icon: %s", excused ? "missing (not ours)" : "MISSING", name);
        if (!excused) missing++;
    }
    assert(missing == 0);

    // And the names that used to be the broken-image placeholder are gone from our widgets
    assert(!names.contains("emblem-ok-symbolic"));
    assert(!names.contains("shield-symbolic"));
    win.destroy();
}

// ── Notes show their line breaks ─────────────────────────────────

void test_note_shows_line_breaks() {
    // A note written with PlantUML's \n reached the panel as backslash-n and was shown
    // literally, while the diagram beside it drew the break
    assert(PropertiesPanel.display_note("line one\\nline two") == "line one\nline two");
    assert(PropertiesPanel.display_note("a\\lb\\rc") == "a\nb\nc");
    assert(PropertiesPanel.display_note("C:\\\\path") == "C:\\path");
    assert(PropertiesPanel.display_note("no escapes here") == "no escapes here");
    assert(PropertiesPanel.display_note("trailing backslash\\") == "trailing backslash\\");
    assert(PropertiesPanel.display_note(null) == "");
    // A real newline is left alone
    assert(PropertiesPanel.display_note("one\ntwo") == "one\ntwo");
}

// ── Open/close cycles must give the memory back ──────────────────

int64 rss_kb() {
    string status;
    try {
        FileUtils.get_contents("/proc/self/status", out status);
    } catch (Error e) {
        return 0;
    }
    foreach (var line in status.split("\n")) {
        if (!line.has_prefix("VmRSS:")) continue;
        return int64.parse(line.substring(6).strip().split(" ")[0]);
    }
    return 0;
}

/*
 * Opens `file` in a tab, uses it the way a session does and closes the tab again.
 *
 * True when the whole document really went away: its editor buffer, its AST, its click
 * regions and its render bitmap are the megabytes, and a weak ref on one of the view's own
 * widgets is what says so (a weak ref on the view itself does not — g_object_run_dispose
 * clears those while the object is still alive). The GWeakRef stays a local: it registers
 * itself by address, so it must not be copied out of the frame it was initialised in.
 */
bool open_close_cycle(MainWindow win, File file) {
    win.open_file(file);
    assert(spin_until(() => win.find_page_for_file(file) != null, 30000));
    var page = win.find_page_for_file(file);
    var view = page.child as DocumentView;
    assert(view != null);
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 60000));

    // Fill the caches a real session fills: properties, a click, search, zoom, git state
    view.toggle_properties_visibility();
    view.get_preview_pane().element_clicked("C1", 2);
    view.show_search();
    view.hide_search();
    view.zoom_in();
    view.refresh_git_dirty();
    // The element context menu too: its actions capture the view in closures and the menu
    // stays parented to the preview, so refcounting alone never frees the document — only
    // MainWindow disposing the detached view does. Without this the check has no teeth.
    view.get_preview_pane().element_context_menu("C1", 2, 20.0, 20.0);
    spin_for(250);

    var weak_pane = WeakRef(view.get_preview_pane());
    view = null;
    page = null;
    // open_file already made it the selected page, which is what close-tab acts on
    win.activate_action("close-tab", null);
    assert(spin_until(() => win.find_page_for_file(file) == null, 10000));
    return spin_until(() => weak_pane.get() == null, 8000);
}

void test_open_close_gives_memory_back() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);

    // Several different documents, so the per-document caches really are filled anew each
    // time rather than answered from the last cycle's
    string dir;
    var files = new Gee.ArrayList<File>();
    try {
        dir = DirUtils.make_tmp("gdiagram-mem-XXXXXX");
        for (int i = 0; i < 4; i++) {
            string path = Path.build_filename(dir, "doc%d.puml".printf(i));
            FileUtils.set_contents(path, big_class_source(30 + i * 7));
            files.add(File.new_for_path(path));
        }
    } catch (Error e) {
        error("setup: %s", e.message);
    }

    // The first documents cost a one-time amount (fonts, Graphviz plugins, style schemes,
    // the icon theme); what must not grow is the per-document part
    for (int i = 0; i < 4; i++) open_close_cycle(win, files[i % files.size]);
    spin_for(500);
    int64 before = rss_kb();

    int CYCLES = 12;
    string? env_cycles = Environment.get_variable("GDIAGRAM_MEM_CYCLES");
    if (env_cycles != null) CYCLES = int.parse(env_cycles);
    int leaked = 0;
    for (int i = 0; i < CYCLES; i++) {
        if (!open_close_cycle(win, files[i % files.size])) leaked++;
        if (Environment.get_variable("GDIAGRAM_MEM_TRACE") != null)
            Test.message("  cycle %d: RSS %lld kB", i, rss_kb());
    }
    spin_for(500);
    int64 after = rss_kb();

    /*
     * RSS is reported, not asserted on: it also moves with allocator arenas and with the
     * font, Graphviz and style caches, none of which is per document, and how much depends
     * on what ran in this process before (alone: ~0.9 MB per cycle; after the rest of this
     * suite: ~6 MB, both with nothing leaked). A bound on it would fail for reasons that
     * have nothing to do with documents. Object lifetime is the check with teeth.
     *
     * Measured with this harness at 24 cycles: before the page_detached fix 320 -> 431 MB,
     * 4.52 MB per cycle with 14 of 24 closed documents still alive; after it 308 -> 330 MB,
     * 0.88 MB per cycle with none.
     */
    double per_cycle_mb = (after - before) / (double) CYCLES / 1024.0;
    Test.message("RSS %lld -> %lld kB over %d open+close cycles: %.2f MB each, %d leaked",
        before, after, CYCLES, per_cycle_mb, leaked);

    // No closed document outlived its tab
    assert(leaked == 0);

    win.destroy();
    foreach (var f in files) FileUtils.remove(f.get_path());
    DirUtils.remove(dir);
}

// ── September 2026 GUI polish round ──────────────────────────────

/*
 * The properties panel follows an undo.
 *
 * Editing a class label through the panel and then undoing put the source and the diagram
 * back, while the panel went on showing the label it had just applied: set_entry() kept any
 * row that held text the user had not applied (and any row with the focus — which an
 * Adw.EntryRow keeps after its own apply button is used), with no regard for whether the
 * value behind the row had changed. The row now yields whenever the source moved on, and
 * still keeps typing in progress while the source has not.
 */
void test_properties_panel_follows_undo() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var view = find_document_view(win);
    assert(view != null);
    view.document.content =
        "@startuml\nclass OuterClass {\n  +x : int\n}\nclass InnerClass {\n  +y : int\n}\n" +
        "OuterClass --> InnerClass\n@enduml\n";
    assert(spin_until(() => !view.render_pending && view.get_preview_surface() != null, 30000));

    var panel = view.get_properties_panel();
    view.toggle_properties_visibility();
    view.get_preview_pane().element_clicked("InnerClass", 5);
    spin_for(200);
    assert(panel.label_row_text == "InnerClass");

    // Type a label and apply it: source, diagram and panel all say "Renamed Kse"
    panel.label_row_text = "Renamed Kse";
    panel.apply_label_row();
    assert(spin_until(() => !view.render_pending && view.displayed_source != null
                            && view.displayed_source.contains("\"Renamed Kse\""), 30000));
    assert(panel.label_row_text == "Renamed Kse");

    // The entry has its own undo stack, so the first Ctrl+Z in the smoke test went into the
    // row and left text there that was never applied. That is the state the undo below meets.
    panel.label_row_text = "Renamed";
    spin_for(100);

    view.undo();
    assert(spin_until(() => !view.render_pending && view.displayed_source != null
                            && !view.displayed_source.contains("Renamed Kse"), 30000));
    // Before the fix this was still "Renamed" while the diagram drew InnerClass
    assert(panel.label_row_text == "InnerClass");

    // The other half of the rule: while the value behind the row is unchanged, a re-render
    // (one runs 300 ms after every keystroke) must not wipe what is being typed
    panel.label_row_text = "half typed";
    view.document.content = view.document.content + "' a comment\n";
    assert(spin_until(() => !view.render_pending && view.displayed_source != null
                            && view.displayed_source.contains("' a comment"), 30000));
    assert(panel.label_row_text == "half typed");

    win.destroy();
}

// A block grid nested `depth` deep. Mermaid sizes every cell like the widest child, so the
// canvas grows per level until no renderer can draw it (see review_regions_test, which checks
// the message the canvas guard puts in its place).
string nested_block_source(int depth) {
    var sb = new StringBuilder("block-beta\ncolumns 1\n");
    string indent = "  ";
    for (int d = depth; d > 0; d--) {
        for (int i = 0; i < 5; i++) sb.append_printf("%sn%d_%d\n", indent, d, i);
        sb.append_printf("%sblock:g%d\n", indent, d);
        indent += "  ";
    }
    for (int i = 0; i < 5; i++) sb.append_printf("%sleaf%d\n", indent, i);
    for (int d = depth; d > 0; d--) {
        indent = indent.substring(2);
        sb.append_printf("%send\n", indent);
    }
    return sb.str;
}

/*
 * A diagram past the bitmap size limit is drawn scaled down and says so; one that really
 * cannot be drawn says why, and what to do instead.
 *
 * 2500 classes lay out past the Cairo image size limit, librsvg refused the surface and the
 * pane showed nothing but "Failed to render class diagram" — while the same file exported
 * from the CLI, which printed the size it had to scale to and pointed at SVG/PDF. Every
 * renderer now sizes its surface (and its click regions) through RenderUtils.svg_page_size(),
 * so the page is scaled to fit and drawn. That leaves a preview which is quietly softer than
 * the diagram, which reads as a bad render — so the zoom bar carries the same note the CLI
 * prints, and the failure message is what is left for a render that produced nothing at all.
 */
void test_render_failure_says_why() {
    string with_note = DocumentView.render_failure_text("Failed to render class diagram",
        "PNG scaled down from 123x337465 to 12x32000 px to fit the Cairo image size limit");
    assert(with_note.contains("Failed to render class diagram"));
    assert(with_note.contains("123x337465"));   // the CLI's own note, verbatim
    // The size the message quotes is the one the renderers scale to, not a number of its own
    assert(with_note.contains("%d".printf((int) RenderUtils.MAX_SURFACE_SIDE)));
    assert(with_note.contains("SVG"));
    assert(with_note.contains("PDF"));

    // A failure with no note did NOT hit the size limit, so the message must not blame it:
    // a user with a 1226x1028 diagram was told the preview cannot exceed 32000 px a side
    // while the real cause (locale-formatted DOT Graphviz refused) was only in the log.
    string without_note = DocumentView.render_failure_text("Failed to render component diagram", null);
    assert(without_note.contains("Failed to render component diagram"));
    assert(!without_note.contains("scaled down"));
    assert(!without_note.contains("%d".printf((int) RenderUtils.MAX_SURFACE_SIDE)));
    assert(!without_note.contains("cannot be larger"));
    assert(without_note.down().contains("log"));

    // The other half: the render did come out, scaled. Same note, same way out.
    string notice = DocumentView.downscale_notice_text(
        "PNG scaled down from 123x337465 to 12x32000 px to fit the Cairo image size limit");
    assert(notice.contains("123x337465"));
    assert(notice.contains("scaled down"));
    assert(notice.contains("%d".printf((int) RenderUtils.MAX_SURFACE_SIDE)));
    assert(notice.contains("SVG"));
    assert(notice.contains("PDF"));

    // End to end: a class chain tall enough to pass the limit (~135 px a class)
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var view = find_document_view(win);
    assert(view != null);
    var sb = new StringBuilder("@startuml\n");
    for (int i = 0; i < 300; i++) {
        sb.append_printf("class T%d {\n  +f%d : int\n  +op%d() : void\n}\n", i, i, i);
        if (i > 0) sb.append_printf("T%d --> T%d\n", i - 1, i);
    }
    sb.append("@enduml\n");
    int before = view.applied_render_count;
    view.document.content = sb.str;
    // Not just "no render pending": the debouncer waits 300 ms before the render even starts
    assert(spin_until(() => view.applied_render_count > before && !view.render_pending, 120000));

    // Drawn, not refused — and inside what the preview bitmap can be
    var surface = view.get_preview_surface();
    assert(surface != null);
    Test.message("scaled to %dx%d px", surface.get_width(), surface.get_height());
    assert(surface.get_height() <= (int) RenderUtils.MAX_SURFACE_SIDE);
    assert(surface.get_width() <= (int) RenderUtils.MAX_SURFACE_SIDE);
    assert(surface.get_height() > 1000);   // the whole chain, not a stub

    // ...and the user is told, instead of being left with a diagram that only looks soft
    string? scaled_says = view.downscale_notice;
    Test.message("zoom bar says: %s", scaled_says);
    assert(scaled_says != null);
    assert(scaled_says.contains("scaled down"));
    assert(scaled_says.contains("SVG or PDF"));

    /*
     * A layout that no size fixes: a block grid nested until its canvas passes what Graphviz
     * can even describe. The renderer replaces the grid with a block saying so (its wording is
     * checked in review_regions_test); what matters here is that the pane shows it rather than
     * the blank the broken canvas used to leave behind.
     */
    before = view.applied_render_count;
    view.document.content = nested_block_source(10);
    assert(spin_until(() => view.applied_render_count > before && !view.render_pending, 120000));
    var refused = view.get_preview_surface();
    assert(refused != null);                 // something is on screen
    Test.message("oversize block drew %dx%d px", refused.get_width(), refused.get_height());
    assert(refused.get_width() > 0 && refused.get_height() > 0);
    assert(refused.get_width() <= (int) RenderUtils.MAX_SURFACE_SIDE);
    assert(refused.get_height() <= (int) RenderUtils.MAX_SURFACE_SIDE);
    // The explaining block is one box, not the thousands of pixels the grid asked for
    assert(refused.get_height() < 2000);
    win.destroy();
}

/*
 * A render in flight shows a spinner rather than an empty pane.
 *
 * A big diagram left the preview blank for over a minute with no sign anything was running.
 */
void test_slow_render_shows_progress() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var view = find_document_view(win);
    assert(view != null);
    var pane = view.get_preview_pane();
    assert(!pane.loading_visible);

    view.document.content = big_class_source(1500);
    // The spinner comes up while the render is still running, not after it finished
    assert(spin_until(() => pane.loading_visible, 20000));
    assert(view.render_pending);
    Test.message("spinner says: %s", pane.loading_text);
    assert(pane.loading_text.contains("Rendering"));

    // ...and goes away when the result lands
    assert(spin_until(() => !view.render_pending, 120000));
    spin_for(200);
    assert(!pane.loading_visible);
    win.destroy();
}

/*
 * The lint / validate / complexity report popover is wide enough to read.
 *
 * It was about 130 px across, one word per line, with the last counter cut off at the window
 * edge: GTK only honours a scrolled window's min-content-width when that direction's
 * scrollbar policy can show a scrollbar, and these are NEVER horizontally, so the popover
 * collapsed to the width of the longest word in the report.
 */
void test_report_popover_is_readable() {
    var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    var button = new Gtk.Button();
    var small_button = new Gtk.Button();
    box.append(button);
    box.append(small_button);
    var window = make_window(box, 900, 600);
    string report = "📋 Linting Report:\n\n💡 0 suggestion(s)\n🎨 0 style improvement(s)\n" +
        "✅ 1 best practice(s)\n⚡ 0 performance tip(s)\n\nDetails:\n\n" +
        "✅ 2 node(s) not connected\n   Fix: Ensure all nodes are part of the workflow\n";
    var popover = DocumentView.build_report_popover(button, report);
    popover.popup();
    spin_for(300);

    var content = popover.child;
    assert(content != null);
    int min_w, nat_w, min_h, nat_h, mb, nb;
    content.measure(Gtk.Orientation.HORIZONTAL, -1, out min_w, out nat_w, out mb, out nb);
    Test.message("report popover width: min %d, natural %d", min_w, nat_w);
    // Before the fix this was the longest word, about 130 px
    assert(min_w >= 300);

    // And it sizes to its content: a one-line report was still forced to 200 px tall
    var small = DocumentView.build_report_popover(small_button, "No lint suggestions");
    small.popup();
    spin_for(200);
    small.child.measure(Gtk.Orientation.VERTICAL, -1, out min_h, out nat_h, out mb, out nb);
    Test.message("one-line report popover height: min %d, natural %d", min_h, nat_h);
    assert(nat_h < 150);

    popover.popdown();
    popover.unparent();
    small.popdown();
    small.unparent();
    window.destroy();
}

// Every label in a menu model, recursively (sections and submenus included)
void collect_menu_labels(GLib.MenuModel model, Gee.ArrayList<string> labels) {
    for (int i = 0; i < model.get_n_items(); i++) {
        string? label = null;
        model.get_item_attribute(i, GLib.Menu.ATTRIBUTE_LABEL, "s", out label);
        if (label != null) labels.add(label);
        var link_iter = model.iterate_item_links(i);
        while (link_iter.next()) {
            collect_menu_labels(link_iter.get_value(), labels);
        }
    }
}

// Every menu hanging off a button in the window (Gtk.MenuButton and Adw.SplitButton)
void collect_window_menu_labels(Gtk.Widget root, Gee.ArrayList<string> labels) {
    var menu_button = root as Gtk.MenuButton;
    if (menu_button != null && menu_button.menu_model != null) {
        collect_menu_labels(menu_button.menu_model, labels);
    }
    var split = root as Adw.SplitButton;
    if (split != null && split.menu_model != null) {
        collect_menu_labels(split.menu_model, labels);
    }
    for (var c = root.get_first_child(); c != null; c = c.get_next_sibling()) {
        collect_window_menu_labels(c, labels);
    }
}

/*
 * No pre-rename branding left in the UI: the main menu still offered "About gPlantUML".
 */
void test_no_stale_app_name_in_menus() {
    var win = new MainWindow(get_shared_app());
    win.present();
    spin_for(400);
    var labels = new Gee.ArrayList<string>();
    collect_window_menu_labels(win, labels);
    assert(labels.size > 10);   // the menus really were walked
    bool has_about = false;
    foreach (var label in labels) {
        assert(!label.contains("gPlantUML"));
        if (label.contains("About")) {
            assert(label.contains("gDiagram"));
            has_about = true;
        }
    }
    assert(has_about);
    win.destroy();
}

/*
 * Every template tile carries the icon of its diagram type.
 *
 * All seven PlantUML tiles were the same generic document, although the element palette
 * beside them already draws the bundled uml-*-symbolic set.
 */
void test_template_gallery_icons() {
    string[] ids = {
        // PlantUML
        "class", "sequence", "activity", "state", "usecase", "component", "cluster",
        // Mermaid (class/sequence/state are shared with the PlantUML ids above)
        "flowchart", "er", "gantt", "pie", "gitgraph", "mindmap", "timeline",
        "quadrant", "xychart", "kanban", "journey",
    };
    // What TemplateGallery.present() does: without it the bundled uml-* icons resolve only
    // once some other widget has added the resource path
    TemplateGallery.register_icons(Gdk.Display.get_default());
    var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
    var seen = new Gee.ArrayList<string>();
    foreach (var id in ids) {
        string icon = TemplateGallery.template_icon_name(id);
        // Not the generic document every tile used to show
        assert(icon != "text-x-generic-symbolic");
        assert(theme.has_icon(icon));
        seen.add(icon);
    }
    // The seven PlantUML tiles are told apart at a glance: no two share an icon
    var puml = new Gee.ArrayList<string>();
    foreach (var id in new string[] {"class", "sequence", "activity", "state", "usecase",
                                     "component", "cluster"}) {
        string icon = TemplateGallery.template_icon_name(id);
        assert(!puml.contains(icon));
        puml.add(icon);
    }
    // An id with no symbol of its own still gets something that draws
    assert(theme.has_icon(TemplateGallery.template_icon_name("no-such-template")));
}

int main(string[] args) {
    Test.init(ref args);
    if (!Gtk.init_check()) {
        Test.message("no display: GUI display tests skipped");
        return 77;
    }
    Adw.init();
    Test.add_func("/gui_display/render_keeps_main_loop_running", test_render_keeps_main_loop_running);
    Test.add_func("/gui_display/close_while_rendering", test_close_while_rendering);
    Test.add_func("/gui_display/placeholder_width", test_placeholder_does_not_widen_preview);
    Test.add_func("/gui_display/ctrl_h_focuses_find", test_ctrl_h_focuses_find);
    Test.add_func("/gui_display/undo_to_saved_clears_modified", test_undo_to_saved_clears_modified);
    Test.add_func("/gui_display/zoom_anchor", test_zoom_anchor);
    Test.add_func("/gui_display/zoom_sharp_tile", test_zoom_gets_sharp_tile);
    Test.add_func("/gui_display/closed_view_is_finalized", test_closed_view_is_finalized);
    Test.add_func("/gui_display/preview_keeps_scroll", test_preview_keeps_scroll_across_renders);
    Test.add_func("/gui_display/wheel_zoom_keeps_pointer", test_wheel_zoom_keeps_pointer);
    Test.add_func("/gui_display/plantuml_render_is_cached", test_plantuml_render_is_cached);
    Test.add_func("/gui_display/failed_tile_keeps_sharp_zoom", test_failed_tile_does_not_disable_sharp_zoom);
    Test.add_func("/gui_display/save_as_keeps_viewport", test_save_as_keeps_viewport);
    Test.add_func("/gui_display/outline_stats_readable", test_outline_stats_are_readable);
    Test.add_func("/gui_display/find_is_window_shortcut", test_find_is_a_window_shortcut);
    Test.add_func("/gui_display/disposed_view_ignores_theme", test_disposed_view_ignores_theme_flip);
    Test.add_func("/gui_display/ui_icons_resolve", test_ui_icons_resolve);
    Test.add_func("/gui_display/note_line_breaks", test_note_shows_line_breaks);
    Test.add_func("/gui_display/open_close_gives_memory_back", test_open_close_gives_memory_back);
    Test.add_func("/gui_display/properties_follow_undo", test_properties_panel_follows_undo);
    Test.add_func("/gui_display/render_failure_says_why", test_render_failure_says_why);
    Test.add_func("/gui_display/slow_render_shows_progress", test_slow_render_shows_progress);
    Test.add_func("/gui_display/report_popover_readable", test_report_popover_is_readable);
    Test.add_func("/gui_display/no_stale_app_name", test_no_stale_app_name_in_menus);
    Test.add_func("/gui_display/template_gallery_icons", test_template_gallery_icons);
    return Test.run();
}
