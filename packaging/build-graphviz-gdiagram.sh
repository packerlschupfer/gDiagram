#!/bin/bash
# build-graphviz-gdiagram.sh - Build graphviz-gdiagram Debian package
#
# Produces a .deb that installs a patched Graphviz to /usr/local,
# coexisting with the system graphviz package. The patch fixes vertical
# text centering in HTML table cells (<TD>).
#
# Prerequisites (Debian/Ubuntu):
#   sudo apt install build-essential cmake dpkg-dev debhelper \
#     libpango1.0-dev libcairo2-dev libgts-dev librsvg2-dev \
#     libgd-dev libexpat1-dev libltdl-dev bison flex
#
# Usage:
#   ./packaging/build-graphviz-gdiagram.sh
#
# Output:
#   ../graphviz-gdiagram_14.1.2-1gdiagram1_<arch>.deb

set -euo pipefail

GRAPHVIZ_VERSION="14.1.2"
PKG_VERSION="${GRAPHVIZ_VERSION}-1gdiagram1"
TARBALL="graphviz-${GRAPHVIZ_VERSION}.tar.gz"
TARBALL_URL="https://gitlab.com/graphviz/graphviz/-/archive/${GRAPHVIZ_VERSION}/${TARBALL}"
SOURCE_DIR="graphviz-${GRAPHVIZ_VERSION}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_FILE="$PROJECT_DIR/patches/graphviz-center-text.patch"
BUILD_DIR="$PROJECT_DIR/build-graphviz-pkg"

if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: Patch file not found: $PATCH_FILE"
    exit 1
fi

echo "=== Building graphviz-gdiagram ${PKG_VERSION} ==="

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download source tarball
if [ ! -f "$TARBALL" ]; then
    echo "Downloading Graphviz ${GRAPHVIZ_VERSION}..."
    wget -q --show-progress "$TARBALL_URL" -O "$TARBALL"
fi

# Extract
echo "Extracting source..."
tar xf "$TARBALL"
cd "$SOURCE_DIR"

# Apply patch
echo "Applying text centering patch..."
patch -p1 < "$PATCH_FILE"

# Replace upstream debian/ with our packaging
echo "Creating debian packaging..."
rm -rf debian
mkdir -p debian/source

# debian/source/format
cat > debian/source/format << 'DEOF'
3.0 (native)
DEOF

# debian/changelog
cat > debian/changelog << DEOF
graphviz-gdiagram (${PKG_VERSION}) unstable; urgency=medium

  * Patched Graphviz ${GRAPHVIZ_VERSION} for gDiagram
  * Fix vertical text centering in HTML table cells

 -- gDiagram Developers <packerlschupfer@github.com>  $(date -R)
DEOF

# debian/control
cat > debian/control << 'DEOF'
Source: graphviz-gdiagram
Section: graphics
Priority: optional
Maintainer: gDiagram Developers <packerlschupfer@github.com>
Build-Depends: debhelper-compat (= 13),
               cmake,
               libpango1.0-dev,
               libcairo2-dev,
               libgts-dev,
               librsvg2-dev,
               libgd-dev,
               libexpat1-dev,
               libltdl-dev,
               bison,
               flex
Standards-Version: 4.6.2
Rules-Requires-Root: no

Package: graphviz-gdiagram
Architecture: any
Depends: ${shlibs:Depends},
         ${misc:Depends}
Conflicts: graphviz-gdiagram-old
Description: Patched Graphviz for gDiagram - installs to /usr/local
 A patched build of Graphviz that fixes vertical text centering in HTML
 table cells (<TD>). Installs to /usr/local to coexist with the system
 graphviz package.
 .
 This package provides /usr/local/bin/dot and the associated libraries
 needed by gDiagram for native diagram rendering.
DEOF

# debian/rules
cat > debian/rules << 'DEOF'
#!/usr/bin/make -f

export DH_VERBOSE = 1

%:
	dh $@ --buildsystem=cmake

override_dh_autoreconf:
	# Skip autoreconf - graphviz uses CMake, not autotools

override_dh_auto_configure:
	dh_auto_configure --buildsystem=cmake -- \
		-DCMAKE_INSTALL_PREFIX=/usr/local \
		-Dwith_gvedit=OFF \
		-Dwith_smyrna=OFF

override_dh_auto_install:
	dh_auto_install --buildsystem=cmake
	# Remove files that conflict with system graphviz or aren't needed
	cd debian/graphviz-gdiagram && \
	rm -rf usr/local/share/man \
		usr/local/share/doc \
		usr/local/share/graphviz/doc \
		usr/local/include

override_dh_shlibdeps:
	dh_shlibdeps -l$(CURDIR)/debian/graphviz-gdiagram/usr/local/lib/x86_64-linux-gnu:$(CURDIR)/debian/graphviz-gdiagram/usr/local/lib/x86_64-linux-gnu/graphviz

override_dh_usrlocal:
	# Allow installing to /usr/local (intentional for coexistence with system graphviz)

override_dh_auto_test:
	# Skip tests during package build
DEOF
chmod +x debian/rules

# debian/copyright
cat > debian/copyright << 'DEOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Graphviz
Upstream-Contact: https://gitlab.com/graphviz/graphviz
Source: https://gitlab.com/graphviz/graphviz

Files: *
Copyright: AT&T Research
License: EPL-1.0
 Eclipse Public License - v 1.0
 .
 THE ACCOMPANYING PROGRAM IS PROVIDED UNDER THE TERMS OF THIS ECLIPSE
 PUBLIC LICENSE ("AGREEMENT"). ANY USE, REPRODUCTION OR DISTRIBUTION OF
 THE PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE OF THIS AGREEMENT.
 .
 For the full license text, see https://www.eclipse.org/legal/epl-v10.html

Files: debian/*
Copyright: 2025 gDiagram Developers
License: EPL-1.0
DEOF

# debian/triggers — update ldconfig after install/remove
cat > debian/triggers << 'DEOF'
activate-noawait ldconfig
DEOF

# debian/postinst
cat > debian/postinst << 'DEOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    ldconfig
fi
#DEBHELPER#
DEOF
chmod +x debian/postinst

# debian/postrm
cat > debian/postrm << 'DEOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    ldconfig
fi
#DEBHELPER#
DEOF
chmod +x debian/postrm

echo ""
echo "=== Building package ==="
dpkg-buildpackage -us -uc -b

# Find the output .deb
DEB_FILE=$(ls "$BUILD_DIR"/graphviz-gdiagram_*.deb 2>/dev/null | head -1)

echo ""
echo "=== Build complete ==="
if [ -n "$DEB_FILE" ]; then
    echo "Package: $DEB_FILE"
    echo ""
    echo "Install with:"
    echo "  sudo dpkg -i $DEB_FILE"
    echo ""
    echo "Verify with:"
    echo "  /usr/local/bin/dot -V"
else
    echo "Warning: .deb file not found in $BUILD_DIR"
    echo "Check build output above for errors."
fi
