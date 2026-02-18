#!/bin/bash
## QA3D Linux Packaging Script
## Creates a standalone compiled application bundle
##
## Usage: bash build/package.sh
##
## Output: dist/QA3D-v{VERSION}-linux-x86_64.tar.gz

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Version
if [ -f "$PROJECT_DIR/VERSION" ]; then
    VERSION=$(cat "$PROJECT_DIR/VERSION" | tr -d '[:space:]')
else
    VERSION="0.1.0"
fi

ARCH=$(uname -m)
BUNDLE_NAME="QA3D-v${VERSION}-linux-${ARCH}"
DIST_DIR="$PROJECT_DIR/dist"
COMPILED_DIR="$DIST_DIR/QA3D-compiled"
STAGE_DIR="$DIST_DIR/$BUNDLE_NAME"

echo ""
echo "=========================================="
echo "     QA3D Linux Bundle Builder"
echo "=========================================="
echo "  Version:  $VERSION"
echo "  Arch:     $ARCH"
echo "  Output:   $BUNDLE_NAME.tar.gz"
echo "=========================================="
echo ""

# Step 1: Build compiled app
echo "1. Building compiled application..."
echo "   This may take 5-15 minutes..."
julia "$SCRIPT_DIR/build_sysimage.jl"

if [ ! -f "$COMPILED_DIR/bin/qa3d" ]; then
    echo "ERROR: Compiled app not found at $COMPILED_DIR/bin/qa3d"
    exit 1
fi

# Step 2: Stage the bundle
echo "2. Staging bundle..."
rm -rf "$STAGE_DIR"
cp -r "$COMPILED_DIR" "$STAGE_DIR"

# Step 3: Copy runtime assets
echo "3. Copying runtime assets..."
cp -r "$PROJECT_DIR/public" "$STAGE_DIR/"
cp -r "$PROJECT_DIR/views" "$STAGE_DIR/"
cp "$PROJECT_DIR/Manifest.toml" "$STAGE_DIR/share/julia/"
cp "$SCRIPT_DIR/qa3d.sh" "$STAGE_DIR/"
chmod +x "$STAGE_DIR/qa3d.sh"

# Step 4: Archive
echo "4. Creating archive..."
cd "$DIST_DIR"
tar czf "${BUNDLE_NAME}.tar.gz" "$BUNDLE_NAME"

ARCHIVE_SIZE=$(du -sh "${BUNDLE_NAME}.tar.gz" | cut -f1)

echo ""
echo "=========================================="
echo "  Bundle created successfully!"
echo "=========================================="
echo "  Archive: dist/${BUNDLE_NAME}.tar.gz"
echo "  Size:    $ARCHIVE_SIZE"
echo "  Run:     bin/qa3d"
