namespace GDiagram {
    public class ComplexityMetrics : Object {
        public int nodes { get; set; default = 0; }
        public int edges { get; set; default = 0; }
        public int max_depth { get; set; default = 0; }
        public int branch_points { get; set; default = 0; }
        public double avg_connections { get; set; default = 0.0; }
        public int disconnected_components { get; set; default = 0; }

        public string get_rating() {
            int score = 0;

            // Node count scoring
            if (nodes > 50) score += 3;
            else if (nodes > 30) score += 2;
            else if (nodes > 15) score += 1;

            // Edge density
            if (nodes > 0) {
                double density = (double)edges / nodes;
                if (density > 3.0) score += 2;
                else if (density > 2.0) score += 1;
            }

            // Branch points (decision nodes)
            if (branch_points > 10) score += 2;
            else if (branch_points > 5) score += 1;

            // Depth
            if (max_depth > 8) score += 2;
            else if (max_depth > 5) score += 1;

            if (score >= 8) {
                return "🔴 Very Complex - Consider refactoring";
            } else if (score >= 5) {
                return "🟠 Complex - Review for simplification";
            } else if (score >= 3) {
                return "🟡 Moderate - Acceptable complexity";
            } else {
                return "🟢 Simple - Easy to understand";
            }
        }

        public string get_summary() {
            var sb = new StringBuilder();
            sb.append("📈 Complexity Analysis:\n\n");
            sb.append_printf("  Nodes: %d\n", nodes);
            sb.append_printf("  Edges: %d\n", edges);
            sb.append_printf("  Branch Points: %d\n", branch_points);
            sb.append_printf("  Max Depth: %d\n", max_depth);
            sb.append_printf("  Avg Connections: %.1f\n", avg_connections);
            sb.append_printf("  Disconnected: %d\n", disconnected_components);
            sb.append_printf("\n  Rating: %s\n", get_rating());

            return sb.str;
        }
    }

    public class ComplexityAnalyzer : Object {
        public ComplexityMetrics analyze_flowchart(MermaidFlowchart diagram) {
            var metrics = new ComplexityMetrics();
            metrics.nodes = diagram.nodes.size;
            metrics.edges = diagram.edges.size;

            // Count branch points (diamond/rhombus nodes)
            foreach (var node in diagram.nodes) {
                if (node.shape == FlowchartNodeShape.RHOMBUS) {
                    metrics.branch_points++;
                }
            }

            // Calculate average connections
            if (metrics.nodes > 0) {
                metrics.avg_connections = (double)metrics.edges / metrics.nodes;
            }

            // Calculate max depth (simplified BFS)
            metrics.max_depth = calculate_max_depth_flowchart(diagram);

            // Detect disconnected components
            metrics.disconnected_components = count_disconnected_components_flowchart(diagram);

            return metrics;
        }

        public ComplexityMetrics analyze_sequence(MermaidSequenceDiagram diagram) {
            var metrics = new ComplexityMetrics();
            metrics.nodes = diagram.actors.size;
            metrics.edges = diagram.messages.size;
            metrics.branch_points = diagram.loops.size; // Control structures

            if (metrics.nodes > 0) {
                metrics.avg_connections = (double)metrics.edges / metrics.nodes;
            }

            // Depth is message count
            metrics.max_depth = metrics.edges;

            return metrics;
        }

        public ComplexityMetrics analyze_state(MermaidStateDiagram diagram) {
            var metrics = new ComplexityMetrics();
            metrics.nodes = diagram.states.size;
            metrics.edges = diagram.transitions.size;

            // Count choice/fork/join points
            foreach (var state in diagram.states) {
                if (state.state_type == MermaidStateType.CHOICE ||
                    state.state_type == MermaidStateType.FORK ||
                    state.state_type == MermaidStateType.JOIN) {
                    metrics.branch_points++;
                }
            }

            if (metrics.nodes > 0) {
                metrics.avg_connections = (double)metrics.edges / metrics.nodes;
            }

            metrics.max_depth = calculate_max_depth_state(diagram);

            return metrics;
        }

        private int calculate_max_depth_flowchart(MermaidFlowchart diagram) {
            // Simplified depth calculation
            // In a full implementation, would do proper graph traversal
            int max_depth = 0;

            if (diagram.nodes.size > 0) {
                max_depth = (int)(Math.log(diagram.nodes.size) / Math.log(2)) + 1;
            }

            return max_depth;
        }

        private int calculate_max_depth_state(MermaidStateDiagram diagram) {
            // Simplified - just estimate based on transitions
            if (diagram.states.size == 0) return 0;

            return (int)(Math.log(diagram.transitions.size + 1) / Math.log(2)) + 1;
        }

        private int count_disconnected_components_flowchart(MermaidFlowchart diagram) {
            if (diagram.nodes.size == 0) return 0;
            if (diagram.edges.size == 0) return diagram.nodes.size;

            // Simplified - just check if any nodes have no connections
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

            return disconnected > 0 ? disconnected : 1;
        }

        // Get optimization suggestions
        public static string[] get_suggestions(ComplexityMetrics metrics) {
            var suggestions = new Gee.ArrayList<string>();

            if (metrics.nodes > 30) {
                suggestions.add("Consider splitting into multiple smaller diagrams");
            }

            if (metrics.avg_connections > 3.0) {
                suggestions.add("High connection density - diagram may be cluttered");
            }

            if (metrics.branch_points > 8) {
                suggestions.add("Many decision points - consider simplifying logic");
            }

            if (metrics.max_depth > 8) {
                suggestions.add("Deep nesting - consider flattening the hierarchy");
            }

            if (metrics.disconnected_components > 1) {
                suggestions.add("Diagram has %d disconnected parts".printf(metrics.disconnected_components));
            }

            if (suggestions.size == 0) {
                suggestions.add("Diagram complexity is reasonable - no suggestions");
            }

            return suggestions.to_array();
        }

        // Recommend best layout engine
        public static string recommend_layout_engine(ComplexityMetrics metrics) {
            if (metrics.nodes < 10) {
                return "dot"; // Simple hierarchical
            }

            if (metrics.avg_connections > 3.0) {
                return "fdp"; // Force-directed for dense graphs
            }

            if (metrics.nodes > 50) {
                return "sfdp"; // Scalable force-directed
            }

            if (metrics.branch_points == 0 && metrics.edges > metrics.nodes) {
                return "neato"; // Spring model for networks
            }

            return "dot"; // Default
        }
    }
}
