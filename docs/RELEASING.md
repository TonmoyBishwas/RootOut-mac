# Releasing RootOut

The whole release is three scripts and one `gh` command. It takes about two
minutes. Do it from a clean `main`.

## 1. Bump the version

`Resources/Info.plist` is the **only** place a version number lives:

```xml
<key>CFBundleShortVersionString</key>   <!-- 1.0.1  → user-visible, names the DMG -->
<key>CFBundleVersion</key>              <!-- 2      → monotonic build number -->
```

`Scripts/make-dmg.sh` reads `CFBundleShortVersionString` out of the built
bundle to name the artifact, so this one edit drives everything downstream.

The README links to `/releases/latest` and hardcodes no version. Leave it that
way.

## 2. Verify

```bash
swift test              # must be green — 30 tests, 3 suites
./Scripts/build-app.sh  # dist/RootOut.app, arm64, ad-hoc signed
./Scripts/make-dmg.sh   # dist/RootOut-<version>.dmg
```

Then actually check the artifact rather than trusting the scripts:

```bash
hdiutil attach dist/RootOut-<version>.dmg
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    /Volumes/RootOut/RootOut.app/Contents/Info.plist   # → the new version
lipo -archs /Volumes/RootOut/RootOut.app/Contents/MacOS/RootOut   # → arm64
codesign -v /Volumes/RootOut/RootOut.app                          # → no output = OK
ls /Volumes/RootOut                                               # → RootOut.app, Applications
hdiutil detach /Volumes/RootOut
```

Launch it once from the mounted image and click through an uninstall you can
undo (anything whose Trash contents you are willing to restore).

## 3. Commit and push

```bash
git commit -am "release: 1.0.x"
git push
```

`dist/` is gitignored — the DMG must not enter the tree. It ships as a release
asset only.

## 4. Cut the release

```bash
gh release create v1.0.x dist/RootOut-1.0.x.dmg \
    --title "RootOut 1.0.x" \
    --notes "$(cat <<'EOF'
### Install
1. Download **RootOut-1.0.x.dmg** below.
2. Open it and drag **RootOut** to **Applications**.
3. First launch only: right-click (or Control-click) RootOut → **Open** → **Open**.

Requires an Apple Silicon Mac running macOS 15 or later.

### What's new
- …
EOF
)"
```

Always include the right-click → Open instruction. The app is not notarized,
and without that line users will conclude it is broken or malicious.

## 5. Verify what you actually published

Not what you built — what GitHub is serving. Download it back:

```bash
cd "$(mktemp -d)"
gh release download v1.0.x -R TonmoyBishwas/RootOut-mac
hdiutil attach RootOut-1.0.x.dmg
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    /Volumes/RootOut/RootOut.app/Contents/Info.plist
lipo -archs /Volumes/RootOut/RootOut.app/Contents/MacOS/RootOut
codesign -v /Volumes/RootOut/RootOut.app
hdiutil detach /Volumes/RootOut
```

This has caught nothing so far, and it costs fifteen seconds. Keep doing it —
a corrupted or stale upload is invisible from the release page.

## Notes

- **The app is ad-hoc signed, never notarized.** Do not add a paid certificate
  to solve the Gatekeeper warning. See [SECURITY.md](../SECURITY.md).
- **arm64 only.** `build-app.sh` passes `--arch arm64`; a fat binary would
  double the download for no user.
- **No auto-updater**, by design. Users return to the releases page. That is
  the trade for shipping no background process.
