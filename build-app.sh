#!/bin/bash
# build-app.sh — Build Spalam Sie.app bundle for macOS
set -euo pipefail

APP_NAME="Spalam Sie"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "=== Building $APP_NAME ==="

# 1. Build release binary
echo "→ Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -3

BINARY_SRC="$BUILD_DIR/arm64-apple-macosx/release/Spalam Sie"
if [ ! -f "$BINARY_SRC" ]; then
    echo "ERROR: Binary not found at $BINARY_SRC"
    exit 1
fi

# 2. Remove old bundle
if [ -d "$APP_BUNDLE" ]; then
    echo "→ Removing old bundle..."
    rm -rf "$APP_BUNDLE"
fi

# 3. Create app bundle structure
echo "→ Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# 4. Copy binary
echo "→ Copying binary..."
cp "$BINARY_SRC" "$APP_BUNDLE/Contents/MacOS/SpalamSie"
chmod +x "$APP_BUNDLE/Contents/MacOS/SpalamSie"

# 5. Copy Info.plist
echo "→ Copying Info.plist..."
cp "$PROJECT_DIR/Sources/Spalam Sie/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 6. Copy icons
echo "→ Copying icons..."
if [ -f "$PROJECT_DIR/Sources/Spalam Sie/Resources/SpalamSie.icns" ]; then
    cp "$PROJECT_DIR/Sources/Spalam Sie/Resources/SpalamSie.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# 7. Copy ALL binary frameworks (preserve symlinks with -P -R)
echo "→ Copying binary frameworks..."
FRAMEWORKS_SOURCE="$BUILD_DIR/arm64-apple-macosx/release"
FRAMEWORKS_DEST="$APP_BUNDLE/Contents/Frameworks"

for fw_path in "$FRAMEWORKS_SOURCE"/*.framework/; do
    if [ -d "$fw_path" ]; then
        fw_name=$(basename "${fw_path%/}" .framework)
        echo "  → Copying $fw_name.framework"
        cp -PR "${fw_path%/}" "$FRAMEWORKS_DEST/"
    fi
done

# 8. Fix binary rpath
echo "→ Fixing binary rpath..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/SpalamSie" 2>/dev/null || true

# 9. Clean up any .DS_Store / resource forks in Frameworks
echo "→ Cleaning up resource forks..."
find "$FRAMEWORKS_DEST" -name ".DS_Store" -delete 2>/dev/null || true

# 10. Sign frameworks individually
echo "→ Signing frameworks..."
for fw_path in "$FRAMEWORKS_DEST"/*.framework/; do
    if [ -d "$fw_path" ]; then
        fw_name=$(basename "${fw_path%/}" .framework)
        codesign --force --sign - "${fw_path%/}" 2>&1 || echo "  ⚠️  Could not sign $fw_name.framework"
    fi
done

# 11. Sign main binary
echo "→ Signing binary..."
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/SpalamSie" 2>&1 || echo "Warning: binary codesign failed"

# 12. Sign entire bundle (not deep — already signed individually)
echo "→ Signing bundle..."
codesign --force --sign - "$APP_BUNDLE" 2>&1 || echo "Warning: bundle codesign failed"

echo ""
echo "=== ✅ $APP_NAME.app built at: ==="
echo "   $APP_BUNDLE"
echo ""
echo "Run it:"
echo "   open \"$APP_BUNDLE\""
echo "   # or:"
echo "   $APP_BUNDLE/Contents/MacOS/SpalamSie"