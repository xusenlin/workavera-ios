import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var errorMessage: String?
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var isDeletingAccount = false

    var body: some View {
        Form {
            if let warningMessage {
                InlineErrorListSection(
                    message: warningMessage,
                    actionTitle: errorMessage == nil ? "Retry" : "Dismiss"
                ) {
                    if errorMessage != nil {
                        errorMessage = nil
                    } else {
                        Task { await auth.reloadPreferences() }
                    }
                }
            }

            Section("Server") {
                LabeledContent {
                    Text(auth.serverAddress)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } label: {
                    Label("Address", systemImage: "server.rack")
                }
            }

            Section {
                NavigationLink {
                    ModelConfigurationsView()
                } label: {
                    Label("Model Configurations", systemImage: "sparkles")
                }
                NavigationLink {
                    ModelSharingView()
                } label: {
                    Label("Model Sharing", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Large Language Model")
            } footer: {
                Text("Add at least one model configuration to use Chat and AI summaries.")
            }

            Section {
                NavigationLink {
                    APIKeysView()
                } label: {
                    Label("API Keys", systemImage: "key")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Connect third-party MCP clients to your Workavera tools.")
            }

            Section {
                Toggle(isOn: memoryEnabledBinding) {
                    Label("Use Chat Memory", systemImage: "brain.head.profile")
                }
                Toggle(isOn: memoryAutoCaptureBinding) {
                    Label("Automatic Capture", systemImage: "wand.and.stars")
                }
                .disabled(!auth.memoryEnabled)
                NavigationLink {
                    SavedMemoriesView()
                } label: {
                    Label("Saved Memories", systemImage: "archivebox")
                }
            } header: {
                Text("Memory")
            } footer: {
                Text("Reuse facts and preferences you allow across chat sessions. Off by default.")
            }

            Section("Appearance") {
                Picker(selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label)
                            .tag(appearance)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
            }

            Section {
                LabeledContent {
                    Text(auth.user?.email ?? "")
                } label: {
                    Label("Email", systemImage: "envelope")
                }
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                Button(role: .destructive) {
                    confirmDeleteAccount = true
                } label: {
                    HStack {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundStyle(.red)
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeletingAccount)
            } header: {
                Text("Account")
            } footer: {
                Text("Deletes your account and signs you out on every device. You won't be able to sign back in, and this can't be undone from the app.")
            }

            Section("About") {
                LabeledContent {
                    Text(appVersion)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
                Link(destination: AppLinks.privacyPolicy) {
                    HStack {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Link(destination: AppLinks.repository) {
                    HStack {
                        Label("GitHub", systemImage: "link")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("xusenlin/workavera")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await auth.reloadPreferences()
        }
        .alert(
            "Sign out of Workavera?",
            isPresented: $confirmSignOut
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                auth.logout()
            }
        } message: {
            Text("Your session will be removed from this device.")
        }
        .alert(
            "Delete your account?",
            isPresented: $confirmDeleteAccount
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Your account will be deleted and you'll be signed out on every device. You won't be able to sign back in, and this can't be undone from the app.")
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await auth.deleteAccount()
                // On success the store transitions to the logged-out phase and
                // this view is torn down, so no further UI work is needed here.
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    /// 从 Bundle 读取版本号，与工程配置 MARKETING_VERSION 保持单一来源。
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { auth.appearance },
            set: { appearance in
                Task {
                    do {
                        try await auth.updateAppearance(appearance)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var memoryEnabledBinding: Binding<Bool> {
        Binding(
            get: { auth.memoryEnabled },
            set: { enabled in
                Task {
                    do {
                        try await auth.updateMemoryEnabled(enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var memoryAutoCaptureBinding: Binding<Bool> {
        Binding(
            get: { auth.memoryAutoCapture },
            set: { enabled in
                Task {
                    do {
                        try await auth.updateMemoryAutoCapture(enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var warningMessage: String? {
        errorMessage ?? auth.preferencesMessage
    }
}
