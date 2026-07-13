namespace GDiagram {

    // ==================== MERMAID EVENT MODELING ====================
    //
    // Mermaid 12.2.0's `eventmodeling` diagram: a banded timeline of event-modeling
    // frames (UI, command, event, read model, processor) laid out across swimlanes in
    // declaration order, with relations drawn between consecutive frames.
    //
    // The grammar is the langium one shipped in @mermaid-js/parser 12.2.0
    // (src/language/eventmodeling), recovered verbatim:
    //
    //   EventModel  : 'eventmodeling' (accDescr | accTitle | title
    //                                 | EmModelEntity | EmFrame | EmDataEntity
    //                                 | EmNoteEntity | EmGwt)*
    //   EmTimeFrame : ('tf'|'timeframe') name=EM_FI modelEntityType entityIdentifier=QualifiedName
    //                 ('->>' sourceFrames+=[EmFrame])* ('[[' dataReference ']]')? EmDataInline?
    //   EmResetFrame: ('rf'|'resetframe') … same tail …
    //   EmModelEntity : 'entity' name=QualifiedName
    //   EmDataEntity  : 'data' name=EM_EID EmDataBlock
    //   EmNoteEntity  : 'note' sourceFrame=[EmFrame] EmDataBlock
    //   EmGwt         : 'gwt' sourceFrame=[EmFrame] 'given' stmt+ ('when' stmt+)? 'then' stmt+
    //   EmGwtStatement: modelEntityType entityIdentifier=[EmModelEntity]
    //   EM_FI  = /\d{1,3}/          (frame id: one to three digits)
    //   EM_ID  = /[_a-zA-Z][\w_]*/  (entity id)
    //
    // `note` and `gwt` are parsed and kept on the AST but never drawn: mermaid
    // 12.2.0's own renderer (eventmodeling/renderer.ts) draws only swimlanes, boxes
    // and relations. gDiagram matches that.

    /** `modelEntityType` — the five kinds, each with its band and colours. */
    public enum EmEntityKind {
        UI,
        PROCESSOR,
        READ_MODEL,
        COMMAND,
        EVENT;

        /** The keyword pairs mermaid accepts for each kind. */
        public static bool try_parse(string word, out EmEntityKind kind) {
            switch (word) {
                case "ui":                       kind = EmEntityKind.UI;         return true;
                case "pcr": case "processor":    kind = EmEntityKind.PROCESSOR;  return true;
                case "rmo": case "readmodel":    kind = EmEntityKind.READ_MODEL; return true;
                case "cmd": case "command":      kind = EmEntityKind.COMMAND;    return true;
                case "evt": case "event":        kind = EmEntityKind.EVENT;      return true;
                default:                         kind = EmEntityKind.EVENT;      return false;
            }
        }

        /**
         * Swimlane band base index (db.ts `calculateSwimlaneProps`): UI and processors
         * share band 0, commands and read models band 100, events band 200. A frame
         * without a namespace lands exactly on the base index; a namespaced one takes
         * the next free index inside its band.
         */
        public int band_base() {
            switch (this) {
                case EmEntityKind.UI:
                case EmEntityKind.PROCESSOR:
                    return 0;
                case EmEntityKind.READ_MODEL:
                case EmEntityKind.COMMAND:
                    return 100;
                default:
                    return 200;
            }
        }

        public int band_limit() {
            return band_base() + 100;
        }

        /** Lane label for a frame with no namespace. */
        public string band_label() {
            switch (this) {
                case EmEntityKind.UI:
                case EmEntityKind.PROCESSOR:
                    return "UI/Automation";
                case EmEntityKind.READ_MODEL:
                case EmEntityKind.COMMAND:
                    return "Command/Read Model";
                default:
                    return "Events";
            }
        }

        /** Lane label prefix for a namespaced frame. */
        public string band_prefix() {
            switch (this) {
                case EmEntityKind.UI:
                case EmEntityKind.PROCESSOR:
                    return "UI/A: ";
                case EmEntityKind.READ_MODEL:
                case EmEntityKind.COMMAND:
                    return "C/RM: ";
                default:
                    return "Stream: ";
            }
        }

        /** Box fill, from db.ts `calculateEntityVisualProps` (default theme). */
        public string fill_color() {
            switch (this) {
                case EmEntityKind.UI:         return "#ffffff";
                case EmEntityKind.PROCESSOR:  return "#edb3f6";
                case EmEntityKind.READ_MODEL: return "#d3f1a2";
                case EmEntityKind.COMMAND:    return "#bcd6fe";
                default:                      return "#ffb778";
            }
        }

        /** Box stroke, from db.ts `calculateEntityVisualProps` (default theme). */
        public string stroke_color() {
            switch (this) {
                case EmEntityKind.UI:         return "#dbdada";
                case EmEntityKind.PROCESSOR:  return "#b88cbf";
                case EmEntityKind.READ_MODEL: return "#a3b732";
                case EmEntityKind.COMMAND:    return "#679ac3";
                default:                      return "#c19a0f";
            }
        }

        /** The canonical keyword, for the outline and stats. */
        public string keyword() {
            switch (this) {
                case EmEntityKind.UI:         return "ui";
                case EmEntityKind.PROCESSOR:  return "pcr";
                case EmEntityKind.READ_MODEL: return "rmo";
                case EmEntityKind.COMMAND:    return "cmd";
                default:                      return "evt";
            }
        }
    }

    /** One `tf` / `rf` frame — a box in the drawing. */
    public class EmFrame : Object {
        /** `name=EM_FI`, the one-to-three digit frame id as written ("01"). */
        public string name { get; set; }
        public EmEntityKind kind { get; set; }
        /** `entityIdentifier=QualifiedName` as written ("Shop.OrderPlaced"). */
        public string entity_identifier { get; set; }
        /**
         * The namespace — the part before the dot, but only for a two-part name.
         * db.ts `extractNamespace` returns undefined for one part and for three or
         * more, so "a.b.c" has no namespace and keeps its whole text as the label.
         */
        public string? ns { get; set; }
        /** The drawn label — the part after the dot of a two-part name, else all of it. */
        public string entity_name { get; set; }
        /** `rf` / `resetframe`: no implicit relation is drawn into this frame. */
        public bool is_reset { get; set; default = false; }
        /** `->>NN` source frame ids, in source order. */
        public Gee.ArrayList<string> source_frames { get; private set; }
        /** `[[name]]` reference to a `data` entity. */
        public string? data_reference { get; set; }
        /** Inline data as written, braces/quotes included. */
        public string? data_inline { get; set; }
        /** Backtick data type (`json`, `md`, …) preceding the data, if any. */
        public string? data_type { get; set; }
        public int source_line { get; set; }
        /** 0-based declaration order; the relation rules index frames by it. */
        public int index { get; set; }

        public EmFrame(string name, EmEntityKind kind, string entity_identifier, int line) {
            this.name = name;
            this.kind = kind;
            this.entity_identifier = entity_identifier;
            this.source_line = line;
            this.source_frames = new Gee.ArrayList<string>();
            split_identifier(entity_identifier, out _ns, out _entity_name);
        }

        /**
         * db.ts `extractNamespace` / `extractName`: only a *two*-part dotted name has
         * a namespace. Anything else keeps its whole text and gets no namespace.
         */
        public static void split_identifier(string id, out string? ns, out string name) {
            string[] parts = id.split(".");
            if (parts.length == 2) {
                ns = parts[0];
                name = parts[1];
            } else {
                ns = null;
                name = id;
            }
        }
    }

    /** `data NAME { … }` — a reusable data block a frame can reference with `[[NAME]]`. */
    public class EmDataEntity : Object {
        public string name { get; set; }
        /** The block's inner text, braces stripped, as written. */
        public string body { get; set; }
        public string? data_type { get; set; }
        public int source_line { get; set; }

        public EmDataEntity(string name, string body, int line) {
            this.name = name;
            this.body = body;
            this.source_line = line;
        }
    }

    /** `entity Some.Name` — declares a model entity a `gwt` statement can reference. */
    public class EmModelEntity : Object {
        public string name { get; set; }
        public int source_line { get; set; }

        public EmModelEntity(string name, int line) {
            this.name = name;
            this.source_line = line;
        }
    }

    /** `note NN { … }` — parsed, kept, and (like mermaid 12.2.0) not drawn. */
    public class EmNote : Object {
        public string frame_name { get; set; }
        public string body { get; set; }
        public string? data_type { get; set; }
        public int source_line { get; set; }

        public EmNote(string frame_name, string body, int line) {
            this.frame_name = frame_name;
            this.body = body;
            this.source_line = line;
        }
    }

    /** One `<kind> <entity>` item inside a `gwt`. */
    public class EmGwtStatement : Object {
        public EmEntityKind kind { get; set; }
        public string entity_identifier { get; set; }

        public EmGwtStatement(EmEntityKind kind, string entity_identifier) {
            this.kind = kind;
            this.entity_identifier = entity_identifier;
        }
    }

    /** `gwt NN given … when … then …` — parsed, kept, and not drawn. */
    public class EmGwt : Object {
        public string frame_name { get; set; }
        public Gee.ArrayList<EmGwtStatement> given { get; private set; }
        public Gee.ArrayList<EmGwtStatement> when_items { get; private set; }
        public Gee.ArrayList<EmGwtStatement> then_items { get; private set; }
        public int source_line { get; set; }

        public EmGwt(string frame_name, int line) {
            this.frame_name = frame_name;
            this.source_line = line;
            this.given = new Gee.ArrayList<EmGwtStatement>();
            this.when_items = new Gee.ArrayList<EmGwtStatement>();
            this.then_items = new Gee.ArrayList<EmGwtStatement>();
        }
    }

    public class MermaidEventModeling : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<EmFrame> frames { get; private set; }
        public Gee.ArrayList<EmDataEntity> data_entities { get; private set; }
        public Gee.ArrayList<EmModelEntity> model_entities { get; private set; }
        public Gee.ArrayList<EmNote> notes { get; private set; }
        public Gee.ArrayList<EmGwt> gwts { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }
        public string? acc_title { get; set; }
        public string? acc_descr { get; set; }

        public MermaidEventModeling() {
            this.diagram_type = MermaidDiagramType.EVENT_MODELING;
            this.frames = new Gee.ArrayList<EmFrame>();
            this.data_entities = new Gee.ArrayList<EmDataEntity>();
            this.model_entities = new Gee.ArrayList<EmModelEntity>();
            this.notes = new Gee.ArrayList<EmNote>();
            this.gwts = new Gee.ArrayList<EmGwt>();
            this.errors = new Gee.ArrayList<ParseError>();
        }

        public EmFrame? find_frame(string name) {
            foreach (var f in frames) {
                if (f.name == name) return f;
            }
            return null;
        }

        public EmDataEntity? find_data(string name) {
            foreach (var d in data_entities) {
                if (d.name == name) return d;
            }
            return null;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
