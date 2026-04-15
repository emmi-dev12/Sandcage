import Foundation

enum SandboxAction: String, Codable, CaseIterable {
    case deny
    case allow  // allow + report: permitted but logged
}

struct ViolationEvent: Identifiable, Codable {
    let id: UUID
    let runID: UUID
    let timestamp: Date
    /// e.g. "file-write-create", "network-outbound", "process-exec"
    let operationType: String
    let deniedPath: String?
    let deniedHost: String?
    let deniedPort: Int?
    let action: SandboxAction
    /// Original log line kept for debugging and export
    let rawLogLine: String
}
