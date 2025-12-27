namespace GPlantUML {
    public class Document : Object {
        public string title { get; set; default = "Untitled"; }
        public string content { get; set; default = ""; }
        public bool modified { get; set; default = false; }
        public File? file { get; set; default = null; }

        // File monitoring
        private FileMonitor? file_monitor = null;
        private bool ignore_next_change = false;

        // Signal emitted when file changes externally
        public signal void external_change();

        public Document() {
            content = "@startuml\n\n@enduml\n";
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

        private void on_file_changed(File file, File? other_file, FileMonitorEvent event) {
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

        public async void load_from_file(File file) throws Error {
            stop_monitoring();

            this.file = file;
            this.title = file.get_basename();

            uint8[] contents;
            yield file.load_contents_async(null, out contents, null);
            this.content = (string) contents;
            this.modified = false;

            start_monitoring();
        }

        public async void reload() throws Error {
            if (file == null) return;

            uint8[] contents;
            yield file.load_contents_async(null, out contents, null);
            this.content = (string) contents;
            this.modified = false;
        }

        public async void save() throws Error {
            if (file == null) {
                throw new IOError.FAILED("No file specified");
            }

            // Ignore the file change event triggered by our own save
            ignore_next_change = true;

            yield file.replace_contents_async(
                content.data,
                null,
                false,
                FileCreateFlags.NONE,
                null,
                null
            );

            this.title = file.get_basename();
            this.modified = false;
        }
    }
}
