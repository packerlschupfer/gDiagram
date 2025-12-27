namespace GDiagram {
    public class DiagramDiff : Object {
        public enum ChangeType {
            ADDED,
            REMOVED,
            MODIFIED,
            UNCHANGED
        }

        public string element_id { get; set; }
        public ChangeType change_type { get; set; }
        public string? old_value { get; set; }
        public string? new_value { get; set; }

        public DiagramDiff(string id, ChangeType type) {
            this.element_id = id;
            this.change_type = type;
        }
    }

    public class DiagramComparison : Object {
        public Gee.ArrayList<DiagramDiff> diffs { get; private set; }

        public DiagramComparison() {
            diffs = new Gee.ArrayList<DiagramDiff>();
        }

        public void compare_flowcharts(MermaidFlowchart old_diagram, MermaidFlowchart new_diagram) {
            diffs.clear();

            // Compare nodes
            var old_node_ids = new Gee.HashSet<string>();
            var new_node_ids = new Gee.HashSet<string>();

            foreach (var node in old_diagram.nodes) {
                old_node_ids.add(node.id);
            }

            foreach (var node in new_diagram.nodes) {
                new_node_ids.add(node.id);
            }

            // Find added nodes
            foreach (var node in new_diagram.nodes) {
                if (!old_node_ids.contains(node.id)) {
                    var diff = new DiagramDiff(node.id, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = node.text;
                    diffs.add(diff);
                }
            }

            // Find removed nodes
            foreach (var node in old_diagram.nodes) {
                if (!new_node_ids.contains(node.id)) {
                    var diff = new DiagramDiff(node.id, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = node.text;
                    diffs.add(diff);
                }
            }

            // Find modified nodes
            foreach (var old_node in old_diagram.nodes) {
                var new_node = new_diagram.find_node(old_node.id);
                if (new_node != null) {
                    if (old_node.text != new_node.text ||
                        old_node.shape != new_node.shape ||
                        old_node.fill_color != new_node.fill_color) {
                        var diff = new DiagramDiff(old_node.id, DiagramDiff.ChangeType.MODIFIED);
                        diff.old_value = old_node.text;
                        diff.new_value = new_node.text;
                        diffs.add(diff);
                    }
                }
            }

            // Compare edges
            int old_edge_count = old_diagram.edges.size;
            int new_edge_count = new_diagram.edges.size;

            if (old_edge_count != new_edge_count) {
                var diff = new DiagramDiff("edges", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d edges".printf(old_edge_count);
                diff.new_value = "%d edges".printf(new_edge_count);
                diffs.add(diff);
            }
        }

        public string get_summary() {
            if (diffs.size == 0) {
                return "✅ No differences found - diagrams are identical";
            }

            var sb = new StringBuilder();
            sb.append("📊 Diagram Comparison:\n\n");

            int added = 0, removed = 0, modified = 0;

            foreach (var diff in diffs) {
                switch (diff.change_type) {
                    case DiagramDiff.ChangeType.ADDED:
                        added++;
                        break;
                    case DiagramDiff.ChangeType.REMOVED:
                        removed++;
                        break;
                    case DiagramDiff.ChangeType.MODIFIED:
                        modified++;
                        break;
                }
            }

            sb.append_printf("  ✅ Added: %d\n", added);
            sb.append_printf("  ❌ Removed: %d\n", removed);
            sb.append_printf("  🔄 Modified: %d\n", modified);
            sb.append("\nDetails:\n\n");

            foreach (var diff in diffs) {
                switch (diff.change_type) {
                    case DiagramDiff.ChangeType.ADDED:
                        sb.append_printf("  + %s: %s\n", diff.element_id, diff.new_value ?? "");
                        break;
                    case DiagramDiff.ChangeType.REMOVED:
                        sb.append_printf("  - %s: %s\n", diff.element_id, diff.old_value ?? "");
                        break;
                    case DiagramDiff.ChangeType.MODIFIED:
                        sb.append_printf("  ~ %s: '%s' → '%s'\n",
                            diff.element_id,
                            diff.old_value ?? "",
                            diff.new_value ?? "");
                        break;
                }
            }

            return sb.str;
        }

        public bool has_changes() {
            return diffs.size > 0;
        }

        public int get_change_count() {
            return diffs.size;
        }
    }
}
