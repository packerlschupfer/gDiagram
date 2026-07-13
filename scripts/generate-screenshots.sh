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
# Output: docs/images/gallery/*.png
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

GDIAGRAM="${GDIAGRAM:-$ROOT/build/src/gdiagram}"
if [[ ! -x "$GDIAGRAM" ]]; then
    echo "error: $GDIAGRAM not found — run 'meson compile -C build' first" >&2
    exit 1
fi

OUT_DIR="$ROOT/docs/images/gallery"
mkdir -p "$OUT_DIR"

# Curated set: one good representative per major diagram type, covering
# the full range of PlantUML + Mermaid formats. The first column is the
# output filename (without extension), the second is the source file.
SAMPLES=(
    # PlantUML
    "plantuml-class:examples/plantuml/class/01_element_types.puml"
    "plantuml-sequence:examples/plantuml/sequence/26_grouping_alt_loop.puml"
    "plantuml-activity:examples/plantuml/activity/06_if_then_else.puml"
    "plantuml-state:examples/plantuml/state/03_composite_states.puml"
    "plantuml-usecase:examples/plantuml/usecase/01_basic_usecases.puml"
    "plantuml-component:examples/plantuml/component/01_basic_components.puml"
    "plantuml-deployment:examples/plantuml/deployment/15_nesting_example.puml"
    "plantuml-gantt:examples/plantuml/gantt/sections.puml"
    "plantuml-c4:examples/plantuml/c4/01_native_container.puml"
    # Mermaid
    "mermaid-flowchart:examples/mermaid/flowchart/flowchart.mmd"
    "mermaid-sequence:examples/mermaid/sequence/sequence.mmd"
    "mermaid-class:examples/mermaid/class/class.mmd"
    "mermaid-state:examples/mermaid/state/state.mmd"
    "mermaid-er:examples/mermaid/er/er.mmd"
    "mermaid-gantt:examples/mermaid/gantt/gantt.mmd"
    "mermaid-pie:examples/mermaid/pie/pie.mmd"
    "mermaid-gitgraph:examples/mermaid/gitgraph/branching.mmd"
    "mermaid-mindmap:examples/mermaid/mindmap/basic.mmd"
    "mermaid-timeline:examples/mermaid/timeline/sections.mmd"
    "mermaid-quadrant:examples/mermaid/quadrant/tech_decisions.mmd"
    "mermaid-kanban:examples/mermaid/kanban/basic.mmd"
    "mermaid-sankey:examples/mermaid/sankey/energy.mmd"
    "mermaid-c4:examples/mermaid/c4/container.mmd"
    "mermaid-architecture:examples/mermaid/architecture/cloud.mmd"
)

pass=0
skip=0
fail=0

# GSettings schema lives in data/ in the tree; compiled into the .deb on install.
export GSETTINGS_SCHEMA_DIR="$ROOT/data"

# Compile the schema once so GSettings can find it (idempotent).
if [[ -f "$ROOT/data/org.gnome.gDiagram.gschema.xml" ]]; then
    glib-compile-schemas "$ROOT/data" 2>/dev/null || true
fi

for pair in "${SAMPLES[@]}"; do
    name="${pair%%:*}"
    src="${pair#*:}"
    if [[ ! -f "$src" ]]; then
        echo "  SKIP  $name — source missing ($src)"
        skip=$((skip+1))
        continue
    fi
    out="$OUT_DIR/$name.png"
    if "$GDIAGRAM" --export "$out" --format png --scale "$src" >/dev/null 2>&1; then
        if [[ -s "$out" ]]; then
            size=$(stat -c '%s' "$out")
            echo "  OK    $name (${size} bytes)"
            pass=$((pass+1))
        else
            echo "  FAIL  $name — empty output"
            fail=$((fail+1))
        fi
    else
        echo "  FAIL  $name — exporter returned non-zero"
        fail=$((fail+1))
    fi
done

echo
echo "Summary: $pass passed, $skip skipped, $fail failed"
echo "Output:  $OUT_DIR"
[[ $fail -eq 0 ]]
