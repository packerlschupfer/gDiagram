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
