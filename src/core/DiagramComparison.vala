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

        public void compare_sequences(
            MermaidSequenceDiagram old_d,
            MermaidSequenceDiagram new_d
        ) {
            diffs.clear();

            // Compare actors
            var old_actors = new Gee.HashSet<string>();
            var new_actors = new Gee.HashSet<string>();
            foreach (var a in old_d.actors) old_actors.add(a.id);
            foreach (var a in new_d.actors) new_actors.add(a.id);

            foreach (var a in new_d.actors) {
                if (!old_actors.contains(a.id)) {
                    var diff = new DiagramDiff(a.id, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "actor: %s".printf(a.id);
                    diffs.add(diff);
                }
            }
            foreach (var a in old_d.actors) {
                if (!new_actors.contains(a.id)) {
                    var diff = new DiagramDiff(a.id, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "actor: %s".printf(a.id);
                    diffs.add(diff);
                }
            }

            // Compare message count
            if (old_d.messages.size != new_d.messages.size) {
                var diff = new DiagramDiff("messages", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d messages".printf(old_d.messages.size);
                diff.new_value = "%d messages".printf(new_d.messages.size);
                diffs.add(diff);
            }
        }

        public void compare_states(
            MermaidStateDiagram old_d,
            MermaidStateDiagram new_d
        ) {
            diffs.clear();

            var old_ids = new Gee.HashSet<string>();
            var new_ids = new Gee.HashSet<string>();
            foreach (var s in old_d.states) old_ids.add(s.id);
            foreach (var s in new_d.states) new_ids.add(s.id);

            foreach (var s in new_d.states) {
                if (!old_ids.contains(s.id)) {
                    var diff = new DiagramDiff(s.id, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "state: %s".printf(s.id);
                    diffs.add(diff);
                }
            }
            foreach (var s in old_d.states) {
                if (!new_ids.contains(s.id)) {
                    var diff = new DiagramDiff(s.id, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "state: %s".printf(s.id);
                    diffs.add(diff);
                }
            }

            if (old_d.transitions.size != new_d.transitions.size) {
                var diff = new DiagramDiff("transitions", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d transitions".printf(old_d.transitions.size);
                diff.new_value = "%d transitions".printf(new_d.transitions.size);
                diffs.add(diff);
            }
        }

        public void compare_classes(
            MermaidClassDiagram old_d,
            MermaidClassDiagram new_d
        ) {
            diffs.clear();

            var old_names = new Gee.HashSet<string>();
            var new_names = new Gee.HashSet<string>();
            foreach (var c in old_d.classes) old_names.add(c.name);
            foreach (var c in new_d.classes) new_names.add(c.name);

            foreach (var c in new_d.classes) {
                if (!old_names.contains(c.name)) {
                    var diff = new DiagramDiff(c.name, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "class: %s".printf(c.name);
                    diffs.add(diff);
                }
            }
            foreach (var c in old_d.classes) {
                if (!new_names.contains(c.name)) {
                    var diff = new DiagramDiff(c.name, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "class: %s".printf(c.name);
                    diffs.add(diff);
                }
            }

            // Check member count changes for retained classes
            foreach (var old_cls in old_d.classes) {
                var new_cls = new_d.find_class(old_cls.name);
                if (new_cls != null && old_cls.members.size != new_cls.members.size) {
                    var diff = new DiagramDiff(old_cls.name, DiagramDiff.ChangeType.MODIFIED);
                    diff.old_value = "%d members".printf(old_cls.members.size);
                    diff.new_value = "%d members".printf(new_cls.members.size);
                    diffs.add(diff);
                }
            }

            if (old_d.relations.size != new_d.relations.size) {
                var diff = new DiagramDiff("relations", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d relations".printf(old_d.relations.size);
                diff.new_value = "%d relations".printf(new_d.relations.size);
                diffs.add(diff);
            }
        }

        public void compare_er_diagrams(
            MermaidERDiagram old_d,
            MermaidERDiagram new_d
        ) {
            diffs.clear();

            var old_names = new Gee.HashSet<string>();
            var new_names = new Gee.HashSet<string>();
            foreach (var e in old_d.entities) old_names.add(e.name);
            foreach (var e in new_d.entities) new_names.add(e.name);

            foreach (var e in new_d.entities) {
                if (!old_names.contains(e.name)) {
                    var diff = new DiagramDiff(e.name, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "entity: %s".printf(e.name);
                    diffs.add(diff);
                }
            }
            foreach (var e in old_d.entities) {
                if (!new_names.contains(e.name)) {
                    var diff = new DiagramDiff(e.name, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "entity: %s".printf(e.name);
                    diffs.add(diff);
                }
            }

            // Check attribute count for retained entities
            foreach (var old_e in old_d.entities) {
                var new_e = new_d.find_entity(old_e.name);
                if (new_e != null && old_e.attributes.size != new_e.attributes.size) {
                    var diff = new DiagramDiff(old_e.name, DiagramDiff.ChangeType.MODIFIED);
                    diff.old_value = "%d attributes".printf(old_e.attributes.size);
                    diff.new_value = "%d attributes".printf(new_e.attributes.size);
                    diffs.add(diff);
                }
            }

            if (old_d.relationships.size != new_d.relationships.size) {
                var diff = new DiagramDiff("relationships", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d relationships".printf(old_d.relationships.size);
                diff.new_value = "%d relationships".printf(new_d.relationships.size);
                diffs.add(diff);
            }
        }

        public void compare_gantt(MermaidGantt old_d, MermaidGantt new_d) {
            diffs.clear();

            var old_ids = new Gee.HashSet<string>();
            var new_ids = new Gee.HashSet<string>();
            foreach (var t in old_d.tasks) old_ids.add(t.id);
            foreach (var t in new_d.tasks) new_ids.add(t.id);

            foreach (var t in new_d.tasks) {
                if (!old_ids.contains(t.id)) {
                    var diff = new DiagramDiff(t.id, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = t.description;
                    diffs.add(diff);
                }
            }
            foreach (var t in old_d.tasks) {
                if (!new_ids.contains(t.id)) {
                    var diff = new DiagramDiff(t.id, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = t.description;
                    diffs.add(diff);
                }
            }

            // Check for modified tasks (description or status changed)
            foreach (var old_t in old_d.tasks) {
                foreach (var new_t in new_d.tasks) {
                    if (old_t.id == new_t.id) {
                        if (old_t.description != new_t.description ||
                            old_t.status != new_t.status) {
                            var diff = new DiagramDiff(old_t.id, DiagramDiff.ChangeType.MODIFIED);
                            diff.old_value = old_t.description;
                            diff.new_value = new_t.description;
                            diffs.add(diff);
                        }
                        break;
                    }
                }
            }
        }

        public void compare_pie(MermaidPie old_d, MermaidPie new_d) {
            diffs.clear();

            var old_labels = new Gee.HashSet<string>();
            var new_labels = new Gee.HashSet<string>();
            foreach (var s in old_d.slices) old_labels.add(s.label);
            foreach (var s in new_d.slices) new_labels.add(s.label);

            foreach (var s in new_d.slices) {
                if (!old_labels.contains(s.label)) {
                    var diff = new DiagramDiff(s.label, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "%.1f".printf(s.value);
                    diffs.add(diff);
                }
            }
            foreach (var s in old_d.slices) {
                if (!new_labels.contains(s.label)) {
                    var diff = new DiagramDiff(s.label, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "%.1f".printf(s.value);
                    diffs.add(diff);
                }
            }

            // Check for value changes on retained slices
            foreach (var old_s in old_d.slices) {
                foreach (var new_s in new_d.slices) {
                    if (old_s.label == new_s.label && old_s.value != new_s.value) {
                        var diff = new DiagramDiff(old_s.label, DiagramDiff.ChangeType.MODIFIED);
                        diff.old_value = "%.1f".printf(old_s.value);
                        diff.new_value = "%.1f".printf(new_s.value);
                        diffs.add(diff);
                        break;
                    }
                }
            }
        }

        public void compare_git_graphs(MermaidGitGraph old_d, MermaidGitGraph new_d) {
            diffs.clear();

            var old_ids = new Gee.HashSet<string>();
            var new_ids = new Gee.HashSet<string>();
            foreach (var c in old_d.all_commits) old_ids.add(c.id);
            foreach (var c in new_d.all_commits) new_ids.add(c.id);

            foreach (var c in new_d.all_commits) {
                if (!old_ids.contains(c.id)) {
                    var diff = new DiagramDiff(c.id, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "branch: %s".printf(c.branch_name);
                    diffs.add(diff);
                }
            }
            foreach (var c in old_d.all_commits) {
                if (!new_ids.contains(c.id)) {
                    var diff = new DiagramDiff(c.id, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "branch: %s".printf(c.branch_name);
                    diffs.add(diff);
                }
            }

            if (old_d.branches.size != new_d.branches.size) {
                var diff = new DiagramDiff("branches", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d branches".printf(old_d.branches.size);
                diff.new_value = "%d branches".printf(new_d.branches.size);
                diffs.add(diff);
            }
        }

        public void compare_user_journeys(
            MermaidUserJourney old_d,
            MermaidUserJourney new_d
        ) {
            diffs.clear();

            var old_sections = new Gee.HashSet<string>();
            var new_sections = new Gee.HashSet<string>();
            foreach (var s in old_d.sections) old_sections.add(s.name);
            foreach (var s in new_d.sections) new_sections.add(s.name);

            foreach (var s in new_d.sections) {
                if (!old_sections.contains(s.name)) {
                    var diff = new DiagramDiff(s.name, DiagramDiff.ChangeType.ADDED);
                    diff.new_value = "section: %s".printf(s.name);
                    diffs.add(diff);
                }
            }
            foreach (var s in old_d.sections) {
                if (!new_sections.contains(s.name)) {
                    var diff = new DiagramDiff(s.name, DiagramDiff.ChangeType.REMOVED);
                    diff.old_value = "section: %s".printf(s.name);
                    diffs.add(diff);
                }
            }

            if (old_d.all_tasks.size != new_d.all_tasks.size) {
                var diff = new DiagramDiff("tasks", DiagramDiff.ChangeType.MODIFIED);
                diff.old_value = "%d tasks".printf(old_d.all_tasks.size);
                diff.new_value = "%d tasks".printf(new_d.all_tasks.size);
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
                    default:
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
                    default:
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
