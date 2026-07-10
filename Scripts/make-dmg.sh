#!/bin/bash
# Packages dist/RootOut.app into dist/RootOut-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/RootOut.app
[ -d "$APP" ] || { echo "Run Scripts/build-app.sh first"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/RootOut-$VERSION.dmg"
STAGING=dist/dmg-staging

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "RootOut" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Done: $DMG"
ls -lh "$DMG"
