namespace GDiagram {
    public class Document : Object {
        public string title { get; set; default = "Untitled"; }
        public string content { get; set; default = ""; }
        public bool modified { get; set; default = false; }
        public bool git_dirty { get; set; default = false; }
        public File? file { get; set; default = null; }

        // The text last loaded or saved: undoing back to it clears `modified`
        public CleanState clean_state { get; private set; default = new CleanState(); }

        // File monitoring
        private FileMonitor? file_monitor = null;
        private bool ignore_next_change = false;

        // Signal emitted when file changes externally
        public signal void external_change();

        /**
         * A different document is now in this object: its text came from another file.
         *
         * Not emitted by reload() (same file, same document) and not by setting `file`:
         * Save As gives the text on screen a name, which is not a document change, and
         * resetting the preview there threw away the user's zoom and scroll position.
         */
        public signal void loaded();

        public Document() {
            content = "@startuml\n\n@enduml\n";
        }

        // PathIdentity.key(file) costs a query_info; cached because every open of any file
        // asks each open tab whether it is that file, which was one blocking stat per tab
        // (on a network mount, one round-trip per tab).
        private string? file_key = null;

        construct {
            notify["file"].connect(() => { file_key = null; });
        }

        /** This document's file identity, or "" when it has never been saved. */
        public string identity_key {
            get {
                if (file == null) return "";
                if (file_key == null) file_key = PathIdentity.key(file);
                return file_key;
            }
        }

        ~Document() {
            stop_monitoring();
        }

        private void stop_monitoring() {
            if (file_monitor != null) {
                file_monitor.cancel();
                file_monitor = null;
            }
        }

        private void start_monitoring() {
            if (file == null) return;

            try {
                file_monitor = file.monitor_file(FileMonitorFlags.NONE, null);
                file_monitor.changed.connect(on_file_changed);
            } catch (Error e) {
                warning("Failed to monitor file: %s", e.message);
            }
        }

        private void on_file_changed(File file, File? _other_file, FileMonitorEvent event) {
            // Only react to content changes
            if (event != FileMonitorEvent.CHANGED && event != FileMonitorEvent.CHANGES_DONE_HINT) {
                return;
            }

            // Ignore changes triggered by our own saves
            if (ignore_next_change) {
                ignore_next_change = false;
                return;
            }

            // Emit signal on main thread
            Idle.add(() => {
                external_change();
                return false;
            });
        }

        // Cast raw bytes to a Vala string safely. `(string) contents`
        // calls strlen which (a) can read past the array end if the
        // byte buffer isn't NUL-terminated, or (b) truncates at the
        // first embedded NUL. Build a properly-sized UTF-8 string so
        // both failure modes are handled.
        private static string bytes_to_string(uint8[] contents) {
            if (contents.length == 0) return "";
            unowned string raw = (string) contents;
            int safe_len = int.min(raw.length, (int) contents.length);
            if (raw.length == contents.length) return raw;
            return raw.substring(0, safe_len);
        }

        public async void load_from_file(File file) throws Error {
            stop_monitoring();

            this.file = file;
            this.title = file.get_basename();

            uint8[] contents;
            yield file.load_contents_async(null, out contents, null);
            string text = bytes_to_string(contents);
            clean_state.mark_saved(text);
            this.content = text;
            this.modified = false;

            start_monitoring();
            loaded();
        }

        public async void reload() throws Error {
            if (file == null) return;

            uint8[] contents;
            yield file.load_contents_async(null, out contents, null);
            string text = bytes_to_string(contents);
            clean_state.mark_saved(text);
            this.content = text;
            this.modified = false;
        }

        public async void save() throws Error {
            if (file == null) {
                throw new IOError.FAILED("No file specified");
            }

            // Ignore the file change event triggered by our own save
            ignore_next_change = true;

            // What is written, in case the text changes while the write is in progress
            string text = content;
            yield file.replace_contents_async(
                text.data,
                null,
                false,
                FileCreateFlags.NONE,
                null,
                null
            );

            this.title = file.get_basename();
            clean_state.mark_saved(text);
            this.modified = !clean_state.is_clean(content);
        }

        // Editor text changed: modified unless it is the saved text again
        public void update_modified(string text) {
            this.modified = !clean_state.is_clean(text);
        }
    }
}
