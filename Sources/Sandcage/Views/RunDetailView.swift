import SwiftUI

struct RunDetailView: View {
    @EnvironmentObject var appState: AppState
    let runID: UUID

    @State private var selectedTab = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showingBuildProfile = false
    @State private var builtProfileName = ""
    @State private var builtProfileSBPL = ""

    private var run: SandboxedRun? {
        appState.runs.first { $0.id == runID }
    }

    private var handle: ActiveRunHandle? {
        appState.activeRuns[runID]
    }

    // Live violations during a run; persisted violations after
    private var violations: [ViolationEvent] {
        handle?.liveViolations ?? run?.violations ?? []
    }

    private var denyViolations: [ViolationEvent] {
        violations.filter { $0.action == .deny }
    }

    var body: some View {
        Group {
            if let run {
                VStack(spacing: 0) {
                    RunDetailHeader(run: run, handle: handle, elapsed: elapsedTime)
                    Divider()
                    tabContent(run: run)
                }
                .navigationTitle(run.appDisplayName)
                .onAppear { startTimer(run: run) }
                .onDisappear { stopTimer() }
                .onChange(of: run.status) { _ in stopTimer() }
                .sheet(isPresented: $showingBuildProfile) {
                    ProfileEditorView(
                        profile: nil,
                        initialName: builtProfileName,
                        initialDescription: "Auto-generated from observed violations. Review and tune before use.",
                        initialSBPL: builtProfileSBPL
                    )
                }
            } else {
                Text("Run not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func tabContent(run: SandboxedRun) -> some View {
        TabView(selection: $selectedTab) {
            violationsTab(run: run)
                .tabItem {
                    Label("Violations (\(violations.count))", systemImage: "exclamationmark.shield")
                }
                .tag(0)

            logTab(text: run.stdoutLog, placeholder: "(no stdout output)")
                .tabItem { Label("stdout", systemImage: "terminal") }
                .tag(1)

            logTab(text: run.stderrLog, placeholder: "(no stderr output)")
                .tabItem { Label("stderr", systemImage: "exclamationmark.triangle") }
                .tag(2)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func violationsTab(run: SandboxedRun) -> some View {
        VStack(spacing: 0) {
            if violations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: run.status == .running
                          ? "shield.lefthalf.filled"
                          : "checkmark.shield")
                        .font(.system(size: 36))
                        .foregroundStyle(run.status == .running ? .blue : .green)
                    Text(run.status == .running
                         ? "Monitoring for violations…"
                         : "No violations recorded")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if run.violationsTruncated {
                    Label("Showing first 10,000 violations. Log may be truncated.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                }

                ScrollViewReader { proxy in
                    List(violations) { event in
                        ViolationRowView(event: event)
                            .id(event.id)
                    }
                    .listStyle(.inset)
                    .onChange(of: violations.count) { _ in
                        if let last = violations.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if run.status != .running && !denyViolations.isEmpty {
                    buildProfileBanner(run: run)
                }

                violationSummary
            }
        }
    }

    private var violationSummary: some View {
        let grouped = Dictionary(grouping: violations, by: \.operationType)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }.prefix(5)

        return HStack(spacing: 16) {
            ForEach(Array(sorted), id: \.key) { op, events in
                VStack(spacing: 2) {
                    Text("\(events.count)")
                        .font(.headline.monospacedDigit())
                    Text(op.replacingOccurrences(of: "-", with: "\u{200B}-"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func buildProfileBanner(run: SandboxedRun) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Build a tighter profile")
                    .font(.caption.bold())
                Text("\(denyViolations.count) denied operations → auto-generate SBPL rules")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Build Profile") {
                let name = "\(run.appDisplayName) – Tightened"
                builtProfileName = name
                builtProfileSBPL = SBPLGenerator.generateProfile(
                    named: name,
                    violations: run.violations
                )
                showingBuildProfile = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.07))
    }

    @ViewBuilder
    private func logTab(text: String, placeholder: String) -> some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
    }

    // MARK: - Timer

    private func startTimer(run: SandboxedRun) {
        guard run.status == .running else { return }
        elapsedTime = Date().timeIntervalSince(run.startTime)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(run.startTime)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Header

struct RunDetailHeader: View {
    let run: SandboxedRun
    let handle: ActiveRunHandle?
    let elapsed: TimeInterval

    private var statusColor: Color {
        switch run.status {
        case .running:   return .blue
        case .completed: return .green
        case .killed:    return .orange
        case .crashed:   return .red
        }
    }

    private var statusLabel: String {
        switch run.status {
        case .running:   return "Running"
        case .completed: return "Completed"
        case .killed:    return "Killed"
        case .crashed:   return "Crashed (exit \(run.exitCode ?? -1))"
        }
    }

    private var elapsedText: String {
        let t = run.status == .running ? elapsed : (run.duration ?? 0)
        if t < 60 { return String(format: "%.0fs", t) }
        return String(format: "%.0fm %.0fs", t / 60, t.truncatingRemainder(dividingBy: 60))
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .overlay {
                            if run.status == .running {
                                Circle().stroke(statusColor.opacity(0.4), lineWidth: 4)
                                    .scaleEffect(1.6)
                            }
                        }
                    Text(statusLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(statusColor)
                }

                HStack(spacing: 12) {
                    Label(run.profileSnapshotName, systemImage: "shield.lefthalf.filled")
                    Label(elapsedText, systemImage: "clock")
                    Label(run.startTime.formatted(date: .omitted, time: .shortened),
                          systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if run.status == .running, let handle {
                Button(role: .destructive) {
                    handle.kill()
                } label: {
                    Label("Kill Process", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
