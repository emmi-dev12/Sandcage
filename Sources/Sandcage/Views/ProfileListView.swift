import SwiftUI

struct ProfileListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingEditor = false
    @State private var editingProfile: SandboxProfile?

    private var builtIns: [SandboxProfile] { appState.profiles.filter(\.isBuiltIn) }
    private var userProfiles: [SandboxProfile] { appState.profiles.filter { !$0.isBuiltIn } }

    var body: some View {
        List(selection: $appState.selectedProfileID) {
            Section("Built-in") {
                ForEach(builtIns) { profile in
                    ProfileRowView(profile: profile)
                        .tag(profile.id)
                        .contextMenu {
                            Button("View Profile") { editingProfile = profile }
                        }
                }
            }

            if !userProfiles.isEmpty {
                Section("Custom") {
                    ForEach(userProfiles) { profile in
                        ProfileRowView(profile: profile)
                            .tag(profile.id)
                            .contextMenu {
                                Button("Edit Profile") { editingProfile = profile }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    appState.deleteProfile(profile)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Profiles")
        .safeAreaInset(edge: .bottom) {
            Button(action: { showingEditor = true }) {
                Label("New Profile", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(.bar)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(profile: profile)
        }
        .sheet(isPresented: $showingEditor) {
            ProfileEditorView(profile: nil)
        }
    }
}

struct ProfileRowView: View {
    let profile: SandboxProfile

    var icon: String {
        switch profile.id {
        case SandboxProfile.readOnlyID:     return "eye.slash"
        case SandboxProfile.noNetworkID:    return "network.slash"
        case SandboxProfile.fullLockdownID: return "lock.shield"
        default:                            return "shield"
        }
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                Text(profile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
        }
    }
}
