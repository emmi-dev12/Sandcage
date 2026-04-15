import SwiftUI

struct RecentRunsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.runs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No runs yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Drop an app on the center panel to get started.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.runs, selection: $appState.selectedRunID) { run in
                    RunSummaryRow(run: run)
                        .tag(run.id)
                        .contextMenu {
                            Button("View Details") { appState.selectedRunID = run.id }
                            Divider()
                            Button("Delete", role: .destructive) { appState.deleteRun(run) }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Run History")
    }
}

struct RunSummaryRow: View {
    let run: SandboxedRun
    @EnvironmentObject var appState: AppState

    private var statusColor: Color {
        switch run.status {
        case .running:   return .blue
        case .completed: return .green
        case .killed:    return .orange
        case .crashed:   return .red
        }
    }

    private var statusIcon: String {
        switch run.status {
        case .running:   return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .killed:    return "stop.circle.fill"
        case .crashed:   return "xmark.circle.fill"
        }
    }

    private var durationText: String {
        if run.status == .running {
            return "Running…"
        }
        guard let d = run.duration else { return "" }
        if d < 60 { return String(format: "%.0fs", d) }
        return String(format: "%.0fm %.0fs", d / 60, d.truncatingRemainder(dividingBy: 60))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.appDisplayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(run.profileSnapshotName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(run.startTime, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if run.violationCount > 0 {
                    Text("\(run.violationCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                }
                Text(durationText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
