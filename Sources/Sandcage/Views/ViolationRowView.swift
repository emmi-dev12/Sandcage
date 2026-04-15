import SwiftUI

struct ViolationRowView: View {
    let event: ViolationEvent

    private var actionColor: Color {
        event.action == .deny ? .red : .orange
    }

    private var operationIcon: String {
        let op = event.operationType
        if op.hasPrefix("file-write") { return "pencil.slash" }
        if op.hasPrefix("file-read")  { return "doc.slash" }
        if op.hasPrefix("network")    { return "network.slash" }
        if op.hasPrefix("process")    { return "xmark.app" }
        if op.hasPrefix("mach")       { return "memorychip.fill" }
        return "exclamationmark.shield"
    }

    private var resourceText: String {
        if let path = event.deniedPath { return path }
        if let host = event.deniedHost, let port = event.deniedPort { return "\(host):\(port)" }
        if let host = event.deniedHost { return host }
        if let port = event.deniedPort { return "*:\(port)" }
        return ""
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: operationIcon)
                .font(.system(size: 13))
                .foregroundStyle(actionColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.operationType)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(actionColor)
                    Text(event.action == .deny ? "DENY" : "ALLOW+REPORT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(actionColor))
                }
                if !resourceText.isEmpty {
                    Text(resourceText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}
