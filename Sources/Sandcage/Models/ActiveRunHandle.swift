import Foundation
import Combine

/// In-memory handle for a currently running sandboxed process.
/// Not persisted — created on launch, discarded on termination.
@MainActor
final class ActiveRunHandle: ObservableObject {
    let runID: UUID
    let process: Process
    @Published var liveViolations: [ViolationEvent] = []
    @Published var isRunning: Bool = true

    init(runID: UUID, process: Process) {
        self.runID = runID
        self.process = process
    }

    func kill() {
        process.terminate()
    }
}
