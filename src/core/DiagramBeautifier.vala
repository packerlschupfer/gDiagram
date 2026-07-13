namespace GDiagram {
    public class DiagramBeautifier : Object {

        // ── Helpers ───────────────────────────────────────────────────────────

        // Strip trailing whitespace from a single line.
        private static string rstrip(string s) {
            int end = s.length;
            while (end > 0 && (s[end - 1] == ' ' || s[end - 1] == '\t')) {
                end--;
            }
            return s.substring(0, end);
        }

        // Final cleanup: strip trailing whitespace per line, collapse consecutive
        // blank lines to at most one, and remove leading/trailing blank lines.
        public static string clean(string source) {
            var sb = new StringBuilder();
            string[] lines = source.split("\n");
            bool last_was_blank = false;
            bool at_start = true;

            foreach (string line in lines) {
                string tr = rstrip(line);
                bool is_blank = (tr.strip().length == 0);

                if (is_blank) {
                    if (!at_start && !last_was_blank) {
                        sb.append("\n");
                        last_was_blank = true;
                    }
                } else {
                    at_start = false;
                    last_was_blank = false;
                    sb.append(tr);
                    sb.append("\n");
                }
            }

            string result = sb.str;
            // Remove single trailing newline added by loop
            if (result.has_suffix("\n")) {
                result = result.substring(0, result.length - 1);
            }
            return result;
        }

        // Build an indent string of n×4 spaces.
        private static string indent(int level) {
            var sb = new StringBuilder();
            for (int i = 0; i < level * 4; i++) {
                sb.append(" ");
            }
            return sb.str;
        }

        // ── Mermaid: generic brace-based indenter ─────────────────────────────
        //
        // For diagram types where blocks are delimited by { and }.
        // - First non-blank line (the diagram header) always at col 0.
        // - Lines starting with `}` decrement indent BEFORE printing.
        // - Lines ending with `{` increment indent AFTER printing.
        // - Lines matching base_zero_prefixes stay at col 0 after the header
        //   (used for directives like %%, accTitle, accDescr).

        private static string indent_brace_blocks(string source, string[] base_zero_prefixes) {
            var sb = new StringBuilder();
            string[] lines = source.split("\n");
            int level = 0;
            bool header_done = false;

            foreach (string line in lines) {
                string tr = line.strip();
                if (tr.length == 0) {
                    if (header_done) sb.append("\n");
                    continue;
                }

                // First content line is the diagram header.
                if (!header_done) {
                    header_done = true;
                    sb.append(tr);
                    sb.append("\n");
                    continue;
                }

                // } closes before printing.
                if (tr.has_prefix("}")) {
                    if (level > 0) level--;
                }

                // Check if this line stays at level 0 (directives).
                bool is_zero = false;
                foreach (string p in base_zero_prefixes) {
                    if (tr.has_prefix(p)) { is_zero = true; break; }
                }

                if (is_zero) {
                    sb.append(tr);
                } else {
                    sb.append(indent(level > 0 ? level : 1));
                    sb.append(tr);
                }
                sb.append("\n");

                // { opens after printing.
                if (tr.has_suffix("{") && !tr.has_suffix("\\{")) {
                    level++;
                }
            }

            return clean(sb.str);
        }

        // ── Mermaid: keyword-block indenter ───────────────────────────────────
        //
        // For diagram types where blocks are delimited by keywords (no braces).
        // opener_prefixes:  lines that open a new indent level (printed then indent++)
        // closer_prefixes:  lines that close BEFORE printing (indent-- then print)
        // reopen_prefixes:  lines that close-then-reopen (else, else if …)
        // base_zero_prefixes: lines that stay at base indent regardless

        private static string indent_keyword_blocks(
            string source,
            string[] opener_prefixes,
            string[] closer_prefixes,
            string[] reopen_prefixes,
            string[] base_zero_prefixes
        ) {
            var sb = new StringBuilder();
            string[] lines = source.split("\n");
            int level = 0;
            bool header_done = false;

            foreach (string line in lines) {
                string tr = line.strip();
                if (tr.length == 0) {
                    if (header_done) sb.append("\n");
                    continue;
                }

                if (!header_done) {
                    header_done = true;
                    sb.append(tr);
                    sb.append("\n");
                    continue;
                }

                // Check closer (decrement before printing).
                bool is_closer = false;
                foreach (string p in closer_prefixes) {
                    string pstripped = p.strip();
                    if (tr == pstripped || tr.has_prefix(pstripped + " ") || tr.has_prefix(pstripped + ":")) {
                        is_closer = true;
                        break;
                    }
                }
                // Check reopen (decrement before, increment after).
                bool is_reopen = false;
                foreach (string p in reopen_prefixes) {
                    string pstripped = p.strip();
                    if (tr == pstripped || tr.has_prefix(pstripped + " ")) {
                        is_reopen = true;
                        break;
                    }
                }

                if ((is_closer || is_reopen) && level > 0) {
                    level--;
                }

                // Check base-zero.
                bool is_zero = false;
                foreach (string p in base_zero_prefixes) {
                    if (tr.has_prefix(p)) { is_zero = true; break; }
                }

                if (is_zero) {
                    sb.append(tr);
                } else {
                    sb.append(indent(level > 0 ? level : 1));
                    sb.append(tr);
                }
                sb.append("\n");

                // Check opener (increment after printing).
                bool is_opener = false;
                foreach (string p in opener_prefixes) {
                    string pstripped = p.strip();
                    if (tr == pstripped || tr.has_prefix(pstripped + " ")) {
                        is_opener = true;
                        break;
                    }
                }

                if (is_opener || is_reopen) {
                    level++;
                }
            }

            return clean(sb.str);
        }

        // ── Mermaid: uniform indenter ─────────────────────────────────────────
        //
        // For types with no block structure: diagram header at col 0,
        // everything else at 4-space indent.

        public static string format_mermaid_uniform(string source) {
            var sb = new StringBuilder();
            string[] lines = source.split("\n");
            bool header_done = false;
            string[] zero_prefixes = { "%%", "accTitle", "accDescr" };

            foreach (string line in lines) {
                string tr = line.strip();
                if (tr.length == 0) {
                    if (header_done) sb.append("\n");
                    continue;
                }
                if (!header_done) {
                    header_done = true;
                    sb.append(tr);
                    sb.append("\n");
                    continue;
                }
                bool is_zero = false;
                foreach (string p in zero_prefixes) {
                    if (tr.has_prefix(p)) { is_zero = true; break; }
                }
                if (is_zero) {
                    sb.append(tr);
                } else {
                    sb.append("    ");
                    sb.append(tr);
                }
                sb.append("\n");
            }
            return clean(sb.str);
        }

        // ── Mermaid type-specific formatters ──────────────────────────────────

        // Flowchart / graph: keyword blocks (subgraph/end).
        // Also auto-applies semantic color classDefs if none exist.
        public static string format_mermaid_flowchart(string source) {
            string[] openers  = { "subgraph" };
            string[] closers  = { "end" };
            string[] reopens  = {};
            string[] zeros    = { "%%", "classDef ", "class ", "style ",
                                  "linkStyle ", "direction ", "accTitle", "accDescr" };

            string formatted = indent_keyword_blocks(source, openers, closers, reopens, zeros);

            // Auto-apply semantic color classes if none exist yet.
            if (!source.contains("classDef") && !source.contains("class ")) {
                formatted = apply_flowchart_colors(formatted);
            }

            return formatted;
        }

        // Sequence diagram: keyword blocks.
        public static string format_mermaid_sequence(string source) {
            string[] openers  = { "loop ", "alt ", "opt ", "par ", "critical ",
                                   "break ", "rect ", "group " };
            string[] closers  = { "end" };
            string[] reopens  = { "else " };
            string[] zeros    = { "participant ", "actor ", "%%",
                                  "autonumber", "accTitle", "accDescr" };
            return indent_keyword_blocks(source, openers, closers, reopens, zeros);
        }

        // State diagram: brace blocks.
        public static string format_mermaid_state(string source) {
            string[] zeros = { "%%", "accTitle", "accDescr" };
            return indent_brace_blocks(source, zeros);
        }

        // Class diagram: brace blocks with namespace/class keywords.
        public static string format_mermaid_class(string source) {
            string[] zeros = { "%%", "accTitle", "accDescr" };
            return indent_brace_blocks(source, zeros);
        }

        // ER diagram: brace blocks (entity body).
        public static string format_mermaid_er(string source) {
            string[] zeros = { "%%", "accTitle", "accDescr", "title " };
            return indent_brace_blocks(source, zeros);
        }

        // Gantt: uniform indent (no syntactic block structure).
        public static string format_mermaid_gantt(string source) {
            return format_mermaid_uniform(source);
        }

        // ── PlantUML formatter ────────────────────────────────────────────────
        //
        // - @startuml / @enduml (and all @start*/@end* directives) at col 0.
        // - title, skinparam, hide, show, !, left to right, top to bottom at col 0.
        // - Block openers (box, alt, loop, group, note, namespace, package, {) indent after.
        // - Block closers (end box, end note, end ref, end, }) dedent before.
        // - `else`, `elseif` dedent before and indent after.

        public static string format_plantuml(string source) {
            var sb = new StringBuilder();
            string[] lines = source.split("\n");
            int level = 0;

            // Absolute zero keywords (always col 0, no indent).
            string[] at_zero = {
                "@start", "@end", "title", "skinparam", "hide ", "show ",
                "!include", "!define", "!undef", "!ifdef", "!ifndef", "!endif",
                "!else", "left to right direction", "top to bottom direction",
                "hide footbox", "header", "footer", "legend", "newpage", "scale ",
                "!pragma", "!theme", "!startsub", "!endsub"
            };

            // Block openers: indent AFTER printing.
            string[] openers = {
                "box ", "group ", "loop ", "alt ", "opt ", "par ", "critical ",
                "break ", "ref over", "note over", "note left", "note right",
                "note as ", "note on link", "namespace ", "package ", "frame ",
                "cloud ", "node ", "database ", "folder ", "rectangle ",
                "component ", "artifact "
            };

            // Block closers: dedent BEFORE printing.
            string[] closers = {
                "end box", "end group", "end loop", "end alt", "end opt",
                "end par", "end critical", "end break", "end ref", "end note",
                "end fork", "end merge", "end split"
            };

            foreach (string line in lines) {
                string tr = line.strip();
                if (tr.length == 0) {
                    sb.append("\n");
                    continue;
                }

                // Absolute zero.
                bool is_zero = false;
                foreach (string p in at_zero) {
                    if (tr.has_prefix(p)) { is_zero = true; break; }
                }

                // } or `end` closes before printing.
                bool is_brace_close = tr.has_prefix("}");
                bool is_kw_close = false;
                foreach (string p in closers) {
                    if (tr == p || tr.has_prefix(p + " ")) { is_kw_close = true; break; }
                }
                // Generic `end` (sequence alt/loop/group etc.)
                bool is_plain_end = (tr == "end");

                if ((is_brace_close || is_kw_close || is_plain_end) && level > 0) {
                    level--;
                }

                // Reopen keywords (else, elseif): dedent before, re-indent after.
                bool is_reopen = (tr == "else" || tr.has_prefix("else ") ||
                                  tr.has_prefix("elseif ") || tr.has_prefix("else if "));
                if (is_reopen && level > 0) {
                    level--;
                }

                if (is_zero) {
                    sb.append(tr);
                } else {
                    sb.append(indent(level));
                    sb.append(tr);
                }
                sb.append("\n");

                // Openers: indent after printing.
                bool opens = false;
                foreach (string p in openers) {
                    if (tr == p.strip() || tr.has_prefix(p)) { opens = true; break; }
                }
                bool brace_open = tr.has_suffix("{") && !tr.has_suffix("\\{");

                if (opens || brace_open || is_reopen) {
                    level++;
                }
            }

            return clean(sb.str);
        }

        // ── Auto-color helper (flowchart) ─────────────────────────────────────

        private static string apply_flowchart_colors(string source) {
            var output = new StringBuilder(source);
            var node_types = new Gee.HashMap<string, string>();

            foreach (string line in source.split("\n")) {
                string tr = line.strip();
                // Rectangle nodes: A[text]
                int id_end = tr.index_of("[");
                if (id_end > 0) {
                    string node_id = tr.substring(0, id_end).strip();
                    if (node_id.length > 0 && !node_id.contains(" ") &&
                        !node_id.contains("-") && !node_id.contains(">")) {
                        string text = "";
                        int te = tr.index_of("]");
                        if (te > id_end) {
                            text = tr.substring(id_end + 1, te - id_end - 1).down();
                        }
                        if (text.contains("start") || text.contains("begin")) {
                            node_types.set(node_id, "start");
                        } else if (text.contains("end") || text.contains("finish") || text.contains("done")) {
                            node_types.set(node_id, "end");
                        } else if (text.contains("error") || text.contains("fail") || text.contains("invalid")) {
                            node_types.set(node_id, "error");
                        } else if (text.contains("success") || text.contains("complete") || text.contains("ok")) {
                            node_types.set(node_id, "success");
                        }
                    }
                }
                // Diamond nodes: A{text}
                int did_end = tr.index_of("{");
                if (did_end > 0) {
                    string node_id = tr.substring(0, did_end).strip();
                    if (node_id.length > 0 && !node_id.contains(" ") && !node_id.contains("-")) {
                        node_types.set(node_id, "decision");
                    }
                }
            }

            if (node_types.size == 0) return source;

            output.append("\n    %% Auto-generated style classes\n");
            output.append("    classDef startStyle    fill:#98D8C8,stroke:#27AE60,stroke-width:2px\n");
            output.append("    classDef endStyle      fill:#7DCEA0,stroke:#27AE60,stroke-width:2px\n");
            output.append("    classDef successStyle  fill:#90EE90,stroke:#228B22,stroke-width:2px\n");
            output.append("    classDef errorStyle    fill:#FFB6C1,stroke:#DC143C,stroke-width:2px\n");
            output.append("    classDef decisionStyle fill:#FFD700,stroke:#DAA520,stroke-width:2px\n");
            output.append("\n    %% Apply styles\n");

            foreach (var entry in node_types.entries) {
                switch (entry.value) {
                    case "start":    output.append_printf("    class %s startStyle\n",    entry.key); break;
                    case "end":      output.append_printf("    class %s endStyle\n",      entry.key); break;
                    case "success":  output.append_printf("    class %s successStyle\n",  entry.key); break;
                    case "error":    output.append_printf("    class %s errorStyle\n",    entry.key); break;
                    case "decision": output.append_printf("    class %s decisionStyle\n", entry.key); break;
                }
            }

            return output.str;
        }

        // ── Legacy API (kept for any external callers) ────────────────────────

        public static string beautify_flowchart(string source) {
            return format_mermaid_flowchart(source);
        }

        public static string format_source(string source) {
            return format_mermaid_flowchart(source);
        }

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
            if (suggestions.size == 0) {
                suggestions.add("Diagram styling looks good!");
            }
            return suggestions.to_array();
        }
    }
}
