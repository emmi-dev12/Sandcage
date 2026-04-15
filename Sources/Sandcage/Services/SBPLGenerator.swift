import Foundation

/// Generates SBPL (Sandbox Profile Language) rules from observed violation events.
/// Enables the "behavioral firewall builder" loop: run → observe violations → build tighter profile → re-run.
final class SBPLGenerator {

    /// Generates an SBPL profile that explicitly denies the specific operations seen in `violations`.
    /// Only deny-action violations are used; allow+report violations are ignored.
    static func generateProfile(named name: String, violations: [ViolationEvent]) -> String {
        let denies = violations.filter { $0.action == .deny }

        var fileWriteDirs:  [String] = []
        var fileReadPaths:  [String] = []
        var networkRules:   [String] = []
        var processExecs:   [String] = []
        var otherOps:       [String] = []

        var seenWriteDirs  = Set<String>()
        var seenReadPaths  = Set<String>()
        var seenHosts      = Set<String>()
        var seenExecs      = Set<String>()
        var seenOther      = Set<String>()

        for v in denies {
            let op = v.operationType

            if op.hasPrefix("file-write"), let path = v.deniedPath {
                let dir = (path as NSString).deletingLastPathComponent
                guard !dir.isEmpty, dir != "/", !seenWriteDirs.contains(dir) else { continue }
                seenWriteDirs.insert(dir)
                fileWriteDirs.append("    (subpath \"\(dir)\")")

            } else if op.hasPrefix("file-read"), let path = v.deniedPath {
                guard !seenReadPaths.contains(path) else { continue }
                seenReadPaths.insert(path)
                fileReadPaths.append("    (literal \"\(path)\")")

            } else if op.hasPrefix("network") {
                if let host = v.deniedHost {
                    guard !seenHosts.contains(host) else { continue }
                    seenHosts.insert(host)
                    if let port = v.deniedPort {
                        networkRules.append("    (remote host \"\(host)\" (port \(port)))")
                    } else {
                        networkRules.append("    (remote host \"\(host)\")")
                    }
                } else if !seenOther.contains("network*") {
                    seenOther.insert("network*")
                    otherOps.append("(deny network*)")
                }

            } else if op.hasPrefix("process-exec"), let path = v.deniedPath {
                guard !seenExecs.contains(path) else { continue }
                seenExecs.insert(path)
                processExecs.append("    (literal \"\(path)\")")

            } else {
                guard !seenOther.contains(op) else { continue }
                seenOther.insert(op)
                otherOps.append("(deny \(op))")
            }
        }

        var lines: [String] = []
        lines.append("; Sandcage: \(name)")
        lines.append("; Generated from observed violations. Review and tune before use.")
        lines.append("")
        lines.append("(version 1)")
        lines.append("(deny default)")
        lines.append("")
        lines.append("; Allow reading system libraries (required to load and run)")
        lines.append("(allow file-read*")
        lines.append("    (subpath \"/usr/lib\")")
        lines.append("    (subpath \"/usr/share\")")
        lines.append("    (subpath \"/System/Library/Frameworks\")")
        lines.append("    (subpath \"/System/Library/PrivateFrameworks\")")
        lines.append("    (subpath \"/System/Library/CoreServices\")")
        lines.append(")")
        lines.append("")
        lines.append("; Allow basic process operations")
        lines.append("(allow process-exec)")
        lines.append("(allow process-fork)")
        lines.append("(allow signal (target self))")
        lines.append("(allow sysctl-read)")
        lines.append("(allow mach-lookup)")
        lines.append("(allow ipc-posix-shm-read*)")
        lines.append("")

        if !fileWriteDirs.isEmpty {
            lines.append("; Block observed write locations")
            lines.append("(deny file-write*")
            lines.append(contentsOf: fileWriteDirs)
            lines.append(")")
            lines.append("")
        }

        if !fileReadPaths.isEmpty {
            lines.append("; Block observed read paths")
            lines.append("(deny file-read*")
            lines.append(contentsOf: fileReadPaths)
            lines.append(")")
            lines.append("")
        }

        if !networkRules.isEmpty {
            lines.append("; Block observed network destinations")
            lines.append("(deny network-outbound")
            lines.append(contentsOf: networkRules)
            lines.append(")")
            lines.append("")
        }

        if !processExecs.isEmpty {
            lines.append("; Block observed process executions")
            lines.append("(deny process-exec")
            lines.append(contentsOf: processExecs)
            lines.append(")")
            lines.append("")
        }

        lines.append(contentsOf: otherOps)

        return lines.joined(separator: "\n")
    }

    /// Returns a single SBPL rule string for one violation — for copy/paste into a profile.
    static func sbplRule(for violation: ViolationEvent) -> String {
        let op = violation.operationType

        if op.hasPrefix("file-write"), let path = violation.deniedPath {
            let dir = (path as NSString).deletingLastPathComponent
            if !dir.isEmpty && dir != "/" {
                return "(deny file-write* (subpath \"\(dir)\"))"
            }
            return "(deny \(op) (literal \"\(path)\"))"
        }

        if op.hasPrefix("file-read"), let path = violation.deniedPath {
            return "(deny file-read* (literal \"\(path)\"))"
        }

        if op.hasPrefix("network") {
            if let host = violation.deniedHost, let port = violation.deniedPort {
                return "(deny network-outbound (remote host \"\(host)\" (port \(port))))"
            }
            if let host = violation.deniedHost {
                return "(deny network-outbound (remote host \"\(host)\"))"
            }
            return "(deny network*)"
        }

        if op.hasPrefix("process-exec"), let path = violation.deniedPath {
            return "(deny process-exec (literal \"\(path)\"))"
        }

        return "(deny \(op))"
    }
}
