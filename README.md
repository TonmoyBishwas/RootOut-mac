# RootOut

A free, open-source, minimal deep app uninstaller for Apple Silicon Macs.

Pick an app. RootOut finds every file it left across your system — support
files, caches, preferences, containers, launch agents, logs, crash reports —
and moves the app and all of it to the Trash. Nothing is deleted permanently,
so you can always change your mind.

One job, done well. No cleaner suites, no background helpers, no subscriptions,
no analytics — RootOut never touches the network.

## Install

1. Download **RootOut-x.x.x.dmg** from the
   [latest release](https://github.com/TonmoyBishwas/RootOut-mac/releases/latest).
2. Open the DMG and drag **RootOut** into the **Applications** folder.
3. First launch only: **right-click (or Control-click) RootOut → Open → Open**.
   macOS shows a warning because RootOut is a free app that isn't notarized by
   Apple ($99/year) — the source code is all here, so you can see exactly what
   it does.

   If macOS still refuses to open it, run this once in Terminal:

   ```bash
   xattr -cr /Applications/RootOut.app
   ```

Requires an Apple Silicon Mac (M1 or newer) running macOS 15 Sequoia or later.
On macOS 26 Tahoe the interface uses native Liquid Glass.

## How it works

- **Find** — RootOut lists your installed apps (system apps are hidden;
  it will never offer to remove part of macOS).
- **Scan** — selecting an app searches the standard locations in `~/Library`
  and `/Library` for files matching the app's bundle identifier, plus a
  conservative name match. Matching is deliberately strict: a missed leftover
  is better than deleting another app's data.
- **Remove** — everything you leave checked is moved to the Trash. Files owned
  by the system that can't be trashed are listed, and you can remove them with
  an administrator prompt if you choose.

## Build from source

```bash
git clone https://github.com/TonmoyBishwas/RootOut-mac.git
cd RootOut-mac
swift test              # run the unit tests
./Scripts/build-app.sh  # build dist/RootOut.app
./Scripts/make-dmg.sh   # package the DMG
```

Requires Xcode 16+ on Apple Silicon. No dependencies.

## License

[MIT](LICENSE) — free forever.
