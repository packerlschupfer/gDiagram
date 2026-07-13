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

        // Local path of a file:// document, null for other schemes (untitled:).
        // Relative !include paths resolve against its directory.
        public string? file_path {
            owned get { return LspProtocol.uri_to_path(uri); }
        }

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
            include_error = null;

            if (content.strip().length == 0) {
                format = DiagramFormat.UNKNOWN;
                diagram_type = DiagramType.UNKNOWN;
                return;
            }

            if (engine == null) {
                engine = new DiagramEngine("dot");
            }

            var result = engine.parse(content, null, file_path);
            format = result.format;
            diagram_type = result.diagram_type;
            parsed_ast = result.ast;

            // Preprocessor problems (PlantUML only): an unresolved !include is an error, as in
            // PlantUML and the CLI; the others are warnings
            if (format != DiagramFormat.MERMAID) {
                foreach (var err in engine.preprocessor_errors) {
                    bool is_include = is_include_error(err.message);
                    if (is_include && include_error == null) {
                        include_error = "Line %d: %s".printf(err.line, err.message);
                    }
                    diagnostics.add(line_diagnostic(err.line, is_include ? 1 : 2, err.message));
                }
            }
            if (result.errors != null) {
                foreach (var err in result.errors) {
                    diagnostics.add(line_diagnostic(err.line, 1, err.message));
                }
            }

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
                    "Unsupported diagram type: %s".printf(LspProtocol.diagram_type_name(diagram_type))
                ));
            }
        }

        // First unresolved !include ("Line 2: Cannot resolve include path: x.iuml"), or null
        public string? include_error { get; private set; default = null; }

        // Kept in step with Application.is_include_failure() (the CLI): an include that
        // exists but cannot be read is just as missing from the source as one that could
        // not be resolved at all.
        public static bool is_include_error(string message) {
            return message.has_prefix("Cannot resolve include") ||
                   message.has_prefix("Standard library include not available") ||
                   message.has_prefix("Cannot read include file");
        }

        // An error on a 1-based source line, covering the whole line (0 or past the end: line 1).
        // The end character is in UTF-16 code units, as LSP positions are — char_count()
        // counted code points, so a line with an emoji ended short of its last character.
        private LspDiagnostic line_diagnostic(int line, int severity, string message) {
            string[] lines = content.split("\n");
            int index = (line >= 1 && line <= lines.length) ? line - 1 : 0;
            int length = index < lines.length
                ? LspProtocol.utf16_length(lines[index].replace("\r", "")) : 0;
            return new LspDiagnostic(index, 0, index, length, severity, "gdiagram", message);
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

            return engine.generate_svg(content, null, file_path);
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
