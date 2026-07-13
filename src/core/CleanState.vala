namespace GDiagram {
    /**
     * Whether an editor's text is back to what was last loaded or saved.
     *
     * GtkTextBuffer only tracks "modified since set_modified(false)", so undoing back
     * to the saved text left documents marked modified and closing them prompted to
     * save an unchanged file. This keeps the saved text and compares against it: a
     * length check first, the full comparison only when the lengths match.
     */
    public class CleanState : Object {
        private string? saved_text = null;

        // No saved baseline: the text counts as modified until mark_saved()
        public bool has_baseline {
            get { return saved_text != null; }
        }

        public void mark_saved(string text) {
            saved_text = text;
        }

        public void clear() {
            saved_text = null;
        }

        public bool is_clean(string text) {
            if (saved_text == null) return false;
            if (saved_text.length != text.length) return false;
            return saved_text == text;
        }
    }
}
