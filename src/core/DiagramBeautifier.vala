namespace GDiagram {
    public class DiagramBeautifier : Object {
        private static string[] SUCCESS_COLORS = {"#90EE90", "#98FB98", "#8FBC8F"};
        private static string[] ERROR_COLORS = {"#FFB6C1", "#FFA07A", "#FF6B6B"};
        private static string[] PROCESS_COLORS = {"#87CEEB", "#4ECDC4", "#45B7D1"};
        private static string[] DECISION_COLORS = {"#FFD700", "#F7DC6F", "#F4D03F"};
        private static string[] START_END_COLORS = {"#98D8C8", "#7DCEA0", "#82E0AA"};

        // Auto-beautify flowchart by analyzing node semantics
        public static string beautify_flowchart(string source) {
            var output = new StringBuilder();
            string[] lines = source.split("\n");

            var style_lines = new Gee.ArrayList<string>();
            bool has_classdef = false;

            // First pass: collect nodes and determine types
            var node_types = new Gee.HashMap<string, string>();

            foreach (string line in lines) {
                string trimmed = line.strip();

                // Detect node declarations
                if (trimmed.contains("[") && trimmed.contains("]") && !trimmed.has_prefix("style")) {
                    // Extract node ID and text
                    int id_end = trimmed.index_of("[");
                    if (id_end > 0) {
                        string node_id = trimmed.substring(0, id_end).strip();
                        string node_text = "";

                        int text_start = trimmed.index_of("[");
                        int text_end = trimmed.index_of("]");
                        if (text_start >= 0 && text_end > text_start) {
                            node_text = trimmed.substring(text_start + 1, text_end - text_start - 1).down();
                        }

                        // Classify node by text content
                        if (node_text.contains("start") || node_text.contains("begin")) {
                            node_types.set(node_id, "start");
                        } else if (node_text.contains("end") || node_text.contains("finish") || node_text.contains("done")) {
                            node_types.set(node_id, "end");
                        } else if (node_text.contains("error") || node_text.contains("fail") || node_text.contains("invalid")) {
                            node_types.set(node_id, "error");
                        } else if (node_text.contains("success") || node_text.contains("complete") || node_text.contains("ok")) {
                            node_types.set(node_id, "success");
                        }
                    }
                }

                // Detect decision nodes (diamond shape)
                if (trimmed.contains("{") && trimmed.contains("}")) {
                    int id_end = trimmed.index_of("{");
                    if (id_end > 0) {
                        string node_id = trimmed.substring(0, id_end).strip();
                        node_types.set(node_id, "decision");
                    }
                }

                output.append(line);
                output.append("\n");
            }

            // Second pass: add classDef if not present
            if (!source.contains("classDef") && node_types.size > 0) {
                output.append("\n    %% Auto-generated style classes\n");
                output.append("    classDef startStyle fill:#98D8C8,stroke:#27AE60,stroke-width:2\n");
                output.append("    classDef endStyle fill:#7DCEA0,stroke:#27AE60,stroke-width:2\n");
                output.append("    classDef successStyle fill:#90EE90,stroke:#228B22,stroke-width:2\n");
                output.append("    classDef errorStyle fill:#FFB6C1,stroke:#DC143C,stroke-width:2\n");
                output.append("    classDef decisionStyle fill:#FFD700,stroke:#DAA520,stroke-width:2\n");
                output.append("\n    %% Apply styles\n");

                // Apply styles based on node types
                foreach (var entry in node_types.entries) {
                    string node_id = entry.key;
                    string node_type = entry.value;

                    switch (node_type) {
                        case "start":
                            output.append_printf("    class %s startStyle\n", node_id);
                            break;
                        case "end":
                            output.append_printf("    class %s endStyle\n", node_id);
                            break;
                        case "success":
                            output.append_printf("    class %s successStyle\n", node_id);
                            break;
                        case "error":
                            output.append_printf("    class %s errorStyle\n", node_id);
                            break;
                        case "decision":
                            output.append_printf("    class %s decisionStyle\n", node_id);
                            break;
                    }
                }
            }

            return output.str;
        }

        // Add consistent spacing and formatting
        public static string format_source(string source) {
            var output = new StringBuilder();
            string[] lines = source.split("\n");

            bool in_subgraph = false;
            int indent_level = 0;

            foreach (string line in lines) {
                string trimmed = line.strip();

                // Skip empty lines at start
                if (trimmed.length == 0 && output.len == 0) {
                    continue;
                }

                // Adjust indent for subgraph
                if (trimmed.has_prefix("subgraph")) {
                    in_subgraph = true;
                    indent_level = 1;
                } else if (trimmed == "end" && in_subgraph) {
                    in_subgraph = false;
                    indent_level = 0;
                }

                // Add proper indentation
                if (trimmed.length > 0) {
                    for (int i = 0; i < indent_level * 4; i++) {
                        output.append(" ");
                    }
                    output.append(trimmed);
                    output.append("\n");
                }
            }

            return output.str;
        }

        // Suggest improvements
        public static string[] get_beautification_suggestions(string source) {
            var suggestions = new Gee.ArrayList<string>();
            string lower = source.down();

            if (!lower.contains("style") && !lower.contains("classdef")) {
                suggestions.add("Add color styling for better visual distinction");
            }

            if (lower.contains("{") && !lower.contains("classdef")) {
                suggestions.add("Color-code decision nodes for clarity");
            }

            if (source.split("\n").length > 20 && !lower.contains("subgraph")) {
                suggestions.add("Group related nodes into subgraphs");
            }

            int edge_count = 0;
            foreach (string line in source.split("\n")) {
                if (line.contains("-->")) edge_count++;
            }

            int labeled_edges = 0;
            foreach (string line in source.split("\n")) {
                if (line.contains("-->|") || line.contains("|")) labeled_edges++;
            }

            if (edge_count > 5 && labeled_edges < edge_count / 2) {
                suggestions.add("Add labels to edges for better clarity");
            }

            if (suggestions.size == 0) {
                suggestions.add("Diagram styling looks good!");
            }

            return suggestions.to_array();
        }
    }
}
