import Testing
import Foundation
@testable import RootOutCore

@Suite struct AppInventoryTests {
    @Test func findsAppWithMetadata() throws {
        let fx = try FixtureDir()
        try fx.app("Apps/CoolTool.app", bundleID: "com.example.cooltool", name: "CoolTool", version: "2.1")
        let apps = AppInventory(searchURLs: [fx.root.appendingPathComponent("Apps")]).installedApps()
        #expect(apps.count == 1)
        #expect(apps.first?.name == "CoolTool")
        #expect(apps.first?.bundleID == "com.example.cooltool")
        #expect(apps.first?.version == "2.1")
    }

    @Test func excludesAppleApps() throws {
        let fx = try FixtureDir()
        try fx.app("Apps/Safari.app", bundleID: "com.apple.Safari")
        try fx.app("Apps/Other.app", bundleID: "org.other.tool")
        let apps = AppInventory(searchURLs: [fx.root.appendingPathComponent("Apps")]).installedApps()
        #expect(apps.map(\.bundleID) == ["org.other.tool"])
    }

    @Test func excludesItself() throws {
        let fx = try FixtureDir()
        try fx.app("Apps/RootOut.app", bundleID: AppInventory.ownBundleID)
        let apps = AppInventory(searchURLs: [fx.root.appendingPathComponent("Apps")]).installedApps()
        #expect(apps.isEmpty)
    }

    @Test func skipsBundlesWithoutInfoPlist() throws {
        let fx = try FixtureDir()
        try fx.dir("Apps/Broken.app/Contents")
        let apps = AppInventory(searchURLs: [fx.root.appendingPathComponent("Apps")]).installedApps()
        #expect(apps.isEmpty)
    }

    @Test func findsAppsOneLevelDeep() throws {
        let fx = try FixtureDir()
        try fx.app("Apps/Utilities/Nested.app", bundleID: "com.example.nested")
        let apps = AppInventory(searchURLs: [fx.root.appendingPathComponent("Apps")]).installedApps()
        #expect(apps.map(\.bundleID) == ["com.example.nested"])
    }

    @Test func usesFilenameWhenNoBundleName() throws {
        let fx = try FixtureDir()
        try fx.app("Apps/Plain.app", bundleID: "com.example.plain", name: nil)
        let apps = AppInventory(searchURLs: [fx.root.appendingPathComponent("Apps")]).installedApps()
        #expect(apps.first?.name == "Plain")
    }

    /// Backs the sidebar's refresh button: nothing is memoized, so an app
    /// installed while RootOut is open shows up on the next scan.
    @Test func rescanSeesAppInstalledAfterFirstScan() throws {
        let fx = try FixtureDir()
        let inventory = AppInventory(searchURLs: [fx.root])

        try fx.app("Before.app", bundleID: "com.example.before")
        #expect(inventory.installedApps().map(\.name) == ["Before"])

        try fx.app("After.app", bundleID: "com.example.after")
        #expect(inventory.installedApps().map(\.name) == ["After", "Before"])
    }
}
