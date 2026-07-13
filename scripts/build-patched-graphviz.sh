#!/bin/bash
# build-patched-graphviz.sh - Build GraphViz with text centering fix
#
# gDiagram uses HTML TABLE labels for node rendering. Upstream GraphViz
# has a vertical text centering bug in HTML table cells where text appears
# shifted upward. This script builds a patched GraphViz and installs it
# to /usr/local so gDiagram can use /usr/local/bin/dot for rendering.
#
# Prerequisites (Debian/Ubuntu):
#   sudo apt install build-essential cmake libpango1.0-dev libcairo2-dev \
#     libgts-dev libgtk-3-dev librsvg2-dev libgd-dev tcl-dev \
#     libexpat1-dev libltdl-dev bison flex
#
# Usage:
#   ./scripts/build-patched-graphviz.sh          # Clone + build + install
#   ./scripts/build-patched-graphviz.sh --local   # Use existing ~/git/graphviz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/../patches/graphviz-center-text.patch"
GRAPHVIZ_DIR="$HOME/git/graphviz"
# Fork of graphviz 14.1.2 with gDiagram text centering patch pre-applied.
# Branch: gdiagram-patch  Commit: 8bcacbc100a23ee25e1e649ef2fafc8deee1a2c7
GRAPHVIZ_REPO="https://github.com/packerlschupfer/graphviz.git"
GRAPHVIZ_BRANCH="gdiagram-patch"

# Clone or use existing
if [ "${1:-}" = "--local" ]; then
    if [ ! -d "$GRAPHVIZ_DIR" ]; then
        echo "Error: $GRAPHVIZ_DIR not found. Run without --local to clone."
        exit 1
    fi
    echo "Using existing GraphViz source: $GRAPHVIZ_DIR"
else
    if [ ! -d "$GRAPHVIZ_DIR" ]; then
        echo "Cloning patched GraphViz fork..."
        mkdir -p "$(dirname "$GRAPHVIZ_DIR")"
        git clone --branch "$GRAPHVIZ_BRANCH" "$GRAPHVIZ_REPO" "$GRAPHVIZ_DIR"
    else
        echo "GraphViz source exists: $GRAPHVIZ_DIR"
        echo "Pulling latest..."
        cd "$GRAPHVIZ_DIR"
        git pull
    fi
fi

cd "$GRAPHVIZ_DIR"
echo "Patch already applied in fork — no git apply needed."

# Configure if needed
if [ ! -d build ]; then
    echo "Configuring build..."
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local
fi

# Build
echo "Building GraphViz..."
make -C build -j"$(nproc)"

# Install
echo "Installing to /usr/local (requires sudo)..."
sudo make -C build install

echo ""
echo "Done! Patched GraphViz installed to /usr/local"
echo "Verify: /usr/local/bin/dot -V"
/usr/local/bin/dot -V
