namespace GDiagram {
    public class DiagramStats : Object {
        public int node_count { get; set; default = 0; }
        public int edge_count { get; set; default = 0; }
        public int line_count { get; set; default = 0; }
        public int char_count { get; set; default = 0; }
        public string diagram_type { get; set; default = "Unknown"; }

        public DiagramStats() {
        }

        public void analyze_mermaid_flowchart(MermaidFlowchart diagram, string source) {
            node_count = diagram.nodes.size;
            edge_count = diagram.edges.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Flowchart";
        }

        public void analyze_mermaid_sequence(MermaidSequenceDiagram diagram, string source) {
            node_count = diagram.actors.size;
            edge_count = diagram.messages.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Sequence";
        }

        public void analyze_mermaid_state(MermaidStateDiagram diagram, string source) {
            node_count = diagram.states.size;
            edge_count = diagram.transitions.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid State";
        }

        public void analyze_mermaid_class(MermaidClassDiagram diagram, string source) {
            node_count = diagram.classes.size;
            edge_count = diagram.relations.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Class";
        }

        public void analyze_mermaid_er(MermaidERDiagram diagram, string source) {
            node_count = diagram.entities.size;
            edge_count = diagram.relationships.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid ER";
        }

        public void analyze_mermaid_gantt(MermaidGantt diagram, string source) {
            node_count = diagram.tasks.size;
            edge_count = diagram.sections.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Gantt";
        }

        public void analyze_mermaid_pie(MermaidPie diagram, string source) {
            node_count = diagram.slices.size;
            edge_count = 0;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Pie";
        }

        public string get_summary() {
            var sb = new StringBuilder();
            sb.append_printf("📊 %s Statistics:\n\n", diagram_type);

            if (diagram_type.contains("Flowchart") || diagram_type.contains("State") ||
                diagram_type.contains("Class") || diagram_type.contains("ER")) {
                sb.append_printf("  Nodes: %d\n", node_count);
                sb.append_printf("  Edges: %d\n", edge_count);
            } else if (diagram_type.contains("Sequence")) {
                sb.append_printf("  Actors: %d\n", node_count);
                sb.append_printf("  Messages: %d\n", edge_count);
            } else if (diagram_type.contains("Gantt")) {
                sb.append_printf("  Tasks: %d\n", node_count);
                sb.append_printf("  Sections: %d\n", edge_count);
            } else if (diagram_type.contains("Pie")) {
                sb.append_printf("  Slices: %d\n", node_count);
            }

            sb.append_printf("  Lines: %d\n", line_count);
            sb.append_printf("  Characters: %d\n", char_count);

            // Complexity assessment
            sb.append("\n");
            string complexity = get_complexity();
            sb.append_printf("Complexity: %s\n", complexity);

            return sb.str;
        }

        public string get_complexity() {
            int total_elements = node_count + edge_count;

            if (total_elements < 5) {
                return "🟢 Simple";
            } else if (total_elements < 15) {
                return "🟡 Moderate";
            } else if (total_elements < 30) {
                return "🟠 Complex";
            } else {
                return "🔴 Very Complex";
            }
        }

        public string get_quick_stats() {
            if (diagram_type.contains("Flowchart") || diagram_type.contains("State") ||
                diagram_type.contains("Class") || diagram_type.contains("ER")) {
                return "%d nodes, %d edges".printf(node_count, edge_count);
            } else if (diagram_type.contains("Sequence")) {
                return "%d actors, %d messages".printf(node_count, edge_count);
            } else if (diagram_type.contains("Gantt")) {
                return "%d tasks, %d sections".printf(node_count, edge_count);
            } else if (diagram_type.contains("Pie")) {
                return "%d slices".printf(node_count);
            }
            return "Unknown";
        }
    }
}
