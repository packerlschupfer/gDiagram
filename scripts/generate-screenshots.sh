#!/usr/bin/env bash
#
# generate-screenshots.sh — render a curated set of example diagrams
# to PNG for documentation/README use. Uses gdiagram's built-in
# headless export mode (--export), no display required.
#
# Usage:
#   ./scripts/generate-screenshots.sh              # uses in-tree build
#   GDIAGRAM=/usr/bin/gdiagram ./scripts/generate-screenshots.sh
#
# Output: docs/images/gallery/*.png   (one PNG per diagram type)
#         docs/images/*.svg           (small inline SVG samples)
#         docs/images/architecture/*.png (the project's own design diagrams)
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

GDIAGRAM="${GDIAGRAM:-$ROOT/build/src/gdiagram}"
if [[ ! -x "$GDIAGRAM" ]]; then
    echo "error: $GDIAGRAM not found — run 'meson compile -C build' first" >&2
    exit 1
fi

# gdiagram is a single-instance GApplication: invoked from a desktop session it
# registers on that session bus, and if the user already has gdiagram running,
# the running GUI process handles the command line — the export happens inside
# their window (and opens tabs there) instead of headlessly here. Give every
# invocation its own private bus and no display so it always runs standalone.
ISOLATE=(env -u WAYLAND_DISPLAY -u DISPLAY dbus-run-session --)
command -v dbus-run-session >/dev/null || {
    echo "error: dbus-run-session not found (apt install dbus)" >&2
    exit 1
}

OUT_DIR="$ROOT/docs/images/gallery"
mkdir -p "$OUT_DIR"

# Curated set: one good representative per major diagram type, covering
# the full range of PlantUML + Mermaid formats. The first column is the
# output filename (without extension), the second is the source file.
SAMPLES=(
    # PlantUML
    "plantuml-class:examples/plantuml/class/24_abstract_interfaces_enums.puml"
    "plantuml-sequence:examples/plantuml/sequence/02_participant_types.puml"
    "plantuml-activity:examples/plantuml/activity/06_if_then_else.puml"
    "plantuml-state:examples/plantuml/state/03_composite_states.puml"
    "plantuml-usecase:examples/plantuml/usecase/08_packages.puml"
    "plantuml-component:examples/plantuml/component/05_database_and_files.puml"
    "plantuml-deployment:examples/plantuml/deployment/15_nesting_example.puml"
    "plantuml-gantt:examples/plantuml/gantt/sections.puml"
    "plantuml-c4:examples/plantuml/c4/01_native_container.puml"
    "plantuml-archimate:examples/plantuml/archimate/basic.puml"
    # Mermaid
    "mermaid-flowchart:examples/mermaid/flowchart/flowchart.mmd"
    "mermaid-sequence:examples/mermaid/sequence/sequence.mmd"
    "mermaid-zenuml:examples/mermaid/zenuml/auth.mmd"
    "mermaid-class:examples/mermaid/class/class.mmd"
    "mermaid-state:examples/mermaid/state/state.mmd"
    # keys.mmd (not er.mmd): shows PK/FK/UK attribute keys next to the
    # crow's-foot cardinalities, which er.mmd's three plain boxes do not.
    "mermaid-er:examples/mermaid/er/keys.mmd"
    "mermaid-requirement:examples/mermaid/requirement/basic.mmd"
    "mermaid-block:examples/mermaid/block/basic.mmd"
    "mermaid-gantt:examples/mermaid/gantt/gantt.mmd"
    "mermaid-pie:examples/mermaid/pie/pie.mmd"
    "mermaid-xychart:examples/mermaid/xychart/sales.mmd"
    "mermaid-radar:examples/mermaid/radar/skills.mmd"
    "mermaid-treemap:examples/mermaid/treemap/languages.mmd"
    "mermaid-gitgraph:examples/mermaid/gitgraph/basic.mmd"
    # roadmap-shapes.mmd (not basic.mmd): same layout engine, but with the
    # per-node shapes and levels that make a readable thumbnail.
    "mermaid-mindmap:examples/mermaid/mindmap/roadmap-shapes.mmd"
    "mermaid-timeline:examples/mermaid/timeline/multi-event.mmd"
    "mermaid-quadrant:examples/mermaid/quadrant/tech_decisions.mmd"
    "mermaid-kanban:examples/mermaid/kanban/project.mmd"
    # energy-flow.mmd (not energy.mmd): the full UK energy data set has ~50
    # nodes whose labels overlap into an unreadable block at gallery size.
    "mermaid-sankey:examples/mermaid/sankey/energy-flow.mmd"
    "mermaid-packet:examples/mermaid/packet/udp.mmd"
    "mermaid-c4:examples/mermaid/c4/container.mmd"
    "mermaid-architecture:examples/mermaid/architecture/cloud.mmd"
)

# docs/images/*.svg — the small inline SVG samples, same pipeline, SVG output.
SVG_SAMPLES=(
    "example_sequence:examples/plantuml/sequence/01_basic_messages.puml"
    "example_class:examples/plantuml/class/24_abstract_interfaces_enums.puml"
    "example_activity:examples/plantuml/activity/06_if_then_else.puml"
    "example_state:examples/plantuml/state/03_composite_states.puml"
)

# docs/images/architecture/*.png — rendered from the project's own design
# diagrams in docs/architecture/.
ARCH_SAMPLES=(
    "01_architecture_overview:docs/architecture/01_architecture_overview.puml"
    "02_rendering_pipeline:docs/architecture/02_rendering_pipeline.puml"
    "03_class_hierarchy:docs/architecture/03_class_hierarchy.puml"
    "04_diagram_types:docs/architecture/04_diagram_types.puml"
    "05_ui_interaction:docs/architecture/05_ui_interaction.puml"
)

pass=0
skip=0
fail=0

# GSettings schema lives in data/ in the tree; compiled into the .deb on install.
export GSETTINGS_SCHEMA_DIR="$ROOT/data"
# In-memory settings: the renders use the default LIGHT palette regardless of the
# desktop's dark-mode or colour-preset settings, so the gallery stays consistent.
export GSETTINGS_BACKEND=memory

# Compile the schema once so GSettings can find it (idempotent).
if [[ -f "$ROOT/data/org.gnome.gDiagram.gschema.xml" ]]; then
    glib-compile-schemas "$ROOT/data" 2>/dev/null || true
fi

# render <out-dir> <format> <"name:source"> ...
render_set() {
    local dir="$1" fmt="$2"
    shift 2
    mkdir -p "$dir"
    local pair name src out
    for pair in "$@"; do
        name="${pair%%:*}"
        src="${pair#*:}"
        if [[ ! -f "$src" ]]; then
            echo "  SKIP  $name — source missing ($src)"
            skip=$((skip+1))
            continue
        fi
        out="$dir/$name.$fmt"
        if "${ISOLATE[@]}" "$GDIAGRAM" "$src" --export "$out" --format "$fmt" >/dev/null 2>&1 \
           && [[ -s "$out" ]]; then
            echo "  OK    $name ($(stat -c '%s' "$out") bytes)"
            pass=$((pass+1))
        else
            echo "  FAIL  $name — no usable output"
            fail=$((fail+1))
        fi
    done
}

echo "Gallery (docs/images/gallery):"
render_set "$OUT_DIR" png "${SAMPLES[@]}"
echo
echo "Inline SVG samples (docs/images):"
render_set "$ROOT/docs/images" svg "${SVG_SAMPLES[@]}"
echo
echo "Project design diagrams (docs/images/architecture):"
render_set "$ROOT/docs/images/architecture" png "${ARCH_SAMPLES[@]}"

echo
echo "Summary: $pass passed, $skip skipped, $fail failed"
echo "Output:  $OUT_DIR"
[[ $fail -eq 0 ]]
