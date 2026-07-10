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
            if state.apps.isEmpty {
                ProgressView()
            } else if state.filteredApps.isEmpty {
                ContentUnavailableView.search(text: state.query)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }
}
