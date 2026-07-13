namespace GDiagram {
    /**
     * Editor buffer edits used by DocumentView (element palette, properties panel).
     * Display-free, so tests/review_ui_test.vala drives them on a plain GtkSource.Buffer.
     */
    public class SourceEdit : Object {

        // Byte lengths of the common prefix and suffix of two strings, both ending on
        // UTF-8 character boundaries and never overlapping
        public static void common_affixes(string old_text, string new_text, out int prefix, out int suffix) {
            int lo = old_text.length;
            int ln = new_text.length;
            int max = int.min(lo, ln);
            int p = 0;
            while (p < max && old_text[p] == new_text[p]) p++;
            while (p > 0 && (is_continuation(old_text[p]) || is_continuation(new_text[p]))) p--;
            int s = 0;
            while (s < max - p && old_text[lo - 1 - s] == new_text[ln - 1 - s]) s++;
            while (s > 0 && is_continuation(old_text[lo - s])) s--;
            prefix = p;
            suffix = s;
        }

        private static bool is_continuation(char c) {
            return (((uchar) c) & 0xC0) == 0x80;
        }

        /**
         * Replaces the buffer text with `new_text` as ONE undo step. Only the changed middle
         * is deleted and re-inserted, so marks (cursor, scroll position) outside it stay put.
         * Gtk.TextBuffer.set_text() can't be used: it is an irreversible action, which GTK
         * refuses inside a user action with a warning.
         */
        public static void replace_text(Gtk.TextBuffer buffer, string new_text) {
            string old_text = buffer.text;
            if (old_text == new_text) return;
            int prefix, suffix;
            common_affixes(old_text, new_text, out prefix, out suffix);

            Gtk.TextIter start, end;
            buffer.get_iter_at_offset(out start, (int) old_text.char_count(prefix));
            buffer.get_iter_at_offset(out end, (int) old_text.char_count(old_text.length - suffix));

            buffer.begin_user_action();
            if (!start.equal(end)) buffer.delete(ref start, ref end);
            int insert_len = new_text.length - prefix - suffix;
            if (insert_len > 0) buffer.insert(ref start, new_text.substring(prefix, insert_len), insert_len);
            buffer.end_user_action();
        }

        /**
         * Index of the `@end…` line a snippet has to go above when the cursor is on line
         * `cursor_line`: the closest `@end` line at or before the cursor, unless a `@start`
         * line follows it (the cursor is then inside the next diagram). -1 when none.
         */
        public static int closing_line_before(string text, int cursor_line) {
            int closing = -1;
            int index = 0;
            foreach (string line in text.split("\n")) {
                if (index > cursor_line) break;
                string stripped = line.strip();
                if (stripped.has_prefix("@end")) {
                    closing = index;
                } else if (stripped.has_prefix("@start")) {
                    closing = -1;
                }
                index++;
            }
            return closing;
        }

        private static bool is_swimlane_line(string line) {
            string t = line.strip();
            return t.length >= 2 && t.has_prefix("|") && t.has_suffix("|") && !t.contains("\n");
        }

        /**
         * Whether the diagram around `cursor_line` already has a swimlane line. When it
         * doesn't, `insert_line` is the line after its `@start` (0 without one), where a
         * first lane must go.
         */
        public static bool diagram_has_swimlane(string text, int cursor_line, out int insert_line) {
            string[] lines = text.split("\n");
            int start = -1;
            for (int i = 0; i < lines.length && i <= cursor_line; i++) {
                if (lines[i].strip().has_prefix("@start")) start = i;
            }
            insert_line = start + 1;
            for (int i = start + 1; i < lines.length; i++) {
                string t = lines[i].strip();
                if (t.has_prefix("@end")) break;
                if (is_swimlane_line(t) || (t.has_prefix("|") && t.index_of("|", 1) > 0)) return true;
            }
            return false;
        }

        /**
         * Element palette insertion. `text` goes on its own line at the cursor with that
         * line's indentation (an empty editor gets a new document of `wrap_type`), `select`
         * is selected inside it, and the whole edit is one undo step. A cursor on or after a
         * diagram's `@end` line (a just-opened file starts on the empty last line) inserts
         * above that line, inside the diagram.
         */
        public static void insert_snippet(Gtk.TextBuffer buffer, string text, string? select, DiagramType wrap_type) {
            Gtk.TextIter start, end;
            buffer.get_bounds(out start, out end);
            string all = buffer.get_text(start, end, false);
            string block;

            buffer.begin_user_action();
            if (all.strip().length == 0) {
                buffer.delete(ref start, ref end);
                block = PaletteCatalog.wrap_document(text, wrap_type);
            } else {
                buffer.get_iter_at_mark(out start, buffer.get_insert());
                int line = start.get_line();
                int closing = closing_line_before(all, line);
                if (closing >= 0) line = closing;
                // PlantUML only accepts a swimlane after other statements when the diagram
                // opened one before its first statement: the first lane goes right below @start
                int first_lane_line = -1;
                if (is_swimlane_line(text) && !diagram_has_swimlane(all, line, out first_lane_line)) {
                    line = first_lane_line;
                    closing = line;
                }

                Gtk.TextIter line_start, line_end;
                buffer.get_iter_at_line(out line_start, line);
                line_end = line_start;
                if (!line_end.ends_line()) line_end.forward_to_line_end();
                string current = buffer.get_text(line_start, line_end, false);
                string indent = current.substring(0, current.length - current.chug().length);

                var sb = new StringBuilder();
                foreach (string snippet_line in text.split("\n")) {
                    if (sb.len > 0) sb.append_c('\n');
                    if (snippet_line.length > 0) sb.append(indent + snippet_line);
                }
                string stripped = current.strip();
                if (closing >= 0) {
                    // Keep the snippet inside the diagram
                    start = line_start;
                    block = sb.str + "\n";
                } else if (stripped.length == 0) {
                    // A blank line is taken over by the snippet
                    buffer.delete(ref line_start, ref line_end);
                    start = line_start;
                    block = sb.str;
                } else {
                    start = line_end;
                    block = "\n" + sb.str;
                }
            }

            int offset = start.get_offset();
            buffer.insert(ref start, block, -1);
            int index = select != null ? block.index_of(select) : -1;
            if (index >= 0) {
                Gtk.TextIter sel_start, sel_end;
                int sel_offset = offset + block.substring(0, index).char_count();
                buffer.get_iter_at_offset(out sel_start, sel_offset);
                buffer.get_iter_at_offset(out sel_end, sel_offset + select.char_count());
                buffer.select_range(sel_start, sel_end);
            } else {
                buffer.place_cursor(start);
            }
            buffer.end_user_action();
        }
    }
}
