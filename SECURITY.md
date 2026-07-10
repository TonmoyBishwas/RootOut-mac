# Security

RootOut deletes files. The threat model is not "someone steals data from
RootOut" — it is "RootOut destroys data it should not have touched."

## Reporting

If you find a way to make RootOut delete something outside its containment
rules, please report it privately first via
[GitHub Security Advisories](https://github.com/TonmoyBishwas/RootOut-mac/security/advisories/new)
rather than a public issue.

Also worth reporting, at whatever level of privacy you think fits:

- Any real app for which RootOut lists a file belonging to a *different* app
- Any path that reaches `rm -rf` without passing containment
- Any way a filename can break out of the admin-removal command string

Include the app, the paths shown, and your macOS version. A screenshot of the
leftover list is usually enough.

## What RootOut does not do

- **No network access.** RootOut makes no connections, ever. No telemetry, no
  update check, no crash reporting. You can verify this: there is no networking
  code and there are no dependencies.
- **No background process.** Nothing installs, nothing persists, nothing runs
  when the app is closed.
- **No permanent deletion by default.** Everything is moved to the Trash and
  can be restored.

## The deletion model

Every path RootOut is asked to delete must pass
`Uninstaller.allowedDeletionPath` before anything touches the filesystem.
That function:

1. Folds `..` components (`standardizedFileURL`), so a path cannot climb out.
2. Resolves every **parent** directory symlink with `realpath(3)`, so a
   symlinked parent cannot smuggle a target past the check.
3. Leaves the **leaf** component unresolved, so trashing a symlink affects the
   link and never its target.
4. Requires the result to sit under one of four roots, at or below a minimum
   depth:

   | Root | Minimum depth |
   |---|---|
   | `/Applications` | 1 |
   | `~/Applications` | 1 |
   | `~/Library` | 2 |
   | `/Library` | 2 |

   The depth rule is why `~/Library/Preferences` — the folder holding every
   app's settings — can never itself be a deletion target, only its contents.

Anything that fails this check is reported to the user as a failure. It is
never deleted.

## Administrator removal

Some files are owned by `root` and cannot be moved to the Trash. For those, and
only after the user reads the list and clicks a button that says what it does,
RootOut runs a single `rm -rf` via `osascript … with administrator privileges`,
which triggers the standard macOS password prompt.

This is the only permanent deletion path in the program. It re-runs the
containment check on every path, and because the command executes as root,
each filename passes through two escaping layers — POSIX shell single-quoting
inside AppleScript string escaping — so that a filename containing `'`, `"`,
`\`, or a newline cannot inject a command. See `adminScriptEscapesHostileFilenames`
in `Tests/RootOutCoreTests/UninstallerTests.swift`.

## Code signing

RootOut is **ad-hoc signed and not notarized by Apple.** Notarization requires a
$99/year Apple Developer account, and this is free software.

The practical consequence: on first launch macOS will refuse to open it until
you right-click → Open. That warning means "Apple has not checked this app," not
"this app is known to be malicious."

If that trade is not acceptable to you, build from source — it takes one
command, and then the binary running on your Mac is one you compiled from code
you can read.
