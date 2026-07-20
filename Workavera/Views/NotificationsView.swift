import SwiftUI

/// 通知页面：分组列表 + 下拉刷新 + 底部分页。
/// 当前为示例数据（AppNotification.sample），接入 API 后替换为真实数据。
struct NotificationsView: View {
    @State private var notifications = AppNotification.sample
    @State private var page = 0

    private let pageSize = 8

    private var pageCount: Int {
        max(1, Int(ceil(Double(notifications.count) / Double(pageSize))))
    }

    private var pageNotifications: [AppNotification] {
        Array(notifications.dropFirst(page * pageSize).prefix(pageSize))
    }

    private var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pageNotifications.enumerated()), id: \.element.id) { index, notification in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 62)
                    }
                    row(notification)
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Notifications")
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark All Read") {
                        markAllRead()
                    }
                }
            }
        }
        .refreshable {
            await reload()
        }
        .safeAreaInset(edge: .bottom) {
            if pageCount > 1 {
                VStack(spacing: 0) {
                    Divider()
                    PaginationBar(pageCount: pageCount, page: $page)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func row(_ notification: AppNotification) -> some View {
        Button {
            markRead(notification.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notification.type.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(notification.type.color)
                    .frame(width: 34, height: 34)
                    .background(notification.type.color.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary)
                    Text(notification.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(notification.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                if !notification.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 本地状态操作（接入 API 后改为写后端）

    /// 下拉刷新：模拟网络请求后重建示例数据，保留已读状态。
    private func reload() async {
        try? await Task.sleep(for: .milliseconds(600))
        let readIDs = Set(notifications.filter(\.isRead).map(\.id))
        notifications = AppNotification.sample.map {
            var notification = $0
            notification.isRead = readIDs.contains(notification.id)
            return notification
        }
    }

    private func markRead(_ id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
    }

    private func markAllRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
    }
}
