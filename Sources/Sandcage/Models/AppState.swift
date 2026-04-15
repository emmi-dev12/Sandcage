import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [SandboxProfile] = []
    @Published var runs: [SandboxedRun] = []
    @Published var activeRuns: [UUID: ActiveRunHandle] = [:]
    @Published var selectedProfileID: UUID?
    @Published var selectedRunID: UUID?
    @Published var sandboxExecMissing: Bool = false

    let profileManager: ProfileManager
    let persistenceStore: PersistenceStore

    init() {
        self.profileManager = ProfileManager()
        self.persistenceStore = PersistenceStore()
        self.profiles = profileManager.loadAllProfiles()
        self.runs = (try? persistenceStore.loadAllRuns()) ?? []
        self.selectedProfileID = profiles.first?.id
        self.sandboxExecMissing = !ProcessLauncher.isAvailable()
    }

    // MARK: - Run Management

    func addRun(_ run: SandboxedRun) {
        runs.insert(run, at: 0)
        try? persistenceStore.saveRun(run)
    }

    func updateRun(_ run: SandboxedRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        }
        try? persistenceStore.saveRun(run)
    }

    func deleteRun(_ run: SandboxedRun) {
        runs.removeAll { $0.id == run.id }
        try? persistenceStore.deleteRun(run)
    }

    // MARK: - Profile Management

    func addProfile(_ profile: SandboxProfile) {
        profiles.append(profile)
        profileManager.saveUserProfile(profile)
    }

    func deleteProfile(_ profile: SandboxProfile) {
        guard !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == profile.id }
        profileManager.deleteUserProfile(profile)
    }

    // MARK: - Launching

    func launch(appPath: String, profile: SandboxProfile) async throws {
        let runID = UUID()
        let displayName = URL(fileURLWithPath: appPath)
            .deletingPathExtension()
            .lastPathComponent

        var run = SandboxedRun(
            id: runID,
            profileID: profile.id,
            profileSnapshotName: profile.name,
            appPath: appPath,
            appDisplayName: displayName,
            status: .running,
            startTime: Date(),
            endTime: nil,
            exitCode: nil,
            violations: [],
            violationsTruncated: false,
            stdoutLog: "",
            stderrLog: ""
        )

        addRun(run)
        selectedRunID = runID

        let launcher = ProcessLauncher()

        let process = try await launcher.launch(
            appPath: appPath,
            profile: profile,
            onViolation: { [weak self] violation in
                guard let self else { return }
                guard let idx = self.runs.firstIndex(where: { $0.id == runID }) else { return }
                if self.runs[idx].violations.count < 10_000 {
                    self.runs[idx].violations.append(violation)
                } else {
                    self.runs[idx].violationsTruncated = true
                }
                try? self.persistenceStore.saveRun(self.runs[idx])
                self.activeRuns[runID]?.liveViolations.append(violation)
            },
            onStdout: { [weak self] text in
                guard let self else { return }
                guard let idx = self.runs.firstIndex(where: { $0.id == runID }) else { return }
                self.runs[idx].stdoutLog += text
            },
            onStderr: { [weak self] text in
                guard let self else { return }
                guard let idx = self.runs.firstIndex(where: { $0.id == runID }) else { return }
                self.runs[idx].stderrLog += text
            },
            onTermination: { [weak self] exitCode in
                guard let self else { return }
                self.activeRuns.removeValue(forKey: runID)
                guard let idx = self.runs.firstIndex(where: { $0.id == runID }) else { return }
                if exitCode == 0 {
                    self.runs[idx].status = .completed
                } else if exitCode == 15 { // SIGTERM
                    self.runs[idx].status = .killed
                } else {
                    self.runs[idx].status = .crashed
                }
                self.runs[idx].endTime = Date()
                self.runs[idx].exitCode = exitCode
                try? self.persistenceStore.saveRun(self.runs[idx])
            }
        )

        let handle = ActiveRunHandle(runID: runID, process: process)
        activeRuns[runID] = handle
    }
}
