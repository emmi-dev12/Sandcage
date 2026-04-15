import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            ProfileListView()
        } content: {
            DropZoneView()
        } detail: {
            if let runID = appState.selectedRunID {
                RunDetailView(runID: runID)
            } else {
                RecentRunsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 920, minHeight: 600)
        .sheet(isPresented: $appState.sandboxExecMissing) {
            SandboxExecMissingView()
        }
    }
}
