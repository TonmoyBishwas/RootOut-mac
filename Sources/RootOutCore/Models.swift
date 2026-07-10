import Foundation

/// An application discovered on disk that RootOut can uninstall.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { bundleURL }
    public let bundleURL: URL
    public let name: String
    public let bundleID: String
    public let version: String

    public init(bundleURL: URL, name: String, bundleID: String, version: String) {
        self.bundleURL = bundleURL
        self.name = name
        self.bundleID = bundleID
        self.version = version
    }
}

/// Where a leftover file comes from, used to group scan results.
public enum LeftoverKind: String, CaseIterable, Sendable {
    case app = "Application"
    case support = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case savedState = "Saved State"
    case logs = "Logs"
    case launchItems = "Launch Items"
    case webData = "Web Data"
    case crashReports = "Crash Reports"
    case other = "Other"
}

/// A file or directory that belongs to an app, found by the scanner.
public struct LeftoverItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let kind: LeftoverKind
    public var size: Int64

    public init(url: URL, kind: LeftoverKind, size: Int64 = 0) {
        self.url = url
        self.kind = kind
        self.size = size
    }
}
