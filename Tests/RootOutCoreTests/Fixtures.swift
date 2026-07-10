import Foundation

/// Creates a throwaway directory tree for filesystem tests and removes it on deinit.
final class FixtureDir {
    let root: URL

    init() throws {
        // Canonicalize so fixture paths (/var/folders/…) compare equal to the
        // /private/var/folders/… URLs that contentsOfDirectory returns.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RootOutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let canonical = try tmp.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath!
        root = URL(fileURLWithPath: canonical, isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates a directory (and intermediates) under the fixture root.
    @discardableResult
    func dir(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Creates a file (and intermediate dirs) under the fixture root.
    @discardableResult
    func file(_ path: String, contents: String = "x") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    /// Creates a minimal .app bundle with an Info.plist under the fixture root.
    @discardableResult
    func app(_ path: String, bundleID: String, name: String? = nil, version: String = "1.0") throws -> URL {
        let bundle = root.appendingPathComponent(path, isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": version,
        ]
        if let name { plist["CFBundleName"] = name }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
}
