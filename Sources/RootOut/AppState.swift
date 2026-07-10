import SwiftUI
import AppKit
import RootOutCore

@MainActor @Observable
final class AppState {
    enum Phase: Equatable {
        case idle, scanning, ready, uninstalling
        case done(String)
    }

    var apps: [InstalledApp] = []
    var query = ""
    var items: [LeftoverItem] = []
    var checked: Set<URL> = []
    var phase: Phase = .idle
    var failures: [UninstallResult.Failure] = []

    var selectionID: URL? {
        didSet { if selectionID != oldValue { startScan() } }
    }

    var selection: InstalledApp? {
        apps.first { $0.id == selectionID }
    }

    var filteredApps: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var checkedItems: [LeftoverItem] { items.filter { checked.contains($0.url) } }
    var totalCheckedSize: Int64 { checkedItems.reduce(0) { $0 + $1.size } }

    private var scanTask: Task<Void, Never>?

    func refresh() async {
        apps = await Task.detached(priority: .userInitiated) {
            AppInventory().installedApps()
        }.value
    }

    private func startScan() {
        scanTask?.cancel()
        items = []
        checked = []
        failures = []
        guard let app = selection else {
            phase = .idle
            return
        }
        phase = .scanning
        scanTask = Task {
            let found = await Task.detached(priority: .userInitiated) {
                LeftoverScanner().scan(app: app).map { item in
                    var sized = item
                    sized.size = SizeCalculator.size(of: item.url)
                    return sized
                }
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                items = found
                checked = Set(found.map(\.url))
                phase = .ready
            }
        }
    }

    func uninstall() async {
        guard let app = selection, phase == .ready else { return }
        phase = .uninstalling
        let urls = checkedItems.map(\.url)
        let bundleID = app.bundleID

        let result = await Task.detached(priority: .userInitiated) {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                running.forceTerminate()
            }
            // Give the app a moment to exit before its bundle is moved.
            try? await Task.sleep(for: .milliseconds(400))
            return Uninstaller().uninstall(items: urls)
        }.value

        // Clear the selection first: its didSet runs startScan(), which resets
        // failures and phase. Assign the outcome after, so it survives.
        selectionID = nil
        failures = result.failed
        phase = .done(result.summary)
        await refresh()
    }

    func removeFailuresWithAdmin() async {
        let urls = failures.map(\.url)
        let outcome = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try Uninstaller().removeWithAdminPrivileges(paths: urls)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if outcome == nil { failures = [] }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
