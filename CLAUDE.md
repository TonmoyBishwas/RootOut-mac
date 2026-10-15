# CLAUDE.md

Guidance for Claude Code (and any AI agent) working in this repository.

Read this first. Then read [CODEBASE.md](CODEBASE.md) before changing code —
it explains the architecture and the invariants that keep the app from
deleting the wrong thing.

## What RootOut is

A free, open-source, minimal deep app uninstaller for Apple Silicon Macs.
You pick an installed app; RootOut finds every file it left behind across
`~/Library` and `/Library`, and moves the app plus its leftovers to the Trash.

That is the entire product. It is not a cleaner suite.

## The prime directive: this app deletes the user's files

Everything else in this document follows from that. A bug in a normal app
shows a wrong number on screen. A bug in RootOut destroys data that someone
spent years accumulating.

Two rules encode it:

1. **A missed leftover is fine. A wrong deletion is not.** When matching is
   ambiguous, do not match. `LeftoverScanner` is deliberately strict and it
   should stay that way even if it means a stray cache file survives.
2. **Deletions are recoverable by default.** `FileManager.trashItem` only.
   The single permanent path is `Uninstaller.removeWithAdminPrivileges`,
   which runs `rm -rf` as root and exists solely because the Trash cannot
   accept root-owned files. It is reached only after the user clicks a
   button labeled with what it does.

## Non-negotiables

These are decisions, not preferences. Do not revisit them without the owner
saying so explicitly. See [CONTRIBUTING.md](CONTRIBUTING.md) for the scope
policy in full.

| Constraint | Detail |
|---|---|
| Scope | One job: uninstall an app and its leftovers. Nothing else. |
| Dependencies | Zero. `Package.swift` has no `dependencies:` array and must not grow one. |
| Network | RootOut never makes a network request. No telemetry, no update check, no crash reporting. |
| Architecture | Apple Silicon only (`arm64`). macOS 15+. |
| Deletion | Trash by default; permanent removal only via the explicit admin prompt. |
| Containment | Every path to be deleted passes `Uninstaller.allowedDeletionPath` first. No exceptions. |

**Explicitly out of scope** (past requests, all declined): orphan-file
scanners, duplicate finders, large-file finders, startup-item managers,
auto-updaters, menubar extras, analytics, a preferences window, onboarding
screens, app "optimization" of any kind.

If you think a feature is a good idea, say so in prose and stop. Do not
build it.

## Commands

```bash
swift build             # debug build of the package
swift test              # 30 tests, 3 suites — all core logic, must stay green
./Scripts/build-app.sh  # release build → dist/RootOut.app (arm64, ad-hoc signed)
./Scripts/make-dmg.sh   # dist/RootOut.app → dist/RootOut-<version>.dmg
```

`make-dmg.sh` reads the version out of `dist/RootOut.app/Contents/Info.plist`,
so `build-app.sh` must run first. Releasing is documented in
[docs/RELEASING.md](docs/RELEASING.md).

## How to make a change here

1. **Core logic changes go through tests first.** `RootOutCore` is pure
   Foundation and fully testable against a temp-directory fixture. Write the
   failing test in `Tests/RootOutCoreTests/`, then make it pass. Anything
   touching `Uninstaller` or `LeftoverScanner` needs a test that would catch
   the deletion of a file that should have survived.
2. **UI changes are unit-test-free by design.** `Sources/RootOut/` has no
   tests; it is thin. Keep it thin. Logic that could be tested belongs in
   `RootOutCore`, not in a view.
3. **Match the existing idiom.** The UI has exactly two glass surfaces
   (`glassCard`, `glassCapsule` in `Glass.swift`) and exactly one colored
   element (the red Uninstall button and its byte count). New chrome should
   reuse those, not invent a third style.
4. **Run `swift test` and build the app before claiming anything works.**

## Common mistakes to avoid

Each of these has already bitten someone. They are listed in rough order of
how much damage they cause.

**Deleting outside the containment check.** `FileManager.trashItem` and
`removeItem` must never be called on a user-supplied path anywhere except
behind `Uninstaller.allowedDeletionPath`. That function folds `..`, resolves
every parent symlink with `realpath(3)`, and enforces a minimum depth. It is
the only thing standing between a malformed bundle ID and `~/Library`.

**Resolving the leaf component of a deletion path.** `deletionPath(for:)`
canonicalizes the *parent* and leaves the final component alone, on purpose.
If you "clean this up" by calling `resolvingSymlinksInPath()` on the whole
URL, then trashing a symlink starts trashing its target — and app bundles
are full of symlinks. There is a test named
`trashingASymlinkNeverTouchesItsTarget` guarding this; if it fails, you broke
it.

**Lowering `minDepth` on the Library roots.** `~/Library` and `/Library` use
`minDepth: 2` so that `~/Library/Preferences` — the folder itself, holding
every app's settings — can never be a deletion target. Only things *inside*
those subfolders qualify. `/Applications` uses `minDepth: 1` because an app
bundle sits directly in it.

**Assigning `selectionID` casually.** Its `didSet` calls `startScan()`, which
wipes `items`, `checked`, `failures`, and `phase`. Commit `50ccd12` fixed a
bug where clearing the selection after an uninstall destroyed the failure
list, so the "Remove with Administrator Privileges…" button vanished before
the user could click it. `AppState.uninstall()` therefore clears the
selection *first* and assigns the outcome *after*, and `refresh()` only
clears the selection when an app that genuinely was selected has genuinely
disappeared. Read the comments in `AppState.swift` before touching either.

**Loosening the scanner's matching.** `matchesBundleID` requires an exact
match, a dot-boundary prefix, or the `group.` form. A bare `hasPrefix` would
make `com.foo.Bar` match `com.foo.Barbecue`. Name matching additionally
requires ≥ 4 characters, absence from `nameDenylist`, and a directory — a
substring match here would delete another vendor's data.

**Forgetting to canonicalize in tests.** `FixtureDir` resolves
`/var/folders/…` to `/private/var/folders/…` on creation. Without that,
fixture URLs compare unequal to what `contentsOfDirectory` returns and tests
fail for reasons that have nothing to do with your change.

**Bumping the version in the wrong place.** `Resources/Info.plist` is the
single source of truth (`CFBundleShortVersionString` + `CFBundleVersion`).
The README deliberately links to `/releases/latest` and hardcodes no version.

**"Fixing" the Gatekeeper warning.** The app is ad-hoc signed and not
notarized, because notarization costs $99/year and this is free software.
The right-click → Open instructions in the README are the intended UX. Do not
add a paid developer certificate, and do not paper over it with a script that
disables Gatekeeper.

## Agent workflow notes

- When dispatching subagents for research or mechanical tasks, override the
  model to a cheaper one than the main session (for example, the current
  Sonnet) — the owner asked for this to keep token cost down.
- `dist/` is gitignored. Build artifacts and the DMG live on GitHub Releases,
  never in the tree.
- The shell in this environment usually lacks screen-recording permission, so
  `screencapture` fails. You can build and launch the app to confirm it runs,
  but you cannot verify visually. Say so rather than implying you looked.
