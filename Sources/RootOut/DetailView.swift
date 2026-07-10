import SwiftUI
import AppKit
import RootOutCore

struct DetailView: View {
    @Bindable var state: AppState
    @State private var confirming = false

    var body: some View {
        ZStack {
            switch state.phase {
            case .idle:
                emptyState
            case .scanning:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for leftover files…")
                        .foregroundStyle(.secondary)
                }
            case .ready, .uninstalling:
                if let app = state.selection {
                    results(for: app)
                }
            case .done(let summary):
                doneState(summary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.trash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select an app to root out")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("RootOut finds every file the app left behind.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func doneState(_ summary: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.title3)
            if !state.failures.isEmpty {
                failuresCard
            }
        }
        .padding(24)
    }

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some items couldn’t be moved to the Trash")
                .font(.headline)
            ForEach(state.failures, id: \.url) { failure in
                Text(failure.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Remove with Administrator Privileges…") {
                Task { await state.removeFailuresWithAdmin() }
            }
        }
        .padding(16)
        .glassCard()
        .frame(maxWidth: 480)
    }

    private func results(for app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            header(for: app)
            list
        }
        .overlay(alignment: .bottom) { actionBar }
    }

    private func header(for app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                Text("\(app.bundleID)  ·  \(app.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(state.items.count) items")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var list: some View {
        List {
            ForEach(LeftoverKind.allCases, id: \.self) { kind in
                let group = state.items.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(kind.rawValue) {
                        ForEach(group) { item in
                            row(item)
                        }
                    }
                }
            }
            // Leave room for the floating action bar.
            Color.clear.frame(height: 44).listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: LeftoverItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { state.checked.contains(item.url) },
                set: { on in
                    if on { state.checked.insert(item.url) } else { state.checked.remove(item.url) }
                }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(AppState.formatBytes(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }

    /// The one colored thing on screen: total footprint + the destructive action.
    private var actionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(AppState.formatBytes(state.totalCheckedSize))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.red)
                Text("\(state.checked.count) of \(state.items.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                confirming = true
            } label: {
                Text(state.phase == .uninstalling ? "Uninstalling…" : "Uninstall")
                    .frame(minWidth: 90)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(state.checked.isEmpty || state.phase == .uninstalling)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassCapsule()
        .padding(.bottom, 16)
        .confirmationDialog(
            "Move \(state.checked.count) item\(state.checked.count == 1 ? "" : "s") to the Trash?",
            isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                Task { await state.uninstall() }
            }
        } message: {
            Text("Everything can be restored from the Trash.")
        }
    }
}
