import SwiftUI

/// 登录后的主界面：侧边栏（iPhone 上为列表导航）+ 各模块详情。
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                detail(for: selection ?? .dashboard)
                    .toolbar {
                        if selection == .dashboard {
                            ToolbarItem(placement: .topBarTrailing) {
                                notificationBell
                            }
                        }
                    }
            }
        }
        .task(id: auth.user?.id) {
            notifications.reset()
            await notifications.loadAutomatically(using: auth)
            await notifications.listenForRealtimeEvents(using: auth)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                userHeader
            }

            Section("Overview") {
                ForEach(AppSection.overview) { section in
                    sidebarRow(section)
                }
            }

            Section("Workflow") {
                ForEach(AppSection.workflow) { section in
                    sidebarRow(section)
                }
            }

            Section("System") {
                ForEach(AppSection.system) { section in
                    sidebarRow(section)
                }
            }
        }
        .navigationTitle("Workavera")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                notificationBell
            }
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.icon)
                .foregroundStyle(.primary)
        }
        .tag(section)
    }

    private var userHeader: some View {
        Button {
            selection = .profile
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: auth.avatarURL, name: auth.user?.displayName ?? "?", size: 44)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill((auth.user?.status ?? .offline).color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2.5)
                            )
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.user?.displayName ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text((auth.user?.status ?? .offline).label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var notificationBell: some View {
        NotificationBellButton(unreadCount: notifications.unreadCount) {
            selection = .notifications
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView { selection = $0 }
        case .contacts:
            ContactsView()
        case .reading:
            ReadingView()
        case .board:
            BoardView()
        case .calendar:
            CalendarView()
        case .docs:
            DocsView()
        case .notifications:
            NotificationsView()
        case .profile:
            ProfileView()
        case .settings:
            SettingsView()
        default:
            PlaceholderView(section: section)
        }
    }
}
