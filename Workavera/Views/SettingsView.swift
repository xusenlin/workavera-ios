import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Form {
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
                placeholderRow(title: "Model Configurations", icon: "sparkles")
                placeholderRow(title: "Model Sharing", icon: "square.and.arrow.up")
                placeholderRow(title: "API Keys", icon: "key")
            } header: {
                Text("Large Language Model")
            } footer: {
                Text("Add at least one model configuration to use Chat and AI summaries.")
            }

            Section {
                placeholderRow(title: "Memory Toggle", icon: "brain.head.profile")
                placeholderRow(title: "Saved Memories", icon: "archivebox")
            } header: {
                Text("Memory")
            } footer: {
                Text("Reuse facts and preferences you allow across chat sessions. Off by default.")
            }

            Section("Appearance") {
                Picker(selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label)
                            .tag(appearance.rawValue)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
            }

            Section("Account") {
                LabeledContent {
                    Text(auth.user?.email ?? "")
                } label: {
                    Label("Email", systemImage: "envelope")
                }
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent {
                    Text(appVersion)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
                Link(destination: URL(string: "https://github.com/xusenlin/workavera")!) {
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
    }

    /// 从 Bundle 读取版本号，与工程配置 MARKETING_VERSION 保持单一来源。
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }

    private func placeholderRow(title: String, icon: String) -> some View {
        LabeledContent {
            Text("In development")
                .foregroundStyle(.tertiary)
        } label: {
            Label(title, systemImage: icon)
        }
    }
}
