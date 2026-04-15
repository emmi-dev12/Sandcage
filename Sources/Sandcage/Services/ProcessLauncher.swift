import Foundation
import AppKit

enum LaunchError: LocalizedError {
    case sandboxExecNotFound
    case invalidBundle(String)
    case profileWriteFailed
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .sandboxExecNotFound:
            return "sandbox-exec not found. Sandcage requires macOS 13 or later with /usr/bin/sandbox-exec present."
        case .invalidBundle(let path):
            return "Could not resolve executable inside bundle at: \(path)"
        case .profileWriteFailed:
            return "Failed to write sandbox profile to a temporary file."
        case .launchFailed(let err):
            return "Process launch failed: \(err.localizedDescription)"
        }
    }
}

final class ProcessLauncher {
    static let sandboxExecPath = "/usr/bin/sandbox-exec"

    static func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: sandboxExecPath)
    }

    /// Resolves the Mach-O binary path from a .app bundle or returns the path unchanged.
    static func resolveBinary(for path: String) throws -> String {
        guard path.hasSuffix(".app") else { return path }
        guard let bundle = Bundle(path: path),
              let execPath = bundle.executablePath else {
            throw LaunchError.invalidBundle(path)
        }
        return execPath
    }

    // MARK: - Launch

    /// Launches the app at `appPath` under `profile`'s sandbox.
    /// - Returns the `Process` object for the sandboxed binary.
    @MainActor
    func launch(
        appPath: String,
        profile: SandboxProfile,
        onViolation: @escaping @MainActor (ViolationEvent) -> Void,
        onStdout: @escaping @MainActor (String) -> Void,
        onStderr: @escaping @MainActor (String) -> Void,
        onTermination: @escaping @MainActor (Int32) -> Void
    ) async throws -> Process {
        guard ProcessLauncher.isAvailable() else {
            throw LaunchError.sandboxExecNotFound
        }

        let binaryPath = try ProcessLauncher.resolveBinary(for: appPath)
        let runToken = UUID().uuidString

        // Write profile SBPL to a temp file
        let tempProfileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandcage-profile-\(runToken).sb")
        guard (try? profile.sbplContent.write(to: tempProfileURL, atomically: true, encoding: .utf8)) != nil else {
            throw LaunchError.profileWriteFailed
        }

        // Build arguments: sandbox-exec -f <profile> [-D KEY=VAL ...] <binary>
        var arguments = ["-f", tempProfileURL.path]

        if profile.id == SandboxProfile.fullLockdownID {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("sandcage-run-\(runToken)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            arguments += [
                "-D", "APP_BUNDLE_PATH=\(appPath)",
                "-D", "APP_EXECUTABLE_PATH=\(binaryPath)",
                "-D", "SANDBOX_TMP_DIR=\(tmpDir.path)"
            ]
        }

        arguments.append(binaryPath)

        // Start LogMonitor BEFORE launching so we don't miss startup violations
        let logMonitor = LogMonitor()
        let runID = UUID()
        try await logMonitor.start(runID: runID) { violation in
            Task { @MainActor in onViolation(violation) }
        }

        // Configure the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessLauncher.sandboxExecPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in onStdout(text) }
        }

        // Stream stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in onStderr(text) }
        }

        process.terminationHandler = { proc in
            Task {
                // Brief drain window so late-arriving log events are captured
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await logMonitor.stop()
                // Clean up temp files
                try? FileManager.default.removeItem(at: tempProfileURL)
                let code = proc.terminationStatus
                Task { @MainActor in onTermination(code) }
            }
        }

        do {
            try process.run()
        } catch {
            await logMonitor.stop()
            try? FileManager.default.removeItem(at: tempProfileURL)
            throw LaunchError.launchFailed(error)
        }

        // Now that we have a PID, tell the monitor what to filter on
        await logMonitor.setPID(process.processIdentifier)

        return process
    }
}
