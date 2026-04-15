import SwiftUI
import AppKit

/// View for creating a new profile or viewing/editing an existing one.
/// Built-in profiles are displayed read-only with an option to duplicate.
/// Pass `initialName`, `initialDescription`, `initialSBPL` to pre-seed a new profile
/// (e.g. when auto-generating from observed violations).
struct ProfileEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// nil = create new; non-nil = view/edit existing
    let profile: SandboxProfile?

    /// Pre-seed values used only when `profile == nil` (new profile creation)
    let initialName: String
    let initialDescription: String
    let initialSBPL: String

    init(profile: SandboxProfile?,
         initialName: String = "",
         initialDescription: String = "",
         initialSBPL: String = ProfileEditorView.defaultTemplate) {
        self.profile = profile
        self.initialName = initialName
        self.initialDescription = initialDescription
        self.initialSBPL = initialSBPL
    }

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var sbplContent: String = ""
    @State private var validationResult: String? = nil
    @State private var isValidating = false
    @State private var showSaveError = false

    private var isReadOnly: Bool { profile?.isBuiltIn == true }

    private var title: String {
        guard let profile else { return "New Profile" }
        return isReadOnly ? profile.name : "Edit Profile"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if isReadOnly {
                    Button("Duplicate & Edit") { duplicateProfile() }
                        .buttonStyle(.bordered)
                }
                Button("Cancel") { dismiss() }
                if !isReadOnly {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()

            Divider()

            if isReadOnly {
                Label("Built-in presets cannot be edited. Duplicate to build a custom behavioral policy.",
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.08))
            }

            // Name + description
            Form {
                TextField("Profile Name", text: $name)
                    .disabled(isReadOnly)
                TextField("Description", text: $description)
                    .disabled(isReadOnly)
            }
            .formStyle(.grouped)
            .frame(height: 110)

            Divider()

            // SBPL editor
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Sandbox Profile (SBPL)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        validateSBPL()
                    } label: {
                        if isValidating {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Label("Validate", systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isReadOnly || isValidating)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                SBPLEditorView(text: $sbplContent, isEditable: !isReadOnly)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Validation result
                if let result = validationResult {
                    HStack(spacing: 6) {
                        Image(systemName: result == "OK"
                              ? "checkmark.circle.fill"
                              : "xmark.circle.fill")
                            .foregroundStyle(result == "OK" ? .green : .red)
                        Text(result == "OK" ? "Profile syntax is valid." : result)
                            .font(.caption)
                            .foregroundStyle(result == "OK" ? .green : .red)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { loadProfile() }
    }

    // MARK: - Actions

    private func loadProfile() {
        if let profile {
            name = profile.name
            description = profile.description
            sbplContent = profile.sbplContent
        } else {
            name = initialName
            description = initialDescription
            sbplContent = initialSBPL.isEmpty ? Self.defaultTemplate : initialSBPL
        }
    }

    private func validateSBPL() {
        isValidating = true
        validationResult = nil
        let content = sbplContent
        Task.detached(priority: .userInitiated) {
            let result = ProfileManager().validateSBPL(content)
            await MainActor.run {
                validationResult = result ?? "OK"
                isValidating = false
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let existing = profile, !existing.isBuiltIn {
            var updated = existing
            updated.name = trimmedName
            updated.description = description
            updated.sbplContent = sbplContent
            // Replace in appState
            if let idx = appState.profiles.firstIndex(where: { $0.id == existing.id }) {
                appState.profiles[idx] = updated
                appState.profileManager.saveUserProfile(updated)
            }
        } else {
            let newProfile = SandboxProfile(
                id: UUID(),
                name: trimmedName,
                description: description,
                sbplContent: sbplContent,
                tier: .userDefined,
                createdAt: Date(),
                modifiedAt: Date()
            )
            appState.addProfile(newProfile)
        }
        dismiss()
    }

    private func duplicateProfile() {
        guard let profile else { return }
        let copy = SandboxProfile(
            id: UUID(),
            name: "\(profile.name) (Copy)",
            description: profile.description,
            sbplContent: profile.sbplContent,
            tier: .userDefined,
            createdAt: Date(),
            modifiedAt: Date()
        )
        appState.addProfile(copy)
        dismiss()
    }

    private static let defaultTemplate = """
    ; Sandcage: Custom Behavioral Policy
    ; Tip: run the app under a built-in preset first, observe violations,
    ; then use "Build Profile" to auto-generate rules — and refine here.

    (version 1)

    ; Start by denying everything
    (deny default)

    ; Allow reading system libraries (needed for the app to load)
    (allow file-read*
        (subpath "/usr/lib")
        (subpath "/System/Library/Frameworks")
        (subpath "/System/Library/PrivateFrameworks")
    )

    ; Allow basic process operations
    (allow process-exec)
    (allow signal (target self))
    (allow sysctl-read)

    ; Add your rules below:

    """
}

// MARK: - NSTextView wrapper

struct SBPLEditorView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }
    }
}
