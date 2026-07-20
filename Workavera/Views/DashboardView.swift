import SwiftUI

/// 工作概览：问候语使用真实用户信息，统计数字为占位。
struct DashboardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications
    var onNavigate: ((AppSection) -> Void)? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greetingCard

                LazyVGrid(columns: columns, spacing: 14) {
                    StatCard(title: "Active Projects", icon: "rectangle.split.3x1")
                    StatCard(title: "Open Tasks", icon: "checklist")
                    StatCard(title: "Next 7 Days", icon: "calendar")
                    StatCard(title: "Unread Reading", icon: "book")
                }

                quickLinks
            }
            .padding(20)
        }
        .scrollBounceBehavior(.always)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .refreshable {
            await notifications.refresh(using: auth)
        }
    }

    private var greetingCard: some View {
        HStack(spacing: 16) {
            AvatarView(url: auth.avatarURL, name: auth.user?.displayName ?? "?", size: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(greetingText)
                    .font(.title3.bold())
                HStack(spacing: 8) {
                    StatusBadge(status: auth.user?.status ?? .offline)
                    if let title = auth.user?.title {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salutation: String = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return "\(salutation), \(auth.user?.displayName ?? "")"
    }

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array([AppSection.chat, .board, .calendar, .reading].enumerated()), id: \.element) { index, section in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 54)
                    }
                    Button {
                        onNavigate?(section)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                            Text(section.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}

private struct StatCard: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: Circle())

            Text("—")
                .font(.system(size: 28, weight: .bold))

            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
