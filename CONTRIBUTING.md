# Contributing to RootOut

Thanks for being here. RootOut is small on purpose, and keeping it small is
most of the work.

## The scope policy, up front

RootOut uninstalls an app and the files it left behind. That is the whole
product.

This is not a placeholder for ambition — it is the feature. Every macOS
cleaner starts as a good uninstaller and ends as a suite of memory optimizers
nobody asked for. RootOut will not do that.

**Already declined, and will be declined again:**

- Orphan-file scanners ("files left by apps you already deleted")
- Duplicate finders, large-file finders, disk visualizers
- Startup / login-item managers
- Auto-updaters and update checks
- A menubar extra or background helper
- Analytics, telemetry, crash reporting
- A preferences window, onboarding, or a welcome screen
- Anything that makes a network request

**Things that are welcome:**

- Leftover locations RootOut misses (with a test, and evidence of a real app
  that uses them)
- Bugs in matching — especially any case where RootOut offers to delete a file
  that does not belong to the selected app. **This is the most valuable bug
  report you can file.**
- Correctness and safety fixes in `Uninstaller`
- Accessibility, VoiceOver, keyboard navigation
- Localization
- Reducing code, not adding it

If you are unsure whether something is in scope, open an issue before writing
code. A rejected PR is worse for both of us than a two-line question.

## Before you write code

Read [CODEBASE.md](CODEBASE.md). It is short, and it explains the deletion
containment model — the part that must not be broken.

Understand the governing asymmetry: **a missed leftover leaves a stray file
on disk; a wrong match destroys someone's data.** Everything in the matching
code resolves toward the former. Patches that make matching more aggressive
need to argue their safety, not just their yield.

## Setup

Requires Xcode 16+ on an Apple Silicon Mac. No package manager, no
dependencies to install.

```bash
git clone https://github.com/TonmoyBishwas/RootOut-mac.git
cd RootOut-mac
swift test              # 30 tests, ~0.05s
./Scripts/build-app.sh  # dist/RootOut.app
open dist/RootOut.app
```

## Tests

All logic lives in `RootOutCore` and is tested there, against a real temp
directory via `FixtureDir`. The SwiftUI layer has no tests and should stay thin
enough not to need them.

Use [Swift Testing](https://developer.apple.com/documentation/testing), not
XCTest:

```swift
@Suite struct MyTests {
    @Test func doesTheThing() throws {
        let fx = try FixtureDir()
        try fx.app("Foo.app", bundleID: "com.example.foo")
        #expect(/* … */)
    }
}
```

Any change to `Uninstaller` or `LeftoverScanner` needs a test that would fail
if the change deleted a file it should not have. "It works on my Mac" is not
evidence; a fixture is.

Never write a test that touches `/Applications`, `~/Library`, or anything else
outside a `FixtureDir`. `Uninstaller(allowedRoots:)` accepts an injected root
list for exactly this reason.

## Pull requests

- One change per PR.
- `swift test` passes, and `./Scripts/build-app.sh` succeeds.
- Match the surrounding style. In particular: comments explain *why* a
  constraint exists, never *what* the next line does. If a line needs a comment
  to say what it does, rewrite the line.
- If you change behavior a user can see, update the README.
- If you change something a future contributor could plausibly undo by
  accident, add it to the "Common mistakes" list in [CLAUDE.md](CLAUDE.md).

## Reporting a safety bug

If RootOut deletes — or offers to delete — a file that does not belong to the
selected app, that is the most serious class of bug in this project. See
[SECURITY.md](SECURITY.md).

## License

By contributing you agree your work is released under the [MIT License](LICENSE).
