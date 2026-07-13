/* ArchimateDiagramParser.vala — line-based parser for PlantUML Archimate diagrams */
namespace GDiagram {

public class ArchimateDiagramParser : Object {
    private ArchimateDiagram diagram;

    public ArchimateDiagramParser() {}

    public ArchimateDiagram parse(string source) {
        this.diagram = new ArchimateDiagram();

        parse_archimate(source);
        return diagram;
    }

    private void parse_archimate(string source) {
        string[] lines = source.split("\n");
        // group_stack tracks nested rectangle blocks
        var group_stack = new Gee.ArrayList<ArchimateGroup>();
        int elem_counter = 0;

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();

            // Skip directives
            if (lower.has_prefix("@startuml") || lower.has_prefix("@enduml")) continue;
            if (lower.has_prefix("skinparam") || lower.has_prefix("!include") ||
                lower.has_prefix("<style>") || lower == "</style>") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            // Closing brace
            if (trimmed == "}") {
                if (group_stack.size > 0) {
                    group_stack.remove_at(group_stack.size - 1);
                }
                continue;
            }

            // archimate #Layer "Label" as id <<stereotype>>
            if (lower.has_prefix("archimate ")) {
                parse_archimate_element(trimmed, i + 1);
                elem_counter++;
                if (group_stack.size > 0 && diagram.elements.size > 0) {
                    var last = diagram.elements.get(diagram.elements.size - 1);
                    group_stack.get(group_stack.size - 1).element_ids.add(last.id);
                }
                continue;
            }

            // Macro-style: Layer_Type(id, "label")  e.g. Business_Role(myRole, "Role")
            if (is_macro_element(lower)) {
                parse_macro_element(trimmed, i + 1);
                elem_counter++;
                if (group_stack.size > 0 && diagram.elements.size > 0) {
                    var last = diagram.elements.get(diagram.elements.size - 1);
                    group_stack.get(group_stack.size - 1).element_ids.add(last.id);
                }
                continue;
            }

            // Rel_XXX(from, to, "label")  or  Rel_XXX_Direction(from, to, "label")
            if (lower.has_prefix("rel_") && trimmed.contains("(")) {
                parse_rel_macro(trimmed, i + 1);
                continue;
            }

            // Rectangle group: rectangle "Name" { or rectangle "Name" <<stereotype>> {
            if (lower.has_prefix("rectangle ")) {
                string rest = trimmed.substring(10).strip();
                // Extract name (may be quoted)
                string group_name = extract_quoted_or_word(rest);
                var grp = new ArchimateGroup(group_name, i + 1);
                diagram.groups.add(grp);
                group_stack.add(grp);
                continue;
            }

            // Arrow relations: from --> to  or  from ..> to  or  from -[#color]-> to
            if (trimmed.contains("-->") || trimmed.contains("..>") ||
                trimmed.contains("->>") || trimmed.contains("->")) {
                parse_arrow_relation(trimmed, i + 1);
                continue;
            }
        }

        // If no explicit elements parsed, generate placeholder
        if (diagram.elements.size == 0) {
            diagram.errors.add(new ParseError("No Archimate elements found", 1, 1));
        }
    }

    // Parse: archimate #Business "My Role" as myRole <<Role>>
    private void parse_archimate_element(string line, int lineno) {
        string rest = line.substring(10).strip();  // after "archimate "

        // Extract color/layer: optional #Color or #Layer
        ArchimateLayer layer = ArchimateLayer.NONE;
        string? color_override = null;

        if (rest.has_prefix("#")) {
            int space = rest.index_of(" ");
            if (space < 0) space = rest.length;
            string color_token = rest.substring(1, space - 1);
            rest = rest.substring(space).strip();
            layer = parse_layer_from_token(color_token);
            if (layer == ArchimateLayer.NONE) {
                // It's a hex color
                color_override = "#" + color_token;
            }
        }

        // Extract label (quoted)
        string label = "";
        string id = "";

        int q1 = rest.index_of("\"");
        int q2 = (q1 >= 0) ? rest.index_of("\"", q1 + 1) : -1;
        if (q1 >= 0 && q2 > q1) {
            label = rest.substring(q1 + 1, q2 - q1 - 1);
            rest = rest.substring(q2 + 1).strip();
        } else {
            // No quotes — label is the next word
            int space = rest.index_of(" ");
            if (space < 0) {
                label = rest;
                rest = "";
            } else {
                label = rest.substring(0, space);
                rest = rest.substring(space).strip();
            }
        }

        // "as id"
        if (rest.down().has_prefix("as ")) {
            rest = rest.substring(3).strip();
            // id ends before <<
            int stereo_pos = rest.index_of("<<");
            if (stereo_pos >= 0) {
                id = rest.substring(0, stereo_pos).strip();
                rest = rest.substring(stereo_pos).strip();
            } else {
                id = rest.strip();
                rest = "";
            }
        } else {
            // No alias — use label as id (sanitized)
            id = sanitize_id(label);
        }

        // Stereotype: <<Type>>
        string? stereotype = null;
        if (rest.has_prefix("<<")) {
            int close = rest.index_of(">>");
            if (close >= 0) {
                stereotype = rest.substring(2, close - 2).strip();
            }
        }

        if (id.length == 0) id = "elem_%d".printf(diagram.elements.size);
        if (label.length == 0) label = id;

        var elem = new ArchimateElement(id, label, layer, lineno);
        elem.stereotype = stereotype;
        elem.color = color_override;
        diagram.elements.add(elem);
    }

    // Parse macro-style element: Business_Role(id, "label")
    private void parse_macro_element(string line, int lineno) {
        int paren = line.index_of("(");
        if (paren < 0) return;

        string type_part = line.substring(0, paren).strip();
        string args_part = line.substring(paren + 1);
        int close = args_part.last_index_of(")");
        if (close >= 0) args_part = args_part.substring(0, close);

        // Determine layer from prefix
        ArchimateLayer layer = ArchimateLayer.NONE;
        string stereotype = "";
        string lower_type = type_part.down();

        if (lower_type.has_prefix("business_")) {
            layer = ArchimateLayer.BUSINESS;
            stereotype = type_part.substring(9);
        } else if (lower_type.has_prefix("application_")) {
            layer = ArchimateLayer.APPLICATION;
            stereotype = type_part.substring(12);
        } else if (lower_type.has_prefix("technology_")) {
            layer = ArchimateLayer.TECHNOLOGY;
            stereotype = type_part.substring(11);
        } else if (lower_type.has_prefix("motivation_")) {
            layer = ArchimateLayer.MOTIVATION;
            stereotype = type_part.substring(11);
        } else if (lower_type.has_prefix("physical_")) {
            layer = ArchimateLayer.PHYSICAL;
            stereotype = type_part.substring(9);
        } else if (lower_type.has_prefix("implementation_")) {
            layer = ArchimateLayer.IMPLEMENTATION;
            stereotype = type_part.substring(15);
        } else if (lower_type.has_prefix("strategy_")) {
            layer = ArchimateLayer.STRATEGY;
            stereotype = type_part.substring(9);
        }

        // Parse args: id, "label"  (or  id, "label", ...)
        string[] args = split_args(args_part);
        if (args.length == 0) return;

        string id = args[0].strip().replace("\"", "");
        string label = (args.length > 1) ? args[1].strip().replace("\"", "") : id;

        if (id.length == 0) return;

        var elem = new ArchimateElement(id, label, layer, lineno);
        if (stereotype.length > 0) elem.stereotype = stereotype;
        diagram.elements.add(elem);
    }

    // Parse: Rel_Flow(from, to, "label") or Rel_Association_Up(from, to, "label")
    private void parse_rel_macro(string line, int lineno) {
        int paren = line.index_of("(");
        if (paren < 0) return;

        string rel_part = line.substring(4, paren - 4);  // after "Rel_"
        // Strip direction suffix: _Up _Down _Left _Right
        string rel_type = rel_part;
        foreach (string dir in new string[]{"_Up", "_Down", "_Left", "_Right"}) {
            if (rel_type.has_suffix(dir)) {
                rel_type = rel_type.substring(0, rel_type.length - dir.length);
                break;
            }
        }

        string args_part = line.substring(paren + 1);
        int close = args_part.last_index_of(")");
        if (close >= 0) args_part = args_part.substring(0, close);

        string[] args = split_args(args_part);
        if (args.length < 2) return;

        string from_id = args[0].strip().replace("\"", "");
        string to_id = args[1].strip().replace("\"", "");
        string? label = (args.length > 2) ? args[2].strip().replace("\"", "") : null;

        var rel = new ArchimateRelation(from_id, to_id, rel_type, lineno);
        rel.label = label;
        rel.is_dotted = rel_type.down().contains("realization") || rel_type.down().contains("influence");
        diagram.relations.add(rel);
    }

    // Parse arrow relations: from --> to : "label"   or   from ..> to : label
    private void parse_arrow_relation(string line, int lineno) {
        string rel_type = "Association";
        bool is_dotted = false;
        string sep = "";

        if (line.contains("-->")) { sep = "-->"; }
        else if (line.contains("..>")) { sep = "..>"; is_dotted = true; }
        else if (line.contains("->>")) { sep = "->>"; }
        else if (line.contains("->")) { sep = "->"; }
        else return;

        int arrow_pos = line.index_of(sep);
        if (arrow_pos < 0) return;

        string from_part = line.substring(0, arrow_pos).strip();
        string rest = line.substring(arrow_pos + sep.length).strip();

        // Remove color spec: -[#color]->
        if (from_part.contains("[")) {
            int lb = from_part.index_of("[");
            from_part = from_part.substring(0, lb).strip();
        }

        // Label after colon
        string? label = null;
        int colon = rest.index_of(":");
        string to_part;
        if (colon >= 0) {
            to_part = rest.substring(0, colon).strip();
            label = rest.substring(colon + 1).strip().replace("\"", "");
        } else {
            to_part = rest.strip();
        }

        if (is_dotted) rel_type = "Flow";

        if (from_part.length == 0 || to_part.length == 0) return;

        var rel = new ArchimateRelation(from_part, to_part, rel_type, lineno);
        rel.label = label;
        rel.is_dotted = is_dotted;
        diagram.relations.add(rel);
    }

    private ArchimateLayer parse_layer_from_token(string token) {
        switch (token.down()) {
            case "business":       return ArchimateLayer.BUSINESS;
            case "application":    return ArchimateLayer.APPLICATION;
            case "technology":     return ArchimateLayer.TECHNOLOGY;
            case "motivation":     return ArchimateLayer.MOTIVATION;
            case "physical":       return ArchimateLayer.PHYSICAL;
            case "implementation": return ArchimateLayer.IMPLEMENTATION;
            case "strategy":       return ArchimateLayer.STRATEGY;
            default:               return ArchimateLayer.NONE;
        }
    }

    private bool is_macro_element(string lower) {
        return lower.has_prefix("business_") || lower.has_prefix("application_") ||
               lower.has_prefix("technology_") || lower.has_prefix("motivation_") ||
               lower.has_prefix("physical_") || lower.has_prefix("implementation_") ||
               lower.has_prefix("strategy_");
    }

    private string extract_quoted_or_word(string s) {
        if (s.has_prefix("\"")) {
            int q2 = s.index_of("\"", 1);
            if (q2 > 0) return s.substring(1, q2 - 1);
        }
        int space = s.index_of(" ");
        return (space >= 0) ? s.substring(0, space) : s;
    }

    // Split comma-separated args, respecting quoted strings
    private string[] split_args(string s) {
        var result = new Gee.ArrayList<string>();
        var current = new StringBuilder();
        bool in_quote = false;

        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (c == '"') {
                in_quote = !in_quote;
                current.append_c(c);
            } else if (c == ',' && !in_quote) {
                result.add(current.str);
                current.truncate(0);
            } else {
                current.append_c(c);
            }
        }
        if (current.len > 0) result.add(current.str);

        return result.to_array();
    }

    private string sanitize_id(string name) {
        var sb = new StringBuilder();
        foreach (char c in name.to_utf8()) {
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '_') {
                sb.append_c(c);
            } else {
                sb.append_c('_');
            }
        }
        return (sb.len > 0) ? sb.str : "elem";
    }
}

}
