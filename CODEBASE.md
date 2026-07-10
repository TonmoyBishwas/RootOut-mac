# CODEBASE.md

A ground-level tour of RootOut, for anyone — human or agent — who needs to
change it. Read [CLAUDE.md](CLAUDE.md) first for the rules; this file explains
the machinery.

About 1,250 lines of Swift including tests, no dependencies. You can read the
whole thing in under an hour, and it is worth doing before your first change.

## Layout

```
Package.swift              Swift 6, macOS 15+, three targets, zero dependencies
Resources/Info.plist       Bundle metadata — the version lives here and nowhere else

Sources/RootOutCore/       Pure Foundation. All the logic. All the tests.
  Models.swift             InstalledApp, LeftoverKind, LeftoverItem
  AppInventory.swift       Which apps exist and may be uninstalled
  LeftoverScanner.swift    Which files belong to a given app
  Uninstaller.swift        Which deletions are permitted, and how they happen
                           (+ SizeCalculator)

Sources/RootOut/           SwiftUI. Thin. Untested by design.
  RootOutApp.swift         @main, NavigationSplitView, window chrome
  AppState.swift           The single @Observable store; all async orchestration
  AppListView.swift        Sidebar: search, app list, refresh capsule
  DetailView.swift         Leftover list, size total, Uninstall button, failures
  Glass.swift              glassCard() / glassCapsule() — the only two surfaces

Tests/RootOutCoreTests/    Swift Testing (@Suite/@Test/#expect), not XCTest
  Fixtures.swift           FixtureDir: throwaway temp tree, cleaned up on deinit
  AppInventoryTests.swift  7 tests
  ScannerTests.swift       10 tests
  UninstallerTests.swift   13 tests

Scripts/
  build-app.sh             swift build --arch arm64 → .app, renders icon, ad-hoc signs
  make-dmg.sh              .app → compressed DMG with an /Applications symlink
  make-icon.swift          Draws the 1024px icon with AppKit at build time

docs/                      Design spec, implementation plan, release process
dist/                      Build output. Gitignored. Never committed.
```

The split is the important part: **`RootOutCore` knows nothing about SwiftUI,
and `RootOut` knows nothing about the filesystem.** Core is a library of pure
functions over a real filesystem, so every dangerous decision is reachable
from a test. If you find yourself writing an `if` statement about which files
to delete inside a `View`, you are in the wrong file.

## The data flow, end to end

```
launch / ⌘R
    │
    ▼
AppState.refresh()  ──►  AppInventory.installedApps()   [detached task]
    │                       scans /Applications and ~/Applications, 2 levels deep
    │                       drops com.apple.* and RootOut itself
    ▼
apps: [InstalledApp]  ──►  AppListView sidebar
    │
    │ user clicks a row
    ▼
AppState.selectionID = url
    │ didSet ──► startScan()
    ▼
LeftoverScanner.scan(app:)  +  SizeCalculator.size(of:)   [detached task]
    │                       walks 13 known Library locations
    │                       matches on bundle ID, cautiously on name
    ▼
items: [LeftoverItem]   (all pre-checked)  ──►  DetailView list, grouped by kind
    │
    │ user unchecks some, clicks Uninstall, confirms
    ▼
AppState.uninstall()
    │  force-terminates the running app, waits 400ms
    ▼
Uninstaller.uninstall(items:)   [detached task]
    │  every path → allowedDeletionPath() → trashItem()
    ▼
UninstallResult { trashed, failed }
    │
    ├─ failed is empty  ──►  "Moved N items to the Trash"
    │
    └─ failed is non-empty (root-owned paths)
           ▼
       DetailView shows the paths + "Remove with Administrator Privileges…"
           ▼
       Uninstaller.removeWithAdminPrivileges()  ──►  osascript, rm -rf, one password prompt
```

Every filesystem operation runs in `Task.detached(priority: .userInitiated)`.
`AppState` is `@MainActor`, so results hop back to the main actor on assignment.

## The four core types

### `AppInventory` — what may be uninstalled

Walks the search directories two levels deep (so `/Applications/Utilities/Foo.app`
is found), reads each `Contents/Info.plist`, and returns `InstalledApp` values
sorted by name.

Two filters matter:

- `bundleID.hasPrefix("com.apple.")` — RootOut will never offer to remove part
  of macOS.
- `bundleID != ownBundleID` — it will never offer to remove itself.

**Nothing is cached.** `installedApps()` hits the disk on every call. That is
what makes the sidebar's refresh button a two-line feature rather than a cache
invalidation problem, and there is a test (`rescanSeesAppInstalledAfterFirstScan`)
pinning the property in place. If you ever add memoization, you break the
refresh button.

`searchURLs` is injectable, which is the only reason this is testable.

### `LeftoverScanner` — what belongs to an app

Given an `InstalledApp`, returns the app bundle plus everything found in 13
`Location`s (Application Support, Caches, Preferences, Containers, Group
Containers, Saved Application State, Logs, LaunchAgents, LaunchDaemons,
HTTPStorages, WebKit, Cookies, Application Scripts), plus crash reports.

Each `Location` declares whether it exists in the user library, the local
(`/Library`) one, or both, and whether **name matching** is allowed there.

Matching has two tiers, and the asymmetry is deliberate:

- **Bundle ID** (always trusted): exact match, dot-boundary prefix
  (`com.foo.Bar.plist`, `com.foo.Bar.helper.plist`), or the app-group form
  `group.com.foo.Bar`. A plain `hasPrefix` would match `com.foo.Barbecue`.
- **App name** (rarely trusted): only in `nameMatchable` locations, only for a
  directory, only on a case-insensitive *exact* match, only when the name is
  ≥ 4 characters and absent from `nameDenylist` (`app`, `mac`, `pro`, `music`,
  `notes`, `mail`, `photos`, …). A folder called `Music` is not your app's.

Crash reports are matched on `<AppName><separator>` with the separator drawn
from `-_. ` and an extension of `ips`/`crash`/`diag`/`hang`.

Missing directories are skipped silently — most Macs do not have every one of
these folders.

> The comment at the top of the file is the whole design in two lines: *a wrong
> match deletes someone else's data, a missed match just leaves a file behind.*
> Every ambiguity resolves toward leaving the file behind.

### `Uninstaller` — what deletion is allowed

This is the security boundary. Everything else in the app can be wrong without
losing data; this cannot.

A path is deletable only if `allowedDeletionPath(for:)` returns non-nil, which
requires it to sit under one of four **roots** at or below the root's
`minDepth`:

| Root | minDepth | Why |
|---|---|---|
| `/Applications` | 1 | An app bundle sits directly inside. |
| `~/Applications` | 1 | Same. |
| `~/Library` | 2 | So `~/Library/Preferences` itself is never a target — only things *inside* it. |
| `/Library` | 2 | Same, for the shared domain. |

Three properties hold, each with a test:

1. **`..` cannot escape.** The URL is `standardizedFileURL`-folded before
   anything else looks at it.
2. **A symlinked parent cannot smuggle a path in.** `realpath(3)` resolves
   every parent component, so `~/Library/Caches/evil → /etc` is checked as
   `/etc`, and rejected.
3. **Deleting a symlink never touches its target.** The *leaf* component is
   deliberately left unresolved. Canonicalizing it would make trashing a link
   inside an app bundle trash whatever it points at.

`removeWithAdminPrivileges` exists because the Trash cannot hold root-owned
files. It builds one `osascript` command and prompts once. Because that string
is executed as root, filenames cross **two escaping layers** —
`shellQuoted` (single-quote wrapping, `'` → `'\''`) inside
`appleScriptEscaped` (backslash, quote, newline, carriage return). A file named
`"; rm -rf /; #` must not break out of either. `adminScriptEscapesHostileFilenames`
tests exactly that. It also re-runs the containment check, so a path that
survived to this point still cannot be outside the roots.

`SizeCalculator` (same file) recursively sums allocated size, returning `0`
rather than throwing on anything it cannot read.

### `AppState` — the one place with mutable state

`@MainActor @Observable`. Holds `apps`, `query`, `items`, `checked`, `phase`,
`failures`, `isRefreshing`, `selectionID`.

**The one trap in the UI layer:**

```swift
var selectionID: URL? {
    didSet { if selectionID != oldValue { startScan() } }
}
```

`startScan()` resets `items`, `checked`, `failures`, and `phase`. So *any*
assignment to `selectionID` — including clearing it — destroys the result of a
finished uninstall. Commit `50ccd12` fixed the resulting bug: after uninstalling
an app, clearing the now-dangling selection wiped `failures`, and the
"Remove with Administrator Privileges…" button disappeared before the user
could press it.

Two places live with this, and both have comments:

- `uninstall()` clears `selectionID` **first**, then assigns `failures` and
  `phase`, so the outcome survives the `didSet`.
- `refresh()` only clears `selectionID` when a selection genuinely exists *and*
  the app it points at genuinely vanished. After an uninstall it is already
  `nil`, so the guard cannot fire and cannot clobber the result on screen.

If you add a third writer to `selectionID`, work out what its `didSet` does to
whatever is currently displayed. This is the single most likely place to
reintroduce a regression.

`phase` drives the whole detail pane: `.idle → .scanning → .ready →
.uninstalling → .done(summary)`.

## The look

Two glass surfaces, defined once in `Glass.swift`:

```swift
glassCard(cornerRadius:)   // rounded rect
glassCapsule()             // the floating action bars
```

Both call `.glassEffect(.regular, in:)` on macOS 26+ (real Liquid Glass) and
fall back to `.ultraThinMaterial` on macOS 15. The window itself uses
`.containerBackground(.thinMaterial, for: .window)` and `.windowStyle(.hiddenTitleBar)`.

Design constraints worth preserving:

- **One accent.** The red byte-count and the red Uninstall button are the only
  colored things on screen. Everything else is `.secondary`/`.tertiary` gray.
  Adding a second accent color would flatten the visual hierarchy that makes
  the destructive action obvious.
- **Floating capsules, not toolbars.** Both the sidebar's refresh control and
  the detail pane's action bar are `glassCapsule()`s floating over scrolling
  content. The sidebar uses `.safeAreaInset(edge: .bottom)` so the capsule
  never covers the last row; the detail list reserves space with a
  `Color.clear.frame(height: 44)` spacer instead. Either works — pick the
  matching one when adding a third.
- **Numbers animate.** `.contentTransition(.numericText())` on counts.

## Testing

Swift Testing, not XCTest: `@Suite struct`, `@Test func`, `#expect(…)`,
`@testable import RootOutCore`.

`FixtureDir` builds a throwaway tree under the temp directory and deletes it on
`deinit`. It canonicalizes the temp path on creation (`/var/folders/…` →
`/private/var/folders/…`) so that fixture URLs compare equal to what
`contentsOfDirectory` hands back. Forget that and you will chase a failure that
has nothing to do with your change.

Helpers: `dir(_:)`, `file(_:contents:)`, `symlink(_:to:)`, `app(_:bundleID:name:version:)`.

`Uninstaller(allowedRoots:)` takes an injected root list precisely so the
destructive tests can run against a fixture instead of `/Applications`.

The UI target has no tests. That is a deliberate trade: the views are thin
enough to review by eye, and testing SwiftUI would cost more than it catches.
The corollary is that **logic must not accumulate in the views.**

## Build and release

`build-app.sh` assembles the `.app` by hand — no Xcode project exists. It
release-builds for `arm64`, copies the binary and `Info.plist` into a bundle,
runs `make-icon.swift` to draw the icon and `sips`/`iconutil` to produce the
`.icns`, then ad-hoc signs (`codesign --force --sign -`).

`make-dmg.sh` reads `CFBundleShortVersionString` from the built bundle, stages
the app next to an `/Applications` symlink, and runs `hdiutil create -format UDZO`.

The app is **not notarized** — that costs $99/year. Users right-click → Open on
first launch. See [docs/RELEASING.md](docs/RELEASING.md) for the full checklist.

## Where things are likely to change

Ranked by how often it will come up, with the trap in each:

- **A new leftover location.** Add a `Location` to `LeftoverScanner.locations`.
  Decide `user`/`local`/`nameMatchable` carefully — `nameMatchable: true` on a
  shared folder is how you delete someone else's data. Add a scanner test.
- **A new deletion root.** Add a `Root` with the right `minDepth` and ask what
  the shallowest legitimate target is. Add a containment test that proves the
  root's own subfolders are still un-deletable.
- **A macOS version bump.** `Package.swift` platforms, `LSMinimumSystemVersion`
  in `Info.plist`, the `#available(macOS 26.0, *)` gates in `Glass.swift`, and
  the README's stated requirement all have to move together.
- **UI polish.** Reuse `glassCard`/`glassCapsule`. Resist adding a toolbar,
  a settings pane, or a second accent color.
