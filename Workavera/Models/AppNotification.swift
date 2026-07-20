import SwiftUI

/// 通知类型（布局阶段自定义，接入 API 后对齐后端通知模型）。
enum AppNotificationType {
    case mention
    case taskAssigned
    case comment
    case dueSoon
    case system

    var icon: String {
        switch self {
        case .mention: "at"
        case .taskAssigned: "checklist"
        case .comment: "text.bubble"
        case .dueSoon: "clock"
        case .system: "bell"
        }
    }

    var color: Color {
        switch self {
        case .mention: Color(hex: "#8b5cf6")
        case .taskAssigned: Color(hex: "#3b82f6")
        case .comment: Color(hex: "#22c55e")
        case .dueSoon: Color(hex: "#f59e0b")
        case .system: Color(hex: "#64748b")
        }
    }
}

/// 一条通知。
struct AppNotification: Identifiable, Equatable {
    let id: String
    var type: AppNotificationType
    var title: String
    var body: String
    var createdAt: Date
    var isRead: Bool
}

// MARK: - 布局示例数据（接入 API 前的占位数据）

extension AppNotification {
    static let sample: [AppNotification] = {
        func minutesAgo(_ value: Int) -> Date {
            Calendar.current.date(byAdding: .minute, value: -value, to: .now) ?? .now
        }

        return [
            AppNotification(
                id: "n1", type: .mention,
                title: "Ada Chen mentioned you",
                body: "@Senlin the board layout looks great, can you review the card spacing?",
                createdAt: minutesAgo(12), isRead: false
            ),
            AppNotification(
                id: "n2", type: .taskAssigned,
                title: "New task assigned",
                body: "Fix avatar flicker on scroll was assigned to you in Workavera iOS App.",
                createdAt: minutesAgo(45), isRead: false
            ),
            AppNotification(
                id: "n3", type: .dueSoon,
                title: "Task due tomorrow",
                body: "Board page layout is due soon. Current status: In Progress.",
                createdAt: minutesAgo(90), isRead: false
            ),
            AppNotification(
                id: "n4", type: .comment,
                title: "New comment",
                body: "Marco Li commented on Dark mode polish: \"Let's align the colors with the web app.\"",
                createdAt: minutesAgo(180), isRead: true
            ),
            AppNotification(
                id: "n5", type: .taskAssigned,
                title: "New task assigned",
                body: "Offline cache for task lists was assigned to you in Workavera iOS App.",
                createdAt: minutesAgo(300), isRead: true
            ),
            AppNotification(
                id: "n6", type: .system,
                title: "Workspace updated",
                body: "Workavera server was updated to the latest version.",
                createdAt: minutesAgo(60 * 8), isRead: true
            ),
            AppNotification(
                id: "n7", type: .comment,
                title: "New comment",
                body: "Yuki Tanaka commented on Define spacing tokens: \"Draft is ready for review.\"",
                createdAt: minutesAgo(60 * 26), isRead: true
            ),
            AppNotification(
                id: "n8", type: .mention,
                title: "Marco Li mentioned you",
                body: "@Senlin can you pick up the crash on iOS 16 login? Two users reported it.",
                createdAt: minutesAgo(60 * 30), isRead: true
            ),
            AppNotification(
                id: "n9", type: .dueSoon,
                title: "Task overdue",
                body: "Crash on iOS 16 login was due 3 days ago in Customer Feedback.",
                createdAt: minutesAgo(60 * 49), isRead: true
            ),
            AppNotification(
                id: "n10", type: .system,
                title: "Weekly summary ready",
                body: "Your activity summary for last week is available.",
                createdAt: minutesAgo(60 * 52), isRead: true
            ),
            AppNotification(
                id: "n11", type: .taskAssigned,
                title: "New task assigned",
                body: "Draft new landing copy was assigned to you in Marketing Site Redesign.",
                createdAt: minutesAgo(60 * 76), isRead: true
            ),
            AppNotification(
                id: "n12", type: .comment,
                title: "New comment",
                body: "Ada Chen commented on Push notification settings: \"Spec attached.\"",
                createdAt: minutesAgo(60 * 100), isRead: true
            ),
            AppNotification(
                id: "n13", type: .system,
                title: "Welcome to Workavera",
                body: "Your workspace is ready. Start by creating your first project.",
                createdAt: minutesAgo(60 * 24 * 7), isRead: true
            ),
        ]
    }()
}
