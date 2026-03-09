#!/bin/bash
set -e

SCHEME="Yap"
ARCHIVE_PATH="build/Yap.xcarchive"
EXPORT_PATH="build/export"
APP_NAME="Yap"

echo "Generating Xcode project..."
xcodegen generate

echo "Archiving..."
xcodebuild \
  -project Yap.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  | grep -E "(error:|Archive Succeeded|BUILD)" || true

echo "Exporting..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ExportOptions.plist \
  | grep -E "(error:|Export Succeeded|BUILD)" || true

VERSION=$(defaults read "$(pwd)/$EXPORT_PATH/$APP_NAME.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "Zipping $APP_NAME.app → $ZIP_NAME (for Sparkle)"
cd "$EXPORT_PATH"
ditto -c -k --keepParent "$APP_NAME.app" "../../$ZIP_NAME"
cd -

echo "Creating $DMG_NAME (for GitHub Releases)..."
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 560 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 140 185 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 420 185 \
  "$DMG_NAME" \
  "$EXPORT_PATH/"

echo ""
echo "Done: $DMG_NAME  (distribute this)"
echo "      $ZIP_NAME  (Sparkle auto-update)"
echo ""
echo "Release steps:"
echo "  1. Upload $DMG_NAME + $ZIP_NAME to GitHub Releases"
echo "  2. Run generate_appcast with --download-url-prefix for $ZIP_NAME"
echo "  3. Commit + push appcast.xml"
