import Foundation

enum ProfileTier: String, Codable, Hashable {
    case builtIn
    case userDefined
}

struct SandboxProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var sbplContent: String
    var tier: ProfileTier
    var createdAt: Date
    var modifiedAt: Date

    var isBuiltIn: Bool { tier == .builtIn }

    // Stable UUIDs for built-in profiles — must never change across app versions
    static let readOnlyID    = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
    static let noNetworkID   = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!
    static let fullLockdownID = UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!
}
