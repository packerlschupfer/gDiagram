namespace GDiagram {
    public class OptimizationSuggestion : Object {
        public string title { get; set; }
        public string description { get; set; }
        public string? before { get; set; }
        public string? after { get; set; }
        public int impact_score { get; set; default = 5; }  // 1-10

        public OptimizationSuggestion(string title, string description, int impact = 5) {
            this.title = title;
            this.description = description;
            this.impact_score = impact;
        }
    }

    public class DiagramOptimizer : Object {
        public Gee.ArrayList<OptimizationSuggestion> suggestions { get; private set; }

        public DiagramOptimizer() {
            suggestions = new Gee.ArrayList<OptimizationSuggestion>();
        }

        public void analyze_flowchart(MermaidFlowchart diagram) {
            suggestions.clear();

            // Suggest direction based on aspect ratio
            int horizontal_edges = 0;
            int vertical_edges = 0;

            // Heuristic: count logical flow
            foreach (var edge in diagram.edges) {
                // This is simplified - real implementation would analyze node positions
                horizontal_edges++;
            }

            if (diagram.nodes.size > 10) {
                var suggestion = new OptimizationSuggestion(
                    "Layout Direction",
                    "Consider using LR (left-right) for wide workflows or TB (top-bottom) for deep hierarchies",
                    6
                );
                suggestion.before = "flowchart TD";
                suggestion.after = "flowchart LR  (or TB, RL, BT)";
                suggestions.add(suggestion);
            }

            // Suggest subgraph grouping
            if (diagram.nodes.size > 20 && diagram.subgraphs.size == 0) {
                var suggestion = new OptimizationSuggestion(
                    "Use Subgraphs",
                    "Group related nodes into subgraphs for better organization",
                    8
                );
                suggestion.after = "subgraph GroupName\\n    Node1\\n    Node2\\nend";
                suggestions.add(suggestion);
            }

            // Suggest color coding
            int colored_nodes = 0;
            foreach (var node in diagram.nodes) {
                if (node.fill_color != null) {
                    colored_nodes++;
                }
            }

            if (diagram.nodes.size > 8 && colored_nodes < 3) {
                var suggestion = new OptimizationSuggestion(
                    "Add Color Coding",
                    "Use colors to distinguish different types of nodes (start, process, decision, end)",
                    7
                );
                suggestion.after = "classDef successStyle fill:#90EE90\\nclass Success successStyle";
                suggestions.add(suggestion);
            }

            // Suggest edge labels for clarity
            int labeled_edges = 0;
            foreach (var edge in diagram.edges) {
                if (edge.label != null && edge.label.length > 0) {
                    labeled_edges++;
                }
            }

            if (diagram.edges.size > 5 && labeled_edges < diagram.edges.size / 3) {
                var suggestion = new OptimizationSuggestion(
                    "Add Edge Labels",
                    "Label edges to clarify the flow, especially for decision branches",
                    6
                );
                suggestion.after = "Decision -->|Yes| Process";
                suggestions.add(suggestion);
            }

            // Detect linear chains that could be simplified
            int chain_length = 0;
            foreach (var edge in diagram.edges) {
                // Simplified detection
                if (edge.label == null) {
                    chain_length++;
                }
            }

            if (chain_length > 5) {
                var suggestion = new OptimizationSuggestion(
                    "Simplify Linear Chains",
                    "Long linear sequences could be combined or grouped",
                    5
                );
                suggestions.add(suggestion);
            }
        }

        public void sort_by_impact() {
            // Sort suggestions by impact score (highest first)
            suggestions.sort((a, b) => {
                return b.impact_score - a.impact_score;
            });
        }

        public string get_report() {
            if (suggestions.size == 0) {
                return "✅ Diagram is well-optimized!";
            }

            sort_by_impact();

            var sb = new StringBuilder();
            sb.append("🔧 Optimization Suggestions:\n\n");
            sb.append_printf("Found %d optimization(s) (sorted by impact):\n\n", suggestions.size);

            int num = 1;
            foreach (var suggestion in suggestions) {
                sb.append_printf("%d. %s (Impact: %d/10)\n", num, suggestion.title, suggestion.impact_score);
                sb.append_printf("   %s\n", suggestion.description);

                if (suggestion.before != null) {
                    sb.append_printf("   Before: %s\n", suggestion.before);
                }
                if (suggestion.after != null) {
                    sb.append_printf("   After: %s\n", suggestion.after);
                }
                sb.append("\n");
                num++;
            }

            return sb.str;
        }

        // Get recommended layout engine based on diagram structure
        public static string recommend_layout(int nodes, int edges, int branch_points) {
            if (nodes < 10) {
                return "dot (hierarchical - best for simple flows)";
            }

            double density = nodes > 0 ? (double)edges / nodes : 0;

            if (density > 3.0) {
                return "fdp (force-directed - good for dense graphs)";
            }

            if (nodes > 50) {
                return "sfdp (scalable force-directed - handles large graphs)";
            }

            if (branch_points == 0 && edges > nodes) {
                return "neato (spring model - good for networks)";
            }

            if (nodes > 20 && branch_points > 5) {
                return "dot (hierarchical - clear for complex flows)";
            }

            return "dot (hierarchical - safe default)";
        }
    }
}
