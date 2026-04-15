import Foundation

final class ProfileManager {
    private let userProfilesDirectory: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        userProfilesDirectory = appSupport
            .appendingPathComponent("Sandcage/Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: userProfilesDirectory,
            withIntermediateDirectories: true
        )
    }

    func loadAllProfiles() -> [SandboxProfile] {
        var all = loadBuiltInProfiles()
        all.append(contentsOf: loadUserProfiles())
        return all
    }

    // MARK: - Built-ins

    private static let builtInMetadata: [(id: UUID, name: String, description: String, filename: String)] = [
        (SandboxProfile.readOnlyID,
         "Read Only",
         "Observe read behaviour. Blocks all writes, network, and child processes.",
         "read-only"),
        (SandboxProfile.noNetworkID,
         "No Network",
         "Observe filesystem and process activity. All network access blocked.",
         "no-network"),
        (SandboxProfile.fullLockdownID,
         "Full Lockdown",
         "Strictest preset. Isolated temp dir only — observe what the app tries to escape.",
         "full-lockdown"),
    ]

    private func loadBuiltInProfiles() -> [SandboxProfile] {
        Self.builtInMetadata.compactMap { item in
            guard let url = Bundle.module.url(
                forResource: item.filename,
                withExtension: "sb",
                subdirectory: "Profiles"
            ), let content = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            return SandboxProfile(
                id: item.id,
                name: item.name,
                description: item.description,
                sbplContent: content,
                tier: .builtIn,
                createdAt: Date(timeIntervalSince1970: 0),
                modifiedAt: Date(timeIntervalSince1970: 0)
            )
        }
    }

    // MARK: - User Profiles

    private func loadUserProfiles() -> [SandboxProfile] {
        guard let urls = try? FileManager.default
            .contentsOfDirectory(at: userProfilesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SandboxProfile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SandboxProfile.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func saveUserProfile(_ profile: SandboxProfile) {
        guard !profile.isBuiltIn else { return }
        let url = userProfilesDirectory.appendingPathComponent("\(profile.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func deleteUserProfile(_ profile: SandboxProfile) {
        guard !profile.isBuiltIn else { return }
        let url = userProfilesDirectory.appendingPathComponent("\(profile.id).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Validation

    /// Validates SBPL syntax using `sandbox-exec -n`.
    /// Returns nil on success, or an error string on failure.
    func validateSBPL(_ sbpl: String) -> String? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandcage-validate-\(UUID().uuidString).sb")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard (try? sbpl.write(to: tempURL, atomically: true, encoding: .utf8)) != nil else {
            return "Failed to write temporary profile file"
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        proc.arguments = ["-n", "-f", tempURL.path, "/bin/true"]

        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return "sandbox-exec unavailable: \(error.localizedDescription)"
        }

        guard proc.terminationStatus != 0 else { return nil }

        let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: errorData, encoding: .utf8) ?? "Unknown syntax error"
        return msg.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
