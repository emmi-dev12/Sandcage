import Foundation

final class PersistenceStore {
    private let runsDirectory: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        runsDirectory = appSupport
            .appendingPathComponent("Sandcage/Runs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: runsDirectory,
            withIntermediateDirectories: true
        )
        cleanUpStaleTempFiles()
    }

    // MARK: - Runs

    func saveRun(_ run: SandboxedRun) throws {
        let url = runsDirectory.appendingPathComponent("\(run.id).json")
        let data = try encoder.encode(run)
        try data.write(to: url, options: .atomic)
    }

    func loadAllRuns() throws -> [SandboxedRun] {
        guard let urls = try? FileManager.default
            .contentsOfDirectory(at: runsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SandboxedRun? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SandboxedRun.self, from: data)
            }
            .sorted { $0.startTime > $1.startTime }
    }

    func deleteRun(_ run: SandboxedRun) throws {
        let url = runsDirectory.appendingPathComponent("\(run.id).json")
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Temp File Cleanup

    /// Cleans up any sandcage-profile-*.sb files left behind by a previous crash.
    private func cleanUpStaleTempFiles() {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("sandcage-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
