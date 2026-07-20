import SwiftUI

/// App 的全部模块，分组与顺序和 Workavera Web 版侧边栏保持一致：
/// Overview（Dashboard）/ Workflow（Reading…Calendar）/ System（Settings），
/// Notifications 在顶栏铃铛，Profile 通过用户卡片进入。
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case reading
    case contacts
    case chat
    case board
    case docs
    case calendar
    case notifications
    case settings
    case profile

    var id: String { rawValue }

    static let overview: [AppSection] = [.dashboard]
    static let workflow: [AppSection] = [.reading, .contacts, .chat, .board, .docs, .calendar]
    static let system: [AppSection] = [.settings]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .reading: "Reading"
        case .contacts: "Contacts"
        case .chat: "Chat"
        case .board: "Board"
        case .docs: "Docs"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        case .settings: "Settings"
        case .profile: "Profile"
        }
    }

    /// 线条风格图标，对应 Web 版 Hugeicons 的选型。
    var icon: String {
        switch self {
        case .dashboard: "house"
        case .reading: "book"
        case .contacts: "person.text.rectangle"
        case .chat: "bubble.left"
        case .board: "rectangle.split.3x1"
        case .docs: "doc.text"
        case .calendar: "calendar"
        case .notifications: "bell"
        case .settings: "gearshape"
        case .profile: "person.crop.circle"
        }
    }

    /// 占位页描述文字，与 Web 版导航描述保持一致。
    var placeholderDescription: String {
        switch self {
        case .dashboard:
            "Your personal overview at a glance."
        case .reading:
            "Bookmarks and reading list with tags, read status, and AI summaries."
        case .contacts:
            "Manage clients, partners, and collaborators."
        case .chat:
            "Conversations with your Workavera assistant, with streaming output and tool calls."
        case .board:
            "Manage projects and tasks in a Kanban board with workflows, labels, and due dates."
        case .docs:
            "Create notes, team documents, and public content with versioning and AI editing."
        case .calendar:
            "Schedule and events, merged with visible board deadlines and reminders."
        case .notifications:
            "Task due alerts, calendar reminders, and model share requests."
        case .settings:
            "Manage your preferences and API keys."
        case .profile:
            "Your profile, avatar, and status."
        }
    }
}
