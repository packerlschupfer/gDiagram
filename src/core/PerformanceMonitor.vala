namespace GDiagram {
    public class PerformanceMetrics : Object {
        public double parse_time_ms { get; set; default = 0.0; }
        public double render_time_ms { get; set; default = 0.0; }
        public double total_time_ms { get; set; default = 0.0; }
        public int svg_size_bytes { get; set; default = 0; }
        public int node_count { get; set; default = 0; }
        public int edge_count { get; set; default = 0; }

        public string get_rating() {
            if (total_time_ms < 5.0) {
                return "🟢 Excellent (<5ms)";
            } else if (total_time_ms < 20.0) {
                return "🟡 Good (<20ms)";
            } else if (total_time_ms < 50.0) {
                return "🟠 Acceptable (<50ms)";
            } else {
                return "🔴 Slow (>50ms)";
            }
        }

        public string get_summary() {
            var sb = new StringBuilder();
            sb.append("⚡ Performance Metrics:\n\n");
            sb.append_printf("  Parse Time: %.2f ms\n", parse_time_ms);
            sb.append_printf("  Render Time: %.2f ms\n", render_time_ms);
            sb.append_printf("  Total Time: %.2f ms\n", total_time_ms);
            sb.append_printf("  SVG Size: %.1f KB\n", svg_size_bytes / 1024.0);
            sb.append_printf("  Throughput: %.0f nodes/sec\n",
                total_time_ms > 0 ? (node_count / total_time_ms) * 1000 : 0);
            sb.append_printf("\n  Rating: %s\n", get_rating());

            return sb.str;
        }
    }

    public class PerformanceMonitor : Object {
        private Timer timer;
        private PerformanceMetrics current_metrics;

        public PerformanceMonitor() {
            timer = new Timer();
            current_metrics = new PerformanceMetrics();
        }

        public void start_parse() {
            timer.reset();
            timer.start();
        }

        public void end_parse() {
            current_metrics.parse_time_ms = timer.elapsed() * 1000.0;
        }

        public void start_render() {
            timer.reset();
            timer.start();
        }

        public void end_render(int svg_size = 0) {
            current_metrics.render_time_ms = timer.elapsed() * 1000.0;
            current_metrics.svg_size_bytes = svg_size;
            current_metrics.total_time_ms = current_metrics.parse_time_ms + current_metrics.render_time_ms;
        }

        public void set_diagram_info(int nodes, int edges) {
            current_metrics.node_count = nodes;
            current_metrics.edge_count = edges;
        }

        public PerformanceMetrics get_metrics() {
            return current_metrics;
        }

        public string get_quick_stats() {
            return "⚡ %.1fms total".printf(current_metrics.total_time_ms);
        }

        // Get performance suggestions
        public string[]? get_suggestions() {
            var suggestions = new Gee.ArrayList<string>();

            if (current_metrics.total_time_ms > 50.0) {
                suggestions.add("Rendering is slow (>50ms) - consider simplifying diagram");
            }

            if (current_metrics.node_count > 50) {
                suggestions.add("Large diagram - try 'sfdp' layout engine for better performance");
            }

            if (current_metrics.svg_size_bytes > 100 * 1024) {
                suggestions.add("Large SVG output (>100KB) - complexity may affect export");
            }

            double nodes_per_ms = current_metrics.total_time_ms > 0 ?
                current_metrics.node_count / current_metrics.total_time_ms : 0;

            if (nodes_per_ms < 5.0 && current_metrics.node_count > 10) {
                suggestions.add("Low throughput - consider enabling caching or simplifying");
            }

            if (suggestions.size == 0) {
                return null;
            }

            return suggestions.to_array();
        }
    }
}
