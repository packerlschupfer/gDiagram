# Test suite
gio_dep = dependency('gio-2.0')

# Suppress warnings that originate in Vala-generated C boilerplate — not real bugs:
#  -Wno-discarded-qualifiers  : Vala string property setters store const gchar* in gchar* (safe)
#  -Wno-unused-parameter      : GObject init boilerplate, signal trampolines, async finish fns
#  -Wno-incompatible-pointer-types : g_file_load_contents_finish takes char** but GLib binding uses uint8[]
test_c_suppress = [
  '-Wno-discarded-qualifiers',
  '-Wno-unused-parameter',
  '-Wno-incompatible-pointer-types',
]

# Every test below compiles only its own test .vala file and links the shared
# gdiagram-core static library (built once in src/meson.build). This stops the
# ~180 core Vala files from being recompiled per test executable and sidesteps
# the Meson/Vala cross-directory absolute-path bug entirely, since core sources
# are no longer fed to each test's valac invocation.
#
# The dependency set mirrors gdiagram-core's own — the test's valac must load
# every --pkg referenced by the library's generated internal .vapi. gio-2.0 is
# added for test files that touch GLib.File / Dir directly.
core_test_deps = [
  gtk4_dep,
  libadwaita_dep,
  gee_dep,
  libgvc_dep,
  librsvg_dep,
  cairo_dep,
  soup_dep,
  json_dep,
  libsecret_dep,
  math_dep,
  gio_dep,
]
core_test_vargs = shared_vala_args + ['--target-glib=2.74']
core_test_cargs = shared_c_args + test_c_suppress

# ── Lexer test ────────────────────────────────────────────────
lexer_test = executable('lexer_test',
  ['lexer_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Lexer tests', lexer_test)

# ── Document test ─────────────────────────────────────────────
document_test = executable('document_test',
  ['document_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Document tests', document_test)

# ── Parser test ───────────────────────────────────────────────
# GDiagram.Parser (in SequenceDiagramParser.vala) handles lexing internally.
parser_test = executable('parser_test',
  ['parser_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Parser tests', parser_test)

# ── TypeDetector test ─────────────────────────────────────────
type_detector_test = executable('type_detector_test',
  ['type_detector_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('TypeDetector tests', type_detector_test)

# ── Preprocessor test ─────────────────────────────────────────
preprocessor_test = executable('preprocessor_test',
  ['preprocessor_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Preprocessor tests', preprocessor_test)

# ── Mermaid lexer test ────────────────────────────────────────
mermaid_lexer_test = executable('mermaid_lexer_test',
  ['mermaid_lexer_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Mermaid lexer tests', mermaid_lexer_test)

# ── Mermaid flowchart parser test ─────────────────────────────
mermaid_flowchart_test = executable('mermaid_flowchart_test',
  ['mermaid_flowchart_parser_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Mermaid flowchart parser tests', mermaid_flowchart_test)

# ── Mermaid styling test ──────────────────────────────────────
mermaid_styling_test = executable('mermaid_styling_test',
  ['mermaid_styling_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Mermaid styling tests', mermaid_styling_test)

# ── Mermaid renderer test ─────────────────────────────────────
mermaid_renderer_test = executable('mermaid_renderer_test',
  ['mermaid_renderer_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Mermaid renderer tests', mermaid_renderer_test)

# ── RenderUtils test ──────────────────────────────────────────
render_utils_test = executable('render_utils_test',
  ['render_utils_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('RenderUtils tests', render_utils_test)

# ── Mermaid gantt & pie test ──────────────────────────────────
mermaid_gantt_pie_test = executable('mermaid_gantt_pie_test',
  ['mermaid_gantt_pie_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Mermaid gantt & pie tests', mermaid_gantt_pie_test)

# ── Mermaid integration test ──────────────────────────────────
mermaid_integration_test = executable('mermaid_integration_test',
  ['mermaid_integration_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Mermaid integration tests', mermaid_integration_test)

# ── Utilities test ────────────────────────────────────────────
utilities_test = executable('utilities_test',
  ['utilities_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Utilities tests', utilities_test)

# ── Renderer snapshot tests ───────────────────────────────────
renderer_snapshot_test = executable('renderer_snapshot_test',
  ['renderer_snapshot_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Renderer snapshot tests', renderer_snapshot_test)

# ── Template health test ──────────────────────────────────────
template_health_test = executable('template_health_test',
  ['template_health_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Template health tests', template_health_test)

# ── Element palette test ──────────────────────────────────────
# Every palette snippet, inserted into a minimal diagram, must be detected as
# the intended type and parse without errors.
palette_catalog_test = executable('palette_catalog_test',
  ['palette_catalog_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Palette catalog tests', palette_catalog_test)

# ── PlantUML renderer snapshot tests ──────────────────────────
plantuml_renderer_snapshot_test = executable('plantuml_renderer_snapshot_test',
  ['plantuml_renderer_snapshot_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('PlantUML renderer snapshot tests', plantuml_renderer_snapshot_test)

# ── AST fuzz test ─────────────────────────────────────────────
ast_fuzz_test = executable('ast_fuzz_test',
  ['ast_fuzz_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('AST fuzz tests', ast_fuzz_test)

# ── Examples health test ──────────────────────────────────────
examples_health_test = executable('examples_health_test',
  ['examples_health_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Examples health tests', examples_health_test,
  env: ['GDIAGRAM_EXAMPLES_ROOT=' + meson.project_source_root() / 'examples'],
  timeout: 120,
)

# ── Element inspector test ────────────────────────────────────
# Properties panel core: reads an element from the AST and rewrites the source.
element_inspector_test = executable('element_inspector_test',
  ['element_inspector_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Element inspector tests', element_inspector_test)

# ── LSP protocol unit tests ───────────────────────────────────
# Exercises the pure logic behind the LSP request handlers directly:
# LspProtocol (JSON response builders) and LspDocumentState (format/type
# detection, parsing, diagnostics) — without spinning up the stdio server.
lsp_protocol_test = executable('lsp_protocol_test',
  [
    'lsp_protocol_test.vala',
    meson.project_source_root() / 'src/lsp/LspProtocol.vala',
    meson.project_source_root() / 'src/lsp/LspDocumentState.vala',
  ],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('LSP protocol tests', lsp_protocol_test)

# ── LSP server integration test ───────────────────────────────
# Spawns the built gdiagram-lsp binary and speaks real LSP over its
# stdin/stdout with Content-Length framing. Binary path arrives via env.
# Self-contained (no core sources) — compiles only its own file.
lsp_server_test = executable('lsp_server_test',
  ['lsp_server_test.vala'],
  dependencies: [gio_dep, json_dep],
  vala_args: ['--target-glib=2.74', '--pkg=posix'],
  c_args: test_c_suppress + vala_c_suppress,
)
test('LSP server tests', lsp_server_test,
  env: ['GDIAGRAM_LSP_BIN=' + gdiagram_lsp_exe.full_path()],
  depends: [gdiagram_lsp_exe],
  timeout: 60,
)

# ── Editor UI logic test ──────────────────────────────────────
# Display-free parts of the GTK UI: SourceEdit (properties-panel text replacement,
# palette snippet placement) on a GtkSource.Buffer and OutlineNode collapse keys.
# fatal-warnings: a GTK warning (e.g. set_text inside a user action) fails the test.
review_ui_test = executable('review_ui_test',
  [
    'review_ui_test.vala',
    meson.project_source_root() / 'src/ui/SourceEdit.vala',
    meson.project_source_root() / 'src/ui/OutlineNode.vala',
  ],
  dependencies: core_test_deps + [gtksourceview_dep, gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Editor UI logic tests', review_ui_test,
  env: ['G_DEBUG=fatal-warnings'],
)

# ── Front-end review findings ─────────────────────────────────
review_frontend_test = executable('review_frontend_test',
  ['review_frontend_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Front-end review tests', review_frontend_test)

# ── Review activity fixes ─────────────────────────────────────
review_activity_test = executable('review_activity_test',
  ['review_activity_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Review activity fixes', review_activity_test)

# ── Review regressions: component / use case / state ──────────
review_structural_test = executable('review_structural_test',
  ['review_structural_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Review structural tests', review_structural_test,
  env: ['GDIAGRAM_EXAMPLES_ROOT=' + meson.project_source_root() / 'examples'],
  timeout: 180,
)
# ── RenderUtils review test ───────────────────────────────────
# Shared SVG post-processing and colour/id helpers: circle-plus markers, actor figure
# colours, contrast text on see-through fills, DOT keyword ids.
review_renderutils_test = executable('review_renderutils_test',
  ['review_renderutils_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('RenderUtils review tests', review_renderutils_test, timeout: 60)


# ── Class/object review findings test ─────────────────────────
review_class_test = executable('review_class_test',
  ['review_class_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Class/object review tests', review_class_test)

# ── !include line mapping + border-message detection ──────────
review_include_test = executable('review_include_test',
  ['review_include_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Include review tests', review_include_test)

# ── Sequence layout: horizontal rows, straight lifelines, frames, notes, titles ──
review_sequence_layout_test = executable('review_sequence_layout_test',
  ['review_sequence_layout_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Sequence layout review tests', review_sequence_layout_test,
  env: ['GDIAGRAM_SOURCE_ROOT=' + meson.project_source_root()],
)

# ── Timing diagrams: parser syntax forms and waveform geometry ──
review_timing_test = executable('review_timing_test',
  ['review_timing_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Timing review tests', review_timing_test)

# ── PlantUML gantt: working days, dependencies, calendar geometry ──
review_gantt_test = executable('review_gantt_test',
  ['review_gantt_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Gantt review tests', review_gantt_test)

# ── Review: object / YAML / JSON / nwdiag / ArchiMate / chronology fidelity ──
review_data_diagrams_test = executable('review_data_diagrams_test',
  ['review_data_diagrams_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Data diagram review tests', review_data_diagrams_test)

# ── Lightweight PlantUML types review test ───────────────────
# Export, board/chen/ebnf/ditaa/salt/regex/packetdiag fidelity vs PlantUML.
review_specialized_test = executable('review_specialized_test',
  ['review_specialized_test.vala'],
  dependencies: core_test_deps + [gdiagram_core_dep],
  vala_args: core_test_vargs,
  c_args: core_test_cargs,
)
test('Specialized types review tests', review_specialized_test,
  env: ['GDIAGRAM_SOURCE_ROOT=' + meson.project_source_root(), 'GSETTINGS_BACKEND=memory'],
  timeout: 120,
)
