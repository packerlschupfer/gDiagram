namespace GDiagram {
    /**
     * Mermaid sequence diagrams, parsed statement by statement from the source lines.
     *
     * The shared token stream lost the text between tokens: labels were rebuilt by joining
     * lexemes with spaces ("GET /a/b (x: 1)" became "GET / a / b ( x : 1 )", "Processing..."
     * lost its dots), so every text (message, note, alias, block condition) is now the
     * source substring itself. Statements are lines, or ";"-separated parts of a line, as
     * in Mermaid. Besides the flat lists the diagram keeps `events` in source order, which
     * the renderer lays out row by row (blocks with their else/and/option sections, notes,
     * activations, create/destroy).
     */
    public class MermaidSequenceParser : Object {
        private MermaidSequenceDiagram diagram;
        private Gee.ArrayList<MermaidLoop> open_loops;
        private MermaidBox? open_box;
        private bool numbering;
        private int next_number;
        private int number_step;

        private static Regex? message_regex = null;
        private static Regex? entity_regex = null;
        private static Regex? br_regex = null;

        // CSS colour names, for telling "box Aqua Group" (colour + title) from "box Group"
        private const string CSS_COLORS = "|aliceblue|antiquewhite|aqua|aquamarine|azure|beige|bisque|black|blanchedalmond|blue|blueviolet|brown|burlywood|cadetblue|chartreuse|chocolate|coral|cornflowerblue|cornsilk|crimson|cyan|darkblue|darkcyan|darkgoldenrod|darkgray|darkgreen|darkgrey|darkkhaki|darkmagenta|darkolivegreen|darkorange|darkorchid|darkred|darksalmon|darkseagreen|darkslateblue|darkslategray|darkslategrey|darkturquoise|darkviolet|deeppink|deepskyblue|dimgray|dimgrey|dodgerblue|firebrick|floralwhite|forestgreen|fuchsia|gainsboro|ghostwhite|gold|goldenrod|gray|green|greenyellow|grey|honeydew|hotpink|indianred|indigo|ivory|khaki|lavender|lavenderblush|lawngreen|lemonchiffon|lightblue|lightcoral|lightcyan|lightgoldenrodyellow|lightgray|lightgreen|lightgrey|lightpink|lightsalmon|lightseagreen|lightskyblue|lightslategray|lightslategrey|lightsteelblue|lightyellow|lime|limegreen|linen|magenta|maroon|mediumaquamarine|mediumblue|mediumorchid|mediumpurple|mediumseagreen|mediumslateblue|mediumspringgreen|mediumturquoise|mediumvioletred|midnightblue|mintcream|mistyrose|moccasin|navajowhite|navy|oldlace|olive|olivedrab|orange|orangered|orchid|palegoldenrod|palegreen|paleturquoise|palevioletred|papayawhip|peachpuff|peru|pink|plum|powderblue|purple|rebeccapurple|red|rosybrown|royalblue|saddlebrown|salmon|sandybrown|seagreen|seashell|sienna|silver|skyblue|slateblue|slategray|slategrey|snow|springgreen|steelblue|tan|teal|thistle|tomato|turquoise|violet|wheat|white|whitesmoke|yellow|yellowgreen|transparent|";

        public MermaidSequenceParser() {
        }

        public MermaidSequenceDiagram parse(string source) {
            this.diagram = new MermaidSequenceDiagram();
            this.open_loops = new Gee.ArrayList<MermaidLoop>();
            this.open_box = null;
            this.numbering = false;
            this.next_number = 1;
            this.number_step = 1;
            init_regexes();

            string[] lines = source.split("\n");
            int i = 0;
            bool header = false;

            // Front matter ("---\ntitle: X\n---"), directives and comments before the keyword
            while (i < lines.length) {
                string t = lines[i].strip();
                if (t == "---" && !header) {
                    i++;
                    while (i < lines.length && lines[i].strip() != "---") {
                        string fm = lines[i].strip();
                        if (fm.has_prefix("title:")) {
                            diagram.title = unquote(fm.substring(6).strip());
                        }
                        i++;
                    }
                    i++;
                    continue;
                }
                if (t.length == 0 || t.has_prefix("%%")) {
                    i++;
                    continue;
                }
                if (t == "sequenceDiagram" || t.has_prefix("sequenceDiagram ") || t.has_prefix("sequenceDiagram;")) {
                    header = true;
                    string rest = t.substring("sequenceDiagram".length);
                    if (rest.has_prefix(";")) {
                        parse_line(rest.substring(1), i + 1);
                    }
                    i++;
                }
                break;
            }
            if (!header) {
                int line = i < lines.length ? i + 1 : int.max(1, lines.length);
                diagram.errors.add(new ParseError("Expected 'sequenceDiagram'", line, 1));
                return diagram;
            }

            for (; i < lines.length; i++) {
                string t = lines[i].strip();
                // "accDescr { ... }" spans lines
                if (t.has_prefix("accDescr") && t.substring(8).strip().has_prefix("{")) {
                    while (i < lines.length && !lines[i].contains("}")) {
                        i++;
                    }
                    continue;
                }
                parse_line(lines[i], i + 1);
            }

            foreach (var loop in open_loops) {
                diagram.errors.add(new ParseError("Expected 'end' to close %s".printf(loop_keyword(loop.loop_type)),
                                                  loop.source_line, 1));
            }
            return diagram;
        }

        private static void init_regexes() {
            if (message_regex != null) {
                return;
            }
            try {
                // from, arrow, +/-, to, text. The arrows longest first: "-->>" before "->>".
                message_regex = new Regex(
                    "^([^:;]+?)\\s*(<<-->>|<<->>|-->>|->>|--x|-x|--\\)|-\\)|-->|->)\\s*([+-]?)\\s*([^:]*?)\\s*(?::(.*))?$");
                entity_regex = new Regex("#([A-Za-z]+|[0-9]+);");
                br_regex = new Regex("<br\\s*/?>", RegexCompileFlags.CASELESS);
            } catch (RegexError e) {
                warning("Mermaid sequence regex: %s", e.message);
            }
        }

        // A source line, split at ";" statement separators ("#quot;" entity codes stay whole)
        private void parse_line(string raw, int line) {
            var sb = new StringBuilder();
            int n = raw.length;
            for (int k = 0; k < n; k++) {
                char c = raw[k];
                if (c == ';') {
                    // part of an entity code "#name;" / "#123;"?
                    int h = sb.len > 0 ? sb.str.last_index_of_char('#') : -1;
                    bool entity = false;
                    if (h >= 0 && h < (int) sb.len - 1) {
                        entity = true;
                        for (int q = h + 1; q < (int) sb.len; q++) {
                            if (!sb.str[q].isalnum()) {
                                entity = false;
                                break;
                            }
                        }
                    }
                    if (!entity) {
                        parse_statement(sb.str, line);
                        sb.truncate();
                        continue;
                    }
                }
                sb.append_c(c);
            }
            parse_statement(sb.str, line);
        }

        private void error(string message, int line) {
            diagram.errors.add(new ParseError(message, line, 1));
        }

        private void parse_statement(string raw, int line) {
            string s = raw.strip();
            if (s.length == 0 || s.has_prefix("%%")) {
                return;
            }
            string kw;
            string rest;
            split_keyword(s, out kw, out rest);
            string lkw = kw.down();

            switch (lkw) {
                case "title":
                    diagram.title = decode_text(rest.has_prefix(":") ? rest.substring(1).strip() : rest);
                    return;
                case "acctitle":
                case "accdescr":
                case "links":
                case "link":
                case "properties":
                case "details":
                    return;
                case "autonumber":
                    parse_autonumber(rest);
                    return;
                case "participant":
                case "actor":
                    parse_participant(lkw == "actor", rest, line, false);
                    return;
                case "create": {
                    string ckw;
                    string crest;
                    split_keyword(rest, out ckw, out crest);
                    if (ckw.down() == "participant" || ckw.down() == "actor") {
                        parse_participant(ckw.down() == "actor", crest, line, true);
                    } else {
                        error("Expected 'participant' or 'actor' after 'create'", line);
                    }
                    return;
                }
                case "destroy": {
                    if (rest.length == 0) {
                        error("Expected participant after 'destroy'", line);
                        return;
                    }
                    var actor = use_actor(rest, line);
                    var ev = new MermaidSeqEvent(MermaidSeqEventKind.DESTROY, line);
                    ev.actor = actor;
                    diagram.events.add(ev);
                    return;
                }
                case "box":
                    parse_box(rest, line);
                    return;
                case "activate":
                case "deactivate": {
                    if (rest.length == 0) {
                        error("Expected actor identifier", line);
                        return;
                    }
                    var ev = new MermaidSeqEvent(lkw == "activate" ? MermaidSeqEventKind.ACTIVATE
                                                                   : MermaidSeqEventKind.DEACTIVATE, line);
                    ev.actor = use_actor(rest, line);
                    diagram.events.add(ev);
                    return;
                }
                case "note":
                    parse_note(rest, line);
                    return;
                case "loop":
                case "alt":
                case "opt":
                case "par":
                case "par_over":
                case "critical":
                case "break":
                case "rect":
                    parse_block_start(lkw, rest, line);
                    return;
                case "else":
                case "and":
                case "option":
                    parse_section(lkw, rest, line);
                    return;
                case "end":
                    if (rest.length == 0) {
                        parse_end(line);
                        return;
                    }
                    break;
                default:
                    break;
            }

            parse_message(s, line);
        }

        private static void split_keyword(string s, out string kw, out string rest) {
            int k = 0;
            while (k < s.length && !s[k].isspace() && s[k] != ':') {
                k++;
            }
            kw = s.substring(0, k);
            rest = s.substring(k).strip();
        }

        private void parse_autonumber(string rest) {
            string r = rest.strip().down();
            if (r == "off") {
                numbering = false;
                return;
            }
            numbering = true;
            diagram.autonumber = true;
            string[] parts = r.split(" ");
            int idx = 0;
            foreach (string p in parts) {
                if (p.length == 0) {
                    continue;
                }
                int v = int.parse(p);
                if (idx == 0) {
                    next_number = v;
                } else if (idx == 1) {
                    number_step = v;
                }
                idx++;
            }
        }

        private MermaidActor use_actor(string id, int line) {
            var actor = diagram.find_actor(id);
            if (actor == null) {
                actor = new MermaidActor(id, true, line);
                register_actor(actor);
            }
            return actor;
        }

        private void register_actor(MermaidActor actor) {
            diagram.add_actor(actor);
            if (open_box != null && !open_box.actors.contains(actor)) {
                open_box.actors.add(actor);
                actor.box_index = diagram.boxes.index_of(open_box);
            }
        }

        // "A", "A as Alice", "A@{ "type": "database", "alias": "DB" }"
        private void parse_participant(bool is_actor, string rest, int line, bool create) {
            string body = rest.strip();
            if (body.length == 0) {
                error("Expected participant identifier", line);
                return;
            }
            string? meta = null;
            int at = body.index_of("@{");
            if (at > 0) {
                int close = body.last_index_of("}");
                if (close > at) {
                    meta = body.substring(at + 2, close - at - 2);
                    body = (body.substring(0, at) + body.substring(close + 1)).strip();
                }
            }
            string id = body;
            string? alias = null;
            int as_pos = find_as(body);
            if (as_pos > 0) {
                id = body.substring(0, as_pos).strip();
                // Mermaid's sequence grammar has no string token for an actor: the
                // quotes of `participant A as "API Gateway"` are part of the label
                alias = decode_text(body.substring(as_pos + 4).strip());
            }
            if (id.length == 0) {
                error("Expected participant identifier", line);
                return;
            }
            string? shape = null;
            if (meta != null) {
                string? type = meta_value(meta, "type");
                if (type != null) {
                    string t = type.down();
                    if (t == "actor") {
                        is_actor = true;
                    } else if (t != "participant") {
                        shape = t;
                    }
                }
                string? meta_alias = meta_value(meta, "alias");
                if (meta_alias != null && alias == null) {
                    alias = decode_text(meta_alias);
                }
            }

            var actor = diagram.find_actor(id);
            if (actor == null) {
                actor = new MermaidActor(id, !is_actor, line);
                register_actor(actor);
            } else {
                // a declaration after first use keeps the position, takes the kind
                actor.is_participant = !is_actor;
                if (actor.source_line <= 0) {
                    actor.source_line = line;
                }
                if (open_box != null && !open_box.actors.contains(actor)) {
                    open_box.actors.add(actor);
                    actor.box_index = diagram.boxes.index_of(open_box);
                }
            }
            if (alias != null && alias.length > 0) {
                actor.alias = alias;
            }
            if (shape != null) {
                actor.shape = shape;
            }
            if (create) {
                var ev = new MermaidSeqEvent(MermaidSeqEventKind.CREATE, line);
                ev.actor = actor;
                diagram.events.add(ev);
            }
        }

        // Position of " as " (case-sensitive, as in Mermaid) outside quotes
        private static int find_as(string s) {
            bool quoted = false;
            for (int k = 0; k + 4 <= s.length; k++) {
                if (s[k] == '"') {
                    quoted = !quoted;
                }
                if (!quoted && s[k].isspace() && s.substring(k + 1, 3) == "as " ) {
                    return k;
                }
            }
            return -1;
        }

        private static string? meta_value(string meta, string key) {
            try {
                var re = new Regex("[\"']?%s[\"']?\\s*:\\s*[\"']([^\"']*)[\"']".printf(key));
                MatchInfo m;
                if (re.match(meta, 0, out m)) {
                    return m.fetch(1);
                }
            } catch (RegexError e) {
            }
            return null;
        }

        // "box Aqua Group", "box rgb(1,2,3) Title", "box "Title" #e0e0ff", "box Title"
        private void parse_box(string rest, int line) {
            if (open_box != null) {
                error("Nested 'box' is not allowed", line);
                return;
            }
            var box = new MermaidBox();
            box.source_line = line;
            string r = rest.strip();
            string? color = take_leading_color(ref r);
            if (color == null) {
                color = take_trailing_color(ref r);
            }
            box.color = color;
            // as for participants, `box "Front End"` keeps its quotes in Mermaid
            r = r.strip();
            if (r.length > 0) {
                box.label = decode_text(r);
            }
            diagram.boxes.add(box);
            open_box = box;
        }

        private static string? take_leading_color(ref string r) {
            string low = r.down();
            if (low.has_prefix("rgb(") || low.has_prefix("rgba(") || low.has_prefix("hsl(") || low.has_prefix("hsla(")) {
                int close = r.index_of(")");
                if (close > 0) {
                    string c = r.substring(0, close + 1);
                    r = r.substring(close + 1).strip();
                    return c;
                }
            }
            int sp = 0;
            while (sp < r.length && !r[sp].isspace()) {
                sp++;
            }
            string word = r.substring(0, sp);
            if (is_color_word(word)) {
                r = r.substring(sp).strip();
                return word;
            }
            return null;
        }

        private static string? take_trailing_color(ref string r) {
            int sp = r.length;
            while (sp > 0 && !r[sp - 1].isspace()) {
                sp--;
            }
            string word = r.substring(sp);
            if (word.has_prefix("#") && is_color_word(word)) {
                r = r.substring(0, sp).strip();
                return word;
            }
            return null;
        }

        private static bool is_color_word(string word) {
            if (word.length == 0) {
                return false;
            }
            if (word.has_prefix("#")) {
                string h = word.substring(1);
                if (h.length != 3 && h.length != 4 && h.length != 6 && h.length != 8) {
                    return false;
                }
                for (int k = 0; k < h.length; k++) {
                    if (!h[k].isxdigit()) {
                        return false;
                    }
                }
                return true;
            }
            return CSS_COLORS.contains("|" + word.down() + "|");
        }

        private void parse_note(string rest, int line) {
            int colon = rest.index_of(":");
            string place = (colon >= 0 ? rest.substring(0, colon) : rest).strip();
            string text = colon >= 0 ? rest.substring(colon + 1).strip() : "";
            string low = place.down();
            var note = new MermaidNote(decode_text(text));
            note.source_line = line;
            string targets;
            if (low.has_prefix("over ") || low.has_prefix("over\t")) {
                note.is_over = true;
                targets = place.substring(5).strip();
            } else if (low.has_prefix("left of ")) {
                note.is_right = false;
                targets = place.substring(8).strip();
            } else if (low.has_prefix("right of ")) {
                note.is_right = true;
                targets = place.substring(9).strip();
            } else {
                error("Expected 'left of', 'right of' or 'over' after 'Note'", line);
                return;
            }
            string[] names = targets.split(",");
            string first = names.length > 0 ? names[0].strip() : "";
            if (first.length == 0) {
                error("Expected actor identifier", line);
                return;
            }
            note.from_actor = use_actor(first, line);
            note.over_actor = note.from_actor;
            if (names.length > 1) {
                string second = names[1].strip();
                if (second.length == 0) {
                    error("Expected second actor identifier", line);
                    return;
                }
                note.to_actor = use_actor(second, line);
            }
            diagram.notes.add(note);
            foreach (var loop in open_loops) {
                loop.notes.add(note);
            }
            var ev = new MermaidSeqEvent(MermaidSeqEventKind.NOTE, line);
            ev.note = note;
            diagram.events.add(ev);
        }

        private void parse_block_start(string kw, string rest, int line) {
            MermaidLoopType type;
            switch (kw) {
                case "alt": type = MermaidLoopType.ALT; break;
                case "opt": type = MermaidLoopType.OPT; break;
                case "par":
                case "par_over": type = MermaidLoopType.PAR; break;
                case "critical": type = MermaidLoopType.CRITICAL; break;
                case "break": type = MermaidLoopType.BREAK; break;
                case "rect": type = MermaidLoopType.RECT; break;
                default: type = MermaidLoopType.LOOP; break;
            }
            var loop = new MermaidLoop(type);
            loop.source_line = line;
            loop.depth = open_loops.size;
            string cond = rest.has_prefix(":") ? rest.substring(1).strip() : rest;
            if (type == MermaidLoopType.RECT) {
                if (cond.length > 0) {
                    loop.color = cond;
                    loop.condition = cond;
                }
            } else if (cond.length > 0) {
                loop.condition = decode_text(cond);
            }
            loop.msg_start = diagram.messages.size;
            open_loops.add(loop);
            var ev = new MermaidSeqEvent(MermaidSeqEventKind.BLOCK_START, line);
            ev.loop = loop;
            diagram.events.add(ev);
        }

        private void parse_section(string kw, string rest, int line) {
            if (open_loops.size == 0) {
                error("'%s' outside a block".printf(kw), line);
                return;
            }
            var loop = open_loops[open_loops.size - 1];
            string cond = rest.has_prefix(":") ? rest.substring(1).strip() : rest;
            var section = new MermaidLoopSection(cond.length > 0 ? decode_text(cond) : null);
            section.msg_start = diagram.messages.size;
            section.source_line = line;
            loop.sections.add(section);
            var ev = new MermaidSeqEvent(MermaidSeqEventKind.BLOCK_SECTION, line);
            ev.loop = loop;
            ev.section = section;
            diagram.events.add(ev);
        }

        private void parse_end(int line) {
            if (open_loops.size > 0) {
                var loop = open_loops.remove_at(open_loops.size - 1);
                loop.msg_end = diagram.messages.size - 1;
                diagram.loops.add(loop);
                var ev = new MermaidSeqEvent(MermaidSeqEventKind.BLOCK_END, line);
                ev.loop = loop;
                diagram.events.add(ev);
                return;
            }
            if (open_box != null) {
                open_box = null;
                return;
            }
            error("Unexpected 'end'", line);
        }

        private void parse_message(string s, int line) {
            MatchInfo? m = null;
            if (message_regex == null || !message_regex.match(s, 0, out m) || m == null) {
                error("Unrecognized statement: '%s'".printf(s), line);
                return;
            }
            string from_id = m.fetch(1).strip();
            string arrow = m.fetch(2);
            string marker = m.fetch(3);
            string to_id = m.fetch(4).strip();
            string? text = m.get_match_count() > 5 ? m.fetch(5) : null;
            if (from_id.length == 0) {
                error("Expected source actor", line);
                return;
            }
            if (to_id.length == 0) {
                error("Expected destination actor (found: '%s')".printf(text != null ? ":" : arrow), line);
                return;
            }
            var from_actor = use_actor(from_id, line);
            var to_actor = use_actor(to_id, line);
            var message = new MermaidMessage(from_actor, to_actor);
            message.arrow_type = mermaid_arrow_type(arrow);
            message.is_activation = marker == "+";
            message.is_deactivation = marker == "-";
            message.source_line = line;
            if (text != null) {
                string t = text.strip();
                if (t.has_prefix("wrap:")) {
                    t = t.substring(5).strip();
                } else if (t.has_prefix("nowrap:")) {
                    t = t.substring(7).strip();
                }
                message.text = decode_text(t);
            }
            if (numbering) {
                message.number = next_number;
                next_number += number_step;
            }
            message.sequence_index = diagram.messages.size;
            diagram.messages.add(message);
            foreach (var loop in open_loops) {
                loop.messages.add(message);
            }
            var ev = new MermaidSeqEvent(MermaidSeqEventKind.MESSAGE, line);
            ev.message = message;
            diagram.events.add(ev);
        }

        // Mermaid arrow syntax: "->>" arrow, "->" line without head, "-x" cross, "-)" async
        // open head, "<<->>" both ends; one more "-" makes each dotted
        public static MermaidArrowType mermaid_arrow_type(string arrow) {
            switch (arrow) {
                case "-->>":   return MermaidArrowType.DOTTED_ARROW;
                case "->":     return MermaidArrowType.SOLID_LINE;
                case "-->":    return MermaidArrowType.DOTTED_LINE;
                case "-x":     return MermaidArrowType.SOLID_CROSS;
                case "--x":    return MermaidArrowType.DOTTED_CROSS;
                case "-)":     return MermaidArrowType.SOLID_OPEN;
                case "--)":    return MermaidArrowType.DOTTED_OPEN;
                case "<<->>":  return MermaidArrowType.SOLID_BIDIRECTIONAL;
                case "<<-->>": return MermaidArrowType.DOTTED_BIDIRECTIONAL;
                default:       return MermaidArrowType.SOLID_ARROW;
            }
        }

        private static string loop_keyword(MermaidLoopType type) {
            switch (type) {
                case MermaidLoopType.ALT: return "alt";
                case MermaidLoopType.OPT: return "opt";
                case MermaidLoopType.PAR: return "par";
                case MermaidLoopType.CRITICAL: return "critical";
                case MermaidLoopType.BREAK: return "break";
                case MermaidLoopType.RECT: return "rect";
                default: return "loop";
            }
        }

        private static string unquote(string s) {
            if (s.length >= 2 && ((s.has_prefix("\"") && s.has_suffix("\"")) ||
                                  (s.has_prefix("'") && s.has_suffix("'")))) {
                return s.substring(1, s.length - 2);
            }
            return s;
        }

        /**
         * Display text: "<br>" / "<br/>" line breaks become "\n", Mermaid entity codes
         * ("#quot;", "#35;", "#9829;") their characters.
         */
        public static string decode_text(string text) {
            init_regexes();
            string t = text;
            try {
                if (br_regex != null) {
                    t = br_regex.replace(t, -1, 0, "\n");
                }
                if (entity_regex != null) {
                    t = entity_regex.replace_eval(t, -1, 0, 0, (m, result) => {
                        string name = m.fetch(1);
                        if (name[0].isdigit()) {
                            int64 code = int64.parse(name);
                            if (code > 0 && code < 0x110000) {
                                result.append_unichar((unichar) code);
                                return false;
                            }
                        }
                        switch (name) {
                            case "quot": result.append("\""); break;
                            case "amp": result.append("&"); break;
                            case "lt": result.append("<"); break;
                            case "gt": result.append(">"); break;
                            case "apos": result.append("'"); break;
                            case "nbsp": result.append(" "); break;
                            case "semi": result.append(";"); break;
                            case "num": result.append("#"); break;
                            default: result.append(m.fetch(0)); break;
                        }
                        return false;
                    });
                }
            } catch (RegexError e) {
            }
            return t;
        }
    }
}
