import Testing
import Foundation
@testable import RootOutCore

@Suite struct ScannerTests {
    /// Fixture with user/ and local/ Library trees and a scanner over them.
    private func makeScanner(_ fx: FixtureDir) -> LeftoverScanner {
        LeftoverScanner(
            userLibrary: fx.root.appendingPathComponent("user"),
            localLibrary: fx.root.appendingPathComponent("local"))
    }

    private func makeApp(_ fx: FixtureDir, name: String = "CoolTool",
                         bundleID: String = "com.example.cooltool") throws -> InstalledApp {
        let bundle = try fx.app("Apps/\(name).app", bundleID: bundleID, name: name)
        return InstalledApp(bundleURL: bundle, name: name, bundleID: bundleID, version: "1.0")
    }

    @Test func includesAppBundleFirst() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        let items = makeScanner(fx).scan(app: app)
        #expect(items.first?.url == app.bundleURL)
        #expect(items.first?.kind == .app)
    }

    @Test func findsBundleIDMatchesAcrossLocations() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        try fx.dir("user/Application Support/com.example.cooltool")
        try fx.dir("user/Caches/com.example.cooltool")
        try fx.file("user/Preferences/com.example.cooltool.plist")
        try fx.dir("user/Containers/com.example.cooltool")
        try fx.dir("user/Saved Application State/com.example.cooltool.savedState")
        try fx.file("user/LaunchAgents/com.example.cooltool.helper.plist")
        try fx.dir("user/HTTPStorages/com.example.cooltool")
        try fx.file("local/LaunchDaemons/com.example.cooltool.daemon.plist")

        let items = makeScanner(fx).scan(app: app)
        let byKind = Dictionary(grouping: items, by: \.kind)
        #expect(byKind[.support]?.count == 1)
        #expect(byKind[.caches]?.count == 1)
        #expect(byKind[.preferences]?.count == 1)
        #expect(byKind[.containers]?.count == 1)
        #expect(byKind[.savedState]?.count == 1)
        #expect(byKind[.launchItems]?.count == 2)
        #expect(byKind[.webData]?.count == 1)
    }

    @Test func findsAppNameDirectories() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        try fx.dir("user/Application Support/CoolTool")
        try fx.dir("user/Logs/cooltool") // case-insensitive
        let items = makeScanner(fx).scan(app: app)
        #expect(items.contains { $0.kind == .support && $0.url.lastPathComponent == "CoolTool" })
        #expect(items.contains { $0.kind == .logs && $0.url.lastPathComponent == "cooltool" })
    }

    @Test func nameMatchIsExactNotSubstring() throws {
        let fx = try FixtureDir()
        let notion = try makeApp(fx, name: "Notion", bundleID: "so.notion.mac")
        try fx.dir("user/Application Support/Notes")
        try fx.dir("user/Application Support/NotionHelperPro")
        let items = makeScanner(fx).scan(app: notion)
        #expect(items.count == 1) // only the .app bundle itself
    }

    @Test func shortOrCommonNamesNeverNameMatch() throws {
        let fx = try FixtureDir()
        // "Mail" is in the denylist; "Zip" is shorter than 4 chars.
        let mail = try makeApp(fx, name: "Mail", bundleID: "org.fake.mail")
        let zip = try makeApp(fx, name: "Zip", bundleID: "org.fake.zip")
        try fx.dir("user/Application Support/Mail")
        try fx.dir("user/Caches/Zip")
        #expect(makeScanner(fx).scan(app: mail).count == 1)
        #expect(makeScanner(fx).scan(app: zip).count == 1)
        // But their bundle IDs still match.
        try fx.dir("user/Caches/org.fake.mail")
        #expect(makeScanner(fx).scan(app: mail).count == 2)
    }

    @Test func bundleIDPrefixRequiresDotBoundary() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        // Same string prefix but different bundle ID — must NOT match.
        try fx.dir("user/Application Support/com.example.cooltooler")
        try fx.file("user/Preferences/com.example.cooltooler.plist")
        let items = makeScanner(fx).scan(app: app)
        #expect(items.count == 1)
    }

    @Test func neverMatchesInsideOtherContainers() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        // A file named like our bundle ID nested inside another app's container.
        try fx.file("user/Containers/com.other.app/Data/com.example.cooltool.plist")
        let items = makeScanner(fx).scan(app: app)
        #expect(items.count == 1)
    }

    @Test func findsCrashReportsByNamePrefix() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        try fx.file("user/Logs/DiagnosticReports/CoolTool-2026-07-01-120000.ips")
        try fx.file("user/Logs/DiagnosticReports/OtherApp-2026-07-01-120000.ips")
        let items = makeScanner(fx).scan(app: app)
        let crashes = items.filter { $0.kind == .crashReports }
        #expect(crashes.count == 1)
        #expect(crashes.first!.url.lastPathComponent.hasPrefix("CoolTool"))
    }

    @Test func allResultsStayInsideLibraryRoots() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        try fx.dir("user/Application Support/com.example.cooltool")
        try fx.dir("elsewhere/com.example.cooltool")
        let roots = [fx.root.appendingPathComponent("user").path,
                     fx.root.appendingPathComponent("local").path,
                     app.bundleURL.path]
        for item in makeScanner(fx).scan(app: app) {
            #expect(roots.contains { item.url.path.hasPrefix($0) },
                    "escaped item: \(item.url.path) roots: \(roots)")
        }
    }

    @Test func missingLocationsAreSkippedSilently() throws {
        let fx = try FixtureDir()
        let app = try makeApp(fx)
        // user/ and local/ don't even exist.
        let items = makeScanner(fx).scan(app: app)
        #expect(items.count == 1)
    }
}
