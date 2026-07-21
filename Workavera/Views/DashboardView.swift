import SwiftUI

/// 工作概览：统计口径与 Web 仪表盘保持一致。
struct DashboardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications
    @Environment(DashboardStore.self) private var dashboard
    var onNavigate: ((AppSection) -> Void)? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        CachedContentView(
            isLoading: dashboard.isLoading,
            hasLoaded: dashboard.hasLoaded,
            loadingTitle: "Loading dashboard…"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let errorMessage = dashboard.errorMessage {
                        InlineErrorBanner(message: errorMessage) {
                            Task { await dashboard.refresh(using: auth) }
                        }
                    }

                    greetingCard

                    LazyVGrid(columns: columns, spacing: 14) {
                        StatCard(
                            title: "Active Projects",
                            icon: "rectangle.split.3x1",
                            value: dashboard.summary?.activeProjects
                        )
                        StatCard(
                            title: "Open Tasks",
                            icon: "checklist",
                            value: dashboard.summary?.openTasks
                        )
                        StatCard(
                            title: "Next 7 Days",
                            icon: "calendar",
                            value: dashboard.summary?.nextSevenDays
                        )
                        StatCard(
                            title: "Unread Reading",
                            icon: "book",
                            value: dashboard.summary?.unreadReading
                        )
                    }

                    quickLinks
                }
                .padding(20)
            }
            .scrollBounceBehavior(.always)
            .refreshable {
                async let dashboardRefresh: Void = dashboard.refresh(using: auth)
                async let notificationRefresh: Void = notifications.refresh(using: auth)
                _ = await (dashboardRefresh, notificationRefresh)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .task(id: auth.user?.id) {
            await dashboard.loadForPresentation(using: auth)
        }
        .task(id: auth.user?.id) {
            await dashboard.listenForRealtimeUpdates(using: auth)
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
                ForEach(Array([AppSection.chat, .board, .docs, .calendar, .reading].enumerated()), id: \.element) { index, section in
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
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: Circle())

            Text(value.map(String.init) ?? "—")
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
