import SwiftUI

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    var color: Color {
        switch self {
        case .none: Color(hex: "#94a3b8")
        case .low: Color(hex: "#64748b")
        case .medium: Color(hex: "#3b82f6")
        case .high: Color(hex: "#f59e0b")
        case .urgent: Color(hex: "#ef4444")
        }
    }
}

enum BoardStateCategory: String, Decodable {
    case pending
    case active
    case completed
}

struct BoardLabel: Identifiable, Equatable {
    let id: String
    let projectID: String
    var name: String
    var color: String
}

struct BoardMember: Identifiable, Equatable {
    let id: String
    var name: String
    var avatarURL: URL?
}

struct BoardState: Identifiable, Equatable {
    let id: String
    let projectID: String
    var name: String
    var color: String
    var category: BoardStateCategory
    var sortOrder: Double
    var tasks: [BoardTask]
}

struct BoardTask: Identifiable, Equatable {
    let id: String
    let projectID: String
    var stateID: String
    var title: String
    var description: String
    var priority: TaskPriority
    var startDate: Date?
    var dueDate: Date?
    var labels: [BoardLabel]
    var assignees: [BoardMember]
    var documentCount: Int
    var rank: Double

    var isOverdue: Bool {
        guard let dueDate else { return false }
        return dueDate < .now
    }

    /// The server rejects a start after the due date, so the form says so
    /// before a save can fail on it. Both dates stay optional.
    static func isValidSpan(start: Date?, due: Date?) -> Bool {
        guard let start, let due else { return true }
        return start <= due
    }

    /// A start and a due date read as one span; either alone reads as a day.
    var dateSpanText: String? {
        let day: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        if let startDate, let dueDate,
           !Calendar.current.isDate(startDate, inSameDayAs: dueDate) {
            return "\(day(startDate)) – \(day(dueDate))"
        }
        return (dueDate ?? startDate).map(day)
    }

    var copyText: String {
        """
        Task ID: \(id)
        Task Name: \(title)
        """
    }
}

struct BoardProject: Identifiable, Equatable {
    let id: String
    let ownerID: String
    var name: String
    var description: String
    var members: [BoardMember]
    var labels: [BoardLabel]
    var states: [BoardState]

    var taskCount: Int {
        states.reduce(0) { $0 + $1.tasks.count }
    }

    var labelCount: Int { labels.count }
}

struct BoardPage: Equatable {
    let projects: [BoardProject]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

/// One archived task, as listed in the Board's archived-tasks sheet. Archived
/// tasks are excluded from `BoardPage`, so they carry only what the list shows.
struct ArchivedBoardTask: Identifiable, Equatable {
    let id: String
    var title: String
    var description: String
    var stateName: String
}

struct ArchivedBoardTaskPage: Equatable {
    let tasks: [ArchivedBoardTask]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

// MARK: - PocketBase records

struct BoardUserRecord: Decodable {
    let id: String
    let collectionId: String
    let name: String
    let email: String
    let avatar: String

    var displayName: String { name.isEmpty ? email : name }

    private enum CodingKeys: String, CodingKey {
        case id, collectionId, name, email, avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    }
}

struct BoardProjectRecord: Decodable {
    struct Expansion: Decodable { let owner: BoardUserRecord? }

    let id: String
    let name: String
    let description: String
    let owner: String
    let archived: Bool
    let expand: Expansion?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, owner, archived, expand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        owner = try container.decode(String.self, forKey: .owner)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        expand = try container.decodeIfPresent(Expansion.self, forKey: .expand)
    }
}

struct BoardProjectPreferenceRecord: Decodable {
    struct Expansion: Decodable { let project: BoardProjectRecord? }

    let id: String
    let project: String
    let sortOrder: Double
    let expand: Expansion?

    private enum CodingKeys: String, CodingKey {
        case id, project, expand
        case sortOrder = "sort_order"
    }
}

struct BoardStateRecord: Decodable {
    let id: String
    let project: String
    let name: String
    let color: String
    let category: BoardStateCategory
    let sortOrder: Double

    private enum CodingKeys: String, CodingKey {
        case id, project, name, color, category
        case sortOrder = "sort_order"
    }
}

struct BoardLabelRecord: Decodable {
    let id: String
    let project: String
    let name: String
    let color: String
}

struct BoardMemberRecord: Decodable {
    struct Expansion: Decodable { let user: BoardUserRecord? }

    let id: String
    let project: String
    let user: String
    let expand: Expansion?
}

struct BoardTaskRecord: Decodable {
    let id: String
    let project: String
    let state: String
    let title: String
    let description: String
    let priority: TaskPriority
    let labelIDs: [String]
    let assigneeIDs: [String]
    let documentIDs: [String]
    let startDate: String
    let dueDate: String
    let rank: Double

    private enum CodingKeys: String, CodingKey {
        case id, project, state, title, description, priority, labels, assignees, documents, rank
        case startDate = "start_date"
        case dueDate = "due_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        project = try container.decode(String.self, forKey: .project)
        state = try container.decode(String.self, forKey: .state)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        labelIDs = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        assigneeIDs = try container.decodeIfPresent([String].self, forKey: .assignees) ?? []
        documentIDs = try container.decodeIfPresent([String].self, forKey: .documents) ?? []
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        rank = try container.decodeIfPresent(Double.self, forKey: .rank) ?? 0
    }
}

struct ArchivedBoardTaskRecord: Decodable {
    struct Expansion: Decodable { let state: BoardStateRecord? }

    let id: String
    let title: String
    let description: String
    let expand: Expansion?

    private enum CodingKeys: String, CodingKey {
        case id, title, description, expand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        expand = try container.decodeIfPresent(Expansion.self, forKey: .expand)
    }
}

struct BoardTaskMoveResponse: Decodable {
    let id: String
    let state: String
    let rank: Double
}

struct BoardTaskPriorityResponse: Decodable {
    let id: String
    let priority: TaskPriority
}

struct BoardTaskDueDateResponse: Decodable {
    let id: String
    let dueDate: String

    private enum CodingKeys: String, CodingKey {
        case id
        case dueDate = "due_date"
    }
}

struct BoardTaskStartDateResponse: Decodable {
    let id: String
    let startDate: String

    private enum CodingKeys: String, CodingKey {
        case id
        case startDate = "start_date"
    }
}

struct BoardTaskArchiveResponse: Decodable {
    let id: String
    let archived: Bool
}

/// A project's public preview link. Unlike a shared document it pins nothing:
/// the link always shows the project as it stands, so there is no revision to
/// republish — only an expiry to set and a link to revoke. A nil `expiresAt`
/// means the link never expires.
struct BoardProjectShare: Equatable, Decodable {
    let projectID: String
    let slug: String
    let expires: String
    let created: String
    let updated: String

    private enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case slug, expires, created, updated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? ""
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        expires = try container.decodeIfPresent(String.self, forKey: .expires) ?? ""
        created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
    }

    var expiresAt: Date? {
        guard !expires.isEmpty else { return nil }
        let parsed = DocsDate.parse(expires)
        return parsed == .distantPast ? nil : parsed
    }
}
