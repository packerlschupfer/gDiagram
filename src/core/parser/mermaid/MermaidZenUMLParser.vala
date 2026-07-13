/* MermaidZenUMLParser.vala — Mermaid ZenUML parser */
namespace GDiagram {

public class MermaidZenUMLParser : Object {
    private MermaidZenUML diagram;
    // Track participants seen in messages (implicit declaration)
    private Gee.HashSet<string> seen_participants;

    public MermaidZenUMLParser() {}

    public MermaidZenUML parse(string source) {
        this.diagram = new MermaidZenUML();
        this.seen_participants = new Gee.HashSet<string>();

        parse_zenuml(source);

        return diagram;
    }

    private void parse_zenuml(string source) {
        // Track current "sender" for nested calls
        var sender_stack = new Gee.ArrayList<string>();
        sender_stack.add("Client"); // default

        string[] lines = source.split("\n");
        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("//")) continue;

            string lower = trimmed.down();
            if (lower == "zenuml") continue;

            if (lower.has_prefix("title ")) {
                diagram.title = trimmed.substring(6).strip();
                continue;
            }

            // Participant declaration: @Type Name [#color]
            if (trimmed.has_prefix("@")) {
                parse_participant(trimmed, i + 1);
                continue;
            }

            // Return statement
            if (lower.has_prefix("return")) {
                if (sender_stack.size >= 2) {
                    string ret_from = sender_stack.get(sender_stack.size - 1);
                    string ret_to = sender_stack.get(sender_stack.size - 2);
                    string ret_val = (trimmed.length > 6) ? trimmed.substring(6).strip() : "";
                    var msg = new ZenMessage(ret_from, ret_to, ret_val.length > 0 ? ret_val : "return", i + 1);
                    msg.is_return = true;
                    msg.depth = sender_stack.size - 1;
                    diagram.messages.add(msg);
                }
                continue;
            }

            // Closing brace — pop sender stack
            if (trimmed == "}") {
                if (sender_stack.size > 1) sender_stack.remove_at(sender_stack.size - 1);
                continue;
            }

            // Control flow keywords — skip the keyword but let body be processed
            if (lower.has_prefix("if (") || lower.has_prefix("if(") ||
                lower.has_prefix("else") || lower.has_prefix("while") ||
                lower.has_prefix("for(") || lower.has_prefix("foreach") ||
                lower.has_prefix("loop") || lower.has_prefix("par") ||
                lower.has_prefix("try") || lower.has_prefix("catch") ||
                lower.has_prefix("finally") || lower.has_prefix("opt")) {
                // Don't change sender stack for control flow
                continue;
            }

            // Message: A -> B.method(params) { or A -> B.method(params)
            if (trimmed.contains("->")) {
                parse_message(trimmed, sender_stack, i + 1);
            }
        }
    }

    private void parse_participant(string line, int lineno) {
        // @Type [<<Stereotype>>] Name [#color]
        // Remove @ prefix
        string rest = line.substring(1).strip();
        string[] tokens = rest.split(" ");
        if (tokens.length < 1) return;

        string actor_type = tokens[0];
        string? color = null;

        // Find name (last non-color token) and color
        int name_idx = tokens.length - 1;
        if (tokens[name_idx].has_prefix("#")) {
            color = tokens[name_idx];
            name_idx--;
        }

        if (name_idx < 1) return;

        // Skip stereotype: <<...>>
        string raw_name = tokens[name_idx];
        if (raw_name.has_prefix("<<") || raw_name.has_suffix(">>")) {
            name_idx--;
            raw_name = (name_idx >= 1) ? tokens[name_idx] : actor_type;
        }
        string name = raw_name;

        if (!seen_participants.contains(name)) {
            seen_participants.add(name);
            var p = new ZenParticipant(name, actor_type, lineno);
            p.color = color;
            diagram.participants.add(p);
        }
    }

    private void parse_message(string line, Gee.ArrayList<string> sender_stack, int lineno) {
        // A -> B.method(params) {
        int arrow_pos = line.index_of("->");
        if (arrow_pos < 0) return;

        string from_part = line.substring(0, arrow_pos).strip();
        string rest = line.substring(arrow_pos + 2).strip();
        // Remove trailing { and whitespace
        if (rest.has_suffix("{")) rest = rest.substring(0, rest.length - 1).strip();

        // Parse to_id.method(params)
        string to_name;
        string method_name;
        string? params_str = null;

        int dot_pos = rest.index_of(".");
        int paren_pos = rest.index_of("(");

        if (dot_pos >= 0 && (paren_pos < 0 || dot_pos < paren_pos)) {
            to_name = rest.substring(0, dot_pos).strip();
            string after_dot = rest.substring(dot_pos + 1);
            int p_open = after_dot.index_of("(");
            int p_close = after_dot.last_index_of(")");
            if (p_open >= 0) {
                method_name = after_dot.substring(0, p_open).strip();
                params_str = (p_close > p_open) ? after_dot.substring(p_open + 1, p_close - p_open - 1).strip() : "";
            } else {
                method_name = after_dot.strip();
            }
        } else if (paren_pos >= 0) {
            to_name = rest.substring(0, paren_pos).strip();
            int p_close = rest.last_index_of(")");
            method_name = to_name;
            params_str = (p_close > paren_pos) ? rest.substring(paren_pos + 1, p_close - paren_pos - 1).strip() : "";
        } else {
            to_name = rest.strip();
            method_name = to_name;
        }

        // Use sender_stack top as from if from_part is empty
        string actual_from = (from_part.length > 0) ? from_part : sender_stack.get(sender_stack.size - 1);

        // Auto-declare participants
        if (!seen_participants.contains(actual_from)) {
            seen_participants.add(actual_from);
            diagram.participants.add(new ZenParticipant(actual_from, "Actor", lineno));
        }
        if (!seen_participants.contains(to_name)) {
            seen_participants.add(to_name);
            diagram.participants.add(new ZenParticipant(to_name, "Actor", lineno));
        }

        string label = method_name;
        if (params_str != null && params_str.length > 0) {
            label = "%s(%s)".printf(method_name, params_str);
        }

        var msg = new ZenMessage(actual_from, to_name, label, lineno);
        msg.params_str = params_str;
        msg.depth = sender_stack.size - 1;
        diagram.messages.add(msg);

        // Push to_name as new sender if line ends with {
        if (line.has_suffix("{")) {
            sender_stack.add(to_name);
        }
    }
}

}
