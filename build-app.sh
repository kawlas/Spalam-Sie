#!/bin/bash
# build-app.sh — Build Spalam Sie.app bundle for macOS
set -euo pipefail

APP_NAME="Spalam Sie"
BUNDLE_ID="com.spalamsie.burner"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "=== Building $APP_NAME ==="

# 1. Build release binary
echo "→ Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -5

BINARY="$BUILD_DIR/arm64-apple-macosx/release/Spalam Sie"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
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
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/SpalamSie"
chmod +x "$APP_BUNDLE/Contents/MacOS/SpalamSie"

# 5. Copy Info.plist
echo "→ Copying Info.plist..."
if [ -f "$PROJECT_DIR/Sources/Spalam Sie/Resources/Info.plist" ]; then
    cp "$PROJECT_DIR/Sources/Spalam Sie/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
    echo "ERROR: Info.plist not found"
    exit 1
fi

# 6. Copy icons
echo "→ Copying icons..."
if [ -f "$PROJECT_DIR/Sources/Spalam Sie/Resources/SpalamSie.icns" ]; then
    cp "$PROJECT_DIR/Sources/Spalam Sie/Resources/SpalamSie.icns" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -f "$PROJECT_DIR/Icons/logo  Spalam Sie.png" ]; then
    cp "$PROJECT_DIR/Icons/logo  Spalam Sie.png" "$APP_BUNDLE/Contents/Resources/"
fi

# 7. Copy SFBAudioEngine binary frameworks (mpg123, opus, FLAC, sndfile, lame)
echo "→ Copying binary frameworks..."
FRAMEWORKS_SOURCE="$BUILD_DIR/arm64-apple-macosx/release"
FRAMEWORKS_DEST="$APP_BUNDLE/Contents/Frameworks"

# These frameworks are built as dependencies of SFBAudioEngine
FRAMEWORKS=("mpg123" "opus" "FLAC" "sndfile" "lame")

for fw in "${FRAMEWORKS[@]}"; do
    FW_SRC="$FRAMEWORKS_SOURCE/$fw.framework"
    FW_DEST="$FRAMEWORKS_DEST/$fw.framework"
    if [ -d "$FW_SRC" ]; then
        echo "  → Copying $fw.framework"
        cp -R "$FW_SRC" "$FW_DEST"
        # Fix install_name to use @rpath
        install_name_tool -id "@rpath/$fw.framework/Versions/A/$fw" "$FW_DEST/Versions/A/$fw" 2>/dev/null || true
    else
        # Check artifacts directory for xcframework
        XCFW_SRC=$(find "$BUILD_DIR/artifacts" -name "$fw.xcframework" 2>/dev/null | head -1)
        if [ -n "$XCFW_SRC" ]; then
            MACOS_FW=$(find "$XCFW_SRC" -path "*macos-arm64*/$fw.framework" 2>/dev/null | head -1)
            if [ -n "$MACOS_FW" ] && [ -d "$MACOS_FW" ]; then
                echo "  → Copying $fw.framework from xcframework"
                cp -R "$MACOS_FW" "$FW_DEST"
                install_name_tool -id "@rpath/$fw.framework/Versions/A/$fw" "$FW_DEST/Versions/A/$fw" 2>/dev/null || true
            fi
        else
            echo "  ⚠️  Warning: $fw.framework not found"
        fi
    fi
done

# 8. Fix binary rpath to include Frameworks directory
echo "→ Fixing binary rpath..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/SpalamSie" 2>/dev/null || true

# 9. Fix framework rpaths
for fw in "${FRAMEWORKS[@]}"; do
    FW_DEST="$FRAMEWORKS_DEST/$fw.framework/Versions/A/$fw"
    if [ -f "$FW_DEST" ]; then
        install_name_tool -add_rpath "@loader_path/../.." "$FW_DEST" 2>/dev/null || true
    fi
done

# 10. Sign with ad-hoc signature
echo "→ Signing bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "Warning: codesign failed (not critical for development)"
}

echo ""
echo "=== ✅ $APP_NAME.app built at: ==="
echo "   $APP_BUNDLE"
echo ""
echo "Run it:"
echo "   open \"$APP_BUNDLE\""
echo "   # or:"
echo "   $APP_BUNDLE/Contents/MacOS/SpalamSie"