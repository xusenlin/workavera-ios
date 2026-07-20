import SwiftUI

/// 个人资料页：头像、姓名、状态均来自后端真实数据，状态可切换并写回后端。
struct ProfileView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    AvatarView(url: auth.avatarURL, name: auth.user?.displayName ?? "?", size: 96)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill((auth.user?.status ?? .offline).color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(Color(.systemGroupedBackground), lineWidth: 3.5)
                                )
                                .offset(x: -2, y: -2)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                    VStack(spacing: 4) {
                        Text(auth.user?.displayName ?? "")
                            .font(.title2.bold())
                        if let title = auth.user?.title {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(auth.user?.email ?? "")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section("Status") {
                Picker("My Status", selection: statusBinding) {
                    ForEach(UserStatus.allCases) { status in
                        HStack {
                            StatusDot(status: status)
                            Text(status.label)
                        }
                        .tag(status)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Details") {
                LabeledContent("Phone", value: auth.user?.phone ?? "Not set")
                LabeledContent("Title", value: auth.user?.title ?? "Not set")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bio")
                    Text(auth.user?.bio ?? "Not set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account") {
                LabeledContent("User ID", value: auth.user?.id ?? "")
                LabeledContent("Joined", value: String((auth.user?.created ?? "").prefix(10)))
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 选择新状态后立即写回后端。
    private var statusBinding: Binding<UserStatus> {
        Binding(
            get: { auth.user?.status ?? .online },
            set: { newValue in
                Task { await auth.updateStatus(newValue) }
            }
        )
    }
}
