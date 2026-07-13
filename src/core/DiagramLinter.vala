namespace GDiagram {
    public class LintMessage : Object {
        public enum Level {
            SUGGESTION,
            STYLE,
            BEST_PRACTICE,
            PERFORMANCE
        }

        public Level level { get; set; }
        public string message { get; set; }
        public string? fix_suggestion { get; set; }
        public int line { get; set; }

        public LintMessage(Level level, string message, string? fix = null, int line = 0) {
            this.level = level;
            this.message = message;
            this.fix_suggestion = fix;
            this.line = line;
        }
    }

    public class DiagramLinter : Object {
        public Gee.ArrayList<LintMessage> messages { get; private set; }

        public DiagramLinter() {
            messages = new Gee.ArrayList<LintMessage>();
        }

        public void lint_flowchart(MermaidFlowchart diagram) {
            messages.clear();

            // Best Practice: Start and End nodes
            bool has_start = false;
            bool has_end = false;

            foreach (var node in diagram.nodes) {
                string lower_text = node.text.down();
                if (lower_text.contains("start") || lower_text.contains("begin")) {
                    has_start = true;
                }
                if (lower_text.contains("end") || lower_text.contains("finish") || lower_text.contains("done")) {
                    has_end = true;
                }
            }

            if (!has_start && diagram.nodes.size > 3) {
                add_best_practice("Consider adding a clear 'Start' node", "Add: Start[Start] at the beginning");
            }

            if (!has_end && diagram.nodes.size > 3) {
                add_best_practice("Consider adding a clear 'End' node", "Add: End[End] at the termination points");
            }

            // Style: Consistent node naming
            bool has_lowercase = false;
            bool has_uppercase = false;

            foreach (var node in diagram.nodes) {
                if (node.id[0].islower()) has_lowercase = true;
                if (node.id[0].isupper()) has_uppercase = true;
            }

            if (has_lowercase && has_uppercase) {
                add_style("Inconsistent node ID casing", "Use consistent casing (e.g., all PascalCase or camelCase)");
            }

            // Performance: Large diagrams
            if (diagram.nodes.size > 40) {
                add_performance("Large diagram (%d nodes)".printf(diagram.nodes.size),
                    "Consider using subgraphs or splitting into multiple diagrams");
            }

            // Best Practice: Color coding decision nodes
            int decision_count = 0;
            int colored_decisions = 0;

            foreach (var node in diagram.nodes) {
                if (node.shape == FlowchartNodeShape.RHOMBUS) {
                    decision_count++;
                    if (node.fill_color != null) {
                        colored_decisions++;
                    }
                }
            }

            if (decision_count > 2 && colored_decisions == 0) {
                add_suggestion("Decision nodes could benefit from color coding",
                    "Example: style Decision fill:#FFD700");
            }

            // Best Practice: Edge labels on branches
            int branch_edges = 0;
            int labeled_branches = 0;

            foreach (var edge in diagram.edges) {
                if (edge.from.shape == FlowchartNodeShape.RHOMBUS) {
                    branch_edges++;
                    if (edge.label != null && edge.label.length > 0) {
                        labeled_branches++;
                    }
                }
            }

            if (branch_edges > 0 && labeled_branches < branch_edges / 2) {
                add_best_practice("Decision branches should have labels",
                    "Example: Decision -->|Yes| Process");
            }

            // Style: Use of subgraphs for complex diagrams
            if (diagram.nodes.size > 15 && diagram.subgraphs.size == 0) {
                add_suggestion("Consider using subgraphs to organize nodes",
                    "Example: subgraph Processing\\n    Process\\n    Transform\\nend");
            }

            // Best Practice: Disconnected nodes
            var connected = new Gee.HashSet<string>();
            foreach (var edge in diagram.edges) {
                connected.add(edge.from.id);
                connected.add(edge.to.id);
            }

            int disconnected = 0;
            foreach (var node in diagram.nodes) {
                if (!connected.contains(node.id)) {
                    disconnected++;
                }
            }

            if (disconnected > 0 && diagram.edges.size > 0) {
                add_best_practice("%d node(s) not connected".printf(disconnected),
                    "Ensure all nodes are part of the workflow");
            }
        }

        public void lint_sequence(MermaidSequenceDiagram diagram) {
            messages.clear();

            // Best Practice: Use autonumbering for clarity
            if (diagram.messages.size > 5 && !diagram.autonumber) {
                add_suggestion("Consider using autonumbering for better readability",
                    "Add 'autonumber' after sequenceDiagram");
            }

            // Best Practice: Add notes for complex interactions
            if (diagram.messages.size > 10 && diagram.notes.size == 0) {
                add_suggestion("Consider adding notes to explain complex interactions",
                    "Example: Note over Alice,Bob: Important step");
            }

            // Style: Consistent participant naming
            foreach (var actor in diagram.actors) {
                if (actor.alias == null && actor.id.contains("_")) {
                    add_style("Consider using aliases for readable participant names",
                        "Example: participant %s as %s".printf(actor.id, actor.id.replace("_", " ")));
                }
            }

            // Performance: Very long sequences
            if (diagram.messages.size > 25) {
                add_performance("Long sequence (%d messages)".printf(diagram.messages.size),
                    "Consider breaking into multiple diagrams or using loops");
            }
        }

        public void lint_state(MermaidStateDiagram diagram) {
            messages.clear();

            // Best Practice: Should have start state
            if (diagram.start_state == null && diagram.states.size > 2) {
                add_best_practice("State diagram should have a start state",
                    "Add: [*] --> FirstState");
            }

            // Best Practice: Should have end state
            if (diagram.end_state == null && diagram.states.size > 2) {
                add_best_practice("Consider adding an end state",
                    "Add: FinalState --> [*]");
            }

            // Best Practice: Transition labels
            int transitions_without_labels = 0;
            foreach (var trans in diagram.transitions) {
                if (trans.label == null || trans.label.length == 0) {
                    transitions_without_labels++;
                }
            }

            if (transitions_without_labels > diagram.transitions.size / 2) {
                add_suggestion("Many transitions lack labels",
                    "Add labels for clarity: State1 --> State2: event");
            }
        }

        public void lint_class(MermaidClassDiagram diagram) {
            messages.clear();

            // Suggest explicit visibility if all members in every class are PUBLIC
            // (likely means visibility symbols were omitted entirely)
            bool all_public = diagram.classes.size > 0;
            int total_members = 0;
            foreach (var cls in diagram.classes) {
                foreach (var member in cls.members) {
                    total_members++;
                    if (member.visibility != MermaidVisibility.PUBLIC) {
                        all_public = false;
                    }
                }
            }

            if (all_public && total_members > 3) {
                add_best_practice(
                    "All members use default public visibility",
                    "Use + (public), - (private), # (protected), or ~ (package) for clarity"
                );
            }

            // Suggest interfaces for abstract concepts
            bool has_interface = false;
            foreach (var cls in diagram.classes) {
                if (cls.class_type == MermaidClassType.INTERFACE) { has_interface = true; break; }
            }

            if (!has_interface && diagram.classes.size > 4) {
                add_suggestion("No interfaces defined — consider extracting contracts to interfaces",
                    "Example: class IRepository\\n    <<interface>>");
            }

            // Classes with too many members
            foreach (var cls in diagram.classes) {
                if (cls.members.size > 15) {
                    add_best_practice("Class '%s' has %d members — consider splitting".printf(
                        cls.name, cls.members.size), null);
                }
            }

            // No relations at all
            if (diagram.relations.size == 0 && diagram.classes.size > 1) {
                add_suggestion("No relationships defined between classes",
                    "Add inheritance (--|>), composition (*--), or association (-->)");
            }
        }

        public void lint_er(MermaidERDiagram diagram) {
            messages.clear();

            // Suggest relationship labels
            int unlabeled = 0;
            foreach (var rel in diagram.relationships) {
                if (rel.label == null || rel.label.length == 0) unlabeled++;
            }
            if (unlabeled > 0) {
                add_best_practice(
                    "%d relationship(s) have no verb label".printf(unlabeled),
                    "Example: CUSTOMER ||--o{ ORDER : places"
                );
            }

            // Suggest primary keys on all entities
            foreach (var entity in diagram.entities) {
                bool has_pk = false;
                foreach (var attr in entity.attributes) {
                    if (attr.is_primary_key) { has_pk = true; break; }
                }
                if (!has_pk && entity.attributes.size > 0) {
                    add_suggestion("Entity '%s' has no primary key".printf(entity.name),
                        "Mark a key attribute with PK: int id PK");
                }
            }

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("ER diagram has no title",
                    "Add a title for documentation purposes");
            }

            // Large diagrams
            if (diagram.entities.size > 15) {
                add_performance("Large ER diagram (%d entities)".printf(diagram.entities.size),
                    "Consider splitting into domain-specific sub-diagrams");
            }
        }

        public void lint_gantt(MermaidGantt diagram) {
            messages.clear();

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Gantt chart has no title",
                    "Add: title Project Name");
            }

            // Suggest milestones for key deliverables
            bool has_milestone = false;
            foreach (var task in diagram.tasks) {
                if (task.status == GanttTaskStatus.MILESTONE) { has_milestone = true; break; }
            }

            if (!has_milestone && diagram.tasks.size > 3) {
                add_suggestion("No milestones defined",
                    "Add key deliverables as milestones: Task : milestone, date, 1d");
            }

            // Unsectioned tasks
            if (diagram.sections.size == 0 && diagram.tasks.size > 5) {
                add_best_practice("Tasks are not organised into sections",
                    "Add sections to group related tasks: section Planning");
            }

            // Missing date format
            if (diagram.date_format == null || diagram.date_format.length == 0) {
                add_best_practice("No dateFormat specified",
                    "Add: dateFormat YYYY-MM-DD");
            }

            // Large diagram
            if (diagram.tasks.size > 30) {
                add_performance("Large Gantt chart (%d tasks)".printf(diagram.tasks.size),
                    "Consider splitting into phase-specific charts");
            }
        }

        public void lint_pie(MermaidPie diagram) {
            messages.clear();

            if (diagram.slices.size == 0) return;

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Pie chart has no title",
                    "Add: pie title Chart Title");
            }

            // Only one slice — not useful as a pie
            if (diagram.slices.size == 1) {
                add_suggestion("Single-slice pie chart conveys no comparison",
                    "Consider a different chart type or add more data points");
            }

            // Suggest ordering slices by value
            bool is_sorted = true;
            for (int i = 1; i < diagram.slices.size; i++) {
                if (diagram.slices.get(i).value > diagram.slices.get(i - 1).value) {
                    is_sorted = false;
                    break;
                }
            }
            if (!is_sorted && diagram.slices.size > 3) {
                add_style("Slices are not ordered by value",
                    "Sort slices from largest to smallest for readability");
            }

            // Very small slices are hard to read
            double total = diagram.get_total();
            if (total > 0) {
                foreach (var slice in diagram.slices) {
                    double pct = (slice.value / total) * 100.0;
                    if (pct < 2.0) {
                        add_suggestion(
                            "Slice '%s' is %.1f%% — very small slices are hard to read".printf(
                                slice.label, pct),
                            "Consider grouping small slices into an 'Other' category"
                        );
                    }
                }
            }
        }

        public void lint_git_graph(MermaidGitGraph diagram) {
            messages.clear();

            if (diagram.all_commits.size == 0) return;

            // Commits without meaningful IDs (auto-generated c0, c1, ...)
            int auto_id_count = 0;
            foreach (var c in diagram.all_commits) {
                if (c.id.length == 2 && c.id[0] == 'c' && c.id[1].isdigit()) {
                    auto_id_count++;
                }
            }
            if (auto_id_count > diagram.all_commits.size / 2) {
                add_suggestion(
                    "%d commit(s) use auto-generated IDs".printf(auto_id_count),
                    "Add meaningful IDs: commit id: \"Add login feature\""
                );
            }

            // No tags on any commit
            bool has_tags = false;
            foreach (var c in diagram.all_commits) {
                if (c.tag != null && c.tag.length > 0) { has_tags = true; break; }
            }
            if (!has_tags && diagram.all_commits.size > 3) {
                add_suggestion("No version tags defined",
                    "Tag release commits: commit id: \"Release\" tag: \"v1.0\"");
            }

            // Long branches (many commits without merging)
            foreach (var branch in diagram.branches) {
                if (branch.commits.size > 8) {
                    add_best_practice(
                        "Branch '%s' has %d commits without merging".printf(
                            branch.name, branch.commits.size),
                        "Consider merging feature branches more frequently"
                    );
                }
            }

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Git graph has no title",
                    "Add: gitGraph\\n    %%{init: {'logLevel': 'debug', 'title': 'My Repo'}}%%");
            }
        }

        public void lint_user_journey(MermaidUserJourney diagram) {
            messages.clear();

            if (diagram.all_tasks.size == 0) return;

            // Missing title
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("User journey has no title",
                    "Add: title My journey");
            }

            // Unsectioned tasks
            if (diagram.sections.size == 0 && diagram.all_tasks.size > 3) {
                add_best_practice("Tasks are not organised into sections",
                    "Group tasks: section Go to work");
            }

            // All tasks have the same score — no variation
            if (diagram.all_tasks.size > 2) {
                int first_score = diagram.all_tasks.get(0).score;
                bool all_same = true;
                foreach (var task in diagram.all_tasks) {
                    if (task.score != first_score) { all_same = false; break; }
                }
                if (all_same) {
                    add_style("All tasks have the same satisfaction score (%d)".printf(first_score),
                        "Vary scores to show the actual user experience across the journey");
                }
            }

            // Tasks without actors
            int no_actor_count = 0;
            foreach (var task in diagram.all_tasks) {
                if (task.actors.size == 0) no_actor_count++;
            }
            if (no_actor_count > 0) {
                add_suggestion(
                    "%d task(s) have no assigned actors".printf(no_actor_count),
                    "Assign actors to tasks: Task description: score: Actor1, Actor2"
                );
            }
        }

        // =====================================================================
        // Linters for the remaining 15 Mermaid diagram types.
        // Focus on best-practice and style suggestions, not errors
        // (errors belong in DiagramValidator).
        // =====================================================================

        public void lint_mindmap(MermaidMindmap diagram) {
            messages.clear();
            if (diagram.root == null) return;
            int nodes = 0;
            int max_depth = 0;
            mindmap_stats(diagram.root, 0, ref nodes, ref max_depth);
            if (nodes > 1 && max_depth == 0) {
                add_best_practice("Mindmap has siblings at root but no children — add nesting",
                    "Indent children under each top-level branch");
            }
            if (max_depth > 6) {
                add_style("Mindmap is %d levels deep — becomes hard to read past level 6".printf(max_depth),
                    "Consider splitting deep branches into separate mindmaps");
            }
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Mindmap has no title", "Add: title Subject");
            }
        }

        private void mindmap_stats(MindmapNode node, int depth, ref int count, ref int max_depth) {
            count++;
            if (depth > max_depth) max_depth = depth;
            foreach (var child in node.children) mindmap_stats(child, depth + 1, ref count, ref max_depth);
        }

        public void lint_timeline(MermaidTimeline diagram) {
            messages.clear();
            if (diagram.periods.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Timeline has no title", "Add: title My timeline");
            }
            // No sections across the timeline
            bool any_section = false;
            foreach (var p in diagram.periods) {
                if (p.section_name != null && p.section_name.length > 0) { any_section = true; break; }
            }
            if (!any_section && diagram.periods.size > 5) {
                add_best_practice("Timeline has %d periods and no sections".printf(diagram.periods.size),
                    "Group periods into sections for readability");
            }
            // Periods with a single event could become inline
            int single_event = 0;
            foreach (var p in diagram.periods) {
                if (p.events.size == 1) single_event++;
            }
            if (single_event > 3) {
                add_suggestion("%d periods have only one event each".printf(single_event),
                    "Multi-event periods make the timeline feel denser and more useful");
            }
        }

        public void lint_quadrant(MermaidQuadrant diagram) {
            messages.clear();
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Quadrant chart has no title", "Add: title Feature prioritization");
            }
            // Quadrants with no points
            int[] counts = {0, 0, 0, 0};
            foreach (var pt in diagram.points) {
                int qi;
                if (pt.x >= 0.5 && pt.y >= 0.5) qi = 0;       // Q1 top-right
                else if (pt.x < 0.5 && pt.y >= 0.5) qi = 1;  // Q2 top-left
                else if (pt.x < 0.5 && pt.y < 0.5) qi = 2;   // Q3 bottom-left
                else qi = 3;                                  // Q4 bottom-right
                counts[qi]++;
            }
            for (int i = 0; i < 4; i++) {
                if (counts[i] == 0 && diagram.points.size > 0) {
                    add_suggestion("Quadrant %d has no data points".printf(i + 1),
                        "Empty quadrants weaken the visual");
                }
            }
            if (diagram.points.size > 30) {
                add_performance("Quadrant has %d points — becomes cluttered past ~20".printf(
                    diagram.points.size), null);
            }
        }

        public void lint_xychart(MermaidXYChart diagram) {
            messages.clear();
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("XY chart has no title", "Add: title Monthly sales");
            }
            if (diagram.x_axis_label.length == 0) {
                add_style("XY chart is missing an x-axis label", "Add: x-axis \"Month\"");
            }
            if (diagram.y_axis_label.length == 0) {
                add_style("XY chart is missing a y-axis label", "Add: y-axis \"Revenue\"");
            }
            if (diagram.series.size > 6) {
                add_best_practice("XY chart has %d series — hard to distinguish".printf(diagram.series.size),
                    "Stick to ≤5 overlaid series for readability");
            }
        }

        public void lint_kanban(MermaidKanban diagram) {
            messages.clear();
            if (diagram.columns.size == 0) return;
            if (diagram.columns.size < 3) {
                add_suggestion("Kanban has only %d columns".printf(diagram.columns.size),
                    "Consider adding todo / in-progress / done at minimum");
            }
            int total_cards = 0;
            foreach (var col in diagram.columns) total_cards += col.cards.size;
            if (total_cards == 0) {
                add_suggestion("Kanban has no cards", "Add tasks: t1[Fix bug]");
            }
            // WIP warning
            foreach (var col in diagram.columns) {
                if (col.label.down().contains("progress") && col.cards.size > 5) {
                    add_best_practice("In-progress column '%s' has %d cards".printf(col.label, col.cards.size),
                        "Limit WIP to ~3 cards per person to avoid context-switching");
                }
            }
        }

        public void lint_sankey(MermaidSankey diagram) {
            messages.clear();
            if (diagram.links.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Sankey diagram has no title", "Add a title comment at the top");
            }
            // Flow conservation hint: nodes with inflow != outflow
            var inflow = new Gee.HashMap<string, double?>();
            var outflow = new Gee.HashMap<string, double?>();
            foreach (var link in diagram.links) {
                double cur_out = outflow.has_key(link.source) ? outflow.get(link.source) : 0.0;
                outflow.set(link.source, cur_out + link.value);
                double cur_in = inflow.has_key(link.target) ? inflow.get(link.target) : 0.0;
                inflow.set(link.target, cur_in + link.value);
            }
            int unbalanced = 0;
            foreach (var node in diagram.get_nodes()) {
                double ins = inflow.has_key(node) ? inflow.get(node) : 0.0;
                double outs = outflow.has_key(node) ? outflow.get(node) : 0.0;
                if (ins > 0 && outs > 0 && Math.fabs(ins - outs) / double.max(ins, outs) > 0.1) {
                    unbalanced++;
                }
            }
            if (unbalanced > 0) {
                add_suggestion("%d node(s) have noticeably unbalanced inflow vs outflow".printf(unbalanced),
                    "Sankey flows usually balance — check for missing links");
            }
        }

        public void lint_requirement(MermaidRequirement diagram) {
            messages.clear();
            if (diagram.elements.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Requirement diagram has no title", null);
            }
            // Requirements without verify method
            int no_verify = 0;
            foreach (var el in diagram.elements) {
                if (el.req_type.down() != "element" && el.verifymethod.length == 0) no_verify++;
            }
            if (no_verify > 0) {
                add_best_practice("%d requirement(s) have no verifymethod".printf(no_verify),
                    "Add: verifymethod: test (or inspection, demonstration, analysis)");
            }
            // Requirements with no risk
            int no_risk = 0;
            foreach (var el in diagram.elements) {
                if (el.req_type.down() != "element" && el.risk.length == 0) no_risk++;
            }
            if (no_risk > 0) {
                add_style("%d requirement(s) have no risk level".printf(no_risk),
                    "Add: risk: low / medium / high");
            }
        }

        public void lint_block(MermaidBlock diagram) {
            messages.clear();
            if (diagram.nodes.size == 0) return;
            if (diagram.columns == 0 && diagram.nodes.size > 3) {
                add_suggestion("Block diagram has no column layout hint",
                    "Add: columns 3 at the top for a grid layout");
            }
            if (diagram.edges.size == 0 && diagram.nodes.size > 2) {
                add_suggestion("Block diagram has nodes but no connections",
                    "Add arrows: a --> b");
            }
        }

        public void lint_packet(MermaidPacket diagram) {
            messages.clear();
            if (diagram.fields.size == 0) return;
            // Check bit coverage (are there gaps?)
            var sorted = new Gee.ArrayList<PacketField>();
            foreach (var f in diagram.fields) sorted.add(f);
            sorted.sort((a, b) => a.bit_start - b.bit_start);
            int expected = 0;
            int gaps = 0;
            foreach (var f in sorted) {
                if (f.bit_start > expected) gaps++;
                expected = f.bit_end + 1;
            }
            if (gaps > 0) {
                add_suggestion("Packet definition has %d bit-range gap(s)".printf(gaps),
                    "Define reserved fields explicitly so the layout is unambiguous");
            }
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Packet diagram has no title", "Add: title TCP header");
            }
        }

        public void lint_c4(MermaidC4 diagram) {
            messages.clear();
            if (diagram.elements.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("C4 diagram has no title", "Add: title System Context");
            }
            // Elements without descriptions
            int no_desc = 0;
            foreach (var el in diagram.elements) {
                if (el.description == null || el.description.length == 0) no_desc++;
            }
            if (no_desc > diagram.elements.size / 2) {
                add_best_practice("Most C4 elements have no description",
                    "Add a short 1-line description to each element — it's what C4 is for");
            }
            // No external systems in a context diagram
            if (diagram.c4_type == "Context") {
                bool has_external = false;
                foreach (var el in diagram.elements) {
                    if (el.is_external) { has_external = true; break; }
                }
                if (!has_external && diagram.elements.size > 2) {
                    add_suggestion("Context diagram has no external systems",
                        "A System Context usually shows at least one external dependency");
                }
            }
            // Dense C4
            if (diagram.elements.size > 20) {
                add_performance("C4 diagram has %d elements".printf(diagram.elements.size),
                    "C4 recommends ~7 elements per level — consider drilling down");
            }
        }

        public void lint_architecture(MermaidArchitecture diagram) {
            messages.clear();
            if (diagram.services.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Architecture diagram has no title", null);
            }
            // Services with unknown icon
            string[] known_icons = {
                "internet", "server", "database", "disk", "cloud", "junction"
            };
            foreach (var s in diagram.services) {
                bool found = false;
                foreach (var ki in known_icons) {
                    if (s.icon == ki) { found = true; break; }
                }
                if (!found && s.icon.length > 0) {
                    add_suggestion("Service '%s' uses unknown icon '%s'".printf(s.id, s.icon),
                        "Known icons: internet, server, database, disk, cloud, junction");
                }
            }
            if (diagram.edges.size == 0 && diagram.services.size > 2) {
                add_suggestion("Architecture has services but no connections",
                    "Add edges: svc1:R --> L:svc2");
            }
        }

        public void lint_zenuml(MermaidZenUML diagram) {
            messages.clear();
            if (diagram.messages.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("ZenUML diagram has no title", null);
            }
            if (diagram.participants.size == 0) {
                add_best_practice("ZenUML messages without explicit @Participant declarations",
                    "Declare participants with @Actor, @OrderService etc. for clearer diagrams");
            }
            if (diagram.messages.size > 30) {
                add_performance("Long sequence (%d messages)".printf(diagram.messages.size),
                    "Consider splitting into multiple sub-flows");
            }
        }

        public void lint_radar(MermaidRadar diagram) {
            messages.clear();
            if (diagram.axes.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Radar chart has no title", "Add: title Skills");
            }
            if (diagram.axes.size > 8) {
                add_best_practice("Radar chart with %d axes is cluttered".printf(diagram.axes.size),
                    "5–7 axes is the sweet spot for readability");
            }
            if (diagram.curves.size > 4) {
                add_performance("Radar chart with %d curves".printf(diagram.curves.size),
                    "Overlapping curves become hard to read past 3–4");
            }
        }

        public void lint_treemap(MermaidTreemap diagram) {
            messages.clear();
            if (diagram.roots.size == 0) return;
            if (diagram.title == null || diagram.title.length == 0) {
                add_style("Treemap has no title", null);
            }
            // Single-root vs multi-root
            if (diagram.roots.size > 1) {
                add_suggestion("Treemap has %d parallel roots".printf(diagram.roots.size),
                    "A single root usually tells a clearer story");
            }
            // Depth warning
            int max_depth = 0;
            foreach (var root in diagram.roots) {
                int d = treemap_depth(root);
                if (d > max_depth) max_depth = d;
            }
            if (max_depth > 4) {
                add_style("Treemap nests %d levels deep".printf(max_depth),
                    "Deep treemaps shrink leaves below legibility — cap at ~4 levels");
            }
        }

        private int treemap_depth(TreemapNode node) {
            if (node.children.size == 0) return 0;
            int best = 0;
            foreach (var c in node.children) {
                int d = treemap_depth(c);
                if (d > best) best = d;
            }
            return best + 1;
        }

        public string get_report() {
            if (messages.size == 0) {
                return "✅ No linting suggestions - diagram looks good!";
            }

            var sb = new StringBuilder();
            sb.append("📋 Linting Report:\n\n");

            int suggestions = 0, styles = 0, practices = 0, perf = 0;

            foreach (var msg in messages) {
                switch (msg.level) {
                    case LintMessage.Level.SUGGESTION:
                        suggestions++;
                        break;
                    case LintMessage.Level.STYLE:
                        styles++;
                        break;
                    case LintMessage.Level.BEST_PRACTICE:
                        practices++;
                        break;
                    case LintMessage.Level.PERFORMANCE:
                        perf++;
                        break;
                }
            }

            sb.append_printf("💡 %d suggestion(s)\n", suggestions);
            sb.append_printf("🎨 %d style improvement(s)\n", styles);
            sb.append_printf("✅ %d best practice(s)\n", practices);
            sb.append_printf("⚡ %d performance tip(s)\n", perf);
            sb.append("\nDetails:\n\n");

            foreach (var msg in messages) {
                string icon = "";
                switch (msg.level) {
                    case LintMessage.Level.SUGGESTION:
                        icon = "💡";
                        break;
                    case LintMessage.Level.STYLE:
                        icon = "🎨";
                        break;
                    case LintMessage.Level.BEST_PRACTICE:
                        icon = "✅";
                        break;
                    case LintMessage.Level.PERFORMANCE:
                        icon = "⚡";
                        break;
                }

                sb.append_printf("%s %s\n", icon, msg.message);
                if (msg.fix_suggestion != null) {
                    sb.append_printf("   Fix: %s\n", msg.fix_suggestion);
                }
                sb.append("\n");
            }

            return sb.str;
        }

        private void add_suggestion(string message, string? fix = null, int line = 0) {
            messages.add(new LintMessage(LintMessage.Level.SUGGESTION, message, fix, line));
        }

        private void add_style(string message, string? fix = null, int line = 0) {
            messages.add(new LintMessage(LintMessage.Level.STYLE, message, fix, line));
        }

        private void add_best_practice(string message, string? fix = null, int line = 0) {
            messages.add(new LintMessage(LintMessage.Level.BEST_PRACTICE, message, fix, line));
        }

        private void add_performance(string message, string? fix = null, int line = 0) {
            messages.add(new LintMessage(LintMessage.Level.PERFORMANCE, message, fix, line));
        }
    }
}
