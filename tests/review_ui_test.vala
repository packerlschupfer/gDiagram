/*
 * review_ui_test.vala — display-free logic behind editor UI fixes.
 *
 * - SourceEdit.replace_text (properties panel edits): one undo step, exact undo/redo,
 *   no set_text inside a user action (the test runs with G_DEBUG=fatal-warnings, so GTK's
 *   "Cannot begin irreversible action while in user action" warning aborts it), marks
 *   outside the changed text stay put, UTF-8 safe diffing.
 * - SourceEdit.insert_snippet (element palette): a cursor on/after @end… inserts inside
 *   the diagram.
 * - OutlineNode.key (outline collapse state): same-label siblings get distinct keys that
 *   are stable across a rebuild.
 *
 * Works on a plain GtkSource.Buffer, which needs no display.
 */
namespace GDiagram.Tests {
    public class ReviewUiTests {

        static GtkSource.Buffer make_buffer(string text) {
            var buffer = new GtkSource.Buffer(null);
            buffer.begin_irreversible_action();
            buffer.text = text;
            buffer.end_irreversible_action();
            return buffer;
        }

        static void place_cursor_at_line(Gtk.TextBuffer buffer, int line) {
            Gtk.TextIter iter;
            buffer.get_iter_at_line(out iter, line);
            buffer.place_cursor(iter);
        }

        // ── SourceEdit.common_affixes ────────────────────────────────

        static void check_affixes(string a, string b) {
            int prefix, suffix;
            SourceEdit.common_affixes(a, b, out prefix, out suffix);
            assert(prefix >= 0 && suffix >= 0);
            assert(prefix + suffix <= a.length && prefix + suffix <= b.length);
            // Both cuts are valid UTF-8 and put back together give the strings again
            string a_mid = a.substring(prefix, a.length - prefix - suffix);
            string b_mid = b.substring(prefix, b.length - prefix - suffix);
            assert(a_mid.validate() && b_mid.validate());
            assert(a.substring(0, prefix) == b.substring(0, prefix));
            assert(a.substring(a.length - suffix) == b.substring(b.length - suffix));
        }

        public static void test_affixes() {
            int prefix, suffix;
            SourceEdit.common_affixes("class A\n", "class A #red\n", out prefix, out suffix);
            assert(prefix == 7 && suffix == 1);
            SourceEdit.common_affixes("aaa", "aa", out prefix, out suffix);
            assert(prefix == 2 && suffix == 0);
            // Ä (C3 84) and Ö (C3 96) share their first byte: the cut must not split it
            SourceEdit.common_affixes("xÄy", "xÖy", out prefix, out suffix);
            assert(prefix == 1 && suffix == 1);
            // … and their suffix bytes can't be shared either (é = C3 A9, ©  = C2 A9)
            SourceEdit.common_affixes("é", "©", out prefix, out suffix);
            assert(prefix == 0 && suffix == 0);

            string[] samples = { "", "a", "ab", "abc", "Ä", "Öx", "xÄ", "ÄÖÜ", "aÄa", "€€", "é©", "\n\n" };
            foreach (string a in samples) {
                foreach (string b in samples) check_affixes(a, b);
            }
        }

        // ── SourceEdit.replace_text ──────────────────────────────────

        static void check_replace(string before, string after) {
            var buffer = make_buffer(before);
            SourceEdit.replace_text(buffer, after);
            assert(buffer.text == after);
            assert(buffer.can_undo);
            buffer.undo();
            assert(buffer.text == before);
            assert(!buffer.can_undo);
            assert(buffer.can_redo);
            buffer.redo();
            assert(buffer.text == after);
        }

        public static void test_replace_one_undo_step() {
            check_replace("@startuml\nclass A\nclass B\n@enduml\n", "@startuml\nclass A #red\nclass B\n@enduml\n");
            check_replace("@startuml\nclass Alpha\n@enduml\n", "@startuml\nclass Beta\n@enduml\n");
            check_replace("a\nb\nc\n", "c\n");
            check_replace("a\n", "x\ny\nz\n");
            check_replace("Ä → Ö\n", "Ä ⇒ Ö\n");
            check_replace("", "@startuml\n@enduml\n");
            check_replace("abc", "");
        }

        public static void test_replace_keeps_marks() {
            string before = "@startuml\nclass A\nclass B\nclass C\n@enduml\n";
            var buffer = make_buffer(before);
            // Cursor at the end of "class C"; the edit is on "class A"
            Gtk.TextIter iter;
            buffer.get_iter_at_line_offset(out iter, 3, 7);
            buffer.place_cursor(iter);
            int cursor_before = iter.get_offset();

            SourceEdit.replace_text(buffer, "@startuml\nclass A <<entity>>\nclass B\nclass C\n@enduml\n");
            buffer.get_iter_at_mark(out iter, buffer.get_insert());
            assert(iter.get_line() == 3);
            assert(iter.get_line_offset() == 7);
            assert(iter.get_offset() == cursor_before + " <<entity>>".length);

            // Unchanged text: no undo step at all
            var same = make_buffer(before);
            SourceEdit.replace_text(same, before);
            assert(!same.can_undo);
        }

        // ── SourceEdit.insert_snippet ────────────────────────────────

        public static void test_closing_line_before() {
            string text = "@startuml\nclass A\n@enduml\n\n@startuml\nclass B\n@enduml\n";
            assert(SourceEdit.closing_line_before(text, 0) == -1);
            assert(SourceEdit.closing_line_before(text, 1) == -1);
            assert(SourceEdit.closing_line_before(text, 2) == 2);
            assert(SourceEdit.closing_line_before(text, 3) == 2);
            assert(SourceEdit.closing_line_before(text, 4) == -1);
            assert(SourceEdit.closing_line_before(text, 5) == -1);
            assert(SourceEdit.closing_line_before(text, 6) == 6);
            assert(SourceEdit.closing_line_before(text, 7) == 6);
            assert(SourceEdit.closing_line_before("flowchart TD\n  A --> B\n", 2) == -1);
        }

        static string insert_at(string text, int cursor_line, string snippet, string? select = null) {
            var buffer = make_buffer(text);
            place_cursor_at_line(buffer, cursor_line);
            SourceEdit.insert_snippet(buffer, snippet, select, DiagramType.CLASS);
            string result = buffer.text;
            // One undo step restores the original
            buffer.undo();
            assert(buffer.text == text);
            assert(!buffer.can_undo);
            return result;
        }

        // PlantUML rejects a first swimlane after other statements: it goes below @start,
        // later lanes go at the cursor
        public static void test_insert_swimlane() {
            string doc = "@startuml\nstart\n:a;\n@enduml\n";
            assert(insert_at(doc, 2, "|Swimlane|", "Swimlane") == "@startuml\n|Swimlane|\nstart\n:a;\n@enduml\n");
            string laned = "@startuml\n|A|\nstart\n:a;\n@enduml\n";
            assert(insert_at(laned, 3, "|Swimlane|", "Swimlane") == "@startuml\n|A|\nstart\n:a;\n|Swimlane|\n@enduml\n");
        }

        public static void test_insert_snippet() {
            string doc = "@startuml\nclass A\n@enduml\n";
            // Just opened: the cursor is on the empty last line, after @enduml
            assert(insert_at(doc, 3, "class B") == "@startuml\nclass A\nclass B\n@enduml\n");
            // On the @enduml line
            assert(insert_at(doc, 2, "class B") == "@startuml\nclass A\nclass B\n@enduml\n");
            // Inside the diagram: after the current line
            assert(insert_at(doc, 1, "class B") == "@startuml\nclass A\nclass B\n@enduml\n");
            assert(insert_at(doc, 0, "class B") == "@startuml\nclass B\nclass A\n@enduml\n");
            // Blank line inside the diagram is taken over
            assert(insert_at("@startuml\n\n@enduml\n", 1, "class B") == "@startuml\nclass B\n@enduml\n");
            // Several blank lines after @enduml
            assert(insert_at("@startuml\nclass A\n@enduml\n\n\n", 5, "a\nb") == "@startuml\nclass A\na\nb\n@enduml\n\n\n");
            // Between two diagrams: into the one above
            string two = "@startuml\nclass A\n@enduml\n\n@startuml\nclass C\n@enduml\n";
            assert(insert_at(two, 3, "class B") == "@startuml\nclass A\nclass B\n@enduml\n\n@startuml\nclass C\n@enduml\n");
            // Mermaid has no @end: after the current line / on the blank last line
            assert(insert_at("classDiagram\n    class A\n", 2, "class B") == "classDiagram\n    class A\nclass B");
            // Indentation of an indented current line
            assert(insert_at("@startuml\n  class A\n@enduml\n", 1, "class B") == "@startuml\n  class A\n  class B\n@enduml\n");

            // The selection lands on `select` inside the inserted text
            var buffer = make_buffer(doc);
            place_cursor_at_line(buffer, 3);
            SourceEdit.insert_snippet(buffer, "class Name", "Name", DiagramType.CLASS);
            Gtk.TextIter s, e;
            assert(buffer.get_selection_bounds(out s, out e));
            assert(buffer.get_text(s, e, false) == "Name");
            assert(s.get_line() == 2);

            // Empty editor: a new document of the snippet's type
            var empty = make_buffer("");
            SourceEdit.insert_snippet(empty, "class B", null, DiagramType.CLASS);
            assert(empty.text == "@startuml\nclass B\n@enduml\n");
        }

        // ── OutlineNode.key ──────────────────────────────────────────

        static Gee.ArrayList<OutlineNode> gantt_outline() {
            var roots = new Gee.ArrayList<OutlineNode>();
            OutlineNode.append(roots, "Title: Plan", "text-x-generic-symbolic", null);
            var dev1 = OutlineNode.append(roots, "Dev", "view-list-symbolic", null);
            OutlineNode.append(dev1.children, "Task", "task-due-symbolic", dev1);
            OutlineNode.append(dev1.children, "Task", "task-due-symbolic", dev1);
            OutlineNode.append(roots, "Test", "view-list-symbolic", null);
            var dev2 = OutlineNode.append(roots, "Dev", "view-list-symbolic", null);
            OutlineNode.append(dev2.children, "Task", "task-due-symbolic", dev2);
            return roots;
        }

        static void collect_keys(Gee.List<OutlineNode> nodes, Gee.List<string> keys) {
            foreach (var node in nodes) {
                keys.add(node.key());
                collect_keys(node.children, keys);
            }
        }

        public static void test_outline_keys() {
            var roots = gantt_outline();
            var keys = new Gee.ArrayList<string>();
            collect_keys(roots, keys);
            assert(keys.size == 7);
            var unique = new Gee.HashSet<string>();
            unique.add_all(keys);
            assert(unique.size == keys.size);
            assert(roots[1].key() != roots[3].key());
            assert(roots[1].children[0].key() != roots[3].children[0].key());
            assert(roots[1].children[0].key() != roots[1].children[1].key());

            // A rebuild from the same diagram (every render) produces the same keys
            var again = new Gee.ArrayList<string>();
            collect_keys(gantt_outline(), again);
            for (int i = 0; i < keys.size; i++) assert(keys[i] == again[i]);
        }

        public static int main(string[] args) {
            Test.init(ref args);
            Test.add_func("/review_ui/common_affixes", ReviewUiTests.test_affixes);
            Test.add_func("/review_ui/replace_one_undo_step", ReviewUiTests.test_replace_one_undo_step);
            Test.add_func("/review_ui/replace_keeps_marks", ReviewUiTests.test_replace_keeps_marks);
            Test.add_func("/review_ui/closing_line_before", ReviewUiTests.test_closing_line_before);
            Test.add_func("/review_ui/insert_snippet", ReviewUiTests.test_insert_snippet);
            Test.add_func("/review_ui/insert_swimlane", ReviewUiTests.test_insert_swimlane);
            Test.add_func("/review_ui/outline_keys", ReviewUiTests.test_outline_keys);
            return Test.run();
        }
    }
}
