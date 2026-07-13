namespace GDiagram {
    public class ValidationMessage : Object {
        public enum Severity {
            INFO,
            WARNING,
            ERROR
        }

        public Severity severity { get; set; }
        public string message { get; set; }
        public int line { get; set; }

        public ValidationMessage(Severity severity, string message, int line = 0) {
            this.severity = severity;
            this.message = message;
            this.line = line;
        }
    }

    public class DiagramValidator : Object {
        public Gee.ArrayList<ValidationMessage> messages { get; private set; }

        public DiagramValidator() {
            messages = new Gee.ArrayList<ValidationMessage>();
        }

        public void validate_flowchart(MermaidFlowchart diagram) {
            messages.clear();

            // Check for disconnected nodes
            var connected_nodes = new Gee.HashSet<string>();
            foreach (var edge in diagram.edges) {
                connected_nodes.add(edge.from.id);
                connected_nodes.add(edge.to.id);
            }

            foreach (var node in diagram.nodes) {
                if (!connected_nodes.contains(node.id) && diagram.edges.size > 0) {
                    add_warning("Node '%s' is not connected to any other node".printf(node.id), node.source_line);
                }
            }

            // Check for nodes with same ID
            var node_ids = new Gee.HashMap<string, int>();
            foreach (var node in diagram.nodes) {
                if (node_ids.has_key(node.id)) {
                    add_warning("Duplicate node ID: '%s'".printf(node.id), node.source_line);
                }
                node_ids.set(node.id, 1);
            }

            // Check for empty nodes
            foreach (var node in diagram.nodes) {
                if (node.text.length == 0 || node.text == node.id) {
                    add_info("Node '%s' has no custom label".printf(node.id), node.source_line);
                }
            }

            // Performance suggestions
            if (diagram.nodes.size > 50) {
                add_info("Large diagram (%d nodes) - consider splitting into smaller diagrams".printf(diagram.nodes.size), 0);
            }

            if (diagram.edges.size > 100) {
                add_info("Many edges (%d) - diagram may be complex to read".printf(diagram.edges.size), 0);
            }
        }

        public void validate_sequence(MermaidSequenceDiagram diagram) {
            messages.clear();

            // Check for actors with messages but no declaration
            foreach (var message in diagram.messages) {
                bool from_declared = false;
                bool to_declared = false;

                foreach (var actor in diagram.actors) {
                    if (actor.id == message.from.id) from_declared = true;
                    if (actor.id == message.to.id) to_declared = true;
                }

                if (!from_declared) {
                    add_info("Actor '%s' used without explicit declaration".printf(message.from.id), 0);
                }
                if (!to_declared) {
                    add_info("Actor '%s' used without explicit declaration".printf(message.to.id), 0);
                }
            }

            // Performance suggestions
            if (diagram.messages.size > 30) {
                add_info("Long sequence (%d messages) - consider breaking into smaller diagrams".printf(diagram.messages.size), 0);
            }
        }

        public void validate_state(MermaidStateDiagram diagram) {
            messages.clear();

            // Check for unreachable states
            var reachable = new Gee.HashSet<string>();
            if (diagram.start_state != null) {
                reachable.add(diagram.start_state.id);
            }

            // BFS from start state
            bool changed = true;
            while (changed) {
                changed = false;
                foreach (var trans in diagram.transitions) {
                    if (reachable.contains(trans.from.id) && !reachable.contains(trans.to.id)) {
                        reachable.add(trans.to.id);
                        changed = true;
                    }
                }
            }

            foreach (var state in diagram.states) {
                if (!reachable.contains(state.id) && state.state_type == MermaidStateType.NORMAL) {
                    add_warning("State '%s' may be unreachable".printf(state.id), state.source_line);
                }
            }

            // Check for states with no outgoing transitions
            var has_outgoing = new Gee.HashSet<string>();
            foreach (var trans in diagram.transitions) {
                has_outgoing.add(trans.from.id);
            }

            foreach (var state in diagram.states) {
                if (!has_outgoing.contains(state.id) && state.state_type == MermaidStateType.NORMAL) {
                    add_info("State '%s' has no outgoing transitions".printf(state.id), state.source_line);
                }
            }
        }

        public void validate_class(MermaidClassDiagram diagram) {
            messages.clear();

            // Check for isolated classes (no relations)
            var connected = new Gee.HashSet<string>();
            foreach (var rel in diagram.relations) {
                connected.add(rel.from.name);
                connected.add(rel.to.name);
            }

            foreach (var cls in diagram.classes) {
                if (!connected.contains(cls.name) && diagram.classes.size > 1) {
                    add_warning("Class '%s' has no relationships".printf(cls.name), cls.source_line);
                }
            }

            // Check for duplicate member names within a class
            foreach (var cls in diagram.classes) {
                var member_names = new Gee.HashSet<string>();
                foreach (var member in cls.members) {
                    if (member_names.contains(member.name)) {
                        add_warning("Duplicate member '%s' in class '%s'".printf(
                            member.name, cls.name), cls.source_line);
                    }
                    member_names.add(member.name);
                }
            }

            // Check for self-referencing relations
            foreach (var rel in diagram.relations) {
                if (rel.from.name == rel.to.name) {
                    add_info("Class '%s' has a self-referencing relation".printf(rel.from.name), 0);
                }
            }

            // Performance suggestion
            if (diagram.classes.size > 20) {
                add_info("Large class diagram (%d classes) — consider splitting by package".printf(
                    diagram.classes.size), 0);
            }
        }

        public void validate_er(MermaidERDiagram diagram) {
            messages.clear();

            // Check for isolated entities
            var connected = new Gee.HashSet<string>();
            foreach (var rel in diagram.relationships) {
                connected.add(rel.from.name);
                connected.add(rel.to.name);
            }

            foreach (var entity in diagram.entities) {
                if (!connected.contains(entity.name) && diagram.entities.size > 1) {
                    add_warning("Entity '%s' has no relationships".printf(entity.name),
                        entity.source_line);
                }
            }

            // Check for entities missing a primary key
            foreach (var entity in diagram.entities) {
                bool has_pk = false;
                foreach (var attr in entity.attributes) {
                    if (attr.is_primary_key) { has_pk = true; break; }
                }
                if (!has_pk && entity.attributes.size > 0) {
                    add_info("Entity '%s' has no primary key attribute".printf(entity.name),
                        entity.source_line);
                }
            }

            // Check for relationships without labels
            int unlabeled = 0;
            foreach (var rel in diagram.relationships) {
                if (rel.label == null || rel.label.length == 0) unlabeled++;
            }
            if (unlabeled > 0 && diagram.relationships.size > 0) {
                add_info("%d relationship(s) have no label".printf(unlabeled), 0);
            }
        }

        public void validate_gantt(MermaidGantt diagram) {
            messages.clear();

            // Missing dateFormat is a common error
            if (diagram.date_format == null || diagram.date_format.length == 0) {
                add_warning("No dateFormat specified — Gantt chart may not render correctly",
                    0);
            }

            // Tasks without any time info
            foreach (var task in diagram.tasks) {
                if ((task.start_date == null || task.start_date.length == 0) &&
                    (task.duration == null || task.duration.length == 0) &&
                    (task.depends_on == null || task.depends_on.length == 0)) {
                    add_warning("Task '%s' has no start date, duration, or dependency".printf(
                        task.description), task.source_line);
                }
            }

            // Check for unknown dependency IDs
            var task_ids = new Gee.HashSet<string>();
            foreach (var task in diagram.tasks) task_ids.add(task.id);

            foreach (var task in diagram.tasks) {
                if (task.depends_on != null && task.depends_on.length > 0 &&
                    !task_ids.contains(task.depends_on)) {
                    add_warning("Task '%s' depends on unknown task id '%s'".printf(
                        task.description, task.depends_on), task.source_line);
                }
            }

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_info("Gantt chart has no title", 0);
            }
        }

        public void validate_pie(MermaidPie diagram) {
            messages.clear();

            if (diagram.slices.size == 0) {
                add_error("Pie chart has no data slices", 0);
                return;
            }

            // Check for zero or negative values
            foreach (var slice in diagram.slices) {
                if (slice.value <= 0) {
                    add_error("Slice '%s' has a non-positive value (%.2f)".printf(
                        slice.label, slice.value), slice.source_line);
                }
            }

            // Check for duplicate labels
            var labels = new Gee.HashSet<string>();
            foreach (var slice in diagram.slices) {
                if (labels.contains(slice.label)) {
                    add_warning("Duplicate pie slice label: '%s'".printf(slice.label),
                        slice.source_line);
                }
                labels.add(slice.label);
            }

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_info("Pie chart has no title", 0);
            }
        }

        public void validate_git_graph(MermaidGitGraph diagram) {
            messages.clear();

            if (diagram.all_commits.size == 0) {
                add_info("Git graph has no commits", 0);
                return;
            }

            // Build set of commit IDs for merge validation
            var commit_ids = new Gee.HashSet<string>();
            foreach (var c in diagram.all_commits) commit_ids.add(c.id);

            // Check for merge commits referencing a missing source
            foreach (var c in diagram.all_commits) {
                if (c.merge_from_id != null && c.merge_from_id.length > 0 &&
                    !commit_ids.contains(c.merge_from_id)) {
                    add_warning("Merge commit '%s' references unknown source commit '%s'".printf(
                        c.id, c.merge_from_id), c.source_line);
                }
            }

            // Branches with no commits
            foreach (var branch in diagram.branches) {
                if (branch.commits.size == 0) {
                    add_info("Branch '%s' has no commits".printf(branch.name), 0);
                }
            }

            // Duplicate commit IDs
            var seen_ids = new Gee.HashSet<string>();
            foreach (var c in diagram.all_commits) {
                if (seen_ids.contains(c.id)) {
                    add_warning("Duplicate commit id: '%s'".printf(c.id), c.source_line);
                }
                seen_ids.add(c.id);
            }
        }

        public void validate_user_journey(MermaidUserJourney diagram) {
            messages.clear();

            if (diagram.all_tasks.size == 0) {
                add_info("User journey has no tasks", 0);
                return;
            }

            // Check for tasks with out-of-range scores
            foreach (var task in diagram.all_tasks) {
                if (task.score < 1 || task.score > 5) {
                    add_error("Task '%s' score %d is out of range 1–5".printf(
                        task.description, task.score), task.source_line);
                }
            }

            // Empty sections
            foreach (var section in diagram.sections) {
                if (section.tasks.size == 0) {
                    add_warning("Section '%s' has no tasks".printf(section.name), 0);
                }
            }

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_info("User journey has no title", 0);
            }

            // Large journey
            if (diagram.all_tasks.size > 20) {
                add_info("Large journey (%d tasks) — consider splitting into multiple diagrams".printf(
                    diagram.all_tasks.size), 0);
            }
        }

        // =====================================================================
        // Validators for the remaining 15 Mermaid diagram types.
        // Each clears `messages` first, checks a handful of universal issues
        // (empty, missing title, scale warnings) plus type-specific invariants.
        // =====================================================================

        public void validate_mindmap(MermaidMindmap diagram) {
            messages.clear();
            if (diagram.root == null) {
                add_error("Mindmap has no root node", 0);
                return;
            }
            int node_count = count_mindmap_nodes(diagram.root);
            if (node_count == 1) {
                add_info("Mindmap has only a root node (add children to make it useful)", 0);
            }
            if (node_count > 60) {
                add_info("Large mindmap (%d nodes) — consider splitting".printf(node_count), 0);
            }
            if (diagram.title == null || diagram.title.length == 0) {
                add_info("Mindmap has no title", 0);
            }
        }

        private int count_mindmap_nodes(MindmapNode node) {
            int count = 1;
            foreach (var child in node.children) count += count_mindmap_nodes(child);
            return count;
        }

        public void validate_timeline(MermaidTimeline diagram) {
            messages.clear();
            if (diagram.periods.size == 0) {
                add_info("Timeline has no periods", 0);
                return;
            }
            foreach (var period in diagram.periods) {
                if (period.events.size == 0) {
                    add_info("Period '%s' has no events".printf(period.label), period.source_line);
                }
                if (period.label.length == 0) {
                    add_warning("Unnamed period", period.source_line);
                }
            }
            if (diagram.title == null || diagram.title.length == 0) {
                add_info("Timeline has no title", 0);
            }
        }

        public void validate_quadrant(MermaidQuadrant diagram) {
            messages.clear();
            // Points outside [0,1]
            foreach (var pt in diagram.points) {
                if (pt.x < 0 || pt.x > 1 || pt.y < 0 || pt.y > 1) {
                    add_error("Point '%s' at (%.2f, %.2f) is outside the 0..1 quadrant range".printf(
                        pt.label, pt.x, pt.y), pt.source_line);
                }
                if (pt.label.length == 0) {
                    add_warning("Unnamed point at (%.2f, %.2f)".printf(pt.x, pt.y), pt.source_line);
                }
            }
            if (diagram.points.size == 0) {
                add_info("Quadrant chart has no data points", 0);
            }
            if (diagram.x_axis_left.length == 0 || diagram.x_axis_right.length == 0) {
                add_info("Quadrant chart is missing x-axis labels", 0);
            }
            if (diagram.y_axis_top.length == 0 || diagram.y_axis_bottom.length == 0) {
                add_info("Quadrant chart is missing y-axis labels", 0);
            }
        }

        public void validate_xychart(MermaidXYChart diagram) {
            messages.clear();
            if (diagram.series.size == 0) {
                add_info("XY chart has no data series", 0);
                return;
            }
            if (diagram.x_labels.size == 0) {
                add_warning("XY chart has no x-axis labels", 0);
            }
            // Series length mismatch
            foreach (var s in diagram.series) {
                if (s.values.size != diagram.x_labels.size && diagram.x_labels.size > 0) {
                    add_warning("Series has %d values but x-axis has %d labels".printf(
                        s.values.size, diagram.x_labels.size), 0);
                }
            }
            if (diagram.has_y_range && diagram.y_min >= diagram.y_max) {
                add_error("y-axis range is invalid: y_min (%.1f) >= y_max (%.1f)".printf(
                    diagram.y_min, diagram.y_max), 0);
            }
        }

        public void validate_kanban(MermaidKanban diagram) {
            messages.clear();
            if (diagram.columns.size == 0) {
                add_info("Kanban board has no columns", 0);
                return;
            }
            // Duplicate column ids
            var col_ids = new Gee.HashSet<string>();
            foreach (var col in diagram.columns) {
                if (col_ids.contains(col.id)) {
                    add_error("Duplicate column id: '%s'".printf(col.id), col.source_line);
                }
                col_ids.add(col.id);
                if (col.label.length == 0) {
                    add_warning("Unnamed column '%s'".printf(col.id), col.source_line);
                }
            }
            // Column with excessive cards
            foreach (var col in diagram.columns) {
                if (col.cards.size > 20) {
                    add_info("Column '%s' has %d cards — consider breaking it up".printf(
                        col.label, col.cards.size), col.source_line);
                }
            }
        }

        public void validate_sankey(MermaidSankey diagram) {
            messages.clear();
            if (diagram.links.size == 0) {
                add_info("Sankey diagram has no links", 0);
                return;
            }
            foreach (var link in diagram.links) {
                if (link.value < 0) {
                    add_error("Negative flow value (%.2f) from '%s' to '%s'".printf(
                        link.value, link.source, link.target), link.source_line);
                }
                if (link.source == link.target) {
                    add_warning("Self-loop on node '%s'".printf(link.source), link.source_line);
                }
            }
            // Duplicate source→target pairs
            var seen = new Gee.HashSet<string>();
            foreach (var link in diagram.links) {
                string key = "%s→%s".printf(link.source, link.target);
                if (seen.contains(key)) {
                    add_warning("Duplicate link: %s".printf(key), link.source_line);
                }
                seen.add(key);
            }
        }

        public void validate_requirement(MermaidRequirement diagram) {
            messages.clear();
            if (diagram.elements.size == 0) {
                add_info("Requirement diagram has no elements", 0);
                return;
            }
            // Duplicate element names
            var names = new Gee.HashSet<string>();
            foreach (var el in diagram.elements) {
                if (names.contains(el.name)) {
                    add_error("Duplicate element name: '%s'".printf(el.name), el.source_line);
                }
                names.add(el.name);
            }
            // Dangling relationships (src/target not in elements)
            foreach (var rel in diagram.relationships) {
                if (!names.contains(rel.source)) {
                    add_error("Relationship source '%s' not defined as element".printf(rel.source),
                        rel.source_line);
                }
                if (!names.contains(rel.target)) {
                    add_error("Relationship target '%s' not defined as element".printf(rel.target),
                        rel.source_line);
                }
            }
            // Requirements without text
            foreach (var el in diagram.elements) {
                if (el.req_type.down() != "element" && el.text.length == 0) {
                    add_warning("Requirement '%s' has no text".printf(el.name), el.source_line);
                }
            }
        }

        public void validate_block(MermaidBlock diagram) {
            messages.clear();
            if (diagram.nodes.size == 0) {
                add_info("Block diagram has no nodes", 0);
                return;
            }
            var ids = new Gee.HashSet<string>();
            foreach (var n in diagram.nodes) {
                if (ids.contains(n.id)) {
                    add_error("Duplicate block id: '%s'".printf(n.id), n.source_line);
                }
                ids.add(n.id);
            }
            foreach (var e in diagram.edges) {
                if (!ids.contains(e.source)) {
                    add_warning("Edge source '%s' not defined".printf(e.source), e.source_line);
                }
                if (!ids.contains(e.target)) {
                    add_warning("Edge target '%s' not defined".printf(e.target), e.source_line);
                }
            }
        }

        public void validate_packet(MermaidPacket diagram) {
            messages.clear();
            if (diagram.fields.size == 0) {
                add_info("Packet diagram has no fields", 0);
                return;
            }
            // Overlapping ranges + ordering
            var sorted = new Gee.ArrayList<PacketField>();
            foreach (var f in diagram.fields) sorted.add(f);
            sorted.sort((a, b) => a.bit_start - b.bit_start);
            for (int i = 0; i < sorted.size; i++) {
                var f = sorted.get(i);
                if (f.bit_end < f.bit_start) {
                    add_error("Field '%s' has invalid range %d..%d".printf(
                        f.label, f.bit_start, f.bit_end), f.source_line);
                }
                if (i > 0) {
                    var prev = sorted.get(i - 1);
                    if (f.bit_start <= prev.bit_end) {
                        add_error("Field '%s' overlaps field '%s' at bit %d".printf(
                            f.label, prev.label, f.bit_start), f.source_line);
                    }
                }
                if (f.label.length == 0) {
                    add_warning("Unnamed field at bits %d..%d".printf(
                        f.bit_start, f.bit_end), f.source_line);
                }
            }
        }

        public void validate_c4(MermaidC4 diagram) {
            messages.clear();
            if (diagram.elements.size == 0) {
                add_info("C4 diagram has no elements", 0);
                return;
            }
            // Duplicate element ids
            var ids = new Gee.HashSet<string>();
            foreach (var el in diagram.elements) {
                if (ids.contains(el.id)) {
                    add_error("Duplicate C4 element id: '%s'".printf(el.id), el.source_line);
                }
                ids.add(el.id);
                if (el.label.length == 0) {
                    add_warning("Unlabeled C4 element '%s'".printf(el.id), el.source_line);
                }
            }
            // Boundary parent references
            var boundary_ids = new Gee.HashSet<string>();
            foreach (var b in diagram.boundaries) boundary_ids.add(b.id);
            foreach (var b in diagram.boundaries) {
                if (b.parent_boundary != null && !boundary_ids.contains(b.parent_boundary)) {
                    add_error("Boundary '%s' references unknown parent '%s'".printf(
                        b.id, b.parent_boundary), b.source_line);
                }
            }
            foreach (var el in diagram.elements) {
                if (el.parent_boundary != null && !boundary_ids.contains(el.parent_boundary)) {
                    add_error("Element '%s' references unknown boundary '%s'".printf(
                        el.id, el.parent_boundary), el.source_line);
                }
            }
            // Dangling relationships
            foreach (var rel in diagram.relationships) {
                if (!ids.contains(rel.from_id)) {
                    add_error("Relationship source '%s' not defined".printf(rel.from_id),
                        rel.source_line);
                }
                if (!ids.contains(rel.to_id)) {
                    add_error("Relationship target '%s' not defined".printf(rel.to_id),
                        rel.source_line);
                }
            }
        }

        public void validate_architecture(MermaidArchitecture diagram) {
            messages.clear();
            if (diagram.services.size == 0) {
                add_info("Architecture diagram has no services", 0);
                return;
            }
            var svc_ids = new Gee.HashSet<string>();
            foreach (var s in diagram.services) {
                if (svc_ids.contains(s.id)) {
                    add_error("Duplicate service id: '%s'".printf(s.id), s.source_line);
                }
                svc_ids.add(s.id);
            }
            var group_ids = new Gee.HashSet<string>();
            foreach (var g in diagram.groups) group_ids.add(g.id);
            // Services pointing at nonexistent groups
            foreach (var s in diagram.services) {
                if (s.group_id != null && !group_ids.contains(s.group_id)) {
                    add_error("Service '%s' references unknown group '%s'".printf(
                        s.id, s.group_id), s.source_line);
                }
            }
            // Edges touching undefined endpoints
            foreach (var e in diagram.edges) {
                if (!svc_ids.contains(e.from_id)) {
                    add_warning("Edge source '%s' not defined as a service".printf(e.from_id),
                        e.source_line);
                }
                if (!svc_ids.contains(e.to_id)) {
                    add_warning("Edge target '%s' not defined as a service".printf(e.to_id),
                        e.source_line);
                }
            }
        }

        public void validate_zenuml(MermaidZenUML diagram) {
            messages.clear();
            if (diagram.messages.size == 0 && diagram.participants.size == 0) {
                add_info("ZenUML diagram is empty", 0);
                return;
            }
            var part_names = new Gee.HashSet<string>();
            foreach (var p in diagram.participants) part_names.add(p.name);
            foreach (var m in diagram.messages) {
                if (m.from_name.length > 0 && !part_names.contains(m.from_name)) {
                    add_info("Participant '%s' used without declaration".printf(m.from_name),
                        m.source_line);
                }
                if (m.to_name.length > 0 && !part_names.contains(m.to_name)) {
                    add_info("Participant '%s' used without declaration".printf(m.to_name),
                        m.source_line);
                }
            }
        }

        public void validate_radar(MermaidRadar diagram) {
            messages.clear();
            if (diagram.axes.size == 0) {
                add_error("Radar chart has no axes", 0);
                return;
            }
            if (diagram.axes.size < 3) {
                add_warning("Radar chart needs at least 3 axes to look correct", 0);
            }
            if (diagram.curves.size == 0) {
                add_info("Radar chart has no curves", 0);
            }
            if (diagram.min_value >= diagram.max_value) {
                add_error("Radar value range invalid: min (%.1f) >= max (%.1f)".printf(
                    diagram.min_value, diagram.max_value), 0);
            }
            var axis_ids = new Gee.HashSet<string>();
            foreach (var a in diagram.axes) axis_ids.add(a.id);
            // Key-valued curves reference valid axes
            foreach (var c in diagram.curves) {
                foreach (var key in c.key_values.keys) {
                    if (!axis_ids.contains(key)) {
                        add_warning("Curve '%s' references unknown axis '%s'".printf(
                            c.label, key), c.source_line);
                    }
                }
                // Out-of-range values
                foreach (var v in c.values) {
                    if (v != null && (v < diagram.min_value || v > diagram.max_value)) {
                        add_warning("Curve '%s' has value %.1f outside %.1f..%.1f".printf(
                            c.label, v, diagram.min_value, diagram.max_value), c.source_line);
                        break;
                    }
                }
            }
        }

        public void validate_treemap(MermaidTreemap diagram) {
            messages.clear();
            if (diagram.roots.size == 0) {
                add_info("Treemap has no root nodes", 0);
                return;
            }
            foreach (var root in diagram.roots) {
                check_treemap_node(root);
            }
        }

        private void check_treemap_node(TreemapNode node) {
            if (node.is_leaf) {
                if (node.value < 0) {
                    add_error("Treemap leaf '%s' has negative value %.1f".printf(
                        node.label, node.value), node.source_line);
                }
                if (node.value == 0) {
                    add_info("Treemap leaf '%s' has zero value".printf(node.label), node.source_line);
                }
            } else if (node.children.size == 0) {
                add_warning("Branch node '%s' has no children".printf(node.label), node.source_line);
            }
            foreach (var child in node.children) check_treemap_node(child);
        }

        public bool has_issues() {
            foreach (var msg in messages) {
                if (msg.severity == ValidationMessage.Severity.ERROR) {
                    return true;
                }
            }
            return false;
        }

        public bool has_warnings() {
            foreach (var msg in messages) {
                if (msg.severity == ValidationMessage.Severity.WARNING) {
                    return true;
                }
            }
            return false;
        }

        public string get_summary() {
            if (messages.size == 0) {
                return "✅ No issues found";
            }

            var sb = new StringBuilder();
            int errors = 0, warnings = 0, infos = 0;

            foreach (var msg in messages) {
                switch (msg.severity) {
                    case ValidationMessage.Severity.ERROR:
                        errors++;
                        break;
                    case ValidationMessage.Severity.WARNING:
                        warnings++;
                        break;
                    case ValidationMessage.Severity.INFO:
                        infos++;
                        break;
                }
            }

            if (errors > 0) {
                sb.append_printf("❌ %d error(s)\n", errors);
            }
            if (warnings > 0) {
                sb.append_printf("⚠️  %d warning(s)\n", warnings);
            }
            if (infos > 0) {
                sb.append_printf("ℹ️  %d suggestion(s)\n", infos);
            }

            sb.append("\nDetails:\n");
            foreach (var msg in messages) {
                string icon = "";
                switch (msg.severity) {
                    case ValidationMessage.Severity.ERROR:
                        icon = "❌";
                        break;
                    case ValidationMessage.Severity.WARNING:
                        icon = "⚠️ ";
                        break;
                    case ValidationMessage.Severity.INFO:
                        icon = "ℹ️ ";
                        break;
                }

                if (msg.line > 0) {
                    sb.append_printf("%s Line %d: %s\n", icon, msg.line, msg.message);
                } else {
                    sb.append_printf("%s %s\n", icon, msg.message);
                }
            }

            return sb.str;
        }

        private void add_error(string message, int line = 0) {
            messages.add(new ValidationMessage(ValidationMessage.Severity.ERROR, message, line));
        }

        private void add_warning(string message, int line = 0) {
            messages.add(new ValidationMessage(ValidationMessage.Severity.WARNING, message, line));
        }

        private void add_info(string message, int line = 0) {
            messages.add(new ValidationMessage(ValidationMessage.Severity.INFO, message, line));
        }
    }
}
