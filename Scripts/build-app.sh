#!/bin/bash
# Builds dist/RootOut.app (release, arm64, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building release binary (arm64)"
swift build -c release --arch arm64

APP=dist/RootOut.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/arm64-apple-macosx/release/RootOut "$APP/Contents/MacOS/RootOut"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Rendering app icon"
ICONDIR=dist/AppIcon.iconset
rm -rf "$ICONDIR" && mkdir -p "$ICONDIR"
swift Scripts/make-icon.swift "$ICONDIR/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONDIR/icon_512x512@2x.png" --out "$ICONDIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    if [ $size -ne 512 ]; then
        sips -z $double $double "$ICONDIR/icon_512x512@2x.png" --out "$ICONDIR/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONDIR" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONDIR"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Done: $APP"
codesign -dv "$APP" 2>&1 | head -3
