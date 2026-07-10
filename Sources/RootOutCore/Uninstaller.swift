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
    let allowedRootPaths: [String]

    /// - Parameter allowedRoots: containment whitelist for deletions;
    ///   defaults to the app folders and the two Library domains.
    public init(allowedRoots: [URL]? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = allowedRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
        ]
        allowedRootPaths = roots.map(Self.canonicalPath)
    }

    public func uninstall(items: [URL]) -> UninstallResult {
        var trashed: [URL] = []
        var failed: [UninstallResult.Failure] = []

        for item in items {
            guard isAllowed(item) else {
                failed.append(.init(url: item, reason: "unsafe path outside app/Library folders"))
                continue
            }
            do {
                try FileManager.default.trashItem(at: item, resultingItemURL: nil)
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
        let safe = paths.filter(isAllowed)
        guard !safe.isEmpty else { return }
        let quoted = safe
            .map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let script = "do shell script \"/bin/rm -rf \(quoted)\" with administrator privileges"

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

    private func isAllowed(_ url: URL) -> Bool {
        let path = Self.canonicalPath(url)
        return allowedRootPaths.contains { root in
            path.hasPrefix(root + "/") && path.count > root.count + 1
        }
    }

    /// Resolves symlinks (/var → /private/var) so containment checks can't be
    /// fooled; falls back to the plain path for nonexistent files.
    static func canonicalPath(_ url: URL) -> String {
        if let canonical = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath {
            return canonical
        }
        // File may not exist (yet); canonicalize its parent instead.
        let parent = url.deletingLastPathComponent()
        if parent.path != url.path,
           let parentCanonical = try? parent.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath {
            return parentCanonical + "/" + url.lastPathComponent
        }
        return url.path
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
