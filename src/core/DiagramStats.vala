namespace GDiagram {
    public class DiagramStats : Object {
        public int node_count { get; set; default = 0; }
        public int edge_count { get; set; default = 0; }
        public int line_count { get; set; default = 0; }
        public int char_count { get; set; default = 0; }
        public string diagram_type { get; set; default = "Unknown"; }

        public DiagramStats() {
        }

        // =====================================================================
        // Mermaid analyze methods
        // =====================================================================

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

        public void analyze_mermaid_user_journey(MermaidUserJourney diagram, string source) {
            node_count = diagram.all_tasks.size;
            edge_count = diagram.sections.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid User Journey";
        }

        public void analyze_mermaid_git_graph(MermaidGitGraph diagram, string source) {
            node_count = diagram.all_commits.size;
            edge_count = diagram.branches.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Git Graph";
        }

        public void analyze_mermaid_mindmap(MermaidMindmap diagram, string source) {
            node_count = count_mindmap_nodes(diagram.root);
            edge_count = node_count > 0 ? node_count - 1 : 0;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Mindmap";
        }

        public void analyze_mermaid_timeline(MermaidTimeline diagram, string source) {
            node_count = diagram.periods.size;
            int event_total = 0;
            foreach (var period in diagram.periods) {
                event_total += period.events.size;
            }
            edge_count = event_total;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Timeline";
        }

        public void analyze_mermaid_quadrant(MermaidQuadrant diagram, string source) {
            node_count = diagram.points.size;
            edge_count = 0;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Quadrant Chart";
        }

        public void analyze_mermaid_xychart(MermaidXYChart diagram, string source) {
            int total_values = 0;
            foreach (var s in diagram.series) {
                total_values += s.values.size;
            }
            node_count = total_values;
            edge_count = diagram.series.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid XY Chart";
        }

        public void analyze_mermaid_kanban(MermaidKanban diagram, string source) {
            int total_cards = 0;
            foreach (var col in diagram.columns) {
                total_cards += col.cards.size;
            }
            node_count = total_cards;
            edge_count = diagram.columns.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Kanban";
        }

        public void analyze_mermaid_sankey(MermaidSankey diagram, string source) {
            node_count = diagram.get_nodes().size;
            edge_count = diagram.links.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Sankey";
        }

        public void analyze_mermaid_requirement(MermaidRequirement diagram, string source) {
            node_count = diagram.elements.size;
            edge_count = diagram.relationships.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Requirement";
        }

        public void analyze_mermaid_block(MermaidBlock diagram, string source) {
            node_count = diagram.nodes.size;
            edge_count = diagram.edges.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Block";
        }

        public void analyze_mermaid_packet(MermaidPacket diagram, string source) {
            node_count = diagram.fields.size;
            edge_count = 0;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Packet";
        }

        public void analyze_mermaid_c4(MermaidC4 diagram, string source) {
            node_count = diagram.elements.size;
            edge_count = diagram.relationships.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid C4";
        }

        public void analyze_mermaid_architecture(MermaidArchitecture diagram, string source) {
            node_count = diagram.services.size;
            edge_count = diagram.edges.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Architecture";
        }

        public void analyze_mermaid_zenuml(MermaidZenUML diagram, string source) {
            node_count = diagram.participants.size;
            edge_count = diagram.messages.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid ZenUML";
        }

        public void analyze_mermaid_radar(MermaidRadar diagram, string source) {
            node_count = diagram.axes.size;
            edge_count = diagram.curves.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Radar";
        }

        public void analyze_mermaid_treemap(MermaidTreemap diagram, string source) {
            int total = 0;
            foreach (var root in diagram.roots) {
                total += count_treemap_nodes(root);
            }
            node_count = total;
            edge_count = diagram.roots.size;
            line_count = source.split("\n").length;
            char_count = source.length;
            diagram_type = "Mermaid Treemap";
        }

        // =====================================================================
        // Node counting helpers
        // =====================================================================

        private int count_mindmap_nodes(MindmapNode? node) {
            if (node == null) return 0;
            int count = 1;
            foreach (var child in node.children) {
                count += count_mindmap_nodes(child);
            }
            return count;
        }

        private int count_treemap_nodes(TreemapNode node) {
            int count = 1;
            foreach (var child in node.children) {
                count += count_treemap_nodes(child);
            }
            return count;
        }

        // =====================================================================
        // Reporting
        // =====================================================================

        public string get_quick_stats() {
            switch (diagram_type) {
                case "Mermaid Flowchart":    return "%d nodes, %d edges".printf(node_count, edge_count);
                case "Mermaid Sequence":     return "%d actors, %d messages".printf(node_count, edge_count);
                case "Mermaid State":        return "%d states, %d transitions".printf(node_count, edge_count);
                case "Mermaid Class":        return "%d classes, %d relations".printf(node_count, edge_count);
                case "Mermaid ER":           return "%d entities, %d relationships".printf(node_count, edge_count);
                case "Mermaid Gantt":        return "%d tasks, %d sections".printf(node_count, edge_count);
                case "Mermaid Pie":          return "%d slices".printf(node_count);
                case "Mermaid User Journey": return "%d tasks, %d sections".printf(node_count, edge_count);
                case "Mermaid Git Graph":    return "%d commits, %d branches".printf(node_count, edge_count);
                case "Mermaid Mindmap":      return "%d nodes".printf(node_count);
                case "Mermaid Timeline":     return "%d periods, %d events".printf(node_count, edge_count);
                case "Mermaid Quadrant Chart": return "%d points".printf(node_count);
                case "Mermaid XY Chart":     return "%d series, %d values".printf(edge_count, node_count);
                case "Mermaid Kanban":       return "%d cards, %d columns".printf(node_count, edge_count);
                case "Mermaid Sankey":       return "%d nodes, %d links".printf(node_count, edge_count);
                case "Mermaid Requirement":  return "%d elements, %d relationships".printf(node_count, edge_count);
                case "Mermaid Block":        return "%d blocks, %d edges".printf(node_count, edge_count);
                case "Mermaid Packet":       return "%d fields".printf(node_count);
                case "Mermaid C4":           return "%d elements, %d relationships".printf(node_count, edge_count);
                case "Mermaid Architecture": return "%d services, %d edges".printf(node_count, edge_count);
                case "Mermaid ZenUML":       return "%d participants, %d messages".printf(node_count, edge_count);
                case "Mermaid Radar":        return "%d axes, %d curves".printf(node_count, edge_count);
                case "Mermaid Treemap":      return "%d nodes".printf(node_count);
                default:                    return "%d elements".printf(node_count + edge_count);
            }
        }

        public string get_summary() {
            var sb = new StringBuilder();
            sb.append_printf("📊 %s Statistics:\n\n", diagram_type);
            sb.append_printf("  %s\n", get_quick_stats());
            sb.append_printf("  Lines: %d\n", line_count);
            sb.append_printf("  Characters: %d\n", char_count);
            sb.append("\n");
            sb.append_printf("Complexity: %s\n", get_complexity());
            return sb.str;
        }

        public string get_complexity() {
            int total_elements = node_count + edge_count;
            if (total_elements < 5)  return "🟢 Simple";
            if (total_elements < 15) return "🟡 Moderate";
            if (total_elements < 30) return "🟠 Complex";
            return "🔴 Very Complex";
        }
    }
}
