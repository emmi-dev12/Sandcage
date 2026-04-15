import Foundation

enum RunStatus: String, Codable {
    case running
    case completed
    case killed
    case crashed   // non-zero exit not via SIGTERM
}

struct SandboxedRun: Identifiable, Codable {
    let id: UUID
    let profileID: UUID
    /// Denormalized name — kept even if the profile is later edited or deleted
    let profileSnapshotName: String
    let appPath: String
    var appDisplayName: String
    var status: RunStatus
    let startTime: Date
    var endTime: Date?
    var exitCode: Int32?
    var violations: [ViolationEvent]
    /// True when violations were capped at 10,000 to prevent unbounded growth
    var violationsTruncated: Bool
    var stdoutLog: String
    var stderrLog: String

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var violationCount: Int { violations.count }
}
