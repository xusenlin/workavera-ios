import Foundation

enum MemoryCategory: String, Codable, CaseIterable, Identifiable {
    case preference
    case personal
    case work
    case goal
    case constraint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preference: "Preference"
        case .personal: "Personal"
        case .work: "Work"
        case .goal: "Goal"
        case .constraint: "Constraint"
        }
    }

    var icon: String {
        switch self {
        case .preference: "slider.horizontal.3"
        case .personal: "person"
        case .work: "briefcase"
        case .goal: "target"
        case .constraint: "hand.raised"
        }
    }
}

enum MemoryOrigin: String, Decodable {
    case manual
    case explicit
    case automatic

    var label: String {
        switch self {
        case .manual: "Added manually"
        case .explicit: "Saved by request"
        case .automatic: "Captured automatically"
        }
    }
}

struct SavedChatMemory: Identifiable, Equatable, Decodable {
    let id: String
    let ownerID: String
    var category: MemoryCategory
    var content: String
    var active: Bool
    let origin: MemoryOrigin
    let sourceConversationID: String?
    let sourceMessageID: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, category, content, active, origin, created, updated
        case ownerID = "owner"
        case sourceConversationID = "source_conversation"
        case sourceMessageID = "source_message"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
        category = try container.decode(MemoryCategory.self, forKey: .category)
        content = try container.decode(String.self, forKey: .content)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        origin = try container.decodeIfPresent(MemoryOrigin.self, forKey: .origin) ?? .manual
        sourceConversationID = Self.nonEmpty(
            try container.decodeIfPresent(String.self, forKey: .sourceConversationID)
        )
        sourceMessageID = Self.nonEmpty(
            try container.decodeIfPresent(String.self, forKey: .sourceMessageID)
        )
        createdAt = MemoryDate.parse(
            try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        )
        updatedAt = MemoryDate.parse(
            try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private enum MemoryDate {
    static func parse(_ value: String) -> Date {
        guard !value.isEmpty else { return .distantPast }
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISO = ISO8601DateFormatter()
        standardISO.formatOptions = [.withInternetDateTime]
        let pocketBase = DateFormatter()
        pocketBase.locale = Locale(identifier: "en_US_POSIX")
        pocketBase.calendar = Calendar(identifier: .gregorian)
        pocketBase.timeZone = TimeZone(secondsFromGMT: 0)
        pocketBase.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        return fractionalISO.date(from: value)
            ?? standardISO.date(from: value)
            ?? pocketBase.date(from: value)
            ?? .distantPast
    }
}
