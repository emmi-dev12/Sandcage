import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var activeRuns: [(UUID, ActiveRunHandle)] {
        appState.activeRuns.sorted { $0.key.uuidString < $1.key.uuidString }
    }

    var body: some View {
        Group {
            if activeRuns.isEmpty {
                Text("No active sandboxes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeRuns, id: \.0) { runID, handle in
                    if let run = appState.runs.first(where: { $0.id == runID }) {
                        activeRunMenuItem(run: run, handle: handle)
                    }
                }
                Divider()
                Button("Kill All") {
                    activeRuns.forEach { _, handle in handle.kill() }
                }
                .foregroundStyle(.red)
            }
        }

        Divider()

        Button("Open Sandcage") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        Divider()

        Button("Quit Sandcage") {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private func activeRunMenuItem(run: SandboxedRun, handle: ActiveRunHandle) -> some View {
        Menu {
            Text("\(run.violationCount) violation(s) so far")
                .foregroundStyle(.secondary)
            Divider()
            Button("Show Details") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
                appState.selectedRunID = run.id
            }
            Button("Kill Process", role: .destructive) {
                handle.kill()
            }
        } label: {
            Label(run.appDisplayName, systemImage: "shield.lefthalf.filled")
        }
    }
}
