/* MermaidWardleyParser.vala — Mermaid `wardley-beta` map parser
 *
 * Written against mermaid 12.2.0's own langium grammar (wardley.langium, as
 * shipped in @mermaid-js/parser) and the AST consumer wardleyParser.ts:
 *
 *   Wardley    : NEWLINE* 'wardley-beta' (NEWLINE | TitleAndAccessibilities | Statement)*
 *   Statement  : Size | Evolution | Anchor | Component | Link | Evolve | Pipeline
 *              | Note | Annotations | Annotation | Accelerator | Deaccelerator
 *   Size       : 'size' '[' INT ',' INT ']'
 *   Evolution  : 'evolution' Stage ('->' Stage)+
 *   Stage      : NAME ('@' NUMBER)? ('/' NAME)?
 *   Anchor     : 'anchor' NAME '[' visibility ',' evolution ']'
 *   Component  : 'component' NAME '[' visibility ',' evolution ']' Label? Decorator?
 *                ('inertia' | '(' 'inertia' ')')?
 *   Label      : 'label' '[' '-'? INT ',' '-'? INT ']'
 *   Decorator  : '(' ('build'|'buy'|'outsource'|'market') ')'
 *   Link       : NAME PORT? ARROW? NAME PORT? (';' label)?
 *   Evolve     : 'evolve' NAME NUMBER
 *   Pipeline   : 'pipeline' NAME '{' NEWLINE+ ('component' NAME '[' evolution ']' Label?)+ '}'
 *   Note       : 'note' STRING '[' visibility ',' evolution ']'
 *   Annotations: 'annotations' '[' x ',' y ']'
 *   Annotation : 'annotation' INT ',' '[' x ',' y ']' STRING
 *   Accelerator / Deaccelerator : KEYWORD NAME '[' x ',' y ']'
 *
 * The grammar is line-terminated throughout (every rule ends in EOL), so this
 * is a line parser rather than a token-stream one, like the other line-based
 * Mermaid parsers in this directory.
 *
 * Deliberate leniency over mermaid: mermaid's WARDLEY_NUMBER terminal is
 * /[0-9]+\.[0-9]+/ and so rejects `[1, 0]`, while we accept a plain integer
 * everywhere a coordinate is read. Everything else follows the grammar.
 */
namespace GDiagram {

public class MermaidWardleyParser : Object {
    private MermaidWardley diagram;

    public MermaidWardleyParser() {}

    public MermaidWardley parse(string source) {
        this.diagram = new MermaidWardley();
        parse_wardley(source);
        return diagram;
    }

    // ==================== driver ====================

    private void parse_wardley(string source) {
        string[] lines = source.split("\n");
        bool in_front_matter = false;
        bool seen_content = false;

        for (int i = 0; i < lines.length; i++) {
            string raw = lines[i];
            string trimmed = strip_comment(raw).strip();

            // YAML front matter, as every other Mermaid parser here handles it.
            if (trimmed == "---" && (!seen_content || in_front_matter)) {
                in_front_matter = !in_front_matter;
                continue;
            }
            if (in_front_matter) {
                if (trimmed.has_prefix("title:") && diagram.title == null) {
                    diagram.title = strip_quotes(trimmed.substring(6).strip());
                }
                continue;
            }
            if (trimmed.length == 0) continue;
            seen_content = true;

            string lower = trimmed.down();
            if (lower == "wardley-beta" || lower.has_prefix("wardley-beta ")) continue;
            if (lower == "wardley") continue;

            // title / accTitle / accDescr (TitleAndAccessibilities)
            if (lower.has_prefix("title ") || lower == "title") {
                diagram.title = trimmed.length > 5 ? trimmed.substring(6).strip() : "";
                continue;
            }
            if (lower.has_prefix("acctitle")) {
                int c = trimmed.index_of_char(':');
                if (c >= 0) diagram.acc_title = trimmed.substring(c + 1).strip();
                continue;
            }
            if (lower.has_prefix("accdescr")) {
                int c = trimmed.index_of_char(':');
                if (c >= 0) diagram.acc_descr = trimmed.substring(c + 1).strip();
                continue;
            }

            if (parse_keyword_statement(trimmed, lower, lines, i, out i)) continue;

            // Anything left with a link separator is a link; anything else is junk.
            if (!parse_link(trimmed, i + 1)) {
                error_at(i + 1, "Unrecognised wardley statement: %s".printf(trimmed));
            }
        }

        // `evolve` needs its component's visibility, which may be declared after
        // it, so the trends are resolved once the whole map is read.
        resolve_trends();
    }

    /**
     * One keyword-led statement. `next_i` lets `pipeline` swallow the block it
     * spans; every other statement leaves the cursor where it was.
     */
    private bool parse_keyword_statement(string line, string lower, string[] lines, int i, out int next_i) {
        next_i = i;
        if (lower.has_prefix("size ") || lower.has_prefix("size[")) {
            parse_size(line.substring(4), i + 1);
            return true;
        }
        if (lower.has_prefix("evolution ")) {
            parse_evolution(line.substring(10), i + 1);
            return true;
        }
        if (lower.has_prefix("anchor ")) {
            parse_point_node(line.substring(7), WardleyNodeKind.ANCHOR, i + 1);
            return true;
        }
        if (lower.has_prefix("component ")) {
            parse_point_node(line.substring(10), WardleyNodeKind.COMPONENT, i + 1);
            return true;
        }
        if (lower.has_prefix("evolve ")) {
            parse_evolve(line.substring(7), i + 1);
            return true;
        }
        if (lower.has_prefix("pipeline ")) {
            next_i = parse_pipeline(line.substring(9), lines, i);
            return true;
        }
        if (lower.has_prefix("note ")) {
            parse_note(line.substring(5), i + 1);
            return true;
        }
        if (lower.has_prefix("annotations ") || lower.has_prefix("annotations[")) {
            parse_annotations_box(line.substring(11), i + 1);
            return true;
        }
        if (lower.has_prefix("annotation ")) {
            parse_annotation(line.substring(11), i + 1);
            return true;
        }
        if (lower.has_prefix("accelerator ")) {
            parse_accelerator(line.substring(12), false, i + 1);
            return true;
        }
        if (lower.has_prefix("deaccelerator ")) {
            parse_accelerator(line.substring(14), true, i + 1);
            return true;
        }
        return false;
    }

    // ==================== statements ====================

    // `size [1200, 800]`
    private void parse_size(string rest, int line) {
        string? body = bracket_body(rest);
        if (body == null) {
            error_at(line, "size needs [width, height]");
            return;
        }
        string[] parts = body.split(",");
        if (parts.length < 2) {
            error_at(line, "size needs [width, height]");
            return;
        }
        int w = int.parse(parts[0].strip());
        int h = int.parse(parts[1].strip());
        if (w <= 0 || h <= 0) {
            error_at(line, "size must be positive");
            return;
        }
        diagram.has_size = true;
        diagram.size_width = w;
        diagram.size_height = h;
    }

    // `evolution Genesis -> Custom Built @0.4 -> Product / Rental -> Commodity`
    private void parse_evolution(string rest, int line) {
        var stages = new Gee.ArrayList<string>();
        var boundaries = new Gee.ArrayList<double?>();
        foreach (string chunk in split_arrow(rest)) {
            string stage = chunk.strip();
            if (stage.length == 0) continue;
            // `@boundary` binds to the stage it follows.
            int at = stage.index_of_char('@');
            if (at >= 0) {
                string after = stage.substring(at + 1).strip();
                // The boundary ends at the `/` of a dual-label stage.
                int slash = after.index_of_char('/');
                string num = slash >= 0 ? after.substring(0, slash).strip() : after;
                string tail = slash >= 0 ? after.substring(slash) : "";
                boundaries.add(double.parse(num));
                stage = (stage.substring(0, at).strip() + " " + tail).strip();
            }
            // `Genesis / Concept` keeps both names, joined as mermaid joins them.
            int slash2 = stage.index_of_char('/');
            if (slash2 >= 0) {
                stage = "%s / %s".printf(stage.substring(0, slash2).strip(),
                                         stage.substring(slash2 + 1).strip());
            }
            stages.add(strip_quotes(stage));
        }
        if (stages.size < 2) {
            error_at(line, "evolution needs at least two stages separated by ->");
            return;
        }
        diagram.stages.clear();
        diagram.stages.add_all(stages);
        diagram.stage_boundaries.clear();
        diagram.stage_boundaries.add_all(boundaries);
    }

    // `anchor Business [0.95, 0.63]` / `component Kettle [0.43, 0.35] label [-57, 4] (build) inertia`
    private void parse_point_node(string rest, WardleyNodeKind kind, int line) {
        int open = rest.index_of_char('[');
        if (open < 0) {
            error_at(line, "a component needs [visibility, evolution]");
            return;
        }
        string name = strip_quotes(rest.substring(0, open).strip());
        if (name.length == 0) {
            error_at(line, "a component needs a name");
            return;
        }
        int close = rest.index_of_char(']', open);
        if (close < 0) {
            error_at(line, "unterminated [visibility, evolution] for \"%s\"".printf(name));
            return;
        }
        string[] coords = rest.substring(open + 1, close - open - 1).split(",");
        if (coords.length < 2) {
            error_at(line, "\"%s\" needs [visibility, evolution]".printf(name));
            return;
        }
        double vis, evo;
        if (!to_percent(coords[0], line, "%s visibility".printf(name), out vis)) return;
        if (!to_percent(coords[1], line, "%s evolution".printf(name), out evo)) return;

        var node = new WardleyMapNode(name, name, evo, vis, kind, line);
        string tail = rest.substring(close + 1);
        apply_label_offset(node, tail);
        node.source_strategy = read_strategy(tail);
        node.inertia = read_inertia(tail);
        add_node(node);
    }

    // `evolve Kettle 0.62` — the target visibility comes from the component later.
    private void parse_evolve(string rest, int line) {
        // The name may contain spaces, so the number is the last whitespace-separated word.
        string body = rest.strip();
        int sp = body.last_index_of_char(' ');
        int tab = body.last_index_of_char('\t');
        if (tab > sp) sp = tab;
        if (sp <= 0) {
            error_at(line, "evolve needs a component and a target evolution");
            return;
        }
        string name = strip_quotes(body.substring(0, sp).strip());
        double target;
        if (!to_percent(body.substring(sp + 1), line, "Evolve target for \"%s\"".printf(name), out target)) return;
        // target_y is filled in by resolve_trends() once every node is known.
        diagram.trends.add(new WardleyTrend(name, target, double.NAN, line));
    }

    /**
     * `pipeline Cup of Tea {` … `}`. Returns the index of the line the block
     * ends on, so the driver resumes after it.
     */
    private int parse_pipeline(string rest, string[] lines, int i) {
        int line = i + 1;
        string head = rest.strip();
        if (head.has_suffix("{")) head = head.substring(0, head.length - 1).strip();
        string parent = strip_quotes(head);
        if (parent.length == 0) {
            error_at(line, "pipeline needs a parent component");
            return i;
        }

        var parent_node = diagram.find_node(parent);
        if (parent_node == null) {
            error_at(line, "Pipeline \"%s\" must reference an existing component with coordinates.".printf(parent));
        }

        var pipeline = new WardleyPipeline(parent, line);
        diagram.pipelines.add(pipeline);
        if (parent_node != null) parent_node.is_pipeline_parent = true;

        // Walk to the closing brace. The opening brace may sit on the next line.
        int j = i;
        bool opened = rest.contains("{");
        while (j + 1 < lines.length) {
            j++;
            string body = strip_comment(lines[j]).strip();
            if (body.length == 0) continue;
            if (!opened) {
                if (body == "{" || body.has_prefix("{")) {
                    opened = true;
                    body = body.substring(1).strip();
                    if (body.length == 0) continue;
                } else {
                    // No block at all: not a pipeline body, give the line back.
                    return j - 1;
                }
            }
            if (body.has_prefix("}")) break;
            if (body.down().has_prefix("component ")) {
                parse_pipeline_component(pipeline, parent_node, body.substring(10), j + 1);
                continue;
            }
            error_at(j + 1, "only `component` statements may appear inside a pipeline");
        }
        return j;
    }

    // `component Hot Water [0.45] label [-14, 10]` — one coordinate only; the
    // visibility is the parent's, so the box is a horizontal band.
    private void parse_pipeline_component(WardleyPipeline pipeline, WardleyMapNode? parent,
                                          string rest, int line) {
        int open = rest.index_of_char('[');
        int close = open >= 0 ? rest.index_of_char(']', open) : -1;
        if (open < 0 || close < 0) {
            error_at(line, "a pipeline component needs [evolution]");
            return;
        }
        string name = strip_quotes(rest.substring(0, open).strip());
        double evo;
        if (!to_percent(rest.substring(open + 1, close - open - 1), line,
                        "Pipeline component \"%s\" evolution".printf(name), out evo)) return;

        string id = "%s_%s".printf(pipeline.node_id, name);
        var node = new WardleyMapNode(id, name, evo, parent != null ? parent.y : 0,
                                      WardleyNodeKind.PIPELINE_COMPONENT, line);
        apply_label_offset(node, rest.substring(close + 1));
        node.in_pipeline = true;
        add_node(node);
        pipeline.component_ids.add(id);
    }

    // `note "Standardising power" [0.33, 0.73]`
    private void parse_note(string rest, int line) {
        int open = rest.index_of_char('[');
        int close = open >= 0 ? rest.index_of_char(']', open) : -1;
        if (open < 0 || close < 0) {
            error_at(line, "a note needs [visibility, evolution]");
            return;
        }
        string text = strip_quotes(rest.substring(0, open).strip());
        string[] coords = rest.substring(open + 1, close - open - 1).split(",");
        if (coords.length < 2) {
            error_at(line, "a note needs [visibility, evolution]");
            return;
        }
        double vis, evo;
        if (!to_percent(coords[0], line, "Note \"%s\" visibility".printf(text), out vis)) return;
        if (!to_percent(coords[1], line, "Note \"%s\" evolution".printf(text), out evo)) return;
        diagram.notes.add(new WardleyNote(text, evo, vis, line));
    }

    /**
     * `annotations [0.03, 0.56]`. The langium grammar calls these fields `x`
     * and `y`, but wardleyParser.ts passes them to
     * `toCoordinates(visibility, evolution)`, which returns
     * `{ x: evolution, y: visibility }` — so the first number is the
     * visibility (vertical) and the second the evolution (horizontal), exactly
     * as for an anchor or a component. Verified against mermaid's own SVG: the
     * legend box of `annotations [0.03, 0.56]` lands at evolution 56%.
     */
    private void parse_annotations_box(string rest, int line) {
        string? body = bracket_body(rest);
        if (body == null) {
            error_at(line, "annotations needs [x, y]");
            return;
        }
        string[] parts = body.split(",");
        if (parts.length < 2) {
            error_at(line, "annotations needs [x, y]");
            return;
        }
        double vis, evo;
        if (!to_percent(parts[0], line, "Annotations box visibility", out vis)) return;
        if (!to_percent(parts[1], line, "Annotations box evolution", out evo)) return;
        diagram.has_annotations_box = true;
        diagram.annotations_box_x = evo;
        diagram.annotations_box_y = vis;
    }

    // `annotation 1, [0.43, 0.49] "Standardising power"`
    private void parse_annotation(string rest, int line) {
        int open = rest.index_of_char('[');
        int close = open >= 0 ? rest.index_of_char(']', open) : -1;
        if (open < 0 || close < 0) {
            error_at(line, "an annotation needs a number and [x, y]");
            return;
        }
        string num_part = rest.substring(0, open).strip();
        if (num_part.has_suffix(",")) num_part = num_part.substring(0, num_part.length - 1).strip();
        int number = int.parse(num_part);
        string[] parts = rest.substring(open + 1, close - open - 1).split(",");
        if (parts.length < 2) {
            error_at(line, "annotation %d needs [x, y]".printf(number));
            return;
        }
        // [visibility, evolution], as for every other coordinate — see
        // parse_annotations_box() for why the grammar's field names mislead.
        double vis, evo;
        if (!to_percent(parts[0], line, "Annotation %d visibility".printf(number), out vis)) return;
        if (!to_percent(parts[1], line, "Annotation %d evolution".printf(number), out evo)) return;
        string text = strip_quotes(rest.substring(close + 1).strip());
        var ann = new WardleyAnnotation(number, text.length > 0 ? text : null, line);
        ann.coordinates.add(new WardleyPoint(evo, vis));
        diagram.annotations.add(ann);
    }

    // `accelerator Electricity [0.6, 0.8]` / `deaccelerator Regulation [0.3, 0.4]`
    private void parse_accelerator(string rest, bool decelerating, int line) {
        int open = rest.index_of_char('[');
        int close = open >= 0 ? rest.index_of_char(']', open) : -1;
        if (open < 0 || close < 0) {
            error_at(line, "an accelerator needs [x, y]");
            return;
        }
        string name = strip_quotes(rest.substring(0, open).strip());
        string[] parts = rest.substring(open + 1, close - open - 1).split(",");
        if (parts.length < 2) {
            error_at(line, "\"%s\" needs [x, y]".printf(name));
            return;
        }
        // [visibility, evolution] again; see parse_annotations_box().
        double vis, evo;
        if (!to_percent(parts[0], line, "Accelerator \"%s\" visibility".printf(name), out vis)) return;
        if (!to_percent(parts[1], line, "Accelerator \"%s\" evolution".printf(name), out evo)) return;
        diagram.accelerators.add(new WardleyAccelerator(name, evo, vis, decelerating, line));
    }

    // ==================== links ====================

    // The link separators, longest first so `-.->` beats `->` and a flow arrow
    // beats a bare port.
    private const string[] FLOW_ARROWS = { "<>", "<", ">" };
    private const string[] PORTS = { "+<>", "+>", "+<" };
    private const string[] PLAIN_ARROWS = { "-.->", "-->", "->", ">" };

    /**
     * `Business->Cup of Tea`, `A +> B`, `A -.-> B ;annotation`,
     * `A +'needs'> B`. Returns false when the line carries no separator at all,
     * which is how the driver tells a link from a typo.
     */
    private bool parse_link(string line, int source_line) {
        string body = line;
        string? annotation = null;
        int semi = body.index_of_char(';');
        if (semi >= 0) {
            annotation = body.substring(semi + 1).strip();
            body = body.substring(0, semi);
        }

        int at;
        string sep;
        string? flow_label;
        if (!next_separator(body, 0, true, out at, out sep, out flow_label)) return false;

        string from_part = body.substring(0, at);
        string rest = body.substring(at + sep.length);
        string? from_port = null;
        string? arrow = null;

        if (is_port(sep)) {
            from_port = sep;
            // A port may be followed by a real arrow: `A +<> --> B`.
            int at2;
            string sep2;
            string? flow_label2;
            if (next_separator(rest, 0, false, out at2, out sep2, out flow_label2)) {
                arrow = sep2;
                if (flow_label2 != null) flow_label = flow_label2;
                rest = rest.substring(at2 + sep2.length);
            }
        } else {
            arrow = sep;
        }

        // A trailing port on the target end: `A --> B +>`.
        string to_part = rest;
        string? to_port = null;
        foreach (string p in PORTS) {
            if (to_part.strip().has_suffix(p)) {
                to_port = p;
                string t = to_part.strip();
                to_part = t.substring(0, t.length - p.length);
                break;
            }
        }

        string from_name = strip_quotes(from_part.strip());
        string to_name = strip_quotes(to_part.strip());
        if (from_name.length == 0 || to_name.length == 0) {
            error_at(source_line, "a link needs a component on both sides");
            return true;
        }

        bool dashed = arrow != null && arrow.contains("-.->");
        var flow = port_flow(from_port);
        if (flow == WardleyFlow.NONE) flow = port_flow(to_port);
        if (flow == WardleyFlow.NONE && arrow != null && arrow.has_prefix("+")) {
            if (arrow.contains("<>")) flow = WardleyFlow.BIDIRECTIONAL;
            else if (arrow.contains("<")) flow = WardleyFlow.BACKWARD;
            else if (arrow.contains(">")) flow = WardleyFlow.FORWARD;
        }
        string? label = flow_label ?? annotation;

        diagram.links.add(new WardleyLink(diagram.resolve_node_id(from_name),
                                          diagram.resolve_node_id(to_name),
                                          dashed, label, flow, source_line));
        return true;
    }

    /**
     * The first link separator at or after `from`. `allow_ports` is false on the
     * second pass, where a port has already been taken and only an arrow may
     * follow. `flow_label` is the text of a `+'label'>` arrow.
     */
    private static bool next_separator(string s, int from, bool allow_ports,
                                       out int at, out string sep, out string? flow_label) {
        at = -1;
        sep = "";
        flow_label = null;
        for (int i = from; i < s.length; i++) {
            if (s[i] == '+') {
                // `+'label'<>` / `+'label'<` / `+'label'>`
                if (i + 1 < s.length && s[i + 1] == '\'') {
                    int q = s.index_of_char('\'', i + 2);
                    if (q > 0) {
                        foreach (string f in FLOW_ARROWS) {
                            if (s.length >= q + 1 + f.length && s.substring(q + 1, f.length) == f) {
                                at = i;
                                sep = s.substring(i, q + 1 + f.length - i);
                                flow_label = s.substring(i + 2, q - i - 2);
                                return true;
                            }
                        }
                    }
                }
                if (allow_ports) {
                    foreach (string p in PORTS) {
                        if (s.length >= i + p.length && s.substring(i, p.length) == p) {
                            at = i;
                            sep = p;
                            return true;
                        }
                    }
                }
                continue;
            }
            foreach (string a in PLAIN_ARROWS) {
                if (s.length >= i + a.length && s.substring(i, a.length) == a) {
                    at = i;
                    sep = a;
                    return true;
                }
            }
        }
        return false;
    }

    private static bool is_port(string sep) {
        foreach (string p in PORTS) {
            if (sep == p) return true;
        }
        return false;
    }

    private static WardleyFlow port_flow(string? port) {
        if (port == null) return WardleyFlow.NONE;
        if (port == "+<>") return WardleyFlow.BIDIRECTIONAL;
        if (port == "+<") return WardleyFlow.BACKWARD;
        if (port == "+>") return WardleyFlow.FORWARD;
        return WardleyFlow.NONE;
    }

    // ==================== helpers ====================

    /**
     * mermaid's toPercent(): 0-1 is a fraction and scales up, 1-100 is already
     * a percentage, anything outside 0-100 is an error.
     */
    private bool to_percent(string text, int line, string what, out double percent) {
        percent = 0;
        string t = text.strip();
        double value = 0;
        if (t.length == 0 || !double.try_parse(t, out value)) {
            error_at(line, "%s is not a number: \"%s\"".printf(what, t));
            return false;
        }
        double normalized = value <= 1.0 ? value * 100.0 : value;
        if (normalized < 0 || normalized > 100 || normalized.is_nan()) {
            error_at(line, "%s must be between 0-1 (decimal) or 0-100 (percentage). Received: %s".printf(what, t));
            return false;
        }
        percent = normalized;
        return true;
    }

    // `label [-57, 4]` anywhere in the statement's tail.
    private static void apply_label_offset(WardleyMapNode node, string tail) {
        int at = tail.down().index_of("label");
        if (at < 0) return;
        int open = tail.index_of_char('[', at);
        int close = open >= 0 ? tail.index_of_char(']', open) : -1;
        if (open < 0 || close < 0) return;
        string[] parts = tail.substring(open + 1, close - open - 1).split(",");
        if (parts.length < 2) return;
        node.label_offset_x = double.parse(parts[0].strip());
        node.label_offset_y = double.parse(parts[1].strip());
    }

    // `(build)` / `(buy)` / `(outsource)` / `(market)`
    private static WardleySourceStrategy read_strategy(string tail) {
        string lower = tail.down();
        if (lower.contains("(build)")) return WardleySourceStrategy.BUILD;
        if (lower.contains("(buy)")) return WardleySourceStrategy.BUY;
        if (lower.contains("(outsource)")) return WardleySourceStrategy.OUTSOURCE;
        if (lower.contains("(market)")) return WardleySourceStrategy.MARKET;
        return WardleySourceStrategy.NONE;
    }

    // `inertia` or `(inertia)`
    private static bool read_inertia(string tail) {
        string lower = tail.down();
        return lower.contains("inertia");
    }

    /**
     * mermaid's WardleyBuilder.addNode merges a repeated id instead of adding a
     * second node, and keeps the earlier className / label offsets when the new
     * statement omits them.
     */
    private void add_node(WardleyMapNode node) {
        var existing = diagram.find_node(node.id);
        if (existing == null) {
            diagram.nodes.add(node);
            return;
        }
        existing.label = node.label;
        existing.x = node.x;
        existing.y = node.y;
        existing.kind = node.kind;
        if (node.label_offset_x != null) existing.label_offset_x = node.label_offset_x;
        if (node.label_offset_y != null) existing.label_offset_y = node.label_offset_y;
        if (node.source_strategy != WardleySourceStrategy.NONE) existing.source_strategy = node.source_strategy;
        if (node.inertia) existing.inertia = true;
        if (node.in_pipeline) existing.in_pipeline = true;
    }

    /**
     * An `evolve` keeps its component's visibility, so it can only be resolved
     * once every node is read. mermaid drops a trend whose component has no
     * coordinates; so do we, with an error to say why.
     */
    private void resolve_trends() {
        var kept = new Gee.ArrayList<WardleyTrend>();
        var seen = new Gee.HashSet<string>();
        foreach (var trend in diagram.trends) {
            string id = diagram.resolve_node_id(trend.node_id);
            var node = diagram.find_node(id);
            if (node == null) {
                error_at(trend.source_line, "evolve references unknown component \"%s\"".printf(trend.node_id));
                continue;
            }
            // addTrend keys on the node, so a repeated evolve replaces the first.
            trend.node_id = id;
            trend.target_y = node.y;
            if (seen.contains(id)) {
                for (int k = 0; k < kept.size; k++) {
                    if (kept.get(k).node_id == id) { kept.set(k, trend); break; }
                }
                continue;
            }
            seen.add(id);
            kept.add(trend);
        }
        diagram.trends.clear();
        diagram.trends.add_all(kept);
    }

    // `A -> B -> C` split on the `->` separators, which `evolution` uses.
    private static Gee.ArrayList<string> split_arrow(string s) {
        var parts = new Gee.ArrayList<string>();
        int start = 0;
        for (int i = 0; i + 1 < s.length; i++) {
            if (s[i] == '-' && s[i + 1] == '>') {
                parts.add(s.substring(start, i - start));
                i++;
                start = i + 1;
            }
        }
        parts.add(s.substring(start));
        return parts;
    }

    // `[a, b]` -> `a, b`
    private static string? bracket_body(string s) {
        int open = s.index_of_char('[');
        int close = open >= 0 ? s.index_of_char(']', open) : -1;
        if (open < 0 || close < 0) return null;
        return s.substring(open + 1, close - open - 1);
    }

    // `%%` to end of line, but only when it starts the line (mermaid's rule).
    private static string strip_comment(string line) {
        string t = line.strip();
        if (t.has_prefix("%%")) return "";
        return line;
    }

    private static string strip_quotes(string s) {
        string t = s.strip();
        if (t.length >= 2 && ((t.has_prefix("\"") && t.has_suffix("\"")) ||
                              (t.has_prefix("'") && t.has_suffix("'")))) {
            return t.substring(1, t.length - 2);
        }
        return t;
    }

    private void error_at(int line, string message) {
        diagram.errors.add(new ParseError(message, line, 0));
    }
}

}
