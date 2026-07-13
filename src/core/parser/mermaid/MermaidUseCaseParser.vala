/* MermaidUseCaseParser.vala — Mermaid `usecase-beta` diagram parser
 *
 * Written against mermaid 12.2.0's own chevrotain grammar
 * (packages/mermaid/src/diagrams/usecase/parser/usecase.parser.ts and
 * usecase.tokens.ts) and its model builder. The grammar is one statement per
 * line, so this is a line parser, with a pre-pass that joins the three forms
 * that may span lines: `@{ … }` metadata, `json id @{ … }` bodies and
 * `accDescr { … }` blocks.
 *
 *   start      := 'usecase-beta' EOL line*
 *   statement  := accTitle | accDescr | direction | actor | systemBoundary
 *               | note | json | classDef | class | style
 *               | metadataAssignment | entity
 *   actor      := 'actor' actorItem (',' actorItem)* | 'actor' actorItem relationTail
 *   entity     := entityName relationTail?
 *   entityName := (IDENT ('(' label ')' | '[' label ']')? | STRING | MARKDOWN)
 *                 metadata? stereotype? (':::' classes)?
 *   relationTail := (IDENT '@')? arrow entityName
 *   boundary   := 'systemBoundary' name metadata? (':::' classes)? EOL body 'end'
 *   note       := 'note' 'for' IDENT label
 *
 * Notable points of the real grammar, each one easy to get wrong:
 *   - the header is exactly `usecase-beta`; bare `usecase` is not a header;
 *   - there is NO `A --> B : label` form. An edge label is the sandwich
 *     `A -- label --> B`, and the opening operator must be exactly `--` or
 *     `<--`;
 *   - include/extend are written `A ..>: include B`, not as `<<include>>`;
 *     `<<…>>` is only a node stereotype;
 *   - there is no `title` statement (mermaid takes a title from front matter
 *     only); we accept front-matter `title:` and nothing else;
 *   - `%%` comments must start their line — there are no trailing comments;
 *   - metadata keys are only type / icon / business / animate / animation, and
 *     values are never bare numbers;
 *   - a quoted name generates its id by replacing every non-word character
 *     with `_`: "Log in" -> Log_in.
 */
namespace GDiagram {

public class MermaidUseCaseParser : Object {
    private MermaidUseCase diagram;
    // The `systemBoundary … end` block currently open, if any.
    private MermaidUseCaseBoundary? current_boundary;
    private int relation_counter;
    private int note_counter;

    public MermaidUseCaseParser() {}

    public MermaidUseCase parse(string source) {
        this.diagram = new MermaidUseCase();
        this.current_boundary = null;
        this.relation_counter = 0;
        this.note_counter = 0;
        parse_usecase(source);
        return diagram;
    }

    // One source statement after the line-joining pre-pass.
    private class Logical {
        public string text;
        public int line;      // 1-based line the statement starts on
        public Logical(string text, int line) {
            this.text = text;
            this.line = line;
        }
    }

    // ==================== driver ====================

    private void parse_usecase(string source) {
        foreach (var stmt in logical_lines(source)) {
            string line = stmt.text.strip();
            if (line.length == 0) continue;
            string head = first_word(line);

            if (head == "usecase-beta" || head == "usecase") continue;

            if (head == "accTitle" || line.has_prefix("accTitle:")) {
                int c = line.index_of_char(':');
                if (c >= 0) diagram.acc_title = line.substring(c + 1).strip();
                continue;
            }
            if (head == "accDescr" || line.has_prefix("accDescr")) {
                parse_acc_descr(line);
                continue;
            }
            if (head == "direction") {
                parse_direction(line, stmt.line);
                continue;
            }
            if (head == "end") {
                if (current_boundary == null) {
                    error_at(stmt.line, "`end` without an open systemBoundary");
                }
                current_boundary = null;
                continue;
            }
            if (head == "systemBoundary") {
                parse_boundary(line, stmt.line);
                continue;
            }
            if (head == "note") {
                parse_note(line, stmt.line);
                continue;
            }
            if (head == "json") {
                parse_json(line, stmt.line);
                continue;
            }
            if (head == "classDef") {
                parse_class_def(line, stmt.line);
                continue;
            }
            if (head == "class") {
                parse_class(line, stmt.line);
                continue;
            }
            if (head == "style") {
                parse_style(line, stmt.line);
                continue;
            }
            if (head == "actor") {
                parse_actor_statement(line.substring(5), stmt.line);
                continue;
            }
            if (FORBIDDEN_PLANTUML.contains(head.down())) {
                error_at(stmt.line, "`%s` is a PlantUML statement, not Mermaid usecase syntax".printf(head));
                continue;
            }
            parse_entity_statement(line, stmt.line);
        }

        if (current_boundary != null) {
            error_at(current_boundary.source_line,
                     "systemBoundary \"%s\" is never closed with `end`".printf(current_boundary.id));
            current_boundary = null;
        }
    }

    // mermaid's forbiddenPlantUmlStatements, rejected so a pasted PlantUML
    // diagram fails loudly instead of becoming a node named `skinparam`.
    private const string[] FORBIDDEN_PLANTUML_LIST = {
        "allowmixing", "newpage", "package", "rectangle", "skinparam"
    };
    private static Gee.HashSet<string>? forbidden = null;
    private static Gee.HashSet<string> FORBIDDEN_PLANTUML {
        get {
            if (forbidden == null) {
                forbidden = new Gee.HashSet<string>();
                foreach (string s in FORBIDDEN_PLANTUML_LIST) forbidden.add(s);
            }
            return forbidden;
        }
    }

    /**
     * Statements, with `@{ … }`, `json … @{ … }` and `accDescr { … }` joined
     * onto one logical line. Front matter is consumed here too; a `%%` comment
     * only counts when it starts the line, as mermaid's custom matcher checks.
     */
    private Gee.ArrayList<Logical> logical_lines(string source) {
        var result = new Gee.ArrayList<Logical>();
        string[] lines = source.split("\n");
        bool in_front_matter = false;
        bool seen_content = false;
        StringBuilder? pending = null;
        int pending_line = 0;
        int pending_count = 0;

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = raw.strip();

            if (pending == null) {
                if (trimmed == "---" && (!seen_content || in_front_matter)) {
                    in_front_matter = !in_front_matter;
                    continue;
                }
                if (in_front_matter) {
                    if (trimmed.has_prefix("title:") && diagram.title == null) {
                        diagram.title = unquote(trimmed.substring(6).strip());
                    }
                    continue;
                }
                if (trimmed.length == 0) continue;
                if (trimmed.has_prefix("%%")) continue;
                seen_content = true;
                pending = new StringBuilder(raw);
                pending_line = i + 1;
                pending_count = 1;
            } else {
                pending.append_c('\n');
                pending.append(raw);
                pending_count++;
            }

            // A statement stays open only while a brace is unbalanced, and
            // never for more than 50 lines: a stray `{` must not swallow the
            // rest of the file.
            if (brace_depth(pending.str) > 0 && pending_count < 50) continue;
            result.add(new Logical(pending.str, pending_line));
            pending = null;
        }
        if (pending != null) result.add(new Logical(pending.str, pending_line));
        return result;
    }

    // Net `{` depth, ignoring braces inside single/double-quoted runs.
    private static int brace_depth(string s) {
        int depth = 0;
        char quote = '\0';
        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (quote != '\0') {
                if (c == '\\') { i++; continue; }
                if (c == quote) quote = '\0';
                continue;
            }
            if (c == '"' || c == '\'') { quote = c; continue; }
            if (c == '{') depth++;
            else if (c == '}') depth--;
        }
        return depth > 0 ? depth : 0;
    }

    // ==================== simple statements ====================

    private void parse_acc_descr(string line) {
        int brace = line.index_of_char('{');
        if (brace >= 0) {
            int close = line.index_of_char('}', brace);
            if (close > brace) {
                diagram.acc_descr = line.substring(brace + 1, close - brace - 1).strip();
                return;
            }
        }
        int c = line.index_of_char(':');
        if (c >= 0) diagram.acc_descr = line.substring(c + 1).strip();
    }

    private void parse_direction(string line, int source_line) {
        string dir = line.substring(9).strip();
        switch (dir) {
            case "TD":
            case "TB":
                diagram.direction = "TB";
                return;
            case "BT":
            case "LR":
            case "RL":
                diagram.direction = dir;
                return;
            default:
                error_at(source_line, "direction must be one of TB, TD, BT, LR, RL (got \"%s\")".printf(dir));
                return;
        }
    }

    // `systemBoundary Shop[Online Shop]@{ type: package }:::framed`
    private void parse_boundary(string line, int source_line) {
        if (current_boundary != null) {
            error_at(source_line, "system boundaries cannot be nested");
            current_boundary = null;
        }
        int i = 15;   // after "systemBoundary"
        var r = read_entity_ref(line, ref i, source_line);
        if (r == null) {
            error_at(source_line, "systemBoundary needs a name");
            return;
        }
        if (r.stereotype != null) {
            error_at(source_line, "a systemBoundary takes no <<stereotype>>");
        }
        var boundary = diagram.find_boundary(r.id);
        if (boundary == null) {
            boundary = new MermaidUseCaseBoundary(r.id, r.label, source_line);
            diagram.boundaries.add(boundary);
        }
        foreach (string c in r.classes) boundary.classes.add(c);
        apply_metadata(boundary, r, "boundary", source_line);
        current_boundary = boundary;
    }

    // `note for Login "Requires MFA for admins"`
    private void parse_note(string line, int source_line) {
        string rest = line.substring(4).strip();
        if (!first_word(rest).down().has_prefix("for")) {
            error_at(source_line, "a note is written `note for <id> <label>`");
            return;
        }
        rest = rest.substring(3).strip();
        int sp = 0;
        while (sp < rest.length && is_word_char(rest[sp])) sp++;
        string target = rest.substring(0, sp);
        if (target.length == 0) {
            error_at(source_line, "`note for` needs a target id");
            return;
        }
        string label_src = rest.substring(sp).strip();
        bool markdown;
        string label = read_label_text(label_src, out markdown);
        if (label.length == 0) {
            error_at(source_line, "`note for %s` needs a label".printf(target));
            return;
        }
        var note = new MermaidUseCaseNote("note-%d".printf(note_counter++), target, label, source_line);
        note.label_markdown = markdown;
        diagram.notes.add(note);
    }

    // `json config @{ "retries": 3 }:::wide`
    private void parse_json(string line, int source_line) {
        int at = line.index_of_char('@');
        int brace = at >= 0 ? line.index_of_char('{', at) : -1;
        if (brace < 0) {
            error_at(source_line, "a json node is written `json <id> @{ … }`");
            return;
        }
        string id = line.substring(4, at - 4).strip();
        if (id.length == 0) {
            error_at(source_line, "a json node needs an id");
            return;
        }
        int close = matching_brace(line, brace);
        if (close < 0) {
            error_at(source_line, "unterminated json body for \"%s\"".printf(id));
            return;
        }
        string body = line.substring(brace, close - brace + 1);
        var node = new MermaidUseCaseJsonNode(id, body, source_line);
        read_json_pairs(node);
        string tail = line.substring(close + 1).strip();
        if (tail.has_prefix(":::")) {
            foreach (string c in split_commas(tail.substring(3))) node.classes.add(c);
        }
        diagram.json_nodes.add(node);
    }

    // `classDef critical,urgent fill:#f96,stroke:#333`
    private void parse_class_def(string line, int source_line) {
        string rest = line.substring(8).strip();
        int at;
        var ids = read_comma_ids(rest, out at);
        if (ids.size == 0) {
            error_at(source_line, "classDef needs at least one class name");
            return;
        }
        var styles = split_commas(rest.substring(at));
        foreach (string id in ids) {
            var def = new MermaidUseCaseClassDef(id);
            foreach (string s in styles) def.styles.add(s);
            diagram.class_defs.add(def);
        }
    }

    // `class Delete,Archive critical,urgent`
    private void parse_class(string line, int source_line) {
        string rest = line.substring(5).strip();
        int at;
        var targets = read_comma_ids(rest, out at);
        var names = split_commas(rest.substring(at));
        if (targets.size == 0 || names.size == 0) {
            error_at(source_line, "`class` needs targets and at least one class name");
            return;
        }
        foreach (string t in targets) {
            if (!add_classes(t, names)) {
                error_at(source_line, "`class` target \"%s\" is unresolved".printf(t));
            }
        }
    }

    // `style Admin fill:#eef,stroke-dasharray:5 5`
    private void parse_style(string line, int source_line) {
        string rest = line.substring(5).strip();
        int at;
        var targets = read_comma_ids(rest, out at);
        var styles = split_commas(rest.substring(at));
        if (targets.size != 1 || styles.size == 0) {
            error_at(source_line, "`style` takes one target and a style list");
            return;
        }
        var el = diagram.find_element(targets.get(0));
        if (el != null) {
            foreach (string s in styles) el.styles.add(s);
            return;
        }
        foreach (var r in diagram.relations) {
            if (r.explicit_id && r.id == targets.get(0)) {
                foreach (string s in styles) r.styles.add(s);
                return;
            }
        }
        error_at(source_line, "`style` target \"%s\" is unresolved".printf(targets.get(0)));
    }

    private bool add_classes(string target, Gee.ArrayList<string> names) {
        var el = diagram.find_element(target);
        if (el != null) {
            foreach (string n in names) el.classes.add(n);
            return true;
        }
        foreach (var r in diagram.relations) {
            if (r.explicit_id && r.id == target) {
                foreach (string n in names) r.classes.add(n);
                return true;
            }
        }
        return false;
    }

    // ==================== actors ====================

    /**
     * `actor Admin` / `actor Admin, Guest` / `actor Admin --> Login`.
     * mermaid's grammar is an OR: a comma list OR a relation tail, never both.
     */
    private void parse_actor_statement(string rest, int source_line) {
        int i = 0;
        var first = read_entity_ref(rest, ref i, source_line);
        if (first == null) {
            error_at(source_line, "`actor` needs a name");
            return;
        }
        var actor = declare_actor(first, source_line);

        skip_ws(rest, ref i);
        if (i >= rest.length) return;

        if (rest[i] == ',') {
            while (i < rest.length && rest[i] == ',') {
                i++;
                var next = read_entity_ref(rest, ref i, source_line);
                if (next == null) {
                    error_at(source_line, "trailing comma in an `actor` list");
                    return;
                }
                declare_actor(next, source_line);
                skip_ws(rest, ref i);
            }
            if (i < rest.length) {
                error_at(source_line, "an `actor` list cannot also carry a relation");
            }
            return;
        }

        if (current_boundary != null) {
            error_at(source_line, "relations are not allowed inside a systemBoundary");
        }
        parse_relation_tail(rest, ref i, actor.id, source_line);
    }

    private MermaidUseCaseActor declare_actor(EntityRef r, int source_line) {
        var actor = diagram.find_actor(r.id);
        if (actor == null) {
            if (diagram.kind_of(r.id) != null) {
                error_at(source_line, "ID \"%s\" is already declared as a %s".printf(
                    r.id, diagram.kind_of(r.id)));
            }
            actor = new MermaidUseCaseActor(r.id, r.label, source_line);
            diagram.actors.add(actor);
        } else if (r.has_label && actor.label != r.label) {
            error_at(source_line, "ID \"%s\" has conflicting labels".printf(r.id));
        }
        actor.label_markdown = r.label_markdown || actor.label_markdown;
        if (r.stereotype != null) actor.stereotype = r.stereotype;
        foreach (string c in r.classes) actor.classes.add(c);
        if (current_boundary != null) {
            actor.parent_id = current_boundary.id;
            if (!current_boundary.members.contains(actor.id)) current_boundary.members.add(actor.id);
        }
        apply_metadata(actor, r, "actor", source_line);
        return actor;
    }

    // ==================== entities and relations ====================

    private void parse_entity_statement(string line, int source_line) {
        int i = 0;
        var left = read_entity_ref(line, ref i, source_line);
        if (left == null) {
            error_at(source_line, "unrecognised usecase statement: %s".printf(line));
            return;
        }

        skip_ws(line, ref i);
        // A bare `id@{ … }` line re-targets metadata at an existing element.
        if (i >= line.length && left.has_metadata && !left.has_label &&
            left.stereotype == null && left.classes.size == 0 &&
            diagram.kind_of(left.id) != null) {
            apply_metadata_to_existing(left, source_line);
            return;
        }

        var item = declare_use_case(left, source_line, i >= line.length);
        if (i >= line.length) return;
        if (current_boundary != null) {
            error_at(source_line, "relations are not allowed inside a systemBoundary");
        }
        parse_relation_tail(line, ref i, item != null ? item.id : left.id, source_line);
    }

    private MermaidUseCaseItem? declare_use_case(EntityRef r, int source_line, bool declaration) {
        var existing = diagram.find_element(r.id);
        if (existing != null && !(existing is MermaidUseCaseItem)) {
            // An actor or json node named in a relation keeps its own kind.
            if (r.has_label || r.has_metadata || r.stereotype != null) {
                error_at(source_line, "ID \"%s\" is already declared as a %s".printf(
                    r.id, diagram.kind_of(r.id)));
            }
            foreach (string c in r.classes) ((MermaidUseCaseElement) existing).classes.add(c);
            return null;
        }

        var item = diagram.find_use_case(r.id);
        if (item == null) {
            item = new MermaidUseCaseItem(r.id, r.label, source_line);
            item.shape = r.has_shape ? r.shape : MermaidUseCaseShape.ELLIPSE;
            diagram.use_cases.add(item);
        } else {
            if (r.has_label && item.label != r.label) {
                error_at(source_line, "ID \"%s\" has conflicting labels".printf(r.id));
            }
            if (r.has_shape && item.shape != r.shape) {
                error_at(source_line, "Use case \"%s\" has conflicting shapes".printf(r.id));
            }
            if (r.has_label) item.label = r.label;
            if (r.has_shape) item.shape = r.shape;
        }
        item.label_markdown = r.label_markdown || item.label_markdown;
        if (r.stereotype != null) item.stereotype = r.stereotype;
        // mermaid rejects `:::` on an endpoint that does not also declare the node.
        if (r.classes.size > 0 && !(declaration || r.has_label || r.has_metadata || r.stereotype != null)) {
            error_at(source_line,
                "Relationship endpoint \"%s\" uses ::: without declaring the node".printf(r.id));
        }
        foreach (string c in r.classes) item.classes.add(c);
        if (current_boundary != null) {
            item.parent_id = current_boundary.id;
            if (!current_boundary.members.contains(item.id)) current_boundary.members.add(item.id);
        }
        apply_metadata(item, r, "usecase", source_line);
        return item;
    }

    /**
     * `(e1@)? arrow entityName`, where `arrow` may be the labelled sandwich
     * `-- label -->`.
     */
    private void parse_relation_tail(string s, ref int i, string source_id, int source_line) {
        skip_ws(s, ref i);

        // An explicit edge id: `e1@-->`, an identifier followed by a bare `@`
        // that is not the `@{` of metadata.
        string? edge_id = null;
        int save = i;
        int j = i;
        while (j < s.length && is_word_char(s[j])) j++;
        if (j > i && j < s.length && s[j] == '@' && !(j + 1 < s.length && s[j + 1] == '{')) {
            edge_id = s.substring(i, j - i);
            i = j + 1;
        } else {
            i = save;
        }

        var op = read_arrow(s, i);
        if (op == null) {
            error_at(source_line, "expected a relation arrow after \"%s\"".printf(source_id));
            return;
        }
        i += op.text.length;

        var kind = MermaidUseCaseRelationKind.ASSOCIATION;
        string? label = null;
        bool label_markdown = false;
        var arrow = op.arrow;
        int minlen = op.minlen;

        if (op.semantic) {
            // `..>: include Target` / `..>: extend Target`
            skip_ws(s, ref i);
            if (i >= s.length || s[i] != ':') {
                error_at(source_line, "`..>` must be written `..>: include` or `..>: extend`");
                return;
            }
            i++;
            skip_ws(s, ref i);
            int k = i;
            while (k < s.length && is_word_char(s[k])) k++;
            string word = s.substring(i, k - i).down();
            if (word != "include" && word != "extend") {
                error_at(source_line, "`..>:` must be followed by include or extend");
                return;
            }
            i = k;
            kind = word == "include" ? MermaidUseCaseRelationKind.INCLUDE
                                     : MermaidUseCaseRelationKind.EXTEND;
            label = word;
            arrow = MermaidUseCaseArrow.SOLID_ARROW;
            minlen = 1;
        } else if (op.labelable) {
            // The sandwich: a label, then a closing operator. Only `--` and
            // `<--` may open one, and only when a closing operator follows.
            int probe = i;
            int found = -1;
            ArrowOp? closing = null;
            while (probe < s.length) {
                var cand = read_arrow(s, probe);
                if (cand != null) {
                    found = probe;
                    closing = cand;
                    break;
                }
                probe++;
            }
            if (closing != null && found > i) {
                if (!op.exact_two) {
                    error_at(source_line,
                        "a labelled relation must open with `--` or `<--`, not `%s`".printf(op.text));
                }
                label = read_label_text(s.substring(i, found - i).strip(), out label_markdown);
                i = found + closing.text.length;
                if (op.arrow == MermaidUseCaseArrow.BACK_ARROW) {
                    arrow = MermaidUseCaseArrow.BACK_ARROW;
                    minlen = closing.minlen;
                } else if (closing.arrow == MermaidUseCaseArrow.CIRCLE_ARROW ||
                           closing.arrow == MermaidUseCaseArrow.CROSS_ARROW) {
                    arrow = closing.arrow;
                    minlen = 1;
                } else {
                    arrow = closing.arrow;
                    minlen = closing.minlen;
                }
                if (closing.arrow == MermaidUseCaseArrow.GENERALIZATION_MARK) {
                    arrow = MermaidUseCaseArrow.SOLID_ARROW;
                    kind = MermaidUseCaseRelationKind.GENERALIZATION;
                }
            }
        }

        if (op.arrow == MermaidUseCaseArrow.GENERALIZATION_MARK && kind == MermaidUseCaseRelationKind.ASSOCIATION) {
            kind = MermaidUseCaseRelationKind.GENERALIZATION;
            arrow = MermaidUseCaseArrow.SOLID_ARROW;
        }

        var right = read_entity_ref(s, ref i, source_line);
        if (right == null) {
            error_at(source_line, "a relation needs a target after the arrow");
            return;
        }
        declare_use_case(right, source_line, false);

        string id = edge_id ?? "edge-%d".printf(relation_counter);
        relation_counter++;
        var rel = new MermaidUseCaseRelation(id, source_id, right.id, source_line);
        rel.explicit_id = edge_id != null;
        rel.kind = kind;
        rel.arrow = arrow;
        rel.label = label != null && label.length > 0 ? label : null;
        rel.label_markdown = label_markdown;
        rel.minlen = int.max(1, minlen);
        diagram.relations.add(rel);

        validate_relation(rel, source_line);

        skip_ws(s, ref i);
        if (i < s.length) {
            error_at(source_line, "unexpected text after the relation: \"%s\"".printf(s.substring(i)));
        }
    }

    /**
     * mermaid's validateRelationship: include/extend need two use cases,
     * a generalization needs two elements of the same kind, and a boundary id
     * is never a relation endpoint.
     */
    private void validate_relation(MermaidUseCaseRelation rel, int source_line) {
        string? sk = diagram.kind_of(rel.source);
        string? tk = diagram.kind_of(rel.target);
        if (sk == "boundary" || tk == "boundary") {
            error_at(source_line, "a systemBoundary cannot be a relation endpoint");
            return;
        }
        if (rel.kind == MermaidUseCaseRelationKind.INCLUDE ||
            rel.kind == MermaidUseCaseRelationKind.EXTEND) {
            if (sk != "usecase" || tk != "usecase") {
                error_at(source_line, "include/extend require a use case on both ends");
            }
            return;
        }
        if (rel.kind == MermaidUseCaseRelationKind.GENERALIZATION && sk != tk) {
            error_at(source_line, "a generalization needs two actors or two use cases");
            return;
        }
        if ((sk == "json" || tk == "json") &&
            rel.arrow != MermaidUseCaseArrow.SOLID_ARROW &&
            rel.arrow != MermaidUseCaseArrow.BACK_ARROW &&
            rel.arrow != MermaidUseCaseArrow.LINE_SOLID) {
            error_at(source_line, "a json node only takes -->, <-- or -- relations");
        }
    }

    // ==================== arrow scanning ====================

    private class ArrowOp {
        public string text;
        public MermaidUseCaseArrow arrow;
        public int minlen = 1;
        public bool semantic = false;    // `..>`
        public bool labelable = false;   // may open a `-- label -->` sandwich
        public bool exact_two = false;   // the opening operator was exactly `--` / `<--`
    }

    /**
     * The relation operator starting at `i`, or null. Longest match wins, so
     * `--|>` beats `--` and `-->` beats `--`.
     */
    private static ArrowOp? read_arrow(string s, int i) {
        if (i >= s.length) return null;
        var op = new ArrowOp();

        // `..>`
        if (s[i] == '.' && i + 2 < s.length && s[i + 1] == '.' && s[i + 2] == '>') {
            op.text = "..>";
            op.arrow = MermaidUseCaseArrow.SOLID_ARROW;
            op.semantic = true;
            return op;
        }
        // `o--` / `x--`
        if ((s[i] == 'o' || s[i] == 'x') && dash_run(s, i + 1) >= 2) {
            int n = dash_run(s, i + 1);
            op.text = s.substring(i, 1 + n);
            op.arrow = s[i] == 'o' ? MermaidUseCaseArrow.CIRCLE_ARROW_REVERSED
                                   : MermaidUseCaseArrow.CROSS_ARROW_REVERSED;
            op.minlen = 1;
            op.labelable = true;
            return op;
        }
        // `<--`, `<---`, …
        if (s[i] == '<' && dash_run(s, i + 1) >= 2) {
            int n = dash_run(s, i + 1);
            op.text = s.substring(i, 1 + n);
            op.arrow = MermaidUseCaseArrow.BACK_ARROW;
            op.minlen = int.max(1, n - 1);
            op.labelable = true;
            op.exact_two = n == 2;
            return op;
        }
        if (s[i] != '-') return null;
        int dashes = dash_run(s, i);
        if (dashes < 2) return null;
        int after = i + dashes;

        if (after < s.length && s[after] == '>') {
            op.text = s.substring(i, dashes + 1);
            op.arrow = MermaidUseCaseArrow.SOLID_ARROW;
            op.minlen = int.max(1, dashes - 1);
            return op;
        }
        if (after + 1 < s.length && s[after] == '|' && s[after + 1] == '>') {
            op.text = s.substring(i, dashes + 2);
            op.arrow = MermaidUseCaseArrow.GENERALIZATION_MARK;
            op.minlen = 1;
            return op;
        }
        if (after < s.length && s[after] == 'o') {
            op.text = s.substring(i, dashes + 1);
            op.arrow = MermaidUseCaseArrow.CIRCLE_ARROW;
            op.minlen = 1;
            return op;
        }
        if (after < s.length && s[after] == 'x') {
            op.text = s.substring(i, dashes + 1);
            op.arrow = MermaidUseCaseArrow.CROSS_ARROW;
            op.minlen = 1;
            return op;
        }
        op.text = s.substring(i, dashes);
        op.arrow = MermaidUseCaseArrow.LINE_SOLID;
        op.minlen = int.max(1, dashes - 1);
        op.labelable = true;
        op.exact_two = dashes == 2;
        return op;
    }

    private static int dash_run(string s, int i) {
        int n = 0;
        while (i + n < s.length && s[i + n] == '-') n++;
        return n;
    }

    // ==================== entity references ====================

    private class EntityRef {
        public string id;
        public string label;
        public bool label_markdown = false;
        public bool has_label = false;
        public bool has_shape = false;
        public MermaidUseCaseShape shape = MermaidUseCaseShape.ELLIPSE;
        public bool has_metadata = false;
        public Gee.HashMap<string, string> metadata = new Gee.HashMap<string, string>();
        public string? stereotype = null;
        public Gee.ArrayList<string> classes = new Gee.ArrayList<string>();
    }

    /**
     * `IDENT`, `IDENT(Label)`, `IDENT[Label]`, `"Quoted"` or a markdown string,
     * followed in this fixed order by `@{ … }`, `<<stereotype>>` and
     * `:::class,list`. Advances `i` past everything it consumed.
     */
    private EntityRef? read_entity_ref(string s, ref int i, int source_line) {
        skip_ws(s, ref i);
        if (i >= s.length) return null;
        var r = new EntityRef();

        if (s[i] == '"' || s[i] == '\'') {
            int end;
            bool markdown;
            string? text = read_quoted(s, i, out end, out markdown);
            if (text == null) {
                error_at(source_line, "unterminated string");
                return null;
            }
            r.label = text;
            r.label_markdown = markdown;
            r.has_label = true;
            r.id = generated_id(text);
            i = end;
        } else {
            int start = i;
            while (i < s.length && is_word_char(s[i])) i++;
            if (i == start) return null;
            r.id = s.substring(start, i - start);
            r.label = r.id;
            // `(Label)` is an ellipse, `[Label]` a rectangle.
            if (i < s.length && (s[i] == '(' || s[i] == '[')) {
                char open = s[i];
                char close = open == '(' ? ')' : ']';
                int end = s.index_of_char(close, i + 1);
                if (end < 0) {
                    error_at(source_line, "unterminated %c…%c label for \"%s\"".printf(open, close, r.id));
                    return r;
                }
                bool markdown;
                r.label = read_label_text(s.substring(i + 1, end - i - 1).strip(), out markdown);
                r.label_markdown = markdown;
                r.has_label = true;
                r.has_shape = true;
                r.shape = open == '(' ? MermaidUseCaseShape.ELLIPSE : MermaidUseCaseShape.RECT;
                i = end + 1;
            }
        }

        // `@{ key: value, … }`
        if (i + 1 < s.length && s[i] == '@' && s[i + 1] == '{') {
            int close = matching_brace(s, i + 1);
            if (close < 0) {
                error_at(source_line, "unterminated @{ … } for \"%s\"".printf(r.id));
                return r;
            }
            read_metadata(s.substring(i + 2, close - i - 2), r, source_line);
            r.has_metadata = true;
            i = close + 1;
        }

        // `<<stereotype>>`
        if (i + 1 < s.length && s[i] == '<' && s[i + 1] == '<') {
            int close = s.index_of(">>", i + 2);
            if (close < 0) {
                error_at(source_line, "unterminated <<stereotype>> for \"%s\"".printf(r.id));
                return r;
            }
            r.stereotype = s.substring(i + 2, close - i - 2).strip();
            i = close + 2;
        }

        // `:::class,list`
        if (i + 2 < s.length && s[i] == ':' && s[i + 1] == ':' && s[i + 2] == ':') {
            i += 3;
            int start = i;
            while (i < s.length && (is_word_char(s[i]) || s[i] == ',' || s[i] == '-')) i++;
            foreach (string c in split_commas(s.substring(start, i - start))) r.classes.add(c);
        }

        return r;
    }

    // `key: value` pairs; mermaid accepts identifiers, quoted strings and the
    // booleans, but never a bare number.
    private void read_metadata(string body, EntityRef r, int source_line) {
        foreach (string part in body.replace("\n", ",").split(",")) {
            string p = part.strip();
            if (p.length == 0) continue;
            int c = p.index_of_char(':');
            if (c < 0) {
                error_at(source_line, "metadata needs `key: value` (got \"%s\")".printf(p));
                continue;
            }
            string key = unquote(p.substring(0, c).strip());
            string value = unquote(p.substring(c + 1).strip());
            r.metadata.set(key, value);
        }
    }

    // mermaid's only metadata keys, each valid on one kind of element.
    private void apply_metadata(MermaidUseCaseElement el, EntityRef r, string kind, int source_line) {
        foreach (var e in r.metadata.entries) {
            string key = e.key;
            string value = e.value;
            if (key == "business" && (kind == "actor" || kind == "usecase")) {
                el.business = value == "true";
                continue;
            }
            if (key == "type" && kind == "actor") {
                var actor = (MermaidUseCaseActor) el;
                switch (value) {
                    case "normal":  actor.actor_type = MermaidActorType.NORMAL;  break;
                    case "hollow":  actor.actor_type = MermaidActorType.HOLLOW;  break;
                    case "awesome": actor.actor_type = MermaidActorType.AWESOME; break;
                    default:
                        error_at(source_line, "actor type must be normal, hollow or awesome (got \"%s\")".printf(value));
                        break;
                }
                continue;
            }
            if (key == "icon" && kind == "actor") {
                var actor = (MermaidUseCaseActor) el;
                actor.icon = value;
                actor.actor_type = MermaidActorType.ICON;
                continue;
            }
            if (key == "type" && kind == "boundary") {
                var b = (MermaidUseCaseBoundary) el;
                if (value == "package") b.boundary_type = MermaidBoundaryType.PACKAGE;
                else if (value == "rect") b.boundary_type = MermaidBoundaryType.RECT;
                else error_at(source_line, "boundary type must be rect or package (got \"%s\")".printf(value));
                continue;
            }
            error_at(source_line, "Metadata property \"%s\" is invalid for %s \"%s\"".printf(key, kind, el.id));
        }
    }

    // A standalone `id@{ … }` line, which may also target an edge.
    private void apply_metadata_to_existing(EntityRef r, int source_line) {
        string? kind = diagram.kind_of(r.id);
        if (kind == "edge") {
            foreach (var rel in diagram.relations) {
                if (!rel.explicit_id || rel.id != r.id) continue;
                foreach (var e in r.metadata.entries) {
                    if (e.key == "animate") rel.animate = e.value == "true";
                    else if (e.key == "animation") { rel.animation = e.value; rel.animate = true; }
                    else error_at(source_line,
                        "Metadata property \"%s\" is invalid for edge \"%s\"".printf(e.key, r.id));
                }
            }
            return;
        }
        var el = diagram.find_element(r.id);
        if (el == null) {
            error_at(source_line, "Metadata target \"%s\" is unresolved".printf(r.id));
            return;
        }
        apply_metadata(el, r, kind, source_line);
    }

    // ==================== lexical helpers ====================

    private static void skip_ws(string s, ref int i) {
        while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++;
    }

    private static bool is_word_char(char c) {
        return c.isalnum() || c == '_';
    }

    private static string first_word(string line) {
        int i = 0;
        while (i < line.length && !line[i].isspace() && line[i] != ':' && line[i] != '{') i++;
        return line.substring(0, i);
    }

    /**
     * A quoted run starting at `i`: `"text"`, `'text'` or the markdown form
     * ``"`text`"``. `end` is the index just past the closing quote.
     */
    private static string? read_quoted(string s, int i, out int end, out bool markdown) {
        end = i;
        markdown = false;
        if (i >= s.length) return null;
        if (s[i] == '"' && i + 1 < s.length && s[i + 1] == '`') {
            int close = s.index_of("`\"", i + 2);
            if (close < 0) return null;
            markdown = true;
            end = close + 2;
            return s.substring(i + 2, close - i - 2);
        }
        char q = s[i];
        int close2 = s.index_of_char(q, i + 1);
        if (close2 < 0) return null;
        end = close2 + 1;
        return s.substring(i + 1, close2 - i - 1);
    }

    // A label: a quoted or markdown string, otherwise the verbatim run.
    private static string read_label_text(string src, out bool markdown) {
        markdown = false;
        string t = src.strip();
        if (t.length == 0) return "";
        if (t.has_prefix("\"`") && t.has_suffix("`\"") && t.length >= 4) {
            markdown = true;
            return t.substring(2, t.length - 4);
        }
        if (t.length >= 2 && ((t.has_prefix("\"") && t.has_suffix("\"")) ||
                              (t.has_prefix("'") && t.has_suffix("'")))) {
            return t.substring(1, t.length - 2);
        }
        return t;
    }

    private static string unquote(string s) {
        bool md;
        return read_label_text(s, out md);
    }

    // mermaid's id generation for a quoted name: every non-word char becomes _.
    private static string generated_id(string label) {
        var sb = new StringBuilder();
        for (int i = 0; i < label.length; i++) {
            sb.append_c(is_word_char(label[i]) ? label[i] : '_');
        }
        return sb.str;
    }

    // The index of the `}` matching the `{` at `open`, or -1.
    private static int matching_brace(string s, int open) {
        int depth = 0;
        char quote = '\0';
        for (int i = open; i < s.length; i++) {
            char c = s[i];
            if (quote != '\0') {
                if (c == '\\') { i++; continue; }
                if (c == quote) quote = '\0';
                continue;
            }
            if (c == '"' || c == '\'') { quote = c; continue; }
            if (c == '{') depth++;
            else if (c == '}' && --depth == 0) return i;
        }
        return -1;
    }

    /**
     * The leading comma-joined identifier list of a `classDef` / `class` /
     * `style` statement; `after` is where it ended. mermaid decides the split
     * the same way: identifiers stay in the list only while commas join them.
     */
    private static Gee.ArrayList<string> read_comma_ids(string s, out int after) {
        var ids = new Gee.ArrayList<string>();
        int i = 0;
        while (true) {
            skip_ws(s, ref i);
            int start = i;
            while (i < s.length && (is_word_char(s[i]) || s[i] == '-')) i++;
            if (i == start) break;
            ids.add(s.substring(start, i - start));
            int save = i;
            skip_ws(s, ref i);
            if (i < s.length && s[i] == ',') { i++; continue; }
            i = save;
            break;
        }
        after = i;
        return ids;
    }

    // Commas split the list; `\,` is a literal comma inside a CSS value.
    private static Gee.ArrayList<string> split_commas(string s) {
        var result = new Gee.ArrayList<string>();
        var cur = new StringBuilder();
        for (int i = 0; i < s.length; i++) {
            if (s[i] == '\\' && i + 1 < s.length && s[i + 1] == ',') {
                cur.append_c(',');
                i++;
                continue;
            }
            if (s[i] == ',') {
                string t = cur.str.strip();
                if (t.length > 0) result.add(t);
                cur = new StringBuilder();
                continue;
            }
            cur.append_c(s[i]);
        }
        string last = cur.str.strip();
        if (last.length > 0) result.add(last);
        return result;
    }

    // The top-level `"key": value` pairs of a json body, for the rendered table.
    private static void read_json_pairs(MermaidUseCaseJsonNode node) {
        string body = node.body;
        int depth = 0;
        char quote = '\0';
        var cur = new StringBuilder();
        var parts = new Gee.ArrayList<string>();
        for (int i = 0; i < body.length; i++) {
            char c = body[i];
            if (quote != '\0') {
                cur.append_c(c);
                if (c == '\\' && i + 1 < body.length) { cur.append_c(body[++i]); continue; }
                if (c == quote) quote = '\0';
                continue;
            }
            if (c == '"') { quote = c; cur.append_c(c); continue; }
            if (c == '{' || c == '[') { depth++; if (depth > 1) cur.append_c(c); continue; }
            if (c == '}' || c == ']') { depth--; if (depth >= 1) cur.append_c(c); continue; }
            if (c == ',' && depth == 1) {
                parts.add(cur.str);
                cur = new StringBuilder();
                continue;
            }
            cur.append_c(c);
        }
        if (cur.str.strip().length > 0) parts.add(cur.str);

        foreach (string part in parts) {
            string p = part.strip();
            if (p.length == 0) continue;
            int c = p.index_of_char(':');
            if (c < 0) continue;
            node.keys.add(unquote(p.substring(0, c).strip()));
            node.values.add(p.substring(c + 1).strip());
        }
    }

    private void error_at(int line, string message) {
        diagram.errors.add(new ParseError(message, line, 0));
    }
}

}
