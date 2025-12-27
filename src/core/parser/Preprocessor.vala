namespace GPlantUML {
    /**
     * Preprocessor handles PlantUML preprocessing directives before lexing.
     *
     * Supported directives:
     * - !include <filename>  - Include another file (relative or absolute path)
     * - !include <filename>  - Include from standard library (future)
     *
     * Future support:
     * - !define NAME VALUE   - Define a macro
     * - !ifdef/!endif        - Conditional compilation
     * - !theme               - Theme directive
     *
     * Usage:
     *   var preprocessor = new Preprocessor();
     *   string processed = preprocessor.process(source, base_path);
     *   var lexer = new Lexer(processed);
     */
    public class Preprocessor : Object {
        // Track included files to prevent circular includes
        private Gee.HashSet<string> included_files;

        // Maximum include depth to prevent infinite recursion
        private const int MAX_INCLUDE_DEPTH = 10;

        // Errors encountered during preprocessing
        public Gee.ArrayList<PreprocessorError> errors { get; private set; }

        public Preprocessor() {
            this.included_files = new Gee.HashSet<string>();
            this.errors = new Gee.ArrayList<PreprocessorError>();
        }

        /**
         * Process source content, expanding all preprocessor directives.
         *
         * @param source The PlantUML source content
         * @param base_path The directory path for resolving relative includes (can be null)
         * @return The preprocessed source with all includes expanded
         */
        public string process(string source, string? base_path) {
            included_files.clear();
            errors.clear();
            return process_internal(source, base_path, 0);
        }

        private string process_internal(string source, string? base_path, int depth) {
            if (depth > MAX_INCLUDE_DEPTH) {
                errors.add(new PreprocessorError(
                    "Maximum include depth (%d) exceeded - possible circular include".printf(MAX_INCLUDE_DEPTH),
                    0
                ));
                return source;
            }

            var result = new StringBuilder();
            var lines = source.split("\n");
            int line_num = 0;

            foreach (var line in lines) {
                line_num++;
                string trimmed = line.strip();

                if (trimmed.has_prefix("!include ") || trimmed.has_prefix("!include\t")) {
                    string include_content = process_include_directive(trimmed, base_path, depth, line_num);
                    result.append(include_content);
                } else if (trimmed.has_prefix("!")) {
                    // Other preprocessor directives - skip for now but preserve as comment
                    // This prevents the lexer from choking on unknown directives
                    result.append("' [preprocessor] ");
                    result.append(line);
                    result.append("\n");
                } else {
                    result.append(line);
                    result.append("\n");
                }
            }

            return result.str;
        }

        private string process_include_directive(string line, string? base_path, int depth, int line_num) {
            // Parse: !include <path> or !include path
            string path = extract_include_path(line);

            if (path == null || path.length == 0) {
                errors.add(new PreprocessorError(
                    "Invalid !include directive: missing path",
                    line_num
                ));
                return "' [preprocessor error] Invalid !include: %s\n".printf(line);
            }

            // Check for standard library includes (future feature)
            if (path.has_prefix("<") && path.has_suffix(">")) {
                // Standard library include - not supported yet
                errors.add(new PreprocessorError(
                    "Standard library includes not yet supported: %s".printf(path),
                    line_num
                ));
                return "' [preprocessor] Unsupported standard library include: %s\n".printf(path);
            }

            // Resolve the file path
            string resolved_path = resolve_path(path, base_path);

            if (resolved_path == null) {
                errors.add(new PreprocessorError(
                    "Cannot resolve include path: %s".printf(path),
                    line_num
                ));
                return "' [preprocessor error] Cannot resolve: %s\n".printf(path);
            }

            // Check for circular includes
            string canonical_path = get_canonical_path(resolved_path);
            if (canonical_path != null && included_files.contains(canonical_path)) {
                // Already included - skip silently (this is valid PlantUML behavior)
                return "' [preprocessor] Already included: %s\n".printf(path);
            }

            if (canonical_path != null) {
                included_files.add(canonical_path);
            }

            // Read the file
            string? content = read_file(resolved_path);
            if (content == null) {
                errors.add(new PreprocessorError(
                    "Cannot read include file: %s".printf(resolved_path),
                    line_num
                ));
                return "' [preprocessor error] Cannot read: %s\n".printf(resolved_path);
            }

            // Get the directory of the included file for nested includes
            string? include_base_path = get_directory(resolved_path);

            // Strip @startuml and @enduml from included content
            string stripped = strip_uml_tags(content);

            // Recursively process the included content
            string processed = process_internal(stripped, include_base_path, depth + 1);

            // Wrap with markers for debugging
            var result = new StringBuilder();
            result.append("' [begin include: %s]\n".printf(path));
            result.append(processed);
            if (!processed.has_suffix("\n")) {
                result.append("\n");
            }
            result.append("' [end include: %s]\n".printf(path));

            return result.str;
        }

        private string? extract_include_path(string line) {
            // !include <path> or !include path or !include "path"
            string after_include = line.substring(8).strip();  // Skip "!include"

            if (after_include.length == 0) {
                return null;
            }

            // Handle quoted paths
            if (after_include.has_prefix("\"") && after_include.has_suffix("\"") && after_include.length > 2) {
                return after_include.substring(1, after_include.length - 2);
            }

            // Handle angle-bracket paths (standard library)
            if (after_include.has_prefix("<") && after_include.has_suffix(">")) {
                return after_include;  // Return with brackets for identification
            }

            // Plain path - take until whitespace or end
            int space_idx = after_include.index_of(" ");
            if (space_idx > 0) {
                return after_include.substring(0, space_idx);
            }

            return after_include;
        }

        private string? resolve_path(string path, string? base_path) {
            // Absolute path
            if (Path.is_absolute(path)) {
                if (FileUtils.test(path, FileTest.EXISTS)) {
                    return path;
                }
                return null;
            }

            // Relative path - resolve against base_path
            if (base_path != null) {
                string full_path = Path.build_filename(base_path, path);
                if (FileUtils.test(full_path, FileTest.EXISTS)) {
                    return full_path;
                }
            }

            // Try current working directory as fallback
            if (FileUtils.test(path, FileTest.EXISTS)) {
                return path;
            }

            return null;
        }

        private string? get_canonical_path(string path) {
            var file = File.new_for_path(path);
            return file.get_path() ?? path;
        }

        private string? get_directory(string path) {
            return Path.get_dirname(path);
        }

        private string? read_file(string path) {
            try {
                string content;
                FileUtils.get_contents(path, out content);
                return content;
            } catch (Error e) {
                return null;
            }
        }

        /**
         * Strip @startuml and @enduml tags from included file content.
         * These tags should only appear in the main file, not in includes.
         */
        private string strip_uml_tags(string content) {
            var result = new StringBuilder();
            var lines = content.split("\n");

            foreach (var line in lines) {
                string trimmed = line.strip().down();
                // Skip @startuml (with or without diagram name) and @enduml
                if (trimmed.has_prefix("@startuml") || trimmed == "@enduml") {
                    continue;
                }
                result.append(line);
                result.append("\n");
            }

            return result.str;
        }

        /**
         * Check if preprocessing produced any errors.
         */
        public bool has_errors() {
            return errors.size > 0;
        }
    }

    /**
     * Represents an error encountered during preprocessing.
     */
    public class PreprocessorError : Object {
        public string message { get; private set; }
        public int line { get; private set; }

        public PreprocessorError(string message, int line) {
            this.message = message;
            this.line = line;
        }
    }
}
