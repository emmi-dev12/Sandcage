import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var appURL: URL?
    @State private var appIcon: NSImage?
    @State private var isLaunching = false
    @State private var errorMessage: String?

    private var selectedProfile: SandboxProfile? {
        appState.profiles.first { $0.id == appState.selectedProfileID }
    }

    private var canLaunch: Bool {
        appURL != nil && selectedProfile != nil && !isLaunching
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Drop target
            dropTarget
                .onDrop(of: [.fileURL], isTargeted: $isDragging, perform: handleDrop)
                .onTapGesture(perform: openFilePicker)

            Spacer().frame(height: 20)

            // Profile badge
            profileBadge

            Spacer().frame(height: 12)

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer().frame(height: 16)

            // Actions
            HStack(spacing: 12) {
                if appURL != nil {
                    Button("Clear") {
                        appURL = nil
                        appIcon = nil
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button(action: launchApp) {
                    if isLaunching {
                        ProgressView().scaleEffect(0.75)
                            .frame(width: 140, height: 28)
                    } else {
                        Text("Launch in Sandbox")
                            .frame(width: 140, height: 28)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canLaunch)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Sandcage")
    }

    // MARK: - Subviews

    private var dropTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDragging
                              ? Color.accentColor.opacity(0.06)
                              : Color.secondary.opacity(0.04))
                )
                .frame(width: 300, height: 220)

            VStack(spacing: 14) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                }

                if let url = appURL {
                    VStack(spacing: 4) {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.title3.bold())
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 260)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("Drop an app here")
                            .font(.title3.bold())
                        Text("or click to choose")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .animation(.easeInOut(duration: 0.15), value: appURL?.path)
    }

    private var profileBadge: some View {
        Group {
            if let profile = selectedProfile {
                Label("Sandbox: **\(profile.name)**", systemImage: "shield.lefthalf.filled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Select a profile from the sidebar", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Actions

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { setApp(url: url) }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application, .unixExecutable]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an application or binary to sandbox"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            setApp(url: url)
        }
    }

    private func setApp(url: URL) {
        appURL = url
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        errorMessage = nil
    }

    private func launchApp() {
        guard let url = appURL, let profile = selectedProfile else { return }
        isLaunching = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await appState.launch(appPath: url.path, profile: profile)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLaunching = false
        }
    }
}
