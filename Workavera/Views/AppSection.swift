import SwiftUI

/// All app modules, grouped and ordered to match the Workavera web sidebar:
/// Overview (Dashboard), Workflow (Reading through Calendar), and System (Settings).
/// Notifications lives in the top bar, and Profile opens from the user card.
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

    /// Line-style SF Symbols corresponding to the web app's Hugeicons choices.
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

    /// Module descriptions aligned with the web navigation copy.
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

    /// Parses `workavera://<section>` links, such as the one the agenda widget opens.
    init?(deepLink url: URL) {
        guard url.scheme == "workavera", let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}
