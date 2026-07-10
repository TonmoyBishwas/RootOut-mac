import SwiftUI
import AppKit
import RootOutCore

struct AppListView: View {
    @Bindable var state: AppState

    var body: some View {
        List(state.filteredApps, selection: $state.selectionID) { app in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .lineLimit(1)
                    Text(app.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .tag(app.id)
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $state.query, placement: .sidebar, prompt: "Search apps")
        .overlay {
            if state.apps.isEmpty && state.isRefreshing {
                ProgressView()
            } else if !state.apps.isEmpty && state.filteredApps.isEmpty {
                ContentUnavailableView.search(text: state.query)
            }
        }
        .safeAreaInset(edge: .bottom) { refreshBar }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }

    /// Echoes the detail pane's floating capsule so the sidebar reads as part
    /// of the same surface. Apps installed while RootOut is open appear here.
    private var refreshBar: some View {
        HStack(spacing: 10) {
            Text("\(state.apps.count) app\(state.apps.count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Button {
                Task { await state.refresh() }
            } label: {
                ZStack {
                    if state.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout.weight(.medium))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(state.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh app list (⌘R)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule()
        .padding(.bottom, 12)
        .animation(.easeOut(duration: 0.2), value: state.isRefreshing)
        .animation(.easeOut(duration: 0.2), value: state.apps.count)
    }
}
