import SwiftUI

/// Shown at startup if /usr/bin/sandbox-exec is not found.
struct SandboxExecMissingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("sandbox-exec Not Found")
                .font(.title2.bold())

            Text("""
                Sandcage requires `/usr/bin/sandbox-exec`, which is present on macOS 13 (Ventura) and later.

                It could not be found on this system. Sandboxed launches will not work until this is resolved.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Button("Continue Anyway") {
                appState.sandboxExecMissing = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(minWidth: 460)
    }
}
