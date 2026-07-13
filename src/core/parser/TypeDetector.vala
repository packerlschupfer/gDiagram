namespace GDiagram {
    /**
     * Single source of truth for diagram-type detection.
     *
     * Both the GUI render path (DocumentView) and the headless export path
     * (Application) used to have their own copies of this logic. They drifted
     * out of sync, causing real bugs (e.g. WBS files detected as ACTIVITY in
     * one path but not the other). All detection now lives here.
     *
     * Returns DiagramType.UNKNOWN when no syntax is recognized so callers can
     * surface a clear error instead of silently rendering an empty default.
     */
    public class TypeDetector : Object {

        // True if the source contains a "business actor" :Name:/ pattern
        // (a letter followed by `:/` followed by whitespace/end). Excludes
        // URL `://` which has `/` immediately after the second `:`.
        // True if the source contains an activity action line: a line that
        // (after leading whitespace) STARTS with ':'. The previous heuristic —
        // any ':' plus any ';' anywhere in the source — misdetected component
        // diagrams whose edge labels contain colons and whose node labels
        // contain a semicolon. A terminating ';' is still required somewhere,
        // but it may sit on a later line (multi-line actions).
        private static bool contains_action_line(string lower) {
            if (!lower.contains(";")) return false;
            foreach (string raw_line in lower.split("\n")) {
                string line = raw_line.strip();
                if (line.length > 1 && line[0] == ':') return true;
            }
            return false;
        }

        private static bool contains_business_actor(string lower) {
            int n = lower.length;
            for (int i = 1; i < n - 1; i++) {
                if (lower[i] != ':') continue;
                // Must have a letter or digit before
                char prev = lower[i - 1];
                if (!(prev >= 'a' && prev <= 'z') && !(prev >= '0' && prev <= '9')) continue;
                // Must have `/` immediately after
                if (lower[i + 1] != '/') continue;
                // Reject URL form (`://`): check that the char after `/` is
                // not another `/`.
                if (i + 2 < n && lower[i + 2] == '/') continue;
                return true;
            }
            return false;
        }

        public static bool is_mermaid(string source) {
            string lower = source.down();
            // PlantUML files start with @startuml, @startgantt, @startwbs,
            // @startpacketdiag etc. Mermaid never uses @start... so the
            // presence of any @start marker means this is PlantUML and we
            // should not match Mermaid keywords against it. (Without this
            // guard, e.g. @startpacketdiag matches "\npacket" below.)
            if (lower.contains("@start")) {
                return false;
            }
            return lower.contains("flowchart") || lower.has_prefix("graph ") ||
                   lower.contains("sequencediagram") ||
                   lower.contains("statediagram") ||
                   lower.contains("classdiagram") ||
                   lower.contains("erdiagram") ||
                   lower.contains("gantt") ||
                   lower.has_prefix("pie") || lower.contains("\npie") ||
                   lower.has_prefix("journey") || lower.contains("\njourney") ||
                   lower.has_prefix("gitgraph") || lower.contains("\ngitgraph") ||
                   lower.has_prefix("mindmap") || lower.contains("\nmindmap") ||
                   lower.has_prefix("timeline") || lower.contains("\ntimeline") ||
                   lower.has_prefix("quadrantchart") || lower.contains("\nquadrantchart") ||
                   lower.has_prefix("xychart") || lower.contains("\nxychart") ||
                   lower.has_prefix("kanban") || lower.contains("\nkanban") ||
                   lower.has_prefix("sankey") || lower.contains("\nsankey") ||
                   lower.has_prefix("requirementdiagram") || lower.contains("\nrequirementdiagram") ||
                   lower.has_prefix("block-beta") || lower.contains("\nblock-beta") ||
                   lower.has_prefix("packet") || lower.contains("\npacket") ||
                   lower.has_prefix("c4context") || lower.has_prefix("c4container") ||
                   lower.has_prefix("c4component") || lower.has_prefix("c4dynamic") ||
                   lower.has_prefix("c4deployment") || lower.contains("\nc4") ||
                   lower.has_prefix("architecture") || lower.contains("\narchitecture") ||
                   lower.has_prefix("zenuml") || lower.contains("\nzenuml") ||
                   lower.has_prefix("radar") || lower.contains("\nradar") ||
                   lower.has_prefix("treemap") || lower.contains("\ntreemap");
        }

        public static DiagramType detect_plantuml(string source) {
            string lower = source.down();

            // Unique @start... keywords first — these are definitive
            if (lower.contains("@startjson")) return DiagramType.JSON_DIAGRAM;
            if (lower.contains("@startnwdiag")) return DiagramType.NWDIAG;
            if (lower.contains("@startpacketdiag")) return DiagramType.MERMAID_PACKET;
            if (lower.contains("@startyaml")) return DiagramType.YAML_DIAGRAM;
            if (lower.contains("@startchronology")) return DiagramType.CHRONOLOGY;
            if (lower.contains("@startgantt")) return DiagramType.GANTT;
            if (lower.contains("@startwbs")) return DiagramType.WBS;
            if (lower.contains("@startmindmap")) return DiagramType.MINDMAP;
            // New @start types
            if (lower.contains("@startdot")) return DiagramType.DOT_DIAGRAM;
            if (lower.contains("@startsalt")) return DiagramType.SALT;
            if (lower.contains("@startchen")) return DiagramType.CHEN_ER;
            if (lower.contains("@startebnf")) return DiagramType.EBNF;
            if (lower.contains("@startregex")) return DiagramType.REGEX_DIAGRAM;
            if (lower.contains("@starttree")) return DiagramType.TREE;
            if (lower.contains("@startditaa")) return DiagramType.DITAA;
            if (lower.contains("@startboard")) return DiagramType.BOARD;
            if (lower.contains("@startancestry")) return DiagramType.ANCESTRY;

            // GEDCOM files start with "0 HEAD"
            if (lower.has_prefix("0 head") || lower.contains("\n0 head")) return DiagramType.ANCESTRY;

            // Archimate: archimate keyword or macro-style layer prefixes
            if (lower.contains("\narchimate ") || lower.has_prefix("archimate ") ||
                lower.contains("\nbusiness_") || lower.contains("\napplication_") ||
                lower.contains("\ntechnology_") || lower.contains("\nmotivation_")) {
                return DiagramType.ARCHIMATE;
            }

            // Timing diagram: @startuml with concise/robust/clock/binary/analog signals
            // Must check BEFORE sequence/state/activity since timing uses @startuml too
            if (lower.contains("@startuml") || !lower.contains("@start")) {
                if (lower.contains("\nconcise ") || lower.has_prefix("concise ") ||
                    lower.contains("\nrobust ") || lower.has_prefix("robust ") ||
                    lower.contains("\nclock ") || lower.has_prefix("clock ") ||
                    lower.contains("\nbinary ") || lower.has_prefix("binary ") ||
                    lower.contains("\nanalog ")) {
                    return DiagramType.TIMING;
                }
            }

            // Raw C4-PlantUML macros: files using the stdlib directly (before
            // preprocessor expansion) call Person(...), Container(...), etc.
            // We route these to COMPONENT so the C4-aware render path kicks in
            // once the preprocessor has expanded the stdlib macros.
            if (lower.contains("person(") || lower.contains("system(") ||
                lower.contains("system_ext(") || lower.contains("container(") ||
                lower.contains("containerdb(") || lower.contains("containerqueue(") ||
                lower.contains("component(") || lower.contains("componentdb(") ||
                lower.contains("system_boundary(") || lower.contains("container_boundary(") ||
                lower.contains("enterprise_boundary(") || lower.contains("deployment_node(")) {
                return DiagramType.COMPONENT;
            }

            // C4-PlantUML expansion: any of the C4 element stereotypes appears.
            // After preprocessor expansion, C4 calls produce rectangle/database
            // declarations with these stereotypes. Routes to COMPONENT (which
            // already understands rectangle/database/<<stereo>> syntax). Must
            // come before the activity heuristic because the C4 output also
            // contains skinparam blocks with ':' and ';' that would otherwise
            // trigger the activity check.
            if (lower.contains("<<person>>") ||
                lower.contains("<<system>>") ||
                lower.contains("<<container>>") ||
                lower.contains("<<container_db>>") ||
                lower.contains("<<container_queue>>") ||
                lower.contains("<<external_person>>") ||
                lower.contains("<<external_system>>") ||
                lower.contains("<<external_container>>") ||
                lower.contains("<<system_boundary>>") ||
                lower.contains("<<container_boundary>>") ||
                lower.contains("<<enterprise_boundary>>") ||
                (lower.contains("<<boundary>>") && lower.contains("rectangle "))) {
                return DiagramType.COMPONENT;
            }

            // Sequence diagram: participant keyword is unique to sequence
            bool has_sequence_syntax =
                lower.contains("\nparticipant ") ||
                lower.has_prefix("participant ") ||
                (lower.contains("\nactor ") && lower.contains("\nparticipant "));
            if (has_sequence_syntax) return DiagramType.SEQUENCE;

            // State diagram: [*], state keyword
            if (lower.contains("[*]") ||
                lower.contains("\nstate ") || lower.has_prefix("state ")) {
                return DiagramType.STATE;
            }

            // Class diagram BEFORE activity — class files can legitimately
            // contain both ':' and ';' (e.g. in note text), which would
            // otherwise trigger the activity heuristic.
            if ((lower.contains("\nclass ") || lower.has_prefix("class ")) ||
                lower.contains("\ninterface ") ||
                lower.contains("\nabstract class") ||
                lower.contains("\nenum ") ||
                // Class declarations with visibility prefix: -class, #class,
                // ~class, +class (private/protected/package/public)
                lower.contains("\n-class ") || lower.contains("\n#class ") ||
                lower.contains("\n~class ") || lower.contains("\n+class ") ||
                // Standard class relation arrows
                lower.contains("--|>") || lower.contains("<|--") ||
                lower.contains("..|>") || lower.contains("<|..") ||
                lower.contains("o--")  || lower.contains("--o")  ||
                lower.contains("*--")  || lower.contains("--*") ||
                // Alternative class relation arrows: #-- x-- }-- +-- ^--
                lower.contains("#--") || lower.contains("--#") ||
                lower.contains("x--") || lower.contains("--x") ||
                lower.contains("}--") || lower.contains("--{") ||
                lower.contains("+--") || lower.contains("--+") ||
                lower.contains("^--") || lower.contains("--^")) {
                return DiagramType.CLASS;
            }

            // Activity diagram: start/stop, control flow keywords, action lines
            bool has_start_stop = lower.contains("\nstart") || lower.contains("\nstop") ||
                                  lower.has_prefix("@startuml\nstart") ||
                                  lower.has_prefix("@startuml\r\nstart");
            bool has_activity_syntax = lower.contains("endif") ||
                                       lower.contains("endwhile") ||
                                       lower.contains("end fork") ||
                                       lower.contains("endswitch") ||
                                       lower.contains("fork again") ||
                                       lower.contains("partition ") ||
                                       contains_action_line(lower) ||
                                       lower.contains("\n* ") || lower.has_prefix("* ") ||
                                       lower.contains("\n- ") || lower.has_prefix("- ");
            if (has_start_stop || has_activity_syntax) {
                return DiagramType.ACTIVITY;
            }

            // Use case diagram
            if (lower.contains("\nusecase ") ||
                lower.contains("\nusecase(") ||
                lower.contains("\nusecase/") || lower.has_prefix("usecase/") ||
                lower.contains("\nactor/") || lower.has_prefix("actor/") ||
                // Business usecase notation: (First usecase)/ — closing paren
                // immediately followed by '/'. Excludes URLs (which have '/'
                // after a host segment, never after a paren).
                lower.contains(")/") ||
                // Business actor notation: :Actor Name:/
                // Match :word:/ but NOT URL :// — the colon must be preceded
                // by a letter (the end of an actor name), and not preceded
                // by another colon or slash.
                contains_business_actor(lower) ||
                (lower.contains("\nactor ") && !lower.contains("\nparticipant "))) {
                return DiagramType.USECASE;
            }

            // ER diagram
            if (lower.contains("\nentity ") || lower.has_prefix("entity ") ||
                lower.contains("||--") || lower.contains("}o--") ||
                lower.contains("|o--") || lower.contains("--||") ||
                lower.contains("--o{") || lower.contains("--o|")) {
                return DiagramType.ER_DIAGRAM;
            }

            // Deployment diagram (device keyword is unique)
            if (lower.contains("\ndevice ") || lower.has_prefix("device ")) {
                return DiagramType.DEPLOYMENT;
            }

            // Component diagram
            if (lower.contains("\npackage ") || lower.has_prefix("package ") ||
                lower.contains("\ncomponent ") || lower.contains("\n[") ||
                lower.contains("\ncloud ") || lower.contains("\nnode ") ||
                lower.contains("\nfolder ") || lower.contains("\nframe ") ||
                lower.contains("\nrectangle ") || lower.contains("\nartifact ") ||
                lower.contains("\nstorage ") || lower.contains("\ndatabase ")) {
                return DiagramType.COMPONENT;
            }

            // Object diagram
            if (lower.contains("\nobject ") || lower.has_prefix("object ") ||
                lower.contains("\nmap ")) {
                return DiagramType.OBJECT;
            }

            // Sequence diagram (last resort — needs only an arrow)
            if (lower.contains("->") || lower.contains("-->") ||
                lower.contains("<-") || lower.contains("<--")) {
                return DiagramType.SEQUENCE;
            }

            // No syntax recognized
            return DiagramType.UNKNOWN;
        }

        public static DiagramType detect_mermaid(string source) {
            string lower = source.down();

            if (lower.contains("flowchart") || lower.has_prefix("flowchart") ||
                lower.has_prefix("graph ")) {
                return DiagramType.MERMAID_FLOWCHART;
            }
            if (lower.contains("sequencediagram") || lower.has_prefix("sequencediagram")) {
                return DiagramType.MERMAID_SEQUENCE;
            }
            if (lower.contains("statediagram-v2") || lower.contains("statediagram")) {
                return DiagramType.MERMAID_STATE;
            }
            if (lower.contains("classdiagram") || lower.has_prefix("classdiagram")) {
                return DiagramType.MERMAID_CLASS;
            }
            if (lower.contains("erdiagram") || lower.has_prefix("erdiagram")) {
                return DiagramType.MERMAID_ER;
            }
            if (lower.contains("gantt") || lower.has_prefix("gantt")) {
                return DiagramType.MERMAID_GANTT;
            }
            if (lower.has_prefix("pie") || lower.contains("\npie")) {
                return DiagramType.MERMAID_PIE;
            }
            if (lower.has_prefix("journey") || lower.contains("\njourney")) {
                return DiagramType.MERMAID_USER_JOURNEY;
            }
            if (lower.has_prefix("gitgraph") || lower.contains("\ngitgraph")) {
                return DiagramType.MERMAID_GIT_GRAPH;
            }
            if (lower.has_prefix("mindmap") || lower.contains("\nmindmap")) {
                return DiagramType.MERMAID_MINDMAP;
            }
            if (lower.has_prefix("timeline") || lower.contains("\ntimeline")) {
                return DiagramType.MERMAID_TIMELINE;
            }
            if (lower.has_prefix("quadrantchart") || lower.contains("\nquadrantchart")) {
                return DiagramType.MERMAID_QUADRANT;
            }
            if (lower.has_prefix("xychart-beta") || lower.has_prefix("xychart") ||
                lower.contains("\nxychart-beta") || lower.contains("\nxychart")) {
                return DiagramType.MERMAID_XYCHART;
            }
            if (lower.has_prefix("kanban") || lower.contains("\nkanban")) {
                return DiagramType.MERMAID_KANBAN;
            }
            if (lower.has_prefix("sankey") || lower.contains("\nsankey")) {
                return DiagramType.MERMAID_SANKEY;
            }
            if (lower.has_prefix("requirementdiagram") || lower.contains("\nrequirementdiagram")) {
                return DiagramType.MERMAID_REQUIREMENT;
            }
            if (lower.has_prefix("block-beta") || lower.contains("\nblock-beta")) {
                return DiagramType.MERMAID_BLOCK;
            }
            if (lower.has_prefix("packet-beta") || lower.contains("\npacket-beta") ||
                lower.has_prefix("packet\n") || lower.contains("\npacket\n")) {
                return DiagramType.MERMAID_PACKET;
            }
            if (lower.has_prefix("c4context") || lower.has_prefix("c4container") ||
                lower.has_prefix("c4component") || lower.has_prefix("c4dynamic") ||
                lower.has_prefix("c4deployment") ||
                lower.contains("\nc4context") || lower.contains("\nc4container")) {
                return DiagramType.MERMAID_C4;
            }
            if (lower.has_prefix("architecture-beta") || lower.contains("\narchitecture-beta")) {
                return DiagramType.MERMAID_ARCHITECTURE;
            }
            if (lower.has_prefix("zenuml") || lower.contains("\nzenuml")) {
                return DiagramType.MERMAID_ZENUML;
            }
            if (lower.has_prefix("radar-beta") || lower.contains("\nradar-beta") ||
                lower.has_prefix("radar\n") || lower.contains("\nradar\n")) {
                return DiagramType.MERMAID_RADAR;
            }
            if (lower.has_prefix("treemap-beta") || lower.contains("\ntreemap-beta") ||
                lower.has_prefix("treemap\n") || lower.contains("\ntreemap\n")) {
                return DiagramType.MERMAID_TREEMAP;
            }
            return DiagramType.UNKNOWN;
        }
    }
}
