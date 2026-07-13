namespace GDiagram {

    /**
     * The Mermaid half of ElementInspector: reads a clicked Mermaid element and
     * rewrites the source for property edits. GTK-free; ElementInspector dispatches
     * here for the types `covers()` accepts, after checking the ElementInfo flags.
     *
     * Covered, with what each type can edit (the flags on ElementInfo):
     *
     *  - flowchart (`flowchart` / `graph`): label in the node's own shape delimiters,
     *    colour as `style ID fill:...`, rename.
     *  - sequenceDiagram: `participant`/`actor` label as `as Label`, rename. A
     *    participant only used in messages gets a declaration above its first use.
     *  - classDiagram: `<<annotation>>` as the stereotype (inline, standalone
     *    `<<x>> Name` or in the class body), rename. gDiagram ignores `class A["Label"]`,
     *    so the label is read-only.
     *  - stateDiagram(-v2): label as `state "Label" as S` or `S : description`,
     *    rename. gDiagram does not render classDef styling for states: no colour.
     *  - erDiagram: rename. gDiagram does not read `ENTITY["Label"]`: no label.
     *
     * Every scan works on the source text: `%%` comments, `%%{init}%%` blocks, front
     * matter, accTitle/accDescr and titles are never code. Rename skips label text in
     * shape delimiters, edge labels (`-->|text|`, `-- text -->`), strings, text after
     * a `:` separator, class bodies, ER attribute bodies and note bodies.
     */
    public class MermaidElementInspector : Object {

        private enum RefKind {
            USE,        // an element reference in a statement
            DECL,       // declaration keyword form (participant, class, state)
            DESC,       // state "S : description" line
            STYLE,      // flowchart "style ID ..."
            OTHER       // click / class lists / subgraph ids: renamed, never a label
        }

        // One written occurrence of an element id, with the label parts next to it
        private class Ref : Object {
            public int line;
            public int start;
            public int end;
            public string text;
            public RefKind kind = RefKind.USE;
            public string keyword = "";
            // flowchart shape: shape_start..shape_end is "[...]", text span inside
            public int shape_start = -1;
            public int shape_end = -1;
            public string opener = "";
            // label text span (flowchart shape text incl. quotes, sequence alias,
            // state quoted label without quotes, state description)
            public int text_start = -1;
            public int text_end = -1;
            public bool quoted = false;
            public string? label = null;
            public bool opens_body = false;   // class declaration with a "{" body

            public Ref(int line, int start, int end, string text, RefKind kind) {
                this.line = line;
                this.start = start;
                this.end = end;
                this.text = text;
                this.kind = kind;
            }
        }

        // A class annotation "<<x>>" and the class it belongs to
        private class Ann : Object {
            public int line;
            public int start;
            public int end;
            public int ws;                // start of the removable span (inline form)
            public bool whole_line;       // standalone or body line: removed as a line
            public string owner = "";
            public string text = "";
        }

        private class Scan : Object {
            public Gee.ArrayList<Ref> refs = new Gee.ArrayList<Ref>();
            public Gee.ArrayList<Ann> anns = new Gee.ArrayList<Ann>();
        }

        // Shape openers, longest first, and their closers
        private const string[] OPENERS = { "(((", "([", "[[", "[(", "((", "{{", "[/", "[\\", "[", "(", "{", ">" };
        private const string[] CLOSERS = { ")))", "])", "]]", ")]", "))", "}}", "/]", "\\]", "]", ")", "}", "]" };

        public static bool covers(DiagramType type) {
            switch (type) {
                case DiagramType.MERMAID_FLOWCHART:
                case DiagramType.MERMAID_SEQUENCE:
                case DiagramType.MERMAID_CLASS:
                case DiagramType.MERMAID_STATE:
                case DiagramType.MERMAID_ER:
                    return true;
                default:
                    return false;
            }
        }

        // ==================== Inspect ====================

        public static ElementInfo? inspect(DiagramType type, Object? ast, string element_name,
                                           int source_line, string source) {
            if (ast == null) return null;
            string[] lines = source.split("\n");
            int header;
            bool[] code = code_mask(lines, out header);
            var sc = scan(type, lines, code);

            var info = new ElementInfo();
            info.diagram_type = type;
            info.editable = true;
            info.can_rename = true;

            if (type == DiagramType.MERMAID_FLOWCHART && ast is MermaidFlowchart) {
                FlowchartNode? node = null;
                foreach (var n in ((MermaidFlowchart) ast).nodes) {
                    if (n.id == element_name || n.get_safe_id() == element_name) {
                        node = n;
                        break;
                    }
                }
                if (node == null) return null;
                info.kind = "Node";
                info.keyword = "node";
                info.id = node.id;
                info.label = node.text;
                info.can_label = true;
                info.can_color = true;
                var decl = flowchart_label_ref(sc, node.id, node.source_line);
                if (decl != null) {
                    info.declared = true;
                    info.line = decl.line + 1;
                    info.label = decl.label.strip();
                } else {
                    info.line = first_use_line(sc, node.id) + 1;
                }
                info.color = style_fill(lines, sc, node.id) ?? node.fill_color;
                return info;
            }

            if (type == DiagramType.MERMAID_SEQUENCE && ast is MermaidSequenceDiagram) {
                var d = (MermaidSequenceDiagram) ast;
                MermaidActor? actor = null;
                foreach (unowned string candidate in sequence_candidates(element_name)) {
                    foreach (var a in d.actors) {
                        if (a.id == candidate || RenderUtils.sanitize_id(a.id) == candidate) {
                            actor = a;
                            break;
                        }
                    }
                    if (actor != null) break;
                }
                if (actor == null) return null;
                info.kind = actor.is_participant ? "Participant" : "Actor";
                info.keyword = actor.is_participant ? "participant" : "actor";
                info.id = actor.id;
                info.label = actor.alias ?? actor.id;
                info.can_label = true;
                var decl = find_ref(sc, actor.id, RefKind.DECL);
                if (decl != null) {
                    info.declared = true;
                    info.line = decl.line + 1;
                    info.label = decl.label ?? actor.id;
                    info.keyword = decl.keyword.ascii_down();
                } else {
                    info.line = first_use_line(sc, actor.id) + 1;
                }
                var notes = new Gee.ArrayList<string>();
                foreach (var n in d.notes) {
                    if ((n.from_actor != null && n.from_actor.id == actor.id) ||
                        (n.to_actor != null && n.to_actor.id == actor.id)) {
                        notes.add(n.text);
                    }
                }
                if (notes.size > 0) info.note = string.joinv("\n\n", notes.to_array());
                return info;
            }

            if (type == DiagramType.MERMAID_CLASS && ast is MermaidClassDiagram) {
                MermaidClass? cls = null;
                foreach (var c in ((MermaidClassDiagram) ast).classes) {
                    if (c.name == element_name || RenderUtils.sanitize_id(c.name) == element_name) {
                        cls = c;
                        break;
                    }
                }
                if (cls == null) return null;
                switch (cls.class_type) {
                    case MermaidClassType.INTERFACE: info.kind = "Interface"; break;
                    case MermaidClassType.ABSTRACT: info.kind = "Abstract class"; break;
                    case MermaidClassType.ENUM: info.kind = "Enum"; break;
                    default: info.kind = "Class"; break;
                }
                info.keyword = "class";
                info.id = cls.name;
                info.label = cls.name;
                info.stereotype = cls.stereotype;
                info.can_stereotype = true;
                foreach (var ann in sc.anns) {
                    if (ann.owner == cls.name) {
                        info.stereotype = ann.text;
                        break;
                    }
                }
                var decl = find_ref(sc, cls.name, RefKind.DECL);
                info.declared = decl != null;
                info.line = decl != null ? decl.line + 1 : first_use_line(sc, cls.name) + 1;
                return info;
            }

            if (type == DiagramType.MERMAID_STATE && ast is MermaidStateDiagram) {
                string wanted = element_name.has_suffix("_anchor")
                    ? element_name.substring(0, element_name.length - 7) : element_name;
                MermaidState? state = null;
                foreach (var s in ((MermaidStateDiagram) ast).states) {
                    if (s.state_type == MermaidStateType.START || s.state_type == MermaidStateType.END) continue;
                    if (s.id == element_name || RenderUtils.sanitize_id(s.id) == element_name ||
                        s.id == wanted || RenderUtils.sanitize_id(s.id) == wanted) {
                        state = s;
                        break;
                    }
                }
                if (state == null) return null;
                switch (state.state_type) {
                    case MermaidStateType.CHOICE: info.kind = "Choice"; break;
                    case MermaidStateType.FORK: info.kind = "Fork"; break;
                    case MermaidStateType.JOIN: info.kind = "Join"; break;
                    default: info.kind = "State"; break;
                }
                info.keyword = "state";
                info.id = state.id;
                info.label = state.description ?? state.id;
                // A <<choice>>/<<fork>>/<<join>> pseudo-state has no label syntax Mermaid accepts
                info.can_label = state.state_type != MermaidStateType.CHOICE &&
                                 state.state_type != MermaidStateType.FORK &&
                                 state.state_type != MermaidStateType.JOIN;
                var decl = state_label_ref(sc, state.id);
                var any_decl = find_ref(sc, state.id, RefKind.DECL);
                if (decl != null) info.label = decl.label;
                if (any_decl != null) {
                    info.declared = true;
                    info.line = any_decl.line + 1;
                } else if (decl != null) {
                    info.declared = true;
                    info.line = decl.line + 1;
                } else {
                    info.line = first_use_line(sc, state.id) + 1;
                }
                return info;
            }

            if (type == DiagramType.MERMAID_ER && ast is MermaidERDiagram) {
                MermaidEREntity? entity = null;
                foreach (var e in ((MermaidERDiagram) ast).entities) {
                    if (e.name == element_name || RenderUtils.sanitize_id(e.name) == element_name) {
                        entity = e;
                        break;
                    }
                }
                if (entity == null) return null;
                info.kind = "Entity";
                info.keyword = "entity";
                info.id = entity.name;
                info.label = entity.name;
                var decl = find_ref(sc, entity.name, RefKind.DECL);
                info.declared = decl != null;
                info.line = decl != null ? decl.line + 1 : first_use_line(sc, entity.name) + 1;
                return info;
            }
            return null;
        }

        // "actor_Alice" (header box) and "s_Alice_3" (lifeline slot) -> "Alice"
        private static string[] sequence_candidates(string element_name) {
            string[] out_names = { element_name };
            if (element_name.has_prefix("actor_")) out_names += element_name.substring(6);
            if (element_name.has_prefix("s_")) {
                int u = element_name.last_index_of("_");
                if (u > 2 && is_all_digits(element_name.substring(u + 1))) {
                    out_names += element_name.substring(2, u - 2);
                }
            }
            return out_names;
        }

        // ==================== Edits ====================

        public static string? set_label(ElementInfo info, string source, string new_label) {
            string label = new_label.strip();
            if (label.contains("\n") || label.contains("\"")) return null;
            string[] lines = source.split("\n");
            int header;
            bool[] code = code_mask(lines, out header);
            var sc = scan(info.diagram_type, lines, code);

            switch (info.diagram_type) {
                case DiagramType.MERMAID_FLOWCHART:
                    return set_flowchart_label(info, lines, sc, label);
                case DiagramType.MERMAID_SEQUENCE:
                    return set_sequence_label(info, lines, code, header, sc, label);
                case DiagramType.MERMAID_STATE:
                    return set_state_label(info, lines, code, header, sc, label);
                default:
                    return null;
            }
        }

        private static string? set_flowchart_label(ElementInfo info, string[] lines, Scan sc, string label) {
            var decl = flowchart_label_ref(sc, info.id, info.line);
            if (decl == null) {
                if (label.length == 0 || label == info.id) return string.joinv("\n", lines);
                // `A --> B` -> `A --> B[Label]` at the first statement use
                foreach (var r in sc.refs) {
                    if (r.kind != RefKind.USE || r.text != info.id) continue;
                    lines[r.line] = splice(lines[r.line], r.end, r.end, "[%s]".printf(flowchart_text(label, false)));
                    return string.joinv("\n", lines);
                }
                return null;
            }
            string line = lines[decl.line];
            if (label.length == 0) {
                // A plain rectangle loses its brackets; other shapes keep the shape
                if (decl.opener == "[") {
                    line = splice(line, decl.shape_start, decl.shape_end, "");
                } else {
                    line = splice(line, decl.text_start, decl.text_end, flowchart_text(info.id, decl.quoted));
                }
            } else {
                line = splice(line, decl.text_start, decl.text_end, flowchart_text(label, decl.quoted));
            }
            lines[decl.line] = line;
            return string.joinv("\n", lines);
        }

        private static string? set_sequence_label(ElementInfo info, string[] lines, bool[] code, int header,
                                                  Scan sc, string label) {
            if (label.contains(";") || label.contains("#") || label.contains("'") || label.contains("%%")) {
                return null;
            }
            var decl = find_ref(sc, info.id, RefKind.DECL);
            if (decl == null) {
                if (label.length == 0 || label == info.id) return string.joinv("\n", lines);
                // Lifelines are ordered by first appearance, and a declaration counts: the
                // participants written before this one on its first line (`A->>B`) are
                // declared first so the new line does not move B in front of A
                int at = first_use_line(sc, info.id);
                var before = new Gee.ArrayList<string>();
                var seen = new Gee.HashSet<string>();
                foreach (var r in sc.refs) {
                    if (r.text == info.id) break;
                    if (seen.contains(r.text)) continue;
                    seen.add(r.text);
                    if (r.line == at) before.add(r.text);
                }
                string[] decls = {};
                foreach (var other in before) {
                    var later = find_ref(sc, other, RefKind.DECL);
                    string kw = later != null ? later.keyword.ascii_down() : "participant";
                    decls += "%s %s".printf(kw, other);
                }
                decls += "participant %s as %s".printf(info.id, label);
                return insert_line(lines, code, header, at, string.joinv("\n" + (at >= 0 && at < lines.length
                    ? leading_ws(lines[at]) : first_code_indent(lines, code)), decls));
            }
            string line = lines[decl.line];
            if (decl.label != null) {
                if (label.length == 0) {
                    line = splice(line, decl.end, decl.text_end, "");
                } else {
                    line = splice(line, decl.text_start, decl.text_end, label);
                }
            } else {
                if (label.length == 0 || label == info.id) return string.joinv("\n", lines);
                line = splice(line, decl.end, decl.end, " as " + label);
            }
            lines[decl.line] = line;
            return string.joinv("\n", lines);
        }

        private static string? set_state_label(ElementInfo info, string[] lines, bool[] code, int header,
                                               Scan sc, string label) {
            var labelled = state_label_ref(sc, info.id);
            if (labelled != null && labelled.kind == RefKind.DECL) {
                string line = lines[labelled.line];
                if (label.length == 0) {
                    // `state "Label" as S` -> `state S`
                    line = splice(line, labelled.text_start - 1, labelled.start, "");
                } else {
                    line = splice(line, labelled.text_start, labelled.text_end, label);
                }
                lines[labelled.line] = line;
                return string.joinv("\n", lines);
            }
            if (labelled != null) {
                if (label.length == 0) {
                    // `B : waiting` -> `B`: the line goes only when another line still
                    // creates the state, else the state would disappear with its description
                    foreach (var r in sc.refs) {
                        if (r.text == info.id && r.line != labelled.line) return remove_line(lines, labelled.line);
                    }
                    lines[labelled.line] = splice(lines[labelled.line], labelled.end, labelled.text_end, "");
                    return string.joinv("\n", lines);
                }
                lines[labelled.line] = splice(lines[labelled.line], labelled.text_start, labelled.text_end, label);
                return string.joinv("\n", lines);
            }
            if (label.length == 0 || label == info.id) return string.joinv("\n", lines);
            var decl = find_ref(sc, info.id, RefKind.DECL);
            if (decl != null) {
                lines[decl.line] = splice(lines[decl.line], decl.start, decl.start, "\"%s\" as ".printf(label));
                return string.joinv("\n", lines);
            }
            return insert_line(lines, code, header, first_use_line(sc, info.id),
                "state \"%s\" as %s".printf(label, info.id));
        }

        /** Adds, changes or (empty) removes the class `<<annotation>>`. */
        public static string? set_stereotype(ElementInfo info, string source, string new_stereotype) {
            if (info.diagram_type != DiagramType.MERMAID_CLASS) return null;
            string s = new_stereotype.strip();
            if (s.has_prefix("<<")) s = s.substring(2);
            if (s.has_suffix(">>")) s = s.substring(0, s.length - 2);
            s = s.strip();
            // gDiagram reads one identifier between the angle brackets
            if (s.length > 0 && !ElementInspector.is_identifier(s)) return null;

            string[] lines = source.split("\n");
            int header;
            bool[] code = code_mask(lines, out header);
            var sc = scan(info.diagram_type, lines, code);

            Ann? ann = null;
            foreach (var a in sc.anns) {
                if (a.owner == info.id) {
                    ann = a;
                    break;
                }
            }
            if (ann != null) {
                if (s.length == 0) {
                    if (ann.whole_line) {
                        // A standalone `<<x>> Name` may be the only line creating the class:
                        // it becomes `class Name` then
                        bool elsewhere = false;
                        foreach (var r in sc.refs) {
                            if (r.text == info.id && r.line != ann.line) elsewhere = true;
                        }
                        if (!elsewhere) {
                            lines[ann.line] = leading_ws(lines[ann.line]) + "class " + info.id;
                            return string.joinv("\n", lines);
                        }
                        return remove_line(lines, ann.line);
                    }
                    lines[ann.line] = splice(lines[ann.line], ann.ws, ann.end, "");
                } else {
                    lines[ann.line] = splice(lines[ann.line], ann.start, ann.end, "<<%s>>".printf(s));
                }
                return string.joinv("\n", lines);
            }
            if (s.length == 0) return source;

            var decl = find_ref(sc, info.id, RefKind.DECL);
            if (decl != null && decl.opens_body) {
                string indent = leading_ws(lines[decl.line]) + "    ";
                return insert_line(lines, code, header, decl.line + 1, "<<%s>>".printf(s), indent);
            }
            if (decl != null && starts_at(lines[decl.line], decl.text_end, ":::")) {
                // Mermaid rejects an annotation after `class A:::hot`: a standalone line follows
                return insert_line(lines, code, header, decl.line + 1, "<<%s>> %s".printf(s, info.id),
                                   leading_ws(lines[decl.line]));
            }
            if (decl != null) {
                lines[decl.line] = splice(lines[decl.line], decl.text_end, decl.text_end, " <<%s>>".printf(s));
                return string.joinv("\n", lines);
            }
            // A declaration, not `<<x>> Name`: Mermaid rejects an annotation for a class
            // that no earlier line created
            return insert_line(lines, code, header, first_use_line(sc, info.id),
                "class %s <<%s>>".printf(info.id, s));
        }

        /**
         * Flowchart only: sets the `fill` of the node's `style` line, adding the line
         * when there is none, keeping the other properties, and dropping the line when
         * removing the fill leaves it empty. Accepts "red", "#red", "#FF0000", "FF0000".
         */
        public static string? set_color(ElementInfo info, string source, string new_color) {
            if (info.diagram_type != DiagramType.MERMAID_FLOWCHART) return null;
            string? color = normalize_color(new_color.strip());
            if (color == null) return null;

            string[] lines = source.split("\n");
            int header;
            bool[] code = code_mask(lines, out header);
            var sc = scan(info.diagram_type, lines, code);

            var styles = new Gee.ArrayList<Ref>();
            foreach (var r in sc.refs) {
                if (r.kind == RefKind.STYLE && r.text == info.id) styles.add(r);
            }

            if (color.length == 0) {
                // Remove the fill from every style line of the node, last line first
                bool changed = false;
                for (int k = styles.size - 1; k >= 0; k--) {
                    var r = styles[k];
                    var props = split_props(lines[r.line].substring(r.end));
                    int idx = prop_index(props, "fill");
                    if (idx < 0) continue;
                    props.remove_at(idx);
                    changed = true;
                    if (props.size == 0) {
                        lines = remove_line(lines, r.line).split("\n");
                    } else {
                        lines[r.line] = lines[r.line].substring(0, r.end) + " " + join_props(props);
                    }
                }
                return changed ? string.joinv("\n", lines) : source;
            }

            Ref? target = null;
            foreach (var r in styles) {
                if (prop_index(split_props(lines[r.line].substring(r.end)), "fill") >= 0) target = r;
            }
            if (target == null && styles.size > 0) target = styles[styles.size - 1];
            if (target != null) {
                var props = split_props(lines[target.line].substring(target.end));
                int idx = prop_index(props, "fill");
                if (idx >= 0) {
                    props[idx] = "fill:" + color;
                } else {
                    props.insert(0, "fill:" + color);
                }
                lines[target.line] = lines[target.line].substring(0, target.end) + " " + join_props(props);
                return string.joinv("\n", lines);
            }

            // New style line after the last code line (the node exists by then)
            int last = -1;
            for (int i = 0; i < lines.length; i++) {
                if (code[i]) last = i;
            }
            if (last < 0) return null;
            string indent = first_code_indent(lines, code);
            return insert_line(lines, code, header, last + 1, "style %s fill:%s".printf(info.id, color), indent);
        }

        /**
         * Renames the id at every reference the scanner found. Null when the new id is
         * not an identifier, is a keyword of the diagram type, is already used, or the
         * old id is written nowhere.
         */
        public static string? rename(ElementInfo info, string source, string new_id) {
            string to = new_id.strip();
            if (to == info.id) return source;
            if (!ElementInspector.is_identifier(to) || is_reserved_id(info.diagram_type, to)) return null;

            string[] lines = source.split("\n");
            int header;
            bool[] code = code_mask(lines, out header);
            var sc = scan(info.diagram_type, lines, code);
            foreach (var r in sc.refs) {
                if (r.text == to) return null;
            }
            int hits = 0;
            for (int k = sc.refs.size - 1; k >= 0; k--) {
                var r = sc.refs[k];
                if (r.text != info.id) continue;
                string written = to;
                // "A---ops" is a circle edge to "ps": an id starting with o/x directly after
                // a link needs a space (Mermaid's own advice)
                if (info.diagram_type == DiagramType.MERMAID_FLOWCHART && (to[0] == 'o' || to[0] == 'x') &&
                    r.start > 0 && is_link_char(lines[r.line][r.start - 1])) {
                    written = " " + to;
                }
                lines[r.line] = splice(lines[r.line], r.start, r.end, written);
                hits++;
            }
            return hits > 0 ? string.joinv("\n", lines) : null;
        }

        // Words Mermaid's grammar reads as keywords where an id is expected, checked
        // against the Mermaid CLI: flowchart and class diagrams match them case-sensitively,
        // sequence, state and ER diagrams in any case
        private static bool is_reserved_id(DiagramType type, string id) {
            switch (type) {
                case DiagramType.MERMAID_FLOWCHART:
                    return id in new string[] { "end", "style", "class", "classDef", "click", "call", "href",
                                                "subgraph", "graph", "flowchart", "linkStyle", "interpolate" };
                case DiagramType.MERMAID_CLASS:
                    return id in new string[] { "class", "namespace", "note", "cssClass", "classDef", "style",
                                                "click", "link", "callback" };
                case DiagramType.MERMAID_SEQUENCE:
                    return id.ascii_down() in new string[] { "note", "participant", "actor", "loop", "alt", "else",
                                                             "opt", "par", "and", "critical", "option", "break",
                                                             "rect", "end", "autonumber", "activate", "deactivate",
                                                             "destroy", "create", "box", "title", "link", "links",
                                                             "properties", "details", "over", "acctitle", "accdescr" };
                case DiagramType.MERMAID_STATE:
                    return id.ascii_down() in new string[] { "state", "note", "classdef", "class", "scale", "end",
                                                             "acctitle", "accdescr" };
                case DiagramType.MERMAID_ER:
                    return id.ascii_down() in new string[] { "erdiagram", "style", "classdef", "class",
                                                             "acctitle", "accdescr" };
                default:
                    return false;
            }
        }

        // ==================== Lookups ====================

        private static Ref? find_ref(Scan sc, string id, RefKind kind) {
            foreach (var r in sc.refs) {
                if (r.kind == kind && r.text == id) return r;
            }
            return null;
        }

        private static int first_use_line(Scan sc, string id) {
            foreach (var r in sc.refs) {
                if (r.text == id) return r.line;
            }
            return -1;
        }

        // The shaped occurrence that defines the node's label: the one on the parser's
        // line when there is one, else the first
        private static Ref? flowchart_label_ref(Scan sc, string id, int line_hint) {
            Ref? first = null;
            foreach (var r in sc.refs) {
                if (r.kind != RefKind.USE || r.text != id || r.shape_start < 0) continue;
                if (r.line + 1 == line_hint) return r;
                if (first == null) first = r;
            }
            return first;
        }

        // `state "Label" as S` wins over `S : description`
        private static Ref? state_label_ref(Scan sc, string id) {
            Ref? desc = null;
            foreach (var r in sc.refs) {
                if (r.text != id || r.label == null) continue;
                if (r.kind == RefKind.DECL) return r;
                if (r.kind == RefKind.DESC && desc == null) desc = r;
            }
            return desc;
        }

        private static string? style_fill(string[] lines, Scan sc, string id) {
            string? fill = null;
            foreach (var r in sc.refs) {
                if (r.kind != RefKind.STYLE || r.text != id) continue;
                var props = split_props(lines[r.line].substring(r.end));
                int idx = prop_index(props, "fill");
                if (idx >= 0) fill = props[idx].substring(props[idx].index_of_char(':') + 1).strip();
            }
            return fill;
        }

        // ==================== Scanning ====================

        // Which lines hold diagram statements: not front matter, init blocks, comments,
        // accessibility text, titles, blank lines or the diagram header line
        private static bool[] code_mask(string[] lines, out int header) {
            var mask = new bool[lines.length];
            header = -1;
            bool in_front = false;
            bool in_init = false;
            bool in_acc = false;
            for (int i = 0; i < lines.length; i++) {
                mask[i] = false;
                string s = lines[i].strip();
                string l = s.ascii_down();
                if (header < 0 && s == "---") {
                    in_front = !in_front;
                    continue;
                }
                if (in_front) continue;
                if (in_init) {
                    if (s.contains("}%%")) in_init = false;
                    continue;
                }
                if (s.has_prefix("%%{")) {
                    if (!s.contains("}%%")) in_init = true;
                    continue;
                }
                if (s.has_prefix("%%")) continue;
                if (in_acc) {
                    if (s.contains("}")) in_acc = false;
                    continue;
                }
                if (starts_word(l, "acctitle") || starts_word(l, "accdescr")) {
                    if (s.contains("{") && !s.contains("}")) in_acc = true;
                    continue;
                }
                if (s.length == 0) continue;
                if (header < 0) {
                    header = i;
                    continue;
                }
                if (starts_word(l, "title")) continue;
                mask[i] = true;
            }
            return mask;
        }

        private static Scan scan(DiagramType type, string[] lines, bool[] code) {
            var sc = new Scan();
            switch (type) {
                case DiagramType.MERMAID_FLOWCHART:
                    for (int i = 0; i < lines.length; i++) {
                        if (code[i]) scan_flowchart_line(lines[i], i, sc.refs);
                    }
                    break;
                case DiagramType.MERMAID_SEQUENCE:
                    for (int i = 0; i < lines.length; i++) {
                        if (code[i]) scan_sequence_line(lines[i], i, sc.refs);
                    }
                    break;
                case DiagramType.MERMAID_CLASS:
                    scan_class(lines, code, sc);
                    break;
                case DiagramType.MERMAID_STATE:
                    scan_state(lines, code, sc);
                    break;
                case DiagramType.MERMAID_ER:
                    scan_er(lines, code, sc);
                    break;
                default:
                    break;
            }
            return sc;
        }

        private static void scan_flowchart_line(string line, int li, Gee.List<Ref> refs) {
            int len = line.length;
            string l = line.ascii_down();
            int p = skip_ws(line, 0);
            int after = keyword_end(l, p, "style");
            if (after >= 0) {
                add_word_ref(line, li, skip_ws(line, after), RefKind.STYLE, refs);
                return;
            }
            after = keyword_end(l, p, "click");
            if (after >= 0) {
                add_word_ref(line, li, skip_ws(line, after), RefKind.OTHER, refs);
                return;
            }
            if (keyword_end(l, p, "classdef") >= 0 || keyword_end(l, p, "linkstyle") >= 0 ||
                keyword_end(l, p, "direction") >= 0 || keyword_end(l, p, "end") >= 0) {
                return;
            }
            after = keyword_end(l, p, "class");
            if (after >= 0) {
                scan_id_list(line, li, skip_ws(line, after), refs);
                return;
            }
            after = keyword_end(l, p, "subgraph");
            if (after >= 0) {
                // `subgraph id` / `subgraph id [Title]`: the id shares the node namespace.
                // `subgraph My Group` has no id, only a title, which is text.
                int q = skip_ws(line, after);
                if (q < len && is_word(line[q])) {
                    int rest = skip_ws(line, word_end(line, q));
                    if (rest >= len || line[rest] == '[' || starts_at(line, rest, "%%")) {
                        add_word_ref(line, li, q, RefKind.OTHER, refs);
                    }
                }
                return;
            }

            int i = p;
            while (i < len) {
                char c = line[i];
                if (starts_at(line, i, "%%")) break;
                if (c == '"') {
                    int q = index_of_byte(line, '"', i + 1);
                    i = q < 0 ? len : q + 1;
                    continue;
                }
                if (c == '|') {
                    int q = index_of_byte(line, '|', i + 1);
                    i = q < 0 ? len : q + 1;
                    continue;
                }
                if (starts_at(line, i, ":::")) {
                    i = word_end(line, i + 3);
                    continue;
                }
                if (starts_at(line, i, "@{")) {
                    int q = index_of_byte(line, '}', i + 2);
                    i = q < 0 ? len : q + 1;
                    continue;
                }
                if (is_link_char(c)) {
                    int q = link_end(line, i);
                    string run = line.substring(i, q - i);
                    if (run == "--" || run == "==" || run == "-.") {
                        // `A -- text --> B`: the text up to the closing link is a label
                        int close = find_link_close(line, skip_ws(line, q), run);
                        if (close >= 0) {
                            i = close;
                            continue;
                        }
                    }
                    i = q;
                    continue;
                }
                if (is_word(c)) {
                    int e = word_end(line, i);
                    var r = new Ref(li, i, e, line.substring(i, e - i), RefKind.USE);
                    parse_shape(line, r);
                    refs.add(r);
                    i = r.shape_end >= 0 ? r.shape_end : e;
                    continue;
                }
                i++;
            }
        }

        // "[...]", "((...))", ">...]" etc. directly after a node id
        private static void parse_shape(string line, Ref r) {
            int len = line.length;
            int p = r.end;
            for (int k = 0; k < OPENERS.length; k++) {
                if (!starts_at(line, p, OPENERS[k])) continue;
                int t = p + OPENERS[k].length;
                string close = CLOSERS[k];
                string? alt = OPENERS[k] == "[/" ? "\\]" : (OPENERS[k] == "[\\" ? "/]" : null);
                int text_end;
                int close_at;
                int close_len;
                if (t < len && line[t] == '"') {
                    int q = index_of_byte(line, '"', t + 1);
                    if (q < 0) return;
                    if (starts_at(line, q + 1, close)) {
                        close_len = close.length;
                    } else if (alt != null && starts_at(line, q + 1, alt)) {
                        close_len = alt.length;
                    } else {
                        return;
                    }
                    r.quoted = true;
                    r.label = line.substring(t + 1, q - t - 1);
                    text_end = q + 1;
                    close_at = q + 1;
                } else {
                    int q = line.index_of(close, t);
                    close_len = close.length;
                    if (alt != null) {
                        int q2 = line.index_of(alt, t);
                        if (q2 >= 0 && (q < 0 || q2 < q)) {
                            q = q2;
                            close_len = alt.length;
                        }
                    }
                    if (q < 0) return;
                    r.label = line.substring(t, q - t);
                    text_end = q;
                    close_at = q;
                }
                r.shape_start = p;
                r.text_start = t;
                r.text_end = text_end;
                r.shape_end = close_at + close_len;
                r.opener = OPENERS[k];
                return;
            }
        }

        private static bool is_link_char(char c) {
            return c == '-' || c == '=' || c == '.' || c == '<' || c == '>' || c == '~';
        }

        // End of a link token: link characters plus an "o"/"x" arrowhead
        private static int link_end(string line, int start) {
            int len = line.length;
            int q = start;
            while (q < len && is_link_char(line[q])) q++;
            if (q < len && (line[q] == 'o' || line[q] == 'x') && (q + 1 >= len || !is_word(line[q + 1]))) q++;
            return q;
        }

        // After `--`, `==` or `-.` label text: the end of the link that closes it, or -1
        private static int find_link_close(string line, int from, string run) {
            int pos = from;
            if (pos < line.length && line[pos] == '"') {
                int q = index_of_byte(line, '"', pos + 1);
                if (q < 0) return -1;
                pos = q + 1;
            }
            if (pos >= line.length || line[pos] == '|') return -1;
            string head = run == "==" ? "==" : (run == "-." ? ".-" : "--");
            int q = line.index_of(head, pos);
            if (q < 0) return -1;
            return link_end(line, q);
        }

        private static void scan_sequence_line(string line, int li, Gee.List<Ref> refs) {
            int len = line.length;
            string l = line.ascii_down();
            int p = skip_ws(line, 0);
            foreach (unowned string kw in new string[] { "loop", "alt", "else", "opt", "par", "and",
                                                         "critical", "option", "break", "rect", "box",
                                                         "autonumber", "end" }) {
                if (keyword_end(l, p, kw) >= 0) return;
            }
            int after = keyword_end(l, p, "create");
            if (after >= 0) p = skip_ws(line, after);

            after = keyword_end(l, p, "participant");
            if (after < 0) after = keyword_end(l, p, "actor");
            if (after >= 0) {
                int q = skip_ws(line, after);
                if (q >= len || !is_word(line[q])) return;
                int e = word_end(line, q);
                var r = new Ref(li, q, e, line.substring(q, e - q), RefKind.DECL);
                r.keyword = line.substring(p, after - p);
                int a = skip_ws(line, e);
                int as_end = keyword_end(l, a, "as");
                if (a > e && as_end >= 0) {
                    int s = skip_ws(line, as_end);
                    int t = len;
                    while (t > s && is_space(line[t - 1])) t--;
                    if (t > s) {
                        r.text_start = s;
                        r.text_end = t;
                        r.label = line.substring(s, t - s);
                    }
                }
                refs.add(r);
                return;
            }
            foreach (unowned string kw in new string[] { "activate", "deactivate", "destroy" }) {
                after = keyword_end(l, p, kw);
                if (after >= 0) {
                    add_word_ref(line, li, skip_ws(line, after), RefKind.USE, refs);
                    return;
                }
            }

            // Messages, notes and links: ids before the ':' text
            int i = p;
            after = keyword_end(l, p, "note");
            bool note = after >= 0;
            if (note) i = after;
            while (i < len) {
                char c = line[i];
                if (c == ':' || starts_at(line, i, "%%")) break;
                if (c == '"') {
                    int q = index_of_byte(line, '"', i + 1);
                    i = q < 0 ? len : q + 1;
                    continue;
                }
                if (c == '-' || c == '<' || c == '>') {
                    int q = i;
                    while (q < len && (line[q] == '-' || line[q] == '<' || line[q] == '>')) q++;
                    // "--x" / "-x" cross arrow
                    if (line[q - 1] == '-' && q < len && line[q] == 'x') q++;
                    i = q;
                    continue;
                }
                if (is_word(c)) {
                    int e = word_end(line, i);
                    string w = line.substring(i, e - i);
                    string wl = w.ascii_down();
                    // "Note right of A", "Note over A,B": placement words are not ids
                    if (!(note && (wl == "left" || wl == "right" || wl == "of" || wl == "over"))) {
                        refs.add(new Ref(li, i, e, w, RefKind.USE));
                    }
                    i = e;
                    continue;
                }
                i++;
            }
        }

        private static void scan_class(string[] lines, bool[] code, Scan sc) {
            string? body_owner = null;
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                string line = lines[i];
                string s = line.strip();
                string l = line.ascii_down();
                int len = line.length;
                int p = skip_ws(line, 0);

                if (body_owner != null) {
                    if (s.has_prefix("}")) {
                        body_owner = null;
                        continue;
                    }
                    if (starts_at(line, p, "<<")) {
                        int q = line.index_of(">>", p + 2);
                        if (q > 0) add_ann(sc, i, p, q + 2, p, true, body_owner, line.substring(p + 2, q - p - 2));
                    }
                    if (s.has_suffix("}")) body_owner = null;
                    continue;
                }
                if (s.has_prefix("}")) continue;
                int after = keyword_end(l, p, "cssclass");
                if (after >= 0) {
                    // `cssClass "Animal,Duck" hot`: the quoted list names classes
                    int q = skip_ws(line, after);
                    if (q < len && line[q] == '"') {
                        int g = index_of_byte(line, '"', q + 1);
                        int k = q + 1;
                        while (g > 0 && k < g) {
                            if (is_word(line[k])) {
                                int e = int.min(word_end(line, k), g);
                                sc.refs.add(new Ref(i, k, e, line.substring(k, e - k), RefKind.OTHER));
                                k = e;
                            } else {
                                k++;
                            }
                        }
                    } else {
                        scan_id_list(line, i, q, sc.refs);
                    }
                    continue;
                }
                if (keyword_end(l, p, "namespace") >= 0 || keyword_end(l, p, "classdef") >= 0 ||
                    keyword_end(l, p, "direction") >= 0) {
                    continue;
                }

                after = keyword_end(l, p, "class");
                if (after >= 0) {
                    int q = skip_ws(line, after);
                    if (q >= len || !is_word(line[q])) continue;
                    int e = word_end(line, q);
                    var r = new Ref(i, q, e, line.substring(q, e - q), RefKind.DECL);
                    int t = e;
                    if (t < len && line[t] == '~') {
                        int g = index_of_byte(line, '~', t + 1);
                        if (g > 0) t = g + 1;
                    }
                    if (starts_at(line, t, "[\"")) {
                        int g = line.index_of("\"]", t + 2);
                        if (g > 0) t = g + 2;
                    }
                    r.text_end = t;    // where an inline annotation goes
                    int u = skip_ws(line, t);
                    if (starts_at(line, u, "<<")) {
                        int g = line.index_of(">>", u + 2);
                        if (g > 0) {
                            add_ann(sc, i, u, g + 2, t, false, r.text, line.substring(u + 2, g - u - 2));
                            u = skip_ws(line, g + 2);
                        }
                    }
                    if (u < len && line[u] == '{' && index_of_byte(line, '}', u) < 0) {
                        r.opens_body = true;
                        body_owner = r.text;
                    }
                    sc.refs.add(r);
                    continue;
                }
                if (starts_at(line, p, "<<")) {
                    // Standalone `<<interface>> Name`
                    int g = line.index_of(">>", p + 2);
                    if (g < 0) continue;
                    int q = skip_ws(line, g + 2);
                    if (q < len && is_word(line[q])) {
                        int e = word_end(line, q);
                        var r = new Ref(i, q, e, line.substring(q, e - q), RefKind.USE);
                        add_ann(sc, i, p, g + 2, p, true, r.text, line.substring(p + 2, g - p - 2));
                        sc.refs.add(r);
                    }
                    continue;
                }
                after = keyword_end(l, p, "note");
                if (after >= 0) {
                    int f = keyword_end(l, skip_ws(line, after), "for");
                    if (f >= 0) add_word_ref(line, i, skip_ws(line, f), RefKind.USE, sc.refs);
                    continue;
                }
                bool handled = false;
                foreach (unowned string kw in new string[] { "click", "link", "callback", "style" }) {
                    after = keyword_end(l, p, kw);
                    if (after >= 0) {
                        add_word_ref(line, i, skip_ws(line, after), RefKind.OTHER, sc.refs);
                        handled = true;
                        break;
                    }
                }
                if (handled) continue;

                // Relationships and `Name : member` lines: ids before the ':' text
                int k = p;
                while (k < len) {
                    char c = line[k];
                    if (c == ':' || starts_at(line, k, "%%")) break;
                    if (c == '"') {
                        int q = index_of_byte(line, '"', k + 1);
                        k = q < 0 ? len : q + 1;
                        continue;
                    }
                    if (starts_at(line, k, "<<")) {
                        int q = line.index_of(">>", k + 2);
                        k = q < 0 ? len : q + 2;
                        continue;
                    }
                    if (c == '~') {
                        int q = index_of_byte(line, '~', k + 1);
                        k = q < 0 ? len : q + 1;
                        continue;
                    }
                    if (is_word(c)) {
                        int e = word_end(line, k);
                        sc.refs.add(new Ref(i, k, e, line.substring(k, e - k), RefKind.USE));
                        k = e;
                        continue;
                    }
                    k++;
                }
            }
        }

        private static void scan_state(string[] lines, bool[] code, Scan sc) {
            bool in_note = false;
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                string line = lines[i];
                string l = line.ascii_down();
                int len = line.length;
                int p = skip_ws(line, 0);

                if (in_note) {
                    if (l.replace(" ", "").replace("\t", "").strip() == "endnote") in_note = false;
                    continue;
                }
                int after = keyword_end(l, p, "note");
                if (after >= 0) {
                    int colon = index_of_byte(line, ':', after);
                    int head_end = colon >= 0 ? colon : len;
                    int k = after;
                    while (k < head_end) {
                        if (is_word(line[k])) {
                            int e = int.min(word_end(line, k), head_end);
                            string w = line.substring(k, e - k);
                            string wl = w.ascii_down();
                            if (wl != "left" && wl != "right" && wl != "of") {
                                sc.refs.add(new Ref(i, k, e, w, RefKind.USE));
                            }
                            k = e;
                        } else {
                            k++;
                        }
                    }
                    if (colon < 0) in_note = true;
                    continue;
                }
                if (keyword_end(l, p, "direction") >= 0 || keyword_end(l, p, "classdef") >= 0) continue;
                after = keyword_end(l, p, "class");
                if (after >= 0) {
                    scan_id_list(line, i, skip_ws(line, after), sc.refs);
                    continue;
                }
                after = keyword_end(l, p, "state");
                if (after >= 0) {
                    int q = skip_ws(line, after);
                    if (q < len && line[q] == '"') {
                        int g = index_of_byte(line, '"', q + 1);
                        if (g < 0) continue;
                        int a = skip_ws(line, g + 1);
                        int ae = keyword_end(l, a, "as");
                        if (a > g + 1 && ae >= 0) {
                            int w = skip_ws(line, ae);
                            if (w < len && is_word(line[w])) {
                                int e = word_end(line, w);
                                var r = new Ref(i, w, e, line.substring(w, e - w), RefKind.DECL);
                                r.text_start = q + 1;
                                r.text_end = g;
                                r.label = line.substring(q + 1, g - q - 1);
                                sc.refs.add(r);
                            }
                        }
                        continue;
                    }
                    add_word_ref(line, i, q, RefKind.DECL, sc.refs);
                    continue;
                }

                // Transitions and `S : description`: ids before the ':' text
                var line_refs = new Gee.ArrayList<Ref>();
                int colon = -1;
                bool arrow = false;
                int k = p;
                while (k < len) {
                    char c = line[k];
                    if (starts_at(line, k, ":::")) {
                        // "S:::hot" applies a class; it is not a "S : description" separator
                        k = word_end(line, k + 3);
                        continue;
                    }
                    if (c == ':') {
                        colon = k;
                        break;
                    }
                    if (starts_at(line, k, "%%")) break;
                    if (c == '-' || c == '>') arrow = true;
                    if (c == '"') {
                        int q = index_of_byte(line, '"', k + 1);
                        k = q < 0 ? len : q + 1;
                        continue;
                    }
                    if (starts_at(line, k, "<<")) {
                        int q = line.index_of(">>", k + 2);
                        k = q < 0 ? len : q + 2;
                        continue;
                    }
                    if (is_word(c)) {
                        int e = word_end(line, k);
                        line_refs.add(new Ref(i, k, e, line.substring(k, e - k), RefKind.USE));
                        k = e;
                        continue;
                    }
                    k++;
                }
                if (line_refs.size == 1 && colon >= 0 && !arrow) {
                    var r = line_refs[0];
                    int s = skip_ws(line, colon + 1);
                    int t = len;
                    while (t > s && is_space(line[t - 1])) t--;
                    if (t > s) {
                        r.kind = RefKind.DESC;
                        r.text_start = s;
                        r.text_end = t;
                        r.label = line.substring(s, t - s);
                    }
                }
                sc.refs.add_all(line_refs);
            }
        }

        private static void scan_er(string[] lines, bool[] code, Scan sc) {
            bool in_body = false;
            for (int i = 0; i < lines.length; i++) {
                if (!code[i]) continue;
                string line = lines[i];
                string s = line.strip();
                int len = line.length;
                if (in_body) {
                    if (s.has_prefix("}") || s.has_suffix("}")) in_body = false;
                    continue;
                }
                var line_refs = new Gee.ArrayList<Ref>();
                bool opens = false;
                int k = skip_ws(line, 0);
                while (k < len) {
                    char c = line[k];
                    if (c == ':' || starts_at(line, k, "%%")) break;
                    if (c == '"') {
                        int q = index_of_byte(line, '"', k + 1);
                        k = q < 0 ? len : q + 1;
                        continue;
                    }
                    if (c == '[') {
                        int q = index_of_byte(line, ']', k + 1);
                        k = q < 0 ? len : q + 1;
                        continue;
                    }
                    if (c == '{') {
                        if (index_of_byte(line, '}', k) < 0) opens = true;
                        break;
                    }
                    if (c == '|' || c == '}' || c == '-' || c == '.') {
                        // Cardinality and line: ||--o{, }o..|{
                        while (k < len && "|o}{-.".index_of_char(line[k]) >= 0) k++;
                        continue;
                    }
                    if (is_word(c)) {
                        int e = word_end(line, k);
                        line_refs.add(new Ref(i, k, e, line.substring(k, e - k), RefKind.USE));
                        k = e;
                        continue;
                    }
                    k++;
                }
                if (opens) {
                    in_body = true;
                    if (line_refs.size == 1) line_refs[0].kind = RefKind.DECL;
                }
                sc.refs.add_all(line_refs);
            }
        }

        // "A,B,C className": every id before the class name
        private static void scan_id_list(string line, int li, int from, Gee.List<Ref> refs) {
            int len = line.length;
            int q = from;
            while (q < len && is_word(line[q])) {
                int e = word_end(line, q);
                int n = skip_ws(line, e);
                bool more = n < len && line[n] == ',';
                if (!more && n >= len) break;   // a lone last word is the class name
                refs.add(new Ref(li, q, e, line.substring(q, e - q), RefKind.OTHER));
                if (!more) break;
                q = skip_ws(line, n + 1);
            }
        }

        private static void add_word_ref(string line, int li, int pos, RefKind kind, Gee.List<Ref> refs) {
            if (pos >= line.length || !is_word(line[pos])) return;
            int e = word_end(line, pos);
            refs.add(new Ref(li, pos, e, line.substring(pos, e - pos), kind));
        }

        private static void add_ann(Scan sc, int line, int start, int end, int ws, bool whole_line,
                                    string owner, string text) {
            var a = new Ann();
            a.line = line;
            a.start = start;
            a.end = end;
            a.ws = ws;
            a.whole_line = whole_line;
            a.owner = owner;
            a.text = text.strip();
            sc.anns.add(a);
        }

        // ==================== Text helpers ====================

        // Label text for a shape: quoted when it holds anything but letters, digits,
        // spaces and underscores (or was quoted before)
        private static string flowchart_text(string label, bool quoted) {
            bool plain = label.length > 0;
            for (int i = 0; i < label.length; i++) {
                char c = label[i];
                if (!(is_word(c) || c == ' ')) {
                    plain = false;
                    break;
                }
            }
            if (quoted || !plain || label != label.strip()) return "\"%s\"".printf(label);
            return label;
        }

        // "" (remove), "#FF0000"/"FF0000"/"#f9f" -> "#hex", "red"/"#red" -> "red"; null if invalid
        private static string? normalize_color(string c) {
            if (c.length == 0) return "";
            string body = c.has_prefix("#") ? c.substring(1) : c;
            if (body.length == 0) return null;
            bool hex = true;
            bool letters = true;
            for (int i = 0; i < body.length; i++) {
                char ch = body[i];
                bool is_digit = ch >= '0' && ch <= '9';
                bool is_hex_letter = (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
                bool is_letter = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
                if (!is_digit && !is_hex_letter) hex = false;
                if (!is_letter) letters = false;
            }
            int n = body.length;
            bool hex_len = n == 3 || n == 4 || n == 6 || n == 8;
            // Hex first: "ABCDEF" is a colour code (no CSS colour name is made of a-f only)
            if (hex && hex_len) return "#" + body;
            if (letters) return body;
            return null;
        }

        // "fill:#f9f,stroke:#333, stroke-width:4px" -> items; commas inside () stay
        private static Gee.ArrayList<string> split_props(string text) {
            var items = new Gee.ArrayList<string>();
            string t = text.strip();
            if (t.has_suffix(";")) t = t.substring(0, t.length - 1);
            int depth = 0;
            int start = 0;
            for (int i = 0; i <= t.length; i++) {
                if (i == t.length || (t[i] == ',' && depth == 0)) {
                    string item = t.substring(start, i - start).strip();
                    if (item.length > 0) items.add(item);
                    start = i + 1;
                    continue;
                }
                if (t[i] == '(') depth++;
                else if (t[i] == ')' && depth > 0) depth--;
            }
            return items;
        }

        private static int prop_index(Gee.List<string> props, string name) {
            for (int i = 0; i < props.size; i++) {
                int colon = props[i].index_of_char(':');
                if (colon > 0 && props[i].substring(0, colon).strip() == name) return i;
            }
            return -1;
        }

        private static string join_props(Gee.List<string> props) {
            return string.joinv(",", props.to_array());
        }

        // Inserts `text` as a new line before line index `at` (with that line's
        // indentation), or after the header line when `at` is negative
        private static string insert_line(string[] lines, bool[] code, int header, int at, string text,
                                          string? indent = null) {
            string ind = indent ?? "";
            if (at < 0) {
                at = header + 1;
                if (indent == null) ind = first_code_indent(lines, code);
            } else if (indent == null && at < lines.length) {
                ind = leading_ws(lines[at]);
            }
            string[] result = {};
            for (int i = 0; i < lines.length; i++) {
                if (i == at) result += ind + text;
                result += lines[i];
            }
            if (at >= lines.length) result += ind + text;
            return string.joinv("\n", result);
        }

        private static string remove_line(string[] lines, int index) {
            string[] result = {};
            for (int i = 0; i < lines.length; i++) {
                if (i != index) result += lines[i];
            }
            return string.joinv("\n", result);
        }

        private static string first_code_indent(string[] lines, bool[] code) {
            for (int i = 0; i < lines.length; i++) {
                if (code[i]) return leading_ws(lines[i]);
            }
            return "    ";
        }

        private static string leading_ws(string line) {
            return line.substring(0, skip_ws(line, 0));
        }

        // Mirrors MermaidLexer.scan_identifier: "LINE-ITEM" is one id, "A-->B" is not,
        // and "-x"/"-o"/"-)" directly before another identifier character is an arrow
        private static int word_end(string line, int start) {
            int len = line.length;
            int q = start;
            while (q < len && is_word(line[q])) q++;
            while (q + 1 < len && line[q] == '-' && is_word(line[q + 1])) {
                char next = line[q + 1];
                if ((next == 'x' || next == 'o') && q + 2 < len && is_word(line[q + 2])) break;
                q++;
                while (q < len && is_word(line[q])) q++;
            }
            return q;
        }

        // End of keyword `kw` (lower case) at `pos` when followed by whitespace or the
        // end of the line, else -1
        private static int keyword_end(string lower, int pos, string kw) {
            if (!starts_at(lower, pos, kw)) return -1;
            int e = pos + kw.length;
            if (e == lower.length || is_space(lower[e])) return e;
            return -1;
        }

        private static string splice(string s, int start, int end, string replacement) {
            return s.substring(0, start) + replacement + s.substring(end);
        }

        private static bool is_all_digits(string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                if (s[i] < '0' || s[i] > '9') return false;
            }
            return true;
        }

        private static bool is_space(char c) {
            return c == ' ' || c == '\t' || c == '\r';
        }

        private static bool is_word(char c) {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                   c == '_' || (uchar) c >= 0x80;
        }

        private static int skip_ws(string s, int pos) {
            while (pos < s.length && is_space(s[pos])) pos++;
            return pos;
        }

        private static bool starts_at(string s, int pos, string prefix) {
            if (pos < 0 || pos + prefix.length > s.length) return false;
            for (int i = 0; i < prefix.length; i++) {
                if (s[pos + i] != prefix[i]) return false;
            }
            return true;
        }

        private static bool starts_word(string l, string prefix) {
            if (!l.has_prefix(prefix)) return false;
            return l.length == prefix.length || !is_word(l[prefix.length]);
        }

        private static int index_of_byte(string s, char c, int from) {
            for (int i = from; i < s.length; i++) {
                if (s[i] == c) return i;
            }
            return -1;
        }
    }
}
