import Foundation

/// Enumerates the apps RootOut is allowed to uninstall.
public struct AppInventory: Sendable {
    public static let ownBundleID = "com.tonmoybishwas.rootout"

    private let searchURLs: [URL]

    /// - Parameter searchURLs: directories to scan; defaults to /Applications and ~/Applications.
    public init(searchURLs: [URL]? = nil) {
        self.searchURLs = searchURLs ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    public func installedApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for base in searchURLs {
            apps.append(contentsOf: appBundles(in: base, depth: 2).compactMap(read))
        }
        return apps
            .filter { !$0.bundleID.hasPrefix("com.apple.") && $0.bundleID != Self.ownBundleID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// .app bundles in `base`, recursing into plain subfolders up to `depth` levels.
    private func appBundles(in base: URL, depth: Int) -> [URL] {
        guard depth > 0,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: base, includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles])
        else { return [] }

        var found: [URL] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if entry.pathExtension == "app" {
                found.append(entry)
            } else {
                found.append(contentsOf: appBundles(in: entry, depth: depth - 1))
            }
        }
        return found
    }

    private func read(bundleURL: URL) -> InstalledApp? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                  as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String
        else { return nil }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? ""
        return InstalledApp(bundleURL: bundleURL, name: name, bundleID: bundleID, version: version)
    }
}
