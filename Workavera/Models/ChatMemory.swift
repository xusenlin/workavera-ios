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

/// Parsed view of a `system_memory_upsert` / `system_memory_forget` tool call,
/// taken from either its input (while the call runs) or its output (once it
/// settles). Used by the chat UI to render a purpose-built memory card.
struct MemoryToolPayload: Equatable, Sendable {
    enum Action: String, Sendable {
        case created, updated, unchanged, forgotten, undone
    }

    var action: Action?
    var category: MemoryCategory?
    var content: String?
    var origin: MemoryOrigin?

    init?(input: JSONValue?) {
        guard let object = Self.object(from: input) else { return nil }
        category = object["category"]?.stringValue.flatMap(MemoryCategory.init(rawValue:))
        content = object["content"]?.stringValue
        origin = object["origin"]?.stringValue.flatMap(MemoryOrigin.init(rawValue:))
    }

    init?(output: JSONValue?) {
        guard let object = Self.object(from: output),
              let action = object["action"]?.stringValue.flatMap(Action.init(rawValue:)) else { return nil }
        self.action = action
        let memory = object["memory"]?.objectValue
        category = memory?["category"]?.stringValue.flatMap(MemoryCategory.init(rawValue:))
        content = memory?["content"]?.stringValue
        origin = memory?["origin"]?.stringValue.flatMap(MemoryOrigin.init(rawValue:))
    }

    /// Tool outputs may arrive either as a JSON object or as a string holding
    /// serialized JSON.
    private static func object(from value: JSONValue?) -> [String: JSONValue]? {
        value?.decodingEmbeddedJSON.objectValue
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
