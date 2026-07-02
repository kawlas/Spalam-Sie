#!/bin/bash
# build-dmg.sh — Build Spalam Sie .dmg for distribution
set -euo pipefail

APP_NAME="Spalam Sie"
DMG_NAME="Spalam-Sie"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/${DMG_NAME}.dmg"
STAGING_DIR="$PROJECT_DIR/.dmg-staging"

echo "=== Building $APP_NAME DMG ==="

# 1. Build app bundle
if [ ! -d "$APP_BUNDLE" ]; then
    echo "→ Building app bundle first..."
    bash "$PROJECT_DIR/build-app.sh"
else
    echo "→ App bundle exists at $APP_BUNDLE"
    echo "→ Rebuilding to ensure latest version..."
    bash "$PROJECT_DIR/build-app.sh"
fi

# 2. Verify bundle
if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: App bundle not found. Build it first: bash build-app.sh"
    exit 1
fi

# 3. Prepare staging
echo "→ Preparing DMG staging..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"

# 4. Create DMG
echo "→ Creating DMG..."
rm -f "$DMG_PATH"

# Get version for filename
VERSION=$(plutil -extract CFBundleShortVersionString xml1 -o - "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g' || echo "1.0")
DMG_FINAL="$PROJECT_DIR/${DMG_NAME}-${VERSION}.dmg"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" 2>&1 | tail -3

# 5. Enable window layout (background retina)
# Set custom icon position and window size
echo "→ Configuring DMG window..."
# Detach if already mounted
hdiutil detach "/Volumes/$APP_NAME" 2>/dev/null || true

# Attach
hdiutil attach "$DMG_PATH" -nobrowse 2>&1 | tail -2

# Set window position and icon layout
osascript -e "
tell application \"Finder\"
    tell disk \"$APP_NAME\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 800, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file \".background:bg.png\"
        delay 1
        close
    end tell
end tell
" 2>/dev/null || true

# Detach
hdiutil detach "/Volumes/$APP_NAME" 2>/dev/null || true

# 6. Rename final DMG
if [ -f "$DMG_PATH" ]; then
    mv "$DMG_PATH" "$DMG_FINAL"
    echo ""
    echo "=== ✅ DMG built: ==="
    echo "   $DMG_FINAL"
    ls -lh "$DMG_FINAL"
fi

# 7. Cleanup
rm -rf "$STAGING_DIR"

echo ""
echo "To distribute:"
echo "   open \"$DMG_FINAL\""
