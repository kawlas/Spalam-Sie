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

# 4. Copy binary
echo "→ Copying binary..."
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/SpalamSie"
chmod +x "$APP_BUNDLE/Contents/MacOS/SpalamSie"

# 5. Copy Info.plist
echo "→ Copying Info.plist..."
# Use the one from Resources if available, otherwise generate minimal
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

# Also copy PNG assets for additional UI use
if [ -f "$PROJECT_DIR/Icons/logo  Spalam Sie.png" ]; then
    cp "$PROJECT_DIR/Icons/logo  Spalam Sie.png" "$APP_BUNDLE/Contents/Resources/"
fi

# 7. Sign with ad-hoc signature
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
