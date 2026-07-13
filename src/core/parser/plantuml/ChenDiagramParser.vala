/* ChenDiagramParser.vala — line-based parser for PlantUML @startchen */
namespace GDiagram {

public class ChenDiagramParser : Object {
    private ChenDiagram diagram;

    public ChenDiagramParser() {}

    public ChenDiagram parse(string source) {
        this.diagram = new ChenDiagram();
        parse_chen(source);
        return diagram;
    }

    private void parse_chen(string source) {
        string[] lines = source.split("\n");

        ChenEntity? current_entity = null;
        ChenRelationship? current_relationship = null;
        bool in_block = false;

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//") || trimmed.has_prefix("'")) continue;

            string lower = trimmed.down();
            if (lower == "@startchen" || lower == "@endchen") continue;
            if (lower.has_prefix("skinparam") || lower.has_prefix("<style>") || lower == "</style>") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip().replace("\"", "");
                continue;
            }

            // Closing brace
            if (trimmed == "}") {
                current_entity = null;
                current_relationship = null;
                in_block = false;
                continue;
            }

            // Entity declaration: entity Name {
            if (lower.has_prefix("entity ")) {
                string rest = trimmed.substring(7).strip();
                bool is_weak_entity = false;
                if (rest.down().has_prefix("weak ")) {
                    is_weak_entity = true;
                    rest = rest.substring(5).strip();
                }
                if (rest.has_suffix("{")) rest = rest.substring(0, rest.length - 1).strip();
                var entity = new ChenEntity(rest, i + 1);
                entity.is_weak = is_weak_entity;
                diagram.entities.add(entity);
                current_entity = entity;
                current_relationship = null;
                in_block = true;
                continue;
            }

            // Relationship declaration: relationship Name {
            if (lower.has_prefix("relationship ")) {
                string rest = trimmed.substring(13).strip();
                if (rest.has_suffix("{")) rest = rest.substring(0, rest.length - 1).strip();
                var rel = new ChenRelationship(rest, i + 1);
                diagram.relationships.add(rel);
                current_relationship = rel;
                current_entity = null;
                in_block = true;
                continue;
            }

            // Link: A -[card]- B or A -- B or A -[card]-> B
            if (try_parse_link(trimmed, i + 1)) {
                continue;
            }

            // Inside entity block — attribute lines
            if (in_block && current_entity != null) {
                parse_attribute(trimmed, current_entity.attributes, i + 1);
                continue;
            }

            // Inside relationship block — attribute lines
            if (in_block && current_relationship != null) {
                parse_attribute(trimmed, current_relationship.attributes, i + 1);
                continue;
            }
        }
    }

    private void parse_attribute(string line, Gee.ArrayList<ChenAttribute> attrs, int lineno) {
        string trimmed = line.strip().replace(";", "");
        if (trimmed.length == 0) return;

        bool is_key = false;
        bool is_derived = false;
        bool is_multivalued = false;

        // * prefix = key attribute
        if (trimmed.has_prefix("*")) {
            is_key = true;
            trimmed = trimmed.substring(1).strip();
        }
        // / prefix = derived attribute
        if (trimmed.has_prefix("/")) {
            is_derived = true;
            trimmed = trimmed.substring(1).strip();
        }
        // { } around name = multivalued
        if (trimmed.has_prefix("{") && trimmed.has_suffix("}")) {
            is_multivalued = true;
            trimmed = trimmed.substring(1, trimmed.length - 2).strip();
        }

        if (trimmed.length == 0) return;

        var attr = new ChenAttribute(trimmed, lineno);
        attr.is_key = is_key;
        attr.is_derived = is_derived;
        attr.is_multivalued = is_multivalued;
        attrs.add(attr);
    }

    private bool try_parse_link(string line, int lineno) {
        // Patterns: A -[card]- B, A -- B, A -[card]-> B
        // Look for -- or -[...]- or -[...]->
        string trimmed = line.strip().replace(";", "");

        // Try -[card]- pattern first
        int bracket_open = trimmed.index_of("-[");
        if (bracket_open >= 0) {
            int bracket_close = trimmed.index_of("]-", bracket_open);
            int bracket_close_arrow = trimmed.index_of("]->", bracket_open);
            if (bracket_close >= 0 || bracket_close_arrow >= 0) {
                string from_name = trimmed.substring(0, bracket_open).strip();
                string card;
                string to_name;
                if (bracket_close_arrow >= 0) {
                    card = trimmed.substring(bracket_open + 2, bracket_close_arrow - bracket_open - 2);
                    to_name = trimmed.substring(bracket_close_arrow + 3).strip();
                } else {
                    card = trimmed.substring(bracket_open + 2, bracket_close - bracket_open - 2);
                    to_name = trimmed.substring(bracket_close + 2).strip();
                }
                if (from_name.length > 0 && to_name.length > 0) {
                    diagram.links.add(new ChenLink(from_name, to_name, card, lineno));
                    return true;
                }
            }
        }

        // Try simple -- pattern
        int dash_pos = trimmed.index_of(" -- ");
        if (dash_pos >= 0) {
            string from_name = trimmed.substring(0, dash_pos).strip();
            string to_name = trimmed.substring(dash_pos + 4).strip();
            if (from_name.length > 0 && to_name.length > 0) {
                diagram.links.add(new ChenLink(from_name, to_name, "", lineno));
                return true;
            }
        }

        return false;
    }
}

}
