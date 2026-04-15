import Foundation

/// Monitors the system log for sandbox violations from a specific PID.
/// Start it *before* launching the sandboxed process to avoid missing early events.
actor LogMonitor {
    private var process: Process?
    private var targetPID: Int32?
    private var pendingLines: [String] = []
    private var onViolation: ((ViolationEvent) -> Void)?
    private var runID: UUID?
    private var buffer = Data()

    // Parses: deny(1) file-write-create /var/folders/...
    //         allow(1) network-outbound *:443
    private static let violationPattern = try! NSRegularExpression(
        pattern: #"(deny|allow)\(\d+\)\s+(\S+)\s*(.*)"#
    )

    private static let logDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [
            .withFullDate, .withTime, .withDashSeparatorInDate,
            .withColonSeparatorInTime, .withFractionalSeconds, .withTimeZone
        ]
        return f
    }()

    // MARK: - Public API

    /// Start streaming system log entries for `com.apple.sandbox`.
    /// Call this before launching the sandboxed process.
    func start(runID: UUID, onViolation: @escaping (ViolationEvent) -> Void) throws {
        self.runID = runID
        self.onViolation = onViolation

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        proc.arguments = [
            "stream",
            "--predicate", #"subsystem == "com.apple.sandbox""#,
            "--style", "ndjson",
            "--level", "debug"
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        self.process = proc
        try proc.run()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.processData(data) }
        }
    }

    /// Set the PID to filter on. Events before this call are buffered and replayed.
    func setPID(_ pid: Int32) {
        targetPID = pid
        let buffered = pendingLines
        pendingLines = []
        for line in buffered {
            processLogLine(line)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        onViolation = nil
    }

    // MARK: - Private

    private func processData(_ data: Data) {
        buffer.append(data)
        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
            buffer = Data(buffer[newlineRange.upperBound...])
            if let line = String(data: lineData, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if targetPID == nil {
                    pendingLines.append(trimmed)
                } else {
                    processLogLine(trimmed)
                }
            }
        }
    }

    private func processLogLine(_ line: String) {
        guard let runID, let pid = targetPID else { return }

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Filter by PID
        let logPID: Int32
        if let p = json["processID"] as? Int32 {
            logPID = p
        } else if let p = json["processID"] as? Int {
            logPID = Int32(p)
        } else {
            return
        }
        guard logPID == pid else { return }

        guard let eventMessage = json["eventMessage"] as? String else { return }

        let timestamp: Date
        if let ts = json["timestamp"] as? String {
            timestamp = Self.logDateFormatter.date(from: ts) ?? Date()
        } else {
            timestamp = Date()
        }

        if let event = parseViolation(
            from: eventMessage,
            timestamp: timestamp,
            runID: runID,
            rawLine: line
        ) {
            onViolation?(event)
        }
    }

    private func parseViolation(
        from message: String,
        timestamp: Date,
        runID: UUID,
        rawLine: String
    ) -> ViolationEvent? {
        let nsRange = NSRange(message.startIndex..., in: message)
        guard let match = Self.violationPattern.firstMatch(in: message, range: nsRange) else {
            return nil
        }

        func capture(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: message) else { return nil }
            let s = String(message[r])
            return s.isEmpty ? nil : s
        }

        guard let actionStr = capture(1),
              let operationType = capture(2) else { return nil }

        let action: SandboxAction = actionStr == "allow" ? .allow : .deny
        let resource = capture(3)?.trimmingCharacters(in: .whitespaces)

        var deniedPath: String?
        var deniedHost: String?
        var deniedPort: Int?

        if let resource, !resource.isEmpty {
            if operationType.hasPrefix("network") || operationType == "system-socket" {
                // Format: host:port or *:443
                if let colonIdx = resource.lastIndex(of: ":") {
                    let hostPart = String(resource[resource.startIndex..<colonIdx])
                    let portPart = String(resource[resource.index(after: colonIdx)...])
                    deniedHost = hostPart == "*" ? nil : hostPart
                    deniedPort = Int(portPart)
                } else {
                    deniedHost = resource
                }
            } else {
                deniedPath = resource
            }
        }

        return ViolationEvent(
            id: UUID(),
            runID: runID,
            timestamp: timestamp,
            operationType: operationType,
            deniedPath: deniedPath,
            deniedHost: deniedHost,
            deniedPort: deniedPort,
            action: action,
            rawLogLine: rawLine
        )
    }
}
