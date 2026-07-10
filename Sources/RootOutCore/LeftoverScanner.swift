import Foundation

/// Finds the files an app has spread across the system.
///
/// Matching is deliberately conservative: a wrong match deletes someone
/// else's data, a missed match just leaves a file behind.
public struct LeftoverScanner: Sendable {
    private let userLibrary: URL
    private let localLibrary: URL

    public init(userLibrary: URL, localLibrary: URL) {
        self.userLibrary = userLibrary
        self.localLibrary = localLibrary
    }

    public init() {
        self.init(
            userLibrary: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true),
            localLibrary: URL(fileURLWithPath: "/Library", isDirectory: true))
    }

    /// App names too generic to trust for name-based matching.
    static let nameDenylist: Set<String> = [
        "app", "mac", "pro", "lite", "beta", "test", "tools", "player",
        "editor", "music", "notes", "mail", "photos",
    ]

    private struct Location {
        let path: String
        let kind: LeftoverKind
        let user: Bool
        let local: Bool
        let nameMatchable: Bool

        init(_ path: String, _ kind: LeftoverKind,
             user: Bool = true, local: Bool = false, nameMatchable: Bool = false) {
            self.path = path
            self.kind = kind
            self.user = user
            self.local = local
            self.nameMatchable = nameMatchable
        }
    }

    private static let locations: [Location] = [
        Location("Application Support", .support, local: true, nameMatchable: true),
        Location("Caches", .caches, nameMatchable: true),
        Location("Preferences", .preferences, local: true),
        Location("Containers", .containers),
        Location("Group Containers", .groupContainers),
        Location("Saved Application State", .savedState),
        Location("Logs", .logs, local: true, nameMatchable: true),
        Location("LaunchAgents", .launchItems, local: true),
        Location("LaunchDaemons", .launchItems, user: false, local: true),
        Location("HTTPStorages", .webData),
        Location("WebKit", .webData),
        Location("Cookies", .webData),
        Location("Application Scripts", .other),
    ]

    public func scan(app: InstalledApp) -> [LeftoverItem] {
        var items = [LeftoverItem(url: app.bundleURL, kind: .app)]
        let trustedName = isNameTrustworthy(app.name)

        for location in Self.locations {
            var roots: [URL] = []
            if location.user { roots.append(userLibrary.appendingPathComponent(location.path)) }
            if location.local { roots.append(localLibrary.appendingPathComponent(location.path)) }

            for root in roots {
                for entry in contents(of: root) {
                    let base = entry.lastPathComponent
                    if matchesBundleID(base, bundleID: app.bundleID)
                        || (location.nameMatchable && trustedName && isDirectory(entry)
                            && base.caseInsensitiveCompare(app.name) == .orderedSame) {
                        items.append(LeftoverItem(url: entry, kind: location.kind))
                    }
                }
            }
        }

        items.append(contentsOf: crashReports(for: app, trustedName: trustedName))
        return items
    }

    /// Exact bundle-ID match, dot-boundary prefix (com.foo.Bar.plist,
    /// com.foo.Bar.helper.plist), or the app-group form group.com.foo.Bar.
    private func matchesBundleID(_ base: String, bundleID: String) -> Bool {
        base == bundleID
            || base.hasPrefix(bundleID + ".")
            || base == "group." + bundleID
    }

    private func isNameTrustworthy(_ name: String) -> Bool {
        name.count >= 4 && !Self.nameDenylist.contains(name.lowercased())
    }

    /// Crash logs are named <ProcessName>-<date>.ips; match on an exact
    /// name prefix followed by a separator.
    private func crashReports(for app: InstalledApp, trustedName: Bool) -> [LeftoverItem] {
        guard trustedName else { return [] }
        let dir = userLibrary.appendingPathComponent("Logs/DiagnosticReports")
        return contents(of: dir).compactMap { entry in
            let base = entry.lastPathComponent
            guard ["ips", "crash", "diag", "hang"].contains(entry.pathExtension.lowercased()),
                  base.hasPrefix(app.name),
                  let separator = base.dropFirst(app.name.count).first,
                  "-_. ".contains(separator)
            else { return nil }
            return LeftoverItem(url: entry, kind: .crashReports)
        }
    }

    private func contents(of dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
