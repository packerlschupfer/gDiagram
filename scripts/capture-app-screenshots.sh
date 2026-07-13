#!/usr/bin/env bash
#
# capture-app-screenshots.sh — capture full-window screenshots of the
# gdiagram GTK app with various example files loaded. Uses Xvfb so no
# real display is required.
#
# Requirements: xvfb-run, ImageMagick (`import`). Both installed by
# the Debian `xvfb` and `imagemagick` packages.
#
# Usage:
#   ./scripts/capture-app-screenshots.sh
#
# Output: docs/images/app/*.png
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

GDIAGRAM="${GDIAGRAM:-$ROOT/build/src/gdiagram}"
if [[ ! -x "$GDIAGRAM" ]]; then
    echo "error: $GDIAGRAM not found — run 'meson compile -C build' first" >&2
    exit 1
fi

command -v xvfb-run         >/dev/null || { echo "error: xvfb-run not installed (apt install xvfb)" >&2; exit 1; }
command -v import           >/dev/null || { echo "error: ImageMagick 'import' not installed (apt install imagemagick)" >&2; exit 1; }
command -v dbus-run-session >/dev/null || { echo "error: dbus-run-session not installed (apt install dbus)" >&2; exit 1; }

OUT_DIR="$ROOT/docs/images/app"
mkdir -p "$OUT_DIR"

# Compile schemas so the app starts without GSETTINGS errors.
export GSETTINGS_SCHEMA_DIR="$ROOT/data"
if [[ -f "$ROOT/data/org.gnome.gDiagram.gschema.xml" ]]; then
    glib-compile-schemas "$ROOT/data" 2>/dev/null || true
fi

# Throwaway settings store: the keyfile backend keeps the captures out of the
# user's dconf, and pre-seeding the window size makes the app open at exactly
# the Xvfb screen size (there is no window manager to maximize it).
CFG_DIR="$(mktemp -d)"
trap 'rm -rf "$CFG_DIR"' EXIT
mkdir -p "$CFG_DIR/glib-2.0/settings"
cat > "$CFG_DIR/glib-2.0/settings/keyfile" <<'EOF'
[org/gnome/gDiagram]
window-width=1600
window-height=968
window-maximized=false
EOF
export XDG_CONFIG_HOME="$CFG_DIR"
export GSETTINGS_BACKEND=keyfile

# Files to capture. Format: "name:source-file"
SHOTS=(
    "main-class:examples/plantuml/class/24_abstract_interfaces_enums.puml"
    "main-activity:examples/plantuml/activity/06_if_then_else.puml"
    "main-sequence:examples/plantuml/sequence/02_participant_types.puml"
    "main-c4:examples/plantuml/c4/01_native_container.puml"
    "main-mermaid-flowchart:examples/mermaid/flowchart/flowchart.mmd"
    "main-mermaid-gantt:examples/mermaid/gantt/gantt.mmd"
)

# Resolution of the virtual display. Xvfb has no window manager, so the app
# window is whatever size it asks for and a larger screen would leave a black
# border around it; the app is told to open at exactly the screen size below
# via its window-width/window-height GSettings keys, which also keeps these
# captures at the same 1600x968 as the committed ones.
RES="1600x968x24"
#
# The committed docs/images/app/*.png were taken at 1600x968 in a headless
# GNOME session (`wlcontrol vd start --name <name> 1600x1000`, window maximized
# under the 32px top bar), with the sidebar, palette and properties panel opened
# by hand, the editor/preview divider moved to ~760px and zoom-to-fit (Ctrl+9);
# this script is the quick, unattended fallback and does not set those panels.

capture_one() {
    local name="$1" src="$2"
    local out="$OUT_DIR/$name.png"

    if [[ ! -f "$src" ]]; then
        echo "  SKIP  $name — source missing ($src)"
        return 0
    fi

    # Spawn Xvfb on its own display number, run gdiagram inside it,
    # wait for the preview pane to finish rendering, screenshot the
    # root window (Xvfb has exactly one client so this == our window),
    # then kill gdiagram and tear down Xvfb.
    (
        export DISPLAY=":99"
        Xvfb "$DISPLAY" -screen 0 "$RES" -nolisten tcp >/dev/null 2>&1 &
        local xvfb_pid=$!
        # Wait for Xvfb to be ready.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then break; fi
            sleep 0.1
        done

        # Private session bus: gdiagram is a single-instance GApplication, so
        # without this the command is handed to whatever gdiagram is already
        # running on the user's desktop — it opens a tab there and nothing ever
        # appears on our Xvfb display.
        dbus-run-session -- "$GDIAGRAM" "$src" >/dev/null 2>&1 &
        local app_pid=$!

        # Render debouncer + layout pass. 2.5s is comfortable on this box.
        sleep 2.5

        import -display "$DISPLAY" -window root "$out" 2>/dev/null || true

        kill "$app_pid"  2>/dev/null || true
        wait "$app_pid"  2>/dev/null || true
        kill "$xvfb_pid" 2>/dev/null || true
        wait "$xvfb_pid" 2>/dev/null || true
    )

    if [[ -s "$out" ]]; then
        echo "  OK    $name ($(stat -c '%s' "$out") bytes)"
    else
        echo "  FAIL  $name — empty or missing"
        return 1
    fi
}

pass=0
fail=0
for pair in "${SHOTS[@]}"; do
    name="${pair%%:*}"
    src="${pair#*:}"
    if capture_one "$name" "$src"; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
    fi
done

echo
echo "Summary: $pass passed, $fail failed"
echo "Output:  $OUT_DIR"
[[ $fail -eq 0 ]]
