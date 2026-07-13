namespace GDiagram {
    /**
     * One palette button: a source snippet inserted at the editor cursor.
     *
     * `select` is a substring of `snippet` (usually the element name) that the
     * editor selects after insertion so the user can type over it.
     * `diagram_type` is UNKNOWN for the format-wide "General" entries.
     */
    public class PaletteEntry : Object {
        public string group { get; construct; }
        public string label { get; construct; }
        public string icon_name { get; construct; }
        public string snippet { get; construct; }
        public string? select { get; construct; }
        public DiagramFormat format { get; construct; }
        public DiagramType diagram_type { get; construct; }

        public PaletteEntry(string group, string label, string icon_name, string snippet, string? select,
                            DiagramFormat format, DiagramType diagram_type) {
            Object(group: group, label: label, icon_name: icon_name, snippet: snippet, select: select,
                   format: format, diagram_type: diagram_type);
        }
    }

    public class PaletteGroup : Object {
        public string name { get; construct; }
        public DiagramFormat format { get; construct; }
        // UNKNOWN for a "General" group that applies to every type of its format
        public DiagramType diagram_type { get; construct; }
        public Gee.ArrayList<PaletteEntry> entries { get; private set; }

        public PaletteGroup(string name, DiagramFormat format, DiagramType diagram_type) {
            Object(name: name, format: format, diagram_type: diagram_type);
        }

        construct {
            entries = new Gee.ArrayList<PaletteEntry>();
        }

        public void add(string label, string icon_name, string snippet, string? select = null) {
            entries.add(new PaletteEntry(name, label, icon_name, snippet, select, format, diagram_type));
        }
    }

    /**
     * The element palette's content: snippets grouped by diagram type, GTK-free
     * so tests can check every snippet against the parsers.
     *
     * Snippets use current syntax (PlantUML 1.2026.1, Mermaid 11). Custom icons
     * are the uml-*-symbolic SVGs bundled under /org/gnome/gDiagram/icons.
     */
    public class PaletteCatalog : Object {
        private static Gee.ArrayList<PaletteGroup>? groups = null;

        public static Gee.ArrayList<PaletteGroup> get_groups() {
            if (groups == null) {
                groups = new Gee.ArrayList<PaletteGroup>();
                add_plantuml_groups();
                add_mermaid_groups();
            }
            return groups;
        }

        // Ordering rank of a group for the rendered diagram: 0 = the group for this
        // type, 1 = a closely related group, 2 = General of this format, 3 = another
        // type of this format, 4 = the other format. Ranks 0-2 start expanded.
        public static int relevance(PaletteGroup group, DiagramType type, DiagramFormat format) {
            if (group.format != format) return 4;
            if (group.diagram_type == DiagramType.UNKNOWN) return 2;
            if (group.diagram_type == type) return 0;
            // Type detection sends crow's-foot links with an "o" end to the class parser.
            if (related(group.diagram_type, type)) return 1;
            return 3;
        }

        private static bool related(DiagramType a, DiagramType b) {
            return (a == DiagramType.ER_DIAGRAM && b == DiagramType.CLASS) ||
                   (a == DiagramType.CLASS && b == DiagramType.ER_DIAGRAM) ||
                   (a == DiagramType.MINDMAP && b == DiagramType.WBS);
        }

        public static bool is_mermaid_type(DiagramType type) {
            return type >= DiagramType.MERMAID_FLOWCHART && type <= DiagramType.MERMAID_TREEMAP;
        }

        // A new document holding `body`, for inserting into an empty editor:
        // the @start/@end pair for PlantUML, the diagram header for Mermaid.
        // `format` tells a PlantUML @startpacketdiag (MERMAID_PACKET) from a Mermaid packet.
        public static string wrap_document(string body, DiagramType type,
                                           DiagramFormat format = DiagramFormat.UNKNOWN) {
            bool mermaid = format == DiagramFormat.UNKNOWN ? is_mermaid_type(type) : format == DiagramFormat.MERMAID;
            if (mermaid) {
                var sb = new StringBuilder(mermaid_header(type));
                sb.append_c('\n');
                foreach (string line in body.split("\n")) {
                    sb.append(line.length > 0 ? "    " + line : "");
                    sb.append_c('\n');
                }
                return sb.str;
            }
            string kind = "uml";
            if (type == DiagramType.MINDMAP) kind = "mindmap";
            else if (type == DiagramType.WBS) kind = "wbs";
            else if (type == DiagramType.GANTT) kind = "gantt";
            else if (type == DiagramType.BOARD) kind = "board";
            else if (type == DiagramType.CHEN_ER) kind = "chen";
            else if (type == DiagramType.EBNF) kind = "ebnf";
            else if (type == DiagramType.REGEX_DIAGRAM) kind = "regex";
            else if (type == DiagramType.SALT) kind = "salt";
            else if (type == DiagramType.DITAA) kind = "ditaa";
            else if (type == DiagramType.CHRONOLOGY) kind = "chronology";
            else if (type == DiagramType.MERMAID_PACKET) kind = "packetdiag";
            else if (type == DiagramType.NWDIAG) kind = "nwdiag";
            return "@start%s\n%s\n@end%s\n".printf(kind, body, kind);
        }

        private static string mermaid_header(DiagramType type) {
            switch (type) {
                case DiagramType.MERMAID_SEQUENCE: return "sequenceDiagram";
                case DiagramType.MERMAID_CLASS:    return "classDiagram";
                case DiagramType.MERMAID_STATE:    return "stateDiagram-v2";
                case DiagramType.MERMAID_ER:       return "erDiagram";
                case DiagramType.MERMAID_GANTT:    return "gantt\n    dateFormat YYYY-MM-DD";
                default:                           return "flowchart TD";
            }
        }

        private static PaletteGroup plantuml(string name, DiagramType type) {
            var g = new PaletteGroup(name, DiagramFormat.PLANTUML, type);
            groups.add(g);
            return g;
        }

        private static PaletteGroup mermaid(string name, DiagramType type) {
            var g = new PaletteGroup(name, DiagramFormat.MERMAID, type);
            groups.add(g);
            return g;
        }

        private static void add_plantuml_groups() {
            var g = plantuml("General", DiagramType.UNKNOWN);
            g.add("Title", "format-text-bold-symbolic", "title Diagram Title", "Diagram Title");
            g.add("Comment", "chat-message-new-symbolic", "' comment", "comment");
            g.add("Block comment", "format-justify-left-symbolic", "/'\n  comment\n'/", "comment");
            g.add("Skin parameter", "preferences-color-symbolic", "skinparam backgroundColor #FFFFFF", "#FFFFFF");
            g.add("Theme", "preferences-desktop-appearance-symbolic", "!theme plain", "plain");

            g = plantuml("Sequence", DiagramType.SEQUENCE);
            g.add("Participant", "uml-lifeline-symbolic", "participant Participant", "Participant");
            g.add("Actor", "uml-actor-symbolic", "actor Actor", "Actor");
            g.add("Database", "uml-database-symbolic", "database Database", "Database");
            g.add("Synchronous message", "uml-message-symbolic", "Alice -> Bob : message", "message");
            g.add("Asynchronous message", "uml-directed-symbolic", "Alice ->> Bob : message", "message");
            g.add("Reply message", "uml-dependency-symbolic", "Bob --> Alice : reply", "reply");
            g.add("Self message", "edit-redo-symbolic", "Alice -> Alice : self call", "self call");
            g.add("Alternative", "uml-fragment-symbolic",
                  "alt condition\n  Alice -> Bob : yes\nelse otherwise\n  Alice -> Bob : no\nend", "condition");
            g.add("Loop", "media-playlist-repeat-symbolic", "loop condition\n  Alice -> Bob : message\nend", "condition");
            g.add("Note", "uml-note-symbolic", "note over Alice : Note text", "Note text");
            g.add("Divider", "list-remove-symbolic", "== Section ==", "Section");
            g.add("Autonumber", "view-list-ordered-symbolic", "autonumber");
            g.add("Autoactivate", "media-playback-start-symbolic", "autoactivate on");
            g.add("Call with return", "uml-dependency-symbolic",
                  "Alice -> Bob : request\nactivate Bob\nreturn response", "response");
            g.add("Colored activation", "preferences-color-symbolic", "activate Bob #Gold", "#Gold");
            g.add("Incoming message", "go-next-symbolic", "[-> Alice : incoming", "incoming");
            g.add("Outgoing message", "go-next-symbolic", "Alice ->] : outgoing", "outgoing");
            g.add("Short message", "uml-directed-symbolic", "?-> Alice : short", "short");
            g.add("Hexagonal note", "uml-note-symbolic", "hnote over Alice : idle", "idle");
            g.add("Rectangle note", "uml-note-symbolic", "rnote over Bob : Note text", "Note text");
            g.add("Participant order", "view-sort-ascending-symbolic", "participant Last order 99", "Last");
            g.add("New page", "document-new-symbolic", "newpage Page title", "Page title");

            g = plantuml("Class", DiagramType.CLASS);
            g.add("Class", "uml-class-symbolic", "class ClassName {\n  +field : Type\n  +method() : void\n}", "ClassName");
            g.add("Abstract class", "uml-class-symbolic", "abstract class AbstractName", "AbstractName");
            g.add("Interface", "uml-interface-symbolic", "interface InterfaceName {\n  +operation() : void\n}", "InterfaceName");
            g.add("Enumeration", "view-list-bullet-symbolic", "enum EnumName {\n  VALUE_A\n  VALUE_B\n}", "EnumName");
            g.add("Package", "uml-package-symbolic", "package PackageName {\n  class Member\n}", "PackageName");
            g.add("Association", "uml-association-symbolic", "ClassA -- ClassB : label", "label");
            g.add("Directed association", "uml-directed-symbolic", "ClassA --> ClassB : label", "label");
            g.add("Generalization", "uml-generalization-symbolic", "Parent <|-- Child", "Child");
            g.add("Realization", "uml-realization-symbolic", "InterfaceName <|.. Implementation", "Implementation");
            g.add("Aggregation", "uml-aggregation-symbolic", "Whole o-- Part", "Part");
            g.add("Composition", "uml-composition-symbolic", "Whole *-- Part", "Part");
            g.add("Dependency", "uml-dependency-symbolic", "Client ..> Supplier : uses", "uses");
            g.add("Association class", "uml-class-symbolic",
                  "class Enrollment\n(ClassA, ClassB) .. Enrollment", "Enrollment");
            g.add("Lollipop interface", "uml-interface-symbolic", "Provided ()- ClassA", "Provided");
            g.add("N-ary association", "uml-decision-symbolic",
                  "<> assoc\nClassA -- assoc\nClassB -- assoc", "assoc");
            g.add("Spot stereotype", "uml-class-symbolic", "class Spotted << (S,#FF7700) Singleton >>", "Spotted");
            g.add("Exception", "dialog-warning-symbolic", "exception AppError", "AppError");
            g.add("Hide empty members", "view-conceal-symbolic", "hide empty members");
            g.add("Note", "uml-note-symbolic", "note \"Note text\" as N1", "Note text");

            g = plantuml("Use Case", DiagramType.USECASE);
            g.add("Actor", "uml-actor-symbolic", "actor ActorName", "ActorName");
            g.add("Use case", "uml-usecase-symbolic", "usecase \"Use case\" as UC1", "Use case");
            g.add("System boundary", "uml-package-symbolic", "rectangle System {\n  usecase \"Inner use case\" as UC2\n}", "System");
            g.add("Association", "uml-association-symbolic", "ActorName -- (Use case)", "ActorName");
            g.add("Include", "uml-dependency-symbolic", "(Use case) ..> (Included) : <<include>>", "Included");
            g.add("Extend", "uml-dependency-symbolic", "(Extension) ..> (Use case) : <<extend>>", "Extension");
            g.add("Generalization", "uml-generalization-symbolic", "(Use case) <|-- (Specialized)", "Specialized");
            g.add("Note", "uml-note-symbolic", "note \"Note text\" as N1", "Note text");

            g = plantuml("Activity", DiagramType.ACTIVITY);
            g.add("Start", "uml-initial-symbolic", "start");
            g.add("Stop", "uml-final-symbolic", "stop");
            g.add("Action", "uml-action-symbolic", ":Action;", "Action");
            g.add("If / else", "uml-decision-symbolic",
                  "if (condition?) then (yes)\n  :Action;\nelse (no)\n  :Other action;\nendif", "condition?");
            g.add("Switch", "uml-decision-symbolic",
                  "switch (test?)\ncase (A)\n  :Action A;\ncase (B)\n  :Action B;\nendswitch", "test?");
            g.add("While loop", "media-playlist-repeat-symbolic",
                  "while (condition?) is (yes)\n  :Action;\nendwhile (no)", "condition?");
            g.add("Repeat loop", "media-playlist-repeat-song-symbolic",
                  "repeat\n  :Action;\nrepeat while (condition?) is (yes)", "condition?");
            g.add("Fork", "uml-fork-symbolic", "fork\n  :Action 1;\nfork again\n  :Action 2;\nend fork", "Action 1");
            g.add("Split", "uml-fork-symbolic", "split\n  :Path A;\nsplit again\n  :Path B;\nend split", "Path A");
            g.add("End", "uml-final-symbolic", "end");
            g.add("Swimlane", "uml-swimlane-symbolic", "|Swimlane|", "Swimlane");
            g.add("Partition", "uml-package-symbolic", "partition Partition {\n  :Action;\n}", "Partition");
            g.add("Note", "uml-note-symbolic", "note right: Note text", "Note text");

            g = plantuml("State", DiagramType.STATE);
            g.add("State", "uml-state-symbolic", "state StateName", "StateName");
            g.add("Initial transition", "uml-initial-symbolic", "[*] --> StateName", "StateName");
            g.add("Final transition", "uml-final-symbolic", "StateName --> [*]", "StateName");
            g.add("Transition", "uml-directed-symbolic", "StateA --> StateB : event", "event");
            g.add("Composite state", "uml-state-symbolic", "state Composite {\n  [*] --> Inner\n  Inner --> [*]\n}", "Composite");
            g.add("Choice", "uml-decision-symbolic", "state Choice <<choice>>", "Choice");
            g.add("Fork", "uml-fork-symbolic", "state Fork <<fork>>", "Fork");
            g.add("Join", "uml-fork-symbolic", "state Join <<join>>", "Join");
            g.add("Concurrent regions", "view-dual-symbolic",
                  "state Active {\n  [*] --> Running\n  --\n  [*] --> Logging\n}", "Active");
            g.add("History", "document-open-recent-symbolic",
                  "state Resumable {\n  [*] --> Step\n}\nStateA --> Resumable[H]", "Resumable");
            g.add("Deep history", "document-open-recent-symbolic",
                  "state Nested {\n  [*] --> Inner\n}\nStateA --> Nested[H*]", "Nested");
            g.add("Entry and exit points", "uml-state-symbolic",
                  "state Machine {\n  state entry1 <<entryPoint>>\n  state exit1 <<exitPoint>>\n  entry1 --> Work\n  Work --> exit1\n}",
                  "Machine");
            g.add("Note on link", "uml-note-symbolic", "StateA --> StateB\nnote on link\n  Note text\nend note", "Note text");
            g.add("Note", "uml-note-symbolic", "note \"Note text\" as N1", "Note text");

            g = plantuml("Component", DiagramType.COMPONENT);
            g.add("Component", "uml-component-symbolic", "component ComponentName", "ComponentName");
            g.add("Interface", "uml-interface-symbolic", "interface InterfaceName", "InterfaceName");
            g.add("Package", "uml-package-symbolic", "package PackageName {\n  component Inner\n}", "PackageName");
            g.add("Database", "uml-database-symbolic", "database Database", "Database");
            g.add("Provided interface", "uml-association-symbolic", "ComponentName - InterfaceName", "InterfaceName");
            g.add("Required interface", "uml-dependency-symbolic", "ComponentName ..> InterfaceName : use", "use");
            g.add("Link", "uml-directed-symbolic", "ComponentA --> ComponentB : label", "label");
            g.add("Ports", "uml-component-symbolic",
                  "component Server {\n  port p1\n  portin in1\n  portout out1\n}", "Server");
            g.add("Queue", "uml-database-symbolic", "queue Queue", "Queue");
            g.add("Thick link", "uml-thick-arrow-symbolic", "ComponentA -[thickness=3]-> Target", "Target");
            g.add("Orthogonal lines", "view-grid-symbolic", "skinparam linetype ortho");
            g.add("Legend", "uml-note-symbolic", "legend right\n  Legend text\nendlegend", "Legend text");
            g.add("Note", "uml-note-symbolic", "note \"Note text\" as N1", "Note text");

            // Deployment files (node, artifact, cloud) are description diagrams, which
            // the component parser draws
            g = plantuml("Deployment", DiagramType.COMPONENT);
            g.add("Node", "uml-node-symbolic", "node NodeName", "NodeName");
            g.add("Node with artifact", "uml-node-symbolic", "node Server {\n  artifact app.jar\n}", "Server");
            g.add("Artifact", "text-x-generic-symbolic", "artifact ArtifactName", "ArtifactName");
            g.add("Cloud", "weather-overcast-symbolic", "cloud CloudName", "CloudName");
            g.add("Database", "uml-database-symbolic", "database DatabaseName", "DatabaseName");
            g.add("Communication path", "uml-association-symbolic", "NodeA -- NodeB : protocol", "protocol");
            g.add("Dependency", "uml-dependency-symbolic", "NodeA ..> NodeB : label", "label");
            g.add("Note", "uml-note-symbolic", "note \"Note text\" as N1", "Note text");

            g = plantuml("Object", DiagramType.OBJECT);
            g.add("Object", "uml-object-symbolic", "object ObjectName {\n  field = value\n}", "ObjectName");
            g.add("Map", "view-list-symbolic", "map MapName {\n  key => value\n}", "MapName");
            g.add("Link", "uml-association-symbolic", "ObjectA -- ObjectB", "ObjectB");
            g.add("Directed link", "uml-directed-symbolic", "ObjectA --> ObjectB", "ObjectB");
            g.add("Aggregation", "uml-aggregation-symbolic", "ObjectA o-- ObjectB", "ObjectB");
            g.add("Composition", "uml-composition-symbolic", "ObjectA *-- ObjectB", "ObjectB");
            g.add("JSON object", "text-x-generic-symbolic", "json Config {\n  \"key\": \"value\"\n}", "Config");
            g.add("Note", "uml-note-symbolic", "note \"Note text\" as N1", "Note text");

            g = plantuml("Entity Relationship", DiagramType.ER_DIAGRAM);
            g.add("Entity", "uml-class-symbolic", "entity EntityName {\n  * id : number <<generated>>\n  --\n  name : text\n}", "EntityName");
            g.add("Exactly one to exactly one", "uml-er-one-to-one-symbolic", "EntityA ||--|| EntityB", "EntityB");
            g.add("Exactly one to zero or many", "uml-er-one-to-many-symbolic", "EntityA ||--o{ EntityB", "EntityB");
            g.add("Exactly one to one or many", "uml-er-one-to-many-symbolic", "EntityA ||--|{ EntityB", "EntityB");
            g.add("Zero or one to exactly one", "uml-er-one-to-one-symbolic", "EntityA |o--|| EntityB", "EntityB");
            g.add("Zero or many to zero or many", "uml-er-many-to-many-symbolic", "EntityA }o--o{ EntityB", "EntityB");

            g = plantuml("Mind Map", DiagramType.MINDMAP);
            g.add("Child node", "uml-mindmap-symbolic", "** Child", "Child");
            g.add("Sub-topic", "go-next-symbolic", "*** Sub-topic", "Sub-topic");
            g.add("Left side", "go-previous-symbolic", "left side\n** Left branch", "Left branch");
            g.add("Boxless node", "format-text-plaintext-symbolic", "**_ Boxless", "Boxless");
            g.add("Colored node", "preferences-color-symbolic", "**[#lightgreen] Colored", "Colored");

            g = plantuml("Gantt", DiagramType.GANTT);
            g.add("Project start", "x-office-calendar-symbolic", "Project starts 2026-01-05", "2026-01-05");
            g.add("Task", "uml-task-symbolic", "[New task] requires 5 days", "New task");
            g.add("Task after task", "uml-task-symbolic", "[Next task] requires 3 days\n[Next task] starts at [Task A]'s end", "Next task");
            g.add("Milestone", "uml-decision-symbolic", "[Milestone] happens at [Task A]'s end", "Milestone");
            g.add("Dependency", "uml-directed-symbolic", "[Task A] -> [Task B]", "Task B");
            g.add("Completion", "checkbox-checked-symbolic", "[Task A] is 40% completed", "40");
            g.add("Closed days", "x-office-calendar-symbolic", "saturday are closed\nsunday are closed", "saturday");
            g.add("Task lasting days", "uml-task-symbolic", "[New task] lasts 5 days", "New task");
            g.add("Then", "uml-task-symbolic", "then [Follow-up] requires 2 days", "Follow-up");
            g.add("Task alias", "uml-task-symbolic", "[Long task name] as [LT] lasts 4 days", "Long task name");
            g.add("Dated task", "x-office-calendar-symbolic", "[Dated task] starts 2026-01-12 and ends 2026-01-16", "Dated task");
            g.add("Resources", "system-users-symbolic", "[Staffed task] on {Alice:50%} {Bob} lasts 4 days", "Alice");
            g.add("Task colour", "preferences-color-symbolic", "[Task A] is colored in LightBlue/Blue", "LightBlue");
            g.add("Separator", "list-remove-symbolic", "-- Phase 2 --", "Phase 2");
            g.add("Closed date", "x-office-calendar-symbolic", "2026-01-19 is closed", "2026-01-19");
            g.add("Today", "alarm-symbolic", "today is 2026-01-08 and is colored in #AAF", "2026-01-08");
            g.add("Print scale", "zoom-in-symbolic", "printscale weekly zoom 2", "weekly");
            g.add("Hide resource names", "view-conceal-symbolic", "hide ressources names");
            g.add("Note", "uml-note-symbolic", "note bottom\n  Note text\nend note", "Note text");

            g = plantuml("Timing", DiagramType.TIMING);
            g.add("Concise signal", "uml-task-symbolic", "concise \"Concise\" as C", "Concise");
            g.add("Robust signal", "uml-waveform-symbolic", "robust \"Robust\" as R", "Robust");
            g.add("Binary signal", "uml-waveform-symbolic", "binary \"Binary\" as B", "Binary");
            g.add("Clock", "preferences-system-time-symbolic", "clock \"Clock\" as CLK with period 50", "Clock");
            g.add("Time point", "alarm-symbolic", "@100\nU is Busy", "Busy");
            g.add("Message", "uml-directed-symbolic", "U -> U@200 : message", "message");
            g.add("Analog signal", "uml-waveform-symbolic", "analog \"Analog\" between 0 and 10 as A", "Analog");
            g.add("Rectangle signal", "uml-task-symbolic", "rectangle \"Rectangle\" as RE", "Rectangle");
            g.add("Clock with pulse", "preferences-system-time-symbolic",
                  "clock \"Pulse\" as PLS with period 50 pulse 15 offset 10", "Pulse");
            g.add("Participant timeline", "view-continuous-symbolic", "@U\n100 is Busy\n+50 is Idle", "Busy");
            g.add("Anchor", "mark-location-symbolic", "@150 as :done\nU is Done", "done");
            g.add("Constraint", "object-flip-horizontal-symbolic", "U@0 <-> @100 : {100 ms}", "100 ms");
            g.add("Highlight", "preferences-color-symbolic", "highlight 0 to 100 #Gold : Setup", "Setup");
            g.add("Note", "uml-note-symbolic", "note top of U : Note text", "Note text");
            g.add("Scale", "zoom-in-symbolic", "scale 100 as 50 pixels", "50");
            g.add("Hide time axis", "view-conceal-symbolic", "hide time-axis");
            g.add("Compact mode", "view-list-bullet-symbolic", "mode compact");

            // C4-PlantUML from the bundled stdlib; the expanded model is a component diagram
            g = plantuml("C4", DiagramType.COMPONENT);
            g.add("C4 include", "document-open-symbolic", "!include <C4/C4_Container>", "C4_Container");
            g.add("Person", "uml-actor-symbolic", "Person(customer, \"Customer\", \"A customer\")", "Customer");
            g.add("External person", "uml-actor-symbolic", "Person_Ext(partner, \"Partner\")", "Partner");
            g.add("System", "uml-component-symbolic", "System(system, \"System\", \"Description\")", "Description");
            g.add("External system", "uml-component-symbolic", "System_Ext(external, \"External System\")", "External System");
            g.add("Container", "uml-component-symbolic",
                  "Container(app, \"Application\", \"Technology\", \"Description\")", "Application");
            g.add("Container database", "uml-database-symbolic", "ContainerDb(store, \"Database\", \"SQL\")", "Database");
            g.add("Boundary", "uml-package-symbolic",
                  "System_Boundary(boundary, \"Boundary\") {\n  Container(api, \"API\", \"Vala\")\n}", "Boundary");
            g.add("Relationship", "uml-directed-symbolic", "Rel(user, sys, \"Uses\", \"HTTPS\")", "Uses");
            g.add("Relationship right", "go-next-symbolic", "Rel_R(user, sys, \"Calls\")", "Calls");
            g.add("Bidirectional", "uml-association-symbolic", "BiRel(user, sys, \"Syncs\")", "Syncs");
            g.add("Element tag", "preferences-color-symbolic", "AddElementTag(\"critical\", $bgColor=\"#C00000\")", "critical");
            g.add("Left to right layout", "object-rotate-right-symbolic", "LAYOUT_LEFT_RIGHT()");
            g.add("Legend", "uml-note-symbolic", "SHOW_LEGEND()");

            // Whole-document types: the snippets are complete bodies or add to one
            g = plantuml("Board", DiagramType.BOARD);
            g.add("Column", "view-dual-symbolic", "Column\n+ Card", "Column");
            g.add("Card", "uml-task-symbolic", "+ Card", "Card");
            g.add("Sub-card", "go-next-symbolic", "++ Sub-card", "Sub-card");

            g = plantuml("Chen ER", DiagramType.CHEN_ER);
            g.add("Entity", "uml-class-symbolic",
                  "entity Movie {\n  Code <<key>>\n  Title\n  Age <<derived>>\n}", "Movie");
            g.add("Relationship", "uml-decision-symbolic", "relationship Rents {\n}\nPerson -N- Rents", "Rents");

            g = plantuml("EBNF", DiagramType.EBNF);
            g.add("Rule", "format-justify-left-symbolic", "identifier = letter, { letter | digit } ;", "identifier");
            g.add("Optional", "format-justify-left-symbolic", "sign = [ \"-\" ] ;", "sign");
            g.add("Alternatives", "format-justify-left-symbolic", "digit = \"0\" | \"1\" | \"2\" ;", "digit");

            g = plantuml("Regex", DiagramType.REGEX_DIAGRAM);
            g.add("Regular expression", "edit-find-symbolic", "^[a-z]+(\\d{2,4})?$", "[a-z]+");

            g = plantuml("Salt", DiagramType.SALT);
            g.add("Form", "view-grid-symbolic",
                  "{\n  Login    | \"user\"\n  Password | \"****\"\n  [Cancel] | [  OK  ]\n}", "user");
            g.add("Tree", "view-list-symbolic", "{T\n  + Root\n  ++ Child\n}", "Root");

            g = plantuml("Ditaa", DiagramType.DITAA);
            g.add("Boxes", "view-grid-symbolic",
                  "+--------+   +--------+\n| Client |-->| Server |\n+--------+   +--------+", "Client");

            // @startpacketdiag documents are read by the Mermaid packet parser
            g = plantuml("Packet", DiagramType.MERMAID_PACKET);
            g.add("Packet", "view-grid-symbolic",
                  "packetdiag {\n  colwidth = 32\n  node_height = 72\n  0-15: Source Port\n  16-31: Destination Port\n  32-63: Sequence Number\n}",
                  "Source Port");

            g = plantuml("Network", DiagramType.NWDIAG);
            g.add("Network", "network-server-symbolic",
                  "nwdiag {\n  network dmz {\n    address = \"210.x.x.x/24\"\n    web01 [address = \"210.x.x.1\"];\n    web02 [address = \"210.x.x.2\"];\n  }\n  group web {\n    web01;\n    web02;\n  }\n}",
                  "dmz");

            g = plantuml("ArchiMate", DiagramType.ARCHIMATE);
            g.add("Business actor", "uml-actor-symbolic",
                  "archimate #Business \"Customer\" as customer <<business-actor>>", "Customer");
            g.add("Application component", "uml-component-symbolic",
                  "archimate #Application \"Application\" as app <<application-component>>", "Application");
            g.add("Technology node", "uml-node-symbolic",
                  "archimate #Technology \"Server\" as server <<technology-node>>", "Server");
            // No chronology group: the reference PlantUML (1.2026.8, GPL) rejects @startchronology
        }

        private static void add_mermaid_groups() {
            var g = mermaid("General", DiagramType.UNKNOWN);
            g.add("Comment", "chat-message-new-symbolic", "%% comment", "comment");
            g.add("Theme", "preferences-desktop-appearance-symbolic", "%%{init: {\"theme\": \"forest\"}}%%", "forest");
            g.add("Accessible title", "format-text-bold-symbolic", "accTitle: Diagram Title", "Diagram Title");

            g = mermaid("Flowchart", DiagramType.MERMAID_FLOWCHART);
            g.add("Process", "uml-process-symbolic", "P1[Process]", "Process");
            g.add("Rounded node", "uml-action-symbolic", "R1(Rounded)", "Rounded");
            g.add("Stadium", "uml-action-symbolic", "S1([Stadium])", "Stadium");
            g.add("Decision", "uml-decision-symbolic", "D1{Decision?}", "Decision?");
            g.add("Circle", "uml-circle-symbolic", "C1((Circle))", "Circle");
            g.add("Database", "uml-database-symbolic", "DB1[(Database)]", "Database");
            g.add("Link", "uml-directed-symbolic", "A --> B", "B");
            g.add("Labeled link", "uml-directed-symbolic", "A -->|label| B", "label");
            g.add("Dotted link", "uml-dependency-symbolic", "A -.-> B", "B");
            g.add("Thick link", "uml-thick-arrow-symbolic", "A ==> B", "B");
            g.add("Subgraph", "uml-package-symbolic", "subgraph Subgraph\n    X --> Y\nend", "Subgraph");
            g.add("Class definition", "preferences-color-symbolic", "classDef highlight fill:#f9f,stroke:#333\nclass A highlight", "highlight");

            g = mermaid("Sequence", DiagramType.MERMAID_SEQUENCE);
            g.add("Participant", "uml-lifeline-symbolic", "participant Participant", "Participant");
            g.add("Actor", "uml-actor-symbolic", "actor Actor", "Actor");
            g.add("Synchronous message", "uml-message-symbolic", "Alice->>Bob: message", "message");
            g.add("Reply message", "uml-dependency-symbolic", "Bob-->>Alice: reply", "reply");
            g.add("Asynchronous message", "uml-directed-symbolic", "Alice-)Bob: message", "message");
            g.add("Alternative", "uml-fragment-symbolic",
                  "alt condition\n    Alice->>Bob: yes\nelse otherwise\n    Alice->>Bob: no\nend", "condition");
            g.add("Loop", "media-playlist-repeat-symbolic", "loop condition\n    Alice->>Bob: message\nend", "condition");
            g.add("Note", "uml-note-symbolic", "Note right of Alice: Note text", "Note text");
            g.add("Activation", "media-playback-start-symbolic", "activate Bob\nBob-->>Alice: done\ndeactivate Bob", "done");
            g.add("Autonumber", "view-list-ordered-symbolic", "autonumber");

            g = mermaid("Class", DiagramType.MERMAID_CLASS);
            g.add("Class", "uml-class-symbolic", "class ClassName {\n    +String field\n    +method() void\n}", "ClassName");
            g.add("Interface", "uml-interface-symbolic", "class InterfaceName {\n    <<interface>>\n    +operation() void\n}", "InterfaceName");
            g.add("Enumeration", "view-list-bullet-symbolic", "class EnumName {\n    <<enumeration>>\n    VALUE_A\n    VALUE_B\n}", "EnumName");
            g.add("Association", "uml-directed-symbolic", "ClassA --> ClassB : label", "label");
            g.add("Link", "uml-association-symbolic", "ClassA -- ClassB", "ClassB");
            g.add("Inheritance", "uml-generalization-symbolic", "Parent <|-- Child", "Child");
            g.add("Realization", "uml-realization-symbolic", "InterfaceName <|.. Implementation", "Implementation");
            g.add("Aggregation", "uml-aggregation-symbolic", "Whole o-- Part", "Part");
            g.add("Composition", "uml-composition-symbolic", "Whole *-- Part", "Part");
            g.add("Dependency", "uml-dependency-symbolic", "Client ..> Supplier", "Supplier");
            g.add("Cardinality", "uml-association-symbolic", "Customer \"1\" --> \"*\" Order : places", "places");
            g.add("Note", "uml-note-symbolic", "note for ClassA \"Note text\"", "Note text");

            g = mermaid("State", DiagramType.MERMAID_STATE);
            g.add("State", "uml-state-symbolic", "state \"Description\" as StateName", "Description");
            g.add("Initial transition", "uml-initial-symbolic", "[*] --> StateName", "StateName");
            g.add("Final transition", "uml-final-symbolic", "StateName --> [*]", "StateName");
            g.add("Transition", "uml-directed-symbolic", "StateA --> StateB : event", "event");
            g.add("Composite state", "uml-state-symbolic", "state Composite {\n    [*] --> Inner\n    Inner --> [*]\n}", "Composite");
            g.add("Choice", "uml-decision-symbolic", "state Choice <<choice>>", "Choice");
            g.add("Fork", "uml-fork-symbolic", "state Fork <<fork>>", "Fork");
            g.add("Join", "uml-fork-symbolic", "state Join <<join>>", "Join");
            // The note's state is written first: Mermaid fails on a note for a state no line created
            g.add("Note", "uml-note-symbolic", "StateName\nnote right of StateName : Note text", "Note text");

            g = mermaid("Entity Relationship", DiagramType.MERMAID_ER);
            g.add("Entity", "uml-class-symbolic", "ENTITY {\n    string id PK\n    string name\n}", "ENTITY");
            g.add("Exactly one to exactly one", "uml-er-one-to-one-symbolic", "A ||--|| B : has", "has");
            g.add("Exactly one to zero or many", "uml-er-one-to-many-symbolic", "A ||--o{ B : has", "has");
            g.add("Exactly one to one or many", "uml-er-one-to-many-symbolic", "A ||--|{ B : contains", "contains");
            g.add("Zero or one to zero or one", "uml-er-one-to-one-symbolic", "A |o--o| B : pairs", "pairs");
            g.add("Zero or many to zero or many", "uml-er-many-to-many-symbolic", "A }o--o{ B : relates", "relates");
            g.add("Non-identifying", "uml-dependency-symbolic", "A ||..o{ B : references", "references");

            g = mermaid("Gantt", DiagramType.MERMAID_GANTT);
            g.add("Title", "format-text-bold-symbolic", "title Project plan", "Project plan");
            g.add("Section", "view-paged-symbolic", "section Section", "Section");
            g.add("Task", "uml-task-symbolic", "New task :t2, after a1, 3d", "New task");
            g.add("Done task", "checkbox-checked-symbolic", "Done task :done, t3, 2026-01-05, 2d", "Done task");
            g.add("Active task", "media-playback-start-symbolic", "Active task :active, t4, after a1, 3d", "Active task");
            g.add("Critical task", "dialog-warning-symbolic", "Critical task :crit, t5, after a1, 2d", "Critical task");
            g.add("Milestone", "uml-decision-symbolic", "Milestone :milestone, m1, after a1, 0d", "Milestone");
            g.add("Exclude weekends", "x-office-calendar-symbolic", "excludes weekends");
        }
    }

    /**
     * When the element palette reorders its groups (the rendered type's group moves to
     * the top). Reordering right after a click moved another group under the pointer,
     * so the next click at the same spot hit a different snippet: while the pointer is
     * over the palette a type change only waits, and it applies when the pointer leaves.
     * An undetectable type (an empty or broken document mid-edit) keeps the order.
     */
    public class PaletteOrderPolicy : Object {
        public DiagramType applied_type { get; private set; default = DiagramType.UNKNOWN; }
        public DiagramFormat applied_format { get; private set; default = DiagramFormat.UNKNOWN; }
        public bool pointer_inside { get; private set; default = false; }
        private bool has_pending = false;
        private DiagramType pending_type = DiagramType.UNKNOWN;
        private DiagramFormat pending_format = DiagramFormat.UNKNOWN;
        private bool applied_once = false;

        /** A render detected `type`. True: reorder for applied_type/applied_format now. */
        public bool request(DiagramType type, DiagramFormat format) {
            if (type == DiagramType.UNKNOWN && applied_once) return false;
            if (applied_once && type == applied_type && format == applied_format) {
                has_pending = false;
                return false;
            }
            if (pointer_inside) {
                has_pending = true;
                pending_type = type;
                pending_format = format;
                return false;
            }
            apply(type, format);
            return true;
        }

        public void pointer_entered() {
            pointer_inside = true;
        }

        /** The pointer left the palette. True: a waiting reorder applies now. */
        public bool pointer_left() {
            pointer_inside = false;
            if (!has_pending) return false;
            has_pending = false;
            apply(pending_type, pending_format);
            return true;
        }

        private void apply(DiagramType type, DiagramFormat format) {
            applied_type = type;
            applied_format = format;
            applied_once = true;
        }
    }
}
