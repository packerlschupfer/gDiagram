namespace GDiagram {

    /**
     * One completion/hover entry of the LSP server.
     *
     * `scope` says where it applies: "puml" (every PlantUML document), "puml:<TYPE>"
     * (a detected PlantUML diagram type, the DiagramType nick without the prefix),
     * "c4" (PlantUML documents that use the C4 stdlib), "mmd" (every Mermaid document)
     * or "mmd:<TYPE>". `insert_text` is an LSP snippet when set.
     */
    public class LspKeyword : Object {
        public string scope;
        public string label;
        public string detail;
        public string documentation;
        public string? insert_text;
        public int kind;
        // Full parameter list of a stdlib macro, shown on hover
        public string? signature = null;

        public LspKeyword(string scope, string label, string detail, string documentation,
                          string? insert_text, int kind) {
            this.scope = scope;
            this.label = label;
            this.detail = detail;
            this.documentation = documentation;
            this.insert_text = insert_text;
            this.kind = kind;
        }

        // Hover text: name and category, the macro signature when there is one, the description
        public string hover_markdown() {
            var sb = new StringBuilder();
            sb.append("**%s**".printf(label));
            if (detail.length > 0) sb.append(" — %s".printf(detail));
            if (signature != null) {
                sb.append("\n\n```plantuml\n%s\n```".printf(signature));
            }
            sb.append("\n\n");
            sb.append(documentation);
            return sb.str;
        }
    }

    /**
     * Keyword tables for LSP completion and hover, per format and diagram type.
     * GTK-free; tests/lsp_protocol_test.vala checks the lookups.
     */
    public class LspKeywords : Object {
        public const int KIND_FUNCTION = 3;
        public const int KIND_KEYWORD = 14;
        public const int KIND_SNIPPET = 15;
        public const int KIND_OPERATOR = 24;

        private static Gee.ArrayList<LspKeyword>? table = null;

        // The scope suffix of a type: SEQUENCE, MERMAID_GANTT, ...
        public static string type_scope(DiagramFormat format, DiagramType type) {
            string nick = type.to_string();
            if (nick.has_prefix("GDIAGRAM_DIAGRAM_TYPE_")) nick = nick.substring("GDIAGRAM_DIAGRAM_TYPE_".length);
            return (format == DiagramFormat.MERMAID ? "mmd:" : "puml:") + nick;
        }

        // Whether a PlantUML document uses the C4 stdlib (C4 macros are offered there)
        public static bool uses_c4(string? content) {
            return content != null && (content.contains("<C4/") || content.contains("C4_") ||
                                       content.contains("C4.puml"));
        }

        /** Entries completed in a document of this format/type, general ones first. */
        public static Gee.ArrayList<LspKeyword> for_document(DiagramFormat format, DiagramType type, string? content) {
            var result = new Gee.ArrayList<LspKeyword>();
            string general = format == DiagramFormat.MERMAID ? "mmd" : "puml";
            string typed = type_scope(format, type);
            bool c4 = format != DiagramFormat.MERMAID && uses_c4(content);
            foreach (var kw in get_table()) {
                if (kw.scope == general || kw.scope == typed || (c4 && kw.scope == "c4")) {
                    result.add(kw);
                }
            }
            return result;
        }

        /**
         * The entry a hovered word stands for. The document's own scopes win; then any
         * macro of the same format (a C4 macro in a file that includes C4 indirectly).
         * Matches the label, or the first word of a multi-word label ("hnote" for
         * "hnote over"); case-insensitive when there is no exact match.
         */
        public static LspKeyword? lookup(string word, DiagramFormat format, DiagramType type, string? content) {
            if (word.length == 0) return null;
            LspKeyword? found = find(word, for_document(format, type, content));
            if (found != null) return found;
            string prefix = format == DiagramFormat.MERMAID ? "mmd" : "puml";
            var same_format = new Gee.ArrayList<LspKeyword>();
            foreach (var kw in get_table()) {
                bool mermaid_scope = kw.scope.has_prefix("mmd");
                if ((prefix == "mmd") == mermaid_scope && kw.kind == KIND_FUNCTION) same_format.add(kw);
            }
            return find(word, same_format);
        }

        private static LspKeyword? find(string word, Gee.List<LspKeyword> candidates) {
            string lower = word.down();
            LspKeyword? exact_ci = null;
            LspKeyword? first_word = null;
            foreach (var kw in candidates) {
                if (kw.label == word) return kw;
                if (exact_ci == null && kw.label.down() == lower) exact_ci = kw;
                if (first_word == null) {
                    int space = kw.label.index_of(" ");
                    if (space > 0 && kw.label.substring(0, space).down() == lower) first_word = kw;
                }
            }
            return exact_ci ?? first_word;
        }

        public static Gee.ArrayList<LspKeyword> get_table() {
            if (table == null) {
                table = new Gee.ArrayList<LspKeyword>();
                add_plantuml();
                add_plantuml_types();
                add_c4();
                add_mermaid();
            }
            return table;
        }

        private static void kw(string scope, string label, string detail, string doc,
                               string? insert = null, int kind = KIND_KEYWORD) {
            table.add(new LspKeyword(scope, label, detail, doc, insert, kind));
        }

        private static void op(string scope, string label, string doc) {
            table.add(new LspKeyword(scope, label, "arrow", doc, null, KIND_OPERATOR));
        }

        // ==================== PlantUML ====================

        private static void add_plantuml() {
            const string S = "puml";
            kw(S, "@startuml", "diagram start", "Begin a PlantUML diagram (sequence, class, activity, state, component, timing, ...)");
            kw(S, "@enduml", "diagram end", "End a PlantUML diagram");
            string[,] starts = {
                { "gantt", "Gantt chart" }, { "mindmap", "mind map" }, { "wbs", "work breakdown structure" },
                { "json", "JSON data" }, { "yaml", "YAML data" }, { "salt", "Salt UI wireframe" },
                { "chen", "Chen entity-relationship diagram" }, { "ebnf", "EBNF railroad diagram" },
                { "regex", "regular expression railroad diagram" }, { "board", "board of columns and cards" },
                { "ditaa", "ASCII art diagram" }, { "nwdiag", "network diagram" },
                { "packetdiag", "packet header diagram" }, { "chronology", "chronology timeline" },
                { "dot", "raw Graphviz DOT" }
            };
            for (int i = 0; i < starts.length[0]; i++) {
                kw(S, "@start" + starts[i, 0], "diagram start", "Begin a %s".printf(starts[i, 1]));
            }
            kw(S, "title", "statement", "Set the diagram title", "title ${1:Title}");
            kw(S, "header", "statement", "Page header text");
            kw(S, "footer", "statement", "Page footer text");
            kw(S, "caption", "statement", "Caption below the diagram");
            kw(S, "legend", "block", "Legend box: `legend [left|right|top|bottom|center]` ... `endlegend`",
               "legend ${1|right,left,top,bottom,center|}\n  ${2:text}\nendlegend");
            kw(S, "note", "note", "Add a note: `note left of X : text`, `note over A, B`, `note \"text\" as N1`");
            kw(S, "skinparam", "styling", "Set a visual parameter: `skinparam backgroundColor #FFFFFF`");
            kw(S, "scale", "statement", "Scale the output: `scale 1.5`, `scale 800 width`; timing: `scale 100 as 50 pixels`");
            kw(S, "hide", "statement", "Hide elements: `hide footbox`, `hide empty members`, `hide time-axis`, ...");
            kw(S, "show", "statement", "Show hidden elements: `show methods`, `show stereotype`");
            kw(S, "!include", "preprocessor", "Include a file or stdlib: `!include <C4/C4_Container>`",
               "!include ${1:<C4/C4_Container>}");
            kw(S, "!theme", "preprocessor", "Apply a theme: `!theme plain`");
            kw(S, "!pragma", "preprocessor", "Set a pragma: `!pragma teoz true`, `!pragma useVerticalIf on`");
            kw(S, "!define", "preprocessor", "Define a macro");
            kw(S, "!procedure", "preprocessor", "Define a procedure (`!endprocedure`)");
            kw(S, "participant", "element", "Declare a sequence participant: `participant \"Label\" as P order 10`");
            kw(S, "actor", "element", "Declare an actor (stick figure); `actor/` is a business actor");
            kw(S, "class", "element", "Declare a class");
            kw(S, "interface", "element", "Declare an interface");
            kw(S, "state", "element", "Declare a state");
            kw(S, "component", "element", "Declare a component");
            kw(S, "package", "container", "Group elements in a package");
            kw(S, "node", "element", "Declare a deployment node");
            kw(S, "database", "element", "Declare a database");
            kw(S, "entity", "element", "Declare an entity");
            kw(S, "usecase", "element", "Declare a use case; `usecase/` is a business use case");
        }

        private static void add_plantuml_types() {
            // ---- Sequence ----
            string S = "puml:SEQUENCE";
            op(S, "->", "Synchronous message");
            op(S, "-->", "Reply (dashed) message");
            op(S, "<-", "Message to the left");
            op(S, "<--", "Dashed message to the left");
            op(S, "->>", "Asynchronous message (open arrow head)");
            op(S, "[->", "Incoming message from outside the diagram");
            op(S, "->]", "Outgoing message to outside the diagram");
            op(S, "?->", "Short incoming message");
            op(S, "->x", "Lost message");
            kw(S, "activate", "lifeline", "Activate a lifeline: `activate Bob #Gold`");
            kw(S, "deactivate", "lifeline", "Deactivate a lifeline");
            kw(S, "return", "lifeline", "Reply to the last activating call and deactivate it: `return result`");
            kw(S, "autoactivate", "lifeline", "`autoactivate on`: every call activates its target until `return`",
               "autoactivate on");
            kw(S, "autonumber", "numbering", "Number messages: `autonumber 10 5 \"<b>[000]\"`, `autonumber stop|resume|inc A`");
            kw(S, "create", "lifeline", "Create a participant at its first message");
            kw(S, "destroy", "lifeline", "Destroy a lifeline");
            kw(S, "newpage", "pages", "Continue on a new page: `newpage Title`");
            kw(S, "ignore newpage", "pages", "Draw all pages as one diagram");
            kw(S, "order", "participant", "Participant column order: `participant Last order 99`");
            kw(S, "hnote", "note", "Hexagonal note: `hnote over Alice : idle`");
            kw(S, "rnote", "note", "Rectangular note: `rnote over Bob : text`");
            kw(S, "box", "grouping", "Group participants: `box \"Name\" #LightBlue` ... `end box`");
            kw(S, "alt", "fragment", "Alternative: `alt condition` ... `else other` ... `end`",
               "alt ${1:condition}\n  $0\nelse ${2:otherwise}\n\nend");
            kw(S, "else", "fragment", "Next branch of an alt fragment");
            kw(S, "loop", "fragment", "Loop fragment: `loop condition` ... `end`", "loop ${1:condition}\n  $0\nend");
            kw(S, "opt", "fragment", "Optional fragment");
            kw(S, "par", "fragment", "Parallel fragment");
            kw(S, "break", "fragment", "Break fragment");
            kw(S, "critical", "fragment", "Critical region");
            kw(S, "group", "fragment", "Generic group: `group Label [second label]`");
            kw(S, "ref", "fragment", "Reference: `ref over A, B : text`");
            kw(S, "delay", "layout", "Delay: `...5 minutes later...`", "...${1:later}...");
            kw(S, "|||", "layout", "Extra vertical space (`||45||` for 45 pixels)");
            kw(S, "==", "layout", "Divider: `== Section ==`", "== ${1:Section} ==");
            kw(S, "{anchor}", "teoz", "Teoz anchor before a message: `{start} A -> B`; `{start} <-> {end} : 2s` draws a duration");

            // ---- Class ----
            S = "puml:CLASS";
            kw(S, "extends", "inheritance", "Inheritance in the declaration: `class A extends B, C`");
            kw(S, "implements", "inheritance", "Realization in the declaration: `class A implements I`");
            kw(S, "abstract", "element", "Abstract class: `abstract class Name`");
            kw(S, "enum", "element", "Enumeration");
            kw(S, "annotation", "element", "Annotation type");
            kw(S, "exception", "element", "Exception class");
            kw(S, "protocol", "element", "Protocol");
            kw(S, "metaclass", "element", "Metaclass");
            kw(S, "stereotype", "element", "Stereotype declaration");
            kw(S, "struct", "element", "Struct");
            kw(S, "dataclass", "element", "Data class");
            kw(S, "record", "element", "Record");
            kw(S, "circle", "element", "Circle element: `circle Name` (also `() Name`)");
            kw(S, "diamond", "element", "Association diamond: `diamond D` (also `<> D`)");
            kw(S, "+", "visibility", "Public member");
            kw(S, "-", "visibility", "Private member");
            kw(S, "#", "visibility", "Protected member");
            kw(S, "~", "visibility", "Package-private member");
            kw(S, "{field}", "member", "Force a member to be a field");
            kw(S, "{method}", "member", "Force a member to be a method");
            kw(S, "{static}", "member", "Static (underlined) member");
            kw(S, "{abstract}", "member", "Abstract (italic) member");
            kw(S, "hide empty members", "visibility", "Hide empty field and method compartments");
            kw(S, "hide circle", "visibility", "Hide the class spot circles");
            kw(S, "show fields", "visibility", "Show fields (`hide methods`, `show Foo methods`, ...)");
            kw(S, "set separator", "namespaces", "Namespace separator: `set separator ::` (`none` to disable)");
            kw(S, "(A, B) .. C", "association class", "Association class C on the link between A and B",
               "(${1:A}, ${2:B}) .. ${3:C}", KIND_SNIPPET);
            kw(S, "()-", "lollipop", "Lollipop interface: `Provided ()- Class`");
            kw(S, "<< (S,#FF7700) >>", "spot", "Stereotype spot with a letter and colour: `class A << (S,#FF7700) Singleton >>`");

            // ---- Activity ----
            S = "puml:ACTIVITY";
            kw(S, "start", "node", "Start node");
            kw(S, "stop", "node", "Stop node");
            kw(S, "end", "node", "End node (a circled cross)");
            kw(S, "kill", "node", "Terminate the flow");
            kw(S, "detach", "node", "Detach the flow");
            kw(S, ":action;", "action", "Action: `:text;` (`#color:text;`)", ":${1:action};", KIND_SNIPPET);
            kw(S, "if", "control", "Condition: `if (test?) then (yes)` ... `else (no)` ... `endif`",
               "if (${1:condition?}) then (${2:yes})\n  $0\nelse (${3:no})\nendif");
            kw(S, "then", "control", "Branch label after `if (...)`");
            kw(S, "else", "control", "Else branch");
            kw(S, "elseif", "control", "Else-if branch");
            kw(S, "endif", "control", "End of a condition");
            kw(S, "while", "control", "While loop: `while (test?) is (yes)` ... `endwhile (no)`");
            kw(S, "endwhile", "control", "End of a while loop");
            kw(S, "repeat", "control", "Repeat loop: `repeat` ... `repeat while (test?)`");
            kw(S, "fork", "control", "Parallel fork: `fork` ... `fork again` ... `end fork`");
            kw(S, "fork again", "control", "Next parallel branch");
            kw(S, "end fork", "control", "End of a fork");
            kw(S, "split", "control", "Split without synchronization: `split` ... `split again` ... `end split`",
               "split\n  $0\nsplit again\n\nend split");
            kw(S, "split again", "control", "Next split branch");
            kw(S, "end split", "control", "End of a split");
            kw(S, "switch", "control", "Switch: `switch (test?)` `case (A)` ... `endswitch`");
            kw(S, "case", "control", "Switch case");
            kw(S, "endswitch", "control", "End of a switch");
            kw(S, "partition", "grouping", "Partition: `partition Name {` ... `}`");
            kw(S, "backward", "control", "Backward action of a repeat loop");
            kw(S, "!pragma useVerticalIf on", "layout", "Draw if/elseif branches vertically");

            // ---- State ----
            S = "puml:STATE";
            kw(S, "[*]", "pseudo-state", "Initial (source) or final (target) state");
            kw(S, "[H]", "pseudo-state", "Shallow history: `A --> Composite[H]`");
            kw(S, "[H*]", "pseudo-state", "Deep history: `A --> Composite[H*]`");
            kw(S, "--", "regions", "Horizontal concurrent region separator inside a composite state");
            kw(S, "||", "regions", "Vertical concurrent region separator inside a composite state");
            string[,] stereos = {
                { "choice", "Choice pseudo-state (diamond)" }, { "fork", "Fork bar" }, { "join", "Join bar" },
                { "start", "Initial pseudo-state" }, { "end", "Final state" },
                { "history", "Shallow history pseudo-state" }, { "history*", "Deep history pseudo-state" },
                { "sdlreceive", "SDL receive signal" }, { "entryPoint", "Entry point on the border" },
                { "exitPoint", "Exit point on the border" }, { "inputPin", "Input pin" },
                { "outputPin", "Output pin" }, { "expansionInput", "Expansion input node" },
                { "expansionOutput", "Expansion output node" }
            };
            for (int i = 0; i < stereos.length[0]; i++) {
                kw(S, "<<%s>>".printf(stereos[i, 0]), "stereotype", stereos[i, 1] + ": `state Name <<%s>>`".printf(stereos[i, 0]));
            }
            kw(S, "note on link", "note", "Note on the previous transition (`end note`)", "note on link\n  ${1:text}\nend note");
            kw(S, "hide empty description", "layout", "Draw states without descriptions as plain boxes");

            // ---- Component / deployment ----
            S = "puml:COMPONENT";
            string[,] elements = {
                { "component", "Component" }, { "interface", "Interface" }, { "port", "Port on a component border" },
                { "portin", "Input port" }, { "portout", "Output port" }, { "actor/", "Business actor" },
                { "usecase/", "Business use case" }, { "boundary", "Boundary" }, { "control", "Control" },
                { "entity", "Entity" }, { "person", "Person" }, { "stack", "Stack" }, { "storage", "Storage" },
                { "queue", "Queue" }, { "frame", "Frame container" }, { "folder", "Folder container" },
                { "cloud", "Cloud container" }, { "database", "Database" }, { "card", "Card" },
                { "agent", "Agent" }, { "artifact", "Artifact" }, { "file", "File" }, { "hexagon", "Hexagon" },
                { "label", "Label" }, { "collections", "Collections" }, { "json", "JSON data block" },
                { "rectangle", "Rectangle container" }, { "action", "Action" }, { "process", "Process" }
            };
            for (int i = 0; i < elements.length[0]; i++) {
                kw(S, elements[i, 0], "element", elements[i, 1]);
            }
            kw(S, "-[thickness=2]->", "link", "Link with a line thickness (`-[#red,thickness=2,dashed]->`)");
            kw(S, "skinparam componentStyle rectangle", "styling", "Draw components as plain rectangles (`uml1`, `uml2`)");
            kw(S, "skinparam linetype ortho", "styling", "Orthogonal links (`polyline` for straight segments)");
            kw(S, "allowmixing", "layout", "Allow class and component elements in one diagram");

            // ---- Timing ----
            S = "puml:TIMING";
            kw(S, "robust", "participant", "Robust signal with named states: `robust \"Web\" as WB`",
               "robust \"${1:Label}\" as ${2:R}");
            kw(S, "concise", "participant", "Concise signal (state bands): `concise \"User\" as U`",
               "concise \"${1:Label}\" as ${2:C}");
            kw(S, "binary", "participant", "Binary (high/low) signal: `binary \"Enable\" as EN`");
            kw(S, "clock", "participant", "Clock: `clock \"Clock\" as C with period 50 pulse 15 offset 10`",
               "clock \"${1:Clock}\" as ${2:CLK} with period ${3:50}");
            kw(S, "analog", "participant", "Analog signal: `analog \"Volt\" between 0 and 5 as V`",
               "analog \"${1:Label}\" between ${2:0} and ${3:10} as ${4:A}");
            kw(S, "rectangle", "participant", "Rectangle signal: `rectangle \"Bus\" as B`");
            kw(S, "compact", "participant", "Compact prefix: `compact concise \"User\" as U`");
            kw(S, "@0", "time", "Time point: following `X is state` lines happen at this time (`@+50` is relative)",
               "@${1:0}");
            kw(S, "@0 as :anchor", "time", "Named time anchor, used as `@:anchor` or `@:anchor+10`", "@${1:0} as :${2:anchor}");
            kw(S, "@participant", "time", "Participant block: `@U` then `0 is Idle`, `+50 is Busy`");
            kw(S, "is", "state", "State change: `U is Busy`, `U is {-}` (hidden), `U is \"Label\" #color`");
            kw(S, "has", "state", "Declare states: `WB has Idle,Waiting` or `WB has \"Long name\" as LN`");
            kw(S, "with period", "clock", "Clock period (`pulse N`, `offset N` follow)");
            kw(S, "pulse", "clock", "Clock pulse width");
            kw(S, "offset", "clock", "Clock start offset");
            kw(S, "between", "analog", "Analog value range: `between 0 and 10`");
            kw(S, "ticks num on multiple", "analog", "Analog axis ticks: `V ticks num on multiple 5`");
            kw(S, "highlight", "decoration", "Highlight a time range: `highlight 0 to 100 #Gold : caption`",
               "highlight ${1:0} to ${2:100} #${3:Gold} : ${4:caption}");
            kw(S, "<->", "constraint", "Time constraint: `U@0 <-> @100 : {100 ms}`");
            kw(S, "hide time-axis", "layout", "Hide the time axis");
            kw(S, "manual time-axis", "layout", "Only label the times used in the diagram");
            kw(S, "mode compact", "layout", "Compact mode for all participants");
            kw(S, "scale", "layout", "Time scale: `scale 100 as 50 pixels`", "scale ${1:100} as ${2:50} pixels");
            kw(S, "use date format", "layout", "Date format of the time axis: `use date format \"YY-MM-dd\"`");
            kw(S, "note top of", "note", "Note on a participant: `note top of U : text`");

            // ---- Gantt ----
            S = "puml:GANTT";
            kw(S, "Project starts", "calendar", "Project start date: `Project starts 2026-01-05`",
               "Project starts ${1:2026-01-05}");
            kw(S, "lasts", "task", "Task duration in calendar days: `[Task] lasts 5 days`",
               "[${1:Task}] lasts ${2:5} days");
            kw(S, "requires", "task", "Task duration in working days: `[Task] requires 3 days`",
               "[${1:Task}] requires ${2:3} days");
            kw(S, "starts", "task", "Task start: `starts 2026-01-12`, `starts at [A]'s end`, `starts 2 days after [A]'s end`");
            kw(S, "ends", "task", "Task end: `ends 2026-01-16`, `ends at [A]'s end`");
            kw(S, "then", "task", "Task starting at the end of the previous one: `then [Next] requires 2 days`");
            kw(S, "happens", "milestone", "Milestone: `[M] happens at [A]'s end` or `happens 2026-02-01`",
               "[${1:Milestone}] happens at [${2:Task}]'s end");
            kw(S, "->", "dependency", "Dependency: `[A] -> [B]` (B starts at A's end)");
            kw(S, "as", "alias", "Task alias: `[Long task name] as [LT] lasts 4 days`");
            kw(S, "is 50% complete", "task", "Completion: `[Task] is 40% completed`");
            kw(S, "is colored in", "task", "Bar colours: `[Task] is colored in LightBlue/Blue`");
            kw(S, "on", "resources", "Resources: `[Task] on {Alice:50%} {Bob} lasts 4 days`");
            kw(S, "-- Separator --", "layout", "Separator row with a label", "-- ${1:Phase} --", KIND_SNIPPET);
            kw(S, "are closed", "calendar", "Closed weekdays: `saturday are closed`");
            kw(S, "is closed", "calendar", "Closed date or range: `2026-01-19 is closed`, `2026-02-01 to 2026-02-05 is closed`");
            kw(S, "is open", "calendar", "Open a closed day again");
            kw(S, "today is", "calendar", "Today marker: `today is 2026-01-08 and is colored in #AAF`");
            kw(S, "printscale", "layout", "Time scale: `printscale daily|weekly|monthly|quarterly|yearly zoom 2`");
            kw(S, "projectscale", "layout", "Same as printscale");
            kw(S, "zoom", "layout", "Zoom factor after the scale");
            kw(S, "print between", "layout", "Print only a date range: `print between 2026-01-01 and 2026-02-01`");
            kw(S, "language", "layout", "Calendar language: `language de`");
            kw(S, "hide ressources names", "layout", "Hide resource names under the bars (`hide ressources footbox`)");
            kw(S, "note bottom", "note", "Note under the previous task (`end note`)", "note bottom\n  ${1:text}\nend note");

            // ---- Other PlantUML types ----
            kw("puml:OBJECT", "object", "element", "Object: `object Name { field = value }`");
            kw("puml:OBJECT", "map", "element", "Map: `map Name { key => value }`");
            kw("puml:OBJECT", "json", "element", "JSON data: `json Name { \"key\": \"value\" }`");
            kw("puml:OBJECT", "diamond", "element", "Association diamond");
            kw("puml:USECASE", "left to right direction", "layout", "Lay the diagram out horizontally");
            kw("puml:USECASE", "<<include>>", "stereotype", "Include relationship label");
            kw("puml:USECASE", "<<extend>>", "stereotype", "Extend relationship label");
            kw("puml:CHRONOLOGY", "happens on", "event", "Event date: `[Release] happens on 2026-03-01`");
            kw("puml:NWDIAG", "nwdiag", "block", "Network diagram block: `nwdiag { ... }`");
            kw("puml:NWDIAG", "network", "block", "Network: `network dmz { address = \"210.x.x.x/24\" ... }`");
            kw("puml:NWDIAG", "group", "block", "Group of nodes: `group web { web01; web02; }`");
            kw("puml:NWDIAG", "address", "attribute", "Network or node address");
            kw("puml:NWDIAG", "description", "attribute", "Node description");
            kw("puml:MERMAID_PACKET", "packetdiag", "block", "Packet header block: `packetdiag { 0-15: Source Port }`");
            kw("puml:MERMAID_PACKET", "colwidth", "attribute", "Bits per row: `colwidth = 32`");
            kw("puml:MERMAID_PACKET", "node_height", "attribute", "Row height: `node_height = 72`");
            kw("puml:CHEN_ER", "relationship", "element", "Relationship diamond: `relationship Rents { }`");
            kw("puml:CHEN_ER", "entity", "element", "Entity with attributes: `entity Movie { Code <<key>> }`");
            kw("puml:CHEN_ER", "<<key>>", "attribute", "Key attribute (underlined)");
            kw("puml:CHEN_ER", "<<derived>>", "attribute", "Derived attribute (dashed)");
            kw("puml:CHEN_ER", "<<multi>>", "attribute", "Multi-valued attribute (double border)");
            kw("puml:CHEN_ER", "-N-", "link", "Link with cardinality: `Person -N- Rents`, `=1=` for total participation");
            kw("puml:BOARD", "+", "card", "Card of the column above; `++` is a sub-card");
            kw("puml:SALT", "{", "layout", "Salt block: `{` grid, `{T` tree, `{#` table, `{+` framed, `{/` tabs");
            kw("puml:ARCHIMATE", "archimate", "element", "ArchiMate element: `archimate #Business \"Customer\" as c <<business-actor>>`");
        }

        // ==================== C4 ====================

        private static void c4(string label, string signature, string doc, string insert) {
            var entry = new LspKeyword("c4", label, "C4 macro", doc, insert, KIND_FUNCTION);
            entry.signature = signature;
            table.add(entry);
        }

        private static void add_c4() {
            kw("puml", "!include <C4/C4_Context>", "C4", "C4 system context diagram macros (also C4_Container, C4_Component, C4_Deployment, C4_Dynamic)",
               "!include <C4/${1|C4_Context,C4_Container,C4_Component,C4_Deployment,C4_Dynamic|}>", KIND_SNIPPET);

            const string ELEM = "($alias, $label, $descr=\"\", $sprite=\"\", $tags=\"\", $link=\"\", $type=\"\")";
            const string TECH = "($alias, $label, $techn=\"\", $descr=\"\", $sprite=\"\", $tags=\"\", $link=\"\")";
            const string REL = "($from, $to, $label, $techn=\"\", $descr=\"\", $sprite=\"\", $tags=\"\", $link=\"\")";
            const string BOUND = "($alias, $label, $tags=\"\", $link=\"\", $descr=\"\")";
            const string NODE = "($alias, $label, $type=\"\", $descr=\"\", $sprite=\"\", $tags=\"\", $link=\"\")";

            string[,] people = {
                { "Person", "A person using the system" }, { "Person_Ext", "An external person" },
                { "System", "A software system" }, { "System_Ext", "An external software system" },
                { "SystemDb", "A system that is a database" }, { "SystemDb_Ext", "An external database system" },
                { "SystemQueue", "A system that is a queue" }, { "SystemQueue_Ext", "An external queue system" }
            };
            for (int i = 0; i < people.length[0]; i++) {
                c4(people[i, 0], people[i, 0] + ELEM, people[i, 1],
                   people[i, 0] + "(${1:alias}, \"${2:Label}\", \"${3:Description}\")");
            }
            string[,] containers = {
                { "Container", "A container (application, service, data store) inside a system" },
                { "Container_Ext", "An external container" }, { "ContainerDb", "A database container" },
                { "ContainerDb_Ext", "An external database container" }, { "ContainerQueue", "A queue container" },
                { "ContainerQueue_Ext", "An external queue container" },
                { "Component", "A component inside a container" }, { "Component_Ext", "An external component" },
                { "ComponentDb", "A database component" }, { "ComponentDb_Ext", "An external database component" },
                { "ComponentQueue", "A queue component" }, { "ComponentQueue_Ext", "An external queue component" }
            };
            for (int i = 0; i < containers.length[0]; i++) {
                c4(containers[i, 0], containers[i, 0] + TECH, containers[i, 1],
                   containers[i, 0] + "(${1:alias}, \"${2:Label}\", \"${3:Technology}\", \"${4:Description}\")");
            }
            c4("Boundary", "Boundary($alias, $label, $type=\"\", $tags=\"\", $link=\"\", $descr=\"\")",
               "A generic boundary grouping elements; `{ ... }` holds its content",
               "Boundary(${1:alias}, \"${2:Label}\") {\n  $0\n}");
            foreach (string b in new string[] { "Enterprise_Boundary", "System_Boundary", "Container_Boundary" }) {
                c4(b, b + BOUND, "Boundary around the elements in its `{ ... }` block",
                   b + "(${1:alias}, \"${2:Label}\") {\n  $0\n}");
            }
            foreach (string n in new string[] { "Deployment_Node", "Deployment_Node_L", "Deployment_Node_R", "Node", "Node_L", "Node_R" }) {
                c4(n, n + NODE, "A deployment node (server, device, execution environment); nests with `{ ... }`",
                   n + "(${1:alias}, \"${2:Label}\", \"${3:Type}\") {\n  $0\n}");
            }
            string[,] rels = {
                { "Rel", "A relationship between two elements" },
                { "Rel_U", "A relationship drawn upwards" }, { "Rel_D", "A relationship drawn downwards" },
                { "Rel_L", "A relationship drawn to the left" }, { "Rel_R", "A relationship drawn to the right" },
                { "Rel_Up", "Same as Rel_U" }, { "Rel_Down", "Same as Rel_D" }, { "Rel_Left", "Same as Rel_L" },
                { "Rel_Right", "Same as Rel_R" }, { "Rel_Back", "A relationship drawn backwards" },
                { "Rel_Neighbor", "A relationship between neighbouring elements" },
                { "BiRel", "A bidirectional relationship" }, { "BiRel_U", "A bidirectional relationship upwards" },
                { "BiRel_D", "A bidirectional relationship downwards" },
                { "BiRel_L", "A bidirectional relationship to the left" },
                { "BiRel_R", "A bidirectional relationship to the right" }
            };
            for (int i = 0; i < rels.length[0]; i++) {
                c4(rels[i, 0], rels[i, 0] + REL, rels[i, 1],
                   rels[i, 0] + "(${1:from}, ${2:to}, \"${3:Label}\", \"${4:Technology}\")");
            }
            c4("RelIndex", "RelIndex($e_index, $from, $to, $label, $techn=\"\", $descr=\"\", $sprite=\"\", $tags=\"\", $link=\"\")",
               "A numbered relationship (dynamic diagrams); `Index()` gives the next number",
               "RelIndex(${1:Index()}, ${2:from}, ${3:to}, \"${4:Label}\")");
            c4("SHOW_LEGEND", "SHOW_LEGEND($hideStereotype=\"true\", $details=Small())",
               "Show a legend of the element and relationship styles used", "SHOW_LEGEND()");
            c4("SHOW_FLOATING_LEGEND", "SHOW_FLOATING_LEGEND($alias=LEGEND(), $hideStereotype=\"true\", $details=Small())",
               "Show the legend as a floating element", "SHOW_FLOATING_LEGEND()");
            c4("LAYOUT_TOP_DOWN", "LAYOUT_TOP_DOWN()", "Lay the diagram out top to bottom (default)", "LAYOUT_TOP_DOWN()");
            c4("LAYOUT_LEFT_RIGHT", "LAYOUT_LEFT_RIGHT()", "Lay the diagram out left to right", "LAYOUT_LEFT_RIGHT()");
            c4("LAYOUT_LANDSCAPE", "LAYOUT_LANDSCAPE()", "Landscape layout", "LAYOUT_LANDSCAPE()");
            c4("LAYOUT_WITH_LEGEND", "LAYOUT_WITH_LEGEND()", "Add a legend to the layout", "LAYOUT_WITH_LEGEND()");
            c4("LAYOUT_AS_SKETCH", "LAYOUT_AS_SKETCH()", "Hand-drawn sketch style", "LAYOUT_AS_SKETCH()");
            c4("AddElementTag",
               "AddElementTag($tagStereo, $bgColor=\"\", $fontColor=\"\", $borderColor=\"\", $shadowing=\"\", $shape=\"\", $sprite=\"\", $techn=\"\", $legendText=\"\", $legendSprite=\"\", $borderStyle=\"\", $borderThickness=\"\")",
               "Define an element tag with its own style; use it with `$tags=\"name\"`",
               "AddElementTag(\"${1:tag}\", \\$bgColor=\"${2:#C00000}\")");
            c4("AddRelTag",
               "AddRelTag($tagStereo, $textColor=\"\", $lineColor=\"\", $lineStyle=\"\", $sprite=\"\", $techn=\"\", $legendText=\"\", $legendSprite=\"\", $lineThickness=\"\")",
               "Define a relationship tag with its own style", "AddRelTag(\"${1:tag}\", \\$lineColor=\"${2:red}\")");
            c4("AddBoundaryTag",
               "AddBoundaryTag($tagStereo, $bgColor=\"\", $fontColor=\"\", $borderColor=\"\", $shadowing=\"\", $shape=\"\", $type=\"\", $legendText=\"\", $borderStyle=\"\", $borderThickness=\"\", $sprite=\"\", $legendSprite=\"\")",
               "Define a boundary tag with its own style", "AddBoundaryTag(\"${1:tag}\", \\$borderColor=\"${2:red}\")");
            c4("UpdateElementStyle",
               "UpdateElementStyle($elementName, $bgColor=\"\", $fontColor=\"\", $borderColor=\"\", $shadowing=\"\", $shape=\"\", $sprite=\"\", $techn=\"\", $legendText=\"\", $legendSprite=\"\", $borderStyle=\"\", $borderThickness=\"\")",
               "Change the default style of an element kind (person, system, container, ...)",
               "UpdateElementStyle(\"${1:person}\", \\$bgColor=\"${2:#08427B}\")");
            c4("UpdateRelStyle", "UpdateRelStyle($textColor, $lineColor)",
               "Change the default relationship colours", "UpdateRelStyle(\"${1:black}\", \"${2:gray}\")");
            c4("UpdateBoundaryStyle",
               "UpdateBoundaryStyle($elementName=\"\", $bgColor=\"\", $fontColor=\"\", $borderColor=\"\", $shadowing=\"\", $shape=\"\", $type=\"\", $legendText=\"\", $borderStyle=\"\", $borderThickness=\"\", $sprite=\"\", $legendSprite=\"\")",
               "Change the default boundary style", "UpdateBoundaryStyle(\\$borderColor=\"${1:gray}\")");
            foreach (string lay in new string[] { "Lay_U", "Lay_D", "Lay_L", "Lay_R" }) {
                c4(lay, lay + "($from, $to)", "Hidden layout link placing `to` relative to `from`",
                   lay + "(${1:from}, ${2:to})");
            }
            c4("Lay_Distance", "Lay_Distance($from, $to, $distance=\"0\")", "Hidden layout link with a distance",
               "Lay_Distance(${1:from}, ${2:to}, ${3:1})");
            c4("SHOW_PERSON_OUTLINE", "SHOW_PERSON_OUTLINE()", "Draw persons as outlines", "SHOW_PERSON_OUTLINE()");
            c4("HIDE_STEREOTYPE", "HIDE_STEREOTYPE()", "Hide the element stereotypes", "HIDE_STEREOTYPE()");
        }

        // ==================== Mermaid ====================

        private static void add_mermaid() {
            const string G = "mmd";
            string[,] headers = {
                { "flowchart", "Flowchart: `flowchart TD|LR|RL|BT`" }, { "graph", "Flowchart (older keyword)" },
                { "sequenceDiagram", "Sequence diagram" }, { "stateDiagram-v2", "State diagram" },
                { "classDiagram", "Class diagram" }, { "erDiagram", "Entity relationship diagram" },
                { "gantt", "Gantt chart" }, { "pie", "Pie chart (`pie showData`)" }, { "journey", "User journey" },
                { "gitGraph", "Git graph" }, { "mindmap", "Mind map" }, { "timeline", "Timeline" },
                { "quadrantChart", "Quadrant chart" }, { "xychart-beta", "XY chart (bar and line)" },
                { "kanban", "Kanban board" }, { "sankey-beta", "Sankey diagram (CSV rows source,target,value)" },
                { "requirementDiagram", "Requirement diagram" }, { "block-beta", "Block diagram" },
                { "packet-beta", "Packet header diagram" }, { "C4Context", "C4 system context diagram" },
                { "C4Container", "C4 container diagram" }, { "C4Component", "C4 component diagram" },
                { "C4Dynamic", "C4 dynamic diagram" }, { "C4Deployment", "C4 deployment diagram" },
                { "architecture-beta", "Architecture diagram (groups, services, junctions)" },
                { "zenuml", "ZenUML sequence diagram" }, { "radar-beta", "Radar chart" },
                { "treemap-beta", "Treemap" }
            };
            for (int i = 0; i < headers.length[0]; i++) {
                kw(G, headers[i, 0], "Mermaid diagram type", headers[i, 1]);
            }
            kw(G, "title", "statement", "Diagram title");
            kw(G, "accTitle", "accessibility", "Accessible title: `accTitle: text`");
            kw(G, "accDescr", "accessibility", "Accessible description: `accDescr: text` or `accDescr { ... }`");
            kw(G, "%%{init: }%%", "directive", "Configuration directive: `%%{init: {\"theme\": \"forest\"}}%%`",
               "%%{init: {\"theme\": \"${1|default,forest,dark,neutral,base|}\"}}%%", KIND_SNIPPET);

            string S = "mmd:MERMAID_FLOWCHART";
            foreach (string d in new string[] { "TD", "TB", "LR", "RL", "BT" }) kw(S, d, "direction", "Flow direction");
            kw(S, "subgraph", "grouping", "Subgraph: `subgraph id [Title]` ... `end`", "subgraph ${1:Title}\n  $0\nend");
            kw(S, "end", "grouping", "End of a subgraph");
            kw(S, "direction", "layout", "Direction inside a subgraph");
            kw(S, "classDef", "styling", "Style class: `classDef name fill:#f9f,stroke:#333`");
            kw(S, "class", "styling", "Apply a style class: `class A,B name`");
            kw(S, "style", "styling", "Style one node: `style A fill:#f9f`");
            kw(S, "linkStyle", "styling", "Style links by index: `linkStyle 0 stroke:red`");
            kw(S, "click", "interaction", "Click action: `click A \"https://...\"`");
            kw(S, "@{ shape: }", "shape", "Expanded node shape: `A@{ shape: rounded, label: \"Text\" }`",
               "@{ shape: ${1|rect,rounded,stadium,diamond,circle,cyl,hex,lean-r,trap-b,doc,delay,fork|}, label: \"${2:Text}\" }", KIND_SNIPPET);
            op(S, "-->", "Arrow link");
            op(S, "-.->", "Dotted arrow link");
            op(S, "==>", "Thick arrow link");
            op(S, "---", "Open link");

            S = "mmd:MERMAID_SEQUENCE";
            foreach (string k in new string[] { "participant", "actor", "activate", "deactivate", "autonumber",
                                                "create", "destroy", "link", "links", "box", "end" }) {
                kw(S, k, "sequence", "Sequence diagram statement `%s`".printf(k));
            }
            kw(S, "Note", "note", "Note: `Note right of A: text`, `Note over A,B: text`");
            foreach (string k in new string[] { "loop", "alt", "else", "opt", "par", "and", "critical", "option", "break", "rect" }) {
                kw(S, k, "fragment", "Block `%s` ... `end`".printf(k));
            }
            op(S, "->>", "Solid line with arrow head");
            op(S, "-->>", "Dotted line with arrow head");
            op(S, "-)", "Asynchronous (open arrow)");
            op(S, "-x", "Line ending in a cross");

            S = "mmd:MERMAID_STATE";
            kw(S, "state", "state", "State: `state \"Description\" as Id`, composite `state Id { ... }`");
            kw(S, "[*]", "pseudo-state", "Start or end state");
            kw(S, "<<choice>>", "stereotype", "Choice state");
            kw(S, "<<fork>>", "stereotype", "Fork state");
            kw(S, "<<join>>", "stereotype", "Join state");
            kw(S, "note", "note", "Note: `note right of State : text` or `note left of S` ... `end note`");
            kw(S, "--", "regions", "Concurrent region separator");
            kw(S, "direction", "layout", "Direction: `direction LR`");
            kw(S, "classDef", "styling", "Style class");

            S = "mmd:MERMAID_CLASS";
            kw(S, "class", "element", "Class: `class Name { +field  +method() }`");
            kw(S, "namespace", "grouping", "Namespace: `namespace Name { class A }`");
            kw(S, "<<interface>>", "annotation", "Interface annotation");
            kw(S, "<<abstract>>", "annotation", "Abstract annotation");
            kw(S, "<<enumeration>>", "annotation", "Enumeration annotation");
            kw(S, "note", "note", "Note: `note \"text\"`, `note for Class \"text\"`");
            kw(S, "direction", "layout", "Direction: `direction RL`");
            kw(S, "cssClass", "styling", "Apply a CSS class");
            op(S, "<|--", "Inheritance");
            op(S, "*--", "Composition");
            op(S, "o--", "Aggregation");
            op(S, "..>", "Dependency");
            op(S, "..|>", "Realization");

            S = "mmd:MERMAID_ER";
            op(S, "||--o{", "Exactly one to zero or more");
            op(S, "||--|{", "Exactly one to one or more");
            op(S, "}o--o{", "Zero or more to zero or more");
            kw(S, "PK", "key", "Primary key attribute");
            kw(S, "FK", "key", "Foreign key attribute");
            kw(S, "UK", "key", "Unique key attribute");

            S = "mmd:MERMAID_GANTT";
            kw(S, "dateFormat", "setting", "Input date format: `dateFormat YYYY-MM-DD`");
            kw(S, "axisFormat", "setting", "Axis label format: `axisFormat %d/%m`");
            kw(S, "tickInterval", "setting", "Axis tick interval: `tickInterval 1week`");
            kw(S, "excludes", "setting", "Excluded days: `excludes weekends`, `excludes 2026-01-01`");
            kw(S, "includes", "setting", "Days included despite excludes");
            kw(S, "todayMarker", "setting", "Today marker style or `todayMarker off`");
            kw(S, "weekday", "setting", "First day of the week: `weekday monday`");
            kw(S, "inclusiveEndDates", "setting", "End dates include their day");
            kw(S, "section", "grouping", "Section of tasks");
            kw(S, "done", "task tag", "Completed task");
            kw(S, "active", "task tag", "Task in progress");
            kw(S, "crit", "task tag", "Critical task");
            kw(S, "milestone", "task tag", "Milestone (zero duration)");
            kw(S, "after", "task", "Start after another task: `after a1`");
            kw(S, "until", "task", "End at another task's start: `until b1`");

            kw("mmd:MERMAID_PIE", "showData", "setting", "Show the values next to the legend: `pie showData`");
            kw("mmd:MERMAID_USER_JOURNEY", "section", "grouping", "Journey section");

            S = "mmd:MERMAID_GIT_GRAPH";
            kw(S, "commit", "git", "Commit: `commit id: \"a1\" type: HIGHLIGHT tag: \"v1\"`");
            kw(S, "branch", "git", "Create a branch: `branch develop order: 2`");
            kw(S, "checkout", "git", "Switch branch");
            kw(S, "switch", "git", "Switch branch");
            kw(S, "merge", "git", "Merge a branch into the current one");
            kw(S, "cherry-pick", "git", "Cherry-pick: `cherry-pick id: \"a1\"`");
            kw(S, "NORMAL", "commit type", "Normal commit");
            kw(S, "REVERSE", "commit type", "Reverse commit");
            kw(S, "HIGHLIGHT", "commit type", "Highlighted commit");

            kw("mmd:MERMAID_TIMELINE", "section", "grouping", "Timeline section");
            S = "mmd:MERMAID_QUADRANT";
            kw(S, "x-axis", "axis", "X axis: `x-axis Low --> High`");
            kw(S, "y-axis", "axis", "Y axis: `y-axis Low --> High`");
            for (int q = 1; q <= 4; q++) kw(S, "quadrant-%d".printf(q), "label", "Quadrant %d label".printf(q));
            S = "mmd:MERMAID_XYCHART";
            kw(S, "x-axis", "axis", "X axis: `x-axis [jan, feb]` or `x-axis 0 --> 100`");
            kw(S, "y-axis", "axis", "Y axis: `y-axis \"Revenue\" 0 --> 1000`");
            kw(S, "bar", "series", "Bar series: `bar [1, 2, 3]`");
            kw(S, "line", "series", "Line series: `line [1, 2, 3]`");
            kw(S, "horizontal", "layout", "Horizontal chart: `xychart-beta horizontal`");

            S = "mmd:MERMAID_KANBAN";
            kw(S, "@{ assigned: }", "metadata", "Card metadata: `id[Card]@{ assigned: 'alice', ticket: 42, priority: 'High' }`",
               "@{ assigned: '${1:name}', ticket: ${2:1}, priority: '${3|Very High,High,Low,Very Low|}' }", KIND_SNIPPET);
            kw(S, "assigned", "metadata", "Card assignee");
            kw(S, "ticket", "metadata", "Card ticket number");
            kw(S, "priority", "metadata", "Card priority: Very High, High, Low, Very Low");

            S = "mmd:MERMAID_REQUIREMENT";
            foreach (string k in new string[] { "requirement", "functionalRequirement", "interfaceRequirement",
                                                "performanceRequirement", "physicalRequirement", "designConstraint" }) {
                kw(S, k, "requirement", "Requirement block: `%s name { id: 1 text: ... risk: high verifymethod: test }`".printf(k));
            }
            kw(S, "element", "element", "Element: `element name { type: simulation docref: path }`");
            foreach (string k in new string[] { "id", "text", "risk", "verifymethod", "type", "docref" }) {
                kw(S, k, "attribute", "Requirement/element attribute `%s:`".printf(k));
            }
            foreach (string k in new string[] { "satisfies", "traces", "contains", "copies", "derives", "refines", "verifies" }) {
                kw(S, k, "relationship", "Relationship: `a - %s -> b`".printf(k));
            }

            S = "mmd:MERMAID_BLOCK";
            kw(S, "columns", "layout", "Columns per row: `columns 3`");
            kw(S, "space", "layout", "Empty cell: `space` or `space:2`");
            kw(S, "block", "grouping", "Nested block: `block:id:2` ... `end`");
            kw(S, "end", "grouping", "End of a nested block");

            kw("mmd:MERMAID_PACKET", "0-15: \"Field\"", "field", "Bit range and label; `+16: \"Field\"` continues from the previous field",
               "${1:0}-${2:15}: \"${3:Field}\"", KIND_SNIPPET);

            S = "mmd:MERMAID_C4";
            foreach (string k in new string[] { "Person", "Person_Ext", "System", "System_Ext", "SystemDb", "SystemQueue",
                                                "Container", "ContainerDb", "ContainerQueue", "Component", "Boundary",
                                                "Enterprise_Boundary", "System_Boundary", "Container_Boundary",
                                                "Deployment_Node", "Node", "Rel", "BiRel", "Rel_U", "Rel_D", "Rel_L",
                                                "Rel_R", "Rel_Back", "UpdateElementStyle", "UpdateRelStyle",
                                                "UpdateLayoutConfig" }) {
                kw(S, k, "C4 macro", "Mermaid C4 statement `%s(...)`".printf(k), null, KIND_FUNCTION);
            }

            S = "mmd:MERMAID_ARCHITECTURE";
            kw(S, "group", "element", "Group: `group api(cloud)[API]`, `in parent` nests it");
            kw(S, "service", "element", "Service: `service db(database)[Database] in api`");
            kw(S, "junction", "element", "Junction point for edges: `junction j1`");
            kw(S, "in", "nesting", "Place a service or group inside a group");
            kw(S, "L:", "edge side", "Edge from the left side: `db:L -- R:server`");

            S = "mmd:MERMAID_ZENUML";
            foreach (string k in new string[] { "@Actor", "@Database", "@Boundary", "@Control", "@Entity", "@Collection", "@Queue" }) {
                kw(S, k, "participant", "Participant annotation `%s Name`".printf(k));
            }
            foreach (string k in new string[] { "try", "catch", "finally", "if", "else", "while", "for", "forEach",
                                                "par", "opt", "return", "new" }) {
                kw(S, k, "statement", "ZenUML `%s`".printf(k));
            }

            S = "mmd:MERMAID_RADAR";
            kw(S, "axis", "axis", "Axes: `axis A[\"Speed\"], B, C`");
            kw(S, "curve", "series", "Curve: `curve c1[\"Team\"]{1, 2, 3}`");
            kw(S, "max", "setting", "Maximum value");
            kw(S, "min", "setting", "Minimum value");
            kw(S, "ticks", "setting", "Number of grid rings");
            kw(S, "graticule", "setting", "Grid shape: `graticule circle|polygon`");
            kw(S, "showLegend", "setting", "Show the legend: `showLegend true`");

            kw("mmd:MERMAID_TREEMAP", "\"Section\"", "node", "Treemap node: a quoted name, `\"Leaf\": 10` for a leaf with a value",
               "\"${1:Name}\": ${2:10}", KIND_SNIPPET);
            kw("mmd:MERMAID_MINDMAP", "::icon()", "decoration", "Node icon: `::icon(fa fa-book)`");
        }
    }
}
