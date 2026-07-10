import Testing
import Foundation
@testable import RootOutCore

@Suite struct UninstallerTests {
    @Test func trashesFilesAndDirectories() throws {
        let fx = try FixtureDir()
        let file = try fx.file("Apps/CoolTool.app/Contents/Info.plist")
        let dir = try fx.dir("user/Caches/com.example.cooltool")
        try fx.file("user/Caches/com.example.cooltool/data.bin")

        let result = Uninstaller(allowedRoots: [fx.root]).uninstall(items: [file, dir])
        #expect(result.failed.isEmpty)
        #expect(result.trashed.count == 2)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func missingPathReportsFailureWithoutThrowing() throws {
        let fx = try FixtureDir()
        let ghost = fx.root.appendingPathComponent("nope/ghost.txt")
        let result = Uninstaller(allowedRoots: [fx.root]).uninstall(items: [ghost])
        #expect(result.trashed.isEmpty)
        #expect(result.failed.count == 1)
    }

    @Test func refusesPathsOutsideAllowedRoots() throws {
        let fx = try FixtureDir()
        let outside = URL(fileURLWithPath: "/usr/bin/true")
        let result = Uninstaller(allowedRoots: [fx.root]).uninstall(items: [outside])
        #expect(result.trashed.isEmpty)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.reason.contains("unsafe") == true)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func defaultRootsCoverStandardLocations() {
        let roots = Uninstaller().allowedRootPaths
        #expect(roots.contains("/Applications"))
        #expect(roots.contains("/Library"))
        #expect(roots.contains { $0.hasSuffix("/Library") && $0 != "/Library" }) // ~/Library
    }

    // MARK: - Symlink and traversal containment

    @Test func trashingASymlinkNeverTouchesItsTarget() throws {
        let inside = try FixtureDir()
        let outside = try FixtureDir()
        let victim = try outside.file("precious/data.txt")
        let link = try inside.symlink("Caches/com.example.evil", to: victim.deletingLastPathComponent())

        let result = Uninstaller(allowedRoots: [inside.root]).uninstall(items: [link])
        #expect(result.trashed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: link.path)) // link gone
        #expect(FileManager.default.fileExists(atPath: victim.path)) // target intact
    }

    @Test func symlinkedParentCannotSmugglePathsOutsideRoots() throws {
        let inside = try FixtureDir()
        let outside = try FixtureDir()
        let victim = try outside.file("real/victim.txt")
        try inside.symlink("escape", to: outside.root.appendingPathComponent("real"))
        let smuggled = inside.root.appendingPathComponent("escape/victim.txt")

        let result = Uninstaller(allowedRoots: [inside.root]).uninstall(items: [smuggled])
        #expect(result.trashed.isEmpty)
        #expect(result.failed.count == 1)
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

    @Test func dotDotComponentsCannotEscapeRoots() throws {
        let fx = try FixtureDir()
        let sneaky = fx.root.appendingPathComponent("sub/../../outside.txt")
        let result = Uninstaller(allowedRoots: [fx.root]).uninstall(items: [sneaky])
        #expect(result.trashed.isEmpty)
        #expect(result.failed.count == 1)
    }

    @Test func libraryRootsRequireItemsInsideSubfolders() throws {
        let uninstaller = Uninstaller()
        // A Library subfolder itself must never be deletable…
        #expect(uninstaller.allowedDeletionPath(
            for: URL(fileURLWithPath: "/Library/LaunchDaemons")) == nil)
        // …but its children are fair game, and app bundles sit directly
        // inside /Applications.
        #expect(uninstaller.allowedDeletionPath(
            for: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.helper.plist")) != nil)
        #expect(uninstaller.allowedDeletionPath(
            for: URL(fileURLWithPath: "/Applications/Example.app")) != nil)
    }

    // MARK: - Admin removal script safety

    @Test func adminScriptEscapesHostileFilenames() throws {
        let fx = try FixtureDir()
        // A filename crafted to break out of the AppleScript string literal
        // and run its own command as root.
        let hostile = try fx.file(#"evil" & (do shell script "id") & "\n.plist"#)
        let script = Uninstaller(allowedRoots: [fx.root]).adminRemovalScript(for: [hostile])

        let expectedCommand = "/bin/rm -rf -- " + Uninstaller.shellQuoted(hostile.path)
        let expected = "do shell script \"\(Uninstaller.appleScriptEscaped(expectedCommand))\""
            + " with administrator privileges"
        #expect(script == expected)
        // The hostile quote must not survive unescaped: every `"` inside the
        // literal has to be preceded by a backslash.
        let body = script!.dropFirst("do shell script \"".count)
            .dropLast("\" with administrator privileges".count)
        var previous: Character = " "
        for char in body {
            #expect(!(char == "\"" && previous != "\\"))
            previous = char
        }
    }

    @Test func escapingHelpersHandleMetacharacters() {
        #expect(Uninstaller.shellQuoted("it's") == #"'it'\''s'"#)
        #expect(Uninstaller.appleScriptEscaped(#"a"b\c"#) == #"a\"b\\c"#)
        #expect(Uninstaller.appleScriptEscaped("line\nbreak\r") == #"line\nbreak\r"#)
    }

    @Test func adminScriptIsNilWhenNothingIsSafe() {
        let script = Uninstaller().adminRemovalScript(
            for: [URL(fileURLWithPath: "/usr/bin/true"), URL(fileURLWithPath: "/Library")])
        #expect(script == nil)
    }

    @Test func sizeSumsAllFiles() throws {
        let fx = try FixtureDir()
        try fx.file("tree/a.bin", contents: String(repeating: "a", count: 10_000))
        try fx.file("tree/sub/b.bin", contents: String(repeating: "b", count: 20_000))
        let size = SizeCalculator.size(of: fx.root.appendingPathComponent("tree"))
        #expect(size >= 30_000) // allocated size is at least the logical size
    }

    @Test func sizeOfSingleFile() throws {
        let fx = try FixtureDir()
        let file = try fx.file("single.bin", contents: String(repeating: "x", count: 5_000))
        #expect(SizeCalculator.size(of: file) >= 5_000)
    }
}
