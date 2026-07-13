# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

gDiagram (formerly gPlantUML) is a native Linux GTK4/libadwaita diagram viewer and editor supporting PlantUML and Mermaid syntax. It renders diagrams natively using Graphviz (no Java required) with real-time preview.

**Language:** Vala (compiles to C)
**Build system:** Meson + Ninja
**UI:** GTK4 + libadwaita + GtkSourceView
**Rendering:** Graphviz (libgvc) + Cairo + librsvg

## Build Commands

```bash
# Initial setup (only needed once)
meson setup build --prefix=/usr

# Compile (primary development command)
meson compile -C build

# Run without installing
./build/src/gdiagram

# Build Debian package
dpkg-buildpackage -us -uc -b
```

Tests live in `tests/` and are wired into the build via `subdir('tests')`. Run them with `meson test -C build`. There are 34 suites covering lexers, parsers, type detection, renderers (snapshot tests), the preprocessor, utilities, template/example health, the element palette catalog, the element inspector (properties panel edits), display-free UI logic (`SourceEdit`, `OutlineNode`), and the LSP server (protocol unit tests + a stdio integration test that spawns `gdiagram-lsp`). The `review_*_test.vala` suites hold regression tests from the September 2026 code review, one per area (activity, structural, front end, class/object, RenderUtils, UI, includes, sequence layout, specialized types, timing, gantt, data diagrams).

## Architecture

All source lives under `src/` within the `GDiagram` namespace. The pipeline is: **Source text -> Parser -> AST -> Renderer -> Graphviz DOT -> SVG/PNG/PDF**.

### DiagramEngine (`src/core/DiagramEngine.vala`) — the central entry point

`DiagramEngine` is the only entry point to parsers and renderers (25 PlantUML types, with WBS sharing the mind map parser, + 23 Mermaid types; deployment-style files — node, artifact, cloud, `device` — are component diagrams) and every consumer goes through it. It holds most instances; the lightweight Dot, Salt, Chen, EBNF, Regex, Tree, Board, Ditaa and Ancestry parsers/renderers are created per call inside it, and the Mermaid C4, Architecture, ZenUML, Radar and Treemap renderers are reached through the `GraphvizRenderer` facade it owns — the GTK UI (`DocumentView`), the LSP server (`src/lsp/`), and the headless CLI export (`Application.vala`). Do not instantiate parsers/renderers elsewhere. Its API:

- `detect_format(source, doc_filename)` / `detect_plantuml_type(source)` / `detect_mermaid_type(source)` — format/type detection (extension first, then content keywords)
- `preprocess(source, base_path)` — PlantUML preprocessor (`!include`, macros)
- `parse(source, doc_filename)` → `ParseResult` (format, type, AST, errors) — parse-only, no Graphviz work; this is what the LSP uses per keystroke
- `render(type, format, source)` → `RenderResult` (status, Cairo surface, AST, errors, fail message) — used by the GUI's single generic render path
- `generate_dot(source, doc_filename, base_path)` — raw DOT output (CLI `-f dot`)
- `export_to_png/svg/pdf(source, doc_filename, base_path, filename)` — file export
- `last_regions` — click-to-source regions from the most recent render

### Parser Layer (`src/core/parser/`)

Split into `plantuml/` and `mermaid/` subdirectories.

- **PlantUML:** `Lexer.vala` tokenizes source, `TokenStream.vala` provides stream access, then diagram-specific parsers (e.g., `ClassDiagramParser.vala`, `StateDiagramParser.vala`) produce AST objects.
- **ActivityDiagramParser** uses an orchestrator pattern — it delegates to 7 specialized parsers in `activity/` (actions, control flow, structure, metadata, edges, text formatting, utils).
- **Mermaid:** Separate `MermaidLexer.vala`/`MermaidToken.vala` and per-diagram parsers (Flowchart, Sequence, State, Class, ER, Gantt, Pie, UserJourney).
- **Important naming:** The PlantUML sequence parser class is `GDiagram.Parser` (in `SequenceDiagramParser.vala`), not `SequenceDiagramParser`. Its `parse()` method takes a `string source` and handles lexing internally.

### AST Layer (`src/core/ast/`)

One file per diagram type (e.g., `ClassDiagram.vala`, `ActivityDiagram.vala`). `DiagramNode.vala` contains shared base types (Participant, Message, etc.). `MermaidDiagram.vala` covers all Mermaid diagram ASTs. `Theme.vala` handles skinparam/styling.

### Renderer Layer (`src/core/renderer/`)

- **`GraphvizRenderer.vala`** — Facade that delegates to per-diagram-type renderers (PlantUML and 13 Mermaid ones). PlantUML renderers are organized under `plantuml/sequence/`, `plantuml/structural/`, `plantuml/behavioral/`, `plantuml/specialized/`. Mermaid renderers are under `mermaid/`.
- **Renderers that don't use Graphviz layout:** the PlantUML timing (`TimingDiagramRenderer`) and gantt (`GanttDiagramRenderer`, dates in `GanttScheduler.vala`) renderers write SVG directly, porting PlantUML's own layout; their `generate_dot()` returns a small valid summary graph so `-f dot` still works. EBNF and regex railroads use fixed positions through `PinnedDotWriter` (in `EbnfDiagramRenderer.vala`). The class renderer uses HTML-table labels (`shape=plain`) for underline/italics and spot circles (`round_spots()` rewrites the ● glyph in the SVG).
- **Stdlib includes:** `!include <C4/...>` resolves to the bundled C4-PlantUML v2.13.0 in `data/stdlib/C4/` (MIT, LICENSE included; installed to `/usr/share/gdiagram/stdlib`, overridable with `$GDIAGRAM_STDLIB_DIR`). The headless CLI exits 1 when an `!include` cannot be resolved (the partial export is still written), matching PlantUML's failure.
- **Sequence diagrams are laid out by the renderer itself**, not by Graphviz ranks: `SequenceDiagramRenderer` sizes text with a throwaway Graphviz run, computes participant columns (gaps widen to the widest label/note) and one row per message/note/divider, and emits fixed positions (`layout=nop2`, set in the DOT). Graphviz only draws; lifelines are straight vertical edges and messages horizontal.
- **`RenderUtils.vala`** — Shared utilities: string escaping, SVG parsing, `ElementRegion` for click-to-source mapping.
- Each renderer exposes: `generate_dot()`, `render_to_svg()`, `render_to_surface()`, `export_to_png/svg/pdf()`.
- All renderers parse DOT with `RenderUtils.read_dot()` (declares `fontname="Sans"` so graph/cluster titles don't fall back to Times) and render with `RenderUtils.render_data()`, which wraps `GraphvizCompat.render_data()` (not `context.render_data()`, see "Patched GraphViz") and applies `fill_svg_background()`: a background rect over Graphviz's rounded canvas, and contrasting colours for default-black graph/cluster titles. Renderers that run the `dot` binary pass `-Gfontname=Sans` and call `fill_svg_background()` on the SVG.

### UI Layer (`src/ui/`)

- `MainWindow.vala` — app window: header bar (sidebar toggle, "+ ▾" new-diagram split button, `Adw.WindowTitle` with the file path, undo/redo, properties toggle), tabs in a second top bar, actions, menus, and an `Adw.Breakpoint` that folds the sidebars on narrow windows (`DocumentView.set_narrow`). Delegates to `TemplateGallery.vala` (template picker dialog + built-in templates, `template_chosen` signal) and `RecentFilesManager.vala` (recent-files persistence + menu, `open_requested` signal).
- `DocumentView.vala` — source editor + render orchestration. Holds ONE `DiagramEngine` and one generic render path (`render_preview` → `apply_render_result` → `update_ui_after_render`); no per-type render methods. Layout: a left `Adw.OverlaySplitView` sidebar (Outline / Palette pages, outline filter, stats footer), the editor | preview `Gtk.Paned`, and a right `Adw.OverlaySplitView` for properties. Delegates to `GitGutterController.vala` (blame gutter, diff marks, git-dirty check), `OutlineController.vala` (tree outline from the engine-supplied AST: expandable containers, collapse kept across re-renders, `set_filter()`, `navigate_to_element` signal), `ElementPalette.vala` (grouped snippet buttons from `PaletteCatalog`, inserted via `insert_snippet()`) and `PropertiesPanel.vala` (label/stereotype/colour/rename of the clicked element via `ElementInspector`, applied with `replace_source_text()` as one undo step). The text logic behind those two lives in `SourceEdit.vala` (minimal-diff replacement inside one user action — `set_text` inside a user action logs GTK warnings; snippet placement inside the diagram, a first swimlane below `@start`), and the outline's node/collapse-key model in `OutlineNode.vala`; both are display-free and unit-tested.
- Closures connected to a view's own child widgets must not capture `this` or locals that hold it (use method handlers): a captured cycle kept every closed document tab alive.
- `PreviewPane.vala` — live preview with zoom/pan/minimap and click-to-source (`element_clicked`). The pan `GestureDrag` sits on the ScrolledWindow, not the drawing area: scrolling moves the drawing area under the pointer, so offsets measured there feed back and jitter.
- Toolbars inside a `Gtk.Paned` child (the search/replace bar, the zoom bar) are wrapped in a `ScrolledWindow` with `hscrollbar_policy = EXTERNAL`: a child below its minimum width is shifted (start child) or overflows (end child), which clipped the editor gutter and pushed the preview off-screen.
- Dialogs: `ExportDialog`, `PreferencesDialog`, `AIAssistantDialog`, `GitHistoryDialog`, `DiagramCompareDialog`, `GitRepoView` (git graph tab).

### LSP Server (`src/lsp/`)

`gdiagram-lsp` — JSON-RPC over stdio (diagnostics, completion, hover, document symbols, custom render/export commands), used by the VS Code extension in `vscode-extension/`. `LspServer` owns one shared `DiagramEngine`; `LspDocumentState` calls `engine.parse()` — never instantiate parsers there.

### Editor support (`src/core/`, GTK-free and unit-tested)

- `PaletteCatalog.vala` — insertable snippets per diagram type (PlantUML + Mermaid groups) for the element palette; icons are `uml-*-symbolic` SVGs in `data/icons/scalable/actions/`, bundled via the gresource.
- `ElementInspector.vala` — reads the clicked element from the AST (kind, id, label, alias, stereotype, colour, note) and returns rewritten source for label / stereotype / colour / rename edits. The source text stays the single source of truth.

### Services (`src/services/`)

`AIService.vala` — Claude API via libsoup. API key: `ANTHROPIC_API_KEY` env var first, then GNOME Keyring (libsecret, schema `org.gnome.gDiagram`), legacy plaintext files are migrated into the keyring and deleted.

### Diagram Type Detection

`DiagramEngine` handles auto-detection of diagram format (PlantUML vs Mermaid) and specific diagram type (sequence, class, activity, etc.) from file extensions (`.puml`, `.mmd`) and content keywords. `Document.vala` handles file I/O and monitoring only.

## Adding New Source Files

The shared core is compiled ONCE into `static_library('gdiagram-core', ...)`; the `gdiagram` GUI, `gdiagram-lsp`, and all test executables link against it instead of recompiling sources.

- **Vala (core: parsers, ASTs, renderers, engine, services):** add to the `core_sources` list in `src/meson.build`.
- **Vala (GTK UI):** add to `ui_sources`. **Vala (LSP):** add to `lsp_sources`.
- **C:** Add `.c` files to the `c_sources` list in `src/meson.build` (compiled into the core library). Headers go in `src/util/` (included via `c_args`).
- **VAPI:** Add custom Vala bindings for C code in `vapi/`. Register with `--pkg=name` in `vala_args` in `src/meson.build`.
- **Tests:** a new test executable compiles only its own `.vala` and uses `dependencies: core_test_deps + [gdiagram_core_dep]` — follow the existing pattern in `tests/meson.build`. New core dependencies must be added to BOTH the library's dependency list and `core_test_deps`.

## Adding a New Diagram Type

**For PlantUML:**
1. Create parser in `src/core/parser/plantuml/`
2. Create AST model in `src/core/ast/`
3. Create renderer in `src/core/renderer/plantuml/<subdirectory>/`
4. Add delegation methods to `GraphvizRenderer.vala` facade
5. In `src/core/DiagramEngine.vala`: add detection in `detect_plantuml_type()`, and cases to the parse/render/export dispatch switches
6. Optional UI: add an outline populator case in `src/ui/OutlineController.vala`
7. Add all new files to `src/meson.build`

**For Mermaid (complete checklist):**
1. Add `MERMAID_<TYPE>` to `DiagramType` enum in `src/core/ast/DiagramNode.vala`
2. Add to `MermaidDiagramType` enum in `src/core/ast/MermaidDiagram.vala` (that file holds only the shared enum)
3. Create the AST classes in a new `src/core/ast/mermaid/Mermaid<Type>.vala`
4. Create `src/core/parser/mermaid/Mermaid<Type>Parser.vala`
5. Create `src/core/renderer/mermaid/Mermaid<Type>Renderer.vala` — must implement `export_to_png/svg/pdf()`
6. Register all new files in `src/meson.build`
7. In `src/core/DiagramEngine.vala`: add `mermaid_<type>_parser`/`_renderer` fields + construct-time init; add detection in `detect_mermaid_type()`; add cases to the parse, render, and export dispatch switches
8. Optional UI: outline populator case in `src/ui/OutlineController.vala`; stats/lint/validate case in `DocumentView.update_ui_after_render()`

Do NOT add per-type code to `DocumentView` render/export paths — they are generic and driven entirely by `DiagramEngine`.

## Critical Conventions

### Color Handling

Graphviz accepts `#` prefix only for hex codes, NOT named colors. Parsers accept both `#red` and `#FF0000`, but renderers must normalize:
- `#FF0000` → keep as `#FF0000` (hex)
- `#red` → strip to `red` (named color)

Failing to normalize causes Graphviz warnings/errors.

### Multi-line Labels in Graphviz

- Simple line breaks: use `\n` in label strings
- Structured content (separate boxes): use HTML TABLE with `BORDER="0"`, `CELLBORDER="1"`, and set `shape=plaintext` to avoid double borders
- Text inside HTML `<TD>` cells must be escaped with `Markup.escape_text()` (GLib), **not** `RenderUtils.escape_label()` (which is for DOT string literals, not HTML context)

### Participant/Node Lookup

Keep `name` as a simple identifier for matching/lookup. Use `display_label` for rendering. Mixing these up breaks cross-references.

### Token Consumption

Parsers must consume all tokens within brackets/blocks. Unconsumed tokens cause parsing failures for subsequent elements.

### Keyboard Shortcuts

Register accelerators in `Application`'s `construct` block. A Vala `construct {}` runs before ordinary properties passed to `Object(...)` are set, so `this.application` is still null inside `MainWindow`'s construct and accels registered there never took effect.

### libadwaita / GTK API level

CI builds on Ubuntu 24.04 (libadwaita 1.5); `meson.build` requires `libadwaita-1 >= 1.4`. Don't use newer widgets (e.g. `Adw.WrapBox`, 1.7) even if the local system has them.

### Compiler Warnings

valac's generated C produces thousands of warnings for any code. `src/meson.build` defines `vala_c_suppress` (unused-*, discarded-qualifiers, cast-function-type, alloc-size) and appends it to `shared_c_args`; a test executable that doesn't use `shared_c_args` needs `c_args: test_c_suppress + vala_c_suppress`. `-Wincompatible-pointer-types` stays on because it also covers the hand-written `graphviz_compat.c`. A clean build should show only the 2 known Vala warnings and the known pointer-type mismatches from the bindings — new Vala warnings (unused methods/variables, unreachable catch) are worth fixing.

## Patched GraphViz

gDiagram requires a patched build of GraphViz installed to `/usr/local`. The patch fixes vertical text centering in HTML table cells (`<TD>`), which GraphViz renders slightly too high by default.

**What's patched:** Two files in `lib/common/`:
- **`htmltable.c` `size_html_txt()`** — changes `lfsize[0] = mxfsize` (raw font size) to `lfsize[0] = maxlayout + maxoffset`, where `maxlayout` is the maximum `yoffset_layout` (pango baseline distance from top of logical rectangle) and `maxoffset` is the maximum `yoffset_centerline` (small above-baseline renderer correction). This places the rendered baseline using actual font metrics rather than approximating with raw font size, centering the pango logical rectangle exactly in the cell. Reduces centering error from ~3.7pt to ~0.1pt for 14pt Times,serif.
- **`textspan.c` `estimate_textspan_size()`** — sets `yoffset_layout = fontsize` (was `0.0`) so the fallback path (non-pango) also benefits from the new formula rather than collapsing to `lfsize[0] ≈ 0`.

**Why:** gDiagram uses HTML TABLE labels with `cellpadding` for activity diagram nodes. Without the patch, text appears shifted above the visual center of cells.

**Rendering paths:**
- **ActivityDiagramRenderer** calls `/usr/local/bin/dot` (the patched binary) directly for export, ensuring the text centering fix is applied.
- **All other renderers** use the patched `libgvc.so` via the system-installed library (pkg-config resolves to `/usr/local`).

**ABI compatibility:** The patched GraphViz changed `gvRenderData`'s length parameter from `unsigned int *` to `size_t *`. The Vala VAPI still declares `unsigned int`, causing stack corruption on 64-bit. A C wrapper (`src/util/graphviz_compat.c`) bridges this mismatch — all renderers must use `RenderUtils.render_data()` (which calls `GraphvizCompat.render_data()`) instead of `context.render_data()`.

**Files:**
- `patches/graphviz-center-text.patch` — the patch itself
- `scripts/build-patched-graphviz.sh` — clones, patches, builds, and installs GraphViz
- `src/util/graphviz_compat.c` / `.h` — ABI compatibility wrapper for `gvRenderData`
- `vapi/graphviz_compat.vapi` — Vala binding for the wrapper

**Quick rebuild:** `cd ~/git/graphviz && make -C build -j$(nproc) && sudo make -C build install`

## Git Workflow

- Work on `main` branch
- Commit message prefixes: `Fix:`, `Refactor:`, `Add:`
- Force push is allowed (personal project)
