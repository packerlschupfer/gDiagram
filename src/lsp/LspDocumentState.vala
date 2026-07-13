namespace GDiagram {

    /**
     * Tracks the state of a single open document in the LSP server.
     * Stores the URI, content, detected format/type, and last parse errors.
     */
    public class LspDocumentState : Object {
        public string uri { get; set; }
        public string content { get; set; default = ""; }
        public DiagramFormat format { get; set; default = DiagramFormat.UNKNOWN; }
        public DiagramType diagram_type { get; set; default = DiagramType.UNKNOWN; }
        public string language_id { get; set; default = ""; }
        public int version { get; set; default = 0; }

        // Parse error storage
        public Gee.ArrayList<LspDiagnostic> diagnostics { get; private set; }

        // Cached AST references (untyped -- each diagram type has a different class)
        public Object? parsed_ast { get; set; default = null; }

        // Shared engine that owns all parser/renderer instances. Supplied by
        // LspServer (one engine per server). When null (e.g. a unit test that
        // constructs a document directly) a private engine is created lazily
        // on first reparse.
        private DiagramEngine? engine;

        public LspDocumentState(string uri, string content, string language_id, int version,
                                DiagramEngine? engine = null) {
            this.uri = uri;
            this.content = content;
            this.language_id = language_id;
            this.version = version;
            this.engine = engine;
            this.diagnostics = new Gee.ArrayList<LspDiagnostic>();
        }

        /**
         * Re-parse the document content. Delegates detection + preprocessing +
         * parsing to the shared DiagramEngine (no rendering) and populates
         * diagnostics for the two conditions the LSP surfaces: undetectable
         * type and an unsupported (detected-but-unparseable) type.
         */
        public void reparse() {
            diagnostics.clear();
            parsed_ast = null;

            if (content.strip().length == 0) {
                format = DiagramFormat.UNKNOWN;
                diagram_type = DiagramType.UNKNOWN;
                return;
            }

            if (engine == null) {
                engine = new DiagramEngine("dot");
            }

            var result = engine.parse(content, null);
            format = result.format;
            diagram_type = result.diagram_type;
            parsed_ast = result.ast;

            if (diagram_type == DiagramType.UNKNOWN) {
                diagnostics.add(new LspDiagnostic(
                    0, 0, 0, 0,
                    2, // Warning
                    "gdiagram",
                    "Could not detect diagram type from content"
                ));
                return;
            }

            if (result.unsupported) {
                diagnostics.add(new LspDiagnostic(
                    0, 0, 0, 0,
                    2, // Warning
                    "gdiagram",
                    "Unsupported diagram type: %s".printf(diagram_type.to_string())
                ));
            }
        }

        /**
         * Render the document content to SVG bytes. Delegates the full
         * detection + preprocessing + parse + render pipeline to the shared
         * DiagramEngine (which owns all renderer instances), so this class no
         * longer instantiates renderers itself. Returns null if the type is
         * unknown or rendering fails.
         */
        public uint8[]? render_svg() {
            if (content.strip().length == 0) return null;

            if (engine == null) {
                engine = new DiagramEngine("dot");
            }

            return engine.generate_svg(content, null, null);
        }
    }

    /**
     * Simple class representing a single LSP diagnostic.
     */
    public class LspDiagnostic : Object {
        public int start_line { get; set; }
        public int start_char { get; set; }
        public int end_line { get; set; }
        public int end_char { get; set; }
        public int severity { get; set; } // 1=Error, 2=Warning, 3=Info, 4=Hint
        public string source { get; set; }
        public string message { get; set; }

        public LspDiagnostic(int start_line, int start_char, int end_line, int end_char,
                             int severity, string source, string message) {
            this.start_line = start_line;
            this.start_char = start_char;
            this.end_line = end_line;
            this.end_char = end_char;
            this.severity = severity;
            this.source = source;
            this.message = message;
        }
    }
}
