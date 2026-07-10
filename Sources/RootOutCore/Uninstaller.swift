import Foundation

public struct UninstallResult: Sendable {
    public struct Failure: Sendable {
        public let url: URL
        public let reason: String
    }

    public let trashed: [URL]
    public let failed: [Failure]

    public var summary: String {
        var parts = ["Moved \(trashed.count) item\(trashed.count == 1 ? "" : "s") to the Trash"]
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return parts.joined(separator: ", ")
    }
}

/// Moves an app and its leftovers to the Trash. Nothing is ever deleted
/// permanently except through the explicit admin fallback.
public struct Uninstaller: Sendable {
    struct Root: Sendable {
        let path: String
        /// Minimum number of path components an item must sit below the root.
        let minDepth: Int
    }

    let roots: [Root]
    var allowedRootPaths: [String] { roots.map(\.path) }

    /// - Parameter allowedRoots: containment whitelist for deletions;
    ///   defaults to the app folders and the two Library domains.
    public init(allowedRoots: [URL]? = nil) {
        if let allowedRoots {
            roots = allowedRoots.map { Root(path: Self.canonicalPath($0), minDepth: 1) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            // Library roots require depth ≥ 2: leftovers live inside Library
            // subfolders, and the subfolders themselves (Preferences,
            // LaunchAgents, …) must never be deletable wholesale.
            roots = [
                Root(path: Self.canonicalPath(URL(fileURLWithPath: "/Applications", isDirectory: true)), minDepth: 1),
                Root(path: Self.canonicalPath(home.appendingPathComponent("Applications", isDirectory: true)), minDepth: 1),
                Root(path: Self.canonicalPath(home.appendingPathComponent("Library", isDirectory: true)), minDepth: 2),
                Root(path: Self.canonicalPath(URL(fileURLWithPath: "/Library", isDirectory: true)), minDepth: 2),
            ]
        }
    }

    public func uninstall(items: [URL]) -> UninstallResult {
        var trashed: [URL] = []
        var failed: [UninstallResult.Failure] = []

        for item in items {
            guard let path = allowedDeletionPath(for: item) else {
                failed.append(.init(url: item, reason: "unsafe path outside app/Library folders"))
                continue
            }
            do {
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: path), resultingItemURL: nil)
                trashed.append(item)
            } catch {
                failed.append(.init(url: item, reason: error.localizedDescription))
            }
        }
        return UninstallResult(trashed: trashed, failed: failed)
    }

    /// Permanently removes root-owned paths with one admin prompt.
    /// Only call with paths the user has explicitly reviewed and confirmed.
    public func removeWithAdminPrivileges(paths: [URL]) throws {
        guard let script = adminRemovalScript(for: paths) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "RootOut", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Administrator removal was cancelled or failed"])
        }
    }

    /// Builds the osascript source for the admin removal, or nil when no
    /// path survives the containment check. The command runs as root, so
    /// every path goes through two escaping layers: shell single-quoting
    /// inside the command, then AppleScript string escaping around it —
    /// a filename containing `"` or `\` must not break out of the literal.
    func adminRemovalScript(for paths: [URL]) -> String? {
        let safe = paths.compactMap { allowedDeletionPath(for: $0) }
        guard !safe.isEmpty else { return nil }
        let command = "/bin/rm -rf -- " + safe.map(Self.shellQuoted).joined(separator: " ")
        return "do shell script \"\(Self.appleScriptEscaped(command))\" with administrator privileges"
    }

    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// The path a deletion is allowed to act on, or nil if it falls outside
    /// the allowed roots (or its parent can't be resolved). `..` components
    /// are folded and every parent symlink is resolved, so a path can't
    /// escape containment; the leaf is deliberately left unresolved so that
    /// deleting a symlink only ever affects the link, never its target.
    func allowedDeletionPath(for url: URL) -> String? {
        guard let path = Self.deletionPath(for: url) else { return nil }
        for root in roots where path.hasPrefix(root.path + "/") {
            let depth = path.dropFirst(root.path.count + 1).split(separator: "/").count
            if depth >= root.minDepth { return path }
        }
        return nil
    }

    /// Canonical parent directory plus the unresolved leaf name.
    static func deletionPath(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        let leaf = standardized.lastPathComponent
        guard !leaf.isEmpty, leaf != "/", leaf != ".", leaf != ".." else { return nil }
        let parent = standardized.deletingLastPathComponent()
        guard let parentCanonical = realPath(parent.path) else { return nil }
        return (parentCanonical == "/" ? "" : parentCanonical) + "/" + leaf
    }

    /// realpath(3): resolves every symlink component (URL canonicalization
    /// leaves the final component unresolved); nil if the path doesn't exist.
    static func realPath(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return nil }
        let bytes = buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:))
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Resolves symlinks (/var → /private/var) so root paths compare
    /// canonically; falls back to the plain path if resolution fails.
    static func canonicalPath(_ url: URL) -> String {
        realPath(url.standardizedFileURL.path) ?? url.standardizedFileURL.path
    }
}

public enum SizeCalculator {
    /// Total allocated size of a file, or recursive total for a directory.
    public static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }

        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [])
        while let child = enumerator?.nextObject() as? URL {
            if let v = try? child.resourceValues(forKeys: keys), v.isDirectory != true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
