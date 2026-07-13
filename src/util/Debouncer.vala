namespace GDiagram {
    public delegate void DebounceCallback();

    public class Debouncer : Object {
        private uint timeout_id = 0;
        public uint delay_ms { get; set; default = 300; }

        public Debouncer(uint delay_ms = 300) {
            this.delay_ms = delay_ms;
        }

        public void call(owned DebounceCallback callback) {
            bool debug = Environment.get_variable("G_MESSAGES_DEBUG") != null;
            if (debug) print("[DEBUG] Debouncer.call() - scheduling callback in %u ms\n", delay_ms);

            cancel();

            timeout_id = Timeout.add(delay_ms, () => {
                if (debug) print("[DEBUG] Debouncer timeout fired, executing callback\n");
                timeout_id = 0;
                callback();
                if (debug) print("[DEBUG] Debouncer callback completed\n");
                return Source.REMOVE;
            });
        }

        public void cancel() {
            if (timeout_id != 0) {
                Source.remove(timeout_id);
                timeout_id = 0;
            }
        }

        ~Debouncer() {
            cancel();
        }
    }
}
