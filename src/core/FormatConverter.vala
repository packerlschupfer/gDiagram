namespace GDiagram {
    public class FormatConverter : Object {
        // Convert PlantUML sequence diagram to Mermaid
        public static string? sequence_plantuml_to_mermaid(string plantuml_source) {
            var output = new StringBuilder();
            output.append("sequenceDiagram\n");

            string[] lines = plantuml_source.split("\n");
            bool in_diagram = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                // Skip PlantUML markers
                if (trimmed == "@startuml" || trimmed == "@enduml") {
                    in_diagram = trimmed == "@startuml";
                    continue;
                }

                if (!in_diagram && trimmed.length > 0) {
                    in_diagram = true; // Start if we see content
                }

                if (!in_diagram) continue;

                // Convert participant
                if (trimmed.has_prefix("participant ")) {
                    output.append("    ");
                    output.append(trimmed);
                    output.append("\n");
                    continue;
                }

                // Convert actor
                if (trimmed.has_prefix("actor ")) {
                    output.append("    ");
                    output.append(trimmed);
                    output.append("\n");
                    continue;
                }

                // Convert messages: -> to ->>
                if (trimmed.contains("->") || trimmed.contains("-->")) {
                    string converted = trimmed.replace("->", "->>");
                    converted = converted.replace("-->>", "-->>");
                    output.append("    ");
                    output.append(converted);
                    output.append("\n");
                    continue;
                }

                // Convert note
                if (trimmed.has_prefix("note ")) {
                    // Simple note conversion
                    string note_line = trimmed.replace("note ", "Note ");
                    output.append("    ");
                    output.append(note_line);
                    output.append("\n");
                    continue;
                }

                // Title
                if (trimmed.has_prefix("title ")) {
                    output.append("    ");
                    output.append(trimmed);
                    output.append("\n");
                    continue;
                }
            }

            return output.str;
        }

        // Convert Mermaid sequence to PlantUML
        public static string? sequence_mermaid_to_plantuml(string mermaid_source) {
            var output = new StringBuilder();
            output.append("@startuml\n");

            string[] lines = mermaid_source.split("\n");
            bool in_diagram = false;

            foreach (string line in lines) {
                string trimmed = line.strip();

                // Skip Mermaid header
                if (trimmed == "sequenceDiagram") {
                    in_diagram = true;
                    continue;
                }

                if (!in_diagram && trimmed.length > 0) {
                    in_diagram = true;
                }

                if (!in_diagram) continue;

                // Convert messages: ->> to ->
                if (trimmed.contains("->>") || trimmed.contains("-->>")) {
                    string converted = trimmed.replace("->>", "->");
                    converted = converted.replace("-->>", "-->");
                    output.append(converted);
                    output.append("\n");
                    continue;
                }

                // Convert Note to note
                if (trimmed.has_prefix("Note ")) {
                    string note_line = trimmed.replace("Note ", "note ");
                    output.append(note_line);
                    output.append("\n");
                    continue;
                }

                // Pass through: participant, actor, title
                if (trimmed.has_prefix("participant ") || trimmed.has_prefix("actor ") ||
                    trimmed.has_prefix("title ")) {
                    output.append(trimmed);
                    output.append("\n");
                    continue;
                }
            }

            output.append("@enduml\n");
            return output.str;
        }

        // Convert PlantUML class diagram to Mermaid (basic)
        public static string? class_plantuml_to_mermaid(string plantuml_source) {
            var output = new StringBuilder();
            output.append("classDiagram\n");

            string[] lines = plantuml_source.split("\n");
            bool in_class = false;
            string current_class = "";

            foreach (string line in lines) {
                string trimmed = line.strip();

                if (trimmed == "@startuml" || trimmed == "@enduml") {
                    continue;
                }

                // Class declaration
                if (trimmed.has_prefix("class ")) {
                    in_class = true;
                    output.append("    ");
                    output.append(trimmed);
                    output.append("\n");

                    // Extract class name
                    string[] parts = trimmed.split(" ");
                    if (parts.length > 1) {
                        current_class = parts[1].replace("{", "").strip();
                    }
                    continue;
                }

                // Class body
                if (in_class && trimmed.length > 0 && !trimmed.has_prefix("}")) {
                    output.append("        ");
                    output.append(trimmed);
                    output.append("\n");
                    continue;
                }

                // End class
                if (trimmed == "}") {
                    output.append("    ");
                    output.append(trimmed);
                    output.append("\n");
                    in_class = false;
                    continue;
                }

                // Relationships
                if (trimmed.contains("<|--") || trimmed.contains("-->") ||
                    trimmed.contains("*--") || trimmed.contains("o--")) {
                    output.append("    ");
                    output.append(trimmed);
                    output.append("\n");
                    continue;
                }
            }

            return output.str;
        }

        // Detect if conversion is possible
        public static bool can_convert(string source, string from_format, string to_format) {
            if (from_format == "plantuml" && to_format == "mermaid") {
                // Check if it's a sequence or class diagram
                return source.contains("participant") || source.contains("actor") ||
                       source.contains("class");
            }

            if (from_format == "mermaid" && to_format == "plantuml") {
                return source.contains("sequenceDiagram") || source.contains("classDiagram");
            }

            return false;
        }

        // Auto-detect and convert
        public static string? auto_convert(string source, string target_format) {
            string lower = source.down();

            // Detect source format
            if (lower.contains("@startuml")) {
                // PlantUML source
                if (target_format == "mermaid") {
                    if (lower.contains("participant") || lower.contains("actor")) {
                        return sequence_plantuml_to_mermaid(source);
                    }
                    if (lower.contains("class")) {
                        return class_plantuml_to_mermaid(source);
                    }
                }
            } else if (lower.contains("sequencediagram")) {
                if (target_format == "plantuml") {
                    return sequence_mermaid_to_plantuml(source);
                }
            } else if (lower.contains("classdiagram")) {
                // Mermaid class to PlantUML not implemented yet
                return null;
            }

            return null;
        }
    }
}
