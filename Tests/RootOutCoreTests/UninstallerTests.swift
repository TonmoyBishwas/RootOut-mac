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
