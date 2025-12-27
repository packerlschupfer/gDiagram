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
