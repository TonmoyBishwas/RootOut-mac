import SwiftUI
import RootOutCore

@main
struct RootOutApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                AppListView(state: state)
            } detail: {
                DetailView(state: state)
            }
            .frame(minWidth: 760, minHeight: 480)
            .containerBackground(.thinMaterial, for: .window)
            .task { await state.refresh() }
            .navigationTitle("RootOut")
        }
        .windowStyle(.hiddenTitleBar)
    }
}
